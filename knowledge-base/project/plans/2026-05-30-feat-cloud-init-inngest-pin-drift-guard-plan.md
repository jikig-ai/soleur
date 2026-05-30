---
lane: procedural
brand_survival_threshold: aggregate pattern
---

# Plan: CI drift-guard for the cloud-init inngest-bootstrap pin (#4675)

♻️ infra / ci

## Enhancement Summary

**Deepened on:** 2026-05-30

### Key Improvements (over the naive "add an assertion" approach)
1. **Caught that the target test runs in zero CI surfaces.** Verified per-test that
   `cloud-init-inngest-bootstrap.test.sh` (and 10 other infra tests) is invoked nowhere —
   `infra-validation.yml` runs a hardcoded list of only 4 infra tests; no `run-tests.sh`,
   no auto-discovery; `test-all.sh` excludes infra. Without an explicit wiring step the
   guard would be dead code. Step 2 now adds the `run:` step, not just a checkout tweak.
2. **Corrected every false premise from the pipeline arguments** (wrong paths, wrong test
   language, wrong claim that git tags can't see the drift) in a Research Reconciliation
   table — all 12 historical releases ARE real git tags, so the guard is fully enforceable.
3. **Pinned semver-max (`sort -V`)** as the comparison, with the plain-`sort` wrong-answer
   contrast captured — this is the exact bug class that hid the original 10-release drift.

### Deepen Gates (all pass)
- 4.6 User-Brand Impact: present, threshold `aggregate pattern` (valid).
- 4.7 Observability: all 5 fields present; `discoverability_test.command` is SSH-free.
- 4.8 PAT-shaped variable: none.
- 4.4 scheduled-work / 4.5 network-outage: N/A (PR-triggered CI assertion, no cron, no SSH
  diagnosis).
- Verify-the-negative: the load-bearing "runs nowhere in CI" claim confirmed (0 wiring
  sites). No KB citations (no broken-citation risk). No self-grep AC scope risk. New bash
  logic is `set -euo pipefail`-safe (string compares + integer `wc -l` only).

## Overview

The cloud-init pin for `ghcr.io/jikig-ai/soleur-inngest-bootstrap` (fresh-host
first-boot only) drifted to a stale `v1.0.0` across ten consecutive bootstrap-image
releases (`vinngest-v1.0.1` … `vinngest-v1.1.10`) before #4669 manually bumped it to
`v1.1.11`. Running hosts get new bootstrap scripts via the `deploy inngest …:vX.Y.Z`
webhook path, but the cloud-init pin was never bumped in lockstep — so a fresh-host
reprovision would have installed an ancient script. The manual "bump the cloud-init pin
on each release" step is reliably forgotten (10 consecutive misses). #4669 added a `MUST
be bumped` comment (cheap mitigation) plus a well-formedness/structure test. This plan
adds the **durable mechanical fix**: a CI drift-guard (Option 1, recommended) that fails
when the cloud-init pin does not match the latest published `vinngest-v*` git tag.

We **extend the existing bash test** `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
rather than create new infrastructure. **Critical caveat (verified this session):** that
test is currently **NOT run anywhere in CI.** `.github/workflows/infra-validation.yml`'s
`deploy-script-tests` job runs an *explicit hardcoded list* of only 4 infra tests
(`ci-deploy`, `ci-deploy-wrapper`, `canary-bundle-claim-check`, `www-apex-canonicalizer`);
there is no `run-tests.sh` and no `*.test.sh` auto-discovery glob. `scripts/test-all.sh`
explicitly excludes `apps/web-platform/infra/*.test.sh` (its own comments say so). So 11 of
15 infra tests — including the one we're extending — execute in zero CI surfaces today.
**Therefore the plan MUST add an explicit CI wiring step** (Step 2) or the drift guard is
dead code. This is the single most important correction over the naive "just add an
assertion" approach.

## Research Reconciliation — Issue/Argument Premise vs. Codebase

The arguments passed to this pipeline contained several factual errors (they described a
hypothetical `.mjs`/node-test layout under `infra/`). The real codebase differs. This
table is the corrected ground truth; build against the **reality** column.

| Premise (from pipeline args / earlier scratch) | Reality (verified this session) | Plan response |
| --- | --- | --- |
| `infra/hetzner/cloud-init.yml` | Path is `apps/web-platform/infra/cloud-init.yml` (517 lines). | Use real path. |
| `infra/inngest-bootstrap/parity.test.mjs` (node `node:test`) | No such file. The real test is a **bash** static test `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` (171 lines, grep/awk-based, `set -euo pipefail`). | Extend the bash test. |
| `scripts/check-deploy-pipeline-parity.mjs` mirror pattern | No such file. The closest mirror is the existing infra bash test + `apply-deploy-pipeline-fix.yml`. | Mirror the bash-test style. |
| Pin tag is `vinngest-v1.1.11` in cloud-init | cloud-init docker tag is the **bare** `v1.1.11` (no `vinngest-` prefix), appearing 3× (lines 464, 468, 471). The git tag is `vinngest-v1.1.11`. | Map `vinngest-vX.Y.Z` (git tag) → `vX.Y.Z` (docker pin). |
| Intermediate releases v1.0.1…v1.1.10 were GHCR-only (no git tags); git tags can't see the drift | **FALSE.** `git ls-remote --tags origin 'vinngest-v*'` shows ALL of v1.0.0…v1.1.11 as real git tags. Git tags ARE the canonical published-release signal. | Git tags are the source-of-truth; the guard is fully enforceable. |
| Test runner is `node --test infra/inngest-bootstrap/` | There is **no** `run-tests.sh` and **no** auto-discovery. `infra-validation.yml` `deploy-script-tests` job runs a hardcoded list of 4 tests; `cloud-init-inngest-bootstrap.test.sh` is NOT in it. `test-all.sh` excludes infra tests. | The test runs nowhere today — Step 2 MUST add an explicit `run:` wiring step, else the guard is dead code. |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is a CI guard.
  The failure mode it *prevents* is: a fresh-host reprovision silently installing a stale
  inngest bootstrap script, which would degrade cron/agentic background processing on the
  newly provisioned host until someone notices. A broken guard (false-green) simply
  returns us to today's manual-memory state.
- **If this leaks, the user's data is exposed via:** N/A — no data surface; the guard
  reads git tags and a tracked YAML file.
- **Brand-survival threshold:** aggregate pattern. (The original drift was a slow
  10-release accumulation, not a single-user incident.)

## Current State

- **`apps/web-platform/infra/cloud-init.yml`** (517 lines) — fresh-host first-boot config.
  The pin appears in the `runcmd` "Bootstrap Inngest server on first boot (#4118)" block:
  - L464 `docker pull ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.11`
  - L468 `docker create --name soleur-inngest-bootstrap-extract ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.11`
  - L471 `image_env=$(docker inspect ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.11 ...)`
  - The header comment (L453-461) already documents that the pin MUST be bumped on each
    bootstrap-script change and that bumping it does NOT redeploy running hosts.
- **`apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`** (171 lines) — a bash
  static test (grep/awk only, no docker). Existing assertions: AC1 (pin tag exactly
  `v1.1.11`, hardcoded in the regex `soleur-inngest-bootstrap:v1\.1\.11`), Config.Env
  sourcing, trap cleanup, AC2 (drift comment present), AC4 (positional ordering + POSIX
  `bash -n`/`dash -n`), AC3 (YAML round-trip), AC5 (sudoers byte-parity). Uses an
  `assert "<desc>" "<condition>"` helper that `eval`s the condition and aggregates
  PASS/FAIL. **Note:** the existing AC1/AC4 hardcode `v1.1.11` in their regexes (test L53,
  L84) — so when a future release bumps the pin, those assertions ALSO need updating. The
  new drift-guard makes the *correct* target loud, but the hardcoded assertions must be
  reconciled (see Sharp Edges).
- **`.github/workflows/infra-validation.yml`** (workflow `Infra Validation`) — triggers on
  `pull_request` for paths `apps/*/infra/**`, `infra/**`, and the workflow file itself,
  plus `workflow_dispatch`. **There is NO `push: [main]` trigger.** Jobs: `detect-changes`
  (matrix of changed infra dirs; its checkout uses `fetch-depth: 0`), `validate`
  (cloud-init schema + `terraform fmt`/`validate` + optional `main.test.sh`),
  `deploy-script-tests` (a **hardcoded list** of 4 `bash …test.sh` steps, L124-134),
  `check-secrets`, `plan`. The `deploy-script-tests` job's `actions/checkout@v4` (L122) has
  **NO `with:` block** → no tags fetched. **The cloud-init test is not invoked by any
  job.** Wiring it into `deploy-script-tests` (which always runs, not matrix-gated) is the
  right home — Step 2.
- **No `run-tests.sh` exists.** Each infra test is invoked individually by an explicit
  `run:` step. Adding a new test surface requires adding an explicit step.
- **Git tags:** `git ls-remote --tags origin 'vinngest-v*'` → `vinngest-v1.0.0` …
  `vinngest-v1.1.11` (all 12 releases present as real annotated git tags). The build
  workflow `.github/workflows/build-inngest-bootstrap-image.yml` is triggered by `push:
  tags: ['vinngest-v*.*.*']`, confirming the git tag is the authoritative
  "image-published" event.
- **Semver vs string sort (the original bug class):** `sort -V` gives latest = `1.1.11`
  (correct); plain `sort` gives `1.1.9` (wrong — the exact lexicographic trap that hid the
  v1.1.10 drift). The guard MUST use `sort -V`.

## Source-of-Truth Decision

**Use git tags `vinngest-v*` as the latest-published signal**, because:
- The build workflow is triggered by `push: tags: ['vinngest-v*.*.*']` — the git tag is
  the authoritative "a new bootstrap image was published" event.
- It needs no registry/network auth (no GHCR API token) and stays hermetic.
- All historical releases are present as git tags (verified), so the comparison is
  complete, not best-effort.

Mapping: a git tag `vinngest-vX.Y.Z` corresponds to a cloud-init docker pin `vX.Y.Z`
(strip the `vinngest-` prefix). The guard extracts the pin, finds the semver-max
`vinngest-v*` tag, strips the prefix, and asserts equality.

CI must (a) actually RUN the test, and (b) fetch tags for the comparison. Step 2 does both:
adds an explicit `run: bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
step to the `deploy-script-tests` job AND adds `fetch-tags: true` + `fetch-depth: 0` to that
job's checkout. **Without tags the guard self-skips** (prints a clear SKIP, does not fail)
— so local runs without fetched tags stay green, and the checkout change is what activates
real enforcement in CI. **Without the run step, the guard never executes at all.**

## Implementation Steps

### Step 1: Add the drift-guard assertion to the existing bash test (RED first)

- **File:** `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
- **Write the failing test first** (cq-write-failing-tests-before): temporarily point the
  expected-latest at a value the pin does not equal, confirm the new assertion FAILs, then
  revert to the real logic.
- **Changes (all using grep/awk/sort, matching the file's existing style — no new deps):**
  1. Extract the pin from cloud-init.yml (unambiguous via the docker pull line):
     ```bash
     PIN=$(grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$CLOUD_INIT" \
       | head -1 | sed 's/.*://')   # → v1.1.11
     ```
  2. List `vinngest-v*` git tags, pick the semver-max, map to the bare docker form.
     Run git from `$SCRIPT_DIR`, wrapped so any failure (no git, no tags, not a repo)
     yields an empty result → SKIP, never FAIL. Do NOT depend on `--show-toplevel` (it
     resolves to the bare-root parent in a worktree; `git -C <subdir> tag --list` works
     regardless):
     ```bash
     LATEST_TAG=$(git -C "$SCRIPT_DIR" tag --list 'vinngest-v*' 2>/dev/null \
       | sed 's/^vinngest-//' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
       | sort -V | tail -1 || true)   # → v1.1.11
     ```
  3. New assertion block — three outcomes:
     - **No tags available** (`-z "$LATEST_TAG"`): `echo "  SKIP: no vinngest-v* tags in
       checkout; drift comparison skipped (CI fetches tags via fetch-tags: true)"` and do
       NOT increment FAIL. (Mirrors the file's existing `SKIP:` convention for dash/visudo.)
     - **Tags present, pin == latest:** `assert "cloud-init pin matches latest published
       vinngest-v* tag ($LATEST_TAG)" "[[ '$PIN' == '$LATEST_TAG' ]]"` → PASS.
     - **Tags present, pin != latest:** same assert → FAIL. Add an explicit `echo` on
       mismatch pointing at the fix: `cloud-init.yml pin $PIN != latest published
       $LATEST_TAG — bump all 3 soleur-inngest-bootstrap:<tag> refs in
       apps/web-platform/infra/cloud-init.yml`.
  4. **Pin-consistency sub-check** (cheap, catches a partial bump):
     ```bash
     DISTINCT=$(grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' "$CLOUD_INIT" \
       | sort -u | wc -l)
     assert "all soleur-inngest-bootstrap pin refs share one tag" "(( DISTINCT == 1 ))"
     ```
     (`DISTINCT` is always an integer from `wc -l`, so `(( ))` is `set -e`-safe.)
- **Verification commands** (pinned in plan; re-run at /work):
  - No-tags path: a checkout lacking tags → drift assertion SKIPs, suite green.
  - Tags path: `git fetch --tags && bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
    → drift assertion PASSes. **Verified this session:** `sort -V | tail -1` over the live
    tag list yields `v1.1.11`; the pin is `v1.1.11`; `DISTINCT == 1`.
  - Negative path: temporarily edit one pin ref to `v1.1.10` → drift assert FAILs with the
    mismatch message AND the consistency sub-check FAILs (`DISTINCT==2`). Revert.

### Step 2: Wire the test into CI AND make the checkout fetch tags

- **File:** `.github/workflows/infra-validation.yml`, job `deploy-script-tests` (L118-134).
  This job always runs (not matrix-gated by `detect-changes`), so the guard fires on every
  PR that triggers the workflow.
- **Change 2a — add tags to the job's checkout** (L122):
  ```yaml
  - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
    with:
      fetch-depth: 0
      fetch-tags: true
  ```
  `fetch-tags` alone is insufficient on a shallow clone; `fetch-depth: 0` makes the tag
  fetch complete (precedent: the `detect-changes` job already uses `fetch-depth: 0`). Keep
  the existing pinned SHA.
- **Change 2b — add an explicit run step** alongside the other 4 (after L134):
  ```yaml
  - name: Run cloud-init inngest-bootstrap pin drift-guard
    run: bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh
  ```
- **Trigger gap to note:** `infra-validation.yml` has NO `push: [main]` trigger — it runs on
  `pull_request` (and `workflow_dispatch`). That is sufficient for a drift-guard (the goal
  is to catch the miss at PR time). A drifted pin can only land via a PR, which this catches.
- The workflow's own `paths:` already includes `.github/workflows/infra-validation.yml`, so
  this edit is covered by its own trigger.
- **Optional hardening (decide inline):** the `pull_request.paths` filter is
  `apps/*/infra/**` — a release PR that ONLY pushes a git tag without touching infra files
  would NOT trigger this workflow. But a drifted pin is itself a missing
  `apps/web-platform/infra/cloud-init.yml` edit, and drift is detected on the NEXT
  infra-touching PR. For the recommended low-effort drift-guard this PR-time coverage
  matches the issue's intent; a tighter per-merge surface is out of scope.

### Step 3: Update the cloud-init header comment to reference the guard

- **File:** `apps/web-platform/infra/cloud-init.yml` (comment block L453-461)
- **Change:** append one sentence noting drift is now mechanically enforced by
  `cloud-init-inngest-bootstrap.test.sh` via the `Infra Validation` workflow. Do NOT change
  the pin value. Keep the existing `MUST be bumped` and `NOT the inngest-cli version`
  phrases intact — the existing AC2 assertion greps for them.

### Step 4: Verify locally and confirm CI semantics

- Run the test directly: `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
  → all assertions green (existing 19 + new drift PASS/SKIP + consistency).
- Exercise all three drift branches (Step 1 verification commands).
- Confirm `infra-validation.yml` change is YAML-valid (`actionlint`, and `bash -c` the
  extracted `run:` snippet), the checkout SHA is unchanged, and the new run step sits in
  `deploy-script-tests` next to the other 4 infra tests.

## Acceptance Criteria

### Pre-merge (PR / CI)
- [ ] `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` passes, and the
      new drift assertion is present (grep the test for `vinngest-v` and `sort -V`).
- [ ] The test is wired into `.github/workflows/infra-validation.yml` `deploy-script-tests`
      job as an explicit `run:` step (grep the workflow for
      `cloud-init-inngest-bootstrap.test.sh`) — closing the "runs nowhere in CI" gap.
- [ ] With tags fetched, the drift assertion PASSes (pin == semver-max tag); output names
      the matched tag.
- [ ] Negative proof captured in PR body: editing a pin ref to an older tag makes the test
      FAIL with a mismatch message naming both values (output pasted, change reverted).
- [ ] No-tags path: a checkout without `vinngest-v*` tags makes the drift assertion SKIP
      (not FAIL) — suite stays green; SKIP line is visible.
- [ ] Pin-consistency sub-check FAILs when the 3 pin refs disagree (negative proof).
- [ ] `.github/workflows/infra-validation.yml` `deploy-script-tests` checkout has
      `fetch-depth: 0` + `fetch-tags: true`; pinned action SHA unchanged.
- [ ] cloud-init.yml header comment references the guard; pin value unchanged; existing
      AC2 phrases (`MUST be bumped`, `NOT the inngest-cli version`) intact.

## Observability

```yaml
liveness_signal:
  what: "Infra Validation workflow, job deploy-script-tests, new step runs cloud-init-inngest-bootstrap.test.sh on PRs touching apps/*/infra/** or the workflow file"
  cadence: "per-PR (pull_request) + workflow_dispatch; no push:[main] trigger"
  alert_target: "GitHub PR required-check status (red = drift)"
  configured_in: ".github/workflows/infra-validation.yml (deploy-script-tests job)"
error_reporting:
  destination: "GitHub Actions job log + failing PR check; failure message names pin vs latest-tag"
  fail_loud: true
failure_modes:
  - mode: "cloud-init pin lags latest vinngest-v* tag (the drift this guards)"
    detection: "drift assertion in cloud-init-inngest-bootstrap.test.sh (sort -V semver-max compare)"
    alert_route: "red Infra Validation check on the PR"
  - mode: "pin refs disagree (partial bump)"
    detection: "pin-consistency sub-check (DISTINCT==1)"
    alert_route: "red Infra Validation check on the PR"
  - mode: "CI checkout fetches no tags -> guard would silently no-op"
    detection: "fetch-tags:true + fetch-depth:0 on checkout; SKIP line is visible in log when tags absent"
    alert_route: "visible SKIP in job log (not a false green that looks like enforcement)"
logs:
  where: "GitHub Actions run logs for Infra Validation"
  retention: "GitHub default (90 days)"
discoverability_test:
  command: "gh run list --workflow=infra-validation.yml --limit 5"
  expected_output: "recent runs with conclusion success; a drifted PR shows failure"
```

## Risks & Mitigations

- **The test runs nowhere in CI today → a guard added without wiring is dead code.**
  (Highest-impact risk; the naive approach misses it.) Mitigation: Step 2 adds an explicit
  `run:` step to `deploy-script-tests`. AC explicitly verifies the wiring grep.
- **CI checkout has no tags → guard silently no-ops.** Mitigation: Step 2 adds
  `fetch-tags`/`fetch-depth: 0`; the test prints a visible SKIP when tags are absent, so a
  tagless run never masquerades as enforcement.
- **String vs semver tag ordering** (`v1.1.10` vs `v1.1.9` vs `v1.1.11`). Mitigation:
  `sort -V`, the exact fix for the bug class that hid the original drift. Verified this
  session that plain `sort` returns the wrong latest.
- **`workflow_dispatch` image builds without a git tag** won't be seen by the guard.
  Accepted — the canonical release path is tag-push (`build-inngest-bootstrap-image.yml`
  `on: push: tags`). Out of Scope.
- **Tag-pushed before the pin PR merges → guard goes red on unrelated PRs.** This is the
  intended behavior (drift = fail). The error message tells the operator which refs to
  bump. Documented in the header comment.
- **Precedent-diff (deepen Phase 4.4):** no in-repo `git tag`-based drift guard exists to
  mirror; the pattern is novel for this repo. The closest precedent is the existing bash
  assert-helper style in this same test file. The chosen extraction (`grep -oE | sed`)
  follows the file's existing grep/awk idiom rather than inventing a new parser. No
  `fetch-tags`/`fetch-depth: 0` precedent exists in any `.github/workflows/*.yml` (verified
  this session) — so Step 2's checkout option is novel-in-repo; the GitHub-documented shape
  (`fetch-depth: 0` + `fetch-tags: true`) is the standard way to get all tags.

### Deepen-plan verification (2026-05-30, run from the worktree)

Every load-bearing one-liner was executed against the live worktree:

- **CI-wiring audit:** `cloud-init-inngest-bootstrap.test.sh` has **0** wiring sites across
  `.github/` and `scripts/`. Only 4 of 15 infra tests run in CI. This is why Step 2 adds an
  explicit run step, not just a checkout tweak.
- Pin extraction `grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+' … | sed 's/.*://'`
  → `v1.1.11`. ✓
- Distinct-pin count → `1` (all 3 refs agree today). ✓
- Latest-tag `git -C apps/web-platform/infra tag --list 'vinngest-v*' | sed 's/^vinngest-//'
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1` → `v1.1.11`. ✓ (matches pin →
  guard PASSes today).
- `git -C apps/web-platform/infra rev-parse --show-toplevel` resolves to the bare-root
  parent, but `git -C <subdir> tag --list` still returns tags correctly — the helper must
  NOT depend on `--show-toplevel`; use `git -C "$SCRIPT_DIR" tag --list` directly.
- Hardcoded `v1.1.11` confirmed at test L53 (AC1 regex), L84 (AC4 regex) — the "hardcoded
  assertions co-exist" Sharp Edge is real and load-bearing.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/infrastructure tooling change. No user-facing
surface, no data surface, no schema/auth/API surface (GDPR gate Phase 2.7 not triggered).

## Infrastructure (IaC)

No new infrastructure is introduced. This plan adds a CI assertion + a checkout option +
a comment. It does NOT provision servers, secrets, vendors, DNS, or runtime processes —
Phase 2.8 routing does not apply. (The cloud-init.yml file it reads is already
Terraform-rendered infra; this change only adds a read-only guard over the tracked source,
no `terraform apply` path.)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails
  `deepen-plan` Phase 4.6. (This plan's section is filled; threshold = aggregate pattern.)
- **Hardcoded-`v1.1.11` assertions co-exist with the new dynamic guard.** The existing
  AC1/AC4 regexes hardcode `v1\.1\.11` (test L53, L84). On the NEXT real release, an
  operator must bump BOTH the cloud-init pin AND these hardcoded test regexes — otherwise
  the static assertions go red even though the pin correctly matches the new latest tag.
  Consider (in /work) softening AC1/AC4 to match `v[0-9]+\.[0-9]+\.[0-9]+` (shape, not
  exact value) so the dynamic drift assertion becomes the single source of the exact-value
  check. Decide inline; if softened, keep the consistency sub-check so a partial bump still
  fails.
- **The guard reads git tags, not GHCR.** If a release ever tags git without publishing the
  image (or vice-versa), the guard tracks the git tag. This matches the build workflow's own
  trigger contract, so it is correct by construction, but note it.

## Out of Scope

- **Option 2 (auto-bump bot PR)** from the build workflow — deferred per the issue's
  re-eval criteria (pick drift-guard unless the release process is being reworked).
- **Redeploying running hosts** — remains the `deploy inngest …:vX.Y.Z` webhook path.
- **Querying GHCR for published image tags** — git tags are the chosen source-of-truth.
- **Changing the bootstrap image release/versioning scheme.**

## Implementation Notes (added at /work time, 2026-05-30)

**As-built location:** the real test is `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`
(the pipeline-args path `apps/inngest/infra/__tests__/...` does not exist). AC6 + AC6b were
appended to that existing bash test (now 21/21 assertions), and the test was wired into the
`deploy-script-tests` job of `.github/workflows/infra-validation.yml` (which runs an explicit
hardcoded list of `run:` steps — confirmed it was NOT auto-globbing the test) with
`fetch-depth: 0` + `fetch-tags: true` added so the `vinngest-v*` tags are reachable.

**Load-bearing correction to the deepen reconciliation table.** The table claimed all releases
`v1.0.0…v1.1.11` exist as `vinngest-v*` git tags. That was FALSE — the remote topped out at
`vinngest-v1.1.10`. `v1.1.11` was published via two `workflow_dispatch` runs on `main`
(2026-05-30 20:27/20:28 UTC) before the #4669 pin-bump commit, so it never got a tag. A guard
asserting `pin == semver-max tag` would have gone red on the correct deployed state. With operator
approval, the missing annotated tag `vinngest-v1.1.11` was backfilled at commit `338ac402` (whose
bootstrap shape inputs are byte-identical to the build-time tree, so the tag-triggered rebuild
reproduces the same image) and pushed — also closing the latent
`hr-tagged-build-workflow-needs-initial-tag-push` gap. Now pin == latest tag == v1.1.11 and the
guard is green, firing only on real drift.

**Hardcoded-version Sharp Edge resolved:** AC1/AC4's hardcoded `v1.1.11` regexes were softened to
shape-match `v[0-9]+\.[0-9]+\.[0-9]+`; AC6 now owns the single exact-value check (+ AC6b catches
partial bumps), so future releases need only a cloud-init pin bump, not a parallel test edit.
