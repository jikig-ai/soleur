---
title: Mint the Cloudflare Origin CA certificate for app.soleur.ai
category: operations
tags: [tls, cloudflare, origin-ca, doppler]
date: 2026-11-06
---

# Mint the Cloudflare Origin CA certificate (ADR-321, #10479)

Workflow `.github/workflows/mint-origin-ca-cert.yml`, body `scripts/mint-origin-ca-cert.sh`. It writes `ORIGIN_TLS_KEY_B64` and
`ORIGIN_TLS_CERT_B64` to Doppler `soleur/prd`. It restarts nothing and revokes nothing. Every command below is run by the owner;
no agent dispatches it without a fresh in-session go that names the command.

## Preconditions

- The listener release (slice 1, #12181) is deployed on both web hosts. Publishing the secret earlier is harmless but proves nothing.
- `CF_API_TOKEN_ORIGIN_CA` (Zone / SSL and Certificates / Edit, zone `soleur.ai`) and `CF_ZONE_ID` are in `soleur/prd_terraform`.

## 1. Rehearse (read-only)

```bash
gh workflow run mint-origin-ca-cert.yml --ref main -f mode=plan
```

Read the run log for `mint-origin-ca` lines. A healthy plan on an empty `prd` ends with `verdict=plan_ok nothing_created=true`.
`existing state=` is one of `absent`, `half`, `unusable`, `expired`, `near_expiry` (at most 90 days), `valid`. A `valid` pair makes the
plan fail with `already_minted_not_expiring`, which is the answer to "do I need to mint?": no.

## 2. Mint

```bash
gh workflow run mint-origin-ca-cert.yml --ref main -f mode=apply -f confirm=MINT-ORIGIN-CA-$(date -u +%F)
```

The `mint` job waits for the `web-platform-infra-apply` reviewer approval. Success ends with `verdict=minted cert_id=... serial=...
not_after=... restart_required=true`. The containers read the value at their next start (the web-platform release redeploy).

## 3. Deliberate rotation (a still-valid certificate)

```bash
gh workflow run mint-origin-ca-cert.yml --ref main -f mode=apply -f replace=true -f confirm=MINT-ORIGIN-CA-REPLACE-$(date -u +%F)
```

The old certificate is not revoked: a running container may still serve it until restarted. Revoke it afterwards by serial
(`DELETE /client/v4/certificates/<id>` with the same token) only once both hosts run the new one.

## Verdicts

| Verdict | Meaning | State of `prd` |
|---|---|---|
| `already_minted_not_expiring` | A valid pair with more than 90 days left exists | untouched |
| `cf_list_failed` | Token invalid, expired or missing Zone / SSL and Certificates | untouched |
| `cf_create_failed` | Cloudflare refused the create (a 403 means the token lacks Edit) | untouched |
| `cert_*` (`wrong_host`, `key_mismatch`, `short_validity`, `is_ca`, `unparseable`) | The issued certificate failed a check; its `cert_id` exists at Cloudflare and is unused | untouched |
| `doppler_write_failed`, `readback_mismatch` | A write or the read-back failed; `prd` was restored to its previous state | restored |
| `*_unrestored` | The restore could not be confirmed: read `ORIGIN_TLS_*` names in `soleur/prd` before anything else | unknown |
| `guard_stale` | The guard passed more than an hour before the apply step ran | untouched |

If Cloudflare issued a certificate that was never stored, it is harmless (the key was shredded) and can be revoked by its `cert_id`.
