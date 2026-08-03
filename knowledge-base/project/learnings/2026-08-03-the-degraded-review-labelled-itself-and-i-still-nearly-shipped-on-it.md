# Learning: a degraded review labelled itself degraded, and the branch was still one command from merging on it

**Date:** 2026-08-03
**PR:** #7146 (`feat-one-shot-7103-recovery-residuals`) · **Issue:** #7103
**Category:** workflow-patterns

## Problem

Session 3 of #7146 ran `/review` with **0 of ~10 agents** — agent spawning was unavailable, so it
took the sanctioned Gate 2a inline fallback. It did the honest thing: it found 3 real findings,
fixed them, and wrote into `session-state.md`:

> Reviewed with 0 of ~10 agents … Treat the findings below as a floor, not a clearance. … If the
> panel can be run in a later session, run `/review` again BEFORE shipping — this diff grants a
> root restart on a host with no replacement path, and a 0-agent review is thin evidence for that
> blast radius.

Then it wrote `Remaining: /compound -> /ship`.

That is the whole problem. **The degraded review correctly diagnosed itself and still left the
branch in a state whose next step was ship.** The self-assessment was prose in a spec file; the
pipeline position was the operative fact. A session resuming from that state — including one told
"review is done" — reads a `/ship` handoff.

## What the re-run found

12 agents, all returned. **~60 distinct findings after dedup, 15 P1**, including three that
blocked merge. The prior review's own 3 findings were real and correctly fixed; what a self-review
structurally cannot find is the class where **the author's mental model is the thing that is
wrong** — and that was most of them:

- The activation gate hard-failed on an **allow-list of three `reason` strings** and never keyed
  on `action`. Measured against the shipped adjudicator: `action=failed` with an unrecognised
  reason returned `rc=0` with **empty output**, not even a warning.
- `unit_prop` returned `""` on *any* probe failure, so a `systemctl show` that could not answer
  graded as `unit_inactive` → warning → green: an instrument failure certifying an apply that
  reconciled nothing.
- A comment asserted a Sentry beacon was "credential-INDEPENDENT here by construction".
  `grep -c SENTRY_INGEST_DOMAIN cloud-init.yml` → **0**. The DSN components ship in the very file
  whose absence triggers the arm, so the beacon was silent in exactly the incident it reported.
  One agent had first reported this beacon as *working well* — from the comment — and retracted
  after tracing it.

The through-line, worth keeping as a sentence: **the diagnostic is correct and the routing is
wrong — the unknown-value path and the error path both land on the same branch as success.**

## Key insight 1 — "degraded" is a property of the ARTIFACT, not of the prose

A review that names its own coverage gap has done everything prose can do. It still leaves no
mechanical difference between itself and a full review at the point where it matters: the ship
gate reads a boolean.

The repo already has the right primitive — `emit-review-trailer.sh --agents-ran/--agents-expected`
writes `Reviewed-Coverage: full 12/12 agents` vs `inline-fallback 0/10`. **A degraded review must
emit the degraded trailer, and `/ship` must refuse to mark ready on a `single-user incident`
brand-survival threshold when coverage is not full.** Session 3 emitted no trailer at all.

Corollary for anyone resuming a branch: **the presence of a "run X before shipping" note in
session-state means X has NOT run.** Treat it as a blocking precondition, not as context.

## Key insight 2 — some guards' verdicts are a function of BRANCH POSITION, and the rebase is the measurement

Three defects were **green on the branch and only existed relative to `main`**:

1. **ADR ordinal collision, TWICE.** `check-adr-ordinals.sh` scans the local `decisions/`
   directory. Three sibling ADRs (155, 156, 157) landed on `main` mid-pipeline. Measured in this
   exact order: `rc=0` before the rebase → `rc=1` immediately after → `rc=0` after renumbering to
   ADR-158. Then, during the BEHIND auto-sync immediately before merge, a further sibling (#7189)
   landed *its* ADR-158 and the gate reddened again → renumbered to **ADR-159**. The ADR's own
   header had called the ordinal *"Provisional until `/ship` re-checks at merge"* — the re-check
   caught it both times. **An ordinal is not claimed until the branch merges**, so the check
   belongs after every sync, not once at ship entry: a single re-check is a snapshot of a moving
   target.
2. **`model.likec4.json`** — a single-line generated artifact both sides rewrote, so
   `mergeable: CONFLICTING`. Resolved by **regenerating from the merged `.c4` at every conflict**;
   picking either side would have dropped `main`'s ADR-156/157 `claude -> hooks` edge while the
   `.c4` still declared it.
3. **`main` advanced a second time mid-session**, adding a `run_suite` registration to
   `scripts/test-all.sh` — the exact file this PR rewrites. A non-conflicting addition git merges
   silently, so the sibling's registration would have survived or vanished depending entirely on
   how the rebase resolved.

Generalisation: for any guard that reads only the local tree, and for any generated artifact,
**"green on my branch" is not a claim about `main`.** Rebase before believing an exit code, and
rebase *again* if the session is long — this one moved twice in a day.

## Key insight 3 — the anti-vacuity machinery exempted itself

The most uncomfortable finding. `cf-tunnel-liveness-gate-mutations.test.sh` exists to prove a
sibling suite *cannot rot into vacuity*, and enforces an assertion floor on that sibling. It had
no floor of its own: neutering its `pass()`/`fail()` printed `0 passed, 0 failed`, then `OK`, then
exited 0 — byte-indistinguishable from a clean run. Same in `betterstack-assert-absence.test.sh`.
A third, `digest-oracle-guard.test.sh`, *had* a floor (`MIN_ASSERTS=22` against 23 running) with
exactly enough slack to delete **the arm the whole design rested on** while still printing
`assertion floor met (22 >= 22)`.

And its `arm()` took ONE regex while the label claimed three assertions (`"W1/W3/W4"` against an
OR of two, with W4's message in neither branch) — so W1, the assertion whose own comment records
it was once satisfied by a header comment, could be made fully vacuous at **8/8 green**.

The rule: **every discipline a guard imposes on its target, apply to the guard.** Litmus — neuter
your own assertion helpers and re-run. If the suite still exits 0, its headline claim is unpinned
no matter how rigorous the individual arms are.

## Key insight 4 — before granting a privilege, establish that the privilege is what activates the thing

`inngest-heartbeat.service` sat in `RESTART_MAP` with a root `try-restart` sudoers grant. It is a
`Type=oneshot` with **no `RemainAfterExit` anywhere** in `inngest-bootstrap.sh`, on a 60s timer
around a sub-second `ExecStart` — so it read `inactive` on essentially every apply. Two
consequences nobody had stated: the gate's "warn, don't fail" arm was the **steady state on a
correct host**, not the edge case its comment described (the alert fatigue #7103 B3 names); and
the grant activated nothing, because a timer-driven oneshot re-reads its drop-in on the next tick
after the `daemon-reload` the handler already performs.

Removing it retired a standing root-restart capability on the one host with no replacement path.
The general form: **"this unit consumes the config" does not imply "this unit needs a restart
primitive."** For some unit types the activation is `daemon-reload` plus the next scheduled start,
and the grant is pure attack surface.

## Prevention

1. **`/review`'s Gate 2a must emit the degraded trailer**, not just say so in prose. A degraded
   review with no trailer is indistinguishable downstream from one that never ran.
2. **`/ship` must treat `Reviewed-Coverage: inline-fallback` on a `single-user incident` threshold
   as blocking**, surfacing the choice rather than merging on it.
3. **Rebase before reading any all-members or ordinal guard's exit code** — and re-check on long
   sessions, because `main` moves.
4. **Never hand-resolve a generated artifact.** Regenerate from the merged source; a side-pick
   silently drops whichever side you didn't take while its source still declares it.
5. **Neuter your own assertion helpers before trusting a battery's score.**

## Session Errors

- **A `MIN_ASSERTS` floor was set to 27 against 26 actual.** Recovery: the floor failed the suite
  and named the count. Prevention: derive a floor from a green run, never from the number you
  expected — and note this is the floor working, which is the argument for having one.
- **`out=$(...); rc=$?` written under `set -euo pipefail` — in the very commit fixing that class.**
  Every iteration exited non-zero by design, so the suite aborted at the first one. Recovery:
  converted to `|| rc=$?`. Prevention: the shape is only safe when non-zero is unexpected; in a
  loop over rejection cases it is guaranteed to fire.
- **Guessed the stub seam as `BETTERSTACK_QUERY_BIN`; the real name is `BETTERSTACK_QUERY_SCRIPT`.**
  The stub was never invoked, so the arms would have exercised the real transport. Prevention:
  grep the SUT for the variable before writing the stub — a stub that cannot be reached is a stub
  that cannot reject.
- **Ran `git commit` from a shell whose CWD had been reset to the bare repo root**, tripping the
  commit-to-main guard (the hook evaluates the CWD's branch, and the bare root is `main`).
  Prevention: re-establish worktree CWD in its own Bash call after any command that reports
  "Shell cwd was reset"; the guard prevented the damage but the call was wasted.
- **`rm -rf ./*` in a scratch dir tripped the protected-path guard** because the preceding `cd`
  had not taken effect. Prevention: never `rm -rf` a relative glob; name the absolute path.
- **`git tag -f` failed with "no tag message"** under this repo's config. Prevention: use the
  recorded SHA / reflog for a pre-rebase anchor rather than an annotated tag.
- **Two aggregate `test-all.sh` runs were killed** under 4 and then 7 concurrent sibling runs
  (load 16.15/16 cores, `/tmp` 71%), the runner's own `SIBLING_RUN_DETECTED` banner firing both
  times. Not an error in the work. Prevention, and the point worth keeping: **a killed run is
  neither a pass nor a failure.** The aggregate total was deliberately left unrecorded and
  per-suite results plus a *derived* registration delta recorded instead — inventing a total is
  the precise defect this PR exists to remove.
- **Forwarded from session-state (earlier phases):** the IaC-routing PreToolUse hook blocked the
  first plan write (resolved by adding the required section, not by weakening the routing); a
  second write failed "file modified since read" after a linter touched the file; and a
  verification sweep found the plan self-contradicting on the suite count
  (`--list | wc -l` counts the runner's header line).

## Related

- [[2026-08-01-i-shipped-a-gate-my-own-tests-could-not-see]] — the same branch's earlier instance;
  this PR appends its Recovery section.
- [[2026-08-01-my-mutation-battery-inferred-the-verdict-from-the-input-under-test]] — battery whose
  stub inferred the verdict; here the battery had no floor at all.
- [[2026-07-30-a-known-gap-of-seven-was-a-predicate-and-my-battery-mutated-one-axis]] — the
  un-mutated-axis family; the axis missed here was "delete the assertion helpers".
- [[2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried]] — the
  allow-list-vs-deny-list shape.
- `knowledge-base/project/learnings/best-practices/2026-06-14-all-members-drift-guard-must-rebase-before-ship.md`
  — rebase-before-ship; sharpened here by a `main` that moved **twice** in one session.
- `knowledge-base/project/learnings/workflow-patterns/2026-07-05-stale-branch-can-silently-revert-a-just-merged-invariant-pr.md`

## Tags

category: workflow-patterns
module: review, ship, infra
