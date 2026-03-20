# Learning: appleboy/ssh-action negotiates ECDSA, not ED25519, on Hetzner Ubuntu servers

## Problem

After the deploy incident on 2026-03-20, the `WEB_PLATFORM_HOST_FINGERPRINT` GitHub secret needed verification. Setting the ED25519 fingerprint resulted in `ssh: host key fingerprint mismatch`. Despite the server offering ED25519 host keys and the deploy key being ED25519, the Go SSH library in `appleboy/ssh-action` negotiated ECDSA for the host key algorithm.

## Solution

Set the ECDSA fingerprint instead of ED25519:

```bash
# Retrieve all fingerprints
for type in ed25519 ecdsa rsa; do
  ssh-keyscan -t "$type" <server-ip> 2>/dev/null | ssh-keygen -lf -
done

# Set the ECDSA fingerprint (not ED25519)
gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "SHA256:<ecdsa-hash>"
```

### Server fingerprints (soleur-web-platform, see WEB_PLATFORM_HOST secret)

| Key Type | Fingerprint |
|----------|------------|
| ED25519 | `SHA256:jDbCI7ey39Cm7RpSViAofI4xKc5gTT4NfAGyAY+/j2U` |
| ECDSA | `SHA256:ARBTzhY4hCGXKwWZ2j9aOc4zZefBYgAxJncoVglvuok` (active) |
| RSA | `SHA256:rIml1djy4LCr/jQWWArJtwxh1UmnURrRYD30Y9HruiE` |

## Key Insight

The SSH host key algorithm negotiation is independent of the deploy key algorithm. Even with an ED25519 deploy key, the Go `crypto/ssh` library may negotiate ECDSA for the host key based on server/client algorithm preference ordering. The `appleboy/ssh-action` does not expose control over host key algorithm selection.

When pinning host key fingerprints for CI/CD:
1. Retrieve fingerprints for ALL key types (`ssh-keyscan -t ed25519,ecdsa,rsa`)
2. Try ED25519 first (most commonly expected)
3. If mismatch, try ECDSA (confirmed working on Hetzner Ubuntu with Go SSH)
4. Store all fingerprints in documentation for quick rotation on reprovisioning

The error `ssh: host key fingerprint mismatch` means the stored fingerprint doesn't match the *negotiated* key type — it does NOT tell you which type was negotiated, making debugging blind without trying all types.

## Additional Fix: Deploy User Setup

During verification, we discovered the `deploy` user didn't exist on the server (cloud-init only runs at provisioning). Manual setup required:
- Creating the deploy user with docker group membership
- Installing SSH authorized_keys with forced command restriction
- Uploading `ci-deploy.sh` forced command script
- Copying GHCR Docker credentials from root to deploy user

For future reprovisioning, cloud-init handles all of this automatically.

## Prevention

- Always store all three fingerprint types in documentation when pinning SSH host keys
- When `ssh: host key fingerprint mismatch` occurs, try the other key types before investigating further
- After changing cloud-init configurations, verify the changes are applied to running servers (cloud-init only runs at first boot)
- Deploy users need GHCR credentials separately from root — either copy Docker config or use `docker login`

## Session Errors

1. Ralph loop script path wrong (`skills/one-shot/scripts/` vs `scripts/`)
2. Terraform state unavailable locally — no remote backend configured for this infra
3. hcloud CLI installed but no context/token configured in environment
4. Server IP discovery required 6 approaches before finding the Hetzner token in `settings.local.json` permissions history
5. ED25519 fingerprint failed as predicted by plan — required ECDSA fallback
6. Deploy user missing from running server (cloud-init only runs at provisioning)
7. ci-deploy.sh forced command script missing from server
8. GHCR Docker credentials not configured for deploy user

## Related

- Issue #858: Verify WEB_PLATFORM_HOST_FINGERPRINT secret
- Issue #857: Deploy user migration
- PR #824: Original fingerprint pinning setup
- PR #859: Deploy user migration (cloud-init only, not applied to running server)
- appleboy/ssh-action#275: Community reports of ED25519 failing, ECDSA working
- Learning: `2026-03-20-premature-ssh-user-migration-breaks-ci-deploys.md`

## Tags
category: integration-issues
module: CI/CD release workflows
