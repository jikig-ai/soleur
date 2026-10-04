# Tasks: inbound email routing table

Plan: `knowledge-base/project/plans/2026-10-03-feat-inbox-provider-neutral-email-routing-plan.md`
Issue: #9458 (closes) | Deferred: #9459 | PR: #9456

## Phase 0 — Empirical gate

- 0.1 Send a direct-to-inbound canary and read it plus the existing `ops@` Sieve traffic back through the receiving API (address fields only); confirm `to` (and `received_for`) carry the `@inbound.soleur.ai` address.
- 0.2 Record the result in the plan's Research Insights. If no field carries the forwarding address, stop and re-scope to ADR-269 + evidence only.

## Phase 1 — Routing table + resolver (tests first)

- 1.1 Write failing tests: `email-triage-normalize-address.test.ts`, `email-triage-resolve-route.test.ts`, new cases in `resend-inbound-route.test.ts` and `email-on-received.test.ts` (no-recipients no-query, route match, ambiguous throw, lookup-error throw, replay safety, adopt path, pre-deploy claim).
- 1.2 `events.ts`: `normalizeInboundAddress`, optional `recipients`.
- 1.3 Webhook route: declare `to`/`received_for`, build normalized, deduped, sorted `recipients` (cap 50).
- 1.4 Migration `155_email_inbox_routes.sql` + `.down.sql` (composite FK, loose CHECK, unique index, RLS on with no policies, REVOKE, LAWFUL_BASIS and retention comments); re-check ordinal against `origin/main`.
- 1.5 `supabase/verify/155_email_inbox_routes.sql` (live-catalog assertions, FK rejection, cascade).
- 1.6 `resolve-inbound-route.ts` (owner validation moved from `email-on-received.ts`, memo keyed on the pair, throws on error/ambiguity).
- 1.7 `email-on-received.ts`: resolver inside `claim-insert`, return ids, later steps read `claim.ownerId`, adopt path uses the adopted row, pre-deploy claim uses env owner; keep `resetOwnerValidationMemo` export.
- 1.8 DSAR exclusion entry; `.service-role-allowlist` entry (repo-root-relative path); `.env.example` comment.

## Phase 2 — Observability

- 2.1 `scripts/email-route-status.sh` with `--resolve <addr>`.
- 2.2 Confirm lookup errors and ambiguous matches reach Sentry via Inngest exhaustion.

## Phase 3 — Documentation and registers

- 3.1 Read `model.c4`, `views.c4`, `spec.c4` in full; edit the `api -> supabase` (line 668) and `api -> resend` (line 666) edges; run the C4 tests and `c4-count-parity`.
- 3.2 ADR-269 (with hard preconditions) and ADR-066 Decision 4 pointer; verify ordinal against `origin/main`.
- 3.3 PA-27 note in `article-30-register.md`; run its validation.
- 3.4 Update #9459's body if anything else is deferred during work; PR body `Closes #9458`.

## Follow-ups (outside this PR)

- Send Resend the written questions (region, retention, delete semantics, pricing, sub-processors).
