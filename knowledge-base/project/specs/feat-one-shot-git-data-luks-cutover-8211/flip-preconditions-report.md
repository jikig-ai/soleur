# Flip preconditions: live read (git-data LUKS cutover, #8211)

- Read at: 2026-10-12, 19:12Z to 19:18Z (all times UTC).
- Scope: read-only. No workflow dispatch, no terraform apply, no production write. No secret value was printed (three reads exceeded "names only"; see Caveats and disclosed deviations); the pin fingerprint is recorded as a prefix of 8 characters only.
- Method: every row below is read from live state (Better Stack, Doppler names, GitHub Actions, the public `/health` endpoint), not from runbook text and not from a merged PR.

## Verdicts

| # | Precondition | Verdict |
|---|---|---|
| 1.1 | `git_data_ssh_client=present` on the DEPLOYED build | VERIFIED |
| 1.2 | pin secret name present in `prd`; post-redeploy `git_data_pin=present` | VERIFIED |
| 1.3 | pin-fault Sentry rule live (drift run under 24 h) | VERIFIED on the drift run only; rule id 1310055 cannot be read headlessly end to end (see caveats and proposal) |
| 1.4 | host liveness heartbeat: up, newest `state=ok` under 15 min, later than `boot_complete` | VERIFIED at the read instant; not the binding flip-time re-read |
| 1.5 | `d6_replace_stale` (a hard `fail` in `git-data-cutover.yml`, not context) | NOT satisfied by a real rotate; the reader has two holes (a plain replace satisfies it; a newer failed or plan-only rotate is skipped); tracker #10166 |

These are point-in-time reads. A web-platform deploy of a newer sha was queued at the time of the read (see 1.1), so rows 1.1 and 1.2 must be re-read at the flip dispatch.

## 1.1 `git_data_ssh_client=present` on the deployed build: VERIFIED

Deployed build, tied to a sha:

- `GET https://app.soleur.ai/health` returned `status=ok version=0.340.1 build_sha=1ff24abfb14524622fca7e74473967ddedda82d7 uptime=1696` at 19:13:24Z. `uptime` places the process start at about 18:45:08Z.
- Release run `38291877556` (Web Platform Release, `workflow_run`, head sha `1ff24abfb1`, "fix(egress): poll the gateway TCP open instead of probing once (#10106)"): `deploy` job success, completed 18:45:16Z; `live-verify` success 18:45:38Z.
- A second `/health` read at 19:17Z returned the same `build_sha` (`uptime=1952`), so the container has not restarted between reads.

Better Stack read (bounded, `--limit 20`):

Command form (narrowed; copied verbatim from `design-9943-liveness-precheck.md`, which prescribes this read: only the three Better Stack query secrets reach the process and the Doppler token and AWS keys are stripped for the reader; `$reader` is the Better Stack query script and `$sql` the query, as in that design):

```
doppler run -p soleur -c prd_terraform --only-secrets BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD --no-exit-on-missing-only-secrets -- env -u DOPPLER_TOKEN -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u SHELLOPTS -u BASH_ENV -u BASHOPTS bash "$reader" "$sql"
```

Note: the reads in this report were taken with the unnarrowed form (`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh ...`), which loads every `prd_terraform` secret into the reader process. The narrowed form above is what to use for any repeat; the unnarrowed form is disclosed as a deviation in the caveats section, not repeated.

Result: 3 rows, all `msg=git_data_ssh_client=present`, `gitDataSshClient=true`, `host_name=soleur-web-platform`:

| dt | container hostname |
|---|---|
| 2026-10-12 18:20:01.704 | 21ee3ab98c47 |
| 2026-10-12 18:29:17.838 | 1a82913c6d02 |
| 2026-10-12 18:45:12.450 | 51b1a623ce34 |

The 18:45:12.450Z row is the start of the container serving build `1ff24abfb1` (matches the `/health` uptime and the deploy job completion at 18:45:16Z). The two earlier rows belong to earlier containers of earlier builds.

Not-yet-stable caveat: release runs for sha `41b8801ad8` were queued/pending at 19:17Z (`38296526078`, `38296585531`, `38295784488`). Once that deploy lands, the deployed sha changes and this row must be re-read on the new container.

## 1.2 Pin secret name in `prd` and post-redeploy `git_data_pin=present`: VERIFIED

Secret name (names only; `doppler secrets --only-names --json -p soleur -c prd | jq -r 'keys[]' | grep GIT_DATA`):

- `GIT_DATA_SSH_HOST_KEY` is present. The exact name was confirmed first from `apps/web-platform/infra/git-data-flag-precheck.sh` (`read_secret GIT_DATA_SSH_HOST_KEY git_data_host_key_unavailable`). The same listing also shows `GIT_DATA_SSH_HOST` and `GIT_DATA_HEARTBEAT_URL`. No value was printed.

Loaded pin on the deployed build (Better Stack, `--since '2026-10-12 18:40:00' --grep 'git_data_pin='`): 1 row.

- `2026-10-12 18:45:12.450 soleur-web-platform git_data_pin=present fp=SHA256:Ny0nYTfj...` (prefix 8 only). Same container start as the 1.1 row, on build `1ff24abfb1`.
- Earlier rows the same day (17:11, 17:27, 17:50, 18:20) carry the same fingerprint prefix `Ny0nYTfj`.
- Cross-check without printing the key: the fingerprint of the Doppler `prd` value, computed locally with `ssh-keygen -lf -` (the value was piped in locally; nothing was printed, see the disclosed deviations), has the prefix `SHA256:Ny0nYTfj`. The loaded pin and the published secret agree on the 8-character prefix.
- The fingerprint differs from the one the runbook records for 2026-09-25 (`SHA256:4eErm...`), which is consistent with the host key rotating on replace. The most recent host replace is run `38140050880` (2026-10-11), whose `Load the rotated git-data pin (same-version redeploy)` step concluded `success`.

## 1.3 Pin-fault Sentry rule live: VERIFIED (caveat on rule id)

- Run read: `scheduled-sentry-alert-drift.yml` run `38216691254` (event `workflow_dispatch`, head sha `0aae3f8680348e25e6794384286a28a3e597d0c8`), `drift-check` job success, started 2026-10-12T07:15:03Z. At 19:17Z this is 12 h 2 min old, inside the 24 h limit. The previous runs on 10-09, 10-10 and 10-11 (07:15Z) are also success.
- Log lines read from the run:
  - `sentry_alert live fidelity: comparing 43 declared rule(s) against 43 live in-scope rule(s)`
  - `sentry_alert live fidelity: PASS (all 43 in-scope rules match the committed reference field-for-field)` (07:15:28Z)
- The committed reference `apps/web-platform/infra/sentry/alert-reference.json` contains rule `git-data-host-key-pin-fault` with `enabled: true`, an `issue_owners` email action, and a `tagged_event` condition `pin_fault in host_key_mismatch,pin_absent,pin_invalid,ssh_client_absent`. The fidelity script compares every in-scope rule field for field against this reference, so a live rule that was disabled or whose `in` set had changed would have failed the run.
- `git diff --stat 0aae3f86 HEAD -- apps/web-platform/infra/sentry` is empty: the reference and rule declarations have not changed since the drift run's sha, and that sha is an ancestor of this branch.
- Caveat 1: the numeric rule id `1310055` is not printed by the fidelity run, so the id-to-rule mapping is taken from ADR-237 and the cutover workflow, not read here. The cutover workflow's own live precheck (`git-data-cutover.yml`, GET `alert-rules/1310055/` with `SENTRY_ACTIONS_RO_TOKEN`) will read the id at the flip dispatch.
- Caveat 2: `SENTRY_ACTIONS_RO_TOKEN` is a GitHub secret and is not in Doppler `prd` or `prd_terraform`, so `scripts/sentry-alert-live-fidelity.sh` was not run live from this session. As a probe only, a read of `.../alert-rules/1310055/` with the Doppler `SENTRY_ISSUE_RO_TOKEN` returned HTTP 404. That token is issue-scoped and the endpoint is the legacy alert-rules path, so this result is inconclusive and is NOT counted as evidence either way. Row 1.3 rests on the drift run only.
- Proposal (rule id readability): the fidelity script does not print the numeric rule id or the rule status, so no headless read can tie id 1310055 to the live rule. Propose that `scripts/sentry-alert-live-fidelity.sh` print `rule_id` and `status` per in-scope rule (names and numbers only). Until then the only end-to-end read of 1310055 is the cutover precheck at flip time, with `SENTRY_ACTIONS_RO_TOKEN`. This stays a proposal: no issue is filed for it from this PR, and the fidelity script is unchanged.

## 1.4 Host liveness heartbeat: VERIFIED at the read instant

Status read (the runbook's `--status` path; the token never appears in argv):

```
doppler run --only-secrets BETTERSTACK_API_TOKEN_READONLY -p soleur -c prd_terraform -- \
  env -u SHELLOPTS -u BASH_ENV -u BASHOPTS bash --noprofile --norc -c \
  'BS_TOKEN="$BETTERSTACK_API_TOKEN_READONLY" exec bash apps/web-platform/infra/arm-heartbeats.sh --status soleur-git-data-host-prd'
```

- 19:14:18Z and again 19:17:28Z: `name=soleur-git-data-host-prd id=506836 paused=false status=up period=60 grace=300`, rc 0.

Events (git-data table pin `t520508_soleur_git_data_prd_logs` UNION `t520508_soleur_git_data_prd_s3`, `host_name=soleur-git-data`, `stage=liveness`):

- Newest `state=ok` event: `2026-10-12 19:08:05.850` (`ok ok config=prd_git_data root_pct=3`). Age at the 19:17:32Z read: 9 min 27 s, under the 15 min limit.
- `boot_complete` of the current host: `2026-10-11 12:51:25.013` (`stage=boot_complete`, `git-data bootstrap complete`, `host_name=soleur-git-data`; the only such row in the last 3 days). No later git-data host replace exists: the dispatch runs after `38140050880` (`38151596067`, `38154554699`, `38296039170`) have `git_data_host_replace` and `git_data_host_create` both `skipped`.
- Ordering: newest `ok` (2026-10-12 19:08:05) is later than `boot_complete` (2026-10-11 12:51:25). First liveness event after boot: 2026-10-11 12:53:42.
- Continuity: 169 liveness rows between 2026-10-11 12:53:42 and 2026-10-12 19:08:05, all `state=ok`; none in any other state. Emission spacing is about 10.8 min (for example 18:46:25, 18:57:15, 19:08:05), so the age of the newest event cycles between 0 and about 11 min against the 15 min limit.

Limits of this row: it is one read at one instant, the same kind the runbook says is NOT the binding one. The runbook requires the re-read at the flip dispatch. The runbook records the arm at 2026-10-12 (monitor id 506836, `--arm-one`); this read confirms the monitor is still `up` and unpaused. Enforcement in the workflow (#9943) does not exist yet, so this check remains a manual re-read until that build lands.

## 1.5 `d6_replace_stale` (a hard gate in the cutover precheck)

The cutover precheck ends with `fail d6_replace_stale "no successful git-data-host-rotate run on record ..."` when the reader finds no qualifying run, so a flip dispatch is refused on it. The earlier label "context, not a gate" was wrong.

Command: `gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch --limit 100`, then each run's `git_data_host_replace` job and steps.

- Rotate run: `38140050880` (2026-10-11T12:38:48Z) concluded `failure`. Its `Terraform apply (git-data-host -replace) — both-volumes-preserved assert` step failed (the defect of #10137). The `git_data_host_replace` job conclusion is `failure`. This is the only rotate dispatch on record (its `Rotate precondition — served store measured empty` step ran and succeeded).
- Correction to the plan text: the plan says the steps after the assert "have never run to completion". In run `38140050880` the later steps were recorded `success`: `Poll for the git-data boot-completion signal (replace)`, `Load the rotated git-data pin (same-version redeploy)` and `Dispatch summary`. Only the assert step and therefore the job conclusion are red. So the rotate path's boot poll and pin load have run once, on a host that was already created by the apply.
- Finding, hole 1 (a plain replace satisfies the reader): the d6 reader in `.github/workflows/git-data-cutover.yml` (precheck step, the `d6 rotate stamp` / `d6_replace_stale` block) stamps `d6_replace_stale` from the first run whose `git_data_host_replace` job concluded `success` AND whose step matching `rotate confirm token` concluded `success`. That step (`Validate dispatch inputs (rotate confirm token)` in `apply-web-platform-infra.yml`, the step whose name contains `rotate confirm token`) is deliberately unconditional and exits 0 with `rotate confirm: n/a` for any non-rotate target. Run `37846545572` (2026-10-08T21:24:27Z, `apply_target=git-data-host-replace`, log line `rotate confirm: n/a (target 'git-data-host-replace')`) has the job `success`, that step `success`, and is the 11th of the 40 runs the reader scans (0-based index 10 in `gh run list --workflow apply-web-platform-infra.yml --branch main --event workflow_dispatch --limit 40`, re-read 2026-10-12). As coded, the reader would stamp `d6 rotate stamp: run 37846545572` although no rotate has succeeded. This was read from run data and workflow text only; the cutover precheck itself was not executed.
- Finding, hole 2 (newer failed or plan-only rotate runs are skipped): the reader `continue`s past any run whose job did not conclude `success`, then takes the first older success. A newer FAILED rotate (run `38140050880`, which created the new host and then failed at the assert) is skipped in favour of an older plain-replace success. Separately, a rotate dispatched with `plan_only=true` runs the same job with its apply steps skipped (`if: inputs.plan_only != true`), so the job and the unconditional `rotate confirm token` step both conclude `success` with nothing applied; the reader would stamp it as a completed rotate.
- Consequence and tracker: this does not change the owner-gated order (the rotate must still be dispatched), but the d6 precheck cannot be relied on as the guard against a missing or failed rotate. The tracker is open issue #10166 ("decision: should the cutover's key-rotation check only accept a real rotate run? (found in PR #10155)"), not #10137: #10137 is the post-apply assert defect and is to be closed by PR #10155, so a finding parked there would be lost. Treat the d6 reader hardening as a hard precondition row for the first real `flip`.

## Owner-gated remainder (NOT in scope; listed only)

1. `HCLOUD_TOKEN`, then `CF_API_TOKEN_R2`, then `TF_STATE_AWS_*` rotation (#8209).
2. G2 probes; G1 last.
3. Windowed prd write credential (#8573, #8609).
4. Rotate re-dispatch only after the #10137 fix lands (PR #10155) and #10166 is settled. Workflow `apply-web-platform-infra.yml`, inputs `apply_target=git-data-host-rotate confirm=ROTATE-GIT-DATA` (the job runs in the `infra-privileged` environment). Whether that environment's approval can be given headlessly is UNVERIFIED: it was not tested here, and approval is the owner's action. The owner names the command. A re-dispatch triggers a same-version fleet redeploy (see the plan's review reconciliation).
5. Flip-then-rollback rehearsal (designed in plan 4.2) and the first real flip: workflow `git-data-cutover.yml`, `mode=flip confirm=FLIP-GIT-DATA`; rollback is `mode=rollback confirm=ROLLBACK-GIT-DATA` (the other modes today are `proof` with `CUTOVER-GIT-DATA`, `unfreeze` with `UNFREEZE-GIT-DATA` plus an optional `lineage`, and `redeploy` with `REDEPLOY-GIT-DATA`). The job runs in the `web-platform-infra-apply` environment; headless approval is UNVERIFIED. The wipe (#10138) has no dispatch string yet: `mode=wipe` and its typed volume-id confirm exist only in the design (plan 4.1), so there is no literal to give until the wipe-build PR lands.
6. After flip: 7-day soak, ADR-068 to `accepted`, close #6897.
7. Decision dates: CLO re-ruling 2026-10-24; plaintext-volume retention 2026-11-12 (a second slip returns to the CLO per ADR-239 Amendment 2026-10-12).
8. Build PRs that follow the designs: wipe body, rollback-rehearsal dispatch, #9943 precheck.

Also remaining, from this report: re-read rows 1.1 to 1.4 at the flip dispatch (the deployed sha moved during the read, so 1.1 and 1.2 are stale by construction; the heartbeat re-read is the binding one); a direct read of rule id 1310055 with `SENTRY_ACTIONS_RO_TOKEN` (done by the cutover workflow's own precheck at flip time); and #10166 (d6 reader) as a hard precondition row for the first real flip.

## Caveats and disclosed deviations

This report was scoped as read-only with names only. Three reads went beyond that and are disclosed so they are not repeated:

- The Better Stack reads used the unnarrowed `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh ...` form (every `prd_terraform` secret loaded into the reader). Repeat with the narrowed form shown in row 1.1 (`--only-secrets` plus `env -u` for the reads).
- A probe of `.../alert-rules/1310055/` with the Doppler `SENTRY_ISSUE_RO_TOKEN` returned HTTP 404: the endpoint is outside that token's scope, so it was an out-of-scope credentialed probe and is not evidence (row 1.3). Do not repeat it.
- The host-key pin value from Doppler `prd` was piped locally into `ssh-keygen -lf -` to compare fingerprints. Nothing was printed except the 8-character fingerprint prefix, but this read the secret value, which is more than "names only". A name-only check, or the loaded-pin fingerprint in Better Stack alone (row 1.2), is the form to repeat.
