---
title: PR-H — Trust-tier external classes wiring (external_low_stakes, external_brand_critical, auto_with_digest)
date: 2026-05-19
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
tracking_issue: 4077
parent_issue: 3244
parent_pr: 3940
sibling_pr: 3984
draft_pr: 4065
deferred_pr: 4078
brainstorm: knowledge-base/project/brainstorms/2026-05-19-pr-h-trust-tier-external-classes-brainstorm.md
spec: knowledge-base/project/specs/feat-trust-tier-pr-h-external-classes/spec.md
status: ready-for-work
---

# PR-H — Trust-tier external classes wiring

Closes umbrella #3244 unchecked AC §3.4 **partially**: ships trust-tier policy engine for 4 of 5 action classes (low-stakes, brand-critical, money-legal-credentials-by-enum-absence, and the `auto_with_digest` tier value + `infra.*` classes WITHOUT the daily digest emitter — emitter deferred to PR-I). PR-F #3940 shipped the 3-tier vocabulary + DB CHECK + CFO function; PR-G #3984 shipped scope-grants substrate + audit viewer + 3-radio UI. PR-H lands the gating + signature substrate. The actual digest delivery surface lands in PR-I alongside outbound delivery integrations.

## Overview

Four shipping behaviors:

1. **`external_low_stakes` (draft + 1-click)** — founder clicks Send once; record `template_hash`, `clicked_at`, `per_send_body_sha256`, `grant_id` to new `action_sends` WORM table; perform outbound effect (or no-op stub for classes without a PR-H producer).
2. **`external_brand_critical` (approve every time)** — typed-confirm modal renders the exact recipient + content excerpt; founder types `SEND` verbatim; server-side re-validates `typed_value === "SEND"`; record `approval_signature_sha256` + `confirmed_typed=true`.
3. **`auto_with_digest` (4th-tier enum value)** — registered as a valid `scope_grants.tier` AND `ACTION_CLASS_DEFAULTS[infra.*]` is set to it. `infra.*` action classes will fire autonomously and write `tier_at_send='auto_with_digest'` rows to `action_sends`. **The daily digest aggregator + `digests` table are deferred to PR-I** (decision below; this closes Kieran P1-2 idempotency, Arch F8 kill-switch interaction, Arch F10 cross-tenant loop, and Simplicity #9 in a single move). PR-H ships the substrate; PR-I ships the delivery surface.
4. **`money_legal_credentials` (per-command-ack via enum-absence)** — `payment.refund`, `legal.dpa_sign`, `auth.api_key_rotate`, etc. are deliberately ABSENT from `ACTION_CLASSES`. Three defenses: (a) compile-time literal-union narrowing on `isGranted` / `isDenied` signatures; (b) rg-based lint test rejecting `string`/`any`-typed arguments to those entry points; (c) DB CHECK `action_class !~ '^(payment|legal|auth)\.'` on `scope_grants` + `action_sends` as defense-in-depth against indirect routes (e.g., RPC-from-JSON-payload). Triple-layer enforcement of `hr-menu-option-ack-not-prod-write-auth`.

Additionally, PR-H wires `today-card.tsx:46-78` Send/Edit/Discard buttons — currently `disabled` + `title="Wires in PR-G (#3947)"` per the PR-G-mis-attribution stub (see learning `2026-05-19-brainstorm-button-stub-title-is-not-evidence-of-wiring.md`). Without wiring, the action-class registry is unobservable end-to-end.

The classifier is **code-static at producer call sites**: each producer (CFO Inngest function, Stripe webhook, future Bluesky adapter, marketing-email-blast handler, etc.) declares its `ActionClass` literal at the `isGranted`/`inngest.send` boundary, exactly as `app/api/webhooks/stripe/route.ts:459` does today. For producers with multiple class options at runtime (e.g., a future Bluesky adapter choosing between `bluesky_reply_personal` and `bluesky_reply_soleur_handle` based on source account), the literal becomes a narrowed-union expression (`actionClass: ActionClass = source === "soleur_handle" ? "..." : "..."`); the lint test (TR2) accepts narrowed unions but rejects raw `string`/`any` types (per ADR-034 §2). No LLM classifier; no runtime-dynamic classification. Founders trust the 3-radio Scope Grants UI (PR-G) + the static map.

## Research Reconciliation — Spec vs. Codebase

Confirmed during plan-time research (repo-research-analyst + learnings-researcher + 4-agent plan review). Every row alters at least one FR, AC, or Implementation Phase below.

| Spec / brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| `isGranted(serviceClient, founderId, actionClass: ActionClass)` | `is-granted.ts:25-29` types `actionClass: string` — NOT `ActionClass`; sibling `isDenied` at L17 + `ACTION_CLASS_DENYLIST: ReadonlySet<string>` at L15 are also `string`-typed | Phase 1.6 tightens signatures across **6 call sites** (not 3): `is-granted.ts:17` (isDenied sig), `is-granted.ts:30` (internal isDenied call), `stripe/route.ts:456` (isGranted call), `cross-tenant-read-denied.test.ts:225,230`, `stripe-payment-failed-inngest.test.ts:92` (mockIsDenied) |
| `today-card.tsx` props carry `action_class` for click-time `isGranted` re-check | `today-card.tsx:15-21` props = `{id, source, owningDomain, draftPreview, urgency}` — no `action_class` | Server-side lookup at new `/api/dashboard/today/[id]/{send,edit,discard}/route.ts` keyed on `messageId`; NO prop-shape churn |
| Send-route uses service-role client for `isGranted` (brainstorm CTO "per PR-G grant route precedent") | **REFUTED at plan review.** `app/api/scope-grants/grant/route.ts:32-72` uses cookie-scoped `createClient()`; calls `supabase.rpc(...)` on it. Service-client is the **webhook** precedent only (`is-granted.ts:1-6` comment). For founder-JWT route, cookie-scoped client + RLS `scope_grants_owner_select` suffices | Phase 4.2 passes **cookie-scoped `supabase`** to `isGranted`; no service-client import in dashboard routes |
| "049/050 duplicate-number conflict" (brainstorm scope) | Conflicts span 020/029/037/038/041/042/048/049/050 — recurrent pattern | PR-H uses **051**. Mig-number hygiene = separate tech-debt issue (file post-merge per `wg-when-deferring-a-capability-create-a`) |
| `messages.tier` CHECK admits `'digest'` (brainstorm OQ2) | Mig 046:266-273 = compound CHECK; `messages.tier` is `text` (admits anything) | Moot — digest emitter + `digests` table deferred to PR-I per Phase 6 decision below. PR-H does NOT touch `messages.tier` CHECK |
| ts-morph / ESLint custom rule infra exists | None; existing lint tests are rg-style (`test/lint/inngest-key-server-only.test.ts`) | TR2 lint test is rg-style with fixture pass/fail cases per learning `2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md` |
| T&C §3a covers template authorization tier-agnostically — no amendment | §3a.2 L57 enumerates "(b) Auto tier" as **closed list** | Phase 7.5 surgical edit at §3a.2: widen "(b) Auto tier" → "(b) `Auto` or `Auto with daily digest` tier" |
| Article 30 PA-13 + PA-14 exist; PR-H adds PA-15 | CONFIRMED. PA-14 last; 9-limb format at L249-261 | Phase 7.1 invokes `legal-document-generator` agent with brainstorm CLO 9-limb framing |
| DPD canonical lives at `apps/web-platform/...` | DPD canonical is `docs/legal/data-protection-disclosure.md`; mirror at `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Phase 7.2-7.3 lockstep both files; AC10 greps both for `(p)` and `(q)` per learning `2026-05-14-discrete-enumeration-relockstep-and-pr-introduced-asymmetry.md` |
| Doppler env hot-reload learning at sibling commit `59b79a53` | NOT on this worktree HEAD; NOT on main HEAD. CONFIRMED Pending sibling-branch | PR-H does NOT depend on file; cites substantive claim via PR-G body. Phase 0.3 re-verifies on plan-execute |
| ADR-033 directory at `adrs/` | Path is `knowledge-base/engineering/architecture/decisions/`. THREE files at ADR-033 (collision class) | PR-H ships **ONE merged ADR-034** ("Action-class registry: code-static literals + 5th-class via enum-absence") with two sections. ADR-035 number reserved-but-unused per simplicity review |
| WORM trigger pattern (mig 037 role-check vs mig 048 shape-validated) | Mig 037 = pure-reject; mig 048 = shape-validated. Post-`2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` learning | `action_sends` ships **pure-reject UPDATE/DELETE** trigger (mig 037 pattern; NOT mig 048 shape-validated, because no Art-17 anonymise shape is needed at INSERT time — anonymise happens via dedicated SECURITY DEFINER RPC). NO `current_user = 'service_role'` bypass |
| `inngest.send` call sites needing typed-literal coverage | Exactly ONE producer today: `stripe/route.ts:491` | Lint test scope is bounded. Future producers register in `ACTION_CLASSES` first (ADR-034) |
| `runtime-explainer-banner.tsx` enumerates the 3 tiers | L43-48 enumerates `ACTION_CLASSES` (classes, NOT tiers); tiers are surfaced in Privacy §8.3 + T&C §3a.2 | TR11: leave banner untouched; Scope Grants settings page surfaces 4th-tier choice |
| Last-Updated annotation convention on legal docs | `**Last Updated:** May 18, 2026` (bold-wrapped) AND `Last Updated May 18, 2026` (hero) | Phase 7 ACs use regex `'Last Updated[: *]+May 19, 2026'` (tolerates both); separate counts per location. No PR-H/#4065 references in legal-doc bodies |
| Plan ships separate `digests` table | Plan-review simplicity #9 + Kieran P1-2 idempotency + Arch F8/F10 — converge on defer | Phase 6 **deferred to PR-I** (filed as child of #4078). PR-H keeps the `auto_with_digest` tier value so PR-I is additive |
| Typed-confirm modal lives at `components/dashboard/typed-confirm-modal.tsx` | Arch F4: operation-bounded primitive; future PR-I template-authorization will reuse | Move to `apps/web-platform/components/ui/typed-confirm-modal.tsx`. Today-card imports from `@/components/ui/typed-confirm-modal` |
| `action_sends` writer logic inline in routes | Arch F1: belongs in own bounded context | Phase 4 extracts `apps/web-platform/server/action-sends/write-action-send.ts` helper; routes call it |

## User-Brand Impact

Carry-forward from brainstorm `## User-Brand Impact` framing (operator re-affirmed 2026-05-19 with "All of them"; first set in umbrella #3244).

**If this lands broken, the user experiences:** a draft on their Today section with a Send button that either does nothing (typo silent fall-through; FR9 backfill missed), sends to the wrong recipient (template_hash collision; classifier-collision row-ordering), or sends without their consent (typed-confirm modal client-side-only check, bypassed by page script). For external_brand_critical, this means an outbound message to a Tier-1 enterprise account or a public X thread that the founder never authorized — the single-user-incident brand-survival vector named in #3244.

**If this leaks, the user's outbound communication and external recipient list is exposed via:** `action_sends` table (per-send signature, recipient_id_hash, template_hash, body sha256) and `messages.action_class` column (classification per draft). Cross-tenant read on these tables exposes business-relationship metadata and inferred operational cadence.

**Brand-survival threshold:** `single-user incident`.

**Why:** Founders accepting Soleur to ship overnight infrastructure work alongside drafting external sends MUST trust three boundaries: (a) the action-class registry is exhaustive and untyped variants fail-closed; (b) the typed-confirm modal cannot be bypassed by a page script or muscle-memory click; (c) per-tenant grants are honored at every send-click via re-checked `isGranted`. ANY single founder experiencing a mis-send breaks the cohort-level "drafts everywhere, sends nowhere except where you authorize" promise that T&C §3a.2 codifies — and forces a public incident response that brand-survival can't absorb at pre-MVP scale.

**How to apply:** PR-time `user-impact-reviewer` agent invocation is mandatory. CPO sign-off required at plan time before `/work` begins (`requires_cpo_signoff: true` in frontmatter). Review-time mandatory agents: `user-impact-reviewer`, `data-integrity-guardian`, `security-sentinel`, `semgrep-sast` (per learnings L4 + L6).

## Files to Edit

| Path | Why |
|---|---|
| `apps/web-platform/server/scope-grants/action-class-map.ts` | Extend `ACTION_CLASSES` 1→11 entries; widen `ActionClassTier` to 4 values; extend `ACTION_CLASS_DEFAULTS`; add `ACTION_CLASS_CATEGORY` discriminant |
| `apps/web-platform/server/scope-grants/is-granted.ts` | Tighten `actionClass: string` → `actionClass: ActionClass` on **both** `isGranted` (L25-29) and `isDenied` (L17); tighten `ACTION_CLASS_DENYLIST: ReadonlySet<string>` (L15) → `ReadonlySet<ActionClass>` |
| `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` | INSERT block adds `action_class: "finance.payment_failed"`; extend `PaymentFailedPayload` type |
| `apps/web-platform/app/api/webhooks/stripe/route.ts` | `inngest.send` data carries `action_class` field; existing `isGranted` call site benefits from signature tightening (no body change) |
| `apps/web-platform/components/dashboard/today-card.tsx` | Wire Send/Edit/Discard onClick handlers; remove `disabled` + `aria-disabled="true"` + `title="Wires in PR-G (#3947)"`; surface tier label; integrate typed-confirm-modal trigger on 409 |
| `apps/web-platform/test/server/scope-grants/cross-tenant-read-denied.test.ts` | Pass typed `ActionClass` literal to `isGranted` (currently passes `string`); 2 sites L225 + L230 |
| `apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts` | Update `mockIsDenied` (L92) signature to `(ActionClass) => boolean` |
| `apps/web-platform/server/account-delete.ts` | Extend Art. 17 erasure cascade to call `anonymise_action_sends(user_id)` BEFORE `auth.admin.deleteUser` per learning K-A1 + mig 048 sibling pattern |
| `docs/legal/data-protection-disclosure.md` | Add §2.3(p) `external_low_stakes` + §2.3(q) `auto_with_digest`; bump `**Last Updated:** May 19, 2026` |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Mirror §2.3(p) + §2.3(q); same Last Updated bump |
| `docs/legal/privacy-policy.md` | §8.3 extend tier enumeration (3→4 tiers); add Art. 22(3) digest-clarification one-liner; Last Updated bump |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | Mirror §8.3 amendment; Last Updated bump |
| `docs/legal/terms-and-conditions.md` | Surgical edit §3a.2 L57: widen "(b) Auto tier" → "(b) `Auto` or `Auto with daily digest` tier"; Last Updated bump |
| `plugins/soleur/docs/pages/legal/terms-and-conditions.md` | Mirror §3a.2 surgical edit; Last Updated bump |
| `knowledge-base/legal/article-30-register.md` | Add PA-15 "Template-authorized autonomous send"; mirror PA-14 9-limb row shape |

## Files to Create

| Path | Why |
|---|---|
| `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql` | (a) `scope_grants_tier_check` DROP+REPLACE to admit `auto_with_digest`; (b) `messages.action_class text NULL` ADD + bounded backfill UPDATE for PR-F drafts; (c) `action_sends` WORM table with shape CHECKs + DB CHECK `action_class !~ '^(payment|legal|auth)\.'`; (d) pure-reject UPDATE/DELETE trigger (mig 037 pattern; no role-check bypass); (e) owner-select + owner-insert RLS; (f) `anonymise_action_sends(uuid)` SECURITY DEFINER RPC; (g) explicit REVOKE/GRANT EXECUTE per `cq-pg-security-definer-search-path-pin-pg-temp` |
| `apps/web-platform/supabase/verify/051_action_sends_worm.sql` | Verify sentinel for `verify-migrations` CI job — confirms table exists, RLS enabled, trigger registered, backfill complete, `anonymise_action_sends` RPC registered with correct grants |
| `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.down.sql` | Reverse migration (DROP TABLE action_sends; DROP CONSTRAINT scope_grants_tier_check + restore prior; ALTER TABLE messages DROP COLUMN action_class; DROP FUNCTION anonymise_action_sends) |
| `apps/web-platform/server/action-sends/write-action-send.ts` | Bounded-context home for the `action_sends` INSERT (Arch F1). Exports `writeActionSend({ supabase, founderId, message, grant, tier, confirmedTyped?, typedValue? }) → Promise<ActionSend>`. Single write boundary used by send route AND future producers per `hr-write-boundary-sentinel-sweep-all-write-sites` |
| `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts` | POST. Cookie-scoped JWT auth (NOT service-role). Server-side `messages` lookup by id with `.eq("user_id", user.id)` belt-and-suspenders. Re-call `isGranted(supabase, user.id, message.action_class as ActionClass)` at click-time using **cookie-scoped client** (RLS owner-select on `scope_grants` lets the founder self-read). Branch on returned tier. Call `writeActionSend(...)`. Reject 409 `requires_confirmation` for `approve_every_time` if body lacks `confirmed_typed=true` AND `typed_value === "SEND"`. Reject 400 for `auto`/`auto_with_digest` tiers (Send not the founder-initiated path) |
| `apps/web-platform/app/api/dashboard/today/[id]/edit/route.ts` | POST. Same auth pattern. Update `messages.draft_preview`; status='draft' guard |
| `apps/web-platform/app/api/dashboard/today/[id]/discard/route.ts` | POST. Same auth pattern. Flip `messages.status` from `draft` to `archived` |
| `apps/web-platform/components/ui/typed-confirm-modal.tsx` | **Lives under `components/ui/` per Arch F4** — operation-bounded primitive; reusable by PR-I template-authorization confirmations. Renders recipient identifier + content excerpt (first 200 chars + ellipsis) + action_class label + tier label. Input field placeholder "Type SEND to confirm". Submit disabled until value === "SEND" (case-sensitive, NO `.trim()`/`.normalize()` per Kieran P2-7). On submit, POST with `confirmed_typed=true` + `typed_value` + `messageId`. Keyboard-only nav (Tab, Enter, Esc), ARIA-announced, 44×44px tap targets, no hover-only affordances |
| `apps/web-platform/test/server/scope-grants/action-class-exhaustive.test.ts` | Combined exhaustiveness + enum-absence regression test (per simplicity #7): (a) `satisfies Record<ActionClass, ...>` parity covers `ACTION_CLASS_DEFAULTS` + `ACTION_CLASS_CATEGORY`; (b) `_exhaustive: never` rail; (c) regex assertion `ACTION_CLASSES.every(c => !/^(payment\|legal\|auth)\./.test(c))` with failure message linking ADR-034 §2 |
| `apps/web-platform/test/lint/action-class-typed-literals.test.ts` | rg-based lint test asserting every `isGranted(`, `isDenied(`, `inngest.send(` call passes a **typed** (literal or narrowed-union) `ActionClass` argument — NOT raw `string`/`any`. Per ADR-034 §1, narrowed unions are valid (e.g., `source === "x" ? "lit_a" : "lit_b"`). Fixture pass/fail cases per learning `2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md` |
| `apps/web-platform/test/server/action-sends-worm.test.ts` | Live-DB integration test gated by `TENANT_INTEGRATION_TEST=1`. (a) INSERT happy → expect 201; (b) UPDATE → expect P0001; (c) DELETE → expect P0001; (d) `scope_grants.tier = 'auto_with_digest'` accepted (folded-in from former auto-with-digest-tier.test.ts per simplicity #7); (e) `scope_grants.tier = 'garbage'` rejected; (f) `action_sends.action_class = 'payment.refund'` REJECTED by new DB CHECK regex (defense-in-depth per Arch F3); (g) `anonymise_action_sends(uuid)` RPC succeeds; SELECT post-call returns `user_id=NULL`; subsequent `users` DELETE succeeds (Kieran P1-1 Art-17 cascade); (h) cross-tenant SELECT returns 0 rows. Synthesized fixtures only per `cq-test-fixtures-synthesized-only` |
| `apps/web-platform/test/components/ui/typed-confirm-modal.test.tsx` | Component test (RTL + Playwright): renders payload; submit disabled until "SEND" exact (test ZWS, lowercase, trailing-space, empty — implementation must NOT call `.trim()`/`.normalize()` per Kieran P2-7); Esc closes WITHOUT discard; Tab focus trap; Enter submits; ARIA `role="dialog"` + `aria-modal` + `aria-labelledby`; mobile 44×44px tap targets |
| `apps/web-platform/test/api/dashboard/today/send-route.test.ts` | Route handler tests: 200 happy (draft_one_click + `action_sends` row + cookie-scoped client used), 409 requires_confirmation, 422 typed_value mismatch, 403 revoked grant, 400 auto/auto_with_digest, 401 no JWT, 403 cross-tenant. Per Kieran B4: schema-correct UUIDs so 403 isn't masked by 22P02 |
| `knowledge-base/engineering/architecture/decisions/ADR-034-action-class-registry-static-literals-and-enum-absence.md` | **One merged ADR** (was 034 + 035). §1: code-static registry, literal-or-narrowed-union at producer call sites, compile-time typo catch via `isKnownActionClass`, lint-test enforcement, branched-producer carveout. §2: 5th class (money/legal/credentials) enforced by enum-absence at TS layer PLUS DB CHECK `action_class !~ '^(payment\|legal\|auth)\.'` as defense-in-depth against indirect routes. Hard-rule lineage from `hr-menu-option-ack-not-prod-write-auth` |

## Open Code-Review Overlap

One open scope-out touches these files: **#3739** (`server/observability.ts`) — "extract `reportSilentFallbackWithUser` helper (collapse 11-site duplication)". Disposition: **acknowledge** (do not fold in). PR-H is a NEW emit site (new dashboard routes + `write-action-send.ts` helper) not in #3739's 11-site enumeration. PR-H uses the same 4-line `withIsolationScope + setUser + reportSilentFallback` shape; will migrate to the helper when #3739 ships. Add inline comment in new route handlers linking to #3739 so the future migration is greppable.

## Domain Review

**Domains relevant:** Product, Legal, Engineering (triad mandatory under `brand_survival_threshold: single-user incident`). Marketing, Sales, Operations, Finance, Support — carry-forward from brainstorm (#3244 PR-F/PR-G assessments stand).

**Brainstorm-recommended specialists:** `legal-document-generator` (PA-15 draft, Phase 7.1). `ux-design-lead` (typed-confirm modal wireframes) explicitly NOT invoked — brainstorm + spec FR7 + Arch F4 collectively specify the modal's interaction contract + placement (`components/ui/`); wireframes would be ceremony.

### Engineering (CTO) — carry-forward + plan-review delta

**Status:** reviewed (carry-forward from brainstorm + plan-review-applied delta)
**Assessment:** Classifier lives at producer call sites (declarative) — not a separate `classify()` step. For multi-class producers (Bluesky reply with source-account branching), the literal becomes a narrowed-union expression that the lint test still accepts. Registry stays code-static `as const` union + parallel `ACTION_CLASS_CATEGORY` discriminant. Dashboard routes use **cookie-scoped client** for `isGranted` (corrected from brainstorm CTO's service-role claim per Kieran P1-3). Send re-checks `isGranted` at click-time (revocation race per TR8). `messages.action_class` column added at mig 051 with bounded backfill. 5th class via enum-absence + DB CHECK defense-in-depth (per Arch F3). Migration 051; mig conflicts at 048/049/050 = separate hygiene. `SOLEUR_FR5_ENABLED` is the producer-side global kill-switch; consumer routes (Send/Edit/Discard) remain live regardless — semantics codified in ADR-034 §3.

### Legal (CLO) — carry-forward + plan-review delta

**Status:** reviewed
**Assessment:** 9 must-haves grows by 1 net (PA-15). T&C §3a.2 L57 surgical edit (closed list "(b) Auto tier" → "(b) `Auto` or `Auto with daily digest` tier") required at Phase 7.5. DPD §2.3(p) + (q) added in both mirrors. `action_sends` WORM = correct shape; pure-reject trigger (mig 037 pattern) + `anonymise_action_sends` SECURITY DEFINER RPC to handle Art. 17 cascade (per Kieran P1-1 + mig 048 sibling precedent). Per-1-click E&O bounds (100 sends OR 30 days; 90-day hard expiration; 30-day re-confirmation) DEFERRED to PR-I via `template_authorizations`. `auto_with_digest` Art. 22(3) one-liner (Phase 7.4) ships in PR-H even though digest emitter defers to PR-I — the legal disclosure is forward-honest about the tier semantics.

### Product (CPO) — carry-forward + sign-off gate

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** Classification is the load-bearing decision for week-1 brand-survival. Reframe 5 classes as `{category × default_tier}` matrix correctly preserves the parent-plan taxonomy. Code-static enum with runtime-overridable wins over LLM classifier. Defer escalation + classifier-feedback loop to PR-I. Hidden gap (closed in this plan): Send/Edit/Discard buttons at `today-card.tsx:48-73` were unwired despite `title="Wires in PR-G"` — PR-H wires them.

**Plan-time CPO sign-off requirement:** `requires_cpo_signoff: true` in frontmatter. CPO has reviewed brainstorm + spec; sign-off carries to plan.

### Product/UX Gate (BLOCKING tier)

**Tier:** blocking
**Mechanical trigger:** `Files to Create` contains `apps/web-platform/components/ui/typed-confirm-modal.tsx` (new component under `components/**/*.tsx`).
**Decision:** reviewed (partial)
**Agents invoked:** spec-flow-analyzer (Phase 2.5 inline; UI-flow prompt), cpo (carry-forward), copywriter (Phase 7 — modal payload framing copy)
**Skipped specialists:** `ux-design-lead` — brainstorm + spec FR7 + Arch F4 collectively specify modal interaction + placement; wireframes would be ceremony (single-modal, single-input, deterministic disable rules, established a11y AC list).
**Pencil available:** N/A

**Findings:** Four user flows are well-formed. Modal close on Esc returns to Today section with draft still listed (NO auto-discard). Phase 5.1 AC covers this. Phase 6 (digest emitter UI surface) defers; the partial AC §3.4 closure is documented in Out of Scope.

## GDPR / Compliance Gate (Phase 2.7)

[skill-enforced: gdpr-gate at plan Phase 2.7]

Plan touches: schema migration (051), new table (`action_sends`), new auth-gated API routes, new processing activity (PA-15). Threshold = `single-user incident`. Canonical regex hit AND trigger (b) brand-survival single-user incident AND trigger (d) new artifact distribution surface (typed-confirm modal payload exposure). Gate **fires**.

**Output (advisory):**

- **Art. 6 lawful basis** for `action_sends` writes: contract performance under T&C §3a "Agent Command Authority". PA-15 references Art. 6(1)(b).
- **Art. 9 special-category check:** `recipient_id_hash` + `per_send_body_sha256` are hashed; `messages.draft_preview` is owner-only RLS-gated. **Pass.**
- **Art. 17 erasure cascade:** REQUIRED. Phase 2.3 adds `anonymise_action_sends(uuid)` SECURITY DEFINER RPC; Phase 4 extends `server/account-delete.ts` to call it BEFORE `auth.admin.deleteUser`. Without this, first user-deletion request fails at FK `RESTRICT` (Kieran P1-1).
- **Art. 22(3) right to human review** for `auto_with_digest`: Phase 7.4 one-liner ships in PR-H even though digest emitter defers — disclosure must be forward-honest about tier semantics.
- **Art. 30 register** PA-15: Phase 7.1 gate-mandatory.
- **Art. 32 TOMs:** typed-confirm modal server-side re-validation of `typed_value === "SEND"` (TR6); DB CHECK `action_class !~ '^(payment|legal|auth)\.'` (defense-in-depth per Arch F3).
- **No Critical findings** (no missing lawful basis; no Art. 9 special-category).

## Infrastructure (IaC)

**Skip rationale.** Plan introduces no new infrastructure. Inngest runtime + Supabase already provisioned. Digest emitter (would have been the only candidate IaC change) is deferred to PR-I. State change = mig 051 only, applied via existing `web-platform-release.yml` CI jobs.

## Implementation Phases

Phases ordered by dependency. TDD per `cq-write-failing-tests-before`. Per Arch F7, Phase 1 and Phase 2 are independent; either order is safe. Plan keeps Phase 1 → Phase 2 → Phase 3 (registry → schema → producer).

### Phase 0 — Preconditions (5 checks; folded down from 8 per DHH+Simplicity)

0.1. Confirm mig 051 is the next free number: `ls apps/web-platform/supabase/migrations/ | grep -E '^0[5-9][0-9]_' | head -5`.
0.2. Re-read `mig 046:266-273` — confirm `messages_external_tier_status_check` is the compound CHECK.
0.3. Re-verify Doppler hot-reload learning land status: `git log --all --oneline -- knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md`. If on `main`, cite the file in plan; else cite PR-G body.
0.4. Confirm ADR-034 free: `ls knowledge-base/engineering/architecture/decisions/ | grep -E '^ADR-034'` → expect empty.
0.5. **Type-widening cross-consumer grep (per `hr-type-widening-cross-consumer-grep` and Arch F6).** Enumerate ALL 6 sweep sites for the `actionClass: string → ActionClass` tightening:
   - `apps/web-platform/server/scope-grants/is-granted.ts:17` (isDenied signature)
   - `apps/web-platform/server/scope-grants/is-granted.ts:25-29` (isGranted signature)
   - `apps/web-platform/server/scope-grants/is-granted.ts:30` (internal isDenied call)
   - `apps/web-platform/server/scope-grants/is-granted.ts:15` (ACTION_CLASS_DENYLIST type)
   - `apps/web-platform/app/api/webhooks/stripe/route.ts:456` (isGranted call site)
   - `apps/web-platform/test/server/scope-grants/cross-tenant-read-denied.test.ts:225, 230` (2 call sites)
   - `apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts:92` (mockIsDenied)

   Total: 6 distinct files / 7 line-anchored sites. Phase 1.6 sweeps all 6 files. **Verify rule IDs cited in this plan via `grep -F "id: <ruleid>" AGENTS.{md,core.md,docs.md,rest.md}` AND `scripts/retired-rule-ids.txt`** (per learning K1).

### Phase 1 — Registry + types (`action-class-map.ts` + `is-granted.ts`)

1.1. **RED:** Add `apps/web-platform/test/server/scope-grants/action-class-exhaustive.test.ts` — combined: parity (`satisfies Record<ActionClass, ...>`), exhaustiveness `_exhaustive: never` rail, enum-absence regex `ACTION_CLASSES.every(c => !/^(payment|legal|auth)\./.test(c))`. Failure message links to ADR-034 §2.
1.2. **RED:** Add `apps/web-platform/test/lint/action-class-typed-literals.test.ts` — rg-based; assert every `isGranted(`, `isDenied(`, `inngest.send(` call has a **typed** argument (literal OR narrowed-union expression). Reject `string`/`any`-typed callers. Fixture pass/fail cases.
1.3. **GREEN:** Widen `apps/web-platform/server/scope-grants/action-class-map.ts`:
   - `ACTION_CLASSES` adds 10 entries (final list in §FR1 below — 11 total).
   - `ActionClassTier` adds `"auto_with_digest"`.
   - `ACTION_CLASS_DEFAULTS` populated per FR4.
   - `ACTION_CLASS_CATEGORY: Record<ActionClass, "finance" | "external_low_stakes" | "external_brand_critical" | "infra">` added.
1.4. **GREEN:** Phase 0.5 sweep — tighten `is-granted.ts:17` (`isDenied(actionClass: ActionClass)`), L25-29 (`isGranted(... actionClass: ActionClass)`), L15 (`ACTION_CLASS_DENYLIST: ReadonlySet<ActionClass>`). Update test sites 225/230 + mockIsDenied L92. `stripe/route.ts:456` benefits from narrowed type with no body change.
1.5. **GREEN:** Run `bun run tsc --noEmit` per `cq-union-widening-grep-three-patterns` (per Arch C2: `tsc` is canonical enumerator, not source-grep). Every `TS2322 ... not assignable to never` is an exhaustive-switch rail to widen.
1.6. **VERIFY:** Phase 1 tests pass.

#### FR1 final action-class registry (11 entries — DHH + Simplicity cut 2)

```ts
export const ACTION_CLASSES = [
  "finance.payment_failed",                                  // existing producer: stripe/route.ts:491
  "external.low_stakes.customer_status_update",              // PR-I producer
  "external.low_stakes.vendor_support_ticket",               // PR-I producer
  "external.low_stakes.bluesky_reply_personal",              // PR-I producer (Bluesky adapter)
  "external.low_stakes.slack_dm_standard",                   // PR-I producer
  "external.brand_critical.marketing_email_blast",           // PR-I producer
  "external.brand_critical.public_x_thread",                 // PR-I producer (X publish API)
  "external.brand_critical.bluesky_reply_soleur_handle",     // PR-I producer (same as personal; branched)
  "external.brand_critical.slack_dm_enterprise_tier1",       // PR-I producer
  "infra.dependency_bump",                                   // PR-I producer
  "infra.log_rotate",                                        // PR-I producer
] as const;
```

**Cut from brainstorm OQ1 list per plan-review:** `external.brand_critical.blog_post_publish`, `external.brand_critical.product_changelog` (no concrete PR-I producer story; would be dead tiles in Scope Grants UI). File tracking issue at /work Phase 9 for adding back when blog-publish producer arrives.

### Phase 2 — Migration 051 (action_sends WORM + messages.action_class + scope_grants.tier widening + anonymise RPC + DB CHECK enum-absence)

2.1. **RED:** Add `apps/web-platform/test/server/action-sends-worm.test.ts` (gated by `TENANT_INTEGRATION_TEST=1`) covering:
   - (a) INSERT happy → 201
   - (b) UPDATE → P0001
   - (c) DELETE → P0001
   - (d) INSERT with NULL `template_hash` → 23502 (column NOT NULL)
   - (e) `scope_grants.tier = 'auto_with_digest'` → 201
   - (f) `scope_grants.tier = 'garbage'` → 23514
   - (g) **DB CHECK enum-absence:** `INSERT … action_class = 'payment.refund'` → 23514 (regex CHECK rejection per Arch F3)
   - (h) **Art-17 cascade:** call `anonymise_action_sends(<uuid>)` → success; SELECT shows `user_id IS NULL` for that founder's rows; subsequent `auth.admin.deleteUser(<uuid>)` succeeds (Kieran P1-1)
   - (i) Cross-tenant SELECT (founder A reads B's row) → 0 rows

   Per learning A2, mocked variants insufficient.

2.2. **GREEN:** Author `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql` (NO outer `BEGIN/COMMIT` — Supabase runner already wraps per Kieran P1-4):

```sql
-- 051: scope_grants.tier widening + messages.action_class + action_sends WORM
--      + anonymise_action_sends RPC + DB CHECK enum-absence.
-- NOTE: Supabase runner wraps each file in a transaction; do NOT add outer BEGIN/COMMIT.
-- Pattern source: mig 037 (pure-reject WORM) + mig 048 (anonymise SECURITY DEFINER RPC).

-- (a) Widen scope_grants.tier CHECK
ALTER TABLE public.scope_grants
  DROP CONSTRAINT IF EXISTS scope_grants_tier_check;
ALTER TABLE public.scope_grants
  ADD CONSTRAINT scope_grants_tier_check
  CHECK (tier IN ('auto', 'draft_one_click', 'approve_every_time', 'auto_with_digest'));

-- DB CHECK enum-absence on scope_grants.action_class (defense-in-depth, Arch F3)
ALTER TABLE public.scope_grants
  DROP CONSTRAINT IF EXISTS scope_grants_action_class_not_locked;
ALTER TABLE public.scope_grants
  ADD CONSTRAINT scope_grants_action_class_not_locked
  CHECK (action_class !~ '^(payment|legal|auth)\.');

-- (b) Add messages.action_class
ALTER TABLE public.messages
  ADD COLUMN action_class text NULL;

-- (c) Backfill existing PR-F drafts with defensive deploy-timestamp bound (Kieran P2-1)
UPDATE public.messages
   SET action_class = 'finance.payment_failed'
 WHERE action_class IS NULL
   AND tier = 'external_brand_critical'
   AND owning_domain = 'cfo'
   AND source = 'stripe'
   AND created_at < '2026-05-19 23:59:59+00'::timestamptz;
-- The cutoff bounds the backfill so a future CFO producer emitting a different class
-- is not retro-labeled. Re-evaluate cutoff at /work-time to the actual mig-deploy timestamp.

-- (d) action_sends WORM table with shape CHECKs + DB CHECK enum-absence
CREATE TABLE public.action_sends (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                   uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  message_id                uuid NOT NULL REFERENCES public.messages(id),
  action_class              text NOT NULL CHECK (length(action_class) BETWEEN 1 AND 64),
  CONSTRAINT action_sends_action_class_not_locked
    CHECK (action_class !~ '^(payment|legal|auth)\.'),
  tier_at_send              text NOT NULL CHECK (tier_at_send IN ('auto', 'draft_one_click', 'approve_every_time', 'auto_with_digest')),
  template_hash             text NOT NULL,
  per_send_body_sha256      text NOT NULL,
  recipient_id_hash         text NOT NULL,
  clicked_at                timestamptz NOT NULL DEFAULT now(),
  confirmed_typed           boolean NOT NULL DEFAULT false,
  approval_signature_sha256 text NULL,
  grant_id                  uuid NOT NULL REFERENCES public.scope_grants(id)
);
-- user_id is NULLABLE to admit Art-17 anonymisation; ON DELETE RESTRICT
-- prevents accidental user-row deletion before anonymise call.
COMMENT ON TABLE public.action_sends IS
  'Per-send signature record. WORM (append-only). Art. 5(2) accountability evidence.';

-- (e) Pure-reject UPDATE/DELETE trigger (mig 037 pattern; no role-check bypass)
CREATE OR REPLACE FUNCTION public.action_sends_worm_reject()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'action_sends is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$$;
REVOKE EXECUTE ON FUNCTION public.action_sends_worm_reject() FROM PUBLIC;

CREATE TRIGGER action_sends_no_update
  BEFORE UPDATE ON public.action_sends
  FOR EACH ROW EXECUTE FUNCTION public.action_sends_worm_reject();

CREATE TRIGGER action_sends_no_delete
  BEFORE DELETE ON public.action_sends
  FOR EACH ROW EXECUTE FUNCTION public.action_sends_worm_reject();

-- (f) RLS — owner-select + owner-insert; no FOR ALL USING (learning 2026-04-18-rls-for-all-using).
ALTER TABLE public.action_sends ENABLE ROW LEVEL SECURITY;

CREATE POLICY action_sends_owner_select ON public.action_sends
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY action_sends_owner_insert ON public.action_sends
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- (g) Index for future digest aggregator + audit viewer
CREATE INDEX action_sends_user_clicked_idx
  ON public.action_sends (user_id, clicked_at DESC);

-- (h) Art-17 anonymise RPC — called by server/account-delete.ts BEFORE auth.admin.deleteUser
--     (Kieran P1-1; sibling pattern from mig 048 anonymise_scope_grants).
--     The function bypasses the WORM trigger via a session-local GUC that the trigger could check;
--     simpler approach used here: UPDATE bypasses the BEFORE UPDATE trigger by going through a
--     SECURITY DEFINER function with SET LOCAL session_replication_role = 'replica'.
--     This is the documented Postgres-canonical way to disable triggers transactionally;
--     scope is the single function call, not session-wide.
CREATE OR REPLACE FUNCTION public.anonymise_action_sends(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  affected integer;
BEGIN
  -- Caller must be service-role or the user themselves (account-delete.ts is service-role).
  IF auth.uid() IS NULL AND current_user NOT IN ('service_role','postgres') THEN
    RAISE EXCEPTION 'anonymise_action_sends: caller not authorised'
      USING ERRCODE = '42501';
  END IF;
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'anonymise_action_sends: self-call only for authenticated callers'
      USING ERRCODE = '42501';
  END IF;

  SET LOCAL session_replication_role = 'replica';
  UPDATE public.action_sends
     SET user_id          = NULL,
         recipient_id_hash = '__anonymised__'
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RESET session_replication_role;

  RETURN affected;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.anonymise_action_sends(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.anonymise_action_sends(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.anonymise_action_sends(uuid) TO authenticated;
-- authenticated grant + self-call guard above lets the user-initiated DSAR flow call the RPC
-- directly without bouncing through a service-role endpoint.
COMMENT ON FUNCTION public.anonymise_action_sends(uuid) IS
  'Art. 17 erasure: nulls user_id on action_sends rows for given founder. Called by account-delete.ts BEFORE auth.admin.deleteUser. Pattern source: mig 048 anonymise_scope_grants.';
```

2.3. **GREEN:** `apps/web-platform/supabase/verify/051_action_sends_worm.sql` — assertions for table, RLS, triggers, policies, both DB CHECKs (tier widening + enum-absence regex), `messages.action_class` column, backfill row count, `anonymise_action_sends` RPC registered with correct grants.

2.4. **GREEN:** `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.down.sql` — reverse migration.

2.5. **VERIFY:** apply locally to dev Supabase per `hr-dev-prd-distinct-supabase-projects`. Run integration test suite from Phase 2.1.

### Phase 3 — Producer call-site extension (CFO function + Stripe webhook)

3.1. **GREEN:** `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` — extend `PaymentFailedPayload` to require `action_class: "finance.payment_failed"`; add field to L214-227 INSERT.
3.2. **GREEN:** `apps/web-platform/app/api/webhooks/stripe/route.ts:491` — `inngest.send` data carries `action_class: "finance.payment_failed"` field.
3.3. **VERIFY:** existing CFO tests pass; Phase 1 lint test passes.

### Phase 4 — New API routes + write-action-send helper + account-delete cascade

4.1. **GREEN:** `apps/web-platform/server/action-sends/write-action-send.ts` (Arch F1). Exports `writeActionSend({ supabase, founderId, message, grant, tier, confirmedTyped?, typedValue? })`. Single write boundary; sweeps all writers per `hr-write-boundary-sentinel-sweep-all-write-sites`. Computes `template_hash`, `per_send_body_sha256`, `recipient_id_hash`, `approval_signature_sha256` (when `tier === "approve_every_time"`). Approval signature uses canonical JSON serialization to avoid `||` ambiguity (per simplicity hidden-assumption note).

4.2. **RED:** Add `apps/web-platform/test/api/dashboard/today/send-route.test.ts` covering 8 cases per Phase 4 spec.

4.3. **GREEN:** `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts`:
   - `export const dynamic = "force-dynamic"`; only HTTP exports per `cq-nextjs-route-files-http-only-exports`.
   - `validateOrigin(req)` → 403 on mismatch.
   - `createClient()` (cookie-scoped) → `supabase.auth.getUser()` → 401.
   - `supabase.from("messages").select("id, user_id, action_class, status, draft_preview").eq("id", id).eq("user_id", user.id).maybeSingle()` — belt-and-suspenders + RLS.
   - `if (!isKnownActionClass(message.action_class)) return 422` (backfill should cover existing rows; defensive guard).
   - **Call `isGranted(supabase, user.id, message.action_class as ActionClass)` with the SAME cookie-scoped `supabase` client** (Kieran P1-3). RLS `scope_grants_owner_select` lets the founder self-read. Returns `null` → 403 (revoked).
   - Branch on `grant.tier`:
     - `draft_one_click`: call `writeActionSend(...)`; perform outbound effect or no-op stub; flip `messages.status` to `archived`.
     - `approve_every_time`: if body has `confirmed_typed=true && typed_value === "SEND"`, proceed as `draft_one_click` PLUS signature; else 409 `{ requires_confirmation, action_class, tier, recipient, content_excerpt }`.
     - `auto` or `auto_with_digest`: 400.
   - Sentry breadcrumbs via `reportSilentFallback`. Inline comment links to #3739.

4.4. **GREEN:** `apps/web-platform/app/api/dashboard/today/[id]/edit/route.ts` + `discard/route.ts` — mirror auth pattern; UPDATE `messages.draft_preview` / flip to `archived`.

4.5. **GREEN:** Extend `apps/web-platform/server/account-delete.ts` cascade (Kieran P1-1). Call `supabase.rpc("anonymise_action_sends", { p_user_id: userId })` BEFORE the `auth.admin.deleteUser` step. Sibling pattern: existing `anonymise_scope_grants` + `anonymise_tc_acceptances` calls.

4.6. **VERIFY:** `bun test apps/web-platform/test/api/dashboard/`.

### Phase 5 — today-card.tsx wiring + typed-confirm-modal component (under `components/ui/`)

5.1. **RED:** `apps/web-platform/test/components/ui/typed-confirm-modal.test.tsx` (RTL + Playwright a11y).
5.2. **GREEN:** `apps/web-platform/components/ui/typed-confirm-modal.tsx` (Arch F4; reusable by PR-I). External UX reference: GitHub repo-delete modal. Server-side re-validation in send route is the load-bearing TOM.
5.3. **GREEN:** Wire `today-card.tsx` Send/Edit/Discard onClick handlers. Remove `disabled` + `aria-disabled` + `title="Wires in PR-G (#3947)"`. On Send 409, open `<TypedConfirmModal>`; second POST with `confirmed_typed=true` + `typed_value`. Optimistic UI on discard.
5.4. **VERIFY:** component + manual smoke in dev.

### Phase 6 — DEFERRED to PR-I (digest emitter + `digests` table)

**Decision:** PR-H ships the `auto_with_digest` tier value + `infra.*` registry + `tier_at_send='auto_with_digest'` writes to `action_sends`. The **digest emitter** (Inngest scheduled function aggregating action_sends → `digests` table → Today section surface) defers to PR-I. Rationale: plan-review converged across 3 reviewers (Simplicity #9 + Kieran P1-2 idempotency window + Arch F10 cross-tenant inner-loop scoping + Arch F8 kill-switch orphan); shipping the emitter in PR-H would require addressing all four issues at PR-H scope.

PR-I tracking item lives under #4078 with the following carry-over:
- `digests` table schema (final shape determined at PR-I with on-write vs on-read evaluation per Arch F5; quantized `window_start` per Kieran P1-2; per-founder inner-loop scoping per Arch F10).
- `digest-infra-actions.ts` Inngest scheduled function + `SOLEUR_FR5_ENABLED` short-circuit per Arch F8.
- `anonymise_digests(uuid)` RPC + `account-delete.ts` extension.
- Founder-local timezone handling (deferred from PR-H per brainstorm OQ; cheap-alternative `users.next_digest_at` per Arch F9 — evaluate then).
- Today section UI render (digest card variant).

Privacy §8.3 Art. 22(3) one-liner ships in PR-H Phase 7.4 even though the emitter defers — disclosure is forward-honest about tier semantics (founders see the tier label "Auto with daily digest" in Scope Grants UI starting at PR-H merge).

### Phase 7 — Legal artifacts

7.1. **GREEN:** Article 30 PA-15 via `legal-document-generator` agent.
7.2. **GREEN:** `docs/legal/data-protection-disclosure.md` §2.3(p) + §2.3(q); `**Last Updated:** May 19, 2026`. No PR-H/#4065 references in body.
7.3. **GREEN:** `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` mirror.
7.4. **GREEN:** `docs/legal/privacy-policy.md` §8.3 — 3→4 tier enumeration + Art. 22(3) one-liner: *"For infrastructure-class actions (Auto with daily digest), the right to human review is exercised via the next-business-day digest review window provided in the Today section."*
7.5. **GREEN:** `plugins/soleur/docs/pages/legal/privacy-policy.md` mirror.
7.6. **GREEN:** `docs/legal/terms-and-conditions.md` §3a.2 L57 surgical edit + Last Updated bump.
7.7. **GREEN:** `plugins/soleur/docs/pages/legal/terms-and-conditions.md` mirror.
7.8. **VERIFY:** every Last-Updated annotation greppable as `Last Updated[: *]+May 19, 2026`; canonical + Eleventy mirrors agree on §2.3 letter ordering, §8.3 tier count, §3a.2 phrasing.

### Phase 8 — ADR (one merged ADR per DHH P2 + Simplicity #3)

8.1. **GREEN:** `knowledge-base/engineering/architecture/decisions/ADR-034-action-class-registry-static-literals-and-enum-absence.md`. Status: `accepted`.
   - **§1** Code-static registry, literal-or-narrowed-union at producer call sites (multi-class producer carveout per Arch F2). Compile-time typo catch + lint test enforcement.
   - **§2** 5th class (money/legal/credentials) enforced by enum-absence at TS layer PLUS DB CHECK regex `action_class !~ '^(payment|legal|auth)\.'` as defense-in-depth (Arch F3). Hard-rule lineage from `hr-menu-option-ack-not-prod-write-auth`.
   - **§3** `SOLEUR_FR5_ENABLED` kill-switch semantics: gates **producer side only**; consumer routes (Send/Edit/Discard) remain live regardless. This codifies the orphan-substrate question raised at Arch F8.
8.2. **VERIFY:** `find knowledge-base/engineering/architecture/decisions/ -name 'ADR-034*'` returns 1 file with `status: accepted`.

### Phase 9 — Verification + multi-agent review

9.1. `bun run tsc --noEmit` clean.
9.2. `bun test apps/web-platform` clean.
9.3. `TENANT_INTEGRATION_TEST=1 bun test apps/web-platform/test/server/action-sends-worm.test.ts` against DEV Supabase.
9.4. `semgrep-sast` 0 findings.
9.5. Push branch; spawn brand-survival-extended review (≥9 agents per AC6): `user-impact-reviewer`, `data-integrity-guardian`, `security-sentinel`, `semgrep-sast`, `agent-native-reviewer`, `code-quality-analyst`, `architecture-strategist`, `pattern-recognition-specialist`, `spec-flow-analyzer`.
9.6. Fix findings inline per `rf-review-finding-default-fix-inline`.

### Phase 10 — Ship

10.1. `/soleur:ship` — preflight Check 6.
10.2. Mark PR ready; auto-merge.
10.3. Post-merge (CI-driven per `hr-all-infrastructure-provisioning-servers`):
   - POST-1: `web-platform-release.yml` migrate + verify-migrations apply mig 051 to dev + prd.
   - POST-2: confirm `SOLEUR_FR5_ENABLED=true` in Doppler `prd` (read-only).
   - POST-3: synthetic smoke against prd via Stripe TEST `invoice.payment_failed`.
   - POST-4: verify `action_sends` row via Supabase MCP read-only query per `hr-no-dashboard-eyeball-pull-data-yourself`.
   - POST-5: verify Art-17 anonymise round-trip — synthetic founder deletion via `account-delete.ts`; expect `action_sends.user_id IS NULL` for that founder; subsequent SELECT on `auth.users` returns 0.
   - POST-6: file PR-I tracking issue under #4078 with Phase 6 carry-over; file mig-number-conflict hygiene issue.
   - POST-7: operator partially closes #3244 §3.4 (note "digest emitter deferred to PR-I"); `gh issue close 4077`.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** All FR1-FR12 implemented per Phase 1-8 (FR10 — digest emitter — deferred to PR-I with explicit Out of Scope citation).
- **AC2.** All TR1-TR13 verified by passing tests.
- **AC3.** `bun test apps/web-platform` clean.
- **AC4.** `bun run tsc --noEmit` clean (zero `TS2322 ... not assignable to never` rails open).
- **AC5.** `TENANT_INTEGRATION_TEST=1 bun test apps/web-platform/test/server/action-sends-worm.test.ts` passes (covers WORM trigger, enum-absence DB CHECK, Art-17 anonymise round-trip, cross-tenant denial).
- **AC6.** Multi-agent review (≥9 agents) returns 0 P1, ≤2 P2; all fixed inline.
- **AC7.** `semgrep-sast` 0 findings.
- **AC8.** Article 30 PA-15 drafted; DPD §2.3(p)+(q) added in BOTH mirrors; Privacy §8.3 amendments in BOTH mirrors; T&C §3a.2 surgical edit in BOTH mirrors. Greps:
   - `grep -cE '^### Processing Activity 15' knowledge-base/legal/article-30-register.md` returns 1.
   - `grep -cE '^- \*\*\(p\)\*\*' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns 1 per file.
   - `grep -cE '^- \*\*\(q\)\*\*' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns 1 per file.
   - `grep -cE 'Last Updated[: *]+May 19, 2026' docs/legal/*.md plugins/soleur/docs/pages/legal/*.md` returns ≥6.
   - `grep -cE 'Auto with daily digest' docs/legal/terms-and-conditions.md plugins/soleur/docs/pages/legal/terms-and-conditions.md` returns ≥1 per file.
- **AC9.** Single merged ADR drafted with `status: accepted`; `ls knowledge-base/engineering/architecture/decisions/ADR-034*` returns 1.
- **AC10.** `apps/web-platform/components/dashboard/today-card.tsx` Send/Edit/Discard buttons are no longer disabled. **Tighter grep** (DHH P3): `grep -cE '<button[^>]*disabled' apps/web-platform/components/dashboard/today-card.tsx` returns 0; `grep -c 'Wires in PR-G' apps/web-platform/components/dashboard/today-card.tsx` returns 0.
- **AC11.** `user-impact-reviewer` agent invoked at PR review-time. Comment on PR with findings (zero or fixed inline).
- **AC12.** Server-side cookie-scoped `isGranted` use verified at Phase 4.2: `grep -E 'isGranted\(\s*supabase\s*,' apps/web-platform/app/api/dashboard/today/` returns ≥1; `grep -E 'isGranted\(\s*serviceClient\s*,' apps/web-platform/app/api/dashboard/today/` returns 0.
- **AC13.** Art-17 cascade integration test passes (Phase 2.1 case (h)).
- **AC14.** DB CHECK enum-absence regression covered (Phase 2.1 case (g)).

### Post-merge (operator — automated where possible)

- **POST-1.** `web-platform-release.yml` migrate + verify-migrations green on dev + prd.
- **POST-2.** `doppler secrets get SOLEUR_FR5_ENABLED -p soleur -c prd --plain` returns `true`.
- **POST-3.** Synthetic smoke: Stripe TEST `invoice.payment_failed` → CFO Today card → Send → typed-confirm modal renders → second click writes `action_sends` row.
- **POST-4.** `mcp__plugin_supabase_supabase__execute_sql` returns ≥1 `action_sends` row for the synthetic founder.
- **POST-5.** Art-17 round-trip on a synthetic founder via prd `account-delete.ts` (read-only verification of result: `action_sends.user_id IS NULL`).
- **POST-6.** Tracking issues filed: PR-I digest emitter (child of #4078); mig-number-conflict hygiene.
- **POST-7.** `gh issue close 4077`; `gh issue edit 3244` partial-AC checkbox update with deferral note.

## Test Strategy

- **Unit:** combined `action-class-exhaustive.test.ts` (parity + exhaustiveness + enum-absence regex); `action-class-typed-literals.test.ts` (rg lint).
- **Live-DB integration:** `action-sends-worm.test.ts` covers 9 cases including Art-17 cascade + DB CHECK enum-absence (per simplicity #7 consolidation, fold former `auto-with-digest-tier.test.ts` cases in here). Gated by `TENANT_INTEGRATION_TEST=1`. Synthesized fixtures per `cq-test-fixtures-synthesized-only`.
- **API route:** `send-route.test.ts` (8 cases); `edit-route.test.ts` + `discard-route.test.ts` (smaller suites).
- **Component:** `typed-confirm-modal.test.tsx` (RTL + Playwright a11y).
- **Cross-tenant:** existing `cross-tenant-read-denied.test.ts` extended (Phase 2.1 case (i)).
- **Type-level:** `tsc --noEmit` is the canonical exhaustiveness enumerator (per learning C2; replaces a dedicated `.test-d.ts` per DHH + Simplicity).

## Risks & Sharp Edges

- **WORM trigger pattern.** Pure-reject UPDATE/DELETE (mig 037 pattern); NO `current_user = 'service_role'` bypass per learning A1. Art-17 erasure handled via dedicated `anonymise_action_sends(uuid)` SECURITY DEFINER RPC with `SET LOCAL session_replication_role='replica'` to traverse the trigger.
- **DB CHECK enum-absence defense-in-depth.** Catches indirect-route attacks (RPC-from-JSON-payload, future config-file imports) that the TS layer can't see. Belt-and-suspenders per Arch F3.
- **Migration number conflicts.** PR-H uses 051. Conflicts at 020/029/037/038/041/042/048/049/050 = separate tech-debt issue (file POST-6).
- **Typed-confirm modal client-side bypass.** Server-side re-validation of `typed_value === "SEND"` (case-sensitive, NO `.trim()`/`.normalize()` per Kieran P2-7) at TR6 is the load-bearing safety net.
- **PR-G `today-card.tsx` button stub.** AC10 verifies removal.
- **Doppler hot-reload limitation** is Pending sibling-branch. Phase 0.3 re-verifies on plan-execute.
- **5th-class enum-absence drift.** Triple defense: TS literal-union narrowing + rg-based lint + DB CHECK regex. Failure messages link to ADR-034 §2.
- **isGranted signature widening cascade** sweeps 6 sites (per Arch F6). Phase 0.5 enumerates; Phase 1.4 sweeps.
- **`SOLEUR_FR5_ENABLED` orphan-substrate question.** ADR-034 §3 codifies semantics: kill-switch gates producer only; consumer routes remain live.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6 and `/soleur:preflight` Check 6.** Section is filled at brainstorm carry-forward.
- **No internal typed-confirm modal precedent.** External reference: GitHub repository-deletion modal. Modal lives under `components/ui/` per Arch F4 for PR-I reuse.
- **CFO backfill ordering.** Mig 051 backfills `messages.action_class='finance.payment_failed'` BEFORE CFO function INSERT change ships (Phase 2 before Phase 3). Defensive `AND created_at < <deploy-ts>` bound per Kieran P2-1 prevents retro-labeling future producers.
- **PR-G's RuntimeExplainerBanner re-audit (TR11).** Plan-time: leave untouched. Scope Grants settings page surfaces the 4th-tier choice; banner stays 3-beat.
- **Multi-class producer pattern (Arch F2).** Future Bluesky reply adapter chooses between `bluesky_reply_personal` and `bluesky_reply_soleur_handle` via narrowed union, not single literal. Lint test accepts narrowed unions; rejects raw `string`/`any`. Carveout codified in ADR-034 §1.
- **Approval signature `||` ambiguity.** `approval_signature_sha256 = sha256(JSON.stringify({founder_id, message_id, typed_value, ts}))` — use canonical JSON serialization (sorted keys), NOT string concat with `||`, to avoid collision when a field contains `||` substring.

## Dependencies

- **Umbrella:** #3244.
- **PR-F:** #3940 (merged 2026-05-17).
- **PR-G:** #3984 (merged 2026-05-19).
- **Pending sibling-branch learning:** `2026-05-19-doppler-env-hot-reload-limitation.md` at commit `59b79a53`. PR-H does NOT block on merge.
- **Code-review overlap:** #3739 (acknowledged; new emit sites in PR-H will migrate to `reportSilentFallbackWithUser` helper when #3739 ships).

## Out of Scope (deferred to PR-I — tracking issue #4078)

Per `wg-when-deferring-a-capability-create-a`, each deferral lives in #4078 with re-evaluation criteria. **Plan-review converged on more aggressive deferral than brainstorm proposed; the cuts below reflect that.**

- **Daily digest emitter + `digests` table + Today-section digest UI render** (Phase 6 entire scope). Re-evaluation: after `infra.*` producer adapters ship in PR-I.
- **Founder-local timezone digest delivery** (cheap-alternative `users.next_digest_at` column per Arch F9 — evaluate at PR-I when emitter ships).
- **`anonymise_digests(uuid)` RPC + `account-delete.ts` extension for `digests`** (folded into PR-I when `digests` table lands).
- **`template_authorizations` WORM table** parallel to `scope_grants`.
- **Template authorization bounds**: 100 sends OR 30 days per template; 90-day hard expiration; 30-day soft re-confirmation prompt.
- **Retroactive classifier-feedback loop**: founder flags past `external_low_stakes` send as `brand_critical` via audit viewer.
- **LLM-based runtime classifier** (Phase 2 evolution).
- **Outbound delivery integrations**: Bluesky API client, marketing-email-blast adapter, X publish API, blog publish. PR-H ships the GATING layer; PR-I ships the WIRE per producer.
- **`SOLEUR_FR5_ENABLED=true` cohort flip**: separate post-merge operator step.
- **Migration-number-conflict hygiene** for 020/029/037/038/041/042/048/049/050: separate tech-debt issue (file POST-6).
- **`reportSilentFallbackWithUser` helper migration**: PR-H uses the 4-line wrap; migrates to helper when #3739 ships.
- **`external.brand_critical.blog_post_publish` and `external.brand_critical.product_changelog`** action-class entries: cut from registry (no PR-I producer story); re-add when blog/changelog producers arrive.

---

**Resume prompt (copy-paste after `/clear`):**

```text
/soleur:work knowledge-base/project/plans/2026-05-19-feat-trust-tier-pr-h-external-classes-plan.md. Branch: feat-trust-tier-pr-h-external-classes. Worktree: .worktrees/feat-trust-tier-pr-h-external-classes/. Issue: #4077. PR: #4065 (draft). Plan reviewed (4-agent panel: DHH + Kieran + simplicity + architecture-strategist); 15 findings applied inline. Phase 6 digest emitter deferred to PR-I (#4078 child); §3.4 closure is partial-with-explicit-deferral. Implementation next.
```
