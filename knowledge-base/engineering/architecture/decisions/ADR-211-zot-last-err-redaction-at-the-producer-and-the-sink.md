---
title: "ADR-211 — zot_last_err is redacted at the producer AND scrubbed at the sink, and the tier decides whether it is a cause at all"
status: adopting
date: 2026-09-08
tags: [registry, zot, redaction, observability, gdpr, public-egress, cloud-init, adr-166]
related_adrs: [ADR-096, ADR-166, ADR-172, ADR-184, ADR-185]
related_issues: [7500, 7444, 7440, 7272, 7530, 7055]
---

# ADR-211: `zot_last_err` is redacted at the producer AND scrubbed at the sink

- **Status:** Adopting — the SINK half (Layer 2) is in force at merge; the PRODUCER half
  (Layer 1) is inert until the next `registry-host-replace` (ADR-096: the host is
  cloud-init-only). It flips to Accepted when the follow-through at #7960 reads a redacted
  sample back out of the warehouse. **[CORRECTED at review — this shipped as `Accepted`, which
  the plan and `tasks.md` both explicitly forbade for exactly this reason. `status:` is the
  most machine-readable in-force signal in the corpus, so asserting it early is the same
  overclaim this ADR exists to remove, in the one field a reader is most likely to trust.]**
- **Date:** 2026-09-08
- **Issue:** [#7500](https://github.com/jikig-ai/soleur/issues/7500)
- **Referred from:** the CLO counsel-review gate on PR #7444
  (`knowledge-base/legal/audits/2026-08-counsel-review-7440.md` §3 / blocker B2), which correctly
  held that the CLO's own gate is discharged by accurate disclosure either way and that the
  remaining question is an architecture call.
- **Ordinal note:** re-derived across every ref, not `origin/main` alone. `origin/main` topped out
  at ADR-207 while ADR-208, ADR-209 and ADR-210 already existed on sibling branches, so
  `origin/main` alone would have collided three times. The population is
  `git log --all --diff-filter=A --name-only -- 'knowledge-base/engineering/architecture/decisions/ADR-*'`;
  cite the command, not the count, and re-derive immediately before merge.

## Context

`soleur-registry`'s `SOLEUR_ZOT_DISK` reporter (#6122/#6244) `curl`-POSTs directly to a Better
Stack Logs source with no Vector agent in the path. Its payload carries `zot_last_err`: a ≤300
character sample of zot's own log output, selected in four tiers — (1) `panic:`/`fatal error`/
signal/`runtime error`, (2) `level:error|fatal`, (3) a `cannot|failed to|unable to` sweep, and
(4) a `docker logs --tail 3` fallback.

That sample passed through the payload-integrity sanitizer only, and through **no `redact()` at
all**. On tier 4 it is routinely an `info`-level `HTTP API` row carrying the full `headers`
object. On the pinned zot image, zot self-masks `Authorization` — but it does **not** mask
`Cookie`, `X-Api-Key`, or any arbitrary header. So the header-object allowlist built for the
zot-log-shipper (`redact()`, fail-closed, `jq walk`, case-folded keys) did not protect this
sibling path, which reaches the same warehouse source.

This is **pre-existing**. The log-shipper work did not create it, and that emitter is verified
sound. It surfaced only because the Art. 30 amendment initially wrote a *host*-level assurance
("its own `redact()` is the whole boundary") that is true of the emitter and false of the host.

### A second egress, which the issue did not name and which is worse

The issue framed this as a warehouse-ingest question. It is not only that.
`scheduled-zot-restart-loop.yml` splices the raw `zot_last_err` tail into `ZOT_ALARM_CAUSE=` and
publishes it into a GitHub issue on a **public** repository. Measured on #7272 (2026-09-08): 100
comments, **36** carrying a `headers` object and **13** carrying a `clientIP`.

No credential leaked, and the reason matters more than the result: all 23 `Authorization`
occurrences render `Authorization:[******]` because zot masks that one header upstream, and all
13 `clientIP` values are the **same single address, `10.0.1.30`** — the tunnel connector, inside
our own estate. (An earlier revision of this line wrote `10.0.x.x`, which invites the reading
that a range of client hosts was observed; the precise fact is materially stronger and is what
the Art. 30 §(c) entry records.) The exposure was bounded by a **vendor default this repository
does not control** and by an ingress topology that a firewall change would alter — not by any
control we own.

## Decision

**Adopt a fourth option the issue did not enumerate, plus a tier gate, at two layers.**

1. **Producer (`zot-disk-heartbeat.sh`).** Share the shipper's `redact()` — but **not** its
   fail-closed drop semantics. Apply it **per line** of the sample and **before** the sanitizer.
   On any redaction failure, degrade the single `zot_last_err` field to `REDACTION_FAILED` and
   tag `zot_last_err_src=<tier>:redact_failed`; **still emit the row.**
2. **Tier gate, first in the chain.** When the tier is `fallback`, emit only the parsed
   `message`. Degrade **closed** — with `jq` unavailable the field becomes `none`, never the raw
   line. **The provenance label does not collapse with it:** when the gate withholds a sample
   that zot did in fact produce, the tier is tagged `fallback:suppressed`, not `none`. Without
   that distinction the alarm publishes "zot produced no log output to sample" on a public issue
   in the one path where that sentence is false — an ADR-166 unmeasured claim created by the
   change that exists to remove them. Caught at CLO review, not by the original suite.
3. **Sink (`zot-restart-loop-alarm.sh` + its workflow).** A credential-header scrub at the
   `emit_and_exit()` chokepoint and again at the workflow publication boundary.
4. **Render the tier inside `ZOT_ALARM_CAUSE`,** so a tier-4 sample is never presented as a cause.

### Why per line, and why before the sanitizer

Both halves were **measured, not reasoned about**, and both are counter-intuitive:

- Applied to the whole multi-line blob, `redact()` takes its **non-JSON denylist** branch (a blob
  is not valid JSON), and an unanticipated header (`X-Secret`) leaves **in the clear at RC=0**.
- Applied **after** the sanitizer, `tr -d '"\\'` has already destroyed the quoting, so the JSON
  **allowlist** branch can never fire and only the denylist backstop remains.

A `Cookie` fixture cannot detect either failure — `Cookie` is on the denylist, so a denylist-only
implementation passes it. This plan made exactly that error once and caught it at review; the
suite now fixtures `X-Secret`, which is on neither list.

### Why the row still ships on a redaction failure

The `SOLEUR_ZOT_DISK` row carries ~26 other fields — `pcent`, `fs_size_gb`, `zot_restarts`,
`oom_kills_5m`, `boot_id`. `redact()`'s own fail-closed contract drops the row, which is correct
for a log **shipper** whose entire payload is the log line, and wrong for a **disk-pressure
reporter** whose payload is mostly numeric telemetry. Adopting the function without adopting its
drop semantics is the whole of option 4: it answers the "Against" argument in the issue rather
than trading against it.

## Alternatives considered

| Option | Verdict | Why |
|---|---|---|
| **1. Route through `redact()` verbatim, drop semantics included** | Rejected | A row that cannot be redacted is *dropped*, and on a disk-pressure reporter that destroys the ~26 numeric fields — the signal most needed during the incident that produced the unredactable sample. |
| **2. Accept as a bounded residual** | Rejected | The bound is a vendor default (`zot` masking `Authorization`) plus an ingress topology, neither of which this repository controls. A residual whose bound is somebody else's default is not bounded. |
| **3. A narrower header-shaped scrub at the producer** | Rejected **at the producer**, adopted **at the sink** | A substring scrub is necessarily a *denylist*, so an unanticipated header name survives it. At the producer the JSON structure still exists, so an allowlist is available and is strictly better. At the sink the structure is already gone (see the scope limit below), so a denylist is the *only* thing available there — which is why option 3 is the right answer at layer 2 and the wrong one at layer 1. |
| **4 (adopted). Share `redact()` per line, discard the drop semantics** | **Adopted** | Buys the allowlist property at the producer AND keeps the disk signal. |
| **5 (adopted, additional). Tier gate suppressing tier 4** | **Adopted** | Best ratio on offer: tier 4 produced ~100% of the measured header exposure and named a cause **zero** times in 21 hours. *(That window is outside the warehouse's hot table, so the derivation is not re-runnable from here — it is cited from the plan's Research Insights rather than from a live query, and a reader should treat it as a recorded measurement, not a reproducible one.)* Suppressing it removes most of the exposure and loses nothing measurable. |

**Cost was not a decision input, and the issue's framing of it was wrong twice.** The issue cites
"ADR-185: 8,000 B headroom … 13,136 B stored". Measured at implementation: 13,692 B stored
(the 13,136 figure was stale), and ADR-185's 8,000 B is a headroom *floor*, not an allowance —
the budget is `REGISTRY_GZIP_BUDGET = 20_000`. The change measured **13,692 → 14,100 B (+408)**,
leaving 5,900 B. Note also that the plan's own estimate for this option was +64 B, so the real
cost is ~6× the estimate and still not close to binding. The dominant cost is `ForceNew`, which
every option pays identically.

### An option the plan never enumerated, surfaced at review and declined

The plan framed the producer-side sharing question as a binary — duplicate the function, or
`source` a shared file at runtime — and correctly rejected the second (a broken `source` on a
cloud-init-only host fails silently and is repairable only by a destructive replace). Review
pointed out a third option the file itself uses eleven times: this cloud-init is rendered by
`templatefile()`, so the function body could be a terraform `local` interpolated into **both**
`write_files` blocks. The rendered host still carries two independent copies, so the silent-
`source` objection does not apply, and drift becomes impossible by construction rather than
caught by a gate.

**Declined for this change, and the reasoning is recorded rather than the conclusion.** The two
design reviewers disagreed: the simplicity lens recommended the interpolation and deleting the
drift gate; the architecture lens independently read the same gate and endorsed the current
boundary, on the grounds that rejecting body byte-equality (because it would dictate dead
`[zot-log-shipper]`-tagged stderr) is a correct call. Given that split, on a boot-critical file
whose failure mode is an unbootable host repairable only by replace, the change is not worth
making inside a security fix. It is a real option and should be evaluated on its own; the drift
gate is what makes deferring it safe.

## Scope limit — what this does NOT claim

Recorded here because an overclaim is the failure this ADR exists to prevent, and because the
Art. 30 register cites it:

- The producer control covers the **`headers` object** of a **JSON** log line, **per line**, via
  an allowlist. It is not a general PII scrubber.
- It does **not** mask `clientIP`. That is deliberate and is owned by **#7530**. On the current
  topology `clientIP` is RFC1918 and not Art. 4(1) personal data.
- **The sink scrub has a SECOND limit, on the VALUE side.** Its bare-form value class stops at
  whitespace, so `Cookie: a b` masks only `a` and the residual survives. The bracketed form zot
  actually emits (`Cookie:[session=…]`) is masked whole, which is why exposure is low — but an
  undocumented limit is exactly what this section exists to prevent. Pinned by
  `scripts/zot-restart-loop-alarm-scrub.test.sh` case `G2-3c`, which asserts the residual
  **survives**, so the boundary is measured rather than discovered.
- **The sink layer is a DENYLIST for as long as the producer ships the sample quote-stripped.**
  By the time text reaches the alarm, the producer's `tr -d '"\\'` has destroyed the JSON, so
  the structural allowlist cannot be reconstructed there. **[CORRECTED — an earlier draft said
  "permanently". That overclaims: the quote strip is a payload-integrity *choice* (ADR-184 §3),
  changeable at the next replace, not a law. Recording it as permanent would foreclose an option
  this ADR never evaluated — e.g. a producer that JSON-escapes the tail instead of stripping
  quotes, which would let the sink recover the allowlist.]** An unanticipated header name **survives** the sink scrub. This is asserted
  as a measured fact by `scripts/zot-restart-loop-alarm-scrub.test.sh` (case `G2-3b`) rather than
  left for a regulator to discover. **Do not describe the sink layer with allowlist language.**
- **Delivery state:** the producer half is **inert until the next `registry-host-replace`**. The
  host is cloud-init-only (ADR-096), nothing in this change schedules a replace, and until one
  fires the sink scrub is the only control in force — on the public surface, which is the worse
  of the two egresses.

## Consequences

- **[CORRECTED at review — an earlier draft of this bullet said the two controls guard
  "disjoint egresses" and that "neither substitutes for the other at any point in time". That is
  false in one direction, and it becomes false at exactly the moment the producer lands.]** The
  two controls sit at different points on **one** path, not on two disjoint egresses — the
  sink's input *is* the producer's output. The correct framing is authoritative/subordinate
  (AP-018), not mirrored:
  - The **producer is authoritative.** It is the only control on the warehouse egress, and once
    delivered its allowlist strictly dominates the sink's denylist on this field — even the
    producer's *non-JSON* branch is broader on the value side (`[^,}]*` runs to the comma or
    brace, where the sink stops at a space; that is the `G2-3c` limit recorded above).
  - The **sink is subordinate and never coverage-bearing.** It is the sole control during the
    unbounded window before the next replace — on the worse, public, non-retractable egress —
    and a backstop against producer regression or a replace shipping a divergent template
    thereafter. The producer substitutes for the sink after delivery; the sink never substitutes
    for the producer, because the warehouse egress is upstream of it.
  This framing survives the delivery event. The earlier one silently became false at it.
- They are **not** mirrored controls at one threshold (the shape
  `2026-05-06-defense-in-depth-…` warns about). An earlier draft argued the sink also uniquely
  covers pre-fix rows inside the alarm's 3-hour window; that was **falsified** and withdrawn —
  the publishing arm is `boot_id=$NEWEST_BOOT`-scoped and a replace necessarily produces a new
  boot, so pre-fix rows are unreachable by construction the instant the producer half exists.
  Recorded rather than deleted, because a wrong recorded reason is the failure mode a decision
  record is supposed to prevent.
- **Primary re-evaluation trigger: the next `registry-host-replace`.** That is the event that
  flips Layer 1 from inert to live, the event every legal record in this change is dated
  against, and — unlike the firewall change below — the one that is going to happen. Tracked at
  #7960. **[An earlier draft named the firewall as "the strongest trigger", which ranked a
  hypothetical above a scheduled certainty.]**
- **Severity-escalation trigger:** `hcloud_firewall.registry` currently carries zero inbound
  rules; ingress is intra-`10.0.1.0/24` plus a Cloudflare tunnel. Any change admitting public
  ingress raises the severity of this decision **and** converts `clientIP` into Art. 4(1)
  personal data on a path this ADR explicitly does not redact.
- A third-party/system-output publication surface remains ungoverned in general — no gate covers
  runtime publication of third-party output to a public artifact by agent-authored automation.
  Tracked separately; markdown/`@mention` injection from an attacker-chosen `User-Agent` is a
  different threat model that redaction does not address and that no guard here covers.
