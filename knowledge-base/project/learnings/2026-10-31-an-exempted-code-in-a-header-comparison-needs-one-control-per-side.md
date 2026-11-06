# Learning: an exempted code in a header-vs-emit comparison needs one control per side, and a guard map must list what it cannot see

## Problem

The restore-engine W9 check compared the engine's header table against the exit codes its `die N` / `exit N` sites emit, but dropped exit code 1 from BOTH sides with `grep -vx 1`. The header gained a row for 1 and the engine has twelve `die 1` / `exit 1` sites, yet deleting the header row, or every site, turned nothing red. Four comments around it (the shared header lib, the pull-path-health message, a hook-test reason string, the wiring suite's header) still described a world where nothing covered computed exits or a seventh header row.

## Solution

- Removed both filters so 1 is compared like any other code. The `{1} ∪ header` union stays only for the *tested* population, as a defence.
- Added one control per side (`eng-hdr-row1-removed` deletes the header row; `eng-emit-sites1-removed` rewrites the live sites), each with a failure-only "mutation landed" check so a landed control adds exactly one passing row (89 → 91 on `EXPECTED_ASSERTIONS`).
- Wrote the controls and the engine-suite wording assertion BEFORE the fix and recorded the RED counts (89/2 and 98/1), then took both pins from a GREEN run, never from arithmetic.
- Fixed the five stale comments, and one engine message whose "Nothing was copied" overclaimed (earlier entries stay in the sink).

## Key Insight

A comparison that exempts a value from both sides is a guard with a hole exactly the size of the exemption, and one mutation per side is the smallest battery that proves the hole is closed: a one-sided filter reds the real-tree row AND the other side's control, so a reviewer can tell which side regressed. The structural-enumeration seat also showed what the repaired guard still cannot see (`return N`, errexit and implicit exits, `die`/`exit` words that are text in a trailing comment, heredoc or dead branch, and code 0). Naming those in the suite's "NOT covered" list is the cheap part of making the claim true; the rest is documented residue, not a defect this PR introduced.

## Session Errors

1. **The first `soleur:one-shot` args cited the closed umbrella issue as `#9757`**, so Step 0a.5's closed-issue gate aborted before any work. Recovery: re-invoked with the number replaced by "the number on the Ref line of the open tracker's body". **Prevention:** when an operator brief demands a `Ref #<closed>` line in the PR body, pass the *location* of that line (the open tracker's body) to `soleur:one-shot`, never the literal; scrub every `#N` in constructed args against `gh issue view --json state` first.
2. **`git commit -F` was given a mangled scratch path** (rc 128, nothing committed). Recovery: retried with the correct path. **Prevention:** write the message file and run the commit in one Bash call, echoing the path.
3. **The planning subagent's ruling row put an unescaped `|` inside a sed expression**, which `technical-ruling-gate.sh` rejects as a four-cell row. Recovery: escaped it. **Prevention:** already mechanically gated by `technical-ruling-gate.sh`; no new rule.
4. **A `cut -c1-200` on the engine diff hid the trailing ` ;;`** on the reworded `die 2` line, which read as a dropped case terminator. Recovery: re-read the line's tail (`rev | cut`), then confirmed by the security seat's `cat -A` and `bash -n`. **Prevention:** never truncate a diff line you are about to judge for syntax; show its tail.

## Tags

category: test-failures
module: registry-restore-engine
