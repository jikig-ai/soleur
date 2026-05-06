# Learning: brainstorm capability-gap claims must grep the repo before declaring

## Problem

The `feat-seo-gsc-indexing-fixes` brainstorm declared a "capability gap":

> No existing Cloudflare Terraform root manages soleur.ai DNS/redirects
> (verified via `find . -maxdepth 4 -name "*.tf"`); plan must establish one
> or extend `apps/web-platform/infra/` if its Cloudflare zone is the same
> account.

The grep was too shallow. `apps/web-platform/infra/` (depth 4) DOES manage
the entire `soleur.ai` Cloudflare zone — DNS records, Tunnel + Access
applications for `deploy.soleur.ai`, Supabase CNAME for `api.soleur.ai`,
zone settings, cache rulesets, bot management. The brainstorm's research
phase missed all of this and propagated three mistakes into the plan:

1. Spec asserted "establish a new Terraform root with R2 backend" (the
   root already existed with R2 backend).
2. Spec proposed "set up new Cloudflare Worker" for per-subdomain
   `robots.txt` (a `cloudflare_ruleset` Transform Rule is the existing
   pattern; no Workers in the repo).
3. Brainstorm framed `deploy.soleur.ai` as a "leaked admin subdomain"
   (it's a deliberate `cloudflare_zero_trust_access_application.deploy`
   resource — the 403 IS the Access challenge page, by design).

The plan-skill's research-phase repo-research-analyst caught all three at
plan-time, surfaced them in a Research Reconciliation table, and rewrote
the plan to (a) extend the existing root, (b) drop the Workers approach,
(c) reframe Vector 3 as "subdomain hardening" with `X-Robots-Tag` defense
in depth.

## Solution

When brainstorm Phase 0.5 emits a Capability Gaps section, every claim
must be backed by a grep that exhausts the search space — not a casual
`find` at insufficient depth. Patterns that work:

- For infra/Terraform claims: `find . -name '*.tf' -not -path '*/.terraform/*' -not -path '*/node_modules/*'` (no depth cap), or `git ls-files | grep -E '\.tf$'`.
- For service / endpoint claims: `git ls-files | grep -E '<keyword>'` against the entire tree, not a hand-picked subset.
- For "X has not been implemented" claims: search by **consuming symbol** (function name, variable name, hook name, route path), not by description.

A capability gap that fails the grep test is not a gap — it's a research
miss. Treating it as a real gap pushes architectural decisions into the
plan body that the existing infrastructure already covers, forcing the
plan-skill to undo them in a Research Reconciliation table.

## Key Insight

**Brainstorm Capability-Gap claims have to clear the same evidence bar as
plan Acceptance Criteria for external state.** AGENTS.md
`hr-before-asserting-github-issue-status` requires verifying issue state
via `gh issue view` before asserting; the same principle applies to
"this infra doesn't exist": verify by grep before asserting.

A second insight from this session: **plan-review's parallel reviewers
catch DIFFERENT classes of issues.** In this session:

- DHH found ceremony (8 phases, deferred-deletion as cop-out, new token
  alias as theatre).
- Code Simplicity converged on most of DHH's cuts plus more (combine the
  two `.tf` files, drop the `disallow-all-robots.txt` artifact entirely).
- Kieran independently found a P0 ship-blocker (Cloudflare v4 `headers`
  block syntax was written as v5 attribute-map syntax) plus 4 P1
  correctness bugs (grep regex false-negative, sitemap regen ordering,
  pre-change baseline missing, hollow validator audit).

A single reviewer would have caught roughly a third. The plan-skill's
parallel-3-reviewer pattern is load-bearing. Don't sequentialize it.

## Session Errors

1. **Cloudflare v4 HCL `headers` block syntax was written as v5 attribute-map** — Recovery: Kieran flagged P0; rewrote with v4 nested-block (`headers { name = "X-...", operation = "set", value = "..." }`) per existing `cache.tf`. — Prevention: when prescribing Cloudflare ruleset HCL, verify the action_parameters block shape against an existing repo `.tf` resource using the same provider version, not against Context7 (which returns latest docs). Generalizes `2026-04-10-context7-terraform-provider-version-mismatch.md` to action_parameters block-vs-attribute shape, not just attribute existence.

2. **Plan self-contradiction on meta-refresh deletion** — Recovery: Kieran flagged P0-3; revised plan to consistently defer deletion to follow-up PR. — Prevention: when a plan's Sharp Edges or Risks section says "decide at /work time" or "recommend X but list opposite in Files to Delete", treat as plan incoherence — pick one BEFORE plan-review.

3. **Plan over-engineered Vector 3** with robots.txt static file + 2 redirect rules + Transform Rule when `X-Robots-Tag` alone is authoritative for indexing — Recovery: DHH + Simplicity both flagged; dropped redundant artifacts. — Prevention: when defending against indexing (not crawling), `X-Robots-Tag` is canonical; `Disallow:` is for crawl prevention. Don't combine without a specific reason.

4. **Plan minted new `cf_api_token_transforms`** when expanding existing `cf_api_token_rulesets` (same blast radius: zone-scoped rule writes) suffices — Recovery: expanded existing scope. — Prevention: token-splitting is for orthogonal blast radii (DNS vs WAF vs Cache); for sibling concerns inside the same blast-radius bucket, expand scope.

5. **Plan grep regex `'https://soleur\.ai[a-zA-Z]'` had false-negative** on the most common pattern (`https://soleur.ai/<path>`) — Recovery: Kieran P1; changed to `'https://soleur\.ai(/|[a-zA-Z]|$)'`. — Prevention: when grepping for a URL pattern, enumerate the three shapes (path-with-slash, alpha-suffix, bare-host) explicitly. A regex that misses the most common shape is silent-deletion.

6. **Brainstorm Capability-Gaps grep was too shallow** (the headline finding above) — Recovery: plan-skill research caught it. — Prevention: brainstorm SKILL.md Phase 0.5 should require evidence (grep output, file paths) for any "doesn't exist" / "no precedent" claim, not just an assertion. (Routing this prevention to brainstorm SKILL.md as a one-line bullet — see Route to Definition below.)

## Related Learnings

- [2026-04-10-context7-terraform-provider-version-mismatch.md](integration-issues/2026-04-10-context7-terraform-provider-version-mismatch.md) — Context7 returns latest provider docs; `terraform validate` is the load-bearing gate.
- [2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md](bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md) — `deploy.soleur.ai` 403 is CF Access challenge; verify response headers on the challenge response, not just origin.
- [2026-05-05-gsc-indexing-triage-patterns.md](2026-05-05-gsc-indexing-triage-patterns.md) — sibling learning from the same feature (GSC triage patterns).

## Tags

category: best-practices
module: brainstorm, plan, plan-review, terraform
