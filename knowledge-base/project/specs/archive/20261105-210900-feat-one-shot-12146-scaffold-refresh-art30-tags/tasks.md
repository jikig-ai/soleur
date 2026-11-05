# Tasks: feat-one-shot-12146-scaffold-refresh-art30-tags

Plan: knowledge-base/project/plans/2026-11-05-feat-scaffold-refresh-path-and-art30-version-tags-plan.md
Tracker: #12146 (items 2 and 3). PR #12177 (draft). PR body uses `Ref #12146`, never a closing keyword.

## Phase 1: RED (ledger, fixture, failing suite)

- 1.1 Generate `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.emitted.sha256` from template git history (six rows; header carries the regeneration command and the append-only rule)
- 1.2 Create fixture `plugins/soleur/skills/constraint-scaffold/test/fixtures/stage-a.v1.0.236.emitted` (byte copy of the substituted emission at 21c9168e59)
- 1.3 Create `plugins/soleur/skills/constraint-scaffold/test/refresh-stage-a.test.sh` with the 12 cases and labelled sub-rows in the plan (per-case sandbox copy of scripts/ and references/, base fixture cp -R, MIN_ROWS floor)
  - 1.3.1 cases 1-4: refresh (mode 0644), already current (no ledger read), edited copy refused (75, template-side report only, planted token absent), stripped newline refused
  - 1.3.2 cases 5-6: dirty tree (67), live-lock positive control, untracked destination (67), symlink-before-tree (75); stage-a/config absent and dangling symlink (70, no lock taken)
  - 1.3.3 cases 7-8: current template hash in ledger (message prints regen command), downgrade refused (75), missing/empty/comment-only ledger fails closed
  - 1.3.4 cases 9-12: symlinked file/parent and empty-digest arms, other emitted files unchanged and dest changed, no pin literal (with positive control), frozen A-to-B interface and contents: read
  - 1.3.5 confirm the suite is RED (unknown flag, rc 64)

## Phase 2: GREEN (`--refresh-stage-a` in constraint-scaffold.sh)

- 2.1 Header: Modes, exit 75, exit 70 text, line-131 usage text
- 2.2 Arg parse third arm, `MODE="stage-a"`
- 2.3 Functions: `sha256_of` (sha256sum else shasum -a 256), `fresh_stage_a`, exact first-field ledger match, `refresh_stage_a`
- 2.4 Step order per plan (70 first, symlink and physical-dir equality, tracked + clean tree, arm traps then lock, mktemp, verify, rank classify, pre-write recheck, chmod 0644, mv); reuse `_wt_cleanup` with `${STAGE_A_TMP:-}`; no top-level trap lines
- 2.5 Refusal path: hand-rolled exit 75; template-side-only report (`diff | grep -v '^< ' | cut -c1-200 | head -60`, wrapped so SIGPIPE cannot abort); downgrade refusal prints no diff
- 2.6 Suite green; run parity, emit-fix-constraints and bite-proof locally

## Phase 3: docs and records

- 3.1 SKILL.md: Usage block, fix "only re-writable artifact" sentence, Self-tests row, ledger link, pin-bump author guidance (no description change)
- 3.2 ADR-071 dated amendment (four-class enumeration, contents: read privilege rule, frozen A-to-B interface, amended bite-proof sentence, one-line alternatives); ADR-074 pointer line
- 3.3 constraint-scaffold.sh header, 66 hint, SKILL.md 75 mentions (71-74 prose, 66..74 cleanup sentence), SIGKILL recovery

## Phase 4: registries

- 4.1 `git add` the new test first
- 4.2 `python3 scripts/regenerate-shard-manifest.py --incremental --write`; verify exactly one new sorted row in `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`
- 4.3 `bash scripts/lint-orphan-test-suites.sh`
- 4.4 Replay ratchet / registry lint; add `scripts/ci-pr-affected-audit.accept.tsv` rows only if reported, in sorted position
- 4.5 Ratchets: fixture-relative-assert, fixture-dir-operand-assert, lint-shell-capture-exit (no baseline growth)

## Phase 5: Art. 30 register (CLO-ruled wording)

- 5.1 Three exact-string replacements in `knowledge-base/legal/article-30-register.md` (member (1), member (8), item (g)(4))
- 5.2 `grep -rnE '5aa6f47e|v1\.0\.[0-9]{2,}' knowledge-base/legal` (only the 7086 counsel review remains)
- 5.3 `scripts/lint-legal-registers.sh`, `scripts/lint-art30-reverification.sh`, markdownlint

## Phase 6: verify and PR

- 6.0 `take_run_lock` race: fixed inline after the second-reviewer DISSENT (no issue filed); see the plan amendment
- 6.1 `git diff origin/main -- apps/web-platform/test/claude-pin-lockstep.test.ts` is empty
- 6.2 PR body: `Ref #12146`, `## Changelog`, `semver:patch`; check `sync-pr-behind.sh 12177 --queue-state` before any push; real push exit code
- 6.3 CI: rely on required `test`; read infra-validation and sandbox-canary-capture-gate by hand; stop if the owner-run freeze blocks the merge

## Phase 7: post-merge

- 7.1 Tick boxes 2 and 3 (not 1) in #12146; re-read the body to confirm only those flipped and the directive is intact
- 7.2 `GH_TOKEN="$(gh auth token)" bash scripts/followthroughs/claude-code-action-residual-pins-12136.sh`; report the exit code verbatim (5 until item 1 is ticked by the parent session)
