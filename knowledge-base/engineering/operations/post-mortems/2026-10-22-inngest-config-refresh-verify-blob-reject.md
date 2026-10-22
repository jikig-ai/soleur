# PIR — inngest config-refresh verify-blob reject (#10390 defect 3)

## Summary

The dedicated inngest host's config-refresh channel was rejecting every promoted bundle: each
~5-minute tick emitted `SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature offered=4e17987c…` and
installed nothing. The refresh channel — ADR-135's in-place redelivery path for host scripts on the
deny-all-public scheduler — was dead from the v3 bundle promotion until the fix.

## Impact

Config-refresh bundles (host scripts) could not deliver; the scheduler itself kept running on its
last-good bundle. No user-visible outage measured, but the channel exists precisely for urgent
host-script delivery — it was silently unusable.

## Root cause

`reason=signature` is emitted on ANY non-zero exit of the verify `docker run` — cryptographic
rejects, flag-parse errors, docker daemon errors, and `timeout` kills all map to one row, with the
stderr swallowed by `>/dev/null 2>&1`. The reject was honest (docker reaches the verifier image;
verify-blob itself fails), but the classification overload made it undebuggable without a host
login. Suspects refuted by measurement: trusted-root staleness (baked root is key-identical to
Sigstore's live root), identity-regexp drift (the real Fulcio cert SAN byte-matches the pinned
regexp), and offline-verify incapacity (a reconstructed v0.3 bundle verified `Verified OK` under the
verbatim `--network none` invocation). Remaining hypothesis class: bundle-load
(`sgbundle.LoadJSONFromPath` — cosign v3.1.1 gates `--trusted-root` on it) or host-state divergence.

## Resolution

- `inngest-config-refresh.sh` captures the verify stderr to a bounded on-host
  `verify.stderr` (4 KiB, 0600, last failure only; captured around `timeout` so rc=124 lands it)
  and classifies it into a `detail=` token on the VERIFY_FAIL row
  (`flag-newbundle|tlog|identity|chain|timeout|docker|other`).
- `inngest-config-drift.yml`'s `_summ_row` allowlist extended so `detail=` surfaces in summaries.
- New kept dispatch-only probe `diagnose-inngest-verify.yml` reproduces the verbatim host
  invocation in CI with stderr visible — the sanctioned no-SSH diagnostic for future rows.
- No verification-weakening flag added (AC10; a posture change would need an ADR-135 amendment).

## Timeline

- v3 bundle promoted; host replaced (run 39818534701) — VERIFY_FAIL loop begins.
- 2026-10-22 — defect found in post-merge verification; root-cause hunting blocked by swallowed
  stderr; fix shipped via immutable host replace per `hr-prod-host-config-change-immutable-redeploy`.

## Follow-ups

- Dispatch `diagnose-inngest-verify.yml` post-merge to capture the real bundle's stderr and name
  the Phase-1 fix branch (tracked on epic #10390).
- Soak: `scripts/followthroughs/inngest-verify-clean-10390.sh` (directive on the epic; ≥24h clean).
- Deferred P3 panel items already tracked in #10751.
