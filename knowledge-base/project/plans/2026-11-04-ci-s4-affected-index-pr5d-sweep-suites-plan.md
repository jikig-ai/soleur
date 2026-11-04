---
title: "ci: S4 affected-index PR5d — drain the last 29 live pairs across 4 suites (Ref #10861)"
type: feat
date: 2026-11-04
slug: ci-s4-affected-index-pr5d-sweep-suites
branch: feat-one-shot-10861-pr5d-sweeps
issue: 10861
lane: cross-domain
---

# Plan: S4 affected-index PR5d — drain the last 29 live pairs across 4 suites

Series: Ref #10448 (index-completion tracker), Ref #9729 (S4 epic), ADR-276, ADR-242 (declared-entry grammar).
Parent plan: `knowledge-base/project/plans/archive/20261103-165953-2026-11-03-feat-one-shot-10861-pr5-strict-zero-plan.md` (slice D1 row "PR5d"); canonical task text: `knowledge-base/project/specs/archive/20261103-165953-feat-one-shot-10861-pr5-strict-zero/tasks.md` §Phase 3.
Merged slices under this issue: #11226 (measurement slice), #11950 (PR5a accepts), #12050 (PR5b edges), #12093 (PR5c edges + forbidden-config globs).
Draft PR: #12116 (this worktree's; already carries the `s4-drain` claim label — the claim is already ours).

Holds, unchanged: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no flip PR, no baseline deletion (that is PR5z). One `s4-drain` PR at a time; every number taken at work time on the then-current `origin/main` — nothing below is a receipt.

## Overview

The PR5d slice of the S4 affected-index strict-zero drain. After PR5c merged at main `9a41cb8e9e` the post-merge audit reads `gap_suites=4 gap_refs=29 accepted=1537 stale=0` and the ratchet reads `SOLEUR_PR_AFFECTED_RATCHET exit=1 reason=new-pair live=29 baseline=22`. The 29 remaining live pairs span four suite labels: `plugins/soleur` 16 (the deferred-sweep code-ext pairs), `tests/scripts/argv-bearer-sweep` 5 (deferred-sweep, all `.sh`), `tests/scripts/git-data-birth-readiness-gate` 1 (the mega-edge onto `.claude/hooks/grep-q-pipe-guard.test.sh`), and `plugins/soleur/test/boundary-prefix.test.sh` 7 (drift `new-pair` rows — never baselined). This slice disposition every one of them: re-measure `glob-rate`, trial-declare the 21 code-ext pairs, install the corrected `/*`-form narrow glob for the mega-edge, classify the seven boundary-prefix pairs individually, and prune the baseline in the same commits — leaving `live` at the floor the PR5z slice deletes the baseline against.

## Problem Statement / Motivation

The drain protocol is shrink-only and strict-zero-bound: the baseline file cannot grow, and PR5z deletes it only once `live=0`. The 29 remaining pairs are exactly the residue no earlier slice could touch — whole-tree/glob readers whose disposition the standing rulings left to this PR (PR4b row 6 policy, PR4c row 7 hold-back), plus one double-forbidden mega-edge and a seven-pair drift set on a directory-glob scanning suite. Dispositioning them is the last data movement before the machinery PR.

## Proposed Solution

Execute tasks.md §Phase 3 verbatim (quoted under Canonical Tasks below), in this order:

1. Preflight + measure (receipts): drain-claim check, `BASE` stamp, `rows.txt` selector rows before any index edit, fresh `audit --all-refs`, `glob-rate` for the three sweep labels.
2. The 21 deferred-sweep code-ext pairs: scratch-worktree trial-declare → exact-file `^path` edges where the reveal fits the caps, narrow `glob:<dir>/*<tail>` where reveal or hot-anchor rules block; per-pair rows into `receipts/sweep-decisions.tsv`.
3. The mega-edge: `glob:.claude/hooks/*grep-q-pipe-guard.test.sh` into `AFFECTED_TESTS_SCRIPTS_GIT_DATA_BIRTH_READINESS_GATE_PATHS` — the tasks.md literal `glob:.claude/hooks/grep-q-pipe-guard*.test.sh` classifies `head-mid-slash` → malformed → always-match degrade (verified against `scripts/lib/affected-glob.sh`); the `/*` form classifies `dir`, well-formed.
4. The 7 boundary-prefix pairs individually: recorder `--mode check` for the three flagged possible real reads; accept rows for the mention lines (all anchors cold at ~4-5 commits/90d). The swept-scope `glob:` coverage amendment (4 dir globs, ~164 files, >25% selection rate) is a CTO line, recorded in `decision-challenges.md` — never installed unilaterally.
5. Baseline prune per edge-commit (`--print-baseline` → tmpfile → `mv`, never self-redirect, never hand-edit), fixpoint audit, local battery, ship with the marker + receipts + mirror comment on #10448.

### Canonical tasks (tasks.md §3, verbatim)

> - [ ] 3.1 Apply `glob-rate` verdicts from 0.4: a `glob` verdict → install the measured candidate set; `always_on` → `ALWAYS_ON_SUITES` + `_MIN_ALWAYS_ON_DECLARED` + `f1` pin + `m_s_floor` fixture + delete the suite's accept rows + drop its `test-affected-kb-consumers.baseline.txt` rows + `always-on-justifications.tsv` entry if required.
> - [ ] 3.2 `baselined` verdicts → the explicit call per plan §D2 as corrected by decision-challenges row 11: **all 21 deferred-sweep pairs are code-ext** (`plugins/soleur` 16, `argv-bearer-sweep` 5 — there are no non-code deferred-sweep pairs), so every one takes the trial-declare path — exact-file edge where the reveal fits the caps, narrow `glob:<dir>/<stem>*.<ext>` where reveal/hot-anchor rules block. … Per-suite disposition + reasoning recorded in the body and `receipts/sweep-decisions.tsv`. Confirm the CTO reading of PR4c row 7 vs the narrow-glob spelling BEFORE the slice ships; if refused, exact-file + atomic accepts wherever the limits allow, else a named line in `explicit-calls.tsv`.
> - [ ] 3.3 `tests/scripts/git-data-birth-readiness-gate`: narrow glob `glob:.claude/hooks/grep-q-pipe-guard*.test.sh` (real read at `test-git-data-birth-readiness-gate.sh:2970`); verify the audit reports 0 new pairs for the suite; its other 6 pairs ride their own classifications (`.yml`/`.md` mentions; `cloud-init-git-data.yml` classify at work time).
> - [ ] 3.4 `plugins/soleur/test/boundary-prefix.test.sh`: decide the glob-scan coverage (handoff notes §1: four dir globs ~164 files, `guardrails.sh` pair held-hot at 13 commits — narrow-glob `glob:.claude/hooks/guardrails*.sh` or the swept-scope `glob:` set if the CTO confirms the >25% amendment); re-read its text-only accept rows before relying on them (handoff §2).
> - [ ] 3.5 `plugins/soleur` 90 pairs: the 16 deferred-sweep via §3.2; the rest by classification (its 5 held-back edges ride Phase 2; mention rows in Phase 1 if classification finished early — else here).

(The brief's corrected task text — quoted in Research Insights — supersedes two stale details in the archived original: the 3.3 glob literal must be spelled `glob:.claude/hooks/*grep-q-pipe-guard.test.sh`, and the 3.4/3.5 pair counts are post-PR5b/PR5c numbers: `plugins/soleur`'s "rest" was drained by the edge slices and the live set for it is exactly the 16 deferred-sweep pairs; `git-data-birth-readiness-gate`'s "other 6 pairs" are likewise already gone — its gap line lists exactly 1.)

## Technical Considerations

- **Audit model.** The audit walks declared inputs from rows emitted by `bash scripts/test-all.sh --print-selection --paths=README.md` (row form `AFFECTED_SELECTED\tsuite\t0|1\tedge:declared\t^pat1|^pat2|...`). Only `^file` code-ext entries (`CODE_EXT` = `.sh .bash .py .ts .tsx .jsx .js .mjs .cjs .mts .cts .rb`, replay.py:1076) join the naming walk → reveals; `glob:`, `dir/` (trailing-slash entries), data-ext and extensionless members never scan → reveal-free.
- **Glob grammar** (`scripts/lib/affected-glob.sh`, `_affected_glob_split`): `glob:<dir>/*<tail>` = `dir` class (head must end in `/`, tail must carry `*` and never end in `/`); `glob:*<tail>` = `root` class (dir-less diffs only); every other shape = `malformed` → always-match degrade (fail-wide — the `^glob:<verbatim>` mint). The tasks.md literal `glob:.claude/hooks/grep-q-pipe-guard*.test.sh` classifies `head-mid-slash` → malformed; the corrected `glob:.claude/hooks/*grep-q-pipe-guard.test.sh` classifies `dir`.
- **Accept rows.** `suite<TAB>path<TAB>anchor12<TAB>ordinal<TAB>false-positive: <kind>: <file:line>: <evidence>` — dedupe on first 4 cols; anchors = sha256 of normalized boundary line; one row per boundary line taken ONLY from `audit --all-refs` `ref` lines (never the ratchet report — it prints at most 3 lines per pair); closed kind list; the "false-positive:" prefix is load-bearing (one malformed reason empties the whole exemption map — learning 2026-11-03). Reasons assert about the suite's entire read surface — enumerate real-tree arms or cite the always-on twin (learning 2026-10-31).
- **Refusal rules.** An edge needing >10 accept rows, or whose accept-row anchors land on a file with >8 commits/90d, is held back → narrow-glob spelling (decision-challenges row 17 scopes the hot-anchor refusal to edge declarations; plain mention accept rows carry staleness as the intended signal).
- **Baseline mechanics.** Strictly shrink-only vs `HEAD^1` (`keep = head ∩ live`, replay.py:2015; `grown` judged vs `HEAD^1` :2065). Regenerate per edge-commit via `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main --print-baseline > tmpfile && mv tmpfile scripts/ci-pr-affected-audit.baseline.tsv` — never `> baseline.tsv` directly (self-redirect truncates), never hand-edit. A drained pair's line must drop in the same commit or the tip is red `stale-line`; an unpruned live pair is `new-pair`.
- **Drain claim.** `gh pr list --label s4-drain --state open` must contain no drain PR other than ours — draft PR #12116 already carries the label (the claim is already ours); mirror comment on #10448 at ship time.
- **Battery cost.** Editing `scripts/lib/test-affected-paths.sh` is runner-changed → the local `--affected` gate degrades to the full battery (`AFFECTED_FALLBACK reason=runner-changed`); CI's required `test` context is the merge gate. Run ratchet, audit, `test-affected-kb-consumers.test.sh`, `scripts/lib/inngest-probe-row.test.sh`, shellcheck and the replay suite locally; let the full gate run detached.
- **Recorder.** `scripts/audit-suite-reads.sh record --mode check --only <label>` is the evidence instrument for real-read-vs-mention — the recorder is evidence, never a gate; a `not opened` claim without a recording is forbidden. The PR4c `retest/recorder-table.tsv` row for boundary-prefix (`files=168 cover=argv`) predates the current tree — re-record at work time.
- **Suite label → array.** `AFFECTED_<suite path with [^A-Za-z0-9]→_>_PATHS` in `scripts/lib/test-affected-paths.sh`: `AFFECTED_PLUGINS_SOLEUR_PATHS` (:1208), `AFFECTED_TESTS_SCRIPTS_ARGV_BEARER_SWEEP_PATHS` (:1602), `AFFECTED_PLUGINS_SOLEUR_TEST_BOUNDARY_PREFIX_TEST_SH_PATHS` (:4134), `AFFECTED_TESTS_SCRIPTS_GIT_DATA_BIRTH_READINESS_GATE_PATHS` (:4444). Members carry `# <kind>; <evidence>` comments (e.g. `glob:tests/scripts/lib/*git-data-birth-readiness-gate*.sh  # real read; anchor churn 15 commits/90d`), alphabetical order, `scripts/lib/test-affected-paths.sh" # THIS FILE` member convention.
- **`always_on` arm (expected unused, kept ready).** `ALWAYS_ON_SUITES` (test-affected-paths.sh:132) + `_MIN_ALWAYS_ON_DECLARED` bump (scripts/test-all.sh:4234, currently 111) + `f1` pin and `m_s_floor` mutation fixture (scripts/test-all-affected.test.sh:722) + `scripts/always-on-justifications.tsv` entry + delete the suite's accept rows + drop its `test-affected-kb-consumers.baseline.txt` rows.
- **Verdict-input doctrine** (learning 2026-11-03, PR #11955): an edge is warranted when the suite "really reads or executes the file, or the file's state feeds its verdict" — the edge remedy text itself says this now.

## User-Brand Impact

- **If this lands broken, the user experiences:** a contributor's PR whose affected-gate mis-selects — either a battery over-run (CI cost) or an under-selected guard suite that lets a real defect reach main and reach a user's commit-time/session-time hook.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user-data surface — the touched files are CI selection metadata, oracle baselines and planning receipts inside the repo.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** every touched path is test-selection machinery (`scripts/lib/test-affected-paths.sh`, `*.tsv` oracles, `knowledge-base/` receipts); no diff path matches the canonical `SENSITIVE_PATH_RE` (`apps/web-platform/...`, `apps/*/infra/`, doppler/secret workflows) — the `apps/web-platform/infra/*` paths appear only as *named* edge members, never as edited files.

## Research Insights

**Premise Validation.** `gh issue view 10861` → OPEN (`s4-drain` label on the issue); #10448 → OPEN; `gh pr view 12116` → OPEN DRAFT titled `WIP: feat-one-shot-10861-pr5d-sweeps` already carrying `s4-drain` (claim already ours). `gh pr list --label s4-drain --state open` → exactly `[#12116]`. Collision precheck (#10333): the only open PR naming #10861 is our own draft; the foreign `test-all.sh` processes are sibling worktrees' runs, unrelated to this drain. Cited artifacts verified on disk: parent tasks.md §3, handoff TSV (43 rows; last 21 = plugins/soleur 16 + argv-bearer 5), `scripts/lib/affected-glob.sh` grammar, `suite-durations.tsv` rows (argv-bearer 47,034 ms `measured`; boundary-prefix 1,222 `floor`; `plugins/soleur` no row → `duration-missing`), `_MIN_ALWAYS_ON_DECLARED=111` (test-all.sh:4234), `m_s_floor` (test-all-affected.test.sh:722), `scripts/always-on-justifications.tsv`. Brief-vs-disk discrepancy noted and corrected: the cited parent plan path lives under `plans/archive/20261103-165953-…`; the tasks.md 3.3 glob literal is malformed as written (corrected spelling adopted). Live measurement on this worktree (HEAD = init commit on `9a41cb8e9e`): `audit` exit 1, `gap_suites=4 gap_refs=29 accepted=1537 stale=0 refs=4371 files_read=1228`; `ratchet` `exit=1 reason=new-pair live=29 baseline=22`; baseline file = 22 lines = exactly the 16+5+1 deferred-sweep/mega-edge pairs; the 7 boundary-prefix pairs are `new-pair` drift (main already red on them).

**Property list** (what the ask is for, Phase 0.6b): (1) every remaining live pair gets a rubric-legal disposition; (2) the baseline is regenerated shrink-only in the same commits; (3) the single-claim drain protocol holds; (4) the mega-edge drains without a reveal explosion or a malformed glob; (5) boundary-prefix pairs get honest dispositions while the >25% coverage question is escalated, not decided, in-slice; (6) holds unchanged.

**Cut list.** None — the ask names no new mechanism; every disposition vehicle (exact-file edge, `glob:`/`dir/` entry, accept row, `ALWAYS_ON_SUITES`, `--print-baseline`, `glob-rate`, recorder) already exists on `origin/main` (glob-rate shipped #11226; narrow globs shipped PR5c). No new scripts, gates, or CI jobs are planned.

**The 29 pairs, verified against the live `--all-refs` output (planning-tree receipt `/tmp/pr5d-receipts/audit-all-refs.txt`; re-verify at work time):**

| Suite | Pairs | Baseline? | Disposition |
|---|---|---|---|
| `plugins/soleur` | 16 | yes | deferred-sweep code-ext → trial-declare → `^path` or narrow `glob:` |
| `tests/scripts/argv-bearer-sweep` | 5 | yes | same |
| `tests/scripts/git-data-birth-readiness-gate` | 1 | yes | mega-edge → `glob:.claude/hooks/*grep-q-pipe-guard.test.sh` |
| `plugins/soleur/test/boundary-prefix.test.sh` | 7 | no (drift `new-pair`) | per-pair: recorder-checked possible real reads vs `message:` accepts |

Boundary-prefix ref-line inventory (boundary file:line → named path): `.gitleaks.toml` — `git-commit-secret-scan.sh:612,613,619,622,623,911` (WARN/emit lines plus the hook's own `[ -f ]` stat and `--config` read site — the *suite's* use is text-scan; recorder settles); `.claude/settings.json` — `pre-closing-technical-fork-gate.test.sh:60` (`SETTINGS=` assignment in a scanned test file); `scripts/lib/rule-metrics-constants.sh` — `lib/incidents.sh:71` (a `source` line inside a scanned lib — real open only if an arm executes the lib; recorder settles); `.gitattributes` — `git-commit-secret-scan.sh:929` (deny-message text → `message:`); `.gitignore` — `git-commit-secret-scan.sh:187,189` (printf recovery strings → `message:`); `knowledge-base/marketing/brand-guide.md` — `brand-hex-commit-gate.sh:462` (deny-reason citation → `message:`); `knowledge-base/project/learnings/security-issues/2026-05-25-terraform-show-json-leaks-sensitive-variables-into-fixtures.md` — `git-commit-secret-scan.sh:971` (deny-reason citation → `message:`).

**Learnings applied:** `2026-10-31-accept-row-reasons-must-enumerate-real-tree-read-arms` (reasons enumerate real-tree arms or cite the always-on twin); `2026-11-03-one-malformed-accept-row-reason-drops-every-exemption` ("false-positive:" prefix load-bearing); `2026-11-03-verdict-input-edges-and-the-442-pair-myth` (verdict-input edge doctrine; extensionless/data files never join the naming walk; the two malformed-glob failure modes); `2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree` (verify on the merged tree / current base).

**Skipped gates (recorded so review does not re-litigate):** GDPR gate — no regulated-data surface and none of the (a)-(d) triggers fire (no new LLM/external-API processing of session data, no single-user threshold, no new cron reading learnings/specs, no new distribution surface — receipts stay in-repo). IaC gate — no infrastructure. Encryption Posture — no store or connection. Task Design — no new autonomous-task surface. Guard Contract — the deliverable edits guard *data* (edge members, oracle rows), it creates no guard, gate, lint or drift-check. Observability — no Files-to-Edit under `apps/*/server|src|infra` or `plugins/*/scripts` and no sensitive-path match (preflight Check 10 gates on the same regex → SKIP). ADR gate — no architectural decision: the grammar (ADR-242), policy (PR4b row 6), and strict-zero mechanics (ADR-276) are unchanged; a CTO-approved >25% amendment, if it lands, would be recorded in `decision-challenges.md` and #10448, not as a new ADR. External research — fully local, series-documented machinery.

## Implementation Phases

**Phase 0 — preflight and measurement receipts (no index edits).**

- [ ] 0.1 Drain-claim preflight: `gh pr list --label s4-drain --state open` → assert the only entry is #12116 (our claim). Record `BASE=$(git fetch origin main && git rev-parse origin/main)` and `date -u` into `knowledge-base/project/specs/feat-one-shot-10861-pr5d-sweeps/receipts/measurement-stamp.txt`.
- [ ] 0.2 Selector rows BEFORE any index edit: `bash scripts/test-all.sh --print-selection --paths=README.md > knowledge-base/project/specs/feat-one-shot-10861-pr5d-sweeps/receipts/rows.txt`.
- [ ] 0.3 Fresh audit: `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv --all-refs > receipts/audit-all-refs.txt`; record the `SOLEUR_PR_AFFECTED_AUDIT` marker; assert `unaudited=0 stale=0`; extract live pairs into `receipts/live-pairs.tsv`; diff against `scripts/ci-pr-affected-audit.baseline.tsv` — any pair beyond the expected 29 is new drift → classify it too (never baseline it).
- [ ] 0.4 `receipts/pairs-decisions.tsv` — one row per live pair: `suite<TAB>path<TAB>class<TAB>evidence<file:line>`.

**Phase 1 — glob-rate re-measure (task 3.1).**

- [ ] 1.1 Candidates file `receipts/glob-rate/candidates.tsv`: `plugins/soleur`, `tests/scripts/argv-bearer-sweep`, `plugins/soleur/test/boundary-prefix.test.sh` — blank entries first (existing edges alone); a `glob:`/`dir/`/`@tree` candidate set only if a suite's policy evaluation needs it.
- [ ] 1.2 Pairs file `receipts/glob-rate/pairs.tsv`: the suite's remaining baselined pairs (a `glob` verdict's candidate set must cover every one or it is refused).
- [ ] 1.3 Run `python3 -I scripts/ci-pr-affected-replay.py glob-rate --candidates <f> --pairs <f> --list receipts/rows.txt --commits 200 --base $BASE --spot-check 3 --out receipts/glob-rate/`; exit 4 (model/selector divergence) stops the work. Expected: all-`baselined` (`duration-missing`, `rate-over-and-duration-over-30s`, `duration-floor`) — prior run 2026-11-03 receipt confirms.
- [ ] 1.4 Verdict application: `glob` → install the measured candidate set; `always_on` → the full task-3.1 procedure (ALWAYS_ON_SUITES entry + `_MIN_ALWAYS_ON_DECLARED` +1 at test-all.sh:4234 + `f1`/`m_s_floor` pins in test-all-affected.test.sh + `always-on-justifications.tsv` row + delete the suite's accept rows + drop its `test-affected-kb-consumers.baseline.txt` rows); `baselined` → per-pair dispositions per Phase 2, recorded in `receipts/sweep-decisions.tsv` with the verdict + reason code.

**Phase 2 — the 21 deferred-sweep code-ext pairs (task 3.2).**

- [ ] 2.1 Re-count hot anchors at work time for every file an accept row could anchor on (`git log --since=90.days --oneline -- <file> | wc -l`); knife-edge files: `scripts/betterstack-query.sh` (8→hot on one commit), `.claude/hooks/git-commit-secret-scan.sh` (10 accept rows exactly — an 11th makes the config forbidden).
- [ ] 2.2 Scratch detached worktree; trial-declare candidates in batches; `ratchet --base origin/main --report` per batch → `receipts/reveal-trials.tsv` (edge, new-pair count, anchor commits/90d).
- [ ] 2.3 Install: reveal ≤10 rows and no anchor file >8 commits/90d → exact-file `^path` member with evidence comment; otherwise narrow `glob:<dir>/*<tail>` (well-formed `dir` class) with a one-line justification comment naming the blocked rule. Revealed mentions get accept rows in the SAME commit as the edge; a still-blocked pair goes to `receipts/explicit-calls.tsv`.
- [ ] 2.4 **CTO confirm gate (task 3.2 tail):** the reading of PR4c row 7 ("no pair is globbed unless both measurements meet the thresholds") vs the narrow-glob spelling. No Agent tool in this run → the decision-challenges row carries `pending - assumed: narrow-glob spellings are permitted` (they are the D2/D3 disposition every prior slice used; PR5c installed 123). If a reviewer rules row 7 covers narrow globs: exact-file edge + atomic accepts wherever limits allow, else a named `explicit-calls.tsv` line — the drain never forces it.

**Phase 3 — the mega-edge (task 3.3).**

- [ ] 3.1 Add `"glob:.claude/hooks/*grep-q-pipe-guard.test.sh"  # real read; sed-extracts PATTERN at test-git-data-birth-readiness-gate.sh:2970; exact-file spelling reveals ~151 pairs, anchors on a 67-commits/90d file` to `AFFECTED_TESTS_SCRIPTS_GIT_DATA_BIRTH_READINESS_GATE_PATHS` (after `apps/web-platform/infra/git-data.tf`, before the fixture-env entry — members sorted).
- [ ] 3.2 Verify the audit reports 0 new pairs for the suite; classify-check its `gap` line is gone.
- [ ] 3.3 Same spelling covers `plugins/soleur → .claude/hooks/grep-q-pipe-guard.test.sh` if its trial-declare is over-cap (it is in the 16).

**Phase 4 — boundary-prefix 7 pairs (task 3.4).**

- [ ] 4.1 Recorder: `bash scripts/audit-suite-reads.sh record --mode check --only plugins/soleur/test/boundary-prefix.test.sh --out receipts/recorder-runs/` — capture whether `.gitleaks.toml`, `.claude/settings.json`, `scripts/lib/rule-metrics-constants.sh` are OPENED (transitively or directly). `unreliable` → retry once; still unreliable → classify by static line kind with the recording caveat noted in the row's evidence.
- [ ] 4.2 Real opens (or verdict-input state) → edges: `.gitleaks.toml`/`.claude/settings.json`/extensionless entries are reveal-free exact-file members; `rule-metrics-constants.sh` is code-ext → trial-declare first, narrow glob if over-cap.
- [ ] 4.3 Mentions → accept rows (all anchors cold ~4-5 commits/90d; per-pair rows ≤6): `.gitattributes` (`message:` deny text :929), `.gitignore` ×2 (`message:` recovery strings :187,:189), `brand-guide.md` (`message:` deny citation :462), the learnings doc (`message:` deny citation :971), plus whichever of the flagged three the recorder rules out (`code line in a file read only as text` needs the recording citation).
- [ ] 4.4 CTO line (decision-challenges row): the swept-scope `glob:` set for the suite's 4 dir globs (~164 files, >25% selection rate) — an amendment to PR4b row 6's threshold. `pending - assumed: do not install swept-scope globs this slice; the named-pair dispositions stand alone, per D2's lower-bound framing.` Recorded on #10448 at ship.
- [ ] 4.5 Re-verify the suite's text-only-kind accept rows against the current suite text (handoff §2; the suite has 0 accept rows on this tree — verify none were re-added by siblings and re-check at ship).

**Phase 5 — plugins/soleur remainder (task 3.5).**

- [ ] 5.1 Confirm via the fixpoint audit that `plugins/soleur`'s live set is exactly the 16 deferred-sweep pairs (its non-code pairs were drained in PR5b/PR5c); any additional live pair classifies and drains per the same rules.

**Phase 6 — prune, fixpoint, verify, ship.**

- [ ] 6.1 Per edge/accept commit: `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main --print-baseline > <tmpfile> && mv <tmpfile> scripts/ci-pr-affected-audit.baseline.tsv` — regenerate, never hand-edit; the drained lines drop in the same commit.
- [ ] 6.2 Fixpoint: re-run `audit --accept` until `refs`, `files_read`, `gap_refs`, `stale` stop changing (≤4 rounds, strictly shrinking); assert `unaudited=0 stale=0`; expected end state `gap_suites=0 gap_refs=0` — anything left is a named `explicit-calls.tsv` line, never forced.
- [ ] 6.3 Regenerate `scripts/test-affected-kb-consumers.baseline.txt` if edge additions moved its rows; run `test-affected-kb-consumers.test.sh`.
- [ ] 6.4 Local battery: `lint-orphan-test-suites` (all new `glob:` members classify), shellcheck, `inngest-probe-row.test.sh`, replay suite (`plugins/soleur/test/ci-pr-affected-replay.test.sh`), `test-all-affected.test.sh`. Runner-changed → detached full battery; CI `test` is the merge gate.
- [ ] 6.5 Ship mechanics: PR body per PR5c's shape (What/Audit marker/Verification/Changelog + per-suite disposition summary + `receipts/` links + the `sweep-decisions.tsv` and any `explicit-calls.tsv`); ratchet marker `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=<shrunk> baseline=<shrunk>`; mirror comment on #10448 naming the drained counts and the two pending-CTO lines; `wc -l` of both oracle files quoted; no `git mv` of the plan.

## Files to Edit

- `scripts/lib/test-affected-paths.sh` — edge/glob members in `AFFECTED_PLUGINS_SOLEUR_PATHS` (:1208), `AFFECTED_TESTS_SCRIPTS_ARGV_BEARER_SWEEP_PATHS` (:1602), `AFFECTED_PLUGINS_SOLEUR_TEST_BOUNDARY_PREFIX_TEST_SH_PATHS` (:4134), `AFFECTED_TESTS_SCRIPTS_GIT_DATA_BIRTH_READINESS_GATE_PATHS` (:4444)
- `scripts/ci-pr-affected-audit.accept.tsv` — mention accept rows + revealed-mention rows (C-locale sorted)
- `scripts/ci-pr-affected-audit.baseline.tsv` — regenerated via `--print-baseline` only
- `scripts/test-affected-kb-consumers.baseline.txt` — regenerated if rows move
- `scripts/always-on-justifications.tsv` — only on an `always_on` verdict (expected unused)
- `scripts/test-all.sh` (`_MIN_ALWAYS_ON_DECLARED` :4234), `scripts/test-all-affected.test.sh` (`f1`/`m_s_floor` :722) — same conditional
- `plugins/soleur/test/boundary-prefix.test.sh` — NOT expected; only if a classification proves a suite-text defect (out of scope otherwise)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10861-pr5d-sweeps/tasks.md` — task breakdown (this pipeline's work list)
- `knowledge-base/project/specs/feat-one-shot-10861-pr5d-sweeps/decision-challenges.md` — the `| Item | Class | Ruling |` table incl. the two `pending - assumed` CTO rows
- `knowledge-base/project/specs/feat-one-shot-10861-pr5d-sweeps/session-state.md` — session log (series convention)
- `knowledge-base/project/specs/feat-one-shot-10861-pr5d-sweeps/receipts/` — `measurement-stamp.txt`, `rows.txt`, `audit-all-refs.txt`, `live-pairs.tsv`, `pairs-decisions.tsv`, `sweep-decisions.tsv`, `reveal-trials.tsv`, `glob-rate/` (`candidates.tsv`, `pairs.tsv`, `glob-rate.tsv`, `glob-rate.marker`), `recorder-runs/`, `explicit-calls.tsv` (only if a pair is held)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Apply glob-rate verdicts: re-measure at work time per drain convention" | Phase 1 | mapped |
| 2 | "The 21 deferred-sweep pairs are ALL code-ext … trial-declare → exact-file `^path` edge where the naming-walk reveal fits caps (≤10 rows/edge, no anchor file >8 commits/90d), narrow `glob:<dir>/*<tail>` otherwise" | Phase 2 | mapped |
| 3 | "git-data-birth-readiness-gate → .claude/hooks/grep-q-pipe-guard.test.sh: narrow glob `glob:.claude/hooks/*grep-q-pipe-guard.test.sh`" | Phase 3 | mapped |
| 4 | "boundary-prefix 7 pairs … classify each pair individually" | Phase 4 | mapped |
| 5 | "plugins/soleur remaining pairs via their own classifications" | Phase 5 | mapped |
| 6 | "CONFIRM the CTO reading of PR4c row 7 vs the narrow-glob spelling BEFORE the slice ships" | Phase 2.4 + decision-challenges row | mapped |
| 7 | "The glob-scan coverage decision (4 dir globs ~164 files; >25% selection-rate amendment) is a CTO line" | Phase 4.4 + decision-challenges row | mapped |
| 8 | "Drain preflight `gh pr list --label s4-drain --state open` must be empty — the draft PR #12116 already carries the label; mirror comment on #10448 at ship time" | Phase 0.1 + Phase 6.5 | mapped |
| 9 | "Baseline prune: `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main --print-baseline > tmpfile && mv tmpfile scripts/ci-pr-affected-audit.baseline.tsv` — never `> baseline.tsv` directly (self-redirect truncates), never hand-edit, regenerate per edge-commit" | Phase 6.1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/lib/test-affected-paths.sh` | asks 2, 3, 4 (edge/glob members) | asked |
| `scripts/ci-pr-affected-audit.accept.tsv` | "mention rows" / "atomic accepts where limits allow" (asks 2, 4) | asked |
| `scripts/ci-pr-affected-audit.baseline.tsv` | ask 9 | asked |
| `scripts/test-affected-kb-consumers.baseline.txt` | "drop its `test-affected-kb-consumers.baseline.txt` rows" (ask 1 arm) | asked |
| `always-on-justifications.tsv`, `test-all.sh`, `test-all-affected.test.sh` | "`always_on` → `ALWAYS_ON_SUITES` + `_MIN_ALWAYS_ON_DECLARED` + `f1` pin + `m_s_floor` fixture … `always-on-justifications.tsv` entry if required" (task 3.1) | asked |
| `receipts/*`, `sweep-decisions.tsv`, `explicit-calls.tsv` | "per-pair dispositions recorded in receipts/sweep-decisions.tsv" / "a named line in receipts/explicit-calls.tsv" | asked |
| `decision-challenges.md` | "Persist every decision as a row of the `| Item | Class | Ruling |` table" | asked |
| `session-state.md` | — | inferred — series convention (every prior slice's spec dir carries one); it is the session handoff the drain protocol expects |
| recorder run receipts | "verify via `scripts/audit-suite-reads.sh record --mode check` recorder, never a `not opened` claim without a recording" | asked |

### Split Assessment

- Subsystems touched: 2 — `scripts/`, `knowledge-base/`
- Planned files: ~12-15 (incl. receipts) | Estimated changed lines: ~600-900 (bulk is generated TSV receipts and oracle diffs; code-surface churn is ~40-70 lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the slice boundary is fixed by the drain protocol; splitting inside a slice breaks the same-commit prune atomicity (decision-challenges row 13)

## Acceptance Criteria

- [ ] `gh pr list --label s4-drain --state open` shows only #12116 throughout the slice.
- [ ] `receipts/glob-rate/glob-rate.marker` exists with `base=<work-time origin/main SHA>` and a `baselined`/`glob`/`always_on` verdict per sweep label; every `baselined` pair has a `receipts/sweep-decisions.tsv` row.
- [ ] `git diff` on `scripts/lib/test-affected-paths.sh` shows only `AFFECTED_*_PATHS` member additions/edits; every added `glob:` line classifies `dir` or `root` (never malformed — verify via `_affected_glob_split` or the `lint-orphan-test-suites` census).
- [ ] `glob:.claude/hooks/*grep-q-pipe-guard.test.sh` is a member of `AFFECTED_TESTS_SCRIPTS_GIT_DATA_BIRTH_READINESS_GATE_PATHS`; `grep -n "git-data-birth-readiness-gate" <audit-out>` shows no `gap` line for the suite and 0 new pairs.
- [ ] All 21 deferred-sweep pairs and the mega-edge drain: `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv` exits 0 with `gap_suites=0 gap_refs=0 unaudited=0 stale=0`, or every residual is a named `receipts/explicit-calls.tsv` line.
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` prints `reason=pass live=<0-or-named-residual> baseline=<shrunk>`; the baseline diff is strictly shrink-only vs `HEAD^1` and regenerated (never hand-edited).
- [ ] Accept-row reasons all carry the "false-positive:" prefix and a closed kind; every boundary line of each accepted pair has a row (all-of rule).
- [ ] Recorder receipt(s) under `receipts/recorder-runs/` back every `code line in a file read only as text` reason and every settled real-read claim for the boundary-prefix pairs.
- [ ] `decision-challenges.md` carries the two technical rows (PR4c-row-7 reading; swept-scope `>25%` amendment) as `pending - assumed` (or their CTO rulings if an Agent tool is available at work time).
- [ ] Holds verified: `grep -n PR_AFFECTED_LOCKED scripts/ci-pr-selection.sh` matches; `test -f scripts/ci-pr-affected-audit.baseline.tsv` still true (deletion is PR5z); `git diff --name-only` shows no `CI_PR_AFFECTED`, no activation-lock removal, no replay.py machinery edit.
- [ ] PR body quotes `wc -l` of both oracle files and the final `SOLEUR_PR_AFFECTED_AUDIT`/`SOLEUR_PR_AFFECTED_RATCHET` marker lines; #10448 carries the mirror comment.

## Test Scenarios

- Given the trial-declare reveals >10 pairs for an edge, when the slice installs, then the pair takes the narrow `glob:<dir>/*<tail>` spelling and the glob classifies `dir` (unit — `lint-orphan-test-suites` census + `_affected_glob_split`).
- Given an accept row is written for a mention, when `audit --accept` runs, then `stale=0` and the pair's `gap` line is gone (integration — the audit itself).
- Given the baseline is pruned mid-slice, when `ratchet --base origin/main` runs at each commit boundary, then no `stale-line`/`new-pair` finding for the just-drained pairs (integration — ratchet).
- Given a malformed glob literal (the tasks.md `grep-q-pipe-guard*` spelling), when `_affected_glob_split` classifies it, then `malformed head-mid-slash` — the plan's AC requires the well-formed `/*` form (unit — the suite's own classifier).
- Given the recorder reports `unreliable` for boundary-prefix, when classification proceeds, then the row's evidence column carries the recording caveat and the static line kind decides — never a bare `not opened` claim (procedural — receipt review).
- Given `glob-rate` returns an `always_on` verdict, when the suite promotes, then `_MIN_ALWAYS_ON_DECLARED`, the `f1`/`m_s_floor` pins, the justifications ledger row, accept-row deletion and kb-consumers row deletion all land in the same commit (integration — `always-on-ledger.test.sh` + `test-all-affected.test.sh`).

## Success Metrics

- Post-merge audit: `gap_suites=0 gap_refs=0` (or every residual named in `explicit-calls.tsv`); `stale=0` throughout the slice.
- Ratchet marker green on the merged tree: `reason=pass`.
- `live` and `baseline` both reach the floor PR5z needs (live=0 target; baseline file at the residual lines or empty).

## Dependencies & Risks

- **New drift pairs:** siblings keep landing; 0.3's live-vs-baseline diff absorbs them (classify, never baseline). Hot anchors churn mid-drain → regenerate `--all-refs` on every rebase.
- **Hot-anchor knife edges:** `betterstack-query.sh` at exactly 8 commits/90d, `git-commit-secret-scan.sh` at exactly 10 accept rows — re-count at work time; one commit/row over flips the pair to the narrow-glob spelling.
- **Reveal explosion on code-ext edges:** the naming walk reads declared code files; every candidate gets a scratch-worktree trial first; over-cap → narrow glob (glob entries never join the walk).
- **PR4c row-7 ruling fork:** if the narrow-glob reading is refused, exact-file + atomic accepts where allowed, else named `explicit-calls.tsv` lines — the drain is never blocked by it (deletion isolation sits in PR5z).
- **Recorder unreliability:** `unreliable` verdicts retry once, then static line-kind decides with the caveat recorded — the recorder is evidence, never the gate.
- **Runner-changed battery:** index edits degrade the local `--affected` gate to the full battery; CI `test` is the merge gate — schedule the detached run.
- **Accept-row grammar:** one malformed reason empties the whole exemption map (learning 2026-11-03) — reasons stay inside the closed kind list with the "false-positive:" prefix.
- **Self-redirect truncate:** `--print-baseline > scripts/ci-pr-affected-audit.baseline.tsv` truncates the file it reads — always tmpfile+`mv`.

## Open Code-Review Overlap

None — 95 open `code-review` issues queried 2026-11-04; zero bodies name any planned file.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI-internal test-selection machinery change. The two technical ruling items (PR4c row-7 reading; swept-scope `>25%` amendment) route to `soleur:engineering:cto` per the technical-ruling delegation rule; this run has no Agent tool, so both are recorded as `pending - assumed` rows in `decision-challenges.md` for the work phase to settle.

## References & Research

- Parent plan: `knowledge-base/project/plans/archive/20261103-165953-2026-11-03-feat-one-shot-10861-pr5-strict-zero-plan.md` §D1-D5 (slice table, deferred-sweep call, mega-edge, baseline mechanics, accept conventions)
- Canonical tasks: `knowledge-base/project/specs/archive/20261103-165953-feat-one-shot-10861-pr5-strict-zero/tasks.md` §Phase 3 + decision-challenges rows 11-17
- Deferred-sweep pair list: `knowledge-base/project/specs/archive/20261026-120221-feat-one-shot-s4-affected-index-pr4c-held-back-edges/receipts/handoff-pr5-deferred-sweep.tsv` (last 21 rows) + `handoff-pr5-notes.md` §1-§5
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §"The drain rubric"
- Glob grammar: `scripts/lib/affected-glob.sh` (`_affected_glob_split` doctrine)
- Tools: `scripts/ci-pr-affected-replay.py` (`audit`, `ratchet`, `glob-rate`), `scripts/audit-suite-reads.sh` (`record --mode check`)
- Related PRs: #11226, #11950, #12050, #12093, #12116; trackers #10861, #10448; learnings 2026-10-31, 2026-11-03 ×2

## Out of scope / Holds

Activation (`CI_PR_AFFECTED`, lock removal), PR D (#10414), PR3b (#10859), evidence re-run, flip PR, baseline deletion and adoption-arm removal (PR5z), `suite-durations.tsv` regeneration, any swept-scope `glob:` install above the 25% measured rate without a CTO confirm, suite-text refactors, product code outside the CI oracle files.
