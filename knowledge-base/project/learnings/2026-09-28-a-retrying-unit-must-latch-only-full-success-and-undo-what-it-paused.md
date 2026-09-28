---
title: "A retrying unit must latch only full success, and undo what it paused"
date: 2026-09-28
category: integration-issues
module: apps/web-platform/infra (dedicated inngest host, cloud-init, systemd)
tags: [systemd, cloud-init, retry, latch, test-design, mutation-testing, dark-launch]
issue: 8562
pr: 9159
---

# A retrying unit must latch only full success, and undo what it paused

## Problem

On the dedicated inngest host, the zot login, isolation check and pull→bootstrap ran once, from
cloud-init `runcmd`. A missed first-boot pull could only be recovered by a host replace. PR #9159
moved that work into `soleur-inngest-provision.service` (a oneshot with `Restart=on-failure`, a
boot timer and a done-latch) and delivered it dark. The change reaches a host only at its next
`inngest-host-replace` plus `op=resume`.

## What review found (11 seats)

1. **The latch recorded the wrong outcome.** Two versions:
   - `tee "$LATCH"` in the exit trap wrote the latch on a failure path, and all three suites
     stayed green. The "no latch on failure" invariant was asserted on only some scenarios.
   - A degraded bootstrap (exit 0, but redis inactive or no durable ExecStart marker) was
     latched. That turns a transient apt/redis failure, which the unit exists to recover from,
     into a permanent SQLite-only host.

   The fix: write the latch only when `boot_rc -eq 0` and every health leg holds, then
   `sync -f`. A degraded success emits `bootstrap-done-DEGRADED`, exits 0 and writes no latch.
2. **The quiesce paused FSM timers and never restored them.** The unit stopped the
   cutover-flip and LUKS-cutover timers before bootstrapping. On failure they stayed stopped.
   The quiesce was also blind to a frozen or flipping state that was already in flight.
3. **Guards matched spellings, not properties.** Each of these kept the guards green while
   defeating the property: a drop-in overriding the unit, `/usr/bin/docker` instead of
   `docker`, a `bootcmd` route, `TimeoutSec=` overriding `TimeoutStartSec=`, and `set -x`
   placed after the xtrace refusal. This is the same class #9134 had, one PR later.
4. **The prose claimed an "arming residual" that does not exist.** It said a LUKS FATAL
   aborts `runcmd` before the arm. `runcmd` is one shell without `-e`, so later entries still
   run.
5. `TimeoutStartSec` had to be re-derived at review: 45 min became 65 min once the
   synchronous `systemctl` waits inside the quiesce and bootstrap were counted.

## Solution

- Tie the latch to the full success predicate. Test it with a failure-path mutation row per
  exit route, not per scenario.
- Record which paused timers were active, and restore exactly those on every non-success
  exit.
- Guards now assert properties, with mutation rows for each variant above:
  - no drop-in directory for the unit
  - any docker invocation form counts
  - no route into the bootstrap outside the unit
  - an effective-timeout parse that `TimeoutSec=` cannot shadow
  - xtrace refused anywhere in the script
- Tier B runs systemd 255 as PID 1 in docker to drive the real unit through failure,
  restart, latch and reboot re-entry offline.

## Key Insight

A retry loop has two jobs, and reviewers find the bug in whichever one the design left
implicit:

- **The latch.** Latching on "the script exited 0" is not latching on "the thing is done". It
  silently converts exactly the transient failures the loop exists for into permanent ones.
- **The undo.** Anything the loop pauses to make its attempt safe must be un-paused on every
  exit the attempt can take.

## Session Errors

1. **rename-guard flagged main's already-merged #9120 copy after a sync merge** (on #9134).
   The file was byte-identical to main, so it was cleared with the `secret-scan-allow-rename`
   label. **Prevention:** tracked in #9028 (this occurrence is commented there), #8348 and
   #8575. Until those are fixed, before applying the label, verify byte-identity with main by
   running `git diff origin/main -- <paths>`.
2. **The PIR gate fired on a plan sentence ("A web-1 outage is a product outage…").**
   **Prevention:** one-off. Reword hypothetical-outage prose, and do not phrase it as an
   incident.
3. **I skipped ship's pre-merge feature-tweet step on #9134**, so it needed the catch-up
   PR #9158. **Prevention:** ship's phase checklist is the contract. Tick each phase against
   the skill text, not from memory.
4. **The catch-up tweet overstated a claim.** The fact-checker softened it. **Prevention:**
   the fact-checker pass is already mandatory. Run it before drafting the PR, not after the
   merge block.
5. **The review-evidence hook blocked the merge of #9158.** **Prevention:** a docs-only PR
   still needs a review trailer, so run the fact-checker seat before `gh pr merge`.
6. **The lint-infra-no-human-steps hook blocked a session-state commit.** **Prevention:** name
   the dispatch-gated workflow as the actor, never "operator runs…".
7. **ADR-256 was already taken on main when work started** (the plan's ordinal was stale).
   **Prevention:** the existing rule applies. Re-check an ordinal against freshly fetched
   `origin/main` before the first write and again before merge.
8. **The new `*.test.sh` added 30 fixture-relative-assert sites that its own green run
   could not see.** **Prevention:** the existing repo-global-ratchet rule in `work/SKILL.md`
   applies. Any new suite runs `fixture-relative-assert` before the first push.
9. **gitleaks flagged a synthetic fixture password at commit.** **Prevention:** build
   credential-shaped fixture strings by concatenation from the start.
10. **The guard suite was spelling-based, and the failure-path latch invariant was asserted
    on only some scenarios.** Review found this; it is the same class as #9134. **Prevention:**
    a new bullet in `plan-sharp-edges.md` requires a property/mutation row per exit route and
    per override surface in the plan.
11. **A degraded exit-0 bootstrap would have been latched.** **Prevention:** the same bullet:
    the plan must state the latch predicate as the full health predicate, not the exit code.
12. **FSM timers were not restored on failure, and the ADR/runbook prose had a false
    "arming residual".** **Prevention:** the same bullet (undo what you pause), plus the
    existing rule to run the falsifying command for every causal claim the diff's prose adds.
13. **A fan-out agent edited a soft budget outside its brief.** **Prevention:** one-off,
    reverted. Keep fan-out briefs listing the exact files the agent may touch.
14. **A transient `gh` API failure during deploy-arm, and a Monitor expiry that needed a
    re-arm.** **Prevention:** one-off. The script's retry and the re-arm handled them.
15. **Forwarded from planning:**
    - The IaC write-guard blocked the first plan write.
    - Provenance line numbers were pinned to f1f2336156 but measured on 7bc9bde2db.
    - The BASELINE_DECLARED_PROBES ratchet was red until task 1.1.

    **Prevention:** pin provenance to the SHA you measured on (`git rev-parse HEAD` at
    measurement time). The other two were expected gates.

## Related

- `knowledge-base/engineering/architecture/decisions/ADR-257-inngest-host-provisioning-runs-in-a-latched-retrying-unit.md`
- `knowledge-base/project/learnings/2026-09-28-a-replace-gate-on-one-route-and-an-isolation-that-shared-one-shell.md`
  (the `runcmd` single-shell fact)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` §Provision unit (#8562)
