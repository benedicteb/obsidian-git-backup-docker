# ADR-0004: FIFO-Based Log Prefixing Instead of Shell Pipelines

## Status

Accepted

## Context

The `obsidian-sync` service runs `ob sync --continuous`, which outputs bare
messages like "Fully synced" to stdout. These are indistinguishable from
`git-watcher` output in `docker logs`, making it hard to identify which
service produced a given line.

The initial implementation used a shell pipeline to prefix output:

```sh
su-exec obsidian sh -c 'exec ob sync ...' | sed -u 's/^/[obsidian-sync] /'
```

Subagent reviews (linux-expert, obsidian-expert) identified three critical
issues with this approach:

### 1. Signal handling — orphaned processes

s6-overlay's `s6-supervise` sends SIGTERM to its **direct child** — the
shell running the `run` script. In a pipeline, the shell forks `ob` and
`sed` as children. When the shell receives SIGTERM, `ob` and `sed` are
reparented to PID 1 and continue running as orphans. s6 considers the
service "down" and may restart it, resulting in two `ob sync` instances
racing against each other.

### 2. Exit code masking

In POSIX sh, the exit code of a pipeline is the exit code of the **last
command** (`sed`). When `ob` crashes, `sed` reads EOF and exits 0. s6 sees
exit 0 and cannot distinguish a crash from a clean shutdown. BusyBox ash
does not support `set -o pipefail`.

### 3. SIGPIPE risk

If `sed` dies (OOM, crash), the pipe breaks. When `ob` next writes a log
line, the kernel delivers SIGPIPE, which terminates `ob` immediately
without graceful shutdown.

### Additional finding: BusyBox sed -u

BusyBox `sed` on Alpine does not support the `-u` (unbuffered) flag,
causing an immediate error. This was discovered during container testing.

### Options considered

**1. Shell pipeline with signal trap**

Add a TERM trap to the `run` script that `kill -TERM 0` (kill process
group). Mitigates the orphan problem but not exit code masking or SIGPIPE.
Complex to get right.

**2. s6-log native logging service**

Use s6's `log/run` with `s6-log` for prefixed log rotation. Idiomatic for
s6 but writes to rotated files on disk — `docker logs` would show nothing.
Users expect `docker logs` to work; this is a dealbreaker for UX.

**3. FIFO-based wrapper script**

Run `ob` as a direct child writing to a named FIFO. A background reader
prefixes lines from the FIFO. Signals are forwarded explicitly. Exit code
is captured directly from `wait`. No pipeline; no SIGPIPE.

## Decision

Use a **FIFO-based wrapper script** (`log-prefix.sh`) — option 3.

Implementation:

- **`log-prefix.sh`** is a general-purpose wrapper:
  `log-prefix.sh PREFIX COMMAND [ARGS...]`
- Creates a temporary FIFO (`mkfifo`), starts a background reader
  (`while IFS= read -r`), then runs the command writing to the FIFO.
- SIGTERM/SIGINT are trapped and forwarded to the command's PID.
- The command's real exit code is captured via `wait` and returned.
- Uses `while read` + `printf` instead of `sed -u` for BusyBox
  compatibility.

The `obsidian-sync/run` script becomes:

```sh
exec su-exec obsidian /usr/local/bin/log-prefix.sh "[obsidian-sync]" \
  ob sync --continuous --path /vault
```

## Consequences

**Easier:**

- `docker logs` output is clearly attributable to its source service.
- Signal delivery is explicit and reliable — no orphaned processes.
- `ob`'s real exit code reaches s6, enabling proper crash detection.
- The wrapper is reusable for any service that needs log prefixing.
- No additional Alpine packages required.

**Harder:**

- A temporary FIFO is created in `/tmp` per invocation. Cleaned up on exit
  via EXIT trap, but a hard kill (SIGKILL) could leave an orphaned FIFO.
- The while-read loop is slower than `sed` for high-throughput output. Not
  an issue for `ob sync`'s low-volume log output.
- Shell `read` strips trailing newlines from empty lines. Acceptable for
  log prefixing; would not be appropriate for binary-safe piping.
- Adds ~60 lines of shell script to maintain. The script is well-commented
  and tested.

**Future improvement (deferred):**

The UX reviewer noted that repeated "Fully synced" heartbeat messages are
noisy. Deduplication could be added to `log-prefix.sh` (or a separate
filter) in the future, but is not implemented now to keep the wrapper
simple and general-purpose.
