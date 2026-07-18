# Tasks — fix(infra): auto-remediate GitHub Pages cert `bad_authz` (#6657)

Plan: `knowledge-base/project/plans/2026-07-18-fix-gh-pages-cert-bad-authz-auto-reissue-plan.md`
Lane: single-domain · Threshold: aggregate pattern

## Phase 0 — Live preconditions (read-only; pin outputs in the PR/spec)

- [ ] 0.1 Re-read live cert state: `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate'` → confirm `bad_authz`, `expires_at`.
- [ ] 0.2 Verify App **live installation grant** includes `administration: write` (scoped-token mint succeeds, OR read `X-Accepted-GitHub-Permissions` on a dry `PUT /pages`). If missing → activate the `github-app-manifest.json` change + founder re-acceptance split.
- [ ] 0.3 Verify the app/Inngest runtime holds a **DNS:edit zone-scoped** CF token that can list + (dry) patch all 4 apex A-records + www CNAME proxied flags. `CF_API_TOKEN_PURGE` (cache-purge) is INSUFFICIENT. If absent → Phase 2.6 provisions a scoped `cloudflare_api_token` + `doppler_secret` to `prd` (IaC, no manual mint).
- [ ] 0.4 Re-confirm carve-out healthy (ACME path `404`, `always_use_https=off`, CAA empty, `_github-pages-challenge` TXT present).
- [ ] 0.5 Confirm CF zone SSL mode (Full vs Full-Strict) — document (not changed).

## Phase 1 — Remediation logic (TDD: failing tests first) — ONE FILE

- [ ] 1.1 In `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts` write pure injectable helpers: `assertStuckState` (allowlist `{bad_authz,failed}`), `checkReissuePreconditions`, `setRecordsProxied(records,bool)` (partial-toggle→abort), `reissueViaCnameToggle`, `pollCertState`, `restoreState(captured{cname,proxied})` (idempotent). CF DNS PATCH inline, mirroring `cf-cache-purge.ts` (Bearer + AbortController + reportSilentFallback). No separate module, no CF-client class.
- [ ] 1.2 Create `test/server/inngest/cron-gh-pages-cert-reissue.test.ts` — Test Scenarios 1–8 RED first: happy path; **`onFailure` (not `finally`) restores symmetric `{cname,proxied}` on throw**; poll-timeout; stuck-state allowlist abort (issued/in-flight → zero writes); precondition-blocked; partial-toggle/4xx → `reissue_failed`; restore-fail P0; freeze-lock defers drift.
- [ ] 1.3 Implement until GREEN.

## Phase 2 — Inngest function + wiring (replay-safe per ADR-077)

- [ ] 2.1 Registration: no `cron:`; event `cron/gh-pages-cert-reissue.manual-trigger`; concurrency fn+account=1; retries 1. **Structure:** step 1 = toggle+reissue (single `step.run`); `step.sleep` poll loop; unconditional final restore step; **`onFailure` handler** = idempotent `restoreState` + lock release. Verify SDK `onFailure` signature vs pinned `inngest` (no existing precedent).
- [ ] 2.2 Acquire/release the **ADR-089 freeze-lock** on `github_pages`/`www`; ensure `cron-terraform-drift` + `apply-web-platform-infra` honor it.
- [ ] 2.3 Add `"cron-gh-pages-cert-reissue"` to `EXPECTED_CRON_FUNCTIONS`; update `function-registry-count.test.ts` + Inngest inventory count. Add `routine-metadata.ts` row (`manualTrigger: "allowed"`). Register in functions index/serve.
- [ ] 2.4 Assert least-privilege scoped mint (`administration:write` + `repositories:["soleur"]`).
- [ ] 2.5 (If Phase 0.3 found no DNS-edit token) Provision scoped `cloudflare_api_token` (DNS:edit) + `doppler_secret` to `prd` (IaC).

## Phase 3 — Poll cron (v1: text-only) + defer self-heal

- [ ] 3.1 Edit `cron-gh-pages-cert-state.ts` issue body to reference the scripted reissue trigger (not the #3976 console step). **No auto-invoke logic in v1.**
- [ ] 3.2 File the **v2 self-heal deferral issue** (Flagsmith flag default OFF + cooldown store + auto-invoke branch + freeze-lock under autonomous timing). Re-eval after ≥1 live manual success.

## Phase 4 — Observability (IaC)

- [ ] 4.1 Emit one structured Sentry terminal event per outcome (`reportSilentFallback` / `mirrorP0Deduped`) with discriminating fields.
- [ ] 4.2 Declare reissue-P0 issue-alert in `infra/sentry/*.tf` (reuse existing paging; no new paid monitor). Verify against `soleur_acme_probe`.

## Phase 5 — ADR + C4 + AP-019

- [ ] 5.1 Author **ADR-125** (provisional) via `/soleur:architecture`: `## Decision` frames the AP-001 **exception** (not compliance-by-no-drift); references ADR-077 (replay-safety) + ADR-089 (freeze-lock) + ADR-038 (deferred flag); `## Alternatives` incl. rejected JS-`finally`.
- [ ] 5.2 Add **AP-019** row to `principles-register.md` (sanctioned transient runtime CF-DNS toggle).
- [ ] 5.3 Edit `model.c4` + `views.c4`: `inngest→cloudflare` DNS-toggle edge + `api→github` cert-admin capability + `view include`. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 6 — Verify + ship

- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 6.2 `./node_modules/.bin/vitest run test/server/inngest/cron-gh-pages-cert-reissue.test.ts test/server/inngest/cron-gh-pages-cert-state.test.ts` green + full-suite exit gate.
- [ ] 6.3 PR body uses `Ref #6657` (not `Closes`).

## Phase 7 — Post-merge live remediation (automated, no console)

- [ ] 7.1 Fire `cron/gh-pages-cert-reissue.manual-trigger` via `POST /api/internal/trigger-cron` (trigger-cron skill).
- [ ] 7.2 Verify `.https_certificate.state` → `approved/issued`; `curl -sSI https://soleur.ai/` + `www` → `HTTP/2 200`.
- [ ] 7.3 `terraform plan` shows apex+www `proxied=true` (no drift). Close #6657 (or let the poll cron auto-close).
