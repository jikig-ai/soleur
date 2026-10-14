# The prose stated the property and the predicate checked a subset

**Issue:** #8539 · **PR:** #8560 · **Date:** 2026-09-23

## Problem

An 11-seat review panel plus QA on a boot-path fix for the SOLE Inngest scheduler produced 35
findings, 10 of them P1. **Every P1 was in the verification or the prose, not in the fix.** Both
design-validity seats confirmed the mechanism, and the load-bearing provider retraction the PR
makes (`network` is not `ForceNew` at hcloud v1.63.0) was independently verified against provider
source. The fix itself was ~40 lines and correct in design.

That is not a comfortable result to read as "the fix was fine". It means the review's whole yield
came from artifacts written to *prove* the fix, by an author holding the defect in mind — which is
exactly when a sentence gets written faster than it gets checked.

## Root cause: one gap, seven instances

Six findings, plus one inverted, reduce to a single sentence: **the prose states the property and
the predicate checks a subset.** Each was measured, not inferred.

| Prose said | Predicate did | Measured |
|---|---|---|
| "read the private-NIC boot events with this query" | `--grep private_nic_` → ClickHouse `LIKE '%private_nic_%'`, where `_` is a **single-char wildcard** | 8,539 unrelated web-1 rows, **zero** intended ones |
| "the guard checks the bytes that boot the host" | rendered through a stub map hardcoding the private IP | changing the real Terraform local left **all 15 rendered rows green** while the host would boot with another address |
| "the wait sits before the FIRST private-net use" | `docker login\|pull` + bare-word `curl\|nc\|ping` + a literal `10.0.1.x` | absolute-path `curl`, `wget`, a `$VAR` target, a second subnet, `docker image pull`, an internal name on a public TLD, `bootcmd`, and a `write_files` script invoked from `runcmd` — **ten escapes, all GREEN** |
| "exactly one networkd fallback file" | `^/etc/systemd/network/[^/]+\.network$` from `write_files` | `/run`, `/usr/lib`, `.network.d/*.conf` drop-ins and `.link` **all invisible** |
| "the detail is byte-identical on both channels" | one of **two** independent 120-char literals | a 90-char basename gave Better Stack 130 B and Sentry 120 B, truncation dropping the field the runbook says to read |
| "emit on every run … met once per boot" | invoked only from `runcmd`, which is **once per instance** | zero markers from boot 2 onward |
| **inverted:** "the event itself pages nothing" | an existing Sentry filter keyed on `stage` with **no host condition**, both hosts sharing a DSN | it pages — under a rule named for the *other* host, whose "self-heals" rationale is false here |

The inverted row is the sharpest. Five of the six normal instances make a guard weaker than its
name; that one makes an operator *less* prepared than saying nothing would have.

## The second class: guards that could not fail

Found only by mutating axes the author's own battery never edited. A self-run battery mutates the
SUT; it cannot see the machinery that grades it.

- `ck()` — the one verdict-owning helper with no self-test — taking the pass branch
  unconditionally left the suite **368 passed, 0 failed, byte-identical green** with every scenario
  assertion neutered. The existing instrument self-test drove `pass()`/`fail()`, which is one layer
  too shallow.
- `mutant_end()` computed `red` then chose pass/fail; forcing the choice made **every** battery row
  report "killed" with nothing behind it.
- `case_must_pass()` reported `HELD` unconditionally — the entire over-fit axis dark.
- With `terraform` off PATH the bootstrap suite printed `139/139`, `OK`, and
  `unconditional=138 floor=138` — every byte the floor and `/ship` Check 10 read **unchanged** —
  while all 15 rendered rows silently did not run, because the gated block's own inventory check
  lived *inside* the gate.

## Key insight

Two habits, both cheap:

1. **Write the property as a sentence, then read the predicate beside it and ask whether they are
   the same set.** Not "does the guard pass?" — it does. The failure is never a bug in the
   predicate; the predicate works exactly as written and is narrower than the sentence next to it.
2. **A positive control belongs on every helper that OWNS a verdict, not just on `pass()`/`fail()`.**
   The litmus: *if this helper always said yes, what would notice?* If the answer is "the
   anti-vacuity floor", check who increments the floor's operand — usually the same helper.

And for widenings specifically: every existing fixture sits on the **old** side of the widening, so
"the suite still passes" is guaranteed rather than informative. A widening owes a fixture in the
newly-admitted region, in the same commit.

## Solution

All 33 fixed inline, 0 scope-outs. The widening was prototyped in an isolated sandbox and measured
against all ten escapes plus two must-PASS controls before being applied; it also fixed a latent
false-RED where a flag *value* shadowed a docker target. Each new guard was mutated back out and
confirmed to redden.

## Session Errors

1. **Regenerated a whole-repo ratchet baseline mid-merge.** `git ls-files` emits a conflicted path
   once per merge stage, so the scanner counted one file 3× (6 → 18 sites), and I wrote a FALSE
   explanation into the merge commit ("the delta is exactly the merged union"). Caught by the
   ratchet on CI. **Prevention:** regenerate whole-repo baselines only after the merge commit
   exists; a mid-merge index is transient state and a baseline is a committed artifact.
2. **`git checkout -- <file>` to drop an already-staged edit.** It restores from the INDEX, so the
   edit survived and I nearly proceeded believing it was gone. **Prevention:** for "undo this
   staged edit", name the source — `git restore --source=HEAD --staged --worktree` — and verify by
   grep, never by the absence of an error.
3. **Read an exit code through a pipeline** (`cmd | tail; echo rc=$?`) and got `tail`'s 0 for a
   command that exited 1. **Prevention:** redirect, then read `$?` on its own line.
4. **`echo "rc=$?"` after a compound command** whose last element was not the command under test,
   twice. **Prevention:** same as 3 — `$?` binds to the immediately preceding command.
5. **Parsed `gh pr checks` with awk on whitespace columns**; check names contain spaces, so every
   bucket count was garbage. **Prevention:** `gh pr checks --json name,bucket | jq`, never column
   splitting.
6. **Staged an archived plan for a one-line supersede marker** and the commit was rejected — that
   file carries 6 pre-existing `lint-infra-no-human-steps` findings, and staging pulled them into
   scope. **Prevention:** before marking a stale claim in an untouched file, check what lints that
   file already fails; a one-line marker is not worth importing unrelated findings.
7. **Made `emit()` use absolute paths** (a P3 hardening) and broke the suite's PATH-based stub
   seam. **Prevention:** before hardening a path resolution, check whether a test seam depends on
   it; reverted and recorded the trade in code rather than adding env seams to a boot-critical
   helper.
8. **Started reasoning from a local reproduction before reading its rc.** `scripts/test-all.sh
   scripts` returned **rc=4 REFUSED** (sibling full-gate run in flight) and had measured nothing.
   **Prevention:** read the rc before the output; rc=4 means the run never happened.
9. **Armed a CI monitor whose filter could not distinguish "no failures" from "never settled".**
   It expired after 30m with no events. **Prevention:** a monitor watching for an outcome needs a
   periodic heartbeat naming what is still pending, or silence reads as progress.
10. *(forwarded from session-state.md)* A plan citation pointed at a wrong learning path; fixed
    before commit.

### The delivery phase produced five more, and they are the SAME shape

The findings above are about a guard checking a subset of the sentence beside it. Shipping and
delivering the fix produced five more defects that are the same error one level out: **the
identifier matched, and the thing it identified was different.** None were caught by a gate; each
was caught by asking "what exactly did that name resolve to?"

11. **The squash-merge commit closed the tracker the PR deliberately did not close.** The PR used
    `Ref #8539`, and `gh pr view --json closingIssuesReferences` returned `[]` right up to the
    merge. GitHub's squash message appends the BRANCH COMMIT MESSAGES, and one of them argued
    *against* the keyword using the literal string inside backticks — the commit parser does not
    honour markdown. **Prevention:** scan the squash message, not the PR body:
    `git log origin/main..HEAD --format=%B | grep -niE '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#[0-9]+'`.
    `closingIssuesReferences` is computed from the PR body alone and is silent about this.
12. **Nearly read a neighbouring merge's deploy arm as this PR's.** A `workflow_run` run's
    `head_sha` is the default-branch tip at trigger time, so the arm triggered by the PREVIOUS
    merge's CI carried OUR sha while its `resolve-target` checked out a different commit. Reading
    it as ours would have reported the PR deployed while production served another build.
    **Prevention:** identify a deploy arm by what it CHECKS OUT
    (`resolve-target` log, `depth=1 origin <sha>`), never by the `head_sha` stamp.
13. **Claimed the resume workflow "verified serving" when its own log said it handed off.** The
    run wrote `INNGEST_CUTOVER_FLIP=flushed` and delegated `start -> verify it SERVES -> record`
    to a 30 s ON-HOST timer. A green run meant *the flag was written*. **Prevention:** for any
    workflow that ends by writing a flag, the serving proof is on the host, not in the run.
14. **Nearly read the steady state as the failure state.** The on-host FSM polls, and after a
    SUCCESSFUL resume it writes `flag=done` back itself — so `noop-done` every 30 s is what
    success looks like. The one decisive line, `reason=flushed-resume-no-reflush`, sat 11 rows
    above what `tail -14` showed. **Prevention:** when a poller's steady state and its
    never-started state print the same token, search the window for the TRANSITION, and never
    conclude from a tail.
15. **A wrapper reported failure while both things it measured were green.** `for s in …; do …;
    [ "$rc" -ne 0 ] && printf …; done` exits 1 when the final test is false, so the loop's status
    said "failed" while every ratchet returned 0. Same family as errors 3 and 4.
    **Prevention:** end such a loop with `true`, or branch with `if`.

The generalisation worth keeping: **an identifier that is merely CORRELATED with the thing you want
will agree with it almost always, and disagree exactly when it matters.** `head_sha` correlates with
the deployed commit; `closingIssuesReferences` correlates with what closes; a green run correlates
with a serving process. Each is a different fact from the one being claimed, and the gap opens under
concurrency — a busy `main`, a neighbouring merge, a poller mid-transition.

## Also worth knowing

**`battery-owed.sh` never skips on inconvenience.** Its exit contract is 42=SKIPPABLE and
*everything else* = OWED, and its four conditions are evidence-based: clean tree, `origin/main` an
ancestor of HEAD, no infra paths while `infra-validate-required` is absent from the LIVE ruleset,
and every required context present-and-green on this exact sha. For an infra diff the third
condition is decisive — `deploy-script-tests` runs the registered infra suites but is NOT required,
so its green cannot block a merge and cannot substitute for the local battery. Contention is not an
input, deliberately.

**A PR that edits `.github/workflows/**` has no agent admin-merge path.** `admin-merge-ready.sh`
returns `verdict=not-ready reason=untrusted-ci`, because the PR's own check runs could mint a run
under any required name. The operator merges it by hand. Worth knowing BEFORE planning a merge
strategy around the `--green-sha` carryover.

**The sync treadmill is real and measurable.** With `strict: true` a branch cannot merge while
behind, and each re-sync restarts CI. Measured here: ~35 min of CI against ~3 commits/hour on
`main`, three successive auto-syncs, the last discarding a shard 32 minutes in. Before waiting it
out, compare the CI cycle against `git log origin/main --since='1 hour ago' --oneline | wc -l`.

**A DIRTY merge ref suppresses every `pull_request` workflow.** A conflicting PR presents as "CI
never ran" with a small, all-green CodeQL check set — `deploy-script-tests`, `test-scripts` and
`e2e` are *absent*, not failing. Check `gh pr view --json mergeable,mergeStateStatus` BEFORE
diagnosing a missing check. Here it was a `PROMOTED_FILES` collision with a sibling PR; resolved as
a union, because dropping either side silently un-promotes a floor-bearing suite into a
shrink-only ledger.

## Tags

category: workflow-patterns
module: infra, guards, review
