---
title: "A systemd unit state used as a coordination signal had no provenance or time — so a resume replayed a stale capture and a crash read as a deliberate quiesce"
category: logic-errors
tags: [inngest, cutover, systemd, provenance, resume, watchdog, review, test-design]
module: apps/web-platform/infra/{ci-deploy,inngest-inventory,inngest-rearm-reminders}.sh, scripts/cutover-inngest.sh, .github/workflows/scheduled-inngest-health.yml
issue: 6921
pr: 8173
date: 2026-09-14
symptom: "A plan-reviewed, deepened, TDD-built fix (6 commits, 18 suites green) let a second op=execute resume a days-old cutover-capture.json as source=persisted (reproduced twice in sandboxes), and let a crashed-then-disabled scheduler read as a deliberate quiesce that the watchdog would never page on."
root_cause: "The design chose the systemd shape (is-active ∈ {inactive,failed} ∧ is-enabled == disabled) as the ONLY quiesce signal to avoid new state. A unit state records WHAT is true, not WHO made it true or WHEN — every consumer that makes a resume, replay or suppress decision needed both."
---

# A systemd state used as a signal had no provenance or time

## Problem

`op=execute → op=quiesce-web → op=execute → op=arm` needed a signal meaning "the web scheduler was
deliberately stopped by the cutover". The plan picked the systemd unit shape — `inactive|failed` +
`disabled` — precisely because it needed no new state, and a 5-agent plan panel accepted it.

Five of twelve review agents then converged on the same gap from different directions:

- **Stale replay (P1, reproduced):** `quiesce` captured only when the unit was `active`, otherwise it
  kept whatever `/var/lib/inngest/cutover-capture.json` existed. On a `failed`+`disabled` unit a
  13-day-old file resumed as `source=persisted` with rc 0 — reminders armed since were lost and ones
  already fired were re-armed to fire twice.
- **False attribution:** `inngest-bootstrap.sh` runs `systemctl enable … || true`; a failed enable or
  a manual `systemctl disable` produces the same shape on a crashed scheduler. The watchdog recorded no
  failure, the check-in stayed `ok`, and restart/deploy refused with "only op=rollback re-arms".
- **Unbounded silence:** an abandoned window (quiesced web, dedicated host on its standing brake) left
  no scheduler anywhere and nothing paged — the shape has no age to escalate on.

The plan's own sentence "only the quiesce handler writes `disabled`" was false the day it was written.

## Solution (CTO ruling — hybrid)

1. **An on-host marker for provenance and age.** The `quiesce inngest` handler writes
   `/var/lib/inngest/quiesced-by-op` (`v, epoch, boot_id, host_id, run_id, capture_sha256,
   capture_count`) atomically after the capture and before disable/stop. `op=rollback`'s `enable`
   retires the capture and removes the marker before re-enabling. A unit that is neither active nor
   already attributed is refused (`quiesce_capture_unavailable`) instead of silently keeping an old file.
2. **Split the question by consumer.** A byte-identical `inngest_quiesce_state` (quiesced |
   disabled_unattributed | not_quiesced) sits in the three delivered scripts. **Start refusal reads the
   SHAPE only** (a lost marker must page, never restart a deliberately stopped scheduler); **attribution
   reads shape AND marker** (inventory verdict, capture resume).
3. **Freshness by identity, not timestamps.** Resume requires `sha256(capture) == marker.capture_sha256`
   and no `capture_consumed_at`. systemd timestamps were rejected: `InactiveEnterTimestamp` is empty
   after a reboot, so a mid-window reboot would have refused the resume and fired the alarm at once.
4. **Page on the two silent states.** `DISABLED_UNATTRIBUTED` → failure, issue, error check-in (no
   restart). Quiesced longer than `INNGEST_QUIESCE_GRACE_MIN` while the dedicated host is not healthy →
   `[ci/inngest-no-live-scheduler]` + error check-in.

## Key Insight

**A state is not an event.** When a design reuses an existing system state (a unit's enabled/active
shape, a flag's value, a file's existence) as a coordination signal, list every consumer and ask what
decision it makes. A consumer that only needs "must this not be started?" can read the state. A consumer
that decides to RESUME, REPLAY or SUPPRESS needs to know *who* produced the state and *when* — and a state
carries neither. "Avoid new state" is the right instinct against off-host markers that drift from the
host; it is the wrong conclusion when the artifact being resumed (the capture) is itself state with no
provenance. An on-host marker written by the same handler, beside the artifact, is not the rejected kind
of state.

Corollary for the split: attach the provenance requirement only to the consumers that need it. Requiring
the marker at the start-refusal sites would have converted "marker lost" into "deliberately stopped
scheduler restarted" — the original #8077 bug.

## Prevention

- **Plan time:** for any state signal consumed by a resume/replay/suppress decision, write one line per
  consumer: which state, whose provenance, what time. A consumer that needs provenance or time and gets
  neither is a design defect before a line is written. (Routed to plan/review SKILL.md.)
- **Falsify every "only X writes Y" claim** with `git grep` across bootstraps, cloud-init and manual
  runbook verbs before the plan asserts it.
- **Workflow run blocks must be EXECUTED by their tests**, not grepped: a probe-step arm rewritten to
  `inngest_down` stayed green against three grep rows.

## Session Errors

1. **Planning subagent killed by an API weekly-limit 429** before deepen-plan. Recovery: the plan (with
   Acceptance Criteria) was on disk; a second subagent ran deepen-plan only. **Prevention:** existing
   plan-artifact-recovery arm worked as designed.
2. **GitHub/Playwright MCP servers failed to connect.** Recovery: gh CLI. **Prevention:** none needed.
3. **#8135's host delivery was cancelled twice by the shared `terraform-apply-web-platform-host` group**;
   my re-dispatch was displaced by another session re-running its cancelled sibling (the two alternate).
   Recovery: dispatched only once both workflows showed zero non-completed runs. **Prevention:** tracked
   in #8167 (comment added).
4. **`gh workflow run` 422 — required input `reason`.** Recovery: passed `-f reason=…`. **Prevention:**
   read `on.workflow_dispatch.inputs` before dispatching.
5. **A polling Monitor failed OPEN**: after the worktree vanished its `gh` calls had no repo context, the
   "is the group busy" probe returned nothing, and it read "free" and attempted a dispatch. Recovery:
   `-R owner/repo` on every call and `|| return 0` (busy) on probe failure. **Prevention:** a Monitor whose
   decision gates a write must treat its own probe failure as the blocking state.
6. **I posted "web-2 was destroyed / CUTOVER_HOSTS is stale" on #6178 and #6921 before measuring it.**
   The Hetzner API showed `soleur-web-2` running since 2026-07-27. Recovery: correction comments on both.
   **Prevention:** an outward-facing causal claim gets its falsifying command (`GET /v1/servers`, a Better
   Stack `FANOUT` grep) run before posting, not after.
7. **`gh issue create` refused three times** (body-file named by an unexpanded variable; no User-Impact;
   Fix-Size 20/2 inside the inline threshold). Recovery: fixed inline in the PR. **Prevention:** the
   #8135 learning already says compute Fix-Size first; apply it before drafting a body.
8. **The refused-connection probe first targeted port 1**, which fetch blocks as "bad port" — the wrong
   error shape. Recovery: a closed allowed port (58287) gave the real `TypeError{cause.code:ECONNREFUSED}`.
   **Prevention:** probe with an ordinary closed high port.
9. **`node -e require("inngest/package.json")` → ERR_PACKAGE_PATH_NOT_EXPORTED**, and the `&&` chain
   skipped the probe heredoc. Recovery: read `node_modules/inngest/package.json` directly. **Prevention:**
   do not chain a probe's file creation behind an unrelated version read.
10. **`git commit` on a staged `.ts` sat behind the lefthook bun-test full battery** (shared lock) until
    my `timeout` killed it (rc 124). Recovery: `LEFTHOOK=0` after running the fast `.ts` linters by hand.
    **Prevention:** documented hatch; the full battery runs at ship Phase 4.
11. **Integration run 1 used wrong fixture-ratchet paths** (rc 127). Recovery: ran them from
    `plugins/soleur/test/`. **Prevention:** `git ls-files | grep` a suite path before listing it.
12. **The first implementation shipped ~58 review findings**, one P1 reproduced twice — the provenance
    gap above. Recovery: CTO ruling + a 5-agent fix round. **Prevention:** the plan-time consumer table
    (Key Insight); routed to plan/review SKILL.md.
13. **Tests pinned workflow TEXT, not behaviour**: the quiesced arm rewritten to `inngest_down` stayed
    green, and the declaration rows passed a broken placement while failing a safe one. Recovery: rows
    that execute the extracted run blocks under `-eo pipefail`. **Prevention:** review defect classes
    already name this; apply when writing, not after review.
14. **Assertion floors were not raised** after rows were added, and self-run batteries reported "all
    caught" while 13 mutants survived. Recovery: exact floors + helper self-tests. **Prevention:** existing
    ADR-193 guidance; count axes, not rows.
15. **The plan asserted "only the quiesce handler writes `disabled`"** — false (`inngest-bootstrap.sh`
    `enable || true`, manual disable). Recovery: `DISABLED_UNATTRIBUTED` verdict. **Prevention:** grep
    every writer of the state before the plan asserts exclusivity.
16. **The wiped-volume `quiesced_refused` gate was unreachable** (placed after an enumeration that always
    fails on a stopped unit) and its test stubbed an impossible success. Recovery: gate moved before
    enumeration, test uses a failing enumeration. **Prevention:** a refusal's fixture must model the
    state that triggers it end to end.
17. **The fixture-relative-assert ratchet went red mid-fix** (`ci-deploy.sh` 11 → 13 sites). Recovery:
    an `_atomic_write` helper brought it back to baseline without regenerating the ratchet.
    **Prevention:** run the P1b ratchet after every `*.sh` write-site edit.
