# JABAWS: Bioinformatics Web Services for Alignment and Analysis

JABAWS provides a suite of bioinformatics web services for multiple sequence alignment, protein disorder prediction, and conservation analysis — packaged for convenient deployment on your local computer, server, or cluster.

This resource was developed by the [Dundee Resource for Sequence Analysis and Structure Prediction](https://www.compbio.dundee.ac.uk/drsasp.html). For more information or to use the public JABAWS server, visit the [JABAWS web server](https://www.compbio.dundee.ac.uk/jabaws/).


## 🚀 Quick Start

Ensure Docker is installed on your system. If needed, refer to the [Docker install docs](https://docs.docker.com/get-started/get-docker/).


### Run a Disposable Instance

To quickly try JABAWS without saving any data or configuration, use the following command:

```bash
docker run --rm -p 8080:8080 drsasp/jabaws:latest
```

This will start the JABAWS web server and expose it at `http://localhost:8080`. The container and any changes made within it will be discarded once it stops.

### Run a Persistent Instance

To keep the container running in the background and retain data or logs, first create the necessary directories on your host:

```bash
mkdir -p ./logs ./jobsout
```

Then start the container with volume mounts:

```bash
docker run -d \
  -p 8080:8080 \
  -v "$(pwd)/logs:/usr/local/tomcat/logs" \
  -v "$(pwd)/jobsout:/usr/local/tomcat/webapps/jabaws/jobsout" \
  --name jabaws-server \
  drsasp/jabaws:latest
```

You can stop it with:

```bash
docker stop jabaws-server
```

And start it again with:

```bash
docker start jabaws-server
```

This setup keeps logs and job output on your host. For example, you can check logs with:

```bash
tail -f ./logs/catalina.out
```

And list completed job outputs:

```bash
ls -la ./jobsout/
```

This method is recommended for regular use or deployment on a server.


## Access the Services

Once started, JABAWS services will be available at:

**URL**: http://localhost:8080/jabaws/

Open `http://localhost:8080/jabaws/ServiceStatus` in your web browser to see the service list and status. Services are accessible via [Jalview](https://www.jalview.org) or the [JABAWS CLI](https://www.compbio.dundee.ac.uk/jabaws/getting_started.jsp#client).



## Use with Jalview 2.11

To enable Jalview to use your local JABAWS instance:

- In Jalview, open **Preferences → Web Services**, and add your server’s JABAWS URL (e.g., `http://localhost:8080/jabaws/`)
- Run the tools via the Jalview **Web Services** menu.


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


## Use Cases

The JABAWS Docker Image is ideal for users needing to:

- Run jobs that exceed our public server limits
- Adhere to strict data policies when working with sensitive data
- Work offline


## Slivka

From Jalview 2.12, JABAWS web services will be replaced by [Slivka](https://www.compbio.dundee.ac.uk/slivka/). Please see our [slivka-bio Docker repository](https://hub.docker.com/repository/docker/stuartmac/slivka-bio/general) for setup and configuration instructions.

Users looking to host bioinformatics web services for programmatic access only (e.g. via Jupyter Notebooks) are recommended to use Slivka.


## Funding

This work is part of the [BBSRC](https://www.ukri.org/councils/bbsrc/) funded [Dundee Resource for Protein Structure Prediction and Sequence Analysis](https://www.compbio.dundee.ac.uk/drsasp.html) grant number [208391/Z/17/Z](https://gow.bbsrc.ukri.org/grants/AwardDetails.aspx?FundingReference=BB%2fR014752%2f1).
