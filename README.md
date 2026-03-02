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

You need three values:

- **`OBSIDIAN_AUTH_TOKEN`** — Your Obsidian account auth token.

  To get it:
  1. Install obsidian-headless: `npm install -g obsidian-headless`
  2. Run `ob login` and follow the prompts
  3. Copy the contents of the `auth_token` file:
     - **macOS**: `~/.obsidian-headless/auth_token`
     - **Linux**: `~/.config/obsidian-headless/auth_token`
     - **Windows**: `%USERPROFILE%\.obsidian-headless\auth_token`

  The file contains the raw token string (not JSON). For example:
  ```sh
  cat ~/.config/obsidian-headless/auth_token   # Linux
  cat ~/.obsidian-headless/auth_token           # macOS
  ```

  > **Note:** `OBSIDIAN_AUTH_TOKEN` does not use the `OBSIDIAN_GIT_` prefix
  > because it's read directly by obsidian-headless, not this project.

- **`OBSIDIAN_GIT_VAULT_NAME`** — The name of your remote vault. Run
  `ob sync-list-remote` to see available vaults.

- **`OBSIDIAN_GIT_REMOTE_URL`** — Your git remote SSH URL
  (e.g., `git@github.com:username/vault-backup.git`).

### 2. Start

```sh
docker compose up -d
```

> **macOS users with bind mounts:** If you're mounting host directories
> (e.g., `./obsidian-config:/config`), you must set `PUID` and `PGID` in
> your `.env` to avoid "permission denied" errors. Run `id -u` and `id -g`
> to find your values (typically 501 and 20). See
> [User / Group Identifiers](#user--group-identifiers-puidpgid) for details.

### 3. Set Up SSH Key

The container needs an SSH key to push to your git remote. You have two
options:

#### Option A: Let the container generate a key (simplest)

On first run, if no SSH key exists at `/config/.ssh/id_ed25519`, the container
generates a new ed25519 keypair. Check the logs to find the public key:

```sh
docker compose logs obsidian-backup
```

Look for the `NEW SSH KEY GENERATED` banner. Copy the public key and add it to
your git server:

- **GitHub**: Settings > SSH and GPG keys > New SSH key
- **GitLab**: Preferences > SSH Keys > Add new key

The container retries every 30 seconds — once you add the key, it will
connect automatically. No restart needed.

#### Option B: Bring your own SSH key (bind mount)

> **Important:** Bind mounts require matching `PUID`/`PGID` on macOS
> (and recommended on Linux). See
> [User / Group Identifiers](#user--group-identifiers-puidpgid).

If you already have an SSH key you want to use (e.g., a deploy key), you can
bind-mount a local directory into `/config` that contains it.

1. Create a config directory on the host:

   ```sh
   mkdir -p ./obsidian-config/.ssh
   cp ~/.ssh/my_deploy_key ./obsidian-config/.ssh/id_ed25519
   cp ~/.ssh/my_deploy_key.pub ./obsidian-config/.ssh/id_ed25519.pub  # optional
   chmod 700 ./obsidian-config/.ssh
   chmod 600 ./obsidian-config/.ssh/id_ed25519
   ```

2. Update your `docker-compose.yml` to use a bind mount instead of a named
   volume:

   ```yaml
   volumes:
     - ./obsidian-config:/config
     - obsidian-vault:/vault
   ```

3. Start the container:

   ```sh
   docker compose up -d
   ```

The container detects the existing key and uses it — no new key is generated.

> **Note:** The key must be at `/config/.ssh/id_ed25519`. The container sets
> permissions automatically (`700` on the directory, `600` on the key), so
> don't worry about permission errors even if your host permissions differ.

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
| `OBSIDIAN_AUTH_TOKEN`* | Yes | — | Obsidian account auth token |
| `OBSIDIAN_GIT_VAULT_NAME` | Yes | — | Remote vault name or ID |
| `OBSIDIAN_GIT_REMOTE_URL` | Yes | — | Git remote URL (SSH) |
| `OBSIDIAN_GIT_USER_NAME` | No | `obsidian-git-backup` | Git commit author name |
| `OBSIDIAN_GIT_USER_EMAIL` | No | `obsidian-git-backup@local` | Git commit author email |
| `OBSIDIAN_GIT_BRANCH` | No | `main` | Git branch |
| `OBSIDIAN_GIT_DEBOUNCE_SECS` | No | `30` | Seconds of quiet before committing. Must be a positive integer. For large vaults, consider 60+. |
| `OBSIDIAN_GIT_E2EE_PASSWORD` | No | — | E2E encryption password |
| `PUID` | No | `1000` | Your host user ID. Needed for bind mounts — run `id -u` to find it. |
| `PGID` | No | `1000` | Your host group ID. Needed for bind mounts — run `id -g` to find it. |

\* `OBSIDIAN_AUTH_TOKEN` is read directly by obsidian-headless. It does not use
the `OBSIDIAN_GIT_` prefix because it's not a variable defined by this project.

## Volumes

| Path | Required | Description |
|---|---|---|
| `/config` | **Yes** | SSH keys and persistent configuration. Must survive restarts. Can be a named volume (key is auto-generated) or a bind mount (bring your own key — see [Option B](#option-b-bring-your-own-ssh-key-bind-mount)). |
| `/vault` | No | Vault data and git working tree. Can be re-synced/re-cloned if lost. |

## User / Group Identifiers (PUID/PGID)

When using **bind mounts** (mapping a host directory into the container), you
must tell the container to run as your host user to avoid permission conflicts.
This follows the [linuxserver.io](https://docs.linuxserver.io/general/understanding-puid-and-pgid/)
convention.

Find your UID and GID:

```sh
id -u   # → e.g. 501 on macOS, 1000 on Linux
id -g   # → e.g. 20 on macOS, 1000 on Linux
```

Then set them in your environment or `docker-compose.yml`:

```yaml
environment:
  - PUID=501
  - PGID=20
```

Or with `docker run`:

```sh
docker run -e PUID=501 -e PGID=20 ...
```

> **Note:** PUID/PGID are **not needed** when using Docker named volumes
> (the default in `docker-compose.yml`). Named volumes are managed by Docker
> and don't have host permission issues. PUID/PGID are only needed when you
> bind-mount host directories (e.g., `./local/config:/config`).

## Architecture

The container runs four s6-rc services:

```
base
  └── init-usermap (oneshot) — remaps UID/GID to match PUID/PGID
        └── init-config (oneshot) — validates env, sets up SSH, clones git, configures ob
              ├── obsidian-sync (longrun) — ob sync --continuous
              └── git-watcher (longrun) — inotifywait + git commit/push
```

- **init-usermap**: Remaps the container's `obsidian` user/group to match
  `PUID`/`PGID`. Fixes ownership of `/config` and `/vault`. Runs once.
- **init-config**: Validates environment, sets up SSH, clones git repo,
  configures obsidian-headless. Runs once at startup.
- **obsidian-sync**: Runs `ob sync --continuous` as the `obsidian` user.
  Auto-restarted by s6 if it crashes.
- **git-watcher**: Monitors `/vault` with `inotifywait` as the `obsidian`
  user. Debounces, then commits and pushes. Auto-restarted by s6 if it
  crashes. On graceful shutdown, any pending changes in the debounce window
  are committed.

## Multiple Vaults

Run one container per vault. Each needs its own `.env` file (with a different
`OBSIDIAN_GIT_VAULT_NAME` and `OBSIDIAN_GIT_REMOTE_URL`) and separate volumes:

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
- **Large syncs may produce partial commits** — The debounce timer helps but
  if an Obsidian sync takes longer than the debounce period, intermediate
  state may be committed. Increase `OBSIDIAN_GIT_DEBOUNCE_SECS` for large vaults.
