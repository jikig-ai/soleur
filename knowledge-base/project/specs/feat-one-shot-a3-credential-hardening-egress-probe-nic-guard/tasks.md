# Tasks: credential-harden cron-egress-enforce-probe.sh and web-private-nic-guard.sh

Plan: `knowledge-base/project/plans/2026-10-06-fix-credential-harden-egress-probe-and-nic-guard-plan.md`
Branch: `feat-one-shot-a3-credential-hardening-egress-probe-nic-guard` | Draft PR: #9632 | Tracker: #9217 (`Ref`, never `Closes`)

## Phase 0 - RED (tests first)

- 0.1 Re-run the baseline-bypassing lint on both scripts and save the output as the pre-change evidence
  (`python3 scripts/lint-shell-trace-credential-refusal.py <file>`: expect 1 finding for the probe, 3 for the guard).
- 0.2 `web-private-nic-guard.test.sh` harness
  - 0.2.1 `run_guard`: `SUT_UNDER_TEST`, launch-flags array, `EXTRA_ENV` array via `env` (SHELLOPTS is readonly in
    the test shell); capture rc, stdout and stderr into `$RC`, `$OUT`, `$ERR`.
  - 0.2.2 `curl` stub: argv one argument per line (calls separated by a marker) into `$STUB_ARGV`;
    `STUB_POST_RC` and `STUB_PING_RC` knobs so the fallback copies are reachable.
  - 0.2.3 `PINNED_URL` read from `zot-registry.tf` (same `sed` as `fresh-boot-ready.test.sh` S4d); feed it as
    `BETTERSTACK_INGEST_URL` in `run_guard`.
- 0.3 `web-private-nic-guard.test.sh` rows (no pipe-fed `grep -q`; use here-strings or `grep -c ... >/dev/null`)
  - 0.3.1 X1 refusal loop over `bash -x`, `SHELLOPTS=xtrace`, `BASH_ENV` file: rc 78, non-`+` stderr line has the
    message, no leaked value, empty emit/ping/argv logs.
  - 0.3.2 X1b: `bash -x` with no credential still 78.
  - 0.3.3 X2 argv walk (healthy, POST-failing, heartbeat-failing): first argument `--disable`, `--noproxy` adjacent
    to `*`, call-count floors (2 POST, 2 ping).
  - 0.3.4 X3 pin: pinned (also with other token and `EXPECTED_IP`) POSTs; unrelated, `http://`, no trailing slash,
    `@evil`, `?x=host/` make zero POSTs, `unpinned_url` on stderr, heartbeat still pings, rc 0.
  - 0.3.5 X3b: exported `INGEST_URL_PINNED` and `BETTERSTACK_INGEST_URL` both evil -> zero POSTs.
  - 0.3.6 X3c: literal equals `zot-registry.tf` byte-for-byte, no `$` or backtick.
  - 0.3.7 X4: path absent from both baselines.
- 0.4 `cron-egress-enforce-probe.test.sh`
  - 0.4.1 `run_probe <path> [flags]` helper and stub dir prepended to PATH (`docker` dispatching on `$1` and refusing
    unknown argv, `nft`, `systemctl`, `sleep`, `doppler` printing a synthetic DSN, `curl`), logging to `$STUB_CALLS`.
  - 0.4.2 P-X1 (three launch forms: rc 78, non-`+` stderr line, empty call log); P-X1c (untraced: rc 0,
    `egress-enforce-ok`, doppler and curl never called); P-L (path absent from the A/B/C baseline).
- 0.5 Run both suites against the PRISTINE scripts and record RED: only the new rows fail; no pre-existing row.
- 0.6 Commit the RED tests alone (so the RED state is in history).

## Phase 1 - GREEN (scripts)

- 1.1 `cron-egress-enforce-probe.sh`: comment plus unconditional `case "$-"` block after line 28 `set -e`, before
  `CONTAINER=`. Touch nothing else (the Sentry curl stays byte-identical).
- 1.2 `web-private-nic-guard.sh`: refusal after `set -u` (before `EXPECTED_IP=`), with the by-design comment.
- 1.3 `web-private-nic-guard.sh`: `readonly INGEST_URL_PINNED`, equality-gated POST with
  `curl --disable --noproxy '*' -fsS ...`, `unpinned_url` refusal branch, existing WARN branch unchanged,
  `--data-raw "{\"message\":\"$LINE\"}"` byte-preserved.
- 1.4 `web-private-nic-guard.sh`: `--disable --noproxy '*'` first on both heartbeat curls; IMDS curl untouched.
- 1.5 Re-run both suites: all rows green.
- 1.6 Run each row of the plan's Guard Contract matrix ONCE on a scratch copy (script or suite as the row says),
  record RED/GREEN per row for the PR body; no mutation runner is added to the suites.

## Phase 2 - drawdown and bookkeeping

- 2.1 Remove the two files from `scripts/lint-shell-trace-credential-refusal.baseline.txt` and the guard from
  `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`.
- 2.2 Correct the comment above the last two deferral rows in `.claude/hooks/grep-q-pipe-guard.test.sh` ("required"
  becomes "advisory job `lint-bot-statuses`"; precondition now met; no PR number). Comment only; rows stay
  `= | 2` and `= | 4`.

## Phase 3 - verification (record every result)

- 3.1 `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` and the repo-wide form.
- 3.2 `bash scripts/lint-shell-trace-credential-refusal.test.sh`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`.
- 3.3 Carrier-census suites: `cron-egress-enforce-probe`, `web-private-nic-guard`,
  `apps/web-platform/test/infra/betterstack-send-failed-alert`, `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation`,
  `fresh-boot-parity`, `doppler-injection-bound`, `fresh-boot-ready`,
  `soleur-host-bootstrap-observability`, `plugins/soleur/test/cloud-init-user-data-size.test.ts`.
- 3.4 `npx markdownlint-cli2` on the plan and this file; `python3 scripts/lint-shell-capture-exit.py` on both scripts; `python3 scripts/lint-guard-contract.py` and
  `python3 scripts/lint-infra-no-human-steps.py` on the plan, tasks, decision-challenges and each learning.
- 3.5 `bash scripts/test-all.sh --affected` last; paste its verdict line verbatim (state "skipped" if skipped).

## Phase 4 - ship and evidence

- 4.1 File the F1 issue (Sentry-DSN curl family, lockstep across `cron-egress-enforce-probe.sh`,
  `soleur-host-bootstrap.sh`, `workspaces-luks-emit.sh`, plus the Rule D blind spot), with the re-evaluation trigger
  from the plan; label and milestone per roadmap.
- 4.2 PR body: first line answers "does merging THIS alone mutate production?" (yes: infra apply re-provisions the NIC
  guard on web-1 plus a normal image release; no host replaced); then `Ref` lines, premise corrections (advisory-not-required; Class W scope), blast radius, RED/GREEN
  output, deferred list, "not fixed" statement naming the F1 issue.
- 4.3 Learnings (three, under `knowledge-base/project/learnings/`; code-simplicity trimmed five to three):
  - L1 [test-failures] premise scope: a lint's required-ness belongs to the JOB hosting the step (`--changed` is in
    advisory `lint-bot-statuses`, absent from `required-checks.txt` and the ruleset), "Class W" auto-apply is a
    per-workflow `paths:` fact (these two files are not in `apply-deploy-pipeline-fix.yml`), and the baseline
    suppresses by FILE so harden and drawdown together.
  - L2 [security-issues] one credentialed curl can be uneditable in isolation and invisible to the lint at once:
    the Sentry DSN POST is byte-parity-pinned across three files and Rule D does not classify `X-Sentry-Auth`/`$KEY`;
    also a destination pin silently invalidates a harness that fed a synthetic URL, so derive the pinned literal
    from the single `.tf` source in the same change.
  - L3 [test-failures] verify every research-subagent claim at `file:line` before it enters a plan: two false
    carrier claims (size budget, `triggers_replace` membership) in this plan's own research.
- 4.4 Evidence comments on #9217 and #7797.
- 4.5 Post-merge (via `soleur:postmerge`): apply run `success` with the SSH-provisioned leg, no `hcloud_server.web`
  replace in the plan, `SOLEUR_PRIVATE_NIC` rows present after the apply and no `unpinned_url` rows.
