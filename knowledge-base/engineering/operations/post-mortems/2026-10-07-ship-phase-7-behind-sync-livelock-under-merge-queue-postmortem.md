---
title: "Ship Phase 7 synced an armed BEHIND PR on a merge-queue repo and restarted CI each time"
date: 2026-10-07
incident_pr: 9710
incident_issue: 9697
incident_window: "2026-10-07 syncs at 13:19, 13:25, 13:53 (local clock as reported); operator stopped the loop by hand during the 4th cycle at 14:07"
recovery_at: "n/a — the loop was stopped by hand; PR #9697 then enqueued without a further push"
suspected_change: "ADR-270 turned the merge queue on for main (#9454) while Phase 7 kept its pre-queue rule of syncing every OPEN BEHIND PR"
brand_survival_threshold: none
status: resolved
triggers:
  - PR #9697 (a test-only flake fix) stayed unmerged across three Phase 7 sync pushes and a fourth running CI cycle
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — a delay in merging one internal pull request. No personal data was stored, processed or disclosed."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

# Incident Overview

On a repo whose `main` has a merge queue (ADR-270), the Phase 7 merge poll of `soleur:ship` kept running `sync-pr-behind.sh --step` on an `OPEN BEHIND`, auto-merge-armed PR. Each sync pushed a merge of `origin/main` into the branch and restarted the required-check set (about 20 minutes). `main` moved faster than that, so the PR was BEHIND again by the time CI finished. Only the merge of one internal PR was delayed; no production service, user data or user-facing surface was involved.

## Status

resolved — Phase 7 and the `merge-pr` mirror now wait on a BEHIND, armed PR when a merge queue exists (PR #9710).

## Symptom

PR #9697 showed `OPEN BEHIND` after every green CI cycle and never merged; the branch head changed three times by sync pushes.

## Incident Timeline

- **Start time (detected):** 2026-10-07 14:07 (local clock as reported), fourth cycle still running
- **End time (recovered):** the loop was halted by hand; no further sync was pushed to #9697
- **Duration (MTTR):** under one hour of operator-observed delay

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 13:19 (local) | Phase 7 sync push 1 |
| agent | 13:25 (local) | Phase 7 sync push 2 |
| agent | 13:53 (local) | Phase 7 sync push 3 |
| human | 14:07 (local) | Operator saw the fourth cycle running, stopped the loop by hand and asked for the cause to be fixed |

## Participants and Systems Involved

`soleur:ship` Phase 7 poll, `plugins/soleur/scripts/sync-pr-behind.sh`, the `main` ruleset (`strict_required_status_checks_policy = true`, merge queue), GitHub auto-merge.

## Detection (+ MTTD)

- **How detected:** manual — the operator watched the PR state cycle.
- **MTTD (mean time to detect):** about 48 minutes from the first sync.

## Triggered by

system — the poll's own sync rule.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Sync is unnecessary under a merge queue, and was restarting CI | #9697 enqueued while BEHIND with no push; queue builds each candidate against the projected post-merge state | none found | confirmed |
| Strict policy blocks auto-enqueue of a BEHIND PR | none | #9697 enqueued while BEHIND | refuted |

## Resolution

Queue mode in the Phase 7 fence and its `merge-pr` mirror (PR #9710): with a `merge_queue` rule and auto-merge armed, a BEHIND tick prints `[ship.phase7.queue_wait]` and does not push; after more than 5 consecutive idle ticks it falls back to today's sync, whose own queue gate refuses to push a queued PR. No rule, an API error or an empty required set keep today's behaviour exactly.

## Recovery verification

`bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` reports 973 pass, 0 fail, and a 26-row mutation battery turns each deleted branch RED. The first real queue-mode PR is recorded on #9454 after merge.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. The PR never merged because each CI cycle ended BEHIND. 2. `main` moved faster than a cycle. 3. Phase 7 pushed a sync on every BEHIND, restarting the cycle. 4. The rule dates from before the merge queue, where up-to-date was the author's job. 5. Nothing made the poll consult the queue before pushing; the livelock was documented three times and "rely on the merge queue" was recorded as an option each time.

## Versions of Components

- **Version(s) that triggered the outage:** Phase 7 at origin/main before PR #9710
- **Version(s) that restored the service:** PR #9710

## Impact details

### Services Impacted

None in production. One internal PR (#9697) merge delayed.

### Customer Impact (by role)

- Prospect: none
- Authenticated app user: none
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None.

### Team Impact

About an hour of operator attention and roughly three wasted CI cycles of runner time.

## Lessons Learned

### Where we got lucky

The livelocked PR was a small test-only fix, and #9697 stayed pinned long enough to show that GitHub enqueues a BEHIND armed PR.

### What went well

The operator stopped the loop before it burned more cycles, and a pinned PR supplied the evidence for the fix.

### What went wrong

A platform feature removed the reason for a workaround and nothing prompted a search for the workaround.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #8683 | Option A (settle before sync) for repos without a merge queue; also the hard-rule line "BEHIND to resync main" in AGENTS.rules.md needs a queue_wait exception under human review | open |
