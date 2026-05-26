---
date: 2026-05-12
issue: 2724
parent_issue: 2718
decision: defer
lane: cross-domain
brand_survival_threshold: single-user incident
domain_leaders: [CPO, CMO, CTO, CLO]
---

# Brainstorm: mcp-server-builder skill (#2724)

## Decision

**Defer entirely.** Do not ship a Soleur-native `mcp-server-builder` skill. Do not ship a companion-pointer doc to alirezarezvani's MIT skill. Close #2724 with `defer rule applied per #2718`.

This is the smallest possible footprint. The decision is reopenable when a concrete wrap target surfaces.

## What We Considered Building

Per the parent #2718 (Claude-skills competitive audit) Tier 2 list, a Soleur skill that takes an OpenAPI spec as input and produces a validated MCP server scaffold (Python or TypeScript runtime), with quality enforcement on tool naming, descriptions, and schemas. Pattern lifted from `alirezarezvani/claude-skills/engineering/skills/mcp-server-builder/` (MIT).

## Why Defer

Four domain leaders + two research agents converged on three independent reasons to defer:

1. **No founder outcome named (CPO gate failed).** Roadmap §3.4 commits to wrapping Cloudflare, Stripe, and Plausible — all three already publish MCP servers. The skill would activate the day Soleur needs a vendor whose API exists but whose MCP server does not, and no such vendor is on Phase 3 or Phase 4. The "customer Y" outcome is impossible: T2 of the roadmap is pre-beta, zero external users today.

2. **Off-axis from CaaS positioning (CMO).** Soleur's wedge is "AI organization for solo founders" — autonomous departments that *consume* MCP services. An OpenAPI → MCP scaffolder is producer-side developer tooling, the same axis as Speakeasy, Stainless, and Cloudflare's `openapi-mcp-server`. We have no moat there. The solo founder ICP does not have an OpenAPI spec they want to wrap; they have a Stripe account and a Notion they want their CMO agent to read. Both are already covered by published MCP servers in Soleur today.

3. **Cannibalization with #2718's reject decisions.** Parent #2718 explicitly rejected the "wholesale 235-skill port" of alirezarezvani's library. Shipping our own mcp-server-builder *because alirezarezvani has one* is a single data point that, repeated 5–10 times across the Tier 2 list, reconstructs the rejected port. The externally-visible pattern matters, and this contradicts the parent decision.

A fourth, independent reason emerged from the learnings researcher: plugin.json only bundles **OAuth or no-auth** MCP servers (per `2026-02-18-authenticated-mcp-servers-cannot-bundle-in-plugin-json.md` and its 2026-02-22 OAuth sibling). Static-bearer/PAT MCP servers cannot bundle. Most "wrap my SaaS API" outputs from this skill would use static-bearer auth and be **operator-local only**, not distributable as a Soleur plugin component. The skill's natural deliverable shape is not bundle-compatible.

Why "no companion doc" rather than option B (recommend alirezarezvani as companion in `knowledge-base/operations/recommended-skills.md`): operator chose to keep the footprint at zero. CMO's curation-narrative value is real but small; deferring the doc-creation cost until a second deferred-skill emerges (which would justify a multi-entry "recommended companions" page) is cheaper than shipping a one-entry page now.

## Why This Approach

This brainstorm itself is the durable artifact. The conclusion of "defer + reopen on concrete trigger" is captured here for the next operator who reads #2724 and asks "why didn't we build this?" The reopen criteria are explicit (see below).

## Key Decisions

| Decision | Rationale |
|---|---|
| **Do not build a Soleur-native skill.** | No founder outcome named; off-axis from CaaS positioning; cannibalizes #2718 reject decisions. |
| **Do not ship a companion-pointer doc.** | Single-entry doc is below the cost-of-publication threshold. Revisit when a second deferred-skill emerges. |
| **Close #2724 as deferred, not won't-fix.** | Issue is reopenable; the criteria are explicit. |
| **No update to plugin.json, AGENTS.md, or skill-creator.** | This brainstorm has no code surface. |
| **No update to alirezarezvani audit spec (`feat-claude-skills-audit`).** | FR5 status of "mcp-server-builder" updates via the closing comment of #2724, not the parent spec. |

## User-Brand Impact

**Threshold:** single-user incident (per Phase 0.1 framing; operator selected both credential-leak and wrong-data-surfaced failure modes apply).

**Vector inherited if we had shipped:** generated MCP server hardcoding secrets, surfacing private endpoints from an over-broad OpenAPI spec, or proxying arbitrary URLs from agent input. Attribution would flow to Soleur because Soleur shipped the generator.

**Vector with this defer decision:** zero. No generator is shipped, no scaffolded artifact exists in any operator's repo, no token handling code authored by Soleur. The skill remains available from the upstream MIT source if any operator independently chooses to install it, in which case the liability sits upstream.

This is the load-bearing reason for the defer over either option A (build with controls) or option B (companion pointer). A companion pointer that operators follow still carries some attribution risk if the upstream skill leaks a token — "Soleur recommended this" is not load-bearing legal liability but is a brand attribution surface. Zero footprint is the cleanest position.

## Domain Assessments

**Assessed:** Product, Marketing, Engineering, Legal. (Operations, Sales, Finance, Support not relevant — no external surface, no revenue surface.)

### Product (CPO)

**Summary:** Recommend Option B (companion pointer) over A (build) or C (defer entirely). No concrete wrap target exists today; roadmap §3.4 wraps services that already publish MCP. Building transfers brand-survival liability to Soleur for zero realized value. Operator overrode to C — accepted as smaller footprint with same logic.

### Marketing (CMO)

**Summary:** Recommend alirezarezvani-as-companion framing if any external artifact ships. Building our own mcp-server-builder is off-axis from CaaS-for-founders and would signal the "wholesale 235-skill port" #2718 explicitly rejected. Operator chose C (no companion doc) — accepted; revisit when a multi-entry "recommended companions" page is justified.

### Engineering (CTO)

**Summary:** If we ship, option (iii) `npx`/`uvx` orchestrator + small stdlib Python OpenAPI parser is the right architecture (matches `docs-site` precedent for `npx` orchestration and `skill-creator` precedent for stdlib Python). The issue body's "no Python CLI" claim overstates the rule — `plugins/soleur/skills/` already ships 10 stdlib-Python scripts. Auto-registration into `plugin.json` is out of scope for v1 (separate PreToolUse-trust-boundary security review needed). With C, none of this work happens.

### Legal (CLO)

**Summary:** If we ship, ship-with-controls — six mandatory automatic safety controls (spec sanitizer, secret-in-schema linter, host allowlist, env-only secret binding, RFC-1918 refusal, MIT NOTICE), plus operator-side GDPR carry-forward stub on PII detection. Single-user incident scenarios are real (credential leak via debug log; internal-API kitchen-sink endpoint exposure). With C, the credential-leak scenario cannot materialize through any Soleur surface.

## Capability Gaps

None blocking. The defer decision creates no gap because the skill remains available from upstream for any operator who needs it.

If we had chosen to build:

- **No existing OpenAPI parser or JSON Schema utility in repo.** Confirmed via `grep -rln "openapi" plugins/ knowledge-base/` — 8 hits, all consumer-side references (Cloudflare MCP's `search` tool queries Cloudflare's OpenAPI; no producer code). Clean slate.
- **No existing scaffolder shells to `uvx`.** Only `npx` precedent (`docs-site/SKILL.md:37-38, 185, 196`). A Python-runtime target would need to establish the `uvx` pattern.

## Open Questions

These are NOT blockers for the defer decision. They are notes for the operator who reopens #2724 later.

1. **What event triggers reopen?** Suggested criteria below. The operator should pick one and note it in the #2724 closing comment.

2. **If reopened, is the architecture choice (iii)?** CTO recommended (iii); learnings researcher flagged that the deliverable shape (operator-local servers using static-bearer auth) limits distribution. At reopen time, re-validate: does the wrap target use OAuth (bundleable) or static-bearer (operator-local)?

3. **If reopened, does CLO's 6-control list survive an updated threat model?** The list was derived for a generic scaffolder. A reopen with a specific wrap target should re-derive controls against the target's auth model and data sensitivity.

## Reopen Criteria

#2724 should be reopened only if **at least one** of the following becomes true:

1. **A Phase 3 or Phase 4 vendor in `knowledge-base/product/roadmap.md` requires API integration and has no published MCP server.** Naming the vendor and the API surface is the trigger.
2. **A founder ICP interview names this gap.** Specifically: a solo founder describes wanting to wrap their own SaaS API for their agent loop, and the upstream alirezarezvani MIT skill does not solve their use case (compatibility, security control, etc.).
3. **The Claude Code plugin runtime gains support for headers in `plugin.json` MCP entries.** This would remove the bundling constraint that today limits the skill's deliverable to OAuth/no-auth servers.

Absent any of these, #2724 stays closed.

## Lane

**Inferred:** cross-domain (auto-set by `USER_BRAND_CRITICAL=true` from Phase 0.1 framing).

The decision spans Product (founder outcome), Marketing (positioning), Engineering (architecture), and Legal (safety controls). No lane override.

## References

- Parent: #2718 — Claude-skills competitive audit action plan.
- Upstream reference (MIT): `alirezarezvani/claude-skills/engineering/skills/mcp-server-builder/SKILL.md` (clean, no vendor surface).
- Roadmap: `knowledge-base/product/roadmap.md` §3.4 (MCP-as-consumption tier; Cloudflare, Stripe, Plausible already publish MCP).
- Constraint learning: `knowledge-base/project/learnings/integration-issues/2026-02-18-authenticated-mcp-servers-cannot-bundle-in-plugin-json.md` (OAuth-only bundling).
- Vendor-skill lift pattern: `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md` (per-file contamination map; tech-debt-tracker #3645 precedent).
- Skill description budget: `plugins/soleur/AGENTS.md:144-147` (12-15 words operating target).
