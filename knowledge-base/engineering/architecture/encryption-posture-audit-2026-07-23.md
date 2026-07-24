# One-Time Encryption-Posture Audit — 2026-07-23

**Scope:** every persistent store and cross-component connection Soleur operates, with each
row's ACTUAL at-rest and in-transit posture and the AUTOMATED source it was determined from.
**Sources:** `git grep` / reading `*.tf` + connection code + cloud-init/bootstrap/cutover
scripts; provider public data-security documentation for the provider-managed rows. **No
dashboard eyeball** (`hr-no-dashboard-eyeball-pull-data-yourself`). **No SSH**
(`hr-no-ssh-fallback-in-runbooks`). This PR **remediates nothing** (AC25) — it installs the gate
and records reality; each non-conforming finding is its own tracked issue.

The machine-readable form is `scripts/encryption-posture-ledger.json`, enforced on every CI run
by `scripts/lint-encryption-posture.py` (Layer A) and reconciled against live state by Layer B.

## Method note — why "code" is the authoritative at-rest source for Hetzner volumes

Encryption-at-rest on a Hetzner volume is **guest-side LUKS**, not a provider attribute — there
is no `encrypted` flag on `hcloud_volume` (pinned `hetznercloud/hcloud` v1.63.0). The Hetzner API
is therefore structurally **blind** to a volume's at-rest posture. The authoritative automated
source is the `.tf` `format` attribute plus the presence/absence of the four-part LUKS apparatus
(`cryptsetup luksFormat/luksOpen` → `random_password` → `doppler_secret` → `/dev/mapper/*`
mount), joined to the volume via its `hcloud_volume_attachment` (never by name similarity — the
plaintext `hcloud_volume.workspaces` sits beside the encrypted `hcloud_volume.workspaces_luks`).

**Host-dimension limitation:** the code-sourced audit determines each resource's *declared*
posture. Whether a superseded plaintext volume is still *attached* to a live host requires a
per-host pull; those rows carry `live_verification: unavailable` and a tracking issue. Layer B is
the mechanism that closes this — and today it can only measure `workspaces_luks` (via
`luks-monitor.sh`); every other volume needs its own posture probe (follow-up scope).

## Persistent stores

| Store | Declared at | Measured at-rest posture | Source | Finding |
|---|---|---|---|---|
| `hcloud_volume.workspaces_luks` | `workspaces-luks.tf:184` | **LUKS** (mapper `workspaces`) | `workspaces-cutover.sh:2041` luksOpen + `random_password`/`doppler_secret` + `soleur-host-bootstrap.sh:564-565` gate | conforming |
| `hcloud_volume.git_data_luks` | `git-data-luks.tf:79` | **LUKS** (mapper `git-data`) | `cloud-init-git-data.yml:160,163,170` | conforming |
| `hcloud_volume.workspaces` | `server.tf:1569` | **plaintext ext4** (superseded on web-1 by `workspaces_luks`, cutover 2026-07-23 verify run 30040444418) | `format = "ext4"`, no apparatus | #6897 (remove/confirm-detach) |
| `hcloud_volume.git_data` | `git-data.tf:196` | **plaintext ext4** (rollback backstop, pending DL-2 wipe) | `format = "ext4"`, no apparatus | #6897 |
| `hcloud_volume.inngest_redis` | `inngest-host.tf:288` | **plaintext ext4** — Inngest AOF (in-flight job payloads) | `format = "ext4"`, no apparatus | **#6894 (highest sensitivity)** |
| `hcloud_volume.registry` | `zot-registry.tf:407` | **plaintext ext4** — GHCR mirror (OCI blobs + cosign sigs) | `format = "ext4"`, no apparatus | #6895 |
| `cloudflare_r2_bucket.cla_evidence` | `apps/cla-evidence/infra/bucket.tf:1` | provider-managed AES-256 (Cloudflare default) | Cloudflare data-security docs | #6896 (formalize attestation) |
| `cloudflare_r2_bucket.workspaces_luks_header` | `workspaces-luks-header.tf:40` | provider-managed AES-256 (LUKS-header escrow) | Cloudflare data-security docs | #6896 |
| R2 Terraform-state backend | `main.tf` backend block | provider-managed AES-256 (in-repo comments asserted "encrypted" with **no attestation** — now substantiated) | Cloudflare data-security docs | #6896 |
| `supabase.prd` / `supabase.inngest` | non-IaC (Doppler-managed) | provider-managed AES-256 | Supabase security docs | #6896 |
| `doppler.secrets` | vendor | provider-managed AES-256-GCM (holds the LUKS passphrases) | Doppler security docs | #6896 |
| `betterstack.logs` (source 2457081) | vendor | provider-managed at-rest | Better Stack security docs | #6896 |
| `redis.session_store` | `model.c4:218` | **at-rest posture unstated in code** — recorded as an exception, not asserted | model.c4 | #6897 |

## Cross-component connections

| Connection | Enforced at | In-transit posture | Finding |
|---|---|---|---|
| web-platform → Supabase Postgres/PostgREST | `lib/supabase/{client,server,service,tenant}.ts` | https, cert verification **on** | conforming |
| web hosts → zot registry (`10.0.1.30:5000`) | `zot-registry.tf` / `model.c4:268` | **plain HTTP by design** (`cert_verification: off`); integrity via cosign digest-pinning | #6897 (ledgered exception) |
| hosts → Better Stack (heartbeats + Logs) | `luks-monitor.sh` + heartbeat curls | https, cert verification **on** | conforming |

*In-transit cert-verification defeats (`rejectUnauthorized: false`, `sslmode=require`, `curl -k`,
etc.) are scanned repo-wide by the Semgrep rules `soleur.tls-cert-verification-defeated` +
`soleur.postgres-sslmode-unverified` (R6), not by this ledger. The known Supabase-pooler
self-signed-chain dev-only exceptions live in `byok-*.tenant-isolation.test.ts`.*

## Claim-vs-reality (R5 — the join the incident lacked)

`docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` assert LUKS /
encryption-at-rest for the workspace volume and TLS in transit. Post-cutover (2026-07-23) web-1
`/mnt/data` runs on the LUKS `workspaces_luks` mapper, so `privacy-policy.md:519` is now
**substantiated** — the ledger row `hcloud_volume.workspaces_luks` carries
`disclosed_as: docs/legal/privacy-policy.md:519` and Layer A confirms the cited store is LUKS. A
full human legal-copy reconciliation against every measured posture is a separate
`/soleur:legal-audit` run (#6897).

## Findings summary

Parent claim-unlock gate: **#6893**. Children: **#6894** (inngest_redis, P2), **#6895**
(registry, P3), **#6896** (provider-managed attestations, P3), **#6897** (superseded plaintext
volumes + zot HTTP link + session-store posture + legal reconcile, P3). All `Ref #6588`, never
`Closes`. The audit PR remediates none of them.
