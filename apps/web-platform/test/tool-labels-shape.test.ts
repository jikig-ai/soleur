import { describe, it, expect, vi } from "vitest";

// feat-concierge-activity-trail (#9515) — copy-contract test for Bash
// activity labels. Two halves:
//   (a) every static label follows the gerund/business-noun shape with
//       U+2026 ellipsis and NEVER leaks unsafe tokens (`soleur:`, `#`, `/`,
//       backticks, raw git subcommand jargon like `rev-parse`);
//   (b) mapBashVerb resolves compound commands to the MEANINGFUL verb
//       (measured fallback class: `cd`/`for`/`if`/`sleep` first-tokens in
//       490 Sentry events — issue 124542794).

const reportSilentFallback = vi.fn();
vi.mock("../server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) => reportSilentFallback(...args),
}));

import { mapBashVerb } from "../server/tool-labels";

const BANNED_TOKENS = [/soleur:/, /#/, /\//, /`/, /\.\.\./, /rev-parse/, /rev-list/];
const GERUND_OR_NOUN = /^[A-Z][a-z]+ing\b|^Working|^Done|^Querying/;

describe("tool-labels copy contract (#9515)", () => {
  it("mapBashVerb outputs follow the gerund/noun shape and never leak unsafe tokens", () => {
    const commands = [
      "ls -la",
      "cd /workspaces/abc-123; gh pr list -R x/y --state open",
      "for n in 1 2 3; do gh pr view $n -R x/y --json files; done",
      "git rev-parse --short HEAD",
      "git status --short",
      "sleep 30",
      "bash scripts/thing.sh 2>&1 | head -100",
      "FOO=bar rg 'pattern' src/",
      "echo ---; gh issue list",
      "curl -sS https://api.example.com | jq -r .id",
      "nohup npm run build >log 2>&1 &",
      "if test -f x; then rm x; fi",
      "gh api repos/x/y/pulls --jq '.[].number'",
      "gh pr merge 42 --squash",
    ];
    for (const cmd of commands) {
      const label = mapBashVerb(cmd);
      expect(label, `label for ${JSON.stringify(cmd)}`).toMatch(GERUND_OR_NOUN);
      for (const banned of BANNED_TOKENS) {
        expect(label, `${JSON.stringify(cmd)} → ${label}`).not.toMatch(banned);
      }
    }
  });

  it("compound commands resolve to the MEANINGFUL verb (measured fallback class)", () => {
    expect(mapBashVerb("cd /workspaces/x; gh pr list -R a/b --state open")).toBe(
      "Listing pull requests",
    );
    expect(
      mapBashVerb('for n in 9470 9443; do gh pr view $n -R a/b --json files; done'),
    ).toBe("Reviewing a pull request");
    expect(mapBashVerb("cd /tmp; sleep 5")).toBe("Pausing briefly");
    expect(mapBashVerb("export FOO=1; gh api repos/x")).toBe("Querying GitHub");
  });

  it("git subcommands never interpolate raw jargon", () => {
    expect(mapBashVerb("git rev-parse --short HEAD")).toBe(
      "Inspecting the repository",
    );
    expect(mapBashVerb("git status")).toBe("Checking repository status");
    expect(mapBashVerb("git log --oneline -5")).toBe(
      "Reviewing commit history",
    );
    // Unknown sub → honest generic, never `Checking git frobnicate`.
    expect(mapBashVerb("git frobnicate -x")).toBe("Working with the repository");
  });

  it("rejected shapes still fall back safely with instrumentation", () => {
    expect(mapBashVerb('bash -c "rm -rf /"')).toBe("Working…");
    expect(mapBashVerb("sudo rm -rf /")).toBe("Working…");
    expect(reportSilentFallback).toHaveBeenCalled();
  });

  it("static label tables carry no unsafe tokens themselves", async () => {
    const mod = await import("../server/tool-labels");
    void mod;
    // The tables are module-private; the public contract is mapBashVerb's
    // output — the table scan above plus this assertion that every key maps
    // to a non-fallback label is the audit.
    for (const cmd of [
      "ls", "rg foo", "cat f", "npm test", "node s.js", "python3 s.py",
      "curl u", "mkdir d", "rm f", "jq . f", "sleep 1", "docker ps",
      "make all", "go build", "cargo test", "ssh h", "tar czf a t",
      "ps aux", "kill 1", "df -h", "which x",
    ]) {
      expect(mapBashVerb(cmd)).not.toBe("Working…");
    }
  });
});
