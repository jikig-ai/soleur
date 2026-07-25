---
title: Action-class registry — code-static literals + enum-absence for per-command-ack class
status: accepted
date: 2026-05-19
related: [3244, 4077, 4078]
related_adrs: [ADR-030, ADR-033-per-tenant-scope-grants]
related_plans:
  - knowledge-base/project/plans/2026-05-19-feat-trust-tier-pr-h-external-classes-plan.md
brand_survival_threshold: single-user incident
---

# ADR-034: Action-class registry — code-static literals + enum-absence

> Numbering note: ADR-033 was claimed by three concurrent PRs on the same day (per-tenant scope grants, runtime JWT signing substrate, Inngest cron via child_process). This ADR adopts ADR-034 as the next free number. Plan-review reserved ADR-035 as a sibling but ultimately merged both sections into this single record per simplicity #3.

## Context

PR-F (#3940, MERGED 2026-05-17) introduced an action-class vocabulary: `ACTION_CLASSES = ["finance.payment_failed"] as const` plus the `ActionClassTier` 3-value union and the `ACTION_CLASS_DEFAULTS` map. PR-G (#3984, MERGED 2026-05-19) added the `scope_grants` WORM ledger and the founder-callable RPC + UI for grant/revoke. PR-H (#4077) extends `ACTION_CLASSES` to 11 entries spanning four categories (finance, external_low_stakes, external_brand_critical, infra) and adds the 4th tier value `auto_with_digest`. The umbrella plan #3244 §3.4 calls for a **5th class**: money/legal/credentials actions that must require per-command-ack regardless of tier.

Two architectural questions emerge with the widening:

1. **How are action classes classified at producer call sites?** A runtime classifier introduces a new failure mode (classifier wrong → wrong tier → wrong consent boundary). A config-file registry separates the literal from the producer code (a `inngest.send` consumer could not be type-checked against the producer's chosen class). A DB-table registry adds a roundtrip on every webhook.

2. **How is the 5th class (per-command-ack) enforced?** Adding a `requires_per_command_ack: true` flag to the registry creates a class of subtle bug where a flag drift (forgetting to set it when adding a class) silently downgrades safety. The action could still flow through `isGranted` and a tier-decision branch, with the per-command-ack gate as an additional check after.

The brand-survival threshold (`single-user incident`) makes the safety boundary at the type-system layer attractive: every TS compilation failure is a forced human review. Hard rule `hr-menu-option-ack-not-prod-write-auth` codifies that money/legal/credentials actions never live as menu options; per-command-ack is non-optional.

## §1 — Decision: code-static literal-union registry with narrowed-union producer carveout

`ACTION_CLASSES` is a frozen `as const` array literal at `apps/web-platform/server/scope-grants/action-class-map.ts`. `ActionClass = (typeof ACTION_CLASSES)[number]` is the literal union derived from it. `ACTION_CLASS_DEFAULTS` and `ACTION_CLASS_CATEGORY` are `Record<ActionClass, ...>` (TS-enforced parity — adding a class without an entry in either map fails `tsc --noEmit`). Every producer that calls `isGranted(...)`, `isDenied(...)`, or `inngest.send({data: {action_class: ...}})` declares a typed literal at the call site:

```ts
// Single-class producer (current Stripe webhook):
const grant = await isGranted(supabase, founderId, "finance.payment_failed");

// Multi-class producer (future Bluesky reply adapter, Arch F2 carveout):
const actionClass: ActionClass = source === "soleur_handle"
  ? "external.brand_critical.bluesky_reply_soleur_handle"
  : "external.low_stakes.bluesky_reply_personal";
const grant = await isGranted(supabase, founderId, actionClass);
```

The narrowed-union expression is acceptable; the lint test (`apps/web-platform/test/lint/action-class-typed-literals.test.ts`) accepts ternary-of-literals and assignments-from-`ActionClass`-typed-variables, rejects `as string` / `as any` casts.

**Rejected alternatives:**

- **Runtime classifier (LLM or rule-based):** Adds a moving boundary. Misclassification is recoverable in principle but the cost of a single wrong tier on a `single-user incident` threshold rules it out.
- **Config-file registry (YAML/JSON):** `inngest.send` consumers cannot be type-checked against the producer's chosen class because the literal is in a file the compiler doesn't see. Bug class: typo in producer-side string passes TS but mismatches the consumer's expectation; webhook silently no-ops.
- **DB-table registry:** Roundtrip per webhook. Producer would have to read the table before `inngest.send` to know which classes are valid — making the registry the slow path on every event. Operational + reliability cost.

**Enforcement layers:**

1. **`tsc --noEmit`** (canonical enumerator per learning C2) — every `isGranted` / `isDenied` / `inngest.send` consumer sees the literal-union signature. A typo at a producer (`finance.payment_faild`) fails compilation.
2. **`action-class-exhaustive.test.ts`** (vitest) — `satisfies Record<ActionClass, ...>` parity for `DEFAULTS` and `CATEGORY` maps, switch-with-`_exhaustive: never` rail.
3. **`action-class-typed-literals.test.ts`** (rg-based lint) — rejects `as string` / `as any` casts at call sites; fixture pass/fail cases validate the regex discriminates correctly.

## §2 — Decision: 5th class (money/legal/credentials) enforced by ENUM-ABSENCE plus DB CHECK regex

`payment.*`, `legal.*`, `auth.*` action classes are **absent** from `ACTION_CLASSES`. There is no `requires_per_command_ack: true` flag in the registry. The shape of the type system is the enforcement:

- `payment.refund` is not assignable to `ActionClass` → `isGranted(client, id, "payment.refund")` fails compilation.
- `inngest.send({data: {action_class: "legal.dpa_sign"}})` fails compilation (when consumer reads the field via the typed `ActionClass`).
- Adding a `payment.*` class is a deliberate code change that flips it from compile-error to compile-allowed — a forced review surface.

**Defense-in-depth (Arch F3):** both `scope_grants` and `action_sends` carry DB CHECK constraints rejecting `action_class !~ '^(payment|legal|auth)\.'`. This closes two indirect routes that the TS layer cannot see:

1. **RPC-from-JSON-payload:** if a future code path passes JSON to a parameterized RPC that constructs the action_class from user input, the CHECK fires at the DB.
2. **Config-file imports:** if action_class strings ever land in a config (YAML loaded at boot, env var, etc.), the CHECK is the gate of last resort.

Hard rule lineage: `hr-menu-option-ack-not-prod-write-auth`. The 5th class lives at the per-command-ack point of authorization — the founder typing the exact command — never as a menu option, never as a tier.

**Rejected alternatives:**

- **Boolean flag `requires_per_command_ack` on the registry entry:** silent-downgrade risk. Forgetting the flag means the class becomes a menu option with `draft_one_click` default. A test could catch this for the in-registry cases, but the TS type system cannot prove a flag's truth across the call graph.
- **Allowlist of "OK for autonomous" + denylist of "needs per-command-ack":** two-list maintenance burden. The TS type system can prove ONE thing (presence in the literal union) but not the conjunction of two flags.
- **Runtime check in `isGranted`:** the call site is where the typo lives; pushing the check into the predicate makes the regression silent until the per-command-ack screen renders (or fails to render).

## §3 — Decision: `SOLEUR_FR5_ENABLED` kill-switch gates producer-side only

`SOLEUR_FR5_ENABLED` (the cohort feature flag for the autonomous-draft runtime, introduced in PR-F #3940) short-circuits **producer-side** integration points: the Stripe webhook (and future producers) check the flag before `inngest.send`. **Consumer-side** routes — `app/api/dashboard/today/[id]/{send,edit,discard}` plus the `/dashboard/audit` viewer — remain live regardless of the flag's value.

Rationale: a founder with existing in-flight drafts must always be able to Send / Edit / Discard them, even if the platform-wide flag is flipped off. The flag controls whether *new* drafts are created, not whether existing drafts can be archived. This codifies the orphan-substrate question raised at Arch F8 plan-review.

When PR-I (#4078) lands the digest emitter, it gates on `SOLEUR_FR5_ENABLED` at the Inngest scheduled function entry (producer-side) — the daily digest does NOT fire when the flag is off. The dashboard digest card render path (consumer-side) gracefully handles "no recent digest available."

## Consequences

**Positive:**

- TS compile-time check is the FIRST forced human review for every new action class.
- DB CHECK is the LAST-line guard against indirect routes the type system cannot see.
- The 5th class needs no flag, no boolean, no maintenance — its safety is the SHAPE of the union.
- Producers and consumers share a single source of truth for the literal vocabulary.

**Negative:**

- Adding a new action class requires editing `ACTION_CLASSES` + `ACTION_CLASS_DEFAULTS` + `ACTION_CLASS_CATEGORY` + the exhaustiveness switch + (sometimes) the lint-test cardinality assertion. Four files for a new entry. This is intentional friction.
- Cross-tenant / cross-environment grant migrations require careful sequencing if the type union changes shape between deploys. Mitigated by the bounded backfill on `messages.action_class` (mig 051) and by the producer-side fallback to `ACTION_CLASS_DEFAULTS` when the event envelope lacks the field.
- The `narrowed-union` carveout for multi-class producers (Arch F2) requires future producers to write the ternary inline rather than store the literal in a variable typed as `string`. The lint test enforces this but the failure message must be clear.

## Implementation references

- Registry: `apps/web-platform/server/scope-grants/action-class-map.ts`
- Predicate: `apps/web-platform/server/scope-grants/is-granted.ts`
- Migration: `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql` (CHECK constraints at scope_grants + action_sends)
- Exhaustiveness test: `apps/web-platform/test/server/scope-grants/action-class-exhaustive.test.ts`
- Lint test: `apps/web-platform/test/lint/action-class-typed-literals.test.ts`
- Plan: `knowledge-base/project/plans/2026-05-19-feat-trust-tier-pr-h-external-classes-plan.md`
