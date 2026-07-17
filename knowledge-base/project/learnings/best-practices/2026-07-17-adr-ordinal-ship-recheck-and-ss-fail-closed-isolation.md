---
title: ADR ordinal must re-check at ship; optional ss makes isolation fail-open
date: 2026-07-17
issue: 6546
pr: 6597
tags: [adr, review, dogfood, isolation, shell, fail-closed]
category: best-practices
---

# Learning: ADR ordinal ship re-check + ss fail-closed isolation

## Problem

Phase 2 open-weight GPU dogfood (#6546 / PR #6597) shipped pre-merge artifacts claiming **ADR-118** while `origin/main` already owned `ADR-118-proxy-cert-sans-track-the-cluster-roster.md`. Plan text said “provisional ordinal — re-verify at ship” but implementation used 118 without re-check. Concurrent branches also claimed 118.

Separately, `assert_ollama_loopback` wrapped the public-bind die in `if command -v ss` — when `ss` was missing, only loopback `curl` ran, which succeeds even if Ollama listens on `0.0.0.0:11434`. Structure tests grepped prose and stayed green if `die` was demoted to `log`.

## Solution

1. **Renumber at review/ship:** free ordinal vs fresh `origin/main` → **ADR-120**; sweep plan/runbook/tasks/discoverability.
2. **Fail-closed isolation:** require `ss` (install iproute2); shared `scripts/dogfood/assert-ollama-loopback.sh` used by bootstrap and by `grok-measure.sh` for `--model local-open`.
3. **Tests pin control flow:** `LICENSE_OK` die regex, public-bind die anchor, base_url unit tests; register dogfood suites in `scripts/test-all.sh`.

## Key Insight

Provisional ADR ordinals are a race against main and siblings — the free number at plan time is not free at merge. Isolation gates that soft-skip their probe (`command -v ss && …`) fail open on the exact catastrophe they name. String greps of die *messages* are not mutation-safe for security gates.

## Session Errors

1. **Session-start cleanup path** — `plugins/soleur/skills/git-worktree/scripts/cleanup-merged.sh` missing from cwd shape used; recovered via direct worktree path. **Prevention:** always `cd` repo root / use worktree-manager absolute path.
2. **ADR-118 collision** — plan provisional ordinal not re-checked at implement/ship. **Prevention:** ship ADR-ordinal gate (`check-adr-ordinals.sh`) + renumber before ready; plan AC must say “free ordinal at *ship*, not plan”.
3. **ss optional public-bind** — multi-agent review converged; fixed fail-closed. **Prevention:** security assert must die when probe binary missing.

## Tags

category: best-practices  
module: scripts/dogfood, ADR, review
