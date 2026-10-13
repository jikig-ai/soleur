# Tasks — LikeC4 Layer 2: re-render diagram after .c4 Save

Plan: `knowledge-base/project/plans/2026-06-05-feat-likec4-rerender-diagram-after-save-plan.md`
Branch: `feat-one-shot-likec4-rerender-on-save` · Closes #4964 · lane: cross-domain

## Phase 0 — Preconditions (verify before coding)

- [ ] 0.1 Confirm `likec4@1.50.0` exists + exports headless: `npx -y likec4@1.50.0 export json -o /tmp/m.json <real diagrams dir>` exits 0 (no native `dot`). (Already verified at deepen-plan 2026-06-05 — re-confirm in image build context.)
- [ ] 0.2 Confirm `reportSilentFallback` signature: `reportSilentFallback(err, { feature, op, extra, message })` at `apps/web-platform/server/observability.ts:183`.
- [ ] 0.3 Confirm `writeC4Diagram` receives `workspacePath` and both write surfaces (PUT route + Concierge tool) funnel through it.

## Phase 1 — Spawn helper (RED → GREEN)

- [ ] 1.1 Write `apps/web-platform/test/c4-render.test.ts` (spawn mocked): success → `{ok:true}`; non-zero exit → `non_zero_exit` + sanitized stderr; timeout → SIGKILL + `timeout`; ENOENT → `spawn_error`; fixed-argv assertion (no user input); cwd = scope-guarded diagrams dir. (RED)
- [ ] 1.2 Create `apps/web-platform/server/c4-render.ts` — `renderC4Model(workspacePath)` modeled on `pdf-linearize.ts`: `spawn("likec4", ["export","json","-o",C4_MODEL_JSON,"."], {cwd: diagramsDir, env: scoped {PATH,LANG,LC_ALL,HOME,TMPDIR}, stdio})`, `RENDER_TIMEOUT_MS=25_000` → SIGKILL, settle-once, concurrency gate (`C4_RENDER_CONCURRENCY` default ≤2), `RenderReason` union, `LIKEC4_BIN` env override (default `"likec4"`). (GREEN)

## Phase 2 — Wire re-render into writeC4Diagram (RED → GREEN)

- [ ] 2.1 Write `apps/web-platform/test/c4-writer-rerender.test.ts` (GitHub API + sync + render mocked): `.c4` save → render + JSON commit + re-sync → `rerendered:true`; render failure → `{ok:true, rerendered:false}` (.c4 commit NOT rolled back) + `reportSilentFallback` fired; `.md` save → no render; OUT_OF_SCOPE/413/SHA_MISMATCH unchanged. (RED)
- [ ] 2.2 Edit `apps/web-platform/server/c4-writer.ts`: after existing commit+sync succeed AND file is `.c4`, call `renderC4Model(workspacePath)`; on success read regenerated JSON + commit via same Contents API path (`.../diagrams/model.likec4.json`) + `syncWorkspace` again; add `rerendered: boolean` to success result; failure-isolate with `reportSilentFallback(err, {feature:"c4-rerender", op, extra, message})` → return `{ok:true, rerendered:false}`. Never fail the `.c4` save on re-render failure. (GREEN)
- [ ] 2.3 Update `WriteC4Result` success type: `{ ok: true; commitSha: string | null; rerendered: boolean }`.

## Phase 3 — Route + Concierge plumbing

- [ ] 3.1 Edit `apps/web-platform/app/api/kb/c4/[...path]/route.ts`: plumb `rerendered` into the 200 JSON response; add `export const maxDuration = 60;`.
- [ ] 3.2 Edit `apps/web-platform/server/c4-concierge-tools.ts`: propagate `rerendered` in the tool text response; **update honesty copy** (tool description + the "out-of-band / you cannot trigger" prompt lines at :55-59) — diagram now re-renders.
- [ ] 3.3 Grep + sweep any prompt-addendum file mirroring the Concierge honesty copy (per #4963 learning). Update `apps/web-platform/test/c4-prompt-addendum-honesty.test.ts` to assert the new copy. (AC6)

## Phase 4 — UI re-key of the stale banner

- [ ] 4.1 Edit `apps/web-platform/components/kb/c4-shared.tsx`: `C4CodePanel.save` reads `rerendered` from PUT response; widen `onSaved` to `(rerendered: boolean) => void | Promise<void>`; update `saveMsg` copy ("Saved — diagram updated." vs "Saved — diagram will update after re-render.").
- [ ] 4.2 Edit `apps/web-platform/components/kb/c4-workspace.tsx` + `c4-diagram.tsx`: `onSaved` handler → `await reload()` FIRST, then `setStale(!rerendered)`.
- [ ] 4.3 Extend `c4-code-panel.test.tsx` / `c4-workspace.test.tsx` / `c4-diagram.test.tsx`: `rerendered:true` → banner hidden after reload; `rerendered:false` → banner shown; save copy reflects state. (AC5)

## Phase 5 — Dockerfile + doc comments

- [ ] 5.1 Edit `apps/web-platform/Dockerfile` runner stage: `RUN npm install -g likec4@1.50.0` with no-native-graphviz + lockfile-parity + version-match comment (alongside the existing `@anthropic-ai/claude-code` global-install precedent). (AC8) NOT `@latest`.
- [ ] 5.2 (optional) Update `C4_MODEL_JSON` doc comment in `lib/c4-constants.ts` and the GET-route doc comment in `app/api/kb/c4/project/route.ts` — model is now regenerated at runtime on the write path.

## Phase 6 — Verify

- [ ] 6.1 `./node_modules/.bin/vitest run apps/web-platform/test/c4-render.test.ts apps/web-platform/test/c4-writer-rerender.test.ts apps/web-platform/test/c4-code-panel.test.tsx apps/web-platform/test/c4-workspace.test.tsx apps/web-platform/test/c4-diagram.test.tsx apps/web-platform/test/c4-prompt-addendum-honesty.test.ts` → all pass. (Use vitest, NOT `bun test` — `apps/web-platform/bunfig.toml` blocks bun discovery; runner is vitest per the test-runner Sharp Edge.)
- [ ] 6.2 `tsc --noEmit` clean (new `rerendered` field + widened `onSaved`). (AC10)
- [ ] 6.3 Confirm `package.json` + `package-lock.json` unchanged (no `likec4` dep added); CLI only in Dockerfile. (AC7)

## Phase 7 — Post-merge (operator/CI, automated)

- [ ] 7.1 `web-platform-release.yml` builds the runner image; `npm install -g likec4@1.50.0` layer succeeds (merge = deploy; no separate operator step). (AC11)
- [ ] 7.2 Post-deploy E2E (Playwright MCP, dev-cohort `c4-visualizer` page): edit a `.c4` in Code tab → Save → diagram visibly updates without manual `/soleur:architecture render`; no stale banner on success. Closes #4964. (AC12)
