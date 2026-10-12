---
title: "Conditioning a unit to skip also conditions every detector wired to its failure mode — enumerate the reporting channels before silencing them"
date: 2026-10-11
category: bug-fixes
module: apps/web-platform/infra/inngest-bootstrap.sh + apps/web-platform/infra/inngest-cutover-flip.{service,timer} + apps/web-platform/infra/cloud-init-inngest.yml + scripts/followthroughs/inngest-provision-rehearsal-capture.sh
issues: [9962, 9939, 9944, 10078]
---

# Silencing a storm class trades away its alarm channel; the trade is only honest if the replacement detector is named and actually armed

## Problem

Issue #9962 asked for the #9939 pattern — `ConditionPathExists=` skip + fail-closed
unprefixed `EnvironmentFile=` — on the non-LUKS units whose env files are
written late in cloud-init (`inngest-cutover-flip` pair, `soleur-inngest-provision`,
`inngest-heartbeat` pair, `inngest-server`, `vector` inside `inngest-bootstrap.sh`).
The change converts a missing env file from repeated `Failed to start` rows into
quiet condition-skips. Two hazards hid in that trade:

1. **The storm was doing detection work.** A unit that fails loudly also feeds
   `OnFailure=` hooks, journal shipping, and monitors keyed on failure text.
   Comment-copying the #9944 precedent's "heartbeat is the designed detection"
   line onto `inngest-server` credited the heartbeat — which is conditioned on
   the *same* env file and co-skips in exactly the scenario the condition covers.
   The detector you name must not share the dependency you are gating on.
2. **A skipped timer stays unarmed for the boot's life.** A timer-level
   `ConditionPathExists` is evaluated at activation, once; systemd does not
   re-evaluate when the file appears. Re-entry requires an explicit
   `enable --now`, a provision rerun, or a reboot. Documenting the skip without
   documenting the recovery path describes a permanently-disabled poll as a
   graceful degradation.
3. **The first same-class census missed generated units.** `inngest-bootstrap.sh`
   embeds units in heredocs — they never appear in `git grep EnvironmentFile=` over
   `*.service`/`*.timer` files. The write-boundary sweep must enumerate unit
   bodies inside the generator script too, not just unit files on disk.

## Investigation attempts

- The mechanical `grep -rn 'EnvironmentFile=[^-]'` file census found the four
  standalone/cloud-init units — and nothing else. Only grepping the *renderers*
  (`inngest-bootstrap.sh`) surfaced the three worst storm shapes
  (`inngest-server` at `RestartSec=5`, heartbeat's 60s `OnFailure` loop).
- An 8-seat panel then found the rest: needle blind to `vector.service` /
  `soleur-inngest-provision.service` (journald text is unit-name-first, so a
  `Failed to start inngest*` prefix misses both); an embedded-journalctl false
  positive (prior-life `systemd[N]: Failed to start` text riding a current-life
  `post-boot-health` row's `jl=` field); floor slack; a pin set thinner than the
  AC's own path-set-equality claim; and a permanent-deadlock additive hole
  (a second, unnegated `ConditionPathExists=<latch>` beside the `!` latch is
  invisible to every latch-shaped check).

## Root cause

The conditioning contract was treated as a purely-local, file-shaped change.
Each layer of the pattern — the unit, its comment's claimed detector, the
forbidden-row evidence needle, the test's extraction machinery — has a failure
mode that only appears one level up from the file being edited.

## Solution

- Conditions added only to calibrated availability units; `inngest-redis.service`
  left deliberately loud (mount/data-integrity detector) with a comment and a
  negative assertion pinning the disposition.
- Every SKIP-VS-FAIL comment names the *external* channel that reports the dark
  state (web-1-fed `betteruptime_heartbeat.inngest_consumer` and the
  `-`-tolerant `inngest-server-probe` — never the co-conditioned heartbeat), and
  every timer comment documents the unarmed-for-boot-life recovery semantics.
- Needle widened to `Failed to start (inngest|vector|soleur-inngest)` + the
  `[="]UNIT` anchored scope; BOOT_STAGE rows excluded pre-scope to defeat the
  embedded-history FP (bounded residual named in the comment: the same exclusion
  also drops a real failure whose only copy is embedded journal text — contained
  because a failed unit emits no `bootstrap-done`, so the verdict gates to
  TRANSIENT, never false-PASS).
- Pins upgraded to the precedent's full shape: per-unit condition-path-set ≡
  envfile-path-set equality, unprefixed-`EnvironmentFile=` retention, bare
  reset-line sweeps, timer-vs-service equality, provision envfile-subset
  (exact equality impossible — the `!`-latch sits in the set), and an explicit
  unnegated-latch additive guard. Floors re-measured to exact green counts.

## Prevention

- When a change converts FAIL→SKIP anywhere, grep the unit's `OnFailure=`,
  heartbeat pings, monitors, and probe units that read the same env file —
  the skip must not also silence the channel that would have told you.
- A timer-level condition is a once-per-boot decision; the comment must name
  the re-arm path.
- Env-file/unit censuses must enumerate generator heredocs, not only
  `*.service`/`*.timer` files.
- Pin the *shape claim* the AC makes (path-set equality, fail-closed prefix,
  no reset lines), not just presence.

## Session Errors

1. `ConditionPathExists=` initially placed inside `[Timer]` — an inert lvalue
   systemd ignores silently; moved to `[Unit]`.
2. `_sec_body` section matcher missed the yaml-indented `[Unit]` header —
   made indent-tolerant.
3. A python batch-edit script's `assert s.count(old) == 1` died mid-run *before*
   `write_text` — the comment fixes reported "landed" but never persisted;
   reviewers then flagged them as stale. Batch edits must write per-file before
   asserting the next file, or assert-all-then-write-all.
4. `\\$` double-escaping inside a `for`-loop `assert` produced unbalanced-quote
   eval failures on all nine loop asserts — single-escape matches the flat form.
5. Two python literal-match attempts failed on `\\/` escaping; the edit tool
   on a read-verified region was the working path.
6. A backticked `` `.?` `` inside `git commit -m` was evaluated by the shell —
   commit messages with backticks need single-quote heredocs.
7. Floors and exact-count inventories ratcheted twice after adding asserts —
   the convention is *exact* counts, no slack (capture MIN=36, inngest 451,
   provision C0_EXPECTED=162).
8. Four of eight review seats hit a model rate limit; re-spawned after reset —
   meanwhile the missing lenses were covered inline (mutation check, delimiter
   census, sibling-needle census, carrier-set match).

## Related

- #9939 (the LUKS storm this generalizes), #9944 (conditioning precedent),
  #10027 (carrier pin update), #9963 (the journald shipping path the
  BOOT_STAGE-exclusion residual interacts with), #10078 (web-host same-class
  follow-up), #7695 (floor-slack defect class), #9703 (probe monitor
  feeder state).
