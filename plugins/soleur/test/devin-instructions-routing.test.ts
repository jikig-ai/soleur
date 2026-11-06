import { readFileSync } from "node:fs";
import { describe, expect, test } from "bun:test";

const INSTRUCTIONS = readFileSync(
  `${import.meta.dir}/../devin/INSTRUCTIONS.md`,
  "utf8",
);
const GO_MD = readFileSync(
  `${import.meta.dir}/../commands/go.md`,
  "utf8",
);
const GO_SKILL = readFileSync(
  `${import.meta.dir}/../skills/go/SKILL.md`,
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
    // Claim-scoped negative: the false claim is "aliases don't resolve /
    // aren't Devin model identifiers". Cover paraphrase shapes (never,
    // cannot, aren't, bare not) while sparing true sentences like
    // "aliases are not valid run_subagent arguments".
    expect(INSTRUCTIONS).not.toMatch(
      /model aliases?[^.\n]*(never|cannot|can't|aren't|don't|doesn't|do(es)? not|are not)[^.\n]*(resolve|Devin model identifiers?)/i,
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

  test("the /soleur:go dispatch surfaces carry the profile contract", () => {
    // Devin lines inside go.md teach profile vocabulary, never the stale
    // "with the agent id" arg shape (the Grok bullet at go.md:631 legitimately
    // names "the agent id" for spawn_subagent — scope the negatives).
    expect(GO_MD).toMatch(/Devin CLI[^\n]*subagent_explore[^\n]*subagent_general/);
    expect(GO_MD).not.toMatch(/Devin CLI[^\n]*run_subagent[^\n]*with (the )?agent id/);
    expect(GO_SKILL).toMatch(/run_subagent[^\n]*subagent_explore[^\n]*subagent_general/);
    expect(GO_SKILL).not.toMatch(/run_subagent[^\n]*with the agent id/);
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
