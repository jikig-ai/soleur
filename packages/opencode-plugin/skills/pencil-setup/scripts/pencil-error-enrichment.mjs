// Pure function: enriches known Pencil API error messages with actionable hints.
// Extracted for testability — no external dependencies.

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
  return text;
}
