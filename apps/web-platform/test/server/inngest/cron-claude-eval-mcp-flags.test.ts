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

// Importing the 2 inline-cron modules (for their exported CLAUDE_CODE_FLAGS)
// transitively pulls in @/server/inngest/client, whose module-load guard throws
// if INNGEST_SIGNING_KEY/INNGEST_EVENT_KEY are unset (client.ts:31-37). Stub them
// before the static imports execute — vi.hoisted runs ahead of imports. `||=`
// preserves a real Doppler-injected value (webplat shard) and never clobbers it.
// The prod-only INNGEST_DEV guard is skipped under NODE_ENV=test.
vi.hoisted(() => {
  process.env.INNGEST_SIGNING_KEY ||= "signkey-test-5691";
  process.env.INNGEST_EVENT_KEY ||= "eventkey-test-5691";
});

const spawnSpy = vi.hoisted(() => vi.fn());

vi.mock("node:child_process", async (importActual) => {
  const actual = await importActual<typeof import("node:child_process")>();
  return { ...actual, spawn: spawnSpy };
});

import { spawnClaudeEval } from "@/server/inngest/functions/_cron-claude-eval-substrate";
import { CLAUDE_CODE_FLAGS as DAILY_TRIAGE_FLAGS } from "@/server/inngest/functions/cron-daily-triage";
import { CLAUDE_CODE_FLAGS as FOLLOW_THROUGH_FLAGS } from "@/server/inngest/functions/cron-follow-through-monitor";

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
      buildSpawnEnv: (token) => ({ PATH: "/usr/bin", NODE_ENV: "test", GH_TOKEN: token }),
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
    // Assert directly against the documented invariant: the flag must sit before
    // ANY trailing `--` end-of-options marker (the input models a cron whose flags
    // end with `--`), not merely before `--print`.
    expect(strictIdx).toBeLessThan(argv.lastIndexOf("--"));
  });

  it("sets CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 in the spawn env", async () => {
    const { env } = await captureSpawn(["--print", "--"]);
    expect(env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC).toBe("1");
    // The caller's buildSpawnEnv allowlist is preserved (merged, not replaced).
    expect(env.GH_TOKEN).toBe("tok-test");
  });
});

describe("#5691 — structural drift invariant: resolveClaudeBin() spawn sites", () => {
  // SCOPE NOTE (the guard's known limitation): this invariant keys off the
  // `resolveClaudeBin()` helper as the sole sentinel for "an inline claude
  // spawner". It catches a NEW spawner that resolves the binary via that helper,
  // but it does NOT catch a spawner that bypasses the helper — e.g. a raw
  // `spawn("claude", …)` or a hardcoded path. The supplementary assertion below
  // closes the most likely bypass (a literal `spawn("claude"`); a fully bespoke
  // bin-resolver would still slip through. The durable fix is the tracked
  // follow-up: migrate the 2 inline crons onto the spawnClaudeEval chokepoint so
  // the flag+env are inherited and the duplication (hence the drift class)
  // dissolves entirely.
  const ALLOWED = [
    "apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts",
    "apps/web-platform/server/inngest/functions/cron-daily-triage.ts",
    "apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts",
  ].sort();

  it("resolveClaudeBin() is referenced ONLY in the substrate + the 2 known inline crons", () => {
    // A NEW inline claude-spawner that routes through resolveClaudeBin trips this
    // test, forcing the author to either route it through spawnClaudeEval
    // (auto-inherits --strict-mcp-config + telemetry env) or add the flag + env
    // and extend ALLOWED.
    const out = execFileSync(
      "git",
      ["grep", "-l", "resolveClaudeBin", "apps/web-platform/server/inngest/functions/"],
      { cwd: REPO_ROOT, encoding: "utf-8" },
    );
    expect(out.trim().split("\n").sort()).toEqual(ALLOWED);
  });

  it("no functions/ file spawns a literal `claude` binary outside the known set (helper-bypass guard)", () => {
    // Closes the most likely resolveClaudeBin-bypass: a raw spawn("claude", …).
    // `git grep -l` exits 1 (no matches) when clean — tolerate that as the pass.
    let out = "";
    try {
      out = execFileSync(
        "git",
        ["grep", "-lE", 'spawn\\(\\s*"claude"', "apps/web-platform/server/inngest/functions/"],
        { cwd: REPO_ROOT, encoding: "utf-8" },
      );
    } catch {
      out = ""; // rc=1 → no matches
    }
    const offenders = out.trim() ? out.trim().split("\n").filter((f) => !ALLOWED.includes(f)) : [];
    expect(offenders).toEqual([]);
  });

  const INLINE_CRONS: [string, string[]][] = [
    ["cron-daily-triage", DAILY_TRIAGE_FLAGS],
    ["cron-follow-through-monitor", FOLLOW_THROUGH_FLAGS],
  ];

  it.each(INLINE_CRONS)(
    "%s flags carry --strict-mcp-config positioned before --print (defense)",
    (_name, flags) => {
      // --strict-mcp-config is defensive for these crons (they pass no --plugin-dir
      // so they make no MCP dial); structural membership + position, not source text.
      const strictIdx = flags.indexOf("--strict-mcp-config");
      const printIdx = flags.indexOf("--print");
      expect(strictIdx).toBeGreaterThanOrEqual(0);
      expect(printIdx).toBeGreaterThanOrEqual(0);
      expect(strictIdx).toBeLessThan(printIdx);
      // Position-safe vs the trailing `--` end-of-options marker.
      expect(strictIdx).toBeLessThan(flags.lastIndexOf("--"));
    },
  );

  const INLINE_CRON_PATHS = [
    "apps/web-platform/server/inngest/functions/cron-daily-triage.ts",
    "apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts",
  ];

  it.each(INLINE_CRON_PATHS)(
    "%s sets the telemetry env (the load-bearing fix) in buildSpawnEnv",
    (rel) => {
      const src = readFileSync(resolve(REPO_ROOT, rel), "utf-8");
      // Require the assignment form (key + value), NOT a bare key substring — the
      // explanatory comments mention the var name but never the `: "1"` literal,
      // so this cannot pass vacuously off a comment.
      expect(src).toContain('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"');
    },
  );
});
