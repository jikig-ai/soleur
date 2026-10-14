# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-16-fix-t5-checksum-never-evaluated-plan.md`
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verification: `git diff origin/main...HEAD --name-only` listed only
  `knowledge-base/project/plans/` and `knowledge-base/project/specs/` — planning subagent
  stayed within its plan-only mandate.
- Post-plan collision re-probe: plan frontmatter `closes: 7565` matches the ref already
  cleared at Step 0a.5 (OPEN, zero closing PRs, empty linked-issue / body / title / `git log`
  probes). No newly-discovered target, so no additional probe was required.

### Errors
- **Self-inflicted, caught and reversed.** The first plan revision inherited issue #7291's
  stated causal story ("a slow/failed download aborts at curl, so `CHMOD_RAN` never prints")
  without probing it, and built a `DL_CURL_OK` marker, an `arm_skip`/`SKIPPED_ASSERTIONS`
  ceiling apparatus, a new ADR, and a recommendation to supersede the open draft PR on top of
  it. A probe of `main`'s actual instrumentation under a blocked CDN showed the mutation arm
  **passes**, falsifying the premise. Roughly two-thirds of the plan was cut and three
  conclusions reversed.
- `deepen-plan` halt 4.6 failed on first run: `brand_survival_threshold: none` with a
  sensitive-path match (`apps/[^/]+/infra/`) and no literal scope-out bullet. Added; gate passes.
- Two enumerations first offered as exhaustive were wrong and are corrected in the plan:
  `$CAPTURE` has six readers (not three); the harness runs eight `docker run --rm` (not four).
- **Review panel not fully spawned:** `spec-flow-analyzer` and `cto` did not run. The design was
  reversed by the first four reviewers before those two would have reviewed anything current.
  Recorded rather than implied as full coverage.

### Decisions
- **The issue's own premise is falsified.** `sha256sum` writes its verdict
  (`/tmp/doppler.tar.gz: FAILED`) to **stdout**, which the harness already captures — only the
  WARNING summary goes to the redirected stderr. The checksum-specific assertion therefore needs
  zero new instrumentation, and the `CURL_OK` marker the issue proposed is dominated by it.
- **The `$` anchor is load-bearing.** A missing tarball yields `FAILED open or read` on the same
  stream; an unanchored `: FAILED` would re-create this bug in a new disguise. Verified by
  executing the acceptance criterion's literal pattern against real captured output from all
  three cells.
- **A bare `&&` is correct for `CHMOD_RAN`**; a heavier errexit-preserving tail is unobservable
  (no arm can reach a failing `chmod` under `set -e`) and misfires when `echo` itself fails.
- **Issue 7291 is NOT closed and its open draft PR is NOT superseded.** Its `DRIVER_REACHED_DL`
  absence key is correct for its real cause: when apt-install fails, the container emits zero
  bytes, so absence is the only available signal. This plan deliberately leaves the apt lines
  untouched so that PR rebases cleanly, and contributes the probe evidence back.
- **No ADR.** Once the decline apparatus was cut, the ADR gate stops firing. ADR-181 property 4
  ("a decline is UNREACHABLE under CI") is recorded as independent doctrinal support for failing
  rather than declining on a supply-chain guard.

### Components Invoked
- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Agents: `repo-research-analyst`, `learnings-researcher`, scoped advisor consult,
  `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
  `architecture-strategist`
- Gates: `lint-guard-contract.py`, `lint-infra-no-human-steps.py`, `lint-shell-capture-exit.py`,
  deepen-plan halts 4.5–4.11
- Measurement: 7 container probes in `ubuntu:24.04` (instrumentation matrix, `main`-instrumentation
  falsification, two apt sub-cases, locale sweep) plus 8 single-command bash errexit probes
