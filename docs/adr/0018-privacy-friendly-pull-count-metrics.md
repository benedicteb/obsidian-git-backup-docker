# ADR-0018: Privacy-Friendly Docker Hub Pull Count Metrics

## Status

Accepted

## Context

The project had no visibility into how many people were using the Docker
image. Understanding adoption trends is useful for prioritising features,
gauging community interest, and providing social proof to potential users
evaluating the tool.

Docker Hub exposes a public `pull_count` field on its API
(`/v2/repositories/{namespace}/{repo}/`). This is a single aggregate
counter — no individual user data, IP addresses, or identifiers are
exposed. It increments on every `docker pull` regardless of
authentication status.

### Options considered

**1. Docker Hub pull_count badge only**

Add a shields.io badge to the README. Zero infrastructure, instant.
Shows point-in-time count but no historical trend data.

**2. Badge + daily cron scraper**

Add the badge AND a GitHub Actions workflow that records the
pull_count daily to a CSV file in the repository. Provides a time
series for trend analysis while remaining fully privacy-friendly.

**3. Docker Hub Pro/Team analytics**

Paid tier ($5-9/month) provides time-series pull graphs and
geographic breakdown. More detailed but costs money and the
geographic data (country-level) is arguably more than needed.

**4. Third-party analytics service (e.g., Google Analytics on docs)**

Would require tracking code on documentation pages. Invasive,
requires cookie consent, and doesn't measure actual Docker pulls.

## Decision

Use option 2: **shields.io badge + daily GitHub Actions cron scraper**.

Implementation:

- **Badge**: A Docker Pulls shields.io badge in the README, linking
  to the Docker Hub page. Shows the current aggregate count.

- **Daily scraper**: A GitHub Actions workflow (`metrics.yml`) runs
  at 06:00 UTC daily. It fetches the Docker Hub API, validates the
  response is numeric, checks for CSV header integrity, and appends
  a `date,pull_count` row to `docs/metrics/pulls.csv`.

- **Idempotency**: The workflow skips if today's date is already
  recorded. Safe for manual re-runs via `workflow_dispatch`.

- **Build isolation**: The Docker publish workflow
  (`docker-publish.yml`) uses `paths-ignore: ['docs/metrics/**']`
  to prevent metrics commits from triggering image builds. Bot
  commits are also filtered from release changelogs by author
  (`--invert-grep --author="github-actions[bot]"`).

- **Concurrency**: A `concurrency` group with
  `cancel-in-progress: false` serialises overlapping runs (e.g.,
  manual trigger during cron execution).

- **Commit identity**: Uses `github-actions[bot]` with scoped
  commit prefix `chore(metrics):` and includes the pull count in
  the message for distinguishable log entries.

- **Failure policy**: API failures produce a gap in the CSV. This
  is documented and acceptable — pull counts are a trend metric,
  not a critical data source. Gaps can be filled by manual
  `workflow_dispatch` re-runs.

## Consequences

**Easier:**

- Adoption trends are visible at a glance (badge) and over time
  (CSV). No third-party analytics, no cookies, no user tracking.
- The CSV is a simple, portable format that can be loaded into any
  spreadsheet, pandas, or charting tool.
- The shields.io badge provides social proof for potential users
  evaluating the tool.
- The workflow is self-contained — no external services, no
  credentials beyond the default `GITHUB_TOKEN`.

**Harder:**

- The CSV file grows by one row per day (~365 rows/year, ~4 KB).
  Negligible storage impact.
- Docker Hub pull counts are noisy — they include CI pulls,
  security scanner pulls, and mirror/proxy cache pulls. The number
  represents total pulls, not unique users.
- Bot commits appear in `git log` on main. Mitigated by using a
  scoped conventional commit prefix (`chore(metrics):`) and
  filtering bot commits from release changelogs.
- API failures produce gaps. Documented as acceptable.
- The workflow adds one daily GitHub Actions run (~10 seconds of
  compute). Well within free tier limits.
