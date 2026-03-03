# ADR-0007: Self-Hosted Unraid Community Applications Template

## Status

Accepted

## Context

Users on Unraid servers wanted an easy way to install this container
through Unraid's Community Applications (CA) plugin — the standard
app-store-like interface for discovering and installing Docker containers
on Unraid.

Unraid CA discovers containers via XML template files that describe the
Docker image, its environment variables, volumes, ports, and metadata.
These templates can be distributed in two ways:

### Options considered

**1. Submit a PR to `selfhosters/unRAID-CA-templates`**

The community-maintained repository that feeds the main CA search index.
Gets the widest discoverability. However, the selfhosters repo is
actively winding down new template requests and recommends that
maintainers host their own template repositories. PRs are still
reviewed, but response times are unpredictable.

**2. Self-hosted template repository in this repo**

Add the XML template directly to this project under a `unraid-template/`
directory. Users add the GitHub repo URL as a template source in CA
settings. The maintainer has full control over template updates — changes
are live as soon as they're pushed to `main`. This is the approach the
selfhosters repo now recommends.

**3. Separate dedicated template repository**

Create a separate GitHub repo solely for Unraid templates. Provides
clean separation but adds maintenance burden (two repos to keep in sync)
with no benefit for a single-container project.

## Decision

Use a **self-hosted template** (option 2) stored at
`obsidian-git-backup.xml` in the repository root.

Implementation details:

- **Directory structure**: The XML template lives at the repository
  root because CA's template scraper only scans the root directory
  of a registered GitHub repo — it does not recurse into
  subdirectories. The icon files remain in `unraid-template/img/`
  since CA fetches icons via direct URL, not directory scanning.

- **PUID/PGID defaults**: Set to `99`/`100` (Unraid's `nobody`/`users`
  convention) instead of the Dockerfile's `1000`/`1000`. This matches
  Unraid's standard appdata ownership model.

- **Volume paths**: Default to `/mnt/user/appdata/obsidian-git-backup/`
  which is the Unraid convention for container persistent data.

- **No `--restart` policy**: Omitted from ExtraParams because Unraid
  manages container lifecycle through its own Autostart mechanism.
  Adding `--restart unless-stopped` would conflict with Unraid's UI.

- **E2EE password visible by default**: Moved from `Display="advanced"`
  to `Display="always"` because users with E2EE vaults need to see
  this field immediately, not discover it after a failed sync.

- **Icon**: A placeholder SVG-derived PNG (purple diamond with git
  branch motif) is included. It can be replaced with a professional
  icon later.

## Consequences

**Easier:**

- Unraid users can discover and install the container through the
  standard CA interface with a guided form for all configuration.
- Template updates ship with the project — no external dependency on
  the selfhosters repo's review process.
- The XML template serves as documentation of Unraid-specific defaults
  (PUID/PGID, appdata paths) in a machine-readable format.

**Harder:**

- Users must manually add the GitHub repo URL in CA settings (one-time
  step). The template is not in the default CA search index.
- The template XML is an additional file to maintain when environment
  variables or volumes change. There is no automated validation that
  the template stays in sync with the Dockerfile.
- A future PR to `selfhosters/unRAID-CA-templates` could provide wider
  discoverability but would create a second copy of the template to
  maintain.
