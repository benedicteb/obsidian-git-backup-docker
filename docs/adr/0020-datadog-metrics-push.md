# ADR-0020: Datadog Metrics Push for Docker Hub Pull Count

## Status

Accepted (amends [ADR-0018](0018-privacy-friendly-pull-count-metrics.md))

## Context

ADR-0018 established a daily GitHub Actions workflow that records Docker
Hub pull counts to a CSV file in the repository. This provides a local
time series, but the data is not queryable, alertable, or visualisable
without manual effort (loading the CSV into a spreadsheet or script).

The project maintainer uses Datadog (EU1 region) for infrastructure
monitoring. Pushing the pull count as a Datadog gauge metric would
enable dashboards, alerts (e.g., pull count plateau suggesting a broken
image), and correlation with other operational metrics — all without
replacing the existing CSV approach.

### Options considered

**1. Add Datadog push to the existing metrics workflow**

Add a step to `metrics.yml` that calls the Datadog v1 series API after
fetching the pull count. Reuses the already-fetched count. No new
workflow, no new cron schedule, no coordination/locking needed.

**2. Separate Datadog-specific workflow**

A new `datadog-metrics.yml` workflow on its own cron schedule. Cleaner
separation but duplicates the Docker Hub API fetch and adds a second
daily cron job. If the two workflows run at different times, the counts
could differ slightly (though pull_count is monotonically increasing, so
the difference would be negligible).

**3. Use Datadog's Docker Hub integration**

Datadog has a Docker integration, but it monitors running containers via
the Agent — it does not track Docker Hub pull counts for public images.
No built-in integration exists for this metric.

## Decision

Use option 1: **add a Datadog push step to the existing `metrics.yml`
workflow**.

Implementation details:

- **API**: Datadog v1 Submit Metrics (`POST /api/v1/series`). This is
  the simplest metrics ingestion endpoint — a single HTTP POST with
  a JSON payload. No SDK, no Agent, no additional dependencies.

- **Endpoint**: `https://api.datadoghq.eu/api/v1/series` (EU1 region).
  Hardcoded because the maintainer uses EU1 and this workflow is not
  intended to be portable across Datadog regions. If the region changes,
  the URL is a single-line edit.

- **Metric name**: `obsidian_git_backup.docker_pulls` — namespaced
  under the project name to avoid collisions with other custom metrics.

- **Metric type**: `gauge` — the Docker Hub pull_count is a cumulative
  total. Each data point reports the absolute value at a point in time.
  Datadog can derive rates (pulls/day) from a gauge via query functions.

- **Tags**: `repo:benedicteb/obsidian-git-backup` and
  `source:github_actions` for filtering and grouping.

- **Authentication**: `DD_API_KEY` GitHub secret. This is a Datadog
  API key (not an Application key). API keys have write-only access
  to the ingestion endpoints — they cannot read data, modify dashboards,
  or access account settings.

- **Optional**: The step checks `DD_API_KEY` at runtime. If the secret
  is not configured (empty string), the step prints a skip message and
  exits 0. Forks and contributors without the secret are unaffected.

- **Failure handling**: The step never fails the workflow. Network
  errors (`curl` exit code + HTTP 000) produce a GitHub Actions warning
  annotation and exit 0. HTTP 403 produces a specific actionable
  message ("check that DD_API_KEY is valid and has metrics:write
  scope"). Other HTTP errors produce a generic warning. In all failure
  cases, the CSV recording and git commit steps proceed normally.

- **JSON construction**: Uses `printf '%d'` format specifiers for
  timestamp and pull count values. This makes numeric injection
  structurally impossible — `printf %d` coerces any input to an
  integer, regardless of what the variable contains.

- **Ordering**: The Datadog step runs after the CSV fetch/record step
  and before the git commit step. It depends on `steps.fetch.outputs.count`
  (skipped via `if:` when the count is empty, which happens when
  today's date is already recorded).

## Consequences

**Easier:**

- Pull count trends are visible in Datadog dashboards alongside other
  infrastructure metrics. No manual CSV analysis needed for trend
  monitoring.
- Alerts can be configured in Datadog (e.g., pull count hasn't
  increased in 7 days → possible broken image or delisting).
- The existing CSV recording is preserved unchanged — Datadog is a
  parallel output, not a replacement. If Datadog is unavailable or
  the API key is removed, the CSV continues working.
- The step is a net 30 lines of YAML/shell. No new files, no new
  dependencies, no new cron schedule.

**Harder:**

- The EU1 endpoint URL is hardcoded. If the project moves to a
  different Datadog region, the URL must be changed manually. This is
  a deliberate simplicity trade-off — adding `DD_SITE` configurability
  for a single-maintainer project adds complexity with no current
  benefit.
- `DD_API_KEY` is a new GitHub secret to manage. It has write-only
  scope (metrics ingestion), so the blast radius of a leak is limited
  to sending garbage metrics — it cannot read existing data or modify
  Datadog configuration.
- ADR-0018's "Consequences" section states "no external services, no
  credentials beyond the default `GITHUB_TOKEN`." This is now stale —
  `DD_API_KEY` is an optional external credential. This ADR serves as
  the amendment.
- Datadog's custom metrics pricing applies. One gauge metric with one
  data point per day is well within free tier limits. If additional
  metrics are added in the future, pricing should be reviewed.
