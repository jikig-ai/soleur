# Learning: Verify referenced PR/issue state and domain-leader infra claims before accepting brainstorm framing

## Problem

A brainstorm for #3436 ("Anthropic Files API for large-PDF Concierge ingest, durable fix for #3429") inherited two load-bearing factual claims from the issue body and from a domain-leader assessment, both of which would have steered the brainstorm to the wrong recommendation if not caught:

**Claim 1 (issue-body framing):** #3436's body asserted "the bridge fix for #3429 (PR #3430) **adds** a page-count gate that turns silent timeouts into specific refusals" — written in present tense, implying merged. The CPO domain-leader read this as "bridge has shipped" and recommended **parking #3436 entirely**, on the grounds that "the trust-breach is fixed for now; designing Files API now is N=1-driven scope creep." The recommendation was internally coherent but premised on a fact that was wrong.

Repo research mid-brainstorm found:

- `gh pr view 3430 --json state,mergedAt` returned `{"mergedAt":null,"state":"OPEN","title":"WIP: feat-large-pdf-soft-route-timeout"}`.
- `git grep -l "too_many_pages" main -- apps/web-platform/` returned zero matches.

So the bridge fix was **not** in production. The trust-breach was still bleeding. Acting on CPO's "park it" recommendation would have left users at the same silent-timeout failure mode that started this whole thread.

**Claim 2 (domain-leader infra claim):** The CFO domain-leader assessment reported "**Build new — no existing budget infra**" and recommended building a new `usage_ledger` table from scratch to enforce per-conv / per-day USD caps. The recommendation was scoped to "new infrastructure" effort.

Repo research mid-brainstorm found:

- `apps/web-platform/server/cc-cost-caps.ts` — env-driven per-conv ($2 BYOK / $0.50 Soleur) + per-user-daily ($25 / $1) + global-daily ($500) caps already shipped.
- `apps/web-platform/server/api-usage.ts` — post-hoc per-conversation token + USD tracking already shipped.

The infra was 60-70% there. CFO's recommendation overstated scope by proposing to build what already existed in a different shape.

## Solution

Mid-brainstorm, the synthesizer (compound's main loop) noticed both claims when assembling the Phase 2 approach options and verified them before presenting to the user:

1. For Claim 1: ran `gh pr view 3430 --json state,mergedAt` + `git grep too_many_pages main` and surfaced "Bridge fix PR #3430 is OPEN/WIP, not merged" as a correction line in the synthesis. The correction reframed the sequencing decision: the durable fix isn't optional follow-up on a closed trust-breach, it's the actual fix riding alongside the still-WIP bridge.

2. For Claim 2: when describing CFO's recommendation in the synthesis, qualified it with "extend `cc-cost-caps.ts` + `api-usage.ts` rather than build from scratch" based on the repo agent's path citations. The user's chosen approach (chapter-chunking) ended up leaning entirely on the existing caps with no new ledger required, which would not have been clearly available as an option if CFO's "build new" framing had been adopted verbatim.

## Key Insight

Brainstorm framing inherits load-bearing facts from two sources that **don't get verified by default**:

1. **Issue bodies for referenced PRs and adjacent work.** Issue bodies are written at one point in time and aren't updated when adjacent PRs land or stall. A statement like "PR #N adds X" is true the day it's written, false the day it stalls or gets reverted. Domain leaders, especially product/strategy leaders whose recommendations turn on sequencing, accept these statements at face value.

2. **Domain-leader claims about what doesn't exist in the codebase.** The brainstorm skill's existing capability-gaps rule (Phase 3.5) explicitly requires `**Each capability-gap claim MUST cite specific evidence**` (the exact grep / `find` command run). This rule covers *gaps* but not the symmetric case: claims about *existing* infrastructure being absent. CFO claimed `byok/` subdirectory didn't exist (true, but irrelevant) and that "no existing per-user budget/quota mechanism" exists (false — `cc-cost-caps.ts` is exactly that mechanism). The claim was technically scoped to a specific subdirectory but was generalized in the recommendation.

Both failure modes share the same root cause: **the brainstorm process treats text from authoritative-feeling sources (the issue body, the domain leader) as ground truth, when the only actual ground truth is the current state of `main`.** Verification commands that take 10 seconds (`gh pr view`, `git grep`) prevent hours of brainstorming on a wrong premise.

This is **not** a new pattern — it echoes existing brainstorm rules:

- Phase 1.0 already requires WebFetch verification of external platform claims before launching agents.
- Phase 1.1 already requires verifying "is X mounted/wired/enabled?" claims with grep evidence.
- Phase 1.1 already requires verifying "this is a regression of #N" claims by tracing the trigger path.
- Phase 3.5 already requires capability-gap claims to cite grep evidence.

The gap is in two adjacent cases the existing rules don't quite cover:

- **Verify referenced PR/issue state** before accepting any sequencing claim derived from "PR #N has merged / PR #N adds X". Use `gh pr view <N> --json state,mergedAt` + a grep for the symbol the PR is supposed to have introduced.
- **Verify "no existing X" claims from domain leaders** with the same grep evidence requirement Phase 3.5 already enforces for capability-gaps. Negative claims are symmetric to gap claims and should require the same evidence floor.

## Session Errors

- **Stale issue-body framing accepted by CPO leader.** CPO's "park it" recommendation was internally coherent but premised on the bridge fix being merged. **Recovery:** repo-research-analyst's check of `git log main` showed the bridge code was not on main, and direct `gh pr view 3430` confirmed PR was OPEN/WIP. **Prevention:** brainstorm skill should require `gh pr view <N> --json state,mergedAt` verification of every PR referenced in the feature description before launching domain leaders, and should pass the verified state into domain-leader prompts so leaders don't accept stale framing.

- **CFO understated existing budget infra.** CFO recommended building a new `usage_ledger` table when `cc-cost-caps.ts` + `api-usage.ts` already implement per-conv + per-day caps + post-hoc tracking. **Recovery:** repo-research-analyst surfaced the existing files at exact paths and line numbers, which the synthesizer used to qualify CFO's recommendation when presenting approaches. **Prevention:** the brainstorm domain-config's leader prompt template should explicitly require leaders to grep for existing implementations before claiming infra is missing — symmetric to Phase 3.5's capability-gap evidence requirement applied to negative-existence claims.

- **Files API 100-page-cap-on-200K-context-models surfaced only by CTO live-doc fetch.** Issue #3436 named "Files API size cap" as one of 5 open questions but did not anticipate that the cap would be **per-model-context-tier** rather than a single global limit. CTO's WebFetch caught it; without that step, the brainstorm would have proposed a Files API path that doesn't deliver the 400pg-book acceptance criterion on Sonnet 4.6. **Recovery:** chapter-chunking pivot adopted instead. **Prevention:** Phase 1.0 external-platform verification rule already covers this (`5) does the limit cover the migration/feature scope?`); reinforce in domain-leader prompts that "live-doc verification" is required for any external-API capability claim, not just self-service/waitlist questions.

## Tags

category: integration-issues
module: brainstorm-skill
related: 2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites, 2026-04-23-verify-trigger-path-before-attributing-regression, 2026-05-05-brainstorm-capability-gaps-need-repo-grep, 2026-05-05-brainstorm-spawn-cpo-cmo-early-on-external-product-trigger
issue: 3436
