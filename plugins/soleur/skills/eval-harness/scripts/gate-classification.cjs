// GATE assert (the ponytail `correctness.js` analog).
//
// promptfoo custom JavaScript assert. FAILS when the model's emitted label is NOT
// a member of the target's closed enum — a malformed or hallucinated label breaks
// the skill's contract regardless of whether it would have been the "right" answer.
// This is the deterministic contract check: the output must be a well-formed label.
//
// Signature: module.exports = (output, context) => GradingResult
//   context.vars.enum : the closed set of allowed labels (route or P-level set)
"use strict";

const { extractLabel } = require("./parse-label.cjs");

module.exports = (output, context) => {
  const vars = (context && context.vars) || {};
  const allowed = Array.isArray(vars.enum) ? vars.enum : [];
  const got = extractLabel(output, allowed);
  const inEnum = allowed.includes(got);
  return {
    pass: inEnum,
    score: inEnum ? 1.0 : 0.0,
    reason: inEnum
      ? `in-enum label: ${got}`
      : `out-of-enum label ${JSON.stringify(got)} — not one of [${allowed.join(", ")}]`,
  };
};
