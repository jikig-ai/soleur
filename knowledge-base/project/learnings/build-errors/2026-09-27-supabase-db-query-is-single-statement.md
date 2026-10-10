---
title: Supabase db query executes one prepared statement at a time
date: 2026-09-27
category: build-errors
module: supabase-local-validation
---

## Problem

Passing a concatenated fixture, migration, behavioral assertions, and rollback
through `supabase db query --file` failed with PostgreSQL's “cannot insert
multiple commands into a prepared statement” error. That command accepts one
query, so it cannot serve as a multi-command migration harness.

## Prevention

After verifying the project stack is loopback-bound with
`scripts/supabase-local.sh assert`, use the local `psql` client with
`ON_ERROR_STOP` for a multi-statement migration probe. Capture the local
connection string without printing it, and keep fixture setup, migration,
behavior checks, and rollback scoped to the disposable local database.
