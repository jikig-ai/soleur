---
feature: feat-one-shot-fsck-gate-differential-evidence
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-20-fix-workspaces-luks-fsck-gate-differential-evidence-plan.md
issue_ref: "Ref #6733"
deepened: 2026-07-20
---

# Tasks — differential + self-reporting git-fsck gate (workspaces-luks cutover)

> **Deepen-pass corrections (v1 → v2).** The source-fsck **hoist was rejected as unsound** — both
> sides now fsck **concurrently inside the freeze**; there is no baseline directory and no
> `baseline=` field. `rc == 0` does **not** mean clean, so the set comparison is unconditional. The
> fsck report spans **both streams**. Linked worktrees and absolute alternates silently fsck the
> **wrong filesystem**. `--no-optional-locks` is required. `dst_only` is cut. See the plan's
> Enhancement Summary and Measured `git fsck` Semantics sections before starting.

## Phase 0 — Preconditions

- [ ] 0.1 Re-read the gate's content anchor on `origin/main`
      (`git show origin/main:apps/web-platform/infra/workspaces-cutover.sh | grep -n 'fsck --full'`).
- [ ] 0.2 The plan's Measured Semantics section already carries the exit-code/stream evidence
      (git 2.53.0). Re-measure only if the local git major version differs. Note in the PR body that
      this is **local** evidence — web-1's authoritative measurement is the advisory probe.
- [ ] 0.3 Confirm `luks-monitor` is allowlisted in `apps/web-platform/infra/vector.toml`.
- [ ] 0.4 `grep -nE '^\s*(ok|no) "L' …loopback.test.sh` — confirm the 10 existing ids, `L6*` free.
- [ ] 0.5 Locate the sourced-detection guard. **All four new functions go ABOVE it**; only the two
      call sites go below.

## Phase 1 — RED (failing tests first, `cq-write-failing-tests-before`)

- [ ] 1.1 Session D on the existing `new_session` helper. Fixtures: real `git init` repos,
      **`chown -R 1001:1001` both sides** (a root-owned fixture never exercises `safe.directory` and
      would go green for a reason that cannot hold in production), one workspace id containing a
      **space**, one non-repo directory, one linked worktree.
- [ ] 1.2 L6a — clean both sides → rc 0, `classification=ok`, summary `skipped=2` with
      `reason=worktree_pointer` and `reason=no_git_dir` distinguished; counts sum to `total`.
- [ ] 1.3 L6b — copy-only object corruption → **aborts**, `copy_corruption`, `copy_corruption` abort
      text, `first=` carries a real fsck error string.
- [ ] 1.4 L6c — same fault both sides → **no abort**, `preexisting`.
- [ ] 1.5 L6d — shared fault **plus** a dst-only fault → **aborts** `copy_corruption`; **and** no
      spurious dst-only line arises from the `$MOUNT` vs `$STAGING` prefix (normalization holds).
- [ ] 1.6 L6e — `probe_failed` **aborts**. Mechanism must be **root-proof**: dangling symlink for
      `.git/objects`, a `fatal:` rc-128 `.git/config`/`HEAD`, or `setpriv --reuid=1001`. A foreign
      uid will NOT work (the SUT's `safe.directory` defeats it) and `chmod 000` is a no-op under root.
- [ ] 1.7 L6f — broken `objects/info/alternates` on the copy only (measured: **rc 0** + `error:`
      lines) → gate **aborts** `copy_corruption`. Proves rc 0 does not short-circuit the comparison.
- [ ] 1.8 L6g — non-zero rc with an **empty** error set → **aborts** `unclassified`. Proves the
      classifier is total and fails closed.
- [ ] 1.9 L6h — truncation. Cheap fixture (many broken alternates entries, not a giant repo). Place
      the dst-only line **beyond** the caps: rows ≤ cap, `truncated=1`, **and the run still aborts**.
- [ ] 1.10 L6i — mutation control: `sed` the abort predicate vacuous in a cutover copy; L6b MUST flip
      green. Assert the `sed` landed before trusting the result.
- [ ] 1.11 L6j — advisory probe: emits `phase=advisory` rows; aborts **pre-freeze** only when *every*
      source repo is `probe_failed`; dry-run output contains `(dry-run) source fsck advisory probe
      only` and **no** `phase=gate` row.
- [ ] 1.12 Run the suite; confirm L6a–L6j RED. Record for the PR body.

## Phase 2 — GREEN

- [ ] 2.1 Add `fsck_advisory_probe`, `verify_git_fsck_differential`, `_fsck_side`, `_fsck_one`,
      `emit_fsck_row` above the sourced-detection guard. Entry points called **directly** in the main
      body (never `$(…)`/pipe/subshell) so `die` reaches the EXIT trap. **Invariant: `_fsck_one` and
      `_fsck_side` never call `die`** — they return and write to files.
- [ ] 2.2 Probe:
      `git --no-optional-locks -c safe.directory="<ABS worktree>" -C "<repo>" fsck --full
      --no-progress --no-dangling --no-reflogs >"$raw_out" 2>"$raw_err"`.
      Every element load-bearing: `--no-optional-locks` (must not rewrite `.git/index` on `$STAGING`
      after C1 certified it); `-C` never `--git-dir` (relative vs absolute object paths); absolute
      per-repo `safe.directory` (the `.git` form and relative forms both still return rc 128); **no**
      `--name-objects` (leaks in-repo file paths); separate streams (a missing object is rc 2 with
      empty stderr); capture to files, bounded **after** write — never `| head -c` (rc 141 under
      `pipefail`).
- [ ] 2.2b Cross-filesystem escape detection **before** probing a dst repo: `.git` is a file
      (linked worktree → follows its absolute `gitdir:` back to the source volume) →
      `skipped reason=worktree_pointer`; absolute `objects/info/alternates` outside the root →
      `skipped reason=alternates_escape`. Summary counters only, no per-workspace rows. Log loudly
      when non-zero.
- [ ] 2.3 Normalize both sides identically (merge streams, strip the root and **both** mount
      prefixes, drop `dangling|unreachable`, `sort -u`), then classify **in the plan's row order**:
      `skipped` → `probe_failed` → `unclassified` (rc≠0 + empty set) → `probe_failed`(src_absent) →
      `copy_corruption` → `preexisting` → `src_only` → `ok` (empty set **and** rc 0 both sides) →
      **default `unclassified` → abort**. `probe_failed` MUST precede the set comparison (under H1 the
      `fatal:` line embeds the differing prefix and would otherwise read as dst-only on 100% of
      workspaces).
- [ ] 2.4 **Per-classification abort text** (three distinct strings — a generic "the copy regressed"
      misattributes under H1). Summary + per-workspace marker rows per the plan's field list, `ws=`
      last, every field `_vscrub`'d, `echo` + `logger -t "$LUKS_LOG_TAG"`, `first=` defined per
      classification. `emit_drift` fires **once per distinct aborting classification per run**.
      Emit before cleanup: register the capture tempdir with the existing EXIT trap, don't `rm` inline.
- [ ] 2.5 `FSCK_MARKER_CAP` (rows, 40) + `FSCK_OUT_CAP` (bytes, 256). **Caps apply to emission only;
      comparison always consumes the full capture.** Aborting rows emitted first; `… +N more`.
- [ ] 2.6 `fsck_advisory_probe "$MOUNT"` after the bulk rsync, **outside** the `DRY_RUN` gate (both
      arms), under `ionice -c3 nice -n 10`, `phase=advisory`. Aborts **pre-freeze** (before
      `FREEZE_HELD=1`) iff every probed source repo is `probe_failed` — use the script's existing
      pre-freeze die language ("no freeze was held; NO rollback is needed").
- [ ] 2.7 Gate call inside `DRY_RUN != 1`, both sides concurrent (`_fsck_side … & _fsck_side … &
      wait`). Dry-run log line: `(dry-run) source fsck advisory probe only; the differential gate
      does NOT run in this arm`. No short-circuit.
- [ ] 2.8 Summary invariant: counts sum to `total`; `total + skipped` cross-checked against
      `G2_COUNT`; `total=0` with `G2_COUNT > 0` **aborts** (instrument failure, not emptiness).

## Phase 3 — Verify

- [ ] 3.1 Loopback suite → `20 passed, 0 failed`, exit 0.
- [ ] 3.2 `bash -n` on both edited files.
- [ ] 3.3 `shellcheck` only if `infra-validation.yml` already runs it on these files (verify first).
- [ ] 3.4 Walk Pre-merge ACs 1–9, recording command + output.

## Phase 4 — Learning & ship

- [ ] 4.1 Write `knowledge-base/project/learnings/<topic>.md` — two learnings: (a) the three-instance
      fail-closed-gate-discards-its-evidence pattern; (b) the `git fsck` semantics every integrity
      gate gets wrong (rc is a bitmask, rc 0 ≠ clean, report spans both streams, `--name-objects`
      leaks paths, a linked worktree fsck'd at a copied path reads the **original** filesystem).
      Author picks the date at write time.
- [ ] 4.2 Measure `B_ALWAYS` before proposing any AGENTS.md rule; if at cap, land it in the
      constitution instead.
- [ ] 4.3 PR body: `Ref #6733` (never `Closes`); the Measured Semantics transcript flagged as **local**
      evidence; the freeze-budget statement (~4.5 min serial-one-side → ~5 min concurrent-two-sides
      against ≤20 min) and why the v1 hoist was rejected as unsound; the advisory probe's ~4.5 min of
      pre-freeze read I/O under `ionice`.
