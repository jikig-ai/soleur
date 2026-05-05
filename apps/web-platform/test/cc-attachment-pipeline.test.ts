/**
 * Unit test for the shared `persistAndDownloadAttachments` helper that
 * cc-dispatcher and agent-runner both call to (a) validate attachment
 * refs against the per-user/per-conv `pathPrefix`, (b) insert
 * `message_attachments` rows, (c) download files into the user's
 * workspace, and (d) build the `attachmentContext` text appended to
 * the LLM prompt. See plan #3254.
 *
 * The test mocks the Supabase service client and the `node:fs/promises`
 * `mkdir`/`writeFile` boundary; the helper is otherwise pure.
 */
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { AttachmentRef } from "@/lib/types";

// Mock fs/promises BEFORE importing the helper. `vi.mock` is hoisted.
const mkdirMock = vi.fn().mockResolvedValue(undefined);
const writeFileMock = vi.fn().mockResolvedValue(undefined);
vi.mock("fs/promises", () => ({
  mkdir: (...args: unknown[]) => mkdirMock(...args),
  writeFile: (...args: unknown[]) => writeFileMock(...args),
  readFile: vi.fn(),
}));

// Build a stateful mock supabase client. Each invocation of `from(table)`
// returns a chain that records its calls. The helper expects:
//   - `from("message_attachments").insert(rows)` returns `{ error: null }`.
//   - `from("users").select(...).eq(...).single()` returns the workspace path.
//   - `storage.from("chat-attachments").download(path)` returns `{ data, error }`.
function makeSupabaseMock(opts: {
  workspacePath: string | null;
  insertError?: Error | null;
  download: (storagePath: string) =>
    | { data: { arrayBuffer: () => Promise<ArrayBuffer> }; error: null }
    | { data: null; error: Error };
}) {
  const insertCalls: unknown[] = [];

  const usersChain = {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    single: vi.fn().mockResolvedValue({
      data: opts.workspacePath ? { workspace_path: opts.workspacePath } : null,
      error: null,
    }),
  };

  const messageAttachmentsChain = {
    insert: vi.fn().mockImplementation(async (rows: unknown) => {
      insertCalls.push(rows);
      return { error: opts.insertError ?? null };
    }),
  };

  const storageBucket = {
    download: vi.fn().mockImplementation(async (storagePath: string) => {
      return opts.download(storagePath);
    }),
  };

  return {
    insertCalls,
    messageAttachmentsChain,
    client: {
      from: vi.fn().mockImplementation((table: string) => {
        if (table === "users") return usersChain;
        if (table === "message_attachments") return messageAttachmentsChain;
        throw new Error(`unexpected table: ${table}`);
      }),
      storage: {
        from: vi.fn().mockImplementation((bucket: string) => {
          if (bucket !== "chat-attachments") {
            throw new Error(`unexpected bucket: ${bucket}`);
          }
          return storageBucket;
        }),
      },
    },
  };
}

import { persistAndDownloadAttachments } from "@/server/attachment-pipeline";

const userId = "00000000-0000-0000-0000-aaaaaaaaaaaa";
const conversationId = "00000000-0000-0000-0000-bbbbbbbbbbbb";
const messageId = "00000000-0000-0000-0000-cccccccccccc";

function makeAttachment(over: Partial<AttachmentRef> = {}): AttachmentRef {
  return {
    storagePath: `${userId}/${conversationId}/screenshot.png`,
    filename: "screenshot.png",
    contentType: "image/png",
    sizeBytes: 1024,
    ...over,
  };
}

const buf = new Uint8Array([0x89, 0x50, 0x4e, 0x47]).buffer as ArrayBuffer;

beforeEach(() => {
  mkdirMock.mockClear();
  writeFileMock.mockClear();
});

describe("persistAndDownloadAttachments", () => {
  it("inserts message_attachments rows, downloads each file, returns attachmentContext", async () => {
    const supabase = makeSupabaseMock({
      workspacePath: "/workspace/u1",
      download: () => ({
        data: { arrayBuffer: async () => buf },
        error: null,
      }),
    });

    const att1 = makeAttachment({
      filename: "a.png",
      storagePath: `${userId}/${conversationId}/a.png`,
    });
    const att2 = makeAttachment({
      filename: "b.jpeg",
      storagePath: `${userId}/${conversationId}/b.jpeg`,
      contentType: "image/jpeg",
    });

    const { attachmentContext } = await persistAndDownloadAttachments({
      supabase: supabase.client as never,
      userId,
      conversationId,
      messageId,
      attachments: [att1, att2],
    });

    expect(supabase.insertCalls).toHaveLength(1);
    const inserted = supabase.insertCalls[0] as Array<{ message_id: string }>;
    expect(inserted).toHaveLength(2);
    expect(inserted[0]!.message_id).toBe(messageId);
    expect(inserted[1]!.message_id).toBe(messageId);

    expect(mkdirMock).toHaveBeenCalledTimes(1);
    expect(writeFileMock).toHaveBeenCalledTimes(2);

    expect(attachmentContext).toBeDefined();
    expect(attachmentContext).toContain("The user attached the following files:");
    expect(attachmentContext).toContain("a.png");
    expect(attachmentContext).toContain("b.jpeg");
    expect(attachmentContext).toContain("/workspace/u1/attachments/");
  });

  it("rejects attachments outside the per-user/per-conversation prefix (path-traversal guard)", async () => {
    const supabase = makeSupabaseMock({
      workspacePath: "/workspace/u1",
      download: () => ({
        data: { arrayBuffer: async () => buf },
        error: null,
      }),
    });

    const evil = makeAttachment({
      // Cross-user storagePath — different userId prefix
      storagePath: `00000000-0000-0000-0000-deadbeef/${conversationId}/x.png`,
    });

    await expect(
      persistAndDownloadAttachments({
        supabase: supabase.client as never,
        userId,
        conversationId,
        messageId,
        attachments: [evil],
      }),
    ).rejects.toThrow(/Attachment not found/);

    expect(supabase.insertCalls).toHaveLength(0);
    expect(writeFileMock).not.toHaveBeenCalled();
  });

  it("rejects unsupported content types", async () => {
    const supabase = makeSupabaseMock({
      workspacePath: "/workspace/u1",
      download: () => ({
        data: { arrayBuffer: async () => buf },
        error: null,
      }),
    });

    const evil = makeAttachment({
      contentType: "application/x-msdownload",
    });

    await expect(
      persistAndDownloadAttachments({
        supabase: supabase.client as never,
        userId,
        conversationId,
        messageId,
        attachments: [evil],
      }),
    ).rejects.toThrow(/Unsupported file type/);
  });

  it("survives a single download failure — others land, failed one omitted", async () => {
    const supabase = makeSupabaseMock({
      workspacePath: "/workspace/u1",
      download: (storagePath) => {
        if (storagePath.endsWith("b.png")) {
          return { data: null, error: new Error("storage 404") };
        }
        return { data: { arrayBuffer: async () => buf }, error: null };
      },
    });

    const att1 = makeAttachment({
      filename: "a.png",
      storagePath: `${userId}/${conversationId}/a.png`,
    });
    const att2 = makeAttachment({
      filename: "b.png",
      storagePath: `${userId}/${conversationId}/b.png`,
    });

    const { attachmentContext } = await persistAndDownloadAttachments({
      supabase: supabase.client as never,
      userId,
      conversationId,
      messageId,
      attachments: [att1, att2],
    });

    expect(writeFileMock).toHaveBeenCalledTimes(1);
    expect(attachmentContext).toContain("a.png");
    expect(attachmentContext).not.toContain("b.png");
  });

  it("returns attachmentContext: undefined when workspace_path lookup is empty", async () => {
    const supabase = makeSupabaseMock({
      workspacePath: null,
      download: () => ({
        data: { arrayBuffer: async () => buf },
        error: null,
      }),
    });

    const { attachmentContext } = await persistAndDownloadAttachments({
      supabase: supabase.client as never,
      userId,
      conversationId,
      messageId,
      attachments: [makeAttachment()],
    });

    // The metadata insert still ran (FK satisfied by messageId), but the
    // local-disk download was skipped because we have nowhere to write.
    expect(supabase.insertCalls).toHaveLength(1);
    expect(writeFileMock).not.toHaveBeenCalled();
    expect(attachmentContext).toBeUndefined();
  });

  it("sanitizes filenames containing path separators", async () => {
    const supabase = makeSupabaseMock({
      workspacePath: "/workspace/u1",
      download: () => ({
        data: { arrayBuffer: async () => buf },
        error: null,
      }),
    });

    const evil = makeAttachment({
      filename: "..\\..\\etc/passwd",
      storagePath: `${userId}/${conversationId}/file.png`,
    });

    await persistAndDownloadAttachments({
      supabase: supabase.client as never,
      userId,
      conversationId,
      messageId,
      attachments: [evil],
    });

    const inserted = supabase.insertCalls[0] as Array<{ filename: string }>;
    expect(inserted[0]!.filename).not.toContain("/");
    expect(inserted[0]!.filename).not.toContain("\\");
  });
});
