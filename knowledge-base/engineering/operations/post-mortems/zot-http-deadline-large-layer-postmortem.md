# Incident Overview

**Slug:** `zot-http-deadline-large-layer`
**Date:** 2026-08-13 → 2026-08-16
**Source PR:** #7552 · **Work target:** #7555

## Status

Resolved in #7552. Delivery to the production host is automated by the replace dispatcher shipped in the same PR; soak verification is enrolled on #7556 and currently blocked by #7569.

## Symptom

`Web Platform Release` failed at the zot mirror, stage `copy_v`, after all three attempts:

```
Error: Patch "http://127.0.0.1:5000/v2/jikig-ai/soleur-<img>/blobs/uploads/cf03ae4f-...":
  readfrom tcp 127.0.0.1:45780->127.0.0.1:5000:
  write tcp 127.0.0.1:45780->127.0.0.1:5000: write: connection reset by peer
zot mirror FAILED at stage 'copy_v' — This release is BLOCKED and will not deploy.
```

The upload started and received a session id each time, then the peer went away partway through writing the layer. From the client this is indistinguishable from a registry that is crash-looping — which is why it was initially attributed to the wrong cause.

## Incident Timeline

| When (UTC) | What |
|---|---|
| 2026-08-04 → 08-10 | `/var/lib/zot` at 100% (#7341). A real, *separate* problem. |
| 2026-08-10 | A recut emptied the store; `pcent` dropped 100 → 8. |
| 2026-08-13 17:02 | `220255759` releases successfully — the 12th consecutive success that day. |
| 2026-08-13 (later) | Run 31740550632 on `910f237f0` fails at `copy_v`. Release blocked; nothing half-shipped (no tag, no version consumed). |
| 2026-08-13 | The run's own `SOLEUR_ZOT_DISK` diagnostic returns **no `zot_restarts` samples**. The unconditional pointer routes the reader to disk/restart telemetry regardless. |
| 2026-08-13 22:28 | Measured refutation posted to #7341: store not full, `zot_restarts=0`, uptime monotonic. |
| 2026-08-14 18:39 | #7341 **auto-closes on its own sweeper** — `pcent=12`, slope `-0.29pp/day`, 550 samples/72 h. |
| 2026-08-14 19:06:58 | The registry's log delivery stops (#7569, filed by this work). The host keeps serving — `zot_restarts=0`, `pcent` 12→14 — so this is a telemetry outage, not a registry outage. |
| 2026-08-16 20:45 | Log delivery resumes — the Better Stack **free-plan quota had been exceeded**; a paid plan restored ingest (operator-confirmed). Corroborated by two independent markers, 8 consecutive heartbeat buckets. |
| 2026-08-16 | Root cause established, fix + guards + delivery dispatcher shipped in #7552. |

## Participants and Systems Involved

zot registry v2.1.20 (pinned by digest) on the cloud-init-only registry host (ADR-096); `reusable-release.yml`; `build-inngest-bootstrap-image.yml`; Better Stack / ClickHouse warehouse.

## Detection (+ MTTD)

**MTTD ≈ 0 for the failure; ~1 day for the cause.** The release failed loudly and blocked itself — the fail-closed behaviour worked exactly as designed. What took a day was establishing *why*, because the workflow's own diagnostic asserted a cause it had not measured.

## Triggered by

No change triggered it. The layer crossed a time budget that had been shrinking for months. The immediately-preceding merge contained only a bash test script and markdown, and the workflow measured the registry-push credential as `live`.

## Root-cause hypothesis (triage)

Initially — and wrongly — attributed to #7341's disk-full restart loop, on the strength of the client-side signature and the workflow's unconditional pointer.

## Resolution

`readTimeout` and `writeTimeout` set to `1800s` in the registry host's `/etc/zot/config.json`. Both, not one: `readTimeout` alone yields a zot-side 202 with no response to the client — a silent success, worse than an honest 500.

## Recovery verification

Guard 3 renders the config and **boots the pinned zot digest against it**, with a `zzzboguskey` negative control. The #7556 probe verifies delivery off-box by reading zot's own boot `configuration settings` line. Run on 2026-08-16 it returned **TRANSIENT (exit 2)** — correctly refusing to certify delivery it could not yet observe, rather than reporting a false PASS. (The `configuration settings` line is emitted at boot, and the replace had not run.)

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the release fail?** zot closed the connection mid-`PATCH`.
2. **Why?** The request exceeded zot's `ReadTimeout`/`WriteTimeout`, both defaulting to `60000000000` ns.
3. **Why did it exceed?** The largest layer is 703,724,542 B and cannot transfer inside 60 s at the throughput the runner sustains.
4. **Why had a 60 s default worked until now?** It is a **time wall, not a size wall**. Layer sizes grew gradually, so the failure arrived intermittently (~1 in 13) rather than as a clean regression — and an intermittent failure reads as flakiness.
5. **Why was it misdiagnosed for a day?** The release workflow appended **one unconditional line** naming registry-host disk and restart telemetry to *every* stage's failure — a cause that job never measured. For a `copy_*` failure the bytes were in flight to zot, so host health was the wrong channel entirely.

**The systemic root cause is #5.** A wrong pointer is not a missing diagnosis; it is a false one, and it cost more than the bug did. This is the failure ADR-166 exists to prevent, occurring inside a workflow that predates it.

## Versions of Components

zot v2.1.20 (digest-pinned); Hetzner `cpx22`; registry host user_data delivered by cloud-init only.

## Impact details

### Services Impacted

The release pipeline. Production itself stayed healthy throughout.

### Customer Impact (by role)

**No user-visible outage and no data loss.** Production continued serving `build_sha 220255759` — a healthy, fully-functional build — for roughly three days. The impact was that *new work could not ship*, not that anything broke. The blocked merge contained no production code, so no user-facing change was actually waiting on it.

### Revenue Impact

None measured.

### Team Impact

One day of diagnosis routed at a stale cause, plus two review rounds' worth of rework on the verification machinery (18 findings, all green when found).

## Lessons Learned

1. **A CI message that names an unmeasured cause is worse than silence.** It does not merely fail to help — it actively routes every subsequent reader, including the ones with better instincts, at the wrong subsystem. ADR-166 already said this; this workflow had not been swept for it.
2. **A client-side symptom is not a diagnosis.** "Connection reset mid-upload" is produced by a crashing peer *and* by a peer enforcing a deadline. The two are byte-identical to the client and require server-side evidence to distinguish — which is exactly what the dark channel (#7569) denies.
3. **A stale issue title outlives its truth.** #7341 said "100% full" long after a recut had emptied the store, and that title did more diagnostic work than the telemetry did.
4. **Every mechanism built to prove the fix was itself broken, and every one was green.** Nine defects in round one, nine more in the fixes for those. The generalizable litmus: *a guard's fixture is a claim about production, and it is the claim nobody checks.* Full detail in `knowledge-base/project/learnings/2026-08-16-every-mechanism-i-shipped-to-prove-the-fix-was-itself-unproven.md`.
5. **A guard that reads the environment has two behaviours.** The preflight suite measured 18/18 locally and 6/18 in CI because its subject refuses its test seams when `GITHUB_ACTIONS` is set. Running a suite in only one of its environments measures half the program.

6. **A vendor quota ceiling took out observability, and the quota check was human-driven.**
   `scripts/followthroughs/betterstack-quota-verdict-5105.sh` exists and knows the 25k/day
   threshold, but it reads a verdict a human posts on the tracking issue — so nothing autonomous
   was watching the number that eventually silenced the fleet's telemetry for ~49 hours. A
   threshold that is known, and a probe that cannot read it without a person, is not a monitor.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #7556 | Soak-verify the raised deadlines landed on the running host and the `i/o timeout` sub-mode stopped; enrolled with the sweeper, `earliest=2026-08-21` | open |
| #7569 | Now the LIVE host for the channel regression detector. Root cause was Better Stack free-plan quota exhaustion, resolved by subscribing to the paid plan; the probe that should have reported the ~49h outage was enrolled on #7455, an issue in the closed state, and the sweeper lists `--state open` — so it had never run | open |
| #7582 | Make the replace dispatcher compare the rendered `user_data` at both SHAs rather than the template, so a zot digest bump cannot merge inert | open |
