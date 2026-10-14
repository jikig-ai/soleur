---
feature: feat-one-shot-likec4-code-viewer-zoom-syntax
lane: single-domain
plan: knowledge-base/project/plans/2026-06-05-feat-c4-code-viewer-font-zoom-syntax-plan.md
date: 2026-06-05
---

# Tasks — C4 Code Viewer: smaller font, zoom controls, `.c4` syntax highlighting

Derived from `2026-06-05-feat-c4-code-viewer-font-zoom-syntax-plan.md`. Runner: **vitest**
(never `bun test` — `apps/web-platform/bunfig.toml` blocks bun discovery). New tests live
under `apps/web-platform/test/` to match the vitest `include` globs.

## Phase 1 — `.c4` language + highlight + font-size extension (new module)

- [ ] 1.1 Create `apps/web-platform/components/kb/c4-code-syntax.ts`.
- [ ] 1.2 Confirm lezer tags exist (verified 2026-06-05): `keyword`, `lineComment`,
      `blockComment`, `comment`, `string`, `meta`, `brace`, `punctuation`.
- [ ] 1.3 Implement `c4Parser: StreamParser<C4State>` — keyword set (whole-word), `//` +
      `/* */` comments (track block state), single/double-quoted strings, `#tag` (meta),
      braces/`->` (punctuation), conservative `stream.next()` fallthrough → `null`.
- [ ] 1.4 Export `c4Language = StreamLanguage.define(c4Parser)`.
- [ ] 1.5 Export `c4HighlightStyle = HighlightStyle.define([...])` mapping tags →
      `var(--soleur-*)` (no literal hex). Tokens verified present in `app/globals.css`:
      `accent-gold-fg`, `accent-gold-text`, `text-muted`, `text-secondary`, `text-primary`.
- [ ] 1.6 Export `MIN_CODE_FONT_PX=10`, `MAX_CODE_FONT_PX=24`, `DEFAULT_CODE_FONT_PX=12`,
      `clampFontPx`, `fontSizeForZoom`, `codeFontTheme` (`EditorView.theme({"&":{fontSize},
      ".cm-gutters":{fontSize}})`).

## Phase 2 — wire extensions into `C4CodePanel`

- [ ] 2.1 In `apps/web-platform/components/kb/c4-shared.tsx`, import `EditorView`
      (`@codemirror/view`), `syntaxHighlighting` + `defaultHighlightStyle`
      (`@codemirror/language`), and the new `./c4-code-syntax` exports.
- [ ] 2.2 Add `const [zoom, setZoom] = useState(0)` to `C4CodePanel`.
- [ ] 2.3 Build `extensions = useMemo(() => [c4Language,
      syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
      syntaxHighlighting(c4HighlightStyle), codeFontTheme(zoom)], [zoom])`.
- [ ] 2.4 Pass `extensions={extensions}` to `<CodeMirror>`; keep `theme={isDark ? oneDark :
      undefined}`, `basicSetup`, `value`, `height`, `onChange` unchanged.

## Phase 3 — zoom toolbar controls

- [ ] 3.1 Add **A−** button (`aria-label="Decrease code font size"`), `disabled` at
      `MIN_CODE_FONT_PX`, clamping `setZoom`.
- [ ] 3.2 Add size label (e.g. `12px`); clicking it (or a dedicated reset button,
      `aria-label="Reset code font size"`) sets `zoom = 0`.
- [ ] 3.3 Add **A+** button (`aria-label="Increase code font size"`), `disabled` at
      `MAX_CODE_FONT_PX`.
- [ ] 3.4 Style with the existing toolbar idiom (`rounded px-2 py-0.5 text-[11px] …`).

## Phase 4 — tests

- [ ] 4.1 Create `apps/web-platform/test/c4-code-syntax.test.ts` (node project): unit-test
      `clampFontPx` (`8→10`, `40→24`), `fontSizeForZoom(0)==="12px"`, tokenizer
      classification over sample inputs, highlight-style no-hex + `--soleur-` grep.
- [ ] 4.2 Create `apps/web-platform/test/c4-code-panel.test.tsx` (happy-dom project): render
      `C4CodePanel` with a fake `ProjectResponse`; assert 3 zoom controls + aria-labels;
      click A+ → label increments; A− disabled at min; default label `12px`; render under
      light + dark `data-theme`; edit → onChange → Save enabled. Mock
      `@uiw/react-codemirror` if needed; assert passed props (extensions/theme), not layout.
- [ ] 4.3 Run `./node_modules/.bin/vitest run test/c4-code-panel.test.tsx test/c4-code-syntax.test.ts`
      from `apps/web-platform/`. Confirm existing `test/c4-workspace.test.tsx` still green.
- [ ] 4.4 `tsc --noEmit` clean for the web-platform package.

## Notes

- No new dependencies (`@codemirror/language`, `@codemirror/view`, `@lezer/highlight`,
  `@uiw/react-codemirror`, `@codemirror/theme-one-dark` all installed).
- No DB/API/infra/observability surface; pure front-end. Post-merge: none.
- Wireframe: `knowledge-base/product/design/engineering/c4-code-viewer-zoom-syntax.pen`.
