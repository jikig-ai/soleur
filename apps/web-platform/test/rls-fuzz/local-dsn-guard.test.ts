import { describe, test, expect } from "vitest";
import { assertLocalDsn, isLocalDsnHost } from "./local-dsn-guard";

// AC7 — the RLS-fuzz harness must NEVER run against a non-local Postgres.
// Fail-closed ALLOWLIST: only localhost / loopback / an explicit CI service
// host is permitted. Everything else (esp. hosted Supabase) hard-errors.
// Parse-host membership only — NO DNS lookup.

describe("assertLocalDsn (fail-closed allowlist)", () => {
  const LOCAL = [
    "postgres://postgres:pw@localhost:54322/postgres",
    "postgres://postgres:pw@127.0.0.1:54322/postgres",
    "postgresql://postgres:pw@[::1]:54322/postgres",
    "postgres://postgres@127.0.0.1/postgres",
  ];
  const REMOTE = [
    "postgres://postgres:pw@db.abcdefgh.supabase.co:5432/postgres",
    "postgres://u:p@aws-0-eu-central-1.pooler.supabase.com:6543/postgres",
    "postgresql://u:p@10.0.1.40:5432/postgres", // private-net, NOT loopback
    "postgres://u:p@example.com:5432/postgres",
    "postgres://u:p@localhost.attacker.com:5432/postgres", // suffix-attack on the label
  ];

  test.each(LOCAL)("permits local host: %s", (dsn) => {
    expect(() => assertLocalDsn(dsn)).not.toThrow();
    expect(isLocalDsnHost(dsn)).toBe(true);
  });

  test.each(REMOTE)("rejects non-local host: %s", (dsn) => {
    expect(() => assertLocalDsn(dsn)).toThrow(/local/i);
    expect(isLocalDsnHost(dsn)).toBe(false);
  });

  test("permits an explicit CI service host via RLS_FUZZ_CI_DB_HOST", () => {
    const dsn = "postgres://u:p@postgres-ci:5432/postgres";
    expect(isLocalDsnHost(dsn, { ciHost: "postgres-ci" })).toBe(true);
    expect(isLocalDsnHost(dsn)).toBe(false); // no allowlist entry → rejected
  });

  test("rejects a malformed / hostless DSN (fail closed)", () => {
    expect(() => assertLocalDsn("not-a-dsn")).toThrow();
    expect(() => assertLocalDsn("")).toThrow();
  });

  test("does not perform DNS resolution (pure host parse)", () => {
    // A hostname that would resolve to 127.0.0.1 in DNS must still be REJECTED —
    // the guard is a literal-host allowlist, never a resolver.
    expect(isLocalDsnHost("postgres://u:p@localtest.me:5432/postgres")).toBe(false);
  });
});
