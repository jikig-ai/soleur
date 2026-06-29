#!/usr/bin/env node
// eval-gate.cjs — thin orchestrator for the validation-gated classifier-skill-edit loop.
//
// The verdict MATH lives in verdict.cjs (pure); this file only does I/O: resolve the
// gated-skills registry, extract current+candidate blocks, project them into skill-arm
// prompts, shell promptfoo SKILL-ARM ONLY (current vs candidate — the baseline control
// arm is irrelevant to a regression gate), normalize promptfoo JSON into the shape
// verdict.cjs expects, and print the verdict. FAIL-CLOSED: any error => non-zero exit +
// stderr and the verdict defaults to NOT accept.
//
// Flags:
//   --check <file>           Lookup-only: print {gated, target, block_id} for whether
//                            <file> is a gated source. Exit 0. NO API.
//   --target <id>            Gated target id (go-routing | ticket-triage).
//   --candidate-file <path>  The edited source file holding the candidate block.
//   --target-task <json|path> The synthesized row whose candidate samples must pass.
//   --repeat N               Samples per cell (default 5).
//   --append-on-accept       On accept, append the (synthesized-only) target task to
//                            tasks/<target>.jsonl.
//   --dry-run                Print the skill-arm-only API-call estimate; exit. NO API.
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { extractBlock } = require("./extract-block.cjs");
const { renderSkillPrompt, tokensFor } = require("./gen-skill-prompt.cjs");
const { computeVerdict } = require("./verdict.cjs");

const SKILL_DIR = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(SKILL_DIR, "..", "..", "..", "..");
const REGISTRY = path.join(SKILL_DIR, "gated-skills.json");
const MODELS_FILE = path.join(SKILL_DIR, "models.generated.json");

// Per-target promptfoo resources (enum SSOT does NOT follow the target id, so it is
// listed explicitly). Corpus tasks file follows tasks/<target>.jsonl by convention.
const TARGET_RESOURCES = {
  "go-routing": { tasks: "tasks/go-routing.jsonl", enumPath: "enums/go-routes.json" },
  "ticket-triage": { tasks: "tasks/ticket-triage.jsonl", enumPath: "enums/triage-levels.json" },
};

function die(message, payload) {
  process.stderr.write(`eval-gate: ${message}\n`);
  // Fail-closed: surface a NOT-accept verdict to any JSON consumer.
  process.stdout.write(JSON.stringify(Object.assign({ accept: false, error: message }, payload || {})) + "\n");
  process.exit(1);
}

function loadRegistry() {
  return JSON.parse(fs.readFileSync(REGISTRY, "utf8"));
}

function parseArgs(argv) {
  const args = { repeat: 5, appendOnAccept: false, dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case "--check": args.check = argv[++i]; break;
      case "--target": args.target = argv[++i]; break;
      case "--candidate-file": args.candidateFile = argv[++i]; break;
      case "--target-task": args.targetTask = argv[++i]; break;
      case "--repeat": args.repeat = parseInt(argv[++i], 10); break;
      case "--append-on-accept": args.appendOnAccept = true; break;
      case "--dry-run": args.dryRun = true; break;
      default:
        process.stderr.write(`eval-gate: unknown flag ${a}\n`);
        process.exit(2);
    }
  }
  return args;
}

// findBySourceFile(file): the registry entry whose source_file resolves to the same
// absolute path as `file` (resolved against CWD), or null.
function findBySourceFile(file) {
  const wanted = path.resolve(process.cwd(), file);
  const wantedRepoRel = path.resolve(REPO_ROOT, file);
  return (
    loadRegistry().find((e) => {
      const abs = path.resolve(REPO_ROOT, e.source_file);
      return abs === wanted || abs === wantedRepoRel;
    }) || null
  );
}

function entryForTarget(target) {
  const entry = loadRegistry().find((e) => e.target === target);
  if (!entry) die(`unknown target ${JSON.stringify(target)}`);
  return entry;
}

function countTasks(target) {
  const res = TARGET_RESOURCES[target];
  if (!res) die(`no promptfoo resources for target ${JSON.stringify(target)}`);
  const text = fs.readFileSync(path.join(SKILL_DIR, res.tasks), "utf8");
  return text.split(/\r?\n/).filter((l) => l.trim() !== "").length;
}

// --- synthesized-only guard (TR2 / cq-test-fixtures-synthesized-only) ----------
// Reject inputs that look like real user data / PII. Heuristic, fail-closed.
function synthesizedCheck(input) {
  const s = String(input);
  const realEmail = /\b[\w.+-]+@(?!example\.|test\.|acme\.)[\w-]+\.[\w.-]+\b/i;
  const cardOrPhone = /\b\d[\d -]{10,}\d\b/;
  const ssn = /\b\d{3}-\d{2}-\d{4}\b/;
  if (realEmail.test(s)) return { ok: false, reason: "input contains a real-looking email address" };
  if (ssn.test(s)) return { ok: false, reason: "input contains an SSN-shaped sequence" };
  if (cardOrPhone.test(s)) return { ok: false, reason: "input contains a card/phone-shaped digit sequence" };
  return { ok: true };
}

// parsePromptfooOutput(json): normalize promptfoo --output JSON into the verdict shape.
// task_id = vars.input (the unique per-task key); correct is read from the MEASUREMENT
// assert (measure-classification.cjs), identified by its "classification-correct" /
// "classification-incorrect" reason prefix — robust to assert ordering. Fail-closed: a
// row with no measurement component throws.
function parsePromptfooOutput(json) {
  const rows = (json && json.results && Array.isArray(json.results.results))
    ? json.results.results
    : (Array.isArray(json && json.results) ? json.results : null);
  if (!rows) throw new Error("promptfoo output has no results array");
  return rows.map((r) => {
    const vars = r.vars || (r.testCase && r.testCase.vars) || {};
    const task_id = vars.input;
    if (typeof task_id !== "string") throw new Error("promptfoo result missing vars.input");
    const comps = (r.gradingResult && Array.isArray(r.gradingResult.componentResults))
      ? r.gradingResult.componentResults
      : [];
    const measure = comps.find((c) => typeof c.reason === "string" && /^classification-(in)?correct/.test(c.reason));
    if (!measure) throw new Error(`no measurement component for task ${JSON.stringify(task_id)}`);
    return { task_id, correct: /^classification-correct/.test(measure.reason) };
  });
}

// runPromptfoo(promptText, target, combinedTasksFile, repeat): SKILL-ARM ONLY run of a
// single prompt; returns the normalized results array. Thin shell-out.
function runPromptfoo(promptText, target, combinedTasksFile, repeat) {
  const res = TARGET_RESOURCES[target];
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "eval-gate-"));
  const promptFile = path.join(tmpDir, "skill.txt");
  const configFile = path.join(tmpDir, "config.json");
  const outFile = path.join(tmpDir, "results.json");
  fs.writeFileSync(promptFile, promptText);
  const config = {
    description: `eval-gate skill-arm-only (${target})`,
    providers: `file://${MODELS_FILE}`,
    prompts: [`file://${promptFile}`],
    defaultTest: {
      vars: { enum: `file://${path.join(SKILL_DIR, res.enumPath)}` },
      assert: [
        { type: "javascript", value: `file://${path.join(SKILL_DIR, "scripts", "measure-classification.cjs")}` },
        { type: "javascript", value: `file://${path.join(SKILL_DIR, "scripts", "gate-classification.cjs")}` },
      ],
    },
    tests: `file://${combinedTasksFile}`,
  };
  fs.writeFileSync(configFile, JSON.stringify(config));
  execFileSync("npx", ["promptfoo", "eval", "-c", configFile, "--repeat", String(repeat), "--output", outFile], {
    cwd: SKILL_DIR,
    stdio: ["ignore", "inherit", "inherit"],
  });
  return parsePromptfooOutput(JSON.parse(fs.readFileSync(outFile, "utf8")));
}

function main() {
  const args = parseArgs(process.argv.slice(2));

  // --check: lookup-only, NO API.
  if (args.check) {
    const entry = findBySourceFile(args.check);
    process.stdout.write(JSON.stringify({
      gated: Boolean(entry),
      target: entry ? entry.target : null,
      block_id: entry ? entry.block_id : null,
    }) + "\n");
    return;
  }

  if (!args.target) die("--target is required (or use --check)");

  // --dry-run: API-cost disclosure (skill-arm-only), NO API.
  if (args.dryRun) {
    const models = JSON.parse(fs.readFileSync(MODELS_FILE, "utf8")).length;
    const corpus = countTasks(args.target);
    const tasks = corpus + 1; // corpus + the target task
    // Two skill-arm runs (current vs candidate); the baseline control arm is skipped.
    const estimate = 2 * models * tasks * args.repeat;
    process.stdout.write(JSON.stringify({
      dry_run: true,
      target: args.target,
      arms: "skill-only (current vs candidate; baseline control arm skipped)",
      models,
      corpus_tasks: corpus,
      target_tasks: 1,
      repeat: args.repeat,
      estimated_api_calls: estimate,
      formula: "2 (current+candidate) x models x (corpus_tasks + 1) x repeat",
      note: "estimate only — no API call made",
    }) + "\n");
    return;
  }

  // Real run.
  if (!args.candidateFile) die("--candidate-file is required for a real run");

  const entry = entryForTarget(args.target);
  let currentBlock, candidateBlock;
  try {
    const currentSource = fs.readFileSync(path.join(REPO_ROOT, entry.source_file), "utf8");
    const candidateSource = fs.readFileSync(args.candidateFile, "utf8");
    currentBlock = extractBlock(currentSource, entry.block_start_marker, entry.block_end_marker);
    candidateBlock = extractBlock(candidateSource, entry.block_start_marker, entry.block_end_marker);
  } catch (err) {
    die(err.message);
  }

  // Ungateable no-op: the edit did not change the gated block. Short-circuit BEFORE
  // requiring a target task or spending any API — there is nothing to gate.
  if (currentBlock === candidateBlock) {
    process.stdout.write(JSON.stringify({ accept: true, reason: "no gated-block change" }) + "\n");
    return;
  }

  if (!args.targetTask) die("--target-task is required for a real run with a changed block");

  // Parse the target task (inline JSON or a path).
  let targetTaskObj;
  try {
    const raw = fs.existsSync(args.targetTask)
      ? fs.readFileSync(args.targetTask, "utf8")
      : args.targetTask;
    targetTaskObj = JSON.parse(raw);
  } catch (err) {
    die(`cannot parse --target-task: ${err.message}`);
  }
  const targetInput = targetTaskObj && targetTaskObj.vars && targetTaskObj.vars.input;
  const targetGolden = targetTaskObj && targetTaskObj.vars && targetTaskObj.vars.golden_label;
  if (typeof targetInput !== "string" || typeof targetGolden !== "string") {
    die("--target-task must be {\"vars\":{\"input\":\"...\",\"golden_label\":\"...\"}}");
  }

  // Build the combined tasks file: corpus + the target task row.
  const res = TARGET_RESOURCES[args.target];
  const corpusText = fs.readFileSync(path.join(SKILL_DIR, res.tasks), "utf8").replace(/\s*$/, "");
  const combinedDir = fs.mkdtempSync(path.join(os.tmpdir(), "eval-gate-tasks-"));
  const combinedFile = path.join(combinedDir, "combined.jsonl");
  fs.writeFileSync(combinedFile, corpusText + "\n" + JSON.stringify(targetTaskObj) + "\n");

  const tokens = tokensFor(args.target);
  const currentPrompt = renderSkillPrompt(args.target, currentBlock, tokens);
  const candidatePrompt = renderSkillPrompt(args.target, candidateBlock, tokens);

  let verdict;
  try {
    const currentResults = runPromptfoo(currentPrompt, args.target, combinedFile, args.repeat);
    const candidateResults = runPromptfoo(candidatePrompt, args.target, combinedFile, args.repeat);
    verdict = computeVerdict(currentResults, candidateResults, { task_id: targetInput }, {});
  } catch (err) {
    die(`gate run failed: ${err.message}`);
  }

  // --append-on-accept: on accept, append the synthesized target task to the corpus.
  if (args.appendOnAccept && verdict.accept) {
    const guard = synthesizedCheck(targetInput);
    if (!guard.ok) {
      die(`refusing to append non-synthesized target task: ${guard.reason}`, { verdict });
    }
    const corpusPath = path.join(SKILL_DIR, res.tasks);
    const existing = fs.readFileSync(corpusPath, "utf8").replace(/\s*$/, "");
    fs.writeFileSync(corpusPath, existing + "\n" + JSON.stringify(targetTaskObj) + "\n");
    verdict.appended_to = res.tasks;
  }

  process.stdout.write(JSON.stringify(verdict) + "\n");
}

main();
