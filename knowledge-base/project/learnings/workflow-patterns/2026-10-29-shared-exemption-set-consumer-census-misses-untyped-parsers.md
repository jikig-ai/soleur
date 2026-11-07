---
title: A shared exemption set's consumer census missed the untyped parsers — twice
date: 2026-10-29
category: engineering
tags: [workflow-patterns, observability, sentry, test-suites, exemptions]
issue: '#6590'
---

# Learning: A shared exemption set's consumer census missed the untyped parsers — twice

## Problem

PR-B of the #6590 monitor prune introduced `PRUNED_MONITOR_SLUGS` — a shared
43-slug set making "declared ∪ pruned = legal universe" the contract at every
guard that used to require slug→monitor parity. The plan enumerated the
consumers as "three vitest guards + two shell suites". The review panel found
the real surface was **six consumers + one manifest**: it additionally missed
`infra/supabase-advisor/scan-workflow.test.sh` (two rows extracting the
destroyed block → live red) and the argv-bearer `DELEGATED_MANIFEST` row +
floor for the retired #10972 probe (two more live reds). The diff implemented
the exemption at every site the plan named — **the plan's census itself was
the gap.** One round later, the format-contract comment claiming "FIVE
consumers" was wrong the day it was written (the sixth had just been added).

## Solution

When a shared manifest becomes a legal-universe contract, census **every
parser of the governed files**, not every *named guard*: the miss was in
untyped consumers (a shell suite awk-extracting the tf block by name, a
manifest registry keyed by file path) that no import graph or grep for the
set's identifier can reach — they read `cron-monitors.tf`/the deleted probe
directly. The working search was: every file whose assertions touch
`cron-monitors.tf` contents or `scripts/followthroughs/` paths, found by
running the affected suites, not by reading the code.

## Also durable

- **A `.ts` file consumed by shell regex needs a byte-level format contract**,
  and the shell parses must anchor on the list-entry line (`^\s*"slug",?\s*$`).
  A quoted kebab token inside a comment otherwise enters the parsed set and
  silently exempts whatever it names — the allowlist-rot class (#8595) one
  layer down, invisible to the typed import consumers' own assertions.
- **Cardinality-pin a curated exemption set** (`size === 43`). `∩ declared = ∅`
  + `⊆ producers` both pass for a fresh never-declared slug with a live
  emitter — the "exempt a brand-new monitor" lane — unless the count is pinned.
- **Destroy-window audits flag live-but-undeclared as expected state.** Between
  the .tf delete and the apply's destroy, the 43 monitors are live-undeclared;
  the Class D machinery reporting them then is working as designed — the
  post-merge audit is what must show zero survivors (#6615's provider-id gap
  is why plan-green is insufficient).
- **Deleting a runbook's subject without sweeping prose that asserts its
  behavior** is the `cq-ref-removal-sweep-cleanup-closures` class at doc level:
  the highest-value stale site was a runbook procedure that *forbade* a correct
  remediation ("no monitor → do not re-fire") for every pruned slug.
