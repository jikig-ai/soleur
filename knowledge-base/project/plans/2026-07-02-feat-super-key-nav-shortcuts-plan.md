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

1. **Fix the pre-existing glyph bug (unambiguous win, do regardless of option).** The
   overlay + palette hardcode `⌘` (`help-overlay.tsx:31-35`, `use-shortcuts.tsx:249`), so
   Windows/Linux users are already shown a key they don't have. Add a tiny
   `platform.ts` (`isApplePlatform()` via `navigator.platform`/`userAgentData`, SSR-safe
   default) and render `⌘` on mac / `Ctrl` elsewhere.
2. **macOS-only additive `⌘` accelerators for genuinely-safe letters only.** Keep the
   `g`-leader as the canonical cross-platform binding. On macOS, ALSO accept `⌘`+letter for
   letters that are (a) not OS/browser-reserved, (b) not already app-bound, (c) not a
   native-copy/select/reload/bookmark hijack. Per the matrix, that set is **at most `{i}`**
   among the current mnemonics — so in practice this delivers little unless letters are
   remapped (which breaks the mnemonic). Document honestly; do not advertise chords the
   browser overrides.
3. **Overlay surfaces reserved chords honestly** (the wireframe design): reserved letters
   render a muted/struck key cap + a one-line reason + a "Click to open" affordance (the
   overlay rows are already clickable launchers). See the `.pen` in Domain Review.
4. **Retain the WCAG turn-off toggle** (`soleur:shortcuts.enabled`) unchanged (CLO blocking
   condition).

## Guarded implementation (only if Option C is chosen — NOT recommended)

If the operator explicitly signs off on the literal rebind despite the verdict, `/work`
MUST honor every CLO/spec-flow guard rail:

- **Scope to Apple platforms.** Split the listener's `mod`: introduce `metaOnly` /
  `ctrlOnly` and bind nav to `metaKey` only (never the `ctrlKey` union) so Windows/Linux
  never arm hostile Ctrl+letter chords. Non-mac keeps only the `g`-leader.
- **Do NOT bind any reserved chord.** ⌘W (impossible), ⌘K (palette), ⌘C (copy) are
  permanently click-only / `g`-leader-only. Workstream and Knowledge Base and Ask-an-agent
  keep the `g`-leader; there is no ⌘ equivalent for them.
- **For the preventable-but-hostile letters (⌘D/⌘R/⌘A/⌘I)**, `preventDefault` and accept
  the browser-action override ONLY on non-editable focus — never inside inputs (so ⌘A/⌘C
  keep native meaning). This is the editable-focus inversion; document it.
- **Retain the `g`-leader as a live cross-platform alias** (dual-bind) — do not delete
  `resolveSequence`. This hedges the macOS-only risk and preserves muscle memory.
- **Platform-aware glyphs + reserved annotations** as in Option A′ (mandatory here too, or
  the overlay lies about what works).

Even fully guarded, Option C re-breaks copy/reload/select-all on macOS and delivers nothing
on the majority platform. Recorded for completeness; the plan recommends against shipping it.

## Functional Requirements

FR1. **Platform detection helper** — `apps/web-platform/components/command-palette/platform.ts`
exporting a pure, SSR-safe `isApplePlatform()` (unit-testable, DOM-free via injected nav
shape). *(location: new file)*

FR2. **Platform-aware glyph rendering** — the `CHORDS` list (`help-overlay.tsx:26-36`) and
the palette/overlay key hints render `⌘`↔`Ctrl` per FR1. `formatSeqHint` / the `seq`
single-source model extends to carry a modifier form without breaking the "documented key
can never drift from the live binding" invariant (`nav-items.ts:12-19`).
*(location: help-overlay.tsx, use-shortcuts.tsx, nav-items.ts)*

FR3. **Reserved-chord annotation model** — `nav-items.ts` carries per-destination metadata
(e.g. `metaKey?: string`, `reservedReason?: string`) so the overlay can render a muted
struck cap + reason + "Click to open" for reserved letters, and the resolver never binds
them. *(location: nav-items.ts, help-overlay.tsx)*

FR4. **(Option A′/C) macOS additive `⌘` accelerator resolution** — a new pure resolver arm
(or an extension of `resolveShortcut`) maps `metaKey`+safe-letter → the destination's
`CommandEffect`, gated on `isApplePlatform()`, suppressed in editables and under
`[role=dialog][aria-modal]` (reuse the existing guard, `use-shortcuts.tsx:494`), never for
reserved letters. *(location: use-shortcuts.tsx)*

FR5. **`g`-leader retained** — `resolveSequence` and the arm/resolve state machine stay as
the cross-platform canonical path (dual-bind), unchanged in behavior.

FR6. **WCAG turn-off retained** — `soleur:shortcuts.enabled` continues to gate the entire
listener (CLO blocking condition). No change.

## User-Brand Impact

**If this lands broken, the user experiences:** a navigation keystroke that closes their
browser tab (⌘W), reloads the page mid-workflow discarding unsaved input (⌘R), or silently
does nothing (a reserved chord swallowed by the browser) — on a surface the solo-founder
operator drives constantly.

**If this leaks, the user's workflow is exposed via:** N/A — no data surface. The exposure
is *session/data loss* (tab close, reload) and *trust erosion* from a shortcut layer that
fights the OS/browser, not a data breach.

**Brand-survival threshold:** `single-user incident` (inherited from the feat-web-app-shortcuts
brainstorm; a single user losing a session to a mis-bound nav key is a brand-eroding event
for the keyboard-power-user beachhead). `requires_cpo_signoff: true`.

## Files to Edit

- `apps/web-platform/components/command-palette/use-shortcuts.tsx` — resolver arm(s),
  glyph hint, retain `resolveSequence`, (C) split `metaKey`/`ctrlKey`.
- `apps/web-platform/components/command-palette/nav-items.ts` — per-destination modifier +
  reserved metadata; keep `seq`.
- `apps/web-platform/components/command-palette/help-overlay.tsx` — platform-aware glyphs,
  reserved annotations, click-to-open affordance.
- `apps/web-platform/components/command-palette/command-palette.tsx` — palette key hints
  (lines ~284, ~292-293, ~303-307, ~344-348) render platform-aware glyphs.
- `apps/web-platform/test/shortcuts-registry.test.ts` — unit assertions: arm-on-`g` (kept),
  `formatSeqHint`, new platform-aware + resolver arms, reserved-letter non-binding.
- `apps/web-platform/test/help-overlay.test.tsx` — testids `help-row-G D/G C/G A` and
  "Go to X" rows; add platform-glyph + reserved-annotation assertions.
- `apps/web-platform/test/command-palette.test.tsx` — hint rows (lines 193-206), go-to
  sequence integration (225-272), modal-suppression (326), WCAG turn-off (595-603).
- `apps/web-platform/app/globals.css` — `.cmdk-keys` (line 356) if the reserved/struck cap
  needs a style hook.

## Files to Create

- `apps/web-platform/components/command-palette/platform.ts` — `isApplePlatform()` helper.
- `apps/web-platform/test/platform.test.ts` — unit tests for the helper (or fold into
  `shortcuts-registry.test.ts`).

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
- AC5. **No reserved chord is bound.** A unit assertion proves `⌘K`→palette (not KB),
  `⌘W`/`⌘C` never resolve to a nav effect, and reserved letters render the struck/click-only
  cap in the overlay.
- AC6. (If B/C) macOS additive accelerators resolve only under `isApplePlatform()`, only for
  non-reserved letters, and are suppressed in editables + under `[role=dialog][aria-modal]`.
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
