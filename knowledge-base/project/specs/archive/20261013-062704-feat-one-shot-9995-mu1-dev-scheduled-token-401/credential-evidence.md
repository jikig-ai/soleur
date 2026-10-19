# Credential evidence — #9995 MU1 AC-2 dev_scheduled

Values are never recorded here — only shapes: byte counts, sha256[:8]
fingerprints of the env-form value (trailing-newline-free, matching CI's
`pemFingerprint`), numeric ids, and verdicts.

## Current (broken) state — measured 2026-10-11

- `soleur/dev_scheduled` `GITHUB_APP_ID`: `3261325`
- `soleur/dev_scheduled` `GITHUB_APP_PRIVATE_KEY` fp (env form): `8246898e`
  — identical bytes to the `dev` config's copy (dead key, unregistered on
  App 3261325; the `dev` copy is left unchanged per plan Cut List).
- RED drill: `doppler run -p soleur -c dev_scheduled -- bash
  scripts/probe-github-app-mint.sh` →
  `::error::GITHUB_APP_* cannot mint a valid JWT for app 3261325
  (status=401 curl_rc=0 fp=8246898e)`, exit 1. Matches the CI
  pemFingerprint exactly — the probe reads exactly what the test reads.

## dev_scheduled shape audit — measured 2026-10-11

```
AUDIT_SUMMARY checked=60 ok=30 fail=0 unclassified=30
```

- `GITHUB_APP_PRIVATE_KEY` → `pem` → `ok`: parseable PKCS#1; the failure is
  *liveness* (key not registered on the App), which is the probe's layer.
- `VAPID_PRIVATE_KEY` initially flagged `FAIL-pem` — false positive:
  43-byte base64url blob, the correct VAPID shape. The `pem` class now
  accepts PEM-parse OR alphabet-clean bare key blob (a `*PRIVATE_KEY` name
  does not promise PEM wrapping).
- Zero non-GITHUB_APP FAILs → no follow-up issues filed.

## Fixture App (deferred to #10058 — pending founder clicks G1–G3)

- Manifest: `apps/web-platform/infra/github-ci-fixture-app-manifest.json`
  — name "Soleur CI Fixture", slug `soleur-ci-fixture`, `public: false`,
  `contents:read` + `metadata:read`, `default_events: []`, no OAuth or
  webhook surface.
- Install target: `jikig-ai/mu1-fixture` only (repo id `1214969354`).
- App id / installation id / new-key fingerprint: **pending** — recorded
  by `bootstrap.sh` (stages `record-key`, `write-doppler`) in the
  gitignored `.env` beside it, then posted to #9995 on `verify`.
