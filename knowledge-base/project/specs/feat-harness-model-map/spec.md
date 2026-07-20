---
title: Harness semantic model-tier map
status: draft
closes: "#6316"
adr: ADR-110
domain: engineering
tags:
  - harness
  - grok
  - model-tiering
---

# Spec: Harness semantic model-tier map

## Goal

Make Soleur's workflow model pins and research-agent overrides work under **both** Claude Code and Grok Build by resolving semantic tiers (`cheap`, `standard`, `strong`, `advisor`, `inherit`) through a single plugin module.

**Tier semantics (corrected):** `strong` → Opus-class judgment (never-downgrade agents, scoring upgrades). `advisor` → Fable-class scoped consult **only** at the two ADR-083 gates (`plan` Step 4.5, `ship` Phase 5.5), with Opus fallback — Fable is not a general-purpose tier.

## Non-goals

- Migrating `claude-code-action` CI workflows to Grok
- Changing web-platform Inngest cron model literals or `MODEL_PRICING`
- Auto-detecting operator billing plan or API key vendor

## User stories

1. **As a Grok contributor**, when I run `/review` or `/drain-labeled-backlog`, mechanical subagent steps use an appropriate cheap Grok model, not a Claude alias that the harness ignores.
2. **As a Claude contributor**, existing cost tiering behavior is unchanged — `cheap` → `haiku`, `standard` → `sonnet`, `strong` → `opus`, `advisor` → `fable` (Opus fallback at the two gates only).
3. **As a maintainer**, when xAI or Anthropic ships a new model generation, I update one tier table row per semantic tier, not 12 workflow files.

## Implementation plan

### PR 1 — Planning (this PR)

- ADR-110 (Proposed)
- This spec
- Issue #6316

### PR 2 — Resolver + migration

| Task | File(s) | Notes |
|---|---|---|
| Resolver module | `plugins/soleur/lib/harness-model-map.ts` | `detectHarness()`, `resolveModelTier(tier)` |
| Unit tests | `plugins/soleur/test/harness-model-map.test.ts` | Fixture maps for `claude` + `grok`; unknown tier throws |
| Workflow wrapper | each `*.workflow.js` `agent()` helper | Resolve semantic tier before `opts.model` reaches harness |
| Pin migration | 8 workflow files, 12 call sites | Per `workflow-model-pins.test.ts` allowlist |
| Allowlist test update | `workflow-model-pins.test.ts` | Semantic tier names + parity test |
| Research agents | 5 `engineering/research/*` agents | `haiku` → `cheap` when spawn API supports it |
| AGENTS.md | Model Selection Policy section | Document semantic tiers; clarify `strong`=Opus vs `advisor`=Fable (ADR-083 only) |
| plan/ship SKILL.md gates | Step 4.5 / Phase 5.5 spawns | Use `advisor` tier via resolver (not raw `fable`) |

### PR 3 — Audit extension (optional follow-up)

- `model-launch-review/scripts/audit-models.sh` — add Grok tier-table staleness row
- Or new `harness-model-audit` skill subcommand

## Harness detection (resolver contract)

```typescript
type Harness = "claude" | "grok" | "unknown";
type SemanticTier = "cheap" | "standard" | "strong" | "advisor" | "inherit";

function detectHarness(env: NodeJS.ProcessEnv): Harness;
function resolveModelTier(tier: SemanticTier, harness: Harness): string;
/** `resolveAdvisorTier` — fable primary, strong (opus) fallback per ADR-083 */
function resolveAdvisorTier(harness: Harness): string;
```

Detection order (implementation PR validates):

1. `env.CLAUDECODE` set → `claude`
2. `env.GROK_SESSION` or Grok-specific marker (confirm against Grok docs at implementation) → `grok`
3. `unknown` → pass `inherit` through; log warning for non-inherit tiers

## Test matrix

| Tier | Claude fixture | Grok fixture |
|---|---|---|
| cheap | `haiku` | non-empty Grok fast model |
| standard | `sonnet` | non-empty Grok build model |
| strong | `opus` | non-empty Grok top reasoning model |
| advisor | `fable` (fallback `opus`) | advisor model (fallback: `strong` map) |
| inherit | `inherit` | `inherit` |

## Risks

- Grok may not support the same spawn `model:` enum shape as Claude Code — resolver may need per-harness output types (alias vs concrete ID).
- Tier table drift if xAI renames models — mitigated by audit checklist row.