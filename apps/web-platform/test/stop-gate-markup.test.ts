import { describe, test, expect } from "vitest";
import { stripStopGateMarkup } from "../server/stop-gate-markup";

// The incident text: the Concierge's whole final block was this tag, replacing the
// question list in the chat bubble.
const INCIDENT =
  "<stop>OPERATOR-GATE: I need the lead's details (at minimum a name) from you. The review and save happen only after you send them, so there is nothing more I can do yet.</stop>";

describe("stripStopGateMarkup", () => {
  test("markup-only block (the incident) -> empty text, markupOnly", () => {
    expect(stripStopGateMarkup(INCIDENT)).toEqual({
      text: "",
      hadMarkup: true,
      markupOnly: true,
    });
  });

  test("the hook's other sentinel (BLOCKED) is stripped too", () => {
    expect(stripStopGateMarkup("<stop>BLOCKED: waiting on CI</stop>").markupOnly).toBe(true);
  });

  test("markup embedded in prose: prose kept, tag removed (before, after, between)", () => {
    expect(stripStopGateMarkup(`Before.\n\n${INCIDENT}`)).toMatchObject({
      text: "Before.",
      hadMarkup: true,
      markupOnly: false,
    });
    expect(stripStopGateMarkup(`${INCIDENT}\n\nAfter.`)).toMatchObject({
      text: "After.",
      markupOnly: false,
    });
    expect(stripStopGateMarkup(`One.\n\n${INCIDENT}\n\nTwo.`)).toMatchObject({
      text: "One.\n\nTwo.",
      markupOnly: false,
    });
  });

  test("case, whitespace before the sentinel and multi-line bodies are stripped", () => {
    expect(stripStopGateMarkup("<STOP>OPERATOR-GATE: x</STOP>").markupOnly).toBe(true);
    expect(stripStopGateMarkup("<stop>\n  operator-gate: x\n</stop>").markupOnly).toBe(true);
    expect(stripStopGateMarkup("<stop>OPERATOR-GATE: line one\nline two\n</stop>").markupOnly).toBe(true);
  });

  test("two sentinel spans are both removed", () => {
    expect(
      stripStopGateMarkup("A <stop>OPERATOR-GATE: x</stop> B <stop>BLOCKED: y</stop> C"),
    ).toMatchObject({ text: "A  B  C", hadMarkup: true, markupOnly: false });
  });

  test("nested sentinel leaves no stray closer", () => {
    const r = stripStopGateMarkup("<stop>OPERATOR-GATE: a <stop>BLOCKED: b</stop> c</stop>d");
    expect(r.text).toBe("cd");
    expect(r.text).not.toContain("</stop>");
    expect(r.hadMarkup).toBe(true);
  });

  test("unterminated sentinel is truncated at the tag", () => {
    expect(stripStopGateMarkup("The list.\n\n<stop>OPERATOR-GATE: never closed")).toMatchObject({
      text: "The list.",
      hadMarkup: true,
      markupOnly: false,
    });
    expect(stripStopGateMarkup("<stop>OPERATOR-GATE: never closed")).toMatchObject({
      text: "",
      markupOnly: true,
    });
  });

  test("no markup -> input returned as-is, hadMarkup false", () => {
    const input = "Here is the list:\n- a\n- b";
    expect(stripStopGateMarkup(input)).toEqual({
      text: input,
      hadMarkup: false,
      markupOnly: false,
    });
  });

  test("must-NOT-strip lookalikes: SVG gradient stops, prose mentions, other tags", () => {
    const svg =
      'Here is the gradient:\n```svg\n<linearGradient id="g">\n<stop offset="0" stop-color="#fff"/>\n<stop offset="1" stop-color="#000"/>\n</linearGradient>\n```\nThen use it as fill.';
    const prose = "Use `<stop>` when you need to halt. Then continue as normal.";
    for (const s of [svg, prose, "<stopwatch>3s</stopwatch>", "Please stop here.", "a <stops> b", "<stop/>", '<stop reason="x">y</stop>']) {
      expect(stripStopGateMarkup(s)).toEqual({ text: s, hadMarkup: false, markupOnly: false });
    }
  });

  test("empty input is not markup", () => {
    expect(stripStopGateMarkup("")).toEqual({ text: "", hadMarkup: false, markupOnly: false });
  });

  test("linear time: 200 KB of pathological openers finishes inside a fixed budget", () => {
    const inputs = [
      "<stop>".repeat(35_000),
      "<stop ".repeat(35_000),
      "<stop>OPERATOR-GATE".repeat(11_000),
      "<stop>x".repeat(28_000) + "</stop>",
      "<stop>OPERATOR-GATE: y</stop>".repeat(7_000),
    ];
    for (const input of inputs) {
      const t0 = performance.now();
      stripStopGateMarkup(input);
      // The lazy-regex implementation took 1-30 s on these; linear is single-digit ms.
      expect(performance.now() - t0).toBeLessThan(250);
    }
  });
});
