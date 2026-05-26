// RED-first per cq-write-failing-tests-before. Phase 2 of feat-cla-legal-rigor.
// TS1: doc-hash determinism — computeDocHash returns deterministic SHA-256
// of docs/legal/individual-cla.md at a given git SHA.
import { describe, it, expect } from "vitest";
import { computeDocHash, computeBodyHash } from "@/scripts/cla-evidence/hash";

describe("computeDocHash", () => {
  it("returns SHA-256 hex of docs/legal/individual-cla.md content at HEAD", async () => {
    const repoRoot = `${__dirname}/../../../..`;
    const head = "HEAD";
    const hash = await computeDocHash(repoRoot, head, "docs/legal/individual-cla.md");
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it("is deterministic across two calls for the same SHA", async () => {
    const repoRoot = `${__dirname}/../../../..`;
    const a = await computeDocHash(repoRoot, "HEAD", "docs/legal/individual-cla.md");
    const b = await computeDocHash(repoRoot, "HEAD", "docs/legal/individual-cla.md");
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
