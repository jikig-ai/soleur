# LikeC4 DSL — Syntax Reference

[LikeC4](https://likec4.dev/) describes a C4 model as code and renders it as
interactive, drill-down diagrams. Soleur keeps ONE consolidated model and scopes
it to each C4 level with views. A project is a directory of `.c4` files merged
together; Soleur splits it into `spec.c4`, `model.c4`, `views.c4`.

## Project shape

```likec4
// spec.c4 — declare element kinds + tags once
specification {
  element actor     { style { shape person } }
  element system
  element container
  element database  { style { shape storage } }
  element component { style { shape component } }
  tag external
}
```

```likec4
// model.c4 — declare every element ONCE; nesting creates C4 boundaries
model {
  customer = actor "Customer" {
    description "Uses the product"
  }

  platform = system "Acme Platform" {
    web = system "Web App" {
      ui  = container "Dashboard" {
        technology "React, Next.js"
        description "UI and session management"
        style { shape browser }
      }
      api = container "API Routes" {
        technology "Next.js API"
      }
    }
    db = database "Primary DB" {
      technology "PostgreSQL"
    }
  }

  stripe = system "Stripe" {
    #external
    description "Payments"
  }

  // relationships: from -> to "label" { technology "..." }
  customer -> ui "Uses" { technology "HTTPS" }
  ui  -> api "Calls" { technology "HTTPS" }
  api -> db  "Reads/writes" { technology "SQL" }
  api -> stripe "Charges" { technology "HTTPS" }
}
```

```likec4
// views.c4 — one view per level; `view <id> of <el>` enables drill-down
views {
  view context {
    title "System Context (C4 L1)"
    include customer, platform, stripe
    style element.tag == #external { color muted }
    autoLayout TopBottom
  }

  // `of platform` → the `platform` box in `context` gets a drill-down button
  view containers of platform {
    title "Containers (C4 L2)"
    include customer, platform.web, platform.web.ui, platform.web.api, platform.db, stripe
    autoLayout TopBottom
  }
}
```

## Rules that matter

| Concept | Mermaid C4 (old) | LikeC4 (now) |
|---------|------------------|--------------|
| Element | `System(id,"L","D")` | `id = system "L" { description "D" }` |
| Tech    | 2nd arg of `Container(...)` | `technology "…"` property |
| External | `_Ext` suffix | `#external` tag |
| Boundary | `Container_Boundary(...) {}` | element **nesting** (parent `{ child }`) |
| Relationship | `Rel(a,b,"L","T")` | `a -> b "L" { technology "T" }` |
| Drill-down | not possible | `view X of <element>` + `navigateTo` |

- **Declare each element once.** Different views `include` subsets of the one
  model — never redefine an element per view.
- **Reference nested elements by qualified path** in views and cross-boundary
  relationships: `platform.web.ui`. Top-level ids may be used unqualified.
- **Nesting is the boundary.** A parent element with children renders as a
  boundary box; there is no separate boundary keyword.
- **Descriptions / multi-line:** single quotes `'…'`, double quotes `"…"`, or
  triple quotes `'''…'''` / `"""…"""` for multi-line.
- **Views:** `include *` pulls the element and its descendants (inside `view of
  X`, scoped to X). Use explicit `include a, b, c` for precise level fidelity.
  `autoLayout TopBottom | LeftRight`. Style by tag: `style element.tag == #external { color muted }`.

## Drill-down (the point of LikeC4)

Define a level-specific view `of` a parent element. LikeC4 adds a navigation
button on that element in any higher view, so the reader clicks Context →
Containers → Components. Relationships you draw to/from a parent element (e.g.
`customer -> platform`) coexist with finer-grained edges to its children
(`customer -> ui`) — both are kept; each view shows the ones whose endpoints it
includes.

## Validate

```bash
npx -y likec4@latest validate .                 # parse + check references
npx -y likec4@latest export json -o "$(mktemp)" .  # element/relation/view counts
```

Export to a temp path, as above, never into the diagrams directory. Never write raw `export json`
output onto the committed `model.likec4.json`. Every writer publishes the canonical
one-value-per-line format with blank view hashes, which is what lets git merge two regenerations
(ADR-235, #8542):

- In any repo, run `bash <plugin-root>/scripts/render-c4-model.sh` (in a SKILL.md fence, `${CLAUDE_PLUGIN_ROOT}`) — the plugin's
  renderer, which the merge resolver also runs (the Soleur repo keeps a
  `scripts/regenerate-c4-model.sh` wrapper around it). `soleur:sync`'s C4 producer canonicalizes
  too. To canonicalize by hand, go through a temp file so a failure never truncates the artifact:
  `node <plugin-root>/lib/c4-canonical-cli.mjs "$raw" > "$tmp" && mv "$tmp" model.likec4.json`.
- To check a committed file, run `node <plugin-root>/lib/c4-canonical-cli.mjs --check model.likec4.json`.
  It prints `canonical` (exit 0) or `not-canonical` (exit 1).

Full docs: <https://likec4.dev/>.
