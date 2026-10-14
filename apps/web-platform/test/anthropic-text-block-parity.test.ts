import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * #8392 — the three TypeScript readers of an Anthropic `content` array must all
 * select the first block whose `type` is `"text"`.
 *
 * Why a SOURCE test and not three behavioural ones: each reader already has its
 * own behavioural case, and a unit test observes a helper — never whether a
 * SECOND copy still agrees with it. `domain-router.ts` keeps a deliberately
 * inlined copy (it must stay off `_cron-shared.ts`'s octokit import graph), so
 * the invariant spans files and nothing but a cross-file assertion can hold it.
 * The prose NOTE that used to carry it is what drifted for ten weeks.
 *
 * Anchored on the SELECTION PREDICATE, not on byte-identity: the copies legitimately
 * differ (`Array.isArray` narrowing, formatting), and forcing them byte-equal would
 * encode the wrong invariant and fail on a cosmetic edit. What may never differ is
 * *selection is by `type === "text"`*.
 *
 * The denylist spelling is asserted ABSENT deliberately: `b.type !== "thinking"`
 * passes every fixture that has only thinking and text blocks, and returns
 * undefined on tool_use / redacted_thinking / server_tool_use — reopening the exact
 * silent-empty class this issue was filed for.
 */
const REPO_ROOT = join(__dirname, "..");

const READERS = [
  { path: "server/inngest/functions/_cron-shared.ts", label: "postAnthropicMessage (shared cron transport)" },
  { path: "server/domain-router.ts", label: "routeMessage classify (inlined leaf-light copy)" },
  { path: "server/email-triage/summarize.ts", label: "email-triage summarize (pre-existing correct reader)" },
] as const;

/** `.content` (optionally chained) → `.find(b => b.type === "text")`, whitespace-tolerant. */
const SELECT_BY_TYPE =
  /\.content\s*\)?\s*\??\.?\s*find\(\s*\(?\s*(\w+)\s*\)?\s*=>\s*\1\.type\s*===\s*"text"\s*\)/;

/** A denylist reader — the mutation that survives a thinking-only fixture set. */
const SELECT_BY_NOT_THINKING = /find\(\s*\(?\s*(\w+)\s*\)?\s*=>\s*\1\.type[^)]*!==\s*"thinking"/;

function sourceOf(rel: string): string {
  // Comments stripped: every assertion below names a literal this file also
  // DOCUMENTS, so an un-stripped haystack is satisfied by the prose.
  return readFileSync(join(REPO_ROOT, rel), "utf-8")
    .split("\n")
    .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l))
    .join("\n");
}

describe("#8392 — Anthropic content-block selection parity across the TS readers", () => {
  it("covers every TS reader of an Anthropic content array", () => {
    // Cardinality pin: a member-wise loop cannot see a reader REMOVED from the set.
    expect(READERS).toHaveLength(3);
  });

  for (const { path, label } of READERS) {
    it(`${label} selects the first block by type === "text"`, () => {
      const src = sourceOf(path);
      expect(src).toMatch(SELECT_BY_TYPE);
    });

    it(`${label} does not select by a "not thinking" denylist`, () => {
      const src = sourceOf(path);
      expect(src).not.toMatch(SELECT_BY_NOT_THINKING);
    });

    it(`${label} reads no fixed content position`, () => {
      const src = sourceOf(path);
      expect(src).not.toMatch(/\.content\s*\??\.?\s*\[\s*\d+\s*\]/);
    });
  }

  it("the assertions above are non-vacuous (known-positive control)", () => {
    // A correct reader must match, and each forbidden spelling must be detectable.
    // Without this, a regex that matches nothing would pass every `not.toMatch`.
    const good = `const text = data.content.find((b) => b.type === "text")?.text ?? "";`;
    const denylist = `const text = data.content.find((b) => b.type !== "thinking")?.text ?? "";`;
    const positional = `const text = data.content[0].text ?? "";`;
    expect(good).toMatch(SELECT_BY_TYPE);
    expect(denylist).toMatch(SELECT_BY_NOT_THINKING);
    expect(positional).toMatch(/\.content\s*\??\.?\s*\[\s*\d+\s*\]/);
  });
});
