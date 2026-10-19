import { describe, test, expect } from "vitest";
import { patternEscapesWorkspace } from "../server/tool-pattern-checker";

// Glob `pattern` and Grep `glob` are path-bearing but carry no `path` param, so
// extractToolPath() never sees them. An absolute one lists any directory in the
// container (the egress token dir's file NAMES are live gateway credentials).
const TOKEN_GLOB = "/var/lib/soleur/egress-tokens/*";

describe("patternEscapesWorkspace", () => {
  test.each([
    { tool: "Glob", input: { pattern: TOKEN_GLOB }, label: "Glob absolute pattern, no path" },
    { tool: "Glob", input: { pattern: TOKEN_GLOB, path: "/workspaces/user1" }, label: "Glob absolute pattern WITH an in-workspace path" },
    { tool: "Glob", input: { pattern: "~/.claude/**" }, label: "Glob ~ pattern" },
    { tool: "Glob", input: { pattern: "../user2/**" }, label: "Glob leading .. pattern" },
    { tool: "Glob", input: { pattern: "a/../../user2/*" }, label: "Glob embedded .. segment" },
    { tool: "Glob", input: { pattern: "{src,/var/lib/soleur/egress-tokens}/*" }, label: "Glob brace alternative that is absolute" },
    { tool: "Glob", input: { pattern: "src/{x,../../etc}/*" }, label: "Glob brace alternative with .. segment" },
    { tool: "Grep", input: { pattern: "TODO", glob: TOKEN_GLOB }, label: "Grep absolute glob" },
    { tool: "Grep", input: { pattern: "TODO", glob: "~/x/*" }, label: "Grep ~ glob" },
    { tool: "Grep", input: { pattern: "TODO", glob: "../*" }, label: "Grep .. glob" },
    // the escaping alternative FIRST in the braces (a comma-only split misses these)
    { tool: "Glob", input: { pattern: "{/var/lib/soleur/egress-tokens,x}/*" }, label: "Glob brace whose FIRST alternative is absolute" },
    { tool: "Glob", input: { pattern: "{../x,y}/*" }, label: "Glob brace whose FIRST alternative is .." },
    { tool: "Glob", input: { pattern: "!/var/lib/soleur/egress-tokens/*" }, label: "Glob negated absolute pattern" },
    { tool: "Grep", input: { pattern: "x", glob: "*.ts /var/lib/soleur/egress-tokens/*" }, label: "Grep glob with whitespace-separated absolute member" },
    { tool: "Glob", input: { pattern: "a".repeat(4097) }, label: "Glob pattern over the 4096-char cap (fail closed, no legitimate glob is that long)" },
  ])("flags $label", ({ tool, input }) => {
    expect(patternEscapesWorkspace(tool, input)).toBe(true);
  });

  test.each([
    { tool: "Glob", input: { pattern: "*.ts" }, label: "Glob relative pattern" },
    { tool: "Glob", input: { pattern: "src/**/*.{ts,tsx}" }, label: "Glob relative brace pattern" },
    { tool: "Glob", input: { pattern: "knowledge-base/**/*.md", path: "/workspaces/user1" }, label: "Glob relative pattern with path" },
    { tool: "Grep", input: { pattern: "TODO", path: "/workspaces/user1", glob: "*.ts" }, label: "Grep relative glob" },
    { tool: "Grep", input: { pattern: "/etc/passwd" }, label: "Grep regex that looks like a path (searched CONTENT, not a location)" },
    { tool: "Grep", input: { pattern: "../x" }, label: "Grep regex containing .." },
    { tool: "Grep", input: { pattern: "TODO", glob: "*.{ts,tsx}" }, label: "Grep brace glob" },
    { tool: "Read", input: { file_path: "/workspaces/user1/a.md" }, label: "Read (not a pattern tool)" },
    { tool: "Glob", input: { pattern: "a..b/*.md" }, label: "Glob where .. is part of a name, not a segment" },
    { tool: "constructor", input: { pattern: "/abs" }, label: "an inherited Object key used as a tool name" },
    { tool: "__proto__", input: { pattern: "/abs" }, label: "__proto__ used as a tool name" },
    { tool: "Glob", input: {}, label: "Glob with no pattern" },
    { tool: "Glob", input: { pattern: 42 as unknown as string }, label: "non-string pattern" },
  ])("allows $label", ({ tool, input }) => {
    expect(patternEscapesWorkspace(tool, input)).toBe(false);
  });
});
