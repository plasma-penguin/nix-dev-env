{
  description = "Cross-platform Nix development environment with scratch and Ubuntu container images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
      llm-agents,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs) lib;
        inherit (pkgs.stdenv) isLinux;
        repoDescription = "Cross-platform Nix development environment with scratch and Ubuntu container images";
        sourceUrl = "https://github.com/plasma-penguin/nix-dev-env";

        inherit (pkgs.playwright-driver) browsers;
        chromiumDir = builtins.head (
          builtins.filter (d: builtins.match "chromium-.*" d != null) (
            builtins.attrNames (builtins.readDir browsers)
          )
        );
        chromeSubdir = builtins.head (
          builtins.filter (d: builtins.match "chrome-.*" d != null) (
            builtins.attrNames (builtins.readDir "${browsers}/${chromiumDir}")
          )
        );
        chromePath = "${browsers}/${chromiumDir}/${chromeSubdir}/chrome";

        # ---------------- Cross-platform Packages ----------------
        commonPackages = with pkgs; [
          # Shell & UX
          bash
          bash-completion
          cacert
          coreutils
          gnugrep
          gnused
          gawk
          file
          less
          watch
          man
          ncurses
          which

          # Editors & utils
          vim
          nano
          tree
          jq
          yq
          zip
          unzip
          gnutar
          xz
          ripgrep
          fd
          bat
          fzf
          delta
          eza

          # Networking & diagnostics
          openssh
          curl
          wget
          netcat
          bind
          nmap
          lsof
          tcpdump
          iftop

          # Dev & build
          git
          git-lfs
          gnumake
          shellcheck
          tmux
          htop
          gcc
          go
          # gotools
          golangci-lint
          gopls
          delve
          python3
          python3Packages.pip
          python3Packages.flake8
          python3Packages.black
          nodejs
          tailwindcss_4
          playwright-test
          playwright-driver.browsers
          postgresql
          sqlite
          doctl
        ];

        llmAgentPackages = with llm-agents.packages.${system}; [
          claude-code
          gemini-cli
          codex
          opencode
        ];

        # ---------------- Linux-only Packages ----------------
        linuxPackages = with pkgs; [
          # Users
          shadow
          procps
          podman

          # Networking & diagnostics (Linux-specific)
          traceroute
          iputils
          iproute2

          # Dev & build (Linux-specific)
          glibc.dev

          # Init
          tini
        ];

        # ---------------- All Packages ----------------
        allPackages = commonPackages ++ llmAgentPackages ++ lib.optionals isLinux linuxPackages;

        # ---- Shell snippets for /etc/profile.d ----
        profileEnv = pkgs.writeText "00-env.sh" ''
          export LANG=C.UTF-8
          export LC_ALL=C.UTF-8
          export CC=gcc

          # User-installed Go tools should live in the writable home directory,
          # not under an immutable Nix profile.
          export GOPATH="''${GOPATH:-$HOME/go}"
          export GOBIN="''${GOBIN:-$GOPATH/bin}"
          case ":$PATH:" in
            *":$GOBIN:"*) ;;
            *) export PATH="$PATH:$GOBIN" ;;
          esac

          # TLS trust
          export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          export SSL_CERT_DIR=${pkgs.cacert}/etc/ssl/certs

          # Playwright
          export PLAYWRIGHT_BROWSERS_PATH=${browsers}
          export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
          export CHROME_PATH=${chromePath}
        '';

        profileCompletion = pkgs.writeText "10-completion.sh" ''
          . ${pkgs.bash-completion}/share/bash-completion/bash_completion
        '';

        profilePrompt = pkgs.writeText "20-prompt.sh" ''
          shopt -s histappend cmdhist checkwinsize
          export HISTSIZE=100000
          export HISTFILESIZE=200000
          export HISTCONTROL=ignoredups:erasedups
          export PROMPT_COMMAND='history -a; history -n; '"$PROMPT_COMMAND"

          . ${pkgs.git}/share/git/contrib/completion/git-prompt.sh

          export GIT_PS1_SHOWDIRTYSTATE=1
          export GIT_PS1_SHOWUPSTREAM=auto

          # Define colors (shell variables)
          RED='\[\033[0;31m\]'
          GREEN='\[\033[0;32m\]'
          BLUE='\[\033[0;34m\]'
          YELLOW='\[\033[0;33m\]'
          CYAN='\[\033[0;36m\]'
          RESET='\[\033[0m\]'

          # Prompt: [nix-dev] user@host:cwd (gitbranch)
          PS1="''${BLUE}[nix-dev]''${RESET} ''${GREEN}\u@\h''${RESET}:''${YELLOW}\w''${RESET}"
          # Escape `$` so __git_ps1 runs each time the prompt is drawn.
          PS1+="''${CYAN}\$(__git_ps1 ' (%s)')''${RESET}\$ "

          alias ll='ls -alF'
          alias la='ls -A'
          alias l='ls -CF'
          command -v grep >/dev/null 2>&1 && alias grep='grep --color=auto'
          command -v ls   >/dev/null 2>&1 && alias ls='ls --color=auto'
        '';

        userBashrc = pkgs.writeText "user.bashrc" ''
          if [ -f /etc/profile ]; then . /etc/profile; fi
        '';

        shellSupport = pkgs.runCommand "nix-dev-env-shell-support" { } ''
          mkdir -p "$out/share/profile.d" "$out/share/skel"
          cp ${profileEnv}        "$out/share/profile.d/00-env.sh"
          cp ${profileCompletion} "$out/share/profile.d/10-completion.sh"
          cp ${profilePrompt}     "$out/share/profile.d/20-prompt.sh"
          cp ${userBashrc}        "$out/share/skel/.bashrc"
        '';

        installableEnv = pkgs.buildEnv {
          name = "nix-dev-env";
          paths = allPackages ++ [ shellSupport ];
          pathsToLink = [
            "/bin"
            "/share"
          ];
        };

        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          settings.global.excludes = [ "flake.lock" ];
          programs.deadnix.enable = true;
          programs.nixfmt.enable = true;
          programs.shfmt.enable = true;
          programs.statix.enable = true;
        };

        shellHook = ''
          . ${profileEnv}
          . ${profileCompletion}
          . ${profilePrompt}
        '';

        containerProfile = pkgs.writeText "container-profile" ''
          for f in /etc/profile.d/*.sh; do
            . "$f"
          done
        '';

        containerPasswd = pkgs.writeText "container-passwd" ''
          root:x:0:0:root:/root:/bin/bash
          nonroot:x:1000:1000:nonroot:/home/nonroot:/bin/bash
          nobody:x:65534:65534:nobody:/nonexistent:/bin/false
        '';

        containerGroup = pkgs.writeText "container-group" ''
          root:x:0:
          nonroot:x:1000:
          nogroup:x:65534:
        '';

        containerBashBashrc = pkgs.writeText "container-bash.bashrc" ''
          . /etc/profile
        '';

        # ---- Common container image settings ----
        containerExtraCommands = lib.concatLines [
          "#!${pkgs.bash}/bin/bash"
          "set -euxo pipefail"
          ""
          "# `extraCommands` runs while assembling the image filesystem tree."
          "# Use relative paths so we write into the image root, not the builder's real '/'."
          "mkdir -p etc/profile.d etc/skel root tmp app home/nonroot etc/ssl usr/bin"
          ""
          "# Many scripts expect /usr/bin/env"
          "ln -sf /bin/env usr/bin/env || true"
          "chmod 1777 tmp"
          "chmod 0777 app"
          "# Make HOME writable without relying on chown/fakeroot"
          "chmod 0777 home/nonroot"
          ""
          "# Global profile loader"
          "install -m 0644 ${containerProfile} etc/profile"
          ""
          "# Profile snippets"
          "install -m 0644 ${profileEnv}        etc/profile.d/00-env.sh"
          "install -m 0644 ${profileCompletion} etc/profile.d/10-completion.sh"
          "install -m 0644 ${profilePrompt}     etc/profile.d/20-prompt.sh"
          ""
          "# Skeleton files"
          "install -m 0644 ${userBashrc} etc/skel/.bashrc"
          "# `useradd --create-home` would normally copy this into the user's home."
          "# Since we don't run useradd/groupadd during image assembly, do it explicitly."
          "install -m 0644 ${userBashrc} home/nonroot/.bashrc"
          ""
          "# --- Users ---"
          "# Avoid useradd/groupadd here: during dockerTools image assembly we may not have"
          "# all the OS config files those tools expect. For containers, minimal passwd/group"
          "# entries are sufficient for `User = \"nonroot\"` to resolve."
          "install -m 0644 ${containerPasswd} etc/passwd"
          "install -m 0644 ${containerGroup} etc/group"
          "install -m 0644 ${containerBashBashrc} etc/bash.bashrc"
          ""
          "# TLS trust (ensure it's a symlink, not a directory)"
          "rm -rf etc/ssl/certs"
          "ln -sfn ${pkgs.cacert}/etc/ssl/certs etc/ssl/certs"
          ""
          "# Playwright Chromium symlink at /opt/google/chrome/chrome"
          "mkdir -p opt/google/chrome"
          "ln -sf ${chromePath} opt/google/chrome/chrome"
        ];

        containerLabels = {
          "org.opencontainers.image.description" = repoDescription;
          "org.opencontainers.image.source" = sourceUrl;
          "org.opencontainers.image.url" = sourceUrl;
        }
        // lib.optionalAttrs (self ? rev) {
          "org.opencontainers.image.revision" = self.rev;
        };

        containerConfigFor = title: extraLabels: {
          Entrypoint = [
            "/bin/tini"
            "--"
          ];
          Env = [
            "HOME=/home/nonroot"
            "USER=nonroot"
          ];
          Labels =
            containerLabels
            // {
              "org.opencontainers.image.title" = title;
            }
            // extraLabels;
          User = "nonroot";
          WorkingDir = "/app";
          Cmd = [
            "bash"
            "-l"
            "-i"
          ];
        };

        packageSmokeCheck =
          pkgs.runCommand "nix-dev-env-package-smoke-check"
            {
              nativeBuildInputs = [ installableEnv ];
            }
            ''
              set -euo pipefail

              command -v bash >/dev/null
              command -v git >/dev/null
              command -v go >/dev/null
              command -v node >/dev/null
              command -v python >/dev/null
              command -v claude >/dev/null
              command -v gemini >/dev/null
              command -v codex >/dev/null

              test -f ${installableEnv}/share/profile.d/00-env.sh
              test -f ${installableEnv}/share/profile.d/10-completion.sh
              test -f ${installableEnv}/share/profile.d/20-prompt.sh
              test -f ${installableEnv}/share/skel/.bashrc

              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              . ${profileEnv}

              test "$GOPATH" = "$HOME/go"
              test "$GOBIN" = "$GOPATH/bin"
              case ":$PATH:" in
                *":$GOBIN:"*) ;;
                *) echo "GOBIN is missing from PATH" >&2; exit 1 ;;
              esac

              touch "$out"
            '';

        scratchContainerImage =
          if isLinux then
            pkgs.dockerTools.buildImage {
              name = "nix-dev-env";
              tag = "latest";
              copyToRoot = installableEnv;
              extraCommands = containerExtraCommands;
              config = containerConfigFor "nix-dev-env" {
                "org.opencontainers.image.base.name" = "scratch";
              };
            }
          else
            null;

        ubuntuContainerImage =
          if isLinux then
            let
              ubuntuImageDigest = "sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b";
              ubuntuImageHashes = {
                "x86_64-linux" = "sha256-kb//V7K505fUXth8qHeVK1AlayGYCEYK5vZPidLFNjE=";
                "aarch64-linux" = "sha256-A+huKbPcWFvrcBIZh4Khhcp4gWl0Fo+M98sR0wULxKY=";
              };
            in
            pkgs.dockerTools.buildImage {
              name = "nix-dev-env-ubuntu";
              tag = "latest";
              fromImage = pkgs.dockerTools.pullImage {
                imageName = "ubuntu";
                imageDigest = ubuntuImageDigest;
                sha256 = ubuntuImageHashes.${system};
                finalImageName = "ubuntu";
                finalImageTag = "latest";
              };
              copyToRoot = installableEnv;
              extraCommands = containerExtraCommands;
              config = containerConfigFor "nix-dev-env-ubuntu" {
                "org.opencontainers.image.base.name" = "docker.io/library/ubuntu:latest";
              };
            }
          else
            null;
      in
      {
        packages = {
          # Supports `nix shell .` and `nix profile add .`.
          default = installableEnv;
        }
        // lib.optionalAttrs isLinux {
          # Container image (Linux only) - scratch base
          containerImage = scratchContainerImage;

          # Container image with an Ubuntu base (Linux only)
          containerImageUbuntu = ubuntuContainerImage;
        };

        checks = {
          defaultPackage = packageSmokeCheck;
          formatting = treefmtEval.config.build.check self;
        }
        // lib.optionalAttrs isLinux {
          containerImage = scratchContainerImage;
          containerImageUbuntu = ubuntuContainerImage;
        };

        formatter = treefmtEval.config.build.wrapper;

        devShells.default = pkgs.mkShell {
          name = "nix-dev-env";
          packages = [ installableEnv ];
          inherit shellHook;

        };
      }
    );
}
