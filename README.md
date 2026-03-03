# obsidian-git-backup-docker

[![Docker Hub](https://img.shields.io/docker/v/benedicteb/obsidian-git-backup?sort=semver&label=Docker%20Hub)](https://hub.docker.com/r/benedicteb/obsidian-git-backup)

A Docker image that syncs an [Obsidian](https://obsidian.md) vault via
[obsidian-headless](https://help.obsidian.md/headless) and automatically
backs it up to a git repository.

Every time Obsidian Sync delivers changes, they are committed and pushed to
your git remote — giving you a private, versioned backup of your vault with
full history.

## Using the Pre-Built Image

Pre-built images are published to Docker Hub for `linux/amd64` and `linux/arm64`:

```sh
docker pull benedicteb/obsidian-git-backup:latest
```

To use a specific version:

```sh
docker pull benedicteb/obsidian-git-backup:v0.1.0
```

See the [Docker Hub page](https://hub.docker.com/r/benedicteb/obsidian-git-backup)
for available tags.

To use the pre-built image instead of building from source, update your
`docker-compose.yml`:

```yaml
services:
  obsidian-backup:
    image: benedicteb/obsidian-git-backup:latest
    # ... rest of config
```

To build from source instead, replace `image:` with `build: .`.

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

On first run, if no SSH key exists at `/config/id_ed25519`, the container
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
   mkdir -p ./obsidian-config
   cp ~/.ssh/my_deploy_key ./obsidian-config/id_ed25519
   cp ~/.ssh/my_deploy_key.pub ./obsidian-config/id_ed25519.pub  # optional
   chmod 600 ./obsidian-config/id_ed25519
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

> **Note:** The key must be at `/config/id_ed25519`. The container sets
> permissions automatically (`600` on the key), so don't worry about
> permission errors even if your host permissions differ.

> **Advanced:** On first run, the container auto-generates `ssh_config` and
> `known_hosts` in `/config/`. If you need custom SSH settings (e.g., a
> non-standard port, proxy, or pre-seeded host keys), you can provide your
> own `ssh_config` and/or `known_hosts` in the same directory — the
> container will use them as-is and not overwrite them.

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
| `/config` | **Yes** | Persistent configuration and SSH keys. Must survive restarts. Named volume (default) or bind mount (see [Option B](#option-b-bring-your-own-ssh-key-bind-mount)). |
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
    image: benedicteb/obsidian-git-backup:latest
    env_file: .env.personal
    volumes:
      - config-personal:/config
      - vault-personal:/vault

  vault-work:
    image: benedicteb/obsidian-git-backup:latest
    env_file: .env.work
    volumes:
      - config-work:/config
      - vault-work:/vault
```

## Unraid Installation

This image is available as an Unraid
[Community Applications](https://forums.unraid.net/topic/38582-plug-in-community-applications/)
template. The template is currently in **beta** — CA will show a warning
before install, which is expected. Please
[report issues](https://github.com/benedicteb/obsidian-git-backup-docker/issues)
if you encounter problems.

### Before You Start

Before installing on Unraid, you need to obtain your Obsidian auth token on a
**desktop or laptop** (not on the Unraid server — a web browser is required):

1. Install Node.js
2. Run `npm install -g obsidian-headless`
3. Run `ob login` — this opens a browser for authentication
4. Copy the token from the `auth_token` file:
   - **macOS**: `~/.obsidian-headless/auth_token`
   - **Linux**: `~/.config/obsidian-headless/auth_token`
   - **Windows**: `%USERPROFILE%\.obsidian-headless\auth_token`

You also need a git repository with SSH access (e.g., a private GitHub repo).

### Add the Template Repository

1. In the Unraid web UI, go to the **Apps** tab.
2. Click the **Settings** icon (gear) to open CA settings.
3. Under **Template Repositories**, add this URL:
   ```
   https://github.com/benedicteb/obsidian-git-backup-docker
   ```
4. Click **Save** and wait 1–2 minutes for CA to index the repository.
5. Search for **obsidian-git-backup** and click **Install**.

### Configure the Container

> **Tip:** For best I/O performance with frequent small file changes, ensure
> your `appdata` share uses "cache-prefer" or "cache-only" mode (Shares tab)
> before installing. The default appdata paths will then land on the cache
> drive automatically.

The template form includes all required and optional settings:

| Field | Required | Notes |
|---|---|---|
| Obsidian Auth Token | Yes | The token from `ob login` above. Masked in the UI. |
| Vault Name | Yes | Exactly as shown in the Obsidian app (case-sensitive). Run `ob sync-list-remote` to list vaults. You can also use the vault UUID. |
| Git Remote URL | Yes | SSH URL, e.g. `git@github.com:user/vault-backup.git` |
| E2EE Password | If encrypted | Only for E2E encrypted vaults. Your git backup will contain **plaintext** notes — secure your git remote accordingly. |
| Config Storage | Yes | Default: `/mnt/user/appdata/obsidian-git-backup/config` |
| Vault Storage | Yes | Default: `/mnt/user/appdata/obsidian-git-backup/vault` |

Additional settings (git author, branch, debounce period) are under
**Advanced View**.

> **Note:** PUID/PGID default to `99`/`100` (Unraid's `nobody`/`users`),
> which is correct for most Unraid setups. Changing these means Unraid's
> *New Permissions* tool may create files with unexpected ownership.

The container is managed by Unraid's Autostart mechanism — no `--restart`
policy is set, which lets Unraid control the container lifecycle cleanly
across array start/stop cycles.

### After Installing

1. Go to the **Docker** tab, click the container's icon (the coloured
   square), and select **Log**.
2. Look for the `NEW SSH KEY GENERATED` banner.
3. Copy the public key and add it to your git server:
   - **GitHub**: Settings → SSH and GPG keys → New SSH key
   - **GitLab**: Preferences → SSH Keys → Add new key
4. The container retries every 30 seconds — once you add the key, it
   connects automatically. No restart needed.

### Multiple Vaults on Unraid

Run one container per vault. To add another vault, install the template
again with:
- A different container name (e.g., `obsidian-git-backup-work`)
- Different appdata paths (e.g., `/mnt/user/appdata/obsidian-git-backup-work/`)
- A different vault name and git remote URL

Each container counts as one device on your Obsidian Sync plan — check
your plan's device limit at [obsidian.md/account](https://obsidian.md/account).

> **Warning:** Never point two containers at the same vault simultaneously.
> Each container must also have its own separate appdata paths — sharing
> paths between containers causes silent data corruption.

### Troubleshooting on Unraid

**Container keeps restarting / inotifywait crashes on a busy server:**

The filesystem watcher uses inotify, which has a host-level watch limit
shared by all containers. On busy Unraid servers, the default limit (8,192)
can be exhausted. Check the current value:

```sh
cat /proc/sys/fs/inotify/max_user_watches
```

To raise it (64× the default):

```sh
# Temporary (until next reboot):
echo 524288 > /proc/sys/fs/inotify/max_user_watches

# Persistent — add to Settings → Boot → Go file (/boot/config/go):
# Run this once; repeat runs append duplicate lines.
echo 'echo 524288 > /proc/sys/fs/inotify/max_user_watches' >> /boot/config/go
```

## Publishing

Pushes to `main` automatically build and publish the Docker image to
[Docker Hub](https://hub.docker.com/r/benedicteb/obsidian-git-backup).

Version tags are created automatically based on
[conventional commits](https://www.conventionalcommits.org/):

| Commit prefix | Version bump | Example |
|---|---|---|
| `feat!:` or `BREAKING CHANGE` in body | Major (0.1.0 → 1.0.0) | `feat!: rename all env vars` |
| `feat:` | Minor (0.1.0 → 0.2.0) | `feat: add LLM commit messages` |
| `fix:`, `docs:`, `chore:`, etc. | Patch (0.1.0 → 0.1.1) | `fix: handle empty vault` |

Two GitHub Actions secrets must be configured (Settings → Secrets and
variables → Actions):

| Secret | Where to get it |
|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub → Account Settings → Security → New Access Token |

## Limitations (PoC)

- **SSH only** — HTTPS git remotes are not supported yet.
- **No LLM commit messages** — Commits use simple timestamps. AI-generated
  messages are planned for a future release.
- **Large syncs may produce partial commits** — The debounce timer helps but
  if an Obsidian sync takes longer than the debounce period, intermediate
  state may be committed. Increase `OBSIDIAN_GIT_DEBOUNCE_SECS` for large vaults.
