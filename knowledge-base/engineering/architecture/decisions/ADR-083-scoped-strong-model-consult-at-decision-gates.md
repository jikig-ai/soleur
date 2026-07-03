# ADR-083: Scoped strong-model consult at decision gates (token-frugal advisor)

- **Status:** Accepted
- **Date:** 2026-07-03
- **Issue:** operator request 2026-07-03 (no tracking issue) — "Fable 5 is out but consuming too many tokens; enable it as an advisor" → follow-up: "reimplement the advisor without re-sending the full context, optimize for token savings."
- **Relationship to ADR-053:** extends the tier-4 (SKILL.md-prose) surface of [ADR-053](./ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md). ADR-053 tier 4 permitted SKILL.md prose to spawn a Task/Agent at a **cheaper** tier for **mechanical** steps only. This ADR permits a single **upgrade** pin (`model: fable`) for a **judgment** step at two named gates. Frontmatter inheritance and the workflow-pin tiers are unchanged.

## Context

Fable 5 prices at $10/$50 per MTok — 2× Opus 4.8 (per ADR-053). Two ways to get Fable-grade judgment at a task's decision points:

1. **Claude Code's built-in [advisor tool](https://code.claude.com/docs/en/advisor)** — `advisorModel: "fable"` in settings. It is a *server-side* tool: on every call it re-sends the **full conversation transcript** to the advisor, **uncached** (each call reprocesses the whole transcript anew), at the advisor's rates. Timing is model-driven (no config to force/cap), and **subagents inherit it** — so on Soleur's high-fan-out skills (`/review` ≥ 8 agents; `/one-shot`, `/drain` many more) every spawn can fire a full-transcript Fable call. On a long autonomous run the transcript is huge, making each advisor call very expensive. Its internal context-packaging is fixed by Anthropic; it cannot be reimplemented to send less.

2. **A Soleur-native scoped consult** — spawn our own `Task` subagent at the gate. A Task subagent **receives prompt text only, never the parent conversation** (`knowledge-base/project/learnings/best-practices/2026-05-12-task-subagent-prompt-text-only.md`). So we control the payload exactly: hand it the plan sections / diff + findings + a sharp question — a few KB — instead of the whole session.

The operator's explicit goal is to **optimize for token savings**. Option 1 optimizes the opposite way. Option 2 delivers the same "Fable judgment at plan/completion gates" at a fraction of the tokens, with no fan-out inheritance surface.

## Decision

1. **Do NOT enable the built-in `advisorModel`** globally (no `advisorModel` key in `.claude/settings.json`).
2. **Wire a scoped consult at the two decision gates:**
   - **Plan-finalization gate** — `plan` SKILL.md Step 4.5: before issues are created, spawn `Task(model: fable)` with only the plan's Overview + Implementation Phases + riskiest phase, asking for the one or two highest-leverage approach changes.
   - **Completion gate** — `ship` SKILL.md Phase 5.5: before the feature is declared shippable, spawn `Task(model: fable)` with only the branch diff summary + unresolved review findings + acceptance criteria, asking whether it is genuinely complete.
   `one-shot` inherits both gates transitively (it invokes `plan` and `ship`); it is deliberately **not** edited, to avoid colliding with its CONTINUATION-GATE anti-stop rules.
3. **`model: fable`, `opus` fallback.** If the org lacks Fable access, the consult falls back to `model: opus`. The consult is a single explicit spawn at a gate — never propagated to leaf fan-out agents.

## Semantics

- **Curation is the token lever.** Cost per gate call drops from *full-transcript × Fable rate* (built-in advisor) to *curated-payload × Fable rate* — typically 10–100× less on a long run. The payload is authored, not the transcript.
- **The accepted tradeoff:** the consult sees only what we quote, so it cannot spot the dead-ends, repeated failures, or loops that the full-transcript built-in advisor would. We trade some catch-rate for a large, controllable token saving. Judgment-sensitive: keep the curated payload honest (include the riskiest phase / unresolved findings, not a rosy summary).
- **Runs headless.** A Task-spawn consult returns advice text without pausing, so it works inside autonomous `one-shot` without an interactive stop. Advisory only — the running skill applies guidance but does not block, loop, or re-consult.
- **Untrusted-payload guard (ship gate).** The completion consult quotes branch-diff hunks, which are attacker-influenceable. The reply is therefore an advisory completeness *opinion only* — it cannot authorize a merge or waive a gate, embedded instructions in the diff are ignored, and the deterministic ship gates (Code Review Completion, Review-Findings Exit) remain the sole merge blockers. Secret-bearing files (`.env*`, key/credential files) are excluded from the quoted hunks. The plan gate's payload is in-session-authored prose, so its injection surface is negligible.
- **Upgrade-pin justification (ADR-053 alignment).** Pinning *up* to Fable for a judgment gate mirrors ADR-053's cited sonnet→opus scoring-upgrade precedent (a deliberate upgrade for a judgment workload). It is bounded to exactly two gates and is discoverable — the tier-4 discovery grep must include `fable`:
  ```bash
  grep -rn 'model: sonnet\|model: haiku\|model: fable' plugins/soleur/skills/*/SKILL.md
  ```
  This is a SKILL.md-prose surface, so it is **not** governed by `plugins/soleur/test/workflow-model-pins.test.ts` (that test scans `*.workflow.js` only).

## Verification

Each consult ≈ curated payload in + short advice out, once per gate. Executed model is confirmable in the spawned agent's transcript (`grep -ho '"model":"[^"]*"' <agent-transcript>.jsonl`, per ADR-053's recipe) and in `/usage` session totals. Re-evaluation trigger: the `model-launch-review` skill (#5100) re-checks the Fable tier/alias at each model release.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Built-in `advisorModel: fable` (global) | Full transcript re-sent uncached every call + subagent-inheritance fan-out — the exact token cost the operator is optimizing away. Its server-side context packaging cannot be reimplemented to send less. |
| Fable 5 as the **main** model | Top-tier cost on every routine turn — the originating problem. |
| Dedicated `advisor` agent file (`model: fable`) | Adds an agent to the registry, token-budget, and docs surfaces for a two-gate consult; an inline `Task` spawn in the two skills is lighter and equally governed. |
| Consult on the **session** model (no fable pin) | Defeats the goal — the ask is specifically Fable-grade judgment at the gates. |
| Edit `one-shot` too | Redundant — its gates come from `plan`/`ship`; a third nudge risks its CONTINUATION-GATE anti-stop logic. |

## Consequences

- Fable-grade judgment at the plan and completion gates at a fraction of the built-in advisor's tokens, with no fan-out inheritance blowup.
- A new SKILL.md-prose **upgrade-pin** surface (fable at judgment gates), kept discoverable via the extended grep above; changing the gate set is a model-policy edit.
- Lower catch-rate than a full-transcript advisor on context-dependent problems (loops/dead-ends) — the deliberate cost of the saving.
- Fully reversible: delete the two gate blocks. No settings or global state to unwind.
