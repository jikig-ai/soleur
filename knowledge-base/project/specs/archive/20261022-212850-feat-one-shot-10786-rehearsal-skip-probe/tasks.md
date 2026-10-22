# Tasks: repair the rehearsal skip-persistence probe (#10786)

Plan: `knowledge-base/project/plans/2026-10-22-fix-rehearsal-skip-persistence-probe-marker-plan.md`

## Phase 0 - RED first

- 0.1 Add probe-suite section `(k)` to `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh`: real runner on a fixture infra dir (mapped suite plus a second suite), runner stdout fed to the probe through the fake-`gh` harness.
  - 0.1.1 Skip plus terminal line expects exit 1; terminal only expects exit 0; neither expects exit 2.
  - 0.1.2 Derive the fixture marker text from the probe file (`SUITE_TERMINAL`, `SKIP_MARKERS` entry 1) so a probe literal edit moves the fixture.
  - 0.1.3 Precondition: the captured runner output contains at least one `relay` line.
- 0.2 Pin the suite end by value: extract the real suite's terminal `echo`, expand with sample numbers, match against the runner's `EVIDENCE_TERMINAL_ERE`.
- 0.3 Add `T13` rows to `apps/web-platform/infra/run-registered-suites.test.sh`.
  - 0.3.1 Relay present, every line `SOLEUR|`-prefixed, none at column 0.
  - 0.3.2 Summary line last and byte-identical; clean fixture still emits no `SOLEUR|` line.
  - 0.3.3 One fixture dir, one `bash "$SUT"` invocation for all rows (T9 re-runs the file ~25 times; record before/after wall time and re-check the 540 s bound). Skips in two suites, both relayed; the 200-skip suite yields exactly 50; the mapped terminal line survives the cap; terminal text relayed only for the mapped basename.
  - 0.3.4 RED suite with an early skip line: exactly one `relay` line (the dump's fallback tail may print it again; not asserted).
- 0.4 Run both suites; confirm RED for the intended reason (exit 2 / no relay lines), not a harness error.

## Phase 1 - runner relay

- 1.1 `apps/web-platform/infra/run-registered-suites.sh`: add `EVIDENCE_SKIP_ERE`, `EVIDENCE_TERMINAL_SUITE` and `EVIDENCE_TERMINAL_ERE` (two scalars), `EVIDENCE_CAP=50`, and `relay_evidence`.
- 1.2 Call it inside the existing `SOLEUR|` diagnostic block, before the retained-logdir note, the reap and the summary line; open the header only on a match.
- 1.3 Two separate greps per log (skip lines capped, terminal line uncapped); `grep -a`; capture each rc as `dump_one` does; `mapfile -n` only on rc 0; `cut -c1-400`; no pipe into `head`.
- 1.4 Update the header comment that says the skip is not visible through the runner.

## Phase 2 - green and harden

- 2.1 Run the Phase 0 suites to green.
- 2.2 Add `T9` rows 1, 3, 5 from the plan's Guard Contract to the runner suite; add the in-suite probe/regex mutation harness (row 4) and the second-member row (row 2, killed by T13) to the right suites; raise floors, itemised.
- 2.3 Raise the probe suite floor, itemised.
- 2.4 Bump `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` with the PLACEMENT / TRUTH / NO SUBSTITUTE comment.

## Phase 3 - probe header correction

- 3.1 `scripts/followthroughs/t5-skip-persistence-bound-7510.sh`: comment-only header correction naming the relay as the carrier.
- 3.2 Probe-suite regression case: a canned log shaped like main run 39612112094 exits 2.

## Phase 4 - documentation

- 4.1 ADR-252 consequence note (per-suite capture, the relay, the drift pin).
- 4.2 ADR-188: record that the evidence path is repaired (true at merge), phrased around the observed-run count (the first read is `observed` of 20 sampled). The observed verdict goes in the #10786 closing comment.

## Phase 5 - verify and ship

- 5.1 Run: runner suite, probe suite, `main-health-monitor-workflow.test.sh`, `c4-count-parity.test.sh`, `lint-guard-contract.py` on the plan, markdownlint on plan and tasks.
- 5.2 PR body: `Closes #10786`; state the streak-cache defect is deferred and link its new tracking issue (file it: priority/p3-low, type/chore, domain/engineering).
- 5.3 Post-merge: select the merge commit's push run by `headSha` (retry on an empty list), grep its log for `SOLEUR| relay git-data-runcmd-rehearsal`, dispatch the monitor, arm a `Monitor` watch, read `probe verdict:`. Done when `pass` or `fail`; post it as the closing comment on #10786.
