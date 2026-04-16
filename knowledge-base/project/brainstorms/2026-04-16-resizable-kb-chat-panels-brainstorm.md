---
title: Resizable KB Navigation and Chat Panels
date: 2026-04-16
status: complete
issue: 2434
branch: feat-resizable-kb-chat-panels
---

# Resizable KB Navigation and Chat Panels

## What We're Building

Two work streams to improve the KB layout experience:

1. **Auto-growing chat input** (quick ship): Replace the fixed 44px single-row textarea with an auto-growing textarea that expands as the user types longer prompts, capped at a max height.

2. **Resizable panels** (UX spec first): Add continuous drag-to-resize handles between the three-panel KB layout (KB nav sidebar | Document viewer | Chat panel) so users can adjust panel widths to their preference.

## Why This Approach

The KB is the product's compounding moat. Currently:

- File names truncate at the fixed 256px sidebar width — users can't distinguish similarly-named files
- The chat panel at 380px feels cramped for reading agent responses with tables or code blocks
- The chat input at 44px discourages longer, more detailed prompts

These friction points undermine the daily-use stickiness that Phase 3 targets.

### Phasing rationale

The auto-growing chat input is a standard pattern (CSS `field-sizing: content` or JS auto-resize) that can ship in hours. Resizable panels require interaction design decisions (handle placement, min/max constraints, collapse interaction, persistence) that benefit from UX design lead review before implementation.

## Key Decisions

| # | Decision | Choice | Alternatives Considered |
|---|----------|--------|------------------------|
| 1 | Phasing | Decouple: auto-grow input ships first, resizable panels ship after UX spec | Ship all together; panels only |
| 2 | Resize model | Continuous drag-to-resize (like VS Code) | Discrete size options (compact/default/wide toggle); CSS-native resize |
| 3 | Collapse interaction | Cmd+B restores last user-set drag width (not default 256px) | Always reset to default; remove Cmd+B entirely |
| 4 | Implementation | `react-resizable-panels` library (~4kb gzip) | Custom `useResizablePanel` hook; CSS-native `resize` property |
| 5 | UX design | UX design lead creates wireframes before panel implementation | Skip to planning with brainstorm spec only |
| 6 | Persistence | Resized widths persist to localStorage across sessions | Reset on navigation; no persistence |

## Open Questions

1. **Min/max width constraints** — What are the minimum and maximum widths for KB sidebar, document viewer, and chat panel? Need to prevent layout breakage (e.g., sidebar at 90% width).
2. **Default proportions** — What should the default panel split be on first load? CMO flagged defaults as a conversion surface — cramped defaults increase bounce.
3. **Tablet breakpoint behavior** — How do resizable panels degrade at tablet widths (769-1024px)? Current sidebar collapses on mobile. Learnings warn about tablet regression.
4. **Chat input growth direction** — Does the textarea grow upward (pushing messages) or downward? Standard is upward growth with a max-height cap.
5. **Double-click to reset** — Should double-clicking a drag handle reset the panel to its default width? Common pattern in IDEs.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** All three sub-features align with Phase 3 ("Make it Sticky"). Recommended decoupling auto-grow input (hours, standard pattern) from resizable panels (days, needs UX spec). Flagged resize-collapse interaction as a key design question. KB file name truncation is a real usability problem — it's the primary navigation affordance. Chat panel width at 380px is narrow for structured agent responses. Routing to UX design lead for panel interaction spec.

### Marketing (CMO)

**Summary:** Ship quietly — this is UX polish, not a feature launch. Focus on getting default proportions right (conversion surface). Update product screenshots after shipping. Include in next changelog as one-liner under UX improvements. Compound these polish items into a "craftsmanship" narrative over time. Recommended delegating layout review to conversion-optimizer and ux-design-lead.

## Technical Context

- **KB sidebar**: `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` — fixed `md:w-64` (256px), collapse via `useSidebarCollapse` hook + Cmd+B
- **Chat panel**: `apps/web-platform/components/chat/kb-chat-sidebar.tsx` — uses Sheet component, fixed `w-[380px]` on desktop. Mobile already has 3-snap drag
- **Chat input**: `apps/web-platform/components/chat/chat-input.tsx` — single-row `<textarea>` at `h-[44px]`, `resize-none`
- **UI framework**: Tailwind CSS v4, no component library
- **Mobile Sheet pattern**: `apps/web-platform/components/ui/sheet.tsx` — pointer-capture-based drag with snap points (mobile only)
- **Persistence pattern**: `useSidebarCollapse` hook uses localStorage — follow this pattern for resize widths
