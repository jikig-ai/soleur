import { describe, it, expect } from "vitest";

// Phase 2 unit tests for `apps/web-platform/server/dsar-export.ts` —
// covers the load-bearing cross-tenant invariant primitives:
//   - assertReadScope(rows, expectedUserId, tableName)
//   - CrossTenantViolation error type
//
// Per plan rev-2 AC12 + AC15 + FR9 + the silent-RLS learning
// `2026-04-12-silent-rls-failures-in-team-names.md`. Wider worker-level
// tests (happy path, archive flow, manifest serialization, per-file
// error policy) land in Phase 5 alongside the worker implementation;
// this file only exercises the Phase 2 skeleton.

import {
  assertReadScope,
  CrossTenantViolation,
} from "../server/dsar-export";

describe("CrossTenantViolation", () => {
  it("is an Error subclass with name and tag", () => {
    const err = new CrossTenantViolation("conversations", "user-a", "user-b");
    expect(err).toBeInstanceOf(Error);
    expect(err.name).toBe("CrossTenantViolation");
    expect(err.tableName).toBe("conversations");
    expect(err.expectedUserId).toBe("user-a");
    expect(err.offendingUserId).toBe("user-b");
    expect(err.message).toContain("conversations");
  });
});

describe("assertReadScope", () => {
  it("returns rows unchanged when every row matches expectedUserId", () => {
    const rows = [
      { id: "1", owner_id: "user-a", payload: "x" },
      { id: "2", owner_id: "user-a", payload: "y" },
    ];
    const out = assertReadScope(rows, "user-a", "conversations");
    expect(out).toBe(rows);
  });

  it("returns an empty array unchanged (caller decides empty-vs-denied)", () => {
    // An empty array is ambiguous between "RLS denied all rows" and "user
    // has no data in this table". The worker's allowlist enumerator
    // distinguishes by re-checking via service-role outside this helper;
    // assertReadScope is a pure invariant check that does not raise on
    // empty input. The silent-RLS failure detection is the worker's
    // responsibility, asserted by the worker's broader unit tests.
    const out = assertReadScope([], "user-a", "messages");
    expect(out).toEqual([]);
  });

  it("raises CrossTenantViolation when ANY row has a different owner_id", () => {
    const rows = [
      { id: "1", owner_id: "user-a" },
      { id: "2", owner_id: "user-b" }, // <-- the bug
      { id: "3", owner_id: "user-a" },
    ];
    expect(() => assertReadScope(rows, "user-a", "messages")).toThrow(
      CrossTenantViolation,
    );
  });

  it("raises with the offending userId in the error fields", () => {
    const rows = [{ id: "1", owner_id: "user-b" }];
    try {
      assertReadScope(rows, "user-a", "kb_documents");
      throw new Error("assertReadScope should have raised");
    } catch (err) {
      expect(err).toBeInstanceOf(CrossTenantViolation);
      expect((err as CrossTenantViolation).expectedUserId).toBe("user-a");
      expect((err as CrossTenantViolation).offendingUserId).toBe("user-b");
      expect((err as CrossTenantViolation).tableName).toBe("kb_documents");
    }
  });

  it("raises when a row is missing the owner_id field (treat as drift)", () => {
    // A SELECT * that drops the owner_id projection (refactor accident)
    // is indistinguishable from a row that genuinely lacks owner_id.
    // Both are P0 — the invariant is that every read row provably
    // belongs to expectedUserId, which we cannot prove if owner_id is
    // absent.
    const rows = [{ id: "1" }] as unknown as Array<{ id: string; owner_id: string }>;
    expect(() => assertReadScope(rows, "user-a", "messages")).toThrow(
      CrossTenantViolation,
    );
  });

  it("accepts a custom owner-field name (some tables use `user_id`)", () => {
    const rows = [{ id: "1", user_id: "user-a" }];
    const out = assertReadScope(rows, "user-a", "conversations", {
      ownerField: "user_id",
    });
    expect(out).toBe(rows);
  });

  it("raises CrossTenantViolation when the custom owner-field is misowned", () => {
    const rows = [{ id: "1", user_id: "user-b" }];
    expect(() =>
      assertReadScope(rows, "user-a", "conversations", {
        ownerField: "user_id",
      }),
    ).toThrow(CrossTenantViolation);
  });
});
