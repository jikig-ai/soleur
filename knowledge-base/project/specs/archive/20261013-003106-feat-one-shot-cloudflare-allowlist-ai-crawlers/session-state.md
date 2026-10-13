# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-cloudflare-allowlist-ai-crawlers/knowledge-base/project/plans/2026-04-21-fix-cloudflare-allowlist-ai-crawlers-plan.md
- Status: complete

### Errors

None. Two deepen-pass findings averted `terraform validate` failures before any HCL was committed:

- Product-enum casing (`uaBlock`/`rateLimit`/`zoneLockdown` → `uablock`/`ratelimit`/`zonelockdown` per cloudflare-go source); `securityLevel` intentionally camelCase.
- `http_request_sbfm` is NOT in the v4 provider's `RulesetPhaseValues()` enum; removed from the `phases` list (public docs list it, but v4.52.7 doesn't wire it).

### Decisions

- Root cause identified as Cloudflare Browser Integrity Check (BIC), NOT Bot Fight Mode or the managed WAF. Verified via live `/settings` endpoint probe: `browser_check=on`, `waf=off`, `security_level=medium`. BFM is non-skippable on all plans per CF docs; BIC IS skippable via `skip` action with product `bic` on Free plan.
- Fix is a single new Terraform file `apps/web-platform/infra/bot-allowlist.tf` with one `cloudflare_ruleset` (phase `http_request_firewall_custom`) containing one `skip` rule. Allowlist-only, 20 documented AI UAs, no global weakening of bot posture.
- Source-of-truth hierarchy for enums locked in: when Context7 and the pinned provider's dependency source disagree, the source wins. Phase 2 mandates a `terraform validate` preflight before commit.
- v4 block syntax (not v5 list-attribute) explicitly documented. Precedent: `apps/web-platform/infra/cache.tf` `cache_shared_binaries` ruleset.
- P0 scope boundary: the AEO audit's P1/P2/P3 items are explicitly out of scope — this PR unblocks the P0 cascade only.

### Components Invoked

- `Skill: soleur:plan` (primary)
- `Skill: soleur:deepen-plan` (primary)
- Bash, WebSearch, WebFetch, Context7 MCP, Grep, Read
- `npx markdownlint-cli2 --fix`
