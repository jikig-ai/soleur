import { describe, it, expect, vi, beforeEach } from "vitest";

// A failed table read in `exportSqlTable` must say what the HTTP layer said,
// not only the body text. A gateway answered `Project not specified` as a
// non-JSON body on one DSAR read of a nightly run; postgrest-js turns that
// into `error = { message: body }` and leaves the status on the result object,
// so the thrown message could not be told apart from a database error.

type ReadResult = {
  data: unknown;
  error: { message: string; code?: string; hint?: string } | null;
  status: number;
  statusText: string;
};

let nextResult: ReadResult;

function makeChain() {
  const chain: Record<string, unknown> = {};
  for (const m of ["select", "eq", "or", "in", "is", "order", "limit"]) {
    chain[m] = () => chain;
  }
  chain.then = (
    resolve: (v: ReadResult) => unknown,
    reject: (e: unknown) => unknown,
  ) => Promise.resolve(nextResult).then(resolve, reject);
  return chain;
}

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ from: () => makeChain(), rpc: () => makeChain() }),
  serverUrl: () => "http://localhost",
}));

import { exportSqlTable } from "@/server/dsar-export";

const USER_ID = "00000000-0000-4000-8000-000000000001";

describe("exportSqlTable read failures", () => {
  beforeEach(() => {
    nextResult = {
      data: null,
      error: { message: "Project not specified" },
      status: 200,
      statusText: "OK",
    };
  });

  it("names the table, keeps the body text and appends the HTTP status", async () => {
    await expect(
      exportSqlTable(USER_ID, Buffer.alloc(32), new AbortController().signal),
    ).rejects.toThrow("users read failed: Project not specified [status=200 OK]");
  });

  it("includes the PostgREST code and hint when they are present", async () => {
    nextResult = {
      data: null,
      error: { message: "no such table", code: "42P01", hint: "reload the schema cache" },
      status: 404,
      statusText: "Not Found",
    };
    await expect(
      exportSqlTable(USER_ID, Buffer.alloc(32), new AbortController().signal),
    ).rejects.toThrow(
      "users read failed: no such table [status=404 Not Found code=42P01 hint=reload the schema cache]",
    );
  });

  it("does not turn a read that returned no error into a failure", async () => {
    nextResult = { data: [], error: null, status: 200, statusText: "OK" };
    // The first read passes (no rows); the run proceeds to later reads, which
    // see the same stub. It must not throw a `read failed` error.
    await expect(
      exportSqlTable(USER_ID, Buffer.alloc(32), new AbortController().signal),
    ).resolves.toBeDefined();
  });
});
