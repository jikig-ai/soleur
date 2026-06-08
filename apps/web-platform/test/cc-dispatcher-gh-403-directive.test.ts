/**
 * AC5 (feat-one-shot-concierge-gh-403): the Concierge system prompt carries a
 * directive forbidding speculation about missing scopes/permissions on a `gh`
 * 403, and forbidding "change GitHub App permissions / re-consent" advice.
 *
 * cc-dispatcher's prompt assembly lives deep in a per-dispatch factory that is
 * impractical to invoke in a unit test, so per AC5's own framing this is a
 * source-presence check: the directive constant exists with the load-bearing
 * prohibitions AND is unconditionally appended to `effectiveSystemPrompt`.
 */
import { describe, test, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const SRC = readFileSync(
  join(__dirname, "..", "server", "cc-dispatcher.ts"),
  "utf8",
);

describe("Concierge gh-403 prompt directive (AC5)", () => {
  test("directive forbids scope speculation and re-consent advice", () => {
    const idx = SRC.indexOf("GH_403_PROMPT_DIRECTIVE =");
    expect(idx, "GH_403_PROMPT_DIRECTIVE constant must exist").toBeGreaterThan(
      -1,
    );
    // The directive body (the assigned string literal) must carry the
    // prohibitions. Scope to a window after the assignment.
    // Match tokens independently — the directive is a multi-line string
    // concatenation (`" +\n  "`), so adjacent-word regexes are brittle.
    const body = SRC.slice(idx, idx + 1200);
    expect(body).toMatch(/speculate/i);
    expect(body).toMatch(/re-consent/i);
    expect(body).toMatch(/change GitHub App permissions/i);
  });

  test("directive is appended unconditionally to effectiveSystemPrompt", () => {
    expect(SRC).toMatch(
      /effectiveSystemPrompt\s*\+=\s*`\\n\\n\$\{GH_403_PROMPT_DIRECTIVE\}`/,
    );
  });

  // AC6 (feat-one-shot-concierge-gh-403-self-heal, Bug C): the directive used to
  // forbid re-consent advice and then immediately sanction *"if the 403 persists
  // across retries, ask the user to confirm the Soleur GitHub App is installed"* —
  // the precise message the screenshot reported, contradicting its own prohibition
  // and sending a non-technical user down a dead-end re-consent path. The fix
  // deletes that escape-hatch clause. Negative-match on single-string-segment
  // phrases (the directive is a `" +\n  "` concatenation; the obvious phrase
  // "confirm the Soleur GitHub App is installed" is split across the segment
  // boundary and would false-negative — see plan AC6).
  test("AC6: directive does NOT offer the install-confirmation escape hatch", () => {
    const idx = SRC.indexOf("GH_403_PROMPT_DIRECTIVE =");
    const body = SRC.slice(idx, idx + 1200);
    expect(body).not.toMatch(/sanctioned next step/i);
    expect(body).not.toMatch(/persists across retries/i);
  });
});
