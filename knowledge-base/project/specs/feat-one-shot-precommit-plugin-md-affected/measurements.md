# Measurements — scoped skill-security-scan calibration in pre-commit

All on 2026-09-25, this worktree, bun 1.4.2, first-party corpus N = 102 `SKILL.md`.

## Dogfood commit (AC9)

Commit `9344d3a892` staged `lefthook.yml`, `plugins/soleur/skills/ship/SKILL.md` and the test file
(`LEFTHOOK_EXCLUDE=bun-test`; `plugin-component-test` live).

| | Before (baseline, same day) | After |
|---|---|---|
| `plugin-component-test` | 176 s (calibration 116.5 s of it) | **48.64 s** |
| calibration log line | n/a | `[skill-security-scan calibration] scoped 1/102` |
| load average (1 min) at start / end | — | 9.15 / 8.33 |
| `git commit` wall, rc | — | 55 s, rc 0, HEAD moved |

## Targeted rows (Phase 3)

| Row | Result |
|---|---|
| 3.1 one `SKILL.md` | rc 0, `scoped 1/102`, 12 s (was 127.9 s for the file), 21 pass / 1 skip (REVIEW) |
| 3.2 two `SKILL.md` | rc 0, `scoped 2/102` |
| 3.3 agent `.md` only | rc 0, `scoped 0/102`, 2 skip |
| 3.4 `CI=1` + scope | `full 102/102` (rc 1 expected: `-t` matched 0 tests) |
| H1 variable unset | `full 102/102` |
| H2 `references/*.md` path | `scoped 0/102`, 2 skip |
| 3.5 `hook-git-env-coverage.test.sh` | rc 0, `SOLEUR_GUARD2_RECEIPT run_lines=32 runners=3` |
| 3.6 `lefthook-bun-test-merge-skip.test.sh` | Passed: 5, Failed: 0 |

## AC10 — `ship/SKILL.md` size

271033 bytes before, 271032 after (sentence 114 → 113 bytes).

## Mutation spot-checks (Guard Contract M1–M5)

Each mutation applied to the committed test file, then restored with `git restore --source=HEAD`.

| # | Mutation | Row | Observed (expected-good in brackets) |
|---|---|---|---|
| M1 | drop `&& !process.env.CI` | 3.4 | `scoped 1/102` [`full 102/102`] — RED |
| M2 | `skills = all` | 3.1 | `scoped 102/102` [`scoped 1/102`] — RED |
| M3 | keep first staged path only | 3.2 | `scoped 1/102` [`scoped 2/102`] — RED |
| M4 | basename match | 3.1 | `scoped 102/102` [`scoped 1/102`] — RED |
| M5 | drop HIGH-RISK `skipIf` | 3.3 | 1 pass / 1 skip [0 pass / 2 skip] — RED |

## Review round (2026-09-25) — scoping extracted to `resolveCalibrationScope`

Test-design review found the CI side unpinned: `skipIf(true)` on HIGH-RISK or an inverted REVIEW
skip left CI at rc 0 with the calibration dark. The decision is now a pure helper with 10 unit
rows, a CI-only "unscoped over a non-empty corpus" test, and an `afterAll` that throws under CI
unless both calibration tests ran. Mutations run on an untracked copy, `CI=true`:

| Row | Result |
|---|---|
| CI control (unmutated) | rc 0, `full 102/102`, 14 pass |
| MA REVIEW skip inverted | rc 1, `CI ran 1/2 calibration tests (high-risk)` |
| MB HIGH-RISK `skipIf(true)` | rc 1, `CI ran 1/2 calibration tests (review)` |
| scoped `ship/SKILL.md` | rc 0, `scoped 1/102`, 1 pass / 2 skip |
| agent `.md` + codex mirror `SKILL.md` | rc 0, `scoped 0/102`, 3 skip (mirror is out of scope, not drift) |
| `./`-prefixed SKILL.md (path-form drift) | rc 1, throws `names SKILL.md not in the corpus` |
