# Decision challenges — feat-one-shot-8535-registry-plaintext-sweep

## Taste (plan-review, named panel: CTO devex) — applied, surfaced for visibility

1. **D6: emitted and operator-facing text states mechanism, not posture.** The `apply_target` dropdown, the `registry-luks-recut` `::error::` line and the runbook decision section now say "a host replace keeps the volume, so it cannot re-encrypt or empty the store". They do not say "the volume is LUKS". Current posture lives only in the encryption-posture ledger and the NFR row.
   - Why: the posture wording would be false in the refuse-arm case (`not_luks` / `fail_header`) where a recut is the remedy, and every state change would need this sweep again.
   - Default if rejected: D1's dated past-tense rewording, with the posture stated inline.
2. **D7: rename the runbook heading and add a pre-dispatch check.** `## Do NOT use registry-host-replace for this` becomes `## registry-host-replace cannot perform a recut (it is the boot-problem lever)`. The pre-dispatch check reads the newest `SOLEUR_ZOT_DISK` row; on `store_escrow=fail_passphrase|fail_header` or `luks_open_arm=not_luks`, go to the triage table.
   - Why: operators skim headings during an outage, and the old heading keeps steering them away from the correct lever.
   - Default if rejected: keep the heading and rewrite only the body.
