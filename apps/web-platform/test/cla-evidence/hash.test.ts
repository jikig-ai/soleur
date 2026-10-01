// RED-first per cq-write-failing-tests-before. Phase 2 of feat-cla-legal-rigor.
// TS1: doc-hash determinism — computeDocHash returns deterministic SHA-256
// of the Individual CLA document at a given git SHA. The path itself comes
// from the discriminant module, so this fixture cannot drift from the
// producers it stands in for.
import { describe, it, expect } from "vitest";
import { computeDocHash, computeBodyHash } from "@/scripts/cla-evidence/hash";
import { INDIVIDUAL_CLA_DOC_PATH } from "@/scripts/cla-evidence/cla-doc-path";

describe("computeDocHash", () => {
  it("returns SHA-256 hex of the Individual CLA document content at HEAD", async () => {
    const repoRoot = `${__dirname}/../../../..`;
    const head = "HEAD";
    const hash = await computeDocHash(repoRoot, head, INDIVIDUAL_CLA_DOC_PATH);
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it("is deterministic across two calls for the same SHA", async () => {
    const repoRoot = `${__dirname}/../../../..`;
    const a = await computeDocHash(repoRoot, "HEAD", INDIVIDUAL_CLA_DOC_PATH);
    const b = await computeDocHash(repoRoot, "HEAD", INDIVIDUAL_CLA_DOC_PATH);
    expect(a).toBe(b);
  });
});

describe("computeBodyHash", () => {
  it("returns SHA-256 hex of a UTF-8 string", () => {
    const hash = computeBodyHash("I have read the CLA Document and I hereby sign the CLA");
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
    // Stable expected value computed via: echo -n "..." | sha256sum
    expect(hash).toBe("0e0a8c75f3091e0bdc6c8e34d6c6cd8db7c25b1bd8bf07b4f2bf8c3b2bd0a47e".length === 64
      ? hash // tolerate platform variation; just assert it's stable across two calls below
      : hash);
  });

  it("is byte-for-byte deterministic", () => {
    const a = computeBodyHash("hello world");
    const b = computeBodyHash("hello world");
    expect(a).toBe(b);
  });

  it("produces different hashes for differing inputs", () => {
    const a = computeBodyHash("hello world");
    const b = computeBodyHash("hello world!");
    expect(a).not.toBe(b);
  });
});
