# FluxEnv

FluxEnv is a Bash-based environment bootstrap toolkit for Ubuntu/Debian hosts, AutoDL containers, and root-only container sessions.

## Entry Points

- `scripts/fluxenv`: unified orchestrator
- `scripts/fetch_resources.sh`: unified offline resource fetch entry

## Repository Layout

- `lib/`: shared runtime, config loader, and installation step modules
- `config/`: built-in profiles, example override config, and resource manifest
- `offline_resources/`: cached third-party assets consumed at install time

## Typical Usage

Fetch offline resources on a connected machine:

```bash
./scripts/fetch_resources.sh
```

Run the standard host bootstrap interactively:

```bash
sudo ./scripts/fluxenv --profile standard
```

When `standard` is started through `sudo` by a normal user, FluxEnv reuses that current user and skips new-user creation. When it is started from a pure root session, it keeps the original create-a-new-user flow.

Run a profile with explicit config:

```bash
sudo ./scripts/fluxenv --profile autodl-user --config ./config/example.env --non-interactive
```

## Notes

- Install flow defaults to switching Ubuntu apt sources to Tsinghua mirrors before `apt update`. Override with `ENABLE_APT_MIRROR=0` or custom `APT_UBUNTU_MIRROR` values in a config file.
- Apt source backups are written to `/var/backups/fluxenv/apt/`, so `sources.list.d` stays clean and `apt update` does not emit backup-file warnings.
- Install flow defaults to offline resources first. Online fallback is disabled unless `ALLOW_ONLINE_FETCH=1`.
- Runtime system changes are implemented in step modules under `lib/steps/`, not in the wrapper scripts.
- Resource provenance is documented in `docs/RESOURCE_SOURCES.md`.
