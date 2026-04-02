# nix-dev-env

This repo exposes the same development environment in a few consistent ways:

| Mode | Command | Platforms | Notes |
| --- | --- | --- | --- |
| Interactive dev shell | `nix develop` | Linux, macOS | Canonical interactive entrypoint. Loads prompt, completion, and shell profile snippets. |
| One-off tool access | `nix shell . -c <cmd>` | Linux, macOS | Fast ephemeral access to the default toolchain without running the shell hook. |
| Installed profile | `nix profile add .` | Linux, macOS | Installs the same default package into your user profile. |
| Validation | `nix flake check` | Linux, macOS | Runs the declarative checks for the current system. On Linux, that includes both container image builds. |
| Formatting | `nix fmt` | Linux, macOS | Formats the repo with the flake formatter. |
| Scratch container image | `nix build .#containerImage` | Linux | Barebones image with no upstream base image. |
| Ubuntu container image | `nix build .#containerImageUbuntu` | Linux | Ubuntu-based image for tools that expect a conventional distro base. |
| Dockerfile build | `docker build .` | Linux, macOS | Host does not need Nix preinstalled. |

## Quickstart

To speed up local `nix develop`, `nix shell`, `nix profile add .`, and `nix flake check`, configure the public `https://cache.numtide.com` binary cache once on your host Nix installation. This environment includes LLM tool packages from [numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix), and without that cache Nix may need to build them from source, which is much slower.

Add the following lines to `~/.config/nix/nix.conf` on single-user Nix installs, or to `/etc/nix/nix.conf` on multi-user or daemon-backed installs:

```conf
extra-substituters = https://cache.numtide.com
extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
```

If your system uses `nix-daemon` or another multi-user setup, update `/etc/nix/nix.conf`, not just your user config. CI, the devcontainer, and the Dockerfile already configure this cache explicitly.

Open the canonical interactive development shell:

```bash
nix develop
```

Run one-off commands with the same toolchain:

```bash
nix shell . -c <command>
```

You can still run bare `nix shell .`, but it will not load the prompt/completion/profile behavior that `nix develop` and the container images use.

Install the environment into your profile:

```bash
nix profile add .
```

Validate the flake:

```bash
nix flake check
```

## Container images

Both container variants run as the non-root user `nonroot` with `HOME=/home/nonroot` and `WORKDIR=/app`.

Build the scratch image:

```bash
nix build .#containerImage
docker load < result
docker run --rm -it nix-dev-env:latest
```

Build the Ubuntu image:

```bash
nix build .#containerImageUbuntu
docker load < result
docker run --rm -it nix-dev-env-ubuntu:latest
```

With Podman bind mounts, map the host user onto the image's `nonroot` account:

```bash
podman run --rm -it --userns=keep-id:uid=1000,gid=1000 -v "$PWD:/app" nix-dev-env-ubuntu:latest
```

## Dockerfile

The included [Dockerfile](/Users/plasma-penguin/code/nix-dev-env/Dockerfile) builds from `nixos/nix`, installs the flake's default package, sets up the same profile snippets, and then drops to `nonroot` with `HOME=/home/nonroot` and `WORKDIR=/app`.

```bash
docker build -t nix-dev-env-dockerfile .
docker run --rm -it -v "$PWD:/app" nix-dev-env-dockerfile
```

## Makefile

The [Makefile](/Users/plasma-penguin/code/nix-dev-env/Makefile) mirrors the flake outputs:

- `make shell`
- `make dev`
- `make tools`
- `make install`
- `make fmt`
- `make check`
- `make build`
- `make build-ubuntu`
- `make run`
- `make run-ubuntu`

`make shell` and `make dev` both open the canonical `nix develop` environment. `make tools` is the ephemeral `nix shell .` path for one-off commands. If `podman` is installed, it is preferred by default so rootless runs automatically use `--userns=keep-id:uid=1000,gid=1000`. You can override the engine or bind mount path with `CONTAINER_ENGINE=...` and `APP_DIR=...`.

## CI/CD

GitHub Actions is split into two flows:

- `CI` runs `nix flake check`, tests `nix shell` / `nix develop`, validates the Dockerfile image, and smoke-tests both Nix-built container images.
- `Nightly Update` refreshes all flake inputs, repins the Ubuntu base image, validates the updated revision, and publishes the fresh images directly.

Pushes to `main` publish the tested images to Docker Hub with:

- scratch tags: `latest` and `sha-<commit>`
- Ubuntu tags: `ubuntu-latest` and `ubuntu-sha-<commit>`

The publish jobs require:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`
- optional `DOCKERHUB_REPO`

If `DOCKERHUB_REPO` is unset, the workflows publish to `${DOCKERHUB_USERNAME}/nix-dev-env`. The CI workflows configure the public `https://cache.numtide.com` binary cache directly in their Nix settings.

## VS Code

The checked-in `.devcontainer` setup uses an Ubuntu base image plus the Nix devcontainer feature to install this flake directly. It also configures the public Numtide binary cache explicitly. If you want to use the published prebuilt image instead, point your devcontainer at the Ubuntu tag and keep the remote user non-root:

```json
{
  "name": "nix-dev-env",
  "image": "your-dockerhub-user/nix-dev-env:ubuntu-latest",
  "workspaceMount": "source=${localWorkspaceFolder},target=/app,type=bind",
  "workspaceFolder": "/app",
  "remoteUser": "nonroot",
  "containerUser": "nonroot",
  "overrideCommand": true,
  "runArgs": ["--entrypoint", ""]
}
```

If you use Podman for VS Code devcontainers, add the keep-id user namespace mapping to `runArgs` as well:

```json
"runArgs": [
  "--entrypoint",
  "",
  "--userns=keep-id:uid=1000,gid=1000"
]
```
