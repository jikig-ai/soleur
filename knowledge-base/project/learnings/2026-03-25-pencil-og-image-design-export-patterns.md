---
title: "Pencil OG image design: flexbox centering, export filename quirk, and per-page OG template"
date: 2026-03-25
category: integration-issues
tags: [pencil-mcp, batch-design, export, og-image, eleventy, seo]
symptoms: ["export_nodes uses node ID as filename", "I() positional insertion fails with misleading error", "base.njk hardcodes single OG image for all pages"]
module: pencil-mcp
---

# Pencil OG Image Design: Flexbox Centering, Export Filename Quirk, and Per-Page OG Template

## Problem

Three issues encountered while designing and exporting a 1200x630 OG image via Pencil MCP headless CLI, and integrating it into an Eleventy site:

1. **Centering content in batch_design frames** — The previously documented two-pass approach (create text → snapshot_layout → reposition) is more complex than needed for simple centered layouts.
2. **export_nodes uses node IDs as filenames** — Exported file named `wZrMw.png` instead of the human-readable node name `Pricing OG Image`.
3. **No positional insertion in batch_design** — `I(parent, props, {after: "siblingId"})` fails with misleading "Invalid properties: /id missing required property" error.
4. **Eleventy base.njk hardcoded OG image** — All pages shared a single OG image with no per-page override.

## Solution

### Centering: use flexbox alignment on parent frame

Instead of the two-pass snapshot_layout workaround, set `alignItems` and `justifyContent` on the parent frame:

```javascript
// Create vertical layout frame with centered children
ogFrame=I(document, {type:"frame", name:"Pricing OG Image", width:1200, height:630, fill:"#0A0A0A", layout:"vertical", padding:[60,80], alignItems:"center", justifyContent:"center"})

// All children are automatically centered — no snapshot_layout needed
headline=I(ogFrame, {type:"text", content:"Every department.\nOne price.", fontSize:56, fontWeight:500, fontFamily:"Cormorant Garamond", fill:"#FFFFFF", textAlign:"center"})
```

The two-pass approach is still needed for pixel-precise positioning within non-flexbox frames.

### Export filename: manual rename after export

```bash
# export_nodes saves as <nodeId>.png
export_nodes(nodeIds: ["wZrMw"], outputDir: "/path/to/images", format: "png", scale: 2)
# Rename to human-readable name
mv wZrMw.png pricing-og.png
```

Filed #1116 to track upstream fix.

### Positional insertion: convert existing placeholder nodes

When you need a node between existing children, don't try `{after: "id"}` — it's not supported. Instead, insert spacer/placeholder nodes upfront and convert them via `U()`:

```javascript
// DON'T — fails with misleading error
goldLine=I("parentId", {type:"frame", width:60, height:2, fill:"#C9A962"}, {after:"headlineId"})

// DO — insert spacer during initial layout, then convert it
spacer=I(parent, {type:"frame", width:"fill_container", height:32})
// Later, convert spacer to the actual element:
U("spacerId", {width:60, height:2, fill:"#C9A962"})
```

Filed #1117 to track positional insertion support.

### Per-page OG images: Nunjucks defaults in base.njk

```html
<!-- Before: hardcoded for all pages -->
<meta property="og:image" content="{{ site.url }}/images/og-image.png">

<!-- After: per-page override with fallback -->
<meta property="og:image" content="{{ site.url }}/images/{{ ogImage | default('og-image.png') }}">
<meta property="og:image:alt" content="{{ ogImageAlt | default(site.name + ' - ' + site.tagline) }}">
```

Pages set frontmatter: `ogImage: pricing-og.png` and `ogImageAlt: "Soleur Pricing — Every department. One price. $0."`

## Session Errors

1. **batch_design I() with {after: "nodeId"} failed** — Error: "Invalid properties: /id missing required property". The error message doesn't indicate positional insertion is unsupported — it looks like a schema validation failure. Recovery: deleted the failed operation (rolled back), used U() on existing spacer. Prevention: Filed #1117; document workaround in learning.

2. **export_nodes used node ID as filename** — No error, but unexpected behavior. Recovery: `mv wZrMw.png pricing-og.png`. Prevention: Filed #1116; always plan a rename step after export_nodes.

## Key Insight

Pencil MCP's batch_design supports flexbox-style layout properties (`alignItems`, `justifyContent`) on parent frames, which makes the two-pass snapshot_layout centering workaround unnecessary for most use cases. The earlier learning (2026-03-10-pencil-batch-design-text-node-gotchas.md) should be updated to mention this simpler approach as the primary recommendation, with snapshot_layout reserved for pixel-precise positioning outside flexbox layouts.

For OG image design specifically: the combination of `layout:"vertical"`, `alignItems:"center"`, `justifyContent:"center"`, and `padding` on a fixed-size frame produces well-balanced compositions with minimal iteration.

## Related

- [pencil-batch-design-text-node-gotchas](./2026-03-10-pencil-batch-design-text-node-gotchas.md) — text centering workaround (partially superseded by flexbox approach)
- [pencil-adapter-env-var-screenshot-persistence-api-coercion](./2026-03-25-pencil-adapter-env-var-screenshot-persistence-api-coercion.md) — adapter fixes from same dogfood session
- GitHub: #1116 (export filenames), #1117 (positional insertion), #656 (pricing page)

## Tags

category: integration-issues
module: pencil-mcp
