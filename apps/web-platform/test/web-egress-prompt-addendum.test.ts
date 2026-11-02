import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

// #9545 PR2 — the agent's system-prompt addendum for a web-egress session must not promise logging the audit
// view cannot keep: recording is best-effort, off for most workspaces, and the CLO ruled out "audited". The
// constant is not exported (cc-dispatcher is large), so the assignment is read from source and its string
// literals joined; anchoring on the assignment keeps the comment above it out of the haystack.
const source = readFileSync(join(__dirname, "..", "server", "cc-dispatcher.ts"), "utf8");
const start = source.search(/^const WEB_EGRESS_PROMPT_ADDENDUM =/m);
const end = start === -1 ? -1 : source.indexOf(";\n", start);
const addendum =
  start === -1 || end === -1
    ? ""
    : [...source.slice(start, end).matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => m[1]).join("");

describe("WEB_EGRESS_PROMPT_ADDENDUM", () => {
  it("was found and is a non-trivial string", () => {
    expect(start).toBeGreaterThan(-1);
    expect(addendum.length).toBeGreaterThan(200);
  });

  it("says recording is best-effort and points members at the audit view", () => {
    expect(addendum).toContain("dedicated egress gateway");
    expect(addendum).toContain("may be recorded on a best-effort basis");
    expect(addendum).toContain("Settings > Scope Grants > View egress audit log");
  });

  it("does not promise that every request is logged or call the gateway audited", () => {
    expect(addendum).not.toMatch(/audited gateway|\baudited\b/i);
    expect(addendum).not.toMatch(/every decision is logged|every (outbound )?request is logged/i);
  });
});
