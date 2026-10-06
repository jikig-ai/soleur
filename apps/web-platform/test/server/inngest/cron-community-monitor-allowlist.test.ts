// #7122 Guard 2 — containment closure for cron-community-monitor (plan
// 2026-10-06-fix-community-monitor-output-allowlist, Phase 3).
//
// The spawned agent may collect and classify; it may not publish. Three layers
// are asserted here, all through the REAL hook's pure `decide()`:
//   1. the Bash surface is exactly the thirteen read invocations of the community
//      router, each an EXACT LITERAL (`<uint>` is the only variable token): no gh verb, no
//      bare router prefix, no posting verb, no trailing or altered argument;
//   2. the `no-file-tools` directive removes the write primitive (an agent that can
//      `Write` over the allowlisted router script and then run it executes
//      model-authored shell with the whole spawn env) AND the read primitives that
//      a deny-list could not close (`Grep{path:"/",glob:"proc/*/environ"}`);
//   3. the argv the handler builds (`--disallowedTools`) and the spawn env.
//
// `lines` is ALWAYS the output of buildAllowlistLines("cron-community-monitor", …)
// and never the raw CRON_BASH_ALLOWLISTS array: feeding the raw array would stay
// green with CRON_NO_FILE_TOOLS emptied, because the directive is produced only by
// the builder. This file reads plugins/soleur/skills/community/scripts/*.sh, so it
// is registered in test/repo-wide-suites.ts.
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { gitFixtureEnv } from "../../../../../plugins/soleur/test/lib/git-fixture-env";
import { decide } from "../../../server/inngest/cron-bash-allowlist-hook.mjs";
import { buildAuthenticatedCloneUrl } from "../../../server/inngest/functions/_cron-shared";
import {
  buildAllowlistLines,
  COMMUNITY_DISALLOWED_TOOLS,
  COMMUNITY_ROUTER_READ_VERBS,
  CRON_BASH_ALLOWLISTS,
  CRON_NO_FILE_TOOLS,
  setOriginToken,
} from "../../../server/inngest/functions/_cron-claude-eval-substrate";

const CRON = "cron-community-monitor";
const OTHER_CRON = "cron-seo-aeo-audit";
const ROUTER = "bash plugins/soleur/skills/community/scripts/community-router.sh";
const SCRIPTS_DIR = join(__dirname, "../../../../../plugins/soleur/skills/community/scripts");
const HANDLER_SRC = readFileSync(
  join(__dirname, "../../../server/inngest/functions/cron-community-monitor.ts"),
  "utf-8",
);

type DecideFn = (input: unknown, lines: string[]) => { hookSpecificOutput: { permissionDecision: string } };

const linesFor = (cron: string): string[] =>
  buildAllowlistLines(cron, CRON_BASH_ALLOWLISTS[cron] ?? [], {}).lines;
const verdictWith = (fn: DecideFn, lines: string[], input: unknown): string =>
  fn(input, lines).hookSpecificOutput.permissionDecision;
const bash = (command: string) => ({ tool_name: "Bash", tool_input: { command } });
// A real operand for the `<uint>` placeholder (a Discord snowflake is 17-19 digits).
const withNumbers = (literal: string) => literal.replaceAll("<uint>", "123456789012345678");

const FILE_TOOLS = ["Read", "Glob", "Grep", "Write", "Edit", "MultiEdit", "Task", "Agent", "Skill"] as const;

// Every probe the suite asserts, as data, so the harness row (G2-9) can run the
// SAME list against a hook that allows everything and require that it fails.
// Each entry is `[label, input, expected verdict]` for the community cron's lines.
const COMMUNITY_PROBES: ReadonlyArray<[string, unknown, "allow" | "deny"]> = [
  ["gh issue create", bash(`gh issue create --title t --label scheduled-community-monitor --body-file /tmp/b.md`), "deny"],
  ["gh issue comment", bash("gh issue comment 1 --body-file /tmp/b.md"), "deny"],
  ["gh label create", bash("gh label create x --color ffffff"), "deny"],
  ["gh issue list --jq env", bash("gh issue list --json number --jq env"), "deny"],
  ["bsky post", bash(`${ROUTER} bsky post hello`), "deny"],
  ["linkedin post-content", bash(`${ROUTER} linkedin post-content --text hello`), "deny"],
  ["x post-tweet", bash(`${ROUTER} x post-tweet hello`), "deny"],
  ["bare router prefix", bash(`${ROUTER} bsky create-session`), "deny"],
  ["redirection over the router", bash(`${ROUTER} platforms > plugins/soleur/skills/community/scripts/community-router.sh`), "deny"],
  ...FILE_TOOLS.map(
    (t): [string, unknown, "allow" | "deny"] => [
      `${t} (no-file-tools)`,
      { tool_name: t, tool_input: { file_path: "knowledge-base/x.md", path: "knowledge-base", pattern: "x" } },
      "deny",
    ],
  ),
  ["Write over the router", { tool_name: "Write", tool_input: { file_path: "plugins/soleur/skills/community/scripts/community-router.sh", content: "x" } }, "deny"],
  ["Grep /proc environ", { tool_name: "Grep", tool_input: { pattern: "KEY", path: "/", glob: "proc/*/environ" } }, "deny"],
  ["Glob .git/config via /tmp", { tool_name: "Glob", tool_input: { pattern: "**/.git/config", path: "/tmp" } }, "deny"],
  ["Grep /pro*", { tool_name: "Grep", tool_input: { pattern: "KEY", path: "/pro*" } }, "deny"],
  ["NotebookEdit", { tool_name: "NotebookEdit", tool_input: { notebook_path: "x.ipynb" } }, "deny"],
  // P1-A: the trailing argument of an ADMITTED verb (verified exploit shapes).
  ["discord messages: arithmetic-context payload", bash(`${ROUTER} discord messages 'HOME[$(cat .git/config /proc/self/environ >&2)]'`), "deny"],
  ["discord messages: payload after the channel id", bash(`${ROUTER} discord messages 123 'HOME[$(id)]'`), "deny"],
  ["hn mentions: python-source breakout", bash(`${ROUTER} hn mentions --query "x'+str(__import__('os').system('id'))+'"`), "deny"],
  ["hn mentions: single-quoted substitution", bash(`${ROUTER} hn mentions --query 'x$(id)'`), "deny"],
  ["github activity: unquoted bracket token", bash(`${ROUTER} github activity HOME[1]`), "deny"],
  // P1-A': verbs removed from the read surface.
  ["discord members (removed)", bash(`${ROUTER} discord members`), "deny"],
  ["hn trending (removed)", bash(`${ROUTER} hn trending --limit 30`), "deny"],
  ["linkedin fetch-activity (removed)", bash(`${ROUTER} linkedin fetch-activity`), "deny"],
  // Round-1 residual: exact literals. A different --query word was a free-text channel to a
  // third-party search API; a trailing token and a leading-zero operand are the other shapes.
  ["hn mentions: a different --query word", bash(`${ROUTER} hn mentions --query other --limit 20`), "deny"],
  ["platforms: an extra trailing token", bash(`${ROUTER} platforms extra`), "deny"],
  ["discord messages: an extra trailing token", bash(`${ROUTER} discord messages 1 50 extra`), "deny"],
  ["discord messages: a leading-zero operand", bash(`${ROUTER} discord messages 08 50`), "deny"],
  ["discord messages: a different limit", bash(`${ROUTER} discord messages 1 100`), "deny"],
  ["router platforms", bash(`${ROUTER} platforms`), "allow"],
  ["hn mentions with the prompt's own arguments", bash(`${ROUTER} hn mentions --query soleur --limit 20`), "allow"],
  ["discord messages with the prompt's own arguments", bash(`${ROUTER} discord messages 123456789012345678 50`), "allow"],
];

function failedProbes(fn: DecideFn, lines: string[]): string[] {
  return COMMUNITY_PROBES.filter(([, input, want]) => verdictWith(fn, lines, input) !== want).map(([label]) => label);
}

describe("cron-community-monitor allowlist closure (#7122 Guard 2)", () => {
  const lines = linesFor(CRON);

  it("G2-1: no gh verb of any kind survives in the community allowlist (create/comment/list/label)", () => {
    expect(COMMUNITY_ROUTER_READ_VERBS.length).toBe(13);
    expect(CRON_BASH_ALLOWLISTS[CRON]).toEqual([...COMMUNITY_ROUTER_READ_VERBS]);
    expect(lines.filter((l) => /^gh\b/.test(l))).toEqual([]);
    for (const verb of ["gh issue create", "gh issue comment", "gh label create", "gh label list", "gh issue list"]) {
      expect(lines, `${verb} must not be in the delivered allow file`).not.toContain(verb);
    }
    expect(verdictWith(decide, lines, bash("gh issue create --title t --label scheduled-community-monitor"))).toBe("deny");
    expect(verdictWith(decide, lines, bash("gh issue comment 1 --body x"))).toBe("deny");
    expect(verdictWith(decide, lines, bash("gh label create x"))).toBe("deny");
    expect(verdictWith(decide, lines, bash("gh issue list --label scheduled-community-monitor"))).toBe("deny");
    // No run-report directive either: the handler files the issue, not the agent.
    expect(lines.some((l) => l.startsWith("run-report-label"))).toBe(false);
  });

  it("G2-2: the bare router prefix is gone — every allow line is a full `<router> <platform> <verb> [fixed args]` literal and posting verbs are denied", () => {
    const bashLines = lines.filter((l) => l.startsWith("bash "));
    expect(bashLines).toEqual([...COMMUNITY_ROUTER_READ_VERBS]);
    expect(bashLines).not.toContain(ROUTER);
    // allow[0] is executed verbatim by runHookSelfTest: it must be a whole command that runs.
    expect(COMMUNITY_ROUTER_READ_VERBS[0]).toBe(`${ROUTER} platforms`);
    expect(COMMUNITY_ROUTER_READ_VERBS[0]).not.toContain("<uint>");
    // The grammar of a literal: the router, a platform, a verb, then fixed arguments; `<uint>` is the only placeholder.
    for (const l of COMMUNITY_ROUTER_READ_VERBS) {
      expect(l).toMatch(/^bash plugins\/soleur\/skills\/community\/scripts\/community-router\.sh [a-z-]+( [a-z-]+( ([A-Za-z0-9<>-]+))*)?$/);
      expect(l.match(/<[^>]*>/g) ?? []).toEqual(l.includes("<uint>") ? ["<uint>"] : []);
    }
    expect(verdictWith(decide, lines, bash(`${ROUTER} bsky post "hello"`))).toBe("deny");
    expect(verdictWith(decide, lines, bash(`${ROUTER} linkedin post-content --text hello`))).toBe("deny");
    expect(verdictWith(decide, lines, bash(`${ROUTER} x post-tweet hello`))).toBe("deny");
    expect(verdictWith(decide, lines, bash(`${ROUTER} bsky create-session`))).toBe("deny");
    expect(verdictWith(decide, lines, bash(`${ROUTER} x fetch-mentions`))).toBe("deny");
    expect(verdictWith(decide, lines, bash(`${ROUTER} discord guild-infox`))).toBe("deny");
    // A redirection over the router itself dies on the metachar layer.
    expect(
      verdictWith(decide, lines, bash(`${ROUTER} platforms > plugins/soleur/skills/community/scripts/community-router.sh`)),
    ).toBe("deny");
    // Exact-literal semantics: the arguments the prompt uses are allowed, ANY other argument is not.
    expect(verdictWith(decide, lines, bash(`${ROUTER} hn mentions --query soleur --limit 20`))).toBe("allow");
    expect(verdictWith(decide, lines, bash(`${ROUTER} github activity 1`))).toBe("allow");
    expect(verdictWith(decide, lines, bash(`${ROUTER} discord messages 123456789012345678 50`))).toBe("allow");
    expect(verdictWith(decide, lines, bash(`${ROUTER} discord messages 123456789012345678`))).toBe("deny");
    expect(verdictWith(decide, lines, bash(`${ROUTER} github activity 7`))).toBe("deny");
    expect(verdictWith(decide, lines, bash(`${ROUTER} hn mentions --query soleur --limit 30`))).toBe("deny");
  });

  it("G2-3: EVERY member is judged — all thirteen read literals allow (with a real number for `<uint>`) and every posting or removed verb denies (a first-member-only check is the defect)", () => {
    expect(new Set(COMMUNITY_ROUTER_READ_VERBS).size).toBe(13);
    // The exact membership, as data: an added or dropped verb is a deliberate edit here.
    expect([...COMMUNITY_ROUTER_READ_VERBS].map((l) => l.slice(ROUTER.length + 1))).toEqual([
      "platforms",
      "discord guild-info",
      "discord channels",
      "discord messages <uint> 50",
      "x fetch-metrics",
      "bsky get-metrics",
      "linkedin fetch-metrics",
      "github activity 1",
      "github contributors 1",
      "github discussions 1",
      "github repo-stats 1",
      "github fetch-interactions 1",
      "hn mentions --query soleur --limit 20",
    ]);
    // Removed: `discord members` returns up to 1000 member objects (the count comes from
    // guild-info's approximate count), `hn trending` and `linkedin fetch-activity` feed no
    // schema field.
    for (const removed of ["discord members", "hn trending", "linkedin fetch-activity"]) {
      expect(COMMUNITY_ROUTER_READ_VERBS.some((l) => l.startsWith(`${ROUTER} ${removed}`)), removed).toBe(false);
      expect(verdictWith(decide, lines, bash(`${ROUTER} ${removed}`)), removed).toBe("deny");
      expect(verdictWith(decide, lines, bash(`${ROUTER} ${removed} 100`)), `${removed} 100`).toBe("deny");
    }
    // The real hook's decide() over EVERY literal, `<uint>` replaced by a real number: a
    // line the grammar rejects (a typo in the list, a placeholder it cannot match) would
    // make the cron's own collector fail at runtime, every day.
    for (const verb of COMMUNITY_ROUTER_READ_VERBS) {
      const cmd = withNumbers(verb);
      expect(verdictWith(decide, lines, bash(cmd)), cmd).toBe("allow");
      // ...and each is EXACT: one extra token, or a missing last token, denies.
      expect(verdictWith(decide, lines, bash(`${cmd} extra`)), `${cmd} extra`).toBe("deny");
      if (verb.slice(ROUTER.length + 1).split(" ").length > 2) {
        const dropped = cmd.split(" ").slice(0, -1).join(" ");
        expect(verdictWith(decide, lines, bash(dropped)), dropped).toBe("deny");
      }
    }
    // A literal containing `<uint>` also takes the boundary values of the placeholder.
    for (const operand of ["0", "7", "123456789012345678"]) {
      expect(verdictWith(decide, lines, bash(`${ROUTER} discord messages ${operand} 50`)), operand).toBe("allow");
    }
    for (const operand of ["08", "00", "-1", "+1", "1.5", "1e3", "0x1", "", "1a"]) {
      expect(verdictWith(decide, lines, bash(`${ROUTER} discord messages ${operand} 50`)), `operand ${JSON.stringify(operand)}`).toBe("deny");
    }
    const POSTING = ["bsky post x", "linkedin post-content --text x", "x post-tweet x"];
    for (const p of POSTING) expect(verdictWith(decide, lines, bash(`${ROUTER} ${p}`)), p).toBe("deny");
    // The allow list contains none of the posting subcommands as a whole token.
    for (const l of COMMUNITY_ROUTER_READ_VERBS) expect(l).not.toMatch(/\b(post|post-tweet|post-content|create-session)\b/);
  });

  it("G2-4: with the no-file-tools directive every file/sub-agent tool is denied — and the directive is per-cron, not global", () => {
    expect(CRON_NO_FILE_TOOLS).toEqual([CRON]);
    expect(lines).toContain("no-file-tools");
    for (const t of FILE_TOOLS) {
      expect(
        verdictWith(decide, lines, { tool_name: t, tool_input: { file_path: "knowledge-base/x.md", path: "knowledge-base", pattern: "x" } }),
        `${t} must be denied for ${CRON}`,
      ).toBe("deny");
    }
    // The allowlisted router script is exactly what a Write would overwrite.
    expect(
      verdictWith(decide, lines, {
        tool_name: "Write",
        tool_input: { file_path: "plugins/soleur/skills/community/scripts/community-router.sh", content: "echo pwned" },
      }),
    ).toBe("deny");
    // NotebookEdit already hits the hook's catch-all deny, with or without the
    // directive: `--disallowedTools` is the only layer that distinguishes it.
    const noDirective = lines.filter((l) => l !== "no-file-tools");
    const nb = { tool_name: "NotebookEdit", tool_input: { notebook_path: "x.ipynb" } };
    expect(verdictWith(decide, lines, nb)).toBe("deny");
    expect(verdictWith(decide, noDirective, nb)).toBe("deny");
    // ...and the same nine tools are ALLOWED for a cron without the directive.
    const other = linesFor(OTHER_CRON);
    expect(other).not.toContain("no-file-tools");
    for (const t of FILE_TOOLS) {
      expect(
        verdictWith(decide, other, { tool_name: t, tool_input: { file_path: "knowledge-base/x.md", path: "knowledge-base", pattern: "x" } }),
        `${t} must stay allowed for ${OTHER_CRON}`,
      ).toBe("allow");
    }
  });

  it("G2-4b: `gh issue list --json number --jq env` (an env dump the hook cannot see through) is denied because the verb is absent", () => {
    expect(verdictWith(decide, lines, bash("gh issue list --json number --jq env"))).toBe("deny");
    expect(verdictWith(decide, lines, bash("gh issue list --json number --jq 'env'"))).toBe("deny");
    // Control: the same command IS allowed where the verb is granted, so the deny
    // above is attributable to the removed verb and not to a metachar.
    expect(verdictWith(decide, linesFor(OTHER_CRON), bash("gh issue list --json number --jq env"))).toBe("allow");
  });

  it("G2-4c: the reproduced Read/Glob/Grep bypasses are denied by ABSENCE of the tools, not by a deny-list match", () => {
    for (const input of [
      { tool_name: "Grep", tool_input: { pattern: "KEY", path: "/", glob: "proc/*/environ" } },
      { tool_name: "Glob", tool_input: { pattern: "**/.git/config", path: "/tmp" } },
      { tool_name: "Grep", tool_input: { pattern: "KEY", path: "/pro*" } },
    ]) {
      expect(verdictWith(decide, lines, input)).toBe("deny");
    }
    // Control: without the directive these are exactly the probes the path
    // deny-list FAILS to catch (the reason the directive exists).
    const noDirective = lines.filter((l) => l !== "no-file-tools");
    expect(verdictWith(decide, noDirective, { tool_name: "Grep", tool_input: { pattern: "KEY", path: "/", glob: "proc/*/environ" } })).toBe("allow");
    expect(verdictWith(decide, noDirective, { tool_name: "Glob", tool_input: { pattern: "**/.git/config", path: "/tmp" } })).toBe("allow");
    expect(verdictWith(decide, noDirective, { tool_name: "Grep", tool_input: { pattern: "KEY", path: "/pro*" } })).toBe("allow");
  });

  it("G2-5: the spawn pool drops the file tools (--disallowedTools) and --allowedTools is Bash only", () => {
    expect(COMMUNITY_DISALLOWED_TOOLS).toBe("Read,Glob,Grep,Write,Edit,MultiEdit,NotebookEdit,Task,Agent,Skill");
    // The two layers must name the same nine hook-denied tools (+ NotebookEdit).
    for (const t of FILE_TOOLS) expect(COMMUNITY_DISALLOWED_TOOLS.split(",")).toContain(t);
    // Source checks on the handler (a handler import would pull the whole static
    // graph into this suite). RED until the handler's flags adopt the constant.
    // Boolean form: a failed toMatch would dump the whole handler source into the report.
    expect(
      /"--disallowedTools",\s*COMMUNITY_DISALLOWED_TOOLS/.test(HANDLER_SRC),
      "handler CLAUDE_CODE_FLAGS must pass --disallowedTools COMMUNITY_DISALLOWED_TOOLS",
    ).toBe(true);
    expect(
      /"--allowedTools",\s*"Bash",/.test(HANDLER_SRC),
      'handler CLAUDE_CODE_FLAGS must pass --allowedTools "Bash"',
    ).toBe(true);
  });

  it("G2-6/G2-7: credential custody is asserted in the flow suite; here, the webhook secret is not in the handler's spawn env", () => {
    // G2-6 (token passed to setupEphemeralWorkspace is the READ token) lives in
    // cron-community-monitor-publication-flow.test.ts. G2-7: DISCORD_WEBHOOK_URL has
    // no read-path consumer, so it must not be forwarded to the child.
    const code = HANDLER_SRC.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
    expect(code).not.toContain("DISCORD_WEBHOOK_URL");
  });

  it("G2-8: every community-router.sh command in COMMUNITY_MONITOR_PROMPT passes the REAL hook with the delivered lines, and the prompt uses every literal (prompt parity, arguments included)", () => {
    const start = HANDLER_SRC.indexOf("const COMMUNITY_MONITOR_PROMPT");
    expect(start, "COMMUNITY_MONITOR_PROMPT not found in the handler source").toBeGreaterThan(-1);
    const end = HANDLER_SRC.indexOf("`;", HANDLER_SRC.indexOf("`", start) + 1);
    const prompt = HANDLER_SRC.slice(start, end);
    // Every backtick-quoted span that invokes the router. In the handler source the prompt's
    // backticks are escaped (\`), and the only placeholder the prompt carries is <channel_id>.
    const spans = [...prompt.matchAll(/\\`(bash plugins\/soleur\/skills\/community\/scripts\/community-router\.sh[^`\\]*)\\`/g)].map((m) => m[1]);
    // Non-vacuity: the prompt's collection steps name the platform probe and the three Discord, X,
    // Bluesky, LinkedIn, five GitHub and HN collectors (one span carries the five GitHub ones).
    expect(spans.length).toBeGreaterThanOrEqual(9);
    const commands = spans.flatMap((span) => span.split(/;|&&/).map((c) => c.trim()).filter(Boolean));
    expect(commands.length).toBeGreaterThanOrEqual(13);
    const seen = new Set<string>();
    for (const raw of commands) {
      expect(raw, "a prompt command with a stray quote, brace or shell metacharacter").toMatch(/^[A-Za-z0-9._:=@/+<>_ -]+$/);
      // The prompt's placeholder is a snowflake the model reads from the channels output.
      const asRun = raw.replaceAll("<channel_id>", "123456789012345678");
      expect(verdictWith(decide, lines, bash(asRun)), `the prompt tells the agent to run \`${raw}\`, which the real hook denies`).toBe("allow");
      seen.add(raw.replaceAll("<channel_id>", "<uint>"));
    }
    // And the whole span, as the agent would send it (a `;` chain of collectors).
    for (const span of spans) expect(verdictWith(decide, lines, bash(span.replaceAll("<channel_id>", "123456789012345678"))), span).toBe("allow");
    // The allowlist is not wider than the prompt: a literal the prompt never runs is dead surface.
    expect([...seen].sort()).toEqual([...COMMUNITY_ROUTER_READ_VERBS].sort());
  });

  it("G2-9: harness — the probe list FAILS against a hook that allows everything, and passes against the real one", () => {
    const allowAll: DecideFn = () => ({ hookSpecificOutput: { permissionDecision: "allow" } });
    const denyAll: DecideFn = () => ({ hookSpecificOutput: { permissionDecision: "deny" } });
    const realFailures = failedProbes(decide as DecideFn, lines);
    expect(realFailures).toEqual([]);
    const allowAllFailures = failedProbes(allowAll, lines);
    // Every deny probe is caught (all but the allow controls).
    expect(allowAllFailures.length).toBe(COMMUNITY_PROBES.filter(([, , w]) => w === "deny").length);
    expect(allowAllFailures.length).toBeGreaterThanOrEqual(15);
    // And a deny-everything stub is caught by the allow control (the suite cannot go green on a hook that blocks all).
    expect(failedProbes(denyAll, lines)).toEqual(
      COMMUNITY_PROBES.filter(([, , w]) => w === "allow").map(([label]) => label),
    );
    expect(COMMUNITY_PROBES.filter(([, , w]) => w === "allow").length).toBeGreaterThanOrEqual(2);
  });

  it("G2-11: the argument grammar is what denies a hostile trailing argument, through the REAL delivered lines — and the same payload is allowed once the directive is removed (prefix semantics)", () => {
    const hostile = [
      `${ROUTER} discord messages 'HOME[$(cat .git/config /proc/self/environ >&2)]'`,
      `${ROUTER} hn mentions --query "x'+str(__import__('os').system('id'))+'"`,
      `${ROUTER} github activity 1 'a b'`,
    ];
    // The pre-#7122 shape: the verb PREFIXES (no placeholder, no fixed arguments), no directive.
    const prefixOnly = COMMUNITY_ROUTER_READ_VERBS.map((l) => l.split(" ").slice(0, 4).join(" "));
    for (const h of hostile) {
      expect(verdictWith(decide, lines, bash(h)), h).toBe("deny");
      // Control: the verb prefix alone admits it, which is the hole the grammar closes.
      expect(verdictWith(decide, prefixOnly, bash(h)), `control ${h}`).toBe("allow");
    }
    // Every one of the thirteen literals, invoked with a real number for the placeholder.
    for (const verb of COMMUNITY_ROUTER_READ_VERBS) {
      expect(verdictWith(decide, lines, bash(withNumbers(verb))), verb).toBe("allow");
    }
  });

  it("G2-12: literal matching is CASE-SENSITIVE — an upper-cased verb, platform or router path is not the allowlisted literal", () => {
    for (const cmd of [
      `${ROUTER} PLATFORMS`,
      `${ROUTER} Discord guild-info`,
      `${ROUTER} hn mentions --query SOLEUR --limit 20`,
      ROUTER.toUpperCase() + " platforms",
    ]) {
      expect(verdictWith(decide, lines, bash(cmd)), cmd).toBe("deny");
    }
    expect(verdictWith(decide, lines, bash(`${ROUTER} platforms`))).toBe("allow");
  });

  it("G2-10 (must PASS): chained `;` and `&&` literals allow, every segment position is judged, and a cron WITHOUT the directive is unaffected", () => {
    expect(
      verdictWith(decide, lines, bash(`${ROUTER} github fetch-interactions 1; ${ROUTER} hn mentions --query soleur --limit 20`)),
    ).toBe("allow");
    expect(
      verdictWith(
        decide,
        lines,
        bash(
          `${ROUTER} discord guild-info; ${ROUTER} discord channels; ${ROUTER} x fetch-metrics; ${ROUTER} bsky get-metrics; ${ROUTER} linkedin fetch-metrics`,
        ),
      ),
    ).toBe("allow");
    // The prompt's whole GitHub batch is one command of five literals.
    expect(
      verdictWith(
        decide,
        lines,
        bash(["repo-stats", "activity", "contributors", "discussions", "fetch-interactions"].map((v) => `${ROUTER} github ${v} 1`).join("; ")),
      ),
    ).toBe("allow");
    // One bad segment poisons the whole command, in ANY position.
    for (const bad of [`${ROUTER} bsky post x`, `${ROUTER} hn mentions --query other --limit 20`, `${ROUTER} platforms extra`]) {
      const ok = `${ROUTER} platforms`;
      for (const cmd of [`${bad}; ${ok}; ${ok}`, `${ok}; ${bad}; ${ok}`, `${ok}; ${ok}; ${bad}`, `${ok} && ${bad} && ${ok}`]) {
        expect(verdictWith(decide, lines, bash(cmd)), cmd).toBe("deny");
      }
    }
    // A different cron keeps its own Bash surface and its tools.
    const other = linesFor(OTHER_CRON);
    expect(
      verdictWith(
        decide,
        other,
        bash(`gh issue create --milestone "Post-MVP / Later" --title "[Scheduled] x" --label scheduled-seo-aeo-audit --body-file /tmp/b.md`),
      ),
    ).toBe("allow");
    expect(verdictWith(decide, other, { tool_name: "Write", tool_input: { file_path: "knowledge-base/x.md", content: "x" } })).toBe("allow");
    expect(verdictWith(decide, other, { tool_name: "Skill", tool_input: {} })).toBe("allow");
  });
});

describe("community router scripts — posting verbs and secret-echo guards (source tests, #7122 anchor)", () => {
  // The posting verbs and the *_ALLOW_POST guards live OUTSIDE the files this
  // change edits; if one is renamed the DENY rows above would pass vacuously. A
  // removed verb must be removed from the test deliberately.
  const scripts = readdirSync(SCRIPTS_DIR).filter((f) => f.endsWith("-community.sh") || f === "community-router.sh");
  const read = (f: string) => readFileSync(join(SCRIPTS_DIR, f), "utf-8");

  it("the three posting subcommands still exist in the platform scripts (non-empty match count)", () => {
    const hits: string[] = [];
    for (const [file, re] of [
      ["bsky-community.sh", /^\s*post\)\s/m],
      ["linkedin-community.sh", /^\s*post-content\)/m],
      ["x-community.sh", /^\s*post-tweet\)\s/m],
    ] as const) {
      if (re.test(read(file))) hits.push(file);
    }
    expect(hits.sort()).toEqual(["bsky-community.sh", "linkedin-community.sh", "x-community.sh"]);
    expect(scripts.length).toBeGreaterThanOrEqual(7);
  });

  it("no router script can print its own environment: no printenv, bare `env`, `set -x` or `declare -p`", () => {
    expect(scripts).toContain("community-router.sh");
    for (const f of scripts) {
      // Drop whole-line comments and trailing comments; prose about `.env` is not code.
      const code = read(f)
        .split("\n")
        .filter((l) => !/^\s*#/.test(l))
        .map((l) => l.replace(/\s+#.*$/, ""))
        .join("\n");
      expect(code, `${f}: printenv`).not.toMatch(/\bprintenv\b/);
      expect(code, `${f}: bare env`).not.toMatch(/(^|[;&|(\s])env(\s|$)/m);
      expect(code, `${f}: set -x`).not.toMatch(/\bset\s+-[a-zA-Z]*x/);
      expect(code, `${f}: declare -p`).not.toMatch(/\bdeclare\s+-[a-zA-Z]*p/);
    }
  });
});

// #7122 P1-A, script layer — an argument of an allowlisted verb must never be
// EVALUATED by the platform script it reaches. Three sink classes, detected by SYNTAX on
// comment-stripped source (never a bare token): (1) a positional/option-derived variable
// (bound at the top of a handler OR inside a `case` arm) used in a bash arithmetic context
// without a numeric guard — `(( limit ))`, `$(( … ))`, a numeric `[[ "$n" -gt 1 ]]`
// comparison, a `${s:$n}` substring offset and `let` all evaluate `HOME[$(cmd)]` as code
// (verified with bash: each creates the marker file); (2) any `$` interpolated into the program text of
// `python3 -c "…"` or a double-quoted jq program (pass values by sys.argv / --arg /
// --argjson instead); (3) `eval`, `bash -c`, `sh -c` beyond the one pinned registry line.
// The detectors are exported-by-position so the non-vacuity rows can run them on
// synthetic bad and good snippets, not only on the real scripts.
function stripShellComments(src: string): string {
  return src
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .map((l) => l.replace(/\s+#\s.*$/, ""))
    .join("\n");
}

/** `name() { … }` bodies, keyed by function name (a `^}` at column 0 ends one). */
function shellFunctions(code: string): Map<string, string> {
  const out = new Map<string, string>();
  const re = /^([A-Za-z_]\w*)\(\)\s*\{\n([\s\S]*?)^\}/gm;
  for (const m of code.matchAll(re)) out.set(m[1], m[2]);
  return out;
}

/** Variables a `cmd_*` handler binds from its positional parameters (its caller-controlled operands). */
function operandVars(body: string): Set<string> {
  const vars = new Set<string>();
  // A binding at the start of a line, or after a `)` / `;` (a `case` arm: `--limit) limit="${2:-20}"; shift 2 ;;`).
  for (const m of body.matchAll(/(?:^|[;)])\s*(?:local\s+)?([A-Za-z_]\w*)=\(?"\$\{?[0-9]/gm)) vars.add(m[1]);
  return vars;
}

function arithmeticIdentifiers(body: string): Set<string> {
  const ids = new Set<string>();
  for (const m of body.matchAll(/\(\(([^\n]*?)\)\)/g)) {
    const expr = m[1].replace(/\$\{#\w+\}/g, " ");
    for (const id of expr.matchAll(/\b[A-Za-z_]\w*\b/g)) ids.add(id[0]);
  }
  // `[[ … -eq|-ne|-lt|-le|-gt|-ge … ]]` evaluates BOTH operands arithmetically.
  for (const m of body.matchAll(/\[\[([^\n]*?)\]\]/g)) {
    if (!/\s-(?:eq|ne|lt|le|gt|ge)\s/.test(m[1])) continue;
    for (const ref of m[1].replace(/\$\{#[^}]*\}/g, " ").matchAll(/\$\{?([A-Za-z_]\w*)/g)) ids.add(ref[1]);
  }
  // `${s:offset:length}`: offset and length are arithmetic. `:-`, `:=`, `:+`, `:?` (no space) are NOT.
  for (const m of body.matchAll(/\$\{\w+:([^}\n]*)\}/g)) {
    if (/^[-=+?]/.test(m[1])) continue;
    for (const id of m[1].matchAll(/\b[A-Za-z_]\w*\b/g)) ids.add(id[0]);
  }
  // `let n+=1`: the whole argument list is arithmetic.
  for (const m of body.matchAll(/(?:^|[;&|(\s])let\s+([^\n;]*)/gm)) {
    for (const id of m[1].matchAll(/\b[A-Za-z_]\w*\b/g)) ids.add(id[0]);
  }
  return ids;
}

// A numeric guard: `[[ "$v" =~ ^[0-9]+$ ]]`, its canonical form `^(0|[1-9][0-9]*)$`, or a
// `require_uint <label> "$v"` call.
const numericGuardFor = (v: string, body: string): boolean =>
  new RegExp(String.raw`"\$\{?${v}\}?"\s*=~\s*\^(?:\[0-9\]\+|\(0\|\[1-9\]\[0-9\]\*\))\$`).test(body) ||
  new RegExp(String.raw`\brequire_uint\s+\S+\s+"\$\{?${v}\}?"`).test(body);

/** Findings for one script's comment-stripped source; empty means clean. */
function evaluationSinkFindings(code: string): string[] {
  const findings: string[] = [];
  for (const [fn, body] of shellFunctions(code)) {
    if (!fn.startsWith("cmd_")) continue;
    const used = arithmeticIdentifiers(body);
    for (const v of operandVars(body)) {
      if (used.has(v) && !numericGuardFor(v, body)) findings.push(`${fn}: operand \`${v}\` reaches an arithmetic context without a numeric guard`);
    }
  }
  if (/\bpython3?\s+-c\s+"(?:[^"\\]|\\.)*\$/.test(code)) findings.push("python -c program text interpolates a shell variable");
  if (/\bjq\b[^\n]*?\s"\s*[.[{(|](?:[^"\\\n]|\\.)*\$/.test(code)) findings.push("a double-quoted jq program interpolates a shell variable");
  if (/\bjq\b(?:\s+-[A-Za-z-]+)*\s+"\$\{?\w+\}?"(?:\s|$)/m.test(code)) findings.push("a jq program is supplied from a variable");
  if (/\b(?:bash|sh|zsh)\s+-[a-z]*c\b/.test(code)) findings.push("bash/sh -c");
  for (const m of code.matchAll(/(^|[;&|(\s])eval\s+([^\n]*)/gm)) {
    if (m[2].trim() !== '"$auth_cmd" &>/dev/null && return 0 || return 1') findings.push(`eval ${m[2].trim().slice(0, 40)}`);
  }
  return findings;
}

describe("community router scripts — no argument is evaluated by the script it reaches (#7122 P1-A, source tests)", () => {
  const files = readdirSync(SCRIPTS_DIR).filter((f) => f.endsWith(".sh"));
  const codeOf = (f: string) => stripShellComments(readFileSync(join(SCRIPTS_DIR, f), "utf-8"));

  it("every community script is clean of the three sink classes", () => {
    expect(files).toEqual(expect.arrayContaining(["discord-community.sh", "hn-community.sh", "community-router.sh", "github-community.sh"]));
    const failures = files.flatMap((f) => evaluationSinkFindings(codeOf(f)).map((x) => `${f}: ${x}`));
    expect(failures).toEqual([]);
  });

  it("non-vacuity: the detectors FIRE on the verified exploit shapes and stay quiet on the guarded forms", () => {
    const bad = {
      arithmetic: 'cmd_messages() {\n  local limit="${2:-100}"\n  while (( fetched < limit )); do\n    :\n  done\n}\n',
      arithmeticSubst: 'cmd_members() {\n  local limit="${1:-1000}"\n  local b=$(( limit < 5 ? limit : 5 ))\n}\n',
      python: "x=$(python3 -c \"import urllib.parse; print(urllib.parse.quote('$query'))\")\n",
      jq: 'x=$(echo "$m" | jq ".[0:${limit}]")\n',
      jqVar: 'x=$(jq -r "$prog" <<<"$m")\n',
      eval: 'eval "$user_cmd"\n',
      bashC: 'bash -c "$1"\n',
      // Test-design P3-4: contexts that evaluate an operand WITHOUT `(( ))` (each verified with
      // bash: `HOME[$(touch m)]` creates the marker).
      testGt: 'cmd_x() {\n  local n="${1:-5}"\n  [[ "$n" -gt 1 ]]\n}\n',
      testEq: 'cmd_x() {\n  local n="${1:-5}"\n  if [[ 1 -eq $n ]]; then :; fi\n}\n',
      testLe: 'cmd_x() {\n  local n="${1:-5}"\n  [[ ${n} -le 9 && -n x ]]\n}\n',
      substring: 'cmd_x() {\n  local n="${1:-5}"\n  local s="abcdef"\n  echo "${s:$n}"\n}\n',
      substringSpaced: 'cmd_x() {\n  local n="${1:-5}"\n  local s="abcdef"\n  echo "${s: -$n}"\n}\n',
      substringLength: 'cmd_x() {\n  local n="${1:-5}"\n  local s="abcdef"\n  echo "${s:0:n}"\n}\n',
      letBuiltin: 'cmd_x() {\n  local n="${1:-5}"\n  let total=n+1\n}\n',
      // Bound inside a `case` arm, not at the start of a line.
      caseArm: 'cmd_x() {\n  local limit=20\n  while [[ $# -gt 0 ]]; do\n    case "$1" in\n      --limit) limit="${2:-20}"; shift 2 ;;\n    esac\n  done\n  (( limit > 1 ))\n}\n',
      caseArmTest: 'cmd_x() {\n  local limit=20\n  case "$1" in\n    --limit)\n      limit="$2"\n      ;;\n  esac\n  [[ "$limit" -gt 1 ]]\n}\n',
    };
    for (const [name, snippet] of Object.entries(bad)) {
      expect(evaluationSinkFindings(snippet), name).not.toEqual([]);
    }
    const good = {
      arithmetic: 'cmd_messages() {\n  local limit="${2:-100}"\n  require_uint limit "$limit"\n  while (( fetched < limit )); do\n    :\n  done\n}\n',
      arithmeticRegex: 'cmd_x() {\n  local n="${1:-5}"\n  if ! [[ "$n" =~ ^[0-9]+$ ]]; then exit 1; fi\n  (( n > 1 ))\n}\n',
      python: "x=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' \"$query\")\n",
      jq: 'x=$(echo "$m" | jq --argjson n "$limit" \'.[0:$n]\')\n',
      lengthOnly: 'cmd_post() {\n  local text="${1:?usage}"\n  if (( ${#text} > 280 )); then exit 1; fi\n}\n',
      // No operand variable: `$#`, an array length and a default-value expansion are not sinks.
      argCount: 'cmd_x() {\n  local n="${1:-5}"\n  while [[ $# -gt 0 ]]; do shift; done\n  [[ ${#missing[@]} -gt 0 ]]\n  echo "${n:-x}" "${n:=y}"\n}\n',
      testGuarded: 'cmd_x() {\n  local n="${1:-5}"\n  require_uint n "$n"\n  [[ "$n" -gt 1 ]]\n  echo "${s:$n}"\n}\n',
      caseArmGuarded: 'cmd_x() {\n  local limit=20\n  case "$1" in\n    --limit) limit="${2:-20}"; shift 2 ;;\n  esac\n  require_uint "--limit" "$limit"\n  (( limit > 1 ))\n}\n',
      canonicalRegexGuard: 'cmd_x() {\n  local n="${1:-5}"\n  if ! [[ "$n" =~ ^(0|[1-9][0-9]*)$ ]]; then exit 1; fi\n  [[ "$n" -gt 1 ]]\n}\n',
    };
    for (const [name, snippet] of Object.entries(good)) {
      expect(evaluationSinkFindings(snippet), name).toEqual([]);
    }
  });

  it("non-vacuity: the guarded-arithmetic path is actually exercised on the real scripts (a guard that is never needed proves nothing)", () => {
    let guardedUses = 0;
    for (const f of files) {
      for (const [fn, body] of shellFunctions(codeOf(f))) {
        if (!fn.startsWith("cmd_")) continue;
        const used = arithmeticIdentifiers(body);
        for (const v of operandVars(body)) if (used.has(v) && numericGuardFor(v, body)) guardedUses++;
      }
    }
    // discord messages (limit), x fetch-mentions (mr_val) and the two `--max` handlers at minimum.
    expect(guardedUses).toBeGreaterThanOrEqual(3);
  });

  it("require_uint: its emitted lines expand only the script-chosen label, never the operand", () => {
    for (const f of ["discord-community.sh", "hn-community.sh"]) {
      const m = codeOf(f).match(/^require_uint\(\)\s*\{\n([\s\S]*?)^\}/m);
      expect(m, `${f}: require_uint helper`).not.toBeNull();
      const emitted = m![1].split("\n").filter((l) => /\b(?:echo|printf)\b/.test(l));
      expect(emitted.length, `${f}: the helper must report the rejection`).toBeGreaterThan(0);
      for (const l of emitted) expect(l, `${f}: ${l}`).not.toMatch(/\$\{?(?:2|value|val|arg)\b/);
      expect(m![1]).toMatch(/exit 1/);
    }
  });

  it("require_uint accepts a canonical decimal only (no leading zero: `08` is an octal literal in bash arithmetic), and the two copies are identical", () => {
    const bodies = ["discord-community.sh", "hn-community.sh"].map((f) => {
      const m = codeOf(f).match(/^require_uint\(\)\s*\{\n([\s\S]*?)^\}/m);
      expect(m, `${f}: require_uint helper`).not.toBeNull();
      return m![1];
    });
    // One rule, two copies (the scripts are standalone): a change to one is a change to both.
    expect(bodies[0]).toBe(bodies[1]);
    expect(bodies[0]).toContain("=~ ^(0|[1-9][0-9]*)$");
    expect(bodies[0]).not.toContain("^[0-9]+$");
    // Behaviour, on the extracted helper itself.
    const fn = `require_uint() {\n${bodies[0]}}\n`;
    const accepts = (v: string) =>
      spawnSync("bash", ["-c", `${fn}\nrequire_uint label "$1"`, "_", v], { encoding: "utf8" }).status === 0;
    for (const ok of ["0", "1", "50", "123456789012345678"]) expect(accepts(ok), ok).toBe(true);
    for (const bad of ["", "08", "00", "007", "-1", "+1", "1.5", "1e3", "0x1", " 1", "1 ", "1\n", "a", "1;id", "HOME[$(id)]"]) {
      expect(accepts(bad), JSON.stringify(bad)).toBe(false);
    }
  });

  it("error text in the hn and x scripts never echoes an operand (label-only messages: option, command, value)", () => {
    for (const f of ["hn-community.sh", "x-community.sh"]) {
      const echoes = codeOf(f).split("\n").filter((l) => /\becho\b[^\n]*"Error:/.test(l));
      expect(echoes.length, `${f}: error echoes found`).toBeGreaterThan(0);
      for (const l of echoes) {
        expect(l, `${f}: ${l}`).not.toMatch(/\bgot\b/);
        expect(l, `${f}: ${l}`).not.toMatch(/Unknown (?:option|command)[^"\n]*\$/);
        expect(l, `${f}: ${l}`).not.toMatch(/\$\{?(?:1|[a-z_]*val|[a-z_]+_id|max_results|command|item_id)\b/);
      }
    }
  });

  // Behavioural proof on the REAL scripts: a hostile operand is rejected BEFORE any
  // evaluation or network call, nothing from it is echoed, and no marker file appears.
  describe("real-script rows (fake credentials, a stub curl; no network)", () => {
    const hostile = (marker: string) => `HOME[$(touch ${marker})]`;
    function run(script: string, args: string[], extraPath?: string) {
      const dir = mkdtempSync(join(tmpdir(), "soleur-router-"));
      const marker = join(dir, "pwned");
      const result = spawnSync("bash", [join(SCRIPTS_DIR, script), ...args.map((a) => a.replaceAll("MARKER", marker))], {
        env: {
          PATH: `${extraPath ? extraPath + ":" : ""}${process.env.PATH}`,
          HOME: dir,
          // Synthesized, token-shaped by pattern only (cq-test-fixtures-synthesized-only).
          DISCORD_BOT_TOKEN: "aaaa.bbbb.cccc",
          DISCORD_GUILD_ID: "1",
        } as unknown as NodeJS.ProcessEnv,
        encoding: "utf8",
        timeout: 20_000,
      });
      const pwned = existsSync(marker);
      rmSync(dir, { recursive: true, force: true });
      return { ...result, pwned, marker };
    }

    it("discord messages: a hostile limit or after_id exits non-zero, runs nothing and echoes nothing", () => {
      for (const args of [
        ["messages", "123", hostile("MARKER")],
        ["messages", "123", "5", hostile("MARKER")],
        ["messages", hostile("MARKER")],
        ["members", hostile("MARKER")],
        ["messages", "123", "1;id"],
        // A leading zero used to reach `(( ))` as an octal literal and exit 0 with `[]`.
        ["messages", "123", "08"],
        ["messages", "123", "50", "08"],
        ["messages", "08"],
      ]) {
        const r = run("discord-community.sh", args);
        expect(r.status, args.join(" ")).not.toBe(0);
        expect(r.pwned, `${args.join(" ")}: marker created`).toBe(false);
        expect(`${r.stdout}${r.stderr}`).not.toMatch(/HOME\[|touch|pwned|1;id|\b08\b|value too great/);
      }
    });

    it("hn: a hostile --limit is rejected without echo, and a python-source breakout in --query is inert data", () => {
      const bin = mkdtempSync(join(tmpdir(), "soleur-stubbin-"));
      writeFileSync(join(bin, "curl"), '#!/usr/bin/env bash\nprintf \'{"hits":[],"nbHits":0,"exhaustiveNbHits":true}\\n200\'\n', { mode: 0o755 });
      try {
        const lim = run("hn-community.sh", ["mentions", "--query", "soleur", "--limit", hostile("MARKER")], bin);
        expect(lim.status).not.toBe(0);
        expect(lim.pwned).toBe(false);
        expect(`${lim.stdout}${lim.stderr}`).not.toMatch(/HOME\[|touch|pwned/);
        // A leading-zero limit is refused by the helper, not by an arithmetic error.
        const octal = run("hn-community.sh", ["mentions", "--query", "soleur", "--limit", "08"], bin);
        expect(octal.status).not.toBe(0);
        expect(`${octal.stdout}${octal.stderr}`).toMatch(/--limit must be a non-negative integer/);
        expect(`${octal.stdout}${octal.stderr}`).not.toMatch(/\b08\b|value too great/);
        const trend = run("hn-community.sh", ["trending", "--limit", hostile("MARKER")], bin);
        expect(trend.status).not.toBe(0);
        expect(trend.pwned).toBe(false);
        // The exploit string from the review: it closes the python quote and calls os.system.
        const q = run("hn-community.sh", ["mentions", "--query", "x'+str(__import__('os').system('touch MARKER'))+'", "--limit", "5"], bin);
        expect(q.pwned, "the query was executed as python source").toBe(false);
        expect(q.status, q.stderr).toBe(0);
        // Control: a benign run through the same harness succeeds (the stub path is live).
        const ok = run("hn-community.sh", ["mentions", "--query", "soleur", "--limit", "5"], bin);
        expect(ok.status, ok.stderr).toBe(0);
        expect(JSON.parse(ok.stdout).count).toBe(0);
      } finally {
        rmSync(bin, { recursive: true, force: true });
      }
    });
  });
});

// G2-6 (custody): the clone embeds its token in `.git/config` via
// buildAuthenticatedCloneUrl, so the token that reaches setupEphemeralWorkspace is
// the one an agent could read if it ever got a read primitive. The handler clones
// with a READ token and re-points `origin` to a WRITE token only AFTER the child
// has exited. The two claims proved here, on a real `git init` fixture (a handler
// test mocks setup and cannot see `.git/config`): the clone URL lands in
// remote.origin.url, and setOriginToken replaces it without leaving the old token.
describe("setOriginToken — re-pointing origin after the spawn (#7122 G2-6)", () => {
  // Built by concatenation: no token-shaped literal in the source (cq-test-fixtures-synthesized-only).
  const READ_TOK = ["ghs", "R3AD" + "x".repeat(32)].join("_");
  const WRITE_TOK = ["ghs", "WR1TE" + "y".repeat(31)].join("_");

  /** Run `fn` with process.env swapped for the fixture env: setOriginToken spawns git with process.env. */
  async function withFixtureEnv<T>(dir: string, fn: () => Promise<T>): Promise<T> {
    const saved = { ...process.env };
    for (const k of Object.keys(process.env)) delete process.env[k];
    Object.assign(process.env, gitFixtureEnv(dir));
    try {
      return await fn();
    } finally {
      for (const k of Object.keys(process.env)) delete process.env[k];
      Object.assign(process.env, saved);
    }
  }
  const git = (dir: string, args: string[]) =>
    execFileSync("git", args, { cwd: dir, env: gitFixtureEnv(dir), encoding: "utf8" }).trim();

  function makeClone(token: string): string {
    const dir = mkdtempSync(join(tmpdir(), "soleur-origin-"));
    git(dir, ["init", "--quiet"]);
    git(dir, ["remote", "add", "origin", buildAuthenticatedCloneUrl(token)]);
    return dir;
  }

  it("the clone URL built from the READ token lands in remote.origin.url and .git/config (the claim the custody split rests on)", () => {
    const dir = makeClone(READ_TOK);
    try {
      expect(git(dir, ["config", "remote.origin.url"])).toBe(buildAuthenticatedCloneUrl(READ_TOK));
      expect(readFileSync(join(dir, ".git", "config"), "utf-8")).toContain(READ_TOK);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("after setOriginToken origin holds the WRITE token and not the READ token — in git config and on disk", async () => {
    const dir = makeClone(READ_TOK);
    try {
      await withFixtureEnv(dir, () => setOriginToken(dir, WRITE_TOK));
      expect(git(dir, ["config", "remote.origin.url"])).toBe(buildAuthenticatedCloneUrl(WRITE_TOK));
      const onDisk = readFileSync(join(dir, ".git", "config"), "utf-8");
      expect(onDisk).toContain(WRITE_TOK);
      expect(onDisk).not.toContain(READ_TOK);
      // Idempotent: a replay re-points to the same token without error or duplication.
      await withFixtureEnv(dir, () => setOriginToken(dir, WRITE_TOK));
      expect(git(dir, ["config", "--get-all", "remote.origin.url"]).split("\n")).toEqual([buildAuthenticatedCloneUrl(WRITE_TOK)]);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("a failure throws an error that never carries the token or the authenticated URL", async () => {
    const dir = mkdtempSync(join(tmpdir(), "soleur-origin-"));
    try {
      git(dir, ["init", "--quiet"]); // no `origin` remote: set-url exits non-zero
      let err: unknown;
      await withFixtureEnv(dir, () => setOriginToken(dir, WRITE_TOK)).catch((e) => {
        err = e;
      });
      expect(err).toBeInstanceOf(Error);
      expect((err as Error).message).not.toContain(WRITE_TOK);
      expect((err as Error).message).not.toContain("x-access-token");
      expect((err as Error).message).toMatch(/set-url|origin/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("a symlinked .git/config (planted by the agent) is refused: the WRITE token is never written through it", async () => {
    const dir = makeClone(READ_TOK);
    const victim = join(dir, "victim.txt");
    try {
      writeFileSync(victim, "VICTIM\n");
      rmSync(join(dir, ".git", "config"));
      symlinkSync(victim, join(dir, ".git", "config"));
      let err: unknown;
      await withFixtureEnv(dir, () => setOriginToken(dir, WRITE_TOK)).catch((e) => {
        err = e;
      });
      expect(err).toBeInstanceOf(Error);
      // The refusal itself (not merely a git failure): without the guard git replaces the
      // symlink via a lock-file rename and the call SUCCEEDS, so this message is the proof.
      expect((err as Error).message).toMatch(/refused: a symlinked git entry/);
      expect((err as Error).message).not.toContain(WRITE_TOK);
      expect(readFileSync(victim, "utf-8")).toBe("VICTIM\n");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("source anchor: the helper redacts the token in its thrown error and never logs the URL", () => {
    const src = readFileSync(
      join(__dirname, "../../../server/inngest/functions/_cron-claude-eval-substrate.ts"),
      "utf-8",
    );
    const body = src.slice(src.indexOf("export async function setOriginToken"));
    const fn = body.slice(0, body.indexOf("\n}\n") + 3);
    expect(fn).toContain("redactToken(");
    expect(fn).not.toMatch(/logger|console\./);
  });
});
