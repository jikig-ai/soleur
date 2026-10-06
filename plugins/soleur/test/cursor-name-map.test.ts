import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join, resolve } from "path";
import { parse as parseYaml } from "yaml";
import {
  buildCursorNameMap,
  cursorNameMapProblems,
  cursorSkillSlash,
  writeCursorNameMap,
} from "../scripts/sync-cursor-name-map";

const pluginRoot = resolve(import.meta.dir, "..");
const script = join(pluginRoot, "scripts/sync-cursor-name-map.ts");

function combined(proc: ReturnType<typeof Bun.spawnSync>): string {
  return `${proc.stdout.toString()}${proc.stderr.toString()}`;
}

function runCheck(root: string) {
  return Bun.spawnSync(["bun", script, "--check", "--root", root], {
    cwd: resolve(pluginRoot, "../.."),
    stdout: "pipe",
    stderr: "pipe",
  });
}

function writeSkill(root: string, folder: string, description: string | null, body = "canonical body\n"): void {
  const dir = join(root, "skills", folder);
  mkdirSync(dir, { recursive: true });
  const descriptionLine = description === null ? "" : `description: ${JSON.stringify(description)}\n`;
  writeFileSync(join(dir, "SKILL.md"), `---\nname: not-the-folder\n${descriptionLine}---\n\n${body}`);
}

function writeAgent(root: string, rel: string, description: string | null): void {
  const abs = join(root, "agents", rel);
  mkdirSync(join(abs, ".."), { recursive: true });
  const descriptionLine = description === null ? "" : `description: ${JSON.stringify(description)}\n`;
  writeFileSync(abs, `---\nname: leaf\n${descriptionLine}---\n\nagent body\n`);
}

function fixture(): string {
  const root = mkdtempSync(join(tmpdir(), "soleur-cursor-map-"));
  mkdirSync(join(root, "agents"), { recursive: true });
  writeSkill(root, "go", "Route the request.");
  writeSkill(root, "sync", "Read the tree.");
  writeSkill(root, "help", "List the commands.", "Detect the active harness as Devin and stop.\n");
  writeSkill(root, "plan", 'Use soleur:finance:cfo for "budget" work.');
  writeSkill(root, "review", "Review the diff.");
  writeSkill(root, "notes", null);
  writeAgent(root, "engineering/cto.md", "Use soleur:finance:cfo.");
  writeAgent(root, "bare.md", null);
  return root;
}

function frontmatter(text: string): Record<string, unknown> {
  const match = text.match(/^---\n([\s\S]*?)\n---/);
  if (!match) throw new Error("stub has no frontmatter");
  return parseYaml(match[1]) as Record<string, unknown>;
}

describe("cursor name map fixture", () => {
  test("bare names stay bare and the other stubs are soleur-prefixed pointers", () => {
    const root = fixture();
    try {
      expect(writeCursorNameMap(root)).toEqual([]);
      const go = readFileSync(join(root, "cursor/skills/go/SKILL.md"), "utf8");
      expect(go).toContain("name: go\n");
      expect(go).toContain("Read `commands/go.md`, relative to the plugin root.");
      expect(go).not.toContain("skills/go/SKILL.md");
      expect(go).not.toContain("plugins/soleur/");
      expect(go).not.toContain("disable-model-invocation");
      expect(go).toContain("do not call the Skill tool");
      expect(go).toContain("AwaitShell");

      const sync = readFileSync(join(root, "cursor/skills/sync/SKILL.md"), "utf8");
      expect(sync).toContain("name: sync\n");
      expect(sync).toContain("commands/sync.md");

      const help = readFileSync(join(root, "cursor/skills/soleur-help/SKILL.md"), "utf8");
      expect(help).toContain("name: soleur-help\n");
      expect(help).toContain("commands/help.md");
      expect(help).not.toContain("skills/help/SKILL.md");
      expect(help).not.toContain("Detect the active harness as Devin");
      expect(help).toContain("disable-model-invocation: true");
      expect(existsSync(join(root, "cursor/skills/help/SKILL.md"))).toBe(false);
      expect(existsSync(join(root, "cursor/skills/soleur-go/SKILL.md"))).toBe(false);

      const plan = readFileSync(join(root, "cursor/skills/soleur-plan/SKILL.md"), "utf8");
      const planLine = plan.split("\n").find((line) => line.startsWith("description: "));
      expect(planLine).toBe('description: "Use soleur:finance:cfo for \\"budget\\" work."');
      expect(frontmatter(plan).description).toBe('Use soleur:finance:cfo for "budget" work.');
      expect(plan).toContain("skills/plan/SKILL.md");
      expect(plan).toContain("disable-model-invocation: true");
      expect(readFileSync(join(root, "cursor/skills/soleur-review/SKILL.md"), "utf8")).toContain(
        "disable-model-invocation: true",
      );

      const notes = readFileSync(join(root, "cursor/skills/soleur-notes/SKILL.md"), "utf8");
      expect(notes).not.toContain("description:");
      expect(notes).not.toContain("disable-model-invocation");

      const cto = readFileSync(join(root, "cursor/agents/soleur-engineering-cto.md"), "utf8");
      expect(cto).toContain("name: soleur-engineering-cto\n");
      expect(cto).toContain("Read `agents/engineering/cto.md`, relative to the plugin root.");
      expect(cto).not.toContain("spawn_subagent");
      expect(cto).not.toContain("GROK_STUB_SPAWN_RULE");
      expect(frontmatter(cto).description).toBe("Use soleur:finance:cfo.");
      const bare = readFileSync(join(root, "cursor/agents/soleur-bare.md"), "utf8");
      expect(bare).not.toContain("description:");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("a deleted stub makes --check exit non-zero and name the path", () => {
    const root = fixture();
    try {
      expect(writeCursorNameMap(root)).toEqual([]);
      rmSync(join(root, "cursor/skills/go/SKILL.md"));
      const proc = runCheck(root);
      const output = combined(proc);
      expect(proc.exitCode).not.toBe(0);
      expect(output).toContain("MISSING: cursor/skills/go/SKILL.md");
      expect(output).not.toContain("cursor-name-map ok");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("a hand-edited stub is drift, so a checker that does not read the tree fails this test", () => {
    const root = fixture();
    try {
      expect(writeCursorNameMap(root)).toEqual([]);
      const path = join(root, "cursor/skills/sync/SKILL.md");
      writeFileSync(path, readFileSync(path, "utf8").replace("name: sync", "name: soleur-sync"));
      const proc = runCheck(root);
      const output = combined(proc);
      expect(proc.exitCode).not.toBe(0);
      expect(output).toContain("DRIFT: cursor/skills/sync/SKILL.md");
      expect(output).not.toContain("cursor-name-map ok");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("a rewritten read target and an extra stub are named", () => {
    const root = fixture();
    try {
      expect(writeCursorNameMap(root)).toEqual([]);
      const path = join(root, "cursor/skills/sync/SKILL.md");
      writeFileSync(path, readFileSync(path, "utf8").replace("Read `commands/sync.md`", "Read `skills/sync/SKILL.md`"));
      const drift = runCheck(root);
      expect(drift.exitCode).toBe(1);
      expect(combined(drift)).toContain("DRIFT: cursor/skills/sync/SKILL.md");
      expect(combined(drift)).not.toContain("cursor-name-map ok");

      expect(writeCursorNameMap(root)).toEqual([]);
      const extraDir = join(root, "cursor/skills/soleur-stale");
      mkdirSync(extraDir, { recursive: true });
      writeFileSync(join(extraDir, "SKILL.md"), "stale\n");
      const extra = runCheck(root);
      expect(extra.exitCode).toBe(1);
      expect(combined(extra)).toContain("EXTRA: cursor/skills/soleur-stale/SKILL.md");
      expect(combined(extra)).not.toContain("cursor-name-map ok");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("a directory extra is reported and does not throw", () => {
    const root = fixture();
    try {
      expect(writeCursorNameMap(root)).toEqual([]);
      const nested = join(root, "cursor/agents/nested-extra");
      mkdirSync(nested, { recursive: true });
      writeFileSync(join(nested, "child.md"), "extra\n");
      expect(writeCursorNameMap(root)).toEqual(["EXTRA: cursor/agents/nested-extra"]);
      expect(existsSync(join(nested, "child.md"))).toBe(true);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("operator-typed frontmatter is copied onto the stub", () => {
    const root = fixture();
    try {
      const dir = join(root, "skills", "flag-delete");
      mkdirSync(dir, { recursive: true });
      writeFileSync(
        join(dir, "SKILL.md"),
        "---\nname: x\ndescription: \"Delete a flag.\"\ndisable-model-invocation: true\n---\n\nbody\n",
      );
      expect(writeCursorNameMap(root)).toEqual([]);
      const stub = readFileSync(join(root, "cursor/skills/soleur-flag-delete/SKILL.md"), "utf8");
      expect(stub).toContain("disable-model-invocation: true");
      expect(stub).toContain("does not block a commit");
      expect(stub).toContain("does not classify the session as cursor");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("a new canonical skill is missing until regenerate, and go stays unprefixed", () => {
    const root = fixture();
    try {
      expect(writeCursorNameMap(root)).toEqual([]);
      writeSkill(root, "extra", "An extra skill.");
      const before = runCheck(root);
      expect(before.exitCode).not.toBe(0);
      expect(combined(before)).toContain("MISSING: cursor/skills/soleur-extra/SKILL.md");
      expect(writeCursorNameMap(root)).toEqual([]);
      const after = runCheck(root);
      expect(after.exitCode).toBe(0);
      expect(after.stdout.toString().trim()).toBe("cursor-name-map ok");
      expect(existsSync(join(root, "cursor/skills/go/SKILL.md"))).toBe(true);
      expect(existsSync(join(root, "cursor/skills/soleur-go/SKILL.md"))).toBe(false);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("two sources that share one output name fail check", () => {
    const root = mkdtempSync(join(tmpdir(), "soleur-cursor-collide-"));
    try {
      mkdirSync(join(root, "skills"), { recursive: true });
      writeSkill(root, "engineering-cto", "A skill.");
      writeAgent(root, "engineering/cto.md", "An agent.");
      const named = runCheck(root);
      const namedOutput = combined(named);
      expect(named.exitCode).not.toBe(0);
      expect(namedOutput).toContain("skills/engineering-cto/SKILL.md");
      expect(namedOutput).toContain("agents/engineering/cto.md");
      expect(namedOutput).not.toContain("cursor-name-map ok");

      const paths = mkdtempSync(join(tmpdir(), "soleur-cursor-path-"));
      mkdirSync(join(paths, "skills"), { recursive: true });
      writeAgent(paths, "a/b-c.md", "one");
      writeAgent(paths, "a-b/c.md", "two");
      const pathProc = runCheck(paths);
      const pathOutput = combined(pathProc);
      expect(pathProc.exitCode).not.toBe(0);
      expect(pathOutput).toContain("agents/a/b-c.md");
      expect(pathOutput).toContain("agents/a-b/c.md");
      expect(pathOutput).not.toContain("cursor-name-map ok");
      rmSync(paths, { recursive: true, force: true });
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("the spelling function used by the stubs does not prefix go or sync", () => {
    expect(cursorSkillSlash("go")).toBe("/go");
    expect(cursorSkillSlash("sync")).toBe("/sync");
    expect(cursorSkillSlash("help")).toBe("/soleur-help");
    expect(cursorSkillSlash("plan")).toBe("/soleur-plan");
    expect(cursorSkillSlash("review")).toBe("/soleur-review");
  });
});

describe("committed cursor name map", () => {
  test("the canonical walk has no collisions and check prints cursor-name-map ok", () => {
    const built = buildCursorNameMap(pluginRoot);
    expect(built.problems).toEqual([]);
    expect(built.files.has("cursor/skills/go/SKILL.md")).toBe(true);
    expect(built.files.has("cursor/skills/soleur-help/SKILL.md")).toBe(true);
    expect(built.files.has("cursor/skills/help/SKILL.md")).toBe(false);
    expect(built.files.has("cursor/agents/soleur-engineering-cto.md")).toBe(true);
    expect(cursorNameMapProblems(pluginRoot)).toEqual([]);
    const proc = runCheck(pluginRoot);
    expect(proc.stderr.toString()).toBe("");
    expect(proc.stdout.toString().trim()).toBe("cursor-name-map ok");
    expect(proc.exitCode).toBe(0);
  });

  test("copied descriptions keep colons inside a quoted scalar", () => {
    const stub = readFileSync(join(pluginRoot, "cursor/agents/soleur-sales-cro.md"), "utf8");
    const canonical = readFileSync(join(pluginRoot, "agents/sales/cro.md"), "utf8");
    const line = stub.split("\n").find((entry) => entry.startsWith("description: "));
    expect(line?.startsWith('description: "')).toBe(true);
    expect(line).toContain("soleur:finance:cfo");
    expect(frontmatter(stub).description).toBe(frontmatter(canonical).description);
    expect(stub).toContain("Read `agents/sales/cro.md`, relative to the plugin root.");
    expect(stub).not.toContain("spawn_subagent");
  });
});
