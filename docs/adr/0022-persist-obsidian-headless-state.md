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
3. **Saved state no longer matching `/vault`.** With saved state, ob treats
   any known file missing from `/vault` as a local deletion and, in
   `bidirectional` mode, deletes it on Obsidian Sync. An *initial* sync
   (no saved state) ignores server deletions, downloads missing files and
   resolves conflicts by newest mtime — it deletes nothing. Before this
   change every start was an initial sync. Ways `/vault` can diverge:
   re-cloned after loss (the README allows this), files deleted while the
   container was stopped, or `state.db` written by a different
   obsidian-headless version (it has a schema version but no migrations).

There is also `sync.log`, which grows without rotation.

## Decision

1. Set `XDG_CONFIG_HOME=/config/headless/<name>-<cksum>` for every `ob`
   call, via `/usr/local/lib/headless-env.sh`, sourced by `init-config.sh`
   and the `obsidian-sync` service. `<name>` is the vault name reduced to
   `[A-Za-z0-9._-]` (others become `_`); `<cksum>` is the checksum of the raw
   name, because BusyBox `tr` works per byte and non-ASCII names of equal
   length would otherwise collide. This is scoped to ob, not set
   image-wide, so it does not change git's config lookup. **Per-vault
   directories** solve hazard 1.
2. Before `sync-setup`, delete every stored `config.json` (state.db stays).
   `sync-setup` writes a config only for the vault it resolves, so
   afterwards every `sync/<id>/` without a `config.json` is stale and is
   deleted. No mtime comparison, so clock skew or a restored `/config`
   can't pick the wrong one. Solves hazard 2.
3. Discard the sync state before `sync-setup`, so the next sync is an
   initial merge, when any of these hold:
   - a random ID stored in `/vault/.git/obsidian-git-backup-state-id`
     (never committed, unique per clone) and `<state dir>/vault-state-id`
     is missing or differs (re-cloned or replaced `/vault`);
   - `ob --version` differs from the one saved with the state;
   - `git ls-files --deleted` reports tracked files missing from `/vault`.
   Solves hazard 3 for the detectable cases.
4. Link `sync.log` to `/dev/null`; it duplicates the container log.
5. Add `OBSIDIAN_GIT_DEVICE_NAME`, default
   `obsidian-git-backup (<vault name>)`, passed as `--device-name` to
   `ob sync-config`.
6. Restrict the state directory to mode 700 (warn, don't fail, where the
   filesystem rejects chmod): `config.json` contains the derived vault
   encryption key.
7. Run deletions inside the state tree as the `obsidian` user, who owns it,
   so root never follows links planted there.

## Consequences

- After the first start on this version, restarts and recreations resume
  from saved state instead of re-checking every file, and the device keeps
  one name in Obsidian Sync.
- The first start after upgrading behaves as before: there is no saved
  state yet, so it is an initial sync. So does the first start after each
  obsidian-headless version bump.
- `/config` now holds the derived vault encryption key, alongside the SSH
  private key that was already there. It must be kept private, as before.
- Renaming `OBSIDIAN_GIT_VAULT_NAME` (even to the vault's ID) uses a new
  state directory; the old one is left behind and can be deleted.
- `state.db` is SQLite in WAL mode, which can corrupt on network and FUSE
  filesystems. `/config` used to hold only small files; it should now be on
  a local filesystem (on Unraid, `/mnt/cache` rather than `/mnt/user`).
  Documented, not enforced.
- Restoring an older copy of the *same* clone (same `.git`, all tracked
  files present) is not detected. Files created after that backup are in
  the saved state but missing on disk, and would be deleted on Obsidian
  Sync. The README tells users to delete `headless/` after a restore.
- Files deleted from `/vault` while stopped are only detected if git
  tracks them; an untracked-and-uncommitted file deleted while stopped is
  uploaded as a deletion. git-watcher commits shortly after changes, so
  the window is small.
- Two containers for the same vault sharing one `/config` would reset each
  other's state on every start. They must not run together anyway.
- With the default device name, two containers for the same vault look
  the same in version history; set `OBSIDIAN_GIT_DEVICE_NAME` per container
  to tell them apart.
- Manual `ob` commands via `docker exec` need `-e XDG_CONFIG_HOME=<state
  dir>` (printed at startup) to see the container's state.
