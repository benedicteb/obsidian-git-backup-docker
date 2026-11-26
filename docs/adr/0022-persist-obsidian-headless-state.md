# ADR-0022: Persist obsidian-headless State in /config

## Status

Accepted

## Context

obsidian-headless (0.0.14) keeps everything under
`$XDG_CONFIG_HOME/obsidian-headless`, defaulting to
`~/.config/obsidian-headless`:

```
obsidian-headless/
├── auth_token                 # only written by `ob login`
└── sync/<vault-id>/
    ├── config.json            # vault settings incl. derived encryption key
    ├── state.db               # SQLite: known local and server file state
    └── sync.log               # append-only copy of everything ob prints
```

For the `obsidian` user that is `/home/obsidian/.config`, which is not a
volume. Every container recreation (each Unraid edit, each image update)
discarded it, so:

- the next start was always an *initial* sync that re-checked every file;
- the device name defaulted to the container hostname, which also changes
  on recreation, so every recreate appeared as a new device in Obsidian
  Sync's version history.

`ob sync-setup` (run on every start) rewrites `config.json` but leaves
`state.db` alone; only `ob sync-unlink` deletes it. So persisting the
directory is enough for state to carry over.

Three hazards appear once the state is persistent:

1. **Shared `/config`.** The README allows several containers to share one
   `/config`. obsidian-headless finds a vault's config by its local path and
   takes the first match. That path is `/vault` in every container, so
   containers would pick up each other's configs.
2. **Stale vault configs.** If a vault is deleted and recreated under the
   same name, the old vault ID's config stays next to the new one, with the
   same path, and may be picked first.
3. **Replaced `/vault`.** The README says `/vault` can be re-cloned if lost.
   With persisted state, ob would read files missing from the new clone as
   local deletions and, in `bidirectional` mode, upload them to Obsidian
   Sync. Before this change every start was an initial sync, which merges
   instead.

There is also `sync.log`, which grows without rotation.

## Decision

1. Set `XDG_CONFIG_HOME=/config/headless/<vault name>` for every `ob` call,
   via `/usr/local/lib/headless-env.sh`, sourced by `init-config.sh` and the
   `obsidian-sync` service. The vault name is reduced to `[A-Za-z0-9._-]`
   (other characters become `_`; `.`/`..` are prefixed). This is scoped to
   ob, not set image-wide, so it does not change git's config lookup.
   **Per-vault directories** solve hazard 1.
2. After `sync-setup`, delete every other `sync/<id>/` in that directory;
   the one sync-setup just wrote is the newest. Solves hazard 2.
3. Pair state and vault clone with a random ID stored in
   `/vault/.git/obsidian-git-backup-state-id` (never committed, unique per
   clone) and `<state dir>/vault-state-id`. If either is missing or they
   differ, delete the sync state before `sync-setup`, so the next sync is an
   initial merge as before. Solves hazard 3.
4. Link `sync.log` to `/dev/null`; it duplicates the container log.
5. Add `OBSIDIAN_GIT_DEVICE_NAME`, default
   `obsidian-git-backup (<vault name>)`, passed as `--device-name` to
   `ob sync-config`.
6. Restrict the state directory to mode 700: `config.json` contains the
   derived vault encryption key.

## Consequences

- After the first start on this version, restarts and recreations resume
  from saved state instead of re-checking every file, and the device keeps
  one name in Obsidian Sync.
- The first start after upgrading behaves as before: there is no saved
  state yet, so it is an initial sync.
- `/config` now holds the derived vault encryption key, alongside the SSH
  private key that was already there. It must be kept private, as before.
- Renaming `OBSIDIAN_GIT_VAULT_NAME` (even to the vault's ID) uses a new
  state directory; the old one is left behind and can be deleted.
- Two vault names that only differ in replaced characters (e.g. `My Vault`
  and `My_Vault`) would share a directory. Unlikely, and only an issue if
  both run with the same `/config`.
- The marker only detects a replaced `.git`. Restoring an older copy of the
  same clone (same `.git`) is not detected.
- Manual `ob` commands via `docker exec` need
  `-e XDG_CONFIG_HOME=/config/headless/<vault>` to see the container's
  state.
