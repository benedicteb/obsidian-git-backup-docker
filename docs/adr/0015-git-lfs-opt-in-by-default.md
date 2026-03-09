# ADR-0015: Git LFS Opt-In by Default

## Status

Accepted (amends [ADR-0014](0014-git-lfs-for-binary-assets.md))

## Context

ADR-0014 enabled Git LFS by default (`OBSIDIAN_GIT_LFS_ENABLED=true`).
The rationale was that most users with binary attachments would benefit,
and enabling it by default would prevent repository bloat without
requiring users to know about LFS.

In practice, **many git servers do not have LFS enabled by default**.
Self-hosted git servers (bare repos, Gitea/Forgejo instances without
LFS storage configured, older GitLab installations) will reject LFS
pushes with "LFS server not found" or similar errors. Even on managed
providers, LFS has storage and bandwidth quotas that users may not
expect.

Enabling LFS by default means users who haven't thought about LFS —
the majority — encounter push failures on first use. This is a poor
first-run experience. The failure message comes from `git-lfs`, not
from this project, and may not be immediately actionable for users
unfamiliar with LFS.

### Options considered

**1. Keep LFS enabled by default (status quo from ADR-0014)**

Users with LFS-capable remotes get automatic benefits. Users without
LFS support see confusing push failures.

**2. Disable LFS by default, make it easy to enable**

Users who want LFS set one environment variable. No surprises for
users whose git remotes don't support LFS. The `git-lfs` package
remains installed so enabling requires no image rebuild.

**3. Auto-detect LFS support on the remote**

Probe the git remote for LFS capability at init time. Complex to
implement reliably across SSH/HTTP transports and provider
variations. Over-engineered for a single environment variable.

## Decision

Use option 2: **disable Git LFS by default**.

All LFS infrastructure remains in the image (`git-lfs` package,
init-config.sh LFS setup code, `.gitattributes` managed block).
Users enable it by setting:

```
OBSIDIAN_GIT_LFS_ENABLED=true
```

Changes from ADR-0014:

| Location | Before | After |
|---|---|---|
| Dockerfile `ENV` | `true` | `false` |
| init-config.sh fallback | `true` | `false` |
| .env.example comment | `Default: true` | `Default: false` |
| Unraid template `Default=` | `true` | `false` |
| README env vars table | `true` | `false` |
| README LFS section | "enabled by default" | "disabled by default" |

## Consequences

**Easier:**

- First-run experience is clean for all users, regardless of their
  git remote's LFS support.
- No confusing LFS push errors for users who didn't ask for LFS.
- Users who want LFS make an explicit, informed choice.
- The `git-lfs` package is still installed — enabling is one env var
  away, no image rebuild needed.

**Harder:**

- Users with large binary attachments who would benefit from LFS must
  discover and enable it themselves. The README documents LFS
  prominently with enabling instructions.
- Existing users upgrading from a version with LFS enabled by default
  will find LFS disabled after the upgrade unless they explicitly set
  `OBSIDIAN_GIT_LFS_ENABLED=true`. Previously LFS-tracked files
  remain in LFS (the `.gitattributes` and LFS hooks persist in the
  repo), but new files will be committed directly to git. Users who
  want to continue using LFS must add the variable to their `.env`.
