---
title: "fix(compound-promote): enforce the 5-source quorum on the server"
date: 2026-10-20
slug: compound-promote-server-quorum
branch: feat-one-shot-compound-promote-server-quorum
pr: 10673
refs: [10552, 8443]
type: fix
lane: cross-domain
priority: P2
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

> Spec lacks valid `lane:` (no `spec.md` exists for this one-shot branch) - defaulted to
> `cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-20. **Panel:** code-simplicity and architecture seats (plan review; the Rails
reviewers were not spawned because nothing here is Rails), then observability-coverage, spec-flow, test-design
and security seats (deepen). Deepen gates 4.6 (user-brand impact with the sensitive-path scope-out line), 4.7
(observability), 4.8 (no PAT shapes), 4.11 (`lint-guard-contract.py`: 2 entries) and 4.12 (one unfenced Scope
Check, no BLOCKED marker) were run mechanically and pass; 4.9, 4.10 and 4.55 do not fire (no UI file, no store,
no downtime-inducing operation).

### What the panel changed

1. **Proof apparatus trimmed to what proves the property.** Guard 1 matrix cut from 13 to 8 rows and Guard 2
   from 5 to 3; rows already killed by existing guards (Guard 3b, the marker field-set pin, H3, C1 emit-once)
   are named, not re-executed. Handler rows H6 and H9 merged; P-4d, Q6 and two ratchet re-runs dropped.
2. **A claim in the plan was overstated.** "No git read for a refused cluster" is true only inside
   `draftAdditiveEdit`; the draft callback still runs the API-key check and `readAlwaysLoaded` first. The AC,
   Approach and ADR text now say so.
3. **Fixture blast radius completed.** Draft-edit tests T10/T11/T12, T10b and T16 share the 2-source fixture; the
   handler `source_learnings: undefined` row silently flips reason; multi-cluster fixtures need different
   source sets because the cluster hash is over the sorted sources only (new row H8 for identical and empty
   lists).
4. **RED discipline.** Phase 0 now separates RED rows from GREEN-by-design pins; H2 uses two different
   targets so a same-target duplicate cannot shadow the quorum check; the replay row filters the Sentry mock
   by op and asserts exactly one call after each pass.
5. **Diagnostic gap closed.** A second bare integer, `proposed_count` (raw list length before normalisation),
   joins `source_count` in the Sentry `extra`, so one event separates "the model proposed too few" from
   "normalisation dropped hallucinated paths"; still no marker field.
6. **Probe suite mechanics.** M-14 and M-15 are `mut_row` predicate arms with their own scenario helper and
   anchors, not exit-code sandboxes; the Guard 1d recipe is spelled out (AST assertions, permanent in-file
   mutation rows, the 8-space closer sharp edge).
7. **Failure-mode layer citations** added for modes 2 and 3; ADR text gains the relatedness limit, the
   headroom-divisor consequence and the pre-read ordering.

### New considerations (deferred, tracked in `decision-challenges.md`)

- Symlinked `.md` files in the learnings corpus walker (pre-existing; security seat): deferred for ship to file.
- Dedupe by content hash, and a headroom divisor that skips refused proposals: not adopted, reasons recorded.

## Overview

The weekly `cron-compound-promote` Inngest function asks the model in phase 1 for clusters of "at least 5"
related learnings. That number lives only in the prompt text (`cron-compound-promote.ts`, the
`anthropic-cluster` step) and as the literal `/5` in the draft PR trailer `Threshold-Hit: N/5`. The
server never checks it. PR #10553 (issue 10552, merged 2026-10-19) made `source_learnings` honest -
non-strings dropped, duplicates collapsed, only keys that exist in the corpus kept - so the length of
that normalised list is the true count and is already what the trailer reports. A model that returns a
two-learning cluster today gets a draft PR whose own trailer reads `Threshold-Hit: 2/5`.

This plan closes the deferral recorded in the archived decision record of #10552 ("Server-side quorum
of 5 source learnings: unchanged (pre-existing)"):

- one named constant, `PROMOTION_QUORUM = 5`, replaces the three places the number is spelled;
- a cluster whose distinct, corpus-resolved source count is below it is refused `quorum-not-met`
  inside `draftAdditiveEdit`, before any git read and before the phase-2 model call;
- the refusal rides the existing path (`DraftOutcome` -> `record()` -> marker `refusals[]`, Sentry via
  `reportSilentFallback(null, { message, tags })`), and the outcome marker's field set does not change;
- everything that enumerates refusal reasons moves in the same PR (sweep below), because the previous
  PR lost five CI cycles to exactly that.

All technical forks were ruled by the CTO agent in one batched spawn; no operator question is open
(`## Technical Rulings`).

## Premise Validation (Phase 0.6)

- **#10552** open (follow-through tracker, label `follow-through`); this plan neither edits nor closes
  it. **#8443** is not touched. **PR #10673** is the draft PR for this branch (open, draft).
- **Cited symbols on the worktree HEAD (= `origin/main` + the init commit):** `draftAdditiveEdit`,
  `EditRefusal`, `EDIT_REFUSAL_REASONS`, `record`, `DraftOutcome`, `TARGET_ALLOW_RE`,
  `corpusSummaries`, the `Threshold-Hit` template (line ~2049) and the phase-1 prompt (line ~1633) all
  exist as described. `compound-promote-marker.ts` has `reason: string` (free) and the field-set pin
  lives in `cron-compound-promote-outcome-marker.test.ts`.
- **Brief premise "the closed-vocabulary allowlist and its tests (cron-compound-promote-allowlist.test.ts)"**
  - partly stale. That file tests `checkDiffPaths` (the git-derived PATH allowlist); it enumerates no
  handler refusal reasons. A quorum refusal returns before `checkDiffPaths` can run, so the file needs no
  edit (reviewed: its only reason literals are the `diff-*` verdicts and one `corpus-shrink-refused`
  source-window row). The vocabulary members actually live in `EDIT_REFUSAL_REASONS`, the probe's
  `GRADE_JQ` sets, and two runbook tables - all in the sweep.
- **Brief premise "the length of the normalised list is what the draft PR reports"** - true, and the
  fixtures show a second consequence the brief did not name: the existing handler tests all use
  two-source clusters (`[L(1), L(2)]`) and one asserts `Threshold-Hit: 2/5`. They are valid today and
  become `quorum-not-met` the moment the check lands (see `## Fixture blast radius`).
- **ADR corpus (mechanism vs rejected alternatives):** ADR-092 is the loop's decision record and the CTO
  confirmed an Amendment (not a new ADR). Grepped `decisions/` for `quorum` and `promotion threshold`:
  no ADR rejects a server-side count gate. ADR-211 (a denylist over a model-written string is the
  rejected shape) is not engaged - this is a count over a server-normalised list, not a filter on model
  text.
- **Own capability claim checked, not assumed:** "no workflow invokes `scripts/compound-promote.sh`"
  - `rg compound-promote.sh .github lefthook.yml` returns one hit, `lefthook.yml:149`, a lint-trigger
  glob. No workflow runs it, so the CTO's condition for leaving it alone (F8) holds.
- **`Threshold-Hit` consumers:** `rg Threshold-Hit` outside `knowledge-base/project/{learnings,plans,specs}`
  and archives returns exactly three files - the source, the handler test, and the operator runbook.
  Nothing parses `/5`.

## Property List and Cut List (Phase 0.6b)

**Properties the change must buy**

1. A cluster with fewer than `PROMOTION_QUORUM` distinct corpus-resolved sources never reaches the
   phase-2 model call, never opens a draft PR, and is named in the marker as `quorum-not-met`.
2. The number appears once as code; the prompt, the check and the trailer cannot drift from each other.
3. The refusal is attributable from one marker row plus one Sentry message event, with no SSH and no new
   marker field.
4. Replay safety is unchanged: no accumulator is mutated inside a step callback, and the Sentry event
   fires once per step, not once per replay.
5. Every artifact that enumerates refusal reasons agrees about the new one, and the follow-through probe
   never reads it as proof (class N).

**Cut list** (mechanism -> property -> what already covers it)

- Handler-body predicate plus a new memoized step (option B) -> property 1 -> the existing draft-edit
  step already is the memoized unit; a second `Promise<DraftOutcome>` opener would break the Guard 3b
  uniqueness check (CTO F3).
- A dedicated Sentry op `quorum-refused` -> property 3 -> op `draft-edit-refused` already carries
  `reason`/`cause` tags and the dashboards filter on it (CTO F5).
- A new outcome-marker field for the observed count -> property 3 -> `extra.source_count` on the Sentry
  event; the marker field set is pinned and stays unchanged (brief, CTO F5).
- `promotion-config.yml` as the home of the quorum -> property 2 -> a config-only PR could weaken what
  may be promoted into always-loaded rules (CTO F2).
- Moving normalisation ahead of the phase-1 slice to stop slot crowding -> none of the five -> replay
  risk or hidden refusals; documented instead (CTO F6).
- A new test file -> none -> every suite below is an existing file (no registration ratchet moves).
- Editing `scripts/compound-promote.sh` -> none -> pre-Inngest path, not a server enforcement surface
  (CTO F8).

## Technical Rulings

All nine forks went to `soleur:engineering:cto` in one spawn (told not to use AskUserQuestion). Full rows,
machine-gated, are in `knowledge-base/project/specs/feat-one-shot-compound-promote-server-quorum/decision-challenges.md`.

- **F1 name** - Ruled by CTO agent, 2026-10-20: `quorum-not-met`, cause `below-quorum`; not `edit-`
  prefixed (Guard 1b pins that prefix to a vocabulary of 7), precedent `target-path-refused`.
- **F2 constant** - Ruled by CTO agent, 2026-10-20: `export const PROMOTION_QUORUM = 5` in
  `cron-compound-promote.ts`; a code constant, not config; census pins one declaration and three
  identifier uses.
- **F3 placement** - Ruled by CTO agent, 2026-10-20: option A, first statement of `draftAdditiveEdit`;
  the `no-source` branch is deleted.
- **F4 order** - Ruled by CTO agent, 2026-10-20: duplicate (body) > target-path-refused (step) >
  quorum-not-met > git reads and the model call.
- **F5 Sentry** - Ruled by CTO agent, 2026-10-20: reuse op `draft-edit-refused`; `source_count` in
  `extra`.
- **F6 slot crowding** - Ruled by CTO agent, 2026-10-20: leave and document.
- **F7 probe** - Ruled by CTO agent, 2026-10-20: class N, `nset`, honest `MIN_CASES`.
- **F8 legacy script / F9 ADR** - Ruled by CTO agent, 2026-10-20: leave the shell script; ADR-092
  Amendment dated 2026-10-20, no new ADR, no C4.

## Research Insights

**Code facts (verified in this worktree)**

- `cron-compound-promote.ts`: constants block at ~62-107; `EditRefusal` at ~933; `draftAdditiveEdit` at
  ~1257 (reads the target first via `readEditTarget`, builds `sources` through `corpusSummaries`, refuses
  zero as `edit-invalid`/`no-source`, then calls the model); handler `record()` at ~1448; phase-1 prompt
  at ~1633; slice to the remaining week cap at ~1690; normalisation at ~1719-1734; the draft step and its
  `!result.ok` branch (logger.warn `draft-edit-refused`, `reportSilentFallback(null, ...)`, return
  `{ kind: "refused", reason }`) at ~1748-1799; trailer at ~2049.
- Census (`cron-compound-promote-outcome-census.test.ts`): Guard 3b `draftStepWindow` needs the
  `async (): Promise<DraftOutcome> => {` opener EXACTLY once and every `return {...}` in it to match
  `{ kind: "drafted", diff: result.diff }` or `{ kind: "refused", reason: result.reason | "[a-z-]+" }`;
  Guard 1b pins `EDIT_REFUSAL_REASONS` to length 7 and one emit site per `edit-*` literal; Guard 1c pins
  two `TARGET_ALLOW_RE.test(` sites in the handler. The new reason is not `edit-` prefixed, so 1b is
  untouched; the new check sits inside the existing draft callback's callee, so 3b and 1c are untouched.
- Probe (`compound-promote-draft-edit-10552.sh`): `GRADE_JQ` classifies by set membership; a reason in no
  set is class N and prints as `unknown` (the `shown` helper), which is why `nset` matters. The suite
  measured **175 cases** on this branch (`All fixtures passed (175 cases)`), equal to `MIN_CASES=175`, so
  the floor is exactly honest today and must be raised by exactly the number of assertions added.
- Marker: `RefusalDetailEntry` carries `{cluster_hash, reason, diff_*}`; `outcome-marker.test.ts` pins the
  field set (Guard 3, #8427). Untouched by this change.

**Institutional learnings applied**

- `2026-10-19-a-model-asked-for-a-diff-it-never-saw-fails-in-a-different-mode-every-week.md` - session
  errors 4 (Sentry `op`/`cause` tags drop on the Error path: use `reportSilentFallback(null, {message,
  tags})`) and 9 (batch every plan-time technical row into the first CTO spawn - done).
- `test-failures/2026-09-19-every-guard-i-shipped-pinned-spelling-not-the-executed-program.md` - the
  census asserts the code that RUNS (comment-stripped, AST), and each guard gets a fixture per member of
  the set it quantifies over; repo-global ratchets are named explicitly because a file-derived suite
  selection cannot see them.
- `2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md` -
  the mutation matrix below targets the chokepoint, its ordering and its dispatch, not only the happy
  path.
- `2026-09-18-the-loop-was-not-failing-it-was-succeeding-at-nothing-and-said-ok.md` - a refusal must be
  a named, countable marker row, never a quiet drop; `quorum-not-met` is exactly that.
- plan-sharp-edges: `decision-challenges.md` rows are machine-gated (`technical-ruling-gate.sh` run and
  passing, 10 rows); a plan declaring `credentials_required` moves `BASELINE_DECLARED_PROBES` (this plan
  does not declare it); a new `SOLEUR_*` marker needs telemetry registration (this change adds none);
  the plan's own discoverability command must be run once (see `## Observability`).

**Open code-review overlap:** queried `gh issue list --label code-review --state open` (200 rows) for the
seven touched paths: none.

## Research Reconciliation - Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "refuse ... before the phase-2 draft step" | The phase-2 CALL is inside `draftAdditiveEdit`, which runs inside the memoized `draft-edit-<hash8>` step. A check outside the step cannot emit a once-per-step Sentry event (body code re-runs on every replay) and a second step breaks Guard 3b. | CTO F3: first statement of `draftAdditiveEdit`, before any git read and before the model call. Same effect (no model call, no spend), replay-safe. |
| "recorded through the same record() path" | `record()` takes a `ClusterOutcome`; a refused draft already becomes `{kind:"refused", reason}` and reaches `record(clusterHash, outcome)`. | No handler change to `record()`; the new reason flows through the existing `outcome` ternary. |
| "closed-vocabulary allowlist and its tests (cron-compound-promote-allowlist.test.ts, outcome-census tests)" | The allowlist file tests `checkDiffPaths`; the closed vocabularies are `EDIT_REFUSAL_REASONS`, probe sets and runbook tables. | Allowlist file: reviewed, no edit. Census gains Guard 1d. Sweep table lists the real members. |
| "grep for every existing refusal reason name ... list every file that enumerates them" | Done: see sweep. | Sweep table below. |
| (not in the brief) existing fixtures | 7 handler fixtures use 2-source clusters; the draft-edit unit fixture uses 2 sources in three places; one handler test asserts `Threshold-Hit: 2/5`; the handler test that feeds all-unknown sources asserts `refusals:["edit-invalid"]` (flips to `quorum-not-met`), and only the draft-edit unit test (T20, ~619-626) asserts the now-dead `no-source` cause. | `## Fixture blast radius`; fixtures rebuilt from `PROMOTION_QUORUM`. |
| (not in the brief) `no-source` | Zero resolved sources is below any positive quorum, so `edit-invalid`/`no-source` becomes unreachable. | CTO F3: delete the branch and its cause; the runbook `edit-invalid` row loses "no resolvable source learning". |

## Reason-vocabulary sweep (up front, per the brief)

Every file in the repo (outside archived plans/specs and point-in-time learnings) that names a refusal
reason, with the disposition for the new `quorum-not-met`:

| File | What it enumerates | Disposition |
|---|---|---|
| `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` | `EDIT_REFUSAL_REASONS`, `EditRefusal`, `DiffPathVerdict`, emit sites, CO-MOVING comment blocks, prompt, trailer | EDIT |
| `apps/web-platform/server/compound-promote-marker.ts` | `reason: string` (free), field set | NO CHANGE (pinned) |
| `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-census.test.ts` | Guards 1, 1b, 1c, 3, 3b | EDIT (add Guard 1d; 1b/3b/1c reviewed, unchanged) |
| `.../cron-compound-promote-draft-edit.test.ts` | `draftAdditiveEdit` unit rows, `no-source` row, shared fixtures | EDIT |
| `.../cron-compound-promote-draft-handler.test.ts` | handler rows, `Threshold-Hit: 2/5`, 2-source fixtures | EDIT |
| `.../cron-compound-promote.test.ts` | constants, phase-1 prompt text, schema | EDIT (pin value, prompt uses the constant) |
| `.../cron-compound-promote-allowlist.test.ts` | `checkDiffPaths` verdicts | NO CHANGE (reviewed) |
| `.../cron-compound-promote-outcome-marker.test.ts` | marker field set, `diff-underivable` rows | NO CHANGE (pins "field set unchanged") |
| `scripts/followthroughs/compound-promote-draft-edit-10552.sh` | `pset`/`fset`/`nset`/`sset`, header comment | EDIT (add to `nset`, comment) |
| `scripts/followthroughs/compound-promote-draft-edit-10552.test.sh` | P-1..P-10, M-1..M-13, `MIN_CASES=175` | EDIT (rows, mutation arms, floor) |
| `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | refusal-enum tables (lines ~626-678) | EDIT |
| `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` | what a streak means; ">=5" prose | EDIT |
| `knowledge-base/engineering/architecture/decisions/ADR-092-...md` | Amendment list of refusal members | EDIT (new dated Amendment) |
| `plugins/soleur/test/preflight-discoverability-test.test.ts` | names `diff-underivable` in a ratchet comment for the earlier plan | NO CHANGE (this plan declares no `credentials_required`, so the G1 count does not move) |
| `scripts/followthroughs/compound-promote-outcome-8281.sh` | the older outcome-marker probe (checks a marker exists, grades no reasons) | NO CHANGE (reviewed) |
| `scripts/compound-promote.sh`, `knowledge-base/project/learnings/promotion-log.md` | legacy `>=5` prompt line; "Source count >=5 to qualify" | NO CHANGE (CTO F8; the doc line stays true) |
| learnings `2026-09-18-...`, `2026-10-19-...`, archived plans/specs | point-in-time records | NO CHANGE |

## Fixture blast radius (the five-CI-cycle trap)

Enforcing the quorum turns every existing two-source fixture into a refusal. Measured sites:

- `cron-compound-promote-draft-handler.test.ts`: `AGENTS_CLUSTER` and `SKILL_CLUSTER` (lines ~133-144),
  the `second` clusters at ~249, ~260, ~332, ~356, the evil-path test at ~310, the all-unknown test at
  ~323 (expects `edit-invalid`, becomes `quorum-not-met`), the duplicate-collapse test at ~405-409
  (`Threshold-Hit: 2/5`), the corpus seed `for n <= 6` at ~103 (widen to `2 * PROMOTION_QUORUM + 2` computed from the constant, not a literal; every multi-cluster fixture uses DISJOINT or at least different source sets, because the step name is `draft-edit-<hash8>` of the sorted set and a repeated set is served from the memo map).
- `cron-compound-promote-draft-edit.test.ts`: `summaries` and `cluster` at ~528-536 (also read by T10/T11/T12 at ~628-639 which expect `edit-target-*` / `target-path-refused`, T10b at ~648-652 which expects a THROW, and T16 at ~641 - a sub-quorum fixture would turn the first two into `quorum-not-met` and T10b into a non-throw), the T20 `no-source`
  row at ~619-626, the prompt-grammar row at ~845-864 (one-entry map).
- `cron-compound-promote.test.ts`: the phase-1 prompt slice test (~257-267) is unaffected in shape; it
  gains a check that the prompt slice contains `${PROMOTION_QUORUM}`.

Rule for the rewrite: fixtures derive their size from the exported constant
(`Array.from({ length: PROMOTION_QUORUM }, ...)`), never from a literal 5, so changing the constant
cannot make a test pass vacuously; ONE row pins the value itself (`toBe(5)`), see Guard 1's anchor note.

## Approach

### Production change (`apps/web-platform/server/inngest/functions/cron-compound-promote.ts`)

1. **Constant.** `export const PROMOTION_QUORUM = 5;` in the constants block (after `MAX_DIFF_BYTES`),
   with a doc comment: what it gates, that it is a code constant on purpose (ADR-092 Amendment
   2026-10-20), and that the prompt, the drafter check and the trailer all read it.
2. **Refusal type.** `EditRefusal.reason` becomes `EditRefusalReason | "target-path-refused" |
   "quorum-not-met"`; add optional `sourceCount?: number`. `EDIT_REFUSAL_REASONS` stays at seven.
3. **The check, in `draftAdditiveEdit`.** Move the pure `sources` construction (the loop over
   `cluster.source_learnings` through `corpusSummaries`, deduped) above `readEditTarget`. Then:

   ```ts
   if (sources.length < PROMOTION_QUORUM) {
     return { ok: false, reason: "quorum-not-met", cause: "below-quorum", sourceCount: sources.length };
   }
   ```

   The `if (sources.length === 0) return invalidEdit("no-source")` branch is deleted. The literal
   `reason: "quorum-not-met"` appears exactly once in the module. Because the loop is pure (a `Map`
   lookup, no I/O), the drafter reads nothing and spends nothing for a refused cluster. The draft callback's own pre-reads (the API-key presence check and `readAlwaysLoaded`, which run before the drafter) still execute; they are not a model call and are accepted, stated in the ADR Amendment.
4. **Handler wiring (three small edits, no new step).**
   - Phase-1 prompt: `(each with >=${PROMOTION_QUORUM} source learnings; the server refuses a cluster
     with fewer, so do not return one)`, and `source_learnings` entries are told to be exact corpus key
     paths, at least `${PROMOTION_QUORUM}` distinct (a mechanical tightening that makes dropped hallucinated
     paths less likely; the existing prompt-slice test still passes).
   - Trailer: ``Threshold-Hit: ${cluster.source_learnings.length}/${PROMOTION_QUORUM}``.
   - The existing `!result.ok` branch forwards the count when present:
     `extra: { cluster_hash: clusterHash, ...(result.sourceCount === undefined ? {} : { source_count: result.sourceCount }), ...(result.proposedCount === undefined ? {} : { proposed_count: result.proposedCount }) }`.
     `proposedCount` comes from an optional `raw_source_count` the handler's normalisation records on the
     proposal (`Array.isArray(c.source_learnings) ? length : 0`, captured BEFORE the filter) and the drafter echoes
     on the refusal; it is internal to `ProposedCluster`/`EditRefusal`, is not copied into `Cluster`, and never
     reaches the marker (so a sub-quorum cluster's two integers separate "model proposed too few" from
     "normalisation dropped hallucinated paths").
     Message, tags (`reason`, `cause`) and op are unchanged by construction, so the event is
     `draft edit refused: quorum-not-met (below-quorum)` on op `draft-edit-refused`.
   - A comment at the phase-1 `slice(0, weekCapResult.remaining)` records the F6 consequence: a refused
     cluster still occupies one of the remaining proposal slots.
5. **Comments that name the old behaviour:** the normalisation comment at ~1718 ("refused `edit-invalid`
   (no-source)") and the CO-MOVING ARTIFACTS block at ~910 (add the quorum reason, the census Guard 1d,
   the probe class and the runbooks).

**Census Guard 1d (implementation recipe, so it is not discovered at work time).** Reuse the TypeScript
AST already imported in `cron-compound-promote-outcome-census.test.ts` (`ts.createSourceFile`). Export the
census function so a dispatch row can drive it with synthetic sources. Assertions: (a) exactly one
`VariableDeclaration` named `PROMOTION_QUORUM` with a numeric-literal initializer; (b) the `TemplateExpression`
whose head contains `clustering agent` has a span that is the `PROMOTION_QUORUM` identifier; (c) the template
whose head starts with `Threshold-Hit:` has its LAST span the identifier and no literal tail matching `/^\/\d/`;
(d) a `BinaryExpression` with operator `<`, left `sources.length`, right the identifier; (e) exactly one
`PropertyAssignment` `reason` with the literal `quorum-not-met`, and it is not in `EDIT_REFUSAL_REASONS`
(declared length still 7); (f) dispatch rows: a synthetic source with zero declarations and one with two both
THROW; (g) the matrix mutations for Guard 1d (prompt back to `>=5`, trailer back to `/5`, a second emit site, a
second declaration) are PERMANENT in-file rows in the census test's existing style (`src.replace(anchor, ...)`
with `expect(src).toContain(anchor)` so the mutation must land), because a PR-body table does not run in CI;
use one `it` per member so each failure is granular. Any new window helper needs a `// window-assembly:` declaration comment (the Guard Contract lint reads
it). Sharp edge: the new `extra: {...}` spread in the draft callback must not produce a line that is exactly
`\n        },\n      );` at 8-space indentation, because `draftStepWindow` closes on that string.

What does NOT change: `record()`, the `draft` / `outcome` ternaries, `draftedTargets` handling (only a
drafted outcome adds a target, so a quorum-refused cluster never blocks a later valid cluster on the
same target), `emitOutcomeMarker`, `compound-promote-marker.ts`, `checkDiffPaths`, the apply step.

### Why this holds under Inngest replay

The check is a pure function of the memoized phase-1 result and the memoized corpus, evaluated inside the
memoized `draft-edit-<hash8>` callback. On replay that callback is not re-entered, the memoized
`{kind:"refused", reason:"quorum-not-met"}` is served, `record()` (handler body) re-counts it, and the
Sentry message was emitted exactly once. In-flight runs across the deploy: a `draft-edit-*` step
memoized under the old code for a sub-quorum cluster resumes on the new code with a memoized "drafted"
diff and opens its PR once; the window is one weekly run of a few minutes and is accepted and stated
here (same disposition as the #10552 deploy-window note at `record()`).

### Probe (`scripts/followthroughs/compound-promote-draft-edit-10552.sh`)

Add `"quorum-not-met"` to `nset` so it is printed instead of bucketed `unknown`; update the header
comment's N-class list. No change to `pset`/`fset`, the precedence rule, the floor derivation or the
35-day ACTION REQUIRED escalation (CTO F7). Class N means: never PASS (the model, or normalisation,
produced too few sources - no derived diff was consumed) and never FAIL (not a server defect).

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` - items 1-5 above.
- `apps/web-platform/test/server/inngest/cron-compound-promote-draft-edit.test.ts` - quorum rows Q1-Q4,
  fixture rebuild from the constant, T20 `no-source` row replaced, prompt-grammar row widened.
- `apps/web-platform/test/server/inngest/cron-compound-promote-draft-handler.test.ts` - handler rows
  H1-H8, fixture rebuild, corpus seed widened, `Threshold-Hit` assertions built from the constant.
- `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-census.test.ts` - Guard 1d.
- `apps/web-platform/test/server/inngest/cron-compound-promote.test.ts` - value pin and prompt check.
- `scripts/followthroughs/compound-promote-draft-edit-10552.sh` - `nset`, header comment.
- `scripts/followthroughs/compound-promote-draft-edit-10552.test.sh` - rows P-4b and P-4c, mutation arms
  M-14 and M-15, `MIN_CASES` raised by the measured delta.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` - the pre-draft refusal
  table gains `quorum-not-met` (a second small table, because it is not an `edit-*` member), the
  `edit-invalid` row drops "no resolvable source learning", and the Sentry-cause paragraph names
  `below-quorum` and `source_count`.
- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` - line ~17 says the
  server enforces `PROMOTION_QUORUM`; the "How a proposal is drafted" section gains the quorum step;
  the streak list gains a `quorum-not-met` bullet; a short note that a run memoized under the old code can still end `edit-invalid` after the `no-source` cause is deleted (one weekly run) and that an empty-list cluster hash is a constant, not a recurring cluster; `last_updated` bumped.
- `knowledge-base/engineering/architecture/decisions/ADR-092-additive-only-auto-edit-boundary-and-hard-rule-body-weakening-gate.md`
  - dated Amendment (via `soleur:architecture`), see `## Architecture Decision (ADR/C4)`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-compound-promote-server-quorum/tasks.md` (this planning
  phase) and `.../decision-challenges.md` (done).
- `knowledge-base/project/learnings/<topic>.md` - work-phase compound learning, topic only (date at
  write time): a threshold that lives only in a prompt is not a constraint; the fixtures that encoded the
  unenforced number were the blast radius.

No `.tf`, migration, workflow, UI, marker or new test file is touched. Globs verified: every edit path
above exists (`git ls-files`); the only new paths are the two spec files and the learning.

## Implementation Phases (test-first)

**Phase 0 - RED.** One inert production line first so fixtures compile and RED is an assertion
failure rather than an import error: add `export const PROMOTION_QUORUM = 5;` alone (unused). Then
write, and run to separate the rows that must be RED from the characterization pins that are
GREEN-by-design (a pin is not a RED proof and is not counted as one):

- RED, right reason: `draft-edit.test.ts` Q1, Q3, Q4 (a sub-quorum cluster currently drafts and calls
  `post`, so `expect(post).not.toHaveBeenCalled()` and the `reason` assertion fail); `draft-handler.test.ts`
  H1, H2, H3, H7 (today a sub-quorum cluster opens a PR, and H7's Sentry count is 0); census Guard 1d
  reference checks (prompt still `>=5`, trailer still `/5`, no comparison, no emit site); probe P-4b (the
  print assertion fails: the reason is bucketed `unknown`).
- GREEN-by-design pins: Q2, H4, H5, H6, V1 (the inert constant is 5 and a 5-source cluster already
  drafts), P-4c, and Guard 1d's declaration/value sub-checks. Their load comes from the mutation rows.
- M-14 and M-15 cannot "land" before `nset` carries the entry; the expected RED reason is the harness's
  `anchor did not land` failure, recorded as such.

**Phase 1 - GREEN, production.** Approach items 2-5. Re-run the four vitest files.

**Phase 2 - GREEN, probe.** `nset` plus comment; measure the new suite total and set `MIN_CASES` to
exactly that total (not rounded up).

**Phase 3 - docs and record.** Runbooks, ADR-092 Amendment (`soleur:architecture`), compound learning.

**Phase 4 - mutation proof.** For every row of the Guard Contract matrix below: copy the file to the
scratchpad, apply the one-line edit, run only the named suite, record RED, restore from the scratch copy
and confirm `git diff` is back to the intended change. Record the table in the PR body.

**Phase 5 - verify.** Targeted suites only (machine is contended): the four vitest files; the probe
suite; `./node_modules/.bin/tsc --noEmit` in `apps/web-platform`; `python3 scripts/lint-guard-contract.py`
on this plan; `npx markdownlint-cli2` on touched `.md`; and the repo-wide ratchets that a file-derived
selection cannot reach, named here so they are not discovered in CI:
`bash scripts/lint-betterstack-emitter-read.sh` (probe edited),
`bash plugins/soleur/test/fixture-relative-assert.test.sh` (probe suite edited),
`bash .claude/hooks/grep-q-pipe-guard.test.sh` (probe suite edited),
`bash scripts/test-affected-kb-consumers.test.sh` (KB files edited),
`python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (plan docs).
No new vitest file means `apps/web-platform/test/repo-wide-suites.ts` is not touched.

At ship: PR body uses `Ref #10552` (never `Closes`), first line states that merging this alone changes
the weekly cron's behaviour on the next scheduled fire (apps/web-platform release), and that PASS
evidence for #10552 may arrive later because sub-quorum clusters no longer open class-P draft PRs.
Diff-scope AC note: the pipeline also writes `knowledge-base/INDEX.md` and `specs/<branch>/session-state.md`
when it runs; the "only these files" check must include them.

## Test Scenarios

Real throwaway git repos (existing fixture pattern); every test asserts at least once. `Q` below means
`PROMOTION_QUORUM`; layer in brackets.

| # | Scenario | Expected |
|---|---|---|
| Q1 [unit] | `draftAdditiveEdit` with `Q-1` distinct resolved sources, and again with zero sources (replaces the T20 `no-source` row) | `{ok:false, reason:"quorum-not-met", cause:"below-quorum", sourceCount:Q-1}` (and `0`), echoing an optional `raw_source_count` as `proposedCount`; `post` not called |
| Q2 [unit] | exactly `Q` resolved sources | proceeds; `post` called once; derived diff applies |
| Q3 [unit] | `2Q` entries listed: `Q-2` distinct in-corpus plus duplicates plus unknown paths | refused; `sourceCount` counts RESOLVED DISTINCT (the prompt's set), not the raw length |
| Q4 [unit] | sub-quorum with `repoRoot` nonexistent, and with a symlink / oversized / missing target | `quorum-not-met` returned (no throw, no `edit-target-*`): proves the check precedes every git read |
| H1 [handler] | one cluster listing `Q-1` valid plus 2 unknown paths (raw length `Q+1`) | marker `refusals:["quorum-not-met"]`, `clusters_opened:0`; `phase2Calls()` empty; `safeCommit` not called; no `apply-and-pr-*` step; `refusal_detail[0]` has exactly `{cluster_hash, reason}`; Sentry called with `(null, objectContaining({op:"draft-edit-refused", message:"draft edit refused: quorum-not-met (below-quorum)", tags:{reason:"quorum-not-met", cause:"below-quorum"}, extra: objectContaining({cluster_hash, source_count: Q-1, proposed_count: Q+1})}))` |
| H2 [handler] | two clusters on two DIFFERENT targets (AGENTS and SKILL, so a same-target duplicate cannot shadow the quorum check): valid first, sub-quorum second, and the reverse order; the run's status is `completed` and the heartbeat step ran (an all-refused week is a green zero-output run, not an error) | exactly one opened, one refused; exactly ONE phase-2 call (the second cluster is observed refused, not merely absent) |
| H3 [handler] | sub-quorum cluster on target T, then a valid cluster on T | the valid one drafts and opens (T was not consumed); no `edit-target-duplicate` |
| H4 [handler] | valid cluster on T drafts, then a sub-quorum cluster on T | second is `edit-target-duplicate` (CTO F4 order, pinned) |
| H5 [handler] | off-allowlist `target_path` with a sub-quorum list | `target-path-refused` (security signal wins); no `quorum-not-met` |
| H6 [handler] | exactly `Q` sources, and `Q+2` sources | both open; trailer `Threshold-Hit: Q/Q` and `(Q+2)/Q` built from the constant; `Source-Learnings` lists the paths |
| H7 [handler] | full replay with a shared memo map, sub-quorum cluster | same marker both passes; the Sentry mock filtered to `op === "draft-edit-refused"` has `toHaveBeenCalledTimes(1)` after pass 1 AND after pass 2 (asserting only "unchanged" would pass vacuously if the event never fired; the mock is cleared only in `beforeEach`); phase-2 call count unchanged |
| H8 [handler] | two sub-quorum clusters with IDENTICAL normalised lists on different targets, and two clusters with EMPTY lists (the cluster hash is over the sorted sources only, so both pairs share `draft-edit-<hash8>`; an empty list hashes to the same constant every week) | both refusals are counted in `refusals[]` and Sentry fires for each (no memo map, so the harness does not alias them); the runbook notes that a recurring empty-list hash is not a streak of one cluster |
| C1 [census] | Guard 1d: one numeric `PROMOTION_QUORUM` declaration; the phase-1 prompt, the `Threshold-Hit` template and the `sources.length <` comparison each reference the identifier; no literal `>=5` or `/5` in the prompt and trailer; `reason: "quorum-not-met"` has exactly one emit site and is not a member of `EDIT_REFUSAL_REASONS` (length still 7) | green; each mutation in the matrix reddens it |
| V1 [unit] | `PROMOTION_QUORUM` equals 5 | the value pin (comment: raising or lowering it needs an ADR-092 Amendment and the runbook line) |
| P-4b [probe] | window of one run refusing only `quorum-not-met` | exit 2, stdout not `PASS`, reason printed as `quorum-not-met` (not `unknown`) |
| P-4c [probe] | same run also refusing `byte-budget-overflow` (class P) | exit 0 (a sub-quorum sibling does not suppress proof) |
| M-14 [probe] | MUTATION: drop the entry from `nset` (anchor: the `nset` tail `"branch-name-shape-failed","diff-size-exceeded"];`) | P-4b's print assertion reddens; implemented as a `mut_row` with a new scenario helper and healthy-predicate (for example `sc_quorum` and `h_quorum_shown`), because M-5..M-13 are predicate-style arms, not exit-code sandboxes |
| M-15 [probe] | MUTATION: add the entry to `pset` (anchor: `def pset: ["byte-budget-overflow"];`) | P-4b exits 0 instead of 2 (same `mut_row` mechanism); update the suite's header comment that names the mutation range `M-5 .. M-13` |

## Guard Contract

### Guard 1 - the server quorum chokepoint

**Property.** No cluster with fewer than `PROMOTION_QUORUM` distinct corpus-resolved source learnings
reaches the phase-2 model call or opens a draft PR, and the refusal is a named, once-per-step, marker-
and-Sentry-visible outcome.

**Assembly.** The members are not "the call sites that exist today" but every path by which a cluster can
turn into a model call or a trailer: (a) `draftAdditiveEdit`, the one function that builds the phase-2
prompt and calls `post` - the chokepoint, whose `sources` is exactly the set the model would be shown;
(b) the handler's normalisation (which produces the list the trailer reports) and the draft step that
calls (a); (c) the phase-1 prompt text and the `Threshold-Hit` template, which must name the same
constant; (d) any future caller of `draftAdditiveEdit` (it is exported). The check is placed at (a), the
single point all of (b) and (d) flow through, rather than at (b) alone.

**Mutation matrix**

| # | Edit (drive the guard RED) | Must go RED in |
|---|---|---|
| 1 | delete the `sources.length < PROMOTION_QUORUM` check | Q1, H1, C1 |
| 2 | `<` becomes `<=` (an at-quorum cluster is refused) | Q2, H6 |
| 3 | move the check below `readEditTarget`, or below the `post` call | Q4 (nonexistent root throws / unreadable target wins), Q1 (`post` called) |
| 4 | count `cluster.source_learnings.length` (raw) instead of the resolved distinct `sources` | Q3 |
| 5 | the guard's own dispatch: remove the declaration or every use of `PROMOTION_QUORUM` so the census sees zero | C1 (a census finding zero declarations/uses THROWS, never reads clean) |
| 6 | a second compliant member: skip the check once any target has drafted (e.g. gate it on `draftedTargets.size === 0`) | H2 in both orders |
| 7 | revert the prompt to `>=5`, or the trailer to `/5` | C1 |
| 8 | drop `tags` (or switch to the Error path) on the quorum event | H1 (call-shape assertion) |

Invariants this change relies on but does not re-prove (each already has a guard that reddens on the
mutation, named so nobody re-executes it): a refused target added to `draftedTargets` (H3); `source_count`
forwarded into the marker `refusal_detail` (H1 exact keys and `outcome-marker.test.ts` Guard 3); an
accumulator push placed in the handler body (H1's exact `refusals:["quorum-not-met"]` catches a double count) or a `reportSilentFallback` placed there (H7: Sentry call count grows on replay); Guard 3b only fires if the push lands inside the draft callback window; a second emit site for the reason (C1 emit-once).

**Harness rows.** (i) Delete every `expect` in the new rows: the suites' `expect.hasAssertions()` floor
reddens. (ii) Must-PASS inputs that are NOT the canonical happy path and differ in a way the contract
permits: `Q+2` sources (H6); `2Q` listed entries that collapse to exactly `Q` distinct (Q3 variant); the
sub-quorum cluster placed second rather than first (H2 reverse); a quorum-refused target reused by a valid
cluster (H3).

**Anchor.** `PROMOTION_QUORUM = 5` is a stored value, and every fixture is built from the constant, so a
diff that lowers it passes the battery: the guard proves consistency, not integrity. The outside-the-
commit movers are the value-pin row V1 (a visible one-line diff) and the ADR-092 Amendment plus runbook
sentence stating "5"; there is no merge-base or WORM check, and the plan does not claim one.

### Guard 2 - the follow-through probe never reads the new reason as proof

**Property.** `compound-promote-draft-edit-10552.sh` exits 0 only on positive evidence that a derived
diff was consumed; a run whose only refusal is `quorum-not-met` is class N (exit 2 while soaking, 5 after
35 days), never PASS and never FAIL, and the reason is printed, not bucketed `unknown`.

**Assembly.** Every set in `GRADE_JQ` (`pset`, `fset`, `nset`, `sset`), the `shown` printing helper, the
precedence rule (any P wins, else the latest post-floor run decides), and the suite's row families
P-1..P-10. The new reason enters `nset` only.

**Mutation matrix**

| # | Edit (drive the guard RED) | Must go RED in |
|---|---|---|
| 1 | remove `quorum-not-met` from `nset` (it prints `unknown`) | P-4b print assertion, M-14 |
| 2 | add it to `pset` (false PASS) | P-4b (rc 0 not 2), M-15 |
| 3 | second member after a compliant first: a class-P sibling in the same run must still win | P-4c (a mutant that lets N override P reddens it) |

**Harness rows.** (i) `MIN_CASES` is raised by exactly the measured delta from the 175 baseline, so
stripping assertions reddens the floor (an over-raised floor would make the suite fail on a healthy tree;
an unraised floor would leave the new rows unprotected). (ii) Must-PASS non-canonical: P-4c is a PASS
whose run also carries the new reason.

**Anchor.** Unchanged from the #10552 probe (the derived deploy floor); this plan adds no stored value.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_COMPOUND_PROMOTE_OUTCOME marker (status, clusters_proposed, clusters_opened, refusals[], refusal_detail[]) emitted on every terminal path, plus the Sentry cron monitor scheduled-compound-promote
  cadence: weekly, Sunday 00:00 UTC (cron 0 0 * * 0), plus any manual-trigger run
  alert_target: Sentry monitor scheduled-compound-promote (liveness only); the open #10552 tracker and the follow-through sweeper comment. No alert rule pages a person on refusals
  configured_in: apps/web-platform/server/inngest/functions/cron-compound-promote.ts (emitOutcomeMarker calls, SENTRY_MONITOR_SLUG) and apps/web-platform/server/compound-promote-marker.ts
error_reporting:
  destination: Sentry web-platform via reportSilentFallback (feature cron-compound-promote, op draft-edit-refused with tags reason and cause, extra cluster_hash, source_count and proposed_count) and Better Stack Logs via the marker
  fail_loud: each refused cluster logs a pino warn row (draft-edit-refused, with hash, reason, cause) and mirrors to Sentry as a MESSAGE event with err null (on the Error path the pino mirror captures first and Sentry drops the tagged capture, #8629); the marker refusals[] names quorum-not-met; the marker field set is unchanged
failure_modes:
  - mode: the model returns clusters below the quorum, or its source list collapses below it after dedupe and corpus filtering
    detection: marker refusals[] contains quorum-not-met (layer 2 pino to Sentry mirror; layer 3 Vector journald shipper to Better Stack); Sentry op draft-edit-refused tagged reason quorum-not-met and cause below-quorum, extra source_count
    alert_route: follow-through probe prints the reason (exit 2, class N); after 35 days of no proof the sweeper receives exit 5 ACTION REQUIRED on the open tracker
  - mode: every cluster refused every week (a persistent quorum streak or slot crowding)
    detection: refusal_detail cluster_hash recurring in the marker week over week (layer 3 Vector journald shipper to Better Stack marker row, query in betterstack-log-query.md; the Sentry monitor scheduled-compound-promote proves the run itself fired); the probe's recent-runs list shows the streak
    alert_route: the 35-day ACTION REQUIRED escalation on the tracker; a separate issue if crowding is shown (CTO F6)
  - mode: the check is silently disabled or reordered by a later edit
    detection: census Guard 1d and the unit rows Q1-Q4 fail in CI (no runtime layer applies: this is a CI-only failure, not production-silent, so no pino, Vector or Sentry layer is cited)
    alert_route: CI required check on the PR
logs:
  where: Better Stack Logs source 2457081 (marker and pino rows via Vector journald shipper); Sentry web-platform for the message events
  retention: Better Stack source retention as configured (hot window plus archive arm, per betterstack-log-query.md); Sentry per project retention
discoverability_test:
  command: grep -o -e 'reason: "quorum-not-met"' apps/web-platform/server/inngest/functions/cron-compound-promote.ts
  expected_output: quorum-not-met
```

Honest limit of the discoverability command: it proves the emitter declares the reason in the PR tree
(offline, no credentials, sub-second). It does not prove the stored Better Stack stream carries it; that
property has no unauthenticated substitute and is covered by the existing credentialed follow-through
probe, so this plan deliberately declares no `credentials_required` (which would move the repo-wide
`BASELINE_DECLARED_PROBES` ratchet). The command contains none of the shell-active characters Check 10
rejects. It cannot return a match until Phase 1 lands; Phase 5 runs it once and records the output. It would also match a
comment repeating the literal, so it is weaker than the census emit-once assertion, which parses the AST; the
two pin the same literal and stay in step.

Affected-surface note (plan Phase 2.9.2): the surface is a cron worker. The discriminating fields for
the competing hypotheses (model proposed too few vs normalisation dropped hallucinated paths) are
`source_count` (distinct corpus-resolved) and `proposed_count` (the model's raw list length, captured before
normalisation) on the Sentry event, together with the marker's recurring `cluster_hash`; `proposed_count -
source_count` is the dropped fraction. Both are bare integers in `extra` (a length is not model text), and
neither goes to the marker, whose field set is forbidden to change. The event is level `error` (message path of
`reportSilentFallback`) although the refusal is model-side: it adds issue-stream noise, not a page, and no
alert may be wired on this op without a threshold.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The failure mode is operator-
  internal: either the weekly loop opens fewer draft PRs than intended (a too-strict check) or it
  continues to open sub-quorum draft PRs whose own trailer reads below `N/5` (a missing check). No end-user
  surface is touched.
- **If this leaks, the user's data is exposed via:** no new vector. The change reads only the already-
  collected corpus Map and reduces the number of model calls; no new data flows to Anthropic or GitHub.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the loop never auto-merges and every proposal is operator-
  reviewed, so a quorum bug costs reviewer attention, not a user-visible incident; `aggregate pattern`
  would apply only if sub-quorum rules reached the always-loaded corpus unreviewed, which the unchanged
  human-review gate prevents.

`threshold: none, reason: apps/web-platform/server/ is a sensitive path by regex, but this change only
adds a pure count gate that REDUCES model spend and draft PRs on an operator-reviewed, never-auto-merged
loop; it touches no auth, credential, RLS, billing or user-data surface.`

## Architecture Decision (ADR/C4)

Detection: this extends an existing ADR's guarantee (the boundary of what may be auto-proposed into the
always-loaded corpus) with a server-enforced precondition. It is not a new substrate or boundary, but a
reader of ADR-092 alone would be misled about where the "5" is enforced, so the record updates in this
PR (rule `wg-architecture-decision-is-a-plan-deliverable`).

### ADR

Amend ADR-092 (`knowledge-base/engineering/architecture/decisions/ADR-092-...md`) with
`## Amendment - server-enforced promotion quorum (2026-10-20)`, via `soleur:architecture` (a task in
Phase 3, not a follow-up). Content, per CTO F9 and F6: the quorum of 5 source learnings is now enforced
in code by `PROMOTION_QUORUM`, no longer only in the phase-1 prompt; the new refusal member
`quorum-not-met` (not an `edit-*` member; `EDIT_REFUSAL_REASONS` stays seven); the check is the first
statement of `draftAdditiveEdit`, counts distinct corpus-resolved sources and subsumes the old
`edit-invalid`/`no-source` cause; the trailer denominator and the prompt read the constant; the marker
field set is unchanged; the constant is a code constant, not config, so a config-only change cannot weaken
it; the known consequence that a refused cluster still occupies one of the week-cap proposal slots (and still counts in the headroom divisor `proposals.length - clusterIndex`, so a valid first cluster is offered a smaller headroom share); that the draft callback's API-key and `readAlwaysLoaded` pre-reads still run before the drafter; the
probe class (N); and the stated limit that the gate counts distinct corpus paths, not relatedness, so
`Threshold-Hit: 5/5` is a floor and the human review of each draft PR is unchanged. No new ordinal is claimed (an Amendment), so the ordinal-collision gate does not apply.

### C4 views

C4 completeness check (all three of `model.c4`, `views.c4`, `spec.c4` read at work time per the mandate):
external human actors - the operator reviewing draft PRs (already modeled; unchanged relationship);
external systems - Anthropic (phase-1/phase-2 model calls: already modeled, call volume only falls),
GitHub (draft PRs: already modeled), Sentry and Better Stack (already modeled); data stores - none added;
actor-to-surface access relationships - none changed. The relevant element is the same Inngest cron
calling the same external systems. Conclusion: no C4 change, confirmed by CTO F9; the work phase must
still run `plugins/soleur/test/c4-count-parity.test.sh` to confirm no derived cardinality on an edge moved
(no workflow, monitor or heartbeat is added or removed).

### Sequencing

The Amendment is authored now and describes the target state; nothing waits on a soak.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled nine forks (see `## Technical Rulings`). No Product/UX surface (no `components/`,
`app/**/page.tsx` or `layout.tsx` file), so the mechanical UI override does not fire. Marketing, legal,
finance, sales, support and operations have no implication: no vendor, cost line, user-facing copy or
processing activity changes (model spend only falls). GDPR gate: not invoked - no regulated-data surface
by the canonical regex beyond the existing cron, and none of triggers (a)-(d) is new (the cron already
reads `knowledge-base/project/learnings/` and calls the model; this change removes calls, adds no flow).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "refuse any cluster whose distinct, in-corpus source_learnings count is below the quorum (5, a single named constant, not a literal repeated in places)" | Approach 1, 3, 4; Guard 1 | mapped |
| 2 | "The refusal must be a new member of the closed refusal vocabulary (pick a name like `quorum-not-met`; the CTO agent rules on the name" | Technical Rulings F1; decision-challenges.md | mapped |
| 3 | "recorded through the same record() path and marker refusals[] as the other refusals" | Approach (no `record()` change; flows via the draft outcome) | mapped |
| 4 | "reaching Sentry through the same message-path convention (reportSilentFallback(null, { message, tags }), see #8629)" | Approach 4 (existing `!result.ok` branch); H1 | mapped |
| 5 | "must not add any field to the outcome marker" | Cut list; H1 exact-keys; outcome-marker test unchanged | mapped |
| 6 | "It must not spend a model call for the refused cluster." | Approach 3; Q1, Q4, H1 | mapped |
| 7 | "Keep Inngest replay safety: accumulators live in the handler body, not inside step callbacks" | Replay section; Guard 3b (existing); H7 | mapped |
| 8 | "grep for every existing refusal reason name across the repo and list every file that enumerates them" | Reason-vocabulary sweep | mapped |
| 9 | "the closed-vocabulary allowlist and its tests (cron-compound-promote-allowlist.test.ts, the outcome-census tests)" | Sweep (allowlist reviewed, census Guard 1d) | mapped |
| 10 | "the follow-through probe ... and its test (classify the new reason; ... class N, never PASS and never FAIL, keep MIN_CASES honest)" | Probe section; Guard 2 | mapped |
| 11 | "the runbooks (compound-promote-runbook.md, betterstack-log-query.md if it lists reasons)" | Files to Edit | mapped |
| 12 | "an ADR-092 dated amendment" | Architecture Decision (ADR) | mapped |
| 13 | "Write failing tests first, and mutation-prove every guard you add" | Phase 0, Phase 4, both Guard matrices | mapped |
| 14 | "Repo-wide ratchets to check locally before pushing if test/script files are added" | Phase 5 ratchet list | mapped |
| 15 | "PR body: use `Ref` for issue numbers, not `Closes`. Do not touch #10552, #8443" | Phase 5 ship note | mapped |
| 16 | "Do not edit anything under knowledge-base/legal/." | Files to Edit has no legal path | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `PROMOTION_QUORUM` constant | "a single named constant, not a literal repeated in places" | asked |
| first-statement check in `draftAdditiveEdit` | "It must not spend a model call for the refused cluster." | asked |
| deleting the `no-source` branch | -- | inferred - justification: with a positive quorum zero sources is already below it, so the branch is dead code that a mutation-prover would flag and a closed `cause` vocabulary should not carry; CTO F3 |
| `source_count` in Sentry `extra` | "reaching Sentry through the same message-path convention" | asked (the field itself: inferred - justification: triage needs the observed count and CTO F5 ruled it belongs in `extra`, never a tag or the marker) |
| census Guard 1d | "mutation-prove every guard you add" | asked |
| value-pin row V1 | "mutation-prove every guard you add" | inferred - justification: fixtures derive from the constant, so without one pinned value a lowered constant passes every test (Guard 1 anchor) |
| fixture rebuild in three test files | "Write failing tests first" | inferred - justification: the existing two-source fixtures become `quorum-not-met` the moment the check lands; leaving them fails the suites |
| probe rows P-4b, P-4c, M-14, M-15 | "classify the new reason; a quorum refusal is a model-side outcome, so class N" | asked |
| `MIN_CASES` raised by the measured delta | "keep MIN_CASES honest" | asked |
| runbook edits (both) | "the runbooks (compound-promote-runbook.md, betterstack-log-query.md if it lists reasons)" | asked |
| ADR-092 Amendment | "an ADR-092 dated amendment" | asked |
| comment at the phase-1 slice | -- | inferred - justification: CTO F6 requires the slot-crowding consequence be documented at the code site, or the next reader re-opens the question |
| compound learning file | -- | inferred - justification: the work-phase exit gate (`soleur:compound`) requires capturing session learnings; topic only, date at write time |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform`, `scripts`, `knowledge-base`
- Planned files: 11 edited + 3 created (plan, tasks, learning) | Estimated changed lines: about 450 (about 60 production, 280 tests, 60 probe suite, 50 docs)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - below every threshold, and the sweep requirement forbids splitting the reason across PRs.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `PROMOTION_QUORUM` is declared once (`export const PROMOTION_QUORUM = 5`) and referenced by the
  phase-1 prompt, the `draftAdditiveEdit` check and the `Threshold-Hit` template; the literals `>=5` and
  `/5` no longer appear in the prompt or the trailer (Guard 1d; implementation locations
  `cron-compound-promote.ts` constants block, prompt at the `anthropic-cluster` step, trailer in the
  `safeCommitAndPr` config).
- [ ] A sub-quorum cluster ends `quorum-not-met` in marker `refusals[]` with `refusal_detail` entry
  keys exactly `cluster_hash` and `reason`; `compound-promote-marker.ts` has an empty diff and
  `cron-compound-promote-outcome-marker.test.ts` is green unchanged (H1).
- [ ] No phase-2 model call for a refused cluster, and no git read INSIDE `draftAdditiveEdit` (Q1, Q4: `post` spy; H1: `post` spy and
  `phase2Calls()` empty).
- [ ] The Sentry event is `(null, {op:"draft-edit-refused", message:"draft edit refused: quorum-not-met
  (below-quorum)", tags:{reason, cause}, extra:{cluster_hash, source_count, proposed_count}})` and fires once across a
  full replay (H1, H7).
- [ ] `EDIT_REFUSAL_REASONS` is still length 7; Guard 1b, 1c, 3, 3b pass unmodified; Guard 1d is added and
  passes.
- [ ] Every Guard 1 (8) and Guard 2 (3) matrix row was executed and went RED in the named test (table in the PR
  body); each file restored afterwards.
- [ ] Probe: `quorum-not-met` only in `nset`; the probe suite reports `All fixtures passed (N cases)` with
  `MIN_CASES` equal to that measured N (baseline 175; the delta is the count of assertions added, written
  down in the PR body).
- [ ] The discoverability command returns `reason: "quorum-not-met"` when run once (output recorded).
- [ ] Runbooks and ADR-092 Amendment merged; markdownlint clean on touched `.md`;
  `python3 scripts/lint-guard-contract.py` passes on this plan with 2 entries.
- [ ] Repo-wide ratchets in Phase 5 pass; `tsc --noEmit` clean.
- [ ] PR body uses `Ref #10552` (no `Closes`); `#10552` and `#8443` are not edited; no path under
  `knowledge-base/legal/` is in the diff (`git diff --name-only origin/main...HEAD`).

### Post-merge

- [ ] Automation: none needed for correctness (tests prove the gate). Production evidence arrives on the
  next scheduled fire; the existing #10552 follow-through probe reads it, and a `quorum-not-met` streak
  surfaces through its 35-day ACTION REQUIRED escalation. No operator step is added.

## Deferred and Not Adopted (from deepen-plan, tracked)

- **Symlinked `.md` files in the learnings corpus** (security seat, pre-existing, `walkDir` follows symlinks
  at ~1583-1602, so a symlink can leak its first 10 lines to the model and N symlinks to one file can meet
  the quorum). Out of scope for a count gate and outside the brief ("anything outside scope"). Recorded as a
  deferral row in `decision-challenges.md`; `soleur:ship` renders it into the PR body and files the
  `action-required` issue from it, so it is not left invisible.
- **Dedupe sources by content hash before counting** (security seat, taste): mirrored content at N paths
  counts as N. Not adopted: the count is a floor not a relatedness check (stated in the ADR Amendment), a
  committer can already edit the rules file, and a content hash adds a second definition of "distinct" that
  must then stay equal to the handler's.
- **Variant-spelling rows in Q3** (`./x`, trailing slash, case): optional, free to add; the exact-string
  `Map` key match already drops them, so they distinct-count correctly.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails `deepen-plan` 4.6 - filled here.
- The quorum counts the `sources` set built inside `draftAdditiveEdit` from the SAME `corpusSummaries`
  Map the handler normalised against. They must stay one definition of "distinct, in-corpus": Q3 and
  H1 pin the equivalence from both sides, and a future change to either dedupe must update both.
- Census Guard 3b counts `async (): Promise<DraftOutcome> => {` openers (exactly one) and its AC6 regex
  accepts only `result.reason` or a lowercase-hyphen literal; do not add a second draft-shaped step and do
  not return an object with extra keys from the draft callback.
- `scripts/compound-promote.sh` keeps its own `>=5` prompt line on purpose (CTO F8). If a workflow ever
  starts invoking it, that is a second enforcement surface and a deferred-scope issue, not a widening of
  this PR.
- Do not add `source_count` (or any key) to `RefusalDetailEntry` or `emitOutcomeMarker`: the field-set pin
  and the Art. 30 register's categories cell are coupled to it.
- Do not edit the archived #10552 decision record or plan; closure of the deferral is recorded here.
