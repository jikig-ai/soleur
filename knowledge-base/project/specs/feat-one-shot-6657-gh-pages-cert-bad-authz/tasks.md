# Tasks — fix(infra): auto-remediate GitHub Pages cert `bad_authz` (#6657)

Plan: `knowledge-base/project/plans/2026-07-18-fix-gh-pages-cert-bad-authz-auto-reissue-plan.md`
Lane: single-domain · Threshold: aggregate pattern

> **CTO ruling 2026-07-18 (see session-state.md):** no runtime freeze-lock substrate exists.
> AC8b + Finding #4 (freeze-lock coordination) DESCOPED to the v2 deferral issue (#6677).
> v1 ships lock-free with a residual-race Sharp Edge + the Sentry P0 backstop.

## Phase 0 — Live preconditions (read-only) — DONE

- [x] 0.1 Live cert state = `bad_authz`, expires 2026-08-16, cname soleur.ai.
- [x] 0.2 App manifest declares `administration: write` (live grant verified at reissue-time / mint returns granted keys).
- [x] 0.3 No DNS-edit token in `prd` runtime (only `CF_API_TOKEN_PURGE`) → Phase 2.5 provisions a scoped one.
- [x] 0.4 Carve-out healthy (ACME 404 apex+www, `always_use_https=off`, CAA empty, challenge TXT present).
- [x] 0.5 CF zone SSL via `cloudflare_zone_settings_override` (documented; not changed).

## Phase 1 — Remediation logic (TDD) — DONE

- [x] 1.1 Pure injectable helpers in `cron-gh-pages-cert-reissue.ts` (assertStuckState, checkReissuePreconditions, setRecordsProxied partial-abort, reissueViaCnameToggle, pollCertState, restoreState). CF PATCH inline (cf-cache-purge shape).
- [x] 1.2 `test/server/inngest/cron-gh-pages-cert-reissue.test.ts` — Scenarios 1–7 (8=freeze-lock → v2).
- [x] 1.3 GREEN (69 → 82 tests pass, tsc clean).

## Phase 2 — Inngest function + wiring — DONE

- [x] 2.1 Registration: no `cron:`; event `cron/gh-pages-cert-reissue.manual-trigger`; concurrency fn+account=1; retries 1; onFailure handler; step.run toggle+reissue; step.sleep poll; final restore step.
- [~] 2.2 Freeze-lock — DESCOPED to v2 (#6677). No runtime substrate exists.
- [x] 2.3 `EXPECTED_CRON_FUNCTIONS` += entry; `function-registry-count.test.ts` 63→64; `routine-metadata.ts` row; route.ts import+array.
- [x] 2.4 Least-privilege scoped mint (`administration:write` + `repositories:["soleur"]`).
- [ ] 2.5 Provision scoped `cloudflare_api_token` (DNS:edit) + `doppler_secret` to prd (IaC) — terraform-architect agent.

## Phase 3 — Poll cron (text-only) + defer self-heal — DONE

- [x] 3.1 `cron-gh-pages-cert-state.ts` issue body → scripted reissue trigger. No auto-invoke.
- [x] 3.2 v2 self-heal + freeze-lock deferral issue filed → **#6677**.

## Phase 4 — Observability (IaC) — DONE

- [x] 4.1 One structured terminal event per outcome via `reportSilentFallback` (discriminating fields).
- [x] 4.2 `sentry_issue_alert.gh_pages_cert_reissue_failed` in `infra/sentry/issue-alerts.tf` (feature-tag filter; no new monitor).

## Phase 5 — ADR + C4 + AP-019 — DONE

- [x] 5.1 ADR-125 (AP-001 exception framing; references ADR-077/033; ADR-089 NOT cited as runtime lock).
- [x] 5.2 AP-019 row in `principles-register.md`.
- [x] 5.3 `model.c4` `api→cloudflare` DNS-toggle edge + `api→github` cert-admin; regenerated `model.likec4.json`; c4 tests pass.

## Phase 6 — Verify + ship

- [x] 6.1 `tsc --noEmit` clean.
- [x] 6.2 Targeted vitest green; full-suite exit gate — pending final run.
- [ ] 6.3 PR body uses `Ref #6657` (not `Closes`).

## Phase 7 — Post-merge live remediation (automated, no console)

- [ ] 7.1 Fire `cron/gh-pages-cert-reissue.manual-trigger` via `POST /api/internal/trigger-cron`.
- [ ] 7.2 Verify `.https_certificate.state` → `approved/issued`; curl apex+www → 200.
- [ ] 7.3 `terraform plan` shows apex+www `proxied=true` (no drift). Close #6657.
