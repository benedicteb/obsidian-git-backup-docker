# ADR-0005: Shared Timestamped Logging Library

## Status

Accepted

## Context

Each shell script in the project (init-usermap.sh, init-config.sh,
git-watcher.sh) defined its own `log()` and `log_error()` functions
inline, all using `echo` with a hardcoded `[service-name]` prefix:

```sh
log() { echo "[init-config] $*"; }
log_error() { echo "[init-config] ERROR: $*" >&2; }
```

Additionally, `log-prefix.sh` (the FIFO-based output wrapper for
obsidian-sync) used a `printf` with only a `[service-name]` prefix.

None of the log output included timestamps. When viewing `docker logs`
output, it was impossible to determine when events occurred without
using `docker logs --timestamps`, which is not available in all viewing
contexts (log files, log shippers, piped output).

### Options considered

**1. Add timestamps inline to each script**

Each script continues to define its own `log()` function, but adds
a `date` call. Simple, but duplicates the format string in 4 places.
Any format change requires updating all scripts in lockstep.

**2. Shared logging library (sourced)**

A single `log-functions.sh` file defines `log()`, `log_error()`, and
`log_banner()`. Each script sets `LOG_TAG` and sources the library.
The format string lives in one place.

**3. External logging tool (e.g., logger, svlogd)**

Use syslog or s6-log for structured logging. This would require a log
service and would not appear in `docker logs` output (dealbreaker for
UX — see ADR-0004).

## Decision

Use a **shared logging library** (option 2) at
`/usr/local/lib/log-functions.sh`.

Implementation details:

- **Format**: `2026-03-02T14:30:05Z [service-name] message`
  - ISO 8601 UTC with trailing `Z` suffix
  - UTC chosen because containers typically run in UTC
  - `Z` suffix avoids BusyBox `%z` formatting quirks (`+0000` vs `+00:00`)

- **Sourcing pattern**: Scripts set `LOG_TAG` then source the file:
  ```sh
  LOG_TAG="init-config"
  . /usr/local/lib/log-functions.sh
  ```

- **Guard**: `: "${LOG_TAG:?...}"` fails immediately if LOG_TAG is unset,
  catching programming errors at source time.

- **Functions provided**:
  - `log()` — stdout, informational
  - `log_error()` — stderr, error messages
  - `log_banner()` — visually prominent messages (SSH key generation)

- **log-prefix.sh**: Uses the same `date -u '+%Y-%m-%dT%H:%M:%SZ'`
  format in its FIFO reader loop for consistency.

- **Performance**: Each `log()` call forks a `date` process (~1-3ms on
  Alpine/musl). Acceptable for all current use cases. Not suitable for
  high-throughput logging (documented in log-prefix.sh comments).

## Consequences

**Easier:**

- All log output includes timestamps, making `docker logs` output
  self-contained and useful for debugging sync timing issues.
- Timestamp format is consistent across all services (init, sync, watcher).
- Format changes (e.g., adding log levels, switching to JSON) require
  editing only one file.
- Log lines are grep-able and parseable by log aggregators.
- Timestamps help correlate obsidian-sync events with git-watcher commits,
  especially for diagnosing debounce window timing.

**Harder:**

- `docker logs --timestamps` produces double timestamps. Documented in
  the library header as an intentional trade-off.
- Each log line forks a `date` subprocess. Negligible for current use
  but would bottleneck at ~300-1000 lines/second.
- log-prefix.sh timestamps reflect reader-loop processing time, not
  child process emission time. Documented in comments.
