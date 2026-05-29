---
feature: feat-one-shot-noindex-api-deploy-subdomains
issue: 4575
lane: single-domain
plan: knowledge-base/project/plans/2026-05-29-fix-noindex-api-deploy-subdomains-coverage-plan.md
---

# Tasks — SEO noindex api./deploy. subdomains (reconcile #4575)

Derived from the finalized plan. The proposed edge rules ALREADY EXIST and `deploy.` is
already noindexed live; this is a reconciliation + CI regression guard + close-as-superseded.

## Phase 1 — Reconcile (read-only verification)

- [x] 1.1 Re-confirm live state (bounded curl):
      `curl -sI -X GET --max-time 15 https://deploy.soleur.ai/ | grep -i x-robots-tag`
      → expect `x-robots-tag: noindex, nofollow`.
      `curl -sI -X GET --max-time 15 https://api.soleur.ai/ | grep -i x-robots-tag`
      → expect NO header (dormant rule, per #3379).
- [x] 1.2 Confirm `apps/web-platform/infra/seo-rulesets.tf` `cloudflare_ruleset.seo_response_headers`
      contains both the `api.soleur.ai` (lines ~319-337) and `deploy.soleur.ai` (~339-351) rules,
      each setting `X-Robots-Tag` = `noindex, nofollow`.
- [x] 1.3 Confirm `cloudflare_record.api` is `proxied = false` and `cloudflare_record.deploy` is
      `proxied = true` in `apps/web-platform/infra/dns.tf` (explains the no-op asymmetry).

## Phase 2 — Regression guard (RED → GREEN) [AC1, AC2]

- [x] 2.1 RED: write `apps/web-platform/test/seo-rulesets-noindex.test.ts` mirroring
      `apps/web-platform/test/github-app-manifest-parity.test.ts` — import `{ describe, test, expect }`
      from `vitest` + `{ readFileSync }` from `node:fs`; `REPO_ROOT = path.resolve(__dirname, "../../..")`;
      read `apps/web-platform/infra/seo-rulesets.tf` as a string.
- [x] 2.2 Assert the `deploy.soleur.ai` rule exists: source matches `http.host eq "deploy.soleur.ai"`
      AND header `X-Robots-Tag` value `noindex, nofollow` (pin the full value, not just `noindex` — AC2).
- [x] 2.3 Assert the `api.soleur.ai` rule exists: source matches `http.host eq "api.soleur.ai"`
      AND `X-Robots-Tag` value containing `noindex` (AC1).
- [x] 2.4 GREEN: run `./node_modules/.bin/vitest run test/seo-rulesets-noindex.test.ts` from
      `apps/web-platform/` (NOT `bun test` — bunfig.toml blocks discovery). Confirm pass.
      Verify RED first by temporarily mutating the `deploy.` value and confirming the test fails.

## Phase 3 — Cross-link comments [AC3]

- [x] 3.1 Edit the `api.soleur.ai` no-op comment block in `seo-rulesets.tf` to reference BOTH #3379
      (existing) and #4575 (this issue, as superseded-by). Comment-only — no resource/expression/header
      body change (AC4).
- [x] 3.2 Verify: `grep -nE '#3379|#4575' apps/web-platform/infra/seo-rulesets.tf` returns both numbers.

## Phase 4 — Validate + ship [AC4, AC5]

- [x] 4.1 Confirm PR diff adds no new `resource "cloudflare_*"` block and edits no `expression`/`headers`
      body inside `seo_response_headers` (AC4).
- [x] 4.2 Confirm Alternatives table in the plan names #3379 as the owner of the `api.`-proxy decision;
      do NOT file a new tracking issue (would double-count #3379) (AC5).
- [x] 4.3 PR body uses `Ref #4575` (NOT `Closes`) — close is a post-merge step after live verification.

## Phase 5 — Post-merge (automation) [AC6, AC7, AC8]

- [x] 5.1 On merge, `apply-web-platform-infra.yml` auto-applies; confirm run log shows
      `0 to add, 0 to change, 0 to destroy` for `seo_response_headers` (comment-only no-op) (AC6).
- [x] 5.2 `/soleur:ship` post-merge: re-run the AC7 curl — `deploy.` still returns
      `x-robots-tag: noindex, nofollow`; `api.` still 404 with no header (AC7).
- [x] 5.3 `gh issue close 4575` with comment linking the regression-guard PR and #3379 (AC8).
