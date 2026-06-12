---
date: 2026-06-12
topic: loop-engineering-positioning
issue: 5088
status: decided
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Adopt "loop engineering" positioning — Soleur as loop engineering for your whole company (#5088)

## What We're Building

A news-hook **blog article** that adopts Addy Osmani's "loop engineering" term (June 2026,
Substack + O'Reilly Radar) and extends it past code: Osmani scopes loop engineering to software
engineering; Soleur runs the same architecture across every department. The article credits Osmani,
quotes the Cherny/Steinberger endorsements **of the term**, and maps Osmani's five building blocks +
external memory onto Soleur's actual capabilities — written at an **honest-hedge** posture.

**This PR ships the blog only** (+ a `social-distribute` content file). The two architecture gaps
that would make a literal "fully autonomous, whole-company" claim true are **decoupled into a
follow-up build** that, when complete, unlocks a "now fully cross-domain" v2 post. This catches the
~2-3 week news window without shipping a testable over-claim.

## Why This Approach

**Posture: honest hedge (operator decision).** Keep "loop engineering for your whole company, not
just your codebase" as the headline hook, but the body is honest about what ships today. The CTO
verified the architecture mapping against the codebase:

| Osmani element | Cross-domain today? | Evidence (CTO-verified) |
|----------------|---------------------|--------------------------|
| Worktrees | **TRUE** | `skills/git-worktree` is domain-neutral |
| Skills | **TRUE** | 86 skills; agents across 8 staffed domains |
| MCP connectors | **TRUE (scope to shipped)** | 4 git-committed in `plugin.json` (context7, cloudflare, vercel, stripe); others (plausible/linear/pencil/supabase/playwright) runtime-available — say "available," not "shipped" |
| External memory | **TRUE — strongest claim** | `knowledge-base/` spans all 9 domains (eng 136, mktg 97, support 81, legal 41 md). The validated moat |
| Automations (scheduled agents) | **ENGINEERING-ONLY** | 9 scheduled crons run deterministic scripts; **zero invoke an agent** (`claude-code-action`). No business-domain agent crons on disk |
| Sub-agents (maker/checker verifier) | **ENGINEERING-CONCENTRATED** | ~15 verifier agents in `engineering/review/`; only marketing (`fact-checker`) + legal (`legal-compliance-auditor`) have business-domain checkers |

The honest framing: the **substrate** (memory + skills + connectors + worktrees) already spans every
department; the **autonomous loop + verification** are proven in engineering and generalizing
outward. A prospect testing "scheduled finance agents" finds nothing today — so the bolder claim is a
single-user brand incident, which the honest hedge avoids.

**Decouple (operator decision) over build-first.** The operator initially wanted to close both gaps
before claiming full support. Building genuine cross-domain scheduling + verifier loops across 7
business domains is bounded but real work that would overrun the news window the blog depends on.
Decoupling lets the timely article ship now and the capability build proceed on its own clock; the
build unlocks an honest "fully cross-domain" v2 post on completion.

**Map block 4 to "MCP connectors" only.** Osmani's block 4 is literally "Plugins & Connectors."
Soleur's roadmap is cloud-first ("no one wants to install a Claude Code plugin"). On Soleur-subject
public surfaces, drop "plugins" and frame this block as **cloud-native MCP connectors** (Stripe,
Cloudflare, Supabase). (Note: existing blog posts about *Claude Code's* plugin primitive may use
"plugin" — the constraint is only against framing *Soleur* as an installable plugin.)

## Key Decisions

| Decision | Choice |
|----------|--------|
| Posture | Honest hedge — "whole company" headline, body honest about the 2 engineering-only elements |
| This-PR scope | Blog article only + `social-distribute` content file. No landing/docs copy change |
| Gap-closing build | **Decoupled** to a follow-up issue → unlocks "fully cross-domain" v2 post |
| Block-4 framing | "MCP connectors" only; no "plugin" framing on Soleur-subject surfaces |
| Attribution | Credit-and-extend wall: attributed section (Osmani + Cherny/Steinberger quotes) structurally separated from Soleur claims/CTAs. Explicit non-affiliation disclaimer |
| Quote gate | **Blocking** `fact-checker` pass — every named-person quote verbatim + sourced URL before publish |
| Source-available hygiene | No "open source" self-claim; Soleur is source-available (BSL 1.1) |
| AEO | Own the "loop engineering" term early; `Article` + `FAQPage` JSON-LD; long-tail "loop engineering for business/operations" |
| Execution pipeline | `content-writer` (draft) → `fact-checker` (blocking quotes) → `legal-compliance-auditor` (false-endorsement + "open source" leak pass) → `social-distribute` |

## User-Brand Impact

- **Artifact:** the published "loop engineering for your whole company" blog article (and its social
  distribution) — the public positioning surface.
- **Vector:** a published capability claim a prospect tests and finds false (e.g., "scheduled
  finance/marketing agents" that don't exist), or an implied endorsement by Osmani/Cherny/
  Steinberger/Google/Anthropic that isn't real — either erodes first-prospect trust.
- **Threshold:** single-user incident.

## Open Questions

- **Exact headline wording.** "Loop Engineering for Your Whole Company, Not Just Your Codebase" is
  the working title; `content-writer` + brand-guide voice may refine. Implementer's call at draft
  time, kept honest.
- **Which live examples to cite.** The body should name concrete running loops as proof. Engineering
  is the safest (real scheduled drift crons + 15 verifier agents); marketing/support can be cited at
  the substrate level (memory + skills + checker agent) without claiming scheduled autonomy.
- **`FAQPage` question set.** Recommended FAQ: "What is loop engineering?", "Can loop engineering
  work outside code?", "Is Soleur affiliated with Addy Osmani / Google / Anthropic?" (doubles as the
  non-affiliation disclaimer in AEO-readable form).

## Domain Assessments

**Assessed:** Marketing, Engineering, Product, Legal — Operations, Sales, Finance, Support not separately assessed (no domain-specific surface in a cross-domain positioning blog).

### Marketing

**Summary:** Frame is sound and on-brand ("Build the loop. Stay the engineer." mirrors "You decide.
Agents execute."). Sharpest angle: credit Osmani, then extend cross-domain as the original
contribution. "loop engineering" is a fresh, low-competition AEO term to own early. Plugin-framing
risk is HIGH (block 4) — map to MCP connectors only. Blog-first; defer landing copy.

### Engineering

**Summary:** Architecture mapping verified against code. Worktrees/Skills/MCP/External-memory are
genuinely cross-domain; Automations and maker/checker are engineering-only (9 crons run scripts not
agents; verifiers concentrated in `engineering/review/`). Distinguish 4 git-committed MCP servers
from runtime-available ones. Blog must hedge elements 1 and 5 honestly.

### Product

**Summary:** Capability-claim honesty is load-bearing (pre-beta, 0 users — claim ships ahead of
validation). 4 of 6 elements safe cross-domain; autonomous scheduling + maker/checker verification
work end-to-end only in engineering. "Whole company" is not literally defensible as *autonomous*
today — scope to "an AI org across every department, autonomous loop proven first in engineering."
External memory is the strongest, most defensible claim.

### Legal

**Summary:** Term adoption + attributed quoting is clean ("loop engineering" is a generic descriptive
coinage, no trademark blocker). Real risk is false endorsement (Lanham §43(a)) — the quotes endorse
the *term*, not Soleur. Two mandatory guardrails: (1) credit-and-extend wall + explicit
non-affiliation disclaimer; (2) blocking verbatim-quote fact-check gate. Plus: no "open source"
self-claim (BSL 1.1).

## Capability Gaps

None block this PR — `content-writer`, `fact-checker`, `legal-compliance-auditor`,
`growth-strategist`, and `social-distribute` all exist in-domain.

The **decoupled follow-up** (tracked as a separate issue, not a gap in this PR) closes the two
cross-domain architecture gaps so a future v2 post can claim full support honestly:
1. **Cross-domain scheduled agent crons** — wire ≥1 business-domain agent cron (via the existing
   `schedule` skill, which already supports any domain) for marketing/finance/support/etc. Evidence
   of gap: `grep -rl claude-code-action .github/workflows/scheduled-*.yml` → none.
2. **Cross-domain maker/checker verifier agents** — add a verifier agent to operations, product,
   support (none today) and designate maker/checker pairs in finance/sales. Evidence of gap:
   `ls plugins/soleur/agents/{operations,product,support}/` → no audit/review/check/verifier agent.
