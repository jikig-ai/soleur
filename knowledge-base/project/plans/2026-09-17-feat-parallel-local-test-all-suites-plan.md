---
title: "workflows: parallelize independent local test-all suites safely"
date: 2026-09-17
slug: feat-parallel-local-test-all-suites
branch: feat-one-shot-8231-parallel-test-all
issue: 8231
closes: 8231
lane: cross-domain
type: chore
priority: p3-low
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for
this branch at plan time.

## Enhancement Summary

**Deepened on:** 2026-09-17
**Reviewed by:** `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
`architecture-strategist`, `spec-flow-analyzer`, plus a scoped `cto` consult and two research passes.
Two User-Challenges were persisted rather than applied — see
`knowledge-base/project/specs/feat-one-shot-8231-parallel-test-all/decision-challenges.md`.

### What review changed

1. **The plan got smaller.** Fifteen new files became four; three guards became two; two Phase-4
   gates became one; eight benchmark runs became two; forty-five acceptance criteria became twenty.
   Every cut is recorded in `## Alternative Approaches Considered` with the mechanism that already
   covered it.
2. **Property 1 was bought by nothing, and now is.** A hand-declared token table with a fail-closed
   drain-barrier default would have left ~420 of 434 registrations demanding an empty pool — a
   parallel mode *slower than serial*, with the classification campaign that would fix it in no
   phase. The table is now **derived** from each suite's own source, with a small override table.
3. **Two go/no-go gates were added ahead of everything.** The Amdahl ratio (0.4a) and the
   nested-spawn wall-clock share (0.5) can each cancel the work before a line is written, and
   reaching a stop verdict is a passing outcome.
4. **Five factual errors of the plan's own were found and corrected**, each by reading the authority
   rather than by argument: `--enumerate` returns **zero** records at rc 1 on this host; the
   `systemd-run` capacity probe checked rc rather than the constrained `nproc` and does **not**
   constrain; `_site/` is a producer/**producer** pair, not producer/consumer; a nested runner
   **refuses** (exit 4) before the lock rather than blocking on it; and the terraform-cache row's
   "zero hits" was two, both benign.
5. **One defect was found by probing bash rather than reading it.** A backgrounded brace group keeps
   the parent's argv, so every worker would have read as a sibling `test-all.sh` run to any other
   worktree — corrupting the sibling census, `--capacity`, and ADR-196's refusal. The fix is one
   token: `( exec "$@" ) &`.

### New considerations discovered

- A green-tree repeat-run experiment cannot detect misattribution, because any index→rc mapping
  satisfies "identical verdict sets" when every rc is 0. Fault injection is the correctness gate;
  repetition is an observation with its power calculation beside it.
- Every guard arm must run under `env -u CI`, or the guards exercise the serial path in the one
  place that blocks a merge and the parallel path gets no CI coverage at all.
- A ceiling trip makes the serial and parallel arms incomparable by construction, so every benchmark
  arm pins the ceiling beyond reach and asserts `_ceiling_declined == 0` before any comparison.
- Re-entrancy on the advisory lock is **prohibited** by ADR-196 D1/D7, not merely a weakening of
  ADR-133 — it is the declared-antecedent pattern that ADR shipped `TC_SIBLING_RUN_COUNT_PID` to end.

## Overview

`scripts/test-all.sh` is this repository's single load-bearing local gate. It walks **434
registrations** one at a time — measured this session with
`bash scripts/test-all.sh --enumerate all | grep -c '^SUITE_REGISTRATION'`, of which 216 come from
the `SUITE_GLOBS` array and 218 from hand-written `run_suite` / `skip_suite` sites. The last
measured uncontended cost of a full pass is 2,721,182 ms (~45.4 min) and the contended cost
3,381,917 ms (~56.4 min) — **both measured 2026-08-11 over a 291-suite population, so against
today's 434 they are lower bounds, not current figures.** `lefthook.yml:332` runs that whole battery from `pre-commit` on
any `*.{ts,tsx,js,jsx}` hit, so the cost lands on a developer holding a commit open.

The obvious remedy — run independent suites concurrently — is blocked by a fact the issue body
omits. This repository already has one parallel suite runner,
`apps/web-platform/infra/run-registered-suites.sh`, which dispatches at `xargs -P min(nproc,6)`,
and it has a measured, open, undiagnosed interference bug (#7376). Adding a second instance of a
mechanism whose first instance is undiagnosed multiplies an unexplained defect rather than
introducing a capability.

**The size of the prize is bounded and is not yet known.** The speedup ceiling is
`total ÷ longest_relevant_suite`, and when the two heavy batteries are relevant the longest is
~14.3 min against a ~45.4 min total — no scheduler beats ~3.2×. When they decline, the total is
~26.6 min and the longest remaining suite is **unmeasured**. A pre-commit hook at 8-14 min is still
a hook developers bypass (`lefthook.yml:314-316` records 3,861 s and four `--no-verify` bypasses on
PR #7866), so parallelism alone does not make that surface usable — scoping the hook's glob (#8045)
is what would. **Phase 0 therefore opens with a go/no-go that can cancel this work**, and the first
thing it measures is the ratio that decides it.

This plan then runs in three ordered movements. It **diagnoses** the interference already measured
in the repo's one existing parallel suite runner, **fixes** only the collisions that diagnosis
attributes, and adds a **bounded parallel mode** in which only suite-body execution is concurrent —
accounting, classification, log shape, the terminal marker and the exit contract all stay serial and
in registration order.

## Research Insights

### Premise Validation (Phase 0.6)

Every issue the brief cites by reference was probed with `gh issue view <N> --json state`. All
eight are **OPEN** and the premise holds: #8231 (target), #7454, #7376, #7432, #7554, #7076,
#8045, #6496. No cited blocker has silently closed, and #8231 is not already resolved by a merged
PR. #8231 is milestoned `Post-MVP / Later` at `priority/p3-low`, labelled `meta/machinery` — the
operator has chosen to implement it now, which is recorded here rather than re-litigated.

Two cited artifacts needed relocation rather than correction: the test-pipeline
`decision-challenges.md` and the 2026-08-11 post-mortem's plan/spec have been **archived** since
they were written. Read at
`knowledge-base/project/specs/archive/20260811-182849-feat-one-shot-test-pipeline-efficiency/decision-challenges.md`
(UC-1, UC-2) and
`knowledge-base/project/plans/archive/20260811-002501-2026-08-10-fix-infra-suite-runner-parallel-flake-plan.md`.

One premise in the brief is **stale and is corrected here.** #7376's body records "three
DIFFERENT suites failing across two of six executions". `.github/workflows/main-health-monitor.yml`
lines 294-296, written later, records the superseding figure: *"measured across SEVEN executions of
the same 92-suite set on an unchanged tree, three failed naming four different suites"*. Both are
cited below with their source; neither is silently preferred.

A second premise in the brief is **already satisfied and must not be re-delivered.** #7376 says
*"the executor runs each suite as `bash "{}" >/dev/null 2>&1` and prints only PASS/RED, so a CI
failure carries no diagnostic output at all… That observability gap is arguably the first thing to
fix."* That gap was closed by the #7429 work: `run-registered-suites.sh:398-404` now captures
`>"$SOLEUR_SUITE_LOGDIR/$key.log" 2>&1` per suite and writes `rc elapsed start_offset` to
`$key.meta`. The diagnosis phase below therefore **reads an instrument that already exists**; it
does not build one.

### Property List (Phase 0.6b)

1. A full local gate finishes in materially less wall clock than the measured serial baseline on a
   host with spare capacity.
2. A parallel run's verdict set is identical to a serial run's verdict set on the same tree.
3. The population of suites executed under parallel scheduling equals the population the
   registration source declares.
4. The exit contract survives: marker + rc 0 green, rc 1 failure-dominant, rc 3 UNRESOLVED
   (terminated), rc 2 usage, no marker + rc 4 refused-before-anything-ran.
5. A suite that must not run beside another does not run beside it **within a run**; across worktrees the guarantee is ADR-133's advisory one — serialise, or announce and proceed at width 1 — never exclusion.
6. A failure's diagnostic output stays attributable to the suite that produced it.
7. Concurrency width never oversubscribes a constrained runner.
8. The operator can obtain serial execution deterministically.

### Cut List (Phase 0.6b)

Each row is `mechanism → property it would buy → what already buys it`. Every "what already buys
it" was established by reading the authority named, per `hr-verify-repo-capability-claim-before-assert`.

| Mechanism proposed or implied | Property | Already covered by | Verdict |
|---|---|---|---|
| A second, hand-maintained list of parallel-safe suites | 3 | `scripts/test-all.sh:173-210` `--enumerate` / `--enumerate-commands`, which emit `SUITE_REGISTRATION` / `SUITE_COMMAND` TAB records derived from the `run_suite` / `skip_suite` chokepoints | **CUT.** The population is derived. Only the per-suite *lane* is declared, and a census guard requires every derived label to carry one. |
| A new cross-worktree mutex for the parallel mode | 5 | ADR-133 Decision 3 + `scripts/lib/test-contention.sh` `tc_acquire` | **CUT — but the guarantee is weaker than "exclusion", and Property 5 is restated accordingly.** The lock is *advisory*: `TC_LOCK_TIMEOUT` is 3600 s and on expiry it fires `LOCK_CONTENDED_PROCEEDING` and **runs anyway**. ADR-133's 2026-08-11 addendum records a real run that queued the full budget while **three siblings executed concurrently**. So the cross-worktree half is "serialise, or announce and proceed", never "exclude" — a second mutex would not change that. What this plan adds is 3.5's fallback to width 1 when the lock was not actually taken. |
| A per-suite log-capture and rc sideband for the top level | 6 | Not present at the top level; `run_suite` streams suite output inline | **KEPT**, but built as an in-process capture, not a file-borne rc (see the `.meta` row). |
| A `.meta`-style file channel carrying each child's rc | 4, 6 | `run-registered-suites.sh:398-404` uses one, and #7554 records that any suite can forge or erase a sibling's because `SOLEUR_SUITE_LOGDIR` is exported to all of them | **CUT for the new runner.** `wait -n -p` returns the child's rc in-process. Measured this session on bash 5.3.15: `bash -c 'bash -c "kill -TERM \$\$" & wait -n -p P; echo $?'` → `143`. That is a **directly observed** signal-shaped rc, which is the only shape ADR-187 §2 permits a wrapper to re-emit. |
| A hand-declared token table with a fail-closed `*` default | 5, 7 | Nothing — and it delivers Property 1 to nobody, because ~420 of 434 labels default to a drain barrier | **CUT.** Replaced by a derived classifier plus a small override table. See Phase 3.1. |
| A standalone lane-census suite | 3, 5 | `scripts/lint-orphan-test-suites.sh:229-232` (fail-closed contract consumer) and `:669` (derived-floor census of `test-relevance-paths.sh`); `scripts/lib/test-relevance-paths.sh` has **no** sibling suite | **CUT.** The census is a check in that linter. |
| A standalone cross-worktree contention suite | 5 | `scripts/lib/test-contention.sh` + `scripts/test-all-runtime-ceiling.test.sh`, which already drive `tc_acquire` — and `tc_acquire` no-ops under `CI`, so the arm could not pass there | **CUT.** Folded into Guard 1 under `env -u CI`. |
| A soak-enrolled follow-through gating the default flip | 1, 2 | Nothing — and it is green by construction (serial-vs-serial during the soak) | **CUT.** The fallback carries the residual risk; rollback is one word. |
| A three-name lane vocabulary (`parallel` / `serial` / `serial-after`) | 5 | Nothing — and it cannot express C1 (needs a drained pool, not a slot) or C3 (ordering is not exclusion against a third writer) | **CUT.** Replaced by one resource-token declaration, which is strictly more expressive and is a single mechanism rather than three names. See Phase 3.1. |
| An "already green" memo keyed on a tree hash | 1 | Nothing — and UC-1 records the structural defect that kills it (`_site/` is untracked and is a producer/consumer pair across two suites) | **CUT.** Explicitly rejected in writing; not reopened here. |
| Admission control on `/tmp` headroom replacing the mutex | 5, 7 | UC-2 + ADR-133 Alternatives: TOCTOU, and non-monotonic degradation to ENOSPC | **CUT.** Recorded rejection. |
| A relevance/skip gate to cut wall clock | 1 | ADR-181 + `scripts/lib/test-relevance-paths.sh`; the two heaviest batteries already decline on an unrelated diff | **CUT.** Already shipped, and this plan must *preserve* its reporting, not duplicate it. |
| Spawning N child `test-all.sh` processes pinned to `SCRIPTS_SHARD=k/N` | 1 | The ordinal partition at `_shard_selects` (`scripts/test-all.sh:782-789`) is structurally total | **CUT.** Each child would take the advisory lock, emit its own contention preamble, its own terminal marker and its own exit code; aggregating N exit contracts is precisely the collapse property 4 forbids. `scripts/test-all.sh:600` also refuses `SCRIPTS_SHARD` outside `TEST_GROUP=scripts`, and the round-robin balances *neighbours*, not durations. |
| Automatic serial re-run of a suite that reds under parallel mode | 2 | Nothing | **CUT.** `work/SKILL.md` calls a re-run of an unchanged tree a harness defect, never a retry. The run reports the failure as today and additionally names the concurrent set observed at that moment, which is attribution rather than a second verdict. |

### Value proposition, measured (Phase 0.6c)

The justification is a wall-clock saving, so it is quantified here with the command that produced
each number.

| Quantity | Value | Source |
|---|---|---|
| Serial full gate, uncontended | 2,721,182 ms (~45.4 min) over **291** suites | ADR-181 Context; `TEST_TIMING_LOG` sum, 2026-08-11 |
| Serial full gate, under contention | 3,381,917 ms (~56.4 min) over **291** suites | `specs/archive/20260811-182849-feat-one-shot-test-pipeline-efficiency/acceptance-evidence.md:65` |
| Registrations **today** | **434** (`--enumerate all`): 422 `scripts` + 7 `bun` + 4 `webplat` + 1 `infra`, a disjoint total partition | measured this session |
| Infra runner's derived population **today** | **122** (`run-registered-suites.sh --list`), against 124 `*.test.sh` on disk | measured this session; the runner's own prose says 86/93 and is stale |
| Typical run with both heavy batteries declined | 1,595,108 ms (~26.6 min) | same file, line 69 |
| Longest single suite (`registry-gate-mutation-battery`) | 860,692 ms baseline / 1,531,471 ms contended | ADR-181 Context; acceptance-evidence line 66 |
| Second-longest (`cf-tunnel-liveness-gate-mutations`) | 189,289 / 255,338 ms | same |

**The speedup ceiling is `total ÷ longest_relevant_suite`, not `total ÷ P`.** When the registry
battery is relevant, the critical path is ~14.3 min against a ~45.4 min total, so no scheduler can
beat ~3.2×. When both heavy batteries decline — the common case under ADR-181 — the total is
~26.6 min and **the longest remaining suite is not known at plan time.** That number is the single
quantity that decides whether this work is worth its blast radius, and Phase 4 produces it with
`sort -k2 -n -r "$TEST_TIMING_LOG" | head -20`. Recorded here as unmeasured rather than asserted.

### Load-bearing findings verified first-hand this session

- **`--enumerate-commands` is the derivation source #8231 asks for.** `scripts/test-all.sh:180-210`
  emits `SUITE_COMMAND\t<label>\t<argv…>` — the exact argv the runner would exec — and
  `SUITE_COMMAND_DECLINED\t<label>\t<rerun>` from `skip_suite`. It refuses (exit 2) rather than
  emitting a corrupt record, takes no lock, and is already consumed by a shard-totality guard.
- **`wait -n -p` is available and returns signal-shaped rc.** bash 5.3.15 here; probed three ways
  this session, including a SIGTERM'd child returning 143.
- **`JOBS` is a poisoned name.** `main-health-monitor.yml:301-305` records that node-gyp reads
  `JOBS` as its `make -j` width, which is why the pins are step-scoped. The new control must not
  reuse it.
- **One documented co-location invariant already forbids exactly this change.**
  `scripts/validate-blog-links.sh:7-15`: *"co-location is a perf optimization (build once, reuse)
  plus defense in depth against any future xargs-P / --max-pool-size attempt that would
  re-introduce the race inside one runner."* `_site/` is built by
  `plugins/soleur/test/seo-aeo-drift-guard.test.ts` and read by `validate-blog-links.sh`; both sit
  in the `bun` group. This is a producer/consumer edge that must be serialized, discovered by
  reading the authority rather than hypothesized.
- **The named top-level tree-copy collision is real.**
  `scripts/cf-tunnel-liveness-gate-mutations.test.sh:53-54` runs `cp -a "$REPO_ROOT/scripts"` and
  `cp -a "$REPO_ROOT/.github"` into its sandbox, then `cp -a "$SB/repo" "$SB/pristine"` (`:67`) and
  restores from it per mutation (`:77`), while other suites write into the same worktree.
- **The deadline-sensitive population is 37 suites.**
  `git grep -lE '(^|[^_[:alnum:]])timeout[[:space:]]+(-k[[:space:]]+[0-9]+[[:space:]]+)?[0-9]+' -- '*.test.sh' | wc -l`
  → **37** of 460 tracked `*.test.sh`. The deadline histogram is dominated by short values
  (21 × 60 s, 14 × 25 s, 12 × 30 s, 12 × 45 s). Those are the H4 class: added concurrency inflates
  elapsed time and fires them.
- **The wall-clock *assertion* class is exactly one suite.**
  `scripts/md-to-mrkdwn.test.mjs:283` (`assert.equal(elapsedMs < 500, true, …)`), which is #6496.
  This is a bounded grep over `*.test.sh` / `*.test.mjs` / `*.test.ts`, not a universal negative.
- **The `.meta` forgery channel is confirmed.** `run-registered-suites.sh:398-404` derives
  `key="${s//\//_}"` and writes `$SOLEUR_SUITE_LOGDIR/$key.meta`, and that directory is exported to
  every suite — so any suite can address a sibling's key. That is #7554.
- **The monitor pins are at two step-scoped `env:` blocks**, `main-health-monitor.yml:306` (tests
  step, which nests `scripts/test-all.sh`) and `:325` (infra step). The assertion that pins them is
  `plugins/soleur/test/main-health-monitor-workflow.test.sh:470-486`, check (12), whose predicate is
  `re.search(r'^          JOBS:\s*1\s*$', env, re.M)` over both step ids.
- **`c4-count-parity` is green and none of its counted quantities move.** Ran
  `bash plugins/soleur/test/c4-count-parity.test.sh` → 10 passed, 0 failed.
- **`--enumerate` returns ZERO records and rc 1 on this host as shipped.** Measured:
  `bash scripts/test-all.sh --enumerate all | grep -c '^SUITE_REGISTRATION'` → **0**, because the
  version check at `scripts/test-all.sh:318-325` runs `actual=$(bun --version)` under
  `set -euo pipefail` (line 2). `command -v bun` succeeds — a `mise` shim is on PATH — but the shim
  exits 1 (`No version is set for shim: bun`), so the unguarded command substitution aborts the
  script before a single registration is reached. With the shim directory removed from PATH the same
  command returns **434**. This is a live defect in the very derivation source this plan depends on,
  and it is the reason every floor below is an **absolute non-zero minimum** rather than the derived
  count: a floor of `derived >= derived` is `0 >= 0` on this host — a guard containing an instance of
  the class it guards. The one-character fix (`|| actual=""`, skip on empty) is in scope because the
  scheduler cannot derive its population without it.
- **`scripts/lint-orphan-test-suites.sh` is the precedent for consuming a runner-published contract,
  and it is where a declaration census belongs.** It already invokes
  `env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 bash "$RUNNER" --print-suite-globs`
  (`:229`) and **fails closed on rc and on a zero pattern count** (`:232`); it already sources
  `scripts/lib/test-relevance-paths.sh` (`:575-580`) and censuses `RELEVANCE_ARRAYS` against
  `test-all.sh`'s `_diff_touches` gate count with a derived floor (`:669`). Decisively: **there is no
  `scripts/lib/test-relevance-paths.test.sh`** — the precedent this plan models its declarations on
  is censused by that linter, not by a sibling suite. A new sibling suite would be a mechanism the
  repo already has.
- **Next free ADR ordinal is 225**, derived across all 86 `refs/remotes/origin` refs (max on `main`
  is ADR-223; ADR-224 is claimed on a pushed branch). Provisional, per the Sharp Edge.

### Structural collision inventory (grepped, not hypothesized)

These are **priors for Phase 1, not findings**. Each was located by reading the authority named; none
is asserted as a cause of #7376, and Phase 1's `SUITE_TRACE` record is what decides whether any of
them actually fires. They are recorded here because they constrain the Phase 3 declaration table regardless
of what Phase 1 concludes.

| # | Surface | Evidence | Consequence under concurrency |
|---|---|---|---|
| C1 | **`scripts/cf-tunnel-liveness-gate-mutations.test.sh` asserts on the LIVE worktree.** `:139` `TREE_BEFORE="$(git -C "$REPO_ROOT" status --porcelain -- scripts .github)"`, `:302` `TREE_AFTER=…`, `:303-306` fails with *"a mutation escaped the sandbox"*. | read directly | For its ~189 s window, **any** sibling that creates, modifies or deletes a file under `scripts/` or `.github/` produces a false FAIL attributed to a sandbox escape. Also `cp -a` of the whole `scripts/` + `.github/` twice (`:53-54`, `:67`) and a restore per mutation (`:77`). **Forces `resources="*"` — a drained pool, not a slot.** |
| C2 | Same suite's `git status --porcelain` carries **no `--no-optional-locks`**, so it refreshes and rewrites `.git/index`. | read directly | Contends for `.git/index.lock` with every other live-repo `git` call in flight. The canonical statement of this hazard is `apps/web-platform/infra/workspaces-luks-g4-mutation.test.sh:945-959`. |
| C3 | **`_site/` is a SHARED WRITE TARGET, and the in-tree comment describing it is stale.** `scripts/validate-blog-links.sh:35-39` is itself the **producer** — registered with no argument (`test-all.sh:2562`), so `SITE_DIR` is empty and it runs `npx --yes @11ty/eleventy` into `$REPO_ROOT/_site`. `plugins/soleur/test/seo-aeo-drift-guard.test.ts:56-58` builds into a `mkdtempSync` dir and touches repo `_site/` **only** under `SEO_AEO_SKIP_BUILD=1` (`:47-55`). So the relationship is producer/producer over one path, **not** producer/consumer, and `after="plugins/soleur"` would order a suite behind something that is not its producer. Other `_site` referents (`scripts/content-publisher.test.sh`, `plugins/soleur/test/marketing-content-drift.test.ts`) make the shared-target reading the correct one. Both `scripts/test-all.sh:2554-2559` and `validate-blog-links.sh:7-15` name a future `xargs -P` attempt as the hazard, which is why the warning is load-bearing even though its stated producer is wrong. | read directly, this session | `_site/` is gitignored, so the repo-write boundary **cannot see this race** — it is silent. **Forces a shared `artifact:_site` token on BOTH sides, plus an ordering edge.** |
| C4 | **72 tracked suites reference `scripts/test-all.sh`**; exactly **5** set `SOLEUR_DISABLE_SESSION_STATE`. **The "a child blocks for up to `TC_LOCK_TIMEOUT`" reading is WRONG on most invocations, and is corrected here:** ADR-196's refusal at `scripts/test-all.sh:1326-1346` fires **before** `tc_acquire` at `:1495` — verified this session, and the ordering is part of ADR-196's decision, pinned by `plugins/soleur/test/fanout-suite-scope.test.sh` — and `suite_exit_class` maps its `exit 4` to `failed`. A nested real runner therefore **reds its parent suite immediately**; it does not deadlock. The deadlock exists only where `SOLEUR_ALLOW_FULL_GATE=1` is inherited, i.e. the two payer paths `lefthook.yml:332` and `grok-pre-push-gate.sh:165`. **Phase 0.5 must measure under that inherited hatch, not under a plain invocation, or it measures the refusing path.** | grep counts plus the line ordering, this session |
| C5 | **Sibling-detection walks `/proc` for any cmdline mentioning `test-all.sh`.** The refusal is `scripts/test-all.sh:1326-1346`; the `TC_SIBLING_RUN_COUNT_PID == $$` conjunct makes an *inherited* count inert but does not protect a **freshly walked** one. | read directly | A worker pool exposes the parent's own cmdline to any child that runs `tc_preamble`. **Three editing constraints, from `plugins/soleur/test/fanout-suite-scope.test.sh:327-340`:** the anchor is `^if [[ "${TC_SIBLING_RUN_COUNT:-0}"` — the `:-0` is **part of it**, so a leading conjunct reds the guard; it must match **exactly once**; and `REFUSAL_LN < ACQUIRE_LN` is asserted against `^tc_acquire "test-all"` at column 0, so the scheduler may neither wrap nor relocate `tc_acquire`. `scripts/test-all.sh:1490-1493` additionally records that the acquire statement's and the epilogue call's full text are uniqueness-asserted by the sandbox builders, so no second textual copy of either may be added. |
| C6 | **Nested parallelism multiplier.** `scripts/test-all.sh:2713` registers `run-registered-suites.sh` as one suite; that runner forks `-P min(nproc,6)` (`:281`), which is **6** on this 16-core host. **13** top-level suites *mention* it; measured, only **1** actually spawns it. The `J x 6` claim rests on the spawning count, not the mention count — the identical conflation this inventory refuses for C4, corrected here rather than inherited. | read directly, this session | Peak process width is `J × 6` unless the inner width is bound. **Forces `cpu:pool`** on the infra registration, and Phase 3.4's budget propagation must bind the inner `JOBS` for the sandboxed spawns. |
| C7 | **Two `vitest` registrations share one working directory.** `scripts/test-all.sh:2515` and `:2518` both `cd apps/web-platform && npm run test:ci`. | read directly | They share `node_modules/.vite` and `node_modules/.cache`. The prior in-script `xargs -P` rejection (`knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md:588`) names a `process.env` leak in `apps/web-platform/test/workspace.test.ts` as one of its sharp edges. |
| C8 | **Whole-box-sensitive suites.** `scripts/orphan-process-reaper.test.sh` and `-mutation.test.sh` walk `/proc`; `scripts/test-all.sh:1260-1271` runs the reaper's live `report` with `ORPHAN_REAPER_EXCLUDE_PGID`. `scripts/test-all-capacity-signal.test.sh`'s entire subject is the sibling count. | read directly | A worker pool changes the descendant set the reaper observes. **Forces `resources="*"`** for this family. |
| C9 | **The canonical precedent already exists in-tree.** `scripts/tmpfs-guard.test.sh:80-92` documents a suite whose colour depended on another process holding a shared lock (*"Observed 28/4 on a run that raced the live cron"*) and its fix: inject `TMPFS_GUARD_LOCKFILE` pointing at the suite's own root. | read directly | This is the shape every C1-C8 remedy should take — inject a run-scoped path, do not widen a global one. |
| C10 | **Fixed temp paths, ports, docker names and terraform caches are clean.** `/tmp/<fixed>` hits are PID-scoped (`/tmp/cron-stale-out.$$`) or fixture text; every binding suite uses an OS-allocated port; docker names are `$$`/`$RANDOM`-scoped with the reasoning already recorded at `apps/web-platform/infra/cloud-init-plugin-seed.test.sh:27-40`; `TF_DATA_DIR` / `TF_PLUGIN_CACHE_DIR` return **two** hits, both in `apps/web-platform/infra/git-data-root-key.test.sh` (`:568`, `:742`) and both **assertions about a workflow's** `TF_DATA_DIR` living under `runner.temp` — not a suite sharing a cache. The substance holds; the "zero hits" phrasing this row first carried did not, and is corrected here rather than inherited. | grep | These four classes are **not** collision surfaces. Recorded so Phase 1 does not re-derive them and Phase 2 does not "fix" them. |

**Correction to a premise in #7454.** Its re-evaluation trigger names *"the per-mount bytes probe
(`bytes_tmp=` / `bytes_tmpdir=` in `TEST_TIMING_LOG`)"* as a mechanism that could identify the
interference. Read at `scripts/test-all.sh:471-478`, `_emit_bytes_probe` is called at exactly **two**
sites — `__run_boundary_start__` (`:1574`) and `__run_boundary_end__` (`:2799`) — deliberately, to
avoid the observer effect of a `du` walk per suite (`:455-468`). It is therefore a **run-boundary**
measurement and **cannot attribute bytes to a suite**. The trigger as written cannot be satisfied by
that probe; Phase 1's per-suite `SUITE_TRACE` record is what supplies the attribution #7454 wanted.

### Governing ADRs

| ADR | What it binds here |
|---|---|
| ADR-133 | Managed tmpfs + advisory cross-worktree lock. **Decision 1: "Instrumentation ships ahead of every fix."** This plan's phase ordering follows it — but **its own 2026-08-11 addendum already records the `run-registered-suites.sh` capture as a departure** ("an instrument that is not observe-only is a confound for the hypothesis it exists to measure"), and Phase 1 deepens that departure with a parent-side sampler. Following a decision is not amending it; what this plan *amends* is Decision 3 (see the ADR section). |
| ADR-177 | `[ok]` / `[FAIL]` / `[KILLED]` taxonomy and the exit contract. `[ok]` and `[FAIL]` are anchored byte-for-byte by 11 learning files and four skills; the scheduler may not re-spell them. |
| ADR-181 | A decline is a counted verdict. `run_suite` increments `suites` on entry; a healthy local run reads `N-k/N`. The scheduler must not flatten declines. **Not a precedent for a 434-row per-suite table:** its Decision 3 establishes two *path arrays* whose load-bearing property is self-correction — each array contains its own battery file, so new-target drift corrects itself. A `label → tokens` table has no analogue, which is why this plan derives the classification instead of hand-declaring it and censuses what it cannot derive. |
| ADR-183 | The full battery runs at `/ship` Phase 4, not at implementation exit. That, plus `lefthook.yml:332` and `grok-pre-push-gate.sh`, is the payer set for this work. |
| ADR-187 | A nested runner may exit `128+N` only for an `N` it **directly observed**. Precedence ladder `failed > UNACCOUNTED > killed`. |
| ADR-193 | Anti-vacuity floor contract: floors report via `printf >&2` + `exit 1`, the case counter increments at the call site and never inside `$( )`, population is derived and never listed, conservation check runs before the floor. |
| ADR-196 | Owns the pre-lock sibling refusal at `scripts/test-all.sh:1326-1346` and its `exit 4`. **Decision 1:** a refusal antecedent must be a condition the runner can OBSERVE from inside its own process. **Decision 7** names the exact mechanism a re-entrant lock would be — a declared antecedent "re-entering through an environment variable" — which is why re-entrancy is *prohibited* here, not merely deferred. Decision 4 fixes the refusal-before-`tc_acquire` ordering the scheduler must preserve. |
| ADR-166 / AP-021 | An operator-facing message may name only a cause the job measured. Binds the runner's banners, the sibling census the `exec` fix protects, and this plan's own hypothesis table. |

### Precedent diff (deepen-plan Phase 4.4)

Every pattern-bound behaviour this plan prescribes has a sibling precedent in the repo, and each was
diffed rather than invented:

| Prescribed behaviour | Precedent | How this plan differs, and why |
|---|---|---|
| A bounded worker pool over suites | `apps/web-platform/infra/run-registered-suites.sh:397-412` (`xargs -P`) | `wait -n -p` instead of `xargs`, because `xargs` cannot return per-child rc and therefore forces the `.meta` sideband that is #7554. The rc becomes directly observed, which is the only shape ADR-187 §2 permits a wrapper to re-emit. |
| Per-suite output capture | same runner, `:398-404` and `:376-391` | Two files per suite (`.out`/`.err`) rather than one `2>&1`, because the top level's `[ok]`/`[skip]` and `[FAIL]`/`[KILLED]` are split across fds and a merged replay widens a documented forgery channel. The PIPE_BUF constraint carries over verbatim. |
| A cross-worktree advisory lock | `scripts/lib/test-contention.sh` `tc_acquire` → `session-state.sh`'s `acquire_lock` | Reused unchanged and held once by the parent. No new primitive. |
| Per-suite declarations read by two consumers | `scripts/lib/test-relevance-paths.sh`, censused by `scripts/lint-orphan-test-suites.sh:575-580`, `:669` | Same file shape and same censusing consumer. It is **not** a precedent for a 434-row hand table: its self-correction property does not transfer, which is why this plan derives the classification. |
| Consuming a runner-published contract | `scripts/lint-orphan-test-suites.sh:229-232` | Copied in shape, including the fail-closed rc-**and**-count check, which is what the zero-record enumerate defect makes load-bearing. |
| A machine-checkable exclusion list with a mandatory reason | `scripts/lint-orphan-test-suites.sh`'s `name|reason` array, recommended by #7076 | Same shape for the override table. |
| A blocking-upward / advisory-downward ratchet | `scripts/lint-diagnosis-claims.highwater` | **Not adopted** — the precedent does not transfer (see Alternatives). |

**Scheduled-work check:** this plan introduces no recurring job, so the Inngest-vs-GH-Actions
precedent (ADR-033) does not apply. **Downtime check:** no serving surface goes offline — this is a
local shell orchestrator with no host, no migration and no router change, so the zero-downtime
cutover gate does not fire.

### Institutional learnings that bind this plan

- `knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`
  — a hypothesis table may not read CONFIRMED or REFUTED while the deciding datum is unavailable;
  the probe ships ahead of the fix and is never deleted using a conclusion it was meant to test.
  **This is the single most binding learning here**, and it is why Phase 1 has no fix in it.
- `knowledge-base/project/learnings/2026-08-11-every-guard-i-wrote-contained-an-instance-of-the-class-it-guarded.md`
  — every guard inherits its author's blind spot. Tells: the guard's own comment asserts an
  invariant it violates; the fixture instantiates one member of the set; the oracle is derived from
  the system under test.
- `knowledge-base/project/learnings/2026-08-11-i-measured-the-issues-remedy-then-asserted-my-own-without-measuring.md`
  — for every mechanism the prose names, run the command that would falsify it.
- `knowledge-base/project/learnings/2026-08-10-pipe-buf-atomicity-does-not-apply-to-the-file-i-was-redirecting-into.md`
  — cited inline at `run-registered-suites.sh:376-386`. Concurrent writers sharing one open file
  description tear lines. The new scheduler gives each suite its **own** capture file and the
  parent is the only writer of the aggregate stream.
- `knowledge-base/project/learnings/2026-08-10-i-fixed-the-guard-twice-and-my-test-could-not-see-either-fix.md`
  — compare the new mechanism against the one already in the codebase before building it.
- `knowledge-base/project/learnings/performance-issues/2026-04-07-bash-file-processing-parallel-xargs-optimization.md`
  — batch-parallel beats per-item spawn. Noted, and **not applicable**: suites here are minutes
  long, so process-spawn amortisation is irrelevant and batching would only coarsen scheduling.

### CLAUDE.md / AGENTS.md conventions engaged

`hr-verify-repo-capability-claim-before-assert` (every "already covered by" above is grepped),
`hr-observability-as-plan-quality-gate`, `hr-no-dashboard-eyeball-pull-data-yourself` (the
diagnosis phase pulls data, it does not read a dashboard), `cq-write-failing-tests-before`,
`cq-assert-anchor-not-bare-token`, `cq-test-fixtures-synthesized-only`,
`hr-never-git-stash-in-worktrees` (relevant to #8045's lefthook hypothesis, which this plan does
not pursue), `wg-when-an-audit-identifies-pre-existing`.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / issue | Reality in the tree | Plan response |
|---|---|---|
| "`run-registered-suites.sh` … prints only PASS/RED, so a CI failure carries no diagnostic output at all" (#7376) | Closed by #7429. `:398-404` captures a per-suite `.log` and writes `rc elapsed start_offset` to a per-suite `.meta`. | Phase 1 **reads** the existing instrument. It adds only the fields the instrument lacks (concurrent set, peak RSS, host headroom minimum). |
| "three DIFFERENT suites failing across two of six executions" (#7376 body) | `main-health-monitor.yml:294-296` records the later figure: seven executions, three failed, four different suites. | Both cited with source. The reproduction harness targets K ≥ 7 to match the larger evidence base. |
| "Derive the suite set from the existing registration source" (#8231) | `--enumerate` / `--enumerate-commands` already do exactly this, with a refuse-on-corrupt record contract. | Consume it. No second list. |
| "keep shared locks around suites that require serialization" (#8231) | The only lock in `test-all.sh` is ADR-133's cross-**worktree** advisory lock. There is no intra-run, per-suite lock, because the runner has never been concurrent. | Intra-run serialization is expressed as a **per-suite resource-token declaration** plus a drain barrier, not as a new lock primitive. The cross-worktree lock is unchanged and is held once, by the parent. |
| "#7376 is the measured flakiness of that runner on this hardware" (#7454) | The flake reproduced on **4-core GitHub-hosted** runners. #7376's own table records `-P 6` on a 16-core box as clean, and this development host is 16-core / 30 GiB. | The flake is **not reproducible here by default.** Phase 1's first deliverable is a capacity-constrained reproduction (`systemd-run --user --scope`, probed working this session) that manufactures the 4-core class locally. Without it the diagnosis has no subject. |
| ADR-181 "declines three suites, so a healthy local run reads `N-3/N`" (brief) | The mechanism is real (`skip_suite`, `scripts/test-all.sh:844-873`). The *count* is diff-dependent: `skip_suite` appears 7 times in the file. | The plan asserts the **mechanism** (declines stay counted, `skipped` and `_ceiling_declined` both subtract from the numerator at `:2990`), never the literal 3. |
| "keep shared locks … prove no cross-worktree contamination" implies the contention test is new | `scripts/lib/test-contention.sh` is 55,684 bytes and already emits `SIBLING_RUN_DETECTED` / `SIBLING_SUITE_DETECTED` / `LOW_TMP_HEADROOM`, and `scripts/test-all-runtime-ceiling.test.sh` already drives it. | The new contention test **extends** that surface with a two-worktree arm; it does not introduce contention instrumentation. |

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (65 open) and matched every
candidate file path with a standalone `jq --arg` pass.

- **#7942** — *"Two mutation batteries in `plugins/soleur/test/` are named `*.mutation.sh` and run
  in no gate"*. Matches on `scripts/test-all.sh`. **Disposition: acknowledge.** #7942 is a defect in
  the *completeness of the registration source* (two batteries the `plugins/soleur/test/*.test.sh`
  glob cannot see). This plan's population-parity property is an **identity** between what the
  scheduler executes and what the registration source declares — it is orthogonal to whether that
  source is itself complete, and would remain satisfied before and after #7942 lands. Folding it in
  would pull in that issue's separate two-stage-parse defect, which has nothing to do with
  scheduling. #7942 stays open.
- No open code-review issue matches `apps/web-platform/infra/run-registered-suites.sh`,
  `scripts/lib/test-contention.sh`, `lefthook.yml`, or `.github/workflows/main-health-monitor.yml`.

## Hypotheses

Per ADR-166 / AP-021 and the 2026-07-16 learning, every row below is **UNKNOWN at plan time** and
stays UNKNOWN until Phase 1's instrument decides it. No row may be marked REFUTED by reasoning.

| ID | Hypothesis | Status | Discriminator (the field that decides it) |
|---|---|---|---|
| H1 | `pipefail` / SIGPIPE in the xargs shim | **REFUTED — by measurement**, in the archived #7376 plan (measured ~12× off on the measured variable). Recorded, not re-tested. | — |
| H2 | Resource exhaustion (memory / CPU / fd / disk) under `-P 4` on a 4-core box | **UNKNOWN** | `host_avail_mem_mb_min` and `host_fd_used_max` sampled across the failing suite's window; a failure that tracks a headroom floor **independent of which neighbours were running** is H2. |
| H3 | Shared-state collision between specific suites | **UNKNOWN** | `concurrent_set` — the labels in flight when the failing suite started and ended. A failure that recurs only when a particular neighbour is in `concurrent_set` is H3, and the record **names the neighbour**. |
| H4 | A polling / wall-clock deadline fires because concurrency inflates elapsed time | **UNKNOWN**. #7432 records H2 and H4 as explicitly unclaimed by #7376's fix. | `elapsed_ms` against the same suite's serial `elapsed_ms`, plus whether the suite's own failing line matches a deadline shape. The 37-suite `timeout` population above is this hypothesis's prior. |
| H5 | The failing suites write into the live worktree that a neighbour reads | **UNKNOWN** | A per-suite write footprint outside its own sandbox, captured as the set of repo-relative paths whose mtime moved during the suite's window. |

**One record, all discriminators.** Per `plan/SKILL.md` §2.9.2, the probe emits a single structured
record per suite carrying every field above, so one run discriminates the whole tree rather than
requiring a separate experiment per hypothesis:

```
SUITE_TRACE\t<label>\t<rc>\t<elapsed_ms>\t<start_offset_ms>\tconcurrent=<l1,l2,…>\tpeak_rss_kb=<n>\ttmp_bytes_delta=<n>\tavail_mem_mb_min=<n>\tfd_used_max=<n>\twrote_outside_sandbox=<n>
```

**The honest exits are named in advance.** If K ≥ 7 constrained runs produce no failure, the
verdict is "not reproducible at this capacity on this host" and every hypothesis stays UNKNOWN —
Phase 2 then ships nothing, and Phase 3's default resolves to serial. That is a permitted outcome
of this plan, not a failure of it.

## User-Brand Impact

**If this lands broken, the user experiences:** a `git commit` that takes longer than today, or —
the harm that matters — a `[FAIL]` line on `scripts/test-all.sh` naming a suite that has no defect,
because a neighbour interfered with it. That is the #8045 shape: a false RED that blocks a
legitimate commit and costs an hour of investigation. In the worse direction, a suite whose
coverage was never obtained is reported as passed, which is a green that was not earned.

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. This
change is confined to a local shell test orchestrator. It reads no credential store, opens no
network socket, writes nothing outside the worktree and the process's own temp sandbox, and ships
no artifact to a third party.

**Brand-survival threshold:** `none`.

- `threshold: none, reason: the change is a local test orchestrator with no user-facing surface, no
  persisted data, no credential read and no network egress; the worst outcome is a developer-visible
  test verdict, which the contract and guards below are built to keep honest.`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Assessed against all eight
domain questions: this is local verification machinery with no user-facing surface, no pricing,
legal, support, revenue, or data-processing implication. The mechanical UI-surface override does
not fire: `## Files to Create` and `## Files to Edit` contain no path matching
`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any term on the shared
UI-surface list. Product tier is therefore **NONE** and no wireframe gate applies. The Playwright
MCP server is disconnected this session and no browser-driven verification is planned or needed.

## Implementation Phases

### Phase 0 — Preconditions (no production edit)

Each precondition is a command whose output is pasted into
`knowledge-base/project/specs/feat-one-shot-8231-parallel-test-all/acceptance-evidence.md`. A
precondition that fails re-shapes the plan rather than being worked around.

0.1 **Repair the enumeration contract, then verify it.** As shipped it is broken here:
`bash scripts/test-all.sh --enumerate all | grep -c '^SUITE_REGISTRATION'` returns **0** at rc 1,
because `actual=$(bun --version)` at `:318-325` aborts under `set -e` when a `mise` shim is on PATH
without a pinned version. Guard the substitution (`|| actual=""`, skip on empty) so the
documented side-effect-free enumerate path is also **toolchain-free**, as its own header claims.
Then record the four per-group counts and the `all` count, and confirm the four sum to `all`.

**Every consumer of this contract fails closed on rc AND on a zero count**, copying
`scripts/lint-orphan-test-suites.sh:229-232` verbatim in shape. A consumer that reads `grep -c` alone
sees `0` and proceeds over an empty population — which is how an anti-vacuity floor written as
`derived >= derived` becomes `0 >= 0`. Every floor in this plan is an **absolute non-zero minimum**
for that reason.

0.2 **`wait -n -p` is usable.** Re-run the three probes recorded in Research Insights against the
build the gate actually runs under, and record `$BASH_VERSION`. The parallel path is gated on
`((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1)))`; anything lower
resolves to serial with a named banner.

0.3 **Capacity constraint — and the first version of this precondition asserted a proxy.**
Measured this session, which corrects an earlier claim in this plan: `systemd-run --user --scope -q
-p AllowedCPUs=0-3 -p MemoryMax=7G -- nproc` returns **16**, not 4. The scope is created (rc 0) but
`AllowedCPUs` does not take effect, because cpuset is not delegated to this user manager. **rc 0 is
not the invariant; `nproc` inside the scope is.** `taskset -c 0-3 nproc` returns **4**.

The precondition is therefore: assert the *constrained view*, not the exit code, and record which
mechanism this host actually provides. **Name the consequence rather than discovering it in
Phase 1:** `taskset` gives a CPU constraint and **no memory constraint at all**, so on a host
without delegated cpuset/memory control H2 — resource exhaustion — cannot be manufactured and will
terminate UNKNOWN by construction. If that is this host, say so in `diagnosis.md`, and note that
Phase 4.3(e) then governs only the default flip, not whether the scheduler ships.

0.4 **Serial baseline on this host, with two samplers.** One
`TEST_TIMING_LOG=<path> bash scripts/test-all.sh` run with nothing else on the box, carrying
(a) a per-suite **peak-RSS** sampler — the input Phase 3.4's width formula needs over the *top-level*
434 population, which Phase 1's infra-runner instrument cannot supply — and (b) a temporary log of
the pid and cmdline of every `tc_acquire` caller, which is how 0.5 determines membership rather than
guessing it from a grep. Capture `sort -k2 -n -r "$TEST_TIMING_LOG" | head -20` verbatim.

0.4a **Go/no-go #1 — the Amdahl ratio.** From 0.4, compute `total_suite_ms ÷ longest_suite_ms` for
the population a typical diff leaves after ADR-181's declines. **If the ceiling is below 2×, stop
here.** At that ratio the pre-commit hook stays in bypass territory whatever the width, and the
change that reaches the stated pain is #8045 — scoping the hook's glob to what the commit touches.
Recording this as a stop condition rather than a caveat is what keeps the plan from spending its
budget before the number that justifies it exists.

0.5 **Go/no-go: is the top level even the right layer?** This is the one precondition that can
cancel the work, so it runs before anything is built.

**72** tracked `*.test.sh` files under `scripts/`, `plugins/soleur/test/` and `.claude/hooks/`
reference `scripts/test-all.sh` — measured with
`git grep -l "test-all\.sh" -- 'scripts/*.test.sh' 'plugins/soleur/test/*.test.sh' '.claude/hooks/*.test.sh' | wc -l`.
Exactly **5** suites set `SOLEUR_DISABLE_SESSION_STATE`
(`plugins/soleur/test/scripts-shard-totality.test.sh`, `scripts/battery-tag-authorship.test.sh`,
`scripts/test-all-capacity-signal.test.sh`, `scripts/test-all-runtime-ceiling.test.sh`,
`scripts/test-contention.test.sh`). The remainder either sandbox the runner, spawn it in
`--enumerate` mode, or merely name it in a grep assertion — **which of those actually spawn a
lock-taking runner is unmeasured, and that is the blocking set.**

**Membership is MEASURED, not grepped.** A grep cannot tell a suite that *spawns* a lock-taking
runner from one that merely names `test-all.sh` in an assertion: 67 of the 72 lack
`SOLEUR_DISABLE_SESSION_STATE`, which is obviously an over-count. Instead, 0.4's `tc_acquire` caller
log names every process that actually took the lock; walk each entry's ancestry to the registration
that owns it. Then sum `elapsed_ms` over that subset and divide by the run total.

- **If the blocking subset holds a minority of the wall clock**, top-level parallelism is the right
  layer and the work proceeds.
- **If it holds the majority**, the win is *inside* those children, not above them, and top-level
  parallelism is a wrong-architecture commit. The plan stops here and re-scopes — either to a
  re-entrant lock model (below) or to an issue about the children.

This costs one `--enumerate` pass plus the serial run Phase 0.4 is doing anyway.

**Go/no-go #2, and no lock-model fork.** If the blocking subset holds a **minority** of the wall
clock, the work proceeds and every member simply carries the `lock:test-all` token — which the
declaration mechanism already expresses for free. If it holds the **majority**, that is a **no-go**:
the win is inside those children, not above them, and top-level parallelism is the wrong layer.

A re-entrant lock was considered as a third arm and **cut**: it weakens a cross-worktree guarantee
ADR-133 established, and "the free option is expensive" is not a reason to weaken an ADR — it is the
no-go branch. Recorded in ADR-225 with the measured share that decided it.

### Phase 1 — Diagnose (#7376). Ships as its own commit, ahead of any fix.

This phase changes no scheduling behaviour anywhere. It adds an instrument and runs it. The
separation is load-bearing: a fix landed in the same commit as its probe makes the probe's result
un-interpretable, and "there is nothing left to discriminate anyway" is the circular argument the
2026-07-16 learning names.

1.1 **A loop, not a harness.** `run-registered-suites.sh` already writes `rc elapsed start_offset`
per suite (`:402`), already retains the per-suite log dir **on the runs that matter** — `:615-621`
deletes it only when `RED == 0` and nothing is unaccounted, and sets `SOLEUR_KEEP_LOGDIR=1`
otherwise — and already prints the retained path. So the reproduction is

```
for i in $(seq "$K"); do
  systemd-run --user --scope -q -p AllowedCPUs=0-3 -p MemoryMax=7G -- \
    bash apps/web-platform/infra/run-registered-suites.sh >"$out/$i.log" 2>&1 || true
done
```

plus a `sort | uniq -c` over the `^PASS `/`^RED ` lines in `$out/*.log` to name every suite whose
verdict was not constant. **The verdict table comes from the captured stdout, not from the log dir**,
which is why a green run reaping its own dir costs nothing here. (Note the correction: `:361` sets
`SOLEUR_KEEP_LOGDIR=""` unconditionally, so an *exported* value is discarded — retention is the
runner's own failure-path decision, not a knob. Honouring an exported value is a one-line change and
is **optional**, not a precondition.)

This lives in `knowledge-base/project/specs/feat-one-shot-8231-parallel-test-all/diagnosis.md` as a
recorded command, **not** as a script — so it needs no registered suite, no anti-vacuity floor and no
synthesized collision fixture. A fifteen-line loop does not earn a guard.

1.2 **Three new `SUITE_TRACE` fields, appended to the record that already exists.** Of the nine
fields first specified, four (`label`, `rc`, `elapsed_ms`, `start_offset_ms`) are already in `.meta`
verbatim, and `concurrent=<labels>` needs **no new instrumentation at all** — it is an `awk`
interval intersection over the `start_offset` and `elapsed` those files already carry.
`avail_mem_mb_min` reuses `tc_avail_mb` (`scripts/lib/test-contention.sh:118`). A
`tmp_bytes_delta` field was specified and **cut as self-contradictory**: Phase 3.3 argues at length
that a machine-global tmp count is unattributable whenever another suite is in flight, and
`SUITE_TRACE` is emitted *only* during a deliberately concurrent run — so every value it could
carry is the number AC19 forbids one layer up.

What is genuinely new: **`peak_rss_kb`** — read from the **suite child's** `/proc/<pid>/status`
`VmHWM`, sampled just before it is reaped, **never from the shim's own `/proc/self/status`**: a
parent's `VmHWM` does not accumulate a child's peak, so the shim would report its own few megabytes
for every suite and Phase 3.4 would divide available memory by a constant. It is also read
**parent-side**, so it does not re-open the `.meta` write channel AC10 closes — and
**`fd_used_max`**, plus `wrote_outside_sandbox` below. The host-wide samplers run parent-side at
≤ 2 s resolution and **carry a sample count**, so a sampler that dies mid-window reports a
truncated minimum *as truncated* rather than as a minimum — AP-021 applied to the instrument itself.

1.3 **`wrote_outside_sandbox` is an mtime sweep over a declared path set, NOT `git status`.** Two
corrections to the first specification. It cannot be "repo-**tracked** paths whose mtime moved":
`_site/` is gitignored, so that predicate is blind to one of the two classes the field is sold on.
And computing it with `git -C "$ROOT" status --porcelain` would manufacture C2 — a bare
`git status` rewrites `.git/index` and contends for `index.lock` — i.e. the instrument would
create the interference class it is measuring. The sweep walks a declared root set (the worktree
plus the ignored build outputs the collision inventory names) at the window boundaries and needs no
`git` call; if one is ever wanted it must carry `--no-optional-locks`.

**Attribution honesty, and a retirement trigger.** Under `-P` the suite windows overlap, so a
boundary-differenced write is attributable to *the set in flight*, not to one suite — the same
argument Phase 3.3 uses to force `tmp_delta=unattributed`, and it applies here or the plan applies
its own rule to one field and not the other. The record therefore carries
`wrote_outside_sandbox=<n> attributed_to=<set>`, and H5 is decided by the *intersection across runs*
of those sets, not by a single run's count. **The instrument also ships into a runner that executes
on every infra-touching PR and six-hourly on `main`, so it carries a retirement trigger:** it is
removed when H5 is decided, or when the `diagnosis.md` verdict table is written — whichever comes
first — and Phase 5 names the issue that tracks its removal if the verdict is UNKNOWN.

This field and Phase 3.3's `_repo_last_suite`-to-set widening are the same capability at two layers
and share one implementation.

1.4 **Run it.** K ≥ 7 constrained runs. Record the raw table in `acceptance-evidence.md`.

1.5 **Adjudicate.** Write the hypothesis table's final verdicts into
`knowledge-base/project/specs/feat-one-shot-8231-parallel-test-all/diagnosis.md`, one row per
hypothesis, each carrying the field value that decided it. **A hypothesis the data does not decide
is written UNKNOWN**, and UNKNOWN is a valid terminal state for this phase.

1.6 **No registered suite for the loop.** A gate suite whose subject is a deliberate race would be
a nondeterministic assertion inside a green battery — it must either reproduce a collision on
command, which is the thing under investigation, or pass vacuously. The loop's correctness is
established by reading its output, and the same discipline applies in Phase 2: a mutation row
"proving the collision reproduces with the fix reverted" must be **deterministic** (a synthesized
fixture that collides by construction) or it does not go into
`apps/web-platform/infra/run-registered-suites.test.sh` at all.

### Phase 2 — Fix what Phase 1 attributed

**Scope is decided by Phase 1's output, not by this plan.** What is written here is the shape each
attribution takes, so the work does not stall on a design decision mid-phase.

- **If H3 or H5 is attributed:** each named colliding pair gets a per-run-scoped namespace — a
  `mktemp -d` root the suite is told about by environment, with the shared path removed. Every fix
  is accompanied by a mutation row proving the collision reproduces with the fix reverted.
- **If H2 is attributed:** `run-registered-suites.sh:281`'s width becomes a function of measured
  memory headroom as well as `nproc` — `JOBS="${JOBS:-$(_width_from_capacity)}"` — and the runner
  prints the inputs it used. Per ADR-166 the printed line names only what was sampled.
- **If H4 is attributed:** the affected suites are given the `deadline` token in the declaration table introduced in
  Phase 3 and the attribution is recorded against each one. Their internal deadlines are **not**
  raised here; raising a deadline to survive a scheduler moves the flake rather than removing it.
- **If every hypothesis stays UNKNOWN:** Phase 2 ships nothing, Phase 3 still ships (its safety does
  not depend on the diagnosis), and Phase 4's default resolves to serial. This is written down so
  the outcome is a plan branch rather than an improvisation.

**#7432 disposition, stated explicitly.** If and only if Phase 1 attributes a mechanism and Phase 2
fixes it, removing the `JOBS: 1` pins at `.github/workflows/main-health-monitor.yml:306` and `:325`
becomes defensible — and doing so also requires deleting check (12) at
`plugins/soleur/test/main-health-monitor-workflow.test.sh:470-486`, which asserts them. **This plan
does not remove them.** The pins are a stopgap whose removal needs a soak on `main`, and #7432 is
the tracker that owns that soak; Phase 5 posts the diagnosis link to #7432 and leaves it open.
Neither #7432 nor #7376 is closed by this work without the soak evidence each one asks for.

### Phase 3 — Bounded parallel mode in `scripts/test-all.sh` (RED first)

The design in one sentence: **only suite-body execution becomes concurrent; accounting,
classification, printing, the terminal marker and the exit contract stay serial and in registration
order.**

3.1 **`scripts/lib/test-suite-lanes.sh`** — a data-only declaration module, sourced by
`test-all.sh` and by the lane census guard, modelled on `scripts/lib/test-relevance-paths.sh`
(which ADR-181 already established as the shape for per-suite declarations read by two consumers).

**A three-name lane vocabulary (`parallel` / `serial` / `serial-after`) was designed first and
cut**, because it cannot express the constraints the collision inventory actually has. `serial`
naturally reads as "gets its own slot", which still leaves `P-1` siblings in flight — and C1's
mutation battery fails on *any* change under `scripts/` or `.github/` during its window, so a slot
is not enough; it needs the pool drained. Worse, `serial-after:<label>` orders the declared consumer
behind the declared producer but does nothing about a *third* suite rebuilding `_site/` in between.
Ordering is not exclusion.

**What ships instead is a resource-token declaration — one mechanism, strictly more expressive.**
Each label declares a set of tokens plus an optional ordering edge:

```
lane_declare "<label>" resources="<tok> <tok> …" after="<label>" reason="<citation>"
```

Scheduling rule: two suites may not be in flight together if their token sets intersect. The token
`*` intersects everything, so it *is* the drain barrier — no new launch until it is reaped, and it
launches only once the pool is empty. `resources=""` is the fully independent case.

| Token | Meaning | Seed members |
|---|---|---|
| `*` | observes or mutates global state; requires a drained pool | C1 `scripts/cf-tunnel-liveness-gate-mutations`; C8's `/proc`-walking family |
| `artifact:_site` | writes or reads the Eleventy build output | C3's producer **and** consumer — both declare it, so a third writer is excluded too, which `serial-after` alone could not do |
| `repo:index` | runs a live-repo `git` command that rewrites `.git/index` | C2 |
| `lock:test-all` | spawns a real `scripts/test-all.sh` that would take the parent's advisory lock | C4's blocking subset |
| `cpu:pool` | carries its own internal `-P` | C6 `run-registered-suites.sh` and the 13 suites that sandbox-spawn it |
| `fs:node_modules_vite` | shares `apps/web-platform/node_modules/.vite` | C7's two vitest registrations |
| `deadline` | carries an internal `timeout` and is load-sensitive | the 37 measured `timeout`-bearing suites, pending Phase 1's H4 verdict |

`after="<label>"` is a separate, additive ordering edge for genuine producer/consumer sequencing; it
never substitutes for a shared token.

**Declarations are DERIVED first and hand-written only as overrides — otherwise Property 1 is
bought by nobody.** A table that starts empty against 434 registrations, with an unlisted label
defaulting to a drain barrier, ships a parallel mode that is *slower than serial*: ~420 suites each
demanding an empty pool, plus semaphore bookkeeping and per-suite captures. The classification work
that would fix that is a several-hundred-suite campaign this plan does not budget, so a
hand-declared table would deliver the mechanism and none of the property.

So `test-suite-lanes.sh` ships a **classifier** over the registered set plus a small override table:

| Derived signal (the grep IS the reason) | Token assigned |
|---|---|
| the suite's subtree took the advisory lock during Phase 0.4's run | `lock:test-all` |
| `git -C "$REPO_ROOT"` or `cp -a "$REPO_ROOT` in the suite body | `*` |
| a `timeout <n>` in the suite body | `deadline`, **only if Phase 1 attributes H4** |
| the registration's argv contains its own `-P`/`--max-pool-size`/`JOBS` | `cpu:pool` |
| the suite is unreadable, or the classifier errors | `*` — fail closed per suite, never per run |

Everything else derives **empty** — parallel. The override table is for what the classifier cannot
see (C3's `artifact:_site` pair, C7's shared vite cache, C8's `/proc` walkers) and every override
carries a hand-written `reason`. **How much this actually buys is a measured number, not a hope:**
Phase 0.4a's ratio is recomputed over the derived-parallel set, and if that set holds too little of
the wall clock the go/no-go fires exactly as it would have anyway.

The failure direction of a classifier miss is "raced", not "slow" — which is why Gate 1's fault
injection and Guard 1's token-intersection assertion are the backstop, and why the derivation is
conservative on every signal it can read. Every declaration carries a `reason` field citing the authority, and the
census guard rejects an empty reason — the machine-checkable exclusion shape #7076 recommends and
`scripts/lint-orphan-test-suites.sh` already uses. The seed set comes straight from the collision
inventory:

| Label | Declaration | Citation |
|---|---|---|
| `scripts/cf-tunnel-liveness-gate-mutations` | `resources="*"` | C1, C2 — live-worktree `TREE_BEFORE`/`TREE_AFTER` assertion, and a bare `git status` that rewrites `.git/index` |
| `plugins/soleur` (`scripts/test-all.sh:2561`) — the bun-test recursion | `resources="artifact:_site"` | C3 — coarse but correct: at least one suite in that batch can touch repo `_site/` under `SEO_AEO_SKIP_BUILD=1` |
| `blog-link-validation` (`:2562`) — **that is the registered label**, not the script path | `resources="artifact:_site"` (no `after=`) | C3 — it is the producer, so there is nothing to order it behind; the shared token is what excludes every other writer |
| `apps/web-platform/infra/run-registered-suites.sh` | `resources="cpu:pool lock:test-all"` | C6 |
| `apps/web-platform [repo-wide+component]`, `apps/web-platform [unit]` | `resources="fs:node_modules_vite"` | C7 |
| `scripts/orphan-process-reaper` (`:1850`), `scripts/orphan-process-reaper-mutations` (`:1861` — **plural**, and the label differs from the filename), `scripts/test-all-capacity-signal` | `resources="*"` | C8 — whole-box-sensitive |
| the blocking subset of the suites that spawn `scripts/test-all.sh` | `resources="lock:test-all"` | C4 — measured by Phase 0.5, not assumed |
| `scripts/md-to-mrkdwn` | `resources="deadline"` | #6496 — the single wall-clock **assertion** in the corpus |
| the 37 suites carrying an internal `timeout <n>` | `resources="deadline"` pending Phase 1's H4 verdict | deadline-sensitive population, measured |

Any lane assignment Phase 1 contradicts is corrected before Phase 3 ships; none of the above is
treated as settled by this plan.

3.2 **Dispatch/reap split inside `run_suite`.** In parallel mode `run_suite` does not execute `"$@"`
inline. It:
  - keeps `_shard_selects`, the `_ENUMERATE` arm, and the `suites=$((suites + 1))` increment exactly
    where they are, so population and shard totality are unchanged by construction;
  - evaluates the runtime ceiling at **dispatch** time, so `_ceiling_declined` accounting is
    unchanged;
  - launches `( exec "$@" ) >"$CAP/$idx.out" 2>"$CAP/$idx.err" &` behind a semaphore of `P` slots,
    recording `idx → (label, pid, start)`.

**The `exec` is load-bearing and is not style.** Measured on bash 5.3.15 in this worktree: a
backgrounded brace group keeps the **parent's** argv — `/proc/<pid>/cmdline` reads
`bash <parent-script>` — because the EXIT trap at `scripts/test-all.sh:1467` disables bash's
last-command exec optimisation. `( exec "$@" ) &` reads `sleep 1`. Without the `exec`, every worker
is indistinguishable from a whole `test-all.sh` **run** to `_tc_is_run_proc`
(`scripts/lib/test-contention.sh:273-283`), which matches `argv[0]=bash` plus any token whose
basename is `test-all.sh`. The self-pgid exclusion at `:413-427` suppresses that only for the run's
*own* scan, so a **sibling worktree** would see `J` phantom runs — inflating `[contention] siblings: N`,
`CAPACITY_CONTENDED reason=sibling_runs measured_siblings=N`, `bash scripts/test-all.sh --capacity`
(consumed by `grok-pre-push-gate.sh:115` and prescribed in `work/SKILL.md` and `ship/SKILL.md`), and
above all **ADR-196's refusal** at `scripts/test-all.sh:1326`, whose whole decision is that the
antecedent must be a condition the runner *measured*. That is an AP-021 violation no `resources=`
declaration can reach, because it happens outside the run. `$!` and `wait -n -p` both still work
through the subshell — verified in the same probe.

**stdout and stderr are captured SEPARATELY and replayed to their own fds.** Today `[ok]` and
`[skip]` go to stdout (`:959`, `:1023`) while `[FAIL]`, `[KILLED]`, `[TRIPWIRE]` and `[budget]` go to
stderr (`:988`, `:974`, `:985`, `:953`). A `2>&1` capture merges them, and replaying a merged stream
from the parent at the exact position the printer emits verdicts widens the marker-forgery channel
`main-health-monitor.yml:487` and `:580` already document from "in principle" to "positionally
indistinguishable" — which AC9's shape-filtered diff cannot see. Two files, two fds. Each suite gets
its **own** pair, never a shared open file description, per the PIPE_BUF learning cited at
`run-registered-suites.sh:376-386`.
**Rendering is drain-then-print, and the incremental cursor is deferred.** Each suite already
writes to its own `$CAP/$idx.out` and each `rc[idx]` is recorded, so a plain
`for idx in 0..n-1; do render "$idx"; done` **after the pool drains** produces byte-identical output
with no cursor and no three-loop interleave. An incremental printer cursor buys earlier output only
when suites finish near registration order — and if index 0 is the 14-minute registry battery it
prints nothing for 14 minutes either way. Phase 0.4's `sort -k2 -n -r | head -20` is the measurement
that decides whether the cursor is worth it; until it says so, drain-then-print.

**Liveness is bought separately and cheaply.** Drain-then-print withholds all result lines until the
run ends, and the payer is a developer holding a commit open, so the dispatcher emits an unanchored
`[run] <label> started` / `[run] <label> done (<ms>)` pair to **stderr** in completion order. These
are new line shapes, not re-spellings, so every `^\[FAIL\]` / `[ok]` / `[KILLED]` anchor is untouched
— and AC13's additive-lines carve-out is what keeps them legal.

**The collector uses the RESTRICTED form `wait -n -p pid -- "${live_pids[@]}"`, not a bare
`wait -n -p`.** A bare `wait -n` reaps *whichever* child of the shell finishes — including one the
scheduler did not start. `scripts/lib/test-contention.sh` spawns `_tc_wait_heartbeat … &` in
`test-all.sh`'s own shell; today it is reaped inside `tc_acquire`, so a bare form would be safe by
accident rather than by construction. Restricting the wait to the live worker set removes the
hazard. Three returns need branches, all measured: a pid the map does not contain (**refuse**, do
not guess); rc **127** with the pid variable **empty**, which means the job table was exhausted and
is *not* a suite's own `exit 127`; and a `128+N` return with the pid variable unset, which is the
parent-signalled case in 3.6b. Every call is `|| rc=$?`-guarded and the guard must not swallow the
127 case. For each index the renderer then runs the existing classification block verbatim: `echo "--- $label ---"`, replay the captured body, then the
unchanged `[ok]` / `[FAIL]` / `[KILLED]` / `[TRIPWIRE]` emission and the unchanged
`TEST_TIMING_LOG` row. `suite_exit_class` is untouched.

3.3 **Fields that are not attributable under concurrency are suppressed, not fabricated.**
`tmp_before` / `tmp_delta` is a **machine-global** tmpfs entry count (`tc_tmp_entry_count`,
`scripts/test-all.sh:892-895`, `:946-949`), so with another suite in flight it measures the machine,
not the suite. The field is emitted as `tmp_delta=unattributed` for any suite whose window
intersected another's, and keeps its numeric value for a barrier suite running with the pool
drained — where the measurement is still attributable and discarding it would lose a real signal. `_repo_last_suite` is a scalar naming "the suite
in flight" for the repo-write boundary; in parallel mode it becomes the **set** of in-flight labels
and the boundary's message names the set. Both are AP-021 obligations: a runner may not report a
number it did not measure.

3.4 **Width resolution.** A new `SOLEUR_TEST_JOBS` — deliberately **not** `JOBS`, which node-gyp
reads as `make -j` (`main-health-monitor.yml:301-305`) and which `run-registered-suites.sh:281`
already owns. Unset resolves to `min(nproc, floor(avail_mem_mb / per_suite_mem_budget_mb), HARD_CAP)`,
with the inputs printed.

**Where `per_suite_mem_budget_mb` comes from, and its fallback.** Phase 1's `peak_rss_kb`
distribution is measured over the **infra** runner's 122 derived suites — a different population from
the top level's 434 — so it cannot be the sole input. Phase 0.4's serial baseline therefore carries
the same per-suite peak-RSS sampler at the top level, and that is the budget's source. If neither
measurement exists (a fresh clone, or Phase 0.3 unavailable), `HARD_CAP` defaults to **2** with a
banner saying the width is a floor rather than a measurement.

**A SET value is validated and clamped, never trusted:** non-numeric, zero, negative or empty
**refuses with `exit 2`**, following the `TEST_GROUP` (`:564-570`) and `SCRIPTS_SHARD` (`:600`)
precedents; a value above the measured ceiling is clamped down with a banner, because Property 7 is
about the width that actually runs, not the width that was asked for. `SOLEUR_TEST_JOBS=1` is the
deterministic serial fallback and is the value under `CI`.

**The outer width propagates as a BUDGET the child subtracts from, not as a width the child
re-reads.** A `cpu:pool` suite consumes the whole budget (its token drains the pool anyway) and sets
its own inner `JOBS` from what it was given. Exporting a width would let the child re-read it and
multiply — C6's `J × 6`. The population that needs it is the **measured** spawner set — one suite
plus the direct registration — not the thirteen that merely name the runner.

3.5 **Automatic fallback to serial: bounded, announced, with a stated precedence.** The conditions
**overlap** — `CI` implies `SOLEUR_TEST_JOBS=1`, which implies a resolved width of 1 — so the banner
names the **first** match in this order, and Guard 1's M8 row asserts that exact string:

1. `CI` is set — CI shards across separate runners and does not need this mechanism.
2. bash < 5.1 (`BASH_VERSINFO`) — no `wait -n -p`.
3. `SOLEUR_TEST_JOBS=1` explicitly.
4. **The cross-worktree advisory lock was not actually taken.** `tc_acquire` returns 0 *without
   serializing* on `SOLEUR_DISABLE_SESSION_STATE=1`, on a missing `session-state.sh`
   (`LOCK_UNAVAILABLE`), on a missing `flock(1)`, and it **proceeds** after
   `LOCK_CONTENDED_PROCEEDING`; `scripts/test-all.sh:862` also documents a silent noop stub
   (`tc_acquire() { :; }`) when the lib cannot be sourced. Going wide with no cross-worktree
   serialization is the one combination that turns a local optimisation into a cross-worktree
   corruption surface, so the runner **reads back whether the lock was taken** and falls back if it
   was not. The Cut List's "the lock exists, is tuned, and is held by the single parent process"
   holds only on the path where `tc_acquire` actually locked; this condition is what makes relying
   on it safe.
5. The declaration table cannot be sourced.
6. The resolved width computes to 1.

The banner is a fact about the runner's own state, so it satisfies AP-021 without a measurement
claim.

3.6 **Tests, written before the scheduler.**
  - `scripts/test-all-parallel-scheduler.test.sh` — population parity, ordering, exit contract,
    signal shape, decline preservation.
  - `scripts/lib/test-suite-lanes.test.sh` — the lane census (auto-registers via the existing
    `scripts/lib/*.test.sh` glob).
Each carries an ADR-193-conformant floor and an accounting-conservation check, with conservation
ordered first.

3.7 **Degenerate states, decided here rather than discovered mid-build.** Each row names the state,
the behaviour, and why.

| State | Behaviour | Why |
|---|---|---|
| The runtime ceiling trips with N workers in flight | Stop dispatching, **drain** the in-flight set to completion, then decline every not-yet-dispatched registration into `_ceiling_declined`. Workers are never killed. | The lock fd is inherited by children (`scripts/test-all.sh:863-870`), so tearing down descendants would need a process-group signal the runner must not send. Draining is the same reasoning the existing early-`return` encodes, extended to a set. |
| `SIGINT` reaches the parent | Children share the parent's process group, so they receive it too. The parent stops dispatching, reaps whatever rcs it can observe, reports every unreaped index as **UNACCOUNTED**, and exits 1. | `unmeasured outranks terminated` (ADR-187's ladder). Reporting an interrupted run as "terminated" would claim a measurement the runner did not make. |
| A worker is OOM-killed | `wait -n -p` returns 137; the existing classifier renders `[KILLED]`; the run exits 3 if nothing failed. | Correct by construction — the rc is directly observed, which is the only shape ADR-187 §2 permits. |
| `tc_acquire` times out and fires `LOCK_CONTENDED_PROCEEDING` | **Resolve the width to 1 for this run** and say so in the banner. | A contended run is precisely when oversubscription hurts, and the lock has already told the runner a sibling is holding capacity. Proceeding at full width would be the runner ignoring its own measurement. |
| The parent is SIGKILLed | Untrappable. Where a serial run orphaned **one** descendant holding the inherited lock fd — ADR-133's 2026-09-06 addendum exists because one such orphan held it for 1d22h — a parallel run orphans **J**. ADR-225 records the decision on whether workers close the inherited lock fd before `exec` (note that `exec` alone preserves it). |
| The parent exits while children are live | Forbidden. The EXIT trap waits for the job table to drain before running `_repo_boundary_exit_note`. | Orphaned children hold the inherited lock fd, so an early exit releases nothing and leaves the next run blocked for up to `TC_LOCK_TIMEOUT`. |
| A capture file cannot be created | Fall back to serial for that suite, with a banner. | A suite whose output cannot be captured cannot be attributed, and an unattributable failure is worse than a slow one. |
| `--enumerate` disagrees with the executed set at the end of the run | Report the difference as UNACCOUNTED and exit 1, before the terminal marker. | This is the in-run form of AC12, and it is the only thing standing between a dropped worker and a green marker. |

### Phase 4 — Benchmark and the default-mode decision

4.1 **Benchmark harness** `scripts/test-all-parallel-benchmark.sh` — **two arms, not eight.** The
only decision riding on it is the wall-clock threshold, and that is serial-versus-`P_measured`
**inside the same constrained scope**; a four-width curve across two runner classes is ~4-6 hours of
compute no decision reads. Both arms pin `TC_RUNTIME_CEILING_S` beyond reach and assert
`_ceiling_declined == 0` before the comparison is read. Output lands in `acceptance-evidence.md`.

4.2 **Critical-path report.** The benchmark prints `total_suite_ms`, `longest_suite_ms`, and the
implied ceiling `total ÷ longest`, so a reader can see that a disappointing speedup is Amdahl and
not a scheduler defect. This is the number Research Insights records as unmeasured.

4.3 **One correctness gate, and a stability observation that is not a gate.**

**A repeat-run experiment on a green tree cannot detect the failure this design introduces.** On an
unchanged green tree every rc is 0, so "identical verdict sets" is satisfied by *any* index→rc
mapping, including one that attributes a suite's rc to its neighbour. Misattribution is invisible to
the experiment meant to license the scheduler.

**The gate is fault injection, and it is Guard 1 parameterised over width — not a second artifact.**
Guard 1 already plants an `exit 1`, a `kill -TERM $$`, an `exit 97`, a decline and an `exit 0` at
known indices and asserts the full triple **label ↔ rc ↔ rendered class** plus the run's exit code
(`143 → [KILLED] → exit 3` with nothing failed; `exit 1` when a failure is also present). Phase 4
wraps that fixture loop in `for w in 1 "$P_measured"`. A separate "Gate 1" script would have been
Guard 1 in a different file.

**Repeat runs are recorded, not gated on.** #7376's observed rate is 3 of 7 ≈ 0.43; five clean runs
bound the true per-run rate only at roughly `p < 0.45` (95%), and a 5%-per-run flake — one a
developer meets about weekly — passes five clean runs **77%** of the time. Bounding `p < 0.05` needs
~59 runs. A five-run gate that the plan's own arithmetic shows cannot detect a weekly flake is not
evidence, so it is not a gate: three repeat runs are recorded in `acceptance-evidence.md` as an
observation, with the power calculation beside them, and nothing is licensed by them.

> **Parallel ships, and the default is the measured choice, iff** at one pinned commit with a clean
> `git status --porcelain`:
> (a) the fault-injection gate passes at width 1 and at `P_measured`;
> (b) the serial arm is **green**, or every failure it carries is confirmed pre-existing and named
>     per `wg-when-tests-fail-and-are-confirmed-pre` — two arms agreeing on a broken baseline is not
>     evidence that the scheduler is safe;
> (c) `_ceiling_declined == 0` on both arms, so the two are comparable at all (3.6d);
> (d) the wall-clock reduction is ≥ 30%, serial comparand measured **inside the same constrained
>     scope** as the parallel arm;
> (e) Phase 1 did **not** terminate with every hypothesis UNKNOWN **and** Phase 0.5's blocking-subset
>     question was answered. UNKNOWN is a permitted terminal state for a *diagnosis*; it is not a
>     permitted input to flipping the default on the mechanism whose first instance caused #7376.
>     It does **not** block shipping the scheduler opt-in, which stands on (a)-(d) alone.
>
> "Verdict set" means, precisely: the ordered list of `(label, rendered class)` pairs plus the
> terminal marker's two integers plus the run's exit code. Order is included deliberately — excluding
> it would let Guard 1's M2 mutation (reap in completion order) pass.
>
> Otherwise the default stays serial, parallel remains opt-in, and ADR-225 records which condition
> failed with its measured value.

**This is not the shape #7454 rejected.** It rejected a *bare* opt-in flag — one with no safety case,
that nobody could responsibly enable. Here the flag arrives after a diagnosis, the fixes that
diagnosis attributes, a fault-injection correctness gate and a measured width, with named adopters
(`lefthook.yml:332`, `/ship` Phase 4) able to enable it the day it lands.

### Phase 5 — ADR, documentation, and issue hygiene

5.1 **ADR-225** (ordinal provisional — re-derive against freshly fetched `origin/*` immediately
before merge).

5.2 **Runbook** `knowledge-base/engineering/operations/runbooks/local-gate-parallel-mode.md` —
when to use local parallel mode versus CI shards, the serial fallback, how to read the banner, and
the declaration table's meaning. The CI-shard side is a statement of existing fact: `ci.yml` already shards
by `TEST_GROUP` and `SCRIPTS_SHARD` across separate runners, where there is no shared `/tmp` and no
co-location race — which is why CI does not need this mechanism and local does.

5.4 **The default flip needs no soak machinery, and the one first designed was green by
construction.** A 20-day sweeper-driven probe was specified and **cut**: the default is serial during
the soak and `CI` forces serial (T11), so the probe would have compared serial to serial twenty
times and could never observe a divergence — and a GitHub-Actions sweeper cannot see local full-gate
runs at all. The rollback for a wrong default is one word (`SOLEUR_TEST_JOBS=1`), so the flip ships
on Phase 4's measurement and the residual risk is carried by the fallback rather than by
governance. **Re-evaluation trigger, since every other deferral here has one:** revisit the width
and the default when `--enumerate all` moves by more than 10% from the count recorded in ADR-225, or
when a parallel run's verdict is reported as diverging from a serial re-run — which is an
issue-filing event, never a silent retry.

5.3 **Issue hygiene.** Post the Phase 1 diagnosis link as a comment on #7376 and #7432. Close
neither. Add a note to #7454 Item 1 recording that its re-evaluation trigger fired and what the
measurement said. Close only #8231.

## Files to Create

Four files, down from fifteen. Every cut is recorded in `## Alternative Approaches Considered`.

| Path | Purpose | Registration |
|---|---|---|
| `scripts/lib/test-suite-lanes.sh` | the classifier plus its override table, sourced by `test-all.sh` and by `lint-orphan-test-suites.sh` | sourced, not run |
| `scripts/test-all-parallel-scheduler.test.sh` | the one new guard: parity, order, exit contract, token intersection, barrier drain, fault injection over width | explicit `run_suite` line — repo-root `scripts/*.test.sh` is **not** globbed |
| `knowledge-base/engineering/architecture/decisions/ADR-225-<slug>.md` | the decision record | — |
| `knowledge-base/engineering/operations/runbooks/local-gate-parallel-mode.md` | local parallel vs CI shards, the serial fallback, reading the banner, what the tokens mean | — |

Plus the branch's spec artifacts: `spec.md`, `tasks.md`, `diagnosis.md` (Phase 1's verdicts and the
recorded reproduction loop) and `acceptance-evidence.md`, all under
`knowledge-base/project/specs/feat-one-shot-8231-parallel-test-all/`.

## Files to Edit

| Path | Change | Verified to exist |
|---|---|---|
| `scripts/test-all.sh` | guard the `bun --version` substitution (`:318-325`); dispatch/reap split in `run_suite`; width resolution and fallback precedence; source the classifier; `tmp_delta` and `_repo_last_suite` honesty under concurrency; one new `run_suite` registration | yes, 3045 lines |
| `scripts/lint-orphan-test-suites.sh` | host the declaration census beside the existing `RELEVANCE_ARRAYS` one | yes |
| `scripts/lint-orphan-test-suites.test.sh` | mutation rows for the new census | yes |
| `apps/web-platform/infra/run-registered-suites.sh` | three new `SUITE_TRACE` fields; any Phase 2 fix the diagnosis attributes | yes, 655 lines |
| `apps/web-platform/infra/run-registered-suites.test.sh` | deterministic mutation rows for whatever Phase 2 changes | yes |
| `scripts/lib/test-contention.sh` | expose the `fd_used` sampler beside the existing `tc_avail_mb` (`:118`) and `tc_used_bytes` | yes |
| `scripts/lib/repo-write-boundary.sh` + `scripts/lib/repo-write-boundary.test.sh` | `_repo_last_suite` becomes a set and the boundary message names it; the suite **extracts the boundary epilogue out of `test-all.sh` by content anchor** (`:1114-1129`) and hard-fails if the shape moves | yes |
| `scripts/test-all-killed-classification.test.sh` | it **byte-diffs the runner's tail against `origin/main:scripts/test-all.sh`** from the terminal marker onward (`:490-506`), and pins `^\[FAIL\] assertfail \([0-9]+ms\)$`, `^\[ok\] okfixture \([0-9]+ms\)$` and a stray-marker count. Nothing may be appended after `:2990` | yes |
| `.github/workflows/ci.yml` | its K-shard balance derivation attributes each `--- <label> ---` mark's span to the **next** mark (`:961-965`). The printer emits that header at *reap* time, so the method is invalid under parallel — today CI is safe only because 3.5 forces serial there. Record the coupling in the comment so the next person to enable it in CI sees it | yes |
| `scripts/test-contention.test.sh` | rows for the new sampler | yes |
| `knowledge-base/INDEX.md` | regenerated by `scripts/generate-kb-index.sh` | yes |
| `CHANGELOG.md` | entry at `/ship` | yes |

**Not edited, deliberately:** `.github/workflows/main-health-monitor.yml`,
`plugins/soleur/test/main-health-monitor-workflow.test.sh`, `lefthook.yml`. See the #7432
disposition in Phase 2 and Non-Goals below.

**Glob verification.** `scripts/lib/*.test.sh` matches 9 tracked files today, so
`scripts/lib/test-suite-lanes.test.sh` auto-registers. `scripts/*.test.sh` is **not** in
`SUITE_GLOBS`, which is why the three new repo-root suites carry explicit `run_suite` lines —
without them `scripts/lint-orphan-test-suites.sh` reds.

## Acceptance Criteria

Twenty criteria, down from forty-five. The cut ones were either notes ("paste this output into a
file", which cannot fail meaningfully), restatements of the repo's standing CI gates, or
"the existing tests still pass" — which is what the existing tests are for. What remains is the
contract a reviewer has to check.

**Go/no-go — these can cancel the work**

1. `acceptance-evidence.md` records `total_suite_ms ÷ longest_suite_ms` over the post-decline
   population **and** over the derived-parallel set, from Phase 0.4's `TEST_TIMING_LOG`. If either is
   below 2×, the PR stops at Phase 0 and says so — that is a passing outcome of this criterion.
2. `acceptance-evidence.md` names the blocking subset **measured** from Phase 0.4's `tc_acquire`
   caller log (never from a grep), and that subset's share of the serial wall clock. A majority share
   is the no-go branch.

**The enumeration contract**

3. `bash scripts/test-all.sh --enumerate all` exits 0 and emits a positive count on a host where a
   `mise` bun shim is on PATH without a pinned version. Today it exits 1 with zero records.
4. Every consumer of that contract fails closed on **both** rc and a zero count, in the shape of
   `scripts/lint-orphan-test-suites.sh:229-232`. No anti-vacuity floor in this change is written as
   `derived >= derived`; each is an absolute non-zero minimum.

**Diagnosis**

5. `diagnosis.md` carries one row per hypothesis H2/H4/H5 (H1 carries its prior refutation and its
   source), each with **either** the measured field value that decided it **or** the literal
   `UNKNOWN`. No row reads CONFIRMED or REFUTED without a field value beside it.
6. `acceptance-evidence.md` carries the raw K-run table, K ≥ 7.
7. `wrote_outside_sandbox` is computed by an mtime sweep over a declared root set that **includes
   gitignored build outputs**, and by no `git status` call; if a `git` call is used anywhere in the
   instrument it carries `--no-optional-locks`. It records `attributed_to=<set in flight>`, never a
   bare per-suite count, and it carries a retirement trigger naming when it comes out.
7b. The `SUITE_TRACE` record is emitted by the **parent** only, asserted structurally rather than by
   a count: the shim body is extracted between its `xargs -P "$JOBS" -I{} bash -c '` opener and its
   closing `' _ {}` and contains no emission. A `grep -c` over the whole file cannot establish
   *where* an occurrence is.
7c. `peak_rss_kb` is read from the **suite child's** `/proc/<pid>/status` `VmHWM`, never from the
   shim's own `/proc/self/status` — a parent's high-water does not accumulate a child's.

**The scheduler**

8. Population parity is asserted against `--enumerate`, not a literal: the guard derives its expected
   set by invoking the runner and compares it to the labels the parallel run emitted, equal for every
   one of the five groups.
9. The per-suite result lines (`--- <label> ---`, `[ok]`, `[FAIL]`, `[KILLED]`, `[TRIPWIRE]`,
   `[skip]`), the breakdown line and the terminal marker are byte-identical between a serial and a
   parallel run of the same fixture group, with elapsed-ms masked. The parallel run's extra lines are
   asserted **additive**: every serial line is present, and every extra matches one of the two
   declared new shapes (`[parallel]` banner, `[run]` liveness pair).
9b. `[budget]` is a **fourth** extra shape and is expected: `scripts/test-all.sh:951-953` emits it whenever `elapsed_ms` exceeds a declared budget, and concurrency inflates `elapsed_ms` — that is H4's premise. The parallel arm may emit `[budget]` lines the serial arm did not, on exactly the heavy budgeted suites. AC9's additive set is therefore `[parallel]`, the `[run]` pair, and `[budget]`; `skip_suite`'s two-line rerun block (`:1023-1025`) is part of the `[skip]` shape, not an extra.
10. **The fault-injection triple.** A synthesized registration set with planted outcomes at known
    indices — at least one `exit 1`, one `kill -TERM $$`, one `exit 97`, one decline and one `exit 0`
    — asserts `label ↔ rc ↔ rendered class` for every index, plus `143 → [KILLED] → exit 3` with
    nothing failed and `exit 1` when a failure is also present. Run at width 1 and at `P_measured`.
11. A declined suite still increments both `suites` and `skipped` under parallel mode, and the
    terminal marker reads `N-k/N`.
12. Two suites whose token sets intersect are never observed in flight together: the transcript's
    per-suite windows are intersected pairwise and every intersecting pair has disjoint tokens.
13. A suite declaring `resources="*"` is observed with a **drained** pool — no other suite's window
    intersects its own in either direction — and the assertion reads the child's own exec/exit, not
    only the parent's dispatch/reap stamps, so a leaked grandchild is visible.
14. `SOLEUR_TEST_JOBS` refuses a non-numeric, zero, negative or empty value with `exit 2`, and clamps
    a value above the measured ceiling with a banner.
15. Each of the six serial-fallback conditions drives the serial path and the banner names the
    **first** matching condition in the declared precedence order; a run whose `tc_acquire` did not
    actually lock falls back rather than going wide.
15b. The census reports `derived`, `overridden` and `unreadable` populations with `unreadable == 0`,
   and prints `barriers=N/M`, which the width banner repeats on every run. It does **not** assert
   `unclassified == 0`: given a default, no label can land in a bucket the default drains, so that
   assertion is a tautology. The barrier population is the number that decays silently, so it is the
   one made visible.
16. A `TEST_TIMING_LOG` row for a suite whose window intersected another's carries
    `tmp_delta=unattributed`; a barrier suite's row may carry a number.
17. The runner never sets a bare `JOBS` for its own width and never *exports a width* to a child:
   `cpu:pool` suites receive a **budget** they subtract from (Phase 3.4), which is the opposite of
   the "export `JOBS=1`" the first draft of this criterion demanded — the two could not both ship.
   `grep -cE '^[[:space:]]*JOBS=' scripts/test-all.sh` is `0` and
    `grep -cE 'SOLEUR_TEST_JOBS' scripts/test-all.sh` is positive — anchored patterns, because
    `SOLEUR_TEST_JOBS` contains `JOBS` as a substring and a bare count conflates exactly the two
    things this distinguishes.

**The default**

18. The mode shipped in `scripts/test-all.sh` matches Phase 4.3's conditions (a)-(e), and ADR-225
    records the measured value of each — including which condition failed where one did.

**Record and scope**

19. `ADR-225-<slug>.md` exists with `status: active`, a Decision section, and an Alternatives
    Considered section naming the cut mechanisms; the runbook exists; the repo's standing gates
    (`lint-diagnosis-claims`, `lint-orphan-test-suites`, `guard-vacuity-floor`, `c4-count-parity`,
    `markdown-lint`) and a `TEST_GROUP=all` run are green on the final tree.
20. #7376, #7432, #7454, #7554, #7076, #8045 and #6496 are all still **open** after merge; only #8231
    closes. Verified with `gh issue view <N> --json state` for each.


## Guard Contract

Two guards, down from three. The declaration census moved into an existing linter rather than
becoming a third file, and the cross-worktree contention suite was cut for re-testing an unchanged
mechanism it could not have passed in CI. Both guards follow ADR-193: floors report with
`printf >&2` + `exit 1` directly, the case counter increments at the call site and never inside
`$( )`, and the accounting-conservation check (`passes + fails == cases`) runs **before** the floor.
**Every floor is an absolute non-zero minimum**, never `derived >= derived` — on this host the
derivation returns 0 today (see Research Insights), which would make a derived floor vacuous.

### Guard 1 — `scripts/test-all-parallel-scheduler.test.sh`

**Property.** Under parallel scheduling: the set of suites executed, the order their verdicts print
in, and the exit code the run produces are identical to serial on the same tree; no two suites whose
declared token sets intersect are ever in flight together; and every rc is attributed to the
registration that produced it.

**Assembly.** Not "the suites listed here" — a snapshot. The quantified set is *every registration
reaching the `run_suite` / `skip_suite` chokepoints* (`scripts/test-all.sh:852` and `:1013`; there
are exactly two and the guard names both), obtained at run time from
`bash scripts/test-all.sh --enumerate <group>` over all five groups, **with a fail-closed rc-and-count
check**. The exit-code assembly is **derived, not listed** —
`grep -nE '^[[:space:]]*exit [0-9]' scripts/test-all.sh` returns **20** sites today, and a
hand-list is the snapshot this very paragraph forbids two sentences earlier. (The first draft
listed nine, miscounted the `:3035-3045` block as four when it holds three, cited `:816` for an
`exit 2` that is at `:817`, and omitted `:513`, `:530`, `:539`, `:605`, `:355`, `:376`, `:387`,
`:98`, `:159` and the enumerate-mode terminator at `:2796` — the one the scheduler's own parity
work runs straight through.) The guard enumerates them and asserts each is still reachable with its
documented value. The intersection assembly is every
*pair* of labels whose declared tokens overlap, derived from `--enumerate` ∩ the declaration table.

**Mutation matrix** (each row MUST drive the guard RED):

| # | Mutation | Why it must red |
|---|---|---|
| M1 | Drop one suite from the dispatch queue after it was counted in `suites` | population parity breaks — the "green over a battery that never ran" class |
| M2 | Render in completion order instead of registration order | verdict-line order diverges from serial; excluded-from-comparison order is why 4.3 defines "verdict set" to include it |
| M3 | Replace the `wait -n -p` rc capture with a boolean `if ! …` test | signal shape flattens; `[KILLED]` degrades to `[FAIL]` and exit 3 to exit 1 (ADR-177) |
| M4 | **Permute the pid→index map by one** so rc `i` renders against label `i+1` | the misattribution a green-tree repeat run cannot see; only the fault-injection triple catches it |
| M5 | **Add a second member after a compliant first** — stage two barrier suites and drain for only the first; and separately two token-sharing suites and exclude only the first pair | a check that stops at the first member is itself the defect class |
| M6 | **Mutate the guard's own dispatch**: iterate zero groups, or let the enumerate call return zero records without failing | a guard reporting "0 checked" and exiting 0 is vacuous; this is the live defect on this host |
| M7 | **Reorder** the `suites=$((suites + 1))` increment to after dispatch rather than at entry | a lifetime property: the count must be right *while* suites are in flight. A delete-only row reds every arm; moving it reds only an arm reading the counter mid-run, so the guard carries one case that reads inside the dispatch window |
| M8 | Make the serial-fallback condition always false; and separately reorder the precedence list | AC15 — bash < 5.1 would take the parallel path, and an overlapping condition would name the wrong banner |
| M9 | Make `*` intersect nothing | the barrier is `*`; a barrier that intersects nothing is not one |
| M10 | Emit a numeric `tmp_delta` for a suite whose window intersected another's | AC16's honesty property — a number that was not measured |

**Harness rows** (mutations of the SUITE, not the system under test):

| # | Mutation | Expected |
|---|---|---|
| H1 | Neuter `fail()` to a no-op | the conservation check fires **first** and says "a verdict was discarded", not "assertions were removed" |
| H2 | Remove one call-site `cases` increment | conservation fires the other way and names a harness bug |
| H3 | **Must-PASS non-canonical input**: a fixture group whose registration order differs from the canonical one, containing one declined suite and one suite with two tokens | passes — the contract permits any registration order, any decline count and any token arity; a guard that only accepts the canonical fixture is a `diff` against that fixture |
| H4 | **The arm's own mode.** Every parallel arm runs its sandboxed runner under `env -u CI` (the precedent is `scripts/orphan-process-reaper.test.sh:216`) and asserts the arm's transcript carries the `[parallel]` banner. If it carries the CI serial-fallback banner instead, **fail closed**. Without this row every mutation above exercises the serial path in CI — where the guard is the only thing blocking a merge — and the parallel path has no CI coverage at all |

**Anchor.** Guard 1 compares two *live* derivations — enumerate output versus executed labels — with
no stored snapshot a single diff could weaken alongside the thing it protects. Its one stored value
is the absolute floor, which is a lower bound on its own dispatch, not a description of the tree.

### Guard 2 — the declaration census, inside `scripts/lint-orphan-test-suites.sh`

**Property.** Every label the registration source emits resolves to a token set; the classifier's
verdict and the override table agree or the override says why; no declaration names a label the
runner does not emit; and a suite that takes the advisory lock carries `lock:test-all`.

**Assembly.** A census over `SUITE_REGISTRATION ∪ SUITE_COMMAND_DECLINED` from
`--enumerate all` run with `SOLEUR_TEST_FORCE_ALL=1` — **both** record types and the maximal
population, because several registrations are conditional (`:2604`, `:2518`) and a diff-dependent
population would make a stale-declaration check red on clean trees. Three buckets: `derived`,
`overridden`, `unreadable`; `unreadable` is red. `MIN_CASES` is an absolute non-zero minimum.

**Mutation matrix:**

| # | Mutation | Why it must red |
|---|---|---|
| M1 | Add an override naming a label `--enumerate` does not emit | stale declaration; `declared − emitted` must be empty. This is also what catches a declaration keyed on a file path rather than the label (`blog-link-validation`, `…-mutations`) |
| M2 | **Add a new registration the table has never seen** | the classifier must read it and the census must count it, never silently skip it — the row that makes this a census rather than a pin on the names this plan listed |
| M3 | Give an override an empty `reason` | fail closed on an empty reason (#7076's machine-checkable exclusion shape) |
| M4 | Make the classifier return "empty tokens" for a suite whose body contains `git -C "$REPO_ROOT"` | the derivation is conservative by contract; a signal it can read and ignores is the defect |
| M5 | **Guard's own dispatch**: make the census iterate an empty population and exit 0 | the absolute floor must fire — and on this host that is not hypothetical |
| M6 | Remove `lock:test-all` from a suite Phase 0.4's caller log named | the C4 deadlock class has a machine check, not a prose promise |

**Harness rows:** H1 neutered `fail()` → conservation first. H2 remove a call-site `cases`
increment → conservation fires the other way. H3 **must-PASS non-canonical**: a table in which a
suite carries two tokens and an `after=` edge, and another carries a token no seed member uses —
permitted, because the contract bounds readability and agreement, not the token vocabulary.

**Anchor.** The census compares the classifier's live derivation against the override table, and the
`lock:test-all` half against Phase 0.4's measured caller log — a value produced by a different
mechanism (the lock itself) than the one it checks. A count ratchet over the parallel population was
specified and **cut**: set identity already implies the cardinality bound, and unlike
`lint-diagnosis-claims.highwater` — whose population is a repo-wide grep invisible in a diff — this
population *is* a declaration table, so every widening is already a reviewable line.


## Observability

```yaml
liveness_signal:
  what: "the terminal marker `=== N/M suites passed ===` on stdout, plus the `[parallel]` banner
         naming the resolved width and the inputs it was resolved from"
  cadence: "once per `scripts/test-all.sh` invocation — pre-commit via lefthook.yml:332,
            /ship Phase 4, grok-pre-push-gate.sh, and main-health-monitor.yml every six hours"
  alert_target: "main-health-monitor.yml files a P1 `ci/main-broken` issue when the marker is
                 absent or the exit code is non-zero on main"
  configured_in: ".github/workflows/main-health-monitor.yml (steps `tests` and `infra`);
                  lefthook.yml:311-332"
error_reporting:
  destination: "the runner's own stderr, and the GitHub issue main-health-monitor files. There is
                no Sentry surface: this is a local shell orchestrator with no network egress and no
                SDK. Observability layer is the CI job transcript (layer 7 equivalent for a
                self-hosted CLI surface), not an APM."
  fail_loud: "yes — an unrecognized suite class already fails CLOSED at scripts/test-all.sh:926,
              counting the suite FAILED and saying so; the parallel path adds no new arm that can
              swallow a class"
failure_modes:
  - mode: "a suite is dispatched but never reaped (worker lost)"
    detection: "population parity between the reaped label set and `--enumerate` output, asserted
                in-run before the marker is printed"
    alert_route: "the run fails closed with an UNACCOUNTED count in the breakdown line, mirroring
                  run-registered-suites.sh:552-559, and exits 1 — `unmeasured outranks terminated`
                  per ADR-187's three-way ladder"
  - mode: "a suite reds only because a neighbour interfered"
    detection: "the failing suite's verdict line is accompanied by the concurrent set observed at
                its start and end — an in-surface fact the parent measured, never an inference
                about cause"
    alert_route: "same `[FAIL]` line as today, so every existing anchor still matches; the
                  concurrent set is an additional line, not a re-spelling"
  - mode: "the pool oversubscribes and the host swaps"
    detection: "the width-resolution banner prints `nproc`, `avail_mem_mb` and the per-suite budget
                it divided by; tc_capacity_line already reports headroom"
    alert_route: "LOW_TMP_HEADROOM / the capacity banner, both existing surfaces"
  - mode: "the parallel path is silently taken on a runner that cannot support it"
    detection: "the serial-fallback banner names the first matching condition; its absence under a
                condition that should have fired is asserted by Guard 1's M8 row"
    alert_route: "run transcript; Guard 1 reds in CI"
  - mode: "a worker is OOM-killed because the scheduler chose too wide"
    detection: "rc 137 observed directly by `wait -n -p`, rendered `[KILLED]` per ADR-177, alongside
                the width banner that records nproc, avail_mem_mb and the per-suite budget the width
                was divided from"
    alert_route: "exit 3 (UNRESOLVED). The banner is what stops a scheduler-caused kill reading as a
                  suite defect — the runner still does not name a cause it did not measure, but it
                  does print the inputs to the choice that preceded it"
  - mode: "the PARENT is OOM-killed"
    detection: "no terminal marker and rc 137. `scripts/test-all.sh:1426` already records that bash
                cannot trap SIGKILL, so this state is indistinguishable from the rc-4 refusal by
                marker-absence alone — the exit code is what separates them, and the monitor's filer
                must read it"
    alert_route: "main-health-monitor's P1 `ci/main-broken` path; the run leaves orphaned workers
                  holding the inherited lock fd, which the next run reports as LOCK_CONTENDED"
logs:
  where: "run transcript on stdout/stderr; per-suite captures under a run-scoped mktemp root that
          the EXIT trap removes unless SOLEUR_KEEP_LOGDIR is set; per-suite rows in TEST_TIMING_LOG
          when that variable is set (CI sets it at .github/workflows/ci.yml:1247)"
  retention: "the run's lifetime locally; the GitHub Actions log retention window in CI"
discoverability_test:
  command: "bash scripts/test-all.sh --enumerate all | grep -c '^SUITE_REGISTRATION'"
  expected_output: "exit 0 and a POSITIVE integer that equals the sum of the four per-group
                    enumerate counts. The absolute value is deliberately NOT pinned here — it was 434
                    when this was written and the population grew 291 -> 434 in five weeks, so a
                    pinned number is the decay this plan criticises elsewhere. Zero, or a non-zero
                    exit, means the registration source is unreadable, which is the one condition
                    under which every population claim in this work is void; as shipped today that
                    is the live state on a host carrying an unpinned mise bun shim."
```

## Architecture Decision (ADR/C4)

This plan changes the execution model of the repository's single load-bearing local gate and adds a
per-suite taxonomy every future suite author must satisfy. A future engineer reading only the
existing ADRs would be misled about what `=== N/M suites passed ===` now means, so the record is a
deliverable of this plan and not a follow-up.

### ADR

**ADR-225 — "The local gate may execute suites concurrently, and concurrency is a declared per-suite
lane."** Ordinal derived across all 86 `refs/remotes/origin` refs this session (max on `main` is
ADR-223; ADR-224 is claimed on a pushed branch), and is **provisional** — re-derive against a
freshly fetched `origin/*` immediately before merge, and if it moves, sweep the whole feature's
artifact set with `grep -rn 'ADR-225' knowledge-base/project/{plans,specs}/` in the same edit so the
plan, tasks and any AC naming the ordinal move with the file.

Decision content:

1. Only suite-body execution is concurrent. Accounting, classification, printing, the terminal
   marker and the exit contract stay serial and in registration order. ADR-177's taxonomy and
   ADR-181's counted declines are inherited unchanged, not re-derived.
2. Per-child rc is obtained with `wait -n -p` — a directly observed value — never through a
   file-borne sideband. This is ADR-187 §2 satisfied by construction rather than by discipline, and
   it is why the #7554 class cannot arise at this layer.
3. Concurrency eligibility is a **resource-token set derived from the suite's own source**, with a
   hand override table for what the derivation cannot read and a fail-closed `*` for a suite it
   cannot read at all. Censused
   against the derived registration population.
4. Per-child rc is read from `wait -n -p`'s output **variable**, not from its return value alone —
   a bare return is `128+N` when the *parent* is signalled, with no child reaped, and re-emitting
   that as a suite's signal shape is exactly ADR-187 §2's forbidden mimicry reached by construction.
5. The default mode is whatever Phase 4's pre-registered conditions license, and the measured value
   of each is recorded here — including which condition failed where one did.

**Frontmatter: `amends: [ADR-133, ADR-177, ADR-181]`**, and the relationship is stated precisely
because the first draft got it wrong (it cited "Decision 1 is the ordering this plan follows", which
is following a decision, not amending one):

- **ADR-133 Decision 3** reserved *one full gate's worth* of machine-global capacity per
  acquisition; a run at width `J` reserves `J` gates' worth under the same acquisition. That is a
  change to what the mutex protects. ADR-133 has an established **append-only dated-addendum**
  convention for changes to its own decisions, so that half lands as a dated addendum in ADR-133
  itself, with ADR-225 carrying the genuinely new content.
- **ADR-177 Decision 1** owns the marker taxonomy; this work adds an **UNACCOUNTED** outcome to the
  top-level runner (measured: `grep -c UNACCOUNTED scripts/test-all.sh` → **0** today), so the class
  needs a rendered marker and a place in the ladder, not an unnamed integer.
- **ADR-181 Decision 1** owns the breakdown line that UNACCOUNTED must appear in.

**Relates to** ADR-183, ADR-187, ADR-193, ADR-166 and ADR-196.

### C4 views

**No C4 impact.** All three model files were read in full —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` (785 / 96 / 54
lines) — not grepped for the feature's own noun. The enumeration checked:

- **External human actors:** none added or changed. The change is invoked by the same operator and
  the same agent sessions already modelled; `model.c4:71` (untrusted contributor) and `:324` (the
  operator workstation) are unaffected because this work adds no new execution of contributor code
  and no new sandbox boundary.
- **External systems / vendors:** none. No new inbound webhook, no outbound API, no third-party
  store. The runner opens no network socket.
- **Containers / data stores touched:** none. Scratch lives in `mktemp` roots under `/var/tmp` and
  `/tmp`, neither of which is a modelled store.
- **Actor↔surface access relationships:** unchanged. No ownership or sharing relationship moves; the
  advisory lock's scope (`git-common-dir`, i.e. all worktrees of one clone) is the same before and
  after.
- **Derived cardinalities `model.c4` embeds:** `bash plugins/soleur/test/c4-count-parity.test.sh`
  ran green this session (10 passed, 0 failed). Its counted quantities are cron-monitor counts,
  workflow check-in counts and Resend emitter counts — this work adds no workflow, no monitor and no
  emitter, so none of them moves.

### Sequencing

The ADR is authored in Phase 5 with the Phase 4 measurement in hand, in the same PR. It is not
`status: adopting`: the decision is true on merge, because the lane taxonomy and the execution model
both ship here. The one value it records after the fact is the default mode, which Phase 4 produces
before Phase 5 writes.

## Test Scenarios

Written as `mutation → guard reddens`, not `command → terminal output`.

| # | Scenario | Expected |
|---|---|---|
| T1 | Three synthesized fixtures — one with empty tokens, one `resources="*"`, one sharing a token with the first — at `SOLEUR_TEST_JOBS=4` | the `*` label's window intersects nothing; the token-sharing pair never overlap; the independent pair do |
| T2 | A fixture calls `kill -TERM $$` under parallel mode | `[KILLED]` with `signal-shaped 128+15 = SIGTERM`; exit 3 |
| T3 | A fixture calls `exit 143` | identical rendering to T2 — the marker has always meant *signal-shaped*, never *was killed by* (ADR-177) |
| T4 | One fixture fails an assertion, another is terminated | exit **1**; failure dominates; both lines present |
| T5 | A fixture exits 97 | `[TRIPWIRE]`, rc named, distinct from `[FAIL]` — the fourth rendered class, which the first draft of this plan omitted from its own taxonomy |
| T6 | A dispatched fixture's worker is killed before the collector joins it | UNACCOUNTED in the breakdown; exit 1; unmeasured outranks terminated (ADR-187) |
| T7 | **SIGINT is delivered to the PARENT while it is blocked in `wait -n -p`** | `wait` returns `128+2` with the pid variable **unset**; the runner must take the interrupt path — stop dispatch, drain, report unreaped indices UNACCOUNTED, exit 1 — and must **not** render `[KILLED]` for a suite that is still running |
| T8 | The pid→index map is permuted by one | the fault-injection triple reds; a green-tree repeat run would not |
| T9 | A relevance-declined suite in a parallel run | `[skip]` unchanged, `suites` and `skipped` both incremented, marker reads `N-k/N` |
| T10 | Serial and parallel transcripts of the same fixture group, elapsed masked | result lines, breakdown and marker identical; extra lines only the `[parallel]` banner and `[run]` pairs |
| T11 | Each of the six fallback conditions, including two true at once | serial path; banner names the **first** in precedence order |
| T12 | `tc_acquire` returns without locking (simulated via `SOLEUR_DISABLE_SESSION_STATE=1` against a synthetic lock root under `env -u CI`) | fallback to serial with the lock-unavailable banner — not a wide run |
| T13 | `LOCK_CONTENDED_PROCEEDING` fires | width resolves to 1 and the banner says so |
| T14 | A new `run_suite` registration added with no override entry | the classifier reads it, the census counts it, and an unreadable suite defaults to `*` |
| T15 | An override naming `scripts/validate-blog-links` instead of `blog-link-validation` | census reds — a declaration keyed on a path rather than on the emitted label |
| T16 | `--enumerate` returns zero records | every consumer fails closed on rc **and** count; no floor is satisfied by an empty population |
| T17 | `SOLEUR_TEST_JOBS` set to `0`, `-1`, `abc`, `""` | `exit 2` in each case, following the `TEST_GROUP` precedent |
| T18 | The runtime ceiling trips with workers in flight | dispatch stops, the pool drains, the banner names the draining labels and the overshoot; no worker is killed and the parent does not exit while one is live |


## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The derived classifier declares a suite parallel-safe that is not** | This is the failure direction the derivation *chooses* — conservative on every signal it can read, but a miss races rather than slows. The backstop is three-layered: Guard 1's pairwise window-intersection assertion over declared tokens, the fault-injection triple that catches misattribution, and the one-word rollback (`SOLEUR_TEST_JOBS=1`). A divergence between a parallel run and a serial re-run is an issue-filing event carrying the `concurrent=` set, never a silent retry. |
| **Property 1 is bought by no mechanism** | The first version of this plan hand-declared a dozen suites and defaulted ~420 to a drain barrier, which is slower than serial — the headline property delivered by unbudgeted work that follows the plan. The classifier is what closes it, and Phase 0.4a recomputes the Amdahl ratio **over the derived-parallel set** so the gap is measured rather than assumed. |
| **The enumeration source returns zero on a developer's host** | Measured, today, here: an unpinned `mise` bun shim aborts `--enumerate` at rc 1 with no records. Every floor is an absolute non-zero minimum and every consumer fails closed on rc *and* count, so the failure is loud. The one-character guard on `actual=$(bun --version)` is in Files to Edit. |
| **The flake does not reproduce under the constrained scope**, leaving every hypothesis UNKNOWN | Named as a permitted outcome in Phase 1.5 and Phase 2's fourth branch. Phase 3 still ships **as an opt-in**: condition (e) governs the **default flip only**, and the scheduler's safety rests on the fault-injection triple, the token-intersection assertion and the exit-contract guards — none of which depend on the diagnosis. That is deliberate: merging a scheduler nobody can enable, plus a taxonomy every future suite author must satisfy, would be exactly #7454's rejected shape with a maintenance obligation attached. The classification itself is independently justified — the collision inventory is a real finding regardless of what #7376 turns out to be. If the Phase 0.3 capacity mechanism cannot manufacture a memory constraint (measured: `systemd-run --user --scope` does not constrain cpuset here), H2 is UNKNOWN by construction and this is the expected branch, not a surprise. |
| **Added concurrency fires the 37 suites carrying an internal `timeout`** (#6496's class, generalised) | The population is measured, not guessed. Phase 1's H4 verdict classifies them; any that fire carry the `deadline` token with the attribution recorded. Their deadlines are **not** raised — raising a deadline to survive a scheduler moves the flake rather than removing it. |
| **An empty token set is a claim no machine can verify** | It is **derived**, so the claim carries the grep that produced it; the derivation is conservative on every signal it can read; Guard 2's M4 row reds if it ignores one; Guard 1's pairwise intersection assertion and the fault-injection triple are the runtime backstop; and the rollback is one word. |
| **`git status --porcelain` contention on `.git/index.lock`** (C2) | `scripts/cf-tunnel-liveness-gate-mutations` declares `*`, and every other live-repo `git` writer declares `repo:index`. Phase 1's `wrote_outside_sandbox` field is what would surface any further live-repo `git` writer this plan has not enumerated. |
| **A suite spawning a real `test-all.sh` deadlocks on the parent's advisory lock for up to `TC_LOCK_TIMEOUT` = 3600 s** (C4) | This is a deadlock with a long fuse, not a flake — and it is also a live candidate cause of #7376 itself, since a starved child looks exactly like an unattributed suite failure and would explain why seven runs named four *different* suites. Phase 0.5 measures the blocking subset's wall-clock share **before** anything is built — from the `tc_acquire` caller log, not from a grep — a majority share is the no-go branch, and every member carries `lock:test-all`. Guard 2's M6 row is the machine check that keeps the set current. |
| **Editing `run_suite` has a 434-suite blast radius** | The dispatch/reap split leaves `_shard_selects`, the `_ENUMERATE` arm, the `suites` increment, `suite_exit_class` and every result-line string untouched. AC13 asserts byte-identical transcripts; AC23 asserts the parity pin still holds; AC22 asserts the `TC_SIBLING_RUN_COUNT` anchor is intact. |
| **The measured baseline is stale** (291 suites then, 434 now) | Phase 0.4 re-measures on this host before anything is claimed, and the staleness is stated wherever the old numbers are quoted. |
| **The ADR ordinal collides** | Re-derived across all `origin/*` refs immediately before merge, with a sweep of the feature's artifact set on any renumber. |
| **Two guards inherit the same blind spot** | The 2026-08-11 learning's tells are applied explicitly: each guard's fixture stages **two** members (M4/M4/M2 rows), each anti-vacuity floor reads a counter incremented at the call site rather than by the verdict helper, and no guard derives its oracle from the system under test — Guards 1 and 3 derive theirs from `--enumerate`, which is a *different* code path from the executor. The review ask is "find vacuity the battery missed", not "re-run its mutations". |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **Opt-in flag, serial default, ship it** | Rejected in writing by #7454: *"a flag nobody can responsibly enable is dead code."* This plan's default is decided by a pre-registered measurement, and either outcome ships with its reason recorded. |
| **Fan out N child `test-all.sh` processes on `SCRIPTS_SHARD=k/N`** | Each child takes the advisory lock, emits its own contention preamble, its own terminal marker and its own exit code. Aggregating N exit contracts is exactly the collapse the contract forbids. `scripts/test-all.sh:600` also refuses `SCRIPTS_SHARD` outside `TEST_GROUP=scripts`, and the round-robin balances *neighbours*, not durations — one leg would get the 25-minute battery. |
| **`xargs -P` at the top level, mirroring the infra runner** | `xargs` cannot return per-child rc, which forces a file sideband — the #7554 forgery channel, and ADR-187's "mimicry unavailable by construction" case. `wait -n -p` returns the rc in-process, measured returning 143 from a SIGTERM'd child. |
| **Longest-processing-time-first scheduling using `TEST_TIMING_LOG` as a duration oracle** | Deferred, not rejected. It would reduce makespan, but it makes execution order depend on a file that may be absent, stale, or from a different host — and order-dependence is what T7's byte-identical-transcript assertion forbids. Registration order is deterministic and cheap. Re-evaluate once Phase 4 reports `total ÷ longest`: if the ceiling is dominated by tail suites rather than by one battery, LPT buys something. Tracked as a deferral below. |
| **Raise the deadlines in the 37 `timeout`-bearing suites so they survive concurrency** | Moves the flake instead of removing it, and the repo has already rejected the equivalent move for #6496 ("only moves the flake rather than removing it"). |
| **Automatic serial re-run of any suite that reds under parallel mode** | A re-run of an unchanged tree is the repo's own definition of a harness defect, never a retry. Attribution (naming the concurrent set) is shipped instead. |
| **Fix #7554 by giving each suite its own `.meta` subdirectory** | That is one of two contested options #7554 records, and choosing between them is that issue's design decision, not this one's. This plan avoids the channel entirely at the new layer rather than picking a winner at the old one. |
| **A `parallel` / `serial` / `serial-after` lane vocabulary** | Cannot express a drain barrier (C1 fails on *any* concurrent worktree change, so its own slot is not enough) and cannot exclude a third writer from a shared artifact (C3 — ordering is not exclusion). One resource-token set expresses both, and `*` *is* the barrier. |
| **A hand-declared token table with a fail-closed `*` default** | Against 434 registrations it classifies a dozen and defaults ~420 to a drain barrier — parallel mode would be *slower than serial* on day one, and the several-hundred-suite classification campaign that would fix it is in no phase. Property 1 would be bought by nobody. Replaced by a derived classifier with a hand override table. |
| **A count ratchet (`test-suite-lanes.highwater`) over the parallel population** | Set identity already implies the cardinality bound, and the `lint-diagnosis-claims.highwater` precedent does not transfer: that population is a repo-wide grep invisible in a diff, this one is a declaration table where every widening is already a reviewable line. A guard that fires on 100% of its intended use is a speed bump. |
| **A standalone cross-worktree contention suite** | Its intra-run half is the window-intersection machinery Guard 1 needs anyway; its cross-worktree half re-tests `tc_acquire`, which this change does not touch. It also could not have passed: `tc_acquire` returns 0 without locking when `CI` is set, so an arm asserting "the lock was held" reds on every CI run. |
| **A standalone lane-census suite** | `scripts/lint-orphan-test-suites.sh` already consumes a runner-published contract with a fail-closed rc-and-count check and already censuses `test-relevance-paths.sh`'s arrays. Decisively, `scripts/lib/test-relevance-paths.sh` has **no** sibling test suite — the precedent is censused by the linter. |
| **A 20-day sweeper-enrolled soak gating the default flip** | Green by construction: the default is serial during the soak and `CI` forces serial, so the probe would compare serial to serial twenty times; and a GitHub-Actions sweeper cannot observe local full-gate runs. The rollback for a wrong default is one word. |
| **A five-run stability gate** | The plan's own arithmetic disqualifies it: 5 clean runs bound the per-run flake rate only at `p < 0.45`, and a weekly 5% flake passes them 77% of the time. Recorded as an observation with its power calculation, never as a licence. |
| **A `scripts/suite-runner-capacity-repro.sh` harness with its own registered test** | `SOLEUR_KEEP_LOGDIR`, the per-suite `.meta` and the retained-path print already exist. What is new is a fifteen-line loop, and a fifteen-line loop does not earn a guard suite, an anti-vacuity floor and a synthesized collision fixture — especially one whose subject is a deliberate race, which cannot assert deterministically inside a green battery. |
| **An incremental printer cursor** | Buys earlier output only when suites finish near registration order, and delivers nothing when a long suite sits at a low index. Drain-then-print is byte-identical and far simpler; liveness is bought instead by two unanchored `[run]` lines on stderr. Reconsider if Phase 0.4 shows the long suites cluster late. |
| **A re-entrant advisory lock for nested `test-all.sh` spawns** | Weakens a cross-worktree guarantee ADR-133 established. "The free option is expensive" is Phase 0.5's no-go branch, not a reason to weaken an ADR. |
| **Batch suites `-n<k>` before parallelising** (the 2026-04-07 xargs learning) | That learning's payer is process-spawn amortisation across 1,779 short items. These suites are minutes long, so spawn cost is noise and batching would only coarsen scheduling. |

## Non-Goals / Out of Scope

Each item below is tracked by an existing open issue. None is closed by this work, and each has a
re-evaluation trigger already recorded on its own issue.

- **#7376 is not closed.** This plan produces its diagnosis; closing it needs the soak its own
  follow-through script (`scripts/followthroughs/suite-runner-flake-7376.sh`) gates on, which in turn
  gates on #7432 closing.
- **#7432 is not closed and the `JOBS: 1` pins are not removed.** Stated explicitly in Phase 2 rather
  than done or skipped silently. Removing them also requires deleting check (12) at
  `plugins/soleur/test/main-health-monitor-workflow.test.sh:470-486`, and
  `scripts/followthroughs/jobs1-stopgap-7432.sh:33` only passes when zero `JOBS: 1` remain on `main`
  — so the removal is a soak-gated event that belongs to #7432.
- **#7554** — the `.meta` forgery channel in the infra runner. Avoided at the new layer, not fixed at
  the old one.
- **#7076** — the infra runner's derivation gap (subdirectory suites and the `sudo bash` case).
  Orthogonal: it is about which suites the *infra* runner sees, not about how the *top-level* runner
  schedules.
- **#8045** — the lefthook hook's glob. Scoping the hook to what the commit touches is a different
  change to a different file, and this work reduces the same pain from the other side.
- **#6496** — the md-to-mrkdwn wall-clock assertion. Given the `deadline` token here with a citation; converting
  it to a growth-ratio assertion is that issue's work.
- **#7942** — the two unregistered `*.mutation.sh` batteries. Acknowledged in the overlap section.
- **Classifying every registration by hand.** The derived classifier is what buys Property 1; a
  hand campaign over ~420 suites is explicitly not in this work, and the override table is for the
  cases the classifier cannot read.
- **Longest-processing-time-first scheduling.** Deferred with a named trigger (Phase 4's
  `total ÷ longest` report). A tracking issue is filed at `/ship` with that trigger, per
  `wg-when-deferring-a-capability-create-a`.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6.** This one declares `none` with the scope-out
  reason preflight Check 6 requires.
- **`plugins/soleur/test/fanout-suite-scope.test.sh` anchors on the literal
  `if [[ "${TC_SIBLING_RUN_COUNT}` at column 0 and requires exactly one match.** Adding a leading
  conjunct to `scripts/test-all.sh:1326` reds it. If the parallel path needs to influence the
  sibling refusal, do it inside the block, not on that line.
- **Check (12)'s regex is indentation-sensitive** (`^        id:` = 8 spaces,
  `^          JOBS:` = 10). Any reformatting of those two workflow steps silently breaks it, even
  though this plan does not edit them.
- **`suite_exit_class` is byte-identical-pinned** against `.github/scripts/test/run-all.sh` by
  `scripts/suite-exit-class-parity.test.sh`. The scheduler must not touch it. The *third* copy, the
  boolean predicate inlined at `apps/web-platform/infra/run-registered-suites.sh:422-436`, is
  deliberately **not** byte-identical and must not be "restored to parity".
- **A backgrounded job in a non-interactive shell gets `/dev/null` on stdin.** Any suite that reads
  stdin behaves differently under the pool than it does inline. Worth one probe before the default
  flips.
- **`wait -n` with no unwaited children returns 127 and leaves the `-p` variable empty**, which
  collides with a suite's own `exit 127`. The empty variable is the discriminator; the `|| rc=$?`
  guard must not swallow it.
- **Cite content anchors, not bare line numbers, wherever a guard will assert** (`cq-cite-content-anchor-not-line-number`).
  Several line cites in the first draft of this plan were already off against today's tree —
  `skip_suite` is at `:1013` not `:844-873`; the `--enumerate-commands` emitter is
  `_shard_enumerate_command_emit` at `:821-823`, not the record-contract comment at `:180-210`;
  `tc_acquire` is defined at `test-contention.sh:942` (`:1038` is a line inside it);
  `session-state.sh` lives under `plugins/soleur/scripts/lib/`, not `scripts/lib/`;
  `grok-pre-push-gate.sh` under `plugins/soleur/scripts/`; the `exit 2` near `:816` is at `:817`.
- **A registration's LABEL is not its file path, and the two drift.** `scripts/validate-blog-links.sh`
  registers as `blog-link-validation` (`:2562`); `scripts/orphan-process-reaper-mutation.test.sh`
  registers as `scripts/orphan-process-reaper-mutation`**s** (`:1861`). The declaration table is keyed
  on the **label `--enumerate` emits**, never on a path, and Guard 2's M1 row reds on any declaration
  whose key is not in the emitted set — which is exactly how a path-shaped guess is caught.
- **Repo-root `scripts/*.test.sh` is not globbed.** Every new suite there needs an explicit
  `run_suite` line or `scripts/lint-orphan-test-suites.sh` reds.
- **`TMPDIR` and `TC_TMPDIR` are deliberately different mounts** — `/var/tmp` (disk, suite scratch)
  and `/tmp` (the ~4 GiB tmpfs the contention lib watches), set at `scripts/test-all.sh:274` and
  `:288`. A "tidy-up" that collapses them changes what every capacity measurement in this repo means.
- **Never `| tee` a shared file from concurrent children.** PIPE_BUF atomicity is a property of
  pipes and does not apply to regular files; the incident is recorded at
  `apps/web-platform/infra/run-registered-suites.sh:376-386` and in
  `knowledge-base/project/learnings/2026-08-10-pipe-buf-atomicity-does-not-apply-to-the-file-i-was-redirecting-into.md`.
  Each suite gets its own capture file and the parent is the sole writer of the aggregate stream.
- **Capture order is `>"$f" 2>&1`, never `2>&1 >"$f"`.** ~107 sites write their failure marker to
  stderr; the inverted form loses every one of them while looking healthy
  (`run-registered-suites.sh:387-391`).
- **The advisory lock's fd is inherited by suite children** (`exec {fd}>>`, no CLOEXEC), which is why
  the runtime ceiling uses an early `return` and never an `exit`
  (`scripts/test-all.sh:863-870`). A parallel reaper must preserve that property: no `exit` while a
  worker is live.
- **`scripts/test-all.sh` runs under `set -euo pipefail` (line 2).** Every `wait -n -p` must be
  written `wait -n -p pid || rc=$?` — a bare one aborts the whole runner on the first failing child,
  and the runner then produces no summary and no terminal marker, which is precisely the
  no-summary shape the comment at `:304-311` documents as sending operators into a relaunch loop.
  The same guard applies to the semaphore's `wait`.
- **`--enumerate` is the derivation source and it is fragile.** It returns zero records at rc 1 on a
  host with an unpinned `mise` bun shim, because `actual=$(bun --version)` at `scripts/test-all.sh:318-325`
  aborts under `set -e`. Any consumer that reads `grep -c` without checking rc sees `0` and proceeds
  over an empty population — and an anti-vacuity floor written as `derived >= derived` is then
  `0 >= 0`. Copy `scripts/lint-orphan-test-suites.sh:229-232`'s shape: check rc, check the count, and
  fail closed on either.
- **`wait -n -p` returns `128+N` when the PARENT is signalled, and leaves the pid variable unset.**
  Read the variable, not the return value. A reaper that trusts the return renders `[KILLED]` for a
  suite that is still running — ADR-187 §2's forbidden mimicry, reached by construction rather than
  by carelessness. `scripts/test-all.sh` has an EXIT trap (`:1467`) and **no INT or TERM trap**.
- **The reaper must be the MAIN SHELL.** `wait` reaps only the forking shell's children, so moving
  the reap loop into a function called in a pipeline puts it in a subshell, returns "no child
  processes" immediately, and marks every suite UNACCOUNTED behind a green-looking run.
- **`resources="*"` is a drain barrier, not a slot.** A declaration that only gives a suite its own
  worker still leaves `P-1` siblings in flight, which is exactly the condition C1's battery fails
  on. If a future edit "optimises" the barrier into a slot, C1 reds intermittently and reads as a
  sandbox escape.
- **Ordering is not exclusion.** `after="<label>"` sequences a declared producer and consumer; it
  says nothing about a third suite touching the same artifact. `artifact:_site` must stay on **both**
  sides of that pair, not on the consumer alone. And `after=` needs a branch for five reachable
  states the first draft left undefined: the named producer relevance-declined, the producer outside
  the selected `TEST_GROUP` (both `plugins/soleur` and `blog-link-validation` are `bun`, so a group
  selection can take the consumer without the producer), the producer registered *after* the
  consumer, a cycle, and a chained `after=`. Today's guarantee is **positional** —
  `scripts/test-all.sh:2554-2562` co-locates them with a comment naming the hazard — and a
  declarative replacement has to carry that guarantee across, not assume it.
- **A ceiling trip makes the two arms incomparable.** `_ceiling_declined` is a function of elapsed
  wall clock at dispatch index `i`, and lowering that is the whole point of parallel mode, so a
  ceiling-tripped run declines a different set in each arm. Pin `TC_RUNTIME_CEILING_S` beyond reach
  in every benchmark arm and guard fixture, and assert `_ceiling_declined == 0` before reading any
  comparison.
- **`TC_LOCK_TIMEOUT` is 3600 s** (`scripts/lib/test-contention.sh:67`). A stale comment at
  `scripts/test-all.sh:1300` still says 900 s; `:1571` says 3600. Read the definition, not either
  comment.
- **A hypothesis table may not read CONFIRMED or REFUTED while its discriminator is invisible.** The
  probe ships in its own commit, ahead of any fix, and is never deleted using a conclusion it was
  meant to test. "There is nothing left to discriminate anyway" is the circular argument that
  ended a full host replacement for a defect that did not exist (#6536).
