#!/usr/bin/env node
// gen-skill-prompt.cjs — project a gated classifier block into a promptfoo
// skill-arm prompt.
//
// The skill-arm prompt is a MECHANICAL PROJECTION of the source block (extracted
// by extract-block.cjs), not a hand-copied paraphrase. This file owns the fixed
// wrapper (instruction header + the block + the {{input}} trailer) per target.
// Regenerate the committed prompts/<target>-skill.txt whenever the source block
// changes; the AC4 round-trip test asserts generated == committed byte-for-byte.
//
// renderSkillPrompt(target, block, tokens) is PURE (text in, text out). The CLI
// reads the source file on disk via gated-skills.json, extracts the block, reads
// the target's enum for the token list, renders, and writes the projection.
//
// CLI:
//   node gen-skill-prompt.cjs <target>        # write prompts/<target>-skill.txt
//   node gen-skill-prompt.cjs --all           # regenerate every gated target
//   node gen-skill-prompt.cjs <target> --stdout   # print, do not write
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { extractBlock } = require("./extract-block.cjs");

const SKILL_DIR = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(SKILL_DIR, "..", "..", "..", "..");
const REGISTRY = path.join(SKILL_DIR, "gated-skills.json");

// Per-target wrapper. `enumPath` is relative to the skill dir; `render` is pure.
const TARGET_CONFIG = {
  "go-routing": {
    enumPath: "enums/go-routes.json",
    render(block, tokens) {
      return [
        "You are the Soleur /go router. Classify the user's request into EXACTLY ONE route token using this routing table.",
        "",
        "Routing table:",
        block,
        "",
        `Respond with ONLY the single route token (one of: ${tokens.join(", ")}). No explanation, no punctuation, no extra words.`,
        "",
        "User request: {{input}}",
        "Route:",
        "",
      ].join("\n");
    },
  },
  "ticket-triage": {
    enumPath: "enums/triage-levels.json",
    render(block, tokens) {
      return [
        "You are the Soleur ticket-triage classifier. Assign a priority level to the GitHub issue using this rubric.",
        "",
        "Priority rubric:",
        block,
        "",
        `Respond with ONLY the single priority token (one of: ${tokens.join(", ")}). No explanation, no extra words.`,
        "",
        "Issue:",
        "{{input}}",
        "Priority:",
        "",
      ].join("\n");
    },
  },
  "lane-inference": {
    enumPath: "enums/lane.json",
    render(block, tokens) {
      return [
        "You are the Soleur brainstorm lane classifier. Classify the feature description into EXACTLY ONE lane using this rule.",
        "",
        "Lane inference rule:",
        block,
        "",
        `Respond with ONLY the single lane token (one of: ${tokens.join(", ")}). No explanation, no punctuation, no extra words.`,
        "",
        "Feature description: {{input}}",
        "Lane:",
        "",
      ].join("\n");
    },
  },
  "incident-threshold": {
    enumPath: "enums/incident-threshold.json",
    render(block, tokens) {
      return [
        "You are the Soleur incident brand-survival classifier. Assign a threshold to the incident description using this rubric.",
        "",
        "Classification rubric:",
        block,
        "",
        `Respond with ONLY the single threshold value (exactly one of: ${tokens.join(", ")}). No explanation, no extra words.`,
        "",
        "Incident:",
        "{{input}}",
        "Threshold:",
        "",
      ].join("\n");
    },
  },
};

// renderSkillPrompt(target, block, tokens): PURE projection of a block into the
// target's skill-arm prompt. Throws on an unknown target (fail-closed).
function renderSkillPrompt(target, block, tokens) {
  const cfg = TARGET_CONFIG[target];
  if (!cfg) {
    throw new Error(`gen-skill-prompt: unknown target ${JSON.stringify(target)}`);
  }
  return cfg.render(block, tokens);
}

function loadRegistry() {
  return JSON.parse(fs.readFileSync(REGISTRY, "utf8"));
}

function entryFor(target) {
  const entry = loadRegistry().find((e) => e.target === target);
  if (!entry) {
    throw new Error(`gen-skill-prompt: target ${JSON.stringify(target)} not in gated-skills.json`);
  }
  return entry;
}

function tokensFor(target) {
  const cfg = TARGET_CONFIG[target];
  const enumAbs = path.join(SKILL_DIR, cfg.enumPath);
  const arr = JSON.parse(fs.readFileSync(enumAbs, "utf8"));
  if (!Array.isArray(arr)) {
    throw new Error(`gen-skill-prompt: enum ${cfg.enumPath} is not an array`);
  }
  return arr;
}

// generateFromDisk(target): read source_file, extract the block, render. Returns
// { prompt, projectedPromptPath }.
function generateFromDisk(target) {
  const entry = entryFor(target);
  const sourceAbs = path.join(REPO_ROOT, entry.source_file);
  const sourceText = fs.readFileSync(sourceAbs, "utf8");
  const block = extractBlock(sourceText, entry.block_start_marker, entry.block_end_marker);
  const prompt = renderSkillPrompt(target, block, tokensFor(target));
  return { prompt, projectedPromptPath: path.join(REPO_ROOT, entry.projected_prompt_path) };
}

module.exports = { renderSkillPrompt, generateFromDisk, TARGET_CONFIG, tokensFor };

if (require.main === module) {
  const args = process.argv.slice(2);
  const toStdout = args.includes("--stdout");
  const all = args.includes("--all");
  const targets = all
    ? loadRegistry().map((e) => e.target)
    : args.filter((a) => !a.startsWith("--"));

  if (targets.length === 0) {
    process.stderr.write(
      "usage: node gen-skill-prompt.cjs <target> [--stdout] | --all\n",
    );
    process.exit(2);
  }

  try {
    for (const target of targets) {
      const { prompt, projectedPromptPath } = generateFromDisk(target);
      if (toStdout) {
        process.stdout.write(prompt);
      } else {
        fs.writeFileSync(projectedPromptPath, prompt);
        process.stderr.write(`gen-skill-prompt: wrote ${projectedPromptPath}\n`);
      }
    }
  } catch (err) {
    process.stderr.write(`${err.message}\n`);
    process.exit(1);
  }
}
