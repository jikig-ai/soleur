---
title: "fix: Close residual file-system race in contained digest write (CodeQL #248)"
type: fix
date: 2026-10-27
slug: fix-codeql-fs-race-digest-write
branch: feat-one-shot-10368-codeql-fs-race
issue: 10368
closes: [10368, 10839, 11318, 11190, 11062, 10985, 10910, 10800, 10687, 10756]
lane: cross-domain
priority: priority/p2-medium
domain: domain/engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix: Close residual file-system race in contained digest write (CodeQL #248)

## Overview

CodeQL alert #248 (`js/file-system-race`, severity high) flags
`writeDigestFileContained` at `apps/web-platform/server/inngest/functions/_cron-community-publication.ts:699`.
The function writes the daily community digest into an **agent-tainted ephemeral
workspace** — a `mkdtemp` + `git clone --depth=1` under `spawnCwd` in which a
prompt-injectable spawned agent ran earlier in the same cron run
(`cron-community-monitor.ts:1122,1243`; the #7122 hardening lineage exists
precisely because that workspace must be treated as adversarial).

The current implementation is a *path-based check-then-use* chain:

1. Per ancestor segment of `relPath` (`knowledge-base/support/community/`):
   `lstat(current)` → maybe `mkdir(current)` → `lstat(current)` again, refusing
   symlinks and non-directories.
2. `lstat(target)` → `unlink(target)` when present (removes a symlink itself).
3. `writeFile(target, text, { flag: "wx", mode: 0o644 })`.

Two distinct surfaces, two different verdicts:

- **Leaf component — already fail-closed.** `wx` maps to `O_CREAT|O_EXCL`, which
  on Linux refuses an existing final path *including symlinks*. A racer that
  re-creates the leaf between `unlink` and `writeFile` wins an `EEXIST` throw,
  never a write-through. This half of the alert is a CodeQL false positive.
- **Ancestor components — a real residual race.** The final `writeFile(target)`
  re-resolves the entire ancestor chain at syscall time. A same-UID racing
  writer inside the ephemeral tree (an agent-planted background process is the
  threat actor the containment exists for — it presumes a prior
  exact-literal-allowlist gap, which is what defense-in-depth is for) can
  `rename` a verified ancestor away and drop a symlink into place between the
  last `lstat` and the `writeFile`, redirecting the digest write **outside
  `spawnCwd`** — an arbitrary file create/truncate as the cron UID. The commit
  pipeline's `expectedContent` byte-verify + `pushTipReason` gate
  (`_cron-safe-commit.ts`) refuse to *commit* the miss, but the out-of-workspace
  write has already landed.

**Ruled by planning subagent, 2026-10-27: structural fix, not a suppression.**
The leaf is false-positive, the ancestor walk is a true positive; the issue
carries `type/security`, and a structural fix using the repo's established
`O_NOFOLLOW`/numeric-flags idiom (`resolve-protected-branches.ts:68`,
`compound-promote-create-gates.ts:449`, `dsar-export.ts:1808`,
`kb-reader.ts:293`) is small and verifiable. The fix **fuses every check into
the act**: per-ancestor `open(..., O_RDONLY|O_DIRECTORY|O_NOFOLLOW)` pinned
through `/proc/self/fd/<fd>` (the dirfd-relative-open workaround — Node has no
`openat`/`dirfd` API; nodejs/node#31110, and the identical fix shipped at
kodustech/kodus-ai#1532), plus a leaf `open(O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW)`.
No path-based stat call remains, which both closes the residual race and
removes the check→use pair CodeQL tracks.

## Research Insights

**Premise Validation (Phase 0.6).** Issue #10368 is OPEN, `type/security`,
`priority/p2-medium`, `domain/engineering`; its 9 duplicate-cluster issues
(#10839, #11318, #11190, #11062, #10985, #10910, #10800, #10687, #10756) are all
OPEN with no closing PR — the fix PR must carry one `Closes #N` per own body
line for all ten. The cited code exists verbatim at
`_cron-community-publication.ts:699` (`await writeFile(target, text, { flag:
"wx", mode: 0o644 })`). ADR corpus grep (`O_NOFOLLOW|file-system-race|symlink|
dirfd|openat|toctou`) found no ADR rejecting fd-pinned traversal; the mechanism
matches existing in-repo precedent. `collision-precheck.sh 10368` reported only
this branch's own auto-WIP PR #11334 (expected, not a foreign duplicate).
Premise holds.

**Property List (Phase 0.6b).**

- P1: the digest write cannot be redirected outside `spawnCwd` by a concurrent
  same-UID mutation of the workspace tree (no ancestor symlink swap, no leaf
  write-through).
- P2: an existing leaf is replaced without ever writing through a symlink;
  every refusal stays fail-closed (throw, never silent write elsewhere).
- P3: no `lstat`/`stat`/`access`/`existsSync` call remains in
  `writeDigestFileContained`, so CodeQL alert #248 has no check→use pair to
  flag and auto-resolves to `fixed` on the next scan after merge.
- P4: behavior parity on all existing unit tests (error-message substrings
  `clean relative path`, `plain directory`, `directory` unchanged).
- P5: no new dependencies, no infra, no schema changes; dev-machine test runs
  (non-Linux) keep working.

**Cut List (Phase 0.6b).**

- Temp-file + `rename` → buys P2's atomicity but ancestors still re-resolve at
  rename time; rejected as the primary mechanism (does not cover P1). The
  unlink+`O_EXCL` leaf under a pinned parent is simpler and equivalent.
- `O_NOFOLLOW` alone on `writeFile` → covers only the final component, which
  `wx` already covers; buys no property.
- Documented suppression (`lgtm`/`codeql` comment) → leaves P1 real; rejected
  per `type/security`.
- Git-plumbing write (`hash-object -w --stdin` + `update-index --cacheinfo`,
  skipping the worktree entirely, mirroring the c4-render off-tree learning) →
  the most surface-reducing option, but `stageExactPaths`
  (`_cron-safe-commit.ts:507`) requires the file on disk (`lstat` + `hash-object
  <path>`) and the marker-3 `existsSync` probe reads it; bypassing both re-plumbs
  trusted commit machinery for a one-alert fix. Recorded as a possible future
  refactor, not this PR.

**Relevant file paths.**

- `apps/web-platform/server/inngest/functions/_cron-community-publication.ts:639-700`
  — `writeDigestFileContained` (the fix site).
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts:1122,1243`
  — the two call sites (`spawnCwd`, `digestPath` =
  `knowledge-base/support/community/<YYYY-MM-DD>-digest.md`,
  `COMMUNITY_DIGEST_DIR_PATH` at `_cron-community-publication.ts:414`).
- `apps/web-platform/test/server/inngest/cron-community-publication.test.ts:1031-1099`
  — the real-fs `writeDigestFileContained` suite (6 tests, extended by this PR).
- `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts:507-530` —
  `stageExactPaths`, sibling lstat→`hash-object` pair; already fail-closed via
  `expectedContent` byte-verify (`:533`) + `pushTipReason` (`:557`). Out of
  scope — see Attack Surface Enumeration.
- Precedent for numeric-flag opens: `server/resolve-protected-branches.ts:68`,
  `server/compound-promote-create-gates.ts:445-449`, `server/dsar-export.ts:1808`,
  `server/kb-reader.ts:293`, `server/kb-binary-response.ts:108`.
- `server/inngest/cron-bash-allowlist-hook.mjs` +
  `_cron-claude-eval-substrate.ts:385-417` — the exact-literal allowlist whose
  hypothetical escape is the threat actor.

**Institutional learnings.**

- `learnings/2026-06-10-bot-cron-safe-commit-substrate-symlink-removal.md` —
  the #5026/#5091/#5111 lineage: the ephemeral workspace is adversarial by
  design; handler-side persistence is deliberately non-throwing and verified.
- `learnings/best-practices/2026-06-05-render-off-tree-return-bytes-and-drop-toctou-with-the-reread.md`
  — precedent for removing TOCTOU surfaces rather than hardening around them
  (informed the git-plumbing alternative, rejected on blast radius).
- `learnings/best-practices/2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md`
  — CodeQL alert state is the closure source of truth; issues must not be left
  as phantom security work (hence all 10 `Closes`).
- Lazy `await import("node:fs/promises")` inside the function is load-bearing:
  top-level bindings land in the static graph of sibling tests mocking node
  builtins with partial factories (existing comment at
  `_cron-community-publication.ts:644-646`; `node:fs` constants import must be
  lazy for the same reason).

**External research (security topic — ran inline).** Node has no
dirfd/`openat` API (nodejs/node#31110, closed stale; libuv/libuv#4167
unresolved) — `/proc/self/fd/<fd>/<next>` is the established dentry-pinned
traversal on Linux (same fix class shipped at kodustech/kodus-ai#1532).
`fs.promises.open(path, <numeric-flags>, <mode>)` supports the full
`fs.constants.O_*` set on Node ≥ 20.16 (repo floor:
`apps/web-platform/package.json` `engines.node`).

## Problem Statement / Motivation

A `type/security` high-severity alert sits open on the digest-write path of a
cron whose workspace is intentionally treated as attacker-influenced. The
leaf half of the alert is a false positive, but the ancestor half is a real —
if narrow — residual: closing it removes the last redirectable write in the
containment chain, and doing it *structurally* (rather than suppressing the
alert) means a future allowlist-hook gap cannot pivot through the digest
write into an arbitrary-path write as the worker UID.

## Proposed Solution

Rewrite `writeDigestFileContained` so every filesystem operation is a single
syscall that fuses check and use:

1. Keep the `relPath` lexical validation verbatim (`""`, absolute, `.`/`..`,
  empty segments → `writeDigestFileContained: relPath must be a clean relative
  path`).
2. Open `spawnCwd` once with `O_RDONLY|O_DIRECTORY|O_NOFOLLOW` → root dirfd
  (fuses existence + is-dir + not-symlink; this newly validates `spawnCwd`
  itself, a tightening over the current code which trusts it).
3. For each ancestor segment, resolve through the *pinned* parent:
   `open(`${FD_BASE}/${dirFh.fd}/${seg}`, O_RDONLY|O_DIRECTORY|O_NOFOLLOW)`.
   `ENOENT` → `mkdir` beneath the pinned fd (tolerate `EEXIST`, then open);
   `ELOOP`/`ENOTDIR` → `writeDigestFileContained: ancestor is not a plain
   directory` (message preserved).
   `FD_BASE` is `/proc/self/fd` on Linux; on other platforms fall back to
   `join(current, seg)` — opens still atomically refuse symlinks/non-dirs
   (P1's pin is Linux-only; the non-Linux residual is dev/test-only since the
   tainted-workspace threat model is production-Linux).
4. Leaf: `unlink(`${FD_BASE}/${dirFh.fd}/${leaf}`)` tolerating `ENOENT`;
   `EISDIR`/`EPERM` → `writeDigestFileContained: target is a directory`
   (message preserved). Then `open(leaf, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,
   0o644)` → `fh.writeFile(text)` → `fh.close()`. A racing leaf re-create wins
   `EEXIST` → throw (fail-closed; new error text permitted).
5. Close every dirfd `FileHandle` in `finally` (`close().catch(() => {})`).

Internal shape (for a deterministic regression test, not part of the public
surface): split into `openContainedDir(spawnCwd, dirSegments)` → `FileHandle`
and `createContainedFile(dirFh, fallbackDirPath, leaf)` → `FileHandle`, with
`writeDigestFileContained` orchestrating validation, both helpers, write and
close.

## Technical Considerations

- **No openat in Node.** `/proc/self/fd/<fd>/<seg>` resolves `<seg>` beneath
  the open file description's *dentry*, so an ancestor renamed away
  mid-sequence can no longer redirect the walk — the fd pins the inode, not
  the name. This is the portable-in-spirit openat equivalent the Node issue
  tracker recommends.
- **Non-Linux fallback.** Plain joined paths keep every refusal atomic
  (O_NOFOLLOW/O_DIRECTORY at open time); only the dentry-pin is lost. The
  Linux-pin test is `it.skipIf(process.platform !== "linux")` — CI covers it.
- **Lazy imports.** `node:fs/promises` (open/mkdir/unlink) and `node:fs`
  (constants) stay lazy per the existing comment — sibling tests mock node
  builtins with partial factories.
- **Error contract.** The three asserted message substrings stay verbatim;
  a new throw is permitted only for the racing-recreate case (`EEXIST`).
- **fd hygiene.** Every opened `FileHandle` is closed in `finally`; the leaf
  handle is closed after `writeFile` (never left to GC).

### Attack Surface Enumeration (for security fixes)

Ways an actor could write inside `spawnCwd` before the handler's write runs:

- **Agent Bash tool** — exact-literal allowlist of 13 `community-router.sh`
  invocations (`_cron-claude-eval-substrate.ts:385-399`), charset-restricted
  tokens, no `ln`/`mv`/`rm`/`nohup`; file tools removed via
  `CRON_NO_FILE_TOOLS` + `COMMUNITY_DISALLOWED_TOOLS`. Checked: yes, by the
  containment hook — *unless the hook itself is bypassed*, which is the threat
  actor this fix defends against.
- **Collector sidecar script** — `community-router.sh` appends
  `.soleur-collector-status/` records; fixed commands only.
- **`stageExactPaths` (`_cron-safe-commit.ts:507-530`)** — sibling
  lstat→`hash-object` pair on the same paths; a redirected *read* produces
  wrong blob bytes, which `expectedContent` byte-verify + `pushTipReason`
  refuse to push. Fail-closed already; NOT fixed here (not the alerted site;
  widening scope is its own review surface). Residual noted for the record.
- **`git -C spawnCwd` operations** (setOriginToken, config rewrite, commit) —
  path-resolved at exec; a swapped `.git` ancestor lands git ops on an
  attacker tree → commit misses the digest → `digestCommittedOnDefaultBranch`
  and liveness markers fail the run loudly. Fail-closed; unchanged.
- **`spawnCwd`'s own ancestors** (`ephemeralRoot`, `CRON_WORKSPACE_ROOT`):
  rename authority there is a sibling-process/cross-cron concern outside this
  function's contract (the caller chooses the root). Documented, not fixed.

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-community-publication.ts`
  — rewrite `writeDigestFileContained` (~50 lines replaced; `openContainedDir`
  and `createContainedFile` internals, docstring updated to describe fd pinning).
- `apps/web-platform/test/server/inngest/cron-community-publication.test.ts`
  — extend the `writeDigestFileContained` describe block (new cases below).

## Files to Create

- None.

## User-Brand Impact

- **If this lands broken, the user experiences:** a missing or failed daily
  community-digest run (public `[Scheduled]` issue + Sentry alert) — an
  internal-ops artifact, not user data.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing user-facing — the digest content is handler-rendered counts over
  public community activity; the fix only hardens where those bytes land on
  disk.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change reduces an already-narrow
  latent hazard on internal machinery; a broken fix fails the cron loudly
  (FAILED issue + Sentry), exposing no user data or workflow.
- `threshold: none, reason: the diff hardens an internal cron write path under apps/web-platform/server/ — failure modes are loud and confined to the ephemeral workspace, no user-facing surface or user data is touched.`

## Observability

```yaml
liveness_signal:
  what: "Daily `[Scheduled] Community digest` issue + dated digest file committed on main; cron run verdict via resolveOutputAwareOk"
  cadence: "daily (0 8 * * * cron)"
  alert_target: "Sentry + scheduled audit issue (FAILED stub via ensureScheduledAuditIssue)"
  configured_in: "apps/web-platform/server/inngest/functions/cron-community-monitor.ts"

error_reporting:
  destination: "Sentry via reportSilentFallback / handler logger"
  fail_loud: "digest write throw → step fails → run verdict FAILED → audit issue + Sentry"

failure_modes:
  - mode: "writeDigestFileContained throws (racing recreate, planted dir at leaf, hostile tree)"
    detection: "inngest step failure surfaced by resolveOutputAwareOk + FAILED audit issue"
    alert_route: "Sentry issue + scheduled-issue comment"
  - mode: "regression: digest bytes land but commit misses"
    detection: "digestCommittedOnDefaultBranch post-push verify + marker-3 existsSync stat"
    alert_route: "Sentry issue"

logs:
  where: "Inngest function logs + Sentry extras (fn=cron-community-monitor, spawnCwd)"
  retention: "platform-default"

discoverability_test:
  command: grep -c O_NOFOLLOW apps/web-platform/server/inngest/functions/_cron-community-publication.ts
  expected_output: "2"
```

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Internal security hardening of an existing cron write path.
No new architecture — the contained-write trust boundary is unchanged (same
invariant, race-free implementation); the fd-pinned technique reuses the
repo's established `O_NOFOLLOW` numeric-flag idiom. Assessment produced
in-process: this harness exposes no Task/agent spawn for domain leaders, so
the CTO-leader review was folded into the evidence-based technical ruling
recorded in `decision-challenges.md`.

### Product/UX Gate

Not applicable — `## Files to Edit`/`## Files to Create` contain no UI-surface
path (`*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`); mechanical override
did not fire; tier: none.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies grepped for
`_cron-community-publication.ts`, `cron-community-monitor.ts`,
`_cron-safe-commit.ts`, `writeDigestFileContained`, and the test file: zero
matches.

## Architecture Decision (ADR/C4)

None required. The contained-write trust boundary, its callers, and the
commit pipeline are unchanged — this is a same-invariant hardening of one
function, the "bug fix on an existing surface" skip case. C4 check: no new
external human actor, external system/vendor, container/data-store, or
actor↔surface relationship is introduced (the digest file, its path, and its
producer are unchanged), so no `model.c4`/`views.c4`/`spec.c4` edit is owed.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "implement — CodeQL alert #248 (js/file-system-race, severity high) at apps/web-platform/server/inngest/functions/_cron-community-publication.ts:699" [issue #10368 + brief] | Phase 1 implementation + Files-to-Edit entry | mapped |
| 2 | "the fix PR body must close ALL of them (one `Closes #N` per own body line)" [brief] | Ship-note AC (PR body carries 10 `Closes` lines); frontmatter `closes:` list | mapped |
| 3 | "assess whether the finding is a real residual race … and whether the correct fix is structural … vs a documented suppression — let the evidence decide" [brief] | Overview ruling + `decision-challenges.md` row + structural fd-pinned design | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| fd-pinned rewrite of `writeDigestFileContained` | "the correct fix is structural (open with O_NOFOLLOW-equivalent, fd-based dir walk, or write-to-temp+rename)" | asked |
| New unit tests incl. Linux dentry-pin regression | — | inferred — justification: `cq-write-failing-tests-before` and P1's property are unverifiable without a deterministic rename-swap fixture |
| `spawnCwd`-is-a-symlink refusal test | — | inferred — justification: new `open(spawnCwd, O_NOFOLLOW)` arm is a behavior change the suite must pin |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 2 | Estimated changed lines: ~140
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `writeDigestFileContained` performs no `lstat`/`stat`/`access`/`existsSync`
  call: `grep -nE '(lstat|stat|access|existsSync)\(' apps/web-platform/server/inngest/functions/_cron-community-publication.ts | grep -v '^\s*//'` returns zero matches inside the function body (other functions in the file may retain their own uses).
- [ ] Ancestor traversal opens each directory with
  `O_RDONLY | O_DIRECTORY | O_NOFOLLOW` and resolves children through
  `/proc/self/fd/<fd>/` on Linux (`process.platform === "linux"`).
- [ ] The leaf is created via `open` with
  `O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW` at mode `0o644`; a racing
  re-create fails closed.
- [ ] All six existing `writeDigestFileContained` tests pass unchanged, plus
  new tests: `spawnCwd` symlink refused; Linux-only dentry-pin regression
  (rename real ancestor + symlink decoy → bytes land in the renamed dir,
  decoy untouched); leaf racing-recreate fails closed.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-community-publication.test.ts` exits 0.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] Post-merge: `gh api repos/jikig-ai/soleur/code-scanning/alerts/248 --jq .state`
  reports `fixed` on the next scan (verified in ship's post-merge pass;
  verified command form, endpoint per GitHub REST docs).
- [ ] PR body carries ten `Closes #N` lines, one per issue: #10368, #10839,
  #11318, #11190, #11062, #10985, #10910, #10800, #10687, #10756 (ship-note;
  `ship` owns the PR body — assert the block lands there, not the title).

## Test Scenarios

- **unit** — Given `spawnCwd` is a symlink, when `writeDigestFileContained`
  runs, then it throws (containment refusal) and writes nothing.
- **unit** — Given a clean relative path, when ancestors are missing, then
  each is created beneath the pinned parent fd and the file lands at the
  expected path (existing test, unchanged).
- **unit** — Given an ancestor that is a symlink or a regular file, when the
  walk reaches it, then `ELOOP`/`ENOTDIR` maps to `ancestor is not a plain
  directory` (existing tests, unchanged).
- **unit** — Given the leaf is a directory, when the write runs, then
  `unlink`'s `EISDIR`/`EPERM` maps to `target is a directory` (existing test,
  unchanged).
- **unit (Linux-only)** — Given the leaf's parent dirfd was opened, when the
  real ancestor directory is renamed away and a symlink decoy occupies its
  name, then the leaf write through the pinned fd lands inside the *renamed*
  directory and the decoy target is untouched. Deterministic proof of the
  P1 property — exercises inside the race window by construction.
- **unit** — Given a leaf recreated between `unlink` and `open` (or an
  `O_EXCL` violation injected via test seam), when the create runs, then it
  throws instead of overwriting — fail-closed.

## Success Metrics

- CodeQL alert #248 resolves to `fixed` on the first scan after merge.
- All ten tracker issues closed by the merge.
- No behavior change in the daily digest pipeline (green run, digest file +
  issue produced).

## Dependencies & Risks

- **`/proc/self/fd` is Linux-only.** Mitigated: fallback path keeps atomic
  opens (no stat-based check→use anywhere, so the alert stays cleared);
  dentry pinning is production-Linux only. Residual on non-Linux is a
  dev-platform-only ancestor-swap window — documented in the code comment.
- **fs mock drift.** Sibling tests mock `node:fs/promises` with partial
  factories; lazy imports preserved and the real-fs suite uses real tmpdirs
  — no mock contract changes.
- **`close()` failures.** Each handle closed under `.catch(() => {})` so a
  double-close on a thrown path cannot mask the real error.
- **In-flight runs.** `writeDigestFileContained` is called inside `step.run`
  blocks; a replayed run re-executes the new code path against a fresh
  workspace — no memoized-shape migration needed (step return shapes
  unchanged).

## References & Research

- Alert: `https://github.com/jikig-ai/soleur/security/code-scanning/248`
- Node dirfd gap: nodejs/node#31110 (closed stale); libuv/libuv#4167.
- Same-class fix precedent: kodustech/kodus-ai#1532 (`/proc/self/fd` parent-dir
  pinning for `js/file-system-race`).
- In-repo `O_NOFOLLOW` precedent: `server/resolve-protected-branches.ts:68`,
  `server/compound-promote-create-gates.ts:449`, `server/dsar-export.ts:1808`,
  `server/kb-reader.ts:293`, `server/kb-binary-response.ts:108`.
- Containment lineage: #5091, #5111, #5199, #7122
  (`_cron-claude-eval-substrate.ts:357-417`, `_cron-safe-commit.ts:95-116`).
- Learnings:
  `knowledge-base/project/learnings/2026-06-10-bot-cron-safe-commit-substrate-symlink-removal.md`,
  `knowledge-base/project/learnings/best-practices/2026-06-05-render-off-tree-return-bytes-and-drop-toctou-with-the-reread.md`,
  `knowledge-base/project/learnings/best-practices/2026-04-19-codeql-orphan-issue-post-dismissal-sweep.md`.
