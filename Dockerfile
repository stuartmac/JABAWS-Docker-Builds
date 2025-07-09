################################################################################
# JABAWS 2.2 — multi‑stage Docker build with Tomcat 9
#
# Stage layout
# ─────────────
# 1. tool-builder   – build every native binary (clustal*, mafft, etc.)
# 2. war-patcher    – unpack WAR, drop in patched config + binaries, re‑jar
# 3. runtime        – Tomcat 9.0.107 with Java 8 (JABAWS compatibility)
################################################################################

############################
# Stage 1 – build native tools
############################
FROM ubuntu:22.04 AS tool-builder

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential \
        gfortran \
        libargtable2-dev \
        wget \
        unzip \
        make \
        perl \
        autoconf

WORKDIR /build

# ----------------------------------------------------------------------------- 
# Copy source tree + helper patches exactly as in the original Dockerfile
# -----------------------------------------------------------------------------
# tool sources
COPY dependencies/jabaws/binaries/src/         ./
# updated GNU config.*
COPY dependencies/config.*                     ./
COPY tool-config/muscle-mk                     muscle/mk
COPY tool-config/tcoffee-makefile              tcoffee/t_coffee_source/makefile
COPY jabaws-config/t_coffee.sh                 tcoffee/t_coffee_source/

# remove any object/lib files that shipped inside the WAR so every tool is rebuilt for the target architecture
RUN find . -type f \( -name '*.o' -o -name '*.a' -o -name '*.so' -o -name '*.deps' \) -delete

# ----------------------------------------------------------------------------- 
# Compile everything (updated: copy patched config.* into each package so
# cross‑platform triples like aarch64‑linux‑gnu are recognized)
# -----------------------------------------------------------------------------
RUN for pkg in clustalw clustalo ViennaRNA; do \
        if [ -d "$pkg" ]; then \
          echo "Compiling $pkg"; \
          cd "$pkg" && \
          # copy modern autoconf helpers into the package *and* any nested sub‑dirs
          cp ../config.guess ../config.sub ./ && \
          find . -name config.guess -exec cp ../config.guess {} \; && \
          find . -name config.sub   -exec cp ../config.sub   {} \; && \
          chmod +x config.* configure && \
          if [ "$pkg" = "ViennaRNA" ]; then \
            ./configure --build="$(uname -m)-linux-gnu" --without-forester && \
            make clean && make CFLAGS="-fcommon" -j"$(nproc)"; \
          else \
            ./configure --build="$(uname -m)-linux-gnu" && \
            make clean && make -j"$(nproc)"; \
          fi && \
          cd ..; \
        else \
          echo "WARNING: source directory [$pkg] not found – skipping"; \
        fi; \
    done && \
    echo "Compiling Mafft"  && make -C mafft/core clean && make -C mafft/core -j"$(nproc)" CFLAGS="-Denablemultithread -O3 -std=c99 -fcommon" && \
    echo "Compiling fasta34"&& make -C fasta34 clean && make -C fasta34 -j"$(nproc)" && \
    echo "Compiling Muscle" && \
      ( cd muscle && \
        chmod +x mk && \
        yes '' | ./mk && \
        g++ -O3 *.o -o muscle -lm && \
        chmod +x muscle ); \
    echo "Compiling Probcons"&& make -C probcons clean && make -C probcons -j"$(nproc)" && \
    echo "Compiling T‑Coffee"&& (cd tcoffee && \
                                  find . -type f \( -name '*.o' -o -name '*.deps' \) -delete && \
                                  chmod +x install && \
                                  ./install clean && \
                                  ./install t_coffee -force) && \
    echo "Compiling DisEMBL" && gcc -O3 disembl/disembl.c -o disembl/disembl && \
                               sed -i '1s|.*|#!/usr/bin/env python|' disembl/DisEMBL.py && \
    echo "Compiling Tisean"  && (cd disembl/Tisean_3.0.1 && chmod +x configure && ./configure && make clean && make) && \
                               cp disembl/Tisean_3.0.1/source_c/sav_gol disembl/ && \
    echo "Compiling GlobPlot"&& cp disembl/sav_gol globplot/ && chmod +x globplot/GlobPlot.py && \
    echo "Compiling IUPred"  && make -C iupred clean && make -C iupred -j"$(nproc)" && \
    echo "Compiling GLProbs" && make -C GLProbs-1.0 clean && make -C GLProbs-1.0 -j"$(nproc)" && \
    echo "Compiling MSAProbs"&& make -C MSAProbs-0.9.7/MSAProbs clean && make -C MSAProbs-0.9.7/MSAProbs -j"$(nproc)"

# ----------------------------------------------------------------------------- 
# Collect the finished executables into /dist (preserving relative paths)
# -----------------------------------------------------------------------------
RUN mkdir /dist && \
    find . -type f -perm -111 -exec cp --parents {} /dist \;

############################
# Stage 2 – patch & re‑package the WAR
############################
FROM eclipse-temurin:8-jdk-jammy AS war-patcher

WORKDIR /work

# 1) Unpack the vanilla WAR
COPY dependencies/jabaws.war /tmp/
RUN jar xf /tmp/jabaws.war

# 2) Overwrite configuration as required
COPY Executable.properties conf/Executable.properties

# 3) Inject freshly‑built binaries into the WAR root so they unpack to /binaries/*
COPY --from=tool-builder /build ./binaries/src

# 3a) Microoptimise final image size by removing source files
RUN find binaries/src -type f \( \
      -name '*.c'   -o -name '*.cpp' -o -name '*.cc' \
      -o -name '*.h' -o -name '*.hpp' \
      -o -name '*.f' -o -name '*.f90' -o -name '*.for' \
      -o -name '*.inc' \) -delete \
      && find binaries/src -type f -name '*.o' -delete

# 4) Re‑assemble the patched WAR (there's no META-INF/MANIFEST.MF in the original WAR,
#    so we don't need to re‑sign it)
RUN jar cf /tmp/jabaws-patched.war -C . .

############################
# Stage 3 – slim Tomcat runtime
############################
FROM tomcat:9.0.107-jre8-temurin-jammy

# ---- bring in the runtime libs the native tools need (and Python 2) ----
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libargtable2-0 \
      libgomp1 \
      python2 \
      && ln -s /usr/bin/python2 /usr/local/bin/python \
 && rm -rf /var/lib/apt/lists/*

# ── Choose ONE of the two COPY lines below ─────────────────────────
# a) Fastest runtime startup (exploded directory, larger image):
# COPY --from=war-patcher /work /usr/local/tomcat/webapps/jabaws

# b) Smaller image (Tomcat explodes WAR on first boot):
COPY --from=war-patcher /tmp/jabaws-patched.war /usr/local/tomcat/webapps/jabaws.war

# Prevent double scanning if both WAR and exploded dir ever co‑exist
ENV CATALINA_OPTS="-Dtomcat.util.scan.StandardJarScanFilter.jarsToSkip=jabaws.war"

EXPOSE 8080
CMD ["catalina.sh", "run"]
