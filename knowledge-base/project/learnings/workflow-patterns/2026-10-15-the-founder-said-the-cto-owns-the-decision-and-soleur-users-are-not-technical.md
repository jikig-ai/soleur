# Learning: operator-only production authorization stalled a non-technical operator, and a brief's HOLDS list was treated as the operator's

## Problem

On 2026-10-15 the founder gave this instruction, quoted exactly:

> "the CTO should own the decision and be able to proceed autonomously to complete the arc/epic, please also improve our workflow and skills to that effect as Soleur users aren't technical so they wouldn't know what to do anyway. Let's also see if the CTO skill should be improved or new skills created under the CTO so the process is higher quality and autonomous"

The wrong prior default was that every production-mutating act (merging a change to the live product, dispatching a deploy
workflow, a revert) needed a per-command go-ahead from the operator (`hr-menu-option-ack-not-prod-write-auth`, ADR-084's closed
operator-only list). That default assumes an operator who can judge a command. Soleur's users cannot, so the question either
stalls the epic or is answered by reflex, which is the exact failure the rule exists to stop. The same assumption sat in resume
briefs: a brief's `HOLDS` list, and its wording "ask the operator", were treated as the operator's even when each hold was a
checkable fact (a PR merged, no deploy run in flight, a run green). The hold in this session's own brief, "do not merge while the
registry host replace workflow runs", is a machine-checkable predicate, not a person's decision.

## Solution

Recorded operator consent plus a drift guard, recorded in ADR-288 (the first draft called this a "two-key" model; review showed the two artifacts are produced by the same agent identity, so they are not independent):

- **A Standing Delegation (the consent).** The operator is asked once, in plain language, at epic start. The calling skill writes an
  epic-issue comment through `delegation-verify.sh render`: marker on line 1, a verbatim quote, a `Confirmation:` line, numbered
  Scope items, a complete Excluded list, an expiry of at most 30 days. Deleting or editing the comment revokes it.
- **A CTO Production Envelope (the drift guard).** A committed section naming the exact command, blast radius, `Gate:`
  preconditions, verification, abort, a named rollback and stop conditions. The executed command is a byte-identical full line of
  it and must match a closed allowlist of four command shapes (merge, ready, workflow dispatch, create), so a "Yes" cannot be
  stretched to an arbitrary command.
- **One chokepoint.** `delegation-verify.sh` holds every validity check; the Technical-Ruling Gate, the hold evaluator
  (`hold-gate-eval.sh`) and the CTO's pre-execution call all call it. Anything it cannot evaluate keeps today's
  behaviour: the hold stands, the question is asked, the gate fails.
- **Holds become predicates.** `soleur:go` routes a brief that carries an epic reference (`#N`) AND a `HOLDS:` list to the CTO; each hold gets
  `Gate:` lines (`pr-merged`, `no-inflight-run`) that ship Phase 6 evaluates mechanically.
- **Receipts.** After each delegated act the CTO posts a receipt comment on the epic and records the row
  `Authorized by delegation <url>, envelope <path>, ran <ISO UTC>` in `decision-challenges.md`. The ship gate checks a receipt
  only for rows that carry `ran`, so recording that row (the CTO's job, not the calling skill's) is what turns the check on. The
  receipt must be created inside the delegation's life, not in the future and after the `ran` instant, never edited, posted by a
  person (not a bot), from an OWNER, MEMBER or COLLABORATOR, matching exactly, and serve one row only. It proves a receipt
  exists and matches, not what ran.
- **Still the operator's:** money, legal exposure, brand, scope, user-data loss, force-push to main, bypassing checks or
  rulesets, editing the delegation, lock-out credential rotation, third-party systems, any act with no named rollback.

## Key Insight

1. **A default that needs expertise the user does not have is a stall, not a safeguard.** Design the control around what the
   user can actually judge (outcomes, money, scope) and move the technical judgment to the agent that can make it, inside a
   record the user can revoke.
2. **A hold is a predicate or it is a person.** If a hold can be written as a checkable fact, evaluate it mechanically and fail
   closed; if it cannot, say plainly that it needs a person. Prose evaluation by the model is the failure the holds guard against.
3. **Name the residual instead of overclaiming.** The delegation is posted through the same `gh` identity as the agent, so the
   quote, the cap and edit-as-revocation are tamper-evidence, not prevention, and a pair of artifacts written by one agent is not
   two independent keys. ADR-288 states that, states the flip conditions, and points at #10361 for the receipt that restores
   independence.
4. **Do not skip the probe and then write as if you ran it.** The `updated_at` behaviour for reactions was never probed with a
   write on this repository; the verifier takes the strict reading. A read-only look at `cli/cli` found 8 of 8 reacted comments
   with `updated_at` equal to `created_at`, which the ADR cites as an observation only.
5. **A rule that grows an exception must say so in its own sentence.** The amended rule kept "menu acks and prior approvals do
   NOT extend to new commands" beside a path that is exactly a prior approval extended to new commands; the sentence now reads
   "outside a recorded delegation".

## Prevention

- When a plan offers an operator-only gate, ask whether the user can judge it; if not, it needs a recorded delegation plus an
  envelope, or a mechanical predicate, not a question.
- A skill that needs the operator once does it with one plain-language question at the start and writes the record through the
  verifier's `render`, then reads it back through `verify`; a record that does not verify is deleted.
- Never ask the operator a technical question (`hr-technical-fork-is-not-an-operator-question`); spawn the CTO.

## Session Errors

- **A background monitor can expire or fire spuriously.** A watch armed on a long wait either reached its time limit before the
  event or fired on text that was not the event. **Prevention:** arm the watch on a state the check itself re-reads (not on
  matching log text), give it a limit longer than the worst observed wait, and treat any fire as "re-read the state", not as
  the event having happened.
- **A merge-gate hook rejected a merge whose PR number was not the first operand.** `.claude/hooks/ship-kb-archive-gate.sh` needs
  the PR number as a bare operand right after `gh pr merge` (flags such as `--squash --auto` may follow). **Prevention:** put the
  number immediately after `gh pr merge` and the flags after it. (An earlier draft of this entry claimed a hook accepts only
  `gh pr merge <N> --squash`; no repo hook does, and `.claude/settings.json` allows `Bash(gh pr merge:*)`.)
- **The merge queue took about 58 minutes.** The wait is far longer than a typical step. **Prevention:** plan merge-queue time as a first-class phase (tens of minutes, not seconds) and do other verification
  while it runs.
- **A heartbeat cadence made the probe wait.** The heartbeat's cadence set when the state probe ran, so the probe had to wait for it. **Prevention:** probe on the event or at a short bounded interval, and do not let a heartbeat be the
  only thing that triggers a read.

## Tags

category: workflow-patterns
module: cto-autonomy, standing-delegation, hold-evaluation
