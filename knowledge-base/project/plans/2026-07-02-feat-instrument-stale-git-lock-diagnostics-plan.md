---
title: "feat: Instrument stale-git-lock sweep with structured blind-surface diagnostics"
date: 2026-07-02
type: feature
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
related_prs: [5880, 5888]
related_adrs: [ADR-080]
related_learnings:
  - knowledge-base/project/learnings/workflow-patterns/2026-07-02-merged-is-not-deployed-on-concierge-instrument-dont-ask.md
---

# 🔧 feat: Instrument stale-git-lock sweep with structured blind-surface diagnostics

## Enhancement Summary

**Deepened on:** 2026-07-02
**Sections enhanced:** Overview, Implementation Phases, Observability, Acceptance Criteria, Sharp Edges, Test Scenarios
**Review agents used:** code-simplifier, silent-failure-hunter, observability-coverage-reviewer, bash-portability (Explore)

### Key improvements from deepen-plan
1. **Reframed from "instrument + type-aware destructive self-healing" to "instrument + report; auto-remove only the regular-file case."** A `config.lock` is always a regular file (git creates it via `open(O_CREAT|O_EXCL)`); the speculative `rm -rf`(dir)/`unlink`(symlink) branches were the sole source of the whole single-user-incident risk narrative and contradicted the plan's own Non-Goal. Non-regular/mount locks are now DETECTED + REPORTED loudly (`SOLEUR_GIT_LOCK_UNREMOVABLE`) and the sweep fails loud instead of marching into the doomed `git config` write — which fully satisfies the task's GOAL (self-report what the lock is) and its fail-loud requirement. **This diverges from the task's literal "directory → guarded rm -rf; symlink → unlink" instruction — flagged for operator review; see Research Reconciliation.**
2. **Corrected the emit stream: sentinels go to STDOUT, not stderr** (verified line 688 precedent — stderr is invisible to orchestrating agents under `claude --bg`, the exact blind-surface case).
3. **Corrected `findmnt` usage** — `findmnt -T <path>` exits 0 and prints the containing-fs SOURCE for *every* existing path (never `none`); mountpoint detection now uses `stat -c%m "$p" == realpath "$p"` (no hard `findmnt` dependency).
4. **Closed two `set -e` silent-abort traps**: (a) every `rm`/`stat`/mountpoint capture must be `if ! …; then` or `|| default` so an abort never pre-empts the loud sentinel; (b) `ensure_bare_config`'s non-zero return is now guarded at all 5 callers with caller-specific handling (session-start cleanup continues; create paths fail with a clear message).
5. **Closed the present-but-fresh blind spot** — DIAG emits whenever a config-write lock is *present*, not only when stale.
6. **Downgraded brand-survival threshold** `single-user incident` → `aggregate pattern` (the destructive op that justified single-user was cut; no new data-loss surface).

---

## Overview

`sweep_stale_git_locks()` (`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:135`) currently self-heals a stale `.git/config.lock` / `config.worktree.lock` **only when the lock is a regular file older than the age threshold**, and it emits nothing about *what the lock actually is*. If the lock is a directory, symlink, or bind-mount, the `[[ -f "$path" ]]` guard at `:151` silently `continue`s past it, and `ensure_bare_config()` (`:176`) marches into `git config --file "$shared_config" …` writes (`:194-215`) that fail `EEXIST` ("could not lock config file …: File exists") on **every** Concierge worktree-creation attempt — the #5880-class wedge, forever, with zero ground truth.

The Concierge agent-sandbox is a **blind execution surface** (you cannot run `ls`/`stat`/`findmnt` in it, and asking the operator to is a hard-rule violation — `hr-no-dashboard-eyeball-pull-data-yourself`, reproduce-bug `SKILL.md:34`), so the deployed sweep code IS the only diagnostic instrument. This plan makes the sweep **self-report the lock's true nature** into the sandbox's own **stdout** stream (grep-able by the orchestrating agent) via two plain sentinels, and makes the sweep **fail loud** (emit `SOLEUR_GIT_LOCK_UNREMOVABLE` and short-circuit, never proceeding into the doomed `git config` write) when a lock genuinely cannot be removed.

This is the exact instrumentation prescribed by the 2026-07-02 learning (Key Insight #2) and reproduce-bug `SKILL.md:34`. Goal: the next wedged `/soleur:go` session emits one structured line that decides the final targeted fix — zero operator action.

## Research Reconciliation — Spec vs. Codebase (Premise Validation)

| Premise (as cited) | Reality (verified) | Plan response |
|---|---|---|
| "the #4826 worktree-creation wedge" | `gh issue view 4826` → **OPEN**, title *"feat: nav-rail position resume…"* — a UI feature, **not** the git-lock wedge. | **Do NOT `Closes #4826`.** Use `Ref` only; flag the number for operator confirmation. Plan targets the config.lock wedge *class* documented by the learning + PR #5880/#5888 + ADR-080. |
| Task: "handle non-regular locks (directory → guarded rm -rf; symlink → unlink)" | A `config.lock` is created by git via `open(O_CREAT\|O_EXCL)` — **always a regular file**. dir/symlink/mount locks are hypothetical; building an auto-firing destructive `rm -rf` for them on a blind surface is speculative and is the entire brand-survival risk. | **Divergence (operator-reviewable):** DETECT + REPORT all types; auto-REMOVE only the regular-file case (existing behavior). Non-regular/mount → loud `SOLEUR_GIT_LOCK_UNREMOVABLE` + fail-loud (no doomed write). This satisfies the task GOAL (self-report the lock's nature) and the fail-loud requirement; destructive non-regular removal is deferred to the targeted fix the probe informs. Operator may override at /work to restore the literal `rm -rf`/`unlink`. |
| PR #5880 — stale-config.lock self-heal | Merged; introduced `sweep_stale_git_locks()` at `:135`. | Extend in place; preserve age-guard + clock-skew guard. |
| PR #5888 / ADR-080 — plugins-only merges now deploy | `ADR-080` present (Status *Adopting*); widened trigger denylist excludes only `plugins/soleur/docs/**` + `plugins/soleur/test/**`. | Edited file is `plugins/soleur/skills/…` → **not excluded** → a merge rebuilds+redeploys the image and re-seeds `/mnt/data/plugins/soleur`. Delivery path is live. |
| reproduce-bug blind-surface rule | `SKILL.md:34` explicitly names *"instrument `worktree-manager.sh` so the sweep self-reports the lock's true nature (type/stat/mount/`rm` errno)"*. | This plan is the literal realization of that rule. |
| Emit-stream precedent | `worktree-manager.sh:685-688`: `SOLEUR_FEATURE_PUSH_FAILED` is emitted to **stdout** because "warn-to-log-file (stderr) is otherwise invisible" under `claude --bg`. | Emit both new sentinels to **stdout** (plain, color-free). |

## User-Brand Impact

**If this lands broken, the user experiences:** their Concierge `/soleur:go` session stays wedged on worktree creation (status quo) — or, if the new fail-loud early-return is buggy, unrelated session-start maintenance (`cleanup_merged_worktrees`) aborts. No new data-loss vector: the only removal is the pre-existing age-guarded `rm -f` on a regular file.

**If this leaks, the user's workflow is exposed via:** N/A — git lock files carry no personal data.

**Brand-survival threshold:** `aggregate pattern`. The destructive `rm -rf`/`unlink` on a blind surface that would have made this single-user-incident was cut (see Enhancement Summary #1); the residual risk is a wedged or over-aborted session across the Concierge worktree-creation surface — an availability regression, not per-user data loss. `requires_cpo_signoff: false`. `user-impact-reviewer` is not required at this threshold; `silent-failure-hunter` review already ran at deepen-plan and its P0/P1 findings are folded below.

## Implementation Phases

### Phase 1 — Structured lock diagnostic (read-only probe, emitted for any PRESENT lock)

For each of `config.lock`, `config.worktree.lock`, **whenever the path exists** (present — regardless of age), compute and emit one grep-able line on **stdout**:

`SOLEUR_GIT_LOCK_DIAG file=<lock> type=<regular|dir|symlink|mount|missing> owner=<uid:gid> perms=<octal> mtime=<epoch> age=<seconds> mount=<source-or-none>`

- **type precedence (load-bearing):** `-L` (symlink) → mountpoint → `-d` (dir) → `-f` (regular) → `missing`. `-L` must be first (`-e`/`-f`/`-d` all dereference symlinks); mountpoint before `-d` (a mountpoint is also a dir).
- **mountpoint test (no findmnt dependency):** `rp=$(realpath -- "$p" 2>/dev/null) || rp=""; [[ -n "$rp" && "$(stat -c%m -- "$rp" 2>/dev/null)" == "$rp" ]]`. `stat -c%m` prints the file's mount root (GNU coreutils ≥ 8.6), consistent with the existing `stat -c%Y`/`stat -c%s` convention. `mount=` is the human-readable SOURCE **only when the path is itself a mountpoint** (`findmnt -n -o SOURCE -T "$p"` guarded by `command -v findmnt`, else `mount=findmnt-unavailable`); otherwise `mount=none`. Do NOT derive `mount=` from bare `findmnt -T` — it returns the containing-fs SOURCE + exit 0 for every existing path and never yields `none`.
- **owner/perms/mtime** via `stat -c '%u:%g' / %a / %Y`, each guarded on its own line: `owner=$(stat -c '%u:%g' -- "$p" 2>/dev/null) || owner=unknown` (the `||` disarms `set -e`).
- **age** only after a numeric guard: `age=unknown; [[ "$mtime" =~ ^[0-9]+$ ]] && age=$(( now - mtime ))` (a non-numeric `mtime` flowing into `$(( ))` aborts under `set -e`; an empty one silently computes 0 under `-u`).
- Emit **plain** (no `${YELLOW}…${NC}` around the token — color breaks grep; follow the stdout `SOLEUR_FEATURE_PUSH_FAILED` precedent at `:688`) to **stdout**.

### Phase 2 — Removal (regular-file only) + errno capture, all `set -e`-safe

For a lock that is **present AND stale** (age ≥ threshold; keep the existing clock-skew/future-date guard at `:154-157`):

- **`type=regular`** → remove via the existing `set -e`-safe form and count it:
  ```bash
  local rm_err="" rm_rc=0
  rm_err=$(rm -f -- "$path" 2>&1 >/dev/null) || rm_rc=$?   # 2>&1 >/dev/null order is load-bearing; -- stops opt parsing
  if (( rm_rc == 0 )); then swept=$(( swept + 1 ))          # assignment form, NOT ((swept++)) — see Sharp Edges
  else
    unremovable=1
    echo "SOLEUR_GIT_LOCK_UNREMOVABLE file=$lock type=regular errno=$(_rm_errno "$rm_err") reason=rm-failed hint=\"git config write will fail EEXIST — targeted fix needed\""
  fi
  ```
  `_rm_errno` maps GNU `rm` strerror text → label: `Device or resource busy`→`EBUSY`, `Operation not permitted`→`EPERM`, `Permission denied`→`EACCES`, `Read-only file system`→`EROFS`, else `OTHER`.
- **`type` ∈ {dir, symlink, mount}** (non-regular) → **do NOT remove** (reframe). Set `unremovable=1` and emit:
  `SOLEUR_GIT_LOCK_UNREMOVABLE file=<lock> type=<type> errno=none reason=non-regular-lock hint="observed non-regular config lock — targeted fix required; not auto-removed"`
  The Phase-1 `SOLEUR_GIT_LOCK_DIAG` line already carries the full forensic detail (owner/perms/mtime/mount) needed to design that fix.
- **fresh** (age < threshold): leave untouched (in-flight-writer safety) — the Phase-1 DIAG line was already emitted, so a perpetually-refreshed lock is still visible.

### Phase 3 — Fail-loud contract with `ensure_bare_config()` and its callers

- `sweep_stale_git_locks()` **returns non-zero** iff `unremovable=1` (a config-write lock remained present-and-unremovable). Returns 0 when locks were absent, fresh, or the regular one was removed. **Echo the `Swept N stale git lock file(s)` summary (`:163-165`) BEFORE any early return** so a partial sweep (one lock removed, the other stuck) still reports progress.
- `ensure_bare_config()` (`:187`): guard the sweep call — `if ! sweep_stale_git_locks "$git_dir"; then` emit one operator-visible line via `headless_or_stderr` naming the wedge, then **`return 1` WITHOUT** running the `git config --file "$shared_config" …` writes (`:194-215`). (The `if !` disarms `set -e`; the loud sweep sentinels already printed on stdout.)
- **Guard `ensure_bare_config`'s non-zero return at all 5 callers** (bare calls today, all would abort the whole script under `set -e`): `:506`, `:567`, `:589`, `:643`, `:942`. Per-caller behavior:
  - `cleanup_merged_worktrees :942` (session-start, defense-in-depth per `:941`): `if ! ensure_bare_config; then <loud one-liner>; fi` and **CONTINUE** — must NOT abort the unrelated maintenance that follows (orphan-dir cleanup, tmp reclamation, runaway-process kill, "Cleaned N" summary).
  - create/feature paths (`:506`, `:567`, `:589`, `:643`): `if ! ensure_bare_config; then` emit a clear "cannot create worktree — wedged on an unremovable git lock; see SOLEUR_GIT_LOCK_UNREMOVABLE above" and `exit 1` (creation genuinely cannot proceed; better a clear exit than a half-created worktree from a raw `set -e` abort).
- **Do NOT change** the scope decision (still only `config.lock` + `config.worktree.lock`; the `:141-148` rationale stands).

### Phase 4 — Tests

New `plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh` (bash `.test.sh`, picked up by `scripts/test-all.sh:188`; sources `test-helpers.sh` like `worktree-manager-bare-sync.test.sh`; fixtures synthesized per `cq-test-fixtures-synthesized-only`). Drives `sweep_stale_git_locks` / `ensure_bare_config` against a temp git_dir.

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  - `:135-166` `sweep_stale_git_locks()` — Phase-1 diagnostic (any present lock, stdout), Phase-2 regular-only removal + errno + non-regular UNREMOVABLE, `unremovable` return contract, summary-before-return, updated header comment. Add `_rm_errno()` + a mountpoint-test helper (or inline).
  - `:176-222` `ensure_bare_config()` — guard the sweep call (`if ! …`), emit fail-loud line, `return 1` before the config writes.
  - `:506`, `:567`, `:589`, `:643`, `:942` — guard each `ensure_bare_config` call with caller-appropriate handling (continue at `:942`; clear `exit 1` on create paths).

## Files to Create

- `plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh`

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_GIT_LOCK_DIAG line emitted on STDOUT from inside the sandbox whenever a config-write lock is PRESENT (any age); confirms the instrumented sweep is the running artifact"
  cadence: "on-demand — every worktree-create path (:506/:567/:589/:643) + every session-start cleanup_merged_worktrees run (:942)"
  alert_target: "none automated (blind surface) — the /soleur:go agent greps its own bash-tool stdout for the sentinel token"
  configured_in: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh sweep_stale_git_locks()"
error_reporting:
  destination: "worktree-manager.sh STDOUT → Concierge agent-sandbox bash-tool result / session transcript (the surface's own grep-able stream; stderr is invisible under claude --bg per :685-687). No Sentry SDK — bash plugin script, not the Next.js server."
  fail_loud: true   # SOLEUR_GIT_LOCK_UNREMOVABLE + guarded non-zero return short-circuits the doomed git config write
failure_modes:
  - mode: "lock present, regular, stale → removed"
    detection: "in-surface: grep 'SOLEUR_GIT_LOCK_DIAG .* type=regular' + 'Swept N' on the sweep's stdout"
    alert_route: "agent reads its own bash-tool stdout (blind surface, no external route)"
  - mode: "lock present, non-regular (dir/symlink/mount) → reported, not removed"
    detection: "in-surface: grep 'SOLEUR_GIT_LOCK_DIAG .* type=(dir|symlink|mount)' — one line discriminates ALL competing hypotheses (type+owner+perms+mtime+age+mount) in a single event; paired SOLEUR_GIT_LOCK_UNREMOVABLE reason=non-regular-lock"
    alert_route: "agent reads stdout"
  - mode: "lock present, regular, stale, rm failed (EBUSY/EPERM/EACCES/EROFS)"
    detection: "in-surface: grep 'SOLEUR_GIT_LOCK_UNREMOVABLE .* errno=' — carries errno label; absence of any subsequent EEXIST proves the short-circuit fired"
    alert_route: "agent reads stdout; loud line names the exact remaining targeted fix"
  - mode: "lock present but perpetually fresh (mtime keeps resetting)"
    detection: "in-surface: SOLEUR_GIT_LOCK_DIAG still emits (present, not stale) with age < threshold — the present-but-fresh wedge is visible; no removal attempted"
    alert_route: "agent reads stdout"
logs:
  where: "worktree-manager.sh stdout, captured in the Concierge agent-sandbox bash-tool result; OPTIONAL durable copy appended to <git_dir>/soleur-lock-diag.log on the mounted volume (no-SSH-retrievable by a later session if the emitting transcript is lost)"
  retention: "session-scoped (transcript); durable-log copy persists on the mount until manually pruned"
discoverability_test:
  command: "bash plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh"
  expected_output: "each lock-type case prints a SOLEUR_GIT_LOCK_DIAG line on stdout with the correct type=; the regular-stale case removes the lock, prints 'Swept 1', returns 0; the non-regular and rm-failed cases print SOLEUR_GIT_LOCK_UNREMOVABLE and the sweep returns non-zero; the present-but-fresh case emits DIAG with no removal and returns 0"
```

Blind-surface note (Phase 2.9.2): the probe is emitted **from** the sandbox on **stdout** (the stream the orchestrating agent actually greps — verified against the `:688` precedent), and its structured fields (`type`/`owner`/`perms`/`mtime`/`age`/`mount`/`errno`) discriminate every competing root-cause hypothesis — stale-regular vs directory vs symlink vs bind-mount vs foreign-uid vs busy vs present-but-fresh — in one event.

## Architecture Decision (ADR/C4)

**No new ADR; no C4 impact.** Extends the self-heal function whose incident lineage IS ADR-080; makes no ownership/tenancy/substrate/trust-boundary decision. C4 completeness check: no new external human actor, external system/vendor, container/data-store, or actor↔surface access-relationship (git-internal lock-file handling inside the already-modeled Concierge agent-sandbox). Skip is valid per Phase 2.10.

## Infrastructure (IaC)

**No new infrastructure.** Pure code change to an already-provisioned surface. **Delivery-path note:** the edited file lives under `plugins/soleur/skills/…`, which the ADR-080 denylist does **not** exclude, so a merge rebuilds the web-platform image and re-seeds `/mnt/data/plugins/soleur` — the fix reaches the Concierge host on the next deploy. AC12 confirms the running artifact carries the sentinel before declaring the instrument live. A merged fix is not a deployed fix.

## Domain Review

**Domains relevant:** engineering (infrastructure/tooling reliability + observability).

### Engineering (CTO)

**Status:** reviewed (deepen-plan agents). **Assessment:** infra/tooling reliability on a blind surface. Load-bearing concerns — (1) `set -e` discipline on every capture and every `ensure_bare_config` caller, (2) correct emit stream (stdout), (3) correct mountpoint detection — were surfaced by silent-failure-hunter (P0/P1), observability-coverage-reviewer (P1), and bash-portability research and are folded into the phases + Sharp Edges above.

### Product/UX Gate

**Not applicable.** No UI surface (no files under `components/**`, `app/**`, `*.tsx`, `.pen`); mechanical UI-surface override does not fire.

## GDPR / Compliance Gate

**Considered, N/A.** Surface touches only git-internal `.git/config.lock` files — zero personal-data processing, no schema/auth/API/`.sql` surface, no LLM-on-session-data. No `compliance-posture.md` write.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` — no open scope-out references `worktree-manager.sh` or the git-lock sweep.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — A **present, regular, stale** `config.lock` prints one `SOLEUR_GIT_LOCK_DIAG … type=regular …` line on **stdout**, is removed, prints `Swept 1`, and the sweep returns 0. (new `.test.sh`)
- [ ] AC2 — A **directory** `config.lock` prints `SOLEUR_GIT_LOCK_DIAG … type=dir …` and `SOLEUR_GIT_LOCK_UNREMOVABLE … reason=non-regular-lock`, is **NOT removed** (test asserts the dir still exists), and the sweep returns non-zero.
- [ ] AC3 — A **symlink** `config.lock` prints `type=symlink` + `SOLEUR_GIT_LOCK_UNREMOVABLE reason=non-regular-lock`, is **NOT removed** (link and its target both still exist), sweep returns non-zero.
- [ ] AC4 — A **regular stale lock whose `rm` fails** (read-only parent → EPERM) prints `SOLEUR_GIT_LOCK_UNREMOVABLE … errno=EPERM` and the sweep returns non-zero — and the loud line IS printed (no `set -e` abort before it).
- [ ] AC5 — `ensure_bare_config()` on an unremovable config-write lock emits the fail-loud line and **does not execute** the `git config --file "$shared_config"` writes (test asserts no shared-config mutation / no `EEXIST`), returning non-zero.
- [ ] AC6 — `cleanup_merged_worktrees` with an unremovable lock **continues** past `ensure_bare_config` (test asserts a later cleanup step still runs / the function does not exit non-zero from the guarded call).
- [ ] AC7 — A **present-but-fresh** lock (age < threshold) emits a `SOLEUR_GIT_LOCK_DIAG` line (present), is untouched, and the sweep returns 0.
- [ ] AC8 — A **future-dated** lock (mtime = now+3600) is preserved (clock-skew guard), sweep returns 0.
- [ ] AC9 — Every sentinel token appears on **stdout** with **no ANSI color codes** wrapping it — `grep -F 'SOLEUR_GIT_LOCK_'` on captured **stdout** (not stderr) matches.
- [ ] AC10 — `bash -n plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` passes; `shellcheck` reports no new errors; full `scripts/test-all.sh` bash-shard green (incl. the two pre-existing `worktree-manager-*.test.sh` — no regression).
- [ ] AC11 — PR body uses `Ref` (not `Closes`) for any issue link, flags that cited issue #4826 does not match this wedge, and flags the deliberate divergence from the literal "rm -rf/unlink non-regular" instruction (detect+report+fail-loud instead) for operator sign-off. `## Changelog` section present; `semver:patch`.

### Post-merge (operator/automated)

- [ ] AC12 — After the merge deploys (web-platform image rebuild per ADR-080), confirm the running artifact carries the sentinel: read the deployed `/mnt/data/plugins/soleur/…/worktree-manager.sh` (via the deploy path / next `/soleur:go` session output) and verify `SOLEUR_GIT_LOCK_DIAG` is present. Automatable via the deploy-status webhook / next-session grep — **no SSH**.

## Test Scenarios

Synthesized fixtures in a `mktemp -d` shaped as a git_dir; each drives `sweep_stale_git_locks "$dir" "$threshold"` (or `ensure_bare_config`), capturing **stdout**:

1. Present regular stale lock → removed, `type=regular`, `Swept 1`, rc 0.
2. Present regular fresh lock (age 0) → DIAG emitted, preserved, rc 0.
3. Future-dated lock (mtime now+3600) → preserved (clock-skew), rc 0.
4. Directory lock → `type=dir`, UNREMOVABLE reason=non-regular-lock, dir preserved, rc≠0.
5. Symlink lock → `type=symlink`, UNREMOVABLE, link + target preserved, rc≠0.
6. Regular stale lock, read-only parent → `SOLEUR_GIT_LOCK_UNREMOVABLE errno=EPERM`, rc≠0, loud line present (no pre-abort).
7. `ensure_bare_config()` integration: unremovable lock → no `git config` write, fail-loud line, rc≠0.
8. `cleanup_merged_worktrees`-style caller: unremovable lock → guarded call continues, later steps still run.

## Sharp Edges

- **`set -e` capture traps (P0, deepen-plan).** A bare `rm_rc=$?` after a failing `rm`, or `x=$(findmnt … 2>/dev/null)` where `findmnt` exits non-zero, aborts the shell **before** the loud sentinel prints — defeating the instrument on the exact unremovable case it exists for. Every `rm`/`stat`/mountpoint capture MUST be `if ! …; then` or `… || <default>`. `local x=$(cmd)` masks the exit status (`local` returns 0) — declare `local` on a separate line when you need `$?`.
- **`ensure_bare_config` non-zero return is unguarded at 5 callers (P1).** `:506/:567/:589/:643/:942` call it bare; under `set -e` a non-zero return aborts the whole script. At `cleanup_merged_worktrees :942` that silently kills unrelated session-start maintenance. Guard every caller; session-start CONTINUES, create paths `exit 1` with a clear message.
- **`findmnt -T` never yields "none" (P0 correction).** It exits 0 and prints the containing-fs SOURCE for every existing path. Use `stat -c%m "$p" == realpath "$p"` for mountpoint detection; use `findmnt` only for the SOURCE label once a path is confirmed a mountpoint.
- **Sentinels go to STDOUT, not stderr (P1).** stderr is invisible to orchestrating agents under `claude --bg` (`:685-687`); the working `SOLEUR_FEATURE_PUSH_FAILED` precedent (`:688`) emits to stdout. Color codes break grep — emit the token plain.
- **`[[ -f ]]` follows symlinks; `-d` is false under `-f`.** Type precedence MUST be `-L` → mountpoint → `-d` → `-f` → missing, or a symlink-to-regular is mislabeled `regular` and a dir/mountpoint is missed.
- **`swept=$(( swept + 1 ))`, never `(( swept++ ))`.** Post-increment yields the old value 0 → exit status 1 → `set -e` abort. Keep the assignment form (matches existing `:159`). Bare `(( age >= threshold ))` similarly aborts when false — keep it inside `if`.
- **Divergence from the literal task instruction.** The task said "directory → guarded rm -rf; symlink → unlink". This plan detects+reports+fails-loud instead of auto-removing non-regular locks (a config.lock is always a regular file; auto-`rm -rf` on a blind surface is the whole risk). Operator can override at /work to restore the literal destructive branches once a real non-regular lock is observed. Flagged in AC11.
- **Cited issue #4826 does not match** (nav-rail UI feature). Use `Ref`, not `Closes`; real lineage is PR #5880/#5888 + ADR-080 + the 2026-07-02 learning.
- **Delivery ≠ merge.** The instrument only helps once the image rebuilds and re-seeds the mount (ADR-080). The edited path is not in the denylist, so it deploys — AC12 still confirms the running artifact carries the sentinel.

## Non-Goals

- **Not** the final targeted fix for the wedge — this is the *instrument* that reveals what `config.lock` actually is so the final fix can be made.
- **Not** destructive auto-removal of non-regular locks (dir/symlink/mount) — deferred to the targeted fix the probe informs (see Divergence).
- **Not** widening the sweep scope to `index.lock`/`HEAD.lock`/per-worktree lock dirs — the `:141-148` rationale stands.
- **No** Sentry/Better Stack wiring — bash plugin script on the agent-sandbox; the stdout stream is the debug channel by design.
- **No** `flock`/mutex — the age-guard remains the parallel-safety mechanism.
