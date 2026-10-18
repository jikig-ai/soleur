import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join, resolve } from "path";
import {
  ADAPTER_DIR,
  PLUGIN_ROOT_TOKEN,
  expectedOpenCodeAdapter,
  openCodeAdapterProblems,
  writeOpenCodeAdapter,
} from "../scripts/sync-opencode-adapter";

const pluginRoot = resolve(import.meta.dir, "..");
const script = join(pluginRoot, "scripts/sync-opencode-adapter.ts");

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

function writeAgent(root: string, relpath: string, frontmatter: Record<string, string>, body = "Canonical body.\n"): void {
  const path = join(root, relpath);
  mkdirSync(join(path, ".."), { recursive: true });
  const lines = ["---", ...Object.entries(frontmatter).map(([k, v]) => `${k}: ${JSON.stringify(v)}`), "---", "", body];
  writeFileSync(path, lines.join("\n"));
}

function fixture(): string {
  const root = mkdtempSync(join(tmpdir(), "soleur-opencode-adapter-"));
  // A nested agent (two path segments below `agents/`) — the id must stay the full path.
  writeAgent(root, "agents/engineering/cto.md", {
    name: "cto",
    description: "Cross-cutting technical assessment during feature exploration.",
    model: "inherit",
  });
  writeAgent(root, "agents/product/cpo.md", {
    name: "cpo",
    description: "Owns the product backlog and the roadmap.",
    // A Claude-Code SKU alias. OpenCode model ids are `provider/model`; a bare alias is
    // not resolvable there, so the stub must NOT carry it through.
    model: "sonnet",
  });
  mkdirSync(join(root, "commands"), { recursive: true });
  writeFileSync(
    join(root, "commands", "go.md"),
    "---\ndescription: Route a request down the pipeline\n---\n\nRun the pipeline for $ARGUMENTS.\n",
  );
  return root;
}

describe("opencode adapter drift", () => {
  test("a clean run writes nothing new and --check exits 0", () => {
    const root = fixture();
    try {
      expect(writeOpenCodeAdapter(root)).toEqual([]);
      const proc = runCheck(root);
      expect(proc.exitCode).toBe(0);
      expect(combined(proc)).toContain("opencode-adapter ok");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("a hand-edited stub is drift, so a checker that does not read the tree fails this test", () => {
    const root = fixture();
    try {
      expect(writeOpenCodeAdapter(root)).toEqual([]);
      const path = join(root, ADAPTER_DIR, "agents/engineering/cto.md");
      writeFileSync(path, readFileSync(path, "utf8").replace("mode: subagent", "mode: primary"));
      const proc = runCheck(root);
      const output = combined(proc);
      expect(proc.exitCode).not.toBe(0);
      expect(output).toContain(`DRIFT: opencode/agents/engineering/cto.md`);
      expect(output).not.toContain("opencode-adapter ok");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("a missing stub is named", () => {
    const root = fixture();
    try {
      expect(writeOpenCodeAdapter(root)).toEqual([]);
      rmSync(join(root, ADAPTER_DIR, "agents/product/cpo.md"));
      const proc = runCheck(root);
      const output = combined(proc);
      expect(proc.exitCode).not.toBe(0);
      expect(output).toContain(`MISSING: opencode/agents/product/cpo.md`);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("a canonical agent added after the tree was written is a loss, named by its stub path", () => {
    const root = fixture();
    try {
      expect(writeOpenCodeAdapter(root)).toEqual([]);
      // Regenerating from the canonical tree is what catches an agent added upstream with
      // no stub. A missing-file test alone would pass against a stale tree, so this writes
      // the tree first and then adds the agent.
      writeAgent(root, "agents/finance/controller.md", { name: "controller", description: "Signs off spend." });
      expect(openCodeAdapterProblems(root)).toEqual(["MISSING: opencode/agents/finance/controller.md"]);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("the emitted agent path IS the agent id (OpenCode derives ids from the path)", () => {
    const files = expectedOpenCodeAdapter(fixture());
    expect(files.has("opencode/agents/engineering/cto.md")).toBe(true);
    expect(files.has("opencode/agents/product/cpo.md")).toBe(true);
    // No colon-form or hyphen-form alias: §3.0 measured `name:` is ignored, so an alias
    // would be dead weight a reader could mistake for a second supported id.
    for (const key of files.keys()) {
      if (!key.startsWith("opencode/agents/")) continue;
      expect(key).not.toMatch(/:/);
    }
  });

  test("every stub carries mode: subagent, and never a name: the harness ignores", () => {
    const files = expectedOpenCodeAdapter(fixture());
    const stub = files.get("opencode/agents/engineering/cto.md")!;
    expect(stub).toContain("mode: subagent");
    // Without `mode: subagent` the agent registers as primary and the Task tool cannot
    // reach it (measurement §3.0). `name:` is ignored by this harness, so emitting it
    // would assert an identity the harness does not use.
    expect(stub).not.toMatch(/^name:/m);
    expect(stub).toContain("description:");
  });

  test("a Claude SKU alias in the canonical model never leaks into the stub", () => {
    const files = expectedOpenCodeAdapter(fixture());
    const stub = files.get("opencode/agents/product/cpo.md")!;
    // `model: sonnet` is a Claude Code alias, not an OpenCode `provider/model` id.
    expect(stub).toContain("model: inherit");
    expect(stub).not.toContain("sonnet");
  });

  test("opencode.json declares the skills root and instructions, both rooted on the token", () => {
    const files = expectedOpenCodeAdapter(fixture());
    const config = JSON.parse(files.get("opencode/opencode.json")!);
    expect(config.skills).toEqual([`${PLUGIN_ROOT_TOKEN}/skills`]);
    expect(config.instructions).toEqual([`${PLUGIN_ROOT_TOKEN}/${ADAPTER_DIR}/INSTRUCTIONS.md`]);
  });

  test("a command stub preserves $ARGUMENTS and points at the canonical command", () => {
    const files = expectedOpenCodeAdapter(fixture());
    const stub = files.get("opencode/commands/go.md")!;
    expect(stub).toContain("$ARGUMENTS");
    expect(stub).toContain(`${PLUGIN_ROOT_TOKEN}/commands/go.md`);
  });

  test("no emitted file contains a machine-specific absolute path", () => {
    // The fragment and stubs are committed, so any absolute checkout path would be wrong
    // on every other machine and would make `--check` machine-dependent. The token is the
    // only form that survives a checkout elsewhere; the installer resolves it.
    const files = expectedOpenCodeAdapter(fixture());
    for (const [key, content] of files) {
      expect(content, `${key} leaked an absolute path`).not.toContain(pluginRoot);
    }
  });

  test("the generator is idempotent: a second run is byte-identical", () => {
    const root = fixture();
    try {
      expect(writeOpenCodeAdapter(root)).toEqual([]);
      const first = new Map(
        [...expectedOpenCodeAdapter(root)].map(([key, value]) => [key, readFileSync(join(root, key), "utf8") as string]),
      );
      expect(writeOpenCodeAdapter(root)).toEqual([]);
      for (const [key, expected] of first) {
        expect(readFileSync(join(root, key), "utf8"), `${key} changed on a second run`).toBe(expected);
      }
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("INSTRUCTIONS.md states the bare-skill and path-id routing contract", () => {
    const files = expectedOpenCodeAdapter(fixture());
    const md = files.get(`${ADAPTER_DIR}/INSTRUCTIONS.md`)!;
    expect(md).toContain("Task");
    expect(md).toContain("$ARGUMENTS");
  });
});
