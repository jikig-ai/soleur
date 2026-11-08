---
title: Key rotation for the non-tunnel secrets (key-rotate.yml)
type: runbook
status: active
issue: 11294
related: [11294, 10205, 11920, 11922, 11923, 11927, 11928, 9294]
related_adrs: [ADR-317, ADR-307, ADR-241]
---

# Key rotation for the non-tunnel secrets

One dispatch-only workflow, `.github/workflows/key-rotate.yml` (body `scripts/key-rotate.sh`, decision record
[ADR-317](../architecture/decisions/ADR-317-key-rotation-second-dispatch-only-route-sourcing-the-inngest-route.md)), rotates ONE
secret per dispatch and then redeploys the web fleet canary-then-prod. This page is the procedure; the rationale lives in the ADR.
Everything here runs from GitHub Actions, the Doppler CLI of the owner's own shell, and Better Stack reads. There is no host shell step
anywhere in this procedure and none is needed.

`tunnel_secret` is out of scope and stays last: a real rotation replaces the tunnel and rebuilds web-2, roll-forward only
(ADR-307 amendment of 2026-10-29). The Inngest `signing`/`event` pair of the **production** scheduler has its own route
(`inngest-key-rotate.yml`, see [inngest-server.md](./inngest-server.md) "Key rotation"). This route covers the seven keys below.

## Who may dispatch, and what the confirm is

- `mode=plan` is the read-only rehearsal. It needs no confirm and no attestation. It runs under the `infra-privileged` environment,
  reads the chosen key's Doppler copies value-silently (hashes only, never printed), plans, and checks the plan against the gate. It
  writes nothing.
- `mode=rotate` needs the typed confirm `ROTATE-<KEY>-<YYYY-MM-DD>` (the key name upper-cased, the UTC date of the run), the
  `quiet_window` attestation, and for the webhook secret the `webhook_patch_ready` attestation.
- **The confirm is a fat-finger guard, not an authorization.** The authorization mechanism is the `key-rotate-approval`
  environment: every `mode=rotate` run parks at a credential-free `approve` job in "Waiting" until a listed reviewer approves it
  in the Actions UI — see the approval section below. The guard additionally refuses a ref other than `main` (`ref_refused`), a
  bot or empty actor (`actor_refused`) and any actor outside the committed owner allowlist (`actor_not_owner`), and it live-reads
  the environment's `protection_rules` before anything writes: an absent environment, a missing `required_reviewers` or
  branch-policy rule, or a failed read refuses `approval_environment_unprotected`. A personal access token can still START the
  dispatch, but the run cannot pass `approve` — the reviewer's click is a distinct human act; a PAT approval of the job is the
  owner's click by design. **An agent may dispatch `rotate` only under the owner's fresh, per-command, in-session go
  naming the exact full command; the reviewer click is never delegated.**
- One key per dispatch. The confirm names exactly one key.

### The approval gate (`key-rotate-approval`)

Every `mode=rotate` dispatch of this workflow — and every `mode=rotate`/`mode=converge` dispatch of the sibling
`inngest-key-rotate.yml` — parks at an `approve` job bound to the `key-rotate-approval` environment (Terraform-provisioned:
required reviewer user 54279, a `main`-only deployment branch policy, `prevent_destroy` on the policy). `mode=plan` never parks:
it writes nothing and binds no approval. The run shows as "Waiting" in the Actions UI; the reviewer opens the run and clicks
**Approve**, and the production-mutating jobs start only after that. The job holds no secrets and writes nothing — it only stamps
`approval_epoch`, and `authorization_stale` measures from THAT stamp, not the dispatch time, so an approval queued for any length
cannot make the run self-refuse. If a dispatch refuses `approval_environment_unprotected`, verify the environment before
re-dispatching:

```bash
gh api repos/jikig-ai/soleur/environments/key-rotate-approval --jq '.protection_rules[].type'
```

Both `required_reviewers` and `branch_policy` must be listed. If either is missing, restore the environment through the infra
apply path (`apply-web-platform-infra.yml` owns the `github_repository_environment.key_rotate_approval` target) — do NOT
hand-edit it, and do not run the rotate anyway: the guard refuses for a reason.

**Environment split** (live-verified 2026-11-08): `rotate`/`converge` park at `key-rotate-approval` (required reviewer
`deruelle`, `main`-only branch policy); `mode=plan` and the apply path (`apply`/`clear`; `apply1`/`reboot`/`apply2` on the
inngest route) bind `infra-privileged` (branch policy, zero required reviewers, no park); `guard`/`redeploy`/`notify` bind
no environment.

**Who clicks what.** Under the 2026-11-08 ruling, an agent may dispatch `rotate`/`converge` ONLY under a fresh,
per-command, in-session owner go naming the exact full command; the reviewer click on `key-rotate-approval` is NEVER
delegated — the owner opens the run and approves it themselves. The approval tap should land inside a measured
release-quiet stretch: the apply path re-checks in-flight runs itself, so a run parked at `approve` CAN still refuse
post-approval if a conflicting run started while it waited.

## The seven keys

| `key` input | What changes | Consumer and pickup | Notes |
|---|---|---|---|
| `inngest_manual_trigger_secret_dev` | `random_id` and `soleur/dev INNGEST_MANUAL_TRIGGER_SECRET` (replaced together) | developer shells and dev servers read `soleur/dev` at their own start; no production container consumes it, so the redeploy is a rehearsal of the route's last leg, not a pickup (#11927) | shakedown key, rotate it first |
| `inngest_manual_trigger_secret_prd` | `random_id` and `soleur/prd INNGEST_MANUAL_TRIGGER_SECRET` (replaced together) | host-side readers pick it up at apply; the routes `trigger-cron`, `schedule-reminder`, `cohort` and `home-census` return 401 on a host whose container has not swapped yet | — |
| `inngest_signing_key_dev` | `random_id` and `soleur/dev INNGEST_SIGNING_KEY` | as the dev manual trigger | dev only |
| `inngest_event_key_dev` | `random_id` and `soleur/dev INNGEST_EVENT_KEY` | as the dev manual trigger | dev only |
| `kb_drift_ingest_signing_key` | `random_id` only; BOTH copies (`soleur/prd_kb_drift_walker` and `soleur/prd`) update in place in the same apply | the walker reads its config at its next run; the `soleur/prd` copy needs the redeploy | refuses inside the 03:00-03:30 UTC window and while a walker run is in flight |
| `egress_audit_ingest_token` | `random_id`; CURRENT updates in place and `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` is `-replace`d with the old value in the SAME apply (apply-A), then `-replace`d back to empty by a later clear apply | the app accepts CURRENT+PREVIOUS after the redeploy; Vector reads CURRENT only at process start, so the run restarts `vector.service` on every web host through the deploy webhook before PREVIOUS is cleared (#11920) | see the egress sequence below; a failed host keeps PREVIOUS — the old token stays valid (lossless) |
| `github_webhook_secret` | `random_id` only; `soleur/prd GITHUB_APP_WEBHOOK_SECRET` updates in place | the verifier uses ONE secret (a grace window is #11922); deliveries fail 401 until the owner step below | `webhook_patch_ready=true`, ends `owner_step_pending` |

## Dispatch order

1. `mode=plan` for the key you are about to rotate. The first plan dispatch also proves that `DOPPLER_TOKEN_TF` can read the copies
   (`copy_unreadable` otherwise); that read is unverified until it runs.
2. Dev shakedown first: `inngest_manual_trigger_secret_dev`, then `inngest_signing_key_dev` and `inngest_event_key_dev`. The first dev
   rotate is also the first test of two premises that nothing has observed yet: that `-replace` of a `doppler_secret` carrying
   `ignore_changes=[value]` recreates it with the new value (the `value_unchanged` verdict is the detector), and that `-replace` of an
   address absent from state plans a plain create. Exercise the second one with a deliberately interrupted **dev** rehearsal before any
   `_prd` rotate.
3. `kb_drift_ingest_signing_key`, started outside the window the guard computes (roughly 00:45 to 03:30 UTC; the guard prints the
   refusal if you are inside it).
4. `egress_audit_ingest_token` — the first `_prd`-class rotate exercises the full approval → vector-restart → clear chain; the
   run parks at `approve`, so leave the reviewer click for a window where you can watch the whole run.
5. `inngest_manual_trigger_secret_prd`.
6. `github_webhook_secret` last, in a quiet window, with the App private key at hand.

The plan rehearsal command shape (no confirm):

```bash
gh workflow run key-rotate.yml -f mode=plan -f key=inngest_manual_trigger_secret_dev
```

The rotate command shape (the owner words the go — fresh, per-command, in-session, naming the exact full command; an
agent may then run the dispatch under that go, but the approval click on `key-rotate-approval` is always the owner's):

```bash
gh workflow run key-rotate.yml -f mode=rotate -f key=inngest_manual_trigger_secret_dev \
  -f confirm=ROTATE-INNGEST_MANUAL_TRIGGER_SECRET_DEV-<YYYY-MM-DD> -f quiet_window=true
```

Find the run you just dispatched, watch it, and read its verdicts and per-copy states:

```bash
gh run list --workflow key-rotate.yml --event workflow_dispatch --limit 1 --json databaseId,status,conclusion
gh run watch <id> --exit-status
gh run view <id> --log | grep -E 'key-rotate (verdict|check)'
gh run view <id> --log | grep -E '(pre|post)-state copy'
```

The first command prints the run id (`databaseId`). `gh run watch --exit-status` exits non-zero when the run fails. The third prints
every verdict line and every guard boolean (`key-rotate check <name>=<bool>`); the fourth prints the per-copy states
(`present`, `absent`, `present-unchanged`, `present-changed`, `unknown`, never a value). **Exit codes:** `guard_ok`, `plan_ok` and
`rotate_ok` exit 0; every other verdict exits non-zero.

### What `plan_ok` tells you

`mode=plan` ends `plan_ok` when the gate passes, with exit 0, and its line ends with `rotate_would_refuse=<token|none>`. The field is
report-only: it names the first rotate-only rung this key would meet right now (`approval_environment_unprotected`,
or a re-check: `run_in_flight`, `run_list_unreadable`, `kb_drift_cron_window`, `kb_drift_walker_in_flight`; an earlier `plan` run
that is still running counts as `run_in_flight` too, because a rotate would refuse on it). It is **advisory**: `plan_ok` with `rotate_would_refuse` other than `none` means a rotate dispatched now
would refuse, not that the plan failed. Not evaluated by `plan` (they need the dispatch inputs or the issues API, which the apply job
does not hold, or that would measure the plan run itself): `authorization_stale` (a plan run would report its own age, not the age a later
rotate dispatch would have), `confirm_mismatch`, `quiet_window_missing`, `rerun_refused`, `webhook_patch_not_ready`, `owner_step_open`.

### The redeploy wait (after a landed write)

The redeploy job's re-check step never refuses on staleness, the kb window or `quiet_window`: the new value is already landed. It polls
read-only (a related workflow in flight, an earlier `key-rotate.yml` run, the kb-drift walker) every 30 s for at most 480 s, then
refuses `rotated_redeploy_failed` naming the blocking workflow. Runs of `web-platform-release.yml` and `apply-deploy-pipeline-fix.yml`
(members of the `web-1-swap` group) are not counted as blockers there, because their deploy jobs are queued behind this job's own hold
and the group serializes the swap anyway (UNVERIFIED live: the first dev rehearsal settles it). Every other related workflow still blocks.

## The egress rotate sequence (`egress_audit_ingest_token`)

The egress token rotates losslessly through a grace window: for a bounded period the app accepts BOTH the new and the old token, so
in-flight Vector sends are never rejected. The run's legs, in order:

1. **Apply-A.** One Terraform apply mints the new `EGRESS_AUDIT_INGEST_TOKEN`, updates the `doppler_secret` in place, AND
   `-replace`s `doppler_secret.egress_audit_ingest_token_previous` with the pre-apply value of the old CURRENT. The old value is
   read value-silently into `TF_VAR_egress_audit_ingest_token_previous` — it never reaches argv or a log.
2. **Fleet redeploy.** The app restarts on every host and begins accepting CURRENT+PREVIOUS (`configuredTokens` in
   `server/egress-audit-ingest.ts`). The redeploy strictly precedes the Vector restart: a Vector restarted first would send the
   new token to an app still on the old env, and every bucket would be rejected.
3. **Vector restart, every web host.** The run dispatches `restart vector _ _` to the deploy webhook with the peers roster. Each
   host runs `sudo /usr/bin/systemctl try-restart vector.service` — the exact argv of the existing `DROPIN_TRY_RESTART` sudoers
   grant — verifies `is-active` plus an `ActiveEnterTimestamp` delta, and writes a `component=vector` deploy-status frame
   (`reason=success`, `vector_restart_failed` or `vector_restart_unverified`). The leg is green only when EVERY host reports a
   fresh success frame after the leg's baseline; a failed, unverified or silent host fails the run. `try-restart` deliberately
   does not start an inactive unit — a host whose Vector was already down reports `vector_restart_unverified`, not success.
4. **Clear apply.** Only after every host is verified does a second apply `-replace` PREVIOUS back to the empty default.
   `doppler secrets get EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS -p soleur -c prd` returning empty is the post-check.

Any non-success before the clear apply leaves PREVIOUS populated — deliberately: the old token stays accepted, the lossless
direction. The notify job files the action-required issue; the fix is a fresh `rotate` (idempotent). The **PREVIOUS lifecycle**
is Terraform-owned end to end: `ignore_changes=[value]` makes routine applies diff-free on it (no drift noise, and a merge apply
can never early-clear the grace token); it is set ONLY by apply-A's `-replace` and cleared ONLY by the clear apply's `-replace`.
A non-empty PREVIOUS after a supposedly clean run means the clear apply did not land — treat it as the failure above, not as
drift, and do NOT clear it by hand through the Doppler CLI (an untracked mutation of Terraform-owned state).

No host shell is needed anywhere in this sequence: the restart lever rides the same `/hooks/deploy` + `/hooks/deploy-peer` +
`/hooks/deploy-status` channel as the redeploy, and the sudoers grant it uses was already delivered.

## Before a `prd` manual-trigger rotation

Do not arm reminders and do not tag cohorts while it runs: between the apply and the container swap a `schedule-reminder` call or a
`users.cohort_key` write through `/api/internal/cohort` answers 401 on a skewed host and is not retried.

## Refusals (nothing written)

A refusal before any write prints one fixed verdict (`key-rotate verdict=<token>`), writes nothing, fails the job and files no issue.
Every token below is in `bash scripts/key-rotate.sh --print-contract`; the suite fails when a printed token is missing from this page.
The three passing verdicts (`guard_ok`, `plan_ok`, `rotate_ok`) are the first rows.

| Verdict | Cause | Next action |
|---|---|---|
| `guard_ok` | passing: every guard rung passed (exit 0; the guard wrote nothing) | none: the apply job runs |
| `plan_ok` | passing: the plan gate passed in `mode=plan` (exit 0; nothing was applied); `rotate_would_refuse` is advisory (see above) | read `rotate_would_refuse`, then dispatch the rotate when it is `none` |
| `rotate_ok` | passing: the apply landed, every copy changed and the fleet redeploy was confirmed by `track.sh` (exit 0); for egress it also means every web host reported a fresh `component=vector` success frame AND the clear apply emptied PREVIOUS | none (it does not prove each consumer picked up the value) |
| `vector_restarted` | passing interim marker (egress only): the fleet redeploy and the per-host vector restart were confirmed; the PREVIOUS clear leg is next — the terminal green is still the rotate-complete verdict above | none unless the run stalls: if it never reaches the terminal green, the clear leg failed — see `previous_not_cleared` below |
| `ref_refused` | dispatched from a ref other than `main` | dispatch from `main` |
| `inputs_invalid` | mode not `plan`/`rotate`, or key not one of the seven (an API dispatch bypasses the choice list) | correct the input |
| `actor_refused` | `github.actor` or `github.triggering_actor` is empty or a `[bot]` | dispatch as the owner, not through a bot |
| `actor_not_owner` | an actor outside the committed owner allowlist | the dispatch must run under a fresh, per-command owner go (an agent may run it under that go); the approval click stays the owner's |
| `rerun_refused` | `GITHUB_RUN_ATTEMPT` is not 1 (a re-run would reuse the first attempt's go) | dispatch a fresh run; only `plan` may be re-run |
| `confirm_mismatch` | the typed confirm is not exactly `ROTATE-<KEY>-<YYYY-MM-DD>` (key upper-cased, UTC date of the run) | retype it for today's UTC date |
| `quiet_window_missing` | `quiet_window` was not attested | check the attestation conditions, then set `quiet_window=true` |
| `approval_environment_unprotected` | the `key-rotate-approval` environment is absent, its `protection_rules` lack `required_reviewers` or the branch policy, or the live read failed (fail-closed) | verify with `gh api repos/jikig-ai/soleur/environments/key-rotate-approval --jq '.protection_rules[].type'`; restore it through the infra apply path, then re-dispatch |
| `webhook_patch_not_ready` | `github_webhook_secret` without `webhook_patch_ready=true` | have the App private key at hand, then set it |
| `owner_step_open` | an `owner_step_pending` issue for the webhook secret is open, or its label or listing is unreadable (fails closed) | finish the owner step and close that issue |
| `kb_drift_cron_window` | the remaining apply-and-redeploy budget would overlap 03:00-03:30 UTC | dispatch outside roughly 00:45 to 03:30 UTC |
| `kb_drift_walker_in_flight` | a `kb-drift-walker.yml` run is queued, running or waiting | wait for it to finish |
| `run_in_flight` | a related workflow, or an EARLIER `key-rotate.yml` run, is running or queued | wait for it, then re-dispatch |
| `run_list_unreadable` | the run listing failed (fails closed, never read as none-in-flight) | re-dispatch; check GitHub API status if it repeats |
| `redaction_coverage_unconfirmed` | the redaction suite on the dispatched ref exited non-zero or lacks a labelled tainted/deposed/drift row | expected until the filter-fix PR (#11930) is on `main`; the run log lists the missing labels |
| `credential_absent` | `GH_TOKEN`, `GITHUB_REPOSITORY`, a Terraform backend credential, `DOPPLER_TOKEN` or `DOPPLER_TOKEN_TF` is missing | fix the loader or secret |
| `authorization_stale` | the approval is older than 60 minutes (measured from the approve job's `approval_epoch` output, so the queue wait itself never counts) or the UTC date rolled, or fewer than the apply bound plus 240 s remain in the apply step | re-dispatch under a fresh confirm and a fresh approval |
| `copy_unreadable` | a Doppler copy could not be read value-silently; the log prints a fixed cause class (`listing_failed`, `listing_empty`, `listing_timeout`, `read_failed`, `read_empty`, `read_timeout`) | fix the `DOPPLER_TOKEN_TF` scope or the config, then re-dispatch |
| `plan_gate_refused` | the plan touches an address or action outside the key's rows (the log names at most five offenders) | stop and read the plan gate rows; do not widen the gate without an ADR |
| `replace_not_requested` | a replace was planned for a reason other than the requested `-replace` (for example a tainted resource) | resolve the tainted resource through the infra apply path, then re-plan |
| `terraform_failed` | init, plan or show failed; the log prints a fixed cause class (`backend_auth`, `provider_auth`, `state_lock`, `init`, `config`, `timeout`, `other`), never a byte of the stream | act on the class; the stream stays on the runner |
| `partial_absent_state` (before the apply) | some copies present, some absent | see the verdict table below: recreate the missing copy first |

## Verdicts, state and recovery

After the apply the script classifies every copy
(`present-unchanged`, `present-changed`, `absent`, `unknown`) and ends with exactly one verdict, with this precedence:
`post_hash_unreadable`, then `partial_absent_state`, then `value_unchanged`, then `copies_differ`. There is **no converge mode and no
redeploy-only mode**: recovery is a fresh `rotate` of the same key under a fresh typed confirm (it mints another value, which is
harmless for all keys in scope; roll-forward is the only direction because the previous value is not retained — egress excepted,
which retains the old value in `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` for the bounded grace window above and clears it before
`rotate_ok`).

| Verdict | Doppler | Terraform state | Running containers | Next safe action |
|---|---|---|---|---|
| `apply_failed` | per-copy classification in the run log | possibly partial (a replace may have destroyed and not created) | old | fresh `rotate`; if any copy is `absent` it is urgent, because a container restart now starts without the secret |
| `post_hash_unreadable` | unknown | new | old | fresh `rotate`; the value is unknown, not unchanged |
| `value_unchanged` | OLD | new `random_id` | old | stop and read the ADR item on the `ignore_changes` premise before re-dispatching; a repeat means the premise is false |
| `copies_differ` (kb_drift) | both present, unequal | new | old | fresh `rotate` outside the cron window |
| `partial_absent_state` (single-copy key, copy absent) | absent | partial | old | URGENT, not auto-repaired: do not restart anything; run the recovery `rotate` now (every copy absent is the shape a rotate recovers) |
| `partial_absent_state` (kb_drift, copies mixed) | some present, some absent | partial | old | URGENT, not auto-repaired: do not restart anything. A rotate refuses identically while the copies are mixed: recreate the missing copy in Doppler (or accept the mixed state), then rotate |
| `rotated_redeploy_failed` | new | new | old, or a MIXED fleet if the canary swapped and prod did not | fresh `rotate` (kb_drift: the next 03:00 UTC walker run is rejected until a redeploy lands; manual trigger prd: `soleur:trigger-cron` answers 401; dev keys: none; egress: the vector-restart leg and the clear apply land here too — PREVIOUS is retained, the old token stays accepted, and the run log names the host that missed its fresh `component=vector` success frame). The new value is landed; the redeploy re-check never refuses on staleness, the kb window or `quiet_window`: it waits up to 480 s (30 s polls) for a blocking related run, an earlier run or a walker to clear, and the verdict names the workflow that blocked it |
| `previous_not_cleared` (egress) | CURRENT new; `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` still set | PREVIOUS populated | new | the old token stays accepted — the lossless direction. Re-dispatch the rotate (the clear leg re-runs); if it refuses again, clear `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` by hand in Doppler soleur/prd |
| `previous_not_staged` (egress) | CURRENT new; `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` absent or empty after apply-A (the staged old value did not land, or reads back wrong) | PREVIOUS empty | old | the old token is accepted NOWHERE — the lossy direction: every host still on the old env is rejected. Redeploy the web fleet NOW so hosts pick up the new CURRENT; if old-env hosts must be served first, set `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` in Doppler soleur/prd to the prior token value (recoverable from a running host's env or the Doppler audit log — drift-free under `ignore_changes`), then re-dispatch the rotate to land the clear |
| `owner_step_pending` | new | new | new | the single owner action below (the issue carries no re-dispatch command) |
| `job_cancelled` | unknown | unknown | unknown | a job was cancelled or killed after a write may have happened and left no stop sentence; the issue says `no write_started marker seen` when the apply never reported one. Read the run, then treat it as the nearest verdict above |
| `issue_unfiled` | as the verdict that preceded it | as that verdict | as that verdict | the `action-required` issue could not be filed (listing failed or truncated, missing label, create did not stick); the red run is the only record. List it with `gh run list --workflow key-rotate.yml --status failure`, read the verdict with the recipe above, and file the issue by hand |
| `internal_error` | unknown | unknown | unknown | a setup or fixed-vocabulary failure of the script itself (xtrace refused, a sourced symbol missing, an unknown token, the temp dir); nothing about a key is implied. Read the run log |

Hold merges to `main` after `apply_failed` or `partial_absent_state` until a recovery `rotate` has landed: a merge triggers the infra
apply, a full Terraform apply against a state this route left partial.

Restart-while-absent consequence per key: manual trigger, 503 on `/api/internal/*` (old containers: 401); webhook, 500 on every
delivery (while the secrets disagree, deliveries are rejected 401 and GitHub does not retry them); kb_drift, 500 on ingest (the 03:00
UTC walker run is rejected 401 until the copies agree and a redeploy lands). The stop sentence and the issue name this per key. On the all-absent recovery path the redeploy leg is mandatory and the log says the old value survives only in running
containers.

Every verdict except `rotate_ok` and `plan_ok` fails the job, and a failure after the apply files ONE `action-required` issue titled
`key-rotate <key> <verdict> (run <id>)` from the `notify` job (de-duplicated on key, verdict and run; a different verdict opens a new
issue, and a re-run of the notify job adds nothing to an identical open issue). On `rotate_ok`, and on `owner_step_pending`, the key's
earlier open `key-rotate` issues are closed (never an `owner_step_pending` one); a failed close prints a `::warning::`. `rotate_ok` means the fleet redeploy was confirmed by `track.sh`; it does not mean each consumer was individually verified.

## The GitHub webhook owner step

After a good redeploy the workflow ends `owner_step_pending` on purpose and files an issue labelled `owner_step_pending`. The single
remaining action, done by the owner (the App private key is needed; an agent never does this without an owner ruling):

1. Update the GitHub App webhook secret with the new value of `GITHUB_APP_WEBHOOK_SECRET`, following
   [github-app-provisioning.md](./github-app-provisioning.md) Step 4 (the command block there reads the private key from the isolated
   project `soleur-github-app`, config `prd`).
2. Redeliver the failed deliveries from the App's Advanced settings, starting at the timestamp of the first container swap in the run.
   GitHub does not retry on its own. How long it keeps deliveries available for redelivery is **UNVERIFIED** here: read GitHub's
   "Handling failed webhook deliveries" documentation before relying on any retention figure.
3. Close the `owner_step_pending` issue. A second `github_webhook_secret` rotate is refused (`owner_step_open`) while that issue is open.

If the redeploy failed instead (`rotated_redeploy_failed`), do NOT update the App secret yet: re-dispatch the rotate first. The one
exception: when the failed run's log shows that BOTH hosts already serve the new container (track.sh prints each host's version), the
fleet already holds the new secret, so run the owner step NOW; every minute of delay is a minute of 401 deliveries.

Read-only probes for the gap windows (pull-only until alert rules exist, #11928):

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep "HMAC verification failed"
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep "GitHub webhook signature verification failed"
```

The first is the kb-drift ingest route, the second the GitHub webhook route. The second pattern is the full GitHub string on purpose:
the bare phrase "signature verification failed" also matches the Stripe and Resend routes.

## Residuals (disclosed)

- The typed confirm is derivable, and a write-access actor or a personal access token of the owner can still START a dispatch —
  but the run cannot reach a production-mutating job without a listed reviewer's click at the `key-rotate-approval` gate. A PAT
  approval of that job is the owner's click by design (#11923 closed the zero-gate gap; this is the bounded residual).
- A `push` run of the sibling workflow `inngest-key-rotate.yml` joining the shared concurrency group `inngest-key-rotate` can replace
  our pending dispatch, and our pending dispatch also cancels a sibling pending dispatch (the same literal group). This is fail-safe
  (nothing mutates); re-dispatch.
- The `ref_refused` and actor rungs guard accidents, not edited workflow code: a write-access actor who dispatches a branch copy of
  the workflow runs that branch's ladder — but GitHub evaluates the environment's `required_reviewers` and `main` branch policy
  before any job starts, so a branch copy still parks at `approve` and never reaches a mutating job unapproved (the sibling
  credential surfaces are #9294). Since 2026-11-05 `authorization_stale` is measured from the approve job's `approval_epoch`
  output rather than the guard job's clock; whether GitHub's run `createdAt` would be a better origin is UNVERIFIED either way.
- The redaction sanity step runs the redaction suite on the dispatched ref. It is an ordering and sanity step; the safety weight is
  that no Terraform stream ever reaches a log (`kr_tf` sends both streams to a private file and the plan JSON is projected to five
  fields and deleted).
- A manual `workflow_dispatch` of `kb-drift-walker.yml` mid-rotation is not blocked (the guard sees a walker in flight, but only at
  its own check times).
- Dev-key rotations gain no pickup from the production redeploy (#11927); it runs anyway because it is the shakedown of the route.
- The redeploy poll skips workflows per file, but `web-1-swap` membership is per job. `apply-web-platform-infra.yml` has six swap jobs
  and is deliberately NOT skipped in redeploy mode (its routine apply job is not in the group). This is the conservative side and it
  is UNVERIFIED live: a merge to main during a redeploy can queue one of that file's jobs, block the poll for the 480 s wait and end in
  a false `rotated_redeploy_failed` although the new value is landed (check both hosts' version, then run the owner step or the
  redeploy as the Refusals table says). The first dev rehearsal settles it.
- The redeploy re-check step's 10-minute timeout is not strictly implied by the 480 s wait: an iteration can run up to about 25 `gh`
  calls (the in-flight rung covers five non-member workflows with several statuses each), each capped at 20 s, so if EVERY call is slow
  but succeeds a single pass could pass 500 s and the step timeout could end it before `rotated_redeploy_failed` is printed. Arithmetic
  only, UNVERIFIED; a hung call fails fast (the rung reports unreadable at the first failure). The budgets are unchanged.
- The suite's CI wall time is an estimate. Record the first CI wall time of the suite's leg (the infra-validation leg that runs
  `key-rotate-workflow.test.sh`) in the PR; if that leg exceeds about 700 s, move the suite to a lighter leg (the per-suite bound is 840 s,
  below the leg's 15-minute ceiling, so a hung suite fails by name).
