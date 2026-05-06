---
date: 2026-05-06
category: ui-bugs
module: theme-toggle
tags: [react-18, hydration, ssr, theme, mounted-gate, next-themes]
related_prs: [3309, 3312, 3315, 3318, 3324]
related_issues: [3325]
---

# React 18 production hydration does NOT patch className/attribute mismatches

## Problem

The dashboard theme selector (`apps/web-platform/components/theme/theme-toggle.tsx`) shipped four sequential fix attempts in 48 hours (PRs #3309 → #3312 → #3315 → #3318) and the underlying bug persisted in production: a screenshot showed two pills visually highlighted (Dark on the left + System on the right) and the selector "reverting to System on reload."

PR #3318's fix made the React lazy initializer read `documentElement.dataset.theme` — which the inline `NoFoucScript` writes synchronously in `<head>` from `localStorage["soleur:theme"]`. This gave the client lazy initializer the correct theme on first render. Unit tests passed; production stayed broken.

## Root Cause

React 18 production hydration applies different reconciliation policies to different mismatch classes:

- **Property mismatches** (e.g., `aria-pressed`) are reconciled — React patches the DOM attribute to match the client-rendered value.
- **className mismatches are NOT reconciled** in production builds. React logs a dev-only `console.error` and **keeps the SSR DOM in place** (no client re-render fires).

The bug's deterministic mechanism, given those two facts plus PR #3318's lazy-initializer change:

1. SSR runs the lazy initializer with `typeof window === "undefined"` → returns `"system"`. Server-rendered HTML therefore paints the System segment with full active className (`bg-soleur-bg-surface-1 ring-1 ring-inset ring-soleur-border-emphasized text-soleur-accent-gold-fg`).
2. Client lazy initializer reads `dataset.theme` (the `NoFoucScript`-written value, e.g., `"dark"`) and returns `"dark"`. React's vDOM has Dark active.
3. Hydration reconciles attributes: `aria-pressed="true"` is moved off System and onto Dark.
4. Hydration does **not** reconcile className: System's active className stays in the DOM.
5. The first-mount `useEffect` from PR #3312 sees `theme === "dark"` (state already correct) and does NOT call `setThemeState` → **no re-render fires**, so the stale className is never repainted.

Result: `aria-pressed="true"` correctly on Dark + active className still on System = "two pills highlighted." This is not a race condition or timing issue — it's a deterministic policy quirk in React 18.

PR #3318's commit message claim that "React 18 hydration reuses the server-rendered state and does NOT re-call lazy initializers on the client" is misleading framing of the bug, NOT the actual mechanism. The lazy initializer IS called on the client; the missing fact is React's selective-reconciliation policy.

## Solution

Apply the canonical "mounted-gate" pattern (`pacocoursey/next-themes`):

```tsx
const [mounted, setMounted] = useState(false);
useEffect(() => { setMounted(true); }, []);

// Render no segment as active pre-mount; correct segment post-mount.
const active = mounted && theme === seg.value;
```

SSR and the first client paint both render `data-active="false"` on every segment with no active className. The mismatch React refused to reconcile is eliminated because there's nothing to reconcile. After hydration completes, `useEffect` flips `mounted` and React re-renders with the real active segment.

For the collapsed cycle button (which renders an icon glyph derived from `theme`, not just an attribute), pin a `PRE_MOUNT_INDEX` constant to the System segment so SSR HTML and first client paint show the same glyph. Post-mount, the gate flips to the real index.

Tradeoff accepted: ~1 paint frame where no segment is highlighted. The page palette is already correct during this frame (`NoFoucScript` writes `dataset.theme` synchronously in `<head>`); only the toggle's own indicator catches up. This is the same trade-off shipped by `next-themes` to ~14k+ downstream consumers.

Defense-in-depth additions:
- `data-active` attribute as the canonical agent/test probe; `aria-pressed` retained as the screen-reader contract. Both flip from the same boolean.
- Module-load assertion `if (PRE_MOUNT_INDEX === -1) throw` so a future SEGMENTS edit that drops "system" fails loud at module load instead of silently rendering `SEGMENTS[-1]`.

## Key Insight

**Vitest cannot reproduce production React's hydration semantics.** Vitest uses dev React, which logs hydration warnings AND attempts subtree re-render on mismatch — production-mode "keep SSR DOM, no re-render" behavior is not exercisable in unit tests. This is why four sequential PRs shipped green CI while production stayed broken.

The right test layering for SSR-hydration concerns:
1. **Vitest contract tests** — assert the post-render invariant (e.g., "exactly one `data-active='true'` matches stored theme"). Catches the contract drift, not the bug itself.
2. **Playwright e2e against production build** — the load-bearing automated gate that runs `bun run build && bun run start` and exercises the real prod hydration path.
3. **Manual production reload check** — the AC8 fallback when e2e infrastructure isn't yet wired (see issue #3325 for the deferred Playwright e2e on this feature).

When choosing between "fix SSR to match client" and "make first paint match SSR's snapshot," prefer the latter for client-only state (localStorage, OS prefs, IndexedDB). The former requires moving the source of truth into a request-level surface (cookies) and forfeits Next.js full-route static caching.

## Session Errors

1. **Bash CWD non-persistence** — `cd apps/web-platform && cmd` failed in a follow-up call because the Bash tool resets CWD between calls. Recovery: chained `cd <absolute-path> && cmd` in a single Bash call. **Prevention:** AGENTS.md `hr-the-bash-tool-runs-in-a-non-interactive` and the work skill's "chain `cd <worktree-abs-path> && <cmd>` in a single Bash call" already cover this; no rule change needed.

2. **Plan path drift** — plan and tasks file prescribed `apps/web-platform/playwright/theme-reload.{e2e,spec}.ts`, but the actual e2e directory is `apps/web-platform/e2e/`. Recovery: discovered via `find` before writing any file. **Prevention:** AGENTS.md `hr-when-a-plan-specifies-relative-paths-e-g` already mandates `git ls-files | grep -E` verification before prescribing paths/globs; the plan/deepen-plan steps should have caught this. No rule change needed; this is enforcement of an existing rule.

3. **Defer-without-issue (workflow gate violation)** — Tasks 3.3 (NoFoucScript script-exec test) and 3.4 (Playwright e2e) were deferred without immediately filing a GitHub issue per `wg-when-deferring-a-capability-create-a`. Recovery: filed issue #3325 during compound. **Prevention:** existing rule already covers this; the work skill should run the defer-issue check at task-status-flip time, not at compound time. (No skill edit proposed — the existing rule is clear; this was a per-session adherence lapse, not a missing rule.)

## Prevention

- **For new SSR-rendered surfaces that depend on client-only state** (localStorage, navigator, OS prefs): use the mounted-gate pattern from the start. Two existing repo precedents to copy from: `apps/web-platform/components/ui/sheet.tsx:26-27` and `apps/web-platform/components/kb/selection-toolbar.tsx:60`.
- **Test-runner choice for SSR/hydration-class bugs:** vitest is for the *contract*; Playwright against the production build is for the *bug*. If the bug class is "rendered DOM disagrees with React state," vitest will not reproduce it.
- **When debugging a "shipped fix didn't work in production":** check whether the failing code path is reconciled by hydration. The two reliable categories that aren't reconciled: className mismatches and inline-style mismatches in production builds.

## References

- `pacocoursey/next-themes` — canonical mounted-gate implementation (`packages/next-themes/src/index.tsx`).
- React 18 hydration docs — `onRecoverableError`, selective hydration semantics.
- `apps/web-platform/components/theme/theme-toggle.tsx` — repo implementation post-PR #3324.
- `apps/web-platform/test/theme-toggle-ssr-hydration.test.tsx` — contract test (asserts post-mount data-active invariant; cannot reproduce the production hydration path itself).
- Issue #3325 — deferred Playwright e2e for the load-bearing gate.
