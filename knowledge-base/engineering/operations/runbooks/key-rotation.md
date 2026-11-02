---
title: Key rotation for the non-tunnel secrets (key-rotate.yml)
type: runbook
status: active
issue: 11294
related: [11294, 10205, 11920, 11922, 11923, 11927, 11928, 9294]
related_adrs: [ADR-314, ADR-307, ADR-241]
---

# Key rotation for the non-tunnel secrets

One dispatch-only workflow, `.github/workflows/key-rotate.yml` (body `scripts/key-rotate.sh`, decision record
[ADR-314](../architecture/decisions/ADR-314-key-rotation-second-dispatch-only-route-sourcing-the-inngest-route.md)), rotates ONE
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
- **The confirm is a fat-finger guard, not an authorization.** The `infra-privileged` environment has ZERO required reviewers
  (measured 2026-11-02), so the string is derivable from public inputs. The authorization is the owner's own fresh in-session go
  naming the exact command. **An agent never dispatches `rotate`; that is policy, not a mechanism.** The guard additionally refuses a
  ref other than `main` (`ref_refused`), a bot or empty actor (`actor_refused`) and any actor outside the committed owner allowlist
  (`actor_not_owner`). A personal access token of the owner still passes: disclosed residual. A reviewer-gated environment is tracked
  in #11923; until it exists, `mode=rotate` for `inngest_manual_trigger_secret_prd`, `kb_drift_ingest_signing_key` and
  `github_webhook_secret` refuses `approval_environment_missing`.
- One key per dispatch. The confirm names exactly one key.

## The seven keys

| `key` input | What changes | Consumer and pickup | Notes |
|---|---|---|---|
| `inngest_manual_trigger_secret_dev` | `random_id` and `soleur/dev INNGEST_MANUAL_TRIGGER_SECRET` (replaced together) | developer shells and dev servers read `soleur/dev` at their own start; no production container consumes it, so the redeploy is a rehearsal of the route's last leg, not a pickup (#11927) | shakedown key, rotate it first |
| `inngest_manual_trigger_secret_prd` | `random_id` and `soleur/prd INNGEST_MANUAL_TRIGGER_SECRET` (replaced together) | host-side readers pick it up at apply; the routes `trigger-cron`, `schedule-reminder`, `cohort` and `home-census` return 401 on a host whose container has not swapped yet | `approval_environment_missing` until #11923 |
| `inngest_signing_key_dev` | `random_id` and `soleur/dev INNGEST_SIGNING_KEY` | as the dev manual trigger | dev only |
| `inngest_event_key_dev` | `random_id` and `soleur/dev INNGEST_EVENT_KEY` | as the dev manual trigger | dev only |
| `kb_drift_ingest_signing_key` | `random_id` only; BOTH copies (`soleur/prd_kb_drift_walker` and `soleur/prd`) update in place in the same apply | the walker reads its config at its next run; the `soleur/prd` copy needs the redeploy | refuses inside the 03:00-03:30 UTC window and while a walker run is in flight; `approval_environment_missing` until #11923 |
| `egress_audit_ingest_token` | nothing: **plan only** | Vector reads the token at start and no restart lever exists without a host shell (#11920) | `rotate` refuses `egress_rotate_unsupported_no_vector_restart_lever` |
| `github_webhook_secret` | `random_id` only; `soleur/prd GITHUB_APP_WEBHOOK_SECRET` updates in place | the verifier uses ONE secret (a grace window is #11922); deliveries fail 401 until the owner step below | `webhook_patch_ready=true`, ends `owner_step_pending`; `approval_environment_missing` until #11923 |

## Dispatch order

1. `mode=plan` for the key you are about to rotate. The first plan dispatch also proves that `DOPPLER_TOKEN_TF` can read the copies
   (`copy_unreadable` otherwise); that read is unverified until it runs.
2. Dev shakedown first: `inngest_manual_trigger_secret_dev`, then `inngest_signing_key_dev` and `inngest_event_key_dev`. The first dev
   rotate is also the first test of two premises that nothing has observed yet: that `-replace` of a `doppler_secret` carrying
   `ignore_changes=[value]` recreates it with the new value (the `value_unchanged` verdict is the detector), and that `-replace` of an
   address absent from state plans a plain create. Exercise the second one with a deliberately interrupted **dev** rehearsal before any
   `_prd` rotate.
3. `kb_drift_ingest_signing_key`, started outside the window the guard computes (roughly 00:55 to 03:30 UTC; the guard prints the
   refusal if you are inside it).
4. `inngest_manual_trigger_secret_prd`, after #11923.
5. `github_webhook_secret` last, in a quiet window, after #11923 and with the App private key at hand.

The plan rehearsal command shape (no confirm):

```bash
gh workflow run key-rotate.yml -f mode=plan -f key=inngest_manual_trigger_secret_dev
```

The rotate command shape (the owner types this themselves, under their own go):

```bash
gh workflow run key-rotate.yml -f mode=rotate -f key=inngest_manual_trigger_secret_dev \
  -f confirm=ROTATE-INNGEST_MANUAL_TRIGGER_SECRET_DEV-<YYYY-MM-DD> -f quiet_window=true
```

Read the verdict of any run:

```bash
gh run view <run-id> --log | grep 'key-rotate verdict='
```

## Before a `prd` manual-trigger rotation

Do not arm reminders and do not tag cohorts while it runs: between the apply and the container swap a `schedule-reminder` call or a
`users.cohort_key` write through `/api/internal/cohort` answers 401 on a skewed host and is not retried.

## Verdicts, state and recovery

A refusal before any write prints one fixed verdict and writes nothing. After the apply the script classifies every copy
(`present-unchanged`, `present-changed`, `absent`, `unknown`) and ends with exactly one verdict, with this precedence:
`post_hash_unreadable`, then `partial_absent_state`, then `value_unchanged`, then `copies_differ`. There is **no converge mode and no
redeploy-only mode**: recovery is a fresh `rotate` of the same key under a fresh typed confirm (it mints another value, which is
harmless for all keys in scope; roll-forward is the only direction because the previous value is not retained).

| Verdict | Doppler | Terraform state | Running containers | Next safe action |
|---|---|---|---|---|
| `apply_failed` | per-copy classification in the run log | possibly partial (a replace may have destroyed and not created) | old | fresh `rotate`; if any copy is `absent` it is urgent, because a container restart now starts without the secret |
| `post_hash_unreadable` | unknown | new | old | fresh `rotate`; the value is unknown, not unchanged |
| `value_unchanged` | OLD | new `random_id` | old | stop and read the ADR item on the `ignore_changes` premise before re-dispatching; a repeat means the premise is false |
| `copies_differ` (kb_drift) | both present, unequal | new | old | fresh `rotate` outside the cron window |
| `partial_absent_state` | some present, some absent | partial | old | URGENT, not auto-repaired: do not restart anything; run the recovery `rotate` now |
| `rotated_redeploy_failed` | new | new | old, or a MIXED fleet if the canary swapped and prod did not | fresh `rotate` (kb_drift: the next 03:00 UTC walker run is rejected until a redeploy lands; manual trigger prd: `soleur:trigger-cron` answers 401; dev keys: none) |
| `owner_step_pending` | new | new | new | the single owner action below |

Restart-while-absent consequence per key: manual trigger, 503 on `/api/internal/*`; webhook, 500 on every delivery; kb_drift, 500 on
ingest. On the all-absent recovery path the redeploy leg is mandatory and the log says the old value survives only in running
containers.

Every verdict except `rotate_ok` and `plan_ok` fails the job, and a failure after the apply files ONE `action-required` issue titled
`key-rotate <key> <verdict> (run <id>)` from the `notify` job (de-duplicated on key, verdict and run; a later event of the same run is
a comment). `rotate_ok` means the fleet redeploy was confirmed by `track.sh`; it does not mean each consumer was individually verified.

## The GitHub webhook owner step

After a good redeploy the workflow ends `owner_step_pending` on purpose and files an issue labelled `owner_step_pending`. The single
remaining action, done by the owner (the App private key is needed; an agent never does this without an owner ruling):

1. Update the GitHub App webhook secret with the new value of `GITHUB_APP_WEBHOOK_SECRET`, following
   [github-app-provisioning.md](./github-app-provisioning.md) Step 4 (the command block there reads the private key from the isolated
   project `soleur-github-app`, config `prd`).
2. Redeliver the failed deliveries from the App's Advanced settings, starting at the timestamp of the first container swap in the run.
   GitHub does not retry on its own and keeps deliveries only for a limited time; confirm the current retention before relying on it.
3. Close the `owner_step_pending` issue. A second `github_webhook_secret` rotate is refused (`owner_step_open`) while that issue is open.

If the redeploy failed instead (`rotated_redeploy_failed`), do NOT update the App secret yet: re-dispatch the rotate first.

Read-only probes for the gap windows (pull-only until alert rules exist, #11928):

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep "HMAC verification failed"
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep "signature verification failed"
```

The first is the kb-drift ingest route, the second the GitHub webhook route.

## Residuals (disclosed)

- The typed confirm is derivable and the environment has no reviewers: a write-access actor or a personal access token of the owner
  can start a forced rotation (#11923).
- A `push` run of the sibling workflow `inngest-key-rotate.yml` joining the shared concurrency group `inngest-key-rotate` can replace
  our pending dispatch. This is fail-safe (nothing mutates); re-dispatch.
- The redaction sanity step runs the redaction suite on the dispatched ref. It is an ordering and sanity step; the safety weight is
  that no Terraform stream ever reaches a log (`kr_tf` sends both streams to a private file and the plan JSON is projected to five
  fields and deleted).
- A manual `workflow_dispatch` of `kb-drift-walker.yml` mid-rotation is not blocked (the guard sees a walker in flight, but only at
  its own check times).
- Dev-key rotations gain no pickup from the production redeploy (#11927); it runs anyway because it is the shakedown of the route.
