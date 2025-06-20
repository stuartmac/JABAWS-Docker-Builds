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

COPY dependencies/Python-2.7.13.tgz /tmp/Python-2.7.13.tgz
RUN tar -xzf /tmp/Python-2.7.13.tgz && cd Python-2.7.13 && ./configure && make && make install

COPY dependencies/jabaws.war /tmp/jabaws.war
RUN mkdir -p $CATALINA_HOME/webapps/jabaws && \
    unzip /tmp/jabaws.war -d $CATALINA_HOME/webapps/jabaws && \
    rm /tmp/jabaws.war

COPY Executable.properties $CATALINA_HOME/webapps/jabaws/conf/Executable.properties

RUN mkdir -p $CATALINA_HOME/webapps/jabaws/jobsout

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/

# compile the binaries
# RUN chmod +x ./compilebin.sh && ./compilebin.sh
# update config scripts and compile both ClustalW & Clustal Omega
COPY dependencies/config.* ./
RUN for pkg in clustalw clustalo ViennaRNA; do \
      echo "Compiling $pkg…"; \
      cd $pkg; \
      cp ../config.guess ../config.sub ./; \
      chmod +x config.* configure; \
      # explicitly set build triplet
      ./configure --build=$(uname -m)-linux-gnu; \
      make clean && make; \
      # glob to capture clustalw2 and clustalo
      chmod +x src/*; \
      cd ..; \
    done

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/mafft/core/
RUN echo "Compiling Mafft…" \
  && make clean \
  && make CFLAGS="-Denablemultithread -O3 -std=c99 -fcommon"

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/fasta34
RUN echo "Compiling fasta34…" && rm -f *.o && make && chmod +x fasta34

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/muscle
COPY tool-config/muscle-mk ./mk
RUN echo "Compiling Muscle…" \
  && chmod +x mk \
  # run headless build  
  && yes '' | ./mk \
  # use g++ (links libstdc++ & libm) instead of gcc
  && g++ -O3 *.o -o muscle -lm \
  && chmod +x muscle

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/probcons
RUN echo "Compiling Probcons…" && make clean && make && chmod +x probcons

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/tcoffee
RUN echo "Compiling T-Coffee…" \
  && find . -type f \( -name '*.o' -o -name '*.deps' \) -delete \
  && chmod +x install \
  && ./install clean \
  && sed -i -E "s|CFLAGS=-O3 -Wno-write-strings|CFLAGS=-g -O0 -fno-strict-aliasing -Wall -Wno-write-strings -std=c++98|" \
    t_coffee_source/makefile \
  && ./install t_coffee -force \
  && chmod +x t_coffee_source/t_coffee*
COPY jabaws-config/t_coffee.sh t_coffee_source/

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/disembl
RUN echo "Compiling DisEMBL…" \
  && gcc -O3 disembl.c -o disembl \
  # fix shebang to env python
  && sed -i '1s|.*|#!/usr/bin/env python|' DisEMBL.py \
  && chmod +x disembl DisEMBL.py

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/disembl/Tisean_3.0.1
RUN echo "Compiling Tisean…" && chmod +x ./configure && ./configure && make && cp source_c/sav_gol ../ && cd ../.. && chmod +x disembl/sav_gol

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/globplot
RUN echo "Setting up GlobPlot…" && cp ../disembl/sav_gol ./sav_gol && chmod +x GlobPlot.py

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/iupred
RUN echo "Compiling IUPred…" && make clean && make

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/GLProbs-1.0
RUN echo "Compiling GLProbs…" && make clean && make

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/MSAProbs-0.9.7/MSAProbs
RUN echo "Compiling MSAProbs…" && make clean && make

# RUN chmod +x ./setexecflag.sh && ./setexecflag.sh

WORKDIR /usr/local/tomcat

# Clean up build resources
RUN apt-get purge -y --auto-remove \
    g++ \
    make \
    unzip \
    wget \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 8080
CMD ["catalina.sh", "run"]
