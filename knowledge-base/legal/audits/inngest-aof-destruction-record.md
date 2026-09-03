---
title: "Art. 5(2) destruction record — Inngest Redis AOF volume (hcloud_volume.inngest_redis)"
status: template
date: 2026-09-03
related: [7695, 6894, 7674]
related_adrs: [ADR-199, ADR-142, ADR-140]
brand_survival_threshold: single-user incident
---

# Art. 5(2) destruction record — Inngest Redis AOF volume

## What this file is

A **template**, not a record. It is committed EMPTY and dated, and it is completed by the operator
in the same session as the `apply_target=inngest-volume-recut` dispatch, in a follow-up commit.

Art. 5(2) makes the controller responsible for demonstrating compliance with Art. 5(1) — including
storage limitation and integrity. Destroying a volume that held in-flight job payloads (user
prompts and agent output) is an Art. 5(1) act, and the only thing that can evidence it afterwards
is a record made at the time. **The volume itself is the evidence, and the recut destroys it.**

Committing the template BEFORE the dispatch exists is deliberate. A record drafted after a
destructive act is a justification; drafted before, it is a precondition — and every field below
is a value the gate has already had to read in order to authorize the dispatch at all, so
completing it is transcription rather than reconstruction.

## Where every field comes from

All of them are read off the SINGLE `SOLEUR_INNGEST_SERVER_PROBE` row that
`tests/scripts/lib/inngest-host-dark-gate.sh` selected, plus the dispatch's own inputs. Do not
assemble the record from more than one row: the gate refuses to authorize on fields taken from two
different moments, and a record that did so would assert a state that never simultaneously existed.

Pull the row with (credentials in Doppler `soleur/prd_terraform`, no SSH):

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since 90m --grep SOLEUR_INNGEST_SERVER_PROBE --limit 500
```

## Record

| Field | Value | Source |
|---|---|---|
| **Date/time of destruction (UTC)** | _(fill: the `terraform apply` step's completion time)_ | the dispatch run's own log |
| **Dispatch run URL** | _(fill)_ | GitHub Actions run |
| **Authorizing reviewer** | _(fill: the GitHub user who approved the `inngest-cutover` environment)_ | the environment approval record — this is the SOLE authorization (DP-11 F8) |
| **Physical volume id destroyed** | _(fill)_ | `expected_inngest_volume_id` dispatch input, pinned by Guard 1 against `.change.before.id` AND by Guard 2 against the live Hetzner volume resolved by NAME (an id lookup only — the attachment property is carried by G14's `data_mount_src`, not by this read) |
| **`redis_keys` on the authorizing row** | _(fill — MUST be `0`)_ | the probe row. Any other value means the dispatch was not authorized and this record should not exist |
| **`data_bytes` on the authorizing row** | _(fill)_ | the probe row. **The audit field.** An empty keyspace on a volume holding megabytes is a state a human should have seen before it was erased — record it whatever it says |
| **`data_mount_src` on the authorizing row** | _(fill)_ | the probe row. Proves the emptiness measured was about the DEVICE destroyed, not about a Redis process whose `dir` had silently landed on the root disk |
| **`flush_latched` on the authorizing row** | _(fill: `true` or `false`)_ | the probe row. Records whether an authorized FLUSHALL had already run |
| **`boot_id` of the authorizing row** | _(fill)_ | the probe row. Ties the reading to the host that was actually destroyed-from |
| **`INNGEST_CUTOVER_FLIP` at dispatch** | _(fill: `rolled-back` or `aborted`)_ | Guard 2's synchronous Doppler re-read |
| **`INNGEST_DIAGNOSTIC_BOOT` at dispatch** | _(fill: unset or `0`)_ | Guard 2's synchronous Doppler re-read |
| **Guard 2 verdict** | `dark` | the only token that proceeds |
| **Categories of personal data destroyed** | _(fill; expected: NONE — a keyspace measured at 0 held no job payloads. If `data_bytes` was non-trivial, say what the residue was and how that was established)_ | |
| **Lawful basis for destruction** | Art. 5(1)(e) storage limitation + Art. 32 — the destroy is the step that replaces a plaintext store with an encrypted one. Recorded so the act is not left resting on operator memory. | |
| **Recoverability** | NONE. `-replace` is destroy-before-create with no snapshot and no header escrow — ADR-142 rejected R2 escrow for this store on confidentiality grounds. | |

## Completion checklist

- [ ] Every `_(fill)_` above is replaced with a measured value, not an estimate.
- [ ] `redis_keys` reads `0`. If it does not, STOP: the dispatch should have been refused and this
      record is evidence of a defect, not of a lawful destruction.
- [ ] The `boot_id` recorded matches the host that was live at the apply.
- [ ] `status:` in this file's frontmatter is changed from `template` to `complete`.
- [ ] The encryption-posture ledger row is NOT flipped to `luks` by this act alone — that waits on
      an observed boot reaching `SOLEUR_INNGEST_LUKS_STAGE stage=verify` with
      `data_mount_src=/dev/mapper/inngest-redis` (ADR-199 §Consequences).
