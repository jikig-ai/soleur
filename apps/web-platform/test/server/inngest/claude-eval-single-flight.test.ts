// #8611 Guard 1 — at most one live Claude child per (cronName, runId), however many times Inngest
// re-invokes the step. A retry that arrives while the first child is still running must JOIN that
// child, never spawn a second paid session (the Cloudflare-524 double-run, 51% of cron spend).
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { fallbackMock } = vi.hoisted(() => ({ fallbackMock: vi.fn() }));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: fallbackMock,
}));
// No database in this suite: the run-progress heartbeat is irrelevant to the single-flight property.
vi.mock("@/server/inngest/routine-run-progress", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/inngest/routine-run-progress")>()),
  upsertRoutineRunProgress: vi.fn(async () => {}),
  heartbeatRoutineRunProgress: vi.fn(async () => {}),
}));
vi.mock("@/server/claude-cost-marker", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/claude-cost-marker")>()),
  emitClaudeCostMarker: vi.fn(),
}));

import {
  SETTLED_TTL_MS,
  spawnClaudeEval,
} from "@/server/inngest/functions/_cron-claude-eval-substrate";

const noopLogger = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } as never;
const RUN_A = "01M37EZCXEGGSDCC428M9N8MYX"; // Inngest ULID shape
const RUN_B = "01M37EZCXEV1W8N02HF26QNJ5N";
const ORIGINAL_CLAUDE_BIN = process.env.CLAUDE_BIN;
const tmpDirs: string[] = [];

// A fake `claude` that appends one line per SPAWN to a counter file, holds for `holdMs` so a
// second call lands while it is live, then prints a result event and exits `code`.
function installFakeClaude(holdMs: number, code = 0): { spawnCwd: string; counter: string } {
  const dir = mkdtempSync(join(tmpdir(), "claude-single-flight-"));
  tmpDirs.push(dir);
  const counter = join(dir, "spawns.log");
  writeFileSync(counter, "");
  const result = JSON.stringify({ type: "result", subtype: "success", is_error: false, result: "ok", total_cost_usd: 0.01 });
  const bin = join(dir, "claude");
  writeFileSync(
    bin,
    `#!/usr/bin/env node
require("fs").appendFileSync(${JSON.stringify(counter)}, "spawn\\n");
setTimeout(() => { process.stdout.write(${JSON.stringify(result)} + "\\n"); process.exit(${code}); }, ${holdMs});
`,
  );
  chmodSync(bin, 0o755);
  process.env.CLAUDE_BIN = bin;
  const spawnCwd = join(dir, "repo");
  mkdirSync(spawnCwd, { recursive: true });
  return { spawnCwd, counter };
}

const spawns = (counter: string) => readFileSync(counter, "utf8").split("\n").filter(Boolean).length;

function run(spawnCwd: string, cronName: string, runId: string | undefined) {
  return spawnClaudeEval({
    spawnCwd,
    installationToken: "ghs_FAKEtoken0123456789ABCDEFghijklmnop",
    flags: ["--print"],
    prompt: "ignored",
    maxTurnDurationMs: 10_000,
    cronName,
    buildSpawnEnv: () => process.env,
    logger: noopLogger,
    runId,
    attempt: 1,
  });
}

beforeEach(() => {
  fallbackMock.mockReset();
  // #8611 — the single-flight map keeps settled results for SETTLED_TTL_MS; start every test empty.
  (globalThis as unknown as Record<symbol, Map<string, unknown> | undefined>)[Symbol.for("soleur.claudeEvalInFlight")]?.clear();
});
afterEach(() => {
  if (ORIGINAL_CLAUDE_BIN === undefined) delete process.env.CLAUDE_BIN;
  else process.env.CLAUDE_BIN = ORIGINAL_CLAUDE_BIN;
  for (const d of tmpDirs.splice(0)) rmSync(d, { recursive: true, force: true });
});

describe("spawnClaudeEval single-flight — #8611 Guard 1", () => {
  it("row 1: a second call with the same (cron, runId) while the first is live JOINS it — one spawn", async () => {
    const { spawnCwd, counter } = installFakeClaude(400);
    const [a, b] = await Promise.all([run(spawnCwd, "cron-x", RUN_A), run(spawnCwd, "cron-x", RUN_A)]);
    expect(spawns(counter)).toBe(1);
    expect(b).toEqual(a);
    expect(fallbackMock.mock.calls.some((c) => c[1]?.op === "claude-eval-singleflight-join")).toBe(true);
  });

  it("row 5: same runId, different cron — distinct keys, two spawns", async () => {
    const { spawnCwd, counter } = installFakeClaude(200);
    await Promise.all([run(spawnCwd, "cron-x", RUN_A), run(spawnCwd, "cron-y", RUN_A)]);
    expect(spawns(counter)).toBe(2);
  });

  it("row 6: a retry just after the child settled (even non-zero) gets that result, not a new session", async () => {
    // The step stream can drop after the child finished but before Inngest read the result.
    const { spawnCwd, counter } = installFakeClaude(50, 1);
    const first = await run(spawnCwd, "cron-x", RUN_B);
    const retry = await run(spawnCwd, "cron-x", RUN_B);
    expect(spawns(counter)).toBe(1);
    expect(retry).toBe(first);
  });

  it("row 9: once SETTLED_TTL_MS has passed, the same key spawns afresh", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval"] });
    try {
      const RUN_C = "01M37EZCXF0000000000000000";
      const { spawnCwd, counter } = installFakeClaude(50, 0);
      await run(spawnCwd, "cron-x", RUN_C);
      vi.advanceTimersByTime(SETTLED_TTL_MS - 1);
      await run(spawnCwd, "cron-x", RUN_C);
      expect(spawns(counter)).toBe(1);
      vi.advanceTimersByTime(2);
      await run(spawnCwd, "cron-x", RUN_C);
      expect(spawns(counter)).toBe(2);
    } finally {
      vi.useRealTimers();
    }
  });

  it("row 7: an undefined or non-ULID runId never joins — two spawns, two reports", async () => {
    const { spawnCwd, counter } = installFakeClaude(300);
    await Promise.all([run(spawnCwd, "cron-x", undefined), run(spawnCwd, "cron-x", "not-a-ulid")]);
    expect(spawns(counter)).toBe(2);
    expect(fallbackMock.mock.calls.filter((c) => c[1]?.op === "claude-eval-singleflight-no-runid")).toHaveLength(2);
  });

  it("row 8: a call that throws before spawning (missing cwd) clears its entry — the next call spawns", async () => {
    const { spawnCwd, counter } = installFakeClaude(50);
    await expect(run(join(spawnCwd, "gone"), "cron-x", RUN_A)).rejects.toThrow(/no longer exists/);
    await run(spawnCwd, "cron-x", RUN_A);
    expect(spawns(counter)).toBe(1);
  });
});

// Guard 1 rows 3/4 (only the substrate may spawn Claude) live in ONE place:
// cron-claude-eval-mcp-flags.test.ts ("resolveClaudeBin() is referenced ONLY in the substrate").
