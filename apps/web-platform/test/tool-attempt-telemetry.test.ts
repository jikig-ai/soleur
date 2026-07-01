import { describe, test, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// TR3 tool-attempt telemetry collector (#5843, ADR-070 amendment).
//
// The collector is a closure-scoped accumulator + ONE fail-open PreToolUse hook
// + a flush() that inserts ONE aggregated jsonb row per cc conversation-session.
// These tests pin the invariants the plan's ACs depend on:
//   - "unrouted" bucket for tools before the first Skill (HIGH-6)
//   - phase tracked on the PreToolUse(Skill) WAY-IN (off-by-one fix): a routed
//     skill's own subsequent tools attribute to the NEW phase
//   - NO tool_input ever reaches the row (NO-ECHO): only tool NAMES + phase enum
//   - WAL-safe: a whole multi-phase session produces exactly ONE insert (AC4)
//   - fail-open: a forced flush failure never throws + mirrors to Sentry (AC2)
//   - no anonymous-row session_id leak (CRITICAL-2): the inserted row carries
//     only { counts }, never a session/user id

const { mockInsert, mockReportSilentFallback } = vi.hoisted(() => ({
  mockInsert: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({
    from: vi.fn((_table: string) => ({ insert: mockInsert })),
  })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({ warn: vi.fn(), info: vi.fn(), error: vi.fn() }),
}));

import { createToolAttemptCollector } from "@/server/tool-attempt-telemetry";

// Minimal PreToolUse hook input shape. The SDK passes (input, toolUseID, options)
// but the collector reads only input.tool_name / input.tool_input.
function pre(tool_name: string, tool_input: unknown = {}) {
  return { hook_event_name: "PreToolUse", tool_name, tool_input, session_id: "sdk-session-should-never-be-read" };
}

async function fire(hook: ReturnType<typeof createToolAttemptCollector>["preToolUseHook"], input: unknown) {
  // The SDK HookCallback signature is (input, toolUseID, options).
  return hook(input as never, undefined, {} as never);
}

beforeEach(() => {
  mockInsert.mockReset();
  mockInsert.mockResolvedValue({ error: null });
  mockReportSilentFallback.mockReset();
});

describe("createToolAttemptCollector", () => {
  test("tools before the first Skill land in the 'unrouted' bucket", async () => {
    const c = createToolAttemptCollector();
    await fire(c.preToolUseHook, pre("Read"));
    await fire(c.preToolUseHook, pre("Grep"));
    await c.flush();

    expect(mockInsert).toHaveBeenCalledTimes(1);
    const row = mockInsert.mock.calls[0][0];
    expect(row.counts.unrouted).toEqual({ Read: 1, Grep: 1 });
  });

  test("phase is tracked on the Skill WAY-IN: a routed skill's subsequent tools attribute to the NEW phase", async () => {
    const c = createToolAttemptCollector();
    await fire(c.preToolUseHook, pre("Read")); // unrouted
    await fire(c.preToolUseHook, pre("Skill", { skill: "work" })); // -> phase "work"
    await fire(c.preToolUseHook, pre("Bash")); // work
    await fire(c.preToolUseHook, pre("Edit")); // work
    await fire(c.preToolUseHook, pre("Skill", { skill: "review" })); // -> phase "review"
    await fire(c.preToolUseHook, pre("Grep")); // review
    await c.flush();

    const row = mockInsert.mock.calls[0][0];
    expect(row.counts.unrouted).toEqual({ Read: 1, Skill: 1 });
    expect(row.counts.work).toEqual({ Bash: 1, Edit: 1, Skill: 1 });
    expect(row.counts.review).toEqual({ Grep: 1 });
  });

  test("repeated tools within a phase increment the count", async () => {
    const c = createToolAttemptCollector();
    await fire(c.preToolUseHook, pre("Skill", { skill: "work" }));
    await fire(c.preToolUseHook, pre("Bash"));
    await fire(c.preToolUseHook, pre("Bash"));
    await fire(c.preToolUseHook, pre("Bash"));
    await c.flush();
    expect(mockInsert.mock.calls[0][0].counts.work.Bash).toBe(3);
  });

  test("NO tool_input is ever recorded and NO session/user id reaches the row (NO-ECHO + CRITICAL-2)", async () => {
    const c = createToolAttemptCollector();
    await fire(
      c.preToolUseHook,
      pre("Bash", { command: "cat /etc/passwd", secret: "sk-should-never-persist" }),
    );
    await c.flush();

    const row = mockInsert.mock.calls[0][0];
    const serialized = JSON.stringify(row);
    expect(serialized).not.toContain("cat /etc/passwd");
    expect(serialized).not.toContain("sk-should-never-persist");
    expect(serialized).not.toContain("sdk-session-should-never-be-read");
    // The row is exactly { counts }: no id/session/user column.
    expect(Object.keys(row)).toEqual(["counts"]);
  });

  test("an unmapped Skill name does not transition the phase (stays in the prior bucket)", async () => {
    const c = createToolAttemptCollector();
    await fire(c.preToolUseHook, pre("Skill", { skill: "not-a-real-skill" }));
    await fire(c.preToolUseHook, pre("Read"));
    await c.flush();
    const row = mockInsert.mock.calls[0][0];
    expect(row.counts.unrouted).toEqual({ Skill: 1, Read: 1 });
    expect(row.counts.work).toBeUndefined();
  });

  test("WAL-safe: a whole multi-phase session produces exactly ONE insert (AC4)", async () => {
    const c = createToolAttemptCollector();
    for (const t of ["Read", "Grep", "Bash", "Read", "Glob"]) {
      await fire(c.preToolUseHook, pre(t));
    }
    expect(mockInsert).not.toHaveBeenCalled(); // no per-call write
    await c.flush();
    expect(mockInsert).toHaveBeenCalledTimes(1);
  });

  test("an empty session (no tools attempted) inserts NO row", async () => {
    const c = createToolAttemptCollector();
    await c.flush();
    expect(mockInsert).not.toHaveBeenCalled();
  });

  test("fail-open: a forced insert error never throws and mirrors to Sentry (AC2)", async () => {
    mockInsert.mockResolvedValue({ error: { message: "boom", code: "42501" } });
    const c = createToolAttemptCollector();
    await fire(c.preToolUseHook, pre("Read"));
    await expect(c.flush()).resolves.toBeUndefined();
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "tool-attempt-telemetry",
      op: "flush",
    });
  });

  test("fail-open: a thrown insert never throws out of flush", async () => {
    mockInsert.mockRejectedValue(new Error("network down"));
    const c = createToolAttemptCollector();
    await fire(c.preToolUseHook, pre("Read"));
    await expect(c.flush()).resolves.toBeUndefined();
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });

  test("fail-open: a malformed hook input never throws out of the hook", async () => {
    const c = createToolAttemptCollector();
    await expect(fire(c.preToolUseHook, null)).resolves.toBeDefined();
    await expect(fire(c.preToolUseHook, { tool_name: 123 })).resolves.toBeDefined();
  });
});

describe("migration 118_tool_attempts.sql", () => {
  const migration = readFileSync(
    join(__dirname, "..", "supabase", "migrations", "118_tool_attempts.sql"),
    "utf8",
  );

  test("has NO session/user/conversation id column (CRITICAL-2 anonymity)", () => {
    expect(migration).not.toMatch(/\bsession_id\b\s+(uuid|text)/i);
    expect(migration).not.toMatch(/\buser_id\b\s+uuid/i);
    expect(migration).not.toMatch(/\bconversation_id\b\s+uuid/i);
  });

  test("enables RLS with no policies (service-role-only)", () => {
    expect(migration).toMatch(/ENABLE ROW LEVEL SECURITY/);
    expect(migration).not.toMatch(/CREATE POLICY/);
  });

  test("schedules a 90-day pg_cron purge, guarded by unschedule-before-schedule", () => {
    expect(migration).toMatch(/cron\.schedule\(\s*'tool_attempts_retention'/);
    expect(migration).toMatch(/interval '90 days'/);
    expect(migration).toMatch(/cron\.unschedule\('tool_attempts_retention'\)/);
  });
});
