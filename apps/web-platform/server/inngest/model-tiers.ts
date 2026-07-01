// Workload-class model-tier registry for the Inngest cron/event subsystem.
//
// Single source of truth for the Anthropic model IDs the scheduled crons
// and ship-merge event hand to the `claude` CLI via argv. Centralizes the
// ~17 inline sonnet / opus-4-7 model-ID literals that were
// scattered across `functions/*.ts` (#5106; consolidation point named by
// ADR-053 line 38). Registry shape follows ADR-034 (frozen `as const`).
//
// Two workload classes:
//   EXECUTION_MODEL (sonnet) — the execution-class crons that do bounded,
//     well-scoped automation (bug-fixer, triage, content, digests, etc.).
//   AUDIT_MODEL (opus-4-7)   — the deep-audit crons that need stronger
//     multi-step reasoning (agent-native-audit, competitive-analysis,
//     growth-audit, legal-audit, ux-audit).
//
// PURE SSOT EXTRACTION — no model assignment changes. Every cron keeps the
// model it has today. Per ADR-053, re-tiering a cron (e.g. sweeping the
// audit crons up to opus-4-8, or a cron down to haiku) is a separate
// clo-attestation-class model-bump PR (with action-pin sync per learning
// 2026-04-18) and is explicitly out of scope here. `cron-weekly-release-
// digest.ts` self-identifies as never-downgrade-shaped; its sonnet pin is
// preserved via EXECUTION_MODEL and its rationale comment stays in place.
//
// Mixed alias/dated convention (do NOT normalize): `claude-sonnet-5` and
// `claude-opus-4-8` are aliases (alias == dated, no separate dated ID),
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

/** Deep-audit crons run on opus-4-7. Pinned exactly; re-tiering is out of scope (ADR-053). */
export const AUDIT_MODEL = "claude-opus-4-8" as const;
