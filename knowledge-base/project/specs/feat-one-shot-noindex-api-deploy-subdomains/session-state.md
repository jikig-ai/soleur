# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-29-fix-noindex-api-deploy-subdomains-coverage-plan.md
- Status: complete

### Errors
None. (One IaC-routing guard hook blocked the initial plan Write because the prose contained "operator"; resolved by adding the documented `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out — the only proposed `.tf` change is comment-only and auto-applies via `apply-web-platform-infra.yml`.)

### Decisions
- The issue's proposed fix is substantially already shipped: X-Robots-Tag Cloudflare Transform Rules for both `api.` and `deploy.` already exist in `apps/web-platform/infra/seo-rulesets.tf` (PR #3296). Live curl confirmed `deploy.soleur.ai` returns `x-robots-tag: noindex, nofollow`.
- `api.soleur.ai` cannot be noindexed by a soleur.ai-zone rule (DNS-only CNAME, `proxied = false`, bypasses the edge) — already owned by OPEN issue #3379. Plan recommends closing #4575 as superseded-by #3379; no duplicate tracker filed.
- Net-positive deliverable: a vitest regression guard asserting both Transform Rules persist in source, mirroring `apps/web-platform/test/github-app-manifest-parity.test.ts`.
- robots.txt alternative rejected — Supabase owns the `api.` origin; X-Robots-Tag is strictly stronger.
- Threshold = aggregate pattern (SEO hygiene); no CPO sign-off. Apply path is auto-apply-on-merge.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- Bash, ToolSearch, Write/Edit
