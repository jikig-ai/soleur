---
title: "Pencil batch_design text node property gotchas"
date: 2026-03-10
category: integration-issues
tags: [pencil-mcp, batch-design, text-nodes, design-tools]
symptoms: ["textColor property silently ignored", "text appears left-aligned despite textAlign center", "width property not applied to text nodes"]
module: pencil-mcp
---

# Pencil batch_design Text Node Property Gotchas

## Problem

When creating text nodes via Pencil MCP `batch_design` I() operations, two properties behave unexpectedly:

1. **`textColor` is not a valid property.** The tool returns "Property 'textColor' is invalid on text nodes. Use 'fill' instead." but the text is created without color (defaults to black).
2. **`width` is silently ignored on text nodes.** The text box auto-sizes to content width, making `textAlign: "center"` ineffective for centering within a parent frame — centering only applies within the (tight) text box.

## Solution

### Text color: use `fill` not `textColor`

```javascript
// WRONG -- silently ignored
wordmark=I(banner, {type:"text", content:"SOLEUR", textColor:"#C9A962"})

// RIGHT
wordmark=I(banner, {type:"text", content:"SOLEUR", fill:"#C9A962"})
```

### Text centering: use snapshot_layout + manual x positioning

Since text nodes cannot have a fixed width, centering requires:

1. Create text node at x=0 with `textAlign:"center"`
2. Call `snapshot_layout` to get the rendered text width
3. Calculate `x = (parentWidth - textWidth) / 2`
4. Update the text node x position

```javascript
// Step 1: Create text
title=I(banner, {type:"text", content:"Hello World", fill:"#FFFFFF", textAlign:"center", x:0, y:100})
```

```
// Step 2: snapshot_layout shows textWidth=320 in a 1500px frame
// Step 3: x = (1500 - 320) / 2 = 590
// Step 4: Update
U("titleId", {x:590})
```

## Key Insight

Pencil text nodes are auto-sized containers — they lack a settable `width` property. This means `textAlign: "center"` only centers text within its own bounding box (no-op for single-line text). For visual centering within a parent frame, always follow the two-pass workflow: create, measure with `snapshot_layout`, then reposition. Batch all measurements into a single `snapshot_layout` call for efficiency.

## Tags

category: integration-issues
module: pencil-mcp
