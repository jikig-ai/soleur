---
title: "Registry growth observability: standing fill-rate detection after the #7341 tracker closes (part b)"
date: 2026-10-16
slug: standing-registry-fill-rate-alarm
branch: feat-one-shot-7521-standing-fill-rate-detection
issue: 7521
type: feat
lane: single-domain
domain: engineering
priority: p3-low
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# Registry growth observability: standing fill-rate detection after the #7341 tracker closes (part b)

Draft PR: #10444. PR body uses `Ref #7521` only (never a closing keyword) and carries a `## Changelog` section. Part (a) of #7521 is parked by a CTO ruling (do not retune) and is out of scope.

## Enhancement Summary

**Deepened on:** 2026-10-16
**Agents used:** repo-research-analyst, learnings-researcher, soleur:engineering:cto (two rulings), dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, security-sentinel, observability-coverage-reviewer.

### Key improvements

1. A header is now required on every exit code and must be unique; three of the script's own precondition exits (not executable, parse library unreadable, python3 missing) print only `TRANSIENT:` text and classify as probe defects, not store states.
2. A probe defect now files a deduped issue (a red run of a cron-dispatched workflow reaches no human); a fill-leg-only TRANSIENT is discriminated statelessly with a closed benign-token allowlist (CTO ruling).
3. The fill steps moved AFTER the Sentry check-in, which removes the separate gate step and makes a fill-side hang unable to delay or kill the monitor check-in.
4. The wiring test and the Guard Contract were cut to one entry and about 14 cases; the issue body was cut to one sanitized header line, a command and a link.
5. Log and issue hardening: carriage-return stripping before the pipe prefix, `::add-mask::` of the lowercased host, `#`/`@`/backtick removal from the published line, hostile-input fixtures.

### New considerations discovered

- Measured live: the existing script returns PASS in 3 s; `deploy-arm.sh` returns `DEPLOY=skipped` and `NOT_CONTAINED` for a non-deploy commit; the `alarm` job runs 20-28 s against an 8-minute timeout; `gh run view --log` lines are tab-prefixed with job, step and timestamp.
- After any reclaim or host replace the leg is TRANSIENT for roughly 25 hours while the store refills from empty (documented seam with a tracking issue); the heartbeat is the only cover meanwhile.
- Inherited exposure: anyone who can write an envelope row into the shared Better Stack source can forge a FAIL or blind the leg; accepted and recorded.

## Overview

`scripts/followthroughs/zot-fill-rate-7341.sh` is the registry store fill-rate detector. It was a follow-through, so its PASS closed tracker #7341 on 2026-08-14 and nothing has run it since. The only remaining backstop is the `soleur-registry-disk-prd` absence heartbeat, which stops pinging at 85 percent: that is the incident itself, not a leading indicator. A store filling at +5 points per day would give no warning until the heartbeat goes quiet and image pulls begin to fail fleet-wide.

The fix is the smallest one that satisfies the property "a projected breach surfaces as an action-required issue, hourly, with no tracker needing to be open": run the existing, heavily tested script **unmodified and in place** as an independent fill-rate leg of the existing hourly workflow `.github/workflows/scheduled-zot-restart-loop.yml`. Zero Terraform, zero change under `apps/web-platform/infra/**`, zero change to `cloud-init-registry.yml`, so no registry host replace and no production apply is triggered.

Ruled by CTO agent, 2026-10-16: vehicle V1a (see `## Decision Record`).

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief | Reality (verified 2026-10-16) | Plan response |
|---|---|---|
| "Reuse the spoof-resistant pcent/boot parsing from zot-fill-rate-7341.sh rather than re-implementing it" | The script itself is the parse. Its header documents it deliberately does NOT source `zot_trusted_region` (that function cuts to end of line, which also removes the closing `"}` of a JSONEachRow row, so every sample vanishes: measured n=0 from 144 rows). It applies the same invariants post-decode. | Do not extract or re-implement. Invoke the script as-is. Library reconciliation stays a filed follow-up, not this PR. |
| "(1) add a fill-rate/projection leg to the existing continuous scheduled alarm (scheduled-zot-restart-loop.yml + zot-restart-loop-alarm.sh)" | The alarm script has a 3h window and cannot fit a 72h trailing slope; folding Python into its 658 lines duplicates the parse and touches a 624-line test and a 495-line scrub test. The workflow, by contrast, already hosts independent verdict streams (NIC) and 7 filing steps. | Add the leg at the workflow level (steps), leave `zot-restart-loop-alarm.sh` byte-identical. |
| "(3) Better Stack logtail alert needs -target lines in apply-web-platform-infra.yml (size-constrained)" | ADR-218 restricts native logtail alerts to "a pure stateless per-bucket count with an email-acceptable surface"; a newest-boot-scoped trailing-segment slope is stateful and the surface must be a digest-visible GitHub issue. `apply-web-platform-infra.yml` is 474,073 bytes against a ~512,000-byte startup_failure cliff (learning 2026-09-19). | Cut. |
| "any cloud-init-registry.yml user_data byte change forces a registry host destroy-recreate" | `registry-host-replace-dispatch.yml` wakes only on `cloud-init-registry.yml`, `zot-registry.tf` and `variables.tf` (runbook `registry-host-replace-dispatch.md`, "What the gate delivers"). `apply-web-platform-infra.yml` push trigger is `apps/web-platform/infra/**`. | The diff must touch none of those paths (AC1). This also rules out moving the script: two of its eight path references live under `apps/web-platform/infra/**` (`zot-log-shipper.test.sh` T21, `zot-image.provenance.md`), and editing them would fire a production apply. |
| "the existing scheduled alarm already runs continuously and exits 0/1/2/3/4" | Confirmed. Its Sentry `status:` expression references only `steps.alarm.*`, and the NIC stream is the precedent for an independent verdict that is deliberately not folded into the exit code. | The fill leg follows the NIC precedent: independent `steps.fill.*` outputs, Sentry status expression untouched. |
| "live heartbeat pcent=16 on a 59 GB LUKS store" | Re-measured read-only at plan time with the unmodified script: `PASS pcent=16 slope=-1.25pp/day proj14d=-1 first=18 last=16 median12=16 max12=16 span=29h samples=349 boot=46f08985 window=72h`, rc 0, 3 s. | Baseline recorded; the post-merge probe expects PASS on the same shape. |

## Research Insights

### Premise Validation (Phase 0.6)

- #7521 is OPEN (labels `priority/p3-low`, `type/chore`, `domain/engineering`, `observability`); part (a) was measured 2026-10-13 and ruled "do not retune" 2026-10-14; the issue comment states "This issue stays open for part (b)". Held.
- #7341 is CLOSED (2026-08-14T18:39:05Z). Held. No merged PR closes #7521; draft PR #10444 is this branch's own WIP.
- `scripts/followthroughs/zot-fill-rate-7341.sh` and its 384-line harness exist on `origin/main` (419 lines). Held.
- ADR corpus checked for the mechanism: no ADR governs a standing fill-rate detector (grep of `fill rate`, `projected breach`, `disk fill`). ADR-218 constrains the logtail alternative (rejected above). ADR-096 names the poller pattern as default; ADR-248 puts the hourly dispatch clock on the web hosts; ADR-033's corollary (a host-state verifier must not run on the host it verifies) is satisfied because the leg runs on a GitHub runner. Nothing is sitting in a rejected-alternatives table.
- The brief's claim "scripts/followthroughs is where the sweeper reads" is true, and a detector living there outside the sweeper is legal: `sweep-followthroughs.sh` only acts on issues carrying a `soleur:followthrough` directive.

### Property List and Cut List (Phase 0.6b)

Properties the ask actually needs:

1. P1: a store that is filling toward the heartbeat threshold is detected on a fixed cadence without any tracker being open.
2. P2: detection surfaces as a digest-visible, deduped `action-required` GitHub issue while pcent is still well below 85 (a leading indicator).
3. P3: the spoof-resistant parse is reused, not re-implemented.
4. P4: no Terraform, no `apps/web-platform/infra/**` change, no registry host replace, no production apply.
5. P5: a defect or hang in the fill leg cannot mask the restart-loop verdict or change the Sentry monitor status.
6. P6: a defective probe (as opposed to a store state) reaches a human as a GitHub issue, not only as a red run nobody is subscribed to.
7. P7: issue flapping is bounded.

Cut List (mechanism, property, what already covers it):

- V2 dispatch-only diagnostic like `registry-zot-inventory.yml` buys no P1 (not continuous); the inventory lever stays the existing attribution step the restart-loop alarm already dispatches.
- V3 Better Stack logtail alert buys at most a stateless threshold (a weaker P2), needs Terraform and `-target` lines, and contradicts ADR-218 for a stateful signal.
- V4 a new dedicated scheduled workflow buys P1 but adds watchdog-dispatch-table, Sentry cron monitor, parity-test and c4-count-parity churn for nothing the existing workflow lacks.
- V1c folding `evaluate_fill()` into `zot-restart-loop-alarm.sh` duplicates the parse (violates P3) and fights P5.
- V1b `git mv` to `scripts/zot-fill-rate-alarm.sh` buys only a nicer name and violates P4 (two references under `apps/web-platform/infra/**`).
- Env-var label parameterization of the script's `[#7341]` header buys nothing and would perturb the 384-line harness that pins the header.
- A slope floor or a `cur` floor buys nothing: reaching 85 from 16 in 14 days needs ~4.9 pp/day, so a flat store cannot fire (CTO ruling).
- A separate red-run gate step, `continue-on-error`, an inner `timeout`, a 16-cell exit-code x header table, a numeric `fill_exit_code` output, an allowlisted/sanitized/capped issue-body fragment of script output, and a re-explanation of the slope arithmetic in the issue body are cut after plan review (the probe step failing itself, the exit-code map plus a header-agreement check, a non-empty verdict literal, and the run log already being public cover the same properties).
- A consecutive-run counter for a persistent fill-leg-only TRANSIENT is cut: the CTO ruled a stateless closed-allowlist discrimination instead (a deferred 24-run alarm is the #7242 pattern).

### Value measurement (Phase 0.6c)

The justification is detection, not cost saving. Measured cost of the leg: one extra Better Stack query per hour, 3 s wall-clock (`doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/zot-fill-rate-7341.sh`, rc 0, elapsed 3 s on 2026-10-16), 349 rows scoped to the current boot out of ~864 over 72h at the 5-minute cadence; `--limit 5000` has ~5.8x headroom because the primary query greps `SOLEUR_ZOT_DISK` only (the FAIL-arm attribution query reads `SOLEUR_ZOT_LOG`, which can truncate its oldest rows, informational only).

### Repo constraints found (file anchors by content, not line)

- Workflow `scheduled-zot-restart-loop.yml`: hourly cron plus the web-host dispatch clock (ADR-248); job `alarm` timeout 8 min; seven filing steps carry `!cancelled()` and compare against non-empty literals; the final `Sentry check-in (final)` step's `status:` expression references only `steps.alarm.*`.
- `apps/web-platform/test/server/watchdog-workflow-idempotence.test.ts` pins this workflow: tracker lookups must be `EXISTING=$(gh issue list ... --label ...)` lines inside steps that contain `gh issue create`, preceded by a bare `ISSUE_TITLE="[ci/<class>] ..."` assignment (no `$` in it), never `--search`; anti-vacuity counts "at least 17 lookups" and "exactly 15 `select(.title`" lookups across two workflows. A new create-or-comment step moves these to 18 and 16 respectively; the test is edited in the same PR.
- `scripts/alarm-issue-filing-guard.test.sh` (+ `.highwater`, 11 pre-existing) discovers all workflows; new filing steps must carry a status function and non-empty, non-numeric-only equality literals. `0`/`1` numeric literals are paired with a verdict literal (`'FAIL'`/`'PASS'`) because Actions `==` is loose (`null == '0'` is true).
- Public egress: this repository is public, so the issue body and the run log are world-readable (model.c4 edge `github -> publicReader`, ADR-211). The fill script never prints `zot_last_err` (the tail is cut before parse), but its attribution lead can print a vendor stderr fragment (`attribution_unavailable: ... $(head -c 300 "$AERR")`). The issue body therefore embeds an allowlisted subset only (see Phase 2).
- Seams recorded, not fixed: (a) the script returns TRANSIENT for the first 24 h of any new boot because `MIN_SPAN_HOURS=24` precedes the absolute `cur >= 85` check, so right after a registry host replace the leg is dark for 24 h (the heartbeat covers >= 85 absolute); (b) the FAIL arm prose names the v2.1.22 pin and zot#4235 and will drift; (c) `SOLEUR_ZOT_LOG` 5,000-row truncation can drop the attribution lead's oldest starts (informational only).

### Institutional learnings applied

- `2026-08-13-a-rider-is-only-valid-while-its-vehicle-is-still-pending.md`: a rider recorded against a vehicle is valid only while that vehicle is still pending, and "not yet delivered" reads the same as "the vehicle has already left". The fill probe rode on the #7341 follow-through, whose PASS closed that vehicle on 2026-08-14, after which nothing ran it; the standing leg therefore runs on the workflow's own schedule instead of on a tracker.
- `2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md`: validate each mechanism against the tree its own remediation produces (applied in the Guard Contract: the filing steps' own text must not satisfy the verdict extractor).
- `2026-10-06-a-new-anti-vacuity-floor-joins-the-meta-guard-...md`: a new suite with `MIN_CASES` joins the guard-vacuity-floor population; build it to that shape on day one.
- `2026-08-09-the-shell-capture-trap-recurred-three-times-and-finally-earned-a-lint.md` and `2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md`: `run:` bodies execute under `bash -eo pipefail`; capture with `|| rc=$?` and guard `grep` substitutions with `|| VAR=""`.
- `2026-10-08-a-pipe-tail-swapped-for-a-command-substitution-aborts-mute-and-the-green-suite-ran-on-a-newer-toolchain-than-ci.md`: runner toolchain is bash 5.2.21; do not trust a local-only green.
- `2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-...md`: measure workflow bytes before and after; this plan never touches the apply workflow.
- `2026-07-03-pass-is-not-proof-three-vacuous-green-traps-in-infra-verification.md`: prove the query sees a known SOLEUR_ZOT_DISK line before trusting a PASS (done live at plan time: samples=349).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement issue #7521 part (b) ONLY: standing registry store fill-rate detection that survives after its original follow-through tracker closed" | Phase 1 (workflow leg) | mapped |
| 2 | "Smallest fix, ONE PR, body uses `Ref #7521` (never a closing keyword), includes a `## Changelog` section" | single PR; AC11 | mapped |
| 3 | "Candidate vehicles to evaluate (CTO ruling required, not an operator question)" | `## Decision Record` row 1; `decision-challenges.md` | mapped |
| 4 | "prefer zero-Terraform and zero registry host replace" | AC1 | mapped |
| 5 | "Reuse the spoof-resistant pcent/boot parsing logic from zot-fill-rate-7341.sh rather than re-implementing it" | script invoked unmodified; AC2 | mapped |
| 6 | "any new or edited *.test.sh must satisfy ratchets grep-q-pipe-guard, fixture-relative-assert, fixture-dir-operand-assert, guard-vacuity-floor, lint-trap-tempfile-ownership, lint-shell-capture-exit (with --baseline)" | Phase 0, Phase 4, AC6 | mapped |
| 7 | "after any re-scope, re-read every post-merge probe's gates against what the PR now does and run the probe live once before merge" | `## Post-merge probe` item 3; Phase 4 live probe; AC10 | mapped |
| 8 | "do NOT merge or run any production-mutating action without the owner's explicit go" | Phase 5; AC15 | mapped |
| 9 | "before any registry/infra merge run `gh run list --workflow apply-web-platform-infra.yml` and `--workflow registry-host-replace-dispatch.yml` and read knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md" | Phase 4; AC14 | mapped |
| 10 | "run compound before ship; ship to a verified production state (deploy-arm.sh find --wait <full-sha> then served <full-sha>, from a detached origin/main worktree)" | Phase 5; `## Post-merge probe` item 1; AC16 | mapped |
| 11 | "Persist every decision as a row of the `| Item | Class | Ruling |` table in knowledge-base/project/specs/<branch>/decision-challenges.md" | `decision-challenges.md` | mapped |
| 12 | "use \"unavailable\"/\"disruption\"" wording in plan and PR text (the brief also names one banned word) | AC11 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/scheduled-zot-restart-loop.yml` probe, FAIL and PASS steps | asks 1, 3, 5 | asked |
| `scripts/followthroughs/zot-fill-rate-7341.sh` invoked unmodified | asks 4, 5 | asked |
| `scripts/zot-fill-rate-standing-wiring.test.sh` | ask 6 ("any new or edited *.test.sh must satisfy ratchets") presupposes a test | inferred - justification: a pass condition written into workflow YAML is one no test can reach; the sibling `alarm-issue-filing-guard.test.sh` is the repo's own precedent |
| `scripts/test-all.sh`, `suite-shard-legs.tsv`, `suite-durations.tsv` registration | ask 6 | inferred - justification: an unregistered suite runs in no runner (`lint-orphan-test-suites.sh`) |
| `UNEVALUATED` verdict that fails the probe step | ask 3 (CTO risk 1) | inferred - justification: the CTO named the #7242 "alarm that cannot report" class; without it a parse regression leaves the leg dark |
| 6-hour `updatedAt` close hysteresis | ask 3 (CTO risk 2) | inferred - justification: closing on the first PASS flaps a store sitting at the threshold |
| Probe-defect issue step and the closed benign-token allowlist | ask 3 (CTO follow-up ruling 2026-10-16) | inferred - justification: a red run of a cron-dispatched workflow reaches no human (no repo-wide workflow_run failure watcher exists), so without a filed issue a defective probe is silent and the leg can go dark unnoticed |
| ADR-096 dated paragraph | ask 3 | inferred - justification: the CTO ruling requires the decision to be recorded where a future reader of ADR-096 looks |
| `apps/web-platform/test/server/watchdog-workflow-idempotence.test.ts` count edit | ask 6 | inferred - justification: the exact `select(.title` pin reds on any new create-or-comment step |
| `plugins/soleur/test/preflight-discoverability-test.test.ts` baseline bump | ask 7 ("run the probe live") | inferred - justification: the Observability block declares `credentials_required`, which the repo-global G1 ratchet counts |
| `scripts/lint-betterstack-emitter-read.sh` disposition reword | ask 5 | inferred - justification: the recorded reason for this workflow ("feeds only the write probe") becomes false and the census would carry a false disposition |
| `decision-challenges.md`, `tasks.md` | ask 11 | asked |

### Split Assessment

- Subsystems touched: 5 - `.github/`, `scripts/`, `apps/web-platform/test/`, `plugins/soleur/test/`, `knowledge-base/`
- Planned files: 12 | Estimated changed lines: 450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the subsystem-root threshold is met only because two one-line edits (an exact-count pin under `apps/web-platform/test/` and a baseline number under `plugins/soleur/test/`) and the knowledge-base records are forced by the workflow change; splitting them out would leave CI red between PRs

## User-Brand Impact

**If this lands broken, the user experiences:** a registry store that fills unwarned until image pulls fail and every rolling deploy fails terminally at `image_pull_failed` (fleet-wide, not one tenant), or, in the other direction, hourly noise on a tracker that trains the owner to ignore it. Neither touches customer data.

**If this leaks, the user's data / workflow is exposed via:** the public issue body and the public Actions run log. The issue body carries only the header line (pcent, slope, projected days, an 8-hex boot prefix, sample count) with the `zot-fill-rate[#7341]:` prefix, `#` and `@` removed and inside a code span, plus the reproduce command and a run link. The attribution lead (repository names, gc and PatchBlobUpload counts, a vendor-stderr fragment) and the FAIL-arm prose naming the v2.1.22 pin and zot#4235 stay in the run log only, which is already public and already carries the whole output of the existing `alarm` step. The new public datum is the slope and its "projects 85 in N days" forecast, derived from rows the inventory workflow already echoes; no customer data, credential or `zot_last_err` text is on this path.

**Brand-survival threshold:** aggregate pattern

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-096 (`knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`) with one short dated paragraph in its observability/alarm section: the restart-loop workflow also hosts an independent fill-rate leg that runs `scripts/followthroughs/zot-fill-rate-7341.sh` in place (poller pattern, #7521); it is not folded into the zot exit code or the Sentry status. No new ADR: the decision applies the existing ADR-096/ADR-218 split (stateful signal, issue surface, poller) rather than creating a new one. The paragraph also states two things a future reader must not assume: a red run of this workflow can also mean a broken fill probe (not only a restart loop or a store state), and Sentry does not cover the fill leg's own liveness. The amendment is a task in Phase 3, not a follow-up issue. Cite this plan by its archived path (`knowledge-base/project/plans/archive/<timestamp>-2026-10-16-feat-standing-registry-fill-rate-alarm-plan.md`, resolved when `archive-kb.sh` runs at ship) wherever a plan citation is needed.

### C4 views

No C4 change. All three model files were read (`model.c4`, `views.c4`, `spec.c4`). Enumeration for this feature: external human actors: the founder (receives the `action-required` issue, already modeled) and the public issue reader (`publicReader`, already modeled with the `github -> publicReader` publication edge); external systems: Better Stack Logs (`github -> betterstack` polling edge already names the SOLEUR_ZOT_DISK source), GitHub (the issue surface), Sentry (untouched); containers/data stores: none added; actor-to-surface access relationships changed: none. The `github -> betterstack` and `github -> publicReader` edge descriptions enumerate consumers by name and do not list the new leg; that is an accepted omission, because editing `model.c4` forces a `model.likec4.json` regeneration (c4-model-freshness gate) for a change that adds no element or relationship. Backed by a green `bash plugins/soleur/test/c4-count-parity.test.sh` (a new step adds no workflow, heartbeat file or monitor, so no derived cardinality moves; AC8).

### Sequencing

The decision is true as soon as the workflow merges; nothing is gated on a later slice.

## Decision Record

Ruled by CTO agent, 2026-10-16: take V1a. Persisted as rows in `knowledge-base/project/specs/feat-one-shot-7521-standing-fill-rate-detection/decision-challenges.md` (technical class). Summary:

1. Vehicle V1a: new steps in `scheduled-zot-restart-loop.yml` running the existing script in place; V1b/V1c/V2/V3/V4 rejected (reasons in the Cut List).
2. The script stays at `scripts/followthroughs/zot-fill-rate-7341.sh`, logic byte-identical; line-count-preserving prose edits allowed (CTO round-3 ruling Q1, 2026-10-16; line 130 stays put); no `git mv`, no label env var. The single logic amendment is the round-3 ruling Q2: the sample-parse `pcent` regex is bounded to `[0-9]{1,3}` with a non-digit lookahead, and a newest sample more than 300 s in the future is a `TRANSIENT future_dated_newest_sample` (a cause outside the workflow's benign set, so it files the probe-defect issue); both can only turn a crash or a forgery into exit 2, never into a PASS. The `[#7341]` header stays (the harness pins it). The seam where `cur >= 85` sits behind the 24 h gate is documented, not hoisted.
3. FAIL conditions are the script's own (`cur >= 85`, or positive slope with `cur + slope*14d >= 85`); no floor. One deduped issue `[ci/zot-fill-rate] Registry store fill rate projects a breach`, label `ci/zot-fill-rate`; comment on each later FAIL; close on PASS only when the issue's `updatedAt` is at least 6 h old; TRANSIENT files nothing (the restart-loop alarm already owns PRODUCER_SILENT, INGEST_DARK and the credential fault for the same stream).
4. Isolation: fill steps run after all existing zot and NIC steps (the ruling placed them before the Sentry check-in; review moved them AFTER it, so a fill-side hang or job timeout can never delay or kill the monitor check-in); `timeout-minutes: 3`; the Sentry `status:` expression is not edited (it references only `steps.alarm.*` and the check-in is `if: always()`, so a failing fill step turns the run red without touching the monitor); an exit code or output shape outside the contract is `UNEVALUATED`: an `::error::` annotation, and the probe step itself fails after writing its outputs.
5. ADR-096 dated paragraph; no new ADR; no C4 edit.
6. Ruled by CTO agent, 2026-10-16 (follow-up after deepen-plan found that a red run reaches no human: `scheduled-sentry-alert-drift.yml` states there is no repo-wide `workflow_run` failure watcher): a probe defect files a deduped `[ci/zot-fill-rate] Registry fill-rate probe defect` issue (the red run is only the p3 fallback when `gh` itself fails), and a fill-leg-only TRANSIENT is discriminated statelessly with a CLOSED allowlist of benign cause tokens (anything else is a defect when the zot leg is not itself failing). The counter-based 24-run follow-up is dropped. The fill steps stay AFTER the Sentry check-in, which also amends the CTO's own earlier placement.
7. No throttle on FAIL comments (ruled by CTO agent, 2026-10-16; source: `decision-challenges.md` line 24, the deepen-plan security row, which records the decline of the throttle, the `--author` pin and the bot-comment derivation; the comment-volume rationale below is this plan's paraphrase of that ruling): each FAIL run comments on the open breach issue and the throttle, the `--author` pin and the bot-comment derivation are all declined. Rationale: comment volume is the whole cost, and not throttling is what lets the breach close's `updatedAt` age test keep meaning "no FAIL for 6 hours". Accepted exposure, recorded in Sharp Edges.

Refinements adopted from plan review (mechanical, 2026-10-16; four reviewers converged, plus Kieran's correctness findings): the fill steps sit after `Sentry check-in (final)`; a header is required on EVERY exit code and must be the single column-0 header (three of the script's own precondition exits print only `TRANSIENT:` text and are real defects, not store states, so they classify UNEVALUATED); the separate red-run gate step, `continue-on-error`, the inner `timeout 150` and the `outcome`/unset arms are replaced by the probe step failing itself (a crash or a hang fails a step by construction, and `Sentry check-in (final)` is `if: always()`); classification is the exit-code map plus a header-agreement check, not a 16-cell table; `fill_exit_code` is dropped (the verdict literal alone is non-empty and non-numeric); the issue body carries the verdict line, the reproduce command and a link, not a re-explanation or script output (the run log, already public, holds the detail). The 6 h `updatedAt` close hysteresis stays as ruled; the review panel's request to cut it was weighed against the CTO ruling and the ruling holds (see `decision-challenges.md`).

## Implementation Phases

### Phase 0 — RED first: the wiring test (cq-write-failing-tests-before)

Create `scripts/zot-fill-rate-standing-wiring.test.sh` before touching the workflow, and see it fail against the current workflow. It is the only owner of the fill-leg contract (say so in its header). Test seam: `ZOT_FILL_WIRING_ROOT` (default: the repo root; test-only, the way `ALARM_GUARD_ROOT` is for the sibling guard) points the suite at a copy of the workflow and of the script tree, so the mutation rows run against scratch copies and AC3 can run the suite against the `origin/main` workflow. It parses the workflow with `python3` + `yaml` (never grep over YAML), finds steps by `id`/`name`, and EXECUTES the fill step bodies against a fixture tree and a PATH-shimmed `gh` (the `watchdog-workflow-idempotence.test.ts` technique). Condition shape (`!cancelled()`, non-empty literals, no `!=`) is not re-tested here: `scripts/alarm-issue-filing-guard.test.sh` discovers the new steps itself and is the independent witness. Shape requirements, because six ratchets bind it (AC6): `set -uo pipefail` (not `-e`); `cases` incremented at the call site, never inside `pass()`/`fail()`; a literal-bound `MIN_CASES` `if` and an accounting sentinel; `PROMOTED_FILES` registration if the guard-vacuity-floor population requires it; one `trap ... EXIT` owning every `mktemp`; assertions relative to the fixture dir with a stated operand; every `$( )` capture guarded (`|| VAR=""` or `|| rc=$?`); no `grep -q` after a pipe.

Test scenarios (about 12 cases):

- T1 Sentry isolation: the set of `steps.<id>` identifiers in the `Sentry check-in (final)` `status:` expression equals `{alarm}` (property, not text equality), the step is still `if: always()`, the job `timeout-minutes` is unchanged at 8, the probe step's `timeout-minutes` is at most 3, and at least 3 fill-referencing steps were found (own-dispatch floor).
- T2 ordering: index(`alarm`) < index(every existing filing step) < index(`Sentry check-in (final)`) < index(`fill`) < index(fill filing steps).
- T3 probe classification and defect flag, executed against a fixture tree whose `scripts/followthroughs/zot-fill-rate-7341.sh` is a fake (rc, stdout): valid pairs (0 with a PASS header) -> PASS, (1 with a FAIL header) -> FAIL, (2 with a TRANSIENT header) -> TRANSIENT; invalid -> UNEVALUATED with outputs written and the step exiting 1: (0 with no header), (2 with only `TRANSIENT:` text and no header, the script's not-executable / parse-library-unreadable / python3-missing exits), (0 with a FAIL header), (3), (127, script absent), two column-0 headers in the body, and body lines holding a workflow command such as `::error::x`, one of them after a bare carriage return, that must reach the log neutralized (control characters including CR are stripped before every line is prefixed with a visible pipe character, because the runner trims leading whitespace before matching `::`). The defect flag: UNEVALUATED -> `fill_defect=true` regardless of the alarm exit code; TRANSIENT with a cause token in the CLOSED benign set (`span=`, `reclaim_at_sample_`, `newest_sample_`, and `too_few_samples` only when the header's `rows_scoped` is below 12) -> `false`; TRANSIENT with any other token (`query_rc=`, `no_emission_rows`, `no_real_boot_id`, `too_few_samples` with `rows_scoped` of 12 or more) -> `true` only when `ALARM_EXIT` is not `2`, `3` or `4`; PASS and FAIL -> `false`. A probe that outlives its step timeout leaves the pre-written `UNEVALUATED` / `fill_defect=true` outputs behind.
- T4 filing, executed against a PATH-shimmed `gh` for the FAIL step and the probe-defect step: no existing tracker -> `gh label create` then `gh issue create` with labels `ci/zot-fill-rate`, `action-required`, `observability`, `domain/engineering`; existing tracker -> `gh issue comment` only; dedupe query failure -> proceeds to create (the documented trade, same as the FIRE step); every lookup uses `--label`, never `--search`; the body holds the verdict line, the reproduce command and the run link, and none of the script's other output; the titles in the filing steps equal the titles in the PASS-close loop (parity); a hostile `FILL_LINE` (`$(id)`, backticks, `@octocat #1`, a markdown link, `::error::x`, a 10 KB tail) reaches the comment and body literal or defanged and capped at 400 characters; no filing step's `env:` references `BETTERSTACK_*`; the FAIL step also closes any open probe-defect issue (a FAIL proves the probe evaluated).
- T5 PASS close: the breach issue's `updatedAt` 5 h ago or 1 minute ago -> no close; 7 h ago -> close with comment; none open -> no-op; two open matches, both old -> both closed. The probe-defect issue closes at once on a PASS whatever its age (7 h, 5 h and 1 minute). The breach close runs first, so a failing defect close cannot starve it (a case with a failing `gh issue close` on the defect issue).

Also edit `apps/web-platform/test/server/watchdog-workflow-idempotence.test.ts`: two new create-or-comment steps move the lookup anti-vacuity counts from 17/15 to 19/17 (one line, noted in the PR). Only the `select(.title` count is an exact pin (15 -> 17); the total is a floor (`toBeGreaterThanOrEqual(17)`), so 17 -> 19 is optional hardening. The pinned shapes the new step must keep: one physical line starting `EXISTING=$(gh issue list` inside the step that also contains `gh issue create`, a bare `ISSUE_TITLE="[ci/<class>] ..."` with no `$`, `--label` as its own flag, and the `gh issue create` following that title assignment within four lines (the pinned create-site check).

### Phase 1 — Workflow edit

Edit `.github/workflows/scheduled-zot-restart-loop.yml`, job `alarm`, inserting AFTER the existing `Sentry check-in (final)` step (the last step today; a failure, hang or timeout in the fill leg therefore cannot delay or kill the monitor check-in):

1. Step `Run standing fill-rate probe` (`id: fill`, `if: ${{ !cancelled() }}`, `timeout-minutes: 3`, env: the three `BETTERSTACK_QUERY_*` secrets plus `ALARM_EXIT: ${{ steps.alarm.outputs.exit_code }}`; budget: one 72 h read of about 3 s measured, and on the FAIL path two sequential reads of at most 60 s each, so the 3-minute cap holds and the job's own 8-minute timeout is untouched). Body: first append `fill_verdict=UNEVALUATED`, `fill_defect=true` and `fill_line=probe step did not complete` to `$GITHUB_OUTPUT` (the pre-write: a 3-minute step timeout otherwise leaves no outputs and fires no filing step; a JOB-level timeout or a cancellation files nothing, only a red run; the end-of-step write overrides it because the runner keeps the last value written, and the pre-write relies on the runner processing `GITHUB_OUTPUT` after the step, read from the actions/runner source and not drilled live), then `echo "::add-mask::${BETTERSTACK_QUERY_HOST,,}"` (the query tool prints the lowercased host, which exact-match secret masking can miss); `rc=0; out="$(bash scripts/followthroughs/zot-fill-rate-7341.sh 2>&1)" || rc=$?`; scrub `*.betterstackdata.com` hostnames from `out`, strip control characters including a bare carriage return (`LC_ALL=C tr -d '\000-\010\013-\037\177'`), then echo every line prefixed with a pipe character (a visible prefix, because the runner trims leading whitespace before matching `::`, so indenting is not a control); extract column-0 headers with a line-anchored `sed -n 's/^zot-fill-rate\[#7341\]: \(PASS\|FAIL\|TRANSIENT\)\( .*\)\{0,1\}$/\1/p'`; require EXACTLY ONE header (zero or several is UNEVALUATED, so no late spoof can pick the verdict); map the exit code (`0` PASS, `1` FAIL, `2` TRANSIENT, anything else UNEVALUATED), and degrade to UNEVALUATED when the header disagrees with the mapped verdict; compute `fill_defect` (true for UNEVALUATED; for TRANSIENT, true when the cause token right after `TRANSIENT` in the header is outside the closed benign set and `ALARM_EXIT` is not `2`, `3` or `4`; else false); write `fill_verdict`, `fill_defect` and `fill_line` (the header line through `strip_log_injection`, the leading `zot-fill-rate[#7341]:` prefix and its following space removed, `#`, `@` and backticks deleted, 400 characters) to `$GITHUB_OUTPUT`; emit `::error::` (FAIL, UNEVALUATED), `::warning::` (TRANSIENT), a `$GITHUB_STEP_SUMMARY` line, and for UNEVALUATED `exit 1` after the outputs are written (the red run is the p3 fallback for when `gh` itself fails). A crash or a hang fails the step by construction.
2. Step `Open or comment fill-rate issue (FAIL)`: `if: ${{ !cancelled() && steps.fill.outputs.fill_verdict == 'FAIL' }}`; bare `ISSUE_TITLE="[ci/zot-fill-rate] Registry store fill rate projects a breach"`; idempotent `gh label create ci/zot-fill-rate`; `EXISTING=$(gh issue list --label ... | jq select(.title | contains($t)))` in the same shape as the FIRE step; create with labels `ci/zot-fill-rate`, `action-required`, `observability`, `domain/engineering`, or comment `"Still projecting a breach at ${NOW} — ${FILL_LINE}. Run: ${RUN_URL}"`. The body: one sentence of origin ("originally the #7341 follow-through, now a standing probe, #7521"), the verdict line, the reproduce command `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/zot-fill-rate-7341.sh`, one sentence of consequence (the `soleur-registry-disk-prd` heartbeat stops at 85 percent and image pulls then fail fleet-wide), the close rule (auto-closes after a PASS run once 6 h pass with no new FAIL comment; because the script returns TRANSIENT while it rebuilds a 24 h baseline after a reclaim or a host replace, expect the close about 25 h after the store recovers), one line saying that closing the issue by hand opens a new one within the hour while the projection holds (fix the store or comment instead), one line saying that silence during that recovery window is the probe rebuilding its baseline, not a dead probe, and the run link. `fill_line` goes in a code span in the body and in each comment. No re-explanation of the slope arithmetic and no script output beyond `fill_line`: the run log holds the attribution lead, and the FAIL-arm prose it would copy is a known drift risk. After filing, the step closes any open probe-defect issue with a one-line loop (a FAIL proves the probe evaluated).
2b. Step `Open or comment probe-defect issue`: `if: ${{ !cancelled() && steps.fill.outputs.fill_defect == 'true' }}`; bare `ISSUE_TITLE="[ci/zot-fill-rate] Registry fill-rate probe defect"`; same label, lookup shape, labels and create-or-comment as step 2; body: the defect cause token or `UNEVALUATED`, the sanitized `fill_line`, the reproduce command, one sentence saying this is the probe failing to evaluate (not a store state, not a restart loop), the close rule (closed by the next PASS or FAIL run), and the run link. Quiet by design when `ALARM_EXIT` is `2`, `3` or `4`: the zot leg already owns those faults (the Sentry error, the PRODUCER_SILENT issue, the INGEST_DARK issue).
3. Step `Auto-close fill-rate issue after a quiet period (PASS)`: `if: ${{ !cancelled() && steps.fill.outputs.fill_verdict == 'PASS' }}`; ONE list by label with `--json number,title,updatedAt`, filtered per title with jq; close EVERY open match of the probe-defect title at once (a PASS proves the probe evaluated, so no age test), and EVERY open match of the breach title (the NIC-GREEN step's shape; the dedupe-failure trade can leave duplicates) with a comment, each only when `fromdateiso8601 < now - 21600` (an unparseable timestamp errors and therefore does not close). `updatedAt` is a proxy for "last FAIL": a human comment or label edit, from anyone on this public repository, defers the close (the safe direction; an outsider can only delay it), and a store flapping around the line with a period over 6 h closes and reopens as a new issue number. That trade is accepted for a p3 leg and no reopen logic is added.

Update the workflow header comment (what the fill leg watches, why it is isolated, that a red run can also mean a broken fill probe, link to the ruling) and nothing else in the file; the existing step comment that the checker exit code is data and the step never `exit 1`s stays true for the `alarm` step.

### Phase 2 — Registration

Register `scripts/zot-fill-rate-standing-wiring` in `scripts/test-all.sh` (next to `scripts/alarm-issue-filing-guard`), then regenerate the shard manifest with `python3 scripts/regenerate-shard-manifest.py --incremental --write` (updates `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv`). Edit nothing under `apps/web-platform/infra/**`.

### Phase 3 — ADR-096 amendment

Add the dated paragraph described above. Leave ADR-184 untouched. The script's prose may be edited only in a line-count-preserving way (a comment insert would shift the `:130` anchor cited by `lint-betterstack-emitter-read.sh`'s disposition map); any added line goes after line 130.

### Phase 4 — Verification (local, read-only)

Run, from the worktree:

```bash
bash scripts/zot-fill-rate-standing-wiring.test.sh
bash scripts/followthroughs/zot-fill-rate-7341.test.sh
bash scripts/alarm-issue-filing-guard.test.sh
bash scripts/lint-betterstack-emitter-read.test.sh
bash apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh
bash scripts/zot-restart-loop-alarm.test.sh
bash scripts/zot-restart-loop-alarm-scrub.test.sh
bash plugins/soleur/test/c4-count-parity.test.sh
bash plugins/soleur/test/fixture-relative-assert.test.sh
bash plugins/soleur/test/fixture-dir-operand-assert.test.sh
bash plugins/soleur/test/guard-vacuity-floor.test.sh
bash .claude/hooks/grep-q-pipe-guard.test.sh
python3 scripts/lint-trap-tempfile-ownership.py --check-highwater
python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt
bash scripts/lint-diagnosis-claims.test.sh
python3 scripts/lint-workflow-step-env-refs.py
python3 scripts/lint-workflow-errexit-capture.py
python3 scripts/lint-workflow-run-body-syntax.py
python3 scripts/lint-workflow-issue-write-scope.py
bash scripts/lint-workflows.sh
bash scripts/lint-orphan-test-suites.sh
bun test plugins/soleur/test/preflight-discoverability-test.test.ts
python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main
npx markdownlint-cli2 knowledge-base/project/plans/2026-10-16-feat-standing-registry-fill-rate-alarm-plan.md knowledge-base/project/specs/feat-one-shot-7521-standing-fill-rate-detection/tasks.md knowledge-base/project/specs/feat-one-shot-7521-standing-fill-rate-detection/decision-challenges.md
(cd apps/web-platform && npx vitest run test/server/watchdog-workflow-idempotence.test.ts test/server/inngest/sentry-monitor-iac-parity.test.ts)
```

Each gate is run with its OWN derived invocation where it has one (`--changed --base origin/main`, `--check-highwater`, `--baseline`), never a hand-enumerated path list, so the AC cannot stay green while the gate goes red.

Then the live read-only probe, once, with the real credentials: `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/zot-fill-rate-7341.sh`; expect rc 0 and a `zot-fill-rate[#7341]: PASS` header (or a TRANSIENT with a stated cause if the host was just replaced). Pre-ship, re-run `gh run list --workflow apply-web-platform-infra.yml` and `gh run list --workflow registry-host-replace-dispatch.yml` and re-read `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`; at plan time both showed only `success` runs and this diff wakes neither (AC1).

### Phase 5 — Ship (owner-go gate before merge)

Rebase onto `origin/main` (never merge main). Run compound before ship. The merge queue is on: arm with a single bare `gh pr merge <N> --squash --auto`. Do not merge or run any production-mutating action without the owner's explicit go; the pipeline stops at that gate.

## Post-merge probe

What the merged PR does: it changes a workflow that the web-host dispatch clock fires hourly (with the cron as fallback). The probe is therefore the first run on `main` that includes the new steps. Gates read against that behavior:

1. Deploy arm: from a detached `origin/main` worktree, `bash plugins/soleur/scripts/deploy-arm.sh find --wait <full-40-hex-sha>`, then `served <full-sha>`. This PR changes no web-platform build input. Measured read-only on 2026-10-16 against a docs-only main commit (`abbd36a696...`): `find` returned `ARM=38878643117 DEPLOYED_SHA=abbd36a6... MATCH=exact DEPLOY=skipped CI=success` and `served` returned `NOT_CONTAINED BUILD_SHA=c896321c...` (production still serves the earlier build, because no deploy ran). The expected verdicts for this change are therefore `DEPLOY=skipped` and `NOT_CONTAINED`; both are recorded, neither is a failure, and the verification of production state for a workflow-only change is item 2 (the workflow executes from the repository, not from the served image).
2. First post-merge run: `gh run list --workflow scheduled-zot-restart-loop.yml --branch main --limit 20 --json databaseId,headSha,conclusion,createdAt,event,status` (measured 2026-10-16: runs are `workflow_dispatch` from the web-host clock and `schedule`, `headSha` is the main tip when the run fired). Take the first completed run whose `headSha` equals the merge sha or descends from it (`git merge-base --is-ancestor <merge-sha> <headSha>` after a fetch), then read it; no dispatch is needed, the hourly clock produces it, and the dispatch would anyway be what that clock does. Step conclusions: `gh run view <id> --json jobs --jq` over the job's `steps[]` (measured shape: `{name, conclusion}` per step). Log line: `gh run view <id> --log` prefixes each line with the job name, the step name and a timestamp ending in `Z`, tab-separated, and the step source is also echoed, so the match is anchored on the step column and on the literal header with unescaped brackets, which the echoed source (it carries backslashes) cannot satisfy: `Run standing fill-rate probe` + tab + timestamp + `Z` + spaces + `zot-fill-rate[#7341]: (PASS|FAIL|TRANSIENT)` followed by a space. Assert: the step concluded `success` with that line present. Expected on the live store: PASS (pcent ~16).
3. Gate-versus-behavior re-read: the probe must not assert "no fill issue exists" (a FAIL would legitimately open one); it asserts "the leg evaluated". A benign TRANSIENT is accepted only with its named cause from the script's distinct TRANSIENT messages (a host replaced within 24 h is the known one) and is re-checked after about 25 h; the leg counts as evaluated only once a PASS or FAIL run has been seen.
4. The pre-merge live run is the read-only script invocation in Phase 4; the post-merge read-through of the real workflow run is the verification that the YAML wiring behaves in Actions.

## Files to Edit

- `.github/workflows/scheduled-zot-restart-loop.yml` (header comment + 4 new steps appended after the Sentry check-in: probe, FAIL filing, probe-defect filing, PASS close; no other step touched)
- `apps/web-platform/test/server/watchdog-workflow-idempotence.test.ts` (exact `select(.title` pin 15 -> 17; floor 17 -> 19)
- `scripts/lint-betterstack-emitter-read.sh` (the disposition for `.github/workflows/scheduled-zot-restart-loop.yml` says the `BETTERSTACK_QUERY_*` env there feeds only the write probe; that becomes false once the fill step passes it to the envelope-anchored reader `scripts/followthroughs/zot-fill-rate-7341.sh`, which already has its own entry; reword the reason, no line numbers change in the script under test)
- `scripts/test-all.sh` (one `run_suite` line)
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` (regenerated entries)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES` 68 -> 69, re-read at rebase time because main moves; with the PLACEMENT / TRUTH / NO SUBSTITUTE comment the neighbouring entries carry; this plan's Observability block declares `credentials_required`, and the repo-global G1 ratchet counts every declaring plan, archived ones included)
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` (dated paragraph)

## Files to Create

- `scripts/zot-fill-rate-standing-wiring.test.sh`
- `knowledge-base/project/specs/feat-one-shot-7521-standing-fill-rate-detection/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-7521-standing-fill-rate-detection/tasks.md`

Touched only under the round-3 CTO ruling (AC2): `scripts/followthroughs/zot-fill-rate-7341.sh` (logic byte-identical apart from the Q2 hardening; line-count-preserving prose edits) and its harness `scripts/followthroughs/zot-fill-rate-7341.test.sh` (five new assertions for the Q2 hardening).

Explicitly NOT touched (diff-scope guard, AC1/AC2): `scripts/zot-restart-loop-alarm.sh`, `scripts/lib/zot-telemetry-parse.sh`, anything under `apps/web-platform/infra/**`, `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, `apply-web-platform-infra.yml`, `*.c4`.

Path-glob verification: `.github/workflows/scheduled-zot-restart-loop.yml`, `scripts/test-all.sh`, both `.tsv` files, ADR-096 and `watchdog-workflow-idempotence.test.ts` each exist on `origin/main` (checked with `git ls-files` during research); `apps/web-platform/infra/**` matches many files and is the trigger glob the diff must avoid.

## Open Code-Review Overlap

Open `code-review` issues whose body names a planned file: #8659 ("33 test suites replace test-helpers' composed EXIT trap ...") and #7942 ("Two mutation batteries ... run in no gate") both name `scripts/test-all.sh`. Disposition: acknowledge both. They concern other suites' trap handling and unregistered mutation batteries; this PR adds one `run_suite` line and a suite that owns its trap, so it neither fixes nor worsens them. None for the other planned files.

## Observability

```yaml
liveness_signal:
  what: the hourly Sentry cron monitor scheduled-zot-restart-loop (unchanged) proves the job ran; the fill leg's own evaluation is proven per run by the step output fill_verdict in {PASS, FAIL, TRANSIENT} and the log header line zot-fill-rate[#7341]:
  cadence: hourly (web-host dispatch clock, ADR-248; cron fallback)
  alert_target: Sentry monitor check-in for the job; the [ci/zot-fill-rate] action-required issue for a FAIL; the probe-defect action-required issue for a defect; the red run only as a fallback
  configured_in: .github/workflows/scheduled-zot-restart-loop.yml (step Run standing fill-rate probe); apps/web-platform/infra/sentry/cron-monitors.tf (existing monitor, untouched)
error_reporting:
  destination: GitHub issue [ci/zot-fill-rate] Registry store fill rate projects a breach (action-required, digest-visible) for a store state; GitHub issue [ci/zot-fill-rate] Registry fill-rate probe defect for a probe defect; workflow run log ::error:: annotation and a failed job as the fallback
  fail_loud: yes — a probe defect files a deduped action-required issue and fails the probe step (red run, the fallback when gh itself fails); an expected TRANSIENT (span, reclaim, stale sample) is quiet and carries a ::warning:: naming its cause in the workflow run log
failure_modes:
  - mode: store is filling toward the heartbeat cliff
    detection: script FAIL (cur >= 85 median-of-12, or positive trailing slope projecting 85 within 14 days)
    alert_route: deduped [ci/zot-fill-rate] issue plus a comment per FAIL run (workflow run log carries the ::error:: annotation)
  - mode: probe defect (marker shape drift, script crash, unexpected exit, hang past the 3-minute step cap)
    detection: exit/header incoherence -> fill_verdict UNEVALUATED, fill_defect=true, the step exits 1; a crash fails the step; a hang or a step timeout leaves the pre-written UNEVALUATED / defect=true outputs (written as the step's first action, overridden by the end-of-step write) so the defect issue is still filed
    alert_route: deduped [ci/zot-fill-rate] probe-defect issue, the workflow run log ::error:: annotation and a red job as the fallback; the Sentry status stays untouched because its expression reads only steps.alarm
  - mode: Better Stack read fails or returns no rows
    detection: script TRANSIENT with its distinct message; the same shared credentials make the zot alarm leg return exit 2, which the Sentry status expression grades error
    alert_route: Sentry monitor errored check-in (via the existing leg) plus the fill leg's ::warning:: in the workflow run log; no second issue while ALARM_EXIT is 2, 3 or 4
  - mode: host replaced within 24 h (span gate)
    detection: script TRANSIENT span=...h_of_history_under_24h (or reclaim_at_sample_..., newest_sample_...)
    alert_route: workflow run log ::warning:: (layer 6) only; the soleur-registry-disk-prd heartbeat covers absolute >= 85 meanwhile, and a replaced host's store refills from empty, so this window is the leg's fastest-growth blind spot: a documented seam with a tracking issue
  - mode: fill-leg-only TRANSIENT with a non-benign cause (for example the 72h archive arm failing alone, no_emission_rows, query_rc, parse drift) while Better Stack is reachable for the zot leg
    detection: the closed benign-token allowlist plus ALARM_EXIT not 2, 3 or 4; first occurrence, no counter state
    alert_route: deduped [ci/zot-fill-rate] probe-defect issue plus the workflow run log ::warning:: (layer 6); the next PASS or FAIL run closes the issue at once (a one-run blip opens an issue that the next PASS or FAIL run closes; a TRANSIENT run leaves it open). Quiet when ALARM_EXIT is 2, 3 or 4, because the zot leg already files its own Sentry error, PRODUCER_SILENT issue or INGEST_DARK issue
logs:
  where: GitHub Actions run log of scheduled-zot-restart-loop.yml (job alarm, step Run standing fill-rate probe); issue comments on [ci/zot-fill-rate]
  retention: GitHub default run-log retention
discoverability_test:
  command: bash scripts/followthroughs/zot-fill-rate-7341.sh
  expected_output: zot-fill-rate[#7341]:
  credentials_required: Doppler soleur/prd_terraform BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD (run as doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/zot-fill-rate-7341.sh) — no unauthenticated substitute can read the live SOLEUR_ZOT_DISK series, so a sandboxed credential-free run would print only a TRANSIENT cause
```

Note on `expected_output`: a blind TRANSIENT also prints the `zot-fill-rate[#7341]:` token, so the discoverability command proves the script is reachable and prints its header, not that the leg evaluated. The liveness check is the public Actions runs and jobs API for the workflow (the probe step ran and concluded, and a PASS or FAIL line follows within about 25 hours of any reclaim).

## Guard Contract

### Guard 1 — fill-leg wiring test (zot-fill-rate-standing-wiring.test.sh)

**Property.** The fill leg can neither change the restart-loop alarm's Sentry status or the reachability of its filing steps, nor file or close an issue on a verdict it did not measure, nor report a probe defect as a store state.

**Assembly.** Every step of every job in `.github/workflows/scheduled-zot-restart-loop.yml`, parsed from YAML (not grepped): the steps whose text references `steps.fill` or `ci/zot-fill-rate` (derived at run time, floor of at least 3), the `status:` expression of `Sentry check-in (final)`, the step order, the single `case` that maps exit code and header to a verdict, and the PASS-close age test. The chokepoints are the `status:` expression and the probe step's classification; the independent witnesses for the condition shape of every issue-writing step are `scripts/alarm-issue-filing-guard.test.sh` (discovers all workflows, ratcheting highwater) and `watchdog-workflow-idempotence.test.ts` (executes the lookup lines), so the quantifier "every step that references the fill outputs" is enforced by a suite this guard does not own.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|------|---------------------|
| 1 | Make the YAML parse yield zero fill steps (rename the step ids and name prefix) | own-dispatch floor: "0 fill steps found" fails instead of exiting 0 |
| 2 | Add `steps.fill.outputs.fill_verdict` to the Sentry `status:` expression | T1 identifier-set equality |
| 3 | Move `Run standing fill-rate probe` before the `alarm` step | T2 ordering (a reorder row; deleting the step would also red, but only a move tests the window the property is about) |
| 4 | Move `Sentry check-in (final)` after the fill steps | T2 ordering |
| 5 | Add a second fill filing step after a compliant first, with a bare `if: steps.fill.outputs.fill_verdict == 'FAIL'` | `alarm-issue-filing-guard.test.sh` (the independent witness) reddens; this suite's step-count floor moves with it |
| 5b | Treat a non-benign TRANSIENT token as benign, or drop the ALARM_EXIT-not-2-3-4 condition, or add a token to the benign set | T3 defect-flag fixtures: one per benign token (false) and one defect token (true); alarm exit 2, 3 and 4 suppress the TRANSIENT-defect filing but not UNEVALUATED |
| 6 | Accept any header with any exit code (drop the header-agreement check), or take the last of two headers | T3: (0 with a FAIL header) and the two-header body expected UNEVALUATED |
| 7 | Default the exit-code `case` to TRANSIENT | T3: rc 3 expected UNEVALUATED |
| 8 | Drop the `exit 1` on the UNEVALUATED branch, or accept rc 2 without a header as TRANSIENT | T3: the step must exit 1; the headerless rc 2 case expected UNEVALUATED |
| 9 | Lower the PASS-close threshold to 3600 s | T5: the 5 h case closes |
| 10 | Harness: replace `pass()`/`fail()` with no-ops | the call-site `cases` conservation check reds |
| 11 | Must-PASS non-canonical input: the same workflow with every fill step id renamed consistently and an extra comment line | stays green (a guard that rejects everything cannot satisfy this row) |

This list stops at row 11 on purpose: `scripts/zot-fill-rate-standing-wiring.test.sh` is authoritative and carries more than 100 mutation rows (the exact `if:` and env pins, the closed key sets of the steps, the job and the workflow, bracket syntax, the `--json` field pins, the `set` lines, the probe-defect step's own hostile-input handling, the close ordering, and a no-op roundtrip must-pass row).

**Anchor.** No stored value: the guard compares the workflow with itself and with test constants. A weakening needs an edit to the workflow AND this test; the independent witnesses are the two suites named in the Assembly, plus the script's own harness (`zot-fill-rate-7341.test.sh`, extended only by the round-3 hardening cases), which pins the header and the exit codes the classification consumes, so producer and consumer cannot both drift in one diff without a second suite reddening.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO ruling 2026-10-16 (V1a). Risks the CTO named and this plan mitigates: (1) a silently dark leg, mitigated by UNEVALUATED + the probe step failing itself + the executed wiring test; (2) issue noise and shared-job blast radius, mitigated by the label-plus-title dedupe, the 6 h `updatedAt` close, step timeouts, strict ordering and the untouched Sentry status; (3) untrusted content in the public issue body, mitigated by publishing only the sanitized verdict line, the reproduce command and a run link (the script output stays in the already-public run log), passed through env vars and never interpolated into the script.

No Product/UX gate: no UI-surface path is in Files to Edit or Create. No marketing, legal, finance or sales implication. GDPR gate not invoked: no regulated-data surface is touched, no personal data is on the path (numeric telemetry only), and the public issue is an existing egress that already carries the restart-loop verdict; the issue body is limited to the sanitized header line, a command and a link.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `git diff --name-only origin/main...HEAD` matches none of `apps/web-platform/infra/**`, `**/cloud-init-registry.yml`, `**/zot-registry.tf`, `**/variables.tf`, `.github/workflows/apply-web-platform-infra.yml`, `*.tf` (so neither the registry host replace gate nor the infra apply fires).
- [x] AC2: logic byte-identical; line-count-preserving prose edits allowed. `git diff origin/main...HEAD -- scripts/zot-restart-loop-alarm.sh scripts/lib/zot-telemetry-parse.sh` is empty; `scripts/followthroughs/zot-fill-rate-7341.sh` differs from `origin/main` only by prose edits that keep the line count (line 130 identical: `sed -n 130p` on both) plus the round-3 Q2 hardening (bounded `pcent` regex, `future_dated_newest_sample` gate), all added after line 130.
- [x] AC3: `bash scripts/zot-fill-rate-standing-wiring.test.sh` passes with every T1-T5 case and, with `ZOT_FILL_WIRING_ROOT` pointed at a scratch copy holding the `origin/main` workflow (`git show origin/main:.github/workflows/scheduled-zot-restart-loop.yml`), exits non-zero (RED first, recorded in the PR).
- [x] AC4: the Sentry `status:` expression in the workflow is byte-identical to `origin/main`'s (`git diff origin/main...HEAD -- .github/workflows/scheduled-zot-restart-loop.yml` shows no hunk inside it).
- [x] AC5: `bash scripts/alarm-issue-filing-guard.test.sh` is green with its `.highwater` unchanged (new steps add no violation), and `watchdog-workflow-idempotence.test.ts` is green with the counts 19/17.
- [x] AC6: the six ratchets pass for the new/edited `*.test.sh`: grep-q-pipe-guard (`bash .claude/hooks/grep-q-pipe-guard.test.sh`), fixture-relative-assert, fixture-dir-operand-assert, guard-vacuity-floor, lint-trap-tempfile-ownership (`--check-highwater`, highwater not raised), lint-shell-capture-exit (`--baseline scripts/lint-shell-capture-exit.baseline.txt`, baseline not raised).
- [x] AC7: `bash scripts/followthroughs/zot-fill-rate-7341.test.sh`, `scripts/zot-restart-loop-alarm.test.sh` and `scripts/zot-restart-loop-alarm-scrub.test.sh` pass (the alarm suites unchanged; the fill-rate harness gains the round-3 cases, floor 30 to 35).
- [x] AC8: `bash plugins/soleur/test/c4-count-parity.test.sh` is green with `model.c4` unedited.
- [x] AC9: `bash scripts/lint-orphan-test-suites.sh` and the shard-manifest tests pass (the new suite is registered in `scripts/test-all.sh`, `suite-shard-legs.tsv`, `suite-durations.tsv`).
- [x] AC10: the live read-only probe (Phase 4) was run once before merge and its verdict line is pasted in the PR body; the allowed set is PASS, a FAIL (which would legitimately have opened the issue), or a TRANSIENT whose message names one of the script's distinct causes.
- [ ] AC11: the PR body uses `Ref #7521`, has a `## Changelog` section, contains no closing keyword for #7521, and uses "unavailable" or "disruption" wording only.
- [x] AC12: ADR-096 carries the dated paragraph (grep for `#7521` in that file returns one hit).
- [x] AC12b: `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` equals the live count of plans declaring `credentials_required` after the bump (`bun test plugins/soleur/test/preflight-discoverability-test.test.ts` green), re-derived after the final rebase; the bump is the last commit before arming the merge, since it is the one line expected to conflict when main moves.
- [x] AC13: the issue body published by the FAIL step is verified, in T4, to hold the verdict line, the reproduce command and the run link, and none of the script's other output.
- [ ] AC14: `gh run list --workflow apply-web-platform-infra.yml` and `--workflow registry-host-replace-dispatch.yml` were re-read before the merge arm and the runbook re-read; recorded in the PR body.
- [ ] AC15: rebased on `origin/main` with no merge commit; the PR is armed with a single bare `gh pr merge <N> --squash --auto` only after the owner's explicit go.

### Post-merge (automated verification)

- [ ] AC16: deploy-arm `find --wait <full-sha>` and `served <full-sha>` verdicts recorded from a detached `origin/main` worktree (`DEPLOY=skipped` and `NOT_CONTAINED` are the expected, recorded verdicts for this workflow-only change).
- [ ] AC17: the first completed `main` run of `scheduled-zot-restart-loop.yml` at or after the merge sha contains the fill header line (verdict in the AC10 allowed set) and the `Run standing fill-rate probe` step concluded `success`, per `## Post-merge probe`.

## Test Scenarios

Covered in Phase 0 (T1-T5) and, for the script, by its existing harness (extended with the round-3 hardening cases). Live scenario: store at 16 percent flat or falling -> PASS, no issue, no comment. Synthetic scenario (T3/T4 fixtures, never production): a store at 40 percent rising 8 pp/day -> FAIL, one issue, hourly comments, closes only after six quiet hours.

## Sharp Edges

- A red run of this workflow can also mean a broken fill probe (the workflow header and the ADR-096 paragraph say so), in addition to a restart loop, and does not by itself mean a store state; the actionable surface is the probe-defect issue.
- Inherited, not introduced here: anyone able to write an envelope row into the shared Better Stack source can forge a FAIL (a public issue plus a comment per run) or blind the leg with a fresh `boot_id` (n=1 -> TRANSIENT). The ingest-only token sits on every host; comment volume is bounded only by the run cadence (one run per hourly slot, plus collisions and the cron fallback) and the CTO ruled no throttle (Decision Record row 7).
- A `run:` body with no `shell:` key executes under `bash -e` (GitHub's default; the fill steps set their own pipefail); the probe capture must be `|| rc=$?` and the classification must not use a bare `$(grep ...)`.
- GitHub Actions `==` is loose: `null == '0'` is true, so no filing step compares a numeric literal; each compares the non-empty, non-numeric verdict literal only.
- The probe step has no `continue-on-error`: a failing step does not cancel the job, so the `!cancelled()` filing steps and the `if: always()` Sentry check-in still run, and the job ends red.
- A slot can hold two runs (two web hosts plus the cron fallback, serialized by the concurrency group with one pending run), so a FAIL produces up to two comments per hour; "hourly comments" means at least one, not exactly one.
- Job-timeout headroom is measured, not assumed: the `alarm` job ran 20-28 s across the last 12 `main` runs (`gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs`, `started_at`/`completed_at`, 2026-10-16), against `timeout-minutes: 8`; the fill leg adds about 3 s, at most about 2 minutes on a FAIL, and its own 3-minute step cap. The job timeout stays 8 and T1 pins it. A job timeout is recorded as `cancelled`, which the dispatch clock treats as non-covering (`watchdog-dispatch-clock.ts`), so exceeding it would re-dispatch the slot; the measured headroom is why that cannot happen here.
- The fill leg is deliberately outside the Sentry monitor: a run where the fill steps are skipped or cancelled still checks in `ok`. Nothing in Sentry covers the leg's own liveness (accepted residual, recorded in the ADR-096 paragraph).
- The fill leg shares credentials with the zot leg: a credential fault shows once, as the zot leg's exit 2 (Sentry error), and again as the fill leg's quiet TRANSIENT. That is intended, and the reason TRANSIENT files nothing.
- Edit `scripts/followthroughs/zot-fill-rate-7341.sh` only in a line-count-preserving way above line 130 (`lint-betterstack-emitter-read.sh` cites its line `:130`); the CTO round-3 ruling is "logic byte-identical; line-count-preserving prose edits allowed", plus the Q2 hardening added after line 130. Check with `sed -n 130p` against `origin/main` and run `scripts/lint-betterstack-emitter-read.test.sh`.
- Scheduled-job precedent (ADR-033, Inngest over a GitHub Actions cron): no new cron is added. The workflow already carries its `gate-override: new-scheduled-cron-prefer-inngest` justification (a bash pipeline over credentialed reads, I7's uncontained class); the new leg inherits it.
- The Actions run log of this public repository is world-readable and the step source is echoed into it; nothing the probe prints may be a credential, and the step passes the three `BETTERSTACK_QUERY_*` secrets only through `env:` (masked by Actions), never as arguments.
- A plan whose `## User-Brand Impact` section is empty, holds only filler text, or omits the threshold fails `deepen-plan` Phase 4.6; this one states `aggregate pattern`.

## Deferred items (each needs a tracking issue filed at ship, with a roadmap milestone)

The lead filed these three trackers at ship: (e) #10462, (d) #10463, (f) #10464 (the implementing agent does not file issues). The earlier items for the script's FAIL-arm prose refresh and the sample-parse and future-dated hardening are no longer deferred: they are done in this PR under the round-3 CTO rulings.

- (e) Rename `zot-fill-rate-7341.sh` to a standing name. Class: pre-existing-unrelated. Trigger (as filed in #10462): the first commit after this PR's merge that touches `apps/web-platform/infra/zot-registry.tf` or `apps/web-platform/infra/cloud-init-registry.yml`. The rename touches two path references under `apps/web-platform/infra/**`, so it must ride a change that is already allowed to fire the infra apply. #10136 (OPEN on 2026-10-16) may be that vehicle but is not the trigger: its closing criterion accepts a decision with no apply.
- (d) JSON-aware parity: reconcile the script's post-decode invariants with a JSON-aware variant in `scripts/lib/zot-telemetry-parse.sh` (the script header already files this). Class: pre-existing-unrelated. Event-grep trigger: `git log --since=2026-10-16 -- scripts/lib/zot-telemetry-parse.sh scripts/followthroughs/zot-fill-rate-7341.sh` returns a commit that is not part of #7521 (the parse library or the script changed again, so the two copies can drift).
- (f) Hoist the absolute `cur >= 85` check above the 24 h `MIN_SPAN_HOURS` gate, so the leg is not dark for about 25 h after any reclaim or host replace while the store refills from empty (the heartbeat is the only cover meanwhile). Class: contested-design. Approaches: hoist the level check after the 12-sample gate; a separate level-only leg; a shorter `MIN_SPAN_HOURS`. Date trigger: 2026-11-16. The consecutive-run streak escalation was dropped by the CTO ruling in favour of the stateless probe-defect issue.

## Rollback

Revert the workflow hunk (one commit); no state to unwind. An open `[ci/zot-fill-rate]` issue, if one was filed, is closed by hand with a pointer to the revert.
