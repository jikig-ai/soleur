---
title: "Tasks — Fix GSC legal-page redirects via Cloudflare Bulk Redirects"
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-09-fix-gsc-legal-page-redirects-plan.md
date: 2026-06-09
---

# Tasks — GSC legal-page 301s (Cloudflare Bulk Redirects, Free tier)

Derived from `2026-06-09-fix-gsc-legal-page-redirects-plan.md`. The plan deliberately
diverges from the one-shot description's `regex_replace()` approach (paid-tier-blocked) to
a Free-tier Cloudflare **Bulk Redirects** list. Provider is pinned `cloudflare ~> 4.0`
(4.52.7) — **all HCL uses v4 BLOCK syntax**, `terraform validate` is the catch.

## Phase 0 — Preconditions

- [x] 0.1 Confirm provider pin `4.52.7` via `apps/web-platform/infra/.terraform.lock.hcl`; commit to v4 syntax.
      (Re-verified on resume 2026-06-09: `version = "4.52.7"`, `constraints = "~> 4.0"`.)
- [x] 0.2 Read `apps/web-platform/infra/tunnel.tf` (account-level `cloudflare_ruleset` v4 block template) and
      `cache.tf` (nested-block ruleset rules template).
- [x] 0.3 Determine Bulk Redirects token scope: does `cf_api_token_rulesets` carry `Account Rulesets:Edit`
      + `Account Filter Lists:Edit`? Record yes/no — drives the post-merge token-widening step.
      **Recorded: NO** — token is zone-scoped only (see session-state.md); 4.3 token-widening is BLOCKING.
- [x] 0.4 `git grep -n "cf_account_id" apps/web-platform/infra/*.tf` — confirm var wired (`tunnel.tf:11`).
      (Re-verified on resume: wired throughout tunnel.tf.)
- [x] 0.5 Verify exact Cloudflare Free-tier Bulk Redirects quota (list count + redirect count) against
      Cloudflare docs; confirm 9 redirects fits. (Verified via CF docs 2026-06-09: Free tier = 10,000 URL
      redirects across lists since 2025-02-12 limit increase — 10 fits.)

## Phase 1 — Eleventy fallback noindex (RED → GREEN, independently shippable)

- [x] 1.1 (RED) Add test to `plugins/soleur/test/seo-aeo-drift-guard.test.ts`: directory-walk every rendered
      meta-refresh stub under `_site/pages/**`; assert each contains `<meta name="robots" content="noindex">`
      and ≥1 stub found. (Walk, do NOT hardcode a file list.) (Commit e36cdbd0f, test at lines 470-505.)
- [x] 1.2 (GREEN) Add `<meta name="robots" content="noindex">` to `<head>` of
      `plugins/soleur/docs/page-redirects.njk`, adjacent to the existing `<meta http-equiv="refresh">`.
      (Commit e36cdbd0f — all three meta-refresh stub templates covered.)
- [x] 1.3 Rebuild docs: `npm run docs:build` (= `npx @11ty/eleventy` from repo root).
      (Re-run on resume: 103 files, exit 0.)
- [x] 1.4 Confirm stubs render with BOTH metas and stay `< 2000` bytes (size-gated `http-equiv="refresh"`
      detection at `seo-aeo-drift-guard.test.ts:220,237,531,1116` must still fire).
      (Re-verified on resume: full suite 48 pass / 0 fail.)
- [x] 1.5 Confirm `terms-of-service` stub guard still green (`seo-aeo-drift-guard.test.ts:464-467`).
      (Re-verified on resume: same run.)

## Phase 2 — Cloudflare Bulk Redirects Terraform (v4)

- [x] 2.1 Create `apps/web-platform/infra/seo-bulk-redirects.tf`:
      - `cloudflare_list.legal_redirects` (`account_id = var.cf_account_id`, `kind = "redirect"`,
        10 `item { value { redirect { source_url=…, target_url=…, status_code=301,
        preserve_query_string="enabled" } } }` blocks per the plan slug-mapping table).
        **Schema correction on resume:** v4.52.7 provider schema (`terraform providers schema -json`)
        types `include_subdomains`/`preserve_query_string` as STRING enums (`"enabled"`/`"disabled"`),
        not booleans — drafted `true` values fixed across all 10 items.
      - `cloudflare_ruleset.bulk_redirects` (`account_id = var.cf_account_id`, `kind = "root"`,
        `phase = "http_request_redirect"`, single `from_list` redirect rule referencing the list).
      - Header comment cross-refs this plan + #3297 + #3328 + `seo-rulesets.tf:59-66`.
- [x] 2.2 Decide provider alias: reuse `cloudflare.rulesets` if Phase 0.3 = scope-present; else document the
      token-widening requirement inline. (Scope-absent: alias reused + widening requirement documented in
      the file header — token widening is post-merge BLOCKING, see 4.3.)
- [x] 2.3 `cd apps/web-platform/infra && terraform fmt && terraform validate` (Doppler-injected canonical
      triplet). MUST pass — this catches v4-vs-v5 schema drift. (Both pass, exit 0. Note: validate alone
      would have silently coerced the bools — the schema probe in 2.1 was the real catch.)
- [x] 2.4 `terraform plan` (target-scoped to the 2 new resources): expect **2 to add, 0 to change, 0 to destroy**.
      Pin the output for the PR body. (Confirmed verbatim: `Plan: 2 to add, 0 to change, 0 to destroy.`
      Run locally against prd state via Doppler R2 creds; plan needs no account-scope token since both
      resources are net-new.)
- [x] 2.5 Update the deferral comment at `seo-rulesets.tf:59-66` (strike "return 404 until a Bulk Redirects
      refactor lands"; note the 9 legal redirects now land via the bulk list). Technical-fact correction only.

## Phase 3 — Apply-workflow allow-list extension

- [x] 3.1 Append `-target=cloudflare_list.legal_redirects` + `-target=cloudflare_ruleset.bulk_redirects` to the
      `terraform plan` `-target=` list in `.github/workflows/apply-web-platform-infra.yml` (after
      `seo_response_headers`, ~line 278). MANDATORY — omission means silent no-apply. (Landed at lines
      279-280. `terraform-target-parity.test.ts` only guards `terraform_data.*` SSH resources — no test
      change needed.)
- [x] 3.2 `git grep -n "seo_page_redirects" .github/workflows/` — if `scheduled-terraform-drift.yml` carries
      its own `-target=` list, add the two addresses there too. (Checked: drift workflow plans the full
      stack with NO `-target=` list — nothing to add. It will surface the 2-to-add as drift until the
      token-widen + apply complete, which is expected signal, not noise.)

## Phase 4 — Validate, PR, post-merge verify

- [x] 4.1 Run the 3 SEO suites green: `apps/web-platform/test/seo-rulesets-noindex.test.ts` (7/7),
      `plugins/soleur/test/validate-seo.test.ts` (17/17), `plugins/soleur/test/seo-aeo-drift-guard.test.ts`
      (48/48).
- [x] 4.2 Open PR; split AC into Pre-merge / Post-merge; use `Ref #3297` / `Ref #3328` (NOT `Closes` —
      ops-remediation: closure happens post-apply). (PR #5082 body updated with split AC + BLOCKING flag;
      post-merge chain consolidated into tracking issue #5092.)
- [ ] 4.3 **(Post-merge, BLOCKING — Phase 0.3 = scope-absent confirmed, Tracks #5092)** Widen the CF token to add
      `Account Rulesets:Edit` + `Account Filter Lists:Edit`; update Doppler `prd_terraform` if rotated.
      Flag explicitly in PR body — never a silent TODO. (Automation: not feasible — no Terraform path for
      CF token permission grants.)
- [ ] 4.4 **(Post-merge, automated, Tracks #5092)** Confirm `apply-web-platform-infra.yml` ran green on merge; if the
      token-widen step was needed, re-fire via
      `gh workflow run apply-web-platform-infra.yml --ref main -F reason='bulk-redirects apply after token widen'`.
- [ ] 4.5 **(Post-merge curl suite — load-bearing, Tracks #5092)** Each `/pages/legal/<slug>.html` (apex + www) → 301 with
      exact Location; `terms-of-service.html` → `/legal/terms-and-conditions/`; negative control
      `changelog.html` → `/changelog/` unchanged.
- [ ] 4.6 **(Post-merge, Tracks #5092)** Request GSC re-validation for the 9 legal URLs; add `gh issue` notes to #3297.

## Notes / Sharp Edges (carry into /work)

- v4 BLOCK syntax only — context7/registry-`latest` show v5 (`items` attribute-set). `terraform validate` is
  the catch. See `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`.
- The `source_url` host-format and the rule `key` expression are the two most likely-wrong details — verify
  vs CF Bulk Redirects docs and curl apex AND www.
- Do NOT delete `page-redirects.njk` / `pageRedirects.js` (terms-of-service stub guard depends on them).
- Do NOT touch `seo_page_redirects` Rule 10 (HTTPS catch-all — credential + ACME protection).
- Adding-only → 0 destroys → no `[ack-destroy]` gate needed.
