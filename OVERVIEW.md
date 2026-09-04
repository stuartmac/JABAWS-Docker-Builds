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
- [🦭 Running with Podman](#-running-with-podman)
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

### 🦭 Running with Podman

Podman runs this image unchanged — substitute `podman` for `docker` above. Two
differences matter on a server:

**SELinux.** On a host with SELinux enforcing, bind mounts need a relabel flag or
the container can't write to them; named volumes are relabelled automatically.

```bash
podman run -d --name jabaws-server -p 8080:8080 \
  -v "$(pwd)/logs:/usr/local/tomcat/logs:Z" \
  drsasp/jabaws:latest
```

`:Z` relabels the directory exclusively to that container, so don't use it on a
directory shared with anything else.

**Nothing restarts a bare `podman run -d`.** A rootless container is torn down
when the user's last login session ends unless lingering is enabled
(`loginctl enable-linger <user>`), and nothing starts it again after a reboot.
`--restart=always` doesn't close the gap either: it needs `podman-restart.service`
to survive a reboot, and deliberately won't restart a container after an explicit
`podman stop`. On Podman 4.4+ hand the container to systemd with a Quadlet unit —
[`deploy/`](deploy/README.md) has a template and a script that installs it.

Rootless can't bind ports below 1024 without `net.ipv4.ip_unprivileged_port_start`;
publish a high port and put a reverse proxy in front instead.

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

### Running behind a reverse proxy

The image configures Tomcat's `RemoteIpValve`, so a proxy in front of the
container only has to send the usual headers — `X-Forwarded-For`,
`X-Forwarded-Proto`, `X-Forwarded-Host`, `X-Forwarded-Port`. Tomcat then
rewrites each request's client IP, scheme, host and port to the external values
before the webapp sees them, which matters because JABAWS derives the service
URLs it publishes (and self-tests) from the request. Without it, a container
behind `https://jabaws.example.org` advertises `http://localhost:8080/...`.

Access logs record the forwarded client rather than the proxy.

Nothing is required to turn this on, and nothing changes when the headers are
absent — a direct `-p 8080:8080` run behaves exactly as before. In particular
this is **not** a substitute for the registry warm-up above: a plain port
remapping with no proxy in front sends no `X-Forwarded-*` headers at all.

`RemoteIpValve` only honours those headers from a trusted peer, and its default
trust list is the RFC1918 and loopback ranges. That covers the Docker bridge and
compose networks. A proxy reaching the container from a public address needs an
explicit `internalProxies` (or `trustedProxies`) regex added to
`tomcat-remoteip-valve.xml`, followed by a rebuild.

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

### Logs are always on a volume

The image declares `VOLUME ["/usr/local/tomcat/logs"]`, so log files never live in
the container's writable layer. If you don't pass `-v`, Docker creates an
*anonymous* volume instead — which is left behind every time you `docker rm` the
container. On a server, always name it as Option A does.

This matters because JABAWS logs to files, not to stdout. Its log4j configuration
writes to `${catalina.base}/logs/engine.log` and
`${catalina.base}/logs/JABAWSErrorFile.log`, so `docker logs` shows you Tomcat's
console output and nothing else — `engine.log` is where a failed alignment job
explains itself. See [🔍 Monitor Logs](#-monitor-logs) for how to read them.

#### Rotation and retention

Everything in the logs volume is capped, so the image needs no external
retention job. Four producers write there, and each is bounded differently:

| File | Rolls | Retention | Configured in |
|---|---|---|---|
| `engine.log` | at 10 MB | 5 backups (60 MB) | [`log4j.properties`](log4j.properties) |
| `JABAWSErrorFile.log` | at 10 MB | 5 backups (60 MB) | [`log4j.properties`](log4j.properties) |
| `localhost_access_log.<date>.txt` | daily | 30 days | `maxDays` on the valve, [`Dockerfile`](Dockerfile) |
| `catalina.`/`localhost.`/`manager.`/`host-manager.<date>.log` | daily | 90 days | stock Tomcat `conf/logging.properties` |

Upstream JABAWS ships the two log4j files as plain `FileAppender`s that never
roll; this image replaces them with `RollingFileAppender`s, which is why
`log4j.properties` is vendored at the repo root and copied over the WAR's copy
at build time. Rotation happens in-process — log4j renames and reopens the file
itself — so no sidecar, cron job or `logrotate` is involved, and there is no
`copytruncate` hazard from JABAWS holding the descriptor open.

Upstream also leaves log4j additivity on for the `compbio` logger, which sends
every engine message to both appenders; `engine.log` and `JABAWSErrorFile.log`
came out byte-identical. This image sets `log4j.additivity.compbio=false`, so
`engine.log` holds the engine's output and `JABAWSErrorFile.log` holds errors
from everything else.

To change any of the ceilings, edit `log4j.properties` (log4j files) or the
`maxDays` attribute in the `sed` block of the `Dockerfile` (access log) and
rebuild — appender config is read once at webapp start. For a quick change
without a rebuild, bind-mount your own `log4j.properties` over
`/usr/local/tomcat/webapps/jabaws/WEB-INF/classes/log4j.properties` and restart.

Note that `docker logs` output is separate: that is Tomcat's console stream,
held by the Docker log driver, and it is bounded by the daemon's settings
(`--log-opt max-size` / `max-file`), not by anything in the image.

### Execution statistics (Derby)

JABAWS records job statistics — the ones behind `/jabaws/PublicAnnualStat`, and
the admin-authenticated `/jabaws/DisplayStat`, `/jabaws/AnnualStat` and
`/jabaws/Joblist` — in an embedded Apache Derby database at
`/usr/local/tomcat/webapps/jabaws/ExecutionStatistic`. That database ships
inside the image, so by default every rebuild or image update resets the
statistics to the copy baked into the WAR.

Nothing breaks if you leave it unmounted; you simply lose usage history across
upgrades. Mount it if that history matters:

```bash
docker run -d \
  -p 8080:8080 \
  -v jabaws-logs:/usr/local/tomcat/logs \
  -v jabaws-jobsout:/usr/local/tomcat/webapps/jabaws/jobsout \
  -v jabaws-stats:/usr/local/tomcat/webapps/jabaws/ExecutionStatistic \
  -v jabaws-stats-backups:/usr/local/tomcat/stats-backups \
  --name jabaws-server \
  drsasp/jabaws:latest
```

The fourth volume is where the [nightly backup](#nightly-backup) lands.

Persisting `jobsout` is not a substitute: job directories are pruned after a week
(`local.jobdir.maxlifespan=168` hours), so the Derby database is the only
long-term record.

Two constraints apply to this mount specifically:

- **Local disk only — not NFS or CIFS.** Embedded Derby depends on real file
  locking; a network mount risks corruption rather than a clean error.
- **One container per volume.** Derby takes an exclusive lock, so a second
  container sharing the volume will fail to open the database.

A *named* volume is populated from the image the first time it's used, so the
command above starts from the shipped database and keeps accumulating from there.
A **bind mount is not** — it presents Derby with an empty directory. If you prefer
Option B's bind mounts, seed the host directory first:

```bash
docker run --rm -e JABAWS_WARMUP=0 -v "$(pwd)/stats:/target" drsasp/jabaws:latest cp -a /usr/local/tomcat/webapps/jabaws/ExecutionStatistic/. /target/
```

To snapshot the volume itself, alongside the others:

```bash
# Backup statistics volume
docker run --rm -v jabaws-stats:/source -v $(pwd):/backup alpine \
  tar czf /backup/jabaws-stats-backup.tar.gz -C /source .
```

> Run that one with the container **stopped**. Copying a Derby database while
> it's being written to can capture an inconsistent snapshot. The nightly
> backup below has no such requirement — prefer it for routine backups, and
> keep this recipe for one-off snapshots of a container you're about to upgrade.

#### Nightly backup

The image backs the statistics database up on its own every night — no host
cron, no sidecar, nothing to install. A listener compiled into the webapp
([`StatsBackup.java`](StatsBackup.java)) calls Derby's
`SYSCS_UTIL.SYSCS_BACKUP_DATABASE` on the live database and then exports
`exec_stat` to CSV.

Going through the JVM is what makes this possible while the server runs.
Embedded Derby gives the Tomcat JVM an exclusive lock, so no external process —
not `ij`, not `docker exec` — can open the database at all, and a plain file
copy taken underneath a live writer may not be recoverable. A backup requested
from inside the process that already holds the database open is quiesced and
checkpointed first, so it is consistent by construction and needs no downtime:
measured at ~0.2 s for a 3.7 MB database, with the service answering throughout.

Each run writes one timestamped directory:

```
/usr/local/tomcat/stats-backups/20260806-031500/
├── ExecutionStatistic/   # complete Derby database, restorable as-is
└── exec_stat.csv         # every row, comma-separated, strings quoted
```

Keep both: the Derby copy is what you restore, and the CSV is what stays
readable years later when no compatible Derby is to hand.

| Variable | Default | Effect |
|---|---|---|
| `JABAWS_STATS_BACKUP` | `1` | `0` disables the schedule entirely |
| `JABAWS_STATS_BACKUP_DIR` | `/usr/local/tomcat/stats-backups` | destination root |
| `JABAWS_STATS_BACKUP_AT` | `03:15` | `HH:MM`, container-local time |
| `JABAWS_STATS_BACKUP_KEEP` | `7` | snapshots kept; older ones pruned after each successful run |

Two things to know about those defaults. The container clock is **UTC** unless
you pass `-e TZ=Europe/London`, so `03:15` means 03:15 UTC out of the box. And
the default destination is inside the container, which means snapshots die with
`docker rm` — mount `/usr/local/tomcat/stats-backups` (as the run command above
does) if the backups are meant to outlive the container.

Pruning only ever deletes directories whose names match the `YYYYMMDD-HHMMSS`
pattern, so the destination is safe to share with other files.

Progress and failures go to `logs/localhost.<date>.log` in the logs volume —
`ServletContext.log`, not `docker logs`:

```bash
docker exec jabaws-server grep stats-backup /usr/local/tomcat/logs/localhost.$(date +%Y-%m-%d).log
```

A failed run logs the exception and leaves the schedule intact, so a transient
problem costs one night rather than every night after it.

#### Restoring

Restoring *does* need the container stopped, since Derby holds the live database
open:

```bash
docker stop jabaws-server
docker run --rm \
  -v jabaws-stats:/db \
  -v jabaws-stats-backups:/backups \
  alpine sh -c 'rm -rf /db/* && cp -a /backups/20260806-031500/ExecutionStatistic/. /db/'
docker start jabaws-server
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

The image ships the webapp already unpacked (~772 MB) rather than as a WAR for
Tomcat to expand on first boot. Shipping the WAR produces a smaller image on disk
(~609 MB) but no smaller a download — a deflated jar can't be compressed again,
so both pull at ~200 MB — and Tomcat then re-expands it into every container's
writable layer at startup, measured at 271 MB per container. Unpacking at build
time keeps that in a shared image layer, starts faster, and is what allows
volumes to be mounted under `webapps/jabaws/`.

The build scripts use whichever engine they find, preferring Podman; set
`CONTAINER_ENGINE` to choose. Only `multi-platform-build.sh` is Docker-specific,
since it builds a multi-arch manifest with Buildx. On a host that builds for
itself — the usual case for Podman — that script isn't needed at all.

For a host build behind a proxy or with short-name resolution enforced, see
[deploy/README.md](deploy/README.md), which also scripts the whole thing.

If you want a standalone WAR to deploy into an existing Tomcat, use
`extract-patched-war.sh`, which builds the `war-patcher` stage and copies the
patched WAR out.

### Site content

`dependencies/jabaws.war` is the August 2017 JABAWS 2.2 release, but the public
server at www.compbio.dundee.ac.uk had two page edits applied on top in March 2018
that were never rolled back into a WAR: `index.jsp` cites the JABAWS 2.2 paper as
"Paper in preparation" when it was published in *Bioinformatics*
([doi:10.1093/bioinformatics/bty045](https://doi.org/10.1093/bioinformatics/bty045)),
and the footer date in `template_footer.jsp` (which every page includes) still
reads August 2017.

Both files are vendored in [`site-content/`](site-content/) and copied over the
unpacked WAR by the `war-patcher` stage, so a built image serves the same pages
as the public server. The step is guarded by the sha256 of each upstream file it
replaces: if the WAR is ever updated, the build fails there rather than silently
reverting newer content. Should that happen, re-check the two files against the
new release and update the checksums in the `Dockerfile`.

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
