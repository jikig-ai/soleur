import { readFileSync } from "node:fs";
import { describe, expect, test } from "bun:test";

const INSTRUCTIONS = readFileSync(
  `${import.meta.dir}/../devin/INSTRUCTIONS.md`,
  "utf8",
);

describe("devin/INSTRUCTIONS.md subagent routing guidance", () => {
  test("binds each profile to its tool-surface predicate, not just the vocabulary", () => {
    // The contract is the BINDING (profile → constraint), so invert-safety
    // requires the pair inside one ordered match — separate presence pins
    // pass on a full contract inversion.
    expect(INSTRUCTIONS).toMatch(
      /`subagent_explore` — the task needs read\/grep\/glob\/web_search[\s\S]*?NO exec\/git tool\s*and cannot fetch arbitrary URLs/,
    );
    expect(INSTRUCTIONS).toMatch(
      /`subagent_general` — full tool access; always runs on the parent's model/,
    );
    expect(INSTRUCTIONS).toMatch(/Mixed or\s*\n?\s*uncertain → `subagent_general`/);
    // The rule text must not hide inside an HTML comment (M3-class vacuity).
    expect(INSTRUCTIONS).not.toMatch(
      /<!--[\s\S]*?Choose the profile by tool surface/,
    );
  });

  test("documents the agent.subagent_model operator opt-in with its expiry", () => {
    expect(INSTRUCTIONS).toContain("agent.subagent_model");
    expect(INSTRUCTIONS).toContain("swe-2-flash");
    // The promo-expiry caveat is load-bearing — a silent post-promo pin bills
    // invisibly. Pin the date and the re-verify instruction.
    expect(INSTRUCTIONS).toContain("2026-11-30");
    expect(INSTRUCTIONS).toMatch(/re-verify the\s*\n?\s*rate/);
  });

  test("keeps the corrected model-alias claim, both halves", () => {
    expect(INSTRUCTIONS).not.toContain(
      "Claude model aliases are not Devin model identifiers",
    );
    // Claim-scoped negative: a paraphrased false claim fails too.
    expect(INSTRUCTIONS).not.toMatch(
      /model aliases? (are|do) not (resolve|valid|supported)/i,
    );
    // Affirmative half must be present, not just the restriction.
    expect(INSTRUCTIONS).toContain("DO resolve");
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
    // The earlier watch paragraph names the profile inline too.
    expect(INSTRUCTIONS).toMatch(
      /Arm the watch as a background `run_subagent` \(profile `subagent_general`\)/,
    );
  });
});
