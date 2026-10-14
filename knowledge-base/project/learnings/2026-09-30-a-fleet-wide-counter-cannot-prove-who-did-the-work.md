---
title: "A fleet-wide counter cannot prove which mechanism did the work — ledger the operation's own verdict"
date: 2026-09-30
category: workflow-patterns
tags: [test-design, discriminator, ledger-fields, systemd, shared-host, mutation-testing, vacuous-assertion]
issue: 9246
pr: 9260
branch: feat-one-shot-9246-oompolicy-reentry
---

# Learning: the discriminator I chose was a fleet-wide counter — fakeable in both directions, by design of what it counts

## Problem

Fixing #9246 — the memory-backstop re-entry `SetUnitProperties` carried the
creation-only `OOMPolicy` member, so on systemd >=261 the all-or-nothing call
was rejected and the refresh never applied. The fix was one member and one
arity digit; the work was proving it.

The first live-arm discriminator read `.repaired` from the ledger line:
reasoning was "if the refresh converged the degraded cap itself, the sibling
`repair_stale_scopes` arm found nothing to do, so `repaired==0`". The RED run
exposed a subtler problem first — the defective hook still read
`TasksMax=4096` and `outcome=applied`, because `repair_stale_scopes` heals the
degraded cap in the SAME pass, so a readback-only assertion was vacuous. Then
four review seats independently flagged the deeper flaw: `.repaired` counts
EVERY `soleur-agent-*.scope` healed on the host, not whether THIS scope was
healed. Both directions were corrupt on a multi-session dev host:

- *False-fail*: any unrelated stale scope (a concurrent battery's synthetic
  units, an operator-raised cap, a pre-rev-2 adoption) inflates the count →
  `repaired>=1` reds a working refresh.
- *False-pass*: a foreign session's repair pass healing the degraded scope
  before the measured run lands `repaired=0` → the defective hook greens and
  the mutation mutant reports SURVIVED.

## Solution

Ledger the operation's own verdict. The hook now records `refresh_rc` — the
exit code of the re-entry `SetUnitProperties` call itself — on the applied
ledger line (`null` on decline/creation paths where no refresh ran). The
rejection signature that IS the defect (`rc=1` on a rejecting host) cannot be
inflated by foreign work or zeroed by a foreign heal. T21 asserts
`refresh_rc==0` + `reason==ok_refreshed` + TasksMax readback; M11 KILLED on
`refresh_rc!=0`. Verified live: baseline `refresh_rc:0`, OOMPolicy mutant
`refresh_rc:1`, with `repaired=0` on both — the field separates what readback
could not.

Companion hardening this produced: the static pin gained comment-stripping,
whitespace/quote normalization (a `Name  "sig"` member in any spacing or
quote style is now judged), a singleton-block census, a token-bounded arity
match, and a per-`StartTransientUnit`-site check replacing a file-wide
literal count; the battery gained probe-unit verification (a
`SetUnitProperties` on a nonexistent unit returns rc=0 — "host accepts"
could previously mean "probe never created"), glob-excluded probe naming,
degrade-retry inside the wrapper, and an honest `inconclusive` counter.

## Key Insight

When a test must know WHICH mechanism produced an outcome, assert the
mechanism's own emitted evidence — never the absence of a sibling's activity.
A counter over a fleet is evidence about the fleet; on a shared host every
fleet read is a race with strangers. Inference-by-absence (`sibling did 0
work ⇒ I did it`) fails both ways: extra sibling work false-fails, and the
sibling doing YOUR work false-passes. And a correction's instrumentation is
worth the production edit: `refresh_rc` would have made the original defect
grep-able in every systemd-261 ledger instead of silent.

## Session Errors

1. **First T21 discriminator was vacuous on the defective hook** — TasksMax
   readback + `outcome=applied` greens because `repair_stale_scopes` heals in
   the same pass. — Recovery: discovered during the RED run, iterated to
   `.repaired==0`, then replaced with `refresh_rc` after review. —
   Prevention: when a sibling mechanism can produce the same end-state,
   mutation-test the assertion against the DEFECT build before trusting the
   green; readback asserts end-state, never attribution.
2. **`.repaired` fleet-wide counter as per-scope discriminator** — fakeable
   in both directions on a shared host. — Recovery: `refresh_rc` field. —
   Prevention: same as above; fleet counters are diagnostics, never verdicts.
3. **Accidental mixed commit** — `git add -A` staged docs + implementation
   together; reset and recommitted as two commits. — Prevention: stage by
   path list, not `-A`, when a commit is scoped.
4. **Issue filing rejected by the filing gate** — `gh issue create` requires
   `--milestone` + an accepted filing exit; the rejected attempt had also
   skipped writing the body file. Recovered by writing the file then filing
   (#9276). — Prevention: constraint was discoverable from the hook's own
   error message; write artifacts before the gated call.
5. **Backgrounded affected-gate died with the session; `/tmp` log lost** —
   relaunched under `setsid nohup` writing to `/var/tmp`. — Prevention: for
   one-shot wait-then-exit runs that must outlive a session, detach with
   setsid and log outside `/tmp`.
6. **Battery rows M7/M10 flake on foreign sweeps** — concurrent sessions'
   `sweep_unadopted_agents`/`repair_stale_scopes` interact with synthetic
   fixtures (pre-existing; rows lack the contamination handling M11 now has).
   — Disposition: filed as #9276, deferred-scope-out (pre-existing machinery
   gap, not this diff's class).

## Tags
category: workflow-patterns
module: memory-backstop
