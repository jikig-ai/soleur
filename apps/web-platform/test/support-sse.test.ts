// Pure SSE transport helpers for the support chat (ADR-113, CTO Option D).
// Server: WSMessage -> `data: …\n\n` frame. Client: reassemble split chunks +
// reduce dispatch frames into support reply state. No I/O — fully deterministic.

import { describe, it, expect } from "vitest";
import type { WSMessage } from "@/lib/types";

import {
  formatSupportSseFrame,
  parseSupportSseChunks,
  reduceSupportFrame,
  initialSupportStream,
  type SupportStreamState,
} from "@/lib/support-sse";

describe("formatSupportSseFrame (server)", () => {
  it("serializes a WSMessage as a single `data: …\\n\\n` frame", () => {
    const frame = formatSupportSseFrame({ type: "stream", content: "hi", partial: true, leaderId: "cc_router" } as WSMessage);
    expect(frame).toBe(`data: ${JSON.stringify({ type: "stream", content: "hi", partial: true, leaderId: "cc_router" })}\n\n`);
  });
});

describe("parseSupportSseChunks (client)", () => {
  it("reassembles a frame split across two network chunks", () => {
    const whole = formatSupportSseFrame({ type: "stream", content: "hello world", partial: false, leaderId: "cc_router" } as WSMessage);
    const mid = Math.floor(whole.length / 2);
    let buf = "";
    const out1 = parseSupportSseChunks(buf + whole.slice(0, mid));
    buf = out1.rest;
    expect(out1.messages).toEqual([]); // incomplete — nothing yet
    const out2 = parseSupportSseChunks(buf + whole.slice(mid));
    expect(out2.messages).toHaveLength(1);
    expect((out2.messages[0] as { content: string }).content).toBe("hello world");
    expect(out2.rest).toBe("");
  });

  it("parses multiple frames in one chunk and drops malformed data", () => {
    const a = formatSupportSseFrame({ type: "stream", content: "a", partial: true, leaderId: "cc_router" } as WSMessage);
    const b = formatSupportSseFrame({ type: "session_ended" } as WSMessage);
    const { messages, rest } = parseSupportSseChunks(a + "data: {not json}\n\n" + b);
    expect(messages.map((m) => m.type)).toEqual(["stream", "session_ended"]);
    expect(rest).toBe("");
  });
});

describe("reduceSupportFrame (client state machine)", () => {
  const run = (frames: WSMessage[]): SupportStreamState =>
    frames.reduce(reduceSupportFrame, initialSupportStream());

  it("stream frames replace the text cumulatively (not append)", () => {
    const s = run([
      { type: "stream_start", leaderId: "cc_router" } as WSMessage,
      { type: "stream", content: "Par", partial: true, leaderId: "cc_router" } as WSMessage,
      { type: "stream", content: "Paris", partial: true, leaderId: "cc_router" } as WSMessage,
    ]);
    expect(s.text).toBe("Paris");
    expect(s.status).toBe("streaming");
  });

  it("session_ended marks done", () => {
    const s = run([
      { type: "stream", content: "answer", partial: false, leaderId: "cc_router" } as WSMessage,
      { type: "session_ended" } as WSMessage,
    ]);
    expect(s.status).toBe("done");
    expect(s.text).toBe("answer");
  });

  it("an error frame surfaces an error status + message", () => {
    const s = run([{ type: "error", message: "boom" } as WSMessage]);
    expect(s.status).toBe("error");
    expect(s.error).toBe("boom");
  });

  it("ignores unrelated frames (tool_use, reasoning_narration)", () => {
    const s = run([
      { type: "stream", content: "x", partial: true, leaderId: "cc_router" } as WSMessage,
      { type: "tool_use", leaderId: "cc_router", label: "kb-search" } as WSMessage,
    ]);
    expect(s.text).toBe("x");
    expect(s.status).toBe("streaming");
  });
});
