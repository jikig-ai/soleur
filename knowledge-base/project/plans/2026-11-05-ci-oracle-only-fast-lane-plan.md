---
title: "ci: oracle-only fast lane — repair diffs to accept/baseline/edge files skip the full battery"
type: feat
date: 2026-11-05
slug: ci-oracle-only-fast-lane
branch: feat-one-shot-12156-oracle-fast-lane
issue: 12156
closes: 12156
lane: cross-domain
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# ci: oracle-only fast lane — repair diffs to accept/baseline/edge files skip the full battery

## Overview

A repair diff that touches only oracle data — `scripts/ci-pr-affected-audit.accept.tsv`,
`scripts/lib/test-affected-paths.sh`'s `AFFECTED_*_PATHS` edge arrays inside
`scripts/lib/test-affected-paths.sh` — currently pays the full ~2h double battery
(pull_request + merge_group) even though it changes no executable path. The affected
selector proves this twice over: every declared edge set self-includes
`scripts/lib/test-affected-paths.sh` ("THIS FILE"), and a diff to that file triggers the
`runner-changed` fallback, so an edge-array edit selects the entire battery *by design*.

This plan adds a third cost lever beside `push-dedupe` (ADR-276 S2) and `pr-selection`
(ADR-276 S4): an **oracle-only lane**. A new `oracle-selection` job classifies the diff
on `pull_request` AND `merge_group`; when every changed path is inside the oracle
surface, the five heavy `test` legs (test-webplat, test-bun, test-scripts,
test-scripts-heavy, web-platform-build) plus `shard-totality-mutations` skip, while the
`affected-index-ratchet` job and a new `oracle-index-check` validation leg keep gating
the oracle's own integrity. The lane ships **dark and locked** — classifier emits
telemetry only; activation (repo variable + lock removal) is a separate authorized step
after observation on a real merge, per `wg-dark-launch-deploy-gates` and ADR-276 3(d).

## Problem Statement

Measured 2026-11-05 (#12156): two oracle repairs (#12128, #12150) each queued behind
~50-min full merge_group batteries and the #10865 soak stayed paused the whole time.
Each repair cycle costs ~2h of queue+runners for a diff that changes no executable
path. The ratchet job IS the relevant check for such diffs; the full battery's purpose
— interaction coverage of *code* — tests nothing an oracle-data edit can move.

## Proposed Solution

### The oracle surface (the lane's entire authority)

A diff is **oracle-only** when EVERY changed path is one of:

1. `scripts/ci-pr-affected-audit.accept.tsv`
2. `scripts/ci-pr-affected-audit.baseline.tsv` — **REMOVED from the surface at review** (PR5z strict zero: the only possible diff is a `baseline-reintroduced` alarm shape; must pay the full battery)
3. `scripts/lib/test-affected-paths.sh` — **AND** every changed line lies inside an
   `^AFFECTED_[A-Z0-9_]+_PATHS=(` … `^)` array extent, computed in BOTH the base and
   head images (so adding or deleting a whole array block still classifies — PR
   #12150's repair declares a new array). Any hunk line outside those extents
   (`ALWAYS_ON_SUITES`, `_CLOSURE_LEAF_*`, `AFFECTED_CONSUMED_EDGES`, comments,
   functions, any code) disqualifies the whole diff.
4. `knowledge-base/**/*.md` or a root-level `*.md` — the same grammar as
   `ci-pr-selection.sh` stage 1's doc allowlist (`is_doc_path`). Justification: real
   repair PRs carry pipeline planning artifacts (PR #12128's diff included
   `knowledge-base/project/{learnings,plans,specs}/**/*.md`); excluding them would
   make the lane unreachable for its primary use case. See decision-challenges row T2.

**Load-bearing exclusion list** (any one path ⇒ full battery, no lane):
`scripts/ci-pr-affected-replay.py`, `scripts/test-all.sh`,
`plugins/soleur/scripts/lint-ratchet.py`, `.github/workflows/ci.yml`,
`scripts/lib/**` other than the in-extent edit above — i.e., every member of the
ratchet's own `RATCHET_ORACLE` set that is *code* (`ci-pr-affected-replay.py:1758`)
plus the workflow and runner. Sentinel-pinned (Guard 1/3).

### Architecture

Mirrors `pr-selection`'s contract (`.github/workflows/ci.yml:365`, driver
`scripts/ci-pr-selection.sh`) — same fail-closed output discipline, same
cost-lever-fails-one-direction-only shape — as a NEW driver, not an edit to the S4
driver (S4 is scoped pull_request + doc-only diffs and is still activation-locked;
this is a different lever, #12156 "Lever A companion").

- **`oracle-selection` job** — `if: (pull_request || merge_group) && vars.CI_ORACLE_LANE != ''`,
  `continue-on-error: true`, parallel root (no `needs:`; `timeout-minutes` alone on its
  line per the release-workflow budget awk constraint), `contents: read`, checkout
  `fetch-depth: 0`, drives `scripts/ci-oracle-lane.sh`. Outputs: `oracle_only`,
  `active`, `skip_legs`, `head_sha`, `base_sha`. While `ORACLE_LANE_LOCKED=1` in the
  driver, `active` never becomes `true` — the job annotates `would_skip` only (dark).
  Inputs env-only: `EVENT_NAME`, `SWITCH` (vars.CI_ORACLE_LANE, exact `on`),
  `PR_HEAD_SHA`/`HEAD_REPO` (pull_request) or `MERGE_GROUP_HEAD_SHA`/
  `MERGE_GROUP_BASE_SHA` (`github.event.merge_group.{head,base}_sha`, the shape
  `pr-quality-guards.yml:576-577,734,747-748` already uses), `RUN_ATTEMPT`.
  - pull_request: validate the merge-ref two-parent shape (HEAD^1 base, HEAD^2 head)
    as `ci-pr-selection.sh` does; same-repo head, attempt 1, ≤500 files, M/A/D only,
    modes {000000,100644,100755}, printable ASCII, no `::`/`,` in paths.
  - merge_group: diff `base_sha..head_sha` covers the whole queued batch — an
    oracle-only batch takes the lane, anything else fails closed (correct: a batch
    containing a code PR is not oracle-only). Same attempt-1 rule.
- **Skip set** — `skip_legs` ⊆ {test-webplat, test-bun, test-scripts,
  test-scripts-heavy, web-platform-build}; each leg's `if:` gains the same
  `!(… && needs.oracle-selection.outputs.active == 'true' && <head-bound> &&
  contains(format(',{0},', needs.oracle-selection.outputs.skip_legs), ',<leg>,'))`
  conjunct the S4 legs already carry, event-agnostic via
  `github.event.pull_request.head.sha || github.event.merge_group.head_sha`.
  `shard-totality-mutations` (not in `test`'s needs, ~10.7 job-min) gains
  `needs.oracle-selection.outputs.oracle_only != 'true'`.
- **NOT skipped**: `encryption-posture` (cheap, keeps the aggregator loop honest),
  `e2e` (required context; `probe-merge-group-coverage.sh` accepts only absent /
  event-independent / positively-named merge_group `if:` terms, and a skip conjunct
  cannot satisfy that — e2e keeps running, ~4.2 min), every guard/lint job,
  `affected-index-ratchet` (already `pull_request || merge_group`), `pr-selection`,
  `draft-light`, `push-dedupe`.
- **`oracle-index-check` job** (new) —
  `if: ${{ always() && !cancelled() && (github.event_name == 'pull_request' || github.event_name == 'merge_group') }}`,
  `needs: [oracle-selection]`, joins `test`'s `needs:` and `entries[]`. The
  `always()` conjunct is a CPO sign-off condition (O1): `oracle-selection` is
  var-gated, so a literal `pull_request || merge_group` `if:` would be
  needs-skip-propagated while `CI_ORACLE_LANE` is unset and wedge `test`'s
  `needs:`/`entries[]` loudly; `always()` defeats the propagation and a
  skipped/empty `oracle_only` output reads as `not-oracle-only`. When
  `oracle_only == 'true'` it runs the oracle-validation manifest
  (`scripts/ci-oracle-lane-suites.txt`: label + argv lines run serially) and its
  result gates via the aggregator; otherwise it prints `not-oracle-only` and exits 0
  in under a minute. On merge_group this is what blocks a malformed oracle edit.
  Manifest membership (default, decision-challenges T3): every registration whose
  SUT is the oracle/selector machinery —
  `scripts/lint-orphan-test-suites` (the AFFECTED_*_PATHS census authority),
  `scripts/test-all-affected-{a,b,c,d}`, `scripts/test-all-group-affected`,
  `scripts/test-affected-derive`, `scripts/test-affected-derive-cache`,
  `scripts/test-affected-kb-consumers`,
  `plugins/soleur/test/ci-pr-affected-replay-{a,b,c}`,
  `scripts/ci-pr-selection`, `plugins/soleur/test/ci-pr-affected-preactivation.test.sh`
  (enumerate-exact label — it registers via the `plugins/soleur/test/*.test.sh`
  SUITE_GLOB, no `run_suite` line, so `test-all.sh --enumerate` prints the
  `.test.sh` filename; CTO T3). The file also carries a committed, commented
  **exclusion list** naming the evaluated candidates and why each is out:
  `lint-orphan-test-suites-mutations-{a,b}` (SUT is the linter's detection corpus,
  not repo state), `test-all-orphan-log-retention` (known flake per ADR-276
  amendment 2026-10-16 item 5), `affected-tests.test.sh`,
  `affected-tests-pool-default.test.sh`, `audit-suite-reads`,
  `tests/scripts/lint-ratchet`, `pre-push-ratchet-lane`, `ci-path-gating.test.sh`
  (adjacent machinery, not the oracle/selector SUT). Membership comment notes the
  root `*.md` surface admits `AGENTS.md`/`CLAUDE.md` edits — covered by the
  rule-corpus lints (CTO T2).
- **`test` aggregator** — `needs:` gains `oracle-selection` and `oracle-index-check`;
  `entries[]` gains `oracle-index-check`; a second named tolerance
  **ORACLE-ONLY-SKIP**: `EVENT_NAME` in {pull_request, merge_group},
  `ORACLE_ACTIVE == 'true'`, `ORACLE_HEAD_OK == 'true'` (head bound to the event's
  own head SHA), `ATTEMPT == '1'`, `SKIP_LEGS` matching a five-name regex allowlist,
  leg named by delimited match — the same conjunct set as PR-AFFECTED-SKIP
  (`ci.yml:2173-2188`), extended to merge_group. The extractor suite
  `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` is extended to cover it.
- **`push-dedupe` proof tightening** — its elide proof today requires only the
  merge_group run's `test` job conclusion == success (`ci.yml:225-226`). An
  oracle-reduced merge_group green would otherwise elide the push run and main would
  never see a full battery for that SHA. Extend the jobs check: all SIX skippable
  legs — the five heavy legs PLUS `shard-totality-mutations` (every leg the lane
  can skip; CTO T4) — must conclude `success` (a `skipped`, absent or malformed
  entry → `elide=false`, fail closed). Update `scripts/ci-push-dedupe.test.sh`
  accordingly. The sentinel pins the proof's leg-name set in BOTH directions:
  a new skippable leg requires editing the driver allowlist, the aggregator regex
  AND this proof in the same diff.
- **Kill-switch + lock** — repo variable `CI_ORACLE_LANE`, accepted value exactly `on`
  (ADR-276 3(c) shape; compared in bash, not the Actions `==`). Activation lock:
  `readonly ORACLE_LANE_LOCKED=1` in the driver, the `PR_AFFECTED_LOCKED` analogue;
  removed by a later, authorized activation PR after the observation window.
- **Sentinel suite** — `scripts/ci-oracle-lane.test.sh`, registered
  `run_suite "scripts/ci-oracle-lane"` in `scripts/test-all.sh` with edge array
  `AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS` in `scripts/lib/test-affected-paths.sh`.
  Mirrors the `ci-pr-selection.test.sh` harness shape: git-fixture diffs driven
  through the real driver, output-grammar pins, mutation battery over the surface
  and the wiring, aggregator-arm extraction check.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Extend `ci-pr-selection.sh` with an oracle stage-1 arm | Rejected — S4's driver is deliberately pull_request-scoped and doc-only, still activation-locked; the merge_group arm needs different payload plumbing and a different authority record. A separate driver keeps the levers independently switchable and independently revertible. |
| Skip `test-scripts` too, no validation leg | Rejected — the census lints (`lint-orphan-test-suites` et al.) live inside `test-scripts` shards; skipping all legs leaves the oracle's own edit unvalidated on the queue path. The issue says "run the ratchet itself plus the census lints" — `oracle-index-check` is the census home. |
| Skip e2e as well | Rejected — `e2e` is a standalone required context; `probe-merge-group-coverage.sh` fails a required context whose merge_group `if:` is gated inside `!(…)`. It is also cheap (~4.2 min). |
| Lane without docs in-surface | Rejected — every pipeline-generated repair PR carries `knowledge-base/project/{plans,specs,learnings}/**/*.md`; a strict oracle-only surface would never fire for its actual workload (measured: PR #12128's file list). |
| Ship the lane armed | Rejected — `wg-dark-launch-deploy-gates` + ADR-276 3(d): the lever dark-launches (telemetry only) and is observed on a real merge before it gates. |

## Research Insights

**Premise Validation** — #11556 (epic), #10865 (soak tracker), #10448 (index
completion) all OPEN as cited; #12128 merged (evidence repair, file list verified:
`accept.tsv` + `test-affected-paths.sh` + KB planning `.md`s); #12150 OPEN (same
repair shape, declares a NEW `AFFECTED_*` array — the new-array case is required).
All cited files exist on `origin/main`. Collision precheck: PR #12166 is this
branch's own pipeline draft, not a duplicate; foreign `test-all.sh` processes belong
to unrelated worktrees.

**Property List** — P1: oracle-only diffs skip the `test` shard battery on
pull_request. P2: the same reduced set applies on merge_group. P3: the reduced set
still runs the ratchet + census lints (oracle edits remain gated). P4: the lane can
never fire on a code diff — the exclusion list is load-bearing; every unknown fails
to the full battery. P5: activation is staged, observable, reversible (dark launch,
kill-switch, lock). P6: repair-cycle wall time drops from ~2h toward ~10–15 min.

**Cut List** — none. Every proposed mechanism maps to a property; no existing
mechanism covers oracle-only diffs (S4's lane is doc-only, pull_request-only, and
still activation-locked with `CI_PR_AFFECTED` unset — verified `gh variable list`).

**Value quantification** — the saving claim is measured, not asserted: latest full PR
baseline 164.4 job-min of which 119.2 test-scripts (ADR-276 measurement,
2026-10-12); oracle repairs measured at ~50 min merge_group wall + PR run
(#12156 body, 2026-11-05). Reduced set ≈ ratchet (~3.4 min, runbook) + one
validation leg (≤ ~10–20 min bounded) + cheap guards + e2e (~4.2 min) → order
~15–25 job-min and ~10–15 min wall.

**Key code anchors** — `.github/workflows/ci.yml:334-468` (pr-selection + ratchet
jobs), `ci.yml:1296,1395,1433,1672,1765,2306` (leg `if:`s), `ci.yml:2090-2292`
(aggregator + PR-AFFECTED-SKIP arm), `ci.yml:154-261` (push-dedupe proof),
`scripts/ci-pr-selection.sh` (driver contract, output grammar, trigger list),
`scripts/test-all.sh:2757-3114` (`_aff_runner_class` registration-only classifier —
the hunk-parsing precedent for the array-extent check),
`scripts/lib/test-affected-paths.sh:68-77` (self-inclusion + runner-changed),
`scripts/ci-pr-affected-replay.py:1748-1761,1898-1900` (`RATCHET_ORACLE` — the
lane's machinery members are added to this set so the ratchet's `oracle-inputs-changed`
notice covers lane-machinery diffs; doc-path surface members are intentionally not in it),
`scripts/probe-merge-group-coverage.sh` (merge_group `if:` constraint),
`scripts/required-checks.txt` (required-context inventory — unchanged).

**Reconciliation — issue vs. codebase** — the issue says "detect-changes/affected
plumbing already enumerates paths; one workflow branch + a sentinel test". Reality:
the plumbing exists but the merge_group arm is a deliberate ADR-276 Decision-5
boundary ("merge_group may not select"), so the plan carries an ADR amendment, a
second aggregator tolerance, a validation leg, and a push-dedupe tightening beyond
"one workflow branch". Fix-size stays medium but the plan names the full surface.

**Applicable learnings** — census-over-enumeration for the manifest; a guard that
cannot be driven red is vacuous (Guard Contract matrices below); the
registration-only carve-out is the precedent for content-aware runner-diff
classification; `2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree`
(head-vs-merge verdicts); `2026-09-19-githubs-merge-ref-runs-your-prs-own-defect-against-it`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a misclassified code diff takes the
  lane, the required `test` check reads green on a skipped battery, and a user-facing
  regression merges to production with no full-battery run anywhere on its path.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the skip
  decision itself — a reduced run read as full coverage (same artifact family as the
  S4 brainstorm's `single-user incident` declaration).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one wrong classification = one regression
  shipped to a user before any gate could read it — the same tier the path-aware
  gating brainstorm (2026-10-12) declared for the identical artifact (`test`
  aggregator + ci.yml).

`soleur:engineering:review:user-impact-reviewer` runs at review time
(`plugins/soleur/skills/review/SKILL.md` conditional block). CPO sign-off is required
at plan time; headless run — recorded as operator item O1 in decision-challenges.md.

- The one user-visible artifact added while dark: `oracle-index-check` runs as a permanent green check row on every pull_request/merge_group (always() + !cancelled(), needs:[oracle-selection]) — a new always-on member of `test`'s closure and therefore a new permanent failure surface (a job-level fault there reds `test` on every PR), accepted because a lane-eligible diff must never weaken its own validation and the job no-ops in under a minute on non-oracle diffs.

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_ORACLE_LANE notice line emitted by the oracle-selection job on every pull_request/merge_group run while CI_ORACLE_LANE is set; a missing line on a set variable means the classifier died before emitting"
  cadence: per CI run
  alert_target: "job annotation (::notice title=ci-oracle-lane::) + step summary; the #10865 observation-window probe counts lane decisions"
  configured_in: ".github/workflows/ci.yml (oracle-selection job) + scripts/ci-oracle-lane.sh emit_notice"
error_reporting:
  destination: "CI job log + ::error annotations on the oracle-index-check job"
  fail_loud: "oracle-index-check concludes failure when a manifest suite reds; aggregator verdict line prints ORACLE-ONLY-SKIP tolerance with the tolerated leg list"
failure_modes:
  - mode: "classifier misclassifies a code diff as oracle-only (worst case)"
    detection: "sentinel mutation battery (RED rows) + the dark phase's would_skip telemetry audited before activation + the activation ADR amendment's exit criterion"
    alert_route: "CI check failure on the sentinel suite; pre-activation audit report on #10865"
  - mode: "lane fires but validation leg is silent (manifest vacuous)"
    detection: "Guard 4 — manifest↔registration parity assertion + non-empty floor in the sentinel"
    alert_route: "oracle-index-check step exit code inside the `test` aggregator"
  - mode: "merge_group batch mixes an oracle PR with a code PR"
    detection: "batch diff is not oracle-only → full battery (fail-closed by construction)"
    alert_route: "n/a — the absence of the lane is the correct verdict"
logs:
  where: "oracle-selection job log + step summary; ratchet job log"
  retention: "GitHub run-log retention (90 days)"
discoverability_test:
  command: "grep -c 'oracle-selection:' .github/workflows/ci.yml"
  expected_output: "1"
```

## Guard Contract

### Guard 1 — oracle-surface classifier

**Property.** `oracle_only=true` is emitted only when every changed path is inside the
oracle surface AND every changed line in `scripts/lib/test-affected-paths.sh` lies
inside an `AFFECTED_*_PATHS` array extent; every other diff is full battery.

**Assembly.** The single diff-listing chokepoint in `scripts/ci-oracle-lane.sh`
(every changed path flows through one per-path loop — there is no second classifier
call site), the `AFFECTED_*_PATHS` extent checker (base and head images), the
doc-allowlist predicate (identical grammar to `ci-pr-selection.sh:185-192`), the
trigger/exclusion literal set, the arm block, and the output-grammar revalidation at
the final printf.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Diff contains `scripts/ci-pr-affected-replay.py` + `accept.tsv` | RED (no lane) |
| 2 | Diff contains one oracle path + any path outside the surface (`scripts/test-all.sh`, `.github/workflows/ci.yml`, `scripts/foo.sh`) | RED (no lane) — second member defeats it |
| 3 | Hunk in `test-affected-paths.sh` outside `AFFECTED_*_PATHS` extents (`ALWAYS_ON_SUITES`, `_CLOSURE_LEAF_*`, a comment) | RED (no lane) |
| 4 | Guard's own dispatch: classifier aborts / diff unparseable / zero paths checked but reports oracle | RED — fail-closed defaults stand |
| 5 | Harness: sentinel asserts lane on an EMPTY surface membership (vacuous classifier) | RED |
| 6 | Must-PASS non-canonical: accept.tsv + `knowledge-base/project/specs/x/y.md` + a NEW `AFFECTED_*_PATHS` block, paths in non-sorted order | PASS |

**Anchor.** The surface and exclusion lists are committed literals in the driver; a
one-commit weakening must edit the driver AND defeat the sentinel — the sentinel pins
the literal set and every mutation row is exercised against the real driver over
throwaway git fixtures.

### Guard 2 — `test` aggregator ORACLE-ONLY-SKIP tolerance

**Property.** A `skipped` heavy leg is not a `test` failure only under the exact
named conditions: event ∈ {pull_request, merge_group}, `ORACLE_ACTIVE == 'true'`,
head bound to the event's own head SHA, attempt 1, leg named in a well-formed
five-name `skip_legs` list.

**Assembly.** The single aggregation loop in the `test` job (`ci.yml:2167-2292`) —
the only chokepoint that reads the six leg results; `entries[]`, the tolerance
preamble, the `tolerated` membership check, and the `oracle-index-check` leg
(always-required success, never tolerable).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Leg skipped with `active` ≠ `true` (empty outputs) | RED — `SKIPPED — the leg did not run` + fail=1 |
| 2 | `skip_legs` names a leg outside the five-name allowlist (`test-scripts` mislabeled, `encryption-posture`, `e2e`) | RED — regex is the allowlist |
| 3 | Head SHA bound to a different value than the event's head (payload vs output mismatch) | RED |
| 4 | Re-run (`run_attempt > 1`) with cached outputs | RED — skip tolerated only on attempt 1 |
| 5 | Event `push`/`workflow_dispatch` with identical other inputs | RED — event term required |
| 6 | Harness: `oracle-index-check` skipped while heavy legs tolerated | RED — validation leg is never in the tolerable set |
| 7 | Must-PASS non-canonical: merge_group + active + head bound + two-leg skip | PASS |

**Anchor.** The arm lives inside the repo's most load-bearing required check;
`plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` extracts and EXECUTES the
body over synthetic result triples — extending that suite is a required deliverable.

### Guard 3 — push-dedupe elide proof

**Property.** A merge_group run whose green `test` rests on ORACLE-ONLY-SKIP
tolerated skips must NOT elide the push run — the post-merge full battery stays the
oracle's post-merge backstop.

**Assembly.** The single proof step in `push-dedupe` (`ci.yml:214-231`): the runs-API
lookup, the jobs-API fetch, and the `test`-success count; the elide output and every
gated job's `!= 'true'` comparison.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Merge_group run green with any heavy leg `skipped` | RED → `elide=false` |
| 2 | Jobs API returns no `test` success record | RED → `elide=false` (already covered; keep as control) |
| 3 | Proof's own dispatch: empty/malformed jobs payload | RED → `elide=false` |
| 4 | Must-PASS non-canonical: all six legs `success`, different job ordering | PASS → `would_elide=true` |

**Anchor.** The proof is the only artifact the push arm trusts; the elide decision
consumes the merge_group run's own job conclusions — the sentinel replays both
shapes through the real step body.

### Guard 4 — oracle-index-check manifest parity

**Property.** On an oracle-only run the validation leg executes every manifest
member, and every manifest member is a live `run_suite`/SUITE_GLOB registration —
a vacuous or stale manifest can never pass. The pin is BI-DIRECTIONAL (CTO T3):
manifest ≡ the declared oracle-SUT registration set minus the committed exclusion
list, so a NEW oracle-machinery registration cannot silently escape the leg.

**Assembly.** `scripts/ci-oracle-lane-suites.txt`, the job's runner loop (the one
chokepoint the manifest flows through), `test-all.sh --enumerate` as the
registration authority, and the sentinel's parity assertion.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Manifest entry that is not a live registration | RED |
| 2 | Empty manifest (0 members) — guard's own dispatch | RED |
| 3 | Second member: manifest drops `lint-orphan-test-suites` while keeping others | RED — census authority is required, not optional |
| 4 | Job runs manifest but swallows a suite's non-zero exit | RED — exit codes propagate into the leg verdict |
| 5 | Must-PASS non-canonical: manifest member list in a different order | PASS |

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`
with a dated `## Amendment 2026-11-05 (oracle-only fast lane, #12156)` — a **new**
stage amendment, not a new ADR. Per CTO T1 the amendment narrows **both**
invariants the lane carves: Decision 5's proposed `merge_group may not` statement
AND Decision 2's ADOPTING guardrail ("the `merge_group` run executes the full
battery against the candidate tree") — naming only Decision 5 would leave
adopting text asserting an invariant the code no longer holds, the exact drift the
append-only convention exists to prevent (S2's "named exception" to Decision 2 is
the precedent shape). The amendment names: the lever, kill-switch `CI_ORACLE_LANE`
(exact `on`), the activation lock, the **scope bound** (oracle data only — not
precedent for content-based merge_group selection), the dark-launch exit
criterion (classifier `would_skip` telemetry audited on ≥1 real oracle repair
merge — a BLOCKING exit criterion, not advisory, per the T1 dissent), the
push-dedupe tightening, the consumer record per Decision 3(a) — consumers taught
vs blind: `admin-merge-ready.sh`/`ci-head-verdict.sh` were never taught the
reduced-run read and that residual is recorded explicitly — the census/probe link
for Decision-3(e) minutes reporting, and the note that an oracle-lane run must
NEVER carry the `[full]` run-name marker when S4 PR C ships it (the marker
asserts a full battery ran). `amended_by:` pointer to this change; ADR-262 gets a
one-line pointer only if its admission-rule text requires it (check at write time
— the oracle lane uses job-level `if:` gating, not the ADR-262 decline
mechanism).

### C4 views

No C4 impact. Checked against `model.c4`/`views.c4`/`spec.c4` read at plan time:
the change adds no external human actor, no external system/vendor, no new
container or data store, and changes no actor↔surface access relationship — it is
an internal change to an existing CI workflow's job gating (C4 does not model
intra-workflow jobs).

### Sequencing

The amendment lands in THIS PR describing the target state with the lever dark and
locked (`status: adopting` semantics for the lane arm); it is not deferred.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "when a PR's entire file list is inside the oracle surface … run the ratchet itself plus the census lints but skip the test/webplat shard battery" | FR-1..FR-5 / Phase 1–2 / `scripts/ci-oracle-lane.sh`, `oracle-selection` + `oracle-index-check` jobs, leg `if:`s | mapped |
| 2 | "On `merge_group` the same reduced set applies" | FR-6 / merge_group arm of `oracle-selection` + aggregator tolerance extension | mapped |
| 3 | "the exclusion list is load-bearing — a lane that also exempts code paths hands every future drift a free pass" | Guard 1 + sentinel `scripts/ci-oracle-lane.test.sh` | mapped |
| 4 | "the `wg-dark-launch-deploy-gates` rule applies if this becomes a gating change: non-blocking first, observed on a real merge before it gates" | FR-7 / kill-switch + activation lock + runbook dark-phase | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| `scripts/ci-oracle-lane.sh` + `oracle-selection` job | "one workflow branch" + "a fast lane for oracle-only diffs" | asked |
| `oracle-index-check` job + manifest | "run the ratchet itself plus the census lints" | asked |
| Sentinel `scripts/ci-oracle-lane.test.sh` | "a sentinel test that the exclusion list stays tight" | asked |
| Aggregator ORACLE-ONLY-SKIP arm | "skip the test/webplat shard battery" — a skipped leg must be tolerated or the required `test` wedges (ADR-276 3(a)) | inferred — justification: the aggregator is the only context that can report a tolerated skip; without it the lane wedges every PR |
| push-dedupe proof tightening | — | inferred — justification: without it an oracle merge_group green elides the push run and main loses the post-merge full-battery backstop (ADR-217/ADR-276 authority chain) |
| ADR-276 amendment | — | inferred — justification: ADR-276 3(g) requires the stage amendment before any switch flips; the merge_group arm narrows Decision 5 |
| Runbook `ci-oracle-lane.md` | — | inferred — justification: the dark phase, activation steps and rollback must be operator-recoverable; every prior lever carries one |
| Consumer verification (battery-owed.sh, admin-merge-ready.sh, monitor-pr-checks.sh, post-merge-monitor.yml) | — | inferred — justification: ADR-276 3(a) requires every consumer of the `test` context be checked so a reduced result is never read as full |
| docs in-surface (KB .md + root .md) | — | inferred — justification: repair PRs always carry pipeline planning artifacts (PR #12128 measured); a strict surface never fires |

### Split Assessment

- Subsystems touched: 3 — `.github`, `scripts`, `knowledge-base`
- Planned files: ~12 | Estimated changed lines: ~700
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (activation is a separate follow-up PR by design, so the
  natural split boundary already exists)

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` (95 issues) against every
planned path.

- #8881 (ci.yml mention) — review record for a merged K-rebalance; unrelated to this
  lane's hunks. **Acknowledge** — no action.
- #7942 ("Two mutation batteries named *.mutation.sh run in no gate") — our sentinel
  is a `.test.sh` registered suite, not a `*.mutation.sh`; same neighborhood.
  **Acknowledge** — the sentinel registers in `test-all.sh` like every other suite.
- #2965, #3374 — unrelated subsystems. None.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline — no Task spawn available in this subagent context;
same assessment shape as the 2026-10-12 S4 brainstorm's Engineering leader, whose
verdict was verified against the repo and applies unchanged to this lever)
**Assessment:** Architectural — the merge_group arm narrows an ADR-276 Decision-5
boundary, so the ADR amendment is a plan deliverable (3(g)); the mechanism mirrors
the S4 driver's fail-closed output contract; the load-bearing risk is the
exclusion list and the hunk-extent check, both pinned by the Guard Contract.
Marketing, Legal, Sales, Finance, Product, Operations, Support: no implications —
internal CI machinery lever, no user-facing surface (mechanical UI-surface scan of
Files to Edit/Create: zero matches).

## Implementation Phases

### Phase 1 — classifier driver + sentinel scaffold (RED first)

- Write `scripts/ci-oracle-lane.test.sh` mutation battery FIRST (RED): fixture diffs
  driven through the driver; surface members, every exclusion, hunk-extent arms,
  output grammar, lock, fail-closed defaults.
- Write `scripts/ci-oracle-lane.sh`: defaults-first output block; merge-ref /
  merge_group shape validation; per-path surface check; `git diff -U0` hunk-extent
  check for `test-affected-paths.sh`; `ORACLE_LANE_LOCKED=1`; final grammar-checked
  output block; single `SOLEUR_ORACLE_LANE` notice; EXIT trap always-exit-0.
- Write `scripts/ci-oracle-lane-suites.txt` (label + argv per line).

### Phase 2 — ci.yml wiring

- `oracle-selection` job (both events, var-gated, continue-on-error, no `needs:`).
- Leg `if:` conjuncts on the five heavy legs; `shard-totality-mutations` conjunct.
- `oracle-index-check` job + runner loop over the manifest.
- `test` aggregator: needs, envs, `entries[]`, ORACLE-ONLY-SKIP arm; extend
  `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`.

### Phase 3 — push-dedupe + consumers

- Tighten the elide proof (all six lane-skippable legs `success`); extend
  `scripts/ci-push-dedupe.test.sh`.
- Verify consumers read a reduced `test` correctly: battery-owed.sh,
  admin-merge-ready.sh, monitor-pr-checks.sh, post-merge-monitor.yml (list each
  verdict; edit only if one misreads).

### Phase 4 — registration + docs

- `run_suite "scripts/ci-oracle-lane"` in `scripts/test-all.sh`;
  `AFFECTED_SCRIPTS_CI_ORACLE_LANE_PATHS` in `scripts/lib/test-affected-paths.sh`.
- ADR-276 amendment; runbook `ci-oracle-lane.md` (dark phase, observation,
  activation procedure, rollback); file activation tracking on the #10865 window.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash scripts/ci-oracle-lane.test.sh` exits 0; every mutation-matrix row in the
      Guard Contract drives the named guard RED when applied.
- [ ] A fixture diff of only `ci-pr-affected-audit.accept.tsv` →
      `oracle_only=true`; a `baseline.tsv` touch alone classifies `oracle_only=false` (outside_surface — PR5z strict zero, review-narrowed); same for an
      `AFFECTED_*_PATHS`-only hunk in `test-affected-paths.sh` (incl. a NEW array block).
- [ ] A fixture diff containing `scripts/ci-pr-affected-replay.py`,
      `scripts/test-all.sh`, `.github/workflows/ci.yml`, or
      `plugins/soleur/scripts/lint-ratchet.py` alongside oracle paths →
      `oracle_only=false`.
- [ ] A `test-affected-paths.sh` hunk outside `AFFECTED_*_PATHS` extents
      (`ALWAYS_ON_SUITES`, `_CLOSURE_LEAF_*`, `AFFECTED_CONSUMED_EDGES`, comments) →
      `oracle_only=false`.
- [ ] `oracle-selection` job `if:` is `(pull_request || merge_group) && vars.CI_ORACLE_LANE != ''`;
      `ORACLE_LANE_LOCKED=1` keeps `active` permanently `false` (telemetry-only).
- [ ] `test` aggregator: ORACLE-ONLY-SKIP tolerated only when event ∈ {pull_request,
      merge_group} AND active AND head-bound AND attempt 1 AND the skipped leg is in
      the five-name allowlist; `oracle-index-check` is never tolerable.
- [ ] `bash plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` and
      `bash scripts/ci-push-dedupe.test.sh` exit 0 with the new arms covered.
- [ ] push-dedupe: a merge_group run with any heavy leg `skipped` → `elide=false`;
      all-success run → `would_elide` path unchanged.
- [ ] `bash scripts/probe-merge-group-coverage.sh` still prints
      `merge-group-coverage=OK` (no required context lost its merge_group producer).
- [ ] `scripts/required-checks.txt`, the canonical ruleset JSONs, and
      `infra/github/ruleset-ci-required.tf` are UNTOUCHED — the lane adds no
      required context (`grep -c 'oracle' scripts/required-checks.txt` == 0).
- [ ] `git diff` on this PR's file list stays inside `## Files to Edit` +
      `## Files to Create` + pipeline planning artifacts.
- [ ] ADR-276 carries the dated amendment; runbook exists;
      `actionlint` clean on `.github/workflows/ci.yml`.

### Post-merge (operator — activation, tracked separately)

- [ ] `gh variable set CI_ORACLE_LANE=on` → dark telemetry visible on next runs
      (`would_skip` annotations; no skips while locked).
- [ ] After ≥1 real oracle repair observed, activation PR removes
      `ORACLE_LANE_LOCKED=1` — filed as follow-up (tracked on #10865).

## Test Scenarios

- Given a diff of only `accept.tsv` + one edge-array hunk + two KB
  planning `.md`s, when `oracle-selection` runs on pull_request, then
  `oracle_only=true` and `skip_legs` names the five heavy legs. (integration)
- Given a `test-affected-paths.sh` diff whose hunk adds a member to
  `ALWAYS_ON_SUITES`, when classified, then `oracle_only=false`. (unit)
- Given a `test-affected-paths.sh` diff adding a complete NEW `AFFECTED_*_PATHS`
  block (PR #12150 shape), when classified, then `oracle_only=true`. (unit)
- Given an oracle-only diff re-run (attempt 2), when classified, then
  `oracle_only=false` — re-runs always full. (integration)
- Given a merge_group batch mixing an oracle PR and a code PR, when classified,
  then `oracle_only=false` — combined diff is not oracle-only. (integration)
- Given `ORACLE_LANE_LOCKED=1` and `CI_ORACLE_LANE=on`, when any oracle-only diff is
  classified, then `would_skip` is annotated and `active=false` — the lane is dark.
  (integration)
- Given the variable unset, when a run starts, then `oracle-selection` is skipped
  and every leg runs — fail closed. (integration)
- Given an oracle-active merge_group run, when `test` aggregates, then tolerated
  legs print ORACLE-ONLY-SKIP and `oracle-index-check` must be `success`. (unit —
  extractor suite)
- Given an oracle merge_group green, when push-dedupe evaluates the push run, then
  `elide=false`. (unit — step-body replay)
- Property: for ANY generated diff fixture, `oracle_only=true` implies every path is
  in-surface and every `test-affected-paths.sh` hunk is in-extent — a property-based
  sweep over shuffled path sets. (unit)

## Success Metrics

- `test`-leg job-minutes on an oracle-only run: from ~164 (measured PR baseline,
  ADR-276) toward ≤ ~25 including the validation leg — ≥ 60% reduction, reported
  via the Decision-3(e) census on the activation issue.
- Wall time per oracle repair cycle: ~2h → ~10–15 min (issue's bar).
- Escape rate: 0 lane-eligible diffs containing a non-surface path (the sentinel
  makes a wrong classification a CI red, and the dark phase audits `would_skip`
  against real diffs before activation).

## Dependencies & Risks

- **Risk — exclusion-list drift**: a future file joins the oracle-machinery set but
  not the surface → it fails closed (full battery) — safe direction. A future file
  that SHOULD be code but sits inside a surface path is impossible: the surface is
  two literal files + array extents, not a prefix.
- **Risk — hunk-extent parser**: the `-U0` hunk parse is the most delicate piece;
  the registration-only classifier (`test-all.sh:2757-3114`, GLOBENT awk in
  `scripts/lib/affected-glob.sh`) is the in-repo precedent; the sentinel drives the
  real driver over fixtures, not a reimplementation.
- **Risk — merge_group payload shape**: `github.event.merge_group.{head,base}_sha`
  is the documented pair and `pr-quality-guards.yml` already consumes it; a batch
  diff is fail-closed correct by construction.
- **Dependency**: none blocking — S4 stays locked behind `CI_PR_AFFECTED`; this
  lever is independent (`CI_ORACLE_LANE`).
- **Risk — aggregator churn**: the `test` job is the most load-bearing check; the
  tolerance arm mirrors the proven PR-AFFECTED-SKIP shape and its extractor suite.

## References & Research

### Internal References

- Lane precedent: `.github/workflows/ci.yml:334-468`, `ci.yml:2173-2188` — pr-selection job + PR-AFFECTED-SKIP tolerance
- Driver contract: `scripts/ci-pr-selection.sh` — output grammar, fail-closed defaults, trigger list, doc allowlist
- Hunk classification precedent: `scripts/test-all.sh:2757-3114`, `scripts/lib/affected-glob.sh:29`
- Oracle inventory: `scripts/ci-pr-affected-replay.py:1748-1761` (`RATCHET_ORACLE`), `scripts/lib/test-affected-paths.sh:68-95`
- Required contexts: `scripts/required-checks.txt`, `scripts/probe-merge-group-coverage.sh`
- Authority: `knowledge-base/engineering/architecture/decisions/ADR-276-*.md` Decision 2, 3(a)(c)(d)(g)(h), 5; ADR-270 (merge queue, accepted); ADR-242 decision 20 (registration-only carve-out)
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`

### Related Work

- Issues: #12156 (this), #11556 (epic), #10865 (ratchet soak), #10859 (PR3b), #10448 (index), #9729 (S4), #9728 (S3), #9512 (S2)
- Repair evidence: PR #12128 (merged), #12150 (open)
- Brainstorm: `knowledge-base/project/brainstorms/2026-10-12-ci-path-aware-gating-brainstorm.md`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails
  deepen-plan Phase 4.6.
- The activation steps (variable set, lock removal) are deliberately NOT in this
  PR's diff — they are the lane's gating authorization and live in the runbook +
  follow-up PR.
- Do not "simplify" the hunk-extent check to a whole-file path test: a path-level
  test lets a logic edit to `test-affected-paths.sh` take the lane — the exact
  free-pass the issue warns against.

## Enhancement Summary

Deepen-plan run 2026-11-05 (inline — subagent context, no Task spawn; halt gates
executed mechanically):

- Phase 4.6 User-Brand Impact: PASS — section present, `single-user incident`.
- Phase 4.7 Observability: PASS — all 5 fields non-placeholder; probe
  `grep -c 'oracle-selection:' .github/workflows/ci.yml` → `1` (allowlisted verb,
  <15 s, literal expected_output).
- Phase 4.8 PAT sweep: PASS — no hits.
- Phase 4.9 UI-wireframe: SKIP — no UI-surface files.
- Phase 4.10 Encryption Posture: SKIP — no persistent store or new connection.
- Phase 4.11 Guard Contract: PASS — `lint-guard-contract.py` green over 4 guard
  entries; adequacy read: assemblies name chokepoints (diff-listing loop,
  aggregation loop, proof step, manifest runner), not member snapshots; every
  matrix has a dispatch row, a second-member row, a harness row and a must-PASS
  non-canonical row.
- Phase 4.12 Scope Check: PASS — exactly one unfenced `## Scope Check`; all asks
  mapped; every inferred item justified; split assessment derived from the file
  lists (single PR).
- Phase 4.13 Task Design: SKIP — no new workflow file, trigger block or task
  surface (the new jobs fire on existing `pull_request`/`merge_group` triggers).
- Phases 4.4/4.45/4.5/4.55: N/A — no scheduled-work pattern, no SSH/network
  hypothesis, no downtime/cutover (the lane is additive and dark).

### New Considerations Discovered

- `CI_PR_AFFECTED` is unset (verified `gh variable list`) and `PR_AFFECTED_LOCKED=1`
  still stands — S4 never activated; this lane is the first skip lever that can
  actually fire, which raises the bar for the dark phase and the ADR amendment.
- The `[full]` run-name marker is not on `main` yet (S4 PR C unshipped) — the
  amendment records that oracle-lane runs must never carry it when it lands.
- push-dedupe (already `on`) would elide the push run on an oracle merge_group
  green unless the proof requires all six lane-skippable legs `success` — now a named
  deliverable (Guard 3), not a review-time surprise.
- `oracle-index-check` joins `test`'s `needs:` and always runs (sub-minute no-op
  off the lane) rather than being a second tolerated context — keeps the merge
  queue's producer semantics per probe-merge-group-coverage.sh.
