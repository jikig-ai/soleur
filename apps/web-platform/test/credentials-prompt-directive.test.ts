import { describe, it, expect } from "vitest";

import {
  CREDENTIALS_PROMPT_DIRECTIVE,
  buildSoleurGoSystemPrompt,
} from "@/server/soleur-go-runner";

// W1 (#9601, ADR-272). The Anthropic credential is unset for sandboxed Bash on
// EVERY hosted entry path, so every system-prompt builder carries one directive:
// without it an agent that finds the variable empty asks the owner to paste the
// key into the chat, where it lands in `messages.body` and the transcript. The
// legacy builder is covered in agent-runner-tools.test.ts.

// The wording is pinned EXACTLY. It is a security prompt: any sentence appended
// (one that names the mechanism, re-permits asking, or names a variable) must be
// a deliberate edit that updates this literal, not a drift a substring test
// would let through.
const EXPECTED =
  "## Credentials\n" +
  "The credential that runs this session is not available in shell commands, and you do not need it: " +
  "never ask the user for it or to paste it into the chat. " +
  "The same goes for any secret a task needs: tell the user where to set it themselves " +
  "(their project's own settings or config), and never ask for the value in the chat.";

const occurrences = (haystack: string, needle: string): number =>
  haystack.split(needle).length - 1;

describe("CREDENTIALS_PROMPT_DIRECTIVE (W1)", () => {
  it("is exactly the reviewed wording", () => {
    expect(CREDENTIALS_PROMPT_DIRECTIVE).toBe(EXPECTED);
  });

  it("never solicits a value in the chat, for the session credential or any other secret", () => {
    expect(CREDENTIALS_PROMPT_DIRECTIVE).toContain("never ask the user for it or to paste it into the chat");
    expect(CREDENTIALS_PROMPT_DIRECTIVE).toContain("never ask for the value in the chat");
    // The loophole the review found: "ask for a key the project needs".
    expect(CREDENTIALS_PROMPT_DIRECTIVE).not.toMatch(/ask for that/i);
  });

  it("names no mechanism and no variable, and claims nothing about other credentials", () => {
    for (const forbidden of [
      /withheld/i,
      /by design/i,
      /sandbox/i,
      /\bunset\b/i,
      /stripped|scrub|denied|hidden/i,
      /only credentials?/i,
      /connected services?/i,
      /environment|\benv\b/i,
      /ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN/,
      /bwrap|namespace|\/proc|parent process/i,
    ]) {
      expect(CREDENTIALS_PROMPT_DIRECTIVE).not.toMatch(forbidden);
    }
  });

  // The three branches of the Concierge builder, each carrying it exactly once:
  // the support persona keeps Bash (kb-search) under the same deny, and the CRM
  // lead is a separate short-circuit that does not reach the baseline.
  it.each([
    ["router baseline", () => buildSoleurGoSystemPrompt()],
    ["support persona", () => buildSoleurGoSystemPrompt({ persona: "support" })],
    ["CRM lead", () => buildSoleurGoSystemPrompt({ crmLead: true })],
  ] as const)("is in the %s prompt exactly once", (_label, build) => {
    expect(occurrences(build(), CREDENTIALS_PROMPT_DIRECTIVE)).toBe(1);
  });
});
