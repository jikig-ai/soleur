---
title: Full /bg-readiness — Soleur concurrency hardening for parallel CC sessions
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec-draft
brainstorm: knowledge-base/project/brainstorms/2026-05-12-cc-agent-view-integration-brainstorm.md
domain_review_carry_forward: true
---

# Feature: Full /bg-readiness — concurrency hardening for parallel Claude Code sessions

## Problem Statement

Anthropic shipped Agent View (`claude agents`, `/bg`, `claude --bg [task]`) — a CLI feature making it trivial for a Soleur operator to launch multiple concurrent Claude Code sessions. Soleur's worktree + SessionStart-hook model assumes a **single foreground writer** and breaks under N>1 parallel sessions in at least four named ways:

1. **`git fetch --prune` race** in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:741`. Multiple SessionStart hooks invoke `cleanup-merged` simultaneously → serialized lock contention on `.git/refs` → losers exit non-zero → per `hr-when-a-command-exits-non-zero-or-prints` should halt and surface, but `/bg` sessions have no operator watching → silent stall.
2. **`cleanup_merged_worktrees` sibling-wipe** at `worktree-manager.sh:755`. Session A merges its PR; Session B's SessionStart sees A's branch as `--merged main` and runs `git worktree remove` on A's still-active directory. This is the 2026-04-21 incident class (`knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md`), amplified by 3× concurrency under `/bg`.
3. **AGENTS.md sidecar loader contention** in `.claude/hooks/session-rules-loader.sh`. Concurrent change-class detection writes the injected sidecar without file-locking → one session loads stale rules → hard-rule violation with no audit trail.
4. **Concurrent `gh pr merge --auto` collisions** via `wg-after-marking-a-pr-ready-run-gh-pr-merge`. Two adjacent PRs touching the same files produce the duplicate-property merge-artifact class documented in `learnings/build-errors/2026-03-20-concurrent-pr-merge-duplicate-object-property.md`.

Additionally, many hooks gate verbose output on `[[ -t 1 ]]` (foreground TTY) — backgrounded sessions silently suppress operator-facing diagnostics, making the above failure modes invisible to the operator until corruption is discovered.

The original "integrate Agent View" framing has zero engineering content (Agent View has no API to integrate with). The actual engineering work is making the existing concurrency model multi-writer-safe. `/bg` and Agent View become free side-effects once the primitives land.

## User-Brand Impact

**Threshold:** `single-user incident`.

A single operator running `claude --bg /soleur:one-shot` 3× and having Session B reap Session A's worktree mid-flight loses committed-but-unpushed local commits and orphans the draft PR. The incident already happened once in foreground mode (2026-04-21); making `/bg` a default workflow without hardening converts a rare collision into a routine failure mode.

Domain leader carry-forward (from brainstorm 2026-05-12):

- **CTO:** PROCEED with full /bg-readiness scope. Cite specific files: `worktree-manager.sh:741`, `:755`, `:802-809`, `:1088`; `session-rules-loader.sh`; `worktree-write-guard.sh`; `pre-merge-rebase.sh`. Use PPID pattern from 2026-03-17 learning.
- **CPO:** PROCEED — operator-data-loss is brand-survival for a dev-tools product even if cloud-first is the strategic direction. Concurrency primitives apply equally to local-worktree workflows AND any future cloud-side multi-session orchestrator.
- **CLO:** GREEN. No legal blockers on this engineering work.
- **CMO:** Silent-and-compatible. Do NOT add Agent View references to operator-facing surfaces (`/soleur:go`, `/soleur:one-shot`, etc.) during this work.

## Goals

- Eliminate the 2026-04-21 incident class entirely: no session can have its worktree reaped by a sibling SessionStart cleanup.
- Make `claude --bg /soleur:<skill>` officially supportable: operator can run 3+ concurrent Soleur workflows under Agent View with no shared-state corruption, no silent stalls, no orphaned PRs.
- Preserve foreground operator experience: no UX regression for the single-session common case.
- Surface previously-silent failures: hooks running headless produce a structured-log artifact the operator can inspect via Agent View attach.
- Splittable into 3-4 reviewable sub-PRs (one per major FR group) — full scope is too large for a single PR.

## Non-Goals

- **Integrating with Agent View as a third-party API.** Agent View has no integration surface; this is misuse of the word. Tracked-and-killed in brainstorm decision #1.
- **Marketing/competitive-intelligence response to Anthropic's launch.** CMO assessment captured for reference but user explicitly rejected this thread.
- **Cloud-UX audit of Phase 3.3 conversation inbox / Phase 3.21 agent work visualization against Agent View's vocabulary.** Deferred to separate tracking issue, aligned with Phase 3.21 active work.
- **Reading Anthropic's internal Agent View state files.** Even if `claude --bg` writes status anywhere in `~/.claude/`, treating those as integration surface couples Soleur to undocumented internals. Out of scope.
- **Rewriting `/soleur:one-shot`, `/soleur:drain-labeled-backlog`, or `/soleur:brainstorm` business logic.** These skills get session-claim helpers as a library; their flow does not change.
- **Distributed locking across multiple hosts.** Soleur's worktree model is single-host. `flock` on local filesystem is sufficient.
- **Backfilling `[[ -t 1 ]]` audit to every script outside `plugins/soleur/skills/` and `.claude/hooks/`.** Scope is Soleur's own hooks + skills.

## Functional Requirements

### FR1: cross-session lock primitive (sub-PR 1)

Add `lib/session-lock.sh` exposing `acquire_lock <name> [timeout-sec]` / `release_lock <name>` wrapped around `flock`. Lock files live at `${GIT_COMMON_DIR:-$GIT_DIR}/soleur-locks/<name>.lock` so all worktrees of one repo share one lock namespace.

- `cleanup_merged_worktrees` in `worktree-manager.sh` MUST acquire `cleanup-merged` lock before iterating branches.
- `git fetch --prune` calls in SessionStart hooks MUST acquire `fetch-prune` lock.
- Locks MUST be released on script exit (`trap 'release_lock ... ' EXIT`).
- Lock acquisition timeout default: 30s. On timeout, skip the operation with a structured-log warning (per FR4) — do not halt the session.

### FR2: session-claim/lease pattern (sub-PR 2)

Adopt the 2026-03-17 PPID-scoped state-file pattern. Every Soleur skill that creates or mutates a worktree MUST write a claim file at `${GIT_COMMON_DIR}/soleur-leases/<worktree-name>.lease` with: PID, PPID, skill-name, started-at ISO-8601, expected-duration estimate.

- `cleanup_merged_worktrees` MUST check for an active lease before reaping. A lease is "active" if its PID is alive AND the lease timestamp is within `now - max(expected-duration, 4h)`.
- Crashed-session orphan recovery: leases older than 24h are unconditionally swept (precedent: `2026-03-09-ralph-loop-crash-orphan-recovery.md`).
- The 10-minute grace heuristic prescribed in `2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md` lines 99-103 lands as a fallback: even without a lease, never reap a worktree whose most recent commit is < 10min ago.
- `/soleur:one-shot`, `/soleur:drain-labeled-backlog`, `/soleur:brainstorm`, `/soleur:work`, `/soleur:plan` MUST acquire a lease at start and release at clean exit.

### FR3: push-on-create (sub-PR 2)

`worktree-manager.sh feature <name>` MUST push the new branch to origin immediately after `git worktree add` and BEFORE returning to the operator. `draft-pr` becomes optional polish, not the only mechanism preventing branch wipe. Already prescribed by `2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md`; not yet shipped.

### FR4: structured-log path for headless hooks (sub-PR 3)

All Soleur hooks under `.claude/hooks/` MUST detect headless mode (`[[ ! -t 1 ]] && [[ -z "${CLAUDE_FOREGROUND:-}" ]]`) and route diagnostic output to `${GIT_COMMON_DIR}/soleur-logs/<session-id>-<hook>-<timestamp>.log` instead of stderr.

- `<session-id>` derived from `$PPID` per the 2026-03-17 PPID pattern, NOT from environment variables that may be absent under `/bg`.
- Hooks affected (CTO-named): `session-rules-loader.sh`, `skill-invocation-logger.sh`, `guardrails.sh`, `ship-unpushed-commits-gate.sh`, `pencil-open-guard.sh`, `worktree-write-guard.sh`, `pre-merge-rebase.sh`.
- Foreground sessions: no behavior change — `[[ -t 1 ]]` path remains primary.
- Log rotation: prune logs older than 14d in the SessionStart cleanup pass (also flock-protected per FR1).

### FR5: sidecar-loader file lock (sub-PR 4)

`session-rules-loader.sh` MUST flock the AGENTS.md sidecar payload write so concurrent change-class detection cannot interleave. Lock name: `sidecar-write`. Timeout 5s; on timeout fall back to all-sidecars (fail-closed, matching existing empty-diff behavior).

### FR6: concurrent-merge guard (sub-PR 4)

`.claude/hooks/pre-merge-rebase.sh` (or a new `pre-merge-lock.sh`) MUST acquire a `merge-main` lock before invoking `gh pr merge --auto`. Holds until merge completes or rejects. Prevents the 2026-03-20 duplicate-object-property class.

### FR7: SessionStart headless detection

`session-start.sh` (or equivalent in `wg-at-session-start-run-bash-plugins-soleur`) MUST detect when invoked under `claude --bg` (heuristics: no TTY + `CLAUDECODE` env present + parent process inspection) and short-circuit prompt-required gates that would otherwise stall a backgrounded session. Specifically: skip any path that calls `AskUserQuestion` or waits for operator input.

## Technical Requirements

- **TR1:** Bash 4+ (for `set -o errtrace` in lock cleanup traps). Verify against minimum supported Soleur shell version.
- **TR2:** `flock` available — assert at script entry. Soleur targets Linux + macOS; macOS lacks `flock` natively → bundle a polyfill via `util-linux` install instructions in dev-setup docs, or fall back to `mkdir`-based locks for macOS.
- **TR3:** All lock acquisitions instrumented with structured logs (FR4) for post-incident debugging.
- **TR4:** PPID inspection must use `ps -o ppid= -p <pid>` portably (avoid Linux-specific `/proc`).
- **TR5:** Lease file format = single-line JSON to make atomic-write trivial via `mv` semantics.
- **TR6:** No new external dependencies (Python, Node) — pure bash + standard utilities.
- **TR7:** Existing `[[ -t 1 ]]` gates remain; headless detection is additive, not replacement.

## Domain Review (carry-forward)

Carries forward from brainstorm 2026-05-12. CPO/CLO/CTO/CMO sign-offs at brainstorm time:

- **CTO:** Approved scope; recommended sub-PR breakdown (FR1; FR2+FR3; FR4; FR5+FR6+FR7).
- **CPO:** Approved on user-impact grounds (operator-data-loss = brand-survival). Cross-applicability to future cloud-side multi-session orchestrator is bonus.
- **CLO:** GREEN — no legal blockers.
- **CMO:** Silent-and-compatible mandate: no Agent View references in operator-facing surfaces during or after this work.

Plan skill: do NOT re-spawn domain leaders for this scope. Refresh per `wg-when-a-workflow-gap-causes-a-mistake-fix` only if scope materially changes (e.g., expansion to cloud-side orchestrator).

## Acceptance Criteria

- Running `claude --bg /soleur:one-shot <issue>` 3× concurrently from one operator terminal completes all 3 PRs with no shared-state corruption, no silent stall, no orphaned worktree, no orphaned draft PR. Verified manually + via a CI smoke that simulates 3 parallel SessionStart hooks.
- 2026-04-21 incident reproducer (if codified) no longer fails.
- All headless hook output captured in `${GIT_COMMON_DIR}/soleur-logs/`, parseable by an operator after `claude agents` attach.
- Foreground `/soleur:go` operator UX is byte-identical to pre-change (no new prompts, no new wait states).
- `flock` polyfill or skip-on-darwin path verified on macOS.
