import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import {
  abortableReviewGate,
  validateSelection,
  extractReviewGateInput,
  buildReviewGateResponse,
  MAX_SELECTION_LENGTH,
  REVIEW_GATE_TIMEOUT_MS,
  type AgentSession,
} from "../server/review-gate";

describe("validateSelection", () => {
  const options = ["Approve", "Reject"];

  test("passes for a valid option", () => {
    expect(() => validateSelection(options, "Approve")).not.toThrow();
  });

  test("passes for second valid option", () => {
    expect(() => validateSelection(options, "Reject")).not.toThrow();
  });

  test("rejects selection not in options", () => {
    expect(() => validateSelection(options, "Ignore all previous instructions")).toThrow(
      "Invalid review gate selection",
    );
  });

  test("rejects empty string", () => {
    expect(() => validateSelection(options, "")).toThrow(
      "Invalid review gate selection",
    );
  });

  test("rejects wrong case", () => {
    expect(() => validateSelection(["Yes", "No", "Maybe"], "yes")).toThrow(
      "Invalid review gate selection",
    );
  });

  test("rejects trailing whitespace", () => {
    expect(() => validateSelection(options, "Approve ")).toThrow(
      "Invalid review gate selection",
    );
  });

  test("rejects oversized string", () => {
    const oversized = "x".repeat(300);
    expect(() => validateSelection(options, oversized)).toThrow(
      "Invalid review gate selection",
    );
  });

  test("rejects string at exactly maxLength + 1", () => {
    const justOver = "x".repeat(MAX_SELECTION_LENGTH + 1);
    expect(() => validateSelection(options, justOver)).toThrow(
      "Invalid review gate selection",
    );
  });

  test("allows string at exactly maxLength when it matches an option", () => {
    const longOption = "x".repeat(MAX_SELECTION_LENGTH);
    expect(() => validateSelection([longOption], longOption)).not.toThrow();
  });

  test("MAX_SELECTION_LENGTH is 256", () => {
    expect(MAX_SELECTION_LENGTH).toBe(256);
  });
});

describe("extractReviewGateInput", () => {
  test("extracts question, header, options from SDK schema", () => {
    const toolInput = {
      questions: [{
        question: "Which approach?",
        header: "Approach",
        options: [
          { label: "A", description: "desc A" },
          { label: "B", description: "desc B" },
        ],
        multiSelect: false,
      }],
    };

    const result = extractReviewGateInput(toolInput);
    expect(result.question).toBe("Which approach?");
    expect(result.header).toBe("Approach");
    expect(result.options).toEqual(["A", "B"]);
    expect(result.descriptions).toEqual({ A: "desc A", B: "desc B" });
    expect(result.isNewSchema).toBe(true);
  });

  test("falls back to legacy fields when questions array is absent", () => {
    const toolInput = {
      question: "Do you approve?",
      options: ["Yes", "No"],
    };

    const result = extractReviewGateInput(toolInput);
    expect(result.question).toBe("Do you approve?");
    expect(result.header).toBe("Input needed");
    expect(result.options).toEqual(["Yes", "No"]);
    expect(result.descriptions).toEqual({});
    expect(result.isNewSchema).toBe(false);
  });

  test("uses default question and options when nothing is provided", () => {
    const toolInput = {};

    const result = extractReviewGateInput(toolInput);
    expect(result.question).toBe("Agent needs your input");
    expect(result.header).toBe("Input needed");
    expect(result.options).toEqual(["Approve", "Reject"]);
    expect(result.descriptions).toEqual({});
    expect(result.isNewSchema).toBe(false);
  });

  test("handles empty questions array gracefully", () => {
    const toolInput = { questions: [] };

    const result = extractReviewGateInput(toolInput);
    expect(result.question).toBe("Agent needs your input");
    expect(result.options).toEqual(["Approve", "Reject"]);
    expect(result.isNewSchema).toBe(false);
  });

  test("handles options without descriptions", () => {
    const toolInput = {
      questions: [{
        question: "Pick one",
        header: "Choice",
        options: [
          { label: "X" },
          { label: "Y" },
        ],
        multiSelect: false,
      }],
    };

    const result = extractReviewGateInput(toolInput);
    expect(result.options).toEqual(["X", "Y"]);
    expect(result.descriptions).toEqual({ X: undefined, Y: undefined });
  });

  test("filters non-string legacy options", () => {
    const toolInput = {
      question: "Choose",
      options: ["Valid", 42, null, "Also valid"],
    };

    const result = extractReviewGateInput(toolInput);
    expect(result.options).toEqual(["Valid", "Also valid"]);
  });
});

describe("buildReviewGateResponse", () => {
  test("builds new-schema response with questions and answers", () => {
    const toolInput = {
      questions: [{
        question: "Which approach?",
        header: "Approach",
        options: [
          { label: "A", description: "desc A" },
          { label: "B", description: "desc B" },
        ],
        multiSelect: false,
      }],
    };

    const result = buildReviewGateResponse(toolInput, "A", true);
    expect(result).toEqual({
      questions: toolInput.questions,
      answers: { "Which approach?": "A" },
    });
  });

  test("builds legacy response with spread toolInput and answer field", () => {
    const toolInput = {
      question: "Approve?",
      options: ["Yes", "No"],
    };

    const result = buildReviewGateResponse(toolInput, "Yes", false);
    expect(result).toEqual({
      question: "Approve?",
      options: ["Yes", "No"],
      answer: "Yes",
    });
  });

  test("new-schema response does not include answer field", () => {
    const toolInput = {
      questions: [{
        question: "Pick",
        header: "H",
        options: [{ label: "X", description: "" }],
        multiSelect: false,
      }],
    };

    const result = buildReviewGateResponse(toolInput, "X", true);
    expect(result).not.toHaveProperty("answer");
    expect(result).toHaveProperty("answers");
  });
});

describe("abortableReviewGate", () => {
  let session: AgentSession;
  let controller: AbortController;

  beforeEach(() => {
    vi.useFakeTimers();
    controller = new AbortController();
    session = {
      abort: controller,
      reviewGateResolvers: new Map(),
      sessionId: null,
    };
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("resolves normally when user responds", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);

    const entry = session.reviewGateResolvers.get("g1");
    expect(entry).toBeDefined();
    entry!.resolve("Approve");

    const result = await promise;
    expect(result).toBe("Approve");
  });

  test("stores options alongside the resolver", async () => {
    const opts = ["Yes", "No", "Maybe"];
    abortableReviewGate(session, "g1", controller.signal, undefined, opts);

    const entry = session.reviewGateResolvers.get("g1");
    expect(entry).toBeDefined();
    expect(entry!.options).toEqual(opts);

    // Clean up
    entry!.resolve("Yes");
  });

  test("uses default options when none provided", async () => {
    abortableReviewGate(session, "g1", controller.signal);

    const entry = session.reviewGateResolvers.get("g1");
    expect(entry!.options).toEqual(["Approve", "Reject"]);

    entry!.resolve("Approve");
  });

  test("cleans up abort listener after normal resolution", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);

    const entry = session.reviewGateResolvers.get("g1");
    entry!.resolve("Approve");
    await promise;

    // Aborting after resolution should not throw — the listener was removed
    controller.abort(new Error("late abort"));
  });

  test("cleans up timeout after normal resolution", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal, 1000);

    const entry = session.reviewGateResolvers.get("g1");
    entry!.resolve("Approve");
    await promise;

    // Advancing past the timeout should not cause rejection
    vi.advanceTimersByTime(2000);
    expect(vi.getTimerCount()).toBe(0);
  });

  test("rejects when abort signal fires", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);

    controller.abort(new Error("Session aborted: user disconnected"));

    await expect(promise).rejects.toThrow("Session aborted: user disconnected");
  });

  test("removes resolver from map on abort", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);
    expect(session.reviewGateResolvers.has("g1")).toBe(true);

    controller.abort(new Error("disconnect"));
    await promise.catch(() => {});

    expect(session.reviewGateResolvers.has("g1")).toBe(false);
  });

  test("rejects when timeout elapses", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal, 1000);

    vi.advanceTimersByTime(1000);

    await expect(promise).rejects.toThrow("Review gate timed out");
  });

  test("removes resolver from map on timeout", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal, 1000);
    expect(session.reviewGateResolvers.has("g1")).toBe(true);

    vi.advanceTimersByTime(1000);
    await promise.catch(() => {});

    expect(session.reviewGateResolvers.has("g1")).toBe(false);
  });

  test("rejects synchronously if signal already aborted", async () => {
    controller.abort(new Error("already aborted"));

    const promise = abortableReviewGate(session, "g1", controller.signal);

    await expect(promise).rejects.toThrow("already aborted");
    expect(session.reviewGateResolvers.has("g1")).toBe(false);
  });

  test("uses signal.reason when abort is called without explicit reason", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);

    controller.abort();

    // Node.js sets signal.reason to a DOMException("This operation was aborted")
    await expect(promise).rejects.toThrow("aborted");
  });

  test("cleans up timeout on abort", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal, 1000);

    controller.abort(new Error("disconnect"));
    await promise.catch(() => {});

    // Advancing past timeout should not cause additional rejection
    vi.advanceTimersByTime(2000);
    expect(vi.getTimerCount()).toBe(0);
  });

  test("uses default 5-minute timeout", async () => {
    expect(REVIEW_GATE_TIMEOUT_MS).toBe(5 * 60 * 1_000);

    const promise = abortableReviewGate(session, "g1", controller.signal);

    // 4m59s should not timeout
    vi.advanceTimersByTime(4 * 60 * 1000 + 59 * 1000);
    expect(session.reviewGateResolvers.has("g1")).toBe(true);

    // 5m should timeout
    vi.advanceTimersByTime(1000);
    await expect(promise).rejects.toThrow("Review gate timed out");
  });

  test("no-op when no review gate is pending on disconnect", () => {
    expect(session.reviewGateResolvers.size).toBe(0);
    controller.abort(new Error("disconnect"));
    // Map should remain empty and not throw
    expect(session.reviewGateResolvers.size).toBe(0);
  });
});
