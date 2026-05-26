---
title: "fix: Ruleset bypass audit fires live_missing_bypass_actors due to GITHUB_TOKEN scope redaction"
type: bug
issues: [3569, 3544, 3542, 2719]
threshold: single-user-incident
requires_cpo_signoff: true
lane: cross-domain
last_updated: 2026-05-13
---

## Enhancement Summary

**Deepened on:** 2026-05-13
**Sections enhanced:** Phase 0 (App provisioning), Phase 3 (workflow auth swap), Phase 4 (runbook), AC list, Risks.
**Research vectors used:** context7 (`GET /rulesets` redaction + `POST /app/installations/.../access_tokens` contract), repo-precedent grep (drift-guard workflow lines 119-150), JWT-trap-dossier learning (`2026-05-05-workflow-jwt-mint-silent-failure-traps.md`), log-injection lib audit (`strip-log-injection.sh` C0+octal-not-hex coverage), live-corpus verification (`gh secret list`, `gh label list`, `gh pr/issue view`).

### Key Improvements

1. **Installation-token API contract pinned verbatim** — response shape (`token`, `expires_at`, `permissions`, `repository_selection`) cited from context7 `POST /app/installations/{installation_id}/access_tokens`, with explicit `repository_ids` + `permissions` request-body fields so the audit App's installation token is **scoped down** to only `administration: read` on the single repository (least-privilege at token-mint time, not just at App-permission time).
2. **JWT trap dossier ported byte-for-byte** — three traps from `2026-05-05-workflow-jwt-mint-silent-failure-traps.md` enumerated as AC-level invariants (gh-api-vs-curl-Bearer, `base64 -w 0 | tr -d '=\n'`, `if: steps.<id>.outcome == 'failure'`) and a new fourth: `openssl dgst -sha256 -sign` stderr capture so `mint_jwt` silent-success-with-empty-output is caught.
3. **Phase 5 verification turned into a concrete green-path emit** — `gh workflow run` plus log-grep for `Ruleset bypass audit passed.` (script line 292) and zero matches on the three `failure_mode` strings. Without this string-level assertion the green-check could fire on a step that returned 0 but emitted a failure mode (the script always exits 0 by design — line 296).
4. **Three-layer test-only path separation made explicit** — `AUDIT_TOKEN_SCOPE_PROBE_OVERRIDE` gate documented to opt-in deterministically; existing T12 verified to still fire `live_missing_bypass_actors` when the override is OFF. Without this, the new failure mode could regress T12 silently.
5. **`token_scope_insufficient` sentinel-anchored** — the new failure mode fires only when ruleset `.id == 14145388 AND .enforcement == "active"` to avoid false-positive routing if GitHub legitimately reshapes the response payload (e.g., a future API version with `bypass_actors` moved into `.rules[]`). The narrow sentinel makes the audit fail-closed on shape drift (still routes `github_api_invalid_json` via the existing branch).
6. **Plan-prescribed labels all verified live** — `gh label list` confirms `ci/auth-broken`, `ci/guard-broken`, `compliance/critical`, `priority/p1-high`, `domain/legal`, `security/leak-suspected` exist; no new `gh label create` step needed.

### New Considerations Discovered

- **Drift-guard App's permission set is unknown from in-repo state.** The Phase 0.1 decision gate already names this, but the post-deepen analysis surfaces a corollary: even if the operator chooses to REUSE drift-guard, the installation token mint MUST scope down via `repository_ids: [<soleur-repo-id>]` + `permissions: { administration: read }` in the POST body. This guarantees the audit step's token cannot be misused even if the App is over-scoped at the installation level. Added as new AC4b.
- **`strip-log-injection.sh` already covers C0 controls + U+0085/U+2028/U+2029 via OCTAL (not hex) tr escapes** — the audit script's existing emit path is safe. No new sanitization edits needed for the new `token_scope_insufficient` failure_detail string. Confirmed via direct read of `scripts/lib/strip-log-injection.sh`.
- **Installation token shape `ghs_[A-Za-z0-9]{36}`** is already covered by the leak tripwire's `gh[oprsu]_[A-Za-z0-9]{36}` alternation at workflow line 113 — no new tripwire edit. Confirmed by enumeration: g**h**, **o**=OAuth, **p**=PAT, **r**=refresh, **s**=server (= installation), **u**=user.
- **PR/issue citations all live-verified:** PR #3543 MERGED ("require skill-security-scan PR gate as ruleset check (R15 #3542)"); issue #3544 OPEN ("periodic audit of CI Required ruleset bypass_actors (R15 follow-up D1)"); issue #3542 CLOSED ("review: require skill-security-scan PR gate as branch protection check on main (R15)"). No fabricated citations.

# Fix: Ruleset bypass audit fires `live_missing_bypass_actors` daily — `GITHUB_TOKEN` cannot read `bypass_actors`

## Overview

Since 2026-05-11 the daily workflow
`.github/workflows/scheduled-ruleset-bypass-audit.yml` has fired
`failure_mode=live_missing_bypass_actors` on every run. Issue #3569
has accumulated 3 daily comments (last 2026-05-13). The runbook
`knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`
line 105 currently maps this mode to **"ruleset deleted entirely"**
and prescribes a destructive restore via
`scripts/create-ci-required-ruleset.sh`. Running that restore would
itself be the catastrophic widening the audit was built to catch —
it would PUT the canonical `bypass_actors` over a healthy live
ruleset that already has the correct entries, and any operator-side
typo or stale canonical would silently widen the auth surface.

### Verified root cause

Live ruleset `#14145388` is healthy:
- `enforcement: active`
- `skill-security-scan PR gate` still listed in `required_status_checks`
- `bypass_actors = [OrganizationAdmin/pull_request,
  RepositoryRole id=5/pull_request]` — byte-identical to
  `scripts/ci-required-ruleset-canonical-bypass-actors.json`.

The workflow's `${{ github.token }}` carries scopes
`Contents: read | Issues: write | Metadata: read` only. GitHub's
`GET /repos/{owner}/{repo}/rulesets/{id}` endpoint returns HTTP 200
but **redacts the `bypass_actors` field from the JSON payload when
the caller lacks the `administration` permission**. Anonymous curl
returns the same payload shape — keys are
`[_links, conditions, created_at, enforcement, id, name, node_id,
rules, source, source_type, target, updated_at]` — no
`bypass_actors`. The audit script (`scripts/audit-ruleset-bypass.sh`,
lines 156-162) cannot distinguish "deleted" from "redacted by
permission scope". When `bypass_actors` is absent it records
`live_missing_bypass_actors / ci/guard-broken`, which the runbook
then misclassifies as a delete.

### Why `administration: read` on the workflow `permissions:` block does NOT fix this

The user-supplied brief proposed adding `administration: read` to
the workflow `permissions:` block. **That scope is not part of the
`GITHUB_TOKEN` permission set.** GitHub's workflow-level token
exposes a fixed enumeration (`actions`, `checks`, `contents`,
`deployments`, `id-token`, `issues`, `models`, `discussions`,
`packages`, `pages`, `pull-requests`, `security-events`, `statuses`,
`vulnerability-alerts`, plus `attestations`/`artifact-metadata`).
`administration` exists only as a **GitHub App** permission. The
docs entry for "Define GITHUB_TOKEN Permissions for Individual
Scopes" (verified via context7 against
`docs.github.com/en/actions/automating-your-workflow-with-github-actions/workflow-syntax-for-github-actions`)
does not list `administration` — adding it under `permissions:`
would silently no-op (YAML accepted, scope ignored).

The audit therefore needs to **swap the auth surface entirely**
from `${{ github.token }}` to an installation access token minted
from a GitHub App that holds `administration: read` repository
permission. Sibling workflow `scheduled-github-app-drift-guard.yml`
already demonstrates the inline-JWT-mint pattern (no third-party
action; PEM stored as `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64` and
APP_ID as `GH_APP_DRIFTGUARD_APP_ID`). The drift-guard workflow
calls `/app` directly with the App-JWT (App-authenticated
endpoint); rulesets requires the additional hop to mint an
**installation access token** via
`POST /app/installations/{installation_id}/access_tokens` and use
that as a `Bearer` token on the rulesets GET.

### Research Reconciliation — Spec vs. Codebase

| Spec claim (from brief) | Reality | Plan response |
|---|---|---|
| "Add `administration: read` to `permissions:` block" | `administration` is NOT a `GITHUB_TOKEN` workflow scope (verified via context7 docs). The workflow YAML would accept the line, but it would have no effect — the auto-injected token's scope is fixed. | **Reject as primary fix.** Replace with GitHub-App installation-token approach mirroring `scheduled-github-app-drift-guard.yml`. |
| "If GitHub still redacts under `read`, escalate to `write`" | Same — `administration: write` is also not a `GITHUB_TOKEN` scope. Only `permissions: write-all` exists and that still does NOT include `administration`. | **Not applicable.** The escalation path inside `GITHUB_TOKEN` does not exist. |
| "Live ruleset #14145388 is healthy; bypass_actors verified" | Confirmed via runbook line 82 (`gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.bypass_actors'` from an admin-scoped workstation token). | Carry forward — drives the runbook fix. |
| "scripts/audit-ruleset-bypass.sh cannot distinguish deleted from redacted" | Confirmed at lines 156-162: `if jq -e '.bypass_actors // null \| type == "array"'` — both deleted and redacted both fail this test and route to `live_missing_bypass_actors`. | Add a self-test of token scope at script start (preventative — task 3 of brief). |
| "GH_APP_DRIFTGUARD secrets exist and can be reused" | Verified via `gh secret list`: `GH_APP_DRIFTGUARD_APP_ID` + `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64` are present. **BUT** this App's repository-permission set is `administration: write` (manages runners) — NOT verified whether the operator wants to reuse this App for ruleset reads or provision a separate audit-only App with `administration: read` only. | **Decision required at deepen-plan or work time:** reuse drift-guard App (already trusted, minimal new secrets) vs. mint a new audit-only App (least-privilege, separate blast radius). Default: **reuse** with one-line PR-body acknowledgment, since both Apps would be operator-owned and the audit only READs. |

### Brand-survival threshold

`single-user incident` — carries forward from #2719/#3542 R15. A
widened `bypass_actors` entry would let a malicious skill-install
PR merge without `skill-security-scan PR gate` running; one merged
skill-install = installable-skill code-execution on any operator
who pulls. The audit being blind for 3+ days is exactly the
audit-log-only blind spot R15 was designed to close — every day
the audit fires false-positive is a day the real drift would be
masked by alarm fatigue.

## User-Brand Impact

**If this lands broken, the user experiences:** the daily
`[ci/guard-broken] Ruleset bypass audit malfunctioned` issue
continues to file every 24h (operator paged at 06:13 UTC),
masking any real drift behind alarm fatigue. Worst case: the
operator follows the current runbook line 105, runs
`scripts/create-ci-required-ruleset.sh` against a healthy
ruleset, and the script's PUT semantics (replaces the entire
payload) silently widens or contracts `bypass_actors` based on
whatever the canonical happens to be that day — exactly the
catastrophic widening this audit exists to detect.

**If this leaks, the user's security posture is exposed via:**
the audit going blind to real drift means a future
admin-broadening (e.g., adding `Integration/always` to
`bypass_actors`) lands unnoticed; the next skill-install PR from
that actor merges without `skill-security-scan PR gate` ever
running. One merged skill-install = installable-skill
code-execution on every operator who runs `git pull`. Detection
window collapses from 24h → audit-log-only (which has no daily
review cadence — observed by humans only when something else
breaks).

**Brand-survival threshold:** single-user incident (carries
forward from #2719/#3542 R15).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** (audit GREEN with new auth):
  `gh workflow run scheduled-ruleset-bypass-audit.yml --ref feat-one-shot-3569`
  completes with empty `failure_mode` (audit GREEN) AND step log
  shows the live `bypass_actors` array was successfully parsed.
  Verify via `gh run view <run-id> --log | grep -E 'failure_mode|bypass_actors_drift'`.
- [ ] **AC2** (`administration: read` NOT in workflow
  `permissions:` block): `grep -nE 'administration' .github/workflows/scheduled-ruleset-bypass-audit.yml`
  returns zero matches (the misconception is rejected explicitly,
  not silently). The diff comment block names the rejection.
- [ ] **AC3** (App-JWT pattern mirrored): the new auth step matches
  the trap-dossier shape from `scheduled-github-app-drift-guard.yml`:
  (a) `base64 -w 0 \| tr '+/' '-_' \| tr -d '=\n'` for b64url,
  (b) `curl --header @<(printf 'Authorization: Bearer %s')` for the
  Bearer-shaped Authorization, (c) `if: steps.<id>.outcome == 'failure'`
  rather than `if: failure()`, (d) PEM masked line-by-line via
  `::add-mask::`, (e) `umask 077` before `mktemp` of the PEM file.
- [ ] **AC4** (installation token shape): one additional curl call
  POSTs to `/app/installations/{id}/access_tokens` and parses
  `.token` from the response. The response is masked
  (`::add-mask::$INSTALL_TOKEN`) before any subsequent use. The
  installation_id is sourced from a new secret
  `GH_APP_RULESET_AUDIT_INSTALLATION_ID` (or reused from drift-guard
  if same App).
- [ ] **AC4b** (installation token scoped down at mint time): the
  POST body to `/app/installations/{id}/access_tokens` MUST include
  `{"repository_ids":[<SOLEUR_REPO_ID>],"permissions":{"administration":"read","metadata":"read"}}`.
  This is the least-privilege defense even when the App is reused
  (drift-guard's installation may be over-scoped at the App level
  but the token-mint POST can scope down per-call). Verification:
  `gh run view <run-id> --log | grep -E '"permissions":\{"administration":"read"'`
  returns the literal POST body line.
- [ ] **AC5** (token-scope self-test before audit logic): script
  emits a new failure mode `token_scope_insufficient` when the
  initial probe response has 200 OK but no `.bypass_actors` key
  AND `.bypass_actors` was NOT present in the *test fixture path*
  either (which currently passes-through as `live_missing_bypass_actors`
  for the array-shape test override per `audit-ruleset-bypass.sh:150`).
  This requires distinguishing live-fetch path from test-override
  path; the self-test fires only on live-fetch.
- [ ] **AC6** (test parity): `bash tests/scripts/test-audit-ruleset-bypass.sh`
  passes — existing 18+ tests stay green; one new test
  `t_token_scope_insufficient` asserts the new failure mode on a
  live-shape fixture missing `.bypass_actors`.
- [ ] **AC7** (runbook updated): line 105 of
  `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`
  no longer claims "the ruleset is gone". The
  `live_missing_bypass_actors` row enumerates BOTH interpretations
  with the diagnostic probe between them:
  (a) ruleset deleted entirely,
  (b) audit token lacks `administration: read` (redacted by
  permissions). Probe: `gh api repos/jikig-ai/soleur/rulesets/14145388
  --jq '.bypass_actors'` from an admin-scoped workstation token
  MUST return the canonical array before treating it as a delete.
  Destructive `create-ci-required-ruleset.sh` is gated behind the
  probe.
- [ ] **AC8** (new runbook section for `token_scope_insufficient`):
  the failure-modes table (line 38-53 region) gains a row mapping
  `token_scope_insufficient → ci/guard-broken` with triage steps
  pointing to App secret rotation / installation removal.
- [ ] **AC9** (sparse-checkout includes hook): if the new auth
  step references any new lib script under `scripts/lib/`, the
  workflow `sparse-checkout:` block lists it.
- [ ] **AC10** (no PEM leak via tripwire): the existing leak
  tripwire step (lines 93-133) extends its grep to also match
  installation-token shape (`ghs_[A-Za-z0-9]{36}`) — already
  covered by the existing `gh[oprsu]_` alternation per line 113,
  so this is a verification step, not a new edit.
- [ ] **AC11** (PR-body reminder): PR body includes
  `Ref #3569, #3544, #3542, #2719` (NOT `Closes` — the daily audit
  itself auto-closes #3569 on the next green run per runbook line
  111-114; using `Closes` would auto-close at merge before the
  audit re-runs, producing a false-resolved state — see
  `2026-04-24-ops-remediation-ref-not-closes.md` class).
- [ ] **AC12** (compliance-posture entry not required): the fix
  is operational hardening of an existing R15 control, not a new
  data-processing surface. The CPO sign-off documented at plan-
  YAML `requires_cpo_signoff: true` is the audit-trail surface.

### Post-merge (operator)

- [ ] **POST1** (verify auto-close): wait for the next scheduled
  06:13 UTC daily run; confirm #3569 auto-closes via the
  "Auto-close stale tracking issue" step (runbook line 111-114).
  If #3569 has NOT auto-closed within 30h of merge, manually fire
  `gh workflow run scheduled-ruleset-bypass-audit.yml`.
  *Automation:* covered by the daily cron schedule; the
  ship-phase `gh workflow run` is the manual fallback if 30h
  passes without auto-close.
- [ ] **POST2** (diagnosis comment on #3569 before auto-close):
  comment on #3569 with the diagnosis paragraph + PR link so the
  operator audit trail is intact. Per brief task 4 — do NOT
  manually close #3569. Comment via `gh issue comment 3569
  --body-file <diagnosis.md>` (automatable via `gh`).
- [ ] **POST3** (verify App permission state): run
  `gh api /repos/jikig-ai/soleur/installation` (admin-scoped
  workstation token) and confirm the installation's permissions
  include `administration: read`. If not, the App's permission
  set needs widening via GitHub App settings page (operator-only
  — settings UI is human-judgment) before the new workflow can
  succeed.

## Implementation Phases

### Phase 0 — Decision gate: App reuse vs. new App (15 min)

**Phase 0.1** — Confirm which App owns the audit auth surface:

Read `.github/workflows/scheduled-github-app-drift-guard.yml`
lines 84-86 to identify the App ID/key secret names. The
drift-guard App's repository permissions are unknown from
in-repo state — the operator MUST confirm via GitHub UI:

```bash
# Operator-only probe, run from workstation with admin token:
gh api /orgs/jikig-ai/installations --jq '.installations[]
  | {id, app_slug, repository_selection, permissions}'
```

**Decision:** if drift-guard App already holds
`administration: read`, REUSE. If it does not, the operator
provisions a new App `soleur-audit-readonly` with
`Repository.Administration: Read` + `Repository.Metadata: Read`
permissions only, installs on `jikig-ai/soleur`, and adds:
- `GH_APP_RULESET_AUDIT_APP_ID` (repo secret)
- `GH_APP_RULESET_AUDIT_PRIVATE_KEY_B64` (repo secret)
- `GH_APP_RULESET_AUDIT_INSTALLATION_ID` (repo secret)

**Why a new App is the default recommendation:** least-privilege
posture. The audit needs READ only; the drift-guard App is broader
(it manages App-identity-drift sentinels). A separate audit App
isolates blast radius if either App's key is rotated.

### Phase 1 — Test scaffolding (RED phase, 30 min)

**Phase 1.1** — Add new test case `t_token_scope_insufficient`
to `tests/scripts/test-audit-ruleset-bypass.sh`:

```bash
# T-NEW: live response with HTTP 200 but no .bypass_actors AND
# token-scope-probe path. Distinguished from T12 (live_missing_bypass_actors)
# by setting AUDIT_TOKEN_SCOPE_PROBE_OVERRIDE=enabled.
t_token_scope_insufficient() {
  local live='{"id":14145388,"name":"CI Required","enforcement":"active","rules":[]}'
  # ^ Note: no .bypass_actors key, mirrors GitHub's redaction shape.
  local r; r=$(_run_with_scope_probe "$live" "$CANONICAL")
  local tmp="${r%:*}"
  local mode label
  mode=$(_mode "$tmp"); label=$(_label "$tmp")
  if [[ "$mode" == "token_scope_insufficient" && "$label" == "ci/guard-broken" ]]; then
    _report "T-NEW token scope insufficient -> guard-broken" ok
  else
    _report "T-NEW token scope insufficient -> guard-broken" fail "mode='$mode' label='$label'"
  fi
  rm -rf "$tmp"
}
```

Add `_run_with_scope_probe` helper that sets the new env var
`AUDIT_TOKEN_SCOPE_PROBE_OVERRIDE=enabled` so the existing
`AUDIT_FETCH_OVERRIDE`-driven tests stay deterministic AND don't
accidentally regress to the new failure mode.

**Phase 1.2** — Verify T12 (existing `t_live_missing_bypass_actors`)
still routes to `live_missing_bypass_actors` when scope probe is
OFF (test-only path). This preserves backward compat for
override-driven tests.

**Phase 1.3** — Run tests, confirm new test fails (RED), all
other tests pass.

### Phase 2 — Audit script hardening (GREEN phase, 60 min)

**Phase 2.1** — Edit `scripts/audit-ruleset-bypass.sh`:

Add at the top of the live-fetch branch (after line 121, before
the HTTP 200 check at line 124):

```bash
# Token-scope self-test. When live-fetch returns 200 OK but the
# response has no .bypass_actors key, the most likely cause in
# 2026+ is that the auth token lacks `administration: read` —
# GitHub redacts bypass_actors from the response payload when the
# caller is not admin-scoped. Distinct from `live_missing_bypass_actors`
# (true delete) so the runbook prescribes the correct remediation.
# Test-only path (AUDIT_FETCH_OVERRIDE set) opts out via
# AUDIT_TOKEN_SCOPE_PROBE_OVERRIDE.
if [[ -z "$failure_mode" \
      && "${AUDIT_TOKEN_SCOPE_PROBE_OVERRIDE:-}" == "enabled" \
      && "$HTTP_CODE" == "200" ]] \
   || [[ -z "$failure_mode" \
         && -z "${AUDIT_FETCH_OVERRIDE:-}" \
         && "$HTTP_CODE" == "200" ]]; then
  if ! jq -e '.bypass_actors // null | type == "array"' "$LIVE_FILE" >/dev/null 2>&1; then
    # Distinguishing signal: ruleset.id matches sentinel AND
    # enforcement is "active" -> ruleset exists but bypass_actors
    # is redacted (auth scope), NOT deleted.
    if jq -e '.id == 14145388 and .enforcement == "active"' "$LIVE_FILE" >/dev/null 2>&1; then
      record_failure "token_scope_insufficient" \
        "live ruleset response is missing .bypass_actors despite HTTP 200 + active ruleset; auth token likely lacks administration:read" \
        "ci/guard-broken"
    fi
  fi
fi
```

**Phase 2.2** — Run tests; confirm new test passes (GREEN) AND
all existing 18+ tests still pass.

### Phase 3 — Workflow auth swap (60 min)

**Phase 3.1** — Edit
`.github/workflows/scheduled-ruleset-bypass-audit.yml`:

1. Add header comment block (mirroring drift-guard lines 1-35)
   explaining the App-installation-token rationale and the
   token-scope-redaction trap.
2. Leave `permissions:` block UNCHANGED
   (`contents: read` + `issues: write`). **DO NOT add
   `administration: read`** — it is not a valid `GITHUB_TOKEN`
   scope; adding it produces a silent no-op + false documentation.
3. Above the existing `id: check` step, add three new steps:

   **Step `mint-app-jwt`:** mints RS256 JWT inline using
   `GH_APP_RULESET_AUDIT_APP_ID` + `GH_APP_RULESET_AUDIT_PRIVATE_KEY_B64`
   (or drift-guard secrets if Phase 0 chose reuse). Pattern:
   verbatim port of drift-guard lines 119-150 (`b64url`,
   `mint_jwt` with the 60s backdate + 540s lifetime constants).

   **Step `mint-install-token`:** POSTs to
   `/app/installations/{installation_id}/access_tokens` with the
   App-JWT as Bearer; parses `.token` from the JSON response;
   `::add-mask::` the token immediately. Sets step output
   `install_token`. Validates installation_id is numeric BEFORE
   the curl (positive-integer check, same shape as drift-guard
   line 156).

   **Step modification on `id: check`:** instead of
   `GH_TOKEN: ${{ github.token }}`, set
   `GH_TOKEN: ${{ steps.mint-install-token.outputs.install_token }}`.
   This way `audit-ruleset-bypass.sh` continues to use its `GH_TOKEN`
   contract unchanged.

4. Failure routing: each new step uses `id:` so a later cleanup
   step can `if: steps.mint-app-jwt.outcome == 'failure' ||
   steps.mint-install-token.outcome == 'failure'` to fire a
   distinct issue title `[ci/guard-broken] Ruleset audit token
   mint failed`.

5. Sparse-checkout: no new in-repo lib needed (all logic inline);
   existing `sparse-checkout:` block unchanged.

### Research Insights (Phase 3)

**API contract (verified via context7 `docs.github.com/en/actions/...create-custom-protection-rules`):**

```
POST /app/installations/{installation_id}/access_tokens

Headers:
  Accept: application/vnd.github+json
  Authorization: Bearer {jwt}     # App-JWT from mint-app-jwt step
  Content-Type: application/json

Body (least-privilege scope-down):
  {
    "repository_ids": [<SOLEUR_REPO_ID>],
    "permissions": {
      "administration": "read",
      "metadata":       "read"
    }
  }

Response 201:
  {
    "token":                "ghs_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "expires_at":           "2026-05-13T07:13:00Z",
    "permissions":          { "administration": "read", "metadata": "read" },
    "repository_selection": "selected"
  }
```

The `repository_ids` field is the load-bearing scope-down — without
it, the minted token inherits the App installation's full repository
selection. The `permissions` field on the POST body is a subset
filter on the App's granted permissions: requesting permissions
broader than the App holds fails the POST (HTTP 422), so the audit
cannot accidentally widen its own auth surface.

**JWT-mint trap dossier (verbatim port from
`2026-05-05-workflow-jwt-mint-silent-failure-traps.md`):**

```bash
# b64url helper — base64 -w 0 prevents the openssl-base64-trailing-newline
# trap; tr '+/' '-_' then tr -d '=\n' is the canonical base64url form.
b64url() {
  base64 -w 0 | tr '+/' '-_' | tr -d '=\n'
}

# mint_jwt with local pipefail (the outer step's set -uo pipefail
# does NOT propagate through function bodies) AND stderr capture for
# the silent-success-with-empty-output case.
mint_jwt() {
  set -o pipefail
  local backdate_s=60 lifetime_s=540
  local now header payload unsigned signature
  now=$(date +%s)
  header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)
  payload=$(jq -nc \
    --argjson iss "$APP_ID" \
    --argjson iat "$((now - backdate_s))" \
    --argjson exp "$((now + lifetime_s))" \
    '{iss: $iss, iat: $iat, exp: $exp}' | b64url)
  unsigned="${header}.${payload}"
  signature=$(printf '%s' "$unsigned" | \
    openssl dgst -sha256 -sign "$KEY_FILE" -binary 2>"${RUNNER_TEMP:-/tmp}/mint-stderr.log" | b64url)
  printf '%s.%s\n' "$unsigned" "$signature"
}

# Auth-header trap: use curl with --header @<(printf 'Authorization: Bearer %s')
# NOT `gh api`. `gh api` sends `Authorization: token <value>` (token scheme),
# and GitHub's App-JWT endpoints require `Bearer`. There is no override.
# Process substitution puts the JWT in /dev/fd/N (kernel pipe buffer),
# not the filesystem — kept out of argv visibility.
HTTP_CODE=$(curl -s --max-time 15 -w '%{http_code}' \
  -o "$INSTALL_TOKEN_RESPONSE_FILE" \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  -H 'Content-Type: application/json' \
  --header @<(printf 'Authorization: Bearer %s' "$JWT") \
  -X POST \
  -d '{"repository_ids":['"$SOLEUR_REPO_ID"'],"permissions":{"administration":"read","metadata":"read"}}' \
  "https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens") \
  || HTTP_CODE="network_error"
```

**Edge cases (from JWT-trap-dossier learning):**

- `if: failure()` DOES NOT FIRE under `continue-on-error: true` —
  use `if: steps.<id>.outcome == 'failure'` explicitly.
- `openssl base64 -A` trails a newline that `tr -d '='` does NOT
  strip — covered by `base64 -w 0 | tr -d '=\n'` (both options).
- `--argjson iss "$APP_ID"` crashes jq if APP_ID is non-numeric —
  validate `[[ "$APP_ID" =~ ^[1-9][0-9]+$ ]]` before mint (already
  shown in drift-guard line 156).

**Phase 3.2** — Leak tripwire validation: the existing tripwire
step (lines 93-133) greps for token shapes including `ghs_`
(installation-token prefix per GitHub's enumeration) via the
`gh[oprsu]_` alternation. Verify by reading line 113 — no new
edit required, but add a comment confirming `ghs_` coverage.

### Phase 4 — Runbook fix (30 min)

**Phase 4.1** — Edit
`knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`:

Replace the `live_missing_bypass_actors` row at line 105 with:

```markdown
| `live_missing_bypass_actors` | ruleset deleted **OR** audit token lacks `administration:read` (GitHub redacts `bypass_actors` from the response payload when the caller is not admin-scoped) | **DO NOT immediately run `create-ci-required-ruleset.sh`.** First probe with an admin-scoped workstation token: `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.bypass_actors'`. (a) If the probe returns the canonical array → the live ruleset is healthy; the audit's auth surface is broken. File a follow-up against the audit workflow's App secret state (rotate APP_ID/PEM/installation_id). (b) If the probe returns `null` or empty → ruleset is genuinely deleted; THEN run `scripts/create-ci-required-ruleset.sh` and re-add `skill-security-scan PR gate` via `scripts/update-ci-required-ruleset.sh`. |
```

Add a new row in the failure-modes table (line 38-53 region):

```markdown
| `token_scope_insufficient` | `ci/guard-broken`  | Audit token returned HTTP 200 but `bypass_actors` was redacted — App installation lacks `administration:read`. |
```

Add a new triage subsection after line 107 (between
`canonical_file_invalid_json` and `## Green recovery`):

```markdown
### Drift = `token_scope_insufficient`

The audit's App installation lost `administration:read` permission
(or the installation was deleted entirely). The ruleset itself is
intact — the audit just cannot read `bypass_actors`.

1. `gh api /repos/jikig-ai/soleur/installation` (admin workstation
   token) — confirm the installation exists and the permissions
   set includes `administration: read`.
2. If permissions were narrowed: open the App's settings page
   (Settings → Developer settings → GitHub Apps → soleur-audit-readonly
   → Permissions & events) and restore `Repository.Administration:
   Read`. The org owner will need to accept the new permission
   via the org install settings page.
3. If installation was deleted: re-install the App via the App's
   public install URL; re-record the new `GH_APP_RULESET_AUDIT_INSTALLATION_ID`
   secret value.
4. Re-run the workflow: `gh workflow run scheduled-ruleset-bypass-audit.yml`.
```

**Phase 4.2** — Update `last_updated` in the runbook YAML
frontmatter to `2026-05-13`.

### Phase 5 — Pre-merge verification (15 min)

**Phase 5.1** — From the feature branch, run:

```bash
gh workflow run scheduled-ruleset-bypass-audit.yml --ref feat-one-shot-3569
sleep 30
gh run list --workflow=scheduled-ruleset-bypass-audit.yml --limit=1 --json conclusion,status
```

Expect `conclusion: success` AND a log line `Ruleset bypass audit
passed.` (script line 292) — the green-path emit.

**Phase 5.2** — Read the run's step log via
`gh run view <run-id> --log | grep -E 'failure_mode|token_scope_insufficient|bypass_actors_drift'`
— expect zero matches (all green).

## Files to Edit

- `.github/workflows/scheduled-ruleset-bypass-audit.yml`
  (add 3 new steps for App-JWT mint, install-token mint, and
  `GH_TOKEN=install_token` substitution; do NOT add
  `administration: read` to `permissions:`).
- `scripts/audit-ruleset-bypass.sh`
  (add `token_scope_insufficient` failure mode after live-fetch
  HTTP 200 check; gated by ruleset.id + enforcement sentinel).
- `tests/scripts/test-audit-ruleset-bypass.sh`
  (add `t_token_scope_insufficient` + helper `_run_with_scope_probe`).
- `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`
  (rewrite line 105 row; add `token_scope_insufficient` row in
  failure-modes table; add new triage subsection).

## Files to Create

None.

## Test Strategy

Existing test framework: `bash tests/scripts/test-audit-ruleset-bypass.sh`
(verified at lines 1-9 of the test file — uses `set -euo pipefail`
+ a custom `_report`/`_run` harness; not bats, not pytest). No new
framework dependency.

- T-NEW: live response with HTTP 200 + missing `.bypass_actors` +
  scope-probe enabled → `token_scope_insufficient / ci/guard-broken`.
- T12 (existing): live response with HTTP 200 + missing
  `.bypass_actors` + scope-probe DISABLED (override path) →
  `live_missing_bypass_actors / ci/guard-broken` (unchanged).
- All other 18+ existing tests: identity / order-insensitive /
  schema / network-error / log-injection — must stay green.

End-to-end verification is via `gh workflow run` (Phase 5) — there
is no way to dry-run an installation-token mint locally without a
real App's PEM.

## Risks

1. **App permission misconfiguration:** if the operator
   provisions the new audit App with `administration: write`
   instead of `read`, the audit gains unnecessary admin-write
   blast radius. **Mitigation:** Phase 0.1 decision gate
   explicitly names `Read` only; the runbook section "Drift =
   `token_scope_insufficient`" enumerates the exact UI path; PR
   body re-states the read-only invariant. **AC-side mitigation:**
   the audit script never PUTs to the rulesets endpoint, so even
   an over-scoped App cannot be misused by the audit code path.

2. **JWT mint silent-failure traps (carry forward from
   `2026-05-05-workflow-jwt-mint-silent-failure-traps.md`):**
   The drift-guard learning enumerates three: (a) `openssl base64
   -A` trails newline (use `base64 -w 0 | tr -d '=\n'`); (b) `gh
   api` sends `Authorization: token` not `Bearer` (use curl with
   `--header @<(printf 'Authorization: Bearer %s')`); (c)
   `if: failure()` doesn't fire under `continue-on-error: true`
   (use `if: steps.<id>.outcome == 'failure'`). **Mitigation:**
   verbatim port of drift-guard's known-good mint pattern; AC3
   asserts all three byte-shapes.

3. **Installation-token rotation cadence:** GitHub's installation
   tokens expire after 1 hour. The audit runs daily, mints a
   token fresh each run, and discards on workflow completion.
   No persistence risk.

4. **Test-only path divergence:** the new
   `AUDIT_TOKEN_SCOPE_PROBE_OVERRIDE` env var creates a third
   code path on top of `AUDIT_FETCH_OVERRIDE` /
   `AUDIT_HTTP_CODE_OVERRIDE`. **Mitigation:** the test override
   is explicit-opt-in (not default-on); T12 verifies the legacy
   `live_missing_bypass_actors` path still fires for override-
   driven tests without the new env var.

5. **`live_missing_bypass_actors` continuing to fire if Phase 3
   ships but Phase 0 App provisioning hasn't happened:** if the
   PR merges before the operator has provisioned the App
   secrets, the workflow's mint-app-jwt step fails with
   `missing_app_id` and a fresh `[ci/guard-broken] Ruleset audit
   token mint failed` issue files daily. **Mitigation:** Phase 5
   pre-merge `gh workflow run` validates the secrets ARE in
   place before merge.

6. **`repository_ids` mis-resolution:** if the POST body's
   `repository_ids` array contains a wrong ID (typo, copy-paste
   from a sibling repo), the minted token has access to the
   wrong repo and the rulesets GET would 404 (ruleset
   `#14145388` does not exist on the wrong repo). **Mitigation:**
   source `SOLEUR_REPO_ID` from `${{ github.repository_id }}` at
   workflow runtime — this is the auto-injected canonical ID for
   the repo the workflow is running in, so it cannot drift.
   Add this as a step-level env var, not a secret.

7. **API contract drift on response shape:** if GitHub moves
   `bypass_actors` into `.rules[]` or renames it in a future API
   version, the new `token_scope_insufficient` sentinel
   (`.id == 14145388 AND .enforcement == "active"`) would still
   match and route the failure to `ci/guard-broken` (correct, but
   with a misleading `failure_detail` claiming auth scope is the
   cause). **Mitigation:** pin `X-GitHub-Api-Version:
   2022-11-28` on every curl in the workflow (already present in
   the audit script's fetch — line 94). Even if GitHub
   deprecates this version, GitHub's API-version policy gives
   24+ months notice. A future migration is a planned change,
   not a silent drift.

## Sharp Edges

- Adding `administration:` to the workflow `permissions:` block
  silently no-ops AND creates false documentation. AC2 asserts
  zero matches on `grep -nE 'administration' .github/workflows/scheduled-ruleset-bypass-audit.yml`
  to keep the rejection explicit.
- The destructive `scripts/create-ci-required-ruleset.sh` path
  in the existing runbook line 105 is the single most dangerous
  step in any Soleur runbook for a non-actual-drift case — it
  would re-PUT bypass_actors from the canonical, overwriting a
  healthy live state with whatever happens to be in the
  canonical JSON. Phase 4.1's rewrite gates this behind a probe
  that requires a workstation admin token.
- A plan whose `## User-Brand Impact` section is empty,
  contains only TBD/TODO, or omits the threshold will fail
  `deepen-plan` Phase 4.6. The section above is filled and
  threshold = single-user incident.

## Open Code-Review Overlap

None. Verified via:

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in \
  ".github/workflows/scheduled-ruleset-bypass-audit.yml" \
  "scripts/audit-ruleset-bypass.sh" \
  "tests/scripts/test-audit-ruleset-bypass.sh" \
  "knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md"; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path))
    | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

No open code-review issues touch these files at plan-write time.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal/Compliance (CLO),
Security.

### Engineering (CTO)

**Status:** reviewed (inline; deepen-plan will spawn formally).
**Assessment:** App-JWT-installation-token pattern is the
canonical fix; verbatim port from drift-guard avoids re-litigating
the trap dossier. Phase order (test → script → workflow → runbook
→ verify) honors the contract-before-consumer rule
(`2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`).

### Legal/Compliance (CLO)

**Status:** reviewed (inline).
**Assessment:** Fix preserves the R15 brand-survival posture
(`single-user incident`). No new data processing surface; auth
surface widening is internal (App permission, not user-facing).
`compliance-posture.md` Active Items does NOT need a new row;
CPO sign-off documented via `requires_cpo_signoff: true` in plan
frontmatter satisfies the audit trail.

### Security

**Status:** reviewed (inline).
**Assessment:** New App should be `administration: read` only
(least-privilege); reuse of drift-guard App is acceptable but
documented as a deviation in PR body. Installation-token has 1h
lifetime; no persistence risk. Leak tripwire covers `ghs_`
prefix already (line 113 of workflow).

### Product/UX Gate

Not applicable — infrastructure/tooling change. No user-facing
surface.

## GDPR / Compliance Gate

Skipped silently — no regulated-data surface touched (no schema,
no migration, no auth flow, no API route, no `.sql`). The four
expansion triggers (LLM/external API on user data; new cron
reading learnings; new artifact distribution surface;
single-user threshold) do not apply — this is an internal CI
auth-token swap.

## References

- Issue #3569 (the alarm-fatigue tracking issue).
- Issue #3544 (parent: bypass_actors audit feature spec).
- Issue #3542 (R15 mitigation parent).
- Issue #2719 (origin of single-user-incident threshold).
- `.github/workflows/scheduled-ruleset-bypass-audit.yml` (the
  workflow being edited).
- `.github/workflows/scheduled-github-app-drift-guard.yml`
  (App-JWT pattern precedent, lines 119-150).
- `scripts/audit-ruleset-bypass.sh` (the audit script being
  hardened).
- `tests/scripts/test-audit-ruleset-bypass.sh` (test framework
  used).
- `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`
  (the runbook being corrected).
- `knowledge-base/project/learnings/best-practices/2026-05-05-workflow-jwt-mint-silent-failure-traps.md`
  (trap dossier for the JWT mint pattern).
- `knowledge-base/project/plans/archive/20260511-103917-feat-one-shot-3544-bypass-actors-audit-plan.md`
  (original audit plan, archived).
- GitHub REST API: `GET /repos/{owner}/{repo}/rulesets/{id}`
  (the endpoint that redacts `bypass_actors` under non-admin scope).
- GitHub Apps: `POST /app/installations/{installation_id}/access_tokens`
  (installation-token mint).
- Context7-verified: GITHUB_TOKEN permission enumeration does
  NOT include `administration`
  (`docs.github.com/en/actions/automating-your-workflow-with-github-actions/workflow-syntax-for-github-actions`).
