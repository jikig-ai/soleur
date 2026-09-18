Delivery watch for **#7500 Phase B** — producer-side redaction of `zot_last_err` in `cloud-init-registry.yml`.

<!-- soleur:followthrough script=scripts/followthroughs/zot-last-err-redact-7500.sh earliest=2026-09-09T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->

## Why this is open

#7500's decision is made and recorded (ADR-211), and both control layers are implemented. But the **producer half is inert until the next `registry-host-replace`** — the registry host is cloud-init-only (ADR-096), so merging applies nothing to it, and nothing in that PR schedules a replace. Until one fires, the sink-side scrub is the only control in force.

That is a legitimate state, not a defect. This issue exists so the interval is *watched* rather than assumed, because the failure mode for an inert change is silence: it never arrives, and nothing notices.

## What the probe grades

`scripts/followthroughs/zot-last-err-redact-7500.sh`. **Delivery proof** is `err_redact_rev` — an integer revision of the redaction gate that the post-#7960 producer emits on **every** `SOLEUR_ZOT_DISK` row, in the trusted region — or, as secondary corroboration, a tier-4 `zot_last_err_src=suppressed` row. Both are read only from envelope-anchored rows, before the first ` zot_last_err=`, on the newest real boot. Boot-id drift is **not** proof (a reboot of an un-replaced host flips it) and feeds no verdict.

- **R3 · PASS (exit 0)** — delivery proven, ≥1 tier-4 row on that boot, none carrying header structure. Closes this issue.
- **R2 · FAIL (exit 1)** — delivery proven and a tier-4 row on that boot carries header structure (a header map, an address-valued `clientIP`, an unmasked credential header) or a `suppressed` row carries anything but `none`. The redaction shipped and is not holding; must not close.
- **R1 · NOT YET (exit 2)** — delivery proven, no tier-4 row on that boot yet. Also exit 2: any auth/query/envelope/decode failure.
- **R4 · CANNOT ESTABLISH (exit 3)** — the newest boot carries neither proof token, so it is not proven to run Phase B. Also exit 3: no row carries a usable `boot_id`.

It grades **delivery**, not correctness. Correctness is settled pre-merge by `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh`, which also pins the proof field on every emitted row.

## The falsification condition, stated up front

A rider is only as live as its vehicle (learning `2026-08-13-a-rider-is-only-valid-while-its-vehicle-is-still-pending`). The vehicle is the `registry-host-replace` triggered by merging PR #8272, which delivers `err_redact_rev`. **After that replace completes (verified from the apply run itself), a CANNOT ESTABLISH naming a boot that lacks `err_redact_rev` means the field did not reach the host — investigate, do not wait.** Before it completes, CANNOT ESTABLISH is the expected reading.

## Guards against a vacuous PASS

1. **Subject-must-have-run** — requires at least one tier-4 row. Tier 4 is the only tier the gate changes, so a window with none makes "no header content" trivially true.
2. **A dark channel is not a clean one** — zero rows of any kind reports `channel_dark` and exits 2, never PASS.
3. **Decode before matching** — the warehouse's `raw` is an escaped JSON string; matching the undecoded envelope silently matches nothing, which is indistinguishable from a clean result.

Ref #7500


---

**Correction (2026-09-08, pre-merge).** An earlier revision of this body said "FAIL is never
emitted", and that matched a probe whose FAIL branch was in fact unreachable: the merge-time
baseline was read from `SOLEUR_FT_BASELINE_BOOT`, which `sweep-followthroughs.sh` strips because it
runs every probe under `env -i` with only the names in the directive's `secrets=`. BASELINE was
therefore empty on every scheduled run and the delivered-and-leaking branch could never fire — a
guard that could not fail, which is the defect class this PR's own learning is about.

The baseline is now baked in as a constant (`BASELINE_AT_MERGE`), re-measured against the live host
immediately before merge: 100 of 100 `SOLEUR_ZOT_DISK` rows in a 24h window carried one boot id,
read from the trusted region. Both directions were then driven — the current host reports
TRANSIENT (rc=2), and a baseline that differs while rows still leak reports FAIL (rc=1). The
contract above now describes what the script does.

For the record, the same run measured the live leak: **51 of 100 tier-4 rows** still carry header
content in `zot_last_err`, which is the expected pre-delivery reading and is what the sink-side
scrub covers in the meantime.

---

**Amendment (2026-09-18, PR #8272).** The probe could not auto-close by construction: after the
2026-09-17 replace the host emitted 272 tier-4 rows on its new boot, 0 carrying header structure
and 0 tagged `suppressed` — very likely working, and unprovable, because `suppressed` is
sufficient but not necessary and boot drift proves a boot, not a host. The producer now emits
`err_redact_rev` on every row and the probe keys delivery on it (ADR-211, "Delivery proof").
`BASELINE_AT_MERGE` and every boot-drift branch described in the 2026-09-08 correction above were
deleted; the exit contract and falsification condition above were rewritten to match. The leak
grade is now structural rather than the bare words `headers`/`clientIP`; on 2,598 real pre-Phase-B
tier-4 rows the old and new discriminators flag the identical 1,792.
