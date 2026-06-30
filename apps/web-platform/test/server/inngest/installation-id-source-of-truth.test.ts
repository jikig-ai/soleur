import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// PR-A (#4124) — Sentinel: `installationId` MUST be server-resolved
// inside `agent-on-spawn-requested` keyed by the SERVER-DERIVED `founderId`.
// Post-#5470 (ADR-044) the source of truth is the workspaces install credential
// resolved via `resolveInstallationIdForWorkspace(founderId, …)` — NOT an inline
// `users.github_installation_id` read (the final `it` enforces that swap). The
// event payload type EXPLICITLY OMITS `installationId`; this test enforces the
// runtime counterpart as belt-and-suspenders against the TypeScript guard.
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

  it("PR-B (#4379) deliberately REVERSES PR-A invariant I4: the function opens runWithByokLease for the Anthropic-SDK leader loop", () => {
    // Plan §Reality-Check Findings: "Only invariant I4 ('No Anthropic SDK in
    // PR-A') is deliberately reversed — PR-B introduces the first raw
    // `@anthropic-ai/sdk` call site inside apps/web-platform/server/." The
    // byok-audit-writer-sweep lint covers the cost-writer pairing.
    expect(fnSrc).toMatch(/\brunWithByokLease\s*\(/);
    expect(fnSrc).toMatch(/persistTurnCostAwaitable\s*\(/);
  });

  it("resolves the install via the service-role workspaces resolver, keyed on the server-derived founderId (#5470 / ADR-044)", () => {
    // Post-#5470: the install is no longer read from users.github_installation_id
    // inline; it is resolved from the user's solo workspace via the service-role
    // resolver (workspaces is the post-ADR-044 source of truth). The key is still
    // the SERVER-DERIVED founderId — never a client-supplied id.
    expect(fnSrc).toMatch(/resolveInstallationIdForWorkspace\s*\(/);
    expect(fnSrc).toMatch(/resolveInstallationIdForWorkspace\s*\(\s*founderId\b/);
    // And it no longer reads the install credential from the users table inline.
    expect(fnSrc).not.toMatch(/from\(["']users["']\)/);
  });
});
