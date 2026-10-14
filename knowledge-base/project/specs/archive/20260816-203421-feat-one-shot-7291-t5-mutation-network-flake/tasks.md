# Tasks — fix: T5 mutation arm reports "vacuous" when the mutant never executed

Plan: `knowledge-base/project/plans/2026-08-12-fix-t5-mutation-arm-network-flake-plan.md`
Issue: #7291 · Branch: `feat-one-shot-7291-t5-mutation-network-flake` · Lane: `cross-domain`

Single file under edit: `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`.
Read the plan's `## Conventions and constraints` before the first edit — four bash traps in it are
load-bearing (`local` outside a function, the `_skip()`/`arm_skip()` name collision, the `#7005`
SIGPIPE prohibition, and the `$(grep -c … || true)` idiom).

## Phase 0 — Preconditions

- [x] 0.1 Confirm `docker info`, `terraform`, `python3` available; the suite `_skip()`s without them.
- [x] 0.2 Baseline the suite: run it once, record the summary line and the current assertion total.
- [x] 0.3 Re-read the T5 mutation arm and the `drive.sh` heredoc end-to-end before editing
      (`hr-always-read-a-file-before-editing-it`).

## Phase 1 — Capture the deciding datum (probe-first; must precede Phase 2)

- [x] 1.1 Add one execution-marker `echo` to the `drive.sh` heredoc, immediately above
      `. /work/doppler-dl.sh` and **below** the capture-server guard.
- [x] 1.2 Add a **structural** (hard-exit, uncounted) guard asserting the marker is present in the
      **mounted** artifact `$TMP/drive.noerrexit.sh`, after the arm's `sed 's/^set -e$/true/'` —
      not in the source heredoc. Pins the transform's application, not just its correctness.
- [x] 1.3 Replace the trailing `|| true` on the arm's `docker run` with a plain `rc=$?` assignment
      on the next line. **Not `local`** — the arm is top-level; `local` errors there, leaves the
      variable unset, and `set -u` then kills the suite mid-run.
- [x] 1.4 Emit the captured rc and the tail of `$TMP/out/stdout` in **every** verdict branch. Name
      the measured rc classes (125 pull, 100 apt, 2 capture-server) as *classification offered*,
      never as an asserted cause — AP-021/ADR-166.
- [x] 1.5 Capture whether the T5 **primary** arm executed into a variable, before the mutation arm's
      `rm -rf "$TMP/out"` destroys the evidence, and include it in the skip reason as evidence only.

## Phase 2 — The counted verdict, and an honest floor

- [x] 2.1 Add the `SKIPPED_ASSERTIONS` counter (renamed at review — see plan AC7) and `arm_skip()`, following
      `git-lock-chardevice-sweep.test.sh`'s existing idiom (uppercase counter, `Skipped: N`).
      Do **not** rename `_skip()`.
- [x] 2.2 Add the capture-integrity precondition ahead of the verdict branch: missing or empty
      `$TMP/out/stdout` with rc 0 ⇒ hard `fail`, never skip.
- [x] 2.3 Rewrite the verdict as an ordered branch — `CHMOD_RAN` → `FIXTURE:` → marker → else fail —
      with the ordering rationale commented.
- [x] 2.4 Change `total` to `passes + fails + SKIPPED`.
- [x] 2.5 Add the ceiling as a **counted** assertion (`SKIPPED <= 1`; **superseded 2026-08-17 —**
      **the #7565 rebase gave the arm a second counted assertion, so the declared cost and the**
      **ceiling are both 2**) with its derivation in a
      comment.
- [x] 2.6 Raise the floor by +1 (46 → 47 after the #7501 rebase; **superseded 2026-08-17 — the**
      **base was re-read from origin/main at ship and is 48, so the shipped raise is 48 → 49**)
      and add a `RAISED` stanza in the file's
      existing style.
- [x] 2.7 Extend the summary line with `Skipped: N`. (The resolved-suite-path half was CUT at review — its premise was false; see plan AC11.)
- [x] 2.8 Amend the B5 doctrine comment block in the same commit; cite the ADR.

## Phase 3 — Prove the mutation matrix

Each row is a temporary local edit, observed, then reverted. Record observed output for the PR body.

- [x] 3.1 Row 1 — block neutered before chmod, environment healthy ⇒ FAIL.
- [x] 3.2 Row 2 — setup forced to fail via a **bogus package name** (not `--network none`) ⇒ SKIP,
      `Skipped: 1`, exit 0, floor met.
- [x] 3.3 Row 3 — execution-marker line deleted, environment healthy ⇒ FAIL.
- [x] 3.4 Row 4 — pre-bind :8099 so the driver exits at `FIXTURE:` ⇒ FAIL.
- [x] 3.5 Row 5 — truncate `$TMP/out/stdout` before the verdict ⇒ FAIL.
- [x] 3.6 Row 6 — delete the ceiling assertion ⇒ suite non-zero (floor).
- [x] 3.7 Row 7 — add a second `arm_skip` call site without raising the ceiling ⇒ non-zero.
- [x] 3.8 Row 8 — restore `set -e` so the mutation does not land ⇒ FAIL at the existing pre-branch.
- [x] 3.9 Row 9 — marker present in source, stripped from the mounted artifact ⇒ structural hard-exit.
- [x] 3.10 Row 10 — control, nothing mutated ⇒ `47 passed, 0 failed, Skipped: 0`, exit 0 (re-running post-rebase).

### Addendum — 2026-08-17 (#7565 rebase, re-measured on `4ba943393`)

Every figure above describes bytes that no longer exist. #7565 merged into this same arm, giving it
a second counted assertion, so the skip cost became 2, the ceiling 2 and the floor 49. The harness
itself was rebuilt: the previous one lived in a session-scoped scratchpad and did not survive, the
perishability recorded in `2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code.md`.
All ten anchors were dry-verified against the post-rebase bytes before any row was trusted.

| Row | rc | Observed | Property |
|---|---|---|---|
| 1 | 1 | `48 passed, 1 failed, Skipped: 0 (49)` | genuine vacuity reaches the `ran` route, not SKIP |
| 2 | 0 | `47 passed, 0 failed, Skipped: 2 (49)` + NOTE | transient decline ⇒ loud counted skip, floor met |
| 3 | 1 | structural hard-exit | marker absent from the mounted driver |
| 4 | 1 | `41 passed, 8 failed, Skipped: 0 (49)` | fixture defect not absorbed into the environment bucket |
| 5 | 1 | `47 passed, 2 failed, Skipped: 0 (49)` | missing measurement is a harness bug, not a skip |
| 6 | 1 | `ran only 48 assertions (<49)` | the ceiling is COUNTED — its own deletion reddens |
| 7 | 1 | `skip ceiling exceeded: 4 … ceiling is 2` | the ceiling counts MEMBERS, not just the first |
| 8 | 1 | 2 FAIL lines, total 48 | mutation-did-not-land pre-branch, doubly red |
| 9 | 1 | structural hard-exit | same message as row 3 |
| 10 | 0 | `49 passed, 0 failed, Skipped: 0 (49)` | control |

**Two rows were mis-designed and were re-run, not reported as passes.** Row 1 v1 removed the
CHMOD_RAN instrumentation, which trips #7565's instrumentation guard and hard-exits *before* the
verdict — red for a reason unrelated to the vacuity routing it is named for. Row 7 v1 added a
synthetic `arm_skip` of cost 2 against a ceiling of 2 without forcing the T5 skip, so it measured
`rc 0, Skipped: 2 (51)` and **survived**; the archived matrix says "force BOTH", and composing
row 2 reaches 4 > 2. Both were fixture defects, so the fixtures were fixed, not the guards.

**Rows 3 and 9 are ONE axis, not two** — both terminate at the same structural marker guard with
an identical message. Counting them separately overstates the battery.

**Axes this battery does NOT edit,** stated rather than implied: fixture *direction* on the premise
assertion (no row makes the premise fail while the result passes), population growth beyond one
synthetic ceiling member, and the `pass`/`fail` dispatch helpers themselves.

Row 8 falsified a claim this PR had written one commit earlier — see `4ba943393`.

## Phase 4 — ADR

- [x] 4.1 Re-derive the next free ADR ordinal against **fetched** `origin/*` refs (the local corpus
      lags origin — ADR-183 exists on origin but not in this worktree, so a local `ls` is not the
      authority).
- [x] 4.2 Write the ADR with `amends: ADR-181`, `related_adrs: [ADR-177, ADR-180, ADR-166]`.
- [x] 4.3 **AMENDED at review:** argue a SECOND CARVE-OUT on the axis ADR-181 already opened (its
      own Scope exempts the infra runner), and on CONTRACTUAL OWNERSHIP rather than the
      deterministic-vs-transient distinction.
- [x] 4.4 Reconcile with AP-021/ADR-166 and record the `git-data-rung2-rehearsal.test.sh`
      per-arm-FAIL counter-precedent.
- [x] 4.5 If the ordinal moved, sweep the plan, this file, the ADR body and every reference in one
      edit.

## Phase 5 — Verification and close

- [x] 5.1 `bash -n` on the edited file — unconditional, must be clean.
- [x] 5.2 Full suite run on a healthy machine, RE-RUN against final post-rebase bytes:
      `47 passed, 0 failed, Skipped: 0 (47 assertions)`, rc=0, 2347s.
      Skip path re-verified too: `46 passed, 0 failed, Skipped: 1 (47 assertions)`, rc=0, 638s,
      with the degraded-run NOTE emitted. Two earlier clean controls (45/0 and an interrupted
      run) described trees invalidated by #7540 and #7501/#7507 landing mid-flight and are NOT
      the evidence of record.

      > **Superseded 2026-08-17 (#7565 rebase):** the figures above are now stale for the same
      > reason they superseded their own predecessors — a sibling landed in this arm. Re-measured
      > on `4ba943393`: control `49 passed, 0 failed, Skipped: 0 (49 assertions)`, rc=0, ~230s;
      > skip path `47 passed, 0 failed, Skipped: 2 (49 assertions)`, rc=0, with the NOTE emitted.
      > The skip is `2` rather than `1` because #7565 gave the arm a second counted assertion.
      > The ~2347s figure was a cold/contended box; with `ubuntu:24.04` cached a single container
      > step measures 21.6s and the suite ~4 min. This is the fourth restatement of this number
      > on this branch, which is the argument for deltas over literals, not against measuring.
- [x] 5.4 Deferred-scope rows dispositioned. Six proposed rows became **three filings and three
      resolved decisions**, after two CONCUR rounds (both DISSENTed, both correctly):
        - #7565 P1 (separate, discovered defect): the vacuous-PASS path — egress blocked while apt
          works leaves both T5 arms green with the checksum never evaluated.
          **> Superseded 2026-08-17: this is no longer true of the tree, and saying so in the**
          **> present tense is the inherited-claim defect this branch exists to remove. #7565**
          **> merged as the rebase base and added sha256sum's own `<tarball>: FAILED` verdict as a**
          **> counted assertion in BOTH arms. Under egress-blocked-with-apt-healthy the primary**
          **> arm's curl aborts before sha256sum runs, so that verdict line is absent and the**
          **> assertion FAILS; the mutation arm lands on `ran` (its marker prints) where the same**
          **> assertion also fails. Both arms are RED. The row is kept as the record of what was**
          **> filed; the issue is closed.**
          Cross-linked from the
          doctrine block so no reader infers soundness from the three skip conditions.
        - #7572 (bug): the S1 arm's live instance of the #7291 class, measured in this PR's own
          control run. Filed as the DEFECT, not as "S1 lacks arm_skip" — that asymmetry is
          PR-introduced and the review gate forbids filing it as pre-existing.
        - #7574 (deferred-scope-out, criterion 3, CONCUR'd): the persistence bound, wired to
          scripts/followthroughs/t5-skip-persistence-bound-7510.sh with an event-grep trigger that
          fires on a GREEN run.
        - RESOLVED not filed: `-lt` -> `-ne` (rejected in the floor comment), SKIP -> INCONCLUSIVE
          (rejected in ADR-188), bounded retry (wontfix, folded into #7535 as a comment).
        - Pre-bake + /out/setup.log: covered by #7535 in another session; pointed at, not restated.
- [ ] 5.5 Confirm `decision-challenges.md` (UC-1) is carried into the PR body by `ship`.
- [ ] 5.6 PR body carries `Closes #7291`.
