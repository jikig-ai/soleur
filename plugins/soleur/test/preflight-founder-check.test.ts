// preflight Check 13 (founder-stated check) — regression suite for founder-check.py (#9578).
//
// The suite drives the PRODUCTION script (plugins/soleur/skills/preflight/scripts/founder-check.py)
// over synthesized git histories, never a TypeScript mirror of it. Every history is built with
// gitFixtureEnv() so a fixture `git` can never be redirected at the developer's live branch by an
// inherited GIT_DIR (plugin AGENTS.md "Test Fixture Conventions").
//
// What each describe pins is named after the Guard it serves in the plan's `## Guard Contract`:
//   Guard 1  frozen-block integrity        -> "verify: ..." (resolution, freeze, rules)
//   Guard 2  must-fail baseline            -> "classify: ..."
//   Guard 3  consent before run            -> "verify: authorship" and "log: ..."
//   Guard 4  single sandbox chokepoint     -> "Guard 4: ..."
//
// Pure decision tables (the static rules, the classify matrix) run IN-PROCESS through one python
// import each; everything that touches git or files goes through the CLI on a copied base repo.
// The harness rows at the bottom edit THIS suite's subject (a stub, a deleted refusal) and
// require the observable to change POSITIVELY, so a suite that asserts nothing cannot stay green.
// The counts are also floored from OUTSIDE by preflight-check10-suite-integrity.test.sh.
import { afterAll, describe, expect, setDefaultTimeout, test } from "bun:test";
import { createHash } from "node:crypto";
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import { gitFixtureEnv } from "./lib/git-fixture-env";

setDefaultTimeout(30_000);

// FOUNDER_CHECK_SCRIPT (with FOUNDER_CHECK_MUTATION_RUN=1) is a seam for the mutation battery only:
// it points the whole suite at a MUTATED COPY of the script (with probe-verb-gate.sh beside it) so a
// surviving mutant is a measured result. Otherwise the suite drives the production script.
const SKILL_DIR = join(import.meta.dir, "..", "skills", "preflight");
// The seam is honoured ONLY with FOUNDER_CHECK_MUTATION_RUN=1: an ambient FOUNDER_CHECK_SCRIPT must not
// silently retarget the suite (Guard 4 included) away from production.
const MUTATION_RUN = process.env.FOUNDER_CHECK_MUTATION_RUN === "1" && !!process.env.FOUNDER_CHECK_SCRIPT;
const SCRIPT = MUTATION_RUN ? (process.env.FOUNDER_CHECK_SCRIPT as string) : join(SKILL_DIR, "scripts", "founder-check.py");
if (MUTATION_RUN) console.warn(`[founder-check suite] MUTATION RUN against ${SCRIPT}`);
const GATE = join(SKILL_DIR, "scripts", "probe-verb-gate.sh");
const FIXTURES = join(import.meta.dir, "fixtures", "founder-check");
const PLANS = "knowledge-base/project/plans";
const OPERATOR = "fixture@example.com"; // gitFixtureEnv()'s synthesized identity
const STRANGER = "stranger@example.com";
const TMP = process.env.TMPDIR ?? "/var/tmp";
const HEX64 = "f".repeat(64);
const SHA40 = "a".repeat(40);

// ---------------------------------------------------------------------------------------------
// Block rendering. Independent of the script: the canonical hash is recomputed here from the
// documented definition (sha256 over sorted-key compact JSON of the seven canonical fields).
// ---------------------------------------------------------------------------------------------
type Fields = {
  kind: string;
  text: string;
  command: string;
  expected: string;
  pins: Record<string, string>;
  approved_by: string;
  approved_at: string;
};

const BASE: Fields = {
  kind: "command",
  text: "the home page says hello",
  command: "grep -c hello site/index.html",
  expected: "1",
  pins: {},
  approved_by: "founder",
  approved_at: "2026-10-06",
};

function canonicalHash(f: Fields): string {
  const pins = Object.fromEntries(Object.entries(f.pins).sort(([a], [b]) => (a < b ? -1 : 1)));
  const obj = {
    approved_at: f.approved_at,
    approved_by: f.approved_by,
    command: f.command,
    expected: f.expected,
    kind: f.kind,
    pins,
    text: f.text,
  };
  return createHash("sha256").update(JSON.stringify(obj)).digest("hex");
}

type RenderOpts = {
  style?: "plain" | "reformatted";
  hash?: string | null; // null removes the line; undefined computes the right one
  extra?: string[];
};

function renderBlock(f: Fields, opts: RenderOpts = {}): string {
  const hash = opts.hash === undefined ? canonicalHash(f) : opts.hash;
  const lines: string[] = [];
  const pinLines = (indent: string) =>
    Object.keys(f.pins).length === 0
      ? [`${indent}pins: {}`]
      : [`${indent}pins:`, ...Object.entries(f.pins).map(([k, v]) => `${indent}  ${k}: ${v}`)];
  if (opts.style === "reformatted") {
    // Same canonical fields, different bytes: single quotes, reordered keys, trailing comments.
    const q = (s: string) => `'${s.replace(/'/g, "''")}'`;
    lines.push("founder_check:");
    lines.push(`  text: ${q(f.text)}   # the founder's own words`);
    lines.push(`  kind: ${f.kind}`);
    lines.push(`  expected: ${q(f.expected)}`);
    lines.push(`  command: ${q(f.command)}`);
    lines.push(...pinLines("  "));
    lines.push(`  approved_at: "${f.approved_at}"`);
    lines.push(`  approved_by: "${f.approved_by}"`);
    if (hash !== null) lines.push(`  hash: ${q(hash)}`);
  } else {
    const q = (s: string) => JSON.stringify(s);
    lines.push("founder_check:");
    lines.push(`  kind: ${f.kind}`);
    lines.push(`  text: ${q(f.text)}`);
    lines.push(`  command: ${q(f.command)}`);
    lines.push(`  expected: ${q(f.expected)}`);
    lines.push(...pinLines("  "));
    lines.push(`  approved_by: ${q(f.approved_by)}`);
    lines.push(`  approved_at: ${q(f.approved_at)}`);
    if (hash !== null) lines.push(`  hash: "${hash}"`);
  }
  for (const e of opts.extra ?? []) lines.push(`  ${e}`);
  return "```yaml\n" + lines.join("\n") + "\n```";
}

function scaffold(name: string, subs: Record<string, string>): string {
  let s = readFileSync(join(FIXTURES, name), "utf8");
  for (const [k, v] of Object.entries(subs)) s = s.replaceAll(`{{${k}}}`, v);
  return s;
}

// ---------------------------------------------------------------------------------------------
// Repo fixture. One base repo is built once and COPIED per test (init plus four git calls per
// test dominated the old suite's runtime).
// ---------------------------------------------------------------------------------------------
const made: string[] = [];
afterAll(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

type Run = { status: number; stdout: string; stderr: string; json: any };

function runPy(args: string[], opts: { cwd?: string; env?: NodeJS.ProcessEnv; script?: string; input?: string; timeout?: number } = {}): Run {
  const r = spawnSync("python3", [opts.script ?? SCRIPT, ...args], {
    cwd: opts.cwd,
    env: opts.env,
    input: opts.input,
    encoding: "utf8",
    timeout: opts.timeout ?? 25_000,
  });
  let json: any = null;
  try {
    json = JSON.parse(r.stdout);
  } catch {
    // not JSON: leave null so an assertion on `json?.x` fails loudly instead of throwing here
  }
  return { status: r.status ?? -1, stdout: r.stdout ?? "", stderr: r.stderr ?? "", json };
}

let baseDir: string | null = null;
function gitIn(dir: string, args: string[], extra: Record<string, string> = {}): string {
  const r = spawnSync("git", ["-c", "commit.gpgsign=false", ...args], {
    cwd: dir,
    env: { ...gitFixtureEnv(dir), ...extra },
    encoding: "utf8",
  });
  if (r.status !== 0) throw new Error(`git ${args.join(" ")} failed: ${r.stderr}`);
  return r.stdout;
}
function buildBase(): string {
  if (baseDir) return baseDir;
  const dir = mkdtempSync(join(TMP, "fc-base-"));
  made.push(dir);
  gitIn(dir, ["init", "-q", "-b", "main"]);
  writeFileSync(join(dir, "README.md"), "fixture\n");
  gitIn(dir, ["add", "-A"]);
  gitIn(dir, ["commit", "-q", "-m", "base"]);
  gitIn(dir, ["update-ref", "refs/remotes/origin/main", "HEAD"]);
  gitIn(dir, ["checkout", "-q", "-b", "feat-x"]);
  baseDir = dir;
  return dir;
}

class Repo {
  dir: string;
  scratch: string;
  constructor() {
    this.dir = mkdtempSync(join(TMP, "fc-"));
    this.scratch = mkdtempSync(join(TMP, "fcs-"));
    made.push(this.dir, this.scratch);
    rmSync(this.dir, { recursive: true, force: true });
    cpSync(buildBase(), this.dir, { recursive: true });
  }
  env(extra: Record<string, string> = {}): NodeJS.ProcessEnv {
    return { ...gitFixtureEnv(this.dir), ...extra };
  }
  git(args: string[], extra: Record<string, string> = {}): string {
    return gitIn(this.dir, args, extra);
  }
  write(rel: string, content: string) {
    const p = join(this.dir, rel);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, content);
  }
  commit(msg: string, email = OPERATOR): string {
    this.git(["add", "-A"]);
    this.git(["commit", "-q", "-m", msg], { GIT_AUTHOR_EMAIL: email, GIT_COMMITTER_EMAIL: email });
    return this.git(["rev-parse", "HEAD"]).trim();
  }
  plan(name: string, body: string) {
    this.write(`${PLANS}/${name}`, body);
  }
  /** Commit a plan carrying `block` under the Acceptance Criteria heading. */
  freeze(f: Fields = BASE, name = "p.md", email = OPERATOR, opts: RenderOpts = {}, fixture = "plan-ac.md"): string {
    this.plan(name, scaffold(fixture, { BLOCK: renderBlock(f, opts) }));
    return this.commit("plan: freeze", email);
  }
  /** Land a file on main (the usual home of a pinned script), then rebase the branch onto it. */
  mainFile(rel: string, content: string) {
    this.git(["checkout", "-q", "main"]);
    this.write(rel, content);
    this.commit(`main: ${rel}`);
    this.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    this.git(["checkout", "-q", "feat-x"]);
    this.git(["rebase", "-q", "main"]);
  }
  blob(rel: string): string {
    return this.git(["rev-parse", `HEAD:${rel}`]).trim();
  }
  py(args: string[], extra: Record<string, string> = {}, script = SCRIPT): Run {
    return runPy(args, { cwd: this.dir, env: this.env(extra), script });
  }
  /** verify as the ship gate runs it; `--no-pr` unless the test is about the PR anchor. */
  verify(extra: string[] = [], script = SCRIPT): Run {
    return this.py(["verify", "--base", "origin/main", ...(extra.includes("--pr-author") ? [] : ["--no-pr"]), ...extra], {}, script);
  }
  /** verify, writing its decision record to a file outside the repo (so it cannot dirty the tree). */
  verifyFile(extra: string[] = [], name = "vj.json"): { file: string; run: Run } {
    const file = join(this.scratch, name);
    return { file, run: this.verify(["--out", file, "--command-out", this.cmdFile, ...extra]) };
  }
  /** The command file `verifyFile` writes: what the wrapper reads and `classify --command-file` compares. */
  get cmdFile(): string {
    return join(this.scratch, "cmd.txt");
  }
  /** classify as the wrapper drives it: the ran-command file defaults to the one verify wrote. */
  classify(args: string[]): Run {
    return this.py(["classify", ...(args.includes("--command-file") ? [] : ["--command-file", this.cmdFile]), ...args]);
  }
}

// ---------------------------------------------------------------------------------------------
// In-process harness: ONE python import runs a whole decision table.
// ---------------------------------------------------------------------------------------------
function harness(code: string, data: unknown, script = SCRIPT): any {
  const prog = [
    "import importlib.util, json, sys",
    'spec = importlib.util.spec_from_file_location("fc", sys.argv[1])',
    "fc = importlib.util.module_from_spec(spec)",
    "spec.loader.exec_module(fc)",
    "data = json.load(sys.stdin)",
    code,
    "print(json.dumps(out))",
  ].join("\n");
  const r = spawnSync("python3", ["-I", "-c", prog, script], { input: JSON.stringify(data), encoding: "utf8", timeout: 60_000 });
  if (r.status !== 0) throw new Error(`harness failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

/** A frozen `bash scripts/ok.sh` check whose script touches a marker file if anything ever runs it. */
function canaryRepo(): { r: Repo; marker: string } {
  const r = new Repo();
  const marker = join(r.scratch, "canary-ran");
  r.mainFile("scripts/ok.sh", `#!/bin/bash\ntouch ${marker}\n`);
  r.freeze({ ...BASE, command: "bash scripts/ok.sh", expected: "", pins: { "scripts/ok.sh": r.blob("scripts/ok.sh") } });
  r.write("src/a.txt", "a\n");
  r.commit("code");
  return { r, marker };
}

/** A mutated COPY of the production script (never the file itself), proven to compile. */
function mutate(anchor: string, replacement: string): string {
  const text = readFileSync(SCRIPT, "utf8");
  const n = text.split(anchor).length - 1;
  if (n !== 1) throw new Error(`mutation anchor must occur exactly once in founder-check.py (found ${n}): ${anchor}`);
  const dir = mkdtempSync(join(TMP, "fcm-"));
  made.push(dir);
  const p = join(dir, "founder-check.py");
  writeFileSync(p, text.replace(anchor, replacement));
  writeFileSync(join(dir, "probe-verb-gate.sh"), readFileSync(GATE, "utf8"), { mode: 0o755 });
  const c = spawnSync("python3", ["-I", "-c", "import ast,sys; ast.parse(open(sys.argv[1]).read())", p], { encoding: "utf8" });
  if (c.status !== 0) throw new Error(`the mutant does not compile (a crash is not a kill): ${c.stderr}`);
  return p;
}

const cmdBlock = (over: Partial<Fields & { creates: string[] }> = {}): Record<string, unknown> => ({
  ...BASE,
  ...over,
});

// ---------------------------------------------------------------------------------------------
describe("verify: resolution", () => {
  test("no plan change on the branch is NO-BLOCK, exit 0, with the pinned banner", () => {
    const r = new Repo();
    r.write("src/a.txt", "a\n");
    r.commit("code only");
    const v = r.verify();
    expect(v.json?.outcome).toBe("NO-BLOCK");
    expect(v.json?.banner).toBe("No founder-stated check was found for this ship, so none was run.");
    expect(v.status).toBe(0);
  });

  test("a plan with no founder_check block and no history is NO-BLOCK", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-no-block.md", {}));
    r.commit("plan without block");
    expect(r.verify().json?.outcome).toBe("NO-BLOCK");
  });

  test("a block quoted under a non-Acceptance-Criteria heading is ignored (Guard 1 row 7)", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-quoted-non-ac.md", { BLOCK: renderBlock(BASE) }));
    r.commit("plan quoting the shape");
    expect(r.verify().json?.outcome).toBe("NO-BLOCK");
  });

  test("a quoted copy does not disturb a real block elsewhere (must-PASS)", () => {
    const r = new Repo();
    r.plan(
      "p.md",
      scaffold("plan-ac-and-quoted.md", {
        QUOTED: renderBlock({ ...BASE, command: "grep -c quoted-only f" }),
        BLOCK: renderBlock(BASE),
      }),
    );
    r.commit("plan: freeze");
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.block?.command).toBe(BASE.command);
  });

  test("a block under a SUFFIXED heading ('## Acceptance Criteria (v2)') is found, not silently NO-BLOCK", () => {
    const r = new Repo();
    r.freeze(BASE, "p.md", OPERATOR, {}, "plan-ac-suffixed.md");
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.block?.command).toBe(BASE.command);
  });

  test("two blocks in one Acceptance Criteria section is FAIL", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-two-blocks.md", { BLOCK: renderBlock(BASE), BLOCK2: renderBlock({ ...BASE, command: "grep -c other f" }) }));
    r.commit("two blocks");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("multiple-blocks");
    expect(v.status).toBe(1);
  });

  test("two plans each carrying a block is FAIL", () => {
    const r = new Repo();
    r.freeze(BASE, "a.md");
    r.freeze({ ...BASE, command: "grep -c other f" }, "b.md");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("multiple-plans");
  });

  test("a symlinked plan is FAIL and is never opened (a link to /dev/zero returns promptly)", () => {
    const r = new Repo();
    r.write("elsewhere/real.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    mkdirSync(join(r.dir, PLANS), { recursive: true });
    symlinkSync(join(r.dir, "elsewhere", "real.md"), join(r.dir, PLANS, "p.md"));
    symlinkSync("/dev/zero", join(r.dir, PLANS, "z.md"));
    r.commit("symlinked plans");
    const v = r.verify();
    expect(v.status).not.toBe(-1); // not killed by the timeout
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("symlinked-plan");
  });

  test("--plan /dev/zero and --plan <fifo> are FAIL, never read", () => {
    const r = new Repo();
    const z = r.verify(["--plan", "/dev/zero"]);
    expect(z.status).not.toBe(-1);
    expect(z.json?.outcome).toBe("FAIL");
    expect(z.json?.reason).toBe("plan-not-regular");
    mkdirSync(join(r.dir, PLANS), { recursive: true });
    const fifo = join(r.dir, PLANS, "fifo.md");
    expect(spawnSync("mkfifo", [fifo]).status).toBe(0);
    const f = r.verify(["--plan", `${PLANS}/fifo.md`]);
    expect(f.status).not.toBe(-1);
    expect(f.json?.reason).toBe("plan-not-regular");
  });

  test("--plan outside the plans directory is FAIL", () => {
    const r = new Repo();
    r.write("elsewhere/x.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    const v = r.verify(["--plan", "elsewhere/x.md"]);
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("plan-outside-plans-dir");
  });

  test("a plan over 1 MiB is FAIL unparseable, not read whole", () => {
    const r = new Repo();
    r.plan("p.md", "x".repeat(1_600_000));
    r.commit("a huge plan");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("unparseable");
  });

  test("a block with no freeze commit (uncommitted working tree) is FAIL", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("no-freeze");
  });

  test("an unresolvable base with a block on disk is FAIL base-unresolvable", () => {
    const r = new Repo();
    r.freeze();
    r.git(["update-ref", "-d", "refs/remotes/origin/main"]);
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("base-unresolvable");
    expect(v.status).toBe(1);
  });

  test("an unresolvable base with NO block anywhere is NO-BLOCK, exit 0 (a repo that never used the feature ships)", () => {
    const r = new Repo();
    r.git(["update-ref", "-d", "refs/remotes/origin/main"]);
    const v = r.verify();
    expect(v.json?.outcome).toBe("NO-BLOCK");
    expect(v.json?.base_note).toBe("base-unresolvable");
    expect(v.status).toBe(0);
  });

  test("a directory that is not a repository is FAIL not-a-repository", () => {
    const d = mkdtempSync(join(TMP, "fc-nogit-"));
    made.push(d);
    const v = runPy(["verify", "--repo", d], { cwd: d, env: gitFixtureEnv(d) });
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("not-a-repository");
    expect(v.status).toBe(1);
  });

  test("--base must be the remote default branch (HEAD is refused; refs/remotes/origin/main is accepted)", () => {
    const r = new Repo();
    r.freeze();
    const bad = r.py(["verify", "--base", "HEAD", "--no-pr"]);
    expect(bad.json?.outcome).toBe("FAIL");
    expect(bad.json?.reason).toBe("base-not-default-branch");
    const full = r.py(["verify", "--base", "refs/remotes/origin/main", "--no-pr"]);
    expect(full.json?.outcome).toBe("OK");
  });

  test("a plan merged to main is found through tasks.md's Plan: line (merge-base freeze)", () => {
    const r = new Repo();
    r.git(["checkout", "-q", "main"]);
    r.plan("m.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.commit("main: reviewed plan");
    r.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    r.git(["checkout", "-q", "feat-x"]);
    r.git(["rebase", "-q", "main"]);
    r.write("src/a.txt", "a\n");
    r.commit("code");
    expect(r.verify().json?.outcome).toBe("NO-BLOCK"); // the branch never touched the plan
    r.write("knowledge-base/project/specs/feat-x/tasks.md", `# Tasks\n\nPlan: ${PLANS}/m.md\n`);
    r.commit("tasks names the plan");
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.freeze_source).toBe("merge-base");
  });
});

describe("block extraction and parsing (in-process tables)", () => {
  const FC = ["founder_check:", "  kind: command", '  text: "t"'];
  const fence = (open: string, close: string, body: string[] = FC) => [open, ...body, close];
  const AC = "## Acceptance Criteria";
  // [name, document lines, how many blocks extract_blocks must return]
  const docs: [string, string[], number][] = [
    ["a plain fenced block under the heading", [AC, "", ...fence("```yaml", "```")], 1],
    ["the heading is case-insensitive", ["## acceptance criteria", ...fence("```yaml", "```")], 1],
    ["a suffixed heading", ["## Acceptance Criteria (v2)", ...fence("```yaml", "```")], 1],
    ["an h3 inside the section does not end it", [AC, "### Details", ...fence("```yaml", "```")], 1],
    ["a following h2 ends the section", [AC, "## Other", ...fence("```yaml", "```")], 0],
    ["an h1 is not the heading", ["# Acceptance Criteria", ...fence("```yaml", "```")], 0],
    ["a heading that only starts with the words is not the heading", ["## Acceptance Criteriafoo", ...fence("```yaml", "```")], 0],
    ["a tilde fence", [AC, ...fence("~~~yaml", "~~~")], 1],
    ["a longer backtick fence", [AC, ...fence("````yaml", "````")], 1],
    ["an indent of three spaces is still a fence", [AC, ...fence("   ```yaml", "   ```")], 1],
    ["an indent of four spaces is code, not a fence", [AC, ...fence("    ```yaml", "    ```")], 0],
    ["a 4-backtick fence quoting a 3-backtick example is one quote, not a block", [AC, "````text", ...fence("```yaml", "```"), "````"], 0],
    ["the real block after a quoting fence is still found, exactly once", [AC, "````text", ...fence("```yaml", "```"), "````", ...fence("```yaml", "```")], 1],
    ["a backtick fence is not closed by a tilde fence (only the later backtick line closes it)", [AC, ...fence("```yaml", "~~~", [...FC, "~~~"]), "```"], 1],
    ["a closer with an info string does not close", [AC, "```yaml", ...FC, "``` yaml", "  more: x", "```"], 1],
    ["a heading inside a fence does not start a section", ["```", AC, "```", ...fence("```yaml", "```")], 0],
    ["a heading inside a fence does not END the section", [AC, "```text", "## Other", "```", ...fence("```yaml", "```")], 1],
    ["a fence whose first line is not founder_check:", [AC, ...fence("```yaml", "```", ["other:", "  a: b"])], 0],
    ["an unterminated fence yields nothing", [AC, "```yaml", ...FC], 0],
  ];

  test("every document yields exactly the expected number of blocks", () => {
    const got: number[] = harness("out = [len(fc.extract_blocks(chr(10).join(d))) for d in data]", docs.map((d) => d[1]));
    docs.forEach(([name, , want], i) => expect([name, got[i]]).toEqual([name, want]));
  });

  test("a closer carrying an info string does not close: it and the lines after it stay in the body", () => {
    const body: string[][] = harness("out = fc.extract_blocks(chr(10).join(data))", [AC, "```yaml", ...FC, "``` yaml", "  more: x", "```"]);
    expect(body.length).toBe(1);
    expect(body[0]).toContain("``` yaml");
    expect(body[0]).toContain("  more: x");
  });

  test("a tilde closer does not end a backtick fence: its line stays in the block body", () => {
    const body: string[][] = harness("out = fc.extract_blocks(chr(10).join(data))", [AC, "```yaml", ...FC, "~~~", "```"].join("\n").split("\n") as unknown as string[]);
    expect(body[0]).toContain("~~~");
  });

  // [name, block lines, expected fields (a subset) | null for a ParseError]
  const blocks: [string, string[], Record<string, unknown> | null][] = [
    ["a double-quoted scalar", [...FC], { text: "t", kind: "command" }],
    ["a doubled single quote unescapes", ["founder_check:", "  text: 'it''s'"], { text: "it's" }],
    ["a # inside quotes is text, not a comment", ["founder_check:", '  command: "grep a # b f"'], { command: "grep a # b f" }],
    ["a trailing comment is removed", ["founder_check:", "  expected: ok # because"], { expected: "ok" }],
    ["a # with no space before it is part of the value", ["founder_check:", "  expected: a#b"], { expected: "a#b" }],
    ["an empty pins literal", ["founder_check:", "  pins: {}"], { pins: {} }],
    ["a block-form pins map", ["founder_check:", "  pins:", "    a.sh: " + "a".repeat(40)], { pins: { "a.sh": "a".repeat(40) } }],
    ["an unterminated double quote", ["founder_check:", '  text: "abc'], null],
    ["an unterminated single quote", ["founder_check:", "  text: 'abc"], null],
    ["a lone quote", ["founder_check:", '  text: "'], null],
    ["a flow map with content", ["founder_check:", "  pins: {a: b}"], null],
    ["a flow list with content", ["founder_check:", "  expected: [1]"], null],
    ["a nested collection inside pins", ["founder_check:", "  pins:", "    a.sh: [x]"], null],
    ["inconsistent indentation", ["founder_check:", "  kind: command", "   text: x"], null],
    ["an unindented field", ["founder_check:", "kind: command"], null],
    ["an empty block", ["founder_check:"], null],
    ["only comments", ["founder_check:", "  # nothing"], null],
    ["a duplicate key", ["founder_check:", "  kind: command", "  kind: judgement"], null],
    ["a line that is not key: value", ["founder_check:", "  just words"], null],
    ["a bad JSON escape in a double quote", ["founder_check:", '  text: "a\\qb"'], null],
    ["not starting with founder_check:", ["other:", "  a: b"], null],
  ];

  test("every block parses to the expected fields, or is a ParseError", () => {
    const code = [
      "out = []",
      "for lines in data:",
      "    try:",
      "        out.append(fc.parse_block(lines))",
      "    except fc.ParseError:",
      "        out.append(None)",
    ].join("\n");
    const got: (Record<string, unknown> | null)[] = harness(code, blocks.map((b) => b[1]));
    blocks.forEach(([name, , want], i) => {
      if (want === null) expect([name, got[i]]).toEqual([name, null]);
      else expect([name, Object.fromEntries(Object.keys(want).map((k) => [k, (got[i] as Record<string, unknown>)?.[k]]))]).toEqual([name, want]);
    });
  });
});

// ---------------------------------------------------------------------------------------------
describe("verify: freeze comparison (Guard 1)", () => {
  test("a block frozen before any code is OK and reports its identity", () => {
    const r = new Repo();
    const sha = r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.freeze_source).toBe("branch");
    expect(v.json?.freeze_sha).toBe(sha);
    expect(v.json?.hash).toBe(canonicalHash(BASE));
    expect(v.json?.first_token).toBe("grep");
    expect(v.status).toBe(0);
  });

  test("a reformatted block with the same canonical fields is still OK (must-PASS)", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.freeze(BASE, "p.md", OPERATOR, { style: "reformatted" });
    expect(r.verify().json?.outcome).toBe("OK");
  });

  for (const [field, edit] of [
    ["kind", { kind: "judgement" }],
    ["text", { text: "the home page says goodbye" }],
    ["command", { command: "grep -c hi site/index.html" }],
    ["expected", { expected: "2" }],
    ["pins", { pins: { "scripts/x.sh": SHA40 } }],
    ["approved_by", { approved_by: "someone else" }],
    ["approved_at", { approved_at: "2026-10-07" }],
  ] as [string, Partial<Fields>][]) {
    test(`editing ${field} after the freeze (with a recomputed hash) is CHANGED-SINCE-APPROVAL`, () => {
      const r = new Repo();
      r.freeze();
      r.write("src/a.txt", "a\n");
      r.commit("code");
      r.freeze({ ...BASE, ...edit } as Fields, "p.md");
      const v = r.verify();
      expect(v.json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
      expect(v.json?.changed_fields).toContain(field);
      expect(v.json?.frozen?.command).toBe(BASE.command); // the prompt can show what was approved
      expect(v.status).toBe(1);
    });
  }

  test("a stale hash: line (fields edited, hash not) is FAIL hash-mismatch", () => {
    const r = new Repo();
    r.freeze(BASE, "p.md", OPERATOR, { hash: "0".repeat(64) });
    expect(r.verify().json?.reason).toBe("hash-mismatch");
  });

  test("a rebased branch (fresh SHAs) with the same content is still OK (must-PASS)", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.git(["checkout", "-q", "main"]);
    r.write("main-only.txt", "x\n");
    r.commit("main moves");
    r.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    r.git(["checkout", "-q", "feat-x"]);
    r.git(["rebase", "-q", "main"]);
    expect(r.verify().json?.outcome).toBe("OK");
  });

  test("a commit that only adds a learning after the freeze does not disturb it (must-PASS)", () => {
    const r = new Repo();
    r.freeze();
    r.write("knowledge-base/project/learnings/2026-10-06-x.md", "# x\n");
    r.commit("learning");
    expect(r.verify().json?.outcome).toBe("OK");
  });

  test("code committed BEFORE the freeze is flagged as an ordering failure", () => {
    const r = new Repo();
    r.write("src/a.txt", "a\n");
    r.commit("code first");
    r.freeze();
    const v = r.verify();
    expect(v.json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(v.json?.reasons).toContain("ordering");
  });

  test("a block reviewed on main (merge-base freeze) needs no authorship anchor and no PR flag", () => {
    const r = new Repo();
    r.git(["checkout", "-q", "main"]);
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.commit("main: reviewed plan", STRANGER);
    r.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    r.git(["checkout", "-q", "feat-x"]);
    r.git(["rebase", "-q", "main"]);
    r.write("knowledge-base/project/specs/feat-x/tasks.md", `# Tasks\n\nPlan: ${PLANS}/p.md\n`);
    r.write("src/a.txt", "a\n");
    r.commit("code, with tasks.md naming the plan");
    const v = r.py(["verify", "--base", "origin/main"]); // no --no-pr on purpose
    expect(v.json?.freeze_source).toBe("merge-base");
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.flags).toEqual([]);
  });

  test("deleting the plan after its freeze is FAIL freeze-without-block, never a SKIP", () => {
    const r = new Repo();
    r.freeze();
    r.git(["rm", "-q", `${PLANS}/p.md`]);
    r.commit("delete the plan");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("freeze-without-block");
  });

  test("a plain rename keeps its freeze (the block is unchanged, so it resolves, must-PASS)", () => {
    const r = new Repo();
    r.freeze();
    r.git(["mv", `${PLANS}/p.md`, `${PLANS}/q.md`]);
    r.commit("rename");
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.plan).toBe(`${PLANS}/q.md`);
  });

  test("compound's archival (git mv into plans/archive/<ts>-name.md) is the SAME plan: OK, not freeze-without-block", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    mkdirSync(join(r.dir, PLANS, "archive"), { recursive: true });
    r.git(["mv", `${PLANS}/p.md`, `${PLANS}/archive/20261006-120000-p.md`]);
    r.commit("archive the plan");
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.plan).toBe(`${PLANS}/archive/20261006-120000-p.md`);
  });

  test("archival is the same plan even when git cannot see a rename (the body was rewritten): the archive prefix is stripped", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.git(["rm", "-q", `${PLANS}/p.md`]);
    const filler = Array.from({ length: 80 }, (_, i) => `Unrelated archived line ${i} ${"x".repeat(30)}`).join("\n");
    r.plan("archive/20261006-120000-p.md", `# archived\n\n${filler}\n\n## Acceptance Criteria\n\n${renderBlock(BASE)}\n`);
    r.commit("archive with a rewritten body");
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.plan).toBe(`${PLANS}/archive/20261006-120000-p.md`);
  });

  test("an unrelated edit to a plan that MAIN already archived compares against main's freeze (it does not self-freeze)", () => {
    const r = new Repo();
    const arch = `${PLANS}/archive/20260101-000000-p.md`;
    r.mainFile(arch, scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.write(arch, scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }) + "\nswept: a link fixed by a docs sweep\n");
    r.commit("docs: sweep archived plans");
    const same = r.verify();
    expect([same.json?.outcome, same.json?.freeze_source, same.json?.plan]).toEqual(["OK", "merge-base", arch]);
    // the same sweep that also rewrites the block is a change to what main froze, not a new freeze
    r.write(arch, scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, expected: "9" }) }));
    r.commit("docs: sweep that touched the block");
    const changed = r.verify();
    expect([changed.json?.outcome, changed.json?.freeze_source]).toEqual(["CHANGED-SINCE-APPROVAL", "merge-base"]);
  });

  test("an archived plan whose block was edited afterwards is still CHANGED-SINCE-APPROVAL", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    mkdirSync(join(r.dir, PLANS, "archive"), { recursive: true });
    r.git(["mv", `${PLANS}/p.md`, `${PLANS}/archive/20261006-120000-p.md`]);
    r.plan("archive/20261006-120000-p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, expected: "9" }) }));
    r.commit("archive and edit");
    expect(r.verify().json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
  });
});

describe("verify: re-freeze (a deliberate change is a real act)", () => {
  const V2: Fields = { ...BASE, expected: "2" };
  const setup = () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    return r;
  };

  test("an operator-authored 're-freeze' commit supersedes the first freeze: OK, refreeze true", () => {
    const r = setup();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(V2) }));
    const sha = r.commit("plan: re-freeze founder-stated check");
    const v = r.verify(["--mode", "interactive"]);
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.refreeze).toBe(true);
    expect(v.json?.freeze_sha).toBe(sha);
    expect(v.json?.block?.expected).toBe("2");
    // loud: the record carries what the check said before, beside what it says now
    expect(v.json?.refrozen_from?.expected).toBe("1");
    expect(v.json?.refrozen_from?.command).toBe(BASE.command);
  });

  test("an unattended run (the default mode) stops on a re-freeze instead of running the replacement", () => {
    const r = setup();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(V2) }));
    r.commit("plan: re-freeze founder-stated check");
    for (const extra of [[], ["--mode", "headless"]]) {
      const v = r.verify(extra);
      expect([v.json?.outcome, v.json?.reason, v.json?.refreeze]).toEqual(["CHANGED-SINCE-APPROVAL", "refreeze-needs-founder", true]);
    }
  });

  test("a re-freeze with no earlier freeze on the branch is an ordinary freeze, not a re-freeze", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.commit("plan: re-freeze founder-stated check");
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const v = r.verify();
    expect([v.json?.outcome, v.json?.refreeze, v.json?.freeze_source]).toEqual(["OK", false, "branch"]);
  });

  test("a forged-author freeze stays UNTRUSTED after an operator 're-freeze' that restates the same block", () => {
    const r = new Repo();
    r.freeze(BASE, "p.md", STRANGER);
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }) + "\nan unrelated edit\n");
    r.commit("plan: re-freeze founder-stated check");
    for (const mode of ["interactive", "headless"]) {
      const v = r.verify(["--mode", mode]);
      expect([mode, v.json?.outcome, v.json?.refreeze]).toEqual([mode, "UNTRUSTED", false]);
    }
  });

  test("an operator re-freeze that CHANGES a stranger's freeze is the operator's own act, and is flagged as a re-freeze", () => {
    const r = new Repo();
    r.freeze(BASE, "p.md", STRANGER);
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(V2) }));
    r.commit("plan: re-freeze founder-stated check");
    const v = r.verify(["--mode", "interactive"]);
    expect([v.json?.outcome, v.json?.refreeze, v.json?.refrozen_from?.expected]).toEqual(["OK", true, "1"]);
  });

  test("the baseline of a re-freeze never reads VACUOUS: a pass is reported as PASSED, a fail as FAILED", () => {
    const r = setup();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(V2) }));
    const cand = r.verifyFile(["--candidate", "--refreeze"], "cand.json");
    expect([cand.run.json?.outcome, cand.run.json?.refreeze]).toEqual(["OK", true]);
    const args = ["--verify-json", cand.file, "--polarity", "baseline", "--control-rc", "0"];
    const pass = r.classify([...args, "--rc", "0"]);
    expect([pass.json?.outcome, pass.json?.reason]).toEqual(["FAILED", "refreeze-baseline-fails"]); // expected "2" is absent from empty stdout
    const out = join(r.scratch, "out.txt");
    writeFileSync(out, "2\n");
    const ok = r.classify([...args, "--rc", "0", "--stdout-file", out]);
    expect([ok.json?.outcome, ok.json?.reason]).toEqual(["PASSED", "refreeze-baseline-passes"]);
    expect(r.classify([...args, "--rc", "1"]).json?.outcome).toBe("FAILED");
    expect(r.classify([...args, "--rc", "127"]).json?.outcome).toBe("INVALID");
  });

  test("the same edit without the re-freeze subject stays CHANGED-SINCE-APPROVAL", () => {
    const r = setup();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(V2) }));
    r.commit("plan: quietly edit the check");
    expect(r.verify().json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
  });

  test("a re-freeze commit authored by someone other than the operator is ignored", () => {
    const r = setup();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(V2) }));
    r.commit("plan: re-freeze founder-stated check", STRANGER);
    expect(r.verify().json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
  });

  test("a re-freeze cannot supersede a freeze that was reviewed on main", () => {
    const r = new Repo();
    r.git(["checkout", "-q", "main"]);
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.commit("main: reviewed plan");
    r.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    r.git(["checkout", "-q", "feat-x"]);
    r.git(["rebase", "-q", "main"]);
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(V2) }));
    r.commit("plan: re-freeze founder-stated check");
    expect(r.verify().json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
  });
});

describe("verify: the pinned-script and pin rules", () => {
  const SCRIPT_SRC = "#!/usr/bin/env bash\necho 1\n";
  const withScript = () => {
    const r = new Repo();
    r.mainFile("scripts/ok.sh", SCRIPT_SRC);
    return r;
  };

  test("an interpreter command naming a pinned script is OK", () => {
    const r = withScript();
    r.freeze({ ...BASE, command: "bash scripts/ok.sh", pins: { "scripts/ok.sh": r.blob("scripts/ok.sh") } });
    expect(r.verify().json?.outcome).toBe("OK");
  });

  test("editing the pinned script after the freeze is CHANGED-SINCE-APPROVAL (pinned-script-changed)", () => {
    const r = withScript();
    r.freeze({ ...BASE, command: "bash scripts/ok.sh", pins: { "scripts/ok.sh": r.blob("scripts/ok.sh") } });
    r.write("scripts/ok.sh", SCRIPT_SRC + "echo 2\n");
    r.commit("edit the pinned script");
    const v = r.verify();
    expect(v.json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(v.json?.reasons).toContain("pinned-script-changed");
  });

  test("an UNCOMMITTED edit of the pinned script is caught too (the run reads the working tree)", () => {
    const r = withScript();
    r.freeze({ ...BASE, command: "bash scripts/ok.sh", pins: { "scripts/ok.sh": r.blob("scripts/ok.sh") } });
    r.write("scripts/ok.sh", SCRIPT_SRC + "echo evil\n");
    expect(r.verify().json?.reasons).toContain("pinned-script-changed");
  });

  test("a pin that does not match the blob at the freeze is FAIL pin-not-at-freeze", () => {
    const r = withScript();
    r.freeze({ ...BASE, command: "bash scripts/ok.sh", pins: { "scripts/ok.sh": SHA40 } });
    expect(r.verify().json?.reason).toBe("pin-not-at-freeze");
  });

  test("a pin on a symlink is FAIL: the pointed-at file could change unnoticed", () => {
    const r = new Repo();
    r.mainFile("scripts/real.sh", SCRIPT_SRC);
    symlinkSync("real.sh", join(r.dir, "scripts", "link.sh"));
    r.commit("a link");
    r.freeze({ ...BASE, command: "bash scripts/link.sh", pins: { "scripts/link.sh": r.blob("scripts/link.sh") } });
    expect(r.verify().json?.reason).toBe("pin-not-at-freeze");
  });

  test("a pinned EXECUTABLE script (mode 100755) is accepted, frozen and as a candidate", () => {
    const r = new Repo();
    r.git(["checkout", "-q", "main"]);
    r.write("scripts/ok.sh", SCRIPT_SRC);
    chmodSync(join(r.dir, "scripts/ok.sh"), 0o755);
    r.commit("main: an executable script");
    r.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    r.git(["checkout", "-q", "feat-x"]);
    r.git(["rebase", "-q", "main"]);
    expect(r.git(["ls-tree", "HEAD", "scripts/ok.sh"]).startsWith("100755")).toBe(true);
    const block = { ...BASE, command: "bash scripts/ok.sh", pins: { "scripts/ok.sh": r.blob("scripts/ok.sh") } };
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(block) }));
    const cand = r.verify(["--candidate"]);
    expect([cand.json?.outcome, cand.json?.reason]).toEqual(["OK", "candidate"]);
    r.commit("plan: freeze");
    r.write("src/a.txt", "a\n");
    r.commit("code");
    expect(r.verify().json?.outcome).toBe("OK");
  });

  test("candidate mode checks every pin against HEAD: a wrong blob, a missing file and a link are each FAIL", () => {
    const r = withScript();
    const plan = (pins: Record<string, string>) => r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, command: "bash scripts/ok.sh", pins }) }));
    plan({ "scripts/ok.sh": r.blob("scripts/ok.sh") });
    expect(r.verify(["--candidate"]).json?.outcome).toBe("OK");
    plan({ "scripts/ok.sh": SHA40 });
    expect(r.verify(["--candidate"]).json?.reason).toBe("pin-not-at-freeze");
    plan({ "scripts/ok.sh": r.blob("scripts/ok.sh"), "scripts/missing.sh": r.blob("scripts/ok.sh") });
    expect(r.verify(["--candidate"]).json?.reason).toBe("pin-not-at-freeze");
    symlinkSync("ok.sh", join(r.dir, "scripts", "link.sh"));
    r.git(["add", "scripts/link.sh"]);
    r.git(["commit", "-q", "-m", "a link"]); // only the link: the candidate plan must stay uncommitted
    plan({ "scripts/ok.sh": r.blob("scripts/ok.sh"), "scripts/link.sh": r.blob("scripts/link.sh") });
    expect(r.verify(["--candidate"]).json?.reason).toBe("pin-not-at-freeze");
  });

  test("replacing the pinned script with a LINK to identical bytes after the freeze is caught (pinned-script-changed)", () => {
    const r = withScript();
    r.freeze({ ...BASE, command: "bash scripts/ok.sh", pins: { "scripts/ok.sh": r.blob("scripts/ok.sh") } });
    r.write("scripts/real.sh", SCRIPT_SRC); // the same bytes, so hash-object of the link still equals the pin
    rmSync(join(r.dir, "scripts/ok.sh"));
    symlinkSync("real.sh", join(r.dir, "scripts/ok.sh"));
    const v = r.verify();
    expect(v.json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(v.json?.reasons).toContain("pinned-script-changed");
  });
});

// ---------------------------------------------------------------------------------------------
describe("verify: the static rules (in-process table)", () => {
  const PIN = { "scripts/ok.sh": SHA40 };
  type Row = [string, Record<string, unknown>, string | null];
  const rows: Row[] = [
    ["a plain grep", cmdBlock(), null],
    ["a judgement check", cmdBlock({ kind: "judgement", command: "" }), null],
    ["a pinned interpreter script", cmdBlock({ command: "bash scripts/ok.sh --flag", pins: PIN }), null],
    ["an expected literal holding < and >", cmdBlock({ expected: "<h1>hello</h1>" }), null],
    ["a verb off the allowlist", cmdBlock({ command: "rm -rf x" }), "verb-gate"],
    ["a semicolon", cmdBlock({ command: "grep a f; id" }), "shell-active-token"],
    ["a pipe", cmdBlock({ command: "grep a f | wc -l" }), "shell-active-token"],
    ["an ampersand in a URL", cmdBlock({ command: "curl http://x/?a=1&b=2" }), "shell-active-token"],
    ["a backtick", cmdBlock({ command: "grep `id` f" }), "shell-active-token"],
    ["a command substitution", cmdBlock({ command: "grep $(id) f" }), "shell-active-token"],
    ["a parameter expansion", cmdBlock({ command: "grep $HOME f" }), "shell-active-token"],
    ["a command substitution in expected", cmdBlock({ expected: "$(id)" }), "shell-active-token"],
    ["a backtick in expected", cmdBlock({ expected: "`id`" }), "shell-active-token"],
    ["a NUL byte in the command", cmdBlock({ command: "grep a\u0000b f" }), "control-character"],
    ["a newline in the command", cmdBlock({ command: "grep a f\nid" }), "control-character"],
    ["an ESC in expected", cmdBlock({ expected: "a\u001bb" }), "control-character"],
    ["an unpinned interpreter script", cmdBlock({ command: "bash scripts/new.sh" }), "unpinned-script"],
    ["a double-quoted interpreter verb", cmdBlock({ command: '"bash" scripts/new.sh' }), "unpinned-script"],
    ["a backslash-escaped interpreter verb", cmdBlock({ command: "\\bash scripts/new.sh" }), "unpinned-script"],
    ["a single-quoted interpreter verb", cmdBlock({ command: "'python3' scripts/new.py" }), "unpinned-script"],
    ["a split-quoted interpreter verb", cmdBlock({ command: 'ba""sh scripts/new.sh' }), "unpinned-script"],
    ["an inline program (-c)", cmdBlock({ command: "bash -c 'bash scripts/new.sh'" }), "interpreter-option"],
    ["python -m", cmdBlock({ command: "python3 -m mymod" }), "interpreter-option"],
    ["node --import", cmdBlock({ command: "node --import=./w.mjs app.mjs" }), "interpreter-option"],
    ["a bare-name operand", cmdBlock({ command: "bash check" }), "script-operand-required"],
    ["bun run", cmdBlock({ command: "bun run verify" }), "script-operand-required"],
    ["bun test", cmdBlock({ command: "bun test" }), "script-operand-required"],
    ["an interpreter with no operand", cmdBlock({ command: "bash" }), "script-operand-required"],
    ["an absolute script path", cmdBlock({ command: "bash /home/op/x.sh" }), "absolute-script-path"],
    ["a traversing script path", cmdBlock({ command: "bash ../x.sh" }), "script-path-traversal"],
    ["git -c", cmdBlock({ command: "git -c alias.t=x t" }), "dangerous-option"],
    ["git -cname=value", cmdBlock({ command: "git -calias.t=x t" }), "dangerous-option"],
    ["rg --pre", cmdBlock({ command: "rg --pre ./x foo f" }), "dangerous-option"],
    ["curl -K", cmdBlock({ command: "curl -K cfg http://x" }), "dangerous-option"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["a bearer token in the command", cmdBlock({ command: 'curl -H "Authorization: Bearer abcdefgh12345" http://x' }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["a token in the founder's words", cmdBlock({ text: "check with ghp_" + "a".repeat(30) }), "secret-shape"],
    ["a credentialed URL in expected", cmdBlock({ expected: "https://user:hunter2@host/x" }), "secret-shape"],
    ["a password assignment", cmdBlock({ command: "grep password=hunter22 f" }), "secret-shape"],
    ["credentials_required", { ...cmdBlock(), credentials_required: "x" }, "credentials-required"],
    ["an unknown field", { ...cmdBlock(), extra: "x" }, "unknown-field"],
    ["a creates field (cut in v2)", { ...cmdBlock(), creates: ["a"] }, "unknown-field"],
    ["an invalid kind", cmdBlock({ kind: "maybe" }), "invalid-kind"],
    ["an empty text", cmdBlock({ text: "  " }), "missing-field"],
    ["an empty command", cmdBlock({ command: "  " }), "missing-field"],
    ["an empty approved_by", cmdBlock({ approved_by: " " }), "missing-field"],
    ["an empty approved_at", cmdBlock({ approved_at: "" }), "missing-field"],
    ["an empty approved_by on a judgement check", cmdBlock({ kind: "judgement", command: "", approved_by: "" }), "missing-field"],
    ["a secret in approved_by (the founder's answer is committed too)", cmdBlock({ approved_by: "yes, token=abcdef123456" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["a secret in approved_by on a judgement check", cmdBlock({ kind: "judgement", command: "", approved_by: "ghp_" + "a".repeat(30) }), "secret-shape"],
    ["a pin that is not a sha", cmdBlock({ command: "bash scripts/ok.sh", pins: { "scripts/ok.sh": "nope" } }), "unparseable"],
    ["a pin path that traverses", cmdBlock({ command: "bash scripts/ok.sh", pins: { "../x.sh": SHA40 } }), "unparseable"],
    // One row per guard, not per spelling: each alternative of a rule is its own row, so deleting
    // one alternative (not just the whole rule) reds the suite.
    ["a pinned script named with ./ and pinned with ./", cmdBlock({ command: "bash ./scripts/ok.sh", pins: { "./scripts/ok.sh": SHA40 } }), null],
    ["a pinned script named with ./ and pinned without it", cmdBlock({ command: "bash ./scripts/ok.sh", pins: { "scripts/ok.sh": SHA40 } }), null],
    ["a pinned script named without ./ and pinned with it", cmdBlock({ command: "bash scripts/ok.sh", pins: { "./scripts/ok.sh": SHA40 } }), null],
    ["a pin that is a 64-hex (sha256) blob", cmdBlock({ command: "bash scripts/ok.sh", pins: { "scripts/ok.sh": "e".repeat(64) } }), null],
    ["a pin that is 41 hex", cmdBlock({ command: "bash scripts/ok.sh", pins: { "scripts/ok.sh": "e".repeat(41) } }), "unparseable"],
    ["a pin with an absolute key", cmdBlock({ command: "bash scripts/ok.sh", pins: { "/etc/x.sh": SHA40 } }), "unparseable"],
    ["a pin with an empty key", cmdBlock({ command: "bash scripts/ok.sh", pins: { "": SHA40 } }), "unparseable"],
    ["a pin with a bare ./ key", cmdBlock({ command: "bash scripts/ok.sh", pins: { "./": SHA40 } }), "unparseable"],
    ["pins that are not a mapping", cmdBlock({ pins: ["a"] }), "unparseable"],
    ["a text that is not a string", cmdBlock({ text: 5 }), "unparseable"],
    ["a command that is not a string", cmdBlock({ command: ["grep"] }), "unparseable"],
    ["an expected that is not a string", cmdBlock({ expected: 1 }), "unparseable"],
    ["an approved_by that is not a string", cmdBlock({ approved_by: 1 }), "unparseable"],
    ["git --config-env", cmdBlock({ command: "git --config-env=alias.t=X t" }), "dangerous-option"],
    ["git --exec-path", cmdBlock({ command: "git --exec-path=/tmp t" }), "dangerous-option"],
    ["curl --config", cmdBlock({ command: "curl --config cfg http://x" }), "dangerous-option"],
    ["curl --config=", cmdBlock({ command: "curl --config=cfg http://x" }), "dangerous-option"],
    ["rg --pre=", cmdBlock({ command: "rg --pre=./x foo f" }), "dangerous-option"],
    ["an output redirect", cmdBlock({ command: "grep a f > out" }), "shell-active-token"],
    ["an input redirect", cmdBlock({ command: "grep a < f" }), "shell-active-token"],
    ["a process substitution <(", cmdBlock({ command: "grep a <(id)" }), "shell-active-token"],
    ["a process substitution >(", cmdBlock({ command: "grep a >(id)" }), "shell-active-token"],
    ["a || chain", cmdBlock({ command: "grep a f || id" }), "shell-active-token"],
    ["a ${ expansion in expected", cmdBlock({ expected: "${HOME}" }), "shell-active-token"],
    ["a <( in expected", cmdBlock({ expected: "<(id)" }), "shell-active-token"],
    ["a >( in expected", cmdBlock({ expected: ">(id)" }), "shell-active-token"],
    ["a control character in the founder's words", cmdBlock({ text: "a\u0001b" }), "control-character"],
    ["a tab in the founder's words is kept", cmdBlock({ text: "a\tb" }), null],
    ["a control character in approved_by", cmdBlock({ approved_by: "yes\u001b[2J" }), "control-character"],
    ["a U+2028 in the founder's words", cmdBlock({ text: "a\u2028b" }), "control-character"],
    ["a Bearer token with no Authorization header", cmdBlock({ text: "send Bearer abcdefgh12345 along" }), "secret-shape"],
    ["an Authorization header with no Bearer", cmdBlock({ command: 'curl -H "Authorization: x" http://x' }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["an AWS access key id", cmdBlock({ text: "key AKIAABCDEFGHIJKLMNOP" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["a private key header", cmdBlock({ text: "-----BEGIN RSA PRIVATE KEY-----" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["curl -u user:pass", cmdBlock({ command: "curl -u me:hunter2 http://x" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["an api_key assignment", cmdBlock({ text: "api_key=abcdef123456" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["a plain word 'token' with no value is not a secret", cmdBlock({ text: "the token page loads" }), null],
    ["a plain 'secret garden' is not a secret", cmdBlock({ text: "the secret garden page loads" }), null],
    // secret FORMS: a name that merely contains the keyword, a flag, a JWT (\\b fails between _ and a keyword)
    ["GITHUB_TOKEN=", cmdBlock({ text: "run with GITHUB_TOKEN=abcdefgh1234" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["AWS_SECRET_ACCESS_KEY=", cmdBlock({ text: "AWS_SECRET_ACCESS_KEY=abcdefghij12" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["DB_PASSWORD=", cmdBlock({ text: "DB_PASSWORD=hunter2abc" }), "secret-shape"],
    ["SLACK_BOT_TOKEN=", cmdBlock({ text: "SLACK_BOT_TOKEN=xoxb-1234-abcd" }), "secret-shape"],
    ["NPM_TOKEN=", cmdBlock({ text: "NPM_TOKEN=npm_abcdef12" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["client_secret=", cmdBlock({ text: "client_secret=abcdefgh" }), "secret-shape"],
    ["access_token= inside a URL in the command", cmdBlock({ command: "curl http://x/p?access_token=abcdef123" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["access_token= inside a URL (founder's words)", cmdBlock({ text: "open http://x/p?access_token=abcdef123" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["curl --password", cmdBlock({ command: "curl --password hunter2 http://x" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["curl --password=", cmdBlock({ command: "curl --password=hunter2 http://x" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["curl --user u:p", cmdBlock({ command: "curl --user me:pw http://x" }), "secret-shape"], // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    ["a JWT", cmdBlock({ text: "token eyJhbGciOiJI.eyJzdWIiOiIx.SflKxwRJSMeKKF2QT4fwpM" }), "secret-shape"],
    ["a JWT with no keyword near it", cmdBlock({ expected: "eyJhbGciOiJI.eyJzdWIiOiIx.SflKxwRJSMeKKF2QT4fwpM" }), "secret-shape"],
    // length caps
    ["a text over 2000 characters", cmdBlock({ text: "x".repeat(2001) }), "too-long"],
    ["a command over 1000 characters", cmdBlock({ command: "grep " + "a".repeat(1000) + " f" }), "too-long"],
    ["an expected over 500 characters", cmdBlock({ expected: "x".repeat(501) }), "too-long"],
    ["an approved_by over 500 characters", cmdBlock({ approved_by: "x".repeat(501) }), "too-long"],
    ["a text of exactly 2000 characters is fine", cmdBlock({ text: "x".repeat(2000) }), null],
    // shlex sees what bash runs: every word bash would expand or re-read is refused
    ["an ANSI-C quoted script name", cmdBlock({ command: "bash $'a.sh'", pins: { "$a.sh": SHA40 } }), "shell-active-token"],
    ["a glob class in a script name", cmdBlock({ command: "bash [a].sh", pins: { "[a].sh": SHA40 } }), "shell-active-token"],
    ["a brace list in a script name", cmdBlock({ command: "bash {a,b}.sh", pins: { "{a,b}.sh": SHA40 } }), "shell-active-token"],
    ["a brace range", cmdBlock({ command: "grep a f{1..3}" }), "shell-active-token"],
    ["an unquoted star", cmdBlock({ command: "grep a *.md" }), "shell-active-token"],
    ["an unquoted question mark", cmdBlock({ command: "grep a f?" }), "shell-active-token"],
    ["a leading tilde", cmdBlock({ command: "grep a ~/f" }), "shell-active-token"],
    ["a history bang", cmdBlock({ command: "grep a !x" }), "shell-active-token"],
    ["an unclosed brace", cmdBlock({ command: "grep a {x" }), "shell-active-token"],
    ["an ANSI-C quoted git option", cmdBlock({ command: "git $'-c' alias.x=y x" }), "shell-active-token"],
    ["an ANSI-C quoted rg option", cmdBlock({ command: "rg $'--pre' cmd f" }), "shell-active-token"],
    ["an ANSI-C quoted curl option", cmdBlock({ command: "curl $'-K' f" }), "shell-active-token"],
    ["a locale-quoted word", cmdBlock({ command: 'grep $"a" f' }), "shell-active-token"],
    ["an unterminated quote", cmdBlock({ command: "grep 'a f" }), "shell-active-token"],
    ["a star inside single quotes is a literal", cmdBlock({ command: "grep -c 'a*' f" }), null],
    ["a pipe inside quotes is still refused", cmdBlock({ command: "grep -c 'a$|b*' f" }), "shell-active-token"],
    ["a dollar inside single quotes is a literal", cmdBlock({ command: "grep -c 'a$' f" }), null],
    ["a trailing dollar inside double quotes is a literal", cmdBlock({ command: 'grep -c "a$" f' }), null],
    ["a positional parameter inside double quotes", cmdBlock({ command: 'grep -c "$1" f' }), "shell-active-token"],
    ["a status parameter inside double quotes", cmdBlock({ command: 'grep -c "$?" f' }), "shell-active-token"],
    ["a process-id parameter inside double quotes", cmdBlock({ command: 'grep -c "$$" f' }), "shell-active-token"],
    ["an all-arguments parameter inside double quotes", cmdBlock({ command: 'grep -c "$@" f' }), "shell-active-token"],
    ["a curl write-out brace with no list is literal", cmdBlock({ command: "curl -s -o /dev/null -w %{http_code} http://example.invalid/x" }), null],
    // option clusters and prefixes, per verb
    ["curl -sSK (bundled)", cmdBlock({ command: "curl -sSK f http://x" }), "dangerous-option"],
    ["curl -Kfile (glued)", cmdBlock({ command: "curl -Kfile http://x" }), "dangerous-option"],
    ["curl --conf (unique prefix)", cmdBlock({ command: "curl --conf f http://x" }), "dangerous-option"],
    ["curl -sS is fine", cmdBlock({ command: "curl -sS http://x" }), null],
    ["rg --hostname-bin", cmdBlock({ command: "rg --hostname-bin x foo f" }), "dangerous-option"],
    ["rg --hostname-bin=", cmdBlock({ command: "rg --hostname-bin=x foo f" }), "dangerous-option"],
    ["rg --pretty is not --pre", cmdBlock({ command: "rg --pretty foo f" }), null],
    ["git diff --ext-diff", cmdBlock({ command: "git diff --ext-diff" }), "dangerous-option"],
    ["git diff --ext-d (prefix)", cmdBlock({ command: "git diff --ext-d" }), "dangerous-option"],
    ["git log --textconv", cmdBlock({ command: "git log --textconv" }), "dangerous-option"],
    ["git grep -O", cmdBlock({ command: "git grep -O less foo" }), "dangerous-option"],
    ["git ls-remote --upload-pack", cmdBlock({ command: "git ls-remote --upload-pack=x origin" }), "dangerous-option"],
    ["git --exec-path (global)", cmdBlock({ command: "git --exec-path=/tmp status" }), "dangerous-option"],
    // git is a read-only allowlist
    ["git status", cmdBlock({ command: "git status" }), null],
    ["git log -1", cmdBlock({ command: "git log -1 --format=%H" }), null],
    ["git ls-files", cmdBlock({ command: "git ls-files" }), null],
    ["git grep -e", cmdBlock({ command: "git grep -e foo" }), null],
    ["git rebase", cmdBlock({ command: "git rebase main" }), "unlisted-git-subcommand"],
    ["git difftool", cmdBlock({ command: "git difftool" }), "unlisted-git-subcommand"],
    ["git bisect run", cmdBlock({ command: "git bisect run x" }), "unlisted-git-subcommand"],
    ["git submodule foreach", cmdBlock({ command: "git submodule foreach x" }), "unlisted-git-subcommand"],
    ["git ls-remote", cmdBlock({ command: "git ls-remote origin" }), "unlisted-git-subcommand"],
    ["git -C dir status", cmdBlock({ command: "git -C dir status" }), "unlisted-git-subcommand"],
    ["a bare git", cmdBlock({ command: "git" }), "unlisted-git-subcommand"],
  ];

  test("every row yields exactly the expected reason", () => {
    // An exception is recorded as a value, so a guard whose deletion makes the code crash is killed
    // by a failed assertion on that row and not by the harness dying (a crash is not a kill).
    const code = [
      "out = []",
      "for b in data:",
      "    try:",
      "        out.append(fc.static_problem(b))",
      "    except Exception as e:",
      "        out.append('EXC:' + type(e).__name__)",
    ].join("\n");
    const got: (string | null)[] = harness(code, rows.map((r) => r[1]));
    expect(got.length).toBe(rows.length);
    rows.forEach(([name, , want], i) => {
      expect([name, got[i]]).toEqual([name, want]);
    });
  });

  test("instrument: the table has both accepting and rejecting rows and many distinct reasons", () => {
    expect(rows.filter((r) => r[2] === null).length).toBeGreaterThanOrEqual(4);
    expect(new Set(rows.map((r) => r[2]).filter(Boolean)).size).toBeGreaterThanOrEqual(12);
  });

  test("a shell-active block is refused at VERIFY (nothing is shown or run)", () => {
    const r = new Repo();
    r.freeze({ ...BASE, command: "grep a f; id" });
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("shell-active-token");
  });

  test("a block with two command keys is FAIL unparseable", () => {
    const r = new Repo();
    r.freeze(BASE, "p.md", OPERATOR, { extra: ['command: "grep -c b f"'] });
    expect(r.verify().json?.reason).toBe("unparseable");
  });

  test("a flow collection with content is refused (only the literals [] and {} are accepted)", () => {
    const r = new Repo();
    r.freeze(BASE, "p.md", OPERATOR, { hash: null, extra: ["pins: {a: b}"] });
    // the extra line duplicates `pins:`, which is also refused; either way a flow map is not accepted
    expect(r.verify().json?.outcome).toBe("FAIL");
  });
});

// ---------------------------------------------------------------------------------------------
describe("verify: authorship (Guard 3)", () => {
  const frozen = (email: string) => {
    const r = new Repo();
    r.freeze(BASE, "p.md", email);
    r.write("src/a.txt", "a\n");
    r.commit("code");
    return r;
  };

  test("a freeze authored by someone other than the local operator is UNTRUSTED", () => {
    const v = frozen(STRANGER).verify();
    expect(v.json?.outcome).toBe("UNTRUSTED");
    expect(v.json?.flags).toContain("freeze-author");
    expect(v.json?.freeze_author).toBe(STRANGER);
    expect(v.json?.block?.command).toBe(BASE.command); // shown, never run
  });

  test("a forged operator email alone is NOT trusted when the PR login is unknown", () => {
    const r = frozen(OPERATOR); // a contributor can set --author to the maintainer's public email
    const v = r.py(["verify", "--base", "origin/main"]); // a PR may exist and no login was supplied
    expect(v.json?.outcome).toBe("UNTRUSTED");
    expect(v.json?.flags).toContain("pr-author-unmeasurable");
    expect(v.json?.pr_author_checked).toBe(false);
  });

  test("only one of the two logins supplied is unmeasurable, never skipped", () => {
    const r = frozen(OPERATOR);
    const a = r.py(["verify", "--base", "origin/main", "--pr-author", "someone"]);
    const b = r.py(["verify", "--base", "origin/main", "--operator-login", "someone"]);
    for (const v of [a, b]) {
      expect(v.json?.outcome).toBe("UNTRUSTED");
      expect(v.json?.flags).toContain("pr-author-unmeasurable");
    }
  });

  test("matching PR author and operator login is OK and reports the comparison happened", () => {
    const v = frozen(OPERATOR).py(["verify", "--base", "origin/main", "--pr-author", "Jean", "--operator-login", "jean"]);
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.pr_author_checked).toBe(true);
  });

  test("a PR author who is not the authenticated login is UNTRUSTED (pr-author)", () => {
    const v = frozen(OPERATOR).py(["verify", "--base", "origin/main", "--pr-author", "contributor", "--operator-login", "jean"]);
    expect(v.json?.outcome).toBe("UNTRUSTED");
    expect(v.json?.flags).toContain("pr-author");
  });

  test("--no-pr states there is no PR: the operator-authored freeze is OK (must-PASS)", () => {
    const v = frozen(OPERATOR).verify();
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.pr_author_checked).toBe(false);
  });

  test("verify emits the head sha and whether the tree is dirty", () => {
    const r = frozen(OPERATOR);
    const clean = r.verify();
    expect(clean.json?.head_sha).toBe(r.git(["rev-parse", "HEAD"]).trim());
    expect(clean.json?.dirty).toBe(false);
    r.write("src/dirty.txt", "x\n");
    expect(r.verify().json?.dirty).toBe(true);
  });
});

describe("verify: outputs and failure modes", () => {
  test("--command-out is written ONLY for an OK verdict (exact bytes, no newline); any other outcome leaves it absent", () => {
    const ok = new Repo();
    ok.freeze();
    ok.write("src/a.txt", "a\n");
    ok.commit("code");
    const good = join(ok.scratch, "cmd.txt");
    expect(ok.verify(["--command-out", good]).json?.outcome).toBe("OK");
    expect(readFileSync(good, "utf8")).toBe(BASE.command);
    for (const [name, build] of [
      ["UNTRUSTED", (r: Repo) => r.freeze(BASE, "p.md", STRANGER)],
      ["CHANGED-SINCE-APPROVAL", (r: Repo) => { r.freeze(); r.write("src/a.txt", "a\n"); r.commit("code"); r.freeze({ ...BASE, expected: "9" }); }],
      ["FAIL", (r: Repo) => r.freeze({ ...BASE, command: "echo a; echo b" })],
    ] as const) {
      const r = new Repo();
      build(r);
      if (name === "UNTRUSTED" || name === "FAIL") { r.write("src/a.txt", "a\n"); r.commit("code"); }
      const f = join(r.scratch, "cmd.txt");
      const v = r.verify(["--command-out", f]);
      expect([name, v.json?.outcome, existsSync(f)]).toEqual([name, name === "FAIL" ? "FAIL" : name, false]);
    }
  });

  test("--display-out carries an escaped, display-only copy for every outcome that parsed a block (no raw control bytes)", () => {
    const r = new Repo();
    r.freeze({ ...BASE, command: "grep a\u001b[2J f" }, "p.md", STRANGER); // an ESC in the command: FAIL control-character
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const f = join(r.scratch, "disp.txt");
    const v = r.verify(["--display-out", f]);
    expect(v.json?.outcome).toBe("FAIL");
    const shown = readFileSync(f, "utf8");
    expect(shown).toContain("grep a\\x1b[2J f");
    expect(shown).not.toMatch(/[\u0000-\u0009\u000b-\u001f\u007f\u2028\u2029]/);
    // and for a clean UNTRUSTED block it shows the command as written
    const u = new Repo();
    u.freeze(BASE, "p.md", STRANGER);
    u.write("src/a.txt", "a\n");
    u.commit("code");
    const g = join(u.scratch, "disp.txt");
    expect(u.verify(["--display-out", g]).json?.outcome).toBe("UNTRUSTED");
    expect(readFileSync(g, "utf8").trimEnd()).toBe(BASE.command);
  });

  test("hash-object ignores .gitattributes filters: a CRLF copy of a pinned script is a changed script", () => {
    const r = new Repo();
    r.git(["checkout", "-q", "main"]);
    r.write(".gitattributes", "*.sh text eol=lf\n");
    r.write("scripts/ok.sh", "#!/bin/bash\necho 1\n");
    r.commit("main: a script under an eol filter");
    r.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    r.git(["checkout", "-q", "feat-x"]);
    r.git(["rebase", "-q", "main"]);
    r.freeze({ ...BASE, command: "bash scripts/ok.sh", pins: { "scripts/ok.sh": r.blob("scripts/ok.sh") } });
    r.write("scripts/ok.sh", "#!/bin/bash\r\necho 1\r\n"); // different bytes, equal after the eol filter
    const v = r.verify();
    expect([v.json?.outcome, v.json?.reasons]).toEqual(["CHANGED-SINCE-APPROVAL", ["pinned-script-changed"]]);
  });

  test("a plan whose path git would quote (a double quote, non-ASCII) is found, never a silent NO-BLOCK", () => {
    const r = new Repo();
    r.plan('p"q é.md', scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.commit("plan: freeze");
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const v = r.verify();
    expect([v.json?.outcome, v.json?.plan]).toEqual(["OK", `${PLANS}/p"q é.md`]);
  });

  test("an UNTRACKED plan whose path git would quote is found through the NUL-separated listing", () => {
    const r = new Repo();
    r.plan('p"q é.md', scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    const v = r.verify(["--candidate"]);
    expect([v.json?.outcome, v.json?.plan]).toEqual(["OK", `${PLANS}/p"q é.md`]);
  });

  test("a block frozen in a plan renamed outside the archive follows the rename even with rename detection off", () => {
    const r = new Repo();
    r.git(["config", "diff.renames", "false"]);
    r.freeze(BASE, "p.md");
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.git(["mv", `${PLANS}/p.md`, `${PLANS}/q.md`]);
    r.commit("rename the plan");
    const v = r.verify();
    expect([v.json?.outcome, v.json?.plan]).toEqual(["OK", `${PLANS}/q.md`]);
  });

  test("an oversized blob is never read: _blocks_at asks for its size first and does not `show` it", () => {
    const r = new Repo();
    const big = scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }) + "x".repeat(1_200_000);
    r.plan("big.md", big);
    r.plan("small.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.commit("plans");
    const code = [
      "calls = []",
      "orig = fc._out",
      "def spy(args, cwd):",
      "    calls.append(args[0])",
      "    return orig(args, cwd)",
      "fc._out = spy",
      "big = fc._blocks_at(data, 'HEAD', 'knowledge-base/project/plans/big.md')",
      "n_show = calls.count('show')",
      "small = fc._blocks_at(data, 'HEAD', 'knowledge-base/project/plans/small.md')",
      "out = {'big': big, 'shown_for_big': n_show, 'small_blocks': len(small), 'sized': calls.count('cat-file') >= 2}",
    ].join("\n");
    const got = harness(code, r.dir);
    expect(got).toEqual({ big: [], shown_for_big: 0, small_blocks: 1, sized: true });
  });

  test("a branch longer than the commit cap is refused, not sampled", () => {
    const r = new Repo();
    for (let i = 0; i < 5; i++) {
      r.write(`src/f${i}.txt`, "x\n");
      r.commit(`c${i}`);
    }
    const code = [
      "fc.MAX_COMMITS = 3",
      "out = {'cap3': fc._history(data, 'main'), 'cap100': len(fc._history(data, 'main') if False else [])}",
    ].join("\n");
    expect(harness(code, r.dir).cap3).toBeNull();
    const ok = harness("fc.MAX_COMMITS = 100\nout = len(fc._history(data, 'main'))", r.dir);
    expect(ok).toBe(5);
  });

  test("a parse error never echoes a long line back (the detail is capped)", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE).replace("  kind: command", "  " + "x".repeat(5000)) }));
    const v = r.verify(["--candidate"]);
    expect(v.json?.reason).toBe("unparseable");
    expect(String(v.json?.detail).length).toBeLessThanOrEqual(120);
  });

  test("a --no-pr declaration is visible in the verify record, and a PR check clears it", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    expect(r.verify().json?.no_pr).toBe(true);
    expect(r.verify(["--pr-author", "octocat", "--operator-login", "octocat"]).json?.no_pr).toBe(false);
  });

  test("a re-freeze commit whose block does not parse is ignored (the earlier freeze stays the freeze)", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE).replace("  kind: command", '  kind: command\n  text: "dup"') }));
    r.commit("plan: re-freeze founder-stated check");
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, expected: "2" }) }));
    r.commit("plan: tidy the check");
    const v = r.verify(["--mode", "interactive"]);
    expect([v.json?.outcome, v.json?.freeze_source]).toEqual(["CHANGED-SINCE-APPROVAL", "branch"]);
  });

  test("an operator email configured in upper case is the same operator", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const v = r.py(["verify", "--base", "origin/main", "--no-pr"], { GIT_AUTHOR_EMAIL: OPERATOR.toUpperCase() });
    expect(v.json?.outcome).toBe("OK");
  });

  test("a hash: that disagrees with the block's own fields is FAIL, whether the wrong one is at the freeze or at HEAD", () => {
    // wrong at HEAD only
    const a = new Repo();
    a.freeze();
    a.write("src/a.txt", "a\n");
    a.commit("code");
    a.freeze(BASE, "p.md", OPERATOR, { hash: "0".repeat(64) });
    expect(a.verify().json?.reason).toBe("hash-mismatch");
    // wrong at the freeze only (HEAD repaired afterwards, canonical fields unchanged)
    const b = new Repo();
    b.freeze(BASE, "p.md", OPERATOR, { hash: "0".repeat(64) });
    b.write("src/a.txt", "a\n");
    b.commit("code");
    b.freeze(BASE, "p.md", OPERATOR, {});
    expect(b.verify().json?.reason).toBe("hash-mismatch");
  });

  test("a freeze copy that does not parse says so ('freeze copy:'); an unparseable HEAD block does not", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE).replace('  kind: command', '  kind: command\n  text: "second"') }));
    r.commit("plan: freeze with a duplicate key");
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.freeze();
    const v = r.verify();
    expect([v.json?.reason, String(v.json?.detail).startsWith("freeze copy: ")]).toEqual(["unparseable", true]);
    const h = new Repo();
    h.freeze();
    h.write("src/a.txt", "a\n");
    h.commit("code");
    h.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE).replace('  kind: command', '  kind: command\n  text: "second"') }));
    h.commit("break the block");
    const w = h.verify();
    expect([w.json?.reason, String(w.json?.detail).startsWith("freeze copy: ")]).toEqual(["unparseable", false]);
  });

  test("the static rules judge the FROZEN block: an edit to a forbidden command is a change, not a rejection", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.freeze({ ...BASE, command: "rm -rf x" });
    expect(r.verify().json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
  });

  test("identities compare case-insensitively: an upper-case commit email and PR login are the operator", () => {
    const r = new Repo();
    r.freeze(BASE, "p.md", OPERATOR.toUpperCase());
    r.write("src/a.txt", "a\n");
    r.commit("code");
    expect(r.verify().json?.outcome).toBe("OK");
    const pr = r.verify(["--pr-author", "OctoCat", "--operator-login", "octocat"]);
    expect([pr.json?.outcome, pr.json?.pr_author_checked]).toEqual(["OK", true]);
    expect(r.verify(["--pr-author", "octocat", "--operator-login", "someone-else"]).json?.flags).toContain("pr-author");
  });

  test("non-ASCII text hashes as written (the canonical hash is not ASCII-escaped)", () => {
    const f = { ...BASE, text: "the café page says ✓ — 日本語" };
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(f) }));
    const v = r.verify(["--candidate"]);
    expect([v.json?.outcome, v.json?.hash]).toEqual(["OK", canonicalHash(f)]);
  });

  test("--plan accepts a plan under the plans directory and refuses a sibling directory with the same prefix", () => {
    const r = new Repo();
    r.write("knowledge-base/project/plans-x/p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.commit("a plan outside the plans directory");
    const v = r.py(["verify", "--base", "origin/main", "--no-pr", "--plan", "knowledge-base/project/plans-x/p.md"]);
    expect([v.json?.outcome, v.json?.reason]).toEqual(["FAIL", "plan-outside-plans-dir"]);
    const ok = new Repo();
    ok.freeze();
    expect(ok.py(["verify", "--base", "origin/main", "--no-pr", "--plan", `${PLANS}/p.md`]).json?.outcome).not.toBe("FAIL");
  });

  test("archival is followed even when git's rename detection is off in the repository", () => {
    const r = new Repo();
    r.git(["config", "diff.renames", "false"]);
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    mkdirSync(join(r.dir, PLANS, "archive"), { recursive: true });
    r.git(["mv", `${PLANS}/p.md`, `${PLANS}/archive/20261006-120000-p.md`]);
    r.commit("archive the plan");
    expect(r.verify().json?.outcome).toBe("OK");
  });

  test("abbreviated flags are refused at every subcommand (allow_abbrev is off)", () => {
    const r = new Repo();
    expect(r.py(["verify", "--bas", "origin/main"]).status).toBe(2);
    expect(r.py(["log", "--outc", "PASSED"]).status).toBe(2);
    const j = r.freeze({ ...BASE, kind: "judgement", command: "" }) && r.verifyFile();
    const abbr = r.py(["log", "--verify-j", j.file, "--polarity", "acceptance", "--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    expect([abbr.status, abbr.stderr]).toEqual([2, expect.stringContaining("required: --verify-json")]);
    expect(r.py(["text", "--lis"]).status).toBe(2);
    expect(r.py(["summar"]).status).toBe(2);
  });

  test("text --underlying only takes a cause the script knows", () => {
    const r = new Repo();
    expect(r.py(["text", "headless-stop", "--underlying", "BOGUS"]).status).toBe(2);
    expect(r.py(["text", "headless-stop", "--underlying", "FAILED"]).status).toBe(0);
  });

  test("text strips control characters from the record's detail before printing it", () => {
    const r = new Repo();
    const f = join(r.scratch, "d.json");
    writeFileSync(f, JSON.stringify({ outcome: "FAIL", reason: "a-future-reason", detail: "bad\u001b[2J\u2028detail" }));
    const t = r.py(["text", "rejected-ask", "--verify-json", f]);
    expect(t.stdout).toContain("Reason: bad [2J detail");
    expect(t.stdout).not.toMatch(/[\u0000-\u0009\u000b-\u001f\u007f\u2028\u2029]/);
  });

  test("a verb gate that cannot be run is FAIL verb-gate-unavailable, never an accept", () => {
    const dir = mkdtempSync(join(TMP, "fcng-"));
    made.push(dir);
    const lone = join(dir, "founder-check.py"); // no probe-verb-gate.sh beside it
    writeFileSync(lone, readFileSync(SCRIPT, "utf8"));
    expect(harness("out = fc.static_problem(data)", cmdBlock())).toBeNull();
    expect(harness("out = fc.static_problem(data)", cmdBlock(), lone)).toBe("verb-gate-unavailable");
  });

  test("a freeze commit that ALSO carries code is an ordering failure (the commonest one)", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.write("src/a.txt", "a\n");
    r.commit("plan: freeze and code together");
    const v = r.verify();
    expect([v.json?.outcome, v.json?.reasons]).toEqual(["CHANGED-SINCE-APPROVAL", ["ordering"]]);
  });

  test("a block moved from one plan to another is FAIL freeze-without-block, not an accept", () => {
    const r = new Repo();
    r.freeze(BASE, "a.md");
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.plan("a.md", scaffold("plan-no-block.md", {}));
    r.freeze(BASE, "b.md");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("freeze-without-block");
  });

  test("the founder-check log in the tree does not make the next verify read as dirty (the Retry flow)", () => {
    const r = new Repo();
    r.freeze({ ...BASE, kind: "judgement", command: "" });
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const first = r.verifyFile();
    expect(first.run.json?.dirty).toBe(false);
    expect(r.py(["log", "--verify-json", first.file, "--polarity", "acceptance", "--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]).status).toBe(0);
    expect(r.git(["status", "--porcelain", "--untracked-files=all"]).includes("founder-check-log.md")).toBe(true); // the row is really there, untracked
    expect(r.verify().json?.dirty).toBe(false);
    r.write("src/other.txt", "x\n");
    expect(r.verify().json?.dirty).toBe(true);
  });

  test("a default branch other than main or master anchors a freeze only through origin/HEAD", () => {
    const r = new Repo();
    r.git(["update-ref", "refs/remotes/origin/trunk", "main"]);
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const run = (base: string) => r.py(["verify", "--base", base, "--no-pr"]);
    expect(run("origin/trunk").json?.reason).toBe("base-not-default-branch");
    r.git(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk"]);
    expect(run("origin/trunk").json?.outcome).toBe("OK");
    expect(run("origin/feature").json?.reason).toBe("base-not-default-branch");
  });

  test("a re-freeze with the PR login unmeasured is UNTRUSTED, like any freeze that was not reviewed on main", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, expected: "2" }) }));
    r.commit("plan: re-freeze founder-stated check");
    const v = r.py(["verify", "--base", "origin/main", "--mode", "interactive"]);
    expect([v.json?.outcome, v.json?.flags]).toEqual(["UNTRUSTED", ["pr-author-unmeasurable"]]);
  });

  test("an internal error is one JSON FAIL line and exit 4, never a traceback", () => {
    const v = runPy(["verify", "--repo", join(TMP, "fc-does-not-exist-" + process.pid)], { cwd: TMP, env: gitFixtureEnv(TMP) });
    expect(v.status).toBe(4);
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("internal-error");
    expect(v.stderr).not.toContain("Traceback");
  });
});

// ---------------------------------------------------------------------------------------------
describe("classify: the verdict matrix (in-process)", () => {
  // [rc, stdout, expected, polarity, first_token, sandbox_healthy] -> [outcome, matched, reason]
  const rows: [string, [number, string, string, string, string, boolean], string, string][] = [
    ["acceptance pass", [0, "ok", "ok", "acceptance", "grep", true], "PASSED", "ran-returned-success"],
    ["acceptance pass, empty expected means exit 0", [0, "", "", "acceptance", "grep", true], "PASSED", "ran-returned-success"],
    ["acceptance rc 0 but expected absent", [0, "no", "ok", "acceptance", "grep", true], "FAILED", "non-zero-or-expected-absent"],
    ["acceptance rc 1", [1, "ok", "ok", "acceptance", "grep", true], "FAILED", "non-zero-or-expected-absent"],
    ["baseline rc 0 + matched is vacuous", [0, "ok", "ok", "baseline", "grep", true], "VACUOUS", "baseline-passes"],
    ["baseline rc 1 is a valid fail", [1, "", "ok", "baseline", "grep", true], "FAILED-AS-EXPECTED", "baseline-fails"],
    ["baseline rc 0 but expected absent is a valid fail", [0, "no", "ok", "baseline", "grep", true], "FAILED-AS-EXPECTED", "baseline-fails"],
    ["rc 124 (timeout) is INVALID", [124, "", "ok", "acceptance", "grep", true], "INVALID", "tooling-rc-124"],
    ["rc 126 is INVALID, even at baseline", [126, "", "ok", "baseline", "rg", true], "INVALID", "tooling-rc-126"],
    ["rc 127 is INVALID, even at baseline", [127, "", "ok", "baseline", "rg", true], "INVALID", "tooling-rc-127"],
    ["curl rc 6 is INVALID", [6, "", "ok", "acceptance", "curl", true], "INVALID", "curl-rc-6"],
    ["curl rc 28 at baseline is INVALID", [28, "", "ok", "baseline", "curl", true], "INVALID", "curl-rc-28"],
    ["curl rc 7 is INVALID", [7, "", "ok", "acceptance", "curl", true], "INVALID", "curl-rc-7"],
    ["rc 124 at baseline is INVALID", [124, "", "ok", "baseline", "grep", true], "INVALID", "tooling-rc-124"],
    ["rc 6 for a non-curl verb is an ordinary fail", [6, "", "ok", "acceptance", "grep", true], "FAILED", "non-zero-or-expected-absent"],
    ["an unhealthy sandbox is INVALID at acceptance", [0, "ok", "ok", "acceptance", "grep", false], "INVALID", "sandbox-unhealthy"],
    ["an unhealthy sandbox is INVALID at baseline too", [1, "", "ok", "baseline", "grep", false], "INVALID", "sandbox-unhealthy"],
  ];

  test("every row yields exactly the expected verdict", () => {
    const got: [string, boolean, string][] = harness("out = [list(fc.classify(*c)) for c in data]", rows.map((r) => r[1]));
    expect(got.length).toBe(rows.length);
    rows.forEach(([name, , outcome, reason], i) => {
      expect([name, got[i][0], got[i][2]]).toEqual([name, outcome, reason]);
    });
  });
});

describe("classify: the CLI reads the verify record and measured inputs only", () => {
  const frozenFile = (cmd = BASE.command, expected = "1") => {
    const r = new Repo();
    r.freeze({ ...BASE, command: cmd, expected });
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const { file, run } = r.verifyFile();
    expect(run.json?.outcome).toBe("OK");
    return { r, file };
  };
  const cls = (r: Repo, args: string[]) => r.classify(args);

  test("acceptance: --stdout-file carries the output the expected text is matched against", () => {
    const { r, file } = frozenFile();
    const out = join(r.scratch, "out.txt");
    writeFileSync(out, "the count is 1\n");
    const pass = cls(r, ["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0", "--stdout-file", out]);
    expect(pass.json?.outcome).toBe("PASSED");
    expect(pass.json?.expected_matched).toBe(true);
    writeFileSync(out, "nothing here\n");
    expect(cls(r, ["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0", "--stdout-file", out]).json?.outcome).toBe("FAILED");
  });

  test("an empty expected in the record is matched by exit 0 alone (the expected text comes from the record, not argv)", () => {
    const { r, file } = frozenFile(BASE.command, "");
    expect(cls(r, ["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0"]).json?.outcome).toBe("PASSED");
  });

  test("a failing health control makes the verdict INVALID at BOTH polarities", () => {
    const { r, file } = frozenFile();
    const a = cls(r, ["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "1"]);
    expect(a.json?.outcome).toBe("INVALID");
    expect(a.json?.reason).toBe("sandbox-unhealthy");
  });

  test("a missing --control-rc is a usage error (no permissive default), and so is a missing --verify-json", () => {
    const { r, file } = frozenFile();
    expect(cls(r, ["--verify-json", file, "--polarity", "acceptance", "--rc", "0"]).status).toBe(2);
    expect(cls(r, ["--polarity", "acceptance", "--rc", "0", "--control-rc", "0"]).status).toBe(2);
  });

  test("a health control that returns 124, 126, 127 or 2 is unhealthy, not just 1", () => {
    const { r, file } = frozenFile();
    for (const c of ["2", "124", "126", "127", "255"]) {
      const a = cls(r, ["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", c]);
      expect([c, a.json?.outcome, a.json?.reason]).toEqual([c, "INVALID", "sandbox-unhealthy"]);
    }
  });

  test("a polarity outside baseline|acceptance, an abbreviated flag and an unreadable --stdout-file are refused", () => {
    const { r, file } = frozenFile();
    expect(cls(r, ["--verify-json", file, "--polarity", "Acceptance", "--rc", "0", "--control-rc", "0"]).status).toBe(2);
    expect(cls(r, ["--verify-json", file, "--polarity", "accept", "--rc", "0", "--control-rc", "0"]).status).toBe(2);
    expect(cls(r, ["--verify-j", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0"]).status).toBe(2); // allow_abbrev is off
    const missing = cls(r, ["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0", "--stdout-file", join(r.scratch, "no-such.txt")]);
    expect([missing.status, missing.stderr]).toEqual([2, expect.stringContaining("cannot read --stdout-file")]);
  });

  test("a quoted curl verb is still curl: rc 6 is INVALID", () => {
    const { r, file } = frozenFile('"curl" -s http://example.invalid/x');
    expect(cls(r, ["--verify-json", file, "--polarity", "acceptance", "--rc", "6", "--control-rc", "0"]).json?.outcome).toBe("INVALID");
  });

  test("classify refuses a record whose verify outcome is not OK (a changed check is never run)", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.freeze({ ...BASE, expected: "9" });
    const { file, run } = r.verifyFile();
    expect(run.json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(cls(r, ["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0"]).status).toBe(2);
  });

  test("baseline needs a candidate record and acceptance refuses one", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    const cand = r.verifyFile(["--candidate"], "cand.json");
    expect(cand.run.json?.outcome).toBe("OK");
    expect(cand.run.json?.reason).toBe("candidate");
    expect(cls(r, ["--verify-json", cand.file, "--polarity", "baseline", "--rc", "1", "--control-rc", "0"]).json?.outcome).toBe("FAILED-AS-EXPECTED");
    expect(cls(r, ["--verify-json", cand.file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0"]).status).toBe(2);
    const { r: fr, file } = frozenFile();
    expect(cls(fr, ["--verify-json", file, "--polarity", "baseline", "--rc", "1", "--control-rc", "0"]).status).toBe(2);
  });

  test("a judgement check is never classified", () => {
    const r = new Repo();
    r.freeze({ ...BASE, kind: "judgement", command: "" });
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const { file, run } = r.verifyFile();
    expect(run.json?.outcome).toBe("OK");
    expect(cls(r, ["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0"]).status).toBe(2);
  });
});

describe("verify --candidate (baseline mode)", () => {
  test("a block with no freeze commit passes the static rules and every pin against HEAD", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    const v = r.verify(["--candidate"]);
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.hash).toBe(canonicalHash(BASE));
  });

  test("the candidate hash is what the plan skill writes into hash: (a stale one is FAIL)", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE, { hash: "0".repeat(64) }) }));
    expect(r.verify(["--candidate"]).json?.reason).toBe("hash-mismatch");
  });

  test("an interpreter script that is not pinned (or not at HEAD) is refused at baseline", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, command: "bash scripts/new.sh" }) }));
    expect(r.verify(["--candidate"]).json?.reason).toBe("unpinned-script");
  });

  test("no block at all is an ERROR in candidate mode, never a success", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-no-block.md", {}));
    const v = r.verify(["--candidate"]);
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("no-block-candidate");
    expect(v.status).toBe(1);
  });

  test("a block under an unrecognised heading is an ERROR in candidate mode (it cannot be baselined and frozen unseen)", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-quoted-non-ac.md", { BLOCK: renderBlock(BASE) }));
    expect(r.verify(["--candidate"]).json?.reason).toBe("no-block-candidate");
  });

  test("candidate mode is refused when a freeze exists, unless --refreeze says this is a deliberate change", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.freeze({ ...BASE, expected: "2" });
    const refused = r.verify(["--candidate"]);
    expect(refused.json?.outcome).toBe("FAIL");
    expect(refused.json?.reason).toBe("candidate-refused-frozen");
    const ok = r.verify(["--candidate", "--refreeze"]);
    expect(ok.json?.outcome).toBe("OK");
    expect(ok.json?.refreeze).toBe(true);
  });
});

// ---------------------------------------------------------------------------------------------
describe("log: the only writer of outcomes", () => {
  const FROZEN = () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    return r;
  };
  /** A frozen command check with a verify record and its command file. */
  const FROZEN_V = () => {
    const r = FROZEN();
    const { file, run } = r.verifyFile();
    expect(run.json?.outcome).toBe("OK");
    return { r, file };
  };
  /** A frozen judgement check: the cheapest verify record `log` can honestly write a row from. */
  const JUDGED = () => {
    const r = new Repo();
    r.freeze({ ...BASE, kind: "judgement", command: "" });
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const { file, run } = r.verifyFile();
    expect(run.json?.outcome).toBe("OK");
    return { r, file };
  };
  /** Classify the frozen command at `rc`; returns the classify record's path. */
  const classified = (r: Repo, file: string, rc: number, out = "cl.json") => {
    const cl = join(r.scratch, out);
    const c = r.classify(["--verify-json", file, "--polarity", "acceptance", "--rc", String(rc), "--control-rc", "0", "--out", cl]);
    expect(c.status).toBe(0);
    return cl;
  };
  /** One real record set per stopped outcome: what the wrapper would hand `log`. */
  const scenario = (o: string): { r: Repo; file: string; extra: string[] } => {
    if (o === "NEEDS-YOUR-EYES") return { ...JUDGED(), extra: [] };
    let r = FROZEN();
    if (o === "UNTRUSTED") {
      r = new Repo();
      r.freeze(BASE, "p.md", STRANGER);
      r.write("src/a.txt", "a\n");
      r.commit("code");
    } else if (o === "CHANGED-SINCE-APPROVAL") {
      r.freeze({ ...BASE, expected: "9" });
    } else if (o === "BLOCK-REJECTED") {
      r = new Repo();
      r.freeze({ ...BASE, command: "echo a; echo b" });
      r.write("src/a.txt", "a\n");
      r.commit("code");
    }
    const { file, run } = r.verifyFile();
    expect(run.json?.outcome).toBe({ UNTRUSTED: "UNTRUSTED", "CHANGED-SINCE-APPROVAL": "CHANGED-SINCE-APPROVAL", "BLOCK-REJECTED": "FAIL" }[o] ?? "OK");
    if (o === "FAILED") return { r, file, extra: ["--classify-json", classified(r, file, 1)] };
    if (o === "INVALID") return { r, file, extra: ["--classify-json", classified(r, file, 127)] };
    return { r, file, extra: [] };
  };
  const LOGDIR = "knowledge-base/project/specs/feat-x";
  const logPath = (r: Repo) => join(r.dir, LOGDIR, "founder-check-log.md");
  const log = (r: Repo, vj: string, extra: string[], input?: string, env: Record<string, string> = {}) =>
    runPy(["log", "--verify-json", vj, "--polarity", "acceptance", ...extra], { cwd: r.dir, env: r.env(env), input });
  const cells = (r: Repo): string[][] =>
    readFileSync(logPath(r), "utf8")
      .split("\n")
      .filter((l) => l.startsWith("|"))
      .slice(2)
      .map((l) => l.split(/(?<!\\)\|/).slice(1, -1).map((c) => c.trim()));
  const COLS = ["kind", "polarity", "command", "rc", "outcome", "underlying", "attempt_n", "tested_sha", "block_hash", "time_utc", "expected_matched", "reason", "freeze_source", "no_pr"];

  test("a row carries every column; the path is derived from the branch; the marker is metadata only", () => {
    const r = FROZEN();
    const { file } = r.verifyFile();
    const cl = join(r.scratch, "cl.json");
    const out = join(r.scratch, "out.txt");
    writeFileSync(out, "SECRET-OUTPUT-TEXT 1\n");
    r.classify(["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0", "--stdout-file", out, "--out", cl]);
    const l = log(r, file, ["--mode", "interactive", "--outcome", "PASSED", "--classify-json", cl, "--attempt-n", "2"]);
    expect(l.status).toBe(0);
    expect(l.stdout.trim()).toBe(`SOLEUR_FOUNDER_CHECK_RESULT outcome=PASSED hash=${canonicalHash(BASE)} tested_sha=${r.git(["rev-parse", "HEAD"]).trim().slice(0, 12)}`);
    const text = readFileSync(logPath(r), "utf8");
    expect(text).not.toContain("SECRET-OUTPUT-TEXT"); // the log never holds output text
    const [row] = cells(r);
    const o = Object.fromEntries(COLS.map((c, i) => [c, row[i]]));
    expect(o.kind).toBe("command");
    expect(o.polarity).toBe("acceptance");
    expect(o.command).toBe(BASE.command);
    expect(o.rc).toBe("0");
    expect(o.outcome).toBe("PASSED");
    expect(o.attempt_n).toBe("2");
    expect(o.tested_sha).toBe(r.git(["rev-parse", "HEAD"]).trim().slice(0, 12));
    expect(o.block_hash).toBe(canonicalHash(BASE));
    expect(o.expected_matched).toBe("true");
    expect(o.time_utc).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
  });

  test("a dirty tree is recorded as +uncommitted in tested_sha", () => {
    const { r, file: f0 } = JUDGED();
    r.write("src/dirty.txt", "x\n");
    const { file } = r.verifyFile();
    expect(f0).toBeTruthy();
    log(r, file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    expect(cells(r)[0][COLS.indexOf("tested_sha")]).toMatch(/^[0-9a-f]{12}\+uncommitted$/);
  });

  for (const outcome of ["FAILED", "INVALID", "CHANGED-SINCE-APPROVAL", "UNTRUSTED", "NEEDS-YOUR-EYES", "BLOCK-REJECTED"]) {
    test(`headless: ${outcome} is recorded as STOPPED-AWAITING-FOUNDER with the cause kept`, () => {
      const { r, file, extra } = scenario(outcome);
      const l = log(r, file, ["--mode", "headless", "--outcome", outcome, ...extra]);
      expect(l.status).toBe(0);
      expect(l.stdout).toContain("outcome=STOPPED-AWAITING-FOUNDER");
      const row = cells(r)[0];
      expect(row[COLS.indexOf("outcome")]).toBe("STOPPED-AWAITING-FOUNDER");
      expect(row[COLS.indexOf("underlying")]).toBe(outcome);
    });
  }

  test("headless: a missing sandbox with an approved block stops the run", () => {
    const r = FROZEN();
    const { file } = r.verifyFile();
    log(r, file, ["--mode", "headless", "--outcome", "SKIP-NOSANDBOX"]);
    const row = cells(r)[0];
    expect(row[COLS.indexOf("outcome")]).toBe("STOPPED-AWAITING-FOUNDER");
    expect(row[COLS.indexOf("underlying")]).toBe("SKIP-NOSANDBOX");
  });

  test("headless: OVERRIDDEN and FOUNDER-CONFIRMED are refused (exit 3) and write no row", () => {
    const r = FROZEN();
    const { file } = r.verifyFile();
    for (const o of ["OVERRIDDEN", "FOUNDER-CONFIRMED"]) {
      const l = log(r, file, ["--mode", "headless", "--outcome", o, "--underlying", "FAILED", "--reason-stdin"], "because\n");
      expect(l.status).toBe(3);
    }
    expect(existsSync(logPath(r))).toBe(false);
  });

  test("unknown or case-variant outcomes and modes are usage errors, never recorded", () => {
    const r = FROZEN();
    const { file } = r.verifyFile();
    for (const bad of ["overridden", "OVERRIDDEN ", "NOPE", "pass"]) {
      expect(log(r, file, ["--mode", "headless", "--outcome", bad]).status).toBe(2);
    }
    for (const bad of ["Headless", "HEADLESS", "interactive "]) {
      expect(log(r, file, ["--mode", bad, "--outcome", "OVERRIDDEN", "--underlying", "FAILED", "--reason-stdin"], "x\n").status).toBe(2);
    }
    expect(runPy(["log", "--verify-json", file, "--mode", "interactive", "--outcome", "PASSED"], { cwd: r.dir, env: r.env() }).status).toBe(2); // --polarity is required
    expect(existsSync(logPath(r))).toBe(false);
  });

  test("every row column follows its record: rc, polarity, kind and expected_matched are not constants", () => {
    // acceptance, rc 1, expected text absent: FAILED with expected_matched false and rc 1
    const f = scenario("FAILED");
    expect(log(f.r, f.file, ["--mode", "interactive", "--outcome", "FAILED", ...f.extra]).status).toBe(0);
    const row = Object.fromEntries(COLS.map((c, i) => [c, cells(f.r)[0][i]]));
    expect([row.kind, row.polarity, row.rc, row.outcome, row.expected_matched]).toEqual(["command", "acceptance", "1", "FAILED", "false"]);
    // a judgement check says so
    const j = JUDGED();
    log(j.r, j.file, ["--mode", "interactive", "--outcome", "FOUNDER-CONFIRMED"]);
    const jr = Object.fromEntries(COLS.map((c, i) => [c, cells(j.r)[0][i]]));
    expect([jr.kind, jr.rc, jr.expected_matched, jr.outcome]).toEqual(["judgement", "", "", "FOUNDER-CONFIRMED"]);
    // baseline rows: FAILED-AS-EXPECTED and VACUOUS are both accepted and logged at baseline polarity
    for (const [rc, out, want] of [["1", "", "FAILED-AS-EXPECTED"], ["0", "1\n", "VACUOUS"]] as const) {
      const r = new Repo();
      r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
      const cand = r.verifyFile(["--candidate"], "cand.json");
      const so = join(r.scratch, "so.txt");
      writeFileSync(so, out);
      const cl = join(r.scratch, "cl.json");
      expect(r.classify(["--verify-json", cand.file, "--polarity", "baseline", "--rc", rc, "--control-rc", "0", "--stdout-file", so, "--out", cl]).json?.outcome).toBe(want);
      const l = runPy(["log", "--verify-json", cand.file, "--classify-json", cl, "--polarity", "baseline", "--mode", "interactive", "--outcome", want], { cwd: r.dir, env: r.env() });
      expect([want, l.status]).toEqual([want, 0]);
      const b = Object.fromEntries(COLS.map((c, i) => [c, cells(r)[0][i]]));
      expect([b.polarity, b.rc, b.outcome]).toEqual(["baseline", rc, want]);
    }
  });

  test("an override can name INVALID or BLOCK-REJECTED when the records show it", () => {
    for (const cause of ["INVALID", "BLOCK-REJECTED"]) {
      const { r, file, extra } = scenario(cause);
      const l = log(r, file, ["--mode", "interactive", "--outcome", "OVERRIDDEN", ...extra, "--underlying", cause, "--reason-stdin"], "ship it\n");
      expect([cause, l.status]).toEqual([cause, 0]);
      expect(cells(r)[0][COLS.indexOf("underlying")]).toBe(cause);
    }
  });

  test("the reason is capped, and the header is written once however many rows follow", () => {
    const { r, file, extra } = scenario("FAILED");
    const long = "x".repeat(2000);
    for (let i = 0; i < 2; i++) log(r, file, ["--mode", "interactive", "--outcome", "OVERRIDDEN", ...extra, "--underlying", "FAILED", "--reason-stdin"], long + "\n");
    const rows = cells(r);
    expect(rows.length).toBe(2);
    expect(rows[0][COLS.indexOf("reason")].length).toBeLessThanOrEqual(600);
    expect(rows[0][COLS.indexOf("reason")].length).toBeGreaterThan(500);
    expect(readFileSync(logPath(r), "utf8").split("\n").filter((l) => l.startsWith("| kind ")).length).toBe(1);
  });

  test("a bogus polarity is a usage error at log too", () => {
    const { r, file } = JUDGED();
    const l = runPy(["log", "--verify-json", file, "--polarity", "accept", "--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"], { cwd: r.dir, env: r.env() });
    expect(l.status).toBe(2);
  });

  test("an override names its cause: no cause, or a cause outside the four, is refused", () => {
    const { r, file, extra } = scenario("FAILED");
    for (const u of ["UNTRUSTED", "SKIP-NOSANDBOX", "failed"]) {
      expect([u, log(r, file, ["--mode", "interactive", "--outcome", "OVERRIDDEN", ...extra, "--underlying", u, "--reason-stdin"], "x\n").status]).toEqual([u, 2]);
    }
  });

  test("an override of a changed check with the verify record's reasons truncated and sanitised", () => {
    const { r, file } = scenario("CHANGED-SINCE-APPROVAL");
    const doc = JSON.parse(readFileSync(file, "utf8"));
    doc.reasons = ["field-changed", "x".repeat(200), "a|b\u001b[2J"];
    writeFileSync(file, JSON.stringify(doc));
    const l = log(r, file, ["--mode", "interactive", "--outcome", "OVERRIDDEN", "--underlying", "CHANGED-SINCE-APPROVAL", "--reason-stdin"], "ok\n");
    expect(l.status).toBe(0);
    const reason = cells(r)[0][COLS.indexOf("reason")];
    expect(reason).not.toContain("x".repeat(41));
    expect(reason).not.toMatch(/[\u0000-\u001f\u007f]/);
    expect(cells(r)[0].length).toBe(COLS.length);
  });

  test("an override of a changed check keeps the FROZEN command beside the reason too", () => {
    const { r, file } = scenario("CHANGED-SINCE-APPROVAL");
    const doc = JSON.parse(readFileSync(file, "utf8"));
    doc.block.command = "grep -c other f";
    writeFileSync(file, JSON.stringify(doc));
    log(r, file, ["--mode", "interactive", "--outcome", "OVERRIDDEN", "--underlying", "CHANGED-SINCE-APPROVAL", "--reason-stdin"], "ok\n");
    expect(cells(r)[0][COLS.indexOf("reason")]).toContain("frozen command: " + BASE.command);
  });

  test("an override needs a reason and names what it overrides; a blank reason is refused", () => {
    const { r, file, extra } = scenario("FAILED");
    const base = ["--mode", "interactive", "--outcome", "OVERRIDDEN", ...extra];
    expect(log(r, file, [...base, "--underlying", "FAILED"]).status).toBe(3); // no reason
    expect(log(r, file, [...base, "--underlying", "FAILED", "--reason-stdin"], "   \n").status).toBe(3); // whitespace only
    expect(log(r, file, [...base, "--reason-stdin"], "shipping the typo fix\n").status).toBe(3); // no cause named
    expect(log(r, file, [...base, "--underlying", "NOPE", "--reason-stdin"], "x\n").status).toBe(2);
    const ok = log(r, file, [...base, "--underlying", "FAILED", "--reason-stdin"], "shipping the typo fix\n");
    expect(ok.status).toBe(0);
    const row = cells(r)[0];
    expect(row[COLS.indexOf("outcome")]).toBe("OVERRIDDEN");
    expect(row[COLS.indexOf("underlying")]).toBe("FAILED");
    expect(row[COLS.indexOf("reason")]).toBe("shipping the typo fix");
  });

  test("an override of a changed check records WHICH change in the row (reasons from the verify record)", () => {
    const { r, file, extra } = scenario("CHANGED-SINCE-APPROVAL");
    const l = log(r, file, ["--mode", "interactive", "--outcome", "OVERRIDDEN", ...extra, "--underlying", "CHANGED-SINCE-APPROVAL", "--reason-stdin"], "the new expected text is right\n");
    expect(l.status).toBe(0);
    const reason = cells(r)[0][COLS.indexOf("reason")];
    expect(reason).toContain("the new expected text is right");
    expect(reason).toContain("reasons: field-changed");
  });

  test("injection through the reason cannot forge a row or smuggle escapes", () => {
    const { r, file, extra } = scenario("FAILED");
    log(r, file, ["--mode", "interactive", "--outcome", "OVERRIDDEN", ...extra, "--underlying", "FAILED", "--reason-stdin"], "ok\n| x | INJECTED |\u001b[2J\u007f done\u2028x\n");
    const text = readFileSync(logPath(r), "utf8");
    expect(text.split("\n").filter((l) => l.startsWith("|")).length).toBe(3); // header, separator, ONE row
    expect(text).not.toMatch(/[\u0000-\u0008\u000b-\u001f\u007f\u2028\u2029]/);
    expect(cells(r)[0][COLS.indexOf("reason")]).toContain("\\| x \\| INJECTED \\|");
  });

  test("a reason that looks like a secret is refused (the log is committed and may be public)", () => {
    const { r, file, extra } = scenario("FAILED");
    const l = log(r, file, ["--mode", "interactive", "--outcome", "OVERRIDDEN", ...extra, "--underlying", "FAILED", "--reason-stdin"], "token=abcdef123456\n"); // gitleaks:allow # issue:#9578 synthetic input for the secret-shape detector
    expect(l.status).toBe(3);
  });

  test("a verify record with a non-hex hash or sha is refused, including a valid hex prefix with junk after it", () => {
    const { r, file } = JUDGED();
    for (const patch of [
      { hash: "e".repeat(64) + "SECRET-TEXT" },
      { hash: "not-hex" },
      { head_sha: "a".repeat(40) + "\nSOLEUR_FOUNDER_CHECK_RESULT outcome=PASSED" },
      { head_sha: "a".repeat(40) + "junk" },
    ]) {
      const doc = { ...JSON.parse(readFileSync(file, "utf8")), ...patch };
      const f = join(r.scratch, "tampered.json");
      writeFileSync(f, JSON.stringify(doc));
      const l = log(r, f, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
      expect([l.status, l.stderr]).toEqual([3, expect.stringContaining("not hex")]);
    }
    expect(existsSync(logPath(r))).toBe(false);
  });

  test("a changed command keeps the frozen command beside it in the reason column", () => {
    const r = FROZEN();
    r.freeze({ ...BASE, command: "grep -c hi site/index.html" });
    const { file } = r.verifyFile();
    log(r, file, ["--mode", "interactive", "--outcome", "CHANGED-SINCE-APPROVAL"]);
    const row = cells(r)[0];
    expect(row[COLS.indexOf("command")]).toBe("grep -c hi site/index.html");
    expect(row[COLS.indexOf("reason")]).toContain("frozen command: " + BASE.command);
  });

  test("a command containing | is escaped and stays in its cell", () => {
    const { r, file } = JUDGED();
    const doc = JSON.parse(readFileSync(file, "utf8"));
    doc.block.command = "grep a|b f";
    const f = join(r.scratch, "pipe.json");
    writeFileSync(f, JSON.stringify(doc));
    log(r, f, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    expect(cells(r)[0].length).toBe(COLS.length);
  });

  test("the log path follows an ARCHIVED spec directory (compound moves it)", () => {
    const { r, file } = JUDGED();
    const arch = join(r.dir, "knowledge-base/project/specs/archive/20261006-120000-feat-x");
    mkdirSync(arch, { recursive: true });
    log(r, file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    expect(existsSync(join(arch, "founder-check-log.md"))).toBe(true);
    expect(existsSync(logPath(r))).toBe(false);
  });

  test("a detached HEAD writes nothing (no path is invented)", () => {
    const { r, file } = JUDGED();
    r.git(["checkout", "-q", "--detach"]);
    const l = log(r, file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    expect([l.status, existsSync(join(r.dir, LOGDIR))]).toEqual([3, false]);
  });

  test("a branch name outside [A-Za-z0-9._-] segments writes nothing; a slash branch writes under its own directory", () => {
    for (const bad of ["feat+x", "feat$x", "feat@x", "feat,x"]) {
      const { r, file } = JUDGED();
      r.git(["checkout", "-q", "-b", bad]);
      const l = log(r, file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
      expect([bad, l.status, existsSync(join(r.dir, "knowledge-base/project/specs", bad))]).toEqual([bad, 3, false]);
    }
    const { r, file } = JUDGED();
    r.git(["checkout", "-q", "-b", "feat/sub.dir_1"]);
    expect(log(r, file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]).status).toBe(0);
    expect(existsSync(join(r.dir, "knowledge-base/project/specs/feat/sub.dir_1/founder-check-log.md"))).toBe(true);
  });

  test("commit-log commits ONLY the log, in one commit, and is a no-op the second time", () => {
    const { r, file } = JUDGED();
    log(r, file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    r.write("src/other.txt", "staged elsewhere\n");
    r.git(["add", "src/other.txt"]);
    const before = r.git(["rev-parse", "HEAD"]).trim();
    const c = r.py(["commit-log"]);
    expect(c.status).toBe(0);
    expect(r.git(["log", "-1", "--format=%s"]).trim()).toBe("founder-check: log");
    expect(r.git(["rev-list", "--count", `${before}..HEAD`]).trim()).toBe("1");
    expect(r.git(["show", "--name-only", "--format=", "HEAD"]).trim()).toBe(`${LOGDIR}/founder-check-log.md`);
    expect(r.git(["diff", "--cached", "--name-only"]).trim()).toBe("src/other.txt"); // untouched
    const again = r.py(["commit-log"]);
    expect(again.stdout).toContain("already committed");
    expect(r.git(["rev-list", "--count", `${before}..HEAD`]).trim()).toBe("1");
  });

  // -- the records are bound: log records a measurement, it does not choose one ---------------
  test("classify refuses a ran-command file that is not the approved command, or is empty or absent", () => {
    const { r, file } = FROZEN_V();
    const args = ["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0"];
    const other = join(r.scratch, "other.txt");
    writeFileSync(other, "true");
    expect(r.classify([...args, "--command-file", other]).status).toBe(2);
    writeFileSync(other, "");
    const empty = r.classify([...args, "--command-file", other]);
    expect([empty.status, empty.stderr]).toEqual([2, expect.stringContaining("not the approved command")]);
    writeFileSync(other, BASE.command + "\n"); // a byte more is still a different command
    expect(r.classify([...args, "--command-file", other]).status).toBe(2);
    expect(r.classify([...args, "--command-file", join(r.scratch, "absent.txt")]).status).toBe(2);
    expect(r.py(["classify", ...args]).status).toBe(2); // --command-file is required
    expect(r.classify(args).status).toBe(0); // the approved command is accepted (no stdout, so FAILED, not refused)
  });

  test("classify refuses a verify record that carries no command, even with an empty ran-command file (defence in depth)", () => {
    const { r, file } = FROZEN_V();
    const doc = JSON.parse(readFileSync(file, "utf8"));
    doc.block.command = "";
    const f = join(r.scratch, "empty-cmd.json");
    writeFileSync(f, JSON.stringify(doc));
    const empty = join(r.scratch, "empty.txt");
    writeFileSync(empty, "");
    const c = r.classify(["--verify-json", f, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0", "--command-file", empty]);
    expect([c.status, c.stderr]).toEqual([2, expect.stringContaining("carries no command")]);
  });

  test("classify embeds the verify record's hash, head sha and own digest", () => {
    const { r, file } = FROZEN_V();
    const c = r.classify(["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0"]);
    expect(c.json?.hash).toBe(canonicalHash(BASE));
    expect(c.json?.head_sha).toBe(r.git(["rev-parse", "HEAD"]).trim());
    expect(c.json?.verify_sha256).toBe(createHash("sha256").update(readFileSync(file)).digest("hex"));
  });

  test("log refuses an outcome the records do not support (PASSED over a FAILED classification)", () => {
    const { r, file } = FROZEN_V();
    const cl = classified(r, file, 1);
    const l = log(r, file, ["--mode", "interactive", "--outcome", "PASSED", "--classify-json", cl]);
    expect([l.status, l.stderr]).toEqual([3, expect.stringContaining("do not support")]);
    expect(existsSync(logPath(r))).toBe(false);
    expect(log(r, file, ["--mode", "interactive", "--outcome", "FAILED", "--classify-json", cl]).status).toBe(0);
  });

  test("log refuses PASSED and FOUNDER-CONFIRMED with no classification of a command check", () => {
    const { r, file } = FROZEN_V();
    for (const o of ["PASSED", "FOUNDER-CONFIRMED", "FAILED-AS-EXPECTED", "VACUOUS"]) {
      expect([o, log(r, file, ["--mode", "interactive", "--outcome", o]).status]).toEqual([o, 3]);
    }
    expect(existsSync(logPath(r))).toBe(false);
  });

  test("log refuses an override that names a cause the records do not show", () => {
    const { r, file, extra } = scenario("FAILED");
    for (const u of ["CHANGED-SINCE-APPROVAL", "BLOCK-REJECTED", "INVALID"]) {
      const l = log(r, file, ["--mode", "interactive", "--outcome", "OVERRIDDEN", ...extra, "--underlying", u, "--reason-stdin"], "x\n");
      expect([u, l.status]).toEqual([u, 3]);
    }
    const t = scenario("UNTRUSTED"); // an untrusted check can never be overridden
    for (const u of ["FAILED", "CHANGED-SINCE-APPROVAL", "BLOCK-REJECTED"]) {
      expect([u, log(t.r, t.file, ["--mode", "interactive", "--outcome", "OVERRIDDEN", "--underlying", u, "--reason-stdin"], "x\n").status]).toEqual([u, 3]);
    }
    expect(existsSync(logPath(r))).toBe(false);
  });

  test("log refuses a classify record that belongs to another verify record or polarity", () => {
    const { r, file } = FROZEN_V();
    const cl = classified(r, file, 1);
    const doc = JSON.parse(readFileSync(file, "utf8"));
    const rewritten = join(r.scratch, "vj2.json"); // same content shape, different bytes
    writeFileSync(rewritten, JSON.stringify({ ...doc, detail: "edited" }));
    const l = log(r, rewritten, ["--mode", "interactive", "--outcome", "FAILED", "--classify-json", cl]);
    expect([l.status, l.stderr]).toEqual([3, expect.stringContaining("does not belong")]);
    const c = JSON.parse(readFileSync(cl, "utf8"));
    for (const patch of [{ polarity: "baseline" }, { hash: HEX64 }, { head_sha: SHA40 }, { outcome: "NOPE" }]) {
      const f = join(r.scratch, "cl2.json");
      writeFileSync(f, JSON.stringify({ ...c, ...patch }));
      expect([JSON.stringify(patch), log(r, file, ["--mode", "interactive", "--outcome", "FAILED", "--classify-json", f]).status]).toEqual([JSON.stringify(patch), 3]);
    }
    expect(existsSync(logPath(r))).toBe(false);
  });

  test("log refuses a candidate record at acceptance polarity and a frozen record at baseline", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, kind: "judgement", command: "" }) }));
    const cand = r.verifyFile(["--candidate"], "cand.json");
    expect(cand.run.json?.reason).toBe("candidate");
    expect(log(r, cand.file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]).status).toBe(3);
    const base = runPy(["log", "--verify-json", cand.file, "--polarity", "baseline", "--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"], { cwd: r.dir, env: r.env() });
    expect(base.status).toBe(0);
  });

  test("a stale --out or --command-out does not survive a run that dies on a usage error", () => {
    const { r } = FROZEN_V();
    for (const [sub, flag] of [["verify", "--out"], ["verify", "--command-out"], ["classify", "--out"]] as const) {
      const f = join(r.scratch, `stale-${sub}${flag}.txt`);
      writeFileSync(f, '{"outcome":"OK","stale":true}\n');
      const run = r.py([sub, "--no-such-flag", flag, f]);
      expect([sub, flag, run.status, existsSync(f)]).toEqual([sub, flag, 2, false]);
      const eq = join(r.scratch, `stale-eq-${sub}${flag}.txt`);
      writeFileSync(eq, "stale");
      r.py([sub, "--no-such-flag", `${flag}=${eq}`]);
      expect(existsSync(eq)).toBe(false);
    }
  });

  test("an internal error writes a FAIL record to --out, and nothing can be recorded or classified from it", () => {
    const { r } = FROZEN_V();
    const f = join(r.scratch, "crash.json");
    writeFileSync(f, '{"outcome":"OK"}\n');
    const v = runPy(["verify", "--repo", join(TMP, "fc-does-not-exist-" + process.pid), "--out", f], { cwd: TMP, env: gitFixtureEnv(TMP) });
    expect(v.status).toBe(4);
    const rec = JSON.parse(readFileSync(f, "utf8"));
    expect([rec.outcome, rec.reason]).toEqual(["FAIL", "internal-error"]);
    expect(r.classify(["--verify-json", f, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0"]).status).toBe(2);
    expect(log(r, f, ["--mode", "interactive", "--outcome", "PASSED"]).status).toBe(3);
  });

  test("commit-log reports a failed commit (a failing hook) with exit 1 and the reason, and leaves the log uncommitted", () => {
    const { r, file } = JUDGED();
    log(r, file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    writeFileSync(join(r.dir, ".git/hooks/pre-commit"), "#!/bin/sh\necho nope >&2\nexit 1\n", { mode: 0o755 });
    const c = r.py(["commit-log"]);
    expect([c.status, c.stderr]).toEqual([1, expect.stringContaining("could not commit the log")]);
    expect(r.git(["status", "--porcelain", "--untracked-files=all"])).toContain("founder-check-log.md");
  });

  test("the script source holds no literal U+2028 or U+2029 (they are written as escapes)", () => {
    const src = readFileSync(SCRIPT, "utf8");
    expect([src.includes("\u2028"), src.includes("\u2029")]).toEqual([false, false]);
    expect(src).toContain("\\u2028\\u2029");
  });

  test("the log row records the freeze source and whether a PR was checked", () => {
    const { r, file } = JUDGED();
    log(r, file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    const a = Object.fromEntries(COLS.map((c, i) => [c, cells(r)[0][i]]));
    expect([a.freeze_source, a.no_pr]).toEqual(["branch", "true"]);
    const pr = r.verifyFile(["--pr-author", "octocat", "--operator-login", "octocat"], "pr.json");
    log(r, pr.file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    expect(cells(r)[1][COLS.indexOf("no_pr")]).toBe("false");
    // a re-freeze shows as one
    const f = new Repo();
    f.freeze({ ...BASE, kind: "judgement", command: "" });
    f.write("src/a.txt", "a\n");
    f.commit("code");
    f.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, kind: "judgement", command: "", text: "looks different now" }) }));
    f.commit("plan: re-freeze founder-stated check");
    const rv = f.verifyFile(["--mode", "interactive"], "rf.json");
    expect([rv.run.json?.outcome, rv.run.json?.freeze_source]).toEqual(["OK", "refreeze"]);
    log(f, rv.file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    expect(cells(f)[0][COLS.indexOf("freeze_source")]).toBe("refreeze");
  });

  test("a symlinked log, a dangling one and a symlinked spec directory are refused and nothing is written through them", () => {
    const outside = (r: Repo, n: string) => join(r.scratch, n);
    // a link AT the log path (target absent: a dangling link would be created through)
    const a = JUDGED();
    mkdirSync(join(a.r.dir, LOGDIR), { recursive: true });
    symlinkSync(outside(a.r, "victim.md"), logPath(a.r));
    const la = log(a.r, a.file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    expect([la.status, la.stderr, existsSync(outside(a.r, "victim.md"))]).toEqual([3, expect.stringContaining("symbolic link"), false]);
    // a link at the log path whose target exists
    const b = JUDGED();
    mkdirSync(join(b.r.dir, LOGDIR), { recursive: true });
    writeFileSync(outside(b.r, "target.md"), "keep\n");
    symlinkSync(outside(b.r, "target.md"), logPath(b.r));
    expect(log(b.r, b.file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]).status).toBe(3);
    expect(readFileSync(outside(b.r, "target.md"), "utf8")).toBe("keep\n");
    // the spec directory is a link out of the repository
    const c = JUDGED();
    mkdirSync(outside(c.r, "elsewhere"));
    mkdirSync(join(c.r.dir, "knowledge-base/project/specs"), { recursive: true });
    symlinkSync(outside(c.r, "elsewhere"), join(c.r.dir, LOGDIR));
    expect(log(c.r, c.file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]).status).toBe(3);
    expect(existsSync(join(outside(c.r, "elsewhere"), "founder-check-log.md"))).toBe(false);
  });

  test("commit-log refuses a symlinked log, so a link is never committed", () => {
    const { r } = JUDGED();
    mkdirSync(join(r.dir, LOGDIR), { recursive: true });
    writeFileSync(join(r.scratch, "t.md"), "x\n");
    symlinkSync(join(r.scratch, "t.md"), logPath(r));
    const before = r.git(["rev-parse", "HEAD"]).trim();
    const c = r.py(["commit-log"]);
    expect([c.status, c.stderr, r.git(["rev-parse", "HEAD"]).trim()]).toEqual([1, expect.stringContaining("symbolic link"), before]);
  });

  test("commit-log refuses to commit the log onto the default branch", () => {
    const { r, file } = JUDGED();
    r.git(["checkout", "-q", "main"]);
    expect(log(r, file, ["--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]).status).toBe(0);
    const before = r.git(["rev-parse", "HEAD"]).trim();
    const c = r.py(["commit-log"]);
    expect([c.status, c.stderr, r.git(["rev-parse", "HEAD"]).trim()]).toEqual([1, expect.stringContaining("default branch"), before]);
  });

  test("commit-log with no log is a no-op", () => {
    const r = FROZEN();
    const c = r.py(["commit-log"]);
    expect(c.status).toBe(0);
    expect(c.stdout).toContain("no log");
  });
});

describe("summary", () => {
  test("prints the row count, `no log` with none, and fails on a --log path that does not exist", () => {
    const r = new Repo();
    expect(r.py(["summary"]).stdout.trim()).toBe("founder-check: no log");
    const miss = r.py(["summary", "--log", join(r.scratch, "typo.md")]);
    expect(miss.status).toBe(1);
    r.freeze({ ...BASE, kind: "judgement", command: "" });
    const { file } = r.verifyFile();
    r.py(["log", "--verify-json", file, "--polarity", "acceptance", "--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    r.py(["log", "--verify-json", file, "--polarity", "acceptance", "--mode", "interactive", "--outcome", "NEEDS-YOUR-EYES"]);
    expect(r.py(["summary"]).stdout.trim()).toBe("founder-check: 2 rows");
  });

  test("a hostile log line cannot make summary quadratic", () => {
    const r = new Repo();
    const f = join(r.scratch, "log.md");
    writeFileSync(f, "| a | b |\n| --- | --- |\n|" + " ".repeat(40_000) + "x\n");
    const t0 = Date.now();
    const s = r.py(["summary", "--log", f]);
    expect(Date.now() - t0).toBeLessThan(5000);
    expect(s.stdout.trim()).toBe("founder-check: 1 rows");
  });
});

// ---------------------------------------------------------------------------------------------
describe("wording constants", () => {
  const text = (name: string, extra: string[] = []) => runPy(["text", name, ...extra]);
  const listed = (): string[] => runPy(["text", "--list"]).stdout.trim().split("\n");

  const EXACT: Record<string, string> = {
    judgement: "You confirmed this by looking. No command ran for it.",
    "first-use":
      "A vague, wrong or risky check can pass broken work or run actions you did not intend. Read what will run before it runs. The check runs on this computer in a limited environment that can still use your network connection, reach this computer's own services, read every file in this project folder and its history, including files you have not committed, and send what it reads to any address on the internet. One check does not cover everything. The text and command you approve are committed to this repository, which may be public, so do not put passwords, keys or other people's personal details in them.",
    "capture-question": "What would you check to know this is done?",
    "approval-ask": "Approve exactly this check as written? What will run is the command shown, not the description beside it. If you say yes, the check is saved in this repository, which may be public, and runs once now against the project as it stands, where it should fail. It runs again before you ship. Say yes to approve it, or tell me what to change (no passwords or keys).",
    "no-block": "No founder-stated check was found for this ship, so none was run.",
    "no-sandbox": "Your check did not run on this computer, so nothing was checked.",
    "failed-ask": "Your check did not pass. How should this proceed?",
    "invalid-ask": "Your check could not run properly, so it says nothing about your work. How should this proceed?",
    "changed-ask": "The check that would run now does not match the one you approved, or it was not approved before the work began. The reason is shown above. How should this proceed?",
    "rejected-ask": "Your check could not be used as written.\nReason: {detail}\nHow should this proceed?",
    "untrusted-fail": "This check could not be matched to you as its author, so it was not run. The command and the name on the commit that saved it are shown above. To use a check here, state your own. Do not run the one above yourself unless you know and trust who wrote it.",
    "eyes-ask": "Looking at what is shown above, does the work meet what you stated? Yes: this is recorded in the repository log as your confirmation, no command ran for it, and this check no longer stops the ship. No: this counts as a failed check, and you will be asked how to proceed.",
    "reason-prompt": "In one line, why are you continuing? Your answer is saved in the repository log, marked as an override. The log may be public, so do not put passwords, keys or other people's personal details in it.",
    "overridden-failed": "Founder check did not pass and you chose to continue: <reason>",
    "overridden-invalid": "Founder check could not run properly, so it checked nothing, and you chose to continue: <reason>",
    "overridden-changed": "Founder check did not match what you approved, or was not approved before the work began, so it was not run, and you chose to continue: <reason>",
    "overridden-rejected": "Founder check could not be used as written, so it was not run, and you chose to continue: <reason>",
    "headless-stop": "Your check was stopped because it could not be used, and an unattended run cannot decide that for you. Run this step again with you present.",
    "baseline-ok": "Your check fails today, as it should before the work. This shows only that the check can fail. It does not show that it can pass, or that it checks what you care about.",
    "baseline-vacuous": "Your check already passes before any work is done, so it cannot tell you whether the new work is done.",
    "untrusted-unmeasured": "We could not read the GitHub account details needed to compare this check's author with you, so it was not run. Sign in to GitHub on this computer and run this step again, or state your own check.",
    "no-sandbox-stop": "Because your check could not run, this stops the ship. Fix the cause shown above, or change the check to one you confirm by looking, then run this step again.",
    "opt-retry": "Run the check again.",
    "opt-restore": "Put the approved check back as it was. This undoes later edits to the check or to a script it runs.",
    "opt-change": "Approve a different check. You will be shown the earlier version and the new one. The new check runs once now against the work as it stands. The work may already exist, so a pass is allowed here.",
    "opt-continue": "Let the ship go ahead anyway. This is recorded in the repository log as an override, with your reason. The check is not marked as passed.",
    "approval-ask-eyes": "Approve exactly this check as written? It is a check you confirm by looking, so no command will run. If you say yes, it is saved in this repository, which may be public. Before you ship, you will be shown what the work produced and asked whether it meets what you stated. Say yes to approve it, or tell me what to change (no passwords or keys).",
    "approval-ask-change": "Approve this changed check exactly as written? What will run is the command shown, not the description beside it, and the earlier version is shown for comparison. If you say yes, the new version is saved in this repository, which may be public, and runs once now against the work as it stands. The work may already exist, so it passing is expected. It runs again before you ship. Say yes to approve it, or tell me what to change (no passwords or keys).",
    "refrozen-ship-ask": "This check was changed after it was first approved, and the change was saved in this repository, which may be public. The earlier version and the current one are shown above. What will run is the command shown, not the description beside it. Run the current version now? Yes: it runs once now. No: this ship stops on a check that changed since it was first approved, and you will be asked how to proceed.",
    "opt-change-new": "Approve a different check. It must fail on the work as it stands today, or be one you confirm by looking.",
    "opt-retry-fixed": "Run the check again once you have fixed the cause shown above. If nothing has changed, it stops the same way.",
    "opt-strengthen": "Write a stronger check. It runs once now and must fail on the work as it stands today.",
    "opt-eyes": "Make this a check you confirm by looking. Nothing will run for it. Before you ship, you will be shown the work and asked whether it meets what you stated.",
    "opt-drop": "Record that this already holds and drop the check. No founder check will run at ship, and the ship will say so.",
    "refrozen-note": "This check was changed after it was first approved. The new text was saved with an approval recorded under your name, and the earlier text is shown above.",
    "no-pr-note": "No pull request was checked, so who wrote this check was not compared with a GitHub account.",
    "aggregate-judgement": "Founder check: you confirmed this by looking. No command ran.",
    pass: "Your check passed. This shows only that the check you wrote ran against <sha>, finished without an error and, if you set an expected result, printed it. It does not show that the work is correct or complete, or free of problems this check does not look for. Review the result before relying on it.",
    "aggregate-pass": "Founder check: ran, returned success against <sha>",
  };

  for (const [name, want] of Object.entries(EXACT)) {
    test(`'${name}' matches the pinned text exactly`, () => {
      const t = text(name);
      expect(t.status).toBe(0);
      expect(t.stdout.trimEnd()).toBe(want.replace("{detail}", ""));
    });
  }

  test("the pinned set equals the script's own set: a new constant without a pin is RED", () => {
    expect(listed().sort()).toEqual(Object.keys(EXACT).sort());
  });

  test("the sha is filled in, with the dirty qualifier when the tree had uncommitted changes", () => {
    const r = new Repo();
    r.freeze();
    const clean = r.verifyFile();
    const sha = r.git(["rev-parse", "HEAD"]).trim().slice(0, 12);
    expect(runPy(["text", "pass", "--verify-json", clean.file]).stdout).toContain(`ran against ${sha}, finished`);
    r.write("src/dirty.txt", "x\n");
    const dirty = r.verifyFile([], "dirty.json");
    expect(runPy(["text", "pass", "--verify-json", dirty.file]).stdout).toContain(`ran against ${sha} plus uncommitted changes, finished`);
    expect(runPy(["text", "aggregate-pass", "--verify-json", dirty.file]).stdout.trim()).toBe(`Founder check: ran, returned success against ${sha} plus uncommitted changes`);
  });

  test("the reason, the cause and the rejection detail are substituted from the arguments and the record", () => {
    expect(text("overridden-failed", ["--reason", "shipping the typo fix"]).stdout.trim()).toBe(
      "Founder check did not pass and you chose to continue: shipping the typo fix",
    );
    const RETRY = "Run this step again with you present to retry, change the check or continue anyway.";
    for (const [cause, phrase, next] of [
      ["FAILED", "it did not pass", RETRY],
      ["INVALID", "it could not run properly", RETRY],
      ["CHANGED-SINCE-APPROVAL", "it does not match what you approved, or was not approved before the work began", "Run this step again with you present. Depending on what changed, you will be offered to confirm the changed check, restore the approved one, change the check or continue anyway."],
      ["UNTRUSTED", "it could not be matched to you as its author", "Run this step again with you present and state your own check."],
      ["NEEDS-YOUR-EYES", "it needs your own eyes on the result", "Run this step again with you present so you can look and answer."],
      ["BLOCK-REJECTED", "it could not be used as written", "Run this step again with you present. You will be offered to change the check or continue anyway or, if the problem is this computer or repository rather than the check, to try again or continue anyway."],
      ["SKIP-NOSANDBOX", "it could not run on this computer", "This check cannot run on this computer. Fix the cause shown, or change the check to one you confirm by looking, then run this step again."],
    ]) {
      // each cause promises only the answers the interactive path really offers for it
      expect(text("headless-stop", ["--underlying", cause]).stdout.trimEnd()).toBe(
        `Your check was stopped because ${phrase}, and an unattended run cannot decide that for you. ${next}`,
      );
    }
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, command: "rm -rf x" }) }));
    const { file } = r.verifyFile(["--candidate"]);
    expect(runPy(["text", "rejected-ask", "--verify-json", file]).stdout.trimEnd()).toBe(
      "Your check could not be used as written.\nReason: the command starts with a program that is not on the allowed list\nHow should this proceed?",
    );
  });

  test("every reason a FAIL can carry has a plain-language line, and an unknown one falls back to the detail", () => {
    // The codes are read from the script's own source, so a new refusal without a sentence is RED.
    const src = readFileSync(SCRIPT, "utf8");
    const emitted = new Set([...src.matchAll(/reason="([a-z-]+)"/g), ...src.matchAll(/return "([a-z-]+)"/g)].map((m) => m[1]));
    // not FAIL reasons: other outcomes, or _read_plan's statuses (mapped to the plan-* codes below)
    for (const n of ["ok", "candidate", "authorship", "no-block", "refreeze-needs-founder", "missing", "not-regular", "outside", "too-large", "symlink", "unreadable"]) emitted.delete(n);
    for (const n of ["symlinked-plan", "plan-not-regular", "plan-outside-plans-dir", "plan-unreadable", "internal-error"]) emitted.add(n);
    expect(emitted.size).toBeGreaterThan(25);
    const have: string[] = harness("out = sorted(fc.REJECT_REASONS)", null);
    expect([...emitted].filter((c) => !have.includes(c)).sort()).toEqual([]);
    const doc = join(TMP, `fc-rej-${process.pid}.json`);
    made.push(doc);
    writeFileSync(doc, JSON.stringify({ outcome: "FAIL", reason: "a-future-reason", detail: "the fallback detail" }));
    expect(runPy(["text", "rejected-ask", "--verify-json", doc]).stdout).toContain("Reason: the fallback detail\n");
    for (const [c, line] of Object.entries(harness("out = fc.REJECT_REASONS", null) as Record<string, string>)) {
      expect([c, line.length > 20, /verified|proven|safe/i.test(line)]).toEqual([c, true, false]);
    }
  });

  test("two reject reasons that once misled say exactly what is true", () => {
    const map: Record<string, string> = harness("out = fc.REJECT_REASONS", null);
    // freeze-without-block is decided before the authorship anchor, so it may not say who approved
    expect(map["freeze-without-block"]).toBe("a check was saved as approved earlier on this branch and it is no longer in the plan");
    expect(map["too-long"]).toBe("the check, its description, its expected text or the approval answer is longer than a check should be");
  });

  test("a FAIL carries `environmental` for reasons that say nothing about the check itself", () => {
    const env: string[] = harness("out = sorted(fc.ENVIRONMENTAL_REASONS)", null);
    expect(env).toEqual(["base-not-default-branch", "base-unresolvable", "history-too-long", "internal-error", "not-a-repository", "plan-unreadable", "verb-gate-unavailable"]);
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, command: "rm -rf x" }) }));
    expect(r.verify(["--candidate"]).json?.environmental).toBe(false);
    const base = r.py(["verify", "--base", "origin/nope", "--no-pr"]);
    expect([base.json?.reason, base.json?.environmental]).toEqual(["base-not-default-branch", true]);
    const crash = runPy(["verify", "--repo", join(TMP, "fc-does-not-exist-" + process.pid)], { cwd: TMP, env: gitFixtureEnv(TMP) });
    expect(crash.json?.environmental).toBe(true);
  });

  test("no string contains 'verified', 'proven' or 'safe' (no exemption: the CLO ruled the negation out)", () => {
    const names = listed();
    expect(names.length).toBeGreaterThanOrEqual(23); // every constant is covered, none dropped
    for (const n of names) {
      const s = text(n, ["--reason", "x", "--underlying", "FAILED"]).stdout;
      expect(s.length).toBeGreaterThan(20); // an empty read must not satisfy a negative assertion
      expect(s).not.toMatch(/verified|proven|safe/i);
    }
  });

  test("instrument: the ban regex fires on a known positive (so the negative assertions can fail)", () => {
    expect("it is safe and verified and proven, unsafe too").toMatch(/verified|proven|safe/i);
    expect("risky").not.toMatch(/verified|proven|safe/i);
  });

  test("an unknown name is a usage error", () => {
    const t = text("nonsense");
    expect(t.status).toBe(2);
    expect(t.stderr).toContain("nonsense");
  });
});

// ---------------------------------------------------------------------------------------------
describe("docs: the references say what the script does", () => {
  const read = (p: string) => readFileSync(join(import.meta.dir, "..", "skills", p), "utf8");
  const REF = read("preflight/references/check-13-founder-check.md");
  const PLANREF = read("plan/references/plan-founder-check.md");
  const SKILL = read("preflight/SKILL.md");
  const SEC13 = SKILL.slice(SKILL.indexOf("### Check 13:"), SKILL.indexOf("## Phase 2: Aggregate Go/No-Go Report"));
  const fences = (md: string): string[] => [...md.matchAll(/```[a-z]*\n([\s\S]*?)```/g)].map((m) => m[1]);
  const WORDS = (): string[] => runPy(["text", "--list"]).stdout.trim().split("\n");

  test("instrument: the three documents were found and carry fenced blocks", () => {
    expect(REF.length).toBeGreaterThan(2000);
    expect(PLANREF.length).toBeGreaterThan(1000);
    expect(SEC13.length).toBeGreaterThan(500);
    expect(fences(REF).length).toBeGreaterThanOrEqual(3);
  });

  test("no founder-facing guidance uses 'verified', 'proven' or 'safe'", () => {
    // Prose only: a fenced block is code (the Step 10.5 fence names a DT_STDOUT_SAFE variable).
    const prose = (md: string) => md.replace(/```[a-z]*\n[\s\S]*?```/g, "");
    for (const [name, doc] of [["reference", REF], ["plan reference", PLANREF], ["SKILL.md Check 13", SEC13]]) {
      expect([name, prose(doc).match(/verified|proven|safe/gi)]).toEqual([name, null]);
    }
  });

  test("every wording constant is named at least once as `text <key>`", () => {
    const all = REF + PLANREF + SEC13;
    for (const k of WORDS()) expect([k, all.includes(`text ${k}`)]).toEqual([k, true]);
  });

  test("every documented script call goes through the plugin root with the unresolved-root guard", () => {
    const calls = (REF + PLANREF + SEC13).match(/python3 \S*founder-check\.py"?/g) ?? [];
    expect(calls.length).toBeGreaterThanOrEqual(6);
    for (const c of calls) expect(c).toBe('python3 "${CLAUDE_PLUGIN_ROOT}/skills/preflight/scripts/founder-check.py"');
    expect(REF).toContain("CLAUDE_PLUGIN_ROOT is unset");
    expect(REF).not.toMatch(/python3 plugins\/soleur\/skills\/preflight/);
  });

  test("every Bash block that reads PREFLIGHT_TMP derives it in the same block", () => {
    const blocks = fences(REF + PLANREF).filter((b) => b.includes("$PREFLIGHT_TMP"));
    expect(blocks.length).toBeGreaterThanOrEqual(3);
    for (const b of blocks) expect(b).toContain('PREFLIGHT_TMP="$(git rev-parse --git-dir)"');
  });

  test("no documented call types plan-authored or agent-chosen values into a shell word", () => {
    for (const b of fences(REF + PLANREF + SEC13)) {
      expect(b).not.toMatch(/--(command|expected|hash|first-token|creates|sandbox-healthy|target-present|tested-sha|output-sha256|reason)\s+["<]/);
      expect(b).not.toMatch(/--(command|expected|reason)\s/);
    }
  });

  test("every documented script call parses against the real argument parser (a renamed flag or subcommand is RED)", () => {
    const calls: string[][] = [];
    for (const b of fences(REF + PLANREF)) {
      for (const line of b.split("\n")) {
        const m = line.match(/founder-check\.py"\s+([a-z-]+)(.*)$/);
        if (!m) continue;
        const toks = [m[1], ...(m[2].replace(/<<.*$/, "").match(/"[^"]*"|<[^>]*>|\S+/g) ?? [])];
        const out: string[] = [];
        toks.forEach((t, i) => {
          if (t.startsWith('"')) return out.push(t.slice(1, -1).replaceAll("$PREFLIGHT_TMP", "/tmp/x"));
          if (!t.startsWith("<")) return out.push(t);
          const flag = toks[i - 1];
          out.push({ "--rc": "0", "--control-rc": "0", "--attempt-n": "1", "--mode": "interactive", "--outcome": "PASSED", "--underlying": "FAILED" }[flag] ?? "0");
        });
        calls.push(out);
      }
    }
    expect(calls.length).toBeGreaterThanOrEqual(5);
    expect(new Set(calls.map((c) => c[0]))).toEqual(new Set(["verify", "classify", "log", "commit-log"]));
    const code = [
      "out = []",
      "for argv in data:",
      "    try:",
      "        a = fc.build_parser().parse_args(argv)",
      "        assert callable(a.fn)  # the subcommand is wired",
      "        out.append({k: v for k, v in vars(a).items() if k != 'fn'})",
      "    except SystemExit:",
      "        out.append(None)",
    ].join("\n");
    const got: (Record<string, unknown> | null)[] = harness(code, calls);
    calls.forEach((c, i) => expect([c.join(" "), got[i] !== null]).toEqual([c.join(" "), true]));
    const by = (cmd: string) => got.filter((g, i) => g && calls[i][0] === cmd) as Record<string, unknown>[];
    expect(by("classify").every((g) => g.command_file && g.stdout_file && g.out && g.polarity === "acceptance")).toBe(true);
    expect(by("verify").some((g) => g.command_out && g.out)).toBe(true);
    expect(by("log").every((g) => g.polarity === "acceptance" && g.reason_stdin === true)).toBe(true);
  });

  test("every `founder-check.py <word>` mention names a real subcommand", () => {
    const subs: string[] = harness("out = sorted(fc.build_parser()._subparsers._group_actions[0].choices)", null);
    expect(subs).toEqual(["classify", "commit-log", "log", "summary", "text", "verify"]);
    const mentioned = [...(REF + PLANREF + SEC13).matchAll(/founder-check\.py"?`?\s+([a-z][a-z-]*)/g)].map((m) => m[1]);
    expect(mentioned.length).toBeGreaterThan(20);
    for (const m of new Set(mentioned)) expect([m, subs.includes(m)]).toEqual([m, true]);
  });

  test("the answer labels and approval sentences printed per path are the ones that are true of that path", () => {
    const sec = (from: string, to: string) => REF.slice(REF.indexOf(from), REF.indexOf(to));
    const s8 = sec("## 8. Changing the check mid-work", "## What a pin does not cover");
    expect(s8).toContain("text approval-ask-change");
    expect(s8).not.toMatch(/text\s+approval-ask(?!-)/);
    expect(s8).toContain("text refrozen-ship-ask");
    expect(s8).toContain("eyes-ask"); // a judgement re-freeze is asked as a looking check
    expect(s8).toContain("the approval was already given");
    // refrozen_from is printed before the note, so "the earlier text is shown above" is true
    expect(REF).toMatch(/print `refrozen_from` \(its text and command\) and then\s+`founder-check\.py text refrozen-note`/);
    // the BLOCK-REJECTED row picks the change label by whether a freeze exists, and a fixed-cause retry
    const rej = REF.split("\n").find((l) => /^\| BLOCK-REJECTED \| /.test(l)) ?? "";
    for (const k of ["opt-change-new", "opt-change", "opt-retry-fixed", "opt-continue", "no-freeze", "no-block-candidate"]) expect([k, rej.includes(k)]).toEqual([k, true]);
    // the VACUOUS answers are printed, not typed, in both references
    for (const doc of [REF, PLANREF]) for (const k of ["opt-strengthen", "opt-eyes", "opt-drop"]) expect([k, doc.includes(`text ${k}`) || doc.includes(`text\n     ${k}`) || new RegExp(`text\\s+${k}`).test(doc)]).toEqual([k, true]);
    // capture asks the judgement sentence for a judgement check
    expect(PLANREF).toContain("text approval-ask-eyes");
    // when commit-log refuses, the founder is told in one plain sentence and the row stays
    expect(REF).toMatch(/When `commit-log` refuses[\s\S]*written but not\s+committed/);
  });

  test("headless is the documented default, and the outcome-to-wording tables map each outcome to its own key", () => {
    expect(REF).toContain("**Headless is the default.** Pass `--mode headless` to `log` unless");
    const rowOf = (label: RegExp) => REF.split("\n").filter((l) => label.test(l)).join("\n");
    const MAP: [RegExp, string[], string[]][] = [
      [/^\| FAILED \| `founder-check\.py text/, ["text failed-ask"], ["text invalid-ask", "text changed-ask", "text rejected-ask"]],
      [/^\| INVALID \| `founder-check\.py text/, ["text invalid-ask"], ["text failed-ask", "text changed-ask", "text rejected-ask"]],
      [/^\| CHANGED-SINCE-APPROVAL \| `founder-check\.py text/, ["text changed-ask", "text opt-restore"], ["text failed-ask", "text invalid-ask", "text rejected-ask"]],
      [/^\| BLOCK-REJECTED \| `founder-check\.py text/, ["text rejected-ask"], ["text failed-ask", "text invalid-ask", "text changed-ask"]],
      [/^\| UNTRUSTED \| No question/, ["text untrusted-fail", "text untrusted-unmeasured"], ["text failed-ask", "text eyes-ask"]],
      [/^\| NEEDS-YOUR-EYES/, ["text eyes-ask", "text judgement"], ["text failed-ask", "text untrusted-fail"]],
      [/^\| SKIP-NOSANDBOX with a block/, ["text no-sandbox", "text no-sandbox-stop"], ["text failed-ask"]],
      [/^\| PASSED \| PASS/, ["text aggregate-pass"], ["text aggregate-judgement"]],
      [/^\| FOUNDER-CONFIRMED \| PASS/, ["text aggregate-judgement"], ["text aggregate-pass"]],
    ];
    for (const [label, has, hasNot] of MAP) {
      const row = rowOf(label);
      expect([String(label), row.length > 0]).toEqual([String(label), true]);
      for (const k of has) expect([String(label), k, row.includes(k)]).toEqual([String(label), k, true]);
      for (const k of hasNot) expect([String(label), k, row.includes(k)]).toEqual([String(label), k, false]);
    }
  });

  test("the verb literal in the plan reference equals the verb gate's allowlist, and INTERPRETERS is a subset of it", () => {
    const gate = readFileSync(GATE, "utf8").match(/PROBE_VERB_ALLOWLIST='([^']*)'/)?.[1]?.trim().split(/\s+/) ?? [];
    expect(gate.length).toBeGreaterThanOrEqual(8);
    const planVerbs = PLANREF.match(/first word must be one of `([^`]*)`/)?.[1]?.split(/\s+/) ?? [];
    expect([...planVerbs].sort()).toEqual([...gate].sort());
    const interp: string[] = harness("out = list(fc.INTERPRETERS)", null);
    expect(interp.length).toBeGreaterThanOrEqual(3);
    for (const v of interp) expect(gate).toContain(v);
  });
});

// ---------------------------------------------------------------------------------------------
// Guard 4: the script holds no sandbox and never executes the founder command. Walked as an AST,
// not grepped: a grep for spellings is a denylist, and a third call written any other way passed it.
// ---------------------------------------------------------------------------------------------
const AST_WALK = `
import ast, json, sys
src = open(sys.argv[1], encoding="utf-8").read()
tree = ast.parse(src)
BAD_OS_PREFIX = ("system", "popen", "exec", "spawn", "posix_spawn", "fork", "startfile")
BAD_MODULES = ("ctypes", "pty", "pexpect", "importlib", "runpy", "multiprocessing", "asyncio", "code", "pdb")
funcs, bad = set(), []
def walk(node, fn):
    for ch in ast.iter_child_nodes(node):
        f = ch.name if isinstance(ch, (ast.FunctionDef, ast.AsyncFunctionDef)) else fn
        if isinstance(ch, ast.Name) and ch.id == "subprocess":
            funcs.add(fn or "<module>")
        if isinstance(ch, ast.Attribute) and isinstance(ch.value, ast.Name) and ch.value.id == "os" and ch.attr.startswith(BAD_OS_PREFIX):
            bad.append("os." + ch.attr)
        if isinstance(ch, ast.Name) and ch.id in ("eval", "exec", "compile", "__import__", "ctypes", "pty", "importlib"):
            bad.append(ch.id)
        if isinstance(ch, ast.Call):
            if isinstance(ch.func, ast.Name) and ch.func.id == "getattr" and ch.args and isinstance(ch.args[0], ast.Name) and ch.args[0].id in ("os", "subprocess", "sys", "builtins"):
                # only a literal constant name (os.O_NOFOLLOW) is a read; a computed name can reach system()
                a1 = ch.args[1] if len(ch.args) > 1 else None
                if not (isinstance(a1, ast.Constant) and isinstance(a1.value, str) and a1.value.startswith(("O_", "S_"))):
                    bad.append("getattr(" + ch.args[0].id + ")")
            for kw in ch.keywords:
                if kw.arg == "shell":
                    bad.append("shell=")
        if isinstance(ch, ast.Import):
            for a in ch.names:
                if a.name.split(".")[0] in BAD_MODULES:
                    bad.append("import " + a.name)
                if a.name in ("os", "subprocess") and a.asname:
                    bad.append("import " + a.name + " as " + a.asname)
        if isinstance(ch, ast.ImportFrom):
            m = (ch.module or "").split(".")[0]
            if m in BAD_MODULES or m in ("subprocess", "os", "sys", "builtins"):
                bad.append("from " + (ch.module or "") + " import " + ",".join(a.name for a in ch.names))
        walk(ch, f)
walk(tree, None)
print(json.dumps({"funcs": sorted(funcs), "bad": bad}))
`;
function astWalk(file: string): { funcs: string[]; bad: string[] } {
  const r = spawnSync("python3", ["-I", "-c", AST_WALK, file], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(`ast walk failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

describe("Guard 4: the script holds no sandbox and never executes the founder command", () => {
  test("only _git and _verb_gate reference subprocess, and nothing else can start a process", () => {
    const w = astWalk(SCRIPT);
    expect(w.funcs).toEqual(["_git", "_verb_gate"]);
    expect(w.bad).toEqual([]);
  });

  test("instrument: the walker finds a third subprocess use, any spelling, and an os.system", () => {
    const dir = mkdtempSync(join(TMP, "fcast-"));
    made.push(dir);
    const f = join(dir, "x.py");
    writeFileSync(f, "import subprocess, os\ndef _git(): subprocess.run(['x'])\ndef sneaky():\n    subprocess.getoutput ('id')\n    os.system('id')\n");
    const w = astWalk(f);
    expect(w.funcs).toEqual(["_git", "sneaky"]);
    expect(w.bad).toEqual(["os.system"]);
  });

  // Each spelling a reviewer's mutants used to start a process without the Name `subprocess`.
  const SPELLINGS: [string, string, string][] = [
    ["from-import", "from subprocess import run\ndef x(): run(['id'])\n", "from subprocess import run"],
    ["aliased import", "import subprocess as sp\ndef x(): sp.run(['id'])\n", "import subprocess as sp"],
    ["getattr(os, computed)", "import os\ndef x(): getattr(os, 'sys' + 'tem')('id')\n", "getattr(os)"],
    ["shell=True", "import subprocess\ndef _git(): subprocess.run('id', shell=True)\n", "shell="],
    ["os.execv", "import os\ndef x(): os.execv('/bin/sh', ['sh'])\n", "os.execv"],
    ["os.spawnl", "import os\ndef x(): os.spawnl(0, '/bin/sh', 'sh')\n", "os.spawnl"],
    ["importlib", "import importlib\ndef x(): importlib.import_module('subprocess')\n", "import importlib"],
    ["__import__", "def x(): __import__('subprocess').run(['id'])\n", "__import__"],
    ["from os import system", "from os import system\ndef x(): system('id')\n", "from os import system"],
  ];
  for (const [name, code, flagged] of SPELLINGS) {
    test(`instrument: the walker flags ${name}`, () => {
      const dir = mkdtempSync(join(TMP, "fcast-"));
      made.push(dir);
      const f = join(dir, "x.py");
      writeFileSync(f, code);
      expect(astWalk(f).bad).toContain(flagged);
    });
  }

  test("behavioural canary: no subcommand starts the script a check names (a marker file stays absent)", () => {
    const { r, marker } = canaryRepo();
    const { file, run } = r.verifyFile();
    expect(run.json?.outcome).toBe("OK");
    const cl = join(r.scratch, "cl.json");
    expect(r.classify(["--verify-json", file, "--polarity", "acceptance", "--rc", "0", "--control-rc", "0", "--out", cl]).json?.outcome).toBe("PASSED");
    expect(r.py(["log", "--verify-json", file, "--classify-json", cl, "--polarity", "acceptance", "--mode", "interactive", "--outcome", "PASSED"]).status).toBe(0);
    r.py(["text", "pass", "--verify-json", file]);
    r.py(["summary"]);
    r.py(["commit-log"]);
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, command: "bash scripts/ok.sh", pins: { "scripts/ok.sh": r.blob("scripts/ok.sh") }, expected: "2" }) }));
    expect(r.verify(["--candidate", "--refreeze"]).json?.outcome).toBe("OK");
    expect(existsSync(marker)).toBe(false);
  });

  test("instrument: the canary fires when the verb gate is made to execute the command", () => {
    const mutant = mutate(
      '    r = subprocess.run(["bash", gate, command], capture_output=True, text=True, errors="replace")',
      '    subprocess.run(command, shell=True, capture_output=True)\n    r = subprocess.run(["bash", gate, command], capture_output=True, text=True, errors="replace")',
    );
    const { r, marker } = canaryRepo();
    expect(r.verify([], mutant).json?.outcome).toBe("OK");
    expect(existsSync(marker)).toBe(true); // the mutant ran the pinned script, so absence above means something
    // and the structural walk sees nothing wrong with this mutant: only the canary can tell
    expect(astWalk(mutant).funcs).toEqual(["_git", "_verb_gate"]);
  });

  test("it declares no sandbox of its own", () => {
    const src = readFileSync(SCRIPT, "utf8").replace(/#.*$/gm, "");
    expect(/BWRAP_ARGS\s*=\s*\(/i.test(src)).toBe(false);
    expect(/\bbwrap\b/i.test(src)).toBe(false);
  });
});

// ---------------------------------------------------------------------------------------------
// Harness rows: edit the SUBJECT and require the observable to change POSITIVELY. A suite that
// asserts nothing cannot pass these, and a mutant that merely crashes is not a kill: every mutant
// must compile, and each row asserts the mutated behaviour, not just a difference.
// ---------------------------------------------------------------------------------------------
describe("harness rows (the suite goes RED when the subject is gutted)", () => {
  const changedRepo = () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.freeze({ ...BASE, command: "grep -c hi f" });
    return r;
  };

  test("a verify stub that exits 0 does NOT report a changed command (and prints nothing)", () => {
    const dir = mkdtempSync(join(TMP, "fcm-"));
    made.push(dir);
    const stub = join(dir, "founder-check.py");
    writeFileSync(stub, "import sys\nsys.exit(0)\n");
    const r = changedRepo();
    expect(r.verify([], SCRIPT).json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    const s = r.verify([], stub);
    expect(s.status).toBe(0);
    expect(s.stdout).toBe("");
  });

  test("Guard 3: deleting the headless refusal lets a headless OVERRIDDEN through (exit 0 and a row)", () => {
    const mutant = mutate('HEADLESS_REFUSED = frozenset({"OVERRIDDEN", "FOUNDER-CONFIRMED"})', "HEADLESS_REFUSED = frozenset()");
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const { file } = r.verifyFile();
    const cl = join(r.scratch, "cl.json");
    expect(r.classify(["--verify-json", file, "--polarity", "acceptance", "--rc", "1", "--control-rc", "0", "--out", cl]).json?.outcome).toBe("FAILED");
    const args = ["log", "--verify-json", file, "--classify-json", cl, "--polarity", "acceptance", "--mode", "headless", "--outcome", "OVERRIDDEN", "--underlying", "FAILED", "--reason-stdin"];
    expect(runPy(args, { cwd: r.dir, env: r.env(), input: "x\n" }).status).toBe(3);
    const m = runPy(args, { cwd: r.dir, env: r.env(), input: "x\n", script: mutant });
    expect(m.status).toBe(0);
    expect(m.stdout).toContain("outcome=STOPPED-AWAITING-FOUNDER".replace("STOPPED-AWAITING-FOUNDER", "OVERRIDDEN"));
  });

  test("Guard 2: a classify whose baseline vacuous branch is dead reports FAILED-AS-EXPECTED for a check that already passes", () => {
    const mutant = mutate('        if rc == 0 and matched:\n            return Result("VACUOUS", matched, "baseline-passes")', '        if False:\n            return Result("VACUOUS", matched, "baseline-passes")');
    const row = [0, "ok", "ok", "baseline", "grep", true];
    expect(harness("out = list(fc.classify(*data))", row)[0]).toBe("VACUOUS");
    expect(harness("out = list(fc.classify(*data))", row, mutant)[0]).toBe("FAILED-AS-EXPECTED");
  });

  test("Guard 2: a classify that ignores sandbox health reports PASSED over a broken sandbox", () => {
    const mutant = mutate('    if not sandbox_healthy:\n        return Result("INVALID", matched, "sandbox-unhealthy")', "    if False:\n        return Result(\"INVALID\", matched, \"sandbox-unhealthy\")");
    const row = [0, "ok", "ok", "acceptance", "grep", false];
    expect(harness("out = list(fc.classify(*data))", row)[0]).toBe("INVALID");
    expect(harness("out = list(fc.classify(*data))", row, mutant)[0]).toBe("PASSED");
  });

  test("Guard 1: a verify that skips the freeze comparison lets an edited command through as OK", () => {
    const mutant = mutate("changed = [k for k in CANONICAL_FIELDS if head_c[k] != frozen_c[k]]", "changed = []");
    const r = changedRepo();
    expect(r.verify([], SCRIPT).json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(r.verify([], mutant).json?.outcome).toBe("OK");
  });

  test("Guard 1: a static rule set without the pin check accepts an unpinned script", () => {
    const mutant = mutate("        if key not in normalised:\n            return \"unpinned-script\"", "        if False:\n            return \"unpinned-script\"");
    const row = cmdBlock({ command: "bash scripts/new.sh" });
    expect(harness("out = fc.static_problem(data)", row)).toBe("unpinned-script");
    expect(harness("out = fc.static_problem(data)", row, mutant)).toBeNull();
  });

  test("Guard 3: a verify without the PR-login check trusts a forged operator email", () => {
    const mutant = mutate('        elif not a.no_pr:\n            flags.append("pr-author-unmeasurable")', "        elif False:\n            flags.append(\"pr-author-unmeasurable\")");
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    expect(r.py(["verify", "--base", "origin/main"]).json?.outcome).toBe("UNTRUSTED");
    expect(r.py(["verify", "--base", "origin/main"], {}, mutant).json?.outcome).toBe("OK");
  });

  test("the mutants themselves are driven: every anchor exists exactly once in the production script", () => {
    const text = readFileSync(SCRIPT, "utf8");
    for (const a of [
      'HEADLESS_REFUSED = frozenset({"OVERRIDDEN", "FOUNDER-CONFIRMED"})',
      '        if rc == 0 and matched:\n            return Result("VACUOUS", matched, "baseline-passes")',
      '    if not sandbox_healthy:\n        return Result("INVALID", matched, "sandbox-unhealthy")',
      "changed = [k for k in CANONICAL_FIELDS if head_c[k] != frozen_c[k]]",
      '        if key not in normalised:\n            return "unpinned-script"',
      '        elif not a.no_pr:\n            flags.append("pr-author-unmeasurable")',
    ]) {
      expect(text.split(a).length - 1).toBe(1);
    }
  });
});
