# Learning: Evaluating an external OFFENSIVE / AGPL security tool for adoption

**Date:** 2026-07-09
**Context:** Brainstorm evaluating [T3MP3ST](https://github.com/elder-plinius/T3MP3ST) (AGPL-3.0 autonomous offensive red-team meta-harness) for (1) hardening Soleur's own security and (2) a future Soleur-Users capability. Outcome: do NOT adopt; borrow techniques into a scoped runtime RLS/authz-fuzz harness (#6256); drop the user-facing offensive idea and reshape to a deferred defensive posture-check (#6257).

## Problem

"Should we adopt tool X to harden security?" for an external offensive tool is easy to answer shallowly ("it's powerful, yes"). Three non-obvious traps make the honest answer more constrained.

## Key Insights

### 1. "Internal use" of an offensive harness is NOT automatically ToS-safe
Pointing exploitation/scan traffic at *your own* dev/staging app also tests the **rented infrastructure underneath it**. Hetzner's abuse desk can suspend the box for outbound attack traffic regardless of target; Supabase/Cloudflare/Vercel AUPs forbid automated attack tooling even against your own account; Cloudflare scans hit the edge (useless data) and trip abuse detection → prod-suspension risk. **The only safe target is a local, provider-detached disposable stack.** For Soleur specifically there is *also* no dev/staging env (all non-prod is operator-local; the dark host runs prod secrets), so a local Postgres with prod RLS policies loaded is both the safest and the *only available* target. Runtime RLS/authz testing does not need the hosted DB — load the policies into a local Postgres and get the same authz truth.

### 2. Borrow the technique taxonomy, don't adopt the AGPL source
An AGPL/copyleft offensive tool should be "borrowed" (kill-chain taxonomy / attack techniques as *concepts*, re-implemented) — never "adopted" (source copied), which triggers viral copyleft on the consuming plugin. Soleur already had a standing policy — MIT/BSD/Apache-2.0 only, "**no GPL/AGPL contagion**" (`feat-behavior-harness-uplift/spec.md`) — plus prior AGPL-tool rejections (Relaticle/Twenty/Corteza, 2026-07-07 brainstorm) that **repo-research surfaced**. Always let repo-research grep for an existing license policy + prior rejections before designing adoption mechanics; the precedent usually already exists.

### 3. A user-facing offensive capability trips the product's OWN AUP
Offering autonomous exploitation to non-technical users is not just externally risky — it contradicts Soleur's *own* Acceptable Use Policy §7(e) (`docs/legal/acceptable-use-policy.md:75`, forbids users' unauthorized scanning). That self-consistency defect is a fast, decisive "no" the CLO found by grepping the legal corpus, on top of criminal exposure (UK CMA §3A tool-supply, EU Directive 2013/40, CFAA origination on a hosted service). The legitimate adjacent need ("is my app secure?") reshapes to a **defensive, read-only posture check on the user's own assets-under-management** — park behind `business-validator`.

## Generalizable Pattern

When a brainstorm evaluates an external security/automation tool:
1. **License-before-mechanics:** repo-research greps the existing license policy + prior same-license rejections before any adoption design (learning `2026-05-15-evaluating-anthropic-first-party-plugin-marketplaces` — verify license first, it changes lift cost ~5x).
2. **"Internal use" ≠ ToS-clear:** if the tool emits attack/scan traffic, enumerate the rented infra underneath every "own" target; the safe boundary is provider-detached local.
3. **Self-consistency check for user-facing capabilities:** grep the product's own AUP/Terms — a capability the product forbids its users from doing cannot be handed to them.
4. **Borrow > adopt for copyleft:** harvest taxonomy as concepts into your own agents (which already carry codebase context), gated at concept-not-source.

## Session Errors

None detected. Workflow ran clean end-to-end (readiness gate → worktree + draft PR #6255 → parallel CLO/CTO/CPO + 2 research agents → issues #6256/#6257 → commit/push). Ambient Playwright MCP disconnect was unrelated and had no impact.

## Tags
category: workflow-patterns
module: brainstorm / security-tooling-evaluation
related: knowledge-base/project/brainstorms/2026-07-09-t3mp3st-security-eval-brainstorm.md, #6256, #6257
