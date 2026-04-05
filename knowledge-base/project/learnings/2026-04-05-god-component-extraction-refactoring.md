# Learning: God component extraction refactoring patterns

## Problem

`apps/web-platform/app/(auth)/connect-repo/page.tsx` grew to 1380 lines containing 13 inline SVG icons, 4 UI primitives, 8 state-view components, font declarations, types, and the main orchestrator. The file was flagged by code-quality-analyst and architecture-strategist agents during PR #1464 review.

## Solution

Extracted into 18 files following existing `@/components/<domain>/<file>` convention:

- **Icons:** Single `components/icons/index.tsx` (13 named exports) — individual files for 6-10 line SVGs is over-engineering
- **UI primitives:** Individual files in `components/ui/` (badge, gold-button, outlined-button, card, constants)
- **Shared deps:** `components/connect-repo/fonts.ts`, `types.ts`, `lib/relative-time.ts`
- **State views:** 9 individual files in `components/connect-repo/`
- **Orchestrator:** `page.tsx` slimmed to 427 lines (handlers + state management + render switch)

The 250-line target for page.tsx was aspirational — the orchestrator's 3 useEffects, 2 useCallbacks, 11 handlers, and 9-state render switch are the irreducible core.

## Key Insight

For god component extraction, the "smart parent / dumb children" pattern works well: parent retains all state, effects, and handlers; children receive only props (data + callbacks). The extraction boundary is clean when no child reaches back into parent state.

Font sharing via a shared module (`fonts.ts`) follows the Next.js recommended pattern and avoids prop-threading font class names through every component.

Review agents unanimously agreed: consolidate small SVG icons into a single file rather than creating individual files. The threshold is ~10 lines per component — below that, the file overhead exceeds the organizational benefit.

## Tags

category: refactoring
module: web-platform/connect-repo
