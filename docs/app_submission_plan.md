# Unraid Community Applications — Submission Plan

This document describes the steps required to submit `obsidian-git-backup`
to the official Unraid Community Applications marketplace so it appears in
the Apps tab search for all Unraid users.

## Current State

- Docker Hub image: `benedicteb/obsidian-git-backup` (public, multi-arch)
- GitHub repo: `https://github.com/benedicteb/obsidian-git-backup-docker`
- CA template XML at repository root (`obsidian-git-backup.xml`)
- PUID/PGID defaults to 99/100 (Unraid convention)
- Volume paths default to `/mnt/user/appdata/obsidian_git_backup/`
- Current install method: `curl` to `/boot/config/plugins/dockerMan/templates/`

## Template Review Summary

An Unraid ecosystem review found the template "very solid" with the
following already correct:

- PUID/PGID defaults (99/100)
- Appdata volume paths
- No `--restart` policy (Unraid manages lifecycle via Autostart)
- Secrets masked (`OBSIDIAN_AUTH_TOKEN`, `OBSIDIAN_GIT_E2EE_PASSWORD`)
- `Privileged=false`
- XML at repo root (CA scraper only scans root)
- E2EE password `Display="always"` (visible to users who need it)
- Overview text is clear and accurate
- Multi-arch support (amd64/arm64)

---

## Mandatory Fixes (Blocking)

### 1. Create an Unraid Forum Support Thread

CA reviewers check for this first and will reject without it.

- Go to the [Docker Containers subforum](https://forums.unraid.net/forum/52-docker-containers/)
- Create a thread titled: `[Support] obsidian-git-backup — Obsidian Sync to git backup`
- Include in the first post:
  - What the container does (3-4 sentences)
  - Prerequisites (Obsidian Sync subscription, git repo with SSH access)
  - The out-of-band `ob login` step (most common confusion point)
  - Links to GitHub repo and Docker Hub
  - Install method (the `curl` command to dockerMan templates)
  - Known limitations
  - Invitation to report issues
- Note the thread URL for the next step

### 2. Update `<Support>` in Template XML

Change from GitHub Issues to the forum thread:

```xml
<!-- Before -->
<Support>https://github.com/benedicteb/obsidian-git-backup-docker/issues</Support>

<!-- After -->
<Support>https://forums.unraid.net/topic/XXXXXX-obsidian-git-backup/</Support>
```

GitHub Issues is not an acceptable support destination for the official
CA index. Keep the GitHub Issues link in `<Overview>` or `<ReadMe>` if
desired, but `<Support>` must point to the forum thread.

### 3. Remove `<Beta>true</Beta>`

Submitting to the official index while flagging as Beta sends mixed
signals and may result in rejection. Remove the line entirely (the
field defaults to `false` when absent).

---

## Recommended Improvements (Non-Blocking)

### 4. Fix `<Changes>` Format

CA does not render Markdown in `<Changes>`. Use CA's native format with
`&#xD;` line breaks and BBCode-style headers:

```xml
<Changes>&#xD;
[center][b]2026-03-03[/b][/center]&#xD;
- Initial release: Obsidian Sync to git backup&#xD;
- Filesystem-event-driven commits (inotify, no polling)&#xD;
- Automatic SSH key generation on first start&#xD;
- E2E encrypted vault support&#xD;
</Changes>
```

### 5. Verify Icon Quality at 75x75px

CA displays icons at roughly 75x75px in the apps grid. Visit the icon
URL in a browser and confirm it looks recognizable at that size:

```
https://raw.githubusercontent.com/benedicteb/obsidian-git-backup-docker/main/unraid-template/img/obsidian-git-backup.png
```

Note: The icon URL path (`unraid-template/img/obsidian-git-backup.png`)
is effectively frozen after CA indexes it. Moving or renaming the file
breaks the icon for all installed instances.

### 6. Strengthen Vault Storage Description

Consider changing from "Recommended" to "Strongly recommended" to better
guide users:

```
Vault data and git working tree. Strongly recommended — without this,
the entire vault re-syncs and re-clones from scratch on every container
restart (slow for large vaults).
```

---

## Submission Process

### Step 1: Create the Forum Thread

See "Mandatory Fixes" item 1 above.

### Step 2: Update the Template XML

Apply all mandatory fixes (items 1-3) and recommended improvements
(items 4-6).

### Step 3: Verify CA Can Scrape the Repo

On an Unraid server:

1. Docker tab > Add Container > template dropdown — verify the template
   appears and populates correctly
2. Optionally verify via the CA plugin: Apps tab > add the GitHub repo
   URL as a template source > verify the template appears in search

### Step 4: Verify the Icon Renders

Confirm the icon loads in the CA Apps tab or template dropdown and looks
reasonable at small sizes.

### Step 5: Submit to the CA Index

Open an issue at
[`Squidly271/community.applications`](https://github.com/Squidly271/community.applications)
with:

- **Title**: `[Template Request] obsidian-git-backup — Obsidian Sync to git backup`
- **Body**:
  - GitHub repo URL
  - Docker Hub URL
  - Unraid forum thread URL
  - Brief description of what the container does

### Step 6: Wait for Review

- Expected turnaround: 1-4 weeks (no SLA — Squid is a one-person operation)
- Having an active forum thread with real users accelerates review
- After acceptance, the template appears in CA's Apps tab search within
  24 hours of the next index refresh

### Step 7: After Acceptance

- Update the README to reflect that the template is discoverable in the
  Apps tab search (keep the `curl` method as a fallback)
- Remove any "not yet in the official CA index" caveats from documentation
- `<TemplateURL>` ensures CA propagates template updates to installed users

---

## Ongoing Maintenance Obligations

After acceptance into the official CA index:

| Obligation | Details |
|---|---|
| **Forum support** | Respond to questions in the forum thread within a reasonable time. Abandoned templates get removed from the index. |
| **Template updates** | When environment variables or volumes change, update the XML. CA's `<TemplateURL>` mechanism propagates updates automatically. |
| **Docker Hub availability** | The image must remain publicly available. Deleting the image or making the repo private breaks the template for all users. |
| **Container name frozen** | `obsidian_git_backup` — once indexed, changing the container name confuses existing installs. Treat the name as immutable. |
| **Icon path frozen** | The `<Icon>` URL path must remain stable. Moving or renaming the icon file breaks it for all installed instances. |

---

## Common Rejection Reasons — Current Status

| Rejection Reason | Status |
|---|---|
| No forum support thread | Must fix |
| `<Support>` points to wrong place | Must fix |
| `<Beta>true</Beta>` | Must fix |
| Template XML not at repo root | Done |
| Icon URL broken or placeholder | Verify quality |
| PUID/PGID default to 1000 not 99/100 | Done |
| Appdata path not using `/mnt/user/appdata/` | Done |
| `--restart` policy in ExtraParams | Correctly absent |
| Required fields not marked | Done |
| Secrets not using `Mask="true"` | Done |
| `Privileged=true` without justification | Correctly `false` |
| Docker Hub image not available | Done |
| `<Changes>` in wrong format | Recommended fix |
