import { describe, it, expect } from "vitest";
import { sqlStateFromError } from "../lib/postgres-errors";

describe("sqlStateFromError", () => {
  it("extracts a 5-char SQLSTATE from a PostgREST-shaped error", () => {
    // The suspected account-delete failure (#4695): permission denied to SET
    // session_replication_role inside an anonymise_* SECURITY DEFINER RPC.
    const pgErr = {
      message: 'permission denied to set parameter "session_replication_role"',
      details: null,
      hint: null,
      code: "42501",
    };
    expect(sqlStateFromError(pgErr)).toBe("42501");
  });

  it("extracts SQLSTATE codes containing letters (e.g. 42P01 undefined_table)", () => {
    expect(sqlStateFromError({ code: "42P01" })).toBe("42P01");
    expect(sqlStateFromError({ code: "23505" })).toBe("23505");
  });

  it("reads .code off a real Error instance (node-postgres shape)", () => {
    const err = Object.assign(new Error("deadlock detected"), { code: "40P01" });
    expect(sqlStateFromError(err)).toBe("40P01");
  });

  it("rejects Node system-error codes (ENOENT/EACCES are not SQLSTATE)", () => {
    // SQLSTATE is exactly 5 chars; ENOENT/EACCES are 6 — the format guard keeps
    // a filesystem error from being mis-tagged as a DB error.
    expect(sqlStateFromError({ code: "ENOENT" })).toBeUndefined();
    expect(sqlStateFromError({ code: "EACCES" })).toBeUndefined();
  });

  it("returns undefined for non-string / missing / lowercase codes", () => {
    expect(sqlStateFromError({ code: 42501 })).toBeUndefined();
    expect(sqlStateFromError({ message: "no code here" })).toBeUndefined();
    expect(sqlStateFromError(null)).toBeUndefined();
    expect(sqlStateFromError(undefined)).toBeUndefined();
    expect(sqlStateFromError("a string error")).toBeUndefined();
    // lowercase would not be a canonical SQLSTATE
    expect(sqlStateFromError({ code: "42p01" })).toBeUndefined();
  });
});
