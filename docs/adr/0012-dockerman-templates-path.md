# ADR-0012: Docker Manager Templates Path for Unraid 7.x

## Status

Accepted (supersedes [ADR-0011](0011-ca-private-repository-install-method.md))

## Context

ADR-0011 documented the CA private repository method for installing the
template on Unraid. Users were instructed to download the XML to:

```
/boot/config/plugins/community.applications/private/obsidian-git-backup/
```

Testing on Unraid 7.0.x revealed two problems:

1. **The template did not appear in the Apps tab.** After placing the XML
   in the CA private directory and refreshing, the template was not
   discoverable via search or the Private category. The CA plugin's
   private repository scanning behaviour appears to have changed in
   Unraid 7.x.

2. **The CA private path requires the CA plugin.** Users without CA
   installed (or with a different CA version) have no way to use the
   template.

Separately, when the template was placed in the Docker Manager templates
directory (`/boot/config/plugins/dockerMan/templates/`), it appeared
immediately in the Docker tab's "Select a template" dropdown — but the
form was blank. This was caused by multi-line `<Config>` tag formatting
and `&#xD;` entities in the Overview field that Unraid's XML parser
could not handle. After reformatting the XML to single-line Config tags,
the template populated correctly.

### Options considered

**1. Docker Manager templates directory**

Place the XML in `/boot/config/plugins/dockerMan/templates/`. This is
Unraid's built-in template mechanism, predating CA. The template appears
in Docker tab > Add Container > "Select a template" dropdown. No CA
plugin required. Works on all Unraid versions (6.x and 7.x).

**2. Keep CA private directory, debug Unraid 7.x issue**

Investigate why CA's private repository scanning changed in 7.x. This
would require access to CA's source code or forum support from Squid.
The outcome is uncertain and the fix would only help users with CA
installed.

**3. Both paths simultaneously**

Document the dockerMan path as primary and the CA private path as a
fallback. Adds complexity to the instructions for uncertain benefit.

## Decision

Use the **Docker Manager templates directory** (option 1) as the sole
documented install method.

Implementation:

- **Single curl command**: No `mkdir` needed — the `dockerMan/templates/`
  directory already exists on all Unraid installations.

  ```sh
  curl -fsSL -o /boot/config/plugins/dockerMan/templates/obsidian-git-backup.xml \
    https://raw.githubusercontent.com/benedicteb/obsidian-git-backup-docker/main/obsidian-git-backup.xml
  ```

- **Access via Docker tab**: Users go to Docker tab > Add Container >
  select `obsidian_git_backup` from the template dropdown.

- **No CA dependency**: The Docker Manager templates path is part of
  Unraid's core Docker support, not the CA plugin. This works even if
  CA is not installed.

- **XML formatting requirements**: Unraid's Docker Manager XML parser
  requires `<Config>` tags on single lines (no multi-line attribute
  splitting). The `<Overview>` field must not use `&#xD;` entities.
  These constraints are documented here for future template edits.

Additional XML fixes applied during this investigation:

- `<Name>` changed from `obsidian-git-backup` to `obsidian_git_backup`
  (Unraid 7.x may reject hyphens in container names).
- Added explicit `<WebUI/>` element.
- Trimmed `<Requires>` to hard prerequisites only.
- Changed Vault Storage from `Required="true"` to `Required="false"`.

## Consequences

**Easier:**

- One `curl` command, no directory creation, no CA plugin required.
- Works on all Unraid versions (6.x and 7.x) without version-specific
  instructions.
- Template appears immediately in the dropdown — no refresh ritual.
- Simpler instructions for users: Docker tab > Add Container > select
  template.

**Harder:**

- The template does not appear in the Apps tab search. Users must know
  to look in the Docker tab's Add Container dropdown.
- `<TemplateURL>` auto-update (a CA feature) does not apply when
  installing via the dockerMan path. Users must re-run the `curl`
  command to get template updates.
- Future submission to the official CA index (via Asana form) would
  make the template discoverable in the Apps tab, making the dockerMan
  path a fallback rather than the primary method.
