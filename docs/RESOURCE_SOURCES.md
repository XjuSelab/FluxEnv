# Resource Sources

This repository now centralizes external downloads in [`resources/manifest.lock`](../resources/manifest.lock) and fetches them through [`scripts/fetch_resources.sh`](../scripts/fetch_resources.sh). Runtime install scripts should consume files from `offline_resources/` instead of embedding `curl`, `wget`, or `git clone` calls inline.

Current buckets:

- `starship-*`: prompt installer script and pinned `1.24.1` x86_64 binary.
- `zsh-*`: pinned plugin commits mirrored into `offline_resources/`.
- `vim-config` and `vundle`: currently tracked as upstream Git mirrors with `HEAD`; pin to a commit after the first reviewed fetch.
- `docker-*`, `nodesource-*`, `pnpm-*`: legacy helper dependencies moved into the manifest so they are auditable even before those helper scripts are fully migrated.

Recommended workflow:

1. Run `./scripts/fetch_resources.sh` on a connected machine.
2. Review fetched artifacts and pin any `HEAD` entries to a commit.
3. Commit the updated resource tree before using `bin/fluxenv` on offline targets.
