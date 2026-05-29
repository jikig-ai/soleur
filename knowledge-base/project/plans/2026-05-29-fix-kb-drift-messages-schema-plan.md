---
feature: fix-kb-drift-messages-schema
issue: 4579
branch: feat-fix-kb-drift-messages-schema
pr: 4580
date: 2026-05-29
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-05-29-kb-drift-messages-schema-brainstorm.md
spec: knowledge-base/project/specs/feat-fix-kb-drift-messages-schema/spec.md
status: plan-reviewed
---

# Plan: Map KB-drift findings onto the workspace-scoped `messages` model

🐛 **fix** · cross-domain · brand-survival threshold = **single-user incident** (CPO sign-off required before `/work`)

> Revised after 4-agent review (spec-flow + DHH + Kieran + code-simplicity). Material changes
> folded in: the latent NOT-NULL/RLS failure is in **all three** draft-card producers (not just
> kb-drift); the `NOT VALID`/`VALIDATE` lock rationale was wrong (single-transaction runner); the
> digest card needed a working operator-action path (it 422'd on click and could not be
> dismissed). Operator confirmed: fix all three producers; fold in the minimal Dismiss path.

## Overview

The nightly **KB-drift walker** (`.github/workflows/kb-drift-walker.yml`, cron `0 3 * * *`)
HMAC-signs its findings and POSTs them to `/api/internal/kb-drift-ingest`, which tries to
persist each finding as a "draft action card" row in `messages`. **The insert has never once
succeeded.** `messages` requires (NOT NULL, no default, no trigger) `conversation_id, role,
content, template_id, workspace_id`; the draft-card insert (`route.ts:137`) supplies none of
`conversation_id/role/content/template_id`, and — because migration 059 rewrote the RLS — the
RLS-bypassing service client masks (but does not satisfy) the workspace-member INSERT policy.

**This is not a kb-drift-only bug.** The two sibling draft-card producers
(`github-on-event:237`, `cfo-on-payment-failed:229`) insert the *same* shape and *also* omit
`workspace_id`+`template_id`, so they have likewise never persisted (their upstreams are stubbed,
so the failure is latent, not observed). A single shared helper + one schema relaxation fixes all
three structurally.

The fix has six moving parts (two plan-time refinements decided with the operator — see Reconciliation):

1. **Schema relaxation (migration 082).** `DROP NOT NULL` on `conversation_id, role, content` +
   a discriminator `CHECK messages_row_kind_chk` admitting a row as *either* a chat row *or* a
   draft-card row. (`template_id`/`workspace_id` are **not** relaxed — Decision A.)
2. **Shared `insertDraftCard` helper** (`server/messages/insert-draft-card.ts`) that resolves
   `workspace_id`, supplies `template_id='default_legacy'`, redacts `draft_preview`, writes via
   the RLS-enforced tenant client, and maps `23505`→idempotent skip (`23514`→loud throw).
3. **Cross-tenant-safe write.** kb-drift switches `createServiceClient()` → `getFreshTenantClient(operatorFounderId)`
   with `workspace_id = resolveCurrentWorkspaceId(operatorFounderId, tenant)`.
4. **All three producers adopt the helper** (kb-drift, github-on-event, cfo-on-payment-failed) —
   closing the latent NOT-NULL/RLS failure (and cfo's silent-error swallow) in each.
5. **One digest card per walker run**, packed into the existing `draft_preview` string, dedup-keyed
   on a content hash (unchanged KB → idempotent skip).
6. **Working operator-action path** for the digest card: a valid `action_class` + a Dismiss
   affordance (existing `/today/[id]/discard` route) so the operator can clear it. (Per-finding
   drill-down deferred.)

This honors ADR-037 (no per-source table; `messages` stays the canonical row) and finishes the
intent migration 046 documented but never completed ("route via `user_id` — no `conversation_id`
required").

---

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Codebase reality (grounded) | Plan response |
|---|---|---|
| "chat works in prod; only the draft-card inserts fail" | `agent-runner:447,2425`, `cc-dispatcher:1445` (chat) **and** `github-on-event:237`, `cfo:229` (drafts) all omit `workspace_id`+`template_id` — both NOT NULL (`059:94`, `053:65`), no default, no trigger (exhaustive grep: 0 `CREATE TRIGGER … messages`). Per migration files these inserts should fail `23502`. | **Phase 0 live-prod schema verification is a hard gate.** The relaxation of `conversation_id/role/content` is needed regardless. If prod schema = migration files, the **siblings** are latently broken too → the helper fixes all three (in scope). If chat genuinely inserts, prod schema ≠ migration files → file a follow-up; do not pour the CHECK on a shape we don't understand (DHH caveat). |
| spec FR1: relax `template_id` NOT NULL too | shape CHECK `^[a-z][a-z0-9_]*$` (`053:71`); send route nullish-coalesces null→`default_legacy` (`today/[id]/send/route.ts:186`). Cards are ack-only (operator decision). | **Decision A (amends FR1):** do **not** relax `template_id`; helper supplies `'default_legacy'`. 3 cols relaxed, not 4 — smaller hot-table blast radius. |
| "NOT VALID then VALIDATE defers the ACCESS-EXCLUSIVE lock" (my v1 rationale) | **Wrong here.** `run-migrations.sh` applies each file with `psql --single-transaction` (`:335`). Both `ADD CONSTRAINT … NOT VALID` and `VALIDATE` run in **one** transaction → no lock deferral. | Restate the rationale: at current single-founder scale the split is **cosmetic / forward-portable**; Phase 0.2 proves 0 violators, so a plain validated `ADD CONSTRAINT` is equally safe. (True deferral would need two migration files — declined at this scale.) |
| FR3: `resolveCurrentWorkspaceId(operatorFounderId)` (1 arg) | **2-arg** `resolveCurrentWorkspaceId(userId, supabase)` (`workspace-resolver.ts:94`); reads `user_session_state` via the passed client; returns `userId` (solo) when absent (`:121`). | Helper calls `resolveCurrentWorkspaceId(founderId, tenant)`. |
| brainstorm: "only a PERMISSIVE workspace-member WITH CHECK; no RESTRICTIVE" | Confirmed (`059:106-113`) **and** 059 **dropped** 046's `user_id`-based external-draft policies. A `user_id`-only insert with no `workspace_id` fails RLS INSERT (no matching policy) **in addition to** NOT NULL. | Reinforces FR3: `workspace_id` is mandatory for RLS, not just NOT NULL. Service-role bypass masked this. |
| route comment + brainstorm: dedup index "migration 051" | Index in **`052_multi_source_dedup.sql:51`**: `UNIQUE (user_id, source, source_ref) WHERE status='draft' AND source_ref IS NOT NULL`. Partial-on-draft → archived (dismissed) rows free the slot. | Fix stale `route.ts:12` comment. Digest `source_ref` (content hash) non-null → partial index applies → `23505` skip. Dismissed-then-recur → new card (no blind spot; Phase 0.5 confirms predicate). |
| brainstorm "ADR-035/037" | `ADR-037-messages-source-ref-composite-unique…` = dedup design of record; `ADR-035` = *separate* template-registry ADR. | Cite ADR-037 for dedup; ADR-035 only for the `default_legacy` key. |
| spec: "the three inserters share the identical insert shape" | **Not identical.** kb-drift+github carry `source_ref`; cfo does **not** (adds `action_class`, literal `source/owning_domain`). cfo `:229` **does not destructure `{ error }`** → silent swallow (`cq-silent-fallback…` violation today). *(Agents disagree on whether github currently sets `action_class` — verify at Phase 4.)* | Helper makes `source_ref` and `action_class` **optional**. cfo refactor closes its silent swallow. |
| FR5: redact via shared helper | `redactGithubSourcedText(s, opts={})` exists (`redaction-allowlist.ts:107`); `RedactionSource` enum has no `kb_drift`; `_opts` is **unused** → redaction is source-agnostic. | **Redact inside the helper** (single idempotent choke point — decided now, not at /work; protects cfo which redacts nothing today). Call `redactGithubSourcedText(text)` with no source. **Drop** the cosmetic enum edit. |
| (new) digest card is actionable | `action_class` null → send route 422s (`today/[id]/send/route.ts:133` `isKnownActionClass`); `KbDriftCard` has no Dismiss button (only StripeCard does). `knowledge.kb_drift` IS valid (`action-class-map.ts:36`). | Set `action_class='knowledge.kb_drift'`; render Dismiss (→ existing `/discard`) for digest cards; no spawn button for digests. |

---

## User-Brand Impact

*(Carried forward from brainstorm; threshold drives `requires_cpo_signoff: true`.)*

- **If this lands broken, the operator experiences:** the nightly walker keeps failing (`500
  Persist failed`); knowledge-domain drift never reaches the Today queue — the operator stays
  blind to broken docs links/anchors. *(And, per the spec-flow finding, a card that **lands but
  422s on click and can't be dismissed** is the same blindness one step downstream.)*
- **If this leaks, the data exposed is:** an operator-internal infra draft cross-posted into a
  **paying tenant's** Today queue. Vector: kb-drift's current `createServiceClient()` write
  **bypasses** `is_workspace_member(workspace_id, auth.uid())`; a mis-resolved `workspace_id` has
  no DB guard. `draft_preview` could carry a token in a broken-target URL query string.
- **Brand-survival threshold:** `single-user incident` (GDPR Art. 5(1)(f) + Art. 32; no statutory
  clock unless a leak occurs).
- **Decisive controls:** FR3 tenant-client write (membership becomes the DB backstop);
  `workspace_id` resolved server-side from `operatorFounderId`, never request-derived (no IDOR);
  FR5 redaction in the helper. `user-impact-reviewer` must verify FR3 + FR5 at PR review.

---

## Research Insights (grounded, path:line)

- **kb-drift route** `app/api/internal/kb-drift-ingest/route.ts` — insert `:137` (one row per finding loop `:136-164`); `createServiceClient()` `:132`; operator id `KB_DRIFT_OPERATOR_FOUNDER_ID` `:122`; Sentry `op:"persist"` `:157`; **silent dedup** `:149-151` (no Sentry — `cq-silent-fallback` gap); stale "migration 051" comment `:12`.
- **Siblings:** `github-on-event.ts:237` (tenant client + `redactGithubSourcedText`; omits `workspace_id`/`template_id`); `cfo-on-payment-failed.ts:229` (stub preview, no `source_ref`, has `action_class`, **no `{ error }` destructure**).
- **Write primitives:** `getFreshTenantClient(userId): Promise<SupabaseClient>` async, Next-free (`lib/supabase/tenant.ts:736`); `resolveCurrentWorkspaceId(userId, supabase): Promise<string>` solo→`userId` (`server/workspace-resolver.ts:94,121`); `createServiceClient()` `@deprecated`, RLS-bypass (`lib/supabase/service.ts:155`).
- **Schema:** base `001:67-76` (`conversation_id/role/content NOT NULL`, `role CHECK in ('user','assistant')`); draft cols nullable `046:92-99` + `messages_status_check` + `messages_external_tier_status_check` `046:269`; `template_id` NOT NULL + shape CHECK `053:65,71`; `workspace_id` NOT NULL + RLS rewrite `059:94,99-122`; `messages_action_class_not_locked` (`action_class IS NULL OR action_class !~ '^(payment|legal|auth)\.'`) `051:81`; dedup index `052:51`.
- **RLS substrate:** `is_workspace_member` plpgsql SECURITY DEFINER `SET search_path = public, pg_temp`, `GRANT EXECUTE TO authenticated` (`053_organizations_and_workspace_members.sql:116,140`); INSERT policy `FOR INSERT TO authenticated WITH CHECK is_workspace_member(workspace_id, auth.uid())` (`059:106-108`); solo `workspaces.id = owner_user_id` + backfilled `workspace_members(id,id)` (`053…:208,240-247`).
- **Migration runner:** `web-platform-release.yml` `migrate` job → `doppler run -c prd -- bash apps/web-platform/scripts/run-migrations.sh`; applies `*.sql` forward only (`*.down.sql` skipped); **`psql --single-transaction`** (`run-migrations.sh:335`); prefix collisions emit `::warning::` only; files apply in filename-lexical order. No `CONCURRENTLY` (`046:33-35`). Next free number = **082**.
- **Today consumer** `app/api/dashboard/today/route.ts:121` — selects `id, source, source_ref, owning_domain, draft_preview, urgency, created_at`; filters `.eq("user_id").in("tier",…).eq("status","draft")`; cap `TODAY_ITEM_CAP=7` (`:107`); **never reads role/content/conversation_id**.
- **Chat render** `server/api-messages.ts:130-140` — conversation-scoped; never sees draft rows.
- **Today card UI** `components/dashboard/today-card.tsx` — `draftPreview: string` (single), `KbDriftCard` renders `whitespace-pre-line` (`:151`), button "Fix link"/"Update anchor" → `useActionSend`→`/send` (`:163-172`); only `StripeCard` has a Discard button (`:347`). `/discard` route exists (`app/api/dashboard/today/[id]/discard/route.ts`).
- **Action class** `server/scope-grants/action-class-map.ts:36` — `knowledge.kb_drift` valid (tier `draft_one_click` `:93`); send route rejects unknown via `isKnownActionClass` (`today/[id]/send/route.ts:133`).
- **Constants** `lib/messages/tiers.ts` — `MESSAGE_TIER_EXTERNAL_LOW_STAKES`, `MESSAGE_STATUS_DRAFT`, `MESSAGE_SOURCE_KB_DRIFT`, `MESSAGE_OWNING_DOMAIN_KNOWLEDGE`; `PG_UNIQUE_VIOLATION` in `lib/postgres-errors`.
- **Learnings:** ADR-037 (plain `.insert()` + catch `23505`, never `ON CONFLICT`); `2026-05-03-postgrest-on-conflict-cannot-infer-partial-index` (42P10); `2026-04-18-supabase-migration-concurrently-forbidden`; `2026-04-17-migration-not-null-without-backfill-and-partial-unique-index-pattern`; `2026-03-20-supabase-silent-error-return-values`; `2026-04-18-server-bundle-transitive-next-headers-leak`; `2026-04-18-discriminated-union-widening-if-ladders-and-config-map-parity`; `security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments`; `security-issues/2026-04-18-rls-for-all-using-applies-to-writes`.

---

## Open Code-Review Overlap

2 open `code-review` issues mention `supabase/migrations` generically — **#3220** (postmerge verification of trigger-bearing migrations) and **#3221** (nightly cron for env-gated integration tests). **Acknowledge both:** different concern (CI verification infra); this migration adds no trigger. Not folded in. No overlap on the code files (`kb-drift-ingest`, `github-on-event`, `cfo-on-payment-failed`, helper, `today-card`, `dashboard/today`, `redaction-allowlist`, `workspace-resolver`, `tenant`).

---

## Implementation Phases

> **Phase order is load-bearing** (`2026-05-10-plan-phase-order-load-bearing-when-contract-changes`):
> the migration (contract) precedes the helper/route (consumers). One atomic merge; sequential `/work`.

### Phase 0 — Live-prod precondition gate (BLOCKING; no code; read-only)

`hr-no-dashboard-eyeball-pull-data-yourself`. *(If Supabase MCP is unauthenticated at /work, run via `doppler run -c prd -- psql` per the migrations runbook, or the PostgREST OpenAPI probe the brainstorm used.)*

- **0.1 Schema truth:**
  ```sql
  SELECT column_name, is_nullable, column_default FROM information_schema.columns
  WHERE table_schema='public' AND table_name='messages'
    AND column_name IN ('conversation_id','role','content','template_id','workspace_id');
  ```
  If `workspace_id`/`template_id` are NOT NULL + no default → confirms the **siblings** are latently broken (in scope; the helper fixes them) and, separately, the chat-insert paths are a distinct latent bug → **file a follow-up** (do not widen this PR). If prod ≠ migration files → **pause**: re-confirm the migration 082 shape before proceeding (DHH caveat — do not pour the CHECK on an unverified shape).
- **0.2 No discriminator violators** (so `VALIDATE` cannot fail, TR1):
  ```sql
  SELECT count(*) FROM public.messages WHERE NOT (
    (conversation_id IS NOT NULL AND role IS NOT NULL AND content IS NOT NULL)
    OR (user_id IS NOT NULL AND source IS NOT NULL AND owning_domain IS NOT NULL AND draft_preview IS NOT NULL));
  -- expect 0
  ```
- **0.3 Operator membership** (FR3 RLS passes only if true):
  ```sql
  SELECT EXISTS(SELECT 1 FROM public.workspace_members
    WHERE workspace_id='<operatorFounderId>' AND user_id='<operatorFounderId>');  -- expect t
  ```
- **0.4 Sibling-row probe** (did any sibling draft ever land?):
  ```sql
  SELECT source, count(*) FROM public.messages
  WHERE source IN ('github','stripe') AND status='draft' GROUP BY 1;
  ```
- **0.5 Dedup predicate** (confirm partial-on-draft so dismissed rows free the slot — no stale-digest blind spot):
  ```sql
  SELECT indexdef FROM pg_indexes WHERE indexname='messages_active_draft_dedup_idx';
  -- expect: … WHERE status='draft' AND source_ref IS NOT NULL
  ```

### Phase 1 — Migration 082 (RED-first)

`apps/web-platform/supabase/migrations/082_relax_messages_draft_card_nullability.sql` (+`.down.sql`).
**Collision guard:** at `/work` and again at merge/rebase, `ls migrations/ | grep '^082'`; if any other `082_*.sql` appears, renumber to the next free integer (runner tolerates collisions with only a `::warning::` and applies in lexical order, so a colliding 082 is a real hazard).

```sql
-- 082: relax messages NOT NULL for user_id-routed draft action cards.
-- Finishes the mig-046 intent ("route via user_id — no conversation_id
-- required"). Honors ADR-037 (messages stays the canonical draft-card row).
-- run-migrations.sh uses psql --single-transaction; the NOT VALID/VALIDATE
-- split therefore defers NO lock here — it is cosmetic/forward-portable at
-- current scale, and Phase 0.2 proves 0 violators so this is safe.
ALTER TABLE public.messages ALTER COLUMN conversation_id DROP NOT NULL;
ALTER TABLE public.messages ALTER COLUMN role            DROP NOT NULL;
ALTER TABLE public.messages ALTER COLUMN content         DROP NOT NULL;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_row_kind_chk CHECK (
    (conversation_id IS NOT NULL AND role IS NOT NULL AND content IS NOT NULL)
    OR
    (user_id IS NOT NULL AND source IS NOT NULL
      AND owning_domain IS NOT NULL AND draft_preview IS NOT NULL)
  ) NOT VALID;
ALTER TABLE public.messages VALIDATE CONSTRAINT messages_row_kind_chk;
```
Notes:
- **Discriminator CHECK kept** (code-simplicity + Kieran concur; DHH dissents). Rationale: after removing the column-level guarantees, the CHECK is the only guardrail against an all-null "junk-drawer" row that both readers silently skip (silent data loss) — proportionate on a hot, cross-tenant table, and consistent with the codebase's explicit-constraint culture (046/053). Contingent on Phase 0.1 (do not add atop an unverified schema).
- `role CHECK (role IN ('user','assistant'))` **passes** when `role IS NULL` (SQL CHECK semantics) → no change.
- Coexists additively with `messages_status_check`, `messages_external_tier_status_check` (046), `messages_template_id_check` (053), `messages_action_class_not_locked` (051) — no DROP of those.
- `template_id`/`workspace_id` stay NOT NULL (Decision A). FK on `conversation_id` (`ON DELETE CASCADE`) unaffected by dropping NOT NULL.

`.down.sql` (forward-only in practice; runner never auto-applies down files):
```sql
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_row_kind_chk;
-- Destructive: re-adding NOT NULL FAILS if any draft-card row exists. Manual rollback only.
ALTER TABLE public.messages ALTER COLUMN content SET NOT NULL;
ALTER TABLE public.messages ALTER COLUMN role    SET NOT NULL;
ALTER TABLE public.messages ALTER COLUMN conversation_id SET NOT NULL;
```

### Phase 2 — Shared `insertDraftCard` helper (TDD: RED test first)

New `apps/web-platform/server/messages/insert-draft-card.ts`. **Import the tenant client from
`@/lib/supabase/tenant` (Next-free)** so the Inngest/server bundle doesn't transitively pull
`next/headers` (`2026-04-18-server-bundle-transitive-next-headers-leak`).

```ts
export interface DraftCardInput {
  founderId: string;
  source: string;            // MESSAGE_SOURCE_*
  owning_domain: string;     // MESSAGE_OWNING_DOMAIN_*
  draft_preview: string;     // RAW — redacted inside the helper (FR5)
  tier: string;
  urgency: string;
  trust_tier: string;
  source_ref?: string;       // optional: cfo has none → that row simply won't dedup
  action_class?: string;     // optional: caller-set; helper does NOT pre-validate
}
export type DraftCardResult = { status: "inserted" | "deduped"; id?: string };

export async function insertDraftCard(input: DraftCardInput): Promise<DraftCardResult> {
  const tenant = await getFreshTenantClient(input.founderId);            // mints role=authenticated, sub=founderId
  const workspace_id = await resolveCurrentWorkspaceId(input.founderId, tenant);
  const id = randomUUID();
  const { error } = await tenant.from("messages").insert({
    id,
    user_id: input.founderId,
    workspace_id,
    template_id: "default_legacy",                 // Decision A — ack-only card
    status: MESSAGE_STATUS_DRAFT,
    source: input.source,
    source_ref: input.source_ref ?? null,
    owning_domain: input.owning_domain,
    draft_preview: redactGithubSourcedText(input.draft_preview),   // FR5: single choke point
    tier: input.tier,
    urgency: input.urgency,
    trust_tier: input.trust_tier,
    ...(input.action_class ? { action_class: input.action_class } : {}),
  });
  if (error) {
    if (error.code === PG_UNIQUE_VIOLATION) return { status: "deduped" };   // 23505 → idempotent
    // 23514 (CHECK, incl. messages_action_class_not_locked / row_kind_chk) and all others → loud:
    Sentry.captureException(error, {
      tags: { feature: "insert-draft-card", op: "persist", source: input.source },
      extra: { founderId: input.founderId, workspace_id, source_ref: input.source_ref, code: error.code },
    });
    throw new Error(`insertDraftCard failed (${error.code}): ${error.message}`);
  }
  return { status: "inserted", id };
}
```
- **Always destructure `{ error }`**; branch on `error.code`. `23505`→deduped; everything else (incl. `23514`) → Sentry + throw (distinct from dedup).
- **Never** `.upsert()`/`on_conflict` against the partial index → 42P10.
- **`action_class` is not pre-validated** — callers must not pass `payment.*`/`legal.*`/`auth.*` (would hit `messages_action_class_not_locked` 23514, surfaced loudly).
- **JWT role:** `getFreshTenantClient` mints `role=authenticated` (required by both the INSERT policy and the `is_workspace_member` EXECUTE grant) — asserted in Phase 7 test 3.

### Phase 3 — kb-drift route adopts helper + digest (FR3, FR4, action_class)

Refactor `route.ts:132-171`:
- Remove `createServiceClient()` import + call (sweep `.service-role-allowlist` for any kb-drift entry — `cq-ref-removal-sweep`).
- `if (payload.findings.length === 0)` → 200, no insert (no empty digest card).
- Build **one** digest:
  - `source_ref = "digest-" + sha256(findings.map(f=>f.source_ref).sort().join("\n")).slice(0,16)` (content-hash; unchanged KB ⇒ same ref ⇒ `23505` skip — NOT a per-date key, which would mask intra-day changes / dup quiet days).
  - `draft_preview = \`${N} KB-drift findings — review\n\` + findings.map(f => \`• ${f.kind==="broken-link"?"Broken link":"Broken anchor"} in ${f.source_path} → ${f.target}\`).join("\n")` (redaction happens in the helper).
- One `await insertDraftCard({ founderId: operatorFounderId, source: MESSAGE_SOURCE_KB_DRIFT, source_ref, owning_domain: MESSAGE_OWNING_DOMAIN_KNOWLEDGE, draft_preview, tier: MESSAGE_TIER_EXTERNAL_LOW_STAKES, urgency: "low", trust_tier: "internal_infra_auto", action_class: "knowledge.kb_drift" })`.
- Map `deduped`→200 `{received:true,inserted:0,deduped:1,total:N}`; `inserted`→`inserted:1`.
- Fix `:12` "migration 051"→"052".

### Phase 4 — Sibling refactors (all three; FR2)

- **`github-on-event.ts:230-273`** → replace inline insert with `insertDraftCard({...})`, passing its existing `source_ref` and `action_class` **if present** (Phase-4 step 0: confirm whether github currently sets `action_class` — agents disagreed; pass it through either way). Net change small (already tenant-client + redaction). Helper redaction is idempotent against any existing pre-redaction. **Upstream wiring stays deferred** (Non-Goal).
- **`cfo-on-payment-failed.ts:224-243`** → replace inline insert with `insertDraftCard({...})`, passing `action_class: payload.action_class ?? "finance.payment_failed"` (**resolved at the call site** — never raw `payload.action_class`, which would null→422 on the live CFO card) and **no `source_ref`** (stub; won't dedup). This refactor **fixes cfo's silent-error swallow** (the helper destructures `{ error }` + mirrors to Sentry). Upstream deferred.

### Phase 5 — Digest card operator-action path (UI; ADVISORY)

`components/dashboard/today-card.tsx` — `KbDriftCard`:
- Detect a digest card (`source_ref?.startsWith("digest-")`).
- For digest cards, **render a Dismiss/Acknowledge button** (reuse `StripeCard`'s existing Discard pattern `:347`) wired to the existing `POST /today/[id]/discard` route (archives → row drops out of the Today select at `route.ts:126`). **Do not render the per-finding "Fix link"/spawn button** for digests (semantically wrong for N findings, and avoids the template-auth/send path entirely).
- Per-finding drill-down / individual dismissal remains **deferred** (Follow-up #3).

### Phase 6 — Observability (TR3)

- Add a Sentry mirror to the **dedup-skip** path (currently silent `route.ts:149-151`) per `cq-silent-fallback-must-mirror-to-sentry`: `Sentry.captureMessage("kb-drift digest deduped", { level:"info", tags:{feature:"kb-drift-ingest", op:"dedup-skip"} })`.
- Add structured success-log fields: resolved `workspace_id`, `finding_count=N`, `deduped`.
- **Atomicity note:** the digest is now one row → a persist failure means **zero** operator visibility for that night (vs. the old per-finding partial success). The authoritative "you are blind tonight" signal is the cron run conclusion (GitHub Actions) — documented in the Observability schema. All failure paths reachable from Sentry/Better Stack with **no SSH**.

### Phase 7 — Tests (RED→GREEN; `cq-write-failing-tests-before`, `cq-test-fixtures-synthesized-only`)

1. **Migration contract** (integration vs prod-shaped DB): a draft-card row (null `conversation_id/role/content`, draft-card cols set, `tier=external_low_stakes`, `status=draft`) **inserts** and satisfies `messages_external_tier_status_check`; a neither-branch row is **rejected** by `messages_row_kind_chk`; an existing chat row still inserts.
2. **Helper unit** (mocked supabase): inserted→`{status:"inserted"}`; `23505`→`{status:"deduped"}` (no throw); `23514`/other→throw + Sentry; `resolveCurrentWorkspaceId` called with the tenant client (2 args); `template_id='default_legacy'`; `draft_preview` redacted; `action_class`/`source_ref` omitted from the row when absent.
3. **Cross-tenant rejection** integration (mirrors `cc-dispatcher-cross-tenant.integration.test.ts`): a tenant-client insert claiming a foreign `workspace_id` is **rejected** by `messages_workspace_member_insert`; assert the minted JWT carries `role=authenticated` + `sub=founderId`.
4. **Route digest:** N findings → exactly one `insertDraftCard` call; preview newline-packed; re-POST identical → `deduped:1`; empty findings → no insert; row carries `action_class='knowledge.kb_drift'`.
5. **Dismiss-then-recur** (stale-digest guard): insert digest → archive via `/discard` → re-POST same findings → a **new** draft card inserts (not deduped against the archived row) — proves the operator is never permanently blinded.
6. **Redaction:** a finding `target` carrying an email/token/JWT is scrubbed in `draft_preview` (one assertion; the Unicode-separator / mixed-case adversarial fixtures belong to `redactGithubSourcedText`'s own test, not re-tested here).

> **Write-boundary sweep (TR2)** is satisfied by a **documented grep** in the PR body (not a test): Today consumer filters by `user_id/tier/status` (`dashboard/today/route.ts:121`); chat render is conversation-scoped (`api-messages.ts:140`). No reader assumes non-null `role/content/conversation_id` on a query that can return draft rows.

---

## Files to Edit

- `apps/web-platform/app/api/internal/kb-drift-ingest/route.ts` — adopt helper, digest, `action_class`, dedup→200, Sentry dedup mirror, fix `:12` comment, drop service client.
- `apps/web-platform/server/inngest/functions/github-on-event.ts` — call `insertDraftCard`.
- `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` — call `insertDraftCard` (resolved `action_class` fallback; fixes silent-error swallow).
- `apps/web-platform/components/dashboard/today-card.tsx` — `KbDriftCard` digest Dismiss affordance.
- `apps/web-platform/.service-role-allowlist` — remove any kb-drift entry if present.

## Files to Create

- `apps/web-platform/supabase/migrations/082_relax_messages_draft_card_nullability.sql` (+ `.down.sql`)
- `apps/web-platform/server/messages/insert-draft-card.ts`
- `apps/web-platform/test/server/insert-draft-card.test.ts`
- `apps/web-platform/test/server/messages-draft-card-cross-tenant.integration.test.ts`
- `apps/web-platform/test/api/kb-drift-ingest.test.ts` (or extend an existing route test)

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Migration 082 applies cleanly against a prod-shaped DB; `VALIDATE CONSTRAINT messages_row_kind_chk` succeeds (Phase 0.2 = 0 violators); draft-card row (null `conversation_id/role/content`) inserts and satisfies `messages_external_tier_status_check`; neither-branch row rejected (contract test green).
- [ ] `insertDraftCard` unit tests green: inserted / `23505`-deduped / `23514`-throw-with-Sentry; `resolveCurrentWorkspaceId(founderId, tenant)`; `template_id='default_legacy'`; `draft_preview` redacted.
- [ ] Cross-tenant integration: foreign-`workspace_id` insert rejected; minted JWT `role=authenticated`, `sub=founderId`.
- [ ] Route digest: N findings → one insert; re-POST identical → `deduped:1`; empty → no insert; row carries `action_class='knowledge.kb_drift'`.
- [ ] Dismiss-then-recur test green (archived row frees the dedup slot).
- [ ] Redaction test green.
- [ ] All three producers route through `insertDraftCard`; cfo no longer swallows its insert error.
- [ ] `tsc --noEmit` + `vitest run` for touched packages pass; no `createServiceClient` in kb-drift route.
- [ ] `/soleur:gdpr-gate` run on the diff; no unresolved Critical.

### Post-merge (operator/CI — automatable; baked into ship/CI, not manual)

- [ ] `web-platform-release.yml#migrate` applies 082 on merge; `verify-migrations` job green.
- [ ] `gh workflow run "KB-drift walker"` → `gh run list --workflow "KB-drift walker" --limit 1 --json conclusion --jq '.[0].conclusion'` = `success`. *(Bake into `/soleur:ship` post-merge.)*
- [ ] The digest row is visible in the operator founder's knowledge-domain Today queue, scoped to the operator's own `workspace_id` (verify via read-only prd query, not dashboard eyeballing).
- [ ] Operator can **Dismiss** the digest card; dismissed card does not reappear on next page load.
- [ ] Re-run over unchanged KB → `deduped:1`, no duplicate card.
- [ ] Follow-up issues filed (`Ref #N`, not `Closes`): ADR; sibling upstream wiring; digest drill-down UI; (conditional) latent chat-insert omission.

---

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm `## Domain Assessments`).

### Engineering (CTO) — carried forward
**Status:** reviewed (brainstorm). **Assessment:** `messages` is the deliberate draft-card home (ADR-037). `role IN (...)` blocks naive column-setting (mitigated: null role passes CHECK). Hot-table NOT-NULL relaxation needs a reader blast-radius sweep (→ TR2 / Phase 7 grep). ADR recommended (→ Follow-up).

### Product (CPO) — carried forward + Product/UX Gate
**Status:** reviewed (brainstorm). **Assessment:** Today consumer shipped (PR-H Phase 6) → a successful insert delivers operator value. Top risk: 7-item cap starvation → one digest card per run (FR4).
#### Product/UX Gate
**Tier:** advisory — modifies existing Today card content (newline-packed `draft_preview`) and adds a Dismiss affordance to `KbDriftCard` reusing `StripeCard`'s existing Discard pattern + the existing `/discard` route. **No new component, page, layout, or route file** → mechanical escalation does not fire. **Decision:** auto-accepted (advisory; backend-dominant; minimal, pattern-reusing UI). Per-finding drill-down deferred (Follow-up #3).
**Agents invoked:** spec-flow-analyzer (journey — surfaced the 422 dead-card + dismiss gap, folded in). **Skipped:** ux-design-lead (no new surface), copywriter (no persuasive copy). **Pencil:** N/A.

### Legal (CLO) — carried forward
**Status:** reviewed (brainstorm). **Assessment:** GATE on the cross-tenant-safe write (FR3); route `draft_preview` through redaction (FR5, now in-helper). No statutory clock; GDPR Art. 5(1)(f)/32 hygiene.

---

## GDPR / Compliance Gate (Phase 2.7)

Regulated surfaces: a DB migration (`.sql`), an internal API route, a workspace-scoped write, a
redaction transform → gate fires. Run `/soleur:gdpr-gate` on the diff at `/work`. Pre-assessed
(advisory): the data is **operator-internal infra signal** (broken doc links), not customer
personal data; incidental token/email in a broken URL → mitigated by FR5 (in-helper redaction).
Cross-tenant control is FR3. No new customer-data processing activity; no Art. 30 entry
(operator-self-scoped). Any Critical finding → operator-ack write to `compliance-posture.md` +
`compliance/critical` issue.

---

## Infrastructure (IaC) — N/A

No new infrastructure (no server, systemd unit, secret, vendor account, DNS, persistent process).
The walker workflow, HMAC signing key, and `KB_DRIFT_OPERATOR_FOUNDER_ID` already exist (PRs
#4570/#4571/#4572). The only deploy action is the DB migration, applied by the existing
`web-platform-release.yml#migrate` job on merge (`run-migrations.sh`, no operator SSH). IaC gate
skipped (pure code + migration against an already-provisioned surface).

---

## Observability (Phase 2.9 / TR3)

```yaml
liveness_signal:
  what: nightly KB-drift walker run concludes success (signed POST → 2xx); a digest persist failure = zero operator visibility that night → cron conclusion is the authoritative blind-night signal
  cadence: daily cron 0 3 * * * (+ workflow_dispatch)
  alert_target: GitHub Actions run conclusion != success; Sentry events for in-route failures
  configured_in: .github/workflows/kb-drift-walker.yml
error_reporting:
  destination: Sentry (tags feature:"kb-drift-ingest"/"insert-draft-card", op:"secret|signature|operator-id|persist|dedup-skip") + pino → Better Stack
  fail_loud: route returns 500 on persist failure; non-2xx fails the cron run; tenant-mint RuntimeAuthError → 500
failure_modes:
  - { mode: HMAC mismatch, detection: Sentry op:"signature", alert_route: Sentry }
  - { mode: signing key unset, detection: Sentry op:"secret", alert_route: Sentry }
  - { mode: operator id unset, detection: Sentry op:"operator-id", alert_route: Sentry }
  - { mode: NOT NULL/CHECK(23514)/RLS reject on insert, detection: Sentry op:"persist" (in helper), alert_route: Sentry }
  - { mode: idempotent dedup skip, detection: Sentry op:"dedup-skip" (NEW — was silent), alert_route: Sentry info }
  - { mode: tenant JWT mint failure, detection: RuntimeAuthError → 500 + Sentry, alert_route: Sentry }
logs:
  where: pino structured logs (Better Stack) + Sentry; success path logs workspace_id, finding_count, deduped
  retention: per existing Better Stack / Sentry retention
discoverability_test:
  command: gh run list --workflow "KB-drift walker" --limit 1 --json conclusion --jq '.[0].conclusion'
  expected_output: success
```

---

## Risks & Sharp Edges

- **The schema paradox is the #1 risk.** Phase 0.1 must run first. If prod = migration files, the siblings are latently broken (helper fixes them, in scope) and chat is a separate latent bug (→ follow-up). If prod ≠ migration files, **pause and re-confirm the 082 shape** before adding the CHECK (DHH caveat).
- **`NOT VALID`/`VALIDATE` defers no lock here** (single-transaction runner) — kept cosmetic/forward-portable; safe because Phase 0.2 = 0 violators.
- **Down migration is destructive** (re-adding NOT NULL fails if draft rows exist) — manual-rollback-only; the runner never auto-applies `*.down.sql`.
- **Partial-index dedup:** plain `.insert()` + catch `23505` only; **never** `.upsert()`/`on_conflict` (→ 42P10). Digest `source_ref` must be non-null. Dismissed rows are archived → leave the partial-on-draft index → recurrence re-inserts (Phase 0.5 confirms; Phase 7 test 5 proves).
- **Server-bundle leak:** import the tenant client from `@/lib/supabase/tenant` (Next-free), never `@/lib/supabase/server`.
- **Operator membership precondition:** FR3 RLS passes only if `KB_DRIFT_OPERATOR_FOUNDER_ID` has a `workspace_members(self,self)` row (Phase 0.3) and the minted JWT is `role=authenticated`.
- **cfo `action_class` fallback** must be resolved at the call site (`payload.action_class ?? "finance.payment_failed"`); the helper omits a falsy `action_class` → a raw-null pass would 422 the live CFO card.
- **`action_class` not pre-validated** in the helper — `payment.*`/`legal.*`/`auth.*` would hit `messages_action_class_not_locked` (23514, surfaced loudly, not swallowed as dedup).
- **`Ref #N` not `Closes #N`** for the deferred-upstream follow-up.
- **Constraint coexistence:** `messages_row_kind_chk` is additive to `messages_status_check` / `messages_external_tier_status_check` / `messages_template_id_check` / `messages_action_class_not_locked`.

---

## Non-Goals

- Wiring the stubbed **upstream** of `github-on-event` / `cfo-on-payment-failed` (their leader-loop; deferred to PR-G). *(Their draft-card insert path IS fixed here via the helper.)*
- A dedicated `draft_action_cards` table (rejected by ADR-037).
- A singleton "Knowledge drift" conversation (Option A, rejected in brainstorm).
- Per-finding drill-down / individual dismissal for the digest card (deferred follow-up).
- An operator-facing "last drift check: clean" liveness surface for empty/clean runs (silence is UI-only; cron conclusion is the engineer-facing signal — acceptable at this threshold; tracked follow-up if desired).
- Relaxing `template_id`/`workspace_id` NOT NULL (Decision A keeps them).
- Reworking Today queue ranking / per-source caps.

## Follow-up (file as issues during `/work`, `Ref` from this PR)

1. **ADR** via `/soleur:architecture create`: canonical draft-card home = `messages`; 082 finishes the mig-046 intent (amends the de-facto ADR-035/037 contract).
2. **Sibling upstream wiring** for `github-on-event` / `cfo-on-payment-failed` leader-loop (PR-G).
3. **Digest drill-down UI** — structured findings payload + per-finding dismissal on `KbDriftCard`.
4. **(conditional, from Phase 0.1)** Latent chat-insert `workspace_id`/`template_id` omission — only if prod schema confirms the columns are NOT-NULL-no-default and chat nonetheless inserts.

---

## Sharp Edge (deepen-plan / ship gates)

`## User-Brand Impact` is filled (carried from brainstorm) → passes `deepen-plan` Phase 4.6 +
preflight Check 6. At `single-user incident` threshold the exit gate recommends
`/soleur:deepen-plan` (data-integrity-guardian + security-sentinel + architecture-strategist)
before `/work` — these catch SQL-atomicity / RLS / migration-safety substance that plan-review
(DHH/Kieran/Simplicity) is structurally blind to.
