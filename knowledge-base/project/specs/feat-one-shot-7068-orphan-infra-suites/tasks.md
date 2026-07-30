# Tasks: feat-one-shot-7068-orphan-infra-suites

**Plan:** `knowledge-base/project/plans/2026-07-29-chore-triage-seven-orphan-infra-suites-plan.md`
**Decision challenges:** `knowledge-base/project/specs/feat-one-shot-7068-orphan-infra-suites/decision-challenges.md`
**Issue:** #7068
**Lane:** single-domain

Triage is **already complete and recorded in the plan** — all 7 suites measured PASS, all 7
subjects-under-test verified live, decision is 7 register / 0 delete. Do **not** re-litigate the
triage; implement it.

## Phase 0: Preconditions

- [x] 0.1 Read the plan's `## Per-Suite Decision Table` and `## Implementation Phases`.
- [x] 0.2 Read `decision-challenges.md` — **DC-1** (include Phase 3 or not) is an open operator
      decision. Default is "include". If dropping it, also drop AC7 and fold its rationale into D1.
- [x] 0.3 Re-confirm the RED baseline so the AC is known able to fail:
      ```bash
      JOB=$(awk '/^  deploy-script-tests:/{f=1;next} /^  [A-Za-z0-9_-]+:/{f=0} f' \
             .github/workflows/infra-validation.yml)
      for s in audit-bwrap-uid cat-infra-config-state cloud-init-plugin-seed \
               inngest-cutover-flip inngest-server-flip-guard live-verify.tf mu1-runbook-cleanup; do
        printf '%s\n' "$JOB" | grep -qE "^[[:space:]]+run: bash apps/web-platform/infra/${s//./\\.}\.test\.sh[[:space:]]*$" \
          || echo "MISSING STEP: $s"
      done   # → all 7 MISSING (the RED baseline)
      ```
- [x] 0.4 Confirm the masking baseline is clean: `continue-on-error` count = 0 and `if:` count = 0
      inside the `deploy-script-tests` slice.

## Phase 1: Register the seven

- [x] 1.1 In `.github/workflows/infra-validation.yml`, `deploy-script-tests` job, adjacent to the
      existing `(#7000) Two ORPHAN suites adopted` block: add one block comment citing #7068 and
      summarising the triage (7 measured green, all subjects live).
      **The comment must NOT contain the string `bash apps/web-platform/infra/<name>.test.sh`** —
      a full token in prose is what makes a suite look registered while running nothing.
- [x] 1.2 Add 6 plain steps, each mirroring the `Rehearse the git-data runcmd chain (abort ordering
      + rc guard)` shape (comment on what it guards, then `- name:` / `run: bash <path>`), for:
      `audit-bwrap-uid`, `cat-infra-config-state`, `inngest-cutover-flip`,
      `inngest-server-flip-guard`, `live-verify.tf`, `mu1-runbook-cleanup`.
      **Single-line `run: bash <path>` with nothing between `run: bash` and the path.**
- [x] 1.3 Add a **separate preceding step** asserting the docker daemon is live, e.g.
      `- name: Assert docker is available (cloud-init-plugin-seed needs a real daemon)` /
      `run: docker info >/dev/null`. Separate on purpose — folding it into the suite's own step
      would make that step a multi-line `run: |`, which the derivation regex cannot match.
- [x] 1.4 Add the `cloud-init-plugin-seed` step itself, with a step-level `timeout-minutes`
      (mirror the `ci-deploy.test.sh` `timeout-minutes: 3` attribution precedent — state the
      measured cost and the multiple in the comment) and a comment recording the docker
      dependency + that the job already builds an image at the sandbox-canary regression step.
- [x] 1.5 **Rewrite** the stale `#7000` paragraph: remove the seven-suite enumeration AND its
      false reason ("would put a container dependency on this job for unrelated scope"), point to
      #7068, keep the two suites #7000 adopted attributed to #7000.
- [x] 1.6 **Update the job's timeout-rationale comment** per its own instruction ("Re-derive this
      if steps are added to the job — the numbers above are a property of its current composition").
- [x] 1.7 `bash scripts/lint-workflows.sh` → exit 0 (NOT bare `actionlint`; it can hang per #7002
      and there are 93 pre-existing findings).
- [x] 1.8 Re-run task 0.3's grep → **no output**.
- [x] 1.9 `bash apps/web-platform/infra/run-registered-suites.sh --list` → no orphan NOTE.
- [x] 1.10 Commit: `ci(infra): register the seven orphan infra suites (#7068)`.

## Phase 2: Dependency record + parallel-run safety

- [x] 2.1 `apps/web-platform/infra/cloud-init-plugin-seed.test.sh`: `$$`-scope the container name
      and image tag (currently fixed `soleur-plugin-seed-test` / `:fixture`, with `docker rm -f` /
      `rmi -f` in the EXIT trap). Registration puts this suite in the local `xargs -P 6` runner,
      where two concurrent worktree runs would delete each other's container mid-test.
- [x] 2.2 Verify: `bash apps/web-platform/infra/cloud-init-plugin-seed.test.sh` still passes.
- [x] 2.3 `apps/web-platform/infra/run-registered-suites.sh`: **comment-only** preamble note
      recording `cloud-init-plugin-seed.test.sh` as the one registered suite needing a real docker
      daemon (operator criterion 2's "recorded at the auto-glob site").
      **No logic change** — derivation, zero-guard, and orphan scan untouched.
- [x] 2.4 `bash apps/web-platform/infra/run-registered-suites.test.sh` → all 11 assertions pass.
- [x] 2.5 Commit: `test(infra): $$-scope plugin-seed docker fixtures; record docker dep (#7068)`.

## Phase 3: Fail-closed registration gate (see DC-1 before starting)

- [x] 3.1 RED first: create `.github/scripts/test/test-infra-suite-registration.sh` and confirm it
      exits non-zero when a Phase 1 `run:` line is removed in a scratch copy. Record the RED output.
- [x] 3.2 Implement: for every `apps/web-platform/infra/**/*.test.sh` on disk, assert a real
      invocation step exists in `infra-validation.yml`; else exit non-zero.
      - Anchor on the **invocation shape**, not a bare basename (`cq-assert-anchor-not-bare-token`).
      - Exclusions carry a reason **AND** a `#NNNN`; a reasonless/issue-less exclusion is an error.
      - **BASH-ONLY** — no terraform, no apt, no python. That contract is why this glob can feed a
        required, merge_group-triggered, path-filter-free check without tripping #6454.
      - Model on `scripts/lint-orphan-test-suites.sh`.
- [x] 3.3 GREEN: `bash .github/scripts/test/test-infra-suite-registration.sh` exits 0.
- [x] 3.4 `bash .github/scripts/test/run-all.sh` → the new suite is auto-globbed and green.
- [x] 3.5 Commit: `ci: fail closed when an infra suite is registered nowhere (#7068)`.

## Phase 4: Verify + ship prep

- [x] 4.1 Re-run all 7 suites individually; capture results for the PR-body table.
- [ ] 4.2 `bash apps/web-platform/infra/run-registered-suites.sh` (full run) → exit 0; record the
      measured wall-clock, not just that the count rose.
- [x] 4.3 File the **D1** follow-up issue for the detector derivation gap. Carry verbatim: the
      79-vs-87 measurement, the `T2b`/`T2d`/`DERIVED`-char-class coupling, the loopback `EXIT=2`
      blast radius (sole offender; other 7 pass unprivileged), the comment-derivation hazard, the
      `79 + 7 + 8 = 94` identity, and the stale `grok-pre-push-gate.sh` "required check" claim.
      Labels: `type/chore`, `domain/engineering`, `priority/p2-medium`.
- [x] 4.4 PR body: per-suite decision table with local result + liveness evidence per suite;
      `Closes #7068` in the **body** (not the title); link the D1 issue; note the
      `inngest-server-flip-guard` textual-coupling tripwire is deliberate.
- [ ] 4.5 After CI: run AC3's `gh api` step-conclusion probe → exactly 7 lines, all `success`.
- [ ] 4.6 Confirm all 8 ACs, then `/soleur:review` → `/soleur:ship`.

## Do NOT do

- ❌ Delete any of the seven suites — all 7 subjects verified live on `origin/main`.
- ❌ Widen `run-registered-suites.sh`'s derivation regex. That is **D1**, deliberately deferred:
  it would add `workspaces-luks-loopback.test.sh` (exits 2 unprivileged) to the local runner and
  turn a mandated ship gate permanently RED.
- ❌ Weaken any assertion to get green. Fix the environment at the call site instead
  (`REGISTRATION IS NOT ENVIRONMENT`).
- ❌ Put anything between `run: bash` and the path, or use a multi-line `run: |` for these steps.
- ❌ Use bare `actionlint` (hangs per #7002); use `scripts/lint-workflows.sh`.
- ❌ Assert `scripts/test-all.sh` as evidence for this diff — it does not cover
  `apps/web-platform/infra/`.
