---
module: work-skill
date: 2026-08-12
problem_type: logic_error
component: skill_definition
symptoms:
  - "a 2-rung decision ladder's second rung ended in a classification with no imperative, so an agent walking it took no branch and fell through to the relaxed default"
  - "the fail-safe sentence was scoped to whether a gate EXISTS while the rung it rescued asks whether it BLOCKS"
  - "reverting the PR's own thesis left its guard test 5 pass / 0 fail"
  - "a self-run 6-mutation battery reported no surviving mutants; review found 13 across five untouched axes"
root_cause: guard_written_against_the_authors_own_mental_model
severity: high
tags: [fail-open, decision-ladder, mutation-testing, vacuous-assertion, self-hosted-users, prose-guard]
synced_to: [work, review, plan]
---

# My ladder rung ended in a label, so it fell through to the unsafe branch

## Problem

#7352 moved the full `scripts/test-all.sh` battery from the `/work` Phase 2 exit to `/ship` Phase 4.
Four of the relaxed prescriptions are **project-agnostic** — they ship to self-hosted plugin users
whose repos have neither this repo's CI ruleset nor `scripts/test-all.sh`. The operator chose to
relax them *with a conditional* rather than leave them alone, so the conditional is the entire
safety case for every external user, and alpha tester #1 was inside a measurement window at the time.

I wrote a two-rung ladder to decide which case a project is in. An 8-agent review found it fail-open.

## Root cause

Three defects composed, and each one alone would have been survivable.

**1. A rung that ends in a CLASSIFICATION is not a branch.** Rung 1 ended correctly:

> No such config ⇒ **no gate** ⇒ run the full battery at implementation exit. Stop here.

Rung 2 ended:

> If enforcement cannot be established from what you already have, that is the uncertain case, not
> the permissive one.

That is a *label*. It names the case and prescribes nothing. Rung 1 established the pattern that a
rung states its own consequence; rung 2 silently broke it, so an agent walking the ladder literally
reaches the end holding a classification and no instruction.

**2. The rescue sentence keyed on the wrong predicate.** The fail-safe below the ladder read:

> if you cannot determine whether such a gate **exists**, treat it as ABSENT and run the full battery.

Rung 2 produces uncertainty about **enforcement**, not existence — and rung 1 had already answered
*existence* with YES. So the one sentence that supplies an action reads as *not firing* for exactly
the case that reached it.

**3. Rung 1's predicate was too weak to be the thing it gates.** "A CI config that runs the project's
full test command on pull requests" is satisfied by a config with a `paths:` filter, a job-level
`if:`, `continue-on-error: true`, fork-secret dependence, or — the structural one — a run that is a
**SUBSET** of the local battery. That last case is what *this repo's own CI* does: three shards,
excluding `apps/web-platform/infra/`. So by the repo's own example, "runs the full test command"
evaluates YES against a partial run.

Composed, the modal external repo — tests on PRs from a starter template, branch protection set in
the GitHub UI and therefore not checked in — walks: rung 1 **YES** → rung 2 **undeterminable** → no
branch taken → falls through to the section's dominant "run the shards your diff touches".

**The relaxation was reached by fall-through**, which is precisely what the design forbade in its own
next sentence ("the relaxation is the privileged branch and is never reached by assumption").

## Solution

Every rung terminates in an action, and the ladder says so:

```markdown
**Each rung ends in an action. If you reach the end of a rung without taking one, you have
misread it — take the safe branch.**

1. **Does a CI config run the project's WHOLE test suite on every pull request targeting the
   merge branch?** Any of the following disqualifies it — treat the gate as ABSENT, run the full
   battery, and stop here:
   - a `paths:` / `paths-ignore:` filter …
   - a job- or step-level `if:` that can skip the run;
   - `continue-on-error: true`, or a command suffixed `|| true`;
   - dependence on secrets unavailable to fork PRs;
   - **a run that is scoped, sharded, or otherwise a SUBSET of the local battery.**
2. **Does that run BLOCK the merge — required, not merely reported?** … **If you cannot establish
   blocking from what you already have — which is the normal case, because GitHub branch
   protection is a server-side setting that is not checked in — treat the gate as ABSENT, run the
   full battery, and stop here.**

**The default is the safe branch: if you cannot determine that such a gate exists AND blocks
merge, treat it as ABSENT and run the full battery.**
```

The predicate is now the **union** of what both rungs can leave undetermined, and the four
project-agnostic sites LEAD with the condition instead of carrying a parenthetical pointer 400+
lines away from it.

## Key insight

**For any decision ladder, ask three questions the author never asks of their own ladder:**

1. **Does every rung terminate in an action?** A rung ending in a noun phrase ("that is the uncertain
   case") is a classification, and classifications do not branch. If the reader can reach the end
   holding only a label, the ladder has a fall-through — and fall-through lands on whatever the
   surrounding document says by default, which is the thing the ladder existed to prevent.
2. **Is the fail-safe's predicate the UNION of what the rungs leave undetermined?** Write out what
   each rung can fail to establish, then check the rescue sentence names all of it. Mine named one
   of two, and the missing one was the rung that actually fails in practice.
3. **Is the FIRST rung strong enough to be the thing it gates?** The weakest rung sets the ladder's
   strength. Enumerate the shapes that satisfy its literal words while defeating its purpose — and
   look at your own repo first, because the counter-example is usually sitting there.

**Corollary, and the harder half:** the safe branch must be reachable by *reading*, not by
*remembering*. Three of my four sites stated the relaxed instruction as an imperative and routed the
safe branch through a parenthetical cross-reference. Even with the ladder fixed, that ordering makes
the safe outcome depend on the reader noticing a link, jumping ~400 lines, walking two rungs, and
concluding ABSENT — four discretionary steps the imperative does not depend on. Put the condition
first, at each site.

## The second thing nobody asserts: the PR's own thesis

I wrote a guard test with five assertions. It pinned the **ceiling** (ship Phase 4 stays unsharded)
and the **fallback prose**. It never pinned the **floor** — that `/work` Phase 2 actually exits on
shards. Reverting §9 to an unconditional `TEST_GROUP=all`, undoing the entire change, left the suite
**5 pass / 0 fail**.

**Gate:** for any PR whose thesis is "X now happens at position A instead of position B", name the
mutation that puts it back at B and confirm something reds. The assertion guarding your own headline
is the one you are least likely to write, because the change feels self-evidently present while you
are making it.

## Related

- [[2026-08-11-my-battery-reported-all-caught-and-eight-axes-were-untouched]] — the mutation-battery
  axes class, documented **the day before** this session and committed again here. My battery
  reported 6/6 RED and "no surviving mutants"; review found **13** survivors across five axes it
  never touched: dispatch (deleting or `test.skip`-ing the whole file was a green build), the floor,
  fixture direction, region widening, and **demotion** (rewriting prose to make the run conditional
  while the fenced command stayed byte-identical). Two axes, not six. Reading a learning is not the
  same as applying it; the durable fix was mechanical — enrolling the file in
  `preflight-check10-suite-integrity.test.sh`'s `SUITES` manifest, which is the repo's existing
  answer to "a floor written inside a suite is itself skippable".
- [[2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim]] — recurred. I re-pointed four
  stale citations inside `work/SKILL.md` and missed `work/references/work-agent-teams.md:82` and
  `work-subagent-fanout.md:52`, the Tier A/B Phase 2 integration checkpoints — same phase, same
  prescription class. I had written "index the sweep by claim" into my own deviations note earlier
  in the same session.
- [[2026-08-10-i-fixed-the-guard-twice-and-my-test-could-not-see-either-fix]] — sibling shape.

## Session Errors

**Ladder rung ended in a classification, not an imperative** — Recovery: every rung now terminates in
an action and the ladder states that rule. — **Prevention:** for any numbered decision procedure,
check each rung ends in a verb the reader can execute; a rung ending in a noun phrase is a
fall-through.

**Fail-safe predicate mismatch (EXISTS vs BLOCKS)** — Recovery: restated as "exists AND blocks
merge". — **Prevention:** write out what each rung can leave undetermined and confirm the rescue
sentence names the union.

**Rung 1's predicate satisfiable by a subset run** — Recovery: added a disqualifier list. —
**Prevention:** enumerate shapes that satisfy a gate's literal words while defeating its purpose, and
check your own repo for the counter-example first.

**No floor assertion — the PR's thesis was unpinned** — Recovery: added floor assertions; reverting
§9 now reds. — **Prevention:** name the mutation that undoes the PR and confirm something reds.

**Mutation battery had two axes, not six; "no surviving mutants" was false** — Recovery: retracted the
claim in `tasks.md` (append-only, old matrix retained) and ran a 13-mutation Round 2. —
**Prevention:** audit a battery's AXES, not its count; N mutations of one shape is one mutation.

**Did not enroll the new guard in an existing mechanism** — Recovery: added to
`preflight-check10-suite-integrity.test.sh` `SUITES`, floors ratcheted 122→131 / 514→537 / 117→126,
non-vacuity proven. — **Prevention:** before writing a new guard, grep for an existing manifest or
floor that already solves the class.

**Swept by file when the unit of truth was the claim** — Recovery: fixed both reference files. —
**Prevention:** enumerate the PROPOSITIONS a change falsifies and `grep -rn` each; never index the
sweep by the files you happened to open.

**Seven false claims in shipped prose** — "an infra regression that reaches merge reaches production"
(`infra-validation.yml` runs the set on every infra PR, non-blocking); "the only full-battery run"
(false on the Grok arm); `TEST_GROUP=all` = a full battery (false locally — `_diff_touches`
short-circuits only under `CI` or `SOLEUR_TEST_FORCE_ALL`); "460+ suites" (measured 292); "six
passages" (seven); a shard-map derivation pointer aimed at `want_*` predicates that carry no path
data; the ADR's 573 s presented as unconditional when it is relevance-gated. — Recovery: all
corrected. — **Prevention:** for every causal or universal claim prose ADDS, name the command that
would falsify it and run it.

**Violated the merge-gate prohibition I authored** — `ship/SKILL.md` says "do not describe this local
run as the merge gate"; my diff said "the `/ship` Phase 4 merge gate" at six sites and the ADR
filename was the forbidden claim. — Recovery: reworded all six, renamed the ADR pre-merge. —
**Prevention:** after writing a prohibition, grep your own diff for it.

**`git push … | tail -5` reported rc=0 on a REJECTED push** — Recovery: read the output, re-pushed
with `--force-with-lease` after a patch-id comparison. — **Prevention:** never pipe a command whose
exit code is load-bearing; capture rc directly.

**markdownlint baseline of 0 errors was a config-resolution artifact** — linting copies outside the
repo picked up different rules. — Recovery: re-ran with `--config` pinned and the copies staged
inside the repo; baseline and branch matched exactly. — **Prevention:** an implausibly clean baseline
is an instrument failure until proven otherwise.

**Backtick `scripts/…` refs tripped `components.test.ts` twice** — Recovery: converted to markdown
links. — **Prevention:** grep the diff for `` `scripts/…` `` before running the suite.

**Diagnostic aggregators dirtied the tree** — `skill-freshness-aggregate.sh` and
`rule-metrics-aggregate.sh` regenerate committed JSON as a side effect. — Recovery: reverted. —
**Prevention:** run them expecting writes, or `git checkout --` after.

**Launched the full battery at the Phase 2 exit, contradicting the change being shipped** —
Recovery: killed it (ownership resolved via `/proc/<pid>/cwd`; three sibling sessions untouched) and
let ship own it. — **Prevention:** when a PR changes a pipeline position, dogfood the NEW position.

**Ended a turn on "Continuing to /qa → /compound → /ship" without invoking** — the operator had to
ask "why did you stop?". — Recovery: resumed immediately. — **Prevention:** a phase-complete marker
is a checkpoint; the next skill invocation must be in the SAME response. Stating an intention is not
performing it.

**A python edit batch aborted on one bad anchor and wrote NOTHING** — the ADR rename and citation
sweep had already landed, so the tree sat in a partial-application state. — Recovery: re-derived the
anchor from the file and re-ran. — **Prevention:** the assert-anchor pattern is right, but stage
independent edits per file so one bad anchor cannot silently revert a whole batch.

**Commit subject shipped the literal template placeholder `(P<1>)`** — Recovery: amended. —
**Prevention:** read the rendered subject before committing.

**Five `hook_self_fault` rows at 09:50–09:52Z, inside this session** — per ADR-157 a PreToolUse hook
could not parse its stdin and ran the tool call **with its guards disarmed**. The window coincides
with large python-heredoc edit batches. — Recovery: none at the time; not noticed until the compound
incident scan. — **Prevention:** treat `hook_self_fault` as the strongest deviation evidence, and
investigate whether large heredoc payloads are the trigger — a guard that silently did not run is
worse than one that denied.

**Forwarded from `session-state.md`** (planning subagent, pre-compaction): ADR ordinal probe wrong
(reported max 180, actual 182); R4 classified as a coverage gap when already CI-gated;
`FULLSUITE_SHA` specified with no persistence substrate; `## Observability` claimed "not applicable"
incorrectly; internal contradictions between Files-to-Edit and its own ACs; its own revision
introduced five stale-live defects. — **Prevention:** each was caught by a gate rather than by the
author, which is the system working; the ordinal one recurs often enough that re-deriving against
freshly-fetched `origin/*` immediately before merge is the standing gate.

## Process notes worth keeping

- **Spawn a large review panel REPORT-ONLY.** With 8 concurrent agents the fix-inline default has
  them reading each other's uncommitted edits and reporting them as defects. All fixes applied by the
  lead from a pinned SHA.
- **Verify semgrep's rule count, not just exit 0** — an invalid `--config` exits 7 and still prints
  `findings: 0`, which reads identically to a clean run. `Ran 79 rules on 1 file` is the evidence.
- **A stalled agent is RESUMABLE from its transcript.** `code-quality-analyst` stalled at 600 s on a
  wide read; resuming with a narrowed scope recovered it without losing prior findings.
