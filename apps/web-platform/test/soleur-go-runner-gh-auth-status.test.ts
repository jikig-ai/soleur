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

  // AC2 (feat-one-shot-concierge-workspace-repo-context) — the baseline no
  // longer tells the agent to infer owner/repo from the git origin remote.
  // On a `.git`-less workspace `git config --get remote.origin.url` returns
  // empty, producing the false "no connected git repository" reply. The
  // server-resolved owner/repo (injected per-dispatch by cc-dispatcher) is the
  // authoritative source; the baseline must point at the connected repository
  // named in the agent's context, not a git remote.
  it("directive no longer instructs deriving owner/repo from the git origin remote", () => {
    expect(GH_AUTH_STATUS_GUIDANCE_DIRECTIVE).not.toContain(
      "remote.origin.url",
    );
  });

  it("directive references the connected repository named in the agent context", () => {
    expect(GH_AUTH_STATUS_GUIDANCE_DIRECTIVE).toMatch(
      /connected repository/i,
    );
  });
});
