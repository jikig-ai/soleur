---
title: "feat: Instrument stale-git-lock sweep with structured blind-surface diagnostics"
date: 2026-07-02
type: feature
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_prs: [5880, 5888]
related_adrs: [ADR-080]
related_learnings:
  - knowledge-base/project/learnings/workflow-patterns/2026-07-02-merged-is-not-deployed-on-concierge-instrument-dont-ask.md
---

# 🔧 feat: Instrument stale-git-lock sweep with structured blind-surface diagnostics

## Overview

`sweep_stale_git_locks()` (`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:135`) currently self-heals a stale `.git/config.lock` / `config.worktree.lock` **only when the lock is a regular file older than the age threshold**, and it emits nothing about *what the lock actually is*. If the lock is a directory, a symlink, a bind-mount, or is owned by another uid / held busy, the `[[ -f "$path" ]]` guard at line 151 silently `continue`s past it, and `ensure_bare_config()` (`:176`) then marches straight into `git config --file "$shared_config" …` writes (`:194-215`) that fail `EEXIST` ("could not lock config file …: File exists") on **every** Concierge worktree-creation attempt — the #5880-class wedge, forever, with zero ground truth.

Because the Concierge agent-sandbox is a **blind execution surface** (you cannot run `ls`/`stat`/`findmnt` in it, and asking the operator to is a hard-rule violation — `hr-no-dashboard-eyeball-pull-data-yourself`, reproduce-bug `SKILL.md:34`), the deployed sweep code IS the only diagnostic instrument. This plan makes the sweep **self-report the lock's true nature** into the sandbox's own stderr/session stream via two grep-able sentinels, and makes the sweep **handle non-regular locks** and **fail loud** (never proceed into the doomed `git config` write) when a lock genuinely cannot be removed.

This is the exact instrumentation prescribed by the 2026-07-02 learning (Key Insight #2) and reproduce-bug `SKILL.md:34`. Goal: the next wedged `/soleur:go` session emits one structured line that decides the final targeted fix — zero operator action.

## Research Reconciliation — Spec vs. Codebase (Premise Validation)

Checked every reference the task cites. One premise is **stale**; the rest hold and strongly corroborate the plan.

| Premise (as cited) | Reality (verified) | Plan response |
|---|---|---|
| "the #4826 worktree-creation wedge" | `gh issue view 4826` → **OPEN**, title *"feat: nav-rail position resume…"* — a UI feature, **not** the git-lock wedge. | **Do NOT `Closes #4826`.** Use `Ref` only, and flag the number for operator confirmation. The plan targets the config.lock wedge *class* documented by the learning + PR #5880/#5888 + ADR-080, not issue #4826. See Sharp Edges. |
| PR #5880 — stale-config.lock self-heal | Merged; introduced `sweep_stale_git_locks()`. The function this plan extends. Confirmed present at `:135`. | Extend in place; preserve age-guard + clock-skew guard semantics. |
| PR #5888 / ADR-080 — plugins-only merges now deploy | `ADR-080` present, Status *Adopting*; widened `web-platform-release.yml` `on.push.paths` + `reusable-release.yml` `check_changed` to a runtime-plugin denylist that **excludes only `plugins/soleur/docs/**` + `plugins/soleur/test/**`**. | The edited file is `plugins/soleur/skills/…` → **not excluded** → a merge rebuilds+redeploys the image and re-seeds `/mnt/data/plugins/soleur`. Delivery path is live. See Infrastructure (IaC). |
| reproduce-bug blind-surface rule | `SKILL.md:34` explicitly names *"instrument `worktree-manager.sh` so the sweep self-reports the lock's true nature (type/stat/mount/`rm` errno)"*. | This plan is the literal realization of that rule. |
| Learning `2026-07-02-merged-is-not-deployed-…` | Present at `knowledge-base/project/learnings/workflow-patterns/`. Key Insight #2 = instrument, don't ask. | Drives the whole design. |

## User-Brand Impact

**If this lands broken, the user experiences:** their Concierge `/soleur:go` session stays wedged on worktree creation (status quo) **or**, worse, a path-construction bug in the new `rm -rf` (non-regular-lock branch) silently deletes real git data inside `.git/` on the user's mounted `/workspaces` volume.

**If this leaks, the user's workflow is exposed via:** N/A for data leakage — git lock files carry no personal data. The exposure axis here is **destructive filesystem action on a blind, auto-running surface**, not a data leak.

**Brand-survival threshold:** `single-user incident`. Rationale: the new capability adds a destructive `rm -rf`/`unlink` on a path, executed automatically on every worktree-create and every session-start `cleanup_merged_worktrees` run, on a surface no human eyeballs before it acts. A single mis-constructed path would be a per-user data-loss incident. This is the same threshold at which ADR-080 (this incident's lineage) was decided. `requires_cpo_signoff: true` — CPO ack required at plan time; `user-impact-reviewer` + `data-integrity-guardian` run at review (destructive-op + guard correctness).

## Implementation Phases

### Phase 1 — Structured lock diagnostic (read-only probe)

Add a helper `_git_lock_diag()` that, given a lock path, computes and emits one grep-able line **before** any removal attempt:

`SOLEUR_GIT_LOCK_DIAG file=<lock> type=<regular|dir|symlink|mount|missing> owner=<uid:gid> perms=<octal> mtime=<epoch> age=<seconds> mount=<findmnt-source-or-none>`

- **type** via test operators, evaluated in this precedence so a symlink is never misread as its target: `-L` (symlink) → `findmnt -T "$path"` target-match (mount) → `-d` (dir) → `-f` (regular) → else `missing`. Do NOT rely on `[[ -f ]]` alone (`-f` follows symlinks and is false for dirs).
- **owner/perms/mtime** via `stat -c '%u:%g' / %a / %Y` (GNU `stat`, mirrors the existing `stat -c%Y` at `:152` and `stat -c%s` convention noted at `:132`). Each `stat` guarded `|| …=unknown` so a race (lock vanished) never trips `set -euo pipefail`.
- **mount** via `findmnt -n -o SOURCE -T "$path" 2>/dev/null` (bounded, no network); `none` when not a mountpoint. Guard for `findmnt` absence (`command -v findmnt`) → emit `mount=findmnt-unavailable` rather than failing.
- Emit as a **plain** line (no `${YELLOW}…${NC}` color wrapping around the sentinel token — color codes break `grep`; follow the existing plain `SOLEUR_FEATURE_PUSH_FAILED` sentinel at `:688`) to **stderr**.

### Phase 2 — Type-aware removal + errno capture

Rework the `for lock in config.lock config.worktree.lock` loop (`:149-162`) so that, for a lock that is **present AND stale** (age ≥ threshold, keeping the existing clock-skew/future-date guard at `:154-157`):

1. Emit the Phase-1 `SOLEUR_GIT_LOCK_DIAG` line (before-state).
2. Remove according to type, capturing exit code + stderr text:
   - **regular** → `rm -f "$path"` (unchanged behavior).
   - **symlink** → `rm -f "$path"` (removes the link itself, never the target — but branch explicitly for the diagnostic label; do NOT `-f` a path you resolved through the link).
   - **dir** → **guarded** `rm -rf "$path"` behind ALL of: `$path` non-empty, `basename "$path"` ∈ {`config.lock`,`config.worktree.lock`}, `$path` is under `$git_dir` (prefix check on the realpath of `$git_dir`), age ≥ threshold, and `findmnt` says `$path` is **not** a mountpoint. If any guard fails → treat as unremovable (step 4).
   - **mount** → never `rm`; treat as unremovable (step 4).
3. Capture: `rm_rc=$?` and `rm_err="$(… 2>&1 >/dev/null)"`; derive a coarse `errno` label from `rm_err` (`EBUSY` ⇐ "busy", `EPERM`/`EACCES` ⇐ "permitted"/"denied", else `OTHER`). Emit an **after** line: `SOLEUR_GIT_LOCK_DIAG … rm_rc=<n> rm_errno=<label> rm_err="<text>"`.
4. **Unremovable** (rc≠0, or a guard blocked removal, or type=mount): emit the loud sentinel and signal the caller:
   `SOLEUR_GIT_LOCK_UNREMOVABLE file=<lock> type=<type> errno=<label> reason="<busy|perm|mount|guard-blocked>" hint="git config write will fail EEXIST — targeted fix needed"`
   Set a function-level flag `unremovable=1`.

### Phase 3 — Fail-loud contract with `ensure_bare_config()`

- `sweep_stale_git_locks()` **returns non-zero** iff a *config-write* lock (`config.lock`/`config.worktree.lock`) remained unremovable after the sweep. It still returns 0 when locks were absent, fresh (age < threshold — legitimately in-flight), or successfully removed.
- `ensure_bare_config()` (`:187`) calls it under `set -euo pipefail`, so the call MUST be guarded: change `sweep_stale_git_locks "$git_dir"` → `if ! sweep_stale_git_locks "$git_dir"; then` … emit a single `SOLEUR_GIT_LOCK_UNREMOVABLE`-aware operator-visible line (via `headless_or_stderr`) explaining the session is wedged on an unremovable lock, then `return 1` **without** running the doomed `git config --file "$shared_config" …` writes at `:194-215`. Failing loud + early beats an obscure `EEXIST` from git.
- Preserve the existing `Swept N stale git lock file(s)` summary (`:163-165`) for the happy path.
- **Do NOT change** the scope decision (still only `config.lock` + `config.worktree.lock`, never `index.lock`/`HEAD.lock`/per-worktree lock dirs — the rationale at `:141-148` stands).

### Phase 4 — Tests

New `plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh` (bash `.test.sh`, picked up by `scripts/test-all.sh:188` glob; sources `test-helpers.sh` like the sibling `worktree-manager-bare-sync.test.sh`). Drives `sweep_stale_git_locks` directly against a temp `.git`-shaped dir with a fabricated (synthesized, per `cq-test-fixtures-synthesized-only`) lock of each type.

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  - `:135-166` `sweep_stale_git_locks()` — add `_git_lock_diag()` helper (or inline), type-aware removal, errno capture, sentinel emission, unremovable return contract, updated function header comment.
  - `:176-222` `ensure_bare_config()` — guard the sweep call (`if ! …`), emit the fail-loud line, `return 1` before the config writes on unremovable.

## Files to Create

- `plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh`

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_GIT_LOCK_DIAG line emitted from inside the sandbox whenever a config-write lock is present (present-and-removed or present-and-stuck); confirms the instrumented sweep is the running artifact"
  cadence: "on-demand — every worktree-create path (:506/:567/:589/:643/:942) + every session-start cleanup_merged_worktrees run"
  alert_target: "none automated (blind surface) — the /soleur:go agent greps the session stderr stream for the sentinel token"
  configured_in: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh sweep_stale_git_locks()"
error_reporting:
  destination: "worktree-manager.sh stderr → Concierge agent-sandbox session transcript / debug stream (the surface's own stream — no Sentry SDK in a bash plugin script)"
  fail_loud: true   # SOLEUR_GIT_LOCK_UNREMOVABLE + non-zero return short-circuits the doomed git config write
failure_modes:
  - mode: "lock present, regular, stale → removed"
    detection: "in-surface: grep 'SOLEUR_GIT_LOCK_DIAG .* type=regular .* rm_rc=0' in the session stream"
    alert_route: "agent reads session stream (blind surface, no external route)"
  - mode: "lock present, non-regular (dir/symlink/mount)"
    detection: "in-surface: grep 'SOLEUR_GIT_LOCK_DIAG .* type=(dir|symlink|mount)' — one line discriminates ALL competing hypotheses (type+owner+perms+mtime+age+mount) in a single event"
    alert_route: "agent reads session stream"
  - mode: "lock genuinely unremovable (EBUSY/EPERM/mount/guard-blocked) → git config write skipped"
    detection: "in-surface: grep 'SOLEUR_GIT_LOCK_UNREMOVABLE' — carries errno + reason; absence of any subsequent EEXIST proves the short-circuit fired"
    alert_route: "agent reads session stream; loud line names the exact remaining targeted fix"
logs:
  where: "worktree-manager.sh stderr, captured in the Concierge agent-sandbox session transcript"
  retention: "session-scoped"
discoverability_test:
  command: "bash plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh"
  expected_output: "each lock-type case prints a SOLEUR_GIT_LOCK_DIAG line with the correct type=; the mount/perm/dir-guard-blocked cases print SOLEUR_GIT_LOCK_UNREMOVABLE and the sweep returns non-zero; the regular-stale case removes the lock and returns 0"
```

Blind-surface note (Phase 2.9.2): the probe is emitted **from** the sandbox (in-surface), not host-side, and its structured fields (`type`/`owner`/`perms`/`mtime`/`age`/`mount`/`rm_rc`/`rm_errno`) discriminate every competing root-cause hypothesis — stale-regular vs directory vs symlink vs bind-mount vs foreign-uid vs busy — in one event. That is the whole point: one line decides the final fix.

## Architecture Decision (ADR/C4)

**No new ADR; no C4 impact.** This extends the self-heal function whose incident lineage IS ADR-080; it makes no ownership/tenancy/substrate/trust-boundary decision. Test: would an engineer reading the existing ADRs + C4 be *misled* about the system after this ships? No — it is a diagnostic + destructive-op hardening on an existing internal shell surface. C4 completeness check: the change introduces **no** external human actor, external system/vendor, container/data-store, or actor↔surface access-relationship (it is git-internal lock-file handling inside the already-modeled Concierge agent-sandbox). Skip is valid per Phase 2.10.

## Infrastructure (IaC)

**No new infrastructure.** Pure code change to an already-provisioned surface. **Delivery-path note (load-bearing, per the learning + ADR-080):** the edited file lives under `plugins/soleur/skills/…`, which the ADR-080 denylist does **not** exclude, so a merge to `main` rebuilds the web-platform image and re-seeds `/mnt/data/plugins/soleur` — the fix reaches the Concierge host on the next deploy, not by coincidence. Post-merge verification (below) confirms the running artifact contains the sentinel before declaring the instrument live. A merged fix is not a deployed fix.

## Domain Review

**Domains relevant:** engineering (infrastructure/tooling reliability + observability).

### Engineering (CTO)

**Status:** carry-forward (pipeline). **Assessment:** infra/tooling reliability change on a blind execution surface; the load-bearing concerns are (1) `rm -rf` guard correctness on an auto-running path and (2) `set -euo pipefail` interaction with the new non-zero return contract. Both are captured in Sharp Edges + the review-time agents. Full CTO/architecture-strategist depth deferred to deepen-plan Phase 4.4 (precedent-diff vs the existing age-guard) and review.

### Product/UX Gate

**Not applicable.** No UI surface — the mechanical UI-surface override does not fire (no files under `components/**`, `app/**`, `*.tsx`, `.pen`). No `## Domain Review` Product subsection needed.

## GDPR / Compliance Gate

**Considered, N/A.** Trigger (b) (single-user-incident threshold) fires the *consideration*, but the surface touches only git-internal `.git/config.lock` files — zero personal-data processing, no schema/auth/API/`.sql` surface, no LLM-on-session-data. No `compliance-posture.md` write. Advisory skip with rationale recorded.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` — no open scope-out references `worktree-manager.sh` or the git-lock sweep.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — For a **regular, stale** `config.lock`, the sweep prints exactly one `SOLEUR_GIT_LOCK_DIAG … type=regular …` line, removes the lock, prints an after-line with `rm_rc=0`, and returns 0. (asserted by the new `.test.sh`)
- [ ] AC2 — For a **directory** named `config.lock` inside the temp git_dir (guards satisfiable), the diag line shows `type=dir` and the guarded `rm -rf` removes it (`rm_rc=0`), returns 0.
- [ ] AC3 — For a **symlink** `config.lock`, the diag line shows `type=symlink`; `rm -f` removes the **link** and the symlink *target file remains on disk* (test asserts target still exists), returns 0.
- [ ] AC4 — For an **unremovable** lock (simulated via a read-only parent dir → `EPERM`, or a dir-guard-blocked case), the sweep prints `SOLEUR_GIT_LOCK_UNREMOVABLE … errno=…` and **returns non-zero**.
- [ ] AC5 — `ensure_bare_config()` on an unremovable config-write lock emits the fail-loud line and **does not execute** the `git config --file "$shared_config"` writes (test asserts no `config` file mutation / no `EEXIST`), returning early.
- [ ] AC6 — A **fresh** (age < threshold) lock is **untouched**, emits **no** `SOLEUR_GIT_LOCK_DIAG` removal attempt (or emits a diag with no removal), and the sweep returns 0 (in-flight-writer safety preserved).
- [ ] AC7 — Every emitted sentinel token (`SOLEUR_GIT_LOCK_DIAG`, `SOLEUR_GIT_LOCK_UNREMOVABLE`) appears with **no ANSI color codes wrapping the token** — `grep -F 'SOLEUR_GIT_LOCK_'` on captured output matches (grep-ability on the blind surface).
- [ ] AC8 — `bash -n plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` passes; `shellcheck` (if available in CI) reports no new errors; full `scripts/test-all.sh` bash-shard green (including the two pre-existing `worktree-manager-*.test.sh` — no regression).
- [ ] AC9 — PR body uses `Ref` (not `Closes`) for any issue link, and flags that cited issue #4826 does not match this wedge (operator to confirm the correct tracking issue).

### Post-merge (operator/automated)

- [ ] AC10 — After the merge deploys (web-platform image rebuild per ADR-080), confirm the running artifact contains the sentinel: read the deployed `/mnt/data/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (via the deploy path / next `/soleur:go` session output) and verify `SOLEUR_GIT_LOCK_DIAG` is present. Automatable via the deploy-status webhook / next-session grep — **no SSH**.

## Test Scenarios

Synthesized fixtures in a `mktemp -d` shaped as a git_dir; each drives `sweep_stale_git_locks "$dir" "$threshold"` (source the script or extract the function):

1. Regular stale lock → removed, `type=regular`, rc 0.
2. Directory lock (guards ok) → guarded `rm -rf`, `type=dir`, rc 0.
3. Symlink lock → link removed, target preserved, `type=symlink`, rc 0.
4. Fresh regular lock (age 0) → preserved, rc 0.
5. Future-dated lock (mtime = now+3600) → preserved (clock-skew guard), rc 0.
6. Unremovable (read-only parent → EPERM) → `SOLEUR_GIT_LOCK_UNREMOVABLE`, rc≠0.
7. `ensure_bare_config()` integration: unremovable lock → no `git config` write, fail-loud line, early return.

## Sharp Edges

- **`set -euo pipefail` × non-zero return (Phase 3).** The script is `set -euo pipefail` (`:16`). A bare `sweep_stale_git_locks "$git_dir"` that returns non-zero would abort the whole script and **skip the loud message**. The caller MUST use `if ! sweep_stale_git_locks …; then` (disarms `set -e` for that call) so the fail-loud line and early `return 1` execute deterministically.
- **`[[ -f ]]` follows symlinks; `-d` is false for dirs-under-`-f`.** Type detection MUST branch `-L` (symlink) **before** `-f`, and `-d` before `-f`, or a symlink-to-regular-file is mislabeled `regular` and a directory is skipped entirely. Precedence: symlink → mount → dir → regular → missing.
- **`rm -rf` guard is brand-survival-load-bearing.** The directory branch runs `rm -rf` on a blind, auto-firing surface. ALL guards (non-empty path, exact basename allowlist, realpath-prefix-under-`$git_dir`, age ≥ threshold, not-a-mountpoint) must hold before `rm -rf`; any guard failure routes to the unremovable/loud path, never to `rm`. A path-construction bug here is a single-user data-loss incident.
- **Color codes break grep.** Sentinel tokens must be emitted plain (no `${YELLOW}…${NC}` around them). Non-sentinel human prose may keep color. Follow the existing plain `SOLEUR_FEATURE_PUSH_FAILED` at `:688`.
- **`findmnt` may be absent** in a minimal sandbox. Guard `command -v findmnt`; emit `mount=findmnt-unavailable` and fall through to `type=dir/regular` detection rather than failing — never let a missing tool wedge the sweep.
- **`errno` from bash is a string heuristic.** `rm` prints a message, not a numeric errno; the `EBUSY`/`EPERM`/`OTHER` label is derived from the stderr text and is best-effort for grouping, not a syscall-exact code. Document this in the field so the reader doesn't over-trust it.
- **Cited issue #4826 does not match** — it is a nav-rail UI feature, not the git-lock wedge. Use `Ref`, not `Closes`; the real lineage is PR #5880/#5888 + ADR-080 + the 2026-07-02 learning. Operator should confirm/point the correct tracking issue at ship.
- **Delivery ≠ merge.** The instrument only helps once the web-platform image rebuilds and re-seeds the mount (ADR-080). The edited path is not in the denylist, so it deploys — but AC10 must still confirm the running artifact carries the sentinel before the fix is declared live.

## Non-Goals

- **Not** the final targeted fix for the wedge — this is the *instrument* that will reveal what `config.lock` actually is so the final fix can be made. (If Phase-2 handling already removes the real-world lock, that is a bonus, not the goal.)
- **Not** widening the sweep scope to `index.lock`/`HEAD.lock`/per-worktree lock dirs — the `:141-148` scope rationale stands (live-clobber risk, zero wedge-fix value).
- **No** Sentry/Better Stack wiring — this is a bash plugin script on the agent-sandbox; the session stream is the debug channel by design (blind-surface instrumentation).
- **No** `flock`/mutex — the age-guard remains the parallel-safety mechanism (`:128-134`).
