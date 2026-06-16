// #5399 AC10 — load-bearing ordering regression guard.
//
// The repo-readiness gate MUST be the FIRST statement of `startAgentSession`,
// ABOVE the supersede-abort (`const existing = getSession(...)`) and ABOVE
// `registerSession(...)`. If a future refactor moves the gate below either,
// a blocked not-ready dispatch would first abort the user's in-flight prior
// session (or register a dangling one) and THEN bail — silently breaking a
// resumable conversation. The behavioral wiring test
// (agent-runner-repo-readiness-gate.test.ts) cannot observe the internal
// session map, so this structural source-order assertion is the only
// mechanical guard for the invariant. Trimmed to the ordering check only
// (the negative space the behavioral suite can't cover); it lives in a
// standalone file because the wiring test mocks `fs`, which would clobber the
// real `readFileSync` this guard needs.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, test, expect } from "vitest";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "../server/agent-runner.ts"), "utf8");

describe("agent-runner — repo-readiness gate ordering (#5399 AC10)", () => {
  test("the gate read precedes getSession and registerSession inside startAgentSession", () => {
    const fnStart = src.indexOf("export async function startAgentSession(");
    expect(fnStart).toBeGreaterThan(-1);

    const idxGate = src.indexOf("await getCurrentRepoStatus(userId)", fnStart);
    const idxSupersede = src.indexOf(
      "const existing = getSession(userId, conversationId, leaderId)",
      fnStart,
    );
    const idxRegister = src.indexOf(
      "registerSession(userId, conversationId, session, leaderId)",
      fnStart,
    );

    // All three anchors must exist within the function.
    expect(idxGate).toBeGreaterThan(fnStart);
    expect(idxSupersede).toBeGreaterThan(fnStart);
    expect(idxRegister).toBeGreaterThan(fnStart);

    // The gate must come first — above both session-mutating statements.
    expect(idxGate).toBeLessThan(idxSupersede);
    expect(idxGate).toBeLessThan(idxRegister);
  });
});
