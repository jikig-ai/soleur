---
title: "bug(pencil-mcp): headless adapter batch_design is a silent no-op; open_document does not load existing file"
type: fix
date: 2026-10-26
slug: pencil-mcp-headless-adapter-batch-design-noop
branch: feat-one-shot-11143-pencil-mcp-headless-adapter
issue: 11143
closes: 11143
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: headless Pencil MCP adapter silently drops design operations and opens existing files empty

## Enhancement Summary

**Deepened on:** 2026-10-26
**Method:** the research the deepen pass would fan out was already done live before drafting (authenticated runs of both CLIs, an SDK spike), so this pass ran the halt gates and the verification sweeps instead of a 40-agent fan-out. A six-seat plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO devex) had already reviewed the finished plan; its findings are folded in (decision-challenges.md R9-R12).

### Key improvements from this pass

1. The `discoverability_test` was a bun suite, which Phase 4.7 rejects as suite-shaped for a block authored in this run. Replaced with a one-line `node -e` probe that prints the sentinel's verdict (`false`), well inside Check 10's 15-second cap.
2. `decideSave` now has a stated return shape (`{ allow, reason }`) so that probe and the unit tests share one contract.
3. Verification sweeps confirmed the plan's negative claims against the code: `nodeIdMap` and `extractNodeIds` are written but never read (safe to delete); the adapter has exactly four `"save()"` literals (batch_design auto-save, `set_variables` auto-save, pre-switch save, explicit `save`), matching the Guard 1 assembly; the adapter has four sibling imports today, five after this change.

### Gates run (all pass)

Phase 4.6 user-brand impact (threshold `single-user incident`), 4.7 observability (5 fields, no SSH, allowlisted verb, matchable literal), 4.8 no PAT-shaped variables, 4.9 not a UI surface, 4.11 `lint-guard-contract.py` (3 guards), 4.12 one unfenced `## Scope Check`, no block marker. Cited issues #3274, #4859, #2630, #11143, #11156 resolved live; cited rule IDs exist; labels `type/chore`, `domain/engineering`, `priority/p3-low` exist.

Spec lacks a valid `lane:` (one-shot path, no brainstorm or spec) — defaulted to cross-domain (fail-closed).

## Overview

The headless Pencil MCP adapter (`plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`) bridges
Claude Code to the `@pencil.dev/cli` 0.2.9 interactive shell. Two defects make it unusable for authoring the
`.pen` wireframe that `wg-ui-feature-requires-pen-wireframe` demands for every UI feature:

1. **Design operations are accepted and silently do nothing.** Measured live on 2026-10-26: the engine's
   `batch_design` takes `{ input }`, the adapter sends `{ operations }`, the engine drops the unknown key and
   prints `OK`. Nothing in the engine is broken.
2. **Opening an existing `.pen` starts an empty document.** `open_document({ filePath })` spawns
   `pencil interactive --out <filePath>` and passes `--in` only when the caller supplied `inputPath`. The next
   save writes a 96-byte empty document over the existing file. This is the root cause of the closed #3274 /
   #4859 collapse class, which was until now only mitigated after the fact by the PostToolUse hook
   `pencil-collapse-guard.sh`.

The plan fixes both, puts every save behind one guarded chokepoint so an empty document can never replace a
non-empty file, makes engine-surface drift loud, pins the CLI, and records the migration decision with a tracked
follow-up (#11156).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (measured 2026-10-26, authenticated, scratch dir) | Plan response |
|---|---|---|
| "find why the headless engine ignores operations" | The engine does not ignore operations: `batch_design` is `{ input }` in 0.2.9 and the adapter's existing `formatReplCommand` sends `{ operations }`. `batch_design({ input: "f=Insert(document,{...})" })` creates the node, `batch_get` shows it, `save()` persists it. | Phase 1: one command formatter maps `operations` to `input`; Guard 2 makes future key/tool drift a thrown error. |
| "Driving `pencil interactive` directly gives the same result" | True only with the `operations` key (the reporter's call). | Covered by the key fix. |
| "a file passed with `--in` also loads as empty" | `--in X --out X` loads and saves correctly (489-byte document, same-path in/out). The reporter's input had already been overwritten by earlier no-op saves. A nonexistent `--in` is a hard CLI error (`Input file not found`) after which the adapter waits 30 s. | Phase 1: `--in` is decided at every spawn; spawn fails fast when the child exits. |
| "`open_document` with only `filePath` ... does not load the existing file" | Confirmed from source and behavior. | Phase 1 `planSpawn`. |
| "the adapter saves the previous document before switching" | Confirmed. Every mutating tool already auto-saves, so the pre-switch save can only persist state the guard would refuse. | Phase 2: delete it. |
| "`@pen.dev/cli` 0.3.13 has no `batch_design`, `batch_get`, `get_editor_state`" | Confirmed, and wider: it also lacks `get_screenshot`, `export_nodes`, `snapshot_layout`, `get_variables`. Its REPL is `execute`, `get_app_state`, `get_style`, `read_skill`, `browser`; screenshot, export and layout checks live inside the `execute` DSL. | R1: stay on 0.2.9, pin it, follow-up #11156. |
| (not in the issue) | 0.2.9 also drifted elsewhere: short aliases `I`/`U`/`C`... are undefined (`ReferenceError`); the insert response is now `Name=id` so `extractNodeIds` matches nothing; `find_empty_space_on_canvas`, `get_style_guide`, `get_style_guide_tags`, `search_all_unique_properties`, `replace_all_matching_properties`, `set_variables` return `Unknown tool:`, which the classifier treats as success and then auto-saves; `get_guidelines` changed from `{ topic }` to `{ category, name, params }` (guide names verified: Code, Design System, Landing Page, Mobile App, Slides, Table, Tailwind, Web App). | Phases 1-2. |

## Research Insights

### Premise validation

#11143 is open with no closing PR. Every cited adapter file, `copy_adapter.sh`, `check_deps.sh` and the hooks exist on
`origin/main`. The cited rule and the cited class (#3274 / #4859, both closed) are real. ADR-corpus grep for the
mechanism and subsystem keywords (pencil, headless adapter) found no ADR deciding or rejecting any mechanism here.
The issue's claims about the new CLI were re-measured, not trusted. Nothing was stale.

### Property List

- **P1.** A design operation sent through the adapter is executed by the engine, or the caller gets an error. Never `OK` with no effect.
- **P2.** Opening an existing `.pen` loads its content and reports what loaded.
- **P3.** No save replaces a non-empty `.pen` with an empty document, at any write site.
- **P4.** A tool or parameter the engine does not know is an error, not a success, and triggers no save.
- **P5.** A drifted CLI surface is detected before it silently breaks authoring.
- **P6.** An installed adapter copy receives the fix.

### Cut List

| Proposed mechanism | Property | Disposition |
|---|---|---|
| Strict MCP schemas (`registerTool` + `.strict()`) | P1, P4 | Cut. Spiked on SDK 1.32.1: legacy `server.tool()` strips unknown keys, `.strict()` rejects them, but Desktop-grammar callers pass extra keys such as `filePath`. The engine-side surface table (Guard 2) closes the real drift. Revisit in #11156. |
| Translation shims for removed tools, `topic` mapping | P4 | Cut (R2): loud errors cover P4; shims die with #11156. |
| Six new hint-only tool handlers and a hint map | P4 | Cut on review (DHH, simplicity): `Unknown tool:` classified as an error already blocks the save; the hint text goes into the existing `pencil-error-enrichment.mjs`. Same observable behavior as R2, less code. |
| "No node mapping means error" heuristic | P1 | Cut: per-op success markers unverified; the engine already errors loudly on a bad op (measured). |
| Porting `extractNodeIds` / `nodeIdMap` | none | Delete as dead code, in its own commit. |
| Pre-switch save in `open_document` | P3 | Delete (review): redundant, every mutation auto-saves. This satisfies the issue's "skip the pre-switch save when the document is empty" strictly. |
| Separate `pencil-open-plan.mjs` | P2 | Merged into `pencil-repl-surface.mjs`: one new module, one `ADAPTER_FILES` entry. |
| Second new learning file | none | Cut: the amended 2026-09-30 learning carries the root cause. |
| Source scan of the registered tool set; "at least 8 imports" floor | P5, P6 | Cut (brittle, wrong count): `formatReplCommand` already throws on an unknown tool. |
| Startup `pencil --version` check; scheduled probe | P5 | Cut: the pin only guards fresh installs and the probe is run by hand on every pin bump (stated in `check_deps.sh` and `SKILL.md`). Revisit in #11156. |
| Migrating to `@pen.dev/cli` | P5 | Deferred, #11156 (R1). |

### Existing-mechanism check (authority grepped: `.claude/hooks/`, `.claude/settings.json`)

`pencil-open-guard.sh` (PreToolUse) denies untracked `.pen` at `open_document` (including a not-yet-existing path);
`pencil-collapse-guard.sh` (PostToolUse) restores a tracked `.pen` collapsed to the empty shape. Neither prevents the
write, neither fires on the explicit `save` tool or on auto-saves, and **both live only in this repo's
`.claude/settings.json`: a customer machine has neither**, so the sentinel is the only layer there. Both stay unchanged.

### Technical rulings (full record: `knowledge-base/project/specs/feat-one-shot-11143-pencil-mcp-headless-adapter/decision-challenges.md`)

| Item | Ruling (CTO agent, 2026-10-26) |
|---|---|
| R1 migration | Fix on 0.2.9 now, pin, follow-up #11156 (Post-MVP / Later); flips to migrate-now if 0.2.9 auth stops working or npm removes it. |
| R2 compat breadth | Translate only `batch_design` `operations` to `input`; removed tools return `isError` plus a hint and trigger no save; `get_guidelines` passes `{ category, name, params }` through; one minimal `ux-design-lead.md` edit. |
| R3 aliases | Per-call `var I=Insert,U=Update,C=Copy,R=Replace,M=Move,D=Delete,G=Generate;` preamble (two consecutive calls verified). |
| R4 sentinel | One `guardedSave()` chokepoint for every write site including the explicit `save` tool; refuse when disk has `children.length > 0` and memory is empty or undeterminable. |
| R5 tests | Pure-module tests + stub-REPL integration over real MCP stdio + key-gated live contract probe. |

Plan-review refinements inside those rulings (record: decision-challenges.md R9-R12): the pre-switch save is deleted
rather than guarded, so R4's four sites become two (`batch_design` auto-save, explicit `save`); R2's hints ride the
existing enrichment module.

### Institutional learnings applied

- `knowledge-base/project/learnings/bug-fixes/2026-09-30-pencil-headless-cli-reopen-wipes-pen-file.md` — the headless reopen wipe is this plan's root cause (no `--in`); amend it.
- `knowledge-base/project/learnings/2026-04-10-pencil-mcp-open-document-clears-untracked-files.md` — same class; verify node count after open (adopted).
- `knowledge-base/project/learnings/integration-issues/mcp-adapter-pure-function-extraction-testability-20260329.md` — keep logic in zero-import modules.
- `knowledge-base/project/learnings/2026-09-25-gh-stub-must-mirror-real-cli-flags.md` and `2026-09-21-my-escrow-suite-stubbed-the-one-tool-that-would-have-refused-it.md` — the stub whitelists real signatures and refuses anything else; a green stub proves nothing about the real binary, hence the live probe.
- `knowledge-base/project/learnings/test-failures/2026-09-30-stub-drain-fidelity-and-endpoint-keyed-sweeps.md` — the stub drains stdin.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — Guard Contract matrices.
- `knowledge-base/project/learnings/2026-05-05-pencil-copy-adapter-missing-package-json.md` — a file missing from `ADAPTER_FILES` breaks fresh installs.
- `knowledge-base/project/learnings/2026-09-25-pencil-headless-cli-install-on-global-libvips-hosts.md` — the libvips install workaround is tracked separately, not here.

Value-proposition measurement: no cost or performance saving is claimed. Functional overlap: internal bug fix in a vendored adapter, no new capability to match against registries.

## Open Code-Review Overlap

None. Open `code-review` issues queried for `pencil-setup`, `pencil-mcp-adapter`, `pencil-save-gate`, `pencil-response-classify`: no matches.

## Proposed Solution

All under `plugins/soleur/skills/pencil-setup/scripts/`, with logic in zero-import `.mjs` modules so bun tests need no MCP SDK.

1. **`pencil-repl-surface.mjs` (new, pure; header: "retire with #11156").** The 0.2.9 signature table (tool to allowed keys, including `save` with none), the `batch_design` preamble, `formatReplCommand(tool, params)` (this **moves and replaces** the adapter's existing local function), and `planSpawn`. `formatReplCommand` throws `ReplContractError` for an unknown tool or key and for empty `operations`; `batch_design` becomes `batch_design({ input: <preamble>\n<operations> })`. `planSpawn({ outFile, initialInFile, probe })`: an explicit initial `inFile` must exist (fail fast); otherwise `--in` equals `--out` when that file exists and is non-empty. The explicit `inFile` is used for the **first** spawn only; every respawn after a crash uses `--in <outFile>` so a template `inputPath` can never overwrite saved edits.
2. **`pencil-save-gate.mjs` (extend).** `diskTopLevelCount(text)` (null for missing, empty or unparseable: nothing recoverable to protect, allow), `memoryTopLevelCount(batchGetText)` (null when undeterminable), `decideSave({ diskCount, memoryCount })` (returns `{ allow: boolean, reason: string }`), `refusalMessage(...)`, and a dependency-injected `runGuardedSave({ readDisk, probeMemory, send })` so "check happens before save, no save sent on refusal" is unit-testable without the SDK. `shouldSkipSave` stays.
3. **`pencil-response-classify.mjs` and `pencil-error-enrichment.mjs` (extend).** `^Unknown tool:` classifies as an error; the enrichment appends the replacement hint per removed tool (`SetVariables(...)` inside `batch_design`; `FindEmptySpace(...)` likewise; `get_guidelines({ category: "style" })` for the style tools; no headless equivalent for the two bulk-property tools). Read-only handlers pass errors through the enrichment.
4. **Adapter wiring.** Paths are absolutized (`path.resolve`) on entry. `spawn()` sets `outputFile` only after the prompt is reached; a child that exits first rejects the pending wait with the stderr tail and cleans the listener and timer. A failed `open_document` leaves the adapter in an explicit "open failed" state that errors every tool until the next successful open (no silent respawn against the bad path). `guardedSave(source)` is the **only** place that emits `save`, and it runs as **one exclusive queue job** (disk read, memory probe, decide, save) via a new `CommandQueue.runExclusive(fn)`; `open_document`'s kill-and-respawn runs inside the same exclusive section, so no queued command or restart can land between probe and save. Callers: the `batch_design` auto-save and the explicit `save` tool. The pre-switch save is deleted. `open_document` reports the loaded top-level node count and fails (and enters the open-failed state) if a non-empty file loaded empty. Dead `extractNodeIds` / `nodeIdMap` / `postHandler` go in a separate commit. `get_guidelines` takes `{ category, name, params }`.
5. **Refusal text** (CPO condition): names the file, says it was not modified, says the likely cause, gives one next step (call `open_document` on the file, which now loads it; to start over use a new file path), and says not to delete or recreate the file to bypass the check. The auto-save variant also says the edit is applied in memory but not persisted and will be lost on the next `open_document`. It goes to the tool result (`isError: true`) and stderr.
6. **Pin and ship.** `check_deps.sh` installs `@pencil.dev/cli@0.2.9` with a comment that bumping the pin requires running the live probe; `copy_adapter.sh` lists `pencil-repl-surface.mjs` and turns "missing source file" from a warning into a hard error (a silently partial install fails at import).
7. **Prose and docs.** `ux-design-lead.md`: Step 2 items 1-2 use `get_guidelines({ category, name })` for the headless adapter and say "if a style tool returns not supported, continue with brand tokens" (Desktop users keep the style tools); Step 3 item 2's post-save gate becomes "node count reported by `open_document`, or size above the empty-document size", and the open-time collapse threshold (`<= 64 bytes`) is aligned to the measured 96-byte empty document (use `<= 128`). `pencil-setup/SKILL.md` Sharp Edges gain the new constraints. The 2026-09-30 learning is amended with the root cause.

## Technical Considerations

- **Architecture impact:** none outside the adapter. The adapter keeps the Desktop-MCP tool names; the REPL surface is an explicit, tested table.
- **Security:** the env allowlist is unchanged. `batch_design` input is model-authored script run by the engine's own JS sandbox (unchanged trust boundary); the preamble adds identifier aliases only. Paths come from MCP arguments as today; the probe only checks existence and size.
- **Write path:** the engine writes only on `save()` (measured: nothing is written on `exit()` or SIGTERM); `export_nodes` and `get_screenshot` write PNGs only. After this plan the REPL `save` command is emitted from one place.
- **Known limit:** the sentinel catches empty-over-non-empty, not partial truncation or a lower node count. The loaded-empty open failure and the exclusive section close the realistic partial-load path.
- **NFR impact:** one extra `batch_get()` round trip per save when the target already holds nodes; top-level read only.

## Architecture Decision (ADR/C4) gate

Skipped on purpose: this fixes an adapter against its engine and defers the re-platform decision to #11156. No ADR mentions Pencil, so no recorded architecture is contradicted, and no C4 element exists for the Pencil CLI or adapter (developer-machine tooling).

## Implementation Phases

### Phase 0 — failing tests first (`cq-write-failing-tests-before`)

Write every test in "Files to Create" before the modules exist; confirm RED and capture the output.

### Phase 1 — pure modules

`pencil-repl-surface.mjs`, the save-gate additions, the classifier line, the enrichment hints.

### Phase 2 — adapter wiring

As Proposed Solution item 4; dead-code deletion in a separate commit.

### Phase 3 — pin, copy list, prose

`check_deps.sh` pin and comment, `copy_adapter.sh` list and hard error, `ux-design-lead.md`, `SKILL.md`, learning amendment.

### Phase 4 — verification against the real engine

Run `engine-contract-probe.sh` with the key from Doppler `soleur/dev` (round trip, signature diff). Refresh the local installed copy with `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --check-adapter-drift --auto` and confirm `OK`.

### Phase 5 — close the loop

PR body: `Closes #11143`, `## Changelog` (patch), a release note that earlier runs may have left 96-byte `.pen` files, and the #11156 reference.

## Files to Edit

- `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`
- `plugins/soleur/skills/pencil-setup/scripts/pencil-save-gate.mjs`
- `plugins/soleur/skills/pencil-setup/scripts/pencil-response-classify.mjs`
- `plugins/soleur/skills/pencil-setup/scripts/pencil-error-enrichment.mjs`
- `plugins/soleur/skills/pencil-setup/scripts/copy_adapter.sh`
- `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`
- `plugins/soleur/skills/pencil-setup/SKILL.md`
- `plugins/soleur/agents/product/design/ux-design-lead.md`
- `plugins/soleur/test/pencil-save-gate.test.ts`
- `plugins/soleur/test/pencil-response-classification.test.ts`
- `plugins/soleur/test/pencil-error-enrichment.test.ts`
- `knowledge-base/project/learnings/bug-fixes/2026-09-30-pencil-headless-cli-reopen-wipes-pen-file.md`

## Files to Create

- `plugins/soleur/skills/pencil-setup/scripts/pencil-repl-surface.mjs`
- `plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh` (key-gated, exit 3 without `PENCIL_CLI_KEY`; deliberately **not** a `*.test.sh`, so it is not an orphan-lint/shard-registry suite and never a required CI job)
- `plugins/soleur/test/pencil-repl-surface.test.ts` (formatter, `planSpawn`, table floor)
- `plugins/soleur/test/pencil-adapter-sentinels.test.ts` (exactly one `save` emission; no string-literal `enqueue(`; `ADAPTER_FILES` contains every imported sibling)
- `plugins/soleur/test/pencil-adapter-stub-repl.test.ts` (integration over real MCP stdio, adapter run from an installed copy; an unreachable registry fails the test, it never skips)
- `plugins/soleur/test/fixtures/pencil-stub-repl.mjs` (synthesized REPL stub)
- `plugins/soleur/test/lib/pencil-adapter-roundtrip.mjs` (shared driver: stub in CI, real engine in the probe)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "pass the existing file as inputPath/--in on open_document" [issue #11143] | Proposed Solution 1 `planSpawn`, 4 spawn wiring | mapped |
| 2 | "skip the pre-switch save when the document is empty" [issue #11143] | Proposed Solution 4: pre-switch save deleted; remaining saves guarded | mapped |
| 3 | "find why the headless engine ignores operations" [issue #11143] | Research Reconciliation row 1; Proposed Solution 1 | mapped |
| 4 | "decide on the CLI migration" [issue #11143] | R1 ruling; Proposed Solution 6 pin; follow-up #11156 | mapped |
| 5 | "`batch_design` returns \"OK\" with no node-id mapping and no error, even for a deliberately invalid op" [issue #11143] | Guard 2; Proposed Solution 1, 3 | mapped |
| 6 | "`save` writes an empty 96-byte document" [issue #11143] | Guard 1 | mapped |
| 7 | "Blocks every UI brainstorm because the wireframe gate requires a committed .pen" [brief] | AC3 live round trip | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `pencil-repl-surface.mjs`, `planSpawn` | "pass the existing file as inputPath/--in on open_document" | asked |
| `guardedSave()` and its exclusive section | "skip the pre-switch save when the document is empty" | asked (extended to every write site: `hr-write-boundary-sentinel-sweep-all-write-sites`) |
| `operations` to `input` | "find why the headless engine ignores operations" | asked |
| `@pencil.dev/cli@0.2.9` pin, #11156 | "decide on the CLI migration" | asked |
| `^Unknown tool:` classifier line, enrichment hints | "returns \"OK\" with no node-id mapping and no error" | asked (same silent-success class) |
| `var I=Insert...` preamble | — | inferred — justification: Desktop-grammar `I()`/`U()` scripts appear throughout repo learnings and would hit a `ReferenceError`; CTO R3 |
| `get_guidelines` schema and `ux-design-lead.md` edits | — | inferred — justification: 0.2.9 changed the tool's parameters; the prose otherwise wastes a round per design run and its post-save gate passes a 96-byte file; CTO R2, CPO |
| Exit-before-ready rejection, open-failed state, first-spawn-only `inFile` | — | inferred — justification: `--in <outFile>` makes a non-empty but invalid file newly reachable (30 s hang) and a respawn must not reload a template over saved edits |
| `open_document` node-count report | — | inferred — justification: the 2026-04-10 learning's verification step and the observable AC3 reads |
| Stub-REPL test, `engine-contract-probe.sh`, sentinels test | — | inferred — justification: without them the drift that caused this bug returns unseen (R5, `cq-write-failing-tests-before`) |
| `copy_adapter.sh` hard error on a missing source file | — | inferred — justification: a silently partial install fails at import on a customer machine (Guard 3) |
| Amended learning | — | inferred — justification: `wg-every-session-error-must-produce-either` |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned files: 19 | Estimated changed lines: ~650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** engineering, product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings R1-R5. Risks adopted: decide `--in` inside `spawn()`; classify `Unknown tool:`; verify multi-line `input` escaping; delete dead node-id code; no "no mapping means error" heuristic. Devex review of the finished plan: no P0; retirement list for #11156 added to that issue.

### Product (CPO)

**Status:** reviewed
**Assessment:** Agrees with `single-user incident`; plan-time sign-off yes, conditional on the refusal message being specified (Proposed Solution 5) and #11156 being milestoned (done). Asked for a content round trip (AC3) and a release note about existing 96-byte files (Phase 5).

### Product/UX Gate

**Tier:** none
**Decision:** no user-facing page or component; the mechanical UI-surface override was checked against both Files lists (no `components/**`, `app/**`, `*.njk` etc.)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## User-Brand Impact

- **If this lands broken, the user experiences:** a wireframe session that reports success for every edit while the `.pen` stays empty, or an existing design file replaced by a 96-byte empty document.
- **If this leaks, the user's workflow is exposed via:** no new data path; the adapter reads and writes only the `.pen` paths the caller names and the env allowlist is unchanged.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user's untracked design file silently destroyed is enough to cost trust in the plugin; the adapter ships to customer machines where the repo's open/collapse hooks do not exist, so the sentinel is the only layer there.

CPO sign-off recorded above (`requires_cpo_signoff: true`). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

Execution surface: the adapter runs only on the developer's own machine as a local MCP stdio child (layer 7, self-hosted CLI). It is never vendored into the production image (no reference under `apps/`, `infra/`, `Dockerfile*`; `.github/workflows/ci.yml` only regenerates its lockfile), so there is no hosted path. Layer 7 forbids routing this output to Soleur infrastructure; the synchronous signal is the tool result plus adapter stderr, and the durable artifact is the `.pen` itself.

```yaml
liveness_signal:
  what: "adapter stderr line '[pencil-adapter] MCP server started on stdio' at boot, then a tool result per call (layer 7 cli-stdout-artifact)"
  cadence: per-tool-call
  alert_target: the calling agent session reads the tool result; no Soleur-side sink by design
  configured_in: plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs

error_reporting:
  destination: "MCP tool result with isError true, read in-session, plus adapter stderr in the MCP log (layer 7; Sentry is deliberately not used for customer-machine code)"
  fail_loud: "'REFUSED save:' (sentinel), 'Unknown tool' with a replacement hint (removed tools), 'ReplContractError' (adapter and engine disagree), 'open failed' (bad inputPath or empty load)"

failure_modes:
  - mode: adapter sends a tool or key the engine does not know (the #11143 class)
    detection: "formatReplCommand throws ReplContractError so the caller gets isError; engine-contract-probe.sh diffs 'pencil interactive --help' signatures against the table (layer 7, run on every pin bump)"
    alert_route: tool result in the agent session
  - mode: an empty in-memory document would be saved over a non-empty .pen
    detection: "guardedSave refuses; stderr line and isError tool result naming the file (layer 7)"
    alert_route: tool result in the agent session, then ux-design-lead post-save gate
  - mode: CLI process exits before it is ready (bad input file, auth failure)
    detection: "spawn rejects with the CLI stderr tail instead of a 30 s timeout (layer 7)"
    alert_route: tool result in the agent session
  - mode: installed adapter copy is stale or missing a module
    detection: "check_deps.sh --check-adapter-drift prints DRIFT; copy_adapter.sh exits non-zero on a missing source file; the adapter's import-failure message names copy_adapter.sh (layer 7)"
    alert_route: stderr in the MCP log and the pencil-setup skill output

logs:
  where: adapter stderr in the Claude Code MCP log for the pencil server
  retention: per Claude Code session log retention on the developer's machine

discoverability_test:
  command: node -e "import('./plugins/soleur/skills/pencil-setup/scripts/pencil-save-gate.mjs').then(m=>console.log(m.decideSave({diskCount:3,memoryCount:0}).allow))"
  expected_output: false
```

## Guard Contract

### Guard 1 — Empty-overwrite save sentinel

**Property.** No code path in the adapter writes an empty in-memory document over an on-disk `.pen` that holds at least one top-level node.

**Assembly.** The chokepoint is `guardedSave()`, one exclusive queue job; the REPL `save` command is emitted only from `formatReplCommand("save", {})` inside it. Callers today: the `batch_design` auto-save and the explicit `save` tool (the `set_variables` and `replace_all_matching_properties` auto-saves vanish because those tools now fail at the engine, and the `open_document` pre-switch save is deleted). `exit()` and SIGTERM do not write (measured). One chokepoint, two callers; a third caller must route through the same function. The target path read inside the job is the **current** `pencilProcess.outputFile` at the moment the job runs. A source-sentinel test derives the caller set by scanning the adapter for every `formatReplCommand("save"` and every string-literal `enqueue(`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make `decideSave` always return `allow` | RED (unit: disk 3 / memory 0; stub integration: a refused save leaves the fixture bytes unchanged) |
| 2 | Add a second `formatReplCommand("save"` emission outside `guardedSave` | RED (sentinel: exactly one emission, inside `guardedSave`) |
| 3 | Register a new mutating tool after the compliant ones that saves through its own path | RED (sentinel: no string-literal `enqueue(`, no `save` emission outside `guardedSave`) |
| 4 | Weaken the predicate to protect only `diskCount > 1` | RED (unit: disk 1 / memory 0) |
| 5 | Treat an undeterminable memory state as allow | RED (unit: disk 3 / memory null expects refuse) |
| 6 | REORDER: do the memory check after the `save` command | RED (stub integration records the command sequence and reads the fixture bytes after the refused call: a post-write check has already overwritten them and a `save` was sent) |
| 7 | Dispatch: make `guardedSave` skip the disk read (treat `diskCount` as null) | RED (stub integration: non-empty fixture plus empty in-memory document must refuse, and the stub must have seen a `batch_get` before any `save`) |
| 8 | INTERLEAVE: run the probe and the `save` as two separate queue jobs | RED (stub integration queues a `batch_design` between them and asserts it cannot land inside the section) |

**Harness rows.** H1: delete the stub's signature whitelist; the stub self-test "stub rejects `batch_design({ operations })` with exit 64" goes RED. H2 (must-PASS, not the canonical): disk 3 nodes with memory 5 saves; a collapsed 96-byte target with an empty memory saves; a missing target saves; an unparseable target saves.

**Anchor.** No stored value is compared: the sentinel compares the live file to the live document, so no hash exists for a single commit to weaken in step with the thing it protects.

### Guard 2 — REPL surface conformance

**Property.** Every REPL command line the adapter emits names a tool and parameter keys that exist in the engine's signature table for the pinned CLI version, and a response of `Unknown tool:` is an error.

**Assembly.** All REPL emissions flow through `formatReplCommand`: the registered tools, the internal `batch_get` inside `export_nodes`, the sentinel's memory probe, and `save` (which is a table entry with no keys). The adapter contains no string-literal `enqueue(`. Three copies of the table exist (the module, the stub fixture's whitelist, the live `--help` output) and must agree.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the `batch_design` key back to `operations` | RED (unit; and the stub exits 64 on the unknown key so the round trip fails) |
| 2 | Dispatch: empty the surface table | RED (the table test asserts the exact tool set and key lists; `formatReplCommand` throws for every tool) |
| 3 | Call `formatReplCommand` for a tool the table does not know, after the compliant ones | RED (unit: throws `ReplContractError`) |
| 4 | Remove the `^Unknown tool:` pattern from the classifier | RED (classification test) |
| 5 | Edit the table and the stub fixture together to agree on a wrong key | RED only in `engine-contract-probe.sh` (the outside anchor); CI cannot see it |
| 6 | Drop the `batch_design` preamble | RED (unit asserts the `var I=Insert` prefix; the probe runs an `I(...)` script) |

**Harness rows.** H1: stub whitelist deletion (as Guard 1). H2 (must-PASS): `get_guidelines({ category: "guide" })` with some optional keys omitted, `snapshot_layout({})` and `get_variables()` format successfully.

**Anchor.** Table and fixture live in one commit, so their agreement proves consistency, not integrity. The outside anchors are the installed CLI (the probe diffs its `--help` signatures against the table) and the version pin; moving the table or the CLI alone turns the probe RED.

### Guard 3 — Installed-adapter completeness

**Property.** Every sibling module the adapter imports at runtime is copied by `copy_adapter.sh`, and a missing source file fails the copy.

**Assembly.** Imports are derived from the adapter source (`await import("./...mjs")`), the copy set from the `ADAPTER_FILES` array; the stub integration test executes the installed copy, so a missing module fails at import.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `pencil-repl-surface.mjs` from `ADAPTER_FILES` | RED (parity test; install-copy import failure) |
| 2 | Dispatch: make the import scan return zero imports | RED (parity test asserts the parsed set equals the five known siblings) |
| 3 | Add another sibling import without listing it | RED (parity test) |

**Harness rows.** H1: break the `ADAPTER_FILES` parser (return an empty set); the set-equality assertion goes RED. H2 (must-PASS): a copy list with an extra non-imported file (`package.json`) passes.

**Anchor.** Both sides derive from one commit; the stub integration test, which executes the installed copy, is the independent check.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. `batch_design({ operations })` through the adapter sends `batch_design({ input: ... })`; the stub integration test fails if the REPL ever receives `operations` (`pencil-repl-surface.mjs`, `pencil-adapter-stub-repl.test.ts`).
- [ ] AC2. `open_document({ filePath })` on an existing non-empty `.pen` spawns with `--in <filePath> --out <filePath>`; on a missing file with neither; an explicit missing `inputPath`, or a file that loads empty from a non-empty file, returns `isError` in under 5 s and puts the adapter in the open-failed state; a respawn after a crash reloads `--out`, never a template `inputPath` (`planSpawn`, `PencilProcess.spawn`).
- [ ] AC3. Live round trip against the real engine: open a new path, insert a frame and text, save, reopen the same path, `open_document` reports at least 1 top-level node, and the file is larger than 96 bytes (`engine-contract-probe.sh`, key from Doppler `soleur/dev`).
- [ ] AC4. With a non-empty target and an empty in-memory document, auto-save and explicit `save` each refuse with the refusal text; fixture bytes are unchanged and no `save` command reached the stub; an interleaved queued command cannot land between probe and save (Guard 1 rows 1, 6, 8).
- [ ] AC5. Removed tools return `isError` with a replacement hint and trigger no save; `Unknown tool:` classifies as an error.
- [ ] AC6. A script written with `I(...)`/`U(...)` runs, and two consecutive `batch_design` calls both succeed (probe).
- [ ] AC7. `check_deps.sh` installs `@pencil.dev/cli@0.2.9`; `copy_adapter.sh` lists every imported sibling and exits non-zero on a missing source file (Guard 3).
- [ ] AC8. Mutation rows Guard 1 #1, #4, #5, #6, #8 and Guard 2 #1 were each applied once and observed RED, output in the PR; the remaining rows are exercised by the committed tests, and Guard 2 #5 by the probe.
- [ ] AC9. `ux-design-lead.md` Step 2 items 1-2 use `get_guidelines({ category, name })` for the headless adapter and tolerate "not supported" from the style tools; Step 3 item 2 no longer treats a 96-byte file as success; `bun test plugins/soleur/test/components.test.ts` passes (no skill `description:` change).
- [ ] AC10. The 2026-09-30 learning is amended with the `--in` root cause; PR body has `Closes #11143`, a `## Changelog` section and the 96-byte release note.
- [ ] AC11. `bun test` for the new and edited pencil tests passes; `bash plugins/soleur/test/pencil-adapter-auth-hard-fail.test.sh` and `bash plugins/soleur/test/check-deps-adapter-drift.test.sh` still pass.

### Post-merge

- [ ] AC12. `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --check-adapter-drift --auto` reports `OK` on a machine whose installed adapter pre-dates the merge (the pencil-setup `--auto` flow already runs it). Sessions already running keep the old MCP child until Claude Code restarts; that is a session boundary, not a task.

## Test Scenarios

Layers: `unit` = bun pure-module tests; `integration` = stub REPL over real MCP stdio from an installed copy; `engine-contract-probe.sh` is the only test that touches the real engine (`pyramid-justified: the stub encodes our belief about the REPL, which is how this bug passed review; only the real engine confirms the contract`).

- Given `batch_design` with `operations: "a=Insert(document,{...})"`, then the line is `batch_design({ input: "var I=Insert,...;\na=Insert(...)" })` with newlines and quotes JSON-escaped (unit).
- Given empty `operations`, or a tool or key absent from the table, then `ReplContractError` (unit).
- Given `outFile` exists and is non-empty, then `inFile === outFile`; given it does not exist, `null`; given an explicit missing initial `inFile`, a thrown not-found error; given a 0-byte `outFile`, `null`; given a respawn with a prior explicit `inFile`, `inFile === outFile` (unit).
- Given disk 3 / memory 0, refuse; disk 3 / memory null, refuse; disk 0 / memory 0, allow; disk missing or unparseable, allow; disk 3 / memory 5, allow (unit).
- Given `Unknown tool: find_empty_space_on_canvas`, then `isError` plus the hint (unit).
- Given the stub holding a 3-node `.pen`, when the adapter opens it, runs `batch_design`, then `save`, then the file keeps 3 plus the new node (integration regression).
- Given a simulated child crash mid-session, then the next command reloads the saved file, not the template (integration).
- Given `open_document` of a non-empty file the stub is told to load empty, then `isError`, the open-failed state, and the file unchanged (integration).
- Given the real engine, the AC3 round trip and a signature diff against the table (probe).

## Dependencies & Risks

- **0.2.9 availability.** The package is npm-deprecated; `latest` is 0.2.9 today so the pin changes nothing for fresh installs and does not correct existing installs on another version or transitive carets. Mitigation: probe on every pin bump; #11156 trigger conditions.
- **Refusing a deliberate wipe.** Delete-all-then-save over a non-empty file is refused by design; the message names the escape (a new file path). In this repo `pencil-open-guard.sh` also requires that path to be committed first; relaxing that guard now that the root cause is fixed is a possible follow-up, not done here.
- **Engine text drift** in the `batch_get()` JSON shape would make saves refuse (fail-closed); the probe asserts the shape on every bump.
- **SDK in CI.** The stub integration test runs `copy_adapter.sh` into a temp dir, which runs `npm ci --ignore-scripts`; an unreachable registry fails the test.
- **One adapter, one open document.** Parallel design sub-agents sharing one adapter switch each other's document on `open_document`; the existing prose recipe uses separate sessions per variant and this plan does not change that.
- **Desktop-grammar `filePath` on `batch_design` / `batch_get` / `get_screenshot`** is stripped by the legacy tool registration and applied to the open document (Cut List, strict schemas).
- **Dependency:** none blocking. #11156 is the deferred migration; its body carries the retirement list for the table, stub, preamble, hints and `planSpawn`.

## Non-Goals

- Migrating to `@pen.dev/cli` (#11156); translating removed tools onto `batch_design`; strict MCP-boundary schemas.
- Hashing every adapter file in the drift check (pre-existing; this PR changes the adapter file so installs drift-detect once).
- The `SHARP_IGNORE_GLOBAL_LIBVIPS=1` install workaround on libvips hosts (tracked from the 2026-09-25 learning).
- Changing `pencil-open-guard.sh` / `pencil-collapse-guard.sh`; they stay as outer layers in this repo.
- Telling the caller when a crash-restart reloaded the document; a startup CLI version check; a scheduled probe.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. This one declares `single-user incident`.
- `copy_adapter.sh` deploys to `~/.local/share/pencil-adapter`, which is what `claude mcp list` shows registered. Verifying against the repo copy alone proves nothing about what a session runs; Phase 4 refreshes and re-checks the installed copy.
- The stub REPL replays synthesized transcripts only (`cq-test-fixtures-synthesized-only`) and drains stdin, or `pipefail` suites flake on EPIPE.
- The `var` preamble tolerates a prior global `I=Insert`; a model script that declares its own `const I` fails with `SyntaxError: invalid redefinition of global identifier`, which the existing `^Error:` / `^\[ERROR\]` patterns classify as an error (measured).
- The probe is a plain script, not a `*.test.sh`: a tracked `*.test.sh` must be registered with the orphan-suite lint and the shard registry, which would make a key-gated check a required CI job.

## References

- Issue #11143; follow-up #11156; closed precursors #3274, #4859, #2630.
- Hooks: `.claude/hooks/pencil-open-guard.sh`, `.claude/hooks/pencil-collapse-guard.sh`.
- Live measurements and the SDK spike ran in the session scratchpad and are summarized above; none are committed.
