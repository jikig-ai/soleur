---
title: "fix: reserve one week-cap slot for the compound-promote create arm"
type: fix
date: 2026-10-27
slug: fix-create-arm-reserve-week-cap-slot
branch: feat-one-shot-10550-create-arm-reserve-slot
issue: 10550
closes: none (Ref #10550 only; the issue stays open)
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix: reserve one week-cap slot for the compound-promote create arm

## Enhancement Summary

**Deepened on:** 2026-10-27
**Sections enhanced:** Research Reconciliation (new), Proposed Solution 4 (stale PR references), Acceptance Criteria, Risks
**Agents used:** plan-review panel (DHH, Kieran, code-simplicity; findings applied or recorded in `decision-challenges.md`); deepen gates 4.6-4.13 run mechanically; live `gh` verification of every cited PR/issue.

### Key improvements

1. Live check found the runbook's saturation example is stale: #11230 and #11231 are CLOSED; the cap is held today by the two live-fire drafts #11290 and #11291 (open, draft, operator-held). The runbook edits now replace the stale numbers, and the plan states the post-merge consequence.
2. The second-cluster fixture for test case 1 is specified exactly (skill target, disjoint evidence, distinct stub rationale), closing Kieran's blocking-if-skipped finding.
3. Added the in-flight-replay-at-deploy risk and the runbook-anchor (heading/phrase, not line number) citation rule.

### New considerations discovered

- Merging this PR does not by itself make the next fire reach the arm: with #11290 and #11291 both open the next manual `allow_create` run still ends `week-cap-reached` (P2, unchanged by design). The operator must dispose of at least one before the next live-fire. This is an operator-held act; this PR touches neither PR.

## Research Reconciliation - Spec vs. Codebase

| Spec / brief claim | Reality (verified live 2026-10-27) | Plan response |
|---|---|---|
| Runbook cites #11230 and #11231 as the open evidence PRs saturating the cap | `gh issue view`: both CLOSED. Open `self-healing/auto` PRs are #11290 and #11291 (draft) | Runbook (iii) and (v) drop the stale numbers; wording refers to "the live-fire drafts" generically so it does not rot again |
| Test title says "two open self-healing/auto PRs: #11230 and #11231 today" | Same staleness (`h.openPrs = 2` is a count, the numbers are decoration) | Case 3 keeps its assertions verbatim; only the parenthetical in the title is made number-free |
| Runbook line numbers ~238, ~279, ~284, ~294, ~312, ~370-374 | Confirmed by `grep -n` on this branch | Edits cite headings/phrases, not line numbers |
| `week-cap` token is parity-counted | Confirmed: `compound-promote-runbook-parity.test.ts` (TOKEN_FLOOR 104) and census mutation tests at `cron-compound-promote-outcome-census.test.ts` | Token and `fail("week-cap", "no-slot"` literal untouched |

Ref #10550 (the issue stays open; never `Closes`).

## Overview

The first live-fire of the gated create arm (2026-10-27, run `01M5YB28JD20JKKH4HG04CX2Z4`, a manual
`input:"patterns"`, `allow_create:true` run) ended with `SOLEUR_COMPOUND_PROMOTE_OUTCOME kind=create`,
`create_refusal_class=week-cap`, `create_detail=no-slot`. The edit loop in `cron-compound-promote` opened two draft
PRs first, spent both week-cap slots (`WEEK_CAP_DEFAULT = 2`), and the arm that runs after it had `capLeft = 2 - 2 = 0`.
With two qualifying edit clusters on a clean state the arm is structurally unreachable.

The CTO ruled design (a) on 2026-10-27 (recorded in `decision-challenges.md`, not re-litigated): on an `allow_create`
run, hold one slot back from the edit loop.

```ts
const editCap = allowCreate ? Math.max(weekCapResult.remaining - 1, 0) : weekCapResult.remaining;
```

`allowCreate` false makes `editCap === remaining`, so scheduled, manual-corpus and no-input runs stay byte-identical.

This change removes the structural cause of the observed `week-cap` refusal. It does NOT prove that a create PR
opens: the arm's effect stays UNMEASURED until a live-fire clears (the live-fire is an operator-held, separately
authorized production act; this PR fires no cron).

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed); no spec.md exists for this one-shot branch.

## Research Insights

### Premise Validation (Phase 0.6)

- #10550 is OPEN (`feat(harness): WikiSkill Phase 2`). The create arm merged in #11233 (`11c23a4e4f`); the cited code
  exists on `origin/main` (`git show origin/main:.../cron-compound-promote.ts | grep -c weekCapResult.remaining` = 4:
  the early return, the prompt, the slice, `capLeft`).
- Collision pre-check: the only open PR naming #10550 is #11297, this pipeline's own draft (`WIP:
  feat-one-shot-10550-create-arm-reserve-slot`, no files). Foreign `test-all.sh` processes belong to other
  worktrees and are unrelated. No duplicate work.
- Brief line anchors verified against the tree: test block `describe("the week cap (CTO G2)...` at line 421; runbook
  interim rule 2 at 238-239, reachability bullet at 278-280, precondition bullet at 283-285, class row at 294,
  detail row at 312, "Where the create outcome sits" at 370-374.
- ADR corpus check: ADR-092 (create-only amendment, line 318) states the arm "shares the week cap with the edit arm,
  edit loop first". The mechanism here extends that (still shared, still edit-first) and rejects nothing in its
  Alternatives; one clause is added for accuracy (see ADR section).
- Archived-spec editing convention: no rule freezes `knowledge-base/project/specs/archive/`; prior merged commits
  amended archived specs (`956558760e` closed an archived spec's post-merge boxes, `8a8df353e3` re-read a flip
  precondition). So the "G2 amended" row goes into the archived `decision-challenges.md` as an appended row AND the
  branch's own `decision-challenges.md` carries the ruling row (which `ship` renders).

### Repo facts that shaped the design (file anchors, re-derived on this branch)

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
  - `week-cap` step (`step.run("week-cap", ...)`): `remaining = WEEK_CAP_DEFAULT - total_count`, floored at 0.
  - `if (weekCapResult.remaining <= 0)` early return `week-cap-reached` (unchanged).
  - `anthropic-cluster` step: prompt line "Return up to ${weekCapResult.remaining} qualifying clusters" and the final
    `.slice(0, weekCapResult.remaining)`. Two further comment mentions ("occupies one of the `remaining` proposal
    slots"; the header comment "the slice(0, remaining) cap stays a post-parse TS ...").
  - `runCreateArm`: `const capLeft = weekCapResult.remaining - clustersOpened;` (unchanged arithmetic; the comment
    above it, "It runs AFTER the edit loop (it shares the week cap with whatever the loop opened)", is what gets updated).
  - Both `runCreateArm()` call sites: the no-clusters branch (`allowCreate && !clusterResult.truncated`) and after the
    edit loop. `editCap = 0` lands on the first.
- `apps/web-platform/server/compound-promote-create-arm.ts` line ~369: `if (!(a.capLeft > 0)) return fail("week-cap", "no-slot")`
  plus the comment above it ("the edit loop ran first and shares the cap"). The token stays (defensive backstop,
  counted by the parity test and the census mutation tests at `cron-compound-promote-outcome-census.test.ts` ~1224-1235).
- Test seam: `h.openPrs` drives the `is:pr is:open label:self-healing/auto` search `total_count`
  (`remaining = 2 - openPrs`); `PATTERNS_CREATE()`; `run()` returns `names`, `markers`, `last`; `createPrompts()`,
  `editCommits()`, `createCommits()`; `stubModel()` answers prompts containing `clustering agent`, `brand-new skill`,
  `RATIONALE-AGENTS`.
- Runbook parity suite: `apps/web-platform/test/server/compound-promote-runbook-parity.test.ts` (a REPO_WIDE suite,
  `test/repo-wide-suites.ts`) requires every code `create_detail` token, `no-slot` included, to remain a whole
  backticked token in the runbook's `create_detail` table, and vice versa. `TOKEN_FLOOR = 104`.
- Parity test `compound-promote-create-parity.test.ts` ~393 pins the ADR-092 prefix
  "Step A (`create-propose`), in order: the week cap (shared with the edit arm"; an appended clause after that prefix is safe.

### Institutional learnings applied

- `2026-10-26-a-caps-reachable-maximum-is-set-by-the-tightest-downstream-gate...`: state the DERIVED reachable
  maximum, not the component's own constant. Applied: the runbook states "an `allow_create` run opens at most
  (free slots - 1) edit PRs" and "with one free slot the edit loop is skipped", not "the cap is 2".
- ADR-092 Amendment 2026-10-20 / ruling C3 (documented slot starvation: the slice runs BEFORE quorum and ledger
  suppression). A smaller `editCap` makes that starvation sharper on `allow_create` runs (one edit slot); accepted and
  already tracked (#10977); the runbook line 254 wording is updated so it does not still say "at most 2".

### Property List and Cut List (Phase 0.6b)

Properties:

1. P1. On an `allow_create` run that starts with at least one free slot, the create arm is never refused `week-cap`.
2. P2. A run with no free slot (`remaining <= 0`) still ends `week-cap-reached`, before the arm.
3. P3. Runs without `allow_create` (scheduled, manual corpus, manual no-input, manual patterns with the flag off or
   non-boolean) are byte-identical to before: same steps, same prompts, same commits, same marker.
4. P4. No new marker field, refusal class or detail token (census unchanged).
5. P5. The operator can read, from the runbook alone, why a run ended `week-cap-reached` / `no-qualifying-clusters`
   with create fields / `create_refusal_class=week-cap`.

Cut List (mechanisms considered and removed before research):

- Create-before-edit reordering (b) -> would buy P1 but needs hash-collision handling and step reordering; already
  covered by the one-line reservation. CTO-rejected.
- A create-only run mode (c) -> new terminal status, census and runbook parity churn; CTO-rejected.
- A new marker field such as `edit_cap` -> P4 forbids; `clusters_opened`, `clusters_proposed` and the open-PR count
  already discriminate (see Observability).
- A new log line or Sentry event for the skipped cluster step -> buys no property the marker does not; omitted.

### Open Code-Review Overlap

None. (Queried open `code-review` issues for the four edited source/test/runbook paths; no body names any of them.)

## Problem Statement

Observed (2026-10-27): the edit loop ran first and consumed both slots, so the arm refused `week-cap` / `no-slot`
although the run began on a clean state with two free slots. Two qualifying edit clusters (the model returns up to
`remaining`) are the common case, so the dark-launched arm would refuse on nearly every clean fire.

## Proposed Solution

### 1. Handler: `cron-compound-promote.ts`

After the `remaining <= 0` early return (step `week-cap` and its return untouched):

```ts
// #10550: an allow_create run holds ONE free slot back from the edit loop so the create arm is reachable
// (live-fire 2026-10-27: two edit PRs took both slots and the arm refused week-cap/no-slot). Runs without
// allow_create keep editCap === remaining, so they are byte-identical to before. remaining >= 1 here.
const editCap = allowCreate ? Math.max(weekCapResult.remaining - 1, 0) : weekCapResult.remaining;
```

Inside the `anthropic-cluster` callback, FIRST statement (before the API-key read, `readAlwaysLoaded`, clone reads
and any model call):

```ts
if (editCap === 0) return { clusters: [] as ProposedCluster[], truncated: false };
```

Step id `"anthropic-cluster"` unchanged (Inngest memoization and replay depend on it). The return shape matches the
callback's other early returns, so the downstream `clusterResult.clusters.length === 0` branch runs
`runCreateArm()` (it is guarded by `allowCreate && !clusterResult.truncated`) and emits
`status: no-qualifying-clusters` with the create fields.

Replace `weekCapResult.remaining` with `editCap` in exactly two places: the prompt ("Return up to ${editCap}
qualifying clusters ...") and the post-parse `.slice(0, editCap)`. Update the comments that name `remaining`
(the C3 starvation comment including its "(at most two) slots" wording, and the header comment at the `slice(0, remaining)` mention). Sweep runbook wording that says the week's cap slots are consumed by a patterns run ("consumes the week's `week-cap` slots", "the two shared `self-healing/auto` week-cap slots") for accuracy.

`runCreateArm`: `const capLeft = weekCapResult.remaining - clustersOpened;` is UNCHANGED. Rewrite the comment above
the arm (the "runs AFTER the edit loop (it shares the week cap with whatever the loop opened)" sentence) to say the
loop is capped at `editCap`, so `clustersOpened <= editCap <= remaining - 1` and therefore `capLeft >= 1` on every
`allow_create` run that reaches the arm.

Invariant proof (also asserted by test 5): `allowCreate` and `remaining >= 1` imply `editCap = remaining - 1`;
the loop opens at most `editCap` clusters (slice, then refusals only reduce the count), so
`capLeft = remaining - clustersOpened >= 1`.

### 2. Create arm: `compound-promote-create-arm.ts` (comment only)

Update the comment above `if (!(a.capLeft > 0)) return fail("week-cap", "no-slot")`: "the edit loop is held to
`remaining - 1` on an allow_create run, so `capLeft >= 1` by construction; this refusal is a defensive backstop
(a caller that bypasses the handler, or a future change to the reservation) and is not expected in production".
No code change; the `fail("week-cap", "no-slot"` literal is byte-identical (census mutation tests replace that exact string).

### 3. Tests (write first, RED)

Rewrite the `describe("the week cap (CTO G2): ...")` block in
`apps/web-platform/test/server/inngest/cron-compound-promote-create-handler.test.ts` (lines ~421-463), and update the
header bullet "CTO G2   The edit loop runs first; ..." to the new semantics. Add a pass-through spy on
`runCreateProposeStep` (hoisted `h.capLefts: number[]`, reset in `beforeEach`) via
`vi.mock("@/server/compound-promote-create-arm", async (importOriginal) => ({ ...orig, runCreateProposeStep: (a) => { h.capLefts.push(a.capLeft); return orig.runCreateProposeStep(a); } }))`
so `capLeft` is observed without altering behaviour.

See Test Scenarios for the five cases. The existing "REAL saturated cap" case (openPrs=2 -> week-cap-reached) is kept
verbatim as case (3). The old "ONE slot left and the edit loop spending it -> class=week-cap" case is replaced
(it pins the old behaviour). "The edit loop runs first" case is kept (remaining 2, editCap 1, one cluster: still
apply-and-pr before create-propose).

### 4. Runbook: `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`

Exact edits (texts from the brief):

- (i) class table `week-cap` row ("How to read it" and "Meaning" columns) -> the brief's text.
- (ii) reachability bullet (~279): replace "The edit loop runs first; the arm then uses what is left of the week cap"
  with the brief's sentence; keep the parenthetical "(it counts all open `self-healing/auto` PRs, not a calendar week)".
- (iii) precondition bullet (~283): "at most one open self-healing/auto PR (none preferred, so the create draft is
  reviewed alone)"; the stale evidence-PR clause naming #11230/#11231 (both now CLOSED; the open drafts are #11290/#11291) is rewritten generically ('the live-fire drafts') (with two open the run ends
  `week-cap-reached` before the arm; with one open the edit loop is skipped and the arm may run).
- (iv) INTERIM OPERATING RULE item 2 (~238): split. A patterns run WITHOUT `allow_create` keeps the rule (no open
  `self-healing/auto` PR). With `allow_create:true`, at most one may be open (with one open the edit loop is
  skipped; two open ends `week-cap-reached`).
- (v) "Where the create outcome sits" (~370-374): drop the sentence that a run whose edit loop used the last slot ends
  `create_refusal_class: "week-cap"`; keep the saturated-cap sentence (`week-cap-reached`, never reaches the arm).
  Mark the 2026-10-27 live-fire as the historical origin in the class-table row only (the brief's text).
- Required for accuracy (not in the brief, same mechanism; cite by heading/phrase, not line number: the `ledger_suppressed` row of the patterns marker table, the sentence starting "Slot starvation (accepted)"): line 254 ("the patterns arm slices the model's clusters to the
  week-cap `remaining` (at most 2)") -> "to the edit cap (the week-cap `remaining`, minus one on an `allow_create`
  run)"; `create_detail` table `week-cap` row keeps the backticked `no-slot` token (parity suite) but its gloss
  becomes "(no slot left for the arm; not expected since the slot reservation)". `betterstack-log-query.md` needs no
  change (it names `week-cap` only as a class list member and the saturated-cap `week-cap-reached` path).

### 5. ADR-092 clause (accuracy, no new decision)

ADR-092 line 318 "(shared with the edit arm, edit loop first)" -> append "; on an `allow_create` run the edit loop is
held to the free slots minus one, so one slot is always left for the arm (2026-10-27)". Keep the parity-pinned
prefix intact. No new ADR.

### 6. Decision records

- Branch `knowledge-base/project/specs/feat-one-shot-10550-create-arm-reserve-slot/decision-challenges.md`: the
  `technical` row with the CTO ruling (created at plan time).
- Archived `knowledge-base/project/specs/archive/20261026-235818-feat-one-shot-10550-wikiskill-phase-2-new-skill-creation/decision-challenges.md`:
  an appended `G2 amended 2026-10-27` row (created at plan time; the original G2 row is not rewritten, the
  amendment supersedes only its "shares the existing cap (`remaining - editPrsOpenedThisRun > 0`)" sentence).

## Technical Considerations

- **Replay determinism.** `editCap` derives only from the memoized `week-cap` step output and the event-derived
  `allowCreate`; the `anthropic-cluster` memoized result is stable across replays. The early return is inside the
  step so a replay never re-evaluates it differently.
- **`remaining === 1` with `allow_create`.** `editCap = 0`: no clustering model call and no API-key read; the run
  still performs `ledger-read` and the pattern/corpus reads (the arm needs `patternRows` and `ledgerEntries`), then the
  no-clusters branch runs the arm and emits `no-qualifying-clusters`, `clusters_proposed: 0`, `clusters_opened: 0` and
  the create fields. The heartbeat step `sentry-heartbeat-ok-no-clusters` is unchanged.
- **`anthropic-truncated`** cannot occur on the `editCap = 0` path (no call), so the arm is not skipped there.
- **Byte-identity for non-`allow_create` runs.** Prompt text, slice length, steps and marker are unchanged because
  `editCap === weekCapResult.remaining` when `allowCreate` is false; the existing Guard 3 fingerprint tests stay
  green unmodified and are the proof (do not touch them).
- **Accepted trade-off.** An `allow_create` run with two free slots opens at most one edit PR; the other slot is the
  arm's. If the arm then declines (`no_action`) or refuses for another reason, that slot goes unused this run (the
  edit loop is not retried). Accepted by the CTO ruling.
- **Not a flag.** No runtime flag, no new event field (`allow_create` stays the single parse site).
- **Sensitive path.** `apps/web-platform/server/**` is a sensitive path (preflight Check 6/10); the User-Brand Impact
  section carries the scope-out bullet and Observability carries a runnable `discoverability_test`.

## Alternative Approaches Considered

| Option | Verdict |
|---|---|
| (a) Reserve one slot for the arm (`editCap`) | Chosen (CTO, 2026-10-27) |
| (b) Run the create arm before the edit loop | Rejected: hash-collision handling between the two arms and reordering of memoized steps (replay risk) |
| (c) A create-only mode | Rejected: a new terminal status, census and runbook parity churn |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The cron is an operator-triggered maintenance
loop that opens draft PRs only; the worst regression is one fewer or one more draft PR per manual `allow_create` run,
or the arm still refusing `week-cap`, both visible in the marker.

**If this leaks, the user's data is exposed via:** no new vector. The change is integer arithmetic on an existing
cap; it adds no input, output, credential handling, network edge or model-visible text beyond the number N in the
existing "up to N clusters" sentence.

**Brand-survival threshold:** none

- threshold: none, reason: the diff touches `apps/web-platform/server/**` only to change an integer cap on draft-PR
  opening (it makes the edit loop open fewer PRs on a manual flag-gated run); no gate, screen, auth path or data flow
  is added, removed or weakened.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_COMPOUND_PROMOTE_OUTCOME marker row per run (Better Stack Logs, pino) carrying status, clusters_proposed, clusters_opened, create_requested and, when the arm ran, create_arm / create_outcome / create_refusal_class; Sentry cron monitor heartbeat for cron-compound-promote"
  cadence: "weekly scheduled run (unchanged) plus every manual fire"
  alert_target: "existing cron-compound-promote Sentry monitor and the existing zero-output-weeks alert; a create refusal routes to a Sentry issue tagged class"
  configured_in: "apps/web-platform/server/inngest/functions/cron-compound-promote.ts and apps/web-platform/server/compound-promote-marker.ts (unchanged by this PR)"
error_reporting:
  destination: "Sentry (feature cron-compound-promote, op create-refused, tag class) via reportSilentFallback, unchanged"
  fail_loud: "a defensive week-cap backstop hit (class=week-cap, detail=no-slot) still writes create_refusal_class to the marker and mirrors to Sentry; the runbook now classes it a defect"
failure_modes:
  - mode: "reservation regressed or bypassed: the arm refuses week-cap on a run that started with a free slot"
    detection: "marker create_refusal_class=week-cap with create_detail=no-slot and status not week-cap-reached; compared with clusters_opened and the open self-healing/auto PR count (runbook class row); unit invariant test 5 pins it pre-merge"
    alert_route: "Sentry issue op create-refused tag class=week-cap (layer 2: pino -> Sentry mirror); Better Stack marker query"
  - mode: "edit loop skipped with one free slot and the operator misreads no-qualifying-clusters as 'the model found nothing'"
    detection: "marker status=no-qualifying-clusters with clusters_proposed=0 and create_arm=ran on a run that started with exactly one open self-healing/auto PR; runbook reachability bullet states it"
    alert_route: "Better Stack marker query in the runbook"
  - mode: "two open self-healing/auto PRs still saturate the cap"
    detection: "status=week-cap-reached with create_requested=true and no create_arm (unchanged)"
    alert_route: "Better Stack marker query; runbook interim rule 2"
  - mode: "scheduled or corpus run changed by this PR"
    detection: "Guard 3 byte-identity tests (steps, prompts, commits, marker) in CI before merge; after deploy no marker row gains a field"
    alert_route: "CI red before merge"
logs:
  where: "Better Stack Logs source for the web-platform (pino marker); Sentry for refusals"
  retention: "Better Stack source retention as configured; Sentry per project retention"
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 30d --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit 5
  expected_output: SOLEUR_COMPOUND_PROMOTE_OUTCOME
  credentials_required: "Better Stack Logs read token (Doppler) - the marker exists only in production logs, so no unauthenticated local probe verifies the same property"
```

Layer citation: markers and refusals ride layer 2 (pino -> Sentry breadcrumb/captureException mirror) and layer 1
(Inngest sentry-correlation middleware tags the run). The cron worker is a blind surface; the in-surface probe is
the marker itself, whose existing fields (`status`, `clusters_proposed`, `clusters_opened`, `create_arm`,
`create_outcome`, `create_refusal_class`, `create_detail`) discriminate every competing cause in one event; no
field is added (P4).

## Architecture Decision (ADR/C4)

No new architectural decision is detected: the change is cap arithmetic inside an existing cron function. The test
"would an engineer reading only the ADRs be misled?" fires for exactly one clause, so:

### ADR

Amend ADR-092 line 318 (create-arm Step A gate order) by the one clause in Proposed Solution 5. No new ADR, no new
ordinal.

### C4 views

No C4 impact. Checked: no new external human actor or external system/vendor, no container or data store touched, no
actor-to-surface access relationship changed; the only C4 mention of this function is the `api -> github` edge
(`model.c4` ~741, read-only search for the ledger), which this change does not alter. Run
`bash plugins/soleur/test/c4-count-parity.test.sh` once at work time as the cardinality backstop.

## Domain Review

**Domains relevant:** engineering (CTO ruling already recorded; not re-litigated)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** design (a) ruled 2026-10-27; (b) and (c) rejected. No product, legal, marketing, finance, sales,
operations or support implications: no user-facing surface, no data processing change (no GDPR gate trigger: no
schema, auth, API route or new processing; the model prompt gains only a smaller integer), no infrastructure.

## Implementation Phases

TDD order per `cq-write-failing-tests-before`.

### Phase 1 - Failing tests (RED)

1. Add the `runCreateProposeStep` pass-through spy and `h.capLefts`.
2. Rewrite the week-cap `describe` (cases 1-5 below). Run the file against the UNCHANGED handler and record the
   failing assertions (case 1 prompt "up to 1", case 2 no cluster call, case 5 capLeft >= 1 must fail for the right
   reason; cases 3 and 4 pass pre-fix and are the regression pins).
3. Commit the RED state only if the repo's commit hooks allow; otherwise keep tests and code in one commit and
   record the RED run output in the PR body.

### Phase 2 - Handler and arm comment (GREEN)

Apply Proposed Solution 1 and 2. Re-run the handler test file, then the sibling suites that load the handler.

### Phase 3 - Runbook, ADR clause, decision records

Apply Proposed Solutions 4, 5 and 6 (the two `decision-challenges.md` writes already exist from plan time; verify).

### Phase 4 - Verification

Run (from `apps/web-platform`): the create-handler file, the patterns-handler file, the outcome-census file,
`compound-promote-create-arm.test.ts`, `compound-promote-create-parity.test.ts`; then the runbook parity suite
(`compound-promote-runbook-parity.test.ts`, repo-wide suite) and `tsc --noEmit` for the changed files; markdownlint
on the touched markdown. The repo-wide suite runner is the one named in `test/repo-wide-suites.ts`.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
- `apps/web-platform/server/compound-promote-create-arm.ts` (comment only)
- `apps/web-platform/test/server/inngest/cron-compound-promote-create-handler.test.ts`
- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`
- `knowledge-base/engineering/architecture/decisions/ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md` (one clause)
- `knowledge-base/project/specs/archive/20261026-235818-feat-one-shot-10550-wikiskill-phase-2-new-skill-creation/decision-challenges.md` (appended row)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10550-create-arm-reserve-slot/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-10550-create-arm-reserve-slot/tasks.md`

## Test Scenarios

All in `cron-compound-promote-create-handler.test.ts`, `describe("the week cap (CTO G2): one slot is reserved for the create arm")`.

| # | Setup (`h.openPrs`, event) | Expected |
|---|---|---|
| 1 | `0` (remaining 2), `PATTERNS_CREATE()`, model returns TWO clusters | cluster prompt contains `Return up to 1 qualifying clusters`; marker `clusters_proposed === 1`; at most 1 `apply-and-pr-*` step and 1 edit commit; `h.capLefts` equals `[1]`; `create_refusal_class` is not `week-cap` (arm reaches a verdict, `create_outcome: "opened"` with the default stub). The second cluster MUST be drafted as: a SKILL target `plugins/soleur/skills/<fixture skill>/SKILL.md` (a second `AGENTS.rules.md` target is refused `edit-target-duplicate` and would not open a PR), evidence `Ls(8,5)` (disjoint from the create pattern `l1-5` and `zz-page-three` `l6-12`), and a rationale token distinct from `RATIONALE-AGENTS` with a matching new branch in `stubModel` whose edit anchors on the fixture SKILL.md `# <name>` line; otherwise the draft prompt throws `unstubbed prompt` and RED is for the wrong reason. Verify on the unfixed handler that it opens a second PR |
| 2 | `1` (remaining 1), `PATTERNS_CREATE()` | no `clustering agent` model call (`h.post` has none for that prompt); the `anthropic-cluster` step id is still in `names`; `result.status === "no-qualifying-clusters"`; marker has `clusters_proposed: 0`, `clusters_opened: 0`, `create_arm: "ran"`, `kind: "create"`, `create_requested: true`; `h.capLefts` equals `[1]`; zero edit commits |
| 3 | `2` (remaining 0), `PATTERNS_CREATE()` | UNCHANGED: `week-cap-reached`, no `create-propose`, no create prompt, marker `create_requested: true`, no `create_arm` (the existing case kept verbatim) |
| 4 | `0`, `MANUAL({ input: "patterns" })` (no `allow_create`), model returns THREE clusters | prompt contains `up to 2 qualifying clusters`; marker `clusters_proposed === 2` (slice 2); no `create-*` step. Plus `allow_create: false` explicit variant |
| 5 | invariant over `openPrs` in `[0, 1]` (remaining 2, 1) with `PATTERNS_CREATE()` and the model returning the maximum clusters | `create_refusal_class !== "week-cap"`, and every captured `capLeft >= 1` |

Kept from the old block: "the edit loop runs first: apply-and-pr precedes create-propose" (remaining 2, one cluster);
"with the edit arm finding nothing the arm still runs, with the whole cap left" is amended to
"with the edit arm finding nothing the arm still runs with `capLeft` 2". Unchanged and must stay green with no edit:
every Guard 3 fingerprint test, G5e key-set test, the single-parse-site test, the census mutation tests
(`fail("week-cap", "no-slot"` string intact) and the runbook parity suite.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "after the remaining<=0 early return add editCap = allowCreate ? Math.max(remaining - 1, 0) : remaining" | Proposed Solution 1 | mapped |
| 2 | "Use editCap instead of weekCapResult.remaining in the clustering prompt ... and in the post-parse .slice(0, ...)" | Proposed Solution 1 | mapped |
| 3 | "When editCap is 0 the anthropic-cluster step returns {clusters: [], truncated: false} at the top of its callback before any model call; keep the step id unchanged" | Proposed Solution 1 | mapped |
| 4 | "capLeft = remaining - clustersOpened in runCreateArm is unchanged. Update the comment near the capLeft computation." | Proposed Solution 1 | mapped |
| 5 | "compound-promote-create-arm.ts: comment-only update near the week-cap refusal." | Proposed Solution 2 | mapped |
| 6 | "Keep the week-cap / no-slot token in code as a defensive backstop ... No new marker fields, classes or detail tokens" | Proposed Solution 2, P4 | mapped |
| 7 | "Scheduled, corpus and no-input runs must stay byte-identical" | Test Scenarios (kept Guard 3 tests), Technical Considerations | mapped |
| 8 | "rewrite the \"week cap (CTO G2)\" block ... Write failing tests first." | Phase 1, Test Scenarios 1-5 | mapped |
| 9 | "Runbook ... (i) class table ... (ii) reachability bullet ... (iii) precondition bullet ... (iv) interim rule 2 ... (v) lines ~372-374 ... Run the runbook parity suite." | Proposed Solution 4, Phase 4 | mapped |
| 10 | "Add a dated \"G2 amended 2026-10-27\" row to decision-challenges.md in the archived spec dir (or ... this branch's own ...)" | Proposed Solution 6 | mapped |
| 11 | "PR body constraints: say \"Ref #10550\", never \"Closes\" ... Do NOT claim the fix \"will open a PR\"" | Overview, Acceptance Criteria | mapped |
| 12 | "Deliverable: merged PR, deploy verified (deploy-arm.sh find --wait, then served), then soleur:postmerge" | Acceptance Criteria (Post-merge) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Handler `editCap` change | "add editCap = allowCreate ? Math.max(remaining - 1, 0) : remaining" | asked |
| Arm comment-only edit | "comment-only update near the week-cap refusal" | asked |
| Five test cases | "(1) remaining=2 + allow_create ... (5) invariant" | asked |
| Runbook edits (i)-(v) | "Runbook ... (i) ... (v)" | asked |
| Archived/branch G2 amendment row | "Add a dated \"G2 amended 2026-10-27\" row" | asked |
| Branch ruling row | "record it as a `technical` row" | asked |
| Runbook line 254 and `create_detail` gloss touch-up | — | inferred — justification: same mechanism makes "at most 2" and "the edit loop used the last slot" wrong; the runbook parity suite and the stated runbook-accuracy goal require them consistent |
| ADR-092 one-clause amendment | — | inferred — justification: ADR-092 states the arm shares the cap "edit loop first"; without the clause the recorded architecture understates the reservation (`wg-architecture-decision-is-a-plan-deliverable`); the parity-pinned prefix is preserved |

### Split Assessment

- Subsystems touched: 3 (`apps/web-platform/server`, `apps/web-platform/test`, `knowledge-base`) | threshold 4
- Planned files: 8 | Estimated changed lines: ~220 (code ~10, tests ~110, docs ~100)
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `cron-compound-promote.ts` defines `editCap = allowCreate ? Math.max(weekCapResult.remaining - 1, 0) : weekCapResult.remaining` after the `remaining <= 0` return; `grep -c "weekCapResult.remaining"` shows only the early-return check, the `editCap` definition and the `capLeft` line (the prompt and slice use `editCap`).
- [ ] The `anthropic-cluster` callback's first statement returns `{ clusters: [], truncated: false }` when `editCap === 0`; the step id string is unchanged.
- [ ] The five scenarios pass; scenarios 1, 2 and 5 were observed RED against the unfixed handler for the stated reason (record in the PR body).
- [ ] All Guard 3 byte-identity tests, G5e, census tests and `compound-promote-create-arm.test.ts` pass unmodified.
- [ ] `fail("week-cap", "no-slot"` is still present in `compound-promote-create-arm.ts`; `git diff` of that file shows comment lines only.
- [ ] Runbook edits (i)-(v) applied (no remaining literal `#11230`/`#11231` in the runbook: `grep -c '#1123[01]' knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` prints 0), `no-slot` still a backticked token in the `create_detail` table, and `compound-promote-runbook-parity.test.ts` passes.
- [ ] No new key in `CREATE_ONLY_KEYS`, no new class in `CREATE_REFUSAL_CLASSES`, `TOKEN_FLOOR` unchanged.
- [ ] Branch `decision-challenges.md` carries the `technical` ruling row; the archived `decision-challenges.md` carries the appended `G2 amended 2026-10-27` row.
- [ ] PR body says "Ref #10550" (never `Closes`), states the change removes the structural cause of the observed `week-cap` refusal, and does NOT say the fix "will open a PR" (the arm's effect is unmeasured until a live-fire clears).
- [ ] No other PR or issue is touched: the operator-held `self-healing/auto` draft PRs, the closed follow-through probe, #10551, #8293, #8443, #11183, #10676 and #11228 are left alone.
- [ ] Every red check on the PR is treated as a finding until its first log line is read.

### Post-merge

- [ ] `deploy-arm.sh find --wait` completes, then the served build sha equals the merge sha; then `soleur:postmerge` prints "postmerge verification complete!".
- [ ] No cron is fired by this work (the live-fire stays an operator-held, separately authorized act).

## Risks

- **Slot starvation sharper on `allow_create` runs.** One edit slot is subject to the C3 pre-quorum slice and ledger suppression; a run can end `no-qualifying-clusters` with `ledger_suppressed >= 1` and still run the arm. Accepted (#10977).
- **Unused slot.** If the arm declines or refuses for another class, the reserved slot is unused this run. Accepted by the ruling; the operator re-fires.
- **Runbook/ADR drift.** Mitigated by the runbook parity suite and the ADR parity prefix test; the extra edits keep both green.
- **Effect unmeasured.** Removing the structural cause does not prove a create PR opens; the other 12 gate classes remain untested in production until a live-fire clears. State this in the PR body.
- **In-flight run at deploy.** A manual `allow_create` run whose `anthropic-cluster` result was memoized under the old slice and that replays on the new code could open two edit PRs and hit the `week-cap` backstop (`capLeft` 0). Manual, flag-gated runs only; the backstop refuses safely and the marker shows it. Accepted.
- **Next fire still blocked until the operator acts.** #11290 and #11291 are both open today, so the next manual `allow_create` run ends `week-cap-reached` (P2). This PR must not touch them; the PR body says so.
- **Collision.** #11297 is this pipeline's own draft; no foreign PR touches these files.
