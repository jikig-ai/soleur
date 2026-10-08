---
title: "A test replica of production logic keeps the pipe shape the carrier just dropped — a sweep of the production file never reaches it"
date: 2026-10-07
category: test-failures
module: .github/scripts/test/test-tag-filter.sh
issues: [9217]
---

# Replicas drift when only the carrier is converted

## Problem

`.github/scripts/test/test-tag-filter.sh` replicates the release workflow's tag-selection pipeline in its own `run_pipeline`
so the filter's behavior can be checked against a synthetic corpus. Wave A2 (#9587, `d58f804f78`) converted the production
step in `.github/workflows/reusable-release.yml` to `tags=$(git tag --list ... --sort=-version:refname)` followed by
`grep -m1 -E ... <<<"$tags" || [ $? -eq 1 ]`. The replica (last changed in #4087, `5408712dca`) still piped
`printf | grep | sort -V -r | { grep -m1 ... || [ $? -eq 1 ]; }`, so the suite that guards the filter kept testing a shape
production no longer has. Nothing failed: the workflow-shape rows assert tokens in the workflow (`grep -m1 -E`,
`[ $? -eq 1 ]`), which both shapes contain.

## What works

- A `-m` site cannot take the mechanical `-c` rewrite (it is output-bearing and `-m` is itself an early exit), so it goes to the
  hand queue, where the right edit is to copy the production form, not the codemod form: read the sorted list into a variable
  and run `grep -m1 -E P <<<"$tags" || [ $? -eq 1 ]`, keeping the `$? -eq 1` tolerance.
- The existing rows already see a first-line-only reader: the corpus sorts `vinngest-v1.0.0` ahead of `v3.101.5` under
  `sort -V -r`, so the bare-`v` prefix case (`ac1-plugin`) only passes if the reader skips the first, non-matching line. The mutation
  battery confirms it (replace the reader with `head -1 | grep -m1` and `ac1-plugin` fails).

## Prevention

When a sweep converts a production pipeline, grep the test tree for a replica of it (the same `sort -V -r | grep -m1` text, the
same variable names) in the same PR. A replica asserts the carrier's behavior only while it has the carrier's shape.
