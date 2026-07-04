---
title: "fix(ci): Version Bump and Release startup_failure — plugin caller missing id-token: write"
date: 2026-07-04
type: fix
issue: 6018
branch: feat-one-shot-6018-version-bump-release-startup-failure
lane: procedural
brand_survival_threshold: none
detail_level: minimal
---

# 🐛 fix(ci): Version Bump and Release workflow `startup_failure` on every merge

Closes #6018.

## Enhancement Summary

**Deepened on:** 2026-07-04

**Deepen-plan halt gates (all PASS):**
- 4.6 User-Brand Impact — section present, threshold `none` + sensitive-path scope-out reason present (`.github/workflows/*version-bump*|*release*.yml` matches the sensitive-path regex, so the reason bullet is mandatory and is supplied).
- 4.7 Observability — 5-field schema present; `discoverability_test.command` is `gh run list` (no SSH).
- 4.8 PAT-shaped variable — none.
- 4.9 UI-wireframe — no UI surface in Files to Edit/Create (only `.yml` + `.test.sh`); skip.
- 4.4 Precedent-diff — pattern-bound (job-level `permissions:`); precedent = #5981, side-by-side below (not novel).

**Key findings (root-cause replaces the issue's hypothesis):**
1. The regression is **not** a parse error / moved ref / org-secret change (issue's guesses).
   It is the caller (`version-bump-and-release.yml`) failing to grant `id-token: write`, a
   permission the reusable `release` job began requiring in #5977 for cosign signing.
2. #5981 already fixed the **sibling** caller (`web-platform-release.yml`) but missed this one.
   The fix is a verbatim application of that precedent — low-risk, established pattern.
3. **Self-verifying merge:** the new drift-guard test lands under `plugins/soleur/test/**`,
   which matches the caller's `plugins/soleur/**` path filter — so merging this PR itself
   re-triggers the workflow and confirms the fix (no forced `workflow_dispatch`, no operator step).
4. Live-verified citations: `gh pr view 5977` → `60f203c50`; `gh pr view 5981` → `08555a944`.

## Overview

The **Version Bump and Release** workflow (`.github/workflows/version-bump-and-release.yml`,
the plugin release tagger) has concluded `startup_failure` (empty `jobs`, run never
starts) on every merge to `main` since **2026-07-04T12:20 UTC**. It succeeded through
2026-07-03T20:09 UTC.

**Root cause (verified, not the issue's hypothesis).** PR #5977 (commit `60f203c50`,
merged 2026-07-04 **11:25 UTC**) added cosign keyless image signing to the shared
`reusable-release.yml`. That change added `id-token: write` to the reusable workflow's
single `release` job permissions block (`reusable-release.yml:66`) so cosign can mint an
OIDC token for Fulcio. **A reusable workflow can only *use* a `GITHUB_TOKEN` permission
that its caller grants** — if the called job declares a permission the caller omits, the
run fails at dispatch with `startup_failure` and zero jobs (GitHub validates the
permission ceiling before evaluating any step `if:`, so this fires even though the plugin
release passes no `docker_image` and never actually runs the cosign steps).

PR #5981 (commit `08555a944`, merged 2026-07-04 **11:38 UTC**) recognised this and added
a **job-level** `permissions` block granting `id-token: write` to the **web-platform**
caller (`web-platform-release.yml`) — but **missed the plugin caller**
(`version-bump-and-release.yml`), whose only permissions are the workflow-level
`contents: write` + `packages: write`. The first plugin-path merge after #5977 landed
(the 12:20 UTC run) hit the ungranted permission and has failed identically ever since.

**Fix.** Add a job-level `permissions` block to the `release` job in
`version-bump-and-release.yml` granting `contents: write`, `packages: write`, and
`id-token: write`, mirroring the exact remediation #5981 applied to the sibling caller.
Add a drift-guard shell test asserting **every** `uses: ./.github/workflows/reusable-release.yml`
caller grants `id-token: write`, so the next caller (or a future permission the reusable
job adds) cannot silently re-introduce the same `startup_failure` class.

This is the identical defect class as learning
`knowledge-base/project/learnings/2026-05-04-schedule-once-template-missing-id-token.md`
("OIDC permission belongs to the action/reusable-job, not the caller task") — which also
prescribes pairing the fix with a regression assertion.

**Impact / severity.** Release tags are not created on merge, so the plugin version does
not advance and the release Slack notification does not fire. The issue explicitly records
**no production/customer impact** — this is the plugin release tagger, not the
web-platform deploy. Brand-survival threshold: **none**.

## User-Brand Impact

**If this lands broken, the user experiences:** the plugin release tag / version bump
continues to not advance on merge, and the release Slack post stays silent — an
operator-facing release-automation gap, not a customer-facing surface.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — the change
grants an OIDC token-mint scope to a release job that already runs in the trusted
`main`-push context; no data path, no secret, no external exposure is added. `id-token: write`
only enables the cosign OIDC handshake, which for the plugin caller does not even execute
(no `docker_image` input).

**Brand-survival threshold:** none — CI release-tagging reliability; the issue records no
production/customer impact. `threshold: none, reason: plugin release-tagger CI permission fix; issue #6018 explicitly records no production/customer impact and the change adds no data/secret path.`

## Research Reconciliation — Issue Hypothesis vs. Codebase Reality

| Issue claim | Reality (verified) | Plan response |
| --- | --- | --- |
| "reusable workflow has a **parse error**, or a pinned action/ref **moved**, or an **org-level permissions/secret** change landed ~12:20 UTC" | None of these. `reusable-release.yml` YAML is valid; the regression is a **new `id-token: write` job permission** added by #5977 (`60f203c50`, 11:25 UTC) that the caller does not grant. | Fix targets the **caller's** permission grant, not the reusable workflow. |
| Caller "delegates to `reusable-release.yml` (#823)" and caller file "unchanged (last edit #942)" | Correct — caller unchanged is *why* it broke: the reusable job's permission ceiling rose under it. | Confirms the fix belongs in the caller. |
| Failure began 2026-07-04T12:20 UTC | Consistent: #5977 (11:25) + #5981 (11:38) landed just before; 12:20 was the first plugin-path merge after. #5981 fixed the web-platform caller only. | — |
| (implicit) fix is web-platform-side | The web-platform caller is **already fixed** (#5981). Only the plugin caller remains. | Single-caller edit + drift-guard for all callers. |

## Affected callers of `reusable-release.yml` (enumerated via grep)

- `.github/workflows/web-platform-release.yml` — **already fixed** by #5981 (job-level `id-token: write`).
- `.github/workflows/version-bump-and-release.yml` — **BROKEN, this plan's target.**
- `.github/workflows/apply-deploy-pipeline-fix.yml` — **not a caller.** The string
  `reusable-release.yml` appears only in a code comment (line 586); there is no
  `uses: ./.github/workflows/reusable-release.yml`. Not affected.

## Files to Edit

- `.github/workflows/version-bump-and-release.yml` — add a job-level `permissions:` block
  to the `release:` job (the only job) mirroring `web-platform-release.yml` (#5981):

  ```yaml
  jobs:
    release:
      uses: ./.github/workflows/reusable-release.yml
      # A reusable workflow can only USE permissions its CALLER grants. cosign
      # keyless signing in reusable-release.yml needs id-token: write (#5977/#5933
      # Item 4). A job-level block REPLACES the inherited workflow perms, so
      # contents/packages are re-declared here. Absent id-token the reusable
      # workflow fails at dispatch with startup_failure (this fixes #6018; sibling
      # fix for web-platform-release.yml was #5981).
      permissions:
        contents: write
        packages: write
        id-token: write
      with:
        component: plugin
        component_display: "Soleur"
        # ... (existing inputs unchanged)
      secrets: inherit
  ```

  (Job-level chosen to mirror #5981 verbatim and stay least-privilege-safe if a second
  job is ever added; since `release` is currently the only job, a workflow-level
  `id-token: write` would be functionally equivalent. `permissions:` is a sibling key of
  `uses:`/`with:`/`secrets:` under `release:` — YAML key order is immaterial; keep the
  existing `with:` inputs verbatim.)

### Precedent Diff (deepen-plan Phase 4.4)

The fix is a verbatim application of the **already-merged sibling** remediation #5981. Side
by side — the target must reach the same shape the web-platform caller already has:

| | `web-platform-release.yml` (post-#5981, live) | `version-bump-and-release.yml` (this plan) |
| --- | --- | --- |
| `release` job `permissions:` | `contents/packages/id-token: write` (job-level, lines 42–52) | **add** `contents/packages/id-token: write` (job-level) |
| workflow-level `permissions:` | `contents/packages: write` (superseded for `release` by job block) | `contents/packages: write` (same; superseded once job block added) |

No novel pattern — this is precedent-conformant. Citations verified live this pass:
`gh pr view 5977` → mergeCommit `60f203c50` ("image signing … cosign"), `gh pr view 5981`
→ mergeCommit `08555a944` ("grant id-token: write to web-platform-release caller"). The
sibling's own comment block already names `startup_failure` and #5977 as the regression it
fixes — this plan closes the caller it missed.

## Files to Create

- `plugins/soleur/test/reusable-release-caller-permissions.test.sh` — drift-guard.
  Auto-discovered by the `scripts/test-all.sh` glob at `:188`
  (`for f in plugins/soleur/test/*.test.sh ...`) — no manual runner registration needed.
  Precedent: `plugins/soleur/test/reusable-release-idempotency.test.sh` (same file header
  convention, static-assertion-over-workflow-YAML pattern). The test MUST:
  1. Assert the reusable workflow (`reusable-release.yml`) declares `id-token: write` on
     its `release` job (guards against the guard going stale if signing is later removed —
     if the requirement disappears, the test's premise should be revisited, not silently pass).
  2. Enumerate every `uses: ./.github/workflows/reusable-release.yml` caller under
     `.github/workflows/` (grep, not a hardcoded list).
  3. For each caller, assert `id-token: write` is granted at **workflow level OR at the
     calling job's job level** (either satisfies the ceiling). FAIL naming the caller if absent.
  4. Include a positive sanity check that the enumeration found ≥ 2 callers (so a future
     grep-scope regression that finds zero callers fails loudly rather than passing vacuously).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.github/workflows/version-bump-and-release.yml`'s `release` job declares
      `id-token: write` (plus `contents: write`, `packages: write`).
      Verify: `grep -A6 '^  release:' .github/workflows/version-bump-and-release.yml | grep -c 'id-token: write'` returns `1`.
- [ ] `actionlint .github/workflows/version-bump-and-release.yml` exits 0 (YAML + job
      shape valid). Note: actionlint does **not** validate the cross-workflow permission
      ceiling (a GitHub-runtime check) — the drift-guard test covers that invariant.
- [ ] New drift-guard test exists and passes:
      `bash plugins/soleur/test/reusable-release-caller-permissions.test.sh` exits 0.
- [ ] Drift-guard proves it catches the bug: temporarily removing the `id-token: write`
      line from the plugin caller makes the test FAIL naming `version-bump-and-release.yml`
      (author-run sanity; revert before commit).
- [ ] `bash scripts/test-all.sh scripts` (or the local shard runner) discovers and runs
      the new test green.
- [ ] PR body uses `Closes #6018`.

### Post-merge (verification — self-triggering)

- [ ] This PR creates `plugins/soleur/test/reusable-release-caller-permissions.test.sh`,
      which matches the caller workflow's path filter `plugins/soleur/**`. **Merging this
      PR therefore itself triggers the Version Bump and Release workflow** — the natural,
      no-forced-dispatch verification. Confirm the triggered run **does NOT conclude
      `startup_failure`** and starts with a populated `jobs` object:
      `gh run list --workflow "Version Bump and Release" --branch main --limit 1 --json conclusion,status,databaseId`
      then `gh run view <id>` shows the `release` job present.
      Automation: `gh` CLI (via Bash) — no operator action.
- [ ] The run advances the plugin version / creates the release tag it had been failing to
      create (release backlog since 2026-07-04 clears). If the run reaches the reusable
      workflow but fails a *later* step (unrelated to permissions), that is out of scope
      for #6018 (the `startup_failure` is fixed) — file a follow-up.

## Observability

The failure mode this plan fixes was itself an observability gap: `startup_failure`
produces an empty `jobs` object and no step logs, so the release simply "didn't happen"
silently. The remediation's durable detection is the **drift-guard test** (a CI gate that
fails loudly at PR time if any caller of `reusable-release.yml` omits a permission the
reusable job requires), not a runtime probe.

- `liveness_signal`: the Version Bump and Release workflow run on each `plugins/soleur/**`
  merge — visible via `gh run list --workflow "Version Bump and Release" --branch main`;
  a `startup_failure` conclusion is the regression signal. Configured in
  `.github/workflows/version-bump-and-release.yml`.
- `error_reporting`: GitHub Actions run conclusion (`startup_failure` / `failure`) surfaced
  in the Actions UI and `gh run list`; the reusable workflow already posts a release Slack
  notification on success (`reusable-release.yml`, #5078/#5204), whose *absence* is the
  operator-visible signal.
- `failure_modes`:
  - {mode: caller omits a permission the reusable job requires, detection:
    `plugins/soleur/test/reusable-release-caller-permissions.test.sh` (CI, pre-merge),
    alert_route: PR check failure blocks merge}
  - {mode: reusable-release run concludes `startup_failure` at dispatch, detection:
    `gh run list --workflow "Version Bump and Release" --branch main` conclusion field,
    alert_route: absent release Slack post + red Actions run}
- `logs`: GitHub Actions run logs (retained per repo Actions retention). `startup_failure`
  runs have no step logs by definition — hence the pre-merge test is the primary guard.
- `discoverability_test`:
  - command (NO ssh): `gh run list --workflow "Version Bump and Release" --branch main --limit 1 --json conclusion`
  - expected_output: `conclusion` is `success` (or at minimum not `startup_failure`) on the
    post-merge trigger.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

Not applicable. This change grants a `GITHUB_TOKEN` OIDC scope (`id-token: write`) to an
existing workflow job — it provisions no server, secret, vendor account, DNS record, or
persistent runtime process. No SSH, no Doppler secret writes, no Terraform. Phase 2.8 skip.

## Architecture Decision (ADR / C4)

No architectural decision. This restores parity with the **already-established** pattern
from #5981 ("callers of `reusable-release.yml` must grant `id-token: write`") — it neither
creates nor reverses an ADR. C4 completeness check: no external human actor, external
system/vendor, container/data-store, or actor↔surface access relationship changes (the
cosign OIDC edge — GitHub Actions → Fulcio/Rekor — was introduced by #5977 for the
web-platform image, and does not execute for the plugin caller which passes no
`docker_image`). "No C4 impact": the `model.c4`/`views.c4`/`spec.c4` scope is the running
system's actors/containers; a CI permission grant on the plugin release tagger adds no
modeled element. Phase 2.10 skip.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/infrastructure-tooling change (a GitHub Actions
permission grant + a drift-guard test). No UI surface (no `components/**`, `app/**/page.tsx`,
or `app/**/layout.tsx` in Files to Create/Edit). No Product/UX Gate.

## Test Scenarios

1. **Regression (the bug):** With `id-token: write` absent from the plugin caller, a
   `plugins/soleur/**` merge → `startup_failure`. After the fix → run starts with the
   `release` job populated. (Verified post-merge via the self-triggering path.)
2. **Drift-guard positive:** `reusable-release-caller-permissions.test.sh` passes with both
   real callers granting `id-token: write`.
3. **Drift-guard negative:** removing the grant from either caller makes the test FAIL
   naming that caller.
4. **Vacuous-pass guard:** if the caller-enumeration grep returns zero callers (e.g., a
   future path/filename change), the ≥2-caller sanity assertion FAILs rather than passing.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`, or omits
  the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled (threshold: none).
- `actionlint` validates YAML/job shape only — it does **not** enforce the caller→reusable
  permission ceiling. Do not treat a green `actionlint` as proof the `startup_failure` is
  fixed; the drift-guard test + the post-merge self-triggering run are the real proofs.
- The reusable job declares `id-token: write` **unconditionally at the job level**, while the
  cosign steps that use it are `if:`-gated on `docker_image != ''`. The plugin caller passes
  no `docker_image`, so it never signs anything — but it STILL must grant the permission,
  because GitHub validates the permission ceiling at dispatch, before any `if:` runs. Do not
  "optimise" by trying to make the grant conditional; it cannot be.
- Job-level `permissions:` **replaces** (does not merge with) the inherited workflow-level
  block for that job — so `contents: write` and `packages: write` must be re-declared
  alongside `id-token: write`, or the release job loses tag-push/GHCR access. (This is the
  exact note from #5981.)
