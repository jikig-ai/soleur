---
title: "Every defect the panel found was in the verification, and then I shipped two more of the same class while fixing them"
date: 2026-09-07
category: workflow-patterns
component: net-issue-flow gate, review pipeline
issue: 7759
pr: 7896
tags: [review, guards, fail-open, mutation-testing, false-claims, sweep-by-claim]
---

## Problem

PR #7896 fixed a real fail-open in a BLOCKING merge gate: a filing that cites the
originating ISSUE instead of the PR was invisible, so the gate under-counted and passed
net-positive. The fix — a declared `Filed:` line in the PR body — was sound and stayed
sound through the whole review.

Everything that was wrong was in the machinery built to prove it.

## What the panel found

Nine lenses (two died on a quota). Thirty-one findings, twelve P1, **none in the
mechanism the PR exists to add**:

- **An unbalanced code fence deleted the entire new arm.** Both strippers return `""`
  on an unbalanced fence, and the two halves fail in OPPOSITE directions: CLOSING drops
  to 0 (harmless), `$declared` drops to empty — and `$declared` is the only arm that can
  see the filing shape this PR exists to catch. One unclosed ``` turned a net-positive
  PR into `Filing: 0 / PASS`, silently. The gate's own header claimed this path "fails
  closed", which is true of the exemption and exactly backwards for FILED. The awk
  stripper already `exit 2`ed on it; the shell caught that and threw it away.
- **`Filed: #N` + `Closes #N` paid −1 for filing an issue.** `$closenums` was subtracted
  from `$declared`, so one close keyword deleted a declared filing from FILED *and*
  claimed a close credit. Two units of NET from one line, with the number then absent
  from every printed line.
- **`Filed: #N` — the exact line the skill instructs — was the one shape that admitted a
  mandated filing to FILED and then denied it the exemption**, rejecting with "PR body
  has no Tracks/Refs #N companion" over a body that declared #N verbatim. The printed
  remediation then looped: it says add `Tracks #N`, and `Tracks: #N` reproduces the
  message.
- **The residual line accused numbers it had itself counted.** `$bodyonly` never joined
  the issue array — no recency filter, no existence check, no exclusion of counted rows.
  Live on merged PR #7702 it printed five numbers, four simultaneously in `Filing: 4`.
- **`Refs:` prose over-attributed.** A real line on `main` — `Refs: #6588, #6897, #6604,
  #6570. Prior decision: #6918` — admitted five issues as this PR's filings, including
  the one the line labels "Prior decision". That is the sibling-attribution failure the
  ADR uses to reject the alternative, reintroduced through the arm that replaced it.
- **The suite had two independent one-token disarms.** A `fail()` incrementing `passes`
  satisfies the conservation check exactly and keeps the floor green — measured, that
  plus a reverted arm printed TEN `FAIL` lines and exited 0. And `neg()`, which owns 16
  assertions and the whole "too permissive" direction, decides its own verdict, so
  `-eq 1` → `-ge 0` makes all 16 unconditional with both helpers perfectly healthy.
- **A PR body over 131072 bytes disabled the gate.** `--arg prbody` put the body in one
  argv element; past `MAX_ARG_STRLEN` jq is never exec-ed and control lands on
  `_fail_open`, which exits 0. Indistinguishable in telemetry from a GitHub outage.

## Key insight

**On a fix PR, review the new ASSERTIONS before the new code.** The author writes them
while holding the defect in mind, so they pin *the shape of that bug* rather than *the
property*. This is now measured across three consecutive sessions and it did not weaken
with awareness of it.

The sharper half: **I committed the class twice while fixing it.**

1. My first verdict-helper control carried a comment claiming it also caught the `neg()`
   disarm. It does not — `neg()` decides its own verdict and then calls `pass()`, so both
   helpers behave perfectly and the wrong branch was taken before either ran. Measured:
   `ALL PASS (104)`, exit 0, with a live gate regression. A verdict-machinery control
   cannot see an assertion that asserts the wrong thing; only a control proving the
   helper can still REJECT can.
2. I corrected the false "0 of 33" measurement in three artifacts and stopped, leaving
   six live twins in this branch's own plan, tasks and session-state — the documented
   "marked one block, not its twin" failure, in the session whose subject is retracting
   a false claim.

**And the empirical claims were wrong in the direction their own stated method
predicted.** "0 of 33 `Mandated-By:` issues cite a PR" classified numbers issue-vs-PR
**by range membership**, which cannot discriminate because GitHub issues and PRs share
one number space — visible in this very work (issue #7759, PR #7896). Re-measured on
`.pull_request`: 21 of 66 cited numbers are PRs, 20 of the 33 issues cite at least one,
over 29 pairs — one being #7710 → #7702, the case #7759 was filed about. Having found
that, I checked the next empirical claim in the same ADR ("sixteen filing sites") and it
was also unreproducible: 19 files, 48 invocations.

Three artifacts restated the bad number and each derived a STRONGER conclusion from it
("never had a candidate", "never evaluated on a real issue", "dead on arrival"), and it
had been recorded as the answer to an explicitly-flagged open question.

## Prevention

- For every causal or universal claim a diff ADDS — in code comments, ADRs or skill prose
  — name the command that would falsify it and RUN it. A claim that reads as established
  usually was established somewhere else, under a premise that did not travel.
- When a measurement classifies members of a set, state the discriminator and check it
  can discriminate. "Range membership" over a shared number space cannot.
- Sweep corrections by CLAIM, never by file. A residual-zero count over the new text is
  structurally blind to the sites still carrying the old, and a retraction quoting what
  it retracts makes the count fire anyway.
- Every verdict-emitting helper needs its own control proving it can still REJECT — not
  just that its counters move. A helper that decides its own verdict is disarmable
  independently of `pass()`/`fail()`.
- Instrument checks that cost seconds and each caught a wrong reading here: assert a
  mutation LANDED against a pristine backup; run the unmutated control IN the sandbox;
  read `${PIPESTATUS[0]}`, never `$?` after a pipe.

## Session Errors

1. **Apostrophes in a jq comment closed the single-quoted jq program**, producing a bash
   syntax error at an unrelated line. Second occurrence on this branch — the work phase
   hit it too. *Prevention:* strip apostrophes from any text inserted into a
   single-quoted jq program; assert `bash -n` after every such edit.
2. **A control comment claimed a property the control did not have** (see Key Insight).
   *Prevention:* measure the claim a control makes about itself, exactly as for any other
   assertion — mutate the thing it claims to catch.
3. **Corrected a retracted claim in 3 artifacts and left 6 twins.** *Prevention:* grep the
   claim's SUBJECT across the branch's own artifacts before declaring a retraction swept.
4. **`rc=$?` after `cmd | tail` captured `tail`'s status**, reporting a linter that exited
   1 as rc=0. *Prevention:* `${PIPESTATUS[0]}`, or capture before piping.
5. **`cp -a .` of the whole repo into a 4 GB tmpfs filled it** ("No space left on
   device") mid-measurement. *Prevention:* sandbox only the files under test and use the
   suite's own env seam.
6. **`git rerere` silently reused a stale resolution** and dropped this branch's ADR-206
   entry from `INDEX.md`. *Prevention:* after any rebase touching a generated index,
   regenerate it rather than trusting the resolution.
7. **Under-spawned the review panel** (4 agents, not the decided set); closed with a late
   spawn, which `review/SKILL.md` warns costs an extra fix-verify round. *Prevention:*
   write the agent list down before the first spawn and spawn it complete.
8. **markdownlint MD018 introduced twice** by wrapping a line so it begins `#NNNN`, which
   parses as a malformed ATX heading. *Prevention:* never let a soft-wrap put `#<digits>`
   at column 0.
9. **A supersede banner landed at EOF** because the target plan has no H1 and the
   insertion walked to end-of-file. One-off; caught by markdownlint.
10. **A Python anchor mismatch left a fixture block uninserted while the floor had already
    been raised**, reddening the suite. One-off — and the anti-vacuity floor caught it
    immediately, which is the floor working exactly as designed.
11. **Two review lenses (`code-quality-analyst`, `git-history-analyzer`) died on an
    Anthropic session limit** with zero findings. *Prevention:* none available in-session;
    recorded in `session-state.md` and in the review trailer as `degraded 7/9` so the
    coverage is not downstream-indistinguishable from a full panel. **The `~300 PRs`
    measurement this PR rests on remains UNVERIFIED.**
12. **`rule-metrics-aggregate.sh` exits 5** on an orphan `rule_id` (`skill-security-scan`)
    present in the local gitignored incidents ledger but not tagged in `AGENTS.md`. Not
    introduced by this branch and not a repo-state defect — the ledger is per-machine, so
    a clean checkout does not reproduce it. Noted rather than filed: a reflexive filing
    here would make this PR net-positive on the very gate it exists to fix. *Prevention:*
    the emitting hook should either tag its rule id or stop emitting one; worth folding
    into whichever PR next touches that hook.

## Routing

- `plugins/soleur/skills/review/SKILL.md` — one Sharp Edges bullet: a helper that decides
  its own verdict is disarmable independently of `pass()`/`fail()`, and the documented
  positive-control remedy is structurally blind to it. Routed to the skill, not
  `AGENTS.rules.md`, because the rule-budget linter reports `[WARN] B_ALWAYS=46000 >=
  44000` — in that tier the skill's own gate forbids adding a rule to the always-loaded
  payload, and this insight is domain-scoped to guard review anyway.
- No constitution promotion: every insight here is already covered by an existing
  cross-cutting rule or is domain-scoped to review.
