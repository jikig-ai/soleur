# Tasks: feat-seo-gsc-indexing-fixes

Plan: `knowledge-base/project/plans/2026-05-05-feat-gsc-indexing-fixes-plan.md`
Issue: #3297 — Branch: `feat-seo-gsc-indexing-fixes` — PR: #3296
Brand-survival threshold: `single-user incident`

## Phase 1: Hostname canonicalization

- [ ] 1.1 Edit `plugins/soleur/docs/_data/site.json`: change `url` to `"https://www.soleur.ai"`.
- [ ] 1.2 Edit `plugins/soleur/docs/robots.txt`: change `Sitemap:` line to `https://www.soleur.ai/sitemap.xml`.
- [ ] 1.3 Run `npx @11ty/eleventy` and verify `rg 'https://soleur\.ai(/|[a-zA-Z]|$)' _site/` returns zero matches. If hits found, route the hardcoded apex through `{{ site.url }}`.
- [ ] 1.4 Edit `plugins/soleur/docs/scripts/validate-seo.sh`: add canonical-host gate that asserts `_site/sitemap.xml` `<loc>` entries all use the host parsed from `site.url`. Fail build on mismatch.
- [ ] 1.5 Edit `.github/workflows/deploy-docs.yml`: add post-build step running the apex-grep above. Fail workflow if matches.

## Phase 2: Cloudflare rulesets (Terraform)

- [ ] 2.1 Edit `apps/web-platform/infra/variables.tf`: update description on `cf_api_token_rulesets` to reflect new scope (Cache Rules:Edit + Zone WAF:Edit + Single Redirect Rules:Edit + Transform Rules:Edit).
- [ ] 2.2 Create `apps/web-platform/infra/seo-rulesets.tf` with two `cloudflare_ruleset` resources:
  - [ ] 2.2.1 `seo_page_redirects` — `kind = "zone"`, `phase = "http_request_dynamic_redirect"`, `provider = cloudflare.rulesets`. 19 `rules` blocks (one per row in the plan's mapping table) with `action = "redirect"` and `action_parameters.from_value` (`status_code = 301`, `target_url { value = "..." }`, `preserve_query_string = false`).
  - [ ] 2.2.2 `seo_response_headers` — `kind = "zone"`, `phase = "http_response_headers_transform"`, same provider. 3 `rules` blocks with `action = "rewrite"` and v4-style nested `headers { name = "X-Robots-Tag", operation = "set", value = "..." }` blocks.
- [ ] 2.3 Verify v4 nested-block syntax (NOT v5 attribute-map) by referencing `apps/web-platform/infra/cache.tf` (existing v4-validated template).

## Phase 3: Pre-merge verification

- [ ] 3.1 Run `terraform validate` with Doppler-injected env (nested `doppler run` per `variables.tf` header comment). Must pass.
- [ ] 3.2 Capture pre-change curl baselines and attach to PR description:
  - `curl -IA "Mozilla/5.0" https://deploy.soleur.ai/`
  - `curl -IA "Googlebot" https://api.soleur.ai/`
  - `curl -IA "Googlebot" https://www.soleur.ai/blog/feed.xml`
  Confirm none currently include `X-Robots-Tag`.
- [ ] 3.3 Push branch; mark PR #3296 ready for review.
- [ ] 3.4 Run review pipeline (DHH + Kieran + simplicity + `user-impact-reviewer` + CPO sign-off).
- [ ] 3.5 Resolve all P0/P1 review findings inline.
- [ ] 3.6 Verify PR body uses `Ref #3297`, NOT `Closes #3297` (ops-only-prod-write classification).
- [ ] 3.7 Verify PR body has `## Changelog` section + `semver:patch` label.

## Phase 4: Post-merge operator runbook

(Each command requires explicit per-command go-ahead per `hr-menu-option-ack-not-prod-write-auth`.)

- [ ] 4.1 Operator: expand `cf_api_token_rulesets` scope in Cloudflare dashboard to include Single Redirect Rules:Edit + Transform Rules:Edit on `Zone:soleur.ai`. Update Doppler if token rotated.
- [ ] 4.2 Operator: `cd apps/web-platform/infra && doppler run … terraform plan -out=seo-fixes.tfplan`. Review diff (expect 2 new rulesets, 22 rules; no drift on existing).
- [ ] 4.3 Operator confirms; run `terraform apply -auto-approve seo-fixes.tfplan`.
- [ ] 4.4 Wait 60s for ruleset propagation.
- [ ] 4.5 Confirm `deploy-docs.yml` workflow conclusion is `success` post-merge: `gh run list --workflow=deploy-docs.yml --limit 1 --json status,conclusion,databaseId`.
- [ ] 4.6 Cache purge: `curl -X POST` against `purge_cache` API for sitemap.xml + robots.txt + feed.xml using `CF_API_TOKEN_PURGE` from Doppler `prd`.
- [ ] 4.7 Run curl verification suite (Vector 1, 2, 3, 4 — see plan Phase 4 step 6). All must pass.
- [ ] 4.8 GSC re-validation: try Playwright MCP to click "Validate fix" on each of 5 critical-issue categories. Operator-fallback if Playwright session can't auth.
- [ ] 4.9 Close issue: `gh issue close 3297 --comment "Verified live: see PR #<merged-pr> Phase 4 curl results."`
- [ ] 4.10 Create follow-up tracking issue (Phase 5 below).

## Phase 5: Follow-up issue creation

- [ ] 5.1 Run `gh issue create --title "feat(seo): migrate blog redirects + delete page-redirects meta-refresh templates" --milestone "Post-MVP / Later" --body "<see plan Phase 5>"`.
- [ ] 5.2 Update `knowledge-base/product/roadmap.md` if a more specific phase fits.

## Phase 6: 7-day observation

- [ ] 6.1 Day +3: re-export GSC Critical issues CSV; verify category counts trending toward zero.
- [ ] 6.2 Day +7: re-export and assert "Page with redirect" ≤ 2 (only unavoidable apex HTTP→HTTPS), other categories at 0 or expected.
- [ ] 6.3 If counts not improving, investigate: cache propagation, sitemap regen, ruleset firing on Access challenge.
