# ADR-0021: Configurable Sync Mode via OBSIDIAN_GIT_SYNC_MODE

## Status

Accepted

## Context

obsidian-headless 0.0.14 supports three sync modes through
`ob sync-config --mode`:

- `bidirectional`: download remote changes and upload local changes
- `pull-only`: download only; local changes are ignored (never uploaded)
- `mirror-remote`: download only; local edits are reverted, locally-deleted
  files are restored, and local-only files are deleted

Before this change the image never passed `--mode`, so every install ran
obsidian-headless's default, `bidirectional`.

This container writes into `/vault` itself: `git-watcher.sh` runs
`git pull` periodically (`OBSIDIAN_GIT_PULL_INTERVAL`) and before every
push. With `bidirectional`, anything changed on the git remote is pushed to
Obsidian Sync. With `mirror-remote`, files that exist only in git are
deleted locally, and the watcher commits and pushes those deletions.

## Decision

1. Add `OBSIDIAN_GIT_SYNC_MODE`, passed as `--mode` to `ob sync-config` in
   step 9 of `init-config.sh` on every start.

2. **Default to `bidirectional`.** `pull-only` is the safer choice for a
   backup container, but changing the default would change behaviour for
   every existing install. Keeping `bidirectional` makes this release a
   no-op for users who do not set the variable. A later switch to
   `pull-only` should be its own, clearly announced release (likely major).

3. **Strict validation, no normalization.** The value must be exactly one
   of the three modes. Whitespace or different casing fails startup with an
   error that quotes the value and lists the valid ones, so typos are
   noticed rather than silently fixed.

4. Document `pull-only` as recommended for backup-only setups, and warn
   that `mirror-remote` deletes git-only files from the backup branch.

## Consequences

- Users can stop the container from pushing git-side changes to Obsidian
  Sync by setting `pull-only`.
- The env var is applied on every start and always wins over any mode
  stored in obsidian-headless's own config. In practice no manual setting
  is lost: obsidian-headless stores its config under
  `~/.config/obsidian-headless` (`/home/obsidian`), which is not a volume,
  so it was already discarded whenever the container was recreated.
- `mirror-remote` is allowed but destructive in combination with the git
  pull loop. It is documented, not blocked.
- Not addressed here: obsidian-headless state (config, sync state) is not
  persisted across container recreation. Each recreate appears as a new
  device and re-checks every file. This deserves a separate decision.
