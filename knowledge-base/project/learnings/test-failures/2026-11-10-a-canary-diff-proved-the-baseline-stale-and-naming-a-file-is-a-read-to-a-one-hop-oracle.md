---
title: "A trivial-diff canary proved a stale oracle baseline — and to a one-hop TOKEN oracle, naming a file IS reading it"
date: 2026-11-10
category: test-failures
tags: [oracle, baseline, ratchet, canary, merge-group, kb-consumers]
related_issues: [12521, 12557, 12559, 12560, 9729]
---

# A canary diff proved the baseline stale; to a one-hop oracle, naming a file is a read

## What happened

The S4-retirement squash `b258336e` (PR #12521) merged green on a Friday. Canary PR
#12557 — a deliberate two-line comment-only diff — then failed BOTH required legs it was
armed to verify:

1. `test-affected-kb-consumers` flagged five `argv-code` violations charged to
   `scripts/ci-oracle-review` and failed check b1 (baseline != `--write-baseline` output).
2. `markdown-lint --repo-sweep` flagged MD032 at ADR-276:694 — a bullet the same squash
   added with no blank line after the `Notes:` paragraph.

The canary's whole purpose was to prove the post-apply producer set still covers all 11
required `merge_group` contexts. It never got there — it caught two main-line regressions
its own parent commit shipped.

## Root causes

- **Baseline drift**: `b258336e` added `ci-oracle-lane.{sh,test.sh}` names into
  `ci-oracle-review.test.sh` (fixture stub-docs + a `printf` line) but regenerated the
  baseline for the *deleted* `ci-pr-selection` rows only. The oracle's `argv_code_refs`
  runs `TOKEN.findall` over the suite file's **entire text — comments and heredoc fixture
  bodies included** — and follows one hop into every `*.sh`/`*.py`/`*.ts` path that exists
  on disk. Naming `ci-oracle-lane.test.sh` therefore charges your suite with every
  `knowledge-base/…` literal inside the lane files (`zzleak-*` fixtures, the
  `O-DIAGRAMS-FLAG` case arm).
- **MD032**: the amendment bullet landed adjacent to a paragraph; `--repo-sweep` lints the
  whole corpus, so the escape was invisible to any changed-files-only lint.

## The fix (PR #12560)

Five two-column `label<TAB>path` rows — NOT four-column `false-positive:` rows. The
suite's contract (`test-affected-kb-consumers.test.sh` §BASELINE): argv-code rows carry no
classification column; a 4-column argv-code row fails check b1. The issue's own wording
(`false-positive: <reason>`) was wrong for this row shape — the plan had to reconcile the
ask against the contract, and the rationale moved into the commit message.

## Learnings

1. **Any change to a file an oracle scans is a change to the oracle's input.** Regenerate
   the baseline in the same commit, or the *next* PR pays for it — the suite diffs the
   committed baseline against live `--write-baseline` output, so drift fails a stranger's
   diff, not yours.
2. **To a one-hop TOKEN oracle, naming a file is a read.** Quoting a `*.sh` path in a
   comment, fixture heredoc, or stub doc charges your suite with that file's entire
   `knowledge-base` literal set. Assembling the name (`'ci-pr-'affected-replay.py'`) is
   the established dodge when the naming is cosmetic — but here the names are the
   fixture's contract, so the baseline row is the honest record.
3. **A comment-only canary is cheap live proof.** Two lines of markdown exercised the
   whole required-check set and caught what the parent PR's own green run missed —
   because the parent's run predated its own baseline-affecting content.
4. **`cmd | tail; echo RC=$?` reports tail's exit, not the command's.** The affected gate
   printed `reason=failed` while my `GATE_RC` read 0. Read the summary line; `$?` after a
   pipe is the last filter's status.

## Session Errors

- Enumeration (`--print-selection`) and `test-all.sh --affected` each ran ~25–33 min under
  load ~40 — the known contention class, not a defect.
- `skill-security-scan` calibration exceeded its 180s cap under the same load (43s
  baseline, ~4× headroom) — filed #12583.
