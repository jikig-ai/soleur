// #7122 — the agent's PROMPT must only ask for commands the containment hook allows.
//
// The hook admits EXACT literals (each `;` / `&&` segment must equal one allow line
// token for token; only `<uint>` is variable). The prompt and the allow list live in two
// files and nothing else ties them: a prompt command the hook denies is a run that burns
// turns on denials, and a hook that quietly widened would never be noticed from the
// prompt side. So this suite extracts EVERY `bash ...` command the prompt asks for, as
// the agent would type it, and runs it through the REAL hook `decide()` over the lines
// the real builder delivers for this cron.
//
// The checks are functions over an injected `decide`, so the harness row runs the same
// checks against stub hooks and proves they can fail (an allow-all hook must be caught by
// the negatives; a deny-all hook by the positives).
import { describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { decide } from "../../../server/inngest/cron-bash-allowlist-hook.mjs";
import {
  buildAllowlistLines,
  COMMUNITY_ROUTER_READ_VERBS,
  CRON_BASH_ALLOWLISTS,
} from "../../../server/inngest/functions/_cron-claude-eval-substrate";
import { COMMUNITY_MONITOR_PROMPT } from "../../../server/inngest/functions/cron-community-monitor";

const CRON = "cron-community-monitor";
const ROUTER = "bash plugins/soleur/skills/community/scripts/community-router.sh";
const CHANNEL_ID = "123456789012345678";

type DecideFn = (input: unknown, lines: string[]) => { hookSpecificOutput: { permissionDecision: string } };

const lines = buildAllowlistLines(CRON, CRON_BASH_ALLOWLISTS[CRON] ?? [], {}).lines;
const verdict = (fn: DecideFn, command: string): string =>
  fn({ tool_name: "Bash", tool_input: { command } }, lines).hookSpecificOutput.permissionDecision;

/** Every backtick-delimited span of the (interpolated) prompt that is a bash command. */
function promptCommandSpans(prompt: string): string[] {
  return [...prompt.matchAll(/`([^`]*)`/g)].map((m) => m[1]).filter((c) => c.startsWith("bash "));
}

/** The command exactly as the agent would type it: the one placeholder replaced by a number. */
const typed = (span: string): string => span.replaceAll("<channel_id>", CHANNEL_ID);

/** Positive checks: every span, and every `;` segment of it, is allowed. Returns the failures. */
function deniedPromptCommands(fn: DecideFn): string[] {
  const failures: string[] = [];
  for (const span of promptCommandSpans(COMMUNITY_MONITOR_PROMPT)) {
    const command = typed(span);
    if (verdict(fn, command) !== "allow") failures.push(`span: ${command}`);
    for (const seg of command.split(";").map((x) => x.trim())) {
      if (verdict(fn, seg) !== "allow") failures.push(`segment: ${seg}`);
    }
  }
  return failures;
}

// Each negative is a one-token departure from a command the prompt really asks for.
const NEGATIVES: ReadonlyArray<[string, string]> = [
  ["a quoted hn query", `${ROUTER} hn mentions --query "soleur" --limit 20`],
  ["a single-quoted hn query", `${ROUTER} hn mentions --query 'soleur' --limit 20`],
  ["a different hn query (egress channel)", `${ROUTER} hn mentions --query anything --limit 20`],
  ["a different hn limit", `${ROUTER} hn mentions --query soleur --limit 21`],
  ["a pipe", `${ROUTER} platforms | head`],
  ["a pipe on a chained segment", `${ROUTER} github repo-stats 1; ${ROUTER} github activity 1 | head -c 100`],
  ["a redirect", `${ROUTER} x fetch-metrics > /tmp/out`],
  ["an extra trailing token", `${ROUTER} x fetch-metrics --verbose`],
  ["an extra trailing token after a numeric argument", `${ROUTER} github activity 1 extra`],
  ["a different github day count", `${ROUTER} github activity 7`],
  ["a different discord message limit", `${ROUTER} discord messages ${CHANNEL_ID} 100`],
  ["a non-numeric discord channel id", `${ROUTER} discord messages abc 50`],
  ["a discord channel id carrying a substitution", `${ROUTER} discord messages $(id) 50`],
  ["a discord messages call without its limit", `${ROUTER} discord messages ${CHANNEL_ID}`],
  ["an extra token after the discord limit", `${ROUTER} discord messages ${CHANNEL_ID} 50 extra`],
  ["the dropped linkedin fetch-activity verb", `${ROUTER} linkedin fetch-activity`],
  ["the dropped discord members verb", `${ROUTER} discord members`],
  ["the dropped hn trending verb", `${ROUTER} hn trending --limit 20`],
  ["a posting verb", `${ROUTER} bsky post hello`],
  ["the bare router (no verb)", ROUTER],
  ["two commands split by a newline", `${ROUTER} platforms\n${ROUTER} x fetch-metrics`],
];

function allowedNegatives(fn: DecideFn): string[] {
  return NEGATIVES.filter(([, command]) => verdict(fn, command) !== "deny").map(([label]) => label);
}

describe("the prompt's commands vs the REAL hook grammar (#7122)", () => {
  it("extracts the router invocations the prompt asks for (non-vacuity: a missed extraction cannot pass)", () => {
    const spans = promptCommandSpans(COMMUNITY_MONITOR_PROMPT);
    // platforms, discord x3, x, bsky, linkedin, github (one chained call), hn
    expect(spans.length).toBeGreaterThanOrEqual(9);
    expect(spans.every((s) => s.startsWith(ROUTER))).toBe(true);
    // The GitHub call chains five segments; the rest are single commands.
    expect(spans.some((s) => s.split(";").length === 5)).toBe(true);
    // EVERY occurrence of the router path in the prompt sits inside such a span (no stray
    // unquoted `bash <router>` the extraction would miss).
    const occurrences = COMMUNITY_MONITOR_PROMPT.split(ROUTER).length - 1;
    const inSpans = spans.reduce((n, s) => n + (s.split(ROUTER).length - 1), 0);
    expect(inSpans).toBe(occurrences);
    // One line per call.
    for (const s of spans) expect(s, s).not.toMatch(/[\r\n]/);
  });

  it("every command the prompt asks for (and every `;` segment of it) is ALLOWED by the real hook", () => {
    expect(deniedPromptCommands(decide as DecideFn)).toEqual([]);
  });

  it("the prompt exercises EXACTLY the hook's allow lines: no allowed command is unused and none is missing", () => {
    const normalised = new Set(
      promptCommandSpans(COMMUNITY_MONITOR_PROMPT).flatMap((span) =>
        span.split(";").map((seg) => seg.trim().replace(/<channel_id>/g, "<uint>")),
      ),
    );
    expect([...normalised].sort()).toEqual([...COMMUNITY_ROUTER_READ_VERBS].sort());
  });

  it("a one-token departure from any of them is DENIED: quoting the hn query, a pipe, a redirect, an extra token, a different number, a dropped verb", () => {
    expect(allowedNegatives(decide as DecideFn)).toEqual([]);
  });

  it("harness: the checks FAIL against a hook that allows everything, and against one that denies everything", () => {
    const allowAll: DecideFn = () => ({ hookSpecificOutput: { permissionDecision: "allow" } });
    const denyAll: DecideFn = () => ({ hookSpecificOutput: { permissionDecision: "deny" } });
    // allow-all: every negative slips through
    expect(allowedNegatives(allowAll)).toHaveLength(NEGATIVES.length);
    // deny-all: the positives are all caught
    expect(deniedPromptCommands(denyAll).length).toBeGreaterThanOrEqual(2 * promptCommandSpans(COMMUNITY_MONITOR_PROMPT).length);
  });

  it("the extraction is live: a prompt that asked for a lookalike would be caught", () => {
    const bad = `${COMMUNITY_MONITOR_PROMPT}\n\`${ROUTER} hn mentions --query "soleur" --limit 20\` and \`${ROUTER} linkedin fetch-activity\``;
    const denied = promptCommandSpans(bad)
      .map(typed)
      .filter((c) => verdict(decide as DecideFn, c) !== "allow");
    expect(denied).toEqual([
      `${ROUTER} hn mentions --query "soleur" --limit 20`,
      `${ROUTER} linkedin fetch-activity`,
    ]);
  });
});
