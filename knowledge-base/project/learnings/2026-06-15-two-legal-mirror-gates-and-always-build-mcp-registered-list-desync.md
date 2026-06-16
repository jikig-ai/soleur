# Learning: two distinct legal-doc mirror gates; and always-build MCP server desyncs the registered-tool mirror

Feature: feat-reasoning-chat-boxes (#5370, PR #5363). Captured 2026-06-15.

## Problem

Two non-obvious traps surfaced while shipping the persisted `turn_summary` feature.

### 1. A new `###` heading in a canonical legal doc fails a SECOND, stricter mirror gate

Phase 7 added a new `### 3.12` section to `docs/legal/gdpr-policy.md`. I updated the
3 `LEGAL_DOC_SHAS` pins and confirmed `check-tc-document-sha.sh` passed — that
script's mirror **body-equivalence** step is `BODY_EQUIVALENCE_DOCS=("terms-and-conditions")`
only (non-T&C docs are explicitly deferred: "pre-existing benign drift … one-off
remediation PR before the gate can fire"). I concluded the Eleventy mirrors
(`plugins/soleur/docs/pages/legal/*.md`) did not need syncing.

That was wrong. A **separate** vitest gate — `apps/web-platform/test/legal-doc-consistency.test.ts`
— enforces **section-heading-sequence parity** (`## ` and `### ` only) between
every `docs/legal/<doc>.md` and its `plugins/soleur/docs/pages/legal/<doc>.md`
mirror, for ALL docs (not just T&C), AND Last-Updated-date parity. The new `### 3.12`
in the source with no matching mirror heading turned the full suite red — but only
the FULL suite caught it (the touched-file test loop never ran it), and the
background runner reported exit 0 while the log showed `1 failed` (exit-code masking).

### 2. Always-building a previously capability-gated in-process MCP server desyncs the unregistered-tool mirror

Phase 5 changed the `soleur_platform` MCP server in `cc-dispatcher.ts` from
`c4Enabled`-gated to always-built (so `narrate`/`summarize` are always registered).
I added the two FQNs to `CC_REGISTERED_PLATFORM_TOOL_NAMES` (the list that
`shouldMirrorUnregisteredPlatformToolUse` checks in `onToolUse` to avoid a
false-positive Sentry "unregistered-tool-invoked" mirror). Review found
`edit_c4_diagram` was registered into the SAME server but NOT in that list — so
every legit c4 edit false-positive-mirrors. It is a **pre-existing** bug (on main
the list was `[]` while c4 was already registered), but the always-build change
made the asymmetry conspicuous.

## Solution

1. Synced the gdpr-policy mirror's `### 3.12` block verbatim (no internal `.md`
   links to convert). privacy-policy/DPD additions were prose **within existing
   sections** (no new heading) so their mirrors stayed parity-green.
2. Did NOT trust the background suite's exit 0 — grepped the log for `FAIL`/`× `,
   found the one failure, fixed it, re-ran the specific gate green.
3. Filed #5388 for the c4 mirror desync (different subsystem; the correct fix
   threads a per-dispatch `registeredPlatformToolNames` from `realSdkQueryFactory`
   into the `dispatchSoleurGo` events closure — they are SEPARATE functions, so a
   module constant cannot see per-dispatch flag state).

## Key Insight

- **Legal-doc mirror parity has TWO independent gates.** `check-tc-document-sha.sh`
  (SHA pins + T&C-only body-equivalence) and `legal-doc-consistency.test.ts`
  (heading-sequence + Last-Updated date, ALL docs). Passing the first does NOT
  imply the second. **Any new `## `/`### ` heading in a canonical `docs/legal/*.md`
  REQUIRES adding the same heading to the Eleventy mirror in the same PR**; prose
  added inside an existing section does not. Run the FULL suite (not just
  touched-file tests) at the Phase 2 exit gate — and never trust a background
  runner's exit code; grep the log (exit-code masking).
- **When you flip an in-process MCP server from capability-gated to always-built,
  every consumer keyed on "which tools are registered this dispatch" must see the
  per-dispatch set, not a module constant** — especially when the server build and
  the tool-use handler live in different functions/closures.

## Session Errors

1. **Plan file `Read` failed at the bare-repo-root path** — Recovery: the file
   lives in the worktree; `cd` into `.worktrees/feat-reasoning-chat-boxes` and use
   worktree-absolute paths. Prevention: on resume, resolve all paths against the
   worktree root named in the resume prompt, not the bare root. (one-off)
2. **Legal 5-file set had changed on main (PR #5365)** — Recovery: `git rebase
   origin/main` before any Phase 7 legal edit. Prevention: already covered by the
   work Phase 0.5 rebase-before-legal-doc-edits FAIL-HARD gate, which fired
   correctly. (recurring, already-enforced)
3. **`controller` out of scope at `onToolUse` (TS2304)** — Recovery: the per-Query
   `AbortController` lives in `realSdkQueryFactory`, not the dispatch events
   closure; used `state.isAborted()` (the turn-abort latch). Prevention: documented
   the scope split in the `emitNarration` `aborted` doc comment. (one-off)
4. **`Edit` rejected ("File has not been read yet") after reading via Bash
   `cat`/`grep`** — Recovery: `Read` the file (or the target region) before
   editing. Prevention: the harness only tracks `Read`-tool reads; a Bash `cat`
   does not satisfy the read-before-edit precondition. (recurring; tool
   self-enforces — note only)
5. **Full vitest suite reported exit 0 with 1 real failure** — Recovery: grepped
   the log for `FAIL`, found `legal-doc-consistency`, fixed + re-ran the gate.
   Prevention: already covered — capture `rc=$?` AND grep the log; never trust the
   background-runner exit summary alone (test-all tail-masking class). (recurring,
   already-enforced)
6. **Mis-judged legal mirrors as fully deferred** — Recovery: synced the gdpr
   mirror `### 3.12`. Prevention: the Key Insight above (two mirror gates).
   (recurring → this learning + route-to-definition)

## Tags
category: integration-issues
module: legal-docs, cc-dispatcher, mcp-tools
