import { describe, test, expect } from "vitest";
import { validateCustomName, RESERVED_NAMES } from "../server/team-names-validation";

describe("validateCustomName", () => {
  test("accepts valid alphanumeric name", () => {
    expect(validateCustomName("Alex")).toEqual({ valid: true });
  });

  test("accepts name with spaces", () => {
    expect(validateCustomName("Alex Smith")).toEqual({ valid: true });
  });

  test("accepts name with numbers", () => {
    expect(validateCustomName("Agent 007")).toEqual({ valid: true });
  });

  test("accepts single character name", () => {
    expect(validateCustomName("A")).toEqual({ valid: true });
  });

  test("accepts 30-character name (max length)", () => {
    const name = "A".repeat(30);
    expect(validateCustomName(name)).toEqual({ valid: true });
  });

  test("rejects empty string", () => {
    const result = validateCustomName("");
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/empty/i);
  });

  test("rejects name exceeding 30 characters", () => {
    const name = "A".repeat(31);
    const result = validateCustomName(name);
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/30/);
  });

  test("rejects name with special characters", () => {
    const result = validateCustomName("Alex!@#");
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/alphanumeric/i);
  });

  test("rejects name with angle brackets (XSS prevention)", () => {
    const result = validateCustomName("<script>alert</script>");
    expect(result.valid).toBe(false);
  });

  test("rejects name with curly braces (injection prevention)", () => {
    const result = validateCustomName("{{system}}");
    expect(result.valid).toBe(false);
  });

  test("rejects name with newlines (control sequence prevention)", () => {
    const result = validateCustomName("Alex\nSmith");
    expect(result.valid).toBe(false);
  });

  test("rejects whitespace-only name", () => {
    const result = validateCustomName("   ");
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/empty/i);
  });

  test("rejects reserved word: system", () => {
    const result = validateCustomName("system");
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/reserved/i);
  });

  test("rejects reserved word case-insensitively", () => {
    const result = validateCustomName("SYSTEM");
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/reserved/i);
  });

  test("rejects reserved word: assistant", () => {
    const result = validateCustomName("assistant");
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/reserved/i);
  });

  test("rejects reserved word: user", () => {
    const result = validateCustomName("user");
    expect(result.valid).toBe(false);
    expect(result.error).toMatch(/reserved/i);
  });

  test("trims leading/trailing whitespace before validation", () => {
    expect(validateCustomName("  Alex  ")).toEqual({ valid: true });
  });

  test("RESERVED_NAMES includes expected words", () => {
    expect(RESERVED_NAMES).toContain("system");
    expect(RESERVED_NAMES).toContain("assistant");
    expect(RESERVED_NAMES).toContain("user");
    expect(RESERVED_NAMES).toContain("admin");
    expect(RESERVED_NAMES).toContain("soleur");
  });
});
