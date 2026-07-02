---
title: "feat: Super/Meta-key navigation shortcuts (rebind the g-leader)"
date: 2026-07-02
branch: feat-one-shot-super-key-shortcuts
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: DECISION REQUIRED — do not /work until the operator signs off on an option
related:
  - PR #5867 (feat-palette-page-shortcuts — the g-leader this plan would rebind)
  - PR #5633 (feat-web-app-shortcuts — the ⌘K palette + ? overlay foundation)
  - brainstorm 2026-06-22-keyboard-shortcuts-brainstorm.md (the decision this reverses)
---

# ✨ feat: Super/Meta-key navigation shortcuts (rebind the `g`-leader)

> **⚠️ DECISION REQUIRED — read this before implementing.**
> The literal request ("rebind the `g d/i/w/k/r`, `g a`, `g c` navigation shortcuts to
> use the Super/Meta key instead of the `g` leader") was validated against the codebase,
> a flow analysis, and three domain leaders (CPO, CLO, plus spec-flow). **All four
> converge that a full literal rebind is a cross-platform + accessibility regression that
> reverses a documented, shipped, 3-domain-leader decision from 10 days ago.** This plan
> therefore leads with the evidence and a decision matrix, and specs the *technically
> safest guarded implementation* only as a sign-off-gated fallback. `requires_cpo_signoff`
> is set. Per the memory guidance "just ship, no gate questions" — its explicit carve-out
> is "risky/irreversible changes + design sign-off," which this is.

## Enhancement Summary

**Deepened on:** 2026-07-02
**Research agents used:** spec-flow-analyzer, cpo, clo, ux-design-lead (plan phase); code-simplicity-reviewer, architecture-strategist, user-impact-reviewer (deepen phase); precedent-diff + verify-the-negative greps.

### Key improvements from the deepen pass

1. **Scope split (simplicity).** The shippable, option-independent scope is now **decision + FR1/FR2 only** — the platform-aware glyph fix, a *real present bug* (glyphs are hardcoded `⌘` even on Windows/Linux; grep confirmed **zero** platform detection exists anywhere in `apps/web-platform`). The accelerator-binding work (former FR3/FR4 + Option-C spec) is demoted to a **gated appendix** that materializes only if the operator overrides the recommendation.
2. **The "safe subset" is empty (user-impact + CPO).** ⌘K/⌘W are taken/impossible; ⌘C/⌘R/⌘A/⌘D all hijack copy/reload/select-all/bookmark and are moved into the **never-bind** set (⌘R reload-data-loss was an un-asserted gap — `preventDefault` on ⌘R is "soft-reload only"). Only ⌘I is marginal. So even Option B delivers ~nothing — reinforcing Option A′ (glyph fix) as the answer.
3. **Architecture seam corrected.** The `metaKey`/`ctrlKey` split must be **local to a new `resolveNavChord(e, ctx): CommandEffect | null` arm only** — NEVER touch `resolveShortcut`'s `mod = metaKey || ctrlKey` union (`use-shortcuts.tsx:88`), or ⌘K/⌘B regress on non-mac. Platform is injected on `ShortcutContext` (never `navigator` inside a resolver). Handler precedence is explicit: `resolveShortcut` → `resolveNavChord` (on null) → g-leader arm/resolve. nav-items field renamed `metaKey`→`accel` (DOM-prop collision); "reserved" ⇔ "no `accel`".
4. **Hydration.** FR2 glyph rendering MUST use the provider's existing init-default-then-`useEffect`-sync pattern (`use-shortcuts.tsx:335-344`) — a raw `isApplePlatform()` call in first render causes a hydration mismatch + glyph flash. Accept a mount-gated first paint.

### New considerations discovered

- No platform-detection helper exists in the repo (`platform.ts` is genuinely novel, no dup risk).
- No hotkey/tinykeys dependency — the bespoke pure-resolver pattern is the canonical precedent to extend.
- The non-mac **Ctrl-union hijack** (Ctrl+W/R/T on Windows/Linux via the `mod` union) is the *highest-risk* role and is now surfaced in User-Brand Impact.

## Overview

The Soleur web-platform command palette (`apps/web-platform/components/command-palette/`)
ships a keyboard layer:

- `⌘K` / `Ctrl+K` — open command palette
- `⌘/` (canonical) + bare `?` — help overlay
- `⌘B` / `Ctrl+B` — toggle sidebar
- **`g`-then-key "go-to" sequences** (PR #5867): press `g`, then within 1500 ms press
  `d`/`i`/`w`/`k`/`r` → Dashboard / Inbox / Workstream / Knowledge Base / Routines;
  `g a` → Analytics (admin); `g c` → "Ask an agent".

The request is to move the `g`-leader "go-to" sequences onto the **Super/Meta key held as
a modifier** (hold ⌘/Super, press the destination letter). This plan validates that
premise, records the converging domain verdict, presents the decision, and — for the path
the operator is most likely to accept if they still want change — specs a guarded,
non-regressing implementation plus the one unambiguous improvement worth doing regardless
(platform-aware key glyphs).

The whole layer is gated by the `command-palette` Flagsmith flag (`enabled=` prop through
`ShortcutsProvider`, `app/(dashboard)/layout.tsx:252`). Any change here rides that existing
flag — no new flag is required.

## Premise Validation (plan Phase 0.6)

**Cited artifacts, verified:**

- **PR #5867 / #5636 (`g`-leader) — real and shipped.** The `g`-leader lives in
  `apps/web-platform/components/command-palette/use-shortcuts.tsx` (`resolveSequence`,
  `SEQUENCE_PREFIX = "g"`, `ASK_AGENT_SEQ = "g c"`, `SEQUENCE_WINDOW_MS = 1500`) and
  `nav-items.ts` (the `seq` single-source field). Confirmed on the branch (not memory).
- **The proposed *mechanism* (modifier-chord navigation) sits in the rejected-alternatives
  space of a prior decision.** `knowledge-base/project/brainstorms/2026-06-22-keyboard-shortcuts-brainstorm.md`
  records CPO/CTO/CLO guidance that **deliberately avoided** any scheme colliding with
  browser accelerators / chat typing, and `nav-items.ts:12-19` documents the `g`-prefix as
  "collision-free with browser chords — the wireframe's design." Per plan Phase 0.6 point 4,
  a mechanism sitting in a prior decision's rejected space is **not an unconsidered idea —
  it is an explicitly-rejected one**; the plan re-scopes to "does the request expose a gap
  the prior decision left open?" (answer: a small one — platform-aware glyphs — see below)
  rather than planning the rejected approach as if new.
- **No ADR governs the keyboard scheme** (`grep` of `knowledge-base/engineering/architecture/decisions/`
  returned only false-positive matches). The design record is the brainstorm + PR #5867.

**Verdict:** the premise is *stale/contested* for a full literal rebind. Proceeding requires
an explicit operator decision, which this plan gates.

## Research Reconciliation — Request vs. Codebase Reality

The heart of this plan. Legend: **Reaches page?** = can a web page observe the keydown at
all. **Preventable?** = can `preventDefault()` stop the browser's default. **App-bound?** =
already owned by Soleur.

| Target | Letter | Chord | Reaches page? | Preventable? | App-bound? | Verdict |
|---|---|---|---|---|---|---|
| Workstream | w | ⌘W / Ctrl+W | **No — closes the tab** | **No** | — | **UNIMPLEMENTABLE.** Fires tab-close before any handler; user loses their session. Hard block. |
| Knowledge Base | k | ⌘K | Yes | Yes | **Yes — opens the palette** (`use-shortcuts.tsx:90`) | **DIRECT APP COLLISION.** KB and the palette cannot both own ⌘K. |
| Ask an agent | c | ⌘C | Yes | Yes | — | **HOSTILE — the exact conflict `g c` was rebound away FROM** (#5636). Re-breaks copy / SIGINT-adjacent. |
| Routines | r | ⌘R | Yes | soft-reload only | — | **HOSTILE.** Hijacks reload; ⌘⇧R still hard-reloads (inconsistent). |
| Dashboard | d | ⌘D | Yes | Yes | — | **HOSTILE.** Hijacks bookmark. |
| Analytics | a | ⌘A | Yes | Yes | — | **HOSTILE.** Hijacks select-all; fires inconsistently vs. editable focus. |
| Inbox | i | ⌘I | varies | mostly | — | **RISKY.** Italic in editors / DevTools / page-info depending on browser. |

**Net: 0 of 7 letters are collision-free.** 1 hard OS block (`w`), 1 direct in-app
collision (`k`), 5 preventable-but-hostile hijacks of copy/reload/bookmark/select-all/italic.

**Second, larger problem — cross-platform reachability.** "Super/Meta" is platform-split:

| Platform | Meta = | Meta+letter reaches the page? |
|---|---|---|
| macOS | ⌘ Command | Yes (except OS/browser-reserved ⌘W/T/N/Q/L/1-9/Space/Tab). |
| Windows | Super/Win | **No** — Win+letter is consumed by the OS shell. |
| Linux (GNOME/KDE) | Super | **No / unreliable** — owned by the window manager. |
| ChromeOS | Search/Launcher | **No** — OS-reserved. |

The listener currently treats **`mod = e.metaKey || e.ctrlKey`** as one
(`use-shortcuts.tsx:88`). A naive rebind therefore *also* arms **Ctrl+letter** on
Windows/Linux — which is *more* hostile (Ctrl+W close, Ctrl+T new tab, Ctrl+R reload,
Ctrl+C copy, Ctrl+A select-all, Ctrl+K Firefox search). So the cross-platform "fallback" is
worse than the primary. **A held-modifier scheme is macOS-only at best.**

**New failure class the `g`-leader never had:** editable-focus inversion. `⌘A`/`⌘C` inside a
text field *must* keep native select-all/copy — so the same chord means "navigate" on the
dashboard and "select text" in an input, gated on invisible focus state. The `g`-leader
never had this (a bare `g` just types `g` in a field).

### Converging domain verdict

| Leader | Verdict |
|---|---|
| **spec-flow-analyzer** | 0/7 clean; ⌘W unimplementable; ⌘K direct collision; recommends reframe, not rebind. |
| **CPO** | *Decisive regression.* 0/7 clean, macOS-only, re-breaks `⌘C`, violates the constitution's "accessibility basics" carve-out. Option B's "safe subset" is **empty**. Recommends keep `g`-leader + explicit sign-off; if the real goal is faster nav, reframe. |
| **CLO** | Held-modifier chords are **outside WCAG 2.1.4 scope** (no compliance worsening), BUT overriding browser/OS/AT-reserved chords (⌘C/R/A/W) is a **real accessibility regression**. Blocking condition: keymap must avoid all reserved chords; **retain the turn-off toggle**. IP: negligible. |

## Decision Matrix (operator picks one)

| # | Option | What it does | Risk | Recommendation |
|---|---|---|---|---|
| **A** | **Keep the `g`-leader as-is** | No change. Collision-free, cross-platform, WCAG-clean. | Low | **RECOMMENDED (default).** |
| **B** | **Additive macOS-only Meta aliases for the safe subset** | Alias only non-reserved ⌘ chords; keep `g`-leader. | Medium | Weak — the safe subset among the mnemonic letters is ~empty (`k/w/c/r/a/d` all taken/hostile; only `i` is marginal). Low value. |
| **C** | **Full literal rebind (`⌘` replaces `g` for all 7)** | Move every target onto ⌘+letter; remap the impossible ones. | High | **REJECT** — maximizes every regression above; macOS-only; re-breaks copy/reload. |
| **D** | **Reframe to the underlying goal (faster navigation)** | Treat "use Super" as a proxy for "fewer keystrokes"; e.g. tighten the `g`-leader window, add a held-`g` HUD, or a single-key-on-non-chat surface. Route to a fresh brainstorm/spec. | Low | Strong alternative if the operator's real want is speed, not the Super key specifically. |

**Plan default if the operator signs off to proceed with *some* change:** the guarded,
non-regressing subset of **Option B + the one unambiguous fix** (platform-aware glyphs),
specified below. This is the only "did something" outcome that ships without a user-facing
regression. If the operator wants the literal Super feel across all 7 despite the evidence,
Option C is fully spec'd in "Guarded implementation (if C is chosen)" so `/work` has a
concrete, guard-railed target — but this plan does not recommend it.

## Recommended implementation (Option A′ = keep `g`-leader + safe wins)

Ships value without regressing anything, and is the honest synthesis of "honor the intent
(a Super-key navigation *feel*) while not breaking reserved chords or dropping non-mac users":

1. **Fix the pre-existing glyph bug (unambiguous win, do regardless of option) — the entire
   shippable scope.** The overlay + palette hardcode `⌘` (`help-overlay.tsx:31-35`,
   `use-shortcuts.tsx:249`), so Windows/Linux users are already shown a key they don't have.
   Add a tiny `platform.ts` (`isApplePlatform()`, SSR-safe) and render `⌘` on mac / `Ctrl`
   elsewhere as a **display-time substitution** (no `seq`/`formatSeqHint` model change),
   using the provider's init-default-then-`useEffect`-sync pattern to avoid a hydration
   mismatch (FR2). This is FR1+FR2 — the whole PR under Option A′.
2. **Keep the `g`-leader** as the canonical cross-platform binding (FR3). The macOS additive
   `⌘` accelerators are NOT part of this scope — per the matrix + user-impact review the
   bindable safe subset is effectively empty (⌘K/W/C/R/A/D all taken/hostile; only ⌘I
   marginal), so they live in the gated Appendix and only materialize under Option B/C.
3. **Retain the WCAG turn-off toggle** (`soleur:shortcuts.enabled`) unchanged (FR4, CLO
   blocking condition).

The wireframe (`.pen`, see Domain Review) additionally shows how reserved chords would be
surfaced (muted/struck cap + reason + "Click to open") — that overlay treatment is part of
the Appendix (Option B/C), not the Option A′ shippable scope.

## Appendix — Guarded accelerator spec (materializes ONLY if operator picks Option B/C)

Demoted from the FR list per code-simplicity review — this is contingency for an outcome the
plan rates Weak/REJECT. If the operator explicitly overrides the recommendation, `/work` MUST
honor every guard rail below (architecture-strategist + user-impact corrections applied):

- **New pure resolver arm, not an extension of `resolveShortcut`.** Add
  `resolveNavChord(e, ctx): CommandEffect | null` as a **sibling of `resolveSequence`** (nav
  destinations are dynamic `href`s → `CommandEffect`, which `resolveShortcut`'s fixed
  action-enum cannot express). Platform enters as an **injected field on `ShortcutContext`**
  (`{ isAdmin }` → `{ isAdmin; isApplePlatform }`) — NEVER read `navigator` inside a resolver
  (preserves the DOM-free/pure invariant).
- **Split `metaKey`/`ctrlKey` LOCALLY, in the new arm only.** `resolveNavChord` reads
  `e.metaKey` exclusively. **Do NOT touch `resolveShortcut`'s `mod = metaKey || ctrlKey` at
  `use-shortcuts.tsx:88`** — ⌘K/⌘B/⌘/ must keep firing on both meta AND ctrl cross-platform;
  a global split regresses them on Windows/Linux.
- **Explicit handler precedence** in the listener: `resolveShortcut` first → fall through to
  `resolveNavChord` only on `null` → then the g-leader arm/resolve (unchanged). This keeps
  ⌘K=palette / ⌘B=sidebar authoritative (AC5).
- **The bindable "safe subset" is effectively EMPTY.** Never-bind: ⌘W (closes tab —
  impossible), ⌘K (palette), ⌘C (copy). **Also never-bind ⌘R / ⌘D / ⌘A** — user-impact
  review showed ⌘R reload-data-loss is only "soft-reload" preventable (⌘⇧R still hard-reloads)
  and ⌘D/⌘A hijack bookmark/select-all with no reliable win. Only ⌘I is marginal. So Option B
  aliases at most `{i}` — i.e. delivers ~nothing. Document this honestly; do not advertise
  chords the browser overrides.
- **If any accelerator IS bound**, an AC/test MUST assert the handler calls `preventDefault`
  for it on non-editable focus (the reload-data-loss guard) — binding without asserting
  `preventDefault` is the FINDING-1 gap.
- **`nav-items.ts` metadata:** add a single `accel?: string` field (NOT `metaKey` — collides
  with the DOM `metaKey: boolean` on `ShortcutKeyEvent`). Binding-eligibility ⇔ presence of
  `accel`; `reservedReason?: string` is advisory display text only (soft-drift is acceptable
  for prose, but do not claim it is covered by the `seq` single-source guarantee).
- **Reuse `isEditable`** (`use-shortcuts.tsx:87/191`) and the `[role=dialog][aria-modal]`
  guard (`:494`) in the new arm — do not reinvent editable/modal suppression. Note that a
  single ⌘-chord **lowers the accidental-navigation-away threshold** vs the 2-key leader
  (FINDING-3); the inline-dirty-form case remains a pre-existing `g`-leader scope-out.
- **Retain the `g`-leader as a live cross-platform alias** (dual-bind — the two grammars are
  mutually exclusive by the modifier bit, so they cannot cross-fire; both converge on the
  single `runEffect` interpreter).
- **Option C only:** author a short ADR ("modifier-nav accepted on macOS despite
  browser-collision trade-offs") in the same PR (not deferred), per `wg-architecture-decision-is-a-plan-deliverable`.

Even fully guarded, Option C re-breaks copy/reload/select-all on macOS and delivers nothing
on the majority platform. Recorded for completeness; the plan recommends against shipping it.

## Functional Requirements (shippable scope — option-independent)

These ship regardless of which option the operator picks (they fix a real present bug and
change no keybinding behavior). Accelerator-binding requirements moved to the gated Appendix.

FR1. **Platform detection helper** — `apps/web-platform/components/command-palette/platform.ts`
exporting a pure, SSR-safe `isApplePlatform()` (unit-testable, DOM-free via injected nav
shape). Confirmed novel — grep found no existing platform helper anywhere in
`apps/web-platform`. *(location: new file)*

FR2. **Platform-aware glyph rendering (render swap, NOT a data-model change)** — the `CHORDS`
list (`help-overlay.tsx:31-35`) and the palette/overlay key hints (`command-palette.tsx`
~284/292-307/344-348, `use-shortcuts.tsx:249`) render `⌘`↔`Ctrl` at display time. Do **not**
alter `formatSeqHint` or the `seq` model — a render-time substitution keeps the single-source
invariant (`nav-items.ts:12-19`) intact with zero model change. **Hydration:** the glyph MUST
render off hydrated state using the provider's existing init-stable-default-then-`useEffect`-sync
pattern (`use-shortcuts.tsx:335-344`), NOT a raw `isApplePlatform()` call in first render, or
React warns + the glyph flashes. AC3 default: treat SSR as non-Apple (`Ctrl`) then sync; accept
a one-frame mount-gated correction. *(location: help-overlay.tsx, command-palette.tsx, use-shortcuts.tsx)*

FR3. **`g`-leader retained unchanged** — `resolveSequence` and the arm/resolve state machine
stay as the cross-platform canonical path. No behavior change.

FR4. **WCAG turn-off retained** — `soleur:shortcuts.enabled` continues to gate the entire
listener (CLO blocking condition). No change.

> Former FR3 (reserved-chord metadata model) and FR4 (macOS `⌘` accelerator resolution) are
> **demoted to the Appendix** — they only materialize if the operator overrides the
> recommendation and picks Option B/C. Per code-simplicity review, speccing them as first-class
> FRs is building infrastructure for a path the plan recommends against.

## User-Brand Impact

**If this lands broken, the user experiences:** a navigation keystroke that closes their
browser tab (⌘W), reloads the page mid-workflow discarding unsaved input (⌘R), or silently
does nothing (a reserved chord swallowed by the browser) — on a surface the solo-founder
operator drives constantly. **Highest-risk role: Windows/Linux/ChromeOS users** — the shipped
`mod = metaKey || ctrlKey` union (`use-shortcuts.tsx:88,193`) means a naive rebind arms
**Ctrl+W (tab close) / Ctrl+R (reload) / Ctrl+T (new tab)** on the majority platform, where
the failure is strictly worse than on mac. (Mitigated only by the Appendix's local-metaKey
split + `isApplePlatform` gate — which is exactly why the rebind is not in the shippable
scope.)

**If this leaks, the user's workflow is exposed via:** N/A — no data surface. The exposure
is *session/data loss* (tab close, reload) and *trust erosion* from a shortcut layer that
fights the OS/browser, not a data breach.

**Brand-survival threshold:** `single-user incident` (inherited from the feat-web-app-shortcuts
brainstorm; a single user losing a session to a mis-bound nav key is a brand-eroding event
for the keyboard-power-user beachhead). `requires_cpo_signoff: true`.

### Shippable scope (Option A′ — FR1/FR2)

- `apps/web-platform/components/command-palette/use-shortcuts.tsx` — glyph hint render swap
  (`:249`); provider hydration-sync of platform (mirror `:335-344`). Retain `resolveSequence`
  untouched.
- `apps/web-platform/components/command-palette/help-overlay.tsx` — platform-aware glyphs in
  `CHORDS` (`:31-35`) via display substitution.
- `apps/web-platform/components/command-palette/command-palette.tsx` — palette key hints
  (~284, ~292-293, ~303-307, ~344-348) render platform-aware glyphs.
- `apps/web-platform/test/shortcuts-registry.test.ts` — fold in `isApplePlatform()` unit
  tests (true/false/no-navigator); keep the `g`-leader cases green.
- `apps/web-platform/test/help-overlay.test.tsx` — assert `Ctrl` on non-Apple nav shape;
  existing `help-row-G D/G C/G A` + "Go to X" rows stay green.

### Appendix scope (Option B/C only — do NOT touch unless operator overrides)

- `apps/web-platform/components/command-palette/nav-items.ts` — add single `accel?` field
  (+ advisory `reservedReason?`); keep `seq`. **`accel`, not `metaKey`** (DOM-prop collision).
- `apps/web-platform/components/command-palette/use-shortcuts.tsx` — new
  `resolveNavChord(e, ctx)` sibling arm; extend `ShortcutContext` with `isApplePlatform`;
  listener precedence; **never** touch the `:88` `mod` union.
- `apps/web-platform/test/command-palette.test.tsx` — go-to integration (225-272),
  modal-suppression (326), WCAG turn-off (595-603), + `preventDefault`-on-bound-accelerator.
- `apps/web-platform/app/globals.css` — `.cmdk-keys` (`:356`) reserved/struck cap style hook.

## Files to Create

- `apps/web-platform/components/command-palette/platform.ts` — `isApplePlatform()` helper
  (novel — no existing platform helper in the repo). Tests folded into
  `shortcuts-registry.test.ts` (no separate `platform.test.ts` — one pure function).

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` not run in this offline planning
session; the touched files — `command-palette/*` — have no known open scope-outs. `/work`
should re-run the overlap check per plan Phase 1.7.5 when online.)

## Acceptance Criteria

### Pre-merge (PR)

- AC1. **Decision recorded.** The PR body states which option (A/B/C/D) the operator signed
  off on. If A or D, the PR is docs-only (this plan + a tracking issue for D) — no keybinding
  code change ships.
- AC2. Platform-aware glyphs: on a non-Apple `navigator` shape, the overlay renders `Ctrl`
  (not `⌘`) for chord rows — asserted in `help-overlay.test.tsx` (both platform shapes).
- AC3. `isApplePlatform()` is pure and SSR-safe (returns a stable default with no
  `navigator`) — asserted in unit tests.
- AC4. The `g`-leader still works unchanged: `resolveSequence(true, key("d"))` →
  `{navigate,/dashboard}` etc. (existing `shortcuts-registry.test.ts` cases stay green).
- AC5. **No reserved chord is bound (precedence holds).** A unit assertion proves
  `resolveShortcut` runs first so `⌘K`→palette (not KB) and `⌘B`→sidebar; `⌘W`/`⌘C`/`⌘R`/`⌘D`/`⌘A`
  never resolve to a nav effect. The `:88` `mod = metaKey||ctrlKey` union is unchanged
  (⌘K/⌘B still fire on Ctrl too).
- AC6. (If B/C) `resolveNavChord` accelerators resolve only under `isApplePlatform()` (via
  injected `ShortcutContext`, not `navigator`), only for non-reserved letters, suppressed in
  editables + under `[role=dialog][aria-modal]`.
- AC6b. (If B/C, and ANY accelerator is bound) a test asserts the keydown handler calls
  `preventDefault` for every bound ⌘-accelerator on non-editable focus (reload-data-loss
  guard — FINDING 1).
- AC7. WCAG turn-off (`soleur:shortcuts.enabled=0`) disables the WHOLE listener incl. any new
  arms — existing `command-palette.test.tsx:603` extended.
- AC8. Typecheck + tests green: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  and `./node_modules/.bin/vitest run test/shortcuts-registry.test.ts test/help-overlay.test.tsx test/command-palette.test.tsx test/platform.test.ts`.

### Post-merge (operator)

- None required (client-only change; rides the existing `command-palette` flag; container
  restart on merge to `apps/web-platform/**` handles deploy via `web-platform-release.yml`).

## Observability

Client-only UI keybinding change (no server/infra surface), so the 5-field server schema is
scoped down to the client-observable signals:

```yaml
liveness_signal:    the ? overlay renders the correct platform glyphs and the g-leader
                    navigates — verified by the vitest suite in CI (no runtime cron).
error_reporting:    a mis-bound/reserved chord is a *silent* failure by nature (browser
                    default wins); mitigation is the reserved-annotation UI (FR3), not a
                    Sentry event. No new error path is introduced.
failure_modes:
  - mode: reserved chord silently lost to the browser
    detection: overlay renders it as struck/click-only (design-level, not telemetry)
    alert_route: none (by design — do not bind it)
  - mode: g-leader regression (arm/resolve broken by the refactor)
    detection: shortcuts-registry.test.ts + command-palette.test.tsx in CI
    alert_route: CI red
logs:               none added (client keydown path; no logging today, none introduced).
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/shortcuts-registry.test.ts test/help-overlay.test.tsx
  expected_output: all suites pass (no ssh)
```

## Domain Review

**Domains relevant:** Product, Legal, Engineering.

### Legal

**Status:** reviewed (CLO). **Assessment:** Held-modifier chords fall OUTSIDE WCAG SC 2.1.4
(single-character-key) scope, same as the existing two-key `g`-leader — no net 2.1.4
obligation change. **Blocking condition:** the keymap must not clobber browser/OS/AT-reserved
chords (⌘C/V/X/A/R/F/Z/W/T), focus must follow navigation (SC 2.1.1/2.4.7), and the
`soleur:shortcuts.enabled` turn-off must be retained (defense-in-depth). IP: negligible —
keybinding schemes are unprotectable idioms; do not copy branded cheat-sheet artwork/text.
No legal-document changes triggered.

### Engineering

**Status:** reviewed (spec-flow + CTO-adjacent from direct code read). **Assessment:** The
listener's `mod = metaKey || ctrlKey` union is the load-bearing risk — a naive rebind arms
hostile Ctrl+letter on non-mac. Any modifier scheme must split the union and gate on
`isApplePlatform()`. The `seq` single-source invariant (`nav-items.ts:12-19`) must be
preserved: overlay/palette/resolver derive from one field, so the reserved metadata must
live on the same model. `deepen-plan` Phase 4.4 should precedent-diff the existing
`resolveShortcut`/`resolveSequence` pure-function pattern for the new arm.

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — `components/command-palette/*.tsx` match
the `components/**/*.tsx` glob).
**Decision:** reviewed (pipeline) — wireframe generated; review pause auto-suppressed
(headless/one-shot arm).
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead.
**Skipped specialists:** none.
**Pencil available:** yes (Tier 0 headless CLI; Node v24.15.0).

#### Findings

- **CPO:** full literal rebind is a decisive regression (0/7 clean, macOS-only, re-breaks
  ⌘C, violates the constitution accessibility carve-out); Option B's safe subset is empty;
  recommends keep `g`-leader (A) with explicit sign-off, or reframe to the speed goal (D).
- **spec-flow:** collision matrix above; ⌘W unimplementable, ⌘K direct collision; reframe.
- **ux-design-lead wireframe** (the required `.pen`):
  - Source: `knowledge-base/product/design/web-platform/super-key-shortcuts-help-overlay.pen`
  - Export: `knowledge-base/product/design/web-platform/screenshots/01-super-key-shortcuts-help-overlay-macos.png`
  - Shows: a `macOS` platform pill, a legend that `⌘`→`Ctrl` off-mac, safe letters with
    solid key caps, and reserved letters (⌘W/⌘K/⌘R) with muted struck caps + reason + a
    gold "Click to open" pill — i.e. the overlay honestly surfaces which chords are
    unbindable while keeping the row clickable.

## Architecture Decision (ADR / C4)

**No ADR/C4 change.** This is a client-side keybinding + glyph change on an existing surface.
No data-model ownership/tenancy move, no new substrate/integration, no resolver/dispatch/trust
boundary change. Checked against the three C4 model files' scope (external actors, external
systems/vendors, data stores, access relationships): a keyboard binding introduces no new
external actor, system, or data store and changes no access relationship — no `.c4` edit is
warranted. The design rationale being reversed lives in the feat-web-app-shortcuts brainstorm,
not an ADR; if the operator picks Option C, a short ADR recording "modifier-nav accepted on
macOS despite browser-collision trade-offs" would be warranted and should be authored in that
PR's lifecycle (not deferred).

## Test Scenarios

1. `g`-leader unchanged (arm on `g`, resolve `d/i/w/k/r/c`, admin-gate `a`, editable
   suppression, auto-repeat, modal suppression) — existing suites stay green.
2. `isApplePlatform()` true/false/no-navigator.
3. Overlay renders `⌘` on Apple, `Ctrl` elsewhere.
4. Reserved letters (`w`/`k`/`c`) render struck/click-only and never resolve to a nav effect.
5. (B/C) macOS additive accelerator resolves only under Apple platform, only for safe letters,
   suppressed in editables and modals.
6. WCAG turn-off disables the whole listener including new arms.

## Alternatives Considered

| Approach | Why not (now) | Tracking |
|---|---|---|
| Full literal `⌘`-rebind of all 7 (Option C) | 0/7 collision-free; macOS-only; re-breaks copy/reload/select-all; ⌘W closes the tab. | Rejected — spec'd as guarded fallback only. |
| Reframe to the speed goal (Option D) | The likely real intent ("fewer keystrokes"). Better solved by tightening the `g`-leader window or a held-`g` HUD. | **File a tracking issue** if operator picks D → route to `/soleur:brainstorm`. |
| Delete `g`-leader entirely | Removes the only collision-free, cross-platform path. | Rejected. |

## Sharp Edges

- The `## User-Brand Impact` section must stay filled (threshold + concrete artifact/vector);
  an empty/`TBD` section fails `deepen-plan` Phase 4.6.
- `apps/web-platform` typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  (NO `npm run -w` — the repo root declares no `workspaces`). Tests run via
  `./node_modules/.bin/vitest run <path>` (vitest, not `bun test`); test files must match
  `vitest.config.ts` `include:` globs (`test/**/*.test.{ts,tsx}`) — a co-located
  `components/**/*.test.tsx` is silently never run.
- Do not bind any `metaKey || ctrlKey` union arm for nav — split it, or Windows/Linux users
  get hostile Ctrl+letter behavior.
- The `.pen`/PNG design artifacts under `knowledge-base/product/design/` are committed by the
  ux-design-lead flow; do not hand-edit.
