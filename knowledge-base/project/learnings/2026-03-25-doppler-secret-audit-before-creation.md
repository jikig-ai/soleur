# Audit All Doppler Configs Before Declaring Secrets Missing

**Date:** 2026-03-25
**Context:** Scheduled tasks migration (#1094)
**Category:** operations/secrets

## Problem

When migrating secrets to a new Doppler config (`prd_scheduled`), the agent checked only `dev` and `prd` configs for existing social media tokens. It missed that the `ci` config already contained all LinkedIn and Bluesky secrets, leading to an unnecessary request for the user to manually provide values.

## Root Cause

The plan prescribed "copy from GHA secrets" without first auditing all Doppler configs. GHA secrets are write-only (values can't be read via API), so when `dev` and `prd` didn't have the values, the agent declared them "missing" without checking the remaining configs (`ci`, `dev_personal`, `prd_terraform`).

## Fix

Before creating or populating a new Doppler config, always run a full audit:

```bash
# Audit all configs for a specific secret
for config in $(doppler configs --project soleur --json 2>/dev/null | jq -r '.[].name'); do
  echo "=== $config ==="
  doppler secrets --project soleur --config "$config" --only-names 2>&1 | grep -iE "$SEARCH_PATTERN" || echo "(none)"
done
```

## Broader Lesson

When a plan says "copy secrets from source A", always check ALL available sources first (Doppler configs, .env files, other secret managers) before concluding a secret is unavailable. GHA secrets should be the last resort since they're write-only.

This applies to any secret migration task — the audit step should be a standard first step in the `soleur:schedule` skill or any plan involving secret provisioning.
