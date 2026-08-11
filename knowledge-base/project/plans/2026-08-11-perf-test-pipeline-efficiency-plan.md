---
title: "perf: cut the local full-gate wall clock — count skipped suites, path-gate the two heavy batteries, and measure the tmpfs the advisory lock protects"
date: 2026-08-11
slug: perf-test-pipeline-efficiency
branch: feat-one-shot-test-pipeline-efficiency
lane: cross-domain
type: enhancement
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

## Overview

A prior session measured a full `scripts/test-all.sh` run at roughly 45 minutes across 288 suites,
and its `TEST_TIMING_LOG` showed four suites accounting for about half the total. This plan takes the
38.6% of that wall clock held by two mutation batteries and stops paying it on diffs those batteries
do not guard, on local runs only. CI keeps running everything, and the change makes that a mechanical
property rather than a convention.

The six items from the post-mortem are all accounted for, but three of them ship smaller than briefed
and two ship as tracked deferrals. That is the outcome of review, not of effort, and every reduction
is stated with its evidence below and belongs in the PR body.

**[Revised 2026-08-11 after 3-agent plan review.]** The first draft was 921 lines proposing 9 new
files, 3 linters, a memo library and 28 acceptance criteria — a plan longer than the 866-line script
it modifies. Both the simplification panel and the correctness lens fired on the same scope, which is
the signal to delete rather than fix. Review also found three P0 defects, all of the same shape: a
guard written against the mental model that produced the plan, failing in the reassuring direction.
They are recorded in "Review Findings Applied" so the next reader sees what the plan nearly shipped.

---

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Probe | Verdict |
|---|---|---|
| Issue #7376 is OPEN and is a blocker, not a work target | `gh issue view 7376 --json state,title` | **HOLDS.** `OPEN`, `type/bug`, `priority/p2-medium`, `follow-through`. Title: "run-registered-suites.sh is flaky under its default -P on a 4-core runner (3 different suites across 2 of 6 executions)". Not a work target here. |
| ADR-133 is on disk and current, modified as recently as 532a6b348 | Read the full on-disk file | **HOLDS.** `status: active`, carries a 2026-08-10 (#7376) addendum recording two departures from its own decisions. Its rationale is stated below from the current file, not reconstructed from history. |
| Branch cut from 532a6b348 (merged PR #7423) | `git log --oneline -5` | **HOLDS.** |
| "No nightly workflow exists that runs the full gated set" (implied by the Item 1 brief) | `grep -rn 'test-all.sh' .github/workflows/*.yml` | **STALE — the plan's biggest scope reduction.** See Research Reconciliation. |
| A `TEST_GROUP=heavy` escape hatch is the right shape | Read `test-all.sh:100-137` | **RE-SCOPED.** `TEST_GROUP` is a *shard partition* selector validated by a `case` that exits 2 on anything else. A value meaning "all, plus force" breaks the invariant every `want_*` helper reads. |

### Research Reconciliation — brief vs. codebase

| Brief claim | Reality on disk | Plan response |
|---|---|---|
| Item 1 requires "a nightly scheduled workflow … so gated suites can never silently rot" | **Already exists, at 4x the requested cadence.** `.github/workflows/main-health-monitor.yml:309` runs `bash scripts/test-all.sh` with no `TEST_GROUP` (i.e. `all`); `:328` runs a second `TEST_GROUP=infra` step. Dispatched by the Inngest cron `cron-main-health-monitor`, `{ cron: "0 */6 * * *" }` (`.../functions/cron-main-health-monitor.ts:118`; `routine-metadata.ts:78` labels it "Every 6h"). It has **no `schedule:` block** — scheduling moved to Inngest as the single substrate — which is why a `grep -l 'schedule:'` sweep reports it absent. | **Add no workflow.** A second one forks the toolchain pin-set #7307 built to make this one non-vacuous (`main-health-monitor.yml:26-47`). Phase C instead makes the bypass mechanical, so this workflow becomes the enforcing un-gated backstop for free. |
| `TEST_GROUP=heavy` as the escape hatch | Partition selector with a fail-closed `case` (`test-all.sh:120-128`) | `SOLEUR_TEST_FORCE_ALL=1`, a separate boolean orthogonal to the partition. |
| "288 sequential suites … the sequential constraint is about Bun's FPE" | **Correct, and narrower than it looks.** `test-all.sh:32-34` cites the FPE learning; that is a `bun test` recursive-discovery constraint. **But** `apps/web-platform/infra/run-registered-suites.sh:334` *already* runs `xargs -P "$JOBS"`, `JOBS=min(nproc,6)` (`:215-217`) — the repo already has a parallel suite runner, and #7376 is the measured flakiness *of that runner*. | Item 4 is not "introduce parallelism"; it is "add a second instance of a mechanism whose first instance has an open, undiagnosed interference bug." Deferred — see Deferrals. |
| The advisory lock protects a 4 GiB tmpfs the runner no longer uses | **Half true, and the shipped instrument cannot settle it.** `test-all.sh:16` exports `TMPDIR=/var/tmp`; `:30` pins `TC_TMPDIR=/tmp` *independently* so the janitor keeps watching the tmpfs. Scratch did move off the protected mount. **But** the per-suite probe records `tmp_delta=<ENTRY COUNT>` (`test-all.sh:179`; `tc_tmp_entry_count` at `test-contention.sh:60`), while ADR-133's capacity verdict is about **bytes** — that ADR explicitly rejected count-based reaping because "4,294 small entries held 160 MB (4.5%) while three trees held 3.1 GiB (88%)". | The quantity the lock exists to protect has never been measured by the instrument shipped to measure it. Phase F swaps in a per-directory `du -sb` at the existing hook. |

### Relevant file paths (all read, not inferred)

- `scripts/test-all.sh` (866 lines) — `run_suite` at `:143-188` (`suites` increments at `:143-144`); the `TEST_TIMING_LOG`-gated probe hook at `:148-152` and `:177-181`; diff detection at `:237-259` (fail-SAFE arm `:256-259`); the two `run_suite` lines to gate at `:614` and `:760`; the infra gate's `if`-wrapper at `:781-814` (its `else` branch `:806-812`); the `N/N` summary at `:825`.
- `scripts/lib/test-contention.sh` — `tc_tmp_entry_count` `:60`, `tc_avail_mb` `:68`, `tc_used_pct` `:75` (`TC_DF_CMD` seam at `:58`), `tc_acquire` `:309` (kill switch `:315`, CI exemption `:322` = `[[ -n "${CI:-}" ]]`, `TC_LOCK_TIMEOUT=900` at `:51`), `tc_epilogue` `:348`.
- `scripts/lint-orphan-test-suites.sh` — iterates `scripts/*.test.sh` only (`:33`); per-suite anchor `:57`; `REQUIRED_RUNNERS` `:85-90`; the command-anchored runner regex `:101` with its rationale at `:96-100`.
- `tests/scripts/test-registry-gate-mutation-battery.sh` — `SUT_GATE`/`SUT_ENGINE` `:58-59`, suites `:60-61`, `for f in` companions `:70-72`, cloud-init `:73-76`.
- `scripts/cf-tunnel-liveness-gate-mutations.test.sh` — `SUITE_REL`/`BRIDGE_REL`/`APPLY_REL` `:37-39`, `INVENTORY_REL` `:64`, whole-tree sandbox copy `:53-54`, the M4 `git-data-cutover.yml` mutation `:200-205`, drift workflow `:227`/`:260`.
- `scripts/check-cloudflare-token-drift.test.sh:1791` — `W7_EXPECTED` pins **5 workflows / 6 call sites**.
- `scripts/validate-blog-links.sh:7-12,20-21` — the `_site/` co-location invariant; `_site` is untracked.
- `.github/workflows/main-health-monitor.yml:309,315-330` — the 6-hourly un-gated backstop and the comment explaining why its second step exists.

### Measured budget headroom (verify-before-cite)

```
$ python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1
[WARN] B_ALWAYS=44478 >= 44000 (AGENTS.md=5341 + AGENTS.rules.md=39137). Approaching the
46000-byte ratchet … Trim rule prose, or retire a rule via scripts/retired-rule-ids.txt.
```

Headroom to the REJECT cap: **1,522 bytes**; per-rule body cap **600 bytes** (`PER_RULE_CAP`,
`B_ALWAYS_REJECT` in that script). One rule body plus its ~55-byte `AGENTS.md` pointer lands at
~45,133. The revised plan files **one** rule and no manifest convention, so the byte-squeeze that
forced two conventions into one body in the first draft is gone. The `2>&1` is load-bearing: WARN and
REJECT print to stderr.

### Institutional learnings that bind this plan

1. **`knowledge-base/project/learnings/2026-08-11-every-guard-i-wrote-contained-an-instance-of-the-class-it-guarded.md`** — from the session that produced these six items. A guard written by the same author, in the same session, against the same mental model inherits that model's blind spot and fails in the reassuring direction. **This plan is the evidence:** review found three P0s and all three are instances of it. The review spawn prompt must ask reviewers to *name an implementation that satisfies each assertion while violating the property it is named for*.
2. **`.../2026-08-10-six-times-a-check-certified-something-other-than-what-it-named.md`** — a skip announcement certifies that the gate *ran*, never that its predicate was *right*.
3. **`.../2026-08-09-my-suites-were-hermetic-so-they-certified-a-gate-reached-through-a-dead-read.md`** — hermetic suites certify logic while the live input is dead. Hence Phase D asserting declared paths resolve in `git ls-files`.
4. **`.../2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md`** — positive-only oracles are true of the correct and the broken implementation alike. **This is what killed the memo:** all seven of its proposed negative controls tested invalidation-on-change; none tested an input the key *omits*, which is exactly where its `_site/` defect lives.
5. **`.../2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md`** — AC verification commands must themselves be falsifiable.
6. **`.../2026-07-06-ac-self-reference-grep-trap-and-verify-config-enabled-state.md`** — an absence-grep false-fails a file that legitimately documents the forbidden token. **This is what killed the AC-determinism linter:** the forbidden phrase necessarily appears inside this plan's own `## Acceptance Criteria`, in the linter's own declared scope.
7. **`.../2026-03-20-bun-fpe-spawn-count-sensitivity.md`** — sequential isolation is defence-in-depth even after the version upgrade. Sequential stays the hard default.
8. **`.../2026-03-05-producer-consumer-merge-for-subagent-limits.md`** and **`.../2026-02-09-parallel-subagent-fan-out-in-work-command.md`** — the lead coordinates; subagents do not run the gate.

### ADR corpus check

- `ADR-133` — the mechanism Phase F re-opens. Decision 3 is the advisory lock. Its Alternatives already REJECTED "make the lock blocking" and "stale-holder detection"; it did **not** consider headroom-based admission control, so that is a genuine gap, not a re-litigation. Its addendum states the governing method: *"Its **method** — probe before committing to a mechanism, and let a measurement rather than an argument settle it — transfers completely. Its **conclusion** is a prior, not evidence."*
- `ADR-151` — the AGENTS index/body split; constrains where the new rule lives.
- No ADR proposes or rejects letting the local gate decline to execute a suite. That is the new decision → **ADR-178** (provisional).

### Skill description budget (Phase 1.8)

No `plugins/soleur/skills/*/SKILL.md` **`description:`** field is edited. Only SKILL.md **bodies**
(`plan-review`, `work`, `review`). Check skipped.

---

## Review Findings Applied

Recorded because each is an instance of the learning this plan cites as binding on itself, and
because the next reader should see what it nearly shipped. All were verified against the tree.

| # | Finding | Resolution |
|---|---|---|
| **P0-1** | The proposed `run_suite --skip-if-not-relevant "<inline paths>" …` call shape opens a **false match** in `lint-orphan-test-suites.sh:57`. Its anchor is satisfied by any `scripts/*.test.sh` appearing after `run_suite `, so a predicate list naming `scripts/check-cloudflare-token-drift.test.sh` would satisfy that suite's own registration check — and deleting its real `run_suite` line at `:401` would leave the linter reporting `orphan test suites: none`. The fix was already written twenty lines down: `:96-100` explains why `REQUIRED_RUNNERS` anchors on the **command**, not the label. | Paths are declared in a **named bash array above** the call; the `run_suite` line carries only the array name. No path literal ever appears on a `run_suite` line, so the anchor cannot false-match. |
| **P0-2** | The CI story contradicted itself and would have **redded main-health-monitor every 6 hours**. The Observability block claimed gates are "bypassed by construction" under `CI` — nothing implemented that. Phase 4.5 then asserted "if `CI` is set and any suite reported a skip, exit non-zero". On `main`, both diff refs resolve but return empty, so both batteries skip and the assertion fires. `_infra_detect_ok` is `1` there (the ref resolves, it just returns nothing), so the fail-SAFE arm does not rescue it. | The predicate **returns true unconditionally when `CI` is set**. A skip in CI becomes *unreachable* rather than *detected*. Strictly stronger, and it deletes the assertion, two ACs and a scenario. |
| **P0-3** | The cf-tunnel predicate table **omitted four workflows the battery actually depends on**. M4 mutates `.github/workflows/git-data-cutover.yml` (`:200-205`), and the oracle it drives pins 5 workflows / 6 call sites (`check-cloudflare-token-drift.test.sh:1791`). A PR removing the bridge `uses:` from `git-data-cutover.yml` would fail W7 *and* crash M4 — while the battery was skipped, reporting green. The plan's own §Risks row-1, landing inside the plan's own table. | All five W7 workflows added to the predicate. `doppler-config-inventory.txt` retained: it is copied at `:65-66` and its absence is a hard abort. |
| **P1-3** | Reusing `_infra_diff_names` does not give the three-source union the plan described: its untracked arm is **path-scoped to `apps/web-platform/infra`** (`:249`), so a brand-new *untracked* mutation target under `scripts/` or `.github/` is invisible and the suite skips. | Rename to `_diff_names` (it was never infra-specific — leaving the name is a trap for the next reader) and widen the untracked arm to the union of declared predicate prefixes. |
| **Simplify ×2** | Both simplification reviewers independently called for deleting the manifest trio, the memo, the AC-determinism linter and the background sampler. Per this skill's rule, both panels firing on one scope means prefer delete. | Manifest trio → inline arrays + ~15 lines folded into `lint-orphan-test-suites.sh`. AC linter → dropped, rule + `plan-review` wiring kept. Sampler → `du -sb` at the existing hook. Memo → deferred (**UC-1**, see `decision-challenges.md`). |
| **Unsatisfiable AC** | The old AC26 asked a *single* sanctioned run to report "before/after wall clock", while Phase 2 spent that run as the baseline. There was no "after". | The one run is taken with `SOLEUR_TEST_FORCE_ALL=1` so every suite executes and it is directly comparable to the prior baseline; the "after" figure is **arithmetic on that same log** (subtract the two gated suites), not a second run. |
| **P2** | Phase 0 named the wrong shard (`test-all.sh:764` is inside `want_scripts` at `:744-768`, not `want_bun`); minor citation drift on the registry battery's line ranges; an undefined `## Cross-cutting` cross-reference; AC10 unrunnable as written. | All corrected. The one-run budget now lives in §Cross-cutting Constraints, which exists. |

---

## Open Code-Review Overlap

**None.** Probed all 64 open `code-review`-labelled issues against every path in Files to Edit/Create
(`gh issue list --label code-review --state open --json number,title,body --limit 200`, then
`jq --arg path … contains($path)`). Zero matches.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a local `288/288 suites passed` line that is not
evidence — the two heaviest batteries (39% of the gate, guarding the registry restore/destroy
authorization path) silently never ran, and the operator ships believing they were covered.

**If this leaks, the user's data is exposed via:** nothing. Local test runner, agent prompt text, one
linter extension. No product runtime surface, no user data, no tenant boundary, no credential, no
network egress.

**Brand-survival threshold:** `aggregate pattern`

**Reasoning:** the failure mode is erosion of trust in the local gate across many sessions, not a
single-user incident. CI remains the merge gate and now runs everything by construction (the
predicate is forced true when `CI` is set), and `main-health-monitor` re-runs the whole un-gated set
every six hours. A local skip cannot, by itself, ship an unreviewed regression. No sensitive path per
preflight Check 6's regex is touched, so no `threshold: none` scope-out bullet is required.

---

## Architecture Decision (ADR/C4)

### ADR

1. **ADR-178 (provisional) — "The local gate may decline to execute a suite, and every decline is a
   counted verdict."** New decision, and it survives the review cuts: the function all 288 suites flow
   through gains a third outcome, and a future engineer reading only the existing ADRs would be
   misled about what `N/N suites passed` means. Records: declines are counted in the denominator and
   named with their re-run command; predicates are declared adjacent to the suite and asserted to
   resolve; and a decline is unreachable under `CI`. Authored via `/soleur:architecture` in Phase C.
   **Ordinal is provisional** — probed across all **62** `origin/*` refs (highest claimed `ADR-177`).
   `/ship`'s collision gate re-derives before merge. On renumber, sweep in the same edit:
   `grep -rn 'ADR-178' knowledge-base/project/{plans,specs}/` — the plan body, `tasks.md`, and AC8
   all name it.
2. **Amendment to ADR-133** (a dated addendum, matching the precedent its own 2026-08-10 addendum
   set). Records the Phase F bytes measurement and states that the lock's mechanism does **not**
   change, with the numbers and the unmet evidence bar, so the next session inherits data rather than
   an argument. ADR-133 stays `status: active`; amended, not superseded.

### C4 views

**No C4 impact.** All three model files read in full, not grepped for the feature's own noun:
`knowledge-base/engineering/architecture/diagrams/{model.c4 (660), views.c4 (70), spec.c4 (54)}`.

- **External human actors** — `founder`, `betaContact` (`model.c4:22`), `contributor` (`:37`),
  `emailSender`. No new human actor; the only human here is the operator, already modelled as
  `founder`. **Adjacency checked:** `contributor`'s description (`:37`) discusses operator-side
  execution of a checked-out PR head — "running its tests, its scripts, its hooks" — and states that
  surface is covered by neither the CI nor the preflight-sandbox boundary. This plan changes *which*
  suites execute there and *how verdicts are reported*; it adds no execution surface and moves nothing
  across a boundary, so that description remains true unedited.
- **External systems / vendors** — `anthropic`, `github`, `cloudflare`, `doppler`, `discord`,
  `stripe`, `plausible`, `resend`, `pushService`, `ghcr`, `projectZot`, `zotRegistry`, `betterstack`,
  `sentry`, `sigstore`, `letsencrypt`, `publicResolvers`, `systemdUser`. No new vendor, webhook, or
  outbound call; nothing egresses.
- **Containers / data stores** — the local test runner is **not modelled as a container**: scanning
  `model.c4` for `ci|test|runner|github.?action|workflow` returns only prose inside other elements'
  `description` strings (`:28-37`, `:62-120`), never an element declaration.
- **Actor↔surface access relationships** — unchanged; no ownership, tenancy, or sharing relationship
  is created or widened.
- **Views** — `views.c4` declares exactly three (`context`, `containers of platform`,
  `components of platform.plugin`); none includes a test-runner element, so no `include` line changes
  and no edge is orphaned.

### Sequencing

ADR-178 is authored in Phase C, once the contract is real rather than proposed. The ADR-133 amendment
is authored in Phase F, once the measurement exists. Neither is deferred to a follow-up issue.

---

## Observability

```yaml
liveness_signal:
  what: >
    `main-health-monitor` runs the FULL gate (`bash scripts/test-all.sh`, TEST_GROUP=all) with `CI`
    set, and the relevance predicate returns true unconditionally under `CI`, so a decline is
    unreachable there. A gated suite that has rotted — predicate no longer matching, or the suite
    itself broken — reds that run and files/updates its tracker. This is the anti-rot signal, and it
    already exists at 4x the briefed cadence.
  cadence: every 6 hours (Inngest cron `cron-main-health-monitor`, `{ cron: "0 */6 * * *" }`)
  alert_target: the workflow's existing tracker-file/close path plus its heartbeat
  configured_in: >
    .github/workflows/main-health-monitor.yml:309 (all) and :328 (infra);
    apps/web-platform/server/inngest/functions/cron-main-health-monitor.ts:118

error_reporting:
  destination: >
    stdout/stderr of the local runner (operator-facing local developer tooling — observability layer
    7, the self-hosted CLI surface), plus the main-health-monitor tracker for the CI-side backstop.
  fail_loud: >
    yes, and fail-SAFE rather than fail-quiet. An undeterminable diff RUNS the suite (the existing
    `_infra_detect_ok == 0` arm at test-all.sh:256-259). A declared predicate path that does not
    resolve is a hard lint failure, not a warning.

failure_modes:
  - mode: >
      A predicate goes stale (a declared path renamed or moved) so the suite is skipped locally
      forever, and no later edit re-arms it because the edit is what broke it.
    detection: >
      `scripts/lint-orphan-test-suites.sh` extension — every element of each declared predicate array
      must resolve in `git ls-files`, and each array must contain its own battery path. Runs in the
      already-registered `scripts/lint-orphan-test-suites` suite.
    alert_route: >
      red `test` required check (the `test-scripts` shard feeds the aggregate `test` context, which is
      in the CI Required ruleset)
  - mode: >
      A battery gains a new mutation target that nobody adds to the predicate.
    detection: >
      Three layers, none of them new code. (1) Each predicate array contains its **own battery file**,
      so the commit that adds a target necessarily matches the predicate and runs the suite. (2) Both
      batteries hard-abort on a missing declared path today — `harness_die "required file is
      unreadable"` and `FATAL: suite missing from sandbox`. (3) CI runs them unconditionally and
      main-health-monitor every 6h.
    alert_route: red suite in CI within one PR, or within 6h from the monitor
  - mode: >
      A suite is skipped locally while the summary still reads N/N, so "local green" quietly stops
      meaning "CI green" for the two most expensive suites.
    detection: >
      `skip_suite` increments the denominator and prints `[skip] <label> (<reason>)` with the exact
      re-run command; the epilogue prints a consolidated roster; `TEST_TIMING_LOG` records
      `skip=relevance` as a labelled trailing field.
    alert_route: operator terminal + TEST_TIMING_LOG
  - mode: >
      A spawned subagent runs the full gate anyway, inflating timings 1.9x and corrupting measurement.
    detection: >
      mechanical, not prose — the lead exports `SOLEUR_SUBAGENT=1` and `test-all.sh` refuses the full
      gate when it is set, naming the targeted-suite alternative and the escape hatch.
    alert_route: non-zero exit in the subagent, with the reason named
  - mode: >
      The bytes probe reads near-zero on /tmp and is misread as "no pressure, drop the lock", when
      what it measured is that the existing `TMPDIR=/var/tmp` mitigation works.
    detection: >
      the probe attributes per-directory (`/tmp` and `$TMPDIR` separately, never summed); the ADR-133
      amendment is required to quote both numbers.
    alert_route: the amendment's own reject condition — one quoting a single directory is incomplete

logs:
  where: >
    operator terminal; `TEST_TIMING_LOG` when set (`skip=<reason>`, `bytes_tmp=`, `bytes_tmpdir=` as
    labelled trailing fields).
  retention: >
    TEST_TIMING_LOG is operator-provided and operator-owned. This plan creates no new persistent
    artifact — the memo that would have is deferred (UC-1).

discoverability_test:
  command: bash scripts/lint-orphan-test-suites.sh
  expected_output: >
    `orphan test suites: none` on stdout, exit 0 — now also covering that every declared relevance
    predicate path resolves and each array contains its own battery. Local, offline, no credential,
    no network, no remote shell.
```

`credentials_required` is deliberately absent: the probe reads only tracked files. First token `bash`
is on preflight Check 10's `PROBE_VERB_ALLOWLIST`.

---

## Cross-cutting Constraints

- **One full-gate run, and one only.** The changes touch `run_suite`, the function every suite flows
  through, so a full gate run is justified once. It is taken in Phase E with
  `SOLEUR_TEST_FORCE_ALL=1`, so every suite including both gated batteries executes and the log is
  directly comparable to the prior session's baseline. **The "after" figure is arithmetic on that same
  log** — subtract the two gated suites — not a second run. Do not re-run the gate to satisfy an
  environmental condition; that is the waste the new AGENTS rule exists to prevent.
- **Test-first.** Each behavioural change gets a failing test before the fix
  (`cq-write-failing-tests-before`).
- **Suite budgets** come from that run's `TEST_TIMING_LOG`, never from standalone re-runs.
- **Every scope reduction and deferral is stated in the PR body** with its reason, and every deferral
  has a tracked issue.

---

## Implementation Phases

Ordering rule: no phase introduces a skip path before skip *reporting* exists, and no phase makes a
decision before its instrument exists.

### Phase A — Item 6: keep heavy suites out of subagent fan-out

First, because until it lands, concurrent agents inflate every measurement taken afterwards (measured
1.9x: 860 s → 1675 s). Fixing the measurement apparatus precedes measuring.

1. **RED.** `plugins/soleur/test/fanout-suite-scope.test.sh` — the one new file. Two arms: the
   mechanical refusal works (with `SOLEUR_SUBAGENT=1`, a full-gate invocation exits non-zero and names
   the alternative), and both SKILL.md files carry the scope clause, asserted on a distinctive content
   anchor that spans no punctuation boundary in the source.
2. **GREEN — the mechanical half.** `test-all.sh` refuses a full-gate run when `SOLEUR_SUBAGENT=1`,
   printing the targeted-suite alternative and the escape hatch. This is the part review insisted on:
   a grep asserting a paragraph exists certifies the instruction was *written*, not that agents obey
   it. The clause is prose in a prompt, which *is* agent discretion; the env-var refusal is not.
3. **GREEN — the prose half.** Add to the fan-out/spawn instructions in
   `plugins/soleur/skills/work/SKILL.md` and `plugins/soleur/skills/review/SKILL.md`:
   > Spawned agents run only the suites targeting the files they were given, and are spawned with
   > `SOLEUR_SUBAGENT=1`. They must not run `scripts/test-all.sh`,
   > `apps/web-platform/infra/run-registered-suites.sh`, or any full-gate runner — concurrent
   > full-gate runs inflate each other's timings and corrupt the measurement. The lead runs the gate
   > once, after collecting fan-out work.
4. Registration: the new suite matches the `plugins/soleur/test/*.test.sh` glob at `test-all.sh:764`,
   which sits inside **`want_scripts`** (`:744-768`), not `want_bun`. Confirm the glob matches rather
   than assuming; `:745-751` explains at length why the shard matters.

### Phase B — skip reporting (the enabler, ~15 lines)

Not one of the six items, and deliberately small. It retires a defect that already exists.

**The defect.** `run_suite` increments `suites` on entry (`:143-144`), so the existing infra gate's
`if`-wrapper (`:781-814`) loses gated suites from the denominator: `N/N suites passed` cannot
distinguish "286/286 because two were gated" from "286/286 because two were de-registered".

1. **RED.** Extend `scripts/test-all-infra-coverage-notice.test.sh` (already registered at `:763`):
   a skipped suite is counted; the summary distinguishes passed/failed/skipped; the skip line names
   suite, reason and re-run command; `TEST_TIMING_LOG` gets `skip=<reason>` as a **labelled** trailing
   field (field 3 already carries `FAIL`, so an unlabelled append is positionally ambiguous — the same
   reasoning `:174-177` already applies to `tmp_delta=`).
2. **GREEN.** Add `skipped=0` and a `skip_suite <label> <reason> <rerun-cmd>` helper that increments
   both counters and prints in the shape `:806-812` already uses. Summary becomes
   `=== P passed, F failed, S skipped, N total ===` with `N = P + F + S`.
   **A sibling helper, not an option on `run_suite`.** `skip_suite` cannot false-match
   `^[[:space:]]*run_suite ` (no trailing space after the token), so it is invisible to the linter
   anchors — unlike the rejected `run_suite --skip-if-not-relevant` shape, which opened P0-1.
3. **Migrate the existing infra gate's `else` branch (`:806-812`) onto it** in the same edit. This
   proves the helper against an already-covered consumer and retires the drift. Net lines removed.

### Phase C — Item 1: the relevance gate (~25 lines)

1. **RED.** In the coverage-notice suite: a **negative-control pair** (a docs-only fixture diff skips
   the registry battery; a fixture diff touching `scripts/registry-pull-path-health.sh` runs it), the
   fail-SAFE arm, the force-all arm, and the CI arm.
2. **GREEN — the derivation.** Rename `_infra_diff_names` → `_diff_names` (it was never
   infra-specific; leaving the name invites a later reader to add an infra filter and silently disarm
   both gates) and add `_diff_touches <path…>`. Reuse the existing three-source union and fail-SAFE
   arm at `:237-259`, **widening the untracked arm** from `-- apps/web-platform/infra` to the union of
   declared predicate prefixes (P1-3).
3. **GREEN — the bypasses.** `_diff_touches` returns true unconditionally when
   `SOLEUR_TEST_FORCE_ALL=1` **or `CI` is set** (same `[[ -n "${CI:-}" ]]` predicate as
   `test-contention.sh:322`). Under CI a decline is *unreachable*, not merely detected — which is why
   no CI assertion is needed and why main-health-monitor cannot red on this (P0-2).
4. **GREEN — the predicates.** A named bash array above each of the two call sites (`:614`, `:760`),
   referenced by name on the guarded branch so **no path literal ever appears on a `run_suite` line**
   (P0-1). Verified against the batteries' own declarations, not invented:

   | Gated suite | Declared predicate paths | Source of truth |
   |---|---|---|
   | `tests/scripts/registry-gate-mutation-battery` (`:614`) | `scripts/registry-pull-path-health.sh`, `scripts/registry-restore-from-ghcr.sh`, `tests/scripts/test-registry-pull-path-health.sh`, `tests/scripts/test-registry-restore-from-ghcr.sh`, `scripts/zot-mirror-diagnosis.sh`, `scripts/check-cloudflare-token-drift.sh`, `apps/web-platform/infra/cloud-init.yml`, **and the battery file itself** | battery `:58-59` (SUTs), `:60-61` (suites), `:70-72` (companions), `:73-76` (cloud-init) |
   | `scripts/cf-tunnel-liveness-gate-mutations` (`:760`) | `scripts/check-cloudflare-token-drift.test.sh`, `.github/actions/cf-tunnel-ssh-bridge/action.yml`, `apps/web-platform/infra/doppler-config-inventory.txt`, `.github/workflows/scheduled-terraform-drift.yml`, **plus all five W7 workflows** — `apply-deploy-pipeline-fix.yml`, `apply-web-platform-infra.yml`, `git-data-cutover.yml`, `workspaces-luks-cutover.yml`, `workspaces-luks-verify.yml` — **and the battery file itself** | battery `:37-39`, `:64`, `:200-205` (M4 mutates `git-data-cutover.yml`), `:227`/`:260`; oracle `check-cloudflare-token-drift.test.sh:1791` (`W7_EXPECTED`, 5 workflows / 6 call sites) |

   The cf-tunnel battery *copies* all of `scripts/` and `.github/` (`:53-54`) but only *depends on*
   the paths above; gating on the copy set would never skip. **Each array contains its own battery
   file** — that single element makes new-target drift self-correcting, because the commit adding a
   target necessarily edits the battery, necessarily matches the predicate, and necessarily runs the
   suite.
5. **Author ADR-178.**

### Phase D — anti-rot (~15 lines in an existing linter)

Fold into `scripts/lint-orphan-test-suites.sh`, which already reads `test-all.sh`, already has a
`fails` counter, and already uses the anchor-grep idiom (`:57`, `:101`). No new linter, no manifest
file, no `--explain` mode.

1. **RED.** Arms in the existing suite: a declared path renamed out of the tree FAILs; an array
   missing its own battery path FAILs; the shipped tree PASSes.
2. **GREEN.** Extract the two predicate arrays from `test-all.sh`, assert every element resolves in
   `git ls-files`, and assert each array contains its own battery path.

**Scope note:** `lint-orphan-test-suites.sh:33` iterates `scripts/*.test.sh` only, so its pre-existing
loop covers `scripts/cf-tunnel-liveness-gate-mutations.test.sh` but not
`tests/scripts/test-registry-gate-mutation-battery.sh` (different directory *and* a `test-` prefix
rather than a `.test.sh` suffix — `test-all.sh:609-613` says so explicitly). The array check added
here is what covers the second one, and it is array-driven rather than glob-driven for exactly that
reason.

**Deliberately NOT built:** a set-equality check between the arrays and the batteries' own
declarations. The batteries declare in four incompatible shapes — shell vars, a bare inline literal,
an unquoted `for` list, and a *transitive* dependency living in a sibling suite's `W7_EXPECTED` — so
the checker would be a second implementation of the batteries' semantics, written by the same author
in the same session. That is the exact learning this plan cites as binding on it. Battery
self-inclusion plus the batteries' own hard-aborts plus unconditional CI cover the window instead.

### Phase E — the sanctioned full-gate run

Run once with `SOLEUR_TEST_FORCE_ALL=1` and `TEST_TIMING_LOG` set. Every suite executes, so the run is
both the green gate and the comparable measurement. Derive the "after" figure arithmetically from the
same log.

### Phase F — Item 2: measure the bytes, amend ADR-133 (~4 lines + a doc)

1. **RED.** Arms in `scripts/test-contention.test.sh` via the existing `TC_DF_CMD` seam (`:58`),
   asserting **per-directory** attribution: a fixture with pressure on `/tmp` and none on `$TMPDIR`
   reports two distinct numbers and never their sum.
2. **GREEN.** At the existing `TEST_TIMING_LOG`-gated probe hook (`test-all.sh:148-152`, `:177-181`),
   record a per-directory `du -sb` alongside the entry count, emitting `bytes_tmp=` / `bytes_tmpdir=`
   as labelled trailing fields. Boundary-sampled at the same two edges the current probe already uses
   — **no background sampler**. This answers the real objection (bytes vs entries) with no
   observer-effect confound to document, and it costs nothing on a default local run because the hook
   is already `TEST_TIMING_LOG`-gated. The in-suite peak matters only for the coincident-peak
   question, which the deferred multi-run experiment owns.
3. **State ADR-133's justification, from the current on-disk file:** parallel worktrees are the
   documented workflow; two concurrent runs produced failures that read as real regressions (#6789,
   #6726, #4096, #3817/#4128); the contended resource was found to be **capacity, not a colliding
   path** — a machine-global RAM-backed 4 GiB `/tmp` at 86% full with swap exhausted; the only prior
   mitigation was prose telling the agent to `ps -ef | grep test-all` and wait. The lock is advisory:
   on timeout it proceeds with `LOCK_CONTENDED_PROCEEDING` and never aborts, CI is exempt, and the
   kill switch is inherited (`test-contention.sh:309-347`).
4. **Verdict: keep the lock, record the numbers.** The decision rule is fixed here, before the data
   arrives, so the data decides rather than the author. One run measures the *uncontended* case while
   the lock protects the *contended* one, so no honest bar for replacing a mutex is met. Two
   mechanism-level objections no measurement removes: **TOCTOU** (admission control is a point-in-time
   prediction about a 15-minute future — two runners both sample abundant headroom, both admit, both
   allocate; fixing that needs a reservation, i.e. the mutex again), and **non-monotonic degradation**
   (the mutex degrades to *slow*; admission control degrades to ENOSPC mid-suite, a RED that reads as
   a code regression — the same "signal that is not evidence" harm #6789 exists to prevent, inverted).
   The follow-up candidate is a headroom **bypass** on top of the mutex, not a replacement.
5. **Write the ADR-133 amendment.** It must quote **both** directory figures; one quoting a single
   directory is incomplete by its own reject condition.

### Phase G — Item 3: the rule against session-dependent acceptance criteria

1. **Measure the budget first.** `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`.
   If headroom has fallen below ~700 bytes since the 44,478 measured here, trim sibling prose in the
   same commit rather than deferring the trim.
2. **The rule.** New id `cq-ac-must-not-depend-on-concurrent-sessions`, body in `AGENTS.rules.md`
   under `## Code Quality`, pointer-only in `AGENTS.md` (ADR-151 — do not merge the body into the
   index). Immutable from the moment it lands (`cq-rule-ids-are-immutable`). Substance: an acceptance
   criterion whose truth depends on unrelated concurrent processes — a sibling worktree, another
   session, ambient machine state — is not a property of the code and must be re-expressed as a
   deterministic test. Carries a `[skill-enforced: …]` tag naming the wiring below so
   `lint-agents-enforcement-tags.py` (registered at `test-all.sh:343`) resolves it.
3. **The wiring.** Add the check to `plugins/soleur/skills/plan-review/SKILL.md`'s standing panel
   instructions, classified **Mechanical** (a yes/no property of the AC text, not taste), so it
   auto-applies. This is what the brief asked for — "wire it into the plan-review skill/agents so it
   actually fires" — and the panel is where the judgment belongs.

**Deliberately NOT built: a `lint-plan-ac-determinism.py`.** It would hunt a *semantic* property in
English prose via regex calibrated on a single sentence that already happened; it would need a
committed baseline to be green against its own corpus, a self-reference carve-out to avoid firing on
the rule that documents the prohibition, and a meta-test to prove it was not vacuous. Decisively, the
forbidden phrase necessarily appears inside *this plan's own* `## Acceptance Criteria` — inside the
linter's declared scope — so its "must not false-fire" and "must exit 0 on the live corpus" criteria
could not both hold. When a check needs a baseline, a carve-out and a meta-test, the check is the
problem.

---

## Files to Edit

- `scripts/test-all.sh` — `SOLEUR_SUBAGENT` refusal; `skipped` counter + `skip_suite` helper; summary
  line; migrate the infra gate's `else` branch; `_infra_diff_names` → `_diff_names` + `_diff_touches`
  with the widened untracked arm and the CI/force bypasses; the two predicate arrays; `du -sb` at the
  existing probe hook; register nothing new beyond what the existing glob already catches.
- `scripts/lib/test-contention.sh` — per-directory bytes helper behind the `TC_DF_CMD` seam.
- `scripts/test-contention.test.sh` — per-directory attribution arms.
- `scripts/test-all-infra-coverage-notice.test.sh` — denominator, skip-line shape, negative-control
  pair, fail-safe, force-all, CI arms.
- `scripts/lint-orphan-test-suites.sh` — predicate-array path resolution + self-inclusion checks.
- `plugins/soleur/skills/work/SKILL.md` — fan-out scope clause.
- `plugins/soleur/skills/review/SKILL.md` — fan-out scope clause.
- `plugins/soleur/skills/plan-review/SKILL.md` — AC-determinism check in the panel instructions.
- `AGENTS.md` — one index pointer under `## Code Quality`.
- `AGENTS.rules.md` — the `cq-ac-must-not-depend-on-concurrent-sessions` body; sibling trim if needed.
- `knowledge-base/engineering/architecture/decisions/ADR-133-test-all-tmpfs-contention-managed-resource-and-advisory-lock.md`
  — dated amendment.

## Files to Create

- `plugins/soleur/test/fanout-suite-scope.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-178-local-gate-declines-are-counted-verdicts.md`
  (provisional ordinal)

**One new test file and one ADR, down from nine new files.** Every path claimed to exist was resolved
with `git ls-files` or a direct `Read`; every path claimed to be new returned no match.

---

## Acceptance Criteria

### Pre-merge (PR)

Written to satisfy the rule this plan adds: **no criterion depends on the presence or absence of an
unrelated concurrent session.** Where a property concerns sibling processes it is asserted through a
synthetic fixture, never ambient machine state. Consolidated from 28 to 10 after review found 11
subsumed by the full-gate run and six explicit duplicate pairs.

**AC1** — Denominator and reporting: `bash scripts/test-all-infra-coverage-notice.test.sh` passes,
including arms asserting that on a fixture where one suite is gated out the summary reports
`P + F + S == N` with `S == 1` and `N` unchanged from the pre-change total; that the skip line names
the suite, the reason and the re-run command (asserted on the exact emitted string); and that
`TEST_TIMING_LOG` carries `skip=relevance` as a labelled field that leaves field 3 unambiguous against
both the `ok` and `FAIL` shapes.

**AC2** — Negative-control pair: on a synthetic docs-only diff the registry battery is skipped; on a
synthetic diff touching `scripts/registry-pull-path-health.sh` it runs. Both driven by fixture diffs,
never the branch's real diff.

**AC3** — Fail-safe: with the diff undeterminable (fixture forcing `_infra_detect_ok == 0`), every
gated suite RUNS. Skipping on an undeterminable diff is a hard failure of this AC.

**AC4** — Bypasses: `SOLEUR_TEST_FORCE_ALL=1` runs both gated suites on a docs-only fixture diff, and
`CI=1` does the same. The CI arm asserts the decline is *unreachable* — the suite executes — not that
an assertion fired.

**AC5** — Anti-rot, both directions: `bash scripts/lint-orphan-test-suites.sh` exits 0 on the shipped
tree with `orphan test suites: none`, and its new arms FAIL when (a) a declared predicate path is
renamed out of the tree, and (b) a predicate array does not contain its own battery path.

**AC6** — Predicate completeness against the source of truth: the cf-tunnel array contains all five
workflows in `W7_EXPECTED` at `scripts/check-cloudflare-token-drift.test.sh:1791` plus
`git-data-cutover.yml` (which M4 mutates at `scripts/cf-tunnel-liveness-gate-mutations.test.sh:200-205`).
Asserted by comparing the array against the parsed `W7_EXPECTED` literal, so the AC reads the same
source the battery does.

**AC7** — Fan-out isolation is mechanical: `bash plugins/soleur/test/fanout-suite-scope.test.sh`
passes, including the behavioural arm (a full-gate invocation with `SOLEUR_SUBAGENT=1` exits non-zero
and names the alternative) and the text arm (both SKILL.md files carry the clause, asserted on a
content anchor).

**AC8** — Architecture records exist: `ADR-178-*.md` is present (or the ordinal actually claimed at
merge time, swept across the plan body, `tasks.md` and this AC in the same edit), and the ADR-133
amendment is dated, quotes **both** the `/tmp` and `$TMPDIR` bytes figures from the sanctioned run's
`TEST_TIMING_LOG`, states the keep-the-lock verdict, and states the evidence bar that was not met.
ADR-133's `status:` is unchanged.

**AC9** — Rule mechanics: `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`
exits 0 (WARN acceptable, REJECT not), and both `scripts/lint-rule-ids.py` and
`scripts/lint-agents-enforcement-tags.py` exit 0 over the new pointer/body pair and its
`[skill-enforced: …]` tag. The measured `B_ALWAYS` is recorded in the PR body against the 44,478
baseline.

**AC10** — The win, measured: the single sanctioned `SOLEUR_TEST_FORCE_ALL=1` full-gate run is green,
and the PR body reports the total wall clock from its `TEST_TIMING_LOG` plus the projected typical-run
figure derived by subtracting the two gated suites' measured times **from that same log**. No second
full-gate run is taken.

### Post-merge (operator)

None. Every step is automatable and runs in-session or in CI. The deferral issues are filed with
`gh issue create`; the #7376 note is posted with `gh issue comment`. No remote shell, no vendor
console, no credential provisioning anywhere in this plan.

---

## Expected Impact

Arithmetic shown so the aggregate is not asserted independently of its parts. Inputs are the prior
session's measured `TEST_TIMING_LOG` figures.

| Suite | Measured ms | Share | Gated? |
|---|---:|---:|---|
| `tests/scripts/registry-gate-mutation-battery` | 860,692 | 31.6% | **Yes** |
| `scripts/cf-tunnel-liveness-gate-mutations` | 189,289 | 7.0% | **Yes** |
| `apps/web-platform` (vitest) | 170,937 | 6.3% | No — touched by most PRs |
| `.github/scripts/test/run-all.sh` | 139,673 | 5.1% | No — a `REQUIRED_RUNNERS` entry |
| **Top-four subtotal** | **1,360,591** | **50.0%** | |

Gated pair: 860,692 + 189,289 = **1,049,981 ms ≈ 17.5 min**.

The full-run total is **derived** from the brief's "these four are ~50%", giving ≈2,721,182 ms
(≈45.4 min) and a gated share of **38.6%** — projecting a typical local run of ≈1,671,201 ms
(≈27.9 min). The derivation cross-checks to within 0.09% against the registry battery's independent
31.6% share, so the true total exists in the source log; **AC10 quotes it directly from the sanctioned
run rather than carrying this back-derivation forward.**

**Coverage loss on a PR touching neither target: zero.** Those suites guard paths the PR does not
touch, CI runs them by construction, and main-health-monitor runs them every six hours regardless.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The biggest way this ships a green that is not evidence:** a predicate goes stale (a declared path renamed) and the suite is skipped locally forever — no later edit re-arms it, because the edit is what broke it. | Four layers, none re-running the predicate's own logic: array-element resolution against `git ls-files`; each array containing its own battery file (so a new-target commit necessarily runs the suite); the batteries' own hard-aborts on a missing declared path; and CI + the 6-hourly monitor, where a decline is unreachable. |
| "Local green → CI green" quietly stops holding for the two most expensive suites. | The skip is loud, counted in the denominator, carries its re-run command, and appears in the epilogue roster. A printed verdict, not a comment. |
| A path list on a `run_suite` line false-matches the orphan linter's per-suite anchor (P0-1). | Arrays are declared above the call and referenced by name; no path literal appears on a `run_suite` line. `skip_suite` cannot match `^[[:space:]]*run_suite ` either. |
| A CI assertion reds main-health-monitor every six hours (P0-2). | No assertion. The predicate returns true under `CI`, making a decline unreachable rather than detected. |
| An untracked new mutation target is invisible to the predicate (P1-3). | The untracked arm is widened from the infra directory to the union of declared predicate prefixes, and `_infra_diff_names` is renamed so the next reader does not re-narrow it. |
| **The Phase F measurement is under-powered and gets over-read.** n=1 measures the uncontended case; a `/tmp`-only reading near zero measures that `TMPDIR=/var/tmp` works, not that the hazard is gone. | The verdict is fixed before the data arrives (keep the lock), per-directory attribution is mandatory, and the amendment records the unmet bar. |
| **Evidence bar for replacing the mutex** (recorded, not met here): an in-suite sampler at ≤2 s; ≥3 single-runner runs for variance; ≥2 at N=2 and ≥1 at N=3 with the lock disabled via `SOLEUR_DISABLE_SESSION_STATE=1`; a re-verified filesystem premise (ADR-133's "4 GiB @ 86%" is a premise to re-measure, not inherit); and one adversarial run starting the top-3 consumers simultaneously. | Deferred to a tracked issue; the one-run budget cannot meet it. |
| **AGENTS budget** at 44,478/46,000, already WARN. | Only one rule is filed and no manifest convention exists to fold in. Phase G re-measures and trims in the same commit if needed. |
| Six items all touch `run_suite`. | Phase B lands the ~15-line reporting change alone and migrates the existing consumer onto it before any new one. |
| **Every guard here was written against the mental model that produced the six items.** Review proved this empirically — three P0s, all of that shape. | The review spawn prompt must instruct reviewers to *name an implementation that satisfies each assertion while violating the property it is named for*, not to re-run the gate's logic. |

---

## Alternative Approaches Considered

| Alternative | Verdict |
|---|---|
| `TEST_GROUP=heavy` as the escape hatch | **Rejected.** Partition selector with a fail-closed `case`; a value meaning "all, plus force" breaks the `want_*` invariant. `SOLEUR_TEST_FORCE_ALL=1` is orthogonal. |
| A new nightly workflow for the gated set | **Rejected — already exists.** `main-health-monitor.yml:309` runs the full gate every 6h; a second forks the pin-set #7307 built. |
| `run_suite --skip-if-not-relevant "<inline paths>"` | **Rejected (P0-1).** Inline paths on a `run_suite` line false-match the orphan linter's per-suite anchor. Arrays by name + a `skip_suite` sibling instead. |
| `run_suite_if_relevant` wrapper | **Rejected.** Breaks the literal `run_suite ` token the linter anchors on. |
| Keeping the `if`-around-`run_suite` shape | **Rejected.** It is the denominator drift; Phase B migrates it. |
| A CI assertion that skips did not occur | **Rejected (P0-2).** Would red main-health-monitor every 6h. Forcing the predicate true under `CI` makes the skip unreachable — strictly stronger and smaller. |
| A relevance manifest file + dedicated linter + `--explain` | **Rejected.** Three artifacts duplicating data the batteries already declare, plus a drift-detector for the duplication it created. Inline arrays + ~15 lines in the existing linter. |
| Set-equality between arrays and the batteries' own declarations | **Rejected.** The batteries declare in four incompatible shapes including a transitive `W7_EXPECTED` in a sibling suite; the checker would re-implement their semantics from the same blind spot. Battery self-inclusion covers the window. |
| `lint-plan-ac-determinism.py` + baseline + carve-out | **Rejected.** Regex for a semantic property, calibrated on n=1, that necessarily fires on this plan's own ACs. Rule + `plan-review` wiring carry the value. |
| A ≤2 s background `du` sampler | **Rejected.** ~1,350 recursive walks over multi-GiB trees, an observer-effect confound the plan would then have to excuse, feeding a pre-announced verdict. `du -sb` at the existing hook answers the bytes-vs-entries objection in ~4 lines. |
| Ship the session memo (Item 5) | **Deferred — UC-1.** `_site/` is untracked and forms a documented producer/consumer pair between two suites, so a tracked-tree key serves a stale green and an untracked-inclusive key never fires. See `decision-challenges.md`. |
| Land Item 4's parallelism opt-in-OFF | **Deferred.** #7376 is the measured result of this exact mechanism on this hardware; a flag nobody can responsibly enable is dead code, and Phase F's probe may diagnose it. |
| Delete the advisory lock outright | **Rejected.** ADR-133 documents its justification; both the brief and the ADR require measurement before a mechanism change. |

---

## Deferrals (tracking issues to file during /work)

Each needs an issue stating what was deferred, why, re-evaluation criteria, and a milestone from
`knowledge-base/product/roadmap.md`.

1. **Bounded parallelism for the top-level bash suites (Item 4).** Blocked on #7376 — the measured
   result of running `xargs -P min(nproc,6)` on this hardware: three *different* suites failing across
   two of six executions, which is an interference signature rather than three fixable suite bugs.
   Re-evaluate when #7376 closes, or when Phase F's per-directory bytes data identifies its mechanism.
   Note the same collision class the ADR-133 addendum recorded for #7376 exists at the top level:
   `cf-tunnel-liveness-gate-mutations.test.sh:53-54` copies the whole `scripts/` and `.github/` trees
   while other suites write into the same worktree. **Comment on #7376** linking this issue and the
   Phase F probe; do not close or re-scope it.
2. **The session "already green" memo (Item 5).** Deferred on the verified `_site/` defect — see UC-1
   in `knowledge-base/project/specs/feat-one-shot-test-pipeline-efficiency/decision-challenges.md`.
   Re-evaluate with an input model that can see untracked producer/consumer pairs.
3. **Multi-run experiment to settle the advisory-lock mechanism (Item 2).** Carries the evidence bar
   from §Risks verbatim. Re-evaluate when it can run without a one-full-gate budget cap.

---

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment:** Materially reshaped the plan rather than ratifying it. Corrected the load-bearing
false premise that no nightly full-gate workflow exists (`main-health-monitor.yml:309`, Inngest-cron
dispatched every 6h, invisible to a `schedule:` grep), deleting a workflow from scope. Identified the
denominator drift in the existing `if`-wrapper shape. Judged the one-run bytes measurement
under-powered for a mechanism change and supplied the evidence bar now in §Risks, naming TOCTOU and
ENOSPC-mid-suite as admission control's mutex-free failure modes. Picked *defer* for Item 4 over
landing opt-in-OFF. Found the toolchain-environment hole in the memo's whole-tree key — later
sharpened by the eng panel into the decisive `_site/` finding. Supplied the phase order. Named the
single biggest green-that-is-not-evidence risk: a silently stale predicate.

### Engineering panel (plan-review)

**Status:** reviewed — three P0s and a large simplification, all applied. See "Review Findings
Applied". Both the simplification panel and the correctness lens fired on the same four scopes
(memo, manifest trio, AC linter, background sampler), which this skill's consolidation rule treats as
a signal to delete rather than fix. Net effect: 9 new files → 2, 11 edited → 11, 28 ACs → 10,
18 scenarios → 8, while keeping 100% of the measured 38.6% win.

**Decision classes:** all correctness and simplification findings were **Mechanical** and
auto-applied. Dropping Item 5 is **never-Mechanical** (operator-requested scope) and was persisted as
**UC-1** rather than silently applied; Item 2 landing as a measurement rather than a mechanism change
was persisted as **UC-2**.

**Named panel:** not activated. The mechanical UI-surface scan over Files to Edit/Create matches no
`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or shared UI term, and an independent
read of the plan body finds no product/market/brand/user-copy content — this is local developer
tooling, agent prompt text and a linter extension. `cto` already ran with a devex lens at Phase 2.5.

### Product/UX Gate

Not applicable. Product sweep returns **NONE**; no user-facing surface, so no `.pen` wireframe is
required (`wg-ui-feature-requires-pen-wireframe` does not fire).

### Gates evaluated and skipped, with reasons

- **GDPR / compliance (2.7):** skipped. No schema, migration, auth flow, API route, or `.sql` file; no
  new external-API processing of operator data; no new cron reading `learnings/` or `specs/`; no new
  distribution surface. None of the (a)-(d) expansion triggers fire.
- **IaC routing (2.8):** skipped. No server, systemd unit, DNS record, TLS cert, secret, firewall rule,
  vendor account, or new cron — the 6-hourly workflow already exists and is not modified. No
  remote-shell step, no secret-store write, and no vendor console step appears anywhere in this plan.
- **Encryption posture (2.11):** skipped. No persistent store and no new cross-component connection;
  no path matches `\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, or
  `docker-compose.*\.ya?ml$`.
- **Soak follow-through enrollment (2.9.1):** skipped. No time-gated close criterion; nothing deploys.
- **Network-outage checklist (1.4):** skipped. No trigger keyword matches; no resource with a
  `provisioner`/`connection` block is touched.
- **Scoped advisor consult (4.5):** served by the CTO consult above, which materially changed the
  plan's shape. A second consult on the same payload was judged redundant; the 3-agent panel then
  reshaped it again.

---

## Test Scenarios

All deterministic and fixture-driven. **None depends on what another session on this machine happens
to be doing** — the rule this plan adds, applied to itself.

1. **Docs-only diff.** Both batteries skipped, loudly, with re-run commands; denominator intact;
   `skip=relevance` in `TEST_TIMING_LOG`.
2. **Diff touching `scripts/registry-pull-path-health.sh`.** Registry battery runs; cf-tunnel skipped.
3. **Diff touching `.github/workflows/git-data-cutover.yml`.** cf-tunnel battery runs — the P0-3
   regression test; registry battery skipped.
4. **`SOLEUR_TEST_FORCE_ALL=1` on a docs-only diff.** Both run.
5. **`CI=1` on a docs-only diff.** Both run, no assertion fires, exit 0 — the P0-2 regression test.
6. **Undeterminable diff** (fixture forcing `_infra_detect_ok == 0`). Everything runs.
7. **Predicate rot.** A declared path renamed out of the tree → `lint-orphan-test-suites.sh` FAILs. An
   array missing its own battery path → FAILs.
8. **Subagent refusal.** `SOLEUR_SUBAGENT=1` + a full-gate invocation → non-zero exit naming the
   alternative; without it → normal run.
9. **Bytes attribution.** Fixture pressure on `/tmp` only → two distinct numbers, never summed.

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`
  Phase 4.6.** This plan's is filled with a concrete artifact, a concrete (null) exposure vector, and
  the `aggregate pattern` threshold.
- **The ADR-178 ordinal is provisional.** Free across all 62 `origin/*` refs at plan time (highest
  claimed: ADR-177), but a sibling can claim it mid-pipeline — this repo has seen an ordinal move
  twice in one ~2h session. On renumber, sweep the plan body, `tasks.md` and AC8 in the same edit.
- **Never put a path literal on a `run_suite` line.** `lint-orphan-test-suites.sh:57` is satisfied by
  any `scripts/*.test.sh` appearing after the `run_suite ` token, so an inline predicate list would
  register a *different* suite than the one executed. Arrays by name; the reasoning is already written
  at `:96-100` for `REQUIRED_RUNNERS`.
- **Do not add a CI assertion that skips did not occur.** On `main` both diff refs resolve and return
  empty, `_infra_detect_ok` is `1`, so the fail-SAFE arm does not rescue it and the assertion would
  red main-health-monitor every six hours. Force the predicate true under `CI` instead.
- **Do not `grep -l 'schedule:'` to enumerate this repo's scheduled work.** Scheduling moved to Inngest
  as the single substrate, so the 6-hourly full-gate backstop has only a `workflow_dispatch` trigger.
  Grep for the thing being scheduled (`test-all.sh`), not the scheduling keyword. A sweep that answered
  the wrong question nearly put a redundant workflow into this plan.
- **The shipped per-suite tmp probe measures entries, not bytes.** `tmp_delta=` is a count; ADR-133's
  capacity verdict is about bytes, and that ADR rejected count-based reasoning as recovering 4.5% of
  the problem. Do not read `tmp_delta` as evidence about capacity.
- **`TMPDIR` and `TC_TMPDIR` are deliberately different mounts** (`test-all.sh:16` vs `:30`). Any probe
  resolving them to one value re-creates the fail-open the comment at `:18-29` was written to prevent.
- **`_site/` is untracked and is a producer/consumer pair between two suites**
  (`validate-blog-links.sh:7-12` reads it; `plugins/soleur/test/seo-aeo-drift-guard.test.ts:8-10,48-51`
  builds it). Any future caching or skip mechanism keyed on tracked content alone will serve a stale
  green here. This is what deferred Item 5.
