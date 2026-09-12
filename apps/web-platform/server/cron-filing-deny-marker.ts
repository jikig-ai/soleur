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
// carries the command HEAD (`gh issue create`, or `gh api <endpoint path>`
// with the query string dropped and the path capped), never a title, body,
// or label value. "Denied and did not comply" is this marker plus
// the existing `scheduled-output-missing` Sentry event for the same fn; the
// marker alone means denied-then-complied (relabelled), which measurement
// line 1d also counts. Runbook: betterstack-log-query.md.
import pino from "pino";
import {
  filingShape,
  splitSegments,
  tokenize,
} from "./inngest/cron-bash-allowlist-hook.mjs";

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
  /** Command heads only — `gh issue create` / `gh api <path>` per denied filing. */
  commands: string[];
  /**
   * `ok`: the result event carried `permission_denials[]`. `field-absent`:
   * it parsed but the array was missing — the deny channel is dark, so a 0
   * count is not "no denials". Emitted at count 0 only in that case.
   */
  capture_status: "ok" | "field-absent";
}

// ONE predicate for "is this a filing": the hook's own `filingShape` over the
// hook's own tokenizer, so what the gate denies and what this counts cannot
// drift (a hand-mirrored regex here missed `gh api -X POST repos/…/issues`
// and `-f title=` without a method — #8074 review). The hook file is plain
// ESM with a CLI entry guard, so importing it runs nothing.

// The api form's endpoint token is agent-controlled and unbounded (a 5 kB
// `…/issues?title=…` is a valid token), so the head is the PATH ONLY — query
// string dropped — and capped. `gh issue create` is always its three literals.
const HEAD_TOKEN_MAX = 64;
const ENDPOINT_RE = /(^|\/)repos\/[^/?]+\/[^/?]+\/issues\/?(\?[^/]*)?$/;

/** The command head for one denied filing segment: `gh issue create` or `gh api <path>`. */
function filingHead(tokens: string[], shape: "create" | "api"): string {
  if (shape === "create") return "gh issue create";
  const endpoint = tokens.find((t) => ENDPOINT_RE.test(t)) ?? "";
  const path = endpoint.split("?")[0].slice(0, HEAD_TOKEN_MAX);
  return `gh api ${path}`;
}

/**
 * Count the filing-shaped Bash denials in a result event's `permission_denials`.
 * Pure; tolerant of a missing/malformed array (→ 0). One count per denied
 * command carrying a filing segment (any position in a `&&`/`||`/`;` chain);
 * the head of its first filing segment goes into `commands`; a segment the hook
 * refused for an unbalanced quote is still counted by its verbs. NOTE: the array
 * carries no deny REASON, so a filing-shaped command denied for another
 * cause (a metachar, an allowlist miss) is counted too — the marker measures
 * "a filing was refused", not "the filing gate refused it".
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
    for (const segment of splitSegments(cmd)) {
      // A segment the hook could not tokenize (unbalanced quote — the FR7
      // apostrophe shape) was STILL a refused filing if its verbs say so; fall
      // back to a whitespace split for shape detection only, never for values.
      const tokens = (tokenize(segment) as string[] | null) ?? segment.trim().split(/\s+/);
      const shape = filingShape(tokens) as "create" | "api" | null;
      if (shape === null) continue;
      commands.push(filingHead(tokens, shape));
      break;
    }
  }
  return { count: commands.length, commands };
}

/**
 * Emit one `SOLEUR_CRON_FILING_DENY` WARN marker. NEVER throws — observability
 * must never break a run. Emits nothing at count 0 with a healthy capture:
 * this is a positive signal for a deny that happened (or for a deny channel
 * that went dark), not a per-run heartbeat.
 */
export function emitCronFilingDenyMarker(m: CronFilingDenyMarker): void {
  try {
    if (!(m.count > 0) && m.capture_status === "ok") return;
    log.warn({ SOLEUR_CRON_FILING_DENY: true, ...m }, "cron filing denied");
  } catch {
    // fail-open: a marker-emit failure must never propagate into the caller.
  }
}
