# Tasks: S4 affected-index PR5d — drain the last 29 live pairs across 4 suites (Ref #10861)

Plan: `knowledge-base/project/plans/2026-11-04-ci-s4-affected-index-pr5d-sweep-suites-plan.md`. Decisions: `decision-challenges.md`. Receipts go under `receipts/` in this directory. Holds: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no flip PR, no baseline deletion (PR5z). Every measurement is taken at work time on the then-current `origin/main`; nothing copied from an earlier PR is a receipt. One `s4-drain` PR at a time — draft PR #12116 already carries the claim (preflight: `gh pr list --label s4-drain --state open` shows only it); mirror comment on #10448 at ship.

## Phase 0 — preflight and measurement receipts (no index edits)

- [x] 0.1 `git fetch origin main`, record `BASE=$(git rev-parse origin/main)` + `date -u` in `receipts/measurement-stamp.txt`; assert `gh pr list --label s4-drain --state open` shows only #12116.
- [x] 0.2 Selector rows before any index edit: `bash scripts/test-all.sh --print-selection --paths=README.md > receipts/rows.txt`.
- [x] 0.3 Fresh audit: `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv --all-refs > receipts/audit-all-refs.txt`; record the `SOLEUR_PR_AFFECTED_AUDIT` line; assert `unaudited=0 stale=0`; extract live pairs into `receipts/live-pairs.tsv`; diff vs `scripts/ci-pr-affected-audit.baseline.tsv` — absorb every pair beyond the expected 29 into the classification table (drift is drained, never baselined).
- [x] 0.4 `receipts/pairs-decisions.tsv`: one row per live pair — `suite<TAB>path<TAB>class(edge-real|mention|deferred-sweep)<TAB>evidence(file:line)`.

## Phase 1 — glob-rate re-measure (task 3.1)

- [x] 1.1 `receipts/glob-rate/candidates.tsv`: `suite<TAB>entry` for `plugins/soleur`, `tests/scripts/argv-bearer-sweep`, `plugins/soleur/test/boundary-prefix.test.sh` — blank entries first; candidate glob/dir/@tree sets only if policy evaluation needs them.
- [x] 1.2 `receipts/glob-rate/pairs.tsv`: each suite's remaining baselined pairs (a `glob` verdict's candidate set must cover every one or it is refused).
- [x] 1.3 Run `python3 -I scripts/ci-pr-affected-replay.py glob-rate --candidates <f> --pairs <f> --list receipts/rows.txt --commits 200 --base $BASE --spot-check 3 --out receipts/glob-rate/`; exit 4 (model/selector divergence) stops the work.
- [x] 1.4 Apply verdicts: `glob` → install the measured candidate set; `always_on` → `ALWAYS_ON_SUITES` + `_MIN_ALWAYS_ON_DECLARED` +1 (test-all.sh:4234) + `f1`/`m_s_floor` pins (test-all-affected.test.sh:722) + `scripts/always-on-justifications.tsv` row + delete the suite's accept rows + drop its `test-affected-kb-consumers.baseline.txt` rows, all in the same commit; `baselined` → Phase 2 dispositions + `receipts/sweep-decisions.tsv` row per suite (verdict + reason code).

## Phase 2 — the 21 deferred-sweep code-ext pairs (task 3.2)

- [x] 2.1 Re-count hot anchors at work time (`git log --since=90.days --oneline -- <file> | wc -l`); knife edges: `scripts/betterstack-query.sh` (8 — one commit flips it hot), `.claude/hooks/git-commit-secret-scan.sh` (10 accept rows — an 11th makes the config forbidden).
- [x] 2.2 Scratch detached worktree; trial-declare candidates in batches; `ratchet --base origin/main --report` per batch → `receipts/reveal-trials.tsv` (edge, new-pair count, anchor commits/90d).
- [x] 2.3 Install per pair: reveal ≤10 rows and no anchor file >8 commits/90d → exact-file `^path` member + evidence comment; otherwise narrow `glob:<dir>/*<tail>` (well-formed `dir` class) + justification comment. Revealed mentions get accept rows in the SAME commit as the edge; still-blocked pairs → `receipts/explicit-calls.tsv`.
- [x] 2.4 CTO confirm gate: the PR4c row-7 reading vs the narrow-glob spelling BEFORE the slice ships (spawn `soleur:engineering:cto` with the evidence — the two `pending - assumed` rows in `decision-challenges.md` must resolve to `Ruled by CTO agent, <date>:` before ship; at most two attempts then leave-draft + `domain/engineering` issue per the gate's remedy). If refused → exact-file + atomic accepts where limits allow, else named `explicit-calls.tsv` lines.

## Phase 3 — the mega-edge (task 3.3)

- [x] 3.1 Add `"glob:.claude/hooks/*grep-q-pipe-guard.test.sh"` to `AFFECTED_TESTS_SCRIPTS_GIT_DATA_BIRTH_READINESS_GATE_PATHS` (scripts/lib/test-affected-paths.sh:4444, sorted, justification comment: real read `test-git-data-birth-readiness-gate.sh:2970`; exact-file spelling reveals ~151 pairs anchored on a 67-commits/90d file — doubly refused). The tasks.md literal `glob:.claude/hooks/grep-q-pipe-guard*.test.sh` is `head-mid-slash`-malformed → always-match degrade; the `/*` form classifies `dir`.
- [x] 3.2 Re-run `audit --accept`; assert the suite's `gap` line is gone and it reports 0 new pairs.
- [x] 3.3 The same spelling covers `plugins/soleur → .claude/hooks/grep-q-pipe-guard.test.sh` if its Phase-2 trial-declare is over-cap/hot-anchored.

## Phase 4 — boundary-prefix 7 pairs (task 3.4)

- [x] 4.1 Recorder: `bash scripts/audit-suite-reads.sh record --mode check --only plugins/soleur/test/boundary-prefix.test.sh --out receipts/recorder-runs/` — settle whether `.gitleaks.toml`, `.claude/settings.json`, `scripts/lib/rule-metrics-constants.sh` are opened. `unreliable` → retry once; still unreliable → static line kind decides with the recording caveat in the evidence column.
- [x] 4.2 Real opens / verdict-input state → edges: `.gitleaks.toml`/`.claude/settings.json` are reveal-free exact-file members (never naming-walk nodes); `rule-metrics-constants.sh` is code-ext → trial-declare first, narrow glob if over-cap.
- [x] 4.3 Mentions → accept rows (anchors cold ~4-5 commits/90d; ≤6 rows/pair): `.gitattributes` (`message:` deny text `git-commit-secret-scan.sh:929`), `.gitignore` ×2 (`message:` recovery strings :187/:189), `knowledge-base/marketing/brand-guide.md` (`message:` deny citation `brand-hex-commit-gate.sh:462`), the terraform-show-json learnings doc (`message:` deny citation `git-commit-secret-scan.sh:971`), plus whichever flagged path the recorder rules out (`code line in a file read only as text` — recording citation required).
- [x] 4.4 The swept-scope `glob:` coverage amendment (4 dir globs ~164 files, >25% rate) is a CTO line — `decision-challenges.md` row, `pending - assumed: do not install this slice`; record on #10448 at ship.
- [x] 4.5 Re-verify the suite's text-only-kind accept rows (handoff §2): 0 on this tree — re-check at ship that no sibling added any and that no suite edit made it source/exec a named file.

## Phase 5 — plugins/soleur remainder (task 3.5)

- [x] 5.1 Confirm via the fixpoint audit that `plugins/soleur`'s live set is exactly the 16 deferred-sweep pairs; any additional live pair classifies and drains per the same rules.

## Phase 6 — prune, fixpoint, verify, ship

- [x] 6.1 Per edge/accept commit: `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main --print-baseline > <tmpfile> && mv <tmpfile> scripts/ci-pr-affected-audit.baseline.tsv` — never `> baseline.tsv` directly, never hand-edited; drained lines drop in the same commit.
- [x] 6.2 Fixpoint `audit --accept` until `refs`/`files_read`/`gap_refs`/`stale` stop changing (≤4 rounds); assert `unaudited=0 stale=0`; target `gap_suites=0 gap_refs=0` — residual only as named `explicit-calls.tsv` lines.
- [x] 6.3 Regenerate `scripts/test-affected-kb-consumers.baseline.txt` if edge additions moved its rows; run `test-affected-kb-consumers.test.sh`.
- [x] 6.4 Local battery: `lint-orphan-test-suites` (every new `glob:` member classifies `dir`/`root`), shellcheck, `inngest-probe-row.test.sh`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`, `test-all-affected.test.sh`. Index edit → runner-changed → detached full battery; CI `test` is the merge gate.
- [x] 6.5 Ship: PR body per PR5c (What/Audit marker/Verification/Changelog + per-suite dispositions + receipts links + `sweep-decisions.tsv` + any `explicit-calls.tsv`); `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=<shrunk> baseline=<shrunk>`; `wc -l` of both oracle files quoted; mirror comment on #10448 naming drained counts + the two CTO-line resolutions.

## Verification (final, on the merged tree)

- [x] `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv` → exit 0, `gap_suites=0 gap_refs=0 unaudited=0 stale=0` (or residuals named in `explicit-calls.tsv`)
- [x] `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` → `exit=0 reason=pass`
- [x] `test -f scripts/ci-pr-affected-audit.baseline.tsv` still true (deletion is PR5z); `grep -n PR_AFFECTED_LOCKED scripts/ci-pr-selection.sh` matches; `gh api repos/jikig-ai/soleur/variables/CI_PR_AFFECTED` = 404
- [x] `gh pr list --label s4-drain --state open` shows only #12116 at every boundary; #10448 carries the mirror comment
