.PHONY: shell dev tools install fmt check build build-ubuntu load load-ubuntu run run-ubuntu clean

IMAGE_NAME ?= nix-dev-env
UBUNTU_IMAGE_NAME ?= nix-dev-env-ubuntu

# Auto-detect container engine (prefer podman for rootless workflows, fall back to docker)
CONTAINER_ENGINE ?= $(shell if command -v podman >/dev/null 2>&1; then echo podman; elif command -v docker >/dev/null 2>&1; then echo docker; else echo docker; fi)

# Podman bind mounts should map the host user onto the image's nonroot account
# (uid/gid 1000). Docker doesn't support keep-id.
ifeq ($(CONTAINER_ENGINE),podman)
    USERNS_FLAG := --userns=keep-id:uid=1000,gid=1000
else
    USERNS_FLAG :=
endif

# Optional directory to mount as /app in the container
APP_DIR ?=
ifneq ($(APP_DIR),)
    VOLUME_FLAG := -v $(APP_DIR):/app
else
    VOLUME_FLAG :=
endif

# Open the canonical interactive development shell.
shell:
	nix develop

# Alias for the canonical interactive development shell.
dev: shell

# Open a one-off shell with the flake's default package.
tools:
	nix shell .

# Install the flake's packages into the user profile
install:
	nix profile add .

# Format the repo with the flake formatter.
fmt:
	nix fmt

# Run the flake's declarative checks.
check:
	nix flake check

# Build the container image (all dev packages, but no VSCode Remote support)
build:
	nix build .#containerImage

# Build the Ubuntu-based container image (VSCode Remote compatible)
build-ubuntu:
	nix build .#containerImageUbuntu

# Load the scratch container image
load: build
	$(CONTAINER_ENGINE) load < result

# Load the Ubuntu container image
load-ubuntu: build-ubuntu
	$(CONTAINER_ENGINE) load < result

# Run the container image
run: load
	$(CONTAINER_ENGINE) run --rm -it $(USERNS_FLAG) $(VOLUME_FLAG) $(IMAGE_NAME):latest

# Run the Ubuntu container image
run-ubuntu: load-ubuntu
	$(CONTAINER_ENGINE) run --rm -it $(USERNS_FLAG) $(VOLUME_FLAG) $(UBUNTU_IMAGE_NAME):latest

# Clean build artifacts and remove loaded container images
clean:
	rm -f result
	-$(CONTAINER_ENGINE) rmi $(IMAGE_NAME):latest 2>/dev/null || true
	-$(CONTAINER_ENGINE) rmi $(UBUNTU_IMAGE_NAME):latest 2>/dev/null || true
