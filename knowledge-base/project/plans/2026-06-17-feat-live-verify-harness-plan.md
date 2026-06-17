---
title: "feat: autonomous post-deploy live-verification harness + fail-closed postmerge gate"
issue: 5452
branch: feat-live-verify-harness
worktree: .worktrees/feat-live-verify-harness
pr: 5453
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
created: 2026-06-17
---

# feat: autonomous post-deploy live-verification harness + fail-closed postmerge gate

## Overview

Build a committed harness that drives the **deployed** app with a **real (non-mock, non-OTP,
non-dev-route) session** and assert the change actually works, then wire it into
`/soleur:postmerge` as a **fail-closed, path-triggered gate**. This ends the broken-fix cycle
(#5391 → #5421 → #5436, each green-on-mock but broken in prod; found only by the headless harness
in #5449/#5451). The existing `apps/web-platform/e2e/` suite mocks Supabase and **structurally
cannot** reproduce the realtime/server-commit-timing class — it verifies the model, not reality.

**Scope (operator-chosen, triad-recommended middle slice):** harness + fail-closed gate + ADR.
**Deferred (fast-follow):** plan-time executable acceptance criteria (#5460), fix-PR live-repro
guard (#5461). Brainstorm: `knowledge-base/project/brainstorms/2026-06-17-live-verify-harness-brainstorm.md`.
Spec: `knowledge-base/project/specs/feat-live-verify-harness/spec.md`.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| Driver = `playwright-core` `chromium.launch` + `addCookies` | `playwright-core` is NOT a dep; only `@playwright/test@1.58.2` (`apps/web-platform/package.json:66`), which bundles `chromium` with the same `.launch()` + `context.addCookies()` API | Import `{ chromium }` from `@playwright/test`. **Zero new dependency.** Do NOT add `playwright-core`. |
| Harness in repo-root `scripts/live-verify/` | Session-mint (`app/api/auth/dev-signin/route.ts`), `@supabase/ssr`, the chromium driver, and `lib/supabase/` all live under `apps/web-platform/` | Harness lives in **`apps/web-platform/scripts/live-verify/`** (apps-local). |
| Seed synthetic user (greenfield) | Idempotent precedent exists: `apps/web-platform/scripts/seed-dev-users.sh` (admin upsert via `POST /auth/v1/admin/users`, triple-defense gate, `email_confirm:true`, **plus** a `public.users` + `api_keys` ladder at `:140-170`) — but hard-gated to `DOPPLER_CONFIG=="dev"` (line 27) AND its URL/ref gate (`:43-49,74-81`) asserts `^https://[a-z0-9]{20}\.supabase\.co$` | Port the FULL pattern (auth + `public.users` + `api_keys` ladder) into a **new prd-gated** seed script with a UID-allowlist. **The prod URL gate must accept the custom domain** `api.soleur.ai` (`lib/supabase/validate-url.ts:22` `PROD_ALLOWED_HOSTS`) — derive the ref from the service-role JWT, not the URL host (Kieran P0-2). |
| Redact captured artifacts (CLO) | No general scrubber exists — `server/userid-pseudonymize.ts` is HMAC top-level-only; `kb-validation.ts sanitizeFilename` is control-char only | Implement a minimal scrubber in the harness (tokens/JWTs/cookies/emails), guided by `security-issues/2026-04-17-pii-regex-scrubber-three-invariants.md` (bound input size, structural shapes, avoid `/g`+`.test()`). |
| Teardown deletes the synthetic user | `auth.admin.deleteUser` is blocked by WORM RESTRICT FKs (`2026-06-02-dev-supabase-trigger-auto-creates-solo-workspace-and-worm-teardown.md`); the synthetic user is **persistent**, so delete-by-`user_id` would wipe every prior run | **Per-run teardown is conversation-scoped** (delete-by-conversation-id, unique marker). Phase 2 must **empirically confirm** the conversation row + child rows (messages, `user_concurrency_slots`) are deletable by id under service_role without tripping a sibling RESTRICT FK, and pin the delete order (Kieran P1-1). |
| Doppler secret provisioning | Doppler TF provider configured (`apps/web-platform/infra/main.tf:37-64`); `random_id` + `doppler_secret config="prd" ignore_changes=[value]` precedent (`apps/web-platform/infra/github-app.tf:67-81`). NB: repo-root `infra/` is a **different** (Hetzner) TF root — do not confuse them. `random_password` not yet present but is in the same `hashicorp/random` provider already pinned | Password via `random_password` → `doppler_secret` prd (no operator-mint; satisfies `hr-tf-variable-no-operator-mint-default`). |

## User-Brand Impact

**If this lands broken, the user experiences:** a fix that ships green (mock-verified) and reaches
the non-technical operator as a re-reported, still-broken feature — the exact #5391/#5421/#5436
trust-eroding cycle this feature exists to stop.
**If this leaks, the user's data is exposed via:** the harness minting/capturing a real prod
session and a WS/DOM/screenshot artifact containing another user's data or a live token landing in
a PR/log.
**Brand-survival threshold:** single-user incident → `requires_cpo_signoff: true` (CPO reviewed at
brainstorm; carry-forward satisfies plan-time sign-off). `user-impact-reviewer` runs at PR review.

## Implementation Phases

### Phase 1 — Synthetic prd principal (IaC + seed)
1. `apps/web-platform/infra/live-verify.tf`: `random_password.live_verify_user` (length 32,
   special=true) → `doppler_secret.live_verify_user_password` (`project="soleur"`, `config="prd"`,
   `name="LIVE_VERIFY_USER_PASSWORD"`, `visibility="masked"`), mirroring
   `apps/web-platform/infra/github-app.tf:67-81` (`hashicorp/random` provider already pinned).
2. `apps/web-platform/scripts/seed-live-verify-user.sh`: port the FULL `seed-dev-users.sh`
   idempotent flow — auth upsert (`POST /auth/v1/admin/users`, `email_confirm:true`, lookup via
   `GET /auth/v1/admin/users?email=`) **AND** the `public.users` ladder (`PATCH /rest/v1/users`:
   `tc_accepted_version` from `lib/legal/tc-version.ts`, `workspace_status="ready"`,
   `repo_status="connected"`, `workspace_path`) **AND** a dummy `api_keys` row — else middleware
   bounces to `/accept-terms`/`/setup-key` and the rail never renders (Kieran P1-4).
   **Gate to `DOPPLER_CONFIG=="prd"`** + assert `service_role` JWT. **Derive the ref from the JWT,
   not the URL host** — the dev `^https://[a-z0-9]{20}\.supabase\.co$` regex rejects the prod
   custom domain `api.soleur.ai` (`lib/supabase/validate-url.ts:22`); validate the URL against
   `PROD_ALLOWED_HOSTS ∪ canonical-shape` (Kieran P0-2). Email: `live-verify@soleur.ai`.
   Records the created UID to stdout for the inline allowlist constant.
3. `apps/web-platform/scripts/seed-live-verify-user.test.sh` (matches the `infra/*.test.sh`
   convention): asserts the seed refuses non-prd `DOPPLER_CONFIG`, a non-`service_role` JWT, and a
   wrong ref (Kieran P1-3).

### Phase 2 — Harness core (`apps/web-platform/scripts/live-verify/`)
Two files only (DHH + simplicity: collapse the per-noun split; the guardrails are behaviors, not
files). Runner is **`bun`** (`apps/web-platform/bun.lock`) — `.ts` runs via `bun run`, NOT bare `node`.
1. `run.ts` — single linear orchestrator:
   - **Mint:** server-side `createServerClient(NEXT_PUBLIC_SUPABASE_URL, anonKey, {cookies})` →
     `signInWithPassword({email, password})` (password from Doppler prd), capturing `setAll`-written
     cookies into an in-memory jar (port `app/api/auth/dev-signin/route.ts:112-139`).
   - **UID-allowlist code-gate (FR2):** inline — after sign-in, `getUser()` and **hard-fail** if
     `user.id` ≠ the single allowlisted synthetic UID, **before** any `chromium.launch()`.
   - **Drive:** `import { chromium } from "@playwright/test"` → `chromium.launch()` →
     `context.addCookies(jar)` → drive `PRODUCTION_URL`; capture WS frames (CDP/`page.on`), console,
     DOM, network with **bounded waits on observable state** (no fixed sleeps); `retries:0`.
   - **verify-rail check (CPO MVP):** start a fresh conversation, assert the row appears in the
     Recent Conversations rail via observed WS/DOM (the #5391/#5436 bug; must PASS against current
     prod, proving the #5451 fix holds as a backstop).
   - **Teardown (FR5):** delete the conversation row + child rows created this run by unique-marker
     id, in the empirically-confirmed delete order (see step 2 below); on failure leave the marker
     and FAIL loudly so the next run reaps it (no silent prod accumulation).
   - **RESULT:** emit one structured line `RESULT: PASS|FAIL|CANT-RUN:<reason>` + redacted summary.
   - `--dry-run`: mint + allowlist-gate + load the page **read-only** (no conversation create) for
     the discoverability probe (the only non-mutating invocation; keeps the doc probe prod-safe).
2. `redact.ts` (FR4) — standalone (it is the leakage-safety boundary with its own fixture test):
   scrub tokens/JWTs/cookies/emails; default attach **redacted-only**; destroy session + raw
   captures at end of run (ephemeral, never commit).
3. **Empirical teardown-order check (Kieran P1-1):** before finalizing `run.ts`, confirm a
   conversation row created via the live UI (and its `messages` + `user_concurrency_slots` children)
   is deletable by conversation-id under service_role in prod without a sibling RESTRICT FK error;
   pin the order in `run.ts` and the AC.

### Phase 3 — Postmerge gate (`plugins/soleur/skills/postmerge/SKILL.md`) — **report-only first**
Per `wg-dark-launch-deploy-gates` (Kieran P0-1): a new deploy-gating check ships **non-blocking**
first and is observed passing on ≥1 real qualifying deploy before it gates. Blocking flip tracked in
**#5463**.
1. New phase after Phase 5: **Live Verification (path-triggered, REPORT-ONLY).** Reuse Phase 4's
   `gh pr diff <number> --name-only` to compute the trigger via a committed grep pattern (Kieran
   P2-5): fire iff a changed path matches `grep -qE '^apps/web-platform/(hooks/|components/chat/|lib/ws-|middleware\.ts|app/\(auth\)/|server/inngest/.*realtime)'`. Pure logic/docs/copy/config →
   skip.
2. If triggered: run the harness (`bun run scripts/live-verify/run.ts`) against
   `PRODUCTION_URL`/`DEPLOY_URL` (reuse Phase 3 resolution, `/health` gate at `:88-91`). Record
   tri-state **`PASS` / `FAIL` / `CANT-RUN:<reason>+#issue`** and **surface it** — but do NOT block
   "done" yet (report-only). `CANT-RUN` still auto-files a tracking issue
   (`wg-when-deferring-a-capability`).
3. Augment existing Phase 5: when Playwright MCP is locked/unavailable, **fall through to the
   harness path** instead of "warn and skip" (the issue's proposal #2).
4. Mode-branch (defense-in-depth, `2026-03-27-skill-defense-in-depth-gate-pattern.md`): always run;
   in report-only mode both arms record + surface (no abort). The empty→FAIL-closed and
   FAIL-blocks-done semantics land with the #5463 blocking flip, after ≥1 observed real PASS.

### Phase 4 — ADR + C4
Author the ADR via `/soleur:architecture` (synthetic prod principal + live-mutation gate); note the
C4 Container-view edge (verification harness → deployed web-platform + prod Supabase auth) as
`status: adopting`, routed through the `c4-edit` Concierge path. See `## Architecture Decision`.

## Files to Create
- `apps/web-platform/infra/live-verify.tf`
- `apps/web-platform/scripts/seed-live-verify-user.sh`
- `apps/web-platform/scripts/seed-live-verify-user.test.sh`
- `apps/web-platform/scripts/bootstrap-live-verify.sh` (one-shot: terraform apply -target + seed; AC12 owner)
- `apps/web-platform/scripts/live-verify/run.ts` (orchestrator; inline UID allowlist + gate)
- `apps/web-platform/scripts/live-verify/redact.ts` (standalone leakage boundary; fixture-tested)
- `knowledge-base/engineering/architecture/decisions/ADR-XXX-live-production-verification-harness.md` (via `/soleur:architecture`)

## Files to Edit
- `plugins/soleur/skills/postmerge/SKILL.md` (new fail-closed gate phase + Phase 5 fall-through)
- `apps/web-platform/.env.example` (add `LIVE_VERIFY_USER_PASSWORD`, `PRODUCTION_URL` if absent)

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1: `git grep -n "playwright-core" apps/web-platform/scripts/live-verify` returns **zero**; `run.ts` imports `{ chromium }` from `@playwright/test` (no new dep).
- [ ] AC2: `run.ts` hard-fails when `getUser().id` ≠ the allowlisted UID — unit test asserting a non-allowlisted session throws before any `chromium.launch`.
- [ ] AC3: `redact.ts` removes JWT/cookie/bearer/email shapes from a fixture capture and passes benign text through — unit test on synthetic input (no real tokens; use `<<...>>` placeholders per push-protection).
- [ ] AC4: `bun run scripts/live-verify/run.ts --dry-run` against a reachable URL prints exactly one `RESULT: ` line and creates **no** conversation row.
- [ ] AC5: the postmerge trigger is a committed grep pattern — a docs-only changed-file set yields `skip`; a `components/chat/**` set yields a run (shell unit over the pinned `grep -qE` pattern).
- [ ] AC6: the gate ships **report-only** (records + surfaces tri-state, does NOT block "done"); the SKILL.md gate text cites `wg-dark-launch-deploy-gates` and references #5463 for the blocking flip.
- [ ] AC7: `apps/web-platform/infra/live-verify.tf` uses `random_password` + `doppler_secret config="prd"` (no `variable {sensitive=true}` operator-mint); `terraform validate` passes (run after `terraform init`).
- [ ] AC8: `seed-live-verify-user.test.sh` passes — refuses non-prd `DOPPLER_CONFIG`, non-`service_role` JWT, wrong ref.
- [ ] AC9: `.env.example` contains `LIVE_VERIFY_USER_PASSWORD` and `PRODUCTION_URL` — `grep -qE 'LIVE_VERIFY_USER_PASSWORD' apps/web-platform/.env.example`.
- [ ] AC10: ADR file exists under `knowledge-base/engineering/architecture/decisions/`.
- [ ] AC11: typecheck green — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

### Post-merge (operator/pipeline)
- [ ] AC12: one-time bootstrap via a single committed script (owner: `apps/web-platform/scripts/bootstrap-live-verify.sh`, called from the deploy pipeline — NOT a manual checklist): `terraform apply -target=random_password.live_verify_user -target=doppler_secret.live_verify_user_password` then `doppler run -p soleur -c prd -- bash apps/web-platform/scripts/seed-live-verify-user.sh` — creates the synthetic prd user + `public.users`/`api_keys` ladder idempotently.
- [ ] AC13 (after AC12; non-blocking per #5463): harness PASSes against production for the rail-conversation-appears check (proves the #5451 fix holds as a live backstop). Cannot gate this PR — report-only.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm `## Domain Assessments`)

### Engineering (CTO)
**Status:** reviewed (carry-forward)
**Assessment:** Mock e2e structurally can't reproduce realtime. Driver via the chromium bundled in
`@playwright/test` (reconciled from "playwright-core"); port the `dev-signin` mint pattern;
dedicated synthetic prd user; standalone `apps/web-platform/scripts/live-verify/`; `retries:0` +
per-run conversation teardown; ADR required.

### Product (CPO)
**Status:** reviewed (carry-forward) — sign-off satisfied for `requires_cpo_signoff: true`
**Assessment:** Fail-closed gate is the lever, harness the ammunition. Tri-state
`PASS/FAIL/CANT-RUN:<reason>+#issue`, empty fails closed, auto-files an issue. Path-triggered to the
realtime/WS/auth/DOM-timing class only.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** Permitted-with-guardrails for operator-self-use against a synthetic account:
(1) UID-allowlist **code gate** before `setSession` (FR2/AC2); (2) redaction-before-persist
(FR4/AC3); (3) ephemeral session + captures (FR4). Re-eval trigger: first arms-length/real user or
EEA data subject.

### Product/UX Gate
**Tier:** none — Files to Create/Edit match no UI-surface glob (scripts/`.ts`, `SKILL.md`, `.tf`,
`.sh`, ADR `.md`); the mechanical UI-surface override did not fire. No wireframes required.

## Architecture Decision (ADR/C4)

### ADR
Create `ADR-XXX: Live production verification harness with synthetic prod session` via
`/soleur:architecture`. Decision: the merge pipeline authenticates to **prod** as a dedicated
synthetic Supabase principal and performs **live mutations** on qualifying PRs to verify the
deployed artifact. Alternatives considered: (a) mock-only e2e (rejected — can't reproduce realtime);
(b) operator's own account (rejected — CLO impersonation/PII surface); (c) preview-deploy target
(rejected — realtime/server-commit timing only reproduces against the real stack).

### C4 views
Container view: new edge "live-verify harness → deployed web-platform (HTTPS) + prod Supabase
(auth)". `status: adopting`. Routed through the `c4-edit` Concierge path (KB-write gated).

### Sequencing
ADR authored now describing target state; the gate becomes load-bearing once the synthetic prd user
is seeded (AC10).

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/live-verify.tf`: `random_password.live_verify_user` +
  `doppler_secret.live_verify_user_password` (config `prd`, masked, `ignore_changes=[value]` not
  needed — TF owns the value). Providers already pinned (`apps/web-platform/infra/main.tf:37-64`,
  `hashicorp/random`, `DopplerHQ/doppler ~>1.21`). Sensitive var: none new (password is
  TF-generated). NB: this is the `apps/web-platform/infra/` root, NOT the repo-root Hetzner root.

### Apply path
Cloud-init not applicable (no host). Apply path = `terraform apply -target=…` for the two new
resources, then the idempotent seed script (AC10). The synthetic Supabase user is created by the
seed script (no Supabase TF provider for auth users) — idempotent, re-runnable.

### Distinctness / drift safeguards
`config="prd"` literal pins the secret to prd (dev/prd isolation, per `github-app.tf` precedent).
Password value lands in `terraform.tfstate` (already R2-encrypted backend). `dev != prd`: the
dev-gated `seed-dev-users.sh` is untouched; the new seed script asserts `DOPPLER_CONFIG=="prd"`.

### Vendor-tier reality check
No paid-tier gate — Supabase admin user creation and Doppler secret writes are within current plan.

## Observability

```yaml
liveness_signal:
  what: postmerge live-verification tri-state RESULT line per qualifying PR merge
  cadence: per merge of a realtime/WS/auth/DOM-timing PR
  alert_target: auto-filed GitHub issue on CANT-RUN/FAIL (label deferred-scope-out / bug)
  configured_in: plugins/soleur/skills/postmerge/SKILL.md (Live Verification gate)
error_reporting:
  destination: postmerge run output (FAIL blocks "done") + redacted artifact summary
  fail_loud: true
failure_modes:
  - {mode: session mint fails, detection: mint-session throws, alert_route: CANT-RUN + auto-issue}
  - {mode: harness assertion fails, detection: verify-rail FAIL, alert_route: FAIL blocks done}
  - {mode: deployed URL unreachable, detection: /health non-2xx, alert_route: CANT-RUN + auto-issue}
  - {mode: teardown fails, detection: delete-by-id error, alert_route: FAIL + marker left for next run}
logs:
  where: postmerge run log + redacted in-run artifact
  retention: ephemeral — session + raw captures destroyed at end of run, never committed
discoverability_test:
  command: "cd apps/web-platform && PRODUCTION_URL=https://app.soleur.ai bun run scripts/live-verify/run.ts --dry-run"
  expected_output: "single 'RESULT: PASS' line + redacted summary; no conversation row created"
```

## Open Code-Review Overlap

**None.** The `infra/` and `lib/supabase` substring hits (#3829, #2197, #2963, #2193) are
coincidental path-fragment matches; none touch the files this plan creates/edits
(`scripts/live-verify/*`, `postmerge/SKILL.md`, new `infra/live-verify.tf`, new seed script).

## Test Scenarios
1. Non-allowlisted session → harness aborts before browser launch (AC2).
2. Redactor strips a fixture JWT/cookie/email; passes through benign text (AC3).
3. `--dry-run` mints + loads read-only, zero prod mutation (AC4).
4. Path-trigger: docs-only → skip; `components/chat/**` → run (AC5).
5. Seed gate: refuses non-prd config / non-service_role JWT / wrong ref (AC8).
6. Live (post-bootstrap, non-blocking): fresh conversation appears in the rail against prod (AC13).

## Risks & Mitigations
- **Prod mutation on every qualifying merge** → per-run conversation teardown + unique marker;
  `retries:0` so a flake is a signal; synthetic user's rows excluded from operator-facing views
  (verify during impl).
- **Flakiness masking the very timing bug** → bounded waits on observable WS/DOM state, never fixed
  sleeps; `retries:0`.
- **Captured-artifact leakage** → redact-before-persist default + ephemeral destroy (CLO).
- **`@playwright/test` chromium in a non-test script** → confirm `chromium.launch()` is exported at
  the installed 1.58.2 (research-confirmed bundled); pin via the existing `playwright-mcp-version-pin`
  posture if needed.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/`TBD`/placeholder fails `deepen-plan`
  Phase 4.6 — this one is filled.
- Do NOT add `playwright-core`; the chromium driver is in `@playwright/test`. Run `.ts` via
  `bun run`, never bare `node`.
- **Dark-launch:** the gate ships report-only first (`wg-dark-launch-deploy-gates`); the
  empty→FAIL-closed + FAIL-blocks-done flip is #5463, after ≥1 observed real PASS. Do NOT ship it
  blocking on this PR.
- **Prod URL gate:** the ported `seed-dev-users.sh` URL regex (`…\.supabase\.co$`) rejects the prod
  custom domain `api.soleur.ai`; derive the ref from the service-role JWT and validate the URL
  against `PROD_ALLOWED_HOSTS`.
- **Full user ladder:** the synthetic prd user needs `public.users` (tc-accepted, workspace ready,
  repo connected) + an `api_keys` row, or middleware bounces it off the rail before the check runs.
- Teardown is **conversation-scoped, not user-scoped** — `auth.admin.deleteUser` hits WORM RESTRICT
  FKs and delete-by-`user_id` would wipe every prior run; the synthetic user is persistent. Confirm
  the conversation+children delete order empirically before relying on "next run reaps it".
- The new seed script must assert `DOPPLER_CONFIG=="prd"` (the ported `seed-dev-users.sh` asserts
  `"dev"`); do not let a prd run reuse the dev gate or vice-versa.
