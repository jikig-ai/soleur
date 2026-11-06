# Review — git-history-analyzer — PR #12127 (feat-one-shot-10861-pr5z-strict-zero)

Seat: `soleur:engineering:research:git-history-analyzer`. Scope: `git diff origin/main...HEAD` (22 files, +587/−90), HEAD `79db88e18b`, merge-base `fc36ec95ad` (the #12128 squash-merge — sequence dep satisfied in-tree, not just by ordering). Report-only; no worktree mutation; no mutants were re-run (suite-c v2 green receipt at `receipts/suite-c-arm-v2.rc` = 0).

## Git-history trace

- `scripts/ci-pr-affected-audit.baseline.tsv` lineage: 1,510 lines at `47232ed180` (oracle regen) → 239 (`153f58d13c`, PR5a #11950) → 235 (`6422ccfbca`) → 22 (`ad644215cc`, PR5b #12050) → 0 (`f06b595420`, PR5d #12116) → deleted here. Runbook's "empty since the PR5d merge" is accurate; the deleted blob is genuinely empty on `origin/main` (0 bytes).
- Adoption arm origin: `45f0b096ff` (PR3a #10851, 2026-10-22) introduced "adoption, passes when live equals"; `baseline-deleted` token same commit. ADR-276 5(d) scheduled the arm's removal at deletion time — this PR executes it.
- Token history: `baseline-reintroduced` was prefigured in #11950's KB (tasks.md 4.3: "`baseline-reintroduced` or the named reason"); first code use is this PR. No collision.
- #12070 (`2e0593a3aa`) landed `codeql-to-issues-sweep-wiring.test.sh` while this branch queued; the suite reads `.github/workflows/codeql-to-issues.yml` (line 25 `WF=`→`check_wf`/`sed` mutants — a real read). Undeclared → live pair post-rebase; `AFFECTED_PLUGINS_SOLEUR_TEST_CODEQL_TO_ISSUES_SWEEP_WIRING_TEST_SH_PATHS` (test-affected-paths.sh:519-523) closes it. `receipts/audit-final.txt` `gap_suites=0 stale=0` and `drift-disposition.tsv` row 3 corroborate.
- The 42 accept rows (14×3 over `ci-pr-affected-replay-{a,b,c}`) key on the baseline path; replay.py's `path-untracked` stale class makes them `stale-accept` the instant the file is untracked — same-commit removal was mandatory, not cosmetic. Post-diff, `accept.tsv` has zero `baseline.tsv` refs; removal count = 42 data rows exactly.
- `DECLARED_TOTAL=599` verified against 473 `^mutate ` + 126 `^ow_mutate ` call sites; the +3 mutants are `ratchet-reintroduced-{tolerated,live-gated,content-weakened}`; arm ranges 1-193/194-386/387-599 tile without overlap.
- `ratchet-observation-window-10865.sh:497-498` was pre-hardened for this PR: baseline absent at main tip → `: > bl.tip; rc=0` → `grew=0` ("absent at the tip is the end state (PR5 deletes it)"). No followthrough breakage. `STEP=` literal at :88 is why the ci.yml step name stays byte-identical — ruling verified against the probe, not just asserted.
- `RATCHET_BASELINE` retained in `RATCHET_ORACLE` (replay.py:1748,1758): a re-added file is both `baseline-reintroduced` and an oracle touch — consistent.
- No external validator enumerates verdict tokens (searched: only replay.py, its test, the probe's `MARKER_RE` `[a-z0-9-]+`, ci.yml's sed `reason=\([a-z0-9-]*\)` — all accept the new token by shape).

## Settled rulings — all verified in-tree, no dissent

1. Token `baseline-reintroduced` — replay.py:2058-2060.
2. Present/present `--baseline` machinery kept — grown/stale/dup/order arms intact (:2070-2084); runbook collapses them into one caveat row.
3. Arm before the new-pair block — :2058 precedes `baseline-deleted`/`elif new`; marker names `findings[0]` (:2104). `elif` chain keeps new-pair detail co-firing.
4. `! grep -q '^grown'` on the contentful row — test.sh:2473. Mechanism verified: `ratchet-adoption-refused` (:4889) widens grown's guard to fire base-absent → `grown` entries append after `baseline-reintroduced` → identical marker, only absent-grown grep discriminates.
5. Sequence-after-#12128 — `git merge-base` = `fc36ec95ad` is ancestor of HEAD; residual absorbed per `drift-disposition.tsv` (main was red `stale-accept live=3` pre-#12128 per `ratchet-initial.txt`; now clean).
6. s4-drain release post-merge — declared in spec §Close-out and runbook; a post-merge act, nothing in-diff contradicts.
7. One commit — `ab487915f1` = rm + arm + docstring + test rework + `.gitattributes:2` + 42 rows + range bump, exactly per ruling.
8. ci.yml step name byte-identical — only the comment block (:397-406) edited.

Self-application check: this PR's own ratchet run sees base-present (empty blob at `fc36ec95ad`)/HEAD-absent with live=0 → the "strict-zero end state" pass path. Correct.

## Findings

- **P3** `scripts/ci-pr-affected-replay.py:136-137` — the RATCHET docstring's opening still teaches the retired contract: "the live gap set ... must EQUAL a committed, shrink-only baseline" and "green on a tree whose audit exits 1". Under strict zero there is no committed baseline, and ratchet-green ⟺ audit-green (every audit exit-1 cause — gaps, unaudited, stale rows — is mirrored as a ratchet finding). The BASELINE STATE paragraph (:151) and `--print-baseline` text (:157, argparse help :2523) were updated; the framing sentence was not, so the docstring contradicts itself within five lines.
- **P3** `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §7 intro — "The audit exits 1 on `main` today (the committed baseline holds whatever `wc -l scripts/ci-pr-affected-audit.baseline.tsv` reports, ...), so a check that simply required the audit to pass could never be green" survives the rewrite. Post-merge there is no file to `wc -l` and the audit exits 0; the sentence is self-contradictory and fights the strict-zero clause appended in the same paragraph.
- **P3** `scripts/ci-pr-affected-replay.py:2092-2097` — the generic remedy tail (`delete the offending line(s) ... then run: --print-baseline > <rel>.new && mv`) fires whenever `stale-line`/`baseline-dup`/`baseline-order`/`grown` co-fire — which is the *common* shape of a re-add (any non-trivial re-added file has non-live lines). Output then carries both "delete <rel> — a re-added baseline never adopts" and a recipe that re-creates the file and re-trips the arm. Marker and first remedy stay correct; consider gating/rewriting the tail when `baseline-reintroduced` ∈ `names`. (CTO row 11's dissent covered marker precedence for co-firing verdicts but not this remedy-text contradiction.)
- **P3** `plugins/soleur/test/ci-pr-affected-replay.test.sh:2970` — chk string still reads "a PR-tree helper that always reports adoption changes no verdict"; `rt_p_weak`'s own comment at :2285 was updated to "baseline-reintroduced" but the chk label was missed. Same stale-token family: `.github/workflows/ci.yml:400` comment says "green on a tree whose audit exits 1" (pre-strict-zero framing).
- No P1/P2.

## Dissent notes

None. All eight settled rulings verified against the tree and against the mechanisms they cite (probe `STEP=` literal, `path-untracked` staleness, marker `findings[0]`). One observation beyond the rulings: `session-state.md` names pre-rebase SHAs (`c09185c5e0`, `49a7b7f623`) that no longer exist in the branch (rebase rewrote them to `ab487915f1`, `12f4861b72`) — internal bookkeeping only, not a defect.

## Summary

PR #12127 cleanly executes the S4 strict-zero end state: the baseline (drained 1,510→0 lines across PR5a/5b/5d) is deleted in the same commit as the `baseline-reintroduced` arm that replaces the PR3a adoption bootstrap, the 42 mechanically-orphaned accept rows, and the `.gitattributes` line. History confirms every settled ruling: the arm's placement preserves marker precedence while new-pair detail co-fires, the `!grown` assertion is the only discriminator that keeps `ratchet-adoption-refused` killed, the #12128 sequence dep is satisfied in the tree itself (merge-base `fc36ec95ad`), and the observation probe was already written for absent-at-tip. The new `codeql-to-issues` edge absorbs a real gap left by #12070's queue merge, with `audit-final` showing `gap_suites=0 stale=0`. Findings are four P3 doc/output polish items: two stale "green on audit-exits-1 / EQUAL a committed baseline" framings (docstring intro, runbook §7 intro, ci.yml comment), a generic remedy tail that contradicts the reintroduced remedy on the common co-fire, and one stale "adoption" chk label. Nothing blocks.
