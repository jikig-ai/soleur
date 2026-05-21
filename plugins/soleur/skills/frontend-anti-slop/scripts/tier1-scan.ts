#!/usr/bin/env bun
/**
 * tier1-scan.ts — deterministic regex audit for React/Next.js anti-slop patterns.
 *
 * Adapted from Hallmark's `slop-test.md` Tier 1 gates (MIT, see /LICENSES/hallmark.MIT.txt).
 * Rules live in `../references/slop-rules.md`; this script parses the Active-rules
 * markdown table, filters `tier === 1`, and runs each rule's `pattern` regex over
 * the target files.
 *
 * Usage:
 *   bun plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts \
 *     [--paths <file-or-glob> ...] [--dry-run|--json] [--rule <id>]
 *
 * Default paths: `git diff --name-only --cached --diff-filter=AMR` filtered to
 * `apps/web-platform/(app|components)/**\*.(tsx|jsx|css)`.
 *
 * Output:
 *   - `--dry-run` (default) — human-readable findings on stdout.
 *   - `--json` — JSON array conforming to `finding.schema.json` with
 *     `category: "anti-slop"`, `selector: "<file-path>#<rule-id>"`,
 *     `route: ""`.
 *
 * Exit codes:
 *   0 — scan completed (regardless of finding count; non-blocking by design).
 *   1 — bad CLI / parse error / IO error.
 *
 * Per-file rule disable: `<!-- anti-slop:disable RULE_ID reason="..." -->`.
 */

import {
  readFileSync,
  existsSync,
  statSync,
  lstatSync,
  readdirSync,
} from "node:fs";
import { resolve, relative, join } from "node:path";

const TC_VERSION = "1.0.0";

function gitRepoRoot(): string {
  // Use Bun.spawnSync (no shell expansion, argv-array form — no command-injection
  // surface). Falls back to cwd if not in a git repo.
  try {
    const p = Bun.spawnSync(["git", "rev-parse", "--show-toplevel"], {
      stdout: "pipe",
      stderr: "pipe",
    });
    if (p.exitCode === 0) {
      return new TextDecoder().decode(p.stdout).trim();
    }
  } catch {
    /* fall through */
  }
  return process.cwd();
}

const REPO_ROOT = gitRepoRoot();

const RULES_FILE = resolve(
  import.meta.dir,
  "..",
  "references",
  "slop-rules.md",
);

interface Rule {
  id: string;
  tier: 1 | 2;
  category: string;
  severity: "critical" | "high" | "medium" | "low";
  pattern: RegExp;
  message: string;
  suggested_fix: string;
  /** UNIFORM-HOVER-SCALE-style rules fire only at ≥ N occurrences in a single file. */
  min_occurrences?: number;
}

interface Finding {
  route: string;
  selector: string;
  category: "anti-slop";
  severity: Rule["severity"];
  title: string;
  description: string;
  fix_hint: string;
  screenshot_ref: string;
  line: number;
}

interface CliArgs {
  paths: string[];
  json: boolean;
  ruleFilter?: string;
}

function parseArgs(argv: string[]): CliArgs {
  const out: CliArgs = { paths: [], json: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--paths") {
      while (i + 1 < argv.length && !argv[i + 1].startsWith("--")) {
        out.paths.push(argv[++i]);
      }
    } else if (a === "--json") {
      out.json = true;
    } else if (a === "--dry-run") {
      out.json = false;
    } else if (a === "--rule") {
      out.ruleFilter = argv[++i];
    } else if (a === "-h" || a === "--help") {
      printHelp();
      process.exit(0);
    } else if (!a.startsWith("--")) {
      out.paths.push(a);
    } else {
      console.error(`unknown arg: ${a}`);
      process.exit(1);
    }
  }
  return out;
}

function printHelp(): void {
  console.log(
    "tier1-scan.ts — React/Next.js anti-slop deterministic audit (v" +
      TC_VERSION +
      ")",
  );
  console.log(
    "\nUsage: bun .../tier1-scan.ts [--paths <file>...] [--dry-run|--json] [--rule <id>]",
  );
}

/**
 * Parse the Active-rules table from references/slop-rules.md.
 *
 * Format: standard GitHub-flavoured Markdown pipe table. Header row is
 * `| id | tier | category | hallmark_gate | severity | pattern | message | suggested_fix |`.
 * Each data row contributes one Rule; `pattern` is unwrapped from backticks and
 * compiled as a RegExp.
 */
function parseRules(content: string): Rule[] {
  const lines = content.split("\n");
  const rules: Rule[] = [];

  let inActiveTable = false;
  let headerSeen = false;

  for (const line of lines) {
    if (line.trim().startsWith("## Active rules")) {
      inActiveTable = true;
      continue;
    }
    if (inActiveTable && line.trim().startsWith("## ")) {
      // hit the next section — stop
      break;
    }
    if (!inActiveTable) continue;

    if (line.startsWith("| id |")) {
      headerSeen = true;
      continue;
    }
    if (!headerSeen) continue;
    if (line.startsWith("|---")) continue;
    if (!line.startsWith("|")) continue;

    // Split on unescaped `|` only — markdown table cells escape literal pipes
    // (used inside regex alternations) as `\|`. After splitting, unescape.
    const cells = line
      .split(/(?<!\\)\|/)
      .slice(1, -1)
      .map((c) => c.trim().replace(/\\\|/g, "|"));
    if (cells.length < 8) continue;

    const [
      id,
      tierRaw,
      category,
      _hallmark,
      severityRaw,
      patternRaw,
      message,
      fix,
    ] = cells;
    const tier = Number(tierRaw) as 1 | 2;
    if (tier !== 1) continue;

    const patternBody = unwrapBackticks(patternRaw);
    let regex: RegExp;
    try {
      regex = new RegExp(patternBody);
    } catch (err) {
      throw new Error(
        `invalid regex for rule ${id}: ${patternBody} (${(err as Error).message})`,
      );
    }

    const rule: Rule = {
      id,
      tier,
      category,
      severity: severityRaw as Rule["severity"],
      pattern: regex,
      message: unwrapBackticks(message),
      suggested_fix: unwrapBackticks(fix),
    };
    if (id === "UNIFORM-HOVER-SCALE") rule.min_occurrences = 4;

    rules.push(rule);
  }

  if (rules.length === 0) {
    throw new Error(
      `parseRules: no Tier-1 rules parsed from ${RULES_FILE} — table format drift`,
    );
  }
  return rules;
}

function unwrapBackticks(s: string): string {
  // Markdown table cells often have leading/trailing backticks (code spans).
  // Strip a single pair if present.
  if (s.startsWith("`") && s.endsWith("`") && s.length >= 2) {
    return s.slice(1, -1);
  }
  return s;
}

function defaultPaths(): string[] {
  try {
    const p = Bun.spawnSync(
      ["git", "diff", "--name-only", "--cached", "--diff-filter=AMR"],
      { cwd: REPO_ROOT, stdout: "pipe", stderr: "pipe" },
    );
    if (p.exitCode !== 0) return [];
    const out = new TextDecoder().decode(p.stdout);
    const all = out
      .split("\n")
      .map((p) => p.trim())
      .filter(Boolean);
    return all.filter((p) =>
      /^apps\/web-platform\/(app|components)\/.*\.(tsx|jsx|css)$/.test(p),
    );
  } catch {
    return [];
  }
}

function isContainedInRepo(abs: string): boolean {
  // Containment check: the resolved path must live under REPO_ROOT.
  // `relative` returns "" when abs === REPO_ROOT, an absolute path on
  // Windows-different-drive (defensive — Linux-only here), or a path
  // starting with ".." when abs is outside REPO_ROOT.
  const rel = relative(REPO_ROOT, abs);
  if (rel === "" || rel.startsWith("..") || rel.startsWith("/")) return false;
  return true;
}

function expandPaths(inputs: string[]): string[] {
  // Caller may pass repo-relative paths OR abs paths. Normalise to absolute,
  // confine to REPO_ROOT, reject symlinks (no traversal via symlink chain),
  // then keep only existing files matching the frontend glob. No glob
  // expansion here — the shell already expanded any literal `*`; callers
  // passing dir paths get all child .tsx/.jsx/.css.
  const out: string[] = [];
  for (const p of inputs) {
    const abs = resolve(REPO_ROOT, p);
    if (!isContainedInRepo(abs)) continue;
    if (!existsSync(abs)) continue;
    // `lstatSync` (not `statSync`) so we see the symlink itself, not its
    // target. Symlinks under the repo pointing outside (or to sensitive
    // files) are rejected here.
    const ls = lstatSync(abs);
    if (ls.isSymbolicLink()) continue;
    const s = statSync(abs);
    if (s.isFile()) {
      if (/\.(tsx|jsx|css)$/.test(abs)) out.push(abs);
    } else if (s.isDirectory()) {
      out.push(
        ...listFilesRecursive(abs).filter((f) =>
          /\.(tsx|jsx|css)$/.test(f),
        ),
      );
    }
  }
  return out;
}

function listFilesRecursive(dir: string): string[] {
  const acc: string[] = [];
  const stack = [dir];
  while (stack.length) {
    const d = stack.pop()!;
    let entries;
    try {
      entries = readdirSync(d, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      const full = join(d, e.name);
      // Symlinks rejected — same containment posture as `expandPaths`,
      // so a recursive walk cannot escape the repo via a symlinked
      // subdirectory or grab a sensitive file via a symlinked entry.
      if (e.isSymbolicLink()) continue;
      if (e.isDirectory()) {
        if (e.name === "node_modules" || e.name === ".next") continue;
        stack.push(full);
      } else if (e.isFile()) {
        acc.push(full);
      }
    }
  }
  return acc;
}

function disabledRulesInFile(content: string): Set<string> {
  const out = new Set<string>();
  const re = /<!--\s*anti-slop:disable\s+([A-Z][A-Z0-9-]*)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(content)) !== null) out.add(m[1]);
  return out;
}

function scanFile(absPath: string, rules: Rule[]): Finding[] {
  let content: string;
  try {
    content = readFileSync(absPath, "utf8");
  } catch (err) {
    console.error(
      `[tier1-scan] read failed: ${absPath} (${(err as Error).message})`,
    );
    return [];
  }

  const relPath = relative(REPO_ROOT, absPath);
  const lines = content.split("\n");
  const disabled = disabledRulesInFile(content);
  const findings: Finding[] = [];

  for (const rule of rules) {
    if (disabled.has(rule.id)) continue;

    const hitLines: number[] = [];
    for (let i = 0; i < lines.length; i++) {
      if (rule.pattern.test(lines[i])) hitLines.push(i + 1);
    }
    if (hitLines.length === 0) continue;
    if (
      rule.min_occurrences !== undefined &&
      hitLines.length < rule.min_occurrences
    ) {
      continue;
    }

    findings.push({
      route: "",
      selector: `${relPath}#${rule.id}`,
      category: "anti-slop",
      severity: rule.severity,
      title: `${rule.message} (rule ${rule.id})`,
      description: `${rule.message} Detected at ${relPath}:${hitLines[0]}${
        hitLines.length > 1 ? ` (and ${hitLines.length - 1} more)` : ""
      }.`,
      fix_hint: rule.suggested_fix,
      screenshot_ref: "/tmp/anti-slop/no-screenshot.png",
      line: hitLines[0],
    });
  }
  return findings;
}

function formatHuman(findings: Finding[]): string {
  if (findings.length === 0) return "anti-slop: no findings.\n";
  const lines: string[] = [`anti-slop: ${findings.length} finding(s)\n`];
  for (const f of findings) {
    lines.push(
      `  [${f.severity.padEnd(8)}] ${f.selector}:${f.line}\n    ${f.title}\n    fix: ${f.fix_hint}\n`,
    );
  }
  return lines.join("");
}

function main() {
  const args = parseArgs(process.argv.slice(2));

  let rules: Rule[];
  try {
    rules = parseRules(readFileSync(RULES_FILE, "utf8"));
  } catch (err) {
    console.error(`[tier1-scan] ${(err as Error).message}`);
    process.exit(1);
  }

  if (args.ruleFilter) {
    rules = rules.filter((r) => r.id === args.ruleFilter);
    if (rules.length === 0) {
      console.error(
        `[tier1-scan] --rule ${args.ruleFilter} matched zero rules`,
      );
      process.exit(1);
    }
  }

  const candidatePaths =
    args.paths.length > 0
      ? expandPaths(args.paths)
      : expandPaths(defaultPaths());

  if (candidatePaths.length === 0) {
    if (args.json) {
      process.stdout.write("[]\n");
    } else {
      process.stdout.write(
        "anti-slop: no frontend files in scope; skipping scan.\n",
      );
    }
    process.exit(0);
  }

  const findings: Finding[] = [];
  for (const file of candidatePaths) {
    findings.push(...scanFile(file, rules));
  }

  if (args.json) {
    // Emit machine-readable shape (drop the `line` field — not in finding.schema.json).
    const emit = findings.map(({ line: _line, ...rest }) => rest);
    process.stdout.write(JSON.stringify(emit, null, 2) + "\n");
  } else {
    process.stdout.write(formatHuman(findings));
  }
  process.exit(0);
}

if (import.meta.main) {
  main();
}

export {
  parseRules,
  scanFile,
  disabledRulesInFile,
  expandPaths,
  defaultPaths,
  unwrapBackticks,
  REPO_ROOT,
  RULES_FILE,
};
export type { Rule, Finding };
