import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join, resolve } from "path";
import {
  PLUGIN_ROOT_TOKEN,
  writeOpenCodeAdapter,
} from "../scripts/sync-opencode-adapter";
import { installOpenCodeAdapter, installProblems } from "../scripts/install-opencode-adapter";

const pluginRoot = resolve(import.meta.dir, "..");

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
      // The stub now names a real path the Task tool can read.
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
