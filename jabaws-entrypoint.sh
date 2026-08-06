#!/bin/bash
#
# Warm the JABAWS service registry, then hand off to Tomcat.
#
# Why this exists
# ---------------
# RegistryWS builds the service URLs it self-tests from the Host header of the
# incoming request. Behind a port mapping such as `-p 18080:8080` that yields
# http://localhost:18080/jabaws/..., which nothing serves *inside* the container
# (Tomcat listens on 8080), so every self-test fails with "Could not connect to
# ..." and getSupportedServices() keeps returning an empty set.
#
# That empty set is what breaks Jalview: JabaWsServerQuery skips every service
# not present in it, and because an empty set is not an error, Jalview's
# JABAWS1 fallback never fires -- it silently discovers zero services.
#
# Calling testAllServices once from inside the container, where the advertised
# port and the listening port agree, populates the registry's cache. That cache
# is global rather than per-URL, so external clients on any mapped port
# afterwards see the full service list.
#
# The self-test genuinely runs every alignment tool, so it costs a few minutes
# of CPU. It runs in the background: Tomcat serves requests throughout, and the
# registry fills in once the sweep completes. Set JABAWS_WARMUP=0 to skip it.

set -u

REGISTRY_URL="http://localhost:8080/jabaws/RegistryWS"
READY_TIMEOUT="${JABAWS_WARMUP_READY_TIMEOUT:-300}"
TEST_TIMEOUT="${JABAWS_WARMUP_TEST_TIMEOUT:-900}"

log() { echo "[jabaws-warmup] $*"; }

warm_registry() {
  local waited=0

  # Wait for the webapp, not just the port -- Tomcat opens 8080 before it has
  # finished deploying, so RegistryWS 404s for a while after the port is up.
  until curl -sf -o /dev/null "${REGISTRY_URL}?wsdl"; do
    if [ "$waited" -ge "$READY_TIMEOUT" ]; then
      log "RegistryWS did not respond within ${READY_TIMEOUT}s -- skipping warm-up."
      log "Services will still work, but getSupportedServices() stays empty and"
      log "Jalview will discover nothing. Re-run testAllServices by hand to fix."
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done

  log "RegistryWS up after ${waited}s; running testAllServices (exercises every tool, takes a few minutes)..."

  if curl -s --max-time "$TEST_TIMEOUT" \
       -H 'Content-Type: text/xml;charset=UTF-8' \
       -H 'SOAPAction: ""' \
       -d '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><testAllServices xmlns="http://msa.data.compbio/01/12/2010/"/></s:Body></s:Envelope>' \
       "$REGISTRY_URL" > /tmp/jabaws-warmup.log 2>&1
  then
    working=$(grep -oE 'IS WORKING' /tmp/jabaws-warmup.log | wc -l | tr -d ' ')
    failed=$(grep -oE 'Fails to connect' /tmp/jabaws-warmup.log | wc -l | tr -d ' ')
    log "warm-up complete: ${working} service(s) working, ${failed} unreachable."
    if [ "$working" = "0" ]; then
      log "No services came back working -- see /tmp/jabaws-warmup.log in the container."
    fi
  else
    log "warm-up request failed or timed out after ${TEST_TIMEOUT}s."
    log "See /tmp/jabaws-warmup.log in the container."
  fi
}

if [ "${JABAWS_WARMUP:-1}" = "1" ]; then
  warm_registry &
else
  log "disabled via JABAWS_WARMUP=${JABAWS_WARMUP:-1}; registry will report no supported services until testAllServices is called."
fi

# exec so Tomcat replaces this shell and receives SIGTERM from `docker stop`
exec "$@"
