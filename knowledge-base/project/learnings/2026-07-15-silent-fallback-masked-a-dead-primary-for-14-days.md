---
title: "A silently-working fallback masked a dead primary for 14 days — alarm on fallback USAGE, not just on total failure"
date: 2026-07-15
category: best-practices
module: apps/web-platform/infra (zot registry / ci-deploy pull path)
issue: 6400
refs: ["#6400", "#6288", "#6285", "#6122", "#6415", "#6416", "ADR-096"]
tags: [observability, fallback, silent-degradation, continue-on-error, github-actions, registry, soleur-user]
---

# A silently-working fallback masked a dead primary for 14 days

## Problem

The container-image pull path is **zot-primary → GHCR atomic fallback** (ADR-096). On
2026-07-14 the `web-platform-release` deploy froze on GHCR `image_pull_failed`, and the
investigation surfaced something worse than the reported symptom:

**zot had served ZERO pulls for 14 days.** Every deploy in that window silently rode the
GHCR fallback. Nothing was broken *visibly* — until GHCR also degraded, at which point a
boring, isolated problem ("the registry host is unreachable") presented as a compound P1
across two registries, and took hours of archaeology through four wrong hypotheses
(credential class → firewall → store OOM → host boot) to unwind.

Two independent mechanisms conspired to keep it invisible:

**(a) The fallback worked.** `pull_image_with_fallback` degrades zot→GHCR by design
(correct!) — but a degrade that always succeeds emits no failure, so the primary's death
is indistinguishable from health at every surface an operator looks at.

**(b) A `continue-on-error` step made a failing gate look green.** CI's
`Bridge to zot registry (CF Tunnel)` carries `continue-on-error: true`, so its **conclusion
was `success`** (green in the UI) while its true **`outcome` was `failure`**. The dependent
mirror step is gated `if: steps.zot_bridge.outcome == 'success'` — so
`Mirror image GHCR→zot (crane)` **silently skipped on every release**, zot never received a
new image, and the release stayed green. The workflow even printed
`⚠️ zot mirror degraded — release OK (GHCR primary), zot redundancy reduced; backfill needed`
— into a log nobody reads.

The signal for (a) *existed*: `registry_pull_event` emits `registry=ghcr-fallback` at
`level=warning` precisely as the watched soak signal, and `scripts/followthroughs/zot-soak-6122.sh`
counts them. **Nothing alarmed on it.** #6285 already tracked "upgrade the zot
mirror-staleness alarm" and was DEFERRED pending a notify target.

## Solution

1. **Alarm on sustained fallback usage, not only on total failure.** `registry=ghcr-fallback`
   sustained above ~0 for N hours ⇒ the primary is dead. Un-defer #6285.
2. **Never trust a `continue-on-error` step's green conclusion.** Gate consumers on
   `outcome`, and when a "belt" step degrades, emit a *monitored* marker (Sentry/`SOLEUR_*`
   stdout), not a log line. See the `ci-workflow-authoring.md` entry added with this learning.
3. Root cause of the dead primary itself: a transient first-boot IMDS failure left the
   registry host without its private NIC (#6415); the mirror can't reach zot because the CF
   tunnel origin (`web-2`) has no private IP (#6416).

## Key Insight

**Degraded-but-working is the state that kills you later.** A fallback converts a
loud failure into a silent liability: the system banks unpaid risk until the fallback
*also* fails, and then you debug two failures at once, under P1 pressure, with the
primary's failure now 14 days cold (logs rotated, cause obscured).

Design rule — for any primary→fallback path (registry, DB replica, API provider, cache,
queue):

- **The fallback firing is itself the alert.** Alarm on fallback RATE/duration, at a
  low severity, continuously. "Total failure" alarms are necessary but they only fire
  after redundancy is already gone.
- **A silent skip is worse than a failure.** If a step can be skipped by a masked
  `outcome`, its skip must emit a monitored signal.
- **Zero of a success metric is a signal.** "zot served 0 pulls in 14d" was queryable the
  whole time; nothing asked. Prefer an absence-of-success alarm over a presence-of-failure
  alarm for anything with a fallback.

**Soleur-user framing (why this matters beyond engineering):** a non-technical founder
*cannot* notice "zot has served 0 pulls since July 1." They have no dashboard instinct and
no infra access. For them, silent degradation is indistinguishable from health right up to
the compound outage that needs an expert. Every fallback we ship must therefore self-report
its own use — the system tells the operator, the operator never has to go looking
(`hr-no-dashboard-eyeball-pull-data-yourself` applied to *degradation*, not just errors).

## Session Errors

- **Misread a `continue-on-error` step as succeeding.** The bridge's green `conclusion`
  hid `outcome: failure`, so I initially reported "the zot mirror push SUCCEEDED" when it
  had skipped. **Prevention:** when a step is `continue-on-error`, read `outcome` (not
  `conclusion`); a dependent `if: steps.X.outcome == 'success'` that skips is the tell.
- **Misread idle metrics as a dead host.** Hetzner `network=0/disk=0` over the *current*
  window meant the host was idle (nothing could reach it), not that it failed to boot — I
  should have queried the **boot window** when cloud-init ran. **Prevention:** when using
  time-series metrics to infer a boot failure, query the boot window, not now.
- **Let a correlation override documented platform behavior.** `git-data.tf` explicitly
  documented "Hetzner firewalls filter only the public interface"; I inferred the opposite
  from an inngest-vs-registry correlation while holding disconfirming evidence (git-data,
  *no* firewall, also unreachable). **Prevention:** when a code comment documents platform
  behavior and a correlation contradicts it, verify the platform behavior before acting.
