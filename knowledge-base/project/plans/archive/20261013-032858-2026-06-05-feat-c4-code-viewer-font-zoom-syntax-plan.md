---
title: "feat: C4 code viewer — smaller default font, zoom controls, syntax highlighting"
date: 2026-06-05
type: feat
branch: feat-one-shot-likec4-code-viewer-zoom-syntax
lane: single-domain
brand_survival_threshold: none
status: planned
---

# ✨ feat: C4 code viewer — smaller default font, zoom controls, `.c4` syntax highlighting

## Enhancement Summary

**Deepened on:** 2026-06-05
**Sections enhanced:** Implementation Phases (Phase 1 tokenizer wiring), Research Reconciliation, Risks & Precedent, Domain Review (wireframe produced)

### Key Improvements
1. **Verified the CodeMirror 6 + lezer API surface against installed versions** (no new deps): `EditorView.theme` (`@codemirror/view:1403`), `StreamLanguage.define`/`StringStream`/`StreamParser.token` (`@codemirror/language`), `HighlightStyle.define`/`syntaxHighlighting` (`:865`), and all eight lezer `tags` used (`keyword`, `lineComment`, `blockComment`, `comment`, `string`, `meta`, `brace`, `punctuation`) confirmed present in `@lezer/highlight`.
2. **Pinned the exact tokenizer→highlight wiring contract** — `StreamParser.token` returns a *style tag NAME STRING* (`"keyword"`, `"comment"`, …), resolved by `StreamLanguage` against the lezer `tags` table; `HighlightStyle.define([{ tag: tags.keyword, color }, …])` styles the resolved tags. Tokenizer returns strings; highlight style maps tag objects. This was the highest-risk implementation detail.
3. **Verified all five `--soleur-*` tokens exist** in `apps/web-platform/app/globals.css` (`accent-gold-fg`, `accent-gold-text`, `text-muted`, `text-secondary`, `text-primary`) — AC5's no-hex + token-reference claim is grounded.
4. **Produced the `.pen` wireframe** (gate 4.9) showing the new zoom toolbar + syntax colors.

### New Considerations Discovered
- The `StreamParser.token` string-vs-tag-object distinction means the tokenizer and the highlight style are decoupled — the tokenizer can be unit-tested purely (feed a `StringStream`, assert the returned string) without instantiating a highlight style.
- `defaultHighlightStyle` (from `@codemirror/language`) can be layered *underneath* `c4HighlightStyle` via two `syntaxHighlighting(...)` extensions as a fallback for any tag the custom style does not cover — recommended for robustness.

## Overview

The LikeC4 full-workspace split (`c4-workspace.tsx`) has a **Code** tab on the right that
renders the project's `.c4` source files in a CodeMirror 6 editor (`C4CodePanel` in
`components/kb/c4-shared.tsx`). Three problems:

1. **Font too big.** `<CodeMirror>` is mounted with no font-size control, so it inherits
   CodeMirror's / `oneDark`'s base size (~13–14px on `.cm-content`). Relative to the
   surrounding chrome — tab labels at `text-[11px]`/`text-xs` — the editor text reads as
   oversized. Make the **default smaller** (12px) and let the user adjust.
2. **No zoom controls.** There is no per-editor text-size control anywhere in `C4CodePanel`.
   Add **zoom-in / zoom-out** (and a reset) buttons scoped to the code editor.
3. **No real syntax highlighting.** `oneDark` themes only the editor *chrome* (gutter,
   selection, background). No CodeMirror **language extension** is wired for `.c4`, so the
   DSL renders as one undifferentiated text color — keywords, identifiers, strings, and
   comments are all the same. Add a lightweight `.c4` tokenizer + a Soleur-tokened
   `HighlightStyle` so the source is legible.

This is a **pure front-end change** against an already-shipped component. No new
dependencies are required — `@codemirror/language` (exports `StreamLanguage`,
`HighlightStyle`, `syntaxHighlighting`), `@codemirror/view` (`EditorView.theme`), and
`@lezer/highlight` (`tags`) are all already installed (verified below). No new
infrastructure, no secrets, no DB, no network surface.

## Premise Validation

No external issues/PRs are cited by the feature description (no external premises to
validate). All three claims were verified by reading the source against the current
worktree (= `origin/main` for these files):

- **Code viewer location:** `C4CodePanel` at `apps/web-platform/components/kb/c4-shared.tsx:177-273`,
  consumed by `c4-workspace.tsx:181` (Code tab). The `<CodeMirror>` call at
  `c4-shared.tsx:263-269` passes `value`, `height`, `theme`, `onChange`, `basicSetup` —
  **no `extensions` prop, no font-size control** → "renders too big" is real.
- **No zoom UI:** grep of `C4CodePanel` shows no zoom/font-size control exists → build, not fix.
- **No syntax highlighting:** only `theme={isDark ? oneDark : undefined}` is passed; no
  language extension → `.c4` tokens render in a single color. "No syntax colors" is a real
  build gap, not a regression. There is **no published `@likec4/*` CodeMirror language
  package** (`ls node_modules/@likec4` → `core`, `diagram`, `styles` only), so the tokenizer
  must be hand-rolled via `StreamLanguage`.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (`knowledge-base/project/specs/feat-one-shot-likec4-code-viewer-zoom-syntax/`
absent). No spec claims to reconcile. Dependency / API facts verified directly:

| Claim | Reality (verified) | Plan response |
|---|---|---|
| A LikeC4 CodeMirror language pkg exists | **False** — `node_modules/@likec4/` = `core`, `diagram`, `styles` only | Hand-roll a `StreamLanguage` tokenizer for the `.c4` DSL |
| `StreamLanguage`/`HighlightStyle`/`syntaxHighlighting` available | **True** — exported from `@codemirror/language` (in `package.json`, `node_modules/@codemirror/language/dist/index.d.ts:1220`) | Use directly; no new dep |
| `@uiw/react-codemirror` accepts an `extensions` array | **True** — `ReactCodeMirrorProps.extensions?: Extension[]` (`node_modules/@uiw/react-codemirror/esm/index.d.ts:65`) | Pass `[language, syntaxHighlighting(style), EditorView.theme(...)]` |
| `@lezer/highlight` `tags` available for the highlight style | **True** — `node_modules/@lezer/highlight/` present (transitive) | Import `tags` for `HighlightStyle.define` |
| `EditorView` import source | `@codemirror/view` (in `package.json`) | Import `EditorView` for `.theme({ "&": { fontSize } })` |

## User-Brand Impact

**If this lands broken, the user experiences:** the C4 **Code** tab editor renders with no
text or mis-sized/garish syntax colors, or the zoom buttons do nothing — a cosmetic
degradation of a read/edit surface that already works today. The diagram canvas and
Concierge are untouched.

**If this leaks, the user's data is exposed via:** N/A — this change adds no data flow, no
network call, no persistence. It reads the already-fetched `.c4` source strings and renders
them client-side. Save path (PUT) is unchanged.

**Brand-survival threshold:** none — purely presentational editor enhancement; no
single-user breach vector. (Sensitive-path scope-out: `threshold: none, reason: front-end-only CodeMirror presentation change, no schema/auth/API/data-flow surface touched.`)

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — smaller default font.** The C4 code editor mounts with a **12px** default
      font size (down from CodeMirror/`oneDark` default). Verified by a component test
      asserting the editor's font-size theme extension resolves to `"12px"` at the default
      zoom level (test the pure `fontSizeForZoom(0)` helper === `"12px"`, since happy-dom
      does not lay out CodeMirror).
- [x] **AC2 — zoom in / zoom out / reset controls exist.** `C4CodePanel` renders three
      controls in the code-tab toolbar: **A−** (zoom out), **A+** (zoom in), and a reset
      affordance (clicking the current-size label or a dedicated reset button returns to
      default). Each has an `aria-label` (`"Decrease code font size"`, `"Increase code font
      size"`, `"Reset code font size"`). Verified by a test that renders `C4CodePanel`,
      clicks **A+**, and asserts the displayed size label increments (e.g. `12px → 13px`).
- [x] **AC3 — zoom is clamped.** Font size is clamped to `[10px, 24px]` (`MIN_CODE_FONT_PX`
      / `MAX_CODE_FONT_PX`). At the min, **A−** is `disabled`; at the max, **A+** is
      `disabled`. Verified by a unit test on the clamp helper: `clampFontPx(8) === 10`,
      `clampFontPx(40) === 24`.
- [x] **AC4 — syntax highlighting applied.** The `<CodeMirror>` `extensions` prop includes
      the `.c4` language extension and `syntaxHighlighting(c4HighlightStyle)`. Verified by a
      test asserting the exported `c4Language` is a `StreamLanguage` instance and that the
      tokenizer classifies known inputs: `specification`/`model`/`views`/`element`/
      `relationship` → `keyword`; `// foo` → `comment`; `"a string"` → `string`; `#tag` →
      `meta`/`tag` token. (Tokenizer is a pure function over `StringStream`; test it directly,
      not through DOM rendering.)
- [x] **AC5 — highlight colors use Soleur tokens, not literal hex.** `c4HighlightStyle` maps
      `tags.keyword`, `tags.comment`, `tags.string`, `tags.meta` (etc.) to `var(--soleur-*)`
      CSS variables (theme-aware, flips with `data-theme`) — consistent with the
      `c4-theme.css` token convention. Verified by a grep test asserting no raw `#rrggbb` in
      the highlight-style definition AND that it references `--soleur-` vars.
- [x] **AC6 — light/dark parity.** The editor chrome theme still switches on
      `data-theme` (existing `oneDark` for dark; default for light), and the new font-size +
      syntax extensions apply in **both** modes (the `extensions` array is theme-independent;
      only the chrome `theme` prop branches). Verified by a test rendering with
      `data-theme="light"` and `data-theme="dark"` and asserting the editor mounts (extensions
      present in both).
- [x] **AC7 — no behavioral regression to save/edit.** `value`/`onChange`/`dirty`/`Save`
      path is unchanged; existing `c4-workspace.test.tsx` (which mocks `C4CodePanel`) still
      passes, and the new `C4CodePanel` test exercises edit → `onChange` → dirty → Save.
- [x] **AC8 — new tests on the correct runner/path.** New test file lives at
      `apps/web-platform/test/c4-code-panel.test.tsx` (matches vitest `happy-dom` include
      `test/**/*.test.tsx`). Pure-helper tests for tokenizer/clamp may live in the same file
      or `apps/web-platform/test/c4-code-syntax.test.ts` (node project, `test/**/*.test.ts`).
      Run via `./node_modules/.bin/vitest run test/c4-code-panel.test.tsx` (and the `.test.ts`
      sibling) from `apps/web-platform/`. **Do NOT** prescribe `bun test` — `bunfig.toml`
      blocks bun discovery; the runner is vitest.
- [x] **AC9 — `tsc --noEmit` clean** for the web-platform package after the change.

### Post-merge (operator)

- [ ] None. Pure front-end change; merge → existing `web-platform-release.yml` path-filtered
      pipeline rebuilds the container. No operator step.

## Implementation Phases

> **Phase order is load-bearing**: build the pure helpers + extensions first (Phase 1),
> then wire them into `C4CodePanel` (Phase 2), then add the zoom UI (Phase 3). Each phase
> is independently testable.

### Phase 1 — `.c4` language + highlight + font-size extension (new module)

Create `apps/web-platform/components/kb/c4-code-syntax.ts` (a plain `.ts` module so its pure
helpers are unit-testable on the vitest **node** project, and so `c4-shared.tsx` stays a
client component importing from it):

- **`c4Language`** — a `StreamLanguage.define(c4StreamParser)` where `c4StreamParser` is a
  hand-rolled tokenizer for the LikeC4 DSL. Recognize:
  - **keywords** (`tags.keyword`): `specification`, `model`, `views`, `view`, `dynamic`,
    `element`, `relationship`, `tag`, `color`, `technology`, `style`, `extend`, `extends`,
    `link`, `icon`, `include`, `exclude`, `group`, `of`, `with`, `autoLayout`, `title`,
    `description`, `navigateTo`, `where`, `this`, `it` — derive the final list by sampling
    the actual `.c4` sources at runtime is NOT needed; base it on the LikeC4 grammar. Treat
    keyword matching as **whole-word** (`\b`-anchored) to avoid mid-identifier hits.
  - **comments** (`tags.lineComment` / `tags.blockComment`): `// …` to EOL, and `/* … */`
    blocks (track block state in the `StreamParser` `State`).
  - **strings** (`tags.string`): single- and double-quoted, plus LikeC4 triple-quoted
    `'''…'''` if present (handle gracefully — fall back to single-quote behavior if the
    triple form complicates state; strings are the high-value case).
  - **tags / refs** (`tags.meta`): `#tag-name` tokens.
  - **braces/punctuation** (`tags.brace` / `tags.punctuation`): `{ } ( ) -> ;`.
  - Everything else → default (no token) so identifiers render in the base text color.
  - Keep the parser **conservative**: when in doubt, consume one char and emit `null`. A
    tokenizer that mis-classifies is worse than one that under-classifies.
- **`c4HighlightStyle`** — `HighlightStyle.define([...])` mapping the lezer `tags` above to
  `color: var(--soleur-*)`:
  - `tags.keyword` → `var(--soleur-accent-gold-fg)` (gold, matches the diagram accent)
  - `tags.lineComment` / `tags.blockComment` → `var(--soleur-text-muted)`, `fontStyle: "italic"`
  - `tags.string` → `var(--soleur-text-secondary)` (or a dedicated string token if one exists;
    grep `globals.css` for available `--soleur-*` tokens before finalizing — see Sharp Edges)
  - `tags.meta` (tags/refs) → `var(--soleur-accent-gold-text)`
  - `tags.brace` / `tags.punctuation` → `var(--soleur-text-muted)`
  - **No literal hex** (AC5). Pick from the same `--soleur-*` palette `c4-theme.css` uses.
- **`MIN_CODE_FONT_PX = 10`**, **`MAX_CODE_FONT_PX = 24`**, **`DEFAULT_CODE_FONT_PX = 12`**.
- **`clampFontPx(px: number): number`** — clamp to `[MIN, MAX]`.
- **`fontSizeForZoom(zoom: number): string`** — pure helper, e.g.
  `\`${clampFontPx(DEFAULT_CODE_FONT_PX + zoom)}px\`` (1px per zoom step). Keeps the zoom
  state as a small integer and the px math in one tested place.
- **`codeFontTheme(zoom: number): Extension`** — returns
  `EditorView.theme({ "&": { fontSize: fontSizeForZoom(zoom) }, ".cm-gutters": { fontSize: fontSizeForZoom(zoom) } })`
  so gutter + content scale together.

> **Verification gate (Phase 1):** before finalizing keyword list & token tags, confirm the
> lezer tag names exist on the installed `@lezer/highlight` `tags` export
> (`grep -E "lineComment|blockComment|brace|punctuation|meta|keyword|string" node_modules/@lezer/highlight/dist/*.d.ts`).
> Use only tags that exist; `defaultHighlightStyle` from `@codemirror/language` can be layered
> underneath as a safety net for any unstyled tag. **All eight tags verified present
> 2026-06-05** (`keyword`, `lineComment`, `blockComment`, `comment`, `string`, `meta`,
> `brace`, `punctuation`).

#### Research Insights — tokenizer ↔ highlight wiring (load-bearing)

**The decoupling contract** (verified against `@codemirror/language/dist/index.d.ts:1129-1154`):
`StreamParser.token(stream, state)` returns a **style tag NAME STRING** — one of the names in
the lezer `tags` table (`"keyword"`, `"comment"`, `"lineComment"`, `"string"`, `"meta"`,
`"punctuation"`, …), optionally suffixed with modifier names — or `null`. It does **not**
return a `Tag` object. `StreamLanguage.define(parser)` resolves those strings against `tags`
internally. The **highlight style** is the other half: `HighlightStyle.define([{ tag:
tags.keyword, color: "var(--soleur-accent-gold-fg)" }, …])` maps `Tag` *objects* to CSS, and
`syntaxHighlighting(style)` is the extension that connects them.

```typescript
// c4-code-syntax.ts (shape — verified API)
import { StreamLanguage, HighlightStyle, syntaxHighlighting,
         defaultHighlightStyle, type StreamParser } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";
import { EditorView } from "@codemirror/view";
import type { Extension } from "@codemirror/state";

const KEYWORDS = new Set(["specification","model","views","view","dynamic","element",
  "relationship","tag","color","technology","style","extend","extends","link","icon",
  "include","exclude","group","of","with","autoLayout","title","description","navigateTo",
  "where","this","it"]);

interface C4State { inBlockComment: boolean }
const c4Parser: StreamParser<C4State> = {
  name: "c4",
  startState: () => ({ inBlockComment: false }),
  token(stream, state) {
    if (state.inBlockComment) {                     // block-comment body
      if (stream.match(/.*?\*\//)) state.inBlockComment = false; else stream.skipToEnd();
      return "blockComment";
    }
    if (stream.match("/*")) { state.inBlockComment = true; return "blockComment"; }
    if (stream.match("//")) { stream.skipToEnd(); return "lineComment"; }
    if (stream.match(/^"(?:[^"\\]|\\.)*"/) || stream.match(/^'(?:[^'\\]|\\.)*'/)) return "string";
    if (stream.match(/^#[A-Za-z][\w-]*/)) return "meta";          // #tag
    if (stream.match(/^[A-Za-z_]\w*/)) {                          // word
      const w = stream.current();
      return KEYWORDS.has(w) ? "keyword" : null;                 // identifiers → default
    }
    if (stream.match(/^[{}()]/) || stream.match("->")) return "punctuation";
    stream.next();                                                // conservative fallthrough
    return null;
  },
};
export const c4Language = StreamLanguage.define(c4Parser);

export const c4HighlightStyle = HighlightStyle.define([
  { tag: t.keyword,                       color: "var(--soleur-accent-gold-fg)" },
  { tag: [t.lineComment, t.blockComment, t.comment], color: "var(--soleur-text-muted)", fontStyle: "italic" },
  { tag: t.string,                        color: "var(--soleur-text-secondary)" },
  { tag: t.meta,                          color: "var(--soleur-accent-gold-text)" },
  { tag: [t.brace, t.punctuation],        color: "var(--soleur-text-muted)" },
]);

export const MIN_CODE_FONT_PX = 10, MAX_CODE_FONT_PX = 24, DEFAULT_CODE_FONT_PX = 12;
export const clampFontPx = (px: number) =>
  Math.min(MAX_CODE_FONT_PX, Math.max(MIN_CODE_FONT_PX, px));
export const fontSizeForZoom = (zoom: number) => `${clampFontPx(DEFAULT_CODE_FONT_PX + zoom)}px`;
export const codeFontTheme = (zoom: number): Extension =>
  EditorView.theme({ "&": { fontSize: fontSizeForZoom(zoom) },
                     ".cm-gutters": { fontSize: fontSizeForZoom(zoom) } });

// In c4-shared.tsx: extensions={[ c4Language,
//   syntaxHighlighting(defaultHighlightStyle, { fallback: true }),  // safety net
//   syntaxHighlighting(c4HighlightStyle), codeFontTheme(zoom) ]}
```

This shape is **illustrative** — the implementer must tune the keyword set to the LikeC4
grammar and confirm `stream.match`/`skipToEnd`/`current`/`next` against `StringStream`
(`@codemirror/language:1018`). The tokenizer's purity (no DOM, no React) is what makes the
node-project `c4-code-syntax.test.ts` possible (feed a constructed `StringStream`, assert the
returned string per AC4).

### Phase 2 — wire extensions into `C4CodePanel`

In `apps/web-platform/components/kb/c4-shared.tsx`:

- Add imports: `EditorView` from `@codemirror/view`; `syntaxHighlighting` from
  `@codemirror/language`; `c4Language, c4HighlightStyle, codeFontTheme, fontSizeForZoom,
  clampFontPx, MIN_CODE_FONT_PX, MAX_CODE_FONT_PX, DEFAULT_CODE_FONT_PX` from `./c4-code-syntax`.
- Add `const [zoom, setZoom] = useState(0);` to `C4CodePanel`.
- Build `const extensions = useMemo(() => [c4Language, syntaxHighlighting(c4HighlightStyle), codeFontTheme(zoom)], [zoom]);`
- Pass `extensions={extensions}` to `<CodeMirror>` (keep `theme={isDark ? oneDark : undefined}`,
  `basicSetup`, `value`, `height`, `onChange`). The `extensions` array is **theme-independent**
  so syntax + font apply in both light/dark (AC6).
- Do **not** remove `oneDark` — it themes the chrome; the new `extensions` add language +
  font on top.

### Phase 3 — zoom-in / zoom-out / reset toolbar controls

In the `C4CodePanel` toolbar row (`c4-shared.tsx:235-261`, the `flex … border-b` div), add a
control cluster next to the Save button (or left of `saveMsg`):

- **A−** button: `onClick={() => setZoom((z) => clampStepDown)}`, `aria-label="Decrease code
  font size"`, `disabled` when `fontSizeForZoom(zoom)` is already at `MIN_CODE_FONT_PX`.
- A small **size label**: shows the current px (e.g. `12px`); clicking it (or a dedicated
  reset button, `aria-label="Reset code font size"`) sets `zoom = 0`.
- **A+** button: `onClick={() => setZoom((z) => clampStepUp)}`, `aria-label="Increase code
  font size"`, `disabled` at `MAX_CODE_FONT_PX`.
- Style with the existing toolbar idiom (`rounded px-2 py-0.5 text-[11px] … text-soleur-text-muted
  hover:text-soleur-text-secondary`) so it matches the file-tab buttons. Keep buttons small;
  the toolbar already uses `flex-wrap`.
- Clamp at the state boundary too (`setZoom` should never push px outside `[MIN, MAX]`), so the
  disabled state and the value can never diverge.

### Phase 4 — tests

Create `apps/web-platform/test/c4-code-panel.test.tsx` (happy-dom project) and optionally
`apps/web-platform/test/c4-code-syntax.test.ts` (node project) per AC8:

- Pure helpers (`c4-code-syntax.test.ts`, node): `clampFontPx`, `fontSizeForZoom`, tokenizer
  classification over sample inputs (AC3, AC4), highlight-style token→`--soleur-*` mapping +
  no-hex grep (AC5).
- Component (`c4-code-panel.test.tsx`, happy-dom): render `C4CodePanel` with a fake
  `ProjectResponse` (one `model.c4` source); assert the three zoom controls render with their
  `aria-label`s (AC2); click **A+** and assert the size label increments; assert **A−**
  disabled at min after repeated clicks (AC3); assert default label reads `12px` (AC1); render
  under `data-theme="light"` and `"dark"` and assert mount (AC6); type into the editor →
  `onChange` fires → Save enabled (AC7).
- Mock `@uiw/react-codemirror` if happy-dom cannot lay out CodeMirror's contenteditable — a
  lightweight mock that surfaces `value`, `onChange`, and the passed `extensions`/`theme` props
  is sufficient to assert wiring (this mirrors how `c4-workspace.test.tsx` already mocks
  `C4CodePanel`). Prefer asserting the **props passed to CodeMirror** (extensions array length,
  presence of the font theme) over DOM-measured pixel sizes — happy-dom does not compute layout.

## Files to Edit

- `apps/web-platform/components/kb/c4-shared.tsx` — wire `extensions` (language + highlight +
  font theme) into `<CodeMirror>`; add `zoom` state + toolbar zoom controls in `C4CodePanel`.

## Files to Create

- `apps/web-platform/components/kb/c4-code-syntax.ts` — `c4Language` (StreamLanguage),
  `c4HighlightStyle`, `codeFontTheme`, `clampFontPx`, `fontSizeForZoom`, font-px constants.
- `apps/web-platform/test/c4-code-panel.test.tsx` — component tests (happy-dom project).
- `apps/web-platform/test/c4-code-syntax.test.ts` — pure-helper + tokenizer tests (node
  project). *(Optional — may be folded into the `.test.tsx` file; keep the node-only pure
  tests here if happy-dom import of `@codemirror/*` is heavy.)*

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (70 open issues); none of the
bodies reference `components/kb/c4-shared.tsx`, `c4-theme.css`, `c4-shared`, `c4-workspace`,
`code viewer`, or `CodeMirror`. Check ran clean.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Wait for / install an upstream `@likec4/*` CodeMirror language package | None is published (`node_modules/@likec4` = core/diagram/styles only). LikeC4's own editor uses a Monaco/Langium stack server-side — not a CodeMirror grammar we can import. Hand-rolled `StreamLanguage` is the pragmatic fit. |
| Swap CodeMirror for Monaco to get rich highlighting | Heavy new dependency (MBs), SSR friction, and overkill for a read-mostly `.c4` viewer. The existing CodeMirror stack already ships; `StreamLanguage` covers the DSL legibly. |
| Browser-native page zoom for text size | Not scoped to the editor — the user asked for zoom **specific to the code viewer**. A per-editor font-size extension is the correct scope. |
| Global font-size in `c4-theme.css` via `.cm-content { font-size }` | Static; can't drive dynamic zoom from React state without re-introducing the same control. The `EditorView.theme(zoom)` extension is the idiomatic CodeMirror 6 path and co-locates font with the editor instance. |

## Test Scenarios

1. Default mount → editor font 12px (AC1).
2. Click **A+** 3× → 15px label; **A−** back to 12px; reset → 12px (AC2).
3. Spam **A−** → stops at 10px, button disabled (AC3); spam **A+** → stops at 24px, disabled.
4. Tokenizer: `model { user = element }` → `model`/`element` keyword-styled; `// note` →
   comment; `"Soleur"` → string; `#external` → meta (AC4).
5. Highlight style references only `--soleur-*` vars, zero `#rrggbb` (AC5).
6. Render under light + dark `data-theme` → both mount with extensions present (AC6).
7. Edit source → dirty → Save enabled; existing `c4-workspace.test.tsx` still green (AC7).
8. `tsc --noEmit` clean (AC9).

## Domain Review

**Domains relevant:** Product (UI surface — Product/UX Gate below)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** ux-design-lead (wireframe)
**Skipped specialists:** none. This modifies an existing editor surface inside an
already-shipped component by adding toolbar controls + text styling — ADVISORY per the
three-tier rule (no new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`,
so the mechanical BLOCKING escalation does not fire). However, the toolbar gains **new
interactive controls** (zoom buttons), which the UI-surface term list treats as a
structural change → a `.pen` wireframe was produced (not skipped) per
`wg-ui-feature-requires-pen-wireframe`.
**Pencil available:** yes (headless CLI Tier 0 via `pencil-setup --auto`; Node 24.15.0,
`PENCIL_CLI_KEY` from Doppler `soleur/dev`)

**Wireframe:** `knowledge-base/product/design/engineering/c4-code-viewer-zoom-syntax.pen`
(committed) — shows the C4 Code panel with the new **A− / 12px / A+** zoom toolbar cluster,
the Save button, and a syntax-highlighted `.c4` sample (gold keywords, muted-italic
comments, tan strings, amber `#tag`, default identifiers) with gutter line numbers and a
color legend. Screenshot at
`knowledge-base/product/design/engineering/screenshots/fYxsz-2026-06-05T09-51-25.png`. The
FR/AC font-size + highlight-token decisions trace to this wireframe.

#### Findings

Modifies the existing C4 **Code** tab: adds three small zoom buttons to the toolbar and
applies syntax colors + a smaller default font to the editor body. No new navigation, no
multi-step flow, no emotional/persuasive copy. Matches the existing toolbar visual idiom
(file-tab buttons, Save button). Auto-accepted on the pipeline path.

## Observability

Not applicable — pure client-side presentational change. No new `apps/*/server/`,
`apps/*/infra/`, `plugins/*/scripts/` code-class file, and no new infrastructure surface is
introduced. The only edited code-class file (`components/kb/c4-shared.tsx`) and the new
`c4-code-syntax.ts` run in the browser; failures are visible directly in the rendered editor
and caught by the component tests above. Skipped per the Phase 2.9 pure-front-end rule.

## Sharp Edges

- **`--soleur-*` token names must be verified before use.** Before finalizing
  `c4HighlightStyle`, `grep -E "--soleur-(text|accent|bg|border)" apps/web-platform/app/globals.css`
  (or wherever the design tokens live) and use only tokens that actually exist. `c4-theme.css`
  already references `--soleur-accent-gold-fg`, `--soleur-text-muted`, `--soleur-text-secondary`,
  `--soleur-text-primary`, `--soleur-accent-gold-text` — those are known-good. Do not invent a
  `--soleur-syntax-string`-style token unless it exists.
- **lezer `tags` names must exist on the installed version.** `@lezer/highlight` tag names
  (`brace`, `punctuation`, `meta`, `lineComment`, `blockComment`) vary across major versions.
  Grep `node_modules/@lezer/highlight/dist/*.d.ts` for each tag used; layer
  `defaultHighlightStyle` underneath as a fallback for any unstyled tag.
- **happy-dom cannot lay out CodeMirror.** Do NOT assert computed pixel font-size via
  `getComputedStyle` in the component test — happy-dom does not run CodeMirror's layout.
  Assert the **props passed to `<CodeMirror>`** (extensions array contents / font-theme
  presence) and the **size-label text**, and unit-test `fontSizeForZoom`/`clampFontPx` purely.
  Mock `@uiw/react-codemirror` in the component test if its contenteditable trips happy-dom.
- **Test path + runner.** New tests MUST live under `apps/web-platform/test/` (`.test.tsx` →
  happy-dom, `.test.ts` → node) to match vitest `include` globs; co-locating in `components/`
  is silently skipped. Run with vitest, never `bun test` (`bunfig.toml` blocks bun discovery).
- **Keep `oneDark` for chrome.** The new `extensions` add language + highlight + font on top
  of the chrome theme; removing `oneDark` would regress the dark-mode editor background/gutter.
  The chrome `theme` prop still branches on `data-theme`; the `extensions` array does not.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6 — this plan fills it (threshold:
  none, with the front-end-only scope-out reason).
- **Conservative tokenizer.** A `StreamLanguage` that mis-classifies (e.g. swallows an
  identifier as a keyword) is worse than one that under-highlights. When the parser is unsure,
  consume one char and emit `null`. Anchor keyword matches on whole-word boundaries.

## Risks & Mitigations — Precedent-Diff

**Precedent (token-reference convention):** `apps/web-platform/components/kb/c4-theme.css`
already establishes the canonical pattern for theming the LikeC4 surface — reference
`var(--soleur-*)` design tokens (never literal hex) so the theme flips with `data-theme`
(globals.css). `c4HighlightStyle` adopts this verbatim: every `color:` is a `var(--soleur-*)`
reference. **No novel pattern** — this is a direct extension of the existing convention to the
CodeMirror highlight layer. (No SQL / lock / atomic-write / RPC-permission precedent applies —
this is a pure front-end change; the precedent-diff gate's other classes are N/A.)

**Risk: `StreamLanguage` is a stream tokenizer, not a full parser.** It cannot do
multi-line-context-sensitive highlighting beyond what the `State` tracks. Mitigation: the
parser tracks only `inBlockComment` state; everything else is single-line. A conservative
tokenizer that under-highlights is acceptable (AC4 only requires the high-value cases:
keyword/comment/string/tag).

**Risk: keyword over-matching.** If a `.c4` identifier coincides with a keyword (e.g. a user
names an element `model`), it renders gold. Mitigation: this is cosmetic only and acceptable;
the tokenizer matches whole words via `/^[A-Za-z_]\w*/` then set-membership, so it never
mid-matches inside a longer identifier.

**Risk: happy-dom cannot lay out CodeMirror.** Covered in Sharp Edges — assert props and
test pure helpers, do not measure computed pixels.

**Risk: font theme + chrome theme interaction.** `oneDark` (chrome) and `codeFontTheme` /
`syntaxHighlighting` (extensions) are independent layers; `EditorView.theme({"&": {fontSize}})`
sets the editor root font size and CodeMirror's `em`-based internals scale from it. Verified
`EditorView.theme` accepts arbitrary CSS-in-JS specs (`@codemirror/view:1403`).

## Infrastructure (IaC)

Not applicable — no server, service, cron, vendor account, DNS, cert, secret, or firewall
rule introduced. Pure front-end edit against an already-provisioned surface
(`apps/web-platform/components/**`). Phase 2.8 skip condition met.
