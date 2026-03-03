# ADR-0010: GitHub Releases with Categorised Changelog

## Status

Accepted (amends [ADR-0006](0006-github-actions-docker-hub-publishing.md))

## Context

ADR-0006 established the CI/CD pipeline with automatic versioning from
conventional commits. However, the workflow only created bare annotated
git tags (`git tag -a vX.Y.Z`). Users could see version numbers but had
no way to know what changed between releases without reading raw commit
logs.

The ADR-0006 Consequences section explicitly noted this gap: "no
changelog generation, no release notes on GitHub."

### Options considered

**1. GitHub's auto-generated release notes**

`gh release create --generate-notes` uses GitHub's built-in algorithm
(PR titles, new contributors). Does not work well for this project
because most changes are pushed directly to `main` without PRs, so
the auto-generated notes would be sparse or empty.

**2. Third-party changelog tool (e.g., `conventional-changelog`, `semantic-release`)**

Full-featured but adds a Node.js dependency to the CI pipeline. The
workflow already runs a hand-rolled conventional commit parser for
versioning — adding a second tool for changelog generation introduces
duplication and dependency weight.

**3. Hand-rolled changelog from `git log` grouped by commit type**

Extend the existing shell-based conventional commit parsing to
categorise commits into sections (Breaking Changes, Features, Fixes,
Other). Output as Markdown. Uses only `git log`, `grep`, `sed` — tools
already available on the runner. Consistent with the hand-rolled
versioning approach from ADR-0006.

## Decision

Use **hand-rolled changelog generation** (option 3) and create
**GitHub Releases** instead of bare git tags.

Implementation details:

- **Changelog generation**: A new workflow step after the Docker build
  runs `git log --pretty=format:"%s"` over the commit range and
  categorises each commit subject by its conventional commit prefix:
  - `type!:` → Breaking Changes
  - `feat:` → Features
  - `fix:` → Fixes
  - Everything else → Other
  - Commit bodies are also scanned for `BREAKING CHANGE` footers

- **Output format**: Markdown with `###` section headers, bulleted
  commit subjects, and a Docker pull command at the bottom. Written
  to a temp file and passed to `gh release create --notes-file`.

- **GitHub Release replaces bare tag**: `gh release create` creates
  the git tag and the GitHub Release atomically. This replaces the
  previous `git tag -a` + `git push origin` approach. The release
  appears on the repository's Releases page with the full changelog.

- **Temp file approach**: Commit subjects are written to categorised
  temp files (`*.breaking`, `*.feat`, `*.fix`, `*.other`) to avoid
  shell variable mutation issues in pipeline subshells. Cleaned up
  after the changelog is assembled.

- **First release handling**: When `previous_tag` is `v0.0.0` (no
  prior tags exist), the changelog header reads "First release."
  instead of "Changes since v0.0.0:".

## Consequences

**Easier:**

- Users can see what changed in each release directly on the GitHub
  Releases page without reading raw commit logs.
- The Docker pull command in each release body tells users exactly
  how to get that specific version.
- GitHub Releases provide an Atom feed (`/releases.atom`) that users
  can subscribe to for update notifications.
- The changelog categories (Features, Fixes, Other) help users quickly
  assess the impact and relevance of an update.
- No additional dependencies — uses `git`, `grep`, `sed`, and `gh`,
  all pre-installed on GitHub Actions runners.

**Harder:**

- The changelog is commit-subject-level, not curated. Noisy commit
  histories (e.g., many `docs:` or `chore:` commits) produce long
  "Other" sections. Acceptable for a pre-stable project with
  conventional commit discipline.
- The hand-rolled parser does not handle scoped types (`feat(sync):`)
  specially — they are grouped with their unscoped counterparts. This
  is correct behaviour but loses the scope information in the grouping.
- Merge commits or non-conventional commit messages end up in the
  "Other" category. The project uses conventional commits consistently,
  so this is rarely an issue.
- The changelog format is fixed (Markdown sections). Switching to a
  different format (e.g., keep-a-changelog, JSON) would require
  rewriting the generation step.
