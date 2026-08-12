---
title: Registry user_data headroom policy is 8,000 B, single-sourced from the TS budget constant
status: accepted
date: 2026-08-12
issue: 7440
supersedes_claim: "registry-userdata-budget.test.sh: headroom >= 20000 B floor"
---

# ADR-185 — Registry `user_data` headroom policy is 8,000 B, single-sourced

## Context

`hcloud_server.registry` renders its cloud-init as
`base64gzip(replace(templatefile(...), local.registry_rationale_strip, ""))`. Hetzner caps
`user_data` at **32,768 B**, and the field is `ForceNew` — a payload rejected at the API strands the
fleet's sole container-image pull path on a destroy-then-create.

Three numbers claimed to govern the same payload, and **two of them contradicted each other**:

| Site | Constraint | Implies |
|---|---|---|
| `plugins/soleur/test/cloud-init-user-data-size.test.ts` | `stored < REGISTRY_GZIP_BUDGET` (20,000) | headroom > 12,768 |
| same file, meta-assertion | `REGISTRY_GZIP_BUDGET < HETZNER_CAP - 8_000` | **preserve ≥ 8,000 B headroom** |
| `apps/web-platform/infra/registry-userdata-budget.test.sh` | `headroom >= 20000` | stored ≤ 12,768 |

The bash arm and the TS budget are the **same pair of numbers transposed**: one treats 20,000 as a
size, the other as a headroom, and they sit ~7 kB apart in stringency. Both were introduced in the
same commit (`dff874e05`, #7300). The bash suite additionally cross-checks itself against the TS
oracle's bounds — so the same file both accepted the payload (via the oracle) and rejected it (via
its own floor).

This surfaced when #7440's zot log shipper took the registry payload to 13,136 B stored: inside
every number authored *as* a policy, and 368 B (11%) outside the bash arm.

## Decision

**The `headroom >= 20000` arm was wrong, and it was a scope slip rather than a units typo.**

That literal is **AC1 of the #7299 plan** — a one-shot verification that the *measurer fix* had
landed, i.e. that the corrected reading was ~23.4 kB rather than the phantom −3,636 B the unstripped
render had produced. 20,000 was a loose round lower bound chosen to separate those two readings. It
was then transcribed verbatim into a standing regression arm, where it silently became a permanent
capacity ceiling nobody decided on — rationing every future feature on this host to 3,360 B.

Five independent lines of evidence, none from the convenience of the change that hit it:

1. **No script enforces it.** `registry-userdata-budget.sh` and its `git-data-userdata-budget.sh`
   sibling fail on exactly one condition: `stored_bytes >= cap`. The gate the operator actually runs
   before a destructive replace has no headroom floor at all.
2. **The runbook states the operational invariant as `headroom > 0`, strictly**
   (`registry-luks-recut-6929.md`).
3. **The #7299 plan's own rejected-alternatives table records "production is 71% under cap"** — a
   plan whose finding is abundance did not simultaneously intend a scarcity ration.
4. **The sibling host falsifies it empirically.** ADR-152 records git-data at 20,456 B stored /
   **12,312 B headroom**, under `GIT_DATA_BUDGET = 28_000` permitting headroom as low as 4,768 —
   same cap, same ForceNew, same hazard, and 4× less conservative. A 20,000 B headroom floor would
   red git-data on contact.
5. **The fingerprint.** The bash suite carries both TS literals: `4000` applied to `stored` (keeping
   both referent and value) and `20000` applied to `headroom` (keeping the value, losing the
   referent). Two constants travelled together; one kept its meaning.

**The policy is 8,000 B of preserved headroom**, which is the only one of the three numbers authored
as a statement about margin. The bash gate now **derives** its floor as `cap - REGISTRY_GZIP_BUDGET`
from the single owning constant, so the two gates cannot disagree again.

### What the margin is actually for

The bash gate measures with terraform's own `base64gzip` + `length()`, so it is byte-exact for the
committed template. Residual measure-time-to-apply-time divergence is bounded by render-time
variable entropy (~340 B, measured in `29c5c9667`), Go zlib build variance (9,404 vs 9,408 across
builds), and template churn between gate run and apply. **Largest divergence ever measured on this
class: 612 B.** 8,000 B is ~13× that. 20,000 B bought nothing measurable.

## Consequences

- Registry `user_data` may grow to just under 20,000 B stored, preserving ≥ 12,768 B headroom —
  itself ≥ the 8,000 B policy the TS meta-assertion pins.
- The headroom arm is deliberately **redundant** with the extracted `ts_floor < stored < ts_budget`
  cross-check. Its value is the message in the operator's unit, not an independent constraint. Both
  move when `REGISTRY_GZIP_BUDGET` moves; mutation-verified by tightening that constant to 12,000
  and observing this gate red.
- An unreadable oracle now **fails explicitly**. Previously the extraction ran *below* the arm, so
  an empty `$ts_budget` inside `$(( ))` would evaluate to 0 and demand `headroom > cap` — failing
  closed by arithmetic accident, for a reason no message named. On a suite whose entire subject is
  gates that report green having asserted nothing, that path had to be named.
- **The ratchet does not disappear.** At 13,136 B the shipper consumes 6,864 B of the budget's
  remaining room, and the shipper alone cost 3,728 compressed bytes. The next `user_data` feature on
  this host meets the same wall one level up. That constraint is real and correctly held — it simply
  was not the constraint the failing arm expressed.

## Alternatives considered

| Alternative | Verdict | Reason |
|---|---|---|
| Cut scope from the shipper to fit | **Rejected** | The candidates (non-JSON redaction backstop, four-reason drop taxonomy, exempt-cap ceiling) are all review findings from the #7444 panel. Trading correctness fixes against a threshold that was never decided is the wrong exchange. |
| Move the shipper out of `user_data` | **Rejected** | ADR-184 rejected a boot-time download on the fleet's sole image-pull path when it rejected Vector. That reasoning is untouched here, and paying a circular-dependency risk on the pull path to satisfy a mis-scoped test arm would be the worst available outcome. |
| Lower the bash floor to a new hand-picked number | **Rejected** | Inventing a fourth constant is what produced the contradiction. The floor is derived, not decided. |
| Leave the arm and compact the feature further | **Rejected** | gzip had already deduplicated the repetition — single-sourcing a replicated literal and stripping blank lines together recovered ~130 B. Closing 368 *compressed* bytes needs ~1,500+ raw bytes of novel code, and the novel code is the review fixes. |

## Status flip condition

None — this is a policy record, accepted on write. It becomes wrong if the measured
measure-time-to-apply-time divergence ever approaches 8,000 B, which would be a finding about the
render chain rather than about this number.

## References

- ADR-152 (git-data `user_data` budget, the 12,312 B operating precedent)
- ADR-184 (the zot log shipper whose growth surfaced this)
- ADR-096 (registry host is cloud-init-only; no in-place execution path)
- `#7299` / `dff874e05` — the plan whose AC1 became this arm
