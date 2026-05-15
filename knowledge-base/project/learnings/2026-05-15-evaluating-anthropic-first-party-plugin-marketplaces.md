---
date: 2026-05-15
category: brainstorm-patterns
module: brainstorm, plugin-evaluation
tags: [vendor-lift, audience-fit, brand-positioning, mcp-connectors, apache-2.0, plugin-marketplace, user-brand-critical, compound-from-no-integration]
related-brainstorm: knowledge-base/project/brainstorms/2026-05-15-claude-for-legal-evaluation-brainstorm.md
related-issues: ["#3785", "#3786"]
related-learnings:
  - knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md
  - knowledge-base/project/learnings/implementation-patterns/2026-02-22-bundle-external-plugin-into-soleur.md
  - knowledge-base/project/learnings/2026-05-05-brainstorm-spawn-cpo-cmo-early-on-external-product-trigger.md
  - knowledge-base/project/learnings/2026-02-25-stripe-atlas-legal-benchmark-mismatch.md
---

# Learning: evaluating Anthropic-first-party plugin marketplaces

## Problem

User invoked `/soleur:go` with `https://github.com/anthropics/claude-for-legal` asking to "review and integrate." This is a recurring shape: an Anthropic-first-party plugin marketplace lands; the question is whether/how to integrate it into Soleur. Three structurally different questions — **integrate as code (lift)**, **integrate as runtime dependency (delegate)**, or **point at it (recommend)** — and each has different cost. Without a structured evaluation pattern, the default behavior is to spawn agents that design the integration instead of agents that test the premise.

The 2026-05-09 vendor-branded-skills brainstorm (`gosprinto/compliance-skills`) built a partial playbook (clean-room / lift-with-MIT-attribution / fork). The Anthropic-first-party case has additional dimensions: license is **Apache-2.0** not MIT; the upstream is the Claude Code platform vendor itself; the audience may not match Soleur's audience at all.

## Solution

A six-step evaluation pattern proven across this brainstorm. The triad (CPO + CMO + CLO + CTO under USER_BRAND_CRITICAL=true) finished in one round of parallel spawn rather than incremental dialogue.

### 1. Verify license BEFORE proposing mechanics

Run `gh api repos/<o>/<r>/contents/LICENSE --jq .content | base64 -d | head -40` first. Apache-2.0 vs. MIT changes lift mechanics non-trivially:

| License | Lift mechanics |
|---|---|
| **MIT** | One-line attribution per file is sufficient. gosprinto NOTICE pattern at `plugins/soleur/skills/gdpr-gate/NOTICE` applies directly. |
| **Apache-2.0** | §4 requires preserving NOTICE + license header in **each derivative file**. Not the same surface. Soleur has **no** Apache-2.0 NOTICE generator yet — that's a capability gap to surface in the brainstorm if a lift is proposed. |

### 2. Grep `.mcp.json` (not `CONNECTORS.md`) for actual MCP wiring

`anthropics/claude-for-legal` `CONNECTORS.md` lists 16+ legal connectors (Ironclad, DocuSign, iManage, CourtListener, Everlaw, Box). Actual `privacy-legal/.mcp.json` wires only Slack + Google Drive. **The README's connector list is aspirational; `.mcp.json` is the contract.** Estimating auth-friction cost from the README inflates by ~5x and biases the brainstorm toward "too heavy to integrate" for the wrong reason.

### 3. Grep upstream skills for hardcoded `~/.claude/plugins/config/<plugin>/CLAUDE.md` profile paths

Claude-marketplace plugins commonly resolve config from `~/.claude/plugins/config/<plugin>/CLAUDE.md` populated by their own `cold-start-interview` skill. **Pure-delegation bridges from Soleur silently fail** if the user hasn't installed AND configured the upstream plugin — the missing-file read produces no Soleur fallback. Always grep for these path patterns before proposing a delegation mechanic; if present, delegation is structurally broken regardless of risk preference.

### 4. Spawn the USER_BRAND_CRITICAL triad on external-product trigger

When the framing-question answer hits multiple triggers (trust + data + brand all fire), the leader prompts can ask sharper safety questions, and convergence is faster than incremental Phase 1 dialogue. Pattern: spawn CPO + CMO + CLO + CTO in one parallel batch with detailed context (license verified, .mcp.json grepped, profile-path issue surfaced), and the 4 leaders converge in ~2 minutes total. This finished a brainstorm in one round of leaders + one round of approach-pick — Phase 1.2 incremental dialogue was effectively skipped because the leaders pre-aligned.

### 5. Look for the smaller adjacent yes when leaders converge on "no"

The literal question was "integrate as bridge." All four leaders converged on "no bridge" but the *adjacent* question — "extend our own CLO + add a vendor-neutral docs page" — captured 90% of the value at 5% of the cost AND honored the PIVOT verdict ("validate demand first"). Pattern: when leaders converge on "no" for the literal question, ask "what's the smallest non-zero version of value capture here?" before closing the brainstorm as no-go. Often the answer is a docs page + a one-line orchestrator change — both of which require zero upstream coupling, zero license entanglement, and zero ToS amendment.

### 6. Vendor-neutrality framing as a brand-positioning safety valve

Listing the candidate alongside ≥1 alternative in `knowledge-base/legal/recommended-tools.md` (or its non-legal equivalent) avoids "Soleur privileges Anthropic" reading. Same pattern works for any single-vendor lift evaluation. Important when the vendor *is* the platform we run on — being seen to privilege the platform vendor's adjacent products is a brand risk distinct from the integration's technical merit.

## Key Insight

**External-product brainstorms with strong audience-mismatch signal can produce more value via "no integration + reframed scope" than via "yes integration + scope-down."** The reframe captures the founder-demand validation surface (docs page click-through) without locking in maintenance cost on an upstream we don't control. The pattern of (a) verify license, (b) grep `.mcp.json` for actual wiring, (c) grep for hardcoded profile paths, (d) spawn the triad on the framing-question signal, (e) look for the smaller adjacent yes, (f) frame vendor-neutrally — is reusable for every Anthropic-first-party plugin marketplace that lands.

## Session Errors

1. **Bash tool CWD persistence after `cd`** — `cd` to worktree during `draft-pr` persisted across subsequent Bash calls; my `ls .worktrees/...` queries assumed bare-root CWD and failed. **Recovery:** re-queried with paths relative to current CWD. **Prevention:** when issuing `cd` in a Bash tool call, treat shell CWD as sticky across subsequent calls in the same session; either always use absolute paths or explicitly `cd` back to the prior CWD. (This is already documented behavior — the prevention is to remember it during multi-step worktree workflows.)

2. **`emit_incident` telemetry call returned silently without verification** — `source .claude/hooks/lib/incidents.sh && emit_incident hr-weigh-every-decision-against-target-user-impact applied "..."` produced no observable output; I did not verify whether the function exists or the event landed in `.claude/.rule-incidents.jsonl`. Per the `cq-silent-fallback-must-mirror-to-sentry` pattern, telemetry calls that should land in a known sink should be verified, not assumed. **Recovery:** none needed (advisory telemetry, did not block brainstorm). **Prevention:** after `emit_incident`, run `tail -1 .claude/.rule-incidents.jsonl 2>/dev/null | grep -q "<rule-id>" && echo "[telemetry-confirmed]"` or accept the silent-success risk explicitly.

3. **`worktree-manager.sh` printed stale "Next steps" path** referencing `feat-cla-legal-rigor` (a sibling worktree) instead of the just-created `feat-cc-legal-skill-bridge`. Script template not parameterized for the active worktree name. **Recovery:** ignored the stale prose, used the correct path manually. **Prevention:** out-of-scope for this learning; warrants a separate fix issue against `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` to interpolate the actual feature name in its handoff prose.
