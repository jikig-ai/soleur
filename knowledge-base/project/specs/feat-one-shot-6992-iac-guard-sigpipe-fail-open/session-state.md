# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-07-27-fix-guard-hygiene-sigpipe-and-tmpfs-reaper-plan.md`
- Status: complete
- Scope: #6992 + #6991 (operator widened scope mid-run to include #6991)

### Errors
No `iac-plan-write-guard.sh` denials fired during planning. The known hazard did not trigger
because every plan write used `Write` (whole document, ack included) rather than `Edit` — which
is itself corroborating evidence for the corrected diagnosis: the ack works on the `Write` path
and fails only on `Edit`.

One methodology error caught mid-session: the first three race probes measured the wrong binary.
`grep` in the agent Bash tool resolves to a Claude Code **ugrep shim shell function**, and ugrep
`-q` drains its input, so the race showed 0/40 and looked refuted. Re-running under
`env -i PATH=/usr/bin:/bin` against GNU grep 3.12 gave the real answer. Became plan finding R8
and a mandatory acceptance criterion.

### Decisions
- **#6992's stated mechanism is refuted by measurement.** All 7 checks use `echo` — a bash
  **builtin** — and builtin producers cannot raise SIGPIPE (0/40 failures up to 1 MB; hook
  end-to-end 12/12 correct on 5 arms). The real cause of the reported 9-deny/3-allow is that the
  hook scans only `new_string` on an `Edit`, so an ack living elsewhere in the file is invisible.
  Reproduced deterministically both ways. The issue does **not** close as invalid — the symptom
  is real, the explanation was not.
- **The decisive triage axis is producer class, not input size.** External producers (`cat`,
  `git show`, `base64 -d`, `jq`) race non-deterministically at **every** size including 1 KB
  (`yes | grep -q` → `141 0`, 3/3). Cut Part A's scope from ~95 shape-matching sites to ~8
  genuinely live ones.
- **Review found a larger, unfiled fail-open:** `.claude/settings.json` registers this hook with
  matcher `Write|Edit` while three sibling hooks use `Write|Edit|MultiEdit|NotebookEdit`. Any
  plan written via MultiEdit bypasses the IaC guard entirely, today. Promoted to headline fix.
  (Independently verified by the parent before accepting the plan.)
- **Three v1 design claims were falsified at review and reversed.** Dropping `SCRATCH_MIN_MB`
  would have deleted a **live Chrome IPC socket directory** (the liveness scan is blind to unix
  sockets — socket fds readlink to `socket:[inode]`). The "cheaper without `du`" claim was
  inverted ~100× (~316 s extrapolated, exceeding the 5-minute cron). And `df -i` would never have
  fired as a trigger (7% inodes while the leak is present). Phase 6 now fixes liveness first,
  *reduces* rather than removes the floor, and triggers on entry count.
- **Two of the issues' own suggested directions are blocked by measured repo state**, and the
  plan says so rather than prescribing paths that don't exist: `scratch-root.sh` has zero
  production callers, and there is no local-cron → remote-observability path (no Vector on this
  host, tag not allowlisted, no local Sentry DSN, `doppler` off cron `PATH`, `gh` gated by an
  unreachable keyring).

### Dissent recorded, not applied
Plan-review recommended splitting into two PRs (no shared file, mechanism, test, or failure
mode). The operator's directive is one PR closing both issues, so the single-PR shape stands.
Reasoning persisted to `decision-challenges.md`.

### Components Invoked
- `Skill: soleur:plan`
- `Skill: soleur:deepen-plan`
- `Agent: general-purpose` ×2 (sweep triage by producer class; tmpfs observability research)
- `Agent: soleur:engineering:review:code-simplicity-reviewer`
- `Agent: soleur:engineering:review:architecture-strategist`
- Deepen-plan gates 4.5–4.10 (all pass), KB citation verification, AGENTS rule-ID verification
