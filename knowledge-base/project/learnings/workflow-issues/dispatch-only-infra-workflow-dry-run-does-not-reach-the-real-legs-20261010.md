---
title: "a dispatch-only infra workflow's dry_run validates the plan leg only — the apply/capture/teardown legs are first-run-elsewhere code"
date: 2026-10-10
issues: ["9175"]
runs: ["38009365571", "38017514694", "38021561267", "38025838564", "38031062344"]
---

# Learning: dry_run≠apply — every unexercised leg is first-run code

The #9175 rehearsal workflow shipped green through a 12-seat review and 78 sentinel
assertions, then needed FOUR fix round-trips against live runs before it completed:

1. `doppler secrets get … -p soleur -c prd` — `secrets.DOPPLER_TOKEN` is prd_terraform-scoped;
   needed `DOPPLER_TOKEN_PRD` (registry-zot-inventory precedent, per-step env + inline override).
2. A `#` comment inside `doppler run … -- \` became an argv word; the teardown leg printed usage
   and never destroyed. Every dry run skipped this leg because nothing had been applied.
3. `parseDateTime64BestEffort(s, 'UTC')` — arg 2 is PRECISION, not timezone (Code 43 every poll;
   the capture's `2>/dev/null` hid it for 20 min). Verified live: `(s, 3, 'UTC')` works.
4. The scratch Doppler env seeded 5 secrets but not `INNGEST_REDIS_LUKS_KEY`; the LUKS stage
   FATALs on an empty key (`refusing an unencrypted mount`), so `/mnt/data` never mounted and
   `bootstrap-done` arrived only DEGRADED — which the capture correctly refused to count.

Pattern: a guarded `terraform plan` exercises init+plan only. Apply-time secrets reads,
wrapper argv shape, query-dialect details, and the real service's secret contract all live on
legs the dry run deliberately does not run. Budget the rehearsal route itself for live-run
debugging — that IS the rehearsal of the harness. Each fix got a sentinel pin so the class
can't regress: ZOT_READ↔token pairing, comment-in-continuation refusal, 3-arg call shape,
LUKS key seed.

Related: the transport-stderr suppression (`2>/dev/null` around a transport that prints its
exception body to stderr) turned a findable defect into a 20-minute TRANSIENT poll loop.
Let transport errors reach the run log; the caller's job is classification, not silencing.
