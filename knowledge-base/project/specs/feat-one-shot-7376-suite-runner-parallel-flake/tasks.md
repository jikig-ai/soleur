---
title: "Tasks — run-registered-suites.sh parallel flake (#7376)"
plan: knowledge-base/project/plans/2026-08-10-fix-infra-suite-runner-parallel-flake-plan.md
issue: 7376
branch: feat-one-shot-7376-suite-runner-parallel-flake
lane: cross-domain
date: 2026-08-10
---

# Tasks — #7376

Derived from `2026-08-10-fix-infra-suite-runner-parallel-flake-plan.md`. Read the plan's
**Hypotheses** and **Sharp Edges** before starting — several obvious-looking changes are
explicitly non-defects (`set -o pipefail` is already set; the `| grep -q` rewrite is refuted).

## Phase 0 — Preconditions (no code)

- [ ] 0.1 Re-derive the failure corpus: `gh run list --workflow=main-health-monitor.yml`,
      `gh run view <id> --json jobs`. **Name all 6 implicated suites** (issue body names 3; PR
      #7371 says 6). Record in the PR body.
- [ ] 0.2 Take the suite count from `bash apps/web-platform/infra/run-registered-suites.sh --list`
      (93 today). Never hardcode.
- [ ] 0.3 Confirm local toolchain matches CI: `terraform`, `docker`, `python3`, `jq`, `cloud-init`.
- [ ] 0.4 Confirm `taskset -c 0-3 nproc` == 4 (so the runner computes `JOBS=4`).

## Phase 1 — The instrument

All in `apps/web-platform/infra/run-registered-suites.sh` unless noted.

- [ ] 1.1 Allocate a per-run log dir (`mktemp -d`); each `xargs` child writes its suite's
      stdout+stderr to its own file. Key the filename on a **sanitised full path**, not `basename`
      (`report_orphans` enumerates a recursive glob; basenames are not guaranteed unique).
- [ ] 1.2 Record per-suite `rc` (`$?` in the same subshell) and elapsed time. Reuse
      `scripts/test-all.sh:38-41,153`'s `EPOCHREALTIME` idiom **including its bash-3 fallback
      guard**; seconds precision is sufficient — do not add a `date +%s%N` dependency.
- [ ] 1.3 Keep `PASS <path>` / `RED  <path>` emitted **first** from the child, byte-identical.
      Document the invariant as *"the summary line stays under `PIPE_BUF` (4096)"*, not "today's
      writes are 60 bytes".
- [ ] 1.4 Dump from the **parent**, single-threaded, after `xargs` returns and **before** the final
      summary block. Never from inside a child.
- [ ] 1.5 **Select the excerpt by anchoring on the suite's own failure marker** (`^\[FAIL\]`,
      `^  FAIL`, `^no `) plus trailing context and the last few lines, capped ~40 lines/suite.
      **Not a blind tail** — suites keep running after a failed assertion (43 arms in
      `web-host-provisioner-parity-mutation`), so a tail shows only trailing passes. Fall back to
      the tail only if no marker matches, and say which was used.
- [ ] 1.6 Prefix every dumped line with `| ` (load-bearing — Risk 1).
- [ ] 1.7 **`.github/workflows/main-health-monitor.yml:436`** — filter the sentinel out of the
      unconditional tail: `$(grep -v '^| ' "$file" | tail -30)`. This line sits **outside** the
      `if [[ -n "$hits" ]]` block, so without this change dumped bytes reach the public issue body
      and the GDPR clearance lapses.
- [ ] 1.8 Log lifetime: retain on non-zero exit + print path; reap on success. Initialise the var
      **before** the `trap`, use `${LOGDIR:-}` (`set -u` active at `:91`). Note in the header that
      retention serves the **local** repro only.
- [ ] 1.9 Add an `INFRA_DIR` seam beside `INFRA_WF` (the derivation regex hardcodes the
      `apps/web-platform/infra/` prefix). Required so Phase 5 fixtures need not be created in the
      live tree.
- [ ] 1.10 Add `SUT="${SUT:-apps/web-platform/infra/run-registered-suites.sh}"` in
      `run-registered-suites.test.sh:13` (currently hardcoded) so AC1's mutation-proof is possible
      without `git stash`.
- [ ] 1.11 Prose sweep on the **verified real strings** (the monitor contains zero
      `dev/null 2>&1`): `run-registered-suites.sh:42-43`; `main-health-monitor.yml:408-409`
      ("discards each suite's own output" + "92 suites"); `main-health-monitor.yml:136`
      ("SAME 92 suites").

**Explicitly NOT in Phase 1:** capacity preamble, `/tmp`+`$TMPDIR` headroom probes, docker daemon
state, cgroup `oom_kill` counter. See the plan's rationale.

## Phase 2 — Fix the provable collision (no measurement gate)

- [ ] 2.1 `run-registered-suites.test.sh:97-103` — stop creating/removing
      `zzz-run-registered-suites-fixture.test.sh` in the live `apps/web-platform/infra/` and stop
      touching `.git/index`. Use a `mktemp -d` fixture root via the new `INFRA_DIR` seam.
- [ ] 2.2 `credential-persist-home-guard.test.sh:643,756,988` — diff against a **frozen snapshot**,
      not the still-live source.
- [ ] 2.3 Fix both sides (2.1 is the mutator, 2.2 is the robustness).

## Phase 3 — Measure and attribute

- [ ] 3.1 Sequential `JOBS=1` baseline pass; keep per-suite elapsed times as H4's baseline table
      (missing for 90 of 93 suites today).
- [ ] 3.2 **Pre-fix** parallel baseline: `taskset -c 0-3 bash …/run-registered-suites.sh`, n ≥ 20,
      on the tree *before* Phase 2. This is AC11's denominator.
- [ ] 3.3 Post-fix loop, n ≥ 20.
- [ ] 3.4 Read **exit codes first** — 137/124 settles H2 and H4 before opening a log.
- [ ] 3.5 Apply each hypothesis's confirmation criterion verbatim. **Do not use "passes when re-run
      standalone" as a discriminator** — every named suite already does; all four hypotheses
      predict it.
- [ ] 3.6 `TMPDIR`-ignoring-write sweep across all 93 suites (covers H3 rows 2-4 only; row 1 uses
      no `TMPDIR`, so a clean sweep does not refute H3).
- [ ] 3.7 Attribute every distinct failing suite; record verdict + evidence per hypothesis.
- [ ] 3.8 **Split Trigger:** if ≥ 20 iterations reproduce nothing, STOP and split — ship instrument
      + Phase 2 alone, harvest CI. A local non-reproduction establishes nothing.

## Phase 4 — Fix every class the evidence confirms

- [ ] 4.1 If H3 (remaining): per-run-scope `git-data-rung2-rehearsal.test.sh:763,956` (`/tmp/rung2`),
      `canary-bundle-claim-check.test.sh:154,189,338,363` and
      `cloud-init-inngest-bootstrap.test.sh:105` (`/tmp`-pinned `mktemp`),
      `verify-tunnel-ingress-origin-infradir.test.sh:40` (`mktemp -u`).
- [ ] 4.2 If H2: serialise the heavy class (2 docker + 5 terraform suites at width 1, rest at 4).
      **Do not derive width from measured capacity.**
- [ ] 4.3 If H4: raise the specific suite's readiness deadline, or class-serialise it.
- [ ] 4.4 If H1 re-opens (all three conditions in the plan met): capture-then-herestring rewrite.
      A linter is **out of scope — file a follow-up issue**.
- [ ] 4.5 Apply the arm-selection rules: more than one arm may fire; a reproduced failure matching
      no arm is a **new hypothesis**, not a forced fit; a failing set differing from Phase 0's six
      is expected.

## Phase 5 — Tests

Use the `INFRA_WF` **and** `INFRA_DIR` seams so fixtures never touch the live infra dir.

- [ ] 5.1 T1 — fixture workflow, 1 PASS + 1 RED where the RED suite fails **early** then emits
      ≥ 100 further passing lines. Assert: exact `RED  <path>` shape; dump present, prefixed,
      ≤ ~40 lines, carries `rc` + elapsed, **contains the early failing assertion**; log dir
      retained + path printed; exit non-zero.
- [ ] 5.2 T2 — fixture emitting `[FAIL]` at column 0. Assert `grep -cE '^(RED |\[FAIL\])'` counts
      genuine `RED` lines only. **Bare `|` in the ERE** — `\|` is a literal pipe, matches nothing,
      passes vacuously (measured: correct 2, escaped 0-and-exit-1).
- [ ] 5.3 T3 — run the monitor's excerpt logic over a capture containing dumped lines; assert
      `$SUMMARY` has no `^| ` line. Pin in `plugins/soleur/test/main-health-monitor-workflow.test.sh`
      beside check (8); leave check (12) intact.
- [ ] 5.4 T4 — all-green run: no dump, log dir reaped, exit 0, `--list` still emits no
      `^(PASS|RED) ` lines (existing T2c).
- [ ] 5.5 Mutation-prove the new assertions against the pre-change runner via the `SUT` seam.

## Phase 6 — Record and ship

- [ ] 6.1 Amend `ADR-133-*.md` with the **single** durable clause: its capacity verdict was
      measured on a RAM-backed `/tmp` workstation under cross-worktree overlap and does **not**
      transfer to a hosted runner on disk-backed `/var/tmp`. Nothing else.
- [ ] 6.2 Register any new suite file in `infra-validation.yml` (else
      `.github/scripts/test/test-infra-suite-registration.sh` fails a required check).
- [ ] 6.3 `bash scripts/test-all.sh` green (nests the runner via `test-all.sh:801`).
- [ ] 6.4 PR body: state explicitly what was and was not established, including every hypothesis
      still UNKNOWN, and AC11's caveats (`taskset` bounds CPU only; observer effect; baseline
      denominator).
- [ ] 6.5 Use `Closes #7376`. Leave `JOBS: 1` at `main-health-monitor.yml:304`/`:323` untouched.
- [ ] 6.6 File the follow-up issue for the `JOBS=1` removal, recording that it must also (a) add a
      non-filing `-P 4` probe job or accept local evidence, (b) remove both pins, and (c) **delete
      check (12)** from `main-health-monitor-workflow.test.sh`.
