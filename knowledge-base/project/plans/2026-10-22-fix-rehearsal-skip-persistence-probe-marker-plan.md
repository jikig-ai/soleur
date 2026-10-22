---
title: "ci(infra): repair the #8856 rehearsal skip-persistence probe (returns TRANSIENT, so the skip-streak trigger cannot fire)"
type: fix
date: 2026-10-22
slug: fix-rehearsal-skip-persistence-probe-marker
branch: feat-one-shot-10786-rehearsal-skip-probe
issue: 10786
closes: 10786
priority: p3-low
domain: engineering
brand_survival_threshold: none
---

# ci(infra): repair the #8856 rehearsal skip-persistence probe

## Enhancement Summary

**Deepened on:** 2026-10-22
**Sections enhanced:** Overview, Research Insights, Implementation Phases, Guard Contract, Scope Check
**Research and review used:** CTO ruling (design fork), DHH, Kieran and code-simplicity plan review, live `gh` and `git` verification of every cited run, PR, issue and ADR, and the plan-time gates below.

### Key Improvements

1. Root cause pinned to a commit, not an inference: before #8763 the workflow ran the suite as its own step
   (`git show 50ae36eff7^:.github/workflows/infra-validation.yml` carries `run: bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`,
   the same file at `50ae36eff7` carries zero occurrences), so its stdout reached the Actions log; after it, the
   runner's per-suite capture is the only path.
2. Review cuts applied: the probe-side diagnostic, the ADR-188 second-PR edit, five of nine mutation rows, the
   duplicate harness rows and the associative array; review corrections applied: the cap binds skip lines only so
   the terminal line cannot be dropped, T13 uses one fixture and one runner invocation (T9 re-runs the file about
   25 times), mutation rows are assigned to the harness that can actually score them, and the suite end of the
   three-way pin compares by value.
3. Post-merge verification hardened against the measured intermittent empty `gh run list` (rc 0, `[]`).

### New Considerations Discovered

- The streak-cache carrier is evicted under the 10 GB Actions cache cap (11.9 GB in use); deferred to its own issue.
- The first post-merge read will have `observed` of 1 against 19 pre-relay logs in the 20-run window; the ADR note
  and the closing comment must be worded around the observed count, not "20 clean runs".

### Deepen-pass gate results

Always-on halts: Phase 4.6 User-Brand Impact present, threshold `none` with the sensitive-path scope-out bullet;
4.7 Observability present, probe verb allowlisted, no `ssh`, `expected_output` literal, non-placeholder
`credentials_required`; 4.8 no PAT-shaped variable; 4.11 `lint-guard-contract.py` green and the Assembly names the
chokepoint, not the members; 4.12 exactly one unfenced `## Scope Check`, every row compliant. Conditional halts not
fired: 4.5 network outage (no SSH or timeout symptom), 4.55 downtime (CI tooling only), 4.9 UI wireframe (no UI
surface), 4.10 encryption posture (no `.tf`, migration or cloud-init edit, no new store or connection). Cited
issues and PRs (#8763 merged, #9394, #8856, #7510, #7574, #7376, #10786) and both ADR files resolved live; the one
rule id cited (`cq-write-failing-tests-before`) is an active rule.

## Overview

The daily skip-persistence monitor (`.github/workflows/scheduled-rehearsal-skip-monitor.yml`) runs
`scripts/followthroughs/t5-skip-persistence-bound-7510.sh`, which reads the Actions logs of the last 20
successful `main` runs of `infra-validation.yml`. For weeks it has reported TRANSIENT ("none containing
'git-data-runcmd-rehearsal:'"), so the first re-evaluation trigger of the #9394 ruling (ADR-188: "the
skip-persistence probe #8856 reports a skip streak") cannot fire.

**Diagnosis (measured against real runs, not inferred): the marker moved; the suite did not skip.** PR #8763
(merged 2026-09-25) moved the rehearsal out of a standalone `run: bash` step into
`apps/web-platform/infra/run-registered-suites.sh`, which redirects every suite's stdout and stderr into a
per-suite file under a log dir and deletes that dir on a green run. The runner prints only `PASS <path>` or
`RED  <path>`. On main run 39612112094 (2026-10-21, success) the only rehearsal line in the whole log is
`PASS apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (leg 1/4); neither the suite's
terminal line (`git-data-runcmd-rehearsal: N passed, M failed, Skipped: K (T assertions)`) nor any
`SKIP (loud): ...` line (stderr via `arm_skip`) can reach a log reader. The last monitor run that saw the
marker was 2026-09-27 (pre-merge runs still in the window); every run since 2026-09-28 is TRANSIENT. The probe therefore cannot report FAIL on a real skip
streak, which is the whole reason it exists.

**Fix (CTO-ruled, see `decision-challenges.md`):** make the runner relay the evidence the probe needs.
After the suites finish, the runner's parent process emits, as `SOLEUR|`-prefixed stdout lines inside the
existing diagnostic block, (a) every column-0 `SKIP (loud):` line from any suite's captured log and (b) the
terminal line of suites named in a small map (one entry today: `git-data-runcmd-rehearsal.test.sh`). The probe's
literals stay unchanged. An end-to-end test pins the three-way contract suite source, runner relay, probe
literal, so the marker cannot move silently a second time.

## Research Insights

### Premise validation (Phase 0.6)

- Issue #10786 is OPEN, not closed by any PR. ADR-188 (`## ... User-Challenge resolved (2026-10-22, #9394)`)
  and `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` exist on `origin/main`.
- The issue body offers two hypotheses: the marker moved, or the sampled runs genuinely skipped the suite.
  **Marker moved is confirmed; "genuinely skipped" is refuted**: the runner reported `PASS` for the suite in every
  sampled post-#8763 run I opened (`PASS apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`). A
  whole-suite skip (`_skip`, docker or terraform absent) exits 1 under `CI=true` (the suite's own contract),
  so a PASS on Actions means it ran to completion; what was never observable is an arm-level `arm_skip`, which
  is exactly the thing the probe exists to count.
- The issue says TRANSIENT "since 2026-10-18". Reality: the last real read was PASS on 2026-09-27 (11 observed
  of 20 sampled, all pre-#8763 runs still inside the 20-run window); the first TRANSIENT is 2026-09-28
  (run 36422425962, 19 logs, none with the marker) once those runs aged out. 2026-10-18 is the day the
  consecutive-TRANSIENT escalation reached 3/3 and commented on #8856.
- ADR corpus check (mechanism = "relay output from a captured suite"): ADR-252 (suite registration is
  presence; deploy-script-tests is a matrix) records per-suite capture as a deliberate property and says
  per-suite logs upload as a leg artifact **on failure only**. It never considered that a log-reading
  observer would go blind. ADR-188 designs the probe as the cross-run bound. Neither rejects a relay; ADR-252
  needs a consequence note (Phase 4).

### Property List (Phase 0.6b)

1. A skip the rehearsal suite declares on a green run is visible in the Actions log of that run.
2. The probe can tell "the suite ran and its output is readable" (positive control) from "unreadable".
3. A real skip streak makes the probe exit 1 (FAIL), not 2 (TRANSIENT).
4. If the evidence path breaks again, it fails loudly in CI (a test goes red), not silently in a nightly cron.

### Cut List (Phase 0.6b)

- Suite-emitted reserved prefix contract (design B): buys property 1, but the runner relay already buys it
  without editing the 3900-line mutation-pinned suite. Cut.
- Always-on log-dir artifact the probe downloads (design C): buys property 1; an artifact lifecycle on a
  cache/artifact budget already over its cap. Cut.
- Downgrading the positive control to the `PASS <path>` line (design D): breaks property 3 (blind to skips).
  Cut.
- Folding the streak-cache eviction fix into this PR: different failure domain, does not change the verdict
  (CTO-ruled defer).

### Value-proposition measurement (Phase 0.6c)

No cost or performance saving is claimed. The relay adds at most 50 short lines per suite to a log that is
already ~4.3 MB per run (`gh run view 39612112094 --log | wc -c` = 4366464).

### Local research findings (Phase 1)

- Runner executor: `apps/web-platform/infra/run-registered-suites.sh` shim line
  `"$@" bash "$s" >"$logdir/$key.log" 2>&1` is the single capture site. The invariant (comment block above
  the xargs call): the children's stdout MUST remain a pipe; do not touch it. The relay is a parent-side
  read of the finished files, single-threaded, after xargs.
- Diagnostic block: `{ dump_reds ... } 2>&1 | sed "s/^/${SENTINEL_PREFIX}/"`. `SENTINEL_PREFIX='SOLEUR| '`.
  `main-health-monitor.yml` strips `^SOLEUR|` lines from its public excerpt; the summary line
  `=== registered infra suites: ${PASS} passed, ${RED} failed, ${#UNACCOUNTED[@]} unaccounted (of N) ===` must stay
  byte-identical and last (T6v).
- `PASS`/`RED` counting is `grep -c '^PASS '` / `'^RED '` over `$LOG` (child summary lines only). The relay
  does not write to `$LOG`, so counts are unaffected.
- `PRIVILEGED_WHY` is keyed by basename; basenames are asserted unique at derive time, so a basename-keyed
  terminal map is safe.
- Probe positive control `SUITE_TERMINAL='git-data-runcmd-rehearsal:'` and `SKIP_MARKERS=( 'SKIP (loud): T5 '
  'SKIP (loud): S1 ' 'SKIP (loud): T17 ' )`, both matched with `grep -F` (substring), so a `SOLEUR|` prefix and
  the Actions timestamp do not break them. The rehearsal prints the terminal line at column 0 on its last
  statements (`echo "git-data-runcmd-rehearsal: ${passes} passed, ${fails} failed, Skipped: ..."`) and
  `arm_skip` prints `SKIP (loud): $1` to stderr (captured by `2>&1`).
- Other suites with column-0 or indented `SKIP (loud):` text: `infra-config-apply.test.sh` (indented, "not root",
  "pinned pre-fix blob"). The probe discriminates by arm name, test (d) in the probe suite pins this.
- Probe suite `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh`: harness `mkcase` pads fixtures
  past the 64 KiB pipe buffer; floor currently 12; registered in `scripts/test-all.sh`.
- Runner suite `apps/web-platform/infra/run-registered-suites.test.sh`: T6t/T6u/T6v assert a clean run's bytes;
  T9 is a self-graded mutation matrix with its own floors.

### Separate defect found (deferred, not in scope)

The monitor job is red on most days from `Assert the streak state round-trips` ("cache restore returned no
prior generation"). Verified: the repo's Actions cache is 11.9 GB against a 10 GB cap
(`gh api repos/jikig-ai/soleur/actions/cache/usage`), so the one-day-old streak cache is evicted; of the last
12 monitor runs 10 are red, all on this assertion. It resets the consecutive-TRANSIENT escalation counter but does not change
the probe verdict once the marker is visible. CTO-ruled: defer to its own tracking issue (file at PR time:
`ci(infra): scheduled-rehearsal-skip-monitor streak cache is evicted under the 10 GB Actions cache cap`,
priority/p3-low, type/chore, domain/engineering). The PR body states the counter is unreliable until then.

## Research Reconciliation: Spec vs. Codebase

| Claim (issue / ADR-188) | Reality | Plan response |
|---|---|---|
| TRANSIENT "since 2026-10-18" | Since 2026-09-28; 10-18 is the 3/3 escalation day | Plan cites the real window; no code depends on it |
| Hypothesis A: output marker moved | Confirmed (#8763 moved the suite from its own workflow step into the runner, whose per-suite capture dates from #7423) | Fix the visibility path (Phase 2) |
| Hypothesis B: sampled runs genuinely skipped | Refuted for whole-suite skips (a PASS under CI=true means the suite ran to completion); arm-level skips were never observable, which is the defect | Not planned; the diagnosis is recorded here and the end-to-end rows keep it from recurring silently |
| "only the two-consecutive-red trigger is live" | True until the relay lands | ADR-188 note updated in Phase 4 once verified post-merge |

## Open Code-Review Overlap

None. Queried open `code-review` issues for every planned path (`run-registered-suites.sh`,
`run-registered-suites.test.sh`, the probe and its test, the monitor workflow, ADR-188, ADR-252): zero matches.

## Architecture Decision (ADR/C4)

No new architectural decision: the relay restores an observation channel ADR-252's change removed, and the
probe design is ADR-188's. The documentation consequence is an in-plan task, not a deferred issue:

- `### ADR` - amend ADR-252 with a Consequences note (per-suite output is captured; observers of suite stdout
  read the runner's `SOLEUR|` relay, with the drift pin named) and amend ADR-188's 2026-10-22 User-Challenge
  paragraph once the post-merge verification shows a non-TRANSIENT result.
- `### C4 views` - read `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: the
  change adds no external actor, external system, container/data store or actor-to-surface relationship; the
  CI runner, GitHub Actions logs and the monitor workflow are not modelled elements. No `.c4` edit.
  `bash plugins/soleur/test/c4-count-parity.test.sh` is run at work time to confirm no embedded cardinality moved.
- `### Sequencing` - both ADR notes land with the code in this PR.

## Implementation Phases

Phase 0 and the order inside each phase follow `cq-write-failing-tests-before`: tests first, RED, then code.

### Phase 0 - RED: pin the contract before building it

Files: `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh`,
`apps/web-platform/infra/run-registered-suites.test.sh`.

1. New probe-suite section `(k)` end-to-end: build a fixture infra dir in the probe test's sandbox containing
   (i) `git-data-runcmd-rehearsal.test.sh` that prints a stderr `SKIP (loud): T5 MUTATION ...` line, then a
   stdout terminal line in the real format, exit 0, and (ii) a second suite that prints
   `SKIP (loud): S1 ...`. Run the REAL runner (`SOLEUR_INFRA_DIR=<fixture> bash apps/web-platform/infra/run-registered-suites.sh`)
   and capture its stdout. Feed that stdout (padded past the pipe buffer, markers early) to the probe through
   the existing fake-`gh` harness. Expect exit 1. Variants: terminal line only -> exit 0; neither -> exit 2.
2. The fixture lines are derived, not hand-copied: read `SUITE_TERMINAL` and the `SKIP_MARKERS` entries out of
   the probe file with `sed`, and build the fixture's skip line from `SKIP_MARKERS` entry 1. A probe literal
   edit therefore moves the fixture and still reddens through the runner's regex (the runner map is hard-coded).
3. Pin the suite end of the three-way pin by VALUE, not by presence: extract the real suite's terminal
   `echo "git-data-runcmd-rehearsal: ${passes} passed ..."` statement by content anchor, expand it with sample
   numbers, and match the expansion against `EVIDENCE_TERMINAL_ERE` read out of the runner. An edit to the
   separator or wording that keeps the anchor but misses the regex then reds. The `arm_skip` echo is already
   pinned by that suite's own roster guard.
4. Runner suite `T13` rows. ONE fixture dir and ONE runner invocation for all rows (T9 re-runs this whole file
   once per mutant, about 25 times, so each extra fixture is paid 25 times; measure the suite's wall time before
   and after and re-check its 540 s `_SUITE_BOUNDS` entry and the leg's 15-minute `timeout-minutes`). The
   invocation is `bash "$SUT"`, not the repo runner, or the mutants never exercise it. The fixture holds: a
   mapped `git-data-runcmd-rehearsal.test.sh` (skip plus terminal line), a second suite with a skip, a suite
   printing 200 skip lines then its own mapped-looking terminal text under another basename, a RED suite that
   prints a skip early, and a suite with an indented skip. Rows: relay present and `SOLEUR\|`-prefixed; no relayed
   line at column 0; summary line still last and byte-identical; a clean fixture still emits no `SOLEUR\|` line
   (T6u unchanged); both suites relayed (second-member row); the 200-skip suite yields exactly 50 relayed skip
   lines, and the mapped suite's terminal line is still relayed when it also has more than 50 skips (the cap
   binds the skip stream only); terminal text relayed only for the mapped basename; the RED suite's skip line
   appears in exactly one `relay` line (the RED dump's fallback tail may print it once more in its own
   `--- RED` block, which is harmless because the probe samples only successful runs; the row asserts the
   relay count, not the whole-log count).
5. Run both; confirm RED for the right reason (TRANSIENT exit 2 / no relayed lines), not a harness error.

### Phase 1 - runner relay (`apps/web-platform/infra/run-registered-suites.sh`)

Add, near `dump_reds`, a `relay_evidence` function plus two constants and call it inside the existing
`{ ... } 2>&1 | sed "s/^/${SENTINEL_PREFIX}/"` block, before the `retained per-suite log dir` note and long before
`rm -rf "$SOLEUR_SUITE_LOGDIR"` and the summary echo.

- `EVIDENCE_SKIP_ERE='^SKIP \(loud\): '`; `EVIDENCE_TERMINAL_SUITE='git-data-runcmd-rehearsal.test.sh'` and
  `EVIDENCE_TERMINAL_ERE='^git-data-runcmd-rehearsal: [0-9]+ passed'` (two scalars: one suite today, an
  associative array would be premature generality); `EVIDENCE_CAP=50`.
- Iterate `SUITES`, read `"$SOLEUR_SUITE_LOGDIR/${s//\//_}.log"`. Two separate greps per log, because the
  terminal line is the suite's last output and a combined stream capped at 50 would drop it: (a) skip lines,
  `sel=$(grep -a -E "$EVIDENCE_SKIP_ERE" "$f"); grc=$?`, capped at `EVIDENCE_CAP`; (b) only when the basename
  equals `EVIDENCE_TERMINAL_SUITE`, the terminal line, uncapped (it is one line). Capture each grep's rc as
  `dump_one` does (rc 1 = none, rc 2 = unreadable: report it, never read as "no skip"); call `mapfile -n` only on
  rc 0, since `mapfile <<<""` yields one empty element. `grep -a` so a NUL byte in a docker or apt log does not
  turn the match into "binary file matches". No `| head` (SIGPIPE under pipefail is this repo's documented
  defect). `cut -c1-400` is byte-based and may split a multibyte character (the suite's `arm_skip` text carries
  em dashes); harmless for matching, accepted. Print `relay <basename>: <line>`. The `SOLEUR|` prefix comes from the existing `sed`; no line reaches column 0
  (an unprefixed relayed line could carry `[FAIL]`/`RED` text into the public monitor excerpt, or an Actions
  `::command::`).
- Open the block header only when at least one line matched, so a clean run's bytes are unchanged. `SUITES`
  needs no re-sort: output order is not part of any consumer's contract.
- No pass/fail filter (CTO ruling): one loop over all suite logs. The probe samples only successful runs, so
  its verdict is identical, and a RED run keeps its context.
- Do not touch the capture line, `$LOG`, the PASS/RED counters, the accounting assertion, or the exit block.
- Update the header comment paragraph that says the skip "is NOT visible through this runner" to describe the
  relay and its coverage (only column-0 `SKIP (loud):` lines and the mapped terminal lines).

### Phase 2 - make the pin hold: green the Phase 0 tests

Run the runner suite and the probe suite. Add T9 rows to the runner suite's mutation matrix (see Guard Contract)
and raise its floors by the number of rows added, itemised in the comment as that file's convention requires.
Raise the probe suite's assertion floor 12 -> the new count, itemised.

### Phase 3 - probe header correction (comment only)

`scripts/followthroughs/t5-skip-persistence-bound-7510.sh`: correct the header paragraph "It reads the ONE
signal that already exists ..." to name the runner's `SOLEUR|` relay as the carrier and to record that the
marker was invisible between 2026-09-25 (#8763) and this change. No behaviour change. (Plan review cut the
proposed "suite ran but terminal line absent" diagnostic: the end-to-end rows already turn a relay regression
red in CI, and until pre-merge runs age out of the 20-run window it would blame the relay for logs that predate it.)
Add one regression case to probe suite `(k)`: a canned log shaped like main run 39612112094 (only
`PASS apps/.../git-data-runcmd-rehearsal.test.sh`) exits 2.

### Phase 4 - documentation

- ADR-252: Consequences note on per-suite capture and the relay (with the drift-pin test names).
- ADR-188: in this PR, replace "Trigger 1 cannot fire yet ... repair is tracked in #10786" with a dated
  sentence that the probe's evidence path is repaired by the runner relay (a statement true at merge). The first
  observed verdict goes in the closing comment on #10786, not in a second ADR edit after merge.

### Phase 5 - post-merge verification (automated, no operator step)

1. Wait for the push-triggered `infra-validation.yml` run on the merge commit (the PR edits
   `apps/web-platform/infra/**`, so the `push` path filter fires) and confirm success. Select the run by
   `headSha == <merge commit sha>` from `gh run list --workflow infra-validation.yml --branch main --limit 10 --json databaseId,headSha,conclusion,status`
   and retry a bounded 3 times with a pause on an empty list: measured 2026-10-22, the same `gh run list`
   call returned `[]` with rc 0 on one of four consecutive invocations, and an empty list must never be read
   as "not yet" nor as "no run".
2. `gh run view <id> --log | grep -c 'SOLEUR| relay git-data-runcmd-rehearsal'` returns >= 1 (the terminal line).
   The count is 0 on the pre-fix run 39612112094 (measured), so a non-zero count is real evidence.
3. `gh workflow run scheduled-rehearsal-skip-monitor.yml`, arm a `Monitor` watch on the run (never a
   background poll), then read the `probe verdict:` line. Done when it is `pass` or `fail`, not `transient`.
   A `fail` is a finding (ADR-188 trigger 1 has fired), not a regression: do not tune the probe to green.
4. Post the observed verdict as the closing comment on #10786 (`Closes #10786` in the PR body closes it).

## Files to Edit

- `apps/web-platform/infra/run-registered-suites.sh` - `relay_evidence`, constants, call site, header comment.
- `apps/web-platform/infra/run-registered-suites.test.sh` - T13 rows, T9 mutation rows, floors.
- `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` - header comment only.
- `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` - end-to-end `(k)` rows, regression case, floor.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` - bump `BASELINE_DECLARED_PROBES` by one (this plan declares `credentials_required`; the G1 ratchet counts declaring plans) with the PLACEMENT / TRUTH / NO SUBSTITUTE comment the failure text asks for. Re-read the current value at work time; it moves when sibling plans land.
- `knowledge-base/engineering/architecture/decisions/ADR-252-infra-suite-registration-is-presence-and-deploy-script-tests-is-a-matrix.md` - consequence note.
- `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md` - evidence path repaired (in this PR, a statement true at merge).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10786-rehearsal-skip-probe/decision-challenges.md` (created).
- `knowledge-base/project/specs/feat-one-shot-10786-rehearsal-skip-probe/tasks.md`.

Globs/paths verified: `git ls-files` shows each Edit path above is tracked. `git-data-runcmd-rehearsal.test.sh`
is not edited (reading it for the pin is not an edit).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. A broken relay leaves the nightly
  monitor TRANSIENT (as today) or, worst case, adds extra `SOLEUR|` lines to a CI log. No product surface.
- **If this leaks, the user's data is exposed via:** no user data path. The relayed lines are the suite's own
  loud-skip and summary text, prefixed so they never reach the public monitor excerpt; the existing RED dump
  already emits arbitrary suite lines under the same rules.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** an internal CI observation path with no user data and no production
  mutation; the cost of being wrong is a delayed signal, not user harm.
- `threshold: none, reason: the touched apps/web-platform/infra/ path is a test-runner script and its suite; it provisions nothing, reads no credentials, and writes only CI log lines.`

## Observability

The probe cannot be an undeclared Check 10 command: Check 10 would execute it in a sandbox under a 15-second cap
with no credentials, and the probe downloads up to 20 multi-megabyte run logs through an authenticated API. A
declared `credentials_required` is therefore the honest form, and it moves the G1 ratchet (Files to Edit).

```yaml
liveness_signal:
  what: scheduled-rehearsal-skip-monitor probe verdict (pass or fail, not transient) plus the SOLEUR| relay terminal line in each main infra-validation run
  cadence: daily at 06:00 UTC (monitor) and per push to main touching apps/*/infra (relay)
  alert_target: comment or issue titled "monitor: git-data rehearsal suite is skipping arms across runs" (#8856), and a red monitor run
  configured_in: .github/workflows/scheduled-rehearsal-skip-monitor.yml and scripts/followthroughs/t5-skip-persistence-bound-7510.sh
error_reporting:
  destination: GitHub Actions run log and the monitor's alert issue (no application Sentry path; repo-scoped CI tooling)
  fail_loud: probe prints FAIL (rc 1) on a skip, TRANSIENT with a relay-moved vs suite-did-not-run reason, and escalates to FAIL after 3 consecutive TRANSIENT runs
failure_modes:
  - mode: the evidence path breaks again (relay regex, probe literal or suite output changes)
    detection: probe end-to-end rows (k) and runner rows T13 go red in the PR that causes it; if it still reaches main, TRANSIENT escalation after 3 runs
    alert_route: failing CI check on the PR, then #8856 comment
  - mode: a rehearsal arm really skips on main runs
    detection: probe counts SKIP_MARKERS hits in relayed lines, exit 1
    alert_route: #8856 alert issue or comment; ADR-188 trigger 1
  - mode: suite does not run in the sampled window
    detection: probe reason names that case separately from relay-missing
    alert_route: TRANSIENT, escalating after 3 runs
logs:
  where: GitHub Actions logs of infra-validation.yml (relay lines) and of the monitor workflow (verdict)
  retention: GitHub default run-log retention (90 days)
discoverability_test:
  command: bash scripts/followthroughs/t5-skip-persistence-bound-7510.sh
  expected_output: PASS: or FAIL: or TRANSIENT:
  credentials_required: "GH_TOKEN with actions:read - Actions run logs are retrievable only through the authenticated GitHub API, so no unauthenticated probe verifies the same property"
```

## Guard Contract

### Guard 1 - suite evidence reaches the probe through the capturing runner

**Property.** Every column-0 `SKIP (loud):` line and the rehearsal terminal line that the suite prints on a
run are present in that run's Actions log, in a form the probe's `SUITE_TERMINAL` and `SKIP_MARKERS` match.

**Assembly.** The quantification is over the whole path, not today's members: (1) the suite's emitters, the
`arm_skip` `echo` and the terminal `echo` in `git-data-runcmd-rehearsal.test.sh`; (2) the capture site, the one
shim line `"$@" bash "$s" >"$logdir/$key.log" 2>&1` in `run-registered-suites.sh`; (3) the single chokepoint
`relay_evidence`, which must read the log dir before the `rm -rf` reap and run inside the `SOLEUR|` block;
(4) the runner's two evidence constants (`EVIDENCE_SKIP_ERE`, `EVIDENCE_TERMINAL`); (5) the consumer, the
probe's `SUITE_TERMINAL` and every `SKIP_MARKERS` entry; (6) other readers of runner stdout that must NOT
change (`main-health-monitor.yml` excerpt filter, T6v summary pin, `scripts/test-all.sh` nested run). The
suite's emitters are reachable by a second route not under this guard: suites that CI runs directly rather
than through the runner (privileged `sudo bash` steps) already log raw output and are out of the relay's scope.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `relay_evidence` call, or make its loop iterate zero suites (own dispatch: relays nothing and exits 0) | RED: T13 relay-present row (it asserts at least one relayed line); scored by the runner suite's T9 |
| 2 | Relay only the first suite then `break` (second member after a compliant first) | RED: T13 fixture has skips in two suites and asserts both are relayed |
| 3 | Emit the relay lines outside the `SOLEUR\|`-prefixing pipeline (the relay's own bypass; distinct from the existing `drop-prefix` row, which is killed by T6k) | RED: T13 asserts no relayed line starts at column 0 |
| 4 | Edit the probe's `SUITE_TERMINAL` literal, or the runner's `EVIDENCE_TERMINAL_ERE` | RED: scored by a small in-suite harness in the PROBE suite (T9 cannot score it: it mutates only the runner copy and greps its own file's output). The harness runs (k) as a function over a copy of the probe and a copy of the runner (both tolerate being copied), applies the edit, and expects the terminal-only case to report FAIL |
| 5 | Move the relay call after the `rm -rf "$SOLEUR_SUITE_LOGDIR"` reap | RED: T13 relay-present row (the logs are gone); scored by the runner suite's T9 |

**Harness rows.** Edit to the SUITE, not the guard: feed (k) a constant canned log instead of the runner's real
stdout -> RED via the precondition that the captured runner output contains at least one `relay` line. The
must-PASS input that differs from the canonical is the terminal-only case (no skip line, a different count
than the skip case), and the unrelated-suite `not root` discrimination is already pinned by probe test (d).
The suite-end value check (the real suite's terminal `echo`, expanded and matched against the runner's regex)
reds if the suite text changes in a way the regex misses.

**Anchor.** The suite-source content anchors are checked against the tracked file at test time, and the real
proof sits outside the commit: the post-merge main run log (`gh run view <id> --log`) must carry the relay line,
and the first real monitor run must read non-TRANSIENT (Phase 5). A weakening that edits the relay, the probe and
the fixture together passes the unit rows but cannot satisfy the live log check.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Find out whether the suite output marker moved or the sampled runs genuinely skipped the suite" [issue #10786] | Research Insights diagnosis (marker moved, #8763) | mapped |
| 2 | "repair the probe (or its marker) so a real skip streak is reported as FAIL and not TRANSIENT" [issue #10786] | Phases 0-2 (runner relay + contract tests) | mapped |
| 3 | "The next probe run reads a non-TRANSIENT result against a window in which the rehearsal suite ran" [issue #10786] | Phase 5 post-merge verification | mapped |
| 4 | "Closes #10786 in the PR body" [brief] | Phase 5 step 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Runner `relay_evidence` (Files to Edit: run-registered-suites.sh) | "repair the probe (or its marker) so a real skip streak is reported as FAIL and not TRANSIENT" | asked |
| End-to-end contract tests (probe suite `(k)`, runner suite T13/T9) | "so a real skip streak is reported as FAIL and not TRANSIENT" | inferred - justification: without a test that runs the real runner into the probe the marker can move a second time silently, which is exactly how #10786 arose |
| Probe header correction (Phase 3, comment only) | "Find out whether the suite output marker moved or the sampled runs genuinely skipped the suite" | inferred - justification: the probe's header still says it reads the suite's own SKIP line from the logs, which is false without the relay; a wrong header is how the next reader repeats this investigation |
| Discoverability baseline bump (plugins/soleur test) | "The next probe run reads a non-TRANSIENT result" | inferred - justification: the plan declares `credentials_required` for its observability probe (run logs need an authenticated API) and the repo-global G1 ratchet counts declaring plans, so the baseline must move in the same PR or CI is red |
| ADR-252 consequence note | "Find out whether the suite output marker moved" | inferred - justification: ADR-252 records per-suite capture as a decision without its observer consequence; the repo rule is that architecture records do not lag the change |
| ADR-188 note | "The next probe run reads a non-TRANSIENT result" | asked (the ruling text names #10786 as the repair; the note records that the repair landed) |
| Phase 5 verification | "The next probe run reads a non-TRANSIENT result against a window in which the rehearsal suite ran" | asked |

### Split Assessment

- Subsystems touched: 4 - apps/web-platform, scripts, plugins/soleur, knowledge-base
- Planned files: 7 edited + 2 created | Estimated changed lines: ~300
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the fourth root is plugins/soleur, touched only by a mechanically forced one-line
  `BASELINE_DECLARED_PROBES` bump that this plan's own `credentials_required` declaration makes the G1 ratchet
  demand; splitting it out would leave that ratchet red on the PR that declares the probe, and the
  knowledge-base root holds the ADR notes and spec records. No seam exists that leaves either half green.

## Acceptance Criteria

### Pre-merge (PR)

- [x] Phase 0 tests were observed RED for the right reason before Phase 1 (recorded in the PR body).
- [x] `bash apps/web-platform/infra/run-registered-suites.test.sh` passes, including T13 rows and the extended
      T9 matrix with every new row reporting "killed by", and its floors raised and itemised.
- [x] `bash scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` passes, including the end-to-end
      `(k)` rows (skip -> exit 1, terminal only -> exit 0, neither -> exit 2) and the pre-fix-shape case.
- [x] A relayed line never starts at column 0 and the runner's summary line is byte-identical and last
      (T6u/T6v unchanged and green).
- [x] `bash plugins/soleur/test/main-health-monitor-workflow.test.sh` still passes (public excerpt filter).
- [x] `bash plugins/soleur/test/c4-count-parity.test.sh` passes (no embedded cardinality moved).
- [ ] ADR-252 carries the consequence note and ADR-188 records the repaired evidence path; PR body says the streak-cache defect is deferred and links its
      tracking issue.
- [ ] PR body contains `Closes #10786`.

### Post-merge (automated by the shipping agent)

- [ ] The push run of `infra-validation.yml` for the merge commit succeeds and its log contains
      `SOLEUR| relay git-data-runcmd-rehearsal` (`gh run view <id> --log | grep -c ...` >= 1).
- [ ] A dispatched monitor run reports `probe verdict: pass` or `fail`, not `transient`; ADR-188 is updated
      with the observed verdict.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled design A (runner-side relay) over a suite-emitted contract, an artifact download and a blind
positive control; relay from every suite log with a 50-line cap; keep probe literals; pin drift with an
end-to-end test; defer the streak-cache eviction to its own issue. Risks to pin: relayed lines never at column
0, relay block gated on a match, relay placed before the summary line and the reap, each skip counted once.
Product/UX, marketing, legal, finance, sales, operations and support: no implications (CI-internal tooling,
no user surface, no personal data).

## Test Scenarios

- Given a runner fixture where the mapped rehearsal suite prints a `SKIP (loud): T5 ...` stderr line and a
  terminal line, when the real runner runs and its stdout is fed to the probe, then the probe exits 1 (unit/integration).
- Given only the terminal line, then the probe exits 0 with "across N observed" (integration).
- Given neither line (the pre-fix production shape: only `PASS <path>`), then the probe exits 2 (integration).
  (The reason-text diagnostic this scenario once asked for was cut at plan review; the exit code is the contract.)
- Given a clean fixture suite with no evidence lines, the runner emits no `SOLEUR|` line (T6u regression, unit).
- Given a suite printing 200 `SKIP (loud):` lines, the relay emits exactly 50 (unit).
- Given a RED suite that printed a skip line early, the line appears relayed once (unit).
- Given an indented `SKIP (loud): not root` line from another suite (the real `infra-config-apply.test.sh`
  shape), the anchored relay does not emit it; a synthetic column-0 variant would be relayed and the probe
  would still not count it (arm-name discrimination, probe test (d)) (unit).
- Regression for #10786: run the probe against a canned log shaped like main run 39612112094 (only
  `PASS apps/.../git-data-runcmd-rehearsal.test.sh`) and assert TRANSIENT with the new reason (integration).

## Dependencies & Risks

- The first real read may be FAIL if an arm genuinely skipped on recent main runs. That is the intended
  outcome of the repair (ADR-188 trigger 1), not a defect; the PR must not suppress it.
- Until the streak-cache issue lands, the 3-consecutive-TRANSIENT escalation is unreliable (cache eviction); a
  future marker regression is therefore caught primarily by the end-to-end test, not by the nightly cron.
- The runner header documents a PIPE_BUF/pipe invariant on the children's stdout; the relay is parent-side and
  must not change it. The `SOLEUR|` prefix is the only thing keeping relayed text out of the public
  monitor excerpt; mutation row 4 pins it.
- The sample window still contains pre-merge logs without the relay; the probe stays TRANSIENT on them and
  only needs one post-merge observed run, which the merge's own push run provides.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one
  carries threshold `none` with the sensitive-path scope-out bullet because `apps/web-platform/infra/` matches
  the canonical regex.
- Do not "fix" the TRANSIENT by weakening the positive control (design D). A probe that can no longer see the
  skip is the defect, not the symptom.
- `grep -q` after a pipe under `set -o pipefail` loses its match (SIGPIPE): use here-strings or `mapfile -n`
  in the relay and in any new probe code; the probe file's own comments record the 2026-08-19 measurement.
- Tests asserting absence (no column-0 relayed line, no `SOLEUR|` line on a clean run) must use count
  comparisons (`grep -c` equals 0, which prints nothing on a bad pattern) or an explicit `rc -eq 1`, never
  `! grep -q`: a negation folds grep's rc 2 (pattern did not compile) into "no match".
- The relay prints text a suite wrote. It must stay `SOLEUR|`-prefixed (a column-0 `::error::`-style line
  would be read by Actions as a workflow command, and a column-0 `[FAIL]`/`RED` line would reach the public
  main-health-monitor excerpt), and must be length-capped (`cut -c1-400`) and count-capped (50 per suite).
- Any heading rename in this plan that `lint-guard-contract.py` keys on (`## Guard Contract`, `### Guard n`)
  must keep the entry count; re-run the lint after edits.

## References & Research

- Issue #10786; monitor issue #8856; ruling #9394 (ADR-188 User-Challenge, 2026-10-22); runner change PR #8763
  (ADR-252); probe origin #7510 / #7574; capture diagnostics #7376.
- Evidence runs: main `infra-validation.yml` 39612112094 (marker absent, `PASS` line present); monitor runs
  36314716954 (last real read, PASS 09-27), 36422425962 (first TRANSIENT, 09-28), 39118197290 (3/3 escalation),
  39766766225 (latest, TRANSIENT 2/3).
