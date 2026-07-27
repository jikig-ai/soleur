---
feature: feat-one-shot-tmp-tmpfs-mktemp-leak
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-27-fix-tmp-tmpfs-mktemp-cleanup-leak-plan.md
status: pending
---

# Tasks — /tmp tmpfs cleanup leak

Derived from the **post-review (v3)** plan: v2 restructured by a 7-agent panel, then reconciled
against the two panel seats that never reported (`code-simplicity-reviewer`, `spec-flow-analyzer`)
plus a round of direct measurement. Phase order: RED → widen linter → derive defective set from
tool output → fix → relocate → ceiling → ADR → track.

**Precedence:** this file wins over the plan body wherever they disagree. The plan body's Phase
numbering is v1 and is retained only for its prose rationale.

## Verified failure chain (all five links measured 2026-07-27, not inferred)

The leak survived **two** deployed defenses. Every link below was confirmed by direct command:

1. **Source defect.** `scripts/followthroughs/anthropic-admin-key-6297.test.sh:31-32` — `mktmp()`/
   `mktmpd()` append to `TMP_PATHS` but every call site uses `$( )`, so the append lands in a
   subshell and is discarded. `trap cleanup_tmp EXIT INT TERM` (line 28) then iterates an empty
   array. Leaked 1,883 `ft.*` + 1,883 `ft6297.*`.
2. **CI linter blind.** `python3 scripts/lint-trap-tempfile-ownership.py <that file>` → **0
   findings**. Two compounding causes: `ARRAY_APPEND.match()` (line 289) anchors at line start and
   the helpers are one-liners, so the append sits mid-line; and the trap names a *function*
   (`cleanup_tmp`), which `trap_owned_arrays()` does not resolve.
3. **Janitor structurally blind.** `scripts/tmpfs-guard.sh` runs `*/5` on the user crontab, but
   `SCRATCH_MIN_MB=100` (line 50). Largest leaked `ft.*` = **372 bytes**; `tmp.*` entries ≥1 MB =
   **0 of 11,172**. Not one leaked artifact could ever be reaped. `SCRATCH_AGE_MIN=1440` (24h)
   additionally excluded the one ≥100 MB item (a 2.3 GB repo copy, 14h old at fill time).
4. **The alarm for exactly this fired, unheard.** `tmpfs-guard.sh:250` logs "nothing reapable
   found" when usage ≥70% and both reapers came back empty — **94 occurrences in 14 days**. It
   goes to `logger` (journal, unwatched) and `notify-send`, which no-ops under cron with no DBUS
   session and is `2>/dev/null || true`.
5. **Its telemetry reads healthy but is fabricated by its own tests.** 346 `Reaped` journal lines
   in 14 days; **344 came from fixture roots** (`/tmp/tmpfs-guard.XXXX/tmp`), **1** from real
   `/tmp`. The test suite writes into the operator's production journal, so the only telemetry for
   this guard is dominated by test noise.

**The through-line:** every layer reported success while doing nothing. Hold the plan's OWN new
machinery to that standard — see the silent-failure gates marked **[SF]** below.

## Phase 0 — Preconditions

- [ ] 0.1 Re-run the falsifying measurements; confirm they still hold:
      `python3 scripts/lint-trap-tempfile-ownership.py scripts/followthroughs/anthropic-admin-key-6297.test.sh` → 0
      `python3 scripts/lint-trap-tempfile-ownership.py --census` → 98 (highwater 100)
- [ ] 0.2 Confirm no bats; suites are plain `*.test.sh`. Do not add a framework.
- [ ] 0.3 **`run_probe` uses `env -i` — this is settled, not an open question.**
      `anthropic-admin-key-6297.test.sh:80` is `( cd "$dir" && env -i PATH=… HOME=… …)`, which
      strips `TMPDIR` from the child. Consequence, precisely scoped: the 1,883/1,883 leak is
      allocated in the **parent** (lines 51, 113-258), so `export TMPDIR` **does** fix the
      observed leak. But any temp the code under test allocates inside the probe still lands in
      `/tmp` while every scratch-root-anchored AC reads 0. **Branch: add `TMPDIR="$TMP_ROOT"` to
      the `env -i` allowlist** beside `PATH`/`HOME`. Do not leave this as a question for `/work`.
- [ ] 0.4 **Census headroom is exactly 2** (98/100). This PR adds `raise-tmp-tmpfs-ceiling.sh` and
      `raise-tmp-tmpfs-ceiling.test.sh` — both MUST carry an owning `trap … EXIT` or
      `--check-highwater` fails at merge. Do not add a third `.sh` without lowering the census
      first. (Converged finding: code-simplicity P2-10, spec-flow P1-11.)
- [ ] 0.5 **Collect a 95-suite `tmp_delta` baseline BEFORE gating on it** (spec-flow P1-3). The
      counter had zero consumers, so its live distribution is unknown; gating first would go
      instantly red across the suite or be quieted into uselessness.

## Phase 1 — RED (tests first, must fail)

- [ ] 1.1 Assert on-disk absence after process exit, driving the helper through command
      substitution at real nesting depth (2 levels). Asserting that a trap *exists* is forbidden —
      it passes today against a leaking script. **Fold into the existing suite** rather than adding
      `anthropic-admin-key-6297-cleanup.test.sh`: a new file costs a `run_suite` registration,
      orphan/exec-bit/varq lints, and 1 of the 2 remaining census slots that Phase 6 needs
      (code-simplicity P2-8).
- [ ] 1.2 Linter fixture reproducing the **mid-line** append inside a `$()`-invoked helper with a
      **named-function** trap. Must exit 1. A multi-line fixture is vacuous — it is not the real
      shape. Both conditions must be present in one fixture; either alone under-constrains.
- [ ] 1.3 Inverse arm: a clean suite must still pass (spec-flow P2). Without it the delta gate can
      be satisfied by a detector that fails closed on everything.

## Phase 2 — Widen rule (a) (contract change BEFORE consumers)

- [ ] 2.1 Un-anchor `ARRAY_APPEND` using the command-position idiom already used by `MKTEMP`;
      switch `.match()` → `.search()` at the append test (line 289).
- [ ] 2.2 Resolve named-function traps in `trap_owned_arrays()` via `find_functions()` spans.
      Kieran's prototype: this fix ALONE yields 0 findings across 689 files — it is necessary but
      not sufficient. Only 2.1 + 2.2 together yield the 2 real findings.
- [ ] 2.3 ~~Give rule (a) an accept mechanism~~ — **CUT.** It already has one: `check_rule_a`
      calls `escaped()` (`lint-trap-tempfile-ownership.py:109`, invoked at `:311`), the
      reason-required `# lint-trap-ownership: ok <reason>` hatch. Added-line scoping would
      additionally blind the rule to exactly the pre-existing files 3.2 sweeps
      (code-simplicity P1-3).
- [ ] 2.4 Do **not** implement transitive `$()` detection (cut, R5).
- [ ] 2.5 Note in-source that `find_functions()` desyncs on heredoc braces and misses `cleanup` in
      the two largest scripts, so it fails toward silence there. **[SF]**
- [ ] 2.6 Run the full scan; confirm exactly 2 findings, both real, zero false positives. **Record
      the tool output as the 3.2 derivation artifact in the same commit** — this count expires the
      moment 3.1 lands (code-simplicity P2, spec-flow P2).

## Phase 3 — Fix the leak site and sweep the class

- [ ] 3.1 Replace the `TMP_PATHS` accumulator with a **single scratch root** + `export TMPDIR` +
      `trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM`. No registry file (R2) — this is already the
      house idiom in 15 sibling files.
- [ ] 3.1a **`set -u` does NOT protect this trap — the failure mode is empty, not unset.** **[SF]**
      Verified: `anthropic-admin-key-6297.test.sh:11` is `set -uo pipefail` — **no `-e`**. So a
      failing `TMP_ROOT=$(mktemp -d …)` — which is exactly what happens when `/tmp` is full, the
      scenario this plan exists for — does not abort. `TMP_ROOT=""` → `export TMPDIR=""` → `mktemp`
      silently reverts to `/tmp` → `rm -rf -- ""` is a no-op. Two silent failures compound into a
      clean-looking run that leaks exactly as before. All four guards are required, not optional:
      `|| { echo …; exit 1; }` on the `mktemp -d`; `: "${TMP_ROOT:?}"`;
      `[[ $TMP_ROOT == /* && -d $TMP_ROOT && ! -L $TMP_ROOT ]]`; and `readonly TMP_ROOT`.
- [ ] 3.1b **`readonly TMP_ROOT` is load-bearing, not defensive style.** The trap body is
      **single-quoted, therefore late-bound** — it resolves `$TMP_ROOT` at exit, not at trap
      installation. Any later reassignment redirects the delete, *including by the Phase 5
      `scratch-root.sh` resolver this same PR introduces*. Contrast `tmpfs-guard.sh`'s deliberate
      early-bound `trap "rm -f '$cand_file' …" RETURN` with its `# shellcheck disable=SC2064`.
- [ ] 3.1c State the doctrine conflict in the PR body (P3): *Alternatives Considered* rejects
      `rm -rf` in the reaper (`guardrails:block-recursive-delete`, "a size-survivor can be an
      abandoned repo clone") while 3.1 mandates `rm -rf` over a root holding ~20 `git init`
      sandboxes. Defensible — every path came from `mktemp` — but state it, don't leave an
      apparent contradiction.
- [ ] 3.2 Derive the defective set **from 2.6 tool output**, not by hand. Expect **12** files, not
      10. Record a *defective* / *sound* verdict per file in the PR body; fix only the defective.
- [ ] 3.3 `constraint-scaffold.sh` and `constraint-scaffold/test/boundary.test.sh` — trap signals to
      `EXIT INT TERM`. Confirm no `git worktree prune` is separately owed on the kill path.

## Phase 4 — Outcome-based detection

Highest leverage in the plan, but it was **vacuous as written** and needs the fix below.

- [ ] 4.1 **Do NOT simply ungate `tmp_delta` from `TEST_TIMING_LOG`.** `TC_TMPDIR` is bound at
      **source time** (`scripts/lib/test-contention.sh:38`), so a per-suite exported `TMPDIR`
      never repoints it — the delta would keep measuring shared `/tmp`, which 4.2 drives to 0 by
      construction. **[SF]** (code-simplicity P1-1, spec-flow P1-3/P1-4.)
      **Resolution — do not cut the item, fix it:** `tc_tmp_entry_count` already accepts an
      optional path (`local d="${1:-$TC_TMPDIR}"`, `:61`). Pass each suite's private root
      explicitly. This makes the delta measure the right directory without globally repointing
      `TC_TMPDIR` (which 5.3 exists to prevent).
- [ ] 4.2 Give each suite a private scratch root; export `TMPDIR` for the child; reap on exit.
- [ ] 4.3 Fail a suite on non-zero delta **against its own private root**. Covers 95 suites and the
      65 non-shell temp allocators the shell linter structurally cannot see. Gate only after 0.5's
      baseline exists.
- [ ] 4.4 **"Reap unconditionally" needs a liveness gate** (spec-flow P1-6) — the property
      `tmpfs-guard.test.sh`'s `MUTATION CONTROL: once the process is gone` arms exist to protect.
      Backgrounded children would otherwise lose scratch mid-run.
- [ ] 4.4a **Do NOT copy `tmpfs-guard.sh`'s liveness gate — it is the wrong shape at this
      cadence.** **[SF]** Its `_INUSE_TOP` set is sound only because candidates first cleared
      `SCRATCH_AGE_MIN=1440`; 24h makes the check→delete TOCTOU window irrelevant. A reaper firing
      *seconds* after suite exit has no age gate at all — and that is exactly when a backgrounded
      child is still starting and holds no fd yet. A full `/proc` pass per suite × 95 is also the
      cost shape that file's own comment rejects ("millions of readlinks").
      **Use a deterministic gate instead:** run each suite in its own process group, `wait` for it,
      reap only then; treat `fuser`/`/proc` as a backstop. **On any ambiguity, leave the directory
      — a leak is recoverable, a delete is not.**
- [ ] 4.5 **Ownership marker for nested runs** (spec-flow P1-5): 5.2 says never override an
      inherited `TMPDIR`, 3.1 mandates override — undefined for nested `run_suite`, where the
      parent's reap would delete the child's live scratch.
- [ ] 4.5a **Do NOT use `$$` as the ownership marker — it cannot distinguish sibling suites, and
      forks invert it.** **[SF]** Verified: `run_suite` executes `"$@"` **in-process**
      (`scripts/test-all.sh:118`), so `$$` is identical for all 95 suites in a run — the marker
      separates *runs*, not *roots*. Worse, in any subshell `$$` is still the parent's PID
      (`$BASHPID` is not), so a forked/backgrounded child stamping `$$` marks the **parent** as
      owner and the parent's exit reap deletes the child's live scratch — precisely the case 4.4
      exists to prevent. **Stamp a random nonce instead** (reuse the `mktemp -d` suffix). PID
      recycling is the benign direction here — a stale marker only ever mis-claims an already-dead
      owner's orphan.
- [ ] 4.5b **The per-suite reaper must never delete the shared parent, and no current AC would
      notice if it did.** **[SF]** Phase 5 puts every root under one `$HOME/.cache/soleur/tmp`.
      Assert the reap target is a **strict descendant** — never equal to, never an ancestor of, the
      resolved shared root, and never the resolver's return value itself. A reap of the shared root
      reads as *success* on every count-based AC, since AC2-corrected is already self-declared
      vacuous. **Add a concurrency test:** two `test-all.sh` runs in parallel, assert neither root
      disappears. Parallel worktrees are this repo's documented workflow, so this is the normal
      case, not an edge case.
- [ ] 4.6 **The `*/5` tmpfs-guard cron mutates `/tmp` mid-suite** (spec-flow P1-3): a reap of N
      cancelling a leak of N reads as a **false green**; live agent sessions inject false reds.
      Private roots under 4.2 resolve this — assert that the guard's reaper cannot see them.

## Phase 5 — Relocate bulk temp writes off RAM

- [ ] 5.1 New `scripts/lib/scratch-root.sh` (NOT `test-contention.sh`, which declares itself
      observation-only and whose `TC_TMPDIR` binds at source time — R6).
- [ ] 5.2 Call-time only; never mutate `TC_TMPDIR`; never override an explicit `TMPDIR` (see 4.5
      for the nested-ownership carve-out).
- [ ] 5.3 Test that `TC_TMPDIR` still resolves to the tmpfs after the resolver runs, so ADR-133's
      instrumentation cannot be silently repointed. **Assert the resolver was actually called** —
      as written this passes trivially when it is never invoked (spec-flow P1-4). **[SF]**
- [ ] 5.4 **Failure contract for scratch-root creation** (spec-flow P1-2). **[SF]** Undefined today
      for: `mkdir` failure, unset/read-only `$HOME`, `XDG_CACHE_HOME` relative or inside the repo,
      pre-existing dir at 0755, or a symlink. An empty return makes `export TMPDIR=""` → `mktemp`
      silently reverts to `/tmp` **and** the delta gate reads clean — two silent failures
      compounding into a false green. Require a loud abort; mirror per
      `cq-silent-fallback-must-mirror-to-sentry`.
- [ ] 5.4a **Resolve and fence the root before trusting it.** **[SF]** `realpath -e` the resolved
      root, then abort unless it is under `$HOME`, is **not** inside the repo working tree, and is
      **not** a symlink. Without this, `XDG_CACHE_HOME=.` makes every scratch root relative to the
      suite's CWD — i.e. **inside the working tree** — and the exit reap deletes tracked files.
      (`rm -rf -- "$ROOT"` is itself traversal-safe: `rm` does not descend symlinks, and a
      symlinked root removes only the link. The exposure is entirely upstream, in what the
      resolver hands back.)
- [ ] 5.5 Assign an age policy + owner for `$HOME/.cache/soleur/tmp`, or drop the claim that it is
      handled. Relocating an un-janitored leak surface only moves the leak (code-simplicity P2-7,
      spec-flow P3).

## Phase 6 — Raise the tmpfs ceiling (RESTORED by operator decision)

The review panel cut this (R4) as lowest-value/highest-risk. **The operator explicitly overrode
that cut and restored it to this PR.** Do not re-defer it; task 8.3 is deleted accordingly.
The `/etc/tmpfiles.d` 2d age drop-in stays **cut on safety grounds** and must not be reinstated —
re-measured 2026-07-27, it would unlink **11 files** under live Claude session scratchpads.

- [ ] 6.1 `scripts/raise-tmp-tmpfs-ceiling.sh` — idempotent, re-runnable, `--dry-run`. Target
      derived from `/proc/meminfo` (25% of MemTotal, floored at current so it can never shrink),
      not hardcoded 8G. Backup + lock + atomic install.
- [ ] 6.1a **Stage the temp file IN `/etc`, never in `/tmp` or `$HOME`.** **[SF]** `mv` is atomic
      only *within one filesystem*. `/tmp` is a separate tmpfs, and once Phase 5 lands a bare
      `mktemp` resolves under `$HOME/.cache` — either way `mv` silently degrades to copy+unlink,
      and a kill mid-copy leaves `/etc/fstab` **neither the old file nor a valid new one**, with
      nothing to restore it. Use `mktemp /etc/.fstab.XXXXXX`. **Precedent:**
      `apps/web-platform/infra/infra-config-apply.sh` mktemps *in the destination dir* for exactly
      this reason; `.claude/hooks/lib/session-state.sh:211` uses the sibling-of-target
      `mktemp "${target}.XXXXXX"` + `mv` form.
- [ ] 6.1b **Validate the temp file BEFORE installing it** — `findmnt --verify --tab-file "$tmp"`
      — so the only content ever placed at `/etc/fstab` is already-validated. 6.3's post-write
      re-parse then *confirms*, rather than being the gate. **Precedent:** `infra-config-apply.sh`
      validates with `visudo` before installing, for the same boot/security-critical reason.
- [ ] 6.1c **`flock` on `/etc/fstab` itself is defeated by the `mv`** — the lock ends up on an
      orphaned inode. Lock a separate, never-replaced path.
- [ ] 6.1d **Preserve mode and ownership explicitly:** `install -m 0644 -o root -g root`.
      `mktemp` creates 0600, which would break non-root `findmnt`/mount helpers. Copy the
      SELinux/AppArmor label too — the temp file's context does not survive as the right one.
- [ ] 6.1e **`fsync` the file AND the parent directory** around the rename. `mv` is atomic but not
      *durable*: without an `fsync` on `/etc` itself, a power loss between rename and boot can lose
      the entry (kernel/PostgreSQL durability guidance).
- [ ] 6.1f **Abort if `/etc/fstab` is a symlink** (`-L`) — `mv` would silently replace the link
      rather than the target.
- [ ] 6.2 Handle every fstab shape with a defined branch; catch-all is a **loud abort, never a
      silent exit 0** (spec-flow P1-7): no `/tmp` line (systemd `tmp.mount` host); `/tmp` line with
      no `size=`; multiple/commented `/tmp` lines; unit normalization (`4G` vs `4194304k` vs `50%`
      compared in bytes). **[SF]**
- [ ] 6.3 **Validate intent, not just syntax** (spec-flow P1-9). **[SF]** `findmnt --verify` proves
      the file parses, not that `/tmp` means what was intended — re-parse the emitted line and
      assert `size=` equals the derived target in bytes. `mount -o remount /tmp` can exit 0 without
      changing size, so read the live value back via `findmnt -no SIZE /tmp` and compare rather
      than trusting the remount exit code.
- [ ] 6.3a **Validate what `findmnt --verify` does NOT catch** (it proves the file parses and the
      targets resolve, nothing more): exactly **6 fields** per line; numeric `dump`/`pass` fields;
      spaces/tabs inside paths escaped as `\040`/`\011`; no CRLF; **trailing newline present**; no
      duplicate mountpoints; and the `4GB`-vs-`4G` suffix trap — an invalid unit *parses fine in
      fstab* and only fails at mount time.
- [ ] 6.4 `scripts/raise-tmp-tmpfs-ceiling.test.sh` — fixture fstab via an injected path seam
      (mirroring `TMPFS_GUARD_TMP`), never the real `/etc/fstab`. Cases: already-applied ⇒ no-op;
      unapplied ⇒ rewritten + backup exists; malformed ⇒ restored + non-zero; `--dry-run` ⇒ zero
      writes; plus one case per 6.2 shape.
- [ ] 6.4a **Assert non-target lines survive — this is the only unbootable-machine path in the
      plan and it is currently untested.** **[SF]** T15-T19 all pass for a rewrite that correctly
      fixes `size=` while dropping the `/` or swap line. Gate on **both**: line count unchanged,
      and `diff` of before/after with the `/tmp` line excised is empty.
- [ ] 6.4b Acknowledge the coverage limit honestly: because fixtures never touch the real
      `/etc/fstab`, the **symlink, cross-device, and mode/ownership branches are untested by
      construction**. Either exercise them against a fixture `/etc`-like dir on the same
      filesystem, or state the gap in the PR body — do not let the fixture suite imply coverage it
      does not have.
- [ ] 6.5 Both new `.sh` files must carry an owning trap (see 0.4 — headroom is exactly 2).
- [ ] 6.6 Bound backup accumulation under `/etc` (spec-flow P3) — keep N most recent. **This is the
      plan's only root-owned delete.** **[SF]** Enumerate with a literal-prefix
      `find /etc -maxdepth 1 -name 'fstab.bak.*' -type f`; **never** a constructed glob (an empty
      variable yields `rm -f /etc/fstab.bak.` at best) and **never** `rm -rf`.
- [ ] 6.7 **Record the ceiling raise as a raised backstop, not a free win.** The kernel's tmpfs
      docs warn: *"if you oversize your tmpfs instances the machine will deadlock since the OOM
      handler will not be able to free that memory."* Tmpfs pages count against RAM; swap on this
      host is ~fully used (2.0 GiB total, 204 KiB free). The `size=4G` pin was incidentally
      *protecting* the machine — it caps a runaway at 4G before `ENOSPC` (not OOM) stops it. At
      ~7.5G a runaway gets twice as far before that backstop engages. Still sound (25% is well
      under the kernel's 50% default, and the leak fix drives accrual to ~0), but the plan must say
      so plainly rather than presenting the raise as unqualified improvement.
- [ ] 6.8 Verify the live result with `findmnt -no SIZE /tmp`, **never `df`** (which can report a
      stale cached value). `mount -o remount /tmp` is safe with open file handles but can exit 0
      without applying the new size — hence read-back, not exit-code trust.

## Phase 7 — ADR

- [ ] 7.1 Withdraw amendment 2a (registry file). Decision #2 stands.
- [ ] 7.2 Re-file the named-function/anchor finding under Decision #2 or "Enforcement, stated
      honestly" — not #4, which governs rule (c).
- [ ] 7.3 New ADR: per-run private scratch roots reaped by owner, over shared `/tmp` reaping gated
      on conjunctive evidence. **Record what shipped; do not re-litigate the cut reaper**
      (code-simplicity P3-13). Ordinal provisional; `/ship` re-verifies against `origin/main`.

## Phase 8 — Track

- [ ] 8.1 File the tracking issue; `Closes #<N>` in the PR body. Cross-ref #6734, #6789, #6713, #6760.
- [ ] 8.2 File: count-based reaper, redesigned after the source fix soaks (R3). **Include the
      measured size-floor evidence** — `SCRATCH_MIN_MB=100` vs a 372-byte largest artifact and
      0-of-11,172 over 1 MB — so the successor issue starts from why the size axis cannot see this
      leak class at all. Carry Phase 6-of-v2 (`tmpfs-guard.sh` logger + `-eq` on multi-line
      capture) here; nothing in this PR reads that journal (code-simplicity P2-9).
- [ ] 8.3 ~~File: fstab ceiling raise~~ — **DELETED.** Restored to this PR as Phase 6 above by
      operator decision.
- [ ] 8.4 File: ADR-129 D#4 accept re-evaluation across the bare-`mktemp` population — the upgrade
      trigger has fired (architecture P0-2).
- [ ] 8.5 File: `iac-plan-write-guard.sh` `echo | grep -q` race under `pipefail` (measured 9 deny /
      3 allow on identical 50 KB input). **Sibling pattern checks lose the same race fail-OPEN** —
      a guard that silently permits what it exists to block. Higher priority than this plan.
- [ ] 8.6 File: **`tmpfs-guard.test.sh` writes to the production journal.** 344 of 346 `Reaped`
      lines in 14 days came from fixture roots, making the guard's only telemetry unreadable.
      Route test-run logging to a fixture-scoped sink. **[SF]**
- [ ] 8.7 File: **the "nothing reapable found" alarm fired 94 times in 14 days into channels nobody
      reads** — `logger` (unwatched journal) and `notify-send` (no-ops under cron, no DBUS,
      `2>/dev/null || true`). Route to the observability layer per
      `hr-no-dashboard-eyeball-pull-data-yourself`. **[SF]**
- [ ] 8.8 Withdraw the #6760 harm-reduction comment — `skill-security-scan-` matches nothing; the
      real prefixes are `skill-scan-input-` / `skill-scan-results-`.
- [ ] 8.9 Capture the learning: an outcome detector beats a source-shape detector; a default name
      template is not a leak signature; and **a size-thresholded reaper cannot see a count-shaped
      leak**.

## Acceptance criteria corrections (apply before claiming any AC)

- [ ] AC2/AC17 must anchor on the **resolved scratch root**, not `/tmp` — Phase 5 moves the
      artifacts and makes the original counts vacuous. **But note AC2-corrected is still vacuous**
      as written: `rm -rf "$TMP_ROOT"` at exit makes any post-exit count 0 by construction
      (spec-flow P2). Assert *during* the run, or assert on `/tmp` non-growth instead.
- [ ] AC12: 12 files, not 10.
- [ ] AC7/T9 are unconstructable (disjoint namespaces) — drop with the reaper.
- [ ] AC1 restate as inspection; AC3 fold into AC4; AC4 wording is inverted; AC13 pin `env -u TMPDIR`;
      AC14 — **do not assert on amendment 2a text**, which 7.1 withdraws (code-simplicity P2-11).
- [ ] AC9-AC11 / T15-T19 reinstated for the restored Phase 6. T15 and T19 are the same assertion —
      keep one (code-simplicity P3-12).
- [ ] AC16 (post-merge live verification of the raised ceiling) has **no follow-through
      enrollment**; the soak script covers AC17 only. Either enroll it or drop the claim
      (spec-flow P1-9). **[SF]**
- [ ] Delete AC17 + its soak follow-through, rather than correcting them: the pass condition is a
      reap by the **deferred** count arm, i.e. new machinery proving a phase that is not shipping
      (code-simplicity P1-4).

## Irreversibility ledger — what is lost on misfire, and whether an AC would catch it

The plan's whole thesis is that every existing layer reported success while doing nothing. This
table is the same audit turned on the plan's OWN deletes. **Every row currently reads "No" or
"Partly" — closing these is the bar for `/work` being done, not a nice-to-have.**

| Path | Permanently lost on misfire | Detected today? |
|---|---|---|
| 3.1 `rm -rf "$TMP_ROOT"` | Synthesized fixtures only — **unless** late-binding (3.1b) or an empty/relocated root (3.1a) redirects it at the shared parent, in which case every concurrent suite's live scratch | **No** — AC2-corrected is self-declared vacuous |
| 4.2/4.4/4.5 per-suite reap | A concurrent run's or a backgrounded child's live scratch; surfaces as an ENOENT that reads as a test bug, not a reaper bug | **No** — no AC asserts a *foreign* root survives (4.5b adds one) |
| 6 fstab rewrite | Boot capability; plus the backups themselves via 6.6 | **Partly** — fixtures never touch the real file, so the symlink / cross-device / mode branches are untested by construction (6.4b), and AC16 has no follow-through enrollment |

**Standing rule for every delete in this PR:** on any ambiguity, leave the directory. A leak is
recoverable; a delete is not.
