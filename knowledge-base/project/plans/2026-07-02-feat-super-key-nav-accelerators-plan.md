---
title: "feat: Super/Meta-key nav accelerators (additive to the g-leader)"
branch: feat-one-shot-super-key-nav-accelerators
date: 2026-07-02
status: DRAFT — operator pre-approved the "Balanced" keymap 2026-07-02 (decision FINAL)
lane: cross-domain # no spec.md on branch — defaulted to cross-domain (fail-closed)
brand_survival_threshold: single-user incident
requires_cpo_signoff: false # OPERATOR OVERRIDE: keymap already signed off (see §User-Brand Impact). This is an implementation plan, not a decision plan; user-impact-reviewer still runs at review-time.
flag: command-palette # rides the existing Flagsmith flag — NO new flag
---

# ✨ feat: Super/Meta-key navigation accelerators (additive to the `g`-leader)

## Overview

Add a **new, additive** Super/Meta-key accelerator layer to the command-palette
keyboard system. Holding **Super** (⌘ on macOS / Win on Windows / Super on Linux,
all of which surface as `metaKey`) plus a letter navigates directly — **additive
to the existing `g`-leader, which stays as the universal cross-platform fallback.
Nothing is removed.**

Approved "Balanced" keymap — bind exactly these 5, do NOT bind the other two:

| Accelerator | Destination | Native action it must `preventDefault` |
|-------------|-------------|----------------------------------------|
| Super+D | Dashboard | browser bookmark |
| Super+I | Inbox | (none material) |
| Super+R | Routines | reload (soft-reload only — see Sharp Edges) |
| Super+A | Analytics (admin-gated) | select-all |
| Super+C | Ask an agent | copy |
| — | Workstream | **`g`-leader ONLY** (⌘W closes the tab before JS runs; Win+W OS-reserved) |
| — | Knowledge Base | **`g`-leader ONLY** (⌘K is already the palette) |

The design is the un-deferred **Appendix** of the merged plan
`knowledge-base/project/plans/2026-07-02-feat-super-key-nav-shortcuts-plan.md`
(Option B/C materialization). It rides the existing `command-palette` Flagsmith
flag — **no new flag** — and adds a new pure resolver `resolveNavChord`, a
sibling of `resolveSequence`, that reads `metaKey` ONLY.

**Detail level:** MORE (additive resolver + data field + one listener branch +
hint rendering + tests; single client module cluster, no server/schema surface).

## Research Reconciliation — Spec vs. Codebase

Premise validated at plan-write time (Phase 0.6). Every cited artifact was read
on this branch.

| Claim (from the task premise) | Reality (verified on branch) | Plan response |
|---|---|---|
| The `metaKey`/`ctrlKey` split must be local to a new `resolveNavChord`; never touch `resolveShortcut`'s `mod = metaKey \|\| ctrlKey` at `use-shortcuts.tsx:88` | Confirmed: line 88 is `const mod = e.metaKey \|\| e.ctrlKey;`, read by ⌘K/⌘/-canonical/⌘B. | Leave line 88 untouched (Rule 2). New `resolveNavChord` reads `e.metaKey` only. Add a regression test that `resolveShortcut` still maps ⌘K/⌘B on **ctrl** too. |
| `nav-items.ts` has a `seq` field, no `accel` | Confirmed: `NavItem` has `readonly seq?: string`; `accel` absent. | Add `readonly accel?: string` (Rule 3). Name `accel`, NOT `metaKey` (collides with the DOM `metaKey: boolean` on `ShortcutKeyEvent`). |
| Listener runs `resolveShortcut` first, then the `g`-leader arm | Confirmed: `use-shortcuts.tsx` L488 `resolveShortcut`, L512 g-arm (`resolveSequence(false,…)==="arm"`), modal-suppress guard at L518. | Insert `resolveNavChord` **between** the two (Rule 4): resolveShortcut → resolveNavChord → g-arm. |
| Prior plan's CPO/user-impact review called these chords HOSTILE / "empty safe subset" and moved ⌘D/⌘R/⌘A/⌘C into a never-bind set | Confirmed at `…super-key-nav-shortcuts-plan.md:37,103-107,199-207`: the accelerator spec is a **gated Appendix that materializes ONLY if the operator picks Option B/C**. | **Operator has picked Option B/C** (premise: keymap FINAL). The prior review's mitigation is now mandatory: every bound accelerator `preventDefault`s and a test asserts it (Rule 5). Threshold stays `single-user incident`; `user-impact-reviewer` runs at review-time. |
| vitest collects `test/**/*.test.ts` (node) + `test/**/*.test.tsx` (dom) | Confirmed `apps/web-platform/vitest.config.ts:44,64`. | Pure-resolver tests → extend `test/shortcuts-registry.test.ts` (node). Component tests → extend `test/command-palette.test.tsx` + `test/help-overlay.test.tsx` (dom). No new files under `components/`. |
| ADR corpus has a keyboard/shortcut decision this conflicts with | grep of `decisions/` found none (only incidental "shortcut" prose). | No ADR to amend; this extends an already-documented sibling-resolver pattern. See §Architecture Decision. |

## User-Brand Impact

**If this lands broken, the user experiences:** a Super+letter press that hijacks
a native browser action they expected — e.g. Super+C silently fails to copy
selected text, Super+R silently fails to reload, Super+D silently fails to
bookmark — OR a mis-bound key navigates them away from a half-filled form and
discards their input. Any of these is a per-keystroke trust break.

**If this leaks, the user's data/workflow is exposed via:** N/A — this is a
client-only keydown handler. It processes NO personal data, touches NO
schema/API/auth surface, and moves NO data across a boundary. The exposure vector
is *data-loss / native-action hijack*, not data exfiltration.

**Brand-survival threshold:** `single-user incident` — a single mis-bound nav key
that hijacks copy/reload/select-all is brand-eroding on its own; it does not need
to aggregate. The mitigation is structural: (a) `metaKey`-only arming (Ctrl+letter
never arms — closes the prior review's highest-risk Win/Linux vector); (b)
`preventDefault` on every bound accelerator with a per-accel test; (c) `isEditable`
suppression so native ⌘C/⌘A/⌘R still work inside inputs/textareas; (d) modal
suppression; (e) the two physically/logically hostile chords (⌘W, ⌘K) are
deliberately NOT bound; (f) **⌘C yields to native copy when a non-empty page-text
selection exists** (reviewers CPO #1 / Kieran P1 / spec-flow) — closes the residual
"copy of selected non-editable text is hijacked" vector, the exact conflict `g c`
was rebound away from in #5636; (g) the accelerator HINT is Apple-only so no
non-mac user is shown an unreachable "Ctrl+D" false affordance (CPO #2).

*Accepted residual:* admin ⌘A (select-all) still `preventDefault`s page
select-all with an active selection — accepted (admin-only, replaces rather than
destroys a selection, no data-loss) and covered by the `user-impact-reviewer`
review-time pass.

> **Sharp Edge (plan-quality gate):** a plan whose `## User-Brand Impact` section
> is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6. This
> section is complete; threshold is `single-user incident`.

## Implementation Phases

### Phase 0 — Preconditions (read-only, no code)

- Re-confirm `use-shortcuts.tsx:88` union is untouched target (`git grep -n "metaKey || e.ctrlKey" apps/web-platform/components/command-palette/use-shortcuts.tsx`).
- Re-confirm the `g`-arm + modal guard block (L509-523) is the insertion anchor.
- Confirm `modChord` + `isApplePlatform` exports in `platform.ts` (display glyphs).
- Confirm no other consumer imports `NavItem` expecting a closed field set (`git grep -n "NavItem" apps/web-platform`).
- **Modal-suppression invariant (spec-flow GAP3):** the accelerator branch (like
  the shipped g-arm at L518) suppresses only on `[role="dialog"][aria-modal="true"]`.
  Confirm app modals set `aria-modal="true"` (the palette's own confirm modal does —
  `command-palette.tsx:559-561`). This is **parity with the shipped g-leader, not a
  new gap**; a bare `[role=dialog]` without `aria-modal` is a pre-existing g-leader
  characteristic, accepted here for consistency (see Sharp Edges).

### Phase 1 — `nav-items.ts`: the `accel` single source (Rule 3)

Add `readonly accel?: string` to `NavItem` with a doc-comment mirroring `seq`
(single source of truth for the accelerator letter; the resolver map, the palette
hint, and the `?` overlay row all derive from it). Bind exactly D/I/R/A:

```ts
export type NavItem = {
  readonly href: string;
  readonly label: string;
  readonly seq?: string;
  /** Optional single-letter Super/Meta accelerator (e.g. "d" → ⌘D). SINGLE
   * source for this destination's metaKey binding: resolver map + palette hint +
   * `?` overlay row all derive from it. Absent ⇔ intentionally unbound (⌘W is
   * physically unbindable; ⌘K is already the palette). */
  readonly accel?: string;
};

export const NAV_ITEMS: readonly NavItem[] = [
  { href: "/dashboard",           label: "Dashboard",      seq: "g d", accel: "d" },
  { href: "/dashboard/inbox",     label: "Inbox",          seq: "g i", accel: "i" },
  { href: "/dashboard/workstream",label: "Workstream",     seq: "g w" },           // NO accel — ⌘W unbindable
  { href: "/dashboard/kb",        label: "Knowledge Base", seq: "g k" },           // NO accel — ⌘K = palette
  { href: "/dashboard/routines",  label: "Routines",       seq: "g r", accel: "r" },
] as const;

export const ADMIN_NAV_ITEMS: readonly NavItem[] = [
  { href: "/dashboard/admin/analytics", label: "Analytics", seq: "g a", accel: "a" },
] as const;
```

### Phase 2 — `resolveNavChord` pure resolver + its map (Rules 1, 6, 7)

In `use-shortcuts.tsx`, add an `ASK_AGENT_ACCEL = "c"` constant (mirrors
`ASK_AGENT_SEQ`), then the accel→effect maps derived from `accel`, then the pure
resolver as a **sibling of `resolveSequence`**:

```ts
/** The Ask-an-agent Super accelerator (⌘C). Mirrors ASK_AGENT_SEQ; not a nav
 * route so it lives here, not on a nav array. */
export const ASK_AGENT_ACCEL = "c";

// letter → effect, derived once from the single-source `accel` fields.
const NAV_ACCEL_EFFECTS: Readonly<Record<string, CommandEffect>> = {
  ...Object.fromEntries(
    NAV_ITEMS.filter((i) => i.accel).map((i) => [
      (i.accel as string).toLowerCase(),
      { kind: "navigate", href: i.href } as CommandEffect,
    ]),
  ),
  [ASK_AGENT_ACCEL]: { kind: "openChat" },
};
const ADMIN_ACCEL_EFFECTS: Readonly<Record<string, CommandEffect>> =
  Object.fromEntries(
    ADMIN_NAV_ITEMS.filter((i) => i.accel).map((i) => [
      (i.accel as string).toLowerCase(),
      { kind: "navigate", href: i.href } as CommandEffect,
    ]),
  );

/**
 * Pure Super/Meta accelerator resolver — the metaKey-only sibling of
 * resolveSequence. Reads `e.metaKey` EXCLUSIVELY (never ctrlKey — Ctrl+letter on
 * Win/Linux is a hostile hijack of native shortcuts and must NOT arm). Rejects
 * the shift variant (⌘⇧D is a distinct chord) and editable focus / auto-repeat.
 * `g a`-style admin gating mirrors resolveSequence. Returns the CommandEffect (the
 * caller preventDefaults + runs it) or null (fall through to the g-leader arm).
 * NOTE on ⌥/Alt (reviewer DHH #6): on macOS Option transforms `e.key`
 * (⌘⌥D → "∂") so an Alt chord never matches a letter here; on Win/Linux Alt does
 * NOT transform the key, so `Meta+Alt+D` would technically match — but that combo
 * is harmless (navigates, no data-loss) and, since the accelerators are a macOS
 * feature in practice (Win+letter / Super+letter are OS/WM-reserved and rarely
 * reach the browser — which is WHY the HINT is gated to Apple, Phase 4), it is
 * accepted-unguarded, not silently wrong. No `altKey` type-widening warranted.
 */
export function resolveNavChord(
  e: ShortcutKeyEvent,
  ctx: ShortcutContext,
): CommandEffect | null {
  if (isEditable(e.target)) return null;        // Rule 6 — native ⌘C/⌘A/⌘R survive in inputs
  if (e.repeat) return null;
  if (!e.metaKey) return null;                  // Rule 1 — metaKey ONLY, never ctrlKey
  if (e.shiftKey) return null;                  // ⌘⇧<letter> is a distinct chord
  const k = e.key.toLowerCase();
  const navEffect = NAV_ACCEL_EFFECTS[k];
  if (navEffect) return navEffect;
  const adminEffect = ADMIN_ACCEL_EFFECTS[k];
  if (adminEffect) return ctx.isAdmin ? adminEffect : null; // Rule 7
  return null;
}
```

`k`/`w` are absent from both maps by construction → `resolveNavChord` returns
null for ⌘K / ⌘W (⌘K is already claimed by `resolveShortcut`; ⌘W never reaches
JS). No special-casing needed.

### Phase 3 — Listener precedence in the ONE global keydown handler (Rules 4, 8, 9)

Insert a branch in `handleKeyDown` **after** the `resolveShortcut` block returns
and **before** the `g`-arm block. Precedence: `resolveShortcut` → `resolveNavChord`
→ g-leader arm (UNCHANGED). Gated on `s.enabled` (the `command-palette` flag —
these are NEW bindings, unlike ⌘B), suppressed under any app modal (mirror the
g-arm guard), and `preventDefault` before running the effect (Rule 5). The
existing `if (!s.shortcutsEnabled) return;` at the top of the handler already
disables this branch too (Rule 8).

```ts
      const action = resolveShortcut(e);
      if (action) { /* …UNCHANGED (⌘K/⌘//⌘B)… */ return; }

      // --- Super/Meta accelerators (metaKey-only). AFTER resolveShortcut so
      // ⌘K=palette / ⌘B=sidebar stay authoritative; BEFORE the g-leader arm.
      // NEW flag-gated bindings → gated on `enabled`. ---
      if (s.enabled && !s.paletteOpen && !s.helpOpen) {
        // Resolve FIRST (pure, exits instantly on !metaKey for ordinary typing);
        // the DOM query then runs ONLY on an actual accelerator match — matching
        // the g-arm's "cheap, only on match" discipline (reviewers DHH #1 +
        // code-simplicity). NOT `if (querySelector) { resolve }` (that walked the
        // DOM on every keystroke).
        const navEffect = resolveNavChord(e, { isAdmin: s.isAdmin });
        if (navEffect) {
          // ⌘C YIELDS to native copy when the user has a non-empty selection —
          // copying agent/KB/code output is a core reading gesture and isEditable
          // does NOT cover selected text in a plain <p>/<div> (focus on body).
          // No selection → ⌘C opens chat as bound. resolver stays DOM-free; this
          // selection read lives in the listener (reviewers CPO #1 / Kieran P1 /
          // spec-flow). Scoped to openChat (⌘C) only — the sole accelerator whose
          // native action captures the current selection.
          const yieldToCopy =
            navEffect.kind === "openChat" &&
            (window.getSelection()?.toString() ?? "") !== "";
          // Suppress under any app modal (a nav-away would discard unsaved input)
          // — parity with the g-arm guard. preventDefault stops the native
          // ⌘D/⌘R/⌘A/⌘C data-loss action.
          if (
            !yieldToCopy &&
            !document.querySelector('[role="dialog"][aria-modal="true"]')
          ) {
            e.preventDefault();
            s.runEffect(navEffect);
            return;
          }
        }
      }

      // --- Arm a new go-to prefix on `g`. …UNCHANGED… (a metaKey chord never
      // arms: resolveSequence(false, …) returns null when mod is set) ---
```

### Phase 4 — Hint rendering: help overlay + palette (Rule 10)

**Badge treatment (from the committed wireframe, `super-key-accelerators.pen`):**
accelerator glyph FIRST, then the `g`-leader (`⌘D` then `G D`), both reusing the
existing `.cmdk-keys` style (muted monospace `~0.72rem #8A8A8A` — NOT a boxed
pill), 8px gap, **no separator glyph**. The `g`-leader stays flush-right so it
forms one consistent right-hand column; single-hint rows (Workstream/KB) leave the
accelerator slot empty and align in that same column, so the asymmetry reads as
intentional. Purely additive: a second `<kbd class="cmdk-keys">` in the existing
right-side cluster, no new component. **Supersession:** the wireframe's
`*-windows-linux` frames depict an off-mac "Ctrl+D" chip; that is OVERRIDDEN by
CPO #2 below (off-mac renders the g-seq only). The badge *anatomy* above (order /
gap / column) is authoritative for the mac case.

Show the accelerator hint **on Apple only**, alongside the g-sequence. Rationale
(reviewer CPO #2 — false-affordance fix): `resolveNavChord` is `metaKey`-only, and
off-mac `metaKey` is the Win/Super key whose letter combos are OS/WM-reserved
(Win+D=show desktop, Win+R=Run, …) and never reach the browser. Rendering
`modChord("D", false)` → **"Ctrl+D"** off-mac would advertise a chord that cannot
fire (Ctrl is never read). So: **dual-hint on mac (⌘D + G D), g-sequence-only
off-mac.** This also removes the second `<kbd>` clutter for the majority-by-count
non-mac users (addresses reviewer DHH #5).

**`command-palette/use-shortcuts.tsx` — `Command` type + `buildCommands`:** add a
display-only `readonly accelKeys?: string` to `Command` (sibling of `keys`; named
`accelKeys` to disambiguate from nav-items' single-letter `accel`). In
`buildCommands`, populate it **only when `isApple`**:
`accelKeys: item.accel && isApple ? modChord(item.accel.toUpperCase(), true) : undefined`
(→ `⌘D`). Ask-agent command: `accelKeys: isApple ? modChord("C", true) : undefined`.
**Do NOT fold the accel into `keys`** — the existing AC7 test asserts `cmd.keys
=== formatSeqHint(seq)` exactly; keep `keys` as the g-seq hint.

**`command-palette.tsx`:** in the Navigation rows render
`{cmd.accelKeys && <span className="cmdk-keys"> {cmd.accelKeys}</span>}` alongside
the existing `{cmd.keys && …}` span. For the **ask hero**, gate the accel span on
the SAME `!trimmed` condition the existing `keys` hint uses (`command-palette.tsx:292`,
`{!trimmed && askCmd.keys && …}`) — otherwise `⌘C` renders next to "Ask an agent
about "<query>"" once the user types (reviewer Kieran P2b): `{!trimmed &&
askCmd.accelKeys && <span className="cmdk-keys"> {askCmd.accelKeys}</span>}`.

**`help-overlay.tsx`:** extend `SeqRow` with `accel?: string` (the raw letter,
platform-independent). Populate `NAV_ROWS`/`ADMIN_NAV_ROWS`/`AGENT_ROW` from
`i.accel` / `ASK_AGENT_ACCEL`. Render the accel `<kbd>` **only when
`isApplePlatform`** (the component already reads it from context):
`{row.accel && isApplePlatform && <kbd className="cmdk-keys">{modChord(row.accel.toUpperCase(), true)}</kbd>}` **before** the existing `<kbd>{row.keys}</kbd>`.
Keep `data-testid={\`help-row-${keys}\`}` (the G-seq) so existing selectors still
pass; the accel `<kbd>` is additive and mac-only.

### Phase 5 — Verify

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/shortcuts-registry.test.ts test/command-palette.test.tsx test/help-overlay.test.tsx`
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (canonical form — the repo root has no `workspaces` field, so `npm run -w` fails).

## Files to Edit

- `apps/web-platform/components/command-palette/nav-items.ts` — `accel?` field + D/I/R/A bindings.
- `apps/web-platform/components/command-palette/use-shortcuts.tsx` — `ASK_AGENT_ACCEL`, accel maps, `resolveNavChord`, listener branch, `Command.accelKeys` + `buildCommands` population. **Line 88 union NOT touched.**
- `apps/web-platform/components/command-palette/command-palette.tsx` — render `accelKeys` on nav rows + ask hero.
- `apps/web-platform/components/command-palette/help-overlay.tsx` — `SeqRow.accel` + platform-aware accel `<kbd>` per row.
- `apps/web-platform/test/shortcuts-registry.test.ts` — `resolveNavChord` describe block + `accel` single-source assertions + `buildCommands.accelKeys`.
- `apps/web-platform/test/command-palette.test.tsx` — Super+letter navigation + preventDefault assertions + suppression matrix.
- `apps/web-platform/test/help-overlay.test.tsx` — dual-hint row assertions.

## Files to Create

- `knowledge-base/product/design/command-palette/super-key-accelerators.pen` — wireframe of the help-overlay "Go to" rows + palette Navigation rows showing the **dual hint** (accelerator glyph + G-sequence). Produced by `ux-design-lead` (Phase 2.5). Referenced by FRs in §Domain Review.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `resolveNavChord(key("d",{meta:true}), nonAdmin)` → `{kind:"navigate",href:"/dashboard"}`; same for `i`→inbox, `r`→routines, `c`→`{kind:"openChat"}`.
- [ ] AC2 — `resolveNavChord(key("a",{meta:true}), admin)` → analytics; with `nonAdmin` → `null` (Rule 7).
- [ ] AC3 — `resolveNavChord(key("w",{meta:true}), admin)` → `null` AND `resolveNavChord(key("k",{meta:true}), admin)` → `null` (the two deliberately-unbound keys).
- [ ] AC4 — `resolveNavChord(key("d",{ctrl:true}), admin)` → `null` (Rule 1 — Ctrl+letter never arms).
- [ ] AC5 — `resolveNavChord(key("d",{meta:true,shift:true}), admin)` → `null`; and with editable target (`{tagName:"INPUT"}`) → `null` (Rule 6); and with `repeat:true` → `null`.
- [ ] AC6 — Regression: `resolveShortcut(key("k",{ctrl:true}))` still `"openPalette"` and `resolveShortcut(key("b",{ctrl:true}))` still `"toggleSidebar"` (Rule 2 — line 88 union intact on non-mac).
- [ ] AC7 — In `command-palette.test.tsx`, pressing `key:"d", metaKey:true` on `document.body` calls `routerPush("/dashboard")` **and** the dispatched event was canceled (`preventDefault` fired). Assert the cancel via a returning-`pressKey` variant that captures `fireEvent.keyDown(...) === false` **inside `act()`** (Kieran P2a — `dispatchEvent` is synchronous so the boolean is available before `act` flushes; capturing inside `act` avoids the React not-wrapped-in-act warning). One assertion per bound accel: D, I, R, and A(admin). (Rule 5.) The C case is split into AC7b.
- [ ] AC7b — ⌘C **with no selection** (`window.getSelection().toString()===""`) opens chat (`routerPush("/dashboard/chat/new")`) + event canceled. ⌘C **with a non-empty non-editable selection** (stub `window.getSelection` → `{toString: () => "picked text"}`) performs NATIVE copy: `routerPush` NOT called AND event NOT canceled (`fireEvent.keyDown(...) === true`). (Reviewers CPO #1 / Kieran P1 / spec-flow — the residual-vector guard.)
- [ ] AC8 — Super+A is inert (no `routerPush`, event NOT canceled — native select-all preserved) for a non-admin; navigates + cancels for an admin. (Distinct from AC2's resolver-null check: this asserts the *listener* does not `preventDefault*.)
- [ ] AC9 — Super+letter is inert (no `routerPush`) when focus is in `outside-input` (native ⌘C/⌘A/⌘R preserved), when a `[role=dialog][aria-modal=true]` node is present, **when the palette or help overlay is open** (spec-flow GAP2), when `enabled=false` (flag off), and when `soleur:shortcuts.enabled="0"` (WCAG turn-off). (Rules 6, 8, 9.)
- [ ] AC10 — `⌘K` still opens the palette (not intercepted by resolveNavChord — precedence: resolveShortcut first); `g d` still navigates (g-leader unchanged).
- [ ] AC10b — Armed-prefix × Super-chord hand-off (spec-flow GAP1): `g` then `⌘D` fires exactly ONE `routerPush("/dashboard")` and clears the pending prefix (a subsequent bare `d` does NOT re-navigate); `g` then `⌘K` opens the palette (no `routerPush`).
- [ ] AC11 — Hint is **Apple-only**. `buildCommands({isAdmin:true},{isApplePlatform:true})`: Dashboard `accelKeys==="⌘D"`, Analytics `"⌘A"`, ask-agent `"⌘C"`; Workstream/KB `accelKeys===undefined`. `buildCommands({isAdmin:true},{isApplePlatform:false})` (and the default no-opts call): **every** `accelKeys===undefined`. `keys` unchanged (`"G D"` …) in both — the existing AC7/seq single-source test (`shortcuts-registry.test.ts:196`) stays green.
- [ ] AC12 — On happy-dom (non-Apple default): palette Navigation rows render ONLY the g-seq (`G D`, `G W`), no accel chip; help overlay "Go to Dashboard" renders ONLY `G D`. With `isApplePlatform` stubbed true: Dashboard palette row + help row render BOTH `⌘D` and `G D`; Workstream renders only `G W` (no `accel`). (Mac-only hint, CPO #2.)
- [ ] AC13 — `apps/web-platform` `tsc --noEmit` clean; full `test/shortcuts-registry.test.ts`, `test/command-palette.test.tsx`, `test/help-overlay.test.tsx` green (run from `apps/web-platform/` via `./node_modules/.bin/vitest run …`).
- [ ] AC14 — `knowledge-base/product/design/command-palette/super-key-accelerators.pen` committed (non-empty) and referenced here (satisfies `wg-ui-feature-requires-pen-wireframe` / deepen-plan Phase 4.9).

## Test Scenarios

Pure (node, `shortcuts-registry.test.ts`): a `describe("resolveNavChord")` mirroring
the `resolveSequence` block (arm-on-meta, reject-ctrl, reject-shift, editable +
repeat suppression, admin gate, unmapped `k`/`w`/`x` → null). Assert the **accel
single-source via `resolveNavChord` behavior** — NOT by importing `NAV_ACCEL_EFFECTS`
(that map is module-private, mirroring the un-exported `NAV_SEQUENCE_EFFECTS`;
adding an export would exceed Files-to-Edit — reviewer Kieran P2c). `buildCommands`
accelKeys assertions for both `isApplePlatform` values (AC11).

Component (dom): a `describe("CommandPalette — Super/Meta accelerators")` covering
AC7–AC10b. Add a returning `pressKeyReturning(key, opts)` helper that captures the
cancel boolean **inside `act()`**: `let cancelled; act(() => { cancelled =
fireEvent.keyDown(target, {...}) === false; }); return cancelled;` (Kieran P2a —
`false` ⇔ `preventDefault` fired; capturing inside `act` avoids the React
not-wrapped warning that `runEffect`'s `setPaletteOpen(false)` would otherwise
trigger). For AC7b, stub `window.getSelection`. Help-overlay hint test: default
(non-Apple) renders only the g-seq; with `isApplePlatform` stubbed, the mac accel
`<kbd>` appears (AC12). Use `waitFor` before negative (`not.toHaveBeenCalled`)
assertions where an async effect could race.

## Domain Review

**Domains relevant:** Product (UI-surface — mechanical override fired on
`components/command-palette/*.tsx` edits).

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override — edited `.tsx` under
`components/**` matches the glob superset). The change is additive hint text on
existing rows (a mac-only `⌘D` glyph beside the existing `G D`), not a new
page/flow/component — the genuine design question the wireframe answers is the
dual key-hint row treatment.
**Decision:** reviewed (auto-accepted, pipeline — headless one-shot; no operator pause per Phase 2.5 step 4b headless arm).
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead.
**Skipped specialists:** none.
**Pencil available:** yes — `.pen` committed at `knowledge-base/product/design/command-palette/super-key-accelerators.pen` (see AC14).

#### Findings

**CPO (product advisory — keymap NOT re-litigated):** two bounded refinements,
both folded in. (1) ⌘C must yield to native copy when a non-empty non-editable
selection exists — closes the residual single-user-incident vector (copying
agent/KB output is a core gesture). → Applied in Phase 3 + AC7b + mitigation (f).
(2) Gate the accelerator hint on `isApplePlatform` — off-mac "Ctrl+D" is a false
affordance (binding is metaKey-only; Win/Super+letter OS-reserved). → Applied in
Phase 4 + AC11/AC12 + mitigation (g). CPO confirmed the ADDITIVE (not replacing)
approach is brand-aligned (delivery-agnostic positioning; constitution
"accessibility basics" carve-out honored via the retained g-leader + WCAG toggle).
Strategic note (non-blocking): value accrues mostly to macOS — keep it an internal
velocity feature, not a "cross-platform keyboard-power-user" marketing claim.

**spec-flow-analyzer (keyboard-flow completeness):** Q3–Q6 flow-complete. Three
gaps folded in: GAP1 (armed-`g` × Super-chord hand-off untested) → AC10b; GAP2
(palette/help-open suppression unlisted) → AC9 extended; GAP3 (`aria-modal="true"`
invariant) → Phase 0 audit + Sharp Edge (accepted g-leader parity). No dead-end
bugs; the ⌘C/⌘A non-editable-selection hijacks are named, operator-approved, and
now (⌘C) guarded.

**Plan-review (DHH / Kieran / code-simplicity):** core factoring endorsed by all
three (pure `resolveNavChord` sibling, line-88 union untouched, `accelKeys`
separate field justified by the `keys===formatSeqHint(seq)` test). Applied: DHH#1
+ code-simplicity (invert the modal `querySelector` — resolve first); Kieran P1
(⌘C mitigation overclaim → selection-yield + AC7b); Kieran P2a (capture cancel
boolean inside `act()`); Kieran P2b (ask-hero accel gated on `!trimmed`); Kieran
P2c (assert single-source via behavior, not by exporting the private map); DHH#6
(⌥/Alt comment corrected to admit the harmless Win/Linux case). Noted/kept: the
`.pen` pipeline is process tax for a hint chip (rides the hard `wg-` gate); double
`isEditable`/`repeat` guards are correct resolver-isolation parity; `accel?:string`
kept per Rule 3.

## Observability

**Gate 2.9 status:** does NOT fire — Files-to-Edit are all under
`apps/web-platform/components/` and `apps/web-platform/test/`, none under
`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and no
new infrastructure surface. This is a pure client-side keydown handler that adds
**no new error path, log call, or failure mode** reaching Sentry/Better Stack.
Discoverability is the vitest suite (`vitest run …`, NO ssh). Client-observability
(`reportSilentFallback`) is untouched — no new emit site, so no monitor darkens.

## Architecture Decision (ADR/C4)

**No architectural decision.** This extends an already-documented sibling-resolver
pattern (`resolveShortcut`/`resolveSequence`) with one more pure arm; it moves no
ownership/tenancy boundary, adds no substrate/integration, and changes no
cross-cutting trust boundary every consumer must honor. A competent engineer
reading the existing code + the merged `super-key-nav-shortcuts` plan would not be
misled.

**C4 completeness check (mandate):** read `model.c4`, `views.c4`, `spec.c4`. The
model's actors are `founder`, `emailSender (#external)`, `contributor (#external)`;
external systems are all third-party vendors (`#external`). This feature adds no
external human actor, no external system/vendor, no container/data-store, and no
actor↔surface access-relationship — it is an in-browser keyboard interaction on an
existing client surface. **No `.c4` edit required.**

## GDPR / Compliance Gate

**Considered under trigger (b)** (`brand_survival_threshold: single-user incident`
declared). **Skipped — reasoned:** the feature processes NO personal data. It
touches no schema/migration/auth/API/`.sql` surface (canonical regex misses), runs
no LLM/external API on session data (trigger a), reads no learnings/specs (trigger
c), and adds no artifact-distribution surface (trigger d). The single-user-incident
threshold here is *native-action hijack / data-loss*, not personal-data exposure.
No regulated-data surface → advisory gate would return empty.

## Infrastructure (IaC)

None — pure client code change against an already-provisioned surface. No server,
secret, vendor, cron, or persistent runtime process introduced.

## Open Code-Review Overlap

**None.** Scanned all 61 open `code-review`-labelled issues (`gh issue list
--label code-review --state open`) for the 4 edited source paths (`nav-items`,
`use-shortcuts`, `help-overlay`, `command-palette` under
`components/command-palette/`) — zero matches. No fold-in / defer needed.

## Risks & Sharp Edges

- **⌘R is only "soft-reload" preventable.** `preventDefault` on ⌘R stops the
  soft reload; **⌘⇧R (hard reload) still fires** — this is an acceptable escape
  hatch, not a gap. Document in the accel doc-comment so it isn't "fixed" later.
- **The prior plan's review called these chords HOSTILE.** This plan is the
  operator-approved override of that recommendation. The `preventDefault`+test
  discipline (Rule 5) is the exact mitigation the prior review required before any
  accelerator could bind — it is load-bearing, not ceremony. Do not weaken it.
- **⌘C selection-yield lives in the LISTENER, not `resolveNavChord`.** The resolver
  stays DOM-free per ADR discipline (`platform.ts` header: resolvers never read
  DOM/navigator). The `window.getSelection()` check that lets ⌘C fall through to
  native copy is in the keydown handler. Do not push it into the pure resolver.
- **Accelerator hint is Apple-only by design.** Off-mac `modChord(letter,false)`
  = "Ctrl+D", but the binding is `metaKey`-only (Ctrl never fires it) and
  Win/Super+letter is OS/WM-reserved — so the hint would be a false affordance.
  `buildCommands`/help-overlay gate the accel glyph on `isApple`/`isApplePlatform`.
  Do not "fix" the missing off-mac hint — its absence is the correctness.
- **Invert the modal `querySelector`, don't gate the resolver behind it.** Call
  `resolveNavChord` first (instant `!metaKey` exit); run the DOM query only when it
  returns an effect. Gating the resolver behind `querySelector` walks the DOM on
  every keystroke (reviewers DHH #1 + code-simplicity).
- **Modal suppression matches `[role=dialog][aria-modal="true"]` only** — parity
  with the shipped g-leader (`use-shortcuts.tsx:518`). A bare `[role=dialog]`
  without `aria-modal` is not suppressed; this is a pre-existing g-leader
  characteristic accepted here, not a new gap (spec-flow GAP3). App modals set
  `aria-modal="true"` (confirmed in Phase 0).
- **`preventDefault` cancel-boolean must be captured inside `act()`** (Kieran P2a).
  The existing `pressKey` wraps `fireEvent` in `act` and drops the return; the new
  returning variant keeps the `act` wrap and captures the sync `dispatchEvent`
  result inside it — otherwise `runEffect`'s state update logs a React act warning.
- **Do NOT fold `accel` into `Command.keys`.** `shortcuts-registry.test.ts:196`
  asserts `cmd.keys === formatSeqHint(seq)` exactly; the accel lives in a new
  `accelKeys` field. Folding it in breaks AC7.
- **`preventDefault` assertion must not be swallowed by `act`.** The existing
  `pressKey` helper wraps `fireEvent` in `act()` and drops the return. Add a
  variant that returns `fireEvent.keyDown(...)` so the cancel boolean (false ⇔
  `preventDefault` fired) is assertable (Rule 5 / AC7).
- **`metaKey` is the union of ⌘/Win/Super — including Win+letter (OS-reserved) and
  Super on Linux WMs.** `resolveNavChord` will *attempt* to arm on those platforms
  but the OS/WM consumes the event before the browser sees it for the reserved
  combos; the bound D/I/R/A/C letters are not OS-reserved on Win/Linux for a
  focused web app, so they resolve. The `g`-leader remains the guaranteed
  cross-platform path — nothing regresses.
- **vitest path discipline:** all tests stay under `apps/web-platform/test/`
  (`*.test.ts` node / `*.test.tsx` dom). A co-located `components/**/*.test.tsx`
  would be silently un-collected.
- **`tsc` form:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT
  `npm run -w` (repo root declares no `workspaces`).
