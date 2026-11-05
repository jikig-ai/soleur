import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, test } from "vitest";

const INSTRUCTIONS = readFileSync(
  resolve(__dirname, "../devin/INSTRUCTIONS.md"),
  "utf8",
);

describe("devin/INSTRUCTIONS.md subagent routing guidance", () => {
  test("routes profiles by tool surface, not by task description", () => {
    expect(INSTRUCTIONS).toContain(
      "Choose the profile by tool surface, not by task description",
    );
    expect(INSTRUCTIONS).toContain("NO exec/git tool");
    expect(INSTRUCTIONS).toContain("cannot fetch arbitrary URLs");
  });

  test("documents the agent.subagent_model operator opt-in", () => {
    expect(INSTRUCTIONS).toContain("agent.subagent_model");
    expect(INSTRUCTIONS).toContain("swe-2-flash");
  });

  test("keeps the corrected model-alias claim", () => {
    expect(INSTRUCTIONS).not.toContain(
      "Claude model aliases are not Devin model identifiers",
    );
    expect(INSTRUCTIONS).toContain("not `run_subagent` arguments");
  });

  test("preserves the sequential-fallback disclosure contract", () => {
    expect(INSTRUCTIONS).toContain("disclose the lack of parallel execution");
    expect(INSTRUCTIONS).toMatch(
      /independent review occurred when it did not/,
    );
  });

  test("poll loops are pinned to subagent_general (they need exec)", () => {
    expect(INSTRUCTIONS).toContain(
      "profile `subagent_general`: the loop needs `exec`",
    );
  });
});
