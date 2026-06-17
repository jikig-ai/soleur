---
feature: live-verify-harness
issue: 5452
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-17-feat-live-verify-harness-plan.md
---

# Tasks: live-verify-harness

> **CTO ruling (2026-06-17, ADR-064):** the deepen invariant **I-message-free was
> structurally vacuous** — `conversations` rows materialize only on the first
> message (`ws-handler.ts:2164`), so a message-free run never exercises the rail
> path. Replaced with **I-action-send-free** (Option B, message-minimal): send ONE
> benign UI message; the synthetic principal holds zero `scope_grants` so a WORM
> `action_sends` row is unreachable; teardown asserts 0 `action_sends` for the
> principal before delete. Seed ladder corrected to set **`workspaces.repo_url`**
> (not `users.repo_url`) per `getCurrentRepoUrl`. AC2c re-read as action-send-free
> (no code-level `messages`/`action_sends` write — the message goes via the UI).

## Phase 1: Synthetic prd principal (IaC + seed)
- [x] 1.1 `apps/web-platform/infra/live-verify.tf` — `random_password.live_verify_user` → `doppler_secret.live_verify_user_password` (config="prd", masked).
- [x] 1.2 `apps/web-platform/scripts/seed-live-verify-user.sh` — FULL ladder (auth upsert + `public.users` + **`workspaces.repo_url` sentinel** + `api_keys`); gate `DOPPLER_CONFIG=="prd"` + service_role JWT; ref from JWT (accept `api.soleur.ai`); echo UID+ref; NO scope_grants.
- [x] 1.3 `apps/web-platform/scripts/seed-live-verify-user.test.sh` — refuses non-prd / non-service_role / wrong-ref; no secret to stdout (AC8).
- [x] 1.4 `apps/web-platform/scripts/bootstrap-live-verify.sh` — one-shot terraform apply -target + seed (AC12 owner).

## Phase 0: gdpr-gate (ADR-049 armed clause)
- [x] 0.1 Ran `/soleur:gdpr-gate` against the cumulative diff (live-origin + real-creds re-trigger per ADR-049:62-63); advisory PASS, zero Critical; output recorded in PR (AC6b).

## Phase 2: Harness core
- [x] 2.1 `apps/web-platform/scripts/live-verify/run.ts` — project-bind (ref before sign-in) → mint (port `dev-signin`, prod cookies `secure:true`) → ref+UID+email gate; single branded `chromium.launch` site → drive via `{ chromium } from "@playwright/test"` + `addCookies` → **message-minimal** rail check (one UI message) → teardown **as synthetic user's own session** (assert 0 action_sends → archive/slot-release → delete by id with `user_id=<UID>` predicate) → `RESULT:` line; stamp `session_id="live-verify:<run-id>"`; `--dry-run` read-only + no artifact.
- [x] 2.2 `apps/web-platform/scripts/live-verify/redact.ts` — structural-location scrub (committed earlier; AC3).
- [x] 2.3 Teardown order pinned in run.ts (archive→slot-release→delete-by-id). Migration-authoritative per CTO Q2 (no other blocking FK). **Gate path is `SUPABASE_SERVICE_ROLE_KEY`-free** (AC2b). NB: the end-to-end dev drive (CTO's pre-flip empirical check) is the documented pre-#5463 step — report-only posture, not pre-merge-blocking.
- [x] 2.4 Unit tests: wrong-ref/UID/email throw before launch (AC2); service-role-free grep (AC2b); action-send-free / no-code-messages-write grep (AC2c); teardown no-op on empty marker (AC2d); redactor fixtures (AC3, committed).

## Phase 3: Postmerge gate (report-only first)
- [x] 3.1 `apps/web-platform/scripts/live-verify/trigger-paths.txt` — committed trigger source-of-truth.
- [x] 3.2 `plugins/soleur/skills/postmerge/SKILL.md` Phase 5.5 — Live Verification: consume trigger-paths.txt, run harness, record+surface tri-state, **report-only** (cites `wg-dark-launch-deploy-gates`, #5463, GH-Action+Sentry flip). CANT-RUN auto-files issue.
- [x] 3.3 Augmented Phase 5: MCP-locked → fall through to harness path (not warn-and-skip).
- [x] 3.4 Tests: trigger pattern (docs→skip; chat→run) (AC5); drift canary.

## Phase 4: ADR + C4 + env
- [x] 4.1 ADR-064 created (decision + invariants incl. **I-action-send-free**; **partial-supersede ADR-049** scoped to realtime class; substrate; AP-009 carve-out; rotation runbook). C4 edge `status: adopting` documented in ADR (c4-edit follow-up).
- [x] 4.2 `apps/web-platform/.env.example` — added `LIVE_VERIFY_USER_PASSWORD`, `PRODUCTION_URL`, `LIVE_VERIFY_EXPECTED_UID/REF` (AC9).

## Phase 5: Verify
- [x] 5.1 `tsc --noEmit` green (AC11).
- [x] 5.2 `terraform init -backend=false && validate` on `apps/web-platform/infra/` — Success; fmt clean (AC7).
- [x] 5.3 All new unit/shell tests green (22 vitest + seed + tf drift) (AC2/2b/2c/2d/AC3/AC5/AC8).

## Post-merge (non-blocking, after bootstrap)
- [ ] P.1 `bootstrap-live-verify.sh` — **agent-run locally, never in CI** (negative AC: no workflow refs it); creates synthetic prd user + ladder idempotently (AC12).
- [ ] P.2 Harness PASSes against prod rail check (AC13) — report-only per #5463.
- [ ] P.3 Confirm synthetic-user rows invisible in operator views (AC14).
