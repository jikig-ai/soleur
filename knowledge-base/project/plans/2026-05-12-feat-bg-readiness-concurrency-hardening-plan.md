---
title: Full /bg-readiness — Soleur concurrency hardening for parallel CC sessions
date: 2026-05-12
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 3690
pr: 3689
branch: feat-cc-agent-view-integration
worktree: .worktrees/feat-cc-agent-view-integration/
brainstorm: knowledge-base/project/brainstorms/2026-05-12-cc-agent-view-integration-brainstorm.md
spec: knowledge-base/project/specs/feat-cc-agent-view-integration/spec.md
sub_prs: 3
plan_review_applied: 2026-05-12 (DHH + Kieran + code-simplicity + spec-flow; full trim)
status: plan-draft
---

# Plan: Full /bg-readiness — Soleur concurrency hardening for parallel Claude Code sessions

## Overview

Pay the 2026-04-21 unpaid concurrency bill so Soleur's worktree + SessionStart-hook model is multi-writer-safe under N parallel CC sessions, including Anthropic's newly-shipped Agent View (`claude --bg`, `claude agents`). 3 sequential sub-commits in this worktree (PR #3689) shipping ~400 LOC including tests. `/bg` and Agent View become safe side-effects.

This plan was trimmed after multi-agent review (DHH + Kieran + code-simplicity + spec-flow-analyzer) flagged the initial draft as over-built. The trim cuts: speculative `lib/session-lock.sh` + `lib/session-lease.sh` separation, JSON lease format, heartbeat helper, 3-value headless enum, macOS polyfill, AGENTS.md sidecar mid-edit race (FR5 — premise unproven against the codebase's actual atomic-rename edit pattern), and the structured-log subsystem (over-built for 6 lost stderr lines). Net result is sharper-mapped to the 2026-04-21 evidence with fewer surfaces to forget.

## User-Brand Impact

**Carry-forward from brainstorm `## User-Brand Impact` (2026-05-12).**

**If this lands broken, the user experiences:** A concurrent SessionStart hook (or workflow-gate `cleanup-merged`) from a sibling CC session reaps the operator's active worktree mid-flight, wiping committed-but-unpushed local commits and orphaning the draft PR. Recovery requires `git reflog` spelunking on a deleted directory.

**If this leaks, the user's workflow is exposed via:** Multi-session corruption is internal — no cross-tenant exposure. Operator-data-loss scope only.

**Brand-survival threshold:** `single-user incident`. One operator losing committed work is a brand-survival event for a dev-tools product. The 2026-04-21 incident already happened once in foreground; making `/bg` recommended without hardening converts a rare race into a routine failure mode.

`requires_cpo_signoff: true`. Brainstorm-time CPO sign-off carries forward — see Domain Review. `user-impact-reviewer` will be invoked at PR-review time.

## Research Reconciliation — Spec vs. Codebase

Spec inherited CTO's brainstorm-time claims verbatim. Plan-time audit reconciled them; multi-agent review further trimmed.

| Spec / CTO claim | Codebase reality | Plan response |
|------------------|------------------|---------------|
| `git fetch --prune` race at `worktree-manager.sh:741` | Confirmed; no flock today. | Sub-PR 1: `acquire_lock fetch-prune 30` wrapping. |
| `cleanup_merged_worktrees` sibling-wipe (reap at `worktree-manager.sh:839-846`); only dirty-status safety guard | Confirmed. Active-worktree check at `:795` matches `$PWD` only — invisible to sibling processes. | Sub-PR 1: `acquire_lock cleanup-merged 30` + lease check + 10-min recent-commit grace + abs() clock-skew guard. |
| AGENTS.md sidecar contention | FALSE PREMISE per Kieran review. Manifests are per-session-id; sidecar reads use atomic-rename semantics from `Edit` tool. No torn-read race exists in current code. | **Dropped (FR5).** Re-introduce only if a non-atomic AGENTS.md writer is later identified. |
| `pre-merge-rebase.sh` concurrent-merge collisions | REFRAMED. The hook is a PreToolUse INTERCEPTOR; does not call `gh pr merge --auto`. Actual `--auto` invocations live in `/soleur:{schedule, product-roadmap, ship, merge-pr}`. | Sub-PR 3: `acquire_lock merge-main 600` in the 4 skill SKILL.md callers; `acquire_lock rebase-main 60` in the hook for its rebase step. |
| FR4 "every hook gates verbose on `[[ -t 1 ]]`; 12-file restructure" | FALSE. Only `worktree-manager.sh:737` uses `[[ -t 1 ]]`. All other hooks emit decisions via stdout JSON envelope (visible in `/bg`). **6 stderr sites lost in headless**, across 3 files: `pre-merge-rebase.sh` (4 sites: lines 110, 137, 147, 153) + `lib/log-rotation.sh:159` + `lib/incidents.sh:236`. | Sub-PR 2: 3-line inline `headless_or_stderr` helper, applied at the 6 sites. No new lib file. |
| `claude --bg` matcher / env distinguisher | NOT DOCUMENTED in Anthropic CC hooks reference. Best inference: `matcher: startup` fires. No env var distinguishes. | Sub-PR 3: boolean `HEADLESS_MODE` via `[[ ! -t 0 ]] && [[ -n "${CLAUDECODE:-}" ]]`. **3-value enum (`peek` vs `bg`) dropped** per Simplicity review — no consumer reads `HEADLESS_KIND`. Add when needed. |
| Canonical flock idiom | Confirmed. `( flock -w 5 -x 9; ...; ) 9>>"$file"` is used in `lib/log-rotation.sh`, `lib/incidents.sh`, `skill-invocation-logger.sh`, `agent-token-tee.sh`. | Plan adopts verbatim; cleanest reference `agent-token-tee.sh:160-170`. |
| PPID-scoped state-file pattern | Confirmed at `plugins/soleur/hooks/stop-hook.sh:32-57` (PID-named files + `kill -0` liveness + mtime TTL). | Plan adopts verbatim into `lib/session-state.sh`. |
| macOS `flock` portability | Keg-only via `brew install util-linux`; path-resolution fragile. NFS unreliable. | **Polyfill dropped** per Simplicity #7 + Kieran P0 #7. Hard-fail with clear error if `command -v flock` absent. Add polyfill the day a darwin operator files an issue. |
| `worktree-manager.sh feature` is the right seam for lease acquisition | Kieran P0 #3 + Simplicity #3: yes. All 5 worktree-creating skills go through `feature`. Lease in one place > 5 places. | Plan acquires lease in `worktree-manager.sh feature`. Skills set `SOLEUR_SKILL_NAME` env once before calling — no per-skill lease-acquire boilerplate. |

**Trim summary:**

- 4 sub-PRs → 3 sub-PRs
- 4 new lib files → 1 new lib file (`lib/session-state.sh`)
- ~800 LOC → ~400 LOC
- FR5 dropped (premise unproven)
- 5 SKILL.md lease edits → 1-line env var + worktree-manager seam

## Implementation Phases (3 sub-commits in PR #3689)

Each sub-commit is independently reviewable. They ship as one PR (#3689) because each later commit consumes the prior's library API. Per Sharp Edge `2026-05-07-foundations-pr-must-not-declare-downstream-contracts`: sub-PR 1 ships lib + wiring in the same commit (not foundations-PR pattern — atomic delivery of contract + consumer); sub-PRs 2-3 only consume existing API.

### Sub-PR 1 — Lock + lease + grace + push-on-create (the 2026-04-21 fix)

**Goal:** Close the 2026-04-21 incident class. Foreground UX byte-identical.

**Files to create:**

- `.claude/hooks/lib/session-state.sh` (~180 LOC) — combined lock + lease module.
  - **Lock API:**
    - `acquire_lock <name> [timeout_s=30]` — opens fd 9 against `${LOCK_DIR}/${name}.lock`, calls `flock -w <timeout> -x 9`. Returns 0 on acquire, 99 on timeout (consistent with `agent-token-tee.sh:161-167` exit-99 convention).
    - `release_lock <name>` — closes fd 9.
    - `acquire_lock_shared <name> [timeout_s=30]` — `flock -w <timeout> -s 9` shared variant for read-side serialization (used by sub-PR 3 sidecar reads if re-introduced; included now for completeness).
    - **Hard-fail behavior** if `command -v flock` returns false: emit clear error "Soleur requires `flock` (util-linux). On macOS: `brew install util-linux` and add `$(brew --prefix util-linux)/sbin` to PATH." Exit 99. No polyfill in v1.
  - **Lease API:**
    - `acquire_lease <worktree-name> <skill-name> <expected-duration-min>` — atomic-write key=value lease at `${LEASE_DIR}/<worktree-name>.lease`. Format:
      ```
      pid=12345
      ppid=12000
      skill=one-shot
      started_at=2026-05-12T16:30:00Z
      expected_duration_min=240
      hostname=jean-laptop
      ```
      Atomic-write via `mktemp + mv` (rename atomic on same filesystem). No `jq` dependency.
    - `release_lease <worktree-name>` — reads lease; if `pid` matches `$$` AND `started_at` matches the value at acquire-time AND `hostname` matches `$HOSTNAME`, removes the file. Otherwise no-op (per Guido Flohr: never delete someone else's pidfile).
    - `is_lease_active <worktree-name>` — reads lease, returns 0 (active) iff: (a) PID alive (`kill -0 "$pid"`), (b) hostname matches (`$HOSTNAME == $lease_hostname`), (c) age < max(`expected_duration_min * 60`, 14400) seconds (4h floor). Else returns 1.
    - `sweep_orphan_leases` — globs `${LEASE_DIR}/*.lease`, removes any whose PID is dead OR age > 86400s (24h). Idempotent; called lazily at `worktree-manager.sh feature` entry.
  - **Trap helper:**
    - `_register_lease_release_trap <worktree-name>` — sets `trap '_lease_release_safe <worktree-name>' EXIT INT TERM HUP`. The `_lease_release_safe` body is unset-variable-safe (`set +u` scope) per Kieran P0 #7.
  - **Path resolution:**
    - `LOCK_DIR="$(git rev-parse --git-common-dir 2>/dev/null)/soleur-locks"` (canonicalized via `cd -P + pwd -P` per existing idiom).
    - `LEASE_DIR="$(git rev-parse --git-common-dir 2>/dev/null)/soleur-leases"`.
    - Both `mkdir -p` at module load.
  - **Headless visibility helper (extracted for reuse in sub-PR 2):**
    - `headless_or_stderr <level> <msg>` — if `[[ ! -t 2 ]] && [[ -n "${CLAUDECODE:-}" ]]`, append a single line to `${LOG_DIR}/${PPID}.log` (`${LOG_DIR}="$(git rev-parse --git-common-dir)/soleur-logs"`); else `echo "[$level] $msg" >&2`. Line format: `[ISO-TS] [level] [hook] msg`. POSIX-atomic append for lines under 4KB.
  - **Kill switch:** `SOLEUR_DISABLE_SESSION_STATE=1` short-circuits all functions to no-ops (per existing idiom `SOLEUR_DISABLE_*`).
- `.claude/hooks/lib/session-state.test.sh` (~150 LOC) — bats-style if available, plain bash assertions otherwise. Tests:
  - **T1:** Three parallel `acquire_lock test 5` invocations against same name; assert exactly one acquires at any time (verify via timestamp file: each acquirer writes `$(date +%s%N)` to a counter file under lock; assert the 3 timestamps are monotonically ordered with no overlap, accepting that wall-clock granularity may allow same-nanosecond timestamps).
  - **T2:** `acquire_lock` returns 99 within `timeout_s + 1` when contended (deterministic — uses a held lock from a background sleep).
  - **T3:** Lease roundtrip — acquire, file exists with key=value format, release, file gone.
  - **T4:** `is_lease_active` returns 1 for dead PID (use `kill $bg_pid && wait $bg_pid` to deterministically reap before checking).
  - **T5:** Orphan sweep removes 25h-mtime lease (use `touch -d "25 hours ago"`), preserves 1h-mtime lease.
  - **T6:** Hard-fail when `flock` missing — temporarily shadow `flock` with `PATH=/empty/dir bash -c 'source lib/session-state.sh; acquire_lock x'`; assert exit 99 + clear error message.
  - **T7:** Multi-signal trap — start a subshell that acquires lease, send `SIGTERM` to it, assert lease file gone within 2s.
  - **T8:** `headless_or_stderr` — TTY-absent + `CLAUDECODE=1` writes to `LOG_DIR`; TTY-present echoes to stderr.

**Files to edit:**

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  - Source `lib/session-state.sh` near top.
  - **`feature` subcommand** (after `git worktree add` succeeds, before exit):
    - Call `sweep_orphan_leases` (lazy cleanup).
    - `acquire_lease "$branch" "${SOLEUR_SKILL_NAME:-unknown}" "${SOLEUR_EXPECTED_DURATION_MIN:-240}"`.
    - **Immediately** `git push -u origin "$branch"` (refuse to return without remote durability). On push failure (no network), warn via `headless_or_stderr warn "push failed: $err"` but continue — the lease still protects the worktree locally.
    - Print "Worktree leased; release on session exit." instruction so the operator knows.
  - **`cleanup_merged_worktrees` function** (line 731 onward):
    - `acquire_lock cleanup-merged 30 || { headless_or_stderr warn "cleanup-merged lock contended; skipping"; return 0; }` — emit visible skip per SpecFlow finding #7.
    - `trap 'release_lock cleanup-merged' RETURN` (function-scope, not EXIT, to avoid clobbering outer EXIT).
    - Wrap `git fetch --prune` at `~:741` in nested `acquire_lock fetch-prune 30` (separate lock — allows cleanup-merged work to proceed in parallel for non-fetch operations).
    - In the reap loop (~`:839-846`), insert lease-check + grace-check **before** the existing dirty-status guard:
      ```bash
      if [[ -n "$worktree_path" ]] && is_lease_active "$(basename "$worktree_path")"; then
        [[ "$verbose" == "true" ]] && echo "(skip) $branch - active lease"
        continue
      fi
      if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
        local last_commit_age
        last_commit_age=$(git -C "$worktree_path" log -1 --format=%ct HEAD 2>/dev/null)
        if [[ -n "$last_commit_age" ]]; then
          local delta=$(( $(date +%s) - last_commit_age ))
          # Clock-skew guard (SpecFlow #9): negative delta = future-dated commit; treat as fresh
          if (( delta < 0 || delta < 600 )); then
            [[ "$verbose" == "true" ]] && echo "(skip) $branch - recent commit (<10min) or clock-skew"
            continue
          fi
        fi
      fi
      ```
- `plugins/soleur/skills/one-shot/SKILL.md`
  - Add at the bash-invocation step that calls `worktree-manager.sh feature`:
    ```bash
    SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240 \
      ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>
    ```
  - Add a Phase Exit "Release lease" step: `bash .claude/hooks/lib/session-state.sh release_lease "$(basename $PWD)"`. (Multi-signal trap covers abnormal exit; this is the clean-exit path.)
- `plugins/soleur/skills/brainstorm/SKILL.md`, `work/SKILL.md`, `plan/SKILL.md`, `drain-labeled-backlog/SKILL.md`
  - Same env-var + Phase Exit pattern. Brainstorm: `EXPECTED_DURATION_MIN=60` (typical). Plan: `60`. Work: `240`. Drain: `480`.

**Acceptance criteria — Pre-merge (PR):**

- [ ] `bash .claude/hooks/lib/session-state.test.sh` — all 8 tests green.
- [ ] **2026-04-21 reproducer** at `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh`: create worktree A with `worktree-manager.sh feature`, acquire lease, simulate merge by adding A's branch to `--merged main` output (mock via test-only `MOCK_MERGED_BRANCHES` env), invoke `cleanup_merged_worktrees` from a subshell, assert A's worktree directory still exists after the call returns.
- [ ] `worktree-manager.sh feature <name>` calls `git ls-remote origin <branch>` after creation and verifies non-empty output before returning successfully.
- [ ] Foreground `/soleur:one-shot` operator UX: capture stdout+stderr trace (not `set -x` — Kieran P1 #6) with `command 2>&1 | tee /tmp/trace`; diff against a recorded `pre-change-trace.txt` baseline. Tolerated diffs: timestamp lines, ANSI color codes. Substantive diff = failure.
- [ ] `command -v flock || true` returns non-empty on the CI Linux runner.
- [ ] PR commit message lists `Ref #3690` (single-PR-with-3-units; final `Closes #3690` is on sub-PR 3's commit body).

**Acceptance criteria — Post-merge:** none for sub-PR 1 in isolation. End-to-end smoke deferred to sub-PR 3.

### Sub-PR 2 — Headless stderr capture for the 6 lost emission sites

**Goal:** Make the 6 stderr emissions visible under `/bg` without building a structured-log subsystem. Reuses `headless_or_stderr` from sub-PR 1.

**Files to edit:**

- `.claude/hooks/pre-merge-rebase.sh` — replace 4 `>&2` warns at lines 110, 137, 147, 153 with `headless_or_stderr warn "<message>"`. Source `lib/session-state.sh` at top.
- `.claude/hooks/lib/log-rotation.sh` — line 159's stderr emission → `headless_or_stderr warn "..."`.
- `.claude/hooks/lib/incidents.sh` — line 236's marker warn → `headless_or_stderr warn "..."`.

**Acceptance criteria — Pre-merge (PR):**

- [ ] `bash .claude/hooks/pre-merge-rebase.test.sh` (existing test) passes after refactor.
- [ ] Headless reproducer: invoke `pre-merge-rebase.sh` with `</dev/null > /tmp/stdout 2> /tmp/stderr` AND `CLAUDECODE=1` set; assert `/tmp/stderr` empty AND `${GIT_COMMON_DIR}/soleur-logs/${PPID}.log` contains a `pre-merge-rebase warn` line.
- [ ] Foreground reproducer: invoke same script with `CLAUDECODE=1` but TTY present (`script -q -c '...' /dev/null`); assert stderr non-empty AND log file unchanged.
- [ ] Each emitted log line is a single line (POSIX-atomic append for <4KB).
- [ ] `Ref #3690`.

**Acceptance criteria — Post-merge:** none.

### Sub-PR 3 — Skill-side merge-main lock + SessionStart headless boolean

**Goal:** Close the 4 concurrent `gh pr merge --auto` collision callers; install boolean `HEADLESS_MODE` env for downstream consumers; emit final smoke verification.

**Files to edit:**

- `plugins/soleur/skills/schedule/SKILL.md` — wrap `gh pr merge --auto` invocation in:
  ```bash
  bash .claude/hooks/lib/session-state.sh acquire_lock merge-main 600 || { echo "merge-main lock contended; will retry"; sleep 30; }
  gh pr merge --auto ...
  bash .claude/hooks/lib/session-state.sh release_lock merge-main
  ```
- `plugins/soleur/skills/product-roadmap/SKILL.md` — same.
- `plugins/soleur/skills/ship/SKILL.md` — same.
- `plugins/soleur/skills/merge-pr/SKILL.md` — same.
- `.claude/hooks/pre-merge-rebase.sh` — wrap the `git rebase origin/main` step (find the exact line with `git rebase` and add `acquire_lock rebase-main 60` around it).
- `.claude/hooks/session-rules-loader.sh` — at top (after `set -e` block, before sidecar reads), add:
  ```bash
  # Boolean headless detection. 3-value enum (peek vs bg) dropped per simplicity review;
  # re-introduce if a consumer needs to distinguish.
  if [[ ! -t 0 ]] && [[ -n "${CLAUDECODE:-}" ]]; then
    export HEADLESS_MODE=1
  else
    export HEADLESS_MODE=0
  fi
  ```

**Acceptance criteria — Pre-merge (PR):**

- [ ] Concurrent `/soleur:ship` reproducer at `plugins/soleur/test/concurrent-ship.test.sh`: spawn 2 background subshells each invoking the skill's merge-main lock block; assert the timestamps of `gh pr merge --auto` invocation are at least 1s apart (proxy for serialization).
- [ ] `HEADLESS_MODE` classification: invoke `session-rules-loader.sh` with `</dev/null` + `CLAUDECODE=1`; assert env `HEADLESS_MODE=1`. Invoke with TTY + `CLAUDECODE=1`; assert `HEADLESS_MODE=0`.
- [ ] PR commit body: `Closes #3690`.

**Acceptance criteria — Post-merge (operator):**

- [ ] **Production smoke:** `claude --bg /soleur:one-shot <small-test-issue>` 3× in parallel from one terminal. All 3 sessions complete with distinct PRs. No orphaned worktrees (verify via `git worktree list` post-smoke = original count). No silent stalls (verify via `${GIT_COMMON_DIR}/soleur-logs/` tail).
- [ ] Capture a screen recording or terminal log of the smoke for the issue.
- [ ] After smoke success, post a comment on #3690 with the 3-PR URLs and `gh issue close 3690 --comment "smoke verified"`.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Marketing

Brainstorm carry-forward (per `## Domain Assessments` in `2026-05-12-cc-agent-view-integration-brainstorm.md`):

### Engineering (CTO)

**Status:** carried-forward (no respawn).
**Assessment:** Approved scope. Plan-time audit reconciled 2 of CTO's 4 named failure modes (sidecar contention, pre-merge-rebase site) — both reframings reduce or redirect scope, do not expand it. The reframed plan is **smaller** than CTO's brainstorm-time framing.

### Product (CPO)

**Status:** carried-forward (no respawn). Satisfies `requires_cpo_signoff: true`.
**Assessment:** Approved on operator-data-loss = brand-survival grounds. Cross-applicability to future cloud-side multi-session orchestrator is bonus.

### Legal (CLO)

**Status:** carried-forward (no respawn).
**Assessment:** GREEN. No legal blockers.

### Marketing (CMO)

**Status:** carried-forward (no respawn).
**Assessment:** Silent-and-compatible — confirmed. This plan adds zero Agent View references to operator-facing surfaces.

**Brainstorm-recommended specialists:** none.
**Skipped specialists:** none.

### Product/UX Gate

**Tier:** NONE. Zero `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in the create/edit list. Pure infrastructure tooling.

## GDPR / Compliance Gate

**Status:** SKIPPED with rationale (unchanged from prior draft).

Canonical regex (schemas, migrations, auth, API routes, `.sql`) does not match. Trigger (b) — `brand_survival_threshold: single-user incident` — fires in principle but the plan's actual content is bash file-locking primitives on local-filesystem state in `${GIT_COMMON_DIR}/`. No GDPR regulated-data surface. The deferred cloud-UX audit (#3691) MUST re-trigger the gate if it extends multi-session state cloud-side.

## Risks

1. **`flock` missing on macOS dev hosts.** Hard-fail at module load with clear install instructions (`brew install util-linux`). No polyfill in v1. Re-evaluate when a darwin operator files an issue. Trade-off: explicit failure beats silent split-brain via mkdir-polyfill orphans.
2. **PID reuse after process death.** Mitigated by `hostname + started_at` verification in `is_lease_active` (Kleppmann lease-not-fence model). Documented hazard.
3. **NFS attribute caching breaks mtime-based 24h orphan sweep.** Soleur is not documented to run on NFS; 24h window is well above documented NFS attribute cache delays (~30-60s).
4. **3 sub-commits ship as one PR; intermediate-commit state could have a partial-defense window.** Mitigated by: PR is a single review-merge event. The branch state mid-review may have partial coverage, but no merge to main occurs until all 3 commits are in.
5. **Lease release not called on abnormal exit (SIGKILL, OOM, host reboot).** Mitigated by: multi-signal trap (`EXIT INT TERM HUP`) catches everything except SIGKILL + reboot. For those, the 24h orphan sweep is the safety net; the dirty-status + recent-commit grace already protect against reaping a worktree with operator-visible state. Residual risk: a 24-25h-old SIGKILLed lease against a worktree with no uncommitted state and no recent commits gets reaped — but in that window the operator had >24h to notice the session was gone and re-attach via Agent View if it's their session.
6. **Heartbeat absent — long >4h skill runs are protected by `expected_duration_min` floor of 4h.** Operators passing higher values (e.g., overnight drains at `SOLEUR_EXPECTED_DURATION_MIN=720`) get the higher floor. The lease's effective TTL is `max(expected_duration_min, 240) * 60` seconds + 24h orphan safety. Re-introduce heartbeat the first time a multi-day skill exists.
7. **`HEADLESS_MODE=1` misclassification.** Fail-closed direction: misclassify foreground → bg means `headless_or_stderr` writes to file instead of stderr. Operator misses warning. Trade-off accepted — visible-in-file beats silent-discard, and the inverse (misclassify bg → foreground) means stderr is lost as it already is today. Sub-PR 2's tests cover both directions.

## Sharp Edges Applied

- **Paraphrase-without-verification (2026-04-22):** Spec/CTO claims reconciled in Research Reconciliation table. 2 of 4 named failure modes reframed.
- **Plan phase order load-bearing (2026-05-10):** Sub-PR 1 ships lib + wiring in one commit (contract-changing + consumer atomic, not foundations-PR pattern). Sub-PRs 2, 3 consume the API.
- **Foundations PR must not declare downstream contracts (2026-05-07):** N/A — atomic delivery, not foundations split.
- **3-value enum gate drift (2026-05-12):** Explicitly REJECTED 3-value enum for headless detection (no consumer reads `peek` vs `bg`). Boolean only. If a future consumer needs distinction, the union-widening rules apply at that point.
- **flock subshell variable scope (Soleur Sharp Edges):** All flock subshells in this plan write to fd 9 via `9>>` redirection but do NOT reassign caller-visible variables. Where needed, temp file + `read` outside the subshell (per established `agent-token-tee.sh` pattern).
- **Plan-time parsing pattern needs codebase precedent (2026-05-12):** Lease key=value parsing uses `grep '^pid=' "$lease_file" | cut -d= -f2` — simple, no awk gsub needed for non-quoted values. Lane-extraction from spec.md (in tasks.md generator) uses canonical `awk gsub` form from `skill-security-scan/scripts/run-scan.sh:34`.
- **Cap coupling between adjacent PRs (2026-05-06):** All timeouts explicit constants in `lib/session-state.sh`: cleanup-merged 30s, fetch-prune 30s, merge-main 600s, rebase-main 60s. Grep-able by name.
- **Plan precondition asserts X accessible at scope Y (2026-05-12):** `GIT_COMMON_DIR` verified accessible from worktree via `git rev-parse --git-common-dir` (returns the bare-repo `.git`).
- **Plan AC external state must be API-verified (2026-05-09):** Smoke AC verifies `git worktree list` count and `${GIT_COMMON_DIR}/soleur-logs/` content via direct `ls`/`stat`, not via assumed env vars.
- **Trace callgraph from entrypoint when placing guards (2026-05-05):** Lease acquisition placed at `worktree-manager.sh feature` (entry point for all 5 worktree-creating skills) rather than per-skill. Trace verified: `/soleur:{one-shot, drain, brainstorm, work, plan}` → `worktree-manager.sh feature <name>` → lease acquire.
- **AC test determinism (Kieran P1 #6):** AC tests use deterministic primitives (`kill $bg_pid && wait`, `touch -d "25 hours ago"`, mock env vars) — no wall-clock timing assertions except where flock semantics inherently require them. Where present, generous timeout multiples (e.g., 5s flock, assert completion within 10s).
- **`trap EXIT` reliability (Kieran P0 #7):** Multi-signal trap `EXIT INT TERM HUP` (4 signals). `_lease_release_safe` body uses `set +u` scope to avoid unset-var swallow. Documented SIGKILL gap; covered by orphan-sweep.
- **Lock-skip visibility (SpecFlow #7):** Every `acquire_lock ... || ...` block emits a `headless_or_stderr warn` skip notice. No silent contention.
- **Plan AC region-replacement (2026-05-12):** N/A — no region-replacement edits.
- **Wrapper-vs-curl check:** No third-party actions. Plain bash + `flock` + `git`.
- **CLI verification gate:** All CLI invocations verified against existing repo usage. See "CLI verification gate" section below.

## CLI verification gate

- `flock -w 5 -x 9` — verified against `agent-token-tee.sh:161`, `log-rotation.sh:73,120`. `flock -w N -s 9` shared variant — verified via `man flock(1)`.
- `git rev-parse --git-common-dir` — verified manually from this worktree; returns `/home/jean/git-repositories/jikig-ai/soleur/.git`.
- `kill -0 <pid>` — verified via `man kill(1)` and `stop-hook.sh:44`.
- `mktemp + mv` atomic-rename — POSIX-guaranteed for same-filesystem renames.
- `git push -u origin <branch>` — verified against existing usage in `worktree-manager.sh:1088`.
- `git log -1 --format=%ct HEAD` — verified via `man git-log(1)`. Returns Unix epoch seconds.
- `touch -d "25 hours ago" <file>` — verified via `man touch(1)`. GNU coreutils form; works on Linux. macOS `touch -d` differs; tests run on Linux CI.

## Open Code-Review Overlap

**None.** Queried 75 open `code-review`-labeled issues for paths matching `worktree-manager.sh`, `session-rules-loader`, `cleanup_merged`, `.claude/hooks/lib/`, `flock`. Zero overlap.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-12-cc-agent-view-integration-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-cc-agent-view-integration/spec.md`
- Issue: #3690
- Draft PR: #3689
- Deferred cloud-UX audit: #3691
- Seed incident: `knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md`
- PPID precedent: `plugins/soleur/hooks/stop-hook.sh:32-57`
- Canonical flock idiom: `.claude/hooks/agent-token-tee.sh:160-170`
- Plan review consensus (2026-05-12): DHH + Kieran + code-simplicity + spec-flow-analyzer; recommended full trim. Applied.

## Reviewer notes

- 3 commits to this worktree map 1:1 to 3 review-units in PR #3689. Reviewers should review each commit independently.
- Initial plan (4 sub-PRs, ~800 LOC) was trimmed to 3 sub-commits (~400 LOC) after multi-agent review. Dropped: FR5 (premise unproven), 3-value headless enum (YAGNI), macOS polyfill (no darwin runner), JSON+heartbeat lease (YAGNI), separate lib files (collapsed into `lib/session-state.sh`), per-skill lease boilerplate (moved to `worktree-manager.sh feature` seam).
- Deferred cloud-UX audit (#3691) and rejected marketing thread (no issue) are NOT in scope for this PR.
