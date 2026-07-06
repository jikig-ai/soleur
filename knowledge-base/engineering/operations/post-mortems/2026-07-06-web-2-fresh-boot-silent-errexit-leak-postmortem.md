---
title: "web-2 warm-standby fresh boot silently aborted since #5921 — leaked cloud-init set -e"
date: 2026-07-06
incident_pr: 6092
incident_window: "~#5921 merge (host-script extraction refactor) → 2026-07-06 (root cause found by code-read; probe + H3 scope-fix shipped)"
recovery_at: "pending — #6090 stays open until a web-2-recreate boots green and :9000 binds (AC16)"
suspected_change: "#5921 (host-script extraction into a baked installer) — its extraction runcmd block set `set -e`, disarmed its on_err trap, and never restored `set +e`; cloud-init joins all runcmd items into ONE /bin/sh, so errexit leaked into the untrapped bare downstream apt/cloudflared region"
brand_survival_threshold: none
status: unresolved but ended
triggers:
  - proactive discovery (found incidentally while diagnosing why web-2-recreate never produced a working warm standby — #6090)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

web-2 is a weight-0, **non-serving** warm standby (ADR-068). Since the #5921 host-script
extraction refactor, every `web-2-recreate` produced a host whose cloud-init aborted silently
before the deploy-status webhook (`:9000`, fronted by cloudflared) came up — so web-2 never
became a working warm standby and every deploy fan-out to it reported `ok_peer_fanout_degraded`.

**No user-facing / production impact:** web-1 has been the sole live origin at 200 throughout;
web-2 serves no traffic. The degraded capability was **failover readiness** (no warm standby
available for the ADR-068 blue-green cutover), not availability. Classified `none` for
brand-survival on that basis; captured as a PIR because it is a silent capability regression
found incidentally (the operator's standing "incident detected → PIR always" rule).

## Status

`unresolved but ended` — the silent-abort root cause is identified and the scope-fix + off-host
observability probe shipped (PR #6092), but "resolved" is only provable by a green recreate;
#6090 stays open until `:9000` binds.

## Symptom

`web-2-recreate` apply succeeds (attach-proof + volume-preserved), but 8/8 `deploy.soleur.ai/hooks/deploy-status`
tunnel probes hit web-1 → web-2's cloudflared never comes up → `:9000` never binds. Sentry was
**silent** on any host-boot event, so the death was invisible off-host (no SSH by rule,
`hr-no-ssh-fallback-in-runbooks`).

## Root cause (5-Whys)

1. Why did web-2 never bind `:9000`? cloud-init aborted before the cloudflared/webhook stage.
2. Why did it abort? A bare downstream command (most likely `apt-get`/cloudflared install) returned
   non-zero and errexit terminated the whole runcmd.
3. Why was errexit active there? cloud-init joins ALL `runcmd` items into ONE `/bin/sh` (the file's
   own line-349/559 comments assert this); the #5921 extraction block ran `set -e` and never restored
   `set +e`, so errexit **leaked** into the bare region.
4. Why was it silent? The extraction block disarmed its `on_err` trap before handing off to the baked
   installer (correct, so bootstrap failures aren't mislabeled), so the leaked-errexit abort in the
   downstream region had **no active trap** and emitted nothing.
5. Why did it go undetected for weeks? web-2 is non-serving, so there was no user-facing signal; and
   the off-host observability stopped at the seed block (#6076) — the downstream region had no Sentry
   emit at all. **The blind spot hid its own cause.**

## Resolution

PR #6092 (this PR): (a) **H3 scope-fix** — restore `set +e` after the extraction block so errexit no
longer leaks; (b) a structured off-host observability probe across the whole post-seed sequence
(baked-DSN emit, `bootstrap_complete` breadcrumb, `cloudflared_ready`/`webhook_bound` readiness gates
that convert an async-service death into a named Sentry fatal, composite traps, terminal breadcrumb);
(c) the recreate workflow's auto Sentry-read repointed to the EU data plane (`de.sentry.io`). Item (B)
cosign ENFORCE was confirmed NOT on the fresh-boot path (no code change).

## Recovery verification

Pending the operator-gated `web-2-recreate` in a quiet window (AC13): read the named last-reached
stage from the recreate run's `$GITHUB_STEP_SUMMARY` / Sentry. If `:9000` binds and the fan-out
reports `ok`, #6090 closes (AC16). The probe's `if: always()` breadcrumb surface makes a green boot
distinguishable from "probe never emitted."

## Action Items & Follow-ups

| Issue | Item | Actor |
|---|---|---|
| #6090 | Rebuild the image (release), then operator-gated `web-2-recreate` in a quiet window; read the named stage; close on green boot or file the named-stage fix. | agent-with-ack |

## Prevention

- The H3 class (a `set -e` in one cloud-init runcmd item leaking into later items) is now documented
  in `knowledge-base/project/learnings/2026-07-06-cloud-init-user-data-cap-bake-bodies-and-set-e-scope-fix-ungates-security-checks.md`.
- The new `soleur-host-bootstrap-observability.test.sh` guard asserts the `set +e` scope-fix (H3),
  the readiness gates, and the fail-open invariant — so a future refactor that re-leaks errexit or
  drops the downstream emit fails CI.
- Off-host observability now spans the whole fresh-boot sequence, so the next silent-abort class in
  this region names its stage in Sentry on the first recreate rather than hiding for weeks.
