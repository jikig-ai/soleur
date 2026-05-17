---
date: 2026-05-15
status: complete
verdict: no-direct-integration; ship CLO upgrade only
trigger: user invoked `/soleur:go` with `https://github.com/anthropics/claude-for-legal` asking "review and see how this can be integrated into Soleur"
brand_survival_threshold: single-user incident
lane: cross-domain
related-issues: "#3785 (parent), #3786 (deferred bridge re-evaluation)"
---

# Claude-for-Legal Evaluation

## What We're Building

**Not a bridge.** A scope-down of `clo` agent + `legal-audit` skill so that when a Soleur user (founder) hits one of 4-5 well-defined legal thresholds (vendor MSA review, DSAR, AI vendor terms, OSS license question, breach notice), Soleur's existing Soleur-native legal stack produces a *Soleur-native* triage output and references `anthropics/claude-for-legal` in a docs page **as one of several recommended downstream tools** — never as a privileged upstream.

claude-for-legal itself was evaluated at length (CPO, CMO, CLO, CTO, plus repo + learnings research). The four leaders converged that the bridge — in any form (delegate, lift, hybrid) — is **not the right shape for Soleur today**.

## What We Investigated

`anthropics/claude-for-legal` (4.5k stars, just shipped 2026-05-15) — Anthropic's plugin marketplace for licensed lawyers. 12 practice-area plugins (privacy, commercial, corporate, employment, IP, litigation, regulatory, AI governance, product, legal-clinic, law-student, legal-builder-hub), 5 managed-agent cookbooks, ~80 named agents. License: **Apache-2.0**. Distribution: Claude Code plugin marketplace + Claude Cowork.

User scope choice was "Targeted skill bridge — pick 3-5 plugins relevant to founder workflows and add `/soleur:legal-*` commands that delegate or reimplement." The leader assessment narrowed that to "no integration at all; CLO upgrade only."

## User-Brand Impact

The Phase 0.1 framing answer was **trust breach + user data exposure + brand confusion** (all three triggers). This sets `Brand-survival threshold: single-user incident` and was the load-bearing reason the leaders rejected the more ambitious approaches.

- **Affected role:** Soleur user = solo founder. Not a licensed attorney. No malpractice insurance, no bar accountability.
- **Vector if a bridge ships and weakens guardrails:** UPL claims (CA/NY/FL: criminal), FTC §5 / state UDAP consumer-protection liability if founder relies on output, negligent-misrepresentation if outputs read as advice. Founder-customer trust loss if their PII/contract data flows through a delegated plugin without disclosure. Brand confusion if `/soleur:legal-*` reads as Soleur-as-legal-services-product.
- **Threshold:** single-user incident. One founder fined or sued because Soleur output was treated as legal advice is brand-fatal.

## Why "No Integration"

### 1. Audience mismatch is structural, not cosmetic (CLO + CPO)

claude-for-legal is built for *licensed attorneys with malpractice coverage*. Soleur targets *solo founders*. The plugins assume a calibrated firm playbook, retained jurisdiction expertise, and an attorney-of-record who reviews every output. Founders have none of these. Wrapping a lawyer-grade skill in a founder-grade UX strips the safety substrate the original relies on; preserving the safety substrate verbatim produces a UX that says "you cannot use this without an attorney" on every output, which is honest but useless as a product.

CPO's brutal cut: of 12 plugins, maybe 2 have non-zero founder-fit, and even those run 1-3x/year per founder — below the maintenance threshold for a coupled bridge.

### 2. The mechanic options are all worse than no-bridge (CTO)

| Mechanic | Why rejected |
|---|---|
| Pure delegation | Skills hardcode `~/.claude/plugins/config/claude-for-legal/<plugin>/CLAUDE.md` profile paths — silent failures for any Soleur user who hasn't installed the upstream plugin AND run its `cold-start-interview`. Cross-namespace command resolution unverified in the loader. |
| Lift-with-attribution | Apache-2.0 mechanically permits it (precedent: gosprinto NOTICE at `plugins/soleur/skills/gdpr-gate/NOTICE`), but the lifted skills assume a profile schema and `matter-workspace` machinery Soleur doesn't have. Rewriting the path refs is essentially a fork; Soleur owns the legal-output liability surface. |
| Hybrid recommend-and-handoff | Lowest-risk, but the same outcome can be achieved by a Soleur-native CLO upgrade + a multi-vendor docs page — without privileging claude-for-legal as a default. |

### 3. Brand-positioning math doesn't work (CMO)

Framing (a) "Soleur extends to legal workflows" is *legally indefensible* — Jikigai isn't a law firm. Framing (b) "handoff when need crosses founder→lawyer threshold" is the only honest framing — but it's a docs/recommendation surface, not a `/soleur:legal-*` command surface. Reimplementing in founder voice strips the conservative defaults; delegating preserves voice safety but couples to upstream version drift. Either way, the marketing surface is docs-only.

### 4. PIVOT verdict alignment (learnings)

Prior brainstorm `2026-03-10-claude-marketplace-evaluation-brainstorm.md` decided "PIVOT validation takes priority" — validate founder demand before adding distribution surface. The same logic applies in reverse here: validate that founders actually want a legal-tooling extension before building one. PR-1 docs page acts as the demand-validation surface.

### 5. claude-for-legal is *recommendable*, not *integrable*

The `clo` agent already routes to `legal-document-generator` and `legal-compliance-auditor`. Adding a fifth row to its decision matrix — "if scope exceeds founder-grade, recommend `anthropics/claude-for-legal` (and 1-2 alternatives)" — captures 90% of the value of a bridge at 5% of the maintenance cost.

## Key Decisions

| Decision | Rationale |
|---|---|
| **No code import / no delegation / no lift from claude-for-legal.** | Audience mismatch is structural; mechanic options are all worse than no-bridge; brand-positioning is docs-only anyway. |
| **Extend `clo` agent + `legal-audit` skill** to detect 4-5 founder thresholds (vendor MSA, DSAR, AI vendor terms, OSS license, breach notice) and produce Soleur-native triage output. | Captures the founder-demand validation use case using existing infrastructure. |
| **Add `knowledge-base/legal/recommended-tools.md`** listing claude-for-legal alongside 1-2 alternatives (e.g., the gosprinto `compliance-skills` lift already in `gdpr-gate`, peer SaaS-legal vendors). | Avoids privileging Anthropic; honors vendor-neutrality; gives `clo` a citable target for "scope exceeds founder-grade" recommendations. |
| **Defer the lift question** until the docs page captures 30-60 days of usage signal AND CPO/CMO see founder demand clearly. | PIVOT-aligned: validate demand first. |
| **Do NOT amend Soleur ToS now.** | No bridge means no UPL surface; ToS amendment was a hard prereq for any bridge mechanic but is unnecessary for the docs-only path. |

## Domain Assessments

**Assessed:** Marketing, Engineering, Product, Legal (CPO + CMO + CLO + CTO triad mandatory under USER_BRAND_CRITICAL=true; Engineering + Product = Marketing + Legal carry-forward via leader spawn).

### CLO
Bridge is conditionally safe ONLY for triage-class skills with verbatim guardrail inheritance. For the chosen "no integration" path, the CLO upgrade has a clean safety surface: extending `clo`/`legal-audit` to recognize founder thresholds and emit Soleur-native triage (which already carries the established "DRAFT — generated by AI, requires professional legal review" disclaimer) does not introduce any new UPL/malpractice surface. License (Apache-2.0) is not load-bearing under this path because no upstream code is imported. Soleur ToS amendment is **not** required for this scope. Anthropic sub-processor row is **not** required because no founder data flows through claude-for-legal under this path.

### CPO
Strongly endorses "skip integration; CLO upgrade only." Honors the PIVOT verdict (validate founder demand first). Cannibalization risk drops to zero: founders learn that Soleur's CLO is the gateway to *any* legal-tooling recommendation, not just one privileged upstream. The recommended-tools.md docs page becomes the demand-validation surface — if founders click through to claude-for-legal frequently, that's a signal to revisit the bridge in 30-60 days. Open question: which 4-5 founder thresholds matter most? (This drives the CLO upgrade scope.)

### CMO
On-brand. The single-sentence framing — "Soleur recognizes when your need crosses the founder-to-lawyer threshold and hands off — output is for attorney review, not client delivery" — fits perfectly under the no-integration path because it's now literally true (no Soleur surface produces legal output beyond what already exists). Marketing surface: one docs page under `integrations/`, no features-page listing, no blog post. No counsel-review gate needed for a vendor-neutral recommendations page.

### CTO
Approves. Lowest-risk implementation. Capability gaps (Apache-2.0 NOTICE generator, upstream-drift cron) are **not** triggered by this path. AGENTS.md hard rules `hr-new-skills-agents-or-user-facing` and `hr-gdpr-gate-on-regulated-data-surfaces` apply to the CLO upgrade work but the existing `clo` agent is already compliant. Reuse the existing disclaimer pattern at `plugins/soleur/agents/legal/legal-document-generator.md:22` and `plugins/soleur/skills/gdpr-gate/SKILL.md:10`.

## Capability Gaps

None — chosen path uses only existing Soleur infrastructure.

(Had we picked PR-1 + PR-2 selective lift, two gaps would have applied: Apache-2.0 NOTICE generator and an upstream-drift cron. Both deferred.)

## Open Questions

1. **Which 4-5 founder thresholds drive the CLO upgrade scope?** Candidates from leader analysis: vendor MSA review, DSAR request, AI vendor terms onboarding, OSS license classification, breach notice. CPO suggests asking the user which of these they've personally hit in the last 90 days — without that, we're designing for an imagined founder.
2. **What goes in `recommended-tools.md` besides claude-for-legal?** Need 1-2 vendor-neutral alternatives. gosprinto/compliance-skills (already lifted in `gdpr-gate`) is one. Need a second to honor vendor-neutrality framing.
3. **Should we tag this brainstorm's verdict in `clo.md`** so a future agent re-investigating the integration question reads the rejection rationale before re-spawning leaders? (Likely yes — analogous to how `2026-03-10-claude-marketplace-evaluation-brainstorm.md` is referenced as a prior decision.)
4. **Re-evaluation criteria** for the bridge decision: ALL must hold. (a) docs page click-through > N founders/month for ≥ 60 days, (b) at least one founder explicitly requests `/soleur:legal-*` commands in Discord/issues, (c) CPO confirms founder-demand signal is real (not Anthropic-prompted). Until then, no bridge work.

## References

- Repo: `anthropics/claude-for-legal@main` (Apache-2.0)
- Prior brainstorm: `knowledge-base/project/brainstorms/2026-03-10-claude-marketplace-evaluation-brainstorm.md` (no-go on Anthropic distribution surface)
- Prior brainstorm: `knowledge-base/project/brainstorms/2026-05-10-gosprinto-pin-policy-brainstorm.md` (lift-pin policy precedent if path ever revisited)
- Prior learning: `knowledge-base/project/learnings/2026-05-09-evaluating-vendor-branded-claude-code-skills.md` (canonical playbook)
- Prior learning: `knowledge-base/project/learnings/implementation-patterns/2026-02-22-bundle-external-plugin-into-soleur.md` (ralph-loop bundle precedent)
- Prior learning: `knowledge-base/project/learnings/2026-02-25-stripe-atlas-legal-benchmark-mismatch.md` (refuse the wrap; redirect to peer benchmark)
- Existing Soleur stack: `plugins/soleur/agents/legal/{clo,legal-compliance-auditor,legal-document-generator}.md`, `plugins/soleur/skills/{gdpr-gate,legal-audit,legal-generate}/`
- Existing disclaimer pattern: `plugins/soleur/agents/legal/legal-document-generator.md:22`, `plugins/soleur/skills/gdpr-gate/SKILL.md:10`
