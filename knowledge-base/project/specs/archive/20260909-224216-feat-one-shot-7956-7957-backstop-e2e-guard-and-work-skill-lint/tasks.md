# Tasks — correct work/SKILL.md's notification clause, reconcile #7956

Derived from
[`knowledge-base/project/plans/2026-09-09-fix-backstop-walk-equivalence-and-work-skill-notification-clause-plan.md`](../../plans/2026-09-09-fix-backstop-walk-equivalence-and-work-skill-notification-clause-plan.md).

**Read before starting:** the plan's `## Overview` and `## Research Reconciliation`. Both issues'
filed diagnoses moved under verification, and one issue is descoped. Do not implement #7956.

**Standing rule for every verification below:** take verdicts from a redirected log's own `RC=` line.
Never a pipe, never a background task's completion notification. This PR's subject is that the
notification's exit code is the last command in the backgrounded string.

## Phase 1 — Setup

- [x] 1.1 Confirm the worktree and branch:
      `feat-one-shot-7956-7957-backstop-e2e-guard-and-work-skill-lint`.
- [x] 1.2 Baseline the linter before editing:
      `bash scripts/markdown-lint.sh plugins/soleur/skills/work/SKILL.md` → expect
      `markdown-lint: 1 file(s) clean.` Record it.
- [x] 1.3 Baseline AC6's checker (plan `## Acceptance Criteria` → AC6) → expect exit 0 and
      `PRESERVED: ['## ', '### ', 'attr = ', 'bash ']`.

## Phase 2 — Core implementation (#7957)

- [x] 2.1 Apply hunk 1 to the wrapper-as-guard paragraph in
      `plugins/soleur/skills/work/SKILL.md` — the replacement of the "Three rules:" sentence,
      **verbatim** from `gh issue view 7957`. The embedded `#7912` is literal file content, not a
      work target.
- [x] 2.2 Apply hunk 2 — the `**Why:**` addition ending
      `a reaped task does not imply a reaped process tree.` — also verbatim.
- [x] 2.3 Correct the Prevention bullet of
      `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`,
      which states the same false claim and is the file the corrected paragraph cites. Correct the
      **prescriptive rule**; leave the session narrative intact.
- [x] 2.4 Update
      `knowledge-base/project/learnings/2026-09-08-the-rule-propagated-the-distrust-stopped-at-commands-i-wrote.md`
      so its Prevention section records that the correction landed. Both of its current statements
      go stale on merge: the clause is now applied, and #7955 already cleared the markdownlint
      blocker it names.

## Phase 3 — Reconcile #7956 (no code)

- [x] 3.1 Run the in-flight probe **first** — the step whose absence produced the plan's first draft:
      `gh pr list --state open --search "memory-backstop"` and
      `gh issue list --state open --search "memory-backstop.test.sh in:title,body"`.
      Confirm PR #7879 is still open and #7886 still names the same defect. If #7879 has merged,
      verify the fix on `main` instead.
- [x] 3.2 Comment on #7956: it duplicates **#7886**; **PR #7879** implements the fix by deleting the
      second walk rather than aligning two; its "Fix, in preference order" is inverted — option (1)
      is a no-op because the arm is already inside the guard, and the measured mechanism is that the
      *hook's* walk fails while the suite's succeeds. Include the depth probe (hop 8 → found,
      hop 9 → `NOT_FOUND`).
- [x] 3.3 Close #7956 as a duplicate of #7886 (or close #7886 into #7956 if the better-diagnosed
      record is preferred). Leaving both open is not an option.
- [x] 3.4 File the residue issue against the post-#7879 file, labelled `code-review`, cross-linking
      #7208 §B. *(Amended 2026-09-09: two of the four Phase 2.4 items were REFUTED against #7879's head and deliberately not filed; #8008 lists the two that survived plus a scope note recording the refutations.)* The original four read: six arms still marked at declaration;
      `passes` never asserted; the uncorrelated `tail -1` ledger read; `disabled` and
      `no_terminal_scope` still hard-failing.
- [x] 3.5 **Do not edit any file under `.claude/hooks/`.** AC11 checks this mechanically.

## Phase 4 — Testing and verification

- [x] 4.1 AC1/AC2 — anchor greps over the edited paragraph.
- [x] 4.2 AC3 — full-class sweep `grep -rn 'infer from a tail' --include=*.md .`; disposition the
      `2026-05-20-long-running-bench-verify-process-before-relaunch.md` hit in the PR body (expected
      scoped out: its claim is about *liveness*, not *verdict*).
- [x] 4.3 AC4 — linter clean **after** the edit.
- [x] 4.4 AC5 — `git diff -U0 -- plugins/soleur/skills/work/SKILL.md | grep -c 'markdownlint-disable-line MD038'`
      returns 0.
- [x] 4.5 AC6 — run the rendered-content checker; then demonstrate RED-ability by removing the
      trailing space from one span and confirming it exits 1 naming that site. Restore. Record both.
- [x] 4.6 AC11 — `git diff --name-only origin/main...HEAD` contains no `.claude/hooks/` path.
- [x] 4.7 AC12 — `bun test plugins/soleur/test/` and `bash scripts/markdown-lint.sh --repo-sweep`,
      both green, verdicts read from redirected logs.

## Phase 5 — Ship

- [ ] 5.1 PR body: `Closes #7957`. **Not** `Closes #7956` — that issue is resolved by dedupe and by
      #7879, not by this diff (AC13).
- [ ] 5.2 PR body records the premise corrections (AC14) and carries the AC6 measurement table plus
      the plan's `## Appendix — the 12 violations and how #7955 repaired them`.
- [ ] 5.3 Render `knowledge-base/project/specs/<branch>/decision-challenges.md` into the PR body and
      file the `action-required` issue for UC-1 (the #7956 descope is a User-Challenge — the operator
      asked for both issues shipped).
