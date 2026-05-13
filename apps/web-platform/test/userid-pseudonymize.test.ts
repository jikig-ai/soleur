import { describe, it, expect, beforeEach, vi } from "vitest";
import { createHmac } from "node:crypto";

// Pepper must be set BEFORE the SUT module loads (observability.ts reads
// `process.env.SENTRY_USERID_PEPPER` at module init). vi.hoisted runs above
// top-level imports. Pepper-unset coverage lives in
// observability-pepper-unset.test.ts (per-file worker isolation).
vi.hoisted(() => {
  process.env.SENTRY_USERID_PEPPER = "test-pepper";
});

const TEST_PEPPER = "test-pepper";
const expectedHashFor = (userId: string) =>
  createHmac("sha256", TEST_PEPPER).update(userId).digest("hex");

// Frozen golden vector — same primitive guard as observability.test.ts:22-23.
// If hashUserId silently switches primitives (scrypt, blake2, truncation), this
// constant fails before the per-call expectedHashFor helpers track the new formula.
const GOLDEN_U1_HASH =
  "d23f7650f3a2d1b52a83870a6412528cb373d6baf3353cba3fd1b421a9c5d7ac";

import { renameUserIdToHash, hashUserIdValue } from "../server/userid-pseudonymize";
import { hashUserId } from "../server/observability";

beforeEach(() => {
  // No shared module state to reset; pure functions.
});

describe("hashUserIdValue (primitive)", () => {
  it("hashes a string via HMAC-SHA256 with the module pepper", () => {
    expect(hashUserIdValue("u1")).toBe(GOLDEN_U1_HASH);
  });

  it("returns 'pepper_unset_null' for null/undefined", () => {
    expect(hashUserIdValue(null)).toBe("pepper_unset_null");
    expect(hashUserIdValue(undefined)).toBe("pepper_unset_null");
  });

  it("coerces non-string values via String()", () => {
    expect(hashUserIdValue(42)).toBe(expectedHashFor("42"));
  });
});

describe("renameUserIdToHash (top-level walker)", () => {
  it("renames top-level `userId` to `userIdHash` with hash", () => {
    const out = renameUserIdToHash({ userId: "u1", err: "boom" });
    expect(out).toEqual({ userIdHash: GOLDEN_U1_HASH, err: "boom" });
  });

  it("renames top-level `user_id` to `userIdHash` with hash", () => {
    const uid = "11111111-1111-1111-1111-111111111111";
    const out = renameUserIdToHash({ user_id: uid, context: "x" });
    expect(out).toEqual({ userIdHash: expectedHashFor(uid), context: "x" });
  });

  it("renames null userId to `userIdHash: 'pepper_unset_null'` (matches observability.ts:53)", () => {
    const out = renameUserIdToHash({ userId: null as unknown as string, op: "x" });
    expect(out).toEqual({ userIdHash: "pepper_unset_null", op: "x" });
  });

  it("keeps existing `userIdHash` and drops raw `userId` when both are present (defensive)", () => {
    const out = renameUserIdToHash({
      userId: "u1",
      userIdHash: "preexisting-hash",
      err: "boom",
    });
    expect(out).toEqual({ userIdHash: "preexisting-hash", err: "boom" });
    expect(out).not.toHaveProperty("userId");
  });

  it("passes through unchanged when no `userId`/`user_id` key is present", () => {
    const input = { err: "boom", op: "x" };
    const out = renameUserIdToHash(input);
    expect(out).toEqual(input);
  });

  it("does NOT recurse into nested objects (top-level boundary)", () => {
    const out = renameUserIdToHash({ extra: { userId: "u1" }, op: "x" });
    expect(out).toEqual({ extra: { userId: "u1" }, op: "x" });
    expect(out.extra).toEqual({ userId: "u1" });
  });

  it("returns an empty object unchanged", () => {
    expect(renameUserIdToHash({})).toEqual({});
  });
});

describe("consistency with observability.hashUserId", () => {
  it("hashUserIdValue and hashUserId emit identical output for the same input", () => {
    const uid = "abcd-1234-5678-90ef";
    expect(hashUserIdValue(uid)).toBe(hashUserId(uid));
  });
});
