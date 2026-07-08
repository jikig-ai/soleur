---
title: "fix(ci): complete verify/068 jti_deny per-table drift guard (26 count / 21 named → 26/26)"
issue: 6233
branch: feat-one-shot-6233-verify-migrations-068-jti-deny-count
type: bug
date: 2026-07-08
lane: cross-domain
brand_survival_threshold: none
detail_level: minimal
---

# 🐛 fix(ci): complete verify/068 jti_deny per-table drift guard

> Spec lacks valid `lane:` (no `spec.md` for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

`Web Platform Release → verify-migrations` was failing on `main` at
`068_jti_deny_rls_predicate_and_revoke_rpc.sql/jti_deny_policies_count_23: FAIL (bad=1)`,
gating the `deploy` job (issue #6233).

**The reported defect is already resolved on `main`.** PR **#6229** (`a4d8208e8`, merged
2026-07-08 13:19 UTC) bumped the count sentinel `23 → 26` (renamed `count_23 → count_26`)
to account for the 3 beta-CRM `*_jti_not_denied` policies added by migration `126`. Every
`Web Platform Release` run since is green (`a4d8208e`, `1688bfee`, HEAD `94c7783e`). Live
`pg_policies` on **dev and prd both return 26** matching RESTRICTIVE `*_jti_not_denied`
policies (see Research Reconciliation). So the count is correct and CI is unblocked.

#6229 did **not** `Closes #6233` (its body says only `Refs #6160`), so #6233 remained open
after the fix — and #6229 was an explicit *hotfix* that did the minimum to unblock deploys
(the count bump) **without** completing the guard's per-table half.

**This plan's deliverable** is the residual completeness work #6229 left behind: the count
sentinel now asserts **26** but the file only carries **21** per-table
`*_jti_not_denied_policy_present` assertions (the mig-068 base array). The 5 later policies
— `workspace_activity` (mig 076), `kb_files` (mig 077), `beta_contacts` /
`interview_notes` / `beta_contact_stage_transitions` (mig 126) — have **no** per-table
presence assertion, and the file header falsely claims "Each of the 26 tenant tables has its
own policy." We add the 5 missing per-table assertions so the named set (26) equals the
count (26), closing the count-vs-identity proxy gap the issue itself names ("the all-members
drift guard turns main red when a sibling adds a member" class). Then close #6233.

Verify-SQL-only change: no runtime code, no schema change, no DDL, no user-facing surface.

## Research Reconciliation — Premise vs. Codebase / Live State

| Premise (from #6233) | Reality (verified 2026-07-08) | Plan response |
|---|---|---|
| `068` verify sentinel asserts `= 23`, fails on main | Already `= 26` (`jti_deny_policies_count_26`) on main since #6229 `a4d8208e8` | Count is correct — no count change needed |
| verify-migrations red on main, blocks deploy | Green since `a4d8208e`; `1688bfee` + HEAD `94c7783e` also green | Confirm CI stays green post-change (AC) |
| "update the sentinel count OR fix a missing policy" | Live count dev=26, prd=26; all 5 newer tables present in both | Live schema correct — no policy fix needed |
| #6233 tracks the count fix | #6229 fixed the count but is `Refs #6160`, never `Closes #6233` | Close #6233 in this PR |
| (implicit) guard is complete | Count=26 but only **21** per-table assertions; 5 tables unnamed; header comment says "26 tables … own policy" (false) | **Add 5 per-table presence assertions; correct header comment** |

Premise Validation note: The one external premise (the sentinel count) was validated and
found **stale** — resolved by merged PR #6229. No blocker premises remain. The only in-scope
work is the guard-completeness gap #6229's hotfix scope left open, which is squarely within
#6233's stated root-cause framing.

Live reconciliation queries (read-only, both returned 26):
- prd `ifsccnjhymdmidffkzhl`: 26 policies incl. `workspace_activity, kb_files, beta_contacts, interview_notes, beta_contact_stage_transitions`.
- dev `mlwiodleouzwniehynfz`: 26 policies; the 5 newer tables all present (`newer5_present = 5`).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this edits a CI
  `verify/*.sql` drift sentinel only. A broken *assertion* (e.g., wrong policy name in a new
  presence check) would turn `verify-migrations` red and re-gate `deploy`, delaying feature
  rollout (same blast radius as the bug being fixed) — caught pre-merge by CI on the PR.
- **If this leaks, the user's data is exposed via:** N/A — no data is read/written/exposed;
  the change asserts on `pg_policies` catalog metadata only, no schema or RLS behavior change.
- **Brand-survival threshold:** none, reason: CI-only change to a `verify/` drift-sentinel's
  per-table presence assertions — no runtime code, no schema/RLS change, no user-facing
  surface; it only strengthens a post-merge gate.

## Implementation Phases

### Phase 1 — Add the 5 missing per-table presence assertions
Edit `apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql`.
Append 5 `UNION ALL SELECT … _jti_not_denied_policy_present` rows mirroring the existing
21-assertion style, for `workspace_activity`, `kb_files`, `beta_contacts`, `interview_notes`,
`beta_contact_stage_transitions`. Each row asserts exactly one RESTRICTIVE policy of that
name on that table:

```sql
UNION ALL
SELECT 'workspace_activity_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='workspace_activity'
   AND policyname='workspace_activity_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'kb_files_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='kb_files'
   AND policyname='kb_files_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'beta_contacts_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='beta_contacts'
   AND policyname='beta_contacts_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'interview_notes_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='interview_notes'
   AND policyname='interview_notes_jti_not_denied' AND permissive='RESTRICTIVE'
UNION ALL
SELECT 'beta_contact_stage_transitions_jti_not_denied_policy_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies WHERE schemaname='public' AND tablename='beta_contact_stage_transitions'
   AND policyname='beta_contact_stage_transitions_jti_not_denied' AND permissive='RESTRICTIVE'
```

**SQL structure sharp edge:** the assertions form one `UNION ALL` chain. The current file's
**final** `SELECT` has no trailing `UNION ALL`. Insert the 5 new rows so exactly one `SELECT`
remains terminal (either append all 5 after the current last assertion — making the 5th new
row terminal — or splice mid-chain). Preserve any terminal `;`/`ORDER BY` the file already
has. Read the file's tail before editing (`hr-always-read-a-file-before-editing-it`).

### Phase 2 — Correct the header comment
The header block already says "Exactly 26 RESTRICTIVE policies … Each of the 26 tenant tables
has its own policy." After Phase 1 that becomes literally true. Add the 5 table names to the
per-table-provenance comment (mig 076 `workspace_activity`, mig 077 `kb_files`, mig 126
`beta_contacts`/`interview_notes`/`beta_contact_stage_transitions`) so the file documents that
all 26 are individually asserted, not just counted.

### Phase 3 — Close #6233
On merge, `gh issue close 6233` (via ship post-merge). PR body uses `Closes #6233` in the
body (not title) so it auto-closes at merge — acceptable here because the fix is code-in-PR
(not an ops-remediation that runs post-merge).

## Files to Edit
- `apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql` — add 5 per-table assertions (Phase 1) + correct header comment (Phase 2).

## Files to Create
- None.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `grep -cE "_jti_not_denied_policy_present'" apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql` returns **26** (was 21).
- [ ] The count sentinel line remains `jti_deny_policies_count_26` asserting `count(*) = 26` (unchanged — do not touch the count).
- [ ] The file contains a per-table presence assertion for each of `workspace_activity`, `kb_files`, `beta_contacts`, `interview_notes`, `beta_contact_stage_transitions`.
- [ ] The `UNION ALL` chain is well-formed: exactly one terminal `SELECT` (no trailing `UNION ALL`); verify by piping the file through a Postgres parse (`psql -f` against a scratch DB, or the repo's existing verify-runner harness) with **0 syntax errors**.
- [ ] Header comment enumerates all 26 tables' provenance (21 base + 076/077 + 126); no claim in the file is falsified by the assertions.
- [ ] PR body uses `Closes #6233`.

### Post-merge (operator/automated)
- [ ] `Web Platform Release → verify-migrations` on the merge commit is **green** and reports `22 passed, 0 failed`-style summary with the count now 26 checks + 26 per-table checks (verified via `gh run list --workflow "Web Platform Release" --branch main` — automatable, ship handles).
- [ ] #6233 is closed (auto via `Closes`).

## Domain Review

**Domains relevant:** none

CI drift-guard hardening on a `verify/*.sql` sentinel. No product/UX surface (no
`components/**`, `app/**/page.tsx`, or UI-surface path in Files to Edit), no marketing/sales/
finance/legal/support implication, no infrastructure provisioning. Engineering-only, verify-SQL.

## GDPR / Compliance Gate

Not materially triggered. The change edits a `.sql` file (surface the canonical regex flags),
but it adds **read-only assertions on `pg_policies` catalog metadata** — no new processing
activity, no schema change, no auth-flow change, no personal-data movement. No `(a)-(d)`
expansion trigger fires (no LLM/external-API on session data, threshold=none, no cron reading
learnings/specs, no new distribution surface). Scope-out recorded per Phase 2.7.

## Observability

`liveness_signal`: the `verify-migrations` job in `Web Platform Release` **is** the liveness
signal for this guard — it runs on every push to `main` that migrates, fails the pipeline
(gating `deploy`) on any `bad > 0` row, and surfaces the failing `check_name` in the job log.
This change strengthens that existing signal (26 per-table pinpoints vs. a single aggregate
count). `discoverability_test` (NO ssh): `gh run view <id> --log | grep jti_deny` — the per-table
`*_jti_not_denied_policy_present` check names name the exact drifted table on failure. No new
error path, log call, or infra surface is introduced (verify SQL only), so the 5-field infra
schema is not otherwise applicable.

## Architecture Decision (ADR / C4)

None. This adds presence assertions to an existing drift sentinel for the already-shipped
jti-deny RLS model (ADRs/migrations 068/069). No ownership/tenancy boundary move, no new
substrate/integration, no resolver/trust-boundary change, no reversal/extension of an existing
ADR. **C4 (all three `.c4` files checked):** the jti-deny RLS mechanism is an internal
Postgres RLS invariant, not a C4 external actor / external system / data-store / access
relationship — no new correspondent, vendor, container, or actor↔surface edge is introduced or
changed. No C4 impact.

## Test Scenarios

1. **Happy path (live-correct):** all 26 policies present → all 26 per-table checks + count
   check return `bad=0` → verify-migrations green. (Confirmed against dev+prd live: 26/26.)
2. **Simulated single-table drift:** if a future migration drops (e.g.) `kb_files_jti_not_denied`,
   the count sentinel drops to 25 (fails in aggregate) **and** `kb_files_jti_not_denied_policy_present`
   returns `bad=1`, naming the exact table — the pinpoint this plan adds.
3. **Count-vs-identity guard:** if a future migration drops one expected policy but adds an
   unrelated `*_jti_not_denied` policy (count stays 26), the per-table presence check for the
   dropped table fails even though the count passes — the proxy gap this plan closes.

## Alternative Approaches Considered

| Alternative | Why not chosen |
|---|---|
| Close #6233 as "resolved by #6229", no code change | Leaves the guard asymmetric (26 count / 21 named) and the header comment false; a bare `gh issue close` yields no mergeable pipeline artifact and no lasting improvement. |
| Redesign the sentinel to derive the expected count from a canonical table list (eliminate the magic 26) | Larger blast radius, changes the file's established pattern, and is YAGNI for this issue. Deferred — see below. |
| Auto-generate per-table assertions in a `DO` loop like mig 068 | Verify files are flat `UNION ALL` result sets (each row must be a static `check_name`); a loop can't emit result rows the harness reads. Not applicable. |

**Deferred (optional, not blocking #6233):** derive the count from an enumerated canonical
table array so the count and per-table set are maintained in one place. If pursued, file a
follow-up issue with re-evaluation criteria (next time a jti-deny table is added). Not created
now — the recurring maintenance is already documented in the file header and is low-frequency.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is
  filled with threshold `none` + reason.)
- **Do not touch the count sentinel** (`jti_deny_policies_count_26`). It is correct (live=26).
  The only edit is adding the 5 per-table rows + the header comment.
- **Terminal `SELECT` in the `UNION ALL` chain:** appending a row with a trailing `UNION ALL`
  and no following `SELECT` is a syntax error. Read the file tail; make exactly one `SELECT`
  terminal; preserve any terminal `;`.
- **Policy-name exactness:** each new assertion's `policyname` must match the migration's
  literal `CREATE POLICY <name>` (verified: `workspace_activity_jti_not_denied` mig 076,
  `kb_files_jti_not_denied` mig 077, `beta_contacts_jti_not_denied` /
  `interview_notes_jti_not_denied` / `beta_contact_stage_transitions_jti_not_denied` mig 126).
  A typo turns verify red — the same class this plan hardens against.
