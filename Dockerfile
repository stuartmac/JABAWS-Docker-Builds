### JABAWS 2.2 ###

FROM tomcat:8.5.100-jre8-temurin-jammy

RUN apt-get update; apt-get -y install g++ && apt-get -y install make && \
  apt-get -y install libargtable2-dev && apt-get -y install gfortran && \
  apt-get -y install unzip

RUN wget --no-check-certificate https://www.python.org/ftp/python/2.7.13/Python-2.7.13.tgz && \
  tar -xzf Python-2.7.13.tgz && cd Python-2.7.13 && ./configure && make && make install

ENV WAR http://www.compbio.dundee.ac.uk/jabaws22/archive/jabaws.war
RUN wget $WAR -O /tmp/jabaws.war && \
    mkdir -p $CATALINA_HOME/webapps/jabaws && \
    unzip /tmp/jabaws.war -d $CATALINA_HOME/webapps/jabaws && \
    rm /tmp/jabaws.war

ENV EXEC http://www.compbio.dundee.ac.uk/jabaws22/archive/docker/Executable.properties
RUN wget $EXEC -O $CATALINA_HOME/webapps/jabaws/conf/Executable.properties

RUN mkdir -p $CATALINA_HOME/webapps/jabaws/jobsout

WORKDIR $CATALINA_HOME/webapps/jabaws/binaries/src/

# compile the binaries
RUN chmod +x ./compilebin.sh && ./compilebin.sh
RUN chmod +x ./setexecflag.sh && ./setexecflag.sh

WORKDIR $CATALINA_HOME

EXPOSE 8080
CMD ["catalina.sh", "run"]
