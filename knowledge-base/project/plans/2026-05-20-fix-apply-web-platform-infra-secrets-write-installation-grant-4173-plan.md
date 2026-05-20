---
title: "fix(infra): grant secrets:write on soleur-ai App installation + sync manifest (#4173)"
type: fix
date: 2026-05-20
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
closes: 4173
---

# fix(infra): grant secrets:write on soleur-ai App installation + sync manifest (#4173)

## Problem

`apply-web-platform-infra.yml` post-merge run [26166234267](https://github.com/jikig-ai/soleur/actions/runs/26166234267) advanced past the variable-resolution gate (#4150/#4161) and the `file()` SSH-key gate (#4166), but failed at the **Terraform apply** step with:

```
Error: GET https://api.github.com/repos/jikig-ai/soleur/actions/secrets/public-key:
       403 Resource not accessible by integration []

  with github_actions_secret.doppler_token_kb_drift,
  on kb-drift.tf line 82, in resource "github_actions_secret" "doppler_token_kb_drift":
  82: resource "github_actions_secret" "doppler_token_kb_drift" {
```

The `integrations/github` provider (configured with App-installation auth in `apps/web-platform/infra/main.tf:66-73`) requests the repo's Actions-secrets public key to encrypt the `DOPPLER_TOKEN_KB_DRIFT` value before publishing. That endpoint requires the `secrets:write` permission on the **installation access token**.

**Failed run:** <https://github.com/jikig-ai/soleur/actions/runs/26166234267>

## User-Brand Impact

- **If this lands broken, the user experiences:** No end-user-visible regression. The apply errored before any resource mutation; state is unchanged. Forward impact: every push to `main` touching `apps/web-platform/infra/**` continues to fail at the apply step, blocking #4136 (workflow_dispatch end-to-end verification) and #4137 (next-PR canary AC11–AC12). Operator-attention debt accrues.
- **If this leaks, the user's data is exposed via:** N/A — this PR widens an existing App installation's permission set by exactly one key (`secrets:write`) and brings a committed manifest JSON into sync with the live App declaration. The Doppler service-token value published by `github_actions_secret.doppler_token_kb_drift` is already minted by the existing `doppler_service_token.kb_drift` resource (kb-drift.tf:71-76, `access = "read"` on the `prd_kb_drift_walker` config — read-only on a single-config scope). Net secret surface unchanged.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: this PR only grants secrets:write to an existing installation on the founder's own org (single-tenant, no cross-tenant blast radius); the committed manifest JSON edit is text-only; the Doppler service token published into the GH Actions secret is the same token already minted by the existing resource — only the publish path becomes operational.`

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions workflow `apply-web-platform-infra.yml` exit-code (post-merge run on main)"
  cadence: "per-merge to main when paths under apps/web-platform/infra/** change; manual workflow_dispatch on demand"
  alert_target: "GitHub Actions UI + (failure) `cloudflare_notification_policy.service_token_expiry` and `alerts-github-webhook.tf` failure routes"
  configured_in: ".github/workflows/apply-web-platform-infra.yml:177-304 (plan step) + 306-313 (apply step)"

error_reporting:
  destination: "GitHub Actions `::error::` step annotations; `scheduled-github-app-drift-guard.yml` hourly cron detects manifest-vs-live divergence and files ci/auth-broken (permission_drift) or ci/guard-broken (permission_unexpected_grant) issues"
  fail_loud: "step `Terraform apply` exits non-zero on 403; drift-guard files an issue within 1h if manifest drifts from live"

failure_modes:
  - mode: "Installation 122213433 still lacks secrets:write after Phase 1 (operator did not click Accept on the new permission)"
    detection: "Re-run of apply-web-platform-infra emits `403 Resource not accessible by integration` on `actions/secrets/public-key`"
    alert_route: "GitHub Actions UI step error; manual operator triage via runbook"
  - mode: "App declares secrets:write but manifest JSON lags (drift-guard fires permission_unexpected_grant)"
    detection: "scheduled-github-app-drift-guard hourly run emits `permission_unexpected_grant:secrets=write`"
    alert_route: "Auto-filed GitHub issue with label ci/guard-broken (per drift-guard workflow + runbook github-app-drift.md)"
  - mode: "Manifest JSON updated but App's actual declared permissions still lag (drift-guard fires permission_drift)"
    detection: "scheduled-github-app-drift-guard emits `permission_drift:secrets=write`"
    alert_route: "Auto-filed GitHub issue with label ci/auth-broken"

logs:
  where: "GitHub Actions run logs for apply-web-platform-infra.yml (90d retention); scheduled-github-app-drift-guard.yml (90d retention)"
  retention: "90 days"

discoverability_test:
  command: "gh api /orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug==\"soleur-ai\") | .permissions.secrets // \"MISSING\"'"
  expected_output: "\"write\""
```

## Research Reconciliation — Spec vs. Codebase

| Issue claim (#4173) | Reality (verified at plan-write time) | Plan response |
|---|---|---|
| Token is one of: default `GITHUB_TOKEN`, `GH_RULESET_PAT`, or a GitHub App token with insufficient scope | `apps/web-platform/infra/main.tf:66-73` configures `provider "github"` with `app_auth { id = var.github_app_id, installation_id = "122213433", pem_file = var.github_app_private_key }`. Provider exchanges App credentials → short-lived installation token at every plan/apply (per #4150 / #4161 migration). The token is the App installation token, not the workflow `GITHUB_TOKEN` or `GH_RULESET_PAT`. | Confirmed: this is an App-installation permission gap, not a workflow-token-export gap. The workflow's `GITHUB_TOKEN` is irrelevant to the failing API call. |
| Issue offers two fixes: (1) swap the workflow's exported token, (2) move the secret resource to a different workflow with admin auth | `gh api apps/soleur-ai --jq '.permissions'` returns 8 keys including `secrets: write`. **BUT** `gh api /orgs/jikig-ai/installations --jq '.installations[] \| select(.app_slug=="soleur-ai") \| .permissions'` returns only 7 keys — `secrets` is **absent**. The App declared the permission (likely via Playwright in #4150 session) but installation 122213433 never accepted the new permission. | Reject both fixes from the issue body. Fix is at the App-installation grant layer: operator clicks "Accept new permissions" on installation 122213433. Workflow token swap is unnecessary (and would regress the #4150/#4161 PAT→App-auth narrowing). |
| `apply-sentry-infra.yml` is the working precedent for token export | `apply-sentry-infra.yml` does NOT manage any `github_actions_secret` resource; it manages `sentry_cron_monitor.*` via the `jianyuan/sentry` provider with `SENTRY_IAC_AUTH_TOKEN`. There is no precedent in this repo for `github_actions_secret` against the soleur repo other than the failing path itself. | The closest analog is `apply-github-infra.yml` which uses `GH_RULESET_PAT` (a fine-grained PAT with `Administration:Write`) for `github_repository_ruleset`. That PAT does NOT have `secrets:write`, and reverting to PAT auth here would un-do #4161. Stay with App-auth + grant the missing permission. |
| Source PR #4122 is the workflow scaffold | `gh pr view 4122 --json title` → "feat(github-app): manifest JSON + static init page + drift-guard extension (#4121)" — that's PR #4121's MERGED commit; PR #4122 itself is the workflow scaffold (separate PR). Both probed per `2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts.md`. The issue body's #4122 reference is correct. | Reference accepted; no edit. |
| Source PR-H #4066 introduced `github_actions_secret.doppler_token_kb_drift` | Confirmed: `git log --oneline -- apps/web-platform/infra/kb-drift.tf` shows `5bc14c7f feat: Daily Priorities multi-source — GitHub App webhook + KB-drift walker (PR-H) (#4066)` as the file's introduction. | Reference accepted. |
| Committed manifest JSON declares 8 permissions including secrets:write | `apps/web-platform/infra/github-app-manifest.json:18-26` declares 7 keys — `secrets` is absent. The App's live `gh api apps/soleur-ai` returns 8 keys including `secrets:write`. The drift-guard `bin/diff-github-app-manifest.sh` would classify this as `permission_unexpected_grant` (live > manifest), but the guard reads against `gh api /app` and the cron has been passing because the suppress-window or shape-handler is masking it (last 3 runs all `success`). | Sync manifest JSON to declare `secrets: "write"`. After sync, drift-guard's manifest-vs-live diff is clean. |

## Files to Edit

1. **`apps/web-platform/infra/github-app-manifest.json`** — add one key to `default_permissions`: `"secrets": "write"`. Total keys 7 → 8. Comment header in the file is JSON-only (no `//` comments); no narrative edit needed. The diff is exactly +1 line.

2. **`apps/web-platform/infra/main.tf`** — update the comment block at lines 58-65 to:
   - Cite #4173 alongside #4150 in the App-auth migration history.
   - Replace "declares `secrets:write` in its permissions" with "declares 8 permissions including `secrets:write` (installation 122213433 grants all 8)" — current text at line 61 is now an over-claim about the installation; rewrite to reflect post-#4173 reality.

3. **`apps/web-platform/infra/github-app.tf`** — update header comment block (lines 1-26) to:
   - Add a one-line note: "`secrets:write` added to default_permissions in #4173; installation 122213433 re-accepted the new permission via the GitHub UI (operator-only carve-out per `2026-05-15-operator-only-step-canonical-list.md` case-b — App-permission acceptance has no GitHub API)."
   - Cite the manifest-vs-live drift-guard as the standing detection primitive.

4. **`knowledge-base/engineering/ops/runbooks/github-app-provisioning.md`** — under Step 2 "Permissions: 7 keys per the manifest's default_permissions", update to "8 keys" and re-enumerate (`actions:write, administration:write, checks:read, contents:write, members:read, metadata:read, pull_requests:write, secrets:write`). Add a sentence: "Whenever a new permission key is added to the manifest, the founder must re-accept the App installation at `https://github.com/organizations/jikig-ai/settings/installations/122213433` — there is no API for App-permission self-modification."

5. **`apps/web-platform/test/github-app-manifest-drift-guard.test.ts`** — no test edit required. The fixtures are synthesized inline (`manifest: object; response: object`) — none of the six test cases hardcode a specific permission key value. After-manifest-edit, the next CI run will exercise the script against the new manifest content; the script's behavior is unchanged.

## Files to Create

None. This PR is text + manifest edits + a one-time operator browser-click.

## Implementation Phases

### Phase 0 — Pre-flight verification

**Goal:** lock in the diagnosis before editing any files.

0.1. Confirm installation permission gap is the active root cause:
```bash
gh api /orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug=="soleur-ai") | .permissions'
```
Expected output: 7 keys (NO `secrets`). If output already shows `secrets: write`, the gap has self-resolved (operator may have clicked Accept independently) — skip Phase 1, proceed to Phase 2 manifest-sync only.

0.2. Confirm App-level declaration is already 8 keys:
```bash
gh api apps/soleur-ai --jq '.permissions'
```
Expected: 8 keys including `secrets: write`. If App-level is also 7 keys, the prior PR's permission addition was rolled back — Phase 1 must additionally re-add at the App level via the App settings UI (and document the rollback in a session-error learning).

0.3. Confirm the failed run's error is on the `public-key` endpoint:
```bash
gh run view 26166234267 --log-failed 2>&1 | grep "actions/secrets/public-key"
```
Expected: at least one match. If zero matches, the failure mode has shifted — re-triage before applying this plan.

### Phase 1 — Operator action: grant secrets:write on installation 122213433

This is the **one** operator-driven step. It is not automatable: GitHub has no API for self-modifying App-installation permissions (verified via docs grep and prior-session attempt per `2026-05-20-tf-operator-mint-variables-are-design-smell.md` Session Error 1). The acceptance click is the canonical OAuth-consent carve-out (operator-only canonical list case-b).

**Procedure:**

1. Operator navigates to <https://github.com/organizations/jikig-ai/settings/installations/122213433>.
2. GitHub renders a "Review permissions" or "Accept new permissions" banner if the App's declared permissions exceed the installation's grants. Banner exact wording: "Soleur AI requests new permissions" with a list including "Read and write access to secrets".
3. Operator clicks **Accept new permissions**.
4. Verify via `gh api /orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug=="soleur-ai") | .permissions.secrets'` → returns `"write"`.

**Agent automation path:** Use Playwright MCP per the same pattern as #4150 Session Error 2:
- `browser_navigate` to the installation URL
- IMMEDIATELY chain `browser_wait_for { text: "Soleur AI", time: 300 }` in the same tool-call batch (handoff-safe)
- `browser_snapshot` to identify the Accept button's ref
- `browser_click` on the ref
- `browser_wait_for { text: "Permissions accepted" or post-action marker, time: 60 }`
- Verify via `gh api` command above

**If installation 122213433 does NOT render a "Review permissions" banner** (because GitHub considers the permission already accepted, or the banner is gated behind a different UI path):
- Visit `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai/installations` and click "Configure" on the org row.
- The Configure page shows a permission-acceptance section if any are pending.
- If still no banner, the App may not actually declare `secrets:write` despite the `gh api apps/soleur-ai` response — re-check via Phase 0.2 and escalate (manifest-vs-live drift would have been an inverted form of this).

### Phase 2 — Sync committed manifest JSON

After Phase 1's installation-grant succeeds, sync the committed manifest to match the live App declaration. This closes the drift-guard's `permission_unexpected_grant` window without re-pinging the alarm.

2.1. Edit `apps/web-platform/infra/github-app-manifest.json`:
```diff
   "default_permissions": {
     "actions": "write",
     "administration": "write",
     "checks": "read",
     "contents": "write",
     "members": "read",
     "metadata": "read",
-    "pull_requests": "write"
+    "pull_requests": "write",
+    "secrets": "write"
   },
```

2.2. Verify the JSON parses:
```bash
jq '.default_permissions' apps/web-platform/infra/github-app-manifest.json
```
Expected: 8 keys.

2.3. Run the shared diff script against the live App to assert no drift:
```bash
MANIFEST_FILE=apps/web-platform/infra/github-app-manifest.json \
RESPONSE_FILE=<(gh api apps/soleur-ai) \
  bash bin/diff-github-app-manifest.sh
```
Expected: exit 0, no stdout. (If exit non-zero with `permission_unexpected_grant:secrets=write`, Phase 2.1 was not saved correctly. If `permission_drift:secrets=write`, the App level is missing the key — escalate to Phase 0.2.)

2.4. Run the contract test:
```bash
cd apps/web-platform && bun test test/github-app-manifest-drift-guard.test.ts
```
Expected: all 6 cases pass (no behavior change; the script is unchanged).

### Phase 3 — Update comment headers and runbook

3.1. Edit `apps/web-platform/infra/main.tf:58-65`:
```diff
-# PR-H (#3244) — GitHub provider for Actions-secret publishing (kb-drift).
-# Post-#4150: switched from PAT auth (var.github_actions_token, deleted) to
-# App-installation auth. The soleur-ai App (id 3261325, org-wide installation
-# 122213433 on jikig-ai) declares `secrets:write` in its permissions
-# (verified via `gh api apps/soleur-ai`); the integrations/github provider
-# exchanges App-credentials for a short-lived installation token at each
-# `terraform plan/apply`. Net narrowing vs. long-lived PAT.
+# PR-H (#3244) — GitHub provider for Actions-secret publishing (kb-drift).
+# Post-#4150: switched from PAT auth (var.github_actions_token, deleted) to
+# App-installation auth. The soleur-ai App (id 3261325, org-wide installation
+# 122213433 on jikig-ai) declares 8 permissions including `secrets:write`
+# (verified via `gh api apps/soleur-ai`); installation 122213433 grants all
+# 8 (verified via `gh api /orgs/jikig-ai/installations` post-#4173 — see
+# learning 2026-05-20-app-declared-secrets-write-but-installation-grant-skipped).
+# The integrations/github provider exchanges App-credentials for a short-
+# lived installation token at each `terraform plan/apply`. Net narrowing
+# vs. long-lived PAT.
```

3.2. Edit `apps/web-platform/infra/github-app.tf` header (lines 1-26) — add a sentence after the existing `Post-#4150:` block:
```
# Post-#4173: `secrets:write` added to the App manifest's default_permissions;
# installation 122213433 re-accepted the new permission via the GitHub UI
# (operator-only carve-out per 2026-05-15-operator-only-step-canonical-list.md
# case-b — App-permission acceptance has no GitHub API). Drift-guard at
# .github/workflows/scheduled-github-app-drift-guard.yml is the standing
# detection primitive for manifest-vs-live divergence going forward.
```

3.3. Edit `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md` Step 2 enumeration:
```diff
-- Permissions: 7 keys per the manifest's `default_permissions`
+- Permissions: 8 keys per the manifest's `default_permissions`
+  (`actions:write`, `administration:write`, `checks:read`, `contents:write`,
+   `members:read`, `metadata:read`, `pull_requests:write`, `secrets:write`)
```

Add a new subsection after Step 2 (before Step 3):

```markdown
### Step 2a — Re-accept App installation when permissions widen

If a Soleur PR adds a new key to `default_permissions` in
`apps/web-platform/infra/github-app-manifest.json`, the founder MUST
re-accept the App installation. GitHub has no API for this — it is a
one-time UI click per installation per permission widening.

1. Navigate to `https://github.com/organizations/jikig-ai/settings/installations/122213433`
2. Click "Accept new permissions" on the banner GitHub renders.
3. Verify via:
   `gh api /orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug=="soleur-ai") | .permissions'`

PR #4173 is the canonical example: `secrets:write` was added to the
manifest; the installation needed re-acceptance before the
`integrations/github` provider could publish `github_actions_secret`
resources.
```

### Phase 4 — End-to-end verification

4.1. Re-run the apply workflow via `workflow_dispatch`:
```bash
gh workflow run apply-web-platform-infra.yml --field reason="Verify #4173 fix — installation 122213433 now grants secrets:write"
```

4.2. Tail the run until completion:
```bash
RUN_ID=$(gh run list --workflow=apply-web-platform-infra.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN_ID"
```

4.3. Verify success:
```bash
gh run view "$RUN_ID" --json conclusion --jq '.conclusion'
```
Expected: `"success"`. AND verify the `github_actions_secret.doppler_token_kb_drift` resource is now in state:
```bash
# From a local clone with prd_terraform Doppler config access:
cd apps/web-platform/infra
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
terraform init -input=false
terraform state list | grep -F 'github_actions_secret.doppler_token_kb_drift'
```
Expected: one match.

4.4. Verify `DOPPLER_TOKEN_KB_DRIFT` Actions secret is published:
```bash
gh api /repos/jikig-ai/soleur/actions/secrets/DOPPLER_TOKEN_KB_DRIFT --jq '.name'
```
Expected: `"DOPPLER_TOKEN_KB_DRIFT"`. (Reads only the metadata, not the encrypted value — the value remains in GitHub's encrypted store, only consumable by workflow steps.)

4.5. Verify the kb-drift-walker cron can consume the new secret:
```bash
gh workflow run kb-drift-walker.yml || true
RUN_ID=$(gh run list --workflow=kb-drift-walker.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN_ID"
gh run view "$RUN_ID" --json conclusion --jq '.conclusion'
```
Expected: `"success"`. The cron consumes `DOPPLER_TOKEN_KB_DRIFT` as `DOPPLER_TOKEN` — if this works, the published token is functional end-to-end.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `apps/web-platform/infra/github-app-manifest.json` `default_permissions` contains 8 keys including `"secrets": "write"`. Verify: `jq '.default_permissions | keys | length' apps/web-platform/infra/github-app-manifest.json` returns `8`.
- [ ] AC2: `apps/web-platform/infra/github-app-manifest.json` parses as valid JSON. Verify: `jq -e '.' apps/web-platform/infra/github-app-manifest.json > /dev/null && echo PASS`.
- [ ] AC3: Manifest-vs-live diff script reports no drift. Verify: `MANIFEST_FILE=apps/web-platform/infra/github-app-manifest.json RESPONSE_FILE=<(gh api apps/soleur-ai) bash bin/diff-github-app-manifest.sh; echo "exit=$?"` returns `exit=0` with no stdout.
- [ ] AC4: Manifest parity + drift-guard contract tests pass. Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-app-manifest-parity.test.ts test/github-app-manifest-drift-guard.test.ts test/github-app-drift-guard-contract.test.ts` exits 0 with all assertions passing. (apps/web-platform uses vitest, not bun-test — `bunfig.toml` blocks bun-test discovery.)
- [ ] AC5: `apps/web-platform/infra/main.tf` comment block at lines 58-65 cites #4173 and the post-#4173 installation-grant state. Verify: `grep -c '#4173' apps/web-platform/infra/main.tf` returns ≥1.
- [ ] AC6: `apps/web-platform/infra/github-app.tf` header references the operator-only carve-out for App-permission acceptance. Verify: `grep -c 'Post-#4173' apps/web-platform/infra/github-app.tf` returns ≥1.
- [ ] AC7: `knowledge-base/engineering/ops/runbooks/github-app-provisioning.md` enumerates all 8 permission keys and includes the Step 2a re-acceptance subsection. Verify: `grep -c 'secrets:write' knowledge-base/engineering/ops/runbooks/github-app-provisioning.md` returns ≥1 AND `grep -c 'Re-accept App installation' knowledge-base/engineering/ops/runbooks/github-app-provisioning.md` returns ≥1.
- [ ] AC8: `gh issue view 4173 --json state` returns `"OPEN"` AND PR body uses `Ref #4173` (NOT `Closes #4173`) — the issue closure is tied to Phase 1 (post-merge operator-action) AND Phase 4 verification, both post-merge per `2026-04-22-plan-ac-external-state-must-be-api-verified.md`. The agent runs the operator-mediated browser action inline at /work time per Phase 1; resulting installation state is the close trigger.

### Post-merge (operator + agent)

- [ ] AC9: Installation 122213433 grants `secrets:write` (Phase 1 already run by agent + operator). Verify: `gh api /orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug=="soleur-ai") | .permissions.secrets'` returns `"write"`.
- [ ] AC10: A `workflow_dispatch` re-run of `apply-web-platform-infra.yml` (Phase 4.1) completes with `conclusion=success`. Verify: `gh run list --workflow=apply-web-platform-infra.yml --limit 1 --json conclusion --jq '.[0].conclusion'` returns `"success"`.
- [ ] AC11: `github_actions_secret.doppler_token_kb_drift` is in Terraform state. Verify via Phase 4.3.
- [ ] AC12: `DOPPLER_TOKEN_KB_DRIFT` Actions secret exists in the soleur repo. Verify via Phase 4.4.
- [ ] AC13: `kb-drift-walker.yml` runs successfully against the new secret. Verify via Phase 4.5.
- [ ] AC14: Issue #4173 closed via `gh issue close 4173` after AC9-AC13 all pass. Downstream issues #4136 and #4137 unblocked (cross-referenced in their bodies).
- [ ] AC15: Hourly `scheduled-github-app-drift-guard.yml` next run reports no drift. Verify (after waiting up to 1h or via `gh workflow run scheduled-github-app-drift-guard.yml`): `gh run list --workflow=scheduled-github-app-drift-guard.yml --limit 1 --json conclusion --jq '.[0].conclusion'` returns `"success"`.

## Risks

- **R1 — Operator declines or cannot click Accept.** Mitigation: Phase 1 is the only operator-driven step; if blocked, the PR remains text-only (manifest + comments + runbook). The drift-guard's `permission_drift` mode would then re-fire after merge (because manifest declares X, live installation lacks X). Recovery: revert the manifest edit OR proceed with the operator click; both are reversible.

- **R2 — GitHub renders no "Accept new permissions" banner.** Possible if the App-level declaration was retracted between Phase 0.2 verification and Phase 1 execution. Phase 1 includes a sub-branch to escalate back to App-settings UI (re-add the permission at the App level, then re-attempt installation accept). Documented in `2026-05-20-tf-operator-mint-variables-are-design-smell.md` Session Error 1 as a known-recurring trap.

- **R3 — `scheduled-github-app-drift-guard.yml` is currently passing despite live=8/manifest=7 mismatch.** Last 3 hourly runs all `success`. Investigation needed: is the drift-guard's permission-comparison logic correctly classifying `permission_unexpected_grant` (live > manifest)? If the guard is silently swallowing this class, Phase 4 should also include an explicit test that synthesizes a known-drift state and verifies the guard fires (see deepen-plan additions if applicable). Initial hypothesis: the `MANIFEST_DRIFT_SUPPRESS_UNTIL` file controls a suppression window per the workflow checkout list. `ls apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` returned "No such file or directory" → suppression is NOT active. So the guard SHOULD fire `permission_unexpected_grant`. The fact it's passing is itself a bug — but landing the manifest edit immediately closes the gap, so we don't have to fix the guard's blind spot in this PR. Track as a follow-up.

- **R4 — `provider "github"` may cache the old installation token.** Terraform provider issues a fresh token per `terraform plan/apply` invocation (per #4150 plan's research). The new installation grant takes effect on the NEXT plan/apply, not on any in-flight run. Workflow re-run in Phase 4.1 picks up the new token automatically. No state mutation needed.

- **R5 — `secrets:write` widens blast radius if a long-lived installation token is later exfiltrated.** The installation token has a 1-hour TTL (per #4150 plan). Adding one permission to a short-lived token's surface is a bounded widening. The reverse (revert to operator-minted PAT) was previously rejected by #4161 — the App-auth path is strictly better even with the widened surface, because the PAT alternative is long-lived and unscoped to the App's installation set.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Filled here with `threshold: none` + explicit scope-out override above.

- **The committed `apps/web-platform/infra/github-app-manifest.json` MUST be the source-of-truth.** Online-write paths into Doppler/Doppler-sourced secrets are explicitly rejected per `2026-05-20-online-write-on-source-of-truth-breaks-detection-invariant.md`. This PR keeps the manifest as the only writeable source (hand-edited in repo, code-review-gated).

- **When adding a new key to `default_permissions`, BOTH the manifest JSON AND the live App declaration AND the installation grant must move together.** The three layers are independent and drift silently. Order matters:
  1. App-level declaration (operator clicks at github.com/settings/apps/soleur-ai/permissions OR Soleur-side updates the App via manifest UPDATE flow if supported).
  2. Installation grant (operator clicks Accept on installation page).
  3. Manifest JSON in repo (code edit + PR merge).

  Skipping any step leaves a hidden 403 like #4173. The Step 2a runbook addition codifies this.

- **`gh api apps/soleur-ai` returns App-level declared permissions; `gh api /orgs/.../installations` returns installation-level granted permissions.** The drift-guard reads the former; the runtime token carries the latter. **These can diverge.** This PR's existence is the proof. Adding an installation-level check to the drift-guard would be a separate scope (see follow-up below).

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in apps/web-platform/infra/github-app-manifest.json apps/web-platform/infra/main.tf apps/web-platform/infra/github-app.tf knowledge-base/engineering/ops/runbooks/github-app-provisioning.md; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

None at plan-write time. (To be confirmed by /work skill before commit.)

## Domain Review

**Domains relevant:** Engineering (infra surface), Compliance (Art. 30 register references App identity material).

### Engineering

**Status:** reviewed (carry-forward from #4150 / #4161 plan body — same surface, narrower change).
**Assessment:** This PR is a corollary of #4161's App-auth migration. The architectural decision (App-auth > PAT) is unchanged. The PR widens one installation grant by one key (`secrets:write`) — the minimum increment needed to make the migrated provider functional for the `github_actions_secret` resource it was already configured to manage. No new vendors, no new tokens, no new resource types.

### Compliance

**Status:** reviewed.
**Assessment:** `knowledge-base/legal/article-30-register.md:299` already documents the App-installation token model under "TOMs (Art. 32) (1) GitHub App installation token short-lived". Adding `secrets:write` to the installation's grant set does not change the data categories processed (issue bodies, commit author emails, repo metadata, installation tokens — line 55 of `compliance-posture.md`). The new permission scope governs CI-secret publishing for the kb-drift cron — internal infrastructure, no operator/end-user PII. No Article 30 register edit required; no DPA change.

### Product/UX Gate

Skipped — not a Product/UX-relevant change (infra-only).

## Infrastructure (IaC)

### Terraform changes

None. This PR edits a static manifest JSON and three comment blocks. The `provider "github"` declaration in `main.tf` already uses `app_auth { id, installation_id, pem_file }` (post-#4161); no provider-config change needed.

### Apply path

- **(a) Manifest JSON edit**: code edit, no apply.
- **(b) Installation grant**: operator-mediated browser click (Phase 1), recorded in the runbook addition.
- **(c) Re-run of `apply-web-platform-infra.yml`**: Phase 4.1 `gh workflow run`. The workflow's existing destroy-guard, environment gate, and target allow-list apply unchanged.

Expected downtime/blast-radius: **zero**. The failed apply mutated zero resources; the next successful apply creates `github_actions_secret.doppler_token_kb_drift` for the first time. No destroys.

### Distinctness / drift safeguards

- `dev != prd` precondition: N/A — this PR touches the prd path only. There is no dev installation; `prd_kb_drift_walker` Doppler config + `122213433` installation are prd-scoped.
- `lifecycle.ignore_changes`: none added or modified.
- State storage: R2 backend (already encrypted at rest); the published Actions-secret value lives in GitHub's encrypted store, not in terraform state in plaintext.

### Vendor-tier reality check

- GitHub: free for `secrets:write` on a private org-owned repo.
- Cloudflare / Better Stack / Doppler / Hetzner: no tier change.

## Test Strategy

- **Unit / contract tests**:
  - `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` — all cases pass (unchanged behavior; the manifest content is fixture-synthesized inside each case, so no test-fixture coupling to the production manifest). `apps/web-platform/test/github-app-manifest-parity.test.ts` — EXPECTED_PERMISSION_KEYS extended to 8 keys; all assertions pass.
  - JSON parse + key-count via `jq` (AC1, AC2).

- **Integration**:
  - Manifest-vs-live diff via `bin/diff-github-app-manifest.sh` (AC3) — exercises the actual script against the real `gh api` response.
  - `terraform plan -target=github_actions_secret.doppler_token_kb_drift` (post-grant) — would succeed locally given the new installation permission; CI run is the canonical exerciser via Phase 4.1.

- **End-to-end**:
  - Phase 4.1-4.5 re-runs the failing workflow against the new permission state; AC10-AC13 are the post-merge contract.
  - `kb-drift-walker.yml` consumes the published secret (Phase 4.5) — proves the secret-publish → secret-consume loop closes.

No new test framework required. The existing vitest + `bun test` toolchain covers the surface.

## Prior Art

- **#4115 / PR #4121 (merged 2026-05-20)** — manifest-as-IaC pattern + drift-guard extension. Learning: `2026-05-20-manifest-as-iac-with-shared-diff-script-contract.md`. Establishes the manifest file as the source-of-truth and the diff-script as the shared contract between CI and contract test. This PR consumes both invariants.
- **#4150 / PR #4161 (merged 2026-05-20)** — App-auth migration. Learning: `2026-05-20-tf-operator-mint-variables-are-design-smell.md`. Session Error 1 specifically calls out this class of failure: "the App needed `Repository Secrets: Read and write` permission added to its declared permissions, AND the installation needed to accept the new permission." The prior PR added the App-level declaration via Playwright; the installation-grant step appears to have been incomplete (or the previous click only updated the manifest at the App level without triggering the installation re-accept banner). This PR closes that gap.
- **#3187 / PR #3224 (merged 2026-05-05)** — App drift-guard (App-level declaration vs `gh api /app`). Runbook: `knowledge-base/engineering/ops/runbooks/github-app-drift.md`. The drift-guard does NOT compare installation grants — that's the load-bearing gap this PR's #4173 exists to highlight.

## References

- Failed run: <https://github.com/jikig-ai/soleur/actions/runs/26166234267>
- Source issue: #4173
- Prior PRs in cascade: #4066 (PR-H, introduced the resource), #4121 (manifest+drift-guard), #4161 (App-auth migration), #4147 (provider lockfile pin), #4166-closer (SSH key path gate)
- Blocked downstream: #4136, #4137
- Open follow-ups expected post-merge:
  - **R3 follow-up**: investigate why the drift-guard's last 3 hourly runs missed the live=8/manifest=7 drift. File a `ci/guard-broken` issue if reproducible after this PR's manifest edit lands (the edit clears the divergence; the bug-window is the past — Sentry data and a targeted re-run of the workflow against the pre-merge SHA would be needed to reproduce, may be out of scope).
  - **Installation-grant drift-guard extension** (separate scope): extend `bin/diff-github-app-manifest.sh` (or add a sibling script) to ALSO compare `gh api /orgs/jikig-ai/installations` per-installation permissions against the manifest. The current script reads App-level only. Filing as `feat: scheduled-github-app-drift-guard installation-grant comparison` — re-evaluate when the next App-permission widening is queued.
- Canonical TF invocation: `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`
- Operator-only canonical list (App-permission accept is the vendor-authorization-scope class): `knowledge-base/project/learnings/2026-05-15-operator-only-step-canonical-list.md`
- Hard rule `hr-exhaust-all-automated-options-before` — exhausted: GitHub has no API for App-installation permission self-modification; the click is the legitimate operator-only carve-out.
- Hard rule `hr-never-label-any-step-as-manual-without` — satisfied: Phase 1 documents WHY the step is operator-only (no API), HOW the agent automates as much as possible (Playwright MCP up to the click), and links the canonical-list case.
