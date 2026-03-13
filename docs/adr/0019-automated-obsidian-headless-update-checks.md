# ADR-0019: Automated obsidian-headless Update Checks

## Status

Accepted

## Context

The Dockerfile pins obsidian-headless to a specific npm version
(`obsidian-headless@0.0.6`) for build reproducibility. When a new
version is published, the maintainer must manually discover it, review
the changes, update the Dockerfile, and push a new image.

obsidian-headless is pre-stable (`0.x`) and under active development
by the Obsidian team. During its first week (Feb 27 – Mar 6, 2026),
six versions were published. The release cadence may slow down as the
package matures, but during active development periods, manual
monitoring is unreliable — especially because:

1. obsidian-headless has no GitHub Releases or tags. The only signal
   for a new version is the npm registry `dist-tags.latest` field.
2. There is no RSS/Atom feed for npm package updates.
3. The npm `CHANGELOG.md` is in the GitHub repo but not published as
   part of the npm package metadata.

### Options considered

**1. Dependabot or Renovate**

Both tools support npm dependency updates. However, this project does
not have a `package.json` — obsidian-headless is installed via
`npm install -g` in the Dockerfile's `RUN` command. Neither Dependabot
nor Renovate can parse version pins from arbitrary Dockerfile `RUN`
commands. Renovate has a `regex` manager that could theoretically be
configured to match the pattern, but the configuration is complex and
the PR body would lack the upstream changelog context that makes
manual review meaningful.

**2. Custom GitHub Actions workflow**

A daily cron workflow that queries the npm registry API, compares
the `dist-tags.latest` version against the Dockerfile pin, and opens
a PR with the version bump, upstream changelog entries, dependency
diff, and commit comparison links. The PR includes an Obsidian-specific
review checklist (sync protocol changes, `ob sync-config` API surface,
E2EE credential format).

**3. Manual monitoring**

Watch the GitHub repo or npm page. Relies on the maintainer remembering
to check. Given the lack of RSS feeds and GitHub Releases, this is
the least reliable option.

## Decision

Use a **custom GitHub Actions workflow** (option 2) at
`.github/workflows/check-headless-update.yml`.

Implementation details:

- **Schedule**: Daily at 08:00 UTC via cron. Manual trigger via
  `workflow_dispatch` for testing.

- **Detection**: Queries `https://registry.npmjs.org/obsidian-headless`,
  extracts `dist-tags.latest`, compares to the version in the Dockerfile
  (extracted via grep).

- **Version validation**: The npm version is validated as a strict
  semver string (`X.Y.Z`) before use in branch names, sed patterns,
  and git operations.

- **Deduplication**: Checks for an existing remote branch
  (`deps/obsidian-headless-X.Y.Z`) and open PR before creating a new
  one. Safe for repeated cron runs and manual re-triggers.

- **PR contents**: The PR body includes:
  - Upstream changelog entries (fetched from GitHub `master` branch,
    extracted via awk between the current and latest version headers)
  - Dependency diff (added/removed/changed npm dependencies, computed
    via jq from the npm registry metadata)
  - Commit comparison link (built from `gitHead` SHAs in npm metadata)
  - Links to npm, upstream repo, and upstream issues
  - A GitHub `> [!WARNING]` callout noting the package is pre-stable
  - An Obsidian-specific review checklist covering sync protocol
    compatibility, `ob sync-config` API surface (ADR-0017 dependency),
    E2EE credential format, native module builds, smoke testing, and
    post-merge verification

- **No auto-merge**: The PR requires manual review and merge. This is
  intentional — obsidian-headless is the core dependency and breaking
  changes in the sync protocol or CLI API could silently break sync
  for all users.

- **PR labels**: `dependencies` and `automated` labels are created
  (if absent) and applied to the PR for easy filtering.

- **Security**: Dependency JSON is passed between steps via temp files,
  not via `${{ }}` template interpolation, to prevent shell injection
  from malicious npm metadata. All shell scripts use `set -euo pipefail`
  and POSIX-compatible constructs (no bashisms).

- **Build isolation**: The PR changes the Dockerfile on a feature
  branch. When merged to main, the existing `docker-publish.yml`
  workflow triggers and builds a new image with the updated dependency.
  No changes to the publish workflow were needed.

## Consequences

**Easier:**

- The maintainer is notified within 24 hours of any new
  obsidian-headless release, with full context for an informed
  merge decision.
- The PR body provides the upstream changelog, dependency diff, and
  review checklist — no need to manually check npm, GitHub, or read
  the CHANGELOG.
- The Obsidian-specific checklist items (sync protocol, `ob sync-config`
  API, E2EE) reduce the risk of merging a breaking change without
  noticing.
- Deduplication prevents PR spam — only one PR per new version.

**Harder:**

- The workflow adds one daily GitHub Actions run (~10 seconds of
  compute on most days). Well within free tier limits.
- The awk changelog extractor uses string-based version comparison.
  If obsidian-headless reaches `0.10.x`, the comparison will break
  (lexicographic: `"0.9" > "0.10"`). This is documented in the
  workflow and should be fixed when it becomes relevant.
- The `gitHead` SHA in npm metadata is not guaranteed to be present
  in future releases (it depends on the publisher's local git state).
  The workflow handles this gracefully — the commit link is omitted
  if either SHA is missing.
- The upstream CHANGELOG.md URL (`master` branch) is hardcoded. If
  the obsidian-headless repo renames its default branch, the changelog
  fetch will fail silently and the PR will note the missing changelog.
- Bot-created PRs accumulate if the maintainer doesn't review them
  promptly during a burst of upstream releases. Each version gets its
  own PR and branch. Stale PRs should be closed manually.
