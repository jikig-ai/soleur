import { describe, test, expect } from "vitest";
import { sanitizeForLog } from "@/lib/log-sanitize";

describe("sanitizeForLog", () => {
  test("strips C0 control characters and DEL", () => {
    expect(sanitizeForLog("a\x00b\x1fc\x7fd")).toBe("abcd");
  });

  test("regex is global — strips every occurrence, not just the first", () => {
    // Pins the /g flag. A regression to a non-global regex would still pass
    // the previous tests when they happen to contain only one offender.
    expect(sanitizeForLog("a\x00b\x00c\x00d")).toBe("abcd");
  });

  test("strips U+2028 and U+2029 line/paragraph separators", () => {
    expect(sanitizeForLog("a\u2028b\u2029c")).toBe("abc");
  });

  test("truncates to default maxLen of 500", () => {
    expect(sanitizeForLog("x".repeat(1000))).toHaveLength(500);
  });

  test("truncates to custom maxLen", () => {
    expect(sanitizeForLog("x".repeat(200), 100)).toHaveLength(100);
  });

  test("preserves ordinary text under the cap", () => {
    expect(sanitizeForLog("hello world")).toBe("hello world");
  });
});
