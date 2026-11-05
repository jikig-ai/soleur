---
title: "ci: S4 affected-index PR5z — strict zero: delete the baseline, remove the adoption arm"
type: feat
date: 2026-11-05
slug: feat-one-shot-10861-pr5z-strict-zero
branch: feat-one-shot-10861-pr5z-strict-zero
issue: 10861
closes: 10861
lane: cross-domain
---

# Plan: S4 affected-index PR5z — strict zero: delete the baseline, remove the adoption arm

Series: Ref #10448 (index-completion tracker), Ref #9729 (S4 epic), ADR-276 (amendment items 5(d) and 10), ADR-242 (declared-entry grammar).
Parent plan: `knowledge-base/project/plans/archive/20261103-165953-2026-11-03-feat-one-shot-10861-pr5-strict-zero-plan.md` (slice D1 row "PR5z"); canonical task text: `knowledge-base/project/specs/archive/20261103-165953-feat-one-shot-10861-pr5-strict-zero/tasks.md` §Phase 4 + the Verification block — quoted verbatim below, this slice's contract.
Merged slices under this issue: #11226 (measurement), #11950 (PR5a accepts), #12050 (PR5b edges), #12093 (PR5c edges + globs), #12116 (PR5d sweeps → the baseline is a tracked empty blob on `origin/main` at `f06b595420`).
Draft PR: #12127 (this worktree's; `s4-drain` claim NOT yet applied — preflight `gh pr list --label s4-drain --state open` was empty at plan time; the claim lands at work start).

Holds, unchanged: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no flip PR, no edge/accept-row drain work beyond what Phase 0's residual-drift gate requires. One `s4-drain` PR at a time; every number taken at work time on the then-current `origin/main` — nothing below is a receipt.

## Overview

The final slice of the strict-zero drain. PR5d merged with `live=0 baseline=0`, leaving `scripts/ci-pr-affected-audit.baseline.tsv` a tracked empty blob. This slice (1) asserts strict zero on the final tree (`audit --accept` exits 0 with `gap_suites=0 unaudited=0 stale=0`; `ratchet --base origin/main` reports `live=0`), (2) deletes the baseline file in the same commit as (3) the adoption-arm removal in `scripts/ci-pr-affected-replay.py` — after this PR a baseline present at HEAD while absent at base exits 1 unconditionally, so a re-added file can never be adopted (ADR-276 amendment item 5(d)), plus (4) the strict-zero rework of the replay suite's state-table rows and mutants, (5) the file-reference sweep (`.gitattributes`, `ci.yml` job comment, fixture/probe verification, `RATCHET_BASELINE` kept in `RATCHET_ORACLE`), (6) the ADR-276 `### Stage status` closing dated line, (7) the runbook §7 strict-zero rewrite, and (8) drain close-out (final marker on #10861, `s4-drain` label released, mirror comment on #10448).

## Problem Statement / Motivation

The adoption arm is the last permissive path in the ratchet: while `base absent / HEAD present` passes whenever `live ⊆ head`, a re-created baseline file equal to the live set passes silently — the baseline can be reborn and the ratchet would re-tighten around it. ADR-276 item 5(d) rules that the commit deleting the baseline also removes the adoption arm, and amendment item 10 has this PR append the closing Stage-status line. Two complications measured at plan time (2026-11-05): (a) `origin/main` is currently red — the newest `affected-index-ratchet` runs, including the merge_group run on the PR5d merge commit `f06b595420` itself, print `exit=1 reason=stale-accept live=3 baseline=0` (8 stale accept rows from sibling anchor drift + 3 live pairs from `plugins/soleur/test/components.test.ts:987-992` naming `scripts/{betterstack-query,sentry-issue}.sh`); the fix PR #12128 (issue #12110, anchor repin) is in flight — the strict-zero assertion cannot be made until main is green again; (b) deleting the baseline orphans **42 accept rows** keyed on `suite → scripts/ci-pr-affected-audit.baseline.tsv` (14 each on the `-a`/`-b`/`-c` replay-suite labels — the suites name the path as a fixture-write token, accepted not declared): once the path is untracked the rows go stale (`path-untracked`/`not-a-gap`), so they must be deleted in the same commit or the deletion commit itself is red.

## Proposed Solution

Execute tasks.md §Phase 4 verbatim (quoted under Canonical Tasks), in this order:

1. **Phase 0 — claim, stamp, measure, coordinate.** `s4-drain` label on draft #12127 + mirror comment on #10448; `BASE` stamp; fresh `audit --all-refs` + `ratchet --base origin/main` receipts on the rebased tree. If the tree is red on main-side drift (#12110-class): check #12128's state — merged → rebase and proceed; open and progressing → hold this slice's destructive commit until it lands or absorb only the residual the repin does not cover, recorded per the runbook's repair-owner rule; never duplicate in-flight repin work.
2. **Phase 1 — the deletion commit (single commit, tasks 4.2+4.3+4.4 machinery+rows+4.5 `.gitattributes`).** Insert the `baseline-reintroduced` arm in `ratchet_run` (replay.py ~:2057), update the RATCHET docstring (BASELINE STATE + verdict list), rework the state-table test rows and mutants, `git rm scripts/ci-pr-affected-audit.baseline.tsv`, delete the 42 orphaned accept rows, and drop `.gitattributes:2` — all in ONE commit, because the task text couples the arm removal to the deletion and the accept rows go stale the instant the path is untracked.
3. **Phase 2 — sweep verification (task 4.5).** `RATCHET_BASELINE` stays in `RATCHET_ORACLE` (replay.py:1758) so a re-added file still trips `oracle-inputs-changed`; `ratchet-observation-window-10865.sh` untouched (verify its baseline-absent-at-tip arm via its test rows); `inngest-probe-row.test.sh` verified no fixture row keys on the baseline; `ci.yml` `affected-index-ratchet` job comment updated (comment only — job name, `if:`, `continue-on-error`, permissions, and the step NAME `Ratchet the audit against the committed baseline` all untouched: the observation probe keys on that step-name literal at :88).
4. **Phase 3 — docs (tasks 4.6+4.7).** ADR-276 dated closing line; runbook §7 rewritten to the strict-zero state.
5. **Phase 4 — verify + battery (task 4.8).** Full replay suite + `test-affected-kb-consumers.test.sh` + `inngest-probe-row.test.sh` + observation-window rows + shellcheck + `py_compile`; final-tree audit/ratchet assertions; CI `test` is the merge gate.
6. **Phase 5 — close-out (task 4.9).** Final marker comment on #10861 (`SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=0 baseline=0` + audit line + per-slice links); `s4-drain` label released post-merge; #10448 mirror comment.

### Canonical tasks (tasks.md §Phase 4 + Verification, verbatim)

> - [ ] 4.1 Assert on the final tree: `audit --accept` exits 0, prints `gap_suites=0 unaudited=0 stale=0`; `ratchet --base origin/main` reports `live=0`.
> - [ ] 4.2 Delete `scripts/ci-pr-affected-audit.baseline.tsv` in the same commit as 4.3 (the `baseline-deleted` arm requires live empty — it is).
> - [ ] 4.3 Remove the adoption arm in `scripts/ci-pr-affected-replay.py` (ADR-276 item 5(d)): a baseline present at HEAD while absent at base exits 1 unconditionally (`baseline-reintroduced` or the named reason) — a re-added file can no longer adopt; update the `ratchet --help` BASELINE STATE text and the failure table.
> - [ ] 4.4 `plugins/soleur/test/ci-pr-affected-replay.test.sh`: retire the baseline-only rows — the adoption state-table rows `row_rt_adopt`/`row_rt_adopt_unequal` (:2473-2474, chks :2899-2900; `row_rt_adopt_unequal` can be reworked INTO the reintroduced-baseline exit-1 row), the grown rows (:2479-2482, chks :2905-2908), the stale-line/dup/order/nonl chks (:2872-2875) IF the implementer retires the `--baseline` machinery arms they cover (they stay reachable whenever a HEAD baseline exists — e.g. an old `--base`; keeping them is the cheaper call, decide in the PR), `row_rt_helper_pr_tree_ignored`'s adoption arm (`rt_p_weak` :2285, chk :2970) and the mutations :4883-4892 — and add strict-zero rows: empty live set passes (absent/absent), one planted gap → `new-pair`, reintroduced baseline → exit 1, `baseline-deleted` while live → exit 1, plus the mutant kills proving each.
> - [ ] 4.5 Sweep: remove `.gitattributes:2` (the `linguist-generated` line for the deleted file); check `scripts/lib/inngest-probe-row.test.sh:143` fixture row keyed to the baseline; verify `scripts/followthroughs/ratchet-observation-window-10865.sh` still passes its baseline-absent-at-tip arm (test rows exist — run them); **keep `RATCHET_BASELINE` in `RATCHET_ORACLE`** (replay.py:1756) — a re-added file then still trips `oracle-inputs-changed`, and the probe's parity row (:85-87) stays in sync; expect the deletion commit itself to print the notice once and record that in the body; update the `affected-index-ratchet` job comment in `.github/workflows/ci.yml` (comment only — name, `if:`, `continue-on-error`, permissions untouched). `scripts/ci-pr-affected-preactivation.sh` needs nothing — verified zero baseline coupling.
> - [ ] 4.6 ADR-276 `### Stage status`: append the closing dated line per amendment item 10 — "audit exits 0, ratchet strict; replay and go/no-go re-ruling pending" (Ref #10861).
> - [ ] 4.7 Runbook `ci-pr-affected-activation.md`: retire the baseline failure-table rows (stale-line, baseline-dup, baseline-order, grown, adoption), add the strict-zero rows, update the drain instructions (`--print-baseline` is now the live-pair listing), record the deletion in the observation log, drop the "only the strict-zero end state may delete it" clause as fulfilled.
> - [ ] 4.8 Full replay suite + `test-affected-kb-consumers.test.sh` + `inngest-probe-row.test.sh` + shellcheck + `py_compile`; the local `--affected` gate is runner-changed → detached full battery; CI `test` context is the gate.
> - [ ] 4.9 Close-out: #10861 body/comment records the final marker `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=0 baseline=0`, the audit line, per-slice links; `s4-drain` label released; #10448 mirror comment.
>
> Verification (final, on the merged tree):
> - [ ] `test ! -f scripts/ci-pr-affected-audit.baseline.tsv`
> - [ ] `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv` → exit 0, `gap_suites=0 unaudited=0 stale=0`
> - [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` → `exit=0 reason=pass live=0 baseline=0`
> - [ ] `grep -n "audit exits 0, ratchet strict" knowledge-base/engineering/architecture/decisions/ADR-276-*.md`
> - [ ] `grep -n PR_AFFECTED_LOCKED scripts/ci-pr-selection.sh` still matches; `gh api repos/jikig-ai/soleur/variables/CI_PR_AFFECTED` still 404

## Technical Considerations

- **The adoption hole, exactly.** In `ratchet_run` (replay.py:2057-2075) there is no explicit adoption arm — the hole is the ABSENCE of a check: `new = live − head_lines` is empty whenever `live ⊆ head`, and `grown` is gated on `base_text is not None` (:2072), so a HEAD-present baseline on a base-absent repo passes unconditionally when live ⊆ head. The fix is additive: `if head_text is not None and base_text is None: findings.append(("baseline-reintroduced", …))` placed immediately before the `if new and head_text is None and base_text is not None:` block so it precedes `baseline-deleted`/`new-pair` in findings order (the marker names `findings[0]`), does NOT suppress the `elif new:` new-pair detail (live pairs not in the re-added file still print), and fires regardless of content — an empty re-add fails too (`ratchet_read` returns `""`, not `None`, for an empty file). Suggested entry text mirrors `baseline-deleted`: `baseline-reintroduced\t<rel>\t<n> pair(s) are live; the baseline is retired and a re-added file is never adopted` with remedy `delete the file; the live set is the state now`. Reason token `baseline-reintroduced` fits the closed `baseline-*` token grammar (decision-challenges row: `pending - assumed`).
- **What stays.** `--baseline`, `baseline_split`, `ratchet_read`, `ratchet_base`, the `baseline-deleted` arm (base present/HEAD absent — still reachable on stale bases and during this PR's own merge window), the present/present arms (`stale-line`, `baseline-dup`, `baseline-order`, `grown` — reachable via `--baseline <path>` and an old `--base`), `--print-baseline` (post-deletion it is the live-pair listing: `keep = live if head_text is None`, :2022), and `RATCHET_BASELINE` + its `RATCHET_ORACLE` membership (:1748,:1758 — decision-challenges row 15 of the parent spec: a re-added file still trips `oracle-inputs-changed`; the probe's parity row stays in sync). Keeping the present/present machinery is the cheaper call task 4.4 itself recommends — the arms remain reachable whenever a HEAD baseline exists against a base that has one.
- **Same-commit set.** The deletion commit MUST carry: `git rm scripts/ci-pr-affected-audit.baseline.tsv`; the reintroduced arm + docstring edits; the test-file rework (the suite must stay green per commit); `.gitattributes:2` removal; and **the 42 accept rows keyed on `suite → scripts/ci-pr-affected-audit.baseline.tsv`** (14 each under `plugins/soleur/test/ci-pr-affected-replay-{a,b,c}` — the suites name the path as a fixture-write/name token; untracked after deletion → `stale` rows). Deleting those rows is deletion-safe: the pairs are `not-a-gap`, so no edge or replacement row is needed.
- **Test-file rework (task 4.4, line numbers as of `f06b595420`).** Already present and correct — keep: `row_rt_deleted` (:2475, baseline-deleted-while-live exit 1), `row_rt_deleted_end` (:2476, deleted at live=0 → pass = the strict-zero end state), `row_rt_absent_both` (:2477, planted gap → new-pair), `row_rt_absent_both_clean` (:2478, absent/absent pass), grown rows (:2479-2482), stale-line/dup/order/nonl chks (:2872-2876). Rework: `row_rt_adopt` (:2473) → the reintroduced row (suggest rename `row_rt_reintroduced`; the `adopt` fixture already writes `bl-ok.tsv` with content AND `bl-empty.tsv` — `rt_in std adopt 1 baseline-reintroduced --baseline scripts/bl-ok.tsv` covers contentful re-add, `rt_in good adopt 1 baseline-reintroduced --baseline scripts/bl-empty.tsv` covers the empty re-add); `row_rt_adopt_unequal` (:2474) folds in or retires. `rt_p_weak` (:2285): comment retires "adoption" wording (the spoofed helper reports base-absent now); `row_rt_helper_pr_tree_ignored` (:2515, chk :2970) keeps `1 grown` assertions — the weak arm still proves the merge-base helper ran because a PR-tree helper would now yield `baseline-reintroduced`, not `pass` — token, not exit code, is the discriminator (add a comment noting this). Chk texts :2899-2900 rewritten to strict-zero semantics.
- **Mutants (:4883-4898).** Keep `ratchet-deleted-baseline-tolerated`/`ratchet-deleted-baseline-always-refused`/`ratchet-unresolved-base-is-an-adoption`/grown mutants (machinery kept). `ratchet-adoption-refused` (:4889 — widens `grown`'s guard to fire on base-absent) is still killed ONLY if a reintroduced row asserts `! grep -q '^grown' <<<"$ROUT"` — the marker alone cannot see it (the reintroduced finding precedes `grown` in findings order). New mutants to add: `ratchet-reintroduced-tolerated` (guard → `if False:` — killed by the contentful reintroduced row: a live-matching re-add would pass); `ratchet-reintroduced-needs-content` (`head_text is not None` → `head_text` — killed by the empty-file arm); a third weakening the arm to fire only when `new` is empty (re-admission of adoption for live-matching files — killed by the same row).
- **Degraded `--print-baseline` behavior.** Unchanged: it refuses exit 2 `census-degraded`; the oracle notice is best-effort when the base is unresolvable (:2024-2028). No text changes needed beyond the BASELINE STATE paragraph.
- **Fixture paths that keep working.** The suite's `bl scripts/ci-pr-affected-audit.baseline.tsv` uses (:2281, :2682, :2699, :2827, :2860, :3027, :3201, :3259) are scratch-repo paths and stub-gh fixtures — deleting the real file affects none of them. Rows :2860-2864 (`is_doc_path`/`is_trigger_path` classification checks) must be re-verified post-deletion — they assert the path is NOT doc/trigger-class and must not silently vacate (assert they still classify, or pin the classification of the literal string).
- **`ci.yml` comment edit.** :398-416 — only the comment block changes. The job name, `if:`, `continue-on-error`, `permissions`, `fetch-depth`, env and the step `name: Ratchet the audit against the committed baseline` (:430) are untouched — the observation probe keys on the step-name literal (`STEP=` at `ratchet-observation-window-10865.sh:88`), so even the step name is load-bearing.
- **Drain claim & the label release.** Claim = `s4-drain` label on draft #12127 + mirror comment on #10448 (task header line 3). Release at close: removing the label from the merged PR regresses the observation probe's floor to the older labeled sentinel (#11226) — the CONSERVATIVE direction (longer window), and the drain is complete, so release is safe; record the release in the close-out comment.
- **Battery cost.** This PR does not touch `RUNNER_TRIGGERS` (`scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`) — the `--affected` degradation in task 4.8 is inherited wording; measure at work time. The `ci.yml` comment edit selects every suite naming `ci.yml` via edges; the replay.py edit selects the replay suites. Run the named suites locally; CI `test` is the merge gate regardless.

## User-Brand Impact

- **If this lands broken, the user experiences:** a contributor's PR mis-judged by the advisory `affected-index-ratchet` — a false red (noise on every PR) or, worse, a false green that lets the retired baseline re-materialize and the index regress silently toward the pre-drain state.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user-data surface — touched files are a CI check script, test fixtures, a deleted oracle file, and docs.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** every touched path is CI/test machinery or knowledge-base docs; no diff path matches the canonical `SENSITIVE_PATH_RE` (`apps/web-platform/...`, `apps/*/infra/`, doppler/secret workflows) — the only `apps/` strings are inside fixture literals, never edited files.

*Scope-out override:* `threshold: none, reason: CI-check script + test fixture + docs only; no user-facing or regulated surface is edited.`

## Observability

The surface being changed is itself part of the observability machinery (the advisory ratchet job + the observation-window probe); the section declares how its own state is read.

```yaml
liveness_signal:
  what: "SOLEUR_PR_AFFECTED_RATCHET marker line on the advisory affected-index-ratchet CI job; SOLEUR_PR_AFFECTED_AUDIT on a local audit run"
  cadence: "per PR / merge_group entry (ratchet job, continue-on-error) / on demand (audit)"
  alert_target: "GitHub Actions job annotation on the PR + the observation-window probe scripts/followthroughs/ratchet-observation-window-10865.sh"
  configured_in: ".github/workflows/ci.yml (affected-index-ratchet job, comment-only edit) and scripts/ci-pr-affected-replay.py"

error_reporting:
  destination: "GitHub Actions annotations + the job's --report file; local receipts under knowledge-base/project/specs/feat-one-shot-10861-pr5z-strict-zero/receipts/"
  fail_loud: "ratchet marker reason=new-pair | baseline-reintroduced | baseline-deleted | stale-accept | unaudited; audit exit 1 with gap_suites/gap_refs/stale counts"

failure_modes:
  - mode: "a PR re-adds the retired baseline file"
    detection: "exit=1 reason=baseline-reintroduced on the next run, plus the oracle-inputs-changed notice (RATCHET_BASELINE stays in RATCHET_ORACLE)"
    alert_route: "PR annotation"
  - mode: "a suite gains an undeclared read (post-deletion world)"
    detection: "exit=1 reason=new-pair (absent/absent strict zero — there is no baseline to absorb it)"
    alert_route: "PR annotation + #10448 cadence"
  - mode: "deletion commit orphans the 42 baseline-keyed accept rows"
    detection: "stale-accept findings on the deletion commit itself if the rows are not removed in the same commit"
    alert_route: "blocks the commit's own audit run — same-commit removal required"

logs:
  where: "GitHub Actions job log for affected-index-ratchet; local receipts/*.txt"
  retention: "GHA default retention; receipts committed to the spec dir permanently"

discoverability_test:
  command: "bash -c 'test ! -f scripts/ci-pr-affected-audit.baseline.tsv && echo baseline-absent'"
  expected_output: "baseline-absent"
```

## Research Insights

**Premise Validation.** `gh issue view 10861` → OPEN (tracker; carries `s4-drain` label on the issue itself — the claim protocol applies the label to the draft PR). `gh pr view 12116` → MERGED as `f06b595420` ("WIP: feat-one-shot-10861-pr5d-sweeps"): baseline = tracked empty blob, `live=0 baseline=0` at its merge. `gh pr view 12127` → OPEN DRAFT, this worktree, no labels. `gh pr list --label s4-drain --state open` → empty (preflight satisfied). Collision precheck (#10333): exit 10 — the only open PR naming #10861 is our own draft; foreign `test-all.sh` processes are sibling worktrees (`feat-one-shot-12013-12025-affected-gate-reprice`, `feat-one-shot-12110-accept-anchor-repin`) — not duplicates of this slice but ONE is a live coordination surface (below). **STALE-PREMISSE FINDING (material):** `origin/main` is currently RED — the `affected-index-ratchet` merge_group jobs on `f06b595420` (PR5d's own merge, run 41943389794) and on queue entry `62335a1f1a` (run 41991683080, 2026-11-05T08:05Z) both print `exit=1 reason=stale-accept live=3 baseline=0`: 8 stale accept rows (`not-a-gap`/`anchor-not-live` on `apps/web-platform/scripts/{plugin-root-sandbox-propagation-probe.mjs,sandbox-canary.mjs,package.json}`) + 3 live pairs (`plugins/soleur → scripts/sentry-issue.sh`, `tests/hooks/emissions → scripts/{betterstack-query.sh,sentry-issue.sh}`, all referenced from `plugins/soleur/test/components.test.ts:987-992`, test-vector strings added by #12061/f212785434). Issue #12110 tracks it; fix PR #12128 (branch `feat-one-shot-12110-accept-anchor-repin`, currently init-commit-only) is in flight — see Phase 0.3. Cited artifacts verified on disk: tasks.md §Phase 4 + Verification; ADR-276 `### Stage status` (:39-65) + amendment items 5(d) (:534) and 10 (:539); replay.py arms (:2015-2102), `RATCHET_ORACLE` (:1758), docstring BASELINE STATE (:151-153); test rows (:2260-2339 fixtures, :2473-2482 rows, :2872-2908 chks, :4883-4898 mutants); `.gitattributes:2`; `inngest-probe-row.test.sh` (grep: ZERO baseline references — the :143 ALLOW row is `scripts/lib/test-affected-paths.sh`, verify-only); observation probe ORACLE parity row (:85-87); runbook §7 (:153-307); `RUNNER_TRIGGERS` = `("scripts/test-all.sh", "scripts/lib/test-affected-paths.sh")` (:934) — this PR touches neither. `scripts/ci-pr-affected-preactivation.sh` verified zero baseline coupling (parent decision-challenges row 16).

**Property list** (Phase 0.6b): (1) the baseline file is absent from the tree; (2) a baseline present at HEAD while absent at base exits 1 unconditionally — content-independent, live-independent; (3) the strict-zero verdicts (absent/absent pass, planted gap → new-pair, deleted-while-live → exit 1, reintroduced → exit 1) are pinned by rows and mutant kills; (4) every reference to the retired file is updated or verified; (5) `oracle-inputs-changed` still fires on a re-add; (6) the closing ADR line, runbook, and drain close-out land; (7) holds unchanged.

**Cut list.** None — the ask names no new mechanism; the reintroduced arm is an arm of the EXISTING ratchet (ADR-276 item 5(d) already mandates it), `--print-baseline`/`--baseline` machinery stays, and every sweep item is a verify-or-delete on artifacts that exist. No new scripts, gates, CI jobs or files are planned.

**Machinery map (verified against `f06b595420`).** `ratchet_run` findings order: `unaudited` → `star-row` → `stale-accept` → `new-pair`/`baseline-deleted` → `stale-line` → `baseline-dup` → `baseline-order` → `grown`; the marker names `findings[0]`. `baseline_split(None)` → `([], True)`; `baseline_at` at base returns `""` for the empty blob (base PRESENT). Fixture `adopt` = base absent/head present with `bl-ok.tsv` + `bl-empty.tsv`; `del` = base present/head absent; `none` = absent/absent. `rt_p_weak` appends a helper that reports base=HEAD, baseline=None — the "adoption" spoof that now yields `baseline-reintroduced` if it ran.

**Accept-row census.** 42 rows key `scripts/ci-affected-audit.baseline.tsv`'s path column (14×3 across the `-a`/`-b`/`-c` replay labels, all kind `false-positive: --rows arm … fixture-write/name token`) — deletion orphans them; same-commit removal is mandatory (they are `not-a-gap` rows; no replacement needed).

**Learnings applied:** `2026-10-31-accept-row-reasons-must-enumerate-real-tree-read-arms`; `2026-11-03-one-malformed-accept-row-reason-drops-every-exemption`; `2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree` (verify on the merged tree); the PR5a self-redirect trap (`--print-baseline > file` truncates before reading — tmpfile+`mv`, moot post-deletion but the live-listing use keeps the pattern); series decision-challenges rows 5 (deletion+arm in one commit), 8 (gitattributes + probe fixture), 15 (`RATCHET_BASELINE` stays in `RATCHET_ORACLE`), 16 (preactivation zero coupling).

**Skipped gates (recorded so review does not re-litigate):** GDPR — no regulated-data surface, none of (a)-(d) (receipts stay in-repo; no new distribution surface). IaC — no infrastructure. Encryption Posture — no store/connection. Task Design — no new autonomous-task surface (the `affected-index-ratchet` job exists; comment only). External research — fully local, series-documented machinery. SpecFlow + advisor consult + research/domain fan-outs — no Task/Agent tool in this subagent; all analysis ran inline (recorded in Domain Review).

## Implementation Phases

**Phase 0 — claim, stamp, measure, coordinate (before any edit).**

- [ ] 0.1 `gh pr list --label s4-drain --state open` → empty → `gh pr edit 12127 --add-label s4-drain` + mirror comment on #10448 naming the slice.
- [ ] 0.2 `git fetch origin main`, rebase onto it, record `BASE=$(git rev-parse origin/main)` + `date -u` in `receipts/measurement-stamp.txt`; mkdir the spec `receipts/` dir.
- [ ] 0.3 **Red-gate.** `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv --all-refs > receipts/audit-all-refs.txt` and `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main > receipts/ratchet-initial.txt`. Expected at plan time: `stale-accept`, `live=3` (main red — #12110). If red: `gh pr view 12128 --json state` — MERGED → rebase and re-measure; OPEN and progressing → do NOT duplicate the repin: either sequence this slice after it, or absorb only the residual it does not cover (delete the stale rows it leaves + classify the 3 drift pairs per the drain rubric — `expect(...).toEqual` string vectors ⇒ mention-class accept rows, e.g. `data row not fed to a read loop`) — record the choice + rationale in `receipts/drift-disposition.tsv` and on the #10448 mirror. The strict-zero assertions in Phase 1 cannot run while the tree is red.
- [ ] 0.4 `receipts/live-pairs.tsv` + `receipts/pairs-decisions.tsv` for any residual pairs absorbed under 0.3.

**Phase 1 — the deletion commit (ONE commit: machinery + tests + file + rows + gitattributes).**

- [ ] 1.1 Re-assert on the final tree (post-0.3): `audit --accept` exits 0 `gap_suites=0 unaudited=0 stale=0`; `ratchet --base origin/main` `reason=pass live=0 baseline=0` (task 4.1 — the `baseline-deleted` arm requires live empty, and it is).
- [ ] 1.2 `scripts/ci-pr-affected-replay.py`: insert the `baseline-reintroduced` arm immediately before `if new and head_text is None and base_text is not None:` (:2058) — fires whenever `head_text is not None and base_text is None`, unconditionally; update the docstring RATCHET section (:136-166): BASELINE STATE first sentence, the verdict list (:148-150), "(adoption, deletion)" (:140), and the `--print-baseline` paragraph's regeneration framing (:157-159) to the live-listing role.
- [ ] 1.3 `git rm scripts/ci-pr-affected-audit.baseline.tsv`; remove `.gitattributes:2` (`scripts/ci-pr-affected-audit.baseline.tsv text eol=lf linguist-generated=true`).
- [ ] 1.4 Delete the 42 orphaned accept rows (`awk -F'\t' '$2 == "scripts/ci-pr-affected-audit.baseline.tsv"'` — 14 per `-a`/`-b`/`-c` label); keep the file C-locale sorted with its 2 header comments; re-run `audit` → `stale=0`.
- [ ] 1.5 Test-file rework per Technical Considerations: `row_rt_adopt`/`row_rt_adopt_unequal` → reintroduced rows (rename allowed — update the chk references :2899-2900); `rt_p_weak` comment; `row_rt_helper_pr_tree_ignored` comment; new mutants; keep grown/stale/dup/order rows and machinery (decision recorded — the arms stay reachable via `--baseline`/stale base).
- [ ] 1.6 Same-commit verification: `python3 -m py_compile scripts/ci-pr-affected-replay.py`; replay suite rows for the state table + new mutants green; `ratchet --base origin/main` on the commit → `reason=pass live=0 baseline=0`, and `oracle-inputs-changed` prints naming the baseline path (expected ONCE — record in the body).

**Phase 2 — sweep (task 4.5).**

- [ ] 2.1 `.github/workflows/ci.yml` :398-416 comment block → strict-zero wording (the live set must be empty; the baseline is retired; a re-added file exits 1 `baseline-reintroduced`). Job name, `if:`, `continue-on-error`, `permissions`, `fetch-depth`, env, step name — all untouched.
- [ ] 2.2 Verify `RATCHET_BASELINE` still in `RATCHET_ORACLE` (:1758) and the probe parity row (`ratchet-observation-window-10865.sh:85-87`) still lists the path; run the probe's baseline-absent-at-tip test rows (`row_ow_*` in the replay suite — they run under stub gh).
- [ ] 2.3 `grep -n "baseline" scripts/lib/inngest-probe-row.test.sh` → assert still zero hits (verified at plan time; re-verify — the :143 ALLOW row is `scripts/lib/test-affected-paths.sh`, untouched). `scripts/ci-pr-affected-preactivation.sh` — re-grep, expect zero coupling.
- [ ] 2.4 Residual-reference sweep: `grep -rln "ci-pr-affected-audit.baseline" --include="*.sh" --include="*.py" --include="*.yml" --include="*.ts" . | grep -v node_modules | grep -v archive` — every remaining hit must be one of: replay.py (constant/help/oracle), the test suite fixtures, the observation probe, the runbook/ADR (history sections stay accurate or are rewritten in Phase 3), accept.tsv (zero after 1.4). `scripts/test-affected-kb-consumers.baseline.txt` — check for a row naming the deleted file; regenerate if moved.

**Phase 3 — docs (tasks 4.6+4.7).**

- [ ] 3.1 ADR-276 `### Stage status`: append `- <date> S4 index completion PR5z strict zero (#10861, PR #12127): the baseline file deleted and the adoption arm removed (amendment item 5(d)); audit exits 0, ratchet strict; replay and go/no-go re-ruling pending` — append-only, dated at work time.
- [ ] 3.2 Runbook `ci-pr-affected-activation.md` §7 strict-zero rewrite: failure table — retire `stale-line`, `baseline-dup`, `baseline-order`, `grown` and the adoption mention; add `baseline-reintroduced`; keep `baseline-deleted` (still reachable on stale bases); drop the "only the strict-zero end state may delete it" clause (fulfilled); §7 intro (:155-158) to strict-zero wording; `--print-baseline` reframed as the live-pair listing (:227-228 incl. retiring the PR3a-adoption paragraph and the adoption-arm hole sentence); baseline-conflict recipe (:230-241) retired; drain claim (:245-249) and completion schedule (:251-253) marked fulfilled; "A revert is not a clean rollback" (:268) updated (a revert now re-adds the file → permanent `baseline-reintroduced`); rollback recipe (:295-302) updated; observation log gets a dated deletion entry; "baseline absent at the tip is the end state and fine" (:279) confirmed-still-true.

**Phase 4 — verify + battery (task 4.8).**

- [ ] 4.1 `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` (full suite — state table, text, `--print-baseline`, oracle, workflow, observation-window rows, all mutants); `bash scripts/test-affected-kb-consumers.test.sh`; `bash scripts/lib/inngest-probe-row.test.sh`; `shellcheck` on edited shell; `python3 -m py_compile`.
- [ ] 4.2 Final-tree assertions: `test ! -f scripts/ci-pr-affected-audit.baseline.tsv`; `audit --accept` → exit 0, `gap_suites=0 unaudited=0 stale=0`; `ratchet --base origin/main` → `exit=0 reason=pass live=0 baseline=0`; `grep -n "audit exits 0, ratchet strict" knowledge-base/engineering/architecture/decisions/ADR-276-*.md` matches; `grep -n PR_AFFECTED_LOCKED scripts/ci-pr-selection.sh` matches; `gh api repos/jikig-ai/soleur/variables/CI_PR_AFFECTED` → 404.
- [ ] 4.3 Whether the local `--affected` gate degrades is measured at work time (no `RUNNER_TRIGGERS` file is touched); CI `test` context is the merge gate either way.

**Phase 5 — close-out (task 4.9).**

- [ ] 5.1 PR body: the marker + audit line, `wc -l` of accept.tsv, the same-commit set, the oracle-notice-once disclosure, `receipts/` links, `Closes #10861`.
- [ ] 5.2 Post-merge/close: #10861 comment with `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=0 baseline=0`, the audit line, per-slice links (#11226/#11950/#12050/#12093/#12116/#12127); `s4-drain` label released from the PR (and noted — the probe floor falls back to sentinel #11226, the conservative direction); mirror comment on #10448.

## Files to Edit

- `scripts/ci-pr-affected-replay.py` — the `baseline-reintroduced` arm (:2058 area), RATCHET docstring (:136-166); `RATCHET_BASELINE`/`RATCHET_ORACLE`/`--baseline`/`--print-baseline`/present-present arms all kept
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` — state-table rows (:2473-2474 reworked), `rt_p_weak` comment (:2285), chk texts (:2899-2900, :2970), mutants (:4883-4898 kept + ~3 new), re-verify :2860-2864 classification rows
- `scripts/ci-pr-affected-audit.accept.tsv` — delete the 42 baseline-keyed rows (C-locale order preserved)
- `.github/workflows/ci.yml` — `affected-index-ratchet` job comment only (:398-416)
- `.gitattributes` — delete line 2
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` — §7 strict-zero rewrite + observation-log entry
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` — one dated line under `### Stage status` (:65 after)
- `scripts/test-affected-kb-consumers.baseline.txt` — only if the file's rows move (verify; expected unchanged)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10861-pr5z-strict-zero/tasks.md` — task breakdown
- `knowledge-base/project/specs/feat-one-shot-10861-pr5z-strict-zero/decision-challenges.md` — the `| Item | Class | Ruling |` table (reintroduced-token name, keep-machinery ruling, #12128 coordination, label-release ordering)
- `knowledge-base/project/specs/feat-one-shot-10861-pr5z-strict-zero/session-state.md` — session log (series convention)
- `knowledge-base/project/specs/feat-one-shot-10861-pr5z-strict-zero/receipts/` — `measurement-stamp.txt`, `audit-all-refs.txt`, `ratchet-initial.txt`, `live-pairs.tsv`, `pairs-decisions.tsv`, `drift-disposition.tsv` (if 0.3 absorbs residual), final-verify outputs

(No product code files are created; `scripts/ci-pr-affected-audit.baseline.tsv` is deleted.)

## Guard Contract

### Guard 1 — baseline-state table, strict-zero arm (`ratchet` in `scripts/ci-pr-affected-replay.py`)

**Property.** A baseline file present at HEAD while absent at the judged base exits 1 unconditionally — the retired baseline can never be re-adopted, whatever its content and whatever the live set.

**Assembly.** The single chokepoint `ratchet_run`'s findings construction (replay.py:2044-2075) — every `ratchet` run, every `--baseline` path and every base resolves through it; the state inputs are `head_text` (`ratchet_read`, confined reader) and `base_text` (`ratchet_base` → merge-base copy of `lint-ratchet.py.baseline_at`). The `oracle-inputs-changed` notice (`ratchet_oracle`, :1898) is the secondary surface pinned by `RATCHET_BASELINE ∈ RATCHET_ORACLE`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `scripts/ci-pr-affected-audit.baseline.tsv` on a base that lacks it, content equal to the live set | RED (`baseline-reintroduced`; adoption no longer exists) |
| 2 | Re-add the file EMPTY on a base that lacks it | RED (`baseline-reintroduced` — content-independent) |
| 3 | Guard's own dispatch removed: `if head_text is not None and base_text is None:` → `if False:` | RED (mutant `ratchet-reintroduced-tolerated` killed by the reintroduced row) |
| 4 | Second member: a re-added file whose FIRST line alone would satisfy live-equality but which carries a second non-live line | RED (`baseline-reintroduced` — presence, not line 1, is judged) |
| 5 | Weaken to `head_text` (truthiness) instead of `is not None` | RED (empty re-add escapes → killed by the `bl-empty.tsv` arm) |
| 6 | Harness row: reintroduced row additionally asserts `! grep -q '^grown' <<<"$ROUT"` | kills the `ratchet-adoption-refused` mutant (grown-guard widening) |
| 7 | must-PASS (non-canonical compliant input): baseline absent at both base and HEAD with an empty live set on a custom `--baseline` fixture path | PASS (`reason=pass live=0 baseline=0`) |

### Guard 2 — oracle coverage survives the deletion (`RATCHET_BASELINE ∈ RATCHET_ORACLE`)

**Property.** A diff that re-creates or edits the baseline path always prints the non-blocking `oracle-inputs-changed` notice.

**Assembly.** `RATCHET_ORACLE` (replay.py:1758) → `ratchet_oracle(touched, rel)` (:1898) → the notice emitters (:2029, :2095); the observation probe's `ORACLE` parity row (`ratchet-observation-window-10865.sh:85-87`) asserts the same list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `RATCHET_BASELINE` from `RATCHET_ORACLE` | RED (the probe's parity row / `row_ow_*` oracle rows fail) |
| 2 | A diff that re-adds the baseline path | notice printed naming the path (Guard 1 also reddens — belt and suspenders) |
| 3 | Second member: a diff touching TWO oracle inputs (baseline + replay.py) | notice names BOTH, not just the first |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "assert strict zero on the final tree (audit exits 0, gap_suites=0 unaudited=0 stale=0; ratchet --base origin/main reports live=0)" | Phase 0.3, 1.1, 4.2 | mapped |
| 2 | "delete `scripts/ci-pr-affected-audit.baseline.tsv` — it is now a tracked EMPTY blob on main" | Phase 1.3 | mapped |
| 3 | "remove the baseline adoption arm in `scripts/ci-pr-affected-replay.py` (ADR-276 item 5(d)) in the SAME commit as the deletion — a baseline present at HEAD while absent at base exits 1 unconditionally; update `ratchet --help` BASELINE STATE text and failure table" | Phase 1.2, 1.3; Phase 3.2 | mapped |
| 4 | "strict-zero test updates in `plugins/soleur/test/ci-pr-affected-replay.test.sh` (retire/rework baseline-only rows …; add strict-zero rows … plus mutant kills)" | Phase 1.5; Guard Contract 1 | mapped |
| 5 | "sweep: remove `.gitattributes` linguist-generated line … check `scripts/lib/inngest-probe-row.test.sh` fixture row, verify `scripts/followthroughs/ratchet-observation-window-10865.sh` still passes, KEEP `RATCHET_BASELINE` in `RATCHET_ORACLE` … update the `affected-index-ratchet` job comment in `.github/workflows/ci.yml` (comment only)" | Phase 1.3, 2.1-2.4; Guard Contract 2 | mapped |
| 6 | "ADR-276 `### Stage status` closing dated line" | Phase 3.1 | mapped |
| 7 | "runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` updates (retire baseline failure-table rows, add strict-zero rows, update drain instructions, observation log, drop the 'only the strict-zero end state may delete it' clause)" | Phase 3.2 | mapped |
| 8 | "close-out: #10861 comment with final marker, release `s4-drain` label, mirror comment on #10448" | Phase 5 | mapped |
| 9 | "claim = label on the draft PR + mirror comment on #10448; `gh pr list --label s4-drain --state open` already verified empty" | Phase 0.1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/ci-pr-affected-replay.py` arm + docstring | "remove the baseline adoption arm … exits 1 unconditionally; update `ratchet --help` BASELINE STATE text and failure table" | asked |
| `plugins/soleur/test/ci-pr-affected-replay.test.sh` | "strict-zero test updates … retire/rework baseline-only rows … add strict-zero rows … plus mutant kills" | asked |
| `git rm` baseline file | "delete `scripts/ci-pr-affected-audit.baseline.tsv`" | asked |
| `scripts/ci-pr-affected-audit.accept.tsv` row deletion (42 rows) | — | inferred — the rows go `stale` (`path-untracked`/`not-a-gap`) the instant the file is deleted; task 4.1's `stale=0` assertion cannot hold on the deletion commit without removing them in the same commit |
| `.gitattributes` | "remove `.gitattributes` linguist-generated line for the deleted file" | asked |
| `.github/workflows/ci.yml` comment | "update the `affected-index-ratchet` job comment in `.github/workflows/ci.yml` (comment only)" | asked |
| Runbook + ADR-276 | "runbook … updates" / "ADR-276 `### Stage status` closing dated line" | asked |
| Spec dir (tasks/decisions/session-state/receipts) | "spec dir `knowledge-base/project/specs/feat-one-shot-10861-pr5z-strict-zero/` with spec.md, tasks.md, decision-challenges.md" + series receipts convention | asked |
| `test-affected-kb-consumers.baseline.txt` conditional | "`test-affected-kb-consumers.test.sh`" in task 4.8 + sweep | asked |
| Phase 0.3 drift-coordination arm | — | inferred — measured at plan time: `origin/main` is red `stale-accept live=3` (#12110, fix PR #12128 in flight); the strict-zero assertion cannot pass while red; the runbook's repair-owner rule + the drain claim make absorbing legitimate when the sibling fix is stalled |

### Split Assessment

- Subsystems touched: 3 — `scripts/`, `plugins/soleur`, `knowledge-base/` (plus `.github/` + `.gitattributes` single-file edits)
- Planned files: ~9 edited + ~5 spec artifacts | Estimated changed lines: ~400-700 (dominated by the runbook rewrite and test-file rework; the replay.py diff is ~30 lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — task 4.2/4.3 fix the deletion and arm removal to one commit; the docs/test/sweep items are inseparable from it (the suite must stay green per commit and the ADR/runbook record the same end state)

## Acceptance Criteria

- [ ] `test ! -f scripts/ci-pr-affected-audit.baseline.tsv` on the merged tree.
- [ ] `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv` → exit 0, `gap_suites=0 unaudited=0 stale=0`.
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` → `exit=0 reason=pass live=0 baseline=0`.
- [ ] A re-added baseline file (any content, incl. empty) on a base that lacks it exits 1 `baseline-reintroduced` — proven by the reworked `adopt`-fixture rows (contentful and empty arms).
- [ ] `baseline-deleted` while live → exit 1; absent/absent with a planted gap → `new-pair`; absent/absent with empty live → pass — all pinned by suite rows.
- [ ] The 42 accept rows keyed on the baseline path are removed; `awk -F'\t' '$2=="scripts/ci-pr-affected-audit.baseline.tsv"' scripts/ci-pr-affected-audit.accept.tsv` is empty and the file stays C-locale sorted.
- [ ] `git rm` + arm removal + test rework + `.gitattributes` + accept-row deletion land in ONE commit.
- [ ] `RATCHET_BASELINE` remains a member of `RATCHET_ORACLE`; the deletion commit's ratchet run prints `oracle-inputs-changed` naming the path exactly once (recorded in the body).
- [ ] `.gitattributes` has no line for the deleted file; the `affected-index-ratchet` job's name/`if:`/`continue-on-error`/`permissions`/step-name are byte-identical pre/post (comment-only diff).
- [ ] `grep -n "audit exits 0, ratchet strict" knowledge-base/engineering/architecture/decisions/ADR-276-*.md` matches the appended dated line.
- [ ] Runbook §7 reads the strict-zero state: failure table carries `baseline-reintroduced` and drops stale-line/dup/order/grown/adoption rows; `--print-baseline` documented as the live-pair listing; the "only the strict-zero end state may delete it" clause is gone; observation log has the deletion entry.
- [ ] Replay suite fully green incl. new mutants; `test-affected-kb-consumers.test.sh`, `inngest-probe-row.test.sh`, observation-window rows, shellcheck, `py_compile` all pass.
- [ ] Holds: `grep -n PR_AFFECTED_LOCKED scripts/ci-pr-selection.sh` matches; `gh api repos/jikig-ai/soleur/variables/CI_PR_AFFECTED` → 404; no `CI_PR_AFFECTED`, no lock removal, no PR3b, no PR D in the diff.
- [ ] `gh pr list --label s4-drain --state open` shows only #12127 throughout; post-merge the label is released and #10861 + #10448 carry the close-out comments.

## Test Scenarios

- Given a fixture repo whose base lacks the baseline and whose HEAD adds it with content equal to live (`adopt` fixture), when `ratchet` runs, then exit 1 `baseline-reintroduced` — and with an EMPTY file likewise (unit — `rt_in std|good adopt 1 baseline-reintroduced`).
- Given a base that has the baseline and a HEAD that deletes it while pairs are live (`del` fixture + `L-std`), when `ratchet` runs, then exit 1 `baseline-deleted` (existing `row_rt_deleted`, kept).
- Given absent at both with an empty live set (`none` fixture + `L-good`), when `ratchet` runs, then exit 0 `reason=pass live=0 baseline=0` (existing `row_rt_absent_both_clean` + `row_rt_deleted_end`).
- Given absent at both with one live pair, when `ratchet` runs, then exit 1 `new-pair` (existing `row_rt_absent_both`).
- Given the mutants: dispatch removed (`if False:`), truthiness weakening (`head_text`), live-gated re-admission, grown-guard widening — when each `mutate` arm runs, then the named kill row fails (unit — the suite's own `mutate` harness).
- Given a diff re-adding the baseline path, when the ratchet runs, then `oracle-inputs-changed` names it (integration — oracle rows + probe parity row).
- Given the deletion commit itself, when `audit --accept` runs, then `stale=0` — the 42 orphaned rows were removed in the same commit (integration — the audit).
- Given #12128 merges first, when Phase 0.3 re-measures, then the tree is green and the residual-drain arm is skipped; given #12128 still open, when the implementer absorbs only uncovered residual, then `receipts/drift-disposition.tsv` records each pair's disposition (procedural — receipt review).

## Success Metrics

- `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=0 baseline=0` on the merged tree.
- `test ! -f scripts/ci-pr-affected-audit.baseline.tsv` — the file is gone, the arm is gone, the state table is strict.
- A re-added file can never adopt: `baseline-reintroduced` exit 1, proven by suite rows and mutant kills.
- The drain claim is released; #10861 closes with the final marker and per-slice links.

## Dependencies & Risks

- **Main is red right now** (`stale-accept live=3 baseline=0`, #12110; fix PR #12128 in flight): the strict-zero assertion cannot be made until green. Phase 0.3's coordination arm (sequence-after vs absorb-uncovered-residual) is the control; never duplicate the repin. A stale-base `baseline-deleted`/`baseline-reintroduced` surprise on the merge ref is re-measured per rebase.
- **42 orphaned accept rows:** forgotten same-commit removal makes the deletion commit itself red `stale-accept` — the AC pins the awk census.
- **Marker precedence:** placing the reintroduced arm first in findings order is load-bearing for the `ratchet-adoption-refused` kill — the row must also assert no `^grown` line (the mutant is invisible to the token alone).
- **Fixture rot:** rows :2860-2864 classify the baseline path string (`is_doc_path`/`is_trigger_path`) — verify they still assert a real classification post-deletion, not a vacuous pass on a nonexistent file.
- **Probe parity:** `RATCHET_ORACLE` and the probe's `ORACLE` list must stay byte-equal; keep both.
- **Step-name coupling:** the observation probe keys on `STEP="Ratchet the audit against the committed baseline"` — renaming the `ci.yml` step would break the probe; comment-only edit.
- **Label-release ordering:** removing `s4-drain` before merge would un-claim mid-slice; after merge it regresses the probe floor to sentinel #11226 (conservative). Release post-merge only.
- **`s4-drain` singleton:** the label list must contain only #12127 for the whole slice; a second drain PR collides on the same files.

## Open Code-Review Overlap

None — open `code-review` issues queried 2026-11-05; zero bodies name any planned file. (Sibling in-flight coordination — NOT a code-review overlap but recorded here: PR #12128 `feat-one-shot-12110-accept-anchor-repin` fixes the same machinery's `stale-accept` red on main; PR #12103 `affected-gate-reprice` is planning-only so far. Sequencing is handled in Phase 0.3.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI-internal check machinery + docs. Technical ruling items (reintroduced token name, keep-machinery call, #12128 coordination, label-release ordering) route to `soleur:engineering:cto` per the technical-ruling delegation rule; this run has no Agent tool, so they are recorded as `pending - assumed` rows in `decision-challenges.md` for the work phase to settle or escalate. The brainstorm-domain fan-out, SpecFlow pass (plan Phase 3), scoped advisor consult (Phase 4.5) and plan-review panel could not be spawned without the Task tool — all analysis ran inline in this session and is recorded here for the reviewers.

## References & Research

- Parent plan: `knowledge-base/project/plans/archive/20261103-165953-2026-11-03-feat-one-shot-10861-pr5-strict-zero-plan.md` §D1-D5; canonical tasks `knowledge-base/project/specs/archive/20261103-165953-feat-one-shot-10861-pr5-strict-zero/tasks.md` §Phase 4 + Verification; decision-challenges rows 5, 8, 15, 16, 17; session-state (prune mechanics, `--print-baseline` self-redirect trap).
- ADR-276: `### Stage status` (:39-65), amendment item 5(d) (:534), item 9 PR3b entry conditions (:538), item 10 (:539).
- Machinery: `scripts/ci-pr-affected-replay.py` (:136-166 docstring, :1748-1758 constants, :1868-1951 helpers, :1994-2102 `ratchet_run`, :2514-2521 argparse); suite `plugins/soleur/test/ci-pr-affected-replay.test.sh` (:2260-2339 fixtures, :2473-2482 rows, :2868-2912 chks, :4880-4898 mutants); `scripts/followthroughs/ratchet-observation-window-10865.sh` (:85-89 oracle/step/baseline constants, :476-512 the (h) arm); runbook §7 (:153-307); `.github/workflows/ci.yml` (:398-444).
- Live evidence: `affected-index-ratchet` job logs, merge_group runs 41943389794 (on `f06b595420`) and 41991683080 — `exit=1 reason=stale-accept live=3 baseline=0`; issue #12110; PR #12128.
- Merged siblings: #11226, #11950, #12050, #12093, #12116 (PR5d body — disposition records + receipts dir layout).

## Out of scope / Holds

- No `CI_PR_AFFECTED` variable, no activation-lock removal (`PR_AFFECTED_LOCKED` stays), no PR D (#10414), no PR3b (#10859), no ruleset change, no flip PR, no evidence re-run, no new `AFFECTED_*` edges or always-on entries.
- No new drain machinery: `--print-baseline`, `--baseline`, `RATCHET_BASELINE`, `RATCHET_ORACLE`, the present/present arms, `baseline-deleted` all stay.
- No replay/ejections/go-no-go re-ruling — the ADR line records it as pending (that is entry condition 3 for a re-attempt, not this slice).
- No step-name/job-name/`required-checks.txt` edits in `ci.yml`; no probe edits; no `inngest-probe-row.sh` edits; no `ci-pr-affected-preactivation.sh` edits.
- The issue's mirror bookkeeping (#10448) is comment-only; the `s4-drain` label moves nowhere else — it is released, not transferred.
