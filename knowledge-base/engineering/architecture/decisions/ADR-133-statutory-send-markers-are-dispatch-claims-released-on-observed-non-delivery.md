---
title: Statutory send-markers are dispatch claims, released on observed non-delivery
status: active
date: 2026-07-22
related: [6802, 6781, 5046]
related_adrs: [ADR-037]
brand_survival_threshold: single-user incident
---

# ADR-133: Statutory send-markers are dispatch claims, released on observed non-delivery

## Status

**Active** (2026-07-22, #6802). Not soak-gated — every consequence is pinned by
pre-merge tests.

## Context

#6781 introduced the `statutory_repin_send` marker: a row keyed `(item_id, tick_key)`
inserted immediately before dispatch so a second scheduler cannot double-fire a
statutory-deadline reminder. That made the backstop reliable — but the marker
certified only that a **dispatch was attempted**, not that anything reached the
recipient.

The gap (#6802): `sendPushNotifications` prunes a subscription only on HTTP 410.
Any other push failure — notably the egress firewall's deliberate WNS DROP (#5046
PR-2), which is not a 410 — left the subscription in place, so `notifyOfflineUser`
kept choosing the push channel on `subscriptions.length > 0`, the email fallback
never fired, and the recipient got **nothing** on a running legal clock while the
cron counted the item as `pinged`. Worse, with the #6781 marker written, the next
tick no longer retried — the pre-#6781 accidental self-heal (an un-pruned row → a
retry) was gone. The marker now certified a non-send as sent.

## Decision

**A statutory send-marker is a DISPATCH CLAIM, not a delivery certificate. A
dispatch observed to reach zero-or-fewer-than-all channels RELEASES its marker so
the next tick retries; a dispatch that reached at least one channel keeps its
marker and stays suppressed.**

Concretely:

1. **`notifyOfflineUser` returns whether the notification was delivered** on at
   least one channel (`Promise<boolean>` — not a struct; nothing consumes a
   channel field the emit doesn't already have locally). It never throws (the
   outer catch returns `false`), preserving the contract `agent-on-spawn-requested`
   and `email-on-received` rely on.
2. **Zero OR partial push delivery on a must-not-fail-silently class falls back to
   email.** The class set (`mustNotFailSilently`) is the single source of truth
   shared with `mirrorNotifyFailure`: statutory `email_triage`, `cost_breaker_tripped`,
   and `action_required` `inbox_item`. The fallback fires on `delivered < attempted`
   (**not** `=== 0`): a stale device that still 201s must not mask a dead one and
   leave a founder on the road with nothing. The `statutory-notify-zero-delivery`
   warn still fires on TRUE zero push delivery (the egress-DROP incident), op slug
   unchanged so keyed alert rules keep firing.
3. **The cron rolls the marker back on non-delivery**, scoped to the `headsup`
   key only. The `daily:<date>` key rotates every day, so the next tick re-arms
   the daily arm for free — deleting a daily marker buys no retry and only reopens
   the same-day double-fire window. All rollback value lives on the constant
   `headsup` key, whose re-send depends on the marker being gone. The rollback may
   only delete a marker THIS iteration claimed (never a fail-open or concurrent
   marker), is wrapped in try/catch (a throw under `retries: 0` would kill the
   ingress liveness probe), and emits its own audit op
   (`statutory-repin-marker-rolled-back`) because it bypasses the audited
   `purge_statutory_repin_send` RPC boundary.
4. **`pinged` now means "delivered on at least one channel"**; `undelivered` is its
   complement and an anomaly counter that escalates the sweep emit to warn.

## Consequences

- The #6781 double-fire suppression is preserved: a DELIVERED send keeps its
  marker, so only a provably-undelivered send is retried. It restores the pre-#6781
  self-heal as a DESIGNED rollback rather than an accident of an un-pruned row.
- **Named residual — "delivered" is transport acceptance, not receipt.**
  `sendPushNotifications` counts `Promise.allSettled` fulfilment (a push service
  201) and the email arm counts "Resend returned no error" (a 200). Neither proves
  the founder saw anything: a bounce, a spam-filter drop, or a wrong
  `auth.users.email` all read as delivered. Closing that gap needs delivery
  webhooks (Resend/push receipts) — a deliberate follow-up, NOT this change.
- **Named residual — the crash window.** The marker is written before dispatch and
  released after; a process kill between the two leaves a marker in the state
  "dispatched, delivery unknown", indistinguishable from delivered to a later
  reader. `retries: 0` and the single-scheduler `concurrency` limit bound this, but
  it is not zero.
- **Named residual — the rollback self-heals only while the heads-up predicate is a
  multi-day band (ADR-037).** If D2's band were later narrowed toward an equality,
  a rolled-back `headsup` marker would have no later tick to re-send it, producing
  permanent silence. This dependency is asserted as an ADR-037 invariant and pinned
  by a re-send test.

## Alternatives Considered

- **Prune the subscription after N consecutive non-410 failures.** Rejected:
  destructive on a signal we cannot distinguish from a transient network failure.
  The firewall-DROP case (#5046) would permanently delete a device that works again
  the moment the allowlist changes. The email fallback already guarantees the notice
  lands; 410-only pruning stays, and the non-410 case is handled by fallback plus
  the existing `webpush-send-failed` Sentry mirror. Re-evaluate only if
  `webpush-send-failed` volume shows a persistent dead-endpoint population.
- **Leave the marker and rely only on the warn.** Rejected: it surfaces the failure
  but does not deliver the notice, and leaves the #6781 "certifies a non-send as
  sent" defect in place.
- **Make `notifyOfflineUser` throw on total failure.** Rejected: breaks the
  documented "never throws" contract two call sites rely on, and under `retries: 0`
  a throw inside the cron loop would kill the ingress liveness probe.
- **A `NotifyOutcome` struct instead of a boolean.** Rejected (plan-review M3): the
  only consumer reads one bit; the emit's `{channel, fallbackDelivered}` fields are
  local to `notifyOfflineUser`. A struct with a field no caller reads is ceremony;
  introduce it if a second consumer ever needs the channel.
