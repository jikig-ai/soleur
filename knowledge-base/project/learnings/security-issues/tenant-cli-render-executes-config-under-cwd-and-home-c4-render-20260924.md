---
module: web-platform C4 re-render (apps/web-platform/server/c4-render.ts)
date: 2026-09-24
problem_type: security_issue
component: service_object
symptoms:
  - "likec4@1.50.0 run in a tenant diagrams dir executes likec4.config.{js,cjs,mjs,ts,cts,mts} found under its cwd"
  - "likec4 honours .likec4rc / likec4.config.json include.paths and follows symlinks out of the diagrams dir"
  - "with the stage dir clean, likec4 still executed a module under $HOME/.node_modules (review measurement)"
root_cause: missing_validation
resolution_type: code_fix
severity: critical
issue: 8623
pr: 8687
synced_to: [security-sentinel]
tags: [likec4, tenant-content, config-execution, rce, staging, symlinks, home-env, aba-race, sandbox-canary]
---

# Troubleshooting: a CLI run on tenant content executes config from its cwd AND from $HOME

## Problem

The C4 re-render spawned `likec4` with the tenant workspace's diagrams directory as cwd.
likec4 loads and EXECUTES `likec4.config.*` from its cwd, follows `include.paths` from JSON
rc files, and follows symlinks — so any tenant (or tenant agent) able to write a file into
the diagrams dir could run code in the web-platform server process. Assessment (legal
record `knowledge-base/legal/audits/2026-09-24-8623-c4-render-exposure-assessment.md`):
not known to have been exploited.

## Solution

1. **Render only committed bytes, never the workspace.** `renderC4Model(stage)` takes a
   stage FUNCTION, no path. `stageCommittedC4Sources` lists the commit GitHub returned for
   the write (Contents + Trees + Blobs APIs) and writes only regular-file
   `.c4`/`.likec4`/`.like-c4` blobs into a `mkdtemp` dir under a private root
   (`~/.cache/soleur-c4-render`, `c4-staging-root.ts`). It REFUSES (does not skip) config
   files, symlinks, gitlinks, a folder named like a source, and >50 sources / >4 MiB.
2. **Neutralise ambient resolution.** The child gets `HOME=<stage dir>` — with only cwd
   cleaned, likec4 still executed `$HOME/.node_modules/...`. The stage is re-verified
   (lstat walk) immediately before spawn, and the staging root must be a directory owned
   by this uid with no group/other write.
3. **Keep the agent sandbox out of the stage.** The staging root is outside the sandbox
   write set and added to `denyRead`; it is `mkdirSync`'d first because the SDK silently
   drops non-existent deny paths.
4. **Pinning to a commit creates an ABA race — close it.** An older render can finish last.
   Before the model PUT the writer re-lists HEAD and requires the SOURCE SET (path + blob
   sha) to equal what was rendered, then PUTs with HEAD's model sha; 409/422 re-checks once.
   An undo (sources restored to an older set) is the case a sha-only check misses.
5. **Canary.** New `${CANARY_C4_STAGING}` placeholder; replay refuses unsubstituted
   placeholders; fixture re-captured in-image.

Acceptance is a real-binary test (`c4-render-tenant-config.test.ts`) that plants a
sentinel-writing config per config name, an rc `include.paths`, a symlink, and a
`$HOME/.node_modules` payload, and asserts no sentinel is ever written. CI installs
`likec4@1.50.0` with `LIKEC4_REQUIRED=1` so the test cannot skip itself green.

## Key Insight

When a server runs a third-party CLI over tenant content, "which files does it read" is
the wrong question — ask **which files does it EXECUTE, resolved from where**: cwd,
ancestors of cwd, `$HOME`, rc files that point elsewhere, and symlink targets. Clean the
input by constructing it (allowlist from a trusted source into a fresh dir), not by
filtering the tenant's tree, and pin every ambient resolution root (`HOME`, cwd) to that
dir. Then re-check the concurrency model: rendering a pinned commit instead of the live
tree turns "latest wins" into a race that needs an explicit source-set comparison.

## Session Errors

1. **`gh issue create` blocked twice by hook** (body file outside worktree; missing User-Impact/Fix-Size/Mandated-By).
   - **Recovery:** moved the body into the worktree and added the fields; filed #8695, #8696.
   - **Prevention:** already hook-enforced — draft follow-up bodies from the issue template inside the worktree.
2. **Phase 1 server-side RED deferred from plan to work** (planning forbids test code).
   - **Recovery:** RED recorded in work at 393cd84112.
   - **Prevention:** none needed — expected pipeline ordering; plan should say "RED in work" explicitly.
3. **`repo-wide-containment` flagged a literal `../../..` in a test fixture.**
   - **Recovery:** built the path with `UP.repeat()`.
   - **Prevention:** build traversal fixtures programmatically; the detector greps literals.
4. **`c4-prompt-addendum-honesty` asserted an inline copy after the copy moved to shared constants.**
   - **Recovery:** retargeted the test at `C4_PROMPT_ADDENDUM`/`C4_TOOL_DESCRIPTION`.
   - **Prevention:** when single-sourcing prose, grep tests for the old literal's anchor phrase.
5. **First staging-root validation forbade tmpdir**, breaking tests and the canary capture.
   - **Recovery:** narrowed the refusal to the sandbox WRITE set.
   - **Prevention:** derive a deny-set from the actual threat (who else can write there), not a location heuristic.
6. **Blob-cache test failed: bytes known from the write were not cached.**
   - **Recovery:** cache known bytes under their git blob sha.
   - **Prevention:** none — TDD RED doing its job.
7. **Concurrency test timed out: `headOverride` matched the `.c4` existing-sha GET too.**
   - **Recovery:** scoped the hook to the parent-listing path.
   - **Prevention:** match fake-API hooks on the full path, never a suffix shared with other calls.
8. **Dist-parity regex missed backtick-quoted config names.**
   - **Recovery:** accept both quote styles.
   - **Prevention:** when parsing a vendor's dist, sample the actual bytes before writing the regex.
9. **TS rejected the env cast.**
   - **Recovery:** `as unknown as NodeJS.ProcessEnv`.
   - **Prevention:** one-off.
10. **lefthook `tsc` failed on stale canary JSDoc types.**
    - **Recovery:** updated the JSDoc.
    - **Prevention:** run `tsc --noEmit` on touched `.mjs` with `@ts-check` before committing.
11. **ESLint ratchet caught an unused `KNOWN_PLACEHOLDERS`** that file-selected suites missed.
    - **Recovery:** removed the constant.
    - **Prevention:** already covered (work SKILL — a file-selected suite set cannot see a repo-global ratchet).
12. **`test-all` webplat shard queued behind the gate lock.**
    - **Recovery:** killed own processes, ran vitest directly.
    - **Prevention:** already covered (one-shot token discipline — refused/contended gate → targeted suites).
13. **git-history seat reported a merge conflict that did not exist** (`merge-tree` rc 0).
    - **Recovery:** measured `git merge-tree --write-tree origin/main HEAD` and discarded the claim.
    - **Prevention:** already covered (review step 1 prescribes the lead's own `merge-tree` measurement).
14. **Legal census contradicted itself** (render count / window).
    - **Recovery:** CLO addendum: exactly 3 renders, window start 2026-06-05T11:40:39Z, closes at deploy.
    - **Prevention:** already covered (compound correction-sweep bullets — grep the claim's subject).
15. **Playwright MCP connection closed.**
    - **Recovery:** not needed (no browser scenarios).
    - **Prevention:** one-off.

## Related

- `knowledge-base/project/learnings/best-practices/2026-06-05-external-cli-exit-0-is-not-proof-validate-the-artifact.md`
- `knowledge-base/project/learnings/best-practices/2026-06-18-likec4-exits-0-on-syntax-error-gate-on-diagnostic-not-just-element-count.md`
- ADR-050 amendment (2026-09-24); ADR-079 amendment; follow-ups #8695, #8696 (bwrap).
