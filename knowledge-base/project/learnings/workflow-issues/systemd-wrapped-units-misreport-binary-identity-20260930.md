---
title: "doppler-wrapped units: MainPID and ExecStart.path= both resolve to the WRAPPER — and /proc/<pid>/exe is denied under yama ptrace_scope=1"
date: 2026-09-30
category: engineering
tags: [systemd, doppler, procfs, yama, observability, deploy-status, inngest, review-panel]
symptoms: [a "running version" field resolved doppler instead of inngest — MainPID is the wrapper process (doppler run forks+waits, never execs), ExecStart's structured path= token is the wrapper's path, and readlink /proc/<pid>/exe on a same-UID non-descendant is EACCES under ptrace_scope=1; in-repo comment asserting "exec keeps inngest as the unit's main PID" was simply wrong]
module: /hooks/deploy-status (cat-deploy-state.sh)
synced_to: []
component: process
problem_type: workflow_issue
resolution_type: process-correction
root_cause: designed process-resolution legs against an assumed ExecStart shape without reading the real rendered unit; two independent reviewers caught it, and each claimed mechanism was then verified empirically
severity: medium
---

# Measure the installed binary; don't fake a running-process read through wrappers

## What happened

A field meant to report the *running* inngest version resolved the binary three
ways: `/proc/<MainPID>/exe`, the `ExecStart` `path=` token, then the installed
path. Both reviewers independently flagged legs 1–2 as dead, and both claims
verified empirically:

1. **doppler stays MainPID.** `ExecStart=/usr/bin/doppler run -- bash -c '… exec
   /usr/local/bin/inngest …'` — `doppler run` forks the payload and stays alive
   to forward signals (verified: Doppler CLI uses `exec.Cmd`+`Wait`). The inner
   `exec` replaces the *child* bash, not the unit's main PID. So `MainPID→exe`
   resolves doppler, and `doppler version` isn't even a registered subcommand —
   the leg could emit `""` today and *doppler's* version tomorrow.
2. **yama blocks the shortcut anyway.** On Ubuntu 24.04's default
   `kernel.yama.ptrace_scope=1`, `readlink /proc/<same-uid non-descendant>/exe`
   → EACCES (verified on this host; `comm`/`cmdline` remain readable).
3. **The seed was a wrong in-repo comment.** `inngest-bootstrap.sh` asserted
   "the `exec` in the ExecStart keeps inngest as the unit's main PID" — false,
   and the design leaned on it. Fixed in the same PR.

Shipped the honest single leg instead: the *installed* binary's self-reported
`version` (bootstrap pins version+sha256; immutable-redeploy keeps
installed≈running), with discriminating sentinels (`absent`/
`unknown-no-timeout`/`version-unreadable`) rather than a bare `""`.

## Rules of thumb that survived

- **Any `ExecStart` wrapped in a supervisor (`doppler run`, `env`, `bash -c`)
  makes `MainPID`, `ExecStart.path=`, and `/proc/<MainPID>/exe` point at the
  wrapper.** If you need the inner process, walk
  `/proc/<pid>/task/<pid>/children` (then accept that `exe` readlink is
  yama-gated) or read `comm`/`cmdline` — or just admit the question can't be
  answered that way.
- **Test fixtures must mirror the PRODUCED ExecStart**, not the convenient one —
  every mock here pointed the unit straight at a stub inngest, so the suite was
  green while production legs were dead. When the fixture encodes a shape the
  renderer never emits, the tests prove nothing.
- **`$()` + `set -e` swallows intent, not exit codes**: a helper whose last
  command is `[[ -n $x ]] && printf` returns 1 on the empty case, and the
  assignment propagates it — the garbage-output arm caught the whole hook
  aborting. Helpers feeding `$( )` under `set -e` must return 0 unconditionally.
- **Bound every exec probe**: `timeout` without `-k` waits forever on a
  SIGTERM-ignoring child; and `head -1` caps lines, not bytes — add
  `head -c N` for anything entering an HTTP body.
