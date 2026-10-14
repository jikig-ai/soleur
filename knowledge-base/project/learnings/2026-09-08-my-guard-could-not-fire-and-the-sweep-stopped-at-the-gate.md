---
name: 2026-09-08-my-guard-could-not-fire-and-the-sweep-stopped-at-the-gate
description: Reviewing the fix for a stale CI constant found the same defect class four times inside the fix's own guard code, and the correction sweep stopped at the executable line while the operator-facing runbook kept the false claim.
category: build-errors
module: apply-sentry-infra
tags: [ci, guards, mutation-testing, errexit, pipefail, stale-constants, review]
issues: [7865, 7866]
date: 2026-09-08
---

# Learning: a fix PR's verification is where the class it closes recurs

## Problem

`apply-sentry-infra.yml`'s AC17 step decides whether a Sentry apply was PARTIAL —
`byok-art-33-breach` is among the 27 paging rules it guards, and its silence stops a
GDPR Art. 33 72-hour clock from starting. The step asserted a hardcoded `27` and `2`.
It red-failed three healthy applies on `main` over two days (#7865), each time filing a
p1 saying "assume a partial write". PR #7866 replaced the literals with counts derived
from the `.tf`.

Review of that fix found **four merge-blocking defects in the guard code the fix itself
added**, plus two pre-existing ones it inherited.

## Solution

### 1. The new guard could not fire

`grep` exits 1 on no match. Actions runs a bare `run:` as `bash -e {0}`, so errexit is
INHERITED, and `set -o pipefail` promotes it out of a pipeline. All four
`VAR=$(grep ...)` assignments therefore killed the step whenever a count was
legitimately zero — before the summary table, before any annotation.

Measured against the shipped bytes: a genuine partial adoption whose state held no
`sentry_issue_alert` exited 1 having printed **nothing**, and the `if: failure()` filer
then opened a p1 with nothing naming why. The brand-new non-vacuity floor
(`if [[ "$exp_alert" -lt 1 ]]; then echo "::error::…the anchor broke…"`) was unreachable
dead code in precisely the case it was written for.

The same file documents this exact trap ~90 lines above, for a sibling step. The lesson
was written down and not applied.

**Fix:** inline `{ grep … || true; }` rescues at each site.

### 2. A count comparison cannot detect an orphan

Config declaring `sentry_alert.a` against a state holding `sentry_alert.zzz_orphan`
scored **rc=0**, with the summary printing `1 | 1` as evidence of health. The step is
named "no orphan" and the failure filer promises "with no orphan"; neither was true.

**Fix:** compare sorted address SETS (`LC_ALL=C comm`), and name both sides in the
error — `DECLARED BUT ABSENT FROM STATE` / `IN STATE BUT NOT DECLARED (orphan)`.

### 3. The correction sweep stopped at the executable line

The step's `name:`, its header comment, the filer's rationale comment and — worst — the
filer's **issue body** all still said "27 + 2". That body is what an operator reads
during a suspected paging outage, and it told them a healthy 27/3 is "a partial adoption
and the highest-priority thing in the repo".

Correcting the gate and not the runbook **moves** the false alarm rather than removing
it, and is worse than correcting neither: before the PR all five sites agreed and were
uniformly wrong; after it, the gate disagreed with four prose sites including the one an
operator acts on.

**Fix:** delete the literals rather than update them, and point at the run's own derived
summary table. Any literal there re-acquires the same rot.

### 4. The prose narrative justifying the fix was wrong, and nobody checks prose

The comment claimed the `2` went stale when `git_data_boot_warning` "landed on main"
via #7772, and that the absorbing merge "updated the README and the T25 prose-count gate
and missed this one constant". Both refuted in seconds:

- `git merge-base --is-ancestor 0f39b7aa2 72ebe67b7` → **true**. It landed via PR #7805
  (`Refs #7772`) two days BEFORE the commit that wrote the `2` — whose own message counts
  three while its gate asserts two. The number was **wrong on arrival, not stale**.
- No "T25 prose-count gate" exists anywhere. The README correction is #7868, which landed
  after this branch's base.

The honest framing was strictly *stronger* support for deriving.

## Key Insight

**A fix is written while holding the defect in mind, so its verification inherits the
defect's framing.** Review the new assertions before the new code, and ask of each:
*name an implementation a reasonable engineer might write next that satisfies this while
violating the property.*

Three corollaries, each measured here:

- **A guard evaded by moving the command out of its window is the same defect one level
  up.** The repo already had T13 (`t_no_unbracketed_status_capture`) for this class, and
  its window matched only the bare-command-then-`rc=$?` shape — blind to all four
  `VAR=$(...)` lines. Widening it caught them. Then the first fix routed the counts
  through a `_lines()` helper and T13 went **green with the rescue stripped**, because it
  could no longer SEE the grep. Third pass: still blind to backslash-continued
  assignments, so stripping the rescue from the two-line `declared=$(` — the one whose
  death kills the whole derivation — survived while its four single-line siblings were
  caught. Enumerate the shapes the SUT actually contains before declaring a window closed.
- **A suite whose verdict reads its own counters is silenceable in one token.** Rewriting
  `_report`'s else-branch to `pass=$((pass + 1))` reported "8 passed, 0 failed" and exit 0
  with a real regression injected. The verdict must read something append-only, pushed
  BEFORE the branch, with a counters-vs-ledger conservation check and an EXACT (`-ne`,
  never `-ge`) row-count floor — none of them dispatched through the helper they backstop.
- **Nothing pinned the change.** Reverting the derivation to the literals left every suite
  in the repo green; the only thing that ever caught the wrong `2` was three live applies
  reding on `main`. A pin must EXECUTE the step's own bytes extracted from the shipped
  YAML — anchored on a step `id:` with uniqueness asserted, run under `bash -e`. A grep
  over the YAML for a spelling is satisfiable by the comment block the same PR adds
  (`cq-assert-anchor-not-bare-token`).

## Session Errors

- **A block-replacement left a superseded copy in place, and the suite stayed green.** My
  `end` anchor matched the first `exit 1\n fi` after `start` (the non-vacuity floor's),
  not the final comparison's, so the old count-comparison survived and the summary table
  was written twice. Green cases satisfy both copies and red cases exit at the first, so
  no behavioural row could see it. — Recovery: read the diff before committing, removed
  it, added row R9 asserting the step writes ONE summary table and emits ONE verdict, and
  mutation-proved R9. — **Prevention:** after any block replacement, assert the replaced
  region's distinctive tokens occur exactly once; a behavioural suite cannot see a
  duplicated no-op branch.
- **My first fix defeated the guard I had just widened.** — Recovery: removed the helper,
  inlined the rescues, added T13 SHAPE 3 for helper definitions. — **Prevention:** after
  widening a guard, mutation-test the GUARD against the fix, not only the fix against the
  guard.
- **The widened guard was still blind to multi-line assignments** (M3 survived). —
  Recovery: join backslash-continued lines before scanning. — **Prevention:** enumerate
  the syntactic shapes present in the SUT (single-line, continued, helper) and require a
  mutation row per shape.
- **The suite's verdict was silenceable from its counters.** — Recovery: append-only
  ledger + conservation + exact floor. — **Prevention:** never let the final gate read a
  number the assertion helper owns.
- **Temp filesystem exhausted** by subagent transcripts plus my mutation sandboxes; a
  command's stdout was lost to ENOSPC mid-run. — Recovery: deleted transcripts. —
  **Prevention:** reuse ONE sandbox directory per battery and delete it when the battery
  ends, rather than accumulating one per round.
- **`rm -rf` blocked on a protected path** because I had run `git init` inside throwaway
  sandboxes. — Recovery: targeted deletion of the contents. — **Prevention:** only
  `git init` a sandbox when the SUT actually derives its corpus from git; otherwise skip
  it, and it stays deletable.
- **A review agent read the stale branch** (20 commits behind `origin/main`) and reported
  stale-claim hits already corrected on main by #7868. — Recovery: re-derived the entire
  sweep against `origin/main` with `git show origin/main:<path>`. — **Prevention:** rebase
  BEFORE spawning the panel; a finding is a claim about a tree at a moment.
- **First `comm` prototype omitted `LC_ALL=C`** and reported "not in sorted order". —
  Recovery: added it to both operands. — **Prevention:** already covered by the repo's
  `t_b7_locale_collation` row; one-off.
- **First actionlint read was truncated by `head -40`**, so I could not tell whether my
  change added findings. — Recovery: measured `origin/main` vs HEAD by rule class
  (result: +1 benign `SC2016:info` on an edited printf, and the 2 `SC2035` the PR had
  added are gone). — **Prevention:** never `head` a lint baseline you intend to diff.

## Tags

category: build-errors
module: apply-sentry-infra
