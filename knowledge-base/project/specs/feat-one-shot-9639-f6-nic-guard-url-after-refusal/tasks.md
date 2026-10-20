# Tasks - fix: resolve the nic-guard heartbeat URL after the xtrace refusal, not in the unit wrapper (#9639 F6)

Plan: knowledge-base/project/plans/2026-10-20-fix-nic-guard-url-lookup-after-xtrace-refusal-plan.md
PR body: `Ref #9639`, `Part of tracker #9217` (no closing keyword). Do NOT touch cloud-init.yml, betterstack-logs-alerts.tf, apply-web-platform-infra.yml, server.tf, .claude/hooks/grep-q-pipe-guard.test.sh, scripts/guard-vacuity-floor.test.sh, or any web-git-data-probe / inngest-consumer-probe / inngest-registry-probe file.

## Phase 1 - Tests first (RED)

### web-private-nic-guard.test.sh

- [x] 1.1 Harness: default env becomes `WEB_NIC_GUARD_URL_KEY=WEB_NIC_GUARD_URL_SYNTH` + `WEB_NIC_GUARD_URL_SYNTH=<url>`; add `-u WEB_NIC_GUARD_URL` to the env scrub; rewrite the `EXTRA_ENV` `WEB_NIC_GUARD_URL=` fixtures to `WEB_NIC_GUARD_URL_SYNTH=`.
- [x] 1.2 Rows: key unset; one table-driven invalid-key loop (lowercase, leading digit, space, hyphen, `a[$(touch PLANT)]`, newline, empty) asserting no execution (`PLANT` absent), no beat, `reason=empty`, value-free invalid-key line; pre-set bare variable ignored; production-shaped keys `WEB_NIC_GUARD_URL_WEB_1` and `_WEB_2` delivered; lowercase key refused under `LANG=en_US.UTF-8`; stub-curl env dump (key-named line excluded) never holds the URL; valid-but-special keys `BASH_ENV`, `RANDOM`, `PATH` read with no execution; hoisted-lookup mutant leaks under `SHELLOPTS=xtrace`.
- [x] 1.3 Unit rows: static row over every `Exec*` directive (anchored, no `$`/`${!`); behavioral launch of the real `$$`-unescaped `ExecStart` with a stub `doppler` under `SHELLOPTS=xtrace` and a `BASH_ENV` `set -x` (rc 78, refusal text present, secret in neither stream); G2.1 leak control with the pre-fix `ExecStart` literal in a fixture copy (secret MUST appear); positive row without xtrace (URL reaches curl's stdin config); dispatch row (stub `doppler` that never execs must fail the row; the stub only skips to `--` and execs, the secret is pre-exported in the test env; launch with `env SHELLOPTS=xtrace bash -c 'eval "$1"' _ "$LINE"`; assert the extracted line names `/usr/local/bin/<script>.sh` before the path rewrite); transitional-pair row (old wrapper env + new script uses the key's value).
- [x] 1.4 Replace the `grep -qF '#9639' $SUT` comment assertion with one asserting the lookup follows the refusal. Raise `MIN_CASES` from the green run.

### web-zot-consumer-probe.test.sh

- [x] 1.5 Lean subset against `WEB_ZOT_CONSUMER_URL` with `ZOT_PULL_TOKEN` set: static, xtrace launch (both forms), G2.1 leak control, positive, dispatch, hoisted-lookup, one hostile key.

### doppler-injection-bound.test.sh

- [x] 1.6 RED rows G1.1-G1.9 and GH1-GH3, GH6 (restore wrapper expansion; second directive; operator-suffix spelling; no-op wrapper stage -> `CENSUS_FAIL`; strip script-side indirect -> `ACK_FAIL stale`; delete an unfixed sibling's wrapper ack; stale wrapper ack for a fixed unit; wrapper-ack pin edit; must-PASS unit without an outer `bash -c`; unmutated control; G1.9 `_KEY`-bound script-side regex: `${!FOO_KEY:-}` enters, `${!_seam+x}` does not, inngest-luks-cutover stays out; GH6 meta-floor row for `wrapper_units_checked`).
- [x] 1.7 Run the three suites on the unchanged tree; record the failing row names for the PR body.

## Phase 2 - GREEN

- [x] 2.1 `web-private-nic-guard.sh`: key read after the refusal, `LC_ALL=C` `case` validation, `${!_key:-}` into a plain unexported variable, value-free invalid-key line inside the existing `_refusal_due` block; refresh the header LIMIT comment and the step-7 comment.
- [x] 2.2 `web-private-nic-guard.service`: `ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- /usr/local/bin/web-private-nic-guard.sh'`; rewrite the comment block.
- [x] 2.3 Same pair for `web-zot-consumer-probe.sh` / `.service` (lookup after the refusal `case` and after the `--canary-only` early exit; header states the refusal needs the pull credential).
- [x] 2.4 `doppler-injection-bound.test.sh` scanner: widen the unit-side `INDIRECT_RE` (optional operator suffix), script-side population reason bound to `*_KEY`-named indirect expansion, unit-side wrapper finding over every directive, `WRAPPER_ACK_REASONS` (2 entries) + `WRAPPER_ACK_CARDINALITY = 2`, `CENSUS: wrapper_units_checked` floor from a green run, stale-wrapper-ack check; refresh the two fixed units' `ACK_REASONS` text. `ACK_CARDINALITY`, `MIN_POPULATION`, `MIN_DOPPLER_UNITS` unchanged.
- [x] 2.5 `web-probe-envwrite.sh`: comment-only correction.
- [x] 2.6 Confirm every Phase 1 row is now GREEN and the mutation rows still RED.

## Phase 3 - Ratchets and verification (before push)

- [x] 3.1 `grep-q-pipe-guard.test.sh` (PJ_TRIPLES unchanged, recompute before/after), `lint-trap-tempfile-ownership` (+ test), `guard-vacuity-floor.test.sh`, shellcheck on touched `.sh`, `c4-count-parity.test.sh`, `lint-guard-contract.py`, `lint-infra-no-human-steps.py --changed --base origin/main`, markdownlint on plan + tasks, the discoverability probe verbatim.
- [x] 3.2 `fresh-boot-parity.test.sh`, `web-host-provisioner-parity.test.sh`.
- [ ] 3.3 Simulate the rollback in a scratch detached worktree under `/var/tmp`; write the measured recipe into the PR body.
- [ ] 3.4 Record `doppler-injection-bound` CENSUS before/after (population 10 -> 10, doppler units 20 -> 20) in the PR body.
- [ ] 3.5 `git diff --name-only origin/main...HEAD` contains none of the files listed under "Do NOT touch".

## Phase 4 - ADR and tracking

- [x] 4.1 ADR-202 addendum (3 lines): the refusal's reach includes the unit wrapper; enforced for `doppler run` units by the scanner stage.
- [ ] 4.2 Comment on #9639: F6 fixed for nic-guard + zot; git-data-probe and inngest-consumer-probe NOT fixed (reason: no xtrace refusal to order against; adding one is a separate #7797-class change; inngest-consumer-probe also sources a file open PR #10501 edits); F7 and F8 still open. No new issue.
- [ ] 4.3 After merge: run the plan's post-merge verification (anchored `Creation complete` lines for both install resources, heartbeats up, Logs rows), record the merge on #9217 without DONE, then close out the series status there.
