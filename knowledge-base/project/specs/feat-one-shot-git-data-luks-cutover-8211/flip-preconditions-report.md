# Flip preconditions: live read (git-data LUKS cutover, #8211)

- Read at: 2026-10-12, 19:12Z to 19:18Z (all times UTC).
- Scope: read-only. No workflow dispatch, no terraform apply, no production write. No secret value was printed; the pin fingerprint is recorded as a prefix of 8 characters only.
- Method: every row below is read from live state (Better Stack, Doppler names, GitHub Actions, the public `/health` endpoint), not from runbook text and not from a merged PR.

## Verdicts

| # | Precondition | Verdict |
|---|---|---|
| 1.1 | `git_data_ssh_client=present` on the DEPLOYED build | VERIFIED |
| 1.2 | pin secret name present in `prd`; post-redeploy `git_data_pin=present` | VERIFIED |
| 1.3 | pin-fault Sentry rule live (drift run under 24 h) | VERIFIED (rule id 1310055 not read directly; see caveat) |
| 1.4 | host liveness heartbeat: up, newest `state=ok` under 15 min, later than `boot_complete` | VERIFIED at the read instant; not the binding flip-time re-read |
| 1.5 | `d6_replace_stale` (context, not a gate) | NOT satisfied by a real rotate; reads as satisfied by a plain replace (finding) |

These are point-in-time reads. A web-platform deploy of a newer sha was queued at the time of the read (see 1.1), so rows 1.1 and 1.2 must be re-read at the flip dispatch.

## 1.1 `git_data_ssh_client=present` on the deployed build: VERIFIED

Deployed build, tied to a sha:

- `GET https://app.soleur.ai/health` returned `status=ok version=0.340.1 build_sha=1ff24abfb14524622fca7e74473967ddedda82d7 uptime=1696` at 19:13:24Z. `uptime` places the process start at about 18:45:08Z.
- Release run `38291877556` (Web Platform Release, `workflow_run`, head sha `1ff24abfb1`, "fix(egress): poll the gateway TCP open instead of probing once (#10106)"): `deploy` job success, completed 18:45:16Z; `live-verify` success 18:45:38Z.
- A second `/health` read at 19:17Z returned the same `build_sha` (`uptime=1952`), so the container has not restarted between reads.

Better Stack read (bounded, `--limit 20`):

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since '2026-10-12 18:00:00' --grep git_data_ssh_client= --limit 20
```

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

- `GIT_DATA_SSH_HOST_KEY` is present. The exact name was confirmed first from `apps/web-platform/infra/git-data-flag-precheck.sh` (`read_secret GIT_DATA_SSH_HOST_KEY git_data_host_key_unavailable`, line 282). The same listing also shows `GIT_DATA_SSH_HOST` and `GIT_DATA_HEARTBEAT_URL`. No value was printed.

Loaded pin on the deployed build (Better Stack, `--since '2026-10-12 18:40:00' --grep 'git_data_pin='`): 1 row.

- `2026-10-12 18:45:12.450 soleur-web-platform git_data_pin=present fp=SHA256:Ny0nYTfj...` (prefix 8 only). Same container start as the 1.1 row, on build `1ff24abfb1`.
- Earlier rows the same day (17:11, 17:27, 17:50, 18:20) carry the same fingerprint prefix `Ny0nYTfj`.
- Cross-check without printing the key: the fingerprint of the Doppler `prd` value, computed locally with `ssh-keygen -lf -`, has the prefix `SHA256:Ny0nYTfj`. The loaded pin and the published secret agree on the 8-character prefix.
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

## 1.5 `d6_replace_stale` (context, not a gate)

Command: `gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch --limit 100`, then each run's `git_data_host_replace` job and steps.

- Rotate run: `38140050880` (2026-10-11T12:38:48Z) concluded `failure`. Its `Terraform apply (git-data-host -replace) — both-volumes-preserved assert` step failed (the defect of #10137). The `git_data_host_replace` job conclusion is `failure`. This is the only rotate dispatch on record (its `Rotate precondition — served store measured empty` step ran and succeeded).
- Correction to the plan text: the plan says the steps after the assert "have never run to completion". In run `38140050880` the later steps were recorded `success`: `Poll for the git-data boot-completion signal (replace)`, `Load the rotated git-data pin (same-version redeploy)` and `Dispatch summary`. Only the assert step and therefore the job conclusion are red. So the rotate path's boot poll and pin load have run once, on a host that was already created by the apply.
- Finding (reader reads as satisfied by a plain replace): the d6 reader in `.github/workflows/git-data-cutover.yml` (precheck step, around line 270) stamps `d6_replace_stale` from the first run whose `git_data_host_replace` job concluded `success` AND whose step matching `rotate confirm token` concluded `success`. That step (`Validate dispatch inputs (rotate confirm token)` in `apply-web-platform-infra.yml`, around line 3745) is deliberately unconditional and exits 0 with `rotate confirm: n/a` for any non-rotate target. Run `37846545572` (2026-10-08T21:24:27Z, `apply_target=git-data-host-replace`, log line `rotate confirm: n/a (target 'git-data-host-replace')`) has the job `success`, that step `success`, and sits at position 10 of the 40 runs the reader scans. As coded, the reader would stamp `d6 rotate stamp: run 37846545572` although no rotate has succeeded. This was read from run data and workflow text only; the cutover precheck itself was not executed. This does not change the owner-gated order (the rotate must still be dispatched), but it means the d6 precheck cannot be relied on as the guard against a missing rotate. It belongs on #10137 as a follow-up, not in this PR's scope.

## Owner-gated remainder (NOT in scope; listed only)

1. `HCLOUD_TOKEN`, then `CF_API_TOKEN_R2`, then `TF_STATE_AWS_*` rotation (#8209).
2. G2 probes; G1 last.
3. Windowed prd write credential (#8573, #8609).
4. Rotate re-dispatch (`apply_target=git-data-host-rotate`, `confirm=ROTATE-GIT-DATA`) only after the #10137 fix merges; the owner names the command.
5. Flip-then-rollback rehearsal (designed in plan 4.2); `flip`; the wipe (#10138; designed in plan 4.1).
6. After flip: 7-day soak, ADR-068 to `accepted`, close #6897.
7. Decision dates: CLO re-ruling 2026-10-24; plaintext-volume retention 2026-11-12 (a second slip returns to the CLO per ADR-239 Amendment 2026-10-12).
8. Build PRs that follow the designs: wipe body, rollback-rehearsal dispatch, #9943 precheck.

Also remaining, from this report: re-read rows 1.1 to 1.4 at the flip dispatch (the deployed sha is about to change; the heartbeat re-read is the binding one); and a direct read of rule id 1310055 with `SENTRY_ACTIONS_RO_TOKEN` (done by the cutover workflow's own precheck at flip time).
