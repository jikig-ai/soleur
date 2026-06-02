---
title: "Docker journald log driver maps ALL container stdout to PRIORITY 6 — filter by the pino `level` field, not journald PRIORITY"
date: 2026-06-02
category: integration-issues
module: apps/web-platform/infra/vector.toml
issue: 4773
pr: 4786
tags: [vector, journald, docker, pino, observability, log-filtering]
---

# Docker journald driver → PRIORITY 6 → filter by pino `level`, not journald PRIORITY

## Problem

PR #4773 PR-C routed the Next.js app container's pino stdout to Better Stack by
switching the container to `--log-driver journald` and adding a Vector
`[sources.app_container_journald]` source. The plan prescribed a journald
`include_matches.PRIORITY = ["0".."4"]` (WARN+) filter to keep volume down —
mirroring the two existing journald sources (`inngest_journald`,
`system_journald`).

That filter would have **dropped 100% of the cron lines it was meant to ship.**

## Root cause

Two facts compose into the trap:

1. **pino writes every level to fd 1 (stdout).** `apps/web-platform/server/logger.ts`
   constructs `pino({ ... })` with **no `destination`** and no per-level stream
   routing. In production (no `pino-pretty` transport) that means `logger.error`,
   `logger.warn`, and `logger.info` ALL go to fd 1 — the level lives only in the
   JSON payload (`"level":50`), never in the OS stream.

2. **Docker's journald log driver tags by file descriptor, not by app log level.**
   stdout (fd 1) → journald `PRIORITY=6` (info); stderr (fd 2) → `PRIORITY=3`
   (err). It does NOT parse the application's JSON to discover the real level.

So every pino line — including error-level cron-failure lines — lands in journald
at `PRIORITY=6`. A Vector source filtering `include_matches.PRIORITY = ["0".."4"]`
matches nothing. `vector validate` passes (the config is syntactically valid), and
the source ships **zero** lines — a silent false-clean that only surfaces as
"no cron lines in Better Stack" post-deploy.

The existing `inngest_journald` / `system_journald` sources can use a PRIORITY
filter because their producers are systemd units whose journald PRIORITY reflects
the real severity. A Docker-json-driver→journald container is different.

## Solution

Do not filter the app-container source by journald PRIORITY. Instead:

- Source: `include_matches.CONTAINER_NAME = ["soleur-web-platform"]`, **no**
  PRIORITY match.
- A downstream `[transforms.app_container_warn_filter]` (`type = "filter"`) parses
  the pino JSON `level` and keeps `>= 40` (WARN/ERROR/FATAL), keeping non-JSON
  crash lines (fd 2 stacks):

```toml
condition = '''
parsed, parse_err = parse_json(.message)
if parse_err != null {
  true
} else if is_object(parsed) {
  parsed_obj = object!(parsed)
  level_int = to_int(parsed_obj.level) ?? 0
  level_int >= 40
} else {
  true
}
'''
```

Wire the filter output (not the raw source) into the existing `pii_scrub_*`
redaction chain so the app container's lines are scrubbed like every other source.

The INFO-level signal you'd lose (e.g. the `claude --print` max-turns notice,
logged via `logger.info`) reaches Sentry by a different path
(`SpawnResult.stdoutTail` → `scheduled-output-missing` extra). Better Stack gets
WARN+ for queryable diagnosis; Sentry gets the full failure tail.

## Key insight

**When a Docker container uses `--log-driver journald`, journald PRIORITY reflects
the file descriptor (stdout=6 / stderr=3), not the application's log level.** If
the app logs structured JSON to stdout (pino, bunyan, winston-json), you MUST
filter on the parsed `level` field downstream — a journald PRIORITY filter is
either vacuous (drops everything) or useless (passes everything). Verify the
producer's fd/level behavior (`grep destination` in the logger config) before
choosing a PRIORITY-based source filter. `vector validate` will NOT catch this —
it is a runtime-semantics gap, not a config-syntax error.

## Session Errors

1. **`set -uo pipefail` tripped the Bash-tool shell snapshot** — the review skill's
   classification-gate snippet prescribes `set -uo pipefail`; running it under the
   Bash tool failed with `ZSH_VERSION: unbound variable` (exit 127) because the
   shell snapshot references `$ZSH_VERSION` unguarded. **Recovery:** re-ran the
   greps without `set -u`. **Prevention:** the review SKILL.md classification
   snippet should not assume `set -u` is safe in the non-interactive Bash tool
   (it already drops `e`; it should drop `u` too, or guard `${ZSH_VERSION:-}`).

2. **Edit failed on `ci-deploy.sh` prod docker-run block (stale read).** The first
   Edit used an `old_string` derived from an earlier partial read that omitted the
   `--restart unless-stopped` line (line numbers had also shifted after the canary
   edit), so it returned "String to replace not found." **Recovery:** re-Read the
   exact target range, then the Edit matched. **Prevention:** re-Read the exact
   lines immediately before an Edit when prior edits in the same file have shifted
   line numbers — do not trust an earlier wide-range read.

3. **Background `vitest run > log 2>&1; echo "EXIT=$?"` → the task-completion
   notification reported "exit code 0", which was the trailing `echo`'s exit, NOT
   vitest's.** A real test failure (1 timeout flake) was present. **Recovery:**
   read the log's own `Tests N failed` summary line rather than trusting the
   reported exit; confirmed it was a pre-existing env-timeout flake by re-running
   the file in isolation. **Prevention:** don't append `; echo …` after a command
   whose exit code you need from a background task — the harness reports the LAST
   command's exit. Capture `rc=$?` into the log, or make the measured command last.

(Forwarded from session-state.md: the planning subagent noted the Task subagent
tool was unavailable in pipeline context, so plan-review/deepen fan-out ran inline
via grep/read — a degradation, not an error; all gates still executed.)
