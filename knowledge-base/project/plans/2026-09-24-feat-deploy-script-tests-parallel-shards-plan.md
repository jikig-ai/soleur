---
title: "feat: shard deploy-script-tests into a matrix runner with duration-aware assignment"
type: feat
date: 2026-09-24
slug: deploy-script-tests-parallel-shards
branch: feat-one-shot-8736-deploy-script-tests-parallel
issue: 8736
closes: [8736, 8744, 7076]
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: shard deploy-script-tests into a matrix runner with duration-aware assignment

## Enhancement Summary

**Deepened on:** 2026-09-24
**Sections enhanced:** Runner contract (per-suite timeout portability,
`::error` sanitization, emit-shape literals), aggregator design (ci.yml:1525
verbatim shape incl. cancelled-vs-superseded discrimination), observability
(follow-through soak enrollment), risks (production-mutation answer,
workflow_run consumer census).
**Research agents used:** none spawned — this pipeline runs headless without
a Task surface; every deepen-plan gate and verification was executed inline
with direct repo/API reads (`Reviewed-Coverage: sequential-fallback`).

### Key Improvements

1. Aggregator job spec changed from "the `test`-aggregator pattern" to the
   verbatim `ci.yml` `Aggregate shard results` shape — including its
   measured insight that a leg-level `timeout-minutes` kill reports
   `cancelled`, not `failure` (load-bearing for the #8735 notify fix).
2. Per-suite timeout bound gained the macOS-portability requirement
   (`timeout`→`gtimeout`→absent; fail-loud under CI) — the runner executes
   on operator hosts.
3. ADR provisional ordinal corrected 246 → 250 (ADR-245/248/249 occupied on
   branch and `origin/main`).
4. `RED  <path>` emit literal normalized to the two-space form the monitor
   anchors on (`run-registered-suites.sh:437`, monitor comment ~420).

### New Considerations Discovered

- The aggregator body carries an executable guard precedent —
  `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` extracts and
  executes the ci.yml step over synthetic result triples; the new job gets
  the same treatment.
- No `workflow_run` consumer watches this workflow (enumerated), so leg
  redness cannot dark a downstream deploy gate — the `#8570` blast-radius
  edge is clear.
- `git ls-files` pathspec `*` crosses `/` — one glob returns all 146 tracked
  suites including the six subdirectory ones (verified).

## Overview

`deploy-script-tests` in `.github/workflows/infra-validation.yml` executes its
registered infra suites as 143 serial per-suite `run: bash` steps on a 4-vCPU
GitHub runner. Green wall clock has grown to ~25 minutes (measured 1504 s of
step time across 168 steps on run 36037220776, the last green main-push run of
2026-09-24) and the job-level `timeout-minutes` ceiling has been re-derived
upward six times in ten weeks (8 → 12 → 14 → 15 → 20 → 27 → 35) because every
new suite extends the serial tail. The job is also the only push-time executor
of this suite set (#6766), so its wall clock is the tail latency of every
main-push CI cycle.

This plan restructures the job around the shard machinery this repo already
operates for `scripts/test-all.sh` (ADR-238, amended by ADR-240): a bounded
matrix of legs, each executing a partition of the registered suite set through
`apps/web-platform/infra/run-registered-suites.sh`'s existing `xargs -P`
executor, with per-suite verdict lines, per-suite log artifacts, per-suite
timeout bounds carried into the runner, and a committed duration-aware
leg-assignment manifest. The registration contract moves from "one named
`run: bash <path>` step per suite" to a derivable registration list
(`git ls-files` glob + justified exclusions), with the registration gate and a
new shard-totality guard extended in the same change. This is the "extend the
contract + gate together" arm the issue sanctions, and it is what lets a new
suite be absorbed by the glob + partition with zero workflow edits and no
ceiling re-derivation.

The #8744 `FIXTURE_APT_FAILED` flake (git-data runtime-arm fixtures running
`apt-get` inside containers with no retry and swallowed diagnostics) is fixed
in an early phase — it is orthogonal to the restructure but operator-approved
in scope, and it is the difference between "shard schedule verified" and
"shard schedule verified against a green fleet".

## Research Insights

Consolidated from in-session repo research (the research fan-out was executed
inline — this pipeline subagent has no Task-spawn surface, so
`soleur:engineering:research:*` agents were replaced by direct reads of the
authoritative files).

**Premise validation (Phase 0.6).** Every cited reference verified live:
#8736, #6766, #8744, #7076 all OPEN (the premise holds); PRs #8738, #8733,
#8690, #6778 all open DRAFTs (collision surface real). Cited files all exist
on the branch: `infra-validation.yml` (2399 lines), `run-registered-suites.sh`
(689), `test-all.sh` (4736), `lib/test-relevance-paths.sh` (277). Two brief
claims needed correction — see Research Reconciliation. ADR corpus checked
for the proposed mechanism: ADR-238 (shard topology precedent, accepted) and
ADR-240 (checked-in manifests) both endorse the mechanism chosen; the
mechanism the brief calls "in-job parallelism over a runner" is NOT in any
ADR's rejected-alternatives table.

**Property List (Phase 0.6b — the ask restated as observable properties).**

- P1: `deploy-script-tests` wall clock < 10 min on typical main-push runs.
- P2: a suite landing adds no re-derivation chore (structure absorbs growth).
- P3: a failing suite names itself in job output/artifacts (attribution).
- P4: push-to-main runs the full registered set (coverage, #6766).
- P5: per-suite time bounds survive the restructure (the ceiling PR's
  step-level `timeout-minutes` convention).
- P6: the apt-fixture flake stops being undiagnosable (#8744).
- P7: the local runner and CI execute the same suite set (#7076).

**Cut List (Phase 0.6b — mechanisms considered and removed).**

- BASH_ENV per-step shard filter (keep all 143 steps + matrix): buys P1 but
  is a masking-adjacent side-channel on every bash invocation in the job and
  shows ~108 green no-op steps per leg — rejected, see Alternatives.
- N sibling jobs with explicit step lists: buys P1/P3 but keeps the
  registration toil that produced the issue and has no automatic balance —
  rejected.
- Published fixture image / registry cache for docker legs: rejected by
  #7535's brainstorm D1 (never-publish; ~10 s/run benefit, fork-PR breakage,
  new trust anchor).
- Affected-only per-suite selection on PR runs: deferred — no per-suite edge
  index exists for infra suites (`test-relevance-paths.sh` covers 4 heavy
  predicates + the nested `run-all.sh` runner only), and a ~5-min full run
  makes the marginal value small. Tracking: fold into the affected-selection
  axis if a tracker exists, else file at ship.

**Measured basis.** `gh api` step timings for run 36037220776 (last green
main-push, 2026-09-24T17:51Z): 168 timed steps, 1504 s total, median 1 s,
p90 18 s; six steps >60 s carry 874 s (58%). Sticky-LPT partition:
K=3→502 s worst leg, K=4→376 s, K=6→251 s; per-leg fixed ≈90 s (checkout 12 s
plus toolchain installs plus docker assert). The floor is the heaviest single
suite (205 s) — no K beats it without splitting that battery.

**Relevant file paths.**

- `.github/workflows/infra-validation.yml` — the `deploy-script-tests` job
  (line ~455; `timeout-minutes: 35` at ~644), `infra-validate-required`
  (~434), `notify-main-failure` (~2380).
- `apps/web-platform/infra/run-registered-suites.sh` — derivation at ~241,
  xargs executor ~432, `.meta`/`RED` emit ~436, UNACCOUNTED accounting ~586.
- `.github/scripts/test/test-infra-suite-registration.sh` — the registration
  gate (job-slice ~139, masking check ~156, EXCLUSIONS ~97,
  KNOWN_UNDERIVABLE ~113) + its mutation harness (same directory).
- `apps/web-platform/infra/git-data-ownership.test.sh:280`,
  `git-data-cutover-access.test.sh:1770` — the #8744 apt sites.
- `scripts/test-all.sh` — `SCRIPTS_SHARD` parse (~348-380) + manifest load
  (~853-948) = the parse contract to mirror; shard scope refusal ~818.
- `scripts/regenerate-shard-manifest.py` + `scripts/suite-shard-legs{,-heavy}.tsv`
  — the sticky-LPT generator (ADR-240) to extend with `--group infra`.
- `plugins/soleur/test/scripts-shard-totality.test.sh` +
  `scripts-shard-totality-mutations.sh` — the totality-guard precedent.
- `scripts/followthroughs/ci-leg-durations-8006.sh` — the soak-probe
  precedent for the wall-clock AC.
- `.github/workflows/main-health-monitor.yml` ~130-230 — references the
  35-min budget + runs the same runner unsharded (must keep working).
- `apps/web-platform/infra/run-registered-suites.test.sh`,
  `scripts/test-all-infra-coverage-notice.test.sh`,
  `scripts/test-all-killed-classification.test.sh` — suites pinning the
  runner's current derivation (must move with it).

**Institutional learnings applied.**

- `2026-09-24-a-line-scanner-is-not-a-lexer…` — the gate's text-anchored YAML
  slicing is a documented limitation, not a license to widen it: new
  assertions stay inside the existing anchored-parse discipline and the
  gap is noted in the gate header.
- `2026-09-21-the-shard-i-substituted-for-a-refused-gate…` and ADR-240 —
  partition data is checked-in generated data; a missing/mismatched manifest
  is a loud degrade, not a silent full-run.
- `2026-08-10-pipe-buf-atomicity…` — the runner's emit discipline (prefixed
  diagnostics, unprefixed verdicts, summary line last) is preserved verbatim;
  the monitor greps those anchors.
- #7942 convention — new guard/battery files are `test-*.sh` under
  `.github/scripts/test/` (auto-globbed, REQUIRED) — never `*.mutation.sh`.

**External research:** skipped — every mechanism in the design is in-repo
precedent (ADR-238/240 machinery, runner executor, gate harness). No new
vendor, framework, or API surface is introduced.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (measured this session) | Plan response |
|---|---|---|
| "~183 named steps" | 168 timed steps on the last green run; 143 are `run: bash` infra-suite registrations (137 top-level + 6 subdir) | Numbers corrected; the argument is unchanged |
| "cap `min(4, nproc-2)`" in the runner | Actual cap is `min(nproc, 6)` → 4 on the runner | Same effective width; corrected |
| "8 registered infra suites missed by derivation (7 subdir + 1 sudo)" | Post-#7068: 6 subdir + 3 sudo = 9 missed; 137 derived vs 146 on disk | Corrected figures; all 9 dissolve under glob derivation |
| infra suites "whether covered by the relevance index is open" | Not covered: `test-relevance-paths.sh` has no per-suite infra edges; `--affected` selects the infra runner as one node | Candidate 1 deferred on evidence |
| "deploy-script-tests red since 13:42Z" | Red at 14:49-15:49Z, green again 17:05/17:51Z — transient recovery, not a fix | #8744 fix still required (open issue, root cause unaddressed) |
| push-time is the only full run | `main-health-monitor.yml` also runs the set 6-hourly via TEST_GROUP=infra | Monitor preserved as the unsharded echo |

## Problem Statement

1. **Wall clock.** The job measures 1066–1462 s across the last 19 successful
   main-push runs (re-derived 2026-09-24, the `timeout-minutes: 35` comment
   block). The step-duration distribution is extreme: of 168 timed steps on
   run 36037220776, the median is 1 s, p90 is 18 s, and six steps carry 874 s
   (58%) — the infra-config re-push mutation battery (205 s), the zot-primary
   bootstrap pull mutation battery (197 s), the git-data runcmd rehearsal
   (189 s), the runner self-tests (120 s), the web-host parity mutation
   battery (93 s), and the git-data cutover access tests (70 s).
2. **Serial structure.** GitHub Actions runs steps within a job strictly
   serially, so 143 registered suite invocations can never overlap regardless
   of how small most of them are.
3. **Ceiling treadmill.** Each suite landing silently pushes the serial sum;
   the ceiling block's own "re-derive if steps are added" instruction has been
   executed six times and produced four consecutive main-push cancels at the
   27-min cap on 2026-09-24 before the bump to 35.
4. **Active flake.** `FIXTURE_APT_FAILED` (rc=100) inside the git-data
   ownership/cutover fixtures made the job red fleet-wide from
   2026-09-24T13:42Z (#8744): the fixture pipes apt output to `/dev/null` and
   has no retry, so one transient mirror error reds the run and the log cannot
   say why.
5. **Known coverage debt.** `run-registered-suites.sh` derives its execute
   set from the workflow's `run: bash` steps with a basename character class
   that excludes `/`, so 6 subdirectory suites plus 3 sudo-invoked loopback
   suites are invisible to the local runner (#7076): 137 derived vs 146 on
   disk.

## Proposed Solution

Convert `deploy-script-tests` from a 143-step serial job into a three-job
structure, reusing the ADR-238/ADR-240 topology rather than inventing one:

| Job | Shape | Contents |
|---|---|---|
| `deploy-script-tests` | `strategy.matrix.leg: [1..K]`, `fail-fast: false` | Per leg: checkout → toolchain setup (terraform, cloud-init, nftables, docker assert) → `SOLEUR_INFRA_SHARD=<leg>/K bash apps/web-platform/infra/run-registered-suites.sh` → per-suite log/timing artifact upload. Each leg runs its assigned subset through the runner's existing `-P` executor. |
| `deploy-script-tests-fixed` | single job, parallel with the legs | The items that cannot or should not be glob-derived or run K times: the 3 sudo loopback suites, the 2 inline `terraform validate` blocks, `fixtures-validate-infra-templates.sh`, the evidence-freshness / systemd-lint / provenance blocks, the 5 `apps/web-platform/test/infra/*.test.sh` steps, and `sandbox-canary-regression.test.sh`. Keeps its own per-step `timeout-minutes` and named-step attribution. |
| `deploy-script-tests-done` | `needs: [deploy-script-tests, deploy-script-tests-fixed]`, `if: always()` | Synthetic aggregator modeled verbatim on ci.yml's `test` job (`Aggregate shard results` step, `ci.yml:~1525`): per-need `result` strings into `env:`, colon-delimited `entries=(...)` list, fail on ANY non-success — with the same cancelled-vs-superseded discrimination (a `timeout-minutes` kill cancels ONE leg while siblings conclude; a concurrency cancel cancels all — the two `cancelled` shapes are distinguished in the diagnostic, and the verdict never depends on it). Gives consumers — `notify-main-failure`, future required-check wiring (#6766/#6480) — ONE stable result name. |

Runner changes in `apps/web-platform/infra/run-registered-suites.sh`:

- **Derivation source switches from workflow-scrape to filesystem glob**
  (`git ls-files "${SOLEUR_INFRA_DIR}/*.test.sh"` — verified: the git pathspec
  `*` matches `/`, so one pattern returns all 146 tracked files including the
  6 subdirectory suites).
  Presence becomes registration: a suite on disk is in the execute set unless
  it carries a justified exclusion. This dissolves the entire defect class the
  current gate exists to catch (suite on disk, no `run:` step) and closes the
  #7076 subdir gap — the `[A-Za-z0-9._-]` derivation class disappears with the
  scrape.
- **Privileged bucket (derive-but-do-not-execute, #7076's recommended shape).**
  A `name|reason|#issue` list carrying the three sudo loopback suites
  (`git-data-plaintext-snapshot-loopback`, `inngest-redis-luks-loopback`,
  `workspaces-luks-loopback`). They are derived, printed as a counted
  `SKIP privileged` set, and never invoked by the runner — in CI they run via
  `sudo bash` steps in `deploy-script-tests-fixed`, which the gate continues
  to require. Locally they stay out of the execute set, so the mandated local
  gate does not go permanently red on a machine without passwordless sudo.
- **`SOLEUR_INFRA_SHARD=k/N`** env selector with the same fail-closed contract
  as `SCRIPTS_SHARD`: unset = full set (local/monitors), set-but-malformed or
  out-of-range = exit 2. Partition order: committed manifest
  `apps/web-platform/infra/suite-shard-legs.tsv` (sticky-LPT generated data,
  ADR-240 pattern) when present and `n` matches; deterministic positional/hash
  fallback otherwise, announced in the log.
- **Per-suite timeout bound.** The xargs shim wraps each suite in a bounded
  execution: a default budget plus a small `name|seconds` override map for
  the docker-runtime heavies (rehearsal, cutover, ownership — the three steps
  the ceiling PR bounded at 10/10/5 min). rc=124 renders as a `RED` verdict
  naming the suite — the step-level `timeout-minutes` attribution convention
  carried into the new structure, now covering every suite rather than three.
  **Portability:** this runner executes on operator hosts too, and stock
  macOS has no `timeout` — resolve the bounder once at startup with the
  repo's `timeout`→`gtimeout`→absent pattern
  (`.claude/hooks/memory-backstop.sh` line ~381 does exactly this) and fail
  LOUD when neither exists under CI (`CI=true`), degrade-with-announce
  locally rather than silently unbounding.
- **`::error` annotation on RED.** Each `RED  <path>` also emits
  `::error file=<path>::suite failed — see <key>.log` so the run summary page
  names the failing suite without opening leg logs. The path is CR/LF-stripped
  (`${var//[$'\n\r']/}`) before reaching the annotation — GitHub annotation
  commands are line-oriented and the path is attacker-adjacent input only in
  the weak sense (a committed filename), but the strip is one expansion.
- **Timings emission.** Each leg uploads a `suite-timings-infra-<leg>`
  artifact (the existing `.meta` rows as `label<TAB>ms<TAB>verdict`), the feed
  for `scripts/regenerate-shard-manifest.py --group infra`.

Gate changes in `.github/scripts/test/test-infra-suite-registration.sh`
(same file, same `guard-script-fixture-tests` home — REQUIRED, merge_group,
path-filter-free):

- The single-line `run: bash` shape assertion is replaced by a
  **registration-list contract**: the workflow must invoke the runner in the
  `deploy-script-tests` job under a matrix whose leg count the gate parses,
  with `SOLEUR_INFRA_SHARD` bound per leg; the glob set must equal
  derived ∪ justified-exclusions; every privileged entry must still be
  invoked via `sudo bash` in `deploy-script-tests-fixed` (the existing
  exclusion-arm "waives the shape, never the existence" rule survives as
  "waives the runner, never the invocation").
- The masking check (`if:`/`continue-on-error:` ban) is re-scoped, not
  deleted: it still bans both keys on the runner-invocation and
  suite-executing steps, and gains an allowlist for the artifact-upload and
  aggregator steps (`if: always()` is required for them to function).
- `KNOWN_UNDERIVABLE` is deleted — subdirectory paths derive under the glob.
- `test-infra-suite-registration-mutations.sh` gains rows for the new arms.

Ceiling re-derivation: each leg carries its own `timeout-minutes` re-derived
at the same ~1.4× convention over the measured worst-leg duration;
`deploy-script-tests-fixed` and `deploy-script-tests-done` get their own
measured ceilings. The 35-min monolith ceiling and its re-derivation comment
are replaced by the per-leg block.

## Technical Approach

### Measured basis (Phase 0.6c / already pulled from the API)

Run 36037220776 (last green main-push run, 2026-09-24T17:51Z): 168 timed
steps, 1504 s total. Sticky-LPT partition of the measured step durations:

| K | worst leg (suite time) | + ~90 s per-leg fixed | projected leg wall |
|---|---|---|---|
| 2 | 752 s | 842 s | ~14 min |
| 3 | 502 s | 592 s | ~9.9 min |
| 4 | 376 s | 466 s | ~7.8 min |
| 6 | 251 s | 341 s | ~5.7 min |
| 8 | 205 s | 295 s | ~4.9 min |

These are *serial-per-leg* projections. Each leg additionally runs its subset
through the runner's `xargs -P` executor (`min(nproc,6)` = 4 on the runner),
so realized leg times should land below the projection — the projection is
the conservative bound. The floor is the heaviest single suite (205 s); no
configuration beats it without splitting that battery internally (rejected by
ADR-238 for the same class — a follow-up, not this plan).

**Recommended K=4**, not K=6+: at K=4 the projected worst leg is ~7.8 min
with margin under the 10-min target even before in-leg parallelism, and each
additional leg costs ~90 s of duplicated fixed work (checkout + toolchain
installs) against the org's 20-concurrent-job budget (2026-09-21
ci-runner-concurrency brainstorm measured the ceiling as the org's binding
constraint). K=4 costs ~6 min of aggregate runner time per run; K=6 saves
~2 min of wall clock for +3 min of aggregate fixed cost — poor trade while
the concurrency ceiling is contested. The shard count becomes a one-line
matrix edit if the suite set doubles, which is the absorption property the
ceiling treadmill never had.

### Per-leg fixed cost (ADR-238's objection, measured not assumed)

Checkout (fetch-depth:0 + tags) 12 s, setup-terraform ~10 s, cloud-init
install ~20 s, nftables install ~15 s, docker assert ~2 s, misc ~30 s →
**~90 s per leg**, measured from run 36037220776's step timings and the
recorded setup figures in the ceiling block. Reported in the PR body per the
issue's acceptance criterion; break-even is immediate (K=4's duplicated fixed
cost ≈ 4×90 s = 6 min aggregate vs ~19 min of wall-clock saving).

### Ordering invariants that must survive the restructure

- `docker info` assert must precede the runner invocation on **every leg**
  (the runner header documents this as the ordering invariant for the five
  docker-consuming suites).
- The toolchain installs (terraform, cloud-init, nftables) precede the runner
  on every leg — 9 suites call terraform, 1 calls cloud-init, the nftables
  gate needs nftables.
- `fixtures-validate-infra-templates.sh` sits in this job precisely because
  it installs terraform + cloud-init (`.github/scripts/test/run-all.sh`
  header) — it moves to `deploy-script-tests-fixed`, which carries the same
  toolchain.
- `notify-main-failure` re-keys on `deploy-script-tests-done.result` and adds
  the `cancelled` arm (folds in #8735: a cancelled leg or job must email, not
  go silent — scoped to `github.event_name == 'push'` as it is today).
- `main-health-monitor.yml` runs the same runner unsharded (unset
  `SOLEUR_INFRA_SHARD` = full set, unchanged) — only its comment references
  to the 35-min deploy-script-tests budget and the derived-count prose are
  updated to the new structure.
- In-flight PR #8738 touches `run-registered-suites.sh` and
  `git-data-runcmd-rehearsal.test.sh`: this change edits the same runner.
  Mitigation: the runner edits are additive sections (shard parse, privileged
  bucket, timeout wrapper) appended near the derivation block rather than
  rewriting the executor; note the collision explicitly in the PR body and
  sequence after #8738 if it merges first (the branch will need one rebase
  either way — the operator accepted this risk).

### What does NOT change

- Push-to-main coverage: every globbed suite runs on exactly one leg on every
  push — the totality guard asserts it (#6766's full-set requirement).
- Pull_request runs get the same sharded full set (affected-only per-suite
  selection is a deferred alternative — see Alternatives).
- `scripts/test-all.sh`'s nested `TEST_GROUP=infra` invocation and
  `main-health-monitor.yml`'s use of the runner keep working: unset shard env
  = full set.
- The 3 sudo loopback suites still execute in CI, still under `sudo bash`,
  still privileged-visible at the call site.

### Implementation Phases

#### Phase 0 — Verify premises and freeze the measurement

- Re-pull per-step durations for the last ≥5 green `deploy-script-tests`
  main-push runs (`gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs`),
  confirm the LPT table above still holds, and pick K from measured data
  (default K=4).
- Confirm #8744 is still reproducible or already recovered (the fleet went
  green again at 17:51Z on 2026-09-24 — the fix is still required per the
  open issue; a transient recovery is not a fix).
- Deliverable: `knowledge-base/project/specs/feat-one-shot-8736-deploy-script-tests-parallel/measurements.md`
  with the raw step table, the partition simulation, and the per-leg fixed
  cost.

#### Phase 1 — #8744 fixture fix (independent, can land first)

- `apps/web-platform/infra/git-data-ownership.test.sh` (the
  `apt-get update && apt-get install openssh-server openssh-client git` site)
  and `apps/web-platform/infra/git-data-cutover-access.test.sh` (the
  `openssh-server openssh-client netcat-openbsd iproute2 git` site):
  - Route apt output to a fixture log file instead of `/dev/null`; on
    exhaustion print the last ~20 lines before `FIXTURE_APT_FAILED`.
  - Bounded retry: `-o Acquire::Retries=5` plus a 3-attempt loop with
    `sleep 10/30` backoff between update and install; keep the fail-closed
    rc=100 exit and the `CI=true` escalation.
- Audit for sibling unprotected apt-in-container sites (the runcmd rehearsal
  carries at least three `apt-get update/install` pairs inside drive.sh
  heredocs — #8738 is editing that file; apply the same retry+diagnose shape
  there only if #8738 has not landed, else file the remainder).
- Success: forced apt failure (poisoned sources.list in a local docker run)
  produces `FIXTURE_APT_FAILED` with the apt error text; suite reds named.

#### Phase 2 — Runner changes (`run-registered-suites.sh` + its suite)

- Glob derivation (`git ls-files` under `SOLEUR_INFRA_DIR`, preserving the
  `INFRA_WF`/seam discipline for fixtures — add a `SOLEUR_INFRA_GLOB` seam if
  the test seam needs it).
- Privileged bucket list + counted SKIP output.
- `SOLEUR_INFRA_SHARD` parse (fail-closed, unset=full), manifest lookup with
  positional fallback, zero-assignment refusal for a shard owning nothing.
- Per-suite `timeout` wrapper + override map.
- `::error` RED annotation + per-leg timings emission to a caller-provided
  artifact dir.
- Update `run-registered-suites.test.sh` for the new derivation (its T2b/T2d
  derive-vs-expected identities change per #7076's warning) and
  `test-all-infra-coverage-notice.test.sh`/`test-all-killed-classification.test.sh`
  where they pin the old scrape.
- Success: `bash run-registered-suites.sh --list` prints 146-3 = 143
  executable + 3 privileged SKIP; `SOLEUR_INFRA_SHARD=1/4` runs exactly the
  assigned subset; `SOLEUR_INFRA_SHARD=0/4` exits 2.

#### Phase 3 — Workflow restructure (`infra-validation.yml`)

- `deploy-script-tests` → 4-leg matrix (`matrix.leg: [1,2,3,4]`,
  `fail-fast: false`) invoking the runner with
  `SOLEUR_INFRA_SHARD=${{ matrix.leg }}/${{ strategy.job-total }}`; per-leg
  toolchain setup; per-leg `timeout-minutes` re-derived at ~1.4× worst
  measured leg; artifact upload per leg under `if: always()` (NOT
  `if: failure()` — that predicate does not fire when an earlier step carried
  `continue-on-error`, and we want logs on green legs too for the timings
  feed) with distinct names per leg (`infra-suite-logs-leg-<k>`,
  `suite-timings-infra-<k>` — upload-artifact v4 names are immutable per
  run, ADR-238 consequence).
- Verification path: `infra-validation.yml` is `pull_request`-triggered, so
  the PR itself exercises the new matrix end-to-end — no `workflow_dispatch`
  pre-merge testing is needed (or possible for a new workflow).
- `deploy-script-tests-fixed` job carrying the non-globbed items.
- `deploy-script-tests-done` aggregator (`needs` both, `if: always()`, fails
  on any non-success result).
- `notify-main-failure` re-keys on the aggregator + adds `cancelled` (#8735).
- `main-health-monitor.yml` comment updates (the 35-min reference + derived
  set prose).

#### Phase 4 — Gate + guards

- Rewrite `test-infra-suite-registration.sh` to the registration-list
  contract (workflow invokes runner × N legs + glob==derived∪exclusions +
  privileged still invoked + rescoped masking check).
- Extend `test-infra-suite-registration-mutations.sh` with rows per new arm.
- `scripts/regenerate-shard-manifest.py --group infra` support + committed
  `apps/web-platform/infra/suite-shard-legs.tsv` generated from the first
  green sharded run's timing artifacts (or seeded from the Phase 0 step table
  so the first sharded run is already balanced).
- Success: mutation harness drives every new arm red; deleting a suite file
  leaves gate green-by-shrink (glob shrinks with it), adding a suite file is
  green-by-absorption, adding a suite to `apps/web-platform/test/infra/` that
  nothing invokes reds the gate.

#### Phase 5 — ADR + docs + monitor

- New ADR (provisional next-free ordinal — ADR-250 at plan time, re-verified
  against `origin/main` at ship): infra suite registration is filesystem
  glob + justified exclusions; `deploy-script-tests` topology is matrix legs
  × parallel runner; per-suite attribution lives in verdict lines/artifacts,
  not step count.
- Update `run-registered-suites.sh` header (the "cannot drift" claim becomes
  literally true), `ship`/`work` skill references to the registration step
  shape, and `main-health-monitor.yml` comments.
- C4: verified no-impact — see Architecture Decision section.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| **Affected-only per-suite selection on PR runs** (candidate 1) | Deferred | `scripts/lib/test-relevance-paths.sh` covers 4 heavy-suite predicates plus the nested `run-all.sh` runner — there is no per-suite edge index for the 146 infra suites, and building one is its own project (the `test-all.sh --affected` machinery landed for the local gate in #8322/ADR-242 at runner granularity). The workflow is already `paths:`-filtered at PR level, and once the run is ~5 min the marginal value of selection is small. Re-evaluate if PR-side latency still hurts after sharding. |
| **Keep all 143 `run: bash` steps; partition via matrix + per-step skip** (e.g., `BASH_ENV` shard filter inspecting the step file's first line) | Rejected | Functionally possible but masking-adjacent: every leg would show ~143 green steps where ~108 did nothing, and the filter is an invisible side-channel on every bash invocation in the job — exactly the "sufficiently creative masking construct" the registration gate disclaims. Nested `bash <sibling>.test.sh` invocations (≥19 suites invoke sibling suites as oracles) force an outer-only rule that is delicate to reason about. The runner model gets the same attribution more honestly via named verdicts + annotations. |
| **N sibling jobs, each with explicit per-suite steps** | Rejected | Keeps step-shape attribution but the partition is by placement: balance decays as suites land wherever the author put them, the YAML boilerplate (checkout/toolchain) is duplicated N ways with no totality guarantee, and registration toil — the thing generating this issue — persists. |
| **Single job, one runner call (K=1, -P4)** | Fallback only | Smallest diff (~500–600 s projected + ~150 s fixed ≈ 10.5–12 min) — misses the <10 min target with no margin and keeps a single long pole. Retained as the rollback shape if matrix leg overhead measures far worse than the ~90 s estimate. |
| **Published fixture image / registry cache for the docker legs** | Rejected (per #7535 D1) | The 2026-08-13 prebake brainstorm measured this: publishing buys ~10 s/run over inline build and owes a trust anchor, fork-PR breakage (no secrets on `pull_request`), and a zot reachability problem needing a prd credential. Inline-build-in-test is the house pattern if apt cost still matters after #8744's retry lands. |
| **Bigger runners** | Out of scope | Explicitly excluded by the issue (separate spend decision). |

## User-Brand Impact

- **If this lands broken, the user experiences:** a false-green or
  silently-red `deploy-script-tests` — the deploy-substrate regression gate —
  letting a broken infra change reach `main` and the production app
  unverified; or a fleet-wide red job that blocks every infra PR for hours
  (the observed #8744/#8688 shape).
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  workflow — a vacuous partition or a de-scoped masking check runs a strict
  subset of the deploy-gate suites while reporting green, so a deploy-path
  regression ships to the production hosts.
- **Brand-survival threshold:** `single-user incident`

*Consistent with the two sibling brainstorms on this job class
(2026-09-21 ci-runner-concurrency, 2026-08-13 prebake-rehearsal-image), which
both resolved `single-user incident` for the deploy-verification pipeline.*

Per the threshold, `requires_cpo_signoff: true` is set in frontmatter and
`soleur:engineering:review:user-impact-reviewer` is the review-time seat.
This pipeline session runs headless, so the sign-off is recorded here as a
plan-time requirement for `soleur:ship` to surface rather than collected
interactively.

## Observability

```yaml
liveness_signal:
  what: "deploy-script-tests-done aggregator green on every infra-touching push/PR; main-health-monitor's 6h TEST_GROUP=infra run as the independent echo"
  cadence: "per push/PR (legs); 6h (monitor)"
  alert_target: "ops email via notify-main-failure (push); monitor-filed GitHub issue (6h)"
  configured_in: ".github/workflows/infra-validation.yml (aggregator + notify jobs), .github/workflows/main-health-monitor.yml"

error_reporting:
  destination: "GitHub check conclusion on the aggregator + 'RED  <path>' lines and '::error file=<path>' annotations in leg logs; notify-ops-email on main-push red/cancelled"
  fail_loud: "aggregator exits non-zero when any leg or the fixed job is failure|cancelled; a suite failure prints RED  <path> and uploads its log"

failure_modes:
  - mode: "a shard leg drops part of its assignment (manifest/env bug)"
    detection: "shard-totality assertions in test-infra-suite-registration.sh red guard-script-fixture-tests (required, merge_group)"
    alert_route: "required check red on the offending PR"
  - mode: "a suite stalls (the #8688 cancel class)"
    detection: "per-suite timeout wrapper -> rc 124 -> 'RED  <path>' naming the suite; leg timeout-minutes as the outer bound"
    alert_route: "leg red -> aggregator red -> notify-main-failure email on push"
  - mode: "apt flake inside a docker fixture (#8744)"
    detection: "FIXTURE_APT_FAILED preceded by the captured apt tail in the suite log"
    alert_route: "RED <suite> names the fixture; ops email on push"
  - mode: "partition silently empty (zero-assignment)"
    detection: "runner refuses exit 2 when a shard owns no suite; gate asserts each of N legs is bound"
    alert_route: "leg red naming the shard env"

logs:
  where: "per-suite .log/.meta under the runner logdir, uploaded as infra-suite-logs-leg-<k> + suite-timings-infra-<k> artifacts; leg console keeps PASS/RED and marker-anchored dumps"
  retention: "GitHub artifact retention default (90 days)"

discoverability_test:
  command: "bash apps/web-platform/infra/run-registered-suites.sh --list"
  expected_output: "registered infra suite"
```

### Follow-Through Enrollment (soak-gated close)

The "≥5 consecutive green main-push runs under 10 min" acceptance criterion
is a post-deploy soak — it cannot be evaluated at merge. Per the
followthrough convention this plan delivers:

- `scripts/followthroughs/deploy-script-tests-legs-8736.sh` — modeled on the
  sibling probe `scripts/followthroughs/ci-leg-durations-8006.sh` (same
  metric class: per-JOB `completed_at - started_at` over qualifying
  `push`-arm runs). Qualifying shape: all K legs of `deploy-script-tests`
  plus `deploy-script-tests-fixed` and `deploy-script-tests-done` present
  with `conclusion=success`; a cancelled/failed/skipped leg contributes
  nothing to the sample — the asymmetry is fail-safe (delays PASS, never
  fabricates one). Exit 0 only when ≥5 qualifying consecutive main-push runs
  show every leg under 600 s. Secrets: `GH_TOKEN` only (Actions API reads).
- The `<!-- soleur:followthrough script=… earliest=<merge+2d> secrets=GH_TOKEN -->`
  directive + `follow-through` label land on the tracking issue at ship;
  both labels verified extant at plan time (`follow-through`,
  `action-required`).

## Hypotheses

Triggered by the `timeout` pattern (job ceilings, apt-mirror stalls). The
relevant layers for the #8744 apt failure, in L3→L7 order:

1. **L3 firewall/egress** — GitHub-hosted runner egress; no host firewall in
   scope. [verified N/A — apt reached the mirror and downloaded at ~525 kB/s
   per the #8744 measurement; egress is not blocked, it is degraded]
2. **L3 DNS/routing** — `apt-get update` resolved and fetched slowly rather
   than failing to resolve. [verified by the same measurement — slow success,
   not a resolution failure]
3. **L7 TLS/proxy** — archive.ubuntu.com over http/https inside the
   `ubuntu:24.04` container; no proxy in the path. [partially verified —
   the retry+diagnose change exists precisely because today's log cannot
   distinguish mirror 5xx from lock/hash errors; the next failure will carry
   the apt stderr tail]
4. **L7 application** — the fixture itself: `>/dev/null 2>&1` on both apt
   calls is the verified defect; rc=100 with no diagnostics. [verified —
   this is what Phase 1 fixes]

## Guard Contract

The deliverable includes guards; matrices are written against the design, not
the implementation.

### Guard 1 — registration-list contract (rewrite of `test-infra-suite-registration.sh`)

**Property.** Every `*.test.sh` under `apps/web-platform/infra/` either runs
through the runner on a `deploy-script-tests` leg or is a justified exclusion
still invoked in `deploy-script-tests-fixed`; the matrix must bind
`SOLEUR_INFRA_SHARD` for every declared leg.

**Assembly.** `git ls-files` over `SOLEUR_INFRA_DIR` (the chokepoint — the
glob is the enumeration, not a list of members), the workflow's
`deploy-script-tests` job slice (matrix bounds + runner invocation), the
`deploy-script-tests-fixed` job slice (privileged invocations), and the
runner's own `PRIVILEGED` list as the exclusion authority.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add an infra `*.test.sh` and patch the runner's glob to skip it | RED (globbed-but-not-derived) |
| 2 | Remove `SOLEUR_INFRA_SHARD` from the matrix `env:` while legs remain | RED (legs exist with no partition binding — every leg would run the full set) |
| 3 | Reduce the matrix leg list from N to N−1 without touching the gate | RED (declared legs < expected coverage shape) |
| 4 | Delete a privileged suite's `sudo bash` step from `deploy-script-tests-fixed` | RED (exclusion waives the runner, never the invocation — the existing INVOKED arm preserved) |
| 5 | Add `if: failure()` to the runner-invocation step | RED (masking check, rescoped to suite-executing steps) |
| 6 | Add a second privileged suite to the exclusion list without a `#NNNN` reason | RED (reasonless-exclusion arm on a second member, not just the first) |
| 7 | Empty `SOLEUR_INFRA_DIR` glob in a fixture (guard's own dispatch — zero members enumerated) | RED (minimum-cardinality guard survives the rewrite) |

**Harness rows.** Mutate the mutation harness itself: a fixture workflow
missing the runner invocation entirely must RED; a fixture where the runner
is invoked with `SOLEUR_INFRA_SHARD=1/1` on a single leg must PASS (a legal
non-sharded shape the contract permits).

**Anchor.** The glob (`git ls-files` against the committed tree) is derived
independently of the workflow being checked — a diff cannot shrink both,
because the glob IS the reference; a weakening must move the exclusion list
(reviewed in the same diff) to pass.

### Guard 2 — shard totality (assertion inside the gate + runner's zero-assignment refusal)

**Property.** The union of the K legs' assigned suite sets equals the derived
execute set exactly — no suite unassigned, none assigned twice, no empty leg.

**Assembly.** The manifest `apps/web-platform/infra/suite-shard-legs.tsv`
(committed derived data), the runner's `_shard`-equivalent partition
chokepoint (one function assigns every derived suite), and the positional/hash
fallback path — the check must cover BOTH assignment paths or a manifest-less
run is unverified.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one manifest row (suite loses its leg) | RED (uncovered member) |
| 2 | Duplicate a row to two legs | RED (double-assignment) |
| 3 | Point the manifest at n=3 while the matrix declares 4 | RED (n-mismatch → fallback announced; the gate asserts the announced mode) |
| 4 | Assign a manifest row to leg 0 (out of 1..N range) | RED (range check on a second member after compliant first rows) |
| 5 | Break the manifest parser so it yields zero assignments (own dispatch) | RED (zero-assignment refusal / guard's cardinality floor) |
| 6 | REORDER: move a suite's row from leg 1 to leg 4 mid-list — totality holds but per-leg identity moves | PASS for totality, RED for a stolen-pin assertion if the pinned heavy-suite leg map is violated (order-vs-membership distinction) |

**Harness rows.** A fixture manifest covering every suite on leg 1 only must
RED (legal file shape, total coverage violation); the empty manifest must RED;
a manifest plus a fallback-eligible suite (absent row, present file) must PASS
only when the fallback is armed — the distinction the guard names explicitly.

**Anchor.** The reference set is the same `git ls-files` glob — independent
of both the manifest and the workflow.

### Guard 3 — per-suite timeout attribution

**Property.** Every suite execution carries a finite bound, and a suite that
exceeds it produces a `RED  <path>` naming the suite — never an anonymous job
cancel.

**Assembly.** The single shim inside the runner's `xargs -P` dispatch (the one
chokepoint all suite executions flow through) + the `name|seconds` override
map for the docker heavies.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture suite `sleep 600` under a 5 s test bound | RED naming the suite, not a job cancel |
| 2 | Remove the `timeout` wrapper from the shim (own dispatch) | RED — a sentinel suite exceeding the bound hangs and is caught by the harness's own outer timeout assertion |
| 3 | Add a second override-map entry pointing at a suite that does not need it | PASS on the run; the map-consistency check (entry names a real derived suite) must not reject a valid-but-unneeded entry |
| 4 | Override entry naming a nonexistent suite | RED (map member ∉ derived set — second-member-class row: the map is checked as a set, not just its first row) |

**Harness rows.** A suite whose real duration is under its bound must PASS
through the same path (a guard that rejects everything is vacuous in the
other direction); `timeout` absent from PATH on the fixture host → runner
fails closed at startup, not per-suite.

**Anchor.** The bound values are committed data next to the runner; the
verdict channel is the existing `.meta` file the runner already writes —
`rc=124` is observed, never fabricated (the runner's observed-rc-only rule).

## Open Code-Review Overlap

2 open scope-outs touch these files:

- **#8735** (`notify-main-failure` misses `cancelled`): **fold in.** The
  restructure rewires that job's `needs:` anyway (aggregator result); adding
  the `cancelled` arm is three tokens and the issue already names the
  trade-off (operator cancels are scoped out by `github.event_name ==
  'push'`).
- **#7942** (`*.mutation.sh` batteries run in no gate): **acknowledge.** Not
  folded in (different files, different fix), but its convention is load-
  bearing here: every new guard/battery file lands as `test-*.sh` under
  `.github/scripts/test/` (auto-globbed by `run-all.sh` →
  `guard-script-fixture-tests`) — never `*.mutation.sh`.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** assessed-inline (this session is a pipeline subagent without a
Task-spawn tool; the semantic sweep ran against the plan content directly
instead of a domain-leader fan-out)

**Assessment:** CI/workflow restructure on the repo's own test substrate.
Engineering-owned end to end; the ADR-238/240 topology is the house pattern
being extended to a second surface. No Marketing/Product/Legal/Sales/
Finance/Support implications: no user-facing surface, no vendor change, no
new spend (matrix legs use the same free-tier runner class; the concurrency
cost is the measured trade-off recorded above), no regulated-data surface.

## Architecture Decision (ADR/C4)

This plan changes the CI matrix topology and the suite-registration contract —
a dispatch boundary every infra consumer depends on — so the decision record
is a deliverable of this plan, not a follow-up.

### ADR

- **Create** provisional ADR-250 (next-free ordinal at plan time; `soleur:ship`
  re-verifies against `origin/main`): *infra suite registration is filesystem
  glob + justified exclusions; `deploy-script-tests` partitions via matrix
  legs × the parallel runner; per-suite attribution lives in verdict lines,
  per-suite logs/artifacts, and `::error` annotations rather than per-suite
  workflow steps.* It extends the ADR-238/ADR-240 shard pattern to the
  infra-validation surface and supersedes the registration-contract
  assumptions embedded in `test-infra-suite-registration.sh`'s header.
- Renumber sweep obligation if the ordinal collides: `grep -rn 'ADR-250'
  knowledge-base/project/{plans,specs}/feat-one-shot-8736-deploy-script-tests-parallel/`
  plus this file.

### C4 views

**No C4 impact.** Enumerated per the completeness mandate against
`model.c4`, `views.c4`, `spec.c4` (all three read):

- External human actors: none new — the change executes on GitHub-hosted
  runners; `github` is already the modeled external system and the
  `contributor` actor's PR-isolation edge is unchanged (the runner consumes
  no secrets and gains none).
- External systems/vendors: none new — no new service, credential, or
  network edge; artifact upload uses the existing Actions surface.
- Containers/data stores touched: none — the suite-log artifacts are
  run-scoped CI output, not a modeled store.
- Actor↔surface relationships: unchanged.

### Sequencing

The ADR is authored in this PR describing the shipped topology directly
(no adopting-status lag — the structure lands atomically).

## Acceptance Criteria

- [ ] `deploy-script-tests` + `deploy-script-tests-fixed` +
      `deploy-script-tests-done` complete under 10 min wall clock on a typical
      main-push run — measured over ≥5 consecutive green runs post-merge, with
      the per-leg durations and the per-leg fixed cost reported in the PR body.
- [ ] A new `apps/web-platform/infra/*.test.sh` file lands with **zero**
      workflow edits and zero ceiling edits: the glob + partition absorb it
      (asserted by a fixture in the gate's mutation harness).
- [ ] Push-to-main coverage unchanged: the union of leg assignments equals
      the derived execute set on every run (totality guard + runner
      zero-assignment refusal).
- [ ] Per-suite attribution: a failing suite produces `RED  <path>`, an
      `::error` annotation naming it, and a retained per-suite log artifact —
      demonstrated in the PR with a deliberately-broken fixture suite.
- [ ] Per-suite timeout bounds exist for every suite (default + override
      map); a stalling fixture suite reds named rather than cancelling.
- [ ] #8744: both git-data fixtures retry apt bounded and print the captured
      apt tail on `FIXTURE_APT_FAILED`; the fail-closed rc=100 arm is kept.
- [ ] #7076: the 6 subdirectory suites derive and run locally; the 3 sudo
      suites are derived-but-not-executed locally (counted SKIP) and still
      invoked under `sudo bash` in `deploy-script-tests-fixed`.
- [ ] #8735: `notify-main-failure` covers `cancelled` on the aggregator for
      push events.
- [ ] `timeout-minutes` re-derived per job at the ~1.4× convention over
      measured legs; the 35-min monolith block is replaced by per-leg
      derivations.
- [ ] `main-health-monitor.yml`'s `deploy-script-tests` references updated to
      the new structure.
- [ ] ADR written and committed in this PR; C4 verified no-impact with the
      enumeration recorded.
- [ ] `bash apps/web-platform/infra/run-registered-suites.sh` (unsharded)
      still runs the full executable set locally — the work/ship exit-gate
      semantics are preserved.

## Test Scenarios

- Given a fixture suite on disk with no manifest row, when a leg runs with
  the fallback partition, then the suite executes on exactly one leg and the
  log announces the fallback mode.
- Given `SOLEUR_INFRA_SHARD=0/4` or `SOLEUR_INFRA_SHARD=abc`, when the runner
  starts, then it exits 2 naming the malformed value — never silently runs
  everything or nothing.
- Given a manifest whose `n` mismatches the matrix leg count, when the gate
  runs, then it reds naming both numbers.
- Given a privileged suite deleted from the fixed job's `sudo bash` block,
  when the registration gate runs, then it reds naming the suite and the
  missing invocation.
- Given a fixture suite forced to exceed its timeout bound, when a leg runs,
  then the suite reports `RED  <path>` with rc=124 recorded in `.meta` and the
  job does not cancel.
- Given forced apt failure inside the ownership fixture, when the runtime arm
  runs, then `FIXTURE_APT_FAILED` is preceded by the captured apt stderr tail
  and the suite reds (CI) / reports the named cause.
- Given `deploy-script-tests` leg 2 fails and legs 1,3,4 pass, when the
  aggregator runs, then `deploy-script-tests-done` is red and
  `notify-main-failure` fires on a push run.
- Given an `if:`/`continue-on-error:` added to the runner-invocation step,
  when the registration gate runs, then it reds; the same keys on the
  artifact-upload step do not red it.

## Success Metrics

- Median `deploy-script-tests` leg wall clock ≤ 6 min; worst leg ≤ 9 min over
  the first 5 green main-push runs.
- Zero ceiling re-derivations required by suite additions for a quarter —
  the structure absorbs growth (the property this plan exists to buy).
- `deploy-script-tests` stays green through the next apt-mirror degradation
  (retry absorbs transients; failure logs name the cause when they don't).
- Zero `UNACCOUNTED`/coverage-gap classes introduced: totality guard green on
  every `guard-script-fixture-tests` run.

## Dependencies & Risks

- **"Does merging THIS alone mutate production?"** No — the diff touches
  `.github/workflows/infra-validation.yml` (whose own `paths:` trigger
  re-runs the validation on merge — self-exercising the new matrix) and
  `apps/web-platform/infra/run-registered-suites.sh` (not a `*.tf`, so
  `apply-web-platform-infra.yml`'s push-triggered apply does not fire; no
  `-target=` surface is touched). No `workflow_run` consumer watches the
  "Infra Validation" workflow conclusion (enumerated: `workflow_run`
  consumers watch `CI`, `Apply web-platform infra`, `Version Bump and
  Release`, `fix-constraints-stage-a` only), so a red leg cannot dark a
  downstream deploy gate.
- **Collision:** draft PR #8738 edits `run-registered-suites.sh` +
  `git-data-runcmd-rehearsal.test.sh`; #8733/#8690/#6778 touch
  `infra-validation.yml`. The runner edits are additive blocks to minimize
  overlap; whichever lands second rebases. Operator accepted this risk.
- **Check-name churn:** legs appear as `deploy-script-tests (1..4)`; the job
  is advisory (absent from `required-checks.txt`), and the aggregator exists
  so that promotion (#6480/#6766) wires ONE name later.
- **Artifact names:** `upload-artifact` v4 names are immutable per run —
  per-leg names are parameterized by `matrix.leg` (ADR-238 consequence).
- **Runner scope creep:** glob derivation widens the *local* execute set by
  the 6 subdir suites (+~19 s measured serial locally, #7076's measurement) —
  acceptable and intended.
- **Manifest drift:** sticky-LPT minimizes regen diff size (ADR-235); the
  fallback keeps a stale/missing manifest a degrade, never a block.
- **Fixed-job load:** the privileged + non-glob items measure ~4–6 min
  combined — under the leg budget; if it outgrows, it shards by the same
  mechanism later.
- **A sub-1% exec-shape risk:** suites that invoke sibling `*.test.sh` files
  as oracles run the sibling in-process — under the runner model that is
  unchanged (the sibling runs wherever the parent runs; it may also run on
  its own leg — duplicate execution is coverage-harmless and was already true
  locally).

## References & Research

- Issue #8736 (the decision-challenge this resolves), #6766 (push coverage /
  required check), #8744 (FIXTURE_APT_FAILED), #7076 (derivation gap),
  #8735 (cancelled-notify gap), #7942 (battery naming convention), #6480
  (required-check promotion), #8322/ADR-242 (affected-selector precedent).
- ADR-238 (TEST_GROUP taxonomy carries matrix topology), ADR-240 (checked-in
  derived-data manifests), ADR-235 (generated-artifact conflict rules),
  ADR-181 (relevance gating), ADR-177/187 (exit-shape taxonomy).
- `knowledge-base/project/brainstorms/2026-08-13-prebake-rehearsal-image-brainstorm.md`
  (never-publish verdict, inline-build pattern, `/run/sshd` caveat).
- `knowledge-base/project/brainstorms/2026-09-21-ci-runner-concurrency-brainstorm.md`
  (20-concurrent-job org ceiling — the cost dimension of K).
- `knowledge-base/project/specs/feat-one-shot-8688-deploy-script-tests-timeout/decision-challenges.md`
  (the standing dissent this plan resolves, with its re-evaluation trigger:
  "two more re-derivations within a quarter" — met).
- Measured run set: `gh api repos/jikig-ai/soleur/actions/runs/36037220776/jobs`
  (1504 s / 168 steps, 2026-09-24).

## Deepen-Pass Gate Record

Executed inline on 2026-09-24 (`Reviewed-Coverage: sequential-fallback` — no
subagent fan-out available in this pipeline; every mechanical gate ran
against the plan file directly).

| Gate | Result | Evidence |
|---|---|---|
| 4.6 User-Brand Impact halt | PASS | `## User-Brand Impact` present; threshold `single-user incident` (valid enum) |
| 4.7 Observability halt | PASS | all 5 fields present with children; `discoverability_test.command` verb `bash` ∈ allowlist, no ssh, <15 s (`--list` is a grep+sort); `expected_output` is the literal `registered infra suite` |
| 4.8 PAT halt | PASS | regex sweep over the plan: zero hits |
| 4.9 UI-wireframe halt | SKIP | no UI-surface file in Files-to-Edit |
| 4.10 Encryption Posture halt | SKIP | Files-to-Edit matches no `.tf`/migration/cloud-init/compose path; prose names no new store class — suite-log artifacts ride the existing `upload-artifact` mechanism inside the Actions boundary (no new cross-component connection) |
| 4.11 Guard Contract halt | PASS | `python3 scripts/lint-guard-contract.py` green: 3 guard entries, all fields non-empty |
| 4.5 Network-outage deep-dive | FIRED | `timeout` trigger matched; Hypotheses section carries the L3→L7 verification record; telemetry emitted |
| 4.55 Downtime halt | SKIP | no host-replace / lock-taking-DDL / serving-surface-swap class in the diff |
| 4.4 Precedent-diff | PASS | every mechanism binds an in-repo precedent: matrix×runner (`scripts/test-all.sh` + ci.yml legs), manifest (ADR-240 + `regenerate-shard-manifest.py`), aggregator (`ci.yml:1498-1560`), soak probe (`scripts/followthroughs/ci-leg-durations-8006.sh`), timeout portability (`memory-backstop.sh:~381`) |
| 4.45 verify-the-negative | PASS | `workflow_run` consumer census (4 consumers, none watch `Infra Validation`); 146-on-disk vs 137-derived re-measured; `test-relevance-paths.sh` confirmed to have no per-suite infra edges |
| 4.45 post-edit self-audit | PASS | dropped symbols (`KNOWN_UNDERIVABLE`, workflow-scrape derivation, the `run: bash` step contract) are referenced only as removal targets |

Quality-checklist results: labels verified (`follow-through`,
`action-required` exist); one rule-ID citation in the plan body —
`wg-use-closes-n-in-pr-body-not-title-to` — verified active in AGENTS.md;
literal sweep consistent (`SOLEUR_INFRA_SHARD` ×12, `suite-shard-legs.tsv`,
`FIXTURE_APT_FAILED`); no external SHA/version citations; no `gh issue
close`/`Closes #N` overreach (`closes:` frontmatter covers #8736/#8744/#7076
— all land IN this PR); markdownlint clean on plan + tasks.md.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails
  deepen-plan Phase 4.6 — filled above.
- The registration-gate rewrite and the workflow restructure must land in the
  SAME PR (the gate reds on the new workflow shape and vice versa); commits
  may be ordered for bisectability but the merge unit is atomic.
- `run-registered-suites.test.sh`'s T2b/T2d compute expectations with the
  same regex as the SUT (#7076 documented this) — under glob derivation those
  arms must derive from `git ls-files` independently, or the test keeps
  passing whatever the derivation does.
- The gate slices YAML with anchored text patterns — a documented
  limitation. New matrix assertions follow the same anchored-parse
  discipline; do NOT widen it into a general YAML lexer in this PR, and
  record the boundary in the gate header comment.
- Run `npx markdownlint-cli2` on the plan and `tasks.md` before the Session
  Summary — lefthook lints both at the work phase's first commit; MD010
  (hard tabs inside quoted command output) and MD032 (list immediately after
  heading/paragraph) are the recurring violations.
- Deferred-item tracking: the affected-only per-suite CI selection
  (Alternatives row 1) needs a tracking issue — search for an existing one
  at ship (`gh issue list --search "affected suite selection"`), file one
  carrying the measured basis if absent.
- `set -uo pipefail` (no `-e`) is this runner's accumulate-then-exit
  convention — match it in new code.
- Do not put the totality assertion inside a matrix leg: a leg cannot see its
  siblings (ci.yml records this exact lesson). The gate lives in
  `.github/scripts/test/` → `guard-script-fixture-tests`, non-sharded.
- The runner summary line stays unprefixed and under PIPE_BUF; the monitor
  greps the `^RED`-anchored and `^\[FAIL\]`-anchored verdict lines — preserve
  the emit shapes verbatim (the space after `RED` is part of the anchor).
