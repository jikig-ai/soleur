---
title: "fix: release BuildKit cache off the Actions cache, and make the rehearsal skip monitor honest"
date: 2026-10-25
slug: release-cache-cap-and-skip-monitor
branch: feat-ci-cache-cap-and-skip-monitor
issue: 10917
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: release BuildKit cache off the Actions cache, and make the rehearsal skip monitor honest

## Overview

Two PRs from three open chores (#10917, #10918, #8856), scoped in the brainstorm (`knowledge-base/project/brainstorms/2026-10-25-ci-cache-cap-and-skip-monitor-brainstorm.md`, spec `knowledge-base/project/specs/feat-ci-cache-cap-and-skip-monitor/spec.md`). Revised after the five-agent plan review (see "Plan Review Outcome").

- **PR A (#10917).** `reusable-release.yml` stops exporting its BuildKit cache to the Actions cache (`type=gha,mode=min`, about 1.17 GB per release, mostly never reused) and uses an inline registry cache on the private GHCR image. `provenance: false` is set explicitly.
- **PR B (#8856 + #10918).** The skip-persistence probe implements ADR-188's stated bound, the alert text stops naming a remedy that was cut, and the probe-broken escalation exits a distinct rc that reaches the existing `broken` alert title.

## Research Insights

### Premise Validation (Phase 0.6)

- **Held:** #10917, #10918, #8856 are OPEN; `cache-to: type=gha,mode=min,scope=web-platform-release` is the only `cache-to` in the repo (`reusable-release.yml:802-803`); the probe fails on any single hit and computes no rate.
- **Stale:** #7535 (pre-baked image) CLOSED 2026-09-17 "image cut on measurement"; #7572 CLOSED. The alert text, probe comments, ADR-188 and the probe tests still say the image is owed.
- **Measured this session (corrects the brainstorm):** of the 12 newest `infra-validation.yml` main runs whose logs were fetched (2026-10-23 through 2026-10-25), exactly one carries a probe marker. Run 39939406626 (2026-10-23T10:28Z) logged `SKIP (loud): S1 G6 verdict-append mutation did not run: docker rc=100 (apt under the container's outer set -e)`. The ten newest runs carry none, and each has the suite terminal line `git-data-runcmd-rehearsal: 108 passed, 0 failed, Skipped: 0`. So the monitor is red from one transient apt decline (ADR-188's accepted class), not a persistent condition. The single `SKIP (loud)` visible in the newest run is `apt-bounded.test.sh` G4-9 (needs a docker daemon plus a local `bash:3.2` image) — not a probe marker (`T5 `, `S1 `, `T17 `) and out of scope.
- **ADR corpus (Phase 0.6.4):** `type=inline` / registry cache appears in no ADR's Decision or Alternatives (ADR-252, ADR-191, ADR-296 hit only on unrelated `cache` wording). ADR-296 rejects cache hygiene for the *streak store* only.

### Property List and Cut List (Phase 0.6b)

Properties: (P1) the repo's Actions cache stays under its cap so unrelated caches stop being evicted; (P2) a release build does not regress and the release path (sign, mirror, verify) is intact; (P3) the monitor's verdict equals ADR-188's bound over a sample that can express it; (P4) alert text names only work that exists; (P5) a probe-broken condition is never titled as arms skipping.

| Mechanism | Property | Disposition |
|---|---|---|
| Cache-prune workflow | P1 | Cut. Mutates production state; inline cache already removes the writer. Old `gha` entries age out (7-day unused eviction). |
| Dockerfile reorder of `ENV BUILD_SHA` (#5055) | P1/P2 | Cut. Inline cache stores no bytes in the Actions cache whichever layers change. |
| `RUN chown -R` to `COPY --chown` (spec FR2) | none | Cut. The cap is met by FR1 alone, and the change alters production image ownership. |
| New registered test suite for the workflow (was Task 1.3) | none beyond AC1 | Cut at plan review (DHH, simplicity). One grep assertion goes into an existing suite that already parses the workflow. |
| Per-verdict dedupe marker (was Task 2.3b) | P5 | Cut at plan review. Ruled by CTO agent (2026-10-25): the monitor never closes issues, the broken comment body names the verdict, one shared marker stays. |
| `observed < 20` summary-note branch | none | Cut. The FAIL/PASS line already prints `observed`. |
| ADR-text-parsing anchor, marker-roster derivation, loop-order mutations | none | Cut at plan review. The suite's existing `_PROBE_NAMED` vs `_SKIP_CALL_SITES` guard already covers the roster. |
| Dead-man's switch for the monitor | none of P1 to P5 | Split out as #11073. |
| Re-opening the pre-baked image | P3/P4 | Cut. #7535 measured $0 saving and 0 operator-visible seconds. |

### Measurements and sources

- Release build step: `.github/workflows/reusable-release.yml:790-803` (`docker/build-push-action`, `push: true`, tags `:v<next>`, `:<sha>`, `:latest`). GHCR login precedes it (L624). The cosign sign step (L845) and the zot copy and verify steps (L960, L1413, L1475) read `steps.docker_build.outputs.digest` / post-push values, so a changed digest from the inline-cache metadata does not break them. Releases serialize per component (`concurrency: release-<component>`, `cancel-in-progress: false`). Worst measured cold build ~21.7 min against a 60-min job ceiling.
- Dockerfile (`apps/web-platform/Dockerfile`): `runner` is `FROM cli-tools` (L111), so `builder` is outside the exported chain. `ARG/ENV BUILD_SHA` at L222-223 invalidates `RUN npm ci --omit=dev` (L227) and every later `COPY` and `chown` (L410) on each release. Layers above `ENV BUILD_VERSION` (L212) are stable: apt, global npm, gh, playwright.
- Sizes (776 MB, 394 MB) come from #10917 and are not verified; a build log is needed (Task 1.1).
- The build step sets no `provenance:`; `build-inngest-config-bundle.yml:191` sets `provenance: false`. No release-image attestation consumer exists (grep for cosign/attest/slsa/provenance finds only keyless signing of the digest, `reusable-release.yml:841-848`).
- Probe: `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` — `SAMPLE=20` (L142) caps `gh run list` at 20 runs including failures, so `observed` is usually 13 to 15. Rehearsal verdict at the `hits -eq 0` branch (L262-271); escalation in `_transient()` exits 1 (L127-133). The probe is deliberately not enrolled as a follow-through, so `sweep-followthroughs.sh` does not run it.
- Monitor workflow: `scheduled-rehearsal-skip-monitor.yml` maps probe rc 0/1/2/other to `pass`/`fail`/`transient`/`broken` (L150-158); the title `case` already has a `broken` arm (L240-242); one shared body marker dedupes against OPEN issues; the monitor never closes issues (header, and the `pass` branch only echoes, L347).
- Test fixture: the `gh` stub in `t5-skip-persistence-bound-7510.test.sh` (`mkcase`, ~L92-140) serves one shared log for every run id, ignores `--limit`, marks every run `success` and keeps no call log.
- Learnings: `2026-06-08-ci-gate-fail-open-traps-skip-token-grep-and-buildkit-cache-mode.md`, `2026-10-23-a-correctness-counter-lived-in-the-store-its-neighbours-evict...md`, and this session's `2026-10-25-a-monitors-alert-text-outlived-the-decision-it-cites-and-its-probe-never-implemented-the-adr-bound.md`.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality | Plan response |
|---|---|---|
| "The monitor stays red after the probe fix until the skip cause is found" (brainstorm; CPO condition) | One skip run in the newest 12; the ten newest runs are clean. With the bound applied over 20 observed runs, 1 skip passes. | Fix the sample so the bound can be expressed (Task 2.1); record the live verdict at AC12. Superseded. |
| "FAIL when `runs_with_skip * 20 > observed`" (CTO ruling) | The sample is 20 runs including failures, so `observed` is below 20 and one skip could never pass. | Stop at 20 observed from up to 40 listed. The formula is kept; its precondition is added. |
| Escalation needs "its own title and body" (#10918) | The workflow already has a `broken` title; the escalation exits 1 so it lands on `fail`. | Escalation exits rc 3 (maps to `broken`); the `broken` body and header comments are reworded so rc 3 is described truthfully. |
| Spec FR2 (`COPY --chown`) | Buys no listed property. | Cut; amend spec. |
| Pre-baked image "owed" (alert, ADR-188) | #7535 closed on measurement. | Text and ADR amendment (Task 2.2). |

## Open Code-Review Overlap

None for `reusable-release.yml`, `apps/web-platform/Dockerfile`, the probe script or the monitor workflow. #8487 ("capability-gate corpus follow-ups from #8372 review") names ADR-188 in its body: **Acknowledge** — a different concern, no fold-in; the ADR-188 amendment is additive.

## User-Brand Impact

- **If this lands broken, the user experiences:** a release that fails to build or deploys a stale image to `app.soleur.ai`, so fixes shipped to users do not reach them, or a cold build slows every release.
- **If this leaks, the user's workflow is exposed via:** a secret-bearing build layer or provenance record readable outside the private registry. The `mode=min` rule (no non-public ARG in the runner stage) is kept as a comment, and `provenance: false` removes the build-arg-recording attestation that a public repo would otherwise default to.
- **Brand-survival threshold:** single-user incident

CPO sign-off recorded under "Domain Review". `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Plan Review Outcome (2026-10-25, five reviewers plus CTO rulings)

Mechanical findings applied: fixture extension; `3 = escalated` documented and the `broken` body reworded; early-stop as a `break` with a per-log `skip_runs` flag and separate rate constants; one sampling rule; new suite, marker split, note branch and over-built guard rows cut; ADR-299 short and accepted; `provenance: false`; local-registry proof; AC6/AC8/AC10 reworded; follow-through exit-1 branch defined; `ci.yml` comment added to the edit list; digest source recorded as verified instead of a task.

Rulings (Ruled by CTO agent, 2026-10-25): (1) keep the shared dedupe marker; (2) `cache-from` is `type=registry,ref=<image>:latest` (a `:buildcache` tag adds an ungated push with the same trust profile; flips if a build that failed the zot gate is shown to have fed a later published build); (3) set `provenance: false` explicitly (flips if anything verifies release-image attestations).

Not applied, surfaced as a taste item: none of the reviewers asked to drop operator-requested scope.

## Implementation Phases

### Phase 1 — PR A: release cache (#10917)

1.1 **Measure before changing.** Record `gh api repos/jikig-ai/soleur/actions/cache/usage` (bytes, entry count), the latest release run's `Build and push Docker image` duration and its `sending cache export` step duration, per-layer sizes of the pushed image, and the manifest type of `:latest` (`docker buildx imagetools inspect <image>:latest`: index with attestations, or a single manifest). Write the numbers into the PR body. This settles which layer is the 776 MB one.

1.1b **Local proof of the cache mechanics.** With a throwaway local registry (`registry:2`) and a two-stage toy Dockerfile, build with `provenance: false` and `--cache-to type=inline`, push, change one late layer, rebuild with `--cache-from type=registry,ref=<local>/x:latest`, and confirm the early layers report `CACHED`. Record the output in the PR body. If Docker is unavailable on the machine, say so in the PR and rely on AC9 and the revert path; do not claim the proof.

1.2 **Switch the backend** in `.github/workflows/reusable-release.yml`:
   - `cache-from: type=registry,ref=${{ inputs.docker_image }}:latest`
   - `cache-to: type=inline`
   - `provenance: false` (explicit).
   - Remove `scope=web-platform-release`. Keep `Set up Docker Buildx` (container driver); reword its `type=gha` comment.
   - Replace the secret-safety comment with one sentence: inline cache carries only final-image layers, and `provenance: false` stops build-args being recorded; still no non-public secret ARG in the runner stage.
   - No `type=gha` fallback (a dual cache would keep exporting).
   - Update the stale `mode=min` gha-scope comment at `.github/workflows/ci.yml` (~L1173).

1.3 **Regression guard.** Add one assertion to an existing suite that already parses `reusable-release.yml` (the implementer picks it): no `type=gha` in the file, `cache-to: type=inline` present, `provenance: false` present. No new suite and no new registration.

1.4 **Post-merge verification.** Merge does not release; the first release after merge builds cold once (the existing `:latest` carries no cache metadata). Write `scripts/followthroughs/actions-cache-usage-10917.sh`: exit 0 when `active_caches_size_in_bytes` is under 8e9, exit 1 when it is over (the sweeper comments the reading on #10917 and leaves it open, and the next step is the explicit-authorization prune option recorded on #10917), exit 2 on API failure. The `<!-- soleur:followthrough script=... earliest=<merge date + 8d> -->` directive on #10917 is added after merge, once the real date is known (unused `gha` entries are evicted after 7 days); the sweeper token needs `actions: read`. PR A uses `Ref #10917`.

### Phase 2 — PR B: skip monitor (#8856 + #10918)

2.1 **Probe implements the bound** (`t5-skip-persistence-bound-7510.sh`, rehearsal source only):
   - Constants: `LIST_LIMIT=40` (the `gh run list` limit), `OBSERVE_TARGET=20` (stop once this many runs are observed), `BOUND_DENOM=20` (the "1 in 20" denominator, with a comment citing ADR-188).
   - At the end of the per-run loop body: `[[ $observed -ge $OBSERVE_TARGET ]] && break` (the loop reads a here-string, so there is no subshell and the TRANSIENT branches after the loop are untouched).
   - Per log: `skip_runs` increments once when the summed counts of `T5 `, `S1 `, `T17 ` are above zero.
   - Verdict: FAIL when `skip_runs * BOUND_DENOM > observed`; otherwise PASS, with its own message when `skip_runs > 0` ("N of M observed runs skipped, within ADR-188's bound"), because "0 loud skips" would be false there.
   - Source 2 (guard-suite arms `g1b.`/`g2b.`/`fl.`) is unchanged: deterministic degradation, any hit FAIL.
   - All TRANSIENT protections stay.

2.2 **Text that named the cut remedy.** Replace "pre-baked image (#7535) is owed / S1 extension (#7572) is the same class" at the probe (L26, L34, L169, L375-376), the workflow (L315) and the probe tests (L264, L276, L521) with: the apt or docker-pull decline (rc 100 / 125) is recurring rather than transient; diagnose the mirror or runner cause; the image was evaluated and cut on measurement in #7535. Add `## Amendment — 2026-10-25` to ADR-188 recording the cut image, the sampling change, and that the 1-in-20 bound is now implemented; correct its carrier note that overstated the script.

2.3 **Escalation reaches `broken` (#10918).** In `_transient()` the consecutive-TRANSIENT escalation exits rc 3 instead of 1, keeping its FAIL text. Add a `3 = escalated (consecutive TRANSIENT)` row to the probe header's exit-code contract. In the workflow, reword the `broken` body and the "contract is 0/1/2 and nothing else" comment so rc 3 is described as an escalation and rc 126/127 as a probe that could not run. The `*)` arm already selects `broken`; the shared marker is kept, so a `broken` verdict comments on an open alert issue (CTO ruling).

2.4 **Tests, written first** (`cq-write-failing-tests-before`). Extend the `gh` stub in `t5-skip-persistence-bound-7510.test.sh`: per-run-id log overrides, honour `--limit`, non-success conclusions, and a call log of every `run view` id. Then cases: 1 skip in 20 observed PASS with the within-bound message; 2 in 20 FAIL; 1 in 13 observed FAIL; one run with two arms skipped counts once; sampling stops at 20 observed (call log length) when 25 are available; fewer than 20 observed still decides; no terminal line anywhere TRANSIENT; source 2 any-hit FAIL; escalation rc 3. Add a wiring case in `scripts/monitor-streak-state.test.sh` (or the suite that owns workflow wiring): the real `case "$rc"` and title `case "$VERDICT"` blocks are extracted from the workflow, rc 0/1/2/3/127 map to pass/fail/transient/broken/broken, and the `broken` title differs from the `fail` title.

2.5 **Live check.** After merge, dispatch `scheduled-rehearsal-skip-monitor.yml` and record the verdict and `observed` count in PR B; do not claim green before it runs.

### Phase 3 — Artifacts

3.1 ADR-299, short, status accepted: the release build cache is an inline registry cache; the Actions cache backend writes one entry per changed layer blob, which churns the shared 10 GB store; alternatives (prune workflow, `mode=max`, scope split, Dockerfile reorder, `:buildcache` tag) and the `:latest` trust note. 3.2 Amend the brainstorm and spec: replace "monitor stays red", drop FR2, record the measured skip history. 3.3 The learning is already written.

## Files to Edit

- `.github/workflows/reusable-release.yml` (cache-from, cache-to, provenance, comments)
- `.github/workflows/ci.yml` (stale gha-scope comment)
- an existing suite that parses `reusable-release.yml` (one assertion)
- `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` (sampling, rate rule, text, escalation rc, header)
- `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` (stub, cases)
- `.github/workflows/scheduled-rehearsal-skip-monitor.yml` (text at L315, `broken` body, contract comment)
- `scripts/monitor-streak-state.test.sh` (wiring cases) — or the suite that owns workflow wiring; confirm at implementation
- `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md` (amendment)
- the brainstorm and spec under `knowledge-base/project/`

## Files to Create

- `scripts/followthroughs/actions-cache-usage-10917.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-299-release-build-cache-is-an-inline-registry-cache-not-the-actions-cache.md`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. `grep -c 'type=gha' .github/workflows/reusable-release.yml` prints 0; `cache-to: type=inline`, a `type=registry` `cache-from` built from `inputs.docker_image`, and `provenance: false` are present; one comment sentence on inline-cache secret safety is retained; the single regression assertion passes in the existing suite.
- [ ] AC2. PR A body records the Task 1.1 numbers (cache bytes and entries, build and export durations, per-layer sizes, `:latest` manifest type) and the Task 1.1b output or its stated absence.
- [ ] AC3. Probe tests pass: 1 skip in 20 observed PASS; 2 in 20 FAIL; 1 in 13 FAIL; one run with two skipped arms counts once; sampling stops at 20 observed; source 2 any-hit FAIL unchanged.
- [ ] AC4. Escalation exits rc 3; the wiring test shows rc 3 selects the `broken` title and the skip FAIL still selects the `fail` title; the probe header documents rc 3.
- [ ] AC5. `git grep -niE 'owed' scripts/followthroughs/t5-skip-persistence-bound-7510.sh scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh .github/workflows/scheduled-rehearsal-skip-monitor.yml` finds no line saying the image is owed, and the ADR-188 amendment records the cut.
- [ ] AC6. `c4-count-parity.test.sh` and the C4 validation tests pass (no C4 edit expected).
- [ ] AC7. Closing keywords: PR A `Ref #10917`; PR B `Closes #10918` and `Ref #8856` (closed after AC11).

### Post-merge

- [ ] AC8. The first release after merge passes `soleur:postmerge`: build success, the pushed digest is cosign-signed, the zot copy succeeds, the offline verify succeeds, health `build_sha` equals the release commit; its build step shows no `sending cache export` to gha. Any failure triggers an immediate revert of PR A.
- [ ] AC9. By the second release or 14 days after merge, whichever is first: the layers above `ENV BUILD_VERSION` (apt, global npm, gh, playwright) report `CACHED` from the registry cache, and the build duration is within 20% of the Task 1.1 baseline.
- [ ] AC10. The follow-through on #10917 passes (`active_caches_size_in_bytes` under 8e9 after the 7-day eviction window), then #10917 closes.
- [ ] AC11. A dispatched monitor run records its verdict and `observed` count on #8856; the issue closes only once the monitor is honest and not red for the skip alone.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO (brainstorm and plan review, 2026-10-25) rulings carried forward and extended: inline registry cache over a prune workflow, two PRs, probe counts runs, escalation reuses `broken`, shared marker, `:latest` cache source, `provenance: false`.

### CPO sign-off (single-user incident threshold)

**Status:** reviewed — SIGN-OFF yes (2026-10-25), conditions adopted as ACs:

- Keep an adapted secret-safety statement (Task 1.2, AC1).
- The first post-merge release must pass `soleur:postmerge`: green build, signed digest, zot copy, offline verify, live version equals the release (AC8).
- Revert PR A at once if any of those fail (Sharp Edges).
- Record the cold-build time as the baseline (AC2, AC9).
- CPO read only the brainstorm and the release build lines, not the ADRs. Digest-source concern resolved by reading the sign and copy steps (see Measurements).
- The "monitor stays red" condition is superseded by the measured skip history; PR B states the verdict observed at AC11 either way.

No product, legal, marketing, or finance surface; the work has no UI.

## Observability

```yaml
liveness_signal:
  what: the scheduled rehearsal skip monitor run, and the release workflow's build step
  cadence: monitor daily 06:00 UTC; release on every merge to main that bumps a version
  alert_target: the soleur-skip-persistence-monitor-alert issue; failed release run
  configured_in: .github/workflows/scheduled-rehearsal-skip-monitor.yml; .github/workflows/reusable-release.yml
error_reporting:
  destination: GitHub Actions run conclusion plus the alert issue
  fail_loud: true
failure_modes:
  - mode: release build cannot pull cache-from (registry auth or missing tag)
    detection: build-push-action warns and builds cold; step duration regression is visible in the run
    alert_route: failed release run; AC9 compares against the Task 1.1 baseline
  - mode: probe cannot reach a verdict for 3 consecutive runs
    detection: probe exits rc 3
    alert_route: the `broken`-titled comment on the open alert issue, or a new `broken`-titled issue
  - mode: Actions cache usage creeps back over the cap
    detection: actions-cache-usage-10917.sh
    alert_route: the follow-through tracker comment on #10917
logs:
  where: GitHub Actions run logs; the alert issue comments
  retention: GitHub default run-log retention
discoverability_test:
  command: bash scripts/followthroughs/actions-cache-usage-10917.sh
  expected_output: PASS
  credentials_required: "GH_TOKEN with actions:read — the cache-usage endpoint has no unauthenticated form, and the property being verified is the repo's own cache bytes"
```

## Architecture Decision (ADR/C4)

### ADR

Create ADR-299 via `soleur:architecture` (Task 3.1), status accepted, and amend ADR-188 (Task 2.2). The ordinal is provisional; `soleur:ship` re-verifies it against `origin/main`.

### C4 views

All three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` are read at implementation. Enumeration checked here: external human actors — none new; external systems — GHCR is already modeled (`model.c4:452`, private registry) and the Actions cache is not an element; containers or data stores — none new (the cache moves into an existing registry); access relationships — none changed. Expected conclusion: no C4 impact, backed by a green `c4-count-parity.test.sh` run (AC6), since count prose on the GitHub edge could move.

### Sequencing

The ADR is authored in PR A, not postponed.

## Guard Contract

### Guard 1 — skip-persistence rate bound

**Property.** The rehearsal source FAILs exactly when more than 1 in 20 observed post-merge runs carried a loud skip on a registered arm, and never PASSes when no run was observed.

**Assembly.** Every path that decides the rehearsal verdict: the run listing (`--limit`), the per-run loop with its early stop, the `observed` and `skip_runs` counters, the PASS/FAIL/TRANSIENT branches in `t5-skip-persistence-bound-7510.sh`, the `SKIP_MARKERS` set (arm-name parity with the suite's `arm_skip` call sites is already asserted by the suite's `_PROBE_NAMED` vs `_SKIP_CALL_SITES` guard and is not restated), and the workflow's rc to verdict `case`. The chokepoint is the single rehearsal verdict block; source 2 is a separate block and is outside this contract.

**Mutation matrix.**

| # | Edit (must drive RED) | Expected |
|---|---|---|
| M1 | Change `skip_runs * BOUND_DENOM > observed` to `skip_runs * 2 > observed` | the "1 in 20 passes" case fails |
| M2 | Count marker lines instead of runs (a run with two arms skipped counts twice) | the "one run, two arms skipped" case fails |
| M3 | Delete the terminal-line discriminator check (own dispatch) | the none-observed case no longer yields TRANSIENT and fails |
| M4 | Stop evaluating after the first skipping run (a second member after a compliant first) | the "2 in 20 FAIL" case fails |

**Harness rows.** H1: a stub `gh` that returns an empty list; the suite must fail on "0 passed, 0 failed" and not exit 0. H2: must-PASS input that is not the canonical: 1 skip among 20 observed on arm `T17`, from a listing of 25 runs, and the call log shows 20 `run view` calls. Must-RED inputs are produced by editing the fixture logs, not the probe.

**Anchor.** The bound's value is pinned by the 1-in-20 and 2-in-20 test cases and recorded in the ADR-188 amendment; weakening the probe requires changing those cases, which the review of the same diff sees. Nothing parses ADR prose.

### Guard 2 — escalation wiring

**Property.** A consecutive-TRANSIENT escalation is never titled as arms skipping.

**Assembly.** The `_transient()` exit paths in the probe, the workflow `case "$rc"`, and the title `case "$VERDICT"`.

**Mutation matrix.**

| # | Edit (must drive RED) | Expected |
|---|---|---|
| M1 | Escalation exits 1 again | wiring test fails |
| M2 | Map rc 3 to `fail` in the workflow `case` | wiring test fails |
| M3 | Remove the `broken` arm from the title `case` | wiring test fails |

**Harness rows.** H1: the test extracts the real `case` blocks from the workflow and fails if extraction yields nothing. H2: must-PASS inputs rc 0, 1, 2 keep `pass`, `fail`, `transient`.

**Anchor.** The rc-to-verdict mapping is read from the workflow file by the test; both sides live in files the test parses, so no value outside the commit has to move.

## Test Scenarios

- Probe: 1 skip in 20 observed; 2 in 20; 1 in 13; one run two arms; 25 observed with early stop; none observed; source 2 any hit; escalation rc 3 after 3 transient runs.
- Wiring: rc 0/1/2/3/127 map to pass/fail/transient/broken/broken; titles differ.
- Release: the single regression assertion; real-release checks are AC8 and AC9.

## Sharp Edges

- The release switch cannot be tested on a real release before merge; Task 1.1b and AC8/AC9 are the evidence. Do not claim a build-time result from the PR run.
- The first release after merge builds cold. Say so in the PR body so it is not read as a regression.
- Do not add a `type=gha` fallback "for safety": it keeps exporting and keeps the cap problem.
- Do not widen the probe's marker to the bare prefix `SKIP (loud): ` — `apt-bounded.test.sh` G4-9 and `infra-config-apply.test.sh` emit loud skips that are not rehearsal arms.
- Up to 40 full logs can be fetched when many runs lack the terminal line; that is accepted, and the loop stops at 20 observed.
- Revert path for PR A: the revert PR restores `type=gha`, deletes `actions-cache-usage-10917.sh` and removes the follow-through directive from #10917 in the same change; re-releasing needs the normal version bump; check `docker buildx imagetools inspect <image>:latest` after a failed release for a half-advanced tag.
- Concurrent releases cannot race on `:latest` (per-component serialization).
- ADR-299's ordinal is provisional; re-check against `origin/main` before merge.
