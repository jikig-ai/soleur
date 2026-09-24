---
title: "My SIGPIPE regression guard pinned the file size, not the cause"
date: 2026-09-23
category: test-failures
module: plugins/soleur/test
tags: [pipefail, sigpipe, grep-q, regression-guard, mutation-testing, test-helpers, followthrough]
issue: 7005
pr: 8644
---

# Learning: my SIGPIPE regression guard pinned the file size, not the cause

## Problem

`plugins/soleur/test/vendor-bundle-coverage.test.sh` (Guard 2, #8122) ran under
`set -euo pipefail` and checked lefthook glob coverage with
`grep -E … "$LEFTHOOK" | grep -qF needle`. When `grep -q` exits on an early match, the
producer's next `write()` fails. SIGPIPE is ignored on CI, so the producer gets EPIPE and exits 2.
`pipefail` promotes that to the pipeline, and the suite reported a covered bundle as
`not covered`. The measured false-negative rate on the real `lefthook.yml` was 7 of 200 runs
with SIGPIPE ignored.

The fix was simple: capture the producer into a variable and test it with a herestring.
The regression guard (TS7) was not. It synthesized a 354 KB lefthook-shaped fixture with the
needle on line 1, and it enforced a **file-size floor** (`wc -c >= 262144`). A 10-seat review
found that the guard pinned stand-ins for the property rather than the property itself:

- **Size is the wrong quantity.** What makes the old pipe shape fail every time is the
  list-item output the producer still has to write *after* the needle's line. De-listing the
  filler (turning each `- "…"` item into `# "…"`) or moving the needle to the last line keeps the file at 354 KB and
  quietly disarms the row. Both survived the old shape at 23/0.
- **The negative decoy row had no positive control.** `glob_item_contains … || true` turned an
  unreadable file into "not found", which is exactly the rc 1 the decoy row expects. Deleting
  the decoy file, pointing at a wrong path, or removing the needle from the decoy all stayed
  green, including together with a real regression (the item filter dropped).
- **The call-site checks were review-time greps (AC2/AC3), not shipped rows.** Re-inlining the
  pipe at one TS4 call site stayed 23/0. AC2's regex also missed 7 of 8 plausible spellings
  (`grep -F -q`, `--quiet`, a trailing `|` continuation, `head`).

## Solution

All fixes stayed in the one file:

1. `glob_item_contains` returns **2** for a missing or unreadable file, so a negative row can
   never read "unreadable" as "not covered".
2. TS7 measures the list-item bytes after the needle with one `awk` pass and floors *that* as
   its own row.
3. The decoy carries the needle on a `run:` line **and** in a commented-out glob. A real list
   item acts as a positive control, and a row pins the decoy's two needle mentions.
4. TS8 ships a pipe scanner over the file's own executable lines. It uses `$'\x7c'` so the
   scanner never matches itself, and it has its own control fixture. TS8 also adds exact-line
   (`grep -cxF`) rows for both call sites. Any pipe, whatever the consumer, now fails the suite.
5. An `assert_eq` instrument self-test (the ADR-193 shape).

The review battery ran on a sandbox copy with a green control (31/0), and every mutation was
checked for landing with `cmp`: 17 mutations, all RED. The one axis still uncovered is a
neutered `print_results` in the shared helper, which only an out-of-process check can see.

## Key Insight

For a race regression fixture, **floor the causal quantity, not a proxy that usually tracks
it.** For SIGPIPE that is "bytes the producer must still write after the consumer can exit",
not the file's size. A size floor is satisfied by every fixture edit that keeps the size and
moves the needle. The same move applies to any guard whose sentence reads "non-vacuous because
X is large": name what X is large *relative to*, and measure that.

A negative assertion (`expect rc 1`) needs a positive control **on the same input**, or it
certifies "I could not read the file" as success.

## Session Errors

1. **The planning subagent was killed by an API session limit mid-deepen-plan.** The plan was
   recovered from the on-disk artifact.
   - **Recovery:** read the plan, fixed its half-applied parts, recorded
     `Status: recovered from partial-artifact`.
   - **Prevention:** none needed. one-shot's plan-artifact-recovery arm handled it as designed.
2. **The plan prescribed "no `trap … EXIT`, clean with `rm -rf`".** The repo ratchet
   `lint-trap-tempfile-ownership` rule (c) failed on the new `mktemp`.
   - **Recovery:** added an owning trap *before* `source test-helpers.sh`, which composes it.
   - **Prevention:** added a plan sharp-edge bullet. A new `mktemp` in a `*.test.sh` owes an
     owning EXIT trap, placed before `source test-helpers.sh`.
3. **An abort-path mutant `sed` matched nothing.**
   - **Recovery:** a landing count (`grep -c`) caught it, and it was redone with `awk`.
   - **Prevention:** assert that the mutation landed. This is existing rule; it worked.
4. **The `TEST_GROUP=scripts` gate was refused (rc 4) because a sibling full-gate run was in
   flight.** The `affected` retry queued on the lock.
   - **Recovery:** killed my own process group (after verifying its cwd), then ran the
     repo-global ratchets by shape.
   - **Prevention:** covered by the existing rc=4 guidance.
5. **`rm -rf "$T"` under `/var/tmp` was blocked by the guardrail hook.**
   - **Recovery:** `find "$T" -depth -delete`.
   - **Prevention:** prefer `find -delete` for scratch dirs under `/var/tmp`.
6. **Review mutations did not land:** M5/M5q (anchor count 2, because TS8's literal contains
   the call-site text), and M1/M2b/UNANCH after the helper was simplified.
   - **Recovery:** re-anchored on the first occurrence and on the new helper line.
   - **Prevention:** the existing "assert the mutation landed" rule caught every case.
7. **The follow-through probe, and my first "41 suites" count, used
   `source.*test-helpers\.sh`,** which matched a comment ("…sourced: test-helpers.sh").
   - **Recovery:** anchored on executable lines, `^[[:space:]]*(source|\.)[[:space:]]`. The
     true count is 33 of 57.
   - **Prevention:** anchor any source-detection regex on the statement form, never a bare
     token (`cq-assert-anchor-not-bare-token`).
8. **`gh issue create --label follow-through` was blocked by the directive gate even though the
   probe existed in the worktree.** The gate resolves the script path against the Bash tool's
   input `cwd`, which for this headless agent resets every call to the session's primary
   directory (a different worktree).
   - **Recovery:** filed #8659 without the label, kept the directive in the body, and add the
     label after merge once the probe is on `main`.
   - **Prevention:** in a headless run whose session cwd is not the branch worktree, expect
     this. The gate could honour a leading `cd <dir> &&` in the command.
9. **The git-history review seat mis-attributed this PR's own commit (bb45e38) as pre-PR.**
   - **Recovery:** checked against `git log origin/main..HEAD`.
   - **Prevention:** none needed. It was one agent's misreading and changed no disposition.
10. **The shipped TS7 guard pinned stand-ins (size, a lone negative row, review-time greps).**
    - **Recovery:** fixed inline after review (see Solution).
    - **Prevention:** added a plan sharp-edge bullet. A regression fixture floors the causal
      quantity, and every negative row gets a positive control on the same input.

11. **An advisor-driven cosmetic edit to the EXIT trap reddened CI's `fixture-relative-assert`.**
    `rm -rf "$fixture_dir"` inside the trap is flagged by `fixture-scan.py --rule relative`
    (operand not provably absolute). The `${fixture_dir:-}` form it replaced had passed. After
    adding the probe and the trap edit I re-ran four ratchets and not this one, so CI found it.
    - **Recovery:** restored the scanner-proven operand, keeping the empty-dir skip. Fixed at the
      site; baseline unchanged; the suite is back to 62/0.
    - **Prevention:** after ANY edit to a line containing `rm -rf`, `mktemp` or a trap in a
      `*.test.sh`, re-run the full fixture ratchet set (`fixture-relative-assert`,
      `fixture-dir-operand-assert`, `lint-trap-tempfile-ownership`). A subset chosen from memory
      misses the one that counts the changed shape.

## Related

- `knowledge-base/project/learnings/test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md`: the defect class.
- #7005 (the repo-wide sweep), #6601, #7432 (the grep -q linter).
- #8659: 33 sibling suites replace test-helpers' composed EXIT trap (pre-existing, scoped out).

## Tags

category: test-failures
module: plugins/soleur/test
