---
title: "fix: extend preflight-worm-cascade-contradiction gate to transitive (non-users) FK chains on WORM-gated tables"
type: fix
date: 2026-10-15
slug: fix-preflight-transitive-fk
branch: feat-one-shot-10379-preflight-transitive-fk
issue: 10379
closes: 10379
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

No infrastructure is provisioned or modified by this plan; it edits one
bash gate script and its fixture test. The ack above opts out of the IaC
routing gate per its documented escape.

# fix: extend preflight-worm-cascade-contradiction gate to transitive (non-users) FK chains on WORM-gated tables

## Overview

`apps/web-platform/scripts/preflight-worm-cascade-contradiction.sh` (#5372)
scans only FKs whose `confrelid = 'public.users'::regclass`
(gate line 137). The #10254 wedge —
`action_sends.message_id → public.messages` bare `REFERENCES` (NO ACTION,
mig 051:103) — was a **table-to-table** chain: `auth.users → messages
(CASCADE, mig 046:93) → action_sends (NO ACTION abort, 23503)`. It sat
outside the gate's envelope and shipped to main green; mig 162 removed it.

The fix is one script extension (plus its fixture test): the gate gains a
**user-erasure delete-cone** computed as a recursive CTE over
`pg_constraint` (seed `{auth.users, public.users}`, propagate through
`confdeltype='c'` edges — only CASCADE propagates row *deletion*), then
classifies **every** FK on every WORM-gated table (a table carrying a
raising UPDATE/DELETE trigger — the existing `prosrc` heuristic) by
(a) whether the referenced parent is in the cone and (b) the RI action
shape. No allowlist file is required: under the recommended disposition
matrix every live shape lands exactly where the completed audit says it
should (see §Disposition).

Issue scope item (2) — the one-time audit of `email_triage_items` /
`template_authorizations` / other WORM tables — is **already done**:
issuecomment-6193176714 on #10379 records zero live wedge and two dormant
anchors (`dsar_export_audit_pii.job_id → dsar_export_jobs` SET NULL;
`action_sends.grant_id → scope_grants` NO ACTION). This plan does not
re-plan that audit; it adds a verification step that the extended query's
out-of-cone census on dev returns exactly that dormant set.

## Problem Statement / Motivation

- **Concrete trigger (issue verbatim):** any future migration adding a
  non-`public.users` FK to a WORM-gated table re-creates an
  undeletable-user wedge with a green preflight. The gate's
  `confrelid = 'public.users'` clause is the whole envelope today.
- **Same class, second escape already documented in the gate itself:**
  header lines 62–65 admit that `auth.users`-referencing WORM FKs
  (`dsar_export_audit_pii.user_id`, mig 041:130) are outside the envelope —
  how #9994 shipped. The cone seed at `auth.users` closes that hole too.
- **Statutory surface:** every wedge of this class aborts
  `auth.admin.deleteUser` inside GoTrue's transaction where no
  `app.worm_bypass` GUC can be set — an Art-17 failure per affected user,
  indistinguishable from a green build today.

## Premise Validation (measured at plan time, 2026-10-15)

- **Delete-cone membership (static census of `supabase/migrations/*.sql`).**
  `public.users.id → auth.users ON DELETE CASCADE` (mig 001:7) makes
  `public.users` reachable from the `auth.users` root. CASCADE chains reach
  `conversations` and `messages` (e.g. mig 001:28,001:48, 046:93).
  **Nothing CASCADEs into `dsar_export_jobs` or `scope_grants`** —
  `grep` over all migrations finds the only inbound FKs as SET NULL
  (`dsar_export_audit_pii.job_id`, mig 041:129) and RESTRICT
  (`template_authorizations.grant_id`, mig 053:106). Both dormant-anchor
  parents are provably **out-of-cone** → warnings, not errors.
- **Sanctioned RESTRICT-to-users shapes exist and must stay green.**
  `action_sends.user_id` (051:102), `email_triage_items.user_id`
  (102:64), `template_authorizations.founder_id` (053:82) and
  `scope_grants.founder_id` (048:16) are all `ON DELETE RESTRICT →
  public.users`, pre-anonymised in `server/account-delete.ts` (3.82–3.84
  ordering at ~:409–509). This is the gate's *primary sanctioned pattern*
  (header lines 51–54) — the disposition matrix must NOT flag
  direct-users `RESTRICT`/`NO ACTION` FKs.
- **Post-162 residue is real and must stay warning-only.**
  `action_sends.message_id → messages ON DELETE SET NULL` (162:77–82) is an
  in-cone non-users SET NULL whose row-level carve-out
  (`action_sends_no_mutate`, 162:138–144) the `prosrc` heuristic cannot
  see — same permanent-warning class as `audit_byok_use.founder_id`.
- **WORM-table census.** `grep -rhoE 'public\.[a-z_]+_no_mutate'` → 18
  `*_no_mutate` functions (action_sends, audit_byok_use,
  audit_github_token_use, byok_delegation_acceptances, byok_delegations,
  byok_delegation_withdrawals, dsar_export_audit_pii, email_triage_items,
  outbound_sends, routine_runs, scope_grants, tc_acceptances,
  template_authorizations, tenant_deploy_audit, workspace_invitations,
  workspace_member_actions, workspace_member_attestations,
  workspace_member_removals). The gate detects WORM-ness dynamically via
  raising triggers, so no static list is added.
- **`account-delete.ts:411` comment is loose, not a defect.** It calls
  `action_sends.grant_id → scope_grants` "also RESTRICT"; the FK is bare
  `REFERENCES` (NO ACTION, mig 051:119 — never altered). Same dormant
  class; the audit comment is authoritative. Optional one-word comment fix
  is in-scope as a ride-along only if trivial.
- **CI wiring:** the gate runs live-schema in `tenant-integration.yml:668`
  and `scheduled-integration-suites.yml:181` (`id: worm`, substrate gate
  for all nightly suites). No workflow changes needed — the script's
  contract (exit codes, `::error::`/`::warning::`) is unchanged.
- **Fixture-test pattern exists:** `preflight-worm-cascade-contradiction
  .test.sh` fakes `psql` on PATH (`MOCK_ROWS` emitted for any query
  containing `pg_constraint`), `MIGRATIONS_DIR_OVERRIDE` decides
  ownership. The extended gate keeps ONE query so the same mock keys it.

## Proposed Solution

Extend `preflight-worm-cascade-contradiction.sh` — one recursive CTE plus a
widened census — and extend its `.test.sh` fixture. No new files, no
workflow edits, no allowlist.

### SQL shape (one query, mock-compatible)

```sql
WITH RECURSIVE del AS (
  -- Delete-cone roots: auth.admin.deleteUser deletes auth.users;
  -- public.users cascades (001:7). Both seeded for robustness.
  SELECT 'auth.users'::regclass AS parent
  UNION SELECT 'public.users'::regclass
  UNION
  -- CASCADE propagates row deletion parent → child.
  -- SET NULL/SET DEFAULT propagate an UPDATE only: the child's rows
  -- survive, so 'n'/'d' edges do NOT extend the cone.
  SELECT con.conrelid
  FROM pg_constraint con
  JOIN del ON con.confrelid = del.parent
  WHERE con.contype = 'f' AND con.confdeltype = 'c'
)
SELECT class, rel.relname, tg.tgname, fn.proname, con.conname,
       action_label, level, timing,
       parent_rel.relname AS parent_table
FROM pg_constraint con
JOIN pg_class rel        ON rel.oid = con.conrelid
JOIN pg_class parent_rel ON parent_rel.oid = con.confrelid
JOIN pg_trigger tg ON tg.tgrelid = con.conrelid AND NOT tg.tgisinternal
JOIN pg_proc fn    ON fn.oid = tg.tgfoid
LEFT JOIN del      ON con.confrelid = del.parent
WHERE con.contype = 'f'
  AND (fn.prosrc ILIKE '%RAISE EXCEPTION%' OR fn.prosrc ILIKE '%ASSERT %')
  AND ((tg.tgtype & 16) = 16 OR (tg.tgtype & 8) = 8)  -- UPDATE or DELETE trigger
  -- classification CASE emits one of:
  --   cone-refuse   : del.parent IS NOT NULL AND confdeltype IN ('r','a')
  --                   AND confrelid NOT IN (users roots)
  --   cone-write-stmt / cone-write-row : del IS NOT NULL AND
  --                   confdeltype IN ('n','c','d') AND trigger level
  --   dormant       : del.parent IS NULL
  --   user-anchor   : confrelid IN (auth.users, public.users) AND
  --                   confdeltype IN ('r','a')  → NOT emitted (sanctioned)
```

Key mechanics:

- **`confdeltype='d'` (SET DEFAULT) joins the write-firing group** — it
  performs `UPDATE child SET fk=DEFAULT`, which fires the UPDATE trigger.
  The current gate's comment (lines 108–109) lumps `'d'` with `'r'/'a'` as
  non-mutating; that is inaccurate (harmless today only because no WORM FK
  uses SET DEFAULT). Correct it in the rewrite.
- **`'r'/'a'` rows need no trigger-event match** — the abort is the FK
  itself (immediate RESTRICT / end-of-statement NO ACTION), not the
  trigger. Join the table's raising triggers for naming only.
- **Direct-user anchors** (`confrelid ∈ {public.users, auth.users}`):
  `'n'/'c'/'d'` keep today's exact semantics (the original WHERE clause is
  the `del`-rooted special case); `'r'/'a'` stay un-emitted — the
  RESTRICT+pre-anonymise pattern is sanctioned and covered by the
  behavioural backstop.
- Keep `severity` derived in SQL (`class` column above replaces the bare
  boolean) so the fixture mock stays honest per the test-header contract —
  mock `class` must be consistent with `level`/`parent_table` columns.

### Disposition matrix (bash side; `owned_by_ref` unchanged)

| FK on WORM table → parent P | action | P in cone? | Disposition |
|---|---|---|---|
| P ∈ {public.users, auth.users} | `n`/`c`/`d` | (root) | as today: STATEMENT→`::error::` if owned else leave-behind `::warning::`; ROW→`::warning::` |
| P ∈ {public.users, auth.users} | `r`/`a` | (root) | **silent** — sanctioned RESTRICT+pre-anonymise (unchanged) |
| P non-users | `n`/`c`/`d` | yes | same trigger-level axis: STATEMENT→error-if-owned; ROW→`::warning::` (carve-out residue; 162's message_id lands here) |
| P non-users | `r`/`a` | yes | **`::error::` if owned** — the #10254 wedge class; no carve-out mechanism exists for an FK refusal, so the heuristic can honestly fail closed. Leave-behind→`::warning::` |
| P any | any | no | `::warning::` dormant anchor — names parent + advises a tracking issue |

**Violation vs advisory, precisely:** a shape is a *violation* when the
erasure cascade provably reaches it AND it unconditionally aborts —
i.e. in-cone `r`/`a` (FK refusal, no carve-out possible) or in-cone
`n`/`c`/`d` under a STATEMENT trigger (fires on 0 rows, no carve-out
possible). It is *advisory* when either the cascade never reaches it
(out-of-cone = dormant anchor) or a sanctioned row-level carve-out may
legitimately admit the transition the heuristic cannot see (in-cone `n`
/`c`/`d` ROW-level). Everything else (leave-behinds) is advisory by the
per-ref ownership gate, unchanged.

**Expected new main-state warnings** (all advisory, build stays green):
`action_sends.grant_id→scope_grants` (dormant, NO ACTION);
`dsar_export_audit_pii.job_id→dsar_export_jobs` (dormant, SET NULL);
`dsar_export_audit_pii.user_id→auth.users` (carve-out residue, NEW — the
#9994 hole this closes); `action_sends.message_id→messages` (in-cone
ROW-level carve-out residue, post-162); `template_authorizations.grant_id→
scope_grants` + `email_triage_items` non-user FKs (RESTRICT, out-of-cone,
dormant — "wedge class in wait": aborts only an out-of-band parent
delete, never erasure, since the anchor is not in the user chain).

### Design tension resolution (recommended; ruled row in decision-challenges)

Issue's options: (a) reviewed allowlist + tracking issues, (b) fix the two
dormant anchors in-flight, (c) warn-only vs fail-closed split by shape.

**Recommend (c) — the cone-membership split — and NO allowlist file.**
The cone computation makes the dormant anchors self-classifying: their
parents are out-of-cone today, so they emit `::warning::` advisory rows and
main stays green without any suppression machinery. An allowlist (option a)
would be needed only if we flagged *all* non-users FKs as errors —
rejected: it couples the gate to a mutable CODEOWNERS-pinned list for rows
that are not violations. Fixing the anchors in-flight (option b) is scope
creep against a fix already ruled out of #10254's arc. The split also has
the right dynamics: if a future migration ever makes `dsar_export_jobs` or
`scope_grants` cascade-deletable, the dormant row *upgrades itself to red*
on the owning ref — an allowlist would have suppressed exactly that signal.
The dormant anchors get tracking issues (filed in tasks), not suppression.

## Files Changed

- `apps/web-platform/scripts/preflight-worm-cascade-contradiction.sh` —
  recursive `del` CTE + widened census + `class`-aware disposition;
  header comment updated (envelope description, the now-closed item-(b)
  limitation at lines 62–65, the `'d'` correction).
- `apps/web-platform/scripts/preflight-worm-cascade-contradiction.test.sh`
  — `MOCK_ROWS` schema gains `class|parent_table`; new mutation rows
  (§Test Scenarios); existing 6 tests updated to the new row schema.
- `apps/web-platform/server/account-delete.ts` — one-word comment fix at
  :411 (`RESTRICT` → `NO ACTION`) — ride-along, drop if contested.
- CODEOWNERS: `preflight-worm-cascade-contradiction.sh` is NOT currently
  pinned; add a pin row for the script + its test only if the reviewer
  asks (the service-role-allowlist precedent, `.github/CODEOWNERS:81–85`,
  pins gate files that can be self-defeated — this gate's rows come from
  the live schema, not a repo-side list, so self-defeat surface is the
  script itself; flag as `operator (scope)` row).

## Test Scenarios (fixture `.test.sh` — offline, fake `psql` + `MOCK_ROWS`)

Row schema becomes `class|tbl|trg|fn|fk|action|level|timing|parent`.
The fake psql still keys on `pg_constraint` (single query preserved).

| # | Mutation | Mock row | Owned? | Expected |
|---|---|---|---|---|
| 1 | Synthetic WORM table + non-users in-cone NO ACTION FK (the #10254 mutant) | `cone-refuse\|worm_ledger\|…\|worm_ledger_message_id_fkey\|NO ACTION\|STATEMENT\|BEFORE\|public.messages` | yes | **exit 1, `::error::` naming table + `public.messages`** |
| 2 | Same row, unowned dir | same | no | exit 0, `::warning::` leave-behind, no `::error::` |
| 3 | In-cone SET NULL, ROW-level (post-162 carve-out residue) | `cone-write-row\|action_sends\|…\|message_id_fkey\|SET NULL\|ROW\|BEFORE\|public.messages` | yes | exit 0, `::warning::`, no `::error::` |
| 4 | In-cone SET NULL, STATEMENT-level | `cone-write-stmt\|worm_tab\|…\|SET NULL\|STATEMENT\|…\|public.messages` | yes | exit 1, `::error::` |
| 5 | Dormant anchors (audit parity): SET NULL + NO ACTION to out-of-cone parents | `dormant\|dsar_export_audit_pii\|…\|job_id_fkey\|SET NULL\|ROW\|…\|public.dsar_export_jobs`, `dormant\|action_sends\|…\|grant_id_fkey\|NO ACTION\|STATEMENT\|…\|public.scope_grants` | yes | exit 0, `::warning::` naming both parents, no `::error::` |
| 6 | RESTRICT to out-of-cone parent stays green per the audit | `dormant\|email_triage_items\|…\|RESTRICT\|ROW\|…\|public.inbox_items` | yes | exit 0, `::warning::` |
| 7 | **Ruling-pinned:** RESTRICT/NO ACTION to in-cone NON-users parent → **red** (recommended; the wedge class) | `cone-refuse\|worm_tab\|…\|RESTRICT\|ROW\|…\|public.conversations` | yes | exit 1 |
| 8 | RESTRICT to a direct-users parent stays silent (sanctioned) | `user-anchor\|…\|RESTRICT\|…\|public.users` | yes | exit 0, no mention of the row at all |
| 9 | Existing tests 1–6 re-pinned on new schema (owned/unowned stmt, row, clean, mixed, missing DATABASE_URL) | existing rows + new cols | — | unchanged verdicts |

Plus one live verification step (not fixture): after dev apply, run the
extended query read-only against dev and assert the dormant census equals
exactly the audited set (hr-no-dashboard-eyeball — pull the rows, cite
them in the PR).

## Out of Scope

- Fixing the two dormant anchors (tracking issues to be filed).
- Scanning **non-WORM** tables for `r`/`a` FKs into the cone — the same
  abort class exists there mechanically (FK refusal needs no trigger) but
  exceeds the issue's WORM-table scope; ruling row + follow-up issue.
- Verifying `account-delete.ts` actually pre-anonymises every
  direct-users RESTRICT anchor — behavioural backstop
  (`account-delete.cascade.integration.test.ts`) owns that.
- Any workflow changes (wiring already correct at both call sites).

## Risks & Mitigations

- **Recursive CTE on `pg_constraint`** — cycles are possible in principle
  (FK cycles with CASCADE, e.g. A↔B); `UNION` (not `UNION ALL`) dedups and
  terminates the recursion. State this in the comment.
- **Mock-vs-real divergence** — the `class` column is derived in SQL but
  mocked in tests; keep the test-header contract ("mock `class`
  consistent with `level`/`parent_table`") and add a fixture row per
  class so a drifted mock fails loudly.
- **Permanent-warning accumulation** — new residue rows (audit_pii
  user_id, post-162 message_id) are expected; each `::warning::` line must
  name class + parent so residue is distinguishable from a NEW dormant
  anchor. The warning banner tells the reader to file a tracking issue
  for any `dormant` row they did not add.
- **`auth.users` in conrelid space** — `pg_constraint` covers it (FKs
  reference `auth.users` today: mig 041:130, 046:93). Seeding both roots
  also covers a hypothetical future `public.users` edge reshape.

## Session Summary

Plan written 2026-10-15 by the one-shot planning subagent. Extends the
WORM-cascade preflight gate with a recursive user-erasure delete-cone and a
four-class disposition (cone-refuse / cone-write / dormant / user-anchor),
catching the #10254 table-to-table wedge class fail-closed while the two
audited dormant anchors self-classify as advisory warnings — no allowlist,
no workflow changes. Open rulings: in-cone `r`/`a` severity (recommended
error-if-owned), all-tables cone scan (recommended follow-up), CODEOWNERS
pin (operator scope). Tasks + decision-challenges + session-state in
`knowledge-base/project/specs/feat-one-shot-10379-preflight-transitive-fk/`.
