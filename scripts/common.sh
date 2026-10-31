# Shared by start.sh, stop.sh, status.sh and verify.sh: reads .env and defines the helpers. Source it; do not run it.
# shellcheck shell=bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_ENV_FILE=${TF_ENV_FILE:-$ROOT/.env}
if [ ! -f "$TF_ENV_FILE" ]; then
  echo "no $TF_ENV_FILE: copy the matching .env example and edit it" >&2
  exit 1
fi
set -a
# The user selects this settings file at run time.
# shellcheck disable=SC1090,SC1091
. "$TF_ENV_FILE"
set +a

API="http://${BIND_HOST/0.0.0.0/127.0.0.1}:${PORT}/v1"
# shellcheck disable=SC2034  # the scripts that source this file use STORE_PORT and LOGS
STORE_PORT=29551                 # TensorFold's rank-0 rendezvous port (--master-port default)
# shellcheck disable=SC2034
LOGS="$ROOT/logs"

# --- container runtime ------------------------------------------------------------------------------
# docker (default, unchanged behaviour) or podman. Both nodes must use the same runtime.
# CONTAINER_RT_SUDO=1 runs it through passwordless sudo: rootful podman matches docker's cgroup, device and
# memlock behaviour. Rootless podman works too, but a system slice (CGROUP_PARENT) needs CONTAINER_RT_SUDO=1.
CONTAINER_RT=${CONTAINER_RT:-docker}
case "$CONTAINER_RT" in
  docker|podman) ;;
  *) echo "CONTAINER_RT must be docker or podman, not '$CONTAINER_RT'" >&2; exit 2 ;;
esac
CONTAINER_RT_SUDO=${CONTAINER_RT_SUDO:-0}
if [ "$CONTAINER_RT_SUDO" = 1 ]; then
  # shellcheck disable=SC2034  # RT_CMD, RT_STRING, GPU_ARGS and SAVE_ARGS are used by the scripts that source this file
  RT_CMD=(sudo -n "$CONTAINER_RT"); RT_STRING="sudo -n $CONTAINER_RT"
else
  RT_CMD=("$CONTAINER_RT"); RT_STRING="$CONTAINER_RT"
fi
# podman 6.x accepts --gpus all. On an older podman use the CDI form: GPU_ARGS="--device nvidia.com/gpu=all"
# A display name for messages ("Docker" / "Podman"), so the wording stays readable in both cases.
RT_LABEL=Docker; [ "$CONTAINER_RT" = podman ] && RT_LABEL=Podman
GPU_ARGS=${GPU_ARGS:---gpus all}
# podman refuses --shm-size together with --ipc host ("cannot set shmsize ... in the host IPC namespace").
# With host IPC the container already uses the host's /dev/shm, which is half the RAM on DGX OS.
SHM_ARGS_STR="--shm-size 32g"
[ "$CONTAINER_RT" = podman ] && SHM_ARGS_STR=""
SAVE_ARGS=()
[ "$CONTAINER_RT" = podman ] && SAVE_ARGS=(--format docker-archive)

log() { echo "[tfv41 $(date -u +%H:%M:%SZ)] $*"; }
wssh() { ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$WORKER_SSH" "$@"; }
auth() { [ -n "${API_KEY_FILE:-}" ] && printf 'Authorization: Bearer %s' "$(grep -v '^#' "$API_KEY_FILE" | head -1 | sed 's/^.*: *//')"; }
healthy() { curl -fsS -m 10 -H "$(auth)" "$API/models" 2>/dev/null | grep -q "\"$SERVED_NAME\""; }
