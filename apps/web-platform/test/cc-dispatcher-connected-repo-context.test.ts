/**
 * feat-one-shot-concierge-workspace-repo-context — the Concierge derives
 * owner/repo from the active workspace instead of inferring it from a git
 * origin remote (which is empty on a `.git`-less workspace, producing the
 * false "no connected git repository" reply).
 *
 * cc-dispatcher's prompt assembly lives deep in a per-dispatch factory that is
 * impractical to invoke in a unit test (same framing as
 * `cc-dispatcher-gh-403-directive.test.ts`), so per AC1's own framing this is a
 * source-presence check: the connected-repo context builder exists naming the
 * repo and referencing `-R`, AND is appended to `effectiveSystemPrompt` only
 * inside the server-resolved `connectedOwner && connectedRepo` guard (NOT a
 * `.git` presence check), fed only the parseConnectedRepo-validated bindings.
 */
import { describe, test, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { buildConnectedRepoContext } from "@/server/cc-dispatcher";

const SRC = readFileSync(
  join(__dirname, "..", "server", "cc-dispatcher.ts"),
  "utf8",
);

// AC1/AC4 are behavioral — assert on the exported builder's OUTPUT, so they
// survive any benign refactor of the call site (rename, reformat, reflow).
// AC3/AC5 prove the WIRING (the builder is appended inside the server-resolved
// guard, not a `.git` probe) via reflow-tolerant source-presence checks — the
// per-dispatch factory is impractical to invoke in a unit test (same framing
// as cc-dispatcher-gh-403-directive.test.ts).
describe("Concierge connected-repo context addendum", () => {
  test("AC1: the builder names the connected repo and instructs -R owner/repo", () => {
    const out = buildConnectedRepoContext("jikig-ai", "soleur");
    // Lock-step lead phrase with agent-runner.ts:1433.
    expect(out).toContain("The connected repository is jikig-ai/soleur");
    expect(out).toContain("-R jikig-ai/soleur");
    // Names the actual values, not a placeholder.
    expect(out).not.toContain("owner/repo");
  });

  test("AC1: the builder tells the agent NOT to infer from a git remote / .git", () => {
    const out = buildConnectedRepoContext("acme", "widgets");
    expect(out).toMatch(/do NOT try to infer/i);
    expect(out).toMatch(/git remote or a \.git directory/);
  });

  test("AC3/AC5: the append is wired inside the connectedOwner && connectedRepo guard (not a .git probe)", () => {
    // Reflow-tolerant: tolerate whitespace/newlines between the guard and the
    // append, but bound the gap so it cannot match across unrelated code. The
    // guard keys on server-resolved truthiness — NOT existsSync('.git').
    expect(SRC).toMatch(
      /if \(connectedOwner && connectedRepo\)\s*\{[\s\S]{0,200}?effectiveSystemPrompt\s*\+=[\s\S]{0,80}?buildConnectedRepoContext\(connectedOwner, connectedRepo\)/,
    );
    // The guard window must not be a filesystem `.git` presence check.
    const guardIdx = SRC.search(/if \(connectedOwner && connectedRepo\)/);
    const appendIdx = SRC.indexOf(
      "buildConnectedRepoContext(connectedOwner, connectedRepo)",
    );
    expect(guardIdx).toBeGreaterThan(-1);
    expect(appendIdx).toBeGreaterThan(guardIdx);
    expect(SRC.slice(guardIdx, appendIdx)).not.toMatch(/existsSync/);
  });

  test("AC4: the call site is fed only the parseConnectedRepo-validated bindings", () => {
    // Passes connectedOwner/connectedRepo (validated before assignment),
    // never raw repoUrl or tool input.
    expect(SRC).toContain(
      "buildConnectedRepoContext(connectedOwner, connectedRepo)",
    );
    expect(SRC).not.toMatch(/buildConnectedRepoContext\(repoUrl/);
    // Injection-safety reasoning carried forward from agent-runner.ts:1425-1428
    // stays adjacent to the builder so a regex relaxation is greppable here.
    // #5388: owner/repo validation moved to the shared `parseConnectedRepo`
    // (github-repo-parse.ts) so the factory + resolveC4Eligible cannot drift.
    const idx = SRC.indexOf("export function buildConnectedRepoContext");
    const comment = SRC.slice(Math.max(0, idx - 800), idx);
    expect(comment).toMatch(/parseConnectedRepo/);
    expect(comment).toMatch(/injection sink/i);
  });
});
