---
feature: design-taste-learning
lane: cross-domain
brand_survival_threshold: single-user incident
closes: 5990
plan: knowledge-base/project/plans/2026-07-05-feat-design-taste-learning-plan.md
status: ready-for-work
date: 2026-07-05
---

# Tasks: design taste-learning (context-keyed, recency) — #5990

Derived from the post-plan-review plan (Option A reshape). Order is contract-before-consumer.

## Phase 1 — Shared helper + tests (TDD)

- [ ] 1.1 Write `plugins/soleur/scripts/taste-profile-update.test.sh` RED (git-init fixture, pattern from `.claude/hooks/skill-context-queries.test.sh`):
  - [ ] 1.1.1 upsert + reinforce (`reinforce_count++`, `last_reinforced`=today)
  - [ ] 1.1.2 recency priming per `(context, axis)` (tie-break `reinforce_count`)
  - [ ] 1.1.3 same-context contradiction → `contradictions[]` append (old value+count+date) + supersede
  - [ ] 1.1.4 cross-context NON-contradiction (dashboard + landing coexist; `contradictions[]` empty)
  - [ ] 1.1.5 reject+preserve: out-of-allowlist context, out-of-allowlist axis, metachar/whitespace value, malformed date (4 cases)
  - [ ] 1.1.6 `--validate` mode returns non-zero on a tampered profile
  - [ ] 1.1.7 `last_updated` bumped, `last_reviewed` byte-unchanged
  - [ ] 1.1.8 atomic tmp+mv: original byte-preserved when the transform fails
- [ ] 1.2 Write `plugins/soleur/scripts/taste-profile-update.sh` GREEN:
  - [ ] 1.2.1 arg contract: `<profile> <context> <axis> <value> <today>` (write) + `--validate <profile>`
  - [ ] 1.2.2 validate all four tokens (context/axis allowlists; value `^[a-z][a-z0-9-]*$` ≤40; date `^\d{4}-\d{2}-\d{2}$`)
  - [ ] 1.2.3 slice fenced JSON block (awk `c==1`), single jq transform (upsert + reinforce + contradiction), re-render whole file
  - [ ] 1.2.4 atomic tmp+mv; bump `last_updated` only; never touch `last_reviewed`
  - [ ] 1.2.5 no decay/confidence tokens anywhere (AC6)
- [ ] 1.3 `bash plugins/soleur/scripts/taste-profile-update.test.sh` passes

## Phase 2 — Seed committed artifact

- [ ] 2.1 Create `knowledge-base/product/design/taste-profile.md` (frontmatter `last_updated`/`last_reviewed`/`review_cadence: quarterly`/`owner: CPO`; empty `entries[]`/`contradictions[]`; the two rendered sections; do-not-hand-edit comment)
- [ ] 2.2 `git add` + commit (net-new → `context-reviewed-gate.sh` exempt); verify `git ls-files --error-unmatch` exits 0

## Phase 3 — Wire `frontend-design` skill

- [ ] 3.1 Add `- knowledge-base/product/design/taste-profile.md` to `context_queries`
- [ ] 3.2 Add `### Multi-Variant Fan-Out` (shared anchor): N=3 sub-agents seeded via prompt text, biased to current-context recent entries; empty-profile → N distinct enum seeds
- [ ] 3.3 Mode predicate: interactive = natural-conversation selection (NO `AskUserQuestion`); headless/nested Task = auto-select top-recency + no write
- [ ] 3.4 Add `### Recording Taste`: run `--validate` (fail→no-bias) on read; on selection call the helper with the current context
- [ ] 3.5 Link the helper: `[taste-profile-update.sh](../../scripts/taste-profile-update.sh)`

## Phase 4 — Wire `ux-design-lead` agent (read-only)

- [ ] 4.1 Pre-Step-1 direct-Read + `--validate` of the taste-profile (bias only, fail→no-bias)
- [ ] 4.2 `### Multi-Variant Fan-Out` (same anchor) at Step 1.5; confirm Pencil MCP per sub-agent or degrade to sequential
- [ ] 4.3 Explicit "this agent never writes taste — the orchestrator does" directive; return variants + machine-readable selection-candidate

## Phase 5 — Orchestrator write path

- [ ] 5.1 `plugins/soleur/skills/brainstorm/SKILL.md` Phase 3.55b approve branch → call helper with design context + approved direction
- [ ] 5.2 `plugins/soleur/skills/plan/SKILL.md` Phase 2.5 §4b approve branch → same

## Phase 6 — ADR + C4

- [ ] 6.1 Author `ADR-087-context-keyed-taste-profile-and-agent-surface-injection.md` (rich; full-slug ref to ADR-086-declarative; 3 decisions; flag 086 collision out-of-scope; note fan-out below C4 line)
- [ ] 6.2 `model.c4`: `agents -> kb "Reads"` → `"Reads/writes"`
- [ ] 6.3 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`

## Phase 7 — Verify (ACs)

- [ ] 7.1 AC1 shared anchor grep=1 in both files
- [ ] 7.2 AC2 `git ls-files --error-unmatch` + direct hook-invocation grep for `taste-profile.md`
- [ ] 7.3 AC3–AC9 per plan (agent read-not-write, contradiction scoping, token rejection, recency-no-decay, freshness, end-to-end per surface, `--validate` wiring)
- [ ] 7.4 AC10 helper + FR6 tests pass
- [ ] 7.5 AC11 C4 edge string + tests; AC12 ADR; AC13 no component drift
- [ ] 7.6 File deferred issues (axis decomposition, negative-evidence, web-Concierge port, 086 renumber)
