import { describe, it, expect } from "vitest";
import { validateConversationContext } from "@/server/context-validation";

describe("validateConversationContext", () => {
  it("returns undefined for undefined input", () => {
    expect(validateConversationContext(undefined)).toBeUndefined();
  });

  it("returns undefined for null input", () => {
    expect(validateConversationContext(null)).toBeUndefined();
  });

  it("accepts valid context with content", () => {
    const result = validateConversationContext({
      path: "product/roadmap.md",
      type: "kb-viewer",
      content: "# Roadmap",
    });
    expect(result).toEqual({
      path: "product/roadmap.md",
      type: "kb-viewer",
      content: "# Roadmap",
    });
  });

  it("accepts valid context without content", () => {
    const result = validateConversationContext({
      path: "knowledge-base/overview.md",
      type: "kb-viewer",
    });
    expect(result).toEqual({
      path: "knowledge-base/overview.md",
      type: "kb-viewer",
      content: undefined,
    });
  });

  it("rejects non-object input", () => {
    expect(() => validateConversationContext("string")).toThrow("expected object");
    expect(() => validateConversationContext(42)).toThrow("expected object");
  });

  it("rejects path with traversal sequences", () => {
    expect(() =>
      validateConversationContext({
        path: "../../../etc/passwd",
        type: "kb-viewer",
      }),
    ).toThrow("path must match");
  });

  it("rejects path with dot-dot segments", () => {
    expect(() =>
      validateConversationContext({
        path: "knowledge-base/../../secret.md",
        type: "kb-viewer",
      }),
    ).toThrow("path must match");
  });

  it("rejects non-.md path extensions", () => {
    expect(() =>
      validateConversationContext({
        path: "file.js",
        type: "kb-viewer",
      }),
    ).toThrow("path must match");
  });

  it("rejects path with null bytes", () => {
    expect(() =>
      validateConversationContext({
        path: "file\0.md",
        type: "kb-viewer",
      }),
    ).toThrow("path must match");
  });

  it("rejects path with spaces", () => {
    expect(() =>
      validateConversationContext({
        path: "my file.md",
        type: "kb-viewer",
      }),
    ).toThrow("path must match");
  });

  it("rejects unknown context type", () => {
    expect(() =>
      validateConversationContext({
        path: "file.md",
        type: "admin-panel",
      }),
    ).toThrow("type must be one of");
  });

  it("rejects missing type", () => {
    expect(() =>
      validateConversationContext({
        path: "file.md",
      }),
    ).toThrow("type must be one of");
  });

  it("rejects content exceeding 1MB", () => {
    expect(() =>
      validateConversationContext({
        path: "file.md",
        type: "kb-viewer",
        content: "x".repeat(1024 * 1024 + 1),
      }),
    ).toThrow("content exceeds 1MB limit");
  });

  it("accepts content at exactly 1MB", () => {
    const result = validateConversationContext({
      path: "file.md",
      type: "kb-viewer",
      content: "x".repeat(1024 * 1024),
    });
    expect(result?.content?.length).toBe(1024 * 1024);
  });

  it("rejects non-string content", () => {
    expect(() =>
      validateConversationContext({
        path: "file.md",
        type: "kb-viewer",
        content: 12345,
      }),
    ).toThrow("content must be a string");
  });
});
