---
title: PR-I — Template authorizations + escalation/quarantine + classifier-feedback
date: 2026-05-21
tracking_issue: 4078
parent_issue: 3244
predecessor_pr: 4065
brainstorm_predecessor: knowledge-base/project/brainstorms/2026-05-19-pr-h-trust-tier-external-classes-brainstorm.md
draft_pr: 4213
lane: cross-domain
brand_survival_threshold: single-user incident
domains_assessed: [Product, Legal, Engineering]
triad_mandated: true
---

# PR-I — Template authorizations (structural-only ship; classifier-feedback deferred to PR-I+1)

Closes umbrella #3244 §3.4 follow-through items: the `template_authorizations` substrate that makes PR-H's per-1-click E&O argument durable under GDPR Art. 7(3).

## Premise verification (pre-brainstorm)

| Re-eval criterion (from #4078 body) | Status |
|---|---|
| PR-H (#4077) merged | ✅ Merged 2026-05-19 via [PR #4065](https://github.com/jikig-ai/soleur/pull/4065) |
| Carry-forward brainstorm at cited path exists | ✅ `knowledge-base/project/brainstorms/2026-05-19-pr-h-trust-tier-external-classes-brainstorm.md` (lines 149-157) |
| `action_sends` WORM smoke confirmed | ⚠️ Synthetic test passing (`test/server/action-sends-worm.test.ts`); production smoke pending operator step |
| ≥1 founder with ≥10 `draft_one_click` sends | ❌ PR-H merged 2 days ago; cohort usage data not yet available |
| Art. 7(3) re-confirmed by legal-compliance-auditor | ⚠️ This brainstorm's CLO assessment serves as the structural re-confirmation; calibration follow-up gates the post-ship audit |

**Bare-root grep false negative caught** (per learning `2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md`): the cited brainstorm path resolved correctly only when grepped from the worktree (at `origin/main` HEAD), not from the bare-repo root. All subsequent leader prompts substituted worktree-relative paths.

## What We're Building

A single PR-I (Approach A — full structural scope, atomic ship) containing:

1. **Canonical template registry** (code-static, mirroring `apps/web-platform/server/scope-grants/action-class-map.ts`'s literal-union + parity-test pattern). New file: `apps/web-platform/server/templates/template-registry.ts`. Replaces PR-H's placeholder `templateHashFor` at `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts:70-80` (`sha256(action_class:owning_domain:tier)`) with `sha256(canonical_template_body)`.
2. **`messages.template_id`** column (mig 053) — references the registry; `NOT NULL` with backfill of all existing `messages` rows to a `default_legacy` template_id before the constraint flips.
3. **`template_authorizations` WORM table** (mig 053) parallel to `scope_grants`. Columns: `id`, `founder_id`, `template_hash`, `action_class`, `authorized_at`, `expires_at` (NOT NULL, default `now() + interval '90 days'`), `soft_reconfirm_at` (NOT NULL, default `now() + interval '30 days'`), `max_sends` (NOT NULL, default `100`), `revoked_at`, `revocation_reason`, `grant_id` (FK `scope_grants(id)` ON DELETE RESTRICT). **`send_count` column dropped** per CTO — derive via `count(action_sends WHERE template_hash=...)` against the covering index at mig 051 L173. Keeps WORM invariant uniform.
4. **Partial UNIQUE** `(founder_id, template_hash) WHERE revoked_at IS NULL` (mirrors mig 051 L91-93 `scope_grants_active_unique` pattern). Closes the concurrent-INSERT race.
5. **`isTemplateAuthorized(client, founderId, templateHash)` predicate** at `apps/web-platform/server/templates/is-template-authorized.ts`. Two-probe ordering at `send/route.ts:155`: `isGranted` FIRST, then `isTemplateAuthorized`. Returns a discriminated `DenyReason` (`no_scope_grant` | `template_unauthorized` | `template_quota_exhausted` | `template_expired` | `template_revoked`).
6. **Three SECURITY DEFINER RPCs** in mig 053 (all with `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`): `authorize_template`, `revoke_template_authorization`, `anonymise_template_authorizations`. Writes (issuance, revocation, dsr_erasure cascade) go through these; reads use cookie-scoped RLS-protected SELECT.
7. **Revocation reasons enum (7 values, with `quarantine_retroactive` reserved in CHECK)**: `founder_revoked`, `quota_exhausted`, `expired`, `dsr_erasure`, `regulator_ordered`, `vendor_tos_revoked`, `policy_violation`. The 8th value `quarantine_retroactive` is reserved in the CHECK constraint but unused until PR-I+1.
8. **`account-delete.ts` cascade extension** — `anonymise_template_authorizations(p_user_id)` called **between** `anonymise_action_sends` (L211) and `anonymise_scope_grants` (L238), enforced by FK chain `template_authorizations.grant_id → scope_grants.id` ON DELETE RESTRICT.
9. **DenyReason channel surface** on `today-card.tsx`. Single deny-channel; deep-link to `/dashboard/settings/scope-grants` for `template_revoked` / `template_quota_exhausted`. No new modal — reuses the disabled-button + `title=""` pattern PR-H already shipped.
10. **`/dashboard/settings/scope-grants` page** — lists active `template_authorizations` for the founder, with a per-row "Revoke" button (writes `revocation_reason='founder_revoked'`).
11. **Legal artifacts:** Article 30 register **PA-16** "Template-authorized autonomous send authorizations"; **DPD §2.3(t)** "Template-authorization ledger" disclosing all 8 revocation reasons + cross-tenant non-cascade rule; **Privacy Policy §8.3** extension with template-level authorization + retroactive-reclassification right (reclassification UI ships PR-I+1; mention is forward-compatible). **No T&C amendment** (§3a Agent Command Authority already tier-agnostic). **AUP** gains one line listing `policy_violation` as a revocation outcome.

## Why This Approach (Approach A)

Three reasons single-PR atomicity wins over the two/three-slice alternatives:

1. The locked scope is **one user-facing capability** — authorize, deny with reason, revoke. Splitting forces operator-trust transitional states (e.g., a deny-without-reason half-state between split β and γ).
2. The legal artifacts (PA-16, DPD §2.3(t), Privacy §8.3) sign-off applies to the **bundle**, not pieces; CLO's Art. 7(3) defense rests on the predicate + bounds + revocation acting together.
3. PR-H precedent (single 11-agent brand-survival-extended review for the whole trust-tier expansion) is the model the cohort already trusts. PR-I should match.

## Why NOT NULL bounds (CLO override of original deferral framing)

Operator initially framed PR-I as "structural design only, bounds deferred." CLO rejected: NULL-bound rows are functionally a blanket consent waiver, re-opening the Art. 7(3) finding CLO closed in PR-H. **Resolved (operator 2026-05-21):** ship bound columns NOT NULL with provisional defaults (100 sends / 90-day hard expiry / 30-day soft re-confirm) sourced from the PR-H carry-forward. The calibration follow-up issue (filed at Phase 3.6) **tunes** these values once `≥1 founder ≥10 sends` evidence accumulates — it does NOT introduce bounds. This preserves Art. 7(3) at structural ship while honoring the operator's intent of not committing to calibration numbers prematurely.

## Why real per-template registry (CTO P0 design dependency lift into PR-I)

CTO flagged PR-H's `templateHashFor` as a placeholder collapsing all sends with the same (action_class, owning_domain, tier) into one bucket. Without a real registry, `template_authorizations` granularity = `scope_grants` granularity, and CLO's Art. 7(3) "authorize THIS template" defense weakens. **Resolved (operator 2026-05-21):** introduce the canonical template registry in PR-I rather than deferring to PR-I+2 retrofit. Larger PR-I (~5-7 days vs 3-5) but PR-I+1 doesn't have to migrate every existing authorization row to a new hash format.

## Why classifier-feedback deferred to PR-I+1 (CPO recommendation)

CPO: retroactive classifier-feedback has the highest mis-click blast radius (one wrong reclassification quarantines all future sends matching a template) and the lowest usage signal pre-cohort (no founder has flagged a misclassified send yet because no founder has sent yet). **Resolved (operator 2026-05-21):** PR-I+1 ships `/dashboard/audit` reclassification UI + `quarantine_retroactive` enum activation + QUARANTINE typed-confirm modal + `audit-sections.tsx` `action_sends` rendering. All primitives PR-I+1 needs (table, predicate, DenyReason channel) are pre-wired in PR-I; PR-I+1 is a UI-only add.

## Key Decisions

| Decision | Rationale |
|---|---|
| Approach A: single PR-I, full structural scope | Atomic ship of one user-facing capability; matches PR-H 11-agent review model. |
| Bounds NOT NULL with provisional defaults (100 / 30 / 90 / 30) | CLO Art. 7(3) override of operator's initial deferral framing; calibration follow-up tunes, doesn't introduce. |
| Real per-template registry in PR-I | Lift CTO P0 design dependency forward; avoids PR-I+2 retrofit migration. |
| Two-probe ordering: `isGranted` FIRST | Preserves existing fail-closed trust model; cheaper short-circuit; some tiers don't need template auth. |
| `send_count` column dropped — derive from `action_sends` count | Keeps WORM invariant uniform across `scope_grants`/`action_sends`/`template_authorizations`. |
| Revocation enum: 7 active + `quarantine_retroactive` reserved in CHECK | CLO's 3 additions (`regulator_ordered`, `vendor_tos_revoked`, `policy_violation`) distinguish un-revocability and Art. 5(2) attribution; cheaper to add at mig 053 than later. |
| `dsr_erasure` cascade is founder-scoped, NOT recipient-scoped | CLO: cross-tenant cascade on shared `recipient_id_hash` would violate Art. 5(1)(b) purpose limitation. |
| Classifier-feedback loop deferred to PR-I+1 | CPO: highest mis-click blast radius + no usage signal pre-cohort; primitives pre-wired. |
| Reuse `disabled` + `title=""` pattern from PR-H for deny surface | Single deny-channel; no new modal. Reduces UI test surface. |
| Reserve `quarantine_retroactive` in CHECK now | Avoids enum-widening migration in PR-I+1. |

## Open Questions

| Question | Owner | Note |
|---|---|---|
| `messages.template_id` backfill: do all existing rows resolve to a single `default_legacy` template, or do we attempt to retrofit historical sends into the new registry? | CTO (plan-time) | Recommend `default_legacy` — historical sends are already authorized via `action_sends`; new registry only governs future sends. |
| Should the canonical template registry support template versioning (`template_id` + `version`)? | CTO (plan-time) | Probably yes (mirrors action-class-map pattern of versioning via ADR), but defer concrete versioning ADR to first time we materially change a template. |
| Does Privacy §8.3 extension need legal-compliance-auditor sign-off before PR-I merge or can it ship inline? | CLO (PR review time) | PR-H precedent: legal text ships in same PR; auditor reviews via PR review, not pre-merge gate. |
| What's the production-smoke evidence path for "action_sends WORM smoke confirmed" — operator step or scheduled workflow? | CTO + operator | Recommend: add a workflow file (or extend `scheduled-*.yml`) that probes the WORM trigger on a synthetic row. Defer to plan-time. |
| Should `scope-grants` settings page surface BOTH `scope_grants` and `template_authorizations`, or split into two tabs? | CPO (plan-time) | Recommend: two tabs ("Action classes" / "Template authorizations") because revoke-semantics differ. |

## Domain Assessments

**Assessed:** Product, Engineering, Legal (the mandatory CPO+CTO+CLO triad under `USER_BRAND_CRITICAL=true`). Marketing, Operations, Sales, Finance, Support not spawned — signal not orthogonal to scope; carry-forward from #3244 PR-F/PR-G assessments applies.

### Product (CPO)

**Summary:** Single deny-channel via discriminated `DenyReason` returned to the today-card prevents "why did this fail?" opacity; reuse PR-H `disabled` + `title=""` pattern. Classifier-feedback's per-row reclassification affordance has mis-click blast radius too high pre-cohort — defer to PR-I+1 behind a `TypedConfirmModal` with phrase `QUARANTINE`. Scope-grants page lists active template authorizations with revoke button. **Tightest first slice = PR-I structural ship; PR-I+1 = audit reclassification UI.**

### Legal (CLO)

**Summary:** Structural ship is GO **conditional on** (a) NOT NULL bound columns with provisional defaults 100/30/90/30 at migration time (Art. 7(3) non-negotiable); (b) revocation enum expanded to 8 reasons including `regulator_ordered`, `vendor_tos_revoked`, `policy_violation` (distinct un-revocability + Art. 5(2) attribution); (c) `dsr_erasure` cascade founder-scoped only (Art. 5(1)(b) purpose limitation forbids cross-tenant cascade on shared `recipient_id_hash`); (d) Article 30 PA-16 + DPD §2.3(t) + Privacy §8.3 extension + AUP one-liner. No T&C amendment needed. `action_sends.template_hash` + `grant_id` verified present (mig 051 L113/L119).

### Engineering (CTO)

**Summary:** Schema mirrors `scope_grants` partial UNIQUE + `action_sends` WORM trigger patterns. Predicate two-probe: `isGranted` first (preserves trust model + short-circuits). **P0 design dependency lifted into PR-I: real per-template registry replacing PR-H placeholder.** `action_class_registry` referenced in #4078 step 3(a) **does not exist** (ADR-034 fixed registry as code-static); restate quarantining as a `template_authorizations.revoked_at` flip — no registry mutation. `dsr_erasure` cascade extends `account-delete.ts:200-251` between existing RPCs. **Migration 053** (052 taken by `052_multi_source_dedup.sql`). Risk ratings: template_hash placeholder (now HIGH→resolved by registry lift), action_class_registry non-existence (HIGH→resolved by quarantine restatement), partial-UNIQUE race (LOW), DSR cascade ordering (LOW), audit-page surface (deferred to PR-I+1). **Complexity: large** (~5-7 days dev assuming registry lift) under Approach A.

## Capability Gaps

| Gap | Domain | Why it matters | Resolution path |
|---|---|---|---|
| `action_class_registry` runtime-mutable table does not exist | Engineering | Issue body #4078 step 3(a) "flip `action_class_registry` default for that `template_hash`" assumes a runtime-mutable registry. ADR-034 fixed action-class as code-static (verified `apps/web-platform/server/scope-grants/action-class-map.ts:23-45` is literal-union). | Restated: quarantining writes a `template_authorizations` row with `revoked_at=now, revocation_reason='quarantine_retroactive'`. PR-I+1 only. |
| Real per-template canonical body registry does not exist | Engineering | `templateHashFor` at `send/route.ts:70-80` collapses all (class, domain, tier) sends into one bucket. Without a real registry, `template_authorizations` granularity collapses to `scope_grants` granularity. | Lifted into PR-I scope (decision above). New file `apps/web-platform/server/templates/template-registry.ts`. |
| `/dashboard/audit` page does not render `action_sends` rows | Engineering / Product | `apps/web-platform/components/audit/audit-sections.tsx` (231 lines) renders only `audit_byok_use` (lines 27-33). No `tier_at_send`, `template_hash`, or `clicked_at` references. PR-I+1 will be first to render. | Deferred to PR-I+1 with `quarantine_retroactive` reclassification UI. |
| `trust-tier-copy.ts` has no `revocation_reason` copy slot | Engineering / Legal | `apps/web-platform/lib/messages/trust-tier-copy.ts:6-42` has 4 keys, all tier-keyed. Revocation reason → founder-facing copy needs a new export. | Add `revocationReasonCopy` sibling export in PR-I. |
| Production smoke evidence path for "action_sends WORM smoke confirmed" | Engineering / Operations | Re-eval criterion #3 in #4078 body requires this; only synthetic test exists today. | Open Question (above) — likely scheduled workflow probe. Defer to plan-time. |

## Carry-forward to PR-I+1 (retroactive classifier-feedback)

For the PR-I+1 follow-up issue (filed at Phase 3.6):

- `/dashboard/audit` page extended to render `action_sends` rows via `audit-sections.tsx` with new `source="action_sends"` variant.
- Per-row "Reclassify…" affordance opening `TypedConfirmModal` with phrase = `QUARANTINE`, showing recipient_excerpt + content_excerpt + current tier + proposed tier + "this will quarantine N future sends matching this template" count.
- Activate the reserved `quarantine_retroactive` enum value in `template_authorizations.revocation_reason` CHECK.
- Mechanism: founder reclassification writes a `template_authorizations` row with `revoked_at=now(), revocation_reason='quarantine_retroactive'` — single write, no transaction. `isTemplateAuthorized` returns null on next probe, quarantining all future sends.
- Un-quarantine = re-grant flow at `/dashboard/settings/scope-grants` (no silent re-arming).

## Carry-forward to calibration follow-up (bound tuning)

For the calibration follow-up issue (filed at Phase 3.6):

- Tune `max_sends` default (100), `expires_at` default interval (90 days), `soft_reconfirm_at` default interval (30 days) once ≥1 founder has executed ≥10 `draft_one_click` sends without incident.
- Tuning is column DEFAULT update + optional existing-row UPDATE for in-flight authorizations — NOT introduction of bounds.

## User-Brand Impact

**Threshold:** `single-user incident` (carry-forward from #3244 umbrella, PR-F #3940, PR-G #3984, PR-H #4077; operator re-affirmed 2026-05-21 via "All" selection on the framing question — all three impact axes [trust breach / cross-tenant leak / silent send-block] flagged simultaneously).

**Artifact:** `template_authorizations` row + `isTemplateAuthorized` predicate output.

**Vector:** (a) Consent-waiver under Art. 7(3) if bounds aren't enforced. (b) Cross-tenant data leak via shared `recipient_id_hash` in classifier-feedback (deferred to PR-I+1; not in scope here). (c) Silent send-blocking via predicate denying without surfaced reason.

**Plan inherits this section verbatim** per plan skill Phase 2.6 carry-forward contract.

## Session Errors

| # | Error | Detection point | Fix |
|---|---|---|---|
| 1 | Bare-repo grep returned false negative for `2026-05-19-pr-h-trust-tier-external-classes-brainstorm.md` cited in #4078 body | Phase 0 premise probe | Re-grepped from worktree (post-Phase-3 cwd) per learning `2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md`. File present at worktree-relative path. |
| 2 | Issue #4078 body step 3(a) prescribes "flip `action_class_registry` default" — table does not exist (ADR-034 code-static) | Phase 0.5 CTO assessment | Restated quarantining mechanism in Capability Gaps; carry-forward to PR-I+1 spec uses the restated mechanism. |
| 3 | Original operator framing "structural-only, bounds deferred" was Art. 7(3) non-defensible (CLO ⚠️) | Phase 1.2 dialogue | CLO compromise accepted: NOT NULL with provisional defaults; follow-up = tune not introduce. |
| 4 | Issue #4078 body assumes `template_hash` has per-template granularity; PR-H shipped a (class, domain, tier) placeholder | Phase 0.5 CTO assessment | Lifted real per-template registry into PR-I scope (operator chose Approach A with registry). |

## ADRs to draft (PR-I scope)

1. **"Template registry is code-static, declared at producer call sites"** — mirrors ADR-034 lineage for action-class registry. Captures literal-union + parity-test pattern applied to templates.
2. **"Template authorization revocation reasons distinguish un-revocability classes"** — captures the 8-value enum (7 active + 1 reserved) with each value's un-revocability + Art. 5(2) attribution.
3. **"Two-probe predicate ordering: `isGranted` short-circuits before `isTemplateAuthorized`"** — captures the trust-model preservation argument + tier-applicability short-circuit.
