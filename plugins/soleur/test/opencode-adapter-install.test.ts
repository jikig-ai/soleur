import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  PLUGIN_ROOT_TOKEN,
  writeOpenCodeAdapter,
} from "../scripts/sync-opencode-adapter";
import {
  UnparseableConfigError,
  installOpenCodeAdapter,
  installProblems,
} from "../scripts/install-opencode-adapter";

function workspace(): { target: string; checkout: string } {
  const base = mkdtempSync(join(tmpdir(), "soleur-opencode-install-"));
  const target = join(base, "config");
  const checkout = join(base, "checkout");
  mkdirSync(target, { recursive: true });
  // A minimal plugin checkout containing the generator's own inputs, so the install never
  // reads the developer's real `plugins/soleur` tree and stays hermetic.
  mkdirSync(join(checkout, "agents", "engineering"), { recursive: true });
  writeFileSync(
    join(checkout, "agents", "engineering", "cto.md"),
    '---\nname: cto\ndescription: "Cross-cutting technical assessment."\nmodel: inherit\n---\n\nCanonical body.\n',
  );
  mkdirSync(join(checkout, "commands"), { recursive: true });
  writeFileSync(join(checkout, "commands", "go.md"), "---\ndescription: Route\n---\n\nRun $ARGUMENTS.\n");
  mkdirSync(join(checkout, "skills"), { recursive: true });
  writeFileSync(join(checkout, "skills", "plan.md"), "# plan\n");
  // The hook module is a hand-written source file in the generator's namespace, so a checkout
  // without it is not a checkout the generator can call clean. It carries the plugin-root token
  // like every other emitted path.
  mkdirSync(join(checkout, "opencode"), { recursive: true });
  writeFileSync(
    join(checkout, "opencode", "plugin.ts"),
    `const INSTALLED_ROOT = "${PLUGIN_ROOT_TOKEN}";\nexport default { id: "soleur", async setup() {} };\n`,
  );
  expect(writeOpenCodeAdapter(checkout)).toEqual([]);
  return { target, checkout };
}

describe("opencode adapter install", () => {
  test("installs the front door into a config dir with no token left anywhere", () => {
    const { target, checkout } = workspace();
    try {
      const result = installOpenCodeAdapter(target, checkout);
      expect(result.written.length).toBeGreaterThan(0);
      expect(existsSync(join(target, "agents", "engineering", "cto.md"))).toBe(true);
      expect(existsSync(join(target, "commands", "go.md"))).toBe(true);
      const stub = readFileSync(join(target, "agents", "engineering", "cto.md"), "utf-8");
      expect(stub).not.toContain(PLUGIN_ROOT_TOKEN);
      // The stub now names a real path the `subagent` tool can read.
      expect(stub).toContain(join(checkout, "agents/engineering/cto.md"));
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });

  test("skills point at the canonical checkout; no second skill tree is created to drift", () => {
    const { target, checkout } = workspace();
    try {
      installOpenCodeAdapter(target, checkout);
      // Measurement §2.0: skills register through the `skills` key from the canonical tree.
      // Copying them into the config dir would create a second tree with nothing keeping it
      // in step with the first.
      expect(existsSync(join(target, "skills"))).toBe(false);
      const config = JSON.parse(readFileSync(join(target, "opencode.json"), "utf-8"));
      expect(config.skills).toEqual([join(checkout, "skills")]);
      expect(config.instructions).toEqual([join(target, "soleur", "INSTRUCTIONS.md")]);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });

  test("an existing config keeps its keys and its other skill roots", () => {
    const { target, checkout } = workspace();
    try {
      writeFileSync(
        join(target, "opencode.json"),
        `${JSON.stringify({ theme: "tokyonight", skills: ["/home/operator/.local/skills"] }, null, 2)}\n`,
      );
      installOpenCodeAdapter(target, checkout);
      const config = JSON.parse(readFileSync(join(target, "opencode.json"), "utf-8"));
      expect(config.theme).toBe("tokyonight");
      expect(config.skills).toEqual(["/home/operator/.local/skills", join(checkout, "skills")]);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });

  test("a second install is a no-op", () => {
    const { target, checkout } = workspace();
    try {
      expect(installOpenCodeAdapter(target, checkout).written.length).toBeGreaterThan(0);
      expect(installOpenCodeAdapter(target, checkout).written).toEqual([]);
      expect(installProblems(target, checkout)).toEqual([]);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });

  test("the hook module lands in OpenCode's plugin discovery dir with the token resolved", () => {
    const { target, checkout } = workspace();
    try {
      installOpenCodeAdapter(target, checkout);
      // Measurement §6.6: `<configdir>/plugins/*.ts` loads with no config entry, so the module
      // must be there — not inside `soleur/`, which is only an instructions location — and its
      // name carries the namespace so it cannot collide with an operator's own plugin file.
      const module = readFileSync(join(target, "plugins", "soleur-plugin.ts"), "utf-8");
      expect(module).not.toContain(PLUGIN_ROOT_TOKEN);
      // The installed copy sits at `<configdir>/plugins/`, so its own parent is not the
      // checkout: only the resolved token can point at the guard scripts.
      expect(module).toContain(checkout);
      expect(installProblems(target, checkout)).toEqual([]);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });

  test("--check is read-only: it reports the un-installed target without creating it", () => {
    const { target, checkout } = workspace();
    try {
      const problems = installProblems(target, checkout);
      expect(problems.length).toBeGreaterThan(0);
      expect(problems).toContain("MISSING: agents/engineering/cto.md");
      expect(existsSync(join(target, "agents"))).toBe(false);
      expect(existsSync(join(target, "opencode.json"))).toBe(false);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });

  test("--check names a config that drifted away from the install", () => {
    const { target, checkout } = workspace();
    try {
      installOpenCodeAdapter(target, checkout);
      const path = join(target, "agents", "engineering", "cto.md");
      writeFileSync(path, readFileSync(path, "utf-8").replace("mode: subagent", "mode: primary"));
      expect(installProblems(target, checkout)).toEqual(["STALE: agents/engineering/cto.md"]);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });
});

describe("opencode adapter install — an unparseable operator config is refused, not replaced (review fix, 2026-10-19)", () => {
  // The write path used to fold "missing" and "unparseable" into `{}`, so an operator's config
  // with JSONC comments, a syntax error or a torn write was replaced by the fragment alone —
  // every key gone, and the install reported success.
  test("a config with JSONC comments is refused, left byte-for-byte, and nothing else is written", () => {
    const { target, checkout } = workspace();
    try {
      const configPath = join(target, "opencode.json");
      const original = '{\n  // operator comment\n  "theme": "tokyonight"\n}\n';
      writeFileSync(configPath, original);
      expect(() => installOpenCodeAdapter(target, checkout)).toThrow(UnparseableConfigError);
      expect(readFileSync(configPath, "utf-8")).toBe(original);
      expect(existsSync(join(target, "agents"))).toBe(false);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });

  test("the refusal names the path and the remedy", () => {
    const { target, checkout } = workspace();
    try {
      const configPath = join(target, "opencode.json");
      writeFileSync(configPath, "{ not json");
      let message = "";
      try {
        installOpenCodeAdapter(target, checkout);
      } catch (error) {
        message = String(error);
      }
      expect(message).toContain(configPath);
      expect(message).toContain("--force");
      expect(message).toContain("backup");
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });

  test("--force replaces it, and the previous bytes survive in a timestamped backup", () => {
    const { target, checkout } = workspace();
    try {
      const configPath = join(target, "opencode.json");
      const original = "{ not json";
      writeFileSync(configPath, original);
      const result = installOpenCodeAdapter(target, checkout, { force: true });
      expect(result.written).toContain("opencode.json");
      const backups = readdirSync(target).filter((name) => name.startsWith("opencode.json.bak-"));
      expect(backups.length).toBe(1);
      expect(readFileSync(join(target, backups[0]), "utf-8")).toBe(original);
      expect((JSON.parse(readFileSync(configPath, "utf-8")) as { skills: string[] }).skills).toEqual([
        join(checkout, "skills"),
      ]);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });

  test("--check throws rather than mutating an unparseable config", () => {
    const { target, checkout } = workspace();
    try {
      const configPath = join(target, "opencode.json");
      const original = "{ /* comments */ }";
      writeFileSync(configPath, original);
      expect(() => installProblems(target, checkout)).toThrow(UnparseableConfigError);
      expect(readFileSync(configPath, "utf-8")).toBe(original);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });
});

describe("opencode adapter install — stale generated files are swept (review fix, 2026-10-19)", () => {
  test("a stub whose canonical agent no longer exists is EXTRA, then removed on install", () => {
    const { target, checkout } = workspace();
    try {
      installOpenCodeAdapter(target, checkout);
      const canonical = readFileSync(join(target, "agents", "engineering", "cto.md"), "utf-8");
      const stale = join(target, "agents", "engineering", "retired.md");
      writeFileSync(stale, canonical.replace("engineering/cto.md", "engineering/retired.md"));
      expect(installProblems(target, checkout)).toContain("EXTRA: agents/engineering/retired.md");
      const result = installOpenCodeAdapter(target, checkout);
      expect(result.removed).toContain("agents/engineering/retired.md");
      expect(existsSync(stale)).toBe(false);
      expect(installProblems(target, checkout)).toEqual([]);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });

  test("an operator's own command or agent in a shared root is never removed or reported", () => {
    const { target, checkout } = workspace();
    try {
      installOpenCodeAdapter(target, checkout);
      writeFileSync(join(target, "commands", "mine.md"), "---\ndescription: operator's own\n---\n\nDo my thing.\n");
      writeFileSync(
        join(target, "agents", "mine.md"),
        "---\nmode: subagent\ndescription: operator's own\n---\n\nBody.\n",
      );
      const result = installOpenCodeAdapter(target, checkout);
      expect(result.removed).toEqual([]);
      expect(existsSync(join(target, "commands", "mine.md"))).toBe(true);
      expect(existsSync(join(target, "agents", "mine.md"))).toBe(true);
      expect(installProblems(target, checkout)).toEqual([]);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });

  test("a stale file in the exclusive `soleur/` namespace is EXTRA without needing a signature", () => {
    const { target, checkout } = workspace();
    try {
      installOpenCodeAdapter(target, checkout);
      writeFileSync(join(target, "soleur", "old-notes.md"), "anything\n");
      expect(installProblems(target, checkout)).toContain("EXTRA: soleur/old-notes.md");
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });
});

describe("opencode adapter install — vendored payload mode (npm distribution)", () => {
  test("vendorPayload mirrors PAYLOAD_DIRS into <target>/soleur/ and resolves tokens to that durable copy", () => {
    const { target, checkout } = workspace();
    try {
      mkdirSync(join(checkout, "scripts"), { recursive: true });
      writeFileSync(join(checkout, "scripts", "guard.sh"), "#!/usr/bin/env bash\necho ok\n");
      mkdirSync(join(checkout, "hooks"), { recursive: true });
      writeFileSync(join(checkout, "hooks", "hooks.json"), "{}\n");
      mkdirSync(join(checkout, "lib"), { recursive: true });
      writeFileSync(join(checkout, "lib", "helper.ts"), "export const x = 1;\n");
      mkdirSync(join(checkout, ".claude-plugin"), { recursive: true });
      writeFileSync(join(checkout, ".claude-plugin", "plugin.json"), '{"name":"soleur"}\n');

      const result = installOpenCodeAdapter(target, checkout, { vendorPayload: true });
      expect(result.written).toContain("soleur/.soleur-vendored.json");
      expect(result.written).toContain("soleur/skills/plan.md");
      expect(result.written).toContain("soleur/scripts/guard.sh");

      const vendoredRoot = join(target, "soleur");
      const config = JSON.parse(readFileSync(join(target, "opencode.json"), "utf-8"));
      expect(config.skills).toEqual([join(vendoredRoot, "skills")]);

      const stub = readFileSync(join(target, "agents", "engineering", "cto.md"), "utf-8");
      expect(stub).toContain(join(vendoredRoot, "agents/engineering/cto.md"));
      expect(stub).not.toContain(checkout);

      // Even after the ephemeral npx cache (`checkout`) is deleted, `--check` against the
      // vendored root passes and every referenced file still exists on disk.
      rmSync(checkout, { recursive: true, force: true });
      expect(installProblems(target, vendoredRoot)).toEqual([]);
    } finally {
      rmSync(join(target, ".."), { recursive: true, force: true });
    }
  });
});

