# ADR-0017: Explicit Sync Config to Fix Binary File Type Filtering

## Status

Accepted

## Context

Users reported that images and other binary attachments were not syncing
from their Obsidian vault. Investigation revealed a bug in how
obsidian-headless applies default file type filtering.

### The bug

obsidian-headless's `ob sync-setup` command creates a stored config
object with these fields:

```javascript
{
  vaultId, vaultName, vaultPath, host,
  encryptionVersion, encryptionKey, encryptionSalt,
  conflictStrategy: "merge", deviceName, configDir
}
```

Notably, `allowTypes` and `allowSpecialFiles` are **not set**. These
fields are only written when `ob sync-config --file-types` or
`--configs` is explicitly called.

When `ob sync` loads the stored config and initializes the file filter,
it passes the config values through a fallback chain:

```javascript
// In the sync engine constructor:
this.filter.init(t.allowTypes || [], t.allowSpecialFiles || [], t.ignoreFolders || [])

// In the filter's init method:
init(e, t, i) {
  this.allowTypes = new Set(e || K);  // K = ["image","audio","pdf","video"]
  ...
}
```

The intent is: if `allowTypes` is not set in the config, fall back to
the default list `K`. However, the `||` fallback chain has a JavaScript
truthiness bug:

1. `t.allowTypes` is `undefined` (not set in stored config)
2. `undefined || []` evaluates to `[]` (empty array)
3. `[] || K` evaluates to `[]` (because empty arrays are **truthy** in
   JavaScript)
4. `new Set([])` creates an **empty set**
5. No binary file types pass the filter — images, audio, video, and
   PDFs are silently excluded from sync

The same bug affects `allowSpecialFiles`, meaning `.obsidian` config
files (app settings, themes, hotkeys, core plugins) are also not synced
unless explicitly configured.

Markdown (`.md`) and Canvas (`.canvas`) files are unaffected because
they bypass the type filter entirely in `_allowSyncFile()`.

### Options considered

**1. Fix the bug in obsidian-headless source**

Modify `cli.js` to use nullish coalescing (`??`) instead of logical OR
(`||`), or avoid the double-fallback pattern. This is the correct fix
but requires a change to an upstream package that this project does not
control. A PR could be submitted, but users need a fix now.

**2. Call `ob sync-config` after `ob sync-setup` to explicitly set
the values**

Run `ob sync-config --file-types image,audio,video,pdf --configs ...`
during container initialization. This writes the values to the stored
config, so when `ob sync` loads them, `t.allowTypes` is a real array
(not `undefined`), and the filter works correctly.

**3. Patch `cli.js` at build time**

Use `sed` or a script to fix the JavaScript in the Docker build. Fragile
— any obsidian-headless update would require updating the patch. Also
modifies a minified file, which is error-prone.

## Decision

Use option 2: **call `ob sync-config` after `ob sync-setup`** to
explicitly set file types and config categories.

Implementation:

- **New init step (step 9)**: After `ob sync-setup` succeeds (step 8),
  run `ob sync-config --path /vault --file-types ... --configs ...`.

- **New environment variables**:
  - `OBSIDIAN_GIT_SYNC_FILE_TYPES` — comma-separated list of attachment
    types. Default: `image,audio,video,pdf,unsupported` (everything).
    Valid values: `image`, `audio`, `video`, `pdf`, `unsupported`.
  - `OBSIDIAN_GIT_SYNC_CONFIGS` — comma-separated list of config
    categories. Default: all 8 categories (`app,appearance,
    appearance-data,hotkey,core-plugin,core-plugin-data,
    community-plugin,community-plugin-data`). This is more aggressive
    than Obsidian desktop's default (which excludes community plugins)
    but appropriate for a backup tool where completeness is paramount.

- **Idempotent**: `ob sync-config` updates the stored config in place.
  Running it on every container start is safe and ensures the filter
  settings always match the environment variables, even if the user
  changes them between restarts.

- **Runs on every start, not just first setup**: This is intentional.
  If a user changes `OBSIDIAN_GIT_SYNC_FILE_TYPES` in their `.env`
  and restarts the container, the new values take effect immediately.

## Consequences

**Easier:**

- Binary attachments (images, audio, video, PDFs) are synced by
  default. Users no longer need to know about or work around the
  obsidian-headless bug.
- Users can customize which file types sync via environment variables,
  without needing to exec into the container and run `ob sync-config`
  manually.
- The `unsupported` file type option lets users sync unusual file
  formats (`.blend`, `.psd`, `.ai`, etc.) that Obsidian doesn't
  categorize.
- Config category syncing is explicitly controlled. Users who want
  community plugin sync can add it via `OBSIDIAN_GIT_SYNC_CONFIGS`.

**Harder:**

- Two additional environment variables to document and maintain. Both
  have sensible defaults that match Obsidian's intended behavior, so
  most users never need to set them.
- If obsidian-headless fixes the truthiness bug in a future version,
  the `ob sync-config` call becomes redundant (but harmless). We
  should monitor upstream releases and consider removing the
  workaround if/when the fix ships.
- The `ob sync-config` call adds a small amount of startup time
  (~100ms). Negligible.
- The `OBSIDIAN_GIT_SYNC_FILE_TYPES` variable name could be confused
  with `OBSIDIAN_GIT_LFS_EXTENSIONS`. The former controls which files
  Obsidian Sync downloads; the latter controls which files Git LFS
  tracks. These are independent features. The naming (`SYNC_FILE_TYPES`
  vs `LFS_EXTENSIONS`) and documentation make the distinction clear.
