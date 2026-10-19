# Learning: a per-area drawdown cannot satisfy a live-census gate, and re-indenting breaks text-anchored mutation rows

## Problem

Slice 3 of #10331 (#10433) drew two shrink-only lint baselines (44 ruff entries, 20 eslint entries) down to empty across 33 files. The plan asked for four per-area commits, each staging its own shrunk baseline. Three things went differently from the plan:

1. The lefthook `ruff-ratchet` / `eslint-test-dirs-ratchet` hooks, like `lint-ratchet.py --check`, require the baseline to EQUAL the live census of the working tree. By the time the first commit was ready every area was already fixed in the tree, so the live census was empty and any non-empty baseline (or any partial shrink) fails. A per-area baseline shrink is only possible if the areas are fixed one at a time with the other areas still unfixed, which a single working session does not do.
2. Wrapping `open(path, "a")` loops in `ci-pr-affected-replay.py` in `with` blocks re-indented them. `plugins/soleur/test/ci-pr-affected-replay.test.sh` selects its mutation hunks by exact multi-line text, so one mutant (`cleared-read-error-as-cleared`) reported `edit-failed` and the suite went 211/2. The other 73 anchors were outside the re-indented region.
3. The infra mutation harness `doppler-download-error-channel.mutation.py` was RED on its own unmutated control on `origin/main` as well: its sandbox copies four files, but the suite it drives now also reads the boot-trail reader and every `*.service` unit. A control that is red voids every row below it.

## Solution

- One commit carries all four areas plus the regenerated empty baselines. The per-area split is a review aid in a squash-merge repo, so nothing is lost; the diff stays readable with `git diff -w` for the re-indent hunks.
- The mutant anchor was re-indented by the same four spaces. The harness sandbox now copies the boot-trail reader and the `*.service` glob, and the control is green again.

## Key Insight

When a gate compares a committed artifact to a census of the CURRENT working tree, the commit unit is the working tree, not the code area. Plan a drawdown as one commit (or fix and commit areas in order with the unfixed areas stashed in a branch), never as N commits that each stage a different baseline.

When a refactor only changes whitespace structure (re-indent under `with`), grep the repo's tests for the changed region as TEXT, not only as a symbol: mutation rows and source-slicing guards anchor on exact bytes, and the suite that anchors on them is not the suite that "covers" the file.

## Session Errors

1. **Ratchet `--check` run from the bare repo root** printed `git diff failed: fatal: this operation must be run in a work tree`, and the brief named a `.lint-ratchet/` directory that does not exist (baselines live in `scripts/lint-ratchet-*.baseline.txt`). — Recovery: ran from the worktree and located the files with `git ls-files`. — **Prevention:** run ratchet commands only after the worktree exists; locate baselines with `git ls-files | grep baseline` before trusting a path in a brief.
2. **Plan prescribed per-area commits with per-area baselines** (see Problem 1). — Recovery: single commit. — **Prevention:** plan Sharp Edges bullet added (see route below).
3. **Re-indent broke a text-anchored mutation row** (Problem 2). — Recovery: updated the anchor. — **Prevention:** grep the tests for the re-indented region as text before committing a re-indent.
4. **Mutation harness control red on main** (Problem 3). — Recovery: extended the sandbox file list. — **Prevention:** a harness that copies a hand-listed subset of files must be run (control only) whenever the suite it drives changes; a red control is the signal.
5. **Own `/proc` kill loop matched its own shell** (`case "$a" in *test-all.sh*`), exit 144. — Recovery: re-ran anchored on argv slots (`$2=="bash" && $3=="scripts/test-all.sh"`). — **Prevention:** the documented self-match class; never match a runner by substring over cmdline when the matching command itself contains the pattern.
6. **Proxy suite flaked once** (row 47, "a request reusing a pending id") while other suites ran in parallel; 499/0 on the unloaded rerun and again after the review fixes. — **Prevention:** none beyond rerunning a timing suite in isolation before reading a single red as a regression.
7. **Two review seats ran `git checkout --detach`** despite being briefed report-only; the tree was restored and no content changed. — **Prevention:** already in review's Sharp Edges (check `git branch --show-current` after the panel).
8. **Affected gate sat 25+ minutes queued at position 4** behind sibling runs; killed it rather than let it acquire mid-edit and re-run later. — **Prevention:** none; the queue is documented behaviour.
9. **Plan's `decision-challenges.md` row failed `technical-ruling-gate.sh`** (a ruling not starting `Ruled by CTO agent, <date>:`). — Recovery: rewrote the row. — **Prevention:** run the gate right after the planner returns (the pipeline already does).
10. **`git add -A -- . ':!.scratch'` aborted** because `.scratch` is gitignored, staging nothing. — Recovery: `git add -u`. — **Prevention:** check the commit's file count after `git add`.

## Tags
category: workflow-issues
module: lint-ratchet, code-quality
