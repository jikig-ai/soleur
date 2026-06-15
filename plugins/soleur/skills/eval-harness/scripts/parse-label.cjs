// Shared label parser for the eval-harness asserts.
//
// extractLabel(output, allowed): given a raw model output string and the closed
// set of allowed labels (the target's enum), return the canonical enum member the
// output denotes, or — when no enum member is present — the raw first non-empty
// line (so the gate assert can reject a malformed / hallucinated label).
//
// Classifier-agnostic: works for /go routes (lowercase, hyphenated) and
// ticket-triage P-levels (P1/P2/P3) alike. Matching is case-insensitive; a
// hyphen counts as part of a label token so "clo-attestation" is not split.
"use strict";

function extractLabel(output, allowed) {
  const text = String(output == null ? "" : output).trim();
  const set = Array.isArray(allowed) ? allowed : [];

  // 1. Exact (case-insensitive) match against the whole trimmed output.
  for (const a of set) {
    if (text.toLowerCase() === String(a).toLowerCase()) return a;
  }

  // 2. Word-boundary search: return the allowed label that appears EARLIEST in
  //    the text (lowest character position), NOT the first member in enum order.
  //    Enum-order would bias the result toward whichever label is declared first
  //    in the type, independent of what the model actually said. Tie-break =
  //    earliest mention. Hedged / negated outputs ("not P1, use P2") are
  //    inherently ambiguous and resolve to the first-mentioned label — the
  //    harness's validity rests on the prompt's "respond with ONLY the token"
  //    instruction (handled by the exact-match tier above); this tier is a
  //    lenient fallback for disobedient prose. The hyphen is treated as an
  //    in-token character so "clo-attestation" is not split.
  let best = null;
  let bestIdx = Infinity;
  for (const a of set) {
    const esc = String(a).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`(^|[^A-Za-z0-9-])(${esc})([^A-Za-z0-9-]|$)`, "i");
    const m = re.exec(text);
    if (m) {
      const idx = m.index + m[1].length; // position of the label token itself
      if (idx < bestIdx) {
        bestIdx = idx;
        best = a;
      }
    }
  }
  if (best !== null) return best;

  // 3. No enum member found — return the raw first non-empty line so a gate
  //    assert can reject it as out-of-enum.
  const firstLine = text.split(/\r?\n/).map((s) => s.trim()).filter(Boolean)[0];
  return firstLine == null ? text : firstLine;
}

module.exports = { extractLabel };
