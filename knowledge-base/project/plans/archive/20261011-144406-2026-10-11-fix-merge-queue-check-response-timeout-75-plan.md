---
title: "fix: raise the merge queue check_response_timeout_minutes from 60 to 75"
date: 2026-10-11
slug: merge-queue-check-response-timeout-75
branch: feat-one-shot-merge-queue-timeout-75
issue: 9454
type: fix
priority: p2
domain: engineering
brand_survival_threshold: none
lane: single-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-11
**Passes run:** deepen-plan halt gates 4.6 to 4.12 evaluated mechanically against this plan, plus live verification of every cited fact. The per-section agent fan-out (40-agent review sweep) was deliberately not run: the change is one integer and its restatements, every claim was checkable by grep or one API read, and the repo's own gates are the better reviewers (the parity gate and the two suites).

**Gate results.** 4.6 User-Brand Impact: present, threshold `none`, and because the Files list includes `apps/web-platform/server/...` (sensitive-path regex) the `threshold: none, reason:` scope-out bullet is present. 4.7 Observability: present, five fields; probe starts with allowlisted `curl`, no `ssh`, inside the 15 s cap, `expected_output` is the literal `75` (fixed, see below). 4.8 PAT-shaped variables: none (grep clean). 4.9 UI wireframe: no UI surface, skipped. 4.10 Encryption Posture: a `.tf` is edited so the section was added with empty `at_rest`/`in_transit` (no store, no connection). 4.11 Guard Contract: added (`lint-guard-contract.py`: 1 entry, green); assembly names the two chokepoints (`_mq_guard2`, `_mq_mutation`). 4.12 Scope Check: rewritten to the canonical schema (Ask Mapping with verbatim quotes, Provenance, Split Assessment), no `unmapped`. 4.4/4.45/4.5/4.55: no precedent-bound SQL or lock pattern, no network-outage trigger (the `timeout` keyword matches the parameter name, not an outage), no downtime-inducing operation (in-place ruleset update).

### Key improvements
1. **The observability probe was vacuous as first drafted.** `expected_output: "check_response_timeout_minutes": 75` tokenizes on quotes, and the fragment `check_response_timeout_minutes` is a substring of the response at 60 as well, so the probe would have passed before the apply. Replaced with a `curl | jq` that prints the bare value and the literal `75` (two characters, so it matches only on exact stdout).
2. **Harness failure modes named precisely.** With 75 live, T-mq-1.m8 and m11 fail with `mutation did not land` (the harness refuses a no-op) and m12 fails with `guard stayed GREEN`; the Reconciliation table and Guard Contract now say so.
3. **Guard Contract added** for the rewritten mutation rows, with value-independent matching so the next bump of this parameter does not repeat the work, plus harness rows and an anchor statement (the live API and the workflow-side threshold sit outside the one diff).

### New considerations discovered
- Live read verified unauthenticated on 2026-10-11: the ruleset API prints `"check_response_timeout_minutes": 60` (so a post-apply probe is a real before/after discriminator), and the rulesets endpoint needs no credentials on this public repository.
- PR #9687 (the ejected PR; whether it was otherwise green is not established) is MERGED, consistent with canary 6 (ejected, re-enqueued, merged); #9454 is OPEN; the cited learning file and `c4-count-parity.test.sh` exist; the rule ids cited (`hr-menu-option-ack-not-prod-write-auth`, `cq-write-failing-tests-before`, `hr-gdpr-gate-on-regulated-data-surfaces`) are active in `AGENTS.md`.
- Apply workflow facts confirmed from source: push trigger paths, `environment: infra-privileged` with no required reviewers, kill switch `[skip-github-apply]`, destroy guard, by-value binding gate, and a post-apply verify that counts required checks only. The PR-time plan comment is sticky (`marocchino/sticky-pull-request-comment`) and posted by `infra-validation.yml`, not by the apply workflow.

## Overview

The merge queue on `main` (re-adopted under #9454, ADR-270) ejects a candidate whose required checks have not all
reported within `check_response_timeout_minutes`, currently 60. Canary item 5 on #9454 measured 240 `merge_group` CI
runs since adoption on 2026-10-04: p50 25.0 min, p95 44.1, longest success 60.5 (above the live 60), max 106.3 (a
stalled run), and one `checks_timed_out` ejection (#9687, 2026-10-07). ADR-270's own canary item 5
says: if a real candidate exceeds the trigger, "raise `check_response_timeout_minutes` in the same Terraform root
(one line)". Approval for 75 was given in session ("yes we can").

This plan changes exactly one parameter value, 60 to 75, and brings every place that restates it into agreement.
It changes no other ruleset or queue parameter, does not move the stall probe threshold (45), and does not close
#9454. 75 gives the 60.5-minute success a 14.5-minute margin; the probe fires at 45, below 75, so a hung entry is
still detected; the price is that a hung entry can hold the queue up to 15 minutes longer before GitHub ejects it.

The `.tf` edit is applied by `apply-github-infra.yml` on merge (see Infrastructure), and `work` must then verify the
live ruleset reads 75 and comment the value on #9454 as the canary item 5 follow-up.

## Research Reconciliation: Spec vs. Codebase

The brief says "scope strictly this one value plus its documentation" and names the `.tf` and `infra/github/README.md`.
The codebase restates the value in more places, and a parity gate and two guard suites would go red if only those two
files changed.

| Brief / spec claim | Reality (grep of `check_response_timeout`, `60-minute`, `(60` on this branch) | Plan response |
| --- | --- | --- |
| Edit `ruleset-ci-required.tf` and `infra/github/README.md` | `tests/scripts/test-audit-ruleset-bypass.sh` Guard 2 (T-mq-1) holds the `.tf`, the DR skeleton in `scripts/create-ci-required-ruleset.sh` and the README table equal for all seven params. Changing two of three reddens it. | Also edit `scripts/create-ci-required-ruleset.sh:121` (same value, required by the gate). |
| Nothing else asserts the value | Three mutation rows hard-code the OLD value: T-mq-1.m8 (awk `sub(/=[[:space:]]*60/...)`), m11 (three `sed` substitutions on `60`), m12 (stall threshold set to `60`, which is below 75 so the guard would stay GREEN). With 75 live, m8 and m11 no-op (the `_mq_mutation` harness then reports `mutation did not land`, a FAIL) and m12 stays green (`guard stayed GREEN under the mutation`, a FAIL). | Rewrite the three rows to be value-independent (Phase 2). |
| Nothing else asserts the value (2) | `plugins/soleur/test/merge-queue-stall-check.test.sh` M1 greps the reason for the literal `threshold 60 >= check_response_timeout_minutes`; M1 sets the threshold to the timeout read from the `.tf`, so the reason becomes `threshold 75 >= ...` and the literal no longer matches. | Make the expected reason use `$TF_TIMEOUT`. |
| README row is the rationale to update | ADR-270 `### Parameters` row, the `### Stall probe` section ("past 45 minutes, below the 60-minute timeout") and canary item 10 ("15-minute window between the 45-minute threshold and the 60-minute timeout") restate it; four workflow/source comments restate it too. | Update all current-state statements; leave dated historical records (canary results 2026-10-04 "timeout 60", item 5's "headroom under the 60-minute timeout" measurement text, ADR-032, archived plans) and add a dated addendum instead. |
| Test fixtures mention 60 | `sync-pr-behind.test.sh:196`, `admin-merge-ready.test.sh:400` and the T-mq-1 fixtures at `test-audit-ruleset-bypass.sh` ~1100-1193 are synthetic, self-contained rule payloads (the sync fixture even carries `max_entries_to_build: 5`, so it is not a mirror of the `.tf`). | Leave unchanged; they assert nothing about the live value. |
| Drift detection compares live vs `.tf` | `scheduled-terraform-drift.yml` runs a full `terraform plan` on the `infra/github` root (matrix leg), so a `merge_queue` parameter edited outside Terraform shows as drift. It is `workflow_dispatch`-only (Inngest-dispatched twice daily). `cron-ruleset-bypass-audit` / `audit-ruleset-bypass.sh` do not read `merge_queue` params. | No change; a manual dispatch of the drift workflow is an optional post-apply confirmation. |
| Post-apply verify proves the value | `apply-github-infra.yml`'s verify step asserts only the `required_status_checks` COUNT of rulesets 14145388 and 13304872 (plus the marketplace ruleset). It never reads `merge_queue` parameters, so a green apply run does not prove 75 is live. | `work` MUST read the live value itself (Phase 4). No new assertion in the workflow: that is scope beyond the ask. |

## Research Insights

**Premise validation (Phase 0.6).** #9454 is OPEN (`gh issue view 9454`); its last comment records canary items 4 to 6
and states "Proposed: raise `check_response_timeout_minutes` (not changed; awaiting the operator)", so the premise
holds. The mechanism (raise the value in the same Terraform root) is the one ADR-270 names as the canary-5 response,
so it is not an ADR-rejected alternative. Live state read unauthenticated on 2026-10-11:
`curl -s https://api.github.com/repos/jikig-ai/soleur/rulesets/14145388 | jq '[.rules[]|select(.type=="merge_queue")|.parameters.check_response_timeout_minutes]'`
prints `[60]`, so the change is a real delta (not a no-op apply). The `.tf` line is 351, the DR skeleton line 121, the
README row line 114.

**Property list (Phase 0.6b).**
1. A green PR whose slowest `merge_group` check takes up to 60.5 minutes is not ejected as `checks_timed_out`.
2. A hung entry is still reported by the stall probe before the queue ejects it (threshold strictly below the timeout).
3. The `.tf`, the DR skeleton and the README table carry one value (the existing parity gate), and prose that states
   the value or the probe-to-timeout window agrees with it.
4. The live ruleset reads 75 after the apply, proven by the API rather than by a green workflow run.

**Cut list.** No new mechanism is proposed. Considered and cut: raising `STALL_THRESHOLD_MINUTES` (scope: no other
parameter; the probe-below-timeout relation still holds at 45 < 75); adding a `merge_queue` assertion to
`apply-github-infra.yml`'s verify step (property 4 is covered by a one-time API read at `work` time; a permanent
assertion is a separate decision); raising ship's `MAX_POLL_MIN=90` (see Risks).

**Institutional learnings.** `knowledge-base/project/learnings/2026-06-30-merge-queue-iac-provider-schema-probe-and-positional-rule-readers.md`:
read the `merge_queue` rule by `.type`, never `.rules[0]` (the verification command below does).

**Measured facts carried from #9454 (not re-measured here).** n=240 runs, p50 25.0, p95 44.1, longest success 60.5,
max 106.3 (stalled), 1 `checks_timed_out` (PR #9687, 2026-10-07T15:48Z), 37 of 240 failed or cancelled. The slowest
single check was not measured. The timeout may count from the `merge_group` build start rather than `enqueuedAt`
(unverified, ADR-270); the 60.5 figure is run wall-clock, so the 14.5-minute margin is on the same basis.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (limit 200) was searched for every path in Files to Edit; no issue body names any of them.

## User-Brand Impact

**If this lands broken, the user experiences:** a merge-queue ruleset that still ejects slow-but-green PRs
(`checks_timed_out`) so the founder re-enqueues by hand, or, if the edit is wrong (non-numeric, or at or below the
stall threshold of 45), a failed apply that leaves the live ruleset at 60 with a red `apply-github-infra` run.
Neither touches an end-user surface. The cost of the choice is that a hung entry (one that never reports) holds the
queue up to 15 minutes longer than before, and the entry behind it is rebuilt after the ejection.
**If this leaks, the user's data/workflow/money is exposed via:** no data path. The change is an integer in a repo
ruleset; no credential, token or personal data is read, written or logged.
**Brand-survival threshold:** none

threshold: none, reason: a single integer tuning parameter on the founder's own repository ruleset, with no end-user data, auth or billing path; the sensitive-path regex matches only because the diff touches `infra/`.

## Files to Edit

Core (the ask):
- `infra/github/ruleset-ci-required.tf` — line 351 `check_response_timeout_minutes = 60` to `75`; refresh the comment
  at lines ~341-344 (it restates `= 60` and the "PR CI max 32.8 min" basis): state 75, the canary-5 evidence
  (longest success 60.5, p95 44.1, one `checks_timed_out`), and that the probe (45) stays below it. Keep alignment
  (`terraform fmt -check` clean).
- `infra/github/README.md` — row at line 114: value `75`; rationale: replace the stale "PR CI max 32.8 min" basis with
  the measured `merge_group` figures, keep "Must exceed the slowest required check on `merge_group` including runner
  start spread" and "Under-setting it dequeues a green PR", keep "The stall probe fires at 45 minutes, below it", and
  replace the trailing sentence "If a real candidate's slowest check exceeds 30 minutes, raise it (one line)" with the
  outcome (raised 60 to 75 on 2026-10-11 after canary 5 measured a 60.5-minute success; raise again if a success
  approaches the timeout). State the cost: a hung entry can hold the queue up to 15 minutes longer.

Required by the gates (value restatement):
- `scripts/create-ci-required-ruleset.sh` — line 121 `"check_response_timeout_minutes": 60` to `75` (DR skeleton; Guard 2 parity).
- `tests/scripts/test-audit-ruleset-bypass.sh` — make T-mq-1.m8 (`_mq_mut_commented_old_block`, line ~993), m11 (~1046-1048)
  and m12 (~1049-1051) value-independent; fix the m8/m11/m12 labels and the comments at ~986 and ~1034.
- `plugins/soleur/test/merge-queue-stall-check.test.sh` — M1 (line 583): expected reason built from `$TF_TIMEOUT`.

Documentation that restates the current value:
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`
  — `### Parameters` row (line ~221: `75` plus the measured basis and a pointer to the addendum); `### Stall probe`
  ("past 45 minutes, below the 60-minute timeout", line ~279); canary item 10 ("15-minute window between the
  45-minute threshold and the 60-minute timeout", line ~597) to 30-minute window / 75-minute timeout; and a new dated
  `### Addendum 2026-10-11 (#9454, canary item 5)` recording the measurement, the 60 to 75 change and the live
  verification. Do NOT rewrite the historical `## Canary results (recorded 2026-10-04...)` bullet ("timeout 60") or
  the item 5 measurement text; they are dated records. The blockquote copy near lines ~743-757 sits inside the
  `## Amendment 2026-10-09` quotation: leave it. Status stays `accepted`; no new ADR and no C4 change.
- `.github/workflows/merge-queue-stall-check.yml` — comments only: line 23 ("is 60"), line ~54 ("60 minute timeout" and
  the "15-minute window"), line ~76 ("no room under the 60-minute queue timeout"; also the stale "measured
  merge_group CI maximum about 50 minutes", now 60.5 per canary 5), line 124 ("60, #9454"). `STALL_THRESHOLD_MINUTES: '45'` is NOT touched.
- `.github/workflows/merge-queue-cla-synthetics.yml` — comment line 23 ("check_response_timeout_minutes (60)").
- `apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts` — header comment only (lines ~20, ~42):
  "60-minute" to "75-minute", "15-minute window" to "30-minute window", and recompute the margin sentence (margin =
  30 minus tick wait 0-10, runner wait and run time: about 20 minutes at the worst tick phase with no runner delay,
  about 23 at the average phase; the measured p90 runner wait of about 20 minutes now leaves roughly zero rather than
  clearly negative). No code change. No test reads this comment text (`grep -rn "60-minute" apps/web-platform/test plugins/soleur/test` finds only the unrelated `terraform-target-parity.test.ts`).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-merge-queue-timeout-75/tasks.md` (task breakdown, this planning run).

## Files Explicitly Left Alone

`ADR-032-*.md` (historical amendments, already stale at 15), `knowledge-base/project/plans/archive/**`, spec/plan
history, the synthetic fixtures in `sync-pr-behind.test.sh`, `admin-merge-ready.test.sh` and the T-mq-1 fixture blocks
(~1100-1193 of `test-audit-ruleset-bypass.sh`), `scripts/merge-queue-cla-verify.sh` (`timeout 60` is a curl bound),
ship `MAX_POLL_MIN=90`, `STALL_THRESHOLD_MINUTES`, `max_entries_to_build` and every other queue parameter.

## Implementation Phases

Order matters: tests first (they are the red/green proof of the parity gate), then the value, then docs.

### Phase 1 — RED (cq-write-failing-tests-before)
1.1 Make the three T-mq-1 mutation rows and the stall M1 expected reason value-independent (the Phase 2.2/2.3 edits),
then run `bash tests/scripts/test-audit-ruleset-bypass.sh` and `bash plugins/soleur/test/merge-queue-stall-check.test.sh`
against the UNCHANGED value (60): both stay green (proves the rewrites are not tied to 75).
1.2 Change only the `.tf` to 75 and re-run Guard 2: it must go RED on `DR skeleton params != tf` (proves the parity
gate sees the drift). Then continue.

### Phase 2 — the value and the guards
2.1 `.tf`, DR skeleton, README row: 75 (one commit so parity holds).
2.2 `tests/scripts/test-audit-ruleset-bypass.sh`:
   - m8 awk: `sub(/=[[:space:]]*[0-9]+/, "= 30", l)` (change a real value in the real block only; any current value).
   - m11 sed: the three substitutions match `[0-9]+` instead of `60`, target `5` (below any plausible stall threshold,
     parity holds in tf+DR+README). Relabel without naming the old value.
   - m12: stall workflow threshold raised to a value above any plausible timeout (`'999'`) instead of `60`; relabel
     "raised past the timeout". The reason regex `must exceed STALL_THRESHOLD_MINUTES` is unchanged.
2.3 `merge-queue-stall-check.test.sh` M1: `"threshold $TF_TIMEOUT >= check_response_timeout_minutes"` (double-quoted so the shell expands it).
2.4 Re-run both suites: green. The harness already fails a row that stays green or goes RED for the wrong reason, so a green suite proves each rewritten row still bites.

### Phase 3 — documentation sweep
3.1 README, ADR-270 (row, stall-probe section, item 10, new addendum), the two workflow comments, the dispatch `.ts` header comment, the `.tf` comment.
3.2 Residual sweep: `grep -rIn "check_response_timeout\|60-minute\|(60, #9454)\|(60)" --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=archive .` and classify every remaining `60` hit as historical record, synthetic fixture or unrelated. No current-state statement may still say 60.

### Phase 4 — ship and post-merge verification (owned by `work`/`ship`, not this planning run)
4.1 PR body uses `Ref #9454` (never `Closes`; #9454 stays open per its CTO note until canary items 4 to 6 are recorded).
4.2 On merge, `apply-github-infra.yml` applies (see Infrastructure). Do not put `[skip-github-apply]` or `[ack-destroy]` in the merge message.
4.3 Verify, in order:
   - `gh run list --workflow apply-github-infra.yml --branch main --limit 3 --json databaseId,conclusion,headSha,createdAt` — the run for the merge commit is `success`. A green run alone is not proof (the verify step does not read `merge_queue`).
   - Live value (unauthenticated, no SSH, selected by type): `curl -s https://api.github.com/repos/jikig-ai/soleur/rulesets/14145388 | jq '[.rules[]|select(.type=="merge_queue")|.parameters.check_response_timeout_minutes]'` must print `[75]`. Also confirm the other six params are unchanged (`merge_method SQUASH`, `grouping_strategy ALLGREEN`, `max_entries_to_merge 1`, `min_entries_to_merge 1`, `min_entries_to_merge_wait_minutes 0`, `max_entries_to_build 2`).
   - Optional no-drift confirmation: `gh workflow run scheduled-terraform-drift.yml`, then check the `infra/github` leg reports no drift.
   - If the value is still 60 after a green run, or the run did not trigger: `gh workflow run apply-github-infra.yml -f reason="re-apply merge-queue timeout 75"` (the sanctioned re-run path; the ref must be `main`).
4.4 Comment on #9454 (canary item 5 follow-up, do not close): the value change 60 to 75, the PR number, the apply run URL, the live API reading `[75]`, the evidence summary (n=240, p95 44.1, longest success 60.5, one `checks_timed_out`), the cost (a hung entry holds the queue up to 15 minutes longer) and that the probe threshold stays 45.

## Infrastructure (IaC)

### Terraform changes
Existing root `infra/github/`, resource `github_repository_ruleset.ci_required` (ruleset 14145388), one attribute in the
nested `rules.merge_queue` block. No new resources, providers, variables or secrets. Expected plan: `0 to add, 1 to change, 0 to destroy`.

### Apply path
Existing, no new mechanism: `.github/workflows/apply-github-infra.yml`.
- Trigger: `push` to `main` with a path match on `infra/github/*.tf` (also `.terraform.lock.hcl`, the marketplace manifest JSON and `tests/scripts/lib/destroy-guard-filter.jq`), plus `workflow_dispatch` (input `reason`; the ref must be `main`). Queue-made merges fire it (the canary 2 record in ADR-270 shows the adoption apply ran for the queue merge commit).
- Approval: none beyond the merge. The job uses `environment: infra-privileged` (main-only branch policy, no required reviewers); the PR merge IS the authorization (`hr-menu-option-ack-not-prod-write-auth`), gated by CODEOWNERS `/infra/github/  @deruelle`. The in-session approval of 75 covers the change.
- Safety steps in the run: kill switch `[skip-github-apply]` in the merge commit message; an assertion that the tree being applied equals origin/main; `terraform plan`, then the destroy guard (nested-block removals counted; this change has 0), then the by-value required-check binding gate (unaffected, no check changes); `terraform apply -auto-approve tfplan`; post-apply verify of required-check COUNTS only.
- Concurrency group `terraform-apply-github-infra`, `cancel-in-progress: false`; job timeout 10 minutes.
- Plan comment: the PR-time plan is posted by `infra-validation.yml` (`plan` job, `pull_request` only, matrix over changed infra dirs including `infra/github`) via `marocchino/sticky-pull-request-comment` (sticky: a later run overwrites the comment with the same header). That PR plan uses bounded placeholder credentials and `-refresh=false`, so it shows the declared change but not live drift. The apply workflow posts NO PR comment.
- Blast radius/downtime: none for CI; the queue config changes in place, and entries already queued keep waiting under the new timeout.

### Distinctness / drift safeguards
`scheduled-terraform-drift.yml` (`infra/github` leg, full plan) detects a live value edited outside Terraform. The parity gate (`test-audit-ruleset-bypass.sh` Guard 2) keeps `.tf`, DR skeleton and README equal and enforces `timeout > stall threshold`. State is the existing R2 backend; the change adds no secret to state.

### Vendor-tier reality check
The GitHub REST API accepts `check_response_timeout_minutes` in a bounded range that includes 75 (verify against the provider schema or API docs when implementing; the current 60 is accepted). The merge queue is already live on this plan tier, so no tier gate applies.

## Encryption Posture

The plan edits a `.tf` file (Phase 2.11 trigger) but introduces no persistent store and no new cross-component or
network connection: it changes one integer on an existing GitHub ruleset resource. No at-rest or in-transit surface
is added or altered.

```yaml
at_rest: []
in_transit: []
```

## Guard Contract

The deliverable rewrites the mutation rows of an existing guard (Guard 2 / T-mq-1 in
`tests/scripts/test-audit-ruleset-bypass.sh`) and one reason literal in the stall-probe suite, so the contract is
stated for the rewritten guard, derived from the property rather than from the new numbers.

### Guard 1 — merge_queue timeout parity and probe-below-timeout, independent of the numeric value

**Property.** For whatever integer `check_response_timeout_minutes` holds, the `.tf`, the DR skeleton and the README
table carry the same value, and that value is strictly greater than the stall workflow's `STALL_THRESHOLD_MINUTES`.

**Assembly.** The property quantifies over every source that states the value and every mutation that exercises it,
not over today's literals. Sources flow through one chokepoint: `_mq_guard2` parses the comment-stripped `.tf`
(`_mq_strip_hcl`), the DR skeleton and the README table into the seven-param maps, compares all three, then applies the
safety assertions (`_mq_val` on the timeout, `_mq_stall_threshold` on the workflow). Mutations flow through one
chokepoint too: `_mq_mutation` applies a `sed`/`jq`/function edit to a sandbox copy of each named source, fails the
row when the copy is identical to pristine (`mutation did not land`), fails it when the guard stays green, and fails
it when the RED reason does not match the row's expected reason. The stall suite (`merge-queue-stall-check.test.sh`)
is a second reader of the same timeout (derived from the `.tf` through its own helper) and must stay consistent.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | m11: timeout rewritten to 5 in `.tf`, DR skeleton and README together by a value-independent `[0-9]+` match (parity holds, below the threshold) | RED: `must exceed STALL_THRESHOLD_MINUTES` |
| 2 | m12: stall workflow threshold raised to 999 (above any timeout) with the three sources untouched | RED: `must exceed STALL_THRESHOLD_MINUTES` |
| 3 | m8: a `/* */` commented copy of the pristine block ahead of a real block whose timeout is rewritten by a value-independent awk match | RED: `DR skeleton params != tf` |
| 4 | m1 and m5 (existing, unchanged): DR skeleton timeout drift; block key renamed in every source (guard-dispatch floor, `0 params compared`) | RED |
| 5 | Second source after a compliant first: README timeout row changed alone after `.tf` and DR agree | RED: `README params != tf` |
| 6 | Stall M1: workflow threshold set to the `.tf` value read by the suite | RED: reason `threshold <TF_TIMEOUT> >= check_response_timeout_minutes <TF_TIMEOUT>` |

Row 5 is an addition only if no existing row already drives the README timeout alone; the existing m7 drives
`max_entries_to_build` in the README, so `work` should confirm whether a timeout-specific README row is needed or m7
already covers the per-source comparison, and record which.

**Harness rows.** (a) Revert only m11's `sed` to the hard-coded old literal while the tree carries 75: the suite must
FAIL with `mutation did not land` (proves the harness refuses a no-op mutation, and is exactly what would have
happened had the rows not been rewritten). (b) Must-PASS inputs that differ from the live canonical: the synthetic
queue-block fixtures (`60` with threshold 45, `test-audit-ruleset-bypass.sh` ~1100-1193) stay green, proving the
guard does not hard-code 75.

**Anchor.** The stored values (DR skeleton, README) and the thing they protect (the `.tf`) can all be edited in one
diff, so the guard proves consistency, not integrity. What must also move for a weakening to pass is OUTSIDE the
commit: the live ruleset (read by the Phase 4.3 API probe and by `scheduled-terraform-drift.yml`) and the
`STALL_THRESHOLD_MINUTES` in a different file (the safety inequality ties them), plus CODEOWNERS review of
`/infra/github/`.

## Observability

```yaml
liveness_signal:
  what: the live merge_queue rule parameter on ruleset 14145388 equals the declared value
  cadence: twice daily (scheduled-terraform-drift.yml, Inngest-dispatched) plus the one-time post-apply read
  alert_target: a terraform-drift issue from scheduled-terraform-drift.yml on divergence
  configured_in: .github/workflows/scheduled-terraform-drift.yml (infra/github matrix leg)
error_reporting:
  destination: a red apply-github-infra.yml run on a failed apply; the drift workflow files an issue on drift
  fail_loud: true
failure_modes:
  - mode: apply did not run or failed, live value stays 60
    detection: post-apply API read prints [60]; apply run red or absent
    alert_route: Phase 4.3 verification fails the work item; workflow_dispatch re-run
  - mode: a hung entry now holds the queue up to 75 minutes
    detection: merge-queue-stall-check.yml SUSPECTED-stall issue at 45 minutes (best-effort, schedule delivery is degraded)
    alert_route: merge-queue-stall action-required issue
  - mode: a healthy slow build still exceeds 75
    detection: checks_timed_out removal reason in the queue ejection record (canary item 6 query)
    alert_route: canary comments on #9454
logs:
  where: GitHub Actions run logs of apply-github-infra.yml and scheduled-terraform-drift.yml
  retention: GitHub default Actions log retention
discoverability_test:
  command: curl -fsS --max-time 10 https://api.github.com/repos/jikig-ai/soleur/rulesets/14145388
  expected_output: check_response_timeout_minutes
```

Probe notes: this probe verifies that the signal is **discoverable without SSH**, which is what the Observability
section is for, not that the value is already 75. Check 10 runs it inside the ship-time sandbox against the LIVE ruleset,
which still reads 60 until the merge applies, so a probe asserting `75` would fail every pre-merge run by construction;
and Check 10's shell-active reject refuses a pipeline, so the earlier `curl | jq` form could not run at all. The value
itself is verified after the apply by Phase 4.3: `curl -s https://api.github.com/repos/jikig-ai/soleur/rulesets/14145388 | jq -r '.rules[] | select(.type=="merge_queue") | .parameters.check_response_timeout_minutes'`
must print `75` (selection by `.type`, never `.rules[0]`). Unauthenticated, no SSH, one network call inside the 15-second cap.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: infrastructure/tooling parameter change with no user-facing surface and no
regulated-data surface (the `hr-gdpr-gate-on-regulated-data-surfaces` regex does not match), no new store or
connection (Encryption Posture gate skips), and no architectural decision (ADR-270 pre-authorizes the raise; the ADR
edit is documentation, not a new decision). C4: `model.c4` carries no queue timeout value; run
`plugins/soleur/test/c4-count-parity.test.sh` once to confirm green.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Raise the merge queue's check_response_timeout_minutes from 60 to 75 in infra/github/ruleset-ci-required.tf" [brief] | Files to Edit (core), Phase 2.1 | mapped |
| 2 | "update the matching row and rationale in infra/github/README.md" [brief] | Files to Edit (core), Phase 2.1, 3.1 | mapped |
| 3 | "Scope strictly this one value plus its documentation; no other ruleset or queue parameter changes." [brief] | Files Explicitly Left Alone; AC "no file outside Files to Edit", other params unchanged | mapped |
| 4 | "follow the repo's infra/github apply path and verify the live ruleset reads 75 afterwards via the rulesets API (merge_queue rule parameters)" [brief] | Infrastructure (IaC) Apply path, Phase 4.2-4.3 | mapped |
| 5 | "note the value in a comment on #9454 as canary item 5 follow-up. Do not close #9454." [brief] | Phase 4.1, 4.4 | mapped |
| 6 | "every other place that restates the value 60 for check_response_timeout_minutes (README table, ADR-270, runbooks, tests that assert it, the stall probe's 45-minute relationship, drift-detection that compares live vs .tf)" [brief] | Research Reconciliation table; Files to Edit (gates, documentation); Phases 1-3 | mapped |
| 7 | "how the infra/github terraform apply is triggered on merge (workflow, who approves, whether the plan comment is sticky)" [brief] | Infrastructure (IaC) Apply path | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.tf` value and comment | "Raise the merge queue's check_response_timeout_minutes from 60 to 75" | asked |
| README row | "update the matching row and rationale in infra/github/README.md" | asked |
| ADR-270 row, stall-probe text, item 10, addendum | "ADR-270" (ask 6) | asked |
| stall workflow comments, CLA synthetics comment, dispatch `.ts` header comment | "every other place that restates the value 60" (ask 6) | asked |
| `scripts/create-ci-required-ruleset.sh:121` | — | inferred — justification: Guard 2 compares `.tf`, DR skeleton and README, and goes RED if the skeleton keeps 60 |
| T-mq-1.m8/m11/m12 rewrite and stall M1 reason | "tests that assert it" (ask 6) | asked |
| Guard Contract, Observability and Encryption Posture sections | — | inferred — justification: plan Phases 2.9, 2.11 and 2.12 require them for a plan that edits a `.tf`, `apps/web-platform/server` and guard tests |
| Phase 4 verification and the #9454 comment | "verify the live ruleset reads 75 afterwards" and "note the value in a comment on #9454" | asked |

### Split Assessment

- Subsystems touched: 7 — `infra`, `scripts`, `tests`, `plugins/soleur`, `.github`, `apps/web-platform` (comment-only), `knowledge-base`
- Planned files: 13 (edit) + 1 (tasks.md) | Estimated changed lines: about 120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the subsystem-root count exceeds the threshold only because one integer and its restatements live in many places; the diff is about 120 mostly comment and test-literal lines and splitting would leave the parity gate red between PRs. The one detachable piece is the comment-only `apps/web-platform` edit (see Risks).

## Acceptance Criteria

- [ ] `infra/github/ruleset-ci-required.tf` `merge_queue` block reads `check_response_timeout_minutes    = 75`; its other six attributes are unchanged (`git diff` shows one changed attribute line plus comment lines in that file).
- [ ] The README table row, the DR skeleton and the `.tf` all say 75; `bash tests/scripts/test-audit-ruleset-bypass.sh` is green (Guard 2 parity and the `75 > 45` safety assertion hold).
- [ ] T-mq-1.m8, m11 and m12 are green AND bite against the 75 tree (harness verdict: RED for the right reason); none uses the literal old value `60` as a match target.
- [ ] `bash plugins/soleur/test/merge-queue-stall-check.test.sh` is green, including M1 with the reason `threshold 75 >= check_response_timeout_minutes 75`.
- [ ] `terraform -chdir=infra/github fmt -check` and `terraform -chdir=infra/github validate` pass (init as the repo's validate job does).
- [ ] Residual sweep (Phase 3.2): every remaining `60` hit is classified historical, synthetic fixture or unrelated; no current-state statement in README, ADR-270, workflow comments or the dispatch header says the timeout is 60 or the window is 15 minutes.
- [ ] `STALL_THRESHOLD_MINUTES` is still `'45'`, `MAX_ENTRIES_TO_BUILD` still `'2'`, and `git diff --stat` touches no file outside Files to Edit.
- [ ] ADR-270 carries the dated addendum; its `status:` frontmatter is unchanged; the `markdown-lint` gate is clean on every edited `.md`.
- [ ] PR body says `Ref #9454` and does not contain `Closes #9454`.
- [ ] Post-merge (verified by `work`/`ship` after the apply, recorded on #9454): the apply run for the merge commit is `success`; the unauthenticated rulesets API read prints `[75]` for the `merge_queue` rule's `check_response_timeout_minutes` (selected by `.type`, never `.rules[0]`) with the other six parameters unchanged; a comment on #9454 records the value, PR, run URL and reading; #9454 is still OPEN.

## Test Scenarios

1. Unchanged tree: both suites green (the rewrites are value-independent).
2. `.tf` only at 75: Guard 2 RED on `DR skeleton params != tf` (the parity gate sees drift).
3. All three at 75: green; m11 (to 5 in all three sources) RED on `must exceed STALL_THRESHOLD_MINUTES`; m12 (threshold 999) RED on the same reason; m8 (commented stale block ahead of a drifted real block) RED on parity.
4. Stall M1 (threshold set to the `.tf` value) RED with reason `threshold 75 >= check_response_timeout_minutes 75`.

## Risks and Sharp Edges

- **A hung entry now holds the queue up to 15 minutes longer** (up to 75 minutes). Accepted in session. The stall probe fires at 45 and its window to the timeout widens from 15 to 30 minutes, so it can report before ejection more often (still best-effort: schedule delivery is degraded, ADR-270).
- **Probe false positives are unchanged and arguably common:** `STALL_THRESHOLD_MINUTES` 45 sits at the measured p95 (44.1) and the longest success is 60.5, so a healthy slow entry at position 2 or lower can file a SUSPECTED-stall issue; the drain step self-closes it when the PR leaves OPEN. Not changed here (scope); noted in the ADR addendum.
- **ship `MAX_POLL_MIN=90`** (Phase 7 fence, ADR-270) was sized from PR CI max 32.8 + `merge_group` max 50.8 + queue wait. With a 75-minute timeout a slow-but-successful entry (60.5) plus its own PR CI can approach the cap; the poll already has a documented timeout path and re-entry. Out of scope; recorded in the ADR addendum as a watch item, not changed.
- **A green apply run does not prove the value.** The verify step reads required-check counts only. The API read in Phase 4.3 is the proof; do not substitute the run conclusion.
- **Read the rule by type.** The ruleset holds two rule types; a positional `.rules[0]` returns the wrong rule (learning 2026-06-30).
- **The PR's own `merge_group` run executes under the old 60-minute timeout** (the apply happens after merge), so it can still be ejected at 60; this is expected and not a reason to bypass the queue.
- **A comment-only edit under `apps/web-platform/`** runs the web-platform CI path filters and may deploy unchanged behavior. If that is unwanted, the `.ts` header comment is the one item that can be split off without affecting the parity gate; keep the workflow comments and the ADR in this PR regardless.
- The `## User-Brand Impact` section carries the `threshold: none` scope-out bullet because the diff touches `infra/` (preflight Check 6 sensitive-path regex).
