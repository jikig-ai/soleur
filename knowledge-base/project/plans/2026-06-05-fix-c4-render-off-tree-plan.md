<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "Harden c4 re-render: render model.likec4.json off-tree (Option A)"
issue: 4976
type: fix
classification: code-hardening
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
date: 2026-06-05
branch: feat-one-shot-4976-c4-render-off-tree
---

# fix: Render `model.likec4.json` off-tree — stop dirtying the tracked working tree on every `.c4` save

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

`renderC4Model` (`apps/web-platform/server/c4-render.ts`) currently publishes the
regenerated `model.likec4.json` **directly onto the tracked working-tree path**
(`<diagramsDir>/model.likec4.json`, via `copyFile`→`rename` at `c4-render.ts:190-191`)
on validated success. `rerenderAndCommit` (`c4-writer.ts:244`) then reads those bytes
back off that same tracked path (`c4-writer.ts:280-305`) and commits them through the
GitHub Contents API, then re-syncs the clone with `syncWorkspace(... op:"manual")`
(`c4-writer.ts:329`).

This tracked-path write is the **source of reconcile dirty-tree churn**:

1. **Success path (every `.c4` save):** the uncommitted working-tree write collides
   with the subsequent `git pull --ff-only` (local file change vs. the incoming
   identical-bytes commit) → `non_fast_forward` dirty-tree abort → the gated
   `reset --hard` self-heal fires **every single time**. After the #4972 de-noise fix
   this is silent-to-error (only a `warn`-level `op:self-heal-reset` per occurrence),
   but it is wasteful churn on the hot post-save path.
2. **Failure path:** any early-return/throw in `rerenderAndCommit` **after** the render
   write but **before** the final resync — the oversized-model early return
   (`c4-writer.ts:300`), a `commit-json` throw (`c4-writer.ts:318`), or a resync failure
   (`c4-writer.ts:340`) — **strands** the uncommitted `model.likec4.json` in the working
   tree. That stranded file then dirties the **next webhook-push reconcile**
   (`syncWorkspace(... op:"push")`) — the original Sentry symptom
   `9ccf1d861b3b4c8595772bd116b931e8` that #4972 only de-noised, not removed.

**Chosen fix — Option A (render off-tree).** `renderC4Model` writes the validated
model only to a process-temp path and **returns the bytes** (plus duration) instead of
copying onto the tracked file. `rerenderAndCommit` commits the returned bytes via the
Contents API exactly as today, then the existing `op:"manual"` resync `git pull --ff-only`
fast-forwards cleanly (working tree is no longer dirty) and brings the committed JSON
down onto disk. The `GET /api/kb/c4/project` route — the **sole on-disk reader** of
`model.likec4.json` — continues to read the committed bytes from the clone, now placed
there by the pull rather than by the render write. **The tracked working-tree file is
never written by the render path again.**

Option A was chosen over Option B (restore-on-every-exit via `git checkout -- <file>`)
because Option B re-introduces git mutations into the hot path and leaves a wider
matrix of exit-paths to cover defensively; Option A removes the dirty-tree source
entirely by construction (the render never touches a tracked path), which is the
structurally simpler and more durable fix. The issue itself flags Option A as "cleaner
but a larger change" — the larger surface is confined to two server modules plus their
two unit tests, all enumerated below, with no client/route/schema/infra change.

This is a robustness/efficiency hardening change. It introduces **no new
infrastructure, no new dependency, no schema change, and no UI surface.**

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| `renderC4Model` writes onto the tracked path at `c4-render.ts:144,191` | Confirmed: `realPath` built at `:144`; `copyFile(tmpOut, stagePath)` `:190` then `rename(stagePath, realPath)` `:191` publish onto the tracked file. | Remove the publish; return bytes instead. |
| `rerenderAndCommit` reads the model off the tracked path then commits | Confirmed: opens `jsonAbsPath` (`workspacePath/knowledge-base/<dir>/model.likec4.json`) with `O_NOFOLLOW`, stat-size-caps, `readFile`, commits (`c4-writer.ts:280-327`). | Replace the on-disk read with the bytes returned by `renderC4Model`; keep the size cap on the returned bytes (no fd/`O_NOFOLLOW` needed once we no longer read a tracked file). |
| GET `/project` reads the committed `model.likec4.json` after pull | Confirmed: `app/api/kb/c4/project/route.ts` opens `<kbRoot>/<dir>/model.likec4.json` (`O_NOFOLLOW`, size-cap) and returns `dump`. **Sole on-disk reader.** | **No change.** Option A keeps the committed bytes landing on disk via the `op:"manual"` resync pull, so the GET reads them exactly as today. |
| `[...path]` route also reads the model | NOT a reader — `app/api/kb/c4/[...path]/route.ts` only references `model.likec4.json` in a comment. | No change; no hidden second reader. |
| Existing `c4-writer-rerender.test.ts` + `kb-route-helpers.test.ts` must stay green | Confirmed both exist; `c4-render.test.ts` also exists and asserts the copyFile/rename publish (lines 116-135, 144-147, 224-225, 260) — **these assertions change under Option A**. | Update `c4-render.test.ts` + `c4-writer-rerender.test.ts` to the new bytes-returning contract; `kb-route-helpers.test.ts` self-heal tests are render-independent and stay verbatim-green. |
| #4972 de-noise PR is the predecessor | Confirmed merged (`3371005b`, "stop error-level Sentry page for a self-healed reconcile ff-only abort"). | Plan builds on it; this issue is the deferred source-hardening follow-up. |

## User-Brand Impact

**If this lands broken, the user experiences:** a stale or blank LikeC4 diagram in the
KB Architecture view after a Code-tab Save (the GET `/project` reads a `model.likec4.json`
that the resync pull failed to update), OR — if the off-tree change is mis-wired — the
*same* dirty-tree self-heal churn this change is meant to remove (no regression beyond
status quo, which is already benign/silent post-#4972).

**If this leaks, the user's data is exposed via:** N/A. The change moves a render
artifact from a tracked path to a process-temp path and returns bytes in-process; it
adds no new persistence, no new network egress, no new log field, and no new
user-controlled input to the spawn (argv stays fixed, cwd stays the constant-derived
diagrams dir). No data-exposure vector is opened or widened.

**Brand-survival threshold:** none.
`threshold: none, reason: the worst realistic failure is a per-user stale-diagram banner that self-heals on the next reconcile — no data leak, no aggregate or cross-tenant impact; the diff touches no auth/migration/API-key/secrets sensitive path.`

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 — render returns bytes, never writes the tracked path.** `renderC4Model` (and its
  inner `renderToValidatedModel`) no longer calls `copyFile`/`rename` onto
  `<diagramsDir>/model.likec4.json`. On validated success it returns
  `{ ok: true, durationMs, json: <validated-model-string> }`. Verify in
  `c4-render.test.ts`: assert the success result carries the model JSON and assert
  `copyFile`/`rename` are **not** called on the real path on any path (success, empty,
  io_error, timeout). Grep gate: `grep -nE 'copyFile|rename' apps/web-platform/server/c4-render.ts`
  returns no call that targets `realPath`/`stagePath` (the same-dir staging machinery for
  the tracked file is removed).
- **AC2 — writer commits the returned bytes, never re-reads the tracked file.**
  `rerenderAndCommit` consumes `render.json` from the `renderC4Model` result and commits it
  via `githubApiPost(... model.likec4.json ...)`. The `open(jsonAbsPath, O_NOFOLLOW)` +
  `handle.stat()` + `handle.readFile()` block (`c4-writer.ts:287-305`) is removed; the
  4 MB cap is enforced on `Buffer.byteLength(render.json, "utf8")` before the commit.
  Grep gate: `grep -nE 'O_NOFOLLOW|jsonAbsPath|handle\.stat' apps/web-platform/server/c4-writer.ts`
  returns nothing.
- **AC3 — oversized regenerated model still NOT committed.** When the returned bytes exceed
  `MAX_C4_MODEL_BYTES` (4 MB), `rerenderAndCommit` returns `{ rerendered: false }`, makes no
  JSON commit, and calls `reportSilentFallback` with `op:"commit-json"` — preserving the
  semantics of existing test AC2c. (`c4-writer-rerender.test.ts` AC2c stays green after the
  fixture is adapted to size the *returned bytes* rather than a mocked `handle.stat`.)
- **AC4 — no dirty-tree self-heal on the success path (the core fix).** A `.c4` save that
  re-renders successfully leaves the working tree clean *before* the JSON commit's resync,
  so the `op:"manual"` `git pull --ff-only` fast-forwards without a `non_fast_forward`
  abort. Verified at the unit boundary: in `c4-writer-rerender.test.ts` the second
  `syncWorkspace` call (after the JSON commit) is invoked with `op:"manual"` and the test
  no longer needs to mock any tracked-file write between render and resync. (The end-to-end
  "no `reset --hard`" assertion is covered by the structural change — no tracked write
  exists to dirty the tree — and documented in the PR body.)
- **AC5 — failure path strands nothing.** On any `rerenderAndCommit` early-return/throw
  after render (oversized model, commit-json throw, resync failure), the working tree is
  unchanged because the render produced only a process-temp artifact (cleaned in its
  `finally`). Verified: `c4-writer-rerender.test.ts` AC2/AC2b/AC2c/AC2d/AC2e assert
  `rerendered:false` + `reportSilentFallback` called, and assert **no** tracked-path write
  occurs on those branches (no `copyFile`/`rename`/fs write mocked or expected).
- **AC6 — empty/invalid render still never commits over the good model.** An `empty_model`
  or `io_error` render result returns `{ ok:false, reason }` with **no `json`** field, so
  `rerenderAndCommit` never commits and the previously-good committed model is untouched
  (preserves #4966/#4967 validate-before-clobber). `c4-render.test.ts` empty/non-object/
  non-JSON cases assert the result has `ok:false` and no `json` payload.
- **AC7 — GET `/project` unchanged and still serves fresh bytes.** No edit to
  `app/api/kb/c4/project/route.ts`. After a successful re-render + resync, the committed
  `model.likec4.json` is on disk via the pull, so the client `reload()` reads the fresh
  `dump`. (Asserted by inspection + the existing route's behavior; the route's on-disk read
  contract is unchanged.)
- **AC8 — existing self-heal tests stay green verbatim.** `kb-route-helpers.test.ts`
  `describe("syncWorkspace")` self-heal tests (non-FF classify, dirty-tree self-heal,
  de-noise no-error-mirror, un-pushed-commit gate) require **no edit** and pass unchanged —
  the render path is not in their scope.
- **AC9 — full suite green.** `./node_modules/.bin/vitest run test/c4-render.test.ts
  test/c4-writer-rerender.test.ts test/kb-route-helpers.test.ts` (from
  `apps/web-platform/`) passes, and `npx tsc --noEmit` is clean (the
  `renderC4Model` return-type widening is honored at every call site — currently the single
  caller `rerenderAndCommit`).

### Post-merge (operator)

- None. This is a pure code change against an already-provisioned surface; the
  `web-platform-release.yml` pipeline restarts the container on merge to main that touches
  `apps/web-platform/**`, so the merge IS the deploy. No migration, no secret/Doppler
  mutation, no Terraform, no vendor-dashboard step.
  - **Automation note:** the dogfood verification that a real `.c4` Save re-renders without
    a self-heal is tracked separately by #4966 (already-open dogfood issue); this plan does
    not re-file it.

## Implementation Phases

> Single atomic PR. Phases are ordered by contract-dependency (the producer
> `renderC4Model` return-type change lands before the consumer `rerenderAndCommit` change)
> so no phase leaves dead code. TDD per the constitution: write/adapt the failing test,
> then make it green.

### Phase 0 — Preconditions (verify-before-code)

- [ ] Confirm `renderC4Model`'s only caller is `rerenderAndCommit`:
      `git grep -n 'renderC4Model' apps/web-platform` → expect `c4-render.ts` (def +
      export), `c4-writer.ts` (import + call), `c4-writer-rerender.test.ts` (mock),
      `c4-render.test.ts` (import). No other production caller → the return-type widening
      is contained.
- [ ] Confirm GET `/project` is the sole on-disk reader of `model.likec4.json`:
      `git grep -nE 'C4_MODEL_JSON|model\.likec4\.json' apps/web-platform --include='*.ts'`
      and verify only `project/route.ts` performs a `readFile`/`open` of it (writer's read
      is being removed; `[...path]` route only comments on it).
- [ ] Confirm test runner + paths: `apps/web-platform/vitest.config.ts` `include`
      collects `test/**/*.test.ts` (node project) — all three target tests qualify. Runner
      is vitest (`package.json scripts.test: "vitest"`); invoke via
      `./node_modules/.bin/vitest run <paths>`.

### Phase 1 — `c4-render.ts`: return bytes, drop the tracked-path publish (producer)

- [ ] Widen `RenderResult` success variant to
      `{ ok: true; durationMs: number; json: string }`.
- [ ] In `renderToValidatedModel`: on validated success, return
      `{ ok: true, durationMs: run.durationMs, json: <the raw temp-read string> }`. Bind the
      `utf8` read at `c4-render.ts:156` into a local `const raw = await readFile(tmpOut,"utf8")`,
      `JSON.parse(raw)` for validation, and return `raw` as `json` so the committed bytes
      are byte-identical to the validated artifact — do not re-`JSON.stringify` (avoids
      key-order/whitespace drift).
- [ ] **Delete** the same-dir staging machinery used only for the tracked-file publish:
      `realPath` (`:144`), `stagePath` (`:148`), the `copyFile`+`rename` publish (`:190-191`),
      and the trailing `rm(stagePath, …)` cleanup (`:204`). Keep the temp-dir `mkdtemp` +
      `rm(dir, …)` lifecycle (still needed for the spawn's `-o` target and cleanup).
- [ ] Remove now-unused imports (`copyFile`, `rename`, `basename` if no longer referenced)
      from the `node:fs/promises` / `node:path` import lines — let `tsc`/lint confirm.
- [ ] Update the module header comment block (lines 12-20, 112-118) so the
      "copy it onto the real `model.likec4.json`" / "where the GET reads it … and the caller
      commits it" prose reflects the new "return the validated bytes; the writer commits
      them and the resync pull lands them on disk" contract.

### Phase 2 — `c4-render.test.ts`: assert the new contract (producer test)

- [ ] Replace the copyFile/rename publish assertions (success test lines 116-135) with:
      success result is `ok:true` and `res.json` equals the staged `VALID_MODEL`; assert
      `fsMock.copyFile`/`fsMock.rename` are **not** called.
- [ ] Drop the `STAGE`/`REAL_JSON` fixtures and the `copyFile`/`rename` entries from
      `fsMock` (no longer part of the success path). Keep `mkdtemp`/`readFile`/`rm`.
- [ ] In every failure case (empty-elements, non-object elements, non-JSON, non-zero exit,
      spawn_error, timeout): assert the result has no `json` field (so the writer can never
      commit on a failed render) and that no publish occurred (already asserted; tighten to
      the new shape).
- [ ] The spawn/argv/env scope assertions (lines 83-114) are unchanged — the `-o` temp
      target and scoped env are unaffected by Option A.

### Phase 3 — `c4-writer.ts`: commit the returned bytes (consumer)

- [ ] In `rerenderAndCommit`, after `const render = await renderC4Model(workspacePath)`
      and the `!render.ok` early-return, use `render.json` directly: cap-check
      `Buffer.byteLength(render.json, "utf8") > MAX_C4_MODEL_BYTES` → `reportSilentFallback`
      (`op:"commit-json"`, `extra:{ userId, relativePath, size }`,
      `message:"c4 re-render: regenerated model too large to commit"`) + return
      `{ rerendered:false }` (preserves AC2c semantics; `size` is now the byte length of the
      returned string).
- [ ] **Delete** the `open(jsonAbsPath, O_NOFOLLOW)` + `handle.stat()` size-cap +
      `handle.readFile()` + `handle.close()` block (`c4-writer.ts:280-305`) and the
      `jsonAbsPath` construction. The TOCTOU/`O_NOFOLLOW` hardening existed because we were
      re-reading a tracked file that a planted symlink could swap; once we commit the
      in-process returned bytes there is no on-disk re-read to harden. Remove the now-unused
      `open` / `constants as fsConstants` / `join` imports if they become unreferenced
      (let `tsc`/lint confirm; `join` may still be used elsewhere — check).
- [ ] Keep the rest of the commit flow byte-for-byte: blob-sha resolve
      (`githubApiGet`), `githubApiPost(... jsonFilePath ...)`, and the `op:"manual"`
      `syncWorkspace` resync + its `!resync.ok` `reportSilentFallback(op:"resync")`. The
      success `logger.info({ event:"c4_rerender", … durationMs: render.durationMs })` still
      reads `render.durationMs` (now alongside `render.json`).
- [ ] Update the `rerenderAndCommit` doc comment (`c4-writer.ts:233-243`) so the
      "renderC4Model validated to a temp file and left the real JSON untouched" /
      "Read the regenerated JSON off the diagrams dir" prose reflects the new
      "renderC4Model returns the validated bytes; we commit them and the resync pull lands
      the committed bytes on the clone" contract.

### Phase 4 — `c4-writer-rerender.test.ts`: adapt the consumer mock (consumer test)

- [ ] Change the `renderC4Model` mock default to resolve
      `{ ok:true, durationMs:12, json:'{"_stage":"layouted"}' }` (carry the JSON the writer
      now commits) instead of `{ ok:true, durationMs:12 }`.
- [ ] **Remove** the `node:fs/promises` `open` mock + the `stat`/`readFile`/`close`
      FileHandle fakes (lines 9-12, 27, 65-74) — the writer no longer opens a file. The
      AC2c oversized case (lines 152-163) now sizes the **mocked `render.json`** above 4 MB
      (e.g. `json: "x".repeat(8 * 1024 * 1024)`) rather than mocking `stat.size`.
- [ ] AC1/AC2/AC2b/AC2d/AC2e/AC3/OUT_OF_SCOPE/first-sync-failure tests: keep their
      assertions on commit ordering, `rerendered`, `rerenderDiagnostic`, and
      `reportSilentFallback`. Verify the JSON-commit assertion
      (`endsWith("/diagrams/model.likec4.json")`) still holds — the commit still happens; only
      the bytes' provenance changed (mock result vs. mocked file read).
- [ ] Add an assertion to AC1 (or a new sibling test) that the writer commits the bytes
      returned by `renderC4Model` (the `githubApiPost` JSON-commit `content` base64-decodes
      to `render.json`), pinning the new producer→consumer contract.

### Phase 5 — Verify

- [ ] `./node_modules/.bin/vitest run test/c4-render.test.ts test/c4-writer-rerender.test.ts
      test/kb-route-helpers.test.ts` (from `apps/web-platform/`) → all green; confirm
      `kb-route-helpers.test.ts` self-heal tests passed **without edit**.
- [ ] `npx tsc --noEmit` (web-platform) → clean; the widened `RenderResult` is honored at
      the sole call site.
- [ ] Run the broader server suite if cheap (`./node_modules/.bin/vitest run test/` scoped
      to changed-area files) to catch any incidental importer.

## Observability

```yaml
liveness_signal:
  what: successful c4 re-render emits logger.info { event:"c4_rerender", path, durationMs }
  cadence: per .c4 Code-tab/Concierge save (user-triggered, not periodic)
  alert_target: none (success breadcrumb; not an alerting signal)
  configured_in: apps/web-platform/server/c4-writer.ts (rerenderAndCommit success branch)
error_reporting:
  destination: Sentry via reportSilentFallback (feature:"c4-rerender") — existing helper, unchanged by this plan
  fail_loud: true (warn+ mirrors to Sentry per observability.ts; render/commit/resync failures already routed)
failure_modes:
  - mode: render returns ok:false (empty_model / io_error / timeout / non_zero_exit / spawn_error)
    detection: rerenderAndCommit !render.ok branch reports via reportSilentFallback op:"render"
    alert_route: Sentry feature:c4-rerender op:render (unchanged)
  - mode: returned model exceeds 4 MB cap
    detection: Buffer.byteLength(render.json) over MAX_C4_MODEL_BYTES reports via reportSilentFallback op:"commit-json"
    alert_route: Sentry feature:c4-rerender op:commit-json (unchanged contract, new size source)
  - mode: JSON commit or resync fails
    detection: githubApiPost throw caught op:"commit-json"; not resync.ok reports op:"resync"
    alert_route: Sentry feature:c4-rerender (unchanged)
  - mode: REMOVED failure mode — stranded dirty model.likec4.json dirtying the next reconcile
    detection: n/a (eliminated by construction — render no longer writes a tracked path)
    alert_route: was Sentry 9ccf1d86… (workspace-sync self-heal); this plan removes the source
logs:
  where: pino to Better Stack drain (server logger); Sentry for warn+ mirrors
  retention: per existing Better Stack / Sentry retention (unchanged)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-render.test.ts test/c4-writer-rerender.test.ts"
  expected_output: "all tests pass; c4-render success result carries json and never calls copyFile/rename on the real path; writer commits the returned bytes"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a server-side code-hardening change to a
single feature's render/commit path. No product/UX surface (no new or modified user-facing
page or component — the GET `/project` route and client components are untouched), no
legal/compliance surface (no new data processing, no new persistence, no new log field),
no security surface widened (argv stays fixed, cwd stays constant-derived, no new
user-controlled input; the removed `O_NOFOLLOW` read is removed *because the on-disk
re-read it hardened no longer exists*), no infra surface (no new server/service/secret/
cron/DNS — pure `apps/web-platform/src` + `server/` + `test/` edit).

### UI-surface override check

`## Files to Edit` contains no path matching the UI-surface term list / glob superset
(`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`) — the only `app/` reference
(`project/route.ts`) is a **read-only no-change** and is not even edited. Product gate
does not fire.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` matched none of
`c4-render.ts`, `c4-writer.ts`, `project/route.ts`.

## Infrastructure (IaC)

Not applicable. This plan introduces no new infrastructure (no server, systemd service,
cron, vendor account, DNS record, TLS cert, secret, firewall rule, or monitoring webhook).
It edits only `apps/web-platform/{server,test}` files against an already-provisioned
surface. Phase 2.8 detection scan found no SSH/systemctl/secret-mutation/terraform/
vendor-dashboard wording in the plan's implementation phases (the `<!-- iac-routing-ack -->`
at the top records this review).

## Research Insights (deepen-plan)

**Deepened on:** 2026-06-05 · gates 4.6/4.7/4.8/4.9 passed · verify-the-negative +
precedent-diff passes run against the `origin/main` working tree.

### Verify-the-negative (every load-bearing negative claim probed against code)

| Plan claim | Probe | Result |
| --- | --- | --- |
| "render never writes the tracked path" (after fix) | `grep -nE 'writeFile\|copyFile\|rename' c4-render.ts` | **Confirms.** The *only* tracked-path write is `copyFile`/`rename` at `c4-render.ts:190-191` (all other hits are comments/imports). Removing it makes the claim true — there is no second write site to miss (`hr-write-boundary-sentinel-sweep-all-write-sites`). |
| "GET `/project` is the sole on-disk reader of `model.likec4.json`" | `grep -rn C4_MODEL_JSON apps/web-platform --include='*.ts' \| grep -v test` + per-file read scan | **Confirms.** Only `project/route.ts:66` does `path.join(dirAbs, C4_MODEL_JSON)` → `fs.open`. `c4-writer.ts:284` is the read-back being *removed*; `[...path]/route.ts` references it only in a comment. No hidden second reader. |
| "renderC4Model's only production caller is rerenderAndCommit" | `grep -rn renderC4Model apps/web-platform --include='*.ts*' \| grep -v test` | **Confirms.** Sole call site `c4-writer.ts:252`. The return-type widening (`hr-type-widening-cross-consumer-grep`) touches exactly one consumer + the `c4-render.test.ts` import. `tsc --noEmit` (AC9) is the backstop. |

### Precedent-diff (Phase 4.4) — `pdf-linearize.ts` is the cited model template

`c4-render.ts`'s own header (`:7`, `:67`, `:136`) says it is "modeled on
`server/pdf-linearize.ts`." Grepping the precedent:

```
apps/web-platform/server/pdf-linearize.ts:14:  | { ok: true; buffer: Buffer }
apps/web-platform/server/pdf-linearize.ts:65:export async function linearizePdf(input: Buffer): Promise<LinearizeResult>
apps/web-platform/server/pdf-linearize.ts:92:      return { ok: true, buffer };   // returns bytes — does NOT write output in place
```

`pdf-linearize.ts` **returns `{ ok: true; buffer: Buffer }`** — it never publishes its
output onto a tracked/destination path; the caller owns persistence. The current
in-place-write `c4-render.ts` is the *deviation* from its own stated precedent (it gained
the tracked-path publish in #4965/#4967 for the validate-before-clobber work). **Option A
restores `c4-render.ts` to the precedent shape** (return the validated bytes; caller owns
the commit/persist), which is the codebase-canonical form for an out-of-process spawn
helper. This is a precedent *confirmation*, not a novel pattern — it strengthens the design
choice. (One shape difference: `pdf` returns a `Buffer`; the c4 model is committed as a
UTF-8 base64 string and validated as parsed JSON, so returning the raw `utf8` **string** —
not a re-encoded buffer — is correct here, per the Sharp Edge on byte-identical bytes.)

### Type-widening discipline (`hr-type-widening-cross-consumer-grep`)

The `RenderResult` success variant gains a required `json: string` field. The cross-consumer
grep (above) confirms the single consumer is `rerenderAndCommit`, which is rewritten in the
same PR (Phase 3) to read `render.json`. No other site destructures a `renderC4Model`
success result. `tsc --noEmit` is the mechanical gate that the widening is honored
everywhere (AC9).

## Files to Edit

- `apps/web-platform/server/c4-render.ts` — widen `RenderResult` success to carry `json`;
  remove the tracked-path publish (`copyFile`/`rename`/`realPath`/`stagePath`); update
  header prose.
- `apps/web-platform/server/c4-writer.ts` — consume `render.json`; remove the
  `open`/`O_NOFOLLOW`/`stat`/`readFile` re-read block; cap-check on returned byte length;
  update `rerenderAndCommit` doc comment.
- `apps/web-platform/test/c4-render.test.ts` — assert the bytes-returning contract; drop
  copyFile/rename publish assertions + fixtures.
- `apps/web-platform/test/c4-writer-rerender.test.ts` — mock `renderC4Model` to return
  `json`; remove the FileHandle (`open`/`stat`/`readFile`/`close`) mocks; resize the
  oversized case to the returned bytes; add a returned-bytes-committed assertion.

## Files to Create

- None.

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| **Option B — restore-on-every-exit** (`git checkout -- model.likec4.json` on every failure exit; stage/commit-or-discard before the pull on success) | Re-introduces git mutations into the hot save path and leaves a multi-branch exit matrix to cover defensively; the issue itself notes Option A is cleaner. Option A removes the dirty-tree source by construction rather than papering over each exit. |
| **Leave as-is (rely on #4972 de-noise)** | #4972 only silenced the *operator page*; the wasteful per-save `reset --hard` churn and the failure-path stranding remain. This issue exists precisely to harden the source. |
| **Re-serialize the model with `JSON.stringify` before returning** | Risks key-order/whitespace drift from the validated artifact (and a needless re-encode); return the raw validated `utf8` string so committed bytes are byte-identical to what was validated. |

## Risks & Mitigations

- **Risk: the resync pull does not land the committed bytes on disk, so GET `/project`
  serves stale/empty.** Mitigation: the `op:"manual"` `git pull --ff-only` already runs
  after the JSON commit (`c4-writer.ts:329`) and, with no dirty tree, fast-forwards
  cleanly — bringing the committed `model.likec4.json` down. This is the *same* resync that
  runs today; Option A makes it succeed cleanly (no abort) rather than triggering a
  `reset --hard`. The honest-stale banner (#4963 Layer 1) covers the transient window
  between commit and pull, exactly as today.
- **Risk: removing `O_NOFOLLOW` re-introduces a symlink/TOCTOU race.** Mitigation: the
  `O_NOFOLLOW`+fd-stat hardening (CodeQL `js/file-system-race`) was added because the writer
  **re-read a tracked file** that a planted symlink at that path could swap. Option A
  removes that re-read entirely — the bytes are produced in-process and committed without
  any on-disk round-trip — so there is no file-read to harden. The **GET `/project`** route
  keeps its own `O_NOFOLLOW`+fd-stat hardening (unchanged), which is the path that still
  reads the on-disk file.
- **Risk: type-widening breaks an unseen caller of `renderC4Model`.** Mitigation: Phase 0
  grep confirms the sole production caller is `rerenderAndCommit`; `tsc --noEmit` (AC9) is
  the backstop.
- **Risk: byte-size cap regression — the in-memory string size differs from the on-disk
  file size the old `stat` measured.** Mitigation: `Buffer.byteLength(render.json, "utf8")`
  measures the exact bytes that will be base64-committed — strictly more accurate than the
  old `handle.stat().size` (which measured the on-disk copy of the same bytes). AC3 + the
  resized AC2c fixture pin this.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's
  section is filled with concrete artifact + vector + `threshold: none` reason.)
- The render module is bundled into the WS/custom server via the Concierge
  `edit_c4_diagram` import chain (no `import "server-only"`, esbuild can't resolve the
  guard). Keep `c4-render.ts` free of any import that drags `next/headers` or the heavy
  `likec4` toolchain into the bundle — Option A adds no imports, only removes them.
- Return the **raw validated `utf8` string**, not a re-`JSON.stringify` of the parsed model —
  re-encoding risks key-order/whitespace drift from the artifact `likec4` actually produced
  and that was validated.
- The `op:"manual"` resync is load-bearing for getting the committed bytes onto the clone
  for the GET to read. Do not drop it when removing the on-disk read — it is the mechanism
  by which the committed JSON reaches disk under Option A.

## Test Scenarios

1. `.c4` save, valid model → `renderC4Model` returns `{ok:true, json}`; writer commits
   those bytes; second resync is `op:"manual"`; `rerendered:true`; **no** `copyFile`/`rename`
   on the tracked path anywhere.
2. `.c4` save, empty/invalid model (#4966) → `renderC4Model` returns `{ok:false,
   reason:"empty_model"}` with no `json`; writer makes no JSON commit; previously-good model
   untouched; `rerenderDiagnostic` surfaced.
3. `.c4` save, oversized returned model (>4 MB) → writer returns `{rerendered:false}`, no
   JSON commit, `reportSilentFallback op:"commit-json"`.
4. `.c4` save, JSON commit throws / resync fails after a good render → `{rerendered:false}`,
   reported; working tree unchanged (nothing stranded — render produced only a temp
   artifact).
5. `.md` save → no render spawned; unchanged.
6. `syncWorkspace` self-heal suite (`kb-route-helpers.test.ts`) → green **without edit**.
