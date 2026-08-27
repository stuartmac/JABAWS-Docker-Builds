#!/bin/bash
################################################################################
# JABAWS Podman deployment helper
#
# Builds the image on the host and installs it as a systemd-managed (Quadlet)
# container. Every site-specific value comes from deploy/deploy.env, which is
# gitignored — see deploy/deploy.env.example.
#
# Usage:
#   ./deploy/podman-deploy.sh [OPTIONS] [STEP ...]
#
# Steps (default: all of them, in this order):
#   preflight    check podman, disk, port, SELinux, unit-name collisions
#   deps         download build dependencies (proxy-aware)
#   bases        pre-pull base images fully qualified and tag them short
#   build        podman build, logged to a timestamped file
#   unit         install and reload the Quadlet unit
#   start        start the unit via systemctl
#   verify       smoke-test the endpoints
#
#   checksums    record dependency checksums (not part of the default run)
#
# Lifecycle steps (not part of the default run):
#   upgrade      build a new image, swap the unit onto it, verify, and roll
#                back automatically if it does not come up
#   rollback     put the previous image back (ROLLBACK_TO=<ref> to choose one)
#
# Options:
#   -h, --help       show this help
#   -f, --env FILE   env file to source (default: deploy/deploy.env)
#   -n, --dry-run    print what would run without changing anything
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
info()  { echo "${BLUE}[INFO]${NC} $*"; }
ok()    { echo "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo "${YELLOW}[WARN]${NC} $*" >&2; }
die()   { echo "${RED}[FAIL]${NC} $*" >&2; exit 1; }

ENV_FILE="$SCRIPT_DIR/deploy.env"
DRY_RUN=false
STEPS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -f|--env)     ENV_FILE="$2"; shift 2 ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        preflight|deps|bases|build|unit|start|verify|checksums|upgrade|rollback) STEPS+=("$1"); shift ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
done
[[ ${#STEPS[@]} -eq 0 ]] && STEPS=(preflight deps bases build unit start verify)

if [[ -f "$ENV_FILE" ]]; then
    info "sourcing $ENV_FILE"
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
else
    warn "no env file at $ENV_FILE — using defaults (see deploy.env.example)"
fi

# Images are tagged immutably (<date>-<git sha>) so a deployment names an exact
# build and rollback is a one-line change to the unit. IMAGE pins an explicit
# reference and skips the derivation.
IMAGE_REPO="${IMAGE_REPO:-localhost/jabaws}"
IMAGE="${IMAGE:-}"
KEEP_IMAGES="${KEEP_IMAGES:-3}"
STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/jabaws-deploy}"
HISTORY_FILE="$STATE_DIR/history"
BUILT_IMAGE=""
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-300}"   # seconds to wait for /jabaws/ to answer
CONTAINER_NAME="${CONTAINER_NAME:-jabaws}"
HOST_PORT="${HOST_PORT:-8080}"
VOLUME_PREFIX="${VOLUME_PREFIX:-jabaws}"
# Individually overridable, so an existing deployment whose volumes were named
# by hand can be adopted without copying data — podman has no volume rename.
LOGS_VOLUME="${LOGS_VOLUME:-$VOLUME_PREFIX-logs}"
JOBSOUT_VOLUME="${JOBSOUT_VOLUME:-$VOLUME_PREFIX-jobsout}"
STATS_VOLUME="${STATS_VOLUME:-$VOLUME_PREFIX-stats}"
STATS_BACKUPS_VOLUME="${STATS_BACKUPS_VOLUME:-$VOLUME_PREFIX-stats-backups}"
QUADLET_SCOPE="${QUADLET_SCOPE:-user}"
UNIT_NAME="${UNIT_NAME:-jabaws}"
BUILD_LOG_DIR="${BUILD_LOG_DIR:-$REPO_DIR/build-logs}"
MIN_FREE_GB="${MIN_FREE_GB:-20}"
RUN_USER="${USER:-$(id -un)}"
WAR_URL="${WAR_URL:-http://www.compbio.dundee.ac.uk/jabaws22/archive/jabaws.war}"
PYTHON_URL="${PYTHON_URL:-https://www.python.org/ftp/python/2.7.13/Python-2.7.13.tgz}"
# Pinned to a tag, not a branch: config.guess/config.sub on master change over
# time, which would break the checksums below on every upstream update.
CONFIG_GUESS_URL="${CONFIG_GUESS_URL:-https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-13.2.0/config.guess}"
CONFIG_SUB_URL="${CONFIG_SUB_URL:-https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-13.2.0/config.sub}"

# Proxy: honour whatever is already set, export the uppercase forms the build needs.
export HTTP_PROXY="${HTTP_PROXY:-${http_proxy:-}}"
export HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
export no_proxy="localhost,127.0.0.1${NO_PROXY_EXTRA:+,$NO_PROXY_EXTRA}"
export NO_PROXY="$no_proxy"

case "$QUADLET_SCOPE" in
    user)   SYSTEMCTL=(systemctl --user); QUADLET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"; WANTED_BY="default.target" ;;
    system) SYSTEMCTL=(systemctl);        QUADLET_DIR="/etc/containers/systemd";                             WANTED_BY="multi-user.target" ;;
    *) die "QUADLET_SCOPE must be 'user' or 'system', got '$QUADLET_SCOPE'" ;;
esac

run() {
    if [[ "$DRY_RUN" == true ]]; then echo "  would run: $*"; else "$@"; fi
}

################################################################################
# Image identity and deployment state

build_tag() {  # <date>-<git sha>, marked when the tree is dirty
    local sha
    sha="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo nogit)"
    [[ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ]] && sha="${sha}-dirty"
    echo "$(date -u +%Y%m%d)-${sha}"
}

unit_file() { echo "$QUADLET_DIR/${UNIT_NAME}.container"; }

current_unit_image() {  # image reference the installed unit deploys, if any
    local f; f="$(unit_file)"
    [[ -f "$f" ]] || return 1
    awk -F= '/^Image=/ { print $2; exit }' "$f"
}

set_unit_image() {  # set_unit_image <ref>
    local f; f="$(unit_file)"
    [[ -f "$f" ]] || die "no unit at $f — run the full deploy first"
    sed -i.bak "s|^Image=.*|Image=$1|" "$f" && rm -f "$f.bak"
}

resolve_image() {  # what to deploy when no build ran in this invocation
    if [[ -n "$IMAGE" ]]; then echo "$IMAGE"; return; fi
    local from_unit; from_unit="$(current_unit_image 2>/dev/null || true)"
    if [[ -n "$from_unit" ]]; then echo "$from_unit"; return; fi
    # newest local build, so `unit` can follow a `build` from an earlier run
    podman images --filter "reference=$IMAGE_REPO" --sort created \
        --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -v ':latest$' | tail -1
}

record_deployment() {  # record_deployment <ref>
    mkdir -p "$STATE_DIR"
    printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$HISTORY_FILE"
}

previous_deployment() {  # last recorded reference that isn't the current one
    local current; current="$(current_unit_image 2>/dev/null || true)"
    [[ -f "$HISTORY_FILE" ]] || return 1
    awk -v cur="$current" '{ if ($2 != cur) prev = $2 } END { if (prev != "") print prev }' "$HISTORY_FILE"
}

# A Derby database can only be copied safely while nothing holds it open, which
# is exactly the window an upgrade opens anyway. The nightly backup covers
# routine loss; this covers "the upgrade itself was the problem".
snapshot_stats() {  # snapshot_stats <label>
    local label="$1"
    podman volume exists "$STATS_VOLUME" 2>/dev/null || {
        warn "no $STATS_VOLUME volume — skipping pre-upgrade snapshot"
        return 0
    }
    info "snapshotting statistics database (container is stopped)"
    # The jabaws image itself, so nothing has to be pulled on a host with
    # short-name resolution enforced.
    podman run --rm \
        -v "$STATS_VOLUME:/src:Z" \
        -v "$STATS_BACKUPS_VOLUME:/dst:Z" \
        --entrypoint /bin/sh "$(resolve_image)" -c \
        "mkdir -p /dst/preupgrade-$label && cp -a /src/. /dst/preupgrade-$label/ &&
         ls -1d /dst/preupgrade-* | sort | head -n -2 | xargs -r rm -rf" \
        || warn "snapshot failed — continuing, last night's backup still applies"
}

prune_images() {  # keep the newest KEEP_IMAGES, never the deployed or previous one
    local keep_current keep_prev
    keep_current="$(current_unit_image 2>/dev/null || true)"
    keep_prev="$(previous_deployment 2>/dev/null || true)"
    local ref
    while read -r ref; do
        [[ -z "$ref" || "$ref" == *":latest" ]] && continue
        [[ "$ref" == "$keep_current" || "$ref" == "$keep_prev" ]] && continue
        info "removing old image $ref"
        podman rmi "$ref" >/dev/null 2>&1 || warn "could not remove $ref (in use?)"
    done < <(podman images --filter "reference=$IMAGE_REPO" --sort created \
                --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | head -n "-$KEEP_IMAGES")
}

################################################################################
step_preflight() {
    info "preflight"

    command -v podman >/dev/null || die "podman not found in PATH"
    local ver major minor
    ver="$(podman version --format '{{.Client.Version}}')"
    major="${ver%%.*}"; minor="${ver#*.}"; minor="${minor%%.*}"
    if (( major < 4 || (major == 4 && minor < 4) )); then
        die "podman $ver is too old for Quadlet (need 4.4+)"
    fi
    ok "podman $ver"

    if [[ "$(readlink -f "$(command -v docker 2>/dev/null || echo /nonexistent)" 2>/dev/null)" != /nonexistent ]] \
       && docker --version 2>/dev/null | grep -qi podman; then
        warn "'docker' on this host is the podman-docker shim — the build scripts in the repo root will misbehave; use this script"
    fi

    local free
    free="$(df -BG --output=avail "$REPO_DIR" | tail -1 | tr -dc '0-9')"
    if (( free < MIN_FREE_GB )); then
        die "only ${free}G free on $REPO_DIR, need ${MIN_FREE_GB}G (base images + build stages are ~4G, image ~550M)"
    fi
    ok "${free}G free"

    if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        local owner
        owner="$(podman inspect "$CONTAINER_NAME" --format '{{index .Config.Labels "PODMAN_SYSTEMD_UNIT"}}' 2>/dev/null || true)"
        if [[ -z "$owner" || "$owner" == "<no value>" ]]; then
            warn "a container named '$CONTAINER_NAME' exists and is not managed by systemd"
            warn "  it holds the name and port this unit needs — see 'Adopting an existing"
            warn "  podman run deployment' in deploy/README.md before continuing"
            die "refusing to run alongside an unmanaged container of the same name"
        fi
    fi

    if ss -ltn 2>/dev/null | grep -qE "[:.]${HOST_PORT}\b"; then
        die "port $HOST_PORT is already in use"
    fi
    ok "port $HOST_PORT free"

    if (( HOST_PORT < 1024 )) && [[ "$QUADLET_SCOPE" == user ]]; then
        warn "rootless cannot bind port $HOST_PORT without net.ipv4.ip_unprivileged_port_start — publish a high port and reverse-proxy instead"
    fi

    if command -v getenforce >/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then
        ok "SELinux enforcing — the unit template uses :Z on its volumes"
    fi

    # A hand-written unit of the same name would silently win: units in
    # /etc/systemd/system outrank generator output in /run/systemd/generator.
    local existing
    existing="$("${SYSTEMCTL[@]}" show -p FragmentPath --value "${UNIT_NAME}.service" 2>/dev/null || true)"
    if [[ -n "$existing" && "$existing" != /run/systemd/generator* ]]; then
        die "${UNIT_NAME}.service already exists at $existing and would shadow the Quadlet unit — set UNIT_NAME to something else"
    fi
    ok "unit name ${UNIT_NAME}.service is free"

    if [[ "$QUADLET_SCOPE" == user ]]; then
        if [[ "$(loginctl show-user "$RUN_USER" --property=Linger --value 2>/dev/null || echo no)" != "yes" ]]; then
            warn "lingering is OFF for $RUN_USER — the container will stop when your last session ends and will not start at boot"
            warn "  fix (needs root):  loginctl enable-linger $RUN_USER"
        else
            ok "lingering enabled for $RUN_USER"
        fi
    fi

    if [[ -n "$HTTP_PROXY" ]]; then
        info "proxy: $HTTP_PROXY (no_proxy=$no_proxy)"
    fi
}

################################################################################
################################################################################
# Dependency integrity
#
# The upstream WAR is 122 MB fetched over plain HTTP, and on a proxied host it
# arrives via a middlebox we don't control. Pin what we expect to receive.
CHECKSUM_FILE="${CHECKSUM_FILE:-$SCRIPT_DIR/dependencies.sha256}"

sha256_of() {
    if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

pinned_sum() {  # pinned_sum <basename> -> sha256, or empty if not pinned
    [[ -f "$CHECKSUM_FILE" ]] || return 0
    # No interval expressions: mawk (the default awk on Debian/Ubuntu) lacks them.
    awk -v f="$1" '/^[ \t]*#/ { next } length($1) == 64 && $1 ~ /^[0-9a-f]+$/ && $2 == f { print $1 }' "$CHECKSUM_FILE" | head -1
}

verify_file() {  # verify_file <path> [existing]; dies on mismatch, warns if unpinned
    local path="$1" existing="${2:-}" name want got
    name="$(basename "$path")"
    want="$(pinned_sum "$name")"
    if [[ -z "$want" ]]; then
        warn "$name is not pinned in $(basename "$CHECKSUM_FILE") — cannot verify what was downloaded"
        return 0
    fi
    got="$(sha256_of "$path")"
    if [[ "$got" != "$want" ]]; then
        [[ -n "$existing" ]] && warn "delete $path and re-run to fetch a fresh copy"
        die "$name failed checksum: expected $want, got $got — refusing to build with it"
    fi
    ok "$name verified"
}

# Choose a route to a host: through the proxy if it can reach it, directly if
# not. Probing beats making the operator guess, and reports which one worked.
pick_route() {  # pick_route <url> <force_direct> -> sets ROUTE_ARGS / ROUTE_NAME
    local url="$1" force_direct="${2:-}"
    ROUTE_ARGS=(); ROUTE_NAME="direct"

    if [[ -n "$force_direct" ]]; then
        ROUTE_ARGS=(--noproxy '*'); ROUTE_NAME="direct (forced)"
        return 0
    fi
    if [[ -z "$HTTP_PROXY" ]]; then
        return 0   # no proxy configured; nothing to choose between
    fi
    if curl -sS -o /dev/null -m 20 -r 0-0 "$url" 2>/dev/null; then
        ROUTE_NAME="proxy"
        return 0
    fi
    local host="${url#*://}"; host="${host%%/*}"
    warn "proxy cannot reach $host — trying a direct connection"
    if curl -sS -o /dev/null -m 20 -r 0-0 --noproxy '*' "$url" 2>/dev/null; then
        ROUTE_ARGS=(--noproxy '*'); ROUTE_NAME="direct (proxy bypassed)"
        return 0
    fi
    die "neither the proxy nor a direct connection can reach $url — set a mirror via the matching *_URL variable"
}

# Prefer TLS when the host offers it, even if the pinned URL is http://.
prefer_https() {  # prefer_https <url> -> echoes url to use
    local url="$1"
    [[ "$url" == http://* ]] || { echo "$url"; return; }
    local https="https://${url#http://}"
    if curl -sS -o /dev/null -m 15 -r 0-0 "$https" 2>/dev/null \
       || curl -sS -o /dev/null -m 15 -r 0-0 --noproxy '*' "$https" 2>/dev/null; then
        echo "$https"
    else
        echo "$url"
    fi
}

step_deps() {
    info "dependencies"
    local d="$REPO_DIR/dependencies"
    run mkdir -p "$d"

    [[ -f "$CHECKSUM_FILE" ]] \
        || warn "no $(basename "$CHECKSUM_FILE") — downloads will not be verified; run '$0 checksums' on a host you trust to create it"

    fetch() {  # fetch <url> <dest> [force_direct]
        local url="$1" dest="$2" force_direct="${3:-}" name
        name="$(basename "$dest")"

        if [[ -s "$dest" ]]; then
            ok "have $name"
            [[ "$DRY_RUN" == true ]] || verify_file "$dest" existing
            return 0
        fi
        if [[ "$DRY_RUN" == true ]]; then
            echo "  would fetch $url -> $dest"
            return 0
        fi

        url="$(prefer_https "$url")"
        pick_route "$url" "$force_direct"
        info "fetching $name via $ROUTE_NAME"

        # --retry covers the transient proxy failures these hosts actually see.
        curl -fSL --connect-timeout 20 --max-time 1800 \
             --retry 3 --retry-delay 5 --retry-connrefused \
             "${ROUTE_ARGS[@]}" -o "$dest" "$url" \
            || { rm -f "$dest"; die "could not fetch $url"; }

        verify_file "$dest"
    }

    fetch "$WAR_URL"          "$d/jabaws.war"          "${WAR_NOPROXY:-}"
    fetch "$PYTHON_URL"       "$d/Python-2.7.13.tgz"
    fetch "$CONFIG_GUESS_URL" "$d/config.guess"
    fetch "$CONFIG_SUB_URL"   "$d/config.sub"

    if [[ ! -d "$d/jabaws" ]]; then
        info "exploding WAR"
        run mkdir -p "$d/jabaws"
        run unzip -q "$d/jabaws.war" -d "$d/jabaws"
    fi
    ok "dependencies ready"
}

# Record checksums for whatever is currently in dependencies/. Trust-on-first-use:
# run it only on a host whose downloads you are prepared to vouch for, then commit
# the file so every later build on every host is checked against it.
step_checksums() {
    info "recording checksums"
    local d="$REPO_DIR/dependencies" f
    for f in jabaws.war Python-2.7.13.tgz config.guess config.sub; do
        [[ -s "$d/$f" ]] || die "$d/$f is missing — run the deps step first"
    done
    if [[ "$DRY_RUN" == true ]]; then
        echo "  would write $CHECKSUM_FILE"
        return 0
    fi
    {
        echo "# sha256 checksums for build dependencies, recorded by podman-deploy.sh."
        echo "# Verified on every fetch; a mismatch aborts the build."
        for f in jabaws.war Python-2.7.13.tgz config.guess config.sub; do
            echo "$(sha256_of "$d/$f")  $f"
        done
    } > "$CHECKSUM_FILE"
    ok "wrote $CHECKSUM_FILE — commit it"
    cat "$CHECKSUM_FILE"
}

################################################################################
step_bases() {
    info "base images"
    # Read them from the Dockerfile so this can't drift out of sync.
    local refs
    mapfile -t refs < <(awk '/^FROM /{print $2}' "$REPO_DIR/Dockerfile" | grep ':' | sort -u)
    [[ ${#refs[@]} -gt 0 ]] || die "no base images found in Dockerfile"

    for ref in "${refs[@]}"; do
        if podman image exists "$ref"; then ok "$ref present"; continue; fi
        # short-name-mode=enforcing rejects unqualified names non-interactively
        local fq="$ref"
        [[ "$ref" != *"/"* ]] && fq="docker.io/library/$ref"
        info "pulling $fq"
        run podman pull "$fq" || die "pull failed for $fq"
        [[ "$fq" != "$ref" ]] && run podman tag "$fq" "$ref"
    done
    ok "base images tagged for --pull=never"
}

################################################################################
step_build() {
    info "build"
    BUILT_IMAGE="${IMAGE:-$IMAGE_REPO:$(build_tag)}"
    run mkdir -p "$BUILD_LOG_DIR"
    local log="$BUILD_LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
    info "logging to $log (10-15 min on 4 cores)"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  would run: podman build --pull=never -t $BUILT_IMAGE $REPO_DIR"
        return 0
    fi

    # setsid so a dropped SSH connection doesn't take the build with it.
    # Labels record provenance, so an image can be identified without its tag.
    setsid podman build --pull=never \
        --label "org.opencontainers.image.revision=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo unknown)" \
        --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --label "org.opencontainers.image.version=${BUILT_IMAGE##*:}" \
        -t "$BUILT_IMAGE" "$REPO_DIR" > "$log" 2>&1 &
    local pid=$!
    info "build pid $pid — tailing; ^C detaches without stopping it"
    tail --pid="$pid" -f "$log" | grep -E '^(STEP|\[[0-9]+/[0-9]+\]|Compiling|Successfully|Error: )' || true
    wait "$pid" || die "build failed — see $log"

    # gfortran prints Error: lines while compiling Tisean without failing.
    podman tag "$BUILT_IMAGE" "$IMAGE_REPO:latest"
    ok "built $BUILT_IMAGE ($(podman image inspect "$BUILT_IMAGE" --format '{{.Size}}' | numfmt --to=iec))"
}

################################################################################
step_unit() {
    info "quadlet unit"
    run mkdir -p "$QUADLET_DIR"
    local dest="$QUADLET_DIR/${UNIT_NAME}.container"
    local image_ref="${BUILT_IMAGE:-$(resolve_image)}"
    [[ -n "$image_ref" ]] || die "no image to deploy — run the build step first"
    info "deploying $image_ref"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  would install $dest"
    else
        sed -e "s|@IMAGE@|$image_ref|g" \
            -e "s|@CONTAINER_NAME@|$CONTAINER_NAME|g" \
            -e "s|@HOST_PORT@|$HOST_PORT|g" \
            -e "s|@LOGS_VOLUME@|$LOGS_VOLUME|g" \
            -e "s|@JOBSOUT_VOLUME@|$JOBSOUT_VOLUME|g" \
            -e "s|@STATS_VOLUME@|$STATS_VOLUME|g" \
            -e "s|@STATS_BACKUPS_VOLUME@|$STATS_BACKUPS_VOLUME|g" \
            -e "s|@UNIT_NAME@|$UNIT_NAME|g" \
            -e "s|@WANTED_BY@|$WANTED_BY|g" \
            "$SCRIPT_DIR/jabaws.container.in" > "$dest"
        ok "installed $dest"
        record_deployment "$image_ref"
    fi

    run "${SYSTEMCTL[@]}" daemon-reload

    if [[ "$DRY_RUN" != true ]]; then
        "${SYSTEMCTL[@]}" cat "${UNIT_NAME}.service" >/dev/null 2>&1 \
            || die "systemd did not generate ${UNIT_NAME}.service — check with: /usr/libexec/podman/quadlet -dryrun$([[ $QUADLET_SCOPE == user ]] && echo ' -user')"
        ok "${UNIT_NAME}.service generated"
    fi
}


################################################################################
step_upgrade() {
    info "upgrade"
    local prev
    prev="$(current_unit_image)" || die "no unit installed — run the full deploy first"
    [[ -n "$prev" ]] || die "the unit has no Image= line"
    info "currently deployed: $prev"

    step_deps
    step_bases
    step_build

    if [[ "$DRY_RUN" == true ]]; then
        echo "  would swap $prev -> $BUILT_IMAGE and verify, rolling back on failure"
        return 0
    fi
    if [[ "$BUILT_IMAGE" == "$prev" ]]; then
        warn "$BUILT_IMAGE is already deployed — nothing to swap"
        return 0
    fi

    # Derby holds an exclusive lock on the statistics volume, so the old and new
    # containers cannot overlap. Stop, snapshot in the gap, then swap.
    info "stopping ${UNIT_NAME}.service"
    "${SYSTEMCTL[@]}" stop "${UNIT_NAME}.service" || warn "stop reported an error"
    snapshot_stats "${BUILT_IMAGE##*:}"

    set_unit_image "$BUILT_IMAGE"
    "${SYSTEMCTL[@]}" daemon-reload
    "${SYSTEMCTL[@]}" start "${UNIT_NAME}.service" || warn "start reported an error"

    if verify_endpoints; then
        record_deployment "$BUILT_IMAGE"
        ok "upgraded $prev -> $BUILT_IMAGE"
        prune_images
        return 0
    fi

    warn "new image did not verify — rolling back to $prev"
    "${SYSTEMCTL[@]}" stop "${UNIT_NAME}.service" || true
    set_unit_image "$prev"
    "${SYSTEMCTL[@]}" daemon-reload
    "${SYSTEMCTL[@]}" start "${UNIT_NAME}.service" || true

    if verify_endpoints; then
        die "upgrade to $BUILT_IMAGE failed; rolled back to $prev, which is serving again"
    fi
    die "upgrade to $BUILT_IMAGE failed AND the rollback to $prev did not come up — ${SYSTEMCTL[*]} status ${UNIT_NAME}.service"
}

################################################################################
step_rollback() {
    info "rollback"
    local current target
    current="$(current_unit_image)" || die "no unit installed"
    target="${ROLLBACK_TO:-$(previous_deployment || true)}"
    [[ -n "$target" ]] || die "no earlier deployment in $HISTORY_FILE — set ROLLBACK_TO=<image reference>"
    [[ "$target" != "$current" ]] || die "$target is already deployed"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  would roll back $current -> $target"
        return 0
    fi
    podman image exists "$target" \
        || die "$target is no longer present locally — pick another from: $(podman images --filter "reference=$IMAGE_REPO" --format '{{.Repository}}:{{.Tag}}' | tr '\n' ' ')"

    info "rolling back $current -> $target"
    "${SYSTEMCTL[@]}" stop "${UNIT_NAME}.service" || warn "stop reported an error"
    set_unit_image "$target"
    "${SYSTEMCTL[@]}" daemon-reload
    "${SYSTEMCTL[@]}" start "${UNIT_NAME}.service" || warn "start reported an error"

    verify_endpoints || die "rollback to $target did not come up — ${SYSTEMCTL[*]} status ${UNIT_NAME}.service"
    record_deployment "$target"
    ok "rolled back to $target"
}

################################################################################
step_start() {
    info "starting ${UNIT_NAME}.service"
    run "${SYSTEMCTL[@]}" start "${UNIT_NAME}.service"
    [[ "$DRY_RUN" == true ]] && return 0
    "${SYSTEMCTL[@]}" is-active --quiet "${UNIT_NAME}.service" \
        || die "unit did not start — ${SYSTEMCTL[*]} status ${UNIT_NAME}.service"
    ok "running"
}

################################################################################
verify_endpoints() {  # returns non-zero instead of dying, for the upgrade path
    local deadline=$((SECONDS + VERIFY_TIMEOUT)) code=000
    while (( SECONDS < deadline )); do
        code="$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' \
                "http://localhost:$HOST_PORT/jabaws/" 2>/dev/null || echo 000)"
        [[ "$code" == "200" ]] && break
        sleep 5
    done
    if [[ "$code" != "200" ]]; then
        warn "GET /jabaws/ returned $code after ${VERIFY_TIMEOUT}s"
        return 1
    fi

    local failed=0
    for p in "" "ClustalWS?wsdl" "MafftWS?wsdl" "ServiceStatus"; do
        code="$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' \
                "http://localhost:$HOST_PORT/jabaws/$p" || echo 000)"
        printf '  %-22s HTTP %s\n' "/$p" "$code"
        [[ "$code" == "200" ]] || failed=1
    done
    (( failed == 0 )) || { warn "not all endpoints returned 200"; return 1; }

    ok "JABAWS is serving on http://localhost:$HOST_PORT/jabaws/"
    info "the registry warm-up runs in the background; services may show as untested for a few minutes"
    info "logs:   podman logs -f $CONTAINER_NAME"
    info "manage: ${SYSTEMCTL[*]} {status,restart,stop} ${UNIT_NAME}.service"
}

step_verify() {
    info "verifying"
    [[ "$DRY_RUN" == true ]] && { echo "  would curl http://localhost:$HOST_PORT/jabaws/"; return 0; }
    verify_endpoints || die "verification failed — ${SYSTEMCTL[*]} status ${UNIT_NAME}.service"
}

################################################################################
[[ "$DRY_RUN" == true ]] && warn "dry run — no changes will be made"
for s in "${STEPS[@]}"; do "step_$s"; done
ok "done: ${STEPS[*]}"
