# chore: bound the release job's runtime, and parity-test the C4 edges' embedded counts

```yaml
issue: 7160
lane: cross-domain            # no spec.md exists for this branch — TR2 fail-closed default
brand_survival_threshold: none
requires_cpo_signoff: false
type: chore
labels: [type/chore, priority/p3-low, domain/engineering, deferred-scope-out]
branch: feat-one-shot-7160-release-timeout-and-c4-count-parity
plan_revision: v2   # v1 revised after a 2-agent review panel; see §Review Revisions
```

> Spec lacks valid `lane:` (no `knowledge-base/project/specs/feat-one-shot-7160-.../spec.md` exists) — defaulted to `cross-domain` (TR2 fail-closed).

---

## Overview

Two post-MVP follow-ups deferred from the production version-drift alerter (#7091), filed as one
tracker (#7160).

**Deliverable 1** declares a runtime ceiling on the `release` job, closing the gap between the
pipeline's *declared execution ceilings* (today 495 minutes) and the drift checker's 195-minute
`DRIFT_SUSTAINED_THRESHOLD_MIN` — and makes deleting that ceiling fail CI instead of passing
silently.

**Deliverable 2** adds a CI parity test over the counts hard-coded in `model.c4` edge prose, so a
future scheduled-workflow or Resend-emitter addition fails loudly instead of silently staling the
architecture model.

> **The issue's framing is overstated and this plan does not adopt it.** #7160 asks for a
> "strictly *provable* commit-to-deployed bound". No `timeout-minutes` value can deliver that:
> `timeout-minutes` caps a job's **execution**, while the checker's clock starts at the oldest
> undeployed commit's **committer epoch**. The unbounded terms between those two points are
> enumerated in **P8** and are *not* closed by this change. What this change delivers is real but
> narrower: the declared-execution-ceiling term drops 495 → 195, and the delete-the-ceiling
> regression stops being silently green. See §Ceiling Analysis for the honest bound.

Research produced **five premise corrections** that materially change Deliverable 1's shape. They
are recorded in full because the plan's approach turns on them.

---

## Premise Validation

| # | Cited premise | Verified? | Finding |
|---|---|---|---|
| P1 | Issue #7160 is open and unresolved | ✅ HOLDS | `gh issue view 7160` → `state: OPEN`, milestone `Post-MVP / Later`, 4 labels as stated. |
| P2 | `#7142` tracks the general repeat-suppression gap | ✅ HOLDS | Referenced only. No work, no re-file. |
| P3 | "Add `timeout-minutes` to `web-platform-release.yml`'s `release` job" | ❌ **REFUTED — schema-rejected** | See P3. |
| P4 | The bound is **555** minutes (195 + 360) | ❌ **REFUTED — 495** | See P4. |
| P5 | Adding a `release` timeout does not by itself trip B9 | ✅ HOLDS | B9's extractor hard-codes `("await-ci","migrate","verify-migrations","deploy")`; `release` is absent. |
| P6 | The three sketch derivation commands produce the encoded numbers | ✅ HOLDS (all three) | §Verified Derivations. |
| P7 | Adjacent worktree has an open PR on the same files | ✅ HOLDS — **and it collides** | PR **#7206**. §Coordination. |
| P8 | A `timeout-minutes` ceiling makes the commit→deployed bound *provable* | ❌ **REFUTED** | See P8. This is the correction that reframes the whole deliverable. |
| P9 | The existing `RELEASE_PARSE_ERROR` arm is a fail-closed precedent to mirror | ❌ **REFUTED — it is asserted nowhere** | See P9. |

### P3 — `timeout-minutes` is INVALID on the `release` job as it exists today

`.github/workflows/web-platform-release.yml`, `jobs.release`, is a **reusable-workflow caller**
(`uses: ./.github/workflows/reusable-release.yml`). GitHub's schema forbids `timeout-minutes` there.
Measured with the repo's own pinned linter (`actionlint 1.7.7`, the version `ci.yml` pins) against a
synthetic caller:

```
when a reusable workflow is called with "uses", "timeout-minutes" is not available.
only following keys are allowed: "name", "uses", "with", "secrets", "needs", "if",
and "permissions" in job "caller" [syntax-check]
```

**Consequence:** the ceiling MUST be declared on `jobs.release` in
`.github/workflows/reusable-release.yml` (the job whose body begins `runs-on: ubuntu-latest`, with
no `timeout-minutes` today). That file has two callers — see §Blast Radius. Independently confirmed
by review: the same `timeout-minutes: 60` on the *callee* lints clean.

### P4 — the declared-execution bound is 495 minutes, not 555

`release` and `await-ci` both declare **no `needs:`**, so they start in parallel. `migrate` needs
*both*.

| job | `needs` | `timeout-minutes` |
|---|---|---|
| `release` | — | **none (inherits 360)** |
| `await-ci` | — | 60 |
| `verify-doppler-secrets` | — | 10 |
| `migrate` | `[release, await-ci]` | 30 |
| `verify-migrations` | `migrate` | 15 |
| `deploy` | `[release, migrate, verify-migrations, verify-doppler-secrets, await-ci]` | 90 |

```
declared_execution_bound = max(T_release, T_await-ci) + T_migrate + T_verify-migrations + T_deploy
                         = max(T_release, 60) + 30 + 15 + 90
                         = max(T_release, 60) + 135
```

Today `T_release = 360` → **495**, not 555. The issue's 555 treats `release` as *serial* with
`await-ci`; the graph makes them parallel. Alternate paths are dominated (`release→deploy` = 150;
`verify-doppler-secrets→deploy` = 100). `live-verify` and `release-outcome` are strictly
post-`deploy` and do not change the SHA production serves, so they are correctly outside the bound —
confirmed by review against the `needs:` graph.

### P8 — `timeout-minutes` bounds EXECUTION, not the checker's clock

The checker computes drift age from the **committer epoch** of the oldest undeployed qualifying
commit (`scripts/prod-version-drift-check.sh`, `oldest_epoch_from_log`, compared against
`DRIFT_SUSTAINED_THRESHOLD_MIN * 60`). `timeout-minutes` starts when a runner begins *executing* a
job. Between those two instants sit at least three terms that no job timeout caps:

1. **Runner queue wait** — excluded from job duration by construction (`started_at` is pick-up time).
   The measured durations in §Observed Run Durations therefore *understate* wall clock.
2. **Concurrency serialization.** `reusable-release.yml` declares
   `concurrency: { group: release-${{ inputs.component }}, cancel-in-progress: false }`, and
   `migrate`, `verify-migrations`, `verify-doppler-secrets` and `deploy` each declare their own
   groups with `cancel-in-progress: false`. Two merges landing close together **serialize**: the
   second commit's age accrues while the first run holds the group. Every ceiling can be honored and
   the measured age still exceed 195.
3. **Commit-to-workflow-start latency** (push processing, path-filter evaluation).

The suite's own B10 comment already reasons about exactly this coupling ("a job timeout above the
tick interval, combined with `cancel-in-progress: false`, would queue every subsequent tick behind a
wedged run").

**What this means for the plan.** The claim "195 becomes a strictly provable bound" is **false** and
is not made anywhere in this plan. The honest statement, which every AC is written against:

> After this change, the **declared execution ceilings** on the critical path sum to exactly 195 —
> equal to `DRIFT_SUSTAINED_THRESHOLD_MIN`. Queue wait, concurrency serialization, and
> push-to-start latency remain **unbounded and unmodelled**; the threshold's tolerance for them is
> empirical, exactly as it was before this change.

This is still worth doing: it removes 300 minutes of *declared* slack, and (via Phase 2) makes
deleting the ceiling a red CI instead of a silent no-op. It does not close the residual, and the
residual is now named rather than papered over. Bounding queue/concurrency latency is a distinct
problem — **out of scope, tracked as a deferral** (§Deferrals).

### P9 — `RELEASE_PARSE_ERROR` is emitted but never asserted

The existing B8 extractor's `except` arm emits `RELEASE_PARSE_ERROR` — and **nothing in the suite
asserts on that key**. Worse, B9's own guard reads
`"${X_RELEASE_SERIAL_TIMEOUT_SUM:-0}" =~ ^[0-9]+$`, so on a parse failure the sum is unset, coerces
to `0`, and `195 >= 0` **passes**. Instructing /work to "mirror the existing arm" would therefore
mirror a silently-green path. Phase 2 adds a real assertion on the error key instead (AC7).

---

## User-Brand Impact

**If this lands broken, the user experiences:** a production deploy killed mid-flight by a too-tight
`release` ceiling — the merged change never reaches `app.soleur.ai`, surfacing as a red
`release / release` job. This is the failure the issue explicitly warns against ("a wrong ceiling is
worse than no ceiling"), and is why the ceiling is derived from 60 measured runs with 2.5× headroom
over the worst, not from a round number.

**If this leaks, the user's data/workflow/money is exposed via:** nothing — no new data path,
credential, or egress. Deliverable 2 reads tracked files at CI time and writes nothing.

**Brand-survival threshold:** `none`.
*Sensitive-path scope-out:* `threshold: none, reason: the diff is a workflow timeout declaration, a
bash/CI test, and architecture-doc prose — no schema, migration, auth flow, API route, or .sql file
is touched.*

---

## Deliverable 1 — bound the `release` job's runtime

### Observed run durations (measured 2026-08-03)

`release / release`, last **60 completed runs** of `web-platform-release.yml` (54 `success`,
6 `failure`), from the GitHub jobs API. **Runner-queue wait is excluded** (see P8) — these are
execution times only.

| statistic | all conclusions | success only |
|---|---|---|
| max | **24.33 min** | 24.33 min |
| p95 | 11.00 | 11.14 |
| p50 | 9.41 | 9.52 |
| mean | 8.82 | 9.62 |

The 24.33-minute outlier decomposes to one dominant step — **`Build and push Docker image`,
21.72 min** (a cold-cache Docker build), plus 1.53 min for the zot mirror + cosign sign. The
realistic worst case is a cold cache, not a hang.

Second caller, `version-bump-and-release.yml` (`component: plugin`), last 40 completed runs:
**max 0.68 min**, mean 0.58.

### Ceiling analysis — why 60 minutes

Substituting into `declared_execution_bound = max(T_release, 60) + 135`:

| `T_release` | declared bound | vs. threshold 195 | forces a threshold raise? |
|---|---|---|---|
| 360 (today, undeclared) | **495** | +300 | — (today's gap) |
| 90 | 225 | +30 | **yes** |
| **60** | **195** | **equal** | **no** |
| 45 / 30 | 195 | equal | no |

Two constraints meet at 60:

1. **60 is the largest ceiling that costs nothing.** Any `T ≤ 60` is absorbed by the `max(·, 60)`
   term `await-ci` already contributes. The first minute above 60 pushes the declared bound past the
   threshold and forces a threshold raise. So 60 buys the **maximum available headroom for free**;
   30 or 45 would discard headroom for an identical bound.
2. **60 is 2.5× the worst run ever observed** (24.33 min), **5.4× p95**, **2.8× the worst single
   step**, and **88×** the plugin caller's worst run.

It is also the ceiling `await-ci` already declares, so the two parallel arms share one number.

**Inherited condition, stated plainly:** `await-ci 60 + migrate 30 + verify-migrations 15 +
deploy 90 = 195` **already equals** `DRIFT_SUSTAINED_THRESHOLD_MIN` exactly. B9's margin was fully
consumed before this change. Choosing 60 preserves that zero margin rather than creating it — any
future timeout increase *anywhere* on the critical path reds CI immediately. That is B9's intended
one-directional semantic, not a regression this plan introduces.

### Blast radius

`.github/workflows/reusable-release.yml` has exactly two callers (verified with
`grep -rn 'uses: \./\.github/workflows/reusable-release\.yml' .github/workflows/`):

| caller | `component` | worst observed | headroom at 60 |
|---|---|---|---|
| `web-platform-release.yml` (`jobs.release`) | `web-platform` | 24.33 min | 2.5× |
| `version-bump-and-release.yml` (`jobs.release`) | `plugin` | 0.68 min | 88× |

One shared ceiling is safe for both. **Rejected:** adding a `timeout_minutes` workflow input — YAGNI,
pure surface to express one value.

### The B9 extension

Today's extractor sums four jobs read from `web-platform-release.yml` with `int(x or 0)`:

```python
for j in ("await-ci", "migrate", "verify-migrations", "deploy"):
    tot += int((rjobs.get(j) or {}).get("timeout-minutes") or 0)
emit("RELEASE_SERIAL_TIMEOUT_SUM", tot)
```

Two defects, both in the unsafe direction:

- **`release` is absent from the tuple**, so removing the new ceiling would leave B9 silently green.
  Closing that is the point of this phase — the YAML edit alone does not.
- **`int(x or 0)` reads a *missing* timeout as *zero*.** Deleting `deploy`'s `timeout-minutes: 90`
  today drops the computed bound to 105 and B9 stays green. This hole exists for **all four**
  current jobs, not just for `release`.

Replacement — **one uniform rule for all five jobs**, no special case:

```
missing timeout-minutes  ⇒  360   (the GitHub default, for EVERY job on the path)
release_ceiling          =  timeout-minutes of jobs.release in the workflow that
                            web-platform-release.yml's `release` job `uses:`
critical_path            =  max(release_ceiling, await-ci) + migrate + verify-migrations + deploy
```

Applying `360 if absent` uniformly is simpler than a release-only special case *and* strictly
stronger — it closes four additional silent-green holes for free. It changes nothing today (all five
values are present once Phase 1 lands, so the result is 195 either way).

The reusable workflow is resolved **from `jobs.release.uses`**, not hard-coded. Hard-coding is one
line shorter and less safe: repointing `jobs.release.uses` at a different reusable workflow would
leave the extractor reading the old file's `60` and passing green — the exact silent-false-green
class this deliverable exists to close. When stripping the leading `./`, use `removeprefix('./')`,
**never `lstrip('./')`** (a character-class strip that mangles any `.`-prefixed segment).

Directional properties, each with an AC:

- **Today:** `max(60, 60) + 135 = 195` — identical to the pre-change value. `DRIFT_SUSTAINED_THRESHOLD_MIN` stays **195**. **No threshold move, so the issue's "threshold moves first" sequencing is never triggered.**
- **Delete the release ceiling:** absent ⇒ 360 ⇒ `495 > 195` ⇒ **B9 fails.** (Today: silently green.)
- **Delete any other ceiling on the path:** absent ⇒ 360 ⇒ bound rises ⇒ **B9 fails.** (Today: silently green.)
- **Raise any ceiling above what the threshold permits:** **B9 fails** until the threshold is raised. Preserves the one-directional semantic.
- **Parse failure / unresolvable `uses:`:** **B9 fails** via a real assertion on the error key (P9), not via a `:-0` coercion that passes.

---

## Deliverable 2 — parity-test the C4 edge descriptions' embedded counts

### Verified derivations (measured 2026-08-03; all match the committed prose, re-verified by review)

| # | Prose in `model.c4` | Derivation | Value |
|---|---|---|---|
| C1 | `github -> sentry`: "check-ins from **7** workflows" | `grep -rln 'actions/sentry-heartbeat' .github/workflows/ \| wc -l` | 7 |
| C2 | "**4** GHA-`schedule:`-fired" | of the C1 set, those whose parsed `on:` has a `schedule` key | 4 |
| C3 | "and **3** `workflow_dispatch`-only" | of the C1 set, those whose parsed `on:` has **no** `schedule` key | 3 |
| C4 | "Of **52** cron monitors" | `grep -c 'resource "sentry_cron_monitor"' apps/web-platform/infra/sentry/cron-monitors.tf` | 52 |
| C5 | "**8** check in from here" | count of **distinct `monitor-slug:` values** across `.github/workflows/` | 8 |
| C6 | "and **44** from webapp" | C4 − C5 | 44 |
| C7 | `github -> resend`: "one of **ten** Resend emitters under .github/" | `grep -rln 'api\.resend\.com\|notify-ops-email' .github/workflows/ .github/actions/ \| wc -l` | 10 |

**Load-bearing subtlety — C1 (7) and C5 (8) are DIFFERENT derivations and must not be conflated.**
Seven *files* use the heartbeat composite, but eight *distinct monitor slugs* check in from GitHub,
because `.github/workflows/scheduled-terraform-drift.yml` declares **two**
(`scheduled-terraform-drift` and `scheduled-heartbeat-reconcile`). A test deriving both from one
command would encode `7 == 8` and be wrong on its first run.

**C7 is a number-WORD ("ten"), not a numeral.** A `([0-9]+)` anchor cannot match it. The registry
must carry a per-row numeral-or-word mode with an explicit word→int map, or Phase 3 rewrites that
clause to a numeral. Either is acceptable; the choice must be explicit, not incidental.

**Two implementation traps to name in the test:**

- **PyYAML parses an unquoted `on:` key as boolean `True`.** A C2/C3 derivation written as
  `d.get("on")` silently yields C2=0 / C3=7. Use `d.get("on", d.get(True))` (or the bash/`yq`
  equivalent). Verified by review — this reproduces the correct 4/3 split only with the fallback.
- **Repo-root resolution.** Every derivation is a repo-root-relative grep. Follow
  `plugins/soleur/test/c4-model-freshness.test.sh`'s idiom — derive `SCRIPT_DIR`, then
  `REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"` — and never assume CWD.

### Sweep of `model.c4` for OTHER count-bearing edges

601 lines swept with a numeral/number-word × artifact-noun regex; every hit classified.

| Location | Prose | Disposition |
|---|---|---|
| `hetzner -> tunnel` | "zero host-identity assertions in the **12** `connection{}` inlines" | **STALE — confirmed by both reviewers.** Actual `connection {` count = **18** (server.tf 16, ci-ssh-key.tf 1, tunnel.tf 1); `host =` in server.tf = 16. Nothing derives 12. **Deferred, not fixed here** — it is a different edge, unasked-for by #7160, and correcting it regenerates `model.likec4.json`. File a tracking issue (§Deferrals). |
| `tunnel` / `hetzner -> tunnel` | "ONE tunnel with **THREE** ingress rules" | Out of scope — ambiguous. `tunnel.tf` has **four** `ingress_rule {` blocks; three carry `hostname =`, the fourth is the `http_status:404` catch-all. "Three" is true only under a reading the prose does not state. Folded into the same deferral. |
| `betterstack` | "**TWO** new per-host web heartbeats"; "**10/10** object pool" | Out of scope — narrative/historical, not live-derivable. |
| `sentry` | "**TWO** distinct hostname classes" | Out of scope — a vendor-API property, not a repo fact. |
| comment (~L521) | "**Three** emitters + a paging exit" | Out of scope — a comment, not edge prose; "emitter" is a judgement (4 edges point into `sentry`). |
| `hetzner -> tunnel` | "ONE connector live: web-1" | Out of scope — live-infra fact, already guarded by the `*/15` connector census in `scheduled-inngest-health.yml`. |

Recording the exclusions *is* the sweep's output. An ambiguous derivation encoded as a test is worse
than no test: it reds CI on a correct model and trains the next engineer to edit the test instead of
the prose.

### Test placement — `plugins/soleur/test/c4-count-parity.test.sh`

**`scripts/*.test.sh` is NOT auto-discovered.** Each needs an explicit `run_suite` line in
`scripts/test-all.sh`, enforced only by `scripts/lint-orphan-test-suites.sh` — which runs in ci.yml's
`lint-bot-statuses` job, an **advisory** job absent from both `scripts/required-checks.txt` and the
Terraform ruleset, so a PR can merge with it red. Forgetting registration yields the #5417 orphan
class: green CI, zero coverage, caught only by a non-blocking gate.

`plugins/soleur/test/*.test.sh` **is** auto-globbed — by the `for f in plugins/soleur/test/*.test.sh
plugins/soleur/skills/*/test/*.test.sh …` loop inside `scripts/test-all.sh`'s `want_scripts` block
(cite the loop, not a line number). It runs in the `test-scripts` CI shard and rolls up into the
synthetic `test` job, which **is** the required status check. It is also where
`c4-model-freshness.test.sh`, the repo's existing `.c4` gate, lives.

**Therefore:** `plugins/soleur/test/c4-count-parity.test.sh`. **Zero wiring changes** — no edit to
`scripts/test-all.sh`, `scripts/required-checks.txt`,
`scripts/ci-required-ruleset-canonical-required-status-checks.json`, or
`infra/github/ruleset-ci-required.tf` (the last three are set-parity-locked and CODEOWNERS-gated).

Precedents: `scripts/sync-readme-counts.sh --check` (the repo's existing
prose-count-vs-filesystem gate, ci.yml job `readme-counts`) for *shape*;
`plugins/soleur/test/c4-model-freshness.test.sh` (`source test-helpers.sh`, `PASS`/`FAIL`/
`print_results`, `REPO_ROOT` idiom) for *harness convention*.

### Test design

A closed **registry**, one row per guarded count: `(edge id, clause-anchored regex, numeral|word
mode, derivation)`. For each row: derive the live value, extract the prose value, compare.

Failure output names the edge, clause, both values, and the derivation:

```
FAIL  c4-count-parity: edge `github -> sentry` is STALE
      clause:      "check-ins from N workflows"
      prose says:  7
      derived:     8
      derivation:  grep -rln 'actions/sentry-heartbeat' .github/workflows/ | wc -l
      fix:         update knowledge-base/engineering/architecture/diagrams/model.c4
```

**Anchor on the clause, never the bare numeral** (`cq-assert-anchor-not-bare-token`). `grep -c '7'`
matches issue refs (`#7138`), ADR ordinals, and ports. Each regex must span the surrounding words
(e.g. `check-ins from ([0-9]+) workflows`), so the assertion cannot be satisfied by unrelated text
**and** a prose rewrite that drops the clause **fails** rather than silently passing.

**A "completeness guard" over the guarded edges was designed in v1 and CUT.** Both reviewers
independently verified it reds a correct model on its first run: `github -> sentry` contains a
second, unconsumed `3` ("Those 3 are the third substrate") that no C-row anchor covers, and
`github -> resend` contains **zero** numeric tokens (C7 is the word "ten"), making the guard vacuous
there. Extending it to number-words makes it worse (it then also hits "two inline curls" and "the
third substrate"). The only path to green would be a hand-maintained exclusion list of prose
fragments — precisely the anti-pattern this plan's own out-of-scope table names. Build the seven
registered rows; add a guard when a real unguarded number actually stales.

**Mutation check (required).** Assert the suite rejects a synthetic prose copy with a perturbed
number, so its failure path is demonstrated rather than assumed.

---

## Coordination — overlap with PR #7206

PR **#7206** (`fix-7091-drift-log-and-alert-drill`) is open and edits the same file. Measured hunk
map against `scripts/prod-version-drift-check.test.sh`:

| #7206 hunk | What it does | Collision |
|---|---|---|
| `@@ -61,9 +61,9 @@` | `MIN_ASSERTIONS` 106→114, `MIN_B` 38→46 | **SEMANTIC.** This plan adds Part-B assertions too, so these floors must be raised **again**, on top of #7206's values. |
| `@@ -581,6 +581,37 @@` | inserts B13/B14 extractor blocks immediately after the B8 `except` clause | **TEXTUAL, adjacent.** This plan rewrites the emit ~1 line above that insertion point. Near-certain conflict. |
| `@@ -618,10 +649,15 @@` | B11 env-ref regex | none |
| `@@ -817,6 +853,23 @@` | adds B13 assertions after B12 | none textually; shifts B9's offsets |

**Sequencing rule for /work — BEFORE editing the file:**

1. `gh pr view 7206 --json state,mergedAt`.
2. If **merged**: `git fetch origin && git rebase origin/main`, then edit.
3. If **open**: rebase onto `origin/main` anyway and edit; resolve the `@@ -581` hunk by hand when
   #7206 lands. Do **not** cherry-pick #7206's commits into this branch.
4. **Never hardcode `MIN_ASSERTIONS` / `MIN_B` from this plan.** Read the post-rebase values and add
   this change's own new-assertion count. The floors are an anti-vacuity mechanism; a stale
   hardcoded value silently weakens it.

---

## Implementation Phases

Phase order is load-bearing: the ceiling must exist before the extractor that reads it, or Phase 2's
assertions have nothing true to assert.

### Phase 0 — Preconditions (no edits)

0.1 Confirm CWD is the worktree; `git branch --show-current` == the feature branch.
0.2 Run the #7206 sequencing rule; rebase onto `origin/main`.
0.3 Re-derive all seven counts in §Verified Derivations. **If any has drifted, correct `model.c4`
    prose in Phase 3 and record it** — do not assume the table.
0.4 Capture the baseline: `bash scripts/test-all.sh scripts` must be green **and**
    `actionlint .github/workflows/reusable-release.yml` output captured verbatim (it exits **1**
    today on six pre-existing shellcheck findings — SC2129 ×4, SC2012, SC2015). This baseline is
    what AC2 diffs against.

### Phase 1 — Declare the ceiling

1.1 In `.github/workflows/reusable-release.yml`, `jobs.release`: add `timeout-minutes: 60` adjacent
    to `runs-on: ubuntu-latest`.
1.2 Add a rationale comment in the register the file already uses: the measured worst run
    (24.33 min, cold-cache Docker build), the arithmetic written as
    `max(release, await-ci) + (migrate 30 + verify-migrations 15 + deploy 90)` — **naming the jobs,
    not the magic total 135**, so the comment cannot silently stale — the fact that 60 is the largest
    value leaving `DRIFT_SUSTAINED_THRESHOLD_MIN` untouched, the P8 caveat that this bounds execution
    only, and the coupling to `scripts/prod-version-drift-check.test.sh` B9 (mirroring the existing
    `COUPLED (#7091)` comment style in `web-platform-release.yml`).
1.3 `actionlint .github/workflows/reusable-release.yml` — **no new diagnostic** vs the Phase-0.4
    baseline (it will still exit 1 on the pre-existing findings; that is expected and is what ci.yml
    itself tolerates).
1.4 Do **not** add `timeout-minutes` to `web-platform-release.yml`'s `release` job (P3).

### Phase 2 — Close the silent-green holes (the B9 extension)

2.1 In `scripts/prod-version-drift-check.test.sh`, replace the `RELEASE_SERIAL_TIMEOUT_SUM` sum with
    the critical-path computation in §The B9 extension:
    - resolve the reusable workflow from `jobs.release.uses` (`removeprefix('./')`, **not**
      `lstrip('./')`);
    - apply **`360` when `timeout-minutes` is absent, uniformly to all five jobs** — replacing every
      `int(x or 0)` on this path;
    - emit `max(release_ceiling, await-ci) + migrate + verify-migrations + deploy`.
2.2 Add a **real assertion** on the parse-error / unresolvable-`uses:` arm (P9), and remove B9's
    `:-0` coercion so an unset sum **fails** instead of passing `195 >= 0`.
2.3 Update B9's assertion text and comment: the value is a **critical path with a `max()` term**, not
    a serial sum; state the corrected **495** undeclared-case figure; state the P8 caveat that this
    bounds declared execution only.
2.4 Correct the two prose comments that state the superseded serial arithmetic — the
    `await-ci 60 + migrate 30 + verify-migrations 15 + deploy 90` header comment in
    `scripts/prod-version-drift-check.sh` and the "one of four on the serial critical path" comment
    in `.github/workflows/web-platform-release.yml`. **Comment-only edits**; no behaviour, and
    `DRIFT_SUSTAINED_THRESHOLD_MIN` is untouched.
2.5 Raise `MIN_ASSERTIONS` / `MIN_B` by exactly the number of assertions added, from post-rebase
    values.
2.6 **Verify by mutation, not by reading.** Independently: (a) remove the Phase-1 ceiling → suite
    **red**; (b) remove `deploy`'s `timeout-minutes` → suite **red** (this case is silently green
    today); (c) restore both → green. Record all three outputs.

### Phase 3 — C4 count parity test

3.1 Create `plugins/soleur/test/c4-count-parity.test.sh`, `source`-ing `test-helpers.sh`, using the
    `PASS`/`FAIL`/`print_results` convention **and the `REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"`
    idiom** of `c4-model-freshness.test.sh`.
3.2 Implement the registry for C1–C7 with clause-anchored regexes. Handle C7's number-**word**
    explicitly. Use the `on:`-parses-as-`True` fallback for C2/C3.
3.3 Implement the mutation/negative check.
3.4 Confirm discovery by running the aggregator (Phase 4.1), not by reading the glob.

### Phase 4 — Verification

4.1 `bash scripts/test-all.sh scripts` — exits 0, and the output contains the new suite's label.
4.2 `actionlint` on both release workflows — no new diagnostic vs the Phase-0.4 baseline.
4.3 Re-run the Phase-2.6 and Phase-3.3 mutation checks; record outputs in the PR body.
4.4 If `model.c4` was edited (Phase 0.3 drift), re-run `plugins/soleur/test/c4-model-freshness.test.sh`
    and commit the regenerated `model.likec4.json` — a description edit changes that artifact.

---

## Files to Edit

- `.github/workflows/reusable-release.yml` — `timeout-minutes: 60` + rationale comment on `jobs.release`.
- `scripts/prod-version-drift-check.test.sh` — B8 extractor (uniform 360-default, max-form critical path, `uses:` resolution), B9 assertion + parse-error assertion + comment, `MIN_ASSERTIONS`/`MIN_B`. **Rebase-sensitive — §Coordination.**
- `scripts/prod-version-drift-check.sh` — **comment only** (superseded serial-sum prose). `DRIFT_SUSTAINED_THRESHOLD_MIN` stays **195**.
- `.github/workflows/web-platform-release.yml` — **comment only** ("one of four on the serial critical path"). No job, key, or value changes.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — only if Phase 0.3 finds drift (plus `model.likec4.json` if so).
- `CHANGELOG.md` — per repo convention at ship time.

## Files to Create

- `plugins/soleur/test/c4-count-parity.test.sh`.

**Explicitly NOT edited:** `scripts/test-all.sh`, `scripts/required-checks.txt`,
`scripts/ci-required-ruleset-canonical-required-status-checks.json`,
`infra/github/ruleset-ci-required.tf` — the chosen test location needs none of them.

## Open Code-Review Overlap

**None.** Ran `gh issue list --label code-review --state open --limit 200` (63 open) and matched
every path above against each issue body via `jq --arg path`. Zero hits. The only open work touching
a shared file is PR #7206 — disposition **coordinate via rebase**, not fold-in (its scope, the run
log and the alert drill, is disjoint from the timeout bound and the C4 counts).

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `jobs.release` in `.github/workflows/reusable-release.yml` declares `timeout-minutes: 60`, with a comment naming the measured worst run, the arithmetic **by job name** (not the literal 135), and the B9 coupling.
- **AC2** `actionlint` on `reusable-release.yml` and `web-platform-release.yml` produces **no diagnostic absent from the Phase-0.4 baseline**. (It exits 1 on six pre-existing shellcheck findings; a "exits 0" criterion would be unachievable, and ci.yml itself only asserts the linter terminates.)
- **AC3** The B8 extractor resolves the reusable workflow from `jobs.release.uses` — no hard-coded `reusable-release.yml` literal in the resolution path — and uses `removeprefix('./')`, not `lstrip('./')`.
- **AC4** A missing `timeout-minutes` is read as **360** for **all five** critical-path jobs; no `int(x or 0)` remains on that path. Verified by mutation (AC5).
- **AC5** Three recorded mutation runs: (a) delete the release ceiling → B9 **FAIL**; (b) delete `deploy`'s `timeout-minutes` → B9 **FAIL** *(silently green before this change)*; (c) both restored → **PASS**. Outputs in the PR body.
- **AC6** B9's computed value **equals 195** on the merged tree, and `git diff origin/main -- scripts/prod-version-drift-check.sh` shows **no change to `DRIFT_SUSTAINED_THRESHOLD_MIN`**.
- **AC7** A parse failure or unresolvable `uses:` target makes the suite **FAIL**. Verified by mutation: point `jobs.release.uses` at a nonexistent path, run the suite, observe FAIL; restore. Output recorded. *(Today this passes via `:-0`.)*
- **AC8** `MIN_ASSERTIONS` and `MIN_B` are raised by exactly the count of assertions added, computed from post-rebase values. PR body shows before → after → delta.
- **AC9** `plugins/soleur/test/c4-count-parity.test.sh` exists, is executable, and asserts all seven counts C1–C7 with **clause-anchored** regexes. No assertion matches a bare numeral alone. C7's number-word is handled explicitly.
- **AC10** The suite **fails** on a perturbed count in a synthetic prose copy, and the failure message names the edge, the clause, both values, and the derivation. Output recorded.
- **AC11** `bash scripts/test-all.sh scripts` exits 0 **and its output contains the new suite's label** — proving auto-discovery by running the aggregator's own invocation (the same one ci.yml's `test-scripts` job runs), not by reading the glob or hand-enumerating paths.
- **AC12** No `.md`/`.yml`/`.json`/`.tf` file in the diff claims the commit→deployed bound is "provable", "strict", or "guaranteed"; the P8 execution-only caveat appears in the `reusable-release.yml` comment and in B9's comment.
- **AC13** Every count in §Verified Derivations re-derived at implementation time matches the committed `model.c4`; any drift is corrected in the same PR, with `model.likec4.json` regenerated and `c4-model-freshness.test.sh` green.

### Post-merge (operator)

*None.* Every step is automatable in-session or in CI. The ceiling takes effect on the next merge to
`main` touching `apps/web-platform/**` — the existing release pipeline is the delivery mechanism.
No dispatch, no dashboard step, no SSH.

---

## Observability

```yaml
liveness_signal:
  what: the `release / release` job's conclusion + duration via the Actions API; the
        `scheduled-prod-version-drift` 30-minute tick (unchanged by this plan)
  cadence: per merge to main touching apps/web-platform/**; drift check every 30 min
  alert_target: existing — Sentry cron monitor `scheduled-prod-version-drift`, operator
        email, and the auto-filed GitHub issue. None altered here.
  configured_in: .github/workflows/reusable-release.yml (the new ceiling);
        .github/workflows/scheduled-prod-version-drift.yml (unchanged)

error_reporting:
  destination: GitHub Actions job status — a ceiling breach is a FAILED `release / release`
        job, which the existing `release-outcome` job mirrors to Sentry and to the
        operator email (#7138)
  fail_loud: true — a timeout kill is a red job, never a skipped one; `release-outcome`
        needs the whole graph and fires regardless of which job failed

failure_modes:
  - mode: the 60-minute ceiling kills a slow-but-healthy deploy
    detection: FAILED `release / release` at ~60 min elapsed, distinguishable from a real
        build error by duration and by a healthy build log
    alert_route: release-outcome operator email + Sentry mirror (pre-existing)
  - mode: a ceiling on the critical path is deleted or raised past what the threshold permits
    detection: B9 in scripts/prod-version-drift-check.test.sh (uniform 360-if-absent).
        Silently green today for ALL five jobs — closing it is the point of Phase 2.
    alert_route: CI `test-scripts` -> required `test` check -> PR blocked
  - mode: the extractor cannot parse or resolve the reusable workflow
    detection: the new parse-error assertion (AC7). Passes today via a `:-0` coercion.
    alert_route: CI `test-scripts` -> required `test` check -> PR blocked
  - mode: a new scheduled workflow or Resend emitter stales a model.c4 count
    detection: plugins/soleur/test/c4-count-parity.test.sh
    alert_route: CI `test-scripts` -> required `test` check -> PR blocked
  - mode: RESIDUAL (P8, NOT closed here) — queue wait or concurrency serialization pushes
        commit-to-deployed past 195 with every ceiling honored
    detection: the drift alerter itself fires; the run log shows a healthy release graph
        with a long gap before job start
    alert_route: existing alerter (email + GitHub issue + Sentry). Tracked as a deferral.

logs:
  where: GitHub Actions run logs for `release / release` and ci.yml `test-scripts`
  retention: GitHub default (90 days)

discoverability_test:
  command: |
    gh run list --workflow=web-platform-release.yml --limit 20 --json databaseId,conclusion
    bash scripts/test-all.sh scripts
  expected_output: |
    the release runs list with conclusions; the aggregator exits 0 and its output contains
    the `plugins/soleur/test/c4-count-parity` suite label
```

No `ssh` appears in any command. Every failure mode is reachable from the Actions API or a local
aggregator run.

---

## Architecture Decision (ADR/C4)

**No new or amended ADR.** The ceiling is a parameter inside the frame ADR-072
(`ADR-072-adaptive-ci-signal-wait-for-deploy-gate.md`) already established for this pipeline; it
neither reverses nor extends that decision. Deliverable 2 enforces an existing documentation
convention. No ownership/tenancy boundary, no new substrate or integration pattern, no
resolver/dispatch/trust boundary change.

**C4 views — completeness enumeration.** All three model files were read, not grepped for the
feature's own noun: `model.c4` (601 lines, ~63 elements), `views.c4` (3 views: `context`,
`containers of platform`, `components of platform.plugin`), `spec.c4` (tag/style spec).

- **(a) External human actors:** none added (`founder`, `emailSender`, `betaContact`, `contributor` unchanged).
- **(b) External systems / vendors:** none added — `github`, `sentry`, `resend` are already modeled with the exact edges this plan reads.
- **(c) Containers / data stores:** none added or touched.
- **(d) Actor↔surface access relationships:** none changed.

The only contemplated `model.c4` edits are **prose corrections to existing edge descriptions** —
description-level, not topology-level. No element added or removed, so no `views.c4` `include` line
changes and `spec.c4` is untouched. If such an edit lands, Phase 4.4 regenerates
`model.likec4.json` and re-runs `c4-model-freshness.test.sh`.

---

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Both deliverables are CI/release-pipeline changes. Material risks and their
mitigations are enumerated in §Risks; the substantive engineering findings (P3 schema rejection,
P4 parallel-not-serial, P8 execution-vs-wall-clock, P9 unasserted error arm, the C1/C5
non-conflation, and the `scripts/*.test.sh` orphan-glob trap) are each recorded with the measurement
that established them. The B9 semantic is preserved and strictly strengthened: five silently-green
regressions (delete any of the five ceilings) plus the parse-error arm move from green to red.

### Product/UX Gate

**Tier:** none. The mechanical UI-surface override was evaluated against `## Files to Edit` and
`## Files to Create`: no path matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`,
or any UI-surface glob. The change set is workflow YAML, a bash test, and doc prose.

---

## Hypotheses

The Phase-1.4 network-outage gate fired on a **keyword match only** — "timeout" appears because this
plan *declares* a `timeout-minutes`, not because anything is timing out, unreachable, or resetting
connections. No SSH step, no `provisioner "file"` / `"remote-exec"` / `connection { type = "ssh" }`
in any edited file, no firewall, no DNS, no connectivity symptom. The checklist's L3→L7 ordering has
no applicable layer. `hr-ssh-diagnosis-verify-firewall` is therefore **not applied** and no
rule-application telemetry is emitted — emitting `applied` for a non-SSH change would poison the
weekly aggregator with a false positive, the same defect class this plan is fixing in `model.c4`.

The one genuine empirical question — *is 60 minutes above every legitimate `release` run?* — is
answered by measurement, not hypothesis: n=60, max 24.33 min, p95 11.1, worst single step a
21.7-minute cold-cache Docker build. Falsification route (a `release / release` failure at ~60 min
with a healthy build log) is in §Observability; the remedy is a ceiling raise **plus** the B9-forced
threshold raise, in that order.

---

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| 60 min kills a healthy deploy | Low | 2.5× worst observed, 5.4× p95, 2.8× worst single step, 88× for the plugin caller. Detection + remedy in §Observability. |
| Merge conflict with PR #7206 | **High** | Rebase-first sequencing rule with a measured hunk map; ban on hardcoding `MIN_*` floors. |
| The plan over-claims a "provable" bound | **Was HIGH in v1 — now closed** | P8 records the refutation; AC12 mechanically forbids the language re-entering the diff; the residual is a named deferral. |
| The B9 rewrite silently weakens the guard | Low | Every direction enumerated; strengthening verified by **three mutation runs** (AC5, AC7), not by reading. |
| A count drifts before merge | Medium | Phase 0.3 re-derives all seven; AC13 folds any correction into the same PR. |
| Encoding an ambiguous derivation reds CI on a correct model | **Was HIGH in v1 — now closed** | The completeness guard is cut (verified-broken on both edges); ambiguous counts are documented as exclusions with reasons, not encoded. |
| New test lands as an orphan | Low | Auto-globbed location; AC11 proves discovery via the aggregator's own invocation. |

---

## Alternative Approaches Considered

| Alternative | Verdict |
|---|---|
| Set `timeout-minutes` on `web-platform-release.yml`'s `release` job (the issue's literal ask) | **Impossible** — schema-rejected (P3, measured). |
| Claim the change makes 195 "strictly provable" (the issue's framing) | **Rejected as false** — P8. Adopting it would ship a documented guarantee the mechanism cannot give. |
| Add a `timeout_minutes` input to `reusable-release.yml` per caller | Rejected — YAGNI; both callers are safe at 60. |
| 90 or 120 minutes | Rejected — pushes the declared bound past 195, forcing a `DRIFT_SUSTAINED_THRESHOLD_MIN` raise (a real loosening of production alerting) for headroom the data does not justify. |
| 30 or 45 minutes | Rejected — identical declared bound, strictly less headroom; a cold-cache build already consumed 21.7 min once. |
| Only add the YAML ceiling, leave B9 alone | Rejected — deleting the ceiling would then be silently green, the exact gap the deliverable closes. |
| Recompute B9 as a 5-way serial sum including `release` | Rejected — factually wrong (`release ∥ await-ci`) and would force a threshold raise to 255 for latency the pipeline cannot incur. |
| Apply the 360-if-absent default only to `release` | Rejected — leaves four identical silent-green holes. Uniform across all five is simpler *and* strictly stronger. |
| Hard-code `reusable-release.yml` in the extractor | Rejected — one line shorter, less safe: repointing `jobs.release.uses` would leave the extractor reading a stale file and passing green. |
| A completeness guard over unregistered numbers in guarded edges | **Rejected — verified broken.** Reds a correct model (unconsumed `3` in `github -> sentry`) and is vacuous on `github -> resend` (zero numerals; C7 is a word). |
| Put the parity test in `scripts/*.test.sh` | Rejected — not auto-globbed; policed only by an advisory job. Orphan risk for no benefit. |
| A dedicated CI job for the parity test | Rejected — needs lockstep edits to three set-parity-locked, CODEOWNERS-gated files. The auto-globbed location inherits the required `test` context. |
| Guard every number in `model.c4` | Rejected — several derivations are ambiguous. A test that reds on a correct model trains people to edit the test. |
| Fix the `12 connection{} inlines` staleness inline | Rejected for this PR — different edge, unasked-for by #7160, drags `model.likec4.json` regeneration into a p3 chore. **Deferred** (§Deferrals). |

---

## Deferrals (tracking issues to file at ship time)

Per `wg-when-deferring-a-capability-create-a`, each needs a GitHub issue with what/why/re-evaluation
criteria and the `Post-MVP / Later` milestone:

1. **`hetzner -> tunnel` embedded-count staleness.** "12 `connection{}` inlines" — actual is 18
   (server.tf 16, ci-ssh-key.tf 1, tunnel.tf 1); "THREE ingress rules" — `tunnel.tf` has four
   `ingress_rule {` blocks, three with `hostname =`. Both need the prose disambiguated *before* a
   count can be guarded. Re-evaluate when that edge is next edited, or fold into the next
   architecture-doc pass.
2. **Unbounded queue / concurrency latency in the commit→deployed path (P8).** `cancel-in-progress:
   false` on the release, migrate, verify-migrations, verify-doppler-secrets and deploy concurrency
   groups means close-together merges serialize, and the checker's committer-epoch clock accrues
   during the wait. Not addressable by `timeout-minutes`. Re-evaluate **on the alerter's first false
   positive** whose run log shows a healthy graph with a long pre-start gap.

---

## Out of Scope (referenced, not re-filed)

**Re-page on a sustained monitor outage.** Sentry's `New/ExistingHighPriorityIssueCondition` routing
rule pages the operator once and stays silent on a repeat of an identical event. Tracked by **#7142**
— not re-filed, not fixed here. Partially mitigated: the alerter's two primary channels (operator
email + GitHub issue) do not depend on Sentry, which covers only "the workflow never ran".

---

## Review Revisions (v1 → v2)

A 2-agent panel (correctness + simplicity) verified v1's claims against the repo. Applied:

| # | Finding | Applied |
|---|---|---|
| R1 | **P0** — "strictly provable bound" is false: `timeout-minutes` caps execution, the checker's clock is the committer epoch, and `cancel-in-progress: false` serializes runs | New **P8**; Overview reframed; AC12 forbids the language re-entering; residual filed as a deferral |
| R2 | `actionlint` exits 1 on six pre-existing findings — an "exits 0" AC is unachievable | AC2 restated as "no new diagnostic vs the Phase-0.4 baseline" |
| R3 | `RELEASE_PARSE_ERROR` is asserted nowhere; B9's `:-0` coercion makes a parse failure **pass** | New **P9**; Phase 2.2 + AC7 add a real assertion and remove the coercion |
| R4 | The completeness guard reds a correct model (unconsumed `3` in `github -> sentry`) and is vacuous on `github -> resend` | **Cut** — design section, phase step, and AC removed; rationale recorded |
| R5 | C7's count is the **word** "ten"; a `([0-9]+)` anchor cannot match it | Called out explicitly; registry carries a numeral-or-word mode |
| R6 | `int(x or 0)` leaves four more silent-green holes beyond `release` | 360-if-absent applied **uniformly to all five jobs**; release-only special case and its extra emit key dropped |
| R7 | AC7(v1) grepped for `555`, which appears zero times already; AC11(v1)'s identities are definitional tautologies; AC3/AC10/AC15/AC17/AC18(v1) unfalsifiable, vacuous, or repo-wide gates | Cut. **18 ACs → 13**, each a checkable post-condition |
| R8 | `scripts/test-all.sh:616` is the wrong line (the glob is at 581) | Now cites the `for f in plugins/soleur/test/*.test.sh …` **anchor text** per `cq-cite-content-anchor-not-line-number` |
| R9 | PyYAML parses `on:` as boolean `True` — a naive C2/C3 derivation yields 0/7 | Named as an implementation trap in Deliverable 2 and Phase 3.2 |
| R10 | `lstrip('./')` is a character-class strip | Phase 2.1 + AC3 mandate `removeprefix('./')` |
| R11 | The two files stating the superseded serial arithmetic were in the "NOT edited" list, so AC7(v1) could not land | Both added as **comment-only** edits (Phase 2.4); `DRIFT_SUSTAINED_THRESHOLD_MIN` still untouched |
| R12 | `135` as a magic constant in the Phase-1.2 comment can stale | Comment must name the jobs, not the total (AC1) |
| R13 | The `12 connection{} inlines` fix is scope creep on a p3 chore | Moved from an in-scope phase step to **Deferral 1** |
| R14 | `c4-model-freshness.test.sh`'s `REPO_ROOT` idiom was not named | Named in Phase 3.1 |
| R15 | B9's margin was already exactly zero before this change | Stated as an **inherited condition** in §Ceiling Analysis, not implied as headroom this plan preserves |

**Surfaced, not auto-applied** (headless — persisted to `decision-challenges.md` for operator
review): the simplicity panel recommended deleting §Hypotheses, §Domain Review, the C4 (a)–(d)
enumeration, and parts of §User-Brand Impact as ceremony (~48% document reduction). These are
**mandated by the plan skill's own gates** (Phases 1.4, 2.5, 2.6, 2.10) and were trimmed rather than
removed. The tension between gate-mandated sections and proportionality on a p3-low chore is a real
one and is the operator's call, not the plan author's.
