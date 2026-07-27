# Tasks — #7004 tmpfs ownership-keyed scratch-root reclamation

Derived from `knowledge-base/project/plans/2026-07-27-feat-tmpfs-ownership-keyed-scratch-root-reclamation-plan.md`
(post-review). Three PRs; **PR 0 ships first and alone**.

Legend: `[ ]` todo · `AC#` maps to the plan's Acceptance Criteria.

---

## PR 0 — Alarm rebaseline (independent, ~40 lines)

The guard alarms every 5 minutes **today**, before any of this. The reaper neither causes nor
worsens it, so this is separable and has the highest immediate operator value.

- [ ] 0.1 In `scripts/tmpfs-guard.sh`, count only entries **not** matching `soleur-run.*`.
- [ ] 0.2 Persist a watermark beside the heartbeat; re-floor every run to `min(stored, current)`.
- [ ] 0.3 Alarm on growth above the floor, never on absolute count.
- [ ] 0.4 Tests: (a) legacy present + zero orphans ⇒ silent; (b) simulated drain lowers the
      watermark; (c) growth above the *lowered* watermark alarms; (d) simulated `/tmp` reset to ~0
      re-floors and does **not** disarm. → **AC-A1**
  - (c) and (d) are the two arms a frozen ship-time baseline fails.

---

## PR 1 — Allocator + Reaper 3 (`/tmp` only, no migration beyond one runner)

### Phase 0 — Preconditions
- [ ] 1.0 Re-run the Overview measurements; paste into the PR body. `/tmp` is volatile — all plan
      figures are `as-measured 2026-07-27`.

### Phase 1 — Allocator (`scripts/lib/scratch-root.sh`)
- [ ] 1.1 Add `soleur_scratch_session_begin [base]`. **Published contract: prints nothing.** After it
      returns, `$TMPDIR` *is* the root; expose `$SOLEUR_SCRATCH_SESSION_ROOT` for the rare path need.
      Never `root=$(soleur_scratch_session_begin)` — the sibling `soleur_scratch_root()` in the same
      file *is* a print-and-capture API, so the obvious form is the banned one.
- [ ] 1.2 Subshell guard: `[[ "$BASHPID" != "$$" ]] && return 1` (the #6986 defect as a guard).
- [ ] 1.3 Sourced-file guard: refuse when `[[ "${BASH_SOURCE[0]}" != "$0" ]]` — when sourced,
      `BASHPID == $$` so 1.2 passes, and the trap would land on the operator's interactive shell.
- [ ] 1.4 Allocate `mktemp -d "$base/soleur-run.$$.XXXXXXXX"`; guard `|| return 1`, `: "${root:?}"`,
      `[[ "$root" == /* && -d "$root" && ! -L "$root" ]]`.
- [ ] 1.5 **Open the holder fd**: `exec 9>"$root/.soleur-run.holder"` (non-`CLOEXEC`). This is the
      primary liveness proof — fds survive `fork` **and** `execve` and are held continuously.
- [ ] 1.6 `export TMPDIR="$root"`; install **one** trap (ADR-129 D3), body **expanded at set time**:
      `trap "mv -- '$root' '$quar/' 2>/dev/null || rm -rf -- '$root'" EXIT INT TERM`.
      Do **not** copy the precedent's `readonly` — `local -r` is out of scope when the trap fires and
      a late-bound body would expand to `rm -rf -- ""`.
- [ ] 1.7 Keep `soleur_scratch_root()` byte-identical. Compose as two statements, never one line.
- [ ] 1.8 Document the option invariant: this library carries no `set` line and inherits the
      caller's; guards must hold under **both** `-e` and `+e`.
- [ ] 1.9 Tests → **AC6**: contract, subshell guard, sourced guard, `mktemp`-failure never yields
      empty `TMPDIR`, trap on EXIT/INT/TERM, quarantine fallback, guards under `-e` and `+e`.

### Phase 2 — Reaper 3 (`scripts/tmpfs-guard.sh`)
- [ ] 2.1 `reap_orphan_scratch_roots()`; candidates
      `find /tmp -mindepth 1 -maxdepth 1 -name 'soleur-run.*' -type d -user "$uid" -print0`.
- [ ] 2.2 **Anchored fixed-arity parse** `^soleur-run\.[0-9]+\.[A-Za-z0-9]{8}$`; near-miss fixtures
      (extra/missing field, non-numeric pid, trailing dot, embedded newline, `..`) → **AC4c**.
- [ ] 2.3 Reap iff `/proc/<pid>` absent. Present ⇒ spare (fail open) → **AC5**. Treat `state == Z`
      as dead, but only *after* the liveness pass.
- [ ] 2.4 Liveness: holder fd via `_INUSE_TOP` (primary) **+** `/proc/<pid>/environ` prefix-match
      (corroboration). Exclude the guard's own pid and ancestors → **AC4, AC12**.
- [ ] 2.5 Make `_mark_inuse` **base-aware** (iterate the base list, not a single `$TMP_ROOT`) →
      **AC4b**. Today it is fail-open toward deletion on every non-`/tmp` base.
- [ ] 2.6 Add the `_INUSE_TOP["__built__"]` sentinel and abort if absent → **AC11**. `_FRESH_TOP`
      already has one; the failure direction is deletion.
- [ ] 2.7 Hoist `_build_inuse_top` into `main` so both arms share one `/proc` walk.
- [ ] 2.8 **Allocation-free**: stream candidates, no `mktemp` on a base being reclaimed → **AC4d**.
- [ ] 2.9 Reap = `mv` into `<base>/soleur-quarantine.<uid>/`; drain on
      `TMPFS_GUARD_QUARANTINE_TTL_MIN` with `rm -rf --one-file-system --`; TTL floors to zero under
      block pressure → **AC7**.
- [ ] 2.10 **Add `soleur-run.*|soleur-quarantine.*` to `reap_scratch_entries`'s protected `case`** →
      **AC10**. Reaper 2 has no name filter and no holder-fd/environ gate; without this it deletes
      the roots Reaper 3 spares, and the plan's central safety claim is false.
- [ ] 2.11 Pin `TMPFS_GUARD_LOCKFILE` to a `TMPDIR`-independent path — otherwise a guard invoked
      from a migrated shell takes a *different* lock and races the cron guard's deletes.
- [ ] 2.12 Extract `scripts/lib/tmp-reaper-scope.sh` with
      `soleur_tmp_reaper_owner <path> → {output|scratch|sandbox|schema|none}`; source from all call
      sites; partition test (no path has two owners). The current split holds only by a character
      class that excludes dots.
- [ ] 2.13 Update the header reaper list **and the seam list** (`TMPFS_GUARD_SCRATCH_BASES`,
      `TMPFS_GUARD_QUARANTINE_TTL_MIN`) — the header states that list is exact.
- [ ] 2.14 Tests → **AC1, AC2, AC4, AC4b, AC4c, AC4d, AC7, AC10, AC11, AC12**, including the
      authored-work fixture untouched by a **non-dry-run** pass, and both blinding halves.
- [ ] 2.15 Tests pin **both** `TMPFS_GUARD_TMP` and `TMPFS_GUARD_SCRATCH_BASES`; unset seam
      defaults fail-closed → **AC14**. AC2 mandates a real reap, so an unpinned seam would delete
      the operator's real roots.

### Phase 3 — One runner
- [ ] 3.1 Pre-flight `scripts/test-all.sh` for the three disqualifiers: existing `trap … EXIT`
      (35 files carry one; `trap` **replaces**), `&`/`nohup`/`setsid`/`disown`, `exec "$0"`.
- [ ] 3.2 Allocate one per-run root under the existing `/var/tmp` default (234 invocations = 98
      static `run_suite` + 136 glob-expanded — record the derivation inline). Preserve "respects an
      explicit caller value" **and** the independent `TC_TMPDIR=/tmp` pin → **AC8, AC13**.
- [ ] 3.3 Record the coverage fraction; if >90%, declare the tail an accepted steady state.

### Phase 4 — Discovery + adoption metric
- [ ] 4.1 Add one Code Quality rule to `AGENTS.rest.md` (new immutable id) + index pointer. Verify
      loader-class fit (`grep -n 'DOCS_RE=' -A 25 .claude/hooks/session-rules-loader.sh`) and
      `lint-agents-rule-budget.py` headroom vs the 23000-byte cap → **AC9**.
      Measured: zero discovery path exists today.
- [ ] 4.2 Adoption **floor** (`scripts/soleur-scratch-adoption.floor`), CI fails when it drops.
      **Not** the census ratchet — it cannot move (the linter needs a literal `trap` in the scanned
      file; the idiom puts it in the library). Delete the plan's earlier false rule-(c) claim.
- [ ] 4.3 Residue probe (`SOLEUR_FT6297_SELFTEST` shape). Note its blind spot: it cannot distinguish
      correct cleanup from a destroyed deliverable — that is what quarantine covers.
- [ ] 4.4 Do **not** add a static entry-point lint (ADR-129 rejected the class) and do **not**
      register `scripts/lib/scratch-root.test.sh` — the `scripts/lib/*.test.sh` glob already covers
      it (`lint-orphan-test-suites.sh` → none); registering would double-register.

### Phase 5 — ADR + record correction
- [ ] 5.1 ADR-150 (ordinal provisional; `/ship` re-verifies). Amends **ADR-133 D2** (age+size →
      declared ownership). States ADR-129 needs no amendment, with the nuance that D2's *remedy*
      sentence is substituted by the `BASHPID` guard. Cites **AP-009 "Never delete user data"** and
      AP-010. Carries the six-reaper partition table and the rejected-alternatives table including
      the measured `systemd-run --user --pipe -p PrivateTmp=yes` **silent no-op**.
- [ ] 5.2 One-line correction to the merged #6986 plan (still directs "amend ADR-129" for a registry
      file that was never adopted).
- [ ] 5.3 `bash scripts/test-all.sh` green → **AC15**.

---

## PR 2+ — Adoption tail (not this PR)

- [ ] 6.1 Rank entry points with the **residue probe**, not `tmp_delta` — the latter reads
      `$TC_TMPDIR` (`/tmp`) while suites allocate in `/var/tmp`, so a 1,883-file leak reports 0.
      Run before opening the PR so the file list is named, not TBD.
- [ ] 6.2 **Attribute `/tmp` growth to named producers and state what fraction the mechanism can
      reach.** Both runners already point at `/var/tmp`, so `/tmp` entries come from paths that do
      not inherit: the Claude Code Bash sandbox (documented unrelocatable), directly-invoked scripts,
      hooks, `env -i`, hardcoded literals. The single most important honesty item.
- [ ] 6.3 `run-registered-suites.sh` (**76** suites, not 87) + `/var/tmp` coverage. Note it already
      has `trap 'rm -f "$LOG"' EXIT` — extend that cleanup function, never add a second trap.
- [ ] 6.4 Tier 3 boundaries: `env -i` (75 occurrences / 28 files **scoped to `*.sh`**; 176/76
      repo-wide), `sudo` (22 files), cron, `ssh`, `docker run`.
- [ ] 6.5 Absolute `/tmp/<literal>` sites — derivation command required (independent patterns give
      12 / 14 / 5). Each checked against the scratch-only rule first; several are deliberate outputs.
- [ ] 6.6 Mechanical gate for the scratch-only rule: assert every path a migrated entry point
      **emits** (`--body-file`, `--output`, `-o`, redirects feeding `gh`/`git`/`rclone`) resolves
      **outside** `$TMPDIR`. Not the rejected lint class — no shell-scope inference required.
- [ ] 6.7 Soak probe + follow-through enrollment (near-vacuous before adoption).

---

## Cross-cutting

- [ ] X.1 Never move an authored artifact inside a root — **a root is scratch-only.** Quarantine is
      the backstop; bounding the edit set (6.1) is the real control.
- [ ] X.2 `/proc` self-check: if the guard cannot read `environ` for a known live own-uid pid
      (`hidepid=2`, `ptrace_scope=3`, non-dumpable), alarm and **skip the reap** (fail closed).
- [ ] X.3 PR body: note that the 3,836 `ft6297.*`/`ft.*` entries predate #6986 by 30 minutes and do
      **not** falsify the precedent — a reviewer running the histogram will conclude the opposite.
