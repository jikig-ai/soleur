# Tasks — fix-linkedin-org-token-probe (#9181)

Plan: `knowledge-base/project/plans/2026-09-28-fix-linkedin-org-token-probe-plan.md`

## Phase 1 — Cron per-token probe + renewal body (TDD)

- [x] 1.1 Update `apps/web-platform/test/server/inngest/cron-linkedin-token-check.test.ts` first (failing tests):
  - [x] 1.1.1 Fetch mocks keyed per URL — `api.linkedin.com/v2/userinfo` for `LINKEDIN_ACCESS_TOKEN`, `api.linkedin.com/v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED` for `LINKEDIN_ORG_ACCESS_TOKEN`.
  - [x] 1.1.2 New case: org ACL `200` → `valid` + stale-issue auto-close.
  - [x] 1.1.3 New case: org ACL `403` → action-required filing (not `unknown`), body names HTTP code + Community-app generator URL.
  - [x] 1.1.4 Probe-routing assertion: assert fetch was called with the ACL URL for the org leg and userinfo for the personal leg.
  - [x] 1.1.5 Source anchors: add `organizationalEntityAcls` and `78s808ujpe6lve`; keep `api.linkedin.com/v2/userinfo`.
  - [x] 1.1.6 bootstrap.sh anchor block (read the file, assert `78s808ujpe6lve`, org stage routes through `LINKEDIN_ORG_ACLS`, `token_probe` is endpoint-parameterized).
  - [x] 1.1.7 Confirm new tests are RED.
- [x] 1.2 Edit `apps/web-platform/server/inngest/functions/cron-linkedin-token-check.ts`:
  - [x] 1.2.1 Replace `LINKEDIN_USERINFO_URL` with a per-token probe table keyed by env-var name (url + app label). A `tokenName` absent from the table must fail LOUD (`reportSilentFallback` + status `unknown`) — never default to an endpoint.
  - [x] 1.2.2 `checkToken` resolves the probe per `tokenName`; `holder` tolerates the ACL `{elements:[...]}` shape (no `name` field — use administered-org count).
  - [x] 1.2.3 `401` → `expired` unchanged; `403` on the resolved probe files the same per-token issue title with an HTTP-code-aware body; other non-2xx stays `unknown`. Add `httpStatus` to the result's logger extras.
  - [x] 1.2.4 Renewal body per token: Soleur app (`78wtm2wu15iikn`, `openid, profile, w_member_social, email`) vs Community app (`78s808ujpe6lve`, "all offered scopes; `w_organization_social` + `rw_organization_admin` mandatory").
  - [x] 1.2.5 Rename the `op: "fetch-userinfo"` reportSilentFallback tag to a per-probe value (verified: no Sentry alert filters consume the tag).
  - [x] 1.2.6 Keep `TokenCheckResult` shape unchanged (Inngest `step.run` memoization: in-flight runs resume on the new code).
- [x] 1.3 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-linkedin-token-check.test.ts` — GREEN (NOT `bun test`; bunfig blocks discovery). Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 2 — Bootstrap script per-token probes

- [x] 2.1 Edit `knowledge-base/project/specs/feat-linkedin-token-renewal/bootstrap.sh`:
  - [x] 2.1.1 Split `TOKEN_GENERATOR_URL` → `TOKEN_GENERATOR_URL_PERSONAL` (`78wtm2wu15iikn`) / `TOKEN_GENERATOR_URL_ORG` (`78s808ujpe6lve`).
  - [x] 2.1.2 `token_probe <value> <url>` and `token_is_live <value> <url>` take the endpoint as a parameter; update messages that hardcode "userinfo".
  - [x] 2.1.3 `mint_or_reuse` gains `<generator-url>` and `<probe-url>` params; keep the `SOLEUR_BOOTSTRAP_*` skip-var token on the same call line (usage() grep derives it).
  - [x] 2.1.4 `stage_1_personal` → userinfo probe + personal generator URL (scope list unchanged).
  - [x] 2.1.5 `stage_2_org` → ACL probe + Community generator URL + corrected scope text ("all offered scopes; `w_organization_social` + `rw_organization_admin` mandatory"); DELETE the advisory ACL block (primary probe is now the ACL probe).
  - [x] 2.1.6 `stage_4_verify` probes each Doppler value at its per-token endpoint; parameterize the "(userinfo 2xx)" message.
  - [x] 2.1.7 Update the scope-table header comment (~L236) and closeout prose (~L631) that claim both tokens probe userinfo.
- [x] 2.2 `bash -n bootstrap.sh` clean; `bash bootstrap.sh --help` still lists `SOLEUR_BOOTSTRAP_LINKEDIN_ACCESS_TOKEN` / `SOLEUR_BOOTSTRAP_LINKEDIN_ORG_ACCESS_TOKEN`.
- [x] 2.3 Do NOT touch `plugins/soleur/skills/operator-bootstrap/template.sh` or `operator-script.sh` — #9146 is out of scope.

## Phase 3 — Closeout wiring

- [x] 3.1 File follow-up issue for `apps/web-platform/server/token-validators.ts:54` (linkedin provider probes userinfo; Community-app tokens 403 — same defect class, different surface).
- [x] 3.2 PR body: `Closes #9181`. Do NOT list `Closes #7606` — it auto-closes via the deployed cron.
- [x] 3.3 Post-merge verification (documented in PR body): after the release deploys, dispatch `cron/linkedin-token-check.manual-trigger` via the repo's trigger-cron path; confirm #7606 gets "is valid. Auto-closing." + closed state.

## Testing

- [x] T1 Scoped vitest run for `cron-linkedin-token-check.test.ts` green.
- [x] T2 `bash -n` on bootstrap.sh; `--help` output spot-checked.
- [x] T3 Grep sweep: `78wtm2wu15iikn` remains ONLY on the personal-token paths; `78s808ujpe6lve` present on the org paths in both files.
