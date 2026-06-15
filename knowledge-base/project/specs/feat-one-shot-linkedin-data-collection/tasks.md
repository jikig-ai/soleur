---
title: "Tasks: LinkedIn Company Page data collection in the community monitor"
plan: knowledge-base/project/plans/2026-06-15-feat-linkedin-company-page-data-collection-plan.md
branch: feat-one-shot-linkedin-data-collection
lane: single-domain
date: 2026-06-15
---

# Tasks — LinkedIn Company Page data collection

Derived from the finalized (deepened) plan. Aggregate-only collection: share statistics +
single follower total + recent org post metadata. **No follower demographic facets** (cut
at deepen-plan — YAGNI + GDPR + silent-failure convergence).

## Phase 0 — Preconditions (verify-before-write)

- [x] 0.1 Confirm stub lines `linkedin-community.sh:362-372`, usage headers `:7-8` + `:385-386` still match.
- [x] 0.2 Re-grep cron test anchor lists + `buildSpawnEnv` positive/negative classes (`cron-community-monitor.test.ts:190-273`).
- [x] 0.3 Confirm `get_request` signature `(endpoint, depth)`, Bearer reads `LINKEDIN_ACCESS_TOKEN`; exit-2 path is in `get_request:122-125` (not `handle_response`).
- [x] 0.4 Re-confirm no negative-class substring collision for `LINKEDIN_ORG_ACCESS_TOKEN` / `LINKEDIN_ORG_ID` (verified 2026-06-15 — none).
- [x] 0.5 (Done at deepen-plan) networkSizes + FINDER header contracts verified live against `LinkedIn-Version: 202602`.

## Phase 1 — linkedin-community.sh: fetch-metrics + fetch-activity (RED tests first)

- [x] 1.1 Add `require_org_credentials()` — `exit 1` (NOT `return 1`), fails when `LINKEDIN_ORG_ACCESS_TOKEN` OR `LINKEDIN_ORG_ID` unset; stderr names missing var(s); never fall back to personal token.
- [x] 1.2 Thread optional `extra_header` (3rd arg) through `get_request` + forward it on the 429 recursion at `:144`.
- [x] 1.3 Implement `cmd_fetch_metrics`: cred check FIRST, then `local LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"`; call `organizationalEntityShareStatistics` (`%3A`-encoded URN) + `networkSizes?edgeType=COMPANY_FOLLOWED_BY_MEMBER`; shape-validate `.elements[0].totalShareStatistics` before `// 0` fallbacks; networkSizes failure → `total_followers: null` (not abort); emit `{org_id, total_followers, share_statistics}` via `jq -n`. No demographic facets. No `{}`-soft-success idiom.
- [x] 1.4 Implement `cmd_fetch_activity`: cred check + `local` token; Posts author-finder `?author=...&q=author&count=10&sortBy=LAST_MODIFIED` with `X-RestLi-Method: FINDER` via the new arg; emit `{posts:[{id,commentary,published_at,lifecycle_state}]}`; INDEX/`//` fallbacks.
- [x] 1.5 Update usage/comment headers (`:7-8`, `:385-386`) — drop "Marketing API"/"MDP"; add org-read-scope + date-anchored note + org env vars.
- [x] 1.6 Update `main()` dispatch — run `require_org_credentials` before fetch-metrics/fetch-activity arms; leave post-content's `require_credentials` unchanged.

## Phase 2 — community-router.sh (verify)

- [x] 2.1 Confirm no route change needed (exec passthrough).
- [x] 2.2 Record accepted-debt note: `linkedin` registry `required_env_vars` intentionally gates on posting creds, not org-read creds (separate axis, deliberately unmodeled).

## Phase 3 — cron-community-monitor.ts

- [x] 3.1 Edit `COMMUNITY_MONITOR_PROMPT:173` — replace "skip — log enabled (posting only)" with literal-path `community-router.sh linkedin fetch-metrics` (and optional fetch-activity); "log the error and continue".
- [x] 3.2 Update `## LinkedIn Activity` digest instruction (`:186`) — total followers + aggregate engagement; on failure write explicit "collection failed: <reason>" line (not silent omit).
- [x] 3.3 Add `LINKEDIN_ORG_ACCESS_TOKEN` + `LINKEDIN_ORG_ID` to `buildSpawnEnv` allowlist (`:236-255`, explicit, no spread); update comments `:220-235` + `:33-36`.
- [x] 3.4 Add code comment near `:173` noting collection only fires once cron restored from `TIER2_DEFERRED_CRONS`.

## Phase 4 — Tests

- [x] 4.1 New `test/linkedin-community.test.ts` (bun:test): cred-missing → exit 1; silent-fallback negative (personal token present + org absent → exit 1, no net, no "401"); jq-transform unit tests via stdin for share-stats + posts; empty-`elements` fixture does not render fake zeros; synthetic creds (`LINKEDIN_ORG_ID=12345`).
- [x] 4.2 `test/helpers/test-handle-response-linkedin.sh` (sources `linkedin-community.sh:409`): assert LinkedIn's actual handler — 403 generic message only (no reason branching); exit-2 via `get_request` depth=3, not handle_response.
- [x] 4.3 Register suite in `scripts/test-all.sh` `want_bun()` block (`146-150`): `run_suite "test/linkedin-community" bun test test/linkedin-community.test.ts`.
- [x] 4.4 `cron-community-monitor.test.ts`: add `LINKEDIN_ORG_ACCESS_TOKEN` + `LINKEDIN_ORG_ID` to positive-class `it.each` (`:191-206`); add prompt anchor for `linkedin fetch-metrics` literal path; keep all existing anchors.

## Phase 5 — Verify + ship

- [ ] 5.1 `bash scripts/test-all.sh bun` green (suite appears); `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` + `./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts` green.
- [ ] 5.2 Run `/soleur:gdpr-gate` — confirm aggregate-only, record joint-controller trigger fired (gated by Tier-2 deferral).
- [ ] 5.3 PR body: `Closes #4049`, `## Changelog`, `semver:minor`.
