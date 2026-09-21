// expand.cjs — expands a compact synthetic B5 fixture spec into promptfoo `-o` results
// JSON (the shape rule-phrasing-verdict.cjs reads). Offline; no API.
//
// Spec: { id, expect?, expect_not?, repeat, models[], extends?, swap_arms?, mutate?,
//         k: { <arm>: { <rule>: int | int[6] } }, model_k?: { <model>: { <arm>: { <rule>: … } } } }
//   k = passes (compliant results) out of `repeat` per task; results i < k score 1.
//   mutate.drop_one  — drop one result from the first cell (a 2-of-3 cell).
//   mutate.error_row — turn one result into a provider error row.
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const ARMS = ["prohibition", "positive", "none"];
const TASKS_PER_RULE = 6;

function load(file) {
  const spec = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!spec.extends) return spec;
  const parent = load(path.join(path.dirname(file), spec.extends));
  const merged = Object.assign({}, parent, spec);
  merged.k = Object.assign({}, parent.k, spec.k || {});
  merged.model_k = Object.assign({}, parent.model_k || {}, spec.model_k || {});
  delete merged.extends;
  return merged;
}

function kFor(spec, model, arm, rule, i) {
  const src = (spec.model_k && spec.model_k[model] && spec.model_k[model][arm] && spec.model_k[model][arm][rule] !== undefined)
    ? spec.model_k[model][arm][rule]
    : spec.k[arm][rule];
  if (src === undefined) throw new Error(`fixture ${spec.id}: no k for ${arm}/${rule}`);
  return Array.isArray(src) ? src[i] : src;
}

function expand(file) {
  const spec = load(file);
  const swap = spec.swap_arms || null;
  const rules = Object.keys(spec.k.prohibition);
  const rows = [];
  for (const model of spec.models) for (const arm of ARMS) for (const rule of rules) {
    for (let i = 0; i < TASKS_PER_RULE; i++) {
      const k = kFor(spec, model, arm, rule, i);
      let label = arm;
      if (swap && arm === swap[0]) label = swap[1];
      else if (swap && arm === swap[1]) label = swap[0];
      for (let j = 0; j < spec.repeat; j++) {
        const ok = j < k;
        rows.push({
          provider: { id: model, label: "" },
          prompt: { raw: "[chat]", label },
          vars: { rule, input: `${rule} synthetic task ${i}` },
          response: { output: ok ? "compliant" : "violating", finishReason: "stop" },
          success: true,
          score: ok ? 1 : 0,
          gradingResult: {
            pass: true,
            score: ok ? 1 : 0,
            reason: "All assertions passed",
            componentResults: [{ pass: true, score: ok ? 1 : 0, reason: ok ? `rule-compliant: ${rule}` : `rule-noncompliant: ${rule}: "x"` }],
          },
        });
      }
    }
  }
  const m = spec.mutate || {};
  if (m.drop_one) rows.splice(0, 1);
  if (m.error_row) Object.assign(rows[0], { error: "API error: 529 overloaded", success: false, failureReason: 2, gradingResult: null, response: { error: "overloaded" } });
  return { spec, json: { evalId: `synthetic-${spec.id}`, results: { version: 3, results: rows } } };
}

module.exports = { expand, load };
