# Tasks — fix(infra): auto-remediate GitHub Pages cert `bad_authz` (#6657)

Plan: `knowledge-base/project/plans/2026-07-18-fix-gh-pages-cert-bad-authz-auto-reissue-plan.md`
Lane: single-domain · Threshold: aggregate pattern

## Phase 0 — Live preconditions (read-only; pin outputs in the PR/spec)

- [ ] 0.1 Re-read live cert state: `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate'` → confirm `bad_authz`, `expires_at`.
- [ ] 0.2 Verify App **live installation grant** includes `administration: write` (scoped-token mint succeeds, OR read `X-Accepted-GitHub-Permissions` on a dry `PUT /pages`). If missing → activate the `github-app-manifest.json` change + founder re-acceptance split.
- [ ] 0.3 Verify CF token (Doppler `prd_terraform`) can list + (dry) patch `cloudflare_record.github_pages` + `.www` proxied flags.
- [ ] 0.4 Re-confirm carve-out healthy (ACME path `404`, `always_use_https=off`, CAA empty, `_github-pages-challenge` TXT present).
- [ ] 0.5 Confirm CF zone SSL mode (Full vs Full-Strict) — document (not changed).

## Phase 1 — Remediation module (TDD: failing tests first)

- [ ] 1.1 Create `apps/web-platform/server/gh-pages-cert-reissue.ts` (or `_cert-reissue-shared.ts`): pure `checkReissuePreconditions`, `reissueViaCnameToggle`, `pollCertState`, `setApexProxied`, thin CF-API client (`listApexRecords`, `patchRecordProxied`). Injectable Octokit + CF client (no live IO in pure fns).
- [ ] 1.2 Create `apps/web-platform/test/server/inngest/cron-gh-pages-cert-reissue.test.ts` — Test Scenarios 1–7 (happy path; `finally` restore on throw; poll-timeout; cooldown no-op; precondition-blocked; expiry-not-reissue; proxy-restore-fail P0). RED first.
- [ ] 1.3 Implement until GREEN.

## Phase 2 — Inngest function + wiring

- [ ] 2.1 Create `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts` (mirror `cron-gh-pages-cert-state.ts` registration; no `cron:`; event `cron/gh-pages-cert-reissue.manual-trigger`; concurrency fn+account=1; retries 1; steps in `step.run`, poll via `step.sleep`).
- [ ] 2.2 Add `"cron-gh-pages-cert-reissue"` to `EXPECTED_CRON_FUNCTIONS` (`cron-manifest.ts`); update `function-registry-count.test.ts` + Inngest inventory count.
- [ ] 2.3 Add `routine-metadata.ts` row (`manualTrigger: "allowed"`).
- [ ] 2.4 Register `cronGhPagesCertReissue` in the functions index/serve.
- [ ] 2.5 Assert least-privilege scoped mint (`administration:write` + `repositories:["soleur"]`).

## Phase 3 — Self-heal wiring in the poll cron

- [ ] 3.1 Edit `cron-gh-pages-cert-state.ts`: on **state-tripped** `bad_authz`/`failed` + healthy preconditions + cooldown elapsed, invoke reissue before the file/comment path; expiry-only warning unchanged.
- [ ] 3.2 Cooldown/attempt-cap constants (respect LE 5/hr · 50/week). Ship auto-invoke conservatively (deepen-plan decides enabled-vs-dispatch-first).
- [ ] 3.3 Extend `cron-gh-pages-cert-state.test.ts` source-shape anchors.

## Phase 4 — Observability (IaC)

- [ ] 4.1 Emit one structured Sentry terminal event per outcome (`reportSilentFallback` / `mirrorP0Deduped`) with discriminating fields.
- [ ] 4.2 Declare reissue-P0 issue-alert in `infra/sentry/*.tf` (reuse existing paging; no new paid monitor). Verify against `soleur_acme_probe`.

## Phase 5 — ADR + C4

- [ ] 5.1 Author ADR-`<next>` (Decision + Alternatives) via `/soleur:architecture`.
- [ ] 5.2 Edit `model.c4` + `views.c4`: `inngest→cloudflare` proxy-toggle edge + `api→github` cert-admin capability + `view include`. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 6 — Verify + ship

- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 6.2 `./node_modules/.bin/vitest run test/server/inngest/cron-gh-pages-cert-reissue.test.ts test/server/inngest/cron-gh-pages-cert-state.test.ts` green + full-suite exit gate.
- [ ] 6.3 PR body uses `Ref #6657` (not `Closes`).

## Phase 7 — Post-merge live remediation (automated, no console)

- [ ] 7.1 Fire `cron/gh-pages-cert-reissue.manual-trigger` via `POST /api/internal/trigger-cron` (trigger-cron skill).
- [ ] 7.2 Verify `.https_certificate.state` → `approved/issued`; `curl -sSI https://soleur.ai/` + `www` → `HTTP/2 200`.
- [ ] 7.3 `terraform plan` shows apex+www `proxied=true` (no drift). Close #6657 (or let the poll cron auto-close).
