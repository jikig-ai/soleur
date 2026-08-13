---
title: zot's HTTP deadlines are sized to the largest layer and bounded above by gcDelay
status: adopting
date: 2026-08-14
issue: 7555
---

# ADR-189 — zot HTTP deadlines are sized to the largest layer, not left at the 60 s default

## Context

`Web Platform Release` intermittently failed at the `zot mirror` step, stage `copy_v`, with
`connection reset by peer` mid-blob-upload. The shape — an upload that starts, gets a session id, and
dies partway through writing the layer — reads from the client side exactly like a registry that is
restarting, and it was attributed to #7341 (`/var/lib/zot` full, zot restarting ~4x/min) on that
resemblance.

That attribution was measured and is false. Across the failure window `zot_restarts=0`,
`zot_uptime_s` rose monotonically on the 300 s heartbeat tick, `state_status=running`, and there had
been no restart in 48 hours; `pcent=12`, not 100; and gc completed for `soleur-web-platform` at 20:01
and 21:01, which is the repo upstream zot#4235 describes as never completing.

The cause is zot's own defaults. The deployed `config.json` has an `"http"` block with **no timeout
key**, and zot v2.1.20 supplies `ReadTimeout` and `WriteTimeout` of `60000000000` ns — 60.000 s —
built in. A 703 724 542 B layer must therefore sustain 11.73 MB/s, and three concurrent layers
~280 Mbit/s through one tunnel, or the deadline expires mid-`PATCH`:

```
message: unexpected error, removing .uploads/ files
error:   read tcp …:5000->…:52888: i/o timeout
caller:  zotregistry.dev/zot/v2/pkg/api/routes.go:2078
func:    …api.(*RouteHandler).PatchBlobUpload
```

This was reproduced off-box against the pinned digest over a docker bridge with **no tunnel and no
Cloudflare edge**, by dribbling a 4 MB blob over 100 s: same message, same `routes.go:2078`, same
`statusCode:500`, same `latency:1m0s`. Two consequences follow that are not obvious from the symptom
and are the reason this record exists:

- **The Cloudflare tunnel is exonerated** for a class of failure it has been carrying blame for. That
  is a correction to the shared model of this subsystem, not a value change.
- **It is a time wall, not a size wall.** The 272 MB layer failed at the same deadline, putting
  effective throughput under ~4.5 MB/s. Shrinking layers is therefore refuted as the remedy from
  evidence already in hand, rather than being merely untried.

## Decision

**Set both `readTimeout` and `writeTimeout` explicitly in the zot `"http"` block, sized to the
largest layer at the observed floor throughput, and strictly below `gcDelay`.**

Three properties, each of which is invisible at the call site where it can be violated:

1. **Both keys move together.** Setting `readTimeout` alone was measured to yield a zot-side `202`
   with no response reaching the client — a split-brain strictly worse than today's honest `500`,
   because the client cannot tell a hung upload from a slow one. The failure mode of moving one key
   is *silent success*, which is why this is a decision and not a value.
2. **The deadline is bounded above by `gcDelay`.** These are configured in the same document and read
   by different subsystems; a deadline at or above `gcDelay` lets gc reclaim staging for an upload
   still in flight. Neither call site shows the coupling.
3. **The invariant, not the literal, is what is enforced.** Guard 3 fails the rendered `config.json`
   on a missing pair-half, on either deadline below the largest-layer budget, and on either at or
   above `gcDelay` — and carries a negative control proving the pinned digest rejects an unknown key,
   without which "the config was accepted" means nothing.

The number itself lives next to the setting in `apps/web-platform/infra/cloud-init-registry.yml` in
the #7282 house style, recording what was measured and instructing *re-measure on every zot bump,
never re-word*.

For the message-honesty half — that a CI message may only name a cause the job actually measured —
this ADR cites **ADR-166** rather than restating it. The copy-stage arm's unconditional pointer at
registry-host disk telemetry is precisely an ADR-166 violation, and it is what sent this
investigation at the refuted framing above.

## Consequences

- The registry host's `user_data` changes, so delivery is a ForceNew **replace** of the fleet's sole
  pull path (ADR-096: the host is cloud-init-only; there is no SSH edit path). Because a config zot
  rejects fails *after* a successful destroy and create, on a host that is then unreachable, the
  rendered config must be validated against the pinned digest before merge — Guard 3 — rather than at
  apply time.
- Grading is deferred to a soak, tracked on #7556. Two criteria are deliberately **excluded**:
  "the next release succeeds" (at the measured ~1-in-13 failure rate this passes ~92% of the time
  unfixed) and anything covering `unexpected EOF`, which is a second, distinct sub-mode observed
  during a *successful* run and is not addressed here.
- The existing 3x retry loop stays exactly as written. It cannot clear a deterministic deadline, but
  it does clear the EOF sub-mode; removing it as "futile" would be a regression.

## Relationship to ADR-167

ADR-167 (container-registry write-path topology) is CPO-gated at this same threshold over this same
subsystem, and the restart-plateau measurement above fires its re-open trigger: the topology question
was framed partly around origin instability that the telemetry now shows was not occurring during
this failure.

This ADR **states that relationship and does not decide it.** Re-opening ADR-167 is a separate call
at its own gate; recording the trigger here keeps the finding from being stranded in a plan.

## Status

`adopting` until the #7556 soak returns a PASS verdict, at which point this moves to `accepted`.
