# Tasks: WikiSkill Phase 3 - ship PURPOSE.md (eval-gate first)

Plan: `knowledge-base/project/plans/2026-10-23-feat-wikiskill-phase-3-ship-purpose-md-plan.md`
Issue: #10551 (`Ref` only). Draft PR: #10947. Verdict at plan time: the gate fails, so this run stops
after the finding. Do not edit `plugins/soleur/skills/ship/SKILL.md` and do not create
`plugins/soleur/skills/ship/PURPOSE.md`.

## Phase 1: Re-verify the gate

- 1.1 From `plugins/soleur/skills/eval-harness` run the three probes in the plan's Test Scenarios
  (`--check ../ship/SKILL.md`, `--dry-run --target ship --repeat 3`, and the `incident-threshold`
  control), each with its exit code.
- 1.2 Outcome unchanged: continue. Control fails or errors: post no comment, leave the PR draft, report the broken probe.
  A negative probe flipped: note "gate flipped" in the PR body, post no "cannot" comment, report it.

## Phase 2: Record the finding

- 2.1 Post the self-contained comment on #10551 (its text is the live comment; marker
  `<!-- wikiskill-p3-gate:2026-10-23 -->`, skip if already present, retry once, fallback is a
  `## Gate Finding` section in the PR body; never a new issue).
- 2.2 Verify the marker with `gh issue view 10551 --json comments`.

## Phase 3: Commit and hand off

- 3.1 Commit the plan, this file and `decision-challenges.md`; the PR title is
  `docs(kb): record eval-harness gate finding for ship PURPOSE.md (Ref #10551)`; the body has
  `Ref #10551` and no closing keyword.
- 3.2 Run the plan's Acceptance Criteria commands, including
  `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` and markdownlint.
- 3.3 Hand off to review and ship (T6 merges this docs-only PR). Capability PR (C) and Move PR (M) are
  not part of this run.
