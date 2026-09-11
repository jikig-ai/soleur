// #8076 — SOLEUR_CRON_FILING_DENY: the cron substrate's filing-gate denials,
// made observable off-host.
//
// The cron containment hook (`cron-bash-allowlist-hook.mjs`) writes its deny
// decision to Claude Code's stdin channel only; nothing reached Better Stack,
// and the first live contact (#8059: denied, then relabelled `meta/machinery`)
// had to be INFERRED from the issue's label set. There is no hook-side write
// and no jsonl: a PreToolUse hook deny lands in the `claude --print
// --output-format json` result event's `permission_denials[]` with the full
// `tool_input.command` (measured 2026-09-11 with a throwaway deny hook), and
// `_cron-claude-eval-substrate.ts` already parses that event. This module
// counts the filing-shaped entries and emits ONE marker per run.
//
// Same contract as SOLEUR_CLAUDE_COST (claude-cost-marker.ts): pino WARN
// (level 40) because the Vector `app_container_warn_filter` ships only
// level >= 40 to Better Stack; fail-open (never throws); PII-free — the marker
// carries the command HEAD (first three tokens: `gh issue create`), never a
// title, body, or label value. "Denied and did not comply" is this marker plus
// the existing `scheduled-output-missing` Sentry event for the same fn; the
// marker alone means denied-then-complied (relabelled), which measurement
// line 1d also counts. Runbook: betterstack-log-query.md.
import pino from "pino";

const log = pino({ base: { component: "cron-filing-deny" } });

export interface CronFilingDenyMarker {
  /** The cron function id (`cronName`). */
  fn: string;
  /** Inngest run id when known, else the cron name. */
  run_id: string;
  /** ISO timestamp of the claude-eval spawn (correlates with the run's Sentry events). */
  spawn_started_at: string;
  /** Filing-shaped denials in this run's result event. */
  count: number;
  /** Command heads only — first three tokens per denied filing. */
  commands: string[];
}

// The two filing shapes the gate covers (mirrors `filingJustificationReason`
// in cron-bash-allowlist-hook.mjs): `gh issue create …` and
// `gh api …/repos/<o>/<r>/issues … -X POST` — anywhere in a segment chain.
const FILING_SHAPE =
  /(^|&&|\|\||;)\s*gh\s+(issue\s+create\b|api\s+\S*repos\/[^/\s]+\/[^/\s]+\/issues\b[^&|;]*(?:-X|--method)\s+POST\b)/;

/**
 * Count the filing-shaped Bash denials in a result event's `permission_denials`.
 * Pure; tolerant of a missing/malformed array (→ 0). Returns command heads
 * (first three whitespace tokens of the matching segment) for the marker.
 */
export function countFilingDenials(
  denials: unknown,
): { count: number; commands: string[] } {
  if (!Array.isArray(denials)) return { count: 0, commands: [] };
  const commands: string[] = [];
  for (const d of denials) {
    if (!d || typeof d !== "object") continue;
    const entry = d as { tool_name?: unknown; tool_input?: { command?: unknown } };
    if (entry.tool_name !== "Bash") continue;
    const cmd = entry.tool_input?.command;
    if (typeof cmd !== "string") continue;
    const m = FILING_SHAPE.exec(cmd);
    if (!m) continue;
    const segment = cmd.slice(m.index + m[1].length).trim();
    commands.push(segment.split(/\s+/).slice(0, 3).join(" "));
  }
  return { count: commands.length, commands };
}

/**
 * Emit one `SOLEUR_CRON_FILING_DENY` WARN marker. NEVER throws — observability
 * must never break a run. Emits nothing at count 0: this is a positive signal
 * for a deny that happened, not a per-run heartbeat.
 */
export function emitCronFilingDenyMarker(m: CronFilingDenyMarker): void {
  try {
    if (!(m.count > 0)) return;
    log.warn({ SOLEUR_CRON_FILING_DENY: true, ...m }, "cron filing denied");
  } catch {
    // fail-open: a marker-emit failure must never propagate into the caller.
  }
}
