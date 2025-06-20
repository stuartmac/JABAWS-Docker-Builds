### JABAWS 2.2 ###

FROM tomcat:8.5.100-jre8-temurin-jammy

RUN apt-get update && apt-get install -y \
    g++ \
    make \
    # build-essential \
    gfortran \
    libargtable2-dev \
    unzip \
    libperl5.34 \
    perl-modules-5.34 \
    wget

RUN wget --no-check-certificate https://www.python.org/ftp/python/2.7.13/Python-2.7.13.tgz && \
  tar -xzf Python-2.7.13.tgz && cd Python-2.7.13 && ./configure && make && make install

ENV WAR=http://www.compbio.dundee.ac.uk/jabaws22/archive/jabaws.war
RUN wget $WAR -O /tmp/jabaws.war && \
    mkdir -p $CATALINA_HOME/webapps/jabaws && \
    unzip /tmp/jabaws.war -d $CATALINA_HOME/webapps/jabaws && \
    rm /tmp/jabaws.war

COPY Executable.properties $CATALINA_HOME/webapps/jabaws/conf/Executable.properties

RUN mkdir -p $CATALINA_HOME/webapps/jabaws/jobsout

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/

# compile the binaries
# RUN chmod +x ./compilebin.sh && ./compilebin.sh
# update config scripts and compile both ClustalW & Clustal Omega
RUN for pkg in clustalw clustalo ViennaRNA; do \
      echo "Compiling $pkg…"; \
      cd $pkg; \
      # grab modern config scripts
      wget -qO config.guess 'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess'; \
      wget -qO config.sub   'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub'; \
      chmod +x config.* configure; \
      # explicitly set build triplet
      ./configure --build=$(uname -m)-linux-gnu; \
      make clean && make; \
      # glob to capture clustalw2 and clustalo
      chmod +x src/*; \
      cd ..; \
    done

RUN echo "Compiling Mafft…" \
  && cd mafft/core \
  && make clean \
  && make CFLAGS="-Denablemultithread -O3 -std=c99 -fcommon"

RUN echo "Compiling fasta34…" && cd fasta34 && rm -f *.o && make && chmod +x fasta34

RUN echo "Compiling Muscle…" \
  && cd muscle \
  && chmod +x mk \
  # remove interactive‐TTY & unsupported SSE flags  
  && sed -i 's|/dev/tty|/dev/null|g' mk \
  # remove unsupported SSE flags, if we need similar optimizations on a non-x86 platform we could swap them for a generic tuning flag (e.g. -march=native)
  && sed -i -E 's/-msse2//g; s/-mfpmath=sse//g' mk \
  # run headless build  
  && yes '' | ./mk \
  # use g++ (links libstdc++ & libm) instead of gcc
  && g++ -O3 *.o -o muscle -lm \
  && chmod +x muscle

RUN echo "Compiling Probcons…" && cd probcons && make clean && make && chmod +x probcons


RUN echo "Compiling T-Coffee…" && cd tcoffee \
  && find . -type f \( -name '*.o' -o -name '*.deps' -o -name '*.d' -o -name '*.depend' \) -delete \
  && chmod +x install \
  && ./install clean \
  && sed -i -E "s|CFLAGS=-O3 -Wno-write-strings|CFLAGS=-g -O0 -fno-strict-aliasing -Wall -Wno-write-strings -std=c++98|" \
    t_coffee_source/makefile \
  && ./install t_coffee -force \
  && printf '%s\n' '#!/usr/bin/env bash' \
    'PDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"' \
    'export PATH="$PATH:$PDIR"' \
    't_coffee "$@"' > t_coffee_source/t_coffee.sh \
  && chmod +x t_coffee_source/t_coffee*

RUN echo "Compiling DisEMBL…" \
  && cd disembl \
  && gcc -O3 disembl.c -o disembl \
  # fix shebang to env python
  && sed -i '1s|.*|#!/usr/bin/env python|' DisEMBL.py \
  && chmod +x disembl DisEMBL.py

RUN echo "Compiling Tisean…" && cd disembl/Tisean_3.0.1 && chmod +x ./configure && ./configure && make && cp source_c/sav_gol ../ && cd ../.. && chmod +x disembl/sav_gol
RUN echo "Setting up GlobPlot…" && cp disembl/sav_gol globplot/sav_gol && cd globplot && chmod +x GlobPlot.py
RUN echo "Compiling IUPred…" && cd iupred && make clean && make
RUN echo "Compiling GLProbs…" && cd GLProbs-1.0 && make clean && make
RUN echo "Compiling MSAProbs…" && cd MSAProbs-0.9.7/MSAProbs && make clean && make

# RUN chmod +x ./setexecflag.sh && ./setexecflag.sh

WORKDIR $CATALINA_HOME

EXPOSE 8080
CMD ["catalina.sh", "run"]
