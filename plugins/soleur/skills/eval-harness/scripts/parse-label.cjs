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

  // 2. Word-boundary search: return the first allowed label that appears as a
  //    standalone token (hyphen is treated as an in-token character).
  for (const a of set) {
    const esc = String(a).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(`(^|[^A-Za-z0-9-])${esc}([^A-Za-z0-9-]|$)`, "i");
    if (re.test(text)) return a;
  }

  // 3. No enum member found — return the raw first non-empty line so a gate
  //    assert can reject it as out-of-enum.
  const firstLine = text.split(/\r?\n/).map((s) => s.trim()).filter(Boolean)[0];
  return firstLine == null ? text : firstLine;
}

module.exports = { extractLabel };
