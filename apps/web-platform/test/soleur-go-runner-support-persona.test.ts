// buildSoleurGoSystemPrompt support-persona branch (Phase 3.2, ADR-113).
// The append cannot un-say the baseline `/soleur:go` routing line already baked
// into the Command Center prompt (Kieran review #5), so the builder itself must
// emit support routing when persona==="support".

import { describe, it, expect } from "vitest";

import { buildSoleurGoSystemPrompt } from "@/server/soleur-go-runner";
import { SUPPORT_SYSTEM_DIRECTIVE } from "@/server/support-directive";

describe("buildSoleurGoSystemPrompt — persona=support", () => {
  it("does NOT emit the Command Center /soleur:go routing line", () => {
    const p = buildSoleurGoSystemPrompt({ persona: "support" });
    expect(p).not.toMatch(/\/soleur:go/);
    expect(p).not.toMatch(/Command Center router/i);
  });

  it("embeds the support directive (kb-search only, no engineering)", () => {
    const p = buildSoleurGoSystemPrompt({ persona: "support" });
    expect(p).toContain(SUPPORT_SYSTEM_DIRECTIVE);
    expect(p).toMatch(/kb-search/);
  });

  it("ignores artifact / sticky-workflow context for support (leaderless help chat)", () => {
    const p = buildSoleurGoSystemPrompt({
      persona: "support",
      artifactPath: "overview/vision.md",
      activeWorkflow: "one-shot" as never,
    });
    expect(p).not.toMatch(/currently viewing/);
    expect(p).not.toMatch(/workflow is active/);
  });

  it("default (no persona) is unchanged — still the Command Center router", () => {
    const p = buildSoleurGoSystemPrompt();
    expect(p).toMatch(/Command Center router/i);
    expect(p).toMatch(/\/soleur:go/);
  });
});
