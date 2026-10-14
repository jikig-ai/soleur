import { describe, expect, it } from "vitest";
import { buildSoleurGoSystemPrompt } from "@/server/soleur-go-runner";

describe("buildSoleurGoSystemPrompt — crmLead", () => {
  it("emits the CRO directive and does not dispatch /soleur:go", () => {
    const prompt = buildSoleurGoSystemPrompt({
      persona: "command_center",
      crmLead: true,
    });
    expect(prompt).toContain("You are the CRO for this chat.");
    expect(prompt).not.toContain("Dispatch via the /soleur:go");
  });

  it("keeps Command Center routing when crmLead is unset", () => {
    const prompt = buildSoleurGoSystemPrompt({ persona: "command_center" });
    expect(prompt).toContain("Dispatch via the /soleur:go");
  });
});
