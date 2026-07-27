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
---

# Tasks — guard hygiene (#6992 + #6991)

Ship as ONE PR closing both issues. Phases are independently revertible.

## Phase 0 — Re-verify every premise (blocking; no edits)

- [ ] 0.1 Producer-class probe in a clean non-interactive shell
      (`env -i PATH=/usr/bin:/bin HOME="$HOME" bash --noprofile --norc`). Assert `grep`
      resolves to `/usr/bin/grep` (GNU). Confirm: builtin `echo` → 0 failures over 40 runs at
      1 MB; `yes | grep -q y` → PIPESTATUS `141 0`; external `cat` of a 1 KB file with
      match-at-top → non-zero failure count over 20 runs.
- [ ] 0.2 Hook end-to-end, 5 arms × 12 runs (`Write` × {violation, clean, clean+ack,
      violation+ack}, plus 1 KB clean). Expect 12/12 correct in every arm.
- [ ] 0.3 Edit-scope probe: ack outside chunk → deny; ack inside chunk → allow.
- [ ] 0.4 `command -v vector` absent; `tmpfs-guard` absent from
      `apps/web-platform/infra/vector.toml`; `gh auth status` fails under `env -i PATH=/usr/bin:/bin`.
- [ ] 0.5 Re-count `mktemp`: total command-position invocations, bare count, `-t` count,
      max `-t` prefix frequency (assert 1).
- [ ] 0.6 Confirm `scripts/lib/scratch-root.sh` still has zero production callers.
- [ ] 0.7 Paste all probe output into this file's evidence block (satisfies AC-X3).

**Gate:** if 0.1 or 0.3 does not reproduce, STOP and re-diagnose. Do not build on a stale premise.

## Phase 1 — Sweep and record (AC-A3)

- [ ] 1.1 Run `git grep -nE '\|[[:space:]]*grep[[:space:]]+-q'` over `.claude/hooks/`,
      `scripts/`, `plugins/` (wider than the issue's glob).
- [ ] 1.2 For each non-test hit record: file:line, `pipefail` status, **producer class
      (builtin vs external)**, producer provenance, failure direction, live/inert verdict.
- [ ] 1.3 Flag every `if ! X | grep -q P; then <early-exit>` site — the inversion makes the
      gate skip its own check (FAILS OPEN).
- [ ] 1.4 Write `knowledge-base/project/specs/<branch>/sweep.md`.

## Phase 2 — Fix the real #6992 defect: Edit scan scope (load-bearing)

- [ ] 2.1 Write the failing test first (T3, see 4.3) — RED before any source edit.
- [ ] 2.2 In `.claude/hooks/iac-plan-write-guard.sh`, for `Edit`: read the file at
      `tool_input.file_path`, apply `old_string`→`new_string` in memory, scan the result.
      `Write` path unchanged.
- [ ] 2.3 On reconstruction failure (new file, unreadable, ambiguous match): fall back to
      scanning `new_string` alone AND name the degradation in the deny reason. A degraded
      scan must never look like a full one.
- [ ] 2.4 Correct the header comment's "Hook exit code: 0 always" claim against the fixed
      control flow.
- [ ] 2.5 Confirm T3 now passes (GREEN) and T4 passes.

## Phase 3 — Fix the genuinely live race sites

- [ ] 3.1 Convert external-producer sites to a non-racing form: herestring
      (`grep -q P <<<"$var"`) when the value is already a variable; otherwise capture first,
      or use `[ "$(cmd | grep -c P || true)" -gt 0 ]`. Never `grep -qo`.
- [ ] 3.2 Sites (finalise from Phase 1): `.claude/hooks/pre-merge-rebase.sh`,
      `.claude/hooks/brand-hex-commit-gate.sh`, `.claude/hooks/skill-security-scan.sh`,
      `.claude/hooks/skill-context-queries.sh`, `scripts/update-ci-required-ruleset.sh`,
      `scripts/create-ci-required-ruleset.sh`, `scripts/watch-live-verify-pass.sh`,
      `plugins/soleur/skills/review/scripts/emit-review-trailer.sh`.
- [ ] 3.3 Convert the 7 builtin-producer sites in `iac-plan-write-guard.sh` (hygiene; inert
      today, but the file is the issue's subject) — satisfies AC-A1.
- [ ] 3.4 Verify surrounding control flow is unchanged at every site: `&&` chaining, `!`
      inversion, and exit paths must be byte-identical in intent. Read the diff; a grep count
      is not sufficient evidence.

## Phase 4 — Regression tests (AC-A2, AC-A4..A6)

- [ ] 4.1 T1 — ≥64 KB body, violation near the top → `deny` on every one of ≥30 runs.
- [ ] 4.2 T2 — same body + ack → `allow` on ≥30 runs.
- [ ] 4.3 T3 — `Edit`, violation in `new_string`, ack elsewhere in file → `allow`.
      Must fail pre-Phase-2 and pass post-Phase-2; demonstrate at both commits.
- [ ] 4.4 T4 — file already contains a violation, `Edit` touches an unrelated region → `deny`.
- [ ] 4.5 T5 — harness asserts `grep` resolves to a GNU grep **binary**, not a shell function;
      abort loudly otherwise (prevents vacuous passes inside an agent session).
- [ ] 4.6 Producer-class unit test beside the Phase 5 lint: `cat | grep -q` can fail,
      `echo | grep -q` does not.

## Phase 5 — Mechanical enforcement

- [ ] 5.1 Create `scripts/lint-piped-grep-q.sh` — fail on any external-producer `| grep -q`
      under `pipefail` that is not in the checked-in allowlist.
- [ ] 5.2 Seed the allowlist from Phase 1 minus everything Phase 3 fixed (shrink-only).
      One line per site including its recorded failure direction, so the allowlist IS the
      AC-A3 sweep record and cannot rot away from the code.
- [ ] 5.3 Register the lint in `scripts/test-all.sh`. Also register
      `scripts/lib/scratch-root.test.sh`, which is currently in no runner.
- [ ] 5.4 Correct the rule text in `plugins/soleur/skills/work/SKILL.md` to state the
      producer-class distinction (current wording sends reviewers after inert builtin sites).
- [ ] 5.5 Verify the lint fails on a deliberately injected external-producer site (AC-A8).

## Phase 6 — Reaper that sees a count-shaped leak (AC-B1..B3)

- [ ] 6.1 Add an inode/block pressure probe (`df -i` plus existing block usage) to
      `scripts/tmpfs-guard.sh`.
- [ ] 6.2 Add the pressure-tier arm: engages only above the high-water mark; drops the size
      floor entirely; lowers the age floor; **keeps ownership, recursive age, liveness, and
      the protected denylist fully intact**. Keys on NOTHING name-derived — no `tmp.` prefix
      logic anywhere.
- [ ] 6.3 Skip `du` on the pressure path (no size floor ⇒ no walk needed) so the arm is
      cheaper than the normal tier.
- [ ] 6.4 Exclude the guard's own `mktemp -t tmpfs-guard-*` working files.
- [ ] 6.5 Encode all four relaxation ceilings: (i) pressure-only, (ii) ownership + liveness
      never relaxed, (iii) per-run cap on entries reaped, (iv) every pressure reap logged
      individually.
- [ ] 6.6 Keep `find … -delete` (never `rm -rf`) — a survivor may be a `.git`-bearing checkout.
- [ ] 6.7 Test: ~10,000 tiny files, none near the old size floor → reaped under simulated
      pressure, untouched without it. Live (open-fd) tree and foreign-uid tree never reaped in
      either mode. Per-run cap holds. Runtime fits a 5-minute window.

## Phase 7 — Alarm that reaches a human (AC-B4)

- [ ] 7.1 Write a durable, size-capped alarm state file at a fixed path **outside `/tmp`**
      (an alarm store on the mount being reaped is self-defeating): timestamp, block usage %,
      inode usage %, reap counts.
- [ ] 7.2 Surface a one-line summary at `SessionStart` — extend the existing SessionStart hook
      rather than adding a new one. No network, no credentials, no PATH assumptions.
- [ ] 7.3 Escalation: when the surfaced count crosses a threshold, the agent files a deduped
      `action-required` GitHub issue — from the session context where `gh` authenticates, NOT
      from cron (keyring is unavailable there).
- [ ] 7.4 Retire `notify-send` from the alarm path, or keep it strictly best-effort with a
      comment recording that it is a no-op under cron. It must never again be counted as a channel.

## Phase 8 — Log sink, telemetry, arithmetic (AC-B5..B8)

- [ ] 8.1 Add `guard_log()` + the `TMPFS_GUARD_LOG_SINK` seam (default `logger`), replacing all
      three hard-coded `logger -t tmpfs-guard` sites.
- [ ] 8.2 Point the test harness at a fixture-scoped sink under its own `TESTROOT`
      (AC-B5: the suite writes nothing to the production journal).
- [ ] 8.3 Route per-entry reap detail (live and `DRY_RUN`) through `guard_log` instead of `echo`.
- [ ] 8.4 Confirm `reap_scratch_entries` now emits ONLY an integer on stdout, so the
      multi-line `-eq` arithmetic error disappears.
- [ ] 8.5 Add a defensive numeric sanitize at the consumer for both `reaped` and `cleaned`
      (the latter is safe only by luck today).
- [ ] 8.6 Emit a per-run liveness line so "silent" and "not running" are distinguishable.
- [ ] 8.7 Make the usage probe hermetic — the suite currently runs `df` against a `TESTROOT`
      that lives on the real `/tmp` and therefore branches on live production state.
- [ ] 8.8 Assert clean stderr on a run that reaps ≥1 entry (AC-B7).

## Phase 9 — Correct falsified documentation (AC-B10)

- [ ] 9.1 `plugins/soleur/skills/work/SKILL.md` — the "cron reaper now bounds the
      abandoned-scratch growth" claim is loaded into EVERY agent session and is false for the
      count-shaped class. Highest blast radius; do this first.
- [ ] 9.2 `knowledge-base/project/plans/2026-07-27-fix-tmp-tmpfs-mktemp-cleanup-leak-plan.md`
      §Observability — 5 false claims incl. an AC that greps for a string `logger` never writes
      (can never pass). Update in place; after Phase 8 most become true.
- [ ] 9.3 `knowledge-base/project/plans/2026-07-22-fix-testall-worktree-contention-plan.md`
      §alert_route — the named backstop is the 94-times-unheard branch.

## Phase 10 — Verify, capture, ship

- [ ] 10.1 `bash scripts/test-all.sh` passes (AC-X2).
- [ ] 10.2 Confirm `scripts/tmpfs-guard.sh` is still a drop-in at its existing path; the PR
      prescribes NO crontab change (AC-B9).
- [ ] 10.3 Write the learning file (directory + topic only; author picks the date at write
      time): producer-class discriminator; race is not size-gated (fires at 1 KB); the ugrep
      shim hides it from manual testing; scanning `new_string` scans a fragment not a document;
      "reviewed direction" is a hypothesis about the codebase, not a fact.
- [ ] 10.4 File the deferred tracking issue: migrate bulk `mktemp` call sites onto
      `soleur_scratch_root()` so per-run private scratch roots become a real convention.
      Re-evaluation trigger: a second count-shaped leak, or adopter count crossing a threshold
      that makes owner-scoped reaping viable.
- [ ] 10.5 PR body contains `Closes #6992` AND `Closes #6991` (AC-X1).

## Evidence block (fill during Phase 0)

```text
<paste Phase 0 probe output here — AC-X3>
```
