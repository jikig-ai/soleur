---
title: "fix: pencil I() positional insert returns clear error with M() workaround"
type: fix
date: 2026-03-29
---

# fix: pencil I() positional insert returns clear error with M() workaround

## Overview

The `I()` insert operation in Pencil's `batch_design` does not support positional placement (`{after: "nodeId"}` or `{before: "nodeId"}`). When a caller passes a third positional argument, Pencil returns a misleading error: "Invalid properties: /id missing required property" -- which looks like a schema validation failure rather than an unsupported feature.

The fix adds pre-validation in the MCP adapter (`pencil-mcp-adapter.mjs`) to intercept positional insert patterns before they reach the Pencil REPL, and returns an actionable error message explaining the limitation and the `M(nodeId, parent, index)` workaround.

Closes #1117

## Problem Statement

When an agent (typically `ux-design-lead`) tries to insert a node at a specific position:

```javascript
D=I("parentId", {type:"frame", width:60, height:2, fill:"#C9A962"}, {after:"headlineId"})
```

Pencil returns: `Invalid properties: /id missing required property`

This error is:

1. **Misleading** -- it suggests a missing `id` property, not an unsupported feature
2. **Missing the workaround** -- Pencil supports `M(nodeId, parent, index)` for repositioning, but the error gives no hint

The adapter already has an `enrichErrorMessage()` function that handles similar gotchas (`alignSelf`, `padding` on text nodes). This fix extends that pattern.

## Proposed Solution

One change in `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`:

### Error enrichment in `enrichErrorMessage()` [Updated 2026-03-29]

Add a pattern to `enrichErrorMessage()` to detect the misleading upstream error and append a clear explanation with the `M()` workaround:

```javascript
if (text.includes("/id missing required property")) {
  return text + "\n\n[adapter hint] This error often occurs when passing a " +
    "third positional argument to I() (e.g., {after: \"nodeId\"}). Positional " +
    "insertion is not supported. Nodes are appended at end of parent. Use " +
    "M(nodeId, parent, index) to reorder after insertion. See #1117.";
}
```

This follows the existing `enrichErrorMessage()` pattern used for `alignSelf` (#1106) and `padding` on text nodes (#1107). The Pencil error is let through to the REPL and enriched on the way back -- no regex parsing of the operations string needed.

**Why not pre-validate with regex?** An earlier draft included a regex to detect positional arguments before sending to Pencil. Plan review rejected this: (1) the regex `[^}]*` fails on nested braces (e.g., `{type:"frame", stroke:{...}}`), (2) the enrichment fallback alone achieves all acceptance criteria, (3) adding regex parsing of a free-form DSL creates maintenance burden with no clear benefit over post-hoc error enrichment.

## Technical Considerations

- **No upstream changes**: This is purely adapter-side. Pencil's REPL behavior is unchanged.
- **Consistency**: Follows the existing `enrichErrorMessage()` pattern established for `alignSelf` (#1106) and `padding` on text (#1107).
- **M() operation**: The `M(nodeId, parent, index)` operation is documented and functional -- it was referenced in the X Twitter banner plan. The error message guides callers toward this workaround.
- **Error specificity**: The `/id missing required property` string is specific enough to avoid false positives -- it is the exact error Pencil returns when the third positional argument is misinterpreted as part of the node schema.

## Acceptance Criteria

- [ ] `I(parent, {props}, {after: "siblingId"})` returns a clear error mentioning `M()` workaround instead of "Invalid properties: /id missing required property"
- [ ] `I(parent, {props}, {before: "siblingId"})` returns the same clear error
- [ ] `I(parent, {props})` (normal two-arg form) continues to work unchanged
- [ ] Error message includes `#1117` reference and `M()` example
- [ ] Existing error enrichment for `alignSelf` and `padding` continues to work

## Test Scenarios

- Given Pencil returns an error containing "/id missing required property", when `enrichErrorMessage()` processes it, then the output includes "[adapter hint]" with `M()` workaround and `#1117` reference
- Given Pencil returns an error containing "alignSelf" and "unexpected property", when `enrichErrorMessage()` processes it, then the existing `#1106` hint is still appended (no regression)
- Given Pencil returns an error containing "padding" and "unexpected property", when `enrichErrorMessage()` processes it, then the existing `#1107` hint is still appended (no regression)
- Given a batch_design operations string containing `I(parent, {type:"frame"})` (normal form), when batch_design is called, then it passes through to Pencil normally with no error enrichment

## Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs` | Add `/id missing required property` pattern to `enrichErrorMessage()` with `M()` workaround hint |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- adapter-layer error message improvement for an existing MCP integration.

## References

- GitHub issue: #1117
- Learning: `knowledge-base/project/learnings/2026-03-25-pencil-og-image-design-export-patterns.md` (documents the problem and workaround)
- Learning: `knowledge-base/project/learnings/2026-03-25-pencil-adapter-env-var-screenshot-persistence-api-coercion.md` (error enrichment pattern)
- Existing enrichment: `alignSelf` (#1106), `padding` on text (#1107)
- M() operation documented in: `knowledge-base/project/plans/2026-03-10-feat-x-twitter-banner-plan.md:122`
