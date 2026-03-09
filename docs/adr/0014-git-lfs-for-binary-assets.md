# ADR-0014: Git LFS for Binary Assets

## Status

Accepted

## Context

Obsidian vaults frequently contain binary attachments — images (PNG,
JPEG), PDFs, audio recordings, videos, and office documents. When
these files are committed directly to a git repository:

1. **Repository bloat.** Binary files don't compress or delta-encode
   well. A vault with 200 MB of images produces a 200 MB+ `.git`
   directory. Every clone downloads the full history of every binary.

2. **Slow clones.** Users restoring from backup or setting up a new
   container must download the entire git history, including every
   version of every binary file ever committed.

3. **Provider storage limits.** GitHub (1 GB soft limit), GitLab
   (10 GB), and self-hosted Gitea instances all have repository size
   thresholds. A vault with regular screenshot or PDF attachments can
   hit these limits within months.

Git LFS (Large File Storage) solves this by storing binary content on
a separate LFS server while keeping lightweight pointer files in the
git repository. Only the current version of each binary is downloaded
on clone.

### Options considered

**1. Enable LFS by default with a curated extension list**

Install `git-lfs` in the image, enable it by default, and track a
comprehensive list of binary file extensions commonly found in Obsidian
vaults. Users who don't want LFS can disable it. Users who need a
different extension list can override it.

**2. Opt-in LFS (disabled by default)**

Install the package but require users to set
`OBSIDIAN_GIT_LFS_ENABLED=true`. Safer — no surprise LFS behaviour —
but most users with binary attachments would benefit and wouldn't know
to enable it.

**3. No LFS support**

Leave binary handling to the user. They could configure LFS manually
by bind-mounting a custom `.gitattributes`, but this requires
understanding both LFS and the container's managed-block system.

## Decision

Use option 1: **enable Git LFS by default** with a configurable
extension list.

Implementation details:

- **Package**: `git-lfs` is installed via `apk add` alongside `git`.
  On Alpine 3.21 (node:22-alpine), the package is ~4 MB.

- **Initialization**: `git lfs install --local` is run per-repo
  during `init-config.sh` (step 6). The `--local` flag writes LFS
  configuration to `/vault/.git/config` instead of the global
  `~/.gitconfig`, keeping the setup repo-scoped and avoiding
  interference with other potential git operations.

- **LFS pull after clone**: `git lfs pull` runs after LFS
  initialization to ensure the working tree contains real binary
  content, not LFS pointer stubs. This is critical: if
  obsidian-headless synced on top of pointer files, it would push
  those stubs to Obsidian Sync, corrupting binary files on all
  connected devices.

- **Extension tracking**: A managed `.gitattributes` block (using the
  same marker-based pattern as `.gitignore`) maps file extensions to
  LFS tracking rules (`filter=lfs diff=lfs merge=lfs -text`).

- **Default extensions**: The default list covers common Obsidian
  vault binary attachments:
  - Images: png, jpg, jpeg, gif, bmp, webp, tif, tiff
  - Video: mp4, mov, avi, mkv, webm
  - Audio: mp3, wav, ogg, flac, m4a, aac
  - Documents: pdf, doc, docx, xls, xlsx, ppt, pptx
  - Archives: zip, tar, gz, 7z, rar
  - Fonts: woff, woff2, ttf, otf (used by Obsidian themes)

  Notable exclusions from the default list:
  - **SVG** — XML text format. Diffs meaningfully, compresses well
    in git, and renders natively on GitHub. Users with very large
    auto-exported SVGs can add `svg` via the override.
  - **Excalidraw** (`.excalidraw`) — JSON text with embedded
    base64 image data. Despite being large, they delta-compress
    better as text in git than as opaque blobs in LFS.
  - **Canvas** (`.canvas`) — Obsidian's native canvas format, JSON
    text. Should not go into LFS.

- **Override mechanism**: `OBSIDIAN_GIT_LFS_EXTENSIONS` accepts a
  comma-separated list of extensions (with or without leading dots).
  This completely replaces the default list — it is not additive.
  An additive syntax (e.g., `+excalidraw`) was considered but
  rejected to avoid parser complexity: the shell parser would need
  to distinguish prefix characters from literal extension names,
  and an extension genuinely starting with `+` would become
  ambiguous.

- **Disable mechanism**: `OBSIDIAN_GIT_LFS_ENABLED=false` skips all
  LFS setup. The `git-lfs` package remains installed but inactive.

- **Transparency**: `git add`, `git commit`, and `git push` work
  without changes in `git-watcher.sh`. LFS hooks handle the
  smudge/clean filters (on add/checkout) and LFS object upload
  (on push) transparently.

- **SSH transport**: LFS uses the same SSH transport as regular git.
  The `core.sshCommand` set by init-config (step 5) applies to LFS
  operations automatically.

## Consequences

**Easier:**

- Vaults with binary attachments produce small, fast-cloning git
  repositories by default. No user configuration needed.
- The extension list is customisable for users with unusual file
  types via `OBSIDIAN_GIT_LFS_EXTENSIONS`.
- LFS is fully transparent to the git-watcher — no changes to the
  commit/push logic were needed.
- Users can disable LFS with a single environment variable if their
  git remote doesn't support it.
- The managed-block pattern in `.gitattributes` allows the extension
  list to be updated on image upgrades without losing user-added
  entries.

**Harder:**

- The git remote must support LFS. All major providers (GitHub,
  GitLab, Gitea, Forgejo, Bitbucket) do, but self-hosted bare repos
  without an LFS server will fail on push. The error message from
  `git lfs` in this case is clear ("LFS server not found").
- LFS adds ~4 MB to the Docker image (`git-lfs` package).
- Enabling LFS on an existing repo does not migrate previously
  committed binaries. Only new or modified files are stored via LFS.
  Manual migration requires `git lfs migrate` (documented in README).
- LFS has provider-specific storage and bandwidth limits (e.g.,
  GitHub Free: 1 GB storage, 1 GB/month bandwidth). Users with many
  large binaries may need a paid plan or self-hosted LFS server.
- The `OBSIDIAN_GIT_LFS_EXTENSIONS` override replaces the entire
  default list. Users who want to add one extension must copy the
  full default list and append their addition.
- `.gitattributes` at the vault root will be synced to all Obsidian
  devices via Obsidian Sync. It is inert (Obsidian ignores it) but
  visible in the mobile file explorer. Users running the Obsidian Git
  plugin on a desktop simultaneously may see minor conflicts with the
  managed block, which self-resolve on next container restart.
