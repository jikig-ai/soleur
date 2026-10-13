---
title: "deepagents Portability Recommendation"
date: 2026-06-08
issue: 5034
---

# Recommendation: deepagents (LangChain) as Alternative Harness

## Decision: NO-GO as a mechanical port · CONDITIONAL-GO as a strategic server-side rebuild

deepagents is **not** worth a parallel mechanical port the way OpenHands is. But it is the strongest target yet for a *specific* strategic move — a model-agnostic, durably-persistent, server-side agent runtime — and that play connects directly to Soleur's existing `soleur-server-side-agentic-runtime` direction. The highest-value option is a **hybrid**, not a replacement.

## Evidence Summary

| Metric | Codex CLI | Gemini CLI | OpenHands | deepagents |
|---|---|---|---|---|
| GREEN (ports as-is) | 47.5% (58/122) | 54.3% (70/129) | 46.5% (60/129) | **19.7% (30/152)** |
| YELLOW (needs adaptation) | 7.4% | 45.0% | 53.5% | **80.3% (122/152)** |
| RED (requires rewrite) | 43.4% | 0.8% | 0% | **0%** |
| Blockers with no equivalent | 4 | 1 | 0 | **0** |
| Agent authoring format | Config YAML | Markdown | Markdown | **Python dict** |
| Skill authoring format | SKILL.md | SKILL.md | SKILL.md | **SKILL.md (identical)** |
| Subagent parallelism | None | Sequential | Parallel | **Parallel** |
| TodoWrite | None | `write_todos` | None | **`write_todos` (built-in)** |
| Structured prompts | None | `ask_user` | None | **None (respond only)** |
| Plugin / distribution | None | None | **Full** | **None (skills dir)** |
| Model support | OpenAI | Gemini | Any LLM | **Any LLM** |
| Durable persistence | None | None | Docker state | **Checkpointers (Postgres/Redis)** |
| Maturity | OpenAI-backed | Google-backed | OSS growing | **24k★ LangChain-backed, MIT** |

## The central finding: the OpenHands pattern inverts

OpenHands was attractive precisely because Soleur's markdown agents ported 1:1 (markdown→markdown) and its plugin system let you ship everything as one installable bundle. deepagents inverts both:

1. **Agents flip GREEN→YELLOW.** Subagents are Python `SubAgent` dicts; there is no markdown-agent loader. All 67 agents — the entire CMO/CFO/CLO/COO/CPO/CRO/CCO domain-leader hierarchy plus 24 review/research specialists — must be re-authored in Python. The prose ports verbatim, so it's *mechanical*, but it's 67 rewrites plus 5 bash-hook rewrites.
2. **No plugin distribution.** There is no `plugin.json`/`marketplace.json` equivalent. You ship agents/hooks as a **Python package** and skills as a **directory** — two artifacts, no enable/disable/uninstall story.

Against that, deepagents flips two things *for* you:
3. **Skills port better.** Identical `SKILL.md` + progressive disclosure. 29 skills are GREEN today; the format itself is a non-event.
4. **It's the only target with built-in `write_todos`, durable checkpointer persistence, true model-agnosticism, and a mature corporate backer — and it is now a real harness (`dcode`), not just a library.**

So: **expensive to port, but the most strategically valuable destination** if the goal is anything other than "same Soleur, different CLI."

## What this means by goal

| If the goal is… | Verdict | Why |
|---|---|---|
| A cheap second harness (insurance vs Claude availability/pricing) | **Use OpenHands, not deepagents** | OpenHands keeps agents as markdown + has a plugin system → 1–2 wk degraded pipeline. deepagents costs 67 agent rewrites for the same outcome. |
| Run Soleur agents on non-Claude models | **deepagents (CONDITIONAL-GO)** | Only target with first-class model-agnosticism *and* a harness. The agent rewrite is unavoidable on any model-agnostic LangGraph path. |
| Server-side, durable, multi-tenant agent runtime | **deepagents (CONDITIONAL-GO, strong fit)** | Checkpointers (Postgres/Redis) + state backends are a greenfield-grade fit; ties into `soleur-server-side-agentic-runtime` + ADR-030 (Inngest durable trigger layer). |
| Ship Soleur skills to a broader LangChain audience | **deepagents skills-only port (GO, low cost)** | 29 GREEN + ~20 light-YELLOW skills publish as a `SKILL.md` package consumable by any deepagents/dcode user. |

## Recommended play: hybrid, not replacement

**Do not replace the Claude Code harness.** Instead, if/when a trigger fires:

1. **Skills-first.** Port the 29 GREEN skills (+ light-YELLOW) to a deepagents `skills/` package. Low cost, immediately reusable, and validates the format-parity claim in production. This is the cheapest way to "have a deepagents story."
2. **deepagents as a server-side skill/agent execution runtime** feeding the existing Claude Code harness — model-agnostic, durably checkpointed — rather than a desktop CLI replacement. Keep the markdown agent hierarchy authoritative on Claude Code; mirror only what the server runtime needs.
3. **Full harness migration only as a deliberate strategic rebuild**, scoped as its own initiative (not a port), if model-agnosticism becomes a hard product requirement.

## Trigger for Investment

Invest in deepagents when ANY of:

1. **Model-agnosticism becomes a hard requirement** — a customer/compliance need to run Soleur agents on GPT/Gemini/open-source models. (This is deepagents' #1 differentiator vs OpenHands.)
2. **Server-side durable agent runtime** is greenlit — deepagents' checkpointer model is the strongest fit analyzed; align with `2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md` and ADR-030.
3. **LangGraph/LangSmith** is adopted elsewhere in the stack (shared observability/tooling lowers marginal cost).
4. **Skills-as-product** — desire to distribute Soleur skills to the LangChain ecosystem (24k★ reach).
5. **dcode matures** — the `deepagents-code` CLI graduates past v0.1.0 packaging churn and demonstrably runs long multi-step pipelines (resolves critical-unknown #1).

Do **not** invest merely for harness redundancy — OpenHands dominates that use case at a fraction of the cost.

## Estimated Effort

| Scope | Effort | Outcome |
|---|---|---|
| Skills-only port (29 GREEN + ~20 light-YELLOW) | 1–2 weeks | deepagents-consumable skill package; format-parity validated |
| GREEN skills + 43 prose agents (bulk-scripted SubAgent wrap) | 2–3 weeks | Agent library + simple skills, model-agnostic |
| Full harness parity (67 agents + 53 YELLOW skills + 5 hook rewrites + MCP wiring + distribution packaging) | **6–10 weeks** | Degraded-but-functional pipeline. **Not recommended as a port** — costs 3–5× OpenHands for a worse distribution story |
| Server-side runtime built on deepagents (greenfield) | Separate initiative | Model-agnostic durable runtime; scope under `soleur-server-side-agentic-runtime` |

For comparison, OpenHands full-pipeline was estimated at 1–2 weeks. deepagents' agent-rewrite + hook-rewrite + no-plugin-distribution triples-to-quintuples that for the *mechanical* path — which is exactly why the recommendation is hybrid/strategic, not port.

## Critical Constraints

1. **67 Python agent rewrites + 5 Python hook rewrites** — unavoidable on any deepagents path. Mechanical but not free; no markdown-agent loader exists.
2. **No structured user prompts** — `HumanInTheLoopMiddleware` has approve/edit/reject/respond, no options schema. Soleur's brainstorm/plan/ship gates degrade to freeform (same as OpenHands).
3. **No plugin distribution** — ship as Python package + skills dir; no enable/disable/marketplace. The one axis where deepagents is worse than OpenHands.
4. **dcode immaturity** — the operator harness is young; production-readiness for Soleur's pipelines is unverified.

## Follow-up (if proceeding)

1. PoC: run a 3-skill + 2-agent slice on `dcode` to resolve critical-unknowns #1 (harness maturity), #2 (subagent nesting), #3 (structured-prompt absence impact).
2. Spike: skills-only package + publish-consume round-trip on a non-Claude model (validate model-agnosticism end-to-end).
3. Align with `soleur-server-side-agentic-runtime` plan owner on whether deepagents' checkpointer model supersedes the current runtime substrate choice.
4. Monitor `langchain-ai/deepagents` for: a markdown-agent loader (would flip 43 agents back to GREEN), a structured-prompt primitive, and a plugin/distribution system.

## References

- deepagents inventory: `knowledge-base/project/specs/feat-deepagents-portability/inventory.md`
- deepagents critical unknowns: `knowledge-base/project/specs/feat-deepagents-portability/critical-unknowns.md`
- OpenHands recommendation: `knowledge-base/project/specs/openhands-portability/recommendation.md`
- Platform comparison: `knowledge-base/engineering/platform-portability-comparison.md`
- Server-side runtime: `knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md`
- ADR-030 (Inngest durable trigger layer): `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`
