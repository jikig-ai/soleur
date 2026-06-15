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

## Phase 1 — Data model (migration 104)
- [ ] 1.1 (RED) RLS owner-SELECT + REVOKE INSERT/UPDATE + RPC append-only tests (`outbound-chokepoint.test.ts`).
- [ ] 1.2 `104_outbound_email.sql` (+ `.down.sql`): flat append-only `outbound_sends` log + `email_suppression`. RLS SELECT-owner, REVOKE writes, SECURITY DEFINER RPCs `SET search_path = public, pg_temp`. NO multi-state machine.

## Phase 2 — Compliance chokepoint
- [ ] 2.1 (RED) `outbound-compliance.test.ts`: C1–C4 absent → throw; suppressed → throw; unknown jurisdiction → EU/UK-strict; C3 = 6 discrete Art.14 element predicates.
- [ ] 2.2 `outbound-compliance.ts`: pure C1–C5 validators; C3 = 6 element predicates.
- [ ] 2.3 `outbound.ts`: `sendCompliantOutbound()` — only outbound→`getResend()` path, only holder of `mail.jikigai.com` FROM literal; validate→throw→send→append→Sentry-mirror.
- [ ] 2.4 (RED) 2-invariant sentinel test: (a) FROM literal in one file; (b) `resend.emails.send` callers == allowlist `{notifications.ts, server/inngest/functions/cron-email-ingress-probe.ts, outbound.ts}`.

## Phase 3 — Agent tools + tiers
- [ ] 3.1 (RED) tools route through chokepoint; refuse without persisted `approved_at`.
- [ ] 3.2 Extend `buildEmailTriageTools` with `email_send`/`email_reply`/`email_suppress` (untrusted-content envelope).
- [ ] 3.3 `tool-tiers.ts`: all three = `"gated"`; update FR9-boundary comment (`:82-83`).
- [ ] 3.4 `agent-runner.ts`: register the three tools (grep real anchors at `:1315`/`:1533`); update tool-description prose.

## Phase 4 — (deferred to #5331)
- [ ] 4.1 Automated decline-matcher deferred. Pilot suppression = manual/agent `email_suppress`; Touch-2 = manual re-trigger.

## Phase 5 — Legal artifacts (docs)
- [ ] 5.1 `2026-06-15-outbound-email-authority-lia.md` (overturn 2026-06-11 deferral; inherit "if/when built" decisions; partial-override comment on source, keep OPEN for remainder).
- [ ] 5.2 Article 30 register entry (grep next free `PA-` id; document collision if any).
- [ ] 5.3 ADR-060 (one paragraph: decision + rejected alternative).

## Phase 6 — Gates & verification
- [ ] 6.1 `/soleur:gdpr-gate` against FR/TR (deepen-plan Phase 4.6 / work Phase 0); fold or track Critical findings.
- [ ] 6.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; `./node_modules/.bin/vitest run <paths>`.
- [ ] 6.3 PR body `Closes #5325`; DNS apply as `Ref` post-merge sub-task.

## Post-merge (operator/automated)
- [ ] P.1 Token-reach gate → `resend-sending-bootstrap.sh` → author record values → nested-Doppler `terraform apply`.
- [ ] P.2 After Resend `verified`, flip DMARC `p=quarantine` → `p=reject`.
- [ ] P.3 Forced staging gate-reject emits Sentry liveness event (discoverability_test, no ssh).
