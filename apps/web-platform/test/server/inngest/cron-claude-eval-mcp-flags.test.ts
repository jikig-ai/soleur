// #5691 — silence-at-source the sporadic cron egress drops to un-enumerated
// plugin-MCP / CC-telemetry hosts. The claude-eval substrate spawns
// `claude --print --plugin-dir plugins/soleur …`, which auto-connects the four
// remote HTTP MCP servers bundled in plugin.json (context7/cloudflare/vercel/
// stripe) at startup — non-essential dials the containment hook denies anyway.
// This file pins the at-source fix:
//   (a) spawnClaudeEval prepends `--strict-mcp-config` (drops the plugin MCP
//       servers) BEFORE `--print`, so it can never land after a trailing `--`
//       prompt separator (obs P2-b: assert POSITION, not mere presence);
//   (b) the spawn env carries CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
//       (kills Claude Code's own non-essential outbound traffic);
//   (c) a structural drift invariant — resolveClaudeBin() may be referenced
//       ONLY in the substrate + the 2 known inline-spawn crons; a NEW inline
//       claude-spawner trips this test (arch P1-2), and those 2 inline crons
//       carry the flag + telemetry env directly (they bypass spawnClaudeEval).
//
// This lives in a SEPARATE file (not cron-claude-eval-substrate.test.ts) on
// purpose: that file deliberately does NOT vi.mock("node:child_process")
// because the mock hoists file-wide and would clobber its real-spawn
// spawnSimple tests (see its header). A spawn spy requires the mock, so it
// must be isolated here.

import { EventEmitter } from "node:events";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { execFileSync } from "node:child_process";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const spawnSpy = vi.hoisted(() => vi.fn());

vi.mock("node:child_process", async (importActual) => {
  const actual = await importActual<typeof import("node:child_process")>();
  return { ...actual, spawn: spawnSpy };
});

import { spawnClaudeEval } from "@/server/inngest/functions/_cron-claude-eval-substrate";

const REPO_ROOT = resolve(__dirname, "../../../../..");

/** Fake child that resolves spawnClaudeEval's promise on the next microtask. */
function makeFakeChild(exitCode = 0) {
  const child = new EventEmitter() as EventEmitter & {
    stdout: null;
    stderr: null;
    pid: number;
  };
  child.stdout = null;
  child.stderr = null;
  child.pid = 4242;
  // Listeners ("exit"/"error") are attached synchronously after spawn() returns
  // in the Promise executor; a microtask fires after that sync stack completes.
  queueMicrotask(() => child.emit("exit", exitCode, null));
  return child;
}

describe("#5691 — spawnClaudeEval at-source egress silencing", () => {
  beforeEach(() => {
    spawnSpy.mockReset();
    spawnSpy.mockImplementation(() => makeFakeChild(0));
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  async function captureSpawn(flags: string[]) {
    await spawnClaudeEval({
      spawnCwd: tmpdir(),
      installationToken: "tok-test",
      flags,
      prompt: "do the thing",
      maxTurnDurationMs: 60_000,
      cronName: "cron-test",
      buildSpawnEnv: (token) => ({ PATH: "/usr/bin", GH_TOKEN: token }),
      // minimal logger
      logger: { info: vi.fn(), error: vi.fn(), warn: vi.fn() } as never,
    });
    expect(spawnSpy).toHaveBeenCalledTimes(1);
    const [, argv, opts] = spawnSpy.mock.calls[0] as [
      string,
      string[],
      { env: NodeJS.ProcessEnv },
    ];
    return { argv, env: opts.env };
  }

  it("prepends --strict-mcp-config BEFORE --print (position-safe vs a trailing -- separator)", async () => {
    // A cron whose flags end with the `--` end-of-options marker (e.g. cron-ux-audit).
    const { argv } = await captureSpawn(["--print", "--max-turns", "60", "--"]);
    const strictIdx = argv.indexOf("--strict-mcp-config");
    const printIdx = argv.indexOf("--print");
    expect(strictIdx).toBeGreaterThanOrEqual(0);
    expect(printIdx).toBeGreaterThanOrEqual(0);
    // Position assertion, not mere presence: strict must precede --print so it
    // can never be appended after a trailing `--` and read as a positional prompt.
    expect(strictIdx).toBeLessThan(printIdx);
  });

  it("sets CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 in the spawn env", async () => {
    const { env } = await captureSpawn(["--print", "--"]);
    expect(env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC).toBe("1");
    // The caller's buildSpawnEnv allowlist is preserved (merged, not replaced).
    expect(env.GH_TOKEN).toBe("tok-test");
  });
});

describe("#5691 — structural drift invariant: resolveClaudeBin() spawn sites", () => {
  it("is referenced ONLY in the substrate + the 2 known inline-spawn crons", () => {
    // A NEW inline claude-spawner (one that does not route through
    // spawnClaudeEval) trips this test, forcing the author to either route it
    // through spawnClaudeEval (auto-inherits --strict-mcp-config + telemetry env)
    // OR add the flag + env and extend the allowed set below. See Phase 5.1
    // follow-up to migrate the 2 inline crons onto the chokepoint.
    const out = execFileSync(
      "git",
      ["grep", "-l", "resolveClaudeBin", "apps/web-platform/server/inngest/functions/"],
      { cwd: REPO_ROOT, encoding: "utf-8" },
    );
    const actual = out.trim().split("\n").sort();
    const expected = [
      "apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts",
      "apps/web-platform/server/inngest/functions/cron-daily-triage.ts",
      "apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts",
    ].sort();
    expect(actual).toEqual(expected);
  });

  const INLINE_CRONS = [
    "apps/web-platform/server/inngest/functions/cron-daily-triage.ts",
    "apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts",
  ];

  it.each(INLINE_CRONS)(
    "%s carries --strict-mcp-config (defense) and the telemetry env",
    (rel) => {
      const src = readFileSync(resolve(REPO_ROOT, rel), "utf-8");
      // --strict-mcp-config is defensive here (these crons pass no --plugin-dir
      // so they make no MCP dial); the telemetry env is their load-bearing fix.
      expect(src).toContain('"--strict-mcp-config"');
      expect(src).toContain('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC');
    },
  );
});
