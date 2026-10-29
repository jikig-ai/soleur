// #11086 (CTO F9): the two permanent auth-failure modules must stay outside the temporary diagnostic, so the #11085 removal
// (which deletes agent-auth-failure.ts, agent-auth-mode.ts and the probe) can never reach product code.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const SERVER = resolve(__dirname, "../server");
const PERMANENT = ["agent-auth-match.ts", "agent-auth-user-message.ts"];
// Any module-loading form: static `from`, bare side-effect `import "x"`, dynamic `import("x")` and `require("x")`.
const loads = (spec: string): RegExp =>
  new RegExp(`(?:from\\s+|import\\s*\\(?\\s*|require\\s*\\(\\s*)["'][^"']*${spec}`);
const FORBIDDEN: Array<[string, RegExp]> = [
  ["agent-auth-failure", loads("agent-auth-failure")],
  ["agent-auth-mode", loads("agent-auth-mode")],
  ["@sentry", loads("@sentry\\/")],
  ["the probe", /createAgentAuthFailureProbe|tapAgentAuthFailure|NOOP_AGENT_AUTH_PROBE/],
  ["observability", loads("[^\"']*\\/observability")],
];

/** Strip comments so a header that DESCRIBES the boundary does not trip it. */
function code(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
}

describe("permanent auth-failure modules stay outside the diagnostic", () => {
  for (const file of PERMANENT) {
    const src = code(readFileSync(resolve(SERVER, file), "utf8"));
    it(`${file} has real code to inspect`, () => {
      expect(src.length).toBeGreaterThan(200);
      expect(src).toMatch(/\bimport\b/);
    });
    for (const [label, pattern] of FORBIDDEN) {
      it(`${file} does not import ${label}`, () => {
        expect(src).not.toMatch(pattern);
      });
    }
  }

  it("agent-auth-user-message imports the matcher from agent-auth-match", () => {
    const src = code(readFileSync(resolve(SERVER, "agent-auth-user-message.ts"), "utf8"));
    expect(src).toMatch(/from\s+["']\.\/agent-auth-match["']/);
  });
});
