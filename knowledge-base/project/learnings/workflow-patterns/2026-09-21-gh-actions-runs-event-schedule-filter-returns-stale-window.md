---
title: "gh api actions/runs?event=schedule can return a stale window — measure cron cadence per-workflow"
synced_to: [brainstorm]
---

# Learning: `gh api actions/runs?event=schedule` can return a stale window — measure cron cadence per-workflow

## Problem

While measuring the scheduled-workload share for #8450 (CI concurrency ceiling),
the repo-wide probe

```bash
gh api 'repos/<o>/<r>/actions/runs?event=schedule&per_page=100'
```

returned 100 runs spanning **2026-08-26 → 2026-08-30** — nearly a month stale —
while unfiltered `actions/runs` showed `pull_request` runs from the same hour.
Read naively, the schedule run history says "no cron has fired in ~3 weeks," and
that conclusion was within one step of being written into a brainstorm artifact.

Per-workflow probes immediately disproved it:

```bash
gh api 'repos/<o>/<r>/actions/workflows/<id>/runs?per_page=3'
# → schedule runs from the same day, healthy
```

The repo-wide `?event=schedule` filter is unreliable on a busy repo (the filter
is served from a different index than the unfiltered list; it lags or truncates
without signaling). A partially-stale result is worse than an empty one: it
looks like a complete answer.

## Solution

For any "how often does cron X fire / did scheduled runs stop" question:

1. Enumerate workflows carrying real `schedule:` triggers
   (`git ls-tree --name-only main -- .github/workflows/` → `git show` each →
   grep `^\s*schedule:` — **not** `grep -l 'schedule:'`, which also matches
   comment mentions and over-counted 20 real crons as 27 in #8450's body).
2. Query **each workflow's own** runs endpoint (`actions/workflows/<id>/runs`),
   which returns current data.
3. Treat a repo-wide filtered result that ends weeks ago while unfiltered
   results are current as an instrument artifact — never as evidence the crons
   stopped.

## Key Insight

A filtered list endpoint can silently serve a different freshness window than
its unfiltered sibling. When a filter's output ends in a suspiciously clean gap
("nothing since <date>"), cross-check one member through its entity-scoped
endpoint before accepting the negative. Same family as the `--limit` truncation
trap in `ship/SKILL.md`: the trap is not that the API fails — it is that it
answers a narrower question than the one you asked, and answers it completely.

## Session Errors

1. **`git ls-tree --name-only <tree> -- <dir>/` returns full paths, not
   basenames.** First pass built `origin/main:.github/workflows/.github/workflows/<f>`
   and produced all-empty bodies and a `0` count that read as "no triggers."
   **Prevention:** pipe through `sed 's|.github/workflows/||'` (or check one
   `git show` on the first element) before looping.
2. **Trusted the repo-wide `event=schedule` window.** Described above.
   **Prevention:** entity-scoped verification probe before writing a
   staleness/cessation claim into an artifact.

## Tags

category: workflow-patterns
module: ci/github-actions
related_issues: [8450]
