---
title: "Rotation census for #11711 — one row per random_id / random_password resource"
branch: feat-one-shot-11294-11711-rotation-audit
created: 2026-11-04
issue: 11711
---

# Rotation census — #11711

One row per `random_id` / `random_password` resource across the three Terraform roots that declare
`random_` resources (verified by `grep 'resource "random_'` over every `.tf` under
`apps/web-platform/infra/` on this branch): **12 `random_id` + 10 `random_password`** in
`apps/web-platform/infra`, **2 + 2** in `inngest-provision-rehearsal/`, **0 + 1** in
`rung2-rehearsal/` — **27 rows**. Addresses, routes and readiness states only — never a value.

**Exposure rule** (CTO rulings 2026-11-04, `decision-challenges.md`): `random_id.id` is the base64url
of the key bytes and prints on every refresh/plan/apply line. `random_password.id` is the literal
`"none"` (provider source `resource_password.go`) and `result` is sensitive — `random_password`
resources are **not exposed via this vector** and need no rotation row. `random_string` would be
exposed (`id` is the value) but **no `random_string` resource exists** (census grep, 0 hits).

## 1. Census

| Address | Root | Value class | Exposed via this vector? | Route | Readiness state today | Gating issues |
|---|---|---|---|---|---|---|
| `random_id.inngest_manual_trigger_secret_dev` | apps/web-platform/infra | random_id — base64url key | yes | `key-rotate.yml` `key=inngest_manual_trigger_secret_dev` | READY — `mode=plan` rehearsal already green (run 41885962147, 2026-11-04T18:19Z); `mode=rotate` is owner-gated dispatch | none blocking; #11927 would skip the (rehearsal-only) prod redeploy leg |
| `random_id.inngest_manual_trigger_secret_prd` | apps/web-platform/infra | random_id | yes | `key-rotate.yml` `key=inngest_manual_trigger_secret_prd` | BLOCKED — `mode=rotate` refuses `approval_environment_missing` until the reviewer-gated environment exists | #11923 |
| `random_id.inngest_signing_key_dev` | apps/web-platform/infra | random_id | yes | `key-rotate.yml` `key=inngest_signing_key_dev` | READY — dev key, not subject to the approval environment | none blocking; #11927 |
| `random_id.inngest_event_key_dev` | apps/web-platform/infra | random_id | yes | `key-rotate.yml` `key=inngest_event_key_dev` | READY — as the dev signing key | none blocking; #11927 |
| `random_id.kb_drift_ingest_signing_key` | apps/web-platform/infra | random_id | yes | `key-rotate.yml` `key=kb_drift_ingest_signing_key` | BLOCKED — `approval_environment_missing` until #11923; also refuses inside the 03:00–03:30 UTC kb-drift window and while a walker run is in flight | #11923; window `kb_drift_cron_window`; `kb_drift_walker_in_flight` |
| `random_id.egress_audit_ingest_token` | apps/web-platform/infra | random_id | yes | `key-rotate.yml` `key=egress_audit_ingest_token` is **plan-only** — no Vector restart lever exists without SSH, so `rotate` refuses `egress_rotate_unsupported_no_vector_restart_lever` | BLOCKED outright — no complete route today; `mode=plan` runs but cannot land the value in Vector | #11920 |
| `random_id.github_webhook_secret` | apps/web-platform/infra | random_id | yes | `key-rotate.yml` `key=github_webhook_secret` (+ `webhook_patch_ready=true`) | BLOCKED — `approval_environment_missing` until #11923; then needs `webhook_patch_ready` and ends `owner_step_pending` (owner updates the App webhook secret); #11922's grace window would soften the 401 window but is not a gate | #11923; post-step issue gate `owner_step_open`; nice-to-have #11922, #11928 |
| `random_id.inngest_signing_key_dedicated` | apps/web-platform/infra | random_id | yes | `inngest-key-rotate.yml` `keys=signing` or `keys=both` — apply1 `-replace`s the dedicated random_id(s), reboot leg, apply2 propagates the app copies (ADR-307; CTO ruling Item 1: `keys=both` IS the covering route) | ROUTED — `#11215` soak CLOSED PASS 2026-11-01T18:51Z (inside the 11-12 deadline); owner-gated dispatch pending; includes the one Hetzner control-plane soft reboot of soleur-inngest (10.0.1.40) | none blocking; quiet_window attestation + fresh owner go required |
| `random_id.inngest_event_key_dedicated` | apps/web-platform/infra | random_id | yes | `inngest-key-rotate.yml` `keys=event` or `keys=both` | ROUTED — as the dedicated signing key | as above |
| `random_id.inngest_signing_key_prd` | apps/web-platform/infra | random_id | yes — printed, but the value is dead (state-only since #10540, zero `.tf` references; CTO ruling Item 2: no rotation owed) | none — retired; close-out is state removal | N/A — removal tracked, no rotation | #11293 |
| `random_id.inngest_event_key_prd` | apps/web-platform/infra | random_id | yes — printed, dead value | none — retired | N/A — as above | #11293 |
| `random_id.tunnel_secret` | apps/web-platform/infra | random_id | yes | none — **roll-forward only**: real rotation = tunnel replacement + web-2 rebuild; `terraform -replace` is a live no-op (`tunnel.tf`: `secret` feeds `cloudflare_zero_trust_tunnel_cloudflared.web.secret` under `ignore_changes = [secret, config_src]`; the original value is recorded irrecoverable) | BLOCKED by design — no dispatch route; owner decision whether the weak ground (the printed value is probably not the live tunnel secret — CTO inference, unverified) is worth the outage of `deploy.`, `ssh.`, `registry.` paths; `app.` traffic unaffected | none tracked; last + separate window per CLO determination |
| `random_password.git_data_luks` | apps/web-platform/infra | random_password — `id="none"`, `result` sensitive | no | not exposed — no rotation owed by this vector | n/a | — |
| `random_password.inngest_redis_luks` | apps/web-platform/infra | random_password | no | not exposed — no rotation owed by this vector | n/a | — |
| `random_password.inngest_redis_password_dedicated` | apps/web-platform/infra | random_password | no | not exposed — no rotation owed by this vector | n/a | — |
| `random_password.inngest_redis_password_prd` | apps/web-platform/infra | random_password | no | not exposed — no rotation owed by this vector | n/a | — |
| `random_password.live_verify_user` | apps/web-platform/infra | random_password | no | not exposed — no rotation owed by this vector | n/a | — |
| `random_password.registry_luks` | apps/web-platform/infra | random_password | no | not exposed — no rotation owed by this vector | n/a | — |
| `random_password.workspaces_luks` | apps/web-platform/infra | random_password | no | not exposed — no rotation owed by this vector | n/a | — |
| `random_password.workspaces_luks_web` | apps/web-platform/infra | random_password | no | not exposed — no rotation owed by this vector | n/a | — |
| `random_password.zot_pull` | apps/web-platform/infra | random_password | no | not exposed — no rotation owed by this vector | n/a | — |
| `random_password.zot_push` | apps/web-platform/infra | random_password | no | not exposed — no rotation owed by this vector | n/a | — |
| `random_id.rehearsal_signing_key` | inngest-provision-rehearsal | random_id | printed — but rehearsal-ephemeral (throw-away keys, destroyed at teardown; never feed production) | ephemeral — destroyed at teardown | n/a | — |
| `random_id.rehearsal_event_key` | inngest-provision-rehearsal | random_id | printed — rehearsal-ephemeral | ephemeral — destroyed at teardown | n/a | — |
| `random_password.rehearsal_luks` | inngest-provision-rehearsal | random_password | no | not exposed — no rotation owed by this vector; ephemeral | n/a | — |
| `random_password.rehearsal_redis_password` | inngest-provision-rehearsal | random_password | no | not exposed — no rotation owed by this vector; ephemeral | n/a | — |
| `random_password.rehearsal_luks` | rung2-rehearsal | random_password | no | not exposed — no rotation owed by this vector; ephemeral | n/a | — |

The seven `key-rotate.yml` rows above match the workflow's `key` input option list exactly
(`key-rotate.yml › workflow_dispatch.inputs.key.options`), verified by grep: `inngest_manual_trigger_secret_dev`,
`inngest_manual_trigger_secret_prd`, `inngest_signing_key_dev`, `inngest_event_key_dev`,
`kb_drift_ingest_signing_key`, `egress_audit_ingest_token`, `github_webhook_secret`.

## 2. Per-secret readiness notes for the owner dispatch

Command shapes are from `knowledge-base/engineering/operations/runbooks/key-rotation.md` (key-rotate
route) and `inngest-server.md` §Key rotation (dedicated-pair route). Every `mode=rotate` /
`mode=converge` dispatch is **owner-only**: a fresh in-session go naming the exact command. The
confirm string is a fat-finger guard, not the authorization — the `infra-privileged` environment
has zero required reviewers today (#11923), so it is derivable from public inputs. An agent never
dispatches either mode.

### Shared readback recipe

```bash
gh run list --workflow key-rotate.yml --event workflow_dispatch --limit 1 --json databaseId,status,conclusion
gh run watch <id> --exit-status
gh run view <id> --log | grep -E 'key-rotate (verdict|check)'      # verdicts + guard booleans
gh run view <id> --log | grep -E '(pre|post)-state copy'          # per-copy states, never a value
```

`guard_ok`, `plan_ok`, `rotate_ok` exit 0; every other verdict exits non-zero. `plan_ok` ends with
`rotate_would_refuse=<token|none>` — the first rotate-only rung this key would meet **right now**.

### `inngest_manual_trigger_secret_dev` — READY (shakedown key)

- Plan: `gh workflow run key-rotate.yml -f mode=plan -f key=inngest_manual_trigger_secret_dev`
- Rotate: `gh workflow run key-rotate.yml -f mode=rotate -f key=inngest_manual_trigger_secret_dev -f confirm=ROTATE-INNGEST_MANUAL_TRIGGER_SECRET_DEV-<YYYY-MM-DD> -f quiet_window=true`
- Confirm form: `ROTATE-<KEY upper-cased>-<YYYY-MM-DD>` (the run's UTC date).
- Refuses NOW: `rerun_refused` (attempt ≠ 1), `actor_refused`/`actor_not_owner`, `run_in_flight`,
  `authorization_stale` (go older than 60 min), `quiet_window_missing`, `confirm_mismatch`.
  NOT subject to `approval_environment_missing` (dev key).
- Baseline: `mode=plan` already exercised green — run **41885962147**, 2026-11-04T18:19:13Z.
- Failure shapes: `rotated_redeploy_failed` is consequence-free for dev keys (no production
  container reads `soleur/dev`; the redeploy leg is a rehearsal of the route, #11927);
  `partial_absent_state` is URGENT — do not restart anything, run a recovery `rotate` now.
- Premise worth exercising here first: a deliberately interrupted **dev** rehearsal tests whether
  `-replace` of a `doppler_secret` carrying `ignore_changes=[value]` recreates with the new value
  (`value_unchanged` is the detector) and whether a state-absent `-replace` plans a plain create —
  before any `_prd` rotate.

### `inngest_signing_key_dev`, `inngest_event_key_dev` — READY

- Identical shapes with `key=inngest_signing_key_dev` / `key=inngest_event_key_dev` and matching
  confirms `ROTATE-INNGEST_SIGNING_KEY_DEV-<date>` / `ROTATE-INNGEST_EVENT_KEY_DEV-<date>`.
- Same refusals and consequences as the dev manual trigger.

### `inngest_manual_trigger_secret_prd` — BLOCKED until #11923

- Rotate (after #11923): `gh workflow run key-rotate.yml -f mode=rotate -f key=inngest_manual_trigger_secret_prd -f confirm=ROTATE-INNGEST_MANUAL_TRIGGER_SECRET_PRD-<YYYY-MM-DD> -f quiet_window=true`
- Refuses NOW: **`approval_environment_missing`** — `scripts/key-rotate.sh › kk_chk_approval`
  (pinned `KK_APPROVAL_ENV_BOUND=false`; the PR binding the apply job to the reviewer-gated
  environment flips the one line). Plus the shared ladder.
- Consequence window: between the apply and the container swap the internal routes
  (`trigger-cron`, `schedule-reminder`, `cohort`, `home-census`) answer **401** on a skewed host —
  do not arm reminders or tag cohorts while it runs (`rotated_redeploy_failed`: `soleur:trigger-cron`
  answers 401 until a redeploy lands).

### `kb_drift_ingest_signing_key` — BLOCKED until #11923 + a window check

- Rotate: `gh workflow run key-rotate.yml -f mode=rotate -f key=kb_drift_ingest_signing_key -f confirm=ROTATE-KB_DRIFT_INGEST_SIGNING_KEY-<YYYY-MM-DD> -f quiet_window=true`
- Refuses NOW: `approval_environment_missing` (#11923); **`kb_drift_cron_window`** — the guard
  refuses when the remaining apply-and-redeploy budget intersects **03:00–03:30 UTC** (dispatch
  outside roughly 00:45–03:30 UTC); `kb_drift_walker_in_flight` while a `kb-drift-walker.yml` run
  is queued/running/waiting.
- Copies: TWO Doppler copies update in place in the same apply — `soleur/prd_kb_drift_walker`
  `KB_DRIFT_INGEST_SIGNING_KEY` and `soleur/prd` `KB_DRIFT_INGEST_SIGNING_KEY`
  (`scripts/key-rotate.sh › KK_COPIES`); the app copy needs the redeploy.
- Failure shapes: `copies_differ` → fresh `rotate` outside the window;
  `partial_absent_state` (copies mixed) → recreate the missing Doppler copy first — a rotate
  refuses identically while mixed; `rotated_redeploy_failed` → the next 03:00 UTC walker run is
  rejected 401 until a redeploy lands.

### `egress_audit_ingest_token` — BLOCKED outright until #11920

- Only `mode=plan` runs: `gh workflow run key-rotate.yml -f mode=plan -f key=egress_audit_ingest_token`
- `mode=rotate` refuses **`egress_rotate_unsupported_no_vector_restart_lever`** — Vector reads the
  token at start and no restart lever exists without a host shell (#11920). There is no complete
  route today; the census records the state, unblocking is #11920's scope.

### `github_webhook_secret` — BLOCKED until #11923; last of the seven

- Rotate: `gh workflow run key-rotate.yml -f mode=rotate -f key=github_webhook_secret -f confirm=ROTATE-GITHUB_WEBHOOK_SECRET-<YYYY-MM-DD> -f quiet_window=true -f webhook_patch_ready=true`
- Refuses NOW: `approval_environment_missing` (#11923); `webhook_patch_not_ready` without
  `webhook_patch_ready=true` (owner has the GitHub App private key at hand — readiness, not the
  authorization); `owner_step_open` while a `owner_step_pending` issue for this key is open (or the
  label/listing is unreadable — fails closed).
- Ends `owner_step_pending` **by design**: the notify job files an issue labelled
  `owner_step_pending`; the owner then (1) updates the GitHub App webhook secret to the new
  `GITHUB_APP_WEBHOOK_SECRET` per `github-app-provisioning.md` Step 4 (App private key, isolated
  project `soleur-github-app`, config `prd`), (2) redelivers failed deliveries from the App's
  Advanced settings starting at the first container-swap timestamp (GitHub does not retry;
  redelivery retention UNVERIFIED — read GitHub's docs first), (3) closes the issue.
- Consequence: while the secrets disagree, deliveries are rejected **401 and GitHub does not retry
  them** — every minute of delay after a good redeploy is a minute of failed deliveries. If the
  redeploy failed instead (`rotated_redeploy_failed`), do NOT update the App secret; re-dispatch
  the rotate first (one exception: both hosts already serving the new container per the track.sh
  log → run the owner step now). #11922's accept-previous-secret grace window would soften this;
  #11928 would alert on signature failures. Neither is a gate.

### `random_id.inngest_{signing,event}_key_dedicated` — ROUTED, owner dispatch pending

- Plan rehearsal: `gh workflow run inngest-key-rotate.yml -f mode=plan -f keys=both -f reason='rehearsal'`
- Rotate: `gh workflow run inngest-key-rotate.yml -f mode=rotate -f keys=both -f confirm=ROTATE-INNGEST-BOTH-<YYYY-MM-DD> -f quiet_window=true -f reason='<go reference>'`
- Converge (recovery only, never mints a key): `gh workflow run inngest-key-rotate.yml -f mode=converge -f keys=<keys> -f confirm=CONVERGE-INNGEST-<KEYS>-<YYYY-MM-DD> -f quiet_window=true -f reason='converge after inngest-key-rotate run <id>'`
- Confirms: `ROTATE-INNGEST-<KEYS upper-cased>-<YYYY-MM-DD>` /
  `CONVERGE-INNGEST-<KEYS upper-cased>-<YYYY-MM-DD>` (`keys` ∈ `signing|event|both`; a go naming one
  cannot rotate the other).
- Guard refuses unless (`inngest-key-rotate.yml` guard rungs): `run_attempt` is 1; inputs/confirm
  well-formed; `quiet_window=true`; the link flag (`INNGEST_LINK_TLS` in `soleur/prd_terraform`) is
  `1`; tracker **#11215 closed as completed** — SATISFIED 2026-11-01T18:51:02Z; no run of
  `apply-web-platform-infra.yml`, `inngest-link-flip.yml`, `cutover-inngest.yml`,
  `deploy-inngest-image.yml`, `web-platform-release.yml` or another `inngest-key-rotate.yml` in
  flight; exactly one server `soleur-inngest` at 10.0.1.40 reading `SERVING=yes` with `listener=1`.
- Shape: apply1 `-replace`s the dedicated `random_id`(s) and updates the dedicated Doppler copies;
  **reboot leg** = ONE Hetzner control-plane soft reboot (no retry, no hard reset) behind an `admit`
  re-check (fresh boot_id, flag still 1, no in-flight runs), verified by a NEW boot_id + SERVING +
  a `tls-health` row with `listener=1`; apply2 replaces the app `doppler_secret` copies; canary-then-prod
  fleet redeploy. **Forward-only — no old key exists after phase 1**; recovery of a failed run is
  `converge` under a fresh go (`converge_stale` refuses a source rotation older than 24 h).
- Readback: `gh run view <id> --log | grep 'inngest-key-rotate verdict='`; the route prints (never
  posts) the `S5-A5-DONE: <UTC>Z` line — the owner posts it on #10136 or relays per the runbook;
  host evidence via `gh workflow run inngest-host-state.yml` (`SERVING=yes`) and Better Stack
  `tls-health` rows for the NEW boot_id.
- Failure shapes worth knowing: `host_read_failed` (no verdict about the host — the last read
  failed), reboot/verify non-completion inside the step budgets, `redeploy_failed` (old containers
  keep the old key, scheduler/Doppler have the new), `quiet_window_missing`, `confirm_mismatch`,
  `rerun_refused`. During the mismatch window step calls fail signature verification (Inngest
  retries them) and `inngest.send` can 401.

### `random_id.inngest_{signing,event}_key_prd` — retired, no dispatch

- CTO ruling: state-only since #10540, zero `.tf` references, `-replace` changes no live value —
  no rotation owed. Close-out is state removal under **#11293** (open). Any printed value is dead.

### `random_id.tunnel_secret` — no route, last and separate

- No dispatch exists. `terraform -replace=random_id.tunnel_secret` is a **live no-op**: the resource
  feeds `cloudflare_zero_trust_tunnel_cloudflared.web.secret` under
  `lifecycle { ignore_changes = [secret, config_src] }` (`tunnel.tf`), and the original live secret
  is recorded irrecoverable — the printed value is probably not the live tunnel secret (CTO
  inference, unverified). A real rotation **replaces the tunnel and rebuilds web-2** — roll-forward
  only (ADR-307 amendment 2026-10-29). `deploy.`, `ssh.` and `registry.` hostnames go offline until
  it completes; `app.` is an A record to web-1 and end-user traffic is unaffected. Last, in its own
  window, and only if the owner decides the weak ground is worth the outage.

### Rehearsal and `random_password` rows

- Rehearsal `random_id`s printed throw-away values that died with their root's teardown — no
  rotation owed; the artifact surface they also touched is the Known-gap item in the audit findings.
- Every `random_password` row: `id="none"`, `result` sensitive — not exposed via this vector; no
  rotation owed. `random_string` would be exposed but does not exist.

## 3. Ordering note for the owner

1. **Dev shakedown first** — `inngest_manual_trigger_secret_dev` (its 2026-11-04 `mode=plan`
   rehearsal, run 41885962147, is the baseline), then `inngest_signing_key_dev`,
   `inngest_event_key_dev`. The first dev rotate also proves the `ignore_changes` re-create premise
   (`value_unchanged` detects a miss) and the absent-state `-replace` shape.
2. **Dedicated pair via `inngest-key-rotate.yml`** `keys=both` — its #11215 gate already closed PASS
   (2026-11-01T18:51Z, inside the 11-12 deadline); the route needs a quiet window and absorbs the
   one host reboot.
3. **`kb_drift_ingest_signing_key`** — after #11923, dispatched outside ~00:45–03:30 UTC and with no
   walker in flight.
4. **`inngest_manual_trigger_secret_prd`** — after #11923, in a window with no reminder-arming or
   cohort tagging.
5. **`github_webhook_secret` last** of the seven — after #11923, with `webhook_patch_ready`, the App
   private key at hand, and the owner step queued immediately behind the redeploy.
6. **`tunnel_secret` last and separate** — roll-forward only, its own window, owner-decided.
7. **`egress_audit_ingest_token` and the retired `_prd` pair are not dispatchable** — they track
   #11920 and #11293 respectively, outside this route.

**Deadline context:** if rotation is not recorded complete in #11294 by **2026-11-08**, the CLO
re-assesses (preservation record §Residual exposure). Every dispatch above is an Operator Hold —
this census shortens the path; it schedules nothing.
