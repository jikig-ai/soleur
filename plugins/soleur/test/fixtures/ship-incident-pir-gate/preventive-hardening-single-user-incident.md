---
title: "fix: guard the statutory-deadline cron send-path against double-fire"
brand_survival_threshold: single-user incident
---

# Preventive hardening — statutory repin idempotency guard

This is a PREVENTIVE change on a path measured dark: zero runs, zero
registrations, backend not wired to prod. Current double-fire posture is clean,
so this is not presently firing.

## User-Brand Impact

**If this lands broken, the user experiences:** a statutory-deadline reminder
that never arrives while the cron reports the ping as sent.

**Brand-survival threshold:** `single-user incident`

The return type is load-bearing, not incidental. We add a send-marker so a
production deploy cannot double-fire in the future.
