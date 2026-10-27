// Pure function: enriches known Pencil API error messages with actionable hints.
// Extracted for testability — no external dependencies.

// Tools @pencil.dev/cli 0.2.9 removed (#11143). Retire with #11156.
const REMOVED_TOOL_HINTS = {
  set_variables:
    "set_variables is not available in the headless CLI. Set variables with SetVariables(...) inside batch_design (syntax: get_editor_state({ include_schema: true })).",
  find_empty_space_on_canvas:
    "find_empty_space_on_canvas is not available in the headless CLI. Use FindEmptySpace(...) inside batch_design (syntax: get_editor_state({ include_schema: true })).",
  get_style_guide:
    "get_style_guide is not available in the headless CLI. Call get_guidelines() with no arguments to list the available guides, or continue with brand tokens.",
  get_style_guide_tags:
    "get_style_guide_tags is not available in the headless CLI. Call get_guidelines() with no arguments to list the available guides, or continue with brand tokens.",
  search_all_unique_properties:
    "search_all_unique_properties has no headless equivalent in this CLI version. Read nodes with batch_get and inspect them.",
  replace_all_matching_properties:
    "replace_all_matching_properties has no headless equivalent in this CLI version. Apply the change with Update(...) calls inside batch_design.",
};

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
      "index with batch_get on the parent. See #1117.";
  }
  const removed = text.match(/^Unknown tool: ([a-z_]+)/m);
  if (removed && Object.hasOwn(REMOVED_TOOL_HINTS, removed[1])) {
    return text + "\n\n[adapter hint] " + REMOVED_TOOL_HINTS[removed[1]];
  }
  return text;
}
