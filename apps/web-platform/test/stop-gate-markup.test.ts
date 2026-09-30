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
    expect(
      stripStopGateMarkup(`One.\n\n${INCIDENT}\n\nTwo.`),
    ).toMatchObject({ text: "One.\n\nTwo.", markupOnly: false });
  });

  test("case, attribute and multi-line variants are stripped", () => {
    expect(stripStopGateMarkup("<STOP>x</STOP>").markupOnly).toBe(true);
    expect(stripStopGateMarkup('<stop reason="x">y</stop>').markupOnly).toBe(true);
    expect(stripStopGateMarkup("<stop>line one\nline two\n</stop>").markupOnly).toBe(true);
  });

  test("two tags are both removed", () => {
    expect(stripStopGateMarkup("A <stop>x</stop> B <stop>y</stop> C")).toMatchObject({
      text: "A  B  C",
      hadMarkup: true,
      markupOnly: false,
    });
  });

  test("unterminated tag is truncated at the tag", () => {
    expect(
      stripStopGateMarkup("The list.\n\n<stop>OPERATOR-GATE: never closed"),
    ).toMatchObject({ text: "The list.", hadMarkup: true, markupOnly: false });
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

  test("lookalikes are not stripped", () => {
    for (const s of ["<stopwatch>3s</stopwatch>", "Please stop here.", "a <stops> b"]) {
      expect(stripStopGateMarkup(s)).toEqual({ text: s, hadMarkup: false, markupOnly: false });
    }
  });

  test("empty input is not markup", () => {
    expect(stripStopGateMarkup("")).toEqual({ text: "", hadMarkup: false, markupOnly: false });
  });
});
