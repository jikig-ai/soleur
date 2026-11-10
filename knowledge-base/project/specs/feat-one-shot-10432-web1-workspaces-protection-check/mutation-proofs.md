# Mutation proofs and RED evidence: feat-one-shot-10432-web1-workspaces-protection-check

Plan: `knowledge-base/project/plans/2026-11-10-infra-web1-workspaces-volume-protection-check-plan.md`. Every mutation below
ran on a COPY (`SOLE_COPY_DRIFT_WF=<copy>` for the workflow, a scratch copy for the suite, the evaluator or a document);
the real files were never mutated, and each copy was diffed against a pristine backup.

## Phase 1a: green refactor against the unchanged workflow

`bash plugins/soleur/test/sole-copy-drift-check.test.sh` at e7024c5ed4 (the workflow unchanged): `=== Results: 195/195
passed, 0 failed ===`, rc 0, `FLOOR=195`, `TABLE_ROWS=126`.

## Phase 1b: RED

1. Against the unchanged workflow the suite stops at the extractor floor (rc 2): `FATAL: job 'sole-copy-protection-check'
   lacks the matrix rows: strategy.matrix.include must carry the entries inngest and web1 (extractor floor; got null)`.
2. Per-row evidence, against a scaffold-only copy (today's job plus `name:`, `fail-fast: false` and the two include rows;
   every step unchanged): `=== Results: 207/250 passed, 43 failed ===`. All 126 pre-existing table rows stayed green (H3
   counted 157 executed rows = 126 + 31 new). Every one of the 31 new W and C rows failed; its first failure line:

| Row | First failure line (scaffold-only copy) |
|---|---|
| WV1 | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|live=true\|name=soleur-web-platform-data-luks\|tf_age_min=N\|v |
| WV2 | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|live=false\|name=soleur-web-platform-data-luks\|tf_age_min=N\| |
| WV3 | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|live=false\|name=soleur-web-platform-data-luks\|tf_age_min=N\| |
| WV3b | 89 min: got 'could-not-read', want 'lift-pending-apply' |
| WV4 | probe outputs: got 'verdict=could-not-read\|', want 'expected=false\|http=200\|live=false\|name=soleur-web-platform-data-luks\|tf_age_min=N\ |
| WV5 | probe outputs: got 'verdict=could-not-read\|', want 'expected=false\|http=200\|live=true\|name=soleur-web-platform-data-luks\|tf_age_min=N\| |
| WV6 | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|name=soleur-web-platform-data-luks\|tf_age_min=N\|verdict=volu |
| WV8 | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|name=soleur-web-platform-data-luks\|tf_age_min=N\|verdict=volu |
| WT1/soleur-alpha-store | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|live=true\|name=soleur-alpha-store\|tf_age_min=N\|verdict=matc |
| WT1/zz9-other-name | probe outputs: got 'verdict=could-not-read\|', want 'expected=true\|http=200\|live=true\|name=zz9-other-name\|tf_age_min=N\|verdict=matches- |
| WT3 | probe outputs: got 'verdict=could-not-read\|', want 'tf_age_min=N\|verdict=could-not-read\|' |
| WR1 | probe outputs: got 'expected=true\|http=200\|live=true\|name=soleur-inngest-redis-store-luks\|verdict=matches-declared\|volume_id=106903269\ |
| WF1 | title: got 'infra: the Inngest store volume protection check could not read Hetzner (name-unreadable)', want 'infra: web-1 workspaces volume |
| WF3 | state: got 'open', want 'closed' |
| WF12/lifted-outside-terraform | the web-1 body names the Inngest volume |
| WF12/volume-not-found | the web-1 body names the Inngest volume |
| WF12/no-token | the web-1 body names the Inngest volume |
| WF12/could-not-read | the web-1 body names the Inngest volume |
| WX5 | vnf title: got 'infra: the Inngest store volume protection check could not read Hetzner (name-unreadable)', want 'infra: web-1 workspaces vo |
| WX7 | title 1: got 'infra: the Inngest store volume protection check could not read Hetzner (name-unreadable)', want 'infra: the web-1 workspaces  |
| WX9 | title: got 'infra: the Inngest store volume protection check could not read Hetzner (name-unreadable)', want 'infra: the web-1 workspaces vo |
| WX16 | the slug names entry:verdict: got '0', want '1' |
| C1 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C2 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C3 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C4 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C5 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C6 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C8 | commits read path: got 'gh api commits path=inngest-redis-luks', want 'gh api commits path=workspaces-luks' |
| C9 | every Inngest issue is untouched: got '5', want '6' |
| C10 | the could-not-perform filer succeeded without a checkout: got 'failure', want 'success' |

   For the C rows the first line is the shared commits-path invariant (the hard-coded Inngest path on the web-1 leg); each
   row also failed on its own assertion: C1 and C2 on the web-1 leg's probe outputs, C3 `web1: own file 3 h old, other file
   5 min old -> files: got 'could-not-read'`, C4/C5/C6 on their positive control (the web-1 leg's clean run could not close
   its own seeded issues), C8 on the web-1 leg's probe outputs. The other reds of that run are the expected pre-implementation
   ones: S1/S2 control (`id-placement`: the probe's literal pin), S2 "a pin literal in the probe" (did not land), S0b and
   H11a/H11b (the evaluator is not strict yet), N1b (three literals), N1c/N3/H14/H15 (the ADR-119 addendum and the runbook
   6604 read-back section do not exist yet), H3 (TABLE_ROWS not raised yet).

## Phase 4.1: GREEN and timing

The final suite, on the same host as the Phase 0.6c baseline: `=== Results: 250/250 passed, 0 failed ===`, rc 0,
`FLOOR=250`, `TABLE_ROWS=157` (H3: 157 executed rows). Compare user+sys, not wall; the host was loaded throughout.

| Run | wall | user | sys | user+sys | load (1 min) |
| --- | --- | --- | --- | --- | --- |
| before (195 assertions, the unchanged suite at the merge base, this session) | 1m42.3s | 41.0 s | 32.8 s | 73.8 s | |
| after Phase 1a (195, per-entry machinery) | 1m30.2s | 36.5 s | 31.5 s | 68.0 s | |
| after, first green (250) | 1m42.3s | 44.3 s | 38.8 s | 83.1 s | about 7-20 |
| after, final (250, the two ratchet fixes below) | 1m47.3s | 47.3 s | 40.1 s | 87.4 s | 23.6 |

The `merge_group` run's per-suite time is added by ship.

## Phase 4.2: mutation proofs

Each mutant is a COPY: workflow mutants run the suite with `SOLE_COPY_DRIFT_WF=<copy>`, harness mutants run a copy of the
suite under a unique untracked name beside it (removed after the run), and the evaluator mutant runs a suite copy whose
`EXPRLIB` points at an evaluator copy. Every copy was generated by one script that asserts each edit lands exactly once,
and the final real files equal HEAD plus the two ratchet fixes. All runs are against the final suite text. Every row below
is KILLED (the named rows went RED; rc 1); no mutant survived.

| Guard / row | Edit | Named rows that must turn RED | Observed RED (summary) |
| --- | --- | --- | --- |
| G1 r1 | `cmd_run` ignores `entry`, loads the first row | every W row, C1-C6 | 219/250: every W row (WV1-WV8, WV3b, WT1, WT3, WR1, WF1, WF3, WF12, WX5, WX7, WX9), C1-C6, C8, C9, C10, H11d |
| G1 r3 | swap `volume_id` between the rows | V1, WV1, N1, N1c | 121/250: V1, WV1, N1, N1b, N1c, S1/S2 and most of the table |
| G1 r4 | `tf_commit` hard-codes `inngest-redis-luks.tf` | C3, the commits-path invariant | 222/250: C3 (and C1-C6, C8), every web-1 row via the commits-path invariant |
| G1 r5 | `clear` builds `TITLES` for both subjects | C4 | 198/250: C4, C6, WF3 and the Inngest clear rows (duplicate titles double-process) |
| G1 r7 | the two `web1:` case arms deleted | WF1, WF12, WX5 | 245/250: WF1, WF12, WX5, WF3 |
| G1 r8 | probe pin is a literal, not `$PIN` | S2/`id-placement`, WV1 | 225/250: S1, S2 (`id-placement:step:probe`), N1b, WV1 and the web-1 rows |
| G1 r10 | awk resource hard-codes `inngest_redis_luks` | WV1, WT1, WR1 | 227/250: WV1, WT1, WR1 and the web-1 rows, C1-C6 |
| G1 r11 | notify subject is the literal "Inngest store volume" | WF1 | 249/250: WF1 |
| G2 r1 | evaluator strict branch removed (`# strict-matrix` lines) | S0b, H11a | 247/250: S0b, H11a, H11b (the strip no longer lands) |
| G2 r2 | `check()` drops the `matrix` clause | H11b | 248/250: H11b, H11c |
| G2 r3 | `refs()` checks only the first `matrix.*` ref | H11c | 249/250: H11c |
| G3 r1 | web1 `volume_id` changed by one digit | N1c, WV1 | 228/250: N1c, WV1, S1/S2 and the web-1 rows |
| G3 r3 | a third `readonly VOLUME_ID_PIN=106903269` inside the job (`tf_commit`) | N1b, S2/`id-placement` | 247/250: N1b, S1, S2 |
| G3 r4 | both rows carry `106903269` | N1c, S2/`id-placement` | 223/250: N1c, S1, S2, the web-1 rows |
| harness | `use_entry web1` a no-op | the use_entry row, WF1, WX9 | 231/250: H13, N1c, WF1, WF12, WV1, WX5, WX7, WX9, C3-C6, C9 |
| harness | invariants stop reading `issues.json` for ids | H12 | 249/250: H12 |
| harness | gh stub serves one commits answer for every path | C3 | 234/250: C3, C1, C2, C8, the web-1 V/T rows |

Not executed here, by the plan's own split: G1 rows 2, 6 and 9 are in-process S2 mutants (the suite runs them on every
run, green in the final run); G3 row 2 (the addendum sentence moved outside its section) is H14, and the N3 command-line
mutants are H15. The must-PASS input, the include rows in swapped order, is C8: green in the final run.

The first battery was discarded and rerun: two ratchet fixes were written into the real suite while workflow mutants were
still reading it, and bash reads a script as it runs, so three of those runs died mid-file (rc 2). The rerun reads a frozen
copy of the final suite.

## Phase 4.3: one row block deleted

The `WV8` row line deleted on a suite copy (its helper stays; H rows reuse it): `=== Results: 248/249 passed, 1 failed ===`,
`FAIL: H3 executed 156 rows, declared TABLE_ROWS=157`, then the outer `FATAL: only 249 assertions ran; expected >= 250.`
(rc 1).

## Phase 3.4 / 4.6b: read-only checks

- The runbook 6604 read-back line, run once as written (`HCLOUD_TOKEN_READONLY` only): `protected`, rc 0.
- The `scheduled-terraform-drift` Sentry monitor, read through the runbook path in `cron-egress-blocked.md`
  (`sentry-monitors-audit.sh`, GETs only, report to scratch): listed, not muted, not disabled; Class A (cron detector with
  no routing workflow) is clean, and the drift monitor is not among the three declared-pending unrouted monitors. Its
  IaC route is `cron-monitor-alerts.tf` email to `issue_owners`, falling through to `ActiveMembers`. `SENTRY_ISSUE_RO_TOKEN`
  answers 403 on the monitors endpoint, as that runbook records.

## Phase 4.4-4.7: ratchets, workflow readers, lints

Ratchets (final tree): `fixture-dir-operand-assert` 71/71 rc 0; `guard-vacuity-floor` 32/32 rc 0; `grep-q-pipe-guard` rc 0
(after the fix above; the first run flagged the suite's piped `grep -q`); `alarm-issue-filing-guard` 8/8 rc 0;
`fixture-relative-assert` 61/63 rc 1. Its two reds are one PRE-EXISTING row: `scripts/ci-oracle-review.sh` has 13 live
sites against a baseline of 12. Neither that file nor the baseline is in this diff, and both are byte-identical between
the merge base and `origin/main`, so `main` reds the same way. The suite's own 4 rows that the first run added are gone
(h11_run is guarded). `lint-shell-capture-exit`: 0 new findings on the suite, token-drift and test-affected-paths.

Workflow readers: the census `git grep -l scheduled-terraform-drift -- '*.test.*' 'tests/'`, rerun at work time, has 18
test files (2 more than the plan's floor: `inngest-luks-wrong-volume-alert.test.sh`, `function-registry-count.test.ts`).
All rc 0: git-data-rung2-rehearsal 143, inngest-provision-rehearsal 91, inngest-luks-wrong-volume-alert 97,
c4-count-parity 13, heartbeat-reconcile-issue-step 142/142, terraform-drift-sentry-leg 24, terraform-drift-step-order 7/7,
token-drift-workflow-causes 402/402, cf-tunnel-liveness-gate-mutations 8, check-cloudflare-token-drift 98/98,
test-apply-github-infra-mint-shape 126, test-argv-bearer-sweep 832, test-git-data-wipe-wedge 19,
terraform-target-parity (bun) 400, and under vitest cron-terraform-drift 19, function-registry-count 13,
sentry-monitor-iac-parity 27.

YAML parse rc 0; `check-workflow-duplicate-keys` OK (114 files); actionlint the same 17 pre-existing findings before and
after, none in the job. Byte identity (Phase 4.8): the first half lists only the notify `subject:`/`body:` lines; the
second half compares 15 lines, 0 diff lines; the `TITLE_*` block against `use_entry inngest` diff is empty.
`lint-guard-contract.py` on the plan: 3 guard entries, rc 0. `git diff --name-only origin/main...HEAD`: no `.tf`,
cloud-init or user_data file.
