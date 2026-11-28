---
title: A CLI hint on stderr switched off every OPEN arm of the merge poll
date: 2026-11-28
category: workflow-issues
module: ship, merge-pr, sync-pr-behind, ship-kb-archive-gate, ship-operator-step-gate, pr-merge-poll
tags: [gh-cli, stderr, merge-poll, required-check, cla-evidence, ship-kb-archive-gate, arm-check]
issue: 12697
pr: 13112
---

# Learning: a CLI hint on stderr switched off every OPEN arm of the merge poll

Three defects surfaced while landing the Scope Grants phone-width e2e PR (#13017, merged
2026-11-25 as 19e48ec44e). Each one alone was a nuisance. Together they meant the poll could not
see the problem, and the documented way to arm the merge was refused.

## 1. Folding stderr into a parsed value breaks the day the CLI adds a hint

`gh` 2.106.0 (2026-11-25) prints an 8-line "use `gh event listen` instead of polling" hint on
**stderr** for every `gh pr view` (and `gh run view` of a PR run). Exit code stays 0, and the hint
is written **before** stdout. No env var or config turns it off.

The Phase 7 poll captured `s=$(gh pr view … 2>&1)`. The captured state therefore began with
`hint:`, and every exact comparison died:

| Arm | Predicate | Under the hint |
|---|---|---|
| terminal break | `grep -qE "^(MERGED\|CLOSED\|fetch-error)"` (line-wise) | still fires |
| queue-state / dequeue read | `$s == OPEN*` | never runs |
| BEHIND auto-sync | `$s == "OPEN BEHIND"` | never fires |
| #11544 required-set read | `$s == "OPEN BLOCKED"` dwell | never counts |

Only the arm that ends the poll kept working, so nothing looked broken. The poll just
heartbeated.

The same capture sat in `sync-pr-behind.sh` standalone mode, where a multi-line `head_ref` made the
manual recovery command exit 12 `kind=wrong_branch`, and in `ship-operator-step-gate.sh`, where an
unreadable answer fell to the fail-closed hold.

**Rule:** stdout is the answer and stderr is a diagnostic. Read stdout only, send stderr to a
file, and use the file only on the failure path (`fetch-error: <first non-hint line>`). A
`2>"${GH_ERR:-/dev/null}"` default keeps `gh` running if the temp file cannot be made (an empty
`2>""` redirect fails and `gh` never runs). A scan in `plugins/soleur/test/pr-merge-poll.test.ts`
now fails CI on any new `$(gh … 2>&1)` capture outside a shrink-only exclusion list.

## 2. The missing-required-check arm already existed, and defect 1 hid it

PR #13017's `cla-evidence` `pull_request_target` run on the final head was cancelled about 20 s
after it started. Its concurrency group `cla-evidence-<PR#>` is shared with the `issue_comment`
trigger, so a comment run replaced the pending head run (tracked separately as #13115). The
required context had no run on the head, and a manual rerun recovered it.

The brief asked for a new poll arm that compares required contexts to the head's check runs. One
already exists: `ci-head-verdict.sh required`, read through `required-set-report.sh` once the PR
is OPEN BLOCKED, armed, not queued and full-decided for 10 ticks. Its header names this exact
class. It never fired because defect 1 made `OPEN BLOCKED` impossible to observe.

**Rule:** before adding a detector, check whether one exists and is merely unreachable. The fix
added fixture rows (H1/H1f) with the hint on stderr proving the existing arm reaches
`[ship.phase7.required_set] state=absent`, and changed none of its predicates.

## 3. A gate that refuses the documented command teaches agents the unsafe one

`ship-kb-archive-gate.sh` refused the locked arm block every skill documents for three independent
reasons:

| Command | Before | After |
|---|---|---|
| `gh pr merge <N> --squash --auto` | allowed | allowed |
| `… with_lock merge-main 600 -- gh pr merge --squash --auto --match-head-commit <40-hex>` | allowed | allowed |
| `gh pr merge <N> … --match-head-commit <40-hex>` | denied: extra operands | allowed |
| `gh pr merge <N> … --match-head-commit "${H:?…}"` | denied: names no 40-hex sha | allowed (head censused by number) |
| documented lock block plus degrade-open `else` (two identical invocations) | denied: more than one invocation | allowed |
| two invocations that differ in number, SHA, operand or prefix | denied | denied |
| `"${H:-x}"`, `"$@"`, `"${!H}"`, nameref, second positional | denied | denied |

The brief blamed the `--` passthrough. Measuring showed the passthrough was always accepted, and
the PR number next to `--match-head-commit` drew the "extra operands" deny. Agents denied on the
documented form fell back to the flag-only form, which keeps the lock only if they remember it.

`--match-head-commit` can only restrict a merge, so every newly admitted command merges nothing
that `gh pr merge <N> --squash --auto` did not already admit. The same change closed two older
fail-opens on the paths the new rules feed: the census read died silently under `set -eo
pipefail` when `ls-remote` failed (G2), and the foreign-repo exit fired on text that pointed `gh`
nowhere, such as `; : GH_HOST=…` (G1).

**Rule:** when a gate and the docs disagree, measure which clause actually fires before choosing a
side, and give the test the documented text extracted verbatim from the skill files, never a
hand copy.

## How they interlock

The hint disabled the required-set arm that would have named the cancelled check. The gate's
refusals pushed agents onto the unlocked or hand-edited form at the very step where the poll
should have been watching. Each defect alone was recoverable by hand. Together, the poll looked
healthy and the documented recovery was refused.

## Timeline (2026-11-25, UTC)

- 13:33:52 an `issue_comment` run of `cla-evidence` is created in the shared concurrency group.
- 13:33:53 the head's `pull_request_target` run (45624818815, attempt 1) is cancelled before any
  job starts.
- 14:16 a manual rerun (attempt 2) passes.
- 15:19 #13017 merges.

## Session Errors

- **The brief named the wrong mechanism for defect 3** ("rejects the `--` passthrough"). Recovery:
  the plan measured the gate with PreToolUse JSON before designing the fix. Prevention: measure a
  gate's verdict per clause before accepting a brief's attribution.
- **The brief asked for a detector that already existed.** Recovery: the plan traced the existing
  #11544 arm and found it unreachable rather than missing. Prevention: grep the detector's marker
  family before adding a new arm.
- **The plan missed a pin on the doc text it edited.** `arm-check-sites.test.sh` hard-codes the
  dequeue arm (`DQ_ARM='gh pr merge "$N" …'`), so the planned `<pr-number>` edit made its mutation
  rows fatal. Recovery: the lead updated the pin in the same batch. Prevention: before editing doc
  text, `git grep -lF` the exact old string across `*.test.*`, not only the file's basename.
- **Parallel agents crossed a repo-global ratchet.** One agent's new unguarded fixture writes moved
  `fixture-relative-assert`'s P1a count, and two other agents reported it as a red they did not own.
  Recovery: the owning agent added `assert_fixture_dir`. Prevention: the fan-out brief already
  lists the ratchets; each agent should re-run them after its last edit, not only mid-task.
- **Two delegates parked on their own background watchers** and reported "waiting" for many rounds.
  Recovery: a `SendMessage` asking for a foreground run and a final report. Prevention: the spawn
  prompt said "foreground"; a long suite pushed to the background by the harness still needs the
  delegate to block on it rather than end its turn.
- **The lead bulk-toggled `tasks.md` checkboxes**, marking the PR-body and arm tasks done before
  they ran. Recovery: unmarked them immediately. Prevention: tick each box only when its own command
  has run.

## Tags

gh-cli, stderr, merge-poll, required-check, ship-kb-archive-gate
