# ADR-0016: Pull Strategy — Rebase-First with Merge Fallback and Periodic Pull

## Status

Accepted

## Context

The git-watcher ran `git pull --rebase` before each push, but this failed
permanently in three scenarios:

### 1. Unrelated histories

If the container initialized the repo against an empty remote (first push
creates the branch), and then someone independently initialized the remote
(e.g., created a repo with a README on GitHub, or pushed from another
machine), the two histories share no common ancestor. `git pull --rebase`
fails with `fatal: refusing to merge unrelated histories`, the rebase is
aborted, and the push fails on every subsequent cycle — forever.

### 2. Rebase conflicts

If the remote has changes to the same files that were changed locally
(e.g., `.gitignore` managed block was edited on both sides, or someone
manually edited a note that Obsidian Sync also delivered), `git pull
--rebase` fails with a merge conflict. The old code aborted the rebase
and retried on the next file change — but the same conflict would recur
every time, creating an infinite failure loop.

### 3. Remote advances with no local changes

The pull only happened before a push, which was triggered by inotifywait
detecting a local file change. If the remote advanced (someone pushed a
change directly) and no local changes occurred, the local repo stayed
behind indefinitely. This is not a failure per se, but it means the
local working tree diverges from the remote, and the next push attempt
may face unnecessary conflicts.

### Options considered for conflict resolution

**1. Rebase with local wins (`git rebase -X theirs`)**

In rebase context, `theirs` means the commits being replayed (our local
commits). Keeps linear history. Local content always wins. But the
confusing flag naming (`theirs` = ours) is a maintenance risk.

**2. Merge fallback with local wins (`git pull --no-rebase -X ours`)**

Creates a merge commit that auto-resolves all conflicts by keeping
local content. Both histories are fully preserved as parents of the
merge commit. Nothing is lost — `git log` shows all remote commits,
and `git diff` against either parent shows exactly what happened.

**3. Force push**

Overwrite the remote with local state. Destructive — loses remote
history. Only appropriate if the container is the sole writer, which
cannot be guaranteed.

### Options considered for periodic pull

**1. Separate s6 longrun service**

A dedicated `git-puller` service that runs on a timer. Clean separation
but requires coordination with the watcher to avoid concurrent git
operations (file locking, mutex). Adds s6-rc service definition files.

**2. Integrated into git-watcher.sh via inotifywait read timeout**

Use `read -t INTERVAL` on the inotifywait pipe. When the timeout fires
(no local changes), do a pull. When a file event arrives, proceed with
the existing debounce + commit + push flow. No new service, no locking
needed, shares the same process and state.

## Decision

### Conflict resolution: rebase-first, merge fallback (option 2)

Extract a `do_pull()` function that implements a two-stage strategy:

1. **Try `git pull --rebase --allow-unrelated-histories`** — preferred
   because it keeps a linear commit history. The
   `--allow-unrelated-histories` flag handles scenario 1 (independently
   initialized repos).

2. **If rebase fails, abort and fall back to
   `git pull --no-rebase --allow-unrelated-histories -X ours`** — creates
   a merge commit where conflicts are auto-resolved by keeping the local
   (Obsidian Sync) content. Non-conflicting remote changes are merged in
   normally. All remote history is preserved as a parent of the merge
   commit.

The `-X ours` strategy is appropriate because this container's local
content is the source of truth — it comes directly from Obsidian Sync.
If someone pushed conflicting changes to the remote, the Obsidian Sync
version should win. The remote changes are not lost; they remain in the
git history and can be recovered from the merge commit's remote parent.

### Periodic pull: integrated via read timeout (option 2)

A new `OBSIDIAN_GIT_PULL_INTERVAL` environment variable (default: 300
seconds / 5 minutes) controls how often the watcher checks the remote
for changes when no local file events have occurred.

Implementation:

- The outer `read` in the inotifywait pipe loop uses `read -t` with the
  pull interval as the timeout.
- On timeout (no file events): run `do_pull()` only (no commit needed).
- On file event: proceed with the existing debounce + commit + push flow.
- `PULL_INTERVAL=0` disables periodic pulling entirely (blocks on read).
- Minimum value is 10 seconds to avoid overly aggressive network
  operations and to distinguish timeout from EOF reliably.

EOF detection: `read -t` returns non-zero on both timeout and EOF (pipe
closed). These are distinguished by measuring wall-clock time — a real
timeout takes approximately PULL_INTERVAL seconds, while EOF returns
almost instantly (< 2 seconds).

## Consequences

**Easier:**

- Unrelated histories are handled automatically. Users who initialized
  the remote independently no longer see permanent push failures.
- Rebase conflicts are auto-resolved. The container never gets stuck in
  an infinite failure loop due to conflicting changes.
- Remote-only changes are picked up within PULL_INTERVAL seconds, even
  when no local Obsidian changes occur.
- All remote history is preserved in merge commits — nothing is ever
  lost or overwritten.
- The `do_pull()` function is reusable — called from both the
  commit-and-push path and the periodic pull path.
- No new s6 services, no locking, no additional processes. The periodic
  pull is a natural extension of the existing inotifywait read loop.

**Harder:**

- Merge commits create non-linear history when rebase fails. Users who
  prefer a strictly linear git history may find this undesirable.
  However, for a backup tool, data preservation is more important than
  history aesthetics.
- The `-X ours` strategy silently resolves conflicts by keeping local
  content. Users who pushed intentional changes to the remote may not
  realize their changes were overridden in the working tree (though the
  changes remain in git history). This is an acceptable trade-off
  because Obsidian Sync is the authoritative source for vault content.
- The `--allow-unrelated-histories` flag could theoretically merge
  completely unrelated repositories if the remote URL is misconfigured.
  This is unlikely in practice and the worst case is extra files in the
  working tree (which Obsidian ignores if they're not markdown).
- The EOF-vs-timeout detection heuristic (< 2 seconds = EOF) is
  imperfect. A very slow system under extreme load could theoretically
  misdetect a timeout as EOF. The minimum PULL_INTERVAL of 10 seconds
  provides a large safety margin.
- The periodic pull adds network traffic (one `git fetch` per interval).
  The default 5-minute interval is conservative. Users on metered
  connections or very slow networks can increase it or set it to 0.
