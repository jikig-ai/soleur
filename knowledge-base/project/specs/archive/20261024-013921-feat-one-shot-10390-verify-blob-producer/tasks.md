# Tasks — feat-one-shot-10390-verify-blob-producer

Plan: `knowledge-base/project/plans/2026-10-23-fix-inngest-bundle-producer-loadjson-plan.md`
Issue: #10390 (epic, defect 3 — Phase-1 producer fix)

## Phase 0 — verbatim-error diagnostic (diagnose workflow extension)

- [x] 0.1 Extend `.github/workflows/diagnose-inngest-verify.yml` `repro` job:
  - 0.1.1 Extended jq field dump on the extracted `.sigstore.json`: top-level keys,
    `verificationMaterial.tlogEntries[0] | keys`, `kindVersion.version`,
    `.inclusionProof.checkpoint` presence + `.envelope | length`, `.canonicalizedBody` presence +
    first-200-chars decode (v1 `{kind…}` vs v2 `{apiVersion,spec…}` discriminator),
    `timestampVerificationData` shape.
  - 0.1.2 `actions/setup-go` + ~25-line Go probe (`go mod init`, `go get
    github.com/sigstore/sigstore-go@v1.2.0`, `LoadJSONFromPath` → print `err` verbatim or
    `LOAD_OK`). Pinned version must match the cosign v3.1.1 image's go.mod.
- [x] 0.2 Update `plugins/soleur/test/diagnose-inngest-verify-workflow.test.sh` — S-rows asserting
  the new steps exist (name + content greps on parsed YAML) and the probe pins `sigstore-go@v1.2.0`.
- [x] 0.3 Dispatch `diagnose-inngest-verify.yml` (default digest `4e17987c…`); record the verbatim
  error in the plan/decision log → selects the fix arm (H1 v2-emit / H2 empty-checkpoint /
  H3 missing-field / H4 protojson-shape).

## Phase 1 — TDD failing rows (before any fix edit)

- [x] 1.1 `plugins/soleur/test/inngest-config-bundle-mirror.test.sh`: failing rows —
  sign step carries `--signing-config apps/web-platform/infra/inngest-signing-config.json`;
  a verify-before-publish step exists between sign and assemble/push and hard-fails on non-zero;
  the committed config parses as signingconfig v0.2 with Rekor v1 only and no `tsaUrls`;
  mutation battery rows (remove flag / re-add tsaUrls / delete verify step) go RED.
- [x] 1.2 `apps/web-platform/infra/inngest-config-bundle-pack.test.sh`: add a row only if the
  selected fix arm changes pack-script output — **no change required** (the mode fix lives in the
  workflow sign step; the pack script is untouched).
- [x] 1.3 `apps/web-platform/infra/inngest-host.test.sh`: floor row 5→6 (fails pre-bump).
- [x] 1.4 Commit failing tests first; capture the red output for the PR body.

## Phase 2 — producer fix

- [x] 2.1 Create `apps/web-platform/infra/inngest-signing-config.json` — signingconfig v0.2:
  Fulcio v1 + OIDC v1 + `rekorTlogUrls` = `https://rekor.sigstore.dev` majorApiVersion 1 ONLY;
  omit `tsaUrls`; selectors `ANY`; header comment documents capture date + rationale.
  (Verify schema against `cosign signing-config create --help` or the sigstore/root-signing
  `targets/signing_config.v0.2.json` shape.)
- [x] 2.2 `build-inngest-config-bundle.yml` sign step: add
  `--signing-config apps/web-platform/infra/inngest-signing-config.json` to the `cosign sign-blob`
  argv (verify the flag token on the installed cosign: `cosign sign-blob --help | grep signing-config`).
- [x] 2.3 Add verify-before-publish step between sign and `Assemble bundle tarball`:
  `verify-blob --trusted-root apps/web-platform/infra/cosign-trusted-root.json --bundle <produced>
  --certificate-identity-regexp <derived-from-GITHUB_REF-escaped> --certificate-oidc-issuer
  https://token.actions.githubusercontent.com <manifest>`; hard-fail unless `Verified OK`.
- [x] 2.4 Fallback arm only if Phase 0 names a field the config cannot fix (H2/H4): smallest
  emitter-side correction per the measured error (e.g., TLE repair via Rekor entry refetch, or
  targeted jq `del()`), still behind the verify-gate. Never: `--insecure-ignore-tlog`,
  `--insecure-ignore-sct`, `--key`, `--new-bundle-format`.
  **Taken — measured error names a NON-envelope field the config cannot fix**: probe printed
  `LOAD_OK version=v0.3` (run 40035816173) — bytes load clean; the defect is the 0600 member
  mode (EACCES in the nonroot verifier container). Correction shipped: `chmod 0644` the emitted
  bundle + the verify-gate runs the PINNED container image (the consumer's own read path), not
  the runner binary. The `--signing-config` pin is kept as emit-surface drift control.
- [x] 2.5 Run the suites: `bash plugins/soleur/test/inngest-config-bundle-mirror.test.sh`,
  `bash plugins/soleur/test/diagnose-inngest-verify-workflow.test.sh`,
  `bash apps/web-platform/infra/inngest-config-bundle-pack.test.sh`,
  `bash apps/web-platform/infra/inngest-host.test.sh` — all green.

## Phase 3 — floor bump (same diff)

- [x] 3.1 `cloud-init-inngest.yml`: `-lt 5` → `-lt 6` + update the "floor stays 5 ON PURPOSE"
  comment (secret materializes in this arc's promotion apply).
- [x] 3.2 `inngest-host.test.sh`: floor assertions 5→6 (extract + `== "5"` → `== "6"` + companion
  greps).

## Phase 4 — records

- [x] 4.1 ADR-135 defect-3 addendum: producer-side root cause (from Phase-0 measured error),
  emit-surface pin + verify-gate mechanism, the "sign-time validate ≠ on-disk load" lesson.
- [x] 4.2 Amend `knowledge-base/engineering/operations/post-mortems/2026-10-22-inngest-config-refresh-verify-blob-reject.md` — producer root-cause closure.
- [x] 4.3 Runbook `inngest-config-refresh.md`: pinned signing-config input + verify-gate contract note.
- [x] 4.4 Check `scripts/followthroughs/inngest-verify-clean-10390.sh` window/wording vs the new
  promotion; amend only if the probe's verdict needs it.

## Phase 5 — post-merge follow-through (normal dispatch gates; not part of this diff)

- [ ] 5.1 Merge; then in the SAME window: dispatch `build-inngest-config-bundle.yml -f version=4`
  (verify-gate must print `Verified OK` pre-publish).
- [ ] 5.2 Dispatch `diagnose-inngest-verify.yml` on the new digest → `LOAD_OK` + `Verified OK`.
- [ ] 5.3 Promote: `TF_VAR_inngest_config_digest=<new sha256>` via `soleur/prd_terraform` +
  `apply-web-platform-infra.yml` (doppler_secret write). No `inngest-host-replace` between merge
  and this apply (floor-6 ordering gate).
- [ ] 5.4 Off-box watch: `SOLEUR_INFRA_PULL_APPLIED version=4` within ~15 min; zero
  `detail=flag-newbundle` rows (AC8). Enrolled soak: `inngest-verify-clean-10390.sh`.
