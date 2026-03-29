---
module: System
date: 2026-03-29
problem_type: documentation_gap
component: documentation
symptoms:
  - "doppler run one-liner examples use bare $DATABASE_URL"
  - "$DATABASE_URL expanded by outer shell before Doppler injects it"
  - "Commands silently connect to wrong database or fail with empty string"
root_cause: config_error
resolution_type: documentation_update
severity: medium
tags: [doppler, shell-expansion, documentation, psql, runbook]
---

# Learning: doppler run one-liner variable expansion in documentation

## Problem

When writing runbook documentation containing `doppler run` one-liners like:

```bash
doppler run -c prd -- psql "$DATABASE_URL" -c "SELECT ..."
```

The `$DATABASE_URL` is expanded by the **outer shell** before `doppler run`
executes. Since `DATABASE_URL` is injected by Doppler into the child process
environment, the outer shell sees it as empty (or whatever the user's local
env has), causing psql to connect to the wrong database or fail silently.

## Solution

Wrap the inner command in `bash -c '...'` with single quotes so Doppler's
environment injection reaches the variable:

```bash
doppler run -c prd -- bash -c 'psql "$DATABASE_URL" -c "SELECT ..."'
```

This ensures `$DATABASE_URL` is expanded inside the Doppler-injected
environment, not the outer shell.

## Key Insight

Any `doppler run -- <command> "$VAR"` pattern in documentation where `$VAR`
is a Doppler-injected secret must use `bash -c '...'` wrapping. The migration
runner script avoids this because it runs entirely as a child process of
`doppler run`, but one-liner examples in docs do not get this protection.

## Session Errors

1. **Wrong Doppler secret name** (`SUPABASE_URL` vs `NEXT_PUBLIC_SUPABASE_URL`) --
   Recovery: listed secrets with `doppler secrets --only-names` and found the
   correct key. Prevention: always list available secrets before assuming a key
   name; Supabase convention prefixes client-side keys with `NEXT_PUBLIC_`.

2. **doppler run variable expansion in rollback docs** -- Caught by architecture
   review agent. Recovery: wrapped all psql commands in `bash -c '...'`.
   Prevention: when writing `doppler run` one-liners in documentation, always
   use `bash -c '...'` wrapping for commands that reference injected variables.

## Tags

category: documentation-gaps
module: System
