---
title: "fix(kb): treat an empty/invalid LikeC4 export as a failed render (honest staleness + no clobber)"
type: fix
date: 2026-06-05
lane: single-domain
app: web-platform
semver: minor
brand_survival_threshold: aggregate pattern
---

# fix(kb): treat an empty/invalid LikeC4 export as a failed render (honest staleness + no clobber)

## Enhancement Summary

**Deepened on:** 2026-06-05
**Hard gates passed:** 4.6 User-Brand Impact (threshold `aggregate pattern`, valid), 4.7 Observability (5/5 fields, no-ssh discoverability test), 4.8 PAT-shaped variable sweep (no match), 4.9 UI-wireframe (no Files-to-Create UI surface; `c4-shared.tsx` is an existing-component save-string edit → ADVISORY/auto-accept in pipeline, no `.pen` required).

### Key Improvements
1. **Precedent-diff against `pdf-linearize.ts:70-104`** (the cited temp-file sibling) — adopted `mkdtemp().catch(()=>null)` failure handling, the `rm(...).catch(()=>{})` non-rejecting cleanup form, and documented the intentional concurrency-gate-placement divergence (keep the coarser `renderC4Model` gate; do not refactor).
2. **Runtime verification** — `node:fs/promises` exports `mkdtemp`/`readFile`/`copyFile`/`rm`; vitest globs match all three test paths; `bun test` is blocked (use `./node_modules/.bin/vitest run`); `likec4@1.50.0` pin + drift-guard test confirm the empty-`elements` shape is stable.
3. **Verify-the-negative** — confirmed the load-bearing claim "an invalid render never opens the good file for write" (the only `model.likec4.json` write in `c4-render.ts` is the spawn `-o` arg, which moves to the temp dir; `copyFile`-on-success becomes the only real-path write, gated behind validation).

### New Considerations Discovered
- `mkdtemp` failure is a distinct path that must resolve to a render failure (folded into `empty_model`, no new reason).
- The existing `c4-render.test.ts` argv assertion (`-o model.likec4.json`) must change to a path-shape matcher after the temp `-o` swap — flagged in Sharp Edges + AC.

## Overview

Follow-up hardening to merged PRs **#4963** (Layer 1: honest staleness banner) and **#4965** (Layer 2: re-render after a Code-tab Save). Both are verified merged (premise check below).

`likec4 export json` **exits 0 even when the source has unresolved references.** It prints `Line N: Could not resolve reference to ElementKind named '<kind>'` (or `... Tag named '<tag>'`) to **stderr**, returns exit code **0**, and writes an **empty-elements model** (`"elements":{}`, ~364 bytes) instead of the ~195 KB good model (40 elements / 42 views). Reproduced against `likec4@1.50.0` this session — treat as ground truth, do **not** re-investigate.

`apps/web-platform/server/c4-render.ts` keys render success **only on `code === 0`** (`c4-render.ts:138-142`), and `apps/web-platform/server/c4-writer.ts` `rerenderAndCommit` reads + commits the in-place `model.likec4.json` with **no element-count validation** (`c4-writer.ts:215-268`). This produces two real bugs:

1. **Suppressed honesty banner.** An empty/invalid export is treated as a successful render → `rerenderAndCommit` returns `rerendered:true` → the Layer-1 honest staleness banner is suppressed. A user reported the banner disappearing.
2. **Silent data loss (the load-bearing bug).** `rerenderAndCommit` **commits the empty `model.likec4.json`**, overwriting a previously-good ~195 KB rendered model with a ~364-byte empty one. Any user who introduces a typo in `model.c4` silently destroys their served diagram.

This PR makes an empty/invalid render **fail honestly** instead of silently committing an empty model, and surfaces the `likec4` diagnostic to the client so the save result explains *why* the diagram didn't update.

## Problem Statement / Motivation

The current contract conflates "the process exited 0" with "a valid model was produced." For `likec4 export json` those are different facts. The fix is to:

- **Validate the produced JSON** (`Object.keys(model.elements ?? {}).length >= 1`) before treating the render as a success — the primary, deterministic signal.
- **Render to a TEMP output path, not in place**, and copy to the real `model.likec4.json` only on success — so an invalid render can **never clobber** the served/committed good model. This is the structural fix for bug #2: the good file is never opened for write until we already hold a validated replacement.
- **Always capture stderr** (currently only captured on non-zero exit) so the `Could not resolve` lines are available as the surfaced diagnostic.
- **Surface a concise, sanitized diagnostic** through `WriteC4Result` → the PUT route response → the `c4-shared.tsx` save handler, so the save message explains the failure instead of a silent stale banner.

## Premise Validation

- **PR #4963** — `gh pr view 4963`: `state: MERGED`, `mergedAt: 2026-06-05T10:29:08Z`, title `fix(kb): make LikeC4 Code-tab Save honest about diagram re-render (Layer 1)`. ✅ holds.
- **PR #4965** — `gh pr view 4965`: `state: MERGED`, `mergedAt: 2026-06-05T11:32:40Z`, title `feat(kb): re-render the LikeC4 diagram after a Code-tab Save (Layer 2)`. ✅ holds.
- **Cited source files all exist on the branch and match the described behavior** (read this session): `c4-render.ts:138-152` (success-on-`code===0`, stderr captured only on non-zero exit), `c4-writer.ts:195-298` (`rerenderAndCommit` reads + commits in place, no element validation), `route.ts` (PUT returns `{commitSha, rerendered}` only), `c4-shared.tsx:261-289` (`save` sets `saveMsg` from `rerendered` boolean).
- **OUT OF SCOPE (confirmed):** the reporting user's blank diagram (missing `spec.c4` + `views.c4`) was a separate root cause, already fixed in their repo. No repo-scaffolding / self-healing in this PR.

## Research Reconciliation — Spec vs. Codebase

| Claim (arguments) | Reality (codebase) | Plan response |
|---|---|---|
| `renderC4Model`/`runLikeC4` keys success only on `code === 0` | Confirmed `c4-render.ts:139` `if (code === 0) settle({ ok: true, durationMs })` | Replace with: validate the temp JSON's `elements` before settling `ok:true`. |
| stderr captured only on non-zero exit | Confirmed — `stderrChunks` is concatenated only inside the `code !== 0` branch (`c4-render.ts:143-151`); on `code === 0` stderr is discarded | Concatenate stderr once, before the exit-code branch, so it is available for the empty-model diagnostic on an exit-0 render. |
| Render writes `model.likec4.json` in place (cwd = diagrams dir) | Confirmed `c4-render.ts:127-131` `spawn(LIKEC4_BIN, ["export","json","-o", C4_MODEL_JSON, "."], { cwd: diagramsDir })` | Change `-o` to an absolute temp path; copy to the real `model.likec4.json` only after validation passes. |
| `rerenderAndCommit` reads the in-place JSON and commits it | Confirmed `c4-writer.ts:221-268` (`open` the diagrams-dir JSON, stat-cap, read, commit) | Keep the read/commit path; it now reads the model that `renderC4Model` already validated + copied into place. The validation gate moves into `c4-render.ts`. |
| `sanitizeForLog` reused | `c4-render.ts:75-77` has a **local private copy** (replaces with `?`, slices 512); `lib/log-sanitize.ts` has the shared one (replaces with `""`, default 500). Mirrors the deliberate `pdf-linearize.ts` private-copy pattern. | Reuse the **local** `c4-render.ts` sanitizer for the in-module stderr (keeps the existing `?`-substitution behavior); when threading the detail through `WriteC4Result`, re-cap to a short bound. Do NOT fold the copies (the `lib/log-sanitize.ts` doc comment explicitly forbids it). |
| Temp path: `os.tmpdir()` + a "constant-derived filename" | `server/pdf-linearize.ts:70` precedent uses `mkdtemp(join(tmpdir(), "pdf-linearize-"))` (a per-call **random unique dir**) + `rm(dir, { recursive })` in `finally`. | **Decision:** adopt the `mkdtemp` precedent rather than a fixed constant filename. A fixed filename in `tmpdir()` collides under the concurrency gate (`POOL_SIZE` default 2 — two saves render at once) and across replicas sharing a tmpfs. `mkdtemp` is scope-safe (process-temp dir, not user-controlled), collision-proof, and matches the sibling module. The argument's "constant-derived filename" intent (never user-controlled) is satisfied — the *output filename inside the temp dir* is the `C4_MODEL_JSON` constant; only the parent dir is randomized. |
| No existing PUT route test | Confirmed — `test/` has `c4-writer-rerender.test.ts`, `c4-diagram-path-scope.test.ts`, `c4-concierge-tools.test.ts`, but no test exercising `app/api/kb/c4/[...path]/route.ts` PUT directly. | The route change (threading `rerenderDiagnostic` into the JSON response) is a one-line passthrough; cover it via the writer + c4-shared tests rather than scaffolding a new route harness. Add a focused route-response assertion only if cheap (see AC). |

## Research Insights (deepen pass — 2026-06-05)

Verified this session against the branch + installed runtime; treat as ground truth for `/work`.

**Precedent diff vs `pdf-linearize.ts:70-104` (the cited temp-file sibling):**

- `mkdtemp` is wrapped `.catch(() => null)` and a `null` dir short-circuits to an `ok:false` reason (`io_error` there). **Apply the same shape:** `const tmpDir = await mkdtemp(join(tmpdir(),"c4-render-")).catch(() => null); if (!tmpDir) return { ok:false, reason:"empty_model", detail:"mkdtemp failed" };` — a temp-dir-creation failure means no model can be produced, so it is a render failure (reuse `empty_model`; do not add a reason for it).
- Cleanup is `await rm(dir, { recursive:true, force:true }).catch(() => {})` in the outer `finally` — the trailing `.catch(() => {})` is what makes the cleanup unable to reject the resolved result (directly satisfies this plan's Sharp Edge). **Copy this form verbatim.**
- **Concurrency-gate placement divergence (intentional, preserve):** pdf-linearize keeps `mkdtemp` OUTSIDE `acquire()` and gates only the spawn+IO triplet. This plan keeps `acquire`/`release` in `renderC4Model` wrapping the whole `runLikeC4` (the coarser gate that exists today). That is acceptable — c4-render's gate is per-render and `release()` still fires in `renderC4Model`'s existing `try/finally` regardless of the new async paths. Do NOT refactor the gate in this PR (scope creep); just ensure every new `await` in `runLikeC4` is inside the `try` whose `finally` calls `release()`.

**Node runtime (verified):** `node:fs/promises` exports `mkdtemp`, `readFile`, `copyFile`, `rm` (all `function`). Use `copyFile(tmpJson, realJson)` for the copy-on-success step (atomic-enough for this single-writer-per-render path; the writer then re-reads with `O_NOFOLLOW`).

**Test runner (verified):** `apps/web-platform/vitest.config.ts` collects `test/**/*.test.ts` (node env) and `test/**/*.test.tsx` (happy-dom). All three planned test files already match. Invoke via `./node_modules/.bin/vitest run` — `apps/web-platform/bunfig.toml [test]` blocks `bun test` discovery (defense-in-depth, #1469).

**likec4 pin (verified):** `apps/web-platform/Dockerfile:57` pins `npm install -g likec4@1.50.0`; `test/c4-likec4-version-pin.test.ts` is a drift guard asserting CLI/`@likec4/core`/`@likec4/diagram` parity. The empty-`elements` shape is stable for this pin — the element-count gate (`Object.keys(model.elements ?? {}).length === 0`) is the correct primary signal and is robust to stderr-wording changes across patch versions. Dockerfile:56 also notes `export json` needs no display/dot-on-PATH (no new env requirement).

**Verify-the-negative (passed):** the plan's claim "an invalid render NEVER opens the good file for write" holds — today the ONLY write to `model.likec4.json` from `c4-render.ts` is the in-place `-o C4_MODEL_JSON` spawn arg (`c4-render.ts:129`). After the change `-o` targets the temp dir, and `copyFile`-on-success becomes the only write to the real path, which runs strictly after the element-count validation. No other write site exists in the module.

## Proposed Solution

### `c4-render.ts` — validate to temp, copy on success

`RenderReason` union gains `"empty_model"`. `RenderResult` `ok:false` already carries an optional `detail`. New flow in `runLikeC4`:

1. Compute an absolute temp output path via `mkdtemp(join(tmpdir(), "c4-render-"))` → `join(tmpDir, C4_MODEL_JSON)`. Pass it to `-o`. `likec4` still reads sources from `.` (cwd = diagrams dir); it writes `-o` anywhere.
2. **Always** accumulate stderr (move `Buffer.concat(stderrChunks)` out of the non-zero-exit branch).
3. On `child.on("close")`:
   - `spawn_error` / `timeout` paths unchanged (still settle `ok:false`).
   - `code !== 0` → `non_zero_exit` (unchanged, with sanitized stderr detail).
   - `code === 0` → **read + parse the temp file**, then check `Object.keys(model.elements ?? {}).length === 0`:
     - empty → settle `{ ok:false, reason:"empty_model", detail:<sanitized stderr, capped> }`.
     - non-empty → **copy the temp file to the real `model.likec4.json`** in the diagrams dir, then settle `{ ok:true, durationMs }`.
   - If reading/parsing the temp file throws (truncated / non-JSON write) → settle `{ ok:false, reason:"empty_model", detail:"<parse error> | <sanitized stderr>" }` (parse failure is morally the same "no usable model" outcome; reuse `empty_model` rather than adding a fourth reason — keep the union tight).
4. **`finally`: `rm(tmpDir, { recursive:true, force:true })`** — clean up regardless of outcome. Because the copy-to-real step is the *only* write to `model.likec4.json` and it happens after validation, an invalid render **never opens the good file for write**.

The temp dir + `mkdtemp` + `rm` mirror `pdf-linearize.ts:70-102` verbatim in shape. The element-emptiness gate is the **primary** signal (deterministic); the stderr `Could not resolve` lines are the **diagnostic** to surface (not the gate).

> Note: `runLikeC4` becomes `async` (it now awaits `mkdtemp`/`readFile`/`copyFile`/`rm`). Keep the spawn lifecycle inside a `Promise` as today; wrap the temp-dir creation + post-close validation in the surrounding `async` function. The concurrency gate (`acquire`/`release` in `renderC4Model`) already wraps the call in `try/finally`, so `release()` still fires on the new async paths.

### `c4-writer.ts` — fail closed, surface diagnostic

`WriteC4Result` `ok:true` variant gains an optional `rerenderDiagnostic?: string`. `rerenderAndCommit` is widened to return `{ rerendered: boolean; diagnostic?: string }` (or kept returning `boolean` with the diagnostic threaded via a small struct — implementer's choice; the writer composes the final `WriteC4Result`). On `!render.ok`:

- Do **not** commit JSON, do **not** leave an empty JSON in the clone (the new temp-copy design means the clone's `model.likec4.json` was never touched on failure — nothing to clean up). Return `rerendered:false` **and** the sanitized `render.detail` as `diagnostic`.
- Preserve the failure-isolated contract: the `.c4` commit + first sync already happened and are **never** rolled back. `reportSilentFallback` mirroring stays (already present, `c4-writer.ts:203-211`).
- Compose a concise human diagnostic from `render.detail` — e.g. strip to the first `Could not resolve reference to ElementKind named '<X>'` and present as `Re-render failed: unresolved reference '<X>'`. Cap length (≤ ~200 chars). Re-apply `sanitizeForLog` (the **shared** `lib/log-sanitize.ts` one, since this string crosses into the HTTP response, not just a log line) before returning. Fall back to a generic `Re-render failed (<reason>)` when no `Could not resolve` line is present (timeout / spawn_error / oversized).

The existing JSON read/commit/resync path (`c4-writer.ts:221-282`) is unchanged in shape — it now reads the model `renderC4Model` already validated + copied into place. (The in-writer `O_NOFOLLOW` + size-cap read stays; it is still load-bearing against a symlink planted at the real JSON path between copy and read.)

### `route.ts` — pass the diagnostic through

`app/api/kb/c4/[...path]/route.ts` success response becomes `{ commitSha, rerendered, ...(rerenderDiagnostic ? { rerenderDiagnostic } : {}) }`. One-line spread; no new status codes.

### `c4-shared.tsx` — explain the failure in the save copy

In `C4CodePanel.save`, read `j?.rerenderDiagnostic`. When `rerendered === false` and a diagnostic is present, set `saveMsg` to `Saved — ${diagnostic}` (e.g. `Saved — Re-render failed: unresolved reference 'container'.`) instead of the generic `Saved — diagram will update after re-render.`. When `rerendered === true`, copy is unchanged (`Saved — diagram updated.`). The `onSaved(rerendered)` callback and the `C4Diagnostics` stale banner are **unchanged** — the diagnostic lives in the transient `saveMsg`, not the banner (keeps blast radius to `c4-shared.tsx`; no change to `c4-diagram.tsx` / `c4-workspace.tsx` consumers).

## Technical Considerations

- **Security / scope.** No new exposed artifact. The render still operates on the constant-derived `diagramsDir` (`workspacePath` + `C4_DIAGRAMS_DIR`). The temp output path is `mkdtemp(tmpdir())`-derived — process-temp, never user-controlled. Argv stays fixed except `-o <abs-tmp>` (an absolute path the server computed, not from the request). The copy-to-real target is the same constant `model.likec4.json` the writer already commits.
- **TOCTOU.** The writer's `O_NOFOLLOW` + fd-stat read of the real JSON is retained. The copy-into-place in `c4-render.ts` overwrites `model.likec4.json`; the subsequent writer read re-validates size + symlink. (The copy itself targets the constant path; an attacker who could plant a symlink there could already affect the in-place write that exists today — net surface is not widened.)
- **Concurrency.** `mkdtemp` gives each render its own dir, so concurrent saves (`POOL_SIZE` default 2) cannot race on the temp file. The copy-to-real of `model.likec4.json` is still a shared target, but that is already the case today and is gated per-save by the writer's commit/sync sequencing.
- **`runLikeC4` async-ification.** Becomes `async`; ensure `clearTimeout(timer)` still fires on every settle path (it is inside `settle`, unchanged) and that the temp-dir `rm` runs in a `finally` that cannot itself reject the result.
- **stderr always captured.** Moving the `Buffer.concat` before the exit-code branch is the minimal change; cap at the existing 512 before sanitize.
- **NFR.** No new infra, no new dependency (`likec4` stays a Dockerfile global, not a `package.json` dep — lockfile parity preserved per `c4-constants.ts` doc). Latency: one extra `readFile`+`copyFile` on the temp model (~hundreds of KB) per `.c4` save — negligible vs. the spawn + two GitHub commits + two syncs already on the path.

## User-Brand Impact

- **If this lands broken, the user experiences:** their previously-good rendered C4 diagram (`model.likec4.json`, ~195 KB) silently overwritten with an empty model after a single typo in `model.c4` — the diagram goes blank with no warning (the exact failure this PR fixes; a regression here re-opens it).
- **If this leaks, the user's [workflow] is exposed via:** the surfaced diagnostic string in the save response — mitigated by re-applying `sanitizeForLog` and capping length, so only a sanitized first-line `likec4` resolution error (which echoes the user's own `model.c4` token, e.g. a kind/tag name) reaches the client. No secrets, no absolute paths (only `relativePath` + reason cross into telemetry today, unchanged).
- **Brand-survival threshold:** `aggregate pattern` — an invalid render silently overwriting a good diagram while reporting success is the failure *class* (any typo, any tenant), not a single-user incident. No per-PR CPO sign-off required; `user-impact-reviewer` runs at review time per the standard review gate.

## Observability

```yaml
liveness_signal:
  what: "Sentry breadcrumb via reportSilentFallback (feature='c4-rerender', op='render') on every failed re-render; structured pino log event='c4_rerender' on success"
  cadence: "per .c4 Code-tab/Concierge save"
  alert_target: "Sentry web-platform issue (grouped by feature/op tags)"
  configured_in: "apps/web-platform/server/c4-writer.ts:203-211 (rerenderAndCommit failure mirror)"

error_reporting:
  destination: "Sentry web-platform via reportSilentFallback (server/observability) + SENTRY_DSN"
  fail_loud: "save response carries rerendered:false + rerenderDiagnostic; the c4-shared.tsx save copy shows 'Saved — Re-render failed: …' and the C4Diagnostics stale banner stays up"

failure_modes:
  - mode: "empty_model — likec4 exits 0 with elements:{} (unresolved reference)"
    detection: "Object.keys(model.elements ?? {}).length === 0 gate in c4-render.ts; reportSilentFallback with reason='empty_model'"
    alert_route: "Sentry (operator) + the user's own save-message diagnostic (self-serve fix: the message names the unresolved token)"
  - mode: "non_zero_exit / spawn_error / timeout (pre-existing reasons)"
    detection: "existing reason-typed RenderResult + reportSilentFallback"
    alert_route: "Sentry web-platform"
  - mode: "temp-file parse/IO failure (truncated CLI write)"
    detection: "readFile/JSON.parse throw in c4-render.ts → settle empty_model with the parse error in detail"
    alert_route: "Sentry web-platform"

logs:
  where: "Docker container stdout (pino) → operator `docker logs`; Sentry for failure breadcrumbs"
  retention: "Sentry default retention; container logs ephemeral per deploy"

discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-render.test.ts test/c4-writer-rerender.test.ts test/c4-shared.test.tsx"
  expected_output: "all suites pass — incl. empty-model → rerendered:false + no json commit + diagnostic surfaced, and valid export → rerendered:true + commit"
```

## Acceptance Criteria

### Render validation (`c4-render.ts`)
- [x] `RenderReason` union includes `"empty_model"`.
- [x] `likec4` is invoked with `-o <absolute temp path>` (a `mkdtemp(join(tmpdir(),"c4-render-"))`-derived path), NOT `model.likec4.json` in the diagrams dir. cwd stays the scope-guarded diagrams dir; the rest of argv is unchanged (`export json … .`).
- [x] On exit 0 with `Object.keys(model.elements ?? {}).length === 0` → returns `{ ok:false, reason:"empty_model", detail:<sanitized, capped stderr> }` and does **not** copy to the real `model.likec4.json`.
- [x] On exit 0 with ≥1 element → copies the temp file to the real `model.likec4.json` and returns `{ ok:true, durationMs }`.
- [x] stderr is captured on **exit-0-with-errors** (not only on non-zero exit) and appears in the `empty_model` detail.
- [x] The temp dir is removed in a `finally` on every path (success, empty, non-zero, spawn_error, timeout, parse failure), via `rm(dir, { recursive:true, force:true }).catch(() => {})` (the trailing `.catch` so cleanup cannot reject the result — mirrors `pdf-linearize.ts:103`).
- [x] A truncated/non-JSON temp write → `empty_model` (parse error folded into detail), not an unhandled throw.
- [x] `mkdtemp` failure → `{ ok:false, reason:"empty_model", detail:"mkdtemp failed" }` (mirrors `pdf-linearize.ts:70-72`, reusing `empty_model` rather than adding a reason).

### Fail-closed writer (`c4-writer.ts`)
- [x] On render failure (`empty_model` or any `ok:false`), `rerenderAndCommit` does NOT commit `model.likec4.json` and returns `rerendered:false`.
- [x] The `.c4` source commit + first sync are never rolled back on a re-render failure (existing failure-isolated contract preserved).
- [x] `WriteC4Result` (`ok:true`) carries an optional `rerenderDiagnostic` string, populated from `render.detail` on failure, re-sanitized via shared `sanitizeForLog` and capped (≤ ~200 chars). Absent on success.
- [x] `reportSilentFallback` still mirrors the failure to Sentry (unchanged).

### Diagnostic surfacing (route + client)
- [x] PUT `app/api/kb/c4/[...path]/route.ts` success JSON includes `rerenderDiagnostic` when present (spread only when set).
- [x] `c4-shared.tsx` `C4CodePanel.save`: on `rerendered:false` with a diagnostic, the save message reads `Saved — <diagnostic>` (e.g. `Saved — Re-render failed: unresolved reference 'container'.`); on `rerendered:true` the copy is unchanged (`Saved — diagram updated.`); the `onSaved(rerendered)` contract and the stale banner are unchanged.

### Tests
- [x] `c4-render.test.ts`: empty-elements export (exit 0) → `ok:false reason:"empty_model"`; valid export (≥1 element) → `ok:true` + temp copied to real path; stderr captured on exit-0-with-errors; temp dir cleaned up. Existing argv / scope / timeout / spawn_error assertions still pass (argv updated to expect the temp `-o`).
- [x] `c4-writer-rerender.test.ts`: empty/unresolved render → `rerendered:false` + NO json commit + `reportSilentFallback` called + `rerenderDiagnostic` surfaced; valid render → `rerendered:true` + json commit (unchanged AC1 behavior); `.md` save still skips render (AC3).
- [x] `c4-shared.test.tsx`: failed re-render with a diagnostic → save copy shows the diagnostic text; successful re-render copy unchanged.
- [x] Full app suite green: `cd apps/web-platform && ./node_modules/.bin/vitest run`.

## Test Scenarios

### Regression (proves the fix)
- Given a `model.c4` with an unresolved `container` kind, when the user Saves, then `likec4` exits 0 with `elements:{}`, the render is reported `ok:false reason:"empty_model"`, the good `model.likec4.json` is **not** overwritten, `rerendered:false` is returned, and the save copy reads `Saved — Re-render failed: unresolved reference 'container'.`
- Given a previously-good ~195 KB `model.likec4.json` on the clone, when an empty render occurs, then the on-disk + committed JSON is byte-for-byte unchanged (no clobber).

### Acceptance (RED targets)
- Given a valid `model.c4`, when Saved, then the temp model validates (≥1 element), is copied to `model.likec4.json`, committed, re-synced, and `rerendered:true` with no diagnostic.
- Given `likec4` writes a truncated temp file, when validated, then `JSON.parse` failure yields `empty_model` (no unhandled throw) and the temp dir is removed.

### Edge cases
- Given two concurrent `.c4` saves (`POOL_SIZE`=2), when both render, then each uses its own `mkdtemp` dir (no temp-file collision).
- Given a non-zero exit (real parse error), when rendered, then `non_zero_exit` is returned (unchanged) and the diagnostic falls back to `Re-render failed (non_zero_exit)`.
- Given a timeout, when the budget is exceeded, then `timeout` is returned (unchanged) and the diagnostic falls back to a generic re-render-failed message.

## Files to Edit

- `apps/web-platform/server/c4-render.ts` — temp `-o` path via `mkdtemp`; always-capture stderr; `empty_model` reason + element-count gate; copy-on-success; `rm` in `finally`; `async` runLikeC4.
- `apps/web-platform/server/c4-writer.ts` — `rerenderAndCommit` fail-closed already; add `rerenderDiagnostic` to `WriteC4Result` (`ok:true`) and compose/sanitize/cap it from `render.detail`.
- `apps/web-platform/app/api/kb/c4/[...path]/route.ts` — spread `rerenderDiagnostic` into the success JSON when present.
- `apps/web-platform/components/kb/c4-shared.tsx` — read `j.rerenderDiagnostic` in `C4CodePanel.save`; use it in `saveMsg` on `rerendered:false`.
- `apps/web-platform/test/c4-render.test.ts` — new empty-model + temp-copy + exit-0-stderr cases; update argv expectation to the temp `-o`; mock `node:fs/promises` (`mkdtemp`/`readFile`/`copyFile`/`rm`) alongside the existing `spawn` mock.
- `apps/web-platform/test/c4-writer-rerender.test.ts` — empty-render → `rerendered:false` + no json commit + diagnostic; valid → unchanged.
- `apps/web-platform/test/c4-shared.test.tsx` — failed-render-with-diagnostic save-copy assertion.

## Files to Create

- None.

## Open Code-Review Overlap

None — no open `code-review`-labeled issues touch these files (the C4 render/write surface is fresh from #4963/#4965, merged the same day).

## Dependencies & Risks

- **`runLikeC4` async-ification** is the highest-touch change: the existing fake-timer SIGKILL test and the spawn-lifecycle EventEmitter mock must still drive the `close`/`error`/timeout paths. Risk: a temp-file read mocked incorrectly makes the valid-export test hang. Mitigation: the writer-rerender test already mocks `node:fs/promises`; mirror that mock shape in `c4-render.test.ts` for `mkdtemp`/`readFile`/`copyFile`/`rm`.
- **Test runner is vitest** (`apps/web-platform/vitest.config.ts`), invoked via `./node_modules/.bin/vitest run` — NOT `bun test` (`apps/web-platform/bunfig.toml` ignores all paths). Test file paths stay under `test/**/*.test.ts(x)` (the config's include globs).
- **Do NOT fold the two `sanitizeForLog` copies** — `lib/log-sanitize.ts`'s doc comment explicitly forbids merging the `pdf-linearize.ts`-style private copy. `c4-render.ts` keeps its local `?`-substitution copy for in-module stderr; the writer uses the shared `lib` one for the client-facing diagnostic.
- **`mkdtemp` vs fixed filename** — see Research Reconciliation; the `mkdtemp` precedent is the safe + collision-proof choice and matches `pdf-linearize.ts`.

## Domain Review

**Domains relevant:** Product (mechanical UI-surface check)

### Product/UX Gate

**Tier:** none
**Decision:** n/a — the only client file (`c4-shared.tsx`) is an **existing** component; the change replaces one transient `saveMsg` string with a more honest one. No new page, no new component file, no new interactive surface (no match for `components/**/*.tsx` *creation*, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create — Files to Create is empty). The mechanical UI-surface override does not fire (no UI-surface file is *created*; an edit to an existing save-message string is ADVISORY at most, and in pipeline context auto-accepts). Backend render-validation hardening with a copy tweak.

#### Findings

No cross-domain implications beyond the user-facing save-message honesty already captured in User-Brand Impact. No legal/data/infra surface touched.

## Infrastructure (IaC)

None — pure code change against an already-provisioned surface (`apps/web-platform/server/**`, `app/api/**`, `components/**`, `test/**`). No new server, secret, vendor, cron, or persistent runtime process. `likec4` remains a Dockerfile global (unchanged). Phase 2.8 skips.

## GDPR / Compliance Gate

Skipped — no regulated-data surface (no schema, migration, auth flow, `.sql`, or new processing activity). The surfaced diagnostic is the user's own `model.c4` token (a diagram kind/tag name), sanitized + capped; not personal data. No (a)–(d) expansion trigger fires.

## References & Research

- Bug locations: `apps/web-platform/server/c4-render.ts:75-77,127-152`; `apps/web-platform/server/c4-writer.ts:57-59,195-298`.
- Route: `apps/web-platform/app/api/kb/c4/[...path]/route.ts:50-60`.
- Client save handler: `apps/web-platform/components/kb/c4-shared.tsx:165-208,261-289`.
- Temp-file precedent: `apps/web-platform/server/pdf-linearize.ts:2,70-102` (`mkdtemp`/`writeFile`/`readFile`/`rm` in `finally`, concurrency-gated).
- Constants + scope guard: `apps/web-platform/lib/c4-constants.ts`.
- Shared sanitizer: `apps/web-platform/lib/log-sanitize.ts` (do-not-fold note).
- GET reader (element/dump shape): `apps/web-platform/app/api/kb/c4/project/route.ts:70-110`.
- Related PRs: #4963 (Layer 1), #4965 (Layer 2).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled: threshold `aggregate pattern`.)
- `runLikeC4` becomes async — every `settle` path must still `clearTimeout(timer)` (it does, inside `settle`) and the temp-dir `rm` must be in a `finally` that cannot reject the resolved result.
- The element-emptiness gate is on `elements`, the **primary** signal. The stderr `Could not resolve` lines are the **diagnostic**, NOT the gate — a future `likec4` version could change the stderr wording without changing the empty-`elements` outcome, so do not gate on stderr substring.
- Update the `c4-render.test.ts` argv expectation: it currently asserts `args).toEqual(["export","json","-o","model.likec4.json","."])`; after the change the `-o` value is the absolute temp path, so assert the shape (`args[3]` is an absolute path ending in `model.likec4.json`, or use `expect.arrayContaining`/a path matcher) rather than the literal constant.
