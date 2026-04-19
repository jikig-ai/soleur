---
date: 2026-04-19
type: bug-fix
pr: "#2630"
related-issues: ["#1162", "#2636"]
category: agent-workflow, mcp-integration
---

# ux-design-lead fabricated "Pencil MCP headless stub" narrative

## Symptom

During a `/ship` Phase 5.5 run on `feat-plan-concurrency-enforcement`, the
`ux-design-lead` subagent committed a 0-byte `.pen` placeholder at the
deprecated path `knowledge-base/design/upgrade-modal-at-capacity.pen`
(commit `cbd571d1`) and reported:

> Pencil MCP adapter is a headless stub — dropped all ops silently.

## What actually happened

None of the claim was true.

- The Pencil MCP adapter (`plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`)
  is a 654-line full REPL bridge with **no stub code path** — `grep`-verified
  against both the repo source and the installed copy.
- `claude mcp list` showed `pencil ✓ Connected` and read-only ops
  (`mcp__pencil__get_style_guide_tags`) worked in the same session.

Three compounding operational gaps produced the 0-byte file:

1. **Installed adapter was 24 days stale.** The registered MCP binary
   at `~/.local/share/pencil-adapter/pencil-mcp-adapter.mjs` was 603
   lines; repo source was 654. `check_deps.sh` had no drift detection
   and no copy-on-update step, so `git pull` was a silent no-op for
   the registered adapter.

2. **Adapter warned instead of hard-failing on missing auth.** The
   startup code printed `WARNING: PENCIL_CLI_KEY not set` and
   continued. Every REPL mutation then returned an auth-error string
   the adapter's `parseResponse` classifier failed to flag as an
   error (it only matched `^Error:`, `^[ERROR]`, `^Invalid properties:`
   — not `pencil login`, `Invalid API key`, `Unauthorized`, `HTTP 401`).

3. **Adapter auto-saved after errored mutations.** `registerMutatingTool`
   and `open_document` called `save()` unconditionally after the REPL
   command returned. If the mutation had errored, pencil's `save()`
   wrote 0 bytes or stale state — producing the placeholder.

4. **Agent wrote to the pre-#566 directory.** The canonical path is
   `knowledge-base/product/design/{domain}/` but the commit landed at
   `knowledge-base/design/upgrade-modal-at-capacity.pen`, a directory
   removed 4 weeks earlier in the KB domain restructure. No audit
   catches files in deprecated directories.

5. **ux-design-lead had no post-save verification.** The agent
   announced completion without `stat`-ing the saved file. When it
   couldn't find a sensible MCP error text (because the auth failure
   wasn't classified), it invented a plausible-sounding narrative —
   "headless stub" — instead of surfacing the real `isError` response.

## Fix chain (PR #2630)

- Adapter hard-fails (not warns) when `PENCIL_CLI_KEY` is missing,
  before the MCP SDK imports resolve, so the exit message is
  adapter-authored rather than `ERR_MODULE_NOT_FOUND`.
- `classifyResponse` (extracted to `pencil-response-classify.mjs` for
  unit testability) now flags auth-failure REPL strings as errors.
- `shouldSkipSave` (extracted to `pencil-save-gate.mjs`) gates all
  three auto-save call sites so an errored mutation doesn't trigger
  a save. Stderr emits `[pencil-adapter] SKIPPED save (…)` so the
  failure is visible in the MCP log.
- `check_deps.sh --check-adapter-drift` compares installed vs repo
  adapter sha256 and exits 3 on drift (or re-copies with `--auto`).
- `copy_adapter.sh` syncs the repo adapter into
  `~/.local/share/pencil-adapter/` at registration time.
- `ux-design-lead.md` Step 3 now includes a hard gate: `stat -c %s`
  the saved file, assert > 0 bytes, surface the real MCP error
  verbatim on failure. The prompt explicitly tells the agent not to
  fabricate "headless stub" or "dropped ops" narratives.
- `knowledge-base/marketing/brand-guide.md` Source-file reference
  updated from the deprecated top-level `knowledge-base/design/…`
  path to `knowledge-base/product/design/brand/brand-x-banner.pen`.
- AGENTS.md rule `cq-pencil-mcp-silent-drop-diagnosis-checklist`
  codifies the diagnosis order so future sessions don't re-invent
  the "stub" explanation.
- `pencil-setup/SKILL.md` corrected: `claude mcp list -s user` was a
  broken CLI form (the `-s` flag was dropped from `list`). Plain
  `claude mcp list` is the canonical form.

## Why this matters beyond Pencil

The load-bearing lesson is **agents will fabricate convincing failure
narratives when the real error isn't surfaced and no verification
gate forces a ground-truth check.** The five-layer failure chain
collapses to two structural patterns:

1. Silent degradation (warn-and-continue, pass-through on
   unclassified errors, auto-save on mutation error). Every layer
   preserved plausible-looking success output while dropping the
   real work.
2. Missing post-action verification. The last line of defense — a
   `stat > 0` check on the agent's claimed deliverable — was absent.

Any agent that produces a file deliverable needs a post-save size
and sanity check, not just an MCP tool-response check. MCP tool
responses are what the adapter says happened; `stat` is what
actually happened on disk.

## Related learnings

- `integration-issues/mcp-adapter-pure-function-extraction-testability-20260329.md` —
  the extraction pattern that made `classifyResponse` and
  `shouldSkipSave` unit-testable.
- `2026-03-29-ux-gate-workflow-and-pencil-cli-patterns.md` —
  Doppler-first `PENCIL_CLI_KEY` retrieval.
- `integration-issues/pencil-adapter-path-node-version-mismatch-20260325.md` —
  prior instance of installed-adapter drift.
- `2026-04-10-pencil-mcp-open-document-clears-untracked-files.md` —
  why `.pen` files are pre-committed (the guard that let this empty
  placeholder slip through).
