# ADR-110: Harness semantic model-tier map (Claude Code + Grok Build)

- **Status:** Proposed
- **Date:** 2026-07-10
- **Issue:** [#6316](https://github.com/jikig-ai/soleur/issues/6316)
- **Relates to:** [ADR-053](ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md) (workflow pin semantics), [ADR-089](ADR-089-freeze-lock-shared-state-substrate.md) (cross-harness shared substrate), [ADR-083](ADR-083-scoped-strong-model-consult-at-decision-gates.md) (strong-tier consult), #6314 (Grok Build project config)

## Context

Soleur's interactive plugin runs under multiple agent harnesses. Claude Code is the primary target; Grok Build now loads the same in-repo plugin via `.grok/config.toml` (#6314). The Model Selection Policy (ADR-053) tiers cost at workflow spawn sites using **harness-native enum aliases** (`'sonnet'`, `'haiku'`, `'fable'`) and agent frontmatter pins (`model: haiku` on five research agents). Those aliases are Anthropic-specific — Grok sessions cannot resolve them, so mechanical workflow steps (classify, fetch, commit-message) either fail or fall back unpredictably.

ADR-053 deliberately chose harness aliases over concrete IDs for workflow pins (zero repo maintenance on Anthropic model deprecation; silent retargeting risk accepted). That tradeoff is harness-local. A second harness requires a **semantic** tier layer that each vendor maps independently, without scattering `if (grok)` across 94 skills.

**Surfaces that stay vendor-specific (not migrated):**

- GitHub Actions `claude-code-action` `--model claude-*` pins (server automation; hard-fail loudly at retirement — ADR-053 surface table)
- Web-platform Inngest cron literals and `MODEL_PRICING` (billing constants; #5106 registry consolidation track)
- `model-launch-review` Anthropic release checklist (extend separately for Grok tier table freshness)

## Decision

1. **Introduce four semantic tiers** for plugin spawn sites: `cheap`, `standard`, `strong`, `inherit`. Names describe **cost/role**, not vendor SKUs (ADR-053 mechanical vs judgment split preserved).

2. **One resolver module** at `plugins/soleur/lib/harness-model-map.ts` maps semantic tier → harness spawn value. Harness detection is centralized (env markers + config presence); skills and workflows call the resolver — never branch on vendor inline.

3. **Workflow pins migrate** from `'sonnet'`/`'haiku'` to `'standard'`/`'cheap'` at the 12 ADR-053 allowlisted call sites. Resolution happens in the workflow `agent()` wrapper immediately before spawn (single choke point per workflow runtime).

4. **Research agent frontmatter** migrates from `model: haiku` to `model: cheap` once the harness accepts semantic tiers in Task/Agent spawn; until then, spawning skills pass `cheap` explicitly via the resolver at the call site.

5. **`workflow-model-pins.test.ts` allowlist** tracks semantic tiers. A parity test asserts every tier resolves to a non-empty harness value for both `claude` and `grok` fixture maps.

6. **Tier tables are versioned config**, not memory. Initial Grok mappings are placeholders validated against `grok inspect` / official xAI docs at implementation time. `model-launch-review` (or a sibling audit row) gains a Grok tier-table freshness check on each xAI model release.

### Initial tier map (illustrative — implementation PR validates against live docs)

| Semantic | ADR-053 role | Claude Code | Grok Build |
|---|---|---|---|
| `cheap` | Mechanical fan-out | `haiku` | fast/cheap Grok model (TBD at implementation) |
| `standard` | Classify, parse, cluster | `sonnet` | `grok-build` or successor (TBD) |
| `strong` | ADR-083 scoped consult only | `fable` (fallback `opus`) | reasoning-tier model (TBD) |
| `inherit` | Judgment, operator agency | session model | session model |

## Consequences

- **Positive:** Grok and Claude operators get the same Soleur workflows; ADR-053 cost tiering semantics survive harness switches; one file to update per vendor model generation bump (tier table, not 12 call sites).
- **Negative / accepted:** Loses ADR-053's "zero repo maintenance" property for Anthropic-only alias retargeting — tier tables must be updated when vendors rename tiers (mitigated by audit skill). Resolver adds a small indirection layer workflows must import.
- **Migration:** Two PRs — (1) ADR + spec + resolver scaffold, (2) workflow/agent migration + tests. No big-bang: resolver can pass through unrecognized tiers during rollout.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Keep Anthropic aliases; document Grok as best-effort | Mechanical steps break or cost-spike under Grok — violates harness-agnostic positioning (#6314 intent). |
| Concrete model IDs in workflow pins | ADR-053 rejected this for Claude (hard-fail vs silent retargeting); doubles maintenance across harnesses. |
| Per-harness workflow copies | 12× duplication; drift guaranteed (opposite of ADR-089 substrate pattern). |
| Session-relative tiers | ADR-053 rejected — non-deterministic cost contract; runtime lacks relative tier API. |