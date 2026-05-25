import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// PR-A (#4124) — Sentinel: `installationId` MUST be server-resolved
// inside `agent-on-spawn-requested` from `users.github_installation_id`
// keyed by the SERVER-DERIVED `founderId`. The event payload type
// EXPLICITLY OMITS `installationId`; this test enforces the runtime
// counterpart as belt-and-suspenders against the TypeScript guard.
//
// Two-layer enforcement (plan AC2):
//   (a) TypeScript: `AgentSpawnRequestedEvent['data']` has no
//       `installationId` field. A consumer reading `event.data.
//       installationId` fails `tsc` at build. Asserted by the negative
//       grep in this file (source-level proxy for the compile gate).
//   (b) Runtime: this sentinel grep — zero matches against any of the
//       drift patterns that would re-introduce client-controlled
//       installation routing.

const FUNCTION_SOURCE = resolve(
  __dirname,
  "../../../server/inngest/functions/agent-on-spawn-requested.ts",
);
const TEMPLATES_SOURCE = resolve(
  __dirname,
  "../../../server/inngest/agent-acknowledgment-templates.ts",
);

// Strengthened per Kieran P1-5: covers the four drift patterns that would
// re-introduce a client-controlled installationId path.
const DRIFT_PATTERNS: RegExp[] = [
  /event\.data\.installationId/,
  /payload\.installationId/,
  /\.data\.installationId/,
  /\binstallationId\b\s*[:=]\s*event/,
];

/**
 * Strips // line comments and block comments so the sentinel greps only
 * the executable surface. The function source's I1..I5 docblock
 * intentionally names the patterns this sentinel rejects ("never read
 * event.data.installationId", "no raw new Octokit", etc.); checking the
 * raw source would false-positive on the documentation that EXPLAINS
 * the rule.
 */
function stripComments(src: string): string {
  // Block comments
  let out = src.replace(/\/\*[\s\S]*?\*\//g, "");
  // Single-line comments (// to end-of-line). Naive but sufficient for
  // a TS source file with no strings containing `//`.
  out = out.replace(/(^|\n)\s*\/\/[^\n]*/g, "$1");
  return out;
}

describe("installation-id source-of-truth sentinel", () => {
  const fnSrcRaw = readFileSync(FUNCTION_SOURCE, "utf8");
  const tplSrcRaw = readFileSync(TEMPLATES_SOURCE, "utf8");
  const fnSrc = stripComments(fnSrcRaw);
  const tplSrc = stripComments(tplSrcRaw);

  it.each(DRIFT_PATTERNS.map((p) => [p.source]))(
    "agent-on-spawn-requested.ts does not match drift pattern %s in executable code",
    (patternSource) => {
      const pattern = new RegExp(patternSource);
      expect(fnSrc).not.toMatch(pattern);
    },
  );

  it.each(DRIFT_PATTERNS.map((p) => [p.source]))(
    "agent-acknowledgment-templates.ts does not match drift pattern %s in executable code",
    (patternSource) => {
      const pattern = new RegExp(patternSource);
      expect(tplSrc).not.toMatch(pattern);
    },
  );

  it("the event payload type explicitly omits the installationId field", () => {
    const m = fnSrc.match(
      /interface\s+AgentSpawnRequestedEvent\s*\{[\s\S]*?data:\s*\{([\s\S]*?)\};\s*\}/,
    );
    expect(m).not.toBeNull();
    const dataBlock = (m![1] ?? "").toLowerCase();
    expect(dataBlock).not.toContain("installationid");
  });

  it("the function routes every Octokit construction through createGitHubAppClient (no probeOctokit, no raw new Octokit in executable code)", () => {
    expect(fnSrc).toMatch(/createGitHubAppClient\s*\(/);
    expect(fnSrc).not.toMatch(/\bprobeOctokit\s*\(/);
    expect(fnSrc).not.toMatch(/\bnew\s+Octokit\s*\(/);
  });

  it("the function does NOT open a BYOK lease in executable code (PR-A makes zero Anthropic SDK calls)", () => {
    expect(fnSrc).not.toMatch(/\brunWithByokLease\s*\(/);
  });

  it("the function reads users.github_installation_id (the source-of-truth column)", () => {
    expect(fnSrc).toMatch(/github_installation_id/);
    expect(fnSrc).toMatch(/from\(["']users["']\)/);
  });
});
