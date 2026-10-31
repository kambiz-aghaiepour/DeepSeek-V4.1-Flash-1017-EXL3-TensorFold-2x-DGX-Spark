#!/usr/bin/env bash
# Build the engine image on the head at the pinned TensorFold commit, copy it to the worker, and check that both nodes
# hold the same image ID. ~10 min (the NGC base pull is ~20 GB the first time).
set -euo pipefail
# shellcheck source=../scripts/common.sh
. "$(dirname "$0")/../scripts/common.sh"

log "building $IMAGE from $TF_REPO @ $TF_COMMIT"
# --network host: the build clones TensorFold, and a host that resolves through a loopback stub
# (systemd-resolved on 127.0.0.53) has no working DNS inside an isolated build network.
"${RT_CMD[@]}" build --network host --build-arg TF_REPO="$TF_REPO" --build-arg TF_COMMIT="$TF_COMMIT" -t "$IMAGE" "$ROOT/docker"
log "copying $IMAGE to the worker ($WORKER_SSH)"
"${RT_CMD[@]}" save "${SAVE_ARGS[@]}" "$IMAGE" | ssh -o BatchMode=yes "$WORKER_SSH" "$RT_STRING load"
head_id=$("${RT_CMD[@]}" images "$IMAGE" --format '{{.ID}}')
worker_id=$(wssh "$RT_STRING images '$IMAGE' --format '{{.ID}}'")
[ "$head_id" = "$worker_id" ] || { log "image IDs differ: head $head_id, worker $worker_id"; exit 1; }
log "both nodes hold $IMAGE ($head_id)"
