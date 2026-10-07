# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9686-watchdog-parent-death/knowledge-base/project/plans/2026-10-07-fix-test-all-parent-death-watchdog-debounce-plan.md
- Status: complete

### Errors
None. (The issue's cited location "~line 3806" had drifted — the `_RUN_WD` watchdog block actually sits at ~4303–4393 on origin/main `66717b6f7f`; the plan anchors on symbols, not line numbers, and records the drift in Research Reconciliation.)

### Decisions
- Debounce design: single per-poll `_wd_bad` verdict over the three parent legs (`kill -0` ESRCH / `stat==Z*` / `lstart` mismatch), `_wd_fails` consecutive counter gated by new knob `SOLEUR_TEST_ALL_WD_FAILS_N` (default 3, floor >=1), plus a deciding-poll re-verify that resets on a recovered read — implementing the issue's suggested fix verbatim.
- Inferred scope items (flagged in Scope Check): runner-death leg gets the same counter discipline, a per-failure `WARN ... (leg=..., k/N consecutive) (#9686)` diagnostic, and a soak followthrough probe (`scripts/followthroughs/watchdog-debounce-soak-9686.sh` + registered `.test.sh`).
- Test-first ordering (cq-write-failing-tests-before): Phase 1 adds ps-PATH-shim arms that MUST be red pre-fix; `kill -0` is a builtin and unshimmable — documented test-seam limit.
- Invariant pinned: consecutive-only, never cumulative/N-of-M — sustained failure always reaps; reap order, `parent process gone` message text, opt-out banner, and disarm stay byte-identical.
- Gates: `## Domain Review` = none (CI-machinery fix, no UI surface); User-Brand threshold `none`; Guard Contract with 7-row mutation matrix (lint-guard-contract.py green); #8659/#7942 acknowledged non-overlapping.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan (deepen ran inline; halts 4.6–4.12 evaluated PASS)
- Commands: gh issue view/list, cloud-detect.sh (local), lint-guard-contract.py (green), git grep/log/show
- Commits: 237d5987f0 (plan + tasks), 0064c6bfe3 (deepen amendments)

## Fix-round append (post-6-seat review)

Six-seat panel + inline shellcheck returned: P1 probe-sink defects (gh-api
logs endpoint fails on ANSI logs; `^`-anchored armed-check can't match
timestamp-prefixed `gh run view --log` lines; bare-phrase grep counted the
monitor's own echoed classifier source → permanent false-DIRTY), P2 fail-open
unguarded `ps` reads under `set -e`, P2 runner-dead reap list structurally
empty (per-poll overwrite drained the snapshot), P2 vacuous test
discriminators (bare `wait` rc=0, no counter assertion, comment-only pins),
plus P3 octal-poison threshold, runner-leg identity gap, silent identity-skip.

Additional root causes found during fix verification:
- `ps -o ppid=` output is column-padded (`" 691177"`) — `_wd_self` must be
  whitespace-normalised or `_wd_descendants`' `a == excl` string compare and
  `grep -vxF` whole-line filters both silently no-op → watchdog pid lands in
  its own reap list → `kill -TERM` self-terminates it mid-sweep (the exact
  "announced fire, surviving children" symptom).
- `ps | tr` inside `$( )` under `set -o pipefail` propagates ps's nonzero rc
  into the assignment → `set -e` aborts the watchdog subshell on line 1 if
  the probe child exits before ps reads it — `|| true` is load-bearing, and
  the probe must outlive the fork+exec (`sleep 0.5`, not `sleep 0.01`).
- `_wd_self` idiom: `$(bash -c 'echo $PPID')` reports the cmdsub subshell's
  pid on this bash (not the watchdog's) — spawned-child ppid probe used
  instead, nested-bash idiom retained as fallback.
- C.9 leftover check raced the TERM→2s→KILL grace window — the announce
  line prints before the sweep completes; assertion now waits for the
  watchdog's exit first.

Final state: orphan-retention suite 54/54, soak harness all-green,
killed-classification 77/77, runtime-ceiling 23/23, fixture ratchet 62/62
(baseline 1908 sites), followthrough-varq-ban clean, orphan-suites none.

## Ship status (auto-merge armed)

- PR #9687 ready, body+labels set (semver:patch), net-issue-flow +0 PASS.
- Merged origin/main (e143734c56) — suite re-verified 54/54 post-merge.
- Auto-merge ARMED (`autoMergeRequest` set, method=MERGE — repo merge queue
  handles squash). mergeStateStatus=BLOCKED = checks pending only.
- Follow-through enrollment DONE on #9686: `follow-through` label +
  column-0 unfenced directive
  `script=scripts/followthroughs/watchdog-debounce-soak-9686.sh earliest=2026-10-07T20:00:00Z secrets=GH_TOKEN`.
- Deferred scope-out filed: #9701 (enumerate watchdog sibling hazard).
- Review trailer: `Reviewed-By-Soleur` + `Reviewed-Coverage: full 6/6 agents`
  (commit ebd0a55ed9).

## Remaining after the queue lands the merge

1. `gh pr view 9687 --json mergedAt` → confirm merged.
2. Post-merge verification per ship skill (probe file present on main,
   directive still live on #9686 — closed-set sweeper pass keeps probing
   while the label stays).
3. Tally show + worktree cleanup (ship skill Phase 7).
