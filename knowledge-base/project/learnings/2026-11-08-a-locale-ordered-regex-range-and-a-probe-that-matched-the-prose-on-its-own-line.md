# Learning: a locale-ordered bash regex range, and a probe that matched the prose sharing its line

## Problem

Adding a `headCommit.oid == run head_sha` correlation arm to `merge-queue-stall-check.yml` (#12320, PR #12350) shipped two guards that read as safe and were not.

1. The oid validation `[[ "$oid" =~ ^[0-9a-f]{40}$ ]]` is the only defence against empty-equals-empty. In bash 5.3 under `LC_ALL=en_US.utf8` it ACCEPTED 39 hex digits plus an accented `e`, because the `[0-9a-f]` range follows the locale's collation order. It rejects the same string under `C` and `C.UTF-8`. A GitHub-supplied oid is always ASCII hex, so nothing could exploit it, but the comment above the check called it "the only defence" and it depended on the runner's locale.
2. The follow-through probe for the pre-existing `headSha` gap grepped the Triage step 2 line for `headSha`. That physical line also carries the prose "correlate ... by headSha/createdAt", so the probe exited 0 (PASS, which would have auto-closed the tracker) on the unfixed tree. A fixture control that ran the probe on the REAL file caught it; the suite never looks at probes.

## Solution

- `local LC_ALL=C` as a function-local statement before the regex (restored on return), plus a suite row run under `LC_ALL=en_US.utf8` (new `CASE_LC_ALL` env word in `run_case`) and a mutant that deletes the pin. The mutant is killable only where the locale exists, so on CI with no `en_US.utf8` the suite FAILS instead of skipping.
- The probe now requires exactly ONE matching Triage line and tests the comma-separated `--json` field list (`case ",$fields," in *,headSha,*`), never the whole line. Controls: real tree exits 5, a fixed copy exits 0, a `headShaX` lookalike exits 5, a decoy comment quoting the command exits 3, an empty file exits 3.
- Equality is byte-equality: rows for a last-character near miss, `oid + 1 char`, and the upper-case oid, with mutants for a truncated, case-folded and prefix compare. A widened class (`[0-9a-z]`) is pinned by 40 lowercase non-hex letters.

## Key Insight

A bash regex range is a claim about the LOCALE, not about ASCII: pin `LC_ALL=C` for any security-relevant `[[ =~ ]]` validation (`[0-9a-f]`, `[A-Za-z]`), and fixture a non-ASCII letter under a collating locale. And a probe that tests a LINE for a token must first prove the token cannot also occur in the surrounding prose of that line: parse the field, and run the probe once against the real file expecting the UNFIXED answer before trusting its PASS arm.

## Session Errors

1. **Planning subagent's scripted edit deleted plan sections, and it ran a stray `sleep 1`** — Recovery: gates returned zero counts, sections rebuilt. **Prevention:** assert the anchor count before a scripted multi-edit (already in work/SKILL.md); no `sleep` in Bash.
2. **`technical-ruling-gate.sh --branch` rejected 5 decision rows** (a parenthetical between the date and the colon, `REVOKED ...` as the first word, and an unescaped `||` inside a table cell splitting the row) — Recovery: reworded rows, escaped `\|\|`. **Prevention:** write each ruling cell as `Ruled by CTO agent, <date>: <decision> - <rationale>` exactly, and escape pipes in cell text.
3. **A second Monitor was armed on the same target** (the hook named the duplicate) and the test-design seat's own wait timer produced a stream of notifications — Recovery: `TaskStop` on both. **Prevention:** one monitor per target; stop a seat's leftover background loop once its report is in.
4. **`git stash list` in a Bash call was hook-denied, and an unguarded `rm -f "$D/$W"` was blocked by the dangerous-rm check** — Recovery: dropped the stash probe; rewrote with `"${D:?}/${W:?}"`. **Prevention:** never include `git stash` in any call; write scratch cleanups with `${VAR:?}`.
5. **The follow-through probe returned PASS on the unfixed tree** (the prose shares the line with the command) — Recovery: parsed the `--json` field list and required exactly one line. **Prevention:** run any new probe against the real file expecting the unfixed verdict, plus a lookalike and a decoy-comment fixture, before filing the tracker.
6. **A header comment I wrote cited an "earlier caveat that an unrelated broken push could be named"; no such caveat exists in the file** (five review seats flagged it) — the phrase came from the brief, not the code. Recovery: reworded to a self-contained sentence. **Prevention:** for every sentence a diff adds, name the command that falsifies it before writing it (inherited-framing rule, Phase 0.5).
7. **The brief said "no live failed-load push run existed"; run 42336368201 is one** — Recovery: the plan corrected it with observed / transitive / not-observed tiers. **Prevention:** re-measure a resume brief's "measured" facts before building on them.
8. **The first `gh issue create` for the scope-out was refused by the filing hook** (no user-visible consequence named) — Recovery: added `--label meta/machinery`. **Prevention:** a finding about Soleur's own verification machinery files with `meta/machinery` from the start.
9. **`grep-q-pipe-guard.test.sh` failed once on its own SIGPIPE probe under load average 33, then passed twice** — one-off flake, not caused by the diff (its derived-triple count was unchanged). **Prevention:** re-run an unrelated guard before attributing a red to the diff.
10. **An accidental `cd` into the bare repo root moved the primary working directory** — Recovery: returned to the worktree before any write. **Prevention:** chain read-only `gh` probes without `cd`.

## Tags
category: logic-errors
module: merge-queue-stall-check
