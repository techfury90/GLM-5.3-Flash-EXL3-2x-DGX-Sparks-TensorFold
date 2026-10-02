#!/usr/bin/env bash
# Save every rank's container log under STATE_DIR before anything removes the containers (issue #31): a rank that
# dies on its own takes its traceback with it once its container is gone, and stop.sh's docker rm -f -- or a monitor
# that calls stop.sh -- removes exactly that. docker logs survives a stop but not an rm, so every teardown path calls
# this first. Safe to re-run and to call while everything is healthy: each dump lands in a fresh timestamped file,
# and a container that is not there is skipped with a note. The whole log is kept, not a tail: the engine logs
# sparsely, and a traceback needs the startup lines above it (the patch set, the settings) for the context.
# Usage: scripts/persist-logs.sh [reason]   Env: CONTAINER_NAME, STATE_DIR, TP (see scripts/config.sh)
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
source ./scripts/config.sh
source ./scripts/nodes.sh

reason="${1:-}"
dir="$STATE_DIR/container-logs"
mkdir -p "$dir"
stamp="$(date +%Y%m%d-%H%M%S)-$$"
saved=0

dump() {                                      # dump <rank> <command...>: the container's log to a fresh file
  local rank="$1" file
  shift
  file="$dir/$CONTAINER_NAME-rank$rank-$stamp${reason:+-$reason}.log"
  if "$@" >"$file" 2>&1; then
    log "saved rank $rank's container log: $file ($(wc -l <"$file") lines)"
    saved=$((saved + 1))
  else
    warn "could not read rank $rank's container log"
    rm -f "$file"
  fi
}

if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  dump 0 docker logs "$CONTAINER_NAME"
else
  log "no container named $CONTAINER_NAME here: rank 0's log has nothing to save"
fi

for i in $(configured_workers); do
  if worker "$i" "docker inspect '$CONTAINER_NAME' >/dev/null 2>&1"; then
    dump "$i" worker "$i" "docker logs '$CONTAINER_NAME' 2>&1"
  else
    log "no container named $CONTAINER_NAME on $(worker_host "$i"): rank $i's log has nothing to save"
  fi
done

(( saved )) || log "no container logs were saved"
