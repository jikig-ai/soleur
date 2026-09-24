---
title: "infra-validation deploy-script-tests runs within ~4-5 min of its 27-min timeout; a slow runner cancels it on main"
date: 2026-09-24
slug: fix-deploy-script-tests-timeout-headroom
branch: feat-one-shot-8688-deploy-script-tests-timeout
issue: 8688
closes: 8688
type: chore
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-09-24
**Sections enhanced:** Research Insights (semantics + precedent + verify-the-negative),
Technical Considerations (deepen gate record).
**Pipeline note:** this planning subagent has no Task/agent tool; the deepen fan-out
(skills, learnings, research/review agents, the 4.45 realism passes) ran inline,
sequentially — `Reviewed-Coverage: sequential-fallback` — and is not claimed as an
independent panel.

### Key Improvements

1. **Attribution mechanism is stronger than the plan stated.** A step `timeout-minutes`
   firing reports API `conclusion: timed_out` on the named step (the jobs API
   conclusion enum includes `timed_out` for both jobs and steps) — distinguishable
   from an anonymous job-level `cancelled`, not merely "a step failed with its name".
2. **Verify-the-negative pass (Phase 4.45) confirmed all four negative claims:**
   `git-data-runcmd-rehearsal.test.sh` contains zero `timeout` tokens;
   `git-data-ownership.test.sh`'s single `timeout` token (:236) is a static regex
   asserting the gc unit's shape inside the boot code — its `docker run` at :321 is
   unbounded; `git-data-cutover-access.test.sh` carries the `timeout -k 10 480`
   internal bound as cited; and no file under `tests/`, `.github/scripts/`, or
   `scripts/` greps the three step names.
3. **Deepen gate verdicts recorded:** Phase 4.6 (User-Brand) PASS with the
   `threshold: none, reason:` scope-out (the workflow name matches the sensitive-path
   regex); Phase 4.7 (Observability) PASS — `discoverability_test.command` uses the
   allowlisted `grep` verb, no SSH, literal `expected_output`, no shell metacharacters
   (Check-10-safe); Phase 4.8 (PAT) PASS — no hits; Phase 4.9 (UI/.pen) skip — no UI
   surface; Phase 4.10 (encryption) skip — no store/connection; Phase 4.11 (Guard
   Contract) skip — the deliverable is config values, not a guard artifact; Phase
   4.55 (Downtime) doesn't fire — no hcloud/migration/router change.

### New Considerations Discovered

- **Network-Outage Deep-Dive (Phase 4.5, `timeout` trigger fired):** not applicable.
  The plan's `timeout` occurrences are GitHub Actions YAML keys, not connectivity
  symptoms; the plan drives no SSH, no `terraform apply`, no `remote-exec`/`file`
  provisioners. L3/L7 layers have nothing to verify.
- **Precedent-Diff (Phase 4.4):** precedent exists — the same file already ships the
  `timeout-minutes` + measured-comment form on four steps (ci-deploy comment
  `:688–692` / key `:695`, plugin-seed `:998–1036`, web-zot `:1064`,
  registry-userdata `:1412–1416`).
  The prescribed edit mirrors that shape verbatim: key as sibling of `name:`/`run:`,
  measured comment above it. Not a novel pattern.

## Overview

*No `spec.md` exists for this branch — `lane:` defaulted to `cross-domain` (fail-closed).*

The `deploy-script-tests` job in `infra-validation.yml` has outgrown the ceiling the
workflow's own re-derivation block last sized (27 min, derived 2026-09-15 on a ~1120 s
basis). The measured green max on the last 19 successful main-push runs is now 1462 s —
a 1.11× margin where the file sizes for ~1.4× — and four consecutive Sep-24 push runs
cancelled at the 1620 s cap. Per-step API data shows the three docker-runtime git-data
steps slowing together on the cancelled runs (ownership ~3×, cutover ~2.5×, rehearsal
≥1.8× and unfinished — a runner/environment signature),
while the one step in flight at every cancel — the git-data runcmd rehearsal — carries no
step-level bound, so a genuine hang and a slow run are indistinguishable. The plan
re-derives the ceiling per the file's own convention and gives the docker-runtime steps
the same attribution `timeout-minutes` the file already puts on its other stall-prone
steps.

## Research Insights

### Premise Validation (plan Phase 0.6)

- **Issue #8688 — OPEN** (`gh issue view 8688`): `type/chore` + `meta/machinery`, 2 comments. Held.
- **Cited file exists**: `.github/workflows/infra-validation.yml`, job `deploy-script-tests`
  opens at `:455`, `timeout-minutes: 27` at `:620` — both verified by direct read on this
  branch. Held.
- **Cited comment conventions verified**: the ceiling block (`:468–620`) is a chain of dated
  MEASURED/RE-DERIVED entries that size the ceiling at ~1.4× a measured basis stated as a
  range on named run sets, and instruct re-derivation whenever steps are added. The
  attribution convention is real and present twice: plugin-seed `timeout-minutes: 1`
  (key `:1036`, measured comment `:998–1009`), `Run ci-deploy.sh tests`
  `timeout-minutes: 3` (key `:695`, comment `:688–692` — "Its value is ATTRIBUTION,
  not budget"), plus web-zot-seed `:1064` (5) and registry-userdata-budget `:1416` (2).
  Noted drift: the ceiling block's own plugin-seed caveat at `:527` still says
  `timeout-minutes: 3` while the key is `1` — a dated comment outliving its value is
  exactly why the file dates every measurement entry, and why the new step comments
  should cite the measured range and date rather than only the number.
- **ADR corpus check (mechanism keywords, not issue refs)**: `ADR-166` (a CI message may only
  name a cause the job measured) supports step-level attribution bounds. `ADR-238`
  (TEST_GROUP taxonomy) records "splitting multiplies fixed cost" for the sibling `ci.yml`
  matrix — evidence against the job-split option, though it governs a different file.
  No ADR rejects raising a ceiling or adding step `timeout-minutes`; the file's own block
  prescribes re-derivation. The issue body's "~2× the observed max" suggestion is NOT the
  file's convention — the block sizes ~1.4×; the plan follows the file.
- **Stale adjacent premise**: #6766 ("infra-validation cannot fail on main: no push
  trigger") is open but stale — the workflow runs on `push` today (the failure-notify job
  at `:2310` reads `needs.deploy-script-tests.result` on push). Not a blocker; flagged so
  the plan does not inherit its framing.
- **Run-set independence verified by direct API pulls** (not trusted from the issue):
  `gh api repos/jikig-ai/soleur/actions/workflows/248570873/runs?branch=main&per_page=30`
  then `.../runs/<id>/jobs` per run — numbers below are this session's measurement.

### Measured basis (this session, `gh api`, 2026-09-24)

Last 19 completed successful main-push runs of `deploy-script-tests`
(35647415891 … 35954771278), whole-job seconds:

```text
1066 1085 1170 1184 1217 1232 1255 1257 1272 1304
1332 1369 1384 1387 1420 1426 1454 1459 1462
```

- max = **1462 s**, median = 1304 s, p90 ≈ 1454 s. Ceiling margin today: 1620/1462 = **1.11×**
  (the block sizes for ~1.4×).
- Four consecutive push runs **cancelled at the cap**: 35963237265, 35976102327,
  35991817044, 36001457260 (all 2026-09-24, 1635–1636 s job time). One failure
  (35744372693) and one queued run (36005279479) excluded from the basis.
- **The in-flight step at all four cancels is the rehearsal step, verified per-run via the
  API** (`conclusion: "cancelled"` on `Rehearse the git-data runcmd chain`; every step
  after it `skipped`): in-flight 455 s (35991817044), 408 s (35976102327), 390 s
  (35963237265), 285 s (36001457260). Green range for the step is 184–267 s (n=10).
- Per-step seconds, cancelled run 35976102327 vs green run 35952634647 (10-green-run
  distributions in parens):

  | Step | green | cancelled | green range (n=10) |
  |---|---|---|---|
  | Run git-data ownership tests | 28 | 80 | 25–100 |
  | Run git-data cutover access-path tests | 74 | 184 | 70–77 |
  | Rehearse the git-data runcmd chain | 223 | **408+** (cancelled in flight) | 184–267 |
  | Run ci-deploy.sh tests | 57 | 52 | ~52–57 |

  All three docker-runtime git-data steps slowed together (ownership 2.9×, cutover 2.5×,
  rehearsal ≥1.8× cancel-bound) while pure-bash `ci-deploy` stayed flat — a
  whole-runner/environment slowdown signature, not a single-step signature. A true hang inside the rehearsal's unbounded `docker run` calls
  still cannot be excluded: it is the only step observed running 285–455 s without
  completing on four separate runners, it has no host-side bound, and the log does not
  separate the two cases — exactly why the step needs its own bound.
- **Even a completed slow rehearsal leaves the job over budget**: ~16 steps follow it in
  the job order; on the cancelled runs the job died mid-rehearsal at 1635 s with those
  steps unrun. A ~460–550 s finishing rehearsal plus the tail steps projects ≈1700–1850 s —
  past the 1620 s ceiling on its own. The ceiling raise is necessary regardless of the
  hang-vs-slow question; the step bound is what makes the question answerable next time.

### Property List (plan Phase 0.6b)

- **P1 — main goes green.** The job ceiling clears the measured green distribution with the
  ~1.4× margin the file sizes for, so an ordinary slow runner no longer cancels the job.
- **P2 — a genuinely-hung step names itself.** If a step stalls past its plausible-slow
  envelope, the failure identifies THAT step instead of cancelling the job anonymously at
  whatever step the clock reached (ADR-166; the file's own attribution convention).
- **P3 — smallest mechanism.** No structural change (job split) when a measured-ceiling +
  step-bound change delivers P1+P2.

### Cut List (plan Phase 0.6b)

- **Split the job (issue option c)** → buys P1 partially; P1 is already bought by the
  ceiling re-derivation at one line + comment vs a job refactor, and the split buys nothing
  for P2 (a hang in either half cancels anonymously anyway). Cut. ADR-238's recorded cost
  ("splitting multiplies fixed cost") agrees.
- **Internal `timeout` wrappers inside `git-data-runcmd-rehearsal.test.sh`'s six
  `docker run` sites** → would buy P2 at per-container granularity, but edits test logic
  (rc-check semantics, `docker rm` cleanup arms) — strictly more surface than the workflow
  key that buys the same property. Recorded under Alternative Approaches; not taken.
- **Reduce the step's cost (prebaked fixture image)** → the #7535/#7540 direction already
  shipped what survived review (e2fsprogs removal); the remaining apt dependency is a
  separate cost-reduction question, not needed for P1/P2. Not taken.
- **Renaming the stale `Assert docker is available (…)` step (#8487 item 5)** → unrelated to
  P1/P2 and a step name is an attribution label; left to its own issue.

### Relevant files

- `.github/workflows/infra-validation.yml` — the only file edited. Job `deploy-script-tests`
  `:455`; ceiling block `:468–620`; `timeout-minutes: 27` `:620`; rehearsal step `:1703–1704`;
  ownership step `:1656–1657`; cutover-access step `:1684–1685`.
- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (3917 lines) — six
  `docker run --rm` source sites / 8 runtime invocations (`:1047,:1340,:1557,:1872,:2423,:3162`),
  NO host-side `timeout` wrapper; in-container waits are bounded polls (`seq 50 × sleep 0.1`)
  and bounded apt (`Acquire::Retries=3` + 3-try backoff `:3051–3060`).
- `apps/web-platform/infra/git-data-ownership.test.sh` — `docker run` `:321` unbounded;
  apt fixture `:280`.
- `apps/web-platform/infra/git-data-cutover-access.test.sh` — `docker run` already wrapped in
  `timeout -k 10 480` `:1927`; apt fixture `:1770`.
- `.github/scripts/test/test-infra-suite-registration.sh` — derives the suite registry from
  `run: bash <path>` lines in this job (`:170–188`); a sibling `timeout-minutes:` key does not
  affect derivation (proven by the existing `ci-deploy` step shape).
- `apps/web-platform/infra/run-registered-suites.sh:242` — same `run: bash` grep derivation.
- `tests/scripts/test-git-data-boot-signal-poll.sh` — its timeout assertions target
  `apply-web-platform-infra.yml`, NOT this file. Verified `:20`.
- `.github/workflows/apply-web-platform-infra.yml` — the rung-2 rehearsal route; untouched.

### Institutional learnings applied

- `learnings/best-practices/2026-07-18-deploy-script-tests-at-budget-timeout-and-infra-pr-ci-gotchas.md`
  — the cancel location is a red herring; pull per-step durations from the API (done above);
  the step-level `timeout-minutes` mechanism this plan adopts was created there and adopted
  in PR #7020.
- `brainstorms/2026-08-13-prebake-rehearsal-image-brainstorm.md` (#7535) — the rehearsal step
  measured 88–123 s in August; it now runs 184–267 s green. Its D7 decision ("re-derive
  `timeout-minutes` when steps are added") is the rule the ceiling violated.
- `learnings/2026-06-09-no-test-asserts-X-must-grep-workflow-step-names-in-ci-test-sh.md` —
  verified no `*.test.sh` asserts on these step names before treating step edits as safe;
  step renames are therefore out of scope (an attribution label must not move under a fix).
- `brainstorms/2026-09-21-ci-runner-concurrency-brainstorm.md` (#8450) — org is on the free
  20-concurrent-job ceiling with 0 self-hosted runners; GitHub-hosted runner variance is the
  environment the ceiling must absorb, not a bug to fix here.
- ADR-166 — a CI-emitted cause may only name what the job measured: an anonymous job cancel
  names nothing; a bounded step names itself.

### External research

Skipped (plan Phase 1.6): the fix shape is fully dictated by the target file's own written
conventions plus ADR-166/ADR-238; no external novelty.

### Community discovery / functional overlap

No uncovered stacks (repo is bash + YAML + TypeScript; signature scan negative). No
community artifact substitutes for editing this repo's own workflow conventions.

## Problem Statement / Motivation

`deploy-script-tests` is the only push-time runner of the ~160 infra suites registered in
`infra-validation.yml`, and main's Infra Validation is currently RED: four consecutive
push runs on 2026-09-24 cancelled at the 27-minute ceiling. Two independent drifts brought
it here:

1. **The ceiling went stale.** The job's own re-derivation block last sized it 2026-09-15
   on a ~1120 s basis (refreshed to ~1204 s at #8539 review). Since then the green max
   reached 1462 s — margin 1.11× where the block sizes for ~1.4× — because the suites
   added since (ownership #8052, cutover-access #8187, the #8539 inngest suites) went in
   without the re-derivation the block requires.
2. **The slowest step is also the least attributable.** `Rehearse the git-data runcmd
   chain` was `conclusion: cancelled` — still running at 285–455 s vs a 184–267 s green
   range — on all four cancelled runs, and it is one of two remaining docker-runtime steps
   with no bound of any kind (no `timeout-minutes`, no internal `timeout` wrapper on its
   six `docker run` sites). A hang there and a slow runner there are indistinguishable in
   today's signal — the exact red-herring class the 2026-07-18 learning recorded and the
   step-level `timeout-minutes` convention was created to kill.

## Hypotheses

Network-outage checklist fired on `timeout` in the feature description. The affected
surface is an **ephemeral GitHub-hosted runner** (`runs-on: ubuntu-24.04`,
`infra-validation.yml:456`) — the repo manages no host, firewall, or sshd on it, so the
SSH-flavored layers are opted out with artifacts, not assumed.

1. **L3 firewall allowlist — opted out (artifact):** the runner is GitHub-hosted; no
   `hcloud firewall` object governs its egress. Verified by the job definition itself —
   and by the cancelled runs completing ~140 apt/docker-dependent steps before dying
   (network worked; it was slow, not absent).
2. **L3 DNS/routing — opted out (artifact):** runner-side routing is GitHub-managed. The
   cancelled runs' logs show apt fetches and docker pulls succeeding mid-run (steps
   completed through #147–148), which only a resolved route permits.
3. **L7 TLS/proxy — opted out (artifact):** no repo-managed HTTPS endpoint sits in the
   failure path; the failing surface is in-container apt and the Docker daemon.
4. **L7 application — partially verified:** the "service" here is the test fixture inside
   the rehearsal containers; its own bounded-poll / apt-retry logs are the journal
   equivalent. The cancelled-run logs do not separate "slow" from "hung" — that is the
   observability gap this plan closes.

Ranked hypotheses for the cancels:

- **H1 — whole-runner degradation (best supported).** The three docker-runtime git-data
  steps each ran well above their green times on the cancelled runs (ownership ~3×,
  cutover ~2.5×, rehearsal ≥1.8× unfinished) while pure-bash steps held flat. On that reading the rehearsal would have finished (~460–550 s) and the job
  would have died anyway ~16 steps later — a budget problem.
- **H2 — genuine stall inside one of the rehearsal's unbounded `docker run` sites.**
  Consistent with it being the in-flight step at every cancel and having no host-side
  bound; inconsistent with the sibling steps' lockstep slowdown (which H1 explains).
  The step bound is what discriminates H1 from H2 on the next occurrence.
- **H3 — upstream runner/image drift** (ubuntu-24.04 image roll, Azure-mirror
  degradation). Cannot be excluded or fixed here; the measured-margin ceiling is robust
  to it either way.
- **H4 — verified contributor, not a hypothesis:** composition growth past a stale
  ceiling (the 1.11× margin). This is the certain half of the failure.

## Proposed Solution

One file edited — `.github/workflows/infra-validation.yml` — two mechanism classes, both
already the file's own conventions:

**1. Re-derive the job ceiling per the block's own instruction** (the "RE-DERIVED
<date> (#N)" paragraph form, appended above `timeout-minutes:`): basis = observed max on
the last 19 successful main-push runs = 1462 s; 1462 × 1.4 = 2047 s = 34.1 min →
`timeout-minutes: 35`. At 35 the margin is 2100/1462 = **1.44×**. The new block also names
the four cancelled runs and states why they are excluded from the basis (cancelled is not
a duration — the file's own rule), and records that ~16 steps trail the rehearsal so a
completed slow run projects ≈1700–1850 s < 2100 s.

**2. Step-level `timeout-minutes` on the three docker-runtime git-data steps** — the same
"ATTRIBUTION, not budget" mechanism the job already carries at `ci-deploy.sh tests` (3),
`cloud-init-plugin-seed` (1), `web-zot-seed` (5) and `registry-userdata-budget` (2):

| Step (anchor: `- name:` text) | Green max (n=10) | Slow-run observed | Bound today | `timeout-minutes` |
|---|---|---|---|---|
| Rehearse the git-data runcmd chain | 267 s | 285–455 s in-flight ×4 | none | **10** |
| Run git-data cutover access-path tests | 77 s | 206 s | `timeout -k 10 480` per container | **8** |
| Run git-data ownership tests | 100 s | 80 s | none | **5** |

Each cap is stated in a comment in the file's style: measured range, the multiplier, and
the trade-off that a pathological runner could flake the step — the intended direction,
because "a step that names itself beats a job that cancels anonymously" (the plugin-seed
comment's own words).

The three caps bound the demonstrated heavy-tail class. If a container stalls inside the
rehearsal, the run now fails at ≤10 min naming `Rehearse the git-data runcmd chain`
instead of cancelling anonymously at 27 min; if the step is merely slow it completes and
the per-step API data records the true envelope for the next re-derivation.

## Implementation Phases

### Phase 1 — the workflow edit (single file, local gates)

1. Append the dated `RE-DERIVED 2026-09-24 (#8688)` paragraph at the end of the ceiling
   comment block (above the `timeout-minutes:` key), carrying the 19-run set, the
   1462 × 1.4 = 2047 s → 35 derivation, the four cancelled-run IDs, the projected
   slow-completion estimate, and a note that the same PR adds three step bounds below —
   so the next re-derivation reads the correct composition. Change
   `timeout-minutes: 27` → `timeout-minutes: 35`.
2. Add `timeout-minutes: 10` to `Rehearse the git-data runcmd chain (abort ordering +
   rc guard)` with a 2–4 line comment in the file's attribution idiom.
3. Add `timeout-minutes: 8` to `Run git-data cutover access-path tests (ADR-220)` —
   sized above its internal `timeout -k 10 480` container bound plus the apt fixture —
   with its comment.
4. Add `timeout-minutes: 5` to `Run git-data ownership tests (authorization map + hook
   dir, Guard 3)` with its comment.
5. Run the local gates (Test Scenarios): `actionlint`, the two workflow lint scripts,
   the infra-suite registration gate, the `run: bash` derivation grep, and a diff review
   confirming only `timeout-minutes` keys and comments changed.

### Phase 2 — post-merge verification (automated by the pipeline)

1. On the first completed main-push Infra Validation run after merge, read
   `deploy-script-tests` conclusion + per-step durations via
   `gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs` — expect `success` and record the
   new green distribution baseline for the next re-derivation.
2. If a step ever exceeds its bound thereafter, the failed step name is the attribution;
   file a follow-up only then (the failure will say which step).

## Files to Edit

- `.github/workflows/infra-validation.yml` — the ceiling comment block + `timeout-minutes`
  on the `deploy-script-tests` job, and step-level `timeout-minutes` + attribution
  comments on the three docker-runtime git-data steps (`- name:` anchors:
  `Run git-data ownership tests`, `Run git-data cutover access-path tests`,
  `Rehearse the git-data runcmd chain`).

## Files to Create

None.

## Technical Considerations

- **Why 1.4× and not the issue's ~2×**: the issue body suggested ~2× "per the file's own
  convention", but the block demonstrably sizes ~1.4× (1568←1120, 1119←799, 876←626,
  791←565). The file is the authority; 2× would also blunt the ceiling's second job —
  catching a genuinely stalled job early. 35 min is 1.44×.
- **Why cap all three docker-runtime steps, not only the rehearsal**: ownership has no
  bound at all and cutover's apt fixture sits outside its internal container bound; both
  demonstrated the same multi-x slowdown on the cancelled runs. Capping only the observed
  offender leaves the identical anonymous-cancel exposure on its two siblings for the
  price of four lines. The caps cover the class, not the incident.
- **SpecFlow self-review (Phase 3 equivalent; no Task tool in this pipeline):**
  a `timeout-minutes` on a step that SKIPs early is inert; step caps apply identically on
  `pull_request` (job needs no secrets — file header `:6`); the registration gate derives
  from `run: bash` lines only, so sibling keys cannot de-register a suite (proven in place
  by the existing `ci-deploy` step); a step-timeout failure fails the job naming the step
  — which the notify job at `:2310` reads the same as any failure; `detect-changes` does
  not gate this job.
- **Guard Contract (Phase 2.12) — reviewed, does not fire:** `timeout-minutes` is a
  runner-enforced bound, not a repo-executed check; no local mutation can drive it red,
  so the mutation-matrix apparatus cannot apply. The enforceable artifacts (the comment
  conventions, the step anchors) are verified by the ACs below.
- **ADR/C4 (Phase 2.10) — does not fire:** a ceiling value and step bounds on an existing
  job change no boundary, substrate, or trust shape; a reader of the ADRs + C4 would not
  be misled.
- **Encryption Posture (Phase 2.11) — does not fire:** no persistent store or new
  cross-component connection.
- **IaC routing (Phase 2.8) — does not fire:** no new infrastructure; this edits a
  workflow ceiling, it does not provision anything.
- **GDPR (Phase 2.7) — does not fire:** no regulated-data surface; the four (a)–(d)
  expansion triggers do not hold.
- **Does merging THIS alone mutate production? No.** The diff touches one CI workflow's
  timeout keys and comments. `apply-web-platform-infra.yml` fires on `apps/*/infra/**`
  changes — untouched here. The merge changes when the *test job* kills itself, never what
  any host runs.
- **NFR:** `knowledge-base/engineering/architecture/nfr-register.md` — the affected NFR is
  CI reliability/observability of the infra suite itself; no production-surface NFR moves.

## Alternative Approaches Considered

| Approach | Why not taken |
|---|---|
| Split the job (issue option c: docker rehearsals vs pure-bash) | Buys P1 only, at a job refactor: two check contexts, duplicated setup (checkout/terraform/cloud-init/apt), and the hang-attribution gap survives unsolved inside each half. ADR-238 records "splitting multiplies fixed cost". Re-evaluate only if the measured ceiling ever exceeds the runner-hour budget the org accepts — it does not. |
| Raise the ceiling alone | Restores green but leaves the rehearsal step unbounded: the next stall still cancels anonymously at a higher clock. Fails P2. |
| Step bounds alone | Names the next stall but the job still sits at 1.11×: a legitimately-slow-but-finishing run still cancels. Fails P1. |
| Internal `timeout` wrappers on the rehearsal's six `docker run` sites | Finer-grained attribution (per-spin), but edits test logic — rc-check semantics, `docker rm` cleanup arms, the `fixture_fail` vocabulary — for a property the step key already buys. Recorded as the next move if a step-bound failure ever needs per-spin resolution. |
| Reduce the step's cost (prebaked fixture image, drop remaining apt cycles) | The #7535 direction already shipped what survived review; the residual apt dependence is a cost-reduction question independent of P1/P2. |
| Ceiling = 2× observed max (issue's suggestion) | The file's convention is ~1.4×, and a ceiling is a stall-detector, not a budget — oversizing it weakens the signal it exists to provide. |

## Non-Goals

- Splitting `deploy-script-tests` or otherwise restructuring the job.
- Making it a required check (#6480/#6473 own that track).
- Renaming the stale `Assert docker is available (…)` step (#8487 item 5 owns it; a step
  name is an attribution label and must not move under this fix).
- Bound wrappers inside the test scripts (recorded under Alternatives).
- Closing #6766 (stale premise — the workflow does run on push) or resolving why GitHub
  runners degraded on 2026-09-24 (environmental, unfixable from here).

## User-Brand Impact

- **If this lands broken, the user experiences:** an `infra-validation.yml` parse or
  semantics error that takes Infra Validation off main entirely — every push ships
  without the only push-time run of ~160 infra suites — or a step cap set under the
  plausible-slow envelope that flakes the job with correct attribution but recurring
  noise.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the
  diff is timeout integers and comments in a public-repo workflow file; the job runs with
  `contents: read` + `actions: read` and no secrets (file header `:6`).
- **Brand-survival threshold:** `none`
- `threshold: none, reason:` the diff touches `.github/workflows/` CI machinery only — no
  user data, credentials, runtime code, or externally-visible surface; the blast radius is
  an internal check going red, not a user-facing defect.

## Observability

The change is itself an observability fix (attribution); its own signals ride the
existing job, not new machinery.

```yaml
liveness_signal:
  what: "deploy-script-tests job conclusion on each main-push Infra Validation run"
  cadence: "per push to main"
  alert_target: "the push-failure notify job (infra-validation.yml:2310-2327, pre-existing) emails on red"
  configured_in: ".github/workflows/infra-validation.yml — needs.deploy-script-tests.result at :2314"
error_reporting:
  destination: "the run's job log and the Actions API steps[] records"
  fail_loud: "a stalled bounded step fails as conclusion=failure ON the named step — versus an anonymous job cancellation today"
failure_modes:
  - mode: "a docker-runtime step stalls (apt hang / container never exits)"
    detection: "the step's timeout-minutes fires; the failed step is the stalled one by name"
    alert_route: "push-failure notify job at :2310"
  - mode: "whole-runner degradation beyond 1.44x the green max"
    detection: "job cancels at 35 min; the bounded steps still name themselves first, so the cancel lands on a measured step, not an anonymous clock"
    alert_route: "push-failure notify job at :2310"
logs:
  where: "the run's job log; per-step durations via gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs"
  retention: "GitHub run-log retention (90 days)"
discoverability_test:
  command: "grep -A2 'Rehearse the git-data runcmd chain' .github/workflows/infra-validation.yml"
  expected_output: "timeout-minutes"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. The sweep assessed
all eight domains semantically: no user-facing surface (Product), no copy (Marketing), no
pipeline/revenue surface (Sales), no regulated data (Legal/Compliance), no spend
(Finance), no vendor or operator procedure change (Operations), no community/support
surface (Support). Engineering-internal machinery only.

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open` (77 issues) searched for
`infra-validation`. Two hits, both acknowledged, neither folded:

- **#8487 (item 5)** — "workflow step name staleness: `Assert docker is available
  (cloud-init-plugin-seed needs a real daemon)` names 1 of 5 docker consumers."
  **Acknowledge:** the issue itself marks it a plan-acknowledged deferral; a step name is
  an attribution label (per-step durations report by name), so renaming belongs with the
  consumers' own change, not a timeout fix.
- **#7942** — cites `infra-validation.yml` only as the naming-convention precedent for
  `*-mutation.test.sh` registration; touches none of the lines this plan edits.
  **Acknowledge:** unrelated concern.

## Acceptance Criteria

### Pre-merge (CI + local; no credentials)

- [ ] `timeout-minutes: 35` replaces `timeout-minutes: 27` on `deploy-script-tests`, and
      the ceiling comment block's final entry is a `RE-DERIVED 2026-09-24 (#8688)`
      paragraph stating: the 19-run successful set, observed max `1462 s`, the arithmetic
      `1462 x 1.4 = 2047 s = 34.1 min -> 35`, the four cancelled run IDs (35963237265,
      35976102327, 35991817044, 36001457260), and the ≥16 trailing steps / ~1700–1850 s
      projected-completion note.
- [ ] `Rehearse the git-data runcmd chain (abort ordering + rc guard)` carries
      `timeout-minutes: 10` plus a comment in the file's attribution idiom (names the
      convention — ci-deploy at 3 / plugin-seed at 1 — and the 184–267 s green range /
      285–455 s cancelled-in-flight data).
- [ ] `Run git-data cutover access-path tests (ADR-220)` carries `timeout-minutes: 8`
      with its derivation comment (must exceed the suite's own `timeout -k 10 480`
      container bound plus fixture time, so the inner bound still fires first).
- [ ] `Run git-data ownership tests (authorization map + hook dir, Guard 3)` carries
      `timeout-minutes: 5` with its derivation comment.
- [ ] `git diff` on `.github/workflows/infra-validation.yml` changes no `- name:` line,
      no `run:` line, and no step order — only added `timeout-minutes:` keys, added
      comment lines, and `27` → `35`. (Guards both the suite-registration derivation and
      the attribution labels.)
- [ ] `actionlint .github/workflows/infra-validation.yml` exits 0 (baseline is clean
      today; any new finding is a regression introduced by this change).
- [ ] `bash .github/scripts/test/test-infra-suite-registration.sh` green, and
      `python3 scripts/lint-workflow-run-body-syntax.py` +
      `python3 scripts/lint-workflow-local-action-checkout.py` green.
- [ ] Every added comment follows the file's own conventions: durations stated as ranges
      on named run sets, steps cited by name not line number, attribution bounds described
      as attribution rather than budget.

### Post-merge (automated by the pipeline; no soak declared)

- [ ] On `origin/main` the `deploy-script-tests` job block carries `timeout-minutes: 35`
      and the three new step bounds — verified via
      `git show origin/main:.github/workflows/infra-validation.yml` (deterministic
      file-state check; the merged post-condition).
- [ ] The first completed main-push `Infra Validation` run after merge is pulled via
      `gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs` and its
      `deploy-script-tests` conclusion plus per-step durations recorded — expected
      `success`. Labeled verify-once/environmental (per the standing panel check): a
      cancel here is a runner-variance observation, not a verdict on the diff, UNLESS the
      in-flight step is one the diff left unbounded.
- [ ] If any subsequent run fails or cancels, the failed step is identifiable by name —
      a bounded step reporting `conclusion: timed_out` (the jobs API enum value a step
      timeout produces), or per-step API durations naming the offender. An anonymous
      `cancelled` at the job ceiling on a step with no bound is the failure this change
      exists to prevent.

Rationale for verify-once rather than a soak: the ceiling margin is deterministic
arithmetic (1.44× vs the 1.11× that was cancelling), and the attribution property is
structural; a multi-run soak would measure runner variance, not this change. If a flake
class does emerge, the bounded steps will name it — that is the mechanism working.

## Test Scenarios

- **Ceiling arithmetic:** given the 19-run set in Research Insights, when re-computing
  `1462 × 1.4`, then the result is `2046.8 s → ceil to 35 min`, matching the new
  `timeout-minutes: 35` and the margin claim `2100/1462 = 1.44`.
- **Parse gate:** given the edited file, when `actionlint` runs, then rc=0.
- **Bound count:** given the job block extracted with the flag-based form
  `awk '/^  deploy-script-tests:/{flag=1} flag{print} /^  [a-z][a-z-]*:$/&&!/^  deploy-script-tests:/{exit}'`
  (the `/A/,/B/` range self-matches its start line — the plan-sharp-edges trap), when
  counting `timeout-minutes:` keys, then the result is 8 — up from today's 5 (the job
  ceiling plus ci-deploy, plugin-seed, web-zot-seed, registry-userdata-budget), the delta
  being exactly the three new step bounds.
- **Anchor presence:** given the three step `- name:` anchors, when grepping each step
  block, then each contains `timeout-minutes:` between the name and `run:` lines.
- **Registration derivation:** given `run-registered-suites.sh`'s
  `grep -oE "run: bash <infra>/*.test.sh"` over the file, when compared before/after,
  then the derived suite set is identical.
- **Stall attribution (CI-semantics, not locally executable):** given a container that
  never exits inside the rehearsal step, when the step exceeds 10 min, then GitHub fails
  the step with its name in the log — asserted by the semantics of step `timeout-minutes`,
  the same mechanism `ci-deploy.sh tests` already relies on.
- **Fork-PR parity:** given a `pull_request` trigger on a fork (no secrets), when the job
  runs, then the step caps apply identically — no new credential dependency introduced.

## Success Metrics

- `deploy-script-tests` margin vs observed green max: 1.44× (was 1.11×).
- Main's Infra Validation returns to green on the first completed push run after merge.
- Zero further anonymous job-ceiling cancels: any future timeout failure names a step.

## Dependencies & Risks

- **Residual ceiling risk:** a runner degraded >44% still cancels the job — now with the
  bounded steps naming themselves first, so the residual reads as attribution, not mystery.
- **Flake trade-off (stated, accepted):** a pathological runner could push a bounded step
  past its cap (e.g. rehearsal >10 min at >2.2× its green max) and fail the step — the
  intended direction per the file's own words ("a step that names itself beats a job that
  cancels anonymously"), and the failure would be correctly attributed and re-derivable.
- **Basis drift recurs:** suites keep being added without re-derivation — the file's own
  rule is the control; the new RE-DERIVED paragraph names the current composition so the
  next stale point is measurable against it.
- **No blocking dependencies:** single-file change; no PR ordering constraint; #8487 and
  #7942 explicitly not folded.
- **Urgency:** main's Infra Validation is RED on four consecutive pushes and a fifth run
  is queued; this job is the only push-time run of the registered infra suites.

## Sharp Edges

- **Do not oversize the ceiling.** The block sizes ~1.4× and calls a ceiling "a ceiling
  absorbing runner variance, not a budget to spend". Bigger silently weakens the
  stall-detector.
- **Do not rename or reorder steps, and do not touch `run:` lines.** Step names are the
  attribution labels the API reports, and `run: bash <path>` lines are the suite registry
  the derivation greps read — a rename de-registers or mislabels.
- **`timeout-minutes` is a step key, not a `run:` modifier.** It must sit as a sibling of
  `name:`/`run:` inside the step (see the `ci-deploy` step's existing shape); placing it
  under `run:` or at wrong indent produces a YAML shape actionlint flags — run it.
- **Empty `## User-Brand Impact` halts deepen-plan Phase 4.6** — filled above.
- **Re-derivation is a dated record, not an edit.** The block's convention appends a new
  RE-DERIVED paragraph; do not rewrite earlier entries — superseded derivations are kept
  because "its METHOD is the one applied above" (the block's own words at `:586`).

## Plan Review

Pipeline note: this planning subagent has no Task/agent tool, so the review lenses were
applied inline by the planner rather than spawned — recorded here per the headless
disclosure convention, not claimed as an independent panel.

- **Standing check (cq-ac-must-not-depend-on-concurrent-sessions):** the original
  post-merge "first run green" AC measured ambient CI state; rewritten as a deterministic
  `origin/main` file-state check plus a labeled verify-once observation. Applied.
- **Simplification axis (DHH / code-simplicity lens):** every mechanism maps to a Property
  List entry — ceiling bump → P1, step bounds → P2, no split → P3. The one arguably-extra
  mechanism (a bound on cutover-access, which has an internal `timeout 480`) is kept
  because its apt fixture sits outside that bound and the class-coverage cost is four
  lines. No cut found that preserves P2.
- **Correctness axis (Kieran lens):** the awk `/A/,/B/` AC in Test Scenarios was the
  self-matching range trap — rewritten to the flag-based form (mechanical). Cited
  issue/PR numbers verified via `gh` (#8052, #8187, #8189, #8539, #7020, #7535, #7540,
  #6480, #6473, #6766, #8450, #8487, #7942 — all resolve to on-point titles).
- **Named panel (relevance-gated, independent scan):** Files to Edit = one
  `.github/workflows/*.yml` — no UI-surface glob hit; CPO/CMO/UX not activated. The
  engineering-CTO lens is the only borderline activation; its taste-class observation
  (the job's growth trend may eventually warrant suite sharding — the issue's option c)
  is persisted to `decision-challenges.md` rather than silently applied, since the
  operator's stated direction was the smallest fix.
- **decisionClass summary:** 3 mechanical findings applied inline (awk AC, post-merge AC
  restructure, RE-DERIVED block naming the new bounds); 1 taste finding persisted.

## References & Research

- Issue: #8688 (open) — body + 2 comments; the comments' per-run observations are verified
  and extended in Research Insights (all four cancels attributed to the rehearsal step).
- File authority: `.github/workflows/infra-validation.yml` ceiling block `:468–620` and
  attribution precedents `:525–528`, `:688–696`, `:1028–1037`, `:1412–1417`.
- Learning:
  `knowledge-base/project/learnings/best-practices/2026-07-18-deploy-script-tests-at-budget-timeout-and-infra-pr-ci-gotchas.md`
  — the cancel-location red herring and the per-step-duration diagnostic used above.
- Brainstorm: `knowledge-base/project/brainstorms/2026-08-13-prebake-rehearsal-image-brainstorm.md`
  (#7535) — the rehearsal step's measured history and its D7 re-derivation rule.
- ADRs: ADR-166 (a CI message may only name a measured cause), ADR-238 (job-split fixed
  cost, sibling file).
- Related open issues not in scope: #6480/#6473 (required-check promotion), #6766 (stale
  premise), #8487 item 5 (step rename), #8450 (org runner concurrency).
