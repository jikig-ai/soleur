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

## Phase 2: Harness core
- [ ] 2.1 `apps/web-platform/scripts/live-verify/run.ts` — mint (port `dev-signin/route.ts:112-139`) → **inline UID-allowlist hard-fail before chromium.launch** → drive deployed app via `{ chromium } from "@playwright/test"` + `addCookies` → verify-rail check → teardown → `RESULT:` line; `--dry-run` read-only path; `retries:0`, bounded waits.
- [ ] 2.2 `apps/web-platform/scripts/live-verify/redact.ts` — scrub tokens/JWTs/cookies/emails (PII-regex invariants); default redacted-only; ephemeral destroy.
- [ ] 2.3 Empirically confirm conversation+children (messages, `user_concurrency_slots`) delete-by-id order under service_role; pin in run.ts.
- [ ] 2.4 Unit tests: non-allowlisted session throws (AC2); redactor strips fixtures / passes benign (AC3).

## Phase 3: Postmerge gate (report-only first)
- [ ] 3.1 `plugins/soleur/skills/postmerge/SKILL.md` — new Live Verification phase: committed `grep -qE` trigger pattern (realtime/WS/auth/DOM-timing), run harness via `bun run`, record + surface tri-state PASS/FAIL/CANT-RUN, **report-only** (cite `wg-dark-launch-deploy-gates`, ref #5463). CANT-RUN auto-files issue.
- [ ] 3.2 Augment Phase 5: MCP-locked → fall through to harness path (not warn-and-skip).
- [ ] 3.3 Shell unit over the trigger pattern (docs-only→skip; chat→run) (AC5).

## Phase 4: ADR + C4 + env
- [ ] 4.1 `/soleur:architecture` — create ADR (synthetic prod principal + live-mutation gate); C4 Container edge `status: adopting` via c4-edit Concierge path.
- [ ] 4.2 `apps/web-platform/.env.example` — add `LIVE_VERIFY_USER_PASSWORD`, `PRODUCTION_URL`.

## Phase 5: Verify
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green (AC11).
- [ ] 5.2 `terraform init && terraform validate` on `apps/web-platform/infra/` (AC7).
- [ ] 5.3 Run all new unit/shell tests (AC2/AC3/AC5/AC8).

## Post-merge (non-blocking, after bootstrap)
- [ ] P.1 `bootstrap-live-verify.sh` creates synthetic prd user idempotently (AC12).
- [ ] P.2 Harness PASSes against prod rail check (AC13) — report-only per #5463.
