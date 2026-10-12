# Decision challenges - feat-one-shot-9786-strip-plain-id-resolver (Ref #9786)

Persisted by plan (headless). Rendered into the PR body by ship Phase 6.

## DC1 - User-Challenge: the no-pointer arm is kept (re-pointed), not removed

- Operator direction (issue #9786): strip "the pre-cutover four-arm blkid discriminator over `$DEV`".
- Finding: that discriminator is also the only path that formats a blank volume on a host with no pointer.
  `inngest-provision-rehearsal/rehearsal.tf` renders the same template with raw scratch volumes and no
  pointer, and the live `inngest-provision-rehearsal.yml` gate requires that boot to reach `bootstrap-done`;
  `hr-fresh-host-provisioning-reachable-from-terraform-apply` requires a fresh host stay provisionable.
- Plan default: keep ARM 0/2/3/4 over the one remaining volume (`LUKS_ID`), delete ARM 1 (ext4) and the
  staging block. The operator's stated direction (full removal of the arm) is the alternative.
- 5-line frame: (1) Direction: remove the discriminator. (2) Evidence: rehearsal gate + fresh-host rule.
  (3) Default taken: re-point, not delete. (4) Cost of default: ~40 retained lines + 4 loopback arms.
  (5) To override: make the no-pointer path refuse and add a pointer to the rehearsal scratch Doppler env
  plus a pre-formatted scratch volume (rehearsal root change, out of scope today).

## DC2 - Taste: keep `inngest_expect_luks` as an inert input

Template key, variable, rehearsal line and the `expect_luks=` telemetry field stay (narrow diff, Better
Stack query stability). A tracking issue retires it at the same replace window.

## DC3 - Taste: park as a reviewed draft PR instead of closing the PR and keeping the patch on the issue

Chosen because the brief mandates a draft PR; rot risk is mitigated by the unpark checklist and the
mechanical-rebase region discipline.

## DC4 - Taste: a production-config guard on the unpointed format arm (D6), not in the issue

Plan review (architecture, Kieran, spec-flow, plus the plan's own R2 correction) showed that re-pointing
the no-pointer arm at the sole-copy volume makes `luksFormat` newly reachable on prod when the Doppler
pointer is lost and a damaged header reads blank. D6 adds one guard line (refuse to format when the
rendered Doppler config is `prd`) and `blkid -p`. Default taken: adopt. Alternative: no guard, document the
exposure (rejected: single-user-incident threshold). Side effect: no automated bring-up for a brand-new
blank prd volume (disaster-recovery procedure written when needed).

## DC5 - Taste: keep the `mode=` rename (`plaintext_canonical` -> `unpointed`)

Simplicity review would defer it to the `inngest_expect_luks` follow-up. Default taken: rename now, because
a telemetry value reading `plaintext_canonical` for a LUKS volume would be a false label shipped in the same
window; the cost is one saved-query re-key, noted in the unpark checklist.

## DC6 - Taste: park the full code diff (brief) vs ship plan-only (DHH/CTO suggestion)

DHH suggested shipping the plan and tracker now and cutting the code when a window exists. The brief
mandates a prepared, reviewed draft; kept. Mitigations: staleness rule + re-review at unpark, `parked` label.
