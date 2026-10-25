// Guard 1 (plan 2026-10-25): every claude-binary spawn made through the cron substrate
// passes the github untrusted-data preamble as a system-prompt append, WITHOUT altering
// the prompt argument.
//
// Why the prompt argument must be untouched: several crons pass a `/soleur:…` slash
// command as the prompt (cron-bug-fixer, cron-nag-4216-readiness, cron-skill-freshness);
// prepending text would stop the CLI recognising the command. The single-flight guard
// also compares prompts, so a rewritten prompt would change its keying.
//
// Separate file from the substrate suite on purpose: the node:child_process mock hoists
// file-wide and would clobber that suite's real-spawn cases (same reason as
// cron-claude-eval-mcp-flags.test.ts).

import { EventEmitter } from "node:events";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.INNGEST_SIGNING_KEY ||= "signkey-test-10194";
  process.env.INNGEST_EVENT_KEY ||= "eventkey-test-10194";
});

const spawnSpy = vi.hoisted(() => vi.fn());
vi.mock("@/server/claude-cost-marker", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/claude-cost-marker")>()),
  emitClaudeCostMarker: vi.fn(),
}));
// No database in this suite: a well-formed runId records run progress, so stub the writers.
vi.mock("@/server/inngest/routine-run-progress", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/inngest/routine-run-progress")>()),
  upsertRoutineRunProgress: vi.fn(async () => {}),
  heartbeatRoutineRunProgress: vi.fn(async () => {}),
  finishRoutineRunProgress: vi.fn(async () => {}),
}));
vi.mock("node:child_process", async (importActual) => {
  const actual = await importActual<typeof import("node:child_process")>();
  return { ...actual, spawn: spawnSpy };
});

import {
  spawnClaudeEval,
  __resetClaudeEvalSingleFlightForTests,
} from "@/server/inngest/functions/_cron-claude-eval-substrate";
import { UNTRUSTED_PREAMBLES } from "@/server/untrusted-content";

const REPO_ROOT = resolve(__dirname, "../../../../..");
// A well-formed Inngest run id (ULID-shaped) takes the single-flight branch.
const GOOD_RUN_ID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";

function makeFakeChild(exitCode = 0) {
  const child = new EventEmitter() as EventEmitter & { stdout: null; stderr: null; pid: number };
  child.stdout = null;
  child.stderr = null;
  child.pid = 4242;
  queueMicrotask(() => child.emit("exit", exitCode, null));
  return child;
}

async function captureArgv(opts: { flags: string[]; prompt: string; runId?: string }) {
  spawnSpy.mockClear();
  await spawnClaudeEval({
    spawnCwd: tmpdir(),
    installationToken: "tok-test",
    flags: opts.flags,
    prompt: opts.prompt,
    maxTurnDurationMs: 60_000,
    cronName: "cron-ux-audit",
    buildSpawnEnv: (token) => ({ PATH: "/usr/bin", NODE_ENV: "test", GH_TOKEN: token }),
    logger: { info: vi.fn(), error: vi.fn(), warn: vi.fn() } as never,
    ...(opts.runId ? { runId: opts.runId, attempt: 0 } : {}),
  });
  expect(spawnSpy).toHaveBeenCalledTimes(1);
  return (spawnSpy.mock.calls[0] as [string, string[]])[1];
}

beforeEach(() => {
  spawnSpy.mockReset();
  spawnSpy.mockImplementation(() => makeFakeChild(0));
  __resetClaudeEvalSingleFlightForTests();
});

describe("cron spawns pass the github preamble as a system-prompt append", () => {
  const BRANCHES: Array<[string, string | undefined]> = [
    ["single-flight (well-formed runId)", GOOD_RUN_ID],
    ["unguarded (no runId)", undefined],
  ];

  it.each(BRANCHES)("%s: --append-system-prompt <preamble> sits before the prompt", async (_n, runId) => {
    const argv = await captureArgv({ flags: ["--print", "--max-turns", "5", "--"], prompt: "do the thing", runId });
    const i = argv.indexOf("--append-system-prompt");
    expect(i).toBeGreaterThanOrEqual(0);
    expect(argv[i + 1]).toBe(UNTRUSTED_PREAMBLES.github);
    // after --strict-mcp-config, before --print and before the trailing prompt
    expect(i).toBeGreaterThan(argv.indexOf("--strict-mcp-config"));
    expect(i).toBeLessThan(argv.indexOf("--print"));
    expect(i + 1).toBeLessThan(argv.length - 1);
  });

  it.each(BRANCHES)("%s: the prompt argument is byte-identical and still last", async (_n, runId) => {
    const argv = await captureArgv({ flags: ["--print", "--"], prompt: "do the thing", runId });
    expect(argv[argv.length - 1]).toBe("do the thing");
    expect(argv.filter((a) => a === "do the thing")).toHaveLength(1);
  });

  it.each(BRANCHES)("%s: a /soleur: slash-command prompt stays command-shaped and last", async (_n, runId) => {
    const prompt = "/soleur:fix-issue 42 --exclude-label ux-audit";
    const argv = await captureArgv({ flags: ["--print", "--"], prompt, runId });
    expect(argv[argv.length - 1]).toBe(prompt);
    expect(argv[argv.length - 1].startsWith("/")).toBe(true);
  });

  it("a differently shaped flags array (allowedTools form) still gets exactly one append", async () => {
    const argv = await captureArgv({
      flags: ["--print", "--allowedTools", "Bash(gh issue view:*),Read", "--max-turns", "3", "--"],
      prompt: "x",
    });
    expect(argv.filter((a) => a === "--append-system-prompt")).toHaveLength(1);
  });
});

describe("the substrate has exactly one claude spawn site", () => {
  it("spawn(claudeBin …) appears once, so the append cannot be bypassed by a second spawner", () => {
    const src = readFileSync(
      resolve(REPO_ROOT, "apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts"),
      "utf8",
    );
    const sites = src.match(/\bspawn\(\s*claudeBin\b/g) ?? [];
    expect(sites).toHaveLength(1);
  });
});
