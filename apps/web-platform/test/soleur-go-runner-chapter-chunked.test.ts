// Concierge dispatch-time chapter-routing integration coverage
// (#3436 Phase 3.B — bundle PR feat-pdf-chapter-chunking-bundle).
//
// Plan §3.5 scenarios pinned by this file:
//   1. Routed answer — `[Answering from chapter N: "title"]`
//      prepended to the first text block of the answer turn.
//   2. System-prompt byte-stability across within-chapter turns
//      (covered by `soleur-go-runner-chapter-chunked-prompt.test.ts`
//      case 4; this file does not re-pin it).
//   3. Ambiguous routing turn — no answer turn fires; routing cost
//      charged.
//   4. Chapter-extraction failure → refund + failure copy + Sentry
//      mirror.
//   5. Cap hit between routing and answer turns → cost_ceiling.
//   6. Router-error path → internal_error WorkflowEnded.
//   7. KD-3 mid-stream cap regression guard — note: this is a
//      forward-looking pin against cc-cost-caps.ts mid-stream
//      behavior. The dispatch invariant under test is:
//      `handleResultMessage` clears `activeChapter` but does NOT
//      touch `chapterChunkedContext`, so the next user turn
//      re-routes off the same outline without a stale chapter.
//      The cap-during-streaming path is structurally handled by the
//      same `handleResultMessage` boundary.
//   8. KD-5 stale-context invalidation (8a path-mismatch with new
//      chapters; 8b path-mismatch with no new chapters).
//   9. KD-6 single-PDF prefix regression guard.
//
// The dispatch path is wired via `dispatchChapterRouted` inside the
// runner. Tests mock `selectChapter`, `readFile`, and
// `extractPdfText` so they're deterministic and engine-floor
// independent.

import {
  describe,
  it,
  expect,
  vi,
  beforeEach,
  afterEach,
} from "vitest";
import type {
  Query,
  SDKMessage,
  SDKUserMessage,
  SDKResultMessage,
  SDKAssistantMessage,
} from "@anthropic-ai/claude-agent-sdk";

const {
  selectChapterSpy,
  readFileSpy,
  extractPdfTextSpy,
  reportSilentFallbackSpy,
} = vi.hoisted(() => ({
  selectChapterSpy: vi.fn(),
  readFileSpy: vi.fn(),
  extractPdfTextSpy: vi.fn(),
  reportSilentFallbackSpy: vi.fn(),
}));

vi.mock("@/server/pdf-chapter-router", () => ({
  selectChapter: selectChapterSpy,
}));

vi.mock("node:fs/promises", () => ({
  readFile: readFileSpy,
}));

// Replicate the real pdf-text-extract ChapterIndex type at the
// import boundary so we keep type discipline without pulling in
// the heavy pdfjs-dist module at test time.
vi.mock("@/server/pdf-text-extract", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/pdf-text-extract")>();
  return {
    ...actual,
    extractPdfText: extractPdfTextSpy,
  };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

import {
  createSoleurGoRunner,
  type QueryFactory,
  type DispatchEvents,
  type WorkflowEnd,
} from "@/server/soleur-go-runner";
import type { ConversationRouting } from "@/server/conversation-routing";

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

function makeResult(totalCostUsd: number, sessionId = "sess-1"): SDKResultMessage {
  return {
    type: "result",
    subtype: "success",
    duration_ms: 1,
    duration_api_ms: 1,
    is_error: false,
    num_turns: 1,
    result: "",
    stop_reason: "end_turn",
    total_cost_usd: totalCostUsd,
    // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    usage: { input_tokens: 0, output_tokens: 0 } as any,
    modelUsage: {},
    permission_denials: [],
    uuid: "00000000-0000-0000-0000-0000000000ff" as never,
    session_id: sessionId,
  } as SDKResultMessage;
}

function makeAssistant(text: string): SDKAssistantMessage {
  return {
    type: "assistant",
    message: {
      id: "msg_1",
      role: "assistant",
      model: "claude-sonnet-4-6",
      stop_reason: null,
      stop_sequence: null,
      type: "message",
      // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
      usage: { input_tokens: 0, output_tokens: 0 } as any,
      content: [{ type: "text", text }],
    },
    parent_tool_use_id: null,
    uuid: "00000000-0000-0000-0000-000000000001" as never,
    session_id: "sess-1",
  } as unknown as SDKAssistantMessage;
}

function createMockQuery() {
  let closed = false;
  const queue: SDKMessage[] = [];
  let resolveNext: ((r: IteratorResult<SDKMessage>) => void) | null = null;
  const closeSpy = vi.fn();
  const iter: AsyncGenerator<SDKMessage, void> = {
    async next() {
      if (queue.length > 0) {
        const v = queue.shift()!;
        return { value: v, done: false };
      }
      if (closed) return { value: undefined, done: true };
      return new Promise<IteratorResult<SDKMessage>>((r) => {
        resolveNext = r;
      });
    },
    async return() {
      closed = true;
      return { value: undefined, done: true };
    },
    async throw(e) {
      closed = true;
      throw e;
    },
    async [Symbol.asyncDispose]() {
      closed = true;
    },
    [Symbol.asyncIterator]() {
      return iter;
    },
  };
  function emit(msg: SDKMessage) {
    if (resolveNext) {
      const r = resolveNext;
      resolveNext = null;
      r({ value: msg, done: false });
    } else {
      queue.push(msg);
    }
  }
  function finish() {
    if (resolveNext) {
      const r = resolveNext;
      resolveNext = null;
      r({ value: undefined, done: true });
    }
    closed = true;
  }
  const q: Mutable<Partial<Query>> = {
    ...(iter as unknown as Query),
    close: () => {
      closeSpy();
      finish();
    },
    interrupt: vi.fn(async () => {}),
    setPermissionMode: vi.fn(async () => {}),
    setModel: vi.fn(async () => {}),
    setMaxThinkingTokens: vi.fn(async () => {}),
    applyFlagSettings: vi.fn(async () => {}),
    // biome-ignore lint/suspicious/noExplicitAny: test stub
    initializationResult: vi.fn(async () => ({}) as any),
    supportedCommands: vi.fn(async () => []),
    supportedModels: vi.fn(async () => []),
    streamInput: vi.fn(async () => {}),
    stopTask: vi.fn(async () => {}),
  };
  return { query: q as Query, emit, finish, closeSpy };
}

function makeEvents(): DispatchEvents & {
  _text: string[];
  _ended: WorkflowEnd[];
} {
  const text: string[] = [];
  const ended: WorkflowEnd[] = [];
  return {
    onText: (t) => text.push(t),
    onToolUse: () => {},
    onWorkflowDetected: () => {},
    onWorkflowEnded: (e) => ended.push(e),
    onResult: () => {},
    _text: text,
    _ended: ended,
  };
}

async function flush(n = 12): Promise<void> {
  for (let i = 0; i < n; i++) await Promise.resolve();
}

const PDF_DISPLAY = "knowledge-base/big-book.pdf";
const WS_PATH = "/workspaces/u1";
const PDF_FULL_PATH = `${WS_PATH}/${PDF_DISPLAY}`;

const SAMPLE_CHAPTERS = [
  { title: "Introduction", startPage: 1, endPage: 12, depth: 0 },
  { title: "Architecture overview", startPage: 13, endPage: 47, depth: 0 },
  { title: "Authentication", startPage: 48, endPage: 102, depth: 0 },
];

const baseDispatchArgs = (
  conversationId: string,
  userMessage: string,
  events: DispatchEvents,
  override: Record<string, unknown> = {},
) => ({
  conversationId,
  userId: "u1",
  userMessage,
  currentRouting: { kind: "soleur_go_pending" } as ConversationRouting,
  events,
  persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
  artifactPath: PDF_DISPLAY,
  documentKind: "pdf" as const,
  documentExtractMeta: {
    numPages: 403,
    chapters: SAMPLE_CHAPTERS,
    fullExtractedText: "(extracted body)",
  },
  workspacePath: WS_PATH,
  ...override,
});

describe("soleur-go-runner chapter-chunked dispatch (Phase 3.B)", () => {
  beforeEach(() => {
    selectChapterSpy.mockReset();
    readFileSpy.mockReset();
    extractPdfTextSpy.mockReset();
    reportSilentFallbackSpy.mockReset();
  });

  it("Case 1 — routed answer: prepends `[Answering from chapter N: \"title\"]` to first text block", async () => {
    selectChapterSpy.mockResolvedValueOnce({
      kind: "selected",
      chapterIndex: 1,
      routingCostUsd: 0.002,
    });
    readFileSpy.mockResolvedValueOnce(Buffer.from("fake-pdf-bytes"));
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "Architecture overview slice text.",
      truncated: false,
      pageCount: 35,
    });

    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => 0 });
    const events = makeEvents();

    await runner.dispatch(baseDispatchArgs("c-route", "Tell me about architecture", events));
    await flush();

    // Routing was invoked against the outline.
    expect(selectChapterSpy).toHaveBeenCalledTimes(1);
    const routingArgs = selectChapterSpy.mock.calls[0]![0];
    expect(routingArgs.question).toBe("Tell me about architecture");
    expect(routingArgs.outline).toEqual(SAMPLE_CHAPTERS);

    // readFile called against the resolved absolute path.
    expect(readFileSpy).toHaveBeenCalledWith(PDF_FULL_PATH);

    // extractPdfText called with the chapter's page range.
    expect(extractPdfTextSpy).toHaveBeenCalledWith(
      expect.any(Buffer),
      expect.any(Number),
      expect.objectContaining({ startPage: 13, endPage: 47 }),
    );

    // Emit an assistant text block. The runner should prepend the
    // chapter prefix to the first text emission.
    mock.emit(makeAssistant("The architecture is layered."));
    await flush();
    expect(events._text[0]).toMatch(
      /^\[Answering from chapter 2: "Architecture overview"\]\n\n/,
    );
  });

  it("Case 3 — ambiguous: no answer turn fires; routing cost charged to user-visible text", async () => {
    selectChapterSpy.mockResolvedValueOnce({
      kind: "ambiguous",
      routingCostUsd: 0.002,
    });
    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => 0 });
    const events = makeEvents();
    await runner.dispatch(baseDispatchArgs("c-ambig", "What chapter covers it?", events));
    await flush();
    expect(events._text.join("\n")).toMatch(/multiple chapters/);
    // No SDK iterator emit — the dispatch returned before the answer
    // turn fires. readFile must NOT have been called.
    expect(readFileSpy).not.toHaveBeenCalled();
  });

  it("Case 4 — chapter-extraction failure: refunds routing cost + emits failure copy + Sentry mirror", async () => {
    selectChapterSpy.mockResolvedValueOnce({
      kind: "selected",
      chapterIndex: 0,
      routingCostUsd: 0.003,
    });
    readFileSpy.mockResolvedValueOnce(Buffer.from("fake-pdf-bytes"));
    extractPdfTextSpy.mockResolvedValueOnce({ error: "parse_error" });

    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => 0 });
    const events = makeEvents();
    await runner.dispatch(baseDispatchArgs("c-slice", "Summarize chapter 1", events));
    await flush();
    expect(events._text.join("\n")).toMatch(/chapter failed to extract/);
    expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        feature: "soleur-go-runner",
        op: "chapter-slice-parse_error",
      }),
    );
  });

  it("Case 5 — cost-cap-hit between routing and answer turns fires cost_ceiling", async () => {
    selectChapterSpy.mockResolvedValueOnce({
      kind: "cost-cap-hit",
      cap: 2.0,
      totalCostUsd: 2.5,
    });
    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => 0 });
    const events = makeEvents();
    await runner.dispatch(baseDispatchArgs("c-cap", "Anything", events));
    await flush();
    const ceiling = events._ended.find((e) => e.status === "cost_ceiling");
    expect(ceiling).toBeDefined();
    if (ceiling && ceiling.status === "cost_ceiling") {
      expect(ceiling.cap).toBe(2.0);
      expect(ceiling.totalCostUsd).toBe(2.5);
    }
    expect(readFileSpy).not.toHaveBeenCalled();
  });

  it("Case 6 — router-error fires internal_error WorkflowEnded", async () => {
    selectChapterSpy.mockResolvedValueOnce({
      kind: "router-error",
      reason: "rate limited",
      routingCostUsd: 0,
    });
    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => 0 });
    const events = makeEvents();
    await runner.dispatch(baseDispatchArgs("c-err", "go", events));
    await flush();
    const err = events._ended.find((e) => e.status === "internal_error");
    expect(err).toBeDefined();
  });

  it("Case 8a — KD-5 path mismatch with new chapters: re-routes against new outline same turn", async () => {
    // Turn 1: set up state with chapterChunkedContext at old.pdf.
    selectChapterSpy.mockResolvedValueOnce({
      kind: "selected",
      chapterIndex: 0,
      routingCostUsd: 0.001,
    });
    readFileSpy.mockResolvedValueOnce(Buffer.from("old"));
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "old chapter text",
      truncated: false,
      pageCount: 12,
    });
    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => 0 });
    const events = makeEvents();
    await runner.dispatch(baseDispatchArgs("c-rotate", "Tell me about ch1", events));
    await flush();
    // End turn 1 to let activeChapter clear.
    mock.emit(makeAssistant("answer 1"));
    mock.emit(makeResult(0));
    await flush();

    // Turn 2: new PDF with NEW chapters at a different path.
    const NEW_DISPLAY = "knowledge-base/new-book.pdf";
    const NEW_FULL = `${WS_PATH}/${NEW_DISPLAY}`;
    const NEW_CHAPTERS = [
      { title: "Foreword", startPage: 1, endPage: 10, depth: 0 },
      { title: "Body", startPage: 11, endPage: 200, depth: 0 },
    ];
    selectChapterSpy.mockResolvedValueOnce({
      kind: "selected",
      chapterIndex: 1,
      routingCostUsd: 0.001,
    });
    readFileSpy.mockResolvedValueOnce(Buffer.from("new"));
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "new chapter text",
      truncated: false,
      pageCount: 190,
    });
    await runner.dispatch(
      baseDispatchArgs("c-rotate", "And the new book?", events, {
        artifactPath: NEW_DISPLAY,
        documentExtractMeta: {
          numPages: 200,
          chapters: NEW_CHAPTERS,
          fullExtractedText: "(new body)",
        },
      }),
    );
    await flush();

    // Routing fired against the NEW outline.
    expect(selectChapterSpy.mock.calls[1]![0].outline).toEqual(NEW_CHAPTERS);
    // readFile against the NEW absolute path.
    expect(readFileSpy.mock.calls[1]![0]).toBe(NEW_FULL);

    // First text emission on the new turn carries the rotation
    // notice prepended to the prefix.
    mock.emit(makeAssistant("Here is the new chapter."));
    await flush();
    const lastText = events._text[events._text.length - 1];
    expect(lastText).toMatch(/Source PDF changed/);
  });

  it("Case 8b — KD-5 path mismatch with no new chapters: falls through to legacy pushUserMessage", async () => {
    // Turn 1: chapter-chunked context bootstrapped.
    selectChapterSpy.mockResolvedValueOnce({
      kind: "selected",
      chapterIndex: 0,
      routingCostUsd: 0.001,
    });
    readFileSpy.mockResolvedValueOnce(Buffer.from("old"));
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "old",
      truncated: false,
      pageCount: 12,
    });
    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => 0 });
    const events = makeEvents();
    await runner.dispatch(baseDispatchArgs("c-rotate-empty", "q1", events));
    await flush();
    mock.emit(makeAssistant("a1"));
    mock.emit(makeResult(0));
    await flush();

    // Turn 2: new path, empty chapters → fall through.
    await runner.dispatch(
      baseDispatchArgs("c-rotate-empty", "q2", events, {
        artifactPath: "knowledge-base/regular.txt",
        documentKind: undefined,
        documentExtractMeta: undefined,
      }),
    );
    await flush();
    // selectChapter NOT invoked on the second turn (no chapters).
    expect(selectChapterSpy).toHaveBeenCalledTimes(1);
  });

  it("GREEN-S1 cache_control: dispatch attaches cache_control: ephemeral on the chapter content block (AC #5 / S1 verification)", async () => {
    // Review fix (data-integrity P2, test-design P2): the inputQueue
    // shape is the load-bearing wire for S1 cache economics — without
    // a static-shape assertion, a silent regression that drops
    // `cache_control` would invalidate AC #4 (10-turn cost envelope)
    // post-deploy with no test signal.
    selectChapterSpy.mockResolvedValueOnce({
      kind: "selected",
      chapterIndex: 0,
      routingCostUsd: 0.001,
    });
    readFileSpy.mockResolvedValueOnce(Buffer.from("fake-pdf-bytes"));
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "Intro slice text.",
      truncated: false,
      pageCount: 12,
    });
    // Capture the SDK user-message that lands on the input stream.
    const captures: SDKUserMessage[] = [];
    const mock = createMockQuery();
    const factory: QueryFactory = (args) => {
      void (async () => {
        for await (const msg of args.prompt as AsyncIterable<SDKUserMessage>) {
          captures.push(msg);
          if (captures.length >= 1) break;
        }
      })();
      return mock.query;
    };
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => 0 });
    const events = makeEvents();
    await runner.dispatch(baseDispatchArgs("c-cache", "What's in chapter 1?", events));
    await flush(20);

    expect(captures.length).toBe(1);
    const pushed = captures[0]!;
    const content = (pushed.message as { content: unknown }).content;
    expect(Array.isArray(content)).toBe(true);
    const blocks = content as Array<{ type: string; cache_control?: { type: string } }>;
    // Exactly one content block (the text block with the chapter slice).
    expect(blocks).toHaveLength(1);
    expect(blocks[0]!.type).toBe("text");
    expect(blocks[0]!.cache_control).toEqual({ type: "ephemeral" });
    // The block does NOT carry the full PDF binary (review F5 fix —
    // earlier draft attached a document block with base64-encoded
    // PDF buffer, leading to per-turn full-binary egress).
    expect(blocks.find((b) => (b as { type: string }).type === "document")).toBeUndefined();
  });

  it("3-failure cap: 3rd slice failure surfaces cap copy and does NOT refund routing cost", async () => {
    // Review fix (data-integrity P2): the chapterExtractionFailures
    // 3-cap is the load-bearing infinite-refund-loop guard. Three
    // consecutive slice failures — first two refund, third surfaces
    // cap copy without refund.
    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => 0 });
    const events = makeEvents();

    for (let i = 0; i < 3; i++) {
      selectChapterSpy.mockResolvedValueOnce({
        kind: "selected",
        chapterIndex: 0,
        routingCostUsd: 0.001,
      });
      readFileSpy.mockResolvedValueOnce(Buffer.from("buf"));
      extractPdfTextSpy.mockResolvedValueOnce({ error: "parse_error" });
      await runner.dispatch(
        baseDispatchArgs(`c-cap-3`, `try ${i}`, events),
      );
      await flush(8);
    }

    // Last text emission is the cap copy.
    const lastText = events._text[events._text.length - 1];
    expect(lastText).toMatch(/can't extract chapters from this PDF/);
    // First two failures should NOT have surfaced the cap copy.
    expect(events._text[0]).toMatch(/chapter failed to extract/);
    expect(events._text[1]).toMatch(/chapter failed to extract/);
  });

  it("Case 9 — single-PDF prefix shape (no document title)", async () => {
    selectChapterSpy.mockResolvedValueOnce({
      kind: "selected",
      chapterIndex: 2,
      routingCostUsd: 0.001,
    });
    readFileSpy.mockResolvedValueOnce(Buffer.from("buf"));
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "auth slice",
      truncated: false,
      pageCount: 55,
    });
    const mock = createMockQuery();
    const factory: QueryFactory = () => mock.query;
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => 0 });
    const events = makeEvents();
    await runner.dispatch(baseDispatchArgs("c-single", "How does auth work?", events));
    await flush();
    mock.emit(makeAssistant("Auth uses JWT."));
    await flush();
    // Single-PDF prefix template — no `from "<book>", chapter`
    // wrapper, just the chapter form.
    expect(events._text[0]).toMatch(
      /^\[Answering from chapter 3: "Authentication"\]\n\nAuth uses JWT\.$/,
    );
    expect(events._text[0]).not.toMatch(/from "[^"]+",/);
  });
});
