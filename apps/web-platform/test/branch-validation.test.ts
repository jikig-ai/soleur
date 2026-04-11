/**
 * Branch Name Validation Tests (#1929)
 *
 * Tests validateBranchFormat() against all 10 git check-ref-format rules
 * (--allow-onelevel semantics: single-component names like "feat-x" are valid).
 *
 * Standalone module with zero heavy dependencies — follows the
 * sandbox.ts / error-sanitizer.ts extraction pattern.
 */
import { describe, test, expect } from "vitest";
import { validateBranchFormat } from "../server/branch-validation";

describe("validateBranchFormat", () => {
  // -----------------------------------------------------------------------
  // Rule 1: no component starts with . or ends with .lock
  // -----------------------------------------------------------------------
  test("rejects branch with component starting with dot", () => {
    expect(() => validateBranchFormat(".hidden/branch")).toThrow(/starts with '\.'|starts with '\.'/);
  });

  test("rejects nested component starting with dot", () => {
    expect(() => validateBranchFormat("feat/.hidden")).toThrow(/starts with '\.'|starts with '\.'/);
  });

  test("rejects branch with component ending in .lock", () => {
    expect(() => validateBranchFormat("feat/branch.lock")).toThrow(/\.lock/);
  });

  test("allows .lock in middle of component", () => {
    expect(() => validateBranchFormat("feat/branch.locksmith")).not.toThrow();
  });

  // -----------------------------------------------------------------------
  // Rule 3: no .. anywhere
  // -----------------------------------------------------------------------
  test("rejects double dots", () => {
    expect(() => validateBranchFormat("feat..branch")).toThrow(/\.\./);
  });

  // -----------------------------------------------------------------------
  // Rule 4: no control chars, space, ~, ^, :
  // -----------------------------------------------------------------------
  test("rejects space in branch name", () => {
    expect(() => validateBranchFormat("feat branch")).toThrow(/forbidden/i);
  });

  test("rejects tilde", () => {
    expect(() => validateBranchFormat("feat~1")).toThrow(/forbidden/i);
  });

  test("rejects caret", () => {
    expect(() => validateBranchFormat("feat^2")).toThrow(/forbidden/i);
  });

  test("rejects colon", () => {
    expect(() => validateBranchFormat("feat:branch")).toThrow(/forbidden/i);
  });

  test("rejects null byte", () => {
    expect(() => validateBranchFormat("feat\x00branch")).toThrow(/forbidden/i);
  });

  test("rejects DEL character", () => {
    expect(() => validateBranchFormat("feat\x7Fbranch")).toThrow(/forbidden/i);
  });

  // -----------------------------------------------------------------------
  // Rule 5: no ?, *, [
  // -----------------------------------------------------------------------
  test("rejects question mark", () => {
    expect(() => validateBranchFormat("feat?")).toThrow(/forbidden/i);
  });

  test("rejects asterisk", () => {
    expect(() => validateBranchFormat("feat*")).toThrow(/forbidden/i);
  });

  test("rejects open bracket", () => {
    expect(() => validateBranchFormat("feat[0]")).toThrow(/forbidden/i);
  });

  // -----------------------------------------------------------------------
  // Rule 6: no leading/trailing /, no //
  // -----------------------------------------------------------------------
  test("rejects leading slash", () => {
    expect(() => validateBranchFormat("/feat")).toThrow(/begin or end with '\/'/);
  });

  test("rejects trailing slash", () => {
    expect(() => validateBranchFormat("feat/")).toThrow(/begin or end with '\/'/);
  });

  test("rejects consecutive slashes", () => {
    expect(() => validateBranchFormat("feat//branch")).toThrow(/\/\//);
  });

  // -----------------------------------------------------------------------
  // Rule 7: cannot end with .
  // -----------------------------------------------------------------------
  test("rejects trailing dot", () => {
    expect(() => validateBranchFormat("feat.")).toThrow(/end with '\.'/);
  });

  // -----------------------------------------------------------------------
  // Rule 8: no @{
  // -----------------------------------------------------------------------
  test("rejects @{ sequence", () => {
    expect(() => validateBranchFormat("feat@{0}")).toThrow(/@\{/);
  });

  // -----------------------------------------------------------------------
  // Rule 9: cannot be @
  // -----------------------------------------------------------------------
  test("rejects single @", () => {
    expect(() => validateBranchFormat("@")).toThrow(/@/);
  });

  // -----------------------------------------------------------------------
  // Rule 10: no backslash
  // -----------------------------------------------------------------------
  test("rejects backslash", () => {
    expect(() => validateBranchFormat("feat\\branch")).toThrow(/forbidden/i);
  });

  // -----------------------------------------------------------------------
  // Valid names
  // -----------------------------------------------------------------------
  test("allows simple branch", () => {
    expect(() => validateBranchFormat("feat-x")).not.toThrow();
  });

  test("allows slashed branch", () => {
    expect(() => validateBranchFormat("feat/my-feature")).not.toThrow();
  });

  test("allows dots in branch", () => {
    expect(() => validateBranchFormat("v1.0.0-rc")).not.toThrow();
  });

  test("allows @ in branch (not sole char)", () => {
    expect(() => validateBranchFormat("user@branch")).not.toThrow();
  });

  test("allows hyphens and underscores", () => {
    expect(() => validateBranchFormat("feat_my-branch")).not.toThrow();
  });

  test("allows multi-level paths", () => {
    expect(() => validateBranchFormat("feat/scope/detail")).not.toThrow();
  });

  // -----------------------------------------------------------------------
  // Length limits
  // -----------------------------------------------------------------------
  test("rejects empty string", () => {
    expect(() => validateBranchFormat("")).toThrow(/empty/i);
  });

  test("rejects branch over 255 chars", () => {
    expect(() => validateBranchFormat("a".repeat(256))).toThrow(/255/);
  });

  test("allows branch at exactly 255 chars", () => {
    expect(() => validateBranchFormat("a".repeat(255))).not.toThrow();
  });
});
