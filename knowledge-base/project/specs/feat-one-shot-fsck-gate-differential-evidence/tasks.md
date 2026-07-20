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

> **Post-merge corrections (v2 → v3), 2026-07-20.** Phases 0–2 shipped in #6745; 3.2/3.3 and the
> Phase 4 items are closed by #6759. Three items below stated rules the shipped code does NOT have,
> and are corrected in place rather than ticked as written — an unreconciled task list is the same
> "asserts a property the code lacks" defect this feature exists to remove:
>
> - **1.11 / 2.6 — the advisory probe's threshold.** Both said "aborts pre-freeze only when *every*
>   source repo is `probe_failed`". The F4 review finding replaced that with **abort on ANY** before
>   #6745 merged: run 29725194755 failed on 8 of 10, so an all-or-nothing threshold would have gone
>   green, held the freeze, taken the outage and aborted at the gate anyway. This stale wording
>   survived into a SUT comment too, where it sat directly above the new rule and made test case L6j
>   read as a test-vs-SUT design contradiction; #6759 removed it from both.
> - **1.1 — the `chown -R 1001:1001` fixture rationale.** The premise ("exercises `safe.directory`")
>   does not hold on a GitHub-hosted runner: uid 1001 is the `runner` user, i.e. `$SUDO_UID` once the
>   suite self-elevates, and git accepts `SUDO_UID` as an owner. So uid 1001 was indeed the wrong
>   fixture — but re-chowning to 65534 did not make the refusal fire either, and #6759 spent three
>   commits guessing why before `L6k-CAP` measured it: the runner image ships `safe.directory = *` in
>   `/etc/gitconfig`, which allowed every directory regardless of uid. With ambient config
>   neutralized, uid 65534 refuses exactly as the design assumed — `rc=128 fatal: detected dubious
>   ownership`, no `GIT_TEST_*` knob needed. The corrected fixture rationale is therefore: a foreign
>   uid IS the right mechanism, and it must be paired with `GIT_CONFIG_SYSTEM/GLOBAL=/dev/null` or
>   the ambient allow-list silently defeats it. L6k arm (i) still synthesizes (deterministic
>   classifier test); `L6m` carries the load-bearing proof against real git and PASSES in CI.
> - **3.1 — the expected case count.** Said `20 passed`. The suite carried **24** executed cases at
>   #6745 and **25** after #6759 adds L6l (confirmed in CI: `25 passed, 0 failed`). Two further ids,
>   `L6k-CAP` and `L6m`, are CONDITIONAL on the host being able to produce a real ownership refusal,
>   so the total is **25 or 27**, never 26. Any future "expected N" must name which it means.
>   **Measured on run 29746786010: 27 passed, 0 failed** — both conditional cases assert on the
>   runner once ambient git config is neutralized.
> - **The cause of the H1 mystery, measured rather than guessed (added after the first green run).**
>   Three separate explanations were advanced across #6745 and #6759 for why the ownership refusal
>   never fired — the fixture uid, then git 2.54.0-vs-2.53.0, then "the runner simply cannot". All
>   three were wrong. `L6k-CAP` printed the answer on its first CI run: the GitHub runner image ships
>   a SYSTEM gitconfig containing `safe.directory = *`, so git allowed every directory and no
>   ownership check could fire. Neutralizing `GIT_CONFIG_SYSTEM/GLOBAL` makes the refusal fire, which
>   makes the load-bearing `-c safe.directory=` proof runnable in CI after all — it is now `L6m`,
>   and it PASSES: `rc=128 fatal: detected dubious ownership` fires from genuine foreign-uid
>   ownership alone, with no `GIT_TEST_*` knob involved. H1 is proven against real git in CI.

## Phase 0 — Preconditions

- [x] 0.1 Re-read the gate's content anchor on `origin/main`
      (`git show origin/main:apps/web-platform/infra/workspaces-cutover.sh | grep -n 'fsck --full'`).
- [x] 0.2 The plan's Measured Semantics section already carries the exit-code/stream evidence
      (git 2.53.0). Re-measure only if the local git major version differs. Note in the PR body that
      this is **local** evidence — web-1's authoritative measurement is the advisory probe.
- [x] 0.3 Confirm `luks-monitor` is allowlisted in `apps/web-platform/infra/vector.toml`.
- [x] 0.4 `grep -nE '^\s*(ok|no) "L' …loopback.test.sh` — confirm the 10 existing ids, `L6*` free.
- [x] 0.5 Locate the sourced-detection guard. **All four new functions go ABOVE it**; only the two
      call sites go below.

## Phase 1 — RED (failing tests first, `cq-write-failing-tests-before`)

- [x] 1.1 Session D on the existing `new_session` helper. Fixtures: real `git init` repos,
      **`chown -R 1001:1001` both sides** (a root-owned fixture never exercises `safe.directory` and
      would go green for a reason that cannot hold in production), one workspace id containing a
      **space**, one non-repo directory, one linked worktree.
- [x] 1.2 L6a — clean both sides → rc 0, `classification=ok`, summary `skipped=2` with
      `reason=worktree_pointer` and `reason=no_git_dir` distinguished; counts sum to `total`.
- [x] 1.3 L6b — copy-only object corruption → **aborts**, `copy_corruption`, `copy_corruption` abort
      text, `first=` carries a real fsck error string.
- [x] 1.4 L6c — same fault both sides → **no abort**, `preexisting`.
- [x] 1.5 L6d — shared fault **plus** a dst-only fault → **aborts** `copy_corruption`; **and** no
      spurious dst-only line arises from the `$MOUNT` vs `$STAGING` prefix (normalization holds).
- [x] 1.6 L6e — `probe_failed` **aborts**. Mechanism must be **root-proof**: dangling symlink for
      `.git/objects`, a `fatal:` rc-128 `.git/config`/`HEAD`, or `setpriv --reuid=1001`. A foreign
      uid will NOT work (the SUT's `safe.directory` defeats it) and `chmod 000` is a no-op under root.
- [x] 1.7 L6f — broken `objects/info/alternates` on the copy only (measured: **rc 0** + `error:`
      lines) → gate **aborts** `copy_corruption`. Proves rc 0 does not short-circuit the comparison.
- [x] 1.8 L6g — non-zero rc with an **empty** error set → **aborts** `unclassified`. Proves the
      classifier is total and fails closed.
- [x] 1.9 L6h — truncation. Cheap fixture (many broken alternates entries, not a giant repo). Place
      the dst-only line **beyond** the caps: rows ≤ cap, `truncated=1`, **and the run still aborts**.
- [x] 1.10 L6i — mutation control: `sed` the abort predicate vacuous in a cutover copy; L6b MUST flip
      green. Assert the `sed` landed before trusting the result.
- [x] 1.11 L6j — advisory probe: emits `phase=advisory` rows; aborts **pre-freeze** on **ANY**
      `probe_failed` source repo (corrected v3 — was "only when *every*"; see the note above), each
      arm naming its count (`1 of 2`, `2 of 2`) and the no-rollback language; dry-run output contains
      `(dry-run) source fsck advisory probe only` and **no** `phase=gate` row.
- [x] 1.12 Run the suite; confirm L6a–L6j RED. Record for the PR body.

## Phase 2 — GREEN

- [x] 2.1 Add `fsck_advisory_probe`, `verify_git_fsck_differential`, `_fsck_side`, `_fsck_one`,
      `emit_fsck_row` above the sourced-detection guard. Entry points called **directly** in the main
      body (never `$(…)`/pipe/subshell) so `die` reaches the EXIT trap. **Invariant: `_fsck_one` and
      `_fsck_side` never call `die`** — they return and write to files.
- [x] 2.2 Probe:
      `git --no-optional-locks -c safe.directory="<ABS worktree>" -C "<repo>" fsck --full
      --no-progress --no-dangling --no-reflogs >"$raw_out" 2>"$raw_err"`.
      Every element load-bearing: `--no-optional-locks` (must not rewrite `.git/index` on `$STAGING`
      after C1 certified it); `-C` never `--git-dir` (relative vs absolute object paths); absolute
      per-repo `safe.directory` (the `.git` form and relative forms both still return rc 128); **no**
      `--name-objects` (leaks in-repo file paths); separate streams (a missing object is rc 2 with
      empty stderr); capture to files, bounded **after** write — never `| head -c` (rc 141 under
      `pipefail`).
- [x] 2.2b Cross-filesystem escape detection **before** probing a dst repo: `.git` is a file
      (linked worktree → follows its absolute `gitdir:` back to the source volume) →
      `skipped reason=worktree_pointer`; absolute `objects/info/alternates` outside the root →
      `skipped reason=alternates_escape`. Summary counters only, no per-workspace rows. Log loudly
      when non-zero.
- [x] 2.3 Normalize both sides identically (merge streams, strip the root and **both** mount
      prefixes, drop `dangling|unreachable`, `sort -u`), then classify **in the plan's row order**:
      `skipped` → `probe_failed` → `unclassified` (rc≠0 + empty set) → `probe_failed`(src_absent) →
      `copy_corruption` → `preexisting` → `src_only` → `ok` (empty set **and** rc 0 both sides) →
      **default `unclassified` → abort**. `probe_failed` MUST precede the set comparison (under H1 the
      `fatal:` line embeds the differing prefix and would otherwise read as dst-only on 100% of
      workspaces).
- [x] 2.4 **Per-classification abort text** (three distinct strings — a generic "the copy regressed"
      misattributes under H1). Summary + per-workspace marker rows per the plan's field list, `ws=`
      last, every field `_vscrub`'d, `echo` + `logger -t "$LUKS_LOG_TAG"`, `first=` defined per
      classification. `emit_drift` fires **once per distinct aborting classification per run**.
      Emit before cleanup: register the capture tempdir with the existing EXIT trap, don't `rm` inline.
- [x] 2.5 `FSCK_MARKER_CAP` (rows, 40) + `FSCK_OUT_CAP` (bytes, 256). **Caps apply to emission only;
      comparison always consumes the full capture.** Aborting rows emitted first; `… +N more`.
- [x] 2.6 `fsck_advisory_probe "$MOUNT"` after the bulk rsync, **outside** the `DRY_RUN` gate (both
      arms), under `ionice -c3 nice -n 10`, `phase=advisory`. Aborts **pre-freeze** (before
      `FREEZE_HELD=1`) when **ANY** probed source repo is `probe_failed` (corrected v3 — was "iff
      every"; see the note above) — use the script's existing pre-freeze die language ("no freeze was
      held; NO rollback is needed").
- [x] 2.7 Gate call inside `DRY_RUN != 1`, both sides concurrent (`_fsck_side … & _fsck_side … &
      wait`). Dry-run log line: `(dry-run) source fsck advisory probe only; the differential gate
      does NOT run in this arm`. No short-circuit.
- [x] 2.8 Summary invariant: counts sum to `total`; `total + skipped` cross-checked against
      `G2_COUNT`; `total=0` with `G2_COUNT > 0` **aborts** (instrument failure, not emptiness).

## Phase 3 — Verify

- [x] 3.1 Loopback suite → **`27 passed, 0 failed`, exit 0** (run 29746786010, sha d0ad9b3b9): 25
      unconditional + L6k-CAP + L6m, both of which assert because the runner CAN produce H1 once
      ambient git config is neutralized. Corrected v3: the stated `20` never matched the
      suite. #6745 merged at 21/3; #6759 took it to 23/1, then added L6l and the ANY-vs-ALL
      two-workspace fixture. This is a **CI-only** verification: the suite requires root + loopback +
      dm-crypt and self-elevates, so `deploy-script-tests` on the PR is the authoritative channel.
      Read its result before merging — #6745 merged while this suite was red for ~15 minutes because
      it is not a required check (tracked in #6766).
- [x] 3.2 `bash -n` on both edited files.
- [x] 3.3 `shellcheck` only if `infra-validation.yml` already runs it on these files (verify first).
- [x] 3.4 Walk Pre-merge ACs 1–9, recording command + output.

## Phase 4 — Learning & ship

- [x] 4.1 Write `knowledge-base/project/learnings/<topic>.md` — two learnings: (a) the three-instance
      fail-closed-gate-discards-its-evidence pattern; (b) the `git fsck` semantics every integrity
      gate gets wrong (rc is a bitmask, rc 0 ≠ clean, report spans both streams, `--name-objects`
      leaks paths, a linked worktree fsck'd at a copied path reads the **original** filesystem).
      Author picks the date at write time.
- [x] 4.2 Measure `B_ALWAYS` before proposing any AGENTS.md rule; if at cap, land it in the
      constitution instead.
      **v3 outcome:** routed by `cq-agents-md-tier-gate`, not by budget. The lesson (threshold
      coverage; per-case verdicts over pass counts; assert WHICH guard) is **domain-scoped to test
      design**, so the gate says edit the owning artifact and never AGENTS.md. Landed as a defect
      class in `plugins/soleur/skills/review/SKILL.md`, alongside every sibling learning it relates
      to. No AGENTS.md edit proposed, so no B_ALWAYS measurement was required.
- [x] 4.3 PR body: `Ref #6733` (never `Closes`); the Measured Semantics transcript flagged as **local**
      evidence; the freeze-budget statement (~4.5 min serial-one-side → ~5 min concurrent-two-sides
      against ≤20 min) and why the v1 hoist was rejected as unsound; the advisory probe's ~4.5 min of
      pre-freeze read I/O under `ionice`.
