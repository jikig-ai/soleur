// #12824 Guard 1 — the write-and-execute census.
//
// THE PROPERTY. For every cron that reaches `spawnClaudeEval`, no path that cron EXECUTES is one that cron can
// WRITE. A cron that can rewrite a file it later runs (a plugin hook, an allowlisted script, the containment hook,
// an MCP server binary) runs agent-authored code with the whole spawn env — paths 1 and 3 of #12824.
//
// HOW IT IS ASSEMBLED.
//   - Population: every `spawnClaudeEval(...)` call under server/, found with the TypeScript compiler API (one
//     createSourceFile per file, open-world, recursive). Any reference that is not a direct call fails, so an
//     alias cannot hide a call site. Stored as an identity map file → { cronName, loadPlugin }.
//   - Executed paths, read from the REAL producers: (1) the `--plugin-dir` root from buildClaudeArgv(); (2) every
//     `bash <path>` line of buildAllowlistLines(); (3) every hook command of buildCronEvalSettings() for both
//     frameGhOutput values; (4) every MCP server `command` a cron writes into its `.mcp.json` overlay. The plugin
//     root fed to the producers is the constant SOLEUR_PLUGIN_PATH_DEFAULT, never getPluginPath() (which a test
//     fixture's SOLEUR_PLUGIN_PATH would move).
//   - Writability: a path is writable when the REAL decide() of cron-bash-allowlist-hook.mjs, fed that cron's real
//     allowlist lines and the run's two write roots, allows a Write/Edit/MultiEdit to it, OR allows any of a fixed
//     set of tree-writing Bash forms aimed at it. The census never assumes "git writes clone paths only": it asks
//     decide(). Branch moves (`git switch <b>`, `git checkout -b`) are not in the probe set: a depth-1 clone holds
//     only its default branch (measurements.md arm 0.7d), so a switch can only reach content the agent could already
//     write, and every such file is pattern-protected.
//   - All-writable class: a cron with an arbitrary-exec allowlist line (`./node_modules/.bin/*`, `node`, an
//     installer, `bash <non-plugin-root path>`, a worktree `create` that runs install_deps) can run code it wrote
//     below the hook, so every path is writable for it. Decided by LINE SHAPE, never by cron name. The set must be
//     empty; the exemption map must be empty.
//
// THE ANCHOR. "Under the plugin root is unwritable" rests on (a) decide() denying every write outside the two run
// roots (asserted here), (b) every `-v …:/app/shared/plugins/soleur` mount ending `:ro` — pinned in
// apps/web-platform/infra/lib/docker-run-tuple.py `_VOLS` and asserted by apps/web-platform/infra/docker-run-tuple.test.sh
// (cited, not repeated; this file only checks the constant names that mount target), and (c) the spawn-time resolver
// refusing a writable root (cron-spawn-isolation.test.ts, Guard 3).
//
// HOW TO READ A RED RUN. Each finding names the cron, the path, the executed source and the write route decide()
// allowed, then the fixes in order: (1) write the allowlist line as `bash <plugin-root>/…` (the read-only root);
// (2) add a WRITE_PROTECTED_PATTERNS entry in cron-bash-allowlist-hook.mjs; (3) only then an EXEMPTIONS entry
// naming an open issue. A red from the identity map says "add `file → cronName`". Any new exemption is a review
// finding: a diff that edits both a producer and this map proves consistency, not integrity.
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative, resolve, sep } from "node:path";
import ts from "typescript";
import { afterAll, describe, expect, it } from "vitest";

import { decide, deriveWriteRoots } from "@/server/inngest/cron-bash-allowlist-hook.mjs";
import {
  buildAllowlistLines,
  buildClaudeArgv,
  buildCronEvalSettings,
  CRON_BASH_ALLOWLISTS,
  CRON_PLUGIN_LOADERS,
  PLUGIN_ROOT_TOKEN,
} from "@/server/inngest/functions/_cron-claude-eval-substrate";
import { SOLEUR_PLUGIN_PATH_DEFAULT } from "@/server/plugin-path";

const APP = resolve(__dirname, "../../..");
const SERVER = join(APP, "server");
const FN_DIR = join(SERVER, "inngest/functions");
const REPO = resolve(APP, "../..");
const ROOT = SOLEUR_PLUGIN_PATH_DEFAULT;
const ENV = { NEXT_PUBLIC_APP_URL: "https://app.soleur.ai" };

// ---- the stored maps ----------------------------------------------------------------------------------------

/** Identity map of every spawnClaudeEval call site: file (relative to server/) → its cron and loadPlugin literal. */
const POPULATION: Record<string, { cronName: string; loadPlugin: boolean }> = {
  "inngest/functions/cron-agent-native-audit.ts": { cronName: "cron-agent-native-audit", loadPlugin: true },
  "inngest/functions/cron-architecture-diagram-sync.ts": { cronName: "cron-architecture-diagram-sync", loadPlugin: true },
  "inngest/functions/cron-bug-fixer.ts": { cronName: "cron-bug-fixer", loadPlugin: true },
  "inngest/functions/cron-campaign-calendar.ts": { cronName: "cron-campaign-calendar", loadPlugin: true },
  "inngest/functions/cron-community-monitor.ts": { cronName: "cron-community-monitor", loadPlugin: false },
  "inngest/functions/cron-competitive-analysis.ts": { cronName: "cron-competitive-analysis", loadPlugin: true },
  "inngest/functions/cron-content-generator.ts": { cronName: "cron-content-generator", loadPlugin: true },
  "inngest/functions/cron-daily-triage.ts": { cronName: "cron-daily-triage", loadPlugin: false },
  "inngest/functions/cron-follow-through-monitor.ts": { cronName: "cron-follow-through-monitor", loadPlugin: false },
  "inngest/functions/cron-growth-audit.ts": { cronName: "cron-growth-audit", loadPlugin: true },
  "inngest/functions/cron-growth-execution.ts": { cronName: "cron-growth-execution", loadPlugin: true },
  "inngest/functions/cron-legal-audit.ts": { cronName: "cron-legal-audit", loadPlugin: true },
  "inngest/functions/cron-roadmap-review.ts": { cronName: "cron-roadmap-review", loadPlugin: false },
  "inngest/functions/cron-seo-aeo-audit.ts": { cronName: "cron-seo-aeo-audit", loadPlugin: true },
  "inngest/functions/cron-ux-audit.ts": { cronName: "cron-ux-audit", loadPlugin: true },
  "inngest/functions/event-ship-merge.ts": { cronName: "event-ship-merge", loadPlugin: true },
  "inngest/functions/oneshot-f2-defer-gate-review.ts": { cronName: "oneshot-f2-defer-gate-review", loadPlugin: false },
  "inngest/functions/oneshot-recheck-4217-calibration.ts": { cronName: "oneshot-recheck-4217-calibration", loadPlugin: false },
};

/** The two crons that run in the server's cwd and clone nothing (no setupEphemeralWorkspace). */
const SERVER_CWD_CRONS = new Set(["cron-daily-triage", "cron-follow-through-monitor"]);

/** (cron, path) pairs allowed to be both written and executed, each naming an open issue. MUST stay empty. */
const EXEMPTIONS: Record<string, { path: string; issue: string }[]> = {};

/**
 * Vendored-file coverage (CTO T2): the deployed copy holds only md/json/njk/yml/yaml/sh/txt
 * (apps/web-platform/.dockerignore). A script a plugin-loading cron's skill names with another extension is absent
 * from the read-only root; each miss carries a disposition. "degrades" is allowed only because the census below
 * proves no cron holds an interpreter verb, so the skill's call fails closed instead of running the clone's copy.
 */
const VENDORED_MISS_DISPOSITIONS: Record<string, string> = {
  "ux-audit ./scripts/bot-fixture.ts": "handler-side import in cron-ux-audit.ts (bot-fixture-seed step), never agent-executed",
  "ux-audit ./scripts/bot-signin.ts": "handler-side import in cron-ux-audit.ts (bot-signin step), never agent-executed",
  "ux-audit ./scripts/dedup-hash.ts": "degrades: ux-audit's allowlist holds no interpreter verb",
  "ship ../../../../scripts/lint-rule-bodies.py": "degrades: event-ship-merge has no bash allowlist (fail-closed)",
  "ship scripts/lint-rule-bodies.py": "degrades: event-ship-merge has no bash allowlist (fail-closed)",
  "ship ../../../../scripts/lint-skill-body-budget.py": "degrades: event-ship-merge has no bash allowlist (fail-closed)",
  "ship scripts/lint-skill-body-budget.py": "degrades: event-ship-merge has no bash allowlist (fail-closed)",
};
const VENDORED_EXTENSIONS = new Set(["md", "json", "njk", "yml", "yaml", "sh", "txt"]);

// ---- discovery (TypeScript compiler API) ----------------------------------------------------------------------

interface CallSite {
  file: string;
  cronName: string | null;
  loadPlugin: boolean | null;
}
interface Discovery {
  calls: CallSite[];
  strayRefs: string[];
}

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else if (/\.[cm]?[tj]sx?$/.test(e.name) && !/\.d\.[cm]?ts$/.test(e.name) && !/\.test\.[cm]?[tj]sx?$/.test(e.name))
      out.push(p);
  }
  return out;
}

/** A string literal, or an identifier bound by a same-file top-level `const X = "…"` (no other indirection). */
function stringValue(sf: ts.SourceFile, e: ts.Expression): string | null {
  if (ts.isStringLiteral(e)) return e.text;
  if (!ts.isIdentifier(e)) return null;
  for (const st of sf.statements) {
    if (!ts.isVariableStatement(st) || !(st.declarationList.flags & ts.NodeFlags.Const)) continue;
    for (const d of st.declarationList.declarations) {
      if (ts.isIdentifier(d.name) && d.name.text === e.text && d.initializer && ts.isStringLiteral(d.initializer)) {
        return d.initializer.text;
      }
    }
  }
  return null;
}

function discover(): Discovery {
  const calls: CallSite[] = [];
  const strayRefs: string[] = [];
  for (const file of walk(SERVER)) {
    const src = readFileSync(file, "utf-8");
    if (!src.includes("spawnClaudeEval")) continue;
    const rel = relative(SERVER, file);
    const sf = ts.createSourceFile(file, src, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
    const visit = (node: ts.Node): void => {
      if (ts.isIdentifier(node) && node.text === "spawnClaudeEval") {
        const p = node.parent;
        const line = sf.getLineAndCharacterOfPosition(node.getStart()).line + 1;
        if (ts.isCallExpression(p) && p.expression === node) {
          const arg = p.arguments[0];
          let cronName: string | null = null;
          let loadPlugin: boolean | null = null;
          if (arg && ts.isObjectLiteralExpression(arg)) {
            for (const prop of arg.properties) {
              if (!ts.isPropertyAssignment(prop) || !ts.isIdentifier(prop.name)) continue;
              if (prop.name.text === "cronName") cronName = stringValue(sf, prop.initializer);
              if (prop.name.text === "loadPlugin") {
                if (prop.initializer.kind === ts.SyntaxKind.TrueKeyword) loadPlugin = true;
                if (prop.initializer.kind === ts.SyntaxKind.FalseKeyword) loadPlugin = false;
              }
            }
          }
          calls.push({ file: rel, cronName, loadPlugin });
        } else if (ts.isImportSpecifier(p) && !p.propertyName) {
          // `import { spawnClaudeEval } from …` — a plain import is not a reference.
        } else if (ts.isFunctionDeclaration(p) && p.name === node && rel === "inngest/functions/_cron-claude-eval-substrate.ts") {
          // the definition itself
        } else {
          strayRefs.push(`${rel}:${line} (${ts.SyntaxKind[p.kind]})`);
        }
      }
      ts.forEachChild(node, visit);
    };
    visit(sf);
  }
  return { calls, strayRefs };
}

// ---- the fixture: one run's two write roots, real on disk -----------------------------------------------------

const BASE = mkdtempSync(join(tmpdir(), "cron-census-"));
const EPHEMERAL = join(BASE, "soleur-cron-x-AAA");
const SPAWN_CWD = join(EPHEMERAL, "repo");
const HOME = join(EPHEMERAL, "home-abc123");
for (const d of [SPAWN_CWD, join(HOME, "tmp"), join(SPAWN_CWD, "src")]) mkdirSync(d, { recursive: true });
afterAll(() => rmSync(BASE, { recursive: true, force: true }));
const ROOTS = deriveWriteRoots(SPAWN_CWD, HOME) as string[];

type DecideFn = (input: unknown, lines: string[], opts?: { writeRoots?: string[] }) => {
  hookSpecificOutput: { permissionDecision: string };
};
const realDecide = decide as DecideFn;

/** Tree-writing Bash forms aimed at a path (relative when the path is in the clone, as the agent would type it). */
const PROBE_FORMS = (p: string): string[] => [
  `git checkout -- ${p}`,
  `git checkout HEAD -- ${p}`,
  `git restore ${p}`,
  `git restore --source=HEAD ${p}`,
  `cp x ${p}`,
  `mv x ${p}`,
  `tee ${p}`,
  `sed -i s/a/b/ ${p}`,
  `ln -sf x ${p}`,
  `dd of=${p}`,
];
/** Whole-tree forms whose content can come from outside the agent's own writes. */
const TREE_FORMS = [
  "git checkout --orphan x",
  "git apply x.patch",
  "git am x.patch",
  "git pull",
  "git fetch",
  "git merge origin/x",
  "git reset --hard origin/x",
  "git cherry-pick x",
  "git stash pop",
];

/** The write route decide() allowed for `p`, or null when every route is denied. */
function writeRoute(fn: DecideFn, lines: string[], p: string): string | null {
  for (const tool of ["Write", "Edit", "MultiEdit"]) {
    const v = fn({ tool_name: tool, tool_input: { file_path: p } }, lines, { writeRoots: ROOTS });
    if (v.hookSpecificOutput.permissionDecision === "allow") return `${tool} ${p}`;
  }
  const typed = p.startsWith(SPAWN_CWD + sep) ? relative(SPAWN_CWD, p) : p;
  const inClone = p.startsWith(SPAWN_CWD + sep);
  for (const command of [...PROBE_FORMS(typed), ...(inClone ? TREE_FORMS : [])]) {
    const v = fn({ tool_name: "Bash", tool_input: { command } }, lines, { writeRoots: ROOTS });
    if (v.hookSpecificOutput.permissionDecision === "allow") return `Bash ${command}`;
  }
  return null;
}

const DIRECTIVE = /^(mcp-allow|navigate-origin|run-report-label) |^no-file-tools$/;
const INSTALLERS = new Set(["npm", "npx", "bun", "bunx", "pnpm", "yarn", "pip", "pip3", "uv", "gem", "cargo", "go"]);
const INTERPRETERS = new Set(["node", "python", "python3", "ruby", "perl", "deno", "tsx", "ts-node", "php"]);
// #12847 review (structural P2) — gh/git lines are judged by decide() through the probe forms, but only for the
// subcommands below: `git rebase`/`bisect`/`submodule`, `gh extension`/`alias` and anything new can run code, so an
// unknown subcommand is UNCLASSIFIED (red) until it is reviewed and added here.
const GH_KNOWN: Record<string, ReadonlySet<string> | "any"> = {
  api: "any", // judged by decide()'s gh api grammar (method / field / endpoint rules)
  issue: new Set(["close", "comment", "create", "edit", "list", "view"]),
  label: new Set(["create", "list"]),
  pr: new Set(["comment", "create", "edit", "list", "view"]),
};
const GIT_KNOWN = new Set(["add", "branch", "checkout", "commit", "diff", "log", "push", "rev-parse", "show", "status", "switch", "worktree"]);
/** Source with `//` line comments and block comments removed (a commented-out literal must not satisfy a pin). */
const stripComments = (src: string): string =>
  ts.transpileModule(src, { compilerOptions: { removeComments: true, target: ts.ScriptTarget.ESNext } }).outputText;

interface Classified {
  executed: { path: string; source: string }[];
  allWritable: string[];
  unclassified: string[];
}

/** Classify each allowlist line by SHAPE (never by cron name). */
function classifyLines(cron: string, lines: string[], cronSource: string): Classified {
  const out: Classified = { executed: [], allWritable: [], unclassified: [] };
  for (const line of lines) {
    if (DIRECTIVE.test(line)) continue;
    const t = line.split(/\s+/);
    const head = t[0];
    if (head === "gh") {
      const known = GH_KNOWN[t[1] ?? ""];
      if (known === "any" || (known && known.has(t[2] ?? ""))) continue; // judged by decide() through the probe forms
      out.unclassified.push(`${line} (gh subcommand not in GH_KNOWN)`);
      continue;
    }
    if (head === "git") {
      if (GIT_KNOWN.has(t[1] ?? "")) continue;
      out.unclassified.push(`${line} (git subcommand not in GIT_KNOWN)`);
      continue;
    }
    if (head === "bash" || head === "sh") {
      const script = t[1] ?? "";
      if (!script.startsWith(ROOT + "/")) {
        out.allWritable.push(`${line} (bash of a non-plugin-root path)`);
        continue;
      }
      out.executed.push({ path: script, source: `allowlist line \`${line}\`` });
      if (/worktree-manager\.sh$/.test(script) && !/SOLEUR_WORKTREE_SKIP_INSTALL:\s*"1"/.test(stripComments(cronSource))) {
        out.allWritable.push(`${line} (worktree create runs install_deps: set SOLEUR_WORKTREE_SKIP_INSTALL=1 in ${cron}'s spawn env)`);
      }
      continue;
    }
    if (head.startsWith("./node_modules/.bin/") || head.includes("/node_modules/.bin/")) {
      out.allWritable.push(`${line} (node_modules binary)`);
      continue;
    }
    if (INSTALLERS.has(head) || INTERPRETERS.has(head)) {
      out.allWritable.push(`${line} (interpreter or installer)`);
      continue;
    }
    out.unclassified.push(line);
  }
  return out;
}

/**
 * MCP server `command` values a cron writes into its MCP overlay, from comment-stripped source. A `command:` whose
 * value is not a plain string literal (an identifier, a template, a call) is returned as null: the census cannot
 * judge it, so it is reported rather than skipped.
 */
function mcpCommands(src: string): (string | null)[] {
  // #12847 fix round — an AST walk, so a quoted key (`"command": "npx"`) and a commented-out literal
  // are seen for what they are; a regex over source saw neither.
  const sf = ts.createSourceFile("cron.ts", src, ts.ScriptTarget.Latest, true);
  const out: (string | null)[] = [];
  const keyName = (n: ts.PropertyName): string | null =>
    ts.isIdentifier(n) || ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n) ? n.text : null;
  const visit = (n: ts.Node, inMcp: boolean): void => {
    if (ts.isPropertyAssignment(n)) {
      const k = keyName(n.name);
      if (k === "mcpServers") return ts.forEachChild(n, (c) => visit(c, true));
      if (inMcp && k === "command") {
        const v = n.initializer;
        out.push(ts.isStringLiteral(v) || ts.isNoSubstitutionTemplateLiteral(v) ? v.text : null);
        return;
      }
    }
    ts.forEachChild(n, (c) => visit(c, inMcp));
  };
  visit(sf, false);
  return out;
}

/** The `--mcp-config` file a cron's flags name, resolved against the spawn cwd (null when none). */
function mcpConfigPath(src: string): string | null {
  const m = /"--mcp-config",\s*"([^"]+)"/.exec(stripComments(src));
  return m ? resolve(SPAWN_CWD, m[1]) : null;
}

interface Finding {
  cron: string;
  path: string;
  source: string;
  route: string;
}

function census(fn: DecideFn = realDecide): { findings: Finding[]; allWritable: string[]; unclassified: string[] } {
  const findings: Finding[] = [];
  const allWritable: string[] = [];
  const unclassified: string[] = [];
  for (const [file, { cronName, loadPlugin }] of Object.entries(POPULATION)) {
    const src = readFileSync(join(SERVER, file), "utf-8");
    const lines = buildAllowlistLines(cronName, CRON_BASH_ALLOWLISTS[cronName] ?? [], ENV, ROOT).lines;
    const c = classifyLines(cronName, lines, src);
    allWritable.push(...c.allWritable.map((x) => `${cronName}: ${x}`));
    unclassified.push(...c.unclassified.map((x) => `${cronName}: ${x}`));
    const executed = [...c.executed];
    // (1) argv
    const argv = buildClaudeArgv(loadPlugin ? ROOT : null, { flags: ["--print", "--"], prompt: "p", budget: [] });
    const i = argv.indexOf("--plugin-dir");
    if (i !== -1) {
      for (const rel of ["hooks/hooks.json", ".claude-plugin/plugin.json", "skills/x/SKILL.md", "agents/x.md"]) {
        executed.push({ path: join(argv[i + 1], rel), source: "argv --plugin-dir" });
      }
    }
    // (3) hook commands, both frameGhOutput values
    for (const frameGhOutput of [false, true]) {
      const settings = buildCronEvalSettings(SPAWN_CWD, { frameGhOutput }) as {
        hooks: Record<string, { hooks: { command: string }[] }[]>;
      };
      for (const entries of Object.values(settings.hooks)) {
        for (const e of entries) {
          for (const h of e.hooks) {
            for (const tok of h.command.split(" ").filter((x) => x.startsWith("/"))) {
              executed.push({ path: tok, source: `hook command (frameGhOutput=${frameGhOutput})` });
            }
          }
        }
      }
    }
    // (4) MCP server commands, and the MCP config file the CLI reads them from
    const cfg = mcpConfigPath(src);
    if (cfg) executed.push({ path: cfg, source: "--mcp-config file (names the commands the CLI launches)" });
    for (const cmd of mcpCommands(src)) {
      if (cmd === null) {
        allWritable.push(`${cronName}: an MCP \`command:\` that is not a string literal (the census cannot judge it)`);
        continue;
      }
      if (!cmd.startsWith("/")) {
        allWritable.push(`${cronName}: MCP command \`${cmd}\` is resolved through PATH/npx, not an absolute image path`);
        continue;
      }
      executed.push({ path: cmd, source: "MCP server command" });
    }
    const exempt = new Set((EXEMPTIONS[cronName] ?? []).map((x) => x.path));
    const seen = new Set<string>();
    for (const { path, source } of executed) {
      if (seen.has(path)) continue;
      seen.add(path);
      const route = writeRoute(fn, lines, path);
      if (route && !exempt.has(path)) findings.push({ cron: cronName, path, source, route });
    }
  }
  return { findings, allWritable, unclassified };
}

const FIXES =
  "Fixes, in order: (1) write the allowlist line as `bash <plugin-root>/…` (the read-only root); (2) add a " +
  "WRITE_PROTECTED_PATTERNS entry in cron-bash-allowlist-hook.mjs; (3) only then an EXEMPTIONS entry naming an " +
  "open issue (cron-write-execute-census.test.ts EXEMPTIONS).";
const show = (fs: Finding[]) =>
  fs.map((f) => `${f.cron}: ${f.path} — executed via ${f.source}; writable via \`${f.route}\``).join("\n") + `\n${FIXES}`;

// ---- the rows -------------------------------------------------------------------------------------------------

describe("Guard 1 — population (identity map)", () => {
  const d = discover();

  it("every reference to spawnClaudeEval is a direct call (no alias, re-export or value pass)", () => {
    expect(d.strayRefs, "call spawnClaudeEval directly so the census can see the call site").toEqual([]);
  });

  it("the discovered call sites equal the stored identity map (non-vacuous)", () => {
    expect(d.calls.length).toBeGreaterThanOrEqual(18);
    const actual = Object.fromEntries(d.calls.map((c) => [c.file, { cronName: c.cronName, loadPlugin: c.loadPlugin }]));
    expect(new Set(d.calls.map((c) => c.file)).size, "one spawnClaudeEval call per file").toBe(d.calls.length);
    expect(actual, "a new or renamed call site: add `file → { cronName, loadPlugin }` to POPULATION").toEqual(POPULATION);
  });

  it("CRON_PLUGIN_LOADERS (setup resolves the root for these) equals the loadPlugin:true call sites", () => {
    const loaders = Object.values(POPULATION).filter((p) => p.loadPlugin).map((p) => p.cronName).sort();
    expect([...CRON_PLUGIN_LOADERS].sort()).toEqual(loaders);
  });

  it("every cron whose prompt invokes a /soleur: skill is in CRON_PLUGIN_LOADERS (AC8 survivor G1-12b)", () => {
    // #12847 fix round — any position (`Run /soleur:x`), not only after a quote, which matched 1 of 12.
    const invokes = Object.entries(POPULATION)
      .filter(([file]) => /(?:^|[\s`"'(])\/soleur:[a-z][a-z-]*/m.test(stripComments(readFileSync(join(SERVER, file), "utf-8"))))
      .map(([, p]) => p.cronName)
      .sort();
    expect(invokes.length).toBeGreaterThanOrEqual(11); // non-vacuous: the regex finds the skill-running crons
    for (const name of invokes) expect(CRON_PLUGIN_LOADERS.has(name), `${name} invokes a /soleur: skill`).toBe(true);
  });

  it("an MCP `command` is read by key, quoted or not, and a commented-out literal does not count", () => {
    expect(mcpCommands('const c = { mcpServers: { p: { "command": "npx", args: [] } } };')).toEqual(["npx"]);
    expect(mcpCommands('const c = { mcpServers: { p: { command: CMD } } }; // command: "/abs"')).toEqual([null]);
    expect(mcpCommands("const c = { other: { command: \"x\" } };")).toEqual([]);
    // The real overlay yields its one command (a shorthand or computed key would yield none and fail here).
    expect(mcpCommands(readFileSync(join(SERVER, "inngest/functions/cron-ux-audit.ts"), "utf-8"))).toEqual([
      "/app/node_modules/.bin/playwright-mcp",
    ]);
  });

  it("an unknown gh/git subcommand is UNCLASSIFIED (negative control for GH_KNOWN / GIT_KNOWN)", () => {
    const c = classifyLines("cron-x", ["gh extension install x/y", "git rebase -x sh", "gh issue list", "gh pr checkout 1"], "");
    expect(c.unclassified).toHaveLength(3); // `gh pr checkout`: a known group, an unknown verb
    expect(c.unclassified.join("\n")).toMatch(/gh extension install/);
    expect(c.unclassified.join("\n")).toMatch(/git rebase/);
  });

  it("every allowlist key is a spawning cron, and setupEphemeralWorkspace uses the same cronName as the spawn", () => {
    const crons = new Set(Object.values(POPULATION).map((p) => p.cronName));
    for (const key of Object.keys(CRON_BASH_ALLOWLISTS)) expect(crons.has(key), `allowlist key ${key}`).toBe(true);
    for (const [file, { cronName }] of Object.entries(POPULATION)) {
      const sf = ts.createSourceFile(file, readFileSync(join(SERVER, file), "utf-8"), ts.ScriptTarget.Latest, true);
      const names: (string | null)[] = [];
      const visit = (n: ts.Node): void => {
        const callee = ts.isCallExpression(n)
          ? ts.isIdentifier(n.expression)
            ? n.expression.text
            : ts.isPropertyAccessExpression(n.expression)
              ? n.expression.name.text
              : null
          : null;
        if (ts.isCallExpression(n) && callee === "setupEphemeralWorkspace") {
          const arg = n.arguments[0];
          let name: string | null = null;
          if (arg && ts.isObjectLiteralExpression(arg)) {
            for (const prop of arg.properties) {
              if (ts.isPropertyAssignment(prop) && ts.isIdentifier(prop.name) && prop.name.text === "cronName")
                name = stringValue(sf, prop.initializer);
            }
          }
          names.push(name);
        }
        ts.forEachChild(n, visit);
      };
      visit(sf);
      for (const n of names) expect(n, `${file}: setupEphemeralWorkspace cronName`).toBe(cronName);
      // Each clone-based cron calls it at least once (an aliased call would hide from this walk); the
      // two server-cwd crons clone nothing.
      if (!SERVER_CWD_CRONS.has(cronName)) expect(names.length, `${file}: setupEphemeralWorkspace call`).toBeGreaterThanOrEqual(1);
    }
  });

  it("every plugin-loading cron judged by its output passes the reseed flag; community-monitor applies it (#12847)", () => {
    const src = (f: string) => stripComments(readFileSync(join(SERVER, f), "utf-8"));
    const outputAware = Object.entries(POPULATION).filter(
      ([f, p]) => CRON_PLUGIN_LOADERS.has(p.cronName) && /resolveOutputAwareOk\(/.test(src(f)),
    );
    expect(outputAware.map(([, p]) => p.cronName).sort()).toHaveLength(7);
    for (const [f] of outputAware) expect(src(f), f).toMatch(/pluginReseeded: spawnResult!?\.pluginReseeded/);
    expect(src("inngest/functions/cron-community-monitor.ts")).toMatch(/if \(spawnResult\?\.pluginReseeded\)\s*heartbeatOk = false;/);
  });

  it("every call passes loadPlugin as a boolean LITERAL and the flags carry no --plugin-dir", () => {
    for (const c of d.calls) expect(typeof c.loadPlugin, `${c.file}: loadPlugin must be a literal true/false`).toBe("boolean");
    for (const file of Object.keys(POPULATION)) {
      const flags = /const CLAUDE_CODE_FLAGS[^=]*=\s*\[([\s\S]*?)\];/.exec(readFileSync(join(SERVER, file), "utf-8"));
      expect(flags?.[1] ?? "", file).not.toMatch(/"--plugin-dir/);
    }
  });
});

describe("Guard 1 — write-and-execute (AC7, AC18)", () => {
  it("no cron can write a path it executes", () => {
    const { findings } = census();
    expect(findings, show(findings)).toEqual([]);
  });

  it("the all-writable set is empty: no cron holds an arbitrary-exec allowlist line", () => {
    expect(census().allWritable).toEqual([]);
  });

  it("no allowlist line falls outside a known shape (UNCLASSIFIED is red)", () => {
    expect(census().unclassified).toEqual([]);
  });

  it("the exemption map is empty (any entry is a review finding)", () => {
    expect(EXEMPTIONS).toEqual({});
  });

  it("no built allowlist line names the clone's plugin tree or carries the token or `$` (AC6)", () => {
    for (const { cronName } of Object.values(POPULATION)) {
      for (const l of buildAllowlistLines(cronName, CRON_BASH_ALLOWLISTS[cronName] ?? [], ENV, ROOT).lines) {
        expect(l, cronName).not.toMatch(/(^|\s)plugins\/soleur\//);
        expect(l, cronName).not.toContain(PLUGIN_ROOT_TOKEN);
        expect(l, cronName).not.toContain("$");
      }
    }
    for (const cron of ["cron-bug-fixer", "cron-community-monitor"]) {
      const scripts = buildAllowlistLines(cron, CRON_BASH_ALLOWLISTS[cron], ENV, ROOT).lines.filter((l) => l.startsWith("bash "));
      expect(scripts.length, cron).toBeGreaterThan(0);
      for (const l of scripts) expect(l.startsWith("bash /app/shared/plugins/soleur/"), l).toBe(true);
    }
  });

  it("AC19: bug-fixer has no node_modules binary and sets SOLEUR_WORKTREE_SKIP_INSTALL=1", () => {
    expect(CRON_BASH_ALLOWLISTS["cron-bug-fixer"].some((l) => l.includes("node_modules/.bin/"))).toBe(false);
    expect(readFileSync(join(FN_DIR, "cron-bug-fixer.ts"), "utf-8")).toMatch(/SOLEUR_WORKTREE_SKIP_INSTALL:\s*"1"/);
  });

  it("every spawn env PATH is the server's own (no cron prepends a clone or HOME directory)", () => {
    for (const file of Object.keys(POPULATION)) {
      const src = readFileSync(join(SERVER, file), "utf-8");
      for (const m of src.matchAll(/^\s*PATH:\s*([^,\n]+),/gm)) expect(m[1].trim(), file).toBe("process.env.PATH");
    }
    const substrate = readFileSync(join(FN_DIR, "_cron-claude-eval-substrate.ts"), "utf-8");
    expect(substrate).not.toMatch(/^\s*PATH:/m);
  });
});

describe("Guard 1 — anchor", () => {
  it("the plugin root the producers use is the `:ro` mount target (docker-run-tuple.test.sh pins the `:ro`)", () => {
    expect(ROOT).toBe("/app/shared/plugins/soleur");
    const tuple = readFileSync(join(APP, "infra/lib/docker-run-tuple.py"), "utf-8");
    expect(tuple).toContain(`:${ROOT}:ro"`);
  });
});

describe("Guard 1 — write confinement probes through the real decide() (CTO S1, AC20)", () => {
  const lines = buildAllowlistLines("cron-bug-fixer", CRON_BASH_ALLOWLISTS["cron-bug-fixer"], ENV, ROOT).lines;
  const verdict = (p: string, roots: string[] | null = ROOTS) =>
    realDecide({ tool_name: "Write", tool_input: { file_path: p } }, lines, roots ? { writeRoots: roots } : {})
      .hookSpecificOutput.permissionDecision;

  it.each([
    "/app/.next/server/x.js",
    "/home/soleur/.bashrc",
    "/workspaces/0b1c2d3e-0000-4000-8000-000000000000/x",
    join(BASE, "soleur-cron-y-BBB", "repo", "x"),
    "/opt/soleur/plugin/x",
    join(ROOT, "hooks", "x.sh"),
    join(SPAWN_CWD, "..", "outside"),
  ])("denies a write to %s", (p) => {
    expect(verdict(p)).toBe("deny");
  });

  it("allows the run's own clone and the spawn TMPDIR (<HOME>/tmp)", () => {
    expect(ROOTS).toEqual([SPAWN_CWD, join(HOME, "tmp")]);
    expect(verdict(join(SPAWN_CWD, "x"))).toBe("allow");
    expect(verdict(join(HOME, "tmp", "x"))).toBe("allow");
  });

  // #12847 review (security P1) — HOME is not a write root: programs the allowlists run read their config from it,
  // so a writable HOME is a write-then-execute path that names no file in any allowlist line.
  it.each([
    [".config/gh/config.yml", "gh: the browser / editor / pager it launches"],
    [".curlrc", "curl: proxy, output and config options"],
    [".gitconfig", "git: aliases, hooks, pager"],
    [".claude.json", "claude CLI: per-user state and MCP servers"],
    ["x", "any other file in HOME"],
  ])("denies a write to $HOME/%s (%s)", (rel) => {
    expect(verdict(join(HOME, rel))).toBe("deny");
  });

  it("denies a write through an in-clone symlink that points outside the roots (AC8 row 15)", () => {
    const outside = join(BASE, "outside-target");
    mkdirSync(outside, { recursive: true });
    const link = join(SPAWN_CWD, "out-link");
    if (!existsSync(link)) symlinkSync(outside, link);
    expect(verdict(join(link, "x"))).toBe("deny");
  });

  it("denies a sibling whose name starts with a root's name (repo-evil, home-abc123x)", () => {
    expect(verdict(join(EPHEMERAL, "repo-evil", "x"))).toBe("deny");
    expect(verdict(join(EPHEMERAL, "home-abc123x", "tmp", "x"))).toBe("deny");
    expect(verdict(join(HOME, "tmp-evil", "x"))).toBe("deny"); // extends the TMPDIR root's name
  });

  it("a HOME that is not a home-* child of dirname(spawnCwd) does not widen the area", () => {
    for (const home of ["/", "/tmp", join(BASE, "elsewhere", "home-abc"), join(EPHEMERAL, "notahome")]) {
      expect(deriveWriteRoots(SPAWN_CWD, home), home).toEqual([SPAWN_CWD]);
    }
    expect(verdict("/etc/x", deriveWriteRoots(SPAWN_CWD, "/") as string[])).toBe("deny");
  });
});

describe("Guard 1 — harness", () => {
  it("H1: a deny-everything decide() fails the known-writable control (the census measures decide(), not a constant)", () => {
    const control = join(SPAWN_CWD, "src", "x.ts");
    const lines = buildAllowlistLines("cron-bug-fixer", CRON_BASH_ALLOWLISTS["cron-bug-fixer"], ENV, ROOT).lines;
    expect(writeRoute(realDecide, lines, control)).not.toBeNull();
    const denyAll: DecideFn = () => ({ hookSpecificOutput: { permissionDecision: "deny" } });
    expect(writeRoute(denyAll, lines, control)).toBeNull();
  });

  it("H1b: an allow-everything decide() makes the census red (it is not vacuously green)", () => {
    const allowAll: DecideFn = () => ({ hookSpecificOutput: { permissionDecision: "allow" } });
    expect(census(allowAll).findings.length).toBeGreaterThan(0);
  });

  it("H3: a cron holding only `gh issue view` and loading no plugin classifies clean", () => {
    const c = classifyLines("x", ["gh issue view"], "");
    expect(c).toEqual({ executed: [], allWritable: [], unclassified: [] });
  });

  it("H4/row 17: a worktree line without SOLEUR_WORKTREE_SKIP_INSTALL=1 is all-writable; with it, clean", () => {
    const line = `bash ${ROOT}/skills/git-worktree/scripts/worktree-manager.sh`;
    expect(classifyLines("x", [line], "").allWritable.length).toBe(1);
    expect(classifyLines("x", [line], 'SOLEUR_WORKTREE_SKIP_INSTALL: "1",').allWritable).toEqual([]);
  });

  it("shape classes: node_modules binary, interpreter, non-root bash are all-writable; an unknown verb is UNCLASSIFIED", () => {
    expect(classifyLines("x", ["./node_modules/.bin/vitest run"], "").allWritable.length).toBe(1);
    expect(classifyLines("x", ["node scripts/x.js"], "").allWritable.length).toBe(1);
    expect(classifyLines("x", ["bash plugins/soleur/skills/x/y.sh"], "").allWritable.length).toBe(1);
    expect(classifyLines("x", ["python3 scripts/x.py"], "").allWritable.length).toBe(1);
    expect(classifyLines("x", ["make build"], "").unclassified).toEqual(["make build"]);
  });
});

describe("Guard 1 — vendored-file coverage (CTO T2)", () => {
  it("every non-vendored script a plugin-loading cron's skill names has a disposition, and every disposition matches", () => {
    const misses = new Set<string>();
    for (const [file, { loadPlugin }] of Object.entries(POPULATION)) {
      if (!loadPlugin) continue;
      const code = readFileSync(join(SERVER, file), "utf-8")
        .split("\n")
        .filter((l) => !l.trim().startsWith("//"))
        .join("\n");
      for (const [, skill] of code.matchAll(/\/soleur:([a-z-]+)/g)) {
        let md: string;
        try {
          md = readFileSync(join(REPO, "plugins/soleur/skills", skill, "SKILL.md"), "utf-8");
        } catch {
          continue;
        }
        for (const [ref] of md.matchAll(/[A-Za-z0-9_.${}/-]*scripts\/[A-Za-z0-9_./-]+\.[a-z]+/g)) {
          const ext = ref.slice(ref.lastIndexOf(".") + 1);
          if (!VENDORED_EXTENSIONS.has(ext)) misses.add(`${skill} ${ref}`);
        }
      }
    }
    expect([...misses].sort(), "a new non-vendored script: degrade it in the skill, then add a disposition").toEqual(
      Object.keys(VENDORED_MISS_DISPOSITIONS).sort(),
    );
  });

  it("the vendored extension set matches .dockerignore's re-include list", () => {
    const di = readFileSync(join(APP, ".dockerignore"), "utf-8");
    const exts = [...di.matchAll(/^!_plugin-vendored\/\*\*\/\*\.([a-z]+)$/gm)].map((m) => m[1]).sort();
    expect(exts).toEqual([...VENDORED_EXTENSIONS].sort());
  });
});
