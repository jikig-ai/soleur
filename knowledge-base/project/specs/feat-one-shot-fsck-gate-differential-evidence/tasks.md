---
feature: feat-one-shot-fsck-gate-differential-evidence
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-20-fix-workspaces-luks-fsck-gate-differential-evidence-plan.md
issue_ref: "Ref #6733"
---

# Tasks — differential + self-reporting git-fsck gate (workspaces-luks cutover)

## Phase 0 — Preconditions

- [ ] 0.1 Re-read the gate's content anchor on `origin/main`
      (`git show origin/main:apps/web-platform/infra/workspaces-cutover.sh | grep -n 'fsck --full'`)
      and confirm it is unchanged since the plan was written.
- [ ] 0.2 Measure the four `git fsck` exit-code semantics on a throwaway repo (foreign-uid rc,
      `-c safe.directory` rc, corrupted-loose-object rc + stderr, dangling-only rc). Paste the
      transcript into the PR body — never infer these.
- [ ] 0.3 Confirm `luks-monitor` is allowlisted in `apps/web-platform/infra/vector.toml`
      (no infra change expected).
- [ ] 0.4 Grep the loopback harness case-id namespace so the new `L6*` ids do not collide.

## Phase 1 — RED (failing tests first, `cq-write-failing-tests-before`)

- [ ] 1.1 Add Session D to `apps/web-platform/infra/workspaces-luks-loopback.test.sh` on the existing
      `new_session` helper; build real git-repo fixtures under `$SRC_DIR/workspaces/` and rsync them
      onto the mapper (mirroring L3's copy step).
- [ ] 1.2 L6a — clean both sides → rc 0, `classification=ok`.
- [ ] 1.3 L6b — copy-only object corruption → **aborts**, `classification=copy_corruption`, `first=`
      carries a real fsck error string.
- [ ] 1.4 L6c — same fault on both sides → **no abort**, `classification=preexisting`.
- [ ] 1.5 L6d — pre-existing fault on both sides **plus** a new dst-only fault → **aborts**,
      `classification=copy_corruption` (proves the error-line-set differential).
- [ ] 1.6 L6e — un-inspectable copy → **aborts**, `classification=probe_failed` (the H1 no-op trap).
- [ ] 1.7 L6f — source-only fault → no abort, `classification=src_only`, logged.
- [ ] 1.8 L6g — dst workspace with no src counterpart → **aborts**, `classification=dst_only`.
- [ ] 1.9 L6h — pathological fsck output → bounded rows/bytes, `truncated=1`.
- [ ] 1.10 L6i — mutation control: neuter the abort predicate in a copy of the cutover; L6b MUST flip
      green. Assert the `sed` landed before trusting the result.
- [ ] 1.11 L6j — workspace with no `.git` directory → `classification=skipped reason=no_git_dir`.
- [ ] 1.12 Run the suite; confirm L6a–L6j are RED. Record the red output for the PR body.

## Phase 2 — GREEN (implementation)

- [ ] 2.1 Extract the inline fsck loop into `verify_git_fsck_differential <src_root> <dst_root>`
      beside `verify_byte_identity`; add `fsck_baseline_source`, `_fsck_one`, `emit_fsck_row`.
      Call it **directly** in the main body (never in `$(…)`, a pipe, or a subshell).
- [ ] 2.2 Probe: `git -c safe.directory=<repo> -C <repo> fsck --full --no-progress`; per-repo scoping
      only (no wildcard, no `--global` write); **no** `--name-objects`; stdout/stderr to **separate**
      `mktemp` files; record rc.
- [ ] 2.3 Classification over (src_rc, dst_rc, error-line sets): `probe_failed` / `dst_only` /
      `copy_corruption` abort; `preexisting` / `src_only` / `ok` / `skipped` do not. Abort message
      names the count and points at the marker.
- [ ] 2.4 Emit the `SOLEUR_WORKSPACES_LUKS_FSCK` summary row + per-workspace rows (`ws=` last, every
      field `_vscrub`'d, `echo` + `logger -t "$LUKS_LOG_TAG"`), **before** any `rm` and **before**
      `die`. `emit_drift workspaces_luks_fsck_<classification>` on aborting classifications.
- [ ] 2.5 Add `FSCK_MARKER_CAP` (rows, default 40) and `FSCK_OUT_CAP` (bytes, default 200); emit
      aborting rows first so the cap cannot hide the explanation; log `… +N more`.
- [ ] 2.6 Insert `fsck_baseline_source "$MOUNT"` immediately after the bulk rsync step (pre-FREEZE),
      writing `<id>.rc` / `<id>.out` to a run-scoped `mktemp -d`; `baseline=missing` falls back to an
      inline source fsck at gate time (`baseline=inline`).
- [ ] 2.7 Dry-run honesty: baseline runs in **both** arms; the dst differential stays inside
      `DRY_RUN != 1`; add the explicit `(dry-run) source fsck baseline only; the differential gate
      does NOT run in this arm` log line. No short-circuit.

## Phase 3 — Verify

- [ ] 3.1 Loopback suite → `20 passed, 0 failed`, exit 0.
- [ ] 3.2 `bash -n` on both edited files.
- [ ] 3.3 `shellcheck` only if `infra-validation.yml` already runs it on these files (verify first).
- [ ] 3.4 Walk every Pre-merge AC (1–13) and record the command + output.

## Phase 4 — Learning & ship

- [ ] 4.1 Write `knowledge-base/project/learnings/<topic>.md` — the three-instance
      fail-closed-gate-discards-its-evidence pattern (C1 verify, G4 holder probe, fsck gate).
      Author picks the date at write time.
- [ ] 4.2 Measure `B_ALWAYS` before proposing any AGENTS.md rule; if at cap, land the principle in
      the constitution instead.
- [ ] 4.3 PR body: `Ref #6733` (never `Closes`), Phase 0.2 transcript, the freeze-budget cost note
      (~4.5 min in-freeze unchanged, ~4.5 min added pre-freeze) and the source-hoist ordering
      rationale.
