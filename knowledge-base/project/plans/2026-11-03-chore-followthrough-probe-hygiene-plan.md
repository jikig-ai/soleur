---
title: "chore: follow-through probe hygiene — retire inngest-trace-retention-5150, repair inngest-cli-apply-window-7463"
type: fix
date: 2026-11-03
slug: chore-followthrough-probe-hygiene
branch: feat-one-shot-11832-9782-probe-hygiene
issue: 11832
closes: [11832, 9782]
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# chore: follow-through probe hygiene — retire inngest-trace-retention-5150, repair inngest-cli-apply-window-7463

## Enhancement Summary

**Deepened on:** 2026-11-03 | **Sections enhanced:** gate-verified | **Passes:** deepen-plan halt gates §4.6–4.13 all PASS or correctly skipped; agent fan-outs discharged inline (no subagent spawner on this harness — Reviewed-Coverage: sequential-fallback)

### Key gate outcomes

1. **§4.11 Guard Contract** — `lint-guard-contract.py` green (1 entry, 6-row matrix incl. dispatch + second-member + must-PASS).
2. **§4.12 Scope Check** — one unfenced section, 8 mapped asks, inferred items justified.
3. **§4.8 PAT / §4.9 .pen / §4.10 encryption / §4.13 task-design / §4.5 network / §4.55 downtime** — no trigger or pass; the §4.5 keyword hit is "unreachable" inside "newly-reachable" prose, not a connectivity symptom.
4. **§4.4 precedent-diff** — suite shape is not novel; donor `scripts/followthroughs/git-data-boot-poll-8178.test.sh` cited.
5. **§4.45 realism** — the plan's negative claims (no jq crash, never-FAIL on vanished history, no STALE verdict) each map to a named suite arm or CI gate.

## Overview

Batch of two same-defect-class follow-through probes under `scripts/followthroughs/` — a probe that cannot reach a terminal verdict.

- **#11832 (retire):** tracker #5150 is CLOSED with verified drain (`INNGEST_TRACE_RETENTION_OUTCOME=ok`, 2026-11-02). The probe `scripts/followthroughs/inngest-trace-retention-5150.sh` still sweeps nightly against it. Its own header prescribes retirement: delete the probe + test, drop the `run_suite` line, remove the tracker directive. The issue's 3-step list undercounts the true footprint — the probe also sits in the betterstack-emitter allowlist, the affected-index, and two generated shard manifests (see Research Reconciliation).
- **#9782 (repair):** `scripts/followthroughs/inngest-cli-apply-window-7463.sh` prints `jq: error: Cannot iterate over null (null)` once per enumerated dispatch run — `.[].jobs[]` iterates null when a jobs payload lacks `.jobs` — so every per-run query yields "no matching job" and the probe reports NOT-YET forever. Its enrolled tracker #9224 (closed on manual evidence, still in the sweeper's closed-set) can never observe a real verdict. Fix per the issue: `.jobs? // []` guard plus a `CANNOT ESTABLISH` (rc 3) arm when ALL per-run jobs queries fail — and, per followthrough convention, a verdict-matrix `.test.sh` pinning the arms (the probe currently has none).

## Research Insights

**Premise validation (Phase 0.6):** all cited artifacts verified 2026-11-03. #11832 OPEN (labels `type/chore`, `meta/machinery`); #9782 OPEN (`type/bug`, `bot-fix/attempted`, `meta/machinery`); #5150 CLOSED (verified drain); #7463 CLOSED; #9224 CLOSED "on manual evidence" and still carries the `<!-- soleur:followthrough script=scripts/followthroughs/inngest-cli-apply-window-7463.sh … -->` directive at body line 26, so the sweeper's closed-set pass still runs the probe; #11869 CLOSED; PR #11893 MERGED; epic #10390 OPEN with six confirmed-stale unticked rows (#8595, #8841, #9139, #8874, #8316, #9705 — plus #8764 and #10136, also CLOSED, on the same two lines); collision-precheck found PR #11994, which is this pipeline's own auto-created draft on this branch, not a foreign duplicate. Both probe files and all registry rows below confirmed present on the branch.

**Property List (Phase 0.6b):**

- P1 — A closed-and-verified tracker leaves no live probe machinery behind: every tracked file or registry row naming the retired probe resolves to an artifact that exists.
- P2 — A probe whose every per-run API read fails reports CANNOT ESTABLISH (rc 3), distinguishable from "no matching job" (NOT-YET, rc 2); a probe must be able to reach a terminal verdict.
- P3 (convention-derived) — The probe's exit semantics are pinned by a registered verdict-matrix suite, as virtually every sibling under `scripts/followthroughs/` carries.

**Cut List (Phase 0.6b):** none. Both issue-specified mechanisms are minimal — deletion is the cheapest realization of P1, and a jq guard + failure-count arm is the cheapest realization of P2 (no new machinery). The new test suite is convention-mandated coverage of P2, not a new mechanism.

**Relevant files:**

| File | Role |
|---|---|
| `scripts/followthroughs/inngest-trace-retention-5150.sh` | DELETE — the retired probe |
| `scripts/followthroughs/inngest-trace-retention-5150.test.sh` | DELETE — its verdict-matrix suite |
| `scripts/test-all.sh:6016-6019` | DELETE — 3-line comment block + `run_suite` registration for the 5150 suite |
| `scripts/lib/test-affected-paths.sh:3346` | DELETE — row in `AFFECTED_SCRIPTS_BETTERSTACK_EMITTER_READ_PATHS` |
| `scripts/lint-betterstack-emitter-read.sh:158` | DELETE — `ALLOW` rationale row; the lint's STALE arm (:325-335) fails CI while it points at a missing file |
| `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` | REGENERATE — `python3 scripts/regenerate-shard-manifest.py --incremental --write` is the canonical suite add/remove path (script docstring :38-50); drops the 5150 rows, registers the new 7463 suite |
| `scripts/followthroughs/inngest-cli-apply-window-7463.sh:78-80` | EDIT — split the `gh api` capture from the `jq` parse; `.jobs? // []` guard; per-run failure counters |
| `scripts/followthroughs/inngest-cli-apply-window-7463.test.sh` | CREATE — verdict-matrix suite; donor `scripts/followthroughs/git-data-boot-poll-8178.test.sh` (PATH-shimmed `gh` answering per-id fixtures, exits 64 on unwritten argv, instrument self-test, `assert_fixture_dir` byte-identical copy) |
| `scripts/test-all.sh` (new line) | ADD — explicit `run_suite` registration; `scripts/followthroughs/*.test.sh` matches no `SUITE_GLOBS` entry, so unregistered suites are orphans (`lint-orphan-test-suites.sh`) |
| `plugins/soleur/test/fixture-relative-assert.baseline.txt` | CONDITIONAL REGEN — the ratchet pins live scanned-site count by EQUALITY; if the new suite adds fixture sites (mktemp/shim dirs), `--write-baseline` is required |

**Exit-code contract (sweeper):** `scripts/sweep-followthroughs.sh` maps 0=PASS, 1=FAIL (reopens a closed tracker), 2=NOT-YET/TRANSIENT, 3=CANNOT ESTABLISH, 5=notify-only, 78=xtrace refusal (`:915`). `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` is the authority: retirement written as a `RETIREMENT:` header line, re-census `git grep <unnumbered-stem>` over live dirs at retirement time and disposition every hit; never gate exits on `: "${VAR:?}"`; `gh api --paginate` emits per-page arrays needing `jq -s`.

**Institutional learnings applied:**

- `2026-11-03-the-classification-table-contradicted-the-census-and-shipped-the-p1.md` — derive the file list from the measured census, not paraphrase; every "already present" claim here was grep-verified this session.
- Convention-suite landmines for the new test (carried from prior runs): no `| grep -q` pipes, no `env -u`, no literal `<<-`, `\x24\x24` not `$$` in unquoted `<<PY` heredocs, six-assignment floor windows, mutate fragments byte-match via `grep -F`, `shellcheck -S warning` clean on every touched file.
- `set -euo pipefail`/`set -u` pitfalls: `((var++))` returns 1 at var=0 — use `var=$((var + 1))` (constitution).
- GitHub run-history retention can empty the anchor query; the probe must degrade to NOT-YET, never FAIL, on vanished history (convention: a one-time-event probe must not exit 1 on a closed tracker).

**Functional-overlap / external research:** skipped — repo-internal CI machinery with an issue-prescribed fix; no community artifact governs a `scripts/followthroughs/` probe (no subagent spawner on this harness; check discharged inline). **SpecFlow:** discharged inline — the exit-code truth table below enumerates every branch the bash conditionals admit.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (verified 2026-11-03) | Plan response |
|---|---|---|
| #11832: 3-step deletion (probe + test, run_suite line, directive) | Footprint is 7 sites: the 3 named + `test-affected-paths.sh:3346`, `lint-betterstack-emitter-read.sh:158` (STALE arm makes this one load-bearing), `suite-durations.tsv` + `suite-shard-legs.tsv` generated rows | Phase 1 enumerates all 7; reconciliation IS this table |
| #11832: "remove the directive from #5150's body" | The directive is a GitHub issue-body artifact, not a tracked file — no repo edit can remove it | Post-merge action (`gh issue edit`), not a diff item |
| #9782: "one jq guard + one failure arm" | Probe also has NO test suite (only followthrough probe without one found in the census) | Phase 2 adds the convention-mandated verdict-matrix suite (inferred item, Scope Check) |
| Epic #10390 checklist "in a tracked repo file" | `git grep 10390 knowledge-base/` hits are citations (runbooks, ADRs, archived specs), not a tracked copy of the body — the body is GitHub-only | Post-merge comment/edit action per the batch rule |

## Problem Statement / Motivation

Two enrolled follow-through probes each sit in a state where the machinery runs but can never conclude:

- `inngest-trace-retention-5150.sh` verifies a condition already verified — #5150 closed on the `INNGEST_TRACE_RETENTION_OUTCOME=ok` drain — and now produces sweeper noise plus a maintenance surface (allowlist row, index row, shard rows) that rots the moment the file leaves.
- `inngest-cli-apply-window-7463.sh` verifies a condition it cannot measure: the `.[].jobs[]` jq term errors on any jobs payload lacking `.jobs` (error shapes, non-array paginate items), each failure is swallowed to "no matching job" by `|| true`, and the loop lands NOT-YET on every sweep. On the closed tracker #9224 a never-measuring probe is machinery noise; on any future open tracker it is a permanent stall.

## Proposed Solution

**Phase 1 — retire the 5150 probe (#11832).** Delete the two probe files and every registry reference enumerated above; regenerate the shard manifests; strip the tracker directive post-merge.

**Phase 2 — repair the 7463 probe (#9782).** Split the `gh api` capture from the `jq` parse so transport failure and empty-result are distinguishable; guard the jq term with `.jobs? // []`; count per-run failures and exit 3 when every enumerated run's jobs read failed; add the verdict-matrix suite and register it.

```bash
# Sketch (implementer finalizes against convention-suite landmines):
raw="$(gh api --paginate "repos/$REPO/actions/runs/$rid/jobs?per_page=100" 2>/dev/null)" \
  || { jobq_failed=$((jobq_failed + 1)); continue; }
jobs="$(jq -rs '[.[].jobs? // [] | .[] | select(.name | test("inngest.host.replace"; "i")) | .conclusion][]' <<<"$raw")" \
  || { jobq_failed=$((jobq_failed + 1)); continue; }
# after the loop:
if [[ -z "$replace_run_id" ]]; then
  if (( jobq_total > 0 && jobq_failed == jobq_total )); then
    echo "CANNOT-ESTABLISH: all $jobq_total per-run job queries failed" >&2; exit 3
  fi
  echo "NOT-YET: post-merge dispatches exist but none reached an inngest_host_replace job" >&2; exit 2
fi
```

## Technical Considerations

- **Counters:** `jobq_total`/`jobq_failed` increment via `var=$((var + 1))`, never `((var++))` — post-increment returns exit 1 at var=0 and would trip a strict-mode shell.
- **`.jobs? // []` semantics:** a payload whose `.jobs` is absent or null now yields "no replace job in this run" — correct for a dispatch that ran a different `apply_target`. An error-shape payload also yields `[]`; that residual is accepted by the issue's own fix direction and bounded by the all-fail rc-3 arm (a *uniformly* broken API surface is CANNOT ESTABLISH, not NOT-YET).
- **`gh api` capture separated from `jq`:** inside `$(cmd | jq … || true)` the transport rc is unobservable — `jq -rs` on empty stdin prints `[]` with rc 0, so a dead `gh` is indistinguishable from zero jobs. Two-step capture is the only honest split.
- **Suite shape (donor `git-data-boot-poll-8178.test.sh`):** PATH-shimmed `gh` answering per-arm fixture files (`pr.json`, `runs.json`, `jobs-<id>.json`, `<name>.fail`), exits 64 on unwritten argv (the #7081 stub-argv-fidelity class), instrument self-test on pass/fail counters, `assert_fixture_dir` byte-identical copy, `env -i` probe invocations. Convention landmines listed in Research Insights apply verbatim.
- **Affected-index / shard manifests:** `test-affected-paths.sh` row removal is a line delete; `suite-durations.tsv` + `suite-shard-legs.tsv` regenerate via `python3 scripts/regenerate-shard-manifest.py --incremental --write` <!-- verified: 2026-11-03 source: scripts/regenerate-shard-manifest.py docstring -->. If the new suite adds fixture-scan sites, `plugins/soleur/test/fixture-relative-assert.test.sh` pins the count by equality — rerun with `--write-baseline`.
- **Run-history retention:** the probe anchors on PR #9201's merge timestamp and enumerates post-merge dispatches; GitHub run retention eventually empties that set, which lands NOT-YET (exit 2) — never exit 1 — on the closed #9224. This is already the correct arm; keep it.
- **Sweeper action per newly-reachable exit code** (sharp-edge: a fix that makes a probe's verdict newly reachable must enumerate what each code triggers, and re-verify criteria the unreachable verdict was masking): on the closed tracker #9224 the closed-set pass maps rc 0 → verdict confirmed, no action; rc 1 → REOPEN; rc 2 → no action; rc 3 → CANNOT ESTABLISH note, no reopen. Post-fix, rc 0 becomes genuinely reachable and the evidence (successful `inngest_host_replace` job + post-dating green health run) is historical and stable, so a PASS is correct closure-confirmation — not a stale-evidence close of an open tracker. An rc-1 reopen fires only when the NEWEST dispatch carrying an `inngest_host_replace` job concluded failure/cancelled — the correct semantics, since the newest attempt supersedes the earlier success; nothing the fix changes alters which verdict is reachable, only that the probe can measure it at all.
- **No infra, no UI, no datastore:** Phases 2.7 (GDPR), 2.8 (IaC), 2.9.3 (Task Design), 2.10 (ADR/C4), 2.11 (Encryption) evaluate to skip — no regulated-data surface, no new infrastructure, no new autonomous-task surface (a `run_suite` registration is not a `CHECK_REGISTRY`/reminder arm), no architectural decision, no persistent store or new cross-component connection.

## Files to Edit

| File | Change |
|---|---|
| `scripts/followthroughs/inngest-cli-apply-window-7463.sh` | `.jobs? // []` guard, two-step gh/jq capture, `jobq_*` counters, rc-3 arm (~:74-94) |
| `scripts/test-all.sh` | Delete the 5150 comment block + `run_suite` (:6016-6019); add the 7463 `run_suite` registration + comment |
| `scripts/lib/test-affected-paths.sh` | Delete `"scripts/followthroughs/inngest-trace-retention-5150.sh"` (:3346) |
| `scripts/lint-betterstack-emitter-read.sh` | Delete the `ALLOW["scripts/followthroughs/inngest-trace-retention-5150.sh"]` rationale row (:158) — STALE arm enforces |
| `scripts/suite-durations.tsv` | Regenerate (drops 5150 row :417, adds 7463) |
| `scripts/suite-shard-legs.tsv` | Regenerate (drops 5150 row :419, adds 7463) |
| `plugins/soleur/test/fixture-relative-assert.baseline.txt` | Regenerate only if the suite's live site count moves |

## Files to Create

| File | Change |
|---|---|
| `scripts/followthroughs/inngest-cli-apply-window-7463.test.sh` | Verdict-matrix suite per the `git-data-boot-poll-8178.test.sh` donor shape |

## Files to Delete

| File | Reason |
|---|---|
| `scripts/followthroughs/inngest-trace-retention-5150.sh` | #5150 closed; probe retired per its own `RETIREMENT:` header |
| `scripts/followthroughs/inngest-trace-retention-5150.test.sh` | Suite for a deleted probe |

## Open Code-Review Overlap

96 open `code-review` issues scanned (2026-11-03); none names `inngest-trace-retention-5150` or `inngest-cli-apply-window-7463`. File-level matches, all **acknowledge** (different concern, no shared hunk):

- #7942 — touches `scripts/test-all.sh` prose-wise but concerns `plugins/soleur/test/*.mutation.sh` gating, not the `run_suite` lines this plan edits.
- #10462 (zot fill-rate rename) — would edit other rows of the same `lint-betterstack-emitter-read.sh` allowlist; no conflict with deleting the 5150 row.
- #11312, #10464, #10463, #8435 — name other `scripts/followthroughs/` probes (monitor_sig, zot fill-rate, gsc-indexing-drain); disjoint files.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst case is a sweeper verdict line or a CI suite failure visible only to operators.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no vector — the diff touches read-only CI verification probes and their registries; the 7463 probe reads GitHub run/job metadata under the workflow's own `GH_TOKEN`.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal machinery with operator-visible blast radius only; no user artifact, data surface, or production runtime is touched.

*Scope-out override:* `threshold: none, reason: edits confined to CI follow-through probes, their test suite, and generated registries — no user-facing, credential-handling-beyond-GH_TOKEN, or production-runtime surface`

## Observability

```yaml
liveness_signal:
  what: "sweeper verdict lines on tracker #9224 (PASS / FAIL / NOT-YET / CANNOT ESTABLISH) and the green registered suite in CI"
  cadence: "probe: each scheduled-followthrough-sweeper run; suite: every CI test-scripts shard"
  alert_target: "tracker issue comment; CI failure"
  configured_in: "scripts/sweep-followthroughs.sh (verdict map ~:915); scripts/test-all.sh (run_suite registration)"
error_reporting:
  destination: "sweeper comment on the tracker; suite FAIL lines on stderr"
  fail_loud: "probe exit 3 prints 'CANNOT-ESTABLISH: all <n> per-run job queries failed' to stderr; suite prints 'FAIL: <arm>' per failed row"
failure_modes:
  - mode: "uniform GitHub API outage — every per-run jobs read fails"
    detection: "probe exit 3 renders CANNOT ESTABLISH on the tracker"
    alert_route: "sweeper comment on #9224"
  - mode: "probe regresses to unconditional NOT-YET (the #9782 defect reintroduced)"
    detection: "suite arm: all-fail fixture must exit 3, not 2"
    alert_route: "CI test-scripts shard red"
logs:
  where: "sweeper run log (scheduled-followthrough-sweeper.yml); CI suite output"
  retention: "GitHub Actions default"
discoverability_test:
  command: "grep -c 'CANNOT-ESTABLISH: all' scripts/followthroughs/inngest-cli-apply-window-7463.sh"
  expected_output: "1"
```

## Guard Contract

### Guard 1 — inngest-cli-apply-window-7463 verdict suite

**Property.** The probe reaches PASS/FAIL/CANNOT-ESTABLISH only on real per-run API evidence — a uniformly failing jobs read is rc 3, an absent-or-null `.jobs` payload is "no replace job" (never a crash and never a false verdict), and the success path requires BOTH a post-merge successful `inngest_host_replace` job AND a post-dating green health run.

**Assembly.** Every exit site of `scripts/followthroughs/inngest-cli-apply-window-7463.sh` (the while-loop arms and the post-loop dispatch, the health-run half) exercised through the PATH-shimmed `gh` in `inngest-cli-apply-window-7463.test.sh`; the suite is reachable only through its `run_suite` line in `scripts/test-all.sh` (the registration is the chokepoint — `lint-orphan-test-suites.sh` enforces it).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert the guard — `.jobs? // []` back to `.jobs[]` | RED — the null-`.jobs` fixture arm drives jq's `Cannot iterate over null` into the failure path |
| 2 | Drop the rc-3 arm so all-fail falls through to exit 2 | RED — all-fail arm asserts rc 3 (the guard's own verdict dispatch) |
| 3 | Break the second half: accept any post-merge health run regardless of `created_at` ordering | RED — a health run that pre-dates the replace must not PASS (second member after a compliant first) |
| 4 | Count a dispatch run with NO `inngest_host_replace`-named job as found | RED — non-replace dispatch fixture must be skipped, not matched |
| 5 | Suite-side: shim answers rc 0 for an argv the probe must not emit (unwritten shape exits 64) | RED — the argv-fidelity contract is asserted, not assumed |
| 6 | Suite-side must-PASS: a payload with `.jobs: []` (present but empty, differing from both null-`.jobs` and the success shape) | GREEN — a member the contract explicitly permits |

**Anchor.** The suite's oracles are fixture files committed beside it; the shim exits 64 on any argv outside the written set, so a probe whose queries drift is red before any fixture is read.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Delete `scripts/followthroughs/inngest-trace-retention-5150.sh` and `inngest-trace-retention-5150.test.sh`" [#11832] | Files to Delete; Phase 1 | mapped |
| 2 | "Drop its `run_suite` line in `scripts/test-all.sh`" [#11832] | `scripts/test-all.sh` edit; Phase 1 | mapped |
| 3 | "Remove the `<!-- soleur:followthrough -->` directive from #5150's body" [#11832] | Post-merge action (GitHub body, untracked) | mapped |
| 4 | "Guard the jq: `[.[].jobs? // [] \| .[] \| select(...)]`" [#9782] | `inngest-cli-apply-window-7463.sh` edit; Phase 2 | mapped |
| 5 | "plus a `CANNOT ESTABLISH` (rc 3) arm when ALL per-run job queries fail" [#9782] | same edit; suite arm 2 pins it | mapped |
| 6 | "Epic #10390 checklist refresh should ride the next epic-touching PR — if the epic body is only a GitHub issue body, note it as a post-merge comment action" [brief] | Post-merge action | mapped |
| 7 | "#11893's paused cutover-flip-silent alert … rule whether to fold a re-enable into this PR, file a tracking issue, or leave for the epic" [brief] | Ruled: leave for epic — see decision-challenges.md; no diff item | mapped |
| 8 | "Optional third seat (rule in or out): #9659" [brief] | Ruled: out — see decision-challenges.md; no diff item | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Delete both 5150 files | "Delete `scripts/followthroughs/inngest-trace-retention-5150.sh` and `inngest-trace-retention-5150.test.sh`" | asked |
| `test-all.sh` 5150 block removal | "Drop its `run_suite` line in `scripts/test-all.sh`" | asked |
| `test-affected-paths.sh` + emitter-read ALLOW row removal | — | inferred — justification: retirement convention's re-census rule; the emitter-read STALE arm fails CI while an allowlist key names a missing file (`lint-betterstack-emitter-read.sh:325-335`) |
| TSV regen | — | inferred — justification: shard manifests are generated (`generated-from-*` headers); a removed/added suite leaves stale rows the regen owns |
| fixture-relative-assert baseline regen | — | inferred — justification: the ratchet pins live site count by equality; a new fixture-bearing suite moves it |
| `.jobs? // []` + rc-3 arm | asks 4–5 | asked |
| New `inngest-cli-apply-window-7463.test.sh` + registration | — | inferred — justification: the probe is the only followthrough found without a verdict suite; the #9782 defect class (a probe that cannot reach terminal state) is exactly what a registered exit-code harness exists to catch (`lint-orphan-test-suites.sh`, sibling suite convention) |
| Post-merge directive strip (#5150) + epic checklist comment (#10390) | asks 3, 6 | asked |

### Split Assessment

- Subsystems touched: 2 — `scripts/` (probes, lints, manifests), `plugins/soleur/test/` (baseline only)
- Planned files: 9 | Estimated changed lines: ~330 (of which ~250 the new test suite)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `scripts/followthroughs/inngest-trace-retention-5150.sh` and `inngest-trace-retention-5150.test.sh` are absent from the tree; `git grep -n 'inngest-trace-retention-5150' -- scripts/ plugins/` returns zero hits. Positive counterpart (AC2/AC4/AC5 assert what the diff ADDS).
- [ ] AC2 — `scripts/test-all.sh` contains no `inngest-trace-retention-5150` `run_suite` or comment, and registers `scripts/followthroughs/inngest-cli-apply-window-7463` exactly once.
- [ ] AC3 — `bash scripts/lint-betterstack-emitter-read.sh` exits 0 on the live tree (no `STALE` line for the retired probe).
- [ ] AC4 — `bash scripts/followthroughs/inngest-cli-apply-window-7463.test.sh` exits 0 and its arms assert: all-per-run-fails → rc 3; a `.jobs`-absent payload → NOT-YET/FAIL as designed, never an uncaught jq error; replace-success + post-dating green health → rc 0; replace concluded failure → rc 1; no post-merge dispatches → rc 2.
- [ ] AC5 — `python3 scripts/regenerate-shard-manifest.py --incremental --write` leaves `suite-durations.tsv`/`suite-shard-legs.tsv` with no `inngest-trace-retention-5150` row and exactly one `inngest-cli-apply-window-7463` row each.
- [ ] AC6 — `bash scripts/lint-orphan-test-suites.sh` and `bash plugins/soleur/test/fixture-relative-assert.test.sh` both exit 0 (baseline regenerated with `--write-baseline` only if the suite reds on count drift).
- [ ] AC7 — `shellcheck -S warning` is clean on every touched `.sh`, and the new suite honors the convention landmines (no `| grep -q`, no `env -u`, no `<<-`, no `$$` in unquoted heredocs, six-assignment floor windows, `grep -F` byte-match for mutate fragments).

### Post-merge (agent-executable — `gh` calls, not operator steps; ship or work may run them)

- [ ] AC8 — `<!-- soleur:followthrough -->` directive stripped from #5150's body (`gh issue edit 5150 --body <stripped>`) so the sweeper's closed-set pass stops resolving a deleted script path.
- [ ] AC9 — Epic #10390 comment/body edit ticks the confirmed-closed rows (#8595, #8841, #9139, #8874, #8316, #9705, #8764, #10136 — plus #11832 and #9782 on closure).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI/verification tooling change (probe scripts, lint registries, generated manifests). Mechanical UI-surface scan: no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in the file lists.

## Test Scenarios

- Given a jobs payload where `.jobs` is null/absent on every enumerated run, when the probe runs, then it exits 3 with `CANNOT-ESTABLISH` (was: `jq: Cannot iterate over null` then rc 2 forever) — `unit`.
- Given a mix of runs where some job reads fail and one valid run has no `inngest_host_replace` job, when the probe runs, then it skips the failed/absent ones and reports NOT-YET or the real verdict — `unit`.
- Given a post-merge dispatch whose `inngest_host_replace` job succeeded plus a later green health run, when the probe runs, then it exits 0 — `unit`.
- Given a post-merge `inngest_host_replace` job that concluded `failure`/`cancelled`, when the probe runs, then it exits 1 — `unit`.
- Given the 5150 deletion, when `lint-betterstack-emitter-read.sh` walks the live tree, then no `STALE` verdict is emitted — `integration`.
- Given the manifest regen, when `test-all.sh` enumerates suites, then the 7463 suite is discovered via its `run_suite` line and the 5150 label is absent — `integration`.

## Success Metrics

- Sweeper renders `CANNOT ESTABLISH` (not silent NOT-YET) on a uniform API outage, and `PASS` on the #9224 evidence set.
- `git grep inngest-trace-retention-5150 -- scripts/ plugins/` is empty; CI green including the newly registered suite.

## Dependencies & Risks

- **Risk — residual noise:** a `.jobs`-absent payload that is actually an API error shape still yields `[]` (no-match); bounded by the all-fail rc-3 arm, per the issue's own fix direction.
- **Risk — regen churn:** `suite-shard-legs.tsv`/`suite-durations.tsv` headers stamp `generated-at`; sticky-LPT keeps the diff small but sibling PRs touching suites may conflict — landmine protocol: rebase onto origin/main before enqueue.
- **Merge-queue protocol (carried landmines):** push everything, freeze, wait for the `test` check-run on the head before `enqueuePullRequest`; `gh pr ready` on a force-push spawns a fresh run — read the ready-run's aggregate, not the cancelled push run.
- **Post-merge items are GitHub-side, not diff items:** the #5150 directive strip and the #10390 checklist refresh execute after merge (or via `gh` at work time if the pipeline elects); neither is a tracked-file change.

## References & Research

- Issues: #11832, #9782, #5150, #7463, #9224, #11869, #11893 (merged PR), #10390 (epic), #9659 (ruled out), #11336, #11337
- Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`; `scripts/sweep-followthroughs.sh` verdict map
- Donor suite: `scripts/followthroughs/git-data-boot-poll-8178.test.sh`
- Learning: `knowledge-base/project/learnings/2026-11-03-the-classification-table-contradicted-the-census-and-shipped-the-p1.md`
- Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed); recorded by Save Tasks.
- Reviewed-Coverage: sequential-fallback — this harness has no subagent spawner; research, specflow, and review lenses were discharged inline in one process.
