# Tasks — fix the rung-2 evidence hash, the rehearsal's misattribution, and the closure guard

Plan: `knowledge-base/project/plans/2026-08-12-fix-git-data-evidence-hash-and-ci-guards-plan.md`
Closes: #7485, #7501, #7506 · Ref #6977 · Threshold: `single-user incident`

Commits grouped by issue. **No revert-cleanliness claim** — `main` is squash-merged, so a merged PR
is one commit (see DC-1).

---

## Phase 0 — Preconditions (no product edits)

- [x] 0.1 Re-run the #7485 reproduction on a fresh `origin/main` extract; confirm rc=1 and the
      9-vs-11 text. If it no longer reproduces, stop and re-scope.
- [x] 0.2 Confirm `python3 -c 'import yaml'` succeeds.
- [x] 0.3 Confirm the closure-guard step still declares **no** `shell:` key. If one has appeared, the
      faithful harness becomes `bash --noprofile --norc -eo pipefail` and Guard 3 row 4 flips — the
      premise is directional and the first draft got the direction wrong.
- [x] 0.4 Re-run the assembly grep over the rehearsal file. Expect **four** call sites; the fourth is
      the R4 MUTATION arm's own liveness marker and is **excluded**, not folded in.
- [x] 0.4b Confirm no `shopt -s nullglob` in the gate lib, so the sibling loop must test for a matched
      directory entry (`-e` OR `-L`) before testing readability. A bare `-r || abort` aborts the live
      tree on the unexpanded `*.tf.json` literal.
- [x] 0.4c Unreadability fixtures use dangling symlinks, never `chmod 000` — root bypasses the mode
      check and would disarm A4/A5/A7 silently.
- [x] 0.5 Read `scripts/lint-shell-capture-exit.baseline.txt` (7 entries for the rehearsal file). Plan
      for it to stay unchanged or shrink, never grow.
- [x] 0.6 Record floors: gate suite 58, rehearsal 44, capture-script suite 33.

---

## Phase 1 — RED (tests before implementation)

### 1.1 Gate suite (`tests/scripts/test-git-data-birth-readiness-gate.sh`)

- [x] 1.1.1 Repair `_r2_hash()`: add the sibling `.tf` glob and widen the regex to the
      `file(base64|sha256|sha512|md5)?` family. Verify `R2_SHA` is byte-identical and the suite is
      still 58/58 — measured hash-neutral, because no current fixture has a sibling or a
      `filebase64` binding. Then add the **equivalence arm** (A10) so a third drift is unshippable.
- [x] 1.1.2 Extend the fixture builder so a fixture can be given sibling `.tf` files. Sibling
      basenames must not collide with any payload basename, or the basename-uniqueness check reddens
      the arms for the wrong reason.
- [x] 1.1.3 Add A1 (live tree → 0, 64-hex) and A2 (two-sibling fixture → 0) on a **separate copied
      tree**, calling the function directly, never through `r2check`/`R2_SHA`. Both **must be RED**.
- [x] 1.1.4 Add A3 — three-sibling fixture → 0 (sibling-count independence).
- [x] 1.1.5 Add A4/A5 — a `.tf` and a `.tf.json` sibling, each a dangling symlink → 1 naming the
      file. **A4 must be RED against the first draft's shape** (measured rc=0 there).
- [x] 1.1.6 Add A6 — a readable `.tf.json` sibling → 0, digest differs from the fixture without it.
- [x] 1.1.7 Add A7/A8 — a referenced payload as a dangling symlink, and one deleted outright, each
      → 1 naming it. A8 inherits the job the deleted counting check used to do.
- [x] 1.1.8 Add A9 — a module binding only 2 payloads with siblings present → 1 naming the drifted
      extraction and the payload count.

### 1.2 Capture-script suite (`tests/scripts/test-git-data-rung2-evidence-capture.sh`)

- [x] 1.2.1 Add one **executing** arm for the derivation-fault path: break a payload in the existing
      minimal fixture tree, assert rc=2 and the corrected text. Replaces the first draft's grep,
      which would be satisfied whether or not the branch is reachable.

### 1.3 Closure-guard suite (`scripts/follow-through-closure-guard.test.sh`, new)

- [x] 1.3.1 Scaffold: PyYAML hard-exit 2; an EXIT trap for its `mktemp` allocations (rule (c) gates
      added lines); a column-0 `FAIL`-shaped failure marker naming which arm failed; floor 9.
- [x] 1.3.2 Extract the step body by name with a one-step cardinality check (C6); assert no `shell:`
      key (C7) and no `${{ }}` (C8).
- [x] 1.3.3 `gh` stub on `PATH` recording argv to a log file.
- [x] 1.3.4 C1–C3 — incomplete comment under **`bash -e`** → rc=0, exactly one reopen, checklist line
      rendered. Two fixtures exercise **both** conditional arms, with URLs derived from the
      workflow's own `required_urls` array so drift cannot collapse them onto one arm. **RED.**
- [x] 1.3.5 C4 — complete comment → rc=0, zero reopens.
- [x] 1.3.6 C5/C6 — a bot reopen body newest, once above a **complete** human comment (→ zero
      reopens, discriminating on count) and once above an **incomplete** one (→ one reopen whose
      body lists the missing URLs, discriminating on content). The naive "bot body → zero reopens"
      arm is WRONG: measured, the unfixed guard reopens once there, because the bot body satisfies
      field 1 but not fields 2 or 3.
- [x] 1.3.6b C7/C8/C9 — a human comment carrying the guard's own heading is NOT excluded (identity
      filter, not content); a 31-comment fixture selects the newest (pagination); no qualifying
      comment reopens rather than falling back to the issue body.
- [x] 1.3.7 C9/C10 — the standing sweep with `[[:space:]]` (not `\s`), a non-zero scanned-file
      assertion, its three documented bounds, and a planted-violation fixture proving it fires.

### 1.4 Rehearsal suite (`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`)

- [ ] 1.4.1 Container-side: rc-check `apt-get update` and `install`, plus `command -v python3` /
      `command -v curl`; emit five new `FIXTURE-FAIL: <cause>` markers and **rename** the existing
      `FIXTURE:` bind marker to match.
- [ ] 1.4.2 Bounded apt: `-o Acquire::Retries=3` on update, backoff loop around install. R4 driver only.
- [ ] 1.4.3 Round-trip sentinel: context-managed write in the capture server; after the bind poll,
      self-POST and poll until the sentinel is observed, then `touch /out/sentinel.ok` — a
      **durable artifact**, because the driver truncates `capture.log` three times and the host
      would never see a sentinel written there.
- [ ] 1.4.4 Host-side: capture the `docker run` rc; emit the container stdout tail on its **own
      column-0 lines** anchored on the `FIXTURE-FAIL:` line — never interpolated into a detail string.
- [ ] 1.4.5 One **run-level** liveness gate (`docker rc == 0` and sentinel observed) above all three
      emitter-claiming arms. No per-arm preconditions; **no** non-emptiness conjunct (an empty
      capture after a proven round trip is a genuine emitter finding). The gate emits its own
      `pass` on the healthy path and skips past the arms on failure, so bypassing it is a deletion
      the count can see. Floor 44 → 45.
- [ ] 1.4.5b Add a named fault-injection hook so Guard 2 rows 3-7 are executable without hand edits.
- [ ] 1.4.6 Forensics: modify the **existing** EXIT trap in place — never add a second — to retain
      the tree and print its path on **any** non-zero exit, including the hard `exit 1` setup paths
      where `fails == 0`. Add the `GIT_DATA_REHEARSAL_KEEP_TMP` opt-in and an age-reaper.
- [ ] 1.4.7 B1–B6 fault-injection scenarios. Failures are **injected**, never awaited.

---

## Phase 2 — GREEN

- [x] 2.1 `tests/scripts/lib/git-data-birth-readiness-gate.sh`:
  - [x] 2.1.1 Payload loop aborts on the first unresolvable reference, naming it; retain the
        `-n "$_f"` guard (a bare `-r` test on an empty `_f` is true for the directory); increment
        `_n_payloads` on each success.
  - [x] 2.1.2 Sibling glob: `[[ -e || -L ]] || continue` (skip the unexpanded literal) then
        `[[ -r ]] || abort` (catch present-but-unreadable AND dangling symlinks), extended to
        `*.tf.json`, which Terraform loads and the current glob misses. **No sibling floor.**
  - [x] 2.1.3 Floor on `_n_payloads` (`-lt 9`); message names the count and where the literal must
        move when the payload set grows.
  - [x] 2.1.4 Delete the referenced-vs-resolved block, `_n_resolved` and both literals.
  - [x] 2.1.5 Update the extraction comment that justified the family regex by reference to the
        now-deleted check. Leave the basename-uniqueness check intact — it is the sole detector of a
        module referencing its own sibling.
- [x] 2.2 `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — re-word the `TRANSIENT:`
      label on the hash-derivation arm only. **`exit 2` unchanged.**
- [x] 2.3 `.github/workflows/follow-through-closure-guard.yml` — `--` on both `printf` calls;
      exclude bot-authored comments from the closing-comment selector.
- [x] 2.4 `scripts/marketplace-drift-check.test.sh` — correct the default-shell comment (it asserts
      the wrong side of a live repo contradiction, and it is what misled this plan).
- [x] 2.5 `scripts/test-all.sh` — `run_suite` line for the new suite in the `want_scripts` block.
- [ ] 2.6 Floors: gate 58 → 68 (exact equality), capture-script 33 → 34, rehearsal 44 → 45, new
      closure-guard suite exactly 13.
- [x] 2.7 Amend the gate suite header: record why one live-tree arm is not the countdown timer the
      header forbids, and that #6982 has closed (the live gate now reports RELEASED).

---

## Phase 3 — Mutation verification and record

- [ ] 3.1 Execute all 11 rows of Guard 1 and record observed colours.
- [ ] 3.2 Execute all 7 rows of Guard 2 (via the fault-injection hook).
- [ ] 3.3 Execute all 12 rows of Guard 3, labelling its last three as controls.
- [ ] 3.4 Execute all 3 rows of Guard 4.
- [ ] 3.5 Any row that does not redden is a defect in the test, not a note — fix and re-run.
- [ ] 3.6 `python3 scripts/lint-guard-contract.py` and
      `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 3.7 `scripts/lint-shell-capture-exit` baseline unchanged or smaller.
- [ ] 3.8 `bash scripts/lint-orphan-test-suites.sh` reports the new suite registered.
- [ ] 3.9 `bash scripts/test-all.sh` exits 0 on a machine with docker.

---

## Phase 4 — Ship

- [ ] 4.1 PR body: `Closes #7485`, `Closes #7501`, `Closes #7506` on their own lines; `Ref #6977`.
- [ ] 4.2 PR body records the mutation-matrix results, the misattribution-not-vacuity framing, and
      the honest scope limit that five other container sites keep their current behaviour.
- [ ] 4.3 Render `decision-challenges.md` (DC-1 split, DC-2 fixture failures stay FAIL) into the PR
      body and file the `action-required` issue.
- [ ] 4.4 File the two deferred follow-ups with their measurements: the container image pre-bake
      (trigger: any R3/R4 arm reports a fixture-starvation failure in CI), and the rehearsal
      workflow's 20 × 30 s retry on a non-clearable `rc=2` plus its hardcoded step-summary text;
      symlink and `realpath` containment hardening on the hash inputs; and the two closure-guard
      field weaknesses (field 2 accepts any green run; the `if:` filter admits any matching title).
- [ ] 4.5 Post-merge: re-run the closure-guard suite against the merged `main` file
      (`wg-after-merging-a-pr-that-adds-or-modifies`; the workflow has no `workflow_dispatch`).
