---
title: "A static security lint that is case-sensitive or body-form-specific is false confidence; make it case/body-form-agnostic AND subordinate to a live-catalog runtime guard"
date: 2026-07-11
category: best-practices
tags: [security, sql, security-definer, migration-lint, two-tier-guard, false-confidence, rls, postgres]
issue: 6328
pr: 6337
module: apps/web-platform/test
---

# Learning: a green static security lint dead for a whole authoring style is worse than no lint

## Context

`#6306` was a class of bug: a service-role-only `SECURITY DEFINER` Postgres function
that retained Supabase's CREATE-time `anon`/`authenticated` EXECUTE grant (an
RLS-bypassing cross-tenant surface). A static lint
(`migration-rpc-grants.test.ts`, PR #3634) was supposed to catch it — and passed
**524/524 green**. `#6328` asked for a repo-wide class-level guard.

## What was wrong

The static lint's detector regex was **case-sensitive** (`CREATE … SECURITY DEFINER`,
no `i` flag) and **body-form-specific** (required `… SECURITY DEFINER … AS $$`, i.e.
`SECURITY DEFINER` *before* the dollar body). Two whole authoring styles escaped it:

1. **lowercase** `create … security definer` — the five lowercase migration files,
   including the exact #6306 functions.
2. **`AS $$ … $$ … SECURITY DEFINER`** body-form (dollar body *before* the modifier) —
   e.g. `017 increment_conversation_cost`, which had been silently unchecked for its
   entire life AND was missing its `pg_temp` search-path pin.

A green lint that is structurally blind to a valid authoring style is **false
confidence** — strictly worse than no lint, because it signals coverage that does not
exist.

## The fix (two-tier guard, ADR-112)

1. **Detection must be case-insensitive and body-form-agnostic.** Strip SQL noise
   (comments, dollar bodies, single-quoted strings) with a left-to-right state machine
   — NOT ordered `.replace()` passes (a `--` inside a dollar body is not a comment; a
   `$$` inside a line comment is not a dollar-quote). Then match the CREATE
   **declaration header** up to the body-start delimiter and stop; the header carries
   everything the assertions need (`security definer`, `returns trigger`, `set
   search_path`) and the body is irrelevant (its `EXECUTE 'GRANT …'` strings must not
   be mistaken for top-level grants).

2. **The static tier is SUBORDINATE, never coverage-bearing.** The authoritative guard
   is the runtime `rls-authz-fuzz` **AC8** gate (ADR-111) — live `pg_proc.proacl`
   introspection, immune to source-form blind spots by construction. State this
   explicitly in the ADR so a future PR cannot cite the cheap static tier to weaken the
   runtime one.

3. **Make the allowlist a single source of truth, not a hand-list.** The
   authenticated-callable allowlist IS the AC8 classification registry
   (`rls-fuzz/rpc-cases.ts`). Every entry cites its AC8 EXCLUDED/ATTACK classification
   *by identity*; the static tier can never bless a function AC8 has not classified.
   (The plan estimated ~8–12 hand-picked entries; the corpus reality is ~42 — importing
   the registry is both correct and drift-proof.)

4. **Add a non-vacuity / live-catalog-parity guard.** Assert the static detector
   matches every live `SECURITY DEFINER` fn from source (`staticallyUndetectedDefinerFns`
   vs `allSecurityDefinerFns`). Without it, "zero silent skips" is the static tier
   grading its own homework.

## Transferable rule

For any **static** security/compliance lint over source text:

- **Verify the detector against the ground truth**, not against its own green run. Here
  the ground truth was the live catalog; a static run that passes proves nothing about
  what it failed to *see*. Build detection empirically (run the detector over the real
  corpus and reconcile every classification) rather than trusting a hand-enumeration.
- **A hardened detector surfaces pre-existing gaps** (`017`'s missing `pg_temp` pin) —
  triage them per `wg-when-an-audit-identifies-pre-existing` (allowlist + document,
  don't expand feature scope).
- **When a runtime guard exists, make the static tier explicitly subordinate** and tie
  its coverage to the runtime enumeration, so the fast tier is fast-feedback, not a
  false backstop.

See ADR-112, `apps/web-platform/test/migration-lint/definer-grants.ts`.
