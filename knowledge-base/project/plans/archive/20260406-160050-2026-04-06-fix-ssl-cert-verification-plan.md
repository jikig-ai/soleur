# Fix: SSL Certificate Verification Failure in Project Setup

## Problem

Project setup fails with:

```
Git clone failed: server certificate verification failed. CAfile: none CRLfile: none
```

## Root Cause

The `node:22-slim` Docker base image does NOT include the `ca-certificates` package.
Git's HTTPS transport (via libcurl/GnuTLS) requires the system CA bundle at
`/etc/ssl/certs/ca-certificates.crt` to verify server certificates. Without it,
all HTTPS git operations fail.

Verified: `docker run --rm node:22-slim dpkg -l ca-certificates` shows status `un` (not installed).

## Fix

Add `ca-certificates` to the `apt-get install` line in the Dockerfile runner stage (line 36-38).

### Files to Change

| File | Change |
|------|--------|
| `apps/web-platform/Dockerfile` | Add `ca-certificates` to `apt-get install` |

### Test Scenarios

- Docker build succeeds with the added package
- `git clone https://github.com/...` works inside the built container (CA bundle exists)

## Risk Assessment

- **Blast radius**: Docker image only, production deploy required
- **Reversibility**: Trivial — revert one line
- **Package size impact**: ~400KB (CA certificates bundle)
