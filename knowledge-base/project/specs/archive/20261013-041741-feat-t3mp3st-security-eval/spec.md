---
feature: t3mp3st-security-eval
date: 2026-07-09
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
brainstorm: knowledge-base/project/brainstorms/2026-07-09-t3mp3st-security-eval-brainstorm.md
---

# Spec: Scoped runtime authz/RLS-fuzz harness (T3MP3ST technique harvest)

## Problem Statement

Soleur's security stack is entirely static / diff-time (`security-sentinel` LLM review,
`semgrep-sast` deterministic SAST, `infra-security` config-audit, `gdpr-gate`). None of it
proves *runtime exploitability*: nothing drives a hostile authenticated client against a
running app to test whether one tenant can reach another tenant's rows (IDOR, cross-tenant
read/write, role confusion). The tenant-isolation work actively shipping (verify/068
jti-deny per-table, RLS) is verified only by asserting the policy SQL exists — never by
exercising it at runtime. T3MP3ST (an AGPL-3.0 autonomous offensive harness) demonstrates
the technique but cannot be adopted: ~95% of its arsenal is inapplicable, it carries
blast-radius/supply-chain/cost risk, and its AGPL license violates Soleur's
MIT/BSD/Apache-2.0-only "no GPL/AGPL contagion" policy.

## Goals

- G1: A small, **deterministic** harness that drives tenant-B's JWT against tenant-A's
  rows across the RLS-protected tables and asserts every cross-tenant access is denied.
- G2: Runs against a **local disposable Postgres with production RLS policies loaded** —
  no live/rented infra, no provider-ToS exposure.
- G3: Borrows T3MP3ST's kill-chain taxonomy / authz-attack technique catalog as
  **concepts only** — zero AGPL source copied.
- G4: Doubles as runtime proof of the in-flight tenant-isolation work (verify/068).

## Non-Goals

- NG1: Adopting/vendoring/running T3MP3ST itself, or copying any AGPL source.
- NG2: Any scan/exploit traffic to Hetzner/Supabase/Cloudflare/Vercel/GHCR/Doppler
  (rented/shared infra) — even our own accounts.
- NG3: Any offensive capability exposed to Soleur Users (hard-dropped; counsel-gated).
- NG4: The user-facing defensive posture-check (separate parked issue).
- NG5: A full open-ended autonomous exploitation agent (blast radius + cost + supply chain).

## Functional Requirements

- FR1: Seed ≥2 synthetic tenants (A, B) with synthetic secrets into a local disposable
  Postgres pre-loaded with the production RLS policies.
- FR2: Mint a valid authenticated JWT for tenant B (claim
  `app_metadata.current_organization_id = B`), matching the app's real token shape.
- FR3: For each RLS-protected table, attempt SELECT/INSERT/UPDATE/DELETE of tenant-A rows
  using tenant-B's token; assert every attempt is denied by RLS.
- FR4: Include JWT-tampering / role-confusion / `org_id` swap cases (the technique subset
  harvested from T3MP3ST's authz/IDOR taxonomy).
- FR5: Emit a deterministic pass/fail report enumerating each (table, operation, verdict).
- FR6: A single leaked cross-tenant access = hard FAIL with the offending table/op named.

## Technical Requirements

- TR1: **Pin scope by identity** (`workspace_id`/`org_id` = tenant), never by session
  state or "current" resolvers — cross-tenant-leak vectors hide behind session-inferred
  scope (learning `security-issues/2026-05-29-identity-pinned-workspace...`).
- TR2: Environment carries **zero real credentials** — synthetic secrets only; egress
  default-deny to everything except the local target.
- TR3: Hard **token-budget cap + wall-clock timeout + kill switch** on any run.
- TR4: Deterministic + reproducible so it can run in CI (no LLM in the assertion path).
- TR5: License hygiene — no AGPL source; harvested taxonomy documented as concepts with
  provenance noted, not copied verbatim.
- TR6: Capture an ADR for the harness + disposable-sandbox topology (new security surface
  + infra pattern) per CTO architecture-decision detection.

## Open Questions

- OQ1: CI-gated per-PR slice vs. operator-run pre-launch check (sequencing vs. #673/#2719).
- OQ2: Full kill-chain taxonomy harvest vs. authz/IDOR/RLS subset only.
- OQ3: Local-Postgres-with-prod-policies provisioning mechanism (migration replay into a
  throwaway container).

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-07-09-t3mp3st-security-eval-brainstorm.md`
- CLO legal-threshold assessment (session, 2026-07-09) — AGPL clean internal; user-facing STOP.
- ADR-064 (live-verify), ADR-075/ADR-079 (agent sandbox) — adjacent runtime/isolation patterns.
- `plugins/soleur/agents/engineering/review/security-sentinel.md` (workspace-boundary R1–R6).
