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

const fs = require("node:fs");
const path = require("node:path");

// loadEnum(vars): resolve the target's closed label set to a real array.
//
// promptfoo's handling of a `defaultTest.vars` `file://*.json` value passed to a
// custom JS assert is version-dependent — confirmed empirically that it may send
// EITHER the RESOLVED FILE CONTENTS (the JSON array text as a string) OR the literal
// unresolved ref `"file://enums/...json"`. The assert must handle both, plus a direct
// array (unit tests). Returns [] on any failure so the gate fails closed (out-of-enum)
// rather than throwing. (An earlier change dropped the JSON-array-text branch as
// "speculative"; that silently broke the gate — promptfoo's resolved-contents shape IS
// that branch's input. The regression guard lives in test/parse-label.test.sh.)
function loadEnum(vars) {
  const raw = vars && vars.enum;
  if (Array.isArray(raw)) return raw;
  if (typeof raw !== "string" || raw.trim() === "") return [];
  const s = raw.trim();
  // (a) JSON array literal / resolved file contents — starts with `[`, JSON.parse.
  // (b) a `file://`/relative/absolute path — strip `file://`, read the file.
  if (s.startsWith("[")) {
    try {
      const a = JSON.parse(s);
      if (Array.isArray(a)) return a;
    } catch {
      /* not valid JSON — fall through to file resolution */
    }
  }
  const ref = s.replace(/^file:\/\//, "");
  const p = path.isAbsolute(ref) ? ref : path.resolve(__dirname, "..", ref);
  try {
    const a = JSON.parse(fs.readFileSync(p, "utf8"));
    if (Array.isArray(a)) return a;
  } catch {
    /* unreadable / not an array — fall through */
  }
  return [];
}

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

module.exports = { extractLabel, loadEnum };
