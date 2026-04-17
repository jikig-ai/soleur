import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import { createShare, listShares, revokeShare } from "@/server/kb-share";
import { shareSupabaseFromMock } from "./helpers/share-mocks";

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  reportSilentFallbackWarning: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

function hex(buf: Buffer): string {
  return createHash("sha256").update(buf).digest("hex");
}

let tmpWorkspace: string;
let kbRoot: string;

beforeEach(() => {
  vi.clearAllMocks();
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "kb-share-unit-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

/**
 * Build a service client mock whose `.from(table)` dispatches via
 * shareSupabaseFromMock. Returns { client, eqSpy } so tests can assert
 * the filter chain shape (learning 2026-04-10: URL/query-shape assertions
 * in mocks prevent "mock returns data for any query" silent passes).
 */
function makeServiceClient(opts: Parameters<typeof shareSupabaseFromMock>[0]) {
  const impl = shareSupabaseFromMock(opts);
  return { from: (table: string) => impl(table) } as unknown as {
    from: (table: string) => unknown;
  };
}

describe("createShare — happy path", () => {
  it("creates a new share link for an unshared markdown file", async () => {
    const bytes = Buffer.from("# hi");
    fs.writeFileSync(path.join(kbRoot, "readme.md"), bytes);
    const insertSpy = vi.fn().mockResolvedValue({ error: null });
    const client = makeServiceClient({
      kb_share_links: { shareRow: null, shareError: null, insertSpy },
    });

    const result = await createShare(client as never, "user-1", kbRoot, "readme.md");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.token).toMatch(/^[A-Za-z0-9_-]{43}$/); // 256-bit base64url
    expect(result.url).toBe(`/shared/${result.token}`);
    expect(result.documentPath).toBe("readme.md");
    expect(result.size).toBe(bytes.length);
    expect(insertSpy).toHaveBeenCalledTimes(1);
    const payload = insertSpy.mock.calls[0][0];
    expect(payload.user_id).toBe("user-1");
    expect(payload.document_path).toBe("readme.md");
    expect(payload.content_sha256).toBe(hex(bytes));
    expect(payload.token).toBe(result.token);
  });

  it("is idempotent on unchanged content — returns existing token", async () => {
    const bytes = Buffer.from("same content");
    fs.writeFileSync(path.join(kbRoot, "doc.md"), bytes);
    const insertSpy = vi.fn().mockResolvedValue({ error: null });
    const client = makeServiceClient({
      kb_share_links: {
        shareRow: {
          id: "share-1",
          token: "existing-token",
          content_sha256: hex(bytes),
        },
        insertSpy,
      },
    });

    const result = await createShare(client as never, "user-1", kbRoot, "doc.md");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.token).toBe("existing-token");
    expect(insertSpy).not.toHaveBeenCalled();
  });

  it("re-issues on content drift — revokes stale row, inserts fresh token", async () => {
    const newBytes = Buffer.from("version 2");
    fs.writeFileSync(path.join(kbRoot, "doc.md"), newBytes);
    const insertSpy = vi.fn().mockResolvedValue({ error: null });
    const updateSpy = vi.fn().mockReturnValue({ error: null });
    const client = makeServiceClient({
      kb_share_links: {
        shareRow: {
          id: "share-1",
          token: "stale-token",
          content_sha256: hex(Buffer.from("version 1")),
        },
        insertSpy,
        updateSpy,
      },
    });

    const result = await createShare(client as never, "user-1", kbRoot, "doc.md");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.token).not.toBe("stale-token");
    expect(updateSpy).toHaveBeenCalled();
    expect(insertSpy).toHaveBeenCalledTimes(1);
    expect(insertSpy.mock.calls[0][0].content_sha256).toBe(hex(newBytes));
  });
});

describe("createShare — validation failures", () => {
  it("rejects null-byte in documentPath with status 400 code invalid-path", async () => {
    const client = makeServiceClient({
      kb_share_links: { shareRow: null },
    });

    const result = await createShare(client as never, "user-1", kbRoot, "foo\0bar.md");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(400);
    expect(result.code).toBe("invalid-path");
  });

  it("rejects path escaping kbRoot with status 400 code invalid-path", async () => {
    fs.writeFileSync(path.join(tmpWorkspace, "outside.md"), "x");
    const client = makeServiceClient({
      kb_share_links: { shareRow: null },
    });

    const result = await createShare(client as never, "user-1", kbRoot, "../outside.md");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(400);
    expect(result.code).toBe("invalid-path");
  });

  it("rejects symlinks pointing outside kbRoot as invalid-path (realpath guard)", async () => {
    // Symlink inside kbRoot but target is outside. isPathInWorkspace
    // resolves realpath → outside → "invalid-path" before O_NOFOLLOW.
    const outside = path.join(tmpWorkspace, "real.md");
    fs.writeFileSync(outside, "secret");
    fs.symlinkSync(outside, path.join(kbRoot, "link-out.md"));
    const client = makeServiceClient({
      kb_share_links: { shareRow: null },
    });

    const result = await createShare(client as never, "user-1", kbRoot, "link-out.md");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(400);
    expect(result.code).toBe("invalid-path");
  });

  it("rejects terminal symlinks to in-kbRoot files as symlink-rejected (O_NOFOLLOW guard)", async () => {
    // Symlink inside kbRoot pointing to another file inside kbRoot.
    // isPathInWorkspace realpath resolves inside kbRoot → passes.
    // O_NOFOLLOW open then raises ELOOP → "symlink-rejected".
    const innerTarget = path.join(kbRoot, "target.md");
    fs.writeFileSync(innerTarget, "target contents");
    fs.symlinkSync(innerTarget, path.join(kbRoot, "link-in.md"));
    const client = makeServiceClient({
      kb_share_links: { shareRow: null },
    });

    const result = await createShare(client as never, "user-1", kbRoot, "link-in.md");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(400);
    expect(result.code).toBe("symlink-rejected");
  });

  it("rejects missing file with status 404 code not-found", async () => {
    const client = makeServiceClient({
      kb_share_links: { shareRow: null },
    });

    const result = await createShare(client as never, "user-1", kbRoot, "missing.md");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(404);
    expect(result.code).toBe("not-found");
  });

  it("rejects directory target with status 400 code not-a-file", async () => {
    fs.mkdirSync(path.join(kbRoot, "subdir"));
    const client = makeServiceClient({
      kb_share_links: { shareRow: null },
    });

    const result = await createShare(client as never, "user-1", kbRoot, "subdir");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(400);
    expect(result.code).toBe("not-a-file");
  });

  it("rejects oversized file with status 413 code too-large", async () => {
    const big = Buffer.alloc(50 * 1024 * 1024 + 1);
    fs.writeFileSync(path.join(kbRoot, "huge.pdf"), big);
    const client = makeServiceClient({
      kb_share_links: { shareRow: null },
    });

    const result = await createShare(client as never, "user-1", kbRoot, "huge.pdf");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(413);
    expect(result.code).toBe("too-large");
  });
});

describe("createShare — concurrent retry (23505 unique violation)", () => {
  it("reads winner's row and returns its token when content hash matches", async () => {
    const bytes = Buffer.from("hello");
    fs.writeFileSync(path.join(kbRoot, "note.md"), bytes);

    // First maybeSingle call (pre-insert check) returns null.
    // Insert fails with 23505.
    // Second maybeSingle call (winner lookup) returns winner with matching hash.
    let maybeSingleCall = 0;
    const winner = { token: "winner-token", content_sha256: hex(bytes) };
    const client = {
      from: () => ({
        select: () => {
          const eqChain: Record<string, unknown> = {};
          eqChain.eq = () => eqChain;
          eqChain.maybeSingle = () => {
            maybeSingleCall++;
            if (maybeSingleCall === 1) return Promise.resolve({ data: null, error: null });
            return Promise.resolve({ data: winner, error: null });
          };
          eqChain.order = () => Promise.resolve({ data: [], error: null });
          eqChain.single = () => Promise.resolve({ data: null, error: null });
          return eqChain;
        },
        insert: vi.fn().mockResolvedValue({ error: { code: "23505" } }),
        update: () => ({ eq: () => ({ error: null }) }),
      }),
    };

    const result = await createShare(client as never, "user-1", kbRoot, "note.md");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.token).toBe("winner-token");
  });

  it("returns status 409 code concurrent-retry when winner's hash differs", async () => {
    const bytes = Buffer.from("hello");
    fs.writeFileSync(path.join(kbRoot, "note.md"), bytes);

    let maybeSingleCall = 0;
    const winner = { token: "winner-token", content_sha256: "deadbeef" };
    const client = {
      from: () => ({
        select: () => {
          const eqChain: Record<string, unknown> = {};
          eqChain.eq = () => eqChain;
          eqChain.maybeSingle = () => {
            maybeSingleCall++;
            if (maybeSingleCall === 1) return Promise.resolve({ data: null, error: null });
            return Promise.resolve({ data: winner, error: null });
          };
          eqChain.order = () => Promise.resolve({ data: [], error: null });
          eqChain.single = () => Promise.resolve({ data: null, error: null });
          return eqChain;
        },
        insert: vi.fn().mockResolvedValue({ error: { code: "23505" } }),
        update: () => ({ eq: () => ({ error: null }) }),
      }),
    };

    const result = await createShare(client as never, "user-1", kbRoot, "note.md");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(409);
    expect(result.code).toBe("concurrent-retry");
  });
});

describe("listShares", () => {
  it("returns empty array when user has no shares", async () => {
    const client = makeServiceClient({
      kb_share_links: { listData: [] },
    });

    const result = await listShares(client as never, "user-1");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.shares).toEqual([]);
  });

  it("returns records mapped to camelCase (token, documentPath, createdAt, revoked)", async () => {
    const rows = [
      {
        token: "t1",
        document_path: "a.md",
        created_at: "2026-04-17T12:00:00Z",
        revoked: false,
      },
      {
        token: "t2",
        document_path: "b.md",
        created_at: "2026-04-16T12:00:00Z",
        revoked: true,
      },
    ];
    const client = makeServiceClient({
      kb_share_links: { listData: rows },
    });

    const result = await listShares(client as never, "user-1");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.shares).toEqual([
      {
        token: "t1",
        documentPath: "a.md",
        createdAt: "2026-04-17T12:00:00Z",
        revoked: false,
      },
      {
        token: "t2",
        documentPath: "b.md",
        createdAt: "2026-04-16T12:00:00Z",
        revoked: true,
      },
    ]);
  });

  it("asserts user_id filter is applied to the query (URL-shape assertion)", async () => {
    const eqSpy = vi.fn();
    const eqChain: Record<string, unknown> = {};
    eqChain.eq = (...args: unknown[]) => {
      eqSpy(...args);
      return eqChain;
    };
    eqChain.order = () => Promise.resolve({ data: [], error: null });
    const client = {
      from: () => ({
        select: vi.fn().mockReturnValue(eqChain),
      }),
    };

    await listShares(client as never, "user-1");

    // MUST filter by user_id at the query layer (never returns another user's rows).
    expect(eqSpy).toHaveBeenCalledWith("user_id", "user-1");
  });

  it("filters by documentPath when provided", async () => {
    const eqSpy = vi.fn();
    const eqChain: Record<string, unknown> = {};
    eqChain.eq = (...args: unknown[]) => {
      eqSpy(...args);
      return eqChain;
    };
    eqChain.order = () => Promise.resolve({ data: [], error: null });
    const client = {
      from: () => ({
        select: vi.fn().mockReturnValue(eqChain),
      }),
    };

    await listShares(client as never, "user-1", { documentPath: "readme.md" });

    expect(eqSpy).toHaveBeenCalledWith("user_id", "user-1");
    expect(eqSpy).toHaveBeenCalledWith("document_path", "readme.md");
  });

  it("returns status 500 code db-error on DB failure", async () => {
    const eqChain: Record<string, unknown> = {};
    eqChain.eq = () => eqChain;
    eqChain.order = () =>
      Promise.resolve({ data: null, error: { message: "connection lost" } });
    const client = {
      from: () => ({
        select: () => eqChain,
      }),
    };

    const result = await listShares(client as never, "user-1");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(500);
    expect(result.code).toBe("db-error");
  });
});

describe("revokeShare", () => {
  it("revokes a link owned by the caller", async () => {
    const updateEqSpy = vi.fn().mockResolvedValue({ error: null });
    const client = {
      from: () => ({
        select: () => ({
          eq: () => ({
            single: () =>
              Promise.resolve({
                data: { id: "share-1", user_id: "user-1", document_path: "readme.md" },
                error: null,
              }),
          }),
        }),
        update: () => ({ eq: updateEqSpy }),
      }),
    };

    const result = await revokeShare(client as never, "user-1", "tok-1");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.token).toBe("tok-1");
    expect(updateEqSpy).toHaveBeenCalledWith("id", "share-1");
  });

  it("returns status 403 code forbidden when revoking another user's token", async () => {
    const client = {
      from: () => ({
        select: () => ({
          eq: () => ({
            single: () =>
              Promise.resolve({
                data: { id: "share-1", user_id: "user-2", document_path: "secret.md" },
                error: null,
              }),
          }),
        }),
        update: () => ({ eq: vi.fn() }),
      }),
    };

    const result = await revokeShare(client as never, "user-1", "tok-1");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(403);
    expect(result.code).toBe("forbidden");
  });

  it("returns status 404 code not-found for unknown token", async () => {
    const client = {
      from: () => ({
        select: () => ({
          eq: () => ({
            single: () =>
              Promise.resolve({
                data: null,
                error: { message: "no rows" },
              }),
          }),
        }),
        update: () => ({ eq: vi.fn() }),
      }),
    };

    const result = await revokeShare(client as never, "user-1", "missing-token");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(404);
    expect(result.code).toBe("not-found");
  });

  it("asserts token filter is applied to the select chain (URL-shape assertion)", async () => {
    const selectEqSpy = vi.fn();
    const client = {
      from: () => ({
        select: () => ({
          eq: (...args: unknown[]) => {
            selectEqSpy(...args);
            return {
              single: () =>
                Promise.resolve({
                  data: { id: "share-1", user_id: "user-1", document_path: "readme.md" },
                  error: null,
                }),
            };
          },
        }),
        update: () => ({ eq: () => Promise.resolve({ error: null }) }),
      }),
    };

    await revokeShare(client as never, "user-1", "tok-1");

    expect(selectEqSpy).toHaveBeenCalledWith("token", "tok-1");
  });
});
