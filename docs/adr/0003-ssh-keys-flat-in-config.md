# ADR-0003: SSH Keys Stored Flat in /config (Not /config/.ssh/)

## Status

Accepted

## Context

The original design stored SSH keys in `/config/.ssh/`, mirroring the
conventional `~/.ssh/` layout. This caused problems for users who bind-mount
a host directory into `/config`:

1. **Hidden directory is invisible by default.** On macOS Finder and in
   `ls` without `-a`, the `.ssh/` subdirectory doesn't appear. Users run
   `ls ./obsidian-config/` and see nothing, even though their key is there.

2. **Extra nesting complicates setup.** The bind-mount instructions
   required `mkdir -p ./obsidian-config/.ssh` followed by copying keys into
   the subdirectory. This is one more step that can go wrong.

3. **Some backup tools skip dotfiles.** Tools and scripts that don't
   process hidden files/directories by default could miss the SSH keys
   when backing up the config directory.

4. **No security benefit.** The conventional `700` permission on `~/.ssh/`
   provides an additional directory-level permission gate in multi-user
   systems. In a single-purpose Docker container with one non-root user,
   this adds no meaningful protection — the file-level `600` permission on
   the private key is sufficient.

### Options considered

**1. Keep `/config/.ssh/` (status quo)**

Familiar to SSH users but awkward for Docker bind mounts. Users must create
a hidden subdirectory and get permissions right on both the directory and
the files.

**2. Store keys flat in `/config/`**

Place `id_ed25519`, `ssh_config`, and `known_hosts` directly at the
`/config/` root. Simpler bind-mount experience. Slightly unconventional
for SSH, but the container uses `-F /config/ssh_config` explicitly so
SSH never looks at `~/.ssh/` at all.

**3. Use a visible subdirectory like `/config/ssh/`**

Provides namespacing without the dotfile visibility problem. Adds nesting
without clear benefit — `/config/` in this container only contains SSH
files (and potentially obsidian-headless state in the future, which would
live in its own subdirectory).

## Decision

Store SSH files directly in `/config/` (option 2):

- `/config/id_ed25519` — private key
- `/config/id_ed25519.pub` — public key
- `/config/ssh_config` — SSH client configuration (auto-generated if absent)
- `/config/known_hosts` — TOFU host key cache

Additional hardening applied during this change:

- **ssh_config is only generated if absent.** Users who bind-mount a custom
  `ssh_config` (e.g., for a ProxyJump or non-standard port) have it
  respected instead of silently overwritten.
- **chown failures are non-fatal.** On macOS, Docker cannot `chown`
  bind-mounted files to a different UID (see ADR-0002). The init script
  now warns instead of aborting.
- **known_hosts is pre-created** with correct ownership to avoid
  umask-dependent permissions when SSH first connects.
- **ssh_config is written with umask 077** to avoid a brief
  world-readable window.

## Consequences

**Easier:**

- Bind-mount setup is simpler: `mkdir ./obsidian-config && cp key ./obsidian-config/id_ed25519`
- Keys are visible in `ls` and Finder without special flags.
- Users can provide custom `ssh_config` and `known_hosts` without them
  being overwritten.

**Harder:**

- `/config/` is a flat namespace. If more config files are added in the
  future, they share space with SSH files. Acceptable for a
  single-purpose container, but worth monitoring.
- The layout is unconventional for SSH. Users familiar with `~/.ssh/`
  might look for that path. The README and log messages clearly document
  the actual paths.
