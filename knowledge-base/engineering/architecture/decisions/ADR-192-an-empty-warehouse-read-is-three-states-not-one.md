---
id: ADR-192
title: "An empty warehouse read is three states, not one"
status: adopting
date: 2026-08-16
issue: 7569
supersedes: []
related: [ADR-166, ADR-170, ADR-184]
---

# ADR-192 — An empty warehouse read is three states, not one

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
   naming an unmeasured cause — never counted the alarm's message. Measured against the two
   offending lines on `main`, **three independent filters reject it**, and the first one is
   decisive:

   | filter | result | effect |
   |---|---|---|
   | `OPERATOR_LINE` | **False** | rejects first — the loop is `if not OPERATOR_LINE or not CLAIM: continue` |
   | `CLAIM` | False | never consulted |
   | `MEASURED` | True | would exempt the line anyway (`VERDICT=` matches) |

   The message is a bare shell assignment (`VERDICT="…"; DETAIL="…"`), not an `echo "`,
   `printf`, or `::error::` emission, so the gate's notion of an operator-facing line does not
   include it. The causal text then reaches the operator via `${detail_safe}` interpolated into
   a `::warning::` **in a different file** — a seam a line-scanning detector cannot cross under
   any `CLAIM` widening. The gate was not bypassed; it was looking at the wrong lines.

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

## Acceptance evidence — the guard measured in BOTH directions against production

The window that made this possible was narrow and is now closed, so it is recorded here rather
than left as a fixture claim. Both readings are from live prod on 2026-08-16, the same day, with
no code change between them — only the vendor state changed.

| | Dark (morning, ingest 402-refused) | Restored (evening, after the account action) |
|---|---|---|
| `betterstack-ingest-probe.sh` | `INGEST_REFUSED_QUOTA http=402`, exit 4 | `INGEST_ACCEPTING http=202`, exit 0 |
| `zot-restart-loop-alarm.sh` (zot leg) | `ZOT_ALARM_VERDICT=INGEST_DARK`, exit 4 | `ZOT_ALARM_VERDICT=GREEN`, exit 0 |
| `zot-restart-loop-alarm.sh` (NIC leg) | `NIC_ALARM_VERDICT=INGEST_DARK` | `NIC_ALARM_VERDICT=GREEN` |
| registry channel | zero rows / 24h | `SOLEUR_ZOT_LOG` 72/h, `SOLEUR_PRIVATE_NIC` 10/h, `SOLEUR_ZOT_DISK` 4/h |

This is what a mutation battery cannot buy. A guard proven only against fixtures is proven
against the shapes its author imagined; this one produced the alarming verdict against the real
outage and the clean verdict against the real recovery. The `2xx` arm in particular could not be
measured while the account was over quota — it was covered by the unit suite and deferred to the
soak follow-through, and it is now measured.

**The restoration does not close the volume problem, and it slightly worsens the urgency.** The
account is accepting writes again at roughly the same rate that exhausted it (~135k rows/day),
so recurrence is a matter of time rather than of chance. That work is #7577.

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

- **Volume reduction.** Measured over the only clean 24 hours that exist
  (`2026-08-13 19:00` → `2026-08-14 19:00`): **135,316 rows/day** total, of which the
  `soleur-web-platform` container is ~101,000 (75%), because pretty-printed multi-line object
  logs bill one row per physical line.

  **Correction, recorded rather than quietly fixed:** an earlier revision of this ADR cited
  `80,320 rows/day (75%)` and a `107,567` total. Both were counts over *calendar day*
  2026-08-14, which the outage truncated at 19:06:58 — a **19.1-hour** window, not 24. The
  ratio was computed inside the truncated window and then paired with a full-day denominator,
  so the two halves of that sentence came from different measurements. Every capacity figure
  derived from it is understated by ×1.26, which is material: the plan's "the upgrade is
  avoidable on capacity" conclusion rests on the low number and has not been re-derived.

  The Vector-side ceiling reaches production through a `terraform_data` re-fire over an SSH
  provisioner gated on `admin_ips`, a delivery path that has bounced on IP drift before. Split
  deliberately so the detector does not wait on it.
- **The blast-radius sweep** across the other absence-asserting consumers of this source.
- **The AP-021 detector gap** described above. A bounded widening measures 30 candidate hits
  across unrelated subsystems, most of them false positives in test files; the offending message
  is fixed here and the detector work is tracked on its own.

  **Closed 2026-08-19 (#7578 + #7318).** All three filters were widened or narrowed together,
  which the three-row table above is what made obvious: `OPERATOR_LINE` gained the
  variable-assignment and continuation-line carriers, `CLAIM` gained a static-prose dash
  appendix, and `MEASURED` no longer exonerates an appendix-named cause on an inferred token —
  only on an explicit `MEASURED-BY:`. Both offending lines are now reported, verified against
  the pre-fix tree.

  Two notes for the record, because the follow-up issue restated this table lossily and the
  restatement was costly. First, **#7578's title carried only the `OPERATOR_LINE` row and its
  body only the `CLAIM` row**; neither carried `MEASURED`. The fix it prescribed — widen
  `CLAIM`, reuse the other filters — is measured **inert** against both lines, and so is
  widening `OPERATOR_LINE` and `CLAIM` together. Only changing all three works. This table had
  it right; the issue derived from it did not.

  Second, the "30 candidate hits" figure was measured with `OPERATOR_LINE` and `MEASURED`
  unchanged, so it priced one factor of three. The delivered widening measures 12, of which 11
  were triaged to `MEASURED-BY:` and the `.highwater` stayed at `1` rather than absorbing them.
- **`vendor-quota-watch` (#5134, deferred from #5103).** This ADR **supersedes its mechanism
  and leaves it open with a re-scoped body.** Guard 1 cannot substitute for it: it reads the warehouse, which is dark at
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
  — predicted this recurrence on 2026-06-10. Its 5-Why #5 action item is **#5103** (still
  open); **#5134** is a deferred increment of #5103, not the action item itself — an earlier
  revision of this ADR and of the postmortem addendum misattributed it. Both are open and
  neither was built.
- ADR-166 (AP-021, diagnostic honesty) — the principle the alarm's message violated.
- ADR-170 (AP-022, errexit capture) — the pattern the new workflow step follows.
- ADR-184 — the registry container-log shipper. **An earlier revision of this ADR exonerated
  it ("absent from the top-10 producers and its 5,000/day cap held"). That is FALSE on both
  grounds and is retracted.** The exoneration came from a producer table grouped by
  container/syslog identifier, which structurally cannot see a direct host POST — the shipper
  fell into an `other/unattributed` bucket and its missing *label* was read as an absent
  *producer*. Decomposing that bucket over the clean 24h window:

  | producer | rows/24h |
  |---|---|
  | `soleur-web-platform` container | ~101,000 |
  | host metrics | 22,464 |
  | **`SOLEUR_ZOT_LOG` (this shipper)** | **5,028** |
  | `SOLEUR_ZOT_LOG_DROPPED` | 287 |

  It is roughly the 4th-largest producer at **5,315 rows/day, over its own declared 5,000/day
  cap**. The reframing in this ADR is right about the *darkness* — the registry channel is the
  consumer that noticed, not the cause — and was wrong about the *volume*.
