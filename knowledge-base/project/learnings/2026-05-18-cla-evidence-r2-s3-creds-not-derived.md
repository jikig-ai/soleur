# Cloudflare R2 S3-compat credentials are NOT derivable from a generic CF API token

**Date:** 2026-05-18
**Surfaces:** `apps/cla-evidence/infra/bootstrap.sh`, `apps/cla-evidence/scripts/r2-conditional-put.sh`, `.github/workflows/cla-evidence.yml`
**Discovered via:** PR #3965 (response-body capture) revealed `<Code>InvalidArgument</Code> <Message>Credential access key has length 53, should be 32</Message>` on every `pull_request_target` run since the 2026-05-16 bootstrap. After pushing a token-id + sha256(token.value) pair (matching the assumed derivation in `bootstrap.sh`), the error progressed to `<Code>SignatureDoesNotMatch</Code>` — proving the derivation itself is wrong.

## The wrong assumption (deleted from `bootstrap.sh`)

```bash
# DO NOT REINTRODUCE — this derivation does not match what R2 expects.
R2_ACCESS_KEY="$OBJECT_WRITE_TOKEN_ID"                                      # 32-char hex
R2_SECRET=$(printf '%s' "$OBJECT_WRITE_TOKEN_VALUE" | openssl dgst -sha256 -hex | awk '{print $NF}')  # 64-char hex
```

The 32-char access-key-id is accepted (gets past `InvalidArgument`), but the secret derivation fails SigV4 with `SignatureDoesNotMatch`. Cloudflare's R2 S3 surface does NOT compute `sha256(token.value)` as the secret. The `cloudflare_api_token` resource (Workers R2 Storage Bucket Item Write permission group) is a **Bearer-auth token**, suitable for `Authorization: Bearer ...` calls to the CF management API (e.g., Lock Rules PUT). It cannot be reused as a SigV4 HMAC pair.

## The actual contract

R2 S3-compat credentials are issued **only** when you create an **R2 API Token** — a distinct resource type from a generic CF API Token. The R2 API Token creation flow returns a 32-char `accessKeyId` + 64-char `secretAccessKey` directly, shown ONCE on creation, and these are NOT derivable from any field of any other CF resource.

**Dashboard path (load-bearing operator step):**
> Storage & databases → R2 → Manage API Tokens → Create Account API token
> Permission: Object Read & Write
> Buckets: Apply to specific buckets only → `soleur-cla-evidence`

The Terraform `cloudflare_api_token` resource in `apps/cla-evidence/infra/iam.tf` is still load-bearing for the CF Lock Rules + GDPR-override REST calls (Bearer auth, not SigV4) — it just cannot be reused as the S3 secret. Do not remove that resource.

## Workflow contract now enforced

1. `bootstrap.sh` requires `R2_S3_ACCESS_KEY_ID` + `R2_S3_SECRET_ACCESS_KEY` as env input (length-asserted 32/64).
2. Before pushing to Doppler, `bootstrap.sh` runs a probe PUT against the bucket. If the probe fails with anything other than 200/201/412, the script aborts and refuses to write Doppler. This catches typos and wrong-token-type before the next workflow run.
3. `r2-conditional-put.sh` (the shared upload primitive used by `upload-evidence.sh` + `upload-bypass.sh`) has a credential-shape preflight that fast-fails with an operator-actionable error pointing at `bootstrap.sh` if Doppler ever drifts.
4. The R2 response body is captured and surfaced in `::error::` annotations on 4xx/5xx so the actual S3 ErrorCode is always visible.

## What to do if creds drift in the future

```bash
# Mint a 1-hour CF admin token at https://dash.cloudflare.com/profile/api-tokens
# (Account → Cloudflare R2 → Edit + User → API Tokens → Edit), then:
# Create a fresh R2 S3 token via dashboard (see path above), then:
CF_ADMIN_TOKEN_BOOTSTRAP=<paste> \
R2_S3_ACCESS_KEY_ID=<32-char from dashboard> \
R2_S3_SECRET_ACCESS_KEY=<64-char from dashboard> \
  bash apps/cla-evidence/infra/bootstrap.sh
```

## Why this was not caught at bootstrap time

The original `bootstrap.sh` length-asserted the derived `R2_ACCESS_KEY` (32 chars) and `R2_SECRET` (64 chars) — both passed. There was no live-probe step, so the wrong-shape secret only surfaced when the first workflow tried a real `PUT` against R2. The R2 error body was discarded (`curl -o /dev/null`), so the failure annotation read `(config bug; stale token or missing perms)` — a generic message that did not point at the real cause. Three layers of safety nets are now in place (preflight in the upload script, probe-PUT in bootstrap, captured response body in error annotations) so the same regression cannot reoccur silently.
