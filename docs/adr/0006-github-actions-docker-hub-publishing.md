# ADR-0006: GitHub Actions CI/CD for Docker Hub Publishing

## Status

Accepted

## Context

The project needed an automated way to publish Docker images so users
don't have to build from source. Key requirements:

1. Every push to `main` should produce a tagged Docker image on Docker Hub.
2. Version tags should be created automatically (no manual release process).
3. Both `linux/amd64` and `linux/arm64` must be supported.
4. The image should be available on Docker Hub's free tier.

### Options considered

**Versioning strategy:**

1. **Manual tags** — Developer creates `git tag v1.0.0` and pushes. Simple
   but requires discipline. Easy to forget.

2. **Patch auto-increment** — Every push bumps the patch version. Simple
   but semantically meaningless — `v0.0.47` tells users nothing about what
   changed.

3. **Conventional commits** — Parse commit messages (`feat:`, `fix:`,
   `BREAKING CHANGE`) to determine the bump type. More complex but
   produces meaningful semver. Well-established convention.

4. **Date-based** — Tags like `v2026.03.02`. Simple but not semantic.

**Publishing platform:**

- **Docker Hub** — Free for unlimited public repositories. The standard
  registry. Most discoverable.
- **GitHub Container Registry (GHCR)** — Free for public repos. Closer to
  GitHub Actions (no separate credentials). Less discoverable for Docker
  users who search Docker Hub first.

**Multi-platform build approach:**

1. **QEMU emulation** — `docker/setup-qemu-action` emulates arm64 on
   amd64 runners. Simple setup, slower builds. Native addon compilation
   (better-sqlite3) under QEMU can be slow or flaky.

2. **Native runners** — Use GitHub's `ubuntu-24.04-arm` runners for arm64.
   Fast, reliable, but requires a matrix build + manifest merge. More
   complex workflow.

## Decision

Use **GitHub Actions with conventional commit parsing** for versioning,
publishing to **Docker Hub**, with **QEMU-based multi-platform builds**.

Implementation details:

- **Trigger**: Every push to `main`. No `[skip ci]` filtering (every push
  is a release). This was a deliberate choice — the project uses
  conventional commits and every change is meaningful enough to release.

- **Versioning**: A shell script in the workflow parses commits since the
  last `vN.N.N` tag. `feat!:` or `BREAKING CHANGE` → major bump,
  `feat:` → minor bump, everything else → patch bump. First release
  starts at `v0.0.1` (from implicit `v0.0.0`).

- **Tag ordering**: Tags are created AFTER the Docker build succeeds to
  avoid orphaned tags (a git tag with no corresponding image).

- **Concurrency**: `cancel-in-progress: true` — newer pushes cancel
  in-progress builds. This prevents race conditions where two runs
  compute the same version tag.

- **Multi-platform**: QEMU emulation via `docker/setup-qemu-action`.
  Simpler than native runners. If arm64 builds become too slow, we can
  switch to native runners later (see Consequences).

- **Docker Hub credentials**: `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`
  stored as GitHub Actions secrets. A preflight check step fails early
  with an actionable error message if secrets are missing.

- **README sync**: `peter-evans/dockerhub-description` keeps the Docker
  Hub repository description in sync with `README.md`.

- **Layer caching**: GitHub Actions cache (`type=gha`) for Docker layer
  caching between builds.

## Consequences

**Easier:**

- Users can `docker pull benedicteb/obsidian-git-backup:latest` without
  building from source.
- Every push to main is automatically released — no manual release process.
- Version tags are semantically meaningful (feat = minor, fix = patch).
- ARM users (Apple Silicon, Raspberry Pi) get native images.
- ~~Docker Hub description stays in sync with the README automatically.~~
  Superseded by [ADR-0008](0008-manual-docker-hub-readme.md) — README
  is now updated manually.

**Harder:**

- QEMU emulation for arm64 builds is slow (~10-15 min for native addon
  compilation). If this becomes a problem, the workflow must be refactored
  to use GitHub's native arm64 runners with a matrix strategy.
- Every push creates a release, including `docs:` and `chore:` commits.
  Version numbers may increment faster than expected. Acceptable for a
  pre-stable project.
- The conventional commit parser is hand-rolled shell (not a dedicated
  tool like `semantic-release`). Simpler but less feature-complete — no
  changelog generation, no release notes on GitHub.
- ~~`peter-evans/dockerhub-description` may require a Docker Hub PAT with
  broader permissions than a scoped registry token. If the README sync
  fails silently, it does not block the image publish.~~
  Removed — see [ADR-0008](0008-manual-docker-hub-readme.md).
- Third-party GitHub Actions are pinned by major version tag, not SHA.
  A supply chain compromise could affect the publish pipeline. Pinning
  to SHAs is a future hardening step.
