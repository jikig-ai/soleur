---
title: Webhook returned 202 but the handler never ran (E2BIG) — ship the component's own error channel BEFORE black-box repro
date: 2026-07-11
category: integration-issues
module: apps/web-platform/infra (webhook / infra-config delivery)
tags: [webhook, adnanh-webhook, E2BIG, MAX_ARG_STRLEN, pass-file-to-command, observability, silent-failure, diagnostic-discipline, inngest-cutover]
issues: [6178, 6311, 6313, 6315, 6331]
---

# Learning: Webhook returned 202 but the handler never ran (E2BIG)

## Problem

On the #6178 Inngest dedicated-host cutover, `/hooks/infra-config` (the HTTPS config-delivery
webhook, adnanh/webhook v2.8.2) returned **HTTP 202 "Infra config update initiated"** but its
handler `/usr/local/bin/infra-config-apply.sh` **never executed**. The host stayed frozen at
**13 of 15 managed files** since ~July 5, so:

- `op=verify`'s registry-probe fast-500'd (its script was never delivered) → cutover gate dead.
- Fresh-host provisioning was broken too — a recreated host could not receive `ci-deploy.sh`,
  which is almost certainly why a `web-2-recreate` never brought `:9000` up.

The handler was present and `test -x` passed. A complete, correct 15-field manual POST still
got `202` + no execution. `infra-config-status` was byte-identical run after run. Every
black-box angle said "202, but nothing happened."

## Root cause

The `infra-config` hook passed all 15 scripts as **exec ENVIRONMENT variables**
(`pass-environment-to-command`). `ci-deploy.sh`'s base64 had grown to **143,756 bytes**, over
Linux's **per-env-var ceiling `MAX_ARG_STRLEN` = 131,072 (128 KB)**. So `execve` rejected it
with **E2BIG** and the handler was never `fork/exec`'d — while the webhook, having already
committed `success-http-response-code: 202`, reported success. It broke the day `ci-deploy.sh`
crossed ~96 KB raw. (Total payload 319 KB was under the 2 MB `ARG_MAX`, so it was the *single-var*
limit, not the total.)

The failure was invisible off-box because the webhook binary's own journald channel
(`SYSLOG_IDENTIFIER=webhook`, running `-verbose`) was **not shipped** to Better Stack. The
handler's markers *were* shipped — but the handler never ran, so there were no markers.

## Solution

**#6331:** switch the hook to `pass-file-to-command` with `base64decode: true` — the webhook
writes each *decoded* payload to a temp file in `command-working-directory=/var/lock`
(deploy-writable, in `webhook.service` `ReadWritePaths`) and passes only the small file **path**
via the env var. The handler `cp`s the file instead of decoding an env string. This removes the
per-var size ceiling entirely and future-proofs any script growing.

The one log line that named it (once #6315 shipped the `webhook` channel):

```
[f1f32a] executing /usr/local/bin/infra-config-apply.sh … with environment [CI…
[f1f32a] error occurred: fork/exec /usr/local/bin/infra-config-apply.sh: argument list too long
```

## Key insight (the expensive one)

**When a component reports success but its downstream effect is absent — a webhook 202 with no
handler run, a deploy "ok" with no state change, a workflow "succeeded" with a stale artifact —
and you cannot see WHY, make THAT component's own error channel observable FIRST. Do not
black-box reproduce.**

This session burned hours and a lot of tokens black-box hypothesizing (manual payloads, two
`redeploy-nonce` cycles, a webhook-restart-race theory) before finally shipping the webhook
binary's journald (#6315: add `webhook` to vector's allowlist). That one change named the cause
in a single line. The instinct to "reproduce and narrow" is wrong when the component already
knows the answer and just isn't telling you — spend the first move making it tell you.

This extends `hr-no-dashboard-eyeball-pull-data-yourself` (self-pull observability) and
`hr-observability-as-plan-quality-gate` (add a marker so it self-reports) down one layer: to the
**intermediary/component's own error channel**, not just the app's.

Corollaries proven this session:
- **`success-http-response-code` (any success-before-effect) is a silent-failure anti-pattern.**
  adnanh/webhook returns the configured success code even when `fork/exec` fails.
- **Verify gates must assert against the EXPECTED value (repo source-of-truth), not the
  artifact's own self-reported total.** `apply-deploy-pipeline-fix`'s verify compared
  `files_written` to the status JSON's *own* `files_total`, so a stale `13/13` passed green
  while the repo expected 15 — it hid the non-delivery for days (#6313 fixed it to derive
  EXPECTED from the FILE_MAP).
- **Do not recreate a host while its config-delivery path is broken.** A `web-2-recreate`
  booted an *uncapped* inngest (the capped config could not be delivered), opened ~26 prod-pooler
  connections, and saturated the shared prod session pooler (30/30 EMAXCONNSESSION) — a
  self-inflicted prod-adjacent incident. Recovery: power off the weight-0 host + `pg_terminate_backend`
  its orphaned pooler sessions.

## Session Errors

1. **Black-box hypothesizing before shipping the component's error channel.** Root cause was one
   `webhook` journald line away the whole time. Recovery: shipped `webhook` to vector (#6315).
   **Prevention:** the diagnostic-discipline AGENTS rule (see route-to-definition) — component's
   own error channel first.
2. **web-2-recreate during a broken delivery path → pooler saturation incident.** Recovery:
   `hcloud server poweroff soleur-web-2` + terminate the 25 orphaned Supavisor sessions.
   **Prevention:** verify config-delivery health (`infra-config-status` fresh + full count)
   before any host `-replace`.
3. **False-green verify hid the non-delivery.** `files_written == files_total` (self-reported)
   passed on a stale 13/13. **Prevention:** already fixed (#6313) — assert `files_total ==`
   the repo FILE_MAP count.
4. **CI concurrency contention** cancelled/queued 4 delivery applies (shared `web-1-swap` +
   `terraform-apply-web-platform-host` locks during a busy main). **Prevention:** one-off timing;
   dispatch into a confirmed-free lock window rather than racing repeatedly.
5. **Minor, fixed inline:** vector AC3 drift-guard flagged `webhook` (a systemd-unit binary
   identifier, not a `logger -t` tag) — taught AC3 the exception; a `printf | grep -q` SIGPIPE
   flake in the concurrency-parity guard (exposed by enlarging the apply-job block) — switched to
   here-strings.

## Tags
category: integration-issues
module: apps/web-platform/infra
