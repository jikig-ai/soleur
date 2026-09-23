# Tasks: mattpocock/skills audit bundle B4/B10/B12b

Plan: `knowledge-base/project/plans/2026-09-23-feat-mattpocock-audit-b4-b10-b12b-bundle-plan.md`

## 1. Setup

- [ ] 1.1 Confirm the four targets have not drifted on `origin/main`:
  `git diff HEAD origin/main -- plugins/soleur/skills/brainstorm plugins/soleur/skills/brainstorm-techniques plugins/soleur/skills/compound plugins/soleur/commands`.
- [ ] 1.2 Run `node plugins/soleur/skills/eval-harness/scripts/eval-gate.cjs --check <file>` for
  each target. All four must print `"gated":false`.

## 2. Core Implementation

- [ ] 2.1 B4: in `plugins/soleur/skills/brainstorm/SKILL.md` §1.2, replace the exit line with the
  Dialogue discipline block and the new exit condition (plan Implementation §1).
- [ ] 2.2 B4: in `plugins/soleur/skills/brainstorm-techniques/SKILL.md`, replace the
  `**Exit Condition:**` line (plan Implementation §1).
- [ ] 2.3 B10: in `plugins/soleur/skills/compound/SKILL.md` Phase 1.5, insert step 3.6. The
  paragraph lead is followed by a blank line and non-indented bullets.
- [ ] 2.4 B10: edit steps 4, 5 and 7 and `### Empty Case` as the plan prescribes. Do not touch
  step 8.
- [ ] 2.5 B12b: add the byte-identical `HOW THE SKILLS FIT TOGETHER:` block to the Claude Code,
  Devin CLI and Grok Build blocks in `plugins/soleur/commands/help.md`. Place it between WORKFLOW
  SKILLS and AGENTS, with no `operator-*` token and no new `### ` heading.

## 3. Testing and Verification

- [ ] 3.1 Run the checks for AC1 to AC6 from the plan: anchors, line order, the Empty Case,
  markdownlint on compound, map parity, scope and eval-gate.
- [ ] 3.2 Check that AC7 passes: the bun suites (components, invocation-axis, harness-parity,
  workflow-fidelity), `bash scripts/lint-agents-compound-sync.sh`, and
  `bash scripts/markdown-lint.sh` on all four files.
- [ ] 3.3 Run the discoverability probe
  `grep -c -e 'Null-guardrail check' plugins/soleur/skills/compound/SKILL.md`. It must print `1`.
- [ ] 3.4 Write the PR body per AC8: say it is the B4/B10/B12b bundle, cite `#8284` with `Ref`,
  and note that `#8648` owns the `competitive-intelligence.md` update. Fold in
  `decision-challenges.md`.
