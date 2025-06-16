### JABAWS 2.2 ###

FROM tomcat:8.5.100-jre8-temurin-jammy

RUN apt-get update && apt-get install -y \
    g++ \
    make \
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

ENV EXEC=http://www.compbio.dundee.ac.uk/jabaws22/archive/docker/Executable.properties
RUN wget $EXEC -O $CATALINA_HOME/webapps/jabaws/conf/Executable.properties

RUN mkdir -p $CATALINA_HOME/webapps/jabaws/jobsout

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/

# compile the binaries
# RUN chmod +x ./compilebin.sh && ./compilebin.sh
RUN echo "Compiling Clustalw…" && cd clustalw && chmod +x ./configure && ./configure && make clean && make && chmod +x src/clustalw2
RUN echo "Compiling Clustal Omega…" && cd clustalo && chmod +x ./configure && ./configure && make clean && make && chmod +x src/clustalo
RUN echo "Compiling Mafft…" && cd mafft/core && make clean && make
RUN echo "Compiling fasta34…" && cd fasta34 && rm -f *.o && make && chmod +x fasta34
RUN echo "Compiling Muscle…" && cd muscle && rm -f *.o muscle && make
RUN echo "Compiling Probcons…" && cd probcons && make clean && make && chmod +x probcons
RUN echo "Compiling T-Coffee…" && cd tcoffee && chmod +x install && ./install clean && ./install t_coffee -force && printf '%s\n' '#!/usr/bin/env bash' 'PDIR=\"$( cd \"$( dirname \"${BASH_SOURCE[0]}\" )\" && pwd )\"' 'export PATH=$PATH:$PDIR' 't_coffee \"$@\"' > t_coffee_source/t_coffee.sh && chmod +x t_coffee_source/t_coffee*
RUN echo "Compiling DisEMBL…" && cd disembl && gcc -O3 disembl.c -o disembl && chmod +x disembl DisEMBL.py
RUN echo "Compiling Tisean…" && cd disembl/Tisean_3.0.1 && chmod +x ./configure && ./configure && make && cp source_c/sav_gol ../ && cd ../.. && chmod +x disembl/sav_gol
RUN echo "Setting up GlobPlot…" && cp disembl/sav_gol globplot/sav_gol && cd globplot && chmod +x GlobPlot.py
RUN echo "Compiling IUPred…" && cd iupred && make clean && make
RUN echo "Compiling ViennaRNA…" && cd ViennaRNA && chmod +x ./configure && ./configure && make clean && make
RUN echo "Compiling GLProbs…" && cd GLProbs-1.0 && make clean && make
RUN echo "Compiling MSAProbs…" && cd MSAProbs-0.9.7/MSAProbs && make clean && make

RUN chmod +x ./setexecflag.sh && ./setexecflag.sh

WORKDIR $CATALINA_HOME

EXPOSE 8080
CMD ["catalina.sh", "run"]
