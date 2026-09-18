# Tasks: feat(workflow-fsm): single-source the edge set, widen the instrument, ratchet prompt weight

Plan: `knowledge-base/project/plans/2026-09-18-feat-workflow-fsm-remediation-plan.md`
Issue: #8302 · PR: #8301 · Branch: `feat-workflow-fsm-remediation` · Lane: cross-domain

Derived from plan **v2** (post-review). v1's transition gate and its three-skill
extraction were cut — do not reinstate them from the spec's superseded FRs.

## Phase 1: Setup

- [x] 1.1 Re-read the plan's `## Plan Review Revisions` before starting — R1–R11
      are the difference between v1 and v2
- [x] 1.2 Confirm ADR-225 is still free across all remote refs
      (`git for-each-ref refs/remotes/origin` + `git ls-tree`, not `origin/main`)
- [x] 1.3 Capture pre-change byte sizes of the four lifecycle `SKILL.md` files
      (needed to seed ceilings with headroom, and as the AC12 diff base)

## Phase 2: Track A — instrument (tests first, per `cq-write-failing-tests-before`)

- [x] 2.1 Write failing tests in `scripts/rule-metrics-aggregate.test.sh`
  - [x] 2.1.1 Two sibling roots sharing one inode → union equals the **distinct**
        sum (not a symmetric both-sides check, which passes while both double)
  - [x] 2.1.2 A mode-000 sibling root → aggregation completes, does not abort
  - [x] 2.1.3 Enumeration that prepends a sibling → `INCIDENTS_DIRS[0]` assertion
        fails (rotation truncates element 0)
- [x] 2.2 Implement the widened read in `scripts/rule-metrics-aggregate.sh`
  - [x] 2.2.1 Enumerate siblings via `git worktree list --porcelain`
  - [x] 2.2.2 Canonicalise each root (`pwd -P`) and dedupe by inode
  - [x] 2.2.3 Append siblings only — never prepend or sort
  - [x] 2.2.4 Add `|| true` to the live-log `cat` in the merge loop
- [x] 2.3 Verify AC1–AC4 green

## Phase 3: Track A — single-source the edge set

- [x] 3.1 Write failing tests in `plugins/soleur/test/workflow-fidelity.test.ts`
  - [x] 3.1.1 `declaredTransitions()` returns the plan's edge set verbatim
  - [x] 3.1.2 `plan -> ship` is **absent** (the product requirement, as an absence)
  - [x] 3.1.3 `mandatorySuccessors("work")` does **not** contain `"plan"`
  - [x] 3.1.4 Existing `mandatorySuccessors` assertions still pass unmodified
- [x] 3.2 Add `declaredTransitions()` backed by a **bundled TS const** in
      `plugins/soleur/lib/` — never a runtime read of `.claude/`
- [x] 3.3 Leave `mandatorySuccessors()` forward-only and unchanged
- [x] 3.4 **DEVIATED:** the derived view went to its own
      `.claude/workflow-transitions.json`, NOT into `phase-surface-map.json`.
      That file is deep-equal'd against the bundled web copy, so a key added
      there would push FSM edges through the web bundle, which has no consumer
      for them. Same drift guard, no coupling.
- [x] 3.5 **NOT NEEDED, because of 3.4:** `phase-surface-map.json` is untouched,
      so `apps/web-platform/server/phase-surface-map.ts` needs no lockstep edit
      and its existing parity test still passes unmodified.
- [x] 3.6 Parity test across the TWO views (Guard 1 rows 1–2). Row 3 (web copy)
      is N/A after deviation 3.4: the web copy carries no edge set.
- [x] 3.7 Census assertion over edge-set readers, classifying test files
      explicitly as non-readers (Guard 1 row 4). **Landed at review, not at
      work** — it was ticked while unimplemented; the reader it would have
      caught (`lint-skill-body-budget.py` consuming the view) was found by the
      architecture seat instead. Then DELETED at the simplification pass: the
      ratchet no longer reads the view, and parity keeps the view correct for
      every reader.
- [x] 3.8 Verify AC5–AC10; run `bash scripts/grok-fidelity-gate.sh`

## Phase 4: Track A — offline classifier

- [x] 4.1 Write a failing test with a synthetic two-session invocation log
- [x] 4.2 Create `scripts/classify-workflow-transitions.sh`
  - [x] 4.2.1 Read `.claude/.skill-invocations.jsonl`, group by `session_id`
  - [x] 4.2.2 Walk each session's sequence; report transitions absent from
        `declaredTransitions()`
  - [x] 4.2.3 Apply the same root canonicalisation as 2.2 — the invocation log
        has the same per-root fragmentation as the incident log
  - [x] 4.2.4 Support `--summary`; exit 0
- [x] 4.3 Verify AC11

## Phase 5: Track B — extraction

- [x] 5.1 Extract `plan`'s `## Sharp Edges` (151,209 B) verbatim into
      `plugins/soleur/skills/plan/references/plan-sharp-edges.md`
- [x] 5.2 Replace it with a load directive. **Revised at review:** unconditional,
      placed as step 6.5 before Plan Review, with a STOP arm on a missing file;
      the conditional premise was measured false (decision-challenges §3)
- [x] 5.3 Verify AC12 by exact diff against the git base (not a byte sum)
- [x] 5.4 Verify AC13: `plan/SKILL.md` under 120,000 bytes

## Phase 6: Track B — ratchet

- [x] 6.1 Seed `plugins/soleur/test/skill-body-budget.json` with ≥10% headroom
      over current sizes (zero-headroom seeding reproduces the 15-bump ritual)
- [x] 6.2 Define "lifecycle skill" as the `declaredTransitions()` keys ∪
      destinations ∪ `ONE_SHOT_CHILD_SKILLS` (revised at review: 10 rows, not 7)
- [x] 6.3 Add the ratchet job to `.github/workflows/ci.yml` with
      `fetch-depth: 0` — **not** the bun shard, which has no fetch depth and
      would make the merge-base read fail on every run
- [x] 6.4 Assert the ceiling against the **merge base**, never the working tree
- [x] 6.5 Base-unavailable is a hard RED, never a skip (Guard 2 row 7)
- [x] 6.6 Unclassified bucket: a lifecycle skill with no row reddens
- [x] 6.7 Walk the full Guard 2 mutation matrix, rows 1–7
- [x] 6.8 **Demonstrate RED**: appended 30 KB to `ship/SKILL.md` (not `review`;
      any lifecycle skill serves), captured
      `ship: ... is 278183 bytes, ceiling is 274000 (4183 over)` — one file, one
      number — reverted byte-identical, verified green again.
- [x] 6.9 Verify AC14–AC17

## Phase 7: Records

- [x] 7.1 Wrote
      `ADR-225-workflow-fsm-single-source-and-offline-classification.md` (final
      filename differs from the plan's provisional one) covering four decisions:
      bundled const, separated transition functions, offline classification, and
      the merge-base ratchet placement.
- [~] 7.2 ~~Create `scripts/followthroughs/workflow-fsm-transition-baseline-8302.sh`~~
      Created, then DELETED at the review simplification pass: it could not PASS
      where the sweeper runs, and as an operator-run script it was a wrapper
      around `classify --summary`. The classifier warns on null/empty readings.
- [~] 7.3 **STRUCK at review.** The sweeper runs on a hosted runner against a
      fresh checkout where the gitignored invocation log cannot exist; a
      synthetic fresh checkout measured FAIL on every sweep. The probe is
      operator-run; ADR-225 and the probe header record why. No directive.
- [ ] 7.4 Verify AC18–AC20

## Phase 8: Exit

- [ ] 8.1 Run the full battery
- [ ] 8.2 Verify AC21 — no rule pruned, rule-id count still 98
- [ ] 8.3 Re-verify the ADR-225 ordinal against freshly-fetched refs; sweep
      plan, tasks and every AC if it moved
- [ ] 8.4 `/soleur:review` → `/soleur:compound` → `/soleur:ship`
