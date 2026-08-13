# Decision Challenges — feat-one-shot-7485-7501-7506-git-data-ci-guards

Recorded at plan time, headless. Per ADR-084 the operator's stated direction is the default; these
are surfaced, not applied.

## DC-1 — Split the PR: land #7485 + #7506 first, #7501 second

**Operator's stated direction.** One PR closing all three of #7485, #7501, #7506.

**What the consult and the review panel agree on.** Both the engineering consult and the
architecture reviewer recommend splitting. #7485 and #7506 are hermetic: both land in the `scripts`
shard, both are deterministic, neither touches the network. #7501 lands in the `infra` shard and is
the only one that can go red for reasons outside the repository — it runs real containers against
`archive.ubuntu.com` and Docker Hub by design. One PR is one merge gate, so a mirror outage in
#7501's surface blocks the #7485 interlock fix, and that fix is on the critical path for #6977.

**The first draft's compromise was withdrawn, not weakened.** It claimed that ordering the commits
`#7485 → #7506 → #7501` made the network-dependent change "a single clean revert". That is false:
`main` is squash-merged — 200 of the last 200 commits have exactly one parent — so a merged PR is
one commit and in-branch ordering does not survive the merge button. A revert takes all three
changes or none. The files are disjoint, so a manual follow-up revert is straightforward, but it is
not automatic and the plan no longer claims otherwise.

**Why it is a challenge and not just guidance.** The brief states the deliverable as "a merged PR
closing all three". Splitting changes the deliverable shape, so it is the operator's call — and it
should now be made knowing the revert argument does not hold.

**If the operator accepts the split.** #7485 + #7506 ship as PR 1 (deterministic, `scripts` shard);
#7501 ships as PR 2. No plan content is wasted — the phases, guards and ACs are already separated
by issue.

## DC-2 — A starved rehearsal arm stays a FAIL, diverging from #7501's proposal

**Issue's stated proposal (#7501, fix 2).** "Treat an empty capture as INCONCLUSIVE/skip rather
than FAIL."

**What the plan does instead.** It delivers the *reading* the issue asks for — a starved arm names
the fixture cause, carries the container's own stdout, and makes no claim about the emitter — but
keeps the verdict a failure. An earlier draft introduced a third `inconclusive` counter; it was cut
after two independent reviewers showed its mechanical delta was zero.

**Why, on measured constraints rather than preference.**

1. **A skip cannot be green here.** `apps/web-platform/infra/run-registered-suites.sh` prints `PASS`
   for any suite exiting 0 and dumps diagnostics only on RED — its own header records this as the
   reason a docker-less laptop reports PASS for suites that assert nothing. An arm that exits 0
   would be laundered into a green *and* would never surface its own explanation.
2. **Once it exits non-zero, a separate counter buys nothing.** It would increment a different
   integer, feed the same anti-vacuity total, produce the same exit status, and print one more
   number on a summary line no consumer parses. The file already has the idiom for "this block could
   not run": explicit `fail` calls purely for cardinality parity.
3. **A distinct exit code is unavailable.** ADR-177 records that exit `3` is a top-level contract and
   that a nested runner returning it classifies as a plain FAIL. The rehearsal runs both as a direct
   CI step and nested under the local runner, so the distinction has to live in the message.

The cost of the divergence is honest and small: CI is red on a starved container before and after,
as it already is today. What changes is that the message names the fixture instead of accusing the
emitter, and the container's stdout is attached — which is what the four hours and two wrong
diagnoses in #7501 were actually spent on.

**Operator decision available.** Accept the divergence, or require a literal skip-and-pass — in
which case the `PASS`-for-exit-0 laundering in `run-registered-suites.sh` must be fixed first, and
that becomes a prerequisite change with its own consumers rather than part of this PR.

## DC-3 — The gate suite's anti-vacuity check stays a FLOOR, against AC7 as written

**Plan's stated direction.** AC7 and §Test Scenarios A required the gate suite's anti-vacuity
check to become an **exact equality** at 68, "matching the suite's existing form".

**Why that was not implemented as written.** The justification is factually wrong, and the
contradiction is in the file the plan was describing. The existing form is a floor:

```
# A floor, not equality: it is developer-incremented, so `-eq` would redden the suite on every
# legitimately added assertion and train the next person to bump it unread.
if [[ "$_ran" -lt 58 ]]; then
```

So "matching the suite's existing form" argues for a floor, not against one. Both sibling
suites (`test-git-data-rung2-evidence-capture.sh`, `git-data-runcmd-rehearsal.test.sh`) also
use floors. Switching this one to `-eq` would have deleted a documented decision, made the
gate suite inconsistent with its two siblings, and done so on a rationale that inverts on
inspection.

**What was implemented.** The floor is raised 58 → 68 and stays a floor. AC7's *observable*
claim — that a healthy run prints `=== 68 passed, 0 failed ===` — is unaffected and is
asserted directly; it was never the contested part.

**The real argument for `-eq` is not the one the plan made,** and is recorded here so the
operator can weigh it rather than have it disappear: a floor cannot see a
delete-one-arm-add-one-arm edit, which is the `2026-08-04-a-count-framed-ratchet-cannot-see-a-rename`
class this PR cites elsewhere. That is a genuine gap in **all three** suites, and closing it
in one of them by contradicting its own recorded reasoning would be the least coherent option
available.

**Where it IS applied.** The new `scripts/follow-through-closure-guard.test.sh` asserts an
exact 13, because its arms are a closed enumerated set (C1–C13) fixed by the Guard 3 matrix
rather than a running total — so equality is a specification there, not a tax on future
contributors.

**Operator decision available.** Accept the floor, or require `-eq` across all three suites as
a separate consistency change with its own review.
