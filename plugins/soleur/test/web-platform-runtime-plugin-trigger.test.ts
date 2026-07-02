// Behavioral drift-guard for the runtime-plugin deploy gap
// (knowledge-base/project/plans/2026-07-02-fix-runtime-plugin-deploy-to-concierge-host-plan.md).
//
// Root cause: a runtime-affecting plugins/soleur/** merge never rebuilt+deployed
// the web-platform image, so the Concierge host mount kept running stale plugin
// components. The fix widens TWO gates:
//   (1) outer  on.push.paths in web-platform-release.yml   (Actions glob dialect)
//   (2) inner  check_changed  in reusable-release.yml       (git-pathspec dialect)
//
// This test proves the INNER gate BEHAVIORALLY: it extracts the byte-identical
// `check_changed` bash from reusable-release.yml AND the exact `path_filter`
// value passed by web-platform-release.yml, then runs the script (same shell
// flags) against synthesized git diffs. It is deliberately NOT a cross-dialect
// string comparison (spec-flow G6) — the outer `**` and inner `/` dialects are
// intentionally different, so we assert the outer gate with a targeted grep only.
//
// Non-vacuity: with the un-widened workflow (path_filter="apps/web-platform/",
// quoted single pathspec) every plugins/** row yields changed=false and this
// suite goes RED. It only passes once BOTH gates are widened.
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).

import { describe, test, expect, beforeAll } from "bun:test";
import { resolve } from "path";
import { readFileSync, existsSync, mkdtempSync, mkdirSync, writeFileSync } from "fs";
import { execFileSync } from "child_process";
import { tmpdir } from "os";
import { dirname, join } from "path";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const REUSABLE = resolve(REPO_ROOT, ".github/workflows/reusable-release.yml");
const WEBPLAT = resolve(REPO_ROOT, ".github/workflows/web-platform-release.yml");

// ── Extract the byte-identical check_changed run: block from reusable-release.yml ──
// Find the step with `id: check_changed`, then its `run: |` scalar, then collect
// the block-indented body and dedent by the common leading whitespace.
function extractCheckChangedScript(yml: string): string {
  const idIdx = yml.indexOf("id: check_changed");
  if (idIdx === -1) throw new Error("id: check_changed step not found in reusable-release.yml");
  const runKey = yml.indexOf("run: |", idIdx);
  if (runKey === -1) throw new Error("run: | block for check_changed not found");
  // Indentation of the `run:` key (used to detect the end of the block scalar).
  const runLineStart = yml.lastIndexOf("\n", runKey) + 1;
  const runIndent = runKey - runLineStart;
  const afterRun = yml.indexOf("\n", runKey) + 1;
  const rest = yml.slice(afterRun).split("\n");
  const body: string[] = [];
  for (const line of rest) {
    if (line.trim() === "") {
      body.push(line);
      continue;
    }
    const indent = line.length - line.trimStart().length;
    // A non-empty line indented <= the `run:` key ends the block scalar (e.g. `env:`).
    if (indent <= runIndent) break;
    body.push(line);
  }
  // Trim trailing blank lines, then dedent by the minimum indent of non-blank lines.
  while (body.length && body[body.length - 1].trim() === "") body.pop();
  const minIndent = Math.min(
    ...body.filter((l) => l.trim() !== "").map((l) => l.length - l.trimStart().length),
  );
  return body.map((l) => l.slice(minIndent)).join("\n");
}

// Extract the path_filter value passed by web-platform-release.yml's release job.
function extractWebPlatPathFilter(yml: string): string {
  const m = yml.match(/^\s*path_filter:\s*"([^"]*)"/m);
  if (!m) throw new Error("path_filter value not found in web-platform-release.yml");
  return m[1];
}

// Extract the outer on.push.paths list (bound to the `on:` section).
function extractOnPushPaths(yml: string): string[] {
  const jobsIdx = yml.indexOf("\njobs:");
  const onSection = jobsIdx >= 0 ? yml.slice(0, jobsIdx) : yml;
  const pathsIdx = onSection.indexOf("paths:");
  if (pathsIdx === -1) return [];
  const block = onSection.slice(pathsIdx);
  // Inline list form: paths: ['a', 'b']
  const inline = block.match(/paths:\s*\[([^\]]*)\]/);
  if (inline) {
    return [...inline[1].matchAll(/'([^']+)'|"([^"]+)"/g)].map((x) => x[1] ?? x[2]);
  }
  // Block list form: one `- 'x'` per line until the next same/lower-indent key.
  const lines = block.split("\n").slice(1);
  const out: string[] = [];
  for (const line of lines) {
    const item = line.match(/^\s+-\s+'([^']+)'|^\s+-\s+"([^"]+)"/);
    if (item) {
      out.push(item[1] ?? item[2]);
      continue;
    }
    if (line.trim() === "") continue;
    // A non-list, non-blank line ends the paths block.
    if (!/^\s+-/.test(line)) break;
  }
  return out;
}

let GATE_SCRIPT: string;
let PATH_FILTER: string;
let ON_PUSH_PATHS: string[];

beforeAll(() => {
  for (const f of [REUSABLE, WEBPLAT]) {
    if (!existsSync(f)) throw new Error(`workflow not found: ${f}`);
  }
  GATE_SCRIPT = extractCheckChangedScript(readFileSync(REUSABLE, "utf8"));
  PATH_FILTER = extractWebPlatPathFilter(readFileSync(WEBPLAT, "utf8"));
  ON_PUSH_PATHS = extractOnPushPaths(readFileSync(WEBPLAT, "utf8"));
});

// Build a 2-commit git repo (HEAD~1 = empty base, HEAD = the changed paths),
// run the extracted gate against it with force_run=false, and return `changed`.
function runGate(changedPaths: string[]): string {
  const dir = mkdtempSync(join(tmpdir(), "deploygap-gate-"));
  const git = (args: string[]) =>
    execFileSync("git", ["-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false", ...args], {
      cwd: dir,
      stdio: "pipe",
    });
  git(["init", "-q"]);
  git(["commit", "-q", "--allow-empty", "-m", "base"]);
  for (const p of changedPaths) {
    const full = join(dir, p);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, `content for ${p}\n`);
  }
  git(["add", "-A"]);
  git(["commit", "-q", "-m", "change"]);
  const outFile = join(dir, ".ghoutput");
  writeFileSync(outFile, "");
  execFileSync("bash", ["-c", GATE_SCRIPT], {
    cwd: dir,
    stdio: "pipe",
    env: {
      ...process.env,
      FORCE_RUN: "false",
      PATH_FILTER,
      COMPONENT: "web-platform",
      GITHUB_OUTPUT: outFile,
    },
  });
  const out = readFileSync(outFile, "utf8");
  const m = out.match(/changed=(\w+)/);
  if (!m) throw new Error(`no changed= line in GITHUB_OUTPUT: ${JSON.stringify(out)}`);
  return m[1];
}

describe("inner check_changed gate — behavioral (force_run=false)", () => {
  // Rows that MUST rebuild+deploy (changed=true). worktree-manager.sh is the
  // literal 2026-07-01 incident file; AGENTS.md/CLAUDE.md are runtime instruction
  // files an allowlist would have missed; plugins/soleur/mcp/x is a hypothetical
  // FUTURE runtime surface the denylist covers by default.
  test.each([
    ["plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"],
    ["plugins/soleur/AGENTS.md"],
    ["plugins/soleur/CLAUDE.md"],
    ["plugins/soleur/mcp/x.json"],
    ["apps/web-platform/server/workspace.ts"],
  ])("TRIGGERS build+deploy: %s", (p) => {
    expect(runGate([p])).toBe("true");
  });

  // Rows that MUST NOT rebuild the web-platform image. docs deploy via
  // deploy-docs.yml; test dirs don't affect the deployed runtime.
  test.each([
    ["plugins/soleur/docs/reference/x.md"],
    ["plugins/soleur/test/some-guard.test.ts"],
  ])("does NOT trigger build+deploy: %s", (p) => {
    expect(runGate([p])).toBe("false");
  });

  test("mixed apps + runtime-plugin change triggers a single build", () => {
    expect(
      runGate([
        "apps/web-platform/app/page.tsx",
        "plugins/soleur/skills/ship/SKILL.md",
      ]),
    ).toBe("true");
  });
});

describe("inner check_changed gate — fail-loud, no shell-glob", () => {
  test("git failure fails loud (::error::) and never defaults to changed=false", () => {
    // Run the gate in a NON-git directory: git diff must fail, the rc check must
    // exit non-zero and emit ::error:: — the opposite of the incident's silent
    // swallow-into-changed=false.
    const dir = mkdtempSync(join(tmpdir(), "deploygap-nogit-"));
    const outFile = join(dir, ".ghoutput");
    writeFileSync(outFile, "");
    let threw = false;
    let stderr = "";
    try {
      execFileSync("bash", ["-c", GATE_SCRIPT], {
        cwd: dir,
        stdio: "pipe",
        env: {
          ...process.env,
          FORCE_RUN: "false",
          PATH_FILTER,
          COMPONENT: "web-platform",
          GITHUB_OUTPUT: outFile,
        },
      });
    } catch (e: any) {
      threw = true;
      stderr = String(e.stderr ?? "") + String(e.stdout ?? "");
    }
    expect(threw).toBe(true);
    expect(stderr).toContain("::error::");
    // Must NOT have written a changed=false verdict on failure.
    expect(readFileSync(outFile, "utf8")).not.toContain("changed=false");
  });

  test("gate script sets pipefail, disables globbing, and word-splits PATH_FILTER", () => {
    expect(GATE_SCRIPT).toContain("set -euo pipefail");
    expect(GATE_SCRIPT).toContain("set -f");
    // Unquoted $PATH_FILTER (word-split into multiple git pathspecs).
    expect(GATE_SCRIPT).toMatch(/git diff --name-only HEAD~1 -- \$PATH_FILTER/);
  });

  test("inner pathspec contract contains NO ** glob token", () => {
    expect(PATH_FILTER).not.toContain("**");
  });

  test("force_run short-circuit is preserved", () => {
    expect(GATE_SCRIPT).toMatch(/if \[ "\$FORCE_RUN" = "true" \]/);
  });
});

describe("web-platform path_filter contract (git-pathspec dialect)", () => {
  test("includes both positive prefixes and both :(exclude) pathspecs", () => {
    expect(PATH_FILTER).toContain("apps/web-platform/");
    expect(PATH_FILTER).toContain("plugins/soleur/");
    expect(PATH_FILTER).toContain(":(exclude)plugins/soleur/docs/");
    expect(PATH_FILTER).toContain(":(exclude)plugins/soleur/test/");
  });
});

describe("outer on.push.paths gate (Actions glob dialect)", () => {
  test("contains apps/web-platform/** and plugins/soleur/** with docs+test exclusions", () => {
    expect(ON_PUSH_PATHS).toContain("apps/web-platform/**");
    expect(ON_PUSH_PATHS).toContain("plugins/soleur/**");
    expect(ON_PUSH_PATHS).toContain("!plugins/soleur/docs/**");
    expect(ON_PUSH_PATHS).toContain("!plugins/soleur/test/**");
  });
});
