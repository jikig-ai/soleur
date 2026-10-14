---
title: /tmp count-shaped mktemp leak across agent sessions — size reaper cannot reclaim
date: 2026-10-11
category: workflow-issues
tags: [tmpfs, mktemp, leak, agent-sessions, watcher, host-health]
symptoms: [tmpfs-guard alarm "/tmp grew to 7710 top-level entries (+7689 above watermark)" at 34% usage, thousands of tmp.* and rung2-archive.* entries spanning days]
module: System
component: tooling
problem_type: workflow_issue
resolution_type: workaround_documented
root_cause: unreaped_mktemp_artifacts
severity: medium
---

# Troubleshooting: /tmp count-shaped mktemp leak across agent sessions

## Problem

The tmpfs-guard fired a count alarm: `/tmp` held ~7,700 top-level entries
(+7,689 above a 21 watermark, trigger 5,000) at only 34% usage — a
**count-shaped** leak the size-based reaper cannot reclaim. Two days of
accumulation (Oct 9-11) across ~50 parallel agent worktrees/sessions.

## Signature

- ~7,000 `tmp.*` entries — `mktemp` artifacts created by pipeline tooling
  (sampled contents: a ship-phase `sync-pr-behind` resync script, drafted
  commit messages, scratch ASCII). Bursts of ~6/sec correlated with skill
  runs; not one-per-exec.
- ~650 `rung2-archive.*` directories — full copies of the git-data rung-2
  script set archived per run (infra/probe tooling leaving its work dir).
- All creator-owned (`jean`), mostly 0-byte or small; the leak is the COUNT,
  not bytes.

## Mitigation applied (session-level, not a fix)

Age-filtered sweep, ~3,000 entries reclaimed:

```bash
find /tmp -mindepth 1 -maxdepth 1 -name 'tmp.*' -mmin +720 -delete
find /tmp -mindepth 1 -maxdepth 1 -type d -name 'rung2-archive.*' -mmin +720 -exec rm -rf {} +
```

Age filter (12h) keeps anything a live session might still hold open.
Entries `devin-overflows-1000`, `codex-*`, `argv-bearer-sweep.*` are
harness-owned — leave them.

## Not fixed

The producer sites (whichever skills/scripts `mktemp` under `/tmp` without
a cleanup trap, and the rung-2 archive step) still leak. Correct fix is a
`trap 'rm -rf "$tmp"' EXIT` (or systemd-tmpfiles `d /tmp` age rule) at each
producer — a census, not a one-liner. Tracked in the issue linked from the
resume prompt that produced this file.

## Environment

- Host: operator workstation (Omarchy), tmpfs `/tmp`
- Observed: 2026-10-11, during feat-open-web-egress post-merge recovery
