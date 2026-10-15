import { describe, it, expect, beforeEach, vi } from "vitest";

// A failed table read in `exportSqlTable` must say what the HTTP layer said,
// not only the body text. A gateway answered `Project not specified` on one
// DSAR read of a nightly run; postgrest-js turns a non-JSON body into
// `error = { message: body }` and leaves the status on the result object, so
// the thrown message could not be told apart from a database error.
// `dsar-export-read-error-sites.test.ts` pins that every other site does the
// same; this drives the first read end to end.

type ReadResult = {
  data: unknown;
  error: { message: string; code?: string; hint?: string; details?: string } | null;
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
const run = () =>
  exportSqlTable(USER_ID, Buffer.alloc(32), new AbortController().signal);

describe("exportSqlTable read failures", () => {
  beforeEach(() => {
    nextResult = {
      data: null,
      error: { message: "Project not specified" },
      status: 502,
      statusText: "Bad Gateway",
    };
  });

  it("names the table, keeps the body text and appends the HTTP status", async () => {
    await expect(run()).rejects.toThrow(
      /^users read failed: Project not specified \[status=502 Bad Gateway\]$/,
    );
  });

  it("includes the PostgREST code and leaves out hint and details", async () => {
    nextResult = {
      data: null,
      error: {
        message: "no such table",
        code: "42P01",
        hint: "Key (email)=(a@example.com)",
        details: "Key (email)=(b@example.com)",
      },
      status: 404,
      statusText: "Not Found",
    };
    await expect(run()).rejects.toThrow(
      /^users read failed: no such table \[status=404 Not Found code=42P01\]$/,
    );
  });

  it("does not turn a read that returned no error into a failure", async () => {
    nextResult = { data: [], error: null, status: 200, statusText: "OK" };
    // Every read sees the same empty stub; none may throw a `read failed` error.
    const files = await run();
    expect(Array.isArray(files)).toBe(true);
  });
});
