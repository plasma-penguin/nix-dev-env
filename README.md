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

## Docker Sandboxes (`sbx`)

The included `Dockerfile.sbx` installs the same flake package into an agent-specific [Docker Sandbox template](https://docs.docker.com/ai/sandboxes/). Its `-docker` base variants give every sandbox its own isolated Docker Engine as well as the Nix development environment; Nix does not need to be installed on the host.

The template variant is selected at build time. Codex is the default:

| Agent | `SBX_TEMPLATE_VARIANT` | Suggested image tag |
| --- | --- | --- |
| Codex | `codex-docker` (default) | `nix-dev-env-sbx:codex` |
| OpenCode | `opencode-docker` | `nix-dev-env-sbx:opencode` |
| Shell (no managed agent) | `shell-docker` | `nix-dev-env-sbx:shell` |

Build one or more variants with Docker:

```bash
# Codex (uses the default build argument)
docker build -f Dockerfile.sbx -t nix-dev-env-sbx:codex .

# OpenCode
docker build -f Dockerfile.sbx \
  --build-arg SBX_TEMPLATE_VARIANT=opencode-docker \
  -t nix-dev-env-sbx:opencode .

# Agent-less shell
docker build -f Dockerfile.sbx \
  --build-arg SBX_TEMPLATE_VARIANT=shell-docker \
  -t nix-dev-env-sbx:shell .
```

The sandbox runtime does not share the host Docker daemon's image store. To use a locally built template without pushing it to a registry, export and load it explicitly:

```bash
docker image save nix-dev-env-sbx:codex -o /tmp/nix-dev-env-sbx-codex.tar
sbx template load /tmp/nix-dev-env-sbx-codex.tar
```

The agent passed to `sbx run` must match the template base. Start a Codex sandbox on a private clone of the current Git repository with:

```bash
sbx run \
  --name codex-agent-1 \
  --clone \
  --template nix-dev-env-sbx:codex \
  codex .
```

`--clone` is recommended when running agents in parallel because each agent works in its own private repository clone. Omit `--clone` to mount the host workspace directly instead; changes made by the agent then appear immediately in the host directory. A second isolated agent can use the same cached template with a different name:

```bash
sbx run \
  --name codex-agent-2 \
  --clone \
  --template nix-dev-env-sbx:codex \
  codex .
```

Common lifecycle and interaction commands:

```bash
# List sandboxes
sbx ls

# Start a stopped sandbox and reattach to its configured agent
sbx run --name codex-agent-1

# Open a shell (also starts the sandbox if it is stopped)
sbx exec -it codex-agent-1 bash

# Use the sandbox's isolated Docker Engine
sbx exec codex-agent-1 -- docker ps
sbx exec codex-agent-1 -- docker compose up -d

# Publish a sandbox port on the host
sbx ports codex-agent-1 --publish 3000:3000

# Stop while preserving the VM, agent state, packages, and Docker data
sbx stop codex-agent-1

# Permanently remove the sandbox and its associated state
sbx rm codex-agent-1
```

Launch the other image variants with their matching agents:

```bash
sbx run --template nix-dev-env-sbx:opencode opencode .
sbx run --template nix-dev-env-sbx:shell shell .
```

For Codex authentication, `sbx run` prompts on first use, or credentials can be configured ahead of time with `sbx secret set openai --oauth`.

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
