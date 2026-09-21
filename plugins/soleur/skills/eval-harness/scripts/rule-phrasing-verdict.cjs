#!/usr/bin/env node
// rule-phrasing-verdict.cjs — the pre-registered B5 verdict (#8290, plan §Guard 2 / §D5).
//
// Pure exported `verdict(json, opts)` + a `require.main` CLI, in the house shape of
// verdict.cjs / eval-gate.cjs: one-line JSON on stdout; exit 1 fail-closed via die();
// exit 2 on bad arguments. NO I/O inside verdict(), NO API.
//
// INPUT: promptfoo `eval -o <file>.json` output (0.123.x). Rows are read from
// `json.results.results[]` (or a bare `json.results[]`). Per row:
//   provider  : `r.provider.label || r.provider.id` (or a string)  -> model
//   arm       : `r.prompt.label` (config sets label: prohibition|positive|none)
//   task      : `r.vars` (or `r.testCase.vars`) -> `rule` + `input`
//   score     : the measurement component whose reason starts `rule-compliant` /
//               `rule-noncompliant` (gradingResult.componentResults[], else gradingResult)
//   error     : `r.error` non-empty, or `r.failureReason === 2` (promptfoo ERROR)
//   truncated : `r.response.finishReason === "length"` (anthropic stop_reason max_tokens)
//
// STATISTICS (unit = task). rate[t][m][a] = mean score over the repeats of task t, model m,
// arm a. Δ_t = mean over models of (positive − prohibition). Over the tasks of the rules that
// pass V1: Δ = mean(Δ_t), SE = sd(Δ_t)/√n (sample sd), interval Δ ± 2·SE.
// MWE = 0.10, ε = 1/24. Δ_m per model, Δ_r per rule. V1 per rule: prohibition − none ≥ ε.
//
// FIXED PRECEDENCE:
//   1 ABORTED        — grid incomplete: a (task, model, arm) cell with results ≠ the declared
//                      repeat, a missing cell, a task or model count ≠ expected (24 / 3 by
//                      default), or ANY error row.
//   2 INVALID        — no rule passes V1 (failing rules are excluded from 3-6).
//   3 REJECT-CEILING — prohibition ≥ 0.95 on every V1 rule AND upper < MWE.
//   4 EXTEND         — Δ ≥ MWE, lower > 0, every Δ_m ≥ −ε, Δ_r > 0 on ≥ 3 of the 4 rules
//                      (counted over V1-passing rules).
//   5 REJECT         — upper < MWE.
//   6 INCONCLUSIVE   — everything else.
// Max-token truncation is RECORDED per arm, not an abort: a cut-off answer can score
// compliant by omission, so the rate travels with the verdict.
"use strict";

const fs = require("node:fs");

const ARMS = ["prohibition", "positive", "none"];
const RULES = [
  "hr-never-git-stash-in-worktrees",
  "hr-never-run-commands-with-unbounded-output",
  "hr-never-write-to-claude-code-memory-claude",
  "wg-never-bump-version-files-in-feature",
];
const MWE = 0.1;
const EPSILON = 1 / 24;
const CEILING = 0.95;
const MIN_RULES_POSITIVE = 3;
const DEFAULT_REPEAT = 3;
const DEFAULT_TASKS = 24;
const DEFAULT_MODELS = 3;
const TOKENS = ["EXTEND", "REJECT", "REJECT-CEILING", "INCONCLUSIVE", "INVALID", "ABORTED"];

const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;
function sd(xs) {
  if (xs.length < 2) return 0;
  const m = mean(xs);
  return Math.sqrt(xs.reduce((a, x) => a + (x - m) * (x - m), 0) / (xs.length - 1));
}

function rowsOf(json) {
  if (json && json.results && Array.isArray(json.results.results)) return json.results.results;
  if (json && Array.isArray(json.results)) return json.results;
  throw new Error("promptfoo output has no results array");
}

function isErrorRow(r) {
  return (typeof r.error === "string" && r.error !== "") || (r.error && typeof r.error === "object") || r.failureReason === 2;
}

function scoreOf(r) {
  const g = r.gradingResult || {};
  const comps = Array.isArray(g.componentResults) ? g.componentResults : [];
  const measure = [...comps, g].find((c) => c && typeof c.reason === "string" && /^rule-(non)?compliant/.test(c.reason));
  if (!measure) return null;
  return /^rule-compliant/.test(measure.reason) ? 1 : 0;
}

function verdict(json, opts) {
  const o = opts || {};
  const repeat = o.repeat === undefined ? DEFAULT_REPEAT : o.repeat;
  const expectedTasks = o.expectedTasks === undefined ? DEFAULT_TASKS : o.expectedTasks;
  const expectedModels = o.expectedModels === undefined ? DEFAULT_MODELS : o.expectedModels;
  if (!(Number.isInteger(repeat) && repeat >= 1)) throw new TypeError("verdict: repeat must be a positive integer");
  const rows = rowsOf(json);

  const base = { token: null, repeat, expected_tasks: expectedTasks, expected_models: expectedModels, rows: rows.length, mwe: MWE, epsilon: EPSILON, ceiling: CEILING };
  const abort = (reason, extra) => Object.assign(base, { token: "ABORTED", abort_reason: reason }, extra || {});

  // --- 1. H-E1: errors, then grid completeness -------------------------------------------
  const errorRows = rows.filter(isErrorRow).length;
  const trunc = {};
  for (const a of ARMS) trunc[a] = { rows: 0, truncated: 0 };
  const cells = new Map(); // key task|model|arm -> scores[]
  const tasks = new Map(); // key -> { rule, input }
  const models = new Set();
  const tokens = { prompt: 0, completion: 0, total: 0 };
  let cost = 0;
  for (const r of rows) {
    const vars = r.vars || (r.testCase && r.testCase.vars) || {};
    const arm = r.prompt && r.prompt.label;
    // Model key: the provider label when set (two providers may share an id), else its id.
    const model = typeof r.provider === "string" ? r.provider : r.provider && (r.provider.label || r.provider.id);
    if (!ARMS.includes(arm)) throw new Error(`unknown arm label ${JSON.stringify(arm)} (expected ${ARMS.join("|")})`);
    if (!RULES.includes(vars.rule)) throw new Error(`unknown vars.rule ${JSON.stringify(vars.rule)}`);
    if (typeof vars.input !== "string") throw new Error("result row missing vars.input");
    if (typeof model !== "string" || model === "") throw new Error("result row missing provider id");
    trunc[arm].rows += 1;
    const fr = (r.response && r.response.finishReason) || r.finishReason;
    if (fr === "length") trunc[arm].truncated += 1;
    const tu = r.tokenUsage || (r.response && r.response.tokenUsage) || {};
    for (const k of Object.keys(tokens)) if (typeof tu[k] === "number") tokens[k] += tu[k];
    if (typeof r.cost === "number") cost += r.cost;
    if (isErrorRow(r)) continue;
    const taskKey = `${vars.rule}\u0000${vars.input}`;
    tasks.set(taskKey, { rule: vars.rule, input: vars.input });
    models.add(model);
    const s = scoreOf(r);
    if (s === null) throw new Error(`no rule-(non)compliant measurement component for ${vars.rule} / ${arm} / ${model}`);
    const k = `${taskKey}\u0001${model}\u0001${arm}`;
    if (!cells.has(k)) cells.set(k, []);
    cells.get(k).push(s);
  }
  const truncation_rate = {};
  for (const a of ARMS) truncation_rate[a] = trunc[a].rows ? trunc[a].truncated / trunc[a].rows : null;
  base.truncation_rate = truncation_rate;
  base.error_rows = errorRows;
  base.tokens = tokens;
  base.cost_usd = cost;
  if (errorRows > 0) return abort(`${errorRows} error row(s)`);

  const modelList = [...models].sort();
  const taskList = [...tasks.keys()].sort();
  base.models = modelList;
  base.tasks = taskList.length;
  if (taskList.length !== expectedTasks) return abort(`task count ${taskList.length} != expected ${expectedTasks}`);
  if (modelList.length !== expectedModels) return abort(`model count ${modelList.length} != expected ${expectedModels}`);
  const badCells = [];
  for (const t of taskList) for (const m of modelList) for (const a of ARMS) {
    const n = (cells.get(`${t}\u0001${m}\u0001${a}`) || []).length;
    if (n !== repeat) badCells.push({ rule: tasks.get(t).rule, model: m, arm: a, results: n });
  }
  if (badCells.length > 0) return abort(`${badCells.length} cell(s) with results != repeat ${repeat}`, { bad_cells: badCells.slice(0, 20) });

  // --- per-task, per-model, per-arm rates ------------------------------------------------
  const rate = (t, m, a) => mean(cells.get(`${t}\u0001${m}\u0001${a}`));
  const armRate = (ts, a) => mean(ts.flatMap((t) => modelList.map((m) => rate(t, m, a))));
  const tasksOf = (rule) => taskList.filter((t) => tasks.get(t).rule === rule);
  const dT = (t) => mean(modelList.map((m) => rate(t, m, "positive") - rate(t, m, "prohibition")));

  const per_arm = {};
  for (const a of ARMS) per_arm[a] = armRate(taskList, a);
  const per_model = {};
  for (const m of modelList) {
    per_model[m] = {};
    for (const a of ARMS) per_model[m][a] = mean(taskList.map((t) => rate(t, m, a)));
  }
  const per_rule = {};
  for (const rule of RULES) {
    const ts = tasksOf(rule);
    if (ts.length === 0) { per_rule[rule] = { tasks: 0, v1: false }; continue; }
    const pr = armRate(ts, "prohibition");
    const po = armRate(ts, "positive");
    const no = armRate(ts, "none");
    per_rule[rule] = {
      tasks: ts.length, prohibition: pr, positive: po, none: no,
      delta_r: mean(ts.map(dT)),
      v1_margin: pr - no,
      v1: pr - no >= EPSILON - 1e-12,
    };
  }
  Object.assign(base, { per_arm, per_model, per_rule });

  // --- 2. V1 exclusion -------------------------------------------------------------------
  const v1Rules = RULES.filter((r) => per_rule[r].v1);
  base.v1_rules = v1Rules;
  if (v1Rules.length === 0) return Object.assign(base, { token: "INVALID" });

  const scored = taskList.filter((t) => v1Rules.includes(tasks.get(t).rule));
  const deltas = scored.map(dT);
  const n = deltas.length;
  const delta = mean(deltas);
  const se = sd(deltas) / Math.sqrt(n);
  const lower = delta - 2 * se;
  const upper = delta + 2 * se;
  const delta_m = {};
  for (const m of modelList) delta_m[m] = mean(scored.map((t) => rate(t, m, "positive") - rate(t, m, "prohibition")));
  const rulesPositive = v1Rules.filter((r) => per_rule[r].delta_r > 0).length;
  const ceilingAll = v1Rules.every((r) => per_rule[r].prohibition >= CEILING);
  const modelsOk = modelList.every((m) => delta_m[m] >= -EPSILON - 1e-12);
  Object.assign(base, {
    n, delta, se, lower, upper, delta_m, rules_positive: rulesPositive,
    ceiling_all_v1: ceilingAll, models_no_regression: modelsOk,
  });

  // --- 3-6 -------------------------------------------------------------------------------
  let token;
  if (ceilingAll && upper < MWE) token = "REJECT-CEILING";
  else if (delta >= MWE && lower > 0 && modelsOk && rulesPositive >= MIN_RULES_POSITIVE) token = "EXTEND";
  else if (upper < MWE) token = "REJECT";
  else token = "INCONCLUSIVE";
  return Object.assign(base, { token });
}

module.exports = { verdict, ARMS, RULES, MWE, EPSILON, CEILING, TOKENS };

function die(message) {
  process.stderr.write(`rule-phrasing-verdict: ${message}\n`);
  // Fail-closed: a consumer reading stdout sees no verdict token, only the error.
  process.stdout.write(JSON.stringify({ token: null, error: message }) + "\n");
  process.exit(1);
}

function main() {
  const argv = process.argv.slice(2);
  let file;
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--repeat" || a === "--expected-tasks" || a === "--expected-models") {
      const v = Number(argv[++i]);
      if (!(Number.isInteger(v) && v >= 1)) {
        process.stderr.write(`rule-phrasing-verdict: ${a} needs a positive integer\n`);
        process.exit(2);
      }
      opts[{ "--repeat": "repeat", "--expected-tasks": "expectedTasks", "--expected-models": "expectedModels" }[a]] = v;
    } else if (a.startsWith("-")) {
      process.stderr.write(`rule-phrasing-verdict: unknown flag ${a}\n`);
      process.exit(2);
    } else if (file === undefined) {
      file = a;
    } else {
      process.stderr.write("rule-phrasing-verdict: exactly one results file expected\n");
      process.exit(2);
    }
  }
  if (file === undefined) {
    process.stderr.write("usage: rule-phrasing-verdict.cjs <promptfoo-results.json> [--repeat N] [--expected-tasks N] [--expected-models N]\n");
    process.exit(2);
  }
  const out = verdict(JSON.parse(fs.readFileSync(file, "utf8")), opts);
  process.stdout.write(JSON.stringify(out) + "\n");
}

if (require.main === module) {
  try {
    main();
  } catch (e) {
    die(e && e.message ? e.message : String(e));
  }
}
