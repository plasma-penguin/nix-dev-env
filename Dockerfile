# Development image with the flake installed through a prebuilt Nix base image.
FROM nixos/nix

# Enable flakes + nix-command, trust the public Numtide cache explicitly,
# and keep containerized builds compatible with common runtimes that do not
# support Nix's extra seccomp layer.
RUN printf '%s\n' \
      'experimental-features = nix-command flakes' \
      'extra-substituters = https://cache.numtide.com' \
      'extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=' \
      'sandbox = false' \
    >> /etc/nix/nix.conf

WORKDIR /tmp
COPY flake.nix flake.lock ./

ARG NIX_DEV_ENV_PROFILE=/nix/var/nix/profiles/nix-dev-env

# Install the flake into a dedicated profile so it does not collide with the
# packages preinstalled in the nixos/nix base image.
RUN nix profile add .#default --profile "$NIX_DEV_ENV_PROFILE"

# Keep system tools first so /bin/bash wins, then prefer the dedicated flake
# profile over the base image's preinstalled Nix profile.
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${NIX_DEV_ENV_PROFILE}/bin:${NIX_DEV_ENV_PROFILE}/sbin:${PATH}"

# Set up system-wide profile scripts for login + interactive shells and add
# the repo-standard nonroot account.
RUN mkdir -p /etc/profile.d /etc/skel /app /home/nonroot && \
    cp "$NIX_DEV_ENV_PROFILE"/share/profile.d/*.sh /etc/profile.d/ && \
    cp "$NIX_DEV_ENV_PROFILE"/share/skel/.bashrc /etc/skel/.bashrc && \
    cp "$NIX_DEV_ENV_PROFILE"/share/skel/.bashrc /home/nonroot/.bashrc && \
    printf '%s\n' 'for f in /etc/profile.d/*.sh; do' '  . "$f"' 'done' > /etc/profile && \
    echo '. /etc/profile' > /etc/bash.bashrc && \
    if ! grep -q '^nonroot:' /etc/passwd; then \
      echo "nonroot:x:1000:1000:nonroot:/home/nonroot:${NIX_DEV_ENV_PROFILE}/bin/bash" >> /etc/passwd; \
    fi && \
    if ! grep -q '^nonroot:' /etc/group; then \
      echo 'nonroot:x:1000:' >> /etc/group; \
    fi && \
    chmod 0777 /home/nonroot /app

# Symlink system certs to the Nix cacert bundle
RUN . "$NIX_DEV_ENV_PROFILE"/share/profile.d/00-env.sh && \
    ln -snf "$SSL_CERT_DIR" /etc/ssl/certs

ENV HOME=/home/nonroot
ENV USER=nonroot


WORKDIR /app

# Drop to nonroot user
USER nonroot

# tini comes from the installed flake on PATH; run it as PID 1
ENTRYPOINT ["tini", "--"]

# Login + interactive bash by default
CMD ["bash", "-l", "-i"]
