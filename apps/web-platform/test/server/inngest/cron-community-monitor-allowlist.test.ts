// #7122 Guard 2 — containment closure for cron-community-monitor (plan
// 2026-10-06-fix-community-monitor-output-allowlist, Phase 3).
//
// The spawned agent may collect and classify; it may not publish. Three layers
// are asserted here, all through the REAL hook's pure `decide()`:
//   1. the Bash surface is exactly the sixteen read invocations of the community
//      router (no gh verb at all, no bare router prefix, no posting verb);
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
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
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
  ["router platforms", bash(`${ROUTER} platforms`), "allow"],
];

function failedProbes(fn: DecideFn, lines: string[]): string[] {
  return COMMUNITY_PROBES.filter(([, input, want]) => verdictWith(fn, lines, input) !== want).map(([label]) => label);
}

describe("cron-community-monitor allowlist closure (#7122 Guard 2)", () => {
  const lines = linesFor(CRON);

  it("G2-1: no gh verb of any kind survives in the community allowlist (create/comment/list/label)", () => {
    expect(COMMUNITY_ROUTER_READ_VERBS.length).toBe(16);
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

  it("G2-2: the bare router prefix is gone — every allow line is a full `<router> <platform> <verb>` literal and posting verbs are denied", () => {
    const bashLines = lines.filter((l) => l.startsWith("bash "));
    expect(bashLines).toEqual([...COMMUNITY_ROUTER_READ_VERBS]);
    expect(bashLines).not.toContain(ROUTER);
    // allow[0] is executed verbatim by runHookSelfTest: it must be a whole command.
    expect(COMMUNITY_ROUTER_READ_VERBS[0]).toBe(`${ROUTER} platforms`);
    for (const l of COMMUNITY_ROUTER_READ_VERBS) expect(l).toMatch(/^bash plugins\/soleur\/skills\/community\/scripts\/community-router\.sh [a-z-]+( [a-z-]+)?$/);
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
    // Trailing arguments on an allowlisted verb stay allowed (prefix + separator semantics).
    expect(verdictWith(decide, lines, bash(`${ROUTER} hn mentions --query soleur --limit 20`))).toBe("allow");
    expect(verdictWith(decide, lines, bash(`${ROUTER} github activity 1`))).toBe("allow");
    expect(verdictWith(decide, lines, bash(`${ROUTER} discord messages 123456789012345678`))).toBe("allow");
  });

  it("G2-3: EVERY member is judged — all sixteen read verbs allow and every posting verb denies (a first-member-only check is the defect)", () => {
    expect(new Set(COMMUNITY_ROUTER_READ_VERBS).size).toBe(16);
    for (const verb of COMMUNITY_ROUTER_READ_VERBS) {
      expect(verdictWith(decide, lines, bash(verb)), verb).toBe("allow");
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

  it("G2-8: every community-router.sh invocation literal in COMMUNITY_MONITOR_PROMPT is in COMMUNITY_ROUTER_READ_VERBS (prompt parity)", () => {
    const start = HANDLER_SRC.indexOf("const COMMUNITY_MONITOR_PROMPT");
    expect(start, "COMMUNITY_MONITOR_PROMPT not found in the handler source").toBeGreaterThan(-1);
    const end = HANDLER_SRC.indexOf("`;", HANDLER_SRC.indexOf("`", start) + 1);
    const prompt = HANDLER_SRC.slice(start, end);
    const literals = [
      ...prompt.matchAll(
        /bash plugins\/soleur\/skills\/community\/scripts\/community-router\.sh(?: ([a-z][a-z0-9-]*))?(?: ([a-z][a-z0-9-]*))?/g,
      ),
    ].flatMap((m) => {
      if (!m[1]) return []; // a prose mention of the script, not an invocation
      return [m[1] === "platforms" ? `${ROUTER} platforms` : m[2] ? `${ROUTER} ${m[1]} ${m[2]}` : []];
    });
    // Non-vacuity: the prompt's steps 1-2 carry at least the platform probe and
    // the three Discord, X, Bluesky, LinkedIn, five GitHub and two HN collectors.
    expect(literals.length).toBeGreaterThanOrEqual(10);
    for (const l of new Set(literals)) {
      expect(COMMUNITY_ROUTER_READ_VERBS, `prompt invokes ${l}, which the hook would deny`).toContain(l);
    }
  });

  it("G2-9: harness — the probe list FAILS against a hook that allows everything, and passes against the real one", () => {
    const allowAll: DecideFn = () => ({ hookSpecificOutput: { permissionDecision: "allow" } });
    const denyAll: DecideFn = () => ({ hookSpecificOutput: { permissionDecision: "deny" } });
    const realFailures = failedProbes(decide as DecideFn, lines);
    expect(realFailures).toEqual([]);
    const allowAllFailures = failedProbes(allowAll, lines);
    // Every deny probe is caught (all but the single allow control).
    expect(allowAllFailures.length).toBe(COMMUNITY_PROBES.filter(([, , w]) => w === "deny").length);
    expect(allowAllFailures.length).toBeGreaterThanOrEqual(15);
    // And a deny-everything stub is caught by the allow control (the suite cannot go green on a hook that blocks all).
    expect(failedProbes(denyAll, lines)).toEqual(["router platforms"]);
  });

  it("G2-10 (must PASS): chained `;` read verbs allow, and a cron WITHOUT the directive is unaffected", () => {
    expect(
      verdictWith(
        decide,
        lines,
        bash(`${ROUTER} github fetch-interactions 1; ${ROUTER} hn trending --limit 30`),
      ),
    ).toBe("allow");
    expect(
      verdictWith(
        decide,
        lines,
        bash(
          `${ROUTER} discord guild-info; ${ROUTER} discord members; ${ROUTER} discord channels; ${ROUTER} x fetch-metrics; ${ROUTER} bsky get-metrics; ${ROUTER} linkedin fetch-metrics; ${ROUTER} linkedin fetch-activity`,
        ),
      ),
    ).toBe("allow");
    // One bad segment in a chain poisons the whole command.
    expect(verdictWith(decide, lines, bash(`${ROUTER} hn trending; ${ROUTER} bsky post x`))).toBe("deny");
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
