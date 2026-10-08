// Shared reading of how an Anthropic turn ended (Haiku 5.5, 2026-10-08). Three call
// sites (domain router, email summarizer, leader loop) used to carry their own copy of
// "which stops are a missing/unusable answer" and "which category rides along", with
// three different gating rules. One helper, pinned here, so they cannot drift again.

import { describe, expect, it } from "vitest";
import {
  KNOWN_REFUSAL_CATEGORIES,
  KNOWN_STOP_REASONS,
  noTextBlockExtra,
  refusalCategory,
  safeStopReason,
} from "@/server/anthropic-stop-report";

const MODEL = "claude-haiku-5-5";
const run = (text: string, stopReason: unknown, stopDetails?: unknown) =>
  noTextBlockExtra({ text, stopReason, stopDetails, model: MODEL });

describe("noTextBlockExtra — when a turn is an unusable answer", () => {
  it("a healthy end_turn with text is null (no mirror)", () => {
    expect(run('{"leaders":["cmo"]}', "end_turn")).toBeNull();
    expect(run("hello", "stop_sequence")).toBeNull();
  });

  it("empty and whitespace-only text mirror whatever the stop reason", () => {
    for (const text of ["", "   ", "\n\t "]) {
      expect(run(text, "end_turn")).toEqual({ stop_reason: "end_turn", model: MODEL });
    }
  });

  it("NON-EMPTY text still mirrors when the turn was cut off or refused (the clause the fixtures never reached)", () => {
    expect(run('{"leaders":["cm', "max_tokens")).toEqual({ stop_reason: "max_tokens", model: MODEL });
    expect(run("I can't help with that.", "refusal")).toEqual({ stop_reason: "refusal", model: MODEL });
    expect(run('{"a":', "model_context_window_exceeded")).toEqual({
      stop_reason: "model_context_window_exceeded",
      model: MODEL,
    });
  });

  it("a refusal carries its category, and ONLY the category — never the rest of stop_details", () => {
    const out = run("", "refusal", {
      type: "refusal",
      category: "cyber",
      explanation: "SENTINEL-explanation-text the model wrote",
    });
    expect(out).toEqual({ stop_reason: "refusal", category: "cyber", model: MODEL });
    expect(Object.keys(out!).sort()).toEqual(["category", "model", "stop_reason"]);
    expect(JSON.stringify(out)).not.toContain("SENTINEL");
  });

  it("a category on a non-refusal stop is dropped (stop_details is a refusal detail)", () => {
    expect(run("", "max_tokens", { category: "cyber" })).toEqual({
      stop_reason: "max_tokens",
      model: MODEL,
    });
  });
});

describe("closed vocabularies — API strings are allowlisted before they reach a sink", () => {
  it("an unrecognized stop_reason becomes 'unknown'; a hostile one never passes through", () => {
    expect(safeStopReason("end_turn")).toBe("end_turn");
    expect(safeStopReason("SENTINEL-" + "x".repeat(500))).toBe("unknown");
    expect(safeStopReason(undefined)).toBe("unknown");
    expect(safeStopReason(42)).toBe("unknown");
    expect(safeStopReason(null)).toBe("unknown");
    for (const s of KNOWN_STOP_REASONS) expect(safeStopReason(s)).toBe(s);
  });

  it("an unrecognized refusal category becomes 'unrecognized'; a hostile one never passes through", () => {
    for (const c of KNOWN_REFUSAL_CATEGORIES) {
      expect(refusalCategory("refusal", { category: c })).toBe(c);
    }
    expect(refusalCategory("refusal", { category: "SENTINEL-" + "y".repeat(500) })).toBe("unrecognized");
    expect(refusalCategory("refusal", { category: 7 })).toBeNull();
    expect(refusalCategory("refusal", null)).toBeNull();
    expect(refusalCategory("refusal", undefined)).toBeNull();
    expect(refusalCategory("refusal", "cyber")).toBeNull();
    expect(refusalCategory("end_turn", { category: "cyber" })).toBeNull();
  });

  it("the vocabularies are the documented ones (a rename or removal is a deliberate test change)", () => {
    expect([...KNOWN_REFUSAL_CATEGORIES].sort()).toEqual(["bio", "cyber", "frontier_llm", "general_harms"]);
    expect([...KNOWN_STOP_REASONS]).toContain("refusal");
    expect([...KNOWN_STOP_REASONS]).toContain("max_tokens");
  });
});
