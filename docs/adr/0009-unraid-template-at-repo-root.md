# ADR-0009: Unraid CA Template XML at Repository Root

## Status

Accepted (amends [ADR-0007](0007-unraid-community-applications-template.md))

## Context

ADR-0007 placed the Unraid CA template XML file at
`unraid-template/obsidian-git-backup.xml`. During a comprehensive Unraid
reviewer audit (session 010), it was discovered that **CA's template
scraper only scans the root directory** of a registered GitHub repository.
It does not recurse into subdirectories.

This meant that when users added
`https://github.com/benedicteb/obsidian-git-backup-docker` as a template
source in CA settings (as documented in the README), CA would scan the
repository root, find no XML files, and index nothing. The template was
effectively invisible.

### Options considered

**1. Move XML to repository root**

Place `obsidian-git-backup.xml` at `/` instead of `/unraid-template/`.
Simplest for CA discovery. Minor repo root clutter (one XML file).

**2. Keep XML in subdirectory, document subdirectory URL**

Tell users to add
`https://github.com/benedicteb/obsidian-git-backup-docker/tree/main/unraid-template`
as their template source. Error-prone — the `tree/main/` URL format is
not reliably handled across CA versions.

**3. Keep XML in subdirectory, hope CA scans recursively**

Incorrect assumption — CA does not recurse. Non-starter.

## Decision

Move the template XML to the repository root (option 1).

- `obsidian-git-backup.xml` lives at the repository root.
- Icon files remain in `unraid-template/img/` since CA fetches icons
  via direct URL, not directory scanning.
- `<TemplateURL>` updated to point to the new root location.
- ADR-0007 updated to reflect the new directory structure.

## Consequences

**Easier:**

- Users add the standard repo URL and CA finds the template immediately.
  No special subdirectory URL or instructions needed.
- Matches 100% of other self-hosted CA template repos (ich777, binhex,
  hotio all place XML at root).

**Harder:**

- One XML file in the repository root. Acceptable for a single-container
  project. The `unraid-template/` directory remains for icon assets.
