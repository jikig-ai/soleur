---
title: "A telemetry-blind fatal give-up let four worktree-wedge fixes fly blind; the real bug was a non-bare guard misfiring under a char-device config mask"
date: 2026-07-07
category: bug-fixes
module: git-worktree
issue: 5934
tags: [git-worktree, telemetry, observability, config-lock, char-device, non-bare, evidence-first, adr-081, mask-degraded-guard]
synced_to: [review, git-worktree]
---

# Learning: telemetry-blindness meta-bug + mask-degraded non-bare guard

## Problem

`worktree-manager.sh create` kept wedging the agent sandbox with:

```
SOLEUR_GIT_LOCK_UNREMOVABLE file=config.lock type=chardevice ... reason=non-regular-lock
mv: cannot move '.git/config.soleur-tmp.4' to '.git/config': Device or resource busy
[error] worktree wedge: could not apply shared-config prerequisites in .git
```

The rename **TARGET** (`.git/config`), not just `.git/config.lock`, is char-device-masked by the
per-session bwrap RCE guard (ADR-081), so `atomic_git_config`'s `mv … .git/config` hit `EBUSY` and
the run gave up at the `ensure_bare_config` fatal path — even though the workspace is a **non-bare**
clone that never needed bare-config surgery at all. Four prior fixes (2026-07-01 → 07-07: the
`config.lock` sweep, lockless `atomic_git_config`, non-bare guard rounds 4–5) had all targeted this
path and none converged.

## Root cause (two coupled defects)

1. **The guard misfired under the mask.** The non-bare skip gated on `git rev-parse
   --show-toplevel` / `--is-bare-repository`, both of which must read the masked `.git/config`.
   Under the char-device mask `--show-toplevel` returns empty (`GIT_ROOT=""`) and
   `--is-bare-repository` degrades to `true`, so a genuinely **non-bare** clone was wrongly routed
   into bare-repo config surgery and reached the fatal `mv`. Live probes pinned it:
   `git rev-parse --is-bare-repository` = `false`, `stat .git` = directory,
   `stat .git/config.worktree` = character-special-file.

2. **The fatal give-up was invisible to telemetry (the meta-bug).** The `[error] worktree wedge:`
   line is emitted via `headless_or_stderr` (`.claude/hooks/lib/session-state.sh`), which in the
   headless sandbox appends to a **per-PID logfile**, not the Bash stdout the PostToolUse telemetry
   hook scans; AND its `[error] ` prefix fails `MARKER_RE`'s `^worktree wedge:` anchor
   (`git-lock-marker-telemetry.ts`). Double-drop → the fatal outcome fired on every wedged run yet
   Better Stack showed **zero** `worktree wedge:` events over 30 days. That "zero events" was the
   symptom, not exoneration — and it is exactly what caused the first planning pass to wrongly
   declare the bug already-fixed.

## Solution

- **D1 — observability meta-fix (highest priority):** emit a bare `echo` stdout sentinel at all
  four `ensure_bare_config` give-ups and at the `atomic_git_config` rename-failure / masked-target
  pre-check, in addition to the existing `headless_or_stderr` line, so the conclusion is
  scanner-visible under the logfile sink. Added `SOLEUR_GIT_CONFIG_TARGET_MASKED`,
  `SOLEUR_GIT_CONFIG_MASK_SKIP` (benign), `SOLEUR_FEATURE_PUSH_FAILED`, `NO_GIT_REPOSITORY` to
  `MARKER_RE`; relaxed `MARKER_RE`/`WEDGE_RE` to tolerate an optional leading `[<level>] ` prefix so
  the existing `[error] worktree wedge:` line finally matches. Broadened the drift-guard collection
  pattern to `SOLEUR_[A-Z_]+|NO_GIT_REPOSITORY`.
- **D3 — non-bare guard-repair (operator-facing fix):** detect non-bare via a pure filesystem fact
  (`git_dir` is a `.git` **directory**, plus a `$PWD/.git` fallback when `GIT_ROOT` resolves empty)
  that never reads the masked config; skip the surgery and emit the benign
  `SOLEUR_GIT_CONFIG_MASK_SKIP branch=non-bare-skip`. `git rev-parse --is-bare-repository` /
  `--show-toplevel` are no longer trusted first. Genuinely-bare + masked target fails LOUD with
  `SOLEUR_GIT_CONFIG_TARGET_MASKED reason=bare-under-mask` naming the host-seed remedy (#6191/#5934).
- **D2 — target-masked pre-check** in `atomic_git_config` (`_config_target_masked`: `[[ -c "$t" ]]`
  OR realpath-is-its-own-mount-root), placed after the read-first / before the native-vs-lockless
  decision so it covers both branches; do not attempt the doomed `mv`.
- **D5 — local mask-simulation test (T20–T23):** `mknod`/`ln -s /dev/null` masked-target proxy +
  `core.bare=true` + empty `GIT_ROOT` to reproduce the D3 guard-misfire deterministically. Genuine
  RED→GREEN on a normal checkout.
- **D4 cut:** self-heal of a stale `extensions.worktreeConfig` — the flag was confirmed UNSET via a
  live probe, and its write targets the exact masked path, so it added risk without fixing the bug.

The host-side defect (`.git/config*` materialized as char devices with sandbox write-blocks) is a
platform/provisioning artifact tracked in #5934/#6191; the in-repo fix makes git-ops robust to it
and finally visible, but cannot remove the nodes. #5934 stays OPEN; PR uses `Ref`, not `Closes`.

## Key insights

1. **Telemetry-blindness meta-bug.** A fatal give-up on a blind execution surface (headless
   sandbox) that routes through `headless_or_stderr` (per-PID logfile) and/or carries an `[error] `
   prefix is INVISIBLE to the marker pipeline. This let FOUR prior fixes fly blind against a
   zero-events dashboard. Fix pattern: a fatal give-up MUST emit a monitored **stdout** sentinel,
   and `MARKER_RE` must tolerate the `[error] ` level prefix + allowlist the new sentinels.
2. **Guard-misfire-under-mask.** A guard that gates on `git rev-parse --show-toplevel` /
   `--is-bare-repository` is NOT robust when the `.git/config` it reads is char-device-masked
   (empty `GIT_ROOT` / degraded bare-status). Detect layout via a pure filesystem fact
   (`.git`-is-a-directory) that never reads the masked config.
3. **Diagnostic discipline.** Operator direct observation ("still wedges post-deploy") is ground
   truth that trumps blind telemetry. The verbatim error + three live probes
   (`--is-bare-repository`=false, `stat .git`=directory, `stat .git/config.worktree`=char-device)
   pinned the root cause only after TWO agent investigations reached partially-wrong conclusions
   from telemetry alone.
4. **Device-node provisioning artifact ≠ in-repo guard.** The masked `.git/config*` char devices
   are a host-side/platform defect (#5934/#6191), distinct from the in-repo guard fix. The in-repo
   fix makes git-ops robust and visible; it cannot remove the nodes.

## Session Errors

- **First planning pass refuted the operator's premise from blind telemetry.** The plan+deepen pass
  declared the wedge "stale, already fixed by #6183" because Better Stack showed zero worktree-wedge
  events in 30 days — a WRONG conclusion that forced a full plan rework. The telemetry was blind
  (fatal line via `headless_or_stderr` logfile + `[error]` prefix failing `MARKER_RE`), so
  "zero events" was a symptom, not exoneration. **Recovery:** operator-verbatim error + live probes
  overturned it; plan re-scoped to the live root cause. **Prevention:** a planning agent must treat
  "zero telemetry events" that contradicts a direct operator observation as a telemetry-coverage
  question to VERIFY (does the fatal path reach a monitored sink?), never as proof the bug is absent.
  (recurring → routed to review defect classes)
- **Plan scope reworked twice before the root cause was pinned.** First framed as a
  "config-target-masked defensive pre-check" (defense-in-depth), then corrected to the confirmed
  root cause "non-bare guard misfires under the char-device config mask"; deliverable D4 (self-heal
  stale `extensions.worktreeConfig`) was added, then CUT mid-implementation after a live probe
  showed the flag unset. **Recovery:** live probes (bare-vs-non-bare + the exact masked node)
  re-scoped the deliverables. **Prevention:** pin bare-vs-non-bare and the exact masked node via
  live probes BEFORE finalizing scope; a config-write self-heal that targets a masked/blocked path
  is itself risky and must be probe-gated. (recurring → routed to git-worktree Sharp Edges)
- **Initial file Read used the main-repo absolute path instead of the worktree path.** Corrected
  immediately (re-read from the `.worktrees/…` path). **Prevention:** in a worktree, always build
  absolute paths from the worktree root, never the bare/main root
  (`hr-when-in-a-worktree-never-read-from-bare`). (one-off, self-corrected)

## Tags
category: bug-fixes
module: git-worktree
