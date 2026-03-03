# ADR-0011: CA Private Repository Install Method

## Status

Accepted (amends [ADR-0007](0007-unraid-community-applications-template.md) and [ADR-0009](0009-unraid-template-at-repo-root.md))

## Context

The README instructed Unraid users to go to the **Apps** tab and click a
"Settings icon (gear)" to add the GitHub repository URL as a template
source. This instruction was wrong — no such gear icon or settings page
exists in the Community Applications plugin.

Investigation of the current CA documentation revealed:

1. CA's template scraper only discovers templates from repositories that
   have been **submitted to and approved by the CA moderation team**.
   Self-hosted template repositories are not automatically indexed just
   because the XML is at the repo root.

2. The old "Template Repositories" UI field (referenced in some legacy
   Unraid forum posts) was located on the **Docker** tab, not the Apps
   tab. Its current availability across Unraid versions is uncertain.

3. The CA FAQ (by Squid, CA's author) describes two methods for
   templates not in the official CA index:
   - **"Old School"**: Paste the GitHub URL in the Docker tab's
     Template Repositories field, then use Add Container.
   - **"Preferred"**: Copy the XML file to
     `/boot/config/plugins/community.applications/private/<name>/`
     on the flash drive. The template appears in the Apps tab under a
     "Private" category.

### Options considered

**1. Submit to the official CA index via Asana form**

As of June 2025, new template repositories are submitted via an Asana
form. Approval takes up to 48 hours. Once approved, the template
appears in CA's main search — the simplest UX for end users. However,
this requires CA moderation review, a dedicated Unraid forum support
thread, and ongoing maintenance commitments. Not suitable for testing
before submission.

**2. Document the Docker tab Template Repositories field**

The "Old School" method from the CA FAQ. Users paste the GitHub URL
on the Docker tab. However, this feature's availability and location
varies across Unraid versions. The user who reported the issue could
not find it, and the official Unraid docs (docs.unraid.net) do not
mention it at all.

**3. CA Private Repository on the flash drive**

Users download the XML to a specific path on the Unraid flash drive.
CA discovers it on the next refresh and shows it under a "Private"
category in the Apps tab. This is the method the CA FAQ labels
"Preferred" and works on all Unraid versions with CA installed.

**4. Direct Docker CLI run (skip CA entirely)**

Document a `docker run` command instead of using the CA template at
all. Bypasses all CA machinery but loses the guided form UI that
Unraid users expect.

## Decision

Use the **CA Private Repository method** (option 3) as the documented
install path, with `curl` for downloading the XML file.

Implementation details:

- **`curl -fsSL`** instead of `wget`: `curl` is available on all
  supported Unraid versions (6.9+); `wget` is not reliably available
  on older versions. The `-f` flag ensures HTTP errors (404, 500)
  produce a non-zero exit code instead of silently writing an HTML
  error body into the XML file.

- **Commands split for copy-paste safety**: The `mkdir` and `curl`
  commands are presented as separate code blocks so users pasting
  into Unraid's web terminal don't encounter line-continuation issues.

- **CA in-app refresh required**: After downloading the XML, users
  must click the refresh icon inside the Apps tab — a browser refresh
  (Ctrl+R) alone does not trigger CA to rescan its index.

- **CA prerequisite noted**: A prerequisite callout explicitly states
  that the Community Applications plugin must already be installed.

- **Future path**: When ready, submit the template to the official CA
  index via the Asana form. At that point, the Private Repository
  instructions become a fallback and the primary path becomes "search
  for obsidian-git-backup in the Apps tab."

## Consequences

**Easier:**

- Instructions now actually work. The previous instructions referenced
  UI elements that don't exist.
- The Private Repository method works on all Unraid versions with CA
  installed, without version-dependent UI variations.
- `curl -fsSL` fails loudly on HTTP errors, preventing silent
  corruption of the XML file.
- Template auto-updates work via the `<TemplateURL>` field in the XML
  — once installed, CA checks for template changes on refresh.

**Harder:**

- Users must open a terminal and run shell commands, which is more
  intimidating than a GUI-only workflow. The commands are documented
  step-by-step with expected output guidance to mitigate this.
- The template appears under "Private" rather than in the main search
  results, which may confuse users who expect it alongside other apps.
- Users must manually re-run the `curl` command to get template
  updates (though `<TemplateURL>` handles this for already-installed
  containers).
- Submitting to the official CA index would eliminate all of these
  friction points but requires a dedicated Unraid forum support thread
  and ongoing moderation relationship.
