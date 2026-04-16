# Tasks: fix PDF viewer sidebar layout

## Phase 1: Setup

- [ ] 1.1 Verify the bug by reading the current height chain in `pdf-preview.tsx`, `[...path]/page.tsx`, `kb/layout.tsx`, and `(dashboard)/layout.tsx`
- [ ] 1.2 Identify all flex containers between `h-dvh` and the PDF `<canvas>` that lack `min-h-0`

## Phase 2: Core Implementation -- PDF Height Fix

- [ ] 2.1 Add `min-h-0` to the outer wrapper in `pdf-preview.tsx` (`<div className="flex h-full flex-col">` -> `<div className="flex min-h-0 h-full flex-col">`)
- [ ] 2.2 Add `min-h-0` to the inner flex-1 container in `pdf-preview.tsx` that wraps `<Document>`
- [ ] 2.3 Add canvas height constraint via Tailwind utility: `[&_canvas]:max-h-full [&_canvas]:w-auto [&_canvas]:mx-auto` on the container
- [ ] 2.4 Add `min-h-0` to the file preview wrapper in `[...path]/page.tsx` (`<div className="flex-1 overflow-y-auto">` -> `<div className="min-h-0 flex-1 overflow-y-auto">`)
- [ ] 2.5 Verify the KB layout content area div also has `min-h-0` if needed

## Phase 3: Core Implementation -- KB Collapse Icon Alignment

- [ ] 3.1 Remove the floating expand button from the content area in `kb/layout.tsx` (lines 281-292)
- [ ] 3.2 Add the expand button to a header-aligned position in the content area, matching the main sidebar collapse toggle's vertical position and size (`h-6 w-6`)
- [ ] 3.3 Ensure the expand button is only visible when the KB sidebar is collapsed (`kbCollapsed` state)

## Phase 4: Testing

- [ ] 4.1 Test PDF rendering with both sidebars expanded -- no truncation
- [ ] 4.2 Test PDF rendering with main sidebar collapsed, KB sidebar expanded -- no truncation
- [ ] 4.3 Test PDF rendering with both sidebars collapsed -- no truncation
- [ ] 4.4 Test PDF rendering with both collapsed + chat panel open -- no regression
- [ ] 4.5 Test multi-page PDF pagination controls remain visible in all states
- [ ] 4.6 Verify KB expand icon aligns vertically with main sidebar collapse icon when both collapsed
- [ ] 4.7 Verify Cmd+B shortcut still toggles the correct sidebar
- [ ] 4.8 Verify mobile layout is unaffected (below md breakpoint)
