---
title: "Workflow FSM: collapse plan/postmerge/ship compound sub-steps, triage review→ship as a compound skip, and rule on the deferred gate"
date: 2026-09-21
slug: feat-fsm-substeps-compound-skip-triage
branch: feat-fsm-substeps-8399
issue: 8399
closes: 8399   # CONDITIONAL — only once the operator rules on dissent 1 (see "Operator Question"); otherwise the PR body says `Ref #8399`
type: feat
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# Workflow FSM: collapse the remaining designed compound sub-steps, triage review→ship, rule on the gate

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this branch.)

## Overview

Continue the workflow-FSM arc that ADR-229 records. Five items, in order:

- **A.** Add `plan: ["compound"]` and `postmerge: ["compound"]` to `DECLARED_SUB_STEPS`.
  Both skills call `compound` as a designed step of their own run. The edge set stays
  the same. This discharges dissent 2 of #8399.
- **B.** Rule on `ship → compound` (17 rows), using `ship/SKILL.md` evidence alone and not
  symmetry with A. **Ruling: declare `ship: ["compound"]` as a sub-step.** Ship's Phase 2
  runs `compound` as a designed step (see B below).
- **C.** Triage `review → ship` (51 rows) as a possible compound skip. Measure it, and do
  **not** declare the edge.
- **D.** Decide the gate question that ADR-229 deferred. **Ruling: no gate.** The ruling
  is recorded in ADR-229, and a tracking issue covers the backstop weakness that C found.
- **E.** Close out #8399. Dissent 2 is discharged by A. Dissent 1 is an **operator
  question** that the lead surfaces. This plan does not decide it.

`ship → plan` and `postmerge → plan` stay undeclared. ADR-229 already rules them to be
genuine starts of a second feature.

## Research Reconciliation — Brief vs. Codebase

| Brief / research claim | Reality (measured 2026-09-21) | Plan response |
|---|---|---|
| A: "expected ~55 rows collapse (plan→compound 30, postmerge→compound 13, following compound→work 12)" | Live: plan→compound **31**, postmerge→compound **14**, compound→work **13**. That is 58 rows collapsed, plus one each of compound→plan, compound→postmerge and compound→review. The collapse also **exposes** 9 rows that were hidden behind the declared `compound → ship` edge: plan→ship +3 (7→10), postmerge→ship +3 (2→5), and +1 each for postmerge→plan, postmerge→review and postmerge→postmerge. Net: **undeclared −52, pairs −45, substep +45** | Re-baseline ADR-229 with the measured **deltas**, and name the exposure explicitly (see Research Insights §Exposure) |
| Brief: "live classifier on main: undeclared=387 … pairs=4969 substep=130 read=10641" | At planning time: `undeclared=389 sessions=1276 pairs=4971 nonnode=4104 substep=130 read=10650 dropped=0`. The log is append-only and moves | Absolute numbers are snapshots. ADR text quotes deltas only, as ADR-229 already instructs |
| Repo-research agent: "no existing classifier test case changes verdict" | **Wrong.** Case 14 (`scripts/classify-workflow-transitions.test.sh`, "pairs follow TIMESTAMP order") uses `ship` then `compound` and asserts the row `ship -> compound`. Under B, that pair collapses and the case goes red | **Keep case 14's `ship`/`compound` input and flip its assertion** to `pairs=0 substep=1` (advisor consult, Step 4.5). A re-fixture would hide the behavior change B makes. The flipped case still pins timestamp order. Sorted (ship@15:01, compound@15:09), compound collapses under ship: `pairs=0 substep=1`. Unsorted file order (compound, ship) would pair the declared `compound -> ship`: `pairs=1 substep=0` |
| Repo-research agent: "DECLARED_SUB_STEPS is NOT exported" | It **is** exported (`export const`), and `workflow-fidelity.test.ts` imports it | No effect on the plan. Recorded so no one repeats the claim |
| ADR-229 Verification: "`classify-workflow-transitions.test.sh` — 28 assertions" | The suite floor is `MIN_CASES=32`. The ADR line is stale | Update it to the new floor in the same ADR edit |
| Brief (dissent 1): "current reading post=7 median_k=73" | Re-read 2026-09-21 with `bash scripts/measure-plan-sharp-edges-turns.sh`: `post=10 median_k=55 p10_k=31` | The dissent rule (post ≥ 5) and the shipped rule (median ≥ 2× the ~8-turn break-even) **still agree** on "kept". The operator question stands |

## Research Insights

### Premise Validation (Phase 0.6)

- #8399 is OPEN, labelled `decision-challenge`, `meta/machinery`, `type/question`. Its
  two dissents are exactly the ones the brief quotes. The archived spec it cites
  (`specs/feat-one-shot-8325-fsm-decision-challenges/`) now lives under `specs/archive/`.
- PR #8459 is an OPEN draft on this branch. Commit `b1a41c34f` (compound learning, plus 2 lines
  each in `review/SKILL.md` and `work/SKILL.md`) is kept. Sizes against the ratchet ceilings:
  review 462403/477000, work 349694/362000.
- Cited symbols exist on this branch: `DECLARED_SUB_STEPS` (`plugins/soleur/lib/workflow-fidelity.ts`,
  the const whose doc comment ends "To add an entry: …"), and `sub_steps` in `.claude/workflow-transitions.json`.
  The classifier's `$SUB[.kept[-1].skill]` collapse is in `scripts/classify-workflow-transitions.sh`
  (the reduce after `map(sort_by(.t))`).
- The designed compound calls cited by A:
  - `plan/SKILL.md` §Exit Gate step 1: "Run `skill: soleur:compound` to capture learnings from the planning session". It is skipped under a RETURN CONTRACT, which is why only direct `plan` runs produce the row.
  - `postmerge/SKILL.md`, the closing step before `## Phase 7: Report`: "Run compound to capture any learnings from the merge: `skill: soleur:compound`".
- Mechanism vs. the ADR corpus: a blocking or record-mode `PreToolUse(Skill)` gate appears in
  ADR-229's Alternatives table as **rejected**. It is rejected under ADR-070, because Skill does
  not re-fetch, and because its output would dead-end in `non_corpus_counts`. D's ruling agrees
  with that record and adds measured grounds.
- The C4 model was read (`model.c4`, `views.c4`, `spec.c4`). No element models the offline
  classifier, the invocation log or the FSM view. The `compound skill` component and
  `oneshot -> compound "Step 4"` are unaffected. `plugins/soleur/test/c4-count-parity.test.sh`
  was run: `ALL TESTS PASSED`, Failed: 0.

### Property List (Phase 0.6b)

1. P1 — A session that runs a node's own designed `compound` step (plan exit gate, postmerge closing step, ship Phase 2) pairs as the enclosing lifecycle transition, not as two undeclared rows.
2. P2 — The collapse never launders a skip. Any transition that crosses a collapsed `compound` must still be reported when it is undeclared (for example plan→ship, postmerge→ship, review→compound→plan).
3. P3 — The TS const, the JSON view and the pinned set agree. A drift in either direction fails the required `grok-fidelity` check.
4. P4 — The `review → ship` class is characterised, so the gate decision rests on a measurement and not on a count.
5. P5 — ADR-229 states the gate ruling and the re-baselined deltas, including a decision not to gate.
6. P6 — #8399's dissents are each either discharged or put in front of the operator.
7. P7 — Each sub-step entry stays true to its SKILL.md. The entry is valid only while the key's SKILL.md still calls `skill: soleur:compound`.
8. P8 — The deferred backstop fix (D.2) is tracked with a concrete fix path (`wg-when-deferring-a-capability-create-a`).

### Cut List (Phase 0.6b)

- A `--sessions`/context flag on the classifier to make C's triage a built-in mode → P4 → covered by a one-off read-only jq/awk procedure. That procedure is recorded in the Appendix and cited from the ADR. The gate ruling is "no gate", and its re-open trigger is tied to the D.2 issue closing plus a re-run of the Appendix procedure, so no new mode is needed.
- A `PreToolUse(Skill ship)` gate (record-mode or blocking) → P4/P5 → rejected in ADR-229 Alternatives. It would also **false-deny the designed path**, where compound runs *inside* ship (see D).
- Tightening ship Phase 2's learning probe in this PR → it would buy "a skipped compound is caught in-process" → **deferred to a tracking issue**, not cut. `ship/SKILL.md` is at its byte ceiling (273970/274000), and the correct predicate still needs design (see D.2).
- Per-parent substep counts, or a containment window on the collapse (advisor, Step 4.5) → would preserve the in-ship vs after-ship compound split inside the classifier → covered.
  - The C triage and its Appendix procedure read the raw sequences independently of the classifier's view, so the split stays measurable.
  - A compound after ship precedes no skip either way: it can only precede a node that ship already declares, or an undeclared one that is still reported.
  - The log carries no parent or tool-use id to bound a window with.
  - A new `--summary` key would change the null-line contract that case 27 pins.
- A new bash suite → not needed. The existing `scripts/classify-workflow-transitions.test.sh` (registered in `scripts/test-all.sh` as `run_suite "scripts/classify-workflow-transitions"`) takes the new cases, so the registered-suite count delta is **0**.

### Value-proposition measurement (0.6c)

Not applicable. This plan claims no cost or performance saving.

### Measurement procedure (read-only; reproducible)

The invocation log is `/data/git-repositories/jikig-ai/soleur/.claude/.skill-invocations.jsonl`.
It lives only in the main checkout, and there are no rotated `.gz` archives at planning time.
Variant views were measured without writing to the log or to any tracked file. The method uses a
scratch root that holds a **symlink** to the log (no copy) and a modified copy of the view, read
through the classifier's own `CLASSIFY_REPO_ROOT` narrowing:

```bash
S=<scratchpad>/fsm; LOG=/data/git-repositories/jikig-ai/soleur/.claude/.skill-invocations.jsonl
for v in base A AS; do mkdir -p $S/$v/.claude; ln -sf $LOG $S/$v/.claude/.skill-invocations.jsonl; done
# (also: ln -sf each $(dirname $LOG)/.skill-invocations-*.jsonl.gz into each variant, if any exist)
jq . .claude/workflow-transitions.json > $S/base/.claude/workflow-transitions.json
jq '.sub_steps += {plan:["compound"], postmerge:["compound"]}' .claude/workflow-transitions.json > $S/A/.claude/workflow-transitions.json
jq '.sub_steps += {plan:["compound"], postmerge:["compound"], ship:["compound"]}' .claude/workflow-transitions.json > $S/AS/.claude/workflow-transitions.json
for v in base A AS; do CLASSIFY_REPO_ROOT=$S/$v bash scripts/classify-workflow-transitions.sh --summary; done
for v in base A AS; do CLASSIFY_REPO_ROOT=$S/$v bash scripts/classify-workflow-transitions.sh | awk -F'\t' '{print $2}' | sort | uniq -c | sort -rn > $S/$v.edges; done
```

Readings (2026-09-21):

| View | undeclared | sessions | pairs | substep |
|---|---|---|---|---|
| base (brainstorm only) | 389 | 1276 | 4971 | 130 |
| A (+plan, +postmerge) | 337 | 1275 | 4926 | 175 |
| A+B (+ship) | 316 | 1271 | 4909 | 192 |

Deltas: **A** −52 / −45 pairs / +45 substep. **B** −21 / −17 / +17. **Combined** −73 / −62 / +62.
Pairs fall by exactly the substep increase, which is the same identity ADR-229's #8325 re-baseline
used.

### Exposure (why the collapse surfaces, not hides)

`compound → ship` is a **declared** edge. So before this change, any `X compound ship`
sequence was reported only as `X → compound`, which reads as benign, and the second half passed
as declared. The collapse turns that into `X → ship`:

- **plan→ship +3.** Examples: `one-shot plan deepen-plan qa compound ship` and `one-shot plan plan deepen-plan code-review compound ship`. These are review-skips that were hidden behind a benign-looking `plan → compound`.
- **postmerge→ship +3.** Examples: `postmerge compound ship` inside the 2026-09-18 sessions. This is a second ship after post-merge verification with no `work` in between.

A therefore makes the ship-skip class **more** visible.

- **When a collapse can mark a pair declared.** `K compound X` becomes `K → X`, which is
  declared only when X is one of K's own declared successors:
  - `brainstorm → plan`. `one-shot` is not a node: it is filtered out before the collapse runs.
  - `plan → work`
  - `postmerge → work`
  - `ship → postmerge` / `work`
- **Why that hides no skip.** Each of those is K's designed continuation, and none of them is
  `ship`. So no collapse can turn a review-skip into a declared pair.
- **The entry that would hide one is already forbidden.** The invariant "a sub_steps value is not
  a declared successor of its key" rules out `review: ["compound"]`. That entry would hide a
  pair: `review compound work` would become `review → work`, which is declared.

### B — ruling on `ship → compound` (from ship/SKILL.md, not symmetry)

- **Evidence that compound is a designed ship step:**
  - `ship/SKILL.md` §Headless Mode Detection says "Phase 2: auto-invoke `skill: soleur:compound --headless`".
  - §Phase 2 (Capture Learnings) says "Then use `skill: soleur:compound` … The compound flow will automatically consolidate and archive the artifacts", and "Auto-invoke `skill: soleur:compound --headless` without prompting".
  - `one-shot/SKILL.md` step 7 says "Ship handles compound re-check (Phase 2)".
- **Log shape (17/17 rows):** compound is always the record **immediately after** ship. That matches a nested call, because ship is logged when invoked and compound is logged when ship's Phase 2 calls it.
  - Successors of that compound: session end 11, `postmerge` 4, `plan` 1, `brainstorm` 1.
  - After the collapse these become `ship → postmerge` (declared), `ship → plan` and `ship → brainstorm` (still undeclared, unchanged in kind).
- **Ruling: declare `ship: ["compound"]`.**
  - Entry rules hold: both are nodes, and `compound ∉ DECLARED_TRANSITIONS.ship = [postmerge, work]`.
  - Nothing is laundered: `compound`'s only declared successor is `ship`, so `ship compound ship` becomes the undeclared self-loop `ship → ship`, which is still reported.

### C — `review → ship` triage (51 rows, 49 sessions)

Each row was classified on the node sequence after the collapse, by what the log records around it
(procedure in the Appendix):

| Class | Rows | Reading |
|---|---|---|
| Compound ran **inside ship** (next node after ship is `compound`, i.e. ship Phase 2) | 5 | Not a skip. This is the designed backstop |
| **Re-entry**: a feature `compound` ran earlier in the same session (second ship pass after `ship→review` / `postmerge→review`) | 4 | Not a skip |
| Compound ran **later** in the session (after a review re-entry) | 4 | Late, not skipped |
| **No compound anywhere after review in the session** | 38 | Skip at the log level. 19 of these rows show `preflight`, so ship provably ran past Phase 2 without invoking compound. The other 19 have no `preflight` record, so ship was not observed past Phase 2 in-session |

- Of the 38, 18 come from sessions with no `plan`/`work` before `review`. These are sessions that started mid-pipeline.
- **Under-recording hypothesis ("a parent orchestrator owned compound and the log misses it"): falsified for Claude Code.**
  - This planning run is a Task subagent under a `one-shot`. Its own `soleur:plan` Skill call is logged under the **parent's** `session_id` (`one-shot` at 07:00:09Z and `plan` at 07:00:54Z carry the same id).
  - So subagent Skill calls are recorded, and a compound run by one-shot step 6 or by ship Phase 2 would appear.
  - The log cannot see compound work done in a **different** session (after `/clear`) or under a harness that Reads SKILL.md instead of calling Skill. The records carry no branch, so those rows cannot be joined to a PR.
- **Rate is low and not rising.**
  - Share of review exits taken as review→ship (vs review→compound): May 6.6% (22/334), Jun 3.0% (8/264), Jul 6.2% (14/227), Aug 3.6% (3/84), Sep month-to-date 3.4% (4/117).
  - Aug+Sep together: 7 rows in ~7 weeks, of which 1 is ship-Phase-2 and 1 is re-entry.
- **Backstop finding (C → D.2).**
  - Ship Phase 2's first probe is `git log --oneline --since="1 week ago" -- knowledge-base/project/learnings/`. It is feature-agnostic.
  - On `origin/main` it was non-empty in **12 of 12** sampled weeks (2026-05-18 → 2026-09-21, minimum 6 learning commits per week). So in this repo it always reports "a recent learning exists".
  - Read literally, that skips the feature-scoped unarchived-artifact check that sits under "If no recent learning exists". This matches the 19 rows where ship passed Phase 2 without calling compound.
  - The log cannot prove that link, because it has no branch field.

### D — gate ruling

**No gate.** The reasons, strongest first:

1. **The invariant a gate would enforce is wrong.** "Compound before ship" is not the design, because ship Phase 2 runs compound *inside* ship. A `PreToolUse(Skill ship)` gate would deny the 5 designed rows in C and all 17 `ship → compound` rows. The only place that can enforce "compound ran before the PR is created" is inside ship, and ship already does it (Phase 2).
2. **ADR-229 Alternatives already rejects both gate shapes.** Record-mode output dead-ends in `non_corpus_counts`, and blocking is barred by ADR-070 because Skill does not re-fetch. The measurement adds no reason to reverse either.
3. **Volume and consequence.** About one row a week recently. A skipped compound costs an uncaptured learning and possibly an unarchived spec (ship §"compound is the last point at which archival can happen"). Both can be recovered with a follow-up PR, and neither is user-facing.

**D.2 — the backstop is weak, and that is tracked, not gated.**

- Ship Phase 2's probe should be scoped to the branch, e.g. `git log --oneline origin/main..HEAD -- knowledge-base/project/learnings/`.
- It must also count a learning that exists but is not yet committed, or it will re-run compound after a compound that captured something and has not committed yet.
- `ship/SKILL.md` has 30 bytes of headroom. The fix needs that design first, so it is filed as a tracking issue (work task 0.1) and not edited here.
- The ceiling is **not** the blocker (CTO review). `plugins/soleur/skills/ship/references/` exists. The fix path, which the issue body names, is:
  - extract Phase 2's probe logic to a reference file, which frees bytes;
  - replace the repo-wide probe with a branch-scoped one that also sees uncommitted learnings;
  - prove it with a fixture test.
- Priority is **p2-medium**, not p3: the measurement is strong and the fix path is concrete.

**Re-open trigger, recorded in ADR-229.** When the D.2 issue closes, re-run the Appendix triage on the rows logged
after the fix merged. If class-D rows still appear (a full pipeline with no compound anywhere after review, including
inside ship), the gate question re-opens on that evidence. The trigger is owned by D.2's closure, not by a
number nobody computes. An earlier draft said "+≥16 rows per 8 weeks", but the classifier's rows carry no timestamp
and the log rotates, so that count could not be computed (CTO + DHH review).

### E — dissents

- **Dissent 2** (sub_steps is generic, and plan/postmerge entries are visible in the data): **discharged by A**. The ADR-229 sentence "`plan → compound` and `postmerge → compound` (11) have the same shape and were not added … recorded as a User-Challenge" is rewritten to record the resolution (#8399).
- **Dissent 1** (the §3 decision rule fires on a median with no floor on n): **operator question, not decided here**. See the next section.

### Operator Question (to surface — NOT decided by this plan)

> **#8399 dissent 1 — should ADR-229's "kept on measured evidence" rule for the
> plan-sharp-edges extraction require a floor of `post >= 5` completed runs?**
>
> - **Today they agree.** At planning time `measure-plan-sharp-edges-turns.sh` reads
>   `post=10 median_k=55 p10_k=31`, and the brief's earlier reading was post=7 median_k=73.
>   The shipped rule and the dissent's floor both say "kept", so the choice changes no verdict now.
> - **What it changes.** It only decides what a future reading below n=5 may say. The corpus
>   is a 3-day rolling window, and the brief's n=2 reading happened on the same day as n=7.
> - **(a) Adopt the floor.** ADR-229's extraction-economics paragraph gains one sentence: "The
>   keep decision is re-stated only at `post >= 5`. Below that, a re-reading records 'measured,
>   inconclusive at n=<N>' and does not restate 'kept on measured evidence'."
> - **(b) Decline the floor.** ADR-229 records that the rule stands as ruled, with the reason
>   the operator gives, and cites #8399.
> - Either answer closes #8399 (`Closes #8399` in the PR body). With no answer, the PR says
>   `Ref #8399` and the issue stays open, carrying only dissent 1.

### Relevant files

- `plugins/soleur/lib/workflow-fidelity.ts`: the `DECLARED_SUB_STEPS` const and its doc comment ("To add an entry …").
- `.claude/workflow-transitions.json`: the `sub_steps` mirror and `_comment`.
- `plugins/soleur/test/workflow-fidelity.test.ts`: the `describe("declared-transitions derived view parity")` block and `describe("DECLARED_SUB_STEPS invariants")` → `test("DECLARED_SUB_STEPS is exactly the reviewed set")`.
- `scripts/classify-workflow-transitions.test.sh`: case 14, case 20's comment, the `MIN_CASES=32` floor, and the `new_root`/`emit_to` helpers used for new cases.
- `knowledge-base/engineering/architecture/decisions/ADR-229-workflow-fsm-single-source-and-offline-classification.md`.

### Institutional learnings applied

- `2026-09-19-adding-a-check-for-the-new-key-showed-me-the-old-one-had-none.md`: a sibling sweep is done when the **case lists** match, not the guards. The new sub-step cases cover all three keys with the same shape (collapse, exposure), not just one.
- `2026-09-18-every-p1-lived-in-a-guard-i-added-…md`: run the full `scripts/test-all.sh` before the first push. A file-selected run cannot see repo-global ratchets.
- ADR-229's own rule: quote **deltas**, not absolutes. The log rotates under other sessions.
- `2026-09-20-the-ops-only-green-verdict-claimed-a-fact-the-gate-never-measured.md`: every number in the ADR edit names the command that produced it.

### Conventions (AGENTS / constraints carried from the brief)

- TS const first, then the JSON mirror, then the parity pin.
- No instrumentation in `plugins/` (ADR-179 d4). The only `plugins/` edit is the data const, its comment and its test.
- `rule-metrics.json` gains no `command_snippet`.
- The invocation and incident logs are only read (symlink, never copied). There are no new write sites.
- No `pgrep -f` and no `git stash`.
- `ship/SKILL.md` is not edited.
- All commits are batched before the first push, and the full `scripts/test-all.sh` runs first.

## Implementation Phases

### Phase 0 — Tracking (before code)

- 0.1 File the D.2 tracking issue with `gh issue create`.
  - Title: `ship Phase 2: the learning probe is repo-wide (--since="1 week ago") and is never empty, so it skips the feature-scoped archive check`.
  - Body:
    - the 12/12-weeks measurement;
    - the C triage table;
    - the uncommitted-learning design caveat;
    - the fix path (extract Phase 2 to `ship/references/`, add a branch-scoped probe that also sees uncommitted learnings, fixture-test it);
    - the D re-open trigger it owns.
    This issue body is where the C evidence lives. The ADR keeps only the ruling.
  - Labels: `domain/engineering`, `type/bug`, `priority/p2-medium`. Milestone: `Post-MVP / Later` unless `knowledge-base/product/roadmap.md` names a closer phase.
  - Cite the issue number in the ADR edit (Phase 3).

### Phase 1 — RED: tests first

1.1 In `plugins/soleur/test/workflow-fidelity.test.ts`:
   - Change `DECLARED_SUB_STEPS is exactly the reviewed set` to
     `toEqual({ brainstorm: ["compound"], plan: ["compound"], postmerge: ["compound"], ship: ["compound"] })`.
   - In the parity `describe`, add one test pinning the **view's** key sets by name:
     `Object.keys(view.sub_steps).sort()` equals `["brainstorm","plan","postmerge","ship"]`, and
     `Object.keys(view.transitions).sort()` equals the seven nodes. A missing mirror key then
     fails with a named message instead of a deep diff. (This is the brief's "pin both key sets in the parity block".
     The simplicity reviewer judged it redundant with deep-equal plus the exact-set pin. That is recorded as a
     User-Challenge in `decision-challenges.md`, and the brief's direction is kept.)
   - **SKILL.md anchor test (P7, CTO review).** For every key of `DECLARED_SUB_STEPS` and every value V,
     `plugins/soleur/skills/<key>/SKILL.md` contains the literal `skill: soleur:<V>`. Today the counts are
     brainstorm 1, plan 1, postmerge 1, ship 4.
     Open the test with a non-empty check so an emptied const cannot pass as zero iterations.
     If a later edit moves ship's Phase 2 call, the `ship` entry then fails loudly instead of collapsing silently.
1.2 In `scripts/classify-workflow-transitions.test.sh`:
   - **Case 14 assertion flip.** Keep the input as it is: file order `compound`@15:09, `ship`@15:01.
     Change the expected result from the row `ship -> compound` to `--summary` containing `pairs=0 `
     and `substep=1 `, with no row. Assert it the way cases 17 and 19 do (Kieran review):
     - take `--summary` for the `pairs=0 ` and `substep=1 ` substrings;
     - capture rows with `2>/dev/null`;
     - assert the `formed ZERO lifecycle pairs` WARNING on the `2>&1` capture.
     A bare `-z` check on the old `2>&1` capture would stay red forever, because the WARNING is in it.
     Rewrite the comment to cite ADR-229 (#8399 amendment). Say why the case still pins ts order:
     unsorted file order would pair the declared `compound -> ship` and give `pairs=1 substep=0`.
   - **Case 20 comment.** Change "keyed on brainstorm" to "keyed on the declared keys, never on
     `review`". The fixture is unchanged.
   - **New cases 33–37** (`new_root` + `emit_to`, real view copied).
     Write 33–35 as ONE loop over `K:X` in `plan:work postmerge:work ship:postmerge`, one `pass`/`fail` per key
     (DHH review):
     - 33 `plan compound work` → `undeclared=0 pairs=1 substep=1`, no row (plan's exit gate).
     - 34 `postmerge compound work` → `undeclared=0 pairs=1 substep=1`, no row (postmerge's closing step).
     - 35 `ship compound postmerge` → `undeclared=0 pairs=1 substep=1`, no row (ship Phase 2).
     - 36 `plan compound ship` → row `plan -> ship`, with `substep=1 undeclared=1`. This is the exposure: before the change the only row was `plan -> compound`.
     - 37 `postmerge compound ship` → row `postmerge -> ship`, with `substep=1 undeclared=1`.
   - Raise `MIN_CASES=32` to `MIN_CASES=37`, keeping the literal `SELFTEST_PASSES=1` contiguous
     (the guard-vacuity-floor shape).
1.3 Run both suites. **Expected RED:** the toEqual pin, the view key-set pin, and cases 33, 34, 35 and 36/37.
   The SKILL.md anchor test is GREEN from the start: the anchors already exist. Its RED is shown by its mutation row.
   Cases 36/37 are red because, without the collapse, the rows read `plan -> compound` / `postmerge -> compound`.
   Case 14 (flipped) is RED before Phase 2, because today it reports `ship -> compound`, and GREEN after.

### Phase 2 — GREEN: const, then mirror

2.1 `plugins/soleur/lib/workflow-fidelity.ts`:
   - Set `DECLARED_SUB_STEPS` to the four entries.
   - Rewrite the doc comment so it names each entry's SKILL.md anchor: brainstorm handoff,
     `plan/SKILL.md` §Exit Gate step 1, `postmerge/SKILL.md` closing step before Phase 7,
     `ship/SKILL.md` §Phase 2 (Capture Learnings).
   - Name the one entry the rules forbid and why: `review` → `compound` is a declared successor.
   - Keep the "To add an entry" paragraph verbatim.
2.2 `.claude/workflow-transitions.json`: mirror `sub_steps` exactly in key order, with the same
   2-space `jq`-style formatting. Change the `_comment` only if it names brainstorm specifically
   (it does not today).
2.3 Run `bun test plugins/soleur/test/workflow-fidelity.test.ts` and `bash scripts/classify-workflow-transitions.test.sh`. Both must be green.

### Phase 3 — ADR-229 amendment (Architecture Decision deliverable)

Measure the deltas on a **frozen snapshot**, not on the live log. Other sessions append to the live log, so two
live readings can differ for reasons outside this diff (`cq-ac-must-not-depend-on-concurrent-sessions`).

- `head -n "$(wc -l < $LOG)" $LOG > $S/snap/.claude/.skill-invocations.jsonl`, with `umask 077` in the session
  scratchpad.
- Run the base view and the new view against that one file, using `CLASSIFY_REPO_ROOT`.
- Delete the snapshot afterwards. It is a transient local read, with no egress and no tracked write.

Quote the **deltas**. These edits go in ADR-229:

- **Decision 1 amendment note:** `sub_steps` now carries `brainstorm`, `plan`, `postmerge`,
  `ship` (#8399). The view still has one consumer.
- **Consequences, the "reading needs interpretation" bullet.** Replace "`plan → compound` and
  `postmerge → compound` (11) … were not added … User-Challenge" with the resolution: A (#8399,
  dissent 2 discharged) and B (the ship Phase 2 evidence above), without restating symmetry as a
  reason.
- **New re-baseline bullet (2026-09-21, #8399):**
  - Before/after `--summary` lines.
  - Deltas: A −52/−45/+45, B −21/−17/+17, or as re-measured.
  - The **exposure**: plan→ship +3, postmerge→ship +3, previously hidden behind the declared `compound → ship`.
  - `ship → plan` and `postmerge → plan` shift by +1 each through the collapse and stay undeclared by ruling.
  - Update the older bullet's "`plan → ship` (7) … unchanged" wording to point at the new reading.
- **Replace the deferred-gate bullet** ("A gate remains buildable … deferred to the measurement
  this ADR makes possible, not to a date") with the **D ruling**:
  - kept to about 10 lines (DHH review): the ruling, reasons 1–3 in one sentence each, one line of C numbers
    (51 rows: 5 inside ship, 4 re-entry, 4 late, 38 with no compound in-session), the falsified
    under-recording hypothesis in one sentence, the D.2 issue number, and the re-open trigger.
  - The full triage table lives in the D.2 issue body.
  - Put reason 1 ("false-denies ship's in-process Phase 2 compound") on the EXISTING Alternatives rows for the
    record-mode and blocking gate. Do not add a new row (simplicity review).
  Keep the first clause ("buildable on top of this without rework"), since it is still true.
- **Verification:** the classifier suite count goes to the new floor (37). Add the
  view-key-set test and the SKILL.md anchor test to the `workflow-fidelity.test.ts` list.
- **Dissent 1:** apply edit (a) or (b) from "Operator Question" **only after the operator answers**.
  With no answer, make no edit here.

### Phase 4 — Verify and batch

- 4.1 Run `bun test plugins/soleur/test/workflow-fidelity.test.ts`, the classifier suite, `bash scripts/lint-skill-body-budget.test.sh` and `python3 scripts/lint-guard-contract.py` on this plan.
- 4.2 Run the full `bash scripts/test-all.sh` **before the first push**. The registered-suite count is unchanged (delta 0).
- 4.3 Confirm `git diff --stat origin/main...HEAD` touches **no** `plugins/soleur/skills/*/SKILL.md` beyond the two files commit `b1a41c34f` already carries.
- 4.4 Batch every commit locally. Push once. The PR body carries `Closes #8399` or `Ref #8399`, per the operator's answer.

## Files to Edit

- `plugins/soleur/lib/workflow-fidelity.ts`: the `DECLARED_SUB_STEPS` value and its doc comment.
- `.claude/workflow-transitions.json`: the `sub_steps` mirror.
- `plugins/soleur/test/workflow-fidelity.test.ts`: the exact-set pin, plus the view key-set pin in the parity block.
- `scripts/classify-workflow-transitions.test.sh`: flip case 14's assertion, edit case 20's comment, add cases 33–37, set `MIN_CASES=37`.
- `knowledge-base/engineering/architecture/decisions/ADR-229-workflow-fsm-single-source-and-offline-classification.md`: the Phase 3 edits.

## Files to Create

None. The D.2 tracking issue is a GitHub issue, not a file.

## Open Code-Review Overlap

None. Checked on 2026-09-21: `gh issue list --label code-review --state open` (200 max) was matched against every path above, and against `ADR-229`, `workflow-fidelity` and `classify-workflow-transitions`. There were 0 matches.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-229**, the existing record, per Phase 3. This is not a new ADR, so no ordinal
collision is possible. The amendment extends Decision 1 (the sub-step set) and resolves the
Consequences bullet that deferred the gate.

### C4 views

**No C4 impact.** All three model files were read (`model.c4`, `views.c4`, `spec.c4`).

- External human actors: none added. The classifier is run locally and is not modeled.
- External systems: none. No vendor or network path is involved. The classifier reads a local gitignored file.
- Containers/stores: none added. `.claude/.skill-invocations.jsonl` is repo-tooling telemetry and is not a modeled store.
- Access relationships: unchanged.
- The `platform.plugin.compound` component and the `oneshot -> compound "Step 4"` edge still describe the system correctly after this change.
- Cardinalities: `bash plugins/soleur/test/c4-count-parity.test.sh` returned `ALL TESTS PASSED` (Failed: 0) on 2026-09-21.

### Sequencing

None. The ruling is true the moment this PR merges.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Declare `plan → compound`, `postmerge → compound`, `compound → work` as edges | This would make `review → compound → work`-style paths and `compound → plan` legal. ADR-229 already chose the sub-step collapse over edges for exactly this reason |
| Decide B by symmetry with A | The brief forbids it. B is ruled on ship/SKILL.md Phase 2 and on the 17/17 nested-log shape |
| Declare `review → ship` | The brief forbids it. It is the compound-skip class this instrument exists to surface |
| Gate `Skill(ship)` on a preceding compound | False-denies ship's own Phase 2 compound, and is barred by ADR-070 and ADR-229 Alternatives |
| Fix ship Phase 2's probe in this PR | `ship/SKILL.md` has 30 bytes of headroom, and the branch-scoped probe must also see uncommitted learnings or it re-runs compound. Deferred to the D.2 tracking issue |
| Add a `--sessions` classifier mode for the triage | YAGNI. The ruling is "no gate", and its trigger uses the existing default output |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The change is confined to repo-local tooling: an offline classifier over a gitignored log, a TS data const that no plugin runtime path reads (ADR-229: "No plugin runtime code calls `declaredTransitions()`"), and an ADR. The worst case is a wrong count in the operator's own `--summary` reading, and the parity block (the required `grok-fidelity` check) plus the classifier suite red on that.
- **If this leaks, the user's data / workflow / money is exposed via:** no vector. There are no new write sites and no egress. The invocation log is read through a symlink and never copied or published. The ADR quotes aggregate counts only, never session ids.
- **Brand-survival threshold:** `none`

## Observability

```yaml
liveness_signal:
  what: "the classifier's --summary line; substep= rises by the collapsed count and the null-reading marker fires on an absent log"
  cadence: "per local run (offline by design, ADR-229 decision 3)"
  alert_target: "the terminal running it; the rc 2 FATAL lines on a stale or truncated view"
  configured_in: "scripts/classify-workflow-transitions.sh"
error_reporting:
  destination: "stderr of scripts/classify-workflow-transitions.sh (repo tooling, no Sentry surface — it never runs in production)"
  fail_loud: "FATAL: declared view … carries no `sub_steps` map … (rc 2); SOLEUR_WORKFLOW_TRANSITIONS_NO_INVOCATIONS … NULL reading"
failure_modes:
  - mode: "view mirror drifts from DECLARED_SUB_STEPS"
    detection: "workflow-fidelity.test.ts parity deep-equal + view key-set pin, in the required grok-fidelity check"
    alert_route: "red required PR check"
  - mode: "a collapse launders a skip"
    detection: "classifier cases 18, 20, 36, 37 (exposure rows asserted)"
    alert_route: "red scripts/classify-workflow-transitions suite in test-all / CI"
logs:
  where: "/data/git-repositories/jikig-ai/soleur/.claude/.skill-invocations.jsonl (gitignored, producer .claude/hooks/skill-invocation-logger.sh)"
  retention: "rotated by log-rotation.sh into .skill-invocations-<ts>.jsonl.gz, which the classifier reads"
discoverability_test:
  command: "bash scripts/classify-workflow-transitions.sh --summary"
  expected_output: "substep="
```

## Guard Contract

### Guard 1 — sub-step set pin (const ↔ view ↔ reviewed set)

**Property.** Every sub-step entry the classifier collapses is exactly one reviewed in
`workflow-fidelity.test.ts`, and the view it reads names no other.

**Assembly.** There is one chokepoint for the classifier: the view's `sub_steps`, read as `$SUB`
in `scripts/classify-workflow-transitions.sh`. It is fed only by a hand mirror of
`DECLARED_SUB_STEPS`. The guard therefore has three members that must agree:
- the TS const, pinned by `toEqual`;
- the view, pinned by the parity deep-equal, the new key-set test, and "names no sub-step absent from the const";
- the entry rules, in the three invariant tests.
- the SKILL.md anchor test, which ties each entry to the literal `skill: soleur:<value>` in its key's SKILL.md (P7).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `ship` from the view's `sub_steps` only | RED (deep-equal + view key-set pin) |
| 2 | Add `review: ["compound"]` to both const and view | RED (exact-set pin; the invariant "value is not a declared successor of its key") |
| 3 | Add a **second** rule-legal entry after the compliant ones, e.g. `work: ["brainstorm"]` in both | RED (exact-set pin, the only test that says *which* entries exist) |
| 4 | Guard dispatch: empty both const and view to `{}` | RED (exact-set pin; the non-empty preconditions in the invariant tests) |
| 5 | Harness row: `new_root` copies a hard-coded view instead of the repo view | RED (cases 33–35 go red against a view lacking the entries) |
| 6 | Delete the `skill: soleur:compound` call from `ship/SKILL.md` Phase 2, and edit nothing else | RED (SKILL.md anchor test). Before this PR, no test failed |
| 7 | Must-PASS non-canonical: the view has the same entries in a different **key order** | PASS for the const-side pins, since `toEqual` is key-order-insensitive. Byte order is a mirror convention, not the property |

### Guard 2 — collapse does not launder (classifier cases 33–37 + 14/18/20)

**Property.** For every declared sub-step key K, `K compound X` pairs as `K → X`, and that pair is
reported whenever `K → X` is undeclared.

**Assembly.** The single reduce in the classifier's jq (`$SUB[.kept[-1].skill]`), per session,
after the node filter. The cases quantify over all four keys (17 brainstorm; 33, 36 plan;
34, 37 postmerge; 35 ship) and over the non-key predecessor `review` (20).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | The reduce keys on the **raw** previous record instead of the previous kept one | RED (case 21) |
| 2 | Drop `compound` unconditionally, i.e. ignore `$SUB` | RED (case 20: `review compound plan` must keep `compound -> plan`) |
| 3 | Mirror only `plan` and `postmerge`, forgetting the second-added `ship` | RED (case 35) |
| 4 | Guard dispatch: the view's `sub_steps` loses `plan` while the const keeps it | RED (case 36 now reads `plan -> compound`, not `plan -> ship`; case 33 reports a row. The parity deep-equal also goes red) |
| 5 | Harness row: delete case 37 without lowering the floor | RED (`MIN_CASES=37` anti-vacuity floor) |

## Acceptance Criteria

- [ ] AC1 `DECLARED_SUB_STEPS` deep-equals `{ brainstorm: ["compound"], plan: ["compound"], postmerge: ["compound"], ship: ["compound"] }`, and `DECLARED_TRANSITIONS` is byte-identical to `origin/main`. Check: `bun -e` deep-equal of `DECLARED_TRANSITIONS` imported from the working tree against the one parsed from `git show origin/main:plugins/soleur/lib/workflow-fidelity.ts`. The existing per-edge `toEqual` pins in `workflow-fidelity.test.ts` stay unchanged and green, and they are the mechanical check.
- [ ] AC2 `.claude/workflow-transitions.json` `.sub_steps` equals the const. Check: `jq -c '.sub_steps' .claude/workflow-transitions.json` prints `{"brainstorm":["compound"],"plan":["compound"],"postmerge":["compound"],"ship":["compound"]}`. `.transitions` is unchanged.
- [ ] AC3 `bun test plugins/soleur/test/workflow-fidelity.test.ts` is green. It includes the updated exact-set pin, a new test that pins the view's `sub_steps` and `transitions` key sets by name, and the SKILL.md anchor test over every `DECLARED_SUB_STEPS` entry.
- [ ] AC4 `bash scripts/classify-workflow-transitions.test.sh` is green, with `MIN_CASES=37`. Cases 33–37 exist as specified. Case 14 keeps its `ship`/`compound` input and asserts `pairs=0 substep=1`, with no row.
- [ ] AC5 On ONE frozen snapshot of the log (Phase 3), the base view and the new view give the same `read` and `dropped`. `pairs` falls by exactly the amount `substep` rises. The ADR quotes those snapshot deltas and labels them a snapshot. This is deterministic, because no concurrent session can move a frozen file.
- [ ] AC6 ADR-229 carries:
  - the 2026-09-21 re-baseline with deltas and the exposure note;
  - the resolved dissent-2 sentence;
  - the D ruling ("no gate"), with the C triage, the falsified under-recording hypothesis, the re-open trigger (owned by the D.2 issue's closure) and the D.2 issue number;
  - a new Alternatives row;
  - the corrected Verification count.
  Check: `grep -ci 'no gate' ADR-229-*.md` ≥ 1, and `grep -c '#<D.2 issue number>' ADR-229-*.md` ≥ 1.
  These are presence assertions only. An absence-grep on the old deferral sentence would false-fail if the amendment quotes it.
- [ ] AC7 No `plugins/soleur/skills/*/SKILL.md` changes beyond those in `b1a41c34f`. Check: `git diff --name-only b1a41c34f..HEAD -- plugins/soleur/skills` is empty. `ship/SKILL.md` stays at 273970 bytes.
- [ ] AC8 The D.2 tracking issue exists and ADR-229 cites it.
- [ ] AC9 The dissent-1 operator question is surfaced to the operator verbatim from "Operator Question". The ADR dissent-1 edit and `Closes #8399` are applied only if the operator answers. Otherwise the PR body uses `Ref #8399`.
- [ ] AC10 The full `bash scripts/test-all.sh` is green before the first push. The registered-suite count is unchanged.

## Test Scenarios

- Given `plan compound work` in one session, when classified, then `undeclared=0 pairs=1 substep=1` and there is no row.
- Given `postmerge compound work`, then `undeclared=0 pairs=1 substep=1`.
- Given `ship compound postmerge`, then `undeclared=0 pairs=1 substep=1`.
- Given `plan compound ship`, then the row `plan -> ship` appears with `undeclared=1 substep=1`. This is the exposure.
- Given `postmerge compound ship`, then the row `postmerge -> ship` appears.
- Given `review compound plan` (case 20), then `compound -> plan` is still reported and `substep=0`.
- Given records filed `compound`@15:09 then `ship`@15:01 (case 14), then `pairs=0 substep=1` and there is no row. Unsorted, it would have been `pairs=1 substep=0`.
- Given the view's `sub_steps` without `ship`, then `workflow-fidelity.test.ts` is red on the parity deep-equal and the key-set pin.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change: an offline repo
classifier, a data const, test cases and an ADR amendment. There is no user-facing surface, no
regulated data, no infra, and no store or connection.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one declares `none` with reasons.
- **Quote deltas, never absolutes.** Measure both views on one frozen snapshot. The live log moves under other sessions. AC5 checks the identity `Δpairs = −Δsubstep` on that snapshot.
- **Case 14 is the trap the repo-research agent missed.** Its assertion is flipped, not re-fixtured, so the behavior change stays visible. Any fixture that places `plan`, `postmerge` or `ship` directly before `compound` changes verdict after this PR. `grep -n 'compound' scripts/classify-workflow-transitions.test.sh` before assuming a case is untouched.
- **Do not edit `ship/SKILL.md` or `postmerge/SKILL.md`.** Ship has 30 bytes of headroom and postmerge has 2 (47998/48000). The D.2 fix belongs to its own issue.
- The dissent-1 answer is the operator's. Neither the planner nor the work phase decides it, and the lead asks it (hr-technical-fork-is-not-an-operator-question does not apply: this one is a policy threshold that ADR-084 explicitly left to the operator).

## Appendix — C triage procedure (read-only)

```bash
S=<scratchpad>/fsm; LOG=/data/git-repositories/jikig-ai/soleur/.claude/.skill-invocations.jsonl
cat > $S/seq.jq <<'EOF'
[inputs | fromjson?]
| map(select((.skill|type)=="string" and (.session_id|type)=="string" and .session_id!="" and (.ts|type)=="string"))
| map(.skill |= ltrimstr("soleur:"))
| group_by(.session_id) | map(sort_by(.ts))
| map({s: .[0].session_id, first: .[0].ts, all: (map(.skill)|join(" ")),
       nodes: (map(select(.skill as $k | $N | index($k) != null)) | map(.skill) | join(" "))})
| .[] | [.s, .first, "-", .nodes, .all] | @tsv
EOF
jq -n -R -r --argjson N '["brainstorm","plan","work","review","compound","ship","postmerge"]' -f $S/seq.jq < $LOG > $S/sessions.tsv
# per review->ship occurrence, after collapsing compound behind brainstorm/plan/postmerge:
#   A = next node after ship is compound (ship Phase 2)       B = a feature compound earlier in session
#   C = no plan/work before review in session                  D = full pipeline, no compound
# plus: `preflight` present in the raw sequence (ship ran past Phase 2); compound later in session.
```

(`$N` with `index` is fine here because every node name is a whole-token array member. The
substring hazard ADR-229 records applies to `index` on a **string**.)

## Review & Consult Provenance

- **Step 4.5 advisor (applied):** flip case 14's assertion instead of re-fixturing it.
- **Step 4.5 advisor (declined):** per-parent substep counts, a containment window, and a generated view. The reasons are in `decision-challenges.md`.
- **Plan review panel:** DHH, Kieran, code-simplicity and CTO (devex). Applied as Mechanical:
  - Kieran: case 14 assertion shape, the `one-shot` not-a-node correction, AC1 check.
  - Standing check and Kieran: AC5 moved to a frozen snapshot, so concurrent sessions cannot flip it.
  - CTO: SKILL.md anchor test (P7); D.2 fix path via `ship/references/` at p2.
  - CTO and DHH: the uncomputable "+≥16 per 8 weeks" trigger replaced by a trigger owned by D.2's closure.
  - DHH: cases 33–35 written as one loop; the ADR's D ruling kept compact, with evidence in the D.2 issue.
  - Simplicity: no new Alternatives row; Guard 2 row 4 made a real RED.
- **Persisted as User-Challenges or Taste** (`knowledge-base/project/specs/feat-fsm-substeps-8399/decision-challenges.md`): decide or split dissent 1 (CTO/DHH); cut the view key-set pin (simplicity); cut the gate-required sections (DHH).
