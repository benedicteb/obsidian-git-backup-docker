# obsidian-git-backup-docker

A Docker image that syncs an [Obsidian](https://obsidian.md) vault via
[obsidian-headless](https://help.obsidian.md/headless) and automatically
backs it up to a git repository.

Every time Obsidian Sync delivers changes, they are committed and pushed to
your git remote — giving you a private, versioned backup of your vault with
full history.

## How It Works

```
Obsidian Sync ──> obsidian-headless ──> vault directory ──> inotifywait ──> git commit + push
                  (ob sync --continuous)                    (filesystem events)
```

1. **obsidian-headless** continuously syncs your vault from the Obsidian Sync
   servers to a local directory.
2. A **filesystem watcher** (inotifywait) detects when files change.
3. After a configurable **debounce period** (default 30s of quiet), all
   changes are committed and pushed to your git remote.

The container uses [s6-overlay](https://github.com/just-containers/s6-overlay)
for process supervision — both services are monitored and automatically
restarted if they crash.

## Prerequisites

- An [Obsidian Sync](https://obsidian.md/sync) subscription
- A git repository (e.g., on GitHub, GitLab, or self-hosted)
- Docker and Docker Compose

## Quick Start

### 1. Configure

```sh
cp .env.example .env
# Edit .env and fill in the required values
```

You need:

- **`OBSIDIAN_AUTH_TOKEN`** — Your Obsidian account auth token. Get it by
  running `npm install -g obsidian-headless && ob login` locally.
- **`OBSIDIAN_GIT_VAULT_NAME`** — The name of your remote vault. Run
  `ob sync-list-remote` to see available vaults.
- **`OBSIDIAN_GIT_REMOTE_URL`** — Your git remote SSH URL
  (e.g., `git@github.com:username/vault-backup.git`).

### 2. Start

```sh
docker compose up -d
```

### 3. Set Up SSH Key

On first run, the container generates an SSH keypair. Check the logs to find
the public key:

```sh
docker compose logs obsidian-backup
```

Look for the `NEW SSH KEY GENERATED` banner. Copy the public key and add it to
your git server:

- **GitHub**: Settings > SSH and GPG keys > New SSH key
- **GitLab**: Preferences > SSH Keys > Add new key

The container retries every 30 seconds — once you add the key, it will
connect automatically. No restart needed.

### 4. Verify

```sh
# Watch the logs
docker compose logs -f obsidian-backup
```

You should see:
1. Successful git clone
2. Obsidian headless sync starting
3. Filesystem watcher detecting changes
4. Git commits and pushes

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `OBSIDIAN_AUTH_TOKEN` | Yes | — | Obsidian account auth token |
| `OBSIDIAN_GIT_VAULT_NAME` | Yes | — | Remote vault name or ID |
| `OBSIDIAN_GIT_REMOTE_URL` | Yes | — | Git remote URL (SSH) |
| `OBSIDIAN_GIT_USER_NAME` | No | `obsidian-git-backup` | Git commit author name |
| `OBSIDIAN_GIT_USER_EMAIL` | No | `obsidian-git-backup@local` | Git commit author email |
| `OBSIDIAN_GIT_BRANCH` | No | `main` | Git branch |
| `OBSIDIAN_GIT_DEBOUNCE_SECS` | No | `30` | Seconds of quiet before committing |
| `OBSIDIAN_GIT_E2EE_PASSWORD` | No | — | E2E encryption password |

## Volumes

| Path | Required | Description |
|---|---|---|
| `/config` | **Yes** | SSH keys and persistent configuration. Must survive restarts. |
| `/vault` | No | Vault data and git working tree. Can be re-synced/re-cloned if lost. |

## Architecture

The container runs three s6-rc services:

```
base
  └── init-config (oneshot)
        ├── obsidian-sync (longrun)
        └── git-watcher (longrun)
```

- **init-config**: Validates environment, sets up SSH, clones git repo,
  configures obsidian-headless. Runs once at startup.
- **obsidian-sync**: Runs `ob sync --continuous`. Auto-restarted by s6 if it
  crashes.
- **git-watcher**: Monitors `/vault` with `inotifywait`. Debounces, then
  commits and pushes. Auto-restarted by s6 if it crashes.

## Multiple Vaults

Run one container per vault. Each needs its own `.env` file and volumes:

```yaml
services:
  vault-personal:
    build: .
    env_file: .env.personal
    volumes:
      - config-personal:/config
      - vault-personal:/vault

  vault-work:
    build: .
    env_file: .env.work
    volumes:
      - config-work:/config
      - vault-work:/vault
```

## Limitations (PoC)

- **SSH only** — HTTPS git remotes are not supported yet.
- **No LLM commit messages** — Commits use simple timestamps. AI-generated
  messages are planned for a future release.
- **No conflict resolution** — If someone pushes to the git remote from
  elsewhere, `git push` will fail until resolved manually.
