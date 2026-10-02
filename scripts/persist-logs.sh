#!/usr/bin/env bash
# Save the two ranks' container logs under STATE_DIR before anything removes the containers (issue #31): a rank that
# dies on its own takes its traceback with it once its container is gone, and stop.sh's docker rm -f -- or a monitor
# that calls stop.sh -- removes exactly that. docker logs survives a stop but not an rm, so every teardown path calls
# this first. Safe to re-run and to call while everything is healthy: each dump lands in a fresh timestamped file,
# and a container that is not there is skipped with a note. The whole log is kept, not a tail: the engine logs
# sparsely, and a traceback needs the startup lines above it (the patch set, the settings) for the context.
# Usage: scripts/persist-logs.sh [reason]   Env: CONTAINER_NAME, STATE_DIR, WORKER (see scripts/config.sh)
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
source ./scripts/config.sh
source ./scripts/nodes.sh

reason="${1:-}"
dir="$STATE_DIR/container-logs"
mkdir -p "$dir"
stamp="$(date +%Y%m%d-%H%M%S)-$$"

saved=0
if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  file="$dir/$CONTAINER_NAME-rank0-$stamp${reason:+-$reason}.log"
  if docker logs "$CONTAINER_NAME" >"$file" 2>&1; then
    log "saved rank 0's container log: $file ($(wc -l <"$file") lines)"
    saved=1
  else
    warn "could not read rank 0's container log"
    rm -f "$file"
  fi
else
  log "no container named $CONTAINER_NAME here: rank 0's log has nothing to save"
fi

if [[ -n "${WORKER:-}" ]] && worker true 2>/dev/null; then
  if worker "docker inspect '$CONTAINER_NAME' >/dev/null 2>&1"; then
    file="$dir/$CONTAINER_NAME-rank1-$stamp${reason:+-$reason}.log"
    if worker "docker logs '$CONTAINER_NAME' 2>&1" >"$file" 2>&1; then
      log "saved rank 1's container log: $file ($(wc -l <"$file") lines)"
      saved=1
    else
      warn "could not read rank 1's container log"
      rm -f "$file"
    fi
  else
    log "no container named $CONTAINER_NAME on $WORKER: rank 1's log has nothing to save"
  fi
fi

(( saved )) || log "no container logs were saved"
