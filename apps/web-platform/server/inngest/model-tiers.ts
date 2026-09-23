// Workload-class model-tier registry for the Inngest cron/event subsystem.
//
// Single source of truth for the Anthropic model IDs the scheduled crons
// and ship-merge event hand to the `claude` CLI via argv. Centralizes the
// ~17 inline sonnet / opus-4-7 model-ID literals (the pre-#5106 landscape —
// HISTORICAL, do not re-pin at a model launch) that were
// scattered across `functions/*.ts` (#5106; consolidation point named by
// ADR-053 line 38). Registry shape follows ADR-034 (frozen `as const`).
//
// Two workload classes:
//   EXECUTION_MODEL (sonnet) — the execution-class crons that do bounded,
//     well-scoped automation (bug-fixer, triage, content, digests, etc.).
//   AUDIT_MODEL (opus-5-5)   — the deep-audit crons that need stronger
//     multi-step reasoning (agent-native-audit, architecture-diagram-sync,
//     competitive-analysis, growth-audit, legal-audit, ux-audit).
//
// Audit effort (#8603): the audit tier also pins reasoning effort. The pinned
// CLI's bundled row for claude-opus-5-5 carries `default_effort: "medium"`
// (Opus 5's was high), so leaving effort unset silently lowered audit depth at
// the 5 → 5.5 swap. AUDIT_EFFORT = "high" restores it. The audit crons pass
// model and effort together by spreading AUDIT_CLI_ARGS — never by naming
// AUDIT_MODEL / AUDIT_EFFORT directly (model-tiers.test.ts Guard 1). Execution
// crons deliberately pass no `--effort` and stay on the CLI default (ADR-053
// amendment 2026-09-23). An unknown --effort VALUE is a silent fallback, not an
// error: claude-cli-pin-knows-models.test.ts probes the pinned CLI with this
// exact tuple.
//
// PURE SSOT EXTRACTION (as of #5106) — that PR changed no model assignment;
// every cron kept the model it had. Same-tier re-pins land here since. Per ADR-053, re-tiering a cron (e.g. moving an
// execution cron up to the audit tier, or a cron down to haiku) is a separate
// clo-attestation-class model-bump PR (with action-pin sync per learning
// 2026-04-18) and is explicitly out of scope here. `cron-weekly-release-
// digest.ts` self-identifies as never-downgrade-shaped; its sonnet pin is
// preserved via EXECUTION_MODEL and its rationale comment stays in place.
//
// Mixed alias/dated convention (do NOT normalize): `claude-sonnet-5` and
// `claude-opus-5-5` are aliases (alias == dated, no separate dated ID),
// while `claude-haiku-4-5-20251001` (imported transitively via constants)
// is the dated form. A future cleanup must preserve the dated haiku literal
// byte-for-byte.
//
// Opus is intentionally absent from `MODEL_PRICING` in
// functions/agent-on-spawn-requested.ts: `leaderModule.model` is typed
// `AnthropicModelId` (the 2-value sonnet|haiku union from
// leader-prompts/constants.ts), and that is the only value that flows
// through the `MODEL_PRICING[leaderModule.model]` lookup. Opus
// never reaches the pricing path, so the parity test (model-tiers.test.ts)
// is scoped to the consumed values. If a future PR makes opus reachable
// through that lookup, add the opus pricing entry and widen the test then.

import { SONNET_MODEL } from "./leader-prompts/constants";

/** Execution-class crons run on sonnet. Imported, not re-declared (FR3 — no second SSOT). */
export const EXECUTION_MODEL = SONNET_MODEL;

/** Deep-audit crons run on opus-5-5. Pinned exactly; re-tiering is out of scope (ADR-053). */
export const AUDIT_MODEL = "claude-opus-5-5" as const;

/**
 * Reasoning effort for the audit tier. The CLI default for claude-opus-5-5 is
 * `medium`; the audit crons are the deep multi-step judgment workloads that
 * justify the opus tier, so they run at `high`. Re-decide at each model launch
 * against the new row's `default_effort` (model-launch-review SKILL.md row 3).
 */
export const AUDIT_EFFORT = "high" as const;

/**
 * The ONLY place the audit model and effort are paired. Audit crons spread this
 * into their CLAUDE_CODE_FLAGS before the `"--"` end-of-options marker (a flag
 * after it becomes prompt text, #4017).
 */
export const AUDIT_CLI_ARGS = [
  "--model",
  AUDIT_MODEL,
  "--effort",
  AUDIT_EFFORT,
] as const;

/**
 * Substring of the pinned CLI's stderr warning for an unknown `--effort` VALUE
 * (the CLI then runs at the model's default effort and exits 0). One constant
 * for the substrate's Sentry mirror and the pinned-CLI probe's positive
 * control, so a CLI reword cannot be fixed in the test while the runtime
 * matcher silently stops matching.
 */
export const CLI_EFFORT_FALLBACK_NEEDLE = "Unknown --effort value";
