---
title: "fix(ci): apply-sentry-infra red on main — derive the fidelity probe's reference from the Terraform source, not a live capture"
date: 2026-09-11
slug: fix-apply-sentry-infra-red-on-main
branch: feat-one-shot-8050-apply-sentry-infra-red-on-main
issue: 8050
closes: [8050]
type: fix
lane: cross-domain
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-09-11
**Sections enhanced:** Research Insights (premise verification), Phases 1–5, Guard Contract, Observability, Acceptance Criteria, Files to Create
**Research agents used:** verify-the-negative sweep (10 repo claims: 9 confirms, 1 not-applicable, 0 contradicts), post-edit self-audit, security-sentinel, test-design-reviewer, git-history-analyzer (15 citations: all resolve; attributions hold), best-practices-researcher (GitHub Actions expression semantics, Terraform JSON format), observability-coverage-reviewer. Earlier in the same pass: five-agent plan-review panel, CTO (blocking), CPO (sign-off), scoped `fable` advisor consult, learnings-researcher, repo-research-analyst, functional-discovery.

### Key Improvements
1. The plan's one load-bearing inference — trigger `logicType` derived from 31 captured rules — was falsified against the provider source (`resource_alert_impl.go` 803/835 hard-codes `any-short`) AND against a comment already in `issue-alerts.tf`; single-trigger rules now project a constant on both sides, closing a certain red-on-`main` on the first single-trigger threshold edit.
2. The apply job projects its reference from the plan it applies, so the committed copy has exactly one consumer (the daily job) and a stale copy can never red the apply job; the PR-time gate prints the expected file to the step summary and uploads it as an artifact.
3. The daily workflow's dead-man's switch is gated on `(verdict, filed)` with `!cancelled()`, and its CLOSER carries the matching `filed == 'true'` conjunct — without it the closer would have undone the new arm in the same run (deepen-pass P1).
4. Test design: a structural tf/live shape-parity row anchors the Terraform-side projection to real API data without a value ledger; every error row asserts a distinct literal; a G0 positive control makes the gate matrix non-vacuous; YAML-level mutation replaces `sed` for the workflow rows.

### New Considerations Discovered
- `terraform show -json` renders sensitive values in plaintext under `.values` (`sensitive_values` is a mask) — the projection now refuses any `sentry_alert` with a `true` sensitive leaf and any action kind outside `["email"]`.
- The apply job's plan step runs under re-armed `set -e`, so a post-command `rc=$?` branch would be dead code; the projection call uses `|| { ::error::; exit 1; }`.
- The probe step must not run when the plan step failed (no reference file → a misleading after-apply red); it is gated on `steps.plan.outcome == 'success'` and the filer body prints the Plan/Apply/Probe outcomes.
- `shape_ok` is shape, not cardinality, so the zero-rules floor stays reachable and testable.
- #7826's ADR note date (`2026-09-06`) is the commit date; the issue closed 2026-09-07 — the existing note is kept as written.

## Overview

The `Apply sentry infra` workflow has been red on `main` since merge `a583e7923159f9f4cef7fc7abd42ccd5a5e8a76a` (PR #7989, 2026-09-10 14:45 UTC, run 34491157462). The run log places the failure in step 15, `sentry_alert live fidelity (AC19/AC20)`, which runs `scripts/sentry-alert-live-fidelity.sh` AFTER `Terraform apply` (step 11, green) and after the AC17 state-vs-config check (step 14, green). The apply itself landed completely: the pre/post state forensics on that run show 28 → 29 `sentry_alert` resources, exactly the one rule PR #7989 added. Nothing is partial; live Sentry and Terraform state agree.

The probe failed because its reference is a committed live capture taken on 2026-09-09, before the new rule existed. It reported the new, Terraform-managed, correctly-applied rule as `UNMANAGED`. The same class fired once before (`git-data-boot-warning`, #7772 → #7985) and was patched by a name carve-out that was later deleted. The reference a post-apply probe compares against must be derived from the Terraform source, so that adding or editing a rule in the `.tf` cannot red `main` after the write. This plan makes that reference Terraform-derived — the apply job projects it from its own plan document, and the daily drift job reads a committed copy that a PR-time gate holds equal to the plan — fixes a sibling defect in the daily drift workflow that files a false "could not establish a verdict" issue on every drift verdict, and rolls forward by merging: the merge push re-fires the apply workflow with its own commit message, which is the only recovery gesture the issue permits.

Spec lacks valid `lane:` — no `knowledge-base/project/specs/<branch>/spec.md` exists for this one-shot branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Root Cause — read from the run log, not inferred

Run 34491157462 (`gh run view 34491157462 --json jobs`), job `apply`, per-step conclusions:

| # | Step | Conclusion |
|---|---|---|
| 9 | Terraform plan (full root) | success |
| 10 | Capture PRE-apply state (forensics) | success |
| 11 | **Terraform apply (cron + uptime monitors)** | **success** |
| 12 | Capture POST-apply state and sweep both for secret bytes | success |
| 13 | BYOK Art.33 detector liveness assertion (#4656 item 5) | success |
| 14 | AC17 — terraform state list matches the declared .tf (no orphan) | success |
| 15 | **sentry_alert live fidelity (AC19/AC20)** | **failure** |
| 16–20 | Upload forensics / file tracking issue / summary | success (17 filed #8050) |

The failing step's output, verbatim from the job log (job 102923475715):

```text
sentry_alert live fidelity: comparing 28 captured in-scope rule(s) against 29 live in-scope rule(s)
  UNMANAGED: 'ops-email-delivery-failure' is live and in scope but absent from the capture — created outside Terraform, or the capture is stale. Nothing in this repo manages it.
ERROR: sentry_alert live fidelity FAILED — 1 divergence(s) between live Sentry and the committed capture at .../knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase34-live-workflows-capture-2026-09-09.json.
```

**Partial-write determination (the issue's first triage question): the failure is AFTER `Terraform apply`, and the apply was COMPLETE, not partial.** Three independent readings agree:

1. Step 11 (`terraform apply -auto-approve -input=false tfplan`) exited 0.
2. Step 14 (AC17) compared `terraform state list` against the `.tf`-declared addresses and passed — no address declared-but-absent, no orphan.
3. The `sentry-forensics-state-34491157462` artifact (read-only, downloaded to the scratchpad): `sentry-state-pre.json` serial 123, 92 resources, 28 `sentry_alert`; `sentry-state-post.json` serial 124, 93 resources, 29 `sentry_alert`. The delta is exactly `sentry_alert.ops_email_delivery_failure`, the one block PR #7989 added to `apps/web-platform/infra/sentry/issue-alerts.tf`.

So the issue body's "DURING or AFTER → assume a partial write" branch does not describe this run. Live Sentry and Terraform state agree; what disagrees is the probe's **reference**, a snapshot of live Sentry taken two days earlier that was never — and could never be, pre-merge — updated for a rule that did not yet exist.

**Why the probe's own message is wrong here.** "created outside Terraform, or the capture is stale. Nothing in this repo manages it." — the first clause is false (AC17 proved Terraform manages it) and the third is false; only "the capture is stale" is true. The probe infers "managed" from the capture rather than from Terraform, which is the design defect, and the step's own comment in the workflow ("Immediately after `terraform apply` has written every Terraform-owned field from source, a divergence here cannot be config drift") only holds if the reference IS the source.

**Why the literal re-run the issue prescribes cannot go green.** The probe reads its reference from the checked-out tree (`REPO_ROOT/knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase34-live-workflows-capture-2026-09-09.json`). Re-running the failed job on run 34491157462 checks out `a583e79` again, whose capture lacks the rule, so the same `UNMANAGED` finding recurs deterministically and the filer re-comments on #8050. The roll-forward that DOES work is the one the issue's reasoning actually wants: a push to `main` carrying its own `head_commit.message`. This fix lives under `apps/web-platform/infra/sentry/**` (the new reference file, the README), which is inside the workflow's `paths:` filter, so merging it fires the apply workflow on the merge SHA with a full-root plan (no changes), a no-op apply, and the post-apply probe against a reference projected from that very plan. No `[ack-destroy]` is needed because this PR destroys nothing (an AC below asserts the PR plan's destroy count is 0). No `workflow_dispatch` of the apply workflow, no revert, no state restore — the issue's four prohibitions all hold.

### The sibling defect the same failure exposed (`scheduled-sentry-alert-drift.yml`)

The daily drift probe (run 34573504979, 2026-09-11 07:15 UTC) hit the same `UNMANAGED` finding and filed #8057 (correct: a drift verdict). It then ALSO filed #8058, "the drift probe could not establish a verdict", whose body literally reads `Verdict reached: drift`. Cause: the step "File or update the probe-unavailable issue" is gated `if: always() && failure()`, and the drift filer two steps above it ends with a deliberate `exit 1` on every drift verdict. `failure()` is therefore true on every drift run, and the dead-man's switch fires on the one class of run it was written to exclude. The "Close the probe-unavailable issue (a verdict was reached)" step that runs next found nothing to close: its `gh issue list` ran ~0.5 s after `gh issue create` and returned empty (read-after-write lag on the issues list), so #8058 stayed open. Both #8057 and #8058 are consequences of the two defects this plan fixes; they are closed by the drift workflow's own close steps on the first clean verdict (Phase 7.2), not by the PR body.

## Research Reconciliation — Issue/Docs vs. Codebase

| Claim (issue body, docs, or research agent) | Reality (measured) | Plan response |
|---|---|---|
| Issue #8050: "Failed DURING or AFTER `Terraform apply`: assume a partial write." | Apply green, AC17 green, forensics 28→29 exactly. Not partial. | Plan records the determination with the three readings above; no state work. |
| Issue #8050: "Re-run the failed job on THIS run. It is the only gesture that works." | Re-run checks out the same SHA whose capture lacks the rule → deterministic re-failure. | Roll-forward = merge of this fix (fires the push trigger with its own commit message). Re-running the old run is neither required nor useful; it is not prohibited, but it will red again and add noise to #8050. |
| Probe message: "UNMANAGED … created outside Terraform … Nothing in this repo manages it." | The rule is declared in `issue-alerts.tf` and present in state (AC17). | Reference becomes Terraform-derived; message rewritten so UNMANAGED means "not declared in the root". |
| Drift issue body: "The capture … is the authoring source for all 28 blocks … Re-capture it, regenerate with `phase2-generate-alert-blocks.py`" | The generator reads the **phase2** capture (hard-coded) and exits on `!= 27` in scope; it is a Phase 2 historical tool. Re-capturing from live is structurally impossible for a rule that is not yet applied (pre-merge). | Reference derives from `terraform show -json`; body text rewritten. Generator and both captures left untouched as history. |
| Plan v1 (this file, before review): "`triggers.logicType` is `any-short` iff the rule has more than one trigger condition" — inferred from 31 captured rules, 0 violations. | **Provider v0.15.7 hard-codes `OrganizationWorkflowTriggerLogicTypeAnyShort` in BOTH the create and the update request builders** (`internal/provider/resource_alert_impl.go` lines 803 and 835, read via `gh api …?ref=v0.15.7`). The 15 single-trigger rules read `all` only because they were imported and never PUT. The first `.tf` edit to a single-trigger rule would have made live `any-short`, the derived reference `all`, and the probe red on `main` again. | Single-trigger rules project `triggerLogicType` to the constant `single` on BOTH sides (one condition makes any/all identical); multi-trigger rules project `any-short` on the Terraform side and the real value on the live side, so a flip to `all` made outside Terraform still reports. Verified in Phase 0.6. |
| `apps/web-platform/infra/sentry/README.md` §Drift detection cites `phase2-live-workflows-capture-2026-09-04.json` | Both call sites were repointed to the phase34 file by #7988; README was not. | README section rewritten to the new reference path and regeneration recipe. |
| learnings-researcher: "the new resource must be added to `apply-sentry-infra.yml`'s `-target=` allow-list" (learning of 2026-06-12) | The workflow has been **full-root** since #6589; there is no allow-list (`apply-sentry-infra.yml` header, "FULL-ROOT PLAN"). | Stale learning; not acted on. Recorded here so it is not re-proposed at review. |
| `plan/SKILL.md` Phase 2.10: "back a no-C4-impact conclusion by a green `apps/web-platform/test/c4-count-parity.test.sh`" | No such file exists (`ls apps/web-platform/test/ | grep c4` lists 18 files, none count-parity). The C4 freshness gate that DOES exist is `plugins/soleur/test/c4-model-freshness.test.sh`, which byte-diffs the committed compiled `model.likec4.json`. | C4 impact assessed by reading `model.c4`/`views.c4`/`spec.c4`; the `sentry -> founder` edge prose is stale (27/3 split, "adoption capture") and is fixed in Phase 6 with `bash scripts/regenerate-c4-model.sh` so the compiled artifact stays fresh. |
| `scheduled-sentry-alert-drift.yml` body: "28 adopted `sentry_alert` rules" (hard-coded count) | Present at THREE sites (two issue bodies and the close-step comment); #7988's own commit message records this count being wrong "in four places". | Count removed from all three; derived wording ("every `sentry_alert` the root declares"). |
| #7997 (open): `sentry-alert-live-fidelity.sh:91` curl lacks `--disable`/`--noproxy '*'` and pins neither `$SENTRY_API_HOST` nor `$SENTRY_ORG`. | Confirmed: `python3 scripts/lint-shell-trace-credential-refusal.py scripts/sentry-alert-live-fidelity.sh` → 3 violations. The lint runs `--changed` in CI (`lint-bot-statuses`, non-required), so editing this script pulls them into scope. The script is also listed at line 71 of `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`. | Fold in the fidelity-script rows of #7997 (Phase 2) and remove the baseline line. The two `sentry-monitors-audit.sh` rows stay in #7997 (region-discovery design question). |

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 8050 --json state,closedByPullRequestsReferences` → OPEN, no closing PR. Premise holds.
- Merge SHA `a583e7923159f9f4cef7fc7abd42ccd5a5e8a76a` is PR #7989 (`git show --stat`); it added `sentry_alert.ops_email_delivery_failure` (+57 lines in `issue-alerts.tf`) and updated the README count to 29 + 2. Holds.
- Run 34491157462 exists, `event: push`, `conclusion: failure`, failing step is #15 (post-apply). Holds; the issue's "partial write" branch does not apply (see Root Cause).
- `scripts/sentry-alert-live-fidelity.sh`, the capture, both workflows, and the test suite exist at the cited paths on `origin/main`. Holds.
- The `terraform show -json` / state attribute shape for `sentry_alert` was **measured** from the run's own forensics artifact, not inferred from provider docs: each `trigger_conditions[]` / `action_filters[].conditions[]` / `actions[]` element carries exactly one non-null key (the live `type`), and `frequency_minutes`/`monitor_ids`/`logic_type`/`email{target_type,target_id,fallthrough_type}` map 1:1 onto the probe's projection fields. `planned_values.root_module.resources[].values` carries the same shape (Terraform JSON output format; the sibling gates in this workflow read `.change.after` in that shape).
- **Measured parity of the proposed mechanism (scratchpad, read-only):** projecting the real post-apply state through a draft `PROJECT_TF` and the committed capture through the probe's existing `PROJECT` gives **28 common rules compared, 0 mismatches**, once lifecycle triggers (`first_seen_event`, `reappeared_event`, `regression_event`, `issue_resolved_trigger`) are normalised to `comparison: true` (live) from `{}` (provider) and `triggers.logicType` is handled as in the Reconciliation row above. The projection then yields the 29th rule (`ops-email-delivery-failure`) in its authored shape. This is the load-bearing evidence that a Terraform-derived reference reproduces the capture without laundering anything.
- **Provider constant (from review, verified twice):** `resource_alert_impl.go` at tag v0.15.7 sets trigger `LogicType` to `AnyShort` in both create (line 803) and update (line 835); and the repo already records it — `apps/web-platform/infra/sentry/issue-alerts.tf` header, "TRIGGER LOGIC IS HARDCODED BY THE PROVIDER. `sentry_alert` exposes no `logic_type` on `trigger_conditions` -- it always applies `any-short`." Plan v1's derived rule contradicted a fact written in the file it was reading about. Consequence folded into the projection design (single-trigger constant on both sides).
- **Provider schema (from review):** `enabled`, `trigger_conditions`, and `action_filters[].conditions` are Optional+Computed; a block that omits `enabled` would be unknown at plan time for a create row. Every block in `issue-alerts.tf` sets `enabled = true` explicitly today; the projection fails closed if `enabled` is not a boolean or a conditions list is not an array (Phase 1.1), so an omission can never become a `null` that matches a `null`.
- **Branch-protection fact (from review):** `infra/github/ruleset-ci-required.tf` sets `strict_required_status_checks_policy = true` and lists `sentry-destroy-required` as a required context, so a PR must be current with `main` before merge and `plan_pr` re-runs on the rebased head — two PRs each adding a rule cannot both merge with a reference lacking the other's rule.
- ADR corpus grep for the mechanism (`show -json`, `planned_values`, `committed capture`): ADR-031 records the capture as the reference ("diffs all 27 against the committed capture"); ADR-032 uses a `terraform show -json | jq` pre-apply gate as its mandatory gate — the mechanism this plan adopts has an accepted precedent and no ADR rejects it. ADR-031 is amended (Phase 6), not reversed: Terraform stays the source of truth; only the probe's reference provenance changes.
- Capability claims checked before asserting: `terraform` reads only `*.tf`/`*.tf.json`, so a `.json` reference under the root directory is inert to plan/apply/fmt; no sentry tooling globs `infra/sentry/*.json`; `scripts/regenerate-c4-model.sh` and `plugins/soleur/test/c4-model-freshness.test.sh` exist.
- Doppler `prd` `SENTRY_API_HOST` compared (boolean, not printed) against the literal `jikigai-eu.sentry.io`: MATCH. `variables.tf` defaults `sentry_org` to `jikigai-eu`. These are the pin literals for the #7997 fold-in.

### Property List (Phase 0.6b)

- **P1** — The next merge to `main` that touches the Sentry root runs `apply-sentry-infra.yml` to green; #8050 is closed at merge by the PR body (the workflow's success step then finds no open tracking issue, which is the expected no-op).
- **P2** — A `sentry_alert` that is declared in the root and applied is never reported `UNMANAGED`/`DRIFT`/`LOGICTYPE FLIP` by the post-apply probe or the daily probe merely because a reference file was not refreshed, or because the provider wrote a trigger logic type the `.tf` cannot express.
- **P3** — A PR that adds, edits, or removes a `sentry_alert` in the root without regenerating the committed reference fails **before merge**, with the exact expected content available as a downloadable artifact and in the step summary, so `main` cannot go red after the write.
- **P4** — The daily drift workflow files the "could not establish a verdict" issue only on runs that did not reach a verdict (or reached `drift` and could not file it), and never on a cancelled run.
- **P5** — The probe keeps detecting, for every declared rule: deletion, `enabled:false`, name drift, changed comparison/tag, a multi-trigger logicType flip, detector unbind, and the reverse direction (live in-scope rule not declared).
- **P6** — Editing the probe does not turn the `lint-bot-statuses` check red on pre-existing #7997 violations.

### Cut List (Phase 0.6b + plan review)

- **Re-capture from live into a new dated `phase35-…` file** (the #7988 precedent) → buys P1 only; re-creates the structural gap and a 5-place repoint the README already lost once. Cut.
- **State-as-reference in the daily job** (`terraform state pull` daily) → buys P2/P3 with no committed file, but puts the R2 credentials for the shared `soleur-terraform-state` bucket (every root's state, host secrets included) into a daily cron job. Cut; the committed copy gives the daily job the same reference with its current three secrets.
- **Name-only parity test** → cannot pass pre-merge for a new rule; cut in favour of the field-level projection gate.
- **Bot commit / artifact hand-off / warning-not-failure** → `contents: write` loop; artifact expiry on a near-dormant workflow; re-opens "the one rule the probe cannot see". Cut.
- **Pre-apply copy of the reference gate in the `apply` job** (plan v1) → both review panels fired on it: the simplification panel (redundant once the apply job projects its own reference), the correctness panel (its red routes to a tracking issue whose remedy — re-run — cannot fix a stale committed file). With the apply job reading a reference projected from its own plan, the committed copy's only consumer is the daily job, and a stale copy (reachable only through a `merge_group` merge whose PR-time gate ran on an older head, which the strict up-to-date policy already prevents) surfaces as one daily-drift issue naming the regeneration remedy, not as a red apply. Cut.
- **Golden-anchor row against the phase34 capture with a `GOLDEN_KNOWN_DIVERGENCES` ledger, and the inverse `_api_shape` helper** (plan v1) → both panels fired: a hand-maintained exclusion list that grows per `.tf` edit, a second inverse projection to keep 13 fixture rows alive, and an AC contradiction. Cut; the probe's suite keeps the frozen phase34 capture as its live fixture and derives its reference from it at suite start; the continuous real-data anchor is the live probe itself (post-merge step 15 and daily), and the one-time 28/28 parity is recorded in the PR body (AC3).
- **Raw v4 state input branch in the projection** → only consumer was a fallback against an artifact that expires 2026-09-17. Cut; the projection accepts `terraform show -json` plan or state documents (`(.planned_values // .values).root_module`).
- **Separate `after_unknown` traversal in the gate** (plan v1 1.1b) → an unknown projected leaf is absent from `planned_values` and renders `null`; a `null` where a boolean or array is required is already an `error` in the projection. Collapsed into the projection floors.

### Relevant files (content anchors)

- `.github/workflows/apply-sentry-infra.yml` — `plan_pr` job: `terraform show -json tfplan > /tmp/sentry-pr-plan.json` then the `sentry-destroy-counts.sh` / `sentry-issue-alert-create-tripwire.sh` / `sentry-monitor-binding-gate.sh` / `sentry-adoption-plan-assert.sh` sequence (the guard block re-arms `set -e` before these calls, so a bare `bash gate.sh` exit 1 aborts the step); `apply` job: `terraform show -json tfplan > /tmp/sentry-apply-plan.json`, same guard sequence, then `terraform apply -auto-approve -input=false tfplan` (step "Terraform apply (cron + uptime monitors)"); post-apply step "sentry_alert live fidelity (AC19/AC20)" (`if: always()`, runs `bash scripts/sentry-alert-live-fidelity.sh` with `SENTRY_AUTH_TOKEN`/`SENTRY_API_HOST`/`SENTRY_ORG` from `secrets.*`); "File or comment tracking issue (apply failed)" (`if: failure()`, dedupes by label `ci/apply-sentry-infra` + title, `--state open`); "Close the apply-failure tracking issue (success)" gated `success() && steps.forensics_sweep.outputs.secret_shape != 'true'`. `paths:` covers `apps/web-platform/infra/sentry/**` and `tests/scripts/lib/destroy-guard-filter-sentry.jq`; `detect-changes` regex `^(apps/web-platform/infra/sentry/|tests/scripts/lib/destroy-guard-filter-sentry\.jq$|\.github/workflows/apply-sentry-infra\.yml$)`.
- `.github/workflows/scheduled-sentry-alert-drift.yml` — step `id: probe` verdict branching (`clean`/`drift`/`unavailable`); "File or update the drift issue" (`id: file_drift`, `if: always() && steps.probe.outputs.verdict == 'drift'`, writes `filed=true` then exits 1); "File or update the probe-unavailable issue" (`if: always() && failure()` — the defect); "Close the probe-unavailable issue (a verdict was reached)" (`verdict == 'clean' || verdict == 'drift'`); "Close the drift issue (clean)" matches `.title == "[ci/sentry-alert-drift] a migrated Sentry alert has drifted from the committed capture"`; the same TITLE literal is in the filer's `TITLE=` and its dedupe query. Body text cites the phase34 path; "28 adopted" appears at three sites. Heartbeat step is source-gated (`inputs.source == 'inngest'`).
- `scripts/sentry-alert-live-fidelity.sh` — `CAPTURE="${SENTRY_CAPTURE_FILE:-…phase34…json}"`, `fetch_rules()` (fixture mode + `curl -fsS --max-time 15` at the #7997 line), the `PROJECT` jq (canon, `in_scope`, allowlist projection, `INDEX(.name)`), per-field loop over `enabled detectorIds frequency triggerLogicType triggerConditions actionFilters`, reverse-direction `UNMANAGED` loop, PASS/FAIL verdict lines the workflows grep (`live fidelity FAILED`, `PASS (all `; fixture mode prints `PASS (FIXTURE — not live) (all N …)`).
- `tests/scripts/test-sentry-alert-live-fidelity.sh` — `CAPTURE=` pinned to phase34, `EXPECTED_TESTS=13`, `_run` (fixture via `SENTRY_FIXTURE_RULES`), `_mutant` (asserts the jq edit landed), F13 (API-shaped fixture = capture + server fields, asserted semantically identical after strip).
- `tests/scripts/test-sentry-alert-drift-workflow.sh` — extracts step `run`/`if:` via `python3 … import yaml` (PyYAML is a CI-image guarantee), `WF=` hard-coded, `EXPECTED_TESTS=5`, W5 asserts every step with "Close" in its name is gated `verdict == 'clean'` with no `!=`; W7 runs the real probe on a real divergence and asserts the exact marker.
- `scripts/test-all.sh` — `run_suite "tests/scripts/sentry-alert-live-fidelity" bash tests/scripts/test-sentry-alert-live-fidelity.sh` and siblings; registration is explicit, no count manifest.
- House style for plan-JSON gates: `scripts/sentry-monitor-binding-gate.sh` (`set -uo pipefail`, `<plan.json>` positional, `.resource_changes` row-count floor, anti-vacuity floor, `::error::` lines, exit 1, rc captured on its own line after each jq) and `scripts/sentry-destroy-counts.sh`. A script that reads no credential needs no entry in `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`.
- `scripts/lint-shell-trace-credential-refusal.py` — Rule D: `CURL_DISABLE_FIRST = \bcurl\s+--disable(?:\s|$)`, `CURL_NOPROXY = --noproxy\s+'?\*'?`, `_pin_re`: `[[ "$VAR" == "literal" ]]` with a literal RHS; model `scripts/supabase-logs-query.sh`.
- `apps/web-platform/infra/sentry/README.md` — line 5 count "29 `sentry_alert` rules + 2 `sentry_issue_alert`", §Local invocation (the Doppler `prd_terraform` triplet + `terraform init -input=false` + `terraform plan`), §Drift detection (stale phase2 path).
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — "Ongoing detection is now a deliverable" paragraph ("diffs all 27 against the committed capture"); amendment convention `> **[YYYY-MM-DD — #NNNN]** …`.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `sentry -> founder` edge prose: "27 are `sentry_alert` … the 3 that stay behind … `git_data_boot_warning` only because it landed after the adoption capture was taken" (stale since #7988/#7989); compiled twin `model.likec4.json` is byte-diffed by `plugins/soleur/test/c4-model-freshness.test.sh` (CI required).
- Forensics artifact `sentry-forensics-state-34491157462` (expires 2026-09-17): raw `terraform state pull` v4 documents — read for the measurement above; never committed.

### Institutional learnings applied

- `knowledge-base/project/learnings/best-practices/2026-07-17-derive-replicated-literal-and-nonvacuous-drift-guard.md` — a guard comparing a copy to a copy is self-referential; derive the artifact from the single source and prove the guard non-vacuous by mutation. This is the shape of the reference gate.
- `knowledge-base/project/learnings/2026-04-03-lockfile-sync-ci-check-pattern.md` — regenerate the derived file in CI, diff against the committed one, fail the PR on divergence. Same pattern, applied to the reference.
- `knowledge-base/project/learnings/2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md` — `jq length` on null reads 0 and passes; assert shape before trusting counts. Applied to every floor in the gate and the probe's reference load.
- `knowledge-base/project/learnings/2026-07-30-the-guard-i-wrote-for-the-failure-path-could-not-run-on-the-failure-path.md` — GitHub `if:` status-function semantics; the mirror-image defect here is a `failure()` that is TRUE on the intended-exclusion path. Fix by gating on the named verdict, not on job status.
- `knowledge-base/project/learnings/2026-07-17-unmanaged-is-not-dead-and-a-plan-premise-about-a-repo-setting-is-checkable.md` — "unmanaged" is a property of the reference, not of the rule; verify before concluding.
- `knowledge-base/project/learnings/2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md` — `gh` read-after-write lag; explains why the close step missed #8058. The gate fix makes create-then-close within one run unreachable, so no retry loop is added.
- `knowledge-base/project/learnings/2026-09-07-my-instruments-reported-green-while-measuring-nothing.md` — the probe PASS line is cited as evidence elsewhere; every verdict must carry its mode and floor.
- `knowledge-base/project/learnings/2026-06-12-detector-cron-must-route-its-own-self-failure-ops-and-register-new-sentry-alert-in-apply-target.md` — surfaced by research; its `-target=` advice is stale since #6589 (full-root). Not applied.

### Functional overlap (Phase 1.5b)

No community overlap: registries queried (3/3) returned general Terraform/Sentry tooling only; nothing projects `terraform show -json` into a fidelity reference or gates a committed snapshot. Proceed in-repo.

### Research decision (Phase 1.6)

Strong local context (two prior PRs on this exact probe, a measured projection, house-style gate scripts, the provider source at the pinned tag). No external research beyond the provider source read. Doc citation: Terraform JSON output format, https://developer.hashicorp.com/terraform/internals/json-format (`planned_values.root_module.resources[].values`; `values.root_module.resources[].values`).

## Proposed Solution

Make the Terraform plan the probe's reference. The apply job projects the reference from the plan document it is about to apply; the daily job reads a committed copy that a PR-time gate holds equal to the plan.

```text
                 issue-alerts.tf (source of truth)
                          │ terraform plan → terraform show -json
                          ▼
   ┌── PR-time (plan_pr) ─────────────────────────────────────────────────────┐
   │ sentry-alert-reference-gate.sh /tmp/sentry-pr-plan.json alert-reference │  RED → PR blocked;
   │   projection(plan) == normalise(alert-reference.json)                    │  expected file in the
   └──────────────────────────────────────────────────────────────────────────┘  step summary + artifact
                          │ merge → push → apply job
   ┌── apply job ─────────┴───────────────────────────────────────────────────┐
   │ terraform show -json tfplan → /tmp/sentry-apply-plan.json                │
   │ projection(apply plan) → ${RUNNER_TEMP}/sentry-alert-reference.json      │
   │ terraform apply                                                          │
   │ sentry-alert-live-fidelity.sh  live GET  vs  ${RUNNER_TEMP} reference    │  ← never reads the
   └──────────────────────────────────────────────────────────────────────────┘    committed copy
   ┌── daily drift job ───────────────────────────────────────────────────────┐
   │ sentry-alert-live-fidelity.sh  live GET  vs  committed alert-reference   │
   └──────────────────────────────────────────────────────────────────────────┘
```

- **Projection module:** `tests/scripts/lib/sentry-alert-projection.jq`, one file, selected by `--arg side tf|live|reference` (production jq filters live in that directory, like `destroy-guard-filter-sentry.jq`). `tf` reads a `terraform show -json` plan or state document and emits the comparable shape; `live` is the probe's current `PROJECT` moved out of the bash string; `reference` normalises an already-projected document. One definition of `canon` (key order) and `normalise` (array order) serves all three sides.
- **Committed reference:** `apps/web-platform/infra/sentry/alert-reference.json` — exists for the daily job, which has no Terraform access. Living under the root directory puts every change to it inside the apply workflow's `paths:` filter and `detect-changes` regex.
- **Gate:** `scripts/sentry-alert-reference-gate.sh <plan.json> <reference.json>`, house style, ONE call site (`plan_pr`); on mismatch prints leaf-level differences, the regeneration command, and writes the expected document to `$GITHUB_STEP_SUMMARY` and to an uploaded artifact.
- **Probe:** reads the reference through `--arg side reference`, keeps every finding class, adds the single-trigger logicType normalisation on the live side, and closes its #7997 rows.
- **Apply job:** the post-apply probe step receives `SENTRY_REFERENCE_FILE=${RUNNER_TEMP}/sentry-alert-reference.json`, projected from `/tmp/sentry-apply-plan.json` in the plan step. A stale committed copy cannot red the apply job by construction.
- **Daily workflow:** dead-man's switch gated on the verdict (and `!cancelled()`), TITLE literal hoisted to one job-level `env:` and unchanged, body text rewritten.

## Alternative Approaches Considered

| Approach | Buys | Why not |
|---|---|---|
| A. Re-capture from live into `phase35-…-2026-09-11.json`, repoint 5 references (#7988 precedent) | P1 | Structural gap remains: a new rule cannot be live-captured before it is applied, so every addition reds `main` once. README already drifted on the repoint. |
| B. Daily job pulls Terraform state and compares live to state (no committed file) | P2, P3 | Puts the R2 credentials for the shared state bucket (every root's state) into a daily cron job. Same detection at a wider credential surface. |
| **C. Apply job projects its reference from its own plan; committed projected copy for the daily job, gated equal to the plan at PR time (chosen)** | P1–P6 | The committed file has one consumer (the daily job), is generated, is printed on mismatch, and cannot merge stale under the strict up-to-date policy. |

## Implementation Phases

### Phase 0 — Preconditions and probes (no product edits)

0.1 From `apps/web-platform/infra/sentry/`, produce a current plan document with the README §Local invocation triplet (Doppler `prd_terraform`: `SENTRY_AUTH_TOKEN` ← `SENTRY_IAC_AUTH_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`; `terraform init -input=false`; `terraform plan -out=/tmp/sentry-local.tfplan`; `terraform show -json /tmp/sentry-local.tfplan > /tmp/sentry-local-plan.json`). Expected: `Plan: 0 to add, 0 to change, 0 to destroy` (root fully applied at serial 124). If any **`sentry_alert`** row is not a no-op, STOP — that is drift on the surface this plan changes and must be its own issue first (`hr-menu-option-ack-not-prod-write-auth`). A non-no-op row on cron/uptime monitors is unrelated drift: file it as its own issue and proceed (the `sentry_alert` planned values are still correct). Read-only; nothing is applied locally.

0.2 Re-run the parity measurement with the shipped projection: `jq --arg side tf -f tests/scripts/lib/sentry-alert-projection.jq /tmp/sentry-local-plan.json` vs `jq --arg side live -f … phase34-live-workflows-capture-2026-09-09.json`: 28 common names, 0 mismatches, exactly `["ops-email-delivery-failure"]` only on the plan side. Record the numbers in the PR body (this is the one-time real-data anchor; the continuous anchor is the live probe).

0.3 Confirm the two pin literals without printing secrets: `[[ "$(doppler secrets get SENTRY_API_HOST --plain -p soleur -c prd)" == "jikigai-eu.sentry.io" ]]` and `grep -n 'default     = "jikigai-eu"' apps/web-platform/infra/sentry/variables.tf`.

0.4 Baseline the lint that this PR will pull the probe into: `python3 scripts/lint-shell-trace-credential-refusal.py scripts/sentry-alert-live-fidelity.sh` → 3 violations today (Phase 2 takes this to 0) and `sed -n 71p scripts/lint-shell-trace-credential-refusal-d.baseline.txt` → the probe's path (Phase 2 removes it).

0.5 **Known-at-plan-time measurement (recorded, not a gate feature).** *Measured 2026-09-11 on a throwaway create row: `after_unknown` carries `true` ONLY under `id`; `environment` and `legacy_trigger_conditions` are known `null`, and `name`/`enabled`/`frequency_minutes`/`monitor_ids`/`trigger_conditions`/`action_filters` are all known (the nested `{}`/`[false]` entries are structure, not unknowns). One `true` leaf in the whole subtree.* In the worktree, append a throwaway `sentry_alert` block to `issue-alerts.tf` (copy `ops_email_delivery_failure`, new label and `name`), run the read-only `terraform plan -out=/tmp/sentry-scratch.tfplan` + `terraform show -json`, then `git checkout -- apps/web-platform/infra/sentry/issue-alerts.tf`. Read the create row's `.change.after_unknown`: expected `true` only under `id`/`environment`/`legacy_trigger_conditions`, with `name`, `enabled`, `frequency_minutes`, `monitor_ids` (data-source resolved), `trigger_conditions`, `action_filters` all known. Record the key list in the PR body. **Defined outcome if a projected leaf IS unknown:** the projection's type floors (Phase 1.1) `error` on it, the gate reds with "a projected attribute is unknown at plan time for `<address>` — a provider limitation; file an issue and set the attribute explicitly in the block" — fail closed, no "any value" arm. Delete the scratch plan afterwards.

0.6 Re-verify the provider constant the design now rests on: `gh api "repos/jianyuan/terraform-provider-sentry/contents/internal/provider/resource_alert_impl.go?ref=v0.15.7" -q .content | base64 -d | grep -n "OrganizationWorkflowTriggerLogicTypeAnyShort"` → two hits (create and update builders). If the pinned provider in `versions.tf` is not 0.15.7, re-read at the pinned tag.

### Phase 1 — Projection module and the committed reference

1.1 Create `tests/scripts/lib/sentry-alert-projection.jq`, selected by `--arg side tf|live|reference`. Shared definitions (single source of `canon` and `normalise`):

```jq
def canon: walk(if type == "object" then (to_entries | sort_by(.key) | from_entries) else . end);
# Array order is not semantic on either side; sort AFTER canon so serialisation is stable.
def normalise: canon
  | with_entries(.value |= (
      .triggerConditions |= sort_by(tostring)
      | .actionFilters |= map(.conditions |= sort_by(tostring) | .actions |= sort_by(tostring))
      | .actionFilters |= sort_by(tostring)));
def excluded: ["event_unique_user_frequency_count","new_high_priority_issue","existing_high_priority_issue"];
def lifecycle: ["first_seen_event","reappeared_event","regression_event","issue_resolved_trigger"];
# Provider v0.15.7 writes trigger logicType = any-short on every create/update
# (resource_alert_impl.go 803/835); imported single-trigger rules still read `all`.
# With one condition any/all are identical, so both sides project the constant.
def trigger_logic_type($n; $live): if $n <= 1 then "single" elif $live == null then "any-short" else $live end;
# Shape is not cardinality: `{}` passes shape_ok and is caught by the probe's/gate's
# separate zero-rules floor, so that floor is reachable and testable (P4).
def shape_ok: type == "object"
  and all(.[]; type == "object" and (keys == ["actionFilters","detectorIds","enabled","frequency","name","triggerConditions","triggerLogicType"]));
```

`side == "tf"`: `(.planned_values // .values) // error("not a terraform show -json plan or state document")`, refuse a non-empty `root_module.child_modules`, take `root_module.resources[] | select(.type=="sentry_alert") | .values`, then `canon` FIRST, then per resource: `enabled` must be a boolean, `trigger_conditions` and each `action_filters[].conditions`/`.actions` must be arrays (an unknown-at-plan leaf renders `null` here and is an `error`, not a value); each condition/action element must carry exactly one non-null key (`error` otherwise); a trigger whose type is in `excluded` is an `error` ("this trigger is outside the probe's live scope; it would apply and then read as DELETED"); lifecycle triggers → `comparison: true`; action element key must be in the explicit allowlist `["email"]` (an unmapped action kind — `slack`, `webhook`, `sentry_app` — is an `error`, not a silent pass-through of a shape the live side projects differently) and maps to `{type, targetType: .target_type, targetIdentifier: .target_id, fallthroughType: .fallthrough_type}`; `terraform show -json` renders sensitive values in PLAINTEXT under `.values` with `sensitive_values` as a mask only, so the projection also `error`s if a `sentry_alert` resource's `sensitive_values` subtree contains any `true` leaf (none do today: the schema marks no attribute sensitive); `triggerLogicType: trigger_logic_type(.trigger_conditions|length; null)`; duplicate `name`s are an `error` before `INDEX(.name)`; finish with `normalise`.

`side == "live"`: the probe's current `PROJECT` body (canon, `in_scope`, allowlist projection, `INDEX(.name)`) with `triggerLogicType: trigger_logic_type(.triggers.conditions|length; .triggers.logicType)` and a trailing `normalise`.

`side == "reference"`: `if shape_ok then normalise else error("reference is not a name-indexed projection object") end`.

Header documents the measurement behind each normalisation and cites the provider source lines.

1.2 Generate `apps/web-platform/infra/sentry/alert-reference.json`: `jq -S --arg side tf -f tests/scripts/lib/sentry-alert-projection.jq /tmp/sentry-local-plan.json > apps/web-platform/infra/sentry/alert-reference.json`. Expect 29 keys including `ops-email-delivery-failure` and `byok-art-33-breach`. Commit it. It holds rule names, tag keys/values, thresholds and the detector id — all already public in `issue-alerts.tf`.

### Phase 2 — The probe reads a projected reference (and closes its #7997 rows)

2.1 `scripts/sentry-alert-live-fidelity.sh`:
- `REFERENCE="${SENTRY_REFERENCE_FILE:-$REPO_ROOT/apps/web-platform/infra/sentry/alert-reference.json}"` replaces `CAPTURE`/`SENTRY_CAPTURE_FILE`. `git grep -nw SENTRY_CAPTURE_FILE` (word-anchored — `MOCK_SENTRY_CAPTURE_FILE` in `apps/web-platform/infra/ci-deploy.test.sh` is unrelated) and update every consumer (expected: only the probe's suite).
- Live projection: `live_proj=$(jq --arg side live -f "$REPO_ROOT/tests/scripts/lib/sentry-alert-projection.jq" <<<"$live_json")`; reference: `ref_proj=$(jq --arg side reference -f … < "$REFERENCE")` with `rc` captured on its own line — a jq `error` (exit 5) must become `ERROR: … exit 1`, never a "compared 0 rules" pass. Keep the zero-rules floor.
- Header rewritten: reference provenance (projection of `terraform show -json`; in the apply job the plan being applied, in the daily job the committed copy); the single-trigger logicType normalisation and its provider citation; "SCOPE" paragraph → "the reference carries exactly the `sentry_alert` set the root declares; the live side is filtered by the trigger predicate, so the two `sentry_issue_alert` survivors and the vendor default are excluded by construction".
- Finding text: `UNMANAGED: '<name>' is live and in scope but declared nowhere in apps/web-platform/infra/sentry/ (absent from the reference projected from the plan). Adopt it as a sentry_alert or delete it in Sentry.`; `LOGICTYPE FLIP` gains "live state an apply will NOT touch — the provider always writes any-short".
- Verdict literals unchanged (`live fidelity FAILED`, `PASS (all `, `PASS (FIXTURE — not live) (all `); W7 asserts the contract.
- #7997 fold-in on the live GET, inside the live branch of `fetch_rules` after the fixture `return` and after the `:?` guard: `[[ "$SENTRY_API_HOST" == "jikigai-eu.sentry.io" ]] || { echo "ERROR: SENTRY_API_HOST is not the pinned Sentry API host; refusing to send the IaC token elsewhere." >&2; exit 1; }`, the same for `[[ "$SENTRY_ORG" == "jikigai-eu" ]]`, then `curl --disable --noproxy '*' -fsS --max-time 15 --header @- …` with the `Authorization: Bearer …` header fed on stdin (`printf 'Authorization: Bearer %s\n' "$SENTRY_AUTH_TOKEN" | curl … --header @- …`) so the token leaves argv, exactly as the model `scripts/supabase-logs-query.sh` does (`--disable` literally first). Verified at review on a scratch copy: lint 3 → 0 and the 13 fixture rows stay green with this placement.

2.2 `python3 scripts/lint-shell-trace-credential-refusal.py scripts/sentry-alert-live-fidelity.sh` → 0 violations; delete the probe's line from `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` (the lint has no stale-entry check, so a leftover entry would hide a future regression). Comment on #7997 that the fidelity-script rows are closed by this PR; the two `sentry-monitors-audit.sh` rows remain (leave #7997 open).

### Phase 3 — The reference gate (PR time) and the apply job's own reference

3.1 Create `scripts/sentry-alert-reference-gate.sh <terraform-show-json-file> <reference.json>` in the house style of `scripts/sentry-monitor-binding-gate.sh` (`set -uo pipefail`, `rc` on its own line after every jq):
- Floors: plan readable and carrying `planned_values`/`values`; projection succeeds (any jq `error` → `::error::` with jq's message + exit 1) and yields ≥ 1 rule; reference readable and `shape_ok` (an API-shaped array fails here). "A gate that compared nothing must not pass."
- Compare `jq -S -c` of `projection(plan)` against `jq -S -c` of `reference-side normalise(reference)`. Equal → `sentry alert reference gate: PASS (N rules, plan == alert-reference.json)`.
- Unequal → names only-in-plan (`ADDED in .tf, missing from reference`), only-in-reference (`REMOVED from .tf, still in reference`), and for common names the leaf paths that differ (`<name>.<path>: planned=<v> reference=<v>`, via `paths(scalars)`/`has` so `false`/`null` render faithfully). If the ONLY differing leaf across all rules is `detectorIds`, add the hint "the issue-stream detector id moved — see scripts/sentry-monitor-binding-gate.sh; this is not an authoring error". Then the remedy: `Regenerate: jq -S --arg side tf -f tests/scripts/lib/sentry-alert-projection.jq <plan.json> > apps/web-platform/infra/sentry/alert-reference.json` plus "if this PR also removes a rule, the destroy gate asks for `[ack-destroy]` next — a stale reference cannot be acked through". Write the full expected document to `$GITHUB_STEP_SUMMARY` (inside a collapsed `<details>`) and to `${RUNNER_TEMP}/sentry-alert-reference.expected.json`. Exit 1.
- Reads no credential; no baseline entry.

3.2 `.github/workflows/apply-sentry-infra.yml`, `plan_pr` job: after the `sentry-adoption-plan-assert.sh` call and before the CREATE gate, `bash "${GITHUB_WORKSPACE}/scripts/sentry-alert-reference-gate.sh" /tmp/sentry-pr-plan.json "${GITHUB_WORKSPACE}/apps/web-platform/infra/sentry/alert-reference.json"`. Add a following step `actions/upload-artifact` (SHA-pinned like the existing forensics upload, `ea165f8d…` # v4.6.2), `if: failure()`, `if-no-files-found: warn` (any other `plan_pr` red — destroy gate, tripwire — leaves the file absent), uploading `${RUNNER_TEMP}/sentry-alert-reference.expected.json` as `sentry-alert-reference-expected-${{ github.run_id }}` so `gh run download` retrieves it byte-exact without prod credentials. Before the upload, run the same secret-shape sentinel sweep the forensics upload runs over its state files (anchor `sentinel='BEGIN [A-Z ]*PRIVATE KEY|…|sntrys_`) over the expected file and `rm -f` it on a hit. A red gate reds `plan_pr`; `sentry-destroy-required` is fail-closed on a red `plan_pr`, so the required check blocks the PR.

3.3 `apply` job: in the plan step, after `terraform show -json tfplan > /tmp/sentry-apply-plan.json` (this point is AFTER the step re-arms `set -e`, so a bare `rc=$?` branch would be dead code — the #7304 class the same step documents), add `jq -S --arg side tf -f "${GITHUB_WORKSPACE}/tests/scripts/lib/sentry-alert-projection.jq" /tmp/sentry-apply-plan.json > "${RUNNER_TEMP}/sentry-alert-reference.json" || { echo "::error::sentry alert projection of the apply plan failed BEFORE apply — nothing written; see jq's message above"; exit 1; }`. Give the plan step `id: plan` (if it lacks one), the apply step `id: apply`, the probe step `id: fidelity`. The post-apply probe step gets `env: SENTRY_REFERENCE_FILE: ${{ runner.temp }}/sentry-alert-reference.json` and `if: always() && steps.plan.outcome == 'success'` — it keeps running after a failed apply or a red AC17 (the coverage its comment defends) but no longer runs when there is no plan, where it would red on "reference unreadable" in the after-apply position and read as a partial write. The tracking-issue filer body gains one line — `Plan step: ${{ steps.plan.outcome }} · Apply: ${{ steps.apply.outcome }} · Post-apply probe: ${{ steps.fidelity.outcome }}` — and the bullet "a plan-step failure with the apply skipped means the projection or a guard refused BEFORE apply: nothing was written; a re-run cannot fix a stale committed file — the remedy is a follow-up PR carrying the printed expected reference". Rewrite the probe step's comment: the reference IS the plan just applied, so a divergence after apply is live state Terraform does not own or evidence the apply did not do what it reported — the sentence is now true by construction. No gate copy runs in this job (see Cut List). Both `sentry-adoption-plan-assert.sh` invocations keep their phase34 capture argument with a one-line comment ("historical bijection source; self-skipping; NOT the fidelity reference — do not repoint").

3.4 Add `scripts/sentry-alert-reference-gate.sh` and `tests/scripts/lib/sentry-alert-projection.jq` to `on.push.paths` and to `detect-changes`'s anti-bypass regex, each with the `#4419` rationale comment (gate logic outside the root must run the gate against itself; a push touching only these runs a 0-change plan, a no-op apply, and the post-apply probe — the only live exercise of a projection change).

### Phase 4 — Daily drift workflow (own early commit: `fix(ci): drift dead-man's switch fired on drift verdicts`)

4.1 `.github/workflows/scheduled-sentry-alert-drift.yml`, step "File or update the probe-unavailable issue": add `id: file_unavailable`; `if: always() && !cancelled() && (steps.probe.outputs.verdict == 'unavailable' || steps.probe.outputs.verdict == '' || (steps.probe.outputs.verdict == 'drift' && steps.file_drift.outputs.filed != 'true'))`. The `== ''` arm keeps the dead-man's-switch semantics for runs that abort before the probe writes a verdict (`null` coerces equal to `''`); `!cancelled()` stops a Stop click or `timeout-minutes` from filing a false issue; the third arm keeps "drift found but the filer could not post" reported to an issue and not only to the heartbeat. Body line `Verdict reached:` renders `drift — but the drift issue could not be filed` in that arm. Comment records run 34573504979 / #8058 as the measured false positive.

4.2 Hoist the drift TITLE literal to job-level `env: DRIFT_TITLE:` and reference it from the filer's `TITLE=`, its dedupe query, and the "Close the drift issue (clean)" match — the STRING IS UNCHANGED (`[ci/sentry-alert-drift] a migrated Sentry alert has drifted from the committed capture`); renaming it would orphan open #8057 and split every future dedupe/close. Same hoist for the unavailable TITLE.

4.3 Body text: the phase34 path → `apps/web-platform/infra/sentry/alert-reference.json`; all THREE "28 adopted" sites → count-free ("every `sentry_alert` the Sentry root declares"); "If the drift is intentional" → edit the `.tf`, regenerate the reference with the command above, open a PR (the reference gate holds it equal; a re-run of this workflow cannot repair a stale committed file); `UNMANAGED` line → "a live rule in scope that the root does not declare — adopt or delete".

4.4 "Close the probe-unavailable issue (a verdict was reached)": `if: always() && (steps.probe.outputs.verdict == 'clean' || (steps.probe.outputs.verdict == 'drift' && steps.file_drift.outputs.filed == 'true'))` — mirroring the heartbeat step's own expression. Without the `filed == 'true'` conjunct the closer would run on the very arm 4.1 adds (`drift` + not filed) and close the issue the filer just opened in the same run (or, per the recorded 0.5 s read-after-write miss, sometimes not — nondeterministic). After this the filer and the closer are disjoint on the PAIR `(verdict, filed)`, so create-then-close in one run is unreachable; no retry is added, and the step comment records the miss as the reason the pair must stay disjoint. W5 still holds (the closer's gate uses `==` only and names `'clean'`).

4.5 The unavailable filer's `gh issue create --milestone "Post-MVP / Later"` hard-fails under `set -euo pipefail` the day that milestone closes (the apply-job filer already carries a `|| gh issue create … ` no-milestone fallback; this step does not). Add the same fallback while editing the step. The hoisted titles reach `run:` as `"$DRIFT_TITLE"` / `"$UNAVAILABLE_TITLE"` (env), never `${{ env.… }}` interpolated into the shell string.

### Phase 5 — Tests (RED first, per `cq-write-failing-tests-before`)

5.1 `tests/scripts/test-sentry-alert-live-fidelity.sh`:
- The frozen phase34 capture stays the LIVE fixture (fixtures may be frozen). The suite's reference is derived at start: `jq --arg side live -f … "$CAPTURE" | jq --arg side reference -f … > "$TMPD/reference.json"`, passed via `SENTRY_REFERENCE_FILE`. No inverse mapping.
- Identity row asserts `PASS (FIXTURE — not live) (all ${N} in-scope rules match the committed reference field-for-field)` with `N` computed from the derived reference.
- New rows, each asserting a DISTINCT literal (a row whose RED is indistinguishable from an unrelated failure proves nothing): (a) live fixture gains an in-scope rule → `UNMANAGED: '<name>'`; (b) reference minus one rule → `UNMANAGED` for that rule; (c) API-shaped capture passed as the reference → `not a name-indexed projection object`, no `PASS`; (d) reference `{}` → `ZERO in-scope rules` (reachable because `shape_ok` is shape, not cardinality); (e) no fixture, `SENTRY_AUTH_TOKEN`/`SENTRY_ORG` set so the `:?` guard is not what exits, `SENTRY_API_HOST=evil.example`, recording `curl` shim on `PATH` → `is not the pinned Sentry API host`, shim records zero invocations; (f) host equals the literal, the shim asserts `$1 == --disable`, `--noproxy '*'` present, `--header @-` present with the token on stdin, and serves the capture → `PASS (all 28` end-to-end through the pinned path; (g) single-trigger rule's live `logicType` mutated `all → any-short` (the provider's post-apply value; `all → all` would be a NOOP the `_mutant` landing check rejects) → PASS, no FLIP; (h) three-trigger rule's live `logicType` mutated `any-short → all` → `LOGICTYPE FLIP`; (i) **tf/live shape parity — the structural anchor for `side tf`:** over `common = keys(alert-reference.json) ∩ keys(live(phase34 capture))`, assert `common | length >= 20` and, per name, equal sets of `[path with numeric indices replaced by "[]", leaf type]` from `paths(scalars)` — a dropped `comparison: true`, a null `targetIdentifier`, or a string-vs-array `detectorIds` in the committed tf-projected reference reds here, while threshold edits and added conditions do not (no value ledger); (j) shape floor: reference with one rule's `triggerLogicType` key deleted → `not a name-indexed projection object`; (k) normalise negative control: swap `comparison.value` between two conditions of `zot-mirror-fallback-rate` (5 conditions) → `DRIFT … comparison.value` (proves `sort_by(tostring)` distinguishes data from order); (l) H4 as a real row: `_mutant` with a selector matching nothing returns `NOOP` and the row FAILs on landing. `EXPECTED_TESTS` 13 → 25 (identity row kept as a WIRING test, stated as such in its comment; F12's hard-coded `comparing 28 captured` stays — the fixture is frozen, so 28 is a fixture constant).

5.2 New `tests/scripts/test-sentry-alert-reference-gate.sh` (synthesized fixtures only): a two-rule synthetic `planned_values` plan — one rule with TWO trigger conditions and TWO actions so array-order rows are meaningful — and its projection as the reference. G0 positive control first (`PASS (2 rules, plan == alert-reference.json)`; without it every M-row is indistinguishable from "the gate always exits 1"), then Guard 1 M1–M12 with their distinct literals, the must-PASS rows, and H2. Show-state (`values`) input of the same two rules projects identically (one row).

5.3 `tests/scripts/test-sentry-alert-drift-workflow.sh`: `WF="${SENTRY_DRIFT_WF:-$REPO_ROOT/.github/workflows/scheduled-sentry-alert-drift.yml}"`; W8 selects the step by `id == "file_unavailable"` (exactly one; the name-based selector would match the Close step too), collapses whitespace (`tr -s ' '`) and asserts the `if:` contains `!cancelled()`, `verdict == 'unavailable'`, `verdict == ''`, `filed != 'true'`, and does NOT contain `failure()`. Mutation rows W8-a..e / W9-a run in-suite against temp copies mutated at the YAML level with `python3` + PyYAML (`safe_load`, edit `steps[id=="file_unavailable"]["if"]` / `del s["id"]` / the closer's `if:` / the closer's `run:` title, `safe_dump`), with the landing assert re-loading the copy and comparing the TARGET field — not `sed` (a single-line `s///` outside a range hits the five other `always() &&` steps first) and not `cmp` on the file. W9: the filer's and the closer's title references resolve to the same `env` key (`"$DRIFT_TITLE"`). `EXPECTED_TESTS` 5 → 8 (W8, W8-e's positive twin on the closer's `filed == 'true'` conjunct, W9).

5.4 Register `run_suite "tests/scripts/sentry-alert-reference-gate" bash tests/scripts/test-sentry-alert-reference-gate.sh` in `scripts/test-all.sh` beside the sibling sentry suites. Run the sentry group plus `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`.

### Phase 6 — Documentation and architecture record

6.1 `apps/web-platform/infra/sentry/README.md` §Drift detection: the apply job derives its reference from the plan it applies; the committed `alert-reference.json` exists ONLY because the daily job has no Terraform access, and is held equal to the plan by `sentry-alert-reference-gate.sh` in `plan_pr` — a future reader must not "fix" the apply job to read the committed file (that coupling is what redded `main`). Regeneration recipe (local-invocation triplet + `terraform show -json` + the jq command); "adding a rule = a resource block + a regenerated `alert-reference.json`; the gate prints the file and uploads it if forgotten"; the phase2/phase34 captures are history. Keep line 5's `29 + 2`.

6.2 `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`, dated note under "Ongoing detection is now a deliverable": `> **[2026-09-11 — #8050]** The probe's reference is no longer the live capture. #7989 added a rule the 2026-09-09 capture could not contain (a rule cannot be live-captured before it is applied), so the post-apply probe reported a Terraform-managed rule as UNMANAGED and `main` went red after a complete apply. The apply job now projects its reference from the plan it applies (`tests/scripts/lib/sentry-alert-projection.jq`); the daily job reads `apps/web-platform/infra/sentry/alert-reference.json`, a committed copy held equal to the plan by `scripts/sentry-alert-reference-gate.sh` in `plan_pr`. Two normalisations bridge provider and API shapes: lifecycle triggers → `comparison: true`, and trigger `logicType` — which the provider hard-codes to `any-short` on every write (`resource_alert_impl.go` 803/835 at v0.15.7) while imported single-trigger rules read `all` — projected to a constant for single-trigger rules on both sides. Measured against 28 live rules: 0 mismatches. The daily job keeps the write-capable IaC token, used read-only and destination-pinned (#7997), rather than gaining R2 state credentials. The captures stay as the Phase 2/3.4 adoption record.`

6.3 `knowledge-base/engineering/architecture/diagrams/model.c4`, edge `sentry -> founder`: update the stale split to 29 `sentry_alert` + 2 `sentry_issue_alert` (31 IaC rules; 30/1 on the fallthrough routing since `ops_email_delivery_failure` is ActiveMembers) and replace "adoption capture" with "the plan-derived reference (#8050)". Then `bash scripts/regenerate-c4-model.sh`, commit `model.likec4.json`, and run `bash plugins/soleur/test/c4-model-freshness.test.sh` and `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.

6.4 `apps/web-platform/infra/sentry/issue-alerts.tf` is NOT edited: its header's "PASS field-for-field against the capture" is a historical statement about the #7826 gate discharge and stays true as history; no `.tf` change of any kind in this PR (so the apply job's plan is a no-op by construction).

### Phase 7 — Verification and roll-forward

7.1 Local live probe (read-only GET) with the Doppler `prd` values: `SENTRY_AUTH_TOKEN=$(doppler secrets get SENTRY_IAC_AUTH_TOKEN --plain -p soleur -c prd) SENTRY_API_HOST=$(doppler secrets get SENTRY_API_HOST --plain -p soleur -c prd) SENTRY_ORG=jikigai-eu bash scripts/sentry-alert-live-fidelity.sh` → `PASS (all 29 in-scope rules match the committed reference field-for-field)`. Never under `bash -x` (#7797).

7.2 **Immediately before merge (same session):** `gh workflow run scheduled-sentry-alert-drift.yml --ref <branch>` then `gh run watch`. This read-only, `workflow_dispatch`-only workflow is the only pre-merge execution of the pinned probe with the REAL repository secrets (`secrets.SENTRY_ORG`/`SENTRY_API_HOST` are repo-level, so this proves the exact values the apply job sees). Expected: `verdict=clean`, `file_unavailable` `skipped`, "Close the drift issue (clean)" closes #8057 and "Close the probe-unavailable issue" closes #8058 — on live evidence, by the mechanism, not by the PR body. The heartbeat is source-gated (`inputs.source == 'inngest'`), so a manual run does not touch the Sentry cron monitor. **Defined outcomes:** a `refusing to send the IaC token` line means the repo secret differs from the pin — set it with `gh secret set SENTRY_API_HOST --body jikigai-eu.sentry.io` (a hostname, not a secret) and re-dispatch before merging; a real, unrelated `drift` verdict leaves #8057 open and is triaged as its own issue — this PR still merges (its probe read live correctly). (The issue's `workflow_dispatch` prohibition is about the APPLY workflow, whose dispatch cannot carry an ack.)

7.3 PR-time: `plan_pr` runs on this branch (it touches `apps/web-platform/infra/sentry/`), plan shows `0 to destroy`, the reference gate PASSes, `sentry-destroy-required` green.

7.4 PR body: `Closes #8050`; `Ref #8057`, `Ref #8058` (closed by 7.2's run). Body, not title (`wg-use-closes-n-in-pr-body-not-title-to`).

7.5 Post-merge (`wg-after-a-pr-merges-to-main-verify-all`): `gh run list --workflow apply-sentry-infra.yml --branch main --limit 1 --json conclusion,headSha,event` → `success` on the merge SHA, `event: push`; step 15 log `PASS (all 29 …)`; `gh issue view 8050 --json state` → CLOSED (by the PR body at merge; the workflow's success step then finds no open tracking issue — expected). Next 07:15 UTC drift run → `clean`; `gh issue list --label ci/sentry-alert-drift --state open` → empty (a drift issue filed by the 07:15 run BEFORE merge, against the stale capture, is closed by that first clean run).

## Files to Create

- `tests/scripts/lib/sentry-alert-projection.jq` — the three-sided projection module (Phase 1.1).
- `apps/web-platform/infra/sentry/alert-reference.json` — the committed projected reference (29 rules), generated in Phase 1.2.
- `scripts/sentry-alert-reference-gate.sh` — the PR-time gate (Phase 3.1).
- `tests/scripts/test-sentry-alert-reference-gate.sh` — gate + projection suite (Phase 5.2).
- `knowledge-base/project/specs/feat-one-shot-8050-apply-sentry-infra-red-on-main/decision-challenges.md` — plan-review taste items for `ship` Phase 6 (written at plan time).

## Files to Edit

- `scripts/sentry-alert-live-fidelity.sh` — projection module, reference load, messages, header, #7997 curl confinement + pins (Phase 2).
- `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` — remove the probe's line (Phase 2.2).
- `.github/workflows/apply-sentry-infra.yml` — gate + expected-file artifact in `plan_pr`; projected reference + `SENTRY_REFERENCE_FILE` in `apply`; `paths:`/`detect-changes` entries; step comments (Phase 3).
- `.github/workflows/scheduled-sentry-alert-drift.yml` — filer `id`/`if:`, TITLE `env` hoist, body text (Phase 4).
- `tests/scripts/test-sentry-alert-live-fidelity.sh` — derived reference + new rows (Phase 5.1).
- `tests/scripts/test-sentry-alert-drift-workflow.sh` — `WF` env, W8, W9 (Phase 5.3).
- `scripts/test-all.sh` — register the new suite (Phase 5.4).
- `apps/web-platform/infra/sentry/README.md` — §Drift detection (Phase 6.1).
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — dated note (Phase 6.2).
- `knowledge-base/engineering/architecture/diagrams/model.c4` and `model.likec4.json` — `sentry -> founder` edge prose + regenerated compiled model (Phase 6.3).

Untouched, deliberately: `knowledge-base/project/specs/fix-7650-sentry-alert-migration/*` (history; `sentry-adoption-plan-assert.sh` still takes the phase34 file as its self-skipping bijection input; the probe suite keeps it as a frozen live fixture), `scripts/sentry-adoption-plan-assert.sh`, `apps/web-platform/scripts/sentry-monitors-audit.sh` (#7997's remaining rows).

## Open Code-Review Overlap

- #7942 (`scripts/test-all.sh`: two `*.mutation.sh` batteries run in no gate) — **Acknowledge.** This PR adds one `run_suite` line; the mutation-battery registration question is a separate concern and stays open.
- #7997 (credentialed curl sites not transport-confined / destination-pinned; names `scripts/sentry-alert-live-fidelity.sh:91`) — **Fold in, partially.** The fidelity-script rows are closed here because editing the file pulls them into `lint-shell-trace-credential-refusal.py --changed` scope; the `sentry-monitors-audit.sh` rows (region-discovery design question) remain in #7997 with a comment.

## Acceptance Criteria

ACs marked **(evidence)** depend on GitHub, live Sentry, or the prod plan and are recorded in the PR body; the rest are CI-reproducible. Numbering below is this plan's own; the tokens `AC17`, `AC19`, `AC20` elsewhere in this document are the #7650 labels baked into the workflow's step names (`AC17 — terraform state list…`, `sentry_alert live fidelity (AC19/AC20)`), not entries in this list.

### Pre-merge (PR)

1. **(evidence)** `gh run view 34491157462 --json jobs -q '.jobs[] | select(.name=="apply") | .steps[] | select(.name | test("Terraform apply|live fidelity")) | "\(.name): \(.conclusion)"'` prints `Terraform apply (cron + uptime monitors): success` and `sentry_alert live fidelity (AC19/AC20): failure`.
2. **(evidence)** `jq --arg side tf -f tests/scripts/lib/sentry-alert-projection.jq /tmp/sentry-local-plan.json | jq 'keys | length'` → `29`; `jq 'has("ops-email-delivery-failure") and has("byok-art-33-breach")' apps/web-platform/infra/sentry/alert-reference.json` → `true`.
3. **(evidence)** Phase 0.2 parity: 0 mismatches over exactly 28 common names; plan-only names `["ops-email-delivery-failure"]`; capture-only `[]`. Phase 0.5 `after_unknown` key list recorded. Phase 0.6 provider grep → 2 hits.
4. **(evidence)** `bash scripts/sentry-alert-reference-gate.sh /tmp/sentry-local-plan.json apps/web-platform/infra/sentry/alert-reference.json` → exit 0, output contains `PASS (29 rules`.
5. `python3 scripts/lint-shell-trace-credential-refusal.py scripts/sentry-alert-live-fidelity.sh` → `0 violation(s)`; `grep -cE '^\s*curl --disable --noproxy' scripts/sentry-alert-live-fidelity.sh` → `1`; `grep -cE '"\$SENTRY_API_HOST" == "jikigai-eu\.sentry\.io"' scripts/sentry-alert-live-fidelity.sh` → `1`; `grep -cE '"\$SENTRY_ORG" == "jikigai-eu"' scripts/sentry-alert-live-fidelity.sh` → `1`; `grep -c 'sentry-alert-live-fidelity' scripts/lint-shell-trace-credential-refusal-d.baseline.txt` → `0`.
6. `git grep -nw SENTRY_CAPTURE_FILE -- scripts tests .github` → no output; `git grep -n phase34-live-workflows-capture -- scripts/sentry-alert-live-fidelity.sh .github/workflows/scheduled-sentry-alert-drift.yml apps/web-platform/infra/sentry/README.md` → no output; `grep -c phase34-live-workflows-capture tests/scripts/test-sentry-alert-live-fidelity.sh` → `1` (the frozen live fixture); `grep -c phase34-live-workflows-capture .github/workflows/apply-sentry-infra.yml` → `2` (the two `sentry-adoption-plan-assert.sh` arguments, each with the do-not-repoint comment).
7. `bash tests/scripts/test-sentry-alert-live-fidelity.sh` → all rows pass, `EXPECTED_TESTS=33` (13 original + #8023's F14–F21 adapted to the literal pin and the derived reference + this PR's F22–F32 and H4; (a) is folded into F10's tightened literal and (d) into F11's `{}` reference — count derived from the as-written suite after the #8023 rebase), and the tf/live shape-parity row (i) reports `common >= 20`; the identity row's asserted literal is `(all ${N} in-scope rules match the committed reference field-for-field)` preceded by `PASS (FIXTURE — not live)`, with `N` computed from the derived reference.
8. `bash tests/scripts/test-sentry-alert-reference-gate.sh` → all rows pass (`EXPECTED_TESTS=29`); G0 and each Guard 1 mutation row (M1–M19: the review added M13–M19 for the module floors the first battery never mutated), the must-PASS rows, D1/M7b and H2 are named in `[ok]` lines.
9. `bash tests/scripts/test-sentry-alert-drift-workflow.sh` → `EXPECTED_TESTS=20` (5 original + W3b, W8, W8c, W9, W9b + the mutation rows W8-a..h, W5-a, W9-a, each a counted `_report` row), W8/W8c compare the EXACT whole expression (substring presence let a bare `filed != 'true'` pass — review mutation), and the in-suite mutation rows each report `[ok]` against their PyYAML-mutated temp copy.
10. `python3 - .github/workflows/scheduled-sentry-alert-drift.yml <<'PY'` / `import sys, yaml` / `d = yaml.safe_load(open(sys.argv[1]))` / `print([s["if"] for s in d["jobs"]["drift-check"]["steps"] if s.get("id") == "file_unavailable"][0])` / `PY` → `always() && !cancelled() && (steps.probe.outputs.verdict == 'unavailable' || steps.probe.outputs.verdict == '' || (steps.probe.outputs.verdict == 'drift' && steps.file_drift.outputs.filed != 'true'))`; the same snippet selecting the step whose name starts with `Close the probe-unavailable` → `always() && (steps.probe.outputs.verdict == 'clean' || (steps.probe.outputs.verdict == 'drift' && steps.file_drift.outputs.filed == 'true'))`.
11. `grep -cE '^\s+bash "\$\{GITHUB_WORKSPACE\}/scripts/sentry-alert-reference-gate\.sh" /tmp/sentry-pr-plan\.json' .github/workflows/apply-sentry-infra.yml` → `1`; `grep -cE '^\s+bash "\$\{GITHUB_WORKSPACE\}/scripts/sentry-alert-reference-gate\.sh" /tmp/sentry-apply-plan\.json' .github/workflows/apply-sentry-infra.yml` → `0` (no apply-job gate copy); `grep -cE '^\s+- "scripts/sentry-alert-reference-gate\.sh"' .github/workflows/apply-sentry-infra.yml` → `0` (revised at review: the apply job never runs the gate, so the push trigger does not carry it — see decision-challenges §4); `grep -cE '^\s+- "tests/scripts/lib/sentry-alert-projection\.jq"' .github/workflows/apply-sentry-infra.yml` → `1`; `grep -cE 'sentry-alert-reference-gate\\\.sh\$' .github/workflows/apply-sentry-infra.yml` → `1` and `grep -cE 'sentry-alert-projection\\\.jq\$' .github/workflows/apply-sentry-infra.yml` → `1` (both in the detect-changes regex); `grep -cE '^\s+SENTRY_REFERENCE_FILE: \$\{\{ runner\.temp \}\}/sentry-alert-reference\.json' .github/workflows/apply-sentry-infra.yml` → `1`; `grep -cE '^\s+jq -S --arg side tf -f .*sentry-alert-projection\.jq" /tmp/sentry-apply-plan\.json' .github/workflows/apply-sentry-infra.yml` → `1`.
12. `grep -c '28 adopted' .github/workflows/scheduled-sentry-alert-drift.yml` → `0`; `grep -c 'a migrated Sentry alert has drifted from the committed capture' .github/workflows/scheduled-sentry-alert-drift.yml` → `1` (the single `env:` definition).
13. `actionlint .github/workflows/apply-sentry-infra.yml .github/workflows/scheduled-sentry-alert-drift.yml` → no findings beyond the pre-existing info-level baseline (`SC2016` markdown-backtick prose in `printf '…'` bodies — 11 on `main`'s drift workflow, 14 after the three new body lines; two `SC2086` on the apply workflow, both present on `main`). CI's actionlint job asserts termination only (#7002); driving SC2016 down is #7042.
14. `bash scripts/test-all.sh` sentry group (or CI `test-scripts`) green including the new suite; `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` → 0 violations; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` → OK; `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-11-fix-apply-sentry-infra-red-on-main-plan.md` → no FAIL lines.
15. `bash plugins/soleur/test/c4-model-freshness.test.sh` → green after `bash scripts/regenerate-c4-model.sh`; `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` → green; `grep -c "plan-derived reference (#8050)" knowledge-base/engineering/architecture/diagrams/model.c4` → `1`; `grep -c "adoption capture was taken" knowledge-base/engineering/architecture/diagrams/model.c4` → `0`.
16. `grep -c "\[2026-09-11 — #8050\]" knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` → `1`; `grep -c "phase2-live-workflows-capture" apps/web-platform/infra/sentry/README.md` → `0`; `grep -c "has no Terraform access" apps/web-platform/infra/sentry/README.md` → `1`.
17. **(evidence)** Live probe (Phase 7.1) → exit 0, stdout `sentry_alert live fidelity: PASS (all 29 in-scope rules match the committed reference field-for-field)`, no `FIXTURE` token, no `refusing to send the IaC token` line.
18. **(evidence)** Phase 7.2 dispatch → run `success`; step `file_unavailable` `skipped`; log contains no `refusing to send the IaC token`; `gh issue view 8057 --json state` and `gh issue view 8058 --json state` → CLOSED (or, on a real unrelated drift, #8057 OPEN with a new comment and a triage issue filed — documented outcome).
19. **(evidence)** `plan_pr` on the PR: `0 to destroy`, reference gate `PASS`, `sentry-destroy-required` green.
20. PR body contains `Closes #8050`, `Ref #8057`, `Ref #8058`; the PR title contains none of them.

### Post-merge (automatic — no human step)

21. **(evidence)** `gh run list --workflow apply-sentry-infra.yml --branch main --limit 1 --json conclusion,headSha,event` → `{"conclusion":"success","event":"push","headSha":"<merge SHA>"}`; step 15's log contains `PASS (all 29 in-scope rules`.
22. **(evidence)** `gh issue view 8050 --json state,stateReason` → `CLOSED`, `COMPLETED`.
23. **(evidence)** The next scheduled drift run (07:15 UTC) concludes `success` with `verdict=clean`; `gh issue list --label ci/sentry-alert-drift --state open` → empty.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly at first — the failure surface is the operator's alerting plane. The worst broken state is a projection or gate that reports PASS while comparing nothing (vacuous), so a paging rule that is later edited through Sentry's own UI and goes dark — `byok-art-33-breach` among them — is not noticed, and a BYOK-key exposure event for a specific user is never escalated inside the notification window the rule exists to start: GDPR Art. 33's 72 hours, and the tighter **24-hour** commitment in `knowledge-base/legal/2026-08-06-alpha-tester-processing-annex.md` §8.1. **If this does NOT land**, the control is already degraded: a probe that is red every day on a known false positive trains the reader to ignore it, which is functionally the same outcome as a dark rule (CPO finding).

**If this leaks, the user's [data / workflow / money] is exposed via:** the committed `alert-reference.json` carries rule names, tag keys/values, thresholds and a detector id — configuration, not customer data, and every one of those values is already public in `issue-alerts.tf` of this public repository, so the reference discloses nothing new (logged as a known-disclosure line item for the CLO, not a change). The probe's live GET carries the write-capable IaC bearer token, used read-only; this PR adds `--disable --noproxy '*'` and exact-equality host/org pins to that call, narrowing (never widening) where the token can be sent. No customer-facing alerting claim is derived from this fix (CPO note).

**Brand-survival threshold:** `single-user incident` — inherited from the #7650 plan that introduced this probe (`brand_survival_threshold: single-user incident`), because the probe is the only control that notices `byok-art-33-breach` matching nothing. `requires_cpo_signoff: true` (granted with notes, below); `user-impact-reviewer` runs at review time; plan-review ran the five-agent panel.

- threshold rationale: every anti-vacuity floor in the probe and the gate is asserted by a mutation row (Guard Contract), so "PASS having compared nothing" is a tested-unreachable state, not a hoped-for one.

## Domain Review

**Domains relevant:** engineering, product

### Engineering

**Status:** reviewed
**Assessment (CTO, blocking Task on the written plan):** verdict "proceed with changes". HIGH: the derived `triggers.logicType` rule was a migration artifact — the provider hard-codes `any-short` on every create/update (verified against `resource_alert_impl.go` 803/835 at v0.15.7), so a single-trigger rule edit would have redded `main` again with a false `LOGICTYPE FLIP`; folded as the single-trigger constant on both sides (Phase 1.1, 2.1) with a suite row (5.1 g/h). MEDIUM: Optional+Computed `enabled`/`trigger_conditions`/`conditions` can be unknown for a create row that omits them — folded as type floors in the projection (1.1) with an M9 row. MEDIUM: the verdict-gated filer must carry `!cancelled()` — folded (4.1, W8). LOW: `secrets.SENTRY_ORG`/`SENTRY_API_HOST` are repo-level, so the 7.2 dispatch proves the exact values the apply job sees; criteria 17 and 18 assert no refusal line. LOW: trust boundary is right — `strict_required_status_checks_policy = true` closes the concurrent-PR race at PR time; no new ADR needed. LOW: `canon` before `sort_by` — folded (projection `normalise`).

### Product/UX Gate

**Tier:** advisory (no UI surface; sign-off required only by the `single-user incident` threshold)
**Decision:** reviewed
**Agents invoked:** cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

- **CPO sign-off: granted with notes.** Framing correctly names the single-user Art. 33 failure; `single-user incident` is the right threshold and must not be downgraded (a BYOK key is one customer's own vendor credential; the alpha-tester annex §8.1 commits to 24-hour notification). Both notes folded into `## User-Brand Impact`: the "if this does NOT land" degraded-control case, and the §8.1 citation.
- Ship as an internal CI fix; no trust-page or docs copy makes an alerting claim, so nothing to announce or correct, and no customer-facing "we monitor" claim may be derived from this.
- Known-disclosure line item (accepted): `alert-reference.json` exposes rule names and thresholds in a public repo — already public in `issue-alerts.tf`.

### Scoped advisor consult (Step 4.5, `model: fable`)

Verdict: the Terraform-derived reference is the right shape. Applied: the known-at-plan-time measurement (Phase 0.5) with a fail-closed outcome; both normalisations as named tables in one module; the drift-workflow gate fix as its own early commit. Its golden-anchor suggestion was superseded at plan review (both panels fired on the ledger it needed; see Cut List).

## Plan Review Revisions (five-agent eng panel + CTO devex lens)

Mechanical findings applied in this revision: provider-constant logicType normalisation (CTO-1, Kieran); unknown-leaf type floors instead of an `after_unknown` traversal (CTO-2, simplicity, DHH-8, spec-flow-14); `!cancelled()` (CTO-3, Kieran-9); `canon` before `sort_by` and a shared `normalise` applied to both sides (CTO-6, Kieran-4, Kieran-6); duplicate-name floor (Kieran-7); `set -uo pipefail` + rc-on-own-line (Kieran-8); W8 selects by `id: file_unavailable` (Kieran-1); AC7 fixture literal (Kieran-3, spec-flow-15); AC11 site-anchored counts (Kieran-5); AC9 via `SENTRY_DRIFT_WF` and in-suite mutation rows (Kieran-11); "28 adopted" at three sites (Kieran-12); baseline line removal (Kieran-13); `git grep -nw` (Kieran-14); live `PROJECT` moved into the shared module (Kieran-15); concrete AC10 (Kieran-16); expected file to step summary + artifact (spec-flow-5); excluded-trigger error in the projection (spec-flow-6); Phase 0.1 STOP scoped to `sentry_alert` rows (spec-flow-4); `filed != 'true'` arm (spec-flow-10); TITLE hoisted and unchanged, W9 (spec-flow-11, arch-2); pin-mismatch outcome via `gh secret set` (spec-flow-12); non-clean 7.2 outcome (spec-flow-13); `model.likec4.json` regeneration (arch-1); detectorIds hint (arch-4); `#4419` comments (arch-5); "write-capable token used read-only" wording (arch-6); PR closes only #8050, 7.2 runs immediately before merge (arch-3, spec-flow-3); alternatives table trimmed to three rows (DHH-10); README sentence on why the committed file exists (DHH-9).

Both-panels-fired scopes, deleted per the plan-review rule: the pre-apply gate copy in the `apply` job (DHH-1/2 + spec-flow-1), replaced by the apply job projecting its own reference; the golden-anchor row, `GOLDEN_KNOWN_DIVERGENCES`, and the inverse `_api_shape` helper (DHH-3 + simplicity-f + Kieran-2/spec-flow-7).

Taste / user-challenge items (headless — persisted to `knowledge-base/project/specs/feat-one-shot-8050-apply-sentry-infra-red-on-main/decision-challenges.md`): keep the #7997 fold-in (DHH-4 wanted it out of scope; simplicity and the lint's `--changed` scope want it in — kept); amend ADR-031 rather than open a new ADR (architecture-strategist advisory); keep the `on.push.paths` entries for the gate and the module (simplicity: consistency; arch: agree).

## Observability

```yaml
liveness_signal:
  what: apply-sentry-infra.yml post-apply probe on every merge to the Sentry root (reference projected from the applied plan), and scheduled-sentry-alert-drift.yml daily (Inngest-dispatched, committed reference) — both run scripts/sentry-alert-live-fidelity.sh and print `PASS (all N in-scope rules …)` or `live fidelity FAILED`
  cadence: per merge touching apps/web-platform/infra/sentry/** or the gate/module paths; daily 07:15 UTC
  alert_target: GitHub issues labelled ci/apply-sentry-infra (apply) and ci/sentry-alert-drift (daily); the daily job's Sentry cron check-in `scheduled-sentry-alert-drift` (ok|error) is the dead-man's switch for "the run never happened"
  configured_in: .github/workflows/apply-sentry-infra.yml (plan step projection, post-apply probe step, tracking-issue filer), .github/workflows/scheduled-sentry-alert-drift.yml (probe / file_drift / file_unavailable / close steps / heartbeat)
error_reporting:
  destination: GitHub issue filer steps (p1, deduped by label + hoisted TITLE env) + the daily job's Sentry cron monitor status; `::error::` annotations; the reference gate's expected document in $GITHUB_STEP_SUMMARY and an uploaded artifact
  fail_loud: yes — every floor in the projection, gate and probe exits 1 with a named reason; the gate reds the required `sentry-destroy-required` check at PR time
failure_modes:
  - mode: committed reference stale vs .tf (rule added/edited/removed without regeneration)
    detection: scripts/sentry-alert-reference-gate.sh in plan_pr (PR red, expected file in summary + artifact); on a merge that bypassed plan_pr, the daily probe's UNMANAGED/DELETED finding names the regeneration remedy
    alert_route: required check on the PR; ci/sentry-alert-drift issue
  - mode: live rule drifted through Sentry's own UI (disabled, retagged, unbound, deleted, multi-trigger logicType flipped)
    detection: sentry-alert-live-fidelity.sh finding classes DISABLED / DRIFT / MONITOR UNBIND / DELETED / LOGICTYPE FLIP
    alert_route: ci/sentry-alert-drift issue (daily) or ci/apply-sentry-infra issue (post-apply)
  - mode: live in-scope rule the root does not declare
    detection: sentry-alert-live-fidelity.sh UNMANAGED (reverse direction, meaning "undeclared")
    alert_route: same issues as above
  - mode: probe could not run (secret cleared, pin refusal, pagination ceiling, non-array payload, reference unreadable/wrong shape)
    detection: probe exits 1 without the FAILED marker → verdict=unavailable
    alert_route: "the drift probe could not establish a verdict" issue — filed only on verdict unavailable/empty, or drift-not-filed, never on cancellation (Phase 4.1)
  - mode: projection, gate or probe vacuous (compared zero rules, unknown leaf, duplicate name, excluded trigger)
    detection: explicit floors in the module, gate and probe; each floor has a RED mutation row in the suites
    alert_route: CI test-scripts job on the PR; in the apply job a projection failure reds the plan step BEFORE the apply and the unconditional `if: failure()` filer opens/comments the ci/apply-sentry-infra tracking issue with the new Plan/Apply/Probe outcome line
logs:
  where: GitHub Actions run logs (apply job plan + step 15; drift job probe step), $GITHUB_STEP_SUMMARY, the expected-reference artifact on a red plan_pr; issue bodies carry the verbatim probe output
  retention: Actions default (90 days); issues permanent
discoverability_test:
  command: bash tests/scripts/test-sentry-alert-reference-gate.sh
  expected_output: every row `[ok]`, final line reporting pass count == EXPECTED_TESTS and 0 failures (exit 0)
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-031** (not a new ADR): the decision "Terraform is the source of truth for Sentry alert rules" is unchanged; what changes is the probe's reference provenance ("committed live capture" → "projection of the plan being applied; committed copy for the daily job, gated equal to the plan"). Dated note per the file's convention (Phase 6.2). Rejected alternatives recorded in the note: keep the live capture (a rule cannot be live-captured before it is applied — measured twice: #7772/#7985, #7989/#8050); daily job reads state (R2 credentials for the shared bucket in a cron job). The architecture-strategist's advisory that this could be its own short ADR is recorded as a taste item; the amendment is proportionate for a provenance change under an unchanged decision.

### C4 views

All three model files were read (`model.c4`, `views.c4`, `spec.c4`). Enumerated for this change: external human actor — the operator paged by `sentry -> founder` (modelled); external systems — Sentry (`sentry = system "Sentry"`), GitHub Actions as applier/emitter (`github -> sentry`), both modelled; data stores — none new (the reference is a repo file under the Sentry root, covered by the `sentry` description's mention of `apps/web-platform/infra/sentry/`); access relationships — unchanged. **One edge description is falsified by this change and was already stale:** `sentry -> founder` ("27 are `sentry_alert` … 3 stay behind … landed after the adoption capture was taken"). Phase 6.3 corrects the split to 29 + 2 and replaces the capture mention, regenerates `model.likec4.json` (`c4-model-freshness` is CI-required), and runs `c4-code-syntax.test.ts` + `c4-render.test.ts`. No view `include` changes: no new element. The `c4-count-parity.test.sh` named by the plan skill does not exist in this repo.

### Sequencing

None — true the moment the module, reference and gate merge; no soak.

## Guard Contract

### Guard 1 — `sentry-alert-reference-gate.sh` (committed reference == plan)

**Property.** For every `sentry_alert` the Sentry root declares, the committed `alert-reference.json` carries exactly the projection of that resource's planned values, and carries nothing else.

**Assembly.** The chokepoint is the plan document `terraform show -json tfplan` of the FULL root, produced by one command form in `plan_pr` (`/tmp/sentry-pr-plan.json`). Members flow through `(.planned_values // .values).root_module.resources[] | select(.type=="sentry_alert")` — one access path; a second injection site would be a child module, which the projection refuses. One call site (`plan_pr`), non-suppressing (the guard block re-arms `set -e`; the gate itself is `set -uo pipefail` with rc checked after every jq). The `apply` job does not consume the committed file at all (it projects `/tmp/sentry-apply-plan.json` itself), so the property's blast radius is the daily job's reference.

**Mutation matrix.** Each row MUST drive the gate RED:

| # | Edit (synthetic two-rule plan + its projection as reference) | Expected |
|---|---|---|
| M1 | Add a third `sentry_alert` to the plan, reference unchanged | RED: `ADDED in .tf, missing from reference: <name>` |
| M2 | Change one `event_frequency_count.value` in the plan | RED: leaf `<name>.triggerConditions….comparison.value: planned=… reference=…` |
| M3 | Remove a rule from the plan, reference unchanged | RED: `REMOVED from .tf, still in reference` |
| M4 | Plan with three rules where the first two match and the third differs | RED naming only the third (the comparison covers every member) |
| M5 | Plan with zero `sentry_alert` resources (own-dispatch row) | RED: floor "projection yielded 0 rules"; never `PASS (0 rules` |
| M6 | Reference replaced by an API-shaped capture (array) | RED: `not a name-indexed projection object` before comparison |
| M7 | Flip `enabled` true→false in the reference | RED: `enabled: planned=true reference=false` (renders `false`, not `<absent>`) |
| M8 | Plan with a `child_modules` entry holding a `sentry_alert` | RED: `child_modules` |
| M9 | Plan create row with `enabled` omitted (unknown at plan) | RED: `enabled is not a boolean` |
| M10 | Plan rule whose trigger type is in the excluded list | RED: `outside the probe's live scope` |
| M11 | Two resources with the same `name` | RED: `duplicate sentry_alert name` before `INDEX` |
| M12 | One condition element with two non-null keys | RED: `exactly one non-null key` |

**Must-PASS (non-canonical) rows:** G0 (the positive control); reference with BOTH array elements reversed AND the keys inside every `comparison` reversed → PASS (`normalise` on both sides — F13's key-only reversal would not exercise array order); a `terraform show -json` STATE document (`values`) for the same two rules → PASS against the same reference; a reference whose only difference is trailing whitespace/indentation → PASS. Negative twin of the reorder row: swap `comparison.value` between the two-condition rule's conditions → RED on `comparison.value` (data, not order).

**Harness row:** (H2) point the suite's `PLAN` fixture at an empty file → every row reports FAIL, none `[ok]`. The count floor (`EXPECTED_TESTS`) is inherited from the sibling suites and is not restated as a row: a suite that runs a mutated copy of itself recurses.

### Guard 2 — probe reverse direction, reference-shape floor, and pins (`sentry-alert-live-fidelity.sh`)

**Property.** A live in-scope rule absent from the reference, or a reference in the wrong shape, can never yield a PASS line; the IaC token is never sent to a host other than the pinned literal.

**Assembly.** One live fetch (`fetch_rules`: fixture branch, then pins, then one `curl`), one projection module invoked with `side=live` and `side=reference`, one PASS site after both direction loops.

**Mutation matrix.** Each row MUST drive the probe RED (exit 1, no `PASS` line) or refuse:

| # | Edit | Expected |
|---|---|---|
| P1 | Live fixture gains an extra in-scope rule not in the reference | `UNMANAGED: '<name>' … declared nowhere` |
| P2 | Reference minus one rule (live fixture unchanged) | that rule `UNMANAGED`, after compliant earlier rules |
| P3 | API-shaped capture passed as the reference | `not a name-indexed projection object` before any comparison; no `PASS` |
| P4 | Reference `{}` (own-dispatch row) | `ZERO in-scope rules`, never `PASS (all 0` (reachable: `shape_ok` is not a cardinality check) |
| P5 | `SENTRY_API_HOST=evil.example`, token and org set, no fixture, recording `curl` shim on `PATH` | `is not the pinned Sentry API host` before the GET; the shim records zero invocations |
| P8 | Reference with one rule's `triggerLogicType` key deleted | `not a name-indexed projection object` |
| P9 | `comparison.value` swapped between two conditions of a five-condition rule | `DRIFT … comparison.value` (order-insensitive, data-sensitive) |
| P6 | Live fixture flips one rule's `enabled` to `false` | `DISABLED: '<name>'` |
| P7 | Three-trigger rule's live `triggers.logicType` mutated to `all` | `LOGICTYPE FLIP` |

**Must-PASS (non-canonical) rows:** F13's API-shaped fixture with server fields → `PASS (FIXTURE — not live) (all N …)`; a single-trigger rule with live `logicType` mutated `all → any-short` → PASS (no FLIP: both sides project `single`); fixture with array elements and object keys reordered → PASS; with the host equal to the literal, the `curl` shim sees `$1 == --disable`, `--noproxy '*'`, `--header @-`, serves the capture, and the probe prints `PASS (all 28`; the tf/live shape-parity row (5.1 i) PASSes on the committed reference.

**Harness row:** (H4) `_mutant` applied with a selector that matches nothing returns `NOOP` and the row FAILs on "edit did not land" rather than passing an identity comparison.

### Guard 3 — drift-workflow dead-man's-switch gate (W8) and title parity (W9)

**Property.** The probe-unavailable filer's `if:` is satisfiable only by a verdict of `unavailable`, an empty verdict, or a `drift` verdict whose filer did not post — and never on a cancelled run; the drift TITLE used to file, dedupe and close is one string.

**Assembly.** The single step with `id: file_unavailable` in `jobs.drift-check.steps` (W8 asserts exactly one) and its closer ("Close the probe-unavailable issue", gated on `(verdict, filed)`); the job-level `env.DRIFT_TITLE` referenced by the filer and the drift close step (W9 asserts both references resolve to the same key).

**Mutation matrix.** Each row MUST drive W8/W9 RED (in-suite, against a `sed`-mutated temp copy of the workflow):

| # | Edit | Expected |
|---|---|---|
| W8-a | Restore `if: always() && failure()` | RED: `failure()` present / named verdicts absent |
| W8-b | Drop the `== ''` arm | RED: aborted-before-probe runs would file nothing |
| W8-c | Drop `!cancelled()` | RED: a cancelled run would file a false issue |
| W8-d | Remove `id: file_unavailable` (selector matches zero steps) | RED: selector floor "expected exactly one step" |
| W8-e | Drop the `filed == 'true'` conjunct from the probe-unavailable CLOSER's `if:` | RED: the closer would undo the filer's `drift`-not-filed arm in the same run |
| W9-a | Inline a differing title literal in the close step | RED: filer and closer titles diverge |

**Must-PASS (non-canonical) row:** the shipped expression with extra whitespace and the disjuncts in another order (the suite collapses whitespace before matching). Runtime semantics the text assertion cannot see — a skipped/never-run step's output comparing equal to `''` — rest on GitHub's documented loose-equality coercion (both sides cast to a number: `null` → 0, `''` → 0; https://docs.github.com/en/actions/reference/workflows-and-actions/expressions) and on `failure()` being job-scoped ("returns true if any previous step in the job fails"), which is exactly why the old gate fired.

## Risks & Mitigations

- **Projection mismatch on a rule shape not present today** (a non-email action, a new condition type): the module maps what the measured 29 rules exercise and `error`s on an element with ≠1 non-null key or an excluded trigger. A future rule with a new shape fails the PR gate loudly with the expected file printed — not `main`.
- **Provider behaviour changes** (a future version exposes or changes trigger logicType): the single-trigger constant is safe under any provider (one condition has no logic); a multi-trigger flip is still reported. The projection header cites the provider source lines so the assumption is re-checkable at each provider bump.
- **Pin literal vs the GitHub secret value.** Doppler `prd` matches; the repo secret is proven by the 7.2 dispatch before merge, and the remedy (`gh secret set SENTRY_API_HOST --body …`) is defined.
- **Cross-PR reference race.** Closed at PR time by `strict_required_status_checks_policy = true` (the second PR must rebase and `plan_pr` re-runs). A `merge_group` merge inherits that PR-time verdict; if a stale copy ever reaches `main`, the apply job is unaffected (it projects its own reference) and the daily job files one drift issue naming the regeneration remedy.
- **`plan_pr` heavy plan on a reference-only or gate-only PR.** Accepted: exactly the PR class where a plan is informative; same cost as the existing `.jq` `paths:` entry.
- **Read-after-write race in the close step** (observed on #8058): unreachable after 4.1 (disjoint verdict gates); not patched with a sleep.
- **Local read-only plan against prod state (Phase 0.1/0.5/1.2)** acquires the state lock briefly; run once, not concurrently with a CI plan.
- **The 07:15 run before merge re-files a drift issue against the stale capture.** Bounded: the first clean daily run after merge closes it (7.5); 7.2 runs immediately before merge so #8057/#8058 are closed by the mechanism on the freshest evidence.
- **Old run stays red in history.** Acceptable; "red on main" is the newest run's conclusion.

## Test Scenarios

1. `bash tests/scripts/test-sentry-alert-reference-gate.sh` — G0, Guard 1 M1–M12, must-PASS rows, H2, show-state identity.
2. `bash tests/scripts/test-sentry-alert-live-fidelity.sh` — existing 13 drift classes on the frozen capture + Guard 2 rows P1–P9, must-PASS rows, H4.
3. `bash tests/scripts/test-sentry-alert-drift-workflow.sh` — W1–W7 + W8 (with W8-a..e in-suite) + W9.
4. Phase 0.2 parity (28/28, 0 mismatches), 0.5 `after_unknown` key list, 0.6 provider grep — recorded in the PR body.
5. Live probe PASS 29/29 (7.1); drift-workflow branch dispatch `clean` immediately before merge (7.2).
6. `plan_pr` on the PR: gate PASS, `0 to destroy`.

## Non-Goals

- Migrating the two surviving `sentry_issue_alert` rules (blocked on upstream provider 950; #7985).
- Re-shaping `sentry-adoption-plan-assert.sh` or the Phase 2/3.4 captures (history, self-skipping, frozen fixture).
- The `sentry-monitors-audit.sh` rows of #7997 (region-discovery design question; stays open).
- Cursor-following pagination in the probe (ceiling 100; org has 32 workflows).
- Adding the Sentry root to `scheduled-terraform-drift.yml` (deliberately not — README §Drift detection explains the brownout exposure).
- A new ADR for the reference-provenance change (recorded as a taste item; ADR-031 amendment chosen).

## Sharp Edges

- The plan's `## User-Brand Impact` section must keep its three lines and the `single-user incident` threshold; `deepen-plan` Phase 4.6 halts when the section is empty or filler.
- Do not "tidy" the two remaining phase34-capture arguments to `sentry-adoption-plan-assert.sh` into the new reference: that script expects the API-shaped capture as its bijection source and self-skips.
- Do not make the `apply` job read the committed `alert-reference.json`: the apply job projects its own reference from `/tmp/sentry-apply-plan.json`; the committed file exists for the daily job only.
- The probe's PASS/FAIL literals (`live fidelity FAILED`, `PASS (all `, `PASS (FIXTURE — not live) (all `) are a contract with two workflows (W7). Reword around them, never inside them.
- The drift issue TITLE literal is a three-site dedupe/close key; hoist it, never rename it (W9).
- `--disable` must be curl's LITERAL FIRST argument; `curl -fsS --disable` satisfies neither the lint nor curl.
- Keep the pins inside the live branch of `fetch_rules`, after the fixture `return`, or every fixture row in the suite fails on `SENTRY_ORG=fixture`.
- Never run the probe under `bash -x` with a real token (#7797 — it refuses with exit 78).
- The forensics artifact is prod state: read it in the scratchpad, never commit it or a derived fixture.
- `canon` before `sort_by(tostring)`, on every side, or a hand-built fixture with `{value, interval}` key order sorts into a different array position than the live side.
