# Tasks — feat: shard deploy-script-tests (plan → work handoff)

Plan:
`knowledge-base/project/plans/2026-09-24-feat-deploy-script-tests-parallel-shards-plan.md`

Execution rules for `soleur:work`:

- Every `## task/<name>` phase is one ordered execution unit; phases are
  dependency-ordered (contract changes land before their consumers).
- Phase 1 (#8744) is independent and MAY land as its own commit ahead of the
  restructure — it unblocks fleet redness regardless of shard progress.
- Phases 2–4 MUST merge atomically in ONE PR (the gate and the workflow
  shape are mutually inconsistent outside it); commit granularity inside
  the PR is free — order commits contract-first.
- `apps/web-platform/infra/run-registered-suites.sh` convention:
  `set -uo pipefail`, accumulate-then-exit — match it.
- Run `npx markdownlint-cli2` on any edited `.md` before committing.

## task/phase-0-measure-and-freeze

- [ ] Re-pull per-step durations for the last ≥5 green `deploy-script-tests`
  main-push runs (`gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs`);
  recompute the sticky-LPT partition for K ∈ {3,4,6}; record the measured
  per-leg fixed cost (checkout + terraform/cloud-init/nftables + docker
  assert).
- [ ] Write
  `knowledge-base/project/specs/feat-one-shot-8736-deploy-script-tests-parallel/measurements.md`
  with the raw step table, partition, and fixed-cost derivation.
- [ ] Choose K (default 4 unless measurements moved) and record the choice
  and rationale in measurements.md.
- [ ] `gh issue view 8744` — confirm the apt flake is still unfixed on main
  (a transiently-green fleet is not a fix).

## task/phase-1-fixture-apt-retry-8744

- [ ] `apps/web-platform/infra/git-data-ownership.test.sh` (the
  `apt-get update && apt-get install` site near `:280`): capture apt output
  to a fixture log file (no more `>/dev/null`); `-o Acquire::Retries=5` plus a
  3-attempt loop with `sleep 10`/`sleep 30` backoff; on exhaustion print the
  last ~20 lines of the captured apt output before `FIXTURE_APT_FAILED`;
  keep fail-closed rc=100 and the `CI=true` escalation.
- [ ] Same shape in `apps/web-platform/infra/git-data-cutover-access.test.sh`
  (site near `:1770`).
- [ ] Audit sibling unprotected apt-in-container sites —
  `git-data-runcmd-rehearsal.test.sh` carries ≥3 (`apt-get update`/`install`
  pairs inside drive.sh heredocs near `:1064`, `:1357`, `:1574`); apply the
  same retry+diagnose shape there ONLY if draft PR #8738 has not landed —
  else file the remainder as a follow-up (collision risk, see plan Risks).
- [ ] RED first: reproduce with a poisoned `sources.list` inside a local
  `ubuntu:24.04` docker run → expect `FIXTURE_APT_FAILED` preceded by the
  apt stderr tail.
- [ ] GREEN: suite reports the named failure cause; CI arm still reds on
  genuine exhaustion.

## task/phase-2-runner-shard-contract

Contract-changing phase — lands before any consumer (Phase 3+4) depends on
the new derivation/env shape.

- [ ] `apps/web-platform/infra/run-registered-suites.sh`:
  - [ ] derivation → `git ls-files "${SOLEUR_INFRA_DIR}/*.test.sh"`
    (git pathspec `*` matches `/`; returns all 146 incl. subdirs). Keep the
    `SOLEUR_INFRA_DIR` test seam; add a glob-seam if fixtures need it.
  - [ ] `PRIVILEGED` bucket (`name|reason|#issue`): the 3 loopback suites;
    derived but not executed — printed as a counted SKIP set; never
    `sudo`'d by the runner.
  - [ ] `SOLEUR_INFRA_SHARD=k/N` env: unset=full set, malformed/out-of-range
    = exit 2 naming the value (mirror the `SCRIPTS_SHARD` parse contract at
    `scripts/test-all.sh` ~348-380). Partition via
    `apps/web-platform/infra/suite-shard-legs.tsv` manifest when present and
    `n` matches; deterministic positional/hash fallback otherwise, announced
    in the log; zero-assignment shard → refuse loudly.
  - [ ] per-suite timeout wrapper in the xargs shim: default budget +
    `name|seconds` override map (rehearsal/cutover/ownership heavies); the
    bounder is resolved once at startup using the `timeout`→`gtimeout`
    portability pattern (`.claude/hooks/memory-backstop.sh` ~381); under
    `CI=true` absence of both is a fail-LOUD startup error; rc=124 → `RED
    <path>`.
  - [ ] `RED` emits `::error file=<path>::suite failed` with the path
    CR/LF-stripped (`${var//[$'\n\r']/}`).
  - [ ] emit per-suite `label<TAB>ms<TAB>verdict` timings (from the existing
    `.meta` fields) to a caller-provided artifact dir.
- [ ] Update the runner header (the "cannot drift" claim becomes literal;
  document PRIVILEGED and SOLEUR_INFRA_SHARD).
- [ ] `apps/web-platform/infra/run-registered-suites.test.sh` — update T2b/T2d
  expectations to derive independently (no shared-regex-with-SUT), add rows
  for: glob pickup of a subdir suite, privileged SKIP counted, shard
  partition disjoint+total over a fixture set, malformed `SOLEUR_INFRA_SHARD`
  → exit 2, zero-assignment refusal, timeout wrapper rc=124 → RED naming.
- [ ] `scripts/test-all-infra-coverage-notice.test.sh`,
  `scripts/test-all-killed-classification.test.sh` — update fixtures pinning
  the old scrape shape.
- [ ] Local check: `bash run-registered-suites.sh --list` prints 143
  executable + 3 privileged SKIP (146 derived).

## task/phase-3-workflow-restructure

- [ ] `deploy-script-tests` → `strategy: { fail-fast: false, matrix: { leg: [1,2,3,4] } }`
  (K per Phase 0); steps per leg: checkout → setup-terraform → install
  cloud-init → install nftables → `docker info` assert (must precede the
  runner step on every leg) → `env: SOLEUR_INFRA_SHARD=${{ matrix.leg }}/${{ strategy.job-total }}`
  `run: bash apps/web-platform/infra/run-registered-suites.sh` →
  `if: always()` artifact uploads `infra-suite-logs-leg-<k>` and
  `suite-timings-infra-<k>` (distinct names — v4 immutability).
- [ ] Per-leg `timeout-minutes` re-derived at ~1.4× worst measured leg with
  the derivation comment preserved.
- [ ] `deploy-script-tests-fixed` job: 3 `sudo bash` loopback steps,
  2 terraform validate blocks, `fixtures-validate-infra-templates.sh`,
  evidence-freshness + systemd-lint + userdata-cap + provenance blocks,
  5 `apps/web-platform/test/infra/*.test.sh` steps,
  `sandbox-canary-regression.test.sh`; own toolchain setup; own ceiling.
- [ ] `deploy-script-tests-done` aggregator: `needs:
  [deploy-script-tests, deploy-script-tests-fixed]`, `if: always()`, exits
  non-zero when any need is `failure|cancelled` — copy the
  `Aggregate shard results` step shape from `ci.yml` (~line 1525) verbatim,
  including the cancelled-vs-superseded leg discrimination (a leg-level
  `timeout-minutes` kill reads `cancelled` with surviving siblings; a
  concurrency cancel reads `cancelled` on all — the aggregator fails on
  either, the diagnostic names which). Guard: extend or mirror
  `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` (it extracts
  and executes the ci.yml body over synthetic result triples) for the new
  job.
- [ ] `notify-main-failure`: re-key on `deploy-script-tests-done.result`,
  add `cancelled` to the disjunction (#8735).
- [ ] `main-health-monitor.yml`: update the 35-min reference + derived-set
  prose; the monitor's runner invocation stays unsharded (unset env = full
  set).
- [ ] `actionlint` the workflow; extract embedded `run:` snippets and
  `bash -c` them (not `bash -n` on the file).

## task/phase-4-gate-and-totality

- [ ] Rewrite `.github/scripts/test/test-infra-suite-registration.sh` to the
  registration-list contract (plan Guard 1): workflow invokes runner × N
  matrix legs with `SOLEUR_INFRA_SHARD` bound; glob == derived ∪ exclusions;
  privileged suites still invoked in `deploy-script-tests-fixed`; masking
  check rescoped (ban on suite-executing steps, allowlist for upload/
  aggregator `if: always()`); delete `KNOWN_UNDERIVABLE`.
- [ ] Extend `test-infra-suite-registration-mutations.sh` with the Guard 1
  and Guard 2 mutation rows from the plan (each ≥3 rows incl. own-dispatch
  and second-member).
- [ ] `scripts/regenerate-shard-manifest.py` — add `--group infra` emitting
  `apps/web-platform/infra/suite-shard-legs.tsv` from `suite-timings-infra-*`
  artifacts; seed the first manifest from the Phase 0 step table so the
  first sharded run is already balanced.
- [ ] Verify RED: each mutation row drives the gate/harness red; verify the
  harness's own rows (missing runner invocation, `1/1` single-leg legal
  shape).
- [ ] Lint: manifest rows ⊆ derived set; `n` in manifest == matrix leg count.

## task/phase-5-adr-followthrough-docs

- [ ] Author ADR (next-free ordinal re-verified against `origin/*` at ship —
  provisional 246): infra registration = filesystem glob + justified
  exclusions; deploy-script-tests topology = matrix × parallel runner;
  attribution = verdict lines + artifacts + annotations.
- [ ] `scripts/followthroughs/deploy-script-tests-legs-8736.sh` +
  `.test.sh` sibling (model on `ci-leg-durations-8006.sh`); directive +
  `follow-through` label land on the tracking issue at ship.
- [ ] Update runner header, `ship`/`work` skill references to the
  registration step shape, `AGENTS.md`-adjacent docs citing the old
  contract (grep `run: bash` contract prose).
- [ ] C4: verify no-impact conclusion still holds (no new actor/system/
  container edge introduced by the final diff).
- [ ] Update `#8736` with the measured per-leg fixed cost + chosen K (the
  issue's required report-back).

## Files to Edit (derived by grep, not enumeration)

- `.github/workflows/infra-validation.yml` (job restructure + notify +
  ceilings)
- `.github/workflows/main-health-monitor.yml` (references only)
- `apps/web-platform/infra/run-registered-suites.sh` + `…test.sh`
- `apps/web-platform/infra/git-data-ownership.test.sh`,
  `git-data-cutover-access.test.sh`, `git-data-runcmd-rehearsal.test.sh`
  (apt fix; rehearsal conditional on #8738)
- `apps/web-platform/infra/suite-shard-legs.tsv` (new, generated)
- `.github/scripts/test/test-infra-suite-registration{,-mutations}.sh`
- `scripts/regenerate-shard-manifest.py` (+ its test surface)
- `scripts/test-all-infra-coverage-notice.test.sh`,
  `scripts/test-all-killed-classification.test.sh`,
  `scripts/check-cloudflare-token-drift.test.sh` (consume the
  `SOLEUR_INFRA_DIR`/`INFRA_WF` seams — grep-verified consumers)
- `scripts/followthroughs/deploy-script-tests-legs-8736.sh` (new) + test
- `knowledge-base/engineering/architecture/decisions/ADR-0NNN-*.md` (new)
- Sweep before committing: `git grep -ln 'run: bash apps/web-platform/infra\|deploy-script-tests' -- '*.sh' '*.ts' '*.md' .github/` — every hit is
  either updated or explicitly left (record why).
