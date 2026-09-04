################################################################################
# JABAWS 2.2 — multi‑stage Docker build with Tomcat 9
#
# Stage layout
# ─────────────
# 0. tomcat-base    – the Tomcat image, named once so war-patcher can borrow its
#                     servlet-api.jar and runtime can build on the same version
# 1. tool-builder   – build every native binary (clustal*, mafft, etc.)
# 2. war-patcher    – unpack WAR, drop in patched config + binaries, re‑jar
#                     (also the --target for extract-patched-war.sh)
# 3. runtime        – Tomcat 9.0.107 with Java 8 (JABAWS compatibility),
#                     webapp unpacked at build time
################################################################################

############################
# Stage 0 – Tomcat base
############################
# Named rather than repeated: war-patcher compiles against this image's
# servlet-api.jar and the runtime stage is built from it, so a Tomcat bump is a
# one-line change and the two can never drift apart.
FROM tomcat:9.0.107-jre8-temurin-jammy AS tomcat-base

############################
# Stage 1 – build native tools
############################
FROM ubuntu:22.04 AS tool-builder

# A flaky or restricted proxy is the normal case on a locked-down build host, and
# a transient repository failure otherwise kills a 15-minute build at step two.
RUN echo 'Acquire::Retries "3";' > /etc/apt/apt.conf.d/80-retries

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
# Upstream logs engine.log and JABAWSErrorFile.log through plain FileAppenders,
# which never roll; this copy makes them RollingFileAppenders so a long-lived
# container cannot fill the logs volume. See log4j.properties for the details.
COPY log4j.properties WEB-INF/classes/log4j.properties

# 2a) Compile the nightly statistics-backup listener into the webapp
#
# The statistics database is embedded Derby, so the Tomcat JVM holds an
# exclusive lock on it and no external process can dump it while the container
# runs. StatsBackup.java runs inside that JVM and calls Derby's own online
# backup on a schedule; see its header comment for the full rationale, and
# OVERVIEW.md for the environment variables that configure it.
#
# servlet-api.jar is compile-time only (Tomcat provides it at runtime), which is
# why it is borrowed from tomcat-base rather than added to WEB-INF/lib.
COPY --from=tomcat-base /usr/local/tomcat/lib/servlet-api.jar /tmp/servlet-api.jar
COPY StatsBackup.java /tmp/StatsBackup.java
RUN javac -cp /tmp/servlet-api.jar -d WEB-INF/classes /tmp/StatsBackup.java \
 && test -f WEB-INF/classes/jabaws/docker/StatsBackup.class

# 2b) Register the listener. As with the server.xml edits in the runtime stage,
# the grep guard is the point: if upstream ever renames that comment the sed
# matches nothing, and a failed build beats an image whose backups silently
# never run.
COPY stats-backup-listener.xml /tmp/stats-backup-listener.xml
RUN sed -i '/<!-- JABAWS listeners -->/r /tmp/stats-backup-listener.xml' WEB-INF/web.xml \
 && grep -q jabaws.docker.StatsBackup WEB-INF/web.xml \
 && rm /tmp/stats-backup-listener.xml /tmp/StatsBackup.java /tmp/servlet-api.jar

# 2c) Restore the site content the public server actually serves.
#
# dependencies/jabaws.war is the August 2017 release, but www.compbio.dundee.ac.uk
# had later edits applied on top that were never rolled back into a WAR. The
# JABAWS 2.2 paper is cited here as "in preparation"; it was published in
# Bioinformatics in 2018 (doi:10.1093/bioinformatics/bty045). Without this the
# container front page advertises a citation that has been wrong for years.
# The footer date lives in template_footer.jsp, which every page includes.
#
# site-content/ holds these two files copied verbatim from the live server
# (gjb-www-4:.../tomcat-8.5.11_jaba-2.2prod/webapps/jabaws/, both dated
# 27 March 2018), so this is the production content itself rather than a
# reconstruction. A sweep of that webapp on 2026-09-03 confirmed these are the
# only two content files that differ from the WAR - about.jsp, download.jsp,
# getting_started.jsp, template_header.jsp and every docs/ page are identical.
#
# Whole-file forks rather than sed edits, because the change is structural: the
# 2018 reference is prepended and the superseded one removed. The sha256 guards
# are the point - if the WAR is ever bumped, the build fails here rather than
# silently reverting whatever content the new release ships.
COPY site-content/index.jsp           /tmp/site-index.jsp
COPY site-content/template_footer.jsp /tmp/site-template_footer.jsp
RUN printf '%s  %s\n' \
      07bfee60eaa99bb82ae83c76427d2211e02c64b01d71dbd3d30543d393ac4544 index.jsp \
      aad5ef12962c799550fe90a51c521d8fd542cd53886ba99f0a6113872e47b3ae template_footer.jsp \
    | sha256sum -c - \
 && mv /tmp/site-index.jsp           index.jsp \
 && mv /tmp/site-template_footer.jsp template_footer.jsp \
 && grep -q 'bioinformatics/bty045' index.jsp \
 && grep -q '27 March 2018'         template_footer.jsp

# 3) Inject freshly‑built binaries into the WAR root so they unpack to /binaries/*
COPY --from=tool-builder /build ./binaries/src

# 3a) Microoptimise final image size by removing source files
RUN find binaries/src -type f \( \
      -name '*.c' -o -name '*.cpp' -o -name '*.cc' \
      -o -name '*.h' -o -name '*.hpp' \
      -o -name '*.f' -o -name '*.f90' -o -name '*.for' \
      -o -name '*.inc' \) -delete \
      && find binaries/src -type f -name '*.o' -delete

# 4) Re‑assemble the patched WAR (there's no META-INF/MANIFEST.MF in the original WAR,
#    so we don't need to re‑sign it)
RUN jar cf /tmp/jabaws-patched.war -C . .

############################
# Stage 3 - slim Tomcat runtime
############################
FROM tomcat-base AS runtime

# ---- bring in the runtime libs the native tools need (and Python 2) ----
# curl is used by the entrypoint to warm the service registry on boot.
RUN echo 'Acquire::Retries "3";' > /etc/apt/apt.conf.d/80-retries \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      libargtable2-0 \
      libgomp1 \
      python2 \
      curl \
      && ln -s /usr/bin/python2 /usr/local/bin/python \
 && rm -rf /var/lib/apt/lists/*

# ---- reverse-proxy awareness + access log retention ----
# Insert RemoteIpValve into the stock server.xml rather than vendoring the whole
# file, which would have to be re-reconciled on every Tomcat bump. It goes just
# inside <Host>, ahead of the AccessLogValve declared there.
#
# The AccessLogValve edit carries two unrelated attributes:
#
#   requestAttributesEnabled="true" is not optional for the proxy case. Tomcat
#   invokes the access log after the pipeline unwinds, by which point
#   RemoteIpValve has restored the original remote address, so AccessLogValve
#   would keep logging the proxy; the valve publishes the forwarded values as
#   request attributes instead, and this is what makes AccessLogValve read them.
#
#   maxDays="30" bounds retention. The valve already rolls the access log daily,
#   but its default maxDays of -1 keeps every one of those files forever, so on
#   a busy server it is the fastest-growing thing in the logs volume. The two
#   log4j files are capped separately, in log4j.properties. Tomcat's own juli
#   logs need nothing here -- the stock logging.properties already sets
#   maxDays = 90 on all four handlers.
#
# The grep guards are the point of this construct: if a future base image
# reformats either line the sed silently matches nothing, and a build that
# fails is better than an image that quietly ships without proxy support or
# without log retention.
COPY tomcat-remoteip-valve.xml /tmp/remoteip-valve.xml
RUN sed -i \
      -e '/unpackWARs="true" autoDeploy="true">/r /tmp/remoteip-valve.xml' \
      -e 's|<Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"|<Valve className="org.apache.catalina.valves.AccessLogValve" requestAttributesEnabled="true" maxDays="30" directory="logs"|' \
      /usr/local/tomcat/conf/server.xml \
 && grep -q RemoteIpValve /usr/local/tomcat/conf/server.xml \
 && grep -q requestAttributesEnabled /usr/local/tomcat/conf/server.xml \
 && grep -q 'maxDays="30"' /usr/local/tomcat/conf/server.xml \
 && rm /tmp/remoteip-valve.xml

# The webapp is unpacked at build time rather than shipped as a WAR for Tomcat
# to explode on first boot. A WAR looks smaller (609 MB vs 772 MB on disk) but
# isn't: it pulls the same (201 MB vs 200 MB compressed -- a deflated jar can't
# gzip again, while the unpacked tree can), and Tomcat then re-expands it into
# every container's writable layer at boot, which measured 271 MB. Unpacking
# here keeps that in a shared image layer and boots faster.
#
# It is also what makes the VOLUMEs below possible. Mounting anything under
# webapps/jabaws/ pre-creates that directory with an mtime newer than the WAR,
# and HostConfig then treats it as an already-deployed app and never unpacks --
# so a WAR-based image serves 404 the moment you mount jobsout.
#
# `extract-patched-war.sh` still produces a standalone WAR via --target
# war-patcher, for deployment into an existing Tomcat.
COPY --from=war-patcher /work /usr/local/tomcat/webapps/jabaws

# Ensure jobsout exists at build time so the volume mounts onto a populated tree
RUN mkdir -p /usr/local/tomcat/webapps/jabaws/jobsout

# Default destination for the nightly statistics backup (JABAWS_STATS_BACKUP_DIR
# overrides it). Created here so a bind mount lands on an existing directory.
# Left undeclared as a VOLUME for the same reason ExecutionStatistic is: an
# anonymous volume per run would be worse than writing to the container layer,
# which is where nightly snapshots go, capped at JABAWS_STATS_BACKUP_KEEP, if
# nobody mounts anything.
RUN mkdir -p /usr/local/tomcat/stats-backups

VOLUME ["/usr/local/tomcat/logs"]
VOLUME ["/usr/local/tomcat/webapps/jabaws/jobsout"]

# webapps/jabaws/ExecutionStatistic -- the embedded Derby DB behind the
# statistics pages -- is deliberately NOT declared here. It ships populated in
# the image and is optional to persist; declaring it would force an anonymous
# volume on every run for something most deployments don't need. Mount it
# explicitly to keep usage history across upgrades (see OVERVIEW.md).

# RegistryWS derives the URLs it self-tests from the request's Host header, so
# behind `-p <other>:8080` it tries to reach itself on a port that does not
# exist inside the container, every test fails, and getSupportedServices()
# returns an empty set -- which makes Jalview discover zero services with no
# error. The entrypoint calls testAllServices once from inside, where the ports
# agree, which populates the registry's global cache. See jabaws-entrypoint.sh.
COPY jabaws-entrypoint.sh /usr/local/bin/jabaws-entrypoint.sh
RUN chmod +x /usr/local/bin/jabaws-entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/jabaws-entrypoint.sh"]
CMD ["catalina.sh", "run"]
