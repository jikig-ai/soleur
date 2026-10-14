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
status: deepened
---

# Plan: Map KB-drift findings onto the workspace-scoped `messages` model

🐛 **fix** · cross-domain · brand-survival threshold = **single-user incident** (CPO sign-off required before `/work`)

## Enhancement Summary

**Deepened on:** 2026-05-29 · **Reviews:** 4-agent plan-review (spec-flow + DHH + Kieran + simplicity) → 6-agent deepen pass (data-integrity-guardian, data-migration-expert, security-sentinel, identity-rbac-reviewer, architecture-strategist, git-history-analyzer).

**Decisive changes from the deepen pass:**
1. **Cross-tenant fix corrected (P0, 2 agents converged).** `resolveCurrentWorkspaceId` carries *current-selection* semantics → a multi-membership operator could cross-post the digest into a team workspace, and `is_workspace_member` RLS passes **by design** (the operator IS a member). **Pin operator-internal writes to the solo workspace** (`workspace_id = founderId`, ADR-038 N2) — RLS is no longer the sole guard.
2. **GDPR-erasure safety (P0).** The discriminator card-branch's `user_id IS NOT NULL` clause would make a future anonymization (`user_id → NULL` on a draft card) satisfy *neither* branch → `23514` aborts Right-to-Erasure. Card branch now anchors on `source + owning_domain + draft_preview` (drops `user_id`).
3. **Redaction gap closed (HIGH).** `redactGithubSourcedText` does **not** strip signed-URL query strings (`?X-Amz-Signature=`, `?token=`) — the exact "token in broken-target URL" vector the plan names. Strip URL query strings from each finding `target` before packing.
4. **Migration idempotency (P1).** Added `DROP CONSTRAINT IF EXISTS` + `COMMENT ON CONSTRAINT` (codebase convention `046:264`, `053:67`); guarded the destructive down for all-or-nothing rollback.
5. **Helper hardening:** narrow `source`/`owning_domain` to the `MESSAGE_*` const unions; full-length sha256 `source_ref` (no 16-char truncation → no birthday-collision masking); `source_ref`-must-be-structured invariant.
6. **Factual corrections:** `#4571` is a Flagsmith fix, not KB-drift (cite `#4570`/`#4572`); cite ADR by **filename** (the ADR-037 file's frontmatter `adr: 035` is stale; follow-up ADR must pick next free integer by enumerating filenames); cfo keeps `external_brand_critical` tier + resolved `action_class`.

**New considerations discovered:** anonymization-cascade vs CHECK interaction; signed-URL redaction bypass; `current_workspace_id` selection-vs-identity semantics; migration-collision lexical-order hazard (triple-`053` precedent).

---

## Overview

The nightly **KB-drift walker** (`.github/workflows/kb-drift-walker.yml`, cron `0 3 * * *`)
HMAC-signs its findings and POSTs them to `/api/internal/kb-drift-ingest`, which tries to
persist each finding as a "draft action card" row in `messages`. **The insert has never once
succeeded.** `messages` requires (NOT NULL, no default, no trigger — verified) `conversation_id,
role, content, template_id, workspace_id`; the draft-card insert (`route.ts:137`) supplies none of
`conversation_id/role/content/template_id`, and migration 059 rewrote the RLS so a `user_id`-only
insert has no matching policy.

**Not a kb-drift-only bug.** The two sibling producers (`github-on-event:237`, `cfo-on-payment-failed:229`)
insert the *same* shape and *also* omit `workspace_id`+`template_id` (verified) → they have likewise
never persisted (upstreams stubbed → latent). cfo additionally swallows its insert error (no
`{ error }` destructure). One shared helper + one schema relaxation fixes all three.

Six parts:

1. **Schema relaxation (migration 082).** `DROP NOT NULL` on `conversation_id, role, content` +
   a discriminator `CHECK messages_row_kind_chk` (chat row **or** draft-card row). `template_id`/
   `workspace_id` stay NOT NULL (Decision A).
2. **Shared `insertDraftCard` helper** (`server/messages/insert-draft-card.ts`): pins `workspace_id`,
   supplies `template_id='default_legacy'`, redacts `draft_preview`, tenant-client insert, `23505`→skip.
3. **Solo-pinned, cross-tenant-safe write.** kb-drift switches `createServiceClient()` →
   `getFreshTenantClient(operatorFounderId)` with `workspace_id = operatorFounderId` (the operator's
   **solo** workspace, ADR-038 N2 — **not** the session-selected workspace).
4. **All three producers adopt the helper** — closing the latent NOT-NULL/RLS failure (+ cfo's silent swallow).
5. **One digest card per run**, packed into `draft_preview`, dedup-keyed on a full sha256 content hash.
6. **Working operator-action path:** valid `action_class` + a Dismiss affordance (existing
   `/today/[id]/discard` route); no spawn button for digests. Per-finding drill-down deferred.

Honors ADR-037 (no per-source table; `messages` stays canonical) and finishes the intent migration
046 documented but never completed ("route via `user_id` — no `conversation_id` required").

---

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Codebase reality (grounded) | Plan response |
|---|---|---|
| "chat works in prod; only the draft-card inserts fail" | chat (`agent-runner:447,2425`, `cc-dispatcher:1445`) **and** drafts (`github-on-event:237`, `cfo:229`) all omit `workspace_id`+`template_id`; both NOT NULL (`059:94`,`053:65`), no default, **no trigger** (verified: 0 `CREATE TRIGGER … messages`). | **Phase 0 live-prod gate is hard.** If prod = migration files, siblings are latently broken (helper fixes them, in scope) + chat is a separate latent bug (→ follow-up). If prod ≠ files, **pause** before adding the CHECK. |
| FR3: `workspace_id = resolveCurrentWorkspaceId(operatorFounderId)` | **`resolveCurrentWorkspaceId` returns the session-SELECTED workspace** (`user_session_state.current_workspace_id`, `workspace-resolver.ts:121`), set by `set_current_workspace_id` to **any workspace the operator is a member of** (`079:256`). A multi-membership operator with a stale selection → digest lands in a **team** workspace; `is_workspace_member` RLS **passes** (legit member). | **Corrected (P0):** pin `workspace_id = operatorFounderId` (the solo workspace, ADR-038 N2 `workspaces.id = owner_user_id`). Do **not** use selection semantics for an identity-attributed headless write. RLS is defense-in-depth, **not** the cross-tenant guard. |
| spec FR1: relax `template_id` NOT NULL too | shape CHECK `^[a-z][a-z0-9_]*$` (`053:71`); send route nullish-coalesces null→`default_legacy` (`today/[id]/send/route.ts:186`). Cards ack-only. | **Decision A (amends FR1):** keep `template_id` NOT NULL; helper supplies `'default_legacy'`. 3 cols relaxed, not 4. |
| "NOT VALID then VALIDATE defers the lock" | `run-migrations.sh:335` uses `psql --single-transaction` — both statements run in **one** AccessExclusive-holding txn. The split defers no lock **and** there is **no concurrent-write window** (the txn holds the lock throughout). | Restate: the split is forward-portable; safety comes from (a) the single-txn lock (no concurrent violator) + (b) Phase 0.2 (no pre-existing violator). |
| brainstorm: "RLS is the cross-tenant backstop" | `messages_workspace_member_insert` checks **membership**, not solo-ownership (`059:106`). It cannot block a write to a workspace the operator legitimately joined. | Identity-pinned solo `workspace_id` is the guard; RLS is the second layer. |
| route comment + brainstorm: dedup index "migration 051" | Index in **`052:51`**: partial-on-draft `WHERE status='draft' AND source_ref IS NOT NULL`. Archived (dismissed) rows leave the index → recurrence re-inserts (no stale-digest blind spot). | Fix stale `route.ts:12` comment. Phase 0.5 confirms predicate; Phase 7.5 proves dismiss-then-recur. |
| brainstorm "ADR-035/037" | dedup ADR = **filename** `ADR-037-messages-source-ref-composite-unique…` (its frontmatter `adr: 035` is **stale** — repo has two "035"s + an ADR-038 collision). `ADR-035` filename = template-registry. | **Cite by filename.** Follow-up ADR must pick next free integer by enumerating **filenames** (not frontmatter), and fix ADR-037's stale frontmatter as a drive-by. |
| spec: "three inserters share identical shape" | **Not identical.** kb-drift+github carry `source_ref`; cfo does not (adds `action_class`, tier `external_brand_critical`). github does **not** currently set `action_class` (verified). cfo `:229` **does not destructure `{ error }`** (silent swallow). | Helper makes `source_ref`/`action_class` optional; cfo refactor closes the swallow + keeps `external_brand_critical`. |
| FR5: redact via shared helper | `redactGithubSourcedText` strips known credential shapes only — **not** signed-URL query strings (`?X-Amz-Signature=`, `?token=`, `?sig=`); `_opts` unused (source-agnostic). | **Redact in-helper** + **strip URL query strings from each `target`** before packing (the named token-in-URL vector). Drop the cosmetic `RedactionSource` enum edit. |
| (new) digest card actionable | `action_class` null → send route 422s; `KbDriftCard` no Dismiss button. `knowledge.kb_drift` valid (`action-class-map.ts:36`). `/discard` is action_class-agnostic (archives). | Set `action_class='knowledge.kb_drift'`; Dismiss → `/discard` for digests; no spawn button (Phase 7 regression test). |
| IaC precondition: "PRs #4570/#4571/#4572" | **#4571 is a Flagsmith fix**, not KB-drift. #4572 provisioned signing key + operator founder id; #4570 routed ingest POST. | Cite **#4570/#4572**; drop #4571. |

---

## User-Brand Impact

*(Carried from brainstorm; threshold drives `requires_cpo_signoff: true`.)*

- **If this lands broken, the operator experiences:** the nightly walker keeps failing
  (`500 Persist failed`); drift never reaches the Today queue — operator blind to broken docs.
  (A card that lands but 422s on click and can't be dismissed is the same blindness downstream.)
- **If this leaks, the data exposed is:** an operator-internal infra draft in a **paying tenant's**
  Today queue. **Two vectors:** (a) the old `createServiceClient()` write bypasses RLS entirely;
  (b) `resolveCurrentWorkspaceId` could route to a *team* workspace the operator legitimately
  joined (RLS passes by membership). `draft_preview` could carry a token in a broken-target URL.
- **Brand-survival threshold:** `single-user incident` — GDPR Art. 5(1)(f) + Art. 32; no statutory clock unless a leak occurs.
- **Decisive controls:** **solo-pinned `workspace_id = operatorFounderId`** (closes vector b; RLS is the second layer, not the only one); tenant-client write (closes vector a); `workspace_id` never request-derived (no IDOR); **URL-query-stripping + in-helper redaction** of `draft_preview`. `user-impact-reviewer` must verify the solo-pin + redaction at PR review.

---

## Research Insights (grounded, path:line)

- **kb-drift route** `app/api/internal/kb-drift-ingest/route.ts` — insert `:137` (per-finding loop `:136-164`); `createServiceClient()` `:132`; operator id `:122`; Sentry `op:"persist"` `:157`; **silent dedup** `:149-151`; auth/cap block `:82-104` (HMAC + 1 MiB — untouched by the refactor); stale "051" comment `:12`.
- **Siblings:** `github-on-event.ts:237` (tenant client + `redactGithubSourcedText`; no `action_class`; omits `workspace_id`/`template_id`); `cfo-on-payment-failed.ts:229` (stub preview, no `source_ref`, tier `external_brand_critical` `:226`, has `action_class`, **no `{ error }` destructure**).
- **Write primitives:** `getFreshTenantClient(userId): Promise<SupabaseClient>` async, Next-free (`lib/supabase/tenant.ts:736`; mints `role=authenticated, sub=founderId` via OTP hook `060:147`); `resolveCurrentWorkspaceId(userId, supabase)` = **selection semantics** (`workspace-resolver.ts:94-122`); `set_current_workspace_id` writer (`079:256`); `createServiceClient()` `@deprecated`, RLS-bypass (`service.ts:155`).
- **Schema:** base `001:67-76`; draft cols nullable `046:92-99` + `messages_status_check` + `messages_external_tier_status_check` `046:267`; `template_id` NOT NULL + shape CHECK `053:65,71`; `workspace_id` NOT NULL + RLS rewrite `059:94,99-122`; `messages_action_class_not_locked` (`!~ '^(payment|legal|auth)\.'`) `051:81`; dedup index `052:51`; **anonymization nulls `messages.user_id`** `068:206-217`; `user_id IS NULL` is steady-state `071`.
- **RLS substrate:** `is_workspace_member` plpgsql SECURITY DEFINER `SET search_path=public,pg_temp`, `GRANT EXECUTE TO authenticated` (`053_organizations_and_workspace_members.sql:116,140`); INSERT policy `FOR INSERT TO authenticated WITH CHECK is_workspace_member(workspace_id, auth.uid())` (`059:106`); solo `workspaces.id = owner_user_id` + backfilled `workspace_members(id,id,'owner')` (`053…:182,253-259`).
- **Migration runner** `run-migrations.sh` — `psql --single-transaction` `:335`; skips `*.down.sql` `:175`; collision = `::warning::` only `:143`, lexical-order apply (triple-`053` precedent); idempotency convention `DROP CONSTRAINT IF EXISTS` before `ADD` (`046:264`, `053:67`); `COMMENT ON CONSTRAINT` convention (`046:121`); DROP-NOT-NULL precedent `072:44`; destructive-down precedent `072.down:39`; `_chk` discriminator precedent `032:59`. Next free = **082** (max is 081).
- **Today consumer** `dashboard/today/route.ts:123` — selects `id, source, source_ref, owning_domain, draft_preview, urgency, created_at`; filters `.eq("user_id").in("tier",…).eq("status","draft")`; cap `TODAY_ITEM_CAP=7`; never reads role/content/conversation_id.
- **Chat render** `api-messages.ts:130-140` — conversation-scoped; never sees draft rows.
- **Today card UI** `today-card.tsx` — `draftPreview: string`; `KbDriftCard` `whitespace-pre-line` `:151`; only `StripeCard` has Discard `:347`. `/discard` route archives (action_class-agnostic) `:35`.
- **Action class** `action-class-map.ts:36` — `knowledge.kb_drift` valid (tier `draft_one_click` `:93`).
- **Constants** `lib/messages/tiers.ts` — `MESSAGE_TIER_EXTERNAL_LOW_STAKES`/`_BRAND_CRITICAL`, `MESSAGE_STATUS_DRAFT`, `MESSAGE_SOURCE_*`, `MESSAGE_OWNING_DOMAIN_KNOWLEDGE`; `PG_UNIQUE_VIOLATION` in `lib/postgres-errors`.
- **Learnings:** ADR-037 (plain insert + catch `23505`, never `ON CONFLICT`); `2026-05-03-postgrest-on-conflict-cannot-infer-partial-index`; `2026-04-18-supabase-migration-concurrently-forbidden`; `2026-04-17-migration-not-null-without-backfill-and-partial-unique-index-pattern`; `2026-03-20-supabase-silent-error-return-values`; `2026-04-18-server-bundle-transitive-next-headers-leak`; `2026-04-18-discriminated-union-widening-if-ladders-and-config-map-parity`; `security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments`; `security-issues/2026-04-18-rls-for-all-using-applies-to-writes`; `2026-05-10-plan-phase-order-load-bearing-when-contract-changes`.

---

## Open Code-Review Overlap

`#3220` + `#3221` mention `supabase/migrations` generically (CI verification infra; this migration adds no trigger) → **Acknowledge** both, not folded in. No overlap on the code files.

---

## Implementation Phases

> Phase order is load-bearing (migration → helper → route → siblings → UI). One atomic merge; sequential `/work`.

### Phase 0 — Live-prod precondition gate (BLOCKING; read-only)

`hr-no-dashboard-eyeball-pull-data-yourself`. *(Supabase MCP if authenticated, else `doppler run -c prd -- psql` per the migrations runbook.)*

- **0.1 Schema truth** — `SELECT column_name, is_nullable, column_default FROM information_schema.columns WHERE table_name='messages' AND column_name IN ('conversation_id','role','content','template_id','workspace_id')`. If prod ≠ migration files → **pause**, re-confirm the 082 shape. If prod = files → siblings are in-scope; chat omission = separate follow-up.
- **0.2 No discriminator violators** — `SELECT count(*) FROM messages WHERE NOT ((conversation_id IS NOT NULL AND role IS NOT NULL AND content IS NOT NULL) OR (source IS NOT NULL AND owning_domain IS NOT NULL AND draft_preview IS NOT NULL))` = 0.
- **0.3 Operator solo workspace** — `SELECT id=owner_user_id AS is_solo FROM workspaces WHERE id='<operatorFounderId>'` returns one row, `is_solo = t`, owned by the operator's own org; AND `EXISTS(SELECT 1 FROM workspace_members WHERE workspace_id='<operatorFounderId>' AND user_id='<operatorFounderId>')` = t (RLS membership). Pinning `workspace_id=founderId` requires this solo workspace to exist.
- **0.4 Sibling-row probe** — `SELECT source,count(*) FROM messages WHERE source IN ('github','stripe') AND status='draft' GROUP BY 1` (did any sibling draft ever land?).
- **0.5 Dedup predicate** — `SELECT indexdef FROM pg_indexes WHERE indexname='messages_active_draft_dedup_idx'` contains `WHERE status='draft' AND source_ref IS NOT NULL`.
- **0.6 Anonymization-safety probe** — `SELECT count(*) FROM messages WHERE user_id IS NULL AND conversation_id IS NULL` = 0 (proves no anonymized cardless rows exist pre-migration, so VALIDATE is safe under the user_id-free card branch).

### Phase 1 — Migration 082 (RED-first)

`082_relax_messages_draft_card_nullability.sql` (+`.down.sql`). **Collision guard:** at `/work` and at merge/rebase, assert `082` is the strict max: `ls migrations/ | grep -oE '^[0-9]+' | sort -n | tail -1` = `081` AND no `082_*.sql` exists (runner tolerates collisions with a `::warning::` and applies lexically — the triple-`053` precedent proves the hazard).

```sql
-- 082: relax messages NOT NULL for user_id-routed draft action cards.
-- Finishes the mig-046 intent ("route via user_id — no conversation_id required").
-- Honors ADR-037 (messages stays the canonical draft-card row).
-- run-migrations.sh uses psql --single-transaction: ADD ... NOT VALID and VALIDATE
-- run in ONE AccessExclusive-holding txn → no concurrent-write window, and the
-- split defers no lock (forward-portable only). Phase 0.2 guards pre-existing violators.
-- Card branch intentionally EXCLUDES user_id (anonymization sets user_id=NULL on
-- cards — 068) and workspace_id/template_id (kept column-NOT-NULL, Decision A).
-- Any future DROP NOT NULL on workspace_id/template_id MUST add them here.
ALTER TABLE public.messages ALTER COLUMN conversation_id DROP NOT NULL;
ALTER TABLE public.messages ALTER COLUMN role            DROP NOT NULL;
ALTER TABLE public.messages ALTER COLUMN content         DROP NOT NULL;

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_row_kind_chk;  -- idempotent (046:264 convention)
ALTER TABLE public.messages
  ADD CONSTRAINT messages_row_kind_chk CHECK (
    (conversation_id IS NOT NULL AND role IS NOT NULL AND content IS NOT NULL)   -- chat row
    OR
    (source IS NOT NULL AND owning_domain IS NOT NULL AND draft_preview IS NOT NULL)  -- draft card (user_id-free: erasure-safe)
  ) NOT VALID;
ALTER TABLE public.messages VALIDATE CONSTRAINT messages_row_kind_chk;

COMMENT ON CONSTRAINT messages_row_kind_chk ON public.messages IS
  'Discriminator: chat row (conversation_id+role+content) OR draft card '
  '(source+owning_domain+draft_preview). user_id excluded — anonymization (068) '
  'nulls it on cards. Migration 082, finishes mig-046 intent. See ADR-037 (filename).';
```
- `role CHECK (role IN ('user','assistant'))` passes when `role IS NULL` (SQL CHECK semantics) → no change.
- Coexists additively with `messages_status_check`, `messages_external_tier_status_check`, `messages_template_id_check`, `messages_action_class_not_locked` (verified non-contradicting).

`.down.sql` (manual-only; runner skips it; guarded for all-or-nothing rollback):
```sql
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.messages WHERE conversation_id IS NULL) THEN
    RAISE EXCEPTION 'cannot restore NOT NULL: % draft-card rows exist; purge/migrate first',
      (SELECT count(*) FROM public.messages WHERE conversation_id IS NULL);
  END IF;
END $$;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_row_kind_chk;
ALTER TABLE public.messages ALTER COLUMN content SET NOT NULL;
ALTER TABLE public.messages ALTER COLUMN role    SET NOT NULL;
ALTER TABLE public.messages ALTER COLUMN conversation_id SET NOT NULL;
```

### Phase 2 — Shared `insertDraftCard` helper (TDD: RED first)

New `apps/web-platform/server/messages/insert-draft-card.ts`. **File header MUST note:** "Reachable from the Inngest/WS server bundle — import the Supabase client only from `@/lib/supabase/tenant` (Next-free); never `@/lib/supabase/server` (`2026-04-18-server-bundle-transitive-next-headers-leak`)."

```ts
// source/owning_domain narrowed to the known unions (architecture P1-2): a typo'd
// literal would silently produce a row the Today `.in("tier",…)` filter drops.
export interface DraftCardInput {
  founderId: string;
  source: MessageSource;            // union of MESSAGE_SOURCE_* constants
  owning_domain: MessageOwningDomain;  // union of MESSAGE_OWNING_DOMAIN_* constants
  draft_preview: string;            // RAW — redacted inside the helper (FR5)
  tier: string;
  urgency: string;
  trust_tier: string;
  source_ref?: string;              // MUST be structured/hashed, NEVER raw upstream text (not redacted)
  action_class?: string;            // caller-set; helper does NOT pre-validate
}
export type DraftCardResult = { status: "inserted" | "deduped"; id?: string };

export async function insertDraftCard(input: DraftCardInput): Promise<DraftCardResult> {
  const tenant = await getFreshTenantClient(input.founderId);   // role=authenticated, sub=founderId
  // SOLO-PIN (P0): operator-internal cards target the operator's solo workspace
  // (ADR-038 N2: workspaces.id = owner_user_id). NOT resolveCurrentWorkspaceId —
  // that returns the session-SELECTED workspace, which RLS cannot distinguish from
  // a legitimate team membership → cross-post risk.
  const workspace_id = input.founderId;
  const id = randomUUID();
  const { error } = await tenant.from("messages").insert({
    id, user_id: input.founderId, workspace_id,
    template_id: "default_legacy",            // Decision A — ack-only card
    status: MESSAGE_STATUS_DRAFT,
    source: input.source,
    source_ref: input.source_ref ?? null,
    owning_domain: input.owning_domain,
    draft_preview: redactGithubSourcedText(input.draft_preview),   // FR5 choke point
    tier: input.tier, urgency: input.urgency, trust_tier: input.trust_tier,
    ...(input.action_class ? { action_class: input.action_class } : {}),
  });
  if (error) {
    if (error.code === PG_UNIQUE_VIOLATION) return { status: "deduped" };  // 23505
    Sentry.captureException(error, {              // 23514 (CHECK) + all else → loud
      tags: { feature: "insert-draft-card", op: "persist", source: input.source },
      extra: { founderId: input.founderId, workspace_id, source_ref: input.source_ref, code: error.code },
    });
    throw new Error(`insertDraftCard failed (${error.code}): ${error.message}`);
  }
  return { status: "inserted", id };
}
```
- Always destructure `{ error }`; `23505`→deduped, else Sentry + throw. Never `.upsert()`/`on_conflict` (→ 42P10).
- `action_class` not pre-validated — callers must not pass `payment.*`/`legal.*`/`auth.*` (→ `messages_action_class_not_locked` 23514, surfaced loudly).
- *(Future non-solo caller: add an explicit `workspaceIdOverride` param — never re-introduce selection semantics for an identity-attributed write.)*

### Phase 3 — kb-drift route adopts helper + digest (FR3, FR4, action_class)

Refactor `route.ts:132-171` (leave the auth/cap block `:82-104` untouched):
- Remove `createServiceClient()` import + call (sweep `.service-role-allowlist`).
- `if (payload.findings.length === 0)` → 200, no insert.
- Build **one** digest:
  - `source_ref = "digest-" + sha256(findings.map(f=>f.source_ref).sort().join("\n"))` — **full 64-hex** (no `.slice(16)`: avoids birthday-collision masking a distinct night's findings as a false dedup).
  - For each finding, **strip the URL query string** from `target` (`target.replace(/(\bhttps?:\/\/[^\s?]+)\?[^\s]*/gi, "$1")`) before composing — a broken doc link never needs its query string for triage, and this closes the signed-URL token vector the redaction allowlist misses.
  - `draft_preview = \`${N} KB-drift findings — review\n\` + findings.map(f => \`• ${f.kind==="broken-link"?"Broken link":"Broken anchor"} in ${f.source_path} → ${strippedTarget}\`).join("\n")` (in-helper `redactGithubSourcedText` is the second layer).
- One `await insertDraftCard({ founderId: operatorFounderId, source: MESSAGE_SOURCE_KB_DRIFT, source_ref, owning_domain: MESSAGE_OWNING_DOMAIN_KNOWLEDGE, draft_preview, tier: MESSAGE_TIER_EXTERNAL_LOW_STAKES, urgency: "low", trust_tier: "internal_infra_auto", action_class: "knowledge.kb_drift" })`.
- Map `deduped`→200 `{received:true,inserted:0,deduped:1,total:N}`; `inserted`→`inserted:1`.
- Fix `:12` "migration 051"→"052".

### Phase 4 — Sibling refactors (all three; FR2)

- **`github-on-event.ts`** → `insertDraftCard({...})` with its existing `source_ref`, tier `external_low_stakes`, redaction now in-helper (idempotent). Does not currently set `action_class` (verified) — omit. Upstream deferred.
- **`cfo-on-payment-failed.ts`** → `insertDraftCard({...})` with **`tier: MESSAGE_TIER_EXTERNAL_BRAND_CRITICAL`** (do not downgrade), `action_class: payload.action_class ?? "finance.payment_failed"` (**resolved at the call site** — a raw-null pass would 422 the live CFO card), no `source_ref`. The refactor **fixes cfo's silent-error swallow** (helper destructures + mirrors to Sentry). Upstream deferred. *(R2 note: the cfo leader-loop `step.run` awaits before persist; the TOCTOU between resolve and write is closed by the tenant-client RLS WITH CHECK, not by a sentinel — documented, accepted.)*

### Phase 5 — Digest card operator-action path (UI; ADVISORY)

`today-card.tsx` — `KbDriftCard`: detect a digest (`source_ref?.startsWith("digest-")`); render a Dismiss/Acknowledge button (reuse `StripeCard`'s pattern) → existing `POST /today/[id]/discard` (archives → drops from Today). **Do not render the per-finding spawn/"Fix link" button for digests** (enforced as a Phase 7 regression test). Per-finding drill-down deferred (Follow-up #3).

### Phase 6 — Observability (TR3)

- Sentry mirror on the dedup-skip path (`route.ts:149-151`, was silent) — `op:"dedup-skip"`, level info, **include `source_ref`** in `extra` (so a true vs false dedup is distinguishable).
- Structured success log: `workspace_id`, `finding_count=N`, `deduped`.
- **Atomicity note:** one digest row → a persist failure = zero operator visibility that night; the cron run conclusion (GitHub Actions) is the authoritative "blind night" signal. All failure paths Sentry/Better Stack reachable, no SSH.

### Phase 7 — Tests (RED→GREEN; `cq-write-failing-tests-before`, `cq-test-fixtures-synthesized-only`)

1. **Migration contract:** draft-card row (null `conversation_id/role/content`; `source/owning_domain/draft_preview` set; `tier=external_low_stakes`, `status=draft`) inserts + satisfies `messages_external_tier_status_check`; a `user_id=NULL` cardless row (anonymization sim) **still passes** the CHECK (erasure-safety); neither-branch row rejected; existing chat row still inserts.
2. **Helper unit:** inserted/`23505`-deduped/`23514`-throw+Sentry; `workspace_id === founderId` (solo-pin, **not** resolveCurrentWorkspaceId); `template_id='default_legacy'`; `draft_preview` redacted; `source`/`owning_domain` type-narrowed; brand-critical-tier case (cfo's tier passes `external_tier_status_check`).
3. **Cross-tenant + solo-pin (security/identity P0):** (a) foreign-`workspace_id` insert rejected by RLS; minted JWT `role=authenticated`,`sub=founderId`; **(b) with `user_session_state.current_workspace_id` set to a FOREIGN workspace the operator is also a member of, the helper still writes to the SOLO workspace (`= founderId`)** — proves the cross-post is closed (RLS alone would NOT catch this).
4. **Route digest:** N findings → one `insertDraftCard`; full-sha256 `source_ref`; re-POST identical → `deduped:1`; empty → no insert; row carries `action_class='knowledge.kb_drift'`.
5. **Dismiss-then-recur:** insert digest → archive via `/discard` → re-POST same findings → a **new** draft card inserts (archived row freed the partial-index slot).
6. **Redaction incl. URL-query vector:** a finding `target` of form `https://host/path?X-Amz-Signature=…&token=…` has its **query string stripped** in `draft_preview`; plus a token/email in `source_path` is scrubbed.
7. **Digest no-spawn regression:** a digest card (`source_ref` starts `digest-`) MUST NOT render a send-capable affordance (guards Phase 5 against future regression).

> **Write-boundary sweep (TR2)** = documented grep in the PR body (Today filters `user_id/tier/status`; chat render conversation-scoped). Not a test.

---

## Files to Edit

- `apps/web-platform/app/api/internal/kb-drift-ingest/route.ts` — helper, digest, URL-strip, `action_class`, dedup→200, Sentry dedup mirror, fix `:12`, drop service client; auth/cap block untouched.
- `apps/web-platform/server/inngest/functions/github-on-event.ts` — call `insertDraftCard`.
- `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` — call `insertDraftCard` (brand-critical tier; resolved `action_class`; fixes silent swallow).
- `apps/web-platform/components/dashboard/today-card.tsx` — `KbDriftCard` digest Dismiss.
- `apps/web-platform/.service-role-allowlist` — remove any kb-drift entry if present.

## Files to Create

- `apps/web-platform/supabase/migrations/082_relax_messages_draft_card_nullability.sql` (+ `.down.sql`)
- `apps/web-platform/server/messages/insert-draft-card.ts`
- `apps/web-platform/test/server/insert-draft-card.test.ts`
- `apps/web-platform/test/server/messages-draft-card-cross-tenant.integration.test.ts`
- `apps/web-platform/test/api/kb-drift-ingest.test.ts` (or extend existing)

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Migration 082 applies on a prod-shaped DB; `VALIDATE` succeeds (Phase 0.2/0.6 = 0); draft-card row (incl. `user_id=NULL` anonymization sim) inserts + satisfies `external_tier_status_check`; neither-branch row rejected; re-apply is idempotent (`DROP CONSTRAINT IF EXISTS`).
- [ ] Helper unit tests green: inserted/`23505`/`23514`; `workspace_id === founderId` (solo-pin); `template_id='default_legacy'`; redaction; type-narrowed source/owning_domain.
- [ ] Cross-tenant + solo-pin tests green: foreign-`workspace_id` rejected; JWT `role=authenticated`,`sub=founderId`; **stale `current_workspace_id` does not redirect the write off the solo workspace**.
- [ ] Route digest: one insert; full-sha256 `source_ref`; re-POST→`deduped:1`; empty→no insert; `action_class='knowledge.kb_drift'`.
- [ ] Dismiss-then-recur green; redaction incl. `?X-Amz-Signature=` query-strip green; digest no-spawn regression green.
- [ ] All three producers route through `insertDraftCard`; cfo keeps `external_brand_critical` + no longer swallows its error.
- [ ] `tsc --noEmit` + `vitest run` (touched packages) pass; no `createServiceClient` in kb-drift route.
- [ ] `/soleur:gdpr-gate` on the diff; no unresolved Critical (confirm redaction allowlist covers URL-query token shape).

### Post-merge (operator/CI — automatable; baked into ship/CI)

- [ ] `web-platform-release.yml#migrate` applies 082; `verify-migrations` green.
- [ ] `gh workflow run "KB-drift walker"` → `gh run list --workflow "KB-drift walker" --limit 1 --json conclusion --jq '.[0].conclusion'` = `success`.
- [ ] Digest row visible in the operator's Today queue, scoped to the operator's **solo** `workspace_id` (read-only prd query, not dashboard eyeballing).
- [ ] Operator can Dismiss the digest; dismissed card does not reappear.
- [ ] Re-run over unchanged KB → `deduped:1`, no dup.
- [ ] Follow-ups filed (`Ref #N`): ADR (next free integer by filename; fix ADR-037 stale frontmatter); sibling upstream wiring; digest drill-down UI; (conditional) latent chat-insert omission.

---

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried from brainstorm `## Domain Assessments`).

### Engineering (CTO) — carried forward
**Status:** reviewed. `messages` is the deliberate draft-card home (ADR-037). Hot-table NOT-NULL relaxation needs a reader blast-radius sweep (TR2/Phase 7). ADR recommended (Follow-up #1).

### Product (CPO) — carried forward + Product/UX Gate
**Status:** reviewed. Today consumer shipped → a successful insert delivers operator value. 7-cap starvation → one digest card (FR4).
#### Product/UX Gate
**Tier:** advisory — modifies existing Today card content + adds a Dismiss affordance reusing `StripeCard`'s pattern + existing `/discard` route. No new component/page/layout/route file. **Decision:** auto-accepted (backend-dominant; minimal pattern-reusing UI). Drill-down deferred (Follow-up #3).
**Agents invoked:** spec-flow-analyzer (surfaced the 422 dead-card + dismiss gap → folded in). **Skipped:** ux-design-lead, copywriter. **Pencil:** N/A.

### Legal (CLO) — carried forward
**Status:** reviewed. GATE on the cross-tenant-safe write (now solo-pinned + RLS); redaction (FR5, in-helper + URL-query strip). No statutory clock; GDPR Art. 5(1)(f)/32. **Erasure note:** the user_id-free card branch keeps Art. 17 anonymization unblocked.

---

## GDPR / Compliance Gate (Phase 2.7)

Regulated surfaces: migration (`.sql`), internal API route, workspace-scoped write, redaction. Run `/soleur:gdpr-gate` on the diff at `/work`; **confirm the redaction allowlist covers the URL-query token shape** (the named vector). Pre-assessed (advisory): operator-internal infra signal, not customer PII; incidental token in a broken URL → mitigated by URL-query strip + in-helper redaction; cross-tenant control = solo-pin. The user_id-free discriminator branch keeps Art. 17 erasure unblocked. No new customer-data processing; no Art. 30 entry. Critical → operator-ack write to `compliance-posture.md` + `compliance/critical` issue.

---

## Infrastructure (IaC) — N/A

No new infra. The walker workflow, HMAC signing key, and `KB_DRIFT_OPERATOR_FOUNDER_ID` already exist (**#4570** routed ingest POST; **#4572** provisioned signing key + operator founder id — note: #4571 is an unrelated Flagsmith fix). Only deploy action is the DB migration via `web-platform-release.yml#migrate` (`run-migrations.sh`, no operator SSH). IaC gate skipped.

---

## Observability (Phase 2.9 / TR3)

```yaml
liveness_signal:
  what: nightly KB-drift walker run concludes success (signed POST → 2xx); one-digest-row design means a persist failure = zero operator visibility that night → cron conclusion is the authoritative blind-night signal
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
  - { mode: NOT NULL/CHECK(23514)/RLS reject on insert, detection: Sentry op:"persist" (in helper, with code), alert_route: Sentry }
  - { mode: idempotent dedup skip, detection: Sentry op:"dedup-skip" (NEW, with source_ref), alert_route: Sentry info }
  - { mode: tenant JWT mint failure, detection: RuntimeAuthError → 500 + Sentry, alert_route: Sentry }
logs:
  where: pino structured logs (Better Stack) + Sentry; success path logs workspace_id, finding_count, deduped
  retention: per existing Better Stack / Sentry retention
discoverability_test:
  # Route-liveness + HMAC-gate probe — verifiable pre- AND post-merge, no SSH, no creds.
  # Proves the ingest surface is deployed and rejects unsigned POSTs. The deeper
  # "digest actually persists" signal is the post-merge AC (walker run concludes success).
  command: curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'x-soleur-kb-drift-signature: sha256=bad' --data '{}' --max-time 10 https://app.soleur.ai/api/internal/kb-drift-ingest
  expected_output: "401"
```

---

## Risks & Sharp Edges

- **Cross-tenant via selection semantics (P0, fixed):** never resolve the operator-internal write via `resolveCurrentWorkspaceId`; pin `workspace_id = operatorFounderId` (solo, ADR-038 N2). RLS membership is the second layer, not the guard. Phase 7.3(b) is the proof test.
- **Anonymization vs CHECK (P0, fixed):** card branch excludes `user_id` so `user_id → NULL` (Art. 17, `068`) keeps satisfying the discriminator. Phase 0.6 + Phase 7.1 verify.
- **Signed-URL token leak (HIGH, fixed):** `redactGithubSourcedText` does not strip `?X-Amz-Signature=`/`?token=` — strip the URL query string from `target` before packing. Phase 7.6 verifies.
- **Schema paradox:** Phase 0.1 first. If prod = files, siblings are in-scope + chat is a separate follow-up; if prod ≠ files, pause before the CHECK.
- **Migration idempotency:** `DROP CONSTRAINT IF EXISTS` before `ADD` (re-apply/drift-recovery → 42710 otherwise). Down is destructive + guarded (aborts before dropping the CHECK if draft rows exist).
- **`NOT VALID`/`VALIDATE`:** safe via single-txn lock (no concurrent violator) + Phase 0.2 (no pre-existing violator); split is forward-portable only.
- **Partial-index dedup:** plain `.insert()` + catch `23505`; never `.upsert()`/`on_conflict` (42P10). Full-sha256 `source_ref` (no truncation collision). Dismissed (archived) rows free the slot.
- **Server-bundle leak:** import tenant client from `@/lib/supabase/tenant` (Next-free); documented in the helper header.
- **`source_ref` not redacted:** must be structured/hashed, never raw upstream text (helper invariant + Phase 2 note).
- **cfo:** keep `external_brand_critical` tier; resolve `action_class` fallback at the call site (raw-null → 422 on the live CFO card). R2 TOCTOU closed by RLS WITH CHECK (documented).
- **ADR numbering:** cite by filename (ADR-037 frontmatter `adr: 035` is stale; ADR-035/038 collisions exist). Follow-up ADR picks next free integer by enumerating filenames + fixes the stale frontmatter.
- **`Ref #N` not `Closes #N`** for deferred-upstream follow-ups.

---

## Non-Goals

- Wiring the stubbed **upstream** of `github-on-event` / `cfo-on-payment-failed` (PR-G). *(Their insert path IS fixed here.)*
- A dedicated `draft_action_cards` table (ADR-037).
- A singleton "Knowledge drift" conversation (Option A, rejected).
- Per-finding drill-down / individual dismissal (deferred follow-up).
- An operator-facing "last drift check: clean" liveness surface for empty/clean runs (cron conclusion is the engineer-facing signal; tracked follow-up if desired).
- Relaxing `template_id`/`workspace_id` NOT NULL (Decision A).
- Reworking Today queue ranking / per-source caps.

## Follow-up (file during `/work`, `Ref` from this PR)

1. **ADR** via `/soleur:architecture create`: canonical draft-card home = `messages`; 082 finishes the mig-046 intent. Pick the next free integer by enumerating ADR **filenames** (not frontmatter — ADR-035/037/038 frontmatter is drifted); fix `ADR-037-*.md`'s stale `adr: 035` frontmatter as a drive-by. Consider an `AP-0NN` principles-register row for the messages-row-shape invariant.
2. **Sibling upstream wiring** for `github-on-event` / `cfo-on-payment-failed` leader-loop (PR-G).
3. **Digest drill-down UI** — structured findings column/payload. *(The packed `draft_preview` is NOT the drill-down data source — redaction + URL-strip are one-way; do not parse it back.)*
4. **(conditional, Phase 0.1)** Latent chat-insert `workspace_id`/`template_id` omission — only if prod schema confirms NOT-NULL-no-default and chat nonetheless inserts.

---

## Sharp Edge (deepen-plan / ship gates)

`## User-Brand Impact` filled (carried + corrected) → passes deepen Phase 4.6 + preflight Check 6. This plan has been through the deepen triad; the P0/HIGH findings (solo-pin, anonymization-safe CHECK, URL-query redaction) are folded in above.
