# Tasks — feat: waitlist Buttondown client-IP hardening

Derived from `knowledge-base/project/plans/2026-06-11-feat-waitlist-buttondown-client-ip-plan.md`.

Lane: cross-domain (fail-closed default — no spec.md `lane:` field).

## Phase 1: Setup / Preconditions

- [ ] 1.1 Confirm worktree on branch `feat-one-shot-waitlist-buttondown-client-ip`; baseline green: `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-waitlist-subscribe.test.ts`
- [ ] 1.2 Confirm `node:net` `isIP` import compiles in the package: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (baseline)

## Phase 2: Core Implementation

- [ ] 2.1 `apps/web-platform/app/api/waitlist/waitlist.ts`
  - [ ] 2.1.1 RED: add failing tests first (see 3.1–3.4) per `cq-write-failing-tests-before`
  - [ ] 2.1.2 Add `isIP` import + module-private `plausiblePublicIp()` (v4 private/reserved exclusion, v6 loopback/unspecified/link-local/ULA exclusion, v4-mapped-v6 strip) — no logging in the helper
  - [ ] 2.1.3 Widen `subscribeToWaitlist(email, clientIp?)`; conditional `...(ipAddress ? { ip_address: ipAddress } : {})` in POST body; `type` stays omitted
  - [ ] 2.1.4 Update doc comment: firewall re-escalation rationale, never-log IP+email discipline, NO `X-Buttondown-Bypass-Firewall`
- [ ] 2.2 `apps/web-platform/app/api/waitlist/route.ts`
  - [ ] 2.2.1 Pass existing line-41 `ip` through: `await subscribeToWaitlist(email, ip)`; one-line header-comment update

## Phase 3: Testing

- [ ] 3.1 Extend happy-path test (no `cfConnectingIp`): assert no `ip_address` key; exact key set `["email_address","tags"]`
- [ ] 3.2 New: public IPv4 `203.0.113.7` → `ip_address` forwarded; exact key set `["email_address","ip_address","tags"]`; no `type`
- [ ] 3.3 New: public IPv6 `2001:db8::1` → forwarded
- [ ] 3.4 New: private `10.0.0.1` and garbage `not-an-ip` → omitted, subscribe still 200
- [ ] 3.5 GREEN: `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-waitlist-subscribe.test.ts`
- [ ] 3.6 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] 3.7 AC greps: AC4 (`grep -c 'cf-connecting-ip' apps/web-platform/app/api/waitlist/route.ts` = 1), AC5 (`git grep -il 'bypass-firewall' -- 'apps/**'` exits 1), AC6 (no new log/Sentry lines in diff)

## Phase 4: Ship

- [ ] 4.1 PR body: GDPR parity note (PA6, privacy policy §4.6/§5.3, DPD §2.3(e)/§6.3; SCCs Module 2; restores embed-form parity — no new disclosure surface)
- [ ] 4.2 No post-merge operator steps (release pipeline redeploys on merge); optional automated live probe per plan
