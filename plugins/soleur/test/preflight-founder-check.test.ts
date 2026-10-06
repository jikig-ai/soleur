// preflight Check 13 (founder-stated check) — regression suite for founder-check.py (#9578).
//
// The suite drives the PRODUCTION script (plugins/soleur/skills/preflight/scripts/founder-check.py)
// over synthesized git histories, never a TypeScript mirror of it. Every history is built with
// gitFixtureEnv() so a fixture `git` can never be redirected at the developer's live branch by an
// inherited GIT_DIR (plugin AGENTS.md "Test Fixture Conventions").
//
// What each describe pins is named after the Guard it serves in the plan's `## Guard Contract`:
//   Guard 1  frozen-block integrity        -> "verify: ..." and the Guard 1 mutants
//   Guard 2  must-fail baseline            -> "classify: ..." and the Guard 2 mutants
//   Guard 3  consent before run            -> "verify: authorship" and "log: ..."
//   Guard 4  single sandbox chokepoint     -> "Guard 4: ..."
//
// The harness rows at the bottom edit THIS suite's subject (a stub, a deleted refusal) and require
// the observable to change, so a suite that asserts nothing cannot stay green. The counts are also
// floored from OUTSIDE by preflight-check10-suite-integrity.test.sh.
import { afterAll, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import {
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

const SCRIPT = join(import.meta.dir, "..", "skills", "preflight", "scripts", "founder-check.py");
const FIXTURES = join(import.meta.dir, "fixtures", "founder-check");
const PLANS = "knowledge-base/project/plans";
const OPERATOR = "fixture@example.com"; // gitFixtureEnv()'s synthesized identity
const STRANGER = "stranger@example.com";

// ---------------------------------------------------------------------------------------------
// Block rendering. Independent of the script: the canonical hash is recomputed here from the
// documented definition (sha256 over sorted-key compact JSON of the six canonical fields).
// ---------------------------------------------------------------------------------------------
type Fields = {
  kind: string;
  text: string;
  command: string;
  expected: string;
  creates: string[];
  pins: Record<string, string>;
};

const BASE: Fields = {
  kind: "command",
  text: "the home page says hello",
  command: "grep -c hello site/index.html",
  expected: "1",
  creates: [],
  pins: {},
};

function canonicalHash(f: Fields): string {
  const pins = Object.fromEntries(Object.entries(f.pins).sort(([a], [b]) => (a < b ? -1 : 1)));
  const obj = {
    command: f.command,
    creates: f.creates,
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
  if (opts.style === "reformatted") {
    // Same canonical fields, different bytes: single quotes, reordered keys, flow collections,
    // trailing comments.
    const q = (s: string) => `'${s.replace(/'/g, "''")}'`;
    lines.push("founder_check:");
    lines.push(`  text: ${q(f.text)}   # the founder's own words`);
    lines.push(`  kind: ${f.kind}`);
    lines.push(`  expected: ${q(f.expected)}`);
    lines.push(`  command: ${q(f.command)}`);
    lines.push(`  creates: [${f.creates.join(", ")}]`);
    lines.push(
      `  pins: {${Object.entries(f.pins)
        .map(([k, v]) => `${k}: ${v}`)
        .join(", ")}}`,
    );
    lines.push(`  approved_at: "2026-10-06"`);
    lines.push(`  approved_by: "founder"`);
    if (hash !== null) lines.push(`  hash: ${q(hash)}`);
  } else {
    const q = (s: string) => JSON.stringify(s);
    lines.push("founder_check:");
    lines.push(`  kind: ${f.kind}`);
    lines.push(`  text: ${q(f.text)}`);
    lines.push(`  command: ${q(f.command)}`);
    lines.push(`  expected: ${q(f.expected)}`);
    if (f.creates.length === 0) lines.push("  creates: []");
    else {
      lines.push("  creates:");
      for (const c of f.creates) lines.push(`    - ${c}`);
    }
    if (Object.keys(f.pins).length === 0) lines.push("  pins: {}");
    else {
      lines.push("  pins:");
      for (const [k, v] of Object.entries(f.pins)) lines.push(`    ${k}: ${v}`);
    }
    lines.push(`  approved_by: "founder"`);
    lines.push(`  approved_at: "2026-10-06"`);
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
// Repo fixture.
// ---------------------------------------------------------------------------------------------
const made: string[] = [];
afterAll(() => {
  for (const d of made) rmSync(d, { recursive: true, force: true });
});

type Run = { status: number; stdout: string; stderr: string; json: any };

class Repo {
  dir: string;
  constructor() {
    this.dir = mkdtempSync(join(process.env.TMPDIR ?? "/var/tmp", "fc-"));
    made.push(this.dir);
    this.git(["init", "-q", "-b", "main"]);
    this.write("README.md", "fixture\n");
    this.commit("base");
    this.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    this.git(["checkout", "-q", "-b", "feat-x"]);
  }
  env(extra: Record<string, string> = {}): NodeJS.ProcessEnv {
    return { ...gitFixtureEnv(this.dir), ...extra };
  }
  git(args: string[], extra: Record<string, string> = {}): string {
    const r = spawnSync("git", ["-c", "commit.gpgsign=false", ...args], {
      cwd: this.dir,
      env: this.env(extra),
      encoding: "utf8",
    });
    if (r.status !== 0) throw new Error(`git ${args.join(" ")} failed: ${r.stderr}`);
    return r.stdout;
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
  freeze(f: Fields = BASE, name = "p.md", email = OPERATOR, opts: RenderOpts = {}): string {
    this.plan(name, scaffold("plan-ac.md", { BLOCK: renderBlock(f, opts) }));
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
  advanceMain() {
    // A new commit on main, then origin/main follows it: the situation after a rebase.
    this.git(["checkout", "-q", "main"]);
    this.write("main-only.txt", "x\n");
    this.commit("main moves");
    this.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    this.git(["checkout", "-q", "feat-x"]);
  }
  py(args: string[], extra: Record<string, string> = {}, script = SCRIPT): Run {
    const r = spawnSync("python3", [script, ...args], {
      cwd: this.dir,
      env: this.env(extra),
      encoding: "utf8",
    });
    let json: any = null;
    try {
      json = JSON.parse(r.stdout);
    } catch {
      // not JSON: leave null so the assertion on `json?.x` fails loudly instead of throwing here
    }
    return { status: r.status ?? -1, stdout: r.stdout, stderr: r.stderr, json };
  }
  verify(extra: string[] = [], script = SCRIPT): Run {
    return this.py(["verify", "--base", "origin/main", ...extra], {}, script);
  }
}

function classify(args: string[], script = SCRIPT): Run {
  const r = spawnSync("python3", [script, "classify", ...args], { encoding: "utf8" });
  let json: any = null;
  try {
    json = JSON.parse(r.stdout);
  } catch {
    /* see Repo.py */
  }
  return { status: r.status ?? -1, stdout: r.stdout, stderr: r.stderr, json };
}

// ---------------------------------------------------------------------------------------------
describe("verify: resolution", () => {
  test("no plan change on the branch is NO-BLOCK, exit 0 (the SKIP banner case)", () => {
    const r = new Repo();
    r.write("src/a.txt", "a\n");
    r.commit("code only");
    const v = r.verify();
    expect(v.json?.outcome).toBe("NO-BLOCK");
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
    const v = r.verify();
    expect(v.json?.outcome).toBe("NO-BLOCK");
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

  test("two blocks in one Acceptance Criteria section is FAIL", () => {
    const r = new Repo();
    r.plan(
      "p.md",
      scaffold("plan-two-blocks.md", {
        BLOCK: renderBlock(BASE),
        BLOCK2: renderBlock({ ...BASE, command: "grep -c other f" }),
      }),
    );
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

  test("a symlinked plan is FAIL, never followed", () => {
    const r = new Repo();
    r.write("elsewhere/real.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    mkdirSync(join(r.dir, PLANS), { recursive: true });
    symlinkSync(join(r.dir, "elsewhere", "real.md"), join(r.dir, PLANS, "p.md"));
    r.commit("symlinked plan");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("symlinked-plan");
  });

  test("a block with no freeze commit (uncommitted working tree) is FAIL", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("no-freeze");
  });
});

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
    expect(v.status).toBe(0);
  });

  test("a YAML reformat with equal canonical fields still passes (must-PASS)", () => {
    const r = new Repo();
    r.freeze();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE, { style: "reformatted" }) }));
    r.commit("work reformats the plan");
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
  });

  test("row 1: an edited command after the freeze is CHANGED-SINCE-APPROVAL", () => {
    const r = new Repo();
    r.freeze();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, command: "grep -c hi site/index.html" }) }));
    r.commit("work edits the command");
    const v = r.verify();
    expect(v.json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(v.json?.changed_fields).toContain("command");
    expect(v.status).toBe(1);
  });

  test("an edited expected after the freeze is CHANGED-SINCE-APPROVAL", () => {
    const r = new Repo();
    r.freeze();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, expected: "" }) }));
    r.commit("work weakens expected");
    const v = r.verify();
    expect(v.json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(v.json?.changed_fields).toContain("expected");
  });

  test("row 4: edit expected AND recompute hash in one commit is still CHANGED", () => {
    const r = new Repo();
    r.freeze();
    const weakened = { ...BASE, expected: "" };
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(weakened) })); // hash recomputed
    r.commit("block and hash edited together");
    const v = r.verify();
    expect(v.json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    // the hash agrees with the file; only the freeze copy disagrees
    expect(v.json?.hash).toBe(canonicalHash(weakened));
  });

  test("an edited field with a STALE hash is FAIL (the block disagrees with itself)", () => {
    const r = new Repo();
    r.freeze();
    r.plan(
      "p.md",
      scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, expected: "" }, { hash: canonicalHash(BASE) }) }),
    );
    r.commit("field edited, hash left");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("hash-mismatch");
  });

  test("a removed hash line is tolerated and the recomputed identity is reported", () => {
    const r = new Repo();
    r.freeze(BASE, "p.md", OPERATOR, { hash: null });
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.hash).toBe(canonicalHash(BASE));
  });

  test("row 2: a plan deleted after the freeze is FAIL, never SKIP", () => {
    const r = new Repo();
    r.freeze();
    r.git(["rm", "-q", `${PLANS}/p.md`]);
    r.commit("delete the plan");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("freeze-without-block");
  });

  test("row 2: a plan renamed after the freeze is FAIL", () => {
    const r = new Repo();
    r.freeze();
    r.git(["mv", `${PLANS}/p.md`, `${PLANS}/renamed.md`]);
    r.commit("rename the plan");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
  });

  test("row 2: a plan stripped of its block while a freeze exists is FAIL", () => {
    const r = new Repo();
    r.freeze();
    r.plan("p.md", scaffold("plan-no-block.md", {}));
    r.commit("strip the block");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("freeze-without-block");
  });

  test("row 3: a second differing block added after a compliant first is FAIL", () => {
    const r = new Repo();
    r.freeze();
    r.plan(
      "p.md",
      scaffold("plan-two-blocks.md", {
        BLOCK: renderBlock(BASE),
        BLOCK2: renderBlock({ ...BASE, command: "grep -c other f" }),
      }),
    );
    r.commit("add a second block");
    expect(r.verify().json?.outcome).toBe("FAIL");
  });

  test("a rebased branch with new SHAs still passes (must-PASS)", () => {
    const r = new Repo();
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    r.advanceMain();
    r.git(["rebase", "-q", "main"]);
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
  });

  test("a learnings-only commit before the freeze does not fail it (must-PASS)", () => {
    const r = new Repo();
    r.write("knowledge-base/project/learnings/note.md", "# note\n");
    r.commit("learning");
    r.freeze();
    r.write("src/a.txt", "a\n");
    r.commit("code");
    expect(r.verify().json?.outcome).toBe("OK");
  });

  test("a plan already on main is frozen at the merge-base copy (must-PASS)", () => {
    const r = new Repo();
    r.git(["checkout", "-q", "main"]);
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.commit("plan merged on main");
    r.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    r.git(["checkout", "-q", "feat-x"]);
    r.git(["rebase", "-q", "main"]);
    r.write("src/a.txt", "a\n");
    r.commit("code");
    const v = r.verify(["--plan", `${PLANS}/p.md`]);
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.freeze_source).toBe("merge-base");
  });

  test("a plan already on main that the branch then edits is CHANGED", () => {
    const r = new Repo();
    r.git(["checkout", "-q", "main"]);
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.commit("plan merged on main");
    r.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    r.git(["checkout", "-q", "feat-x"]);
    r.git(["rebase", "-q", "main"]);
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, expected: "" }) }));
    r.commit("branch weakens the check");
    expect(r.verify(["--plan", `${PLANS}/p.md`]).json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
  });

  test("a freeze committed together with code is an ordering violation: stop-and-ask, not FAIL", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.write("src/a.txt", "a\n");
    r.commit("plan and code together");
    const v = r.verify();
    expect(v.json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(v.json?.reasons).toContain("ordering");
  });

  test("a code commit that precedes the freeze is an ordering violation", () => {
    const r = new Repo();
    r.write("src/a.txt", "a\n");
    r.commit("code first");
    r.freeze();
    const v = r.verify();
    expect(v.json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(v.json?.reasons).toContain("ordering");
  });
});

describe("verify: block rules", () => {
  test("a verb off the probe allowlist is FAIL", () => {
    const r = new Repo();
    r.freeze({ ...BASE, command: "ls site" });
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("verb-gate");
  });

  test("kind must be command or judgement", () => {
    const r = new Repo();
    r.freeze({ ...BASE, kind: "vibes" });
    expect(r.verify().json?.reason).toBe("invalid-kind");
  });

  test("a judgement check carries no command and passes", () => {
    const r = new Repo();
    r.freeze({ ...BASE, kind: "judgement", command: "", expected: "" });
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
    expect(v.json?.block?.kind).toBe("judgement");
  });

  test("credentials_required is FAIL (a check needing credentials is a judgement check)", () => {
    const r = new Repo();
    r.plan(
      "p.md",
      scaffold("plan-ac.md", {
        BLOCK: renderBlock(BASE, { extra: ["credentials_required: [SOME_TOKEN]"] }),
      }),
    );
    r.commit("plan: freeze");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("credentials-required");
  });

  test("an unparseable block is FAIL, never SKIP", () => {
    const r = new Repo();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: "```yaml\nfounder_check:\n  kind command\n    : : :\n```" }));
    r.commit("plan: freeze");
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("unparseable");
  });

  test("row 6: an interpreter verb naming a script that is not pinned is FAIL", () => {
    const r = new Repo();
    r.mainFile("scripts/check.sh", "echo ok\n");
    r.freeze({ ...BASE, command: "bash scripts/check.sh", expected: "ok" });
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("unpinned-script");
  });

  test("an interpreter verb with every script pinned by blob sha passes", () => {
    const r = new Repo();
    r.mainFile("scripts/check.sh", "echo ok\n");
    const blob = r.git(["rev-parse", "HEAD:scripts/check.sh"]).trim();
    r.freeze({ ...BASE, command: "bash scripts/check.sh", expected: "ok", pins: { "scripts/check.sh": blob } });
    const v = r.verify();
    expect(v.json?.outcome).toBe("OK");
  });

  test("row 5: editing a pinned script after the freeze is CHANGED-SINCE-APPROVAL", () => {
    const r = new Repo();
    r.mainFile("scripts/check.sh", "echo ok\n");
    const blob = r.git(["rev-parse", "HEAD:scripts/check.sh"]).trim();
    r.freeze({ ...BASE, command: "bash scripts/check.sh", expected: "ok", pins: { "scripts/check.sh": blob } });
    r.write("scripts/check.sh", "echo always-ok\n");
    r.commit("work rewrites the pinned script");
    const v = r.verify();
    expect(v.json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(v.json?.reasons).toContain("pinned-script-changed");
  });

  test("a pin whose sha is not the blob at the freeze is FAIL", () => {
    const r = new Repo();
    r.mainFile("scripts/check.sh", "echo ok\n");
    r.freeze({
      ...BASE,
      command: "bash scripts/check.sh",
      expected: "ok",
      pins: { "scripts/check.sh": "0".repeat(40) },
    });
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("pin-not-at-freeze");
  });

  test("a pinned script that does not exist at the freeze is FAIL", () => {
    const r = new Repo();
    r.freeze({
      ...BASE,
      command: "bash scripts/new.sh",
      expected: "ok",
      pins: { "scripts/new.sh": "1".repeat(40) },
    });
    expect(r.verify().json?.reason).toBe("pin-not-at-freeze");
  });

  test("row 6: creates combined with an interpreter verb is FAIL", () => {
    const r = new Repo();
    r.freeze({ ...BASE, command: "python3 scripts/new.py", expected: "ok", creates: ["scripts/new.py"] });
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("creates-with-interpreter");
  });

  test("creates with a non-interpreter verb passes when the path is absent at the freeze", () => {
    const r = new Repo();
    r.freeze({ ...BASE, command: "grep -c hello site/new.html", expected: "1", creates: ["site/new.html"] });
    expect(r.verify().json?.outcome).toBe("OK");
  });

  test("creates naming a path that already exists at the freeze (a stub) is FAIL", () => {
    const r = new Repo();
    r.write("site/new.html", "stub\n");
    r.commit("stub already present");
    r.freeze({ ...BASE, command: "grep -c hello site/new.html", expected: "1", creates: ["site/new.html"] });
    const v = r.verify();
    expect(v.json?.outcome).toBe("FAIL");
    expect(v.json?.reason).toBe("creates-exists-at-freeze");
  });
});

describe("verify: authorship (Guard 3)", () => {
  test("a freeze authored by another identity is UNTRUSTED, exit 1", () => {
    const r = new Repo();
    r.freeze(BASE, "p.md", STRANGER);
    const v = r.verify();
    expect(v.json?.outcome).toBe("UNTRUSTED");
    expect(v.status).toBe(1);
  });

  test("a freeze authored by the local identity is trusted (must-PASS)", () => {
    const r = new Repo();
    r.freeze(BASE, "p.md", OPERATOR);
    expect(r.verify().json?.outcome).toBe("OK");
  });

  test("a PR author who is not the authenticated login is UNTRUSTED", () => {
    const r = new Repo();
    r.freeze();
    const v = r.verify(["--pr-author", "someone-else", "--operator-login", "the-operator"]);
    expect(v.json?.outcome).toBe("UNTRUSTED");
  });

  test("a PR author equal to the authenticated login is trusted", () => {
    const r = new Repo();
    r.freeze();
    const v = r.verify(["--pr-author", "the-operator", "--operator-login", "the-operator"]);
    expect(v.json?.outcome).toBe("OK");
  });

  test("a merge-base freeze (reviewed on main) is trusted whoever wrote it", () => {
    const r = new Repo();
    r.git(["checkout", "-q", "main"]);
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock(BASE) }));
    r.commit("plan merged on main", STRANGER);
    r.git(["update-ref", "refs/remotes/origin/main", "HEAD"]);
    r.git(["checkout", "-q", "feat-x"]);
    r.git(["rebase", "-q", "main"]);
    expect(r.verify(["--plan", `${PLANS}/p.md`]).json?.outcome).toBe("OK");
  });
});

// ---------------------------------------------------------------------------------------------
describe("classify (Guard 2)", () => {
  const A = (rc: number, extra: string[] = []) => ["--rc", String(rc), "--polarity", "acceptance", ...extra];
  const B = (rc: number, extra: string[] = []) => ["--rc", String(rc), "--polarity", "baseline", ...extra];

  test("acceptance: rc 0 with an empty expected is PASSED", () => {
    const c = classify(A(0, ["--stdout", "anything"]));
    expect(c.json?.outcome).toBe("PASSED");
    expect(c.json?.expected_matched).toBe(true);
  });

  test("acceptance: rc 0 with expected present in stdout is PASSED", () => {
    expect(classify(A(0, ["--stdout", "total 34 rows", "--expected", "34"])).json?.outcome).toBe("PASSED");
  });

  test("acceptance: rc 0 with expected absent is FAILED", () => {
    const c = classify(A(0, ["--stdout", "total 3 rows", "--expected", "34"]));
    expect(c.json?.outcome).toBe("FAILED");
    expect(c.json?.expected_matched).toBe(false);
  });

  test("acceptance: a non-zero rc is FAILED even when expected is present", () => {
    expect(classify(A(1, ["--stdout", "34", "--expected", "34"])).json?.outcome).toBe("FAILED");
  });

  test("row 1: a baseline that already passes is VACUOUS", () => {
    expect(classify(B(0, ["--stdout", "ok", "--expected", "ok"])).json?.outcome).toBe("VACUOUS");
  });

  test("a baseline with a non-zero rc is FAILED-AS-EXPECTED", () => {
    expect(classify(B(1, ["--stdout", ""])).json?.outcome).toBe("FAILED-AS-EXPECTED");
  });

  test("a baseline with rc 0 but expected absent is FAILED-AS-EXPECTED (a real fail)", () => {
    expect(classify(B(0, ["--stdout", "no", "--expected", "yes"])).json?.outcome).toBe("FAILED-AS-EXPECTED");
  });

  for (const rc of [124, 126, 127]) {
    test(`rc ${rc} is INVALID in both polarities (tooling, not a result)`, () => {
      expect(classify(A(rc)).json?.outcome).toBe("INVALID");
      expect(classify(B(rc)).json?.outcome).toBe("INVALID");
    });
  }

  for (const rc of [6, 7, 28]) {
    test(`rc ${rc} is INVALID when the first token is curl`, () => {
      expect(classify(B(rc, ["--first-token", "curl"])).json?.outcome).toBe("INVALID");
      expect(classify(A(rc, ["--first-token", "curl"])).json?.outcome).toBe("INVALID");
    });
    test(`rc ${rc} is an ordinary result when the first token is not curl`, () => {
      expect(classify(A(rc, ["--first-token", "git"])).json?.outcome).toBe("FAILED");
    });
  }

  test("row 3: an unhealthy sandbox is INVALID, never a baseline fail", () => {
    // bwrap's own runtime errors surface as an ordinary rc 1
    const c = classify(B(1, ["--sandbox-healthy", "false"]));
    expect(c.json?.outcome).toBe("INVALID");
    expect(c.json?.reason).toBe("sandbox-unhealthy");
  });

  test("row 4: rc 127 for a target NOT listed in creates is INVALID", () => {
    expect(classify(B(127, ["--first-token", "bash"])).json?.outcome).toBe("INVALID");
  });

  test("a listed creates path that is absent makes any non-zero baseline rc a valid fail", () => {
    for (const rc of [1, 2, 126, 127]) {
      const c = classify(B(rc, ["--creates", "scripts/new.sh", "--target-present", "false"]));
      expect(c.json?.outcome).toBe("FAILED-AS-EXPECTED");
    }
  });

  test("a timeout is never exempted by creates", () => {
    expect(classify(B(124, ["--creates", "x/y", "--target-present", "false"])).json?.outcome).toBe("INVALID");
  });

  test("a creates path that is PRESENT does not exempt rc 127", () => {
    expect(classify(B(127, ["--creates", "x/y", "--target-present", "true"])).json?.outcome).toBe("INVALID");
  });

  test("an unknown polarity is a usage error, exit 2", () => {
    const c = classify(["--rc", "0", "--polarity", "sideways"]);
    expect(c.status).toBe(2);
    expect(c.stderr).toContain("polarity");
  });
});

// ---------------------------------------------------------------------------------------------
describe("log (Guard 3 and the leakage rule)", () => {
  const row = (extra: string[]) => [
    "log",
    "--log",
    "specs/founder-check-log.md",
    "--kind",
    "command",
    "--command",
    "grep -c hello site/index.html",
    "--rc",
    "1",
    "--attempt-n",
    "1",
    "--tested-sha",
    "abc1234",
    "--hash",
    "f".repeat(64),
    "--output-sha256",
    "e".repeat(64),
    "--expected-matched",
    "false",
    ...extra,
  ];
  const logOf = (r: Repo) => {
    const p = join(r.dir, "specs", "founder-check-log.md");
    return existsSync(p) ? readFileSync(p, "utf8") : "";
  };

  test("headless refuses OVERRIDDEN and writes nothing", () => {
    const r = new Repo();
    const x = r.py(row(["--mode", "headless", "--outcome", "OVERRIDDEN", "--reason", "because"]));
    expect(x.status).toBe(3);
    expect(logOf(r)).toBe("");
  });

  test("headless refuses FOUNDER-CONFIRMED and writes nothing", () => {
    const r = new Repo();
    const x = r.py(row(["--mode", "headless", "--outcome", "FOUNDER-CONFIRMED"]));
    expect(x.status).toBe(3);
    expect(logOf(r)).toBe("");
  });

  test("interactive OVERRIDDEN without a reason is refused", () => {
    const r = new Repo();
    const x = r.py(row(["--mode", "interactive", "--outcome", "OVERRIDDEN"]));
    expect(x.status).toBe(3);
    expect(logOf(r)).toBe("");
  });

  test("interactive OVERRIDDEN with a reason is recorded as an override, never as a pass", () => {
    const r = new Repo();
    const x = r.py(row(["--mode", "interactive", "--outcome", "OVERRIDDEN", "--reason", "shipping a hotfix"]));
    expect(x.status).toBe(0);
    const log = logOf(r);
    expect(log).toContain("OVERRIDDEN");
    expect(log).toContain("shipping a hotfix");
    expect(log).not.toMatch(/PASSED/);
  });

  test("a headless failing check is recorded as STOPPED-AWAITING-FOUNDER, with the underlying outcome kept", () => {
    const r = new Repo();
    const x = r.py(row(["--mode", "headless", "--outcome", "FAILED"]));
    expect(x.status).toBe(0);
    const log = logOf(r);
    expect(log).toContain("STOPPED-AWAITING-FOUNDER");
    expect(log).toContain("FAILED");
    expect(x.stdout).toContain("outcome=STOPPED-AWAITING-FOUNDER");
  });

  test("headless with an approved block and no sandbox is STOPPED-AWAITING-FOUNDER; without a block it stays SKIP-NOSANDBOX", () => {
    const r = new Repo();
    const withBlock = r.py(row(["--mode", "headless", "--outcome", "SKIP-NOSANDBOX", "--block-present", "true"]));
    expect(withBlock.stdout).toContain("outcome=STOPPED-AWAITING-FOUNDER");
    const without = r.py(row(["--mode", "headless", "--outcome", "SKIP-NOSANDBOX", "--block-present", "false"]));
    expect(without.stdout).toContain("outcome=SKIP-NOSANDBOX");
  });

  test("the log is append-only: a second row leaves the first byte-identical", () => {
    const r = new Repo();
    r.py(row(["--mode", "interactive", "--outcome", "FAILED"]));
    const first = logOf(r);
    r.py(row(["--mode", "interactive", "--outcome", "PASSED", "--attempt-n", "2"]));
    const second = logOf(r);
    expect(second.startsWith(first)).toBe(true);
    expect(second.length).toBeGreaterThan(first.length);
  });

  test("a row carries rc, attempt, sha, hash and output hash but no output text", () => {
    const r = new Repo();
    const x = r.py(row(["--mode", "interactive", "--outcome", "FAILED"]));
    expect(x.status).toBe(0);
    const log = logOf(r);
    for (const needle of ["abc1234", "f".repeat(64), "e".repeat(64), "FAILED"]) expect(log).toContain(needle);
  });

  test("there is no way to hand the log the command's output", () => {
    const r = new Repo();
    const x = r.py(row(["--mode", "interactive", "--outcome", "FAILED", "--output", "SECRET-VALUE"]));
    expect(x.status).toBe(2);
    expect(x.stderr).toContain("--output");
    expect(logOf(r)).not.toContain("SECRET-VALUE");
  });

  test("a non-hex output hash is refused", () => {
    const r = new Repo();
    const x = r.py(
      row(["--mode", "interactive", "--outcome", "FAILED"]).map((a) => (a === "e".repeat(64) ? "SECRET-VALUE" : a)),
    );
    expect(x.status).toBe(3);
    expect(x.stderr).toContain("output-sha256");
    expect(logOf(r)).not.toContain("SECRET-VALUE");
  });

  test("a command with pipes and newlines cannot break the row apart", () => {
    const r = new Repo();
    const args = row(["--mode", "interactive", "--outcome", "FAILED"]).map((a) =>
      a === "grep -c hello site/index.html" ? "grep a | b\nINJECTED ROW" : a,
    );
    expect(r.py(args).status).toBe(0);
    const dataRows = logOf(r)
      .split("\n")
      .filter((l) => l.startsWith("| ") && !l.startsWith("| kind") && !l.startsWith("| ---"));
    expect(dataRows.length).toBe(1);
  });

  test("the stdout marker is metadata only: outcome, hash, tested_sha", () => {
    const r = new Repo();
    const x = r.py(row(["--mode", "interactive", "--outcome", "FAILED"]));
    const marker = x.stdout.split("\n").find((l) => l.startsWith("SOLEUR_FOUNDER_CHECK_RESULT"));
    expect(marker).toBe(`SOLEUR_FOUNDER_CHECK_RESULT outcome=FAILED hash=${"f".repeat(64)} tested_sha=abc1234`);
    expect(marker).not.toContain("grep");
  });
});

describe("summary (the layer-7 discoverability probe)", () => {
  test("prints founder-check: no log before any run", () => {
    const r = new Repo();
    const x = r.py(["summary"]);
    expect(x.status).toBe(0);
    expect(x.stdout.trim()).toBe("founder-check: no log");
  });

  test("prints the row count over a populated log", () => {
    const r = new Repo();
    const args = (n: number, outcome: string) => [
      "log", "--log", "specs/founder-check-log.md", "--mode", "interactive", "--outcome", outcome,
      "--kind", "command", "--command", "grep -c a f", "--rc", "1", "--attempt-n", String(n),
      "--tested-sha", "abc1234", "--hash", "f".repeat(64),
    ];
    r.py(args(1, "FAILED"));
    r.py(args(2, "PASSED"));
    const x = r.py(["summary", "--log", "specs/founder-check-log.md"]);
    expect(x.stdout.split("\n")[0]).toBe("founder-check: 2 rows");
  });

  test("a pass after failures says so", () => {
    const r = new Repo();
    const args = (n: number, outcome: string) => [
      "log", "--log", "specs/founder-check-log.md", "--mode", "interactive", "--outcome", outcome,
      "--kind", "command", "--command", "grep -c a f", "--rc", "1", "--attempt-n", String(n),
      "--tested-sha", "abc1234", "--hash", "f".repeat(64),
    ];
    r.py(args(1, "FAILED"));
    r.py(args(2, "FAILED"));
    r.py(args(3, "PASSED"));
    const x = r.py(["summary", "--log", "specs/founder-check-log.md"]);
    expect(x.stdout).toContain("PASSED on attempt 3 after 2 failures");
  });

  test("with no --log it reads the current branch's spec directory", () => {
    const r = new Repo();
    r.write(
      "knowledge-base/project/specs/feat-x/founder-check-log.md",
      "| kind | outcome |\n| --- | --- |\n| command | FAILED |\n",
    );
    expect(r.py(["summary"]).stdout.split("\n")[0]).toBe("founder-check: 1 rows");
  });
});

// ---------------------------------------------------------------------------------------------
describe("wording constants", () => {
  const text = (name: string, extra: string[] = []) =>
    spawnSync("python3", [SCRIPT, "text", name, ...extra], { encoding: "utf8" });

  const EXACT: Record<string, string> = {
    judgement: "You confirmed this by looking. No command ran for it.",
    "first-use":
      "A vague, wrong or unsafe check can pass broken work or run actions you did not intend. Read what will run before it runs. One check does not cover everything. The text and command you approve are committed to this repository.",
    "no-block": "No founder-stated check was defined. Nothing was run on your behalf.",
    "no-sandbox": "Your check did not run on this host.",
    "no-sandbox-ask": "Your check did not run on this host. Continue without it?",
  };

  for (const [name, want] of Object.entries(EXACT)) {
    test(`'${name}' matches the plan's text exactly`, () => {
      const t = text(name);
      expect(t.status).toBe(0);
      expect(t.stdout.trimEnd()).toBe(want);
    });
  }

  test("'pass' matches the plan's sentence with the sha filled in", () => {
    const t = text("pass", ["--sha", "abc1234"]);
    expect(t.stdout.trimEnd()).toBe(
      "Your check passed. This shows only that the check you wrote ran and returned success against abc1234. It does not confirm the work is correct, complete or safe. Review the result before relying on it.",
    );
  });

  test("the aggregate row says ran, returned success against the sha — never a bare PASS", () => {
    const t = text("aggregate-pass", ["--sha", "abc1234"]);
    expect(t.stdout.trimEnd()).toBe("Founder check: ran, returned success against abc1234");
  });

  test("no string claims 'verified', 'proven' or 'safe' (the pass sentence's one negation is the exemption)", () => {
    const names = [...Object.keys(EXACT), "pass", "aggregate-pass"];
    for (const n of names) {
      let s = text(n, ["--sha", "abc1234"]).stdout;
      expect(s.length).toBeGreaterThan(20); // an empty read must not satisfy a negative assertion
      s = s.replace("complete or safe", "complete");
      expect(s).not.toMatch(/\b(verified|proven|safe)\b/i);
    }
  });

  test("an unknown name is a usage error", () => {
    const t = text("nonsense");
    expect(t.status).toBe(2);
    expect(t.stderr).toContain("nonsense");
  });
});

// ---------------------------------------------------------------------------------------------
describe("Guard 4: the script holds no sandbox and never executes the founder command", () => {
  const read = () => readFileSync(SCRIPT, "utf8");

  test("no shell-out primitives", () => {
    const src = read();
    for (const bad of ["os.system", "shell=True", "os.popen", "os.exec", "os.spawn", "bash -c", "pty.spawn"]) {
      expect(src.includes(bad)).toBe(false);
    }
  });

  test("exactly two subprocess call sites: git and the verb gate", () => {
    const calls = read().match(/subprocess\.(run|Popen|call|check_output|check_call)\(/g) ?? [];
    expect(calls.length).toBe(2);
  });

  test("it declares no sandbox of its own", () => {
    const src = read();
    expect(/BWRAP_ARGS\s*=\s*\(/.test(src)).toBe(false);
    expect(/\bbwrap\b/.test(src.replace(/#.*$/gm, ""))).toBe(false);
  });
});

// ---------------------------------------------------------------------------------------------
// Harness rows: edit the SUBJECT and require the observable to change. A suite that asserts
// nothing cannot pass these.
// ---------------------------------------------------------------------------------------------
describe("harness rows (the suite goes RED when the subject is gutted)", () => {
  const mutate = (anchor: string, replacement: string): string => {
    const text = readFileSync(SCRIPT, "utf8");
    if (!text.includes(anchor)) throw new Error(`mutation anchor absent from founder-check.py: ${anchor}`);
    const dir = mkdtempSync(join(process.env.TMPDIR ?? "/var/tmp", "fcm-"));
    made.push(dir);
    const p = join(dir, "founder-check.py");
    writeFileSync(p, text.replace(anchor, replacement));
    // the verb gate is resolved relative to the script, so carry it along
    const gate = join(dirname(SCRIPT), "probe-verb-gate.sh");
    writeFileSync(join(dir, "probe-verb-gate.sh"), readFileSync(gate, "utf8"), { mode: 0o755 });
    return p;
  };

  test("a verify that always exits 0 does NOT report a changed command", () => {
    const stub = join(mkdtempSync(join(process.env.TMPDIR ?? "/var/tmp", "fcm-")), "founder-check.py");
    made.push(dirname(stub));
    writeFileSync(stub, "import sys\nsys.exit(0)\n");
    const r = new Repo();
    r.freeze();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, command: "grep -c hi f" }) }));
    r.commit("edit");
    expect(r.verify([], SCRIPT).json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(r.verify([], stub).json?.outcome).not.toBe("CHANGED-SINCE-APPROVAL");
  });

  test("Guard 3: deleting the headless refusal lets a headless OVERRIDDEN through", () => {
    const mutant = mutate("HEADLESS_REFUSED = frozenset({\"OVERRIDDEN\", \"FOUNDER-CONFIRMED\"})", "HEADLESS_REFUSED = frozenset()");
    const r = new Repo();
    const args = [
      "log", "--log", "specs/l.md", "--mode", "headless", "--outcome", "OVERRIDDEN", "--reason", "x",
      "--kind", "command", "--command", "grep -c a f", "--rc", "1", "--attempt-n", "1",
      "--tested-sha", "abc1234", "--hash", "f".repeat(64),
    ];
    expect(r.py(args).status).toBe(3);
    expect(r.py(args, {}, mutant).status).not.toBe(3);
  });

  test("Guard 2: a classify that returns FAILED-AS-EXPECTED unconditionally makes the VACUOUS case disappear", () => {
    const mutant = mutate("# mutation-anchor: baseline-vacuous", "return Result(\"FAILED-AS-EXPECTED\", matched, \"mutant\")");
    const args = ["--rc", "0", "--polarity", "baseline", "--stdout", "ok", "--expected", "ok"];
    expect(classify(args).json?.outcome).toBe("VACUOUS");
    expect(classify(args, mutant).json?.outcome).not.toBe("VACUOUS");
  });

  test("Guard 1: a verify that skips the freeze comparison lets an edited command through", () => {
    const mutant = mutate("changed = [k for k in CANONICAL_FIELDS if head_c[k] != frozen_c[k]]", "changed = []");
    const r = new Repo();
    r.freeze();
    r.plan("p.md", scaffold("plan-ac.md", { BLOCK: renderBlock({ ...BASE, command: "grep -c hi f" }) }));
    r.commit("edit");
    expect(r.verify([], SCRIPT).json?.outcome).toBe("CHANGED-SINCE-APPROVAL");
    expect(r.verify([], mutant).json?.outcome).toBe("OK");
  });

  test("the mutants themselves are driven: the anchors exist in the production script", () => {
    const text = readFileSync(SCRIPT, "utf8");
    for (const a of [
      "HEADLESS_REFUSED = frozenset({\"OVERRIDDEN\", \"FOUNDER-CONFIRMED\"})",
      "# mutation-anchor: baseline-vacuous",
      "changed = [k for k in CANONICAL_FIELDS if head_c[k] != frozen_c[k]]",
    ]) {
      expect(text.includes(a)).toBe(true);
    }
  });
});
