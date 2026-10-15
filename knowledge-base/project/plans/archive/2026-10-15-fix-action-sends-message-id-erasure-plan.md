---
title: "fix: action_sends.message_id nullable + ON DELETE SET NULL + row-level WORM carve-out (migration 162)"
type: fix
date: 2026-10-15
slug: fix-action-sends-message-id-erasure
branch: feat-one-shot-10254-action-sends-message-id
issue: 10254
closes: 10254
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: action_sends.message_id nullable + ON DELETE SET NULL + row-level WORM carve-out (migration 162)

## Overview

Migration 162 unblocks GDPR Art-17 erasure for every user who has an
`action_sends` row. Today `action_sends.message_id` is
`NOT NULL REFERENCES public.messages(id)` (NO ACTION, mig 051:103), so when
`auth.admin.deleteUser` cascades through `messages` it hits
`action_sends_message_id_fkey` and aborts — verified live on dev as
`ERROR: violates foreign key constraint "action_sends_message_id_fkey"`.
`server/account-delete.ts` has no unanchoring path, so any real user who ever
sent an action is undeletable.

The design is already ruled (CTO-agent ruling comment on the issue,
2026-10-15): **option (b)** — `message_id` nullable + `ON DELETE SET NULL` + a
row-level WORM carve-out, mirroring the migration-161 precedent family
(066 → 160 → 161). This plan implements the ruling; it does not re-litigate
the design.

## Problem Statement / Motivation

- **Statutory blocker, not test noise.** The wedge fires inside GoTrue's
  `deleteUser` transaction where no `app.worm_bypass` GUC can be set, so the
  anonymise RPC's privilege path cannot reach it. Every user with an
  `action_sends` row fails erasure — an Art-17 violation per user, not an
  aggregate-only concern.
- **Surfaced by PR #10238's loud teardown** on dev (tenant-integration run
  38469450080): `tearDownTenantUser: deleteUser(<synthetic>) failed: Database
  error deleting user` in `action-sends-worm.test.ts` and
  `template-authorizations-worm.test.ts`. Both suites currently carry a
  documented `tolerate:` escape hatch via `hasUndeletableActionSendsAnchor`
  (`test/helpers/tenant-isolation-teardown.ts:322`) — dead code after this
  lands.

## Proposed Solution (ruled — option (b))

One migration pair implementing the four ruled pieces, exactly mirroring the
161 shape (`161_audit_github_token_use_cascade_null_carveout.sql`):

1. **FK reshape.** `ALTER TABLE public.action_sends ALTER COLUMN message_id
   DROP NOT NULL`; drop `action_sends_message_id_fkey`; re-add it as
   `FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE SET
   NULL`. `message_id` is pure linkage — the row snapshots everything it
   reads (`per_send_body_sha256`, `template_hash`, `action_class`,
   `tier_at_send`, `grant_id`), so NULL is a complete de-link, not data loss.
2. **Trigger reshape.** `action_sends_no_update` keeps the 064
   statement-level `BEFORE UPDATE OF` form minus `message_id` (11 columns:
   `id, user_id, action_class, tier_at_send, template_hash,
   per_send_body_sha256, recipient_id_hash, clicked_at, confirmed_typed,
   approval_signature_sha256, grant_id`). A NEW row-level trigger
   `BEFORE UPDATE OF message_id ... FOR EACH ROW` fires through
   `action_sends_no_mutate`. `action_sends_no_delete` is untouched — DELETE
   stays universally blocked.
3. **Carve-out in `action_sends_no_mutate`** (161 shape): admit exactly
   `OLD.message_id IS NOT NULL AND NEW.message_id IS NULL AND
   (to_jsonb(NEW) - 'message_id') = (to_jsonb(OLD) - 'message_id') AND
   NOT EXISTS (SELECT 1 FROM public.messages WHERE id = OLD.message_id)` —
   the RI action fires after the parent `messages` row is removed, so the
   cascade passes while a direct `UPDATE ... SET message_id = NULL` against
   a row whose message still exists is rejected (a privileged role holding
   UPDATE cannot forge an erasure on a live anchor). The `to_jsonb`-minus
   compare is drift-proof: a future `ADD COLUMN` cannot silently widen the
   gate.
4. **Hardening (one line).** `anonymise_action_sends` also sets
   `message_id = NULL` inside its existing `app.worm_bypass` window —
   eager de-link as recommended hardening, not the mechanism.

Plus the ruled deliverables: `.down.sql`, `supabase/verify/162_*.sql`
sentinel, a migration-shape test mirroring the 161 test, and removal of the
`#10254` tolerances so loud teardown resumes catching all residue.

## Technical Considerations

- **`TG_LEVEL` gate is load-bearing.** `action_sends_no_mutate` serves BOTH
  the statement-level triggers (`action_sends_no_update`,
  `action_sends_no_delete`) and the new row-level trigger. For a
  statement-level firing, `OLD`/`NEW` are unassigned records — touching
  `OLD.message_id` raises `record "old" is not assigned yet`, not the clean
  P0001. The carve-out branch MUST be guarded by `TG_OP = 'UPDATE' AND
  TG_LEVEL = 'ROW'` so the statement path still pure-rejects with P0001.
- **Trigger ordering needs no care but is documented:** statement-level
  BEFORE triggers run before row-level ones, so an UPDATE touching
  `message_id` AND a protected column raises P0001 at the statement trigger
  before the row guard ever runs — and even if ordering changed, the
  `to_jsonb` compare would still reject any other-column drift.
- **`anonymise_action_sends` under the GUC bypass fires both triggers** and
  is admitted at the `app.worm_bypass` fast-path before either rejects —
  the hardening line is safe.
- **Unique index NULL semantics:** `action_sends_message_unique
  (message_id)` (051:183) treats NULLs as distinct — multiple post-erasure
  NULL rows coexist fine.
- **FK re-creation lock:** `ADD CONSTRAINT ... FOREIGN KEY` validates
  existing rows under a brief lock; `action_sends` is a low-row table so
  the plain form is acceptable. `NOT VALID` + `VALIDATE CONSTRAINT` is a
  permitted variant if review prefers a shorter lock window.
- **Security definer already in place** (051 + 087): the initiator check's
  `public.messages` read runs identically under every firing context —
  the same property 161 bought by flipping DEFINER on, already true here.
- **Cross-tenant/message-delete coverage:** any `messages` row deletion —
  user cascade OR conversation cascade OR direct — fires the SET NULL and
  is admitted because the parent is already gone. That is the ruled
  semantic: when the message is gone, the linkage releases.
- **NFR impacts:** none new — one added per-row trigger fires only on
  `UPDATE OF message_id`, which today occurs only via the RI cascade and
  the anonymise RPC.
- **Verification constraint (environment):** `registry.npmjs.org` is
  unreachable from this host — `node_modules` may be absent, so vitest/bun
  steps and `TENANT_INTEGRATION_TEST=1` dev-DB runs are CI/deployed-surface
  verification, not local-run assumptions. The offline
  `test/supabase-migrations/162-*.test.ts` shape test needs no DB but does
  need vitest installed.

## Research Insights

**Premise Validation (measured at plan time, 2026-10-15):** all cited
premises verified in this worktree —

- Issue #10254 is OPEN (`type/bug`, `priority/p1-high`, `domain/engineering`);
  the CTO ruling comment (author `deruelle`, soleur:engineering:cto,
  report-only review of `main@084a5b0d`) is present and prescribes option (b)
  verbatim as implemented here.
- `action_sends.message_id uuid NOT NULL REFERENCES public.messages(id)`
  confirmed at `migrations/051_action_class_widening_and_action_sends.sql:103`;
  `user_id ... ON DELETE RESTRICT` at :102; `grant_id ... ON DELETE` (NO
  ACTION) at :119.
- Trigger `action_sends_no_update` = `BEFORE UPDATE OF` 12 columns `FOR EACH
  STATEMENT` at `064_action_sends_acknowledgment.sql:61-78`; DELETE trigger
  untouched since 051:150-154.
- Function `action_sends_no_mutate` = 087 GUC-bypass + pure-reject body at
  `087_worm_bypass_privilege_independence.sql:92-106`, `SECURITY DEFINER`,
  `search_path = public, pg_temp`.
- `anonymise_action_sends` body at `087_*.sql:406-441` — sets
  `user_id=NULL, recipient_id_hash='__anonymised__'` under `SET LOCAL
  app.worm_bypass` (the hardening adds one column to that SET list).
- Precedent `161_audit_github_token_use_cascade_null_carveout.sql` (and
  `.down.sql`, and
  `test/supabase-migrations/161-audit-github-token-use-cascade-null-carveout.test.ts`)
  verified as the mirror template; `verify/160_dsar_export_audit_pii_*` is
  the verify-file convention (`(check_name, bad)` row contract consumed by
  `run-verify.sh`).
- Next free migration number confirmed: `ls migrations | grep -oE '^[0-9]+'
  | sort -n | tail` → 161; **162 is free**. `verify/` has no 161 file —
  162's verify file follows the 160 convention regardless (the ruling
  prescribes it; the #9994 learning names verify files "the only permanent
  gate that a live `prosrc` matches the file's").
- `anonymise_scope_grants` nulls `founder_id` + `workspace_id`
  (`064_anonymise_scope_grants_*.sql:86-108`) — the `grant_id`
  re-identification chain the ruling relies on is severed as stated.
- Blast radius re-verified against consumers: write path
  `server/action-sends/write-action-send.ts:157` INSERTs non-NULL; Inngest
  ack route `server/inngest/functions/agent-on-spawn-requested.ts:1684-1722`
  filters `.eq("message_id", ...)` so NULL rows never match; DSAR export
  `server/dsar-export.ts:890` keys on `user_id`; realtime subscriber
  `components/dashboard/leader-loop-status.tsx` filters
  `message_id=eq.<id>`; `account-delete.ts:743`'s `.in("message_id")` is on
  `message_attachments`, a different table. No inner join on
  `action_sends.message_id` exists.
- `messages.user_id → users ON DELETE CASCADE` confirmed via mig 001 +
  046; `public.users.id → auth.users(id) ON DELETE CASCADE` at
  `001_initial_schema.sql:7`.

**Property List (Phase 0.6b):**

1. `auth.admin.deleteUser` succeeds for a user with `action_sends` rows on
   EVERY deletion path (saga, teardown, cross-tenant, direct) — not only
   when the anonymise RPC ran first.
2. The WORM guarantee is preserved for every non-cascade mutation: no
   caller can set `message_id = NULL` while its `messages` row lives, and
   no other column can ride the carve-out.
3. The post-erasure `action_sends` row is Recital-26 anonymous (all three
   identifier-bearing columns — `user_id`, `recipient_id_hash`,
   `message_id` — cleared; `grant_id`'s chain severed by
   `anonymise_scope_grants`).
4. Loud teardown resumes: the `#10254` tolerances are removed so any other
   undeletable-residue class fails red instead of being masked.
5. Deploy-time drift is detectable: a verify sentinel proves the live
   function body/FK/trigger match the committed files.

**Cut List (Phase 0.6b):**

- Tombstone-`messages` (option (a)) — cut by the ruling: strictly more
  surgery on the hotter table and weaker erasure (the message must survive
  two cascades).
- RESTRICT + eager `message_id=NULL` inside the RPC (narrower (b)) — cut by
  the ruling: erasure stays wedged on any path missing the RPC; fail-closed
  is wrong on an Art-17 surface.
- `account-delete.ts` saga change — cut by the ruling: the carve-out admits
  the cascade's own transition inside GoTrue's transaction; no code path
  there can reach it.
- `action_sends.grant_id` same-class anchor — descoped (dormant:
  `scope_grants` rows survive user deletion; tracked under #10379's audit
  item).
- `preflight-worm-cascade-contradiction.sh` envelope extension — descoped:
  filed separately as #10379 per the ruling comment.

**Relevant learnings:**

- `learnings/test-failures/2026-10-12-a-set-null-fk-into-a-worm-table-fires-the-worm-gate-on-the-cascade.md`
  — the exact defect class; initiator check + drift-proof `to_jsonb`
  compare + verify-file contract all originate here.
- `preflight-worm-cascade-contradiction.sh` scans only
  `confrelid = 'public.users'` (its own header admits this) — a
  table-to-table chain like `action_sends → messages` escapes it; the fix
  therefore needs no gate change but gets no gate protection either (#10379).
- Legal surfaces that will go stale: `docs/legal/data-protection-disclosure.md`
  §2.3(r) calls the trigger "pure-reject" and enumerates `message_id`;
  `knowledge-base/legal/article-30-register.md` rows 344/421 describe the
  TOM (already stale re `session_replication_role` — 087 replaced it with
  the GUC). The consistency test enforces mirror parity, not these strings;
  the edits are small and in-scope for compliance accuracy.

**Community discovery / functional overlap (Phases 1.5/1.5b, inline — no
subagent spawn available in this context):** the mechanism is a fourth
instance of an in-repo precedent family (066/160/161); no external package,
agent, or skill covers this better, and no existing component is
duplicated — the plan extends `action_sends_no_mutate`, not a sibling.

**External research decision (Phase 1.6):** skipped — the design is ruled,
the precedent is in-repo and thrice-applied, and every premise is
repo-verified. Security/compliance caution is satisfied by the ruling's own
threat analysis and this plan's GDPR section.

## Files to Create

| File | Purpose |
|------|---------|
| `apps/web-platform/supabase/migrations/162_action_sends_message_id_cascade_null_carveout.sql` | FK reshape + trigger split + carve-out + RPC hardening + COMMENTs |
| `apps/web-platform/supabase/migrations/162_action_sends_message_id_cascade_null_carveout.down.sql` | Restore 087 function body, 064 12-column trigger, NOT NULL + NO ACTION FK, drop row-level trigger, restore pre-hardening RPC |
| `apps/web-platform/supabase/verify/162_action_sends_message_id_cascade_null_carveout.sql` | Post-apply `(check_name, bad)` sentinel — see Guard Contract |
| `apps/web-platform/test/supabase-migrations/162-action-sends-message-id-cascade-null-carveout.test.ts` | Offline migration-shape test mirroring the 161 test |

## Files to Edit

| File | Change |
|------|--------|
| `apps/web-platform/test/helpers/tenant-isolation-teardown.ts` | Delete `hasUndeletableActionSendsAnchor` + its `#10254` doc block (~lines 309-339); keep the generic `tolerate:` option (other callers + its unit test exist) |
| `apps/web-platform/test/server/action-sends-worm.test.ts` | Remove `tolerate:` block (~lines 197-205); add carve-out coverage — see Test Scenarios |
| `apps/web-platform/test/server/template-authorizations-worm.test.ts` | Remove `tolerate:` block (~lines 185-188) |
| `apps/web-platform/test/server/account-delete.cascade.integration.test.ts` | **Required** (CTO-ruled 2026-10-15, elevated from recommended): extend the seeded-`audit_byok_use` fixture with one `action_sends` row so the canonical end-to-end deletability pin covers this wedge class |
| `docs/legal/data-protection-disclosure.md` | §2.3(r): trigger description no longer "pure-reject on UPDATE" — note the Art-17 cascade carve-out; retention sentence gains `message_id = NULL` |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Mirror of the above (legal-doc-consistency parity) |
| `knowledge-base/legal/article-30-register.md` | action_sends TOM/retention rows (~lines 344, 421): record the carve-out form; fix the stale `session_replication_role` mention to `app.worm_bypass` while touched |

## Implementation Phases

### Phase 1 — Migration 162 (forward + down + verify)

```sql
-- precondition per lint-migration-fk-preconditions.sh (cross-file REFERENCES)
DO $$
BEGIN
  IF to_regclass('public.action_sends') IS NULL
     OR to_regclass('public.messages') IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Migration 162 precondition failed: public.action_sends/public.messages missing',
      DETAIL  = 'Schema-vs-ledger drift class (issue 4338).',
      HINT    = 'Recovery: knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md';
  END IF;
END $$;

ALTER TABLE public.action_sends ALTER COLUMN message_id DROP NOT NULL;
ALTER TABLE public.action_sends DROP CONSTRAINT action_sends_message_id_fkey;
-- NOT VALID skips the existing-row scan's long lock; enforcement applies to
-- new writes immediately; VALIDATE CONSTRAINT then runs under SHARE UPDATE
-- EXCLUSIVE (reads/writes unblocked) — see ## Downtime & Cutover.
ALTER TABLE public.action_sends
  ADD CONSTRAINT action_sends_message_id_fkey
  FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE SET NULL
  NOT VALID;
ALTER TABLE public.action_sends
  VALIDATE CONSTRAINT action_sends_message_id_fkey;

DROP TRIGGER IF EXISTS action_sends_no_update ON public.action_sends;
CREATE TRIGGER action_sends_no_update
  BEFORE UPDATE OF id, user_id, action_class, tier_at_send, template_hash,
                   per_send_body_sha256, recipient_id_hash, clicked_at,
                   confirmed_typed, approval_signature_sha256, grant_id
  ON public.action_sends FOR EACH STATEMENT
  EXECUTE FUNCTION public.action_sends_no_mutate();

DROP TRIGGER IF EXISTS action_sends_message_id_guard ON public.action_sends;
CREATE TRIGGER action_sends_message_id_guard
  BEFORE UPDATE OF message_id ON public.action_sends
  FOR EACH ROW EXECUTE FUNCTION public.action_sends_no_mutate();

CREATE OR REPLACE FUNCTION public.action_sends_no_mutate()
  RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'action_sends is append-only (WORM); DELETE rejected'
      USING ERRCODE = 'P0001';
  END IF;
  IF TG_OP = 'UPDATE' AND TG_LEVEL = 'ROW' THEN
    IF OLD.message_id IS NOT NULL
       AND NEW.message_id IS NULL
       AND (to_jsonb(NEW) - 'message_id') = (to_jsonb(OLD) - 'message_id')
       AND NOT EXISTS (SELECT 1 FROM public.messages WHERE id = OLD.message_id)
    THEN
      RETURN NEW;  -- Art-17 SET NULL cascade carve-out (mirrors mig 161).
    END IF;
  END IF;
  RAISE EXCEPTION 'action_sends is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$fn$;

REVOKE ALL ON FUNCTION public.action_sends_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.action_sends_no_mutate() IS
  'WORM gate for action_sends. Allows UPDATE only via the app.worm_bypass '
  'bypass (anonymise_action_sends) or the Art-17 SET NULL cascade transition '
  '(message_id NOT NULL -> NULL, all other columns structurally unchanged, '
  'parent messages row already gone — NOT EXISTS initiator check, mig 161 '
  'shape). DELETE is universally blocked.';

COMMENT ON COLUMN public.action_sends.message_id IS
  'NULL after erasure or any parent-messages deletion: ON DELETE SET NULL '
  'de-links the WORM ledger row (mig 162). NULL = de-linked state, not a '
  'data gap; consumers must tolerate it (all .eq filters simply never match).';

-- anonymise_action_sends: add `message_id = NULL` to the existing UPDATE's
-- SET list (single-column addition inside the established GUC window).
```

The `.down.sql` restores: the 087 `action_sends_no_mutate` body verbatim;
the 064 12-column statement trigger; drops `action_sends_message_id_guard`;
restores `message_id NOT NULL` + the NO ACTION FK; and restores the
pre-162 `anonymise_action_sends` body — with the 161-style WARNING that
reverting reinstates the Art-17 wedge. Ordering note: `SET NOT NULL` fails
if any NULL rows exist; the down file documents that prerequisite.

### Phase 2 — Offline migration-shape test

`test/supabase-migrations/162-action-sends-message-id-cascade-null-carveout.test.ts`
mirroring the 161 test's structure: SECURITY DEFINER + search_path pin;
bypass precedes raises; DELETE raises unconditionally; the four carve-out
conjuncts; `TG_LEVEL = 'ROW'` guard; statement trigger list excludes
`message_id` (and retains the other 11); row-level `BEFORE UPDATE OF
message_id ... FOR EACH ROW` trigger exists; `anonymise_action_sends`
contains `message_id = NULL`; COMMENTs present; down restores the 087 body
and the 12-column trigger.

### Phase 3 — Test-suite edits (tolerance removal + new coverage)

Remove both `tolerate:` blocks and `hasUndeletableActionSendsAnchor`; add
the integration coverage in Test Scenarios. Extend
`account-delete.cascade.integration.test.ts` with one seeded `action_sends`
row (required per CTO ruling — teardown-only coverage is `afterAll` noise).

### Phase 4 — Legal-doc parity

Update the three disclosure/register surfaces listed in Files to Edit.

### Phase 5 — Verification

Local (no deps): `bash apps/web-platform/scripts/lint-migration-fk-preconditions.sh
apps/web-platform/supabase/migrations/162_action_sends_message_id_cascade_null_carveout.sql`.
With deps: `cd apps/web-platform && ./node_modules/.bin/vitest run
test/supabase-migrations/162-*.test.ts` (per constitution: vitest via
`./node_modules/.bin/` in worktrees). Deployed surface: dev apply +
`run-verify.sh` + `TENANT_INTEGRATION_TEST=1` worm suites + cascade
integration test.

## Open Code-Review Overlap

- `#4254` (template_id NOT NULL fixture drift): names
  `action-sends-worm.test.ts:93`, but `seedDraftMessage` already carries
  `template_id: "default_legacy"` (line 121) — **acknowledge**: the drift
  naming this file is already fixed; the scope-out's remaining files are
  outside this diff.
- `#3220` (postmerge trigger verification in prd): our migration adds a
  trigger, but the scope-out targets `web-platform-release.yml` —
  **defer**: `verify/162_*.sql` partially covers its intent for this
  migration; the generic mechanism stays with the issue.
- No other open `code-review` issues touch the planned files.

## User-Brand Impact

- **If this lands broken, the user experiences:** an opaque
  `500 Database error deleting user` (or silent undeletable account) when
  they exercise Art-17 erasure — today for EVERY user who ever sent an
  action.
- **If this leaks, the user's data is exposed via:** a mis-shaped carve-out
  would let a privileged role de-link `message_id` on a LIVE message —
  audit-trail tamper, not data leak; the initiator check + `to_jsonb`
  compare exist precisely to bound that. Residual PII after erasure is the
  other direction: covered by the anonymise RPC + this hardening.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user's failed statutory
  erasure is itself a reportable GDPR miss — the blast radius (every user
  with `action_sends`) makes `aggregate pattern` arguable, but the defect
  manifests per-user-per-request, so `single-user incident` is the floor,
  not the ceiling.
- Per plan §2.6 step 3, `requires_cpo_signoff: true` is set; CPO sign-off
  is required at plan time before `soleur:work` begins (headless context:
  recorded in `decision-challenges.md`).

## Observability

```yaml
liveness_signal:
  what: verify-file post-apply sentinel (supabase/verify/162_*.sql emits (check_name,bad) rows; run-verify.sh fails the deploy on any bad=1) + loud tenant-integration teardown resuming as the residual-residue tripwire
  cadence: per-deploy (verify) + per TENANT_INTEGRATION_TEST=1 run (teardown)
  alert_target: CI/release-pipeline failure
  configured_in: apps/web-platform/supabase/verify/162_action_sends_message_id_cascade_null_carveout.sql; apps/web-platform/scripts/run-verify.sh
error_reporting:
  destination: Sentry web-platform via SENTRY_DSN (account-delete.ts reportSilentFallback wraps saga steps; GoTrue 500s surface to the caller)
  fail_loud: 'auth.admin.deleteUser returns "Database error deleting user"; tearDownTenantUsers aggregates and throws'
failure_modes:
  - mode: carve-out regression re-wedges erasure (FK blocks deleteUser again)
    detection: TENANT_INTEGRATION_TEST worm suites red + account-delete.cascade.integration.test.ts red
    alert_route: CI failure on the PR / scheduled dev run
  - mode: migration apply drift (file landed, live prosrc/FK/trigger differs)
    detection: verify/162 rows return bad=1; run-verify.sh fails
    alert_route: deploy pipeline failure
  - mode: forged NULL transition on a live message (privilege escalation attempt)
    detection: NOT EXISTS initiator check rejects; pinned by the new negative integration test
    alert_route: test red
logs:
  where: Supabase Postgres logs (P0001 raises surface as statement errors); GitHub Actions run logs for tenant-integration
  retention: Supabase platform retention / Actions run retention
discoverability_test:
  command: grep -l "ON DELETE SET NULL" apps/web-platform/supabase/migrations/162_action_sends_message_id_cascade_null_carveout.sql
  expected_output: 162_action_sends_message_id_cascade_null_carveout.sql
```

## Encryption Posture

Detection fired on `supabase/migrations/.*\.sql$`. The change introduces no
new persistent store and no new cross-component connection — it alters an FK
on an existing table inside the existing `supabase.prd` store:

```yaml
at_rest:
  - store: supabase.prd (existing — posture unchanged by this migration)
    mechanism: provider-managed:supabase-postgres-aes256
    evidence: 'scripts/encryption-posture-ledger.json store "supabase.prd" row (attestation https://supabase.com/docs/guides/security, retrieved_on 2026-07-24)'
    defends_against: physical-media compromise of the managed Postgres storage
    does_not_defend: a leaked service-role key, an RLS bypass, or any query via a legitimate connection
    disclosed_as: not-publicly-claimed
    live_verification: 'unavailable:named SOC 2 attestation formalization pending; tracked #6911'
in_transit: none — schema-internal FK change on the existing supabase.prd store; no new cross-component connection
```

No `exception` block — mechanism is provider-managed and
`cert_verification` is not off.

## Guard Contract

### Guard 1 — `verify/162` post-apply drift sentinel

**Property.** The LIVE dev/prd schema carries migration 162's real objects:
`confdeltype='n'` on `action_sends_message_id_fkey`, `message_id` nullable,
the row-level guard trigger present, the carve-out + initiator check inside
`action_sends_no_mutate` `prosrc`, and `message_id = NULL` inside
`anonymise_action_sends` `prosrc`.

**Assembly.** Every check reads pg_catalog/information_schema through the
single chokepoint `apps/web-platform/scripts/run-verify.sh`, which executes
every `supabase/verify/*.sql` post-apply and fails on any `bad=1` row.
Members: `pg_constraint.confdeltype`, `information_schema.columns.is_nullable`,
`pg_trigger` (row-level + UPDATE-event bit), `pg_proc.prosrc` ×2.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Apply lands but `action_sends_no_mutate` retains the 087 body (no `NOT EXISTS`/`to_jsonb`) | RED — `no_mutate_has_*` checks return bad=1 |
| 2 | FK re-added as NO ACTION (`confdeltype='a'`) instead of SET NULL | RED — `fk_is_set_null` returns bad=1 |
| 3 | Row-level `action_sends_message_id_guard` trigger missing | RED — trigger check returns bad=1 |
| 4 | Guard's own dispatch: target object absent (`pg_proc`/`pg_trigger` lookup matches zero rows) | RED — every check is written `CASE WHEN EXISTS(...) AND <cond> THEN 0 ELSE 1 END` so a missing object emits bad=1, never a missing row (vacuity control) |
| 5 | Second protected surface added later (e.g. a future `162`-family check drops out of the UNION) | RED — the per-check-EXISTS form keeps each row independent; deleting any check still leaves the others probing live state |
| 6 | Harness row: `run-verify.sh` treats a zero-row file as pass | must-PASS control — a conforming 162 apply emits all-0 `bad` values, which is distinguishable from zero rows only because each check always emits exactly one row |

### Guard 2 — migration-162 shape test (assertion-based CI check)

**Property.** The committed SQL carries the ruled contract: four carve-out
conjuncts + `TG_LEVEL='ROW'` gate + SET NULL FK + split triggers + hardened
RPC + faithful down-file.

**Assembly.** The three 162 files' SQL text, parsed by regexes in
`test/supabase-migrations/162-*.test.ts`; chokepoint is the vitest run in
CI. Members are the regexes themselves — each pins one conjunct so a single
conjunct's loss reddens exactly one assertion.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop `AND NOT EXISTS (SELECT 1 FROM public.messages …)` from the function | RED |
| 2 | Re-add `message_id` to the statement-level `BEFORE UPDATE OF` column list | RED — the test enumerates the expected 11-column set |
| 3 | `.down.sql` keeps the carve-out (fails to restore the 087 pure-reject body) | RED |
| 4 | Guard's own dispatch: delete the `FN_RE` extraction so no function block is found | RED — the block-presence assertion fails first |
| 5 | Add a second admitted transition (e.g. also admit `recipient_id_hash`→NULL without bypass) | RED — `to_jsonb`-minus-`message_id` compare pin rejects extra columns by shape |
| 6 | Harness rows: (a) comment-strip the fixture loader so `--` content enters `executable` | RED — pinned by `expect(executable).not.toMatch(...)` cases; (b) must-PASS control: reorder the function's whitespace/comment layout while keeping semantics | PASS — regexes are whitespace-tolerant by construction |

## Architecture Decision (ADR/C4)

**ADR: none required.** The design was already decided by the CTO-agent
ruling on the issue (option (b)), and it instantiates an established,
thrice-shipped precedent family (mig 066 → 160 → 161) rather than a new
architectural decision: no ownership/tenancy boundary moves, no new
substrate, no trust-boundary change — `action_sends_no_mutate` was already
SECURITY DEFINER, and the carve-out's blast radius is one table's UPDATE
path. The one delta from precedent — the initiator check reading
`public.messages` (a table-to-table chain) rather than a users table — is a
degree extension, not a kind extension, and is documented in the migration
header, `COMMENT ON`, the verify sentinel, and this plan.

**C4 views: no impact.** Read `model.c4`/`views.c4`/`spec.c4` (all three):
the model carries no `action_sends`/`messages`/per-table Postgres elements
(C4 stops at container grain; the only WORM mention is descriptive prose on
a notification store). External-actor enumeration: none new (no new human
role; erasure remains founder/admin-initiated). External-system/vendor
enumeration: none (no new integration). Containers/data-stores touched:
`public.action_sends` inside the existing Supabase Postgres — not
C4-modeled. Access relationships: unchanged (RLS policies untouched;
`check-tom4-rls-posture.sh` still asserts `user_id = auth.uid()` on every
`action_sends` policy).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | [issue #10254] "e.g. anonymise/tombstone messages instead of cascade-delete for users with anchored sends, or a migration-level change to the action_sends↔messages relationship. Until it lands, the two worm suites tolerate the verified-anchor residue" | Phase 1 (migration 162: ruled option (b)) + Phase 3 (tolerance removal) | mapped |
| 2 | [ruling comment] "`ALTER TABLE action_sends ALTER COLUMN message_id DROP NOT NULL, DROP CONSTRAINT …, ADD CONSTRAINT … ON DELETE SET NULL`" | Phase 1 — FK reshape | mapped |
| 3 | [ruling comment] "keep the 064 statement-level `BEFORE UPDATE OF` trigger minus `message_id`; add a NEW row-level `BEFORE UPDATE OF message_id` trigger through `action_sends_no_mutate`" | Phase 1 — trigger split | mapped |
| 4 | [ruling comment] "admit `OLD.message_id IS NOT NULL AND NEW.message_id IS NULL` with all other columns unchanged AND the parent `messages` row already deleted (`NOT EXISTS` initiator check); DELETE stays universally blocked" | Phase 1 — carve-out branch | mapped |
| 5 | [ruling comment] "`COMMENT ON COLUMN` stating `NULL = post-erasure de-link`; ship `.down.sql` + `supabase/verify/162_*.sql` + migration test mirroring the 161 test" | Phase 1 (comments/down/verify) + Phase 2 (shape test) | mapped |
| 6 | [ruling comment] "`anonymise_action_sends` also sets `message_id = NULL` under the GUC bypass" | Phase 1 — RPC hardening | mapped |
| 7 | [ruling comment] "The documented tolerances in `action-sends-worm.test.ts` and `template-authorizations-worm.test.ts` (and `hasUndeletableActionSendsAnchor` in `tenant-isolation-teardown.ts`) become removable dead code in the same PR" | Phase 3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| `162_*.sql` forward migration | asks 2–4, 6 | asked |
| `162_*.down.sql` | ask 5 ("ship `.down.sql`") | asked |
| `supabase/verify/162_*.sql` | ask 5 ("`supabase/verify/162_*.sql`") | asked |
| `test/supabase-migrations/162-*.test.ts` | ask 5 ("migration test mirroring the 161 test") | asked |
| Tolerance removal in two worm suites + teardown helper | ask 7 | asked |
| `TG_LEVEL = 'ROW'` gate inside the carve-out branch | — | inferred — justification: `action_sends_no_mutate` also serves the statement-level triggers, where OLD/NEW are unassigned records; without the gate the statement path raises `record "old" is not assigned yet` instead of clean P0001 — required to preserve the ruled "DELETE/other UPDATEs still reject" contract |
| `account-delete.cascade.integration.test.ts` extension | — | inferred — justification: that suite is the documented end-to-end backstop for this exact defect class (preflight-worm-cascade-contradiction.sh names it "the behavioural backstop that catches any raise idiom"); seeding one `action_sends` row pins the wedge's end-to-end absence; CTO ruled it **required** (2026-10-15): the suite exists because teardown-only coverage surfaces as `afterAll` noise. Fixture plumbing: the `action_sends` insert needs ancestor seeds — a `scope_grants` row (`grant_id NOT NULL`), a fresh `messages` row owned by the test user (`action_sends_message_unique` forbids shared messages), then the send row — service-role INSERTs or the `write-action-send` path; post-delete assertion mirrors `audit_byok_use`: row survives, `message_id IS NULL` |
| Legal-doc parity edits (disclosure §2.3(r) ×2 mirrors + article-30-register rows) | — | inferred — justification: §2.3(r) and the Art-30 TOM rows describe this trigger as "pure-reject" and enumerate `message_id`; shipping the carve-out without the doc update leaves published compliance text misstating the mechanism (GDPR gate 2.7 consequence) |
| Verify-file always-emits-a-row form (`CASE WHEN EXISTS(...) AND <cond>`) | — | inferred — justification: the 160 sentinel returns zero rows if the function is absent, a vacuous pass; per-check EXISTS makes a missing object bad=1 |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform` (migrations/verify/tests), `docs/` + `plugins/soleur/docs/` (legal mirror), `knowledge-base/legal/` (Art-30 register)
- Planned files: 4 created + 7 edited = 11 | Estimated changed lines: ~450 (mostly new files)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/supabase/migrations/162_action_sends_message_id_cascade_null_carveout.sql` exists with: `message_id` DROP NOT NULL; `action_sends_message_id_fkey` dropped and re-added `ON DELETE SET NULL`; `to_regclass` preconditions for `public.action_sends` + `public.messages`
- [ ] `action_sends_no_update` redeclared `BEFORE UPDATE OF` the 11 non-`message_id` pre-064 columns `FOR EACH STATEMENT`; new `action_sends_message_id_guard` is `BEFORE UPDATE OF message_id FOR EACH ROW`; `action_sends_no_delete` untouched
- [ ] `action_sends_no_mutate` admits exactly the ruled transition — `OLD.message_id IS NOT NULL AND NEW.message_id IS NULL AND (to_jsonb(NEW)-'message_id')=(to_jsonb(OLD)-'message_id') AND NOT EXISTS (SELECT 1 FROM public.messages WHERE id = OLD.message_id)` — gated on `TG_OP='UPDATE' AND TG_LEVEL='ROW'`; all other UPDATEs and every DELETE raise P0001; `app.worm_bypass` fast-path precedes every raise
- [ ] `anonymise_action_sends` sets `message_id = NULL` inside its existing GUC window; auth checks and re-arm unchanged
- [ ] `162_*.down.sql` restores the 087 function body, the 064 12-column trigger, `NOT NULL` + NO ACTION FK, drops the row-level trigger, and carries the reinstatement WARNING
- [ ] `supabase/verify/162_*.sql` emits one `(check_name, bad)` row per check with the always-emits EXISTS form (a missing object is bad=1, never a missing row)
- [ ] `test/supabase-migrations/162-*.test.ts` passes and pins every invariant in Guard 2's assembly (vitest run per the worktree convention `./node_modules/.bin/vitest run`, deps permitting)
- [ ] `bash apps/web-platform/scripts/lint-migration-fk-preconditions.sh` passes on the new migration — command verified at plan time against the 161 precedent (rc=0)
- [ ] `hasUndeletableActionSendsAnchor` and both `tolerate:` call sites are gone — `git grep -n 'hasUndeletableActionSendsAnchor\|tolerate:' -- apps/web-platform/test/server/action-sends-worm.test.ts apps/web-platform/test/server/template-authorizations-worm.test.ts apps/web-platform/test/helpers/tenant-isolation-teardown.ts` returns zero hits (the generic `tolerate:` OPTION in `tearDownTenantUsers` and its unit test remain)
- [ ] Legal surfaces consistent: disclosure §2.3(r) (both copies) and the Art-30 register rows no longer describe the trigger as unconditionally pure-reject
- [ ] `action_sends.grant_id` and `preflight-worm-cascade-contradiction.sh` are untouched (descoped to #10379)
- [ ] PR body carries `Closes #10254` and the `## Changelog` section (plugin-versioning convention); the merge-triggered release pipeline's `migrate` job applies 162 to prd, so `Closes` (not `Ref`) is correct

### Post-merge (deployed surface — runs in CI/release pipeline, no operator step)

- [ ] `run-verify.sh` against dev/prd shows all `verify/162` checks with `bad=0` (the always-emits form makes a missing object visible as `bad=1`, not absent)
- [ ] `TENANT_INTEGRATION_TEST=1` worm suites green WITHOUT tolerances — teardown exercises the real `deleteUser` path against a seeded `action_sends` row
- [ ] `account-delete.cascade.integration.test.ts` green with the seeded `action_sends` row (the documented end-to-end backstop for this wedge class)

## Domain Review

**Domains relevant:** Legal (GDPR Art-17/Art. 5(2) surface), Engineering (host domain). Product/UX: **NONE** — no UI-surface file in either Files list (`components/**`, `app/**/page.tsx`, `app/**/layout.tsx` all absent); the mechanical override does not fire. (Domain-leader subagent spawns were unavailable in this planning context — no Task tool; assessments below are inline and marked accordingly.)

### Legal

**Status:** reviewed (inline — no subagent spawn available)
**Assessment:** This change REMOVES an Art-17 blocker; it does not add a
processing activity (no Art. 30 trigger beyond the doc-accuracy edits).
Lawful basis unchanged: Art. 6(1)(b) contract performance for the signature
ledger, Art. 5(2) accountability for retaining the anonymised row. Post-
erasure residue is Recital-26 anonymous **provided** `anonymise_scope_grants`
has run (it severs `grant_id → founder_id`; `account-delete.ts` orders it at
step ~3.82 — verified). One boundary worth stating: a `messages` deletion
outside erasure (conversation cascade) de-links `message_id` while
`user_id` survives — intended per the ruling ("message_id is pure
linkage"). Art. 9: no special-category data in the table (hashes, enums,
FKs only). No `compliance/critical` finding; no `compliance-posture.md`
write required. The Art-30 register + disclosure edits keep published TOM
text truthful — that is the gate's artifact here.
**CPO sign-off:** required by `brand_survival_threshold: single-user
incident` before `soleur:work`; spawn unavailable here — persisted to
`decision-challenges.md` for the pipeline to surface.

## Test Scenarios

- **(integration, TENANT_INTEGRATION)** Given a synthetic user with a seeded
  `action_sends` row anchoring a `messages` row, when `tearDownTenantUser`
  runs `deleteUser` WITHOUT any `tolerate:` escape, then teardown succeeds
  and the `action_sends` row survives with `message_id IS NULL` (carve-out
  fired inside GoTrue's transaction).
- **(integration)** Given a seeded `action_sends` row whose `messages` row
  still exists, when any role issues `UPDATE action_sends SET message_id =
  NULL`, then P0001 is raised (initiator check rejects the forged
  transition).
- **(integration)** Given a seeded row, when `anonymise_action_sends` runs,
  then `user_id`, `recipient_id_hash`, AND `message_id` are all cleared in
  the row (hardening pinned) while `template_hash`/`grant_id`/`action_class`
  remain unchanged.
- **(integration)** Given a seeded row, when `DELETE FROM action_sends` is
  attempted, then P0001 — the carve-out never admits DELETE.
- **(integration)** Given an UPDATE touching `message_id` AND another
  protected column, when it executes, then P0001 — the `to_jsonb` compare
  catches the extra column even though the statement trigger fires first
  anyway.
- **(unit — offline shape test)** Given migration 162's three files, when
  the vitest suite runs, then every Guard-2 assembly regex pins true and
  the mutation matrix rows each isolate to a failing assertion.
- **(integration)** Given a messages row deleted via conversation cascade
  (not user erasure), when the delete commits, then linked `action_sends`
  rows carry `message_id IS NULL` and the user row survives intact —
  cross-path de-link works on every deletion path, per the ruling.
- **Regression note:** `account-delete.cascade.integration.test.ts` with a
  seeded `action_sends` row is the deploy-level backstop for this wedge
  class; opt-in `TENANT_INTEGRATION_TEST=1` applies.

## Downtime & Cutover

**Offline-inducing operation (deepen-plan Phase 4.55 trigger — database lock
class):** the FK re-creation (`DROP CONSTRAINT` + `ADD CONSTRAINT`) on
`public.action_sends`. A plain `ADD CONSTRAINT ... FOREIGN KEY` scans all
existing rows under `ACCESS EXCLUSIVE`.

**Zero-downtime path (default — adopted):**

- `ALTER COLUMN message_id DROP NOT NULL` — metadata-only `ACCESS
  EXCLUSIVE`, instantaneous.
- `DROP CONSTRAINT` — `ACCESS EXCLUSIVE`, instantaneous (no scan).
- `ADD CONSTRAINT ... NOT VALID` — `SHARE ROW EXCLUSIVE`; enforces on new
  writes immediately while skipping the existing-row scan.
- `VALIDATE CONSTRAINT` — `SHARE UPDATE EXCLUSIVE`; reads AND writes stay
  unblocked during the scan. `action_sends` is a low-row ledger, so the scan
  is milliseconds either way — `NOT VALID` + `VALIDATE` is still the correct
  default because the gate's rule is mechanism-first, not size-first.
- `DROP`/`CREATE TRIGGER` — `SHARE ROW EXCLUSIVE`, instantaneous;
  `CREATE OR REPLACE FUNCTION` — catalog write, no table lock.

**Per-stage verification/rollback:** the whole migration runs inside the
runner's transaction (`run-migrations.sh` wraps each file), so any failure
rolls back atomically; the `.down.sql` restores the prior shape. Residual
downtime: none accepted and none expected — no operator window needed.

## Risks & Mitigations

- **Precedent diff (Phase 4.4):** `action_sends_no_mutate` vs the 161
  template — same DEFINER + `search_path` pin + bypass-first + per-column
  `to_jsonb` compare + `NOT EXISTS` initiator check + `REVOKE` quartet.
  Deliberate divergences: (a) `TG_LEVEL='ROW'` gate — required because this
  function also serves statement-level triggers (161's is row-only); (b)
  initiator check reads `public.messages`, not a users table (the
  table-to-table case #10379 tracks for the preflight gate); (c) `NOT
  VALID` + `VALIDATE CONSTRAINT` on the FK re-add (zero-downtime default).
- **Carve-out admits a forged de-link on a live message** → mitigated by the
  `NOT EXISTS` initiator check + `to_jsonb`-minus compare; pinned by the new
  negative integration test and Guard 1's live probe.
- **Dev schema drift between file and live body** → mitigated by
  `verify/162` (the class the #9994 learning names as the only permanent
  live-body gate).
- **Statement trigger regression** (e.g., message_id left in the 064 list
  would double-fire) → pinned by Guard 2's column-set assertion and the
  `TG_LEVEL` gate.

## Non-Goals

- `action_sends.grant_id` (`→ scope_grants`, NO ACTION) — the dormant
  same-class anchor; out of scope per the pipeline brief, tracked under
  #10379's WORM-table audit item.
- `preflight-worm-cascade-contradiction.sh` envelope extension
  (`confrelid='public.users'` only) — filed as #10379 by the ruling.
- `account-delete.ts` saga changes — the ruling rules them unnecessary.
- Any change to the WORM contract for tables other than `action_sends`.
- Re-numbering: 162 was the next free number at plan time; a sibling
  migration claiming 162 before merge is resolved at rebase, not here.

## Context / References

- Issue: #10254 (+ CTO ruling comment, 2026-10-15 — the prescriptive source)
- Ruled-out alternatives: tombstone-`messages` (a); RESTRICT + RPC-eager-null (narrower (b))
- Precedents: `160_dsar_export_audit_pii_cascade_null_carveout.sql`,
  `161_audit_github_token_use_cascade_null_carveout.sql` (+ its test),
  mig 066 `audit_byok_use` founder_id shape
- Learning: `learnings/test-failures/2026-10-12-a-set-null-fk-into-a-worm-table-fires-the-worm-gate-on-the-cascade.md`
- Gate: `apps/web-platform/scripts/preflight-worm-cascade-contradiction.sh`
  (envelope note: scans `confrelid=public.users` only; table-to-table
  chains escape — #10379)
- Follow-ups: #10379 (envelope + audit), refs #10096, #9993, #9994, #10238
- Spec note: `Spec lacks valid lane:` — defaulted to cross-domain (TR2
  fail-closed); no brainstorm/spec.md existed for this branch.
- Advisor consult (Phase 4.5): skipped — the design is externally ruled
  with a shipped triple precedent; the only plan-authored wrinkle
  (TG_LEVEL gating) is mechanical and derived from Postgres trigger
  semantics documented in the migration's own comments.

## Enhancement Summary

Deepened 2026-10-15 (in-process run — no subagent/Task tool in this context;
fan-out phases were resolved inline against the repo):

- Phase 4.55 fired on the FK re-add (`ADD CONSTRAINT` lock class) → added
  `## Downtime & Cutover` and switched the sketch to `NOT VALID` +
  `VALIDATE CONSTRAINT` (zero-downtime default).
- Phase 4.10 fired on `supabase/migrations/*.sql` → `## Encryption Posture`
  emitted citing the existing `supabase.prd` ledger row; no new store or
  connection.
- Phase 4.11 fired on the `verify/162` drift sentinel → `## Guard Contract`
  with two guards (verify sentinel + shape test); `lint-guard-contract.py`
  run against this file: rc=0, 2 entries.
- Phase 4.6/4.7/4.8/4.9/4.12: all pass — User-Brand Impact has a concrete
  `single-user incident` threshold; Observability's probe is an
  allowlisted-verb literal-output command; no PAT-shaped variables; no UI
  surface; Scope Check has 7 mapped asks + justified inferred items +
  single-PR recommendation.
- Phase 4.4 precedent diff captured in `## Risks & Mitigations` (161/087
  side-by-side, three deliberate divergences named).
- Caught at deepen time, fixed before writing: `TG_LEVEL='ROW'` gate is
  load-bearing (the shared function serves statement triggers where
  OLD/NEW are unassigned); verify-file checks must always emit a row
  (missing object = bad=1, not absent); legal surfaces §2.3(r) + Art-30
  register go stale on this change and are in-scope edits.
