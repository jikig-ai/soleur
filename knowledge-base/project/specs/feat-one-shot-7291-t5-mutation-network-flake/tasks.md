# Tasks — fix: T5 mutation arm reports "vacuous" when the mutant never executed

Plan: `knowledge-base/project/plans/2026-08-12-fix-t5-mutation-arm-network-flake-plan.md`
Issue: #7291 · Branch: `feat-one-shot-7291-t5-mutation-network-flake` · Lane: `cross-domain`

Single file under edit: `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`.
Read the plan's `## Conventions and constraints` before the first edit — four bash traps in it are
load-bearing (`local` outside a function, the `_skip()`/`arm_skip()` name collision, the `#7005`
SIGPIPE prohibition, and the `$(grep -c … || true)` idiom).

## Phase 0 — Preconditions

- [ ] 0.1 Confirm `docker info`, `terraform`, `python3` available; the suite `_skip()`s without them.
- [ ] 0.2 Baseline the suite: run it once, record the summary line and the current assertion total.
- [ ] 0.3 Re-read the T5 mutation arm and the `drive.sh` heredoc end-to-end before editing
      (`hr-always-read-a-file-before-editing-it`).

## Phase 1 — Capture the deciding datum (probe-first; must precede Phase 2)

- [ ] 1.1 Add one execution-marker `echo` to the `drive.sh` heredoc, immediately above
      `. /work/doppler-dl.sh` and **below** the capture-server guard.
- [ ] 1.2 Add a **structural** (hard-exit, uncounted) guard asserting the marker is present in the
      **mounted** artifact `$TMP/drive.noerrexit.sh`, after the arm's `sed 's/^set -e$/true/'` —
      not in the source heredoc. Pins the transform's application, not just its correctness.
- [ ] 1.3 Replace the trailing `|| true` on the arm's `docker run` with a plain `rc=$?` assignment
      on the next line. **Not `local`** — the arm is top-level; `local` errors there, leaves the
      variable unset, and `set -u` then kills the suite mid-run.
- [ ] 1.4 Emit the captured rc and the tail of `$TMP/out/stdout` in **every** verdict branch. Name
      the measured rc classes (125 pull, 100 apt, 2 capture-server) as *classification offered*,
      never as an asserted cause — AP-021/ADR-166.
- [ ] 1.5 Capture whether the T5 **primary** arm executed into a variable, before the mutation arm's
      `rm -rf "$TMP/out"` destroys the evidence, and include it in the skip reason as evidence only.

## Phase 2 — The counted verdict, and an honest floor

- [ ] 2.1 Add the `SKIPPED` counter and `arm_skip()` reporter, following
      `git-lock-chardevice-sweep.test.sh`'s existing idiom (uppercase counter, `Skipped: N`).
      Do **not** rename `_skip()`.
- [ ] 2.2 Add the capture-integrity precondition ahead of the verdict branch: missing or empty
      `$TMP/out/stdout` with rc 0 ⇒ hard `fail`, never skip.
- [ ] 2.3 Rewrite the verdict as an ordered branch — `CHMOD_RAN` → `FIXTURE:` → marker → else fail —
      with the ordering rationale commented.
- [ ] 2.4 Change `total` to `passes + fails + SKIPPED`.
- [ ] 2.5 Add the ceiling as a **counted** assertion (`SKIPPED <= 1`) with its derivation in a
      comment.
- [ ] 2.6 Raise the floor 44 → 45 and add a `RAISED 44 -> 45` itemisation stanza in the file's
      existing style.
- [ ] 2.7 Extend the summary line with `Skipped: N` and the resolved suite path.
- [ ] 2.8 Amend the B5 doctrine comment block in the same commit; cite the ADR.

## Phase 3 — Prove the mutation matrix

Each row is a temporary local edit, observed, then reverted. Record observed output for the PR body.

- [ ] 3.1 Row 1 — block neutered before chmod, environment healthy ⇒ FAIL.
- [ ] 3.2 Row 2 — setup forced to fail via a **bogus package name** (not `--network none`) ⇒ SKIP,
      `Skipped: 1`, exit 0, floor met.
- [ ] 3.3 Row 3 — execution-marker line deleted, environment healthy ⇒ FAIL.
- [ ] 3.4 Row 4 — pre-bind :8099 so the driver exits at `FIXTURE:` ⇒ FAIL.
- [ ] 3.5 Row 5 — truncate `$TMP/out/stdout` before the verdict ⇒ FAIL.
- [ ] 3.6 Row 6 — delete the ceiling assertion ⇒ suite non-zero (floor).
- [ ] 3.7 Row 7 — add a second `arm_skip` call site without raising the ceiling ⇒ non-zero.
- [ ] 3.8 Row 8 — restore `set -e` so the mutation does not land ⇒ FAIL at the existing pre-branch.
- [ ] 3.9 Row 9 — marker present in source, stripped from the mounted artifact ⇒ structural hard-exit.
- [ ] 3.10 Row 10 — control, nothing mutated ⇒ `45 passed, 0 failed, Skipped: 0`, path printed.

## Phase 4 — ADR

- [ ] 4.1 Re-derive the next free ADR ordinal against **fetched** `origin/*` refs (the local corpus
      lags origin — ADR-183 exists on origin but not in this worktree, so a local `ls` is not the
      authority).
- [ ] 4.2 Write the ADR with `amends: ADR-181`, `related_adrs: [ADR-177, ADR-180, ADR-166]`.
- [ ] 4.3 Argue the reversal of ADR-181 property 4 ("a decline is UNREACHABLE under CI") on the
      deterministic-vs-transient distinction.
- [ ] 4.4 Reconcile with AP-021/ADR-166 and record the `git-data-rung2-rehearsal.test.sh`
      per-arm-FAIL counter-precedent.
- [ ] 4.5 If the ordinal moved, sweep the plan, this file, the ADR body and every reference in one
      edit.

## Phase 5 — Verification and close

- [ ] 5.1 `bash -n` on the edited file — unconditional, must be clean.
- [ ] 5.2 Full suite run on a healthy machine; record the summary as an environment observation.
- [ ] 5.3 Verify every AC in the plan's `## Acceptance Criteria` → Pre-merge.
- [ ] 5.4 File a tracking issue for each `## Deferred Scope` row with its re-evaluation criterion
      (pre-bake, retry, `run_case`/`_s1_run` extension, T17 capture, P4 persistence window).
- [ ] 5.5 Confirm `decision-challenges.md` (UC-1) is carried into the PR body by `ship`.
- [ ] 5.6 PR body carries `Closes #7291`.
