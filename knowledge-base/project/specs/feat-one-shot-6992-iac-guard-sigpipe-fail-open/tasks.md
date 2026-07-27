<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  ACK JUSTIFICATION: no infrastructure is introduced. Operator-SSH / systemd /
  secret-write / crontab literals appear only as citations of the detection
  regexes belonging to the guard under repair. See the plan's "Infrastructure (IaC)".
-->
---
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-27-fix-guard-hygiene-sigpipe-and-tmpfs-reaper-plan.md
closes: [6992, 6991]
revision: v2 (post plan-review)
---

# Tasks — guard hygiene (#6992 + #6991)

ONE PR closing both issues. **Read the plan's "Plan Review Revisions" table before starting** —
three of v1's design claims were falsified by measurement, and two would have shipped active
harm. In particular: **do NOT remove `SCRATCH_MIN_MB`** (it would delete live socket-held
directories) and **do NOT rescan the whole document on Edit** (274 existing files would be
denied on every edit).

## Phase 0 — Re-verify premises (blocking; no edits)

- [ ] 0.1 Producer-class probe, clean shell (`env -i PATH=/usr/bin:/bin bash --noprofile --norc`).
      Assert `grep` is `/usr/bin/grep` (GNU). Builtin `echo` → 0 failures over 40 runs at 1 MB;
      `yes | grep -q y` → PIPESTATUS `141 0`; external `cat` of a 1 KB file, match-at-top →
      non-zero failures over 20 runs.
- [ ] 0.2 Edit-scope: ack outside chunk → deny; ack inside chunk → allow.
- [ ] 0.3 MultiEdit bypass: confirm `.claude/settings.json`'s matcher for this hook lacks
      `MultiEdit` while sibling hooks include it.
- [ ] 0.4 **Socket liveness blindness** — pick a live socket-holding directory under `/tmp`;
      confirm it clears ownership, recursive age, denylist, and `_INUSE_TOP` liveness. If this
      no longer reproduces, Phase 6's ordering assumption changes. DO NOT SKIP.
- [ ] 0.5 Cost model: time batched `du --files0-from` vs per-candidate recursive `find` over the
      current candidate set; confirm the per-candidate form extrapolates past the cron interval.
- [ ] 0.6 Trigger signal: record `df -h /tmp`, `df -i /tmp`, and top-level entry count. Confirm
      inode % is far below any plausible high-water mark.
- [ ] 0.7 Paste probe output into the evidence block below.

**Gate:** if 0.1, 0.2, or 0.4 does not reproduce, STOP and re-diagnose.

## Phase 1 — Sweep and record (AC-A3)

- [ ] 1.1 `git grep -nE '\|[[:space:]]*grep[[:space:]]+-q'` over `.claude/hooks/`, `scripts/`,
      `plugins/`.
- [ ] 1.2 Record per non-test hit: file:line, `pipefail` status, **producer class (builtin vs
      external)**, provenance, failure direction, live/inert verdict.
- [ ] 1.3 Flag every `if ! X | grep -q P; then <early-exit>` site — the inversion makes the gate
      skip its own check (FAILS OPEN).
- [ ] 1.4 Write `knowledge-base/project/specs/<branch>/sweep.md`.

## Phase 1.5 — Land failing tests RED (before Phase 2)

- [ ] 1.5.1 Write T3 (Edit + ack elsewhere → expect allow) and T4 (MultiEdit + violation →
      expect deny) against UNMODIFIED code; confirm both FAIL; commit at that state so AC-A4 can
      be demonstrated at both commits.

## Phase 2 — Fix the real #6992 defects (load-bearing)

- [ ] 2a.1 Add `MultiEdit` to this hook's matcher in `.claude/settings.json` (match its three
      siblings) and to the hook's `tool_name` case. **This is the largest fail-open in Part A
      and is not in the issue.**
- [ ] 2a.2 Fold `edits[]` into the scanned text for MultiEdit.
- [ ] 2b.1 Check the ack literal against `new_string` AND against the on-disk file:
      `grep -qF "$ack" <<<"$content" || { [ -f "$file_path" ] && grep -qF "$ack" "$file_path"; }`
- [ ] 2b.2 Resolve a relative `file_path` against the existing `PROJECT_DIR`.
- [ ] 2b.3 Guard the file read so a failure cannot trip `set -e` and change the hook's
      "exit 0 always" contract.
- [ ] 2.4 Correct the header's "Hook exit code: 0 always" comment against the final control flow.
- [ ] 2.5 Confirm T3 and T4 now pass (GREEN).
- [ ] **DO NOT** implement whole-document reconstruction. See the plan's "Not taken" note and
      Phase 10.4's deferred issue.

## Phase 3 — Fix the genuinely live race sites

- [ ] 3.1 Convert external-producer sites: herestring when the value is already a variable;
      otherwise capture first, or `[ "$(cmd | grep -c P || true)" -gt 0 ]`. Never `grep -qo`.
- [ ] 3.2 Sites (finalise from Phase 1): `.claude/hooks/pre-merge-rebase.sh`,
      `.claude/hooks/brand-hex-commit-gate.sh`, `.claude/hooks/skill-security-scan.sh`,
      `.claude/hooks/skill-context-queries.sh`, `scripts/update-ci-required-ruleset.sh`,
      `scripts/create-ci-required-ruleset.sh`, `scripts/watch-live-verify-pass.sh`,
      `plugins/soleur/skills/review/scripts/emit-review-trailer.sh`.
- [ ] 3.3 Convert the 7 builtin sites in `iac-plan-write-guard.sh` (AC-A1).
- [ ] 3.4 Verify each touched hook's EXISTING test suite passes unchanged (AC-A7).

## Phase 4 — Regression tests (AC-A2, A4, A5, A6)

- [ ] 4.1 T1 — ≥64 KB body, match near top → deny on every one of ≥30 runs. Annotate:
      issue-requested; passes pre- and post-fix, so it verifies no-regression, not the fix.
- [ ] 4.2 T2 — same body + ack → allow on ≥30 runs.
- [ ] 4.3 T5 — assert `grep` resolves to a GNU grep BINARY, not a shell function; abort loudly.
- [ ] 4.4 T6 — producer-class behaviour (`cat | grep -q` can fail, `echo | grep -q` does not).
      This is the ONE executable home for that measurement; do not restate it as prose elsewhere.

## Phase 5 — Record and nudge (reduced per PR-8)

- [ ] 5.1 Commit `sweep.md` as the AC-A3 record.
- [ ] 5.2 Add a minimal baseline assertion to the existing `scripts/test-all.sh` surface that the
      external-producer count does not grow. NO new script, NO bespoke allowlist format.
- [ ] 5.3 Correct the `work/SKILL.md` rule text to name the producer-class distinction.
- [ ] 5.4 Verify the assertion fails when a new external-producer site is injected (AC-A8).

---

# Part B — order is 8 → 6 → 7 (NOT 6 → 7 → 8)

Phase 6 consumes `guard_log()` and the usage seam from Phase 8, and shipping 6 first actively
regresses production (new logging lands in the captured value and triggers the hard abort).

## Phase 8 — Log sink, telemetry, return contract (FIRST)

- [ ] 8.1 Add `guard_log()` + `TMPFS_GUARD_LOG_SINK` seam (default `logger`), replacing all three
      hard-coded `logger -t tmpfs-guard` sites.
- [ ] 8.2 Point the test harness at a fixture-scoped sink under its own `TESTROOT` (AC-B5).
- [ ] 8.3 Route per-entry reap detail (live and `DRY_RUN`) through `guard_log` instead of `echo`.
- [ ] 8.4 **Change the return contract to globals.** `reap_scratch_entries` / `reap_output_files`
      set `REAP_COUNT` / `REAP_MB` and `return 0`; `main` reads globals and drops the command
      substitution entirely. No sanitize needed; if one survives it must log loudly, never
      silently default to 0.
- [ ] 8.5 Note the real severity: today this is a HARD ABORT under `set -u` (`tmpfs` parsed as an
      unbound variable), so `main` exits 1 and the high-usage alarm branch never runs — on
      precisely the run that reaped something at ≥70% usage.
- [ ] 8.6 Emit a per-run liveness line so "silent" and "not running" differ.
- [ ] 8.7 Make the usage probe hermetic (today `df` runs against a `TESTROOT` on the real `/tmp`).
- [ ] 8.8 Add `flock` — the guard has none, so overlapping runs would race each other's deletes.

## Phase 6 — Reaper that sees a count-shaped leak, safely

- [ ] 6a.1 **Parse `/proc/net/unix`** into `_INUSE_TOP`. A unix-domain socket fd readlinks to
      `socket:[inode]`, so the existing `/proc/<pid>/fd` walk is architecturally blind to
      socket-held directories. One file read.
- [ ] 6a.2 Run `fuser` on directories too (drop the `[[ ! -d ]]` gate).
- [ ] 6a.3 Widen the protected denylist against a LIVE `/tmp` listing — at minimum
      `com.google.Chrome.*`, `.org.chromium.*`, `dbus-*`, `pulse-*`, `.mount_*`, `tmux-*`,
      `ssh-*`, `.X*-lock`. Do not assume the current 9-entry list is complete.
- [ ] 6a.4 Correct the SAFETY header's "no open file handle" claim, which is overstated.
- [ ] **6a is a HARD PREREQUISITE. Nothing else in Phase 6 may land before it.**
- [ ] 6b.1 **Reduce** the size floor (order 1 MB) under pressure — do NOT remove it. Sockets and
      lockfiles are ~0 bytes, so a tiny floor preserves the protection while still catching the
      15,000 × 372-byte class.
- [ ] 6c.1 Trigger on **top-level entry count** under `$TMP_ROOT` (one `find | wc -l`), NOT
      `df -i` (measured 7% while the leak is present — it would never fire).
- [ ] 6c.2 Pin the threshold against measured current state so engagement is proven.
- [ ] 6d.1 KEEP the batched `du --files0-from` — it is ~2.8 s at full scale and supplies the
      `size_mb` that per-entry log lines and `reaped_mb` accounting need.
- [ ] 6d.2 Batch the recursive-age check: one
      `find "$TMP_ROOT" -mindepth 1 -mmin -N -printf '%H\n' | sort -u` pass instead of ~17,900
      per-candidate forks (measured ~316 s, exceeding the cron interval).
- [ ] 6e.1 Encode the age-relaxation ceilings: (i) pressure-only; (ii) ownership + liveness never
      relaxed — 6a is what makes this true; (iii) per-run cap on entries reaped; (iv) every
      pressure reap logged individually via `guard_log`.
- [ ] 6.7 Keep `find … -delete` (never `rm -rf`).
- [ ] 6.8 Tests: socket-held fixture NOT reaped (AC-B2); ~10,000 tiny files reaped under
      pressure, untouched without (AC-B3); open-fd and foreign-uid trees never reaped; per-run
      cap holds; wall clock well inside 5 minutes with the bound recorded (AC-B4).

## Phase 7 — Alarm that reaches a human

- [ ] 7.1 Append to a durable, size-capped alarm state file at a fixed path **outside `/tmp`**:
      timestamp, usage %, entry count, reap counts.
- [ ] 7.2 Surface a one-line summary at `SessionStart` by extending the EXISTING hook.
- [ ] 7.3 **Emit nothing when the state file records zero alarms** — a healthy machine must not
      tax every session's context.
- [ ] 7.4 **Delete `notify-send`** from all three call sites. Do not keep it as a hedge.
- [ ] **DO NOT** add threshold-triggered agent-filed GitHub issues (cut at review: no threshold,
      no dedupe key, no code, no AC).

## Phase 9 — Correct the session-loaded doc claim

- [ ] 9.1 `plugins/soleur/skills/work/SKILL.md` — remove the false claim that the cron reaper
      bounds abandoned-scratch growth. It is loaded into EVERY agent session.
- [ ] Cut at review: corrections to the merged 2026-07-27 and 2026-07-22 plan documents.

## Phase 10 — Verify, capture, ship

- [ ] 10.1 `bash scripts/test-all.sh` passes (AC-X2).
- [ ] 10.2 Confirm `scripts/tmpfs-guard.sh` is still a drop-in at its existing path; NO crontab
      change is prescribed.
- [ ] 10.3 Write the learning file (directory + topic only; author picks the date): producer-class
      discriminator; race fires at 1 KB, not size-gated; the ugrep shim hides it from manual
      testing; scanning `new_string` scans a fragment; a PreToolUse matcher missing `MultiEdit`
      silently disables the hook; a size floor can be load-bearing safety by accident; "reviewed
      direction" is a hypothesis about the codebase, not a fact.
- [ ] 10.4 File deferred tracking issues: (a) whole-document delta scanning for the guard — record
      the `replace_all` / glob-safe-substitution / MultiEdit-sequencing requirements so the next
      attempt does not rediscover them; (b) migrate bulk `mktemp` sites onto
      `soleur_scratch_root()` and register `scripts/lib/scratch-root.test.sh`; (c) the full
      external-producer lint with a per-site allowlist.
- [ ] 10.5 PR body contains `Closes #6992` AND `Closes #6991` (AC-X1).

## Evidence block (fill during Phase 0)

```text
<paste Phase 0 probe output here>
```
