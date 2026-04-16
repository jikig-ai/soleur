# Learning: react-resizable-panels v4 treats numeric sizes as pixels, not percentages

## Problem

After shipping PR #2433 (resizable KB panels), production showed a broken layout:
the KB sidebar was ~18px wide (nearly invisible, showing only first letters of
"Knowledge Base"), the document viewer filled most of the viewport, and resize
handles barely worked.

The code used:

```tsx
<Panel defaultSize={18} minSize={10} maxSize={25} ...>
```

The intent was 18% / 10% / 25% — matching the plan. Documentation reinforced
this: the API docs said "Percentage of the parent Group (0..100)" for numeric
sizes.

## Solution

In `react-resizable-panels` v4, the **runtime implementation treats numbers as
pixels, not percentages**. The minified library source contains:

```js
function parseSize(e) {
  switch (typeof e) {
    case "number": return [e, "px"];  // ← numbers are pixels
    case "string": {
      const t = parseFloat(e);
      return e.endsWith("%") ? [t, "%"]
           : e.endsWith("px") ? [t, "px"]
           // ...
    }
  }
}
```

To pass percentages, use string form:

```tsx
<Panel defaultSize="18%" minSize="10%" maxSize="25%" ...>
```

## Key Insight

**Do not trust library docstrings alone — verify against runtime behavior when
observed output contradicts intent.** The v4 docstring claimed numbers are
percentages, but the parsing function treated them as pixels. The discrepancy
only surfaced in production because:

1. The test mocks captured Panel props verbatim, so tests passed with `18` as a
   prop value — they never exercised the library's internal size resolution.
2. The local/dev environments didn't reveal the issue because the specific
   combination of `h-full` on Group + narrow containers just looked "tight" in
   some viewport sizes but wasn't obviously broken.
3. Browser screenshots at actual production viewport widths were needed to
   detect the bug.

**Detection pattern:** When using a new library's sizing/dimension API and the
result looks "way off" in production, grep the library source for the sizing
parse function to see whether numbers are pixels, percentages, or another unit.

**Prevention:** When using any third-party library for layout, always pass
**explicit units** (strings like `"18%"`, `"100px"`, `"1rem"`) rather than bare
numbers — even when the docstring claims a default unit. Explicit units make
the intent visible at the call site and survive library version upgrades.

## Session Errors

1. **Trusted docstring over implementation** — docstring said "Percentage (0..100)"
   but code treated numbers as pixels. Recovery: grep library source for
   `typeof === "number"` to find the parse function. Prevention: verify with
   source code, not just docs, when behavior looks wrong.

2. **Tests passed but production was broken** — mock captured the prop value
   (`18`) without exercising the library's size-resolution logic. Prevention:
   integration tests with the real library would have caught this; alternatively,
   always use explicit units in the source so the test assertion (`"18%"`) matches
   the actual behavior.

## Tags

category: ui-bugs
module: react-resizable-panels, kb-layout
