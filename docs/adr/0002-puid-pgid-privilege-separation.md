# ADR-0002: PUID/PGID Runtime User Identity

## Status

Accepted

## Context

The container was running all services as root (UID 0). When users mounted
host directories (bind mounts) into the container — particularly on macOS —
they encountered "permission denied" errors because:

1. Files created by root inside the container are inaccessible to the host
   user (e.g., UID 501 on macOS).
2. Files owned by the host user are sometimes inaccessible to root inside
   the container due to macOS Docker's permission model.

This is a well-known problem with Docker bind mounts. Running as root inside
the container also violates the principle of least privilege.

### Options considered

**1. Hardcoded non-root user (e.g., UID 1000)**

- Simple: `USER obsidian` in the Dockerfile.
- Fails when the host UID doesn't match 1000 (e.g., macOS uses 501).
- No way to fix ownership of bind-mounted directories.

**2. Docker `--user` flag**

- `docker run --user 501:20 ...`
- Runs the process as the specified UID, but `/etc/passwd` still shows the
  build-time user. Some tools (git, ssh) behave incorrectly when the running
  UID doesn't match any passwd entry.
- No init-time ownership fixup.

**3. PUID/PGID environment variables (linuxserver.io convention)**

- Users set `PUID` and `PGID` to their host UID/GID.
- An init script remaps the container user's UID/GID at startup using
  `usermod`/`groupmod`.
- Ownership of mounted directories is fixed up before services start.
- Services run as the remapped user via `su-exec`.
- Well-established pattern with extensive community documentation.

**4. Docker user namespace remapping**

- Kernel-level UID mapping. Transparent but requires Docker daemon config,
  not available on all platforms, and adds operational complexity.

## Decision

Use the **PUID/PGID convention** (option 3) with `su-exec` for privilege
de-escalation.

Implementation:

- **Build time**: Create an `obsidian` user/group (UID/GID 1000) in the
  Dockerfile. Install `su-exec` (lightweight, ~10 KB) and `shadow`
  (provides `usermod`/`groupmod`).

- **Runtime — init-usermap oneshot**: Runs before all other services.
  Validates PUID/PGID (must be numeric, must not be 0). Remaps the
  `obsidian` user/group to match. Recursively fixes ownership of `/config`
  and `/vault` (only when ownership actually changed, to avoid slow chowns
  on normal restarts).

- **Runtime — services**: All service scripts (`init-config`, `obsidian-sync`,
  `git-watcher`) use `su-exec obsidian` to run user-facing operations as
  the remapped user. s6-overlay's `with-contenv` passes environment
  variables to services.

- **Default**: PUID=1000, PGID=1000 (matches common Linux defaults). Named
  volumes work without setting these. Bind mounts on macOS require
  PUID=501, PGID=20.

## Consequences

**Easier:**

- macOS users can use bind mounts without permission errors.
- The container follows the principle of least privilege — no services run
  as root during normal operation.
- Users familiar with linuxserver.io images recognize the pattern instantly.
- Switching between named volumes and bind mounts is straightforward.

**Harder:**

- Two additional packages in the image (`su-exec`, `shadow`). Adds ~2 MB.
- Every service script must use `su-exec` or `run_as_user` for commands
  that touch user-owned files. Missing a `su-exec` creates root-owned
  files that break the permission model.
- The init-usermap oneshot adds startup time when ownership needs fixing
  (recursive chown on large vaults). This only happens when PUID/PGID
  changes, not on normal restarts.
- PUID=0 is explicitly blocked. Users who genuinely need root execution
  must modify the image.
