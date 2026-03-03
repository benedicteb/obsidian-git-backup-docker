# ADR-0008: Manual Docker Hub README Updates

## Status

Accepted (supersedes the README sync part of [ADR-0006](0006-github-actions-docker-hub-publishing.md))

## Context

ADR-0006 included automated README syncing to Docker Hub via the
`peter-evans/dockerhub-description` GitHub Action. In practice, this
step failed with `403 Forbidden` on every CI run.

The Docker Hub API endpoint for updating repository descriptions
(`PATCH /v2/repositories/{namespace}/{repo}`) requires authentication
via a **Docker Hub account password** — not a scoped Personal Access
Token (PAT). The scoped PAT used for image pushes (`DOCKERHUB_TOKEN`)
authenticates successfully for registry operations (push/pull) but is
rejected by the repository description endpoint.

### Options considered

**1. Store Docker Hub password as a GitHub secret**

Create a `DOCKERHUB_PASSWORD` secret and use it for the description
sync step. The image push continues using the scoped PAT.

- Works, but storing an account password in CI is a security concern.
  The password grants full account access (billing, org settings,
  deletion of any repository) — far broader than needed for updating
  one repo's description.
- If the secret leaks, the blast radius is the entire Docker Hub
  account, not just one repository.

**2. Use a Docker Hub account-level access token**

Docker Hub previously offered "classic" account-level tokens that
worked with the description API. These are being phased out in favor
of scoped PATs, which do not support the description endpoint. This
option has no future.

**3. Update the README on Docker Hub manually**

Remove the automated sync step. Update the Docker Hub description
through the web UI when the README changes significantly. The README
changes infrequently — major updates happen during feature development,
not on every commit.

**4. Use the Docker Hub web UI API with a session token**

Scrape a session token from a browser login and store it as a secret.
Fragile, undocumented, and would break without warning.

## Decision

Use **manual README updates** (option 3). The `peter-evans/dockerhub-description`
step has been removed from the CI workflow.

To update the Docker Hub README:

1. Go to [hub.docker.com/r/benedicteb/obsidian-git-backup](https://hub.docker.com/r/benedicteb/obsidian-git-backup)
2. Click the repository overview → edit
3. Paste the contents of `README.md`
4. Save

## Consequences

**Easier:**

- No account password stored in CI. The only Docker Hub credential in
  GitHub Actions is a scoped PAT with minimal permissions (push/pull).
- CI runs no longer fail on the final step. The workflow status
  accurately reflects whether the image was built and pushed.
- One fewer third-party GitHub Action in the supply chain
  (`peter-evans/dockerhub-description` removed).

**Harder:**

- The Docker Hub README can drift from the repo's `README.md`. This is
  acceptable because the README changes infrequently, and the GitHub
  repo is the canonical source. Users who find the image on Docker Hub
  are linked to the GitHub repo for full documentation.
- Updating the Docker Hub README is a manual step that someone must
  remember. In practice, this matters only for major documentation
  changes (new features, changed env vars, new setup steps).
