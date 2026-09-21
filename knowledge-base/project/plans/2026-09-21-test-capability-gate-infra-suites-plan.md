---
title: "test: capability-gate two infra suites that RED on capability-absent dev hosts"
type: test
date: 2026-09-21
slug: test-capability-gate-infra-suites
branch: feat-one-shot-8372-capability-gate-infra-suites
issue: 8372
closes: 8372
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-09-21
**Sections enhanced:** Proposed Solution (verbatim `_skip` precedent + evidence-preserving
probe + trap-safe placement), Technical Considerations (exit-0-path enumeration + selector
ownership), Observability (detector argue-down), Dependencies & Risks (workflow step-name
staleness), all file:line citations re-verified live.
**Research agents used:** sequential-fallback inline passes (no Task/subagent tool in this
pipeline context — `Reviewed-Coverage: sequential-fallback`); learnings applied inline from
`knowledge-base/project/learnings/` (2026-08-13 red-gate arming, 2026-08-13
lower-bound-vs-constant, 2026-09-07 guard-dies-on-its-case, 2026-07-20
evidence-discarding-gate); skills discovered at `~/.claude/skills/` (`diagnose-crash`,
`omarchy`, `synced`) — none applicable to a test-harness plan.

### Key Improvements

1. Probe prescription now captures `http.server` stderr instead of `>/dev/null 2>&1`
   (evidence-preserving decline — the SKIP verdict carries *why*).
2. `_skip` helper prescribed verbatim from `git-data-emit.test.sh:28-35` (stderr, embedded
   `SKIP` marker, `CI=true` discriminator) rather than a paraphrase.
3. Every exit-0 path in both dispatches enumerated; the zot digest dispatch ends in the *run*
   arm, so no edit can mint a silent new pass path.
4. Zot `Skipped:` reporting prescribed as a separate `finish()` line — the `=== Results:`
   format stays verbatim (no consumer greps it, but minimal churn is the safer default).
5. Line citations corrected: docker assert step is `:961-963` (not `:962`); `start_server`
   call sites enumerated (:201-396, 13 sites).

### New Considerations Discovered

- The `Assert docker is available` step name is already stale (names only
  `cloud-init-plugin-seed` while `git-data-runcmd-rehearsal` also needs the daemon); this
  change adds a third consumer — noted as a follow-up, kept out of scope.
- `cleanup_test` EXIT trap in the canary suite is armed at :83 and idempotent — an early
  `exit 0` from `_skip` is safe regardless of probe placement.
- `EXPECTED_MIN` enforcement is the derived check at ~:293 (not the floor block itself);
  the decline must re-key the `:243` digest term or every capability decline collapses to
  rc=2.

## Overview

Two suites registered in the `deploy-script-tests` job of `infra-validation.yml` fail on dev
hosts that lack a capability the suite assumes, producing environmental REDs indistinguishable
from real regressions (#8372):

- `apps/web-platform/infra/canary-bundle-claim-check.test.sh` — its `python3 -m http.server`
  loopback fixture never binds within the 4s readiness window on this host (verified: the CLI
  path stalls before binding while a raw `socketserver` bind succeeds instantly).
- `apps/web-platform/infra/zot-config-deadlines.test.sh` — `docker info` returns
  `permission denied` on `unix:///var/run/docker.sock` for this user, and the digest half
  fails closed by design.

The repo already owns the convention this change applies: `_skip()`/`_runtime_skip()`
capability declines in `git-data-emit`, `git-data-ownership`, `git-data-cutover-access`, and
`cloud-init-plugin-seed` (exit 0 + printed SKIP locally; hard FAIL under `CI=true`, because the
runner is contracted to supply the dependency — ADR-181, ADR-188). The plan extends that
convention to these two suites: a one-shot capability probe per suite, a counted/explicit SKIP
verdict when the capability is absent off-CI, and unchanged fail-closed behaviour when the
capability is present or the run is under CI.

## Research Insights

**Premise Validation (Phase 0.6).** Issue #8372 is OPEN with no closing PRs. Both cited
files exist on `origin/main` (`apps/web-platform/infra/canary-bundle-claim-check.test.sh`,
`apps/web-platform/infra/zot-config-deadlines.test.sh`; last touched by 173f7889b / #7552).
Both failures reproduced on this host during planning: `docker info` → `permission denied
while trying to connect to the docker API at unix:///var/run/docker.sock` (rc=1), and
`python3 -m http.server` produced no listener and no stderr within ~1.5s while a raw
`socketserver.TCPServer` bound instantly — i.e., the CLI startup path (not the socket layer)
is what stalls, so the capability probe must exercise `python3 -m http.server` itself.
Mechanism check against the ADR corpus: the proposed skip-not-fail mechanism is the
ADR-181/ADR-188 doctrine, not a rejected alternative — ADR-188's ownership table assigns
"runner-contracted precondition absent" the verdict **hard fail under CI / skip locally**,
which is exactly the change scoped here. No stale premises found.

**Property List (Phase 0.6b).** The ask restated as observable properties:

- P1: on a host where `python3 -m http.server` cannot bind loopback within the readiness
  window, `canary-bundle-claim-check.test.sh` exits 0 with a printed SKIP verdict, not RED.
- P2: on a host where `docker info` cannot reach the daemon, `zot-config-deadlines.test.sh`
  declines the digest half with an explicit printed verdict and still runs + reports the
  static half, S4 battery, and floors — never a silent pass.
- P3: under CI (the runner is contracted to provide both capabilities), an absent capability
  remains a hard failure — fail-closed is preserved where the capability is expected.
- P4: the anti-vacuity accounting (`EXPECTED_MIN`, `FAIL_FLOOR_MIN`, harness canary) stays
  consistent under the decline route — a declined digest half must not trip rc=2, and the
  floors must still catch a real collapse.
- P5: docs that enumerate capability-dependent suites (`run-registered-suites.sh` tooling
  table) stay true after the change.

**Cut List (Phase 0.6b).** Mechanisms considered and cut:

- Shared capability-probe helper file (`infra/lib/` or similar) — cut: the repo convention
  is self-contained suites that each inline their `_skip()` (3 existing copies); no shared
  lib exists in `apps/web-platform/infra/` and ADR-178's shared primitives ship in the
  plugin, not here. A new shared file buys nothing a 10-line inline probe doesn't.
- New CI assertion step for the http.server capability — cut: the `CI=true` arm inside the
  suite already hard-fails when the capability is absent in CI (the `deploy-script-tests`
  runner is contracted to provide python3 + loopback); for docker, `.github/workflows/
  infra-validation.yml` already carries `Assert docker is available` at :961-963, ordered
  before the zot step at :1420 — ordering invariant documented in
  `run-registered-suites.sh` lines 61-67.
- Distinct `INCONCLUSIVE` verdict class — cut: explicitly rejected by ADR-188.
- Host fix (docker group membership, python shim repair) — out of scope per the issue
  ("Or: mark both suites host-capability-gated"); needs sudo.
- Runner-level SKIP taxonomy — cut: `run-registered-suites.sh` documents that a self-skip
  prints as PASS through the runner, an accepted and documented trade-off (lines 45-49).

**Relevant file paths.**

- `apps/web-platform/infra/canary-bundle-claim-check.test.sh` — suite under change;
  `start_server` (:92-104) is the failure site (4s / 20×0.2s curl window, exit 2 on
  exhaustion); `command -v python3` precondition at :24-27; 13 `start_server || exit 2`
  call sites.
- `apps/web-platform/infra/zot-config-deadlines.test.sh` — digest-half docker check at
  :198-199 (`fail` arm to convert); `SOLEUR_ZOT_GUARD_NO_DIGEST` decline at :191-194;
  `EXPECTED_MIN` accounting at :239-243; literal floor `FAIL_FLOOR_MIN=7` at :309.
- `apps/web-platform/infra/cloud-init-plugin-seed.test.sh` :17-25 — canonical whole-suite
  docker skip (`SKIP: docker not available` / `SKIP: docker daemon not reachable`, exit 0).
- `apps/web-platform/infra/git-data-emit.test.sh` :28-35 — canonical `_skip()`:
  `CI=true` → `exit 1` + "the runner must provide this dependency"; else printed SKIP,
  `exit 0`.
- `apps/web-platform/infra/git-data-ownership.test.sh` :248-270 — `_runtime_skip()`
  counted partial-arm decline (CI → fail; local → `SKIPPED += RUNTIME_ROWS` + printed SKIP).
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` :461-480 — CI-env-armed
  skip with the "CI will exercise it" rationale wording.
- `apps/web-platform/infra/run-registered-suites.sh` — derives the suite list from
  `infra-validation.yml`; header lines 36-49 enumerate docker-dependent suites (currently
  "TWO registered suites"; zot-config-deadlines' digest half becomes a third conditional
  dependency — the header instructs re-derivation).
- `.github/workflows/infra-validation.yml` — `Assert docker is available` step :961-963
  (`run: docker info >/dev/null`), canary step :1200-1201, zot step :1420.
- `plugins/soleur/test/zot-http-deadlines-required.test.sh` — meta-guard that greps only
  `LARGEST_LAYER_BYTES=`/`FLOOR_THROUGHPUT_BPS=` from the infra suite; unaffected by this
  change.
- `scripts/guard-vacuity-floor.test.sh` ~:870-888 — carries a scoped exception for
  zot-config-deadlines' floor (`MAX_DEFERRED=47`); edits to the `EXPECTED_MIN`/floor region
  must keep the literal bound adjacent and mutant-constructible — re-run this suite after
  editing.

**Institutional learnings / decisions.**

- ADR-181 — declines are counted verdicts; a decline is unreachable under CI for
  harness-owned relevance (its own Scope exempts runner-environment declines).
- ADR-188 — a transient/environment decline IS reachable under CI when nobody owns the
  missing precondition; the ownership table puts "docker / python3 absent" in the
  "runner, contracted" column → **hard fail under CI, skip locally**. Counter-precedent
  (`git-data-rung2-rehearsal`): deterministic locally-fixable absence fails loudly —
  docker-group membership is deterministic and locally fixable BUT requires sudo, and the
  issue explicitly scopes to capability-gating, so the `_skip()` convention governs.
- `run-registered-suites.sh` header — a self-skip prints as PASS through the local runner
  (documented trade-off); CI does not rely on the skip because of the separate
  `docker info` assertion step.
- ADR-180 — the guard contract is a plan-time deliverable: this change ships a gate, so
  `## Guard Contract` is required.

**External research decision (Phase 1.6).** Skipped — the mechanism is fully governed by
in-repo precedent (ADR-181/188 + four existing `_skip` implementations). External research
adds nothing.

**Functional overlap (Phase 1.5b).** No community artifact applies — the feature is the
application of this repo's own ADR-181/188 skip doctrine; sequential-fallback inline
assessment (no Task subagent available in this pipeline context).

**Skill description budget (Phase 1.8).** No `SKILL.md` `description:` edits are candidate
or planned — skipped.

## Deepen Pass (2026-09-21)

Gate-by-gate disposition of `deepen-plan` (sequential-fallback; no subagent fan-out available
in this pipeline context):

- **4.4 Precedent-diff** — the `_skip`/`_runtime_skip` decline pattern is pattern-bound with
  sibling precedents; side-by-side applied: `git-data-emit.test.sh:28-35` (whole-suite
  `_skip`, verbatim body now prescribed), `git-data-ownership.test.sh:249-256`
  (`_runtime_skip` counted-decline form — `fail` under CI, `SKIPPED += rows` + printed
  verdict locally — mirrored for the zot digest half), `cloud-init-plugin-seed.test.sh:17-25`
  (docker probe shape `command -v docker || docker info`). No novel pattern introduced.
- **4.45 Round-1 realism passes** — verify-the-negative: plan's negative claims
  ("no user-data/credential/network-egress change", "S4 children never probe docker")
  grep-confirmed (`synth_case` pins `SOLEUR_ZOT_GUARD_NO_DIGEST=1` at :259). Post-edit
  self-audit: no dropped symbols.
- **4.5 Network-outage deep-dive** — trigger word `unreachable` present; resolved inline:
  both capabilities are host-local (a unix socket, a loopback listener). All four layers
  (L3 firewall/DNS, L7 TLS/application over external paths) are N/A — no external network
  path exists in either probe. Not applicable.
- **4.55 Downtime & Cutover** — not triggered: test-script edits only.
- **4.6 User-Brand Impact halt** — PASS: section present, `threshold: none` with scope-out
  reason (files match the sensitive-path regex `apps/[^/]+/infra/`).
- **4.7 Observability gate** — PASS: 5-field schema present; `discoverability_test.command`
  verb `bash` is allowlisted, no SSH, `expected_output: "ok"` is a literal; the command's
  `.test.sh` filename match on the suite-shape detector is argued down in-band (two greps,
  milliseconds).
- **4.8 PAT halt** — PASS: grep over the plan body returned no hits.
- **4.9 UI wireframe** — not triggered: no UI-surface files.
- **4.10 Encryption posture** — not triggered: no persistent store; the only new connection
  is an ephemeral loopback fixture torn down in-process.
- **4.11 Guard Contract halt** — PASS: `python3 scripts/lint-guard-contract.py` →
  `2 guard entries`, all fields present; assemblies are structural (chokepoint + dispatch,
  not member lists).
- **Quality checks** — no rule IDs cited (vacuous); `#8372`/`#7552` verified live
  (`gh issue view`: OPEN / MERGED-PR); ADR-177/180/181/188/193 exist on disk; file:line
  citations re-verified and `:962` corrected to `:961-963`; no SHA pins, no prescribed labels,
  no workflow-constant invariants, no pathspec-regex translations.
- **Learnings applied** — 2026-08-13 red-gate arming (exit-0 enumeration added);
  2026-08-13 lower-bound (SKIPPED ceiling is a ceiling, decline cost asserted by
  construction); 2026-09-07 guard-dies-on-its-case (trap/errexit interaction checked —
  `cleanup_test` idempotent, `set -uo pipefail` no `-e`); 2026-07-20 evidence-discarding
  (probe now captures server stderr rather than discarding it).

## Problem Statement / Motivation

On a dev host that lacks a capability two registered suites assume, the suites report RED —
indistinguishable from a real regression to anyone running
`apps/web-platform/infra/run-registered-suites.sh` or `scripts/test-all.sh` locally (#8372).
Both are green in CI because the `deploy-script-tests` runner is contracted to provide the
capabilities. The failures are environmental, not diff-caused, and the correct verdict for
"the host cannot run this suite" is a printed SKIP/decline — the repo's ADR-181/ADR-188
doctrine — not a RED that trains readers to distrust the suite set.

- `canary-bundle-claim-check.test.sh` exits 2 (`FATAL: http.server did not start on port <N>
  within 4s`) at F1. Reproduced during planning: `python3 -m http.server` on this host emits
  no listener and no stderr within the window, while a raw `socketserver.TCPServer` binds
  instantly — the stall is in the CLI startup path, not the socket layer. Any probe that does
  not exercise the real `python3 -m http.server` invocation false-greens on this host.
- `zot-config-deadlines.test.sh` exits 1 at its digest half: `docker info` →
  `permission denied ... unix:///var/run/docker.sock` for this user. The fail-closed arm is
  correct *as a default*; what it lacks is the off-CI decline route the repo's other
  docker-dependent suites already have. Its static half, S4 mutation battery, and both floors
  need no docker and should still run on a dockerless host.

## Proposed Solution

Apply the existing `_skip()` capability-decline convention (verbatim shape from
`git-data-emit.test.sh:28-35`, `git-data-ownership.test.sh:248-270`,
`cloud-init-plugin-seed.test.sh:17-25`) to the two suites. No new files, no workflow changes,
no shared helper.

### Suite 1 — `canary-bundle-claim-check.test.sh` (whole-suite capability gate)

1. Add a `_skip()` helper — verbatim shape from `git-data-emit.test.sh:28-35`:

   ```bash
   _skip() {
     if [ "${CI:-}" = "true" ]; then
       echo "$1 — and CI=true, so this is a FAILURE: the runner must provide this dependency. A gate that cannot run must not report success." >&2
       exit 1
     fi
     echo "$1" >&2
     exit 0
   }
   ```

   Callers embed the `SKIP` marker in the message (the convention's form); the
   `GITHUB_ACTIONS` variant used by `cloud-init-inngest-bootstrap.test.sh` is an acceptable
   alternative but `${CI:-} = true` is the dominant in-suite form and GitHub sets `CI=true`
   unconditionally.
2. Convert the existing `command -v python3` precondition (:24-27) from `FATAL`/exit 2 to
   `_skip "canary-bundle-claim-check: SKIP — python3 required for fixture HTTP server"`. Add
   the same check for `curl` (the suite's readiness probe depends on it). Keep
   `[[ ! -x "$SCRIPT" ]]` at exit 2 — a missing script is a repo defect, not a host
   capability.
3. Add `probe_loopback_http()` — a single up-front probe that runs the suite's real fixture
   mechanism: `alloc_port` → `python3 -m http.server "$port" --directory <scratch>` → the same
   20×0.2s `curl -fsS -m 1 http://localhost:$port/` readiness loop as `start_server` → kill +
   reap + `rm -rf` the scratch dir. Placement: immediately after the `start_server`
   definition (~:104), before F1 — the probe needs `alloc_port`, and the `cleanup_test` EXIT
   trap (:83) is already armed and idempotent, so an `exit 0` from `_skip` is safe.
   **Evidence preservation (learning 2026-07-20):** the probe must NOT discard the server's
   stderr with `>/dev/null 2>&1` — capture it to a file in the scratch dir and print its tail
   on failure, so the SKIP verdict carries *why* the capability is absent (on this host the
   CLI emits no output at all, which is itself a datum worth printing).
   On failure: `_skip "canary-bundle-claim-check: SKIP — python3 http.server cannot
   bind+serve loopback on this host; the fixture mechanism every F-row depends on is absent
   (CI exercises the full suite)"`.
4. Leave all 13 `start_server || exit 2` sites (:201-396) unchanged: after a passing probe the
   capability is established, so a mid-suite bind failure is a real flake/regression and
   stays `FATAL`.

### Suite 2 — `zot-config-deadlines.test.sh` (partial-arm decline)

The digest half (docker `zot verify` + negative control) is the only docker-dependent arm.
The static half and S4 battery run regardless.

1. Keep the `SOLEUR_ZOT_GUARD_NO_DIGEST=1` explicit-decline arm and the pinned-image
   readability check (`ZOT_IMAGE` empty → `fail`) unchanged and ahead of the capability gate:
   the pin's existence is a static property testable without docker.
2. Replace the `fail` arm at :198-199 with the two-route capability gate:
   - `${CI:-} = true` or `GITHUB_ACTIONS` set → keep `fail` (wording updated to name the
     contract: the `deploy-script-tests` runner supplies docker; the
     `Assert docker is available` step at `infra-validation.yml:961-963` precedes this suite's
     step at :1420 — a daemonless CI run is a runner defect, never a decline).
   - otherwise → print the explicit verdict (ADR-181 shape):
     `SKIP: docker absent or daemon unreachable by this user — digest acceptance half declined`,
     plus the existing consequence line `The static relations above were checked; ACCEPTANCE
     BY ZOT WAS NOT OBTAINED.` — then set `DIGEST_SKIPPED=1` and add 2 to a `SKIPPED` counter
     (the decline is counted and denominated in assertion cost per ADR-188 property 4).
3. Accounting: gate the `+2` term of `EXPECTED_MIN` (:243) on the digest half having run —
   introduce `DIGEST_RAN=1` inside the digest-run arm (or equivalently subtract when
   `DIGEST_SKIPPED` is set) so a capability-declined run's floor reflects the assertions
   actually dispatched. Init `SKIPPED=0` beside `PASS`/`FAIL` (:34-35), print the decline
   count on its own line in `finish()` (`=== Skipped: $SKIPPED assertion(s) declined ===`,
   only when `SKIPPED > 0` — the existing `=== Results:` format stays verbatim; verified no
   consumer greps this suite's Results line), and add a ceiling assertion `SKIPPED <= 2`
   adjacent to the floor block — the decline site is single and its cost is fixed at the
   digest pair (`SKIPPED` is 0 or 2 by construction; the ceiling catches a second decline
   site sneaking in).
4. The literal `FAIL_FLOOR_MIN=7` (:309) is untouched: 7 is the smallest legitimate population
   (the S4 child), which is unchanged. Re-run `scripts/guard-vacuity-floor.test.sh` after the
   edit — the floor region is under that suite's mutant-construction scope and the
   `EXPECTED_MIN` expression change must stay constructible.

### Doc consistency — `run-registered-suites.sh` header

The header's tooling table (:36-49, :71-87) says "TWO registered suites need a real docker
daemon" and lists the skip convention. Re-derive it: zot-config-deadlines becomes a third
conditional docker consumer (digest half only), and the `docker info` ordering paragraph
(:61-67) gains this suite as covered by the :961-963 assert step. The header itself instructs
re-derivation; keep the list's shape (suite names + measured cost).

## Technical Considerations

- **Verdict taxonomy (ADR-181/ADR-188).** Capability-absent on a non-CI host → printed
  SKIP/decline, exit 0 (whole suite) or partial decline (zot digest half). Capability-absent
  under CI → hard fail: the runner is *contracted* to provide docker and python3, so absence
  there is a provisioning defect, per ADR-188's ownership table row
  ("docker / terraform / python3 absent → the runner, contracted → hard fail under CI").
  This also matches the workflow's existing `Assert docker is available` step — the suite's
  CI arm is defense-in-depth, not the sole gate.
- **Probe fidelity.** The canary probe must invoke `python3 -m http.server` itself — measured
  on this host during planning: raw `socketserver` binds instantly while the CLI path stalls
  before binding (likely name-resolution in `_get_best_family`/`getfqdn`; the mechanism is
  not in scope — only the capability verdict is). A substitute probe (raw bind, `/dev/tcp`,
  `nc -l`) would false-green here.
- **Exit-code contract consumers** (enumerated, per "everything that EXECUTES these bytes"):
  `infra-validation.yml` `run:` steps (:1201, :1420) — any non-zero reds the step;
  `run-registered-suites.sh` — exit 0 prints PASS (documented trade-off: a self-skip is not
  distinguished locally; the printed `SKIP:` verdict is in the per-suite log);
  `scripts/test-all.sh` — nested `run_suite` sees exit 0; `main-health-monitor.yml` greps the
  *runner's* `^RED `/`^\[FAIL\]` output, unaffected. `zot-config-deadlines`'s S4
  `synth_case` children set `SOLEUR_ZOT_GUARD_NO_DIGEST=1` explicitly — they take the
  DECLINED arm and never probe docker (hermetic + faster; unchanged).
- **Portability.** New code uses only `python3`, `curl`, `seq`, `sleep`, `mktemp`, `kill`,
  `wait`, `rm` — all already used by these suites; no GNU-only flags, no `timeout` builtin
  (absent on stock macOS). `curl -m 1` bounds each probe attempt; the 20-iteration loop
  bounds the total at ~4s, matching the existing readiness window.
- **Deterministic simulation seams** for the decline arms (no host mutation needed):
  a PATH-prepended stub `curl` (exit 7) forces the canary probe to fail; a PATH-prepended
  stub `docker` (exit 1 on `info`) forces the zot decline arm; `CI=true` in the environment
  selects the fail-closed arm in both. The real dev host already provides the genuine
  negative case for both suites.
- **Every path to exit 0, enumerated** (learning 2026-08-13 — turning a red gate green arms
  whatever the red was silently gating). Canary: (a) precondition `_skip`, (b) probe `_skip`,
  (c) all 13 fixtures pass — no bare `else`, no other exit-0 path exists; (a)+(b) fire only
  before F1, so nothing downstream is newly reachable. Zot digest dispatch: (a) `NO_DIGEST=1`
  → DECLINED, (b) docker unreachable + non-CI → SKIP + `SKIPPED+=2`, (c) digest runs →
  normal pass/fail; the dispatch ends in the *run* arm, not a bare decline, so adding a case
  cannot mint a new exit-0 path. Selector ownership: the `CI`/`GITHUB_ACTIONS` selector is
  set by the runner environment, not by the subject under test — a forged `CI=true` can only
  push toward failure, never toward skip.

## Files to Edit

- `apps/web-platform/infra/canary-bundle-claim-check.test.sh` — add `_skip` helper +
  `probe_loopback_http` + probe call; convert python3 precondition; add curl precondition.
- `apps/web-platform/infra/zot-config-deadlines.test.sh` — two-route capability gate in the
  digest half; `DIGEST_SKIPPED`/`SKIPPED` accounting; `EXPECTED_MIN` conditional term;
  `=== Skipped:` line in `finish()`; decline-ceiling assertion.
- `apps/web-platform/infra/run-registered-suites.sh` — header tooling table + docker-assert
  ordering paragraph re-derived (comment-only edit).

## Files to Create

None.

## Implementation Phases

### Phase 1: canary suite capability gate

- Add `_skip()` (CI → exit 1 + runner-contract message; local → `SKIP:` + exit 0).
- Add `probe_loopback_http()`; invoke once after the precondition block.
- Convert `command -v python3` to `_skip`; add `command -v curl` the same way.
- Success criterion: on this host the suite prints the SKIP verdict and exits 0; under
  `CI=true` with a failing `curl` stub it exits 1.

### Phase 2: zot digest-half decline

- Split the docker-unavailable arm into the CI-fail / local-SKIP routes.
- Add `DIGEST_SKIPPED`/`SKIPPED` accounting and re-key `EXPECTED_MIN`'s digest term on the
  digest half having run.
- Keep `SOLEUR_ZOT_GUARD_NO_DIGEST=1` and the `ZOT_IMAGE` pin check unchanged.
- Success criterion: on this host the suite exits 0 with the SKIP verdict and the static+S4
  assertions in the `Results` line; under `CI=true` with a failing `docker` stub it exits 1;
  `SOLEUR_ZOT_GUARD_NO_DIGEST=1` still prints DECLINED.

### Phase 3: runner header re-derivation

- Update the tooling table and docker-ordering paragraph in `run-registered-suites.sh`.

### Phase 4: verification battery

- Run both edited suites on this host (genuine capability-absent case), the stub-forced
  arms, and `CI=true` arms.
- Re-run `scripts/guard-vacuity-floor.test.sh` and
  `plugins/soleur/test/zot-http-deadlines-required.test.sh`.
- Confirm `bash apps/web-platform/infra/run-registered-suites.sh --list` still derives both
  suites.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing on the product surface — the only
  reachable blast radius is internal: a suite that false-SKIPs in CI would lose coverage on
  the zot config (a deploy-safety guard) without anyone noticing. That arm is defended by the
  `CI`-conditional hard-fail and the workflow's own `docker info` assertion step.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no vector — the
  change touches test scripts only; no user data, credentials, or network egress change.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the touched files are local/CI test harnesses under
  apps/web-platform/infra/; they exercise deploy-time scripts against synthesized fixtures and
  never reach a production surface or user data.`

## Observability

```yaml
liveness_signal:
  what: "the suites' own verdict lines — 'SKIP: <reason>' + '=== Results:' / 'Tests run:' —
    per-suite log under run-registered-suites.sh's log dir locally, and the deploy-script-tests
    step log in CI"
  cadence: "per local run / per PR (deploy-script-tests job)"
  alert_target: "RED line in run-registered-suites output; required-check red on the PR"
  configured_in: "apps/web-platform/infra/run-registered-suites.sh; .github/workflows/infra-validation.yml:961-963,1200,1420"
error_reporting:
  destination: "suite stderr/stdout captured to the runner's per-suite log; CI step log"
  fail_loud: "non-zero exit -> 'RED <path>' locally; step failure in CI"
failure_modes:
  - mode: "capability absent, non-CI host"
    detection: "printed SKIP/decline verdict line in the suite log + exit 0"
    alert_route: "visible in the suite log; counted in SKIPPED for the zot digest half"
  - mode: "capability absent under CI"
    detection: "exit 1 with 'the runner must provide this dependency' + the workflow's Assert-docker step (:961-963) reds the job earlier anyway"
    alert_route: "required-check failure on the PR"
  - mode: "real regression with capability present"
    detection: "unchanged FAIL/FATAL paths (exit 1/2)"
    alert_route: "required-check failure on the PR"
logs:
  where: "run-registered-suites.sh per-run log dir; GH Actions step log"
  retention: "run-scoped locally; 90d GH Actions retention"
discoverability_test:
  command: "bash -c 'grep -q \"SKIP\" apps/web-platform/infra/canary-bundle-claim-check.test.sh && grep -q \"SKIP\" apps/web-platform/infra/zot-config-deadlines.test.sh && echo ok'"
  expected_output: "ok"
  # The command matches the over-inclusive suite-shape detector (the probed files carry
  # `.test.sh` names), but it is two `grep -q` calls — it finishes in milliseconds, far
  # inside Check 10's 15s cap. Argued down per the detector's own false-hit clause.
```

## Gate dispositions (Phases 2.7–2.11)

- **2.7 GDPR** — skipped. No schema/migration/auth/API-route/`.sql` surface; no LLM processing
  of session data; threshold is `none`; no cron reading learnings/specs; no new artifact
  distribution surface.
- **2.8 IaC routing** — skipped. No server, service, cron, vendor account, DNS record, cert,
  secret, or firewall rule is introduced; all edits are inside test scripts and a comment
  block.
- **2.10 ADR/C4** — no new architectural decision: the verdict taxonomy applied here is
  ADR-181 + ADR-188's own (runner-contracted precondition → hard fail under CI; absent
  locally → counted/printed decline). This plan applies the decision; it does not extend or
  reverse it. No new external actor, external system/vendor, container/data-store, or
  access relationship is introduced — the suites' consumer set is enumerated in Technical
  Considerations and is unchanged in shape.
- **2.11 Encryption posture** — skipped. No persistent store; no new cross-component
  connection (the probe is loopback-only on an ephemeral port, torn down in the same
  process).
- **2.9.1 Soak enrollment** — not triggered: no acceptance criterion is time-gated.

## Guard Contract

### Guard 1 — canary loopback-HTTP capability gate (`canary-bundle-claim-check.test.sh`)

**Property.** The suite exits 0 with a printed `SKIP` verdict iff `python3 -m http.server`
cannot bind+serve loopback on a non-CI host; under CI the same absence is a hard failure;
when the capability is present the suite is unchanged and any mid-suite fixture failure still
exits 2.

**Assembly.** One chokepoint: the `probe_loopback_http` call between the precondition block
and F1 — every F-row's fixture flows through `start_server`, which is the identical mechanism
the probe exercises, so a probe pass is a honest precondition for all 13 fixtures. Secondary
members: the `command -v python3` and `command -v curl` precondition checks routing through
the same `_skip` helper.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Probe call deleted (the gate's own dispatch removed) | RED on a capability-absent host — F1's `start_server` exits 2 instead of a clean SKIP |
| 2 | Predicate inverted (`probe_loopback_http && _skip`) | RED under `CI=true` on a capable host — `_skip` fires with CI set → exit 1 |
| 3 | Probe weakened to a raw socket bind instead of `python3 -m http.server` | RED on this dev host — measured: raw bind succeeds while the CLI path never binds, so the suite proceeds and exits 2 at F1 |
| 4 | `_skip`'s CI arm removed (always exit 0) | RED — `CI=true` + failing-curl stub must exit non-zero; scenario asserts it |
| 5 | Capability established, then a second `start_server` call fails mid-suite | RED (exit 2) — fail-closed preserved after a compliant first probe; this is the "second member" row: the gate must not license later fixture failures |
| 6 | Harness row — `_skip` prints `SKIP:` but exits non-zero | RED — the runner prints RED on any non-zero; scenario asserts exit 0 on the local skip arm |
| 7 | Must-PASS — capable host, no mutations | PASS — all 13 fixtures run, `Tests run:`/`Tests failed: 0`, no `SKIP` line; verified by the PR's own `deploy-script-tests` run |

### Guard 2 — zot digest-half capability decline (`zot-config-deadlines.test.sh`)

**Property.** The digest half runs iff `SOLEUR_ZOT_GUARD_NO_DIGEST` is unset AND docker is
reachable; a capability decline prints an explicit verdict, counts 2 skipped assertions,
still runs the static half + S4 battery + floors, and never lets the two un-run digest
assertions into `EXPECTED_MIN`; under CI the same absence is a hard failure.

**Assembly.** The digest-block dispatch (:191-227) — the single chokepoint every digest
assertion flows through — plus `EXPECTED_MIN`'s conditional terms (:239-243), the results
summary (:40-42), and the floor block (:291-313). The S4 children are a second entry point
into the file but are pinned to `SOLEUR_ZOT_GUARD_NO_DIGEST=1`, so they route through the
same decline accounting by construction.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `EXPECTED_MIN` digest term still keyed on the env var only (decline forgets to re-key) | RED — a capability-declined run demands 2 assertions that never ran → rc=2 on a healthy decline |
| 2 | Capability check drops `docker info` (tests `command -v docker` only) | RED on this host — `/usr/bin/docker` exists but the socket denies this user; the digest half would run and fail |
| 3 | Decline arm also skips the static half (early exit before render/relations) | RED — assertion count collapses below `FAIL_FLOOR_MIN=7` → rc=2 |
| 4 | Local SKIP verdict removed but dispatch still skips the half | RED — "a decline is an explicit, printed verdict" (ADR-181); scenario asserts the `SKIP`/`ACCEPTANCE BY ZOT WAS NOT OBTAINED` lines |
| 5 | `CI=true` arm dropped — decline reachable under CI | RED — simulated `CI=true` + docker stub must exit non-zero |
| 6 | Harness row — `SKIPPED` incremented but omitted from the summary output | RED — scenario asserts the skipped count is printed (a counted decline that is not reported is a silent one) |
| 7 | Must-PASS — docker reachable, `NO_DIGEST` unset | PASS — digest pair runs, `EXPECTED_MIN` includes +2, suite green; verified by `deploy-script-tests` on the PR |

## Acceptance Criteria

- [ ] AC1 — On a host where `python3 -m http.server` cannot serve loopback (this dev host, or
  a PATH-prepended `curl` stub exiting 7), `bash
  apps/web-platform/infra/canary-bundle-claim-check.test.sh` exits 0 and prints a line
  containing `SKIP`; zero F-rows execute.
- [ ] AC2 — Same forced absence with `CI=true` in the environment: the suite exits non-zero
  and prints a line containing `the runner must provide this dependency`.
- [ ] AC3 — The PR's own `deploy-script-tests` run executes all 13 canary fixtures green (the
  `Run canary-bundle-claim-check.sh tests` step succeeds; no `SKIP` line in its log).
- [ ] AC4 — On a host where `docker info` cannot reach the daemon (this dev host, or a
  PATH-prepended `docker` stub failing `info`), `bash
  apps/web-platform/infra/zot-config-deadlines.test.sh` exits 0, prints the digest-decline
  `SKIP` verdict and `ACCEPTANCE BY ZOT WAS NOT OBTAINED`, prints a
  `=== Skipped: 2 assertion(s) declined ===` line, and its assertion count meets the
  decline-adjusted floor (no rc=2).
- [ ] AC5 — Same forced absence with `CI=true`: the suite exits non-zero.
- [ ] AC6 — `SOLEUR_ZOT_GUARD_NO_DIGEST=1 bash
  apps/web-platform/infra/zot-config-deadlines.test.sh` still prints the `DECLINED:` verdict
  (the explicit-decline path is unchanged).
- [ ] AC7 — `bash scripts/guard-vacuity-floor.test.sh` and `bash
  plugins/soleur/test/zot-http-deadlines-required.test.sh` are green after the edit (the
  floor region stays mutant-constructible; the operand pin is untouched).
- [ ] AC8 — `bash apps/web-platform/infra/run-registered-suites.sh --list` derives both
  suites, and `grep -n "zot-config-deadlines" apps/web-platform/infra/run-registered-suites.sh`
  shows the suite named in the tooling/ordering paragraphs (the header no longer claims only
  two docker-dependent suites).
- [ ] AC9 — On a capable host (CI or a docker-abled dev host), `zot-config-deadlines.test.sh`
  runs the digest pair — `the pinned zot digest ACCEPTS the rendered config` and its negative
  control appear in the output (verified via the PR's `deploy-script-tests` run).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-harness capability gating on internal CI/dev
tooling. The mechanical UI-surface scan over `## Files to Edit` found no UI-surface paths
(all `.sh` under `apps/web-platform/infra/`). Sequential-fallback note: domain leaders were
assessed inline rather than spawned (no Task tool in this pipeline context); each domain's
assessment question resolves negative for a change confined to test scripts.

## Open Code-Review Overlap

None — 68 open `code-review` issues queried; no body mentions
`canary-bundle-claim-check.test.sh`, `zot-config-deadlines.test.sh`, or
`run-registered-suites.sh`.

## Alternatives Considered

- **Host fix (docker group / python shim)** — out of scope per the issue; requires sudo.
  Capability-gating is the chosen remediation; the host fix remains available to the operator
  independently.
- **Unconditional self-skip (plugin-seed shape, no CI arm)** — rejected for the canary suite:
  unlike docker (which has a dedicated `Assert docker is available` step), no workflow step
  asserts the http.server capability, so an unconditional skip would silently disarm the
  suite in CI. The `CI`-conditional form keeps the gate self-contained.
- **`exit 77` (automake SKIP) or a new runner taxonomy** — rejected: the runner treats any
  non-zero as RED, and the PASS-for-skip trade-off is already documented and accepted in the
  runner header; a taxonomy change is a wider blast radius than this issue scopes.
- **Shared `_skip` helper file** — rejected (Cut List): the convention is per-suite inline
  copies; no lib dir exists under `apps/web-platform/infra/`.

## Non-Goals

- No changes to `canary-bundle-claim-check.sh` (the script under test) or
  `registry-userdata-budget.sh` / `zot-registry.tf`.
- No workflow edits — the `Assert docker is available` step and both `run:` steps are
  unchanged.
- No runner (`run-registered-suites.sh`) behavior change — header comments only.
- No fix to this host's docker group membership or python installation.

## Test Scenarios

- Given a host where `python3 -m http.server` never binds, when the canary suite runs, then
  it prints `<suite>: SKIP — python3 http.server cannot bind+serve loopback ...` and exits 0.
- Given `CI=true` and a `curl` stub that always exits 7 on PATH, when the canary suite runs,
  then it exits 1 with the runner-contract message.
- Given a capable host, when the canary suite runs, then all 13 fixtures report PASS and no
  `SKIP` line appears (covered by AC3/CI).
- Given `docker info` fails (real on this host; stubbed elsewhere), when the zot suite runs,
  then it prints the SKIP decline, the static relations + 3 S4 rows still report, an `=== Skipped:`
  line is printed, and exit is 0.
- Given `CI=true` and the same docker failure, when the zot suite runs, then exit is
  non-zero.
- Given `SOLEUR_ZOT_GUARD_NO_DIGEST=1`, when the zot suite runs (any host), then the
  `DECLINED:` arm prints and the digest half does not execute (regression of the unchanged
  path).
- Given the probe passes but a later `start_server` fails (mutation row 5, Guard 1), then the
  suite exits 2 — mid-suite fixture failures stay fail-closed.

Verification commands (deterministic, local):

- `bash apps/web-platform/infra/canary-bundle-claim-check.test.sh; echo "rc=$?"` — on this
  host: `rc=0` + `SKIP` line.
- `bash apps/web-platform/infra/zot-config-deadlines.test.sh; echo "rc=$?"` — on this host:
  `rc=0` + SKIP verdict + `=== Skipped:` line.
- `bash scripts/guard-vacuity-floor.test.sh | tail -3` — green.
- `bash apps/web-platform/infra/run-registered-suites.sh --list` — both suites derived.

## Success Metrics

- On this dev host (and any capability-absent host), both suites exit 0 with printed SKIP
  verdicts instead of RED — `run-registered-suites.sh` reports them PASS with the verdict in
  the per-suite log.
- In CI, both suites execute their full assertion sets (capability present; `deploy-script-tests`
  green on the PR).
- Zero change in verdict on capability-present hosts: the canary suite still exits 2 on a
  mid-suite bind failure; the zot suite still fails closed on any digest-half regression.

## Dependencies & Risks

- **Risk: silent coverage loss locally.** A SKIP prints as PASS through the runner —
  pre-existing, documented trade-off (`run-registered-suites.sh` :45-49). Mitigated by the
  printed verdict in the per-suite log and by CI, where the capability is contracted and the
  skip is unreachable.
- **Risk: the `EXPECTED_MIN` re-keying interacts with the floor-mutant construction.**
  `guard-vacuity-floor.test.sh` slices the floor region; the edit must keep the literal
  `FAIL_FLOOR_MIN=7` bound adjacent and the derived check constructible — AC7 re-runs it.
- **Risk: a probe pass + mid-suite bind flake** now reads as `FATAL` exit 2 on a flaky host
  that previously failed identically — unchanged semantics, correct direction (capability
  present ⇒ flake is a real RED).
- **Risk: `CI`/`GITHUB_ACTIONS` unset in a non-GitHub CI.** Both GitHub-hosted runners and
  the `CI=true` convention are already the repo-wide discriminator (same check in
  `git-data-emit`, `git-data-ownership`, `cloud-init-inngest-bootstrap`); no new assumption.
- **Known staleness, not introduced here:** the `Assert docker is available` step name
  (:961-963) names only `cloud-init-plugin-seed` though `git-data-runcmd-rehearsal` already
  needs the daemon; this change adds a third conditional consumer. Widening the step name is
  a one-line workflow comment edit — deliberately left out of scope (Non-Goals) but worth a
  follow-up line in the PR description.
- **Dependency:** none beyond existing tools (`python3`, `curl`, `docker` where present).

## Sharp Edges

- The probe MUST exercise `python3 -m http.server` itself — a raw-socket substitute was
  measured to false-green on this host during planning (Guard 1 matrix row 3 pins this).
- `EXPECTED_MIN`'s digest term must key on whether the digest half *ran*, not only on
  `SOLEUR_ZOT_GUARD_NO_DIGEST` — a second decline route (capability) joins the first, and
  keying on the env var alone collapses every capability decline into rc=2.
- Editing inside the `EXPECTED_MIN`/`FAIL_FLOOR_MIN` region is inside
  `guard-vacuity-floor.test.sh`'s mutant-construction scope — keep the literal floor adjacent
  to its check and re-run the suite (AC7).
- A `SKIP` verdict that is printed but not counted in the summary is the "decline that is not
  reported" class; the `=== Skipped:` line in `finish()` is the contract (Guard 2
  matrix row 6).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled
  with a concrete artifact and a concrete vector; do not reduce either to a category name.

## Review and Consult Provenance

- Research, SpecFlow-style edge analysis, domain sweep, and plan-review panel ran as
  sequential-fallback inline passes — this pipeline context provides no Task/subagent tool.
  `Reviewed-Coverage: sequential-fallback` — no independent agent review was performed.
- Phase 4.5 scoped advisor consult: not spawned (same constraint); the riskiest phase is
  Phase 2 (`EXPECTED_MIN` accounting + the CI/local verdict split), self-reviewed against
  ADR-188's ownership table and the suite's floor mechanics.

## References & Research

- Issue: #8372 (OPEN — premise verified at plan time)
- ADR-181 `local-gate-declines-are-counted-verdicts`; ADR-188
  `a-transient-environment-decline-is-reachable-under-ci` (ownership table is the governing
  rule); ADR-180 (guard contract as plan deliverable); ADR-177 (unresolved is not failed).
- Convention sources: `apps/web-platform/infra/git-data-emit.test.sh:28-38`,
  `git-data-ownership.test.sh:248-270`, `git-data-cutover-access.test.sh:1202-1212`,
  `cloud-init-plugin-seed.test.sh:17-25`, `cloud-init-inngest-bootstrap.test.sh:461-480`.
- `apps/web-platform/infra/run-registered-suites.sh` header (:36-49, :61-67, :71-87);
  `.github/workflows/infra-validation.yml` :961-963, :1200-1201, :1420.
- Prior plan-time precedent for the sensitive-path scope-out on this exact file:
  `knowledge-base/project/specs/feat-one-shot-resolve-security-alerts/session-state.md`.
