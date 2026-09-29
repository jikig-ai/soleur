---
title: "Use the exact head SHA for GitHub check-run queries"
date: 2026-09-29
category: workflow-issues
---

# Learning: use the exact head SHA for GitHub check-run queries

## Symptom

A read-only `gh api .../commits/<sha>/check-runs` query returned HTTP 422 because
the command used a guessed, malformed abbreviation instead of the commit's full
SHA.

## Resolution

Read the exact head with `gh pr view <number> --json headRefOid` and pass that
value unchanged to the REST endpoint. Re-run the query after correcting the
input; do not interpret the failed request as a CI result.

