---
title: "A unit-file content pin must model systemd's parser, not the file's bytes"
date: 2026-10-11
category: test-failures
module: apps/web-platform/infra/inngest-redis-luks.test.sh + apps/web-platform/infra/inngest.test.sh + scripts/followthroughs/inngest-provision-rehearsal-capture.test.sh
issues: [9939]
---

# The #9939 ConditionPathExists pins: seven ways a whole-file grep stays green while systemd never reads the line

## Problem

Issue #9939 / PR #9944 added `ConditionPathExists=` lines to three systemd units
(`inngest-luks-open.service` inside `cloud-init-inngest.yml`, plus the committed
`inngest-luks-cutover.service`/`.timer`) so a start attempted before the runcmd
env-file writes SKIP instead of FAIL into the LUKS observability channel. The
first-pass pinning asserts (commit `27a7fa74`) were whole-file `grep -qxF`
presence checks plus count-parity comparisons. A 9-seat panel and two targeted
fix rounds (`772c63d3`, `1a59a4b5`, `7af4747e`) progressively demolished them —
each round finding a shape under which the pin reports green while systemd
itself would not honor the directive. The resulting gap vocabulary is what any
future unit-file content assert inherits.

## The gap vocabulary — what the review seats found, and the fix shape for each

1. **SECTION SCOPE.** Directives are valid only inside their own section:
   `ConditionPathExists=` in `[Unit]`, `EnvironmentFile=` in `[Service]`. A line
   under the wrong section is an inert "unknown lvalue" journal notice — the
   property silently dies while every whole-file presence grep stays green.
   Fix: extract the directive's own section first (an awk flag-window —
   `_luks_sec()` in `inngest.test.sh`, `_LUKS_OPEN_UNITSEC`/`_LUKS_OPEN_SVCSEC`
   in `inngest-redis-luks.test.sh`) and grep there, so a misplaced line reads as
   absent. The section extracts are themselves non-vacuity-guarded (T1.15a), or
   every assert below them grades an empty string.
2. **SET IDENTITY vs CARDINALITY.** Counting members on both sides
   (`EF count == CX count == timer CX count`) passes a coordinated mismatched
   pair — `EnvironmentFile=/a` + `ConditionPathExists=/b` satisfies 2==2 while an
   unconditioned env file still fails a start. The same trap appeared inside one
   arm: the timer's `c==2` alternation counted *either* needle, so a duplicated
   `inngest-server` line plus a missing `luks-volumes` line passed — the one new
   P2 of fix round 1. Fix: compare sorted path SETS, not counts — strip the
   directive with `sed -n 's/^[[:space:]]*Directive=//p'`, tokenize multi-path
   values with `tr ' \t' '\n'`, drop empties, `sort -u`, string-compare
   (`_luks_sec_vals`, `_T115_EF_SET`/`_T115_CX_SET`) — and pin each literal at
   `grep -cxF … -eq 1`, not `-ge`.
3. **PATH-PREFIX BLINDNESS.** An earlier counter patterned
   `EnvironmentFile=/etc/default/[^ ]+` — it silently skipped any directive on a
   path outside `/etc/default/`, so a re-point at an always-present path
   (mutation row 5 in the plan) was invisible. Fix: drop the infix; count and
   set-compare every member of the directive, wherever it points.
4. **BARE RESET LINES.** systemd's empty-assignment semantics: `EnvironmentFile=`
   and `ConditionPathExists=` *with no value* reset the whole list — the env set
   empties, every condition erases. The set extractors drop the empty token, so
   a reset line is invisible to them, and the literal pins keep matching the
   surviving lines. Fix: a file-wide absence assert
   `^[[:space:]]*(EnvironmentFile|ConditionPathExists)=[[:space:]]*$` — file-wide
   because a reset line is never legitimate in any section at any indent (T1.15g
   plus the shared arm in `inngest.test.sh`).
5. **WHITESPACE TOLERANCE.** systemd strips leading whitespace on directive
   lines — `   EnvironmentFile=-/x` is honored but invisible to `^`-anchored
   checks. Fix: `^[[:space:]]*` in every negative/reject pattern and every value
   extractor. The literal pins keep their exact-indent needles
   (`      ConditionPathExists=…`) on purpose — a strict literal fails RED in the
   direction that names the defect, while a tolerant reject fails closed on the
   shape that matters.
6. **PIPED PREDICATE CONVENTION.** The suite's own header convention
   (`inngest-redis-luks.test.sh` harness block, ~line 22: "NEVER pipe into an
   assertion predicate") exists because `printf | grep -q` under `pipefail`
   SIGPIPEs the producer (rc 141) on an early match — and a NEGATIVE assert then
   fails *open*. The first-pass T1.15 arms used exactly that form inside the
   suite that carries the warning. Fix: EOF-consuming forms only —
   `grep -cxF needle` / `grep -cE pattern` piped to `>/dev/null`, never `-q`.
7. **MUTATION CONTROLS.** T1.15e drives the mutated block through the SAME
   needle variable and the SAME predicate as the arm under test
   (`_T115_NEEDLE_LUKS`, `grep -cxF`), so a drifted needle or a laxer predicate
   breaks the control too. A mutation row that greps a *different* literal would
   pass either way and pin nothing.

## The production semantics the change relies on (all measured, systemd 261 `--user` harness; host runs 255, condition semantics stable since ~v210)

- **`ConditionPathExists=` on a timer evaluates at ACTIVATION, not per-elapse.**
  `enable --now` (or `timers.target` on later boots) is the evaluation point, so
  on an abort-host the timer never arms the ~30 s tick storm — one skip notice
  per boot instead of a `Failed to start` every 31 s — and a later boot with the
  files present self-heals.
- **`enable --now` on a condition-failed unit exits rc 0 with
  `is-active=inactive`.** The state verdict is `is-active`, never the exit code:
  the `inngest-luks-reopen-armed`/`ARM-FAILED` phone-home's `= "active"` check
  still fires correctly, and the bootstrap's `enable --now` under
  `set -euo pipefail` does not abort.
- **A skipped service never runs `ExecStopPost`.** Skip → silence; start → the
  `unit-exit` phone-home fires on EVERY exit once a start is attempted, success
  ticks included. So keeping *attempted starts* rare is what keeps the channel
  meaningful — the first-pass comment ("fires on failures after ExecStart")
  understated it and was corrected in review.
- **Bare `enable` on a timer does not propagate to its `Unit=` service's
  `[Install]` arms.** The service's `WantedBy=multi-user.target` arm, manual
  `systemctl start`, and any future `Wants=`/`Requires=` consumer are triggers
  the timer's condition cannot see — the service carries its own pair.
- **Pattern origin:** `ConditionPathExists=` is the established repo idiom —
  ADR-257's `ConditionPathExists=!/var/lib/soleur-inngest-provision/done` latch
  on `soleur-inngest-provision.service` ("the latch's one consumer… only refuses
  a start"), and `scripts/tmpfs-guard.service`. The `-` tolerant
  `EnvironmentFile=-` prefix was the deliberately rejected alternative: the
  fail-closed contract is the point of these units.

## Key Insight

A content pin over a systemd unit is only as strong as its model of systemd's
parser. Presence greps model *bytes*; the parser models *sections, sets,
resets, and whitespace* — and every gap between those two models is a shape
under which the assert reports green while the property is absent. The correct
mental frame is the same one the suite already uses for awk extraction
(T1.7a2/a3, T1.9c, T1.10): prove the extraction is bounded at both ends, prove
each conjunct with its own fixture, and let the mutation control share the
production predicate so a weak assert cannot hide behind a strong name.

## Session Errors

1. **Mangled first edit.** The first edit attempt against
   `cloud-init-inngest.yml` landed malformed and had to be redone before the RED
   run. Recovery: re-applied the edit and verified the hunk region before the
   suite ran. **Prevention:** after any edit into a structured file (YAML,
   unit file), re-read the edited region — or run the extractor the suite uses
   — before declaring the edit landed.
2. **1.5 h flock queue.** `test-all.sh --affected` queued on the repo-global
   flock behind sibling worktree runs (position 3; measured >1 h) while nothing
   else was running locally. **Prevention:** start the affected-gate run early
   and overlap it with review prep rather than serializing it at the end; check
   lock occupancy before assuming the gate itself is slow.
3. **`gh issue create` gate refusal.** The follow-up filings were refused by
   `.claude/hooks/follow-through-directive-gate.sh` until the body carried the
   `<!-- soleur:followthrough script=… earliest=… -->` directive. **Prevention:**
   when filing review follow-ups, embed the directive stub
   (`plugins/soleur/skills/ship/references/followthrough-stub-template.sh`) in
   the first attempt — the gate is mechanical and the refusal is unambiguous.
4. **Fixture indent slip.** The injected `Failed to start inngest-luks*` rows in
   `inngest-provision-rehearsal-capture.test.sh` initially carried formatting
   (indent and Description text) that did not match the real units' journal
   shape — the arm passed, but against a needle the real journal never emits.
   Recovery: fixtures rebuilt to carry the real unit Descriptions and row shape
   (the run-38031062344 journal shape recorded in the plan). **Prevention:**
   build fixtures by copying a real journal/evidence line, not by paraphrasing —
   a fixture the producer could never emit proves the predicate on text that
   does not exist.
5. **semgrep broken-but-present → #9964.** `ensure-semgrep.sh` exits 0 when
   `command -v semgrep` resolves, but every installed semgrep on this host had a
   shebang pointing at mise `python/latest` (now 3.15) while the package lived in
   python3.14 site-packages — `ModuleNotFoundError` on invocation, so the SAST
   seat silently no-opped. Recovery: a shim pinned to `mise python 3.14.8`;
   filed #9964 (verify `semgrep --version` executes, fall through to install on
   failure). **Prevention:** a presence probe that gates a seat must *execute*
   the binary, not merely resolve it — `command -v` answers "does a file exist",
   never "does it run".

## Related

- `2026-09-25-the-flake-was-sigpipe-at-4kib-and-my-fix-leaked-a-pipe-status-through-a-bare-return.md` — the SIGPIPE mechanism gap 6 rides on
- `2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md` — same convention, earlier incident
- `2026-10-10-a-negative-row-passed-for-the-wrong-reason-four-times-in-the-guard-built-to-contain-mutants.md` — mutation controls and per-conjunct fixtures, the same week
- ADR-257 (`knowledge-base/engineering/architecture/decisions/ADR-257-inngest-host-provisioning-runs-in-a-latched-retrying-unit.md`) — the `ConditionPathExists=!` latch idiom this change extends
- Follow-ups filed from this work: #9962 (same-class units), #9963 (journald shipping path), #9964 (ensure-semgrep probe)

## Tags
category: test-failures
module: inngest-redis-luks.test.sh, inngest.test.sh, inngest-provision-rehearsal-capture.test.sh, systemd-unit-asserts
