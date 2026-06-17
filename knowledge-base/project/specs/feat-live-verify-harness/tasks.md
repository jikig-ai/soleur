---
feature: live-verify-harness
issue: 5452
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-17-feat-live-verify-harness-plan.md
---

# Tasks: live-verify-harness

## Phase 1: Synthetic prd principal (IaC + seed)
- [ ] 1.1 `apps/web-platform/infra/live-verify.tf` — `random_password.live_verify_user` → `doppler_secret.live_verify_user_password` (config="prd", masked), mirror `github-app.tf:67-81`.
- [ ] 1.2 `apps/web-platform/scripts/seed-live-verify-user.sh` — port FULL seed flow (auth upsert + `public.users` ladder + `api_keys` row); gate `DOPPLER_CONFIG=="prd"` + service_role JWT; derive ref from JWT (accept `api.soleur.ai` custom domain); email `live-verify@soleur.ai`; echo created UID.
- [ ] 1.3 `apps/web-platform/scripts/seed-live-verify-user.test.sh` — refuses non-prd / non-service_role / wrong-ref.
- [ ] 1.4 `apps/web-platform/scripts/bootstrap-live-verify.sh` — one-shot terraform apply -target + seed (AC12 owner).

## Phase 0: gdpr-gate (ADR-049 armed clause)
- [ ] 0.1 Run `/soleur:gdpr-gate` against the plan (live-origin + real-creds re-trigger per ADR-049:62-63); record output in PR (AC6b).

## Phase 2: Harness core
- [ ] 2.1 `apps/web-platform/scripts/live-verify/run.ts` — **project-bind (ref+URL) before sign-in** → mint (port `dev-signin/route.ts:112-139`, prod cookies `secure:true`) → **ref+UID+email gate; chromium.launch only via post-gate fn** → drive via `{ chromium } from "@playwright/test"` + `addCookies` → **message-free** verify-rail check → teardown **as synthetic user's own session** (assert 0 messages → release slot → delete by id with `user_id=<UID>` predicate) → `RESULT:` line; stamp `session_id="live-verify:<run-id>"`; `--dry-run` destroys session + no artifact; `retries:0`.
- [ ] 2.2 `apps/web-platform/scripts/live-verify/redact.ts` — scrub by structural location: `?access_token=`/`apikey=` URL params (WS connect URL), `Authorization` headers, `sb-*-auth-token` cookie, `refresh_token`/`access_token` JSON keys, emails; redacted-only default; ephemeral destroy.
- [ ] 2.3 Empirically confirm (under synthetic session) archive→slot-release→delete-by-id order with 0 messages, no RESTRICT; pin in run.ts. **Gate path must NOT reference SUPABASE_SERVICE_ROLE_KEY** (AC2b).
- [ ] 2.4 Unit tests: wrong-ref/UID/email each throw before launch (AC2); service-role-free grep (AC2b); message-free grep (AC2c); teardown no-op on empty marker (AC2d); redactor WS-URL/Bearer/cookie/refresh fixtures (AC3).

## Phase 3: Postmerge gate (report-only first)
- [ ] 3.1 `apps/web-platform/scripts/live-verify/trigger-paths.txt` — committed trigger source-of-truth (realtime/WS/auth pattern).
- [ ] 3.2 `plugins/soleur/skills/postmerge/SKILL.md` — new Live Verification phase: consume trigger-paths.txt, run harness via `bun run`, record + surface tri-state PASS/FAIL/CANT-RUN, **report-only** (cite `wg-dark-launch-deploy-gates`, ref #5463; state blocking flip needs GH-Action+Sentry). CANT-RUN auto-files issue.
- [ ] 3.3 Augment Phase 5: MCP-locked → fall through to harness path (not warn-and-skip).
- [ ] 3.4 Tests: trigger pattern (docs→skip; chat→run) (AC5); drift canary (new realtime dir absent from file → fail).

## Phase 4: ADR + C4 + env
- [ ] 4.1 `/soleur:architecture` — create ADR (decision + invariants I-allowlist/I-message-free/I-service-role-bootstrap-only/etc.; **partial-supersede ADR-049** scoped to realtime class; substrate decision; AP-009 carve-out; rotation runbook); C4 Container edge `status: adopting` via c4-edit.
- [ ] 4.2 `apps/web-platform/.env.example` — add `LIVE_VERIFY_USER_PASSWORD`, `PRODUCTION_URL`.

## Phase 5: Verify
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green (AC11).
- [ ] 5.2 `terraform init && terraform validate` on `apps/web-platform/infra/` (AC7).
- [ ] 5.3 Run all new unit/shell tests (AC2/2b/2c/2d/AC3/AC5/AC8).

## Post-merge (non-blocking, after bootstrap)
- [ ] P.1 `bootstrap-live-verify.sh` — **agent-run locally, never in CI** (negative AC: no workflow refs it); creates synthetic prd user + ladder idempotently (AC12).
- [ ] P.2 Harness PASSes against prod message-free rail check (AC13) — report-only per #5463.
- [ ] P.3 Confirm synthetic-user rows invisible in operator views (AC14).
