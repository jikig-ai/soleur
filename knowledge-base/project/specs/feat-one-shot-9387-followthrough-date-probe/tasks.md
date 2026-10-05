# Tasks: enroll #9387 in the follow-through sweeper with a notify-only date probe

Plan: knowledge-base/project/plans/2026-10-05-feat-enroll-9387-notify-only-date-probe-plan.md

## Phase 1: Probe and suite (tests first)

- 1.1 Write scripts/followthroughs/tty-ack-migration-9387.test.sh (mirror workspaces-plaintext-hold-9348.test.sh)
  - 1.1.1 Instrument self-test, case_ control that must fail, hard pass floor
  - 1.1.2 Clock arms via NOW_EPOCH: before (2), deadline-1s (2), deadline (5), deadline+1s (5), year 2100 (5)
  - 1.1.3 Hostile clocks -> 3: abc, -5, 1.5, 13-digit, trailing newline, fullwidth digits, Arabic-Indic digits
  - 1.1.4 Zero-padded clocks: 0000000009 -> 2; zero-padded epoch above deadline -> 5
  - 1.1.5 date unusable: absent, garbage shim (with and without seam) -> 3
  - 1.1.6 Production shape (env -i, no seams): rc in {2,5}; credential canaries never printed
  - 1.1.7 No gh/curl: stub log empty on both verdict arms; source pin on executable lines
  - 1.1.8 Message arm: exit-5 names bootstrap-runs.jsonl, founder machine, ADR-264, ledger line is not approval evidence; (a) before (b); exit-2 names NOT YET and 2026-10-16
  - 1.1.9 Source pins: every exit operand literal in {2,3,5}; no set -e/-u; LC_ALL=C; header has NOTIFY-ONLY and RETIREMENT:
  - 1.1.10 Six mutation arms M1-M6 with pristine-copy control
- 1.2 Run the suite red (probe missing aborts loudly), then write scripts/followthroughs/tty-ack-migration-9387.sh
  - 1.2.1 Header: notify-only, credential posture (none), exit vocabulary, why the ledger is unreachable, RETIREMENT line
  - 1.2.2 Body: LC_ALL=C, no set -e/-u, validated epochs, base-10 compare, exit 2 / 3 / 5 only
  - 1.2.3 chmod 755 and index mode 100755
- 1.3 Run the single suite plus followthrough-exec-bit.test.sh and lint-followthrough-varq-ban.sh locally (no long battery)

## Phase 2: Registration

- 2.1 Append run_suite "scripts/followthroughs/tty-ack-migration-9387" LAST in the light scripts block of scripts/test-all.sh with a comment
- 2.2 python3 scripts/regenerate-shard-manifest.py --incremental --write; diff is one added row per TSV
- 2.3 bash scripts/lint-orphan-test-suites.sh

## Phase 3: Ship and post-merge enrollment

- 3.1 PR body uses Ref #9387 (never Closes); no .github/** path in the diff; admin merge on green CI via admin-merge-ready.sh, Reviewed-By-Soleur trailer
- 3.2 After merge: probe present and executable in the primary checkout (pull --ff-only, else untracked copy)
- 3.3 env -i local run of the probe: expect exit 2 NOT YET
- 3.4 gh issue edit 9387: add labels follow-through, do-not-autoclose; append unfenced column-0 directive (script=, earliest=2026-10-16T00:00:00Z, no secrets=) to the freshly read body
- 3.5 Verify by pull: labels, original text intact, directive at column 0 outside fences, directive date equals DEADLINE_ISO, issue still OPEN
- 3.6 Do not dispatch the sweeper and do not start the migration
