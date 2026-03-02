#!/bin/sh
# =============================================================================
# log-prefix.sh — Run a command with a log prefix on every output line
#
# Usage: log-prefix.sh PREFIX COMMAND [ARGS...]
#
# Runs COMMAND as a direct child process, forwarding SIGTERM/SIGINT.
# Reads COMMAND's stdout+stderr line by line and prepends PREFIX.
#
# This avoids the pipeline problems of `cmd | sed 's/^/prefix/'`:
#   - Signal delivery: SIGTERM is forwarded to the child explicitly
#   - Exit code: the real exit code is preserved and returned to s6
#   - No SIGPIPE risk: the child writes to a FIFO, not a pipe
#
# Requires: mkfifo (coreutils)
# =============================================================================
set -eu

PREFIX="$1"
shift

# Create a temporary FIFO for capturing output
FIFO="$(mktemp -u /tmp/log-prefix.XXXXXX)"
mkfifo "${FIFO}"

# Start the prefixer in the background — reads from FIFO, writes to stdout.
# Uses a while-read loop instead of sed because BusyBox sed does not support
# -u (unbuffered). Shell's built-in read/echo is naturally line-buffered.
#
# Timestamps use ISO 8601 UTC with Z suffix, matching log-functions.sh output.
#
# NOTE: Timestamps reflect when this reader loop processed each line,
# not when the child process emitted it. Under normal load the delta is
# negligible (<1ms), but timestamps should not be treated as high-precision
# event times during a performance investigation.
#
# NOTE: Each line forks a `date` process (~1-3ms on Alpine/musl). This is
# fine for ob sync's low-volume output but would bottleneck at ~300-1000
# lines/second. Do not use this wrapper for high-throughput commands.
while IFS= read -r line; do
    printf '%s %s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${PREFIX}" "${line}"
done < "${FIFO}" &
READER_PID=$!

# Run the actual command, sending stdout+stderr to the FIFO.
# This is a direct child of this script, so we can signal it explicitly.
"$@" > "${FIFO}" 2>&1 &
CMD_PID=$!

# On SIGTERM/SIGINT: forward to the command, then clean up.
# The EXIT trap handles FIFO removal regardless of how we exit.
trap 'kill -TERM "${CMD_PID}" 2>/dev/null || true' TERM INT
trap 'rm -f "${FIFO}"' EXIT

# Wait for the command to finish and capture its exit code.
#
# Disable set -e for the wait block: we need to capture the child's exit
# code without the shell aborting on non-zero. If a trapped signal (TERM/INT)
# interrupts wait, it returns 128+signum; we then re-wait for the real code.
set +e
wait "${CMD_PID}" 2>/dev/null
EXIT_CODE=$?
if [ "${EXIT_CODE}" -gt 128 ] 2>/dev/null; then
    # wait was interrupted by a signal. Re-wait for the child's real exit code.
    wait "${CMD_PID}" 2>/dev/null
    EXIT_CODE=$?
fi
set -e

# Command is done — its side of the FIFO is closed, the reader gets EOF.
wait "${READER_PID}" 2>/dev/null || true

exit "${EXIT_CODE}"
