# Tasks: API-budget operator preamble backport

**Plan:** [../../plans/2026-05-15-feat-api-budget-preamble-backport-3819-plan.md](../../plans/2026-05-15-feat-api-budget-preamble-backport-3819-plan.md)
**Spec:** [spec.md](./spec.md)
**Issue:** #3819 · **Draft PR:** #3839 · **Branch:** `feat-api-budget-preamble-backport-3819`

---

## Phase 0 — Preconditions (read-only)

- [ ] **0.1** Re-measure pre-PR `B_ALWAYS` and record as `B_ALWAYS_PRE`:
  ```bash
  B_INDEX=$(wc -c < AGENTS.md); B_CORE=$(wc -c < AGENTS.core.md); B_ALWAYS_PRE=$((B_INDEX + B_CORE)); echo "B_ALWAYS_PRE = $B_ALWAYS_PRE"
  ```
- [ ] **0.2** Verify canonical disclosure prose at `plugins/soleur/docs/pages/goal-primitive.md` §"What it consumes" still contains `disclaims warranty for runtime cost`.
- [ ] **0.3** Confirm `<decision_gate>` is absent from drain-labeled-backlog, resolve-todo-parallel, resolve-pr-parallel, work, one-shot SKILL.md files:
  ```bash
  grep -l "<decision_gate>" plugins/soleur/skills/{drain-labeled-backlog,resolve-todo-parallel,resolve-pr-parallel,work,one-shot}/SKILL.md
  ```
  Expected: zero matches.
- [ ] **0.4** Re-run code-review overlap check; confirm the 6 acknowledged issues are still no-conflict.

## Phase 1 — Disclosure blocks in 6 SKILL.md files

- [ ] **1.1** `plugins/soleur/skills/test-fix-loop/SKILL.md` — merge API-budget preamble into existing `<decision_gate>` block at lines 42-46.
- [ ] **1.2** `plugins/soleur/skills/drain-labeled-backlog/SKILL.md` — insert new `<decision_gate>` after `## When to use`, before `## Prerequisites`.
- [ ] **1.3** `plugins/soleur/skills/resolve-todo-parallel/SKILL.md` — insert new `<decision_gate>` after the `> **Note:**` legacy blockquote.
- [ ] **1.4** `plugins/soleur/skills/resolve-pr-parallel/SKILL.md` — insert new `<decision_gate>` after the intro paragraph, before `## Workflow`.
- [ ] **1.5** `plugins/soleur/skills/work/SKILL.md` — insert new `<decision_gate>` after `## Input Document`, before `## Execution Workflow`.
- [ ] **1.6** `plugins/soleur/skills/one-shot/SKILL.md` — insert new `<decision_gate>` at the top of the body, before Step 0a.
- [ ] **1.7** Re-read each edited file after edit; verify the block landed inside the worktree (not the bare root).

## Phase 2 — New `hr-*` rule + index entry

- [ ] **2.1** Append new rule body to `AGENTS.docs.md` `## Hard Rules` section.
- [ ] **2.2** Add `- [id: hr-autonomous-loop-skill-api-budget-disclosure] → docs-only` to `AGENTS.md` `## Hard Rules` index in slug-alphabetical position.
- [ ] **2.3** Confirm rule ID is not in `scripts/retired-rule-ids.txt`:
  ```bash
  grep -F "hr-autonomous-loop-skill-api-budget-disclosure" scripts/retired-rule-ids.txt
  ```
- [ ] **2.4** Run `python3 scripts/lint-rule-ids.py` — must pass.
- [ ] **2.5** Run `python3 scripts/lint-agents-rule-budget.py` — expected rejection on B_ALWAYS until Phase 3 trim lands; re-run after trim.

## Phase 3 — `AGENTS.core.md` body-trim ≥67 bytes

- [ ] **3.1** Identify the trim site:
  ```bash
  awk '/^- /' AGENTS.core.md | awk '{print length, NR, $0}' | sort -rn | head -10
  ```
- [ ] **3.2** Trim ≥67 bytes of redundant `Why:` prose from one core rule. Preserve per-issue mechanism labels.
- [ ] **3.3** Re-measure: `B_ALWAYS_POST ≤ B_ALWAYS_PRE`.
- [ ] **3.4** Re-run `python3 scripts/lint-agents-rule-budget.py` — must pass after trim.

## Phase 4 — CI assertion

- [ ] **4.1** Edit `plugins/soleur/test/components.test.ts` per plan §10. If `readFileSync` isn't already imported, add `import { readFileSync } from "node:fs";` at top.
- [ ] **4.2** Run `bun test plugins/soleur/test/components.test.ts` — all existing + 6 new tests pass.

## Phase 5 — Verification + commit

- [ ] **5.1** Full test run: `bun test plugins/soleur/test/components.test.ts`.
- [ ] **5.2** Visual scan of each of the 6 SKILL.md files for correct rendering.
- [ ] **5.3** Single atomic commit:
  ```bash
  git add plugins/soleur/skills/{test-fix-loop,drain-labeled-backlog,resolve-todo-parallel,resolve-pr-parallel,work,one-shot}/SKILL.md \
          AGENTS.md AGENTS.docs.md AGENTS.core.md \
          plugins/soleur/test/components.test.ts
  git status --short
  git commit -m "feat: backport API-budget operator preamble to autonomous-loop skills"
  git push
  ```
- [ ] **5.4** Update PR #3839 body: ensure `## Changelog` section + `Closes #3819`. Apply `semver:patch` label.

## Phase 6 — Follow-up tracking

- [ ] **6.1** File deferred-scope-out issue: `chore: shrink AGENTS.md always-loaded payload under 22000 critical threshold` (milestone `Post-MVP / Later`, label `deferred-scope-out`).

## Out of scope for this PR

- Empirical per-skill cost telemetry (deferred per plan Open Question #2).
- Demoting `wg-*` rules from core to bring B_ALWAYS under 22000 (deferred per plan Open Question #1).
- Re-evaluating the hr-* rule + CI test against DHH's dissent (recorded per plan Open Question #4 for future override conversation).
