---
title: "Tasks — fix(kb): regenerating merge driver for the generated KB index"
branch: feat-one-shot-7935-kb-index-merge-driver
issue: 7935
plan: knowledge-base/project/plans/2026-09-08-fix-kb-index-merge-driver-plan.md
lane: cross-domain
---

# Tasks

Derived from `knowledge-base/project/plans/2026-09-08-fix-kb-index-merge-driver-plan.md` after the
review panel. Phase order is load-bearing: the shared renderer (2.1) must exist before the driver
(2.2) that round-trips through it, and the suite (1.x) must be red before either.

## Phase 0 — Preconditions

- [x] 0.1 Re-run the ADR ordinal probe across **every** `origin/*` ref (not just `origin/main`) and
      record the next free ordinal. ADR-210 is provisional; highest claimed at plan time was ADR-209.
- [x] 0.2 Run `bash scripts/generate-kb-index.sh` and confirm the delta is small (the plan measured a
      two-line delta plus this feature's own rows). A large delta means unrelated drift accumulated and
      must be handled before the regenerated index enters this diff.
- [x] 0.3 Confirm `git --version` on the working machine and record it beside the plan's measured
      facts (they were taken on git 2.53.0).
- [x] 0.4 Confirm the hook layer is armed: the bare repo's hooks directory holds a real `pre-commit`,
      not only `*.sample` files. Record the result — the plan's M19 depends on it.

## Phase 1 — RED: the functional merge suite

Four suites ship in total, split on the seam `scripts/test-all.sh` documents. Phase 1 writes only the
first; the registration suite is Phase 3 and both mutation batteries are Phase 2 (their anchors do not
exist until the code they mutate does).

- `plugins/soleur/test/kb-index-merge-driver.test.sh` — functional (this phase)
- `plugins/soleur/test/kb-index-merge-driver-registration.test.sh` — Phase 3
- `plugins/soleur/test/kb-index-check-guard.mutation.sh` — Guard 1 battery, Phase 2
- `plugins/soleur/test/merge-kb-index-driver.mutation.sh` — Guard 2 battery, Phase 2

- [x] 1.1 Create `plugins/soleur/test/kb-index-merge-driver.test.sh`. Source
      `plugins/soleur/test/test-helpers.sh` first, for the Guard 3 `GIT_*` tripwire (exit 97).
- [x] 1.1b Pin `KB_DIR=<fixture>` on **every** generator and `--check` invocation in every suite. The
      generator defaults to the real 6,432-file tree, so an omitted pin silently costs ~9.9 s per call
      (~19 calls as designed). AC17 is the single call allowed to run against the real tree.
- [x] 1.2 Fixture builder: `mktemp -d` with a `trap 'rm -rf …' EXIT`, `git init -q -b trunk`
      (**never `main`**), inline `user.email` / `user.name`, and a small synthetic knowledge-base
      corpus. Generate the fixture's index by calling the real generator with `KB_DIR` pointed at the
      fixture — never by hand-writing an index.
- [x] 1.3 Central case (AC1/AC2/AC3/AC4): two branches each add a distinct KB file and regenerate;
      register the driver in the **fixture's own** config; `git merge`; assert both rows present,
      header count equals row count, `git rev-list --parents -1 HEAD | wc -w` returns 3, and the
      merged file is byte-identical to a fresh generator run over the merged corpus.
- [x] 1.4 Unregistered case (AC5): same scenario with `merge.kb-index.driver` unset; assert the result
      differs from a fresh generation and that `--check` exits non-zero on it.
- [x] 1.5 Show the suite failing. Do not proceed until the failure is the expected one.

## Phase 2 — GREEN: renderer, driver, `--check`

- [x] 2.1 Create `scripts/lib/kb-index-render.sh` by extracting the render block from
      `scripts/generate-kb-index.sh` verbatim (the `# Knowledge Base Index` header echoes, the
      `> Total files:` line, the domain-grouping loop, the `- [$title]($rel)` row). Edit
      `scripts/generate-kb-index.sh` to source it. Assert the generator retains no second copy of the
      `Total files:` literal (AC13).
- [x] 2.2 Create `scripts/merge-kb-index.sh`: validate `%P` equals `knowledge-base/INDEX.md` before
      reading anything; parse `%O`/`%A`/`%B` into `rel\ttitle`; **round-trip validate all three**
      (parse, re-render through the shared renderer, byte-compare — exit 1 on any mismatch); three-way
      set merge keyed on `rel`; render; write `%A`; exit 0.
- [x] 2.2b Safe-parsing constraints, all mandatory: never `eval`; read line by line
      (`while IFS= read -r`) rather than a whole-file regex; strip a trailing `\r` from each line;
      reject any physical line over 8 KB; quote every expansion. Titles already reach committed rows
      carrying `$(…)`, backticks and quotes — the generator escapes only `[` and `]`.
- [x] 2.2c Reject any row whose `rel` is absolute, contains a `..` segment, or resolves outside
      `knowledge-base/`. This is checked **separately** from round-trip, because such a row
      round-trips byte-identically.
- [x] 2.2d Reject a same-`rel` two-sided add (absent from the ancestor, added on both sides) whose
      titles differ — exit 1 rather than picking one.
- [x] 2.3 Sentinel (AC6/P6) via `trap 'write_sentinel; exit 1' ERR`, installed **before any parsing**,
      writing `<<<<<<< kb-index: merge driver could not resolve — re-run the merge after fixing
      registration` into `%A`. A hand-placed write before each deliberate `exit 1` is not sufficient:
      under `set -euo pipefail` an unhandled failure exits without reaching it, reproducing the exact
      markerless-conflict defect the sentinel exists to prevent.
- [x] 2.6 Write `plugins/soleur/test/kb-index-check-guard.mutation.sh` (Guard 1, `EXPECTED_ROWS=12` (12, not the 14 estimated before the code existed))
      and `plugins/soleur/test/merge-kb-index-driver.mutation.sh` (Guard 2, `EXPECTED_ROWS=13`).
      Harness per `plugins/soleur/test/git-fixture-env.mutation.sh`: pristine copy under `mktemp -d`,
      Python `s.replace(old, new, 1)` guarded by `assert old in s` (never inline `sed`), assert the
      mutation **landed** before scoring, green unmutated control first, `trap` restore on exit.
      `mkdir -p "$WORK/lib"` and copy `scripts/lib/kb-index-render.sh` alongside — a flat copy makes
      every row a spurious RED from a missing-`source` crash. Report row-count shortfalls with a
      direct `printf >&2; exit 1`, never through the `FAIL` counter.
- [x] 2.4 Add `--out DIR` to `scripts/generate-kb-index.sh` — the primitive, mirroring
      `scripts/regenerate-c4-model.sh --out PATH` — writing `INDEX.md`, `kb-tags.txt` and
      `kb-categories.txt` into `DIR` instead of `$KB_DIR`. Then add `--check` as a thin wrapper:
      `--out "$(mktemp -d)"`, diff all three against the committed copies, print the diff, exit
      non-zero on mismatch, and fail rather than pass when the regeneration indexed zero files.
- [x] 2.5 Re-run Phase 1 to green.

## Phase 3 — Registration

- [x] 3.1 Create `scripts/install-kb-merge-driver.sh`: read `git config --get merge.kb-index.driver`;
      write only when absent or different; store a **worktree-relative** command
      (`bash scripts/merge-kb-index.sh %O %A %B %P`) with no absolute path; never touch
      `config.worktree` or `extensions.worktreeConfig`; retry once on a `config.lock` failure, then
      report to stderr and exit 0. Mutate `.git/config` **only through `git config` porcelain**, never
      by editing the file — the same shared config holds `core.hooksPath`, and clobbering that would
      disarm every lefthook gate across all 37 worktrees at once.
- [x] 3.2 Append the registration hook to the existing `SessionStart` array in `.claude/settings.json`
      (AC11).
- [x] 3.3 Add `"prepare": "bash scripts/install-kb-merge-driver.sh"` to the root `package.json`
      (AC11). Note it also fires in CI's `lockfile-sync` job — harmless, since no CI workflow merges.
- [x] 3.4 Create `plugins/soleur/test/kb-index-merge-driver-registration.test.sh` with: idempotency
      (AC7), no absolute path stored and resolution from a subdirectory (AC8),
      `extensions.worktreeConfig` still unset (AC9), exit 0 under a held config lock (AC10), and N
      **parallel** invocations converging on one value (T17) — sequential idempotency does not cover
      the concurrent shape, which is the 2026-08-09 incident's exact form.

## Phase 4 — Wiring, routing correction, ADR

- [x] 4.1 Create the root `.gitattributes`: `knowledge-base/INDEX.md merge=kb-index`,
      `knowledge-base/kb-tags.txt merge=union`, `knowledge-base/kb-categories.txt merge=union`, plus a
      comment naming the driver and the registration script. Verify with `git check-attr merge` on all
      four paths, including the plugin mirror, which must report `unspecified` (AC12).
- [x] 4.2 Edit the existing `generate-kb-index` stanza in `lefthook.yml` only: dual glob
      (`knowledge-base/*.md` plus `knowledge-base/**/*.md`) for the gobwas depth-1 hole, and widen
      `git add` to all three generated files. Observe the fix with `lefthook run pre-commit` and only
      `knowledge-base/INDEX.md` staged (AC18, T15) — do not reason about the glob.
- [x] 4.3 Edit `plugins/soleur/skills/merge-pr/SKILL.md` §3.2b: add the three generated knowledge-base
      paths to the known-members list with the correct remedy — re-run the merge after fixing
      registration; never side-pick; never look for markers on these paths (AC19).
- [x] 4.4 Replace the `--help` line in `scripts/generate-kb-index.sh` that prescribes the hand-run
      post-conflict regeneration; name the driver and the registration script instead (AC20).
- [x] 4.4b Add explicit `.github/CODEOWNERS` rows for `scripts/merge-kb-index.sh`,
      `scripts/lib/kb-index-render.sh` and `scripts/install-kb-merge-driver.sh` (AC26), following the
      file's "load-bearing files get explicit rows" convention. Record in the PR body that this is a
      marker, not an enforced gate — `main` is not branch-protected today.
- [x] 4.5 Write the ADR at the ordinal confirmed in 0.1, with the five decision points and the
      alternatives table from the plan. If the ordinal moved, sweep the plan, this file and AC21 in the
      same edit.
- [x] 4.6 Run `bash scripts/generate-kb-index.sh`, which rewrites all three generated artifacts. Only
      `knowledge-base/INDEX.md` is expected to change; `kb-tags.txt` and `kb-categories.txt` were
      measured byte-identical to a fresh generation, so a diff in either is a signal to investigate,
      not to commit blindly.

## Phase 5 — Verification

- [x] 5.1 All four suites exit 0, each with its assertion floor satisfied.
- [x] 5.2 Both batteries pass every row: `kb-index-check-guard.mutation.sh` scores **12/12**
      (C1-C11 plus one harness self-test, over a nine-property probe, after a green unmutated
      control) and `merge-kb-index-driver.mutation.sh` scores **13/13** (G1-G12 plus one harness
      self-test, over an eleven-property probe, after a green unmutated control). The row labels and
      counts here are the ones the code admits, not the plan-time estimate; `EXPECTED_ROWS` in each
      file is the binding number and is asserted by direct `printf` + `exit 1` rather than through
      the `FAIL` counter. Each file carries a `# MUTATION MATRIX` header recording observed
      verdicts, per `plugins/soleur/test/fixture-relative-assert.test.sh` (AC14).
- [x] 5.3 `bash scripts/lint-orphan-test-suites.sh` exits 0 (AC15).
- [x] 5.4 `bash scripts/generate-kb-index.sh --check` exits 0 against the branch (AC17).
- [ ] 5.5 `bash scripts/test-all.sh scripts` exits 0 (AC16).
- [x] 5.6 `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.
- [ ] 5.7 `python3 scripts/lint-infra-no-human-steps.py --changed` and
      `python3 scripts/lint-guard-contract.py` exit 0.
- [x] 5.8 Scope check (AC23): the diff touches neither `.github/workflows/ci.yml` nor
      `plugins/soleur/skills/ship/SKILL.md`.
- [ ] 5.9 Walk every acceptance criterion in the plan and record the command output.

## Phase 6 — Ship

- [ ] 6.1 PR body carries `Closes #7935` (AC22) and reproduces the plan's
      `## The kb-tags.txt / kb-categories.txt decision` section verbatim — this is the issue's second
      acceptance criterion and it must be visible in the PR, not only in the plan.
- [ ] 6.2 PR body renders the challenge recorded in
      `knowledge-base/project/specs/feat-one-shot-7935-kb-index-merge-driver/decision-challenges.md`.
- [ ] 6.3 Re-verify the ADR ordinal against freshly-fetched `origin/*` refs immediately before merge.
- [ ] 6.4 File no new issues — #7935's net-issue-flow must stay Closing:1 / Filing:0 / Net:-1.
