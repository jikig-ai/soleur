---
title: "infra(github): a prd_terraform-planted integration id must not rebind the required checks in place"
date: 2026-10-10
slug: github-ruleset-required-check-integration-id-rebind
branch: feat-one-shot-9362-tf-var-integration-id-rebind
issue: 9362
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Plan: close the tf-var rebind path in apply-github-infra (Refs #9362, #8209, #8609)

## Enhancement Summary

**Deepened on:** 2026-10-10. **Method:** the seven-reviewer plan-review panel already ran on this plan, so the deepen pass was spent on verification rather than a second fan-out: the halt gates (4.6 to 4.12) were run mechanically, and the forward direction the review flagged as "argued, not run" was run in a scratch clone.

- Wrapper deletion applied to a scratch clone of this branch (four `doppler run` prefixes removed): `tests/scripts/test-infra-privileged-tier-census.sh` 296 passed 0 failed; `tests/scripts/test-apply-github-infra-mint-shape.sh` 9 passed 0 failed; `test-destroy-guard-regex-parity.sh`, `test-destroy-guard-counter.sh` and `test-audit-ruleset-bypass.sh` rc 0; `lint-shell-trace-credential-refusal.py` OK with the rule-E baseline unchanged.
- Gates: User-Brand Impact present with a valid threshold; Observability present, probe verb allowlisted with no shell-active character; PAT-shape sweep none; Guard Contract lint green (2 entries); Scope Check exactly one unfenced section; no encryption-posture trigger (no `.tf` in the file lists); no UI surface; no downtime-class operation.
- Citations: the one rule id cited is active; #9360 is merged, #9893, #9361, #9466, #8609, #9394, #9791, #8800, #8659, #7942 are open; no SHA or version is cited.
- No contradictions found between the Decision table, Phase 3, Guard 2 and the tasks file.

## Overview

`apply-github-infra.yml` wraps four Terraform invocations in
`doppler run -p soleur -c prd_terraform --name-transformer tf-var`. A value planted in that Tier-A
config for `ACTIONS_INTEGRATION_ID`, `CODEQL_INTEGRATION_ID`, `GH_OWNER` or `GH_REPO` overrides the
`infra/github/variables.tf` default. The two integration ids feed `required_check.integration_id` on
the CI and CLA rulesets, so a planted id rebinds the required checks to another integration as an
in-place ruleset update, which the destroy guard (deletes only) and the post-apply verify (it echoes
counts and asserts nothing) both pass.

**PR-body first line (required):** `No apply runs on merge: this PR touches no path in apply-github-infra.yml on.push.paths and none in any other workflow's push filter, so no ruleset is mutated.`

## Decision: which of the three candidate fixes

Property list (Phase 0.6b):

- P1. A value in a Tier-A config cannot change what the apply writes to the rulesets.
- P2. If the required-check bindings about to be written differ from the committed canonical, the apply stops before any write.
- P3. Re-adding a Tier-A injection to this job is a red CI check, not a silent regression.

| Candidate | Verdict | Why |
|---|---|---|
| 3. "O11 closes it" | **Rejected: does not cover it** | O11 ran on 2026-10-04 (#8209 comment): it deleted repo secrets `DOPPLER_TOKEN_GIT_DATA_ROOT` and `DOPPLER_TOKEN_WRITE` and revoked two tokens. #8209 still lists #9362 as open after O11, and ADR-241's 2026-10-01 amendment records the tf-var layer as "pre-existing, unchanged". `prd_terraform` stays Tier A by D1 (PR plan jobs need it), so no O-step removes the path. |
| 2. `--only-secrets` allowlist | **Right idea, wrong form: take it to its limit** | The set this root needs from `prd_terraform` is empty. In infra mode every provider input arrives from the Tier-B loader as `TF_VAR_github_infra_app_*`, the backend keys are extracted into `GITHUB_ENV` by a separate step, and every other variable has a default. An allowlist needs an invented name plus `--no-exit-on-missing-only-secrets`, and `knowledge-base/project/learnings/2026-03-21-doppler-tf-var-naming-alignment.md` records that `--only-secrets` combined with `--name-transformer tf-var` fails (lookup is by original name after the rename). So delete the injection (P1) instead of filtering it. |
| 1. by-value assertion | **Adopt, pre-apply only** | A post-apply check detects after the write, and the daily Inngest cron `cron-ruleset-bypass-audit` already compares both rulesets' live checks by value against the same two canonical files. A **pre-apply** gate on `terraform show -json tfplan` (P2) prevents the write and is the safety net for the wrapper deletion. The post-apply live check the issue names is cut (see Cut List); the plan-review panel split on which single mode to keep, and pre-apply wins because it is the only one that prevents. |

Cut List: job-level `env:` pins of `TF_VAR_*` (the issue's own rejection: they override future `variables.tf` defaults); a `validation {}` block in `variables.tf` (touches `infra/github/*.tf`, the apply trigger, and hard-codes the id); a post-apply live mode and a verify-step edit (duplicates the daily audit; keeps the verify step, its token-holder pin and #9893's coupling untouched); touching `tests/scripts/lib/destroy-guard-filter.jq` (also a trigger path); a new test suite and its registration plumbing (the checks join the existing, registered mint-shape suite); an `--only-secrets` allowlist (above).

**Scope of the gate, stated plainly:** it compares `{context, integration_id}` of the two rulesets' required checks and nothing else. `GH_REPO` and `GH_OWNER` are closed by the removal (P1), and a changed `repository` would still be a resource-level delete the destroy guard counts. The gate is not a general ruleset-equality check.

## Research Reconciliation: issue vs repo

| Issue / brief claim | Reality | Plan response |
|---|---|---|
| Verify "asserts the required-check count (24 / 2)" | The verify step only echoes both counts and asserts nothing. CI is also stale: `CodeQL` left the ruleset in #9454, the canonical holds 23 rows (CLA: 2). | No number is hard-coded; the canonical file is the only source. The verify step is left as is. |
| Candidate 3: O11 closes it | O11 is done and did not (above). | Rejected. |
| "GH_REPO ... expected to force replacement" | Moot once the injection is gone. | No provider-schema work. |
| Daily audit not mentioned | `cron-ruleset-bypass-audit.ts` audits both rulesets by value daily (CLA via `CLA_AUDIT_CONFIG`); `scripts/audit-ruleset-bypass.sh` is the CI-ruleset-only script form. | It stays as the independent after-the-fact detector; the new gate prevents the write. |
| Terraform "reads Tier A" | The job already runs under `environment: infra-privileged` with Tier-B loader values; only the wrapper reads Tier A. | Delete the wrapper in the four steps; the two backend-key reads stay. |
| (own claim, corrected by review) "a non-default `prd_terraform` value would be refused by the gate" | False: with the wrapper gone the effective id is the default, which equals canonical, so the gate passes. | Replaced by the measured proof below. |

## Implementation Phases

Failing tests first (cq-write-failing-tests-before); one PR.

### Phase 1 — failing checks in the existing suite

Extend `tests/scripts/test-apply-github-infra-mint-shape.sh` (already registered, already parses this workflow's `apply` job with a `row` mutation helper, an instrument self-test and a `MIN_ASSERTIONS` floor; its header and floor are updated, its name stays). Add (a) Guard 2 checks to its parsed-YAML `check.py` with named reasons and rows, and (b) a gate-script section driving `scripts/verify-ruleset-required-checks.sh` over fixtures. Plan-shaped fixtures are built at run time with `jq` from `tests/scripts/fixtures/tfplan-real-ruleset-baseline.json` (a real `terraform show -json` capture, so the real nesting, set typing and `no-op` `after` are preserved) with `required_check` replaced from the canonical files. Run red first.

### Phase 2 — `scripts/verify-ruleset-required-checks.sh`

```text
verify-ruleset-required-checks.sh <plan.json|-> <resource-address> <canonical.json>
```

- Reads all of stdin (or the file) before anything else, so an early exit never SIGPIPEs `terraform show`; empty input is exit 2.
- Sources `scripts/lib/canonicalize-required-status-checks.sh` (`map({context, integration_id}) | sort_by(.context)`).
- Selects `.resource_changes[] | select(.address == $addr)`; exit 2 if the address is absent, `.change.after` is null (a delete) or the projected set is empty. Reads `.change.after.rules[]?.required_status_checks[]?.required_check[]?`; a null `integration_id` is a mismatch.
- Validates the canonical (non-empty array, string `context`, number `integration_id`, unique `context`), then compares the two sets whole. Exit 0 and `OK: <address>: N/N required checks match the canonical by value`; exit 1 printing each differing row as `-`/`+` (context and id only); exit 2 on usage or malfunction. jq stderr goes to `/dev/null` (a parse error quotes input fragments); no `set -x`; no secret in argv.

### Phase 3 — `apply-github-infra.yml` (narrow hunks, no `on:` change)

1. Header comment: replace the sentence saying the tf-var layer still injects the sentinel with one saying the job injects nothing from `prd_terraform` (avoid writing the literal `--name-transformer` there, the probe below greps for it).
2. Import steps, `Terraform plan`, `Terraform apply`: delete the four `doppler run ... --` prefixes and the now-unused step `env: DOPPLER_TOKEN` on those three steps. Keep `set +e`/`rc=$?` in the plan step and the `tee` in the apply step byte-stable.
3. New step `Gate planned required-check bindings (by value, pre-apply)` between plan and apply, `working-directory: ${{ env.INFRA_DIR }}`, `set -euo pipefail`, no `set -x`: `terraform show -json tfplan | bash "${GITHUB_WORKSPACE}/scripts/verify-ruleset-required-checks.sh" - github_repository_ruleset.ci_required "${GITHUB_WORKSPACE}/scripts/ci-required-ruleset-canonical-required-status-checks.json"`, then the same for `cla_required` with the CLA canonical (absolute `${GITHUB_WORKSPACE}` paths because the step runs in `infra/github`). The plan JSON carries input-variable values including the Tier-B key, so it is piped and never written to disk.
4. Nothing else changes: not the `paths:` filter, the ref conjunct, the tree-equals-main assertion, the verify step (its stale "Expected count" comment stays), or the revoke step.

### Phase 4 — ownership and record

- `.github/CODEOWNERS`, R15 trust-loop block: add `/scripts/verify-ruleset-required-checks.sh`, `/scripts/ci-cla-required-ruleset-canonical-required-status-checks.json` and `/tests/scripts/test-apply-github-infra-mint-shape.sh` (the guard's pins now live there; a stored canonical editable in the same unreviewed commit as its guard proves consistency, not integrity).
- `scripts/lib/test-affected-paths.sh`: add the new script, the shared lib and both canonicals to `AFFECTED_TESTS_SCRIPTS_APPLY_GITHUB_INFRA_MINT_SHAPE_PATHS` (consumer: `test-all.sh --affected` reads it to select this suite; `lint-orphan-test-suites.sh` reds an unclassified suite). No `test-all.sh` or `.tsv` edit: the suite is already registered.
- ADR-241: a short dated amendment-log entry (see Architecture Decision).
- Follow-up tracking (a deferral without an issue is invisible): file one issue at work time for the two Tier-A tf-var readers left on this root, `scheduled-terraform-drift.yml` (infra/github leg, read-only plan, its comment still says it mirrors the apply's Doppler injection) and the PR plan job, plus the stale local-apply recipe in `infra/github/README.md`. That README is deliberately not edited here: `infra/**` matches `infra-validation.yml`'s push filter.

## Files to Edit

- `.github/workflows/apply-github-infra.yml`
- `tests/scripts/test-apply-github-infra-mint-shape.sh`
- `.github/CODEOWNERS`
- `scripts/lib/test-affected-paths.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`

## Files to Create

- `scripts/verify-ruleset-required-checks.sh`

**Deliberately NOT touched** (each is, or sits under, an auto-apply or validation trigger): `infra/**`, `tests/scripts/lib/destroy-guard-filter.jq`, `apps/web-platform/infra/**`, `.github/workflows/apply-web-platform-infra.yml`, `.github/workflows/apply-inngest-rls.yml`, `scripts/test-all.sh`, the `.tsv` manifests.

## Proof the merge causes no ruleset mutation

1. **Trigger arithmetic.** `apply-github-infra.yml` fires on push to `main` only for `infra/github/*.tf`, `infra/github/.terraform.lock.hcl`, `infra/github/soleur-marketplace-manifest.json`, `tests/scripts/lib/destroy-guard-filter.jq`, or `workflow_dispatch`; the workflow file is not in `paths:`. The architecture review parsed every workflow's push, pull_request and merge_group `paths:` against the planned file set: no match. AC1 repeats it.
2. **No dispatch.** No workflow is dispatched to validate the edit, now or after merge.
3. **The next apply is a no-op on the bindings, measured read-only.** Today, `GET repos/jikig-ai/soleur/rulesets/14145388` and `.../13304872` (GitHub, no Doppler) return 23 and 2 required checks whose `{context, integration_id}` sets equal the two canonical files exactly. The effective ids after this change are the `variables.tf` defaults (15368), equal to live. A planted non-default value could not have been live-applied (live equals canonical), so removing the injection changes nothing. The gate then fails closed on any later divergence.

## Conflict avoidance with draft PR #9893

#9893 edits `apply-github-infra.yml` in one hunk: the final `Revoke the soleur-infra token` step. This plan's hunks (header comment, import/plan/apply steps, one inserted step before apply) are all more than 100 lines from it, and the verify step is untouched, so a textual merge is clean either way and there is no semantic collision with what #9893 asserts about the mint/revoke steps or the shell-trace baseline (rule E counts the revoke `curl`; this PR adds no `curl`). Shared files: only `scripts/lib/test-affected-paths.sh` (one array hunk, at the mint-shape block's own anchor) and `tests/scripts/test-apply-github-infra-mint-shape.sh` (#9893 does not list it). No `.tsv`, no `test-all.sh`. If #9893 lands first and a `merge_group` run fails on a textual conflict, that is not a flake: stop, report to the owner and do not push to the armed PR (the owner decides whether to disarm and rebase).

## Merge protocol (owner constraints)

CODEOWNERS covers the workflow, so the owner reviews. After CI is green: arm auto-merge once, then poll read-only. No `--admin` merge, no `update-branch`, no sync, no push to the armed PR. A `merge_group` failure on an unrelated flake (for example `scripts/test-all-orphan-log-retention`, #9791) gets one re-enqueue, then a report. PR body uses `Refs #9362`, `Refs #8209`, `Refs #8609`, never `Closes`. #9362 stays open until the owner confirms the first live apply: the owner is the confirmer, the trigger is the next natural merge touching `infra/github` paths, and the run link is posted on #9362 (no dispatch is requested). The issue's milestone (`Post-MVP / Later`) and priority (`p1-high`) disagree; the PR body states it for the owner and changes neither.

## Guard Contract

### Guard 1 — by-value required-check gate

**Property.** For the CI and CLA rulesets, the set of `{context, integration_id}` the apply is about to write equals the committed canonical set, row by row, by value.

**Assembly.** Chokepoint: `scripts/verify-ruleset-required-checks.sh` and the shared projection. Quantified over: two rulesets (two exact resource addresses) = two call sites in `apply-github-infra.yml`; two canonical files; one input shape (plan JSON `.resource_changes[]`). The suite derives the call sites from the parsed workflow and requires exactly the two addresses, each paired with its own canonical. The marketplace ruleset is outside the assembly (`scripts/verify-marketplace-ruleset.sh` owns a different property).

**Mutation matrix** (table-driven over positions `first`, `last`, `duplicate` where it applies):

| # | Mutation | Expected |
|---|---|---|
| 1 | one `integration_id` changed to 57789 at first / last row (the attack; last-only proves it does not stop at the first member) | RED |
| 2 | a context renamed / dropped / added | RED |
| 3 | own dispatch: address absent from the plan; `after` null (delete); empty required set; empty stdin; no arguments | exit 2 |
| 4 | canonical malformed: empty, not an array, duplicate context, string id | exit 2 |
| 5 | precondition holds, property fails: action `no-op` (a clean plan) with a rebound `after` | RED |
| 6 | a null `integration_id` where the canonical has a number | RED |

**Harness rows.** The script replaced by a stub that exits 0 must turn the suite RED. Must-PASS inputs that are not the canonical's byte form: rows reordered; extra provider fields on each row; action `update` whose checks equal canonical; the real-fixture nesting.

**Anchor.** CODEOWNERS review of the script, the CLA canonical and the pinning suite (this PR adds them; the CI canonical and the shared lib are already pinned), plus the tree-equals-main assertion that precedes any apply and the existing canonical-vs-`.tf` parity tests. Intended behaviour, for the ADR and not to be removed under pressure: the gate has no override, so a legitimate restore with a disagreeing canonical needs a reviewed canonical fix (the `[skip-github-apply]` kill switch skips the whole job).

### Guard 2 — no Tier-A injection in the apply job

**Property.** The `apply` job of `apply-github-infra.yml` passes no `prd_terraform` value to Terraform.

**Assembly.** Every step of the job, from parsed YAML: any `run:` containing `doppler run`, `--name-transformer`, `doppler secrets download` or a `TF_VAR_` assignment; any `>> "$GITHUB_ENV"` write outside `Extract backend credentials`; any step `env:` naming `DOPPLER_TOKEN` other than exactly `Extract backend credentials` (the verify-secrets step uses `DOPPLER_TOKEN_CHECK`); the `doppler secrets get` names, which must be exactly `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Also: the gate step sits after the plan step and before the apply step, runs two invocations with the exact addresses, uses `${GITHUB_WORKSPACE}` paths, and declares `pipefail`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | the wrapper prefix re-added to the apply step; or only to the second import function, first compliant | RED |
| 2 | `DOPPLER_TOKEN` re-added to the plan step or to the verify-secrets step | RED |
| 3 | a `doppler secrets download ... >> "$GITHUB_ENV"` step added | RED |
| 4 | own dispatch: no `apply` job, or zero steps parsed | RED |
| 5 | gate step removed, moved after apply, one invocation dropped, a relative `scripts/` path, `pipefail` dropped | RED |

**Harness rows.** `row` runs a mutated COPY of the real workflow and requires a named reason; the suite's instrument self-test and floor are kept, with `MIN_ASSERTIONS` raised to the new count. Must-PASS: the real workflow, and a copy with a harmless comment added.

**Anchor.** The pin lives in a CODEOWNERS-covered suite and reads the workflow's own text, so weakening it takes an owner-reviewed edit to both.

## Observability

```yaml
liveness_signal:
  what: the apply job's conclusion plus an ::error annotation naming the ruleset and the differing rows
  cadence: every apply (push to main on infra/github paths, or dispatch)
  alert_target: GitHub Actions run status and the owner's failed-run notification on main
  configured_in: .github/workflows/apply-github-infra.yml (gate step)
error_reporting:
  destination: job log annotations and the step summary
  fail_loud: yes, the script exits non-zero and the step has no continue-on-error
failure_modes:
  - mode: planned bindings differ from canonical
    detection: gate step exits 1 before terraform apply runs
    alert_route: red apply job on main
  - mode: canonical malformed, plan JSON empty or mis-invoked
    detection: exit 2, distinct from a mismatch
    alert_route: red apply job on main
  - mode: a rebind made outside Terraform between applies
    detection: the daily cron-ruleset-bypass-audit (up to a day, after the fact; runbook ruleset-bypass-drift.md)
    alert_route: the audit's drift issue
logs:
  where: GitHub Actions run log (the plan JSON is piped, never written or echoed)
  retention: GitHub default
discoverability_test:
  command: grep -c -e '--name-transformer' .github/workflows/apply-github-infra.yml
  expected_output: 0
```

No SSH; no swallowed catch (every error path exits non-zero).

## User-Brand Impact

- **If this lands broken, the user experiences:** an apply job that goes red on main (a false mismatch) and blocks the next ruleset change, or, worst case, a ruleset check left bound to the wrong integration so an unreviewed pull request can merge into the plugin that installers pull.
- **If this leaks, the user's workflow is exposed via:** the `terraform show -json` plan document, which carries input-variable values including the Tier-B App key; the gate pipes it and never writes or echoes it, and the loader masks the values in the log.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the audit script's own header rates a widened required-check or bypass surface on this ruleset `single-user incident` (one merged malicious skill-install reaches every installer); exploitation needs Doppler write access, which lowers likelihood, not blast radius.

CPO read (plan-review, 2026-10-10): approve with conditions, all folded in above (named confirmer and trigger for the first live apply, the milestone/priority note, CODEOWNERS rows kept). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-241 with one short dated entry (2026-10-10, #9362): `apply-github-infra.yml` no longer injects `prd_terraform`; a pre-apply by-value gate checks the two rulesets' required checks against the canonical files; O11 was evaluated and does not apply; the gate has no override by design. The 2026-10-01 "Pre-existing, unchanged here" bullet is cross-referenced to this entry rather than rewritten. No decision's status changes and no new ADR: this applies D1 (tiers) and D6 (loader values win).

### C4 views

`model.c4`, `views.c4` and `spec.c4` were read for this feature. External actors: none added. External systems: the GitHub rulesets API and Doppler, both already modeled (`github -> doppler` Tier-B edge; `github -> soleurMarketplace` write edge from this workflow). Containers or stores: none. Access relationships: none changed; no tf-var text appears in any C4 description. No C4 impact; `bash plugins/soleur/test/c4-count-parity.test.sh` confirms (AC9).

### Sequencing

Same PR; nothing deferred except the follow-up issue above.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (plan-review panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO, CPO)
**Assessment:** CI/infra change. The credential-tier model (ADR-241 D1/D6) is respected: no Tier-B value moves, no Tier-A value is added, the only Tier-A reads left in the job are the two backend-key reads. No UI, no regulated-data surface, so no GDPR gate and no Product/UX gate.

## Open Code-Review Overlap

- #8800 (census sandbox shares inodes with the live repo) touches `scripts/lib/test-affected-paths.sh`: **Acknowledge**, a different concern.
- #8659 and #7942 touch `scripts/test-all.sh`, which this plan no longer edits: **Acknowledge**.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Plan must first decide which of these is the right fix and whether #8209's O11 already covers it" | Decision section | mapped |
| 2 | "prefer a code/CI-side fix that needs no Doppler value change" | Phase 3 hunk 2, Guard 2 | mapped |
| 3 | "the plan must prove the resulting apply is a no-op (or scope the edit so it does not trigger), and must say so in the PR body's first line" | Proof section, PR-body first line, AC1 | mapped |
| 4 | "Never dispatch any workflow to validate a workflow edit" | Proof item 2 | mapped |
| 5 | "No agent --admin merge on a PR that edits .github/workflows; merge through the queue only" | Merge protocol | mapped |
| 6 | "PR body uses Refs, never Closes, for #9362, #8209 and #8609" | Merge protocol, AC11 | mapped |
| 7 | "Targeted test suites only; CI owns the full battery" | AC list | mapped |
| 8 | "keep your edit regions narrow and say in the plan how a conflict with it is avoided" | Conflict avoidance | mapped |
| 9 | "Do not touch parked PR #9466 or its worktree" | not touched | mapped |
| 10 | [issue #9362] "Have the verify assert each required check's `integration_id` and context by value against a canonical file" | Phase 2, Phase 3 hunk 3, Guard 1 | mapped (pre-apply form; post-apply placement cut, see Decision) |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| Drop the doppler wrapper (Phase 3 hunk 2) | asks 2, 10 [issue candidate 2: "only the names the root needs are injected"] | asked |
| Pre-apply gate script and step | ask 10 | asked |
| Guard 2 pin in the mint-shape suite | — | inferred — justification: without it a later edit re-adds the wrapper with every other test green (P3) |
| CODEOWNERS rows | — | inferred — justification: a canonical editable in the same unreviewed commit as its guard proves consistency only |
| Array edit in `test-affected-paths.sh` | — | inferred — justification: the suite must be selected when the script or canonicals change |
| ADR-241 entry | — | inferred — justification: the recorded "unchanged" status would otherwise go stale |
| Follow-up issue | — | inferred — justification: a deferral without a tracking issue is invisible |

### Split Assessment

- Subsystems touched: 3 (`.github/`, `scripts/`, `tests/scripts/`) plus `knowledge-base/` for the ADR
- Planned files: 6 | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 Trigger proof: `git diff --name-only origin/main...HEAD | grep -E '^(infra/|tests/scripts/lib/destroy-guard-filter\.jq|apps/web-platform/infra/)'` prints nothing, and `.github/workflows/apply-github-infra.yml` appears in no workflow's push `paths:`.
- [ ] AC2 `bash tests/scripts/test-apply-github-infra-mint-shape.sh` passes with every Guard 1 and Guard 2 row present, each mutant row RED before the fix landed, and `MIN_ASSERTIONS` raised accordingly.
- [ ] AC3 `grep -c -e '--name-transformer' .github/workflows/apply-github-infra.yml` prints `0`; the two `doppler secrets get` reads remain.
- [ ] AC4 `bash tests/scripts/test-infra-privileged-tier-census.sh` passes, run against the actual edit (the deepen pass already ran it on a scratch clone with the four prefixes removed: 296 passed, 0 failed; repeat on the real tree).
- [ ] AC5 `bash tests/scripts/test-destroy-guard-regex-parity.sh` and `bash tests/scripts/test-destroy-guard-counter.sh` pass.
- [ ] AC6 `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` and `bash tests/scripts/test-audit-ruleset-bypass.sh` pass; `bash scripts/marketplace-drift-check.test.sh` passes.
- [ ] AC7 The shell-trace credential lint reports no new finding (the workflow's rule-E count stays 1).
- [ ] AC8 With the new file tracked, `bash scripts/lint-orphan-test-suites.sh` reports the suite classified.
- [ ] AC9 `bash plugins/soleur/test/c4-count-parity.test.sh` passes.
- [ ] AC10 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` is clean; ADR-241 carries the dated #9362 entry.
- [ ] AC11 PR body first line is the "No apply runs on merge" sentence; trailers `Refs #9362`, `Refs #8209`, `Refs #8609`; no `Closes`.
- [ ] AC12 The follow-up issue for the remaining Tier-A tf-var readers is filed and linked in the PR body.

### Post-merge

- [ ] None required. The owner confirms the first live exercise of the gate on the next natural `infra/github` merge (run link on #9362); no dispatch is requested or planned.

## Rollback

Revert the squash commit: it restores the four wrappers and removes the gate step, the script, the suite rows and the array entry together. The revert is a CODEOWNERS-reviewed workflow edit that does not touch the push `paths:` filter, so it triggers no apply. It reopens the tf-var path; last resort only.

## Risks and Sharp Edges

- The plan JSON carries variable values: never written to disk by the gate, never `set -x`. The runner's binary `tfplan` and `tfplan.txt` already exist there today (pre-existing, not new).
- The gate's first run on a real apply is on a plan shape the suite only knows from one real fixture and the read-only live comparison above; a false red blocks that apply and has no override, by design. The real-fixture-derived rows are the mitigation.
- Scheduled drift (read-only `plan`) and the PR plan job keep the injection: a planted value there shows as a drift plan, which is the detector, and they cannot write. Apply and drift now differ in effective inputs by design; the follow-up issue tracks unwrapping them.
- A plan whose `## User-Brand Impact` is empty fails deepen-plan; it is filled here.
- The `terraform import` calls run without `-input=false`; every `variables.tf` variable has a default, so none prompts. A future no-default variable would hang there, which the existing plan step (`-input=false`) would surface first.

## Research Insights

**Premise validation.** #9362 open, #8209 open, #9893 an open draft with one hunk in this workflow (the revoke step). ADR-241's 2026-10-01 amendment still lists #9362 as pre-existing. O11 executed 2026-10-04. `--only-secrets` exists in the installed Doppler CLI, but `knowledge-base/project/learnings/2026-03-21-doppler-tf-var-naming-alignment.md` records that it fails together with `--name-transformer tf-var`. Live ruleset bindings equal the canonical files today (read-only GitHub GET, 23 and 2 rows). No cited blocker is stale.

**Repo research (read-only).** Deleting the four wrappers needs no edit to any existing gate: census Guard 2 rows count `doppler run` invocations with no floor, the ordering row still keys on `terraform plan|apply|import`, the mint-shape first-write check is met by the plan line, and the shell-trace baseline counts credential-header `curl` sites this PR does not touch. Any script the workflow invokes must exist and not contain `doppler run`. Provider schema (pinned integrations/github 6.12.1, extracted offline): `rules` list, `required_status_checks` list, `required_check` set (min 1) of `{context, integration_id}`; set order is not guaranteed, so the projection sorts by context.

**Plan-review outcome.** Eight reviewers converged on cutting the post-apply live mode, the new suite and its registration, and the heavier matrices; the pre-apply gate, the wrapper deletion, the Guard 2 pin and the CODEOWNERS rows were kept. Findings folded in: absolute `${GITHUB_WORKSPACE}` paths and `pipefail` in the gate step; stdin read first and empty-stdin exit 2; Guard 2 allowlist pinned to exactly one step plus a ban on `doppler secrets download` and `GITHUB_ENV` writes; the corrected no-op argument; the gate's narrow scope stated; the drift/PR-plan asymmetry tracked. Taste decisions are recorded in `knowledge-base/project/specs/feat-one-shot-9362-tf-var-integration-id-rebind/decision-challenges.md`.

**Learnings to honor:** `--only-secrets` exits 0 on an unknown flag and passes blank values; a delete-only destroy guard misses in-place updates; pin the id end to end (`2026-07-06-migrating-literal-pinned-sync-gate-to-var-referencing-iac-loses-the-number-pin.md`); a self-graded mutation battery can measure nothing (`2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md`); the workflow `paths:` filter is the actuating surface (`2026-06-18-coupled-registration-must-guard-the-actuating-surface.md`).
