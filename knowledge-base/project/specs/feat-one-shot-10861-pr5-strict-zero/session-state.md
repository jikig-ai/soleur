# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-03-feat-one-shot-10861-pr5-strict-zero-plan.md
- Status: planning complete, implementation not started
- Plan artifact: written 2026-11-03 on worktree `feat-one-shot-10861-pr5-strict-zero` (HEAD cfb6fc4dc8), draft PR #11950 (unlabelled)

### Errors
None blocking. The full `audit --all-refs` run took ~5 min locally (background it). The live set on the planning tree is already 2 pairs beyond the baseline (drift on main — `scripts/image-cve-triage`↔`betterstack-query`/`image-cve-triage.sh`); a fresh PR's ratchet is red `new-pair` until the first slice absorbs them.

### Decisions
- Slice, don't single-shot: PR5a mention accepts → PR5b/PR5c edges (≤150 cumulative reveal each) → PR5d sweeps + mega-edge → PR5z deletion + machinery (decision-challenges rows 1-2).
- Deferred-sweep (21 remaining of the 43): re-measure `glob-rate` at work time; expected all-`baselined`; per-pair dispositions — exact-file edges where the walk reveal fits, narrow `glob:<dir>/<stem>*.<ext>` where reveal caps or hot anchors block (row 3). PR4c row 7's literal reading vs narrow globs is the one CTO-confirm item; it cannot block the drain because deletion sits in PR5z.
- `git-data-birth-readiness-gate` mega-edge: narrow glob (its ~151 revealed pairs' accept rows are doubly forbidden: >10 rows, 67-commit anchor file).
- Deletion mechanics verified: live=0 → `baseline-deleted` passes; absent/absent = strict zero (`new-pair` per live pair); ADR-276 item 5(d) requires the adoption-arm removal + a reintroduced-baseline exit-1 test row in the same commit.

### Measured (planning-tree numbers, re-take at work time)
- Live: `gap_suites=252 gap_refs=1512 accepted=234 refs=4031 files_read=1203`; baseline 1,510 lines; accept file 459 rows.
- Split: 633 code-ext (546 classified mention = 762 boundary lines; 87 deferred-real = 66 held-back edges + 21 deferred-sweep), 877 non-code (2,087 boundary lines), +2 drift.
- Held-back reveal, all-at-once trial from PR4c: ~407 remaining (475 − 68 moot grep-q-pipe-guard).
- Hot anchors: `grep-q-pipe-guard.test.sh` 67/90d, `guardrails.sh` 13, `betterstack-query.sh` 7 (borderline).
- Sweep durations now: `argv-bearer-sweep` 47,034 ms measured; `boundary-prefix` 1,222 floor; `plugins/soleur` no row.

### Components Invoked
planning subagent only. Sources: issue #10861/#10959, PR3 plan §PR5, runbook `ci-pr-affected-activation.md` §7, ADR-276 (esp. item 5(d)), `scripts/ci-pr-affected-replay.py` (ratchet state table, `code_pats_of`/`CODE_EXT`, `glob_decide`, `_affected_glob_split` via `scripts/lib/affected-glob.sh`), PR4 `pairs-decisions.tsv`, PR4c receipts (`edges-decisions.tsv`, `trial-all-edges-*`, `handoff-pr5-*`), #11226 glob-rate receipts, learnings 2026-10-30/2026-10-31.

### Next Action
Implement Phase 0 of `tasks.md`: rebase, fresh `audit --all-refs` receipts, classification table, work-time `glob-rate`, reveal trials, slice map. Then claim `s4-drain` on draft PR #11950 (preflight: `gh pr list --label s4-drain --state open` empty) and mirror-comment #10448.

## Deepen pass (2026-11-03, worktree HEAD d09ff3c361 — KB edits only, no product code touched)

Verified the plan's mechanics against code; all load-bearing claims hold. Findings:

- **Confirmed**: `audit --all-refs` prints `ref<TAB>suite<TAB>path<TAB>file:line<TAB>anchor/ordinal<TAB>text` per boundary line (replay.py:2113-2117); accept-row shape and the every-boundary-line rule (docstring:121-128); the ratchet report shows only `refs[:3]` per new-pair (:1938) — `--all-refs` really is the only complete source. Accept file = 459 data rows + 2 header comments; baseline = 1,510 lines.
- **Confirmed**: ratchet state table matches the plan/ADR-276 item 5 verbatim (ADR line ~533): base-present/head-absent passes only at live=0 (`baseline-deleted`, :2050-2053); absent/absent is strict zero (`new-pair` per live pair); the adoption hole is real — base-absent/head-present passes whenever `live ⊆ head` (a re-added file equal to live passes; an empty re-add at live=0 passes trivially; `grown` is gated on `base_text is not None`, :2065). Test rows cited by the plan exist (`row_rt_adopt` :2473, `row_rt_adopt_unequal` :2474, `row_rt_deleted` :2475, grown :2479-2482, `rt_p_weak` :2285; chks :2872-2875 stale/dup/order and :2899-2908 state-table+growth; mutants :4883-4892). `scripts/ci-pr-affected-preactivation.sh` has ZERO baseline coupling.
- **Confirmed**: naming-walk nodes are exactly `^`-prefixed exact-file entries on CODE_EXT files not in RUNNER_TRIGGERS, read only when already-read texts name them (`code_pats_of`, :1376-1386). Non-code `^file` edges, `dir/` prefixes (trailing slash — there is no `dir:` spelling) and `glob:` entries are never nodes → never reveal. `glob:` tails require `*` (`tail-no-star` malformed → always-match `^glob:<verbatim>` mint).
- **Correction (decision-challenges row 11)**: all 21 remaining deferred-sweep pairs are code-ext (PR4c `handoff-pr5-deferred-sweep.tsv`: plugins/soleur 16 + argv-bearer-sweep 5, all `.sh/.mjs/.ts/.py`). Plan §D2's "non-code deferred-sweep" class is empty and its "plugins/soleur 6× code" undercounts (16×). Strategy unchanged — all 21 take the trial-declare/narrow-glob path; the item-1 disposition still covers the sweep suites' 73 other non-code baseline pairs (plugins/soleur 59 + argv-bearer-sweep 14, extension-counted) via normal classification.
- **Correction (row 14)**: `scripts/rule-metrics-aggregate.sh` measures 7 commits/90d on this tree, not 15 as the Risks line says (and the path is `scripts/`, not `scripts/lib/`). Under the >8 threshold today; re-count at work time.
- **New named decision (row 12)**: drift pair `scripts/image-cve-triage → scripts/betterstack-query.sh` — the no-override arm (`image-cve-triage.test.sh:~429`, `env -i ... bash "$SUT"`) stats the real file via `[[ -f "$QUERY" ]]` (`image-cve-triage.sh:94`) and asserts the arm is reached; never executes it (credential refuse precedes :100). If `-f` is ruled a read → edge-real → rides an edge slice and PR5a's marker stays red `new-pair` on it alone (same state main is already in — documented exception, not a regression).
- **Tightened (row 13)**: baseline is strictly shrink-only vs `HEAD^1`; `--print-baseline` can never add a line (`keep = head ∩ live`, :2015) → drift pairs can only be drained, and each drained pair's baseline line must drop in the same commit (else `stale-line`). Task 2.4 updated.
- **Decided (row 15)**: keep `RATCHET_BASELINE` in `RATCHET_ORACLE` post-deletion — a re-added file still trips `oracle-inputs-changed` and the observation probe's parity row (:85-87) stays in sync. Task 4.5 updated; the deletion commit will print the notice once (expected).
- Phase-0 re-measurement confirmed present and correctly sequenced: task 0.2 (fresh `audit --all-refs` + live-pairs diff) and task 0.4 (`glob-rate` for the three sweep labels) precede every slice. No step added.
- Spot checks: `betterstack-emitter-read → image-cve-triage.sh` mention classification matches precedent (accept.tsv:290-292, same suite / same ALLOW-key shape, "data row not fed to a read loop"; reason must cite the `-live` always-on twin for the FLOOR/LIVE real-tree arms). `git-data-birth-readiness-gate → .claude/hooks/grep-q-pipe-guard.test.sh` real read confirmed (`test-git-data-birth-readiness-gate.sh:~2970`, sed-extracts PATTERN — the mega-edge/narrow-glob ruling stands). `boundary-prefix` = 1 baseline pair (guardrails.sh); handoff §1-2 confirmed. `AFFECTED_PLUGINS_SOLEUR_PATHS` does not exist yet — created at edge time per task 2.1.
- **Work-ready**: yes, with rows 11-16 applied. The only open fork is the PR4c-row-7 narrow-glob CTO reading (already isolated to PR5d; the deletion sits in PR5z so nothing blocks).

## Work (2026-11-03, worktree HEAD 06800a1122 — Phase 0 + Phase 1 done)

- **BASE** `f05eaab78faec600bb8a2c763891bf79a34d748b`; stamp `2026-11-03T07:11:42Z` in `receipts/measurement-stamp.txt`.
- **0.2** fresh `audit --all-refs` → `receipts/audit-all-refs.txt` (`suites=724 always_on=116 audited=608 unaudited=0 gap_suites=252 gap_refs=1512 accepted=234 stale=0 refs=4031`); `receipts/live-pairs.tsv` = 1,512 pairs = baseline(1,510) + 2 drift.
- **0.3** `receipts/pairs-decisions.tsv` — 1,512 rows: **1,272 mention / 153 edge-real / 66 held-back / 21 deferred-sweep**. Code-ext classes inherited from PR4/PR4c; the 877 non-code pairs + 2 drift classified per-boundary-line at work time (boundary contexts in `receipts/noncode-boundary-lines.txt`, handle traces in `read-flagged-review.txt`, `final-verify.txt`). `image-cve-triage → betterstack-query.sh` = edge-real (`-f` stat at `image-cve-triage.test.sh:~429`) per decision-challenges row 12; `betterstack-emitter-read → image-cve-triage.sh` = mention (manifest data row).
- **0.4** `receipts/glob-rate/` re-run at work time (`--commits 200 --base $BASE --spot-check 3`, blank-entry candidates for the 3 suites; grep-q-pipe-guard not re-questioned).
- **0.5** `receipts/reveal-trials.tsv` — sizing table only: 219 edge rows (153 edge-real + 66 held-back) with `git log --since=90.days` anchor counts; **110 hot-anchor flags** (>8 commits/90d → refuse exact-file, reroute to narrow glob — top: review/SKILL.md 184, work/SKILL.md 127, apply-web-platform-infra.yml 107, infra-validation.yml 93, suite-durations.tsv 91, ci.yml 62). **Deviation: live `ratchet --report` trial-declares in a scratch worktree were NOT run** — the new-pair counts per edge remain for Phase 2.
- **0.6** `receipts/slice-map.tsv` — PR5a 1,272 (this slice) / PR5b edge-real 153 / PR5b-PR5c held-back 65 / PR5d = deferred-sweep 21 + git-data-birth mega-edge 1.
- **1.1** preflight `gh pr list --label s4-drain --state open` empty → `s4-drain` labeled on PR #11950; mirror comment posted on #10448.
- **1.2–1.3** 2,448 accept rows (one per boundary line) merged C-locale into `scripts/ci-pr-affected-audit.accept.tsv` → **459 → 2,907 data rows**; baseline regenerated via `ratchet --print-baseline` to a temp file then moved (the task's literal `> baseline.tsv` self-redirect truncates the file before the tool reads it — use a temp file) → **1,510 → 239 lines**. Post-audit: `accepted=1506 stale=0 gap_refs=240` — the gap set equals exactly the non-mention classes (153+66+21=240), zero mention leaks.
- **1.4** no split — single accept+baseline diff; accept-only (no runner trigger).
- **1.5** accept 2,909 total lines (2 hdr + 2,907 data), baseline 239. No index file in the diff (no `test-affected-paths.sh`, no preactivation, no ci.yml). **Exception (row 12): real `ratchet` is red `new-pair` on `image-cve-triage → betterstack-query.sh` alone** — live=240, baseline=239; same state main is already in; the pair rides an edge slice.
- **Deviation: recorder never run.** `audit-suite-reads.sh record --mode check` was not executed for any pair — all classifications are static per-boundary-line reads. ~102 accept rows carry kind `code line in a file read only as text`; the runbook wants recorder evidence (file opened, path not opened, both recordings) behind that kind. Phase 2/3 (or a reviewer pass) should run the recorder against those ~30 suites before relying on the rows — listed for re-verification in `receipts/pairs-decisions.tsv`.
