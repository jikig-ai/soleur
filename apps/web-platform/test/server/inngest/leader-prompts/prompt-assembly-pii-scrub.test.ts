/**
 * Tests for the prompt-assembly PII-scrub TOM (AC16 in
 * 2026-05-25-feat-anthropic-leader-loop-pr-b-plan.md).
 *
 * Two passes:
 *   1. sanitizePromptString: control char / U+2028 / U+2029 strip (per
 *      learning 2026-05-06-new-prompt-injection-site-needs-sanitization-parity.md).
 *      Mirrors the contract at server/soleur-go-runner.ts:1009-1013 but
 *      without the 256-cap (PR diffs are long).
 *   2. scrubEmails: replace any /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/
 *      match with `<email-redacted>` EXCEPT the operator's own email if
 *      present on a redact-allowlist.
 *
 * Test fixtures are synthesized per cq-test-fixtures-synthesized-only.
 * Per cq-regex-unicode-separators-escape-only: U+2028/U+2029 are
 * referenced via \u2028 / \u2029 escapes in regex literals (literal
 * separator chars are JS line terminators and cannot appear inside a
 * regex source).
 */

import { describe, it, expect } from "vitest";

import {
  sanitizePromptString,
  scrubEmails,
  assemblePromptText,
} from "@/server/inngest/leader-prompts/prompt-assembly";

const OPERATOR = "ops@jikigai.example"; // synthetic allowlist target

const EMAIL_REGEX = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;

// U+2028 (line separator) + U+2029 (paragraph separator) constructed
// from char codes so the test source file contains no literal copies.
const LS = String.fromCharCode(0x2028);
const PS = String.fromCharCode(0x2029);

describe("prompt-assembly --- sanitizePromptString", () => {
  it("strips control chars (0x00 .. 0x1f, 0x7f)", () => {
    const dirty = "hello\x00world\x01\x1f\x7fend";
    expect(sanitizePromptString(dirty)).toBe("helloworldend");
  });

  it("strips U+2028 (line separator) and U+2029 (paragraph separator)", () => {
    const dirty = `line1${LS}line2${PS}line3`;
    expect(sanitizePromptString(dirty)).toBe("line1line2line3");
  });

  it("preserves regular printable ASCII", () => {
    const clean = "Review the diff at apps/web-platform -- looks good!";
    expect(sanitizePromptString(clean)).toBe(clean);
  });

  it("preserves newline and tab (NOT control chars per our contract)", () => {
    const text = "line1\nline2\ttab";
    expect(sanitizePromptString(text)).toBe(text);
  });

  it("returns empty string for null/undefined", () => {
    expect(sanitizePromptString(null)).toBe("");
    expect(sanitizePromptString(undefined)).toBe("");
  });
});

describe("prompt-assembly --- scrubEmails", () => {
  it("replaces non-allowlisted emails with <email-redacted>", () => {
    const text = "Commit by alice@evil.example and bob@third-party.example";
    const scrubbed = scrubEmails(text, OPERATOR);
    expect(scrubbed).not.toMatch(EMAIL_REGEX);
    expect(scrubbed).toContain("<email-redacted>");
  });

  it("preserves the operator's own email (allowlist)", () => {
    const text = `Commit by ${OPERATOR} and by attacker@evil.example`;
    const scrubbed = scrubEmails(text, OPERATOR);
    expect(scrubbed).toContain(OPERATOR);
    expect(scrubbed).toContain("<email-redacted>");
    expect(scrubbed.split("<email-redacted>")).toHaveLength(2);
  });

  it("redacts the operator email when allowlist is null (no allowlist)", () => {
    const text = `Commit by ${OPERATOR}`;
    const scrubbed = scrubEmails(text, null);
    expect(scrubbed).not.toContain(OPERATOR);
    expect(scrubbed).toContain("<email-redacted>");
  });

  it("handles a fixture with multiple non-operator emails + control chars + separators together", () => {
    const fixture = `Diff author: anna@example.com\x00${LS}reviewer: bob@example.org${PS}reply-to: charlie@third.example`;
    const out = scrubEmails(sanitizePromptString(fixture), OPERATOR);
    expect(out).not.toMatch(EMAIL_REGEX);
    expect(out.match(/<email-redacted>/g)?.length).toBe(3);
    // Control chars + U+2028 + U+2029 stripped.
    // eslint-disable-next-line no-control-regex
    expect(out).not.toMatch(/[\x00-\x1f\x7f\u2028\u2029]/);
  });
});

describe("prompt-assembly --- assemblePromptText (composes both passes)", () => {
  it("strips control chars THEN redacts emails (sanitize first)", () => {
    const dirty = `author = attacker\x00@evil.example`;
    const out = assemblePromptText(dirty, OPERATOR);
    expect(out).toBe("author = <email-redacted>");
  });

  it("preserves allowlisted operator email through both passes", () => {
    const dirty = `committer: ${OPERATOR}${LS}author: ${OPERATOR}`;
    const out = assemblePromptText(dirty, OPERATOR);
    expect(out).toContain(OPERATOR);
    expect(out).not.toMatch(/[\u2028\u2029]/);
  });

  it("is deterministic (same input -> same output)", () => {
    const dirty = "author = victim@example.com";
    const a = assemblePromptText(dirty, OPERATOR);
    const b = assemblePromptText(dirty, OPERATOR);
    expect(a).toBe(b);
  });

  it("known-PII fixture produces output free of non-operator @-signs (canonical pre-merge assertion)", () => {
    const fixture = [
      "Author: alice@corp.example",
      "Reviewer: bob@vendor.example",
      "Bug report from: carol+spam@third.example",
      "Allow operator commit: " + OPERATOR,
    ].join("\n");
    const out = assemblePromptText(fixture, OPERATOR);
    const nonOperatorMatches = out.replace(OPERATOR, "").match(EMAIL_REGEX);
    expect(nonOperatorMatches).toBeNull();
  });
});
