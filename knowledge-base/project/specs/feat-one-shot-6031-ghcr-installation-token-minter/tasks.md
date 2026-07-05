# Tasks — feat(supply-chain): control-plane Inngest installation-token minter for private-GHCR reads (#6031)

Plan: `knowledge-base/project/plans/2026-07-05-feat-ghcr-installation-token-minter-plan.md`
Lane: cross-domain · Brand-survival threshold: single-user incident (requires_cpo_signoff)
**Hard dependency:** blocked-by #6011 (issue #6005). Do not start work until #6011 is on `origin/main`.

## Phase 0 — Preconditions & empirical GHCR gate (BLOCKING)
- [x] 0.1 Assert `origin/main` has `apps/web-platform/infra/ghcr-read-credential.tf` + `ADR-086-*.md`; halt + rebase onto post-#6011 main if absent.
- [x] 0.2 Run the GHCR installation-token **test matrix** (throwaway script): mint `generateInstallationToken(orgInstallId, {permissions:{packages:"read"}})`, then `docker login ghcr.io -u x-access-token` + `docker pull` under (a) as-is, (b) package linked+granted to a covered repo, (c) org- vs repo-scoped install. Record each outcome in `specs/<branch>/` Phase-0 evidence note.
  - [x] (b) PASS → proceed. If only (a) failed → add package↔repo linkage as a Phase 5/6 config task.
  - [ ] (b) FAIL → halt; write `decision-challenges.md`; do not build the minter.
- [x] 0.3 Confirm the jikig-ai org installation id to mint against (`findInstallationByAccountLogin("jikig-ai")`).
- [ ] 0.4 **Cross-config resolution+isolation assertion (gates the prd_ghcr default):** with the actual consumer `prd`-scoped token, assert `doppler secrets download --config prd` returns the resolved `GHCR_READ_TOKEN` AND that token cannot enumerate `prd_ghcr`. Both hold → prd_ghcr default; else fallback prd-scoped + security sign-off. Keep the spike script uncommitted; never echo the token. Record which scopes the pull actually required (surface any `contents:read` delta).

## Phase 1 — App manifest `packages: read`
- [x] 1.1 Add `"packages": "read"` to `github-app-manifest.json` `default_permissions`.
- [x] 1.2 Update `test/github-app-manifest-parity.test.ts` expected-permission set; green.
- [ ] 1.3 Org-owner re-consent (plane-c grant). Playwright attempt → operator step w/ `playwright-attempt:` evidence if a human gate. Verify: scoped mint returns `permissions.packages == "read"`.

## Phase 2 — Dedicated `prd_ghcr` Doppler config + narrow write token (IaC)
- [x] 2.1 New `ghcr-minter-doppler-token.tf`: `prd_ghcr` config + `prd_ghcr`-scoped read/write `doppler_service_token`.
- [ ] 2.2 Verify Doppler tier supports **cross-config secret referencing**; in `prd`, set `GHCR_READ_TOKEN`/`GHCR_READ_USER = ${soleur.prd_ghcr.…}`. Contingency: fallback `prd`-scoped token + security-sentinel sign-off.
- [x] 2.3 Publish write token as `GHCR_MINTER_DOPPLER_TOKEN` via DIRECT `prd_ghcr` runtime injection (NOT a `prd` cross-ref — that would let every prd reader read the write token). Only the two read-only consumer secrets are cross-referenced into `prd`. App private key stays sourced from `prd`.
- [x] 2.4 Confirm auto-apply resolves; add `-target` if root uses targeted apply. No dev provisioning.

## Phase 3 — Minter Inngest function
- [x] 3.1 Create `server/inngest/functions/cron-ghcr-token-minter.ts` (template: `cron-anthropic-credit-probe.ts`); triggers `[{cron:"*/20 * * * *"},{event:"ghcr/token-minter.mint-now"}]`.
- [x] 3.2 **Single `step.run("mint-and-write")`** — mint+write in ONE step; return metadata-only (`{dopplerStatus, permissionKeys, expiresAt}`), never the token (Inngest persists step returns → leak). **Mint FRESH: assert `expires_at − now ≥ 40 min` before writing** (cache hit can be too stale). Atomic partial-upsert POST to `prd_ghcr` (preserves `GHCR_MINTER_DOPPLER_TOKEN`; not full-replace). Token via env, not argv.
- [x] 3.3 Output-aware terminal Sentry heartbeat: `ok` only on 2xx Doppler write; `error` on mint/write failure. Fail-loud (throw). **Failure-path captures numeric HTTP status ONLY — never request/response body or token** (scrubber is key-name-based, not value-based).
- [x] 3.4 Unit test (deterministic, mocked): scoped-mint body; atomic two-key write; heartbeat ok-only-on-2xx + error; single-step metadata-only return (token never in step return); token string absent from every Sentry field; ≥40-min freshness floor.

## Phase 4 — Five-registry Inngest lockstep (this PR)
- [x] 4.1 `app/api/inngest/route.ts` serves the function.
- [x] 4.2 `server/inngest/cron-manifest.ts` slug in `EXPECTED_CRON_FUNCTIONS`.
- [x] 4.3 `test/server/inngest/function-registry-count.test.ts` count +1; green.
- [x] 4.4 `infra/sentry/cron-monitors.tf` `sentry_cron_monitor` slug `scheduled-ghcr-token-minter` (== handler `SENTRY_MONITOR_SLUG` byte-for-byte; `scheduled-<name>` convention). Reuse `postSentryHeartbeat`.
- [x] 4.5 `.github/workflows/apply-sentry-infra.yml` `-target`; sweep any sentry `-target` scope-guard suite.

## Phase 5 — Event-driven mint (conditional)
- [x] 5.1 `inngest.send("ghcr/token-minter.mint-now")` at the deploy/provision surface; if no clean surface, document the 20-min floor bound and file a follow-up.

## Phase 6 — Cutover / revoke / ADR-C4 / #6023 (post-merge, gated)
- [ ] 6.1 Verify a real deploy + fresh-host boot authenticate with the minted token (telemetry, no SSH).
- [ ] 6.2 Revoke interim machine-account PAT (after 6.1). `Ref #6005`.
- [x] 6.3 Amend ADR-086: status (minter shipped); per-installation `packages:read` blast radius + CPO acceptance; token-at-rest-only scope of prd_ghcr benefit; **the control-plane separation gate (committed here, not a #5274 comment) enumerating BOTH creds to relocate at #5274 cutover — `GITHUB_APP_PRIVATE_KEY` + `prd_ghcr` `GHCR_MINTER_DOPPLER_TOKEN`**.
- [x] 6.4 C4: edit `model.c4`/`views.c4` — add `inngest -> github` (mint) + `inngest -> doppler` (write) edges, correct stale "Public GHCR registry" description; `c4-code-syntax.test.ts` + `c4-render.test.ts` green.
- [ ] 6.5 Close #6023 proactive-PAT-expiry alarm item as moot.
- [x] 6.6 Enroll soak follow-through (`scripts/followthroughs/ghcr-minter-live-6031.sh` + tracker directive + `follow-through` label).

## Exit
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` + full suite green.
- [ ] Pre-merge ACs (AC1–AC9) met; PR body uses `Ref` not `Closes` for #6005/#6023.
