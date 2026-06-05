# Learning: an external CLI's exit code 0 is not proof of success — validate the produced artifact

## Problem

The LikeC4 visualizer's Code-tab Save (PR #4965, Layer 2) spawned `likec4 export json` out-of-process to regenerate the precomputed `model.likec4.json`, keyed success on `child.exitCode === 0`, then committed the result over the previous model. A user reported the diagram going blank and the honest staleness banner disappearing.

Ground truth (reproduced against `likec4@1.50.0`): when the LikeC4 source has unresolved references (e.g. a `model.c4` that uses `container`/`system`/`actor` kinds defined in a `spec.c4` that is absent), `likec4 export json`:

- prints `Line N: Could not resolve reference to ElementKind named 'container'` to **stderr**, AND
- **still exits 0** (`✓ export in 324ms`), writing a degenerate model with `"elements":{}` (~364 bytes vs a healthy ~195 KB).

So the exit code was a lie. The code treated the empty export as a successful render → reported `rerendered:true` (suppressing the honest banner) → committed the empty 364-byte model over the good one (silent data loss for anyone who typo'd their source).

## Solution

Exit-0 from an external tool is necessary but not sufficient. Validate the **artifact**, not just the exit code:

1. **Render to a temp path, never in place.** `mkdtemp(join(tmpdir(),"c4-render-"))` → `likec4 export json -o <temp> .`. The real `model.likec4.json` is only touched on validated success.
2. **Validate the output structurally.** Gate on `Object.keys(model.elements).length === 0` (after confirming `elements` is a non-empty plain object — untrusted CLI output could emit a non-empty string/array that fools a bare `Object.keys`). Gate on the structural invariant, NOT a stderr substring — stderr wording drifts across tool patch versions.
3. **Publish atomically.** `copyFile(temp, sameDirStage)` then `rename(stage, real)` — a crash mid-publish can never truncate the previously-good artifact.
4. **Classify the failure.** `empty_model` (the user's source is broken) vs `io_error` (our mkdtemp/parse/copy failed) are different reasons — only the former should surface a source-blaming diagnostic ("is spec.c4 present?") to the user.
5. **Capture stderr on EVERY exit** (not just non-zero), because the diagnostic lives there even when the tool exits 0.

The data fix for the reporting user was separate (their repo was missing `spec.c4` + `views.c4` — only `model.c4` had been copied in); that was corrected directly in their repo. This code-hardening makes the failure honest and non-destructive for everyone.

## Key Insight

**When you shell out to a tool whose output you then trust/commit/overwrite, the exit code is a claim, not a proof. Validate the produced artifact against a structural invariant before acting on it, render to a temp location and atomically publish so a bad run can't clobber the last good one, and capture stderr on success too — tools emit diagnostics-with-exit-0.** This generalizes beyond likec4: linters, formatters, codegen, and exporters routinely warn-and-exit-0.

## Session Errors

- **Literal U+2028/U+2029 bytes in the `sanitizeForLog` regex.** The Write tool rendered `/[\x00-\x1f\x7f<U+2028><U+2029>]/` with literal separator bytes instead of `  ` escapes — the exact trap `cq-regex-unicode-separators-escape-only` exists for, and the same one hit during the Layer-2 PR. Recovery: byte-level `perl -i -pe 's/\xe2\x80\xa8/\\u2028/g; s/\xe2\x80\xa9/\\u2029/g'`. **Prevention:** when typing a control-char regex via Write/Edit, always type the `\uXXXX` escape; grep the file with `grep -nP '\x{2028}|\x{2029}'` after writing any sanitizer.
- **`c4-render.test.ts` timed out (16s) on 6 tests.** The fix added an `await mkdtemp` before `spawn`, so a test that scheduled the child's `close`/`error` event via a top-level `queueMicrotask` fired the event before `runLikeC4` attached its listeners → the event was lost → the settle-once promise never resolved. Recovery: schedule the emit from INSIDE the spawn mock (`spawnMock.mockImplementation(() => { queueMicrotask(emit); return child; })`) so it runs after listeners attach. **Prevention:** when the SUT awaits something before calling the mocked `spawn`/`fetch`, drive the mock's events from inside the mock implementation, not from a sibling `queueMicrotask`.
- **Wrong assertion `.toContain("unresolved")`** — the diagnostic text uses "Could not resolve" verbatim. One-off typo; fixed. **Prevention:** assert against the literal string the code produces, not a paraphrase.
- **Edit-before-Read on `log-sanitize.ts` / `route.ts`** — harness requires a Read before Edit. One-off; harness-enforced, no rule change needed.

## Tags
category: best-practices
module: web-platform/kb/c4-visualizer
related: [[2026-06-05-never-at-runtime-often-means-never-import-spawn-a-preinstalled-cli]], [[2026-06-05-llm-facing-claim-correction-must-sweep-tool-desc-and-prompt-addendum]]
