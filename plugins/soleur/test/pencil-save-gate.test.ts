import { describe, test, expect } from "bun:test";
import { shouldSkipSave } from "../skills/pencil-setup/scripts/pencil-save-gate.mjs";

// T2.3 — Auto-save after a failed mutation is the mechanism that produced
// 0-byte .pen files. The adapter's registerMutatingTool and open_document
// unconditionally enqueued save() after a batch_design/open. If the
// mutation errored, pencil's save() ran against a stale or uninitialized
// state and wrote nothing. The gate decides: do NOT save when the
// preceding mutation produced an isError=true classification.

describe("shouldSkipSave", () => {
  test("skips when last classification isError=true", () => {
    expect(shouldSkipSave({ isError: true, text: "Invalid properties: foo" })).toBe(true);
  });

  test("allows save when last classification isError=false", () => {
    expect(shouldSkipSave({ isError: false, text: 'node0="abc"' })).toBe(false);
  });

  test("skips on auth-failure classification", () => {
    expect(shouldSkipSave({ isError: true, text: "Unauthorized" })).toBe(true);
  });

  test("allows save when no prior classification exists (first call)", () => {
    expect(shouldSkipSave(null)).toBe(false);
    expect(shouldSkipSave(undefined)).toBe(false);
  });

  test("allows save when classification is missing isError field", () => {
    // Defensive: if the caller forgets to pass the classification shape,
    // don't block the save (preserves existing behavior).
    expect(shouldSkipSave({ text: "hello" } as any)).toBe(false);
  });

  test("skips when isError is truthy but not strictly true", () => {
    // Defensive: accept any truthy isError value.
    expect(shouldSkipSave({ isError: 1, text: "bad" } as any)).toBe(true);
  });
});
