# cosign-trusted-root.json — provenance

Pinned Sigstore **public-good** trusted root, vendored to the deploy host and mounted
into the ephemeral cosign verifier (`ci-deploy.sh` `verify_image_signature`, ADR-086)
so image-signature verification runs against a **local** trust anchor — no live
Fulcio/Rekor/TUF egress (the container egress firewall #5046/ADR-052 blocks sigstore).

`trusted_root.json` is pure JSON (no comment syntax), so provenance lives here.

| Field | Value |
|---|---|
| Capture date (UTC) | **2026-07-04** |
| sha256 | `6494e21ea73fa7ee769f85f57d5a3e6a08725eae1e38c755fc3517c9e6bc0b66` |
| bytes | 6787 |
| mediaType | `application/vnd.dev.sigstore.trustedroot+json;version=0.1` |
| Source | Sigstore public-good TUF repo (`tuf-repo-cdn.sigstore.dev`), TUF-verified |
| Capture method | `cosign initialize` in the SHA-pinned verifier container `ghcr.io/sigstore/cosign/cosign@sha256:57c0e93a… (v3.1.1)`, then copied from `~/.sigstore/root/tuf-repo-cdn.sigstore.dev/targets/trusted_root.json` |

## Integrity / TOFU note

The `sha256` above is a **trust-on-first-capture** anchor: `cosign initialize` TUF-verifies
the root at capture time; this record + the CI capture-age gate guard against silent
substitution afterward. Pinning a local root **disables TUF revocation propagation** — a
compromised-then-rotated Sigstore key stays trusted here until a human re-captures. That is
the deliberate trade-off of an air-gapped root (security-sentinel HIGH #2, ADR-086).

## Staleness

Sigstore's `trusted_root.json` has **no root-level expiry** — current CA/tlog/ctlog/tsa key
material is open-ended; the only `validFor.end` timestamps in the file are 2022 (retired
keys), always in the past by design. So "parse expiry, fail within N days" does **not** map
onto this structure. The actionable staleness signal is the **capture age**: when Sigstore
rotates to new key material, a stale pinned root will not contain it and new signatures
fail to verify. `apps/web-platform/infra/cosign-trusted-root-staleness.test.sh` fails CI once
this capture date exceeds the re-capture threshold, forcing a periodic re-capture +
re-verify against a live signed image **before** the WARN→ENFORCE flip.

## Rotation recipe

```sh
# On a network-connected machine, re-capture the current public-good root:
d=$(mktemp -d)
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/out -v "$d":/out \
  ghcr.io/sigstore/cosign/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870 initialize
cp "$d/.sigstore/root/tuf-repo-cdn.sigstore.dev/targets/trusted_root.json" \
  apps/web-platform/infra/cosign-trusted-root.json
# Then update the Capture date + sha256 above, and re-verify a live signed digest offline.
```
