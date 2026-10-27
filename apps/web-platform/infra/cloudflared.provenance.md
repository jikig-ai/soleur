# cloudflared — CI pin provenance

Analysis of record for the `CLOUDFLARED_VERSION` / `CLOUDFLARED_SHA256` pin
replicated across `.github/` (10 sites in 9 workflows: 5 env-form pairs + 5
call-site literals; canonical = `apply-web-platform-infra.yml`'s env pair, every
other site pinned equal by the terraform-target-parity census). Read by
`cloudflared-pin-staleness.test.sh` (CI gate) and by the `Detect cloudflared pin
staleness` poll step in `.github/workflows/rule-audit.yml` (detection, 1st +
15th). Mirrors the shape of `inngest-cli.provenance.md` so the sidecars share
one parseable format.

**The pin is the trust store.** Cloudflare's 2026-10-20 advisory disclosed that
the private keys of eight eMudhra (emSign) intermediate CA certificates are
compromised; cloudflared `>= 2026.10.2` removes them from the trusted set. Every
CI bridge run downloads the pinned `cloudflared-linux-amd64` release binary and
sha256-verifies it before opening the tunnel — a stale pin re-ships the
vulnerable client to the management plane. Treat every row below as
load-bearing.

| Field | Value |
|---|---|
| Pinned version | **2026.10.4** |
| Upstream release date | 2026-10-26T11:19:58Z |
| Capture date (UTC) | **2026-10-27** |
| Superseded | 2026.5.0 — bumped under the 2026-10-20 eMudhra intermediate-CA compromise advisory; advisory floor is 2026.10.2 (2026.10.3 for non-Homebrew macOS) |

## Current pin

Release tag: **2026.10.4** (bare semver — cloudflared tags carry no `v` prefix).

| Asset | sha256 |
|---|---|
| cloudflared-linux-amd64 | `ae5e8add7884b0531d66bbca4570d1de491ff6da51e4ebe7eb160cdf241d9e42` |
| cloudflared-linux-amd64.deb | `3d73cd9f085de5a947fce8a72d0acc34a6a18cb23f369549b1cd0efc51121e98` |

Each row was re-verified at bump time by downloading the real release asset and
re-hashing it (`curl -sSfL <url> | sha256sum`), never pasted from docs or
release notes — per the composite-action headers and the 2026-03-21
server-provisioning learning (Session Error #4). The bare binary row is the
artifact the two `cf-tunnel-*-bridge` composites install; the `.deb` row is the
artifact the web-host cloud-init installs:

`https://github.com/cloudflare/cloudflared/releases/download/2026.10.4/cloudflared-linux-amd64`
`https://github.com/cloudflare/cloudflared/releases/download/2026.10.4/cloudflared-linux-amd64.deb`

## Previous known-good pin

**This is the rollback target.** The bump erases the superseded checksum from
every `.github/` pin site, so without this section it survives only in git
history — a git-archaeology exercise under incident pressure. Asserted by the
staleness gate's previous-known-good check; rotate it on every bump.

| Asset | sha256 | Superseded |
|---|---|---|
| cloudflared-linux-amd64 | `0095e46fdc88855d801c4d304cb1f5dd4bd656116c47ab94c2ad0ae7cda1c7ec` (2026.5.0) | 2026-10-27 |

Recovery: a rollback is a coherent revert of every `.github/` pin site to the
above pair plus this sidecar (previous==current reds the gate, deliberately —
rotate this section to the pin being rolled back from). **Check the advisory
floor before rolling back:** 2026.5.0 predates the eMudhra fix and is
non-compliant; a rollback below 2026.10.2 re-opens the compromise. The version
floor itself is enforced by `scripts/cloudflared-compliance-probe.sh` and the
census monitor's `client_version` classifier, not by this gate — so a coherent
rollback to a post-floor pin stays sanctioned.

## Drift threshold (the poll's trip point — recorded here so the two cannot diverge)

The `rule-audit.yml` poll (`Detect cloudflared pin staleness`) files the
`cloudflared-pin-drift` issue when the pinned version is **`>= 5` stable
releases behind `releases/latest` OR the pinned release's upstream date is
`>= 45` days old** — the same thresholds the inngest pin poll carries. The
offline `MAX_AGE_DAYS=60` in `cloudflared-pin-staleness.test.sh` is the backstop
for the poll's OWN failure — the two mechanisms are different failures, not
redundancy.

## Version-scoped claim register

The staleness gate's claim check enforces that `e.g. <version>` claims in the
two composite actions name the pinned version. **The claim phrasing contract is
`e.g. X.Y.Z`** inside the `cloudflared-version` input description — write it in
the canonical form when re-stamping. The REQUIRED claim locations (each must
carry >= 1 claim) are `.github/actions/cf-tunnel-ssh-bridge/action.yml` and
`.github/actions/cf-tunnel-registry-bridge/action.yml`.

| Claim | Location | Status |
|---|---|---|
| `cloudflared-version` input example names the pinned release | `.github/actions/cf-tunnel-ssh-bridge/action.yml` (`e.g. 2026.10.4`) | Re-stamped at the 2026.10.4 bump |
| `cloudflared-version` input example names the pinned release | `.github/actions/cf-tunnel-registry-bridge/action.yml` (`e.g. 2026.10.4`) | Re-stamped at the 2026.10.4 bump |

## Refresh recipe (capture date aged out, pin unchanged)

Use when the age gate reddens but upstream has **not** moved: re-confirm the two
release assets still resolve upstream (`curl -fsSI` both URLs above), then
re-stamp `Capture date (UTC)`.

**Do not re-stamp the date to clear a red gate without doing the work.** The
date is an attestation that the analysis above is current; typing today's date
makes the backstop permanently green while the analysis rots. If upstream HAS
moved, use the bump procedure below instead.

## Bump procedure

1. **Rotate `## Previous known-good pin`** to the pin you are about to replace,
   with today's date. Do this FIRST.
2. **Resolve the target:** `gh api repos/cloudflare/cloudflared/releases/latest`
   → tag (bare semver, no `v` prefix). Confirm the tag is `>=` the advisory
   floor — a bump below floor is a compliance regression, not a rollback.
3. **Recompute both checksums against the real release assets** —
   `curl -sSfL` the `cloudflared-linux-amd64` binary and the
   `cloudflared-linux-amd64.deb` at the target tag and `sha256sum` each. Never
   paste a checksum from docs, release notes, or prior output.
4. **Update every `.github/` pin site together** — the census
   (`terraform-target-parity.test.ts`, Guard 1) discovers them; do not restate
   the file list here. Both `e.g.` claim comments in the two composite actions
   move with the bump (claim register above).
5. **Re-stamp `Capture date (UTC)` + the `Pinned version` header row**, then run
   `bash apps/web-platform/infra/cloudflared-pin-staleness.test.sh` — it must
   exit 0 — and `bash scripts/cloudflared-compliance-probe.sh` — it must print
   `PINS_OK`.

Agent entry point:

```
/soleur:one-shot "refresh the cloudflared pin provenance sidecar per apps/web-platform/infra/cloudflared.provenance.md section 'Bump procedure'"
```
