---
title: Two-tier SECURITY DEFINER grant-hygiene guard (runtime AC8 authoritative, static lint subordinate)
status: accepted
date: 2026-07-11
amends: [ADR-101, ADR-111]
supersedes: none
issue: 6328
related: [6306, 6318, 6256, 6332]
related_adrs: [ADR-101, ADR-111]
brand_survival_threshold: aggregate pattern
---

# ADR-112: Two-tier SECURITY DEFINER grant-hygiene guard

> **Ordinal.** ADR-112 is the next free ordinal against `origin/main` (highest existing is ADR-111). Provisional until `/ship` — the ADR-Ordinal Collision Gate re-verifies against `origin/main` at merge and after every Phase-7 sync; on collision, sweep `grep -rn 'ADR-112' knowledge-base/project/{plans,specs}/feat-one-shot-6328-definer-grant-hygiene/` + this file + the reciprocal cross-refs in ADR-101/ADR-111 in the same edit.

## Context

The `#6306` defect class is a **service-role-only `SECURITY DEFINER` function that
retains Supabase's CREATE-time `anon`/`authenticated` EXECUTE grant** — an
RLS-bypassing cross-tenant IDOR / disclosure surface. Postgres grants `EXECUTE` to
`PUBLIC` on every new function by default, and Supabase's `ALTER DEFAULT PRIVILEGES`
additionally grants `anon`/`authenticated`/`service_role`; a migration that runs only
`REVOKE … FROM public` leaves the explicit `anon`/`authenticated` grants live, and a
`DEFINER` function's owner rights then bypass base-table RLS for those roles.

Migration `128` (PR #6318) revoked the residual grants on the **five known**
instances. Issue `#6328` asks for a **class-level** guard against future/undetected
instances, proposing **(a)** an `ALTER DEFAULT PRIVILEGES` baseline migration or
**(b)** a migration-lint CI gate — deferring the choice until **#6256** (the runtime
RLS/authz-fuzz harness, ADR-111) merged.

That re-eval condition is now satisfied. Two facts reframe the decision:

1. **A durable, runtime, live-catalog class-level guard already exists** — the
   `rls-authz-fuzz` **AC8** gate (`.github/workflows/rls-authz-fuzz.yml`, ADR-111).
   It enumerates every `SECURITY DEFINER` function `authenticated` may EXECUTE **from
   the live `pg_proc.proacl` catalog** (`catalog.ts:securityDefinerAuthenticatedFns`)
   and reds until each is classified and proven to deny a cross-tenant caller. Being
   live-catalog-driven it is immune to source-form blind spots and already closes the
   issue's "no-grants-at-all" concern. `#6332` un-baselined the #6306 `test.fails`, so
   AC8 enforces on `main` today.
2. **The pre-existing _static_ sibling lint was false-confidence.**
   `apps/web-platform/test/migration-rpc-grants.test.ts` (PR #3634) was
   case-sensitive and `AS $$`-body-form-only, so it silently passed over the five
   lowercase `security definer` files (incl. the #6306 functions and
   `handle_new_user`) **and** over `AS $$ … $$ … SECURITY DEFINER` body-forms. A green
   lint dead for whole authoring styles is worse than no lint.

## Decision

Adopt a **two-tier guard** and record which tier is authoritative:

1. **Runtime AC8 (`rls-authz-fuzz`) is the AUTHORITATIVE durable class-level guard.**
   It computes net grant state exactly from the live catalog, per-migration-PR. This
   ADR states that authority explicitly so a future PR cannot cite the cheaper static
   tier to weaken AC8.

2. **The static migration-lint is a SUBORDINATE, no-stack, fast pre-filter — advisory
   fast-feedback, NEVER coverage-bearing.** It is hardened (this PR) to be
   case-insensitive and body-form-agnostic (`test/migration-lint/definer-grants.ts`),
   and asserts a **corpus-wide revoke-union of `{public, anon, authenticated}`** over
   forward migrations only (type-precise signatures, DROP-without-recreate excluded,
   `RETURNS TRIGGER` excluded — trigger functions have no `GRANT EXECUTE` path). It
   deliberately does **not** re-implement `has_function_privilege()`; the
   revoke-then-`DROP`+`CREATE`-without-re-revoke residual is AC8's to own.

3. **The authenticated-callable allowlist IS the AC8 classification registry.** The
   static lint exempts a `DEFINER` fn from the revoke-union only if it appears in
   `test/rls-fuzz/rpc-cases.ts` (`ATTACK_SQL ∪ EXCLUDED ∪ KNOWN_EXPOSURES`). This is a
   single source of truth: every allowlist entry cites its AC8 EXCLUDED/ATTACK
   classification **by identity**, and the static tier can never bless a function AC8
   has not classified. A new authenticated-callable `DEFINER` fn added without an AC8
   classification therefore reds BOTH tiers.

4. **A non-vacuity / live-catalog-parity guard ties the static detected-set to AC8's
   live enumeration** (`allSecurityDefinerFns` → `staticallyUndetectedDefinerFns`, run
   in the `rls-authz-fuzz` job). It reds if the static detector under-detects relative
   to the live catalog, so "zero silent skips" is real, not self-referential.

5. **Option (a) `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE … FROM anon, authenticated`
   is DEFERRED** as optional defense-in-depth pending a **live role-scope probe**
   (Supabase applies ADP under `supabase_admin`; a mis-scoped ADP is a silent no-op
   and would itself be false-confidence — `hr-verify-repo-capability-claim-before-assert`).
   Tracked separately in **#6340**.

## Consequences

- **Accepted residual (named).** A `DEFINER` function created **out-of-band** (SQL
  console / hotfix, not via a migration file) is invisible to BOTH the static lint (no
  migration file to scan) AND AC8 (its stack is built from `migrations/**`). The
  compensating control is `AP-002` (no-SSH state mutation) + Terraform-only
  provisioning, which prohibits that path; the deferred ADP baseline is the only
  control that would additionally close it, and its re-eval fires if the no-SSH policy
  is relaxed. Only a live-prod `has_function_privilege` sweep would then find such a
  function.
- **Accepted residual (shared with AC8).** A function deliberately mis-classified into
  `EXCLUDED` with a bogus rationale escapes both tiers; this is inherent to any
  allowlist and is the same escape hatch AC8 already carries — caught by review, not
  by either automated tier.
- **Accepted residual (overload name-collision).** The authenticated-callable allowlist
  is keyed by bare `proname` (mirroring AC8's `pg_proc.proname` keying). A NEW
  service-role-only DEFINER **overload** whose name collides with an existing AC8 entry
  (e.g. a 3-arg `is_workspace_owner` added beside the classified 2-arg one) is exempted
  from the static revoke-union by name — and AC8 does not backstop it either, since its
  coverage gate is name-keyed and its ATTACK case drives only the original signature.
  The overload's `search_path` pin IS still checked (per-`(name,signature)` identity),
  so it is not fully unchecked. Closing this fully requires AC8 to drive attacks
  per-signature; deferred with AC8's name-keying. Net grant state remains AC8's
  authoritative domain.
- **Accepted residual (guard shares fate with its job).** The non-vacuity parity guard
  (`staticallyUndetectedDefinerFns`) and AC8 both live in the `rls-authz-fuzz` job; if a
  future PR deletes/disables that workflow, AC8 and its parity guard vanish together,
  leaving only the explicitly-non-authoritative static tier green. Compensating control:
  `rls-authz-fuzz` must remain a **branch-protection required check**; the ordinary
  vitest floors assert the static detector runs, NOT that AC8 does.
- **Convention cross-link.** The authenticated-callable allowlist extends **ADR-101**'s
  `GRANT EXECUTE … TO authenticated` client-callable-RPC convention.

## Alternatives considered

- **Amend ADR-111 instead of a new ADR.** Rejected: ADR-111 has no YAML frontmatter, so
  an appended section produces no `amended_by` edge and is undiscoverable from ADR-101
  (where future client-callable-RPC authors look). ADR-084 set the precedent of
  rejecting amend for an orthogonal cross-cutting invariant. ADR-112 carries
  `amends: [ADR-101, ADR-111]` with reciprocal cross-refs.
- **A from-baseline "ordered replay" static model.** Rejected (code-simplicity): it
  would re-implement `has_function_privilege()` (AC8 already does this exactly) and
  bake in the same unproven CREATE-time-inheritance premise option (a) is deferred for.
  The revoke-union requires an *explicit* corpus REVOKE regardless of the CREATE-time
  default — a strictly better basis for a pre-filter.
- **Adopt option (a) now.** Deferred (not rejected): valuable defense-in-depth, but
  needs a live role-scope probe first, and the one residual it uniquely closes
  (out-of-band creation) is already compensated by AP-002 + Terraform-only provisioning.

## C4 impact

None. No external actor, external system, container/data-store, or actor↔surface
access relationship changes — no schema, table, or RPC is added and no runtime grant
is mutated (option (a) is deferred). Standard C4 does not model CI gates / security
controls as elements. The `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`
files are unchanged.
