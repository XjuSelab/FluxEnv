# Repository Guidelines

## Project Structure & Module Organization
This repository is a collection of Bash automation for provisioning Ubuntu-like hosts. The main entry point is `bin/fluxenv`. Reusable one-off installers live in `scripts/apps/` (for example `scripts/apps/nginx_setup.sh`, `scripts/apps/node_setup.sh`, `scripts/apps/maven_setup.sh`). Shared installation logic lives in `lib/` and `lib/steps/`. Bundled third-party assets and offline installers live in `offline_resources/`; treat that directory as curated vendor content and avoid casual edits there.

## Build, Test, and Development Commands
There is no compiled build step. Use shell validation and targeted dry runs instead:

- `bash -n bin/fluxenv lib/*.sh lib/steps/*.sh` checks runtime syntax before committing.
- `bash -n scripts/apps/*.sh` validates helper scripts in bulk.
- `bash scripts/fetch_resources.sh` refreshes cached installers and plugin mirrors.
- `sudo bash bin/fluxenv --profile standard` runs the full interactive bootstrap on a disposable host or VM.
- `sudo bash scripts/apps/nginx_setup.sh` exercises a single installer script.

Run scripts only on test machines; many commands modify packages, users, SSH, and system services.

## Coding Style & Naming Conventions
Use Bash with a `#!/bin/bash` shebang and 4-space indentation, matching the existing scripts. Prefer lowercase snake_case for function names and variables such as `show_stage` or `host_name`. Name new utility scripts with a verb-focused suffix pattern like `*_setup.sh`; keep orchestration scripts under `bin/` and helper installers under `scripts/apps/`. Keep user-facing progress messages explicit, and validate destructive or privileged operations before execution. If `shellcheck` is available locally, run it on changed scripts before opening a PR.

## Testing Guidelines
This repo does not currently ship an automated test suite. Minimum validation is `bash -n` on every changed script plus one realistic manual run in an Ubuntu VM, container, or throwaway server. Document the environment you tested, such as `Ubuntu 24.04 x86_64`, and note any interactive prompts or package-manager assumptions.

## Commit & Pull Request Guidelines
Recent history uses short Conventional Commit prefixes such as `feat:`, `fix:`, and `style:`. Follow that format, for example `fix: harden nginx OS detection`. PRs should describe the scenario changed, list the scripts touched, and include manual verification notes. When output or prompts changed, paste a short terminal transcript instead of screenshots.
