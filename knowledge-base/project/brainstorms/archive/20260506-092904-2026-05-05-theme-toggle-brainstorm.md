---
title: Theme toggle (light / dark / system)
date: 2026-05-05
status: planning
related_issue: 3232
related_pr: 3271
branch: feat-theme-toggle
user_brand_critical: true
---

# Theme Toggle Brainstorm

## What We're Building

A theme switcher control on the main app page that lets the user pick between three modes:

- **Solar Forge** (dark — current default)
- **Solar Radiance** (light — palette landed in commit `112491b3` / #3233)
- **System** (follows `prefers-color-scheme`)

The Solar Radiance palette is now production-approved in `knowledge-base/marketing/brand-guide.md`, which unblocks issue #3232 (previously blocked on palette definition).

## Why This Approach

The user explicitly asked for a button on the main page. Issue #3232 already captured the acceptance criteria during a prior /soleur:go session today. Rather than re-litigate scope through full Phase 0.5 / 1 / 2 dialogue, the operator chose **plan-first** — the open decisions are crisp enough for /soleur:plan to resolve with CPO + CLO + CTO + user-impact-reviewer gating.

## Key Decisions (Deferred to Plan)

| Decision | Options | Notes |
|---|---|---|
| Persistence layer | localStorage vs DB column on `users` | Issue #3232 explicitly flagged "cross-tenant leak considered." localStorage is per-browser, no leak surface. |
| No-FOUC strategy | Inline script in `<head>` reading localStorage | Must be CSP-nonce-compatible — `apps/web-platform/app/layout.tsx` already wires a CSP nonce. |
| Tokenization scope | Full sweep of ~65 dark-only components vs incremental | Issue lists ~115 TSX files with hardcoded `bg-neutral-950` / `text-neutral-100`. Full sweep is high blast radius. |
| Toggle UI placement | Header right, settings panel, or main-page corner | User said "main page" — exact placement decided at design time. |
| `viewport.themeColor` | Static fallback + dynamic update via `<meta>` swap | Currently hardcoded `#0a0a0a` in `apps/web-platform/app/layout.tsx`. |

## Non-Goals

- Custom user-defined palettes (only the two brand-approved palettes + system).
- Per-route theme overrides.
- Animated theme transitions beyond the default CSS variable swap.
- Marketing-site (Eleventy docs) theme toggle — separate surface, separate scope.

## User-Brand Impact

**Threshold: `single-user incident`**

Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, the operator confirmed the framing answer covers all three failure vectors at the brainstorm gate:

1. **Trust breach / cross-tenant read.** If theme preference is persisted in DB without correct RLS, a poorly-scoped read could expose another tenant's user row scope. Mitigation pressure: prefer localStorage; if DB persistence is selected at plan time, RLS scoping must be reviewed by `data-integrity-guardian` and `security-sentinel`.
2. **Trust breach via FOUC + CSP.** A misbuilt no-FOUC inline script could break the existing CSP nonce policy in `apps/web-platform/app/layout.tsx`, knocking out auth, payment, and chat surfaces app-wide. Mitigation pressure: the inline script must consume the same CSP nonce used today, and the plan must include a CSP regression test.
3. **No direct user impact (cosmetic).** Wrong default theme or transient FOUC flash is annoying but not brand-survival.

**Sign-off required at plan ready:** CPO + CLO + CTO + `user-impact-reviewer`.

## Open Questions (for /soleur:plan)

- Which persistence layer wins (localStorage strongly preferred — does anyone need cross-device persistence today?).
- Where exactly on the main page does the button live? Header, sidebar, settings dropdown?
- What's the tokenization migration sequencing — single PR vs phased?
- Do we ship a server-rendered first paint that already matches the chosen theme (cookie-based) or accept a one-frame swap?

## Domain Assessments

**Assessed:** none in brainstorm phase — operator selected plan-first path. The plan skill will spawn CPO + CLO + CTO at Phase 0.5 with the user-brand-critical flag inherited from this document.

## Capability Gaps

None reported.
