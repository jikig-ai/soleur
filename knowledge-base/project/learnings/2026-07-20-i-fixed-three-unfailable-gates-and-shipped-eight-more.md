---
title: "I fixed three structurally-unfailable gates and shipped eight more inside the fix"
date: 2026-07-20
category: workflow-patterns
issues: [6721, 6723, 6724]
pr: 6727
symptoms:
  - "a gate/test/claim that looks like it verifies X but verifies Y"
  - "green suite, green CI, and the property the suite is named for is violated"
  - "tree scan clean while the range scan reds"
  - "mutation battery reports all-caught while the central mechanism is deletable"
tags: [vacuity, mutation-testing, secret-scanning, review-gates, verification-shape]
---

# I fixed three structurally-unfailable gates and shipped eight more inside the fix

## Problem

Three gates shared one shape: each was incapable of failing.

- **#6721** — `gitleaks git` drives `git log -p`; without `-m` a merge commit
  contributes zero patch, so a secret introduced only by a hand-resolved merge
  conflict was invisible to every job.
- **#6723** — the DSN rule's password class stopped at the FIRST `@` while every
  real parser takes userinfo to the LAST, so an unanchored allowlist entry let a
  real credential allowlist itself.
- **#6724** — the review-evidence merge gate's Check 1 was a repo-global
  `grep -rl "code-review" todos/`, and `todos/` lives on main, so one long-lived
  file satisfied it for every branch forever.

The fix for all three passed a green suite. Multi-agent review then found
**eight more instances of the same class inside the fix**, four of them
introduced by it, two demonstrated live.

## Root cause

Every defect — the three originals and the eight new ones — reduces to one
sentence:

> **A check certified a property adjacent to the one it was named for.**

The check ran. It passed. It was measuring something else.

| The check | What it certified | What it was named for |
|---|---|---|
| `gitleaks dir .` on the tip | tree is clean | *range* is clean (a range scan reads the OLD blob) |
| `rc == 1` from gitleaks | the process exited 1 | a secret was detected (rc=1 also means *git errored*) |
| `dir_steps >= 2` | at least two steps exist | every event has full-tree coverage |
| `grep -c 'review: '` | the token appears in the file | the matcher uses that pattern (a **comment** satisfies it) |
| `grep 'log-opts="-m ${BASE_SHA}'` | `-m` precedes the range | `-m` is absent (git accepts options *after* revisions) |
| T-V1 (todos on main) | Signal 1 is branch-scoped | *the gate* is branch-scoped (2 of 3 signals unguarded) |
| `FETCH_OK=1` | the fetch was attempted | the range is trustworthy (recorded, never *gated*) |
| "compensating controls stay live" | three controls exist | they cover *this* file (none did) |

## Solution

**Mutate the thing and confirm the check can still fail.** Nothing else in this
session reliably found these — not tsc, not 194 green suites, not reading the
code carefully, not nine review agents reading the code carefully.

Concretely, per check, ask: *name an implementation a reasonable engineer might
write next that satisfies this assertion while violating the property.* If you
can name one, the assertion is measuring the wrong thing.

Three mechanics that made mutation trustworthy here:

1. **Assert the mutation LANDED**, by diffing against a pristine backup taken
   before any edit — never against `HEAD`, which is dirty during review.
   Baseline-identical is **UN-RUN**, never "caught nothing". This fired twice:
   once from nested shell/Python quoting, once because a mutation hit the
   advisory sweep instead of the cron the assertion actually reads.
2. **Mutate a SANDBOX COPY.** A concurrent in-place mutation is reported by
   every file-reading agent as a false "uncommitted drift P1".
3. **Verify with the same SHAPE as the thing verified.** A tree scan cannot
   confirm a range finding is cleared. An exit code cannot distinguish detection
   from error. A bare-token grep cannot distinguish code from comment.

## Key insight

**Writing the warning does not inoculate you against the trap.**

Within this one PR I:

- documented "a line waiver cannot clear a history finding / fixing the file at
  the tip does not turn the gate green" in the runbook — then fixed two DSN
  literals at the tip, verified with a tree scan, and had my own PR failing its
  own range gate;
- documented the `grep -q` SIGPIPE-under-`pipefail` flake — then wrote
  `git log | grep -qF` in a new test one commit later;
- fixed six bare-token-grep-matches-comment assertions — then wrote a parity
  assertion that grepped the bare token `review: `, which the mutated copy
  satisfied *from a comment*, so it survived the mutation it existed to catch;
- corrected a false claim in the runbook — having written that false claim into
  the runbook whose subject is not shipping false claims.

The mechanism is that the warning is stored as *prose to recall* while the trap
fires as *a reflex to act*. Recall loses. Only a mechanical gate — a mutation
run, a comparison, a differently-shaped second measurement — beats the reflex.

**Corollary on agreement:** two agent findings were false positives that cost
one command each to reject (a tree-hash comparison against the wrong refs; a
CI-wiring claim citing an unrelated workflow). Meanwhile the single most
valuable finding — a live gate bypass my own change made *worse* — came from one
agent that went and *measured* it. Convergence is not evidence when reviewers
share a premise; a measurement from one is worth more than agreement among five.

## Prevention

- After fixing any finding, **re-verify with the same scan shape that produced
  it**. Tree-vs-range is the canonical trap; exit-code-vs-report is the sibling.
- For any assertion over a SET, state the set and count the fixture members.
  `>=` thresholds license deletion up to the threshold.
- For any grep over a source body, anchor on a syntactic construct
  (`^\s*attr\s*=`, a call shape) — never a bare token, because the moment a task
  needs both "assert X" and "document X", they collide.
- For a gate that must *deny*, write the deny case FIRST and confirm it denies
  before writing the allow case. Two of three signals here had an allow-path
  test and no deny-path test.
- Prefer `git clone --depth 1` for verification clones. Two full clones
  (211 MB each) exhausted the 4 GB `/tmp` tmpfs and killed a full-suite run,
  which then read as a test failure.

## Session Errors

1. **My own PR failed its own secret-scan gate.** Commit `432081d46` carried two
   DSN literals; I fixed them at the tip and confirmed with a CI-equivalent
   *tree* scan, which structurally cannot see a *range* finding.
   **Recovery:** rewrote the branch history (reset --soft + 5 clean commits),
   tree hash provably identical before and after. Not `.gitleaksignore` — using
   the escape hatch this PR exists to make harder to abuse, for my own mistake,
   would have been the wrong instinct.
   **Prevention:** re-verify with the same scan shape that produced the finding.

2. **Two DSN literals shipped in explanatory comments.** The fixtures were
   correctly runtime-assembled; only the prose explaining them was not.
   **Recovery:** elide the scheme (`<scheme>://`) — the rule is keyword-gated, so
   no keyword means no match, which is stronger than relying on the allowlist.
   **Prevention:** the AC12 baseline-config-vs-shipped-config comparison against
   the same tree; now documented in the runbook.

3. **T-V2 was vacuous.** Its fixture subject `review: no findings` matched the
   legacy Signal 2 pattern, so deleting trailer support left it GREEN.
   **Recovery:** neutral subject. **Prevention:** for a test named after signal
   X, confirm removing X reddens it.

4. **The parity T-S assertion survived its own mutation.** It grepped the bare
   token `review: `, which the reverted copy still carried in a comment.
   **Recovery:** re-anchored on the call shape. **Prevention:** as above — this
   is the sixth instance of this class in two PRs; it needs a gate, not a rule.

5. **`git log | grep -qF` under `pipefail`** in a new precondition, one commit
   after documenting that exact trap. Passed on the run I verified, failed the
   next. **Recovery:** herestring; 3/3 stable. **Prevention:** the existing rule
   exists and did not fire — treat any `| grep -q` in a `pipefail` script as a
   defect on sight.

6. **A false claim written into the runbook that warns against false claims**
   ("the cron is the only range scan carrying `-m`" — the advisory sweep carries
   it too), plus a stale ref-scope row and a "two invocations" that was three.
   **Prevention:** re-derive every count from the artifact at write time.

7. **`.gitleaks.toml` asserted three compensating controls; none held.**
   lint-fixture-content's regex does not match that path, CODEOWNERS is a
   catch-all that adds nothing for file *content*, and "every other rule applies"
   is vacuous since no other rule matches a bare DSN.
   **Prevention:** a compensating-control claim is a testable claim — check each.

8. **The mutation battery reported UN-RUN twice** (nested quoting; wrong step
   targeted). **Prevention:** the landed-check caught both — keep it mandatory.

9. **A TypeScript sibling suite was missed by the touched-file loop**, on a file
   the plan named and I ticked without opening.
   **Prevention:** a plan task naming a file is not evidence the file was opened.

10. **Background-task notifications misreported the exit code twice, in opposite
    directions** — "exit 0" on a run that exited 1, "failed exit 1" on a run that
    never wrote its rc file. **Prevention:** the rc FILE is the only signal.

11. **`/tmp` (4 GB tmpfs) exhausted by my own two 211 MB verification clones**,
    killing a full-suite run and surfacing as an unrelated suite failure.
    **Prevention:** `--depth 1`, and clean up scratch clones immediately.

12. **Two agent findings were false positives** (tree-hash compared against the
    wrong refs; CI-wiring premise cited an unrelated workflow).
    **Prevention:** already covered by the cross-reconcile rule — verifying cost
    one command each.
