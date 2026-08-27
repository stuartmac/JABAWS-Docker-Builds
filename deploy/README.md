# Deploying JABAWS with Podman + systemd

`podman-deploy.sh` builds the image on the host and hands the container to
systemd via a [Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
unit. It is written for a fresh RHEL-family or Debian-family host with Podman
4.4+ and no Docker daemon.

```bash
cp deploy/deploy.env.example deploy/deploy.env   # edit for this host
./deploy/podman-deploy.sh --dry-run              # see what it will do
./deploy/podman-deploy.sh
```

Everything site-specific — proxies, ports, unit and volume names, dependency
mirrors — lives in `deploy/deploy.env`, which is gitignored. The script and the
unit template carry no hostnames.

Steps run in order and are individually re-runnable, so you can pick up after a
failure without repeating the 15-minute build:

| Step | Does |
|---|---|
| `preflight` | podman version, free disk, port, SELinux, lingering, unit-name collision |
| `deps` | downloads build dependencies, proxy-aware, skipping any already present |
| `bases` | pulls base images fully qualified and tags them short (for `short-name-mode = enforcing`) |
| `build` | `podman build --pull=never`, detached via `setsid`, logged to `build-logs/` |
| `unit` | renders `jabaws.container.in` into the Quadlet directory and reloads systemd |
| `start` | `systemctl start` |
| `verify` | polls `/jabaws/` then checks two WSDLs and `ServiceStatus` |

```bash
./deploy/podman-deploy.sh unit start verify   # e.g. after editing the template
```

## Building on the host

The script's `deps`, `bases` and `build` steps exist because three things trip up
a from-source build on a locked-down host. If you are running them by hand, these
are the same workarounds.

### Short-name resolution

RHEL sets `short-name-mode = "enforcing"` in `/etc/containers/registries.conf`,
so the Dockerfile's unqualified `FROM ubuntu:22.04`,
`eclipse-temurin:8-jdk-jammy` and `tomcat:9.0.107-jre8-temurin-jammy` prompt for a
registry — which fails outright in a scripted build. Podman's default pull
policy (`missing`) leaves images already in local storage alone, so pulling them
under their fully qualified names and tagging them short is enough; `--pull=never`
then makes a missing base fail immediately rather than at the registry:

```bash
for img in docker.io/library/ubuntu:22.04 \
           docker.io/library/eclipse-temurin:8-jdk-jammy \
           docker.io/library/tomcat:9.0.107-jre8-temurin-jammy; do
  podman pull "$img" && podman tag "$img" "${img#docker.io/library/}"
done
podman build --pull=never -t jabaws:latest .
```

### Behind an HTTP proxy

`prepare_dependencies.sh` downloads with `wget`, which honours `http_proxy` /
`https_proxy` for every source — and **hangs rather than failing** when the proxy
can't reach one. Two sources are worth knowing about: the JABAWS WAR is served
from `www.compbio.dundee.ac.uk`, which some site proxies cannot route to, and
Savannah's gitweb URLs for `config.guess` / `config.sub` are prone to 502s
through a proxy, where the gcc mirror on GitHub serves the same files.

The `deps` step doesn't make you work this out in advance. For each source it
probes the proxy first, falls back to a direct connection, reports which one it
used, and fails loudly if neither works. It also upgrades an `http://` source to
`https://` when the host answers on TLS, and retries three times, since a
transient proxy failure is the normal case on these hosts rather than the
exception. `WAR_NOPROXY=1` remains as an override when you already know the
proxy can't route to the WAR host and want to skip the probe.

To fetch by hand instead, bypassing the proxy only where needed:

```bash
mkdir -p dependencies
curl -fSL --noproxy '*' -o dependencies/jabaws.war \
  http://www.compbio.dundee.ac.uk/jabaws22/archive/jabaws.war
curl -fsSL -o dependencies/Python-2.7.13.tgz \
  https://www.python.org/ftp/python/2.7.13/Python-2.7.13.tgz
curl -fsSL -o dependencies/config.guess \
  https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess
curl -fsSL -o dependencies/config.sub \
  https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.sub
mkdir -p dependencies/jabaws && unzip -q dependencies/jabaws.war -d dependencies/jabaws
```

The build itself needs the proxy too, for `apt-get` in the first stage. Nothing
special is required: `podman build --http-proxy` defaults to true and passes
`http_proxy`, `https_proxy`, `ftp_proxy`, `no_proxy` *and* their uppercase forms
into every `RUN`. Set them however your host normally does; `deploy.env` is the
place to do it per host, along with `NO_PROXY_EXTRA` for hosts that must be
reached directly.

What does bite is a proxy that reaches a repository intermittently — one failed
`apt-get` used to kill a fifteen-minute build at step two. Both apt stages now
set `Acquire::Retries "3"`.

### Dependency integrity

The upstream WAR is 122 MB fetched over plain HTTP, and on a proxied host it
arrives through a middlebox you don't control. `deploy/dependencies.sha256` pins
what each download should be; every fetch is checked against it, and a mismatch
aborts before anything is built. Files already present in `dependencies/` are
verified too, so a corrupted or substituted artefact can't survive into a later
build.

The pins that ship with the repo were established as follows:

| File | Basis |
|---|---|
| `jabaws.war` | two independent downloads eight months apart agree; upstream publishes no checksum or signature of its own |
| `Python-2.7.13.tgz` | matches the MD5 published on python.org for the release |
| `config.guess`, `config.sub` | taken from the immutable `gcc-13.2.0` tag — the copies on `master` change over time and cannot be pinned |

If you point a `*_URL` at a different mirror, re-record and commit the result:

```bash
./deploy/podman-deploy.sh deps checksums
```

A file already in `dependencies/` that fails its pin is refused too, with the
remedy — delete it and re-run to fetch a fresh copy. If the checksum file is
absent entirely the step still runs, but warns on every download that it cannot
verify what arrived.

### Long builds over SSH

Compiling the native tools takes roughly 10–15 minutes on 4 cores, and a dropped
connection takes the build with it. Run it detached (`setsid`, `nohup`, `tmux`)
and log to a timestamped file, so a later attempt doesn't overwrite the record of
a successful one:

```bash
nohup podman build --pull=never -t jabaws:latest . \
  > "build-$(date +%Y%m%d-%H%M%S).log" 2>&1 &
```

Two things in that log look alarming but are not: gfortran emits `Error:` lines
while compiling Tisean (`Nonnegative width required in format string`, `END tag
label 999 at (1) not defined`) without failing the build, and `apt-get` prints
`Ign:` lines for repositories it retries. A successful run ends with
`Successfully tagged`.

## Verifying a deployment

`verify` polls `/jabaws/` until it answers, then checks the rest:

```bash
for p in "" "ClustalWS?wsdl" "MafftWS?wsdl" "ServiceStatus"; do
  printf "%-20s " "/$p"
  curl -sS --noproxy '*' -o /dev/null -w "HTTP %{http_code}\n" \
    "http://localhost:8080/jabaws/$p"
done
```

All four should return 200. `--noproxy` keeps a proxy environment from sending
the localhost request out to the network. The registry warm-up runs in the
background after start, so `ServiceStatus` may show services as untested for the
first few minutes — see [Registry warm-up](../OVERVIEW.md#registry-warm-up).

## Adopting an existing `podman run` deployment

A container started by hand holds the name, the port and the volumes the unit
wants, so systemd cannot simply take over: the two would collide. `preflight`
detects an unmanaged container of the same name and stops rather than fighting
it.

Adoption is a deliberate swap. Point the unit at the volumes that already exist
— podman cannot rename a volume, so if yours were named by hand, set
`LOGS_VOLUME`, `JOBSOUT_VOLUME`, `STATS_VOLUME` and `STATS_BACKUPS_VOLUME` in
`deploy.env` rather than copying data between volumes.

```bash
# 1. What is actually mounted, so deploy.env can match it exactly
podman inspect jabaws --format '{{range .Mounts}}{{.Name}} -> {{.Destination}}
{{end}}'

# 2. A cold copy of the statistics database, before anything is torn down
podman stop jabaws
podman run --rm -v jabaws-stats:/src:Z -v "$PWD:/out:Z" \
  --entrypoint /bin/sh localhost/jabaws:latest \
  -c 'tar czf /out/stats-preadoption.tgz -C /src .'

# 3. Give the running image an immutable tag, so there is something to roll
#    back to. :latest is mutable and will be overwritten by the next build.
podman tag localhost/jabaws:latest localhost/jabaws:$(date -u +%Y%m%d)-adopted

# 4. Release the name and port
podman rm jabaws

# 5. Hand it to systemd, deploying the tag from step 3
IMAGE=localhost/jabaws:$(date -u +%Y%m%d)-adopted \
  ./deploy/podman-deploy.sh preflight unit start verify
```

Nothing is rebuilt: the same image, the same volumes, now under a unit that
survives a reboot and a logout. Once that is serving, `upgrade` builds a fresh
image and swaps onto it with automatic rollback to the adopted tag.

## Upgrading and rolling back

Images are tagged immutably as `<date>-<git sha>` (with `-dirty` when the tree
has uncommitted changes) and labelled with the revision and build time, so a
deployment names one exact build. `:latest` is kept as a convenience alias for
interactive use — nothing systemd reads it. The unit file is the record of
what's deployed, which means `systemctl cat` answers "what is running here?" on
a host with no checkout:

```bash
systemctl --user cat jabaws | grep ^Image=
```

To upgrade:

```bash
./deploy/podman-deploy.sh upgrade
```

That builds a new image, stops the unit, snapshots the statistics database into
the backups volume as `preupgrade-<tag>` (keeping the last two), points the unit
at the new image, starts it, and verifies. **If verification fails it puts the
old image back and re-verifies**, exiting non-zero — a failed upgrade should
leave a serving container, not a broken one. Old images beyond `KEEP_IMAGES`
(default 3) are pruned afterwards, never the deployed or previous one.

There is a short outage, by necessity: Derby holds an exclusive lock on the
statistics volume, so the old and new containers cannot overlap. Expect a few
seconds — Tomcat deploys the unpacked webapp in around four, and the registry
warm-up runs in the background afterwards. If you ever need zero downtime, the
honest route is a second container on another port with no statistics volume,
flipped at the reverse proxy; two containers sharing one Derby database is not
an option.

To roll back — no rebuild, since the images are still there:

```bash
./deploy/podman-deploy.sh rollback                                   # previous
ROLLBACK_TO=localhost/jabaws:20260826-7fc5260 ./deploy/podman-deploy.sh rollback
```

Deployment history is recorded in `${XDG_STATE_HOME:-~/.local/state}/jabaws-deploy/history`
— state, deliberately not in `deploy.env`, which is configuration.

### Health checks

`Restart=always` only notices a process that has exited; a wedged Tomcat looks
healthy to it. The unit therefore carries a Podman health check that asks
whether JABAWS is actually answering:

```ini
HealthCmd=curl -fsS http://localhost:8080/jabaws/ServiceStatus || exit 1
HealthInterval=60s
HealthStartPeriod=120s
HealthOnFailure=restart
```

The image already ships `curl` for the entrypoint's registry warm-up, so this
needs nothing extra. Inspect the current state with
`podman healthcheck run jabaws` or `podman inspect jabaws --format '{{.State.Health.Status}}'`.

## Does Quadlet clash with existing systemd-managed containers?

No. Quadlet is a systemd *generator*: at each `daemon-reload` it reads
`*.container` files from `~/.config/containers/systemd` (rootless) or
`/etc/containers/systemd` (system) and writes ordinary `.service` units into
`/run/systemd/generator`. Those services sit alongside hand-written units and
alongside anything produced by the older `podman generate systemd`. Nothing
existing is read, rewritten, or taken over, and the two styles can run side by
side on the same host indefinitely.

Four things to know before mixing them:

- **Unit names must not collide.** `jabaws.container` generates
  `jabaws.service`. A hand-written `/etc/systemd/system/jabaws.service` takes
  precedence over generator output, so it would silently shadow the Quadlet unit
  — you would edit the `.container` file and see nothing change. `preflight`
  checks for this and refuses to continue; set `UNIT_NAME` if it fires. The same
  applies to units from `podman generate systemd`, which conventionally uses
  `container-<name>.service`.
- **Manage Quadlet containers with `systemctl`, not `podman`.** A `podman stop`
  looks like a failure to systemd, which restarts the container straight back.
  There is also nothing to `systemctl enable`: generated units cannot be enabled,
  and the `[Install] WantedBy=` line in the template is what Quadlet uses to wire
  it into boot.
- **Rootless still needs lingering.** Without
  `loginctl enable-linger <user>`, the user manager stops at logout and takes the
  container with it, and nothing starts at boot. Quadlet does not change that;
  `preflight` warns if it is off.
- **`podman-restart.service` is unrelated.** It only restarts containers created
  with `--restart`. Quadlet containers are restarted by systemd's own
  `Restart=always`, so leave that service to whatever it was already doing.

Migrating an existing deployment is optional and can be done one container at a
time: stop and disable the old unit, drop in a `.container` file with a different
name, `daemon-reload`, start. [`podlet`](https://github.com/containers/podlet)
converts an existing `podman run` command or generated unit into Quadlet syntax
if you would rather not write it by hand. Verify what the generator produced
with:

```bash
/usr/libexec/podman/quadlet -dryrun -user      # drop -user for system scope
systemctl --user cat jabaws.service
```

## Deploying a second instance on one host

Set `UNIT_NAME`, `CONTAINER_NAME`, `HOST_PORT` and `VOLUME_PREFIX` to distinct
values in a second env file, then point the script at it:

```bash
./deploy/podman-deploy.sh --env deploy/deploy.staging.env
```

Note the statistics database takes an exclusive Derby lock, so two containers
must not share a `VOLUME_PREFIX`.
