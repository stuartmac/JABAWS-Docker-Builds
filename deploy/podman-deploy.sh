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
        preflight|deps|bases|build|unit|start|verify) STEPS+=("$1"); shift ;;
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

IMAGE="${IMAGE:-localhost/jabaws:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-jabaws}"
HOST_PORT="${HOST_PORT:-8080}"
VOLUME_PREFIX="${VOLUME_PREFIX:-jabaws}"
QUADLET_SCOPE="${QUADLET_SCOPE:-user}"
UNIT_NAME="${UNIT_NAME:-jabaws}"
BUILD_LOG_DIR="${BUILD_LOG_DIR:-$REPO_DIR/build-logs}"
MIN_FREE_GB="${MIN_FREE_GB:-20}"
RUN_USER="${USER:-$(id -un)}"
WAR_URL="${WAR_URL:-http://www.compbio.dundee.ac.uk/jabaws22/archive/jabaws.war}"
PYTHON_URL="${PYTHON_URL:-https://www.python.org/ftp/python/2.7.13/Python-2.7.13.tgz}"
CONFIG_GUESS_URL="${CONFIG_GUESS_URL:-https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess}"
CONFIG_SUB_URL="${CONFIG_SUB_URL:-https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.sub}"

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
step_deps() {
    info "dependencies"
    local d="$REPO_DIR/dependencies"
    run mkdir -p "$d"

    fetch() {  # fetch <url> <dest> [noproxy]
        local url="$1" dest="$2" noproxy="${3:-}"
        if [[ -s "$dest" ]]; then ok "have $(basename "$dest")"; return 0; fi
        local args=(-fSL --connect-timeout 20 --max-time 900 -o "$dest")
        [[ -n "$noproxy" ]] && args+=(--noproxy '*')
        info "fetching $(basename "$dest")${noproxy:+ (proxy bypassed)}"
        run curl "${args[@]}" "$url" \
            || die "could not fetch $url — if a proxy is in the way, set WAR_NOPROXY=1 or point *_URL at a mirror"
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
    run mkdir -p "$BUILD_LOG_DIR"
    local log="$BUILD_LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
    info "logging to $log (10-15 min on 4 cores)"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  would run: podman build --pull=never -t $IMAGE $REPO_DIR"
        return 0
    fi

    # setsid so a dropped SSH connection doesn't take the build with it.
    setsid podman build --pull=never -t "$IMAGE" "$REPO_DIR" > "$log" 2>&1 &
    local pid=$!
    info "build pid $pid — tailing; ^C detaches without stopping it"
    tail --pid="$pid" -f "$log" | grep -E '^(STEP|\[[0-9]+/[0-9]+\]|Compiling|Successfully|Error: )' || true
    wait "$pid" || die "build failed — see $log"

    # gfortran prints Error: lines while compiling Tisean without failing.
    ok "built $IMAGE ($(podman image inspect "$IMAGE" --format '{{.Size}}' | numfmt --to=iec))"
}

################################################################################
step_unit() {
    info "quadlet unit"
    run mkdir -p "$QUADLET_DIR"
    local dest="$QUADLET_DIR/${UNIT_NAME}.container"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  would install $dest"
    else
        sed -e "s|@IMAGE@|$IMAGE|g" \
            -e "s|@CONTAINER_NAME@|$CONTAINER_NAME|g" \
            -e "s|@HOST_PORT@|$HOST_PORT|g" \
            -e "s|@VOLUME_PREFIX@|$VOLUME_PREFIX|g" \
            -e "s|@UNIT_NAME@|$UNIT_NAME|g" \
            -e "s|@WANTED_BY@|$WANTED_BY|g" \
            "$SCRIPT_DIR/jabaws.container.in" > "$dest"
        ok "installed $dest"
    fi

    run "${SYSTEMCTL[@]}" daemon-reload

    if [[ "$DRY_RUN" != true ]]; then
        "${SYSTEMCTL[@]}" cat "${UNIT_NAME}.service" >/dev/null 2>&1 \
            || die "systemd did not generate ${UNIT_NAME}.service — check with: /usr/libexec/podman/quadlet -dryrun$([[ $QUADLET_SCOPE == user ]] && echo ' -user')"
        ok "${UNIT_NAME}.service generated"
    fi
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
step_verify() {
    info "verifying"
    [[ "$DRY_RUN" == true ]] && { echo "  would curl http://localhost:$HOST_PORT/jabaws/"; return 0; }

    local deadline=$((SECONDS + 300)) code=000
    while (( SECONDS < deadline )); do
        code="$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' \
                "http://localhost:$HOST_PORT/jabaws/" 2>/dev/null || echo 000)"
        [[ "$code" == "200" ]] && break
        sleep 5
    done
    [[ "$code" == "200" ]] || die "GET /jabaws/ returned $code after 5 min — ${SYSTEMCTL[*]} status ${UNIT_NAME}.service"

    local failed=0
    for p in "" "ClustalWS?wsdl" "MafftWS?wsdl" "ServiceStatus"; do
        code="$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' \
                "http://localhost:$HOST_PORT/jabaws/$p" || echo 000)"
        printf '  %-22s HTTP %s\n' "/$p" "$code"
        [[ "$code" == "200" ]] || failed=1
    done
    (( failed == 0 )) || die "not all endpoints returned 200"

    ok "JABAWS is serving on http://localhost:$HOST_PORT/jabaws/"
    info "the registry warm-up runs in the background; services may show as untested for a few minutes"
    info "logs:   podman logs -f $CONTAINER_NAME"
    info "manage: ${SYSTEMCTL[*]} {status,restart,stop} ${UNIT_NAME}.service"
}

################################################################################
[[ "$DRY_RUN" == true ]] && warn "dry run — no changes will be made"
for s in "${STEPS[@]}"; do "step_$s"; done
ok "done: ${STEPS[*]}"
