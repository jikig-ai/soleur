# Tasks — feat-one-shot-11776-machinery-batch

Plan: knowledge-base/project/plans/2026-11-02-ci-machinery-batch-sweep-plan.md
Issues: #11776, #10859 (hold), #11789, #11795, #3926, #9457, #9830

## Phase 1 — Affected-index repair + schedule (#11776)

- [x] 1.1 Read `plugins/soleur/test/terraform-target-parity.test.ts` around the
      `inngest-userdata-budget.sh` ref (~line 5876) and classify per the drain
      rubric in `ci-pr-affected-activation.md`: real read/execute → declared
      edge in `scripts/lib/test-affected-paths.sh`; fixture-string mention →
      anchor-keyed accept row in `scripts/ci-pr-affected-audit.accept.tsv`.
- [x] 1.2 `python3 -I scripts/ci-pr-affected-replay.py ratchet --report` →
      `SOLEUR_PR_AFFECTED_RATCHET exit=0`.
- [x] 1.3 Schedule artifact: fresh `audit` numbers mapped onto #10860/#10861/
      #10959 + named remainder; post schedule comment to #11776; pointer note
      in `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`.
- [x] 1.4 CTO-ruled ceiling re-rule (#10865): `P95_MAX=240`, `MAX_MAX=285`
      constants only in `scripts/followthroughs/ratchet-observation-window-10865.sh`
      (~lines 89-90); ratifies the ruling already on #10865 at 08:31:45Z.

## Phase 2 — Merge-watch disarm gating (#11789)

- [x] 2.1 `plugins/soleur/scripts/sync-pr-behind.sh`: armed classification
      (`qw_snapshot`/`queue_wait_eval` path) must not yield `disarmed`/`proceed`
      for `autoMergeRequest=null` while `isInMergeQueue=true` — route the flag
      through the GraphQL `queue_state_read` answer (gh pr view has no field;
      verified gh 2.103.3).
- [x] 2.2 `plugins/soleur/scripts/monitor-pr-checks.sh`: gate disarm-shaped
      emission/verdicts on the queue read (`in_queue`/`--queue-state`); a
      queued PR with `automerge=false` emits an annotated state, never the
      not-armed verdict.
- [x] 2.3 `plugins/soleur/skills/ship/references/ready-run-wait.md`: add the
      queued-PR caveat to the `autoMergeRequest` armed probe.
- [x] 2.4 New stub rows in `sync-pr-behind.test.sh` + `monitor-pr-checks.test.sh`:
      queued+null → not disarmed; not-queued+null → disarmed (unchanged);
      malformed queue answer → unknown, not disarmed.

## Phase 3 — CMO gate PR_NUM scoping (#11795)

- [x] 3.1 `.claude/hooks/ship-cmo-content-gate.sh`: resolve `PR_NUM` from
      `$SCAN` (strip_command_bodies-scrubbed), scoped to the command-position
      `gh pr ready|merge` invocation (last real invocation wins).
- [x] 3.2 `+2` rows in `.claude/hooks/ship-cmo-content-gate.test.sh`: quoted
      `gh pr merge <M>` inside `--body` before AND after real `gh pr ready <N>`
      → resolves `N`.

## Phase 4 — cla-evidence-timestamp (#3926)

- [x] 4.1 `.github/workflows/cla-evidence-timestamp.yml`: `permissions:` add
      `contents: write` (push died 403).
- [x] 4.2 Escalation step (`if: failure()`): bootstrap `cla-evidence` +
      `timestamp-failure` labels (`gh label create … || true` or existence
      check) before the dedupe/`--label` use.
- [x] 4.3 Post-merge: `gh workflow run cla-evidence-timestamp.yml`; verify run
      `success` + `Verification: OK` + no `InvalidArgument`; close #3926 on green.

## Phase 5 — Main-health + red rate (#9457, #9830)

- [x] 5.1 #9457 findings comment: Oct-3 `audit-suite-reads` signature absent
      from last 40 monitor runs; current mode = legs killed at step ceilings +
      `[FAIL] lint-orphan-test-suites-mutations-a`.
- [x] 5.2 `.github/workflows/main-health-monitor.yml`: CTO-ruled realignment —
      `test-scripts` step 15→60 and job `timeout-minutes` 35→80; `test-webplat`
      step 10→30 and job 30→50; `test-bun` unchanged; no split; keep
      `plugins/soleur/test/main-health-monitor-workflow.test.sh` green.
- [x] 5.3 Disposition the `lint-orphan-test-suites-mutations-a` orphan (register
      the suite or fix per orphan-lint contract).
- [x] 5.4 #9830: classify the 8 push failures (2026-10-05→09) — flake /
      post-merge-only / queue-miss; document queue-vs-push gap; state the
      CTO-ruled target ≤2% of push runs on main red (rolling 50-run window);
      add rate line to the monitor's report surface; comment on #9830.

## Phase 6 — Hold record + ship prep

- [x] 6.1 #10859 hold comment: measured soak evidence (3 `NOT YET` lines incl.
      wall-max-over-provisional-ceiling + window paused by the red this PR
      repairs), unmet entry conditions, exact un-landed edit set. NO activation
      diff (no continue-on-error removal, no required-checks.txt row, no
      ruleset-ci-required.tf context, no count-pin change).
- [x] 6.2 `bash scripts/test-all.sh --affected` green; PR green incl.
      `affected-index-ratchet` advisory.
- [x] 6.3 PR body: `Closes #11776, #11789, #11795, #3926, #9457, #9830` +
      `Refs #10859` (hold — do NOT keyword-close it).
