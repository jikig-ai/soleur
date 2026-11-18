---
title: "Verify container metadata and connection paths explicitly"
date: 2026-11-18
category: workflow-issues
tags: [docker, inspection, verification]
related: []
---

# Learning: verify container metadata and connection paths explicitly

## Problem

An image inspection template accessed `.Config.User` directly, but the pinned
image omits that key and Docker's formatter exited with a template error.

The first migration replay then used TCP in its synthetic database URL even
though `pg_isready` had only confirmed the container's Unix socket. The local
runner refused the connection before applying the baseline migration. The
second replay reached PostgreSQL during initialization, before its server was
stable; migration 001 saw the init server shutting down. A later patch also
missed because its context did not match the file's actual wording.

Once the healthcheck stabilized, the pinned PostgreSQL image still lacked the
Supabase Storage schema required by migration 019. The container ran migrations
001–018, then the exact runner stopped at 019 and removed its disposable
database. The local image cache contains no other standard Supabase service
images, and the Supabase CLI is not installed.

## Solution

Read the inspection JSON and access optional fields with a fallback, while
printing only the specific metadata needed for the check. The retry confirmed
the image has no configured user, the expected entrypoint and command, and the
previously observed image digest. For local database fixtures, make the psql
wrapper use the verified transport explicitly; socket readiness does not prove
TCP is listening. For this image, wait for its configured TCP healthcheck before
running migrations. Read the exact target text before composing patch context.
All failed attempts removed their owned containers automatically. A
PostgreSQL image without Storage cannot establish a full Supabase migration
baseline; do not call a partial replay schema equivalence.

## Key Insight

Image metadata fields and network listeners are not guaranteed; inspect only
what is needed, then wait for the configured healthcheck and verify the exact
transport before running migrations. Match the local database fixture's
platform services to those the migration set requires.
