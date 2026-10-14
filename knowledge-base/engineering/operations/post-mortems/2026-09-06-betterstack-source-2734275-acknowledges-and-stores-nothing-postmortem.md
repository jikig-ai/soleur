---
title: "Better Stack acknowledged every write to the git-data source and stored none of them, and the birth gate blamed the transport"
date: 2026-09-06
incident_pr: 7856
incident_issue: 7855
incident_window: "first observed 2026-09-04 (rung-2 rehearsal); still open at 2026-09-06"
recovery_at: "not recovered — source 2734275 has never stored a row; vendor escalation tracked on #7867"
suspected_change: "none in this repo — no config change correlates. The source's creation date was not measured; what IS measured is that its table has never existed, which means it has never stored a row since creation."
brand_survival_threshold: single-user incident
status: ongoing
triggers:
  - every read against t520508_soleur_git_data_prd_logs returns CLUSTER_DOESNT_EXIST
  - ingest POST to s2734275.eu-central-1a.betterstackdata.com returns 2xx with no stored row
  - the rung-2 evidence capture reported "query transport exited 22 (unreachable or unauthorised)" 20 times, naming two causes it never measured
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/observability only, and narrower than the usual form of that claim: source 2734275 has never stored a single row, and the host whose logs it would carry has not been born. No personal data was disclosed, altered, or lost, because none ever reached the vendor's storage. The write path was acknowledged and dropped; the read path was never populated to expose."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER the operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — the operator did this directly.

# Incident Overview

Better Stack returns HTTP 2xx for every ingest write to source **2734275** (the git-data host's
production log source) and stores none of them. The source's ClickHouse table
`t520508_soleur_git_data_prd_logs` has therefore never been created — Better Stack creates a
source's table lazily on its first **stored** row — so every read against it answers
`CLUSTER_DOESNT_EXIST`.

The git-data host's birth is gated on a rung-2 rehearsal that reads that source for evidence. With
the table absent, the rehearsal could not reach a verdict, and the host's provisioning has been
blocked since.

The second half of this incident is ours. The evidence capture translated the failed read into
`"the Better Stack query transport exited 22 (unreachable or unauthorised)"` and printed it twenty
times. The transport was reachable and the credential was valid. That sentence named two causes the
run had not measured — an AP-021 violation on the operator-facing surface of a birth interlock —
and it is what turned a legible vendor fault into two days of misdirected diagnosis.

## Status

`ongoing` — the storage failure is not resolved. This PR resolves the **diagnosis** defect (the
capture can now distinguish the three states a failed read can mean) and establishes by measurement
which state actually holds. The vendor-side fix is tracked on #7867.

## Symptom

- Every `remote(t520508_soleur_git_data_prd_logs)` read: `CLUSTER_DOESNT_EXIST` (code 701).
- Every `s3Cluster(primary, …_s3)` read on the same source: `NAMED_COLLECTION_DOESNT_EXIST` (669).
- Every ingest POST: `http=202`, body acknowledged.
- The rung-2 capture: 20 × `TRANSIENT: the Better Stack query transport exited 22 (unreachable or
  unauthorised)`.
- The git-data host: not born.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-09-04 15:46Z | Rung-2 rehearsal run; capture reports a transport failure 20×. Issue #7855 filed (`compliance/critical`) with the open question stated as a two-way fork: ingest→query latency, or accepted-but-not-stored. |
| agent | 2026-09-04 | Plan written; ADR-192 (an empty warehouse read is three states, not one) drafted. |
| agent | 2026-09-06 15:04Z | Round-trip probe run once against production under explicit operator authorisation. POST acknowledged (2xx). |
| agent | 2026-09-06 (same session, minutes after the write) | `remote(t520508_soleur_git_data_prd_logs)` still `CLUSTER_DOESNT_EXIST` after the acknowledged write. The control source is storing normally in the same window, and the account-wide outage #7811 is closed. Exact clock time not recorded. |
| agent | 2026-09-06 18:03Z | #7873 filed. Review round 2 establishes that the probe's own `ROUNDTRIP_NOT_STORED` verdict could not have carried the finding (see 5-Whys #4); the conclusion is re-grounded on the independent table-absence check, which is unaffected. |
| agent | 2026-09-06 (end of session) | PR #7856 opened with the capture fix, the credential-bypass fix, and this PIR. Storage failure still open. |

## Participants and Systems Involved

- Better Stack (Logs/ClickHouse warehouse) — sources 2734275 (git-data, failing) and the shared
  control source (healthy).
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — the birth gate's evidence capture.
- `scripts/betterstack-ingest-probe.sh` — the ingest reachability probe.
- `.github/workflows/git-data-rung2-rehearsal.yml` — the rehearsal that consumes the capture.

## Detection (+ MTTD)

- **How detected:** by the rung-2 rehearsal failing to reach a verdict — i.e. by a *dependent* gate,
  not by any monitor of the source itself. No alarm exists that fires when a Better Stack source
  acknowledges writes and stores none.
- **MTTD:** not determinable, and that is itself the finding. Because the source has never stored a
  row, there is no stored-data timeline against which to bound "when it started" — the failure has
  no observable onset. The first *observed* symptom is the 2026-09-04 rehearsal.

## Triggered by

provider — the vendor acknowledges and drops. No change in this repo correlates with the onset.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| (a) ingest→query latency exceeds the capture's polling window | ADR-172 records a 17s POST→queryable floor, so *some* latency exists | a 349s readback window (20× that floor) never retrieved the marker; the table is absent, which latency does not explain — a stored-but-not-yet-queryable row still creates the table | **refuted** |
| (b) writes acknowledged but not stored, source-specific | table absent after an acknowledged write, and Better Stack creates it on the first stored row; the control source stores normally in the same window | none | **confirmed** |
| (c) account-wide vendor outage (#7811 recurrence) | #7811 is a real precedent with the same 2xx-and-nothing shape | #7811 was already CLOSED at measurement time, and the control source stored normally in the same window | **refuted** |

## Resolution

**Not resolved for the storage failure.** Resolved for the diagnosis defect:

- The capture now performs a **control read against a different source** before naming a cause, and
  emits one of three distinguishable readings: nothing ever stored to this source / the warehouse is
  dark for every producer / the instrument itself is unusable. The vendor error codes (701 vs 669)
  ride along as the *reason*; the control read decides.
- `INGEST_ACCEPTING` → `INGEST_ACKNOWLEDGED`, and its `detail=` now states that storage was not
  established and names the instrument that can establish it.
- A round-trip follow-through probe (#7867) writes a marker and reads it back, so the question
  "does this source store?" is answerable by a scheduled job rather than by a human.

## Recovery verification

The recovery probe is `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh`, enrolled on
issue #7867 and run daily by the follow-through sweeper from `earliest=2026-09-07T00:00:00Z`. It exits 0
(and closes the tracker) only when a marker written to source 2734275 is read back. Until then the
tracker stays open by design.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why is the git-data host not born?** The rung-2 rehearsal cannot reach a verdict.
2. **Why can it not reach a verdict?** Every read of its evidence source returns
   `CLUSTER_DOESNT_EXIST`.
3. **Why does the table not exist?** Better Stack creates a source's table on its first stored row,
   and source 2734275 has never stored one — every write is acknowledged with 2xx and dropped.
4. **Why did that take two days to establish?** Because the only signal anyone had said something
   different and false: the capture reported a transport failure. It reached that sentence by
   deriving a cause from an exit code that carries none, which is the AP-021 class. The same class
   then recurred **inside this fix** — the new round-trip probe `UNION ALL`-ed an `s3Cluster` arm
   whose named collection does not exist for this source, so its readback failed on every poll
   regardless of storage; it consulted a *different*, healthy control table, found it live, and
   emitted `ROUNDTRIP_NOT_STORED` (exit 1, a public vendor data-loss accusation) off a query that
   never ran. That verdict was reported to the operator before review caught it. And a THIRD
   instance was found at ship, after both sign-offs were recorded: the same rc-only reading, in the
   capture's own three reads and again in the round-trip probe's `_read_ever_answered` — the gate
   whose comment block explains the second instance. The class did not merely recur in the fix; it
   recurred inside the paragraph documenting the fix.
5. **Why was there nothing else to look at?** Because no alarm watches "a source acknowledges and
   stores nothing". Ingest acknowledgement was treated as storage everywhere — the probe's own token
   was literally named `INGEST_ACCEPTING`, and it printed green throughout the ~31 hours
   #7811 was open (2026-09-03 20:55Z → 2026-09-05 04:02Z), an issue titled *"Better Stack is
   accepting no writes"*. **An acknowledgement was load-bearing evidence for
   a property it does not establish, in a gate authorising a production host's birth.**

## Versions of Components

- **Version(s) that triggered the outage:** none in this repo — the storage failure is vendor-side.
  The capture's false-cause sentence was introduced with the capture itself, in `be7b5a5ee`
  (#7066, "the guards review proved could not fire") — measured with
  `git log -S 'unreachable or unauthorised' -- scripts/followthroughs/git-data-rung2-evidence-capture.sh`,
  whose first hit is that commit.
- **Version(s) that restored the service:** none — not restored. PR #7856 restores *legibility*, not
  storage.

## Impact details

### Services Impacted

- git-data host provisioning: **blocked** for the duration (the host does not exist).
- git-data log observability: **absent** — every log line written to source 2734275 is lost. Nothing
  consumes those logs yet, because the host is not born.
- The shared control source and the web-platform log path: **unaffected** (verified storing normally
  in the same window).

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

The one affected party is the operator, who is the sole user: a host they were provisioning stayed
blocked, and the reason they were given for two days was false.

### Revenue Impact

None.

### Team Impact

Two days of diagnosis pointed at the wrong subsystem (transport/credential) by the capture's own
sentence.

## Lessons Learned

### Where we got lucky

The host is not born. Had it been, its logs would have been silently dropped with a green ingest
probe reporting `INGEST_ACCEPTING` the whole time — and the first thing anyone would have wanted
those logs for is diagnosing whatever made them look.

### What went well

- The birth gate held. A capture that could not reach a verdict refused to emit one, so the
  interlock did its job even while explaining itself wrongly.
- The review panel caught both P1s, and one of them — `_rt_host` unassigned under `set -u` — was
  found by `shellcheck` in seconds after reading and two agents had missed it.

### What went wrong

- **A signal named two causes it never measured**, on the operator-facing surface of a production
  interlock, and printed it twenty times.
- **The same class recurred inside its own fix** (5-Whys #4), and produced a public vendor
  data-loss accusation from a query that could not have succeeded. It was reported to the operator
  as evidence before review retracted it.
- **An include guard added to fix a P1 shipped a P1**: keyed on `_BS_SOURCES_LIB_LOADED`, an
  inheritable environment variable, so one exported name made the destination allowlist compare two
  attacker-supplied strings; reproduced sending a live ingest write token to
  `https://attacker.example.org/collect`.
- **The ingest probe's destination allowlist was decorative.** `https://*.betterstackdata.com/*` as
  a shell glob accepts `https://evil.com/?x=.betterstackdata.com/`, and the probe forwards a bearer
  token. This was live on `origin/main`.
- **No monitor exists for acknowledged-and-not-stored.** Detection came from a dependent gate.
- **The interlock had a second way to clear a host on evidence it never read, and three reviews
  walked past it.** `betterstack-query.sh` runs curl `--fail-with-body`, which returns 0 for an
  HTTP 200 carrying a ClickHouse mid-stream exception; all three of the capture's reads were gated
  on that rc. Reproduced at ship: a fatal read answering `Code: 241. DB::Exception: ...
  (MEMORY_LIMIT_EXCEEDED)` at rc 0 carries no `"level":"fatal"`, so the FAIL arm did not fire and
  the run wrote `RUNG2_BOOT_REHEARSAL=PASS`. The comment above that gate states the correct
  invariant — *"an unanswered fatal query is NOT a clean bill"* — and the predicate beneath it
  measures the transport instead, which is how two review panels and a targeted user-impact pass
  all read the right sentence and approved the wrong check. Fixed in the same PR; the shared
  predicate that catches it (`bs_absence_response_is_answer`) already existed and was `source`d
  inside the one branch that could not need it.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #7867 | Establish by measurement whether source 2734275 ever stores an acknowledged write; escalate to Better Stack with the round-trip evidence. Enrolled in the follow-through sweeper with a committed probe — this is the recovery verification for this incident. | engineering |
| #7873 | Three pre-existing scripts forward a Better Stack ingest bearer token to an unvalidated, env-settable destination. An inline fix was implemented and reverted (the zot suite runs real loopback listeners, which a vendor-host pin refuses); it needs its own PR. | engineering |
