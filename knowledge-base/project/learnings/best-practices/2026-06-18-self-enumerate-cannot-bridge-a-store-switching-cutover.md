# Learning: a "self-enumerate the current server" recovery step cannot bridge a cutover that REPLACES the server's state store

category: best-practices
module: apps/web-platform/infra (inngest cutover), #5542

## Problem

The no-SSH Inngest SQLite→Postgres cutover had a FALLBACK reminder-preservation path: `op=enumerate` the still-armed reminders, deploy, then `op=rearm`. The rearm host script **self-enumerated the current server** to source its records (a deliberate design choice — adnanh/webhook can't pipe a stdin body, and self-enumerate keeps comment bodies on-host per P2-sec-a). That self-enumerate is correct for a STEADY-STATE restart (durable Redis preserves the queue, so the events are still there). But for the FIRST cutover it is fatal: the step-4 deploy switches the event store to a fresh Postgres+Redis backend whose queue starts **empty** (spike verdict 0.2 — the armed `reminder.scheduled` queue lives in Redis, not Postgres). So `op=rearm` post-deploy self-enumerates the new empty server → 0 records → re-arms nothing → every armed reminder silently lost, and the run reports green. The exact brand-survival data-loss the feature existed to prevent.

The runbook even documented the broken order ("enumerate before, re-arm after") without noticing the rearm script didn't persist the before-capture across the store switch.

## Solution / durable rule

When a recovery/migration step sources its work-list by **reading live state**, and a later step in the same procedure **replaces or wipes that state**, the read MUST be captured to a medium that survives the replacement and the later step must consume the capture — never re-read the (now-mutated) source. Here: `op=capture` self-enumerates the OLD server and persists records to an on-host file under the volume that survives the systemd restart; `op=rearm` (mode `rearm-from-capture`) consumes that file. Three modes, not "presence of a file":

- `capture` — persist (atomic temp+rename so a partial write can't survive as readable-but-corrupt).
- `rearm-from-capture` — the capture is the ONLY valid source; missing/empty/corrupt is **FATAL**, never a silent downgrade to self-enumerate the post-switch empty store.
- `rearm` (default/steady-state) — self-enumerate; deliberately IGNORE any capture file so an orphan from an aborted cutover can't hijack a routine re-arm and replay a stale snapshot.

## Key Insight

"Self-enumerate the current server" silently assumes the server's state is invariant across the procedure. A cutover whose entire point is to REPLACE the state store violates that assumption — the recovery read and the destructive write straddle the boundary. The presence-of-a-file heuristic isn't enough either: it conflates "mid-cutover, consume this" with "orphaned stale capture, ignore this." Make the intent explicit (a mode), make the corrupt/missing case loud (the whole feature is loss-prevention, so a silent fall-through is the anti-feature), and make the write atomic (the capture crosses a restart that can truncate an un-synced write).

## Session Errors

1. **Built the FALLBACK re-arm to self-enumerate the post-deploy server — would have lost all 4 armed prod reminders on the first cutover.** Caught by reading `inngest-rearm-reminders.sh:59` against spike verdict 0.2/0.4 DURING execution, before firing any mutation (backup + read-only ops only). Recovery: halted the cutover, filed #5542, built the capture bridge. Prevention: this learning + the tristate design; the runbook FALLBACK now leads with `op=capture` pre-deploy.
2. **First capture-bridge cut had a HIGH silent-data-loss vector** (present-but-corrupt capture fell through to self-enumerating the empty backend, reported success). Caught by the adversarial silent-failure-hunter review, not by my own tests. Recovery: fatal-on-invalid + atomic write + 4 new RED cases. Prevention: for a loss-prevention feature, a reviewer prompted to REFUTE ("how does this still lose data?") earns its cost — the green happy-path suite did not surface it.
3. **The original `functions` projection (#5517, sibling-fixed) and this re-arm path both trusted a sibling/plan ASSUMPTION about an external shape instead of the captured reality** — the recurring `2026-06-16-external-api-shape-...captured-fixture-not-probed-claim` class, one layer up (a behavioral assumption about state lifetime, not a JSON shape).

## Tags
category: best-practices
module: inngest, cutover, datastore-migration, reminder-survival, #5542, #5450
related: [[2026-06-18-destructive-datastore-migration-backup-inventory-after-diff]]
