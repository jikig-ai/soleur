---
adr: ADR-007
title: Doppler Secrets Management
status: active
date: 2026-03-27
---

# ADR-007: Doppler Secrets Management

## Context

Secrets scattered across 4 surfaces (GitHub Actions, local .env, server /mnt/data/.env, Terraform). No rotation mechanism. Plaintext root credentials on disk.

## Decision

Doppler as centralized secrets manager (free tier: 10 projects, 4 environments, 50 service tokens). Runtime injection via `doppler run` — no plaintext .env files on disk. Incremental migration by surface. One bootstrap credential: DOPPLER_TOKEN as the "turtles all the way down" manual secret.

## Consequences

Single source of truth for secrets. Rotation and versioning built in. Free tier sufficient for current scale. BYOK_ENCRYPTION_KEY gets offline backup regardless (urgent, independent of migration).
