# Tasks: fix #11143 headless Pencil MCP adapter

Plan: `knowledge-base/project/plans/2026-10-26-fix-pencil-mcp-headless-adapter-batch-design-noop-plan.md`
Scripts dir: `plugins/soleur/skills/pencil-setup/scripts/` (below, `scripts/`). Tests: `plugins/soleur/test/`.

## Phase 0 — failing tests first

- 0.1 Write `pencil-repl-surface.test.ts`: formatter (`operations` to `input`, preamble prefix, JSON-escaped newlines and quotes, empty `operations` throws, unknown tool or key throws, `save` is a keyless entry), `planSpawn` (exists non-empty to `inFile === outFile`; missing to null; 0-byte to null; explicit missing initial `inFile` throws; respawn ignores a prior explicit `inFile`), exact tool set and key lists.
- 0.2 Extend `pencil-save-gate.test.ts`: `diskTopLevelCount`, `memoryTopLevelCount`, `decideSave` (disk 3/mem 0 refuse; 3/null refuse; 0/0 allow; missing or unparseable allow; 3/5 allow), `runGuardedSave` with injected `readDisk`/`probeMemory`/`send` (check before save; no `save` sent on refusal).
- 0.3 Extend `pencil-response-classification.test.ts` (`^Unknown tool:` is an error) and `pencil-error-enrichment.test.ts` (replacement hints for the six removed tools).
- 0.4 Write `fixtures/pencil-stub-repl.mjs` (synthesized REPL: `pencil > ` prompts, in-memory document, `--in`/`--out`, `save()` writes JSON, signature whitelist exits 64 on an unknown key, `Unknown tool:` for unknown tools, drains stdin) and `lib/pencil-adapter-roundtrip.mjs` (shared driver).
- 0.5 Write `pencil-adapter-stub-repl.test.ts`: install a temp copy via `copy_adapter.sh` (npm ci failure fails the test), then: `operations` arrives as `input`; open existing file keeps nodes through edit and save; refused save leaves bytes unchanged and sends no `save`; interleaved command cannot land between probe and save; crash respawn reloads `--out` not the template; non-empty file loaded empty gives `isError` plus open-failed state.
- 0.6 Write `pencil-adapter-sentinels.test.ts`: exactly one `formatReplCommand("save"` emission inside `guardedSave`; no string-literal `enqueue(`; `ADAPTER_FILES` set equals the parsed sibling imports (five siblings after this change).
- 0.7 Run all and capture the RED output.

## Phase 1 — pure modules

- 1.1 Create `scripts/pencil-repl-surface.mjs` (header "retire with #11156"): signature table, preamble, `formatReplCommand`, `ReplContractError`, `planSpawn`.
- 1.2 Extend `scripts/pencil-save-gate.mjs` with the four new functions plus `runGuardedSave`.
- 1.3 Add `^Unknown tool:` to `scripts/pencil-response-classify.mjs`.
- 1.4 Add per-tool replacement hints to `scripts/pencil-error-enrichment.mjs`.

## Phase 2 — adapter wiring (`scripts/pencil-mcp-adapter.mjs`)

- 2.1 Dynamic-import the new module inside the existing try/catch; delete the local `formatReplCommand`.
- 2.2 `path.resolve` every incoming path.
- 2.3 `PencilProcess.spawn`: call `planSpawn`; set `outputFile` only after the prompt; child exit before ready rejects the wait with the stderr tail and cleans listener and timer; clear the explicit `inFile` after the first successful spawn.
- 2.4 Add `CommandQueue.runExclusive(fn)`; implement `guardedSave(source)` as one exclusive job (read disk at current `outputFile`, memory probe via `formatReplCommand("batch_get", {})`, `decideSave`, then `save`).
- 2.5 Route the `batch_design` auto-save and the explicit `save` tool through `guardedSave`; delete the `open_document` pre-switch save; run kill-and-respawn inside `runExclusive`.
- 2.6 `open_document`: report the loaded node count; non-empty file loaded empty gives `isError` and the open-failed state (every tool errors until the next successful open).
- 2.7 `get_guidelines` schema `{ category, name, params }`; pass read-only errors through the enrichment.
- 2.8 Refusal text per plan item 5 (stderr and tool result; auto-save variant mentions the unsaved edit).
- 2.9 Separate commit: delete dead `extractNodeIds`, `nodeIdMap`, `postHandler`.

## Phase 3 — pin, copy list, prose

- 3.1 `check_deps.sh`: install `@pencil.dev/cli@0.2.9`; comment that bumping the pin requires `engine-contract-probe.sh`.
- 3.2 `copy_adapter.sh`: add `pencil-repl-surface.mjs`; missing source file is a hard error.
- 3.3 `ux-design-lead.md`: Step 2 items 1-2 (headless `get_guidelines({ category, name })`, tolerate "not supported" from style tools); Step 3 item 2 post-save gate and the open-time threshold aligned to the 96-byte empty document.
- 3.4 `pencil-setup/SKILL.md` Sharp Edges: `input` key, `--in` behavior, sentinel, pin and probe rule.
- 3.5 Amend `knowledge-base/project/learnings/bug-fixes/2026-09-30-pencil-headless-cli-reopen-wipes-pen-file.md` with the `--in` root cause.

## Phase 4 — verification

- 4.1 Create `scripts/engine-contract-probe.sh` (exit 3 without `PENCIL_CLI_KEY`): round trip through the roundtrip driver against the real engine, `--help` signature diff against the table, `I(...)` script and two consecutive `batch_design` calls.
- 4.2 Run the probe with the key from Doppler `soleur/dev`; run Guard 1 #1, #4, #5, #6, #8 and Guard 2 #1 mutations once each and paste the RED output.
- 4.3 `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --check-adapter-drift --auto` reports `OK`.
- 4.4 Run `pencil-adapter-auth-hard-fail.test.sh`, `check-deps-adapter-drift.test.sh`, `components.test.ts`.

## Phase 5 — ship

- 5.1 PR body: `Closes #11143`, `## Changelog` (patch), 96-byte release note, #11156 reference; label `semver:patch`.
