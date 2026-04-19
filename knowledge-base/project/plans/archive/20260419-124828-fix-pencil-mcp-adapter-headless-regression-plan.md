---
type: fix
status: plan
created: 2026-04-19
deepened: 2026-04-19
branch: feat-one-shot-pencil-mcp-headless-stub-regression
---

# fix: ux-design-lead "Pencil MCP headless stub" regression — diagnose and restore real .pen output

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** Research Insights, Phase 2 (test runner), Phase 3 (test-extraction), Phase 4, Sharp Edges
**Research sources:** 6 pencil-adapter learnings (`integration-issues/`, root learnings dir), ship/plan/compound SKILL.md cross-references, live MCP probe, `gh issue view 1162`.

### Key Improvements

1. **Test runner corrected from `vitest` to `bun:test`.** Existing pencil tests (`pencil-error-enrichment.test.ts`, `sanitize-filename.test.ts`) use `bun:test` — running `./node_modules/.bin/vitest` would produce 0 collected tests. Root `package.json` defines `"test": "bash scripts/test-all.sh"`, which enforces this.
2. **Test-design constraint: pure-function extraction is mandatory.** Per `mcp-adapter-pure-function-extraction-testability-20260329`, tests CANNOT import `pencil-mcp-adapter.mjs` directly — the top-level `McpServer`/`StdioServerTransport` imports crash Bun's module resolver. Every new test in Phase 2 must target an extracted pure module (`pencil-error-enrichment.mjs` pattern) or use a subprocess harness for adapter-level tests (T2.1).
3. **"Ship Phase 5.5 Product/UX Gate" is a misnomer in the source error.** Phase 5.5 in `ship` SKILL.md is CMO/CRO/COO gates. The Product/UX Gate lives in `plan` SKILL.md §2.5. This confirms the subagent not only fabricated "headless stub" but also misattributed the phase. No code-level action; documented in Sharp Edges.
4. **Three related pencil-adapter learnings were already filed** and reinforce the root-cause hypothesis: (a) env-var misregistration via `-e` after `--` (#1108, already fixed by argv defense-in-depth), (b) stderr vs stdout error capture (already fixed via `stderrBuffer`), (c) untracked-file destruction by `open_document` (already guarded by `pencil-open-guard.sh`). The regression is in operational drift layered on top of these fixes — not an unknown failure class.
5. **Doppler-first pattern is already codified** (`2026-03-29-ux-gate-workflow-and-pencil-cli-patterns.md`). The fix is not "add Doppler lookup"; it is "re-trigger Doppler lookup on adapter drift detection" — because `/soleur:pencil-setup` re-registers and re-bakes the env.
6. **Acceptance criterion for #1162 follow-up sharpened.** The placeholder was for `feat: plan-based agent concurrency enforcement` (#1162, OPEN) — T3.7's follow-up issue is "recreate the upgrade-modal design under `knowledge-base/product/design/upgrade/` once adapter is fixed."

### New Considerations Discovered

- **Observability gap**: the adapter's `process.stderr.write()` goes to the Claude Code MCP log, not to Sentry or user-visible output. Per `cq-silent-fallback-must-mirror-to-sentry`, a fallback that commits empty state to disk should not be invisible. Phase 4 adds a plan note; full Sentry wiring is out of scope (adapter is a Node process, not Next.js).
- **`claude mcp get <name>` availability**: plan assumed it exists. Need to verify — `claude mcp list` works, but T1.2 should prefer direct inspection of `~/.claude.json` / `~/.config/claude/mcp.json` if `get` is missing.
- **Bun FPE spawn sensitivity** (`2026-03-20-bun-fpe-spawn-count-sensitivity.md`, via `scripts/test-all.sh` header): `bun test` has a known crash when spawning many subprocesses; tests that spawn the adapter (T2.1) need to serialize, not parallelize.
- **`.mcp.json` secret leak pattern** (`pencil-mcp-adapter-zod4-stderr-detection-20260324`): confirms our decision NOT to put `PENCIL_CLI_KEY` in repo `.mcp.json`. User-scoped registration is correct.

## Overview

During a `/ship` Phase 5.5 Product/UX Gate run, the `ux-design-lead` agent emitted
the error "Pencil MCP adapter is a headless stub — dropped all ops silently" and
committed a 0-byte placeholder `.pen` file at `knowledge-base/design/upgrade-modal-at-capacity.pen`
(commit `cbd571d1`). The reported symptom is that the adapter "silently drops all
operations" and that this may be caused by a new Pencil release breaking our
headless integration.

**Live investigation (pre-plan) changes the picture:**

1. The phrase "headless stub" does **not** appear in any committed adapter code.
   `pencil-mcp-adapter.mjs` (654 lines) is a real bridge — it spawns
   `pencil interactive`, speaks REPL, auto-saves after mutations, and has no
   code path that returns a synthetic success without touching the subprocess.
   The message was **fabricated by the failing subagent** as post-hoc
   rationalization for an empty-file output it could not explain.

2. The adapter **is registered and responsive** in the current session.
   `claude mcp list` shows `pencil: ... ✓ Connected` and
   `mcp__pencil__get_style_guide_tags` returned ~200 tags in this planning
   session. The MCP transport is healthy; failures are inside authenticated
   REPL commands, not in tool dispatch.

3. The **installed adapter is 24 days stale.**
   `~/.local/share/pencil-adapter/pencil-mcp-adapter.mjs` dated 2026-03-25
   is 603 lines; the repo source is 654 lines. The installed copy is missing
   four merged fixes: PR #1180 (`Invalid properties:` error detection),
   #1259 (set_variables enrichment), #1262 (export_nodes name-based renames),
   #1263 (positional insert M() hint). This does not itself cause "silent
   drops" but it means the adapter cannot surface recent error classes
   correctly.

4. `PENCIL_CLI_KEY` is present in Doppler (`pencil_cli_576...c9f8`, `dev` config)
   but is **not in the adapter's process environment** in the failing session.
   The adapter prints `WARNING: PENCIL_CLI_KEY not set. Auth will fail.` at
   startup when absent. Every REPL mutation (`open_document`, `batch_design`,
   `save`) would then return an auth error string — which the adapter's
   `parseResponse` classifies as `isError: true` and returns verbatim. The
   ux-design-lead agent apparently received these auth errors, did not
   surface them, and wrote the "headless stub" message as a summary.

5. The placeholder landed at `knowledge-base/design/...` but the `ux-design-lead`
   workflow (Step 3, line 54) specifies
   `knowledge-base/product/design/{domain}/{descriptive-name}.pen`. So the
   agent wrote to a **stale path** that no longer exists in the current
   taxonomy (the `knowledge-base/design/` directory was removed by #566 in
   2026-03 when the KB was restructured by domain). The pre-commit
   `pencil-open-guard.sh` let it through because the file was tracked;
   nothing after that catches "placeholder in deprecated directory."

**Root cause (hypothesis, three contributing factors, ranked by likelihood):**

- **(A) Missing `PENCIL_CLI_KEY` at the MCP registration moment.** The
  registration command bakes `-e PENCIL_CLI_KEY=...` into `claude mcp add`;
  if that value was empty or a stale token at registration time, every
  subsequent MCP session inherits the broken env. This is the "silent drop"
  the subagent observed — mutations return auth errors, `save()` is called
  anyway (the adapter always auto-saves after mutations), but the file on
  disk stays empty because no design ops actually executed.

- **(B) Stale installed adapter.** The on-disk adapter (`~/.local/share/pencil-adapter/...`)
  is 24 days behind repo. `check_deps.sh` has no copy-on-update step, so a
  fresh `git pull` of the plugin does not propagate to the adapter that
  `claude mcp` invokes. Users see repo-level fixes (#1262, #1263) silently
  not apply.

- **(C) ux-design-lead writes to a non-canonical directory.** The agent's
  documented output path is `knowledge-base/product/design/...`, yet the
  commit shows `knowledge-base/design/...`. This could be (a) the subagent
  hallucinating the old path, or (b) a leftover instruction somewhere that
  still references the old path. Either way, the placeholder landed where
  no human or automated audit looks.

None of these is the "new Pencil release broke our headless integration"
that the task description assumed — pencil-cli has had no release since the
adapter was last synced (no commits to `plugins/soleur/skills/pencil-setup/`
since 2026-04-15). The regression is in our own stack, not upstream.

## Research Reconciliation — Spec vs. Codebase

| Spec / Task Claim | Codebase Reality | Plan Response |
|---|---|---|
| "Pencil MCP adapter is a headless stub" | No stub code path exists. Adapter is a full REPL bridge (654 lines, 13 tools, auto-save after mutations). | Treat the error message as a misdiagnosis. Do not search for a stub to fix. Focus on auth env + staleness instead. |
| "Dropped all ops silently" | Adapter returns `isError: true` on pencil-side errors. It does not swallow errors. The `save()` call after failed mutations does write the file (possibly empty). | Investigate whether the ux-design-lead agent masks `isError` responses in its flow. File behavior is consistent with auth failure producing empty saves. |
| "A new Pencil release broke our headless integration" | No pencil-cli upgrade since 2026-04-15. No commits to pencil-setup scripts since #2404 (Apr dep bump). Adapter tests pass with repo source. | Skip upstream-version-chasing. Verify with `pencil --version` during GREEN; if mismatch, track separately. |
| "Placeholder .pen committed at `knowledge-base/design/`" | Current canonical path per ux-design-lead.md is `knowledge-base/product/design/{domain}/...`. `knowledge-base/design/` was removed in #566. | Remove the deprecated-path placeholder as part of GREEN. Grep the whole repo for residual references. |

## Goals

1. **Diagnose definitively.** Produce a reproducing test that distinguishes
   the three root-cause hypotheses (auth env missing, stale installed adapter,
   wrong output path) so the fix targets the real failure — not the fabricated
   "headless stub" story.
2. **Restore end-to-end design output.** After the fix, invoking
   `ux-design-lead` through the Product/UX Gate pipeline must produce a
   non-empty `.pen` file at `knowledge-base/product/design/{domain}/...` with
   real node IDs in it.
3. **Prevent recurrence.** Three specific gaps let this happen silently —
   close each: (a) `check_deps.sh` must compare installed-adapter checksum
   to repo source and re-copy on drift, (b) the adapter's startup auth
   warning must escalate to hard-fail the MCP connection when
   `PENCIL_CLI_KEY` is absent, (c) ux-design-lead must refuse to write to
   `knowledge-base/design/` (deprecated path) and must verify the saved
   file is non-empty before announcing completion.
4. **Capture the failure mode as a rule.** Add an AGENTS.md rule (cq-\*) so
   future sessions don't invent "stub" explanations for auth failures. The
   rule codifies: when a Pencil MCP operation "fails silently," check
   `PENCIL_CLI_KEY` in the MCP registration AND compare installed adapter
   SHA against repo source before reaching for upstream explanations.

## Non-Goals

- **Rewriting the adapter as a "true headless" service.** The current adapter
  is already headless-CLI-backed (no GUI required) and works; the regression
  is operational (stale install, missing env), not architectural.
- **Changing Pencil upstream.** No indication upstream broke anything.
- **Back-filling the `upgrade-modal-at-capacity.pen` design.** That file was
  created for a concurrency-enforcement feature (#1162) unrelated to this
  PR; the design should be regenerated under the right path in a follow-up
  once the adapter is fixed. This PR only removes the stale placeholder.
- **Fixing `PENCIL_CLI_KEY` rotation/refresh.** Key expiry handling is a
  separate concern — we assume a valid Doppler-provisioned key is available.
- **Investigating the other "failed-to-connect" MCP servers** (`plugin:github:github`,
  `cloudflare`) surfaced by `claude mcp list`. Out of scope.

## Research Insights

**Repo context (this worktree, HEAD `cbd571d1`):**

- Adapter entrypoint: `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`
  (654 lines). Registers 13 MCP tools. Spawns `pencil interactive --out <file>`.
  Auto-saves after mutating ops (`save()` call on line 385). Warns but does
  not fail-fast when `PENCIL_CLI_KEY` is unset (lines 649–653).
- Error parse: `parseResponse` (line 84) classifies output starting with
  `Error:`, `[ERROR]`, or `Invalid properties:` as `isError: true`. It does
  NOT currently classify auth-failure responses (e.g. `Please run \`pencil login\``,
  `Invalid API key`, HTTP 401) as errors — these pass through as success
  text if they don't start with one of the three prefixes. This is one way
  "silent drops" can happen even without a "stub."
- Registration skill: `plugins/soleur/skills/pencil-setup/SKILL.md` lines 70–85.
  Baked-in env: `claude mcp add pencil -s user -e PENCIL_CLI_KEY="$PENCIL_KEY" -- <node> <adapter>`.
- Dependency checker: `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`
  (485 lines). Detects binaries. **Does not verify installed-adapter currency
  against repo source.** Does not copy adapter files into
  `~/.local/share/pencil-adapter/`. The installed location is written once,
  never synchronized.
- ux-design-lead workflow: `plugins/soleur/agents/product/design/ux-design-lead.md`
  line 54 — output path is `knowledge-base/product/design/{domain}/...`.
  No post-save verification step; announcing completion does not check that
  the file has bytes > 0.
- `.mcp.json` (worktree): only playwright. Pencil is user-scoped (via `claude mcp add -s user`)
  and intentionally not in repo `.mcp.json` — per existing architecture,
  keys are user-specific. No action needed there.
- Hook: `cq-before-calling-mcp-pencil-open-document` / `pencil-open-guard.sh`
  requires the `.pen` to be tracked in git before `open_document`. This is
  why an empty placeholder is committed pre-emptively; the guard is
  guarding against a different failure mode (adapter overwriting untracked
  files) and working as designed.

**Relevant learnings (prioritized by directness to this bug):**

- `knowledge-base/project/learnings/integration-issues/mcp-adapter-pure-function-extraction-testability-20260329.md`
  — **shapes Phase 2 test design.** The adapter's top-level MCP SDK
  imports prevent direct import from `bun:test`. Every testable unit
  must be extracted into a dependency-free sibling module
  (`pencil-error-enrichment.mjs`, `sanitize-filename.mjs` already
  follow this pattern). T3.2 and T3.3 follow by creating
  `pencil-response-classify.mjs` and `pencil-save-gate.mjs`.
- `knowledge-base/project/learnings/2026-03-25-pencil-adapter-env-var-screenshot-persistence-api-coercion.md`
  — **confirms root cause hypothesis A.** `PENCIL_CLI_KEY`
  misregistration (via `-e` after `--`) is a known recurring failure
  mode. Defense-in-depth argv parsing already exists in the adapter
  (lines 30–42). What is missing, and what T3.1 adds, is **hard-fail
  on absent key** — today the adapter only warns.
- `knowledge-base/project/learnings/integration-issues/pencil-mcp-adapter-zod4-stderr-detection-20260324.md`
  — reinforces two existing fixes (stderr capture, Zod 4 two-arg
  `record`) and documents the `.mcp.json` secret-leak pattern that
  explains why `PENCIL_CLI_KEY` must remain user-scoped, not
  project-scoped.
- `knowledge-base/project/learnings/2026-04-10-pencil-mcp-open-document-clears-untracked-files.md`
  — **explains the existing `cq-before-calling-mcp-pencil-open-document`
  rule.** `open_document` on untracked files silently zeros them. The
  commit `cbd571d1` pre-commits a placeholder precisely to satisfy this
  guard. The unresolved gap is that a failed mutation + auto-save can
  STILL produce a 0-byte file at a tracked path — the open_document
  guard doesn't cover mutation-time destruction. T3.3 closes that gap.
- `knowledge-base/project/learnings/2026-03-29-ux-gate-workflow-and-pencil-cli-patterns.md`
  — already codifies Doppler-first `PENCIL_CLI_KEY` lookup and the
  session-errors pattern where agents didn't check Doppler before
  prompting for credentials. T3.4's drift detector should recommend
  re-running `/soleur:pencil-setup` which already does Doppler lookup.
- `knowledge-base/project/learnings/integration-issues/pencil-adapter-path-node-version-mismatch-20260325.md`
  — the installed-adapter staleness pattern. Same root shape: the
  adapter lives at `~/.local/share/pencil-adapter/`, registration
  records absolute paths at install time, and nothing re-syncs on
  `git pull`. T4.2 (copy_adapter.sh) is the structural fix.
- `AGENTS.md:cq-silent-fallback-must-mirror-to-sentry` — the existing
  rule codifies the pattern: code catches a degraded state (failed
  mutation) and continues with fallback (empty save). Adapter stderr
  does not reach Sentry, so T3.3 at minimum makes the fallback visible
  in the MCP log. Full Sentry integration is out of scope for this
  fix — the adapter is a standalone Node server, not the Next.js app.
- `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`
  (via `scripts/test-all.sh` header) — constrains Phase 2's
  subprocess-spawning tests to the sequential `run_suite` harness.

**Commit / environment evidence:**

- `cbd571d1` — the placeholder commit, 0-byte file at deprecated path.
- `~/.local/share/pencil-adapter/pencil-mcp-adapter.mjs` — dated 2026-03-25,
  603 lines. Repo source: 654 lines, dated 2026-04-18.
- `diff` of installed vs repo shows missing imports (`enrichErrorMessage`,
  `sanitizeFilename`), missing `Invalid properties:` detection, entirely
  different `export_nodes` handler (no filename renames).
- Doppler `soleur/dev` has `PENCIL_CLI_KEY=pencil_cli_576...c9f8` — key
  is provisioned; registration script can retrieve it.
- `claude mcp list` confirms `pencil: ... ✓ Connected` right now — the
  transport is working. `mcp__pencil__get_style_guide_tags` returned ~200
  tags in this session, confirming even read-only auth is functional.
  *However*, style-guide fetch may not require auth; `open_document` to
  cloud-scoped resources certainly does. The selective-failure pattern
  is consistent with PENCIL_CLI_KEY being valid for read but expired/invalid
  for write, OR the key being present now but absent during the failing
  `/ship` session (which ran under a different environment).

**CLI form verification:**

- `claude mcp list -s user` (documented in `pencil-setup/SKILL.md` line 47) — **broken**:
  `error: unknown option '-s'`. The current `claude` CLI has dropped the `-s`
  flag on `list`. The skill's instruction to grep `claude mcp list -s user`
  needs updating. Verified this session: plain `claude mcp list` works and
  includes user-scoped entries.
- `verified: 2026-04-19 source: claude mcp list --help (ran this session)`

## Implementation Phases

### Phase 1: Reproduce and confirm root cause (diagnosis-only, no fixes)

**Goal:** convert the three hypotheses into a single confirmed failure mode
before writing any fix. Do NOT guess.

- [ ] **T1.1 — Adapter drift check.** Compute `sha256sum` of both
      `~/.local/share/pencil-adapter/pencil-mcp-adapter.mjs` and
      `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`.
      Capture the hash pair in the plan's scratchpad file
      `knowledge-base/project/specs/feat-one-shot-pencil-mcp-headless-stub-regression/diagnosis.md`.
      Expected: the two hashes differ. If they match, rule out hypothesis B.
- [ ] **T1.2 — Env presence check.** From a fresh shell (no doppler run),
      run `claude mcp get pencil` (or inspect `~/.config/claude/mcp.json`)
      and confirm whether the baked `-e PENCIL_CLI_KEY=...` value is:
      (a) absent, (b) empty, (c) an expired-looking token, or (d) the
      currently-valid Doppler value. Record the finding in
      `diagnosis.md`. Do NOT print the key value — record only `present/empty/different-from-doppler`.
- [ ] **T1.3 — Controlled failure reproduction.** With a temp .pen file,
      invoke `mcp__pencil__open_document(filePath=/tmp/repro-$(date +%s).pen)`
      from this session, then a trivial `batch_design` that inserts one frame,
      then `save`. Capture: (a) each tool's return, (b) the on-disk size
      of the file after each step, (c) adapter stderr (which goes to the
      Claude Code MCP log). If the file stays 0 bytes, auth failure is
      confirmed. If the file grows, hypothesis A is wrong and we must
      reread the ux-design-lead agent transcript to find the real drop
      point.
- [ ] **T1.4 — Output-path audit.** Grep the full repo (excluding `.git/`
      and `knowledge-base/project/plans/archive/`) for any remaining
      reference to `knowledge-base/design/` (the deprecated path). List
      each hit with filename and line. Decide for each: update to
      `knowledge-base/product/design/`, or leave if it's intentional
      historical narrative.
- [ ] **T1.5 — Write up diagnosis.md.** One paragraph per hypothesis with
      the supporting evidence from T1.1–T1.4. Confirm which hypothesis
      is the primary cause, which are contributing, and which are ruled
      out. This is the authoritative input to Phase 2's test design.

### Phase 2: RED — failing tests that pin the real failure modes

**Goal:** write tests BEFORE fixes. Per `cq-write-failing-tests-before`,
this is mandatory since the plan has acceptance criteria.

**Critical test-runner constraint (from deepen pass):**

- Tests use **`bun:test`**, NOT vitest. Existing tests
  (`plugins/soleur/test/pencil-error-enrichment.test.ts`,
  `sanitize-filename.test.ts`) import from `"bun:test"`. Test runner is
  `bash scripts/test-all.sh` (per root `package.json`). Running vitest
  here would produce zero collected tests and a false green.
- **Tests CANNOT import `pencil-mcp-adapter.mjs` directly.** Per
  `knowledge-base/project/learnings/integration-issues/mcp-adapter-pure-function-extraction-testability-20260329.md`,
  the adapter's top-level `McpServer` / `StdioServerTransport` imports
  crash Bun's module resolver (`Cannot find module '@modelcontextprotocol/sdk/server/mcp.js'`).
  Every Phase 2 test must EITHER target a pure-function module (extract
  if not already extracted) OR spawn the adapter as a subprocess and
  drive it via stdio.

Put new tests in `plugins/soleur/test/`. All imports use `import {...} from "bun:test"`.

- [ ] **T2.1 — `pencil-adapter-auth-hard-fail.test.sh` (NOT .ts).** Shell
      test (same pattern as `plugins/soleur/test/ralph-loop.test.sh`)
      that spawns the adapter as a subprocess with
      `env -u PENCIL_CLI_KEY /home/jean/.local/node22/bin/node <adapter>`,
      waits up to 3 seconds, asserts exit code ≠ 0 AND stderr contains
      `ERROR: PENCIL_CLI_KEY not set`. Subprocess-driven because the
      test cannot import the adapter module.
- [ ] **T2.2 — `pencil-response-classification.test.ts`.** Target the
      pure function `classifyResponse` (extracted in T3.2). Imports
      from `../skills/pencil-setup/scripts/pencil-response-classify.mjs`.
      Asserts: `Please run \`pencil login\`` → `isError: true`;
      `Invalid API key` → `isError: true`; `Unauthorized` → `isError: true`;
      `Error: foo` → `isError: true` (preserved existing behavior);
      `node0="abc"` (normal output) → `isError: false`.
      **Extraction is part of the fix, not just the test** — T3.2
      moves the existing inline `parseResponse` logic into
      `pencil-response-classify.mjs` so it can be unit-tested. The
      adapter's `parseResponse` becomes a thin wrapper.
- [ ] **T2.3 — `pencil-adapter-save-nonempty-guard.test.sh`.**
      Subprocess-driven. Spawns the adapter with a valid
      `PENCIL_CLI_KEY`, pipes in a canned MCP `batch_design` request
      that will error (e.g., malformed operation), then a `save`
      request. Assert the resulting `.pen` file stays 0 bytes OR the
      tool response contains `SKIPPED save (preceding mutation errored)`.
      Alternative (preferred for reliability): extract the save-gating
      logic into a pure function `shouldSkipSave(lastError)` in
      `pencil-save-gate.mjs` and test it directly.
- [ ] **T2.4 — `check-deps-adapter-drift.test.sh`.** Shell test. Copies
      `pencil-mcp-adapter.mjs` to a temp dir with one byte changed,
      points `check_deps.sh` at that temp dir via env var, asserts the
      script exits non-zero (interactive mode) or re-copies
      (`--auto` mode) with stdout containing both sha prefixes.
- [ ] **T2.5 — `ux-design-lead-output-path-guard.test.sh`.** Shell test.
      `grep -F "knowledge-base/design/" plugins/soleur/agents/product/design/ux-design-lead.md`
      must return exit code 1 (no match); `grep -F "knowledge-base/product/design/"`
      must return exit code 0. Catches both future regressions and any
      residual deprecated-path reference. Currently passes — kept as
      regression guard.
- [ ] **T2.6 — `pencil-setup-skill-cli-form.test.sh`.** Shell test.
      `grep -F "claude mcp list -s user" plugins/soleur/skills/pencil-setup/SKILL.md`
      must return exit code 1. Currently matches — test fails until
      T3.6 ships.

Run the suite: `bash scripts/test-all.sh`. Verify T2.1, T2.2, T2.3, T2.4,
T2.6 fail red. T2.5 starts green (regression guard).

**Why subprocess harness for T2.1/T2.3/T2.4**: see
`knowledge-base/project/learnings/integration-issues/mcp-adapter-pure-function-extraction-testability-20260329.md`.
Serialize subprocess-spawning tests via `scripts/test-all.sh` sequential
runner — Bun has an FPE crash when spawning many subprocesses in
parallel (see `2026-03-20-bun-fpe-spawn-count-sensitivity.md`).

### Phase 3: GREEN — fix each confirmed failure

Fix in the order determined by T1.5's diagnosis. Default order (if
diagnosis confirms all three hypotheses are in play):

- [ ] **T3.1 — Adapter hard-fail on missing auth env.** Edit
      `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`
      lines 649–653. Replace the `process.stderr.write(WARNING…)` with
      `process.stderr.write(ERROR…)` plus `process.exit(1)`. This turns
      a silent-drop vector into a load-time failure the MCP client sees
      immediately. Update T2.1 from fail to pass.
- [ ] **T3.2 — Adapter detects auth-failure response patterns via
      extracted pure module.** Create
      `plugins/soleur/skills/pencil-setup/scripts/pencil-response-classify.mjs`
      exporting `classifyResponse(raw) -> { text, isError }`. Move
      the current inline logic from `parseResponse` (adapter line 84)
      into this module. Extend the `isError` union to include
      `/pencil login/i`, `/Invalid API key/i`, `/Unauthorized/i`. The
      adapter imports it:
      `import { classifyResponse } from "./pencil-response-classify.mjs";`
      — then `const { text, isError } = classifyResponse(raw);` wherever
      `parseResponse` was called. This follows the extraction pattern
      from `pencil-error-enrichment.mjs` / `sanitize-filename.mjs` and
      makes T2.2 testable without a subprocess. Add inline comment
      with a symbol anchor (`cq-code-comments-symbol-anchors-not-line-numbers`).
      Update T2.2 from fail to pass.
- [ ] **T3.3 — Adapter `save()` refuses to overwrite with empty.** Edit
      the `save` tool handler (symbol: `server.tool("save", …)`) and
      the auto-save call sites inside `registerMutatingTool` (symbol:
      `registerMutatingTool`) and `open_document` (symbol:
      `server.tool("open_document", …)`). Extract the gating decision
      to a pure function in
      `plugins/soleur/skills/pencil-setup/scripts/pencil-save-gate.mjs`:
      `export function shouldSkipSave(lastResponse) { return lastResponse?.isError === true; }`
      so T2.3 can test it directly without subprocess. Before invoking
      `pencil interactive`'s `save()`, check whether the last
      sendCommand result was an error (via
      `shouldSkipSave(lastClassification)`). If so, skip the save and
      return the error response verbatim — do NOT fabricate a "stub" or
      "dropped" message and do NOT emit a synthetic success. This is
      the core fix for the "0-byte placeholder committed" symptom.
      Per `cq-silent-fallback-must-mirror-to-sentry`, also
      `process.stderr.write("[pencil-adapter] SKIPPED save: preceding mutation errored — <err summary>\n");`
      so the failure is at least visible in the MCP log. Update T2.3.
- [ ] **T3.4 — `check_deps.sh` drift detection + auto-re-copy.** Edit
      `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`. Add a
      phase: if `~/.local/share/pencil-adapter/pencil-mcp-adapter.mjs`
      exists and `sha256sum` differs from repo source, either (a) emit
      `PENCIL_ADAPTER_DRIFT=yes` with the sha diff and instruct the user
      to re-run `/soleur:pencil-setup`, or (b) re-copy automatically
      when `--auto` is passed. Update T2.4.
- [ ] **T3.5 — ux-design-lead post-save verification + path enforcement.**
      Edit `plugins/soleur/agents/product/design/ux-design-lead.md`.
      In Step 3, add: "Before announcing completion, `stat` the saved
      .pen file and assert size > 0 bytes. If the file is 0 bytes,
      report the failure explicitly — do not fabricate a 'stub' or
      'dropped ops' narrative. Pencil MCP always returns a real
      `isError` response; read the error instead of inventing one."
      Also explicitly state that the directory MUST be
      `knowledge-base/product/design/` and NOT `knowledge-base/design/`
      (which was removed in #566). This paragraph is the direct
      documentation antidote to the fabricated "headless stub" message.
- [ ] **T3.6 — Skill CLI form correction.** Edit
      `plugins/soleur/skills/pencil-setup/SKILL.md` line 47. Replace
      `claude mcp list -s user` with `claude mcp list`. Add
      `<!-- verified: 2026-04-19 source: claude mcp list --help -->`
      per `cq-docs-cli-verification`. Update T2.6.
- [ ] **T3.7 — Remove the stale placeholder.** Delete
      `knowledge-base/design/upgrade-modal-at-capacity.pen` and remove
      the empty `knowledge-base/design/` directory if it has no other
      files. File a follow-up GitHub issue: "Recreate
      `upgrade-modal-at-capacity.pen` under
      `knowledge-base/product/design/{correct-domain}/` as part of #1162"
      — per `wg-when-deferring-a-capability-create-a`. Link the issue
      from the PR body.

### Phase 4: REFACTOR and harden

- [ ] **T4.1 — AGENTS.md rule.** Add to CQ section:
      `When a Pencil MCP operation appears to 'silently drop' ops, verify (a) PENCIL_CLI_KEY in `claude mcp get pencil` matches Doppler `soleur/dev`, (b) installed adapter sha matches `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`, (c) .pen saved file size > 0. A 'headless stub' is NOT a known failure mode — the adapter has no stub code path. [id: cq-pencil-mcp-silent-drop-diagnosis-checklist]. **Why:** PR #<this PR>.`
      Size check: keep under 600 bytes per `cq-agents-md-why-single-line`.
- [ ] **T4.2 — Installed-adapter copy step.** If T3.4 chose option (a),
      add a small `copy_adapter.sh` that pencil-setup invokes at
      registration time. This closes the update gap: a fresh plugin
      pull always re-copies the adapter.
- [ ] **T4.3 — Learning file.** Write
      `knowledge-base/project/learnings/bug-fixes/ux-design-lead-headless-stub-fabrication.md`
      (let the author date it — per the sharp-edge rule about dated
      filenames). Capture: (a) symptoms, (b) misleading message from
      subagent, (c) actual three contributing factors, (d) diagnosis
      order, (e) links to PRs that remediated each factor.

### Phase 5: Validation

- [ ] **T5.1 — Full test suite.** From the worktree (NOT the bare root —
      `scripts/test-all.sh` aborts on bare repos per its own guard),
      run `bash scripts/test-all.sh`. All T2.\* pass, no regressions
      elsewhere. The runner enforces sequential suite execution
      (one Bun process per suite) to avoid the known FPE
      spawn-count-sensitivity crash
      (`2026-03-20-bun-fpe-spawn-count-sensitivity.md`). Do NOT try to
      run `bun test plugins/soleur/test/` directly — it will crash with
      SIGFPE under the subprocess-spawning tests.
- [ ] **T5.2 — End-to-end Pencil round-trip.** Manually (in this session,
      since we already verified MCP connectivity):
      `mcp__pencil__open_document` on a fresh tracked `.pen` under
      `knowledge-base/product/design/test/roundtrip.pen`, `batch_design`
      insert one frame, `save`. Assert file size > 0 and contains
      non-placeholder bytes. Then clean up (delete the test file).
- [ ] **T5.3 — Simulated ship-gate.** Dry-run the `/ship` Phase 5.5
      Product/UX Gate branch logic against this plan. Confirm that with
      the hard-fail adapter + post-save guard, a missing
      `PENCIL_CLI_KEY` produces a clear actionable error, not a
      committed 0-byte file.

## Test Scenarios

1. **Missing PENCIL_CLI_KEY → adapter exits.** With
   `env -u PENCIL_CLI_KEY node pencil-mcp-adapter.mjs`, the process
   exits non-zero within 2 seconds and stderr contains
   `ERROR: PENCIL_CLI_KEY not set`.
2. **Auth-failure REPL response → isError true.** When pencil subprocess
   emits `Please run \`pencil login\``, `parseResponse` returns
   `{ isError: true }`.
3. **Failed mutation → save() skipped.** After `batch_design` returns
   an error, the adapter does NOT send `save()` to pencil; the MCP
   response surfaces the error instead.
4. **Installed adapter drift → check_deps warns.** If installed-adapter
   sha ≠ repo-source sha, `check_deps.sh` exits with `DRIFT` status and
   prints both hashes.
5. **ux-design-lead refuses 0-byte save.** A .pen file with `stat -c%s`
   of 0 after `save` causes the agent to emit an explicit failure
   message referencing the adapter error — not a "stub" message.
6. **Deprecated path check.** No file in `plugins/soleur/agents/**`
   contains the string `knowledge-base/design/` (without `product/` in
   between).
7. **Skill CLI form verified.** `pencil-setup/SKILL.md` contains no
   `claude mcp list -s user` occurrence.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] T1.1–T1.5 diagnosis committed to `diagnosis.md` before any fix
      code is written.
- [ ] T2.1–T2.6 tests fail before T3.\* changes, pass after.
- [ ] `knowledge-base/design/upgrade-modal-at-capacity.pen` removed;
      follow-up issue filed and referenced in PR body.
- [ ] AGENTS.md gains `cq-pencil-mcp-silent-drop-diagnosis-checklist`,
      within the 600-byte cap.
- [ ] Learning file under `knowledge-base/project/learnings/bug-fixes/`
      describes the misdiagnosis and fix chain.
- [ ] T5.2 end-to-end round-trip passes in the session (file > 0 bytes).
- [ ] PR body has `Closes #<follow-up>` for the path-drift placeholder
      issue and `Ref #1162` (the concurrency-enforcement work that the
      deleted placeholder was intended for).

### Post-merge (operator)

- [ ] Re-run `/soleur:pencil-setup` on operator machine to adopt the
      new `copy_adapter.sh` step (if T3.4 chose option a). Verify
      `~/.local/share/pencil-adapter/pencil-mcp-adapter.mjs` sha matches
      repo source.
- [ ] On next invocation of `ux-design-lead` in a `/ship` gate, observe
      that a real .pen file is produced under
      `knowledge-base/product/design/{domain}/`, size > 0, and a
      screenshot is auto-exported.

## Files to Edit

- `plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs` — T3.1, T3.2, T3.3
- `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh` — T3.4
- `plugins/soleur/skills/pencil-setup/SKILL.md` — T3.6
- `plugins/soleur/agents/product/design/ux-design-lead.md` — T3.5
- `AGENTS.md` — T4.1

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-pencil-mcp-headless-stub-regression/diagnosis.md` — T1.5 scratchpad
- `plugins/soleur/test/pencil-adapter-auth-hard-fail.test.sh` — T2.1 (shell — adapter must spawn as subprocess; Bun cannot import MCP SDK)
- `plugins/soleur/test/pencil-response-classification.test.ts` — T2.2 (`bun:test`, imports extracted `pencil-response-classify.mjs`)
- `plugins/soleur/test/pencil-adapter-save-nonempty-guard.test.sh` — T2.3 (shell subprocess harness) AND/OR `plugins/soleur/test/pencil-save-gate.test.ts` (unit test of extracted pure gate)
- `plugins/soleur/test/check-deps-adapter-drift.test.sh` — T2.4 (shell — exercises `check_deps.sh`)
- `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` — T2.5 (shell — grep-based structural guard)
- `plugins/soleur/test/pencil-setup-skill-cli-form.test.sh` — T2.6 (shell)
- `plugins/soleur/skills/pencil-setup/scripts/pencil-response-classify.mjs` — T3.2 (extracted pure classifier, zero imports)
- `plugins/soleur/skills/pencil-setup/scripts/pencil-save-gate.mjs` — T3.3 (extracted pure save-gating decision, zero imports)
- `plugins/soleur/skills/pencil-setup/scripts/copy_adapter.sh` — T4.2 (if option a chosen in T3.4)
- `knowledge-base/project/learnings/bug-fixes/ux-design-lead-headless-stub-fabrication.md` — T4.3 (author-dated; do not pre-date in tasks.md per sharp-edge rule)

## Files to Delete

- `knowledge-base/design/upgrade-modal-at-capacity.pen` — T3.7 (plus empty directory if applicable)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (run during
Phase 1.7.5) returns no issues touching
`plugins/soleur/skills/pencil-setup/`, `plugins/soleur/agents/product/design/`,
or `AGENTS.md`.

## Alternative Approaches Considered

1. **"Rewrite adapter from scratch as pure in-process library."** Rejected.
   Adapter already works when env is correct; the regression is operational,
   not architectural. Large refactor would delay the actual fix.
2. **"Replace ux-design-lead with a simpler `frontend-design`-based flow
   that skips Pencil entirely."** Rejected — filed as deferred follow-up
   instead (out of scope here). `ux-design-lead` is the documented UX
   Gate agent and removing it requires CPO+CMO assessment per
   `hr-new-skills-agents-or-user-facing`.
3. **"Warn on missing PENCIL_CLI_KEY instead of hard-fail."** This is the
   current behavior and is exactly what produced the regression — downgrading
   errors to warnings lets the MCP client continue and commit broken state.
   Hard-fail is the right call.
4. **"Auto-fetch PENCIL_CLI_KEY from Doppler in the adapter itself."**
   Rejected — the adapter is a generic MCP server that should not bundle
   secret-management. Doppler fetch belongs in `pencil-setup`/registration.

## Domain Review

**Domains relevant:** Engineering (CTO-scoped — infrastructure of the
plugin). Product (via Pencil MCP touching `ux-design-lead` output flow).

*Spawning CTO and CPO as blocking Tasks is deferred to the /work phase
under pipeline auto-mode — per `plan` skill §2.5, when running inside a
pipeline subagent the skill does not open AskUserQuestion loops. The
plan captures the engineering and product concerns directly:*

### Engineering (CTO)

**Status:** reviewed (inline)
**Assessment:** Regression is three compounding operational gaps
(stale install, missing env, silent auto-save-after-error). Fix chain
is minimal (≤60 LOC across 3 files) and all three gaps close with a
single diagnostic playbook codified as an AGENTS.md rule. No
architectural change. Risk: T3.1 (hard-fail on missing env) might
break existing sessions where the adapter was registered without a
key — acceptable because such sessions were already silently broken;
surfacing the error is an improvement.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline mode)
**Skipped specialists:** ux-design-lead (N/A — this plan fixes
ux-design-lead, not a user-facing page), copywriter (no copy in scope)
**Pencil available:** yes (verified this session)

#### Findings

The plan modifies the `ux-design-lead` agent behavior but does not add
a new user-facing page. Per skill §2.5, agent-workflow fixes are NONE
tier from a UX perspective. Product-strategy implication is positive:
restoring real .pen output unblocks every downstream design-gated flow.

## Risks

1. **PENCIL_CLI_KEY rotation.** If the Doppler-stored key expires,
   even the post-fix adapter will hard-fail at every registration.
   Mitigation: T4.3 learning file documents how to re-provision;
   separate issue for proactive rotation is out of scope.
2. **Installed-adapter copy racing with a running MCP session.** If
   `check_deps.sh --auto` copies over the adapter while Claude Code
   has an open MCP connection, the running adapter process keeps the
   old file loaded (Linux unlinks are deferred). Low risk — worst case
   is a restart-required message. Mitigation: T3.4 emits drift warning
   with instructions to restart Claude Code.
3. **T3.3 (skip save on error) changes a user-observable behavior.**
   Callers who currently rely on the empty `.pen` existing after a
   failed mutation may break. Mitigation: grep the whole codebase for
   code that stats `.pen` size after an adapter call — none found in
   this plan's scope.
4. **Fabricated error messages elsewhere.** This plan only addresses
   the "headless stub" message. Other subagents may similarly
   fabricate convincing failure narratives. Mitigation: T4.1 AGENTS.md
   rule + T4.3 learning file establish the pattern; a broader sweep
   is out of scope.

## PR Body Template

```markdown
## Summary

Fixes ux-design-lead producing 0-byte .pen placeholders during `/ship`
Phase 5.5 Product/UX Gate. Root cause was three compounding operational
gaps, not the fabricated "Pencil MCP adapter is a headless stub" message
the subagent emitted: (1) stale installed adapter 24 days behind repo,
(2) adapter silently warned instead of failing when `PENCIL_CLI_KEY`
unset, (3) adapter auto-saved after errored mutations, writing empty
files.

## Changes

- Adapter hard-fails when `PENCIL_CLI_KEY` is missing (was silent warn).
- Adapter detects auth-failure REPL responses as errors (was pass-through).
- Adapter skips auto-`save()` when the preceding mutation errored.
- `check_deps.sh` detects installed-vs-repo adapter drift and warns.
- `ux-design-lead` enforces output path
  `knowledge-base/product/design/{domain}/` and verifies saved file
  size > 0 before announcing completion.
- AGENTS.md rule `cq-pencil-mcp-silent-drop-diagnosis-checklist` codifies
  the diagnosis playbook so future sessions don't invent "stub"
  explanations for auth failures.
- Removes stale 0-byte `knowledge-base/design/upgrade-modal-at-capacity.pen`.

## Changelog

fix: Pencil MCP adapter silent-drop regression; hard-fail on missing
auth, skip save-on-error, detect install drift.

## Test plan

- [ ] vitest passes from worktree (via `./node_modules/.bin/vitest run`).
- [ ] `mcp__pencil__open_document` → `batch_design` → `save` round-trip
      produces non-empty .pen at `knowledge-base/product/design/test/`.
- [ ] `env -u PENCIL_CLI_KEY node pencil-mcp-adapter.mjs` exits non-zero.
- [ ] `sha256sum ~/.local/share/pencil-adapter/*.mjs` matches
      `plugins/soleur/skills/pencil-setup/scripts/*.mjs` after
      `/soleur:pencil-setup`.

Ref #1162 — the `upgrade-modal-at-capacity` design this cleanup removes
belongs to the plan-based concurrency enforcement work; recreate under
the correct path as a follow-up.

Closes #<follow-up issue filed by T3.7>.
```

## Sharp Edges

- Do not treat the "Pencil MCP adapter is a headless stub" message as
  ground truth — it is fabricated by the failing subagent. The adapter
  has no stub code path. Search for "headless stub" in the repo; it
  returns no hits in any committed adapter code. This plan's T1 phase
  is deliberately diagnosis-first for exactly this reason.
- The `claude mcp list -s user` form is broken in the current CLI.
  Use plain `claude mcp list`. Documented in T3.6; verified this
  session with `claude mcp list --help`.
- `PENCIL_CLI_KEY` is baked into `claude mcp add -e` at registration
  time — it is NOT read from the environment at MCP session start.
  Re-registering (or re-running `/soleur:pencil-setup`) is required
  after key rotation. The adapter's env allowlist
  (`buildPencilEnv`, line 46) only passes through what was set at
  registration, plus the allowlist names. A shell-level `export
  PENCIL_CLI_KEY=...` done after registration does NOT propagate to
  the MCP subprocess.
- The installed adapter at `~/.local/share/pencil-adapter/` is never
  auto-synced with repo source. Until T3.4 ships, a fresh `git pull`
  on the plugin is a no-op for the adapter. This is the highest-ROI
  fix in the plan because it prevents the same class of bug from
  recurring silently.
- Do not put `PENCIL_CLI_KEY` in the worktree's `.mcp.json`. The key
  is user-specific and the existing user-scoped `claude mcp add -s user`
  pattern is correct. Committing the key would be a secret leak.
- `knowledge-base/design/` is a dead directory from pre-#566. Any path
  surfacing it in an agent prompt, skill doc, or plan is a stale
  reference — update to `knowledge-base/product/design/{domain}/`.
- "`/ship` Phase 5.5 Product/UX Gate" is misattribution. `ship`
  SKILL.md Phase 5.5 is CMO Content-Opportunity / CMO Website Framing /
  COO Expense Tracking gates — there is NO Product/UX Gate in ship.
  The Product/UX Gate lives in `plan` SKILL.md §2.5. The failing
  subagent's phase attribution was wrong in addition to its error
  message. The fix does not need to touch `ship/SKILL.md`; the UX
  Gate orchestration lives in `plan/SKILL.md` and the agent-level
  behavior lives in `ux-design-lead.md`.
- MCP adapter tests cannot import the adapter module directly.
  Bun's `import ... from "../skills/pencil-setup/scripts/pencil-mcp-adapter.mjs"`
  throws `Cannot find module '@modelcontextprotocol/sdk/server/mcp.js'`
  because the MCP SDK is installed only in the adapter's own
  `node_modules`, not at the plugin test level. Always extract the
  unit-under-test into a sibling pure module with zero imports
  (pattern: `pencil-error-enrichment.mjs`, `sanitize-filename.mjs`,
  and the new `pencil-response-classify.mjs`, `pencil-save-gate.mjs`).
- Do NOT put `PENCIL_CLI_KEY` in the repo `.mcp.json` via
  `claude mcp add -s project -e`. Per
  `pencil-mcp-adapter-zod4-stderr-detection-20260324.md` session-error
  #5, that form writes the plaintext key into a committed file. The
  user-scoped `-s user` registration is the only correct path — and is
  what the setup skill already does.
- `claude mcp add` with a mid-session re-registration causes
  tool-unavailability until the next turn
  (`2026-03-25-pencil-adapter-env-var-screenshot-persistence-api-coercion.md`
  session-error #2). Document this in T3.4 if drift-detection triggers
  a re-copy: the user may need to restart Claude Code, not just
  re-register.
