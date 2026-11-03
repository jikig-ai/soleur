# Tasks: S4 affected-index PR5, strict zero (Ref #10861)

Plan: `knowledge-base/project/plans/2026-11-03-feat-one-shot-10861-pr5-strict-zero-plan.md`. Decisions: `decision-challenges.md`. Receipts go under `receipts/` in this directory. Holds: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no flip PR. No number from an earlier PR is copied into a receipt; every measurement is taken at work time on the then-current `origin/main`. One `s4-drain` PR at a time (claim = label on draft PR #11950 or its successor + mirror comment on #10448; preflight `gh pr list --label s4-drain --state open` must be empty).

## Phase 0 — base, measure, classify (before any PR)

- [ ] 0.1 `git fetch origin main`, rebase, record `BASE=$(git rev-parse origin/main)` and `date -u` in `receipts/measurement-stamp.txt`.
- [ ] 0.2 Fresh audit: `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv --all-refs > receipts/audit-all-refs.txt`; record the `SOLEUR_PR_AFFECTED_AUDIT` line; assert `unaudited=0 stale=0`; extract the live pair list (`^ref` lines → `suite<TAB>path`) into `receipts/live-pairs.tsv` and diff it against `scripts/ci-pr-affected-audit.baseline.tsv` — absorb every live pair not in the baseline into the classification table (the 2 known drift pairs at planning time: `scripts/image-cve-triage`→`scripts/betterstack-query.sh`, `scripts/betterstack-emitter-read`→`scripts/image-cve-triage.sh`).
- [ ] 0.3 Classification table `receipts/pairs-decisions.tsv`, one row per live pair: `suite<TAB>path<TAB>class(edge-real|mention|deferred-sweep|held-back)<TAB>evidence(file:line)`. Sources: PR4 `pairs-decisions.tsv` for the 546 code mentions and 87 deferred-real rows; per-pair ref-line reading for the 877 non-code pairs and any drift; `scripts/audit-suite-reads.sh record --mode check` for a pair the static read cannot settle (recorder is evidence, never the gate; a `not opened in both recordings` alone never licenses an accept row). A real read of any boundary line makes the pair `edge-real`; all-mention → `mention`.
- [ ] 0.4 `glob-rate` at work time for `plugins/soleur`, `tests/scripts/argv-bearer-sweep`, `plugins/soleur/test/boundary-prefix.test.sh` (and `grep-q-pipe-guard.test.sh` only if its always_on status is re-questioned — it is not): rows.txt before any index edit, `--pairs` scope = the suite's remaining baselined pairs, `--commits 200 --base $BASE --spot-check 3`; save `receipts/glob-rate/`. Expected all-`baselined`; a `glob`/`always_on` verdict installs per the runbook procedure instead.
- [ ] 0.5 Reveal sizing: scratch detached worktree; trial-declare the candidate `edge-real` code-file edges in batches; `ratchet --base origin/main --report` per batch → `receipts/reveal-trials.tsv` (edge, new-pair count, anchor-file commits/90d per `git log --since=90.days --oneline -- <file> | wc -l`). This sizes the PR5b/PR5c slices and flags every `>10`-row or hot-anchor config for the narrow-glob spelling.
- [ ] 0.6 Slice map: assign every live pair to PR5a/PR5b/PR5c/PR5d in `receipts/slice-map.tsv` (pair → slice → disposition → row/edge count).

## Phase 1 — PR5a: the mention accept bulk

- [ ] 1.1 Claim `s4-drain` (label + #10448 comment) after the empty-preflight.
- [ ] 1.2 Write accept rows for every `mention`-classified pair — `suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <kind>: <file:line>: <evidence>` from `audit --all-refs` ref lines ONLY (never the ratchet report), one row per boundary line, closed kind list, reasons enumerate real-tree arms or cite the always-on twin (learning 2026-10-31). Sort into `scripts/ci-pr-affected-audit.accept.tsv` (C-locale). Rows anchored on a file with >8 commits/90 d are refused — those pairs reroute to the edge slices (narrow glob).
- [ ] 1.3 `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main --print-baseline > scripts/ci-pr-affected-audit.baseline.tsv` (prune-only, never hand-edited); re-run `audit` → the mention pairs are gone, `stale=0`; commit rows + pruned baseline together.
- [ ] 1.4 Split note: if the single diff is unreviewable, cut a1 (non-code mentions) / a2 (code mentions + drift) at the suite-area seam — accept-only slices never touch the runner trigger, so no battery cost either way.
- [ ] 1.5 Ship checks: `ratchet` exit 0 `reason=pass`, `wc -l` of both files quoted in the body, no index file in the diff.

## Phase 2 — PR5b / PR5c: the edges

- [ ] 2.1 Non-code `edge-real` edges first (reveal-free): add each path to `AFFECTED_<LABEL>_PATHS` (create the array if absent; alphabetical by label; `"scripts/lib/test-affected-paths.sh" # THIS FILE` member) with the file:line evidence comment; verify `audit` shows the pairs gone with **zero** new pairs.
- [ ] 2.2 Held-back edges ascending-reveal, cumulative ≤150 per slice: declare edge + write accept rows for its revealed mentions in the SAME commit; re-run the audit to fixpoint per round (≤4 rounds, strictly shrinking); rows anchored on a >8-commits file or >10 per edge → do not declare; use the narrow glob (`glob:<dir>/<stem>*.<ext>`, `*` tail mandatory) and note it in the body.
- [ ] 2.3 Narrow-glob edges for the forbidden configs identified in 0.5, each with a one-line justification comment (real read; exact-file spelling would reveal N pairs anchored on a hot file).
- [ ] 2.4 Prune baseline per slice; the `s4-drain` label moves to each new PR; the second slice rebases and regenerates (never hand-edits) the baseline.
- [ ] 2.5 Any still-blocked pair → `receipts/explicit-calls.tsv` for the PR5d CTO line; never force it.

## Phase 3 — PR5d: sweep suites, mega-edge, boundary-prefix

- [ ] 3.1 Apply `glob-rate` verdicts from 0.4: a `glob` verdict → install the measured candidate set; `always_on` → `ALWAYS_ON_SUITES` + `_MIN_ALWAYS_ON_DECLARED` + `f1` pin + `m_s_floor` fixture + delete the suite's accept rows + drop its `test-affected-kb-consumers.baseline.txt` rows + `always-on-justifications.tsv` entry if required.
- [ ] 3.2 `baselined` verdicts → the explicit call per plan §D2: exact-file edges for non-code named pairs; trial-declare code named pairs; narrow glob where the reveal/hot-anchor rules block. Per-suite disposition + reasoning recorded in the body and `receipts/sweep-decisions.tsv`. Confirm the CTO reading of PR4c row 7 vs the narrow-glob spelling BEFORE the slice ships; if refused, exact-file + atomic accepts wherever the limits allow, else a named line in `explicit-calls.tsv`.
- [ ] 3.3 `tests/scripts/git-data-birth-readiness-gate`: narrow glob `glob:.claude/hooks/grep-q-pipe-guard*.test.sh` (real read at `test-git-data-birth-readiness-gate.sh:2970`); verify the audit reports 0 new pairs for the suite; its other 6 pairs ride their own classifications (`.yml`/`.md` mentions; `cloud-init-git-data.yml` classify at work time).
- [ ] 3.4 `plugins/soleur/test/boundary-prefix.test.sh`: decide the glob-scan coverage (handoff notes §1: four dir globs ~164 files, `guardrails.sh` pair held-hot at 13 commits — narrow-glob `glob:.claude/hooks/guardrails*.sh` or the swept-scope `glob:` set if the CTO confirms the >25% amendment); re-read its text-only accept rows before relying on them (handoff §2).
- [ ] 3.5 `plugins/soleur` 90 pairs: the 16 deferred-sweep via §3.2; the rest by classification (its 5 held-back edges ride Phase 2; mention rows in Phase 1 if classification finished early — else here).

## Phase 4 — PR5z: strict zero

- [ ] 4.1 Assert on the final tree: `audit --accept` exits 0, prints `gap_suites=0 unaudited=0 stale=0`; `ratchet --base origin/main` reports `live=0`.
- [ ] 4.2 Delete `scripts/ci-pr-affected-audit.baseline.tsv` in the same commit as 4.3 (the `baseline-deleted` arm requires live empty — it is).
- [ ] 4.3 Remove the adoption arm in `scripts/ci-pr-affected-replay.py` (ADR-276 item 5(d)): a baseline present at HEAD while absent at base exits 1 unconditionally (`baseline-reintroduced` or the named reason) — a re-added file can no longer adopt; update the `ratchet --help` BASELINE STATE text and the failure table.
- [ ] 4.4 `plugins/soleur/test/ci-pr-affected-replay.test.sh`: retire the baseline-only rows (adoption, grown/new-suite/swap/stack, stale-line, baseline-dup, baseline-order, the helper-adoption mutation arm) and add strict-zero rows: empty live set passes (absent/absent), one planted gap → `new-pair`, reintroduced baseline → exit 1, `baseline-deleted` while live → exit 1, plus the mutant kills proving each.
- [ ] 4.5 Sweep: remove `.gitattributes:2` (the `linguist-generated` line for the deleted file); check `scripts/lib/inngest-probe-row.test.sh:143` fixture row keyed to the baseline; verify `scripts/followthroughs/ratchet-observation-window-10865.sh` still passes its baseline-absent-at-tip arm (test rows exist — run them); update the `affected-index-ratchet` job comment in `.github/workflows/ci.yml` (comment only — name, `if:`, `continue-on-error`, permissions untouched).
- [ ] 4.6 ADR-276 `### Stage status`: append the closing dated line per amendment item 10 — "audit exits 0, ratchet strict; replay and go/no-go re-ruling pending" (Ref #10861).
- [ ] 4.7 Runbook `ci-pr-affected-activation.md`: retire the baseline failure-table rows (stale-line, baseline-dup, baseline-order, grown, adoption), add the strict-zero rows, update the drain instructions (`--print-baseline` is now the live-pair listing), record the deletion in the observation log, drop the "only the strict-zero end state may delete it" clause as fulfilled.
- [ ] 4.8 Full replay suite + `test-affected-kb-consumers.test.sh` + `inngest-probe-row.test.sh` + shellcheck + `py_compile`; the local `--affected` gate is runner-changed → detached full battery; CI `test` context is the gate.
- [ ] 4.9 Close-out: #10861 body/comment records the final marker `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=0 baseline=0`, the audit line, per-slice links; `s4-drain` label released; #10448 mirror comment.

## Verification (final, on the merged tree)

- [ ] `test ! -f scripts/ci-pr-affected-audit.baseline.tsv`
- [ ] `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv` → exit 0, `gap_suites=0 unaudited=0 stale=0`
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` → `exit=0 reason=pass live=0 baseline=0`
- [ ] `grep -n "audit exits 0, ratchet strict" knowledge-base/engineering/architecture/decisions/ADR-276-*.md`
- [ ] `grep -n PR_AFFECTED_LOCKED scripts/ci-pr-selection.sh` still matches; `gh api repos/jikig-ai/soleur/variables/CI_PR_AFFECTED` still 404
