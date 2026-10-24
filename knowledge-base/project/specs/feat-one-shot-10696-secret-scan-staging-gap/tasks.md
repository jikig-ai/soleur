# Tasks: would-be index for git-commit-secret-scan (#10696)

Plan: `knowledge-base/project/plans/2026-10-23-fix-commit-secret-scan-would-be-index-plan.md` (deepened 2026-10-23)
Branch: `feat-one-shot-10696-secret-scan-staging-gap` | Draft PR: #10893 | Closes #10696 | Ref #10331 (non-closing)
Decisions: `decision-challenges.md` rows 1 to 21 (CTO rulings; do not re-litigate).

## Phase 0: RED (tests first)

- 0.1 Helpers: `cp` and `sleep` in `_mk_stub_path`; the `git` PATH shim (absolute real git, `printf %q` log, env-selected failure modes keyed on "sim index set and different from the real path", logs `LC_ALL` and the three sim variables); a recording gitleaks stub (copies `$GIT_INDEX_FILE`, logs `git ls-files -s`); `_rows_since_mark <rule_id>`; `_assert_repo_untouched <repo> -- <run>` (index `cmp`, object count, real gitdir listing, working tree) with a self-test; a private `TMPDIR` per hook run.
- 0.2 Fixture modes `untracked` and `tracked-modified` for `_mk_leaky_repo` and `_mk_bare_root_with_worktree`; a fixture control (`gitleaks detect --no-git`, rc 1); a gap-witness control and a deny twin per group; explicit non-sequential `_mk_pem` bodies.
- 0.3 Flip the pre-filter table row `git add -A && git commit -m "fix: tidy"` to must-match; state the expected result per form; keep `git commit -m x`, `-n -m x`, `git status && git commit -m x`, `git commit -m "fix the commit scan"`, `git addr` must-skip.
- 0.4 Groups 1 to 12 from the plan (leak cases, must-PASS controls, directory-proof set 10b, `-diff` canary, invariants incl. `core.splitIndex=true`, bare-root, failures, pathspec-missing deny (producer rule removed, row 25), linked worktree and symlinks).
- 0.5 Extra rows: walker output via `ctr_stage_dump`, commit-flag table, `rm`/`mv`, two roots, mixed directories, force-add, config-transforming refusal and pin canaries, fsmonitor, TERM arm (release-file contract), `deny()` anchor and no-`restore --staged` text, stale sweep, residual pins, `check-attr` equivalence test, consumer stub test.
- 0.6 Run the suite against the unmodified hook; confirm each new arm is RED for the right reason.

## Phase 1: walker (`.claude/hooks/lib/commit-target-roots.sh`)

- 1.1 `_ctr_reset_stage` at top level and in `ctr_collect`; outputs `CTR_STAGE_API`, `CTR_COMMIT_STAGES`, `CTR_STAGE_OPAQUE`, `CTR_STAGE_REFUSE(_WHY)`, `CTR_STAGE_UNSIMULABLE`, the six parallel `CTR_ADD_*` arrays, `CTR_ADD_ARGV`, `CTR_COMMIT_ALL`, `CTR_COMMIT_PATHS(_LITERAL)`, `CTR_STAGE_CD_FIRST`; `ctr_stage_dump`.
- 1.2 `_ctr_git_walk`: validated `add`/`stage` records (every word before `--`, control bytes, `x` flag, unquoted glob chars, launcher allowlist, `own_C`, `force`); `rm`/`mv` ignored; stage-unknown verbs and `x`-flagged command word -> opaque; config-transforming arguments -> refuse; producer facts.
- 1.3 `_ctr_commit_flags`: short bundles with attached operands, optional-argument `S`/`u`, long-option tables (staging, benign, separate-operand, `--no-`), unknown long -> opaque, `--` pathspec.
- 1.4 Widen and anchor `ctr_wants_lex`; leave refusal logic and `ctr_resolve_roots` untouched.

## Phase 2: `.claude/hooks/lib/commit-index-sim.sh`

- 2.1 `cis_plan` (exactness predicate and directory proof (i)/(ii)/(iii)), `cis_build` (prepare, export, replay, commit step, superset, force-add; codes 0/10/20; workdir removed on failure), `CIS_ENV`, `cis_export`/`cis_unexport` restoring prior values, `CIS_ACTIVE`.
- 2.2 One git wrapper: pins (`core.fsmonitor`, `core.untrackedCache`, `core.splitIndex`, per-filter neutralisation), `LC_ALL=C`, anchored error classification, sanitised error line, 30 s total deadline, `timeout -k 2` integer ceiling >= 1, perl `alarm` fallback, deny when no bounding tool.
- 2.3 Header: contract, inputs, allowlist, failure classes, bash 3.2 rules, no `mktemp`/`trap`/`exit`/`$(...)`.

## Phase 3: hook glue and `scan_root` edit (`.claude/hooks/git-commit-secret-scan.sh`)

- 3.1 Source the sim lib in the same checked `if` as the walker lib; read `${CTR_COMMIT_STAGES:-0}`; read the payload `.cwd` directly.
- 3.2 Split trap (`cleanup` on EXIT, `exit 130`/`exit 143` on INT/TERM); `sim_dir=""` first; `mktemp ... || deny`; marker-gated sweep (row 45); guarded `rm -rf`; ERR trap and exit latch (rows 30, 41).
- 3.3 Policy loop: refuse -> deny; `cis_build` code mapping; one plan for the command, only the `CIS_TOP` root simulated when the directory is proven; export window around `scan_root`; the perl bound prefix on both gitleaks calls (no wrapper, rows 20 and 30).
- 3.4 `deny()` under `CIS_ACTIVE`: a finding keeps `git-commit-secret-scan` with `mode=... cause=finding`, the recovery text is built from facts (`sim_recovery`), a simulation failure is `git-commit-secret-scan-sim-deny` with `mode=... cause=...` (the `sim-failed` bypass row was retired, row 34).
- 3.5 The one `scan_root` edit: batched `git check-attr -z --stdin diff` (fallback to the old loop on the plain path, deny in sim mode); update `tooling`/`parse`/`bound` repair text; update the header comment (behaviour, failure table, named residuals).

## Phase 4: docs

- 4.1 One-line note in `knowledge-base/engineering/operations/secret-scanning.md`.
- 4.2 `.claude/hooks/README.md`: rewrite the "BEFORE the command runs (#10696)" sentence, move the new residuals into the list, add a pointer paragraph.
- 4.3 `guardrail-audit.md`: new lib row (`soleur-coupled`), divergence note, walker outputs, census count; one disclosure sentence in `secret-scan-hook.sh.template` and `verification-readme.template`; re-run `manifest.test.sh`.

## Phase 5: verification and measurements

- 5.1 Suite green; `MIN_ASSERTIONS` to the measured total; drive every mutation-matrix row RED once (apply, observe, revert); canary arms against the pinned gitleaks 8.24.2 tarball; `scan_root` body diff shows only the `check-attr` hunk.
- 5.2 `shellcheck` (four shell files), `lint-trap-tempfile-ownership.py`, `verification-scaffold/test/manifest.test.sh`, `c4-count-parity.test.sh`, markdownlint; refresh `scripts/suite-durations.tsv`; record suite wall time before/after (added <= about 60 s).
- 5.3 Re-confirm the default hook timeout (600 s) and `onFailure` from the Claude Code hooks documentation.
- 5.4 Latency: >= 30 interleaved pairs in a scratch worktree, gate `p95(b) - p95(a) <= 1.5 s`, report paired p50, load, filesystem, unstaged baseline, 5,000-untracked and 5 MB runs. If the gate fails: KEEP-OPEN, stop, report.
- 5.5 Lexer-failure ceiling over the local sampled commit lines (counts only), under 0.5 percent, plus the multi-root frequency table.

## Phase 6: ship

- 6.1 PR body: `Closes #10696`, separate `Ref #10331` line, measurements, `## Changelog`, closing line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- 6.2 File one follow-up issue listing the named residuals (script-wrapped staging, content created or changed earlier in the same command, positional path after `-m`, content brought from outside the working tree, filters/LFS, porting the would-be index to the emitted template); link it from the PR body.
- 6.3 Every commit ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; never edit `plugins/soleur/skills/work/SKILL.md`; no `git stash`.
