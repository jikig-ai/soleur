---
feature: agent-native-outbound-email
issue: 5325
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-15-feat-agent-native-outbound-email-pilot-plan.md
---

# Tasks: Agent-Native Outbound Email (Pilot Slice) — #5325

Phases ordered by dependency (contract before consumer). Tests-first (`cq-write-failing-tests-before`).

## Phase 0 — Blocking prereq: jikigai.com sending domain (infra)
- [ ] 0.1 Run the token-reach gate `curl …/zones/$CF_JIKIGAI_ZONE_ID/dns_records | jq .success` BEFORE any TF plan. If false → mint narrow `CF_API_TOKEN_JIKIGAI` + aliased provider.
- [ ] 0.2 Add `apps/web-platform/infra/resend-sending-bootstrap.sh` (generalize `resend-inbound-bootstrap.sh`; `mail.jikigai.com`, eu-west-1, sending-only).
- [ ] 0.3 Add `var.cf_jikigai_zone_id` (`variables.tf`) + 4 `cloudflare_record` resources (DKIM, SPF, MX-bounce, DMARC `p=quarantine`+`rua`) on `var.cf_jikigai_zone_id`.
- [ ] 0.4 Verify Resend domain-count tier impact; disclose paid-tier bump (ledger).

## Phase 1 — Data model (migration 104) [reworked per deepen-plan]
- [x] 1.1 (RED) RLS owner-SELECT + REVOKE writes + `auth.uid()` owner-pin + `email_suppression` upsert idempotency on `(owner_id, recipient_hash)` + `recipient_hash` stability + no-un-suppress tests. → `test/supabase-migrations/104-outbound-email.test.ts` (18, GREEN) + `test/migration-rpc-grants.test.ts` (PASS). Resume-verification caught a REVOKE-missing-`authenticated` defect; fixed.
- [x] 1.2 `104_outbound_email.sql` (+ `.down.sql`): **reuse `action_sends` (051)** for send-audit + body-hash approval (extend `action_class`); net-new = `email_suppression` only (`UNIQUE(owner_id,recipient_hash)`, upsert `ON CONFLICT DO NOTHING`, owner FK `ON DELETE RESTRICT`, `recipient_hash`=HMAC(`EMAIL_HASH_PEPPER`, normalize(email))). RLS SELECT-owner, REVOKE writes, RPCs `auth.uid()`-pinned + `SET search_path = public, pg_temp`. NO new `outbound_sends` table, NO un-suppress RPC. + `verify/104_outbound_email.sql` sentinel (carried fwd from 051/102). dev apply via tenant-integration CI; see `migration-checklist.md`.

## Phase 2 — Compliance chokepoint
- [x] 2.1 (RED) `outbound-compliance.test.ts`: C1–C4 absent → throw; suppressed → throw; unknown jurisdiction → EU/UK-strict; C3 = 6 discrete Art.14 predicates; CR/LF/U+2028/U+2029 in `to`/`reply-to`/`subject` → throw; internal/own-domain/role recipient → reject. (44 tests green)
- [x] 2.2 `outbound-compliance.ts`: pure C1–C5 validators (6 Art.14 predicates) + RFC-5322 header-field validator + recipient allow-list + deterministic HMAC `recipientHash`.
- [x] 2.3 `outbound.ts`: `sendCompliantOutbound()` — only outbound→`getResend()` path + only `mail.jikigai.com` FROM holder. Order: domain-verified precondition → validate C1–C5 → header → recipient → **body-hash approval match** (recompute vs gated-review `approvedBodySha256`; ADR-060 — `outbound_sends` WORM via `record_outbound_send`, NOT `action_sends`) → in-txn suppression recheck → Resend → record `outbound_sends` → Sentry-mirror (PII-free). `email_reply` recipient-from-`message_id` is enforced at the tool layer (Phase 3).
- [x] 2.4 (RED) sentinel test scoped to `apps/web-platform/server/**` excl. `**/*.test.ts`: (a) cold sending identity `@mail.jikigai.com` in one file; (b) `resend.emails.send` caller allowlist `{notifications.ts, cron-email-ingress-probe.ts, outbound.ts}`; (c) no non-`outbound.ts` file sends FROM the cold subdomain (typed `FromDomain` discriminant). 13 tests green; tsc clean.

## Phase 3 — Agent tools + tiers
- [x] 3.1 (RED) tools route through chokepoint; `email_reply` recipient derived server-side; refuse on chokepoint throw (mirror Sentry, generic error). `test/server/outbound-tools.test.ts` (6 green).
- [x] 3.2 Extend `buildEmailTriageTools` with `email_send`/`email_reply`/`email_suppress`. Handlers route through `sendCompliantOutbound`; `email_suppress` → `suppress_recipient` RPC (hashed). `email_reply` recipient from inbound item's `sender` (P0-3, ignores agent-supplied recipient).
- [x] 3.3 `tool-tiers.ts`: all three = `"gated"`; FR9-boundary comment updated (write tools now ship gated; status-transition boundary still holds).
- [x] 3.4 `agent-runner.ts`: registered the three tool names; tool-description prose updated. Existing FR9 boundary tests updated for the shipped write tools. tsc clean.

## Phase 4 — (deferred to #5331)
- [x] 4.1 Automated decline-matcher deferred (out of pilot scope, tracked #5331). Pilot suppression = manual/agent `email_suppress`; Touch-2 = manual re-trigger. No code in this PR.

## Phase 5 — Legal artifacts (docs)
- [x] 5.1 `2026-06-15-outbound-email-authority-lia.md` (Art.6(1)(f) Purpose/Necessity/Balancing; cold-contact + Art.14 + keyed-HMAC tradeoff). Partial-override note added to the 2026-06-11 LIA's send-authority re-evaluation trigger (PA-27 stays in force for inbound).
- [x] 5.2 Article 30 **PA-28** entry appended (next free id confirmed = 28; rebased origin/main first — no collision).
- [x] 5.3 ADR-060 (decision + 4 rejected alternatives incl. the action_sends-reuse fork; CTO-decided).

## Phase 6 — Gates & verification
- [ ] 6.1 `/soleur:gdpr-gate` against FR/TR (deepen-plan Phase 4.6 / work Phase 0); fold or track Critical findings.
- [ ] 6.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; `./node_modules/.bin/vitest run <paths>`.
- [ ] 6.3 PR body `Closes #5325`; DNS apply as `Ref` post-merge sub-task.

## Post-merge (operator/automated)
- [ ] P.1 Token-reach gate → `resend-sending-bootstrap.sh` → author record values → nested-Doppler `terraform apply`.
- [ ] P.2 After Resend `verified`, flip DMARC `p=quarantine` → `p=reject`.
- [ ] P.3 Forced staging gate-reject emits Sentry liveness event (discoverability_test, no ssh).
