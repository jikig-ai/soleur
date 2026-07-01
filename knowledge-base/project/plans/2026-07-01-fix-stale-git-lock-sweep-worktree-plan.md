---
title: "fix: age-guarded stale git-lock sweep in worktree tooling (self-heal wedged Concierge workspaces)"
date: 2026-07-01
type: bug
branch: feat-one-shot-stale-git-lock-sweep
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix: age-guarded stale git-lock sweep in worktree tooling

## Enhancement Summary

**Deepened on:** 2026-07-01
**Passes run:** CTO engineering domain review; verify-the-negative + implementation-realism
(inline, single-file scope); empirical root-cause + anchor verification.

### Key confirmations (all verified live, not from memory)

1. **EEXIST wedge reproduced empirically.** In a scratch repo, planting a
   `.git/config.lock` then running `git config --file .git/config test.key val`
   yields `error: could not lock config file .git/config: File exists` (exit 255).
   This confirms both the root cause (a residual on-disk lock) and that removing the
   lock before the config write is the correct fix.
2. **All cited anchors verified at exact lines:** first config write is
   `worktree-manager.sh:144`; the clock-skew age-guard precedent is `:995`
   (`if (( _delta < 0 || _delta < 600 ))`); `stat -c%s` already used at `:1186`;
   `ensure_bare_config` defined at `:132`, called at `:452 / :513 / :535 / :589`
   (create paths) and `:888` (cleanup-merged / session-start). Single chokepoint
   confirmed.
3. **`set -e` hardening applied** to the code snippet (arithmetic nested in `if`,
   guarded `rm`/`stat`) per CTO — the real implementation risk for this fix.
4. **Scope boundary verified:** no bwrap-layer file
   (`agent-runner-sandbox-config.ts`, seccomp profile, SDK) appears in Files to
   Edit — only in Overview/Non-Goals as context.
5. **Test recipe portability verified:** `touch -d '120 seconds ago'` and
   `touch -d '+120 seconds'` both work on GNU (the target/CI/dev platform).

## Overview

Concierge worktree creation can be **permanently wedged** by a stale git lock file
left behind when a `git config` / `git worktree add` process is killed mid-write.
This is exactly what happened during the 2026-07-01 seccomp outage
([postmortem](../../engineering/operations/post-mortems/2026-07-01-concierge-bwrap-seccomp-sdk-0-3-outage-postmortem.md)):
every Bash/git call died on `unshare` EPERM, leaving a stale `config.lock` on the
mounted `/workspaces` volume. After git was restored, the stale lock **persists on
disk**, so every subsequent config write fails forever with
`could not lock config file .git/config: File exists` (EEXIST). Worktree creation
is the first config-writer in a session, so it is the first thing to break.

**Fix (scope = lock-sweep ONLY):** add an **age-guarded** sweep of stale git lock
files to `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`. The
sweep removes only locks **older than a small threshold** (default 60s) so a
legitimately in-flight sub-second config writer is never clobbered. Because the
sweep is wired into `ensure_bare_config()` — the chokepoint that runs before every
`git config` write on both the create path and the session-start `cleanup-merged`
path — an affected workspace **self-heals on the next Concierge session**, with no
operator SSH into the live volume required. The single chokepoint (rather than a
second explicit call in `cleanup_merged_worktrees`) is confirmed correct by CTO
domain review: `cleanup_merged_worktrees:888` already calls `ensure_bare_config`,
so the session-start path is covered transitively.

This is a pure bug fix on existing shell tooling. It makes **no** change to the
bwrap/tenant-isolation layer.

## Root Cause (confirmed, not the debug stream's guess)

- The Concierge agent-sandbox binds the **entire** workspace read-write
  (`allowWrite: [workspacePath]` in
  `apps/web-platform/server/agent-runner-sandbox-config.ts:213-221`) via bwrap
  `--bind`. `.git/config` lives inside that dir, so writes to it **are** permitted
  — the debug stream's "`.git/config` is bind-mounted, writes fail" theory is
  **wrong**.
- `File exists` (EEXIST) is git's signature for a **stale lock file**
  (`could not lock config file .git/config: File exists`), left when a
  `git config` / `git worktree add` process is killed mid-write.
- During the 2026-07-01 seccomp outage all git calls died on `unshare` EPERM,
  leaving a stale `.git/config.lock` on the mounted `/workspaces` volume. After git
  was restored, the stale lock persists on disk, so every subsequent config write
  fails forever.
- **Confirmed gap:** NO stale-git-lock cleanup exists anywhere. Grep of
  `worktree-manager.sh`, `.claude/hooks/`, `plugins/soleur/hooks/` returns zero
  matches for `config.lock` / `config.worktree.lock` / `index.lock` / `HEAD.lock`
  (only an unrelated `yarn.lock` string in `install_deps`).

## Research Reconciliation — Spec vs. Codebase

| Claim (from feature description) | Codebase reality (verified) | Plan response |
|---|---|---|
| Sweep in `ensure_bare_config()` (~lines 132-172) runs before every worktree create | `create_worktree:452`, `create_worktree:513`, `create_for_feature:535`, `create_for_feature:589` all call `ensure_bare_config` | Wire the sweep into `ensure_bare_config` right after `git_dir` is resolved, before the first `git config --file` write |
| Sweep in `cleanup-merged` path (session-start preamble) | `cleanup_merged_worktrees:888` calls `ensure_bare_config` | A single call site inside `ensure_bare_config` covers **both** required paths. See "Design Decision: single chokepoint" below |
| Handle both bare (`$GIT_ROOT/config.lock`) and non-bare (`$GIT_ROOT/.git/config.lock`) layouts | `ensure_bare_config:133-137` already resolves `git_dir` = `$GIT_ROOT/.git` (non-bare) or `$GIT_ROOT` (bare) | Pass the already-resolved `git_dir` into the sweep helper — no duplicated layout logic |
| New test auto-discovered | `scripts/test-all.sh:188` globs `plugins/soleur/skills/*/test/*.test.sh` | New file `plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh` is picked up automatically; no runner wiring needed |
| Scope boundary: do not touch bwrap layer | `feat-harden-agent-sandbox-5875` worktree is handling ADR-075 sandbox hardening in parallel | This plan touches **only** `worktree-manager.sh` + a new test file |

## User-Brand Impact

**If this lands broken, the user experiences:** a Concierge session whose very
first action — worktree creation — fails with `could not lock config file
.git/config: File exists`, permanently, for every subsequent session on that
workspace, until an operator manually SSHes into the live `/workspaces` volume and
deletes the lock. The tenant cannot do any work.

**If this leaks, the user's data is exposed via:** N/A — this change reads/removes
only git lock files under the workspace's own `.git` dir; it moves no user data and
opens no new read/write surface. (No leak vector.)

**Brand-survival threshold:** `single-user incident` — a single stale lock wedges
one tenant's workspace indefinitely, and a broken sweep (see Risks) could
theoretically `rm` a lock during an unusually-long-but-live config write on that
one tenant's volume. The **age-guard is the brand-survival brake**: it removes only
locks older than the threshold, so a normal sub-second config write (lock lifetime
in milliseconds) is never in scope. This threshold and the artifact/vector framing
are carried forward from the postmortem, which set
`brand_survival_threshold: single-user incident` for this exact surface.

> CPO sign-off required at plan time before `/work` begins. `user-impact-reviewer`
> will be invoked at review-time (handled by the review skill's conditional-agent
> block).

## Design Decisions

### Single chokepoint: sweep inside `ensure_bare_config()`

The feature brief asks for a sweep "in the cleanup-merged path AND in
`ensure_bare_config()`". These collapse to **one** call site because
`cleanup_merged_worktrees` (the session-start preamble path) already calls
`ensure_bare_config` at line 888, and every create path calls it at entry and after
`git worktree add`. Wiring the sweep into `ensure_bare_config` — immediately after
`git_dir` is resolved and **before** the first `git config --file` write — makes
the fix fire on both required paths with no duplication (KISS / DRY). The sweep
runs *before* the writes that would otherwise hit EEXIST, which is the whole point:
self-heal, then write. **CTO-resolved:** single chokepoint only — no second
explicit call in `cleanup_merged_worktrees` (it would be redundant since :888
already routes through `ensure_bare_config`). Note: the create paths call
`ensure_bare_config` *without* a lock while :888 calls it under `acquire_lock
cleanup-merged`; the sweep therefore runs both locked and unlocked, which is fine
because the **age-guard, not the flock, is the real safety mechanism**.

The sweep MUST land after `git_dir` is resolved (line 137) and before the **first**
config write, which is line 144 (`git config --file "$shared_config"
core.repositoryformatversion 1`) — not the `core.bare` logic. Line 144 is itself a
writer that hits the EEXIST wedge first, so the sweep must precede it.

### Age-guard via mtime comparison (not `find -mmin`)

Use an explicit `stat -c %Y` (mtime epoch) vs `date +%s` (now) comparison so the
threshold is expressed in **seconds** (60s), not `find -mmin`'s coarse whole-minute
granularity. This mirrors the existing clock-skew-guarded age check already in this
file at `cleanup_merged_worktrees:989-999` (which uses `date +%s` + a `git log
--format=%ct` mtime and treats a negative delta as "fresh"). A **future-dated lock
(negative age) is treated as fresh and never removed** — same clock-skew posture as
the existing code.

### Lock-file set (revised per CTO, then narrowed at review)

Sweep ONLY the config-write locks in the resolved common `git_dir`:
**`config.lock`, `config.worktree.lock`** — the confirmed EEXIST wedge that blocks
`ensure_bare_config`'s writes.

**`index.lock` / `HEAD.lock` dropped at review time (user-impact P2).** The CTO
pass had kept them "for completeness / near-inert." Review found they are worse than
inert on the **non-bare** path: when `ensure_bare_config` resolves
`git_dir="$GIT_ROOT/.git"`, `index.lock`/`HEAD.lock` are the **live working-tree
locks** a concurrent >60s `git commit`/`checkout`/`rebase` legitimately holds —
removing one mid-op tears that tenant's index. They also never block a `git config`
write, so they carried live-clobber risk with zero wedge-fix value. Dropping them
eliminates the race and the dead weight; the actual self-heal (config writes) is
unaffected. Test AC3b pins the exclusion (aged `index.lock`/`HEAD.lock` preserved).

**Do NOT** expand the sweep to per-worktree lock dirs (`.git/worktrees/*/index.lock`):
a *different* failure class (a wedged commit/checkout inside one worktree), unrelated
to the config-write wedge, with a larger blast radius. `packed-refs.lock` is **out** —
not the wedge class.

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  - **Add** a new function `sweep_stale_git_locks()` (near `ensure_bare_config`,
    ~line 124):

    ```bash
    # Remove stale git lock files left when a git process is killed mid-write
    # (e.g., the 2026-07-01 seccomp outage killed git under `unshare` EPERM,
    # leaving `.git/config.lock` on the mounted /workspaces volume; every later
    # `git config` write then fails EEXIST forever). Age-guarded: only removes
    # locks older than $threshold seconds so a legitimately in-flight sub-second
    # config writer is never clobbered. Clock-skew guard: a future-dated lock
    # (negative age) is treated as fresh and preserved, matching the existing
    # guard in cleanup_merged_worktrees. Idempotent; safe for parallel sessions.
    sweep_stale_git_locks() {
      local git_dir="$1"
      local threshold="${2:-60}"   # seconds
      [[ -d "$git_dir" ]] || return 0
      local now lock mtime age swept=0
      now=$(date +%s)
      for lock in config.lock config.worktree.lock; do  # config-write wedge only (index/HEAD dropped at review)
        local path="$git_dir/$lock"
        [[ -f "$path" ]] || continue
        mtime=$(stat -c%Y "$path" 2>/dev/null) || continue
        age=$(( now - mtime ))
        # Remove only stale (age >= threshold). Skips fresh AND future-dated
        # (age < 0, clock skew). Arithmetic nested in `if` so a false `(( ))`
        # returning exit 1 never trips `set -e` (mirrors :989-999).
        if (( age >= threshold )); then
          if rm -f "$path" 2>/dev/null; then
            swept=$((swept + 1))
          fi
        fi
      done
      if (( swept > 0 )); then
        echo -e "${YELLOW}Swept $swept stale git lock file(s) from $git_dir${NC}"
      fi
    }
    ```

  - **Call** the helper from `ensure_bare_config()` immediately after `git_dir` is
    resolved (after line 137, before the `git config --file "$shared_config"
    core.repositoryformatversion 1` write at line 144):

    ```bash
      # Self-heal: remove stale git locks BEFORE any config write, or the writes
      # below fail EEXIST forever (2026-07-01 outage class).
      sweep_stale_git_locks "$git_dir"
    ```

  - **No second call site** (CTO-resolved): do NOT add an explicit sweep to
    `cleanup_merged_worktrees` — it already routes through `ensure_bare_config` at
    :888, so a second call would be redundant.

## Files to Create

- `plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh` — source-based
  unit test (the script's `BASH_SOURCE`/`$0` guard at line 1490 explicitly supports
  sourcing without running `main`), plus one black-box integration assertion.
  Follows the structure of the sibling `create-from-origin-main.test.sh`.

## Test Scenarios

New test file `stale-lock-sweep.test.sh`:

1. **Setup** — stand up a bare repo + a linked worktree (mirrors the soleur bare
   layout, same pattern as `create-from-origin-main.test.sh`); `cd` into the
   worktree so the script's top-level init resolves `GIT_ROOT`/`IS_BARE`; `source`
   the script. Compute `git_dir` the same way `ensure_bare_config` does.
2. **AC1 — aged lock removed:** plant `config.lock` with mtime 120s in the past
   (`touch -d '120 seconds ago' "$git_dir/config.lock"`), call
   `sweep_stale_git_locks "$git_dir" 60`, assert the file is gone.
3. **AC2 — fresh lock preserved:** plant a fresh `config.worktree.lock` (`touch`),
   call the sweep, assert it still exists (age < 60s).
4. **AC3 — multiple patterns:** plant an aged `HEAD.lock` (removed) and a fresh
   `index.lock` (preserved) in the same run; assert both outcomes.
5. **AC4 — clock-skew guard:** plant a **future-dated** lock
   (`touch -d '+120 seconds' "$git_dir/config.lock"`), call the sweep, assert it is
   **preserved** (negative age treated as fresh).
6. **AC5 — self-heal wiring (black-box):** plant an aged `config.lock` in the
   bare git dir, run `bash "$WM" --yes cleanup-merged` (or a `create`) as a
   subprocess, assert the aged `config.lock` is gone afterward — proves the sweep
   actually fires through `ensure_bare_config` on the real session-start path.
7. **AC6 — no false wedge:** after a sweep with a fresh lock present, assert a real
   `git config --file "$git_dir/config" test.key val` still succeeds (sweep did not
   corrupt config).
8. **AC7 — no-op when no lock present (CTO):** call the sweep against a `git_dir`
   with no lock files; assert exit 0 and no error (guards against a `set -e` /
   glob-miss regression when the lock set is empty).

Standard results footer (`PASS`/`FAIL`, `exit 1` on any fail), matching the sibling
tests. Auto-discovered by `scripts/test-all.sh` via the
`plugins/soleur/skills/*/test/*.test.sh` glob.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `sweep_stale_git_locks()` exists in `worktree-manager.sh` and is called from
      `ensure_bare_config()` **before** the first `git config --file` write.
- [x] Sweep removes only locks with `age >= threshold` (default 60s); fresh and
      future-dated locks are preserved (verified by AC2/AC4).
- [x] Sweep operates on the `git_dir` resolved by the existing bare/non-bare logic
      (no duplicated layout computation).
- [x] New test `plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh`
      passes and is discovered by `bash scripts/test-all.sh`.
- [x] `bash -n plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
      passes (and `shellcheck` clean if available).
- [x] The three sibling tests
      (`create-from-origin-main`, `lease-protects-active`, `no-repo-fail-loud`)
      still pass (no regression to `ensure_bare_config`'s existing behavior).
- [x] No file outside `worktree-manager.sh` + the new test is modified (scope
      boundary: bwrap layer untouched).

## Observability

This is a shell tool that runs inside the Concierge sandbox — a blind execution
surface. Its observability model is the **session-start / debug-stream stdout** the
operator already pastes when a session strands (no Sentry/Better Stack path exists
for this surface; SSH is explicitly not required).

```yaml
liveness_signal:
  what: "`Swept N stale git lock file(s) from <git_dir>` line on stdout when the sweep removes a lock"
  cadence: "every worktree create + every session-start cleanup-merged"
  alert_target: "operator-visible in the /soleur:go debug stream (grep-able marker), same visibility model as SOLEUR_FEATURE_PUSH_FAILED"
  configured_in: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh (sweep_stale_git_locks echo)"
error_reporting:
  destination: "stdout/stderr in the session preamble output (the surface has no server-side telemetry path)"
  fail_loud: "rm failure is non-fatal by design (idempotent self-heal); a persisting wedge re-surfaces as the original EEXIST error on the next config write, which is itself the alert"
failure_modes:
  - mode: "aged lock NOT removed (threshold/mtime bug)"
    detection: "stale-lock-sweep.test.sh AC1/AC3 fail; in prod the original `could not lock config file .git/config: File exists` reappears in the debug stream"
    alert_route: "test suite (pre-merge) + operator-pasted debug stream (prod)"
  - mode: "fresh/live lock wrongly removed (age-guard bug)"
    detection: "stale-lock-sweep.test.sh AC2/AC4/AC6 fail"
    alert_route: "test suite (pre-merge)"
logs:
  where: "session-start preamble stdout captured in the Concierge debug stream"
  retention: "per-session (transcript)"
discoverability_test:
  command: "plant an aged config.lock, run `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes cleanup-merged`, then `test ! -f <git_dir>/config.lock` (NO ssh)"
  expected_output: "exit 0 — lock removed and `Swept 1 stale git lock file(s)` printed"
```

## Architecture Decision (ADR/C4)

**No architectural decision.** This is a bug fix on existing internal worktree
tooling — no ownership/tenancy boundary move, no new substrate/integration, no
resolver/dispatch/trust-boundary change, and it neither reverses nor extends any
ADR. A competent engineer reading the existing ADR corpus + C4 would not be misled
about the system after this ships. No C4 impact: the change introduces no external
human actor, no external system/vendor, no new data store, and no
actor↔surface access-relationship change (worktree-manager.sh is internal tooling
already within the modeled boundary). ADR/C4 gate: **skip**.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Complexity Small (hours); overall risk **Low**. CTO independently
verified every plan claim against the code:
- `ensure_bare_config:132-172` resolves `git_dir` for both bare/non-bare at
  :133-137; its **first** config write is :144 (`repositoryformatversion`), which is
  itself a writer that hits the EEXIST wedge — the sweep must land after :137 and
  before :144. Placement correct.
- Single call-site is correct — `cleanup_merged_worktrees:888` covers the
  session-start path transitively; a second call would be redundant. Create paths
  call `ensure_bare_config` unlocked, :888 calls it under `acquire_lock`; both are
  fine because the **age-guard, not the flock, is the safety mechanism**.
- 60s age-guard is sound; **no meaningful parallel-session race** — a live config
  write holds the lock for single-digit ms, so its mtime always reads fresh; the
  only way to clobber a live writer is a >60s config write, which does not occur.
  Keep `>= threshold` (strictly older), mirroring :995.
- **Scope to common `git_dir` config locks only** — `config.lock` /
  `config.worktree.lock` are load-bearing; `index.lock` / `HEAD.lock` don't block
  config writes and are near-inert in the common dir (kept only because the brief
  names them). Do NOT expand to per-worktree lock dirs (different failure class,
  larger blast radius).
- `stat -c %Y` is GNU-only but acceptable (Linux containers + CI ubuntu + existing
  GNU `stat -c%s` at :1186); add a one-line GNU-assumption comment.
- **`set -e` discipline is the real implementation risk**: `stat … 2>/dev/null ||
  continue`, `rm -f … 2>/dev/null` guarded by `if`, and nest the arithmetic
  comparison inside `if (( … ))` (a bare `(( expr ))` evaluating to 0 returns exit 1
  and aborts under `set -e` — the exact reason :995 nests it). Incorporated into the
  code snippet above.
- **No ADR required** — agreed; bugfix reusing an established in-repo pattern.
- Additional: log every removal (already in the snippet via the color echo) so the
  self-heal is not invisible in headless/CI logs; add a no-op-when-no-lock test case
  (added as AC7). No capability gaps — the `.test.sh` harness and discovery already
  exist.

### Product/UX Gate

Not applicable — no user-facing surface. No files under `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx`. Product tier: **NONE**.

## Alternatives Considered

| Approach | Why not |
|---|---|
| Separate SessionStart hook that sweeps locks | Extra moving part; `ensure_bare_config` is already the pre-write chokepoint on every relevant path. Keeping it in `worktree-manager.sh` avoids a new hook (per brief). |
| `find -mmin +1 -delete` | Coarse whole-minute granularity; can't express a clean 60s threshold and has no clock-skew guard. mtime comparison mirrors the existing in-file pattern. |
| Unconditional `rm -f config.lock` (no age guard) | Would clobber a legitimately in-flight concurrent config writer on a parallel Concierge session — the exact race the age-guard exists to prevent (brand-survival brake). |
| Fix in the bwrap/sandbox layer | Out of scope — sandbox hardening is `feat-harden-agent-sandbox-5875` (ADR-075). This plan stays out of those files to avoid collision. |

## Risks & Mitigations

### Precedent-diff (age-guarded cleanup pattern)

The age-guard is a lock/cleanup pattern with an established in-repo precedent —
`cleanup_merged_worktrees:989-999`. The new sweep mirrors it:

| Aspect | Precedent (`:989-999`, recent-commit skip) | New sweep (`sweep_stale_git_locks`) |
|---|---|---|
| Now source | `_now=$(date +%s)` | `now=$(date +%s)` |
| mtime source | `git log -1 --format=%ct HEAD` | `stat -c %Y "$path"` |
| Delta | `_delta=$(( _now - last_commit_age ))` | `age=$(( now - mtime ))` |
| Clock-skew guard | `if (( _delta < 0 || _delta < 600 ))` → skip | `if (( age >= threshold ))` → remove (skips fresh AND negative/future-dated) |
| set-e safety | arithmetic nested in `if` | arithmetic nested in `if` (same) |

The sweep is the **inverse polarity** of the precedent (precedent *skips* fresh
things; sweep *removes* stale things) but uses the identical now/mtime/delta/skew
machinery. Not a novel pattern.

### Other risks

| Risk | Mitigation |
|---|---|
| Clobbering a live concurrent config writer | Age-guard: a real `git config` write holds the lock for single-digit ms, so its mtime always reads fresh (< 60s) and is skipped. CTO: no meaningful parallel-session race. |
| `stat -c %Y` is GNU-only (BSD/macOS differ) | Acceptable — Concierge runs Linux containers, CI is ubuntu, dev is Linux; the file already depends on GNU `stat -c%s` at `:1186`. One-line comment notes the assumption. |
| Lock vanishes between `stat` and `rm` (racing sibling) | `stat … 2>/dev/null || continue` and `rm -f … 2>/dev/null` guarded by `if` — both non-fatal under `set -e`. |
| Empty lock set aborts under `set -e` | Fixed list + `[[ -f ]]` per-file guard (no glob); AC7 covers the no-lock no-op case. |

## Non-Goals

- No change to the bwrap sandbox, seccomp profile, or vendored SDK.
- No new SessionStart hook.
- No broad "git repair" logic — sweep is limited to the named stale lock files.
