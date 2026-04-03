import { describe, it, expect } from "vitest";
import { safeReturnTo } from "@/lib/safe-return-to";

describe("safeReturnTo", () => {
  it("returns /dashboard as fallback for null input", () => {
    expect(safeReturnTo(null)).toBe("/dashboard");
  });

  it("returns /dashboard as fallback for empty string", () => {
    expect(safeReturnTo("")).toBe("/dashboard");
  });

  it("allows /dashboard path", () => {
    expect(safeReturnTo("/dashboard")).toBe("/dashboard");
  });

  it("allows /dashboard/settings path", () => {
    expect(safeReturnTo("/dashboard/settings")).toBe("/dashboard/settings");
  });

  it("blocks absolute URLs", () => {
    expect(safeReturnTo("https://evil.com")).toBe("/dashboard");
  });

  it("blocks protocol-relative URLs", () => {
    expect(safeReturnTo("//evil.com")).toBe("/dashboard");
  });

  it("blocks paths with backslash", () => {
    expect(safeReturnTo("/dashboard\\@evil.com")).toBe("/dashboard");
  });

  it("blocks paths not starting with /dashboard", () => {
    expect(safeReturnTo("/login")).toBe("/dashboard");
  });

  it("blocks paths that start with /dashboard but use // after", () => {
    expect(safeReturnTo("/dashboard//evil.com")).toBe("/dashboard");
  });
});
