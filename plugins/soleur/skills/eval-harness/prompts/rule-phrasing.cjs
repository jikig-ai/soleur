// rule-phrasing.cjs — chat-format prompt functions for the B5 rule-phrasing A/B (#8290).
//
// MEASUREMENT-ONLY target (not registered in gated-skills.json). The first `.cjs`
// chat-array prompt in eval-harness: every other config uses `file://prompts/*.txt`.
//
// Each arm is the LIVE always-loaded corpus — AGENTS.md + "\n" + AGENTS.rules.md, read at
// call time — as the SYSTEM message, and the task scenario (`vars.input`) as the USER
// message. That mirrors how a session loads the rules. The three arms differ only in the
// four target rules pinned in `rule-phrasing-bodies.json`:
//   prohibition — the four bodies verbatim (the live corpus, untouched);
//   positive    — the four body lines swapped for the fixture's positive-led rewrites;
//   none        — the four body lines AND their four AGENTS.md `- [id: …]` pointers removed.
//
// HASH-LOCK. The generator THROWS when a live body's sha256 differs from the fixture's
// `prohibition_sha256`, so a rerun after any edit to AGENTS.rules.md cannot silently
// compare stale text. It also throws when a line to swap/remove is not found exactly once,
// when a positive body drops/moves a `[tag: …]` token or exceeds the 600 B body cap, and
// when the corpus carries Nunjucks syntax promptfoo would re-render.
//
// promptfoo 0.123.1 calls `fn({ vars, provider, config })` for `file://<path>.cjs:<fn>`
// (src/prompts/processors/javascript.ts); a returned array is JSON-stringified and the
// anthropic provider lifts the `system` message into the Messages API `system` field.
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const DEFAULT_FIXTURE = path.join(__dirname, "rule-phrasing-bodies.json");
const PER_RULE_CAP = 600; // mirrors scripts/lint-agents-rule-budget.py PER_RULE_CAP
const ARMS = ["prohibition", "positive", "none"];

// Walk up from this file to the first directory holding both corpus files. Robust to the
// worktree layout (.worktrees/<name>/plugins/…) and to promptfoo's cwd.
function findRepoRoot(start) {
  let dir = start;
  for (;;) {
    if (fs.existsSync(path.join(dir, "AGENTS.md")) && fs.existsSync(path.join(dir, "AGENTS.rules.md"))) {
      return dir;
    }
    const parent = path.dirname(dir);
    if (parent === dir) throw new Error(`rule-phrasing: no AGENTS.md + AGENTS.rules.md above ${start}`);
    dir = parent;
  }
}

function sha256(s) {
  return crypto.createHash("sha256").update(s, "utf8").digest("hex");
}

function tagsOf(s) {
  return s.match(/\[[a-z-]+:[^\]]*\]/g) || [];
}

function indexOfExactlyOnce(lines, predicate, what) {
  const hits = [];
  lines.forEach((l, i) => { if (predicate(l)) hits.push(i); });
  if (hits.length !== 1) {
    throw new Error(`rule-phrasing: expected exactly 1 ${what}, found ${hits.length}`);
  }
  return hits[0];
}

function loadFixture(fixturePath) {
  const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  const ids = Object.keys(fixture);
  if (ids.length !== 4) throw new Error(`rule-phrasing: fixture must pin 4 rules, has ${ids.length}`);
  for (const id of ids) {
    const f = fixture[id];
    for (const k of ["prohibition", "prohibition_sha256", "positive"]) {
      if (typeof f[k] !== "string" || f[k] === "") throw new Error(`rule-phrasing: ${id}.${k} missing`);
    }
    if (sha256(f.prohibition) !== f.prohibition_sha256) {
      throw new Error(`rule-phrasing: hash-lock: fixture ${id}.prohibition does not hash to its prohibition_sha256`);
    }
    if (JSON.stringify(tagsOf(f.positive)) !== JSON.stringify(tagsOf(f.prohibition))) {
      throw new Error(`rule-phrasing: ${id}.positive does not carry the prohibition's [tag] tokens byte-identical and in order`);
    }
    if (Buffer.byteLength(f.positive, "utf8") > PER_RULE_CAP) {
      throw new Error(`rule-phrasing: ${id}.positive exceeds the ${PER_RULE_CAP} B body cap`);
    }
  }
  return fixture;
}

// buildCorpus(arm, opts) -> the system-message text for one arm. opts.root / opts.fixture
// exist for the offline battery (hash-lock test on a temp copy); promptfoo never passes them.
function buildCorpus(arm, opts) {
  if (!ARMS.includes(arm)) throw new Error(`rule-phrasing: unknown arm ${JSON.stringify(arm)}`);
  const o = opts || {};
  const root = o.root || findRepoRoot(__dirname);
  const fixture = loadFixture(o.fixture || process.env.RULE_PHRASING_FIXTURE || DEFAULT_FIXTURE);
  const index = fs.readFileSync(path.join(root, "AGENTS.md"), "utf8").split("\n");
  const rules = fs.readFileSync(path.join(root, "AGENTS.rules.md"), "utf8").split("\n");

  const bodyIdx = {};
  const pointerIdx = {};
  for (const id of Object.keys(fixture)) {
    const tag = `[id: ${id}]`;
    const bi = indexOfExactlyOnce(rules, (l) => l.includes(tag), `AGENTS.rules.md body line for ${id}`);
    const live = rules[bi];
    if (sha256(live) !== fixture[id].prohibition_sha256) {
      throw new Error(`rule-phrasing: hash-lock: live body for ${id} (sha256 ${sha256(live)}) != fixture prohibition_sha256 ${fixture[id].prohibition_sha256}`);
    }
    bodyIdx[id] = bi;
    pointerIdx[id] = indexOfExactlyOnce(index, (l) => l === `- ${tag}`, `AGENTS.md pointer line for ${id}`);
  }

  let outIndex = index;
  let outRules = rules;
  if (arm === "positive") {
    outRules = rules.slice();
    for (const id of Object.keys(fixture)) outRules[bodyIdx[id]] = fixture[id].positive;
  } else if (arm === "none") {
    const dropRules = new Set(Object.values(bodyIdx));
    const dropIndex = new Set(Object.values(pointerIdx));
    outRules = rules.filter((_, i) => !dropRules.has(i));
    outIndex = index.filter((_, i) => !dropIndex.has(i));
  }

  const corpus = outIndex.join("\n") + "\n" + outRules.join("\n");
  // promptfoo Nunjucks-renders every string of a JSON prompt; a corpus carrying template
  // syntax would be silently rewritten, so refuse rather than measure mangled text.
  if (/\{\{|\{%|\{#/.test(corpus)) throw new Error("rule-phrasing: corpus contains Nunjucks syntax promptfoo would re-render");
  return corpus;
}

function messages(arm, context) {
  const vars = (context && context.vars) || {};
  if (typeof vars.input !== "string" || vars.input === "") throw new Error("rule-phrasing: vars.input missing");
  return [
    { role: "system", content: buildCorpus(arm) },
    { role: "user", content: vars.input },
  ];
}

module.exports = {
  prohibition: (context) => messages("prohibition", context),
  positive: (context) => messages("positive", context),
  none: (context) => messages("none", context),
  buildCorpus,
  loadFixture,
  findRepoRoot,
  ARMS,
};
