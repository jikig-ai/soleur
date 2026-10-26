---
title: "chore(pencil-mcp): migrate headless adapter from @pencil.dev/cli 0.2.9 to @pen.dev/cli, with a stale-file save guard"
type: chore
date: 2026-10-26
slug: migrate-pencil-adapter-to-pen-cli-and-stale-save-guard
branch: feat-one-shot-11156-11168-pen-cli-migration
issue: 11156
closes: [11156, 11168]
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# chore(pencil-mcp): migrate headless adapter to @pen.dev/cli, with a stale-file save guard

## Overview

Move the headless Pencil MCP adapter onto the maintained `@pen.dev/cli` package, and build the on-disk
change check for saves (#11168) on the new adapter structure in the same change so it is written once.
The adapter is the bridge every UI wireframe authored through `soleur:product:design:ux-design-lead`
depends on (`wg-ui-feature-requires-pen-wireframe`), and on a customer machine its save sentinel is the
only protection a user's design file has (this repo's open/collapse hooks do not exist there).

The operator asked for the migration now, so #11156's "trigger to start" list is satisfied by request.
Both issues close from the one PR (`Closes #11156`, `Closes #11168` in the PR body, not the title).

Shape of the change: the agent-facing `mcp__pencil__*` tool names stay (hooks and prose are keyed on
them); the adapter translates each live tool onto the new REPL (`execute`, `get_app_state`, `read_skill`,
`save`); tools the new engine cannot honour become removed-tool stubs with an actionable hint; the save
path gains a SHA-256 baseline of the file (captured before every load, re-set after every confirmed save)
and refuses a save when the file no longer matches it.

## Enhancement Summary

**Deepened on:** 2026-10-26
**Agents used:** security-sentinel, test-design-reviewer, observability-coverage-reviewer, user-impact-reviewer (this pass); dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer and a sharp-edges verification pass (plan-review); CTO (three ruling rounds); CPO sign-off.
**Halt gates run:** 4.6 user-brand impact (pass), 4.7 observability (pass, probe command replaced), 4.8 PAT-shaped variables (none), 4.9 UI wireframe (no UI surface), 4.10 encryption posture (no store, skipped), 4.11 guard contract (lint green, 2 guards), 4.12 scope check (pass), 4.13 task design (no autonomous task surface, skipped).

### Key improvements

1. The CLI moves to its own lockfile-pinned prefix (`~/.local/share/pen-cli`, `npm ci`, scripts ignored): this removes the `.bin/pencil` collision with a leftover `@pencil.dev/cli` entirely and keeps the credential out of install scripts.
2. The stale fingerprint hashes the canonical JSON of the document, so line-ending conversion, formatters and Desktop normalisation cannot make every save refuse; the post-save read retries before the baseline becomes unknown.
3. The REPL framing is hardened: the prompt must be at the end of the buffer after a quiet period, the save confirmation compares realpaths by string equality, the count line carries a random nonce, and `jsonLine` escapes the C1 range.
4. A refusal now returns the refused operations (capped) and marks exports rendered from unsaved memory, so refused work is recoverable and not silently shipped.
5. The child runs in a private empty cwd with a filtered PATH; `PENCIL_BINARY` is honoured only for a safe regular file; export and screenshot persistence share one contained-directory helper.
6. Observability gains stderr reason lines for every new refusal state, a committed-artifact instruction for the wireframe summary, and the correct hosted-path evidence.

### New considerations discovered

- The vendored plugin tree ships these scripts in the production image; the adapter is still never started hosted because no hosted `mcpServers` registration names `pencil` (pinned by an acceptance criterion).
- `batch_design` forwards raw DSL, so host functions that take paths are reachable without `export_nodes` validation; the residual is recorded in the ADR and pinned by one probe case (CTO ruling 11.2).
- The stub needs new capabilities (flags that rewrite the file at start and at probe time, scripted save replies, per-session side channels) before four mutation rows are realisable; they are now part of Phase 1.1.
- Adding a fifth lockfile directory touches ADR-191's lockfile-sync and Dependabot wiring; the work phase enumerates and edits those through the ADR's own procedure.

## Research Reconciliation — Spec vs. Codebase

The #11156 body was written before anyone ran the new engine end to end. Measured against
`@pen.dev/cli` 0.3.13 on 2026-10-26 (live, Doppler `soleur/dev` credential, scratch directory):

| Issue / brief claim | Reality (measured) | Plan response |
|---|---|---|
| "Retire `planSpawn`" | `pen interactive --out existing.pen` with no `--in` still loads an EMPTY document (the #11143 hazard is unchanged) | Keep `planSpawn`; it still supplies `--in` for a non-empty `--out` |
| "Retire the `batch_design` alias preamble" | `typeof I` and `typeof U` are `undefined` inside `execute`; only the long names exist (same as 0.2.9) | Keep the `var I=Insert,...;` preamble, now prefixed onto `execute({ input })` |
| "Retire the `Unknown tool:` hints in `pencil-error-enrichment.mjs`" | Removed tools must still answer with a replacement hint, and the removed set grows (batch_get, snapshot_layout, get_guidelines) | Rewrite the hint table; do not delete it |
| "Retire the `batch_get()` node-count parsing in the save sentinel" | Correct: `batch_get` is gone. A read-only `execute` snippet prints a count line and `get_app_state` lists top-level nodes | Replace with a nonce-anchored count parse (CTO ruling 6, reviewer hardening) |
| "Retire the stub REPL fixture and its signature whitelist" | The stub is still the only offline harness for queue/save ordering tests | Rewrite it to the new prompt and surface; keep ONE whitelist (the module table) and pin its reply shapes to a captured real transcript |
| "The migration also touches hooks keyed on `mcp__pencil__open_document`" | Not if tool names stay stable | No hook or `settings.json` change (CTO ruling 1) |
| "auth variable `PENCIL_CLI_KEY` to `PEN_CLI_KEY`" | The existing Doppler value authenticates when passed as `PEN_CLI_KEY` (`pen status` Active). A bogus value does NOT stop `pen interactive`: the usage check fails open, so only a missing key is fatal | Accept both names, empty counts as unset; Doppler untouched (CTO ruling 2) |
| "bin `pen` with a `pencil` alias" | Confirmed (`bin: {pen, pencil}`, same `dist/index.mjs`); `engines.node >=22.19.0` confirmed | Resolve only `pen` inside the installed package directory; never `pencil` |
| #11168: "`decideSave` allows any save when `memoryCount > 0`" | Confirmed in `pencil-save-gate.mjs` (`decideSave` last branch) | Add the stale check as a separate pure function after `decideSave` |
| Agent prose names `get_guidelines`, `snapshot_layout`, `batch_get` | Those tools are gone; guides exist as `read_skill({ path: "guide/<name>.md" })` and layout problems arrive as an `## issues detected:` block on `execute` replies | Update `ux-design-lead.md` (+ generated mirrors) in the same PR |

## Research Insights

**Premise validation.** Both issues are OPEN with no closing PR (`gh issue view 11156/11168`). Every cited
file exists on `origin/main` (`pencil-save-gate.mjs` `decideSave`, `pencil-repl-surface.mjs`,
`pencil-error-enrichment.mjs`, the stub fixture, `engine-contract-probe.sh`, `check_deps.sh`). No ADR in
`knowledge-base/engineering/architecture/decisions/` names `@pencil.dev`, `@pen.dev`, `PENCIL_CLI_KEY` or
`mcp__pencil__`, so no rejected-alternative collision. The brief's "Unknown tool" measurement was
re-measured and holds. A census of the retired terms outside plans, specs and archives
(`git grep -nE '@pencil\.dev/cli|PENCIL_CLI_KEY|snapshot_layout|get_guidelines|batch_get' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!**/archive/**' ':!knowledge-base/project/learnings'`)
returns only the files in Files to Edit (plus the generated mirrors); no other plan or spec directs an agent
to a retired tool. `knowledge-base/INDEX.md` is pipeline-written and not hand-edited.

**Property List.**

1. A wireframe round trip (open, edit, export, save, reload) works against `@pen.dev/cli` 0.3.13 through the `mcp__pencil__*` names agents and hooks already use.
2. An empty document is never written over a file that holds nodes, nor anything over an unrecognizable file (unchanged from #11143).
3. A save never replaces a file that changed on disk behind the session (#11168), including a smaller non-empty document over a larger one.
4. The adapter authenticates with the existing credential value under either variable name and never leaks it.
5. Install and detection resolve only the maintained package and fail closed on the deprecated one.
6. The adapter/engine contract is checked against the real engine (key-gated), not only a stub that encodes our belief.
7. Agents are told truthfully which tools exist; a removed tool answers with an actionable hint.

**Cut List** (mechanism, property, what already covers it or why cut).

- Renaming `mcp__pencil__*` to native names (property 1; names already stable, renaming forces hook and prose churn for no capability).
- Exposing raw `execute` (no property; a second mutation path would bypass the save and open guards). `batch_design` already forwards agent script to `execute`; the engine's DSL runs in a QuickJS sandbox with no `process`, `require`, `fetch` or `XMLHttpRequest` (measured), which is the residual-risk statement the ADR records.
- A `batch_get` / `snapshot_layout` shim over `Get()` (no property the engine can honour; it would invent a node-dump format agents then rely on).
- A `get_style` tool (CTO follow-up ruling; `read_skill` already returns the style archetypes and `get_style({name,params})` would embed caller text in a REPL line).
- Adapter-side rename of exported files by node name (CTO follow-up ruling; needed a second parsed reply carrying user node names, and `ux-design-lead.md` step 3.4 already renames after export).
- Size+mtime as the #11168 fingerprint (property 3; content hash covers same-size rewrites and a `git checkout` that restores identical bytes).
- A delete-all-nodes escape hatch (property 2; a flag is itself the bypass).
- Renaming the Doppler secret (property 4; production mutation with no benefit; the value already works).
- Auto-uninstalling a leftover `@pencil.dev/cli`, and a PATH fallback for the `pen` binary (property 5; resolve inside the installed package only).
- A second copy of the REPL signature whitelist inside the stub (property 6; the module table is the one copy, the captured transcript and the live probe are the checks).
- A one-time differential run against the deprecated 0.2.9 (the oracle's contract is already encoded in the 63 existing unit assertions and the old stub; the key-gated live probe is the oracle for the new engine).
- A separate Phase 0 (its probe cases are folded into the test-first step of Phase 1).

**Authority grepped for the Cut List claims:** `pencil-save-gate.mjs` (`decideSave` covers only empty and
unrecognizable), `.claude/hooks/pencil-collapse-guard.sh` and `pencil-open-guard.sh` (repo-only, run on
`open_document`, never on a stale save and never on a customer machine), `apps/web-platform` (no Pencil MCP
code; the adapter does not execute hosted).

**Measured contract of `@pen.dev/cli` 0.3.13 headless (`pen interactive --out f.pen [--in g.pen]`).**

| Fact | Evidence |
|---|---|
| The prompt is the text `pen >` followed by one space (it was `pencil >`); startup prints `[INFO] Starting pen.dev (headless)...`, `[INFO] Ready.` and a banner before it | live session |
| REPL tools: `execute({input\|edits,editId,description})`, `get_app_state()`, `get_style({name,params})`, `read_skill({path})`, `browser(...)`; shell commands `save()`, `exit()`, `import_library`, `remove_library`, `list_libraries` | `pen interactive --help` |
| `batch_design`, `batch_get`, `get_editor_state`, `get_screenshot`, `export_nodes`, `snapshot_layout`, `get_variables`, `get_guidelines` answer `Unknown tool: X` | live (`batch_design`), help listing; Phase 1 probe re-checks every name live |
| `execute` success replies start `OK`, then `## Print output`, `## Created nodes by name`, optionally `## issues detected:` | live |
| `execute` failure prints red `Error: ### Failure during operation execution` plus `[ERROR] ...` lines and rolls the block back; the reply tells the caller to retry with `edits`/`editId` (not exposed by the adapter) | live |
| Top-level count: `Get((n,c)=>{c.skipChildren();...})` visits only top-level children (0 on an empty document); `Get(document)` without a visitor is an error | live |
| `TakeScreenshot(["id"])` reply carries a JSON array `[{nodeId,image(base64),mimeType}]`; `Export(["id"],"png","./dir")` prints `Exported <abs path>`; a 4th argument must be an options object (`{scale:3}` changes output size; `3` errors) | live |
| `GetVariables()` prints `{"variables":{}}`; `FindEmptySpace({width,height})` prints `{"x":..,"y":..}`; `SetVariables`, `Generate`, `Copy`, `Replace`, `Move`, `Delete`, `Update` exist; `I`/`U` aliases do not | live |
| `save()` replies `Saved <path>` (green); a failed save prints `Save failed: <reason>` (red) and nothing else marks it as an error | live (read-only directory) |
| The engine never writes `--out` except on `save()`: a new path edited then `exit()`, an existing file edited then `exit()`, and SIGTERM after an edit all leave the file absent or byte-identical | live |
| The DSL runs in a QuickJS sandbox: `typeof process`, `require`, `fetch`, `XMLHttpRequest`, `WebSocket` are all `undefined`; `Export` to a missing node id errors before writing | live |
| `--in` unparseable `.pen` makes the CLI exit with `[ERROR] Fatal error: Failed to open document` (0.2.9 loaded such a file empty) | live |
| Saved document: `"version":"2.21"`, `children`, and a `fileToken` UUID (gitleaks `generic-api-key`; tracked in #8964) | live |
| No `PEN_CLI_KEY` and no login: `[ERROR] Authentication required. Run "pen login" or set PEN_CLI_KEY environment variable.` and exit; an invalid key still runs (fail-open usage check, `[WARN] ... 401`) | live |
| `read_skill()` guide index: `guide/{components,code,design-system,landing-page,mobile-app,slides,table,tailwind,web-app}.md` plus top-level `pen-schema.md`, `execute.md`, `generate.md`, `scripts-and-shaders.md`; `execute.md` is the DSL grammar | live |

Not measured, recorded as limits: whether the engine's write is atomic (temp file plus rename), and how the
engine behaves when handed a file written by a newer Desktop. The design does not depend on either: a
post-save read happens only after the confirmed `Saved` reply, and a truncated file is caught by the existing
unrecognizable-file refusal on the next save.

**Institutional learnings applied** (all under `knowledge-base/project/learnings/`):

- `bug-fixes/2026-10-26-a-stub-that-encodes-your-belief-about-an-engine-passes-the-bug-it-was-written-to-catch.md`: stub tests encoded the wrong belief; only the real-engine probe catches contract drift. Drives the probe rewrite, the captured-transcript fixture and keeping ONE signature table.
- `bug-fixes/2026-09-30-pencil-headless-cli-reopen-wipes-pen-file.md` and `2026-04-10-pencil-mcp-open-document-clears-untracked-files.md`: re-open of an existing file loads empty; the reason `planSpawn` stays.
- `2026-04-17-stream-response-toctou-across-fd-boundary.md`: a check on one handle and a use on another let the file change between them. Drives "re-read immediately before `save()`" and baseline-before-load ordering.
- `2026-06-04-pencil-headless-key-from-doppler-before-hardblock.md` and `2026-03-25-pencil-adapter-env-var-screenshot-persistence-api-coercion.md`: the key lives in Doppler `soleur/dev`; registering with `-e` after `--` makes auth hang. Existing registrations keep working through the `PENCIL_CLI_KEY` fallback.
- `2026-09-25-pencil-headless-cli-install-on-global-libvips-hosts.md` (tracked in #8964, acknowledged below): `sharp` install fails on hosts with a global libvips.
- `2026-03-10-dogfood-collision-guard-requires-realistic-fakes.md`: fakes must answer every probe like the real binary; the stub reproduces the real prompt, `Saved`, `OK` and `Save failed:` shapes measured above and a test pins them to a captured transcript.

**Related issues.** #11143 / PR #11155 (predecessor), #8964 (install landmines, acknowledged: not in this PR), #9310 (unbounded install at `copy_adapter.sh`, acknowledged: untouched).

**Skill-body byte headroom** (`plugins/soleur/test/skill-body-budget.json`): `brainstorm/SKILL.md` has 7 bytes under its ceiling and `plan/SKILL.md` has 14. Their wireframe-gate edits therefore replace the package and variable names with a pointer to `pencil-setup/SKILL.md` and must be byte-neutral or smaller; `python3 scripts/lint-skill-body-budget.py --base origin/main` is an acceptance criterion.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200) searched for every planned file path
(adapter and its five siblings, `check_deps.sh`, `engine-contract-probe.sh`, `SKILL.md`, the stub fixture,
`ux-design-lead.md`, the hook scripts): no body mentions any of them. #8964 and #9310 are not
`code-review` labelled; both are acknowledged under Non-Goals.

## Technical Rulings

Persisted in `knowledge-base/project/specs/feat-one-shot-11156-11168-pen-cli-migration/decision-challenges.md`.
Summary of the CTO rulings (2026-10-26; none needed operator input):

1. **Tool surface: keep the names, translate inside the adapter.** Live (8): `open_document`, `save`, `batch_design`, `get_screenshot`, `export_nodes`, `get_editor_state`, `get_variables`, `read_skill`. Removed stubs (9, never reach the engine): `batch_get`, `snapshot_layout`, `get_guidelines`, `get_style_guide`, `get_style_guide_tags`, `find_empty_space_on_canvas`, `search_all_unique_properties`, `replace_all_matching_properties`, `set_variables`. Raw `execute` is not exposed. (`get_style` was cut by the follow-up ruling; the stub set was kept.)
2. **Auth:** resolve the key from `PEN_CLI_KEY`, else `PENCIL_CLI_KEY` (an empty or whitespace value counts as unset), always hand the child `PEN_CLI_KEY`, one value-free deprecation line on the fallback; redact both names; Doppler unchanged.
3. **Install:** `@pen.dev/cli@0.3.13` exact pin, installed from a committed lockfile with `npm ci` (credential variables unset, scripts ignored if the probe passes) into its own prefix `~/.local/share/pen-cli` so it can never collide with a leftover `@pencil.dev/cli` bin; resolve only that prefix's `.bin/pen`, whose realpath must equal the package's declared `bin.pen` target and whose `package.json` name is `@pen.dev/cli`; no PATH fallback; a leftover `@pencil.dev/cli` is a warning; Node floor 22.19.0 everywhere.
4. **#11168:** SHA-256 of the canonical JSON of the document (BOM stripped, raw bytes only when the text does not parse), one per-process baseline, refuse in the existing `REFUSED save:` style, re-open clears it, `decideSave` unchanged and the stale check is a separate pure function; a `refusalPending` flag keeps a stale refusal alive across a crash respawn until `open_document` succeeds.
5. **Delete-every-top-level-node stays refused**, no escape hatch.
6. **Sentinel memory probe:** read-only `execute` snippet printing a nonce-anchored count line, anything else is unreadable.
7. **Tests:** rewrite stub and probe, one whitelist, a mutation matrix for the guard, nothing beyond.
8. **No operator authorization needed** (no money, scope, priority, production mutation, legal or brand call); record the engine decision as an ADR.
9. **Read-only guidance:** `read_skill` registered 1:1 onto the REPL tool; `get_editor_state` returns `get_app_state` text only, accepts and ignores `include_schema`; `batch_design` replies pass the `## issues detected:` block through (not an error, does not skip the save).
10. **Plan-review follow-ups:** keep the 9 stubs; cut `get_style`; drop adapter-side export renaming and return only engine-printed paths that resolve inside the validated output dir; contain `outputDir` inside the realpath of `process.cwd()` or `dirname(outFile)` with no symlinked component; binary identity check as in 3.

11. **Deepen-pass rulings:** (1) canonical-JSON fingerprint with a 3 x 100 ms post-save read retry before the baseline becomes unknown; (2) the raw-DSL path bypass of `export_nodes` validation is accepted and recorded in the ADR, with one probe case pinning current engine behaviour (switch to a shadowing prelude only if the probe shows `Export` overwriting arbitrary files or reading `file:` urls); (3) export and screenshot persistence use a shared `containedDir()` helper (realpath, `lstat` per component, separator-bounded root, root excludes `/` and `$HOME`), adapter-written screenshots use the `wx` flag, no staging directory; (4) prompt at the end of the buffer plus a 50 ms quiet period, bytes after the prompt mean desync (kill and respawn), `Saved <path>` compared by string equality after realpath of both sides (parent directory realpath when the file is missing); (5) a stale refusal echoes the refused operations (64 KiB cap, redacted) and exports or screenshots made while a refusal is pending are prefixed as rendered from unsaved memory; (6) install from a committed lockfile with `npm ci`, credential variables unset, `--ignore-scripts` if the live probe passes (measured: a scratch install with scripts ignored exported and screenshotted fine), no `--min-release-age`; (7) child cwd is a private empty temp directory, empty and relative PATH entries are dropped, `PENCIL_BINARY` is honoured only for a regular file owned by the current uid and not group- or world-writable (stub tests create stubs mode 0755).

CPO sign-off at plan time (single-user-incident threshold): **yes**, with two conditions carried into the
phases below (a refused save must say how to recover, with the recovery path tested; update every prose
reference to a retired tool including the post-save hard gate at `ux-design-lead.md` step 3.2). CPO named
no operator-only decision.

### Refinements the plan makes to the rulings (recorded, not new forks)

- **Baseline states are tagged**, not nullable: `none` (no target bound), `missing` (file absent at capture), `hash`, `unknown` (a post-save read failed or the save reply was not confirmed). `decideStale` allows only an exact `missing`/`hash` match and refuses every other state.
- **Baseline for a blank-but-present file.** Ruling 4 maps "missing or blank" to one state. The plan keeps them distinct: `missing` only for an absent file, and the hash of the (empty) bytes for a present file. A blank file appearing behind the session is a change; fails safe.
- **Baseline is captured from `outFile` immediately before every spawn** into a local, and committed next to `outputFile` only when the spawn reaches its prompt, for all three load shapes. What must not be overwritten is `outFile`.
- **Precedence of refusals:** the existing `decideSave` runs first so the empty-over-non-empty and unrecognizable messages keep their text; the stale check runs second and before `send("save")`, on a fresh read taken after the memory probe.
- **`read_skill` path:** `^(guide/)?[a-z0-9-]+\.md$` (one optional `guide/` prefix, lowercase file name), tighter than the character-class regex in the ruling and with no traversal surface.

## Proposed Solution

### Adapter tool translation (agent-facing names unchanged)

| MCP tool | REPL line the adapter emits | Notes |
|---|---|---|
| `open_document` | spawn `pen interactive --out <f> [--in <f>]` | existing flow (symlink/.pen refusal, template refusal, open-failed state); baseline captured pre-spawn; clears `refusalPending` on success |
| `save` | `save()` | only inside `guardedSave`; one emission site |
| `batch_design({operations})` | `execute({ input: "<preamble>\n<operations>" })` | preamble `var I=Insert,U=Update,C=Copy,R=Replace,M=Move,D=Delete,G=Generate;`; auto-save after success; the reply ends with one `Document: <abs outFile>` line so parallel agents can see which file a call hit |
| `get_screenshot({nodeId})` | `execute({ input: 'TakeScreenshot([<id>])' })` | id validated `^[A-Za-z0-9_-]{1,100}$` and embedded via `JSON.stringify`; the JSON array is parsed from the UNtruncated reply text (the 64 KiB classifier cap would break it), capped at 8 MiB, malformed JSON is an `isError` result; the saved copy goes through `containedDir()` with the `wx` flag; the same unsaved-memory prefix applies |
| `export_nodes({nodeIds,outputDir,format,scale,quality})` | `execute({ input: 'Export([<ids>], "<fmt>", "<abs dir>", {scale,quality})' })` | ids as above, at most 50; `format` enum png/jpeg/webp/pdf; `scale` finite 0.1 to 8; `quality` integer 1 to 100; `outputDir` must be absolute (a relative path is rejected with the reason), resolved through the shared `containedDir()` helper (Technical Rulings 11.3) and checked before any `mkdir`; the reply starts `Exported to: <abs dir>`, lists any same-named files that already existed there, and returns only the `Exported <path>` lines whose path resolves inside that directory; while a refusal is pending it is prefixed `WARNING: rendered from unsaved memory, not the file on disk`; no rename |
| `get_editor_state({include_schema})` | `get_app_state()` | `include_schema` accepted and ignored (stated once in the tool description) |
| `get_variables` | `execute({ input: 'Print(GetVariables())' })` | |
| `read_skill({path?})` | `read_skill(...)` | read-only; path `^(guide/)?[a-z0-9-]+\.md$`; reply capped, redacted, never parsed |

Every command line still flows through one formatter in `pencil-repl-surface.mjs` that refuses a tool or key
that is not in its table; the table now lists `execute`, `get_app_state`, `read_skill` and `save`.

### Save path (shared by auto-save and the explicit `save` tool)

```text
one exclusive queue job:
  disk1 = read outFile bytes once                 (ENOENT -> missing)
  diskCount = diskTopLevelCount(utf8(disk1))      existing, unchanged
  memory probe only when diskCount > 0            execute count snippet with a per-call nonce
  decideSave(...)                                 existing predicate, unchanged -> existing refusal text
  disk2 = read outFile bytes again, NOW           (the stale decision uses this read, not disk1)
  decideStale({ baseline, current: fingerprint(disk2), refusalPending })   NEW -> refuse   (fingerprint = sha256 of canonical JSON)
  send(save())                                    the only emission
  reply must match ^Saved <abs outFile>$          otherwise: not confirmed -> baseline unknown, isError
  confirmed: baseline = sha256(read outFile)      read failure -> success reply + warning, baseline unknown
```

The stale refusal text states: the file was not modified; it changed on disk since this session loaded or
last saved it (another session, git, or an editor such as Pencil Desktop); edits made since are not
persisted and re-opening discards them; stop editing, call `open_document` on the file, then replay the
refused operations in order; keep one writer per file (there is no lock); do not delete or recreate the file
to bypass this check. The refused operations (64 KiB cap, redacted) are echoed after the text so the replay does
not depend on the agent's context. If `open_document` itself fails on the changed file the text says to stop,
not retry or recreate it, and tell the user the file was changed by another tool. With `refusalPending` set
after a restart the text says the session restarted and the earlier edits were discarded; the unconfirmed-save
state has its own wording (the last save was not confirmed, not that the file changed). No re-baseline flag
exists. Every refusal also writes one `[pencil-adapter] REFUSED save: [reason=<code>] <file> ...` stderr line
(codes: stale, missing, unknown-baseline, refusal-pending, empty, unrecognized) from one `logRefusal(saved, via)`
helper that the auto-save and the explicit `save` tool both call; hashes appear only as 8-hex-char prefixes.

## Implementation Phases

Test-first per `cq-write-failing-tests-before`: each phase starts with its failing tests.

### Phase 1: Engine migration (#11156)

- 1.1 Tests and captured evidence first.
  - Capture one real, redacted 0.3.13 transcript (prompt, banner, `OK`, `## Print output`, `Saved <path>`, `Save failed:`, `Unknown tool:`; credential, absolute paths and any `fileToken` removed) into `plugins/soleur/test/fixtures/pen-0.3.13-transcript.txt`, and assert the stub reproduces each shape from it.
  - Update `pencil-repl-surface.test.ts` (new table, snippet escaping, validators including length caps and the `read_skill` pattern, prompt constant, Node floor compare distinguishing 22.18.x from 22.19.0), `pencil-response-classification.test.ts` (`Save failed:` is an error; `Unknown tool:` kept; node-name lines cannot trip it), `pencil-error-enrichment.test.ts` (new hint table; the `edits`/`editId` retry advice rewritten to "re-send the corrected operations with batch_design"; the `/id` hint stops naming `batch_get`).
  - Rewrite `fixtures/pencil-stub-repl.mjs` to the measured shapes; it imports the table and prompt constant from `pencil-repl-surface.mjs`. New capabilities the matrix rows need: `execute` recognises the adapter's count snippet by an anchored regex, extracts the nonce and answers the count line (flags `countForgery: wrongNonce | duplicate | missing`); `rewriteOnStart: <doc>` writes `--out` after loading `--in` and before the first prompt; `rewriteOnProbe: <doc>` writes `--out` just before answering the count probe (no timers, no test-side sleeps; each case also asserts the stub log shows the probe or the `ARGS` line, so a case where it never ran is not vacuous); `saveReply: "<text>"` and `saveWrites: false` script the save reply; `failSave` answers the measured `Save failed: <reason>` shape without writing; the stub logs `ENVKEYS` (key names only) and `CWD` at start; `echoKey` echoes `PEN_CLI_KEY` and `echoKeySplit` writes it to stderr in two chunks 50 ms apart; a `STUB_TAG` wrapper (one-line module in `test/lib/`) suffixes `.log`, `.pid` and `.flags` so two sessions on one path do not share side channels; the crash helper polls `process.kill(pid, 0)` until `ESRCH` (20 ms, 5 s ceiling) instead of a fixed sleep. `connectAdapter({ keys })` sets exactly the key names given (empty strings allowed, default `PEN_CLI_KEY: "stub-key"`); `installAdapter` strips both names before `npm ci`; stub files are created mode 0755.
  - The transcript fixture is a sequence of `> command` and `< reply` blocks with `<PATH>` and `<NONCE>` placeholders and a header `engine: @pen.dev/cli@0.3.13 captured <date>`; a test replays every command through the stub and compares normalised replies byte for byte, a second asserts the header version equals the pin in `check_deps.sh` (a pin bump forces a re-capture), a third asserts no UUID, key-shaped string or e-mail address. A shared `scrubTranscript()` (keys in raw and encoded forms, `$HOME` and absolute paths to placeholders, every UUID including `fileToken` to a fixed synthetic one, e-mail and account lines removed) produces both this file and `probe-transcript.md`, and fails the run if `gitleaks detect --no-git` reports a finding. It must include the count-probe exchange, `get_app_state`, a `TakeScreenshot` reply, an `Exported` line, and a record of whether ANSI codes appear on piped stdout.
  - Rewrite the key-gated `engine-contract-probe.sh` cases (they stay RED against the old adapter): prompt, `OK` prefix, nonce count round trip, `Saved`, `Save failed:`, every one of the 9 removed names answers `Unknown tool:` live, every `export_nodes` format and the `quality` option have an observable effect, `read_skill` on every guide path followed by an intact `save()` reply, no engine write outside `save()` (one fresh session per exit path: first a positive control where the same edit plus `save()` does change the bytes, then edit and exit via SIGTERM, SIGKILL or `exit()`, poll `kill -0` until the process is gone, compare bytes; the child is found by a process lookup on the unique mktemp output path; a timed autosave outside the observation window is a stated limit), a `batch_design` script calling `Export` and an image fill with an absolute `url` against paths outside the document directory (the probe records what the engine does and pins it; if it overwrites arbitrary files or reads local files the plan switches to a shadowing prelude, CTO ruling 11.2), a rewrite of the file with an unrecognised `version` followed by `open_document` (record the engine's answer), and a canary `PEN_CLI_KEY=CANARY-<random>` run asserting the canary and its base64 and URL-encoded forms appear nowhere in adapter stderr or any tool result. The probe resolves its key once as `${PEN_CLI_KEY:-${PENCIL_CLI_KEY:-}}`, passes it explicitly to `connectAdapter` (no stub default against a live engine), redacts that value in `check()`, begins by asserting `pen status` reports Active (a fail-open engine must not yield `PROBE OK`), prints `PROBE SKIPPED (no key)` with the distinct exit code 3 when the key is absent, and carries the `pyramid-justified: the real engine is the only oracle for the contract` marker in its header comment (the PR body also carries a `## Test Pyramid` block).
- 1.2 `pencil-repl-surface.mjs`: new `REPL_SURFACE` (execute, get_app_state, read_skill, save), `REPL_PROMPT`, builders for batch_design / screenshot / export / variables / count, validators, `planSpawn` unchanged (one read feeds exists, size and hash), header and comment rewritten for `@pen.dev/cli` 0.3.13. `jsonLine` escapes `\u007f`, `\u0080` to `\u009f` and `\u0085`, `\u2028`, `\u2029` (written in escape notation per `cq-regex-unicode-separators-escape-only`). The nonce is `crypto.randomBytes(16).toString("hex")` generated after the previous reply is consumed; the count snippet is one self-contained IIFE using only `Get`, `Print` and a literal, printing `TOPLEVEL_COUNT:<nonce>:<n>`; a stub test runs a prior script that declares `var n,c,Print` and asserts the next save still works. A pure rolling-tail redactor lives here and is unit-tested with split chunks.
- 1.3 `pencil-response-classify.mjs`: add `^Save failed:`; keep `^Error:`, `^\[ERROR\]`, `^Unknown tool:`; replace the `pencil login` backtick pattern (the engine's `Authentication required` line is already covered by `^\[ERROR\]`) and drop the dead 0.2.9 comment.
- 1.4 `pencil-error-enrichment.mjs`: an explicit hint for each of the 9 stubs, one table that also feeds the stub handlers (batch_get: run `Get`/`Print` inside batch_design, noting that a batch_design call also auto-saves, or use `get_editor_state` for the top-level list; snapshot_layout: layout problems arrive as `## issues detected:` on batch_design replies; get_guidelines: `read_skill({ path: "guide/<name>.md" })`; set_variables and find_empty_space_on_canvas: `SetVariables(...)` / `FindEmptySpace(...)` inside batch_design; style-guide tools: `read_skill()` style archetypes; search_all_unique_properties and replace_all_matching_properties: read with `Get`, change with `Update` inside batch_design). A test asserts each hint names a tool that exists in the new surface and answers the same before and after `open_document`.
- 1.5 `pencil-mcp-adapter.mjs`:
  - Node gate 22.19.0 as a numeric `[major, minor, patch]` compare; the exit message names the installed and required versions and `bash check_deps.sh`, and `ux-design-lead.md` tells the agent to relay it verbatim and stop.
  - Credential: the argv `-e` parser accepts only `PEN_CLI_KEY` and `PENCIL_CLI_KEY` (other names are ignored with a value-free stderr line) and, when the key arrived that way, writes a stderr line that argv is visible to other local users; the key is resolved once into a module-level trimmed `const` (empty or whitespace is unset), both names are then deleted from `process.env`, and `buildPencilEnv` and the redactor read only that const; redaction covers raw, trimmed, JSON-escaped, `encodeURIComponent` and base64 forms (length at least 4) across a rolling stderr tail; the child env carries `PEN_CLI_KEY` only; one value-free deprecation line on the fallback.
  - Child process: spawned with `cwd` set to a private empty temp directory (removed on exit; the engine receives absolute paths only), empty and relative PATH entries dropped, `PENCIL_BINARY` honoured only for a regular file owned by the current uid and not group- or world-writable (each use writes a value-free stderr line); the probe records what `pen interactive` opens from cwd and its ancestors.
  - REPL framing: the prompt must be at the END of the buffer followed by 50 ms of quiet; bytes after the prompt are a desync (kill the child, restart from the saved file, report it). The save confirmation is string equality of the trimmed, ANSI-stripped reply with the literal word Saved, one space, then the path, after `realpathSync` of both sides (the parent directory's realpath when the file is missing). Stub tests: a node name containing a newline then the prompt text, and a `read_skill` reply with a prompt-shaped line, each followed by an intact `save()`.
  - Shared `containedDir()` helper for exports and screenshots: realpath of the requested directory, `lstat` of every existing component (symlinks refused, missing components created one at a time and re-checked), separator-bounded containment in the allowed root (`process.cwd()` realpath or `dirname(outFile)`; a cwd equal to `/` or `$HOME` is excluded), adapter-written files use `writeFileSync(path, bytes, { flag: "wx" })`. Tests: symlinked leaf and symlinked `screenshots` directory refused, cwd equal to `$HOME` falls back, a `/tmp`-style symlinked root accepted when the real path is inside the root, relative `outputDir` rejected, an overwrite listed.
  - Refused work: a stale refusal appends the refused `batch_design` operations (64 KiB cap, redacted); a three-operation replay where operation 3 refers to a node created by operation 1 succeeds after re-open (the replay test uses names the script itself binds, not ids from the previous session).
  - `findPenBinary()`: `~/.local/share/pen-cli/node_modules/.bin/pen` only; `realpathSync` of it must EQUAL the package's declared `bin.pen` target (resolved from the realpath'd package directory), the package `name` must be `@pen.dev/cli`, a version other than the pin warns; `spawn()` passes that realpath to `node`, so a link swapped between resolution and a respawn is not followed; no PATH fallback; `PENCIL_BINARY` keeps its name (absolute path, constraints above). Guard 2's property is reworded: mis-pointed or colliding bin links are refused; tampering by the same user is out of scope.
  - Spawn args unchanged; prompt detection uses `REPL_PROMPT`; register the 8 live tools and the 9 stubs; screenshot, export, variables, editor-state and skill handlers per the table; `Document:` line on `batch_design` replies; `buildPencilEnv` allowlist updated. `pencil-adapter-sentinels.test.ts` pins the success-side lines `[pencil-adapter] MCP server started on stdio` and `Opened ... top-level node(s) loaded` so the migration cannot drop them.
- 1.6 `pencil-save-gate.mjs`: `memoryTopLevelCount` becomes the nonce-anchored parse (exactly one matching line, otherwise `null`); the module header drops the "known limit" lines that #11168 closes.
- 1.7 `check_deps.sh`: install the CLI from the committed `scripts/pen-cli/package.json` and `package-lock.json` (copied to `~/.local/share/pen-cli`, `env -u PEN_CLI_KEY -u PENCIL_CLI_KEY npm ci`, `--ignore-scripts` if the live probe passes; adding this fifth lockfile directory follows ADR-191's procedure, so the work phase edits the `ci.yml` lockfile-sync job, `.github/dependabot.yml` and the dependabot-drain pins it names); the old `~/.local/node_modules/.bin/pencil` is left alone, so an old adapter copy still finds its own old engine and the new engine can never be reached through the old bin name, and `--check-adapter-drift` reports `DRIFT` on a stale adapter copy (a shell test builds a fake `~/.local` holding `@pencil.dev/cli@0.2.9` and a stale adapter and asserts exactly this); `detect_headless_cli` recognises only the new prefix's `.bin/pen`; `detect_pencil_cli`'s negative guard also excludes the pen package path; a leftover `@pencil.dev/cli` prints one warning line; the auth check runs `PEN_CLI_KEY="<non-empty PEN_CLI_KEY or PENCIL_CLI_KEY>" node <pen> status`; Node floor 22.19.0 in `find_node22` and its messages (numeric compare, tested); trace guard covers both variable names (a test sets each name alone); path resolution uses a `realpath`-or-`node -e` fallback instead of `readlink -f` (macOS).
- 1.8 `engine-contract-probe.sh`: signature diff against `pen interactive --help` (`# tool({ ... })` blocks still parse) for the REPL tools; round trip through the INSTALLED adapter (open, batch_design twice, save, reload, screenshot, export, empty-over-non-empty refusal, stale refusal behind a real engine); `PEN_CLI_KEY` gate with the `PENCIL_CLI_KEY` fallback; `PENCIL_BIN` defaults to `.bin/pen`; trace guard covers both names. The redacted transcript is written to `knowledge-base/project/specs/feat-one-shot-11156-11168-pen-cli-migration/probe-transcript.md` for `soleur:ship` to fold into the PR body.
- 1.9 Prose and docs:
  - `pencil-setup/SKILL.md`: registration with `PEN_CLI_KEY` and the fallback, engine contract, Node 22.19, one-writer-per-file rule and the Pencil Desktop caveat, the read-via-batch_design auto-save side effect, silent-drop checklist wording kept so the anchor `ex-cq-pencil-mcp-silent-drop-diagnosis-checklist` stays. In this repo the collapse hook asks for a snapshot before a re-open: copy the `.pen` aside first, then follow the refusal's re-open advice.
  - `ux-design-lead.md`: prerequisite line, guidance and grammar steps (headless: `read_skill`; Desktop and IDE wording kept), drop `snapshot_layout` for headless, the post-save hard gate runs a `node -e` snippet (Node 22.19 is guaranteed; no `stat -c`, no `jq`): sha256 of the file before the first edit, then after the final save assert size over 128 bytes, `children.length` of at least 1, a sha256 different from the pre-edit one, and that no `batch_design` or `save` result in the session contained `REFUSED save:` (otherwise report incomplete and surface the text); step 3.2 also tells the agent to copy the first line of any `REFUSED save:` result verbatim into the wireframe summary it commits (the durable artifact); a bash test runs the documented snippet on a 96-byte empty document, an unchanged file after a refusal and a valid saved file; export step says the adapter no longer renames and the agent renames as step 3.4 already directs. The three generated mirrors are regenerated by their sync scripts.
  - A parse test over the headless-branch lines of `ux-design-lead.md` and `pencil-setup/SKILL.md` asserts every `mcp__pencil__*` or bare tool name is one of the 8 live tools or sits on a line marked Desktop/IDE; `pencil-setup/SKILL.md` gains a `REFUSED save:` reason table (each `reason=` code to its recovery step) and its first triage step is the tool result and stderr marker, with no `ssh`, `docker exec` or `systemctl`.
  - `brainstorm/SKILL.md`, `plan/SKILL.md` (byte-neutral pointer to `pencil-setup/SKILL.md`), `brainstorm-brand-workshop.md` case pattern (`*@pen.dev/cli*`), `knowledge-base/project/constitution.md` headless-auth line.

### Phase 2: Stale-file save guard (#11168), on the Phase 1 structure

- 2.1 Tests first (see Guard Contract): `pencil-save-gate.test.ts` for `fingerprintBytes` (Buffer or string input), `decideStale` over the four baseline states, and `runGuardedSave` ordering; `pencil-adapter-stub-repl.test.ts` cases for stale refusal, own-save re-baseline, re-open recovery that actually replays the refused edit and saves, smaller-over-larger behind the session, two sessions on one file, refusal then crash respawn, file removed behind the session; `pencil-adapter-sentinels.test.ts` for the single emission and the baseline write sites.
- 2.2 `pencil-save-gate.mjs`: `fingerprintBytes`, tagged baseline states, `decideStale({ baseline, current, refusalPending })`, a `stale` argument on `refusalMessage({ file, source, stale })` (the observability probe calls it), and `runGuardedSave` extended with a baseline get/adopt pair, a fresh-read dep and a confirmation hook so ordering stays unit-testable without the MCP SDK. `readDisk` returns bytes (`Buffer|string|null`); the count decodes utf8; `fingerprintBytes` hashes the canonical JSON (`JSON.stringify(JSON.parse(text))`, BOM stripped, reusing the parse the count already does) and falls back to the raw bytes only when the text does not parse. Only `ENOENT` maps to `missing`; any other read error maps to baseline `unknown` with `cause=capture-failed` and a stderr line carrying `err.code`, never swallowed. Every disk read inside the save job opens `O_RDONLY|O_NOFOLLOW`, `fstat`s the descriptor, requires `isFile()` and a size of at most 64 MiB (a violation is `unknown`, refused), and the baseline, the fresh read and the engine's `--out` all use one canonical path (`realpathSync(dirname(outFile))` plus the basename, computed once at `open_document`). The post-save read retries 3 times at 100 ms before the baseline becomes `unknown`, and a read failure after a confirmed `Saved` returns a success reply with a warning (no duplicate re-apply).
- 2.3 `pencil-mcp-adapter.mjs`: a small `SaveBaseline` object with private fields and `capture` / `commit` / `clear` / `adopt` / `matches`; the baseline is captured from `outFile` into a local immediately before `nodeSpawn` and committed next to `outputFile` when the prompt arrives; `clearTarget()` clears it; `refusalPending` is set on a stale refusal and cleared only by a successful `open_document`; a respawn does not recapture while it is set; `guardedSave` wires the pair; the explicit `save` tool and the auto-save reach it only through `guardedSave`.
- 2.4 `SKILL.md` sharp edge "Save sentinel" gains the stale rule, the recovery, the real window it cannot close (a second writer between the fresh read and the engine's write, and whatever lands between the engine's write and the post-save read), and the note that a change during engine startup refuses the first save.

### Phase 3: Verify and record

- 3.1 `bun test plugins/soleur/test/pencil-*.test.ts` and the pencil `*.test.sh` suites green; `bash scripts/test-all.sh` green; `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --check-adapter-drift` prints `OK` or `NOT_INSTALLED`.
- 3.2 Live: `doppler run -p soleur -c dev -- bash plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh` prints `PROBE OK`, including the issue's acceptance round trip.
- 3.3 ADR (below), `technical-ruling-gate.sh --branch` green, markdownlint on the plan and `tasks.md`, and the PR body (`Closes #11156`, `Closes #11168`) with the probe transcript folded in by `soleur:ship`.

## Files to Edit

- `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`
- `plugins/soleur/skills/pencil-setup/scripts/pencil-repl-surface.mjs`
- `plugins/soleur/skills/pencil-setup/scripts/pencil-save-gate.mjs`
- `plugins/soleur/skills/pencil-setup/scripts/pencil-error-enrichment.mjs`
- `plugins/soleur/skills/pencil-setup/scripts/pencil-response-classify.mjs`
- `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`
- `plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh`
- `plugins/soleur/skills/pencil-setup/SKILL.md`
- `plugins/soleur/test/fixtures/pencil-stub-repl.mjs`
- `plugins/soleur/test/lib/pencil-adapter-roundtrip.mjs` (key variable names the harness sets)
- `plugins/soleur/test/pencil-adapter-stub-repl.test.ts`
- `plugins/soleur/test/pencil-adapter-sentinels.test.ts`
- `plugins/soleur/test/pencil-repl-surface.test.ts`
- `plugins/soleur/test/pencil-save-gate.test.ts`
- `plugins/soleur/test/pencil-error-enrichment.test.ts`
- `plugins/soleur/test/pencil-response-classification.test.ts`
- `plugins/soleur/test/pencil-adapter-auth-hard-fail.test.sh`
- `plugins/soleur/test/pencil-setup-skill-cli-form.test.sh` (only if the canonical CLI form it greps changes)
- `plugins/soleur/test/check-deps-adapter-drift.test.sh` (only if the module list or messages it asserts change)
- `plugins/soleur/agents/product/design/ux-design-lead.md`
- `plugins/soleur/skills/brainstorm/SKILL.md`
- `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md`
- `plugins/soleur/skills/plan/SKILL.md`
- `knowledge-base/project/constitution.md`
- ADR-191 lockfile wiring for the new CLI lockfile directory, enumerated by the work phase from the ADR and edited only where it names them: `.github/workflows/ci.yml` (lockfile-sync job), `.github/dependabot.yml`, `scripts/assert-dependabot-drain.py` pins
- Generated mirrors, regenerated by their sync scripts and never hand-edited: `plugins/soleur/opencode/agents/product/design/ux-design-lead.md`, `plugins/soleur/cursor/agents/soleur-product-design-ux-design-lead.md`, `.grok/agents/soleur-product-design-ux-design-lead.md` (the work phase finds the sync commands in `plugins/soleur/scripts/sync-*.ts` and the CI parity check, and runs them)

Verified-unchanged (no edit; `git diff --quiet origin/main...HEAD -- .claude/settings.json .claude/hooks` is an acceptance criterion): `.claude/settings.json` and the two `.claude/hooks/pencil-*.sh` matchers (tool names stable), `copy_adapter.sh` (no new sibling module, so `ADAPTER_FILES` and the five-sibling sentinel stay), `package.json` / `package-lock.json` of the adapter (its dependencies are `@modelcontextprotocol/sdk` and `zod` only; the CLI has its own lockfile under `scripts/pen-cli/`, installed by `check_deps.sh`), `AGENTS.rules.md` (names no engine; rule IDs immutable).

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-304-headless-pencil-adapter-engine-and-tool-surface.md` (ordinal provisional: ADR-303 is already claimed on `origin/feat-one-shot-supabase-public-grants`; the work phase and `soleur:ship`'s ordinal gate re-check the next free number across every `origin/*` ref immediately before merge)
- `plugins/soleur/test/fixtures/pen-0.3.13-transcript.txt` (redacted real transcript the stub's shapes are pinned to)
- `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package.json` and `package-lock.json` (the CLI's own lockfile-pinned prefix; copied to `~/.local/share/pen-cli` by `check_deps.sh`)
- `plugins/soleur/test/fixtures/pen-identity-cases.tsv` (layout, expected adapter verdict, expected `check_deps` verdict; run through both) and a helper in `plugins/soleur/test/lib/` that builds the fake package tree under a temp `HOME`
- `plugins/soleur/test/lib/stub-tag.mjs` (the one-line per-session stub wrapper) and `plugins/soleur/test/pencil-post-save-gate.test.sh` (runs the documented hard-gate snippet on fixtures)
- `knowledge-base/project/specs/feat-one-shot-11156-11168-pen-cli-migration/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-11156-11168-pen-cli-migration/tasks.md`

(`probe-transcript.md` in the same specs directory is written by the live probe run in Phase 1.8 and Phase 3.2.)

## User-Brand Impact

- **If this lands broken, the user experiences:** a wireframe session in which `mcp__pencil__batch_design` reports success while the saved `.pen` is empty, or a refusal on every save so no wireframe can be produced, or an agent that follows stale prose to a tool that no longer exists and stalls the UI-feature gate.
- **If this leaks, the user's workflow data is exposed via:** the adapter's child environment and stderr (the `PEN_CLI_KEY` credential and engine error text that may echo it); a screenshot/export path or a `read_skill` path escaping the intended directory; node names or file content echoed into REPL replies that the adapter then parses.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one customer's design file silently overwritten, or all their wireframe work blocked, is a brand-visible failure on a surface where the adapter's sentinel is the only protection; `aggregate pattern` would understate it. CPO signed off the tier on 2026-10-26 (recorded in the decision-challenges table as a taste row).

Second-order failures the plan also covers (found in the deepen pass): (a) bytes rewritten without a change in
meaning (line endings, a formatter, Desktop normalisation) would refuse every save, so the fingerprint hashes
canonical JSON and the post-save read retries; (b) a file the engine cannot parse blocks `open_document` and
therefore the stale recovery, so the refusal tells the agent to stop and report, and the probe records the
engine's answer; (c) refused edits and exports rendered from them exist only in memory, so the refusal returns
the refused operations and exports are marked as rendered from unsaved memory; (d) the post-save gate must not
pass on a stale file, so it compares sha256 before and after and checks for `REFUSED save:`; (e) a relative or
misplaced export directory is rejected; (f) an old adapter copy or a colliding `.bin/pencil` can never run the
old adapter against the new engine because the new CLI lives in its own prefix. Residual, accepted: a second
writer between the fresh read and the engine's write is not caught, and `batch_design` can reach any path-taking
host function of the engine (ADR-304 records it and the probe pins the current behaviour).

Mitigations in scope: the credential is allowlisted into the child under one name and redacted under both,
including across stderr chunks (CTO ruling 2); the engine is the only thing that writes the `.pen`, behind
the sentinel and the stale guard; `nodeId`, `nodeIds` (count and length), `format`, `scale`, `quality`,
`outputDir` (contained) and `read_skill` paths are validated before they are embedded in an `execute`
snippet or passed to the engine; the count probe prints only a number the adapter generated, tagged with a
per-call nonce, so text from a previous reply cannot forge it; a save is accepted only on a positive
`Saved <path>` reply.

## Observability

Layer 7 (`cli-stdout-artifact`): the adapter executes on the operator's or customer's own machine, with no
Soleur-side sink by design. Hosted path: the plugin tree is vendored into the production image
(`web-platform-release.yml` `vendor_plugin`, which excludes only `plugins/soleur/docs/` and
`plugins/soleur/test/`, then `COPY _plugin-vendored /opt/soleur/plugin`) and loaded by
`agent-runner-query-options.ts`, so these files are present hosted. The adapter is never started hosted because
no hosted `mcpServers` registration names `pencil`: `plugins/soleur/.claude-plugin/plugin.json`, `.mcp.json`
and `plugins/soleur/.mcp.json` carry none, and the hosted servers are `soleur_platform`, `c4McpServers` and the
cron Playwright overlay. If a registration were ever added, the hosted path would be covered by layers 1-3
(stderr to the container journal and Vector). An acceptance criterion pins the claim mechanically.

The signal the agent reads is the MCP tool result plus the adapter's stderr. The durable artifact carrying the
same fields is the first line of any `REFUSED save:` result, which `ux-design-lead.md` step 3.2 tells the agent
to copy verbatim into the wireframe summary it commits next to the `.pen` (a test asserts the instruction is
present); the byte-identical `.pen` after a refusal is asserted by test but is the absence of a change, not the
artifact. Stderr lines (all through `oneLine(redactKey(...))`, hashes as 8-hex-char prefixes):

| Event | stderr line |
|---|---|
| stale refusal | `[pencil-adapter] REFUSED save: [reason=stale] <file> baseline=<hash8> disk=<hash8> via=<auto-save or save>` |
| file removed behind the session | `... [reason=missing] <file> baseline=<hash8>` |
| baseline unknown | `... [reason=unknown-baseline] <file> cause=<unconfirmed-save, post-save-read-failed or capture-failed>` |
| refusal pending set or cleared, crash respawn while armed | `[pencil-adapter] refusalPending=true <file>`, `refusalPending=false <file> (open_document ok)`, `respawn: refusalPending still armed, baseline not recaptured` |
| unconfirmed save | `[pencil-adapter] save unconfirmed: reply did not match the expected Saved line; baseline=unknown` |
| post-save read failed | `[pencil-adapter] WARN post-save read failed (<errno>); baseline=unknown` |
| desync, credential via argv, `PENCIL_BINARY` override, deprecated key name | one value-free line each |

```yaml
liveness_signal:
  what: "adapter stderr line '[pencil-adapter] MCP server started on stdio' at registration time, and the tool result of open_document ('Opened <file> (<n> top-level node(s) loaded)')"
  cadence: "per session start / per open_document call"
  alert_target: "the calling agent (tool result) and the session's MCP stderr log; no Soleur-side sink by design (layer 7 cli-stdout-artifact)"
  configured_in: "plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs"

error_reporting:
  destination: "MCP tool result with isError true (layer 7 cli-stdout-artifact); stderr lines prefixed [pencil-adapter]"
  fail_loud: "REFUSED save: <file> was not modified (stale, empty-over-non-empty, unrecognizable); 'open failed:' refuses every tool until open_document succeeds"

failure_modes:
  - mode: "file changed on disk behind the session (second session, git, editor) and the next save would overwrite it"
    detection: "decideStale compares the SHA-256 baseline with a fresh read inside the save job; REFUSED save text in the tool result (cli-stdout-artifact)"
    alert_route: "calling agent surfaces the text verbatim; file stays byte-identical (durable artifact)"
  - mode: "empty in-memory document over a file that holds nodes, or any save over an unrecognizable file"
    detection: "decideSave (unchanged predicate) using the nonce-anchored count probe; REFUSED save text (cli-stdout-artifact)"
    alert_route: "calling agent; file untouched"
  - mode: "engine contract drift (prompt, reply shapes, tool list) after a CLI bump"
    detection: "key-gated engine-contract-probe.sh signature diff and round trip print PROBE FAILED; the run is required before any pin bump (documented in SKILL.md); a save reply that is not 'Saved <path>' is an isError result in the tool output (cli-stdout-artifact)"
    alert_route: "the engineer running the probe (stdout, non-zero exit); never a required CI job because it needs the credential"
  - mode: "baseline unknown (unconfirmed save, post-save read failed, capture failed) or refusalPending armed after a crash respawn"
    detection: "the sticky refusal text and the matching stderr line above (cli-stdout-artifact); the first line is copied into the committed wireframe summary (durable artifact)"
    alert_route: "calling agent; recovery is open_document then replay, per the SKILL.md reason table"
  - mode: "foreign or mismatched binary refused, Node below 22.19.0, or REPL desync (bytes after the prompt)"
    detection: "adapter startup or spawn error text naming the cause and the fix command (cli-stdout-artifact); desync is a stderr line plus a restart from the saved file"
    alert_route: "claude mcp registration shows the failure; tool result isError"
  - mode: "credential missing for the child"
    detection: "adapter hard-fails at startup before module imports ('PEN_CLI_KEY not set'); the engine's own 'Authentication required' line classifies as an error"
    alert_route: "claude mcp registration fails loudly; tool result isError (cli-stdout-artifact)"

logs:
  where: "adapter stderr (MCP server log of the host CLI); credential redacted under both variable names"
  retention: "host CLI session logs; the refusal text is also in the transcript"

discoverability_test:
  command: node --input-type=module -e "import('./plugins/soleur/skills/pencil-setup/scripts/pencil-save-gate.mjs').then(m=>console.log(m.refusalMessage({file:'x.pen',source:'save',stale:'changed'})))"
  expected_output: "REFUSED"
```

The command is one import of the pure gate module (milliseconds, no test runner) that prints the stale
refusal text, which is the signal the agent reads; it has no network and no credential. It is declared in
Phase 2.2 as the `stale` argument of `refusalMessage`, so the work phase must keep that signature or update
this command in the same change.

## Guard Contract

### Guard 1 — Stale-file save guard with a single save chokepoint

**Property.** A save never replaces a `.pen` whose bytes differ from what this session last loaded or last saved, and the REPL `save` command reaches the engine only through that check.

**Assembly.** The property quantifies over every path that can put bytes into `outFile` or change what the
session believes it loaded, and the chokepoint all of them must flow through. Writers of `outFile`: (1) the
engine's `save()`, emitted at exactly one site inside `guardedSave`, reached by the auto-save in
`registerMutatingTool` and by the explicit `save` tool (two callers, one chokepoint); the engine writes
nowhere else (measured: startup, `exit()` and SIGTERM leave the file untouched; the live probe re-asserts it
with SIGKILL); (2) any external writer (git, an editor, a second adapter process), which the guard cannot
prevent and must detect. Sites that touch the baseline: `capture` once in `spawn()` before `nodeSpawn`,
`commit` next to `outputFile`, `adopt` once in the post-save confirmation hook, `clear` in `clearTarget()`;
the state lives in private fields of one `SaveBaseline` object, so no other spelling can reach it. Members
drift; the structural statements are "one emission site" and "one capture, one adopt".

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make `decideStale` always return allow (or delete its call in `runGuardedSave`): a file rewritten behind the session with a SMALLER non-empty document (5 nodes in memory, 8 on disk) is saved over | RED (stale refusal test, bytes-unchanged assertion) |
| 2 | The guard's own dispatch: the post-save `adopt` never runs; the own-save then save-again case must fail (RED), and the refusal cases assert the count of `save` lines the stub received | RED |
| 3 | Add a SECOND writer after a compliant first: session A saves (re-baselines), a second adapter process saves a different document, session A saves again | RED unless refused with the stale text; a third round (A re-opens, replays, saves) must be ALLOWED |
| 4 | REORDER: capture the baseline after the prompt arrives instead of before `nodeSpawn`; the stub flag `rewriteOnStart` (no timers) rewrites the file after load and before the first prompt and the first save must be refused | RED |
| 5 | REORDER: move the stale decision to the first read (before the memory probe) or after `send("save")`; the stub flag `rewriteOnProbe` rewrites the file when it receives the count probe and the save must be refused, and on refusal the stub must have received no `save` line and the bytes must be identical | RED |
| 6 | Make `fingerprintBytes` size-only, mtime-only or raw-bytes: a same-size rewrite that changes one node value (`seed0` to `seed1`) must refuse; a CRLF-converted or reformatted copy of the same document with a forced future mtime (`utimesSync`, one hour ahead) must be allowed | RED (each mutant fails one of the two cases) |
| 7 | Accept any non-error reply as a confirmed save and adopt whatever is on disk: with `saveReply: ""` and `saveWrites: false`, then a foreign write, the next save must refuse and the foreign bytes must not become the baseline; with `Saved <other path>` the result is `isError`; after one `Save failed:` and a retry the refusal uses the unconfirmed-save wording (distinct from the stale and restart wordings) and a re-open then allows the save | RED |
| 8 | After a stale refusal, a crash respawn recaptures the baseline: a refused save, a stub crash, a respawn, then a save must STILL be refused (`refusalPending`), with the restart wording | RED |
| 9 | Harness row: the stub always answers `Saved` and never `Save failed:`; a failed save must surface as an error and must not re-baseline | RED |
| 10 | Structural: add a second `formatReplCommand("save"` emission, a raw `save()` string literal outside the surface module, or a second `.adopt(`/`.capture(`/`.commit(` call site in the adapter OR in `pencil-save-gate.mjs` (the sentinel scans both files after comment stripping and `SaveBaseline` has `#`-private fields only); the scan itself reads an empty string; `decideStale` is called at more than one site or not between the memory probe and the `save` emission | RED (each; the scan asserts it found at least one of each site, as the existing emission scan does) |
| 11 | Must-PASS non-canonical: a session that loads from a template `inputPath` onto an absent `--out`, then a clean first save, then an edit and save | PASS |
| 12a | Must-PASS: an external rewrite with identical content (new mtime) between two saves, and one injected transient `EBUSY` on the post-save read (the retry absorbs it) | PASS |
| 12b | A file removed behind the session, and a FIFO or a symlink swapped in after `open_document` | RED, each with its own reason (never `missing` for a non-`ENOENT` error) |
| 13 | Remove the nonce comparison and take the first count-looking line: the stub's `wrongNonce` flag must make the save refuse on an unreadable count where the true count would have refused it | RED |

**Anchor.** The baseline is a stored value compared with the thing it protects, and one process owns both,
so a code edit could weaken the guard together with its test. What outside the commit must also move for a
weakening to pass: the stub-REPL test (separate fixture, separate file), the source sentinel that pins the
emission and the baseline sites, the captured real transcript the stub is pinned to, and the key-gated live
probe case that rewrites the file behind a real engine session and asserts `REFUSED save:` with the file
byte-identical.

### Guard 2 — Binary identity before the credential is handed over

**Property.** The credential is passed only to the `pen` binary the installed `@pen.dev/cli` package declares as its own `bin`; mis-pointed or colliding bin links are refused (tampering by the same user is out of scope).

**Assembly.** Every resolver and every place that runs the CLI: `findPenBinary()` in the adapter,
`detect_headless_cli` and the `detect_pencil_cli` negative guard in `check_deps.sh`, the auth check that
runs `pen status`, the default in `engine-contract-probe.sh`, and the registration text in `SKILL.md`. They
must agree on one rule (realpath inside the package directory, separator-bounded, `package.json` name
`@pen.dev/cli`); `PENCIL_BINARY` is the one documented override (registrant trusted, used by the stub
tests).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Point `.bin/pen` at a file under a sibling directory whose name merely starts with the package path (`.../@pen.dev/cli-evil/x.mjs`), or at another file inside the package that is not the declared `bin.pen` target | RED (refused: equality with the declared target, separator-bounded) |
| 2 | Point it at the deprecated `@pencil.dev/cli` install, or a package whose `package.json` name differs | RED (refused, with the leftover-package warning from `check_deps.sh`) |
| 3 | Zero candidates: no `.bin/pen`, and a foreign `pen` earlier on PATH | RED (adapter errors; it never spawns the PATH binary) |
| 4 | A second resolver disagrees: `check_deps.sh` accepts a target the adapter refuses (or the reverse) | RED (shared fixture table run through both) |
| 5 | Must-PASS: a correct install whose package version differs from the pin | PASS with a stderr warning |
| 6 | `PENCIL_BINARY` pointing at a group-writable file, a file owned by another uid, or a symlink | RED (override ignored with an error); a mode-0755 regular file owned by the current uid is must-PASS |
| 7 | A leftover `@pencil.dev/cli` with `.bin/pencil` at its old location and a stale adapter copy | RED for the new tier selection (never routed to the old engine); `--check-adapter-drift` prints `DRIFT` |

**Anchor.** The pin and lockfile live in `check_deps.sh` and `scripts/pen-cli/`, the identity rule in the adapter;
a weakening must edit both plus `pen-identity-cases.tsv` (run through the adapter side as integration and the
`check_deps` side as a shell test), and the live probe asserts the real `.bin/pen` resolves.

## Architecture Decision (ADR/C4)

### ADR

Create `ADR-304-headless-pencil-adapter-engine-and-tool-surface.md` through `soleur:architecture` as a Phase 3
task (CTO ruling 8). Decision in one line: the headless Pencil adapter targets the maintained `@pen.dev/cli`
at an exact pin and keeps the `mcp__pencil__*` names stable by translating them inside the adapter, retiring
tools the engine cannot honour as hinted stubs. Keep it short: the measured contract lives in
`pencil-setup/SKILL.md`, not the ADR. Alternatives Considered: rename to native tool names (hook and prose
churn), expose raw `execute` (bypasses the save and open guards), shim `batch_get` over `Get()` (invents a
format), stay on the deprecated 0.2.9 (flip conditions recorded in #11156 are met by operator request).
Records: `batch_design` forwards raw DSL so engine host functions that take paths are reachable without `export_nodes` validation, accepted with one probe case pinning current behaviour (switch to a shadowing prelude if the probe shows arbitrary overwrite or local file reads); the new CLI prefix and its lockfile (ADR-191's fifth lockfile directory); the stale-guard threat model and the real window it cannot close; the QuickJS-sandbox measurement as
the residual-risk statement for `batch_design`; the CLI's transitive dependencies run with the credential in the child's environment, now pinned by a committed lockfile and installed without scripts if the probe passes; the stub-only
tests cannot catch engine drift, the key-gated probe is the oracle and is deliberately not a required CI job.
The ordinal is provisional (see Files to Create).

### C4 views

No C4 change. All three model files (`model.c4`, `views.c4`, `spec.c4`, 1,228 lines) are read in the work
phase and the result recorded in the PR; the plan-time evidence: a case-insensitive search of all three for
`pencil` and `pen.dev` returns nothing, and the model covers the plugin, the harnesses and generic MCP
connections but not design tools. Enumerated against the feature: (a) external human actor: none added or
changed; (b) external system: the pen.dev cloud usage endpoint the CLI calls from the operator's machine is a
dev-tool vendor edge that was unmodelled before and after (a package rename, not a new edge); (c) data store:
local `.pen` files, unmodelled, unchanged; (d) actor-to-surface access relationship: unchanged. The
derived cardinalities `c4-count-parity` gates are untouched; `plugins/soleur/test/c4-count-parity.test.sh` is
run green in Phase 3.

### Sequencing

The decision is true as soon as the PR merges; no later slice.

## Domain Review

**Domains relevant:** engineering, product

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled the forks (summarized under Technical Rulings) and recorded no dissent and no operator-only item. Main risks named: embedding ids and paths into `execute` snippets (validated), parsing replies that can carry node names (count probe prints only a nonce-tagged number), confusing the two package bins (resolve only inside the installed package).

### Product

**Status:** reviewed
**Assessment:** CPO signed off (`requires_cpo_signoff: true`): approach and the `single-user incident` tier accepted; conditions carried into Phases 1.9 and 2 (recovery text and tested recovery path; every prose reference to a retired tool updated including the post-save hard gate; exact pin; real-engine smoke before declaring done). Operator-only decisions: none.

### Product/UX Gate

**Tier:** none
**Decision:** not applicable. The Files lists contain no UI-surface path (no `components/`, `app/**/page.tsx`, layout or modal files); the plan changes tooling that produces wireframes, not a user-facing page.
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

GDPR gate: not invoked. No schema, migration, auth flow or API route is touched, and none of the four cross-controller triggers fire: the adapter already ships in the plugin, and the CLI's egress is to the pen.dev API it already used (the `Generate` function is reachable only through agent-authored `batch_design` scripts, unchanged in kind from 0.2.9). The work phase records the endpoints observed during the live probe; `deepen-plan` runs the data-integrity, security and architecture lenses before work starts.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "migrate the headless Pencil MCP adapter (plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs) from the deprecated @pencil.dev/cli onto @pen.dev/cli" [brief] | Phase 1 | mapped |
| 2 | "pencil adapter save sentinel must refuse a save when the file changed on disk since this session loaded or saved it" [brief] | Phase 2, Guard 1 | mapped |
| 3 | "remember a content hash or size+mtime after every load and save" [brief] | Phase 2.2-2.3 (SHA-256, CTO ruling 4) | mapped |
| 4 | "a smaller non-empty document must not replace a larger one after an on-disk change behind the session" [brief] | Guard 1 matrix row 1 | mapped |
| 5 | "Implement #11168 on the new @pen.dev/cli adapter structure so it is not built twice." [brief] | Phase 2 sequenced after Phase 1; one PR | mapped |
| 6 | "Close both issues with Closes #11156 and Closes #11168 in the PR body." [brief] | Phase 3.3 | mapped |
| 7 | "Adapter on `@pen.dev/cli` passes the stub-REPL integration test and the key-gated live contract probe introduced by #11143." [issue #11156] | Phases 1.1, 1.8, 3.2 | mapped |
| 8 | "A wireframe round trip works end to end: open, edit, export screenshots, save, reload." [issue #11156] | Phase 1.8, 3.2 | mapped |
| 9 | "The empty-overwrite save sentinel from #11143 still guards every write site." [issue #11156] | Phase 2.1, Guard 1 row 10 | mapped |
| 10 | "`pencil-repl-surface.mjs` signature table, `planSpawn`, the `batch_design` alias preamble" (retirement list) [issue #11156] | Phase 1.2 and Research Reconciliation (table rewritten; `planSpawn` and preamble kept because measured still needed) | mapped |
| 11 | "`@pencil.dev/cli@0.2.9` pin in `check_deps.sh`; the auth variable (`PENCIL_CLI_KEY` to `PEN_CLI_KEY`)" (retirement list) [issue #11156] | Phase 1.5, 1.7 | mapped |
| 12 | "Keep: the empty-overwrite sentinel's predicate and refusal text, the exclusive queue section, `copy_adapter.sh` completeness check." [issue #11156] | `decideSave` and queue unchanged; `copy_adapter.sh` unedited | mapped |
| 13 | "a legitimate \"delete every top-level node\" is refused for good (memory 0 over disk N); the refusal tells the caller to open a new path, so confirm that is acceptable." [issue #11168] | CTO ruling 5 (stays refused) | mapped |
| 14 | "Verify this yourself against the installed CLI if feasible (note engines.node >= 22.19.0, auth var rename PENCIL_CLI_KEY -> PEN_CLI_KEY)." [brief] | Research Insights measured table; Phase 1.5/1.7 | mapped |
| 15 | "how to keep the `mcp__pencil__*` tool surface stable for agents/hooks vs renaming" [brief] | CTO rulings 1, 9, 10 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Adapter, repl-surface, classify, enrichment, check_deps, probe, SKILL.md of pencil-setup | "migrate the headless Pencil MCP adapter" (ask 1) | asked |
| `pencil-save-gate.mjs` stale guard and adapter baseline | "refuse a save when the file changed on disk since this session loaded or saved it" (ask 2) | asked |
| Stub fixture and the six pencil test files | "passes the stub-REPL integration test" (ask 7) | asked |
| `engine-contract-probe.sh` rewrite | "the key-gated live contract probe" (ask 7) | asked |
| Tool-name stability (no hook or settings edit) | "how to keep the `mcp__pencil__*` tool surface stable" (ask 15) | asked |
| `brainstorm/SKILL.md`, `plan/SKILL.md`, `brainstorm-brand-workshop.md`, `constitution.md` edits | — | inferred — justification: these four name the package or the variable the migration changes; leaving them stale makes the wireframe gate point at a deprecated install and the wrong key name (enforcement contract) |
| `ux-design-lead.md` and the three generated mirrors | — | inferred — justification: the issue lists "agent prose that names `mcp__pencil__*` tools" as touched, and retiring `batch_get`/`snapshot_layout`/`get_guidelines` makes the prose false; CPO made it a sign-off condition |
| New live tool `read_skill` | — | inferred — justification: without it agents cannot reach design guidance or the DSL grammar once `get_guidelines` and `get_editor_state({include_schema})` are retired; CTO follow-up ruling 9 (`get_style` was cut) |
| The `Document: <path>` line on `batch_design` replies, `refusalPending`, the `outputDir` containment, the binary identity check | — | inferred — justification: single-user-incident safety on customer machines found by plan review (parallel agents on one server, silent re-baseline after a respawn, path escape, credential handed to a foreign binary); CTO ruling 10 |
| Captured transcript fixture `pen-0.3.13-transcript.txt` | "the key-gated live contract probe" (ask 7) | inferred — justification: keeps the stub's shapes tied to the real engine so the stub cannot drift into belief (the #11143 lesson) |
| `scripts/pen-cli/` lockfile prefix, install from `npm ci`, ADR-191 lockfile wiring, canonical-JSON fingerprint, child cwd and PATH filtering, REPL framing hardening, `containedDir()`, refused-operations echo, stderr reason lines | — | inferred — justification: deepen-pass security, user-impact and observability findings for a `single-user incident` surface on customer machines (credential reaching install scripts, false-positive refusals, forged replies, path escape, lost refused work, unobservable refusal states); CTO ruling 11 |
| ADR-304 | — | inferred — justification: CTO ruling 8 and plan Phase 2.10 (a vendor-engine and tool-surface decision a future engineer would be surprised to find undocumented) |
| `.gitleaksignore` / libvips install fix | — | not planned (excluded: #8964 owns it) |

### Split Assessment

- Subsystems touched: 3 — `plugins/`, `.grok/` (generated mirror), `knowledge-base/`
- Planned files: about 42 (31 edited incl. 2 conditional, 3 lockfile-wiring files and 3 generated mirrors; 11 created incl. the CLI lockfile pair) | Estimated changed lines: ~2,200 (lockfile content excluded)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. All three thresholds except the root count are exceeded, but the operator directed one PR ("Implement two OPEN issues in one PR") and ask 5 forbids building the guard twice; the commit sequence is Phase 1, Phase 2, Phase 3 so each is reviewable alone.

## Acceptance Criteria

- [ ] `bun test plugins/soleur/test/pencil-*.test.ts` passes, the pencil `*.test.sh` suites pass, and `bash scripts/test-all.sh` is green (it includes the orphan census and the harness-parity census, which catch an unregistered test or a hand-edited mirror)
- [ ] `doppler run -p soleur -c dev -- bash plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh` prints `PROBE OK` against `@pen.dev/cli@0.3.13` (open new file, two `batch_design` calls, save, reload in a fresh session with the nodes loaded, `get_screenshot`, `export_nodes`, the empty-over-non-empty refusal, the stale refusal behind a real engine, `Unknown tool:` for each of the 9 removed names, no engine write outside `save()` across SIGTERM, SIGKILL and `exit()`)
- [ ] `get_editor_state`, `get_variables`, `get_screenshot`, `export_nodes`, `batch_design`, `open_document`, `save` and `read_skill` work through the adapter; the 9 stubs return `isError` with a hint naming a tool that exists and trigger no save; the registered-tools test lists exactly 8 live and 9 stubs
- [ ] A save with 5 top-level nodes in memory over a file rewritten behind the session with 8 is refused with `REFUSED save:` text that names the change, warns that re-opening discards edits since the last save, and says to re-open then replay in order; the file is byte-identical and no `save` line reached the stub
- [ ] The recovery the refusal names is executed by a test: `open_document` on the changed file, replay of the refused edit, and the following save is allowed; after a refusal plus a crash respawn the next save is still refused with the restart wording until `open_document` succeeds
- [ ] After a confirmed save the next save is allowed; a save reply that is not `Saved <outFile>` is an `isError` result, sets the baseline to unknown and adopts nothing from disk
- [ ] An identical-bytes rewrite behind the session does not refuse; a same-size different-bytes rewrite does; a file removed behind the session is refused with its own reason
- [ ] `decideSave`'s predicate and its three refusal texts are unchanged (`pencil-save-gate.test.ts` existing cases pass untouched); delete-every-top-level-node is still refused with the open-a-new-path text
- [ ] `PEN_CLI_KEY` alone, `PENCIL_CLI_KEY` alone, `PEN_CLI_KEY=""` with a valid `PENCIL_CLI_KEY`, and both set with different values (`PEN_CLI_KEY` wins) all start the adapter and the child receives only `PEN_CLI_KEY`; an engine reply or a stderr chunk boundary echoing either value is redacted; with neither set the adapter exits non-zero before importing modules (`pencil-adapter-auth-hard-fail.test.sh`)
- [ ] `check_deps.sh` installs `@pen.dev/cli@0.3.13`, detects only the `pen` bin whose real path is inside the installed package directory, warns on a leftover `@pencil.dev/cli` without using it, and applies the 22.19.0 floor (a test distinguishes 22.18.x from 22.19.0 in both JS and bash); the adapter and `check_deps.sh` agree on every row of the shared identity fixture
- [ ] `pencil-repl-surface.mjs` rejects a `nodeId` or export id outside `^[A-Za-z0-9_-]{1,100}$`, more than 50 ids, a `scale` or `quality` outside its range, a `read_skill` path outside `^(guide/)?[a-z0-9-]+\.md$`, an `outputDir` that resolves outside the allowed roots or through a symlink, and a `format` outside the enum, before anything is written to the REPL
- [ ] `git grep -nE '@pencil\.dev/cli|PENCIL_CLI_KEY|snapshot_layout|get_guidelines|batch_get' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!**/archive/**' ':!knowledge-base/project/learnings'` returns only deliberate statements (the fallback variable, "was removed" hints and tests), every hit classified in the PR; the three mirrors equal the output of their sync scripts
- [ ] `python3 scripts/lint-skill-body-budget.py --base origin/main` passes, `plugins/soleur/test/components.test.ts` and `c4-count-parity.test.sh` pass
- [ ] `git diff --quiet origin/main...HEAD -- .claude/settings.json .claude/hooks` exits 0 (hooks and matchers untouched)
- [ ] ADR-304 (or the next free ordinal across every `origin/*` ref at merge time) exists with Alternatives Considered; `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` and `npx markdownlint-cli2` on the plan and `tasks.md` are green
- [ ] Canonical-JSON fingerprint: a CRLF-converted and a reformatted copy of the same document, and one injected transient read error after a confirmed save, do not refuse; a changed node value does
- [ ] Prompt framing: a node name or `read_skill` reply containing the prompt text at a line start does not desynchronise the REPL and the next `save()` reply is intact; bytes after a prompt trigger a restart from the saved file
- [ ] The child runs in a private empty cwd with no empty or relative PATH entries; `PENCIL_BINARY` is refused unless it is a regular file owned by the current uid and not group- or world-writable
- [ ] Install: `check_deps.sh` installs the CLI from the committed lockfile into `~/.local/share/pen-cli` with both credential names unset; the old `~/.local/node_modules/.bin/pencil` is never selected; a fake `~/.local` holding `@pencil.dev/cli@0.2.9` plus a stale adapter copy yields `DRIFT` and never routes the old adapter to the new engine
- [ ] Export and screenshots: relative `outputDir` rejected, symlinked components refused, cwd equal to `$HOME` excluded, overwrites listed, exports made while a refusal is pending are prefixed as rendered from unsaved memory
- [ ] Observability: every refusal state writes its stderr line through the one `logRefusal` helper (both call sites asserted); `git grep -nI pencil -- plugins/soleur/.claude-plugin/plugin.json plugins/soleur/.mcp.json .mcp.json` returns nothing; `ux-design-lead.md` step 3.2 carries the commit-the-marker instruction and the node-based post-save gate, and `pencil-post-save-gate.test.sh` passes on its fixtures
- [ ] The retired-term census also covers `get_style_guide|get_style_guide_tags|find_empty_space_on_canvas|set_variables|search_all_unique_properties|replace_all_matching_properties`, and the headless-branch parse test of `ux-design-lead.md` and `pencil-setup/SKILL.md` passes
- [ ] The Node-floor exit text (installed and required versions, `check_deps.sh`) is asserted in `pencil-adapter-auth-hard-fail.test.sh`
- [ ] PR body carries `Closes #11156` and `Closes #11168`, the redacted probe transcript and a `## Test Pyramid` block

## Test Scenarios

Pyramid layers: unit (pure modules), integration (installed adapter over real MCP stdio against the stub REPL), e2e (the key-gated live probe; `pyramid-justified: the real engine is the only oracle for the contract, the #11143 lesson`).

- Given the stub engine, when `batch_design` runs, then the REPL receives `execute({ input: ... })` carrying the alias preamble and never a `batch_design(` line (integration)
- Given a node name containing a line that looks like the count line, or a previous reply that carried a forged count line, when the count probe runs, then only the line carrying this call's nonce is accepted; zero or two matching lines give `null` and an existing non-empty file refuses the save (unit + integration)
- Given a reply that is empty, or is not `Saved <outFile>`, when the auto-save reply is checked, then the edit tool returns `isError`, the baseline becomes unknown and the next save refuses until re-open (unit + integration)
- Given 5 nodes in memory and 8 on disk after an external rewrite, when `batch_design` auto-saves, then it refuses as stale and the file is byte-identical (integration; Guard 1 row 1)
- Given two adapter sessions on one path, when A saves, B edits and saves, then B refuses; when B re-opens, replays and saves, then B saves and A's next save refuses (integration; Guard 1 row 3)
- Given a file rewritten while the engine is still starting, when the first save runs, then it refuses (integration, stub `startDelayMs`; Guard 1 row 4)
- Given a file rewritten while the count probe is in flight, when the save runs, then it refuses and no `save` line reaches the stub (integration; Guard 1 row 5)
- Given a stale refusal and then a crash and respawn, when the next edit saves, then it is refused with the restart wording until `open_document` succeeds (integration; Guard 1 row 8)
- Given a symlink named `pen` earlier on PATH and no installed package, when the adapter resolves the binary, then it errors and never spawns it (unit; Guard 2 row 3)
- Given `check_deps.sh` with only `@pencil.dev/cli` installed under a fake `~/.local`, when detection runs, then the headless tier is not selected and a deprecation warning prints (shell test with a fake prefix)
- Given the live engine, when the probe rewrites the file behind an open session and the agent edits, then `REFUSED save:` is returned and the bytes are unchanged (e2e)
- Given `rewriteOnStart` or `rewriteOnProbe` (no timers), when the first save runs, then it refuses and the stub log proves the probe or start was reached (integration; Guard 1 rows 4 and 5)
- Given two sessions with separate `STUB_TAG` side channels on one path, when A saves, B edits and saves, then B refuses; B re-opens, replays and saves, then B saves; A's next save refuses (three separate tests)
- Given `PEN_CLI_KEY` alone, `PENCIL_CLI_KEY` alone, `PEN_CLI_KEY=""` with a valid fallback and both set, when the adapter starts, then the stub's `ENVKEYS` line shows only `PEN_CLI_KEY` and a key written to stderr in two chunks is redacted (integration plus a unit test of the pure redactor)
- Given a three-operation script where operation 3 refers to a node created by operation 1, when it is refused as stale and then re-opened and replayed, then the replay saves (integration)
- Given each engine reply shape in the captured transcript, when the stub is used, then it reproduces the prompt, `OK`, `## Print output`, `Saved <path>`, `Save failed:` and `Unknown tool:` shapes (fixture realism, per the dogfood learning)

## Sharp Edges

- `waitForPrompt` detects the first newline followed by the prompt text in the buffer, so reply text that contains that sequence at a line start would cut a reply short and the tail would be attributed to the next command. The prompt is accepted only at the END of the buffer after a 50 ms quiet period, bytes after it are a desync (restart), the count line carries a random nonce, and the save confirmation is string equality after realpath, so a forged tail cannot pass as a count or a confirmation; the live probe calls `read_skill` on every guide path and then asserts the next `save()` reply is intact. Replies that carry user node names or long markdown are passed to the agent as text and never parsed.
- With an invalid but present key the engine still runs (fail-open usage check, `[WARN] ... 401`), so the adapter cannot detect a bad key at startup. `check_deps.sh` (`pen status`) and the live probe are where it shows.
- A read done through `batch_design` (`Get`/`Print`) also auto-saves, so under a stale refusal it is refused too; use `get_editor_state` or `open_document` to look at the document in that state. A raw read path is not exposed (CTO ruling 1).
- The stale check reads the file and the engine writes later, so a second writer inside that window is not caught, and the post-save read adopts whatever is on disk at that instant. The SKILL.md sharp edge says so. A change during engine startup makes the first save refuse (fails safe).
- The collapse hook in this repo asks for a snapshot before a re-open; on a customer machine no hook exists. The refusal text stays hook-neutral and SKILL.md carries the snapshot note.
- `PENCIL_BINARY` keeps its name and is trusted (only the registrant can set it); only the default binary changes. The CLI has its own lockfile under `scripts/pen-cli/` (ADR-191's fifth lockfile directory); the sentinel is accident protection, not a defence against an adversarial `batch_design` author (a script can reassign `Print` or `Get`).
- Do not add a `version` key to any plugin manifest, and do not hand-edit the generated agent mirrors.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this one is filled.

## Non-Goals

- Fixing the global-libvips install failure and the `fileToken` gitleaks waiver: tracked in #8964 (existing issue, not re-filed).
- Bounding the install in `copy_adapter.sh`: tracked in #9310.
- Writing the in-memory document to a recovery file when a save is refused: not built (a second write path the sentinel would then have to guard); the refusal instead returns the refused operations (64 KiB cap) so the replay does not depend on the agent's context.
- A replacement layout-check tool, a lock between writers, and a `get_style` tool: layout problems arrive on `batch_design` replies, the refusal states there is no lock, and `read_skill` returns the style archetypes.

## References

- Issues: #11156, #11168; predecessor #11143 / PR #11155; related #8964, #9310
- `plugins/soleur/skills/pencil-setup/scripts/pencil-save-gate.mjs` (`decideSave`, `runGuardedSave`)
- `plugins/soleur/skills/pencil-setup/SKILL.md` (sharp edges: engine contract, save sentinel, pin bump)
- `knowledge-base/project/learnings/bug-fixes/2026-10-26-a-stub-that-encodes-your-belief-about-an-engine-passes-the-bug-it-was-written-to-catch.md`

## Addendum — 2026-10-26 (work phase): measured outcome of the batch_design host-function probe

Ruling 11.2 and the Cut List entry for raw `execute` made a shadowing prelude conditional on the live probe. The probe on `@pen.dev/cli` 0.3.13 recorded `Export` writing outside the document directory and replacing an existing file, and image fills reading local files through absolute, `file://` and `../` urls. The condition was met, and the CTO ruled (2026-10-26, row in `decision-challenges.md`) to accept the residual with no prelude: the caller already has a same-user shell, image urls resolve inside the engine so a prelude cannot cover them, and the probe pins the behaviour so engine drift fails a named pin. ADR-304 carries the reasoning and the flip condition (confine the child with an OS sandbox if the tools reach an agent without a shell, or run hosted).
