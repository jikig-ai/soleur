// #8611 Guard 1 — at most one live Claude child per (cronName, runId), however many times Inngest
// re-invokes the step. A retry that arrives while the first child is still running must JOIN that
// child, and one that arrives after it finished must get ITS result — never a second paid session
// (the Cloudflare-524 double-run was 51% of cron spend). Also pins the substrate-owned budget flag.
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

const { fallbackMock, warnMock, upsertMock, markerMock } = vi.hoisted(() => ({
  fallbackMock: vi.fn(),
  warnMock: vi.fn(),
  upsertMock: vi.fn(async () => {}),
  markerMock: vi.fn(),
}));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: fallbackMock,
  warnSilentFallback: warnMock,
}));
// No database in this suite: the run-progress writers are counted, not executed.
vi.mock("@/server/inngest/routine-run-progress", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/inngest/routine-run-progress")>()),
  upsertRoutineRunProgress: upsertMock,
  heartbeatRoutineRunProgress: vi.fn(async () => {}),
}));
vi.mock("@/server/claude-cost-marker", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/claude-cost-marker")>()),
  emitClaudeCostMarker: markerMock,
}));

import {
  SETTLED_TTL_MS,
  __resetClaudeEvalSingleFlightForTests,
  spawnClaudeEval,
} from "@/server/inngest/functions/_cron-claude-eval-substrate";
import { CLAUDE_BUDGET_USD } from "@/server/inngest/cron-budgets";

const noopLogger = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } as never;
const RUN_A = "01M37EZCXEGGSDCC428M9N8MYX"; // Inngest ULID shape
const RUN_B = "01M37EZCXEV1W8N02HF26QNJ5N";
const RUN_C = "01M37EZCXF0000000000000000";
// Real budget keys: the substrate derives --max-budget-usd from the cron name and refuses unknown ones.
const CRON_X = "cron-bug-fixer";
const CRON_Y = "cron-roadmap-review";
const ORIGINAL_CLAUDE_BIN = process.env.CLAUDE_BIN;
const tmpDirs: string[] = [];

// A fake `claude` that appends its argv (one JSON line per SPAWN) to a counter file, holds for
// `holdMs` so a second call lands while it is live, then prints a result event and exits `code`.
function installFakeClaude(
  holdMs: number,
  code = 0,
  resultEvent: Record<string, unknown> = { type: "result", subtype: "success", is_error: false, result: "ok", total_cost_usd: 0.01 },
): { spawnCwd: string; counter: string } {
  const dir = mkdtempSync(join(tmpdir(), "claude-single-flight-"));
  tmpDirs.push(dir);
  const counter = join(dir, "spawns.log");
  writeFileSync(counter, "");
  const result = JSON.stringify(resultEvent);
  const bin = join(dir, "claude");
  writeFileSync(
    bin,
    `#!/usr/bin/env node
require("fs").appendFileSync(${JSON.stringify(counter)}, JSON.stringify(process.argv.slice(2)) + "\\n");
setTimeout(() => { process.stdout.write(${JSON.stringify(result)} + "\\n"); process.exit(${code}); }, ${holdMs});
`,
  );
  chmodSync(bin, 0o755);
  process.env.CLAUDE_BIN = bin;
  const spawnCwd = join(dir, "repo");
  mkdirSync(spawnCwd, { recursive: true });
  return { spawnCwd, counter };
}

const argvs = (counter: string): string[][] =>
  readFileSync(counter, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as string[]);
const spawns = (counter: string) => argvs(counter).length;
// A real macrotask turn: the settled-result retention must survive past the promise's own
// microtasks, which a synchronous retry right after `await` would not exercise.
const macrotask = () => new Promise((r) => setTimeout(r, 20));

function run(
  spawnCwd: string,
  cronName: string,
  runId: string | undefined,
  opts: { prompt?: string; flags?: string[] } = {},
) {
  return spawnClaudeEval({
    spawnCwd,
    installationToken: "ghs_FAKEtoken0123456789ABCDEFghijklmnop",
    flags: opts.flags ?? ["--print", "--"],
    prompt: opts.prompt ?? "ignored",
    maxTurnDurationMs: 10_000,
    cronName,
    buildSpawnEnv: () => process.env,
    logger: noopLogger,
    runId,
    attempt: 1,
  });
}

const ops = (m: ReturnType<typeof vi.fn>) => m.mock.calls.map((c) => (c[1] as { op?: string })?.op);

beforeEach(() => {
  fallbackMock.mockReset();
  warnMock.mockReset();
  upsertMock.mockClear();
  markerMock.mockReset();
  // Settled results persist for SETTLED_TTL_MS; start every test empty.
  __resetClaudeEvalSingleFlightForTests();
});
afterEach(() => {
  if (ORIGINAL_CLAUDE_BIN === undefined) delete process.env.CLAUDE_BIN;
  else process.env.CLAUDE_BIN = ORIGINAL_CLAUDE_BIN;
  for (const d of tmpDirs.splice(0)) rmSync(d, { recursive: true, force: true });
});

describe("spawnClaudeEval single-flight — #8611 Guard 1", () => {
  it("row 1: a second call with the same (cron, runId) while the first is live JOINS it — one spawn, one marker, one progress row", async () => {
    const { spawnCwd, counter } = installFakeClaude(400);
    const [a, b] = await Promise.all([run(spawnCwd, CRON_X, RUN_A), run(spawnCwd, CRON_X, RUN_A)]);
    expect(spawns(counter)).toBe(1);
    expect(b).toEqual(a);
    expect(ops(warnMock)).toContain("claude-eval-singleflight-join");
    // The join is an expected path: warning severity, never an error-level report.
    expect(ops(fallbackMock)).not.toContain("claude-eval-singleflight-join");
    expect(markerMock).toHaveBeenCalledTimes(1);
    expect(upsertMock).toHaveBeenCalledTimes(1);
  });

  it("row 5: same runId, different cron — distinct keys, two spawns", async () => {
    const { spawnCwd, counter } = installFakeClaude(200);
    await Promise.all([run(spawnCwd, CRON_X, RUN_A), run(spawnCwd, CRON_Y, RUN_A)]);
    expect(spawns(counter)).toBe(2);
  });

  it("row 6: a retry a macrotask after the child settled (even non-zero) gets that result, not a new session", async () => {
    // The step stream can drop after the child finished but before Inngest read the result.
    const { spawnCwd, counter } = installFakeClaude(50, 1);
    const first = await run(spawnCwd, CRON_X, RUN_B);
    await macrotask();
    const retry = await run(spawnCwd, CRON_X, RUN_B);
    expect(spawns(counter)).toBe(1);
    expect(retry).toBe(first);
    expect(markerMock).toHaveBeenCalledTimes(1);
    expect(upsertMock).toHaveBeenCalledTimes(1);
  });

  it("row 7: an undefined or non-ULID runId never joins — two spawns, two reports", async () => {
    const { spawnCwd, counter } = installFakeClaude(300);
    // 26 chars, starts with 01, but ends in I/L — outside the ULID alphabet.
    const almostUlid = "01M37EZCXEGGSDCC428M9N8MIL";
    await Promise.all([run(spawnCwd, CRON_X, undefined), run(spawnCwd, CRON_X, almostUlid)]);
    expect(spawns(counter)).toBe(2);
    expect(ops(fallbackMock).filter((o) => o === "claude-eval-singleflight-no-runid")).toHaveLength(2);
  });

  it("row 8: a call that throws before spawning (missing cwd) clears its entry — the next call spawns", async () => {
    const { spawnCwd, counter } = installFakeClaude(50);
    await expect(run(join(spawnCwd, "gone"), CRON_X, RUN_A)).rejects.toThrow(/no longer exists/);
    await run(spawnCwd, CRON_X, RUN_A);
    expect(spawns(counter)).toBe(1);
  });

  it("row 9: the settled result is kept up to SETTLED_TTL_MS, then the same key spawns afresh", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval"] });
    try {
      const { spawnCwd, counter } = installFakeClaude(50, 0);
      await run(spawnCwd, CRON_X, RUN_C);
      // Async advance flushes microtasks too, so a retention that were dropped on a microtask
      // (instead of a timer) would already be gone here.
      await vi.advanceTimersByTimeAsync(SETTLED_TTL_MS - 1);
      await run(spawnCwd, CRON_X, RUN_C);
      expect(spawns(counter)).toBe(1);
      await vi.advanceTimersByTimeAsync(2);
      await run(spawnCwd, CRON_X, RUN_C);
      expect(spawns(counter)).toBe(2);
    } finally {
      vi.useRealTimers();
    }
  });

  it("row 10: the retention window outlasts the longest claude-eval run plus a queued retry", () => {
    // MAX_TURN_DURATION_MS tops out at 70 min; a dropped-stream retry can queue behind another
    // claude-eval cron on the shared cron-platform concurrency slot before it runs.
    expect(SETTLED_TTL_MS).toBeGreaterThanOrEqual(2 * 60 * 60_000);
  });

  it("row 11: a second, DIFFERENT spawn in the same run is refused, never handed the first spawn's result", async () => {
    const { spawnCwd, counter } = installFakeClaude(300);
    const first = run(spawnCwd, CRON_X, RUN_A, { prompt: "plan" });
    await expect(run(spawnCwd, CRON_X, RUN_A, { prompt: "execute" })).rejects.toThrow(/second distinct spawn/);
    await first;
    expect(spawns(counter)).toBe(1);
    expect(ops(fallbackMock)).toContain("claude-eval-singleflight-key-collision");
  });
});

describe("spawnClaudeEval budget ceiling — #8611 Fix 3", () => {
  it("passes --max-budget-usd with the cron's own CLAUDE_BUDGET_USD value, once, before the trailing --", async () => {
    const { spawnCwd, counter } = installFakeClaude(20);
    await run(spawnCwd, CRON_Y, RUN_A, { flags: ["--print", "--allowedTools", "Read", "--"] });
    const [argv] = argvs(counter);
    const i = argv!.indexOf("--max-budget-usd");
    expect(i).toBeGreaterThanOrEqual(0);
    expect(argv![i + 1]).toBe(String(CLAUDE_BUDGET_USD[CRON_Y]));
    expect(i).toBeLessThan(argv!.lastIndexOf("--"));
    expect(argv!.filter((a) => a === "--max-budget-usd")).toHaveLength(1);
  });

  it("refuses a caller-supplied --max-budget-usd (the CLI takes the last value, so it could raise the cap)", async () => {
    const { spawnCwd, counter } = installFakeClaude(20);
    await expect(
      run(spawnCwd, CRON_Y, RUN_B, { flags: ["--print", "--max-budget-usd", "999", "--"] }),
    ).rejects.toThrow(/must not carry --max-budget-usd/);
    expect(spawns(counter)).toBe(0);
  });

  it("refuses a cron with no budget entry before spawning or writing anything", async () => {
    const { spawnCwd, counter } = installFakeClaude(20);
    await expect(run(spawnCwd, "cron-not-in-the-table", RUN_B)).rejects.toThrow(/no budget/);
    expect(spawns(counter)).toBe(0);
    expect(upsertMock).not.toHaveBeenCalled();
  });
});

describe("spawnClaudeEval result plumbing — #8611 review", () => {
  it("carries the result event's subtype/isError/numTurns onto the SpawnResult (a capped run is classifiable)", async () => {
    const { spawnCwd } = installFakeClaude(20, 0, {
      type: "result", subtype: "error_max_budget_usd", is_error: true, num_turns: 9, result: "stopped", total_cost_usd: 4,
    });
    const r = await run(spawnCwd, CRON_X, RUN_A);
    expect(r.subtype).toBe("error_max_budget_usd");
    expect(r.isError).toBe(true);
    expect(r.numTurns).toBe(9);
  });

  it("redacts the operator ANTHROPIC_API_KEY from the child's result text", async () => {
    const key = "sk-ant-api03-FAKEFAKEFAKEFAKEFAKEFAKE0123456789";
    const prev = process.env.ANTHROPIC_API_KEY;
    process.env.ANTHROPIC_API_KEY = key;
    try {
      const { spawnCwd } = installFakeClaude(20, 0, {
        type: "result", subtype: "success", is_error: false, result: `env says ${key}`, total_cost_usd: 0.01,
      });
      const r = await run(spawnCwd, CRON_X, RUN_B);
      expect(r.stdoutTail).toContain("[REDACTED-ANTHROPIC-KEY]");
      expect(r.stdoutTail).not.toContain(key);
    } finally {
      if (prev === undefined) delete process.env.ANTHROPIC_API_KEY;
      else process.env.ANTHROPIC_API_KEY = prev;
    }
  });
});

// Guard 1 rows 3/4 (only the substrate may spawn Claude) live in ONE place:
// cron-claude-eval-mcp-flags.test.ts ("resolveClaudeBin() is referenced ONLY in the substrate").
