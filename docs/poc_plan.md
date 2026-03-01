# PoC Implementation Plan

## Goal

Build a Docker image that runs `obsidian-headless` to continuously sync one
Obsidian vault, watches for filesystem changes with `inotifywait`, and
commits/pushes changes to a git remote automatically.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Base image | `node:22-alpine` + s6-overlay v3 | obsidian-headless requires Node 22. Alpine keeps image small. |
| Process supervision | s6-overlay (s6-rc service definitions) | Proper PID 1, dependency ordering, automatic restarts, clean shutdown. |
| Git auth | SSH only. Auto-generate ed25519 key if none provided. | Simple. User mounts `/config` volume; if no key exists one is generated and logged. Container retries git clone every 30s. |
| SSH known_hosts | `StrictHostKeyChecking=accept-new` | Accept on first connect, reject changes after. Standard TOFU for automated setups. |
| Git repo init | Clone existing remote on startup | User provides `OBSIDIAN_GIT_REMOTE_URL`. Container clones into `/vault`. |
| First-start order | Git clone first, then obsidian-headless syncs on top | Preserves existing git history. Obsidian Sync wins on conflicts (latest data). |
| Crash behavior | s6 restarts crashed services automatically | Container only stops on `docker stop`. Docker restart policy is a second layer. |
| Obsidian auth | `OBSIDIAN_AUTH_TOKEN` env var | Non-interactive, standard for Docker. |
| Volumes | `/config` (required), `/vault` (optional) | Config persists SSH keys. Vault data can be re-synced/re-cloned if lost. |
| LLM commit messages | Deferred | Not in PoC scope. Simple timestamp-based messages for now. |
| Watcher mechanism | `inotifywait` + debounce timer | Event-driven, not polling. Debounce prevents committing during active sync. |

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `OBSIDIAN_AUTH_TOKEN` | Yes | — | Obsidian account auth token |
| `OBSIDIAN_GIT_VAULT_NAME` | Yes | — | Remote vault name or ID |
| `OBSIDIAN_GIT_REMOTE_URL` | Yes | — | Git SSH remote URL |
| `OBSIDIAN_GIT_USER_NAME` | No | `obsidian-git-backup` | Git commit author name |
| `OBSIDIAN_GIT_USER_EMAIL` | No | `obsidian-git-backup@local` | Git commit author email |
| `OBSIDIAN_GIT_BRANCH` | No | `main` | Git branch to use |
| `OBSIDIAN_GIT_DEBOUNCE_SECS` | No | `30` | Seconds of quiet before commit |
| `OBSIDIAN_GIT_E2EE_PASSWORD` | No | — | Obsidian E2E encryption password |

## File Structure

```
obsidian-git-backup-docker/
├── Dockerfile
├── docker-compose.yml
├── .gitignore
├── .env.example
├── README.md
├── rootfs/
│   ├── etc/s6-overlay/s6-rc.d/
│   │   ├── init-config/
│   │   │   ├── type                         # oneshot
│   │   │   ├── dependencies.d/
│   │   │   │   └── base                     # wait for s6 base services
│   │   │   └── up                           # exec /usr/local/bin/init-config.sh
│   │   ├── obsidian-sync/
│   │   │   ├── type                         # longrun
│   │   │   ├── run                          # exec ob sync --continuous
│   │   │   └── dependencies.d/
│   │   │       └── init-config              # wait for init
│   │   ├── git-watcher/
│   │   │   ├── type                         # longrun
│   │   │   ├── run                          # exec git-watcher.sh
│   │   │   └── dependencies.d/
│   │   │       └── init-config              # wait for init
│   │   └── user/contents.d/
│   │       ├── init-config                  # empty marker
│   │       ├── obsidian-sync                # empty marker
│   │       └── git-watcher                  # empty marker
│   └── usr/local/bin/
│       ├── init-config.sh
│       └── git-watcher.sh
└── docs/
    ├── poc_plan.md                          # this file
    ├── adr/
    │   └── 0001-base-image-and-s6-overlay.md
    └── sessions/
        └── 001.md
```

## Startup Flow

```
Container starts -> s6-overlay as PID 1 -> /init
  |
  +-- init-config (oneshot)
  |   |
  |   +-- 1. Validate required env vars
  |   |      Missing? -> log error, exit nonzero -> container fails to start
  |   |
  |   +-- 2. SSH key setup
  |   |      /config/.ssh/id_ed25519 exists?
  |   |        YES -> chmod 600, continue
  |   |        NO  -> ssh-keygen -t ed25519 -> log public key prominently
  |   |
  |   +-- 3. Configure SSH
  |   |      Write /config/.ssh/config with StrictHostKeyChecking=accept-new
  |   |
  |   +-- 4. Git clone (with retry)
  |   |      Loop: git clone $REMOTE_URL /vault
  |   |        Success -> continue
  |   |        Failure -> log message, sleep 30s, retry
  |   |      (This is where the container waits if SSH key hasn't been
  |   |       added to the git server yet)
  |   |
  |   +-- 5. Git configuration
  |   |      git config user.name / user.email
  |   |      git checkout -B $BRANCH
  |   |
  |   +-- 6. Vault .gitignore
  |   |      Create/update .gitignore in /vault:
  |   |        .obsidian/workspace.json
  |   |        .obsidian/workspace-mobile.json
  |   |        .obsidian/cache/
  |   |        .trash/
  |   |
  |   +-- 7. Obsidian headless setup
  |          ob sync-setup --vault $VAULT_NAME --path /vault
  |            [--password $E2EE_PASSWORD if set]
  |
  +-- obsidian-sync (longrun, depends on init-config)
  |   +-- ob sync --continuous --path /vault
  |      (s6 restarts automatically if it crashes)
  |
  +-- git-watcher (longrun, depends on init-config)
      +-- inotifywait loop (see below)
         (s6 restarts automatically if it crashes)
```

## Git Watcher Logic

```sh
#!/bin/sh
set -eu

DEBOUNCE="${OBSIDIAN_GIT_DEBOUNCE_SECS:-30}"
VAULT="/vault"
BRANCH="${OBSIDIAN_GIT_BRANCH:-main}"

cd "$VAULT"

# Monitor filesystem events, excluding .git directory
# When events occur, wait for DEBOUNCE seconds of quiet, then commit+push

inotifywait -m -r \
  --exclude '\.git' \
  -e modify,create,delete,move \
  --format '%w%f' \
  "$VAULT" |
while read -r _; do
  # Drain events for DEBOUNCE seconds (reset timer on each new event)
  while read -t "$DEBOUNCE" _; do :; done

  # Stage all changes
  git add -A

  # Commit only if there are staged changes
  if ! git diff --cached --quiet; then
    git commit -m "vault sync: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    git push origin "$BRANCH"
  fi
done
```

Key behaviors:

- **Debounce**: After the first event, wait `DEBOUNCE_SECS` of silence before
  acting. This lets obsidian-headless finish syncing a batch of files.
- **Exclude `.git`**: Don't react to git's own internal changes.
- **Idempotent commits**: Only commit if `git diff --cached` shows actual changes.
- **Simple messages**: `vault sync: 2026-03-01 14:30:00 UTC` (LLM messages deferred).

## Dockerfile Outline

```dockerfile
FROM node:22-alpine

ARG S6_OVERLAY_VERSION=3.2.2.0
ARG TARGETARCH

# Install system dependencies
RUN apk add --no-cache \
    git \
    openssh-client \
    inotify-tools \
    xz

# Install s6-overlay (with arch mapping)
# Docker TARGETARCH uses amd64/arm64, s6 uses x86_64/aarch64

# Install obsidian-headless
RUN npm install -g obsidian-headless

# Create directories
RUN mkdir -p /vault /config/.ssh

# Copy s6 service definitions and scripts
COPY rootfs/ /

VOLUME ["/config", "/vault"]
ENTRYPOINT ["/init"]
```

Note: s6-overlay uses `x86_64` / `aarch64` naming, not Docker's `amd64` /
`arm64`. The Dockerfile will need an arch mapping step.

## Implementation Order

| # | Task | Files | Priority |
|---|---|---|---|
| 1 | Project `.gitignore` | `.gitignore` | High |
| 2 | Env var reference | `.env.example` | High |
| 3 | ADR: base image + s6-overlay | `docs/adr/0001-*.md` | High |
| 4 | Dockerfile | `Dockerfile` | High |
| 5 | Init script | `rootfs/usr/local/bin/init-config.sh` | High |
| 6 | Git watcher script | `rootfs/usr/local/bin/git-watcher.sh` | High |
| 7 | s6 service definitions | `rootfs/etc/s6-overlay/s6-rc.d/*` | High |
| 8 | Docker compose | `docker-compose.yml` | Medium |
| 9 | README | `README.md` | Medium |
| 10 | Subagent reviews | — | Medium |
| 11 | Address review feedback | Various | Medium |
| 12 | Session summary | `docs/sessions/001.md` | Low |

## Known Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Watcher commits during active obsidian sync | 30s debounce (configurable). Obsidian-headless writes files in bursts; debounce waits for quiet. |
| `git push` fails (network, permissions) | Log error, don't crash watcher. Next successful cycle will push all accumulated commits. |
| s6-overlay arch naming mismatch | Map Docker `TARGETARCH` (amd64/arm64) to s6 naming (x86_64/aarch64) in Dockerfile. |
| `ob sync-setup` needs interactive E2EE password | Pass via `--password` flag from env var. |
| Git repo and Obsidian vault have conflicting content on first start | Git clone first, then Obsidian Sync overlays latest. Conflicts are unlikely since the git repo *is* the vault backup. |
