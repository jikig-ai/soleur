# Decision challenges — feat-one-shot-6604-wipe-plaintext-identity

Headless plan-review (2026-09-30). The operator's stated direction was kept as the default in each
case below. Each is surfaced here for `ship` to render into the PR body and file as
`action-required`.

## DC-1 (User-Challenge) — keep `label=` on the rehearsal row?

- **Operator direction:** keep `label=` on the row as observed evidence.
- **Challenge (DHH, code-simplicity):** drop the `blkid -p -s LABEL` probe and the `label=` field.
  Nothing consumes it, and reporting it keeps the dead premise visible. `plaintext_dev=` alone is the
  identity evidence.
- **Plan:** kept, per the operator.
- **Cost of keeping it:** one probe, a stub default and one field.

## DC-2 (User-Challenge) — keep the physical witness inside the dead-man fire?

- **Operator direction:** mirror the new witness inline in the fire string.
- **Challenge (DHH):** keep only the marker grep in the fire. The marker precedes any zero, and arming
  is unreachable on a cut-over host (S6).
- **Plan:** kept, per the operator. The fire's physical arm uses `dev`, which is baked at arm time, so
  it is the one witness that survives a lost state file.

## DC-3 (Taste / operator sequencing) — C15 reboot proof vs. the wipe

- **The issue:** `PLAINTEXT_DEV` is a kernel name recorded on 2026-07-23. If web-1 reboots before the
  wipe (for example the C15 proof reboot, #9179), the record can drift. The rehearsal then refuses
  with `wipe_target_not_recorded_plaintext`, and Guard 5 reads "gone". Both fail closed, but the wipe
  then needs another fix-forward.
- **The trade-off:** rebooting first proves boot-time unlock while the plaintext backstop still
  exists. Wiping first keeps the recorded identity valid.
- **Status:** the plan does not choose. The operator sequences it.
