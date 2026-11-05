/**
 * #11636 (ADR-309), Guard 2: allow-source pin over the platform plugin tree.
 *
 * The cc dispatcher registers one approval-required tool (`github_push_branch`) and relies on `canUseTool` (the approval
 * gate) being the only thing that can allow it. A skill, agent or command file that PRE-ALLOWS an MCP tool in its
 * frontmatter (`allowed-tools:` / `tools:`), or a hooks / MCP config that names the tool, is a second allow source that
 * could resolve ahead of `canUseTool`. The strict handler (`requireGrant`) already makes such an allow inert for this tool
 * (pinned in github-tools-push-grant.test.ts and cc-push-gate-flow.test.ts); this scan keeps the ADR claim CHECKABLE.
 *
 * A minimal TEXT scan, deliberately not a YAML parser: it over-reports (prose that names the tool inside frontmatter is a
 * hit) rather than under-reports, and it cannot be fooled by list-versus-string syntax.
 *
 *   - Markdown: inside the leading `---` frontmatter block ANY mention of the `mcp__soleur_platform` server prefix is a hit
 *     (a wildcard, a bare server, a list entry, a one-line string, a second member after a compliant first one); in the
 *     body, only an approval-required FQN is a hit (prose elsewhere may describe the `mcp__soleur_platform__*` naming).
 *   - JSON (hooks.json, .mcp.json, plugin.json): any line naming the server prefix or an approval-required FQN is a hit.
 *   - Wildcards: in frontmatter or JSON, an `mcp__...*` token whose literal part is a PREFIX of an approval-required FQN
 *     (`mcp__*`, `mcp__soleur*`, `mcp__soleur_platform*`) is a hit even though it never spells the server prefix; an
 *     unrelated plugin wildcard (`mcp__plugin_x__*`) is not.
 *   - hooks.json matchers (a behavioural check, not a text scan): every PreToolUse / PostToolUse matcher is tested, as a
 *     string and as a regular expression, against the push FQN; an empty, `*` or matching matcher is a hit.
 *
 * Does NOT see: how the SDK orders an MCP allow rule that came from a skill against `canUseTool` (stays UNVERIFIED beyond
 * this source scan; `settingSources: []` is pinned by T7 in cc-dispatcher-real-factory.test.ts), or a tool name assembled
 * at run time. The approval-required FQNs are imported from `server/approval/tools.ts`, never restated, so adding a tool
 * there tightens the pin.
 */
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative, resolve } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { APPROVAL_REQUIRED_TOOLS } from "@/server/approval/tools";

const SERVER_PREFIX = "mcp__soleur_platform";
const PLUGIN_ROOT = resolve(__dirname, "../../../../plugins/soleur");
const SCANNED_DIRS = ["skills", "agents", "commands", "hooks"] as const;
/** The least number of skills the walk must see (106 tracked at plan time): a walker that returns zero or one root cannot read green. */
const SKILL_FLOOR = 100;

interface Hit {
  file: string;
  line: number;
  text: string;
}

function walk(dir: string): string[] {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries.flatMap((e) => {
    const full = join(dir, e.name);
    if (e.isDirectory()) return e.name === "node_modules" ? [] : walk(full);
    return e.isFile() ? [full] : [];
  });
}

/** Files in scope under `root`: every *.md and hooks.json under the four directories, plus .mcp.json and plugin.json when present. */
function discover(root: string): string[] {
  const out: string[] = [];
  for (const d of SCANNED_DIRS) {
    for (const f of walk(join(root, d))) {
      if (f.endsWith(".md") || f.endsWith("/hooks.json")) out.push(f);
    }
  }
  for (const rel of [".mcp.json", ".claude-plugin/plugin.json"]) {
    const f = join(root, rel);
    if (existsSync(f)) out.push(f);
  }
  return out;
}

/** An `mcp__...*` wildcard whose literal part would match an approval-required FQN (so it could pre-allow it). */
function namesPlatformWildcard(line: string): boolean {
  const tokens = line.match(/mcp__[A-Za-z0-9_]*\*/g) ?? [];
  return tokens.some((tok) => {
    const literal = tok.slice(0, -1);
    return APPROVAL_REQUIRED_TOOLS.some((fqn) => fqn.startsWith(literal));
  });
}

/** The 1-based line numbers (and text) of every offending line in one file's text. */
function scanText(file: string, text: string): Hit[] {
  const hits: Hit[] = [];
  const lines = text.split("\n");
  const isJson = file.endsWith(".json");
  // Frontmatter = a leading `---` line to the next `---` line (markdown only).
  let fmEnd = -1;
  if (!isJson && lines[0]?.trim() === "---") {
    for (let i = 1; i < lines.length; i++) {
      if (lines[i].trim() === "---") {
        fmEnd = i;
        break;
      }
    }
  }
  lines.forEach((line, idx) => {
    const inFrontmatter = fmEnd > 0 && idx > 0 && idx < fmEnd;
    const namesFqn = APPROVAL_REQUIRED_TOOLS.some((fqn) => line.includes(fqn));
    const namesServer = line.includes(SERVER_PREFIX);
    const namesWildcard = (isJson || inFrontmatter) && namesPlatformWildcard(line);
    if (namesFqn || namesWildcard || ((isJson || inFrontmatter) && namesServer)) hits.push({ file, line: idx + 1, text: line.trim().slice(0, 160) });
  });
  return hits;
}

function scanTree(root: string): { files: string[]; hits: Hit[] } {
  const files = discover(root);
  const hits = files.flatMap((f) => scanText(relative(root, f), readFileSync(f, "utf8")));
  return { files, hits };
}

/** The per-directory floor: throws when the walk did not see a plausible tree (never a "0 checked" green). */
function assertFloor(root: string, files: readonly string[]): void {
  const under = (d: string) => files.filter((f) => f.startsWith(join(root, d) + "/"));
  const skills = under("skills").filter((f) => f.endsWith("/SKILL.md"));
  if (skills.length < SKILL_FLOOR) throw new Error(`walk saw ${skills.length} SKILL.md files, expected at least ${SKILL_FLOOR}`);
  if (under("agents").length < 1) throw new Error("walk saw no agent files");
  if (under("commands").length < 1) throw new Error("walk saw no command files");
  if (!under("hooks").some((f) => f.endsWith("/hooks.json"))) throw new Error("walk saw no hooks.json");
}

const tmpRoots: string[] = [];
afterAll(() => {
  for (const r of tmpRoots) rmSync(r, { recursive: true, force: true });
});
function fixture(files: Record<string, string>): string {
  const root = mkdtempSync(join(tmpdir(), "allow-source-pin-"));
  tmpRoots.push(root);
  for (const [rel, body] of Object.entries(files)) {
    mkdirSync(join(root, rel, ".."), { recursive: true });
    writeFileSync(join(root, rel), body);
  }
  return root;
}

const PUSH_FQN = "mcp__soleur_platform__github_push_branch";

describe("the platform plugin tree pre-allows no approval-required tool and not the whole platform server", () => {
  const { files, hits } = scanTree(PLUGIN_ROOT);

  it("the walk is non-vacuous: it sees at least the floor of skills, and agents, commands and a hooks.json", () => {
    expect(() => assertFloor(PLUGIN_ROOT, files)).not.toThrow();
    expect(files.filter((f) => f.includes("/skills/") && f.endsWith("/SKILL.md")).length).toBeGreaterThanOrEqual(SKILL_FLOOR);
  });

  it("no scanned file names an approval-required FQN, or the platform server prefix in frontmatter or JSON config", () => {
    expect(hits).toEqual([]);
  });

  it("the approval-required set it imports includes the push tool (the pin tightens when a tool is added there)", () => {
    expect([...APPROVAL_REQUIRED_TOOLS]).toContain(PUSH_FQN);
  });
});

/** Tool-event hook matchers from a hooks.json text: `undefined` when the entry has none (which matches every tool). */
const TOOL_EVENTS = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest"] as const;
function toolHookMatchers(json: string): Array<string | undefined> {
  const doc = JSON.parse(json) as { hooks?: Record<string, Array<{ matcher?: string }>> };
  return TOOL_EVENTS.flatMap((ev) => (doc.hooks?.[ev] ?? []).map((entry) => entry.matcher));
}
/** String form: an exact name (or the match-all `""` / `*`). Regex form: an unanchored RegExp (the over-reporting reading). */
function matcherReaches(matcher: string | undefined, toolName: string): boolean {
  if (matcher === undefined || matcher === "" || matcher === "*") return true;
  if (matcher === toolName) return true;
  try {
    return new RegExp(matcher).test(toolName);
  } catch {
    return false;
  }
}

describe("hooks.json: no tool-event hook matcher reaches the push tool (behavioural, string and regex forms)", () => {
  const hooksJson = readFileSync(join(PLUGIN_ROOT, "hooks/hooks.json"), "utf8");
  const matchers = toolHookMatchers(hooksJson);

  it("is non-vacuous: the real file has tool-event matchers to test", () => {
    expect(matchers.length).toBeGreaterThanOrEqual(3);
  });

  it("no PreToolUse or PostToolUse matcher in the real hooks.json matches the push FQN", () => {
    expect(matchers.filter((m) => matcherReaches(m, PUSH_FQN))).toEqual([]);
  });

  it.each([
    ["an empty matcher", ""],
    ["a star matcher", "*"],
    ["an unset matcher", undefined],
    ["a regex over the mcp__ prefix", "mcp__.*"],
    ["the exact FQN as a string", PUSH_FQN],
    ["a regex alternation naming the tool", "^(Bash|mcp__soleur_platform__github_push_branch)$"],
    ["an unanchored fragment of the tool name", "github_push"],
  ])("canary: %s reaches the push FQN", (_n, matcher) => {
    expect(matcherReaches(matcher, PUSH_FQN)).toBe(true);
  });

  it.each(["^Bash$", "^(Bash|exec)$", "^(Bash|Monitor|Write|Edit|MultiEdit|NotebookEdit)$", "startup|resume"])(
    "must-pass: %s does not reach the push FQN",
    (matcher) => {
      expect(matcherReaches(matcher, PUSH_FQN)).toBe(false);
    },
  );

  it("canary: a fixture hooks.json with a match-all PreToolUse entry is reported by the extractor", () => {
    const fixtureJson = JSON.stringify({ hooks: { PreToolUse: [{ matcher: "^Bash$" }, { hooks: [] }], SessionStart: [{ matcher: "" }] } });
    expect(toolHookMatchers(fixtureJson).filter((m) => matcherReaches(m, PUSH_FQN))).toEqual([undefined]);
  });
});

describe("canary: the scanner reports an offending fixture (mutation rows)", () => {
  const skill = (fm: string, body = "Body.\n") => `---\nname: x\n${fm}\n---\n${body}`;

  it("row 1: the push FQN on a skill's allowed-tools line", () => {
    const root = fixture({ "skills/a/SKILL.md": skill(`allowed-tools: Read, ${PUSH_FQN}`) });
    const { hits } = scanTree(root);
    expect(hits).toHaveLength(1);
    expect(hits[0]).toMatchObject({ file: "skills/a/SKILL.md", line: 3 });
  });

  it("row 2: the whole-server wildcard as a SECOND list entry after a compliant first entry", () => {
    const root = fixture({ "skills/a/SKILL.md": skill("allowed-tools:\n  - mcp__plugin_x__tool\n  - mcp__soleur_platform__*") });
    const { hits } = scanTree(root);
    expect(hits.map((h) => h.text)).toEqual(["- mcp__soleur_platform__*"]);
  });

  it("a bare server name in an agent's tools frontmatter is a hit", () => {
    const root = fixture({ "agents/b.md": skill("tools: mcp__soleur_platform") });
    expect(scanTree(root).hits).toHaveLength(1);
  });

  it("an approval-required FQN in a hooks.json or .mcp.json line is a hit, wherever it sits", () => {
    const root = fixture({
      "hooks/hooks.json": `{\n  "hooks": [{"matcher": "${PUSH_FQN}"}]\n}\n`,
      ".mcp.json": `{"mcpServers": {"x": {"args": ["mcp__soleur_platform__*"]}}}\n`,
    });
    const { hits } = scanTree(root);
    expect(hits.map((h) => h.file).sort()).toEqual([".mcp.json", "hooks/hooks.json"]);
  });

  it("an approval-required FQN named in a command BODY is a hit (over-reports on purpose)", () => {
    const root = fixture({ "commands/c.md": skill("description: d", `Call \`${PUSH_FQN}\` directly.\n`) });
    expect(scanTree(root).hits).toHaveLength(1);
  });

  it.each(["mcp__*", "mcp__soleur*", "mcp__soleur_*", "mcp__soleur_platform*"])(
    "a frontmatter wildcard %s that would cover the platform server is a hit even though it never spells the server prefix",
    (wild) => {
      const root = fixture({
        "skills/a/SKILL.md": skill(`allowed-tools: Read, ${wild}`),
        "agents/b.md": skill(`tools:\n  - ${wild}`),
        "hooks/hooks.json": `{\n  "allow": ["${wild}"]\n}\n`,
      });
      expect(scanTree(root).hits.map((h) => h.file).sort()).toEqual(["agents/b.md", "hooks/hooks.json", "skills/a/SKILL.md"]);
    },
  );

  it("row 3: a walker that returns no files trips the floor (no '0 checked' green)", () => {
    const empty = fixture({ "README.md": "x" });
    const { files: none } = scanTree(empty);
    expect(none).toEqual([]);
    expect(() => assertFloor(empty, none)).toThrow(/SKILL\.md/);
  });
});

describe("must-pass: non-canonical inputs that are NOT violations", () => {
  const skill = (fm: string, body = "Body.\n") => `---\nname: x\n${fm}\n---\n${body}`;

  it("an unrelated plugin MCP allow entry, with prose naming the platform wildcard in the body, passes", () => {
    const root = fixture({
      "skills/a/SKILL.md": skill(
        "allowed-tools: Read, mcp__plugin_x__tool",
        "The platform tools are named `mcp__soleur_platform__*` and are tiered in code.\n",
      ),
      "agents/b.md": skill("tools: Read, Grep"),
    });
    expect(scanTree(root).hits).toEqual([]);
  });

  it.each(["mcp__plugin_x__*", "mcp__github__*", "mcp__playwright__browser_*"])(
    "an unrelated plugin wildcard %s in frontmatter passes",
    (wild) => {
      const root = fixture({ "skills/a/SKILL.md": skill(`allowed-tools: Read, ${wild}`), "agents/b.md": skill(`tools: ${wild}`) });
      expect(scanTree(root).hits).toEqual([]);
    },
  );

  it("a wildcard named in prose in a body (not frontmatter) passes", () => {
    const root = fixture({ "commands/c.md": skill("description: d", "Never grant `mcp__*` here.\n") });
    expect(scanTree(root).hits).toEqual([]);
  });

  it("a non-approval-required platform FQN in the body (narration) passes", () => {
    const root = fixture({ "commands/c.md": skill("description: d", "Uses mcp__soleur_platform__narrate.\n") });
    expect(scanTree(root).hits).toEqual([]);
  });
});
