# Evidence: grep -q drain, Item B slice S6 (apps/web-platform/*.test.sh)

Every figure below was read from command output on this branch. Base SHA for every comparison: `df1891cbbb7cb32a20e1c5c0bf2403b4b2a2f6cf` (`origin/main`, merged into the branch once during planning, never again; `git rev-list --count HEAD..origin/main` read 0 at the start of work).

## Drain probe (GNU grep, dev host)

Run with the SIGPIPE disposition forced in two legs. Default disposition: `q: 141`, `c: 0`, `nomatch: 1`, `neg-q: 0`, `neg-c: 1`. Ignored disposition: `q: 1`, `c: 0`, `nomatch: 1`, `neg-q: 0`, `neg-c: 1`. The `ubuntu:24.04` leg was not run (no container runtime was used on this host); the converted form was run once under `dash` (rc 0).

## Red step, then conversions

- Row lowered to `<= | 60`: `FAIL: deferral ceiling exceeded: apps/web-platform/*.test.sh has 178 hits, ceiling 60`, rc 1.
- Codemod census (dry run): `WOULD-CHANGE: 60 lines in 14 files` by default; with the 13 reviewed-suspect paths `WOULD-CHANGE: 118 lines in 26 files`. Written in two passes (60, then 58); guard green at `60 hits, ceiling 60`. Idempotency dry run: `WOULD-CHANGE: 0 lines in 0 files`.
- Data tier: 38 lines in 9 files by `data_convert.py` (`data-conversions.txt`); guard read `22 hits, ceiling 60` after it.
- Hand tier: 22 base lines by `hand_apply.py` (`hand-edits.txt`: 4 `-m` forms, 3 labels, 15 kept lines, 14 marker lines, two of them on marked variables); guard read `0 hits` and `stale deferral`, then the row was deleted in the guard commit.
- Commits: 3d2ba9f1bc (60), 0e213ae155 (58 plus ceiling 60), data tier, hand tier, guard edit (7783eea0b7).

## verify

`python3 scripts/grep-q-drain-codemod.py verify --base df1891cbbb... --hand-edits <spec>/hand-edits.txt`: `verified: 156`, `hand-edited: 24`, `unexplained: 0`. `git diff --numstat df1891cbbb -- apps`: 37 files, 180 insertions, 178 deletions. No fenced file and no baseline file in `git diff --name-only df1891cbbb...HEAD`.

## Guard

`bash .claude/hooks/grep-q-pipe-guard.test.sh` rc 0 (about 7 s); 8 `DEFERRED:` lines (none for the apps glob); `SWEEP_CANARY_COUNT=9`, `REAL_PLANTED=31`, `SWEEP_PROBE_CHECKS=62` (63 `sweep_probe_fail+=(` occurrences, as before). Lints: `lint-shell-capture-exit.py --baseline` 0 new findings; `guard-vacuity-floor.test.sh` 23/0; `lint-orphan-test-suites.sh` none orphaned; shellcheck delta over the 37 files (line and column normalised) empty (1792 lines on each side); `run-registered-suites.sh --list` derives 175 infra suites and lists all 26 infra files this PR edits; the converted form `grep -c >/dev/null -- 'a'` under `dash`: rc 0. No converted line sits inside an `sh -c` text (the two `bash -c` lines are kept, marked controls).

## What merging fires (`trigger-derive.py`, probe lit 6 workflows)

`FILTERED` rows over the 50 paths of the diff (49 files plus this `evidence.md`): `apply-web-platform-infra.yml` push 26 of 50; `infra-validation.yml` push and pull_request 29 of 50; `mint-inngest-bootstrap-tag.yml` push 2 of 50; `validate-vector-config.yml` push and pull_request 28 of 50; `web-platform-release.yml` push 37 of 50; 19 other filtered pairs match 0 of 50; 27 unfiltered pairs.

## Guard mutation matrix (scratch clone of the committed guard, one mutant at a time, `ulimit -v 6000000`, green control first, landing check by `git diff HEAD`, restore by `git reset --hard` plus `git clean`)

All 41 rows of the first batch and the second batch graded as the plan predicted (RED rows on the named text, known surviving mutants GREEN):

- Rows 1a to 1d (new hit in four places), 2a to 2d (revert one converted site: eval string, stub, suspect file, negated line), 3 (three members), 4 (table emptied), 5a and 5b (row put back), 6 (row put back with a covering hit), 8 (complement of the conversion: `outside the deferral table (178 site(s))`): RED rc 1.
- Rows 7a, 7b, 7d, 7f, 7g (a pathspec exclusion of a root): RED rc 3 `UNRESOLVED: no swept file under ...`. Rows 7c, 7e, 7h: RED rc 1 `the derived sweep's own probe is broken`. Rows 7i and 7j: GREEN rc 0, known surviving mutants.
- Rows 9a and 9b (plant list or pin edited): RED with `real-table-control ... (want 31)` and `(want 32)`. Row 12 (list and pin edited together): GREEN rc 0, the known anchor limit.
- Rows 10a (drained spelling) and 10b (real marker): GREEN; paired control 10z (bare hit) and look-alike 10c: RED.
- Rows 11a to 11c (narrow, file-exact and wide row resurrected beside the pin): RED.
- Rows 13a and 13b (`.gitignore` of a whole root): RED rc 3; 13c (root removed from `SWEEP_CANARIES` alone): RED `canary-count: ... has 8 roots, pinned at 9`; 13d to 13f (only test-shaped files or a nested directory hidden): GREEN rc 0, recorded surviving mutants (S7 remedy in `decision-challenges.md`).
- Rows 13g, 13h, 13i (the new `test/` root omitted from one canary place each: `sweeproot` fixture, `sw_roots` alternation, `okroot` loop): RED rc 1 each.
- Row 14a, 14b, 14c (every marker stripped: `outside the deferral table (17 site(s))` = 14 plus the 3 pre-existing markers in `infra/scripts/sigpipe-triage-feasibility.sh`) and 14d (one run per marker line, 14 of 14): RED each.
- Row 15 (pin edited alone): RED. Row 16 (`>/dev/null` dropped from one converted line): `verified: 155`, `unexplained: 1`, `UNEXPLAINED ...: added line is not the transform of its base line`, rc 1. Row 17 not re-run (S5 row 17).

## Pair run (real detached clone at the base SHA, root and `apps/web-platform` `node_modules` linked on both sides, sequential, `ulimit -v 6000000`, `TMPDIR=/var/tmp`, `nice -n 10`; caps 600 s, 1500 s for `workspaces-boot-unlock`, 900 s for `workspaces-luks-provision`; load 2 to 4)

37 suites. 34 read identical rc 0 and the same final line on both sides. The three that did not read as plain identical passes:

- `infra/inngest.test.sh`: branch rc 1 with no FAIL line, cut off mid-run; the host filesystem was full at that moment (`No space left on device` while cloning scratch). Rerun on the branch alone after space was freed: `=== Results: 419/419 passed, 0 failed ===`, rc 0. Recorded as a rerun, not as an identical pair.
- `infra/workspaces-luks-loopback.test.sh`: rc 2 on both sides, environment gate (needs root and dm-crypt); its one converted line (a `-m` form) is exercised only by CI.
- `test/infra/vector-pii-scrub.test.sh`: rc 1 on both sides, `FAIL: vector binary not found (set VECTOR_BIN or install Vector 0.43.1)`; its 7 converted lines are exercised only by CI's `validate-vector-config`.

| suite (under apps/web-platform/) | base rc | branch rc | same final line | skip lines base/branch |
| --- | --- | --- | --- | --- |
| infra/apt-bounded.test.sh | 0 | 0 | yes | 0/0 |
| infra/ci-deploy.test.sh | 0 | 0 | yes | 1/1 |
| infra/cron-egress-ghcr-probe.test.sh | 0 | 0 | yes | 19/19 |
| infra/cron-egress-nftables.test.sh | 0 | 0 | yes | 2/2 |
| infra/cron-egress-self-heal.test.sh | 0 | 0 | yes | 1/1 |
| infra/cutover-inngest-workflow.test.sh | 0 | 0 | yes | 24/24 |
| infra/doppler-download-error-channel.test.sh | 0 | 0 | yes | 0/0 |
| infra/fresh-boot-parity.test.sh | 0 | 0 | yes | 0/0 |
| infra/fresh-boot-ready.test.sh | 0 | 0 | yes | 4/4 |
| infra/infra-config-handler-bootstrap.test.sh | 0 | 0 | yes | 0/0 |
| infra/inngest-dedicated-host-classify.test.sh | 0 | 0 | yes | 0/0 |
| infra/inngest.test.sh | 0 | 1 | NO | 3/1 |
| infra/lb-weight-gate-with-marker.test.sh | 0 | 0 | yes | 0/0 |
| infra/luks-monitor-install.test.sh | 0 | 0 | yes | 0/0 |
| infra/luks-monitor.test.sh | 0 | 0 | yes | 3/3 |
| infra/registry-insecure-config.test.sh | 0 | 0 | yes | 0/0 |
| infra/registry-luks-launch-gate.test.sh | 0 | 0 | yes | 0/0 |
| infra/registry-luks.test.sh | 0 | 0 | yes | 0/0 |
| infra/supabase-advisor/scan-workflow-mutation.test.sh | 0 | 0 | yes | 0/0 |
| infra/web2-luks-rebirth-workflow.test.sh | 0 | 0 | yes | 1/1 |
| infra/workspaces-boot-unlock.test.sh | 0 | 0 | yes | 1/1 |
| infra/workspaces-luks-freeze.test.sh | 0 | 0 | yes | 1/1 |
| infra/workspaces-luks-loopback.test.sh | 2 | 2 | yes | 1/1 |
| infra/workspaces-luks-provision.test.sh | 0 | 0 | yes | 3/3 |
| infra/workspaces-luks-verify-root-mtime.test.sh | 0 | 0 | yes | 0/0 |
| infra/zot-image-fetch.test.sh | 0 | 0 | yes | 0/0 |
| scripts/dev-ledger-parity.test.sh | 0 | 0 | yes | 11/11 |
| scripts/lint-migration-fk-preconditions.test.sh | 0 | 0 | yes | 2/2 |
| scripts/lint-migration-immutability.test.sh | 0 | 0 | yes | 0/0 |
| scripts/postgrest-reload-schema.test.sh | 0 | 0 | yes | 1/1 |
| scripts/run-migrations-schema-probe.test.sh | 0 | 0 | yes | 0/0 |
| scripts/sandbox-canary-regression.test.sh | 0 | 0 | yes | 1/1 |
| scripts/seed-live-verify-user.test.sh | 0 | 0 | yes | 0/0 |
| scripts/sentry-monitors-audit.test.sh | 0 | 0 | yes | 2/2 |
| test/infra/ghcr-blocked-alert.test.sh | 0 | 0 | yes | 3/3 |
| test/infra/inngest-luks-wrong-volume-alert.test.sh | 0 | 0 | yes | 0/0 |
| test/infra/vector-pii-scrub.test.sh | 1 | 1 | yes | 0/0 |

## Observer mutants for the 38 data-tier lines

Protocol: control first (rc 0), one mutant at a time under `ulimit -v 6000000`, inversion `grep -cv<flags> >/dev/null` (every span on the line), then never-match `grep -m 0 -c<flags> >/dev/null` for lines the inversion left alive. A kill is graded on the suite's own FAIL text with rc 1. `scan-ancestor-signal-helpers.py --list` was run on `ci-deploy` (class L: the `trap ... pkill -TERM -P` line) and `workspaces-luks-provision` (class P twice: `kill -9 "$PPID"`), which are the only two suites with data-tier lines that list a signalling site.

Seven short suites, 25 of the 38 lines (19 killed, 4 unobserved by their suite, 2 observed as an rc 1 abort with no FAIL line). The survivors are lines their suite does not observe: they were equally unobserved on base, nothing was reverted, and no claim of coverage is made for them.

| file:line | result | reading |
| --- | --- | --- |
| infra/cron-egress-nftables.test.sh:196 | inv(spans=1):KILLED | killed |
| infra/cron-egress-nftables.test.sh:289 | inv(spans=2):KILLED | killed |
| infra/cron-egress-nftables.test.sh:291 | inv(spans=1):SURVIVED nomatch(spans=1):SURVIVED | unobserved by its suite (survived inversion and never-match) |
| infra/cron-egress-nftables.test.sh:295 | inv(spans=1):KILLED | killed |
| infra/cron-egress-nftables.test.sh:307 | inv(spans=2):KILLED | killed |
| infra/cron-egress-nftables.test.sh:309 | inv(spans=1):SURVIVED nomatch(spans=1):KILLED | killed |
| infra/cron-egress-nftables.test.sh:311 | inv(spans=1):SURVIVED nomatch(spans=1):SURVIVED | unobserved by its suite (survived inversion and never-match) |
| infra/cron-egress-nftables.test.sh:313 | inv(spans=1):SURVIVED nomatch(spans=1):KILLED | killed |
| infra/cron-egress-nftables.test.sh:315 | inv(spans=1):SURVIVED nomatch(spans=1):KILLED | killed |
| infra/cron-egress-nftables.test.sh:317 | inv(spans=1):SURVIVED nomatch(spans=1):KILLED | killed |
| infra/cron-egress-nftables.test.sh:319 | inv(spans=2):SURVIVED nomatch(spans=2):KILLED | killed |
| infra/cutover-inngest-workflow.test.sh:4365 | inv(spans=1):KILLED | killed |
| infra/cutover-inngest-workflow.test.sh:4373 | inv(spans=6):KILLED | killed |
| infra/infra-config-handler-bootstrap.test.sh:262 | inv(spans=1):KILLED | killed |
| infra/infra-config-handler-bootstrap.test.sh:264 | inv(spans=1):KILLED | killed |
| infra/infra-config-handler-bootstrap.test.sh:266 | inv(spans=1):KILLED | killed |
| infra/inngest-dedicated-host-classify.test.sh:636 | inv(spans=1):SURVIVED nomatch(spans=1):KILLED | killed |
| infra/inngest.test.sh:1813 | inv(spans=2):RC1-NO-FAIL-TEXT nomatch(spans=2):RC1-NO-FAIL-TEXT | observed (suite aborts rc 1, no FAIL line) |
| infra/inngest.test.sh:1849 | inv(spans=1):RC1-NO-FAIL-TEXT nomatch(spans=1):RC1-NO-FAIL-TEXT | observed (suite aborts rc 1, no FAIL line) |
| infra/registry-insecure-config.test.sh:102 | inv(spans=1):SURVIVED nomatch(spans=1):KILLED | killed |
| infra/zot-image-fetch.test.sh:63 | inv(spans=1):KILLED | killed |
| infra/zot-image-fetch.test.sh:293 | inv(spans=1):KILLED | killed |
| infra/zot-image-fetch.test.sh:368 | inv(spans=1):SURVIVED nomatch(spans=1):SURVIVED | unobserved by its suite (survived inversion and never-match) |
| infra/zot-image-fetch.test.sh:370 | inv(spans=1):SURVIVED nomatch(spans=1):SURVIVED | unobserved by its suite (survived inversion and never-match) |
| infra/zot-image-fetch.test.sh:372 | inv(spans=1):KILLED | killed |

`ci-deploy.test.sh` (5 lines: 540, 547, 9795, 9809, 9816) and `workspaces-luks-provision.test.sh` (8 lines: 329, 849, 851, 885, 899, 903, 906, 942): UNVERIFIED-IN-NAMESPACE, 13 of 38 lines. Both suites list a signalling site, so every mutant had to run through `bash scripts/soleur-sandbox.sh run-isolated "$SBX" -- bash <suite>` (a PID 1 namespace, uid 0; the sandbox was removed with the allocator's `rm` verb), and the unmutated control read red there: `ci-deploy` rc 1, `FAIL: assertion-count floor: TOTAL=565 (PASS+FAIL=565), expected TOTAL >= 568` (three rows differ under uid 0); `workspaces-luks-provision` rc 2, `FATAL: fixture dir is EMPTY; git -C "" would operate on <sandbox>`. A red control inside the namespace is an environment difference and not a kill, so no mutant of those 13 lines was run and none is claimed. Their evidence is the pair run on the host (identical rc 0 on both sides) plus `verify`.

The eval strings among the 38 lines run under live `pipefail`; the draining form is the same one S3 to S5 shipped.

## Ablation V0 (row deleted and pin edited only, nothing else; re-measured on the final guard text)

Control rc 0. Rows 7b, 7c, 7e, 7h and 13b: GREEN rc 0 (the root canary for `test/`, the plants and the nested plants are what close them in the full form). Rows 7a and 13a: RED rc 1, but on `stale deferral: apps/web-platform/infra/cloud-init-registry.yml has no hits left` (the six file-exact rows going stale), the wrong reason for the `infra/` root canary, which becomes the sole witness once those rows convert. Row 6 (row put back with a covering hit): RED rc 1. Row 7d: RED rc 3.

## Guard run time (AC-10)

Same host, same run, three alternating pairs, base guard versus edited guard (each about 10.5 s user plus 6.5 s sys, 7.3 s to 8.0 s wall); the edit is not measurable against the noise. Planning figure 8.8 s; cap 15 s.

## Addendum, review round (12-seat panel at 0a29e171ba; corrections by appending, nothing above was edited)

- **Removed scripts.** `data_convert.py`, `hand_apply.py`, `guard_edit.py` and `trigger-derive.py` are no longer in this directory (they cannot run again after merge; see decision-challenges item 29). They are readable at `787bbc944f` (`git show 787bbc944f:knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s6-web-platform-tests/<name>`). The commands and counts above stay the evidence; `verify` needs only `hand-edits.txt`.
- **Commits.** The five conversion and guard commits are 3d2ba9f1bc (codemod default pass, 60 lines), 0e213ae155 (reviewed-suspect pass, 58 lines, plus the row ceiling to 60), 6f6dfccc26 (data tier, 38 lines), 9c0d697672 (hand tier, 22 base lines), 7783eea0b7 (row deleted, canary roots, plants, pin); `0a29e171ba` added this file.
- **Mutation-matrix row count.** The paragraph above lists the rows by id; the count it states as 41 is the first driver's rows (1a to 15) and the rows 13g to 14d and 16 came from the second driver, 49 distinct row ids in all, every one graded as the plan predicted. Rows 17 and ablation V1 are not re-run (S5 and plan decision 5).
- **V0 attribution.** The `test/` root canary is what closes rows 7b and 13b on the full guard (a `.gitignore` entry is invisible to scratch plants); the plants and nested plants close 7c, 7e and 7h. The V0 paragraph named the union.
- **Hand-edit count wording.** 24 hand-edited added lines for 22 base lines: one true insertion (`cron-egress-self-heal.test.sh:532+`, the `MUT_EARLY_PIPE` variable) and `ghcr-blocked-alert.test.sh:167` becoming two lines under its plain key.
- **`inngest.test.sh` reconciliation.** Base log 3 skip lines (`grep -ci skip`); the branch-only rerun after space was freed, 3 skip lines, `419/419 passed`, rc 0; a second independent rerun by the data-integrity seat read the same. The 3/1 in the pair table is the disk-full cut-off, not a difference in arms.
- **Observers for the four lines the assertion-side observer could not see** (measured by the test-design seat on a sandbox copy, not by this branch's driver): `cron-egress-nftables.test.sh:291` and `:311` go red when `cron-egress-resolve.sh` has `PRUNE="no-prune"` changed to `PRUNE="prune"` and the suite runs with `CEN_RESOLVER` pointing at the copy (the same two rows go red with the base `grep -q .` spelling, and the suite is green with that conjunct replaced by `true`); `zot-image-fetch.test.sh:368` and `:370` go red when `cloud-init-registry.yml:2501` has `exit 1; }` changed to `:; }` (about 7 s). So those four lines are observable and were equally observable on base.
- **Guard time (AC-10).** Three alternating pairs, base 10.5 s user plus 6.5 s sys and edited 10.5 s user plus 6.6 s sys (7.3 to 8.0 s wall) on a host at load 2 to 4; a review seat measured 10.0 to 12.0 s wall under load 10. The 15 s cap held in every reading.
- **What merging fires.** `mint-inngest-bootstrap-tag.yml` takes a no-change decision for a test-only diff (the architecture seat read its decision logic: it compares the `cp`-staged carriers only); `soleur:postmerge` reads that run. The PR-time Terraform plan comment showing an inngest host replacement is pre-existing drift from #9899 (no `.tf`, carrier or hashed file is in this diff; the push apply job's `-target` set has no host resource), not an effect of this change.
