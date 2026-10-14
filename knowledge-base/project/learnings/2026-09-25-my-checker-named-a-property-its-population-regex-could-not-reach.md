---
title: "My checker named a property its population regex could not reach"
date: 2026-09-25
category: test-failures
module: .claude/hooks test suites
issue: 8616
pr: 8768
tags: [guard-contract, mutation-testing, path-farm, anti-vacuity, hook-suites]
---

# My checker named a property its population regex could not reach

## Problem

#8616: the hook test suites under `.claude/hooks/` opened with `command -v jq … || { echo "SKIP"; exit 0; }`,
so on a host without the tool every one of them reported green having asserted nothing. The fix converted
40 guards to `UNRESOLVED: <tool> missing … ; exit 3` and added `.claude/hooks/hook-suite-dep-unresolved.test.sh`.
That checker runs each guarded suite on a PATH farm with the tool removed and requires a not-green verdict
naming the tool. It also carries a static sweep for skip-then-`exit 0`.

The author's 17-row mutation battery passed. A nine-seat review then found 12 surviving mutants and four hook
suites that were **still green with a tool missing**:

- `grep-q-pipe-guard` and `new-scheduled-cron` without git;
- `session-rules-loader-headless` without `script`;
- two arms (`hook-input-contract`/python3 and `pre-merge-rebase-parity`/python3) that were red only
  because an assertion floor happened to sit one above the python3-less count.

The checker's header claimed "no hook suite reports green when a tool it guards is absent". What it
actually checked was far narrower.

## Root cause

Every miss was one gap: **the population and the verdict machinery were narrower than the stated
property.** Four instances, each invisible to a battery that mutated one axis (the canonical `||` guard):

1. **Population regex.** It matched `… ||` and `if !` only. The positive form
   `if command -v X; then … else <skip>` and quoted tool names fell outside it. A one-line
   `if ! …; then …; exit 1; fi` was classified by looking at the NEXT lines, so an unrelated
   `else` further down made it an `arm` and relaxed its rc check.
2. **Sweep.** It tested `}` on the raw line rather than the variable-stripped one, so
   `echo "SKIP: ${X}"` read as "closes its own block" and the `exit 0` on the next line was never read.
   The lookahead also stopped at a comment line, and it did not recognise `exit "0"`.
3. **Self-test pinned COUNT, not CONTENT.** It asserted "each fixture derives exactly one pair" and never
   which tool or class. Collapsing every class to `arm` survived.
4. **The floor counted loop iterations, not measurements.** `pairs_checked` was incremented whether or not
   `check_pair` ran. A mutant that skipped the call entirely kept the floor satisfied. The per-root check
   also only saw roots it read, so a filtered read of the glob list dropped a whole root silently.

Two instrument defects hid behind these:

- **The farm linked every entry on PATH, not just executable regular files.** A non-executable
  `~/.local/bin/env` shadowed `/usr/bin/env`, the parity suite failed seven cases at rc 126, and its python3
  pair went non-zero for a reason unrelated to its guard. Mutant M4 then SURVIVED, because the rc it
  expected to see was already non-zero.
- **The farm inherited the whole environment except `CI`/`GITHUB_ACTIONS`**, so a guard keyed on
  `RUNNER_OS` was untested.

## Solution

- **Population:** include positive-form guards and quoted tool names. Classify an `if !` guard from its own
  line first (an `exit` or `fi` on that line means whole-suite).
- **Sweep:** run every structural test on the stripped text. The lookahead skips comments and accepts
  `exit`/`return` with a quoted `0`.
- **Self-test:** 14 fixtures, each asserting its derived **tool and class** as well as both verdicts. Two
  pairs and two sweep files are then driven **through the real loop and reporter**, so a verdict misrouted at
  a call site is caught before any real pair runs.
- **Reconciliation, not just a floor:**
  - suite runs made must equal pairs counted;
  - hook roots walked must equal hook roots the runner declares;
  - a tool the host lacks makes the checker exit 3 (it holds itself to its own taxonomy);
  - a signal-killed pair is UNRESOLVED (ADR-187), not RED.
- **Farm:** link only `-f && -x` entries, built by array append (linear, not quadratic). Run suites
  under `env -i` with a fixed whitelist.
- **Suites:** a counted skip exits 3 (no floor dependence). Arms that miss a tool print the
  `UNRESOLVED:` line. git guards were added to the two suites that were green without git.
  `ship-unpushed` T10/T11 now FAIL when the repo-owned registration is missing.
- **Header:** states what is covered and names what is not: unguarded dependencies, guards in sourced
  libraries, tools probed by running them, absolute paths, and tools that resolve but cannot run.

The final battery is 32 rows, 32 caught: the 17 original rows plus 15 reviewer mutants.

## Key Insight

A checker whose deliverable is "no member of set S does X" needs **three reconciliations, not one floor**:

- every member was *derived*: the population regex against the grammar of spellings;
- every derived member was *measured*: runs against counted pairs;
- every declared root was *walked*: roots read against roots declared.

A floor sees only the size of the first. And a PATH-farm harness is itself an instrument that must
reproduce the shell's lookup exactly: it should contain executable regular files only, first entry
winning, with a whitelisted environment. Otherwise it reddens suites for its own reasons, and every rc
check downstream of it goes vacuous.

## Session Errors

1. **The guardrails hook blocked `gh issue create` twice** (forwarded from planning). The body file was
   under `/tmp` and never written in the same call.
   - Recovery: wrote the body inside the spec directory.
   - **Prevention:** already enforced by the hook. Write `--body-file` with the Write tool first, in its own
     call.
2. **The plan sharp-edges catalogue cited `memory-backstop.sh` as the portable-timeout example; it has no
   `gtimeout`** (forwarded).
   - Recovery: repointed the citation to `git-commit-secret-scan.sh` in this PR.
   - **Prevention:** a catalogue example is a claim. `grep` the pattern in the cited file before citing it.
3. **An apostrophe in a comment inside `awk '…'` closed the block and broke the parse.**
   - Recovery: reworded the comment.
   - **Prevention:** work skill trap (b). Grep the awk block for `'` after every edit; run `bash -n`.
4. **The sweep false-fired on its own R-b fixture** (an exit on the literal's own line was not treated as
   terminating).
   - Recovery: an own-line exit terminates the statement.
   - **Prevention:** the fixture self-test caught it before any real run. Keep must-PASS fixtures next to
     every must-RED one.
5. **The PATH farm linked a non-executable file that shadowed `/usr/bin/env`, and M4 survived.**
   - Recovery: link only `-f && -x` entries.
   - **Prevention:** before trusting a farm-based verdict, run one suite on the full farm with nothing
     removed and require it green. A red there is the instrument, not the subject.
6. **The farm build used quadratic `set -- "$@" "$e"` appends** (about 6 s per `/usr/bin`).
   - Recovery: array append.
   - **Prevention:** never grow `"$@"` in a loop over a directory listing.
7. **The first guard-class rule would have let M12 (drop the `exit 3`) reclassify a guard as `arm`.**
   - Recovery: `||` is always whole; `if !` is classified from its own line.
   - **Prevention:** for every classifier, write the mutation that moves a member between classes and name
     the row that reds.
8. **The `guard-vacuity-floor` ledger ignores untracked files, so the 47→48 growth appeared only after
   `git add`.**
   - Recovery: staged the new suite before measuring.
   - **Prevention:** `git add` a new floor-bearing suite before running that ratchet (routed to the work
     skill, §6.6).
9. **`lint-orphan-test-suites` flagged the new registration as UNCLASSIFIED.**
   - Recovery: added a declared affected edge (`.claude/hooks/` prefix).
   - **Prevention:** a new registered suite needs an edge or an ALWAYS_ON entry in
     `scripts/lib/test-affected-paths.sh` (routed to `.claude/hooks/README.md` §Adding a hook test suite; the work skill is at its byte ceiling).
10. **`incident-sandbox-coverage` failed: every hook suite must source `lib/test-incident-sandbox.sh`.**
    - Recovery: sourced it.
    - **Prevention:** routed to `.claude/hooks/README.md` §Adding a hook test suite.
11. **The merge with main conflicted on `PROMOTED_FILES`** (a sibling promotion on the same line).
    - Recovery: took main's line and added this entry.
    - **Prevention:** run `git merge-tree` before spawning the review panel (already in the review skill).
12. **The review found 12 surviving mutants and four suites green with a tool missing.**
    - Recovery: fixed as a class (see Solution).
    - **Prevention:** the Key Insight above. Also audit a self-run battery's AXES: it mutated one guard
      spelling six times.
13. **The #8756 merge Monitor expired at 30 minutes and needed re-arming.**
    - Recovery: re-armed.
    - **Prevention:** none needed; the harness limit is documented.
14. **The perf reviewer left a 320 MB clone under `/var/tmp`, and the `rm -rf` hook blocked it from
    cleaning up.**
    - Recovery: `find -depth -delete`.
    - **Prevention:** the review skill already says to brief each seat on sandbox size and lifetime.
15. **AC6's literal `git diff --quiet origin/main -- <files>` returned 1 against a moved `origin/main`, while
    the branch's own diff was clean.**
    - Recovery: re-measured with `origin/main...HEAD`.
    - **Prevention:** a plan AC that diffs against main uses the merge-base form (routed to the plan
      sharp-edges catalogue).
16. **The final lint batch exceeded the 600 s foreground limit and moved to the background.**
    - Recovery: waited for the completion notification and read the rc lines.
    - **Prevention:** run a batch over roughly 5 minutes with `run_in_background` from the start.

17. **I ran `bash scripts/lint-skill-body-budget.py` (a Python file under bash).** Bash executed `import
    argparse` as ImageMagick's `import`, which blocks waiting for a click. The call hung past its timeout
    and was moved to the background.
    - Recovery: found the process by argv with `ps` and killed it.
    - **Prevention:** invoke a script by its interpreter per its extension, and copy the invocation from
      `test-all.sh`/`ci.yml` rather than retyping it.

## Related

- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
- `knowledge-base/project/learnings/2026-09-23-the-prose-stated-the-property-and-the-predicate-checked-a-subset.md`
- ADR-177 and ADR-188 #8616 addenda; #8773 (same idiom outside `.claude/hooks/`)
