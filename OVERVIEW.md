# JABAWS: Bioinformatics Web Services for Alignment and Analysis

JABAWS is a suite of bioinformatics web services for multiple sequence alignment, protein disorder prediction, and conservation analysis — packaged in a Docker image for easy deployment on your computer, server, or cluster.

The JABAWS Docker image is ideal if you need to:

- Run jobs that exceed public server limits
- Work with sensitive data under strict security policies
- Operate in offline or restricted environments

## Contents

- [Quick Start](#-quick-start)
- [Run a Persistent Instance](#run-a-persistent-instance)
- [Access the Services](#access-the-services)
- [Use with Jalview 2.11](#use-with-jalview-211)
- [Services Provided](#services-provided)
- [🔍 Monitor Logs](#-monitor-logs)
- [📁 Retrieve Job Outputs](#-retrieve-job-outputs)
- [Volume Management](#volume-management)
- [🔄 Moving to Slivka](#-moving-to-slivka)
- [Funding](#funding)

This resource was developed by the [Dundee Resource for Sequence Analysis and Structure Prediction](https://www.compbio.dundee.ac.uk/drsasp.html). For more information or to use the public JABAWS server, visit the [JABAWS web server](https://www.compbio.dundee.ac.uk/jabaws/).

## 🚀 Quick Start

Ensure Docker is installed on your system. If needed, refer to the [Docker install docs](https://docs.docker.com/get-started/get-docker/).

### Run a Disposable Instance

To quickly try JABAWS without saving any data or configuration, use the following command:

```bash
docker run --rm -p 8080:8080 drsasp/jabaws:latest
```

This will start the JABAWS web server and expose it at `http://localhost:8080/jabaws`. The container and any changes made within it will be discarded once it stops.

## Run a Persistent Instance

Choose one of the following:

#### 🔒 Option A: Docker-managed volumes (recommended)

```bash
docker run -d \
  -p 8080:8080 \
  -v jabaws-logs:/usr/local/tomcat/logs \
  -v jabaws-jobsout:/usr/local/tomcat/webapps/jabaws/jobsout \
  --name jabaws-server \
  drsasp/jabaws:latest
```

#### 💻 Option B: Bind mounts for local file access

```bash
mkdir -p ./logs ./jobsout
docker run -d \
  -p 8080:8080 \
  -v "$(pwd)/logs:/usr/local/tomcat/logs" \
  -v "$(pwd)/jobsout:/usr/local/tomcat/webapps/jabaws/jobsout" \
  --name jabaws-server \
  drsasp/jabaws:latest
```

To stop and restart the container:

```bash
docker stop jabaws-server
docker start jabaws-server
```

These methods are recommended for regular use or deployment on a server.

## Access the Services

Once started, JABAWS services will be available at:

**URL**: http://localhost:8080/jabaws/

Open `http://localhost:8080/jabaws/ServiceStatus` in your web browser to see the service list and status. Services are accessible via [Jalview](https://www.jalview.org) or the [JABAWS CLI](https://www.compbio.dundee.ac.uk/jabaws/getting_started.jsp#client).

## Use with Jalview 2.11

To enable Jalview to use your local JABAWS instance:

- In Jalview, open **Preferences → Web Services**, and add your server’s JABAWS URL (e.g., `http://localhost:8080/jabaws/`)
- Run the tools via the Jalview **Web Services** menu.

---

## Services Provided

**Multiple Sequence Alignment**

- Clustal Omega
- Clustal W
- MAFFT
- MUSCLE
- T-Coffee
- ProbCons
- MSAProbs
- GLProbs

**Disorder Prediction**

- DisEMBL
- IUPred
- Jronn
- GlobPlot

**Conservation Analysis**

- [AACon (v1.1)](https://www.compbio.dundee.ac.uk/aacon/)

**RNA Structure Prediction**

- RNAalifold (from the Vienna RNA package)

---

### 🔍 Monitor Logs

```bash
# Follow Tomcat stdout/stderr (catalina.out)
docker logs -f jabaws-server
```

Other log files can be tailed similarly:

```bash
# View the latest Tomcat access log
docker exec jabaws-server tail -f /usr/local/tomcat/logs/localhost_access_log.$(date +%F).txt

# Tail all .log and .txt files in the logs directory
docker exec -it jabaws-server bash -c 'tail -n 20 -f /usr/local/tomcat/logs/*.log /usr/local/tomcat/logs/*.txt'
```

### 📁 Retrieve Job Outputs

```bash
# List job-output files inside the container
docker exec jabaws-server ls -la /usr/local/tomcat/webapps/jabaws/jobsout/
```

```bash
# Copy job-output directory to your host
docker cp jabaws-server:/usr/local/tomcat/webapps/jabaws/jobsout ./local-jobsout
```

> Use these commands whether you launched JABAWS with *Docker-managed volumes* or *bind mounts*.

---

## Volume Management

If you're using Docker-managed volumes (recommended Option A), here are some helpful commands:

```bash
# List volumes
docker volume ls
```

To back up volumes:

```bash
# Backup logs volume
docker run --rm -v jabaws-logs:/source -v $(pwd):/backup alpine \
  tar czf /backup/jabaws-logs-backup.tar.gz -C /source .

# Backup job outputs volume
docker run --rm -v jabaws-jobsout:/source -v $(pwd):/backup alpine \
  tar czf /backup/jabaws-jobsout-backup.tar.gz -C /source .
```

---

## 🔄 Moving to Slivka

From Jalview 2.12 onward, JABAWS will be replaced by [Slivka](https://www.compbio.dundee.ac.uk/slivka/) — a modern framework for providing bioinformatics tools as web services.

- If you're using JABAWS with Jalview 2.11 or earlier, the instructions above apply.
- If you're deploying new services or need programmatic access (e.g. Jupyter notebooks), we recommend using Slivka.

➡️ [See the Slivka Docker setup](https://hub.docker.com/repository/docker/stuartmac/slivka-bio/general)

## Funding

This work is part of the [BBSRC](https://www.ukri.org/councils/bbsrc/) funded [Dundee Resource for Protein Structure Prediction and Sequence Analysis](https://www.compbio.dundee.ac.uk/drsasp.html) grant number [208391/Z/17/Z](https://gow.bbsrc.ukri.org/grants/AwardDetails.aspx?FundingReference=BB%2fR014752%2f1).
