import { describe, it, expect } from "vitest";

import {
  CREDENTIALS_PROMPT_DIRECTIVE,
  buildSoleurGoSystemPrompt,
} from "@/server/soleur-go-runner";

// W1 (#9601, ADR-272). The Anthropic credential is unset for sandboxed Bash on
// BOTH hosted entry paths, so both system-prompt builders carry one directive:
// without it a Concierge agent that finds the variable empty asks the owner to
// paste the key into the chat, where it lands in `messages.body` and the
// transcript. The legacy builder is covered in agent-runner-tools.test.ts.

describe("CREDENTIALS_PROMPT_DIRECTIVE (W1)", () => {
  it("tells the agent not to ask for the credential, and keeps a project's own keys askable", () => {
    expect(CREDENTIALS_PROMPT_DIRECTIVE.startsWith("## Credentials\n")).toBe(true);
    expect(CREDENTIALS_PROMPT_DIRECTIVE).toContain(
      "never ask the user for it or to paste it into the chat",
    );
    expect(CREDENTIALS_PROMPT_DIRECTIVE).toContain(
      "ask for that as you would any project secret",
    );
  });

  it("names no mechanism and claims nothing about which other credentials the shell sees", () => {
    for (const forbidden of [
      /withheld/i,
      /by design/i,
      /sandbox/i,
      /only credentials/i,
      /connected services/i,
      /environment variable/i,
    ]) {
      expect(CREDENTIALS_PROMPT_DIRECTIVE).not.toMatch(forbidden);
    }
  });

  it("is in the Concierge router baseline prompt (the cc path)", () => {
    expect(buildSoleurGoSystemPrompt()).toContain(CREDENTIALS_PROMPT_DIRECTIVE);
  });
});
