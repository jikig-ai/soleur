---
title: CI Required Ruleset `bypass_actors` Drift
audience: operator
on_page_for: scheduled-ruleset-bypass-audit
issues: [3544, 3542, 2719, 3569]
brand_survival_threshold: single-user incident
last_updated: 2026-05-13
---

# CI Required Ruleset `bypass_actors` Drift

This runbook covers triage and remediation when
[`Scheduled: Ruleset Bypass Audit`](../../../../.github/workflows/scheduled-ruleset-bypass-audit.yml)
fires.

## Why this audit exists

The R15 mitigation (#3542, PR #3543) made `skill-security-scan PR gate`
a required check on `main` via the "CI Required" repository ruleset
(#14145388). The ruleset's `bypass_actors` array names who may merge
around that gate. A widened entry (mode broadened from `pull_request`
to `always`, or a new actor added) lets a malicious skill-install PR
land without the gate ever running — one merged skill-install =
installable-skill code-execution on any operator who pulls.

`scripts/update-ci-required-ruleset.sh` PUTs `bypass_actors` verbatim
from the live snapshot (GitHub's PUT API replaces the entire payload;
omitting a field silently strips it). An admin who edits `bypass_actors`
directly via the GitHub UI between two PUTs leaves no repo-side trace —
GitHub's organization audit log is the only surface. This daily audit
closes that gap with a 24-hour worst-case detection window.

Brand-survival threshold: **single-user incident** (inherited from
#2719). One unauthorized merge under a widened bypass is the
brand-ending incident. Threshold change requires CPO + user-impact-
reviewer sign-off.

## Failure modes

The audit emits one of three outcomes via `$GITHUB_OUTPUT`:

| `failure_mode`             | `failure_label`    | What it means                                              |
|----------------------------|--------------------|------------------------------------------------------------|
| `""` (empty)               | `""`               | Green. Live `bypass_actors` matches canonical.             |
| `bypass_actors_drift`      | `ci/auth-broken`   | Drift detected. **The load-bearing detection.**            |
| `ruleset_enforcement_disabled` | `ci/auth-broken` | Ruleset id matches canonical but `enforcement` is no longer `active`; bypass_actors guarantee is suspended (#3569). |
| `github_api_network`       | `ci/guard-broken`  | curl failed to reach api.github.com (>15s or unreachable). |
| `github_api_http`          | `ci/guard-broken`  | GitHub returned non-200 for the ruleset GET.               |
| `github_api_invalid_json`  | `ci/guard-broken`  | Response body did not parse as JSON.                       |
| `live_missing_bypass_actors` | `ci/guard-broken` | Response had no `.bypass_actors` array AND id+enforcement sentinel did NOT match → ruleset is likely actually deleted. |
| `token_scope_insufficient` | `ci/guard-broken`  | Response 200 OK + missing `.bypass_actors` BUT id+enforcement sentinel matched canonical → audit token lacks `administration:read`. Ruleset itself is intact (#3569). |
| `canonical_file_missing`   | `ci/guard-broken`  | Canonical JSON file is gone from the checkout.             |
| `canonical_file_invalid_json` | `ci/guard-broken` | Canonical JSON file did not parse.                       |
| `missing_gh_token`         | `ci/guard-broken`  | Workflow ran without `GH_TOKEN` env var.                   |

`ci/auth-broken` failures also get `compliance/critical` +
`domain/legal` labels (CLO routing). `ci/guard-broken` failures stop
at `priority/p1-high`.

## Triage by drift kind

### Drift = legitimate authorized change (e.g., onboarding a 2nd admin)

1. Verify with the editing actor via GitHub organization audit log
   (Settings → Audit log → filter by `repository_ruleset`).
2. Open a PR that:
   - Edits `scripts/ci-required-ruleset-canonical-bypass-actors.json` to
     match the new live state.
   - Adds `requires_cpo_signoff: true` to the PR body (inherits #2719's
     posture).
   - Appends a row to `knowledge-base/legal/compliance-posture.md`
     `#2719` section documenting the new actor.
3. Merge; the daily audit auto-closes the drift issue on the next green
   run.

### Drift = unauthorized broadening

1. **Rotate immediately:** if a non-trusted org admin has gained
   write access, rotate the org owner credentials (GitHub Settings →
   Organization → Owners).
2. **Restore canonical:** the canonical JSON file is the source of
   truth. Use the audit's "fast path":
   ```bash
   gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.bypass_actors' > /tmp/live-now.json
   diff <(jq -S . /tmp/live-now.json) <(jq -S . scripts/ci-required-ruleset-canonical-bypass-actors.json)
   ```
   If the live diff confirms drift, file a destructive-write
   confirmation gate per `hr-menu-option-ack-not-prod-write-auth` and
   re-PUT the canonical via a short ad-hoc script (the
   `update-ci-required-ruleset.sh` post-PUT verification will now diff
   against the canonical and exit 2 on mismatch — see #3544).
3. **Post-mortem:** file under
   `knowledge-base/project/learnings/security-issues/` with timeline,
   blast radius, remediation, and prevention.
4. **Update compliance-posture.md:** add an entry under Active Items
   noting the incident and its resolution.

### Drift = guard malfunction (`ci/guard-broken`)

The audit itself failed — not the bypass_actors state. Common causes:

| `failure_mode`             | Likely cause                                | Fix                                                                                                |
|----------------------------|---------------------------------------------|----------------------------------------------------------------------------------------------------|
| `github_api_network`       | api.github.com transient outage             | Wait one cycle and re-run via `gh workflow run scheduled-ruleset-bypass-audit.yml`.                |
| `github_api_http`          | 403 rate limit, 502/503 upstream, 401 token | Check token scope; if 401, `GH_TOKEN` (`${{ github.token }}`) lost `contents:read`/`issues:write`. |
| `github_api_invalid_json`  | upstream regression in GitHub API           | Open a GitHub Support ticket if persistent.                                                        |
| `live_missing_bypass_actors` | ruleset deleted entirely (id+enforcement sentinel did NOT match) | **PROBE FIRST.** Run from an admin-scoped workstation: `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.bypass_actors'`. (a) Returns the canonical array → the live ruleset is healthy; the audit emitted a false positive — investigate the audit script's HTTP-200 path (likely a contract drift in GitHub's response shape). (b) Returns `null`/empty or the API 404s → ruleset is genuinely deleted; then restore via `scripts/create-ci-required-ruleset.sh` and re-add `skill-security-scan PR gate` via `scripts/update-ci-required-ruleset.sh`. **NEVER run the restore without the probe** — the script PUTs from the canonical, which would overwrite a healthy live state. (#3569) |
| `token_scope_insufficient` | audit token lost `administration:read` (GitHub redacts `bypass_actors` from the response payload when caller is not admin-scoped) | See "Drift = `token_scope_insufficient`" subsection below. The ruleset itself is intact — the audit's App-installation-token mint is the broken surface. |
| `canonical_file_missing`   | sparse-checkout misconfigured               | Verify the workflow's `sparse-checkout:` block includes the JSON path.                             |
| `canonical_file_invalid_json` | bad merge to the canonical                | Run `jq -e . scripts/ci-required-ruleset-canonical-bypass-actors.json` locally; fix syntax.        |

### Drift = `ruleset_enforcement_disabled` (#3569)

The ruleset still exists at id `14145388` but `enforcement` is set to
something other than `"active"` (e.g., `"disabled"`, `"evaluate"`).
The `skill-security-scan PR gate` requirement is suspended for as
long as enforcement stays non-active — every PR can merge without
the gate running. Routes as `ci/auth-broken` because the auth
surface IS effectively widened, even though the bypass_actors array
is unchanged.

1. Confirm the live state from an admin workstation:
   ```bash
   gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.enforcement'
   ```
2. If enforcement is `disabled` or `evaluate`, re-enable via Settings
   → Rules → Rulesets → CI Required → Enforcement status → Active.
   The org owner (or anyone with admin write on the ruleset) can do
   this from the GitHub UI; there is no `gh` subcommand for
   ruleset enforcement state today.
3. Investigate via the GitHub organization audit log
   (Settings → Audit log → filter `repository_ruleset`) to
   identify who and when. If the change was unauthorized, treat as
   the "Drift = unauthorized broadening" path above (rotate org
   owner credentials, post-mortem).
4. Re-run `gh workflow run scheduled-ruleset-bypass-audit.yml` from
   an admin workstation to confirm green.

### Drift = `token_scope_insufficient` (#3569)

The audit's App-installation token lost `administration:read` permission
(or the installation was deleted entirely). The ruleset itself is
intact — the audit just cannot read `bypass_actors`. The script
distinguishes this from "ruleset deleted" by checking
`.id == 14145388 AND .enforcement == "active"` on the HTTP-200 response.

The audit workflow mints the install token from the `soleur-ai`
GitHub App (drift-guard's App, reused per #3569 Phase 0.1 decision)
via the App-JWT → installation-token pattern. Failure modes:

1. **Probe live state first** — confirm the ruleset is actually healthy
   before touching App config:
   ```bash
   # Admin workstation token (gh CLI, not GHA token):
   gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.bypass_actors'
   ```
   Expect the canonical 2-entry array (OrganizationAdmin + RepositoryRole
   id=5). If this returns `null` or 404s, the failure is misclassified —
   the ruleset is genuinely deleted and you want the
   `live_missing_bypass_actors` triage path instead.

2. **Confirm the App installation has admin scope** — admin workstation:
   ```bash
   gh api /orgs/jikig-ai/installations --jq \
     '.installations[] | select(.app_slug=="soleur-ai") | {id, repository_selection, permissions}'
   ```
   The `permissions` map MUST include `administration` (any value: read
   or write). If absent, the org owner narrowed the App's permission set;
   widen via Settings → Developer settings → GitHub Apps → `soleur-ai` →
   Permissions & events → Repository permissions → Administration: Read.
   The org owner must accept the new permission via the install settings
   page.

3. **Confirm the mint step is finding the App** — check the run log for
   the `mint-jwt` step. Failure modes (each routes its own warning):
   - `missing_app_id` / `app_id_not_numeric` → `GH_APP_DRIFTGUARD_APP_ID`
     secret missing or corrupted. Re-set from the App's settings page.
   - `missing_private_key` / `pem_b64_decode_failed` / `pem_shape_invalid`
     → `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64` secret missing or corrupted.
     Re-generate the App's PEM, base64-encode (`base64 -w 0 < pem`), and
     re-set the secret.
   - `jwt_mint_failed` → check `mint-stderr.log` line printed in the
     run; typically a transient `openssl` failure (rare).

4. **Re-run after fix:** `gh workflow run scheduled-ruleset-bypass-audit.yml`
   from an admin workstation. The next run should emit
   `Ruleset bypass audit passed.` and auto-close any stale issue.

**Do NOT run `scripts/create-ci-required-ruleset.sh`** under
`token_scope_insufficient` — the ruleset is healthy and the script
would re-PUT the canonical, overwriting the live state.

## Green recovery

The audit auto-closes the tracking issue on the next green run
(Step "Auto-close stale tracking issue"). **Do NOT manually close
a drift-fired issue without verifying the next audit pass.** The
auto-close comment links to the green run as the durable receipt.

Manual run for verification:
```bash
gh workflow run scheduled-ruleset-bypass-audit.yml
gh run list --workflow=scheduled-ruleset-bypass-audit.yml --limit=1 --json conclusion,status
```

## Smoke test (post-deploy)

After any change to `scripts/audit-ruleset-bypass.sh` or
`scripts/ci-required-ruleset-canonical-bypass-actors.json`:

1. Open a short-lived branch.
2. Temporarily edit the canonical to a known-different state (e.g.,
   remove the `RepositoryRole` entry).
3. Push, open a tiny PR.
4. `gh workflow run scheduled-ruleset-bypass-audit.yml --ref <branch>`.
5. Expect: tracking issue filed with `bypass_actors_drift` failure mode.
6. Close the smoke PR without merging; revert the canonical; manually
   close the test issue (no auto-close happens until the next *main*
   run, which will read the restored canonical and close it).

## References

- `.github/workflows/scheduled-ruleset-bypass-audit.yml` — the workflow.
- `scripts/audit-ruleset-bypass.sh` — extracted audit logic.
- `scripts/ci-required-ruleset-canonical-bypass-actors.json` — canonical.
- `scripts/update-ci-required-ruleset.sh` — R15 mutation script; now
  diffs post-PUT against the canonical (audit fast-path).
- `scripts/create-ci-required-ruleset.sh` — bootstrap script; sources
  bypass_actors from the canonical via `jq --slurpfile`.
- `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md`
  — parent R15 runbook.
- `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md` — sibling lint
  runbook (#3546) covering pre-merge enforcement of bot-PR synthetic check-run
  completeness.
- `knowledge-base/legal/compliance-posture.md` `#2719` row.
- GitHub Ruleset PUT API:
  https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset
