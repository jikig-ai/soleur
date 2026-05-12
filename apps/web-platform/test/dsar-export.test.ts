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
  dsarStringify,
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

// Phase 5: deterministic serialization conventions per AC23.
//
// Why this is a golden fixture: the manifest's stability under SHA-256
// is part of the audit story (AC2 — every per-table file's sha256 in
// manifest must reproduce on re-read). Sorted-keys + ISO 8601 + base64
// for bytea + JSON null for SQL NULL are the four invariants that make
// the bundle byte-stable across re-runs of the same data.

describe("dsarStringify (AC23 serialization conventions)", () => {
  it("sorts object keys alphabetically for deterministic SHA-256", () => {
    const out1 = dsarStringify({ b: 1, a: 2, c: 3 });
    const out2 = dsarStringify({ c: 3, a: 2, b: 1 });
    expect(out1).toBe(out2);
    expect(out1.indexOf('"a"')).toBeLessThan(out1.indexOf('"b"'));
    expect(out1.indexOf('"b"')).toBeLessThan(out1.indexOf('"c"'));
  });

  it("encodes Date values as ISO 8601 with UTC offset (Z)", () => {
    const out = dsarStringify({ at: new Date("2026-05-12T10:30:00.000Z") });
    expect(out).toContain('"2026-05-12T10:30:00.000Z"');
  });

  it("encodes Buffer (Postgres bytea) as base64 string", () => {
    const out = dsarStringify({ ciphertext: Buffer.from("hello", "utf-8") });
    // "hello" base64 = "aGVsbG8="
    expect(out).toContain('"aGVsbG8="');
  });

  it("encodes Uint8Array as base64 string (bytea via non-Buffer path)", () => {
    const bytes = new Uint8Array([104, 105]); // "hi"
    const out = dsarStringify({ ciphertext: bytes });
    expect(out).toContain('"aGk="');
  });

  it("encodes null and undefined as JSON null (SQL NULL convention)", () => {
    const out = dsarStringify({ a: null, b: undefined });
    expect(out).toContain('"a": null');
    expect(out).toContain('"b": null');
  });

  it("recursively normalizes nested objects + arrays of mixed types", () => {
    const out = dsarStringify({
      rows: [
        { c: 1, a: new Date("2026-01-01T00:00:00.000Z"), b: null },
      ],
    });
    // Inside the array, the row's keys must also be sorted.
    const aIdx = out.indexOf('"a"');
    const bIdx = out.indexOf('"b"');
    const cIdx = out.indexOf('"c"');
    expect(aIdx).toBeLessThan(bIdx);
    expect(bIdx).toBeLessThan(cIdx);
    expect(out).toContain('"2026-01-01T00:00:00.000Z"');
  });

  it("produces byte-identical output across calls (SHA-256 stability)", () => {
    const fixture = {
      table: "conversations",
      rows: [
        { id: "11111111-1111-1111-1111-111111111111", user_id: "u-1", title: "t" },
        { id: "22222222-2222-2222-2222-222222222222", user_id: "u-1", title: null },
      ],
    };
    const a = dsarStringify(fixture);
    const b = dsarStringify(fixture);
    expect(a).toBe(b);
  });
});
