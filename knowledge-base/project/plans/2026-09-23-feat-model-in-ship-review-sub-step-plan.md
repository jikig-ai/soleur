---
title: "feat: model ship's in-ship review call as a declared sub-step (ADR-229)"
date: 2026-09-23
slug: feat-model-in-ship-review-sub-step
branch: feat-one-shot-adr229-in-ship-review-call
issue: none            # no dedicated issue; the PR (#8627) is the record
refs: 8470             # PR body says `Ref #8470` — NEVER Closes/Fixes (ADR-229 re-open trigger)
type: feat
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# feat: model ship's in-ship review call as a declared sub-step (ADR-229)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No spec directory
existed for this branch; the one-shot pipeline entered at plan.)

## Enhancement Summary

**Deepened on:** 2026-09-23, after a 4-seat plan review (DHH, Kieran, code-simplicity, and CTO
on the devex lens).

**Halt gates:** 4.6, 4.7, 4.8 and 4.11 pass. 4.9, 4.10 and 4.55 do not fire. The probe
`jq -c .sub_steps.ship .claude/workflow-transitions.json` prints `["compound"]` before the change.

**Agents:** a bounded, change-proportionate fan-out:

- `soleur:engineering:review:architecture-strategist`;
- `soleur:engineering:review:test-design-reviewer`, grade B 7.9/10, which re-ran cases 39–41
  against the real classifier with both views;
- `soleur:engineering:research:git-history-analyzer`, with 7 of 8 attribution claims confirmed.
  The eighth (#8302 vs PR #8301 as ADR-229's origin) was in the brief, not the plan;
- a verify-the-negative and self-audit sweep at the `standard` tier. All 6 negative claims were
  confirmed, and there are no stale references to cut items.

### Key improvements

1. **The `ship → ship` cost is now measured, not guessed.** All five newly exposed sessions were
   read. Two come from review's own §6 Exit Gate (`compound` then `ship`), and three go review →
   ship directly. One review starts 42 h after its ship. The nested-calls note, cut at plan
   review as "no delta", is restored.
2. **The anchor test no longer checks itself.** The set equality is asserted before the loop, the
   loop runs over `DECLARED_SUB_STEPS`, and the lower bound does not come from `ANCHORS`.
3. **Case 40 compares its row output exactly and has a RED mutation (C1).** Mutation row 1 is
   anchored, so it removes only the Phase 5.5 call.
4. **The ADR amendment follows the #8325/#8399 precedents:**
   - supersede brackets on the two 2026-09-21 sentences this change falsifies;
   - an Alternatives row for the rejected `ship → review` edge;
   - "(PR #8627)" as the citation form;
   - a "Since #8627" Verification clause;
   - the classifier's `review → ship` delta named, so no one reads 48 as progress against 51.

### New considerations discovered

- The C4 L3 block does have skill→agent and skill→store edges. The "no C4 impact" reasoning is
  corrected accordingly, and the conclusion stands.

## Overview

ADR-229 lists one designed call it does not model: `soleur:ship` can invoke `soleur:review`
from inside its own run. Neither the declared edge set nor the `sub_steps` map expresses that
call. So the offline classifier (`scripts/classify-workflow-transitions.sh`) reports
`ship review compound postmerge` as two undeclared pairs: `ship → review` and
`compound → postmerge`. Both are phantoms. That noise sits in the same invocation log the
#8470 re-measure reads (`SINCE=2026-09-23T15:40:08Z`, deadline 2026-11-04).

**Decision: declare it.** Add `review` to `DECLARED_SUB_STEPS.ship`, so the entry becomes
`ship: ["compound", "review"]`. Edit the TS const first, then the hand-mirrored view
`.claude/workflow-transitions.json`, then the parity pin and the tests. Then amend ADR-229 with
the measured deltas and the one cost the collapse cannot avoid.

We chose this over leaving the call unmodelled because the measurement settles it:

- **What changes.** One frozen copy of the real log was run through both views. Undeclared
  pairs fall **324 → 291 (−33)**. `pairs` falls by 35 and `substep` rises by 35, the same
  identity ADR-229's earlier re-baselines hold to.
- **The designed call is real.** All 29 `ship → review` rows disappear.
  - 13 of them start ≤300 s after the ship record, which is the Phase 1.5 shape.
  - 10 have ship's own `preflight` before the review, which is the Phase 5.5 shape.
  - Several are followed by `preflight`, `compound` or `postmerge`. That means ship carried on
    after the review, so the review ran inside ship.

This PR does NOT touch:

- the #8470 triage procedure (it is the re-measure's instrument and has its own inline
  collapse);
- `ship → plan` or `postmerge → plan` (undeclared by ruling);
- the content post (#8326);
- `ship/SKILL.md` (the calls already exist there).

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (verified) | Plan response |
|---|---|---|
| "ship **Phase 1.5**'s in-ship `review` call" | `ship/SKILL.md` invokes `skill: soleur:review` at **three** sites in **two** sections: Phase 1.5 (the `sequential-fallback` re-run, and the "Run soleur:review now" option) and Phase 5.5 `### Code Review Completion Gate` (interactive arm). All three are interactive-only; headless aborts instead | Anchor the entry to BOTH sections (`## Phase 1.5: Review Evidence Gate`, `## Phase 5.5: Pre-Ship Review Gates`). The log confirms Phase 5.5 is live: 10 of 29 rows are `ship preflight review` |
| ADR-229 text "~line 346" | The sentence is at lines ~371–374, the tail of the `[Amended 2026-09-22 (#8470)]` Consequences bullet | Cite it by content anchor ("Known unmodelled designed call"), not by line (`cq-cite-content-anchor-not-line-number`) |
| "the phantom pair is noise in the same invocation log the #8470 re-measure will read" | True for the LOG. The re-measure's INSTRUMENT is #8470's inline jq triage, which collapses compound behind `brainstorm`/`plan`/`postmerge` only and deliberately not behind `ship`, and does not read the view. So declaring changes the classifier's report, not the triage's rows | Leave the triage alone. Record in ADR-229, in one sentence in the re-baseline bullet, that the two instruments now differ on the `ship … review ship` shape |
| "Either declare it … or record why it stays unmodelled" | Existing mechanism `DECLARED_SUB_STEPS` covers the property exactly. Its entry rules hold: `review` is a node, and not a declared successor of `ship` (`ship: ["postmerge","work"]`) | Declare |

## Research Insights

### Premise Validation (Phase 0.6)

- **#8470:** OPEN (`gh issue view 8470`). It is ADR-229's re-open trigger, so the PR body says
  `Ref #8470`.
- **#8567** (the #8470 fix): MERGED at `2026-09-23T15:40:08Z` (`gh pr view 8567 --json mergedAt`).
  This equals the brief's `SINCE`.
- **#8627:** draft PR, OPEN.
- **#8326:** OPEN, untouched.
- **Cited code exists on this branch, which is at `origin/main` `ca971ee88c` (0 commits behind):**
  - `DECLARED_SUB_STEPS` at `plugins/soleur/lib/workflow-fidelity.ts` (the const after the
    "Node skills that another node's SKILL.md invokes as a designed SUB-STEP" docblock).
  - the `sub_steps` block in `.claude/workflow-transitions.json`.
  - the "Known unmodelled designed call" sentence in ADR-229.
- **ADR corpus mechanism check:** ADR-229's Alternatives table has no row that rejects adding a
  sub-step. Its entry rules are on the TS docblock: both sides are nodes, and the value is not a
  declared successor of the key. `ship: review` satisfies both.
- **Nothing is stale.**

### Property List (Phase 0.6b)

- **P1.** When ship's run invokes `review` (Phase 1.5 or 5.5) and ship then continues, the call
  adds no undeclared pair. That means no `ship → review`, and no `compound → X` tail from ship's
  own Phase 2 after it.
- **P2.** The collapse launders no review skip:
  - every pair INTO `ship` from an undeclared predecessor (`plan`, `postmerge`, `brainstorm`) is
    still reported;
  - a ship re-invoked after a review still reads as the undeclared self-loop `ship → ship`.
- **P3.** A `review` whose previous KEPT node is not `ship` is never collapsed. So `review → ship`
  skip-compound rows stay reported everywhere outside that shape.
- **P4.** ADR-229 records the decision, its measured delta, and its one unavoidable cost. It also
  records how the change interacts with the #8470 re-measure.
- **P5.** The claim "ship invokes review" is pinned to each SKILL.md section that makes it. So
  deleting either call site fails a test.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| Time-window heuristic in the classifier (collapse `review` only if ≤N s after `ship`) | Separate an in-ship review from a standalone review run after a headless abort | The log has start records only, with no end-of-skill record. N would be a new tuning surface. The measured cost it would avoid is 3 `review → ship` rows plus 5 self-loops |
| Declare `ship → review` as a transition edge | P1 (half) | It fails P1, because the `compound → postmerge` tail stays. It also gets the meaning wrong: ship CALLS review and does not hand off to it. And a mandatory-successor reader would read the edge as "go to review after ship" |
| Edit the #8470 triage procedure to also collapse `review` behind `ship` | P4 | The triage is the re-measure's frozen instrument, and it deliberately does not collapse behind `ship` so that class A stays visible. One ADR sentence buys P4 with no change to the instrument |
| C4 `ship -> review` edge | P4 | C4 L3 has no skill→skill sub-invocation edge; none of the four existing designed sub-step calls (`brainstorm/plan/postmerge/ship -> compound`) is drawn. See the ADR/C4 section |
| Edit `ship/SKILL.md` | P5 | All three calls already exist. The file is 267,185 B against a 274,000 B ceiling |
| New per-key `substep` output field | P1 visibility | `substep=` plus the undeclared-row list already show the delta |
| General completeness invariant: every `skill: soleur:<node>` in a node's SKILL.md ⊆ `sub_steps[k] ∪ successors[k]` (advisor suggestion) | Catch the NEXT unmodelled call mechanically | Measured, and it false-positives today. `review/SKILL.md` names `skill: soleur:compound` then `skill: soleur:ship` as a handoff sequence, which is the declared `review → compound → ship`, not a direct `review → ship` call. `compound/SKILL.md` names itself 4×. A textual mention is not an edge, so the invariant needs an allowlist, and an allowlist makes it a second hand-maintained set beside the exact-set pin. Also outside the brief's scope. Not taken |
| Pin `sub_steps.ship`'s value list inside the classifier suite | view drift | The TS parity deep-equal plus the exact-set `toEqual` already pin it (required `grok-fidelity` check). New case 39 also goes red on a view that lacks `review` |

### Value measurement (Phase 0.6c): measured, with the command named

Both views read ONE frozen copy of the log, so the delta comes from the view diff alone. This is
the method ADR-229's 2026-09-21 re-baseline uses:

```bash
export TMPDIR=/var/tmp; S=/var/tmp/adr229-measure
for v in before after; do mkdir -p "$S/$v/.claude"; cp /data/git-repositories/jikig-ai/soleur/.claude/.skill-invocations.jsonl "$S/$v/.claude/"; done
cp .claude/workflow-transitions.json "$S/before/.claude/"
jq '.sub_steps.ship = ["compound","review"]' .claude/workflow-transitions.json > "$S/after/.claude/workflow-transitions.json"
for v in before after; do CLASSIFY_REPO_ROOT="$S/$v" bash scripts/classify-workflow-transitions.sh --summary; done
```

Planning-time reading on 2026-09-23 (read=10863, both runs):

- **Before:** `undeclared=324 sessions=1299 pairs=4992 nonnode=4202 substep=195`
- **After:** `undeclared=291 sessions=1294 pairs=4957 nonnode=4202 substep=230`

Per-pair deltas (`uniq -c` of the row lists, diffed):

- **Removed:**
  - `ship → review` −29
  - `review → postmerge` −4 (6 → 2)
  - `review → ship` −3 (51 → 48)
  - `compound → postmerge` −1 (3 → 2; this row is the ADR's own example session)
  - `review → plan` −1
  - `review → review` −1
- **Exposed by the collapse:**
  - `ship → ship` +5 (8 → 13)
  - `ship → plan` +1 (51 → 52; a second-feature start, undeclared by ruling)

The arithmetic checks out: −39 + 6 = −33.

The 29 `ship → review` rows (timing from the ship record to the review record):

- 13 are ≤300 s.
- 10 are `ship preflight review`, the Phase 5.5 shape.
- The rest are long-gap reviews that end the session. These carry no skip signal (see Sharp
  Edges).
- **`ship review work`** (the one shape where the collapse silently yields a DECLARED pair):
  **0** rows.

**Re-measure at implementation time.** The log is append-only and machine-local. ADR-229 says to
quote the deltas, never the absolutes. The ADR amendment must quote the deltas from a run done
at work time with this exact procedure, not from the numbers above
(`2026-09-21-a-re-open-trigger-…` session error 1: a count written into an ADR comes from the
procedure the artifact publishes).

### Relevant files

- `plugins/soleur/lib/workflow-fidelity.ts`: the `DECLARED_SUB_STEPS` const and its docblock
  (which lists each entry with its section, plus the entry rules).
- `.claude/workflow-transitions.json`:
  - `sub_steps.ship`;
  - the `_comment` amendment list `(amended 2026-09-19, #8325; 2026-09-21, #8399)`.
- `plugins/soleur/test/workflow-fidelity.test.ts`:
  - `DECLARED_SUB_STEPS is exactly the reviewed set` (the `toEqual` pin);
  - `every sub-step is invoked by its key's SKILL.md in the section that owns it` (the
    `SECTION` map, one heading per key, with `checks === flat().length`);
  - the three invariant tests;
  - the view key-set test (4 keys, unaffected).
- `scripts/classify-workflow-transitions.sh`: the collapse is
  `($SUB[.kept[-1].skill] // []) | index($r.skill)`. It is membership-based, so a two-value array
  needs **no classifier change**.
- `scripts/classify-workflow-transitions.test.sh`:
  - cases 33–38;
  - `MIN_CASES=39`;
  - the floor comment ("cases 1-38 yield 39");
  - `new_root` copies the REAL view, so new cases test the real mirror.
- `scripts/guard-vacuity-floor.test.sh`: slices the `MIN_CASES` floor and its contiguous
  assignments into a mutant. Keep `MIN_CASES=` on the line directly above its `if`.
- `plugins/soleur/skills/ship/SKILL.md`: `## Phase 1.5: Review Evidence Gate`, which has 2 call
  sites and runs to `## Phase 2`. It also contains `## Phase 5.5: Pre-Ship Review Gates`, with 1
  call site under `### Code Review Completion Gate`, which runs to `## Phase 6.4`. No H2 line
  falls between each heading and its calls (verified with `awk`).
- ADR-229: the Status line; the Decision 1 amendment brackets; the Consequences re-baseline
  bullets; the "Known unmodelled designed call" sentence; the Verification bullets
  (`39 assertions (the MIN_CASES floor)`, "the exact four-key sub-step set").

**Consumer census** (to back the universal negative "no other reader"):
`git grep -l -e DECLARED_SUB_STEPS -e sub_steps -- ':!knowledge-base'` returns 7 files. Five of
them are the files above: the const, the view, the TS test, the classifier and its test. The
other two are the generic guard-authoring bullets in `review/SKILL.md` and `work/SKILL.md`, which
name no entry. Neither needs an edit.

### Institutional learnings applied

- `2026-09-21-a-re-open-trigger-keyed-on-an-issue-closing-fires-at-the-fixing-merge.md`
  - Use `Ref #8470`, never a closing keyword.
  - Counts in the ADR come from the published procedure.
  - The anchor test is textual. Its limits are written into the test and the ADR, not hardened
    past what a text anchor can prove.
  - On `Disk quota exceeded`, use `TMPDIR=/var/tmp`.
- `2026-09-18-every-p1-lived-in-a-guard-i-added-…`: the TS const and the JSON view need a
  two-way parity check. Edit the TS first.
- `2026-09-11-the-shard-i-substituted-for-a-refused-gate-was-the-one-that-was-red.md` and
  work/SKILL.md §REFUSED gate: substitute suites are chosen by shape (repo-global ratchets
  UNFILTERED) plus the consumers of the diff's vocabulary, never by name prefix.
- `2026-05-16-adr-amendment-required-when-reversing-…`: the ADR amendment ships in the same PR.

### CLAUDE.md / AGENTS.md conventions honoured

- `cq-write-failing-tests-before`: tests are written RED first.
- `hr-never-git-stash-in-worktrees`.
- ADR-179 d4: no rule instrumentation in `plugins/`, and no `command_snippet` in
  `rule-metrics.json`.
- `pgrep -f` is banned.
- `knowledge-base/INDEX.md` is untracked (ADR-235). Never regenerate or stage it.

## Implementation Phases

### Phase 0: Setup

1. `export TMPDIR=/var/tmp`.
2. Run `npm ci --ignore-scripts` at the worktree root and in `apps/web-platform`. A fresh
   worktree needs this before any commit, because lefthook runs plugin tests.
3. Baseline green:
   - `bun test plugins/soleur/test/workflow-fidelity.test.ts`
   - `bash scripts/classify-workflow-transitions.test.sh` (expect `39 passed, 0 failed`)

### Phase 1: RED (tests first)

1. **`plugins/soleur/test/workflow-fidelity.test.ts`, the exact-set pin.** Change `ship: ["compound"]` to
   `ship: ["compound", "review"]`. The array order is part of the pin, because `toEqual` checks
   array order. The const must use this exact order.
2. **Same file, the anchor test.** Replace the one-heading-per-key `SECTION` map with a
   per-entry map of heading lists:

   ```ts
   const ANCHORS: Record<string, Record<string, readonly string[]>> = {
     brainstorm: { compound: ["### Phase 4: Handoff"] },
     plan: { compound: ["## Exit Gate"] },
     postmerge: { compound: ["## Phase 6: Update Issue and Compound"] },
     ship: {
       compound: ["## Phase 2: Capture Learnings"],
       review: ["## Phase 1.5: Review Evidence Gate", "## Phase 5.5: Pre-Ship Review Gates"],
     },
   };
   ```

   - Keep the existing scope rule: a section starts at `startsWith(heading)` and ends at the next
     H2 line.
   - Keep the regex `skill: soleur:${sub}(?![\w-])`, the per-heading `start >= 0` assertion and
     the `checks > 0` guard.
   - **Coverage is one set equality, asserted BEFORE the loop.** The sorted `node:sub` pairs of
     `ANCHORS` must `toEqual` the sorted `node:sub` pairs of `DECLARED_SUB_STEPS`. This one
     assertion replaces separate "missing" and "stale" checks. Asserting it first matters: an
     unanchored entry then fails with a readable diff, not a `TypeError` on `undefined`.
   - **Loop over `DECLARED_SUB_STEPS`, not over `ANCHORS`** (deepen, test-design P1). A total
     summed from the same map the loop walks checks itself. For each entry:
     - look up `ANCHORS[node]?.[sub] ?? []`;
     - assert it is non-empty with a named message ("`ship:review` has no anchor headings");
     - run one section-scoped check per heading.

     Then assert `checks >= Object.values(DECLARED_SUB_STEPS).flat().length`, a lower bound that
     does not come from `ANCHORS`.
   - **Do not add a literal `6`.** Both review panels cut it: `ANCHORS` sits in the same diff as
     the literal, so the literal proves consistency, not integrity.
   - **Extend the LIMITS comment with two new textual limits.** (i) Phase 1.5 holds two review
     call sites, so the anchor cannot see one of them being deleted. (ii) The Phase 5.5 H2 scope
     runs about 1,145 lines (to `## Phase 6.4`), so any later `skill: soleur:review` mention
     anywhere in it keeps the anchor green even if the Code Review Completion Gate call is
     deleted. Anchoring on the H3 would not help, because the scope still ends at the next H2.
     Both limits are accepted, the same posture as #8399.
3. **`scripts/classify-workflow-transitions.test.sh`: new cases 39, 40, 41.** Each case:
   - uses `new_root`, which copies the REAL view;
   - asserts rc 0, the exact `--summary` counts and the exact row list.

   The expected values were traced through the jq, and the plan review re-ran them against the
   real classifier:
   - **39.** `ship review compound postmerge`: expect `undeclared=0 pairs=1 substep=2` and no
     row. This is ADR-229's own example and proves P1.
   - **40.** `work review ship`: expect `undeclared=1 pairs=2 substep=0`, and the row output
     must EQUAL exactly one row (`[[ "$ROWS" == $'  s40\treview -> ship' ]]`; the real format is
     two spaces, the session id, a tab, then the pair). Do not use a substring match: cases 36
     and 37 use `*"plan -> ship"*`, which still passes when an extra row appears. This is P3,
     the control: the collapse is keyed on the previous KEPT node being `ship`. It is GREEN
     before and after the change. Its RED mutation is Guard 1 classifier row C1.
   - **41.** `ship review work`: expect `undeclared=0 pairs=1 substep=1` and no row. Its pass
     message names it as the accepted false-negative ("accepted cost: ship review work reads as
     declared ship -> work"). A future time-window heuristic will then break it deliberately,
     not as an apparent regression. 0 rows were measured.
   - Cases 39 and 41 keep `-z "$ROWS"`. Match `--summary` fields as `*"substep=2 "*` with the
     trailing space. Never compare the whole summary line, which would break every case
     whenever a field is added.
   - **Cut at plan review:**
     - `ship review ship`: case 22 already pins that a self-loop the collapse exposes is
       reported, and the reduce's membership test does not change.
     - `plan ship review …`: cases 1 and 36 already pin that `plan -> ship` is exposed.
   - **Floor.** Set `MIN_CASES=42` (39 today, plus 3 single-pass cases), and change the floor
     comment to "cases 1-41 yield 42". Confirm by running the suite: `REAL_PASSES` must print 42.
     The floor must equal the measured count. Keep `MIN_CASES=` on the line directly above its
     `if` (`guard-vacuity-floor.test.sh` slices those lines).
4. Run both suites. Expected RED:
   - the exact-set pin;
   - the anchor set-equality (ANCHORS names `ship:review`, which the const lacks);
   - cases 39 and 41, which report `ship -> review` under the old view.

   Case 40 stays GREEN.

### Phase 2: GREEN (TS first, then the mirror)

1. **`plugins/soleur/lib/workflow-fidelity.ts`.** Set `ship: ["compound", "review"]`. Update the
   docblock:
   - The `ship:` bullet reads: "§Phase 2 (Capture Learnings) runs `compound` inside ship.
     §Phase 1.5 (Review Evidence Gate: the missing-evidence option and the `sequential-fallback`
     re-run) and §Phase 5.5 (Pre-Ship Review Gates → Code Review Completion Gate) run `review`
     inside ship. These are interactive arms only; headless aborts instead."
   - Add one sentence on why `review` is legal as a value: it is a node, and it is not among
     ship's declared successors (`postmerge`, `work`).
   - Update the "To add an entry" steps to name every place a new entry touches:
     - the const;
     - the JSON view;
     - the exact-set pin;
     - the `ANCHORS` heading list;
     - a classifier case, plus `MIN_CASES`;
     - the ADR-229 Status line and re-baseline.
   - Append `2026-09-23, #8627` to the "See ADR-229 (amended …)" citation.
2. **`.claude/workflow-transitions.json`.** Set `sub_steps.ship` to `["compound", "review"]`, in
   the same order and with the file's existing 2-space formatting. Append `; 2026-09-23, #8627`
   to the `_comment`'s amendment list. It must still parse as JSON.
3. Re-run both suites. Everything should be GREEN, and `REAL_PASSES` should equal `MIN_CASES`.

### Phase 3: ADR-229 amendment (same PR, `wg-architecture-decision-is-a-plan-deliverable`)

Write the cost list ONCE, in the re-baseline bullet (step 3). Every other edit points to it.

1. **Status line.** Change to: "Amended 2026-09-19 (#8325), 2026-09-21 (#8399), 2026-09-22 (#8470)
   and 2026-09-23 (#8627)."
2. **Decision 1.** Add a bracket after the #8399 one: **[Amended 2026-09-23 (#8627): `ship` also
   carries `review`, anchored to §Phase 1.5 and §Phase 5.5 under the same textual-anchor limits;
   see the 2026-09-23 re-baseline. The view still has one consumer.]**
3. **Consequences.** Add ONE bullet, "Re-baselined 2026-09-23 (#8627, `review` as a `ship`
   sub-step)", placed right after the 2026-09-21 re-baseline bullet so the re-baselines stay in
   date order. It holds:
   - the before/after `--summary` from ONE frozen copy, re-run at work time with this plan's
     §Value measurement procedure, and the identity `Δpairs = −Δsubstep`;
   - one evidence clause: of the N `ship → review` rows collapsed, how many start ≤300 s after
     ship, and how many follow ship's own `preflight`;
   - **the accepted cost, stated once and measured, not guessed.** Any `review` after a kept
     `ship` is dropped, whatever caused it, and that also erases the review's own outgoing edges:
     - `ship review work` reads as the declared `ship → work` (0 rows measured).
     - A ship run again after a review reads as the undeclared self-loop `ship → ship`, which
       is still reported. At planning time there were +5 such rows (the deepen pass read all
       five sessions):
       - **2** are review's own §6 Exit Gate (`review/SKILL.md`: `skill: soleur:compound`,
         then `skill: soleur:ship`), shaped `ship review … compound ship`.
       - **3** go review → ship directly.
     - The log has start records only, so a review long after ship cannot be told from ship's
       own review. In one of the five sessions the review starts 42 h after the ship.

     This is a real delta of this PR: before it, those rows read `ship → review` plus declared
     tails. No pair INTO `ship` changes: `plan → ship`, `postmerge → ship` and `brainstorm → ship`
     are unchanged.
   - **two sentences on #8470.** First: the classifier's own `review → ship` count falls by the
     measured amount (−3 at planning time, all shaped `ship … review ship`), so the #8399 ruling's
     51 is comparable only with the #8470 triage's count, never with a post-#8627 classifier
     run. Second: the triage deliberately does not collapse `review` behind `ship`; it keeps its
     own inline collapse and is unchanged.
4. **The "unmodelled designed call" sentence.** Keep it and append: **[Modelled 2026-09-23 (#8627):
   declared as a `ship` sub-step; see the 2026-09-23 re-baseline.]** Do not edit the text of the
   2026-09-22 (#8470) bracket.
   - **Supersede brackets.** Follow the #8325 precedent. Put a short `[#8627: …; see the
     2026-09-23 re-baseline]` bracket on the two 2026-09-21 sentences this change falsifies:
     - "`review → ship` stays at 51 — it is not a collapse candidate";
     - "No collapse can launder a review skip", whose argument covers `compound` only. The new
       argument is "no pair INTO `ship` changes".
   - **Alternatives table.** Add one row: "Declare `ship → review` as an edge (#8627): the
     `compound → X` tail survives, and any review after ship becomes legal-if-taken."
   - **Citation form.** #8325, #8399 and #8470 are issues, while #8627 is a PR. Write
     "(PR #8627)" in the Status line and in every bracket, so a reader who runs
     `gh issue view 8627` is not misled.
5. **Verification section.**
   - workflow-fidelity bullet: rewrite the anchor clause to "…a SKILL.md anchor test, per entry
     (the `ANCHORS` map), one check per heading, with a check count equal to the heading total".
     It currently says "scoped per key, with a check count equal to the entry count", which
     becomes false.
   - classifier bullet: change `39 assertions (the MIN_CASES floor)` to the new measured floor,
     and add one clause in the #8399 style: "Since #8627: `ship review compound postmerge`
     collapses, `work review ship` stays reported (the control), and `ship review work` reads as
     declared (the accepted cost)."
   - Status line uses "(PR #8627)".
6. `bash scripts/check-adr-ordinals.sh`. No new ordinal is claimed, but the brief requires this
   after every sync with main.

### Phase 4: Verify

1. `bun test plugins/soleur/test/workflow-fidelity.test.ts`. This suite runs in the required
   `grok-fidelity` check.
2. `bash scripts/classify-workflow-transitions.test.sh`. It prints `<floor> passed, 0 failed`.
3. `bash scripts/guard-vacuity-floor.test.sh`, because the floor moved.
4. `bash plugins/soleur/test/c4-count-parity.test.sh`. This is the "no C4 impact" evidence
   (green at planning time, rc=0).
5. `bash scripts/check-adr-ordinals.sh`.
6. **Full pre-merge gate:** `bash scripts/test-all.sh`. **If it is REFUSED (rc=4)**, run
   `TEST_GROUP=affected bash scripts/test-all.sh`. Its census backstop always runs every
   repo-enumerating suite. Then ALSO run, UNFILTERED and by hand, every path-less ratchet
   registered in `scripts/test-all.sh`. Select them by shape, never by a keyword filter. They
   include at least:
   - `scripts/lint-window-closure-assertion.test.sh`, plus the `-live` python run with its
     allowlist;
   - `scripts/battery-tag-authorship.test.sh` and `scripts/battery-tag-authorship-mutations.test.sh`;
   - `scripts/guard-vacuity-floor.test.sh`;
   - `plugins/soleur/test/fixture-dir-operand-assert.test.sh`.

   Then run the consumers of the diff's vocabulary:
   `git grep -l -e DECLARED_SUB_STEPS -e sub_steps -e workflow-transitions.json -- '*.test.*'`.
   Name each suite in the PR body with its pass count.

## Files to Edit

- `plugins/soleur/lib/workflow-fidelity.ts`: the `DECLARED_SUB_STEPS.ship` value and its docblock.
- `.claude/workflow-transitions.json`: `sub_steps.ship`, plus the `_comment` amendment list.
- `plugins/soleur/test/workflow-fidelity.test.ts`: the exact-set pin and the per-entry anchor
  test.
- `scripts/classify-workflow-transitions.test.sh`: cases 39–41, `MIN_CASES`, and the floor comment.
- `knowledge-base/engineering/architecture/decisions/ADR-229-workflow-fsm-single-source-and-offline-classification.md`:
  Status, Decision 1 bracket, one Consequences re-baseline bullet, the unmodelled sentence,
  Verification.

## Files to Create

None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 issues) was checked against every
path above, and against `ADR-229` and `workflow-transitions`. There were zero matches.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-229**. This extends Decision 1's `sub_steps` membership and discharges the "Known
unmodelled designed call". It needs no new ADR and no new ordinal. The tasks are in Phase 3
above.

### C4 views

**No C4 impact.** This conclusion comes from READING `model.c4`, `views.c4` and `spec.c4`, not
from grepping for the feature's name:

- **(a) External human actors:** none are involved. The change is repo-local tooling over a
  gitignored log.
- **(b) External systems:** none.
- **(c) Containers and data stores:** the Soleur Plugin container's L3 components `ship` and
  `review` already exist in `model.c4` (the `ship = component "ship skill"` and
  `review = component "review skill"` blocks). The classifier and the view are repo tooling,
  which C4 does not model. The same was true for ADR-229's three earlier amendments.
- **(d) Relationships:** the C4 L3 relationship block ("C4 L3 (Component — Soleur Plugin)") has
  orchestrator step edges (`go -> X`, `oneshot -> plan/work/review/compound/ship`) and
  skill→agent or skill→store calls (`brainstorm -> cto`, `plan -> cto`, `review -> archstrat`,
  `compound -> evalharness`). It has no skill→skill sub-invocation edge: the four existing
  designed sub-step calls (`brainstorm/plan/postmerge/ship -> compound`) are undrawn. Adding `ship -> review` alone would make the view inconsistent. If C4 ever models
  sub-step calls, all five should be added together; that is not in this PR's scope.
- `plugins/soleur/test/c4-count-parity.test.sh` was **green** at planning time (rc=0,
  `ALL TESTS PASSED`). Phase 4 re-runs it.

### Sequencing

The decision is true at merge. No soak is needed, and there is no `adopting` status.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Keep the call unmodelled and record why in ADR-229 | Rejected. It leaves 33 undeclared rows (about 10% of the report) in the log the #8470 re-measure reads. The only argument for it (the collapse cannot tell in-ship from post-abort review) costs 3 `review → ship` classifier rows and 5 self-loops, and none of those carries a skip signal |
| Declare the edge `ship → review` | Rejected. The `compound → postmerge` phantom remains, the semantics are wrong, and it becomes legal-if-taken for any post-ship review |
| Time-window heuristic | Cut. See the Cut List |
| Also collapse `review` behind `ship` in the #8470 triage | Rejected. It changes the frozen re-measure instrument mid-window, and it would hide class A. One ADR sentence records the divergence instead |

No deferrals, so no tracking issues are needed.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The change stays inside
  repo-local tooling:
  - a TS data const that no plugin runtime path reads (ADR-229: "No plugin runtime code calls
    `declaredTransitions()`", and `DECLARED_SUB_STEPS` has no runtime reader either);
  - a hand-mirrored view read only by an offline classifier over a gitignored log;
  - tests and an ADR.

  The worst case is a wrong count in the operator's own `--summary` reading. The parity block (the
  required `grok-fidelity` check) and the classifier suite both go red on that.
- **If this leaks, the user's data / workflow / money is exposed via:** no vector. There are no
  new write sites and no egress. The ADR quotes aggregate counts only, never session ids.
- **Brand-survival threshold:** `none`
- threshold: none, reason: the diff touches only plugin-internal data consts, a repo-local JSON
  view, tests and an ADR, and none of them matches `SENSITIVE_PATH_RE`.

## Observability

```yaml
liveness_signal:
  what: "the classifier --summary line: substep= rises and undeclared= falls by the measured delta once the view carries ship:review"
  cadence: "per local run (offline by design, ADR-229 decision 3)"
  alert_target: "the terminal running it; rc 2 FATAL lines on a stale or malformed view"
  configured_in: "scripts/classify-workflow-transitions.sh"
error_reporting:
  destination: "stderr of scripts/classify-workflow-transitions.sh (repo tooling; never runs in production, so no Sentry surface)"
  fail_loud: "FATAL: declared view … carries no `sub_steps` map … (rc 2); the NULL-reading marker on an absent log"
failure_modes:
  - mode: "view mirror drifts from DECLARED_SUB_STEPS (review added to one side only)"
    detection: "workflow-fidelity.test.ts parity deep-equal + exact-set toEqual, in the required grok-fidelity check"
    alert_route: "red required PR check"
  - mode: "the new entry collapses a review not preceded by ship, or a review after ship is left uncollapsed"
    detection: "classifier cases 39, 40, 41 (and the existing exposure cases 22 and 36)"
    alert_route: "red scripts/classify-workflow-transitions suite (test-all / CI scripts shard)"
  - mode: "a ship review call site is deleted or its section renamed"
    detection: "per-entry SKILL.md anchor test (Phase 1.5 and Phase 5.5 headings)"
    alert_route: "red grok-fidelity check"
logs:
  where: "/data/git-repositories/jikig-ai/soleur/.claude/.skill-invocations.jsonl (gitignored; producer .claude/hooks/skill-invocation-logger.sh)"
  retention: "rotated into .skill-invocations-<ts>.jsonl.gz, which the classifier also reads"
discoverability_test:
  command: "jq -c .sub_steps.ship .claude/workflow-transitions.json"
  expected_output: "[\"compound\",\"review\"]"
```

## Guard Contract

### Guard 1: the sub-step set pin and the per-entry SKILL.md anchor

**Property.** Every `(key, value)` sub-step the classifier collapses is exactly one reviewed in
`workflow-fidelity.test.ts`. For every such entry, each SKILL.md section named as making the call
names `skill: soleur:<value>`.

**Assembly.** There is one chokepoint: the view's `sub_steps`, read as `$SUB` by the classifier.
It is fed only by the hand mirror of `DECLARED_SUB_STEPS`. The members that must agree:

- the TS const (`toEqual` exact set);
- the view (parity deep-equal, and "names no sub-step absent from the const");
- the entry rules (the three invariant tests);
- the `ANCHORS` map (the `node:sub` pair set equals the const's pair set, each heading list is
  non-empty, and one section-scoped check runs per heading).

**Mutation matrix** (each row MUST go RED):

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete ONLY the `skill: soleur:review` call under `### Code Review Completion Gate` (Phase 5.5), keeping both Phase 1.5 calls. Anchor the edit on the line containing "No code review was run before ship", because a file-wide `s/skill: soleur:review//` removes all three sites. Then assert `grep -c 'skill: soleur:review'` fell by exactly 1 | RED (the Phase 5.5 heading check) |
| 2 | Delete BOTH Phase 1.5 `skill: soleur:review` calls, keeping Phase 5.5 | RED (the Phase 1.5 heading check) |
| 3 | Second member after a compliant first: add `brainstorm: ["compound", "review"]` to const and view | RED (exact-set pin, and the ANCHORS set equality) |
| 4 | Rule-legal hidden entry: add `ship: ["compound", "review", "plan"]` to both | RED (exact-set pin, and the ANCHORS set equality) |
| 5 | Own dispatch: `ANCHORS.ship.review = []` | RED (the non-empty heading-list check) |
| 6 | Own dispatch: remove the `ship` key from `ANCHORS` | RED (the ANCHORS set equality) |
| 7 | View only: `sub_steps.ship = ["compound"]` while the const keeps `review` | RED (parity deep-equal; classifier case 39) |
| C1 | Classifier: drop ANY record whose skill is in ANY `sub_steps` list, regardless of the previous kept node (a scratch copy of the script, never committed) | RED (case 40: `review` is dropped, `work -> ship` is declared, and the expected row disappears. Case 20 covers the same mutant for `compound`; case 40 covers it for `review`) |

**Harness rows:**

| # | Harness edit | Expected |
|---|---|---|
| H1 | `ANCHORS.ship.review` names a non-existent heading (`## Phase 1.6: Review Evidence Gate`) | RED (the per-heading `start >= 0` assertion) |
| H2 | Must-PASS (not canonical): the Phase 1.5 heading gains a suffix (`## Phase 1.5: Review Evidence Gate (defense-in-depth)`) | PASS (`startsWith`) |

**Anchor.** The reviewed set lives in the test, in the same diff as the const and the view. One
PR can edit all three, so the guard proves consistency, not integrity. The outside anchor is
plan review and code review of `DECLARED_SUB_STEPS is exactly the reviewed set` (the #8399
posture). An `ANCHORS` heading dropped in the same diff is visible there, and a count literal
would not add anything that review does not already see.

**Classifier cases (not a separate guard).** The classifier's reduce is NOT in this diff; its
own guard is cases 18, 20–22 and 33–38. The new cases 39–41 are data-coverage rows for the new
view value. They go RED on the pre-change view (39 and 41) or stay green as the control (40),
and `MIN_CASES` counts them.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `DECLARED_SUB_STEPS.ship` deep-equals `["compound", "review"]` in
      `plugins/soleur/lib/workflow-fidelity.ts`. `jq -c .sub_steps.ship .claude/workflow-transitions.json`
      prints `["compound","review"]`.
- [ ] `bun test plugins/soleur/test/workflow-fidelity.test.ts` passes. The anchor test:
      - asserts, before its loop, that the `ANCHORS` pair set equals the `DECLARED_SUB_STEPS`
        pair set;
      - loops over `DECLARED_SUB_STEPS` and asserts each entry has a non-empty heading list;
      - asserts `checks >= Object.values(DECLARED_SUB_STEPS).flat().length`;
      - anchors `ship : review` to `## Phase 1.5: Review Evidence Gate` AND
        `## Phase 5.5: Pre-Ship Review Gates`.
- [ ] `bash scripts/classify-workflow-transitions.test.sh` prints `<N> passed, 0 failed`. N
      equals `MIN_CASES`, measured and not assumed (planned value 42). Cases 39–41 each assert
      exact row text and exact `undeclared=/pairs=/substep=` values.
- [ ] Guard 1 mutation rows 1 and 2 (deleting either call site) and classifier row C1 are each
      applied at work time on a scratch copy, and each goes RED. Row 1's edit must be anchored,
      and `grep -c 'skill: soleur:review'` must fall by exactly 1. The PR body records all
      three.
- [ ] ADR-229 carries four changes:
      - the Status line names `2026-09-23 (#8627)`;
      - Decision 1 has the #8627 bracket;
      - Consequences has the single 2026-09-23 re-baseline bullet, placed after the 2026-09-21
        one. It carries:
        - the deltas from a work-time frozen-copy run and the identity `Δpairs = −Δsubstep`;
        - the cost stated once, including the measured split of the `ship → ship` causes;
        - the two #8470 sentences, one of them giving the classifier's `review → ship` delta;
      - supersede brackets on the two 2026-09-21 sentences this change falsifies;
      - an Alternatives row for declaring a `ship → review` edge;
      - "(PR #8627)" as the citation form;
      - the Verification anchor clause and floor number are rewritten.
- [ ] The Modelled bracket sits beside the unmodelled sentence. The phrase wraps across lines in
      the ADR, so check it on the joined text:
      `tr '\n' ' ' < knowledge-base/engineering/architecture/decisions/ADR-229-workflow-fsm-single-source-and-offline-classification.md | grep -c 'unmodelled designed call[^[]*\[Modelled 2026-09-23'`
      prints `1`.
- [ ] `bash scripts/check-adr-ordinals.sh` exits 0, run after the final sync with main.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` passes.
- [ ] The full gate `bash scripts/test-all.sh` is green. If it is REFUSED, run the substitute set
      in Phase 4 step 6, with the path-less ratchets UNFILTERED, and name each suite in the PR
      body.
- [ ] The PR body says `Ref #8470` and contains no `Closes`/`Fixes`/`Resolves` keyword adjacent to
      8470. #8470 stays OPEN after merge.
- [ ] `git diff --name-only origin/main...HEAD` is a subset of two groups:
      - Files to Edit;
      - the files the pipeline writes itself: this plan, `knowledge-base/project/specs/feat-one-shot-adr229-in-ship-review-call/**`
        (tasks.md, session-state.md, decision-challenges.md) and any learning under
        `knowledge-base/project/learnings/` that compound writes.
      - In particular, `plugins/soleur/skills/ship/SKILL.md`, `scripts/classify-workflow-transitions.sh`
        and `rule-metrics.json` are absent, and `knowledge-base/INDEX.md` is never staged.

### Post-merge (operator)

None. The change is inert until someone next runs the classifier. The #8470 re-measure keeps its
own trigger (at least 5 post-fix full-pipeline `review → ship` rows, or 2026-11-04).

## Test Scenarios

- `ship review compound postmerge` → `ship → postmerge` (declared), `substep=2`, no row.
- `work review ship` → exactly one row, `review -> ship`. It is unchanged by this PR.
- `ship review work` → `ship → work` (declared), no row. This is the accepted cost, pinned.
- Existing cases 1–38 remain green. They include:
  - 20 (`review compound plan`: `review` is never a key);
  - 22 (an exposed self-loop is reported);
  - 24 (a first-record sub-step is never collapsed);
  - 36 (`plan -> ship` is exposed).

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment:** The approach is sound. Adding a sub-step entry is the existing pattern, and
declaring a `ship → review` edge would get the meaning wrong. The CTO confirmed the following.

- **Invariants:** they hold. `review` is a node, and it is not among ship's declared successors.
- **Anchoring:** anchoring both sections is right. There are three call sites: Phase 1.5 at the
  sequential-fallback re-run and at the "Run soleur:review now" option, and Phase 5.5 under
  `### Code Review Completion Gate`.
- **Consumers:** there are no consumers beyond the const, the view, the classifier and their
  tests.

Folded in:

- **(1)** Add a `ship review work` case, and name that shape in the ADR cost bullet. This is case
  41.
- **(2)** The anchor count must become the total number of headings, with the `> 0` guard kept.
  This is the computed sum. Plan review later cut the literal `6`.
- **(3)** The docblock and the `_comment` need updates. These are in Phase 2.
- **(5)** Note review's nested `compound`/`work`/`ship` calls in the ADR. Plan review cut this,
  because the note records no change: the behaviour predates this PR.

Complexity: small. No new ADR is needed.

No Product/UX gate: there is no UI surface, and no file in Files to Edit matches the UI-surface
terms.

## Sharp Edges

- **Array order is part of the pin.** `toEqual` checks array order. Keep `["compound", "review"]`
  in the const, the view and the test. The classifier itself does not depend on order
  (`index()` membership).
- **The floor is measured, not computed.** Set `MIN_CASES` to the `REAL_PASSES` the suite prints
  after the cases land. Keep the assignment on the line directly above its `if`, because
  `guard-vacuity-floor.test.sh` slices those lines into a mutant and an unbound variable scores
  as a construction failure.
- **Quote deltas, not absolutes.** Re-run the frozen-copy procedure at work time. The log grows
  under other sessions, and the planning-time absolutes will already have moved.
- **The #8470 instruments now differ on one shape, by design.** The classifier collapses
  `ship review` and the triage does not. Do not "fix" the triage in this PR.
- **The long-gap `ship → review` rows** (a review that ends the session, hours after ship) also
  vanish. They carry no skip signal: a review after ship is not a missing review before ship,
  and the pair INTO that ship is reported on its own terms.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6. This one declares `none` with a reason.
- **Fresh worktree.** Run `npm ci --ignore-scripts` at the root and in `apps/web-platform` before
  the first commit, or lefthook's plugin tests fail on missing modules.

## Review & Consult Provenance

- **Research:** `soleur:engineering:research:repo-research-analyst` and
  `soleur:engineering:research:learnings-researcher`. The repo analyst inferred "unmodelled
  because conditional". That inference was checked and rejected: ADR-229 gives no reason, and
  `plan`'s compound sub-step is conditional too (direct invocation only).
- **Domain:** `soleur:engineering:cto`. Risks 1, 2, 3 and 5 are folded in (see Domain Review).
- **Step 4.5 advisor consult** (semantic tier `advisor`, curated payload):
  - (2) is applied: the ADR states what the collapse masks as an accepted cost, not as "no
    laundering".
  - (1), a general completeness invariant, was measured and not taken. It false-positives on
    `review/SKILL.md`'s compound-then-ship handoff and on `compound/SKILL.md`'s mentions of
    itself (see the Cut List). Its other point, deriving the count rather than pinning a
    literal, became moot when plan review cut the literal.
- **Plan review** (four seats: DHH, Kieran, code-simplicity, and CTO with a devex lens).
  - **Mechanical findings applied:**
    - Kieran P1: the AC grep for the wrapped ADR phrase could never match; it is replaced by a
      `tr`-joined check.
    - Kieran P2s: the Verification clause rewrite; the docblock wording; the Phase 5.5 LIMITS
      sentence; the #8470 bracket left unedited.
    - Both panels fired on the literal `6`, so it is deleted per the prefer-delete rule.
    - Cases `ship review ship` and `plan ship review …` are cut (case 22 and case 36 cover them).
    - Guard 2 is folded into a one-paragraph note, because the classifier is not in the diff.
    - The original harness rows H2 (the file-wide weakening) and H4 (the reworded call) are cut,
      and so are the Guard 2 spot-checks. The suffix must-PASS row was renumbered H2.
    - The ADR cost is written once, in one re-baseline bullet placed after the 2026-09-21 one.
    - The nested-calls note was cut (no delta) at plan review, then RESTORED at deepen. Reading the
      5 new `ship → ship` sessions showed that review's own exit gate produces 2 of them, so it is
      a delta after all.
    - The Verification case list is cut.
  - **Taste, persisted headless** to `knowledge-base/project/specs/feat-one-shot-adr229-in-ship-review-call/decision-challenges.md`:
    - CTO devex #2: a read-only one-liner plus a disposition for a #8470 confounder. The
      confounder was cut instead.
    - DHH #8: collapse Phase 4's explicit ratchet list to a pointer. Not applied: the brief
      requires the path-less ratchets to run UNFILTERED, and naming them is how that is
      verified.
