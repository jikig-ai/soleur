import { describe, test, expect } from "bun:test";

// Import the sanitizeFilename function from the adapter
// We extract it as a standalone module for testability
import { sanitizeFilename } from "../skills/pencil-setup/scripts/sanitize-filename.mjs";

describe("sanitizeFilename", () => {
  test("preserves simple names", () => {
    expect(sanitizeFilename("Pricing OG Image")).toBe("Pricing OG Image");
  });

  test("replaces forward slashes with hyphens", () => {
    expect(sanitizeFilename("hero/banner")).toBe("hero-banner");
  });

  test("replaces backslashes with hyphens", () => {
    expect(sanitizeFilename("hero\\banner")).toBe("hero-banner");
  });

  test("replaces colons with hyphens", () => {
    expect(sanitizeFilename("test:file")).toBe("test-file");
  });

  test("collapses consecutive unsafe characters into single hyphen", () => {
    expect(sanitizeFilename("test:::file")).toBe("test-file");
  });

  test("replaces all unsafe characters", () => {
    expect(sanitizeFilename('a*b?c"d<e>f|g')).toBe("a-b-c-d-e-f-g");
  });

  test("trims leading and trailing hyphens", () => {
    expect(sanitizeFilename("/leading")).toBe("leading");
    expect(sanitizeFilename("trailing/")).toBe("trailing");
  });

  test("trims leading and trailing whitespace", () => {
    expect(sanitizeFilename("  spaced  ")).toBe("spaced");
  });

  test("truncates to 200 characters with correct content", () => {
    const longName = "a".repeat(250);
    expect(sanitizeFilename(longName)).toBe("a".repeat(200));
  });

  test("returns empty string for null or undefined input", () => {
    expect(sanitizeFilename(null)).toBe("");
    expect(sanitizeFilename(undefined)).toBe("");
  });

  test("returns empty string for empty input", () => {
    expect(sanitizeFilename("")).toBe("");
  });

  test("returns empty string for dot-dot traversal names", () => {
    expect(sanitizeFilename("..")).toBe("");
    expect(sanitizeFilename(".")).toBe("");
  });

  test("returns empty string when all characters are unsafe", () => {
    expect(sanitizeFilename("///")).toBe("");
  });

  test("preserves Unicode characters", () => {
    expect(sanitizeFilename("日本語テスト")).toBe("日本語テスト");
  });

  test("preserves dots in names", () => {
    expect(sanitizeFilename("file.name")).toBe("file.name");
  });

  test("handles mixed unsafe and safe characters", () => {
    expect(sanitizeFilename("my/cool*design|v2")).toBe("my-cool-design-v2");
  });
});
