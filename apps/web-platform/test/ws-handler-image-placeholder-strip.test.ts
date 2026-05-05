/**
 * Unit test for the inbound image-placeholder strip + emit guard wired
 * into ws-handler's `chat` case (#3254). The helper is a small pure
 * function so we can test it without spinning the WS server up.
 *
 * Behavior locked here:
 *   - When `[Image #N]` markers are present in the inbound content, the
 *     helper strips them, sends a structured `error` event with
 *     `errorCode: "image_paste_lost"`, and mirrors to Sentry under
 *     `feature: "command-center", op: "image-placeholder-strip"` with
 *     `count` + `conversationId` in `extra`.
 *   - When the content is clean, the helper is a no-op (no client send,
 *     no Sentry mirror, original text returned).
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import type { WSMessage } from "@/lib/types";

import { stripAndReportImagePlaceholders } from "@/server/image-paste-strip";

describe("stripAndReportImagePlaceholders", () => {
  const userId = "user-aaaa";
  const conversationId = "conv-bbbb";

  let send: ReturnType<typeof vi.fn>;
  let reportFallback: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    send = vi.fn();
    reportFallback = vi.fn();
  });

  it("returns original text when content has no placeholders (no side effects)", () => {
    const out = stripAndReportImagePlaceholders("hello world", {
      userId,
      conversationId,
      send,
      reportFallback,
    });

    expect(out).toBe("hello world");
    expect(send).not.toHaveBeenCalled();
    expect(reportFallback).not.toHaveBeenCalled();
  });

  it("strips placeholders, returns cleaned text", () => {
    const out = stripAndReportImagePlaceholders(
      "what is this? [Image #1] [Image #2]",
      { userId, conversationId, send, reportFallback },
    );

    // Trailing whitespace / collapsed runs are normalized by the detector.
    expect(out).toBe("what is this?");
  });

  it("emits a single `error` event with errorCode 'image_paste_lost' (not one per placeholder)", () => {
    stripAndReportImagePlaceholders(
      "[Image #1] [Image #2] [Image #3]",
      { userId, conversationId, send, reportFallback },
    );

    expect(send).toHaveBeenCalledTimes(1);
    const sent = send.mock.calls[0]?.[0] as WSMessage;
    expect(sent.type).toBe("error");
    if (sent.type !== "error") throw new Error("type narrow");
    expect(sent.errorCode).toBe("image_paste_lost");
    expect(sent.message).toMatch(/image|re-attach/i);
  });

  it("mirrors to Sentry once per stripped message with feature, op, count, conversationId", () => {
    stripAndReportImagePlaceholders(
      "[Image #1] [Image #2]",
      { userId, conversationId, send, reportFallback },
    );

    expect(reportFallback).toHaveBeenCalledTimes(1);
    const [err, options] = reportFallback.mock.calls[0]!;
    expect(err).toBeNull();
    expect(options).toMatchObject({
      feature: "command-center",
      op: "image-placeholder-strip",
      extra: { count: 2, conversationId },
    });
  });

  it("handles a null/undefined conversationId (mid-pending materialization)", () => {
    const out = stripAndReportImagePlaceholders(
      "what is [Image #1]?",
      { userId, conversationId: null, send, reportFallback },
    );

    expect(out).toBe("what is ?");
    expect(send).toHaveBeenCalledTimes(1);
    expect(reportFallback).toHaveBeenCalledTimes(1);
    expect(reportFallback.mock.calls[0]![1]).toMatchObject({
      extra: { count: 1, conversationId: null },
    });
  });

  it("returns empty string when the message is nothing but placeholders (does not inject synthetic text)", () => {
    const out = stripAndReportImagePlaceholders("[Image #1] [Image #2]", {
      userId,
      conversationId,
      send,
      reportFallback,
    });
    expect(out).toBe("");
  });

  it("ignores lowercase [image #N] (SDK marker is fixed-case)", () => {
    const out = stripAndReportImagePlaceholders("hi [image #1]", {
      userId,
      conversationId,
      send,
      reportFallback,
    });
    expect(out).toBe("hi [image #1]");
    expect(send).not.toHaveBeenCalled();
    expect(reportFallback).not.toHaveBeenCalled();
  });
});
