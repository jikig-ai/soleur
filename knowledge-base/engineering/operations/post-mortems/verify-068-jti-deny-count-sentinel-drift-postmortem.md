---
title: "verify/068 jti_deny count-sentinel drift blocked Web Platform Release deploys on main"
date: 2026-07-08
incident_pr: "#6236"
incident_window: "2026-07-08 12:38 UTC → 2026-07-08 13:19 UTC (~41 min)"
recovery_at: "2026-07-08T13:19:44Z"
suspected_change: "Migration 126 (beta-CRM, #6160 ee58951b) added 3 RESTRICTIVE *_jti_not_denied policies (live count 23→26) without updating verify/068's jti_deny_policies_count_23 sentinel."
brand_survival_threshold: none
status: resolved
triggers:
  - system
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

`verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql` carries a drift sentinel
`jti_deny_policies_count_23` asserting exactly 23 RESTRICTIVE `*_jti_not_denied`
RLS policies. Migration 126 (beta-CRM, #6160) added 3 more such policies
(`beta_contacts`, `interview_notes`, `beta_contact_stage_transitions`), moving
the live count to 26 without updating the sentinel's expected value. From that
merge onward, the `verify-migrations` job of every `Web Platform Release` run
failed on `main`, and because `verify-migrations` gates the `deploy` job, all
app-container deploys to production were blocked (production kept running the
prior, healthy build — no user-facing outage).

## Status

resolved — the count sentinel was corrected 23→26 by #6229 (`a4d8208e`); this PR
(#6236) completes the residual per-table half of the guard.

## Symptom

`Web Platform Release → verify-migrations` red on `main` at
`068_jti_deny_rls_predicate_and_revoke_rpc.sql/jti_deny_policies_count_23: FAIL (bad=1)`
across consecutive commits (`ee58951b` #6160, `409cf4fa` #6225, `957350d8` #6218),
gating `deploy`.

## Incident Timeline

- **Start time (detected):** 2026-07-08 12:38 UTC (mig 126 merged; count drifted)
- **End time (recovered):** 2026-07-08 13:19 UTC (#6229 bumped sentinel 23→26)
- **Duration (MTTR):** ~41 minutes

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-08 12:38 | #6160 (`ee58951b`, mig 126 beta-CRM) merges; live `*_jti_not_denied` policy count moves 23→26 while `verify/068` still asserts 23. `verify-migrations` starts failing on main. |
| agent | 2026-07-08 ~13:00 | Drift discovered incidentally during #6218 post-merge verification (that PR added no migrations; its own infra applies succeeded). |
| agent | 2026-07-08 13:19 | #6229 (`a4d8208e`) bumps the sentinel 23→26; `Web Platform Release` goes green; deploys unblocked. |
| agent | 2026-07-08 15:31 | #6237 (`e656434f`, #6232 residual) adds the 3 beta-CRM per-table presence assertions (named set 21→24). |
| agent | 2026-07-08 (this PR) | #6236 adds the final 2 per-table assertions (`workspace_activity` mig 076, `kb_files` mig 077) that #6237's beta-CRM scope left behind (named set 24→26 == count), and closes the tracking issue #6233. |

## Participants and Systems Involved

CI (`Web Platform Release` workflow, `verify-migrations` job), Supabase Postgres
RLS policy catalog (`pg_policies`), the jti-deny RLS model (migrations 068/069/076/077/126).

## Detection (+ MTTD)

- **How detected:** internal — surfaced incidentally during #6218 post-merge verification (the failing `verify-migrations` job on the release run), not by a dedicated monitor.
- **MTTD:** ~22 min after the drift entered (12:38 → ~13:00).

## Triggered by

system — a sibling migration adding members to an aggregate-count-guarded set without updating the guard's expected count.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Mig 126 added policies without bumping the 068 count sentinel | Live `pg_policies` = 26; sentinel asserted 23; failure began at `ee58951b` | none | confirmed |

## Resolution

#6229 (`a4d8208e`) bumped `jti_deny_policies_count_23` → `..._count_26`, matching
the live schema (dev + prd both = 26). `verify-migrations` green from that commit
onward. The per-table (identity) half was then completed across two PRs: #6237
(#6232 residual) added the 3 beta-CRM presence assertions (21→24), and #6236
(this PR) added the final 2 (`workspace_activity` mig 076, `kb_files` mig 077),
so the named set equals the count (24→26), closing the count-vs-identity gap the
count-only hotfix left open.

## Recovery verification

`Web Platform Release` runs on `a4d8208e` (#6229), `1688bfee` (#6231) concluded
`success`. Live read-only verify query against dev (`mlwiodleouzwniehynfz`) after
#6236's change: 35 checks, 0 failing, 26 per-table checks pass.

## Root Cause(s) — 5-Whys

1. Why did verify-migrations go red? — The 068 count sentinel asserted 23 but the live count was 26.
2. Why was the live count 26? — Mig 126 added 3 `*_jti_not_denied` policies.
3. Why didn't the sentinel update? — It is a hardcoded magic-number count; adding a member to the guarded set does not force a same-PR update of the count.
4. Why is that a recurring class? — "All-members drift guard turns main red when a sibling adds a member": the count and the per-table set are maintained by hand in a different file from the migration that changes the set.
5. Why wasn't it caught pre-merge? — Mig 126's PR CI did not run the count sentinel against the post-merge combined schema; the drift only manifests once the policy lands on main.

## Versions of Components

- **Version(s) that triggered the outage:** `ee58951b` (#6160, mig 126).
- **Version(s) that restored the service:** `a4d8208e` (#6229).

## Impact details

### Services Impacted

`Web Platform Release` → `deploy` job (blocked). Production app container kept serving the prior healthy build.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none (prod served the prior build throughout).
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None. No user-facing degradation; only new app-container deploys were paused for ~41 min.

## Lessons Learned

### Where we got lucky

The drift guard itself fired correctly — the red `verify-migrations` job is exactly the signal it exists to produce. No broken schema shipped; deploys were blocked (fail-safe), not corrupted.

### What went well

The guard turned `main` red immediately on the drift, and #6229 restored green within ~41 min.

### What went wrong

The count-only hotfix (#6229) restored green but left the guard's per-table (identity) half incomplete — the count asserted 26 while only 21 tables were individually named, so a future "one dropped + one unrelated added" swap would pass the count while the set is wrong. It also did not `Closes #6233`, so the tracking issue stayed open.

### What we changed

#6236 completes the per-table half (26 named == 26 counted). Recurrence-prevention beyond that (deriving the expected count from a canonical table list to eliminate the magic number) was evaluated and deferred as YAGNI in the plan — low-frequency maintenance, already documented in the file header.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
