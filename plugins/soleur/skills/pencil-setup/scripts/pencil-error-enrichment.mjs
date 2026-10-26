// Pure function: enriches known Pencil API error messages with actionable hints.
// Extracted for testability — no external dependencies.
//
// Tool surface (CTO ruling 1): the adapter keeps the agent-facing `mcp__pencil__*`
// names stable and translates them onto @pen.dev/cli's REPL. Eight tools are
// live; nine are removed stubs that never reach the engine. REMOVED_TOOL_HINTS is
// the ONE table behind both the adapter's stub handlers and the hint appended to
// an engine `Unknown tool:` line, so the two cannot drift.

export const LIVE_TOOL_NAMES = Object.freeze([
  "open_document",
  "save",
  "batch_design",
  "get_screenshot",
  "export_nodes",
  "get_editor_state",
  "get_variables",
  "read_skill",
]);

// Every hint starts with the removed tool's own name and names a tool that exists.
const REMOVED_TOOL_HINTS = Object.freeze({
  batch_get:
    "batch_get was removed (the engine has no node-dump tool). Read nodes with Get(...) and Print(...) inside batch_design (a batch_design call also auto-saves), or call get_editor_state for the list of top-level nodes.",
  snapshot_layout:
    "snapshot_layout was removed. Layout problems arrive as an `## issues detected:` block on batch_design replies; fix them with Update(...) inside batch_design.",
  get_guidelines:
    'get_guidelines was removed. Read design guidance with read_skill({ path: "guide/<name>.md" }); call read_skill() with no path for the index.',
  get_style_guide:
    'get_style_guide was removed. read_skill() lists the style archetypes; read one with read_skill({ path: "guide/<name>.md" }), or continue with brand tokens.',
  get_style_guide_tags:
    'get_style_guide_tags was removed. read_skill() lists the style archetypes; read one with read_skill({ path: "guide/<name>.md" }), or continue with brand tokens.',
  find_empty_space_on_canvas:
    'find_empty_space_on_canvas was removed. Call FindEmptySpace(...) inside batch_design (grammar: read_skill({ path: "execute.md" })).',
  set_variables:
    'set_variables was removed. Call SetVariables(...) inside batch_design (grammar: read_skill({ path: "execute.md" })).',
  search_all_unique_properties:
    "search_all_unique_properties has no headless equivalent. Read nodes with Get(...) and Print(...) inside batch_design; change them with Update(...) in the same batch_design call.",
  replace_all_matching_properties:
    "replace_all_matching_properties has no headless equivalent. Read with Get(...) and change nodes with Update(...) calls inside batch_design.",
});

export const REMOVED_TOOL_NAMES = Object.freeze(Object.keys(REMOVED_TOOL_HINTS));

// The hint for a removed tool, or undefined for any other name (prototype names
// included).
export function removedToolHint(name) {
  return Object.hasOwn(REMOVED_TOOL_HINTS, name) ? REMOVED_TOOL_HINTS[name] : undefined;
}

// `execute` failures end with advice to retry with `edits`/`editId`, which the
// adapter does not expose; point at the one path that exists instead.
const EXECUTE_RETRY_ADVICE =
  /^- IMPORTANT: Fix this by calling `execute` again with the `edits` parameter.*$/m;
const EXECUTE_EDIT_ID_LINE = /^- `editId`: .*\n?/m;

export function enrichErrorMessage(text) {
  if (text.includes("alignSelf") && text.includes("unexpected property")) {
    return text + "\n\n[adapter hint] alignSelf is not supported on frames. " +
      "Use parent container alignment or layout properties instead. See #1106.";
  }
  if (text.includes("padding") && text.includes("unexpected property")) {
    return text + "\n\n[adapter hint] Text nodes do not support padding. " +
      "Wrap the text in a frame and apply padding to the frame. See #1107.";
  }
  if (text.includes("/id missing required property")) {
    return text + "\n\n[adapter hint] This error often occurs when passing a " +
      "third positional argument to I() (e.g., {after: \"nodeId\"}). Positional " +
      "insertion is not supported. Nodes are appended at end of parent. Use " +
      "M(nodeId, parent, index) to reorder after insertion. Discover the target " +
      "index with Get(...) on the parent inside batch_design. See #1117.";
  }
  const removed = text.match(/^Unknown tool: ([a-z_]+)/m);
  if (removed) {
    const hint = removedToolHint(removed[1]);
    if (hint) return text + "\n\n[adapter hint] " + hint;
    return text;
  }
  if (EXECUTE_RETRY_ADVICE.test(text)) {
    return text
      .replace(
        EXECUTE_RETRY_ADVICE,
        "- IMPORTANT: Fix the operations and re-send the corrected operations with batch_design (the failed block was rolled back)."
      )
      .replace(EXECUTE_EDIT_ID_LINE, "")
      .trimEnd();
  }
  return text;
}
