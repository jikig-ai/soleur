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

## Enhancement Summary

**Deepened on:** 2026-06-17 · **Agents:** data-integrity-guardian, security-sentinel,
architecture-strategist, verify-the-negative (Explore). Verify-the-negative confirmed all 6
factual reconciliations.

### Critical findings folded in
1. **ADR-049 conflict (must supersede).** ADR-049 (Headless Visual-Regression Gate) mandates
   "zero credentials / no live backend / never point at a live origin — if it ever does, re-trigger
   gdpr-gate" (`ADR-049…:27,35,62-63`). This plan reintroduces the rejected live-creds shape for a
   *new* reason (realtime timing is invisible to mock). The new ADR **partial-supersedes ADR-049**
   scoped to the realtime-timing class; **gdpr-gate runs inline** (ADR-049's armed clause) as a
   /work Phase 0 deliverable.
2. **`action_sends` WORM permanent-wedge.** `action_sends.message_id → messages` is NO-ACTION +
   WORM `BEFORE DELETE` trigger (`051…:103,150-154`); any `messages` row the harness creates becomes
   **permanently undeletable** → monotonic prod accumulation. Harness is **message-free**; teardown
   asserts 0 messages before delete.
3. **Service-role blast radius.** Bootstrap (service-role) runs **locally via the agent**, never
   wired into a workflow; the **gate-run teardown uses the synthetic user's own session** (RLS),
   not service-role.
4. **UID allowlist insufficient** (wrong-project collision) → gate binds **ref + UID + email** before
   sign-in; `chromium.launch` reachable only via a function taking the verified principal.
5. **Slot leak** — `user_concurrency_slots` has no FK (`029…:77`); teardown must release the slot.
6. **Redaction gaps** — scrubber must cover `?access_token=`/`apikey=` (WS connect URL),
   `Authorization` headers, `sb-*-auth-token` cookie, `refresh_token`.
7. **Substrate** — report-only v1 in agent-postmerge is fine; the **#5463 blocking flip requires
   re-homing into a GH-Action/`workflow_dispatch` with Sentry-observable result** (ADR-033 Option C),
   not flipping a boolean in an agent skill.
8. **Trigger drift** — move the path-set to a committed source-of-truth file + a drift canary
   (fail-open is the accepted residual).

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
   - **Project bind (I-allowlist, security P0-3):** derive the ref from the anon-key JWT and assert
     it equals a pinned `LIVE_VERIFY_EXPECTED_REF`; validate the URL against
     `PROD_ALLOWED_HOSTS ∪ canonical-shape` (`lib/supabase/validate-url.ts`). Wrong project →
     hard-fail **before** sign-in.
   - **Mint:** server-side `createServerClient(NEXT_PUBLIC_SUPABASE_URL, anonKey, {cookies})` →
     `signInWithPassword({email, password})` (password from Doppler prd), capturing `setAll`-written
     cookies into an in-memory jar (port `app/api/auth/dev-signin/route.ts:112-139`); set prod
     cookies `secure:true` (do NOT copy dev-signin's `secure:false`).
   - **Allowlist code-gate (FR2):** after sign-in, assert `getUser().id == UID` **AND**
     `email == "live-verify@soleur.ai"`. `chromium.launch` is reachable ONLY via a single function
     that takes the verified-principal token as a typed argument — no other launch call site exists
     (a future refactor cannot bypass a boolean).
   - **Drive:** `import { chromium } from "@playwright/test"` → `chromium.launch()` →
     `context.addCookies(jar)` → drive `PRODUCTION_URL`; capture WS frames (CDP/`page.on`), console,
     DOM, network with **bounded waits on observable state** (no fixed sleeps); `retries:0`.
   - **verify-rail check (CPO MVP), MESSAGE-FREE (I-message-free, data-integrity P0-1):** start a
     fresh conversation, assert the row appears in the Recent Conversations rail via observed WS/DOM
     — and **never send a message** (a `messages` row spawns a WORM-undeletable `action_sends`
     child). This is the #5391/#5436 bug; must PASS against current prod (#5451 backstop).
   - **Teardown (FR5), as the SYNTHETIC USER's OWN session (security P0-2), NOT service-role:**
     (a) assert `SELECT count(*) messages WHERE conversation_id=$id == 0` — else
     `CANT-RUN:CANT-TEARDOWN-has-messages+#issue` (distinct, escalated, never "reap next run");
     (b) release the concurrency slot (the synthetic user archives its own conversation → fires the
     `036` slot-release trigger, OR calls `release_conversation_slot`) — `user_concurrency_slots` has
     no FK (`029…:77`) so a plain conversation delete leaks it (data-integrity P1-1);
     (c) delete the conversation by id **with `user_id=<allowlisted UID>` as a mandatory first
     predicate** (defense-in-depth; abort if the marker/UID is empty so a null filter can't match
     other users — data-integrity P2-1). `messages` would CASCADE but we asserted 0.
   - **Queryable marker (data-integrity P1-2):** stamp `session_id = "live-verify:<run-id>"` so the
     start-of-run reaper can `DELETE … WHERE user_id=<UID> AND session_id LIKE 'live-verify:%'` to
     reap any orphan from a crashed run (`conversations` has no title column).
   - **Start-of-run guards:** assert 0 active slots for the synthetic user (fail-closed if a prior
     leak saturated the cap; set the synthetic user's tier cap ≥ 2 for sweep-lag tolerance).
   - **RESULT:** emit one structured line `RESULT: PASS|FAIL|CANT-RUN:<reason>` + redacted summary.
   - `--dry-run`: project-bind + mint + full allowlist-gate + load page **read-only** (no conversation
     create) + **destroy the session, write no artifact**. The only non-mutating invocation; keeps
     the doc probe prod-safe.
2. `redact.ts` (FR4) — standalone leakage boundary (own fixture test). Scrub by **structural
   location**, not just free-text JWT shape (security P0-4): `?access_token=`/`&access_token=`/
   `apikey=` URL query params (incl. the WS connect URL), `Authorization` request headers,
   `Cookie`/`Set-Cookie` + `sb-*-auth-token` cookie values, JSON keys `access_token`/`refresh_token`/
   `provider_token`, plus emails. Default attach **redacted-only**; destroy session + raw captures
   at end of run (ephemeral, never commit).
3. **Empirical teardown-order check:** before finalizing `run.ts`, confirm — under the **synthetic
   user's own session** — that archiving (slot release via `036`) then deleting the conversation by
   id succeeds with 0 messages and no RESTRICT error; pin the order in `run.ts` + AC. The gate path
   must NOT reference `SUPABASE_SERVICE_ROLE_KEY`.

### Phase 3 — Postmerge gate (`plugins/soleur/skills/postmerge/SKILL.md`) — **report-only first**
Per `wg-dark-launch-deploy-gates` (Kieran P0-1): a new deploy-gating check ships **non-blocking**
first and is observed passing on ≥1 real qualifying deploy before it gates. Blocking flip tracked in
**#5463**.
1. New phase after Phase 5: **Live Verification (path-triggered, REPORT-ONLY).** The trigger path-set
   is a **committed source-of-truth file** `apps/web-platform/scripts/live-verify/trigger-paths.txt`
   (not SKILL.md prose — architecture P1-4), consumed by both the gate and a test. Reuse Phase 4's
   `gh pr diff <number> --name-only`; fire iff a changed path matches the file's `grep -qE` pattern
   (seed: `^apps/web-platform/(hooks/|components/chat/|lib/(ws-|realtime)|middleware\.ts|app/\(auth\)/|server/inngest/.*realtime)`). Pure logic/docs/copy/config → skip. **Fail-open is the accepted
   residual** (unmatched path → skip) — mitigated by a drift canary (step 5).
2. If triggered: run the harness (`bun run scripts/live-verify/run.ts`) against
   `PRODUCTION_URL`/`DEPLOY_URL` (reuse Phase 3 resolution, `/health` gate at `:88-91`). Record
   tri-state **`PASS` / `FAIL` / `CANT-RUN:<reason>+#issue`** and **surface it** — but do NOT block
   "done" yet (report-only). `CANT-RUN` still auto-files a tracking issue
   (`wg-when-deferring-a-capability`).
3. Augment existing Phase 5: when Playwright MCP is locked/unavailable, **fall through to the
   harness path** instead of "warn and skip" (the issue's proposal #2).
4. Mode-branch (defense-in-depth, `2026-03-27-skill-defense-in-depth-gate-pattern.md`): always run;
   in report-only mode both arms record + surface (no abort). The empty→FAIL-closed and
   FAIL-blocks-done semantics land with the **#5463 blocking flip — which also requires re-homing the
   harness into a GH-Action/`workflow_dispatch` with a Sentry-observable result** (ADR-033 Option C);
   a boolean flip in the agent-driven skill is NOT acceptable for a blocking gate.
5. **Drift canary:** a cheap test that fails when a new top-level dir under `apps/web-platform/`
   matches realtime/WS/auth heuristics but is absent from `trigger-paths.txt` (mirrors the
   `kb-domain-allowlist-guard.sh` advisory pattern) — converts silent-skip into a loud
   "extend the trigger set" prompt.

### Phase 4 — ADR + C4
Author the ADR via `/soleur:architecture` (synthetic prod principal + live-mutation gate); note the
C4 Container-view edge (verification harness → deployed web-platform + prod Supabase auth) as
`status: adopting`, routed through the `c4-edit` Concierge path. See `## Architecture Decision`.

## Files to Create
- `apps/web-platform/infra/live-verify.tf`
- `apps/web-platform/scripts/seed-live-verify-user.sh`
- `apps/web-platform/scripts/seed-live-verify-user.test.sh`
- `apps/web-platform/scripts/bootstrap-live-verify.sh` (one-shot, **agent-run locally**: terraform apply -target + seed; never in CI; AC12 owner)
- `apps/web-platform/scripts/live-verify/run.ts` (orchestrator; project-bind + ref+UID+email gate)
- `apps/web-platform/scripts/live-verify/redact.ts` (standalone leakage boundary; fixture-tested)
- `apps/web-platform/scripts/live-verify/trigger-paths.txt` (committed trigger source-of-truth)
- `apps/web-platform/test/live-verify/*.test.ts` (allowlist-gate, redact, trigger-pattern, drift-canary) — NB: under `test/`, not `scripts/` — vitest node `include` is `test/**` + `lib/**` only, so co-located `scripts/**` tests are silently skipped
- `knowledge-base/engineering/architecture/decisions/ADR-XXX-live-production-verification-harness.md` (via `/soleur:architecture`)

## Files to Edit
- `plugins/soleur/skills/postmerge/SKILL.md` (new fail-closed gate phase + Phase 5 fall-through)
- `apps/web-platform/.env.example` (add `LIVE_VERIFY_USER_PASSWORD`, `PRODUCTION_URL` if absent)

## Acceptance Criteria

### Pre-merge (PR)
- [x] AC1: `grep -rn "playwright-core" apps/web-platform/scripts/live-verify` returns **zero**; `run.ts` imports `{ chromium }` from `@playwright/test` (no new dep). Verified.
- [x] AC2: the gate asserts **ref(from anon JWT)** before sign-in and **UID + email** after sign-in, all before launch; `chromium.launch` has exactly one call site (inside the branded post-gate function) — `gate.test.ts` proves wrong-ref/wrong-UID/wrong-email each throw before launch.
- [x] AC2b: **gate path is service-role-free** — `grep -rn "SUPABASE_SERVICE_ROLE_KEY" apps/web-platform/scripts/live-verify` returns **zero**. Verified.
- [x] AC2c (re-read per CTO ruling as **action-send-free**): `grep -rnE "from\(.messages.\)|/messages|insertMessage" apps/web-platform/scripts/live-verify` returns **zero** — the harness performs no code-level `messages`/`action_sends` write (the one message is sent through the browser UI). Teardown asserts the principal has **0 `action_sends`** before delete (stronger than per-conversation, and avoids reading `.from("messages")`).
- [x] AC2d: the teardown DELETE carries `user_id=<allowlisted UID>` as a predicate and is a **no-op when the marker is empty/undefined** — `gate.test.ts` proves 0 DB calls on empty convId AND empty UID.
- [x] AC3: `redact.test.ts` (committed) redacts a WS connect URL `access_token`/`apikey`, `Authorization: Bearer`, `sb-<ref>-auth-token` cookie, `refresh_token` JSON key, email; passes benign text; idempotent. Synthetic concatenated fixtures.
- [ ] AC4: `bun run scripts/live-verify/run.ts --dry-run` against a reachable URL prints exactly one `RESULT: ` line, creates no conversation row, destroys the session, writes no artifact. **Deferred to post-bootstrap** (needs a reachable deployed URL + seeded Doppler prd creds — the `--dry-run` path is implemented and unit-covered; the live invocation is a post-merge step, report-only per #5463).
- [x] AC5: the trigger lives in committed `trigger-paths.txt` — `trigger.test.ts` proves docs-only → skip, `components/chat/**` + `ws-handler.ts` + `middleware.ts` + `(auth)` → run; drift canary fails on an uncovered new realtime/WS/auth top-level dir.
- [x] AC6: the gate ships **report-only** (records + surfaces tri-state, does NOT block "done"); SKILL.md Phase 5.5 cites `wg-dark-launch-deploy-gates`, references #5463, states the blocking flip requires re-homing into a GH-Action with Sentry-observable result.
- [x] AC6b: ADR-064 partial-supersedes ADR-049 (scoped to realtime class) and `/soleur:gdpr-gate` was run inline at /work Phase 0 (ADR-049 armed clause) — advisory PASS, zero Critical, output recorded in the PR.
- [x] AC7: `live-verify.tf` uses `random_password` + `doppler_secret config="prd"` (no operator-mint variable); `terraform validate` passes (Success; fmt clean) + the PR's `plan (apps/web-platform/infra)` CI check is green.
- [x] AC8: `seed-live-verify-user.test.sh` passes — refuses non-prd / non-`service_role` / wrong-ref, AND asserts no secret-shaped string reaches stdout/stderr (no `set -x`; password/key never echoed; decode pipelines excluded).
- [x] AC9: `.env.example` contains `LIVE_VERIFY_USER_PASSWORD` and `PRODUCTION_URL`. Verified.
- [x] AC10: ADR-064 exists under `knowledge-base/engineering/architecture/decisions/`.
- [x] AC11: typecheck green — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

### Post-merge (operator/pipeline)
- [ ] AC12: one-time bootstrap via a single committed script `apps/web-platform/scripts/bootstrap-live-verify.sh`, **run once by the agent locally** (`doppler run -p soleur -c prd -- bash …`) — **NEVER wired into `.github/workflows/`** (keeps prod service-role out of CI; security P0-1). It runs `terraform apply -target=random_password.live_verify_user -target=doppler_secret.live_verify_user_password` then the seed (synthetic user + `public.users`/`api_keys` ladder, idempotent). Negative AC: `grep -rl "bootstrap-live-verify\|seed-live-verify" .github/workflows/` returns **zero**.
- [ ] AC13 (after AC12; non-blocking per #5463): harness PASSes against production for the message-free rail-conversation-appears check (proves the #5451 fix holds as a live backstop). Cannot gate this PR — report-only.
- [ ] AC14: synthetic-user rows are invisible in operator-facing views (RLS/user_id scoping) — a stranded marker row never surfaces to the operator (security P1-2).

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

Decision adjudicated **at plan time** (per `wg-architecture-decision-is-a-plan-deliverable`); Phase 4
transcribes it into the ADR file via `/soleur:architecture`.

### Decision
The merge pipeline authenticates to **prod** as a dedicated, persistent synthetic Supabase principal
and performs **live, conversation-scoped mutations** on qualifying PRs to verify the deployed
artifact — the only way to exercise the realtime/server-commit-timing class.

### Partial-supersession of ADR-049 (load-bearing)
ADR-049 (Headless Visual-Regression Gate) mandates "runs with zero credentials," "no dev-signin, no
live backend, no real credentials," and "the gate must never point at a live/staging origin. If it
ever does, re-trigger the gdpr-gate" (`ADR-049…:27,35,62-63`). This ADR **partial-supersedes ADR-049,
scoped to the realtime/server-commit-timing trigger class only** — CSS/structural diffs stay on
ADR-049's zero-cred mock gate. The new fact ADR-049 didn't weigh: realtime timing is invisible to
mock-Supabase (it 200s `/realtime/*` instead of upgrading the WS). **ADR-049's gdpr-gate clause is
armed** → run `/soleur:gdpr-gate` inline at /work Phase 0 (not brainstorm carry-forward).

### Alternatives considered
(a) mock-only e2e — rejected, can't reproduce realtime; (b) operator's own account — rejected (CLO
impersonation/PII); (c) preview-deploy target — rejected: a preview points at **dev** Supabase
(ADR-023), a different realtime backend, so it cannot reproduce the prod race; (d) ADR-049's zero-cred
mock-storageState gate — rejected for this class (mock can't upgrade the WS). Honest consequence:
this is a **detect-fast gate, not a prevent gate** — it verifies post-merge, so a regression is
briefly live; prevention would need a prod-realtime-pointing preview (separate, larger infra,
deferred).

### Binding invariants (ADR must enumerate, ADR-033 I1–I7 style)
- **I-allowlist:** exactly one synthetic principal; gate asserts ref(from anon JWT) **+ UID + email**
  before sign-in; `chromium.launch` reachable only via a function taking the verified principal.
- **I-blast-radius:** read-mostly + conversation-scoped mutation only; a 1-member personal workspace
  (consistent with ADR-044 owner-gate / AP-015 canary); never touches another user's data.
- **I-message-free:** never writes `messages`/`action_sends`/any WORM/audit row (undeletable on a
  persistent principal — data-integrity P0-1).
- **I-no-founder-context:** no BYOK/operator credentials beyond its own session (ADR-033 I2 mirror).
- **I-service-role-bootstrap-only:** service-role used only at one-time local bootstrap; the gate-run
  path never references it.
- **I-ephemerality:** session + raw captures destroyed at end of run.
- **I-teardown:** delete-by-conversation-id (+ `user_id=<allowlisted uid>` predicate), never
  delete-by-user-id.

### Substrate (reconcile with ADR-033)
Report-only v1 lives in the agent-driven `/soleur:postmerge` skill (acceptable for dark-launch
observation). **The #5463 blocking flip is gated on re-homing the harness into a GH-Action /
`workflow_dispatch`-from-`web-platform-release.yml` with a Sentry-observable result** (ADR-033 Option
C for credential-heavy real-stack execution) — never a boolean flip in an agent skill (that would
re-create the #4932 non-deterministic-blocking-gate class). Record this as a written precondition on
#5463.

### Principle-register alignment
AP-001 (Terraform — aligned; note `-target=` is a scoped bootstrap escape hatch), AP-008 (Doppler —
aligned), **AP-009 (never delete user data — carve-out:** synthetic-principal rows are not user data;
teardown is scoped to the allowlisted UID), AP-015 (always-enforce-workspace — synthetic user is a
1-member personal workspace, does not perturb the canary).

### C4 views
Container view: new edge "live-verify harness → deployed web-platform (HTTPS) + prod Supabase
(auth)". `status: adopting`. Routed through the `c4-edit` Concierge path (KB-write gated).

### Password rotation / revocation
Leak path: `terraform apply -replace=random_password.live_verify_user` → re-seed (idempotent admin
password update) → `auth.admin` sign-out-all for the synthetic UID. Record in the ADR body.

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
- **`action_sends` WORM permanent-wedge** (data-integrity P0-1) → harness is message-free
  (I-message-free); teardown asserts 0 messages before delete (`051…:103,150-154`).
- **Service-role blast radius** (security P0-1/P0-2) → service-role is bootstrap-only and local;
  gate-run teardown uses the synthetic user's own session (RLS); AC2b greps it to zero.
- **Wrong-project UID collision** (security P0-3) → bind ref+UID+email before sign-in; type-gated
  launch.
- **Concurrency-slot leak** (data-integrity P1-1) → release slot (archive trigger / RPC) before
  delete; assert 0 slots at start; cap ≥ 2.
- **Service-role teardown matching other users on empty marker** (data-integrity P2-1) →
  `user_id=<UID>` mandatory predicate + no-op-on-empty test.
- **Captured-artifact leakage** → structural-location scrubber (`?access_token=`, `Authorization`,
  `sb-*-auth-token`, `refresh_token`) + ephemeral destroy (security P0-4).
- **Prod mutation on every qualifying merge** → message-free conversation-scoped teardown + queryable
  `live-verify:<run-id>` marker; `retries:0`; rows invisible in operator views (AC14).
- **Flakiness masking the timing bug** → bounded waits on observable WS/DOM state, no fixed sleeps.
- **Detect-fast, not prevent** → post-merge gate means a regression is briefly live; accepted (ADR
  Consequences); prevention would need a prod-realtime preview (deferred).
- **Gate substrate non-determinism** → report-only in agent-postmerge is OK; #5463 blocking flip
  requires GH-Action + Sentry-observable result (ADR-033 Option C).

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
