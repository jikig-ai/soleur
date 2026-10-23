# Tasks: would-be index for git-commit-secret-scan (#10696)

Plan: `knowledge-base/project/plans/2026-10-23-fix-commit-secret-scan-would-be-index-plan.md`
Branch: `feat-one-shot-10696-secret-scan-staging-gap` | Draft PR: #10893 | Closes #10696 | Ref #10331 (non-closing)

## Phase 0: RED (tests first)

- 0.1 Add `cp` to `_mk_stub_path`, a `git` PATH-shim helper (logs argv plus `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES` per call, then execs real git), a private-`TMPDIR` helper, a snapshot helper (index sha256, loose-object count, working-tree listing).
- 0.2 Flip the pre-filter table row `git add -A && git commit -m "fix: tidy"` to must-match; add must-match rows for each Design 2 form and keep `git commit -m x`, `git status && git commit -m x`, `git log --grep=commit` must-skip.
- 0.3 Groups 1 to 12 from the plan (leak cases, must-PASS controls, `-diff`, invariants, bare-root, failures, linked worktree).
- 0.4 Extra rows: walker output table, commit-flag table, `rm`/`mv`, multi-root and directory-rule cases, force-add, residual pins (`terraform show > f && git add f`), telemetry rule ids, signal arm (sleeping gitleaks stub, TERM).
- 0.5 Run the suite against the unmodified hook; confirm the new arms are RED for the right reason. Use an explicit non-sequential body for every `_mk_pem` fixture.

## Phase 1: walker (`.claude/hooks/lib/commit-target-roots.sh`)

- 1.1 Initialise and reset `CTR_COMMIT_STAGES`, `CTR_STAGE_OPAQUE`, `CTR_ADD_ARGV`, `CTR_COMMIT_ALL`, `CTR_COMMIT_PATHS`, `CTR_COMMIT_PATHS_LITERAL` at top level and in `ctr_collect`.
- 1.2 `_ctr_git_walk`: `add`/`stage` records (`tgt_known`, `exact`, `force`, words) validated with the lexer flags; `rm`/`mv` ignored; stage-unknown verbs and an `x`-flagged command word followed by a staging word set `CTR_STAGE_OPAQUE`.
- 1.3 `_ctr_commit_flags`: short bundles (attached operands, optional-argument `S`/`u`), long-option tables (staging, benign, separate-operand, `--no-` forms), unknown long option -> opaque, `--` pathspec.
- 1.4 Widen `ctr_wants_lex` (verbs, bundle, `--(al|o|in|pa)`, bare ` -- `, bare first word after `commit`).
- 1.5 Leave refusal logic and `ctr_resolve_roots` untouched; re-run the existing walker/target arms.

## Phase 2: `.claude/hooks/lib/commit-index-sim.sh`

- 2.1 `cis_prepare` (absolute index and objects paths, `:` rejected, `mkdir -m 700`), `cis_export`/`cis_unexport`, `_cis_git` (timeout wrapper, `LC_ALL=C`, first stderr line, total 15 s deadline via `$SECONDS`).
- 2.2 Exact replay (allowlisted options, failure classes), superset (`add -A`, force-add of literal words, deny on non-literal), commit step ladder (`-u -- paths`, `-u`, `-A`).
- 2.3 Header: contract, allowlist, failure classes, bash 3.2 rules, no `mktemp`/`trap`/hook response, never inside `$(...)`.

## Phase 3: hook glue (`.claude/hooks/git-commit-secret-scan.sh`)

- 3.1 Source the sim lib in the same checked `if` as the walker lib; read `${CTR_COMMIT_STAGES:-0}`.
- 3.2 Split the trap (`cleanup` on EXIT, `exit 130`/`exit 143` on INT/TERM); declare `sim_dir=""` first; allocate with `|| deny`.
- 3.3 Per-root build/export/scan/unexport loop; explicit checks on every `cis_*` call; exactness predicate (one root, proven directory, every record exact, not opaque, no loop).
- 3.4 `deny()` would-be note and `git-commit-secret-scan-sim-deny` rule id when `SIM_ACTIVE=1`; bypass row `git-commit-secret-scan-sim-failed`; update `tooling`/`parse`/`bound` repair text; `scan_root` body stays byte-identical.
- 3.5 Update the header comment (behaviour, failure table, named residuals).

## Phase 4: docs

- 4.1 One-line note in `knowledge-base/engineering/operations/secret-scanning.md`.
- 4.2 Pointer paragraph in `.claude/hooks/README.md`.
- 4.3 `guardrail-audit.md` rows (new lib; walker row mentions the new outputs).

## Phase 5: verification and measurements

- 5.1 Suite green; raise `MIN_ASSERTIONS` to the measured total; drive each mutation-matrix row RED once (apply, observe, revert).
- 5.2 `shellcheck` (four shell files), `lint-trap-tempfile-ownership.py`, `verification-scaffold/test/manifest.test.sh`, `c4-count-parity.test.sh`, markdownlint.
- 5.3 Confirm the harness default hook timeout from the Claude Code hooks documentation.
- 5.4 Latency: scratch worktree, 20 runs each, p95 = 19th sorted sample, added p95 <= 1.5 s, plus a 5k-untracked superset run. If above: KEEP-OPEN, stop, report.
- 5.5 Lexer-failure ceiling over the local sampled commit lines (counts only), under 0.5 percent; tabulate how often two roots occur.

## Phase 6: ship

- 6.1 PR body: `Closes #10696`, separate `Ref #10331` line, measurements, `## Changelog`, closing line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- 6.2 File one follow-up issue listing the named residuals (script-wrapped staging, content created earlier in the same command, positional path after `-m`, filters/LFS).
- 6.3 Every commit ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; never edit `plugins/soleur/skills/work/SKILL.md`; no `git stash`.
