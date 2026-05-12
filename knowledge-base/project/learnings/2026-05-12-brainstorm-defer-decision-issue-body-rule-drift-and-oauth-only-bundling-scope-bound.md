---
date: 2026-05-12
category: best-practices
module: brainstorm
tags:
  - brainstorm
  - mcp
  - skills
  - issue-body-drift
  - plugin-json
  - oauth
  - cannibalization
  - tier-2-port
issues:
  - 2724
  - 2718
related_learnings:
  - knowledge-base/project/learnings/integration-issues/2026-02-18-authenticated-mcp-servers-cannot-bundle-in-plugin-json.md
  - knowledge-base/project/learnings/integration-issues/2026-02-22-oauth-mcp-servers-can-bundle-in-plugin-json.md
  - knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md
  - knowledge-base/project/learnings/2026-05-12-brainstorm-write-mostly-artifact-diagnosis-and-lifecycle-prereq.md
---

# Learning: brainstorm defer decision surfaces three reusable patterns

## Problem

Brainstorm for #2724 (`mcp-server-builder` skill — OpenAPI → MCP server scaffolding, Tier 2 candidate from parent #2718 audit) had to weigh whether to ship a Soleur-native port of `alirezarezvani/claude-skills/engineering/skills/mcp-server-builder/` (MIT). Three independent failure modes nearly cost a multi-PR build before the four-leader (CPO + CMO + CTO + CLO) assessment surfaced the defer signal:

1. The issue body's architectural constraint contradicted the actual plugin-wide rule.
2. The skill's natural deliverable shape was not bundle-compatible with `plugin.json`.
3. Building this single Tier 2 candidate would cannibalize the parent issue's already-recorded reject decisions one data point at a time.

## Solution

**Decision:** Defer entirely. No Soleur-native skill, no companion-pointer doc, close #2724 with three explicit reopen criteria.

Brainstorm artifact: `knowledge-base/project/brainstorms/2026-05-12-mcp-server-builder-brainstorm.md`.
PR landing the docs: #3675.

## Key Insight

Three reusable patterns to apply on every future brainstorm of a Tier 2 candidate from a competitive-audit umbrella issue:

### Pattern 1 — Issue-body architectural constraints can contradict plugin-wide rules

#2724's body said "Architecture compatible with Soleur skill contract (SKILL.md + bash scripts, **no stdlib Python CLI**)." Repo research confirmed this overstates the rule. `plugins/soleur/skills/` already ships ten stdlib-only Python scripts (`skill-creator/scripts/init_skill.py:14-15`, `gemini-imagegen/scripts/*`, `resolve-debt/scripts/*`). The authoritative rule is **"no non-stdlib Python"** — `pyyaml` is forbidden because the runner image may strip it (`knowledge-base/project/plans/2026-04-17-fix-one-shot-2525-2527-plan.md:154`), but `sys`/`pathlib`/`json` are fine.

**Lens:** When a brainstorm's issue body cites a hard architectural constraint, verify it against the plugin-wide rule corpus (`plugins/soleur/AGENTS.md`, `knowledge-base/project/learnings/`, `plugins/soleur/skills/**/scripts/`) before letting it bound the option space. Issue bodies drift; the plugin's actual practice does not.

**Why this matters:** Accepting the issue-body constraint at face value would have forced architecture (i) (clean-room bash port — rejected by CTO as brittle for `$ref`/`allOf`/`oneOf` resolution) or architecture (ii) (lock-in to a single upstream OSS generator). Verifying the real rule unlocked architecture (iii) (`npx`/`uvx` orchestrator + small stdlib Python parser) as a viable Soleur-native option — though the brainstorm still concluded defer for other reasons.

### Pattern 2 — `plugin.json` OAuth-only bundling is a load-bearing scope-bounder for any "generate an MCP server" skill

The Claude Code plugin runtime's `plugin.json` only bundles MCP servers with `type: http` + URL (no `headers` field). This means a bundleable MCP server must use **OAuth or no-auth** — static-bearer/PAT auth (Stripe non-OAuth, HubSpot, Linear, Notion, most SaaS) cannot bundle (`knowledge-base/project/learnings/integration-issues/2026-02-18-authenticated-mcp-servers-cannot-bundle-in-plugin-json.md`, with 2026-02-22 OAuth sibling).

**Lens:** Any brainstorm proposing a "skill that **generates** an MCP server" must ask: *does the natural deliverable shape (a wrapper around an OpenAPI spec for $VENDOR) produce a server that uses OAuth, no-auth, or static-bearer?* If static-bearer, the generated server is operator-local only — not distributable as a Soleur plugin component. This dramatically narrows the user value: operators get a one-off scaffolded server they install manually, not a redistributable plugin contribution.

**Why this matters:** The headline framing of #2724 ("OpenAPI → MCP server scaffolding") implies a bundleable artifact. The deliverable shape under the bundling constraint is a 90%-non-bundleable artifact. Surfacing this at brainstorm time prevents weeks of work on a skill whose output cannot ship through the primary distribution surface.

### Pattern 3 — Tier 2 candidates from a competitive-audit umbrella cannibalize the parent's reject decisions one at a time

Parent #2718 explicitly rejected "wholesale 235-skill port" of alirezarezvani's library. The umbrella's Tier 2 list contains five candidates (#2723 tech-debt-tracker, #2724 mcp-server-builder, #2725 incident-commander, #2726 code-to-prd, #2727 karpathy-check). Each individual candidate looks like a justified one-off port. **The externally-visible pattern after five ports is the wholesale port the parent rejected.** The reject decision is not preserved by Tier 2 candidate brainstorms in isolation; it is preserved only when each brainstorm re-references the parent's reject list and counts how many candidates have already been ported.

**Lens:** When brainstorming a Tier 2 candidate from a competitive-audit umbrella, run this check:

1. List the umbrella's explicit reject decisions.
2. Count how many sibling candidates already shipped.
3. Ask: "If we ship N more, do we reconstruct the rejected outcome?"
4. If yes, the bar for shipping THIS candidate is higher than the candidate's own merits — it must also defend against the cumulative pattern.

**Why this matters:** #2723 already shipped (tech-debt-tracker, PR #3645). Shipping #2724 would be the second data point. After five, the parent's reject is silently undone. Each Tier 2 brainstorm needs to surface the count in its Domain Assessments so the cumulative lens is visible.

## Session Errors

1. **Wrong nested path guess for upstream repo content fetch.** `gh api repos/alirezarezvani/claude-skills/contents/engineering/mcp-server-builder` returned 404. Actual path was `engineering/skills/mcp-server-builder/SKILL.md`.
   **Recovery:** Ran `gh search code --repo alirezarezvani/claude-skills --filename SKILL.md "mcp-server-builder"` to locate the correct path.
   **Prevention:** When probing a third-party repo's content path, list one level shallower first (`gh api .../contents/engineering`) before guessing a deeper segment. Cheaper than 404-retry. Add to `repo-research-analyst` agent's investigation defaults if not already there.

## Tags

category: best-practices
module: brainstorm
