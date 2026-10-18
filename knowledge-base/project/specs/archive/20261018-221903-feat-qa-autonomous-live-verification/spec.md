---
title: Autonomous live verification (Soleur drives its own live session)
feature: feat-qa-autonomous-live-verification
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-16-autonomous-live-verification-brainstorm.md
pr: 10446
issue: 10449
---

# Spec: Autonomous live verification

## Problem Statement

After deploys and flag flips, Soleur hands the operator a live step ("ask the Concierge in the web app to fetch a
page; only you can start that session"). The post-deploy harness (ADR-064) exists but drives one hardcoded flow,
cannot start an agent/Concierge session, and has no flag-segment-aware test org. The `postmerge` skill also still
says the gate is report-only while CI has blocked since 2026-06-18.

## Goals

- G1: A live flow that starts a Concierge session in the synthetic workspace and asserts the downstream effect
  (e.g. egress-audit-ingest event in Sentry/DB), with zero operator action.
- G2: `run.ts` runs declared flow specs, so a new live check is a file, not a harness rewrite.
- G3: Skills and rules stop treating "run a live session" as operator-only.
- G4: A written `qa-fixtures` contract so a user's own app can opt in later.

## Non-Goals

- A new QA agent or skill.
- Creating per-run orgs/accounts in prod; customer-prod verification; automating CAPTCHA/OAuth/2FA/payment.
- The generic manifest parser and the scheduled reaper (deferred issues).
- Migrating `flag-set-role` to staged approval (#9387).

## Functional Requirements

- FR1: Flow-spec runner in `apps/web-platform/scripts/live-verify/flows/` with the existing rail flow ported.
- FR2: Concierge URL-fetch flow; assertion via an observability read and/or DB read; marker `lv-<runid>`.
- FR3: The synthetic workspace is a flag-segment member by operator flip (`--org`), never by the verifier.
- FR4: Marker-based teardown as the user's own RLS session with a zero-residue read-back.
- FR5: Unautomatable steps return `CANT-RUN:operator-only:<capability>` and file an issue; never PASS/skip.
- FR6: `postmerge` wording corrected to blocking; `flag-set-role`, `ship`, `qa` point at the live-verify flow
  instead of an operator hand-off; AGENTS rule wording amended per `cq-agents-md-tier-gate` at plan time.
- FR7: `qa-fixtures` contract spec + ADR (personas, seed entry, auth mode, flag keys, base URLs, teardown,
  assertion sources, `unautomatable`).

## Technical Requirements

- TR1: Keep ADR-064 invariants: UID allowlist before sign-in, zero `scope_grants` (unless amended), redact-before-
  persist, own-session teardown, `CANT-TEARDOWN` escalates.
- TR2: Secrets only via Doppler; no service-role key in the runner.
- TR3: Synthetic email on a controlled domain with reserved prefix + nonce; mail suppressed; Stripe test mode only.
- TR4: ADR-064 amendment + new ADR; Article 30 register line; `gdpr-gate` before first ship.
- TR5: Gate stays `postmerge` tri-state `PASS | FAIL | CANT-RUN:<reason>+#issue`; empty fails closed.

## Open Questions

See brainstorm. Blocking one: whether Concierge URL-fetch is allowed for a principal with zero `scope_grants`.
