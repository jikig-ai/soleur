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

- [ ] 0.1 Re-run the ADR ordinal probe across **every** `origin/*` ref (not just `origin/main`) and
      record the next free ordinal. ADR-210 is provisional; highest claimed at plan time was ADR-209.
- [ ] 0.2 Run `bash scripts/generate-kb-index.sh` and confirm the delta is small (the plan measured a
      two-line delta plus this feature's own rows). A large delta means unrelated drift accumulated and
      must be handled before the regenerated index enters this diff.
- [ ] 0.3 Confirm `git --version` on the working machine and record it beside the plan's measured
      facts (they were taken on git 2.53.0).
- [ ] 0.4 Confirm the hook layer is armed: the bare repo's hooks directory holds a real `pre-commit`,
      not only `*.sample` files. Record the result — the plan's M19 depends on it.

## Phase 1 — RED: the merge suite

- [ ] 1.1 Create `plugins/soleur/test/kb-index-merge-driver.test.sh`. Source
      `plugins/soleur/test/test-helpers.sh` first, for the Guard 3 `GIT_*` tripwire (exit 97).
- [ ] 1.2 Fixture builder: `mktemp -d` with a `trap 'rm -rf …' EXIT`, `git init -q -b trunk`
      (**never `main`**), inline `user.email` / `user.name`, and a small synthetic knowledge-base
      corpus. Generate the fixture's index by calling the real generator with `KB_DIR` pointed at the
      fixture — never by hand-writing an index.
- [ ] 1.3 Central case (AC1/AC2/AC3/AC4): two branches each add a distinct KB file and regenerate;
      register the driver in the **fixture's own** config; `git merge`; assert both rows present,
      header count equals row count, `git rev-list --parents -1 HEAD | wc -w` returns 3, and the
      merged file is byte-identical to a fresh generator run over the merged corpus.
- [ ] 1.4 Unregistered case (AC5): same scenario with `merge.kb-index.driver` unset; assert the result
      differs from a fresh generation and that `--check` exits non-zero on it.
- [ ] 1.5 Show the suite failing. Do not proceed until the failure is the expected one.

## Phase 2 — GREEN: renderer, driver, `--check`

- [ ] 2.1 Create `scripts/lib/kb-index-render.sh` by extracting the render block from
      `scripts/generate-kb-index.sh` verbatim (the `# Knowledge Base Index` header echoes, the
      `> Total files:` line, the domain-grouping loop, the `- [$title]($rel)` row). Edit
      `scripts/generate-kb-index.sh` to source it. Assert the generator retains no second copy of the
      `Total files:` literal (AC13).
- [ ] 2.2 Create `scripts/merge-kb-index.sh`: parse `%O`/`%A`/`%B` into `rel\ttitle`; **round-trip
      validate all three** (parse, re-render through the shared renderer, byte-compare — exit 1 on any
      mismatch); three-way set merge keyed on `rel`; render; write `%A`; exit 0.
- [ ] 2.3 Sentinel (AC6/P6): before **every** `exit 1`, write
      `<<<<<<< kb-index: merge driver could not resolve — re-run the merge after fixing registration`
      into `%A`, so the failure is visible and trips `guardrails:block-conflict-markers`.
- [ ] 2.4 Add `--check` to `scripts/generate-kb-index.sh`: regenerate into a temp directory and diff
      against the committed `INDEX.md`, `kb-tags.txt` and `kb-categories.txt`; print the diff; exit
      non-zero on any mismatch; fail rather than pass when the regeneration indexed zero files.
- [ ] 2.5 Re-run Phase 1 to green.

## Phase 3 — Registration

- [ ] 3.1 Create `scripts/install-kb-merge-driver.sh`: read `git config --get merge.kb-index.driver`;
      write only when absent or different; store a **worktree-relative** command
      (`bash scripts/merge-kb-index.sh %O %A %B %P`) with no absolute path; never touch
      `config.worktree` or `extensions.worktreeConfig`; retry once on a `config.lock` failure, then
      report to stderr and exit 0.
- [ ] 3.2 Append the registration hook to the existing `SessionStart` array in `.claude/settings.json`.
- [ ] 3.3 Add `"prepare": "bash scripts/install-kb-merge-driver.sh"` to the root `package.json`.
- [ ] 3.4 Add suite cases: idempotency (AC7), no absolute path stored and resolution from a
      subdirectory (AC8), `extensions.worktreeConfig` still unset (AC9), and exit 0 under a held
      config lock (AC10).

## Phase 4 — Wiring, routing correction, ADR

- [ ] 4.1 Create the root `.gitattributes`: `knowledge-base/INDEX.md merge=kb-index`,
      `knowledge-base/kb-tags.txt merge=union`, `knowledge-base/kb-categories.txt merge=union`, plus a
      comment naming the driver and the registration script. Verify with `git check-attr merge` on all
      four paths, including the plugin mirror, which must report `unspecified` (AC12).
- [ ] 4.2 Edit the existing `generate-kb-index` stanza in `lefthook.yml` only: dual glob
      (`knowledge-base/*.md` plus `knowledge-base/**/*.md`) for the gobwas depth-1 hole, and widen
      `git add` to all three generated files. Observe the fix with `lefthook run pre-commit` and only
      `knowledge-base/INDEX.md` staged (AC18, T15) — do not reason about the glob.
- [ ] 4.3 Edit `plugins/soleur/skills/merge-pr/SKILL.md` §3.2b: add the three generated knowledge-base
      paths to the known-members list with the correct remedy — re-run the merge after fixing
      registration; never side-pick; never look for markers on these paths (AC19).
- [ ] 4.4 Replace the `--help` line in `scripts/generate-kb-index.sh` that prescribes the hand-run
      post-conflict regeneration; name the driver and the registration script instead (AC20).
- [ ] 4.5 Write the ADR at the ordinal confirmed in 0.1, with the four decision points and the
      alternatives table from the plan. If the ordinal moved, sweep the plan, this file and AC21 in the
      same edit.
- [ ] 4.6 Regenerate `knowledge-base/INDEX.md`.

## Phase 5 — Verification

- [ ] 5.1 `bash plugins/soleur/test/kb-index-merge-driver.test.sh` exits 0, with the assertion floor
      satisfied.
- [ ] 5.2 Both mutation batteries from the plan's `## Guard Contract` (Guard 1 M1–M9 + H1–H2; Guard 2
      M10–M15 + H3–H4) drive their guard red, and both must-pass rows stay green (AC14).
- [ ] 5.3 `bash scripts/lint-orphan-test-suites.sh` exits 0 (AC15).
- [ ] 5.4 `bash scripts/generate-kb-index.sh --check` exits 0 against the branch (AC17).
- [ ] 5.5 `bash scripts/test-all.sh scripts` exits 0 (AC16).
- [ ] 5.6 `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.
- [ ] 5.7 `python3 scripts/lint-infra-no-human-steps.py --changed` and
      `python3 scripts/lint-guard-contract.py` exit 0.
- [ ] 5.8 Scope check (AC23): the diff touches neither `.github/workflows/ci.yml` nor
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
