---
type: feature
date: 2026-05-17
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
parent_epic: "#3244"
parent_plan: knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md
parent_spec: knowledge-base/project/specs/feat-agent-runtime-platform/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-17-pr-f-inngest-trigger-layer-brainstorm.md
spec: knowledge-base/project/specs/feat-pr-f-inngest-trigger-layer/spec.md
branch: feat-pr-f-inngest-trigger-layer
worktree: .worktrees/feat-pr-f-inngest-trigger-layer
draft_pr: "#3940"
predecessor_prs:
  - "#3240"  # PR-A
  - "#3395"  # PR-B
  - "#3854"  # PR-C
  - "#3883"  # PR-D
  - "#3922"  # PR-E (issue #3887 closed by this PR; original session-start commit message was "(#3887) (#3922)")
follow_up_issues:
  - "#3947"  # PR-G cohort onboarding
  - "#3948"  # cron migration TR9
review_revision: v2
---

# Plan: PR-F Inngest Trigger Layer

## Overview

Execution plan for PR-F — the final increment of the Soleur Server-Side Agentic Runtime (umbrella #3244). Sits on the merged PR-A→E hardening (user-scoped JWT mint, BYOK lease + audit writer sweep, JWT deny-list, RLS attachments). Ships: Inngest substrate (self-hosted OSS server), Stripe `invoice.payment_failed` → CFO end-to-end, single-source `/dashboard` Today section, per-tenant cost kill-switch, ADR.

Parent plan `2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md` §3.1–3.5 is the design source of truth. This plan subsets that to PR-F's executable scope, resolves the 3 brainstorm open questions, and absorbs 2 Kieran P1 fixes + DHH/Simplicity convergent simplifications from plan-review v1.

**Brand-survival threshold:** `single-user incident`. CPO sign-off carried forward from brainstorm; `user-impact-reviewer` mandatory at PR review-time.

## Review-Driven Revisions (v1 → v2)

v1 was reviewed by DHH + Kieran + Code Simplicity. Operator approved "apply all" 2026-05-17. Material changes:

| # | Change | Source | Why |
|---|--------|--------|-----|
| RV1 | Kill-switch SQL rewritten as `LANGUAGE plpgsql` with leading `SELECT ... FROM users WHERE id = p_founder_id FOR UPDATE` | Kieran P1.1 + DHH | v1 CTE form had a TOCTOU race even with the snapshot fix — two concurrent calls at cap-boundary both passed the predicate. `FOR UPDATE` serializes per-founder. plpgsql is also more legible (DHH). |
| RV2 | Schema-version gate moved into a non-throwing `step.run("schema-gate")` returning `{deadletter: true}`; `retries: 1` retained for transient SDK/network only | Kieran P1.3 | Schema-version errors are deterministic; throwing under `retries: 1` wastes a BYOK turn. Gate-as-step keeps deadletter semantics honest. |
| RV3 | Schema-version constants + branch logic dropped from `event-schema.ts` (file deleted); `v: "1"` shipped as envelope-only field, no consumer gate beyond the schema-gate step above | DHH + Simplicity | v="1" is the only version at merge; routing logic for v=2 is YAGNI. Re-introduce consumer-first when v=2 ships per `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary`. |
| RV4 | `ACTION_CLASS_DEFAULTS` policy map + Phase 6 trust-tier scope dropped; inline `const TIER = "draft_one_click"` in CFO function | DHH + Simplicity | One consumer in PR-F → a policy map is a framework for an audience of one. Lift to a map in PR-G when a 2nd consumer arrives. Spec FR4 demoted to PR-G follow-up #3947. |
| RV5 | "Drafts everywhere, sends nowhere" promoted from ADR prose to a Postgres `CHECK` constraint on `messages` for `external_*` tiers | DHH | Code/DB-level invariant beats markdown for a load-bearing brand-survival guarantee. |
| RV6 | `server/inngest/functions/index.ts` registry dropped; one function inlined into `serve({ functions: [cfoOnPaymentFailed] })` in route.ts | Simplicity | Registry pattern is premature for one function. |
| RV7 | `server/stripe/minimize-payment-failed.ts` dropped; minimization is a local function in `route.ts` webhook case | Simplicity | ~10 LoC inline beats a sibling module. |
| RV8 | `server/dashboard/today-query.ts` dropped; today query is a local non-exported function in `route.ts` | Simplicity | `cq-nextjs-route-files-http-only-exports` bars exports, not local helpers. |
| RV9 | `RUNTIME_COST_CAP_CENTS_DEFAULT` env var dropped; SQL column default is single source of truth | Simplicity | Eliminates SQL-vs-Doppler drift surface. |
| RV10 | Phases collapsed: 2+3 → Phase 2 (Inngest substrate); 6+7 → Phase 5 (Today + inline tier); 8+9 → Phase 6 (legal + ADR flip + preflight + review) | DHH + Simplicity | 9 phases → 6 phases; same review surface, less ceremony. |
| RV11 | Test taxonomy 5 → 3 tiers (unit + integration + E2E); dedicated `pr-f-inngest-integration` CI job dropped | DHH + Simplicity | Single E2E flow; one integration tier covers both DB and Inngest dev-mode in the same job. |
| RV12 | ADR file numbered `ADR-030-inngest-as-durable-trigger-layer.md` (next sequential; ADR-029 is the highest existing) | Kieran P3.1 | Pre-pick avoids collision (per `2026-05-13-re-review-after-fix-catches-new-p1s-and-adr-number-collision`). |
| RV13 | Disclosure literal extracted to `apps/web-platform/lib/legal/disclosures.ts` named constant; component imports constant; AC checks rendered output via import | Kieran P2.3 | Magic-string gate decouples from code; legal-copy changes propagate. |
| RV14 | Disclosure surface moved from per-card to page-level banner above the Today section | Simplicity | One DOM node, same guarantee, less visual noise. |
| RV15 | Distinctness AC limited to `INNGEST_SIGNING_KEY` + `INNGEST_EVENT_KEY` (secrets); dropped for `INNGEST_BASE_URL` (URL pointer) and tuning scalars | Kieran P2.2/P3.3 | Distinctness is for secrets, not scalars or pointers. |
| RV16 | `runWithByokLease` dropped from the `persist-draft` step | Kieran P3.2 | Lease is for SDK calls; INSERT into `messages` under tenant client is sufficient. |
| RV17 | Verify-external-state retained per Kieran P1.2 framing; ADR records **single-pass-only invariant** (any Inngest retry path re-enters from `verify-stripe-state`, never from a checkpointed verify result) | Kieran P1.2 (operator over DHH on this disagreement) | Stale-after-verify is a real failure mode on 6h-deadlettered retries; ADR invariant + step ordering address it without re-verifying on every retry. |
| RV18 | `SOLEUR_FR5_ENABLED` env var retained | DHH (operator over Simplicity on this disagreement) | Dark-launch flag is useful for on-call wiring; named gate beats a "set INNGEST_EVENT_KEY=disabled" workaround. |
| RV19 | Two ceremony ACs dropped (`user-impact-reviewer sign-off captured` and `All P1/P2 findings resolved`) — moved to Phase 6 steps | Kieran P2.1 | Phase-output, not gate-output. The `user-impact-reviewer` invocation is a /soleur:review concern. |

## Research Reconciliation — Spec vs Codebase

Three drifts surfaced during plan-write v1 verification; all carried forward into v2 unchanged.

| # | Spec / Parent plan claim | Codebase reality | Plan response |
|---|--------------------------|------------------|---------------|
| RR1 | Parent plan §3.3 line 664: "Page is a server component already." | `apps/web-platform/app/(dashboard)/dashboard/page.tsx:1` is `"use client"` with 5+ client-only hooks. | New server route `/api/dashboard/today` (HTTP-handlers-only). Client `page.tsx` fetches via `useEffect`. |
| RR2 | Brainstorm K12: "self-hosted Inngest **dev server**". | Inngest dev server is local-development-only. The OSS production substrate is `inngest start` from `inngest-cli`. | PR-F deploys the OSS binary as a systemd-managed sidecar on Hetzner with **SQLite** state persistence; bound to `127.0.0.1` only. |
| RR3 | Parent plan §3.5 SQL: `agg` CTE SUMs in parallel with `ins` CTE INSERT, claiming atomic "INSERT-then-SUM". | PG CTE snapshot isolation: `agg` snapshot does NOT see the just-inserted row. **And** per Kieran P1.1: even with the snapshot-fix, two concurrent calls at cap-boundary race. | Phase 1 ships `LANGUAGE plpgsql` with leading `FOR UPDATE` lock on `public.users` + explicit `INSERT ... RETURNING ... INTO v_this_cents`. RR3 v2 supersedes the v1 CTE-only fix. |

## User-Brand Impact

**Threshold:** `single-user incident` (carry-forward from `[[brainstorm]]` and PR-A→E).

**If this lands broken, the user experiences:** Founder discovers a CFO-drafted customer email auto-sent overnight (wrong-action) OR sees their BYOK Anthropic key in Inngest logs (lease-escape leak) OR a paying customer's data surfaces in another founder's Today card (cross-tenant) OR a runaway Inngest loop burns $400 of Anthropic credit on a single Stripe event before the founder wakes (billing surprise).

**If this leaks, the user's data / workflow / money is exposed via:** Inngest server SQLite store + structured stdout logs, the `messages` table draft rows, the `audit_byok_use` cost log, or the Stripe webhook payload bridge. Self-hosted Inngest keeps every surface on the Hetzner host (no external sub-processor).

**Plan-time gates:**

- CPO sign-off captured at brainstorm Phase 0.5 triad. Plan inherits; `requires_cpo_signoff: true` in frontmatter.
- `user-impact-reviewer` invoked at PR review-time (handled by `/soleur:review` conditional-agent block).
- preflight Check 6 fires on the sensitive paths in `spec.md §User-Brand Impact`.
- `/soleur:gdpr-gate` invoked at this plan Phase 2.7 (regulated-data surfaces) and at `/work` Phase 2 exit.

## Open Question Resolutions

### Q1 — Stripe event source for the merge

**Stub-then-flip.** Tests use synthesized Stripe `invoice.payment_failed` event payloads (fixture JSON + `stripe.webhooks.generateTestHeaderString`). The merge ships with `SOLEUR_FR5_ENABLED=false` in both Doppler `dev` and `prd`. Post-merge operator step: set `=true` in `prd`, send a real Stripe `invoice.payment_failed` from operator's own Stripe TEST mode (not LIVE), observe the Today card appear within ~60s.

### Q2 — `/dashboard/page.tsx` client/server shape

**Keep `page.tsx` as a client component; add `/api/dashboard/today/route.ts`** (server-side data loader, HTTP-handlers-only). Client fetches via `useEffect` on mount. Reverses parent plan §3.3 line 664's no-new-route prescription — that prescription assumed server-side page, which is wrong (RR1).

### Q3 — Article 30 + DPD light amendment

**Ship in PR-F.** Add one paragraph to `knowledge-base/legal/article-30-register.md` and one bullet each to `docs/legal/data-protection-disclosure.md` + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (two copies per CLO finding). NO new sub-processor section (self-hosted Inngest avoids that cycle).

## Sharp Edges (PR-F-specific)

1. **Kill-switch TOCTOU race (RV1).** Two concurrent BYOK turns at cap-boundary will both pass the predicate unless the function takes a row-level lock on `public.users` BEFORE summing. Phase 1 ships plpgsql with `SELECT ... FOR UPDATE` as the first statement. Atomicity test runs 10 concurrent invocations summing to exactly `cap + 1 cent` and asserts EXACTLY one `kill_tripped=true`.
2. **Verify-external-state checkpoint staleness (RV17).** Inngest `step.run` memoizes results. On a 6h-deadlettered retry, the verify result is stale and Stripe state may have moved. **ADR-030 records the single-pass-only invariant**: any retry path MUST re-enter from `verify-stripe-state`, never from a checkpointed result. Implementation: CFO function does NOT split verify into a sub-step that other steps consume by reference; verify state lives in the function body and is recomputed on each pass.
3. **Schema-gate as non-throwing step (RV2).** Schema-version mismatches are deterministic. `step.run("schema-gate", ...)` returns `{deadletter: true}` and the function early-returns. Throwing under `retries: 1` would waste a BYOK turn.
4. **Drafts-everywhere CHECK constraint (RV5).** Phase 1 adds `ALTER TABLE public.messages ADD CONSTRAINT messages_external_tier_status_check CHECK (...)` enforcing `status IN ('draft', 'archived')` whenever `tier IN ('external_brand_critical', 'external_low_stakes')`. Future code attempting to INSERT `status='sent'` on an external-tier row is rejected at DB level.
5. **Inngest server ports must NOT be exposed externally.** Systemd unit pins `inngest start --host 127.0.0.1`. Phase 2 AC: `ss -tlnp | grep -E '8288|8289'` shows `127.0.0.1` only. Public binding is a forged-event attack surface.
6. **Inngest CLI install path.** `inngest-cli` is a Go binary distributed via GitHub Releases. Pinned to a specific release tag in the deploy pipeline / image build — NOT installed via npm.
7. **CEL concurrency key simplification.** `key: "event.data.founderId"` (single-path CEL). Function name already namespaces by event-name; the colon-suffix in parent plan §3.1 line 626 is redundant. Verified against Inngest docs (`/websites/inngest` 2026-05-17).
8. **Writer-sweep alias-rename bypass.** The regex `/\brunWithByokLease\s*\(/` at `byok-audit-writer-sweep.test.ts:73` is bypassed by `import { runWithByokLease as openLease } from ...`. Phase 2 extends the sentinel with `import\s*\{[^}]*\brunWithByokLease\s+as\b` detection. Negative-case fixture under `apps/web-platform/test/fixtures/inngest-bypass-alias-rename.ts.fixture` (`.fixture` extension keeps it out of glob) asserts the catch.
9. **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is populated; CPO sign-off carried forward.
10. **GH push-protection synthetic-token shape.** When prose includes Stripe-test-key-shaped strings, use `<<...>>` placeholder shape (e.g., `sk_test_<<24+ alnum chars, no underscores>>`), NEVER literal-alnum. Push-protection rejects regardless of context.

## Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | ALS context lost across `step.run` replay → BYOK lease escape thrown OR fallback to a global default key | HIGH | Open `runWithByokLease` INSIDE each `step.run` that calls the SDK (Phase 3). `byok-lease.ts:133–139` sync-escape check fails closed. |
| R2 | "Sends nowhere" invariant slips at a future code-edit | HIGH (single-user incident) | Phase 1 `messages_external_tier_status_check` CHECK constraint at DB level (RV5). Code-level edits cannot bypass. |
| R3 | Kill-switch races at cap-boundary → 2 concurrent calls both pass | HIGH | plpgsql + leading `FOR UPDATE` on `public.users` (RV1). Atomicity test verifies exactly-once trip under 10 concurrent calls. |
| R4 | Self-hosted Inngest server crashes/hangs; Stripe events queue | MEDIUM | systemd `Restart=always` + Node-side health probe (Phase 2). Stripe redelivery (up to 3 days) preserves at-least-once. Outbox pattern (TR9) deferred per parent plan + COO. |
| R5 | Verify-state checkpoint staleness on 6h retry | MEDIUM | ADR-030 single-pass-only invariant (RV17). Implementation: verify lives in function body, recomputed per pass. |
| R6 | Inngest CEL typo → ralph-loop pathology | MEDIUM | Phase 3 test: 5 synthetic events same founderId → exactly 1 runs, 4 blocked. CEL syntax verified vs Inngest docs. |
| R7 | Customer-email cleartext leaks into Inngest stdout | MEDIUM | Inline minimization in webhook (RV7): hashes `customer_email` BEFORE `inngest.send`. Unit test asserts `@` absent from `event.data.payload`. |
| R8 | Art. 22 line crossed by future capability extension (auto-send) | LOW (PR-F) / HIGH (future) | ADR records "drafts everywhere, sends nowhere" PLUS the DB CHECK constraint (RV5). Any future auto-send requires migration to widen the constraint — caught at review. |
| R9 | Inngest port bound to `0.0.0.0` by default → public attack surface | HIGH (if missed) | Systemd unit pins `--host 127.0.0.1`. Phase 2 AC: `ss -tlnp` verification. |
| R10 | Stripe retry past 24h: Inngest dedup-window gone, only DB index protects | LOW | `processed_stripe_events` unique index (migration 030) backstops past 24h. R-note: Stripe caps retries at 3 days, so 24-72h window relies on the DB index alone — acceptable. |

## Implementation Phases (6 phases, TDD-ordered, contract-before-consumer)

### Phase 0 — Preconditions, ADR (proposed), Doppler env vars

**Files to Create:**
- `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` — status `proposed` (flipped to `accepted` at Phase 6).

**Steps:**
1. Verify all 5 predecessor PRs MERGED via `gh pr view <N> --json state` for #3240, #3395, #3854, #3883, #3922. Abort if any OPEN. (Note: #3887 is the closed *issue* PR-E references; the merged PR is #3922 — caught at /work Phase 0.1 verification 2026-05-17.)
2. Verify worktree on `feat-pr-f-inngest-trigger-layer` branch at HEAD pushed to remote.
3. Run `/soleur:architecture create "Adopt Inngest as durable trigger layer for server-side agents"` with status `proposed`. ADR records:
   - **Chosen substrate:** self-hosted OSS Inngest server on Hetzner with SQLite persistence, bound to `127.0.0.1`.
   - **Rejected alternatives:** Inngest Cloud (sub-processor cycle conflicts with EU-only posture), LangGraph + custom (operationally heavy), Bedrock AgentCore (AWS lock + no EU residency parity), Cloudflare DO + LISTEN/NOTIFY (can't host Agent SDK long-running process).
   - **Re-evaluation criteria for Cloud:** concurrency-cap pressure OR third hosted founder onboarded.
   - **Load-bearing invariants:** (a) lease opened INSIDE each `step.run` that calls the SDK; (b) JWT minted INSIDE each `step.run` that touches tenant data; (c) singleton concurrency per founderId (`scope: "fn"`); (d) signature-verify required at startup; (e) **"drafts everywhere, sends nowhere" enforced by the `messages_external_tier_status_check` CHECK constraint AND by code**; (f) **verify-external-state is single-pass-only — any retry path re-enters from `verify-stripe-state`, never resumes from a checkpointed verify result**.
4. **Operations task (NOT code):** Doppler `dev` and `prd` configs receive:
   - `INNGEST_SIGNING_KEY` (generated `openssl rand -hex 32`, distinct per env)
   - `INNGEST_EVENT_KEY` (distinct per env)
   - `SOLEUR_FR5_ENABLED=false`
   - `MAX_TURN_DURATION_MS=90000`
   - `INNGEST_BASE_URL=http://127.0.0.1:8288`

**Phase 0 AC:**
- ADR file exists at `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` with `status: proposed`.
- All 5 predecessor PRs MERGED.
- 5 new env vars present in Doppler `dev` AND `prd`.
- **Distinctness:** `INNGEST_SIGNING_KEY` and `INNGEST_EVENT_KEY` differ between `dev` and `prd`. (`INNGEST_BASE_URL` and tuning scalars MAY match.)

### Phase 1 — Migration 046 (atomic plpgsql kill-switch + drafts-everywhere CHECK constraint)

**Files to Create:**
- `apps/web-platform/supabase/migrations/046_runtime_cost_state.sql`
- `apps/web-platform/test/server/migrations/046-runtime-cost-state.test.ts` — TENANT_INTEGRATION_TEST gated.

**Tests (RED first):**
- Schema assertions: `runtime_paused_at` + `runtime_cost_cap_cents` columns exist; `record_byok_use_and_check_cap` function exists.
- Function security shape: `SECURITY DEFINER`, `search_path = public, pg_temp`, revoked from anon/authenticated.
- **TOCTOU atomicity (RV1)**: 10 concurrent calls, each adding cents such that they collectively cross cap-boundary by 1 — exactly one returns `kill_tripped=true`. (Without `FOR UPDATE`, this test is flaky; with it, deterministic.)
- **Drafts-everywhere CHECK (RV5)**: INSERT into `messages` with `tier='external_brand_critical', status='sent'` fails with `ERRCODE=23514` (check_violation); INSERT with `status='draft'` succeeds.
- **Cumulative correctness**: invocation with `prior_cents=1950, this_cents=100, cap=2000` returns `cumulative_cents=2050, kill_tripped=true` (RR3 still works; the just-inserted row IS counted).

**Implementation:**
```sql
-- 046_runtime_cost_state.sql
-- PR-F (#3244, this slice).
--
-- RV1 (Kieran P1.1 / DHH): rewrote as LANGUAGE plpgsql with leading
-- SELECT ... FOR UPDATE on public.users to close the TOCTOU race
-- the v1 CTE form left open. Supersedes parent plan §3.5 SQL.
--
-- RV5 (DHH): adds messages_external_tier_status_check CHECK constraint
-- enforcing "drafts everywhere, sends nowhere" at the DB level for
-- external_* tiers.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp.
-- Per 2026-04-18-supabase-migration-concurrently-forbidden: no
-- CREATE INDEX CONCURRENTLY. Existing index
-- audit_byok_use_founder_ts_idx (founder_id, ts DESC) INCLUDE
-- (token_count, unit_cost_cents) from migration 037 covers the
-- 1-hour SUM hot path — no new index required.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS runtime_paused_at timestamptz,
  ADD COLUMN IF NOT EXISTS runtime_cost_cap_cents int NOT NULL DEFAULT 2000;

COMMENT ON COLUMN public.users.runtime_paused_at IS
  'Set by record_byok_use_and_check_cap when 1-hour cumulative > cap. '
  'NULL = active. Reset path lives outside PR-F. PR-F (#3244).';
COMMENT ON COLUMN public.users.runtime_cost_cap_cents IS
  'Per-tenant hourly cost cap in cents. Default 2000 = $20/hr per '
  'data-integrity P2-5 (200% headroom over realistic Sonnet 4.6 burn). PR-F (#3244).';

-- RV1: plpgsql with explicit FOR UPDATE lock per Kieran P1.1.
CREATE OR REPLACE FUNCTION public.record_byok_use_and_check_cap(
  p_invocation_id   uuid,
  p_founder_id      uuid,
  p_agent_role      text,
  p_token_count     int,
  p_unit_cost_cents int
) RETURNS TABLE(cumulative_cents int, kill_tripped boolean)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_cap        int;
  v_paused_at  timestamptz;
  v_this_cents int := p_token_count * p_unit_cost_cents;
  v_prior      int;
  v_total      int;
  v_tripped    boolean := false;
BEGIN
  -- RV1: serialize concurrent callers on the same founder row BEFORE
  -- the prior-hour SUM. Without this lock, two concurrent calls at
  -- cap-boundary both pass the predicate (snapshot isolation reads
  -- each one's pre-INSERT state).
  SELECT runtime_cost_cap_cents, runtime_paused_at
    INTO v_cap, v_paused_at
    FROM public.users
   WHERE id = p_founder_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'record_byok_use_and_check_cap: founder % not found', p_founder_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Append the audit row first (always — accounting is sacred).
  INSERT INTO public.audit_byok_use (
    invocation_id, founder_id, agent_role, token_count, unit_cost_cents
  ) VALUES (
    p_invocation_id, p_founder_id, p_agent_role, p_token_count, p_unit_cost_cents
  );

  -- Now sum prior-hour cents (the lock above ensures no concurrent
  -- INSERT can race between this SUM and the UPDATE below).
  SELECT COALESCE(SUM(token_count * unit_cost_cents), 0)::int
    INTO v_prior
    FROM public.audit_byok_use
   WHERE founder_id = p_founder_id
     AND ts > now() - interval '1 hour';

  -- v_prior already includes this just-inserted row (it's now committed
  -- to the transaction's local view, visible to subsequent reads in
  -- the same transaction).
  v_total := v_prior;

  IF v_paused_at IS NULL AND v_total > v_cap THEN
    UPDATE public.users
       SET runtime_paused_at = now()
     WHERE id = p_founder_id;
    v_tripped := true;
  END IF;

  cumulative_cents := v_total;
  kill_tripped     := v_tripped;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, text, int, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, text, int, int)
  TO service_role;

COMMENT ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, text, int, int) IS
  'Atomic per-founder kill-switch: row-locks public.users, appends '
  'audit row, SUMs 1-hour, flips runtime_paused_at on cap breach. '
  'Service-role-only. plpgsql + FOR UPDATE per Kieran P1.1. PR-F (#3244).';

-- RV5: "drafts everywhere, sends nowhere" at DB level for external_* tiers.
-- Future schema-widening to add status='sent' for these tiers MUST
-- DROP this constraint explicitly — caught at PR review.
ALTER TABLE public.messages
  ADD CONSTRAINT messages_external_tier_status_check
  CHECK (
    tier NOT IN ('external_brand_critical', 'external_low_stakes')
    OR status IN ('draft', 'archived')
  );

COMMENT ON CONSTRAINT messages_external_tier_status_check ON public.messages IS
  'PR-F (#3244) RV5: enforces "drafts everywhere, sends nowhere" for '
  'external_* tiers. Widening requires explicit DROP + replacement.';
```

**Phase 1 AC:**
- Migration applies cleanly on a fresh DB.
- All RED tests pass.
- 10-concurrent-caller atomicity test produces exactly one `kill_tripped=true`.
- INSERT with `tier='external_brand_critical', status='sent'` raises check_violation.

### Phase 2 — Inngest substrate (deps + client + serve route + writer-sweep alias extension)

**Files to Create:**
- `apps/web-platform/server/inngest/client.ts` — exports `inngest` client; throws at module load if required env vars missing.
- `apps/web-platform/app/api/inngest/route.ts` — exports `GET`/`POST`/`PUT` from `serve()`. NO non-HTTP exports (per `cq-nextjs-route-files-http-only-exports`).
- `apps/web-platform/test/server/inngest/client-startup.test.ts` — RED tests for env-var-missing throws.
- `apps/web-platform/test/server/inngest/signature-verify.test.ts` — RED tests for signature-verify-401.
- `apps/web-platform/test/fixtures/inngest-bypass-alias-rename.ts.fixture` — negative-case for writer-sweep extension.

**Files to Edit:**
- `apps/web-platform/package.json` — add `inngest@^3`.
- `apps/web-platform/bun.lock` + `apps/web-platform/package-lock.json` — regenerate (both lockfiles confirmed present 2026-05-17).
- `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts` — extend sentinel with `ALIAS_IMPORT_RE = /import\s*\{[^}]*\brunWithByokLease\s+as\s+\w+/`. New negative-case test asserts a file containing only the alias import IS classified as sweepable.

**Tests (RED first):**
- Module load with `INNGEST_SIGNING_KEY` or `INNGEST_EVENT_KEY` unset throws at startup.
- POST `/api/inngest` with invalid `x-inngest-signature` returns 401 BEFORE any function dispatches; `reportSilentFallback` mirrored to Sentry.
- POST with stale timestamp (>5 min) returns 401.
- Writer-sweep extension: alias-rename bypass fixture is classified as sweepable AND fails the `persistTurnCost`-or-marker assertion (proving the bypass would have been caught).

**Implementation skeleton:**
```ts
// apps/web-platform/server/inngest/client.ts
import { Inngest } from "inngest";

const SIGNING_KEY = process.env.INNGEST_SIGNING_KEY;
const EVENT_KEY = process.env.INNGEST_EVENT_KEY;
const BASE_URL = process.env.INNGEST_BASE_URL;

if (!SIGNING_KEY) throw new Error("INNGEST_SIGNING_KEY missing at startup");
if (!EVENT_KEY) throw new Error("INNGEST_EVENT_KEY missing at startup");
if (BASE_URL) try { new URL(BASE_URL); } catch { throw new Error(`INNGEST_BASE_URL malformed: ${BASE_URL}`); }

export const inngest = new Inngest({
  id: "soleur-runtime",
  eventKey: EVENT_KEY,
  ...(BASE_URL ? { baseUrl: BASE_URL } : {}),
});
```

```ts
// apps/web-platform/app/api/inngest/route.ts
import { serve } from "inngest/next";
import { inngest } from "@/server/inngest/client";
import { cfoOnPaymentFailed } from "@/server/inngest/functions/cfo-on-payment-failed";

const SIGNING_KEY = process.env.INNGEST_SIGNING_KEY;
if (!SIGNING_KEY) throw new Error("INNGEST_SIGNING_KEY missing at /api/inngest load");

// RV6: single-function inlined; no registry module for one consumer.
export const { GET, POST, PUT } = serve({
  client: inngest,
  functions: [cfoOnPaymentFailed],
  signingKey: SIGNING_KEY,
});
```

**Phase 2 AC:**
- Both lockfiles regenerated atomically.
- `/api/inngest` rejects invalid signatures with 401 before dispatch.
- Writer-sweep extended; alias-rename fixture caught.
- After deploy (Phase 0 ops task complete): `ss -tlnp | grep -E '8288|8289'` shows `127.0.0.1` only.

### Phase 3 — CFO function `cfo-on-payment-failed.ts` (per-step lease re-entry, schema-gate as non-throwing step, single-pass verify, AbortSignal)

**Files to Create:**
- `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` — the CFO function. Inlined `PaymentFailedPayload` type (RV3). Inlined `const TIER = "draft_one_click"` (RV4).
- `apps/web-platform/test/server/inngest/cfo-on-payment-failed.test.ts` — RED tests.

**Tests (RED first):**
- **Lease per step (R1)**: mock Inngest step boundary; assert lease opened INSIDE the SDK-calling step's body. Inject an outer-scope lease and assert `byok-lease.ts:133–139` sync-escape check throws if reused.
- **JWT mint per step**: `getFreshTenantClient(event.data.founderId)` called inside each tenant-touching step; never cached across boundaries.
- **Schema-gate as non-throwing step (RV2)**: `v: "2"` → step returns `{deadletter: true}`, function early-returns without retry; `v: "0"` → same; `v: "1"` → proceeds. NO BYOK turn consumed on schema mismatch.
- **Single-pass verify (RV17)**: simulate `step.sleep` between verify and draft, then a retry path that DOES NOT resume from `verify-stripe-state` (the verify must run again). Implementation forbids splitting verify into a stepped artifact that other steps consume by reference.
- **Verify timeout**: `stripe.charges.retrieve` times out at 2s → function does NOT draft; `reportSilentFallback` mirrored with `feature: "trust-tier-verify"`.
- **Verify mismatch**: live state `"succeeded"` after webhook said `"payment_failed"` → function does NOT draft; existing draft (if any) archived; new draft NOT re-queued (PR-F shipping shape — re-queue lives in PR-G).
- **Cost-gate**: `record_byok_use_and_check_cap` returns `kill_tripped=true` → function aborts at next `step.run` boundary; `runtime_paused_at` propagates.
- **CEL concurrency (R6)**: 5 events same `event.data.founderId` → exactly 1 executes, 4 blocked.

**Implementation skeleton:**
```ts
// apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts
import { inngest } from "@/server/inngest/client";
import { runWithByokLease } from "@/server/byok-lease";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { recordByokUseAndCheckCap } from "@/server/cost-writer";
import { getStripe } from "@/server/stripe/client";

// RV3: inlined payload type; reintroduce as discriminated-union when v=2 ships.
interface PaymentFailedPayload {
  founderId: string;
  invoiceId: string;
  customerEmailHash: string;
  amount: number;
  currency: string;
  failureCode: string;
}

// RV4: inlined tier constant; reintroduce ACTION_CLASS_DEFAULTS map in PR-G.
const TIER = "draft_one_click" as const;

const MAX_TURN_DURATION_MS = parseInt(process.env.MAX_TURN_DURATION_MS ?? "90000", 10);
const SUPPORTED_V = "1";

export const cfoOnPaymentFailed = inngest.createFunction(
  {
    id: "cfo-on-payment-failed",
    concurrency: [
      // CEL key simplification per Inngest docs /websites/inngest 2026-05-17.
      { scope: "fn", key: "event.data.founderId", limit: 1 },
      { scope: "account", key: '"agent-runtime"', limit: 50 },
    ],
    retries: 1, // RV2: applies to transient SDK/network errors only.
  },
  { event: "finance.payment_failed" },
  async ({ event, step, logger }) => {
    // RV2: schema-gate as NON-throwing step (deterministic; never retry).
    const v = (event as { v?: string }).v ?? "0";
    const gate = await step.run("schema-gate", async () => {
      if (v !== SUPPORTED_V) return { deadletter: true, reason: `schema_v=${v}` };
      return { deadletter: false };
    });
    if (gate.deadletter) {
      logger.warn({ v, reason: gate.reason }, "Schema-gate deadletter");
      return { deadlettered: true, reason: gate.reason };
    }

    const data = event.data as { founderId: string; payload: PaymentFailedPayload };
    const founderId = data.founderId;

    // RV17: verify happens INSIDE the function body, not as a step.run
    // whose result other steps consume by reference. Any Inngest retry
    // re-enters from the top and re-verifies. ADR-030 records this as
    // a load-bearing invariant.
    const stripe = getStripe();
    const verify = await Promise.race([
      stripe.charges.retrieve(data.payload.invoiceId).then((c) => ({ ok: true, state: c.status })),
      new Promise<{ ok: false; reason: string }>((res) => setTimeout(
        () => res({ ok: false, reason: "verify-timeout-2s" }), 2000)),
    ]);
    if (!verify.ok || verify.state === "succeeded") {
      // Block-and-alert; NO silent proceed (Kieran K3 contract).
      logger.warn({ founderId, verify }, "Stripe state verify failed — aborting");
      // reportSilentFallback fired by cq-silent-fallback-must-mirror-to-sentry
      return { drafted: false, reason: verify.ok ? `state=${verify.state}` : verify.reason };
    }

    // Draft inside a fresh lease scope (R1 load-bearing invariant).
    const draft = await step.run("draft-customer-response", async () => {
      return runWithByokLease(founderId, async (lease) => {
        const tenant = await getFreshTenantClient(founderId);
        const ac = new AbortController();
        const timer = setTimeout(() => ac.abort(), MAX_TURN_DURATION_MS);
        try {
          // ... CFO leader prompt + Anthropic SDK call with ac.signal ...
          // ... after each SDK turn: recordByokUseAndCheckCap(...) ...
          // ... if kill_tripped: throw to abort step (cooperatively) ...
          return { body: "<draft text>", tokenCount: 1234, unitCostCents: 30 };
        } finally {
          clearTimeout(timer);
        }
      });
    });

    // RV16: persist-draft does NOT need runWithByokLease (no SDK call).
    await step.run("persist-draft", async () => {
      const tenant = await getFreshTenantClient(founderId);
      await tenant.from("messages").insert({
        user_id: founderId,
        tier: "external_brand_critical",  // RV5: DB CHECK constraint enforces status='draft'.
        status: "draft",
        source: "stripe",
        owning_domain: "cfo",
        draft_preview: draft.body,
        urgency: "medium",
        trust_tier: TIER, // RV4: inlined.
      });
    });

    return { drafted: true };
  },
);
```

**Phase 3 AC:**
- All RED tests pass.
- Schema-gate as non-throwing step (no retry on schema mismatch).
- Verify is single-pass; not split into a checkpointed step.
- Lease opened INSIDE each SDK-calling step; sync-escape verifies.

### Phase 4 — Stripe webhook integration (inline `inngest.send` + inline minimization + `SOLEUR_FR5_ENABLED` gate)

**Files to Edit:**
- `apps/web-platform/app/api/webhooks/stripe/route.ts` — replace `invoice.payment_failed` no-op at lines 415–426 with inline minimization + gated `inngest.send`.

**Files to Create:**
- `apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts` — RED tests.

**Tests (RED first):**
- `SOLEUR_FR5_ENABLED=false`: webhook receives event, returns 200, NO `inngest.send`, existing log retained.
- `SOLEUR_FR5_ENABLED=true`: webhook fires `inngest.send` with envelope `{id: "stripe-<event.id>", name: "finance.payment_failed", v: "1", data}` AFTER `processed_stripe_events` dedup-insert.
- Stripe redelivery (same `event.id` twice): `inngest.send` fires ONCE.
- Minimization (RV7): `event.data.payload` has NO `@` character (email hashed), NO `payment_method`, retains `amount`/`currency`/`failure_code`/`invoice_id`.
- Inngest unreachable: `reportSilentFallback` fires; webhook returns 200 (Stripe redelivery handles retry).

**Implementation skeleton (edit at `route.ts:415–426`):**
```ts
case "invoice.payment_failed": {
  const invoice = event.data.object as Stripe.Invoice;
  const customerId = typeof invoice.customer === "string" ? invoice.customer : invoice.customer?.id;
  logger.warn(
    { customerId, invoiceId: invoice.id },
    "Stripe invoice.payment_failed — logged for observability",
  );

  // PR-F (#3244): emit Inngest event for autonomous CFO drafting if flag enabled.
  if (process.env.SOLEUR_FR5_ENABLED === "true") {
    const founderId = await resolveFounderIdFromCustomer(customerId);
    if (founderId) {
      // RV7: inlined minimization — hash email, drop payment_method, keep 4 fields.
      const customerEmailHash = invoice.customer_email
        ? createHash("sha256").update(invoice.customer_email).digest("hex")
        : "";
      const payload = {
        founderId,
        invoiceId: invoice.id,
        customerEmailHash,
        amount: invoice.amount_due ?? 0,
        currency: invoice.currency ?? "usd",
        failureCode: invoice.last_finalization_error?.code ?? "unknown",
      };
      try {
        await inngest.send({
          id: `stripe-${event.id}`,
          name: "finance.payment_failed",
          v: "1",
          data: { founderId, domain: "finance", event: "finance.payment_failed", payload },
        });
      } catch (err) {
        reportSilentFallback(err, {
          feature: "inngest-emit",
          op: "finance.payment_failed",
          message: "Inngest unreachable on invoice.payment_failed — CFO draft skipped",
        });
      }
    }
  }
  break;
}
```

**Phase 4 AC:**
- Stub-mode (`=false`) returns 200 with no emit.
- Flag-on emits exactly one event per Stripe `event.id`.
- Payload minimized; no `@` in `event.data.payload`.

### Phase 5 — `/api/dashboard/today` route + page banner + `today-card.tsx`

**Files to Create:**
- `apps/web-platform/app/api/dashboard/today/route.ts` — server-side data loader with inline (non-exported) `todayQuery` function (RV8).
- `apps/web-platform/components/dashboard/today-card.tsx` — single Today card client component.
- `apps/web-platform/components/dashboard/today-banner.tsx` — page-level disclosure banner (RV14).
- `apps/web-platform/lib/legal/disclosures.ts` — exports `RUNTIME_COST_DISCLOSURE` constant (RV13).
- `apps/web-platform/test/server/dashboard/today-route.test.ts` — RED tests.
- `apps/web-platform/test/components/today-banner.test.tsx` — RED tests for disclosure.

**Files to Edit:**
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — `useEffect` fetch `/api/dashboard/today` on mount; render `<TodayBanner />` once at the top, then `<TodayCard>` per row. Place ABOVE existing inbox + foundation sections.

**Tests (RED first):**
- `GET /api/dashboard/today` returns the caller's `external_brand_critical, status='draft'` messages only.
- RLS isolation: caller A's request never returns caller B's rows.
- Banner renders the imported `RUNTIME_COST_DISCLOSURE` constant (gate via import, not free literal).
- Card renders source / owning leader / draft preview / urgency / Send / Edit / Discard buttons.
- Empty state: `{ items: [] }` when no drafts.

**Phase 5 AC:**
- All RED tests pass.
- RLS isolation verified.
- Banner is rendered above the Today section; substring `disclaims warranty for runtime cost` matches the imported constant.

### Phase 6 — Article 30 + DPD light amendments + ADR flip + preflight + review

**Files to Edit:**
- `knowledge-base/legal/article-30-register.md` — one paragraph on the new processing activity.
- `docs/legal/data-protection-disclosure.md` — one bullet under existing processing-activities section.
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — mirror bullet (CLO finding 2).
- `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` — flip `status: proposed` → `status: accepted`.

**Steps:**
1. Apply legal amendments.
2. Flip ADR-030 to `accepted`.
3. Run `/soleur:preflight` — verifies migrations, security headers, lockfiles, sensitive-path gate (Check 6).
4. Run `/soleur:gdpr-gate` against the diff (cross-check Phase 2.7 gate is still satisfied).
5. Run `/soleur:qa` for functional verification.
6. Mark PR #3940 ready: `gh pr ready 3940`.
7. Invoke `/soleur:review` — multi-agent review including **mandatory `user-impact-reviewer`** (brand-survival single-user-incident threshold).
8. Address P1/P2 findings inline.
9. `gh pr merge --auto --squash 3940`.

**Phase 6 AC:**
- All 3 legal docs amended; sub-processor lists UNCHANGED.
- ADR-030 status flipped to `accepted`.
- preflight + gdpr-gate + qa all green.
- `user-impact-reviewer` summary visible in PR review thread.
- All P1/P2 multi-agent review findings resolved inline OR explicitly scoped-out with tracking issue.

## Test Strategy (3 tiers — RV11)

| Tier | Scope | Runner | Gate |
|------|-------|--------|------|
| Unit | Disclosure constant import, CEL key shape, minimization fn, schema-gate behavior, trust-tier constant resolution | vitest in `apps/web-platform` | `bun test` default |
| Integration | Migration 046 (schema + plpgsql atomicity + CHECK constraint), CFO function under Inngest dev-mode (lease per step, schema-gate, verify single-pass), Stripe webhook gate + dedup | vitest under `TENANT_INTEGRATION_TEST=1` + Inngest CLI dev-mode in same job | Existing CI tenant-isolation job (no new dedicated Inngest job) |
| E2E | Stripe synthesized webhook → Today card renders with banner disclosure | playwright | `apps/web-platform/test/e2e/` |

Sentinel sweep extension runs in the standard vitest suite.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `inngest@^3` added; both lockfiles (`bun.lock` + `package-lock.json`) regenerated.
- [x] `apps/web-platform/server/inngest/client.ts` throws at module load if `INNGEST_SIGNING_KEY` or `INNGEST_EVENT_KEY` missing.
- [x] `apps/web-platform/app/api/inngest/route.ts` rejects invalid signature with 401 BEFORE dispatch.
- [x] `cfo-on-payment-failed.ts` opens `runWithByokLease` INSIDE each SDK-calling `step.run`; schema-gate is a non-throwing step.
- [x] Stripe `invoice.payment_failed` branch at `route.ts:415` emits gated `inngest.send` AFTER `processed_stripe_events` dedup; minimized payload has no `@`, no `payment_method`.
- [x] `/api/dashboard/today` returns RLS-scoped draft messages.
- [x] Today banner renders disclosure via imported `RUNTIME_COST_DISCLOSURE` constant; substring `disclaims warranty for runtime cost` matches.
- [x] Migration 046: `record_byok_use_and_check_cap` uses plpgsql with `FOR UPDATE`; atomicity test (10 concurrent at cap-boundary) returns exactly one `kill_tripped=true`.
- [x] Migration 046: `messages_external_tier_status_check` rejects `tier='external_brand_critical', status='sent'`.
- [x] Writer-sweep test catches alias-rename bypass via the new `ALIAS_IMPORT_RE` regex.
- [x] Article 30 register + BOTH DPD copies amended; sub-processor list UNCHANGED.
- [x] ADR-030 file exists; status `accepted` at merge HEAD.
- [ ] `SOLEUR_FR5_ENABLED=false` in Doppler `prd` at merge time.
- [ ] Doppler `dev` AND `prd` contain `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY`, `SOLEUR_FR5_ENABLED`, `MAX_TURN_DURATION_MS`, `INNGEST_BASE_URL`. **Distinctness:** `dev.INNGEST_SIGNING_KEY ≠ prd.INNGEST_SIGNING_KEY` AND `dev.INNGEST_EVENT_KEY ≠ prd.INNGEST_EVENT_KEY` (RV15).

### Post-merge (operator)

- [ ] Install `inngest-cli` (pinned release tag) on Hetzner host AND configure systemd unit `inngest-server.service` running `inngest start --host 127.0.0.1 --event-key $INNGEST_EVENT_KEY --signing-key $INNGEST_SIGNING_KEY` with `Restart=always`. Verify `ss -tlnp | grep -E '8288|8289'` shows `127.0.0.1` only.
- [ ] Set `SOLEUR_FR5_ENABLED=true` in Doppler `prd` and restart Node app.
- [ ] Send synthesized Stripe `invoice.payment_failed` from operator's own Stripe TEST mode. Verify CFO Today card appears within ~60s; verify `audit_byok_use` row written.
- [ ] Wire Better Stack Incidents on-call (free tier) to alert on Inngest server outage AND `runtime_paused_at` flip events.
- [ ] Close follow-up only after all 4 post-merge steps verified.

`Ref #3244` (NOT `Closes` — umbrella stays open until cohort exposure via PR-G #3947).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO), Operations (COO). Carry-forward from brainstorm Phase 0.5.

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** Locks at brainstorm: self-hosted Inngest, ALS lease per `step.run`, ADR before code, sentinel sweep extension. v2 absorbs Kieran P1.1 + P1.3 corrections (plpgsql + `FOR UPDATE`; schema-gate as non-throwing step). DHH simplifications applied (inlined payload/registry/minimizer/query modules; phases collapsed 9→6; tests collapsed 5→3 tiers).

### Product (CPO)

**Status:** reviewed (carry-forward) — CPO sign-off REQUIRED per brand-survival threshold
**Assessment:** PR-F ships substrate + one E2E trigger + `/dashboard` Today list view (with page-banner disclosure). Alpha-internal-only; PR-G (#3947) gates cohort exposure. `user-impact-reviewer` mandatory at PR review.

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** Self-hosted Inngest avoids sub-processor disclosure cycle. Article 30 + BOTH DPD copies amended in Phase 6. "Drafts everywhere, sends nowhere" promoted from prose to a `CHECK` constraint (RV5) — DB-level enforcement now backs the ADR invariant.

### Operations (COO)

**Status:** reviewed (carry-forward)
**Assessment:** Zero crons migrate; #3948 tracks TR9 destination. `SOLEUR_FR5_ENABLED=false` default until on-call wires. Inngest server pinned to `127.0.0.1`; systemd `Restart=always`.

### Product/UX Gate

**Tier:** advisory (modifies existing `/dashboard`; new banner + card are single-purpose surfaces mirroring existing inbox affordances)
**Decision:** auto-accepted (pipeline; brainstorm captured CPO framing; banner placement is a Simplicity-reviewer-driven design choice)
**Agents invoked:** none beyond brainstorm carry-forward
**Skipped specialists:** ux-design-lead (CPO recommended visual treatment as a follow-up; list view ships in PR-F per parent plan §3.3 + brainstorm K9)
**Pencil available:** N/A

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped each planned-edit/create file path against issue bodies.

**Results:** None of the open code-review issues touch the files PR-F edits or creates.

**Verification:**
```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in \
  apps/web-platform/server/inngest/client.ts \
  apps/web-platform/app/api/inngest/route.ts \
  apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts \
  apps/web-platform/app/api/webhooks/stripe/route.ts \
  apps/web-platform/app/api/dashboard/today/route.ts \
  apps/web-platform/app/\(dashboard\)/dashboard/page.tsx \
  apps/web-platform/components/dashboard/today-banner.tsx \
  apps/web-platform/components/dashboard/today-card.tsx \
  apps/web-platform/lib/legal/disclosures.ts \
  apps/web-platform/supabase/migrations/046_runtime_cost_state.sql \
  apps/web-platform/test/server/byok-audit-writer-sweep.test.ts \
  knowledge-base/legal/article-30-register.md \
  docs/legal/data-protection-disclosure.md \
  plugins/soleur/docs/pages/legal/data-protection-disclosure.md \
  knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Result: **None.**

## References

- Brainstorm: `[[2026-05-17-pr-f-inngest-trigger-layer-brainstorm]]`
- Spec: `[[feat-pr-f-inngest-trigger-layer/spec]]`
- Parent plan: `knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md` §3.1–3.5
- Parent spec: `knowledge-base/project/specs/feat-agent-runtime-platform/spec.md`
- Inngest docs (verified via context7 `/websites/inngest` 2026-05-17): concurrency CEL, event `v` envelope, `inngest start` self-hosted binary with SQLite/Postgres backing, v3 `serve({ signingKey })`
- ADR: `ADR-030-inngest-as-durable-trigger-layer.md` (ADR-029 is highest existing; numbered to avoid collision per `2026-05-13-re-review-after-fix-catches-new-p1s-and-adr-number-collision`)
- Predecessor PRs: #3240 (PR-A), #3395 (PR-B), #3854 (PR-C), #3883 (PR-D), #3887 + #3922 (PR-E)
- Follow-up issues: #3947 (PR-G cohort onboarding), #3948 (cron migration TR9)
- v1 → v2 reviewer attribution: DHH (architectural critique), Kieran (correctness + P1.1/P1.3 + paper-cuts), Code Simplicity (YAGNI + collapses + module inlining)
- AGENTS.md rules touched: `hr-write-boundary-sentinel-sweep-all-write-sites`, `hr-dev-prd-distinct-supabase-projects`, `hr-gdpr-gate-on-regulated-data-surfaces`, `hr-weigh-every-decision-against-target-user-impact`, `hr-autonomous-loop-skill-api-budget-disclosure`, `cq-pg-security-definer-search-path-pin-pg-temp`, `cq-nextjs-route-files-http-only-exports`, `cq-write-failing-tests-before`, `cq-silent-fallback-must-mirror-to-sentry`
- Learnings carried forward: `2026-03-13-ralph-loop-idle-detection-and-repetition`, `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs`, `2026-03-23-action-completion-workflow-gap`, `2026-03-20-claude-code-action-max-turns-budget`, `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary`, `2026-04-18-supabase-migration-concurrently-forbidden`, `2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern`, `2026-05-13-re-review-after-fix-catches-new-p1s-and-adr-number-collision`, `2026-05-15-github-push-protection-rejects-synthetic-tokens-in-plan-prose`
