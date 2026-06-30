---
title: "Merge queue deadlocked main — CodeQL default setup does not post on merge_group temp refs"
date: 2026-07-01
incident_pr: 5800
incident_window: "2026-06-30T21:41:55Z .. 2026-06-30T21:56:00Z (~14 min queue deadlock; no merges lost)"
recovery_at: "2026-06-30T21:56:00Z (approx — kill-switch terraform apply complete)"
suspected_change: "PR #5800 enabled a GitHub merge queue on main (merge_queue ruleset rule)"
brand_survival_threshold: none
status: resolved
triggers:
  - merge queue enabled with CodeQL as a required context that does not report on merge_group
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

PR #5800 (PR-2 of #5780) enabled a GitHub merge queue on `main` by adding a
`merge_queue` rule to the `CI Required` ruleset. Within minutes, three real PRs
(#5808, #5794, #5798) entered the queue and stalled in `AWAITING_CHECKS`
indefinitely. Root cause: the ruleset requires a `CodeQL` status context
(GitHub Advanced Security, integration_id 57789), but GitHub **CodeQL default
setup runs only on `push` / `pull_request` — never on `merge_group`**. The
queue dispatches each candidate against a `gh-readonly-queue/main/pr-*` temp
ref via a `merge_group` event; CodeQL never posted on that ref, so every queue
entry waited forever for a required check that could not arrive. The merge path
to `main` was effectively down for all PRs until the kill-switch reverted the
queue.

## Status

resolved — kill-switch (remove the `merge_queue` rule) applied; queue disabled;
main back on direct-merge where CodeQL runs on `pull_request`.

## Symptom

Queue entries stuck `AWAITING_CHECKS`; on the oldest temp ref, all 15 other
required contexts reported success/skip while `CodeQL` was entirely absent (no
check-run, no check-suite). No merges could complete via the queue.

## Incident Timeline

- **Start time (detected):** 2026-06-30T21:52:00Z (approx)
- **End time (recovered):** 2026-06-30T21:56:00Z (approx)
- **Duration (MTTR):** ~4 min from detection to kill-switch apply; ~14 min total queue-deadlock window from first-entry-enqueued.

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-06-30T21:36:29Z | PR #5800 merged; `merge_queue` rule applied to ruleset 14145388 via apply-github-infra.yml. |
| system | 2026-06-30T21:41:55Z | First PR (#5808) enters the queue → `AWAITING_CHECKS`. |
| system | 2026-06-30T21:45:56Z | #5794 enqueued. |
| system | 2026-06-30T21:48:40Z | #5798 enqueued. |
| agent | 2026-06-30T21:52:00Z | Post-enablement canary probe finds all 3 entries stuck; full-pagination check-run diff shows `CodeQL` is the ONLY missing required context on the temp ref; check-suites confirm no CodeQL/code-scanning suite. Deadlock confirmed. |
| agent-with-ack | 2026-06-30T21:56:00Z | Kill-switch: remove `merge_queue` rule from `ruleset-ci-required.tf`, `terraform apply` (0 add / 1 change / 0 destroy). merge_queue rule count → 0; required_status_checks intact at 16. |
| system | 2026-06-30T21:56:30Z | Queue empty; #5808/#5794/#5798 return to `OPEN CLEAN` (direct-merge restored). |

## Participants and Systems Involved

GitHub merge queue, the `CI Required` ruleset (id 14145388) managed by
`infra/github/` Terraform, GitHub CodeQL default setup (GHAS), and the
`apply-github-infra.yml` auto-apply workflow.

## Detection (+ MTTD)

- **How detected:** the post-enablement canary the operator asked to "complete
  the remaining" work ran the discoverability + queue-drain probes and caught
  the stall directly (not via the standing `merge-queue-stall-check.yml` cron,
  which would also have fired at the 15-min threshold).
- **MTTD:** ~10 min (first entry enqueued 21:41:55Z → confirmed 21:52Z).

## Triggered by

system — the merge queue, once enabled, dispatched `merge_group` builds whose
required `CodeQL` context had no producer on that event.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| CodeQL default setup does not post on merge_group temp refs | `CodeQL` is the only required context absent from the temp ref; no code-scanning check-suite present; all 15 PR-1-wired producers DID post | none | CONFIRMED |
| A PR-1 producer workflow lacks merge_group | 15/16 contexts present and passing on the temp ref | the 15 non-CodeQL contexts all reported | REJECTED |

## Resolution

Applied the documented, reversible kill-switch: removed the `merge_queue` rule
from `infra/github/ruleset-ci-required.tf` and `terraform apply`-d
(`0 to add, 1 to change, 0 to destroy`). Verified: live `merge_queue` rule
count = 0, `required_status_checks` count = 16 (CodeQL still required, now
satisfied on `pull_request` via direct-merge). The three stuck PRs returned to
`OPEN CLEAN`.

## Recovery verification

- `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '[.rules[]|select(.type=="merge_queue")]|length'` → `0`.
- `gh api graphql ... mergeQueue(branch:"main")` → `no queue`.
- `#5808/#5794/#5798` each `OPEN CLEAN`.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the queue deadlock?** Every entry waited on a required `CodeQL`
   context that never posted on the `merge_group` temp ref.
2. **Why did CodeQL not post on merge_group?** CodeQL *default setup* only
   triggers on `push` and `pull_request`; it has no `merge_group` trigger.
3. **Why was that not caught before enabling?** The plan flagged this as a
   Phase-0 HARD GATE ("confirm CodeQL default setup supports merge queues
   empirically; if unconfirmed, PR-2 holds"), but the gate was never executed
   as an empirical probe — the implementing session trusted the plan's parenthetical
   "(CodeQL is default-setup)" note instead.
4. **Why was the empirical gate skipped?** The PR-2 planning subagent was killed
   by a session limit; recovery loaded the already-written plan from disk and
   proceeded to implementation, treating the plan's prose as settled fact rather
   than re-deriving the unverified Phase-0 preconditions.
5. **Why does that matter generally?** A recovered-from-disk plan's "verify X
   before shipping" preconditions are UNVERIFIED claims, not completed steps —
   the recovery path must re-run empirical hard gates, not inherit them as done.

**Final root cause:** CodeQL default setup is structurally incompatible with a
required-`CodeQL` merge queue (no `merge_group` trigger), and the empirical
Phase-0 gate that would have caught this pre-merge was skipped during a
subagent-crash recovery.

## Versions of Components

- **Version(s) that triggered the outage:** PR #5800 (merge_queue rule on ruleset 14145388); CodeQL default setup (languages actions/javascript-typescript/python, extended suite).
- **Version(s) that restored the service:** kill-switch apply (merge_queue rule removed). Roll-forward: CodeQL **advanced** setup (`.github/workflows/codeql.yml`, `on: merge_group`) + queue re-enable.

## Impact details

### Services Impacted

CI merge path to `main` (all PRs). No production/runtime impact — prod kept
serving the prior commit; `/health` 200 throughout.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

(Internal developer/operator impact only: merges to main blocked ~14 min.)

### Revenue Impact

None.

### Team Impact

~14 min where no PR could merge to main; three PRs transiently stuck (none lost).

## Lessons Learned

### Where we got lucky

The operator asked to "complete the remaining" canary, which surfaced the
deadlock in ~10 min. Unwatched, the standing stall probe would have caught it at
the 15-min threshold — still fine, but the canary made it immediate. The failure
mode was loud (stuck entries) and the kill-switch was `0 destroy` and instant.

### What went well

PR-1's `merge_group` wiring was correct — 15/16 required contexts posted on the
temp ref. Diagnosis was unambiguous (full-pagination check-run diff isolated
`CodeQL` as the sole gap). The reversible kill-switch worked exactly as the ADR
designed.

### What went wrong

The Phase-0 empirical CodeQL-on-merge_group gate was never run; the queue was
enabled on an unverified precondition inherited from a crash-recovered plan.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5780 | Roll forward: land CodeQL advanced setup (`.github/workflows/codeql.yml`, `on: merge_group`), disable CodeQL default setup, verify the required `CodeQL` context posts on a real ref, then re-enable the merge queue and confirm the queue drains (post-enablement canary). | open |
