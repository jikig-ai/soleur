// MEASUREMENT assert (the ponytail `loc.js` analog).
//
// promptfoo custom JavaScript assert. Records the classification-correct rate as
// a score and ALWAYS passes — it measures, it never gates. The recorded number is
// the metric under test: 1.0 when the model's emitted label matches the golden
// label, 0.0 otherwise. Aggregated across runs (repeat: N) and across the skill
// vs baseline arms, the mean of this score IS the baseline-vs-skill delta.
//
// Signature: module.exports = (output, context) => GradingResult
//   context.vars.golden_label : the expected label (route or P-level)
//   context.vars.enum         : the closed set of allowed labels (for parsing)
"use strict";

const { extractLabel } = require("./parse-label.cjs");

module.exports = (output, context) => {
  const vars = (context && context.vars) || {};
  const golden = vars.golden_label;
  const allowed = vars.enum;
  const got = extractLabel(output, allowed);
  const correct = got === golden;
  return {
    pass: true, // measurement only — never gates
    score: correct ? 1.0 : 0.0,
    reason: correct
      ? `classification-correct: ${got}`
      : `classification-incorrect: got ${JSON.stringify(got)}, expected ${JSON.stringify(golden)}`,
  };
};
