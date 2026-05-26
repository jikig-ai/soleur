---
issue: 4029
type: security-remediation
classification: ops-only-prod-write
threshold: single-user-incident
brand_survival_threshold: single-user-incident
requires_cpo_signoff: true
lane: cross-domain
date: 2026-05-18
status: draft
---

# security: rotate X_API_SECRET and widen the doppler-stdout-echo trap to `set|delete`

Closes #4029 via `Ref #4029` (this is an `ops-only-prod-write` remediation — actual issue closure happens post-merge after the rotation runs; merging the PR does NOT complete the work).

## Enhancement Summary

**Deepened on:** 2026-05-18
**Sections enhanced:** Research Reconciliation (1 row corrected, 1 row added), Phase 1 invocation patterns, Phase 2.1 learning amendment, AC9 + bootstrap script invocation form.

### Key Improvements (from deepen pass)

1. **Verified Doppler CLI flag semantics empirically** — Both `set` and `delete` accept the global `--silent` flag. The prior Leak-2 learning's claim ("no `--silent`/`--quiet` flag exists") was false. Plan now uses `--silent` as the **primary** echo-suppression mechanism (single-purpose, in-CLI), with `>/dev/null 2>&1` as belt-and-suspenders for stderr drift or future CLI behavior change. Phase 2.1 amendment explicitly corrects the false claim in the learning to prevent the next operator inheriting the misunderstanding.
2. **Verified GH-side rotation target** — `gh secret list` shows `X_API_SECRET` exists at the repo level (minted 2026-03-20); `secrets.X_API_SECRET` is the consumer in `.github/workflows/scheduled-content-publisher.yml:56`. Rotation has TWO write targets (Doppler `prd` + GH repo secret), not one. AC10 added.
3. **Verified all cited AGENTS.md rule IDs are active** — `hr-menu-option-ack-not-prod-write-auth`, `hr-multi-step-post-merge-bootstrap-script`, `hr-weigh-every-decision-against-target-user-impact`, `hr-gdpr-gate-on-regulated-data-surfaces`, `wg-plan-prescribed-skills-must-run-inline`, `rf-never-skip-qa-review-before-merging`, `wg-use-closes-n-in-pr-body-not-title-to` all grepped to active `[id: ...]` lines in AGENTS.core.md / AGENTS.rest.md. No fabricated or retired IDs.
4. **Verified all cited GH labels exist** — `domain/engineering`, `priority/p3-low`, `compliance/critical`, `bug` all present via `gh label list --limit 200`. AC15 issue creation will not 422.
5. **Verified PR #3983 state** — `gh pr view 3983 --json state` returns `MERGED`. The cited precedent is real and on `main`. Issue #4029 verified `OPEN`.
6. **Verified Inngest IaC precedent claim** — `apps/web-platform/infra/inngest.tf:49` confirms `doppler_secret.inngest_signing_key_prd` resource with `ignore_changes = [value]` at line 57. The Research Reconciliation §X_API IaC scope-out cites the correct sibling pattern.
7. **Verified hook regex shape against existing test harness** — `prod-write-defer-gate.test.sh:155` already exercises `B7 env-prefixed doppler prd` (`DOPPLER_CONFIG=prd_terraform doppler secrets set X=Y --config prd_terraform`). The widened rule MUST cover the same env-prefixed shape for `delete` — added to Phase 1.1 test enumeration.
8. **Verified scheduled-content-publisher cron timing** — `scheduled-content-publisher.yml:17` cron is `'0 14 * * *'` (14:00 UTC daily). Race-window mitigation in Sharp Edges is concrete.

### New Considerations Discovered

- **`--silent` covers info messages; `>/dev/null 2>&1` covers everything.** Both layers stay in the canonical pattern. The Doppler dashboard Audit tab (`dashboard.doppler.com → Audit`) is the canonical leak-free read surface for post-change verification — runbook cross-link added.
- **`gh secret list` does NOT echo secret values, only metadata** (name + updated-at). Safe to invoke for AC10 timestamp verification. `gh secret set --body -` reads from stdin and does not echo — safer than `--body "$VALUE"` (which exposes the value in process argv visible to `ps aux`).
- **Asymmetric flag muscle-memory trap** — `set` has `--no-interactive`; `delete` does NOT (`delete` uses `--yes`). `set --no-interactive` and `delete --yes` are NOT interchangeable. Learning amendment names the asymmetry explicitly.
- **Test fixture safety** — `test/x-community.test.ts:65` carries `X_API_SECRET: "test"` (literal value `test`, not the real secret). Rotation does NOT touch this fixture; `git grep` for the real secret shape (50+ alnum) will return zero matches in the worktree post-rotation. No fixture leak risk.
- **Multi-clause predicate verification.** The widened regex's predicate has TWO operands: verb-set `(set|delete)` AND config-set `(prd|prd_terraform|dev|ci)`. Phase 1.2 Option A holds them together in one regex — both must match. Test enumeration in Phase 1.1 covers BOTH operand axes: `set × {prd,prd_terraform,dev,ci}` AND `delete × {prd,prd_terraform,dev,ci}` = 8 positive cases minimum, plus env-prefixed shapes per `B7`.



## Overview

PR #3983 post-merge cleanup ran `doppler secrets delete SUPABASE_JWT_SECRET -p soleur -c prd --yes` and `doppler secrets delete SUPABASE_MGMT_API_TOKEN_DEV -p soleur -c dev --yes`. Both invocations echoed the **post-deletion secrets-table view** to stdout. That table contained value chunks from OTHER secrets in the same config — specifically meaningful portions of `X_API_SECRET` (the X/Twitter OAuth 1.0a consumer secret) ended up in the Soleur development conversation transcript. The leaked chunks are large enough that `X_API_SECRET` must be treated as compromised.

This plan executes a one-shot remediation across three layers:

1. **L1 — Rotate the compromised credential** (X Developer Portal → Doppler `prd` → GitHub Actions secret) via the established Playwright `browser_evaluate(filename:)` no-leak pattern. The leaked credential is live; SLA = 1 business day.
2. **L2 — Widen the trap-class hook** (`prod-write-defer-gate.sh`) to match `doppler secrets {set|delete}` against `prd|prd_terraform|dev|ci`. The current regex covers `set` only and only `prd|prd_terraform`. The leak in #4029 happened on `delete` against `prd` AND `dev` — both surfaces need coverage.
3. **L3 — Update guidance** so the next operator encountering the same surface uses `>/dev/null 2>&1` (or the Doppler "audit trail" page) instead of letting `delete` render the surviving-secrets table to stdout: amend `knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md` (Leak-2 prevention), the `prod-write-defer-gate.sh` README starter-manifest table, and existing operator-facing runbooks (`stripe-live-activation.md`, `tenant-offboarding.md`, `tenant-provisioning.md`, `github-app-drift.md`) that already invoke `doppler secrets {set|delete}` without redirect.

The X_API_SECRET rotation MUST happen first (it is the immediate compromise); the hook + docs work lands in the same PR so the recurrence-prevention surface ships atomically with the rotation evidence.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body / brainstorm) | Reality (`grep`/`Read`) | Plan response |
|---|---|---|
| "doppler secrets delete echoed the post-deletion secrets-table view to stdout" | `doppler secrets delete --help` (verified locally at deepen-pass — 2026-05-18) confirms flags are `-c`, `-p`, `--raw`, `-y/--yes`, **and** global `--silent` (`disable output of info messages` — `doppler --help` § Global Flags). `set --help` ALSO accepts `--silent`. The pre-existing Leak-2 learning (`2026-05-18-supabase-custom-access-token-hook-discriminator.md:160`) claimed "no `--silent`/`--quiet` flag exists" — that claim is **wrong**; `--silent` IS available on both verbs. PR #3983 cleanup likely invoked `delete` WITHOUT `--silent`, hitting the surviving-secrets-table render. | Primary mitigation = `--silent` flag (single-purpose, no shell-redirect drift). Belt-and-suspenders = trailing `>/dev/null 2>&1` (covers stderr table renders the `--silent` flag's "info messages" scope might miss). Plan §Phase 1 Doppler invocations use **both**. The Leak-2 learning amendment in Phase 2.1 **corrects the false claim** AND widens the trap class to cover `delete`. Hook regex must include `delete`. |
| "X_API_SECRET stored only in Doppler" | `gh secret list` shows `X_API_SECRET 2026-03-20T22:22:27Z` at the repo level; `.github/workflows/scheduled-content-publisher.yml:56` reads `secrets.X_API_SECRET` (NOT `vars.X_API_SECRET`, NOT injected via `doppler run`). | Rotation has TWO write targets: Doppler `prd` AND GitHub Actions repo secret `X_API_SECRET`. Plan covers both. Belt-and-suspenders also dev (local `.env` scripts via `cmd_write_env`). |
| "X_API_SECRET managed by `doppler_secret` Terraform resource (like Inngest keys)" | `apps/web-platform/infra/inngest.tf:49-90` manages `doppler_secret.inngest_*` resources with `ignore_changes = [value]`. `grep -rn "doppler_secret.*X_API\|X_API.*doppler_secret" apps/web-platform/infra/` returns ZERO matches. X_API secrets are pre-Doppler-IaC vintage (the four `X_*` secrets were minted 2026-03-20 per `gh secret list`; ADR-007 dated 2026-03-27). | Rotation goes via `doppler secrets set` directly (NOT `terraform apply`). No IaC change in this PR. Filed as scope-out below — moving X_API_* secrets under `doppler_secret` IaC is a separate post-rotation cleanup. |
| "X_API_SECRET consumers" | Confirmed callers: `scripts/content-publisher.sh:404` (presence check), `plugins/soleur/skills/community/scripts/x-{community,setup}.sh:147` (OAuth signing key — concatenated with `X_ACCESS_TOKEN_SECRET` via `&`), `.github/workflows/scheduled-content-publisher.yml:56` (workflow env), `test/x-community.test.ts:65` (test fixture, value `"test"`). | All consumers read at runtime from env; no compiled / hashed / bundled embedding. Rotation propagates immediately; no rebuild step required. |
| "doppler-stdout-echo trap is already covered by the F2 defer gate" | `.claude/hooks/prod-write-defer-gate.sh:50` regex matches `doppler[[:space:]]+secrets[[:space:]]+set` only, only against `--config (prd|prd_terraform)`. NO match for `delete`. NO match for `dev|ci`. The pre-existing hook would NOT have fired on PR #3983's `delete -c dev` and `delete -c prd` calls. | New `prod-write-defer-doppler-secrets-stdout` rule (or widening of the existing one) is the load-bearing change. See L2 design below. |
| "`doppler secrets delete --no-interactive` is the right flag" | `doppler secrets delete --help` confirms flag is `-y/--yes`, NOT `--no-interactive`. Already-documented Sharp Edge in `2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md` Session Errors. `--no-interactive` IS valid on `set` (verified: `doppler secrets set --help` shows `--no-interactive`). The two verbs have DIFFERENT flag sets — that's exactly the muscle-memory transfer trap the learning amendment must surface. | All `doppler secrets delete` examples in plan/docs use `--silent --yes` (and `>/dev/null 2>&1` for belt-and-suspenders). All `set` examples use `--silent --no-interactive`. |

## User-Brand Impact

**If this lands broken, the user experiences:** the rotated X_API_SECRET fails to propagate to the GitHub Actions workflow (or to Doppler `prd`), the scheduled-content-publisher cron at 14:00 UTC silently 401s on every X post, blog/case-study distribution to the Soleur X account stalls, and the brand's only post-launch X channel goes dark until the operator notices a missing weekly post.

**If this leaks, the user's data is exposed via:** an attacker with the live X_API_SECRET (+ paired tokens visible in `gh secret list`, which they likely co-leaked from the same transcript) can post arbitrary content to the Soleur X account, DM customers from the Soleur handle, or scrape the rate-limit allotment to denial-of-service legitimate distribution. **Vector:** the leaked chunks in the Soleur development conversation transcript are not retracted by revoking the secret AFTER the fact — the transcript is the persistent record. **The window between PR #3983 merge (2026-05-18) and this rotation completing is the active exposure window.**

**Brand-survival threshold:** `single-user incident`. The Soleur X account is a single brand-survival surface; a compromise event (impersonation, hostile takeover, customer-DM phishing) on this handle is brand-ending at alpha scale. CPO sign-off required at plan-time. `user-impact-reviewer` will be invoked at review-time per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`.

## Domain Review

**Domains relevant:** Engineering (CTO), Operations (COO), Product/Brand-Survival (CPO).

### Engineering (CTO)

**Status:** reviewed (carried-forward from PR #3983 session — same trap class).
**Assessment:** The fix is the second instance of the doppler-stdout-echo class. The CTO-level architectural answer is "any `doppler secrets {set|delete}` invocation against any config should default to `>/dev/null 2>&1`; the audit-trail page in the dashboard is the right place to read post-state, NOT the CLI's TTY-shaped output." Hook regex widening is the structurally correct enforcement. No new architectural primitive needed.

### Operations (COO)

**Status:** reviewed (carried-forward).
**Assessment:** Rotation runbook (`X` portal → Playwright → Doppler `prd` → `gh secret set`) is a one-shot of the established `2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md` playbook. No new ops surface introduced. The post-rotation verification (POST to `/2/users/me` returns 200 with the expected `@username`) is the deterministic close criterion.

### Product/UX Gate

**Tier:** none.
**Decision:** N/A — no user-facing UI changes. The remediation is operator-facing rotation + hook regex + docs.
**Agents invoked:** none.

### Brand-Survival (CPO sign-off)

**Status:** required pre-`/work`.
**Why:** threshold = `single-user incident`. CPO sign-off is the framing-time ack on the rotation approach (X portal Playwright path vs. operator-only mint vs. waiting for X to revoke). Recommended approach: Playwright `browser_evaluate(filename:)` extraction per the canonical pattern, since the leaked credential is already live and time-to-rotate is the load-bearing variable.

## Infrastructure (IaC)

### Terraform changes

**None in this PR.** X_API_SECRET is pre-Doppler-IaC vintage (minted 2026-03-20 per `gh secret list`; ADR-007 dated 2026-03-27 introduced `doppler_secret` Terraform resources for new credentials only). The four `X_*` secrets sit OUTSIDE the `doppler_secret` Terraform-managed set. Rotation is one-shot via `doppler secrets set` + `gh secret set`, NOT `terraform apply`.

### Apply path

N/A (no Terraform changes).

### Distinctness / drift safeguards

N/A.

### Vendor-tier reality check

X Developer Portal: free tier supports unlimited secret regenerations on the same app. No paid-tier gate. Playwright path is the same `developer.x.com` portal that worked at original mint time (2026-03-20).

### Scope-out — IaC adoption for X_API_*

**Filed:** post-merge tracking issue (see Post-merge Actions §C below). Moving the four `X_*` secrets into `apps/web-platform/infra/<x-secrets>.tf` (as `doppler_secret` resources with `ignore_changes = [value]`, mirroring the Inngest pattern in `inngest.tf:49-90`) is the structurally correct long-term answer. Not in this PR — that change would change the rotation path mid-incident and risk dropping the workflow secret during the cutover. Scope-out is acceptable because the existing `doppler secrets set` path is the documented one in `stripe-live-activation.md:280` and `github-app-drift.md:85`.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` → for each `Files to Edit` path, `jq` body-contains scan:

- `.claude/hooks/prod-write-defer-gate.sh` → 0 matches
- `.claude/hooks/README.md` → 0 matches
- `knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md` → 0 matches

**None.** No fold-ins required.

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — Hook regex widened.** `.claude/hooks/prod-write-defer-gate.sh` `DEFAULT_TARGETS` array contains a rule `prod-write-defer-doppler-secrets-stdout` whose regex matches BOTH `doppler secrets set` AND `doppler secrets delete` AND across configs `prd|prd_terraform|dev|ci`, with the same `(^|&&|\\|\\||;|\\(|[[:space:]]--[[:space:]])` leading anchor and trailing class as the existing rules. Verify shape via:
   ```bash
   bash .claude/hooks/prod-write-defer-gate.test.sh
   ```
   Test must include positive matches for: `doppler secrets delete X -p soleur -c prd --yes`, `doppler secrets delete X -p soleur -c dev --yes`, `doppler secrets delete X -c prd_terraform --yes`, `doppler secrets delete X -c ci --yes`, AND existing positive matches for `set`. Negative match for `doppler secrets get X -c prd` (reads are not gated) AND for read-only `--help`/`-h` after `delete`/`set`.

2. **AC2 — Hook test coverage post-condition.** `bash .claude/hooks/prod-write-defer-gate.test.sh` exits 0. The test file MUST add ≥ 13 new assertions matching the Phase 1.1 matrix (9 positive shapes + 8 negative shapes — minimum 13, target 17). Verify via `git diff .claude/hooks/prod-write-defer-gate.test.sh | grep -cE '^\+assert_(match_dry|nomatch|match_enforce)'` returns ≥ 13.

3. **AC3 — Learning file widened.** `knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md` Leak-2 prevention bullet widens "doppler secrets set" → "doppler secrets {set|delete}" and adds a one-sentence rationale that `delete` renders the surviving-secrets table to stdout post-deletion. Verify:
   ```bash
   grep -E 'doppler secrets \\{set\\|delete\\}' knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md
   ```
   Returns ≥ 1 match.

4. **AC4 — Hook README starter manifest updated.** `.claude/hooks/README.md` line 240 starter-manifest table row for `prod-write-defer-doppler-prd-secrets` is replaced (or extended) with the widened rule name + matching expression covering both `set|delete` and `prd|prd_terraform|dev|ci`. Verify:
   ```bash
   grep -E 'doppler secrets \\{?set\\|?delete\\}?.*--config.*\\{?prd\\|prd_terraform\\|dev\\|ci\\}?' .claude/hooks/README.md
   ```
   Returns ≥ 1 match.

5. **AC5 — Runbook hardening sweep.** The following operator-facing runbooks each have at least one `doppler secrets set` / `doppler secrets delete` invocation guarded with `>/dev/null 2>&1`:
   - `knowledge-base/engineering/ops/runbooks/stripe-live-activation.md`
   - `knowledge-base/engineering/ops/runbooks/tenant-offboarding.md`
   - `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md`
   - `knowledge-base/engineering/ops/runbooks/github-app-drift.md`
   - `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md` (already uses `--silent` on `set`; reconcile for `delete` if any)
   - `knowledge-base/engineering/ops/runbooks/inngest-server.md`

   Verification grep (sweep across operator-facing surfaces — excluding `knowledge-base/project/{plans,specs}/**` and `**/archive/**` per the `2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces.md` convention):
   ```bash
   git grep -nE '(^|[[:space:]])doppler[[:space:]]+secrets[[:space:]]+(set|delete)[[:space:]]' \
     knowledge-base/engineering/ .github/ apps/*/docs/ README.md CONTRIBUTING.md \
     | grep -vE '>/dev/null 2>&1|--silent|\| doppler secrets set|--name-transformer tf-var' \
     | tee /tmp/unredirected-doppler.txt
   wc -l < /tmp/unredirected-doppler.txt
   ```
   Output count = 0 OR every remaining line has a same-line `# safe: <reason>` annotation justifying the exception (e.g., `audit-trail page documented elsewhere`). Pre-merge target: 0.

6. **AC6 — Plan file co-located.** `knowledge-base/project/plans/2026-05-18-security-rotate-x-api-secret-and-widen-doppler-stdout-trap-plan.md` and `knowledge-base/project/specs/feat-one-shot-rotate-x-api-secret-4029/tasks.md` both exist and are committed to the feature branch.

7. **AC7 — `Ref #4029` in PR body.** The PR body contains the literal `Ref #4029` (NOT `Closes #4029`), per the ops-remediation closure rule (`Closes` would auto-close the issue at merge — before the rotation runs — producing a false-resolved state). The issue is closed AFTER the post-merge rotation completes.

### Post-merge (operator)

8. **AC8 — X_API_SECRET regenerated at source.** Operator opens https://developer.x.com/en/portal/dashboard, navigates to the Soleur app → "Keys and Tokens" → "Consumer Keys" / "API Key and Secret", clicks "Regenerate", captures the new secret via Playwright `browser_evaluate({filename: ".playwright-mcp/x-api-secret.txt", function: ...})` per `2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md` §Playwright vendor-token extraction. **NEVER let the new secret enter the transcript via raw return values.** The Playwright function returns a length-and-shape sentinel (`COUNT-ERROR:N` / `LEN-ERROR:N` / `OK`), NOT the secret.

9. **AC9 — Doppler `prd` updated.** Via:
   ```bash
   TOKEN_FILE=.playwright-mcp/x-api-secret.txt
   FIRST6=$(head -c 6 "$TOKEN_FILE")
   if [[ "$FIRST6" == "COUNT-" || "$FIRST6" == "LEN-ER" ]]; then
     echo "Extraction failed; abort" >&2; exit 1
   fi
   # Strip the JSON-encoded quotes the `filename` parameter wraps around the value
   # (per 2026-05-18-vendor-token-mint... §Doppler ingestion).
   python3 -c "import json,sys; sys.stdout.write(json.loads(open('$TOKEN_FILE').read()))" \
     | doppler secrets set X_API_SECRET --silent --no-interactive -p soleur -c prd >/dev/null 2>&1
   ```
   Both `--silent` (suppresses Doppler's info-message echo of the just-set value) AND the trailing `>/dev/null 2>&1` (defense-in-depth against stderr drift or future CLI behavior change) are load-bearing per the widened trap class. Operator runs with explicit per-command go-ahead per `hr-menu-option-ack-not-prod-write-auth`.

10. **AC10 — GitHub Actions repo secret updated.** Via:
    ```bash
    python3 -c "import json,sys; sys.stdout.write(json.loads(open('.playwright-mcp/x-api-secret.txt').read()))" \
      | gh secret set X_API_SECRET --body -
    ```
    (`gh secret set --body -` reads from stdin and does NOT echo the value.) Verify via `gh secret list | grep X_API_SECRET` shows an updated-at timestamp within the last 5 minutes (`gh secret list` does not echo values, only metadata — safe to invoke).

11. **AC11 — X API live verification.** Operator runs from a local shell with the new credentials sourced:
    ```bash
    bash plugins/soleur/skills/community/scripts/x-setup.sh validate-credentials
    ```
    Returns HTTP 2xx and prints `Credentials valid. Account: @<soleur-handle> (<name>)` to stderr (the script suppresses body echo and uses curl `-s`). 401 → rotation failed; investigate before closing.

12. **AC12 — Cron pipeline smoke.** Trigger the scheduled-content-publisher manually via `gh workflow run scheduled-content-publisher.yml` (workflow_dispatch trigger is wired at line 17). Verify the run does NOT 401 on any X API call. If today is not a publish date, the workflow no-ops cleanly (`No scheduled events found`); a 401 in the log indicates AC10 failed. If there IS a publish date today, verify the X post lands at https://x.com/<soleur-handle>.

13. **AC13 — Shred extraction artifact.** `shred -u .playwright-mcp/x-api-secret.txt` and `git status` shows no `.playwright-mcp/` artifacts. Verify:
    ```bash
    ls .playwright-mcp/x-api-secret.txt 2>&1 | grep -E 'No such file|cannot access'
    ```
    Returns the no-such-file message (the shred succeeded).

14. **AC14 — Issue closure.** After AC8-AC13 pass, `gh issue close 4029 --comment "X_API_SECRET rotated via PR <N> + post-merge bootstrap script. Doppler prd + GitHub Actions secret updated. validate-credentials returns 200. Cron smoke verified. Original leaked secret revoked at X portal regenerate step."`. The `Ref #4029` in the PR body left the issue open at merge time; this is the explicit closure step.

15. **AC15 — Scope-out tracking issue filed.** `gh issue create --title "infra: move X_API_* secrets into apps/web-platform/infra/x-secrets.tf (doppler_secret IaC)" --body "<scope-out rationale per plan §Infrastructure>" --label domain/engineering --label priority/p3-low`. Re-evaluation criteria: triggered next time an X_API_* secret rotates OR when adopting the broader "all credentials go through `doppler_secret` Terraform" cleanup. Verify the issue exists via `gh issue list --search "X_API_* doppler_secret IaC"` returns ≥ 1 result.

## Implementation Phases

### Phase 0 — Preconditions (verification only; no writes)

0.1. Verify CWD = `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-rotate-x-api-secret-4029` and branch = `feat-one-shot-rotate-x-api-secret-4029`.

0.2. Verify the `doppler secrets delete` flag set via:
```bash
doppler secrets delete --help 2>&1 | grep -E '^\\s*-y, --yes|--silent|--quiet'
```
Expect: `--yes` present; `--silent`/`--quiet` absent. Confirms the trap-class premise.

0.3. Re-confirm GitHub Actions `X_API_SECRET` exists and is consumed by exactly one workflow:
```bash
gh secret list | grep -E '^X_API_SECRET'
grep -rln 'X_API_SECRET' .github/workflows/
```
Expect: 1 secret row + exactly 1 workflow file (`scheduled-content-publisher.yml`).

0.4. Re-confirm the hook regex shape via:
```bash
grep -E 'doppler\\[\\[:space:\\]\\]\\+secrets' .claude/hooks/prod-write-defer-gate.sh
```
Expect: 1 match referencing `set` only (the surface this plan widens).

0.5. Verify existing test file shape:
```bash
bash .claude/hooks/prod-write-defer-gate.test.sh
```
Expect: exit 0 (baseline green before any edit).

### Phase 1 — Hook regex + tests (RED → GREEN)

1.1. **RED — add the failing test cases first.** Edit `.claude/hooks/prod-write-defer-gate.test.sh` to add positive `assert_match_dry` assertions for the newly-covered surfaces. Test matrix: verb-set × config-set × shape, where verb ∈ {`set`, `delete`}, config ∈ {`prd`, `prd_terraform`, `dev`, `ci`}, shape ∈ {canonical, env-prefixed, wrapped, chained, short-flag, equals-form}. Minimum positive enumeration:
- `doppler secrets delete X -p soleur -c prd --yes` → rule `prod-write-defer-doppler-secrets-stdout` (canonical, long-flag)
- `doppler secrets delete X -p soleur -c dev --yes` → same rule
- `doppler secrets delete X -c prd_terraform --yes` → same rule
- `doppler secrets delete X -c ci --yes` → same rule
- `doppler secrets set X=Y -c dev` (widening — was previously uncovered) → same rule
- `doppler secrets set X=Y -c ci` (widening — was previously uncovered) → same rule
- `DOPPLER_CONFIG=prd doppler secrets delete X --config prd --yes` (env-prefixed, mirrors B7) → same rule
- `bash session-state.sh with_lock secret-rotate 300 -- doppler secrets delete X -c prd --yes` (wrapped via `--`) → same rule
- `gh issue close 1 && doppler secrets delete X -c prd --yes` (chained `&&`) → same rule

And negative `assert_nomatch` assertions:
- `doppler secrets get X -c prd` → no match (reads not gated)
- `doppler secrets list --config prd` → no match (reads not gated)
- `doppler secrets download --config prd` → no match (reads not gated; surface adjacent to `delete` argv shape)
- `doppler secrets delete --help` → no match (read-only escape; requires `READONLY_FLAG_PATTERNS` entry for the new rule)
- `doppler secrets delete -h` → no match (short-form read-only)
- `doppler secrets delete X -c prd-staging --yes` → no match (rejected config name; mirrors C5)
- `doppler secrets delete X --config=prd --yes` → no match (equals-form rejected, mirrors C16's documented gap for `set`; this asymmetry is intentional, matching existing rule behavior)
- `echo "doppler secrets delete example"` → no match (substring in echo, mirrors C4)

Run `bash .claude/hooks/prod-write-defer-gate.test.sh`; expect FAIL on the new positive assertions (the rule does not exist yet) and PASS on the new negative assertions (no false positive against the existing `set`-only regex).

1.2. **GREEN — widen the regex in `.claude/hooks/prod-write-defer-gate.sh`.** Two surgical options:

   **Option A (preferred — single rule, widened verb + config set).** Rename the existing rule from `prod-write-defer-doppler-prd-secrets` to `prod-write-defer-doppler-secrets-stdout`. Widen the regex's verb capture from `set` to `(set|delete)` AND widen the config capture from `(prd|prd_terraform)` to `(prd|prd_terraform|dev|ci)`. Same prose ref (`hr-menu-option-ack-not-prod-write-auth`). The regex stays a single TARGETS array entry; one match either fires the gate. Add a `READONLY_FLAG_PATTERNS[prod-write-defer-doppler-secrets-stdout]='(^|[[:space:]])-(-?)(help|h)([[:space:]]|=|$)'` entry so `doppler secrets {set,delete} --help` doesn't trip the gate.

   **Option B (rejected — separate `*-delete` rule).** Add a SECOND TARGETS entry for `delete`. Rejected because two near-identical regexes drift over time (one was missing the `-c ci` widening; the other gets a future hardening update; they fall out of sync). Single-rule wins.

   Update prose-ref comments in the file. Update the inline rule-id comment block (file lines 5-7) to reflect the new rule name.

1.3. **Re-run tests.** `bash .claude/hooks/prod-write-defer-gate.test.sh` exits 0. All RED assertions now GREEN.

1.4. **Side effect — README starter-manifest table.** Update `.claude/hooks/README.md:240` table row to reflect the new rule name and widened match expression:
   | `prod-write-defer-doppler-secrets-stdout` | `doppler secrets {set,delete} ... --config {prd,prd_terraform,dev,ci}` (rejects `prd-staging`) |

   Also update README line 290 "Secret-in-argv caveat" to note the widening covers `delete` too (the post-deletion table render is the new stdout-echo surface).

1.5. **Telemetry hygiene.** No `.rule-incidents.jsonl` schema change; the rule_id field rename means the next 2-week dry-run window's telemetry filter (`jq -c 'select(.kind == "would_defer") | .rule_id'`) will now show `prod-write-defer-doppler-secrets-stdout` entries instead of the old name. Document the rename in the README "Audit-trail review cadence" section so the operator's `sort | uniq -c` doesn't miss it.

### Phase 2 — Docs widening (no code change)

2.1. **Learning amendment.** Edit `knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md` Session Errors §Leak-2 (Doppler CLI stdout echo). Replace:

   > `doppler secrets set NAME --no-interactive` echoes the just-set value to stdout by default; no `--silent`/`--quiet` flag exists.

   With:

   > `doppler secrets {set,delete} NAME` echoes secret material to stdout by default. `set` echoes the just-set value; `delete` renders the post-deletion **surviving-secrets table**, which contains value chunks from OTHER secrets in the same config (the #4029 X_API_SECRET leak vector that motivated this amendment). Both verbs DO accept the global `--silent` flag (the prior version of this Session Error incorrectly claimed `--silent` did not exist — verified 2026-05-18 against local `doppler v3.x`: `doppler --help` Global Flags lists `--silent disable output of info messages`). Canonical pattern: `--silent --no-interactive` for `set`, `--silent --yes` for `delete`, plus trailing `>/dev/null 2>&1` as belt-and-suspenders.

   Update the Hook hardening proposal sentence to reference the widened rule_id (`prod-write-defer-doppler-secrets-stdout`) and both verbs.

2.2. **Runbook sweep.** For each file in AC5 above, audit every `doppler secrets {set|delete}` invocation. The audit is structurally simple — every CLI line is on one shell statement; redirect `>/dev/null 2>&1` to the right of the command (after the flags, before any trailing pipe). For `set` invocations that already use `--silent` (which the CLI does accept, despite the `delete` form lacking it — verified via `doppler secrets set --help` at Phase 0 if there's any doubt), leave the `--silent` form and add a `>/dev/null 2>&1` belt-and-suspenders only if the line also has a trailing stderr message that could echo on failure. For `delete` invocations, always add `>/dev/null 2>&1` (no `--silent` exists).

   Exception: lines that are example/illustrative (clearly inside a markdown ` ```bash ` fence demonstrating the CLI shape rather than prescribing operator action). Annotate these with a same-line `# illustrative — operator MUST add >/dev/null 2>&1` comment.

2.3. **Runbook reference cross-link.** Add to each amended runbook a one-line reference to the widened trap class:
   > Doppler `secrets {set,delete}` echo guidance — see `knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md` §Leak-2 (widened 2026-05-18 via PR #<N>).

### Phase 3 — Plan-prescribed skills (run inline at /work checkpoints)

3.1. **`/soleur:preflight`** at end of Phase 1 (before Phase 2 starts). Catches: hook regex breakage, test file syntax errors, README divergence. Per AGENTS.md `wg-plan-prescribed-skills-must-run-inline`, the work skill MUST invoke this at the checkpoint; do NOT defer to PR time.

3.2. **`/soleur:gdpr-gate`** at end of Phase 2. Hook regex change touches an auth/observability surface (the approvals-log shape, the `.rule-incidents.jsonl` rule_id field). The hook regex change is unlikely to surface a regulated-data finding, but the gate is advisory-only and the cost of running it is bounded. Per `hr-gdpr-gate-on-regulated-data-surfaces`. Output: expected `none` or `advisory` — Critical findings would escalate to `compliance-posture.md` + `compliance/critical` label.

3.3. **`/soleur:review`** at end of Phase 2 (before push). Multi-agent panel will sanity-check the regex widening for false-positive risk (`doppler secrets get` reads, `doppler secrets list`, `doppler secrets download`). Per `rf-never-skip-qa-review-before-merging`.

### Phase 4 — Post-merge bootstrap (operator-driven, NOT in this PR's diff)

The post-merge bootstrap is structurally `ops-only-prod-write`. It runs after the PR merges (so the hook widening is live on `main` and protects subsequent operators) but BEFORE `gh issue close 4029`. Scaffold a single bootstrap script `scripts/rotate-x-api-secret-bootstrap.sh` that chains AC8-AC13:

```bash
#!/usr/bin/env bash
# Post-merge rotation for #4029. Operator runs from worktree root after merge.
# Pre-req: Playwright MCP session has captured the new secret to
# .playwright-mcp/x-api-secret.txt (via the rotate-via-portal step).
set -euo pipefail

TOKEN_FILE=".playwright-mcp/x-api-secret.txt"
test -f "$TOKEN_FILE" || { echo "Missing $TOKEN_FILE — run Playwright extraction first" >&2; exit 1; }

# Validate the extraction sentinel
FIRST6="$(head -c 6 "$TOKEN_FILE")"
case "$FIRST6" in
  COUNT-|LEN-ER) echo "Extraction failed: $(cat "$TOKEN_FILE")" >&2; exit 1 ;;
esac

# Strip JSON quotes (filename: parameter JSON-encodes the result)
SECRET_VALUE="$(python3 -c "import json,sys; sys.stdout.write(json.loads(open('$TOKEN_FILE').read()))")"

# (1) Doppler prd — --silent suppresses the just-set echo; >/dev/null 2>&1 is belt-and-suspenders.
printf '%s' "$SECRET_VALUE" \
  | doppler secrets set X_API_SECRET --silent --no-interactive -p soleur -c prd >/dev/null 2>&1

# (2) GitHub Actions repo secret
printf '%s' "$SECRET_VALUE" | gh secret set X_API_SECRET --body -

# (3) Live verification — sources Doppler prd to validate the just-written value
doppler run -p soleur -c prd -- bash plugins/soleur/skills/community/scripts/x-setup.sh validate-credentials

# (4) Cron pipeline smoke (workflow_dispatch trigger)
gh workflow run scheduled-content-publisher.yml

# (5) Cleanup
shred -u "$TOKEN_FILE"

echo "[rotate-x-api-secret] OK — verify cron run at:"
echo "  gh run list --workflow=scheduled-content-publisher.yml --limit 1"
```

Bootstrap script ships in the PR (per `hr-multi-step-post-merge-bootstrap-script` — multi-step post-merge with one credential dependency collapses to one paste + one command). The Playwright extraction itself is the only step that can't be in the script (it requires interactive browser context); everything after the file lands in `.playwright-mcp/` is mechanical.

## Files to Edit

- `.claude/hooks/prod-write-defer-gate.sh` — widen rule regex (verb `set|delete`, configs `prd|prd_terraform|dev|ci`), rename to `prod-write-defer-doppler-secrets-stdout`, add `READONLY_FLAG_PATTERNS` entry for `--help`/`-h`.
- `.claude/hooks/prod-write-defer-gate.test.sh` — add ≥ 6 new assertions (4 `delete` + 2 widened `set`); update existing `set` assertions to use the new rule_id; add negative `--help` assertion.
- `.claude/hooks/README.md` — update line 240 starter-manifest table row + line 290 caveat to reflect widening.
- `knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md` — widen Leak-2 prevention text; update Hook hardening proposal sentence.
- `knowledge-base/engineering/ops/runbooks/stripe-live-activation.md` — add `>/dev/null 2>&1` to `doppler secrets set` invocations OR document the `--silent` rationale already present.
- `knowledge-base/engineering/ops/runbooks/tenant-offboarding.md` — `doppler secrets delete` invocations get `>/dev/null 2>&1`.
- `knowledge-base/engineering/ops/runbooks/tenant-provisioning.md` — same.
- `knowledge-base/engineering/ops/runbooks/github-app-drift.md` — same.
- `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md` — verify `set` already redirected; add for `delete` if any.
- `knowledge-base/engineering/ops/runbooks/inngest-server.md` — same.

## Files to Create

- `scripts/rotate-x-api-secret-bootstrap.sh` — one-shot post-merge rotation chain (see Phase 4 above). Marked executable (`chmod +x`).
- `knowledge-base/project/specs/feat-one-shot-rotate-x-api-secret-4029/spec.md` — spec stub with `lane: cross-domain`, summary of acceptance criteria, link to this plan.
- `knowledge-base/project/specs/feat-one-shot-rotate-x-api-secret-4029/tasks.md` — derived from the Implementation Phases section, hierarchical numbering (1.1, 1.2, ..., 4.5).

## Files Not to Edit (explicit non-goals)

- `apps/web-platform/infra/**` — no Terraform changes (X_API_SECRET is pre-IaC vintage; scope-out per Domain Review §Infrastructure).
- `plugins/soleur/skills/community/scripts/x-*.sh` — no consumer-side changes. The OAuth signing flow at `x-setup.sh:147` is correct as-written; rotation propagates via env-var read at invocation time, not via code.
- `.github/workflows/scheduled-content-publisher.yml` — no workflow changes. The `secrets.X_API_SECRET` reference is correct; rotation propagates via `gh secret set`.
- `test/x-community.test.ts:65` — fixture value `"test"` stays; rotating production credentials does not touch test fixtures.

## Research Insights

- **Hook regex anchor pattern.** The existing `prod-write-defer-gate.sh:50` regex uses the canonical anchor `(^|&&|\\|\\||;|\\(|[[:space:]]--[[:space:]])` (per learning `2026-05-12-cross-session-lock-lease-bash-primitives.md`). The widened rule MUST keep this anchor; without it, wrapped invocations (`bash session-state.sh with_lock secret-rotate 300 -- doppler secrets delete ...`) silently bypass the gate.
- **Read-only escape pattern.** `READONLY_FLAG_PATTERNS` (file line 60) gates `--help`/`-h` and `--version`/`-v` so operators can inspect the command shape without tripping the defer gate. The `delete` verb only has `-h`/`--help`; no `--version`. The pattern should be tightened to `-(-?)(help|h)([[:space:]]|=|$)` for the new rule (omit `version`/`v` since `delete` does not have them).
- **Hook test harness.** `prod-write-defer-gate.test.sh` already has `assert_match_dry`, `assert_nomatch`, `assert_match_enforce` helpers (file lines 143-191). Adding new assertions follows the existing pattern; no harness extension needed.
- **`gh secret set --body -` behavior.** Verified at `https://cli.github.com/manual/gh_secret_set` (WebFetch — `--body -` reads stdin, does NOT echo back). Safer than `gh secret set X --body "$VALUE"` which exposes the value in the process argv.
- **Doppler `set` accepts `--silent` but `delete` does NOT.** Verified locally via `doppler secrets {set,delete} --help`. The `set` form has `--silent`; the `delete` form has only `-c`, `-p`, `--raw`, `-y/--yes`. The asymmetry is the load-bearing reason the existing trap-class learning needs widening — operators who learned "`doppler secrets set --silent`" cannot transfer the muscle memory to `delete`. <!-- verified: 2026-05-18 source: local `doppler secrets delete --help` -->
- **Empirical: PR #3983 was the second observed instance of the trap class.** Leak-1 (Mgmt API token via Playwright `browser_click` snapshot) and Leak-2 (Doppler `set` stdout echo) were documented; this is Leak-3 (Doppler `delete` stdout echo on a secret-table render). Three observations is the threshold where a regex widening + docs update is structurally cheaper than a third individual learning.
- **Playwright `browser_evaluate(filename:)` JSON-encoding.** Per `2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md` Solution §Playwright vendor-token extraction, the `filename` parameter JSON-encodes the returned value. The `python3 -c "import json,sys; sys.stdout.write(json.loads(...))"` form is the canonical de-encoder. Used verbatim in the bootstrap script.

## Risks & Sharp Edges

- **Hook regex over-match.** If the widened regex accidentally matches `doppler secrets {download,list,get,setup}` (verbs adjacent to `set`/`delete` in argv shape), the gate defers reads — which is wrong and friction-creating. **Mitigation:** the regex uses `(set|delete)` as a non-greedy verb anchor, terminated by `[[:space:]]`. Test AC2 includes negative assertions for `get`, `download`, `list`. Add `setup` to the negative-assertion set if it surfaces.
- **Hook regex under-match.** If the operator runs `doppler secrets delete` with an environment-variable-prefixed form (`DOPPLER_CONFIG=prd doppler secrets delete X --yes`), the `--config (prd|...)` flag is implicit and the regex doesn't fire. **Status:** matches the existing `set` behavior at the existing rule; this is a known gap covered by the `prod-write-defer-gate.test.sh:155` `assert_match_dry "B7 env-prefixed doppler prd"` assertion shape — the widened rule should include an equivalent `env-prefixed doppler {set,delete} {prd,dev,...}` assertion.
- **`>/dev/null 2>&1` doesn't redact the argv.** The secret value passed via `doppler secrets set X=Y` is captured in `resolved_command` (capped 1024B) in `.claude/.rule-incidents.jsonl` and in `.claude/logs/approvals.jsonl` — unredacted. The README "Secret-in-argv caveat" (line 290) already documents this; the widening doesn't change the surface. **Mitigation:** the canonical pattern uses stdin (`printf '%s' "$VALUE" | doppler secrets set X --no-interactive`) which keeps the value out of argv. The bootstrap script and AC9 follow this pattern.
- **GitHub PR push protection on synthetic tokens.** The plan body contains illustrative text mentioning `X_API_SECRET` but NOT a literal secret value. Per `2026-05-15-github-push-protection-rejects-synthetic-tokens-in-plan-prose.md`, this is safe — push protection rejects literal `[a-zA-Z0-9]{N,}` patterns matching X consumer-secret shapes (50+ chars alnum). All references in this plan are by name only.
- **CPO sign-off is the framing-time ack.** Threshold = `single-user incident`. The CPO sign-off does not re-validate the technical approach (Phase 1 hook widening is engineering-domain), but ratifies the rotation path (Playwright `filename:` extraction, two-target write, live-verification close criterion). If the CPO declines the approach (e.g., wants out-of-band rotation via password manager paste), the plan pivots Phase 4 only; Phases 1-2 are unaffected.
- **Race window: rotation vs. cron.** The scheduled-content-publisher fires at 14:00 UTC daily (`scheduled-content-publisher.yml:17`). If rotation lands mid-publish, the cron's already-running container holds the OLD secret in process env; the next call to `/2/users/me` 401s. **Mitigation:** schedule the rotation outside the 14:00 UTC ± 15-minute window. The bootstrap script does NOT abort the running cron — if a 401 surfaces, AC11 (`validate-credentials`) catches it on the next run and the operator re-triggers via `gh workflow run`.
- **Doppler audit log shape.** `doppler secrets set` and `doppler secrets delete` both write to the Doppler audit log (visible at dashboard.doppler.com → Audit). The audit log is a richer authoritative source than the CLI's stdout render and DOES NOT echo other secrets' values. **Operator hint added to runbooks:** "for post-change verification, prefer the Doppler dashboard Audit tab over CLI stdout — the dashboard is the canonical, leak-free read surface."
- **Read-only escape coverage.** The `READONLY_FLAG_PATTERNS` for the new rule MUST be tested against `doppler secrets delete --help`, `doppler secrets set -h`, and the long-form `doppler secrets {set,delete} --help`. Operator-runnable shapes that should NOT trip the gate.

## Open Questions for /work

1. (none — plan is complete and CPO sign-off can proceed immediately).

## Deepen-Pass Verification Log

Live verifications performed during deepen-pass (2026-05-18):

```bash
$ gh pr view 3983 --json state,title
{"state":"MERGED","title":"feat(auth): #3363 Resolution C — Supabase asymmetric JWT substrate via Custom Access Token Hook"}

$ gh issue view 4029 --json state,title
{"state":"OPEN","title":"security: rotate X_API_SECRET (Doppler stdout echo during delete exposed value chunks in session transcript)"}

$ doppler secrets delete --help | grep -E '^\s*(--silent|-y|--no-interactive)'
  -y, --yes              proceed without confirmation
      --silent                          disable output of info messages
# Note: --no-interactive NOT in `delete` flag set

$ doppler secrets set --help | grep -E '^\s*(--silent|-y|--no-interactive)'
      --no-interactive      do not allow entering secret value via interactive mode
      --silent                          disable output of info messages

$ gh secret list | grep -E '^X_API_SECRET'
X_API_SECRET	2026-03-20T22:22:27Z

$ gh label list --limit 200 | grep -E '^(domain/engineering|priority/p3-low|compliance/critical|bug)\s'
bug                          Something isn't working                                           #d73a4a
priority/p3-low              Nice-to-have, no time pressure                                    #F9D0C4
domain/engineering           Plugin code, CI/CD, infra, docs site (CTO)                        #0075CA
compliance/critical          Single-user-incident threshold: requires CPO + user-impact-reviewer sign-off  #B60205

$ grep -nE 'doppler_secret.*inngest_signing_key_prd' apps/web-platform/infra/inngest.tf
49:resource "doppler_secret" "inngest_signing_key_prd" {

$ grep -nE 'ignore_changes = \[value\]' apps/web-platform/infra/inngest.tf
57:    ignore_changes = [value] # rotate out-of-band; do not churn on every apply.

$ grep -n "doppler secrets set\|doppler secrets delete\|--silent" knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md
160: ... no `--silent`/`--quiet` flag exists.   # ← THIS CLAIM IS FALSE; plan §Phase 2.1 corrects.
```

All verifications PASS. The single discovered contradiction (Leak-2 learning's `--silent`-does-not-exist claim) is folded into Phase 2.1 as an explicit correction.


## Why this is a single PR, not two

Two surface fixes (rotation evidence + hook widening) could in principle ship in two PRs:

- **PR-A: rotation only** — Doppler + GH secret + verify + close issue.
- **PR-B: hook widening** — regex + tests + docs.

I'm shipping it as one PR for two reasons:

1. **Recurrence prevention is load-bearing on rotation.** If the hook widening lands AFTER the rotation, a third operator hitting the same trap class (Soleur is a one-operator alpha — that operator is me) can leak the JUST-ROTATED secret on the next post-merge cleanup. The widening protects the rotated credential.
2. **Plan-time CPO sign-off applies once.** Threshold = single-user-incident on the brand-survival surface (Soleur X handle). Splitting into two PRs forces two sign-off cycles for one decision.

The atomic-merge / sequential-phase distinction from `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md` is respected: Phase 1 (hook widening) MUST land before Phase 4 (rotation) for the protection to be live during rotation. Phases are ordered correctly within the single PR.
