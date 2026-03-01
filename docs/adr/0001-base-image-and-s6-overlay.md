# ADR-0001: Base Image and Process Supervision

## Status

Accepted

## Context

This project needs a Docker image that runs two long-lived processes
simultaneously:

1. `ob sync --continuous` — the obsidian-headless sync daemon
2. A filesystem watcher — monitors vault changes and commits/pushes to git

Docker containers are designed to run a single foreground process. Running
multiple processes requires either a process supervisor or a shell script that
backgrounds processes manually.

Additionally, obsidian-headless requires Node.js 22 or later at runtime.

### Options considered

**Base image:**

- `node:22-alpine` — Official Node.js on Alpine. Minimal, ~50 MB. Has npm to
  install obsidian-headless.
- `node:22-slim` — Official Node.js on Debian slim. Larger (~80 MB) but more
  compatible.
- `lsio/baseimage-alpine` — linuxserver.io base with s6-overlay pre-installed.
  Does not include Node.js; would need to install it separately.

**Process supervision:**

- **s6-overlay** — Open source (MIT), built on s6 by skarnet.org. Purpose-built
  for containers. Proper PID 1, dependency ordering between services, automatic
  restarts, clean shutdown. Used by linuxserver.io and many other projects.
  ~6 MB overhead.
- **Simple bash entrypoint** — Background one process, foreground the other.
  Fragile signal handling, no restart capability, no dependency ordering.
- **supervisord** — Python-based. Heavy dependency (~30 MB+), overkill for
  two services.
- **tini + bash** — Proper PID 1 for zombie reaping but no process supervision
  or restart capability.

## Decision

Use `node:22-alpine` as the base image and install s6-overlay v3 on top.

- Alpine provides a minimal image size with the musl-based package manager.
- Node.js 22 is required by obsidian-headless and comes included in the base.
- s6-overlay provides proper PID 1 behavior, dependency-ordered service startup,
  automatic restarts of crashed services, and clean container shutdown.
- We use the s6-rc service definition format (not the legacy `/etc/services.d`)
  for explicit dependency declarations between init, sync, and watcher services.

s6-overlay is pinned to a specific version (v3.2.2.0) for build reproducibility.

## Consequences

**Easier:**

- Adding new services (e.g., a health check endpoint) is straightforward — just
  add another service definition directory.
- Crash recovery is automatic — s6 restarts failed services without container restart.
- Shutdown is clean — services stop in reverse dependency order.
- Init tasks (git clone, SSH setup) run as oneshots with guaranteed ordering
  before longrun services start.

**Harder:**

- s6-overlay adds complexity compared to a simple entrypoint script. Developers
  need to understand s6-rc service definitions.
- The s6-overlay tarball uses different architecture naming than Docker
  (`x86_64`/`aarch64` vs `amd64`/`arm64`), requiring a mapping step in the
  Dockerfile.
- Debugging service startup issues requires understanding s6-overlay's init
  stages and log output.
