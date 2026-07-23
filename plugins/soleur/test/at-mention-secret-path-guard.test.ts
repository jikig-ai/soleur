import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
  existsSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";

// Guard for the `@file`-auto-attach secret-leak footgun.
//
// Claude Code scans user-turn content (which includes a skill/agent/command
// BODY at load time) for `@<path>` mentions and reads the referenced file into
// model context. A documentation example that quotes an `@`-prefixed REAL path
// (e.g. the curl `@file` upload form pointing at `~/.doppler/.doppler.yaml`)
// therefore leaks the operator's live secret on every load. This suite pins the
// guard script that prevents that regression.
//
// The dangerous literal is never written adjacently in this file — it is built
// via string concatenation (`AT + "~/…"`) so the guard cannot flag its own test
// and so loading this file could never re-trigger the footgun.

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const GUARD_SH = resolve(
  REPO_ROOT,
  "plugins/soleur/scripts/lint-at-mention-secret-paths.sh",
);
const PREFLIGHT_MD = resolve(
  REPO_ROOT,
  "plugins/soleur/skills/preflight/SKILL.md",
);

const AT = "@"; // never adjacent-literal a real path in this source file

function run(root: string): { code: number; stdout: string; stderr: string } {
  const r = Bun.spawnSync(["bash", GUARD_SH, root], {
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    code: r.exitCode ?? -1,
    stdout: r.stdout.toString(),
    stderr: r.stderr.toString(),
  };
}

function sandbox(files: Record<string, string>): string {
  const dir = mkdtempSync(join(tmpdir(), "at-mention-guard-"));
  Bun.spawnSync(["git", "init", "-q", dir], {
    stdout: "ignore",
    stderr: "ignore",
  });
  for (const [rel, content] of Object.entries(files)) {
    const abs = join(dir, rel);
    mkdirSync(dirname(abs), { recursive: true });
    writeFileSync(abs, content);
  }
  Bun.spawnSync(["git", "-C", dir, "add", "."], {
    stdout: "ignore",
    stderr: "ignore",
  });
  return dir;
}

describe("scaffold", () => {
  test("guard script exists and is the source of truth", () => {
    expect(existsSync(GUARD_SH)).toBe(true);
  });
});

describe("regression — the real repo is clean", () => {
  test("guard passes against the live repo (preflight line 843 fixed)", () => {
    const { code, stdout } = run(REPO_ROOT);
    expect(code).toBe(0);
    expect(stdout).toContain("OK: no dangerous @-real-path mentions");
  });

  test("preflight SKILL.md no longer carries an @-prefixed real secret path", () => {
    const md = readFileSync(PREFLIGHT_MD, "utf8");
    // The pre-fix form was: `@` immediately followed by `~/.doppler/.doppler.yaml`.
    const danger = AT + "~/.doppler";
    expect(md.includes(danger)).toBe(false);
    // The accepted phrasing keeps the path in a plain code-span, @ detached.
    expect(md).toContain("`~/.doppler/.doppler.yaml` token file");
  });
});

describe("positive — dangerous @-real-path mentions are flagged", () => {
  const cases: Record<string, string> = {
    "home-tilde-doppler": AT + "~/.doppler/.doppler.yaml",
    "abs-home-ssh": AT + "/home/jean/.ssh/id_ed25519",
    "home-var-aws-creds": AT + "$HOME/.aws/credentials",
    "dotenv": AT + "~/app/.env",
  };

  for (const [name, token] of Object.entries(cases)) {
    test(`flags ${name}`, () => {
      const dir = sandbox({
        "plugins/soleur/skills/foo/SKILL.md": `# Foo\n\nExample: curl --data-binary ${token} up\n`,
      });
      try {
        const { code, stdout } = run(dir);
        expect(code).toBe(1);
        expect(stdout).toContain("VIOLATION:");
        expect(stdout).toContain("plugins/soleur/skills/foo/SKILL.md");
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    });
  }
});

describe("negative — safe @-mentions are NOT flagged", () => {
  test("Next.js @/ import aliases and a detached real path pass", () => {
    const detached =
      "the curl `" + AT + "file` form pointing at `~/.doppler/.doppler.yaml`";
    const dir = sandbox({
      "plugins/soleur/skills/foo/SKILL.md": [
        "# Foo",
        "",
        "import x from " + AT + "/server/logger",
        "import y from " + AT + "/lib/api",
        "see " + AT + "types/node and " + AT + "playwright/mcp",
        detached,
      ].join("\n"),
    });
    try {
      const { code, stdout } = run(dir);
      expect(code).toBe(0);
      expect(stdout).toContain("OK: no dangerous");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
