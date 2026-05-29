---
title: "infra: extend apply-sentry-infra.yml auto-apply to sentry_uptime_monitor.*"
type: infra
issue: 4585
branch: feat-one-shot-4585-sentry-uptime-autoapply
date: 2026-05-29
lane: single-domain
status: draft
related:
  - knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md
  - knowledge-base/project/plans/2026-05-29-fix-reconcile-cf-sentry-iac-apex-canonical-plan.md
---

# infra: extend apply-sentry-infra.yml auto-apply to `sentry_uptime_monitor.*`

🛠️ Infrastructure / CI change. Spun out of #4577 (reconcile CF/Sentry IaC to apex canonical) as deferred follow-up #4585. Ref #4577, #4578.

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Overview, Research Reconciliation, Acceptance Criteria, Risks (precedent diff added)
**Verification done (live, this pass):**

- **PR/issue citations resolved live:** #4577 (issue — CF/Sentry apex-canonical reconcile), #4578 (PR — parent one-shot), #4585 (this issue), #4220 (PR — env-reviewer gate removal), #4419/#4420 (destroy-guard widening), #3814 (Sentry-as-IaC adopt). All match their narrative roles.
- **Rule IDs verified active in AGENTS.md/sidecars:** `hr-exhaust-all-automated-options-before`, `hr-all-infrastructure-provisioning-servers`, `hr-menu-option-ack-not-prod-write-auth`, `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-weigh-every-decision-against-target-user-impact`, `hr-observability-as-plan-quality-gate`.
- **KB citations resolve:** ADR-031, the import-only beta-provider learning, the #4577 sibling plan (all `[[ -f ]]` OK).
- **Negative claim verified — "apply step applies saved `tfplan`, no `-target=` re-enumeration":** confirmed `terraform apply -auto-approve -input=false tfplan` at the apply step (no `-target`). This is the **saved-plan** pattern — `-target=` belongs in the *plan* step ONLY. AC1/AC2 grep expectations derive from this (per the #4201 saved-plan-vs-inline lesson).
- **Negative claim verified — "zero array-of-blocks on `sentry_uptime_monitor`":** all attrs scalar (`assertion_json` is a function-built string, not a block) → destroy-guard `nested_deletes: 0` stays correct, no jq clause needed.
- **Precedent diff (Phase 4.4):** `apply-github-infra.yml` is the byte-for-byte sibling — same saved-plan + destroy-guard + `[ack-destroy]`/`[skip-*]` gate shape. This change mirrors the established cron-monitor `-target=` allow-list pattern; no novel pattern.
- **Baseline test green pre-edit:** `tests/scripts/test-destroy-guard-counter-sentry.sh` → 5 passed / 0 failed (confirms AC6's comment-only edit cannot regress the gate).

### Key Improvements over the round-1 plan

1. Confirmed the saved-plan architecture so AC1 (4 uptime `-target=` in plan step) and AC2 (apply step references `tfplan`, NOT a re-listed subset) are correctly scoped — this is the exact #4201 drift class (saved-plan vs inline-apply `-target=` placement).
2. Locked the destroy-guard decision: **no jq change**, comment-only — backed by the empirical scalar-attr grep, not assertion.
3. Pinned the post-merge verification (AC10/AC11) to API-GET probes (`gh run` + Sentry monitors API), satisfying `hr-no-dashboard-eyeball-pull-data-yourself`.

### New Considerations Discovered

- The `paths:` trigger must include `uptime-monitors.tf` OR a future uptime-only edit would silently not auto-apply (the exact gap this PR closes) — captured as AC3.
- The first auto-apply may be a *create* (if monitors were never operator-applied) — verified safe against the destroy-guard (0 destroy on create). Captured in Test Scenarios.

## Overview

`.github/workflows/apply-sentry-infra.yml` currently auto-applies **only** `sentry_cron_monitor.*` resources on push-to-`main` (17 explicit `-target=` flags). The 4 `sentry_uptime_monitor.*` resources in `apps/web-platform/infra/sentry/uptime-monitors.tf` are NOT auto-applied — they require a manual operator `terraform apply` against the Sentry root after merge.

This split forced #4577 to be cut into a CI-auto-applied half (`seo-rulesets.tf`) and an operator-applied half (`uptime-monitors.tf`) purely because uptime monitors fall outside the auto-apply allow-list. Per `hr-exhaust-all-automated-options-before` and `hr-all-infrastructure-provisioning-servers`, each uptime-monitor edit needing a hand-run `terraform apply` is an avoidable operator step.

**Fix:** add the 4 `sentry_uptime_monitor.*` resources to the workflow's plan/apply `-target=` allow-list (mirroring the cron-monitor pattern), add `uptime-monitors.tf` to the `paths:` trigger, and update the now-stale "cron monitors only" naming/comments. The destroy-guard, the `[ack-destroy]`/`[skip-sentry-apply]` gates, the audit-gate, and the auth/backend wiring all already cover any resource in this root — no new infrastructure is introduced.

### The 4 target resources (verified against `apps/web-platform/infra/sentry/uptime-monitors.tf`)

| Resource address | name | assertion |
|---|---|---|
| `sentry_uptime_monitor.soleur_apex` (line 54) | `soleur-ai-apex` | 2xx |
| `sentry_uptime_monitor.soleur_www` (line 73) | `soleur-ai-www` | equals 301 |
| `sentry_uptime_monitor.soleur_changelog_deep` (line 103) | `soleur-ai-changelog-deep` | 2xx |
| `sentry_uptime_monitor.soleur_acme_probe` (line 164) | `soleur-ai-acme-carveout-probe` | equals 404 |

The issue body's 4 target names match the `.tf` file byte-for-byte (verified via `grep -nE 'resource "sentry_uptime_monitor"'`).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / PR #4578 body) | Reality (verified in repo) | Plan response |
|---|---|---|
| Workflow auto-applies `sentry_cron_monitor.*` only via explicit `-target=` | Confirmed: 17 `-target=sentry_cron_monitor.*` flags at lines 178–194; zero `uptime` references in the workflow | Add 4 `-target=sentry_uptime_monitor.*` flags after the cron block |
| 4 uptime resources named `soleur_apex/www/changelog_deep/acme_probe` | Confirmed at uptime-monitors.tf lines 54/73/103/164 | Use these exact addresses |
| Destroy-guard / drift-probe coverage must extend to new targets | Destroy-guard filter (`destroy-guard-filter-sentry.jq`) is resource-type-agnostic for `resource_deletes` (walks all `.resource_changes[]` with `delete` action) and hard-codes `nested_deletes: 0` | No filter code change needed — see Sharp Edges nested-block analysis. Update the filter's CURRENT SCOPE comment to name uptime monitors. |
| `sentry_uptime_monitor` is beta (v0.15.0-beta2) | Confirmed in `.terraform.lock.hcl` (`version = "0.15.0-beta2"`) and uptime-monitors.tf BETA STATUS comment | No version change; `terraform init -lockfile=readonly` already pins it |

### Nested-block reality check (destroy-guard)

Every attribute in `uptime-monitors.tf` is **scalar** — `organization`, `project`, `name`, `environment`, `url`, `method`, `interval_seconds`, `timeout_ms`, `downtime_threshold`, `recovery_threshold`, `assertion_json` (a string built by the `provider::sentry::assertion(...)` function — NOT an HCL block), and `description`. There are **zero array-of-blocks**. This is the same shape `sentry_cron_monitor` has (`schedule = {...}` is an object-attribute, not a block). Therefore the destroy-guard filter's `nested_deletes: 0` posture remains correct for uptime monitors; removing an uptime monitor is a resource-level delete already caught by `resource_deletes`. **No `select(.type == "sentry_uptime_monitor")` clause is required** — only a comment update to record that the scope now includes uptime monitors.

Verification commands at /work time:
```bash
grep -oE '^\s+[a-z_]+\s*=' apps/web-platform/infra/sentry/uptime-monitors.tf | sed 's/[[:space:]=]//g' | sort -u
# Expect: all scalar attrs above; no `{` block openers on their own line.
```

## User-Brand Impact

**If this lands broken, the user experiences:** if the auto-apply mis-targets or the destroy-guard mis-counts, a `terraform apply` could *delete* a live uptime monitor — the apex / www-redirect-health / changelog-deep / ACME-carve-out alerting goes silent. The next cert-renewal or canonicalization regression (the 2026-05-18 cert-outage shape) would then page nobody, and `soleur.ai` could 526/4xx for hours before a human notices. The monitors are the "hear about it before the next renewal fails" layer.

**If this leaks, the user's data is exposed via:** N/A — no PII, auth, payments, or regulated-data surface. The workflow already handles the Sentry IaC auth token (`SENTRY_IAC_AUTH_TOKEN`, GH repo secret) and R2 backend creds (Doppler `prd_terraform`); this change adds no new secret and no new credential path.

**Brand-survival threshold:** aggregate pattern. (Reason: a regression degrades alerting coverage / SEO-redirect health over time; it is not a single-user data exposure. Threshold `none` would be wrong because the apex-down blind-spot has brand impact, but it is observability-of-an-aggregate, not per-user.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — targets added.** `apply-sentry-infra.yml` "Terraform plan" step contains all 4 `-target=sentry_uptime_monitor.{soleur_apex,soleur_www,soleur_changelog_deep,soleur_acme_probe}` flags in addition to the 17 existing cron targets. Verify:
  ```bash
  grep -cE '^\s*-target=sentry_uptime_monitor\.' .github/workflows/apply-sentry-infra.yml   # == 4
  grep -cE '^\s*-target=sentry_cron_monitor\.'   .github/workflows/apply-sentry-infra.yml   # == 17 (unchanged)
  ```
- [ ] **AC2 — apply targets the same set.** If the apply step re-lists targets, it MUST match the plan step (it currently applies the saved `tfplan`, so adding targets to plan is sufficient — confirm the apply step still does `terraform apply ... tfplan` and was NOT changed to re-enumerate a stale subset). Verify the apply step references `tfplan` (the `-out` artifact) so the apply set == the plan set:
  ```bash
  grep -A4 'name: Terraform apply' .github/workflows/apply-sentry-infra.yml | grep -q 'tfplan'   # exit 0
  ```
- [ ] **AC3 — paths trigger extended.** The `paths:` block fires on `apps/web-platform/infra/sentry/uptime-monitors.tf`:
  ```bash
  grep -q 'apps/web-platform/infra/sentry/uptime-monitors.tf' .github/workflows/apply-sentry-infra.yml   # exit 0
  ```
- [ ] **AC4 — stale naming updated.** No remaining "(cron monitors only)" / "cron monitors only" claims that are now false. The `name:` field, the "Terraform plan (...)" step name, the "Terraform apply (...)" step name, and the Post-apply summary header are updated to reflect cron + uptime (e.g., "cron + uptime monitors"). Verify no false-scope literal survives:
  ```bash
  grep -nE 'cron monitors only|\(cron monitors\)' .github/workflows/apply-sentry-infra.yml   # zero matches OR only in historical-context comments explicitly scoped to the cron block
  ```
- [ ] **AC5 — destroy-guard filter comment updated.** `tests/scripts/lib/destroy-guard-filter-sentry.jq` CURRENT SCOPE comment names `sentry_uptime_monitor.*` as in-scope and documents that uptime monitors expose zero array-of-blocks (so `nested_deletes: 0` stays correct). No change to the jq expression itself.
- [ ] **AC6 — destroy-guard test still green.** `bash tests/scripts/test-destroy-guard-counter-sentry.sh` passes (the filter logic is unchanged; this confirms the comment edit did not break the jq parse).
- [ ] **AC7 — workflow lints clean.** `actionlint .github/workflows/apply-sentry-infra.yml` passes; embedded `run:` shell parses (`bash -n` on each extracted `run:` snippet, NOT on the YAML file).
- [ ] **AC8 — destroy-guard re-capture note extended.** The `test-destroy-guard-counter-sentry.sh` header's "Re-capturing baseline" command block adds the 4 `-target=sentry_uptime_monitor.*` flags so a future operator re-capture mirrors the workflow's actual target set. (Documentation accuracy; the committed fixtures themselves need no change since the filter logic is unchanged.)
- [ ] **AC9 — full suite green.** Project test suite (`package.json scripts.test` / the repo's canonical runner) passes.

### Post-merge (automated by the pipeline — no operator action)

- [ ] **AC10 — first auto-apply runs.** On merge to `main`, `apply-sentry-infra.yml` fires (the merge touches `apply-sentry-infra.yml` + `uptime-monitors.tf` paths). The "Terraform plan" step now includes the 4 uptime targets; the apply applies them. Verify via the workflow run log + post-apply summary.
  - **Automation:** `gh run list --workflow=apply-sentry-infra.yml --limit 1` + `gh run view <id> --log` — feasible, bake into /soleur:ship post-merge verification.
- [ ] **AC11 — monitors live in Sentry (API-GET, not dashboard).** Per `hr-no-dashboard-eyeball-pull-data-yourself`, confirm the 4 uptime monitors exist post-apply via the Sentry monitors API. Reuse the audit script's org-wide monitors GET (`GET /api/0/organizations/${SENTRY_ORG}/monitors/`) and grep for the 4 slugs (`soleur-ai-apex`, `soleur-ai-www`, `soleur-ai-changelog-deep`, `soleur-ai-acme-carveout-probe`).
  - **Automation:** API-GET feasible; if run locally needs `SENTRY_IAC_AUTH_TOKEN` from the GH repo secret (not Doppler). Document as a /soleur:ship post-merge probe.

## Implementation Phases

### Phase 0 — Preconditions (read + grep, no edits)

1. Re-confirm the 4 resource addresses: `grep -nE 'resource "sentry_uptime_monitor"' apps/web-platform/infra/sentry/uptime-monitors.tf`.
2. Confirm no nested blocks: `grep -oE '^\s+[a-z_]+\s*=' apps/web-platform/infra/sentry/uptime-monitors.tf | sed 's/[[:space:]=]//g' | sort -u` — all scalar (no own-line `{`).
3. Confirm the apply step applies the saved `tfplan` (so plan-targets == apply-targets) — read lines around "Terraform apply (cron monitors only)".
4. Confirm `actionlint` is available (`command -v actionlint`); if absent, fall back to `bash -n` on extracted `run:` snippets + a YAML parse via the repo's existing workflow-lint convention.

### Phase 1 — Workflow target + trigger edits (`.github/workflows/apply-sentry-infra.yml`)

1. **`paths:` block** (after line 39, alongside `cron-monitors.tf`): add `- "apps/web-platform/infra/sentry/uptime-monitors.tf"`. Keep the existing `destroy-guard-filter-sentry.jq` defense-in-depth path.
2. **"Terraform plan" step** (after the last cron `-target=` at line 194, before `-no-color -input=false -out=tfplan`): add the 4 lines:
   ```
   -target=sentry_uptime_monitor.soleur_apex \
   -target=sentry_uptime_monitor.soleur_www \
   -target=sentry_uptime_monitor.soleur_changelog_deep \
   -target=sentry_uptime_monitor.soleur_acme_probe \
   ```
3. **Naming/comments** (AC4): update line 33 `name:`, line 164 step name, line 239 step name, line 257 summary header, and the file-header comment lines 1–15 to read "cron + uptime monitors" (or equivalent). Keep historical-context comments that are explicitly about the cron rollout intact; only fix the literal "cron monitors only" scope claims that are now false.

### Phase 2 — Destroy-guard comment sync (`tests/scripts/lib/destroy-guard-filter-sentry.jq`)

1. Update the CURRENT SCOPE comment block: change "targets only `sentry_cron_monitor.*` resources" to name both cron and uptime monitors, and add one sentence: "`sentry_uptime_monitor` exposes ZERO array-of-blocks (all attrs scalar incl. `assertion_json` string), so `nested_deletes: 0` remains correct; an uptime-monitor removal is a resource-level delete caught by `resource_deletes`."
2. **Do NOT** add a `select(.type == "sentry_uptime_monitor")` clause or `walk()` — the EXTENDING THIS FILTER note explicitly forbids `walk()` and only requires a per-type clause when a resource type introduces a nested array-of-blocks; uptime monitors do not.

### Phase 3 — Test re-capture note sync (`tests/scripts/test-destroy-guard-counter-sentry.sh`)

1. In the header "Re-capturing baseline" command block, append the 4 `-target=sentry_uptime_monitor.*` flags to the `terraform plan` example so the documented re-capture mirrors the workflow's real target set (AC8). Logic + committed fixtures unchanged.

### Phase 4 — Verify

1. Run AC1–AC9 verification commands.
2. `bash tests/scripts/test-destroy-guard-counter-sentry.sh`.
3. `actionlint .github/workflows/apply-sentry-infra.yml`.
4. Full suite.

## Test Scenarios

- **Auto-apply fires on uptime edit:** a future PR that edits only `uptime-monitors.tf` now triggers `apply-sentry-infra.yml` (previously: no trigger → silent operator gap). Covered by AC3 + AC10.
- **Destroy-guard trips on uptime delete:** removing a `sentry_uptime_monitor` block produces `resource_deletes ≥ 1` → guard requires `[ack-destroy]`. Covered structurally by the resource-type-agnostic `resource_deletes` walk; AC6 confirms the filter still parses. (No new fixture needed — the existing `tfplan-sentry-resource-delete.json` exercises the resource-level delete path identically.)
- **No false destroy on in-place uptime edit:** editing an assertion (`assertion_json` string) is an in-place `update`, not a delete → guard not tripped. This is the #4578 `soleur_www` 2xx→301 shape; matches the cron-monitor in-place behavior.
- **First apply create-vs-noop:** if the 4 uptime monitors were never operator-applied, the first auto-apply is a *create* (0 destroy → guard passes). If already applied (via #4578's pipeline), it is a no-op/in-place. Both pass the destroy-guard. AC10/AC11 confirm end state regardless.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a CI/infrastructure-tooling change that widens an existing auto-apply allow-list to 4 already-defined Terraform resources. No user-facing surface, no new data processing, no schema/auth/API change. (Engineering/CTO is the owning domain; the change is single-domain per `lane: single-domain`.)

## Infrastructure (IaC)

This change modifies the **apply path** of an existing IaC pipeline; it introduces no new infrastructure resource (the 4 uptime monitors already exist in `uptime-monitors.tf`). It is the *opposite* of a `hr-all-infrastructure-provisioning-servers` violation — it removes a manual operator `terraform apply` step and routes it through the existing CI auto-apply.

### Terraform changes

None to the `.tf` resource definitions in this PR. The only `.tf`-adjacent edits are: (a) the workflow `-target=` allow-list, (b) a comment in `destroy-guard-filter-sentry.jq`. Providers/version pins unchanged (`jianyuan/sentry 0.15.0-beta2`, pinned in `.terraform.lock.hcl`, enforced by `terraform init -lockfile=readonly`).

### Apply path

**Chosen path:** CI auto-apply on push-to-`main` (existing `apply-sentry-infra.yml`), now scoped to cron + uptime monitors. The PR merge IS the human authorization (per ADR-031 + `hr-menu-option-ack-not-prod-write-auth`); no `environment:` reviewer gate (removed in PR #4220). Blast-radius: ≤4 uptime monitors + 17 cron monitors, all `-target=`-scoped — the apply cannot touch `sentry_issue_alert.*` (still import-only) or any out-of-target resource. Expected downtime: none (monitor create/update is non-disruptive).

### Distinctness / drift safeguards

- **Destroy-guard:** `terraform show -json | jq -f destroy-guard-filter-sentry.jq` → trips on any `delete` action unless `[ack-destroy]` is on its own line in the merge commit. Now implicitly covers uptime monitors (resource-type-agnostic `resource_deletes`).
- **Kill switch:** `[skip-sentry-apply]` on its own line skips the apply.
- **Audit-gate:** `sentry-monitors-audit.sh` 4-gate destination-controllability check runs BEFORE `terraform plan` — fail-closed, already org-wide (not cron-scoped), no change needed.
- **`-lockfile=readonly`:** refuses a re-published beta provider checksum not already in the committed lockfile.
- **State storage:** R2-backed remote state (creds from Doppler `prd_terraform`); apply state holds the Sentry token — unchanged from current posture.
- **`dev != prd`:** N/A — Sentry IaC has a single prd org target; no dev mirror for this root.

### Vendor-tier reality check

`sentry_uptime_monitor` is a **beta** resource (v0.15.0-beta2). Uptime monitors are a paid Sentry feature, but the resources already exist in code and (per #4578) were applied at least once via the operator/pipeline path — so the org tier already supports them. This change only moves *where* the apply runs (CI vs. operator laptop), not *whether* the tier allows the resource. No `count = var.*_paid_tier ? 1 : 0` gate is needed (unlike the `betteruptime_policy` free-tier case) because the resources are unconditionally defined today.

## Observability

```yaml
liveness_signal:
  what: "apply-sentry-infra.yml workflow run + Post-apply summary (GITHUB_STEP_SUMMARY) on every push-to-main touching uptime-monitors.tf"
  cadence: "on merge (event-driven, not scheduled)"
  alert_target: "GitHub Actions run status; a failed apply surfaces as a red workflow run on main"
  configured_in: ".github/workflows/apply-sentry-infra.yml (Post-apply summary step, if: always())"
error_reporting:
  destination: "GitHub Actions job log + ::error:: annotations (destroy-guard trip, plan failure, missing-secret guard); workflow failure on main is the loud signal"
  fail_loud: true
failure_modes:
  - mode: "destroy-guard trips (uptime monitor would be deleted without [ack-destroy])"
    detection: "terraform show -json | jq destroy-guard-filter-sentry.jq → resource_deletes > 0"
    alert_route: "::error:: annotation + non-zero exit → red workflow run on main"
  - mode: "terraform plan/apply fails against beta provider (schema drift on provider bump)"
    detection: "rc capture in plan step; terraform apply non-zero"
    alert_route: "::error::terraform plan failed → red workflow run"
  - mode: "uptime monitor silently absent post-apply (apply skipped via kill switch, or target typo)"
    detection: "AC11 API-GET probe (GET /api/0/organizations/${SENTRY_ORG}/monitors/) greps for the 4 slugs"
    alert_route: "post-merge /soleur:ship probe; absence → operator follow-up"
logs:
  where: "GitHub Actions run logs for apply-sentry-infra.yml; per-run STEP_SUMMARY"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: "gh run list --workflow=apply-sentry-infra.yml --limit 1 --json conclusion,headSha && gh api /repos/:owner/:repo/actions/workflows/apply-sentry-infra.yml/runs --jq '.workflow_runs[0].conclusion'"
  expected_output: "most-recent run conclusion == success after a merge that touches uptime-monitors.tf"
```

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
# Probe each planned file against open code-review issue bodies (standalone jq --arg):
for p in \
  ".github/workflows/apply-sentry-infra.yml" \
  "tests/scripts/lib/destroy-guard-filter-sentry.jq" \
  "tests/scripts/test-destroy-guard-counter-sentry.sh"; do
  jq -r --arg path "$p" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```
Run at /work Phase 0. Record matches here with a Fold-in / Acknowledge / Defer disposition. If zero matches: **None**.

## Files to Edit

- `.github/workflows/apply-sentry-infra.yml` — add 4 `-target=sentry_uptime_monitor.*` flags to the plan step; add `uptime-monitors.tf` to `paths:`; fix "cron monitors only" naming in `name:`, two step names, summary header, file-header comments.
- `tests/scripts/lib/destroy-guard-filter-sentry.jq` — CURRENT SCOPE comment update (name uptime monitors + zero-nested-block note). No jq-expression change.
- `tests/scripts/test-destroy-guard-counter-sentry.sh` — re-capture-baseline command-block note: append 4 uptime `-target=` flags (documentation accuracy). No test-logic change.

## Files to Create

- None.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Add a `select(.type == "sentry_uptime_monitor")` clause to the destroy-guard filter | Rejected — uptime monitors have zero array-of-blocks, so `resource_deletes` already covers them; the filter's own EXTENDING note says add a clause only for a new nested-block-bearing type. Adding a no-op clause would be dead code. |
| Drop the `-target=` allow-list and apply the whole Sentry root | Rejected — `sentry_issue_alert.*` is import-only (operator import-then-apply per `issue-alerts.tf`); an unscoped apply would try to create/destroy them. The `-target=` allow-list is load-bearing. |
| Re-enumerate targets in the apply step too | Rejected — the apply step applies the saved `tfplan` artifact, so plan-targets == apply-targets automatically. Re-enumerating would create a drift surface. (Confirm in Phase 0.) |

## Risks & Mitigations

- **Beta-provider schema drift on a future bump.** `sentry_uptime_monitor` is v0.15.0-beta2; an `init -upgrade` could rename `assertion_json` or threshold attrs. Mitigation: `-lockfile=readonly` + committed lock pin freeze the version; the uptime-monitors.tf BETA STATUS comment already mandates re-validation on bump. Out of scope for this PR (no version change). Precedent: the same beta-provider config-time validation trap is documented at `knowledge-base/project/learnings/2026-05-15-terraform-import-only-beta-provider-schema-validation.md` (applies to `sentry_issue_alert`, not uptime monitors, which are create-managed with no empty-list-block requirement).
- **First auto-apply is a *create* if monitors were never operator-applied.** 0-destroy → guard passes; safe. If already applied, no-op/in-place. Either way safe (Test Scenarios).
- **Naming-edit over-reach.** Risk of rewriting a historical-context comment that should stay cron-specific. Mitigation: AC4 grep targets only false-scope literals; preserve cron-rollout history comments verbatim.

### Precedent diff (Phase 4.4 — pattern-bound CI behavior)

The auto-apply `-target=` allow-list + destroy-guard + ack/skip-gate shape is an **established, non-novel** pattern. The canonical sibling is `.github/workflows/apply-github-infra.yml` and this same file's existing cron-monitor block. Side-by-side:

| Aspect | `apply-github-infra.yml` (precedent) | `apply-sentry-infra.yml` cron block (precedent) | This change (uptime) |
|---|---|---|---|
| `-target=` placement | plan step only | plan step only (17 cron targets) | plan step only (+4 uptime targets) |
| apply step | `terraform apply ... tfplan` (saved-plan) | `terraform apply ... tfplan` (saved-plan) | unchanged (consumes same `tfplan`) |
| destroy-guard | `destroy-guard-filter-web-platform.jq` (has a `select(.type==...)` nested clause for `github_repository_ruleset`) | `destroy-guard-filter-sentry.jq` (`nested_deletes: 0`, no clause — cron has no blocks) | reuse sentry filter as-is (uptime has no blocks) |
| ack/skip gate | `[ack-destroy]` line-anchored | `[ack-destroy]` + `[skip-sentry-apply]` line-anchored | unchanged |

**Conclusion:** the pattern is established; the only delta is 4 added `-target=` lines + a `paths:` entry + comment sync. The github-infra filter DOES carry a nested-block clause (`github_repository_ruleset` has array-of-blocks) — that is the case the sentry filter's "EXTENDING THIS FILTER" note refers to, and uptime monitors are explicitly NOT that case (verified scalar-only). No precedent gap.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled with threshold `aggregate pattern`.)
- `assertion_json` is a **string attribute** produced by `provider::sentry::assertion(...)`, NOT an HCL block — do not mistake it for a nested block when reasoning about the destroy-guard. Verified: all uptime-monitor attrs are scalar.
- The apply step applies the saved `tfplan` — adding targets to the *plan* step is sufficient and the *only* correct place. Adding targets to a separate apply enumeration would risk plan/apply set drift. Confirm the apply step references `tfplan` at Phase 0 (AC2).
- Do NOT add `walk()` to `destroy-guard-filter-sentry.jq` — the filter explicitly forbids it; the path-specific-clause pattern is the contract, and uptime monitors need no clause at all.
- For `actionlint`: this is a **workflow** file (`on:` + `jobs:`), so `actionlint` is correct (unlike composite-action `action.yml` files where it emits spurious errors). Use `bash -c '<extracted run snippet>'` for embedded shell, NOT `bash -n` on the YAML.

## Deferred / Out of Scope

- Migrating to the unified `sentry_alert` beta resource (forbidden until provider GA per ADR-031 NG9).
- Changing the `sentry_issue_alert.*` import-only posture (separate concern; not requested).
- Provider version bump / re-validation (separate cycle; no version change here).
