# Tasks — fix #6775: auto-close hook PR-body scan + follow-through label gate

Plan: [`2026-07-20-fix-autoclose-hook-pr-body-scan-plan.md`](../../plans/2026-07-20-fix-autoclose-hook-pr-body-scan-plan.md)
Lane: `cross-domain` (no `spec.md` — TR2 fail-closed default)
Branch: `feat-one-shot-6775-autoclose-hook-pr-body-scan`

**Three defects.** D1: the `--repo` slug leaves `.git` on SSH remotes, so the PR-body
fetch has been silently dead since 2026-07-03. D2: no `follow-through` label gate on the
plain `gh pr merge` path. D3: the test's `gh` stub ignores `argv`, so the body-path test
is green on a dead path.

**Read §Review Corrections in the plan before starting.** Four blocking findings from
plan review are encoded there — three of them were the plan reproducing the defect class
it was written to eliminate.

---

## Phase 0 — RED (own commit)

Land this phase as a **separate commit** so AC1's evidence is re-derivable via
`git checkout <red-sha> -- .claude/hooks/`. Never `git stash`
(`hr-never-git-stash-in-worktrees`). Never paste RED output into the PR body — the
fixtures contain prose closes that would trip the repaired guard against this very PR.

- [ ] **0.1** Rewrite the `gh` stub in `.claude/hooks/pre-merge-auto-close-scan.test.sh`
      to inspect `argv`: dispatch on subcommand (`pr view` → body, `issue view` → label
      JSON, else empty); add a per-case failure switch that exits non-zero with empty
      stdout; add a comment stating hook stubs must validate `argv`.
- [ ] **0.2** Run the suite unmodified. Assert the **body case FAILS** and the
      **commit-body case still PASSES in the same run**. Both halves required — a
      body-only failure is also what a broken stub produces. Capture per-case output.
- [ ] **0.3** Add the reachability case: standalone `Closes #N` on a follow-through
      issue in the PR body → expect `deny`. (Pins C1.)
- [ ] **0.4** Add label-gate cases: commit-message standalone close on a follow-through
      issue → `deny`; `Ref #N` alone → `allow`; standalone close on a non-follow-through
      issue → `allow`.
- [ ] **0.5** Add extraction cases: `Refs #A, closes #B` (`#A` follow-through, `#B` not)
      → `allow`; a number that is a **prefix of** a follow-through number (`#661` vs
      `6617`) → `allow`; `GH-N` form handled.
- [ ] **0.6** Add degraded cases: stubbed `gh` fails → `allow` + one notice; scanner
      unresolvable → `allow` + one notice; **no PR for branch → `allow`, NO notice**.
- [ ] **0.7** Create `.claude/hooks/stub-argv-fidelity.test.sh`, modelled on
      `hookeventname-coverage.test.sh`. Sweep every `.claude/hooks/*.test.sh` that puts a
      `gh` stub on `PATH`; assert the stub body references `$1`/`$@`. **Parse the stub
      heredoc body, not the whole test file** — a naive grep false-positives on `$1` in
      surrounding helpers. Expect pre-existing sibling gaps; triage inline per
      `wg-defer-only-after-inline-triage`.
- [ ] **0.8** Commit Phase 0 alone. Record the SHA — AC1 depends on it.

## Phase 1 — GREEN: make the PR-body fetch execute (D1)

- [ ] **1.1** Replace the `--repo "$(… sed …)"` construction at `:69-70` with
      `(cd "$WORK_DIR" && gh pr view "$BRANCH" --json body --jq '.body') >>"$SCAN_FILE"`.
      No slug, no `sed`, no extractor — `gh` resolves the remote itself (verified from a
      worktree, resolves by branch name).
- [ ] **1.2** Resolve `SCANNER` from `git -C "$WORK_DIR" rev-parse --show-toplevel`
      instead of the payload cwd, so a merge issued from a subdirectory still finds it.
- [ ] **1.3** Confirm 0.2's body case flips to `PASS` and the commit case stays `PASS`.
      **Assert per-case `PASS:` lines, not suite exit code** — 0.3–0.6 are still red by
      design through Phases 1–2.

## Phase 2 — GREEN: make the fail-open loud

- [ ] **2.1** Capture exit status per arm instead of discarding it. On failure keep
      `allow` and print **one terse stderr line** naming the skipped arm. Not a banner.
- [ ] **2.2** Distinguish gh's no-PR-found exit from auth/network failure; the former is
      silent (a normal pre-PR state must not cry wolf).
- [ ] **2.3** Give both `gh` arms a **single shared deadline**, not independent
      `timeout 8`s. Measured: `gh` fails fast on DNS failure (0.10s) but hangs past 20s on
      blackholed packets, so the additive worst case is reachable.
- [ ] **2.4** Confirm 0.6 goes green.

## Phase 3 — GREEN: follow-through label gate (D2)

- [ ] **3.1** **Restructure the early exit.** Hoist the raw scanner output once; derive
      `EMBEDDED` (prose arm) and `REFERENCED` (label arm) from it; exit 0 only when
      **both** are empty. The gate is evaluated **before** the existing
      `[[ -n "$EMBEDDED" ]] || exit 0`, never appended after it. *Appending it after ships
      a gate that passes every test and is dark in production.*
- [ ] **3.2** Extraction contract: strip the `^[0-9]+:` line-number prefix **first**;
      match keyword-paired references globally per line
      (`(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(#|GH-)([0-9]+)`); de-duplicate;
      compare by **exact token** (`grep -Fxq`), never substring.
- [ ] **3.3** Cap fan-out at 3 distinct issues; beyond that skip the gate with the
      degraded notice.
- [ ] **3.4** Per issue, run a deadline-bounded `gh issue view <N> --json labels` from
      inside `$WORK_DIR` and test for `follow-through`. **No `gh issue list`** — it
      silently truncates at 30 (44 exist).
- [ ] **3.5** On a hit, deny — naming the issue(s), the surface (commit vs PR body), and
      *why* it is protected (carries `follow-through`; closing it makes the sweeper skip
      it so the soak never runs). Do not reuse "reword the sentence." Offer
      `SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1`. Word it so an operator tripping both this and
      `ship-soak-followthrough-gate.sh` on one `--auto` merge can tell them apart.
- [ ] **3.6** Add the scoped hatch `SOLEUR_ACK_FOLLOWTHROUGH_CLOSE`, checked **at the
      gate** (not at `:60` beside the broad hatch) so it does not disarm the prose arm.
- [ ] **3.7** Preserve the prose-embedded deny for all issues, labelled or not.
- [ ] **3.8** Confirm 0.3, 0.4, 0.5 go green.

## Phase 4 — Documentation + full suite

- [ ] **4.1** Hook header: document the four-surface division of labour, both escape
      hatches and what each disarms, and the known bypasses (merge from `main`, web UI,
      admin merge, CI-queued auto-merge, OpenHands). State the guard is best-effort for
      the agent-driven path, not a complete boundary. No dated history.
- [ ] **4.2** `.claude/hooks/README.md`: add the escape-hatch inventory —
      `SOLEUR_ACK_AUTOCLOSE`, `SOLEUR_ACK_FOLLOWTHROUGH_CLOSE`,
      `SOLEUR_SKIP_OPERATOR_STEP_GATE`, `SOLEUR_SKIP_RUNBOOK_SSH_GATE` are undocumented.
- [ ] **4.3** File the four deferred tracking issues (see plan §Deferred), each with
      milestone `Post-MVP / Later`.
- [ ] **4.4** Run `bash scripts/test-all.sh` — orphan suites are exercised only there.
- [ ] **4.5** Verify AC1–AC13 against the plan's §Acceptance Criteria.

---

## Verification quick-reference

```bash
# AC8  — no paginated label call
grep -c 'gh issue list' .claude/hooks/pre-merge-auto-close-scan.sh          # -> 0
# AC10 — no slug parsing / --repo
grep -cE 'remote get-url origin|--repo' .claude/hooks/pre-merge-auto-close-scan.sh  # -> 0
# AC12 — meta-test
bash .claude/hooks/stub-argv-fidelity.test.sh
# AC13 — full suite
bash scripts/test-all.sh
```

**Runner:** plain `.test.sh` invoked from `scripts/test-all.sh`. `bats` is NOT installed —
do not introduce it.
