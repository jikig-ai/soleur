#!/usr/bin/env node
// extract-block.cjs — deterministic projection of a gated classifier block.
//
// A "gated block" is the span of a source file (e.g. the /go routing table, the
// ticket-triage P-level rubric) wrapped in HTML-comment sentinels:
//
//   <!-- eval-gate:block:<block-id>:start -->
//   ...the classifier rules (the SSOT)...
//   <!-- eval-gate:block:<block-id>:end -->
//
// This is the mechanical link that makes the eval-harness skill-arm prompt a
// projection of the production source (NOT a hand-copied paraphrase). It is used
// (a) to build the skill-arm prompt and (b) to detect whether an edit changed the
// block at all.
//
// Pure / deterministic: extractBlock() takes text in, returns text out, no I/O.
//
// CLI: node extract-block.cjs <source-file> <block-id>
//   Prints the text strictly between the markers (exclusive of the marker lines),
//   trimmed. Exits non-zero with a clear stderr message if either marker is missing.
"use strict";

const fs = require("node:fs");

// markersFor(blockId): the canonical start/end sentinels for a block id.
function markersFor(blockId) {
  return {
    start: `<!-- eval-gate:block:${blockId}:start -->`,
    end: `<!-- eval-gate:block:${blockId}:end -->`,
  };
}

// extractBlock(sourceText, startMarker, endMarker): the text strictly between the
// two markers, trimmed. Throws (fail-closed) if either marker is absent or the end
// precedes the start.
function extractBlock(sourceText, startMarker, endMarker) {
  if (typeof sourceText !== "string") {
    throw new TypeError("extractBlock: sourceText must be a string");
  }
  const startIdx = sourceText.indexOf(startMarker);
  if (startIdx === -1) {
    throw new Error(`extract-block: start marker not found: ${startMarker}`);
  }
  const endIdx = sourceText.indexOf(endMarker);
  if (endIdx === -1) {
    throw new Error(`extract-block: end marker not found: ${endMarker}`);
  }
  if (endIdx < startIdx) {
    throw new Error(
      `extract-block: end marker ${endMarker} precedes start marker ${startMarker}`,
    );
  }
  const between = sourceText.slice(startIdx + startMarker.length, endIdx);
  return between.trim();
}

// extractBlockById(sourceText, blockId): convenience wrapper using the canonical
// marker convention for a block id.
function extractBlockById(sourceText, blockId) {
  const { start, end } = markersFor(blockId);
  return extractBlock(sourceText, start, end);
}

module.exports = { extractBlock, extractBlockById, markersFor };

if (require.main === module) {
  const [sourceFile, blockId] = process.argv.slice(2);
  if (!sourceFile || !blockId) {
    process.stderr.write(
      "usage: node extract-block.cjs <source-file> <block-id>\n",
    );
    process.exit(2);
  }
  let text;
  try {
    text = fs.readFileSync(sourceFile, "utf8");
  } catch (err) {
    process.stderr.write(`extract-block: cannot read ${sourceFile}: ${err.message}\n`);
    process.exit(1);
  }
  try {
    process.stdout.write(extractBlockById(text, blockId) + "\n");
  } catch (err) {
    process.stderr.write(`${err.message}\n`);
    process.exit(1);
  }
}
