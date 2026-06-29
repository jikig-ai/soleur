---
title: "feat: tenant-integration required-check shim"
type: feat
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5585
brainstorm: knowledge-base/project/brainstorms/2026-06-29-tenant-integration-required-shim-brainstorm.md
spec: knowledge-base/project/specs/feat-tenant-integration-required-shim/spec.md
branch: feat-tenant-integration-required-shim
pr: 5688
created: 2026-06-29
---

# feat: tenant-integration required-check shim ✨

Make `.github/workflows/tenant-integration.yml` (the dev-Supabase tenant-isolation
suite) a **required** merge gate that blocks PRs touching the tenant-isolation
surface, while staying a zero-cost green no-op for the ~95% of PRs that don't —
closing the gap that let #5582 sit red on `main`.

## Overview

The suite is the only authoritative live verification that one founder's JWT
cannot read another's `users` / repo / session-sync / email-triage rows. It is
path-filtered (`on.<event>.paths`) and not required, so a red run does not block
merges. Flipping it to required as-is fails: GitHub never reports a status
context for a workflow filtered out by `on.paths`, so the check sits
"Expected — Waiting" forever and blocks every unrelated PR.

**Solution (mirrors the repo's own `ci.yml` `test` aggregator idiom):** always
trigger the workflow; detect relevant paths in a cheap job; gate the heavy suite
on that detection; add an always-run `tenant-integration-required` gate job that
inspects **both** `needs.detect-changes.result` **and** `needs.tenant-integration.result`
and fails closed; register that gate job as a required status check in the
IaC-managed "CI Required" ruleset.

> **SpecFlow correctness note (DROP-1, fail-open).** The gate must inspect
> `detect-changes.result` too, not just `tenant-integration.result`. If
> `detect-changes` itself fails (git/checkout error, missing `origin/$BASE_REF`),
> GitHub marks the dependent heavy job `skipped` — and a gate that treats
> `skipped` as pass would green a run where the path-detection that decides
> whether to run the suite never executed. The gate passes **iff
> `detect-changes.result == 'success'` AND `tenant-integration.result ∈ {success,
> skipped}`**; everything else (including `detect-changes` ≠ success) fails. This
> is a divergence from `ci.yml`'s `test` job, whose dependencies are not a gating
> `detect-changes` — copying its shape verbatim would reintroduce the hole.

## Research Reconciliation — Brainstorm/Spec vs. Codebase

| Brainstorm/Spec claim | Codebase reality | Plan response |
|---|---|---|
| Register the required check via an "automated post-merge `gh api`" call (FR5). | The "CI Required" ruleset (id 14145388) is **Terraform-managed**: `infra/github/ruleset-ci-required.tf`, governed by **ADR-032**, auto-applied by `apply-github-infra.yml` on merge to `main` touching `infra/github/*.tf`. App-auth, no operator step. | **Supersede FR5.** Register by adding a `required_check` block to `ruleset-ci-required.tf` (`integration_id = var.actions_integration_id`). Merge auto-applies it. No `gh api` mutation, no post-merge operator step. |
| (Brainstorm Open Q2) confirm GitHub stores contexts as job-level check names. | Confirmed: all 14 contexts in the live ruleset are job names with `integration_id` 15368 (GitHub Actions); `CodeQL` alone pins 57789 (GHAS). | Context = `tenant-integration-required` (the gate **job** name), `integration_id = var.actions_integration_id` (15368). |
| Bot-synthetic blast radius not analyzed. | Bot/cron PRs (GITHUB_TOKEN) never trigger CI, so they post **synthetic** check-runs for required checks. `.github/actions/bot-pr-with-synthetic-checks/action.yml` **hardcodes** its list (`CHECK_NAMES=(test dependency-review e2e "skill-security-scan PR gate" enforce)`) — it does NOT read `required-checks.txt`; the two are hand-maintained duplicates. `lint-bot-synthetic-completeness.sh` scans only `.github/workflows/` and **exempts composite-action consumers**, so it is structurally blind to a missing `CHECK_NAMES` entry. | Edit `CHECK_NAMES` directly (Files-to-Edit) AND `required-checks.txt`; assert the action edit with its own grep (do NOT rely on the lint to catch it — see AC5). |
| Count-contract assumed to be an executable guard. | There is **no executable guard asserting the count is 14**. `test-destroy-guard-counter.sh` is **delete-only** (asserts `destroy_count == 0`); adding a 15th `required_check` is an *add* → it stays green with no edit. `apply-github-infra.yml` only *emits* `length`, doesn't assert it. The `14` lives only in **documentation**: ADR-032 (L49/136/140/247/253/257) + the `ruleset-ci-required.tf` header comment (L2-3, 12-13). | Update the doc `14`→`15` sites (ADR-032 + `.tf` header). Destroy-guard counter + fixture = **verify-only** (stay green). |

## User-Brand Impact

**If this lands broken, the user experiences:** a tenant-isolation regression
(one founder reading another's `users`/repo/session-sync/email-triage rows)
merges to `main` undetected, because the gate that should have blocked it was
either never required, or fails **open** (treats a skipped/failed suite as
success).

**If this leaks, the user's data is exposed via:** a fail-open shim — a gate job
that reports green when `needs.tenant-integration.result` is `failure`,
`cancelled`, or empty; or a path-detection miss that skips the suite on a PR that
actually touches the isolation surface.

**Brand-survival threshold:** single-user incident. (`requires_cpo_signoff: true`
— carried from brainstorm; `user-impact-reviewer` runs at PR review.)

## Files to Create

- _None._ (All changes edit existing files.)

## Files to Edit

**Definite:**

- `.github/workflows/tenant-integration.yml` — remove `on.push.paths` + `on.pull_request.paths`; add `detect-changes` job; gate the heavy `tenant-integration` job; add always-run `tenant-integration-required` gate job. detect-changes anchors = former `on.paths` **PLUS the workflow file itself** (anti-bypass, mirrors `ci.yml`). **This supersedes spec TR4** ("byte-identical to former `on.paths`"): the self-anchor is required so a PR weakening the gate logic still runs the suite.
- `infra/github/ruleset-ci-required.tf` — add a 15th `required_check { context = "tenant-integration-required"; integration_id = var.actions_integration_id }`.
- `scripts/required-checks.txt` — add `tenant-integration-required` under the "CI Required ruleset" block.

**Bot-synthetic coverage (corrected after SpecFlow + source verification — the brainstorm and first draft mis-scoped this):**

- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — **DEFINITE.** `CHECK_NAMES` is a **hardcoded array** (`=(test dependency-review e2e "skill-security-scan PR gate" enforce)`), NOT loaded from `required-checks.txt`. Add `tenant-integration-required`. This is the load-bearing path: it posts via the **Check-Runs API** (the action's own comment: "rulesets require Check Runs from integration_id 15368"). Both the real gate job and this synthetic run under integration_id 15368, so the `.tf` `required_check` needs no integration_id pin (unlike CodeQL/57789).
- `scripts/required-checks.txt` — **DEFINITE** (already listed above) — drives `lint-bot-synthetic-completeness.sh`; must land in the same PR as the `CHECK_NAMES` edit or the lint red-fails.
- `scripts/post-bot-statuses.sh` — **verify-only, likely NO edit.** It uses the **Statuses API**, which does NOT satisfy rulesets (they require Check-Runs). Confirm in Phase 0 whether any live bot path depends on it; do not add the context unless a real consumer needs it.

**Required-check set: canonical mirror (DEFINITE edit):**

- `scripts/ci-required-ruleset-canonical-required-status-checks.json` — **DEFINITE.** Canonical mirror / drift-audit source (340 B). Add the context (keeps `canonicalize-required-status-checks.sh` + the drift/bypass audit consistent).

**Doc `14`→`15` count sites (DEFINITE edits — these are where `14` actually lives):**

- `knowledge-base/engineering/architecture/decisions/ADR-032-...md` — count sites L49/136/140/247/253/257 **and** the always-run-gate-job pattern note (see Architecture Decision section).
- `infra/github/ruleset-ci-required.tf` header comment (L2-3, 12-13: "WIDENED from 5 to **14**", "the **14** context strings … are public ABI") → 15.

**Verify-only / NO edit (confirmed by Kieran against the codebase):**

- `tests/scripts/test-destroy-guard-counter.sh` + `tests/scripts/lib/destroy-guard-filter.jq` + `tests/scripts/fixtures/tfplan-real-ruleset-baseline.json` — **delete-only** guard; an *add* keeps it green. No edit.
- `scripts/create-ci-required-ruleset.sh` + `scripts/update-ci-required-ruleset.sh` — **frozen one-shot migration artifacts** (each scoped to the single check it originally added); appending here is wrong. No edit.
- `scripts/lib/canonicalize-required-status-checks.sh` (sorts/dedups, no count), `scripts/audit-ruleset-bypass.sh` / `tests/scripts/test-audit-ruleset-bypass.sh` (bypass actors unchanged). No edit.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` cross-referenced against every planned file path on 2026-06-29 — zero matches.)

## Implementation Phases

### Phase 0 — Confirm the (already-verified) edit set (read-only)

The Files-to-Edit list was verified at plan time (SpecFlow + 4 reviewers). Phase 0
is a fast re-confirm, not open discovery:

1. Confirm `test-destroy-guard-counter.sh` is delete-only (no count-of-14 assertion) → no edit; confirm `create/update-ci-required-ruleset.sh` are frozen one-shots → no edit.
2. Confirm `CHECK_NAMES` in `bot-pr-with-synthetic-checks/action.yml` is still hardcoded and `lint-bot-synthetic-completeness.sh` still exempts composite-action consumers (so the action edit needs its own grep gate, not the lint).
3. Read ADR-032 `## Decision` + `## Sharp Edges` (job-name contract) to confirm the amendment shape; enumerate the `14` doc sites.

### Phase 1 — Workflow shim (`tenant-integration.yml`)

1. Remove `on.push.paths` and `on.pull_request.paths`; keep `on.push.branches:[main]`, `on.pull_request.branches:[main]`, `workflow_dispatch`.
2. Add `detect-changes` job mirroring `ci.yml:40-69`: `fetch-depth: 0`; on non-PR events short-circuit `tenant=true`; else `git diff --name-only origin/$BASE_REF...HEAD` grep the anchors (tenant-isolation tests, `apps/web-platform/server/**`, `apps/web-platform/supabase/migrations/**`, **and** `.github/workflows/tenant-integration.yml` itself). Pass `$BASE_REF` via `env:` quoted.
3. Gate the existing heavy job: `needs: detect-changes`, `if: needs.detect-changes.outputs.tenant == 'true'`. No other change to its steps.
4. Add `tenant-integration-required` job: `needs: [detect-changes, tenant-integration]`, `if: always()`, single `run:` step reading BOTH `needs.detect-changes.result` and `needs.tenant-integration.result` via `env:` + quoted `"$VAR"`. **Allow-list predicate (not deny-list):** pass iff `detect-changes.result == 'success'` AND `tenant-integration.result` ∈ {`success`, `skipped`}; `exit 1` for everything else (so any future GitHub-added result state fails closed). Structure mirrors `ci.yml:401-428` `test`; the extra `detect-changes.result` clause is the DROP-1 divergence.
5. Keep `concurrency.cancel-in-progress: false` (no change from current) — see Risks R3.
6. Harden `detect-changes`: `set -uo pipefail`; a git/checkout error or missing `origin/$BASE_REF` must **fail the job** (→ gate fails closed per the predicate), never silently emit `tenant=false`. Do not let a `grep` no-match `|| true` swallow a git error.

### Phase 2 — Required-check registration (IaC) + count contracts

1. Add the `required_check` block to `ruleset-ci-required.tf` (Tier placement per file convention; comment citing the shim rationale + #5585). Update the file's header comment `14`→`15`.
2. Add `tenant-integration-required` to `scripts/required-checks.txt` and to `scripts/ci-required-ruleset-canonical-required-status-checks.json`.
3. Update the ADR-032 count sites `14`→`15` (Phase 4). No edit to the destroy-guard counter/fixture (delete-only; add stays green) or the frozen provisioning one-shots.
4. `cd infra/github && terraform fmt && terraform validate` (no apply — apply is the merge-triggered `apply-github-infra.yml`; `terraform plan` needs `prd_terraform` creds absent in the worktree).

### Phase 3 — Bot-synthetic blast-radius audit

1. Add `tenant-integration-required` to `CHECK_NAMES` in `.github/actions/bot-pr-with-synthetic-checks/action.yml` (the Check-Runs poster).
2. Run `bash scripts/lint-bot-synthetic-completeness.sh` locally. For every workflow it flags as missing the new synthetic, add the synthetic posting (or confirm it routes through the action). Paste the full audit list (every PR-creating workflow + its disposition) into the PR body per the required-check Sharp Edge — do not claim "only N" without the lint output.
3. `post-bot-statuses.sh` (Statuses API) is NOT a ruleset-satisfying path; only edit it if Phase 0 finds a live consumer that needs it.

### Phase 4 — ADR amendment

Amend ADR-032 per the Architecture Decision section.

### Phase 5 — Verification (pre-merge)

Run `bash scripts/test-all.sh` (destroy-guard + bot-synthetic completeness + fixture tests). Run `actionlint` on the workflow + `bash -c` on extracted `run:` snippets. Confirm `terraform fmt -check` + `terraform validate` green and the `grep -c required_check → 15` (AC4). `terraform plan` is NOT run in-worktree (needs `prd_terraform` creds); its one-added-resource diff is verified in the post-merge `apply-github-infra.yml` run (AC9).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `tenant-integration.yml` has no `paths:`/`paths-ignore:` under `on.push`/`on.pull_request`; `actionlint` passes; extracted `run:` snippets pass `bash -c`.
- **AC2.** `detect-changes` emits `tenant=false` for a diff touching none of the anchors and `tenant=true` for a diff touching any anchor (incl. the workflow file itself) and for non-PR events.
- **AC3.** `tenant-integration-required` uses `if: always()` (job level) and asserts **inside a `run:` step** (NOT job `if:`), reading BOTH results. Allow-list predicate: pass iff `detect-changes.result == 'success'` AND `tenant-integration.result ∈ {success, skipped}`; fail otherwise. Verified by a unit-style assertion over all five branches: (success+success)→pass, (success+skipped)→pass, (success+failure)→fail, (**detect-changes failure** → tenant skipped)→**fail** (DROP-1), (cancelled/empty)→fail.
- **AC4.** `ruleset-ci-required.tf` contains the `tenant-integration-required` `required_check` with `integration_id = var.actions_integration_id`; `terraform fmt -check` + `terraform validate` pass; `grep -c '^      required_check {' infra/github/ruleset-ci-required.tf` returns 15. Registration is via this `.tf` (+ canonical JSON) applied by `apply-github-infra.yml` — never `gh api`. (The `terraform plan` one-added-resource diff is asserted post-merge in AC9, where `prd_terraform` creds exist.)
- **AC5.** All THREE synthetic/registration sources contain `tenant-integration-required`, asserted by **direct grep** (the completeness lint is blind to the action — it scans only `.github/workflows/` and exempts composite-action consumers): `grep -q 'tenant-integration-required' scripts/required-checks.txt` AND `... .github/actions/bot-pr-with-synthetic-checks/action.yml` AND `... scripts/ci-required-ruleset-canonical-required-status-checks.json`. Additionally `bash scripts/lint-bot-synthetic-completeness.sh` exits 0. Phase 3 audit list pasted in PR body.
- **AC6.** The `14` count is updated to `15` at every documentation site (ADR-032 L49/136/140/247/253/257 + the `ruleset-ci-required.tf` header comment); `grep -rn '\b14\b' <those sites>` shows none referring to the required-check count. `bash scripts/test-all.sh` exits 0 (destroy-guard counter unchanged — an add is not a delete).
- **AC7.** A PR editing ONLY `tenant-integration.yml` computes `tenant=true` (anti-bypass self-anchor) and runs the suite — so the introducing PR itself runs a real green suite before the check becomes required.
- **AC8.** ADR-032 amended (count 14→15 + the always-run-gate-job pattern for path-filtered required checks). PR body uses `Closes #5585`.

### Post-merge (operator)

- **AC9.** `apply-github-infra.yml` runs on merge and applies the ruleset; the live ruleset (`gh api repos/jikig-ai/soleur/rulesets/14145388`) lists `tenant-integration-required` among required contexts. (Automated by the workflow — no operator action. Verify the run is green.)
- **AC10.** First subsequent unrelated PR (touching none of the anchors) reports `tenant-integration-required` **success** with the heavy job **skipped** and no Doppler/dev-Supabase call. (`Ref` only — verification, not a fix.)
- **AC11.** Registration cutover does not permanently block pre-existing open PRs: under `strict_required_status_checks_policy = true` they show "Expected — Waiting" until rebased onto post-merge `main`, which re-runs the workflow and produces the context (self-healing). Confirm by rebasing one open PR (and re-running any open bot PR so it re-posts the new synthetic). Push-to-`main` with a red suite reports `tenant-integration-required` **failure** on `main`.

## Infrastructure (IaC)

### Terraform changes

- `infra/github/ruleset-ci-required.tf` — one added `required_check` block. Provider: `integrations/github` (App-auth, installation 122213433). Backend: R2 (`github/terraform.tfstate`). Sensitive vars unchanged (`github_app_id`, `github_app_private_key` from Doppler `prd_terraform`); no new variable.

### Apply path

Merge-triggered auto-apply via `apply-github-infra.yml` (`on.push.paths: infra/github/*.tf`). The PR merge IS the authorization (ADR-031/032, `hr-menu-option-ack-not-prod-write-auth`). In-place ruleset update — no taint/replace, no downtime. Kill switch `[skip-github-apply]` available if needed.

### Distinctness / drift safeguards

GitHub rulesets affect only the founder's repo (no dev/prd split). `strict_required_status_checks_policy = true` is preserved. The destroy-guard counter (Phase 0) prevents an accidental check-set shrink. No `lifecycle.ignore_changes` change.

### Vendor-tier reality check

N/A — GitHub rulesets carry no paid-tier gate for required-check count.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-032** (do not author a new ADR — this is within its branch-protection-as-IaC pattern). Two amendments, as in-scope plan tasks (Phase 4):

1. Required-check count 14 → 15 wherever ADR-032 enumerates it.
2. Add to `## Decision` (or a `## Amendments` note): `tenant-integration-required` is the **first path-filtered required check** — all prior 14 run unconditionally. The pattern for making a path-filtered workflow required without "Expected — Waiting" blocking is an **always-run aggregator gate job** (`if: always()` + `needs.*.result` inspection, fail-closed), mirroring `ci.yml`'s `test`. Record the job-name-contract sharp edge applies (renaming the gate job silently un-requires it).

### C4 views

**No C4 impact.** Checked all three model files (`model.c4`, `views.c4`, `spec.c4`): the model describes the product runtime (Claude Code, the workflow skills, the go-router, web-platform containers/stores), not CI/merge-gating — a required status check is no actor/system/store/access-relationship in it. Nothing to add or correct.

## Domain Review

**Domains relevant:** Engineering (carry-forward from brainstorm).

### Engineering

**Status:** reviewed (brainstorm carry-forward + plan-time CTO findings).
**Assessment:** Approach mirrors the proven `ci.yml` `test` + `detect-changes` idiom — no new pattern. Hardening baked into ACs: fail-closed predicate (`success`/`skipped` only), assert in `run:` not job `if:`, per-event `$BASE_REF` guard, IaC registration (not `gh api`), idempotent/atomic apply. CLO/CPO assessed **low-relevance** in brainstorm (no user-facing surface, no legal document, no product decision); threshold (`single-user incident`) carries forward. `requires_cpo_signoff: true` — satisfiable by brainstorm framing carry-forward; `user-impact-reviewer` is the load-bearing review-time gate.

### Product/UX Gate

Skipped — mechanical UI-surface scan of Files-to-Edit (`.yml`, `.tf`, `.txt`, `.sh`, ADR `.md`) matches no UI-surface term/glob. NONE.

## Observability

Skipped per Phase 2.9 trigger set — Files-to-Edit contains no code under `apps/*/server|src|infra` or `plugins/*/scripts`, and a CI merge-gate is not a runtime service. The gate's own observability is intrinsic: the required-check **status** is visible on every PR; `apply-github-infra.yml` failures surface as a red workflow run on `main` (and via `main-health-monitor.yml`); a fail-open regression is structurally prevented by AC3 (fail-closed predicate) + AC6 (count contract).

## GDPR / Compliance Gate

Trigger (b) fires (threshold = single-user incident), but the diff touches **no regulated-data surface** — no schema/migration/auth/API-route, no new processing activity, no data movement. The change gates a check that itself verifies tenant isolation; it processes no personal data. Determination: documented no-op (no `compliance/critical` finding to file).

## Risks & Sharp Edges

- **R1 (fail-open via detect-changes failure — DROP-1, all 4 reviewers + SpecFlow converged).** If `detect-changes` fails (git/checkout error, missing `origin/$BASE_REF`), the heavy job is `skipped`; a gate reading only `tenant-integration.result` would green a run where the path-detection never ran — on a PR that may touch the isolation surface. Mitigation: gate predicate also requires `detect-changes.result == 'success'` (Phase 1.4, AC3); diff step fails closed (Phase 1.6).
- **R1b (fail-open via job-level skip).** A job-level `if:` skip reports **no context** → reopens "Expected — Waiting". Mitigation: AC3 mandates `if: always()` + in-`run:` assertion.
- **R2 (bot-PR deadlock + lint blindness).** A required check the bot synthetic-poster doesn't produce deadlocks every GITHUB_TOKEN bot/cron PR, and `lint-bot-synthetic-completeness.sh` won't catch a missing `CHECK_NAMES` entry (it exempts composite-action consumers). Mitigation: edit `action.yml` `CHECK_NAMES` + assert by direct grep (AC5), not by the lint.
- **R2b (count-contract).** No executable guard pins the count at 14 (the destroy-guard is delete-only); the `14` is documentation. Mitigation: update ADR-032 + `.tf` header (AC6); no test/fixture edit needed.
- **R3 (concurrency).** Keep `cancel-in-progress: false` (decided — no change). Rationale: with `true`, a manual re-run race could cancel the gate/detect-changes job on the *head* SHA, concluding the required context `cancelled` (fail-closed, but blocks merge until re-run). `false` avoids that edge; the only cost is two full suites on rapid pushes to the same isolation-touching PR (rare). Because this is settled, there is no separate concurrency test scenario.
- **R4 (anti-bypass).** A PR editing only `tenant-integration.yml` (e.g. weakening the suite invocation) must still run the suite. Mitigation: include the workflow file in the detect-changes anchors (mirrors `ci.yml`'s `(ci|deploy-docs).yml` self-trigger anchor).
- **R5 (first-merge sequencing).** With `strict_required_status_checks_policy = true`, open PRs must rebase onto post-merge `main` before merging — that rebase re-runs CI, producing the new context. So same-PR atomic delivery (workflow + ruleset) is safe; the introducing PR itself is gated by the pre-merge 14-check ruleset and is unaffected.
- **R6 (`gh api` array form).** Not used here (IaC path), but if any verification prescribes `gh api` writes, use `--input -` heredoc, never `--field` (array→string 422), and re-read after write.
- **SE.** A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is complete.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | PR touching no anchors | `detect-changes`→`tenant=false`; heavy job `skipped`; `tenant-integration-required` **success**; no Doppler call |
| T2 | PR touching `apps/web-platform/server/**` + suite passes | heavy job `success`; gate **success** |
| T3 | PR touching anchors + suite **fails** | heavy job `failure`; gate **failure**; merge blocked |
| T4 | push to `main` | `tenant=true`; full suite runs (green-on-main signal) |
| T5 | PR editing only `tenant-integration.yml` | `tenant=true` (anti-bypass); suite runs |
| T6 | **`detect-changes` fails** (git/checkout error) | heavy job `skipped`; gate reads `detect-changes.result==failure` → **failure** (fail-closed, DROP-1) |
| T7 | bot/cron PR (GITHUB_TOKEN) | `CHECK_NAMES` synthetic check-run satisfies the ruleset (Check-Runs API, integration_id 15368) |
