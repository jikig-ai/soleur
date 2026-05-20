---
title: PR-H — Trust-tier external classes (`external_low_stakes`, `external_brand_critical`, `auto_with_digest` wiring)
date: 2026-05-19
brand_survival_threshold: single-user incident
lane: cross-domain
tracking_issue: 4077
parent_issue: 3244
parent_pr: 3940
sibling_pr: 3984
draft_pr: 4065
---

# PR-H — Trust-tier external classes brainstorm

Umbrella #3244 unchecked AC: "Trust-tier policy engine: 5 action classes (read/draft auto, internal infra auto+digest, external low-stakes draft+1-click, external brand-critical approve-every-time, money/legal/credentials per-command ack)." PR-F #3940 shipped the 3-tier vocabulary + DB CHECK + cfo-on-payment-failed; PR-G #3984 (merged 2026-05-19) shipped scope-grants substrate + audit viewer + 3-radio UI. PR-H closes the AC by wiring the remaining classes end-to-end.

## What we're building

PR-H lands four of five trust-tier action classes end-to-end (the 5th — money/legal/credentials per-command-ack — is enforced by enum-absence: it is unreachable through the registry, so a runtime call falls through `isGranted → null → fail-closed`):

1. **`external_low_stakes` (draft + 1-click)** — customer status updates, vendor support tickets, non-promotional Bluesky replies. Founder clicks Send once; we capture `template_hash`, `clicked_at`, `per_send_body_sha256`, `grant_id` to the new `action_sends` WORM table and fire the outbound effect.
2. **`external_brand_critical` (approve every time)** — blog posts, marketing email blasts, public X threads, product changelogs, replies from the `@soleur.ai` Bluesky handle, Slack DMs to Tier-1 enterprise accounts. Founder types "SEND" verbatim into a typed-confirm modal that renders the exact recipient + content excerpt; we capture `approval_signature_sha256` + `confirmed_typed=true` to `action_sends`.
3. **`auto_with_digest` (4th tier, infra category)** — `infra.*` action classes fire autonomously; a daily Inngest scheduled function emits a digest to the founder's Today section summarizing the last 24h of infra actions. Closes the "47 silent overnight things" brand-survival vector per parent plan §3.4.
4. **`money_legal_credentials` (per-command-ack via enum-absence)** — `payment.refund`, `legal.dpa_sign`, `auth.api_key_rotate`, etc. are deliberately absent from `ACTION_CLASSES`. An agent invocation referencing such a class is unroutable; the runtime equivalent of `hr-menu-option-ack-not-prod-write-auth` is enforced by the type system, not by relaxable DB CHECK. The web-app analog for the modal-confirm flow lives at the `approve_every_time` tier.

In addition, PR-H wires the Send/Edit/Discard buttons in `today-card.tsx:48-73` — currently `disabled` with `title="Wires in PR-G (#3947)"` despite PR-G shipping without wiring them. Without wiring, the action-class registry is unobservable end-to-end.

## Why this approach

The CPO + CLO + CTO triad (mandatory under `USER_BRAND_CRITICAL=true`) converged on a **code-static registry with literal action-class names declared at producer call sites**:

- **The "Slack DM to Tier-1 enterprise" disambiguation case** (operator scope question 1) is resolved by registering `external.brand_critical.slack_dm_enterprise_tier1` and `external.low_stakes.slack_dm_standard` as distinct registry entries, not by runtime LLM classification. Founders ship pre-MVP with the existing 3-radio UI at `/dashboard/settings/scope-grants` and trust the static map.
- **Runtime-dynamic classification** (LLM inspects recipient/channel/audience at send-time) introduces "classifier was wrong" as a new failure mode on top of "founder forgot to grant" — additional brand-survival risk for marginal flexibility. Defer to a Phase-2 follow-up after 5+ orgs running.
- **Producer-site literal pattern already exists** at `apps/web-platform/app/api/webhooks/stripe/route.ts:459`. PR-H follows the precedent; future producers (Bluesky adapter, marketing email blast handler, etc.) declare their `ActionClass` literal at the `isGranted` / `inngest.send` call site.
- **Compile-time typo catch** via the existing `isKnownActionClass` type guard at `action-class-map.ts:23`. A typo would silently fall through `isGranted → null → fail-closed` (safe but produces silent UX bugs); a lint test enforces that every `inngest.send` / `isGranted` call passes a typed `ActionClass` literal, not `string`.

## Key decisions

| Decision | Rationale |
|---|---|
| Code-static action-class registry with literal-at-producer-site classifier | Deterministic; compile-time typo catch via `isKnownActionClass`; matches shipped pattern at `stripe/route.ts:459`. Avoids "classifier was wrong" failure mode. |
| Add `auto_with_digest` as 4th tier value in `ActionClassTier` enum and `scope_grants.tier` CHECK | Parent plan §3.4 names "internal infra auto+digest" as one of 5 classes. Cheap now (1 enum value + Inngest digest function); expensive post-migration (DB CHECK migration, audit-viewer column). Operator chose include-in-PR-H. |
| 5th class (`money_legal_credentials`) enforced via **enum-absence**, not parallel DB CHECK | One source of truth (code enum). A DB CHECK can be dropped in a future migration without code review catching it. Mirrors the CLI hard rule invariant at the type system layer. |
| New `action_sends` WORM table at migration 051 (mirrors `audit_byok_use` pattern from mig 037) | Art. 5(2) accountability evidence. `messages` is NOT WORM (drafts mutate during edit). Extending `audit_byok_use` would conflate BYOK-key-use with action-send signature and break its single-purpose RLS contract. |
| Add `messages.action_class` column at migration 051 | `isGranted` re-check at Send-click needs the class persisted. PR-F's `cfo-on-payment-failed.ts:225` writes drafts without storing which class produced them — gap discovered during this brainstorm. |
| Wire Send/Edit/Discard in PR-H scope (NOT a PR-G follow-up) | Hidden incomplete AC: `today-card.tsx:48-73` buttons `disabled` with `title="Wires in PR-G (#3947)"` but PR-G shipped without handlers. Without wiring, PR-H's registry is unobservable end-to-end. |
| Typed-confirm modal for `approve_every_time` — founder types "SEND" verbatim, payload rendered in full | Web analog of CLI `hr-menu-option-ack-not-prod-write-auth`. The CLI rule "show the exact command before running it" translates to "render the exact outbound payload (recipient + content excerpt) in the confirmation surface." Operator chose this over second-click ack — typing breaks muscle-memory. |
| Defer `template_authorizations` table + escalation/retroactive quarantine to PR-I | Keeps PR-H tight. PR-I spec input from CLO: template authorization bound at **100 sends OR 30 days**, with 90-day hard expiration and 30-day re-confirmation soft prompt. Distinguishes "standing instruction" from "blanket consent waiver" under GDPR Art. 7(3). |
| Defer the classifier-feedback loop (low-stakes → brand-critical reclassification) to PR-I | Couples to escalation/quarantine; same boundary. |
| No new env flag; per-grant predicate is tenant invariant; `SOLEUR_FR5_ENABLED` remains global kill-switch | Doppler env hot-reload limitation (Pending learning, see below) — env flags are one-shot snapshots at `docker run`, not per-tenant gates. Per-grant DB predicate at `is-granted.ts:25` is the load-bearing tenant invariant. |
| Migration starts at 051; existing 048/049/050 duplicate-number conflict filed as separate hygiene issue | Renumbering applied migrations is destructive. Precedent: learning `2026-05-13-re-review-after-fix-catches-new-p1s-and-adr-number-collision.md`. |
| `messages_external_tier_status_check` (mig 046:269-273) already covers `external_low_stakes` | Verified: `CHECK (tier NOT IN ('external_brand_critical', 'external_low_stakes') OR status IN ('draft','archived'))`. No parallel CHECK needed in PR-H. |
| ADRs to draft: (1) "Action-class registry is code-static, declared at producer call sites"; (2) "Money/legal/credentials category enforced by enum-absence, not DB CHECK" | CTO-flagged architectural decisions worth durable capture. |

### Productize Candidate

None this round. The classifier-site declaration pattern is too narrow to skill-ize. If a 3rd Inngest function adopts the producer-literal pattern, revisit.

## Open questions

1. **Exact action-class registry for PR-H.** First-cut (subject to revision in spec):
   - `finance.payment_failed` (existing)
   - `external.low_stakes.customer_status_update`
   - `external.low_stakes.vendor_support_ticket`
   - `external.low_stakes.bluesky_reply_personal`
   - `external.low_stakes.slack_dm_standard`
   - `external.brand_critical.blog_post_publish`
   - `external.brand_critical.marketing_email_blast`
   - `external.brand_critical.public_x_thread`
   - `external.brand_critical.product_changelog`
   - `external.brand_critical.bluesky_reply_soleur_handle`
   - `external.brand_critical.slack_dm_enterprise_tier1`
   - `infra.dependency_bump`
   - `infra.log_rotate`

   Open: which of these have a corresponding *producer* call site already (vs. defining the class without a producer)? Defining a class without a producer is allowed (founder grants it; nothing triggers it yet) but creates "dead" tiles in the scope-grants UI.

2. **Digest persistence shape.** Persist as `messages` row with `tier='digest'` (new tier value — requires widening another CHECK?) vs new `digests` table. CTO leaned `messages` with new tier value but flagged the CHECK widening risk. Verify `messages.tier` CHECK constraint in mig 046 before deciding.

3. **Typed-confirm modal accessibility.** Web platform is PWA-first per roadmap T1. Modal must be keyboard-only navigable, screen-reader announceable, and mobile-tap-friendly (no hover-only affordances). Reference for the founder-types-verbatim pattern: GitHub "type repo name to confirm deletion" but with payload rendered above the input.

4. **Cohort gate timing.** Does PR-H itself flip `SOLEUR_FR5_ENABLED=true` for the alpha cohort, or does that remain a separate post-merge operator step (per PR-G's `## Post-merge operator handoff` pattern)? Recommendation: separate post-merge step; PR-H merges with the kill-switch still false.

5. **Article 30 PA-15 timing.** CLO recommends drafting "Template-authorized autonomous send" processing activity via legal-document-generator pre-merge to keep the closed-alpha gating intact. Confirm with CLO at /plan time whether to draft inline in PR-H or as a parallel docs-PR.

## User-Brand Impact

**Brand-survival threshold:** `single-user incident` (carry-forward from umbrella #3244, PR-F #3940, PR-G #3984; operator re-affirmed 2026-05-19 with "All of them" on the framing question).

**Artifacts exposed by PR-H:**
- `messages.action_class` (new column) — classification record per draft message.
- `action_sends` (new WORM table) — per-send signature, template_hash, body_sha256, click event, grant_id.
- `scope_grants.tier` CHECK (expanded to include `auto_with_digest`).
- `today-card.tsx` Send/Edit/Discard handlers (new active outbound trigger paths).
- Typed-confirm modal component (new web primitive rendering recipient + payload excerpt).
- `infra.*` digest entries in founder Today section.

**Vectors if PR-H ships broken (with mitigations):**

1. **Classifier-typo silent fall-through.** Agent invokes with mistyped action_class → `isGranted` returns null → fail-closed → no send. Founder sees a draft with no Send button. Symptom: cohort attrition, not data leak. **Mitigation:** compile-time `ActionClass` union via `as const`; lint test that every `inngest.send` / `isGranted` call passes a typed `ActionClass` literal not `string` (extends the `cq-union-widening-grep-three-patterns` pattern).

2. **`action_sends` WORM bypass.** If trigger uses role-check (not shape-validation), `service_role`-issued INSERT could later be UPDATE'd — destroys Art. 5(2) accountability. **Mitigation:** mirror mig 048's shape-validated pattern; single SET-site GUC bypass; live-DB integration test (not `vi.fn()`-mocked) per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`.

3. **Typed-confirm modal bypassable.** If "SEND" string check is client-side only, founder muscle-memory or programmatic page-script can bypass. **Mitigation:** server-side re-check on POST: `confirmed_typed=true` AND `typed_value === "SEND"` in request body; reject 422 otherwise. Audit the server-side requirement in same-PR review.

4. **Template_hash collision.** Two distinct outbound bodies hashed to the same template_hash → wrong template authorized. **Mitigation:** template_hash is sha256 of canonical-form template (no time-varying fields); `per_send_body_sha256` is the per-send body hash. Both columns mandatory in `action_sends`. PR-I template_authorizations will key on template_hash; collision here means cross-template authorization confusion.

5. **`auto_with_digest` digest emission failure.** Inngest scheduled function errors → infra actions land without disclosure → Art. 22(3) gap (founder didn't receive the next-business-day digest window). **Mitigation:** Sentry on digest-emission errors (`cq-silent-fallback-must-mirror-to-sentry`); same-PR test asserts digest is enqueued; runbook entry "if Sentry alerts on `digest-infra-actions` failures, manually trigger via Inngest UI within 12h."

6. **5th-class enum-absence drift.** A future PR adds `payment.refund` to `ACTION_CLASSES` without code review catching that it should be unreachable. **Mitigation:** ADR-NN captures the invariant; a lint test asserts that no `ACTION_CLASSES` entry matches the prefix regex `/^(payment|legal|auth)\./`; the test failure message points to the ADR.

7. **PR-G's transparency-surface drift.** `RuntimeExplainerBanner` (PR-G) is currently scoped to introduce the runtime to first-time founders; PR-H's audience is the same cohort, but the banner's three-beat copy may not cover the new tiers' semantics. **Mitigation:** re-audit per learning `2026-05-12-brainstorm-re-audit-inherited-transparency-surfaces.md` at /plan time — drop the banner reference if a cheaper channel (in-product tooltip on the new tier) is more honest.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

(Triad mandatory under `USER_BRAND_CRITICAL=true`: CPO + CLO + CTO. Other domains not spawned — signal not orthogonal to scope. Marketing/Sales/Support/Finance/Operations carry forward from #3244 PR-F/PR-G assessments; no new vectors.)

### Product (CPO)
**Summary:** Classification is the load-bearing decision for week-1 brand-survival. Reframe 5 classes as `{category × default_tier}` matrix correctly preserves the parent-plan taxonomy. Add `auto_with_digest` as 4th tier (cheap now, expensive later). Code-static enum with runtime-overridable wins over LLM classifier for pre-MVP — founders trust the explicit 3-radio UI at `/dashboard/settings/scope-grants`. Defer escalation to PR-I; ship without classifier-feedback loop. **Hidden gap:** Send/Edit/Discard buttons at `today-card.tsx:48-73` are unwired despite `title="Wires in PR-G"`; without wiring, PR-H ships an unobservable registry.

### Legal (CLO)
**Summary:** 9 must-haves grows by 1 net (PR-H adds PA-15 "Template-authorized autonomous send" to Article 30 register; closes 1 by completing the trust-tier AC, opens 1 via Privacy §8.3 template-authorization sub-clause). T&C 2.0.0 §3a "Agent Command Authority" already covers template authorization in tier-agnostic language — no amendment. DPD §2.3 needs new rows for `external_low_stakes` and `auto_with_digest`. New `action_sends` WORM table is the correct schema (mirror `audit_byok_use` mig 037). Per-1-click E&O requires `template_hash` + `click_event_ts` + `per_send_body_sha256` + `recipient_id_hash` + upper bound (100 sends OR 30 days) + 90-day expiration + 30-day re-confirmation soft prompt for PR-I. 5th class enforced by enum-absence is cleaner than parallel DB CHECK. `auto_with_digest` is T&C-neutral but needs DPD §2.3 amendment + Privacy §8.3 Art. 22(3) digest-clarification one-liner ("for infrastructure-class actions, the right to human review is exercised via the next-business-day digest review window") — without it, a 47-action overnight digest is a per-decision Art. 22(3) violation × 47.

### Engineering (CTO)
**Summary:** Classifier lives at producer call sites (declarative) — not a separate `classify()` step. Each producer passes the `ActionClass` literal directly to `isGranted` / `inngest.send`; the existing pattern at `stripe/route.ts:459` is the precedent. Action-class registry stays code-static `as const` literal union + a parallel `ACTION_CLASS_CATEGORY` discriminant; lint enforces typed literals at call sites. New routes at `/api/dashboard/today/[id]/{send,edit,discard}/route.ts` mirror `/api/scope-grants/grant/route.ts` shape (founder JWT auth, not service-role). Send handler re-checks `isGranted` at click-time (revocation race is real). For `draft_one_click`: write `action_sends` row + perform send + flip `messages.status` to `archived`. For `approve_every_time`: return 409 `requires_confirmation`; client opens typed-confirm modal; second POST with `confirmed_typed=true` + `typed_value=SEND` proceeds (server re-validates the typed string). `messages.action_class` column MUST be added at mig 051 (PR-F gap). `messages_external_tier_status_check` already covers `external_low_stakes`. 5th class via enum-absence. Migration 051 is the next free number; 048/049/050 conflict is a separate hygiene issue. No new env flag — `SOLEUR_FR5_ENABLED` is the global kill-switch, per-grant predicate is the tenant invariant.

## Capability Gaps

| Gap | Domain | Evidence |
|---|---|---|
| `messages.action_class` column missing | Engineering / data model | `cfo-on-payment-failed.ts:225` persists draft with `tier='external_brand_critical'` + `status='draft'` but no `action_class` column exists in `messages` schema (mig 046:266-273 schema). The `isGranted` re-check at Send-click requires resolving the action_class from the message — currently impossible. PR-H mig 051 adds the column; CFO function must populate it. |
| Send/Edit/Discard handlers unwired | Engineering / web-platform UI | `today-card.tsx:48-73` buttons rendered with `disabled` + `aria-disabled="true"` + `title="Wires in PR-G (#3947)"`. No `today-card-actions.ts` file exists; no `app/api/dashboard/today/[id]/{send,edit,discard}/route.ts` directory exists (the `app/api/dashboard/` directory contains only `today/route.ts` and `runs/route.ts`). PR-G workflow-gate followup required. |
| No typed-confirm modal component | Engineering / web-platform UI | `find apps/web-platform/components -iname "*confirm*"` returned no matches matching the typed-confirmation pattern. Closest precedent is the second-click ack on PR-G's scope-grants `auto` tier — different semantic. New primitive must be designed inline. |
| `auto_with_digest` digest emitter | Engineering / Inngest | `apps/web-platform/server/inngest/functions/` contains only `cfo-on-payment-failed.ts` and `cron-daily-triage.ts`. The `cron-daily-triage.ts` pattern is the closest precedent for a scheduled Inngest function but the digest aggregation logic over `action_sends` is new. |
| Action-class registry > 1 entry | Engineering / scope-grants | `action-class-map.ts:9` ships `ACTION_CLASSES = ["finance.payment_failed"] as const`. PR-H adds ~12 entries spanning 4 categories. Header docblock at `action-class-map.ts:3-7` already names the 4 canonical update sites (CFO function, stripe route, settings page, audit page). |
| Article 30 register PA-15 missing | Legal | `knowledge-base/legal/article-30-register.md` ships PA-13 (PR-F autonomous-draft) + PA-14 (PR-G cohort onboarding). PA-15 "Template-authorized autonomous send" is PR-H scope per CLO. |
| DPD §2.3 rows for `external_low_stakes` + `auto_with_digest` missing | Legal | `docs/legal/data-protection-disclosure.md` + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (both mirrors) ship §2.3(o) per PR-G. PR-H adds (p) for `external_low_stakes` and (q) for `auto_with_digest`. |
| `messages.tier` CHECK widening (if digest persists as `messages` row) | Engineering / data model | If decision (open question 2) is to persist digests as `messages` rows with `tier='digest'`, the `messages_external_tier_status_check` constraint at mig 046:269-273 needs widening to admit the new tier. Verify before mig 051. Alternative: separate `digests` table sidesteps the widening. |
| Web-app per-command-ack primitive has no prior precedent | Engineering / web-platform UI + Legal | Learning `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md` defines the CLI rule but does not translate to web. Genuinely new decision. Recommendation: render exact recipient + content excerpt above the typed-input field; require verbatim "SEND" not case-insensitive; capture `confirmed_typed=true` AND `typed_value` in `action_sends`. |
| Classifier-collision discipline not yet applied | Engineering / quality | Learning `2026-05-15-classifier-prose-table-row-ordering-collision.md` documents the failure mode for prose classifier tables. PR-H must enumerate every existing class trigger description for keyword overlap with each new class; place more-specific classes first; have `user-impact-reviewer` agent fire at PR-time (already implied by single-user-incident threshold). |
| Union-widening parity test missing | Engineering / quality | Per learning `2026-04-18-discriminated-union-widening-if-ladders-and-config-map-parity.md` and `cq-union-widening-grep-three-patterns`, every action-class enum widening requires (a) `switch + _exhaustive: never` over if-ladders, (b) parity test asserting policy-key map covers every enum member. PR-H must add the parity test for `ACTION_CLASS_DEFAULTS` and `ACTION_CLASS_CATEGORY`. |

## Pending (sibling-branch dependency)

`knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md` lives on sibling worktree `docs-compliance-posture-pr-g-post-merge-gates` (commit `59b79a53`); not yet on main. Substantive claim — "env flag is global kill-switch only; per-grant predicate is the tenant invariant; `--env-file` is a one-shot snapshot at `docker run`" — is independently verified by PR-G's body (`## Sharp edges (load-bearing)` section). PR-H plan-time should re-verify the learning file lands on main before referencing it in tests. Posture: cite as **Pending** in plan + test; do not block PR-H on sibling-branch merge.

## Carry-forward to PR-I (escalation + classifier-feedback)

For the PR-I follow-up issue (to be filed at Phase 3.6):

- **`template_authorizations` WORM table** parallel to `scope_grants` (per CLO).
- **Bounds: 100 sends OR 30 days per template authorization**; 90-day hard expiration; 30-day soft re-confirmation prompt (per operator + CLO).
- **Retroactive quarantine**: `template_authorizations.revoked_at NULL → non-NULL` with `revocation_reason` enum (`founder_revoked`, `quota_exhausted`, `expired`, `quarantine_retroactive`, `dsr_erasure`).
- **`isTemplateAuthorized(founderId, template_hash)` predicate** added to webhook/Inngest predicate path (two probes per send: `isGranted` + `isTemplateAuthorized`).
- **Classifier-feedback loop** — founder can flag a past `external_low_stakes` send as "should have been brand_critical" via the `/dashboard/audit` viewer; the action_class is re-registered with stricter default and all future sends with same `template_hash` are quarantined.

## ADRs to draft (PR-H scope)

1. **"Action-class registry is code-static, declared at producer call sites"** — captures the literal-at-call-site discipline + compile-time typo catch + rejection of LLM classifier for pre-MVP.
2. **"Money/legal/credentials category enforced by enum-absence, not parallel DB CHECK"** — captures the type-system-over-DB-constraint invariant + the hard-rule lineage from `hr-menu-option-ack-not-prod-write-auth`.
