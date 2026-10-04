# Tasks: recorder evidence for three unevidenced suites (umbrella #9307, section 2)

Plan: `knowledge-base/project/plans/2026-10-04-chore-recorder-evidence-for-three-unevidenced-suites-plan.md`

## Phase 0 -- baseline

- 0.1 Confirm worktree, note `bash plugins/soleur/skills/ship/scripts/battery-owed.sh` for the end (rc 42 = skippable)
- 0.2 Registration check: `bash scripts/test-all.sh --enumerate-commands all | grep -c -F -e 'scripts/audit-suite-reads' -e 'scripts/test-affected-kb-consumers' -e 'scripts/orphan-process-reaper-mutations'` >= 3
- 0.3 Re-run the code-review overlap query for the files under Files to Edit; confirm CI runs the scripts job as a non-root user

## Phase 1 -- recorder (own commit)

- 1.1 Write Guard 1 rows (section B) in `scripts/audit-suite-reads.test.sh`: uid row, `EXPECT_IDMAP` probe, scripted mutants rows 1-3 with "mutation landed", row 4 shim; run RED
- 1.2 `cmd_record`: probe `unshare -cn`, then `unshare -rn`, then bwrap; `idmap=` header cell
- 1.3 `make_scratch_bin`: add `unshare`
- 1.4 Text updates: header line 17, `die_usage` line 567, test header 15-16 and skip text 777-778, "rows with different idmap are not comparable" note
- 1.5 Re-price `ROWS_B_CORE` (line 771) and `MIN_CASES` (line 1306); suite green, 0 skipped
- 1.6 Run `scripts/guard-vacuity-floor.test.sh`, `fixture-relative-assert`, `fixture-dir-operand-assert`, `fixture-cd-containment`; commit

## Phase 2 -- declarations and the hedge (own commit)

- 2.1 Five paths into `AFFECTED_SCRIPTS_AUDIT_SUITE_READS_PATHS`
- 2.2 `ALWAYS_ON_SUITES` += `scripts/test-affected-kb-consumers` ("Round 4" comment); keep its AFFECTED array with the "retained for pre-push-ratchet-lane arm 21; do not delete" comment
- 2.3 `scripts/test-all.sh:3025` 140 -> 141; `scripts/test-all-affected.test.sh` f1 literals (1781, 1782, 1784) and new row f2 after q4 against the real runner (keep-list untouched)
- 2.4 Correct the A5 `scripts/orphan-process-reaper` comment in `scripts/lib/test-affected-paths.sh`
- 2.5 Run the consumer sweep (plan section) and judge every hit
- 2.6 Targeted suites: `test-all-affected.test.sh` (detached + Monitor), `test-affected-derive.test.sh`, `test-affected-kb-consumers.test.sh`, `pre-push-ratchet-lane.test.sh`, `lint-orphan-test-suites.sh`, `.claude/hooks/incident-sandbox-coverage.test.sh`, `c4-count-parity.test.sh`; commit

## Phase 3 -- evidence (detached, Monitor, never a foreground sleep)

- 3.1 `record --rev <SHA> --mode check --cover-from-selection --max-load 12 --load-wait 600 --only <9 labels> --out <new dir>` against the committed SHA
- 3.2 Pass criterion: exit 0, no `unreliable`/`load_refused` row (retry once); known-clean control `covered`

## Phase 4 -- docs

- 4.1 Append the dated addendum to `always-on-audit.md` (per suite: option, why, cost; table verbatim with SHA; pre-2026-10-04 rows marked idmap=root)
- 4.2 Append short ADR-242 decision 19 (supersedes decision 18's sentence and 7 s threshold for the three suites; hedge rule; revisit trigger)
- 4.3 Commit, push (no merge commits; rebase if behind), PR body `Ref #9307`
