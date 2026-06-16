# Learning: small (≤10px) gold interactive text needs `-text`, not `-fg`, for WCAG AA

## Problem

The Debug stream panel's "Copy" control read as oversized and mis-colored: it was
grey (`text-soleur-text-muted`) in a `font-mono` face with a grey border, while
its sibling header controls ("Hide", "not saved") are sans-serif `text-[10px]`.
The ask was to make it the gold brand accent (a button affordance) at a size
consistent with the chrome.

The tempting recolor is `text-soleur-accent-gold-fg` — the common `text-sm` link
idiom across the app. At 10px on this panel's composited surface
(`bg-soleur-bg-surface-1/30` over base = `#f9f4ea` light), light-theme `-fg`
(#9c7a2e) measures **3.66:1** — it FAILS WCAG AA (4.5:1 required below
"large text"). The brand-guide itself documents `-fg` as "≥ AA non-text / large
text only."

## Solution

- **Resting color = `text-soleur-accent-gold-text`** (the deeper gold,
  #7a5e1f light / #d4b36a dark). Light-theme **5.56:1 PASS** at 10px; dark passes
  comfortably (9.68:1).
- **Hover = `hover:text-soleur-text-primary`** — contrast INCREASES on hover in
  both themes (#1a1612 on light / #fff on dark). WCAG SC 1.4.3 has no
  transient-state exemption, so the hover (an active state) must also clear AA; a
  gold `-fg` hover would fail light-theme AA and de-emphasize on interaction.
- **Border = `border-soleur-accent-gold-text/30`** (gold-tinted, not dropped) so
  COLOR is not the only clickability cue next to the inert "not saved" label
  (WCAG SC 1.4.1).
- Drop `font-mono` + add `font-medium` to match the sibling toggle; monospace was
  the dominant cause of the "oversized" perception.
- `disabled:text-soleur-text-muted` so gold never renders dimmed (Copy is
  `disabled` whenever `events.length === 0` — the first-paint default).

## Key Insight

For any gold interactive control at **≤10px**, default to the `-text` gold token,
not `-fg`. `-fg` is calibrated for large/non-text use and fails AA 4.5:1 at small
sizes on light surfaces. When recoloring an interactive control, check contrast on
BOTH the resting AND hover states (SC 1.4.3, no transient exemption), and prefer a
hover that INCREASES contrast in both themes (darker-on-light / lighter-on-dark)
rather than a same-hue brighten. State the invariant — "contrast increases on
hover" — in any inline comment rather than the light-theme-only "darkens" framing.

## Session Errors

1. **(Forwarded, planning)** Initial plan `Write` hit the main-repo checkout path
   while worktrees exist; re-issued to the worktree path.
   **Prevention:** already hook-enforced via `hr-when-in-a-worktree-never-read-from-bare`; no new rule.
2. **(Review)** Inline AA comment said hover "must DARKEN" but `-primary` is `#fff`
   in dark theme (brightens). The AA conclusion was correct; the wording was
   light-theme-only.
   **Prevention:** describe the theme-independent invariant ("contrast increases
   on hover") in comments, not a single-theme direction. Captured in Key Insight above.

## Tags
category: ui-bugs
module: apps/web-platform/components/chat
