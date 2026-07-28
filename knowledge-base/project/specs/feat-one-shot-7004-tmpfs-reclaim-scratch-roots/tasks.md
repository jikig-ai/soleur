# Tasks — #7004 tmpfs ownership-keyed scratch-root reclamation

Derived from `knowledge-base/project/plans/2026-07-27-feat-tmpfs-ownership-keyed-scratch-root-reclamation-plan.md`
(post-review). Three PRs; **PR 0 ships first and alone**.

Legend: `[ ]` todo · `AC#` maps to the plan's Acceptance Criteria.

---

## PR 0 — Alarm rebaseline (independent, ~40 lines)

The guard alarms every 5 minutes **today**, before any of this. The reaper neither causes nor
worsens it, so this is separable and has the highest immediate operator value.

- [ ] 0.1 In `scripts/tmpfs-guard.sh`, count only entries **not** matching `soleur-run.*`.
      **MOVED TO PR 1** (task 1.x below) on converging review evidence. The recogniser matches
      **zero** entries today (no producer exists on `main`), so it delivers nothing in PR 0 while
      carrying a live risk: its failure direction is *silent*. If PR 1's allocator emits
      `XXXXXXXXXX` (mktemp's common arity) nothing matches, every scratch root counts as unowned,
      and the every-5-minutes alarm returns at the moment the allocator lands — the exact defect
      PR 0 exists to remove. Three agents converged independently: architecture ("the single
      highest-leverage change available to this PR"), simplicity ("the clearest YAGNI in the
      diff"), and security (the name-only test is blind to a dead-pid orphan, which is *the* leak
      class #7004 addresses). Mutation testing then showed five of eleven surviving mutants were
      schema-regex vacuities that dissolve entirely with the move. Shipping recogniser and producer
      together is what makes the contract testable at all.
- [x] 0.2 Persist a watermark beside the heartbeat; re-floor every run to `min(stored, current)`.
      `WATERMARK_FILE` sits in the same state dir as the alarm + heartbeat. A missing or
      unparseable value seeds from the current count rather than reading as `0` — reading a corrupt
      file as zero would alarm on the entire legacy backlog, which is the behaviour being replaced.
      Reseeding is **not** silent when a heartbeat proves a prior run completed: see 0.5, where
      review showed the reseed forgives the whole accumulated leak.
- [x] 0.3 Alarm on growth above the floor, never on absolute count.
      Order is load-bearing and is asserted: the floor derives from the *previously stored* value,
      the comparison runs against that, and only then is the new floor persisted. Re-flooring first
      would compare the count against itself and never alarm.
- [x] 0.4 Tests: (a) legacy present + zero orphans ⇒ silent; (b) simulated drain lowers the
      watermark; (c) growth above the *lowered* watermark alarms; (d) simulated `/tmp` reset to ~0
      re-floors and does **not** disarm. → **AC-A1**
  - (c) and (d) are the two arms a frozen ship-time baseline fails.

- [x] 0.5 Review-driven fixes (8 agents; the ones below are merge-blocking silent failures, all
      independently reproduced before fixing):
  - **Enumeration failure no longer floors the watermark.** `find` failing was swallowed into `0`;
    because the ratchet is down-only that persisted `floor=0` and re-armed the forever-alarm on the
    next healthy run. Reproduced: run1 wm=30, run2 (unreadable `/tmp`) wm=0, run3 alarms at the
    full count forever. `top_level_entry_count` now returns non-zero for "could not look" and the
    caller leaves the stored floor alone. **This had to land before deleting the dead
    `entry_count`** — that variable was dead as a *value* but load-bearing as a *side effect*
    (under `pipefail` its un-guarded `find` aborted the run), so removing it alone, as two agents
    suggested, would have converted the defect from latent to live.
  - **Watermark loss is no longer silently forgiven.** `min(stored,current)` does not neutralise a
    lost/corrupt/hostile value — it re-floors to *current*, granting the leak an amnesty equal to
    its size (leak at 18,000 over a true floor of 600 ⇒ floor rewritten to 18,000, alarm now needs
    23,000). Reproduced three ways. `HEARTBEAT_FILE` is the discriminator: present ⇒ a run
    completed ⇒ a missing watermark is state loss, not a first run, and now alarms.
  - **An unpersistable watermark says so.** Both write paths swallowed failure, disarming growth
    detection permanently with no artifact anywhere. Now atomic (tmp+mv, mirroring `alarm_record`)
    and loud, with a `COUNT_DEGRADED` flag so `alarm_clear_if_healthy` cannot erase the very alarm
    reporting the disarm.
  - **The count alarm can no longer be buried.** The loader renders `tail -1`; the count alarm is
    appended at run start and the usage alarm at run end, so at 94 % usage the usage line always
    outranked it. Harmless while the count alarm re-fired every 5 min — but this PR makes it rare
    and edge-triggered, so a real leak would have been the tail line for one run then evicted
    within hours. The usage alarm is now suppressed when count pressure already fired.
  - **A dry run no longer mutates the watermark**, and the floor is written only when it moves.
  - **Newline-safe counting**: one line emitted per *entry* rather than per name-line. Measured
    before the fix, a single directory named `leak_a<newline>leak_b` counted as 3. The reap path in
    this same file already defends against this after a measured incident; the count path had
    re-solved the problem from scratch and got it wrong.
  - **Octal-shaped watermarks rejected** (`08` aborts bash arithmetic under `set -e`; `0600` means
    384).
  - **The suite no longer overwrites the operator's real heartbeat.** Live proof during review: it
    read `run complete: /tmp/tmpfs-guard.vFKDu4hJ/tmp at 94%` — a fixture root — which masks a dead
    cron for 30 minutes. Caused by my own test runs.
  - Stale prose corrected where the change falsified it: the "provably reachable" justification for
    5000 (argued from absolute counts), the "BOTH signals must hold" comment (a passing arm
    disproves it), the seam-list omission, and `plugins/soleur/skills/work/SKILL.md` — the
    highest-reach one, injected into every agent session, which told the agent a reclamation
    mechanism exists that was removed before merge.
  - Declined, with reasons: adding the watermark to Arm 20's loader-parity loop (observability
    showed there is no loader coupling to assert — kept a standalone "not on tmpfs" assertion
    instead, which is the real defect that mutant exposed); and an upward ratchet to absorb a new
    legitimate steady state (a design change with tradeoffs — recorded as a known limit in the
    code and carried to PR 1 rather than improvised here).
  - Evidence: `scripts/tmpfs-guard.test.sh` Arms 21–29. Suite: **60 passed, 0 failed**, stable
    across 4 consecutive runs.
  - **My first mutation battery was the floor, not the proof.** It ran 3 mutations, all killed, and
    I recorded that as "mutation-verified". An independent pass then ran 13 and **11 survived** —
    evidence about the mutations I imagined, not about the tests. The decisive survivor: replacing
    `growth >= COUNT_TRIGGER` with a hardcoded `growth >= 7` passed the entire suite, as does any
    constant in roughly [2,12], so `COUNT_TRIGGER`, its env override and the whole justification
    for 5000 were unfalsifiable. Also correcting the earlier claim's arithmetic: each reported
    figure was inflated by one, because the cardinality guard fires on *any* failure and is not an
    independent detector.
  - Arms 22–29 were written to close those survivors. Re-verified against a **GREEN positive
    control**, 8/8 killed: threshold `>=`→`>`; hardcoded trigger; 20 % threshold inflation; alarm
    reporting a hardcoded count; watermark default relocated onto tmpfs; enumeration failure
    read as 0; dry-run persisting; state-loss reseeding silently.
  - **Two mutation runs were discarded as VOID rather than counted** — the failure mode this
    repo documents. Run 1's baseline exited non-zero with zero `[FAIL]` lines (sandbox missing a
    file a drift-guard arm reads). Run 2's baseline did the same because `/tmp` had reached 99 %
    and Arm 1's 20 MB fixture could not allocate; re-running with scratch on disk restored a green
    baseline. A baseline that is not green makes every mutation result meaningless in both
    directions.
  - Measured on the real `/tmp`, re-derivable with
    `find /tmp -mindepth 1 -maxdepth 1 -printf '.\n' | wc -l`: **20,832 top-level entries counted
    in 0.076 s** against the 300 s cron interval (an independent re-derivation during review read
    20,855 — `/tmp` is volatile, so treat the figure as ~20.8k, not a constant).

---

## PR 1 — Allocator + Reaper 3 (`/tmp` only, no migration beyond one runner)

### Phase 0 — Preconditions
- [ ] 1.0 Re-run the Overview measurements; paste into the PR body. `/tmp` is volatile — all plan
      figures are `as-measured 2026-07-27`.
- [ ] 1.0a **Carried from PR 0 task 0.1 — the schema recogniser.** Add the ownership-schema
      exclusion to `tmpfs-guard.sh`'s count **in the same PR as the allocator that produces the
      names**, so producer and recogniser can be pinned to each other. Requirements the PR 0 review
      established, all of which PR 0 could not satisfy alone:
  - Derive the recogniser and the producer from ONE source (the plan's ADR-150 Record #4 already
    mandates extracting a shared `soleur_tmp_reaper_owner` predicate). Note this collides with the
    stated "`tmpfs-guard.sh` sources nothing" constraint — resolve that in the ADR, do not
    discover it mid-implementation.
  - Build the exclusion fixture from **real `mktemp` output**, not a hand-written literal, so the
    coreutils alphabet/arity assumption is asserted rather than assumed.
  - Include a **mixed** fixture (schema + unowned entries in one `/tmp`). A pure all-or-nothing
    fixture pair cannot distinguish per-entry exclusion from "any schema entry ⇒ count 0", and the
    latter mutant survived PR 0's original suite — in production one scratch root would have
    silenced the machine's alarm.
  - Gate the exclusion on **liveness, not name shape** (`/proc/<pid>`) plus `-user`. A name-only
    test excludes dead-pid orphans, which is exactly the leak class #7004 exists to catch, and it
    lets any local process hide behind a schema-shaped name in a world-writable `/tmp`.
  - Pin the anchors and the arity with a fixture that deviates in the **suffix**, not only the pid
    component; dropping `^`, dropping `$`, and `{8}`→`+` all survived PR 0's near-miss arm.
  - Verify the regex under the **cron locale**: `[A-Za-z0-9]` is a collation range, and
    `/etc/pam.d/cron` loads `LANG=fr_FR.UTF-8`, so `soleur-run.1.aaaaaaaé` matches in production
    but not under `LC_ALL=C`. Direction is suppression. Pin `LC_ALL=C`.
- [ ] 1.0b Consider an **upward ratchet** for the count watermark. PR 0's floor only ratchets down,
      so a sustained *legitimate* rise into a new steady state alarms every run and cannot be
      absorbed. Correct for an unreclaimed leak, noise for a genuine new baseline; deliberately not
      improvised in PR 0.

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
