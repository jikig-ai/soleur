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
 * `.git` presence check), fed only the CC_GITHUB_NAME_RE-validated bindings.
 */
import { describe, test, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const SRC = readFileSync(
  join(__dirname, "..", "server", "cc-dispatcher.ts"),
  "utf8",
);

describe("Concierge connected-repo context addendum", () => {
  test("AC1: a connected-repo context builder names the repo and references -R", () => {
    const idx = SRC.indexOf("buildConnectedRepoContext");
    expect(
      idx,
      "buildConnectedRepoContext builder must exist",
    ).toBeGreaterThan(-1);
    // The builder body (window after the definition) names the connected repo
    // and instructs passing `-R owner/repo` using that resolved value.
    const body = SRC.slice(idx, idx + 1200);
    // Lock-step lead phrase with agent-runner.ts:1433.
    expect(body).toMatch(/connected repository is \$\{owner\}\/\$\{repo\}/);
    expect(body).toMatch(/-R \$\{owner\}\/\$\{repo\}/);
  });

  test("AC3/AC5: addendum is appended only inside the connectedOwner && connectedRepo guard", () => {
    // Guard on server-resolved truthiness — NOT existsSync(.git). The append
    // sits immediately inside the guard so it fires on a `.git`-less workspace
    // (the failing case) and is omitted when no repo is connected (byte-parity).
    expect(SRC).toMatch(
      /if \(connectedOwner && connectedRepo\) \{\s*effectiveSystemPrompt\s*\+=\s*`\\n\\n\$\{buildConnectedRepoContext\(connectedOwner, connectedRepo\)\}`;\s*\}/,
    );
  });

  test("AC5: addendum is NOT gated on a .git presence check", () => {
    // The append must not be conditioned on a filesystem `.git` probe.
    const appendIdx = SRC.indexOf(
      "buildConnectedRepoContext(connectedOwner, connectedRepo)",
    );
    expect(appendIdx).toBeGreaterThan(-1);
    const window = SRC.slice(appendIdx - 300, appendIdx);
    expect(window).not.toMatch(/existsSync[\s\S]*\.git/);
  });

  test("AC4: builder is fed only the CC_GITHUB_NAME_RE-validated bindings", () => {
    // Call site passes connectedOwner/connectedRepo (validated at :1330),
    // never raw repoUrl or tool input.
    expect(SRC).toMatch(
      /buildConnectedRepoContext\(connectedOwner, connectedRepo\)/,
    );
    expect(SRC).not.toMatch(/buildConnectedRepoContext\(repoUrl/);
    // Injection-safety comment carried forward from agent-runner.ts:1425-1428.
    const idx = SRC.indexOf("buildConnectedRepoContext");
    const comment = SRC.slice(Math.max(0, idx - 600), idx + 200);
    expect(comment).toMatch(/CC_GITHUB_NAME_RE/);
    expect(comment).toMatch(/injection sink/i);
  });
});
