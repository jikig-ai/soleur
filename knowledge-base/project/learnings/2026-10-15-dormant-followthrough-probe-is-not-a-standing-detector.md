---
title: "A follow-through probe's enrollment dies with its tracker — a check meant to outlive it is a standing alert, not a probe"
date: 2026-10-15
category: engineering
tags: [follow-through, sweeper, better-stack, dormant-detector, observability]
issue: '#10321'
type: learning
---

# Dormant follow-through probes are not standing detectors

`scripts/sweep-followthroughs.sh` reads only OPEN `follow-through` issues plus
closed ones inside `CLOSED_LOOKBACK_DAYS=14`. A probe whose tracker closes on
PASS silently stops running ~14 days later — while its header may still claim
"enrolled as a REGRESSION detector". #10321: `zot-log-channel-7440.sh` was
dormant ~7 weeks with nobody paged on the credential-shape leak it claimed to
watch.

**The fix pattern:** a check meant to outlive its tracker is a standing alert
(ADR-218 `logtail_exploration_alert`), not a probe. Port the arms to SQL, add
the `-target=` pair to `apply-web-platform-infra.yml`, a drift-guard suite under
`apps/web-platform/test/infra/` (+ `infra-validation.yml` step + runbook
`paths:` entry), a runbook, and correct every file that claimed enrollment.
Audit the OTHER dormant probes in the same pass (the audit table is a
one-shot `gh issue list` + `sweep-followthroughs.sh` read-surface check).

**Measured traps this cycle:** `{{source}}` in the tf template expands to
`remote($BS_TABLE)` (not a bare table) when live-probing via
`scripts/betterstack-query.sh`; ClickHouse `$` inside bash double-quoted guard
strings needs `\\\\\$` under `set -u`; node:crypto `update(str,'hex')` SILENTLY
drops invalid hex chars — a fail-closed key-hash replica needs explicit
validation, the vendored inngest SDK tolerates malformed input.
