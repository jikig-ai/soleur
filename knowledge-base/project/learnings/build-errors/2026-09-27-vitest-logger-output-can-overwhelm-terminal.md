---
title: Capture noisy full-suite Vitest output and print a bounded summary
date: 2026-09-27
category: build-errors
module: apps/web-platform tests
---

## Problem

The full Web Platform Vitest suite emits fixture logger output even with
`--silent`. Running it directly produced an oversized terminal stream and was
interrupted before a verdict, so the exit code was not a test result.

## Prevention

Redirect the full-suite output to a temporary log, then print only the test
summary and a bounded failure excerpt. If interrupted, report it as an
incomplete run and rerun with captured output; never treat its partial output
or exit status as a pass/fail verdict.
