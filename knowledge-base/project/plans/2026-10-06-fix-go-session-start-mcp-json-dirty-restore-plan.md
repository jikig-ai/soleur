---
title: "fix(go): session-start .mcp.json restore overwrites a dirty tracked file"
type: fix
date: 2026-10-06
slug: go-session-start-mcp-json-dirty-restore
branch: feat-one-shot-9622-go-mcp-json-dirty-restore
issue: 9622
closes: 9622
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(go): session-start .mcp.json restore overwrites a dirty tracked file

## Overview

`/soleur:go` Step 0 (`plugins/soleur/commands/go.md`, the restore block under
`if [ "$DO_RESTORE" = true ]`) refreshes `.mcp.json` from local `main` with a
write-then-rename. It does so unconditionally. In this repo `.mcp.json` is
**tracked**, so an uncommitted local edit (observed 2026-10-06: `git status` showing `M` on `.mcp.json`, a
local Playwright launch variant) is silently replaced by main's bytes. The loss was
recoverable only because the operator had copied the file aside by hand.

Fix: before the write, if `.mcp.json` is tracked and differs from `HEAD`, **skip the
restore** and print `SOLEUR_SESSION_START_SKIPPED reason=mcp-json-dirty`. Skip was chosen
over timestamped-backup because it is the smaller change, leaves no stray file in the
worktree (the existing block already treats stray `*.soleur-tmp` files as a defect), and
needs no new operator-facing artifact to explain. An untracked `.mcp.json`, or a tracked
one that matches `HEAD`, keeps today's behavior.

The edit is local to the restore block and the one prose sentence after the fence. It is
outside the three byte-identical resolver snippets (R8) and adds no bash fence (R10).

## Research Insights

### Premise Validation (Phase 0.6)

- Issue #9622 is OPEN, no closing PR, no open PR mentions it. Not stale.
- The cited block exists verbatim on `origin/main`
  (`git grep -c 'git show main:.mcp.json > .mcp.json.soleur-tmp' origin/main -- plugins/soleur/commands/go.md` = 1).
- `.mcp.json` is tracked here (`git ls-files --error-unmatch .mcp.json` succeeds), as the issue says.
- No ADR is in play: grep of `knowledge-base/engineering/architecture/decisions/` for the restore
  mechanism finds only unrelated `.mcp.json` mentions (ADR-052, ADR-213, ADR-271); ADR-179 (the
  session-gate plugin-root contract) does not mention the restore.
- Proposed mechanism (skip vs backup) is not in any rejected-alternatives table.

### Property List and Cut List (Phase 0.6b)

Properties the issue buys:

1. A tracked `.mcp.json` with uncommitted changes is never overwritten by the session-start gate.
2. The skip is visible, not silent (a named marker, in the family every sibling skip uses).
3. Everything the issue did not name is unchanged: clean-tracked and untracked files still restore;
   the restore stays non-fatal, POSIX, and free of `set -e/-u/-o pipefail`.

Cut List (mechanisms considered and removed before design):

| Mechanism | Property | What covers it / why cut |
|---|---|---|
| Timestamped backup then overwrite | 1 | Skip already buys property 1 with no new artifact; backup adds a file to the worktree and a second marker spelling. Issue permits either; lead directive prefers skip. |
| Compare to `main` instead of `HEAD` | 1 | Would flag every stale-but-clean worktree as dirty, which is exactly the case the refresh exists for. `HEAD` is the right baseline for "uncommitted". |
| New operator-facing bullet in the marker list above the fence | 2 | None of the existing `mcp-json-*` markers has one; the one-line prose fix after the fence carries the remedy. |
| Equal-to-main silent branch (no marker when dirty file already equals main) | 2 | YAGNI. A dirty file that equals main prints a harmless extra marker; the extra branch and its rows buy nothing the issue asked for. |
| Editing a Codex/Devin/Grok/Cursor mirror | 3 | None carries the block (see Mirror check). |

### Mirror check (lead item d)

- `.grok/commands/go.md` is a **symlink** to `../../plugins/soleur/commands/go.md`
  (`ls -l` shows `->`); one edit covers it. `diff -q` against the target is clean.
- `plugins/soleur/{codex,devin,}/skills/go/SKILL.md` contain **zero** `DO_RESTORE` / `.mcp.json`
  / `session-start` hits; they are thin pointers, not copies.
- `git ls-files` shows no `.cursor` go copy. `grep -rl DO_RESTORE` over the repo finds exactly two
  files: `go.md` and `go-session-gates.test.sh`. No parity test pins the restore text:
  `go-routing-table-parity.test.sh` pins only the routing table; `workflow-fidelity.test.ts`
  pins resolver call-forms (untouched); `devin-cloud-mode.test.ts` derives files naming a Devin
  cache path (go.md must stay in that set, and does).
- Telemetry: `apps/web-platform/server/git-lock-marker-telemetry.ts` `MARKER_RE` does not include
  `SOLEUR_SESSION_START_SKIPPED`, and its own test comments state the sibling reasons are
  "visible on the operator's terminal (layer 7) and nowhere else". The new reason joins that family;
  no allowlist needs a new entry (verified by grep, no `reason=` enumeration exists server-side).

### Key finding the issue did not state: the suite's default fixture IS a tracked-dirty file

`mk_workspace` in `plugins/soleur/test/go-session-gates.test.sh` commits `{"fixture":"main"}` on
`main`, then overwrites the working copy with `{"fixture":"working-copy-differs"}`. That is
precisely the incident shape (tracked, dirty vs `HEAD`). Five existing rows depend on the gate
overwriting it and will go RED after the fix, for the right reason:

| Row | Dependence on overwrite |
|---|---|
| R3 (inside the R1/R2/R3 loop, `i == 2`) | asserts `.mcp.json` equals `main:.mcp.json` |
| R3e | writes DIRTY on top, asserts restored to main |
| R3f | asserts restore ran with the manager absent |
| R3g | needs the restore to reach `git show` to emit `mcp-json-no-local-main` (dirty guard now fires first) |
| R11 | writes DIRTY on top, asserts restored to main on the capability-refusal arm |

So the work is NOT "add one row": it is a second fixture shape (clean tracked file that differs from
`main`, i.e. a worktree cut before main's `.mcp.json` changed) plus re-pointing those five rows at
it, plus the new rows. `R3d` is unaffected (it `git rm --cached` + commits, making the file
untracked on `main`, which is the untracked arm).

### Other facts that shaped the design

- The restore reads **local** `main`, not `origin/main`. Out of scope; noted so nobody "fixes" it here.
- `git diff --quiet HEAD -- .mcp.json` (with `HEAD`), not the issue's literal `git diff --quiet -- .mcp.json`.
  Without `HEAD`, a change that is `git add`ed but uncommitted compares worktree-to-index, reports
  clean, and the file is overwritten. Staged-only edits are uncommitted edits.
- Exit-code policy: `git diff --quiet` returns 1 for "differs" and >1 for errors (for example
  128 on an unborn branch with a staged `.mcp.json`). The guard treats **any non-zero** as "do not
  overwrite". An error probing the user's file must fail toward keeping it.
- Exit codes MEASURED 2026-10-06 in a throwaway `mktemp` repo (not recalled), git env scrubbed:

  | State of `.mcp.json` | `git ls-files --error-unmatch` | `git diff --quiet HEAD --` | `git diff --quiet --` (issue's form) |
  |---|---|---|---|
  | untracked | 1 | not reached | not reached |
  | tracked, clean | 0 | 0 | 0 |
  | tracked, unstaged edit | 0 | 1 | 1 |
  | tracked, staged-only edit | 0 | 1 | **0 (reads clean; would overwrite)** |
  | tracked, deleted from worktree | 0 | 1 | not measured |
  | staged on an unborn branch | 0 | **128** | not measured |
  | untracked, born repo | 1 | 0 | not measured |
  | untracked, unborn repo | 1 | **128** | not measured |

  The last row is why the `ls-files` conjunct stays: without it an untracked file on an unborn `HEAD`
  would be reported `mcp-json-dirty` instead of the accurate `mcp-json-no-local-main`.

- A tracked file deleted from the worktree is "differs from `HEAD`" and is skipped as dirty. Acceptable:
  conservative, and the operator who deleted it chose the state.
- `$?` inside the existing `else` arm (`SHOW_RC=$?`) must remain the status of `git show`. Converting
  the outer `if git show` into `if <dirty>; elif git show …; else` preserves that (in an `if/elif/else`
  chain the `else` sees the last evaluated condition's status; verified in bash and dash). R3d and R3g do
  NOT pin it: they drive `absent-on-main` and `no-local-main`, which never read `SHOW_RC`. Only the
  `mcp-json-read-failed rc=${SHOW_RC}` arm does, and no existing row reaches it, so R12g (below) is added
  to pin it.
- Bare root verified (plan-review seat ran the proposed block against a bare clone): `ls-files --error-unmatch`
  returns 1 there, the guard falls through, and the restore runs as before. The session-start rule names the
  bare root as a primary use, so this matters.
- Status-quo hazard, not introduced here: on a feature branch that COMMITTED a `.mcp.json` change, `HEAD`
  differs from main and the file is clean, so the gate overwrites it with main's bytes and a later
  `git commit -a` would silently revert the branch's change. Out of scope for #9622; recorded as a
  decision challenge (a design where tracked files are never refreshed contradicts ask 9).
- Acknowledged limitation (not deferred scope): when the gate refreshes a clean tracked file whose
  `HEAD` differs from main, the refreshed file is itself dirty vs `HEAD`, so later session-starts in
  that worktree print `mcp-json-dirty` and stop refreshing until the operator commits or
  `git checkout -- .mcp.json`. Failing toward "do not overwrite" is the intended direction.
- Institutional learnings applied: write-then-rename and "measure the cause, do not name one"
  (AP-021) are already in the block and are preserved; the suite's `${ws:?}` guard lesson (R3d
  comment) applies to every new row that runs `git -C "$ws"` from the parent shell; `fixture-env`
  subshell pattern (R3d/R3g) for fixture writes.

## Open Code-Review Overlap

- #8659 (`review: 33 test suites replace test-helpers' composed EXIT trap …`) names
  `plugins/soleur/test/go-session-gates.test.sh`. **Acknowledge:** different concern (EXIT-trap
  composition across suites); this plan neither touches the trap nor makes it worse. Issue stays open.
- No open code-review issue names `plugins/soleur/commands/go.md` or the fixture baseline files.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: agent-tooling shell/markdown fix, no UI surface, no
regulated-data surface (the marker prints no path or content), no infrastructure, no ADR/C4 change
(a bug fix on an existing surface; an engineer reading the existing ADRs and C4 is not misled
afterward).

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) status quo, a local uncommitted
  `.mcp.json` edit silently replaced at session start, or (b) the guard misfires and the benign
  main refresh never lands, which shows as a stale MCP server registry plus a visible
  `mcp-json-dirty` line.
- **If this leaks, the user's workflow is exposed via:** nothing new. The guard only reads local
  git state; the marker carries a fixed reason string and no path, content, or token. Nothing is
  sent anywhere (the marker is not in the server-side `MARKER_RE`).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the blast radius is one operator's uncommitted local
  config on their own machine, recoverable from the editor or shell history, with no cross-user data
  or credential exposure; it is not `aggregate pattern` because no population is affected by one
  occurrence. The touched paths (`plugins/soleur/commands/go.md`, `plugins/soleur/test/**`) do not
  match preflight Check 6's `SENSITIVE_PATH_RE`, so no scope-out bullet is required.

## Observability

Customer-executed `plugins/` shell that also runs hosted (Concierge runs `/soleur:go`). Layer
citation per `hr-observability-layer-citation`: the signal is layer 7 (`cli-stdout-artifact`) on the
self-hosted path, and on the hosted path **no server-side sink exists for any `SOLEUR_SESSION_START_SKIPPED`
reason today** (`MARKER_RE` omits the family; its test comment says so). This plan does not change
that: routing a per-user file-state marker to Soleur infrastructure would be a new data flow for no
reviewer need. The durable artifact is the file itself: the preserved `git status` showing `M` on `.mcp.json` is visible in
`git status` after the session.

```yaml
liveness_signal:
  what: "SOLEUR_SESSION_START_SKIPPED reason=mcp-json-dirty printed to the Bash tool-result stdout when the guard fires; a clean/untracked file prints nothing (existing behavior)"
  cadence: per session start (every /soleur:go invocation)
  alert_target: operator reads it in-session (layer 7); no pager, by design
  configured_in: plugins/soleur/commands/go.md (Step 0 restore block)

error_reporting:
  destination: stdout marker (layer 7); the dirty file persisting in git status is the durable artifact
  fail_loud: the marker line itself; any non-zero probe status also takes the skip path, so an error never degrades to an overwrite

failure_modes:
  - mode: guard predicate regresses and a dirty tracked file is overwritten again
    detection: go-session-gates.test.sh rows R12/R12b/R12c/R12d/R12f fail in CI (suite is a required shard leg)
    alert_route: red CI on the PR / merge queue
  - mode: guard over-fires and a clean/untracked file stops refreshing
    detection: go-session-gates.test.sh R3 and R12e (must-PASS) fail in CI
    alert_route: red CI on the PR / merge queue
  - mode: restore leaves .mcp.json.soleur-tmp behind on the skip path
    detection: R12 asserts no temp file in the worktree after the run
    alert_route: red CI on the PR / merge queue

logs:
  where: Bash tool-result stdout of the session (layer 7); not persisted by Soleur
  retention: session lifetime; the dirty file itself persists until the operator resolves it

discoverability_test:
  command: grep -o 'SOLEUR_SESSION_START_SKIPPED reason=mcp-json-dirty' plugins/soleur/commands/go.md
  expected_output: SOLEUR_SESSION_START_SKIPPED reason=mcp-json-dirty
```

## Files to Edit

- `plugins/soleur/commands/go.md` — restore block only (see Phase 2). Plus one prose sentence after
  the fence (the "refresh is harmless inside a worktree" line) and one fence-internal comment.
- `plugins/soleur/test/go-session-gates.test.sh` — fixture mode, five row re-points, new R12 rows,
  `MIN_ASSERTIONS` floor.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — regenerate with `--write-baseline` (the P1b
  row set for this file is expected to move); never hand-edit.
- `plugins/soleur/test/fixture-dir-operand-assert.baseline.txt` — regenerate only if its scan moves.

## Files to Create

- None in `plugins/`. Planning artifacts only: this plan and
  `knowledge-base/project/specs/feat-one-shot-9622-go-mcp-json-dirty-restore/tasks.md`.

No glob is prescribed. Every path above was confirmed present via `git ls-files`.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: rows first, RED, then the fix.

### Phase 1 — RED: fixture mode and rows (test file only)

1. `mk_workspace <dir> [mode]`: modes are named `dirty` (the default, unchanged: tracked, dirty vs `HEAD`,
   the incident shape) and `stale`. Put a loud comment on the default: a future row wanting "the restore
   works" would otherwise silently get the skip arm. New `mode=stale`: after committing `{"fixture":"main"}` on `main`,
   `git checkout -q -b feat`, write `{"fixture":"head-stale"}`, `git add`, `git commit -q` — so the
   working copy is **clean vs `HEAD`** and differs from `main`. Both writes go through the existing
   `git_fixture_env "$dir" || { …; exit 2; }` form and quoted heredocs.
   `fresh_ws <name> [mode]` passes the mode through.
2. Re-point the five dependent rows at `stale` and delete the now-wrong explicit DIRTY writes in R3e
   and R11 (a stale fixture already differs from main; leaving the `printf DIRTY >` would make the
   file tracked-dirty and the rows would test the new guard instead of the restore). Update the two
   comments that justify those writes ("Dirtied for the same reason…") to say the stale fixture
   supplies the difference.
   - R1/R2/R3 loop: `ws="$(fresh_ws "r$i" stale)"` (other gates are indifferent to the mode).
   - R3e, R3f, R3g, R11: `fresh_ws … stale`.
   - R3g's `git branch -m main notmain` still works (`main` is not the checked-out branch in `stale`).
3. Add section `R12. a tracked .mcp.json with uncommitted changes is never overwritten (#9622)`
   after R11c and before R6 (it needs `NOCAP_ROOT`/`NOCAP_HOME` from R11 and `CLASSLESS` from R3e).
   Every fixture write from the parent shell uses the `${ws:?…}` guard and the
   `( git_fixture_env "$ws" || …; git -C "$ws" … ) || { echo FATAL; exit 2; }` subshell shape.

   | Row | Fixture | Arm driven | Assertions (each a `want_*` call) |
   |---|---|---|---|
   | R12 | default (tracked, dirty) | success arm (`FIX_ROOT`, `delivered_fence 2`) | content still `{"fixture":"working-copy-differs"}`; `want_in` `SOLEUR_SESSION_START_SKIPPED reason=mcp-json-dirty`; no `.mcp.json.soleur-tmp`; `want_in` `STUB_WORKTREE_MANAGER argv=cleanup-merged` (the skip is non-fatal and takes only the restore) |
   | R12b | default + `git add .mcp.json` (staged, worktree == index != `HEAD`) | success arm | content unchanged; marker present (this row exists to kill the missing-`HEAD` mutation) |
   | R12c | default | capability-refusal arm (`NOCAP_ROOT`, `FENCE_LITERAL[2]`, `NOCAP_HOME`) | content unchanged; marker present |
   | R12d | default | classifier-absent arm (`CLASSLESS`, `delivered_fence 2`) | content unchanged; marker present |
   | R12e | `stale` + `git rm --cached` + commit (file untracked, main carries one) | success arm | content equals `main:.mcp.json` (1 assertion; it cannot hold if the guard fired, so no marker assertion). Must-PASS, characterizes unchanged behavior. Fixture copies R3d's `${ws:?…}` + `( git_fixture_env … )` shape exactly |
   | R12f | two bare repos built with `assert_fixture_dir` + `git_fixture_env`: (i) `git init -b main`, `.mcp.json` staged, **no commit** (unborn `HEAD`, no `main`); (ii) same but `.mcp.json` left untracked | success arm | (i) marker `reason=mcp-json-dirty` present, content unchanged. `git diff HEAD` exits 128 here, so this pins "any non-zero skips"; before the fix only the marker assertion is RED (the file survives because there is no `main`). (ii) `want_not_in` `reason=mcp-json-dirty` and `want_in` `reason=mcp-json-no-local-main`: pins the `ls-files` conjunct, which no born-repo row can see (4 assertions total) |
   | R12g | `stale` fixture plus `mkdir "$ws/.mcp.json.soleur-tmp"` before the run | success arm | the temp redirect fails (`Is a directory`, rc 1): `want_in` `reason=mcp-json-read-failed rc=1`, `want_not_in` `reason=mcp-json-dirty`. Pins `SHOW_RC=$?` surviving the `elif` restructure (2 assertions). Leave the directory; the block's `rm -f` only complains on stderr |

   No assertion is added to R3: the existing "restored from main" check cannot pass if the guard fired
   on that stale fixture, so a marker `want_not_in` there would be redundant.
4. Run the suite with `SOLEUR_GO_GATES_SKIP_H3=1`. Expected before the fix: R12, R12b, R12c, R12d, R12f (marker assertion only) RED;
   R12g and R3/R3e/R3f/R3g/R11/R12e GREEN (the old code still restores clean files). If any R12 row is green
   before the fix, the fixture is wrong, not the code.

### Phase 2 — GREEN: the guard in go.md

Edit only inside the `if [ "$DO_RESTORE" = true ]; then` block. Change the first condition from
`if git show main:.mcp.json > .mcp.json.soleur-tmp 2>/dev/null; then` to:

```sh
  # An uncommitted edit to a TRACKED .mcp.json is the operator's work, not stale state (#9622).
  # Compared to HEAD, not the index: `git diff --quiet` without HEAD reads a staged-only change
  # as clean. ANY non-zero status (1 = differs, >1 = could not tell, e.g. an unborn branch) skips:
  # an error probing the file must fail toward keeping it. Untracked, or tracked and equal to
  # HEAD, falls through to the restore below, unchanged.
  if git ls-files --error-unmatch -- .mcp.json >/dev/null 2>&1 \
     && ! git diff --quiet HEAD -- .mcp.json 2>/dev/null; then
    echo "SOLEUR_SESSION_START_SKIPPED reason=mcp-json-dirty"
  elif git show main:.mcp.json > .mcp.json.soleur-tmp 2>/dev/null; then
```

Everything else in the block (inner `mv`, the `else` with `SHOW_RC=$?`) is untouched. Notes:

- No `set` option, no `[[`, no `timeout` command, no `find` call; POSIX `git` flags only. R9's banned-form rows and
  R10b's "no `find` after the resolver" rows stay green. The resolver snippet (R8) is not touched.
- The two comment lines above the existing `# Write-then-rename` paragraph that call `.mcp.json`
  "untracked — so the loss is unrecoverable" are reworded to say: usually untracked on a customer
  machine (unrecoverable) and tracked in this repo, where the same loss applies. Comment-only.
- The prose after the fence: replace "The `.mcp.json` refresh is harmless inside a worktree (file gets
  overwritten on next session-start from the new CWD)." with a version that keeps that sentence for
  clean/untracked files and adds that a tracked `.mcp.json` with uncommitted changes is left alone and
  reported as `SOLEUR_SESSION_START_SKIPPED reason=mcp-json-dirty`, with the remedy
  (`git diff HEAD -- .mcp.json` to review, then commit or `git checkout -- .mcp.json` to accept the committed version). The sentence must also say the marker can come from the gate's own earlier refresh of a stale file, which that same `git checkout` clears.
  One to two sentences; do not touch "Skip silently on first error".

### Phase 3 — floors, baselines, regression sweep

1. Raise `MIN_ASSERTIONS` in the test file to the **measured** total with `SOLEUR_GO_GATES_SKIP_H3=1`
   (the file's own comment: never derive it from a local run where `claude` is present). Expected
   194 + 17 = 211: R12 (4) + R12b (2) + R12c (2) + R12d (2) + R12e (1) + R12f (4) + R12g (2). The
   per-row counts are the intent; a dropped assertion must not hide inside the floor. Measure, do not
   trust this number.
   Update the "Raising it is part of adding a row" comment with the new total.
2. `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `fixture-dir-operand-assert.test.sh`.
   Expect `fixture-relative-assert.baseline.txt` (line pinning `go-session-gates.test.sh` at 5 rows) to move:
   deleting the R3e/R11 `printf >` writes and adding new `git -C "$ws"` / redirect sites changes the
   row-by-row set. Regenerate with `--write-baseline` in the same
   commit (row-by-row equality; the file's header is explicit). `fixture-env-adoption.test.sh` must
   stay green; the new `git -C "$ws"` calls sit inside the existing subshell/`git_fixture_env` shape.
3. Run: `SOLEUR_GO_GATES_SKIP_H3=1 bash plugins/soleur/test/go-session-gates.test.sh`,
   `bash plugins/soleur/test/go-routing-table-parity.test.sh`,
   `bun test plugins/soleur/test/workflow-fidelity.test.ts plugins/soleur/test/devin-cloud-mode.test.ts plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/harness-parity-tree.test.ts plugins/soleur/test/invocation-axis.test.ts`,
   and `apps/web-platform` vitest `plugin-root-anchoring.test.ts` (it mentions the sibling markers).
4. One real-harness run of H3 (suite without the skip env) if `claude` is on PATH, so the delivered
   fence is exercised by the actual loader once; H3 asserts only the three RESOLVE lines, which this
   change does not touch. Report skip reason if absent.
5. PR body: one sentence on why five existing rows changed, a note that `MIN_ASSERTIONS` must be re-measured
   (never hand-merged) after any rebase, and a pointer to the decision challenges below.

Constraint carried through every phase: do **not** touch `/data/git-repositories/jikig-ai/soleur/.mcp.json`
(the primary checkout's own dirty file). All behavior is exercised only in `mktemp` fixture repos.

## Guard Contract

The deliverable includes a guard (the dirty-file check) and the suite rows that pin it.

### Guard 1 — tracked-dirty .mcp.json overwrite guard

**Property.** The session-start gate never replaces the bytes of a `.mcp.json` that is tracked and
differs from `HEAD`, on any path that reaches the restore, while a clean-tracked or untracked file is
still refreshed.

**Assembly.** The single chokepoint is the `if [ "$DO_RESTORE" = true ]` block in `go.md`'s Step 0
fence: it holds the only writer (`mv .mcp.json.soleur-tmp .mcp.json`) and is the sole consumer of
`DO_RESTORE`. Three arms set `DO_RESTORE=true` and all three flow through it: the success arm, the
`reaper-capability-unverified` arm, and the `classifier-absent` arm. The guard is placed at the shared
block, not per arm, and R12/R12c/R12d drive one dirty fixture through each of the three arms (not just
the first). Members drift; the chokepoint is structural: a fourth `DO_RESTORE=true` arm is covered by
construction, a second writer outside the block is NOT, which is mutation 5.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the guard (restore unconditional, today's code) | RED: R12, R12b, R12c, R12d, R12f |
| 2 | Guard always true (`skip` on every file) | RED: R3 (clean tracked must restore) and R12e (untracked must restore) |
| 3 | Drop `HEAD` from `git diff --quiet HEAD -- .mcp.json` | RED: R12b (staged-only edit) |
| 4 | Move the guard to just before `mv`, after `git show … > .mcp.json.soleur-tmp`, without cleaning up | RED: R12 "no temp file" assertion (user bytes survive, the window is wrong) |
| 5 | Add a second writer for `.mcp.json` in another arm, outside the restore block | RED only if that arm is driven with a dirty fixture: R12c (capability arm) and R12d (classifier arm) are the two non-success arms driven |
| 8 | Drop the `ls-files` conjunct (probe `git diff HEAD` alone) | RED: R12f (ii) (untracked file on an unborn `HEAD` would read `mcp-json-dirty`) |
| 9 | Clobber `$?` between the `elif` condition and the `else` arm | RED: R12g |
| 6 | Guard prints nothing on skip (silent keep) | RED: R12 marker `want_in` (a guard reporting "kept" without a marker is vacuous) |
| 7 | Treat probe errors as clean (test `git diff --quiet HEAD` for rc == 1 instead of rc != 0) | RED: R12f (unborn `HEAD` makes `git diff HEAD` exit 128; marker must still be `mcp-json-dirty`) |

**Harness rows (edits to the SUITE that must drive it RED, and must-PASS inputs that are not the canonical):**

- Suite edit H-a: make `mk_workspace`'s default branch write the same bytes as the committed file
  (a clean fixture). R12/R12b/R12c/R12d must go RED on the missing marker (R12f builds its own unborn repo and is unaffected by this edit). This is what proves the
  rows decide on the guard and not on a fixture that is accidentally clean.
- Suite edit H-b: make `mk_workspace stale` behave like the default (dirty). R3, R3e, R3f, R3g, R11 must
  go RED on "not restored"; that proves the stale fixture is load-bearing for the must-PASS rows.
- Must-PASS non-canonical inputs: R3 restores a **tracked-clean** file (head-stale vs main) and R12e
  restores an **untracked** file. They differ from each other and from the dirty canonical, so a guard
  that rejects everything cannot satisfy both.
- Dispatch floor: `MIN_ASSERTIONS` is raised in the same diff; the suite's L2 decider self-tests and
  ledger reconciliation already prevent a `ck; pass` decider.

**Anchor.** No stored value is compared (the guard reads live git state), so there is no hash/registry
to anchor. The only count-like control is the `MIN_ASSERTIONS` floor, which proves cardinality and not
identity; row identity is carried by the named rows above and by L2.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "fix the /soleur:go session-start .mcp.json restore so it does not overwrite a tracked, dirty .mcp.json" [brief] | Phase 2 (guard) | mapped |
| 2 | "skip with a SOLEUR_SESSION_START_SKIPPED reason=mcp-json-dirty marker, or back it up first" [brief] | Phase 2 (skip with marker; backup in Cut List) | mapped |
| 3 | "Edit only the restore block in plugins/soleur/commands/go.md Step 0 (outside the three byte-identical resolver fences pinned by go-session-gates.test.sh)" [brief] | Files to Edit (go.md restore block + one prose sentence + one fence comment) | mapped |
| 4 | "add a test row" [brief] | Phase 1 (R12 section) | mapped |
| 5 | "the primary checkout has a locally modified tracked .mcp.json (M .mcp.json) that must not be touched or overwritten — do the work in a fresh worktree" [brief] | Phase 3 constraint; all behavior exercised in `mktemp` repos | mapped |
| 6 | "Also check whether the prose after the fence ... needs a one-line update" [brief] | Phase 2 prose edit | mapped |
| 7 | "check whether other go mirrors ... carry the same restore block" [brief] | Research Insights, Mirror check (none; Grok is a symlink) | mapped |
| 8 | "the restore must remain non-fatal, must not enable set -e/-u/pipefail, and must stay POSIX" [brief] | Phase 2 notes; R9 rows stay green | mapped |
| 9 | "a clean-tracked/untracked row still restoring" [brief] | R3 (tracked-clean) + R12e (untracked) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| go.md guard + marker | asks 1–2 | asked |
| go.md prose sentence | ask 6 | asked |
| go.md fence comment reword | "Edit only the restore block" | inferred — justification: the existing comment asserts `.mcp.json` is untracked, which this fix contradicts; leaving it would make the block self-contradictory |
| `mk_workspace` stale mode and five row re-points | "add a test row" | inferred — justification: the suite's default fixture is itself a tracked-dirty file, so five existing rows depend on the overwrite and go RED after the fix; without a second fixture shape the clean-restore rows cannot exist |
| R12 / R12b / R12c / R12d / R12e | ask 4, ask 9 | asked |
| R12f / R12g (unborn HEAD probe-error path; read-failed `SHOW_RC`) | — | inferred — justification: the guard's fail-toward-keeping policy on a probe error is a stated design decision and a mutation row (7) needs a row that can see it |
| `MIN_ASSERTIONS` raise | — | inferred — justification: the suite's floor must track its rows or deleting the new rows stays green |
| baseline regeneration | — | inferred — justification: `fixture-relative-assert` and `fixture-dir-operand-assert` pin per-file site counts by row-equality; new `git -C "$ws"` sites reddens them unless regenerated in the same commit |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 4 | Estimated changed lines: ~150 (go.md ~12, test file ~120, baselines ~2)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] With a tracked `.mcp.json` that differs from `HEAD` (unstaged), the Step 0 fence leaves its bytes
  unchanged and prints `SOLEUR_SESSION_START_SKIPPED reason=mcp-json-dirty` (R12).
- [ ] Same when the change is staged but uncommitted (R12b), on the capability-refusal and
  classifier-absent arms (R12c, R12d), and when `HEAD` is unborn so the probe errors (R12f). A read failure still reports `mcp-json-read-failed rc=1` (R12g).
- [ ] The skip is non-fatal: `cleanup-merged` still dispatches on the success arm (R12), and no
  `.mcp.json.soleur-tmp` is left (R12).
- [ ] A tracked-clean `.mcp.json` that differs from `main` is still restored and prints no
  `mcp-json-dirty` (R3); an untracked one is still restored (R12e).
- [ ] R3d (main carries none) and R3g (no local main) stay green, and R12g pins `SHOW_RC=$?` for the
  `read-failed` arm that neither of them reaches.
- [ ] `go.md` diff is confined to the restore block, one fence-internal comment, and the one prose
  sentence; R8 (byte-identical resolvers) and R10 (three fences, no fourth) stay green. Verify with
  `git diff --stat` and a read of the hunk headers: no hunk inside a `# --- soleur plugin-root resolver`
  region.
- [ ] `bash plugins/soleur/test/go-session-gates.test.sh` (with `SOLEUR_GO_GATES_SKIP_H3=1`) is green
  at `MIN_ASSERTIONS` equal to the measured total; fixture baselines are green (regenerated only if
  they moved).
- [ ] `/data/git-repositories/jikig-ai/soleur/.mcp.json` in the primary checkout is untouched
  (`git -C /data/git-repositories/jikig-ai/soleur status --short .mcp.json` still shows `M`, same
  `sha256sum` before and after the work).
- [ ] PR body carries `Closes #9622` and a `## Changelog` section (`semver:patch`).

### Post-merge (operator)

- None. No deploy, migration, or infrastructure step.

## Test Scenarios

- Given a tracked `.mcp.json` edited but not staged, when the session-start gate runs, then the file is
  byte-identical and `reason=mcp-json-dirty` is printed and the reaper still runs.
- Given the edit is `git add`ed but not committed, when the gate runs, then it is still skipped (HEAD
  comparison, not index).
- Given a worktree cut before main's `.mcp.json` changed (tracked, clean, differs from main), when the
  gate runs, then it is refreshed to main's bytes with no marker.
- Given `.mcp.json` is untracked and main carries one, when the gate runs, then behavior is unchanged
  (refreshed).
- Given `main` carries no `.mcp.json` and the local file is untracked, then `mcp-json-absent-on-main`
  is still reported and the file survives (R3d, unchanged).
- Given an unborn branch with a staged `.mcp.json`, when the gate runs, then `git diff HEAD` errors
  (rc 128) and the file is kept with `mcp-json-dirty` (R12f).

## Risks and Sharp Edges

- **The five fixture-dependent rows are the real risk.** A reviewer who sees only "add a row" will be
  surprised that R3/R3e/R3f/R3g/R11 change. The plan's Research Insights table is the explanation;
  the PR description should repeat it in one sentence.
- Do not "simplify" the guard to `git diff --quiet -- .mcp.json` (the issue's literal form): it misses
  staged-only edits. R12b exists to hold that line.
- Do not add a fourth ` ```bash ` fence or a `~~~` fence to `go.md`; R10 counts bash fences file-wide.
- Do not add `set -e/-u/-o pipefail`, `timeout`, `sed -i`, `readlink -f`, `stat -c`, `xargs -r` to fence
  code; R9 bans them and strips only comment lines.
- A parent-shell `git -C "$ws"` in a new row must be preceded by `: "${ws:?…}"` (an empty `$ws` makes git
  resolve against the caller's repository, which is how the primary checkout's own `.mcp.json` could be
  unstaged by a test; this is the R3d lesson). No apostrophe inside the `:?` word.
- `MIN_ASSERTIONS`: measure with `SOLEUR_GO_GATES_SKIP_H3=1`; a local run with `claude` present counts
  two extra H3 assertions and CI will redden on the difference (#8418).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. This one is filled.

## References

- Issue: #9622 (`fix(go): session-start .mcp.json restore overwrites a dirty tracked file`)
- Code: `plugins/soleur/commands/go.md` (Step 0 restore block), `plugins/soleur/test/go-session-gates.test.sh`
- Prior art in the same block: #8308 (write-then-rename), #8401 (restore decoupled from the reaper,
  `DO_RESTORE`), AP-021 (measure the cause, do not name one)
- ADR-179 (session-gate plugin-root contract; unchanged by this fix)
