# Tasks: P4a gitleaks per-commit pre-push range scan (ship Phase 6.4)

Plan: `knowledge-base/project/plans/2026-10-26-feat-p4a-gitleaks-pre-push-range-scan-ship-phase-6-4-plan.md`
Issue: #10924 (Ref #9757 only; tick P4a checkbox, do not close). Branch: `feat-one-shot-10924-p4a-gitleaks-pre-push`. Draft PR #11124.

## Phase 1: Setup and RED

- 1.1 Run `git config user.name; git config user.email`; remove `t` / `t@t` from the shared bare-repo config if present.
- 1.2 Create `plugins/soleur/test/ship-prepush-secret-scan.test.sh` (fails first: script absent). Owning EXIT trap before sourcing `test-helpers.sh`; bare `mktemp -d`; `rm -rf "${VAR:?}"`; hermetic git fixture env; copy repo `.gitleaks.toml` into fixtures.
  - 1.2.1 Runtime-assembled synthesized secret (split `printf` args); validate the shape against the repo `.gitleaks.toml` (a `gitleaks dir` precondition over the fixture tip must find it before any RED assertion is trusted).
  - 1.2.2 Use `plugins/soleur/test/lib/gitleaks-probe.sh` (`gl_probe`, `gl_run`): SKIP locally with cause, FAIL under `CI=true` (ADR-188).
  - 1.2.3 Bind `FLOOR=N` on the line directly above `if [ "$PASS" -lt "$FLOOR" ]`.
- 1.3 Write the fixture rows from the plan Test Scenarios (secret added then removed, two secret commits, empty range, empty commit, benign high-entropy + binary, gitleaks absent/unrunnable/timeout/empty-report/no-report/scanned-mismatch/unparseable-scanned-line, non-parseable non-empty report = FINDINGS, missing toml, bad base, unreachable origin, colour pin via `GIT_CONFIG_PARAMETERS`, merge-only known answer, SKILL.md pointer order).

## Phase 2: Core Implementation

- 2.1 Create `plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh` (`set -uo pipefail`, no `-e`; header with exit contract 0/1/43 and the reasoning for 43).
  - 2.1.0 Hardening first: `cd` top-level, `umask 077`, private `mktemp -d` + EXIT/INT/TERM trap, scrub `GIT_*`/`GITLEAKS_*` env (+ `GIT_NO_REPLACE_OBJECTS=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`), colour pins via COUNT and PARAMETERS.
  - 2.1.1 Preconditions with named `reason=`: work tree, `.gitleaks.toml`, runnable gitleaks (absolute path, refuse under repo, probe from cwd `/` with `timeout`, retry wider on 124/137), `--base` regex + `--end-of-options` SHA resolution (`base-unresolvable`), `merge-base` present (`no-merge-base`, depth-1 clones).
  - 2.1.2 Best-effort `git fetch --no-tags origin main` (`--no-fetch` skips); `fetch=ok|stale|skipped`.
  - 2.1.3 `gitleaks git --redact --no-banner --exit-code 1 --config <top>/.gitleaks.toml --report-format json --report-path <tmp> --log-opts="--no-merges BASE..HEAD"` with colour pins on BOTH `GIT_CONFIG_COUNT` and `GIT_CONFIG_PARAMETERS`, `timeout` bound, `GIT_TERMINAL_PROMPT=0`, stdin closed; capture rc and output in separate statements.
  - 2.1.4 Verdict: CLEAN = rc 0 AND report exactly `[]`; rc 1 + non-empty report = FINDINGS (even if unparseable); rc 1 + missing/zero-byte report = NOT_RUN; scanned line read best-effort (`scanned=?` on parse miss), cross-checked against `git log --no-merges --format= --name-only` only when it parses. Findings summary (<= 5) with commit12/File:Line/RuleID, never the secret, `Match` or raw gitleaks output; one static remedy text.
  - 2.1.5 Receipt line (version via `tr -cd '[:alnum:].-'`, other fields controlled tokens/integers); EXIT trap removes the temp report; explicit `exit "$final_rc"`. timeout resolved once (timeout -> gtimeout -> unbounded); `SOLEUR_PREPUSH_SCAN_TIMEOUT` honoured only as an integer in 1..600.
- 2.2 Script header carries the contract, receipt grammar and limitations (merge-only content, `-diff`, version skew). No separate references file.
- 2.3 Edit `plugins/soleur/skills/ship/SKILL.md`: Phase 6 preamble pointer (runnable `bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/prepush-secret-scan.sh"`, explicit exit-code rule, no pipe) before the push; Phase 6.4 one-sentence pointer ("Phase 6's secret scan"); funding trims in Phase 6.4 (#3624 sentence, fail-closed clause, chained-forms parenthetical, Hook ordering). Net <= 0 bytes target (measured: +482 added, -438 trimmed, plus a required >= 150-byte Hook-ordering trim), hard ceiling +116.
- 2.4 Add one layering-table row and a short "Local pre-push range scan" subsection to `knowledge-base/engineering/operations/secret-scanning.md`.

## Phase 3: Registries and gates

- 3.1 `scripts/lib/test-affected-paths.sh`: add the suite's `AFFECTED_..._PATHS` array (script, SKILL.md, suite, `test-helpers.sh`, probe + git-fixture libs, `.gitleaks.toml`, `secret-scan.yml`, itself; no hook or context-sanitize entries). Local affected gate escalates to the full battery (rc=4 on a contended host): run covering suites directly, CI is the gate.
- 3.2 Regenerate `scripts/suite-shard-legs.tsv` (+ `.n`) with `regenerate-shard-manifest.py` and add a measured `scripts/suite-durations.tsv` row; `plugins/soleur/test/fixture-relative-assert.baseline.txt` only if the suite has counted operands.
- 3.3 `affected-index-ratchet`: enumerate uncovered boundary lines with `scripts/ci-pr-affected-replay.py pair_anchors`; add anchor-keyed rows to `scripts/ci-pr-affected-audit.accept.tsv` only for merely-named pairs.
- 3.4 If the suite names `knowledge-base`: regenerate `scripts/test-affected-kb-consumers.baseline.txt` detached and confirm the diff adds only our rows.
- 3.5 Run `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/markdown-lint.sh --repo-sweep`, the pipe-guard test, `shellcheck`, `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`, `bun test plugins/soleur/test/components.test.ts`, `bash scripts/guard-vacuity-floor.test.sh`, `python3 scripts/lint-guard-contract.py`.

## Phase 4: Mutation and verification

- 4.1 Realize Guard Contract mutation rows 1-6 as mutant runs (each must turn the suite RED; row 4 as three measured mutants, row 6 split 6a/6b), mutation rows 7 (`--config`) and 8 (base validation), the direct-assertion arms (exact exit codes, timeout stub, scanned-mismatch stub) and harness rows (i)-(ii).
- 4.2 Run the suite detached (foreground commands time out at 120 s); watch the rc file.
- 4.3 Run the script over this branch's own range: receipt `verdict=CLEAN`.
- 4.5 Measure the three colour-pin mutants and record any equivalent mutant with the measurement.
- 4.4 Diff-scope check: none of `.claude/hooks/`, `.claude/settings.json`, `AGENTS.rules.md`, `.github/workflows/`, `apps/`, `scripts/registry-restore-from-ghcr.sh`, `skill-body-budget.json` changed.

## Phase 5: Ship

- 5.1 Follow-up issue already filed as #11126 (`git push` hook + tracked-files tip scan; Post-MVP / Later); cite `Filed: #11126` in the PR body.
- 5.2 PR body: `Ref #9757`, no closing keyword (assert `closingIssuesReferences` is `[]`), `## Changelog`, `semver:patch`. Tick the P4a checkbox in #10924.
- 5.3 `gh pr merge <N> --squash --auto` (never `--admin`); do not push or sync once queued. No ADR in this PR, so no ordinal race.
