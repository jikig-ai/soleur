---
title: "fix: stuck-draft-release deadlock freezing web-v version computation"
date: 2026-06-03
type: fix
issue: 4902
branch: feat-one-shot-4902-web-v-version-frozen-stuck-draft
lane: cross-domain
brand_survival_threshold: none
status: planned
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# fix: stuck-draft-release deadlock freezing web-v version computation

Closes #4902 (pre-merge code change). The orphaned-draft backlog resolution is a
post-merge `gh`-automated step, so the PR body uses `Ref #4902` and the issue is
closed after the backlog is drained (see Acceptance Criteria split).

## Overview

`reusable-release.yml` computes each component's next version from the highest
`<prefix>v*` git tag. GitHub only materializes a tag ref when a release is
published -- a `--draft` release creates no tag. The workflow deliberately
creates releases as `--draft` (load-bearing per the immutable-release upload
flow -- the prior closed PR cited inline in the `Create GitHub Release` step
comment established that published releases are immutable and reject
`gh release upload` with HTTP 422, so the draft->upload-asset->publish sequence is
required), then flips `--draft=false` in the Finalise step after Docker push.

The deadlock: if any step between create and finalise fails (or the publish
itself fails), the job stops and the release stays an orphaned draft with no
git tag. The idempotency step (`if gh release view "$TAG" &>/dev/null` ->
`exists=true` -> skip) then finds that orphaned draft on every subsequent run
and skips `create_release` forever. `released` never becomes `'true'` again, so
Finalise never runs again either -- a permanent lock. The git-tag baseline
freezes; `BUILD_VERSION` is recomputed off the frozen baseline each build and
baked into the image, but no new tag is ever persisted, so `/health.version` is
frozen and non-monotonic (flips between `0.101.100` and `0.102.0` depending on
the merged PR's semver label, both hitting orphaned drafts).

Verified live state (2026-06-03):

| Artifact | State | Evidence |
|---|---|---|
| Last published web tag | `web-v0.101.99` (git tag present) | `gh release view web-v0.101.99 --json isDraft` -> `{"isDraft":false}`; `git log web-v0.101.99` -> 2026-05-27 13:23 UTC |
| Orphaned draft 1 | `web-v0.101.100` draft, no git tag | `gh release view web-v0.101.100 --json isDraft` -> `{"isDraft":true}`; created 2026-05-27 20:30 UTC; `target_commitish: main` |
| Orphaned draft 2 | `web-v0.102.0` draft, no git tag | created 2026-05-20 13:19 UTC (predates `web-v0.101.99`) -- stale/wrong artifact |
| `gh release view --json` fields | `isDraft`, `isImmutable` both exist | `gh release view --help` JSON FIELDS list |

The fix has two parts:

- A. Prevent recurrence (`reusable-release.yml`, pre-merge): the idempotency
  check treats a draft as "not done" (`exists=true` only when the existing
  release is published), and the Finalise step (re-)publishes an existing
  orphaned draft so a transient failure self-heals on the next release. Preserve
  the immutable-release draft->upload->publish flow.
- B. Drain the backlog (post-merge, `gh`-automated): publish `web-v0.101.100`
  (materializes the git tag matching the currently-deployed `BUILD_VERSION`,
  resuming monotonic patch bumps) and delete the stale `web-v0.102.0` draft.

Blast radius: `reusable-release.yml` gates every release -- plugin `v`,
`web-v`, `telegram-v` (callers: `version-bump-and-release.yml`,
`web-platform-release.yml`). A regression here breaks all three release lanes.
The idempotency change is covered by a workflow unit test.

## Premise Validation

Checked against live repo + GitHub state on 2026-06-03 (the cheap-probe gate
before research): (1) Issue #4902 is OPEN, not closed by any merged PR -- premise
holds. (2) `reusable-release.yml` exists on this branch and matches the RCA's
quoted snippets line-for-line (idempotency step L241-253, Create-draft L275-295,
Finalise L577-584). (3) Both orphaned drafts confirmed present via
`gh api .../releases --jq 'select(.draft==true)'` -- `web-v0.101.100` (2026-05-27)
and `web-v0.102.0` (2026-05-20); git tags absent (`git tag --list web-v*` tops out
at `web-v0.101.99`). (4) The RCA-prescribed `gh release view "$TAG" --json isDraft`
field shape verified live: returns `{"isDraft":false}` for the published
`web-v0.101.99` and `{"isDraft":true}` for the orphaned `web-v0.101.100`. (5) The
`--draft` rationale comment in the workflow cites a prior closed PR by description
(immutable-release HTTP 422 on asset upload) -- that PR is a contextual citation
in the comment, not a work target; the plan preserves the citation verbatim and
does not chase or re-verify it. No stale premise found.

## Research Reconciliation -- Spec vs. Codebase

| RCA claim | Codebase reality | Plan response |
|---|---|---|
| Idempotency uses `gh release view "$TAG" &>/dev/null` -> exists=true (treats draft as done) | Confirmed at `reusable-release.yml:248` | Replace with `--json isDraft` published-only check |
| Finalise gated `if: steps.create_release.outputs.released == 'true'` | Confirmed at L578 | Widen gate so finalise reaches an orphaned-draft re-publish path even when create_release was skipped |
| `--draft` is load-bearing (immutable-release 422) | Confirmed; rationale comment L282-288 + L566-576 | Preserve the draft->upload->publish flow unchanged; only the gating/idempotency logic changes |
| Two orphaned drafts hold the lock | Confirmed live (both `draft==true`, no git tag) | Post-merge `gh`-automated drain |
| `web-v0.101.100` matches deployed BUILD_VERSION | `BUILD_VERSION` recomputes to `0.101.100` off the frozen `web-v0.101.99` baseline on patch PRs (per RCA run 26908931474 log) | Publish `web-v0.101.100` to materialize the tag |
| `web-v0.102.0` predates `web-v0.101.99` | Created 2026-05-20 < published 2026-05-27 | Delete the stale draft |
| `web-v0.101.100` draft `target_commitish` | `main` (symbolic, NOT a pinned SHA) | Sharp edge: publishing tags at current `main` HEAD, not the original 2026-05-27 build commit -- acceptable (the tag is a version baseline, `build_sha` already identifies the deployed tree) |

## User-Brand Impact

If this lands broken, the user experiences: `/health.version` and the Sentry
`release` tag continue to report a frozen, non-monotonic version -- incident triage
and release correlation stay degraded. A regression in the shared
`reusable-release.yml` (the high-blast-radius surface) would additionally break
plugin `v` and `telegram-v` releases, stalling all version computation.

If this leaks, the user's data / workflow / money is exposed via: N/A -- this
change touches only the release-versioning workflow and GitHub Release draft
state. No data, auth, payment, or PII surface. `build_sha` is always correct, so
the deployed code is identifiable throughout; only the human-readable `version`
string is wrong.

Brand-survival threshold: none -- internal release-ops correctness. The diff
touches no sensitive path (no schema, auth, API route, or `.sql`); threshold:
none, reason: the change is confined to a CI release workflow and a workflow unit
test, with no user-data or money surface.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 -- Idempotency treats draft as not-done. The `Check idempotency` step
  in `reusable-release.yml` sets `exists=true` only when the existing release
  is published. Verification: the step shells `gh release view "$TAG" --json isDraft`
  and gates on the parsed value being `false`; a non-existent release OR an
  existing draft both yield `exists=false`. Grep:
  `grep -n 'isDraft' .github/workflows/reusable-release.yml` returns >=1 line inside
  the idempotency step.
- [ ] AC2 -- Orphaned-draft re-publish self-heal. When the idempotency step
  finds an existing draft (not published), a downstream path re-publishes it so
  a transient prior-run failure self-heals. Verification: the Finalise step (or an
  equivalent publish step) runs when EITHER `create_release.released == 'true'` OR
  the idempotency step recorded `draft_exists == 'true'`. Grep the Finalise `if:`
  for the disjunction.
- [ ] AC3 -- Immutable-release flow preserved. The `Create GitHub Release` step
  still passes `--draft`; the `--draft`-rationale comment block (citing the prior
  closed PR for the immutable-upload 422) is unchanged. Verification:
  `grep -c -- '--draft' .github/workflows/reusable-release.yml` is unchanged on the
  create step; the comment lines L282-288 are byte-identical pre/post (diff shows no
  deletion in that block).
- [ ] AC4 -- `released` output stays truthful. The job's `released` output is
  `true` exactly when a new tag will be persisted this run -- i.e. when a new draft
  was created OR an existing orphaned draft is (re-)published this run. A run that
  finds an already-published release still outputs `released=false` (no new tag).
  Verification: trace the `steps.create_release.outputs.released` / new output wiring
  in the test across the three scenarios.
- [ ] AC5 -- Workflow unit test passes. A new
  `plugins/soleur/test/reusable-release-idempotency.test.sh` is auto-discovered by
  the `scripts` shard glob (`plugins/soleur/test/*.test.sh` in
  `scripts/test-all.sh:176`) and passes via
  `bash plugins/soleur/test/reusable-release-idempotency.test.sh` (exit 0). It
  exercises the extracted idempotency+finalise gating logic against a mocked `gh`
  with three scenarios (no release / published release / orphaned draft) -- see Test
  Scenarios. The test removes the LLM and the live GitHub API from the assertion
  path (deterministic `gh` stub).
- [ ] AC6 -- No regression to plugin/telegram lanes. The idempotency/finalise
  logic is prefix-agnostic (operates on `$TAG` only). The test runs all three
  scenarios against a representative tag for each lane to prove no
  `web-v`-specific assumption leaked in.
- [ ] AC7 -- actionlint clean. `reusable-release.yml` passes `actionlint`
  (workflow schema), and every edited embedded `run:` snippet passes
  `bash -c '<extracted snippet>'` syntax check (never `bash -n` on the `.yml`).

### Post-merge (`gh`-automated -- Automation: feasible via gh CLI, no portal/SSH step)

- [ ] AC8 -- Publish `web-v0.101.100`. `gh release edit web-v0.101.100
  --draft=false` succeeds; afterward `gh release view web-v0.101.100 --json isDraft`
  -> `{"isDraft":false}` AND `git ls-remote --tags origin web-v0.101.100` returns a
  ref (the tag is materialized). This restores the git-tag baseline and resumes
  monotonic patch bumps.
- [ ] AC9 -- Delete stale `web-v0.102.0`. `gh release delete web-v0.102.0 --yes`
  succeeds; afterward `gh release view web-v0.102.0` returns non-zero (gone) AND
  `git ls-remote --tags origin web-v0.102.0` is empty (no orphaned tag left behind).
- [ ] AC10 -- Baseline resumes. After AC8/AC9, the next `web-platform-release.yml`
  run (or a `workflow_dispatch` patch bump) computes `0.101.101` (one above the
  newly-published `0.101.100`) and persists the `web-v0.101.101` git tag --
  confirmed by `git ls-remote --tags origin 'web-v*'` advancing past `0.101.100`.
- [ ] AC11 -- Issue closed after drain. `gh issue close 4902` runs after AC8-AC10
  verify (the PR body used `Ref #4902`, not `Closes`, so merge does not auto-close
  before the backlog drain runs).

## Implementation Phases

### Phase 0 -- Preconditions (no code)

- [ ] Confirm `actionlint` is available locally (`command -v actionlint`); if absent,
  note the CI `actionlint` job covers the workflow-schema gate and run the embedded
  `bash -c` snippet check locally regardless.
- [ ] Re-read the three load-bearing regions of `reusable-release.yml` before
  editing: `Check idempotency` (L241-253), `Create GitHub Release (as draft)`
  (L275-295, incl. the `--draft` rationale comment), `Finalise release (publish
  draft)` (L566-584). Confirm the `released` output wiring at L69.
- [ ] Re-confirm live backlog state (`gh api .../releases --jq 'select(.draft==true)'`)
  is unchanged since 2026-06-03 -- if either draft was resolved out-of-band, re-scope
  Phase 3 accordingly (per the drift-runbook learning: live state can change between
  plan and execution).

### Phase 1 -- RED: write the failing workflow unit test

`plugins/soleur/test/reusable-release-idempotency.test.sh` (new). The test extracts
the idempotency + finalise gating decision as a small pure-shell function (or
sources the snippet via a `bash -c` harness with a mocked `gh` on `PATH`), then
asserts the three scenarios. Structure mirrors `concurrent-ship.test.sh` (PASS/FAIL
counters, `set -uo pipefail`, `mktemp -d` + `trap` cleanup, exit 1 on any FAIL).

Mock `gh` strategy (deterministic, no live API): prepend a temp dir to `PATH`
containing a `gh` stub script whose behavior is driven by an env var
(`MOCK_GH_STATE=absent|published|draft`):
- `gh release view "$TAG"` (bare): exit 0 if state in {published, draft}, else exit 1.
- `gh release view "$TAG" --json isDraft ...`: print `{"isDraft":false}` for
  published, `{"isDraft":true}` for draft, exit 1 for absent.
- `gh release edit "$TAG" --draft=false`: record the call to a trace file, exit 0.
- `gh release create ...`: record the call, exit 0.

The test asserts the decision outputs (`exists`, the new `draft_exists` flag,
`released`, and whether a publish/finalise call fired) -- not the LLM, not live gh.

Because the gating logic currently lives inline in YAML, Phase 1 must extract it
so it is unit-testable. Two acceptable extraction shapes (decide in Phase 2; prefer
the one with the smaller workflow diff):

1. Inline-faithful harness: the test greps the exact `run:` blocks out of
   `reusable-release.yml` (via an `awk`/`yq` extraction the test owns) and executes
   them under the mocked `gh`. Keeps the workflow as the single source of truth; the
   test exercises the real shell. (Preferred -- no production code path moves; matches
   the "remove the LLM/API from the assertion path" discipline.)
2. Extracted helper: move the gating shell into
   `.github/workflows/lib/release-idempotency.sh` (or similar) sourced by the
   workflow, and unit-test the helper directly. Heavier diff; only adopt if the
   inline-faithful harness proves brittle.

Run the test; confirm it FAILS against the current (unfixed) workflow -- specifically
the `draft` scenario must show `exists=true` (the bug) and no re-publish call.

### Phase 2 -- GREEN: fix `reusable-release.yml`

Edit three steps; preserve the `--draft` create flow and its rationale comment.

1. `Check idempotency` (L241-253) -- replace the bare `gh release view` check:
   ```bash
   # exists=true ONLY when the release is already PUBLISHED. A non-existent
   # release OR an orphaned DRAFT (no git tag yet) both yield exists=false so
   # the pipeline proceeds -- the draft case is re-published by Finalise below,
   # self-healing a transient prior-run failure instead of locking forever.
   # Refs #4902 (stuck-draft deadlock).
   if gh release view "$TAG" --json isDraft >"$REL_JSON" 2>/dev/null; then
     IS_DRAFT=$(jq -r '.isDraft' "$REL_JSON")
     if [ "$IS_DRAFT" = "false" ]; then
       printf 'exists=%s\n' "true" >> "$GITHUB_OUTPUT"
       printf 'draft_exists=%s\n' "false" >> "$GITHUB_OUTPUT"
       echo "Release $TAG already published, skipping"
     else
       printf 'exists=%s\n' "false" >> "$GITHUB_OUTPUT"
       printf 'draft_exists=%s\n' "true" >> "$GITHUB_OUTPUT"
       echo "Release $TAG exists as an ORPHANED DRAFT -- will re-publish (self-heal)"
     fi
   else
     printf 'exists=%s\n' "false" >> "$GITHUB_OUTPUT"
     printf 'draft_exists=%s\n' "false" >> "$GITHUB_OUTPUT"
   fi
   ```
   (Use a `steps.tmpfiles`-managed secure temp file for `$REL_JSON` rather than a
   hardcoded path -- the workflow already mints temp files in the `Create secure temp
   files` step; add a `rel_json` output there. Final form decided at /work time.)

2. `Create GitHub Release (as draft)` (L275-295) -- gating decision: the orphaned-draft
   case must not error on "release already exists." Preferred: gate create on
   `idempotency.outputs.exists == 'false' && idempotency.outputs.draft_exists ==
   'false'` (skip create when the draft already exists; only finalise is needed), and
   set `released=true` in BOTH the create step AND a small new "mark re-publish" step
   that fires when `draft_exists == 'true'`. The `released` output (L69) then becomes
   `true` whenever a tag will be persisted this run (new draft created OR orphaned
   draft re-published), keeping AC4 truthful. Alternative considered: keep create
   gated on `exists == 'false'` and let `gh release create` no-op/`--clobber` on an
   existing draft -- rejected because `gh release create` on an existing tag errors,
   it does not no-op.

3. `Finalise release (publish draft)` (L566-584) -- widen the gate so it reaches
   the orphaned-draft re-publish:
   ```yaml
   if: >-
     steps.check_changed.outputs.changed == 'true' &&
     (steps.create_release.outputs.released == 'true' ||
      steps.idempotency.outputs.draft_exists == 'true')
   ```
   The `gh release edit "$TAG" --draft=false` body is unchanged (idempotent -- editing
   an already-published release to `--draft=false` is a no-op; editing a draft
   publishes it and materializes the tag).
   Caveat to resolve at /work: the Docker build / audit steps between create and
   finalise are gated on `steps.version.outputs.next != ''` and
   `steps.create_release.outputs.released == 'true'` respectively. For the
   orphaned-draft re-publish path (where `create_release` did NOT run this run), the
   audit-upload step (gated `create_release.released == 'true'`) will skip -- which is
   correct (the draft already has whatever assets the original run uploaded, or none;
   the immutable-422 risk does not apply because we are only flipping draft->published,
   not uploading). Confirm the Docker build still runs for this path so the image is
   freshly pushed (it is gated on `version.outputs.next != ''`, independent of
   `released`). Trace all five `if:` gates between create and finalise in Phase 2 and
   record the per-path firing matrix in the PR body.

4. Update the job `outputs.released` expression at L69 if a new "mark re-publish"
   step contributes to it (e.g.
   `released: ${{ steps.create_release.outputs.released || steps.republish.outputs.released || 'false' }}`).

Re-run the Phase-1 test; confirm all three scenarios PASS.

### Phase 3 -- Post-merge backlog drain (`gh`-automated)

Bake into the ship post-merge sequence (NOT a human checklist -- every step is a
single `gh` call). After the PR merges to main:

```bash
# Resolve the two orphaned drafts that held the lock (#4902 Part B).
# Both are gh-automated -- no portal/dashboard/SSH step.

# 1. Publish web-v0.101.100 (matches deployed BUILD_VERSION) -> materializes tag,
#    resumes monotonic patch bumps. target_commitish is `main`, so the tag lands
#    at current main HEAD (see Sharp Edges).
gh release edit web-v0.101.100 --draft=false
gh release view web-v0.101.100 --json isDraft --jq '.isDraft'   # expect: false
git ls-remote --tags origin web-v0.101.100                       # expect: ref present

# 2. Delete the stale web-v0.102.0 draft (predates web-v0.101.99 -- wrong artifact).
gh release delete web-v0.102.0 --yes
gh release view web-v0.102.0 2>&1 || echo "deleted (expected non-zero)"
git ls-remote --tags origin web-v0.102.0                         # expect: empty

# 3. Close the issue (PR used Ref #4902, not Closes).
gh issue close 4902 --comment "Stuck-draft deadlock fixed; orphaned drafts drained: web-v0.101.100 published (tag materialized), web-v0.102.0 deleted. Monotonic web-v bumps resume from 0.101.100."
```

Place this in the `/soleur:ship` post-merge verification block (ship/SKILL.md already
runs `gh`-automated post-merge steps), OR run inline during the one-shot post-merge
phase. Do NOT defer to a human-run list (`hr-all-infrastructure-provisioning`,
`wg-block-pr-ready-on-undeferred-operator-steps`, and the automation-feasibility gate
all forbid punting an automatable `gh` step).

### Phase 4 -- Verify baseline resumes

After Phase 3, trigger one `web-platform-release.yml` run (next merge to main
touching `apps/web-platform/**`, or a `workflow_dispatch` patch bump) and confirm the
computed version is `0.101.101` and the `web-v0.101.101` git tag is persisted
(`git ls-remote --tags origin 'web-v*'` advances past `0.101.100`). This closes
AC10. If a natural merge does not land promptly, fire
`gh workflow run web-platform-release.yml -f bump_type=patch` (the workflow exists on
the default branch post-merge, so `workflow_dispatch` is valid).

## Files to Edit

- `.github/workflows/reusable-release.yml` -- idempotency step (`--json isDraft`
  published-only check + `draft_exists` output), create-release gate, Finalise gate
  widening, job `released` output wiring, `Create secure temp files` step (add a
  `rel_json` temp output). Preserve the `--draft` create flow and its rationale
  comment verbatim.

## Files to Create

- `plugins/soleur/test/reusable-release-idempotency.test.sh` -- workflow unit test
  (auto-discovered by `scripts/test-all.sh:176` glob; no registration needed).
  Mocks `gh`; asserts the three-scenario gating matrix. Mirrors
  `concurrent-ship.test.sh` structure.

## Test Scenarios

The unit test asserts this decision matrix (mocked `gh`, deterministic):

| Scenario (`MOCK_GH_STATE`) | `exists` | `draft_exists` | create fires? | finalise/publish fires? | `released` |
|---|---|---|---|---|---|
| `absent` (no release) | `false` | `false` | yes | yes (publishes the just-created draft after Docker) | `true` |
| `published` (tag exists) | `true` | `false` | no | no | `false` |
| `draft` (orphaned, no tag) | `false` | `true` | no (skipped -- draft exists) | yes (re-publishes -> self-heal) | `true` |

Lane-agnostic check (AC6): run the `draft` scenario against `v0.5.0`,
`web-v0.101.100`, and `telegram-v0.3.0` tags and confirm identical decision output
(no prefix-specific branch).

The pre-fix run (Phase 1 RED) must show the `draft` row as `exists=true` / no publish
(the bug); the post-fix run (Phase 2 GREEN) must show the corrected row.

## Risks and Mitigations

- R1 -- Regressing the immutable-release flow. The `--draft` create + Finalise
  publish sequence is load-bearing (422 on upload-to-immutable). Mitigation: the
  create step's `--draft` and its rationale comment are unchanged (AC3); only the
  idempotency gating and Finalise reachability change. The re-publish path only flips
  draft->published (the exact operation Finalise already performs), never uploads to a
  published release.
- R2 -- `released` output drift breaking downstream `web-platform-release.yml`
  jobs. The `deploy`/`migrate` jobs gate on `needs.release.outputs.version != ''`
  and `docker_pushed == 'true'`, NOT on `released`. Mitigation: the test asserts
  `released` is truthful across all three scenarios (AC4); confirm at /work that no
  caller gates a deploy on `released` (grep the two caller workflows -- already
  inspected: `web-platform-release.yml` gates on `version`/`docker_pushed`, not
  `released`).
- R3 -- Orphaned-draft re-publish path skips the audit-asset upload. For the
  re-publish path `create_release` didn't run, so the audit-upload step (gated on
  `create_release.released == 'true'`) skips. Mitigation: this is correct -- the
  draft already carries whatever it carried; the immutable-422 only applies to
  uploading to a published release, and we are not uploading on this path. Document
  the per-path firing matrix in the PR body (Phase 2 step 3).
- R4 -- Publishing `web-v0.101.100` tags current `main`, not the 2026-05-27 build
  commit. `target_commitish: main` is symbolic. Mitigation: acceptable -- the tag
  is a version baseline for monotonic bumps, not the source-of-truth for that
  historical build (`build_sha` already identifies the deployed tree). If a
  point-in-time tag is required, `gh release edit web-v0.101.100 --target <sha>` can
  pin it; default is to accept current `main`. Documented in Sharp Edges.
- R5 -- Live backlog drifts between plan and post-merge drain. Per the
  drift-runbook learning, re-confirm `draft==true` state immediately before Phase 3
  (Phase 0 precondition + Phase 3 inline checks already do this); if a draft was
  resolved out-of-band, skip that sub-step rather than erroring.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold:
  none with a one-sentence reason.)
- Do not test the workflow via `bash -n reusable-release.yml` -- that parses the
  YAML header as bash. Use `actionlint` for the YAML and `bash -c '<extracted run
  snippet>'` for embedded shell (per the composite-action/workflow learning).
- Test runner: the new test is a `.test.sh` under `plugins/soleur/test/` --
  auto-discovered by the `scripts` shard glob in `scripts/test-all.sh:176`. Do NOT
  prescribe `bun test` for it (it is shell, not TS) and do NOT add a manual
  `run_suite` line (the glob handles it). Run locally via
  `bash plugins/soleur/test/reusable-release-idempotency.test.sh`.
- `gh release edit --draft=false` on a draft materializes the git tag; on an
  already-published release it is a no-op. This idempotence is what makes the
  re-publish self-heal safe to run unconditionally on the widened Finalise gate.
- Publishing `web-v0.101.100` lands the tag at current `main` HEAD
  (`target_commitish: main`), not the original 2026-05-27 build commit. This is
  intentional for restoring monotonic bumps; `build_sha` remains the source of truth
  for what code is deployed.
- The `web-v0.102.0` draft (2026-05-20) predates the published `web-v0.101.99`
  (2026-05-27) -- it is a stale/wrong artifact from an earlier minor-labeled attempt.
  Deleting it (not publishing) is correct; publishing it would create a
  non-monotonic `0.102.0` tag below the resumed `0.101.100` baseline in creation
  time while above it in semver, re-introducing the exact flip the issue describes.

## Domain Review

Domains relevant: none

No cross-domain implications detected -- CI release-workflow correctness change. No
user-facing UI surface (no file under `components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`), no product/legal/marketing/finance/sales/support implications.
The Product/UX Gate does not fire (no UI-surface file in Files to Edit / Create).

## Infrastructure (IaC)

Not applicable -- this plan introduces no new server, service, cron, secret, vendor,
DNS record, or persistent runtime process. It edits an existing GitHub Actions
workflow (already-provisioned CI surface) and adds a shell test. No Terraform change.
Phase 2.8 IaC routing gate reviewed: the only post-merge steps are single `gh` CLI
calls (publish/delete a GitHub Release, close an issue), which are `gh`-automatable
and are NOT infrastructure provisioning -- hence the `iac-routing-ack` opt-out at the
top of this file.

## Observability

```yaml
liveness_signal:
  what: "web-v git tag advances monotonically; /health.version increments per web-platform release"
  cadence: "every merge to main touching apps/web-platform/**"
  alert_target: "web-platform-release.yml release job (fails loud if version computation errors)"
  configured_in: ".github/workflows/reusable-release.yml (Compute next version step) + web-platform-release.yml (Verify deploy health and version step, asserts /health.version == computed version)"
error_reporting:
  destination: "GitHub Actions run annotations (::error::) on the release job; workflow run failure visible in Actions tab and via gh run list"
  fail_loud: "true -- a version-computation or publish error fails the release job non-zero; the deploy job gates on release.outputs.version != '' so a broken release blocks deploy rather than shipping a stale version silently"
failure_modes:
  - mode: "orphaned draft re-introduced (transient failure between create and finalise)"
    detection: "next release run logs 'exists as an ORPHANED DRAFT -- will re-publish (self-heal)' and re-publishes; if re-publish itself fails, the release job fails non-zero"
    alert_route: "GitHub Actions run failure + ::error:: annotation"
  - mode: "version computation reads a draft-only baseline"
    detection: "Compute next version reads only git tags (published); the workflow unit test asserts draft state never advances the baseline"
    alert_route: "CI test failure (plugins/soleur/test/reusable-release-idempotency.test.sh) pre-merge"
  - mode: "/health.version frozen / non-monotonic post-deploy"
    detection: "web-platform-release.yml deploy job 'Verify deploy health and version' step asserts /health.version == computed version; mismatch fails the deploy"
    alert_route: "deploy job failure (already wired)"
logs:
  where: "GitHub Actions run logs for reusable-release.yml (idempotency decision, create/republish/finalise step output)"
  retention: "GitHub default (90 days for Actions logs)"
discoverability_test:
  command: "git ls-remote --tags origin 'web-v*' | sort -t/ -k3 -V | tail -3"
  expected_output: "the three highest published web-v tags, advancing monotonically past web-v0.101.100 after the fix + drain (no remote-shell access required)"
```

## Open Code-Review Overlap

None -- checked open `code-review` issues against the two touched/created paths
(`.github/workflows/reusable-release.yml`,
`plugins/soleur/test/reusable-release-idempotency.test.sh`) at plan time; no open
scope-out references either path. (Re-confirm with the two-stage `gh issue list
--label code-review --json` + standalone `jq --arg` form at /work if the backlog
shifted.)

## Enhancement Summary

Deepened on: 2026-06-03

Sections enhanced: Test sketch grounded in repo precedent; Precedent-Diff added;
verify-the-negative pass run on the load-bearing "never uploads to a published
release" claim.

Key improvements:
1. The `gh`-stub test strategy is grounded in an existing repo precedent
   (`plugins/soleur/test/audit-flag-flip.test.sh` stubs `curl` on `PATH` via a
   `chmod +x` stub + `PATH="$STUB_DIR:$PATH"`) — the new test follows the same
   shape, so it is not a novel pattern.
2. verify-the-negative confirmed: the Finalise step body is exactly
   `gh release edit "$TAG" --draft=false` (no `gh release upload`), so the plan's
   claim that the re-publish path never uploads to a published release is
   verified against the actual workflow shape, not assumed.
3. Live-state verification of every cited GitHub artifact (releases, tags,
   `--json isDraft` field shape) folded into Premise Validation + Overview.

New considerations discovered:
- The orphaned-draft `web-v0.101.100` has `target_commitish: main` (symbolic) —
  publishing lands the tag at current `main` HEAD, documented as R4 + Sharp Edge.
- No new scheduled job is introduced, so the ADR-033 Inngest-vs-GH-Actions-cron
  precedent gate (deepen Phase 4.4) does not apply.

### Research Insights — Test Implementation (grounded in repo precedent)

Best Practices:
- Stub `gh` the same way `plugins/soleur/test/audit-flag-flip.test.sh` stubs
  `curl`: write an executable stub into a temp `STUB_DIR`, `chmod +x` it, and run
  the snippet under `PATH="$STUB_DIR:$PATH"`. This keeps the live GitHub API and
  the LLM out of the assertion path (the discipline the plan requires).
- Drive the stub's behavior with `MOCK_GH_STATE=absent|published|draft` so a
  single stub covers all three scenarios; record `gh release edit`/`create` calls
  to a trace file the test asserts against.

Precedent-Diff (deepen Phase 4.4):
- The idempotency/finalise gating is a bash conditional over `gh` output, not a
  pattern-bound primitive (no SQL `SECURITY DEFINER`, no atomic-write, no lock).
  The closest sibling is the existing workflow's own Finalise step
  (`gh release edit --draft=false`), which the fix reuses verbatim — the only
  change is the `if:` gate reachability and the idempotency `--json isDraft`
  parse. No novel pattern is introduced.
- gh-CLI form note: `gh release view "$TAG" --json isDraft --jq '.isDraft'`
  returns the bare boolean (`true`/`false`); the plan's Phase 2 sketch parses via
  `jq -r '.isDraft'` from a captured JSON file — both are valid. Verified live:
  `gh release view web-v0.101.99 --json isDraft` → `{"isDraft":false}`,
  `gh release view web-v0.101.100 --json isDraft` → `{"isDraft":true}`.

Edge Cases:
- `gh release view "$TAG" --json isDraft` exits non-zero when the release does not
  exist at all (absent case) — the Phase 2 sketch's outer `if ... 2>/dev/null`
  correctly routes that to `exists=false, draft_exists=false`. The test's `absent`
  stub must exit non-zero for the `--json isDraft` invocation to exercise this.
- An already-**immutable** published release: `gh release edit --draft=false` on an
  already-published release is a no-op (does not error), so the widened Finalise
  gate is safe even if it fires on a freshly-published release within the same run.
