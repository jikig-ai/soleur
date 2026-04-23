import { describe, test, expect, vi } from "vitest";
import { formatAssistantText } from "../lib/format-assistant-text";

// ---------------------------------------------------------------------------
// FR3 (#2861): pure client-side render scrub. Strips sandbox/host workspace
// path prefixes from assistant text at render time ONLY. The stored
// `conversation_messages.content` remains verbatim — cost tracking, SDK
// replay, and Sentry breadcrumbs must observe the original model output.
//
// Path stripping runs only on prose segments; fenced code blocks, indented
// code blocks, and inline backticked identifiers are preserved byte-for-byte.
// ---------------------------------------------------------------------------

const WORKSPACE_PREFIX = "/workspaces/abc123def456";
const SANDBOX_PREFIX =
  "/tmp/claude-1000/-workspaces-abc123def456-7e8f9a2b1c3d4e5f6a7b8c9d0e1f2a3b";

describe("formatAssistantText (FR3 #2861)", () => {
  test("strips host workspace prefix outside code fences", () => {
    const raw = `Read ${WORKSPACE_PREFIX}/knowledge-base/vision.md first.`;
    const out = formatAssistantText(raw);
    expect(out).not.toContain(WORKSPACE_PREFIX);
    expect(out).toContain("knowledge-base/vision.md");
  });

  test("strips sandbox prefix outside code fences", () => {
    const raw = `The file ${SANDBOX_PREFIX}/knowledge-base/vision.md is open.`;
    const out = formatAssistantText(raw);
    expect(out).not.toContain(SANDBOX_PREFIX);
    expect(out).not.toContain("/tmp/claude-");
    expect(out).toContain("knowledge-base/vision.md");
  });

  test("preserves fenced code blocks byte-for-byte even with sandbox paths", () => {
    const raw = [
      "Before the fence.",
      "```",
      `cat ${SANDBOX_PREFIX}/vision.md`,
      "```",
      "After the fence.",
    ].join("\n");
    const out = formatAssistantText(raw);
    // Inside the fence: path must survive verbatim.
    expect(out).toContain(`cat ${SANDBOX_PREFIX}/vision.md`);
  });

  test("preserves language-tagged fenced code blocks", () => {
    const raw = [
      "```ts",
      `const p = "${WORKSPACE_PREFIX}/knowledge-base/vision.md";`,
      "```",
    ].join("\n");
    const out = formatAssistantText(raw);
    expect(out).toContain(`${WORKSPACE_PREFIX}/knowledge-base/vision.md`);
  });

  test("preserves indented 4-space code blocks", () => {
    // Markdown indented code: 4-space prefix marks a code block.
    const raw = [
      "Here is an example:",
      "",
      `    cat ${WORKSPACE_PREFIX}/vision.md`,
      "",
      "That is the path.",
    ].join("\n");
    const out = formatAssistantText(raw);
    expect(out).toContain(`    cat ${WORKSPACE_PREFIX}/vision.md`);
  });

  test("preserves inline backticked identifiers with sandbox paths", () => {
    const raw = `Use \`${SANDBOX_PREFIX}/file.md\` for now.`;
    const out = formatAssistantText(raw);
    expect(out).toContain(`\`${SANDBOX_PREFIX}/file.md\``);
  });

  test("preserves URLs containing sandbox-like substrings", () => {
    // URL starting with http(s) must never be scrubbed.
    const url = "https://example.com/workspaces/abc123def456/vision.md";
    const raw = `See ${url} for details.`;
    const out = formatAssistantText(raw);
    expect(out).toContain(url);
  });

  test("preserves #NNNN GitHub references", () => {
    const raw = "See #2861 for context. The #2843 fix landed earlier.";
    const out = formatAssistantText(raw);
    expect(out).toContain("#2861");
    expect(out).toContain("#2843");
  });

  test("handles CRLF line endings without corruption", () => {
    const raw = `Line one.\r\nLine two ${WORKSPACE_PREFIX}/file.md\r\nLine three.`;
    const out = formatAssistantText(raw);
    expect(out).not.toContain(WORKSPACE_PREFIX);
    expect(out).toContain("Line one.");
    expect(out).toContain("Line three.");
  });

  test("is pure: does not mutate its input", () => {
    const raw = `Read ${WORKSPACE_PREFIX}/vision.md now.`;
    const snapshot = raw.slice();
    formatAssistantText(raw);
    expect(raw).toBe(snapshot);
  });

  test("idempotent: running twice yields the same output", () => {
    const raw = `Open ${WORKSPACE_PREFIX}/vision.md and ${SANDBOX_PREFIX}/other.md.`;
    const once = formatAssistantText(raw);
    const twice = formatAssistantText(once);
    expect(twice).toBe(once);
  });

  test("reportFallthrough callback fires on unmatched suspected-leak shape", () => {
    const fallthrough = vi.fn();
    // This shape matches SUSPECTED_LEAK_SHAPE but not a canonical pattern
    // (non-hex chars in the UUID slot).
    const raw = "See /tmp/claude-weirdshape-not-matched/file.md here.";
    formatAssistantText(raw, { reportFallthrough: fallthrough });
    expect(fallthrough).toHaveBeenCalled();
  });

  test("reportFallthrough not called on clean matched paths", () => {
    const fallthrough = vi.fn();
    const raw = `Open ${WORKSPACE_PREFIX}/vision.md.`;
    formatAssistantText(raw, { reportFallthrough: fallthrough });
    expect(fallthrough).not.toHaveBeenCalled();
  });

  test("empty string passes through unchanged", () => {
    expect(formatAssistantText("")).toBe("");
  });

  test("no paths: passes through unchanged", () => {
    const raw = "Nothing path-shaped here, just prose. Also #2861.";
    expect(formatAssistantText(raw)).toBe(raw);
  });

  // Security-review regressions (#2861 review findings).

  test("prose containing literal 'PRESERVED_N' token is NOT rewritten (sentinel collision guard)", () => {
    // Before the per-call random sentinel fix, the placeholder was ` PRESERVED_N `.
    // If assistant prose happened to contain ` PRESERVED_0 `, the restore regex
    // would splice in preserved content or delete the literal. The fix uses a
    // per-call random nonce — literal PRESERVED_N in prose must round-trip.
    const raw = "See PRESERVED_0 in the earlier example. Also PRESERVED_42 below.";
    const out = formatAssistantText(raw);
    expect(out).toContain("PRESERVED_0");
    expect(out).toContain("PRESERVED_42");
    // Sentinel prefix must NOT leak into output
    expect(out).not.toContain("SOLEUR_PRES_");
  });

  test("prose with both literal PRESERVED token AND real sandbox path scrubs the path and preserves the literal", () => {
    const raw = `Read ${WORKSPACE_PREFIX}/vision.md, it explains PRESERVED_99 (legacy).`;
    const out = formatAssistantText(raw);
    expect(out).not.toContain(WORKSPACE_PREFIX);
    expect(out).toContain("PRESERVED_99");
    expect(out).toContain("vision.md");
  });

  test("idempotent on mixed fenced + prose with paths in both", () => {
    const raw = [
      `Open ${WORKSPACE_PREFIX}/vision.md first.`,
      "```",
      `cat ${SANDBOX_PREFIX}/vision.md`,
      "```",
      `Then ${SANDBOX_PREFIX}/other.md.`,
    ].join("\n");
    const once = formatAssistantText(raw);
    const twice = formatAssistantText(once);
    expect(twice).toBe(once);
    // Fence content survived
    expect(once).toContain(`cat ${SANDBOX_PREFIX}/vision.md`);
    // Prose paths stripped
    expect(once.split("```")[0]).not.toContain(WORKSPACE_PREFIX);
    expect(once.split("```")[2]).not.toContain(SANDBOX_PREFIX);
  });
});
