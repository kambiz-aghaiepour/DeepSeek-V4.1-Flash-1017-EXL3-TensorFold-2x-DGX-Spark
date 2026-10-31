# Podman instead of Docker

The scripts run unchanged under podman. Set one value in `.env`:

```bash
CONTAINER_RT=podman
```

The runtime must be the same on both nodes. `docker` stays the default, so a
podman change cannot alter the tested setup by accident.

## Rootful or rootless

```bash
CONTAINER_RT_SUDO=1     # rootful podman through passwordless sudo
```

**Rootful podman is the close match for docker here.** This recipe relies on
three docker behaviours that rootless podman does not give you in the same way:

| What | Why it matters |
|---|---|
| `--cgroup-parent tensorfold.slice` | `scripts/host_tuning.sh` creates that system slice with swap off. Rootless podman cannot join a system slice. |
| `--device /dev/infiniband` | The RDMA gather needs the uverbs devices. They are world-readable (`0666`), so rootless can pass them, but the device cgroup rules are simpler rootful. |
| `--ulimit memlock=-1` | Works rootless when the hard limit is unlimited, which DGX OS sets. |

With rootless podman set `CGROUP_PARENT=` as well: preflight stops with a clear
message if you leave the system slice configured, because the engine would then
be allowed to swap.

## GPU devices

Podman 6.x accepts `--gpus all`, which this recipe passes through `GPU_ARGS`.
On an older podman use the CDI form:

```bash
GPU_ARGS="--device nvidia.com/gpu=all"
```

`nvidia-ctk cdi list` must show `nvidia.com/gpu=all`.

## Image build and copy

`docker/build.sh` becomes:

- `podman build` on the head,
- `podman save --format docker-archive | ssh <worker> podman load`,
- `podman images` on both nodes to compare the image IDs.

Rootful podman stores the image in `/var/lib/containers/storage`; rootless
podman stores it in the user's home. The two stores do not see each other, so
keep `CONTAINER_RT_SUDO` the same on both nodes.

## GPU guard

`scripts/uncensored.sh` refuses to start while another GPU container runs. Under
docker it reads `DeviceRequests` and `Runtime`; under podman it reads the
`HostConfig` JSON (`Devices`, CDI annotations), because podman has no
`DeviceRequests` field. With `CONTAINER_RT_SUDO=1` it also scans the user's
rootless containers, so a rootless vLLM server still blocks the start.

## What was checked

- `tests/run_offline.sh` passes, including the launcher tests.
- Podman 6.1.2 accepts the full flag set: `--gpus all`, `--device
  /dev/infiniband`, `--ipc host`, `--network host`, `--shm-size`, `--ulimit
  memlock=-1`, `--oom-score-adj`, `--cap-add IPC_LOCK`, `--cap-add SYS_PTRACE`.
- The RDMA device nodes are `0666`, so a rootless container can open them.

Not checked here: a full engine start under podman, which needs the 400 GB
model and an idle pair.
