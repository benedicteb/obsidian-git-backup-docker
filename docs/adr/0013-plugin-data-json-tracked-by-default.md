# ADR-0013: Track Plugin data.json by Default

## Status

Accepted

## Context

The vault `.gitignore` managed block included a blanket ignore pattern:

```
.obsidian/plugins/*/data.json
```

This was intended to reduce noisy commits from plugins that write
frequently to `data.json` (e.g., Dataview's index cache, Various
Complements' word frequency data).

However, `data.json` is the **only persistence mechanism** for Obsidian
plugins. Many plugins store irreplaceable user configuration there:

| Plugin | What's in data.json |
|---|---|
| Templater | Template folder path, script settings |
| Tasks | Global filter, date formats |
| QuickAdd | Macros, choice definitions |
| Periodic Notes | Daily note template path, folder |
| Kanban | Board settings |
| Excalidraw | Font settings, template paths |

The blanket ignore silently excluded these settings from backups. A
user restoring from the git backup would lose all plugin configuration
and have to reconfigure every plugin manually.

### Options considered

**1. Per-plugin ignores for known noisy plugins**

Ignore specific high-frequency writers (e.g.,
`.obsidian/plugins/dataview/data.json`) and track everything else.
Correct but creates a maintenance burden — the list of noisy plugins
grows over time and varies per user.

**2. Comment out the blanket ignore (let users opt in)**

Move `.obsidian/plugins/*/data.json` to a commented-out option with
a clear warning. Users who find plugin-settings churn unacceptable
can uncomment it, understanding the trade-off.

**3. Keep the blanket ignore (status quo)**

Accept incomplete backups in exchange for cleaner commit history.

## Decision

Use option 2: **track plugin data.json by default**, with the blanket
ignore available as a commented-out option with a warning.

The inotifywait exclude pattern in `git-watcher.sh` was also updated
to match — plugin data.json changes now trigger the watcher and are
committed to git.

## Consequences

**Easier:**

- Backups are complete by default. Restoring from git includes all
  plugin configuration.
- Users don't need to understand which plugins store settings vs caches
  in data.json.
- The commented-out option with its warning makes the trade-off
  explicit for users who want to opt in.

**Harder:**

- Plugins that write frequently to data.json (Dataview, Various
  Complements) will generate more commits. The debounce window in
  git-watcher mitigates this somewhat, but users with many such
  plugins may see noisier commit history.
- Users upgrading from a previous version will see data.json files
  appear in their next commit as the ignore pattern is removed. This
  is a one-time event and is the desired behaviour (recovering
  previously-excluded settings).
