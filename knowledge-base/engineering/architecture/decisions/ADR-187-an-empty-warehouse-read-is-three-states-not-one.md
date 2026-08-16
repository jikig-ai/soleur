---
id: ADR-187
title: "An empty warehouse read is three states, not one"
status: adopting
date: 2026-08-16
issue: 7569
supersedes: []
related: [ADR-166, ADR-170, ADR-184]
---

# ADR-187 — An empty warehouse read is three states, not one

## Status

`adopting`. The classifier and its two consumers ship with this ADR. The volume-reduction half
(Vector-side ceilings) and the blast-radius sweep across the other absence-asserting consumers
are tracked separately; see [Scope](#scope-what-this-adr-does-not-decide).

## Context

On **2026-08-14 19:06:58Z** Better Stack stopped accepting writes. Every ingest POST has since
returned `HTTP 402 {"error": "Quota exceeded"}`. The **read** path kept answering `200`
throughout.

That asymmetry is the whole incident. Every absence query against the source returned `rc=0`
with zero rows, and the two detectors watching that source both read the result as benign:

- `scripts/zot-restart-loop-alarm.sh` collapsed the two cases with a single `||`:

  ```bash
  CONTROL="$("$BQ" --since "$WINDOW" --limit 1 2>/dev/null)"; control_rc=$?
  if [[ "$control_rc" -ne 0 || -z "$CONTROL" ]]; then
    VERDICT="TRANSIENT"; DETAIL="… — Better Stack unreachable / creds unset"
  ```

  It reported the non-alarming `TRANSIENT` every 30 minutes for two days, and the message named
  two causes the run had just measured **false** — `control_rc` was `0`.

- The `#7556` soak probe correctly returned `TRANSIENT reason=no-config-line`, which is the
  right behaviour and still produced no page.

The registry host is the fleet's sole image-pull path and has no SSH by policy, so this channel
is its only off-box view. While it was dark, a crash loop, a filling disk or an upload failure
would each have produced no signal at all.

### Why nothing caught it

Three independent guards were green throughout, and each was green for a different reason:

1. **The alarm** conflated "the query failed" with "the query answered and found nothing".
2. **The workflow** reported `completed/success` every run, because the detector *ran*.
3. **`scripts/lint-diagnosis-claims.sh`** — the AP-021 gate that exists to stop a CI message
   naming an unmeasured cause — did not flag the alarm's message at all. Its `CLAIM` pattern is
   a fixed phrase list (`most likely cause`, `caused by`, `is the cause`, …). The alarm named
   its causes with an **em-dash appendix** (`— Better Stack unreachable / creds unset`), a form
   the detector does not model. The gate was not bypassed; it was blind.

The measured shape rules out every producer-side explanation. Ingest was a flat ~5,500 rows/hour
through 18:00 on 08-14, 612 in the 19:00 hour, then nothing — a clean cliff with no ramp. Every
producer on the source stopped at the same instant, so the common factor is the destination. The
source is not paused, its table is unchanged, the endpoint in `zot-registry.tf` matches the API's
reported `ingesting_host`, and the ingest token in Doppler matches the source's current token in
both projects that hold it.

## Decision

### I-1 — An empty read is classified into three states, never two

`scripts/lib/betterstack-absence.sh` is the single implementation:

| Verdict | Meaning | Exit |
|---|---|---|
| `TRANSPORT_FAIL` | the read did not answer (non-zero rc, or a 200 carrying a mid-stream `DB::Exception`) — **we learned nothing** | 2 |
| `INGEST_DARK` | the read answered and the source holds no row of any kind — **we learned the source is taking no writes** | 4 |
| `LIVE` | rows came back | 0 |

The rc branch and the emptiness branch are separate `if`s. Collapsing them with `||` is the
defect; a mutation row asserts the collapse drives the suite red.

`TRANSPORT_FAIL` and `INGEST_DARK` are not severity levels of one thing. They are different
epistemic states calling for opposite operator actions — one says retry, the other says the
evidence store is down and every absence signal on it is unreadable.

### I-2 — No marker predicate may be satisfiable by a row an attacker can influence

The predicate this replaces was an unanchored `raw LIKE '%SOLEUR_PROBE_CANARY%'` scoped only by
`host_name`. `host_name` is Vector-injected and not attacker-settable, but it pins the **host**,
not the **producer** — and the web container runs on that host, reachable by an unauthenticated
party who can write attacker-chosen text into this shared source.

The only thing separating an HTTP request from a forged "the channel is alive" was that
ClickHouse `LIKE` is byte-case-sensitive while the origin resolver lowercases. That call exists
for origin comparison. It is not documented as a log-safety control and nothing tested it.

Marker-mode controls therefore anchor on the **envelope prefix** — the form already proven at
the NIC leg, which survived the live 2026-07-15 incident where three GitHub-webhook rows quoting
a marker were returned by a substring match.

### The two anchor modes are deliberate, and conflating them would be a regression

| Mode | Question | Used by |
|---|---|---|
| `marker` | did *this producer's* heartbeat come back? | `betterstack-assert-absence.sh` |
| `any-row` | is the source receiving *anything at all*? | `zot-restart-loop-alarm.sh` |

`any-row` is the correct instrument for an **account-wide** refusal, and producer-anchoring it
would not harden it — it would change what it measures and misreport a live source carrying only
other hosts' rows as dark.

**Recorded residual, not papered over:** in `any-row` mode a single forged row masks darkness,
because an unauthenticated party can write into this shared source. That is not fixable from the
reader side. Rate-capping that write path is a **security control**, not housekeeping — an
unauthenticated third party holds a write handle on the vendor bill — and is tracked separately.

### The ingest probe annotates the cause and never holds a veto

`scripts/betterstack-ingest-probe.sh` reports the refusal code (402 quota / 401 auth / 2xx
accepting / unreachable). The verdict of record stays the reader-derived one. Inverting that
would reintroduce this exact outage, in which a healthy-looking signal — the 200 from the read
path — was available and misleading for two days.

**The probe writes nothing.** Measured against the live endpoint on 2026-08-16: an empty batch
(`[]` or `{}`) is refused with the same 402 as a real payload, and a bad token returns 401. This
is load-bearing rather than tidy: the alarm's control is an unfiltered "is there any row", so a
probe that wrote its own marker would satisfy that control forever and convert a two-day outage
into a permanent blind spot. The probe would mask the silence it exists to detect.

The one arm not measured against production is `2xx`, because the account was already over quota
when this was written. It is covered by the unit suite and by the time-gated soak follow-through.

### The alarm channel must be independent of the monitored vendor

`INGEST_DARK` surfaces as a deduped `[ci/betterstack-ingest-dark]` GitHub issue. It checks in to
Sentry as `ok`, following this file's existing "a FIRE is not a monitor error" doctrine — and
because routing the report of a Better Stack outage through Sentry would put it in a channel this
repo cannot assume is healthy. The Sentry PAYG seat cap has silently disabled cron monitors here
before.

## Consequences

- A silent stop of this source now alarms within one 30-minute cycle instead of going unnoticed
  for two days.
- Exit `4` is added to the alarm's contract. The workflow maps it explicitly; an unmapped exit
  would have degraded to an unread `::warning::`, which is the failure shape being fixed.
- `zot-restart-loop-alarm.test.sh` S9 previously asserted `TRANSIENT` for the outage state. A
  test that pins a non-alarming verdict on the outage state certifies the bug, so it moved with
  the fix, and S9c was added as its must-PASS twin.
- **Restoring ingest is an account-level billing action.** No code in this repo can restore it,
  and this ADR does not pretend otherwise.

## Scope — what this ADR does not decide

Recorded so the gaps are visible rather than implied:

- **Volume reduction.** Sustained ingest was ~132k rows/day. The dominant producer is the
  `soleur-web-platform` container at 80,320 rows/day (75%), because pretty-printed multi-line
  object logs bill one row per physical line. The Vector-side ceiling reaches production through
  a `terraform_data` re-fire over an SSH provisioner gated on `admin_ips`, a delivery path that
  has bounced on IP drift before. Split deliberately so the detector does not wait on it.
- **The blast-radius sweep** across the other absence-asserting consumers of this source.
- **The AP-021 detector gap** described above. A bounded widening measures 30 candidate hits
  across unrelated subsystems, most of them false positives in test files; the offending message
  is fixed here and the detector work is tracked on its own.
- **`vendor-quota-watch` (#5134).** This ADR **supersedes its mechanism and leaves it open with
  a re-scoped body.** Guard 1 cannot substitute for it: it reads the warehouse, which is dark at
  exactly the moment quota is exhausted. Claiming a closure this change does not deliver would
  repeat the near-miss's own defect.

## The through-line

Three green signals, one dark channel, two days. Each guard answered a question it could
actually answer — "did the detector run?", "did the query return an error?", "does this message
match a known phrase?" — and none answered "is the evidence store still accepting evidence?".

An absence of evidence is only evidence of absence once you have shown the channel could have
carried it. That is the invariant, and it is why the positive control exists at all.

## Related

- `knowledge-base/engineering/operations/post-mortems/betterstack-quota-near-miss-postmortem.md`
  — predicted this recurrence on 2026-06-10; its 5-Why #5 action item (#5134) is still open.
- ADR-166 (AP-021, diagnostic honesty) — the principle the alarm's message violated.
- ADR-170 (AP-022, errexit capture) — the pattern the new workflow step follows.
- ADR-184 — the registry container-log shipper, exonerated here: it is absent from the top-10
  producers and its 5,000/day cap held.
