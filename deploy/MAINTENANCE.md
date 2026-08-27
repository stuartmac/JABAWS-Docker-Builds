# Maintaining a JABAWS deployment

Day-to-day operation of a container already running under systemd. For first-time
setup, see [README.md](README.md).

Throughout, `systemctl --user` assumes `QUADLET_SCOPE=user`; drop `--user` for a
system-scope unit. Volume names follow the defaults (`jabaws-logs`,
`jabaws-jobsout`, `jabaws-stats`, `jabaws-stats-backups`) — substitute your own
if `deploy.env` overrides them.

## Is it healthy?

```bash
systemctl --user status jabaws                              # unit state
podman inspect jabaws --format '{{.State.Health.Status}}'   # is it *serving*?
systemctl --user cat jabaws | grep ^Image=                  # what is deployed
curl -sS --noproxy '*' -o /dev/null -w '%{http_code}\n' http://localhost:8080/jabaws/
```

`healthy` is the answer you want from the second one. `starting` is normal for
the first two minutes after a restart; an empty result or `<no value>` means the
health check isn't configured on this unit at all.

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

## When something is wrong

**JABAWS logs to files, not to stdout.** `podman logs` shows Tomcat's console
output and nothing else, so a failed alignment job leaves no trace there. The
engine's own log is inside the logs volume:

```bash
podman exec jabaws tail -50 /usr/local/tomcat/logs/engine.log
podman exec jabaws tail -50 /usr/local/tomcat/logs/JABAWSErrorFile.log
```

| Symptom | Look here |
|---|---|
| A job fails or returns nothing | the job's own directory — see [Inspecting a job](#inspecting-a-job) |
| Service missing from Jalview | registry warm-up; `podman logs jabaws \| grep jabaws-warmup` |
| Container restarts in a loop | `systemctl --user status jabaws`, then `podman logs jabaws` |
| Health check flapping | `podman healthcheck run jabaws` runs it once, in the foreground |
| Nightly backup didn't run | `podman exec jabaws grep stats-backup /usr/local/tomcat/logs/localhost.$(date +%Y-%m-%d).log` |

Everything in the logs volume is capped and rotated in-process — see
[Rotation and retention](../OVERVIEW.md#rotation-and-retention). No `logrotate`
entry is needed and adding one risks a `copytruncate` conflict with log4j.

## Inspecting a job

Every request leaves a directory under the `jobsout` volume named
`<Service>#<jobid>`, and it holds everything needed to reproduce the run. This
is the first place to look when a job fails or returns something unexpected —
before the logs, because it is per-job rather than per-server.

```bash
# most recent jobs
podman exec jabaws sh -c 'ls -1t /usr/local/tomcat/webapps/jabaws/jobsout | head'

# everything about one of them
podman exec jabaws sh -c 'cd /usr/local/tomcat/webapps/jabaws/jobsout/ClustalO#67218589855079 && ls -la && echo --- && cat procInput.txt'
```

| File | Is |
|---|---|
| `procInput.txt` | **the exact command line that ran** — the most useful file here |
| `input.txt` | the sequences submitted |
| `RunnerConfig.xml` | the parameters the client asked for |
| `STARTED`, `FINISHED` | epoch milliseconds; the difference is the runtime |
| `COLLECTED` | empty marker: the client fetched the result |
| `result.txt` | the output, for services that produce one |
| `stat.txt`, `stat.log` | the tool's own timing and statistics |
| `error.txt` *or* `procError.txt` | the tool's stderr — which name depends on the service |

`procInput.txt` is what makes a failure reproducible: copy the command, run it
inside the container against the same `input.txt`, and you are testing the tool
rather than the web service.

```bash
podman exec -it jabaws bash
cd /usr/local/tomcat/webapps/jabaws/jobsout/<Service>#<jobid>
cat procInput.txt          # then run that command by hand
```

### Two things that look like failures and are not

**A non-empty stderr file usually means nothing.** These tools narrate to stderr.
Mafft writes `nthread = 0 / stacksize: 8192 kb / Gap Penalty = -1.53` into
`error.txt` on a completely successful run. Of the jobs in a healthy sample here,
24 of 60 had a non-empty stderr file and every one of them had produced correct
output. Judge the result, not the noise.

**A missing `result.txt` is not necessarily a failure either.** Output filenames
are per-service: IUPred writes `out.short`, `out.long` and `out.glob` and no
`result.txt` at all; RNAalifold adds `alirna.ps`; ClustalW writes `input.dnd`
and `input.clustalw`. Check what that service is supposed to produce before
concluding anything.

Note also that stderr lands in `error.txt` for some services (Mafft, T-Coffee,
Probcons, MSAprobs, GLprobs, RNAalifold, DisEMBL, GlobPlot) and `procError.txt`
for others (Clustal W/O, MUSCLE, AACon, Jronn, IUPred). Look for both.

### What a real failure looks like

- **No `FINISHED`** — the process never completed. Compare `STARTED` against the
  clock; a job still running is normal, a job from yesterday is not.
- **`FINISHED` present, no output file, and a stderr file containing an actual
  diagnostic** — a missing shared library, a permission error, or the tool
  refusing its input.
- **Job directory absent entirely** — job directories are pruned after 168 hours
  (`local.jobdir.maxlifespan`), so anything older than a week is simply gone.
  Nothing is wrong; there is just nothing left to inspect.

For failures that never reached a tool at all — a rejected request, a service
that would not start — the job directory will be missing or near-empty, and
`engine.log` is the place to look instead.

## The statistics database

Derby is the only long-term record of usage: `jobsout` is pruned after a week, so
job directories are not a substitute. Two mechanisms protect it.

**Nightly, automatically.** A listener in the webapp backs the live database up
at 03:15 **container-local time — UTC unless you pass `TZ`** — keeping seven
snapshots. Confirm they are actually landing:

```bash
podman run --rm -v jabaws-stats-backups:/d:Z --entrypoint /bin/sh \
  localhost/jabaws:latest -c 'ls -1 /d'
```

Expect a `YYYYMMDD-HHMMSS` directory per night. A gap means the container was
down at that hour.

**Before each upgrade.** `upgrade` takes a cold copy while the container is
stopped, named `preupgrade-<tag>`, keeping the last two. The nightly pruner
ignores those, since it only deletes names matching its own timestamp pattern.

### Restore drill

Worth rehearsing before you need it. Derby holds an exclusive lock, so the
container must be stopped — and stopped through systemd, or it will be restarted
underneath you:

```bash
systemctl --user stop jabaws

podman run --rm -v jabaws-stats:/db:Z -v jabaws-stats-backups:/backups:Z \
  --entrypoint /bin/sh localhost/jabaws:latest \
  -c 'rm -rf /db/* && cp -a /backups/20260827-031500/ExecutionStatistic/. /db/'

systemctl --user start jabaws
podman inspect jabaws --format '{{.State.Health.Status}}'
```

Note this uses the JABAWS image itself rather than `alpine`, as the recipes in
OVERVIEW.md do. On a host with `short-name-mode = "enforcing"` an unqualified
`alpine` will not resolve; use `docker.io/library/alpine` there, or the image you
already have.

Each backup directory also holds `exec_stat.csv`. Keep both: the Derby copy is
what you restore, the CSV is what stays readable in ten years when no compatible
Derby is to hand.

## Disk

Four things grow. Two are bounded by the image itself, one is bounded by
configuration, and one is not bounded at all.

| What | Bounded? | Action |
|---|---|---|
| Logs volume | Yes — rotation and retention are configured in the image | none |
| `jobsout` volume | Yes — job directories are pruned after 168 hours | none |
| Images | Partly | `KEEP_IMAGES` (default 3) prunes old builds after an upgrade |
| Untagged build stages | **No** | `podman image prune -f`, or `PRUNE_DANGLING=1` |

The untagged images are the ones that bite. Each multi-stage build leaves its
intermediate stages behind at roughly 1–2 GB apiece, and after a few builds they
outweigh everything retention is carefully managing. They are also the layer
cache, so pruning them means the next build recompiles every native tool from
scratch — the full 10–15 minutes rather than a partial rebuild. That trade is
why it is opt-in:

```bash
podman system df                    # what is actually reclaimable
podman image prune -f               # reclaim it, at the cost of build cache
```

On a build host, prune by hand every few upgrades. On a host that only ever
receives images, set `PRUNE_DANGLING=1` and forget about it.

## After a host reboot

```bash
loginctl show-user "$USER" --property=Linger   # must be yes for a rootless unit
systemctl --user is-active jabaws
podman inspect jabaws --format '{{.State.Health.Status}}'
```

If the unit is not running and lingering says `no`, that is the whole
explanation: the user manager never started, so nothing it owns did either. Fix
it once, as root, with `loginctl enable-linger <user>`.

Allow a few minutes after any start before judging Jalview service discovery —
the registry warm-up runs every tool once in the background, and until it
finishes `ServiceStatus` reports services as untested.

## Routine

| When | Do |
|---|---|
| After every upgrade | check health status; confirm a `preupgrade-*` snapshot was written |
| Weekly | confirm last night's backup landed; check free disk |
| Every few upgrades | `podman image prune -f` on a build host |
| Occasionally | rehearse the restore drill on a non-production host |
| After a reboot | the three checks above |
