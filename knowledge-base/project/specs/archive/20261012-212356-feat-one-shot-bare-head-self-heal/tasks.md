# Tasks: fix bare-root HEAD self-heal

Plan: knowledge-base/project/plans/2026-10-12-fix-bare-root-head-self-heal-plan.md

## Phase 1: Helper
- 1.1 Write failing test skeleton `.claude/hooks/bare-head-self-heal.test.sh` (H1-H10 fixtures + builders, git-fixture-env + incident-sandbox sourced)
- 1.2 Create `.claude/hooks/bare-head-self-heal.sh` (mode 100755): bare check, git-dir == common-dir, symbolic-ref -q, show-ref --verify (HEAD target, then main), symbolic-ref write, sanitized marker; always exit 0
- 1.3 Make H1-H10 green

## Phase 2: Loader wiring
- 2.1 Add loader integration cases L1-L3 to the test (RED first)
- 2.2 Edit `.claude/hooks/session-rules-loader.sh`: child-process helper call before `WS_BRANCH`, `|| true` on the call, PURE-BASH first-line prefix test for the marker (NO `| grep -m1/-q`: grep-q-pipe-guard.test.sh sweeps .claude/hooks/*.sh), trailing marker in `OUT_BODY`, header job 10
- 2.3 Run `session-rules-loader.test.sh` unchanged (positional contract), then L1-L3 green

## Phase 3: Test-bites verification
- 3.1 Apply each of the 10 mutations in the plan's table; confirm the named case goes RED; restore. Mutation 3 drops steps 1 AND 2 together (dropping step 2 alone is an equivalent mutant: `--is-bare-repository` is already false in a worktree)
- 3.2 Add case-count floor (declared cases == executed; zero assertions exits non-zero)

## Phase 4: Docs and gates
- 4.1 `.claude/hooks/README.md` subsection: marker, no-op list, bootstrap-order note, follow-up trigger (guardrail only if drift recurs)
- 4.2 Run dependent suites: grep-q-pipe-guard, hookeventname-coverage, stub-argv-fidelity, scripts/rules-loader-stamp-probe.test.sh (loader copied alone -> helper-absent fail-open), scripts/lib/rule-line-regex-parity.test.sh
- 4.3 Run the Observability discoverability_test probe from the plan under `env -i` and confirm it prints SOLEUR_BARE_HEAD_HEALED
- 4.4 Verify modes 100755, `settings-hook-exec-bit.test.sh`, `devin-matcher-parity.test.sh`, no AGENTS*.md / settings.json in diff
