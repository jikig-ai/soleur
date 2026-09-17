---
title: "`command -v` is a resolvability probe, and every guard I wrote to pin it was narrower than its name"
date: 2026-09-17
issue: 8231
pr: 8241
category: test-failures
module: scripts/test-all.sh
tags: [guards, mutation-testing, escapes, bash, toolchain, measurement, vacuity]
---

# `command -v` is a resolvability probe, and every guard I wrote to pin it was narrower than its name

## Problem

`scripts/test-all.sh` exited rc 1 having emitted nothing, on a host where nothing about the
battery was wrong.

`command -v bun` succeeds for a version-manager SHIM that resolves on PATH and cannot run — an
unpinned `mise` shim prints `No version is set for shim: bun` and exits non-zero. The runner is
`set -euo pipefail`, so the bare `actual=$(bun --version)` was an **abort**, not a skipped check,
and it sits above every registration emit. Measured before the fix: all five `--enumerate` groups
returned rc 1 with **zero** records, and the full local gate was unrunnable **in every mode**.

Two consumers that correctly fail closed on the record count then went red for a cause neither
could name. CI never saw it: the `test-scripts` job omits `setup-bun` by design, so `command -v
bun` is false there and the block is skipped. A local-host-only defect, latent since the check was
introduced and observable only once the consumers arrived.

## Solution

Guard the read, bound its TIME as well as its status, and report the degraded case:

```bash
_bun_rc=0
actual=$(timeout 10 bun --version 2>/dev/null) || _bun_rc=$?
actual=$(printf '%s' "${actual:-}" | tr -d '[:space:]') || actual=""
if [[ -z "$actual" ]]; then
  echo "WARNING: 'bun --version' produced no version (exit ${_bun_rc}); skipping the version check" >&2
elif [[ "$actual" != "$expected" ]]; then
  printf 'WARNING: Bun %q installed, expected %q (from .bun-version)\n' "$actual" "$expected" >&2
fi
```

The in-repo reference shape already existed: `scripts/orphan-process-reaper.sh` › the `logger`
guard **runs** the tool and lets its status decide.

## Key Insight

**A mutation asks whether a guard CAN fail. An escape asks whether its predicate IS the property.
No mutation can answer the second, because on an escape the guard works exactly as written.**

Two escapes survived a green suite and a passing self-run battery:

- **The registration SET.** A plausible alternative fix — making `want_bun()` require a runnable
  bun — silently drops the 7 bun suites: `--enumerate all` emits **428** instead of 435, and
  every `>= 1` assertion is satisfied by 428 as happily as by 435. The PR's own defect class,
  surviving the PR's own assertions. Closed by per-group count parity against a working-bun twin,
  plus cross-arm parity.
- **The MODE.** The abort killed every invocation, which the branch's own evidence established —
  and all 20 arms drove `--enumerate`, pinning one projection of a defect already characterised as
  global. Closed by an arm driving a non-enumerate path.

Litmus: *name an implementation a reasonable engineer might write next that satisfies every
assertion while violating the property.*

## Prevention

- **A probe must TRAVERSE the code it tests.** The first non-enumerate arm used `--capacity`,
  which returns ABOVE the Version Check, so the arm never reached what it named and the escape
  passed 32/32. Before trusting any arm, ask which lines it actually executes. Prefer a probe
  whose success emits a distinctive marker from BELOW the code under test — reaching that marker
  is the proof.
- **A guard that bounds a STATUS does not bound TIME.** `|| actual=""` covers a non-zero exit and
  cannot rescue a command that never returns. This file already stated that rule verbatim for
  `crane`, 950 lines below the edit.
- **An exit gate must be DUAL-SOURCE.** Reading only the append-only log means dropping the log
  write from `fail()` prints ten `[FAIL]` lines, reports `10 passed, 10 failed` and exits 0 —
  `run_suite` reads rc, so that is a green suite over real failures. The instrument self-test must
  assert the EFFECT the gate reads, not only that a counter moved.
- **A mutation that produces a SYNTAX ERROR proves nothing.** One row scored "caught" at rc 2 with
  no summary line; the replacement had left `; ; }`. Require the mutant to PARSE (`bash -n`) before
  reading its verdict, and require a summary line — an rc with no verdict is unresolved.
- **Reconcile a derived row set against its source before publishing any figure from it.** The
  baseline timing log carried 441 labels against 435 registrations, because nested sandbox runners
  inherited an exported `TEST_TIMING_LOG`. The conservation check (`429 timed + 6 declined = 435`)
  is one command and was never run; three published numbers were wrong. The "sanity check" that
  was supposed to catch it was invalid reasoning — a **contained** double-count inflates a sum
  without ever approaching wall clock.
- **A claim inherited from a PLAN is a claim to measure.** "Three registered consumers fail closed
  on the enumerate stream" reached a code comment, an evidence table and a commit message; one of
  the three spawns no process and is not a consumer at all.

## Session Errors

**`command -v bun` treated as a liveness claim** — Recovery: guard the read, report the rc.
**Prevention:** run the tool and branch on its status; `scripts/orphan-process-reaper.sh` › the
`logger` guard is the in-repo reference shape.

**`AllowedCPUs=` on a `--user` scope asserted by rc rather than by effect** — Recovery: measure the
constrained view. **Prevention:** `cpuset` is not delegated below `user.slice`; use `taskset`.

**`_site/` described as a producer/consumer pair; nested runner described as blocking; a
"zero hits" row that was two** — Recovery: corrected in the evidence file. **Prevention:** read the
authority rather than the plan's summary of it.

**A `wait -n -p` probe measured 137 where the claim was 143** — the victim carried `trap '' TERM`
and was then SIGKILLed. Recovery: re-probe without the trap. **Prevention:** when a probe's result
disagrees with a documented claim, suspect the probe first; a fixture that changes the signal
disposition is not measuring the signal.

**`systemd-run` expanded `${cg}` before bash saw it, so two cgroup reads silently hit the ROOT
cgroup and returned a confident wrong answer** — Recovery: re-probe via a script FILE.
**Prevention:** never interpolate a shell variable into a `systemd-run` command line; pass a script.

**`$?` after a pipe reported 0 for a lint that exited 1 — three times in one session** —
Recovery: redirect to a file and read `$?` on its own line. **Prevention:** `cmd | tail` yields
`tail`'s status. This is documented and still recurred three times; treat any `echo "rc=$?"`
following a pipe as a defect on sight.

**Triaged `fixture-relative-assert` as pre-existing when it was this branch's own regression** —
Recovery: ran it on `origin/main` via a detached worktree (62/0 there, 60/2 here).
**Prevention:** a repo-global ratchet references no file in the diff, so no file-selected suite set
can surface it. Before calling any red "pre-existing", run it on `origin/main` and compare the
failure MODE, not just the colour.

**Inline `assert_fixture_dir` drifted from canonical by one message** — Recovery: restored
byte-identical. **Prevention:** the copy is policed by an equality ratchet; do not reword it alone.

**Claimed "no importable canonical form exists; 32 files re-derive it"** — false. There is a
canonical home (`plugins/soleur/test/test-helpers.sh`) AND a ratchet enforcing equality against it.
Recovery: corrected the comment and recorded the superseded claim. **Prevention:** before calling
something a propagation weakness, grep for the canonical home.

**`GROUPS` is a bash SPECIAL ARRAY** — `GROUPS=()` does not clear it and `+=` appends, so a
derivation read the user's gids (`1000 998`) and drove `--enumerate 1000`. The precondition guarding
it checked CARDINALITY, not VALIDITY, and passed on garbage. Recovery: renamed to `ENUM_GROUPS` and
added a validity assertion. **Prevention:** avoid bash special names (`GROUPS`, `PIPESTATUS`,
`SECONDS`, `LINENO`, `FUNCNAME`, `BASH_*`, `EUID`, `PPID`, `RANDOM`, `REPLY`, `OPTARG`); and a
non-vacuity check on a derived set must assert the MEMBERS are well-formed, not just that there
are some.

**A computed `MIN_CASES` dropped the suite into `guard-vacuity-floor`'s unconstructible set**
(22/1, "a floor enforced THROUGH the machinery it guards"). Recovery: the bound is a literal again,
with a separate derivation check keeping it honest. **Prevention:** this trap is documented
verbatim in `review/SKILL.md` › Sharp Edges and I walked into it anyway — before changing the shape
of a line adjacent to a floor's `if`, read the comment above it and run the guard it names.

**A mutation scored "caught" that was a syntax error** — Recovery: re-ran well-formed.
**Prevention:** `bash -n` the mutant and require a summary line before reading any verdict.

**Three propagated claims published false** — the third consumer, the contaminated row set, the
`pipefail` mechanism. Recovery: all three corrected with superseded notes rather than deletions.
**Prevention:** for every causal or universal claim a diff ADDS, name the command that falsifies it
and run it.

**The token-efficiency report read ZERO subagent tokens for a session that spent ~1.35M across 7
agents** — five of them individually past its own 100k `te-subagent-overshoot` threshold, so it
reported "no outliers triggered. Session within thresholds." Recovery: none needed for this PR; the
report is advisory. **Prevention:** an instrument that has never been shown to produce a positive
has not returned a negative. Before reading any "within thresholds" verdict from
`token-efficiency-report.sh`, check that its inputs are non-empty — it derives subagent envelopes
from `.session-tokens.jsonl` and skill payloads from `.skill-invocations.jsonl`, and reports `n/a
(0 tokens)` indistinguishably for "no subagents ran" and "the log was never written". A zero from a
cost instrument on a session that visibly spent is a measurement failure, not a clean result.

**A boundary guard fixed on one side reads as fixed.** `scripts/ship-incident-pir-gate.sh`'s
`PROD_RE` anchors `prod(uction)?` on the right — `prod(uction)?([^a-zA-Z]|$)` — and its header
records the measurement that motivated it: bare `prod` matched 14 times in a plan and not once as
the word, every hit being `producer`, `produced`, `product`, `reproduced`. The guard removes all
four. It has no LEFT boundary, and `reproduction` is the single inflection where taking the
optional `(uction)` group puts the right guard on a real word end, so `reproduction` still matches
while `reproductions` and `reproduced` do not. Four of five `production`-class hits in this
branch's plan are `reproduction`. Recovery: adjudicated and recorded in `acceptance-evidence.md`;
not fixed, because it does not change this PR's verdict (20 standalone `live` tokens satisfy the
same conjunct) and the gate's pinning suite runs under `bun`, which this host cannot run.
**Prevention:** a substring guard is two claims, not one. When fixing a token that matched inside
longer words, enumerate the false-hit set AND the inflections of each member, and assert the
reject for every one — the surviving member is always the inflection whose ending happens to
coincide with the guarded boundary. The same-class recurrence rule applies: the finding here is
that the documented fix was graded by re-running the words that motivated it, never by generating
new ones.

## Related

- `knowledge-base/project/specs/feat-one-shot-8231-parallel-test-all/acceptance-evidence.md`
- #8231 (open — the parallel scheduler is blocked on a green baseline)
- #7376, #7432, #7454, #7554, #7076, #8045, #6496 — the adjacent test-infrastructure set
