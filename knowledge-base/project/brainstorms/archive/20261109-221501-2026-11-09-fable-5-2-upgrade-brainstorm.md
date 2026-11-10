# Fable 5.2 upgrade — brainstorm (2026-11-09)

Source: https://www.anthropic.com/claude-fable-and-mythos-5-2 (fetched 2026-11-09). Branch `feat-fable-5-2-upgrade`, draft PR #12513.

## What We're Building

Move Soleur from Fable 5.1 to Fable 5.2 (`claude-fable-5-2`) and adopt only the article items that fit the existing model policy (ADR-053, ADR-083, ADR-110). It is a model-launch change, not a feature: audit tooling, tests and policy docs.

## Article facts used

- Fable 5.2: $8 input / $40 output per MTok (Fable 5.1: $10 / $50). Fast mode $16 / $80, up to 2.5x faster.
- Mythos 5.2: same model without cyber/bio safeguards, vetted organizations only, no public API ID.
- Preserved thinking for all accounts; effort levels Low to Max, Medium default in Claude Code.
- Vendor claims (not measured here): ~30% faster than 5.1, ~55% fewer classifier blocks.
- Fable 5.2 can act as Advisor or Orchestrator. No deprecations.

## Repo findings (verified in the worktree)

- `audit-models.sh` reports no stale IDs: Fable reaches Soleur only as the harness alias `model: fable` (`plugins/soleur/lib/harness-model-map.ts` advisor tier) and the ADR-083 consult gates. No web-platform code uses a fable ID.
- `AUTOFIX_PAIRS` still maps `claude-fable-5` to `claude-fable-5-1`; it must be retargeted to `claude-fable-5-2` (single-hop rule).
- Pinned `claude-code` CLI 2.1.311 has 0 hits for `claude-fable-5-2` (12 for `-5-1`). 2.1.321 (published 2026-11-09) has 10; 2.1.315 has 0.
- Pricing basis in ADR-053 and `plugins/soleur/AGENTS.md` still says Fable 5.1.

## Key Decisions (CTO ruling, agent-ruled)

Ruled by CTO agent, 2026-11-09:

| Question | Ruling |
|---|---|
| CLI bump in this PR | Defer. Nothing sends a fable ID as an argv value, so the #6934 `max_tokens` halving does not apply. A bump is a supply-chain change spanning 10 releases. Flip: any web-platform tier or cron gaining a fable literal means bump first. Follow-up issue records a `grep -a` check of 2.1.321. |
| Fast mode | Not adopted. Raises spend (2x price); operator authorization if ever wanted. |
| Preserved thinking | Not adopted. No consumer. |
| Orchestrator role | Not adopted. Would expand ADR-083's two named gates. |
| Advisor role | Unchanged. Already the ADR-083 consult; 5.2 confirms the pattern. |
| Effort | No change. `AUDIT_EFFORT` is Sonnet/Haiku tier; note Medium default. |
| `MODEL_PRICING` | Untouched (billing constant). |
| Mythos 5.2 | Not usable: no public API ID, vetted organizations only. |

Change set: retarget `AUTOFIX_PAIRS`; update `model-launch-review.test.ts` and the SKILL.md release list; ADR-053 "Fable 5.2 re-tier review" section ($8/$40, Fable-vs-Sonnet 5.5 now ~4x, no pin change); refresh the pricing basis in `plugins/soleur/AGENTS.md`; ADR-083/110 addendum recording the rejections. Vendor speed/block claims are recorded as vendor claims, never as measurements.

## User-Brand Impact

- **Artifact:** the Soleur plugin's model-launch tooling (`model-launch-review` audit, tier map, ADR-053 pricing basis).
- **Vector:** a stale or wrong model ID or price silently misroutes spend or breaks advisor consults for a user.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering (CTO). Product, Legal, Marketing, Finance and the other domains were not consulted: no user-facing surface, no data handling, no external copy. The Phase 0.1 triad default was narrowed to the CTO because the scope is internal tooling and the one cost question (fast mode) was ruled out.

### Engineering

**Summary:** Defer the CLI bump, adopt only the pricing re-derivation, reject fast mode, preserved thinking and the orchestrator role for now.

## Open Questions

- Does the `fable` alias resolve to 5.2 on pinned CLI 2.1.311? Unverified; tracked in the follow-up issue.
- Re-derive every pricing row from the official pricing page during planning (past launches copied a wrong inherited figure).
- Whether to later evaluate fast mode for the ADR-083 consult (operator money decision, out of scope).
