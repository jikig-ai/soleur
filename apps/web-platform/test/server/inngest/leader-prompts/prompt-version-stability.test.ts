/**
 * Sentinel tests for the leader-prompt registry (PR-B #4379 AC2).
 *
 * Asserts:
 *   - Registry covers EXACTLY 5 classes (no more, no less).
 *   - Each module's promptVersion matches v{major}.{minor}.{patch}.
 *   - Each module's tools array is non-empty.
 *   - Each module's systemPrompt enumerates its tool names verbatim
 *     (per learning 2026-05-05-baseline-prompt-must-declare-capabilities-or-model-fabricates-missing-tools.md).
 *   - All modules pin maxTurns + maxTokens to the registry constants.
 *   - SSOT constant `PER_SPAWN_COST_CEILING_CENTS = 260`.
 */

import { describe, it, expect } from "vitest";
import {
  LEADER_PROMPTS,
  PER_SPAWN_COST_CEILING_CENTS,
  LEADER_MAX_TURNS,
  LEADER_MAX_TOKENS,
  SONNET_MODEL,
  HAIKU_MODEL,
  type LeaderActionClass,
} from "@/server/inngest/leader-prompts";

const EXPECTED_CLASSES: LeaderActionClass[] = [
  "engineering.pr_review_pending",
  "engineering.ci_failed",
  "triage.p0p1_issue",
  "security.cve_alert",
  "knowledge.kb_drift",
];

const PROMPT_VERSION_REGEX = /^v\d+\.\d+\.\d+$/;

describe("leader-prompt registry — AC2 sentinels", () => {
  it("covers exactly 5 action classes", () => {
    const keys = Object.keys(LEADER_PROMPTS).sort();
    expect(keys).toEqual([...EXPECTED_CLASSES].sort());
    expect(keys).toHaveLength(5);
  });

  it.each(EXPECTED_CLASSES)(
    "%s — promptVersion matches v{major}.{minor}.{patch}",
    (cls) => {
      const m = LEADER_PROMPTS[cls];
      expect(m.promptVersion).toMatch(PROMPT_VERSION_REGEX);
    },
  );

  it.each(EXPECTED_CLASSES)(
    "%s — tools array is non-empty",
    (cls) => {
      const m = LEADER_PROMPTS[cls];
      expect(m.tools.length).toBeGreaterThan(0);
    },
  );

  it.each(EXPECTED_CLASSES)(
    "%s — systemPrompt enumerates every tool name verbatim",
    (cls) => {
      const m = LEADER_PROMPTS[cls];
      for (const tool of m.tools) {
        expect(m.systemPrompt).toContain(tool.name);
      }
    },
  );

  it.each(EXPECTED_CLASSES)(
    "%s — maxTurns + maxTokens pinned to registry constants",
    (cls) => {
      const m = LEADER_PROMPTS[cls];
      expect(m.maxTurns).toBe(LEADER_MAX_TURNS);
      expect(m.maxTokens).toBe(LEADER_MAX_TOKENS);
    },
  );

  it.each(EXPECTED_CLASSES)(
    "%s — model is one of {Sonnet, Haiku}",
    (cls) => {
      const m = LEADER_PROMPTS[cls];
      expect([SONNET_MODEL, HAIKU_MODEL]).toContain(m.model);
    },
  );

  it("Sonnet-routed classes: pr_review_pending, ci_failed, cve_alert (reasoning-shape)", () => {
    expect(LEADER_PROMPTS["engineering.pr_review_pending"].model).toBe(SONNET_MODEL);
    expect(LEADER_PROMPTS["engineering.ci_failed"].model).toBe(SONNET_MODEL);
    expect(LEADER_PROMPTS["security.cve_alert"].model).toBe(SONNET_MODEL);
  });

  it("Haiku-routed classes: p0p1_issue, kb_drift (classification-shape)", () => {
    expect(LEADER_PROMPTS["triage.p0p1_issue"].model).toBe(HAIKU_MODEL);
    expect(LEADER_PROMPTS["knowledge.kb_drift"].model).toBe(HAIKU_MODEL);
  });

  it("PER_SPAWN_COST_CEILING_CENTS SSOT constant equals 260 ($2.60 USD)", () => {
    // Layer 2 cap (ADR-041), raised from the brainstorm-locked $2.00 by ~30%
    // for the Sonnet 5 tokenizer (see constants.ts rationale).
    expect(PER_SPAWN_COST_CEILING_CENTS).toBe(260);
  });

  it("userPromptTemplate is callable for each class with a minimal ClassInput", () => {
    for (const cls of EXPECTED_CLASSES) {
      const m = LEADER_PROMPTS[cls];
      const out = m.userPromptTemplate({
        actionClass: cls,
        sourceRef: `${cls}-sourceref`,
      });
      expect(typeof out).toBe("string");
      expect(out.length).toBeGreaterThan(0);
    }
  });
});
