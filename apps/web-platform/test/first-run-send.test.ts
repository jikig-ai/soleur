import { describe, it, expect, vi, beforeEach } from "vitest";
import type { AttachmentRef } from "@/lib/types";

// Sanctioned client mirror of the server observability helper. Mocked so the
// captured op/extra payloads are observable without a real Sentry transport.
const mockReport = vi.fn();
vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: (err: unknown, opts: unknown) => mockReport(err, opts),
}));

import { runFirstRunSend } from "@/lib/first-run-send";

const REAL_ID = "0a1b2c3d-0000-4000-8000-00000000abcd";

type UploadOpts = { signal?: AbortSignal; onUploaded?: (ref: AttachmentRef) => void };
type Live = { conversationId: string | null; connected: boolean; sessionConfirmed: boolean };

function makeFile(name: string): File {
  return new File(["synthetic"], name, { type: "text/markdown" });
}

function refFor(file: File): AttachmentRef {
  return {
    storagePath: `user/${REAL_ID}/${file.name}`,
    filename: file.name,
    contentType: "text/markdown",
    sizeBytes: 9,
  };
}

function setup(over: { live?: Partial<Live> } = {}) {
  const log: string[] = [];
  const live: Live = {
    conversationId: REAL_ID,
    connected: true,
    sessionConfirmed: true,
    ...over.live,
  };
  const getLive = vi.fn(() => live);
  const upload = vi.fn(async (files: File[], _id: string, _opts?: UploadOpts): Promise<AttachmentRef[]> => {
    log.push("upload");
    return files.map(refFor);
  });
  const send = vi.fn((..._args: unknown[]) => {
    log.push("send");
  });
  return { log, live, getLive, upload, send };
}

function ops(): string[] {
  return mockReport.mock.calls.map(
    (c) => (c[1] as { op?: string }).op ?? "",
  );
}

function callFor(op: string) {
  const c = mockReport.mock.calls.find((x) => (x[1] as { op?: string }).op === op);
  return c as [unknown, { feature: string; op: string; extra?: Record<string, unknown> }] | undefined;
}

describe("runFirstRunSend", () => {
  beforeEach(() => {
    mockReport.mockClear();
  });

  it("files + empty message -> uploads once, sends exactly once with refs", async () => {
    const h = setup();
    const f = makeFile("a.md");
    const res = await runFirstRunSend({
      msgParam: null,
      files: [f],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.upload).toHaveBeenCalledTimes(1);
    expect(h.upload).toHaveBeenCalledWith(
      [f],
      REAL_ID,
      expect.objectContaining({ signal: expect.any(AbortSignal), onUploaded: expect.any(Function) }),
    );
    expect(h.send).toHaveBeenCalledTimes(1);
    expect(h.send).toHaveBeenCalledWith("", [refFor(f)]);
    expect(res).toEqual({ sent: true, retry: false });
  });

  it("files + message -> upload completes BEFORE the single send(msg, refs)", async () => {
    const h = setup();
    const f = makeFile("a.md");
    await runFirstRunSend({
      msgParam: "hi",
      files: [f],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.log).toEqual(["upload", "send"]);
    expect(h.send).toHaveBeenCalledTimes(1);
    expect(h.send).toHaveBeenCalledWith("hi", [refFor(f)]);
  });

  it("no files + message -> send(msg) with exact arity, upload never called", async () => {
    const h = setup();
    const res = await runFirstRunSend({
      msgParam: "hi",
      files: [],
      conversationId: null,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.upload).not.toHaveBeenCalled();
    expect(h.send).toHaveBeenCalledTimes(1);
    // Exact arity: chat-page.test.tsx asserts sendMessage("help with pricing").
    expect(h.send.mock.calls[0]).toEqual(["hi"]);
    expect(res).toEqual({ sent: true, retry: false });
  });

  it("no files + no message -> nothing happens", async () => {
    const h = setup();
    const res = await runFirstRunSend({
      msgParam: null,
      files: [],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.upload).not.toHaveBeenCalled();
    expect(h.send).not.toHaveBeenCalled();
    expect(res).toEqual({ sent: false, retry: false });
  });

  it("all uploads fail + message -> message still sent once, text only", async () => {
    const h = setup();
    h.upload.mockResolvedValueOnce([]);
    const res = await runFirstRunSend({
      msgParam: "hi",
      files: [makeFile("a.md")],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.send).toHaveBeenCalledTimes(1);
    expect(h.send.mock.calls[0]).toEqual(["hi"]);
    expect(res).toEqual({ sent: true, retry: false });
    expect(ops()).toEqual(["first-run-batch-failed"]);
    expect(callFor("first-run-batch-failed")![1].extra).toEqual({ attempted: 1, uploaded: 0 });
  });

  it("all uploads fail + no message -> nothing sent", async () => {
    const h = setup();
    h.upload.mockResolvedValueOnce([]);
    const res = await runFirstRunSend({
      msgParam: null,
      files: [makeFile("a.md")],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.send).not.toHaveBeenCalled();
    expect(res.sent).toBe(false);
    expect(ops()).toEqual(["first-run-batch-failed"]);
  });

  it("stale-id window (connected, sessionConfirmed=false, id unchanged) -> not ready, retry, no send", async () => {
    const h = setup({ live: { sessionConfirmed: false } });
    const res = await runFirstRunSend({
      msgParam: "hi",
      files: [makeFile("a.md")],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.send).not.toHaveBeenCalled();
    expect(res).toEqual({ sent: false, retry: true });
    expect(ops()).toContain("first-run-send-dropped");
  });

  it("id changed while uploading (open socket, confirmed) -> not ready, retry", async () => {
    const h = setup({ live: { conversationId: "ffffffff-0000-4000-8000-000000000000" } });
    const res = await runFirstRunSend({
      msgParam: "hi",
      files: [makeFile("a.md")],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.send).not.toHaveBeenCalled();
    expect(res).toEqual({ sent: false, retry: true });
  });

  it("socket closed (id unchanged, confirmed) -> never sends into a dead socket, dropped captured", async () => {
    const h = setup({ live: { connected: false } });
    const res = await runFirstRunSend({
      msgParam: "hi",
      files: [makeFile("a.md")],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.send).not.toHaveBeenCalled();
    expect(res).toEqual({ sent: false, retry: true });
    expect(ops()).toContain("first-run-send-dropped");
  });

  it("re-reads getLive AFTER the upload (live state changes inside upload)", async () => {
    const h = setup();
    h.upload.mockImplementationOnce(async (files: File[]) => {
      // The socket drops while the upload is in flight.
      h.live.connected = false;
      return files.map(refFor);
    });
    const res = await runFirstRunSend({
      msgParam: "hi",
      files: [makeFile("a.md")],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.send).not.toHaveBeenCalled();
    expect(res.retry).toBe(true);
  });

  it("partial failure (2 of 3) -> sends the 2 and captures counts", async () => {
    const h = setup();
    const files = [makeFile("a.md"), makeFile("b.md"), makeFile("c.md")];
    h.upload.mockResolvedValueOnce([refFor(files[0]), refFor(files[1])]);
    await runFirstRunSend({
      msgParam: "hi",
      files,
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.send).toHaveBeenCalledTimes(1);
    expect(h.send).toHaveBeenCalledWith("hi", [refFor(files[0]), refFor(files[1])]);
    const c = callFor("first-run-upload-partial");
    expect(c).toBeDefined();
    expect(c![1].extra).toEqual({ attempted: 3, uploaded: 2 });
    expect(c![1].feature).toBe("kb-chat");
    expect(ops()).toEqual(["first-run-upload-partial"]);
  });

  it("upload never resolves -> deadline fires, text-only send, timeout captured", async () => {
    const h = setup();
    h.upload.mockImplementationOnce(() => new Promise<AttachmentRef[]>(() => {}));
    const res = await runFirstRunSend({
      msgParam: "hi",
      files: [makeFile("a.md")],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
      deadlineMs: 20,
    });
    expect(h.send).toHaveBeenCalledTimes(1);
    expect(h.send.mock.calls[0]).toEqual(["hi"]);
    expect(res.sent).toBe(true);
    expect(ops()).toEqual(["first-run-upload-timeout"]);
    expect(callFor("first-run-upload-timeout")![1].extra).toEqual({
      attempted: 1,
      uploaded: 0,
      deadlineMs: 20,
    });
  });

  it("upload throws -> same as all-fail, never rejects, counts captured", async () => {
    const h = setup();
    h.upload.mockRejectedValueOnce(new Error("boom"));
    const res = await runFirstRunSend({
      msgParam: "hi",
      files: [makeFile("a.md"), makeFile("b.md")],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.send.mock.calls).toEqual([["hi"]]);
    expect(res.sent).toBe(true);
    const c = callFor("first-run-batch-failed");
    expect(c).toBeDefined();
    expect(c![1].extra).toEqual({ attempted: 2, uploaded: 0 });
  });

  it("does not leak signed-URL tokens to Sentry (only message length)", async () => {
    const h = setup();
    h.upload.mockRejectedValueOnce(new Error("PUT failed https://x/?token=SECRET"));
    await runFirstRunSend({
      msgParam: "hi",
      files: [makeFile("a.md")],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(mockReport).toHaveBeenCalled();
    for (const [err, opts] of mockReport.mock.calls) {
      const flat = `${err instanceof Error ? err.message : JSON.stringify(err)}|${JSON.stringify(opts)}`;
      expect(flat).not.toContain("SECRET");
    }
    const c = callFor("first-run-batch-failed");
    expect(String((c![0] as Error).message)).toMatch(/length \d+/);
  });

  it("never rejects when send itself throws", async () => {
    const h = setup();
    h.send.mockImplementationOnce(() => {
      throw new Error("send blew up");
    });
    const res = await runFirstRunSend({
      msgParam: "hi",
      files: [makeFile("a.md")],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(res.sent).toBe(false);
    expect(mockReport).toHaveBeenCalled();
  });
  it("default deadline is 45_000 ms (no deadlineMs passed)", async () => {
    vi.useFakeTimers();
    try {
      const h = setup();
      h.upload.mockImplementationOnce(() => new Promise<AttachmentRef[]>(() => {}));
      let done = false;
      const p = runFirstRunSend({
        msgParam: "hi",
        files: [makeFile("a.md")],
        conversationId: REAL_ID,
        getLive: h.getLive,
        upload: h.upload,
        send: h.send,
      }).then((r) => {
        done = true;
        return r;
      });
      await vi.advanceTimersByTimeAsync(44_999);
      expect(done).toBe(false);
      await vi.advanceTimersByTimeAsync(1);
      await p;
      expect(done).toBe(true);
      expect(callFor("first-run-upload-timeout")![1].extra).toMatchObject({ deadlineMs: 45_000 });
    } finally {
      vi.useRealTimers();
    }
  });

  it("a rejection that lands AFTER the deadline is not an unhandled rejection", async () => {
    const unhandled: unknown[] = [];
    const onUnhandled = (reason: unknown) => unhandled.push(reason);
    process.on("unhandledRejection", onUnhandled);
    try {
      const h = setup();
      let rejectLate!: (e: Error) => void;
      h.upload.mockImplementationOnce(
        () => new Promise<AttachmentRef[]>((_, rej) => (rejectLate = rej)),
      );
      await runFirstRunSend({
        msgParam: "hi",
        files: [makeFile("a.md")],
        conversationId: REAL_ID,
        getLive: h.getLive,
        upload: h.upload,
        send: h.send,
        deadlineMs: 10,
      });
      rejectLate(new Error("late boom"));
      await new Promise((r) => setTimeout(r, 20));
      expect(unhandled).toEqual([]);
    } finally {
      process.off("unhandledRejection", onUnhandled);
    }
  });

  it("uploads under the CAPTURED id, not whatever getLive reports at upload time", async () => {
    const OTHER = "ffffffff-0000-4000-8000-000000000000";
    const h = setup({ live: { conversationId: OTHER } });
    h.upload.mockImplementationOnce(async (files: File[]) => {
      // The session settles onto the captured id only by the time the upload ends.
      h.live.conversationId = REAL_ID;
      return files.map(refFor);
    });
    const f = makeFile("a.md");
    const res = await runFirstRunSend({
      msgParam: "hi",
      files: [f],
      conversationId: REAL_ID,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.upload.mock.calls[0]![1]).toBe(REAL_ID);
    expect(h.send).toHaveBeenCalledWith("hi", [refFor(f)]);
    expect(res).toEqual({ sent: true, retry: false });
  });

  it("files but no conversation id (defensive) -> no upload, no send, dropped captured, retry", async () => {
    const h = setup();
    const res = await runFirstRunSend({
      msgParam: "hi",
      files: [makeFile("a.md")],
      conversationId: null,
      getLive: h.getLive,
      upload: h.upload,
      send: h.send,
    });
    expect(h.upload).not.toHaveBeenCalled();
    expect(h.send).not.toHaveBeenCalled();
    expect(res).toEqual({ sent: false, retry: true });
    expect(callFor("first-run-send-dropped")![1].extra).toEqual({ attempted: 1 });
  });

  describe("partial salvage and cancellation", () => {
    it("deadline: already-uploaded refs are SALVAGED and sent, and the signal is aborted", async () => {
      const h = setup();
      const files = [makeFile("a.md"), makeFile("b.md")];
      let seen: AbortSignal | undefined;
      h.upload.mockImplementationOnce((_f: File[], _id: string, opts?: UploadOpts) => {
        seen = opts?.signal;
        opts?.onUploaded?.(refFor(files[0]!));
        return new Promise<AttachmentRef[]>(() => {}); // second file hangs forever
      });
      const res = await runFirstRunSend({
        msgParam: "hi",
        files,
        conversationId: REAL_ID,
        getLive: h.getLive,
        upload: h.upload,
        send: h.send,
        deadlineMs: 20,
      });
      expect(seen?.aborted).toBe(true);
      expect(h.send.mock.calls).toEqual([["hi", [refFor(files[0]!)]]]);
      expect(res).toEqual({ sent: true, retry: false });
      expect(ops()).toEqual(["first-run-upload-timeout"]);
      expect(callFor("first-run-upload-timeout")![1].extra).toEqual({
        attempted: 2,
        uploaded: 1,
        deadlineMs: 20,
      });
    });

    it("the signal is NOT aborted when the upload finishes in time", async () => {
      const h = setup();
      let seen: AbortSignal | undefined;
      h.upload.mockImplementationOnce(async (f: File[], _id: string, opts?: UploadOpts) => {
        seen = opts?.signal;
        return f.map(refFor);
      });
      await runFirstRunSend({
        msgParam: "hi",
        files: [makeFile("a.md")],
        conversationId: REAL_ID,
        getLive: h.getLive,
        upload: h.upload,
        send: h.send,
      });
      expect(seen?.aborted).toBe(false);
    });

    it("upload rejects after some files finished -> salvaged refs still sent, captured as partial", async () => {
      const h = setup();
      const files = [makeFile("a.md"), makeFile("b.md")];
      h.upload.mockImplementationOnce(async (_f: File[], _id: string, opts?: UploadOpts) => {
        opts?.onUploaded?.(refFor(files[0]!));
        throw new Error("boom");
      });
      const res = await runFirstRunSend({
        msgParam: "hi",
        files,
        conversationId: REAL_ID,
        getLive: h.getLive,
        upload: h.upload,
        send: h.send,
      });
      expect(h.send.mock.calls).toEqual([["hi", [refFor(files[0]!)]]]);
      expect(res).toEqual({ sent: true, retry: false });
      expect(ops()).toEqual(["first-run-upload-partial"]);
      expect(callFor("first-run-upload-partial")![1].extra).toEqual({ attempted: 2, uploaded: 1 });
    });

    it("files-only + deadline with nothing uploaded -> nothing sent, timeout captured, no retry", async () => {
      const h = setup();
      h.upload.mockImplementationOnce(() => new Promise<AttachmentRef[]>(() => {}));
      const res = await runFirstRunSend({
        msgParam: null,
        files: [makeFile("a.md")],
        conversationId: REAL_ID,
        getLive: h.getLive,
        upload: h.upload,
        send: h.send,
        deadlineMs: 10,
      });
      expect(h.send).not.toHaveBeenCalled();
      expect(res).toEqual({ sent: false, retry: false });
      expect(ops()).toEqual(["first-run-upload-timeout"]);
    });
  });

  describe("final attempt (retry budget exhausted)", () => {
    const OTHER = "ffffffff-0000-4000-8000-000000000000";
    const run = (h: ReturnType<typeof setup>, over: { msgParam?: string | null } = {}) =>
      runFirstRunSend({
        msgParam: over.msgParam === undefined ? "hi" : over.msgParam,
        files: [makeFile("a.md")],
        conversationId: REAL_ID,
        getLive: h.getLive,
        upload: h.upload,
        send: h.send,
        final: true,
      });

    it("live session is connected+confirmed under a NEW id -> text-only send(msg), files dropped and captured", async () => {
      const h = setup({ live: { conversationId: OTHER } });
      const res = await run(h);
      expect(h.send.mock.calls).toEqual([["hi"]]);
      expect(res).toEqual({ sent: true, retry: false });
      const c = callFor("first-run-send-dropped");
      expect(c).toBeDefined();
      expect(c![1].extra).toMatchObject({ attempted: 1, uploaded: 1, idChanged: true, final: true });
    });

    it("dead socket -> never sends, dropped captured, no retry", async () => {
      const h = setup({ live: { conversationId: OTHER, connected: false } });
      const res = await run(h);
      expect(h.send).not.toHaveBeenCalled();
      expect(res).toEqual({ sent: false, retry: false });
      expect(ops()).toEqual(["first-run-send-dropped"]);
    });

    it("socket up but session not confirmed -> never sends", async () => {
      const h = setup({ live: { sessionConfirmed: false } });
      const res = await run(h);
      expect(h.send).not.toHaveBeenCalled();
      expect(res).toEqual({ sent: false, retry: false });
    });

    it("no message text -> nothing to fall back to, nothing sent", async () => {
      const h = setup({ live: { conversationId: OTHER } });
      const res = await run(h, { msgParam: null });
      expect(h.send).not.toHaveBeenCalled();
      expect(res).toEqual({ sent: false, retry: false });
      expect(ops()).toEqual(["first-run-send-dropped"]);
    });

    it("ready on the final attempt -> normal send with refs (fallback not taken)", async () => {
      const h = setup();
      const res = await run(h);
      expect(h.send).toHaveBeenCalledTimes(1);
      expect(h.send.mock.calls[0]![1]).toHaveLength(1);
      expect(res).toEqual({ sent: true, retry: false });
      expect(ops()).toEqual([]);
    });

    it("NOT final: the same id-changed state still asks for a retry and sends nothing", async () => {
      const h = setup({ live: { conversationId: OTHER } });
      const res = await runFirstRunSend({
        msgParam: "hi",
        files: [makeFile("a.md")],
        conversationId: REAL_ID,
        getLive: h.getLive,
        upload: h.upload,
        send: h.send,
        final: false,
      });
      expect(h.send).not.toHaveBeenCalled();
      expect(res).toEqual({ sent: false, retry: true });
    });
  });
});
