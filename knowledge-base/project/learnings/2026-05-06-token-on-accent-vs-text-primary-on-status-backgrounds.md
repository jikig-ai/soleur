---
title: text-soleur-text-on-accent vs text-soleur-text-primary on status backgrounds
date: 2026-05-06
category: best-practices
tags: [tokenization, light-theme, contrast, parallel-agents, migration]
related_pr: "#3308"
related_pr_parent: "#3271"
---

# text-soleur-text-on-accent vs text-soleur-text-primary on status backgrounds

## Problem

When migrating Tailwind hardcoded grays to Soleur design tokens, three of six parallel migration agents (Groups A, B, C of PR #3308) independently produced the same wrong mapping for `text-white` on status/brand-color backgrounds:

```tsx
// Wrong (low contrast in light theme)
className="rounded-lg bg-amber-600 ... text-soleur-text-primary"
className="rounded bg-red-700 ... text-soleur-text-primary"
className="rounded-lg bg-blue-600 ... text-soleur-text-primary"
```

`text-soleur-text-primary` resolves to **dark text in light theme** (intended for body content on light surfaces). Pairing it with a saturated status background produces dark-on-color, which fails the original `text-white` contrast intent.

Six sites across four files needed post-hoc fixing:

- `components/chat/welcome-card.tsx` (avatar)
- `components/chat/workflow-lifecycle-bar.tsx` (Start new conversation CTA)
- `components/chat/interactive-prompt-card.tsx` (×3 CTAs)
- `components/chat/chat-input.tsx` (send button)
- `components/kb/share-popover.tsx` (Revoke destructive)
- `components/settings/delete-account-dialog.tsx` (Confirm Deletion destructive)
- `components/chat/notification-prompt.tsx` (Allow CTA)

## Solution

Use `text-soleur-text-on-accent` — it resolves to **white in both Forge and Radiance** by design, exactly preserving the original `text-white` contrast pairing across themes.

```tsx
// Correct
className="rounded-lg bg-amber-600 ... text-soleur-text-on-accent"
className="rounded bg-red-700 ... text-soleur-text-on-accent"
```

## Root Cause

The token-migration prompt enumerated:

> `text-white`, `text-zinc-50`, `text-zinc-100`, `text-zinc-200`, `text-neutral-100`, `text-neutral-200` → `text-soleur-text-primary`

This is correct for `text-white` over neutral surfaces (body text on dark cards in Forge, or what *should* be dark body text in Radiance). It is wrong for `text-white` paired with `bg-<status>-NNN` or `bg-amber-NNN`, where the original intent is "white text on a saturated fill" — a contrast pairing the `text-soleur-text-on-accent` token exists to preserve.

The CTA-fill section of the prompt did mention:
> `bg-amber-500 text-black`, `bg-yellow-500 text-zinc-900` → `bg-soleur-accent-gold-fill text-soleur-text-on-accent`

But three agents handled the case where the literal `bg-amber-600` (not `bg-amber-500`) and the literal `bg-red-700`, `bg-blue-600` were kept literal as status colors per the "DO NOT CHANGE: status colors" rule, while `text-white` was migrated standalone.

## Key Insight

When a migration prompt has TWO rules:

1. "Status backgrounds stay literal"
2. "Map `text-white` → `text-soleur-text-primary`"

…rule (2) silently shadows the contrast intent that rule (1) preserves. The fix is a third rule that takes precedence:

> **If the same className contains both a literal status/brand background (`bg-<color>-NNN`) and `text-white`, map `text-white` to `text-soleur-text-on-accent`** (white in both themes by design — same contrast as the original).

This rule must appear *before* the generic `text-white` mapping in the prompt, and the agent must check both directions: the substring `text-white` in a className with any literal `bg-<status>-NNN` adjacent.

## Prevention

For future token migrations:

1. **Add a precedence-ordered mapping section** to migration prompts: contrast-pair rules (status bg + text-white) come BEFORE generic substring mappings. Order matters because the agent applies the first matching rule.
2. **Add a verification grep** to the migration agent's contract: before reporting "Group N complete," run `rg 'bg-(amber|red|orange|blue|green|emerald|cyan|pink|violet|sky|indigo|rose|fuchsia|teal|yellow)-[0-9]+[^"]*text-soleur-text-primary'` and assert zero hits.
3. **Add a post-merge regression assertion** to `light-theme-tokenization.test.tsx` (or a sibling test file): grep the tokenized surfaces for the same anti-pattern and fail if any are present. This catches future contrast regressions even if the migration prompt is forgotten.

## Session Errors

1. **Three migration agents made the same wrong mapping independently.** Recovery: orchestrator post-implementation sweep with a single `sed` invocation across the affected files. Prevention: token-mapping prompts must enumerate contrast-pair precedence before generic mappings.
2. **Group A migration missed `app/(dashboard)/dashboard/chat/layout.tsx`** — file was outside the explicit hand-listed scope but contained tokenizable classes; only caught by code-quality reviewer post-implementation. Recovery: P2 fix-inline (commit `99bbcc4f`). Prevention: migration-group prompts should accept a glob pattern (`app/(dashboard)/**/*.tsx`) and let the agent expand to the actual file list, rather than hand-enumerating files which can miss layout/template siblings.
3. **Plan subagent did not create the spec directory.** `knowledge-base/project/specs/feat-one-shot-fix-light-theme-incomplete-styling/` was missing when the orchestrator tried to write `session-state.md`. Recovery: orchestrator `mkdir -p` before writing. Prevention: plan skill should create the spec dir during plan generation (Phase 0 of the plan skill).

## Tags

category: best-practices
module: apps/web-platform/design-tokens
