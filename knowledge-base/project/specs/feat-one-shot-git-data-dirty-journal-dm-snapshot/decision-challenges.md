# Decision challenges — feat-one-shot-git-data-dirty-journal-dm-snapshot

Recorded headless by `soleur:plan` (plan-review + Step 4.5 advisor consult), 2026-09-24. `ship`
renders these into the PR body and files an `action-required` issue.

## DC-1 — Scope addition: an adopted-LUKS replace arm in the rung-2 rehearsal (P8)

- **Your direction:** make the rung-2 rehearsal reproduce a dirty journal (mount the plaintext volume
  rw, write, hard power-off without unmounting, then boot the payload against it).
- **What the plan adds:** after that boot and the existing reboot arm, the rehearsal also runs a
  `terraform apply -replace` of the rehearsal host. The second boot adopts a LUKS volume that its
  predecessor formatted and abandoned while mounted, against the still-dirty plaintext volume.
- **Why:** the failed 2026-09-24 host already formatted the production LUKS volume. So G3 will be the
  first first-boot ever to take the cloud-init LUKS adopt arm, and no rehearsal has booted that arm.
  The second boot also reports `plaintext_journal=dirty` again, which proves on the real image that
  the first boot did not write the plaintext volume. CTO, CPO and code-simplicity all endorsed it.
- **Cost:** one more paid boot per rehearsal (cents, about 10–15 minutes), and more workflow
  wiring (a separate teardown job, the replace-arm capture, and an upload condition).
- **To cut it:** drop Phase 3's replace arm, `RUNG2_REPLACE_BOOT`, T13/T14 and P8. The dirty-journal
  proof (P6) stands without it, and G3 then boots the adopt arm unrehearsed.
