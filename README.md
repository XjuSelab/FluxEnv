# FluxEnv

FluxEnv is a Bash-based environment bootstrap toolkit for Ubuntu/Debian hosts, AutoDL containers, and root-only container sessions.

## Entry Points

- `bin/fluxenv`: unified orchestrator
- `scripts/fetch_resources.sh`: unified offline resource fetch entry

## Repository Layout

- `lib/`: shared runtime, config loader, and installation step modules
- `profiles/`: built-in profile defaults
- `configs/example.env`: override template for non-interactive runs
- `resources/manifest.lock`: auditable external download manifest
- `offline_resources/`: cached third-party assets consumed at install time
- `scripts/apps/`: standalone service and tool installers

## Typical Usage

Fetch offline resources on a connected machine:

```bash
./scripts/fetch_resources.sh
```

Run the standard host bootstrap interactively:

```bash
sudo ./bin/fluxenv --profile standard
```

Run a profile with explicit config:

```bash
sudo ./bin/fluxenv --profile autodl-user --config ./configs/example.env --non-interactive
```

## Notes

- Install flow defaults to switching Ubuntu apt sources to Tsinghua mirrors before `apt update`. Override with `ENABLE_APT_MIRROR=0` or custom `APT_UBUNTU_MIRROR` values in a config file.
- Install flow defaults to offline resources first. Online fallback is disabled unless `ALLOW_ONLINE_FETCH=1`.
- Runtime system changes are implemented in step modules under `lib/steps/`, not in the wrapper scripts.
- Resource provenance is documented in `docs/RESOURCE_SOURCES.md`.
