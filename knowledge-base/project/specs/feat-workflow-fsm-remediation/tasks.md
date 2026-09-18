# Tasks: feat(workflow-fsm): single-source the edge set, widen the instrument, ratchet prompt weight

Plan: `knowledge-base/project/plans/2026-09-18-feat-workflow-fsm-remediation-plan.md`
Issue: #8302 · PR: #8301 · Branch: `feat-workflow-fsm-remediation` · Lane: cross-domain

Derived from plan **v2** (post-review). v1's transition gate and its three-skill
extraction were cut — do not reinstate them from the spec's superseded FRs.

## Phase 1: Setup

- [ ] 1.1 Re-read the plan's `## Plan Review Revisions` before starting — R1–R11
      are the difference between v1 and v2
- [ ] 1.2 Confirm ADR-225 is still free across all remote refs
      (`git for-each-ref refs/remotes/origin` + `git ls-tree`, not `origin/main`)
- [ ] 1.3 Capture pre-change byte sizes of the four lifecycle `SKILL.md` files
      (needed to seed ceilings with headroom, and as the AC12 diff base)

## Phase 2: Track A — instrument (tests first, per `cq-write-failing-tests-before`)

- [ ] 2.1 Write failing tests in `scripts/rule-metrics-aggregate.test.sh`
  - [ ] 2.1.1 Two sibling roots sharing one inode → union equals the **distinct**
        sum (not a symmetric both-sides check, which passes while both double)
  - [ ] 2.1.2 A mode-000 sibling root → aggregation completes, does not abort
  - [ ] 2.1.3 Enumeration that prepends a sibling → `INCIDENTS_DIRS[0]` assertion
        fails (rotation truncates element 0)
- [ ] 2.2 Implement the widened read in `scripts/rule-metrics-aggregate.sh`
  - [ ] 2.2.1 Enumerate siblings via `git worktree list --porcelain`
  - [ ] 2.2.2 Canonicalise each root (`pwd -P`) and dedupe by inode
  - [ ] 2.2.3 Append siblings only — never prepend or sort
  - [ ] 2.2.4 Add `|| true` to the live-log `cat` in the merge loop
- [ ] 2.3 Verify AC1–AC4 green

## Phase 3: Track A — single-source the edge set

- [ ] 3.1 Write failing tests in `plugins/soleur/test/workflow-fidelity.test.ts`
  - [ ] 3.1.1 `declaredTransitions()` returns the plan's edge set verbatim
  - [ ] 3.1.2 `plan -> ship` is **absent** (the product requirement, as an absence)
  - [ ] 3.1.3 `mandatorySuccessors("work")` does **not** contain `"plan"`
  - [ ] 3.1.4 Existing `mandatorySuccessors` assertions still pass unmodified
- [ ] 3.2 Add `declaredTransitions()` backed by a **bundled TS const** in
      `plugins/soleur/lib/` — never a runtime read of `.claude/`
- [ ] 3.3 Leave `mandatorySuccessors()` forward-only and unchanged
- [ ] 3.4 Add the derived `transitions` view to `.claude/phase-surface-map.json`
- [ ] 3.5 Update `apps/web-platform/server/phase-surface-map.ts` in lockstep
- [ ] 3.6 Parity test across all three views (Guard 1 rows 1–3)
- [ ] 3.7 Census assertion over edge-set readers, classifying test files
      explicitly as non-readers (Guard 1 row 4)
- [ ] 3.8 Verify AC5–AC10; run `bash scripts/grok-fidelity-gate.sh`

## Phase 4: Track A — offline classifier

- [ ] 4.1 Write a failing test with a synthetic two-session invocation log
- [ ] 4.2 Create `scripts/classify-workflow-transitions.sh`
  - [ ] 4.2.1 Read `.claude/.skill-invocations.jsonl`, group by `session_id`
  - [ ] 4.2.2 Walk each session's sequence; report transitions absent from
        `declaredTransitions()`
  - [ ] 4.2.3 Apply the same root canonicalisation as 2.2 — the invocation log
        has the same per-root fragmentation as the incident log
  - [ ] 4.2.4 Support `--summary`; exit 0
- [ ] 4.3 Verify AC11

## Phase 5: Track B — extraction

- [ ] 5.1 Extract `plan`'s `## Sharp Edges` (150,469 B) verbatim into
      `plugins/soleur/skills/plan/references/plan-sharp-edges.md`
- [ ] 5.2 Replace it with a **conditional** load directive naming the gating
      phase — match the 7 gated directives, not the 5 unconditional ones
- [ ] 5.3 Verify AC12 by exact diff against the git base (not a byte sum)
- [ ] 5.4 Verify AC13: `plan/SKILL.md` under 120,000 bytes

## Phase 6: Track B — ratchet

- [ ] 6.1 Seed `plugins/soleur/test/skill-body-budget.json` with ≥10% headroom
      over current sizes (zero-headroom seeding reproduces the 14-bump ritual)
- [ ] 6.2 Define "lifecycle skill" as the seven `declaredTransitions()` keys
- [ ] 6.3 Add the ratchet job to `.github/workflows/ci.yml` with
      `fetch-depth: 0` — **not** the bun shard, which has no fetch depth and
      would make the merge-base read fail on every run
- [ ] 6.4 Assert the ceiling against the **merge base**, never the working tree
- [ ] 6.5 Base-unavailable is a hard RED, never a skip (Guard 2 row 7)
- [ ] 6.6 Unclassified bucket: a lifecycle skill with no row reddens
- [ ] 6.7 Walk the full Guard 2 mutation matrix, rows 1–7
- [ ] 6.8 **Demonstrate RED**: append 1 KB to `review/SKILL.md`, capture the CI
      output naming one file and one number, revert, paste into the PR body
- [ ] 6.9 Verify AC14–AC17

## Phase 7: Records

- [ ] 7.1 Write `ADR-225-workflow-fsm-single-source-of-truth.md` with all three
      decisions: bundled const (packaging boundary), separated transition
      functions, offline classification
- [ ] 7.2 Create `scripts/followthroughs/workflow-fsm-transition-baseline-8302.sh`
      honouring the sweeper contract (0 PASS / 1 FAIL / other TRANSIENT)
- [ ] 7.3 Add the `soleur:followthrough` directive to the tracker with a
      `script=` path that resolves (the gate hook blocks otherwise)
- [ ] 7.4 Verify AC18–AC20

## Phase 8: Exit

- [ ] 8.1 Run the full battery
- [ ] 8.2 Verify AC21 — no rule pruned, rule-id count still 98
- [ ] 8.3 Re-verify the ADR-225 ordinal against freshly-fetched refs; sweep
      plan, tasks and every AC if it moved
- [ ] 8.4 `/soleur:review` → `/soleur:compound` → `/soleur:ship`
