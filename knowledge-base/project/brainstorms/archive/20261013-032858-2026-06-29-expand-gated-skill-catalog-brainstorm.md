---
title: Expand gated-skill catalog with golden sets for more classifier surfaces
date: 2026-06-29
issue: 5704
parent_brainstorm: knowledge-base/project/brainstorms/2026-06-29-skill-eval-gate-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
status: ready-for-plan
---

# Expand gated-skill catalog with golden sets for more classifier surfaces

## What We're Building

Bring two more single-token classifier surfaces under the eval-harness validation gate
that shipped in #5701/#5702 (merged 2026-06-29). For each surface, add the additive opt-in
unit — a closed enum, a synthesized golden set, the two arm prompts (baseline + generated
skill projection), a `promptfooconfig`, an `eval-gate:block:<id>` sentinel pair around the
rule prose in the source file, and a `gated-skills.json` registry row:

1. **brainstorm lane-inference** — `procedural | single-domain | cross-domain`
   (`plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` §Lane Inference).
2. **skill-security-scan verdict** — `LOW-RISK | REVIEW | HIGH-RISK`
   (`plugins/soleur/skills/skill-security-scan/SKILL.md`).

Delivered as **one PR per surface**, lane-inference first (cleanest, proves the additive
template), then skill-security-scan. Both PRs reference #5704.

## Why This Approach

- **Premise confirmed actionable.** #5704's re-evaluation trigger ("after #5702 ships and
  the gate is proven on go-routing + ticket-triage") has fired: #5702 is CLOSED, closed by
  #5701, merged 2026-06-29T15:36Z. The v1 gate is live on its two surfaces.
- **Bounded to verifiable single-token classifiers** (inherited from parent Decision 4).
  Subjective/open-ended surfaces (brainstorm dialogue, plan, legal, marketing) provably
  cannot use this method. Only surfaces with a closed enum + a prose rubric the LLM applies
  qualify.
- **The issue named pdr-* as the example; the gateable core of pdr IS lane-inference.**
  Passive-domain-routing (`pdr-*`) routes by *signal orthogonality* (how many distinct-domain
  asks → how many leaders) and does not map to a single closed label — it is genuinely
  multi-label. But its single-token *output slice* is exactly the lane breadth enum
  (`procedural`/`single-domain`/`cross-domain`). Gating lane-inference therefore satisfies
  #5704's pdr intent for the part that has a verifiable signal, and defers only the
  irreducibly-multi-label "which specific leaders" slice.
- **skill-security-scan is the strongest new signal.** Unlike lane-inference (a deterministic
  keyword scan, so the LLM-arm-vs-baseline delta is muted), the security verdict is a genuine
  LLM judgment over a multi-section severity-aggregation rubric — the gate's delta is
  meaningful, and a regression here has a real user-facing vector (a HIGH-RISK skill
  mis-graded LOW-RISK).
- **One PR per surface** isolates each surface's manual ~230-API-call opt-in run (deliberately
  kept out of per-PR CI per parent Decision + the harness budget gate). A weak golden set
  blocks only its own PR.

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Which surfaces | **lane-inference + skill-security-scan** | Two clean single-token classifiers with a real prose rubric. Operator-selected. |
| 2 | pdr-* | **Defer to its own issue** | Genuinely multi-label; constraining golden tasks to single-signal cases would skip pdr's hard case (orthogonality of distinct asks) and give false confidence. Its single-token output slice is already covered by lane-inference. |
| 3 | pdr handling (if ever built) | **Set-membership assert, not single-label** | A net-new assert script (README defers non-single-token to v1+). Tracked in the deferred issue, not this scope. |
| 4 | Delivery shape | **One PR per surface** (lane first) | Isolates each manual opt-in run; keeps each diff reviewable; lane proves the additive template before security-scan. |
| 5 | Golden-set design | **~6-8 synthesized tasks each + adversarial keyword-overlap cases** | Per `2026-05-15-classifier-prose-table-row-ordering-collision`: routing classifiers must include cross-label-overlap tasks (a message that plausibly matches two labels) — those are exactly the regressions the gate exists to catch. Synthesized fixtures only (`cq-test-fixtures-synthesized-only`). |
| 6 | Reuse vs new code | **Reuse generic asserts + models.generated.json unchanged** | Both surfaces are single-token; no new script needed (additive recipe). |
| 7 | Deferred future candidate | **incident `brand_survival_threshold`** noted, not scoped | Single-label with a real prose rubric, but operator-advisory-with-override → weaker signal. Revisit if the gate proves out on these two. |

## Open Questions

- **lane-inference muted-delta acceptance.** Because lane inference is rule-deterministic, the
  skill-arm may not beat baseline by much. Acceptance question for plan/implementation: is a
  small-but-positive delta sufficient evidence, or does lane warrant a note that its value is
  primarily *regression detection* (does an edit to the lane table break a previously-passing
  task) rather than *arm uplift*? (Lean: regression-detection framing; the gate's accept rule
  is no-regression + target-improvement, which works regardless of baseline delta size.)
- **AGENTS.core.md sentinel cost (lane lives in a reference file, not core — N/A for lane).**
  Confirmed lane-inference rule lives in `brainstorm-domain-config.md` (a reference file, NOT
  always-injected), so no always-on context-budget cost. skill-security-scan rule lives in its
  own SKILL.md (also not always-injected). Neither surface incurs the AGENTS.core.md
  always-injected-comment cost the CTO flagged for a hypothetical pdr gate.

## User-Brand Impact

- **Artifact:** the eval-harness gated-skill catalog — specifically the lane-inference and
  skill-security-scan validation gates added to `gated-skills.json`.
- **Vector:** a silently-regressed classifier ships because its golden set was too weak to
  catch the regression, and an agent then mis-routes a real user request — e.g.
  skill-security-scan grades a HIGH-RISK skill as LOW-RISK and it gets installed, or lane
  mis-sizing drops a domain leader so a user-impact/legal gate never fires.
- **Threshold:** single-user incident.

Tagged user-brand-critical (auto, per #5175). The vector is honest, not ceremonial: these
gates exist precisely to stop classifier regressions that reach users. The plan inherits
`Brand-survival threshold: single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Confirmed lane-inference and skill-security-scan as the best fits for the existing
single-token machinery; caught skill-security-scan as a candidate and ruled out incident
severity as redundant with ticket-triage. Recommended deferring pdr entirely (multi-label;
half-covering it gives false confidence) and delivering one surface per PR. Flagged that
lane-inference is a deterministic keyword scan (muted arm/baseline delta) and that
AGENTS.core.md sentinels would add always-injected context cost — moot here since neither
chosen surface lives in core.

> Marketing, Operations, Product, Legal, Sales, Finance, Support: no implications — this is
> internal CI/agent-infra tooling adding synthesized test fixtures and config to an existing
> skill. No user-data, credential, auth, billing, or external-facing surface.

## Capability Gaps

None. The `soleur:eval-harness` skill (additive recipe) and the `prompt-engineer` agent cover
authoring enums, arm prompts, and synthesized golden sets. Evidence: `gated-skills.json` +
README §"Adding a new target (the additive recipe)" describe the full additive unit with no
new script required for single-token surfaces; CTO assessment confirmed no missing agent/skill.
