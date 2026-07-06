# Phase 0 — live probe evidence (#6005)

Ran against the REAL SHA-pinned verifier container
`ghcr.io/sigstore/cosign/cosign@sha256:57c0e93a… = v3.1.1`, 2026-07-04.

## 0.1 — cosign v3.1.1 `verify` flag set (plan's prescribed flags FALSIFIED)

`docker run --rm $COSIGN_IMAGE verify --help` flag list contains **`--trusted-root`,
`--local-image`, `--certificate-identity-regexp`, `--certificate-oidc-issuer`** — and
does **NOT** contain `--new-bundle-format` or a visible `--offline`.

- `--new-bundle-format`: **does not exist** on `cosign verify` in v3.1.1 (plan assumed it).
- `--offline`: **accepted but DEPRECATED** (hidden from `--help`). Running it emits:
  `Flag --offline has been deprecated, To verify in an airgapped environment, provide a
  --bundle … and a --trusted-root file`. Removed in cosign v4.
- Critically, `verify --offline <digest>` **still performs a registry round-trip** for the
  OCI-attached `.sig` (observed it hit `https://ghcr.io/token` and return `DENIED` on a
  private/nonexistent repo). `--offline` only suppresses the **online tlog/rekor** lookup;
  it does not remove the registry fetch. `docker pull` of the image does not pull the `.sig`.

→ This falsification triggered a CTO architecture re-decision → **ADR-087 (Design B′:
`--network host` ephemeral verifier, no allowlist widening, keep pinned `--offline` +
`--trusted-root` frozen inert by the pinned SHA)**.

## 0.1b — Design C primitives confirmed (rejected by ADR-087, recorded for completeness)

`cosign save <digest> --dir` and `cosign verify --local-image --trusted-root …` both exist
(the fully-offline two-step path). Rejected: `save` still needs the credential + a registry
round-trip for the `.sig`, so it delivers no egress advantage over B′ while adding a
two-invocation temp-dir lifecycle. See ADR-087 §Considered Options.

## 0.2 — trusted_root.json generated + offline-verify mechanics proven

- Generated the public-good `trusted_root.json` via `cosign initialize` in the pinned
  container → `apps/web-platform/infra/cosign-trusted-root.json`
  (sha256 `6494e21ea73fa7ee769f85f57d5a3e6a08725eae1e38c755fc3517c9e6bc0b66`, 6787 bytes,
  mediaType `…trustedroot+json;version=0.1`; 2 tlogs / 2 CAs / 2 ctlogs / 1 TSA).
- Proved the B′ invocation shape runs the offline trust-root path with **no TUF/sigstore
  egress error**:
  `docker run --rm --network host -v <root>:…:ro $COSIGN_IMAGE verify --offline
  --trusted-root=<root> --certificate-identity-regexp=… --certificate-oidc-issuer=…
  <public-digest>` → reached the registry sig-lookup and returned `no signatures found`
  for that particular public digest (i.e. the trust-root load + offline path work; that
  digest simply has no attached sig). No `TUF`/`fulcio`/`rekor` reachability error.
- **Full PASS against the real signed PRIVATE `soleur-web-platform` digest is the
  post-credential acceptance probe** (Phase 0.2 needs the `read:packages` credential to
  pull the private `.sig`) — validated post-merge on a real signed deploy (WARN, no
  `verify_result` failure in Sentry). See plan §Acceptance Post-merge.

## 0.3 — signing identity regexp unchanged

`COSIGN_IDENTITY_REGEXP` (`ci-deploy.sh:41`) pins
`…/reusable-release.yml@(refs/heads/main|refs/tags/v…)`; unchanged since #5933 — carried
verbatim into the B′ invocation.

## 0.4 — DOPPLER_TOKEN ambient at verify time

Confirmed `DOPPLER_TOKEN` is in the ambient webhook env (`cloud-init.yml:312`
`/etc/default/webhook-deploy`) and checked at `ci-deploy.sh:613`, so the Phase-3 early
`doppler secrets get` (GHCR token + SENTRY_*) is feasible before the pull/verify.

## 0.5 — both packages private (H4)

`gh api` confirmed BOTH `soleur-web-platform` AND `soleur-inngest-bootstrap` are
`visibility: private`; the credential must cover both (fresh boot pulls inngest at
`cloud-init.yml:511`).

## 0.6 — keep-private (D0)

Operator/CPO signed off 2026-07-04: keep PRIVATE (deliberate supply-chain hardening).
Full credential subsystem in scope.
