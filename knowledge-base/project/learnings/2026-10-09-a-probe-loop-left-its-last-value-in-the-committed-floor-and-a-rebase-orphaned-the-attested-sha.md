# Learning: a probe loop left its last value in a committed floor, and a rebase orphaned the attested SHA

## Problem

PR #9877 (#8285 PR B, retire the Inngest plaintext-backstop wipe apparatus) went through a 12-seat panel and a
4-seat fix round. Four defects came from the author's own fix-round work, not from the code under review:

1. **A bisect loop edited the file under test and left its last value behind.** To find the exact assertion count I ran
   `for n in 314 315 316; do sed -i "s/^FLOOR=.*/FLOOR=$n/" suite.sh; bash suite.sh; done`. The loop ended with
   `FLOOR=316`; the follow-up Python `replace("FLOOR=314\n", ...)` matched nothing, and the commit went in with a floor
   the suite could not meet. Caught by re-running the suite after the commit (`grep -n '^FLOOR='` printed 316).
2. **A rebase after attestation orphaned the attested SHAs.** The CLO attested the destruction record at two commit ids,
   both recorded in the record's frontmatter and body. Rebasing onto `origin/main` rewrote them, so the recorded ids no
   longer resolve in the branch. The content was unchanged, and that is provable: `git rev-parse <old>:<path>` equals
   `git rev-parse <new>:<path>` for each attested file, so I appended a dated mapping note instead of editing the
   attested text.
3. **The first behavioural driver for the surviving `luks-cutover` arm covered 5 of 14 exit paths.** It stubbed
   liveness to always `audible`, confirm to always `done`, and `secrets set` to always succeed, so dropping the `exit 1`
   on G3 silent/unreadable/unrecognised, G2 unreadable, the empty-token refusal, the unreadable-prd refusal, the write
   failure and two confirm arms left the suite green (test-design seat, measured by sandbox mutation). It also ran
   without the production script's `set -euo pipefail`.
4. **Prose I wrote to correct a stale runbook inverted a verdict.** The new signal-to-route table said the
   `rollback_inversion` probe verdict means "the ledger/probe pair claims plaintext on a host that has no plaintext
   volume"; the emitter (`inngest-luks-property-8296.sh`) fires when the ledger claims **LUKS** and the store is measured
   **off** the mapper. Two seats converged on it. The same edit left the runbook's opening paragraph saying a failed
   verification "rolls itself back", contradicting the section I had just rewritten.

## Solution

- Re-derive the floor by running the suite once at the intended value after the probe loop, and read it back with
  `grep -n '^FLOOR='` before committing. Better: probe by copying the suite to the scratchpad, never by editing the
  tracked file.
- For an attested record whose ids a rebase rewrites: do not edit the attested text; append a dated note mapping old to
  new ids and state the evidence (identical blob ids at each pair).
- Give an extracted-arm driver one stub knob per refusal arm and one row per `exit` (rc **and** "no write happened"),
  run it under the production script's shell options, and mutation-verify at least the arms whose only evidence is a
  new row.
- Check each sentence of rewritten prose against the emitter's own source line, and grep the same document for
  every other statement of the corrected fact (the opening paragraph is the one an operator reads first).

## Key Insight

The fix round is where the author's own verification is least audited. Every one of these four was introduced
**while fixing** review findings, and each was caught by a second instrument (a re-run, a blob comparison, a sandbox
mutation, an independent reader), never by the author's reading. A loop that mutates the artifact it measures must be
followed by a read-back of the artifact; a driver is only as strong as the exit paths it can reach.

## Session Errors

1. **Python replacement anchors drifted twice (capital "The store", a line-wrapped "2 people")** — nothing was written
   because each script asserted a unique match first. Recovery: corrected the anchors. Prevention: keep the
   `assert s.count(a) == 1` guard on every scripted replacement; it turned two silent misses into loud ones.
2. **`git stash list` appended to a shellcheck command, blocked by the PreToolUse hook (twice in the branch)** —
   Recovery: removed it. Prevention: already hook-enforced (`block-stash-in-worktrees`); no stash read is needed to
   inspect a worktree.
3. **`bun test` two reds after deleting a describe block** (TEST_FLOOR exact; rationale-pointer parity). Recovery:
   set the exact floor with an itemised comment; replaced a `##` heading with `###` retired note. Prevention: the
   suites' own floors caught both; run the owning suite after any deletion of registered tests or headings.
4. **Tier-census G4c red on two deleted addresses with no state entry** — Recovery: a narrow `RETIRED_STATE_ABSENT`
   allowance. Prevention: later hardened per review (plan-step `-target` scan, G4g, protected live stores); ledger
   entry expiry is a SOLEUR-DEBT tagged to #9786.
5. **`inngest-probe-row.test.sh` must-find failure after removing the retire workflow** — Recovery: removed the
   workflow from MUST_FIND. Prevention: grep the deleted workflow's name across every registry/allowlist before
   deleting.
6. **`test-all.sh --affected` rc=4 (runner changed, degraded to a long full run), then killed** — Recovery:
   `TEST_GROUP=affected`; CI is the authority for the full battery. Prevention: read the rc file; do not wait on a
   contended full run locally.
7. **Mutation helper expected diff-line counts wrong (g4-8: 3, g4-10: 1)** — Recovery: measured. Prevention: derive
   the expected count from one dry landing, not from the sed program.
8. **Stop-hook "unkept promise" blocks and a blocked `pgrep -f`** — Recovery: `<stop>BLOCKED:</stop>` tags while
   background seats ran; `proc.sh` helpers instead of `pgrep -f`. Prevention: when waiting on background agents, end
   the turn with an explicit stop tag naming what is awaited.
9. **Committed `FLOOR=316` after a bisect loop** — see Problem 1. Recovery: set 314, amended. Prevention: read-back
   before commit.
10. **`ADDR_FLAG` accepted a single separator character (`[= ]`)**, so a line-continuation fold that leaves two spaces
    evaded it — Recovery: `(?:=|\s+)`. Prevention: a regex that mirrors another guard's scan (the census uses `\s+`) must
    use the same separator class.
11. **Two mutation scripts did not land** (a non-unique anchor, and an `assert` on a wrong substring) — the second
    returned the unmutated baseline (1090/0). Recovery: `cmp` against a backup caught it; re-anchored. Prevention:
    always `cmp -s` the mutated file against the pristine backup before reading the verdict.
12. **shellcheck SC1010 (`done` as an argument) and SC1007 (`VAR= cmd`) in the new driver rows** — Recovery: quoted
    the arguments. Prevention: run `shellcheck -S warning` on new rows before the panel; the deterministic lint is the
    cheapest instrument.
13. **A rebase orphaned the attested SHAs** — see Problem 2. Prevention: when a record names an attested commit, do not
    rebase afterwards; if unavoidable, append the mapping and the blob-equality evidence.
14. **The post-fix-round "fresh verifier" seat was not spawned.** Disposition: replaced by lead-run mutation checks of
    the new rows (G3 silent, empty token, set failure, rolled-back refusal) and a re-run of every touched suite; stated
    in the PR body rather than claimed as a verification pass.

## Tags

category: workflow-issues
module: soleur:review, soleur:compound
