---
title: A trailing shell && prevents the intended probe from running
date: 2026-09-28
category: build-errors
module: shell-probe-construction
---

## Problem

A read-only `rg` probe ended with a dangling `&&`, so Bash returned a syntax
error before running any command in the chain.

## Prevention

Only add `&&` when another command follows it. Run the intended probe again
without the empty chain terminator before interpreting any result.
