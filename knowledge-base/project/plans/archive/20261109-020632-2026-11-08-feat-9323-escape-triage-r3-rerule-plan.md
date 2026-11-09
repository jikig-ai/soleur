---
title: "feat: triage the #9323 PBG escape verdict and run the #9729 R3 go/no-go re-ruling"
type: fix
date: 2026-11-08
slug: 9323-escape-triage-r3-rerule
branch: feat-one-shot-9323-escape-r3-rerule
issue: 9323
priority: high
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# feat: triage the #9323 PBG escape verdict and run the #9729 R3 go/no-go re-ruling

## Overview

One PR resolves the two open residual items of the ci-lever work merged by PR #12412. Item 1 triages the FAIL verdict the #9323 soak probe (`scripts/followthroughs/pr-battery-gate-saving-9323.sh`) posted on 2026-11-08T20:20Z: its single "escape" is a merge-commit ci.yml push run that went red on two curl(56) network flakes in jobs the path-gate cannot affect (`lint-bot-statuses` actionlint download, `tenant-integration` Supabase CLI install), which is not an ADR-262 R1 escape; the technical fork among widening the declaring array, reverting the PR arm, or fixing the probe's escape classification was ruled at plan time (Arm A — fix the classification; `decision-challenges.md`, sequential-fallback CTO execution), and the ruling is implemented. Item 2 executes the second term of the operator SCHEDULE comment on #9729 (2026-11-08T13:48Z): re-run the R3 go/no-go ruling on a fresh 300-commit window per `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`, commit the receipts, and post the third verdict comment on #9729. Schedule term 1 (replay-tool allowlist for post-umbrella job names) already shipped via 33f0b8ee83 + PR #12412 and is verified, not redone. Stage 4 stays non-activated throughout: `CI_PR_AFFECTED` unset, `PR_AFFECTED_LOCKED` intact in `scripts/ci-pr-selection.sh`, merge_group keeps the full battery.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch; the value is the fail-closed default, not a carried-forward one.

## Problem Statement / Motivation

Two live threads remain after PR #12412 merged (2026-11-08T20:16Z):

1. **#9323 (OPEN).** The 2026-11-08T20:20Z `PBG_UNBOUNDED` verdict comment is `FAIL: 1 escape(s); widen the declaring array (ADR-262 R1) or revert the PR arm`, naming "PR 12390 was green but its merge-commit push run on 22608aa4cc63a78e81f3d64b9627410954da30d0 is failure". The parent session established that the push run's only failures were curl(56) network flakes in jobs outside the gated set, and dispatched `gh run rerun --failed` on both. Verified at plan time: ci.yml push run `42483264409` now reads `conclusion=success`; the `tenant-integration` run `42483264452` reads `in_progress` (a different workflow the probe never reads — the probe reads `workflows/ci.yml/runs` only, `scripts/followthroughs/pr-battery-gate-saving-9323.sh:330`). So the named "escape" self-clears on the probe's next sweep — but the classification defect stands: `_pbg_w_esc` (:330-340) counts ANY red push-run conclusion (`failure|timed_out|startup_failure|action_required`) as an ADR-262 R1 escape without checking which jobs failed, so the next unrelated-job flake on a merge-commit push run produces the same false FAIL. ADR-262 R1 (:86-95) defines an escape as a change that *breaks a battery* without touching its declared paths; a flake in `lint-bot-statuses` or `tenant-integration` is not that.
2. **#9729 (OPEN).** The operator SCHEDULE comment (2026-11-08T13:48Z) set two terms. Term 1 (allowlist for post-umbrella job names) shipped — `scripts/ci-pr-affected-replay.py:219-222` now carries `rule-body-lint`, `adr-ordinals`, `grok-fidelity`, `harness-discovery`, `marketplace-manifest-guard`, `credential-path-guard`, `lockfile-sync`, `sandbox-canary-capture-gate`, `service-role-allowlist-guard`→(`service-role-allowlist-gate`), `tc-document-sha-guard`, `cla-check`, `cla-evidence`; verify, do not redo. Term 2 — re-run the R3 go/no-go on a fresh 300-commit window once the queue-cancel rate settles — is now live: the parent measured 0 cancelled of the last 60 merge_group runs (2026-11-07T19:58Z → 2026-11-08T21:12Z; 37 success / 21 failure — settled failures are evaluable; cancelled runs were what left suite legs unsettled and drove criterion a's 19.38% worst-case bound).

## Proposed Solution

**Item 1 — ruled, now implement.** Per `hr-technical-fork-is-not-an-operator-question` the three-way fork {widen the declaring array (ADR-262 R1) / revert the PR arm / fix the probe's escape classification} was ruled as a technical fork at plan time: **Arm A — fix the probe's escape classification** (`decision-challenges.md` row 1; executed sequential-fallback because no subagent spawn was available in the planning subagent, disclosed — the work phase may re-verify via the parent's batched ruling gate but implements this ruling, not a re-vote). On a red push-run conclusion, `_pbg_w_esc` additionally reads the run's jobs and counts an escape only when a job in the gated family failed — the same `test-scripts*` `startswith` set the examine arm already uses at :281 — classifying a red run whose failures are all outside the gated set as a new reported bucket (not an escape, not silently absent), and a jobs-read failure as `pending`/not-evaluable, never `ok`.

**Item 2 — execute the runbook.** Re-run `scripts/ci-pr-affected-replay.py` collect/ejections/aggregate on a fresh 300-commit window, re-run the pinned-tree audit (criterion b), re-measure the baseline + sampled saving (criterion c), re-run the reader audit (criterion d), compute the third verdict via `verdict`, commit receipts under the schedule-named receipts dir, amend ADR-276 (the established amendment pattern — new `## Amendment` section + a new last `Go/no-go receipt:` line), append the runbook §2 status line, run `scripts/ci-pr-affected-preactivation.sh` from a detached origin/main checkout, and post the third verdict comment on #9729.

## Technical Considerations

- **Live duplicate (collision).** `collision-precheck.sh` flagged PR #12439 — it is this branch's own auto-created draft PR (self-hit, not a foreign change). It also flagged live `test-all.sh --print-selection` processes inside `.worktrees/s4-r3-replay` (detached HEAD at 4fba0d512e) writing `/var/tmp/s4-r3-20261108/` (`units-commits-1-of-1.jsonl`, `units-ejections.jsonl`, created 2026-11-08T22:28Z): an R3 collect is already in flight. The replay tool is resumable; Phase 0 inventories it and adopts its output if alive, restarts if dead — never runs a second concurrent collect.
- **API budget.** The probe's `need_min` preflight (:368-377) models 2 reads per qualifying run in the escape arm; the classifier arm adds a jobs read ONLY on red push runs (rare) — note the change in the header comment, no floor change needed in expectation.
- **The probe keeps posting FAIL until this merges.** The sweeper runs the committed (unfixed) probe; another false escape comment may land on #9323 before merge — acceptable, and the corrected-verdict comment distinguishes it.
- **NFRs** (per `knowledge-base/engineering/architecture/nfr-register.md` assessment): CI-cost measurement accuracy (the probe is the measure), workflow reliability (rerun semantics). No user-facing NFR moves.
- **`Ref`, never `Closes`.** Neither issue closes: #9323 stays open until the soak PASSES on its own terms; #9729's retire-vs-schedule call is operator-owned per #10448. The PR body MUST use `Ref #9323` / `Ref #9729`.

## Research Insights

**Relevant file paths**

- `scripts/followthroughs/pr-battery-gate-saving-9323.sh` — `_pbg_w_esc` escape arm :322-340 (conclusion→bucket case at :334-336); verdict aggregation :543-568 (`escape)` row case :555, FAIL line :564); `test-scripts*` job prefix convention :281; `need_min` API model :368-377; header exit vocabulary :65-69; RETIREMENT instructions :80-82.
- `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` — probe suite (registered `scripts/test-all.sh:7094`; shard leg `suite-shard-legs.tsv:443`; duration `suite-durations.tsv:441`).
- `scripts/ci-pr-affected-replay.py` — allowlist :202-222 (term-1 shipped); `audit`/`collect`/`ejections`/`aggregate`/`cp-upper`/`verdict` subcommands (runbook §§4-5).
- `scripts/ci-pr-affected-preactivation.sh` — read-only pre-activation gate; `verdict=` line reads the LAST `Go/no-go receipt:` line in ADR-276 and tolerates the archived path (`(receipt-archived)` suffix).
- `scripts/ci-pr-selection.sh:90` — `readonly PR_AFFECTED_LOCKED=1` (activation lock, verified present).
- `.github/workflows/ci.yml:399` — `vars.CI_PR_AFFECTED != ''` switch (verified unchanged).
- `scripts/ci-pr-affected-audit.accept.tsv` — the pinned accept file (864 KB) the criterion-b audit takes via `--accept`.
- `scripts/ci-demand-census.sh` — baseline measurement tool (12 h max span; two adjacent windows per the criterion-c receipt recipe).
- `scripts/test-affected-kb-consumers.test.sh` — criterion-d dropped-consumer census.
- `scripts/lib/test-relevance-paths.sh` — the declaring array ADR-262 R1's remedy edits (Arm B only).
- ADR-262 Residuals :86-95 (R1 definition); ADR-276 amendment pattern and receipt lines :460, :642 (last wins).
- Receipts dir (verified on disk): `knowledge-base/project/specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/` — holds R2's `go-no-go.md`, `replay-summary.txt`, `replay-commits.tsv`, `ejections-window.json`, `index-audit*.out`, `criterion-c.md`, `census-w1/w2.txt`, `reader-audit.md`. R3 lands in an `r3/` subdirectory to keep R2 receipts intact (precedent: `…10862-norun-investigation/receipts/rerun/`).

**Premise Validation (Phase 0.6).** Checked and held: #9323 OPEN (verdict comment verified verbatim, 2026-11-08T20:20:37Z); #9729 OPEN (SCHEDULE comment verified, 2026-11-08T13:48:59Z); PR #12412 MERGED 2026-11-08T20:16:45Z; runs 42483264409 (`success` post-rerun) and 42483264452 (`in_progress`); all cited scripts/runbook/ADR-262/ADR-276/receipts-dir present on disk; commit 33f0b8ee83 real (3-file allowlist+test diff); allowlist now covers all six named post-umbrella jobs plus the rest of the folded set. Stale/mismatch: the ADR-276 receipt line names `specs/feat-one-shot-ci-lever-residuals/receipts/go-no-go.md`, now archived — the gate tolerates this by design (`(receipt-archived)`), and this plan's amendment writes the new last line anyway.

**Property List (Phase 0.6b).** (P1) a binding ruling among the three fork options, implemented; (P2) the #9323 FAIL verdict resolved honestly — the false escape cleared AND the false-FAIL mechanism addressed if the ruling so chooses; (P3) the third go/no-go ruling (GO/NO-GO/UNDECIDED) computed on a fresh window with committed receipts and a posted comment; (P4) non-activation invariants preserved end-to-end; (P5) both items in one PR on this branch.

**Cut List (Phase 0.6b).** None — the ask names no new machinery. Every mechanism already exists on `origin/main`: the probe, the replay tool, the preactivation gate, the census tool, the accept file, the receipts convention, the ADR amendment pattern. The only candidate code change (classifier fix inside `_pbg_w_esc`) is contingent on the CTO ruling and modifies an existing guard rather than adding one.

**Institutional learnings applied**

- `specs/archive/20261108-160216-feat-one-shot-12360-ci-lever-threads/decision-challenges.md` — the exact `| Item | Class | Ruling |` convention and the "Ruled by CTO agent" row format this branch's decision-challenges.md mirrors.
- `knowledge-base/project/learnings/workflow-patterns/2026-11-08-parallelizing-a-serial-gate-changes-its-resource-bound-not-just-its-speed.md` — PBG's own bounded-parallel lesson; the jobs read added on the escape path must ride the same `api()` deadline contract, never a new fetch primitive.
- Guard-vacuity corpus (e.g. `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`) — drives the Guard Contract section: the classifier change needs must-RED rows on BOTH directions (unrelated-red ≠ escape AND gated-red = escape) plus a must-PASS row.
- `hr-no-dashboard-eyeball-pull-data-yourself` — all verdict figures come from the scripts' own outputs, never console eyeballs.

**External research:** skipped — strong local context; repo-internal CI machinery with an established runbook, receipts convention and ADR pattern. External best practices add nothing the runbook doesn't already encode.

**Functional overlap check (1.5b, sequential):** no new capability is invented — every tool the plan invokes already exists and is named by the schedule comment/runbook; the conditional classifier edit lands inside the existing probe file.

**Research Reconciliation — Spec vs. Codebase.** No `spec.md` exists for this branch (no spec claims to inherit). Repo research surfaced one documentation drift worth noting, not a spec fiction: the ADR-276 `Go/no-go receipt:` line points at a pre-archive path the gate resolves via its `(receipt-archived)` arm; the new amendment writes a fresh last line to a stable archived path.

## Implementation Phases

### Phase 0 — Coordination snapshot (blocking, cheap)

1. `gh run view 42483264409 --json status,conclusion` and `gh run view 42483264452 --json status,conclusion` — record terminal states; the #9323 comment quotes them.
2. Inventory the in-flight R3 collect: `ls -la /var/tmp/s4-r3-20261108/`; `ps` the `s4-r3-replay` worktree processes. **If alive:** adopt the output dir as this ruling's evidence base (the tool is resumable — do not start a second collect; record the adoption in `receipts/r3/adoption-note.md`). **If dead/stale:** delete nothing; rerun `collect` against the same `--out` (it resumes) or a fresh `OUT=/var/tmp/s4-r3-<date>`.

### Phase 1 — Item 1: #9323 escape triage

1. **CTO ruling — taken at plan time (binding).** The ruling is recorded in `knowledge-base/project/specs/feat-one-shot-9323-escape-r3-rerule/decision-challenges.md` (`Ruled by CTO agent, 2026-11-08: fix the probe's escape classification (Arm A) - …`, sequential-fallback execution, disclosed). The work phase implements it directly — no re-spawn needed; if the parent's batched technical-ruling gate re-runs the seat it adjudicates against the same record: the verbatim 20:20Z FAIL comment; both job-flake evidences (run 42483264409 `lint-bot-statuses` curl(56) on actionlint download ~13:06Z; run 42483264452 `tenant-integration` curl(56) on Supabase CLI install ~13:06Z; rerun dispatched, 42483264409 now `success`); ADR-262 R1 text (:86-95); probe code refs (:330-340, :555, :564); and the three arms {widen the declaring array / revert the PR arm / fix the probe's escape classification}. Instruction: "do NOT use AskUserQuestion". The brief MUST enumerate the fact that would disqualify each arm (a binding ruling on an incomplete record is the #7442 defect): Arm A (classifier fix) is unavailable if the gated family cannot be named without a second enumeration that drifts — mitigated by reusing the examine arm's `test-scripts*` prefix (:281), so the disqualifier reduces to "the probe reads only ci.yml; a battery break surfacing only in a non-ci.yml push workflow is already invisible to it either way" (the classifier neither fixes nor worsens that bound); Arm B (widen declaring array) is unavailable if the failing jobs name no battery subject — `lint-bot-statuses`/`tenant-integration` are not declared paths of any gated battery, so "widening" has no array member to widen toward and would instead have to declare infra jobs as battery subjects, arming the batteries on every unrelated flake (defeating the gate's measured ~295-min→skip saving); Arm C (revert) is unavailable unless the gate itself is judged net-harmful — it forfeits the measured saving to fix a false-positive the classifier edit removes at ~40 lines. Persist as a `## Decision Classes` row in `knowledge-base/project/specs/feat-one-shot-9323-escape-r3-rerule/decision-challenges.md` (`Ruled by CTO agent, <date>: <decision> - <rationale>`).
2. **Implement the ruled arm:**
   - *Arm A — classifier fix:* in `_pbg_w_esc`, on a red-family conclusion, read the push run's jobs (extend the same `runs?event=push&head_sha=` read to also capture `.workflow_runs[0].id`, then `repos/$REPO/actions/runs/<id>/jobs?per_page=100` through the existing `api()` deadline primitive). Escape iff ≥1 `conclusion≠success,skipped` job name matches the gated family (`test-scripts*`, same prefix as :281). All-failed-jobs-outside-the-gated-set → new bucket row (e.g. `unrelated <detail>`): counted beside `dropped`/`open_prs` in the note line, NEVER in `escapes`. Jobs-read failure/empty on a red run → `pending` (not evidence either way), never `ok`. Update the header's escape-arm description and the `need_min` comment.
   - *Arm B — widen declaring array:* edit `scripts/lib/test-relevance-paths.sh` per ADR-262 R1 (that edit itself arms every gated battery on this PR — expected and honest).
   - *Arm C — revert the PR arm:* revert the PR-9324 gate machinery per its RETIREMENT-style reversal.
3. **Tests** (Arm A; the other arms carry their own machinery's existing suites): extend `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` with the Guard Contract matrix rows below — red-run-with-gated-failure → escape; red-run-unrelated-only → not escape; red-run-jobs-read-fails → pending/not-evaluable; green run → ok.
4. **Re-verdict.** `GH_TOKEN=… PBG_UNBOUNDED=1 bash scripts/followthroughs/pr-battery-gate-saving-9323.sh` locally (~11 min); post the corrected verdict comment on #9323 naming the rerun outcomes, the classification change, and the honest new output (whatever it computes — PASS needs the saving bar + no escapes on its own terms; anything else is reported, not edited).
5. Sweep the probe's RETIREMENT block (:80-82) — confirm no instruction the classifier change falsifies.

### Phase 2 — Item 2: #9729 R3 re-ruling

1. **Collect** (adopted or fresh per Phase 0): `python3 -I scripts/ci-pr-affected-replay.py collect --out <OUT> --commits 300 --base origin/main` (resumable; `--chunk I/K` if parallelism needed).
2. **Ejections:** `python3 -I scripts/ci-pr-affected-replay.py ejections --out <OUT> --commits 300 --base origin/main` (~25 min).
3. **Aggregate:** `python3 -I scripts/ci-pr-affected-replay.py aggregate <OUT> --expect-commits 300 --out <OUT>/replay-summary.txt` + `cp-upper` for the point-estimate bound reads (criterion a).
4. **Criterion b:** `git worktree add --detach /var/tmp/s4-audit origin/main`; `python3 -I scripts/ci-pr-affected-replay.py audit --root /var/tmp/s4-audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv > index-audit.out` — plus the bare no-`--accept` run the R2 convention commits alongside (`index-audit-bare-noaccept.out`); `git worktree remove --force`.
5. **Criterion c:** fresh baseline via `bash scripts/ci-demand-census.sh --start <t0> --end <t1> --workflow ci.yml --summary` over two adjacent closed 12 h windows (LONGER SPANS recipe); sampled saving over the 20 most recent successful pull_request runs (mirror `receipts/criterion-c.md`: per-run changed files → `--print-selection` → priced via `suite-durations{,-heavy}.tsv`); canary timing leg ≤120 s carried per its precedent.
6. **Criterion d:** `bash scripts/test-affected-kb-consumers.test.sh` + the reader census → `reader-audit.md`.
7. **Verdict:** `python3 -I scripts/ci-pr-affected-replay.py verdict --a <s> --b <s> --c <s> --d <s>` — read `computed=` (exit code carries no verdict); GO / NO-GO / UNDECIDED all equally reportable.
8. **Receipts** → `knowledge-base/project/specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/r3/`: `go-no-go.md` (mirroring the R2 receipt's shape: rule of the record, criterion table, computed verdict, why-line, non-activation statement, closing `SOLEUR_PR_AFFECTED_VERDICT verdict=<V> ruled=confirmed date=2026-11-08`), `replay-summary.txt`, `replay-commits.tsv`, `ejections-window.json`, `index-audit.out`, `index-audit.err`, `index-audit-bare-noaccept.out`, `criterion-c.md`, `census-w1.txt`, `census-w2.txt`, `reader-audit.md`, `preactivation.out`, `adoption-note.md`.
9. **ADR-276 amendment:** new `## Amendment 2026-11-08 (S4 go/no-go third re-ruling, #9729)` section (status stays `adopting`; verdict + four criterion figures + the explicit non-activation paragraph) and a new LAST `Go/no-go receipt:` line → `knowledge-base/project/specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/r3/go-no-go.md`.
10. **Runbook append:** `ci-pr-affected-activation.md` §2 gains the dated third-ruling status line (its established append convention).
11. **Preactivation gate:** `bash scripts/ci-pr-affected-preactivation.sh` from a detached `origin/main` checkout (or the `s4-r3-replay` worktree refreshed to tip); capture `SOLEUR_PR_AFFECTED_PREACTIVATION ready=…` into `receipts/r3/preactivation.out`.
12. **Verdict comment on #9729** mirroring the prior comments' shape: `computed=<V> reason=…`, the criterion table, the non-activation statement, the receipts path.

### Phase 3 — Ship

1. `knowledge-base/project/specs/feat-one-shot-9323-escape-r3-rerule/{decision-challenges.md,tasks.md}` committed (decision-challenges written at Phase 1 step 2, amended if later phases surface more rows).
2. Non-activation verification sweep (AC8's grep assertions) before PR-ready.
3. PR body: `Ref #9323` / `Ref #9729` — never `Closes`.

## Files to Edit

- `scripts/followthroughs/pr-battery-gate-saving-9323.sh` — Arm A only (CTO ruling): `_pbg_w_esc` job-scoped escape classification + header/`need_min` comments.
- `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` — Arm A only: the matrix-row fixtures.
- `scripts/lib/test-relevance-paths.sh` — Arm B only.
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` — R3 amendment section + new last `Go/no-go receipt:` line.
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` — §2 dated status append.

## Files to Create

- `knowledge-base/project/specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/r3/` — the 13 receipt files named in Phase 2 step 8.
- `knowledge-base/project/specs/feat-one-shot-9323-escape-r3-rerule/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-9323-escape-r3-rerule/tasks.md`

## User-Brand Impact

- **If this lands broken, the user experiences:** a public GitHub issue comment on #9323/#9729 asserting a wrong CI verdict — the repo's public face of engineering rigor misreporting its own evidence (worst case: a false GO comment later needing public correction).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data in scope — the receipts are CI-run aggregates (commit SHAs, run ids, suite names); the one reachable user-visible surface is the same public-issue-comment channel already modeled as `publicReader` in the C4 model.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the blast radius is one public comment correctable by a follow-up comment, with the committed receipts as the auditable record — no user data, no production surface, no money path.

*Scope-out override:* `threshold: none, reason: every touched path is repo-internal CI measurement machinery (scripts/, runbook, ADR, receipts); the only externally visible artifacts are GitHub issue comments on two already-public engineering issues`.

## Observability

(The Phase 2.9 detection list does not reach repo-root `scripts/`; included anyway because the deliverable IS an observability probe — the escape classifier — and the probe's own liveness is worth declaring.)

```yaml
liveness_signal:
  what: scheduled-followthrough-sweeper runs pr-battery-gate-saving-9323.sh and posts its verdict line to #9323
  cadence: sweeper schedule (per-issue earliest= directive; probe wall-capped at 300 s under the sweeper)
  alert_target: issue #9323 comments (FAIL posts verbatim); main-side red is separately paged by notify-main-failure
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml + the <!-- soleur:followthrough script=… --> directive on issue #9323

error_reporting:
  destination: probe stdout captured by the sweeper → posted to the tracker issue; local runs post via operator gh
  fail_loud: exit 1 FAIL verdict line; exit 3 CANNOT ESTABLISH (retried by the sweeper); exit 2 NOT YET

failure_modes:
  - mode: escape classifier counts an unrelated-job flake as an escape (the defect Arm A fixes)
    detection: FAIL verdict names a push run whose failed jobs are all outside the gated family — visible in the verdict comment itself
    alert_route: #9323 comment (this plan is the fix)
  - mode: jobs read fails on a red push run
    detection: `pending` bucket in the probe output — reported, never folded to ok
    alert_route: #9323 comment via the sweeper's next sweep

logs:
  where: sweeper run logs (GH Actions) + #9323 comment trail + receipts/r3/ committed artifacts
  retention: GH Actions retention for logs; receipts are permanent in git

discoverability_test:
  command: bash scripts/followthroughs/pr-battery-gate-saving-9323.sh
  expected_output: CANNOT ESTABLISH
```

## Guard Contract

### Guard 1 — PBG escape classification is job-scoped (Arm A ruled 2026-11-08; had Arm B/C been ruled this section's subject would have been moot and dropped from the diff, not weakened)

**Property.** A merge-commit ci.yml push run that is red counts as an ADR-262 R1 escape only when ≥1 failed job belongs to the gated battery family (`test-scripts*`); a run red solely on jobs the path-gate cannot skip is reported but never an escape, and a jobs read that cannot be established is `pending`, never `ok`.

**Assembly.** Every code path that turns a push-run read into an escape verdict: `_pbg_w_esc` in `scripts/followthroughs/pr-battery-gate-saving-9323.sh` is the sole producer of `escape` row prefixes — the case-arm at :334-336 is the one chokepoint every escape flows through — and the parent's `escape)` aggregation at :555 is the only consumer. The jobs read is added inside that same case-arm (a sibling-site check would leave the chokepoint unguarded); the gated-family set is the same `test-scripts*` prefix the examine arm already derives at :281, not a second enumeration that can drift.

**Mutation matrix:**

| # | Mutation (fixture or edit) | Expected |
|---|---|---|
| 1 | Push run red; failed jobs = `test-scripts (shard 2)` only | escape row emitted; `escapes=1` (must-RED arm — the escape property must still fire) |
| 2 | Push run red; failed jobs = `lint-bot-statuses` + `tenant-integration` only | NOT an escape — the unrelated bucket row emitted; `escapes=0` (the defect this guard exists against) |
| 3 | Push run red; failed jobs = `lint-bot-statuses` AND `test-scripts (shard 1)` | escape — a second member after a compliant unrelated first does not wash out the gated failure |
| 4 | Push run red; `runs/<id>/jobs` read fails or returns empty | `pending`/`not-evaluable` row — the classifier's own dispatch cannot conclude "no escape" on no evidence (anti-vacuity row) |
| 5 | Harness row: fixture where `workflow_runs[0].id` is absent from the runs-list read | the probe reports `pending`/`fail`, never `ok` — a missing run-id silently degrading to `ok` is the vacuous-harness shape |
| 6 | Must-PASS (non-canonical): push run `success` | `ok` — unchanged from today (proves the guard does not reject everything) |

**Anchor.** The fixtures pin the job-name sets and run conclusions; weakening the property requires editing both `pr-battery-gate-saving-9323.sh` and its `.test.sh` in the same diff — no stored outside value is consulted, so the guard compares live fixture inputs to live code paths, and the suite registration (`test-all.sh:7094`) makes the check run on every full battery.

## Architecture Decision (ADR/C4)

### ADR

- **Amend ADR-276** (`knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`): new `## Amendment 2026-11-08 (S4 go/no-go third re-ruling, #9729)` recording the computed third verdict, the four criterion figures, the window bounds, and the non-activation paragraph — plus a new LAST `Go/no-go receipt:` line → `knowledge-base/project/specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/r3/go-no-go.md`. This is the established amendment pattern for this ADR (the 2026-10-16 and 2026-11-07 amendments), not a new ADR.
- **ADR-262:** no edit required under Arm A (R1's definition is unchanged — the probe's classification is corrected toward it, not the reverse). If the ruling picks Arm B the widening edit is R1's own prescribed remedy and needs no ADR edit; Arm C (revert) would need an ADR-262 status revisit and the ruling's rationale would carry that explicitly.

### C4 views

**No C4 impact**, established by reading all three model files (`model.c4`, `views.c4`, `spec.c4`) and enumerating this plan's external surface: (a) external human actors — none new (verdict comments reach the already-modeled `publicReader` publication surface at `model.c4:84-93` and are written through the existing sweeper/`founder -> github` filing edges); (b) external systems/vendors — none new (GitHub Actions reads happen inside the existing `github` system element `model.c4:423`; CI workflow internals are not modeled elements at any view depth); (c) containers/data-stores — none (receipts are committed repo files, not a new store); (d) actor↔surface access relationships — none change (the preactivation gate and sweeper read GitHub through already-modeled CI machinery; nothing activates, so no new CI→repo relationship forms). A future engineer reading the ADRs + C4 after this ships would not be misled: the architectural lever (ADR-276 S4) stays dark and locked, exactly as modeled.

### Sequencing

The ADR-276 amendment lands in THIS PR's diff (the re-ruling is only *true* once its receipt and comment exist — they are written first, then the amendment names them).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "check `gh run view 42483264409` and `gh run view 42483264452` for current status before planning" [brief] | Phase 0 step 1 (done at plan time: `success` / `in_progress`; re-checked at work time) | mapped |
| 2 | "the plan MUST prescribe a soleur:engineering:cto spawn for a binding ruling among {widen declaring array, revert the PR arm, fix the probe's escape classification}, then implement the ruling" [brief] | Phase 1 steps 1-2 | mapped |
| 3 | "update scripts/ci-pr-affected-replay.py's job-name allowlist for post-umbrella job names — ALREADY SHIPPED via 33f0b8ee83 and PR #12412's folded-job classification, verify and do not redo" [brief] | Verified at :219-222 in premise validation; AC11 | mapped |
| 4 | "re-run the R3 go/no-go ruling on a fresh 300-commit window 'once the queue-cancel rate settles'" [brief / #9729 SCHEDULE term 2] | Phase 2 steps 1-7 | mapped |
| 5 | "receipts go to the receipts dir named in the schedule comment (knowledge-base/project/specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/ — verify on disk)" [brief] | Phase 2 step 8 (dir verified on disk at plan time) | mapped |
| 6 | "the third ruling (GO / NO-GO / UNDECIDED) with committed receipts and a verdict comment posted on #9729" [brief] | Phase 2 steps 7-9, 12 | mapped |
| 7 | "Stage 4 stays NON-ACTIVATED throughout: CI_PR_AFFECTED unset, PR_AFFECTED_LOCKED intact in scripts/ci-pr-selection.sh, merge_group keeps the full battery" [brief] | AC8 + Phase 3 step 2 sweep | mapped |
| 8 | "Both items land in ONE PR on this branch" [brief] | whole plan; Split Assessment = single PR | mapped |
| 9 | "Execute per runbook knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md using scripts/ci-pr-affected-replay.py and scripts/ci-pr-affected-preactivation.sh" [brief] | Phase 2 steps 1-7, 11 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `pr-battery-gate-saving-9323.sh` classifier edit | "fix the escape classifier in scripts/followthroughs/pr-battery-gate-saving-9323.sh, which currently counts ANY push-run `failure` conclusion (including unrelated-job infra flakes) as an escape" | asked (one of three arms; conditional on ask #2's ruling) |
| `pr-battery-gate-saving-9323.test.sh` fixtures | "fix the escape classifier …" (a classifier fix without mutation coverage is the vacuous-guard class) | inferred — justification: every guard change carries its test per the repo's guard contract and the probe's own registered suite |
| `test-relevance-paths.sh` edit | "widen the declaring array (ADR-262 R1)" | asked (one of three arms; conditional) |
| ADR-276 amendment + receipt line | "a third ruling pass under the same rule of the record" (#9729 SCHEDULE, quoted in ask 4/6) — the rule of the record lives in the ADR's amendment chain | inferred — justification: the preactivation gate's `verdict=` reader resolves the LAST `Go/no-go receipt:` line, so an unamended ADR leaves the new receipt unreadable by the gate |
| Runbook §2 status append | "Execute per runbook …" + the runbook's own dated-append convention (its §2 carries a dated line per re-ruling) | inferred — justification: the runbook is the operational record of each re-attempt; skipping the append leaves it claiming the latest ruling is the second |
| `receipts/r3/` files | "receipts go to the receipts dir named in the schedule comment" | asked |
| decision-challenges.md / tasks.md | — | inferred — justification: the one-shot pipeline contract requires the `| Item | Class | Ruling |` persistence and the work-phase task breakdown |
| Phase 0 adopt-or-restart coordination | — | inferred — justification: `collision-precheck.sh` surfaced a live `s4-r3-20261108` collect; a second concurrent collect duplicates ~2.5 h of API reads and risks divergent windows |
| preactivation.out receipt | "using … scripts/ci-pr-affected-preactivation.sh" | asked |

### Split Assessment

- Subsystems touched: 2 — `scripts/`, `knowledge-base/` (no `.github/`, `apps/`, or `plugins/` file changes)
- Planned files: ~20 (5 edit + 15 create, of which 13 are generated receipts) | Estimated changed lines: ~250 hand-written (receipts excluded as generated artifacts)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — under all three
- Recommendation: single PR (also the explicit ask #8)

## Acceptance Criteria

- [ ] AC1: `decision-challenges.md` carries the Item-1 fork as a `## Decision Classes` row ruled `Ruled by CTO agent, <date>: <decision> - <rationale>` — the ruling names exactly one of {widen declaring array, revert the PR arm, fix the probe's escape classification}.
- [ ] AC2: The ruled arm is implemented and its diff matches the ruling (Arm A: `_pbg_w_esc` scopes escape to gated-family job failures; Arm B: `test-relevance-paths.sh` widened; Arm C: PR-9324 machinery reverted).
- [ ] AC3 (Arm A): `bash scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` exits 0 with new cases covering matrix rows 1-6.
- [ ] AC4: A corrected verdict comment is posted on #9323 quoting the rerun terminal states of runs 42483264409/42483264452, the classification disposition, and the probe's honest re-run output verbatim.
- [ ] AC5: `receipts/r3/` under the schedule-named receipts dir contains all 13 named files; `go-no-go.md` ends with `SOLEUR_PR_AFFECTED_VERDICT verdict=<GO|NO-GO|UNDECIDED> ruled=confirmed date=2026-11-08`.
- [ ] AC6: A verdict comment is posted on #9729 carrying `computed=<GO|NO-GO|UNDECIDED> reason=…`, the four-criterion table, and the receipts path.
- [ ] AC7: ADR-276 carries the `## Amendment 2026-11-08 (S4 go/no-go third re-ruling, #9729)` section and its LAST `Go/no-go receipt:` line resolves to the committed `receipts/r3/go-no-go.md` (the preactivation gate's reader finds it).
- [ ] AC8: Non-activation sweep green at PR-ready: `grep -n 'PR_AFFECTED_LOCKED=1' scripts/ci-pr-selection.sh` hits (verified :90 at plan time); `grep -n 'vars.CI_PR_AFFECTED' .github/workflows/ci.yml` unchanged at :399; `git diff --name-only origin/main...HEAD` contains no `scripts/required-checks.txt`, no `.github/workflows/*`, no ruleset JSON, no `scripts/ci-pr-selection.sh`, and no `apps/*/infra/*` path.
- [ ] AC9: One open PR on `feat-one-shot-9323-escape-r3-rerule` carries both items; its body says `Ref #9323` and `Ref #9729` and contains no `Closes`/`Fixes`/`Resolves` keyword for either.
- [ ] AC10: `ci-pr-affected-activation.md` §2 carries the dated 2026-11-08 third-ruling status line.
- [ ] AC11: The plan's term-1 verification is restated in the PR body: allowlist covers `rule-body-lint`, `adr-ordinals`, `grok-fidelity`, `harness-discovery`, `cla-check`, `cla-evidence` (verified `ci-pr-affected-replay.py:219-222`), no allowlist edit made.
- [ ] AC12: `preactivation.out` committed under `receipts/r3/` captures the gate's `SOLEUR_PR_AFFECTED_PREACTIVATION ready=…` line from an origin/main checkout.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Product/UX gate: NONE — no user-facing surface, no `components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx` in either Files list; the mechanical UI-surface override does not fire.

## Test Scenarios

- Given a merged PR whose merge-commit ci.yml push run failed only `lint-bot-statuses`/`tenant-integration`, when `_pbg_w_esc` classifies it, then the row is the unrelated bucket and `escapes` stays 0 (unit — `.test.sh` fixture; matrix row 2).
- Given a red push run whose failed jobs include a `test-scripts*` leg, then the row is `escape` and the verdict FAILs honestly (unit; matrix rows 1, 3).
- Given a red push run whose jobs read fails or is empty, then the row is `pending`/not-evaluable — never `ok` (unit; matrix rows 4, 5).
- Given a green push run, then `ok` — the must-PASS row (unit; matrix row 6).
- Given an aggregate output dir missing `ejections-window.json`, when `aggregate` runs, then it refuses rc 2 (integration — existing tool contract, re-verified by the receipts' presence check).
- Given the R3 verdict inputs, when `verdict --a … --b … --c … --d …` runs, then stdout carries `computed=` and the exit code is 0 regardless — the comment reads the printed verdict, not the exit code (integration — documented tool contract).
- Given HEAD on this branch, `grep -n 'PR_AFFECTED_LOCKED=1' scripts/ci-pr-selection.sh` prints the lock line and `git diff --name-only origin/main...HEAD` shows no activation-surface file (integration — non-activation sweep, AC8).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 issues) searched against every Files-to-Edit/Create path plus ADR-262/ADR-276: zero matches.

## Context

- Verbatim FAIL comment (2026-11-08T20:20:37Z, `deruelle`): `qualifying_runs=40 evidenced_runs=21 mean_runner_min=295.1 required_saving=20 baseline_runner_min=76 candidates_examined=48 pages=6` / `ESCAPE: PR 12390 was green but its merge-commit push run on 22608aa4cc63a78e81f3d64b9627410954da30d0 is failure` / `note: 3 qualifying PR(s) still open — excluded` / `FAIL: 1 escape(s); widen the declaring array (ADR-262 R1) or revert the PR arm`.
- R2 criterion-a anatomy (receipt, 2026-11-07): worst-case numerator 61 of 382 = 58 refused-run not-evaluable (25 unsettled suite legs from the window's 24 cancelled runs; 29 unclassified-job — the pre-umbrella names term 1 fixed; 5 failed-job-without-fail-line) + 2 unverified + 1 unsettled commit unit. The settled-cancel window (0 of last 60) directly attacks the 24-cancelled term; term 1's allowlist attacks the 29 unclassified-job term. The residual not-evaluable drivers are `failed-job-without-fail-line` and whatever this window's cancelled count lands at.
- Known residual recorded-not-built: #12428 (ejections index-drop under-count of the refused-merge_group population; per the 2026-11-08 CTO ruling no per-sha non-search read exists) — cite it in the R3 `go-no-go.md` limits, do not fix it here.
- The probe's next sweeper sweep may post another FAIL on the still-unfixed classifier before this PR merges — expected; AC4's comment explains it.
- **Sweeper close semantics (sharp-edge #11393 class).** `scripts/sweep-followthroughs.sh` closes the tracker issue on probe exit 0. If the Arm-A fix plus the rerun-green push run lets the probe compute PASS (saving bar met + no escapes), the sweeper CLOSES #9323 — the intended end-state of the soak, not a defect: the verdict comment must state plainly that the corrected classifier makes the PASS verdict reachable and that a close on PASS is warranted; a NOT YET (still accumulating qualifying runs/evidence) leaves the tracker open honestly. The Arm B/C ruling leaves this reachability question with the ruling text.

## Non-Goals

- No `CI_PR_AFFECTED` set, no `PR_AFFECTED_LOCKED` removal, no stage-2 reduced-run build, no required-checks/ruleset/infra change — activation stays operator-owned (budget-owner go-ahead naming the command + admin-side control decision).
- No fix for #12428 (recorded-not-built per CTO ruling).
- No probe retirement and no retire-vs-schedule call on #9729 (operator-owned per #10448).
- No re-do of schedule term 1 (already shipped).
- No 4th schedule term invented; no widening of the R3 rule of the record.

## Risks

- **Live duplicate collect** (`/var/tmp/s4-r3-20261108` + `s4-r3-replay` worktree processes): mitigated by Phase 0's adopt-or-restart gate; a stale adoption is caught by `aggregate`'s `--expect-commits 300` + ejections-population checks.
- **The ruling lands Arm B or C:** the plan branches explicitly; Arm B edits `test-relevance-paths.sh` (self-arming, expected); Arm C is a machinery revert with its own blast radius the CTO ruling will have weighed.
- **R3 window still carries cancelled runs** despite the settled 60-run trigger: the honest bound is reported — a third NO-GO is a legitimate computed output, and the comment says so.
- **API quota:** replay reads are gh-API-bound; the tool's own quota preflight floors the sweep (probe `need_min` :368-377; replay has its own accounting per runbook).
- **Comment race:** a sweeper sweep between now and merge can post a second false FAIL — disclosed in Context; AC4's comment addresses the mechanism, not just the instance.

## Enhancement Summary

Deepen pass (2026-11-08, `soleur:deepen-plan`; sequential-fallback — no subagent spawn in the planning subagent, disclosed; research/review seats were executed inline rather than spawned, `Reviewed-Coverage: sequential-fallback`).

### Gate results (all halt gates passed)

- **4.6 User-Brand Impact** — section present; threshold `none` + scope-out bullet. PASS.
- **4.7 Observability** — section present; `discoverability_test.command` (`bash scripts/followthroughs/pr-battery-gate-saving-9323.sh`) executed at plan time: prints `CANNOT ESTABLISH` rc 3 in <1 s; verb allowlisted, no `ssh`, literal `expected_output`. PASS.
- **4.8 PAT-shaped variable** — no PAT/TF-var/token literal introduced. NOT TRIGGERED.
- **4.9 UI wireframe** — no UI surface. NOT TRIGGERED.
- **4.10 Encryption Posture** — no new store/connection. NOT TRIGGERED.
- **4.11 Guard Contract** — `python3 scripts/lint-guard-contract.py <plan>` scanned 1 entry, exit 0; assembly is the `:334-336` case-arm chokepoint, not a member list; matrix rows 1-6 design-derived (both directions + anti-vacuity + must-PASS). PASS.
- **4.12 Scope Check** — exactly one unfenced section; 9 asks all `mapped`; every `inferred` row carries a justification. PASS.
- **4.13 Task Design** — no new autonomous-task surface. NOT TRIGGERED.
- **4.4/4.5/4.55 precedent-diff/network-outage/downtime** — classifier arm rides the existing `api()`/`_w_row` primitives (precedent-bound, not novel); no network-outage keywords; no offline-inducing operation. NOT TRIGGERED.

### Enrichments applied during the deepen pass

1. **CTO ruling executed inline** (no spawn available): the Item-1 technical fork is ruled — Arm A, fix the probe's escape classification — recorded `Ruled by CTO agent, 2026-11-08` in `decision-challenges.md`; `technical-ruling-gate.sh --branch` PASS (3 rows). The plan's Phase 1 was rewritten from "prescribe the spawn" to "implement the recorded ruling".
2. **Sharp-edges catalogue** (all 356 lines) applied as a verification pass: added per-arm disqualifying facts to the ruling brief (#7442 class), the sweeper close-on-exit-0 semantics note (#11393 class), merge-base three-dot form in AC8 (#8616 class), markdownlint clean, all prescribed commands executed once (#9303 class — discoverability probe verified live).
3. **Collision deconfliction** recorded: PR #12439 is this branch's own draft (self-hit); the live `/var/tmp/s4-r3-20261108` collect + `s4-r3-replay` worktree processes are handled by Phase 0's adopt-or-restart gate — never two concurrent collects.
4. **Precedent-diff note** (Phase 4.4): the Arm-A shape (`_w_row` bucket + `api()` deadline read + parent-owned aggregation) mirrors the existing `dropped`/`open`/`pending` arms added by #12360 — the new `unrelated` bucket is the same idiom, not a novel mechanism.

### New considerations discovered

- The named "escape" self-clears on the probe's next sweep (push run 42483264409 now `success` post-rerun) — the classifier fix is what prevents the NEXT false FAIL; both facts belong in the #9323 comment.
- The ADR-276 `Go/no-go receipt:` line currently resolves via the gate's `(receipt-archived)` arm; the R3 amendment writes a fresh last line to the stable `receipts/r3/` path.
- A PASS under the fixed classifier lets the sweeper close #9323 automatically — the intended end-state, called out so the verdict comment addresses it plainly.

## References

- Issues: #9323 (probe soak), #9729 (S4 parked), #10448 (decision the NO-GO left), #12360 (probe convergence defect), #12428 (ejections residual), #12089 (umbrella fold), #10862 (no-run corroboration)
- PRs: #12412 (merged ci-lever threads), #9324 (the gate machinery itself), #12329 (ratchet required-context flip)
- ADRs: ADR-262 (R1 escape semantics), ADR-276 (S4 + amendment chain), ADR-217 (deploy block on red push run), ADR-270 (merge queue)
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §§1, 3-6
- Prior receipts: `knowledge-base/project/specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/` (R2); `…/20261108-110953-feat-one-shot-10862-norun-investigation/receipts/rerun/` (criterion-a re-run precedent)
- Ruling-row precedent: `knowledge-base/project/specs/archive/20261108-160216-feat-one-shot-12360-ci-lever-threads/decision-challenges.md`
