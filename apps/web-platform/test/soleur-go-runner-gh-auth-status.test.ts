import { describe, it, expect } from "vitest";

import {
  GH_AUTH_STATUS_GUIDANCE_DIRECTIVE,
  buildSoleurGoSystemPrompt,
} from "@/server/soleur-go-runner";

// Item 2 (plan §Phase 2) — Concierge stops self-blocking on `gh auth status`.
//
// GitHub App *installation* tokens cannot call `GET /user`, which `gh auth
// status` probes — so it ALWAYS reports the token "invalid" even though the
// SAME token works for `gh issue view -R owner/repo`, `gh pr create`, and
// git-over-HTTPS. The agent trusted that false negative and refused to
// proceed. The fix is system-prompt guidance baked into the baseline.
//
// Assertions use paren-safe substrings (no phrase straddles a punctuation
// boundary) per the CI-sentinel Sharp Edge — each anchor is a clean token.

describe("buildSoleurGoSystemPrompt — gh auth status guidance (item 2)", () => {
  it("exports a non-empty GH_AUTH_STATUS_GUIDANCE_DIRECTIVE string", () => {
    expect(typeof GH_AUTH_STATUS_GUIDANCE_DIRECTIVE).toBe("string");
    expect(GH_AUTH_STATUS_GUIDANCE_DIRECTIVE.length).toBeGreaterThan(50);
  });

  it("baseline prompt embeds the directive verbatim", () => {
    expect(buildSoleurGoSystemPrompt()).toContain(
      GH_AUTH_STATUS_GUIDANCE_DIRECTIVE,
    );
  });

  it("directive tells the agent not to self-block on gh auth status", () => {
    // Paren-safe anchor #1.
    expect(GH_AUTH_STATUS_GUIDANCE_DIRECTIVE).toContain("gh auth status");
  });

  it("directive mandates passing -R owner/repo on repo gh operations", () => {
    // Paren-safe anchor #2.
    expect(GH_AUTH_STATUS_GUIDANCE_DIRECTIVE).toContain("-R owner/repo");
  });

  it("baseline prompt itself contains both anchors (integration)", () => {
    const prompt = buildSoleurGoSystemPrompt();
    expect(prompt).toContain("gh auth status");
    expect(prompt).toContain("-R owner/repo");
  });
});
