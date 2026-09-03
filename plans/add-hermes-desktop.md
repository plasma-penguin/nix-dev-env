# Add hermes-desktop to nix-dev-env

## Problem / goal

`nix-dev-env` already ships `hermes-agent` from [numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix). Users also need the official Hermes Desktop shell (`hermes-desktop`) in the same environment: `nix develop`, `nix shell .`, `nix profile add .`, and the Linux container images.

The goal is to add `hermes-desktop` the same way `hermes-agent` was added. Do not introduce a second packaging path.

## Current state

`hermes-agent` is not packaged in this repo. It is consumed as a flake package from `llm-agents`:

```nix
llmAgentPackages = with llm-agents.packages.${system}; [
  claude-code
  antigravity-cli
  codex
  grok
  opencode
  hermes-agent
];
```

That list is concatenated into `allPackages`, then into `installableEnv` (the flake `default` package). Dev shell, profile install, Dockerfile, Docker Sandbox templates, and both Nix-built container images all install that one env.

The original `hermes-agent` change ([126deb69](https://github.com/plasma-penguin/nix-dev-env/commit/126deb69d89017681a27b2fc2447994aa1716dbe)) was that list entry plus a lock bump so `llm-agents` actually exported the package. Same pattern as `grok`.

`llm-agents` already exports `hermes-desktop` at the revision pinned in `flake.lock` (`b7e6d6d4cb01ee1bc704db8e11629adec7e2509c`):

- Official Electron desktop for Hermes Agent
- `mainProgram = "hermes-desktop"`
- Depends on `hermes-agent` and wraps it via `HERMES_DESKTOP_HERMES`
- Platforms: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin` (same as `hermes-agent`)
- Linux: `/bin/hermes-desktop` wrapper, `/share/applications/hermes-desktop.desktop`, app files under `/share/hermes-desktop`
- Darwin: `/bin/hermes-desktop` wrapper around `Hermes.app`

NousResearch also exposes `nix run github:NousResearch/hermes-agent#desktop`. That is **not** how this repo packages `hermes-agent`. Using it here would be a divergent pattern.

## Approach

Add `hermes-desktop` to `llmAgentPackages` next to `hermes-agent`. Let the existing env / container / CI wiring pick it up.

Also extend `packageSmokeCheck` so both Hermes binaries are asserted the way the other LLM tools already are (`command -v claude`, `command -v grok`, …). `hermes-agent` never got that coverage; add it now because desktop launches the agent binary.

Do **not**:

- Add a `github:NousResearch/hermes-agent` flake input
- Vendor a local `package.nix`
- Export a new named flake output (`packages.hermes-desktop`) — `hermes-agent` is not exported that way
- Add a `profileAgents` wrapper — `hermes-agent` has none; desktop is not a CLI approval-bypass tool
- Add `/Applications` to `pathsToLink` — the Darwin `/bin` wrapper already points at the real store path
- Touch `flake.lock` unless evaluation proves the pin is missing the attribute (it is not)
- Document the package in `README.md` — individual LLM tools are not listed there

### Implementation steps (one PR)

1. Add `hermes-desktop` to `llmAgentPackages` in `flake.nix`.
2. In `packageSmokeCheck`:
   - `command -v hermes`
   - `command -v hermes-desktop`
   - `hermes --version` (CLI; safe in the sandbox)
   - Do **not** run `hermes-desktop --help` / launch Electron in the Nix check. That needs a display and is not how this check treats GUI apps.
   - On Linux only, `test -f ${installableEnv}/share/applications/hermes-desktop.desktop` (`pathsToLink` already includes `/share`).
3. `nix fmt` if the formatter rewrites anything.
4. Verify as below. Commit implementation on this same branch.

## File-level touch list

| File | Change |
| --- | --- |
| `flake.nix` | Add `hermes-desktop` to `llmAgentPackages`. Extend `packageSmokeCheck` for `hermes`, `hermes-desktop`, `hermes --version`, and the Linux desktop file. |
| `plans/add-hermes-desktop.md` | This plan (already in the PR). |

No changes expected:

- `flake.lock` — pin already has `hermes-desktop`
- `README.md`, `Makefile`, `Dockerfile`, `Dockerfile.sbx`, `.github/workflows/*`, `.devcontainer/devcontainer.json` — they install `.#default`

## Risks

- **Closure size.** Electron will grow the default package and both Linux container images. That matches how every other `llmAgentPackages` entry is shipped. CI already builds those images; expect longer builds and larger artifacts if the Numtide cache misses.
- **Cache miss.** Desktop is a heavier build (Electron, `node-pty` for Electron ABI). CI and local hosts already pin `https://cache.numtide.com`. If the cache lacks this output, `nix flake check` / image builds compile from source.
- **Headless containers.** Desktop is not useful without a display. Including it anyway keeps one env definition. Do not split a “GUI vs CLI” package set.
- **`x86_64-darwin`.** `llm-agents.nix` does not export that system; `hermes-desktop` does not list it. `hermes-agent` already has this limit. Out of scope.
- **GUI launch in CI / this VM.** Smoke check must not start Electron. Manual GUI verification is host-display dependent.
- **Weekly lock updates.** Future `llm-agents` bumps can change desktop version or Electron pins. That is already true for `hermes-agent`. No extra pin work here.

## Verification

### Automated (implementation must run these)

```bash
nix fmt
nix flake check
nix shell . -c bash -lc 'command -v hermes && command -v hermes-desktop && hermes --version'
nix develop -c bash -lc 'command -v hermes-desktop'
```

On Linux, also confirm the env contains the desktop entry:

```bash
nix build .#default
test -f result/share/applications/hermes-desktop.desktop
```

`nix flake check` already builds `packageSmokeCheck` and, on Linux, both container images. That is the CI path (`nix flake check` in `.github/workflows/ci.yml`).

Do not add new workflow jobs. The existing check covers the new package once it is in `installableEnv`.

### Manual / walkthrough artifacts (implementation)

This is a Nix toolchain change, not a web UI. Implementation walkthroughs should prove PATH + smoke, not a fake app demo.

**Screenshot — env provides both binaries**

```bash
nix shell . -c bash -lc 'command -v hermes; command -v hermes-desktop; hermes --version'
```

Must show real store paths and a Hermes version line.

**Screenshot or terminal capture — flake check**

`nix flake check` exiting 0 (or at least `nix build .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').defaultPackage` succeeding). That is the check CI runs.

**Screenshot — Linux desktop file (Linux only)**

`test -f result/share/applications/hermes-desktop.desktop` after `nix build .#default`, plus `cat` of that file showing `Exec=hermes-desktop`.

**Video — GUI launch, only if a display works**

If the implementation environment can start an X/Wayland session: record `hermes-desktop` opening the Hermes window, then quit. If Electron cannot start (no display, missing GPU, sandbox), do **not** upload a failing launch. The PATH / version / desktop-file artifacts are the proof. Note in the PR that GUI launch was skipped and why.

Do not record `nix flake update`, cache configuration, or unrelated package installs.
