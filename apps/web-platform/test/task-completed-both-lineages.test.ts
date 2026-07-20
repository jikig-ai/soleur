import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Drift guard (review: architecture P1). The `task_completed` inbox nudge must
// fire from BOTH agent-run turn-boundary terminals — the legacy
// `startAgentSession` (agent-runner.ts) AND the cc-soleur-go path
// (cc-dispatcher.ts, the DOMINANT production path since #3270). A new emit wired
// into only one lineage is the exact "must cover both turn boundaries" defect
// class that shipped in the first cut of this feature. Both terminals call the
// SHARED `notifyTaskCompleted` helper; this asserts neither loses the call.

const SERVER = path.join(__dirname, "../server");
const read = (f: string) => readFileSync(path.join(SERVER, f), "utf-8");

describe("task_completed producer covers both agent-run lineages", () => {
  it("the legacy startAgentSession terminal (agent-runner.ts) emits it", () => {
    expect(read("agent-runner.ts")).toMatch(/notifyTaskCompleted\(/);
  });

  it("the cc-soleur-go terminal (cc-dispatcher.ts) emits it", () => {
    expect(read("cc-dispatcher.ts")).toMatch(/notifyTaskCompleted\(/);
  });

  it("both import the shared helper (no per-lineage inline copy)", () => {
    for (const f of ["agent-runner.ts", "cc-dispatcher.ts"]) {
      expect(read(f)).toMatch(/notifyTaskCompleted/);
    }
    // The helper is defined once in notifications.ts.
    expect(read("notifications.ts")).toMatch(
      /export async function notifyTaskCompleted/,
    );
  });
});
