---
title: Moving 53 argv bearers to curl's stdin config needed a ratchet, a token-shape guard and process substitution, not a pipe
date: 2026-10-06
category: security-issues
tags: [curl, config-stdin, argv, xtrace, lint-ratchet, pipefail, sigpipe, review-coverage]
---

# Moving argv bearers to curl's stdin config

## Problem

`-H "Authorization: Bearer $TOK"` puts the token on curl's argument list, so `bash -x`, `ps` and `/proc/<pid>/cmdline` can all show it. PR #9594 moved 53 tracked scripts (123 sites) to `curl --config -`. Ref #7797, #7843; residue in #9597.

## Solution and the measured sharp edges

- **Canonical form:** `curl --disable --noproxy '*' … --config - URL < <(printf 'header = "Authorization: Bearer %s"\n' "$TOK")`. Process substitution, never `printf | curl`: a consumer that does not read stdin makes the writer exit 141 (SIGPIPE) under `pipefail`, and the 100,000-byte-token battery row measures it (pipe-form mutant 141, process substitution 0). `#!/bin/sh` scripts cannot use `<(…)`, which is part of why Tier 2 was deferred.
- **Token-shape guard before any curl:** `_bearer_ok` accepts `[A-Za-z0-9._~+/=-]` only. A newline or quote in the token injects a curl config directive (`url = …`), and an unset token silently sends a headerless request. A response-derived token (bsky login) is the same hazard.
- **Ratchet first, then convert:** a new lint Rule E counts argv-bearer sites per file against a baseline compared by equality, so every phase shrinks the baseline and nothing can regrow. `--changed` bypasses the baseline, so touching a deferred file forces its conversion.
- **A meta-guard can go vacuous when the test changes shape:** moving a here-string (`<<<`) to `printf | bash -c` in `arm-heartbeats.test.sh` is what the fixture-relative-assert and vacuity-floor guards watch; the floor was re-measured (234), not lowered.
- **Env-derived URL parts need a literal pin** (Rule D): a converted script still sends the token to whatever `$BASE_URL` says, so the host is pinned to a literal before the credential is read.
- **Coverage honesty:** the review panel died on an API weekly limit (HTTP 429). The trailer says `Reviewed-Coverage: degraded 4/10 agents (missing: …)` and the gaps were covered by named inline checks. A degraded panel is never reported as full-strength evidence.

## Session Errors

1. **Review seats died on a 429 weekly limit; most ended as stubs** — Recovery: waited for the reset, re-ran, covered the missing lenses inline, emitted a degraded trailer — Prevention: the review skill should record per-seat delivery and refuse a full-strength trailer when a seat returned a stub.
2. **`scripts/test-all.sh --affected` was queued behind sibling worktrees twice (first run killed, second sat at position 2 for ~55 min)** — Recovery: ran the owning suites directly (lint 119, battery 137, guard-vacuity 23, fixture ratchets, orphan lint) and left the full run to CI — Prevention: run the owning suites first, treat the local affected gate as supplementary when the queue position does not move, and state that in the PR body.
3. **`pkill -f` was blocked by the self-matching-pattern hook** — Recovery: `source plugins/soleur/scripts/lib/proc.sh; kill_mine '<pattern>'` (takes a pattern argument) — Prevention: already hook-enforced; use `kill_mine <pattern>`, not a bare `kill_mine`.
4. **A production-pin regression and a vacuous guard from `<<<` appeared mid-sweep** — Recovery: fixed and pinned by a lint row — Prevention: Rule D now requires the literal pin; the vacuity-floor suite covers the here-string shape.
5. **`set-role.sh` was missing from the first sweep and mis-listed in #9597 as residue** — Recovery: converted in `cd4125cc81` and corrected on #9597 — Prevention: derive the deferral list from the census script, not from memory (the census now equals the Tier 2 set).
6. **A rebase conflicted on the shard manifest** — Recovery: regenerated `suite-shard-legs.tsv` and `suite-durations.tsv` rather than hand-merging — Prevention: generated manifests are regenerated, never merged.

## Key Insight

When a security sweep touches dozens of files, the durable artifact is the ratchet (a per-file baseline that can only shrink), not the conversions. The conversion form needs its own measured failure modes (SIGPIPE under `pipefail`, config-directive injection from the token itself) pinned by tests that fail on the wrong form.
