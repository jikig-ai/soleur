---
title: "An agent admin-merged #8458 while a required check did not yet exist"
date: 2026-09-21
incident_pr: 8474
incident_window: "2026-09-21T10:56:53Z – 2026-09-21T13:53:00Z"
recovery_at: "2026-09-21T13:53:00Z"
suspected_change: "Phase 7 admin-merge watch loop keyed on `gh pr checks --required`"
brand_survival_threshold: aggregate pattern
status: unresolved but ended
triggers:
  - "admin merge bypassed an absent required status check"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data involved; an internal CI-governance event"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The operator authorized a `soleur:one-shot` session to admin-merge PR #8458 "once every required check is green on its current head". The session's Monitor looped on `gh pr checks 8458 --required` until no check was pending, reported `ALL REQUIRED DONE: pass=25`, and ran `gh pr merge 8458 --squash --admin`. The `CI Required` ruleset lists 26 contexts. The missing one, `test`, is created only after its `test-scripts` shards finish, and `gh pr checks --required` lists only checks that exist. At merge time `test` was absent and one shard had already failed. `test` later concluded `failure`. `--admin` bypasses the whole `required_status_checks` rule, so nothing server-side stopped the merge.

## Status

unresolved but ended — the merge cannot be undone without a revert, and `main`'s `test` was already red for an unrelated reason (below). The gap that allowed the merge is closed in the hatch prose by PR #8474; the shared enforcing script, `plugins/soleur/scripts/admin-merge-ready.sh`, lands with #8547 (for #8500).

## Symptom

A squash commit (`d78264e4b`) landed on `main` without its required `test` context ever having concluded green on the PR head.

## Incident Timeline

- **Start time (detected):** 2026-09-21T13:53:00Z (#8500 filed)
- **End time (recovered):** 2026-09-21T13:53:00Z (no further unverified admin merges from this session; hatch prose fixed in #8474)
- **Duration (MTTR):** about 3 h from merge to detection

| Actor | Time (UTC) | Action |
|---|---|---|
| human | earlier in the session | Authorized an admin-merge of #8458 once every required check was green on its head. |
| agent | 10:56:45 | Monitor printed `ALL REQUIRED DONE: pass=25` (25 of 26 required contexts; `test` absent). |
| agent | 10:56:50 | Ran `gh pr merge 8458 --squash --admin --match-head-commit 285cc0982…`; merged as `d78264e4b`. |
| agent | 11:16:40 | The `test` context was created on the PR head and concluded `failure`. |
| human | 13:53:00 | #8500 filed under the operator's account (session or person not recorded) describing the absent-context merge and a second manual admin merge (#8439). |
| agent | 14:01 | Found #8500 via the net-issue-flow gate on PR #8474; replaced the hatch's vacuous wait with a ruleset-derived presence-and-green check. |

## Participants and Systems Involved

The one-shot agent session on PR #8474, the operator, GitHub's `CI Required` ruleset (26 contexts, `--admin` bypass allowed for OrganizationAdmin), and `ci.yml`'s `test` aggregator.

## Detection (+ MTTD)

- **How detected:** a check-timeline reconstruction recorded in #8500 (filed under the operator's account).
- **MTTD (mean time to detect):** about 3 h.

## Triggered by

system — an agent-authored watch loop.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| `gh pr checks --required` cannot report a required context that has not been created | 25 listed vs 26 in the ruleset; `test` created 20 min after the merge | none | confirmed |

## Resolution

PR #8474 rewrote step 2 of the settle-then-admin-merge procedure (`plugins/soleur/skills/ship/references/settle-then-admin-merge.md`). It reads the required set from the ruleset API, takes the newest check run per context on the head SHA, and prints `ADMIN-MERGE-READY` only when every one is present and success/skipped/neutral. Merges pin `--match-head-commit`.

PR #8547 (for #8500) replaced that inline block with `plugins/soleur/scripts/admin-merge-ready.sh`, a tested script that ship, merge-pr, one-shot and drain-prs all route an `--admin` merge through; the reference's merge block re-runs it before every attempt.

## Recovery verification

Driven on 2026-09-21 against real PRs: #8458's head reports `NOT-READY: NOT-GREEN:test`, and #8474's head, before its CI had run, reports every absent context by name.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why was #8458 merged unverified? The watch loop ended when no listed required check was pending.
2. Why was `test` not listed? `gh pr checks --required` only lists checks that exist, and `test` is created after its shards finish.
3. Why did the loop trust that listing? The hatch said "present and green" in prose, and the natural implementation of "wait until nothing is pending" is vacuous for an absent context.
4. Why did nothing else stop it? `--admin` bypasses every required context, not just the up-to-date rule.
5. Why was the count not compared? The loop never read the ruleset's required list, so 25 read as "all".

## Versions of Components

- **Version(s) that triggered the outage:** the Phase 7 admin-merge watch written ad hoc in this session.
- **Version(s) that restored the service:** PR #8474 (hatch step 2 presence-and-green check).

## Impact details

### Services Impacted

`main`'s CI signal. No production deploy was affected: `main`'s `test` was already failing on the two preceding commits (`907066c2d`, `8986da7ed`) from kb-index AC17 drift tracked in #8370, so CI on `main` was already red before this merge; whether any deploy arm ran on these commits was not checked. #8458's own change (the `sync-pr-behind.sh` caller-worktree fix) was not the cause of that failure.

### Customer Impact (by role)

- Prospect: none
- Authenticated app user: none known — #8458 changes a developer script, not app code
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None.

### Team Impact

A required-check guarantee on `main` was bypassed without evidence; the timeline had to be reconstructed after the fact from check-run data.

## Lessons Learned

### Where we got lucky

`main` was already red for an unrelated reason, and #8458's change was a small, already-diffed hunk that PR #8474 carries verbatim, so its content had been exercised by #8474's suites.

### What went well

The operator's authorization was scoped to a condition; the condition itself was right.

### What went wrong

The agent reported a count (25) as a verdict without comparing it to the ruleset (26), and the same vacuous loop was then written into the hatch's own instructions during QA.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #8500 | A shared `admin-merge-ready` script that every skill must call before `gh pr merge --admin`, plus a mutation row for the N−1 shape. | addressed by #8547 |
| #8370 | Fix the kb-index AC17 freshness failure that left `main`'s `test` red. | open |
