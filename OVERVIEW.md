# JABAWS: Bioinformatics Web Services for Alignment and Analysis

JABAWS is a suite of bioinformatics web services for multiple sequence alignment, protein disorder prediction, and conservation analysis — packaged in a Docker image for easy deployment on your computer, server, or cluster.

The JABAWS Docker image is ideal if you need to:

- Run jobs that exceed public server limits
- Work with sensitive data under strict security policies
- Operate in offline or restricted environments

This resource was developed by the [Dundee Resource for Sequence Analysis and Structure Prediction](https://www.compbio.dundee.ac.uk/drsasp.html). For more information or to use the public JABAWS server, visit the [JABAWS web server](https://www.compbio.dundee.ac.uk/jabaws/).

## Contents

- [🚀 Quick Start](#-quick-start)
- [Run a Persistent Instance](#run-a-persistent-instance)
- [Access the Services](#access-the-services)
- [Use with Jalview 2.11](#use-with-jalview-211)
- [Services Provided](#services-provided)
- [🔍 Monitor Logs](#-monitor-logs)
- [📁 Retrieve Job Outputs](#-retrieve-job-outputs)
- [Volume Management](#volume-management)
- [🔨 Building the Image](#-building-the-image)
- [🔄 Moving to Slivka](#-moving-to-slivka)
- [Funding](#funding)

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

### Registry warm-up

Jalview discovers services by calling `RegistryWS.getSupportedServices()`, and it
skips any service missing from that list. The registry only populates the list
after it has successfully self-tested — and it builds the URLs it tests from the
request's `Host` header. Published on a non-matching port (`-p 18080:8080`), that
becomes `http://localhost:18080/...`, which nothing serves *inside* the
container, so every self-test fails and the list stays empty. Jalview then finds
**zero services and reports no error**, because an empty list isn't a failure.

The entrypoint (`jabaws-entrypoint.sh`) works around this by calling
`testAllServices` once from inside the container, where the advertised and
listening ports agree. The registry's cache is global, so clients on any mapped
port see the full list afterwards.

It runs in the background — Tomcat serves requests within seconds of start,
and the registry fills in once the sweep finishes. Watch it with:

```bash
docker logs -f <container> 2>&1 | grep jabaws-warmup
```

The sweep genuinely runs every tool. To skip it, set `JABAWS_WARMUP=0` — but
note that Jalview will then discover nothing until `testAllServices` is called
by hand. Timeouts are tunable via `JABAWS_WARMUP_READY_TIMEOUT` (default 300s)
and `JABAWS_WARMUP_TEST_TIMEOUT` (default 900s).

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

## 🔨 Building the Image

Most users should pull the published image. If you build it yourself, note that
the native tools (T-Coffee, MAFFT, MUSCLE, …) are compiled from source during the
build, for whatever architecture you build on. Building on the machine you intend
to deploy to therefore gives you natively compiled binaries, with no cross-build
or emulation involved.

```bash
docker build -t jabaws:local .
```

The Dockerfile offers two runtime variants as build targets:

| Target | Size | Notes |
| --- | --- | --- |
| `exploded` (default) | ~772 MB | Webapp unpacked at build time. Faster startup, and the only variant that supports mounting a volume at `jobsout`. |
| `packed` | ~608 MB | Ships the WAR; Tomcat unpacks it on first boot. Smaller to store and pull. |

```bash
# Smaller image, no jobsout volume
docker build --target packed -t jabaws:slim .
```

> ⚠️ **The `packed` variant cannot be used with a `jobsout` volume.** Mounting
> anything under `/usr/local/tomcat/webapps/jabaws/` creates that directory before
> Tomcat starts, so Tomcat treats it as an already-deployed application and never
> unpacks the WAR — the service returns 404. Use `packed` only without the
> `jobsout` mount shown in [Run a Persistent Instance](#run-a-persistent-instance);
> otherwise stay on the default.

To get a shell with the tool sources *and* a full compiler toolchain — useful when
experimenting with compilation flags — build the first stage on its own:

```bash
docker build --target tool-builder -t jabaws-tools .
```

---

## 🔄 Moving to Slivka

From Jalview 2.12 onward, JABAWS will be replaced by [Slivka](https://www.compbio.dundee.ac.uk/slivka/) — a modern framework for providing bioinformatics tools as web services.

- If you're using JABAWS with Jalview 2.11 or earlier, the instructions above apply.
- If you're deploying new services or need programmatic access (e.g. Jupyter notebooks), we recommend using Slivka.

➡️ [See the Slivka Docker setup](https://hub.docker.com/repository/docker/stuartmac/slivka-bio/general)

## Funding

This work is part of the [BBSRC](https://www.ukri.org/councils/bbsrc/) funded [Dundee Resource for Protein Structure Prediction and Sequence Analysis](https://www.compbio.dundee.ac.uk/drsasp.html) grant number [208391/Z/17/Z](https://gow.bbsrc.ukri.org/grants/AwardDetails.aspx?FundingReference=BB%2fR014752%2f1).
