---
title: "fix(ci): refuse vinngest-v* tags whose commit is not reachable from main, in the publish workflow and the ADR-232 pin bump"
date: 2026-09-24
slug: fix-inngest-bootstrap-tag-ancestry-gate
branch: feat-one-shot-8747-inngest-tag-ancestry-gate
issue: 8747
closes: 8747
type: bug
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-09-24. **Sections enhanced:** 9.

**Agents used:**

- soleur:engineering:review:security-sentinel
- soleur:engineering:review:test-design-reviewer
- soleur:engineering:review:architecture-strategist
- a verify-the-negative and post-edit audit pass
- an attribution check (finished inline after the nested agent was interrupted)

### Key improvements

1. **The bump binds to the built commit through `--signed-commit`.** This closes a race in which a tag
   is re-pointed from an off-main build to a main commit while that build is still in flight. Without
   the binding, the bump would pass ancestry and still pin the off-main digest.
2. **The dispatch checkout uses a qualified `refs/tags/` ref**, so a same-named branch can no longer be
   built in place of the tag.
3. **Workflow-injection hardening.** The refusal step reads only the validated tag output, passed
   through `env:`, with no `${{ }}` in its body. The shallow check fails closed on empty output, and a
   missing `origin/main` gets its own refusal.
4. **Tests are behaviour-checked, not only shape-checked.** An inline-step harness executes the shipped
   step body against real git fixtures, which catches argument reversal, a dropped `exit 1`, and rc
   collapse. Every refusal row asserts its stop point. B7, B8 and B9 are rebuilt to constructions
   verified to exercise the right branch.
5. **ADR-241 / #8209 conflict surfaced.** A main-only environment on the bump job would refuse every
   tag-push run. ADR-232 §7 forbids the tag-pattern-policy repair, and #4326 is steered to
   dispatch-from-main.

### New considerations discovered

- The `model.c4` bump-flow edge is incomplete in a way that misleads, so its clause is restored.
- ADR-232's Context, §2 and Consequences passages need rewriting, not only an added §7.
- Census corrected:
  - the unbroken off-main run is the last **14** tags (16 of 44 overall);
  - GuardA landed in PR #7887 (issue #7695), on whose own branch `v1.1.26` was cut;
  - ADR-232's code merged 2026-09-20 (#8360).
- An existing workflow comment falsely claims the workflow file is always read from the default branch.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Issue #8747: a `vinngest-v*` tag cut on a commit that existed only on an unmerged pull-request branch was
published as an inngest-bootstrap image, and the ADR-232 automated pin-bump PR then merged that image's
pin into main while the source PR was still open. The content drift has since cleared, but nothing stops
the same sequence from recurring. This plan adds a main-reachability gate to both the publish workflow and
the pin-bump script.

## Research Insights

### Premise Validation (Phase 0.6)

- **#8747** — OPEN, P1, `type/bug`, `meta/machinery`. Premise holds: the gap is open on `origin/main`
  (`8d1b0501ad`, later `be0f5ca7e6`). Neither `.github/workflows/build-inngest-bootstrap-image.yml` nor
  `.github/scripts/bump-inngest-bootstrap-pin.sh` contains `merge-base`, `is-ancestor` or any
  reachability test (grepped both, the authorities, not a consumer).
- **#8741** — MERGED 2026-09-24T17:04:59Z (squash `f4c5f11b94`). **#8745** (the bot bump to v1.1.39) —
  MERGED 15:31:47Z, 93 minutes earlier. Confirms the issue's sequence.
- **Incident run 36018918724** — `event=push`, `head_branch=vinngest-v1.1.39`,
  `head_sha=22f0167d27181ef3543af68b6d127262c52b536c` (the peeled commit, not the tag object).
- **"Symptom has cleared" holds for CONTENT only.** All 13 baked carriers (the `cp apps/web-platform/infra/…`
  set GuardA derives from the workflow) are byte-identical between `vinngest-v1.1.39` and `origin/main`.
  But main still pins a commit that is **not** an ancestor of main — `22f0167d27` is a PR-branch commit
  and squash-merge means it never will be.
- **STALE-PREMISE FINDING (load-bearing).** "Refuse a tag whose commit is not reachable from origin/main"
  is not a rare-accident filter — it would have refused **every one of the last 14** tags
  (`v1.1.26`–`v1.1.39`). Census over all 44 `vinngest-v*` tags (re-verified at deepen): 28 on-main, the
  last being `v1.1.25`; 16 off-main — `v1.1.14`, `v1.1.24`, and the unbroken run `v1.1.26`–`v1.1.39` (on
  `pr/7887`, `pr/7978`, `pr/7996`, `pr/8001`, `pr/8005`, `pr/8019`, `pr/8248`, `#8741`'s branch). GuardA
  (tracked as issue #7695) landed in PR #7887 on 2026-09-08, and `v1.1.26` was cut on #7887's own branch
  — since then, cutting the tag on the PR branch has been
  the de-facto practice: GuardA reds any PR whose carriers differ from the pinned tag, and the only way
  to green it before merge was to tag the PR commit. Under squash-merge that commit is permanently
  unreachable from main. The runbook (`inngest-server.md` §Bootstrap-image release step 1) already
  says `git tag -a vinngest-vX.Y.Z <main-sha>`; practice drifted from it. The plan therefore changes an
  operator workflow, not only a CI edge — see §Decision: carrier-changing PR flow.
- **#6766** (deploy-script-tests not required) — OPEN. **#4326** (auto-mint `vinngest-v*` on infra push to
  main) — OPEN. **#8359** (ADR-232 auto-bump) — CLOSED. **#8209** (ADR-241, moves the bump job to a
  main-only environment + infra App) — OPEN, not yet on main (the bump job has no `environment:` today).
- **ADR corpus vs. proposed mechanism.** ADR-232 §Alternatives rejects a tag-triggered sibling workflow
  and a scheduled reconciler; neither is proposed here. ADR-232 never considered tag provenance — its
  §2 recomputes the target as semver-max over **all** tags. This plan amends ADR-232 (§7), it does not
  reverse it.

### Property List (Phase 0.6b)

- **P1** — No inngest-bootstrap image is built from a commit that is not reachable from `main`.
- **P2** — The automated pin bump never moves main's pin to a tag whose commit is not reachable from the
  tree the bump PR is based on.
- **P3** — The commit the gate verifies is the commit the build actually builds (a gate over X while
  building Y proves nothing).
- **P4** — A refusal is loud and names its remediation, on the publish run itself and not only through a
  downstream drift guard.
- **P5** — Operators know the supported flow: tag the squash-merge commit on main, after merge.

### Cut List (Phase 0.6b)

- **"Bump PR waits for / is blocked by the source PR"** (issue's alternative) → buys P2 → P2 is already
  bought, more simply, by the ancestry check: a tag on an unmerged branch is off-main by definition, and
  it stays off-main after a squash-merge. PR-linkage machinery would also need a tag→PR mapping that does
  not exist. Cut.
- **"Make GuardA required on the bump PR"** (issue's fix (b)) → buys P2's content half ("pin only to bytes
  on main") → the authoring-time ancestry gate buys the stronger provenance property; the required-check
  change is exactly #6766's scope (infra-validation has no `merge_group` arm and a 35-min budget, so
  making it required is a ruleset + pipeline change). Cut from this PR; comment on #6766 with the #8747
  rationale.
- **Changing AC6/bump target to `git tag --merged HEAD`** → would buy "an off-main tag never becomes
  the target" → **rejected, measured**: with 16 legacy off-main tags, `--merged` on main resolves to
  `v1.1.25` today, so the bump would open a **downgrade** PR and AC6 would red main immediately. The
  ancestry check on the resolved target buys the same property without re-defining "latest". Cut
  from this PR; it becomes correct after the post-merge re-anchor and is sequenced as #8782.
- **Registry provenance binding (digest → commit)** → out of scope; GuardA's header already records it
  as residual (1).

### Relevant files

- `.github/workflows/build-inngest-bootstrap-image.yml` — jobs `build` (checkout `ref: ${{ inputs.ref }}`,
  shallow tag tree; inline `Resolve image tag`) and `bump-cloud-init-pin` (`needs: build`, checkout
  `ref: main` + `fetch-depth: 0` + `fetch-tags: true`, runs **main's** copy of the bump script).
- `.github/scripts/bump-inngest-bootstrap-pin.sh` — `TARGET` = semver-max over all `vinngest-v*`; stages
  `args|resolve|rewrite|push|pr`; `result=opened|existing|noop|skipped|error`.
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — fixture suite (real git, PATH-shimmed
  `crane`/`gh`), Guard 1 behavior + Guard 2 workflow shape, `MIN_ASSERTIONS=150`.
- `.github/scripts/test/test-inngest-bootstrap-tag-guard.sh` — YAML-literal + inline-mirror suite for the
  `Resolve image tag` step.
- `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh` — **asserts the workflow has exactly the
  jobs `["build", "bump-cloud-init-pin"]`** and that `build` has no job-level `if:`/`continue-on-error:`.
  (v1 of this plan added a job and would have had to widen that set; v2 adds a step instead, so the
  set assert stays as-is.)
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — AC6 (pin == semver-max tag), GuardA
  (pinned tag's carriers byte-identical to HEAD). Unchanged by this plan.
- `.github/scripts/test/run-all.sh` — auto-discovers `test-*.sh`; the glob feeds the REQUIRED
  `guard-script-fixture-tests` (bash-only, `merge_group`, no path filter).
- `knowledge-base/engineering/architecture/decisions/ADR-232-…md`, `knowledge-base/engineering/operations/runbooks/inngest-server.md`
  §Bootstrap-image release, `knowledge-base/engineering/architecture/diagrams/model.c4` (edge
  `github -> soleurMarketplace`, which narrates the bump flow).

### Sibling sweep (hr-write-boundary-sentinel-sweep-all-write-sites)

- `build-inngest-bootstrap-image.yml` is the **only** workflow with `on.push.tags`, and
  `bump-inngest-bootstrap-pin.sh` is the **only** ADR-232-style pin-bump author (`gh pr create` census over
  `.github/` + `scripts/`: the other authors are bot-synthetic-check PRs, CLA evidence, constraint stage-b,
  PR auto-close — none bumps an image pin).
- Adjacent class, different mechanism — **publish from a non-main ref via `workflow_dispatch`**:
  `build-inngest-config-bundle.yml` (dispatchable from any branch; gated by the `inngest-config-signing`
  environment's required reviewer, which has **no** `deployment_branch_policy`; promotion is a human
  `terraform apply`) and `web-platform-release.yml`'s dispatch arm. Neither auto-bumps a pin, and the fix
  is an environment `deployment_branch_policy` in Terraform, not a tag-ancestry check. Deferred to a
  tracking issue (see §Deferred).

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-05-31-tag-driven-dispatch-invariant-and-checkout-refspec-tag-locality.md`
  — the build job's checkout is a shallow tag tree; a helper script is absent there on the dispatch path
  (#4700), so any build-job logic must be inline.
- `knowledge-base/project/learnings/best-practices/2026-07-05-bounded-retry-off-host-verify-and-fail-loud-guard-detection-command-exit.md`
  — neutralize the detection command's exit status (`merge-base --is-ancestor` returns 1 on "no") so
  `set -e` cannot abort before the tailored `::error::` prints.
- `knowledge-base/project/learnings/best-practices/2026-07-04-bash-yaml-drift-guard-must-mutation-test-fail-open-and-allow-trailing-comments.md`
  — mutation-test the fail-open direction; scope job-level asserts to the job block.
- `knowledge-base/project/learnings/test-failures/2026-09-19-every-guard-i-shipped-pinned-spelling-not-the-executed-program.md`
  — test the executed program (real git ancestry in fixture repos), not literal presence.
- `knowledge-base/project/learnings/workflow-patterns/2026-06-18-inngest-bootstrap-release-tag-then-dispatch-deploy.md`
  — tags must be annotated; the publish does not deploy.
- `git merge-base --is-ancestor`: 0 = ancestor, 1 = not, other (128) = error (git-scm docs). A shallow
  clone can turn a true ancestor into rc 1 — both checks refuse to decide in a shallow repo.
  **Measured 2026-09-24 in this worktree:** `vinngest-v1.1.39^{commit}` vs `origin/main` → rc 1;
  `vinngest-v1.1.25^{commit}` → rc 0; unknown object `deadbeef` → rc 128;
  `git rev-parse --is-shallow-repository` → `false`.

### External facts

- For `push` events the run's `GITHUB_SHA` is the pushed tip; for an annotated tag it is the peeled commit
  (run 36018918724: `head_sha=22f0167d27…`). Push-triggered runs use the workflow definition at that
  commit, so a tag on a branch forked before this fix runs the branch's (ungated) copy of the workflow.
  **The design does not rely on the publish gate alone for this reason**: the bump job checks out `main`
  and runs main's copy of the bump script, so P2 holds for every branch that carries the ADR-232 bump
  job at all.
- actions/checkout v4 `fetch-depth: 0` fetches `+refs/heads/*` and, with `fetch-tags: true`, all tags —
  so a tag pointing at an unmerged-branch commit resolves in a `ref: main` clone.
- Functional-discovery: no reusable action/skill worth adopting (closest: `rickstaa/action-contains-tag`,
  7 stars, one-command wrapper; rejected under SHA-pin + wrapper-vs-curl).

### CLAUDE.md / AGENTS conventions carried

`hr-github-app-auth-not-pat` (no new credential), `hr-write-boundary-sentinel-sweep-all-write-sites`
(sweep above), `cq-write-failing-tests-before` (fixture rows first), `hr-observability-as-plan-quality-gate`,
`cq-assert-anchor-not-bare-token` (shape asserts anchor on code, not comments).

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "Refuse a tag whose commit is not reachable from origin/main" reads as a filter for a rare accident | All of the last 14 tags (`v1.1.26`–`v1.1.39`) are PR-branch commits, unreachable from main under squash-merge; in-PR tagging is the de-facto practice GuardA forces | Implement the gate as stated (the operator's direction), and change the documented flow: tag the squash-merge commit on main after merge (§Carrier-changing PR flow). Disclosed as the main cost in §Risks |
| "The symptom has cleared" | Content cleared (13/13 carriers identical); main still pins off-main commit `22f0167d27` | Post-merge: cut `vinngest-v1.1.40` on main (identical content) — re-anchors the pin on an on-main commit AND is the live proof of the gate's happy path |
| Fix (b): make GuardA required on the bump PR | `deploy-script-tests` required-ness is #6766 (open); infra-validation has no `merge_group` arm | Not in this PR; the authoring-time ancestry gate buys the stronger property. Comment on #6766 |
| "Both the publish workflow and the auto-bump must refuse" | The publish gate runs the workflow YAML at the tagged commit, so a branch forked before this fix carries no gate; the bump job runs **main's** script | Both gates ship; the bump-script gate is the authoritative chokepoint, the publish gate stops the image from being built at all for branches that carry it |

## Problem Statement

`build-inngest-bootstrap-image.yml` fires on any `vinngest-v*.*.*` tag push, builds the image from the
tag's tree, and its `bump-cloud-init-pin` job runs `bump-inngest-bootstrap-pin.sh`, which pins the
semver-max tag and arms auto-merge. At no point does anything ask whether the tagged commit is on
`main`. A tag cut on an open PR's commit therefore produced an image, a bump PR, and a merged pin of
unreviewed bytes (#8745 merged 93 minutes before its source #8741). Main's GuardA caught the resulting
content drift, but `deploy-script-tests` is advisory, so nothing blocked the merge.

## Proposed Solution

*Revised after plan review (v2): the publish check moved inline into `build`, the shared helper became
a function in the bump script, and the bind step, `--expect-commit`, `--allow-off-main`, the gate job,
its Slack step, the `TARGET == pinned tag` skip, the AC6/GuardA hint lines and the `model.c4` clause
were cut. See §Plan Review Revisions.*

Two checks, one per chokepoint. **The bump gate is the fix for #8747**: the harm was an off-main pin
merging into main, and nothing pulls an image that no pin names. The publish gate is
defence-in-depth that keeps unreviewed code out of the registries.

1. **Bump gate (the fix)**: `bump-inngest-bootstrap-pin.sh` gains a function
   `target_on_main <tag-ref>`. It runs right after `TARGET` is resolved and **before** the `crane digest`
   loop. It refuses (`die ancestry …`) unless `refs/tags/vinngest-${TARGET}^{commit}` is an ancestor of
   `HEAD`, which is the `main` checkout the bump PR is based on. The existing `if: failure()` Slack step
   notifies.
2. **Publish gate (defence-in-depth)**: the `build` job's checkout gains `fetch-depth: 0` (all branches +
   tags). A new inline step, `if: ${{ !inputs.mirror_only }}`, placed after checkout and before
   `Build + verify + push`, refuses unless `HEAD` (the commit actually being built) is an ancestor of
   `refs/remotes/origin/main`. The step checks `HEAD` itself, so what it verifies is what gets built. No
   second job and no bind step are needed. `mirror_only` builds nothing and cannot move a digest, so the
   step skips it. The step-level `!inputs.mirror_only` pattern is already used on `Read pinned …` and
   `Build + verify + push`.

### `target_on_main` (bump script)

- Resolves `refs/tags/vinngest-${TARGET}^{commit}` **explicitly**, never the bare name, so a branch named
  `vinngest-vX.Y.Z` cannot stand in for the tag. An unresolvable tag → `die ancestry "tag not found"`.
- Refuses in a shallow repository (`git rev-parse --is-shallow-repository` = `true`). A cut-off history
  can report a real ancestor as rc 1.
- Captures `git merge-base --is-ancestor` rc explicitly (`|| rc=$?`): 0 → continue; 1 → `die ancestry`
  naming `vinngest-${TARGET}` and its commit. When `SIGNED_TAG != TARGET`, the message says the
  **semver-max** tag is the off-main one, not the tag this run published. Any other rc → `die ancestry`
  "could not decide (rc=N)". The rc values are measured (§Research Insights).
- The refusal prints the remediation: `git push origin :refs/tags/vinngest-${TARGET}`, then re-cut on the
  squash-merge commit on `main` (`git tag -a … <main-sha> -m …`), then re-run the failed job.
- It runs before `crane` on purpose. An off-main semver-max tag whose publish was refused has no image,
  and the existing unresolved-digest arm would report "that tag's publish is probably still in flight"
  and exit `skipped`: the wrong diagnosis, on a green job.
- Stage list in the header's RESULT CONTRACT becomes `args|resolve|ancestry|rewrite|push|pr`.

### Inline publish step (build job)

```yaml
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          # CHANGED on dispatch: a fully qualified tag ref, so a same-named branch can never be
          # checked out instead of the tag (GuardA residual (3)). On push: '' -> the pushed commit.
          ref: ${{ github.event_name == 'workflow_dispatch' && format('refs/tags/{0}', inputs.ref) || '' }}
          fetch-depth: 0          # NEW: history + origin/main, so ancestry is decidable

      - name: Resolve image tag   # unchanged; validates the tag against ^v[0-9]+\.[0-9]+\.[0-9]+$
        id: tag

      - name: Record the built commit (#8747)            # NEW; runs on EVERY path, mirror_only included
        id: commit
        # c=$(git rev-parse --verify HEAD^{commit}); require ^[0-9a-f]{40}$; commit=$c >> $GITHUB_OUTPUT

      - name: Refuse a commit that is not on main (#8747) # NEW, inline (tag tree has no helper)
        if: ${{ !inputs.mirror_only }}
        env:
          TAG: ${{ steps.tag.outputs.tag }}        # already validated; the ONLY tag source
          HEAD_SHA: ${{ steps.commit.outputs.commit }}
        run: |
          # set -uo pipefail (NOT -e). No ${{ }} anywhere in this body.
          # [ "$(git rev-parse --is-shallow-repository)" = false ] || refuse "shallow/undecidable"
          # git rev-parse --verify -q refs/remotes/origin/main >/dev/null || refuse "no origin/main"
          # tag_c=$(git rev-parse --verify -q "refs/tags/vinngest-$TAG^{commit}") || refuse "tag not found"
          # [ "$tag_c" = "$HEAD_SHA" ] || refuse "checkout is not the tag's commit (re-pointed tag?)"
          # rc=0; git merge-base --is-ancestor "$HEAD_SHA" refs/remotes/origin/main || rc=$?
          # rc 0 -> echo "verdict=on-main commit=$HEAD_SHA"
          # rc 1 -> ::error:: naming vinngest-$TAG, $HEAD_SHA, the delete + re-cut commands; exit 1
          # else -> ::error:: "could not decide (rc=$rc)"; exit 1
```

- **Inline.** The step stays inline because the dispatch path checks out an existing tag's tree, which
  predates any new helper (#4700).
- **No fetch.** `fetch-depth: 0` already fetches `+refs/heads/*:refs/remotes/origin/*` from this
  repository only. Fork pushes cannot trigger runs here, and `main` is protected and only grows, so a
  stale view can only cause a false refusal.
- **Injection-safe.** The step sits after `Resolve image tag` and reads the tag only through its
  validated output, passed via `env:`. Nothing in the body is interpolated with `${{ }}`, and it never
  echoes raw `$GITHUB_REF`. Every value it prints is a validated `vX.Y.Z` or 40-hex, so no CR/LF can
  reach an annotation. Free-text sources (tag messages, `git log %s`, `describe`) are forbidden in
  `::error::`.
- **Every check fails closed.** The shallow check refuses unless the output is exactly `false`, so a git
  error that prints nothing is refused too. `HEAD` is resolved with `--verify … ^{commit}`.
- **`Record the built commit` also runs under `mirror_only`.** Its output feeds the bump binding below.
- **Existing comment corrected.** The `Resolve image tag` comment says the workflow file is "always read
  from the default branch". That is false for tag pushes: a push runs the tagged commit's YAML. Correct
  it in the workflow and in `.github/scripts/test/test-inngest-bootstrap-tag-guard.sh`, so no reader
  mistakes the publish check for the authoritative one.

### Bump binding to the built commit (`--signed-commit`)

Security review, P1: the ancestry check alone judges the tag's commit **at bump time**, while `RESOLVED`
is whatever GHCR holds for that tag. A tag built off-main by a pre-fix branch's YAML, then deleted and
re-cut on main while the first run is still in flight, would pass the check and pin the off-main
image's digest: the signed digest and the resolved digest agree, because both are the off-main
build's.

The fix is to bind the check to the built commit:

- The bump job passes `--signed-commit "${{ needs.build.outputs.commit }}"` (a new `build` output from
  `steps.commit`).
- The script requires the flag and validates it against `^[0-9a-f]{40}$`. A missing flag dies at `args`,
  so a pre-fix branch's YAML (which lacks the flag) fails closed at the bump.
- When `SIGNED_TAG == TARGET`, `target_on_main` also requires
  `refs/tags/vinngest-${TARGET}^{commit} == SIGNED_COMMIT`, alongside the existing digest cross-check.
- When `SIGNED_TAG != TARGET` (a backfill of an older tag), the binding does not apply, exactly as the
  digest cross-check does not. The ancestry check on `TARGET` still runs.
- Existing fixture rows gain the flag through `run_bump`.

### Carrier-changing PR flow (the operator-visible change)

Before: tag the PR commit, get an image, and (after ADR-232) an auto-bump PR merges on its own; the
source PR's GuardA goes green after a sync. That is the sequence #8747 went through, and it is now
refused.

After:

1. The PR that changes a baked carrier merges. Its `deploy-script-tests` GuardA row is red (advisory),
   which is expected and is described as expected in the runbook.
2. Tag the squash-merge commit on `main` (`git tag -a vinngest-vX.Y.Z <main-sha> -m …`).
3. The publish check passes, the image builds, and the ADR-232 bump PR auto-merges.
4. Main's GuardA is red from (1) to (3). That window is **longer** than the one ADR-232 accepted: it now
   runs from the source PR's merge until someone tags main, not only from tag to bump.
   `main-health-monitor.yml` (every 6 h) may file `ci/main-broken` if the window spans one of its runs.
   The red is truthful: main's carriers are in no pinned image. #4326 (auto-mint on infra push to main)
   is the zero-touch fix. Whether to fold a minimal version of it into this PR is recorded as a decision
   challenge.
5. **Lost capability:** a candidate image can no longer be built from an unmerged PR (#8781).
6. **Rollback** to a legacy off-main version (`v1.1.26`–`v1.1.39`) is a manual pin PR to an image that
   already exists. A *rebuild* of such a tag is refused, so the runbook says to roll back by re-cutting
   the old content on main as a new version.

## Technical Considerations

- **Why the bump gate is authoritative.** Push-triggered runs execute the workflow YAML at the tagged
  commit, so a branch forked before this merges has no publish check. Every branch since ADR-232
  (#8360, merged 2026-09-20) *does* have the bump job, and that job checks out `main` and runs main's script.
  **Caveat (ADR-232 §7):** the bump job's own definition also comes from the tagged commit's YAML, so
  this holds only for branches whose copy of that job is unmodified. The threat model is accident, not a
  hostile branch. A branch forked before ADR-232 has no bump job and moves no pin; it can still build an
  off-main image, which is inert because no pin names it.
- **`mirror_only` is not refused.** It builds nothing and cannot move a digest (it crane-copies an
  existing GHCR manifest). Refusing it would permanently stop the 16 legacy off-main versions
  (`v1.1.26`–`v1.1.39`, including today's pin) from being backfilled into zot after an eviction. That
  would lose a rollback path. The pin stays protected because the bump gate judges the target however
  the run started.
- **Legacy-pin window.** Main's pin is `v1.1.39`, which is off-main. Until the post-merge re-anchor
  (`v1.1.40` on main), a `mirror_only` backfill of `v1.1.39` resolves `TARGET = v1.1.39`, and the bump
  job fails at `ancestry` instead of `noop`. That failure is loud and harmless. It is why AC-P1 runs
  **immediately** after merge, not at some later time.
- **AC6 and the bump target stay "semver-max over all tags" in this PR.** An off-main tag pushed after
  this lands is refused at publish. AC6 then reds main and every open PR until the tag is deleted; the
  refusal prints the deletion command. `--merged` resolves to `v1.1.25` today (Cut List) but resolves
  correctly after the re-anchor. The switch of both to semver-max over `git tag --merged HEAD` is
  therefore sequenced as #8782.
- **The re-anchor does not touch a live host.** The pin feeds the dedicated host's `user_data`, but the
  merge-time apply's `-target=` allow-list excludes `hcloud_server.inngest`
  (`apps/web-platform/infra/inngest-host.tf`). Nothing is replaced until an `inngest-host-replace` or an
  untargeted apply consumes the new pin. Every ADR-232 bump already carries that exposure, and
  `v1.1.40`'s carriers are byte-identical to `v1.1.39`'s.
- **Cost.** The build job's clone becomes full-history, the same as the bump job's. Publishes happen a
  few times a week.
- **ADR-241 / #8209 conflict (architecture review, high).** ADR-241's plan
  (`2026-09-22-feat-evict-privileged-terraform-credentials-plan.md`, item 4) gives
  `bump-cloud-init-pin` `environment: infra-privileged`. That environment's only deployment policy is
  `branch_pattern = "main"` (`apps/web-platform/infra/infra-privileged-environment.tf`). A tag-push run's
  ref is `refs/tags/vinngest-v…`, so GitHub will refuse the bump job on every tag push once #8209 lands.
  - The obvious repair, a `vinngest-v*` tag policy, would reopen #8747 in a worse form: YAML written on a
    branch would run with Tier-B secrets, and those secrets load before any ancestry step runs.
  - ADR-232 §7 forbids that repair.
  - The PR comments on #8209 with the conflict.
  - The comment on #4326 recommends the compatible shape: mint the tag, then **dispatch** the build from
    `main` (`inputs.ref` = the new tag). That passes a main-only policy, and because a
    `GITHUB_TOKEN`-minted tag fires no `push` event anyway, it also removes §7's tagged-commit-YAML
    caveat.
- **Concurrent work.** #8759 edits `inngest-server.md`. It can only cause rebase conflicts.

## Implementation Phases

### Phase 1: RED (tests first, `cq-write-failing-tests-before`)

1. Extend the fixtures in `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`:
   - add `seed_tag_at`;
   - add `MOCK_CRANE_LOG` to the crane stub, to `reset_state` and to `run_bump`;
   - make `run_bump` pass `--signed-commit`.
2. Add rows B1–B11 and B7a. Each one asserts its own precondition and its stop point (§Test Scenarios).
3. Add the inline-step harness I1–I9. It slices the `run:` body out of the YAML by step name.
4. Add shape asserts S1–S8 to the Guard 2 section, sliced by job key and comment-stripped. Raise
   `MIN_ASSERTIONS` by the number of assertions added.
5. In `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh`, add the exact-string
   `if: ${{ !inputs.mirror_only }}` assert for the refusal step, and the no-`if:` assert for
   `Record the built commit`. The two-job set assert does not change.
6. Run both suites. Confirm they fail for the expected reasons.

### Phase 2: GREEN

7. In `bump-inngest-bootstrap-pin.sh`:
   - add `target_on_main`, the required `--signed-commit`, and the `ancestry` stage;
   - update the header INPUTS and stage list.
8. In `build-inngest-bootstrap-image.yml`:
   - qualify the dispatch checkout ref, and set `fetch-depth: 0`;
   - add `Record the built commit` and the `build.outputs.commit` it feeds;
   - add the inline refusal step, after `Resolve image tag`;
   - pass `--signed-commit` to the bump;
   - correct the "always read from the default branch" comment, in both the workflow and
     `test-inngest-bootstrap-tag-guard.sh`.
9. Run both suites, plus these three, and confirm AC6 and GuardA are unchanged and green:
   - `bash .github/scripts/test/run-all.sh`
   - `bash .github/scripts/test/test-inngest-bootstrap-tag-guard.sh`
   - `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`

### Phase 3: Record the decision

10. Amend ADR-232. It is Provisional and its decision stands, and the `## Amendment` pattern is the
    precedent in ADR-204 and ADR-218.
    - Add **§7**:
      - Publish and bump both refuse an off-main tag.
      - The bump check is the authoritative one, with the caveat about an unmodified bump job.
      - The bump binds to the built commit through `--signed-commit`.
      - `mirror_only` is not refused.
      - Ancestry is an **accident control, not a secret boundary**: never admit the bump job to an
        environment through a tag-pattern deployment policy (see §Technical Considerations, ADR-241).
      - Residual: an old main commit, for example one whose code was later reverted, passes both checks.
    - Add `ancestry` to §6's stage list.
    - Rewrite three passages the change falsifies:
      - Context: "the writer and the checker cannot disagree on what latest means" (they now disagree
        whenever an off-main tag is semver-max, until #8782).
      - §2: the target rule gains the ancestry refusal.
      - Consequences: "drift window shrinks to one CI run" (false for carrier-changing PRs, where the
        window now runs from merge to the manual tag).
    - Add an `## Amendment 2026-09-24 (#8747)` note recording the stuck-main state until #8782.
    - Add a sequencing line naming #8782.
    - Add two rows to Alternatives: the bump waits for the source PR; a `--merged` target now.
11. `inngest-server.md` §Bootstrap-image release:
    - Step 1: the tag goes on the squash-merge commit on `main` after merge; a PR-branch tag is refused;
      include the delete command.
    - Step 2: the bump is authored automatically (ADR-232); keep the four-site detail as the manual
      fallback.
    - Add the carrier-changing PR flow and the rollback-by-re-cut note.

### Phase 4: Follow-through

12. Comment on #6766. The #8747 incident is a concrete case for making GuardA blocking, **and** making it
   required before #4326 (or a PR-diff exemption) lands would deadlock every carrier-changing PR: it
   cannot go green until a tag exists on main, and that tag cannot exist until it merges.
13. Comment on #4326: tags are now required on main, so it is the next PR that completes the flow.
14. Link #8780, #8781 and #8782 from the PR body.

### Post-merge (pipeline-executed, immediately)

15. Cut `vinngest-v1.1.40` on this PR's squash-merge commit (content identical to `v1.1.39`).
16. Watch the run with `gh run watch`. The inline step must print `verdict=on-main`, and the bump job
    must report `result=opened` with auto-merge armed.
17. After the bump merges, check that AC6 and GuardA are green on main.
18. **Condition.** If #8209 has already put `environment: infra-privileged` on the bump job, a tag push
    cannot run it. In that case, re-anchor by dispatching the build from `main` with
    `inputs.ref=vinngest-v1.1.40`, after pushing the tag.
19. Pick up #8782 in the next session, right after AC-P2 passes, rather than leaving it in the backlog.
    Until it lands, an off-main tag leaves main stuck: AC6 demands that pin, and the bump refuses it.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Bump PR waits for / is blocked by the source PR | Needs a tag→PR mapping that does not exist; ancestry gives the same guarantee with one git call, and survives squash-merge |
| Make `deploy-script-tests` (GuardA) a required check | #6766's scope; ruleset + pipeline change; checks content, not provenance; deadlocks carrier PRs before #4326 |
| Target = semver-max over `git tag --merged HEAD` **in this PR** | Measured: resolves to `v1.1.25` on main today → downgrade PR + AC6 red. Correct after the re-anchor → #8782 |
| Separate `verify-tag-on-main` job + bind step + shared helper (plan v1) | Verifies in one job and builds in another, which needed a bind step and `--expect-commit` to reconnect them; checking `HEAD` inside `build` holds by construction |
| Refuse `mirror_only` too | Permanently strands the 16 legacy off-main versions from zot backfill; builds nothing |
| GitHub compare API instead of git | Network + token dependency; git ancestry is hermetic and fixture-testable |
| Bump refuses when the target's carriers differ from main's | Duplicates GuardA's carrier derivation; a stale-but-on-main pin is reviewed code |
| Tag-protection ruleset | Rulesets cannot express "tag must point at a main-reachable commit" |

## Deferred

- **#8780**: `workflow_dispatch` from a non-main ref can publish artifacts. This covers
  `build-inngest-config-bundle.yml` (its environment has no `deployment_branch_policy`),
  `web-platform-release.yml`'s dispatch arm, and this workflow's own dispatch arm when dispatched from a
  feature-branch workflow ref. The fix is a different mechanism from this PR's.
- **#8781**: a pre-merge candidate build of the bootstrap image, the capability this PR removes.
- **#8782**: switch AC6 and the bump target to `--merged HEAD`. Blocked on AC-P2.
- **#4326**: auto-mint tags on main. It is the planned next PR, the zero-touch completion of the new
  flow.
- **#6766**: making GuardA blocking. It must wait for #4326 (the comment carries the deadlock warning).

## Files to Create

None.

## Files to Edit

- `.github/scripts/bump-inngest-bootstrap-pin.sh`:
  - `target_on_main` and the `ancestry` stage, placed after `TARGET` and before `crane`;
  - the required `--signed-commit` argument, bound to the tag's commit when `SIGNED_TAG == TARGET`;
  - the header stage list and INPUTS.
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`: add `seed_tag_at`, `MOCK_CRANE_LOG` and
  `--signed-commit` in `run_bump`; rows B1–B11 and B7a; the inline-step harness I1–I9; shape asserts
  S1–S8; raise `MIN_ASSERTIONS`.
- `.github/workflows/build-inngest-bootstrap-image.yml`:
  - `build` checkout: `fetch-depth: 0`, plus the qualified `refs/tags/` ref on dispatch;
  - the `Record the built commit` step and a `commit` output on `build`;
  - the inline refusal step;
  - `--signed-commit` passed to the bump;
  - the corrected "default branch" comment and a header comment.
- `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh`: exact-string asserts on the new
  step's `if: ${{ !inputs.mirror_only }}` (operand inversion is the risk) and on its position before
  `Build + verify + push`. The two-job set assert does not change.
- `knowledge-base/engineering/architecture/decisions/ADR-232-inngest-bootstrap-pin-bumps-are-authored-by-the-publish-workflow.md`:
  §7, §6 stage list, amendment note, two Alternatives rows.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: §Bootstrap-image release.
- `knowledge-base/engineering/architecture/diagrams/model.c4`: the `github -> soleurMarketplace` edge
  clause.
- `.github/scripts/test/test-inngest-bootstrap-tag-guard.sh`: correct the "always read from the default
  branch" header claim.

## Open Code-Review Overlap

None. On 2026-09-24, 78 open `code-review` issues were queried against every path in Files to Edit (and
against `ADR-232`). There were zero matches.

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) a false refusal, where a legitimate on-main
  `vinngest-v*` tag is refused and a fix to the dedicated Inngest host (the scheduler every user's
  background jobs run on) cannot ship until the gate is fixed; or (b) a false pass, where the next
  `inngest-host-replace` boots bootstrap code nobody reviewed or merged, and every user's scheduled jobs
  run on it.
- **If this leaks, the user's workflow is exposed via:** a production bootstrap image carrying unreviewed
  code on the host that runs every user's Inngest functions. Anyone with tag-push rights can cause it by
  tagging an unmerged commit. Accident is the threat model; the same check also removes a review bypass.
- **Brand-survival threshold:** `aggregate pattern`. This is a platform-integrity control whose breach
  degrades every user at once, not a per-user data exposure. No CPO sign-off gate applies.

## Observability

```yaml
liveness_signal:
  what: "the build-inngest-bootstrap-image.yml run conclusion per publish; the inline step prints verdict=on-main commit=<sha>; the bump job prints result=<kind>"
  cadence: "per vinngest-v* tag push or dispatch (a few per week)"
  alert_target: "GitHub run-failure email to the tag pusher; Slack releases channel via the bump job's existing if: failure() step (SLACK_RELEASES_WEBHOOK_URL)"
  configured_in: ".github/workflows/build-inngest-bootstrap-image.yml (build job inline step; bump-cloud-init-pin job)"

error_reporting:
  destination: "GitHub Actions run log + ::error:: annotations + Slack releases webhook (no Sentry: CI-only surface, no runtime process)"
  fail_loud: "::error:: from the build step naming the tag, the commit and the delete + re-cut commands; ::error::ancestry: … and result=error from the bump script"

failure_modes:
  - mode: "tag pushed on a commit not reachable from main (the #8747 class)"
    detection: "build's inline step exits 1 with verdict off-main before Build + verify + push; the bump job never runs; AC6 in cloud-init-inngest-bootstrap.test.sh reds main until the tag is deleted"
    alert_route: "GitHub run-failure email; main-health-monitor ci/main-broken issue for the AC6 red"
  - mode: "tag pushed from a branch whose workflow copy predates the check"
    detection: "image builds, but main's bump-inngest-bootstrap-pin.sh dies at stage ancestry before any write"
    alert_route: "Slack (existing pin-bump failure step)"
  - mode: "semver-max tag is off-main while a legitimate on-main tag is published"
    detection: "bump dies at ancestry naming the semver-max tag as the offender"
    alert_route: "Slack (existing pin-bump failure step)"
  - mode: "check cannot decide (shallow clone, tag unresolvable, merge-base error)"
    detection: "inline step or bump script exits non-zero with a cause-specific ::error::; fail-closed"
    alert_route: "GitHub run-failure email / Slack for the bump job"

logs:
  where: "GitHub Actions logs for build-inngest-bootstrap-image.yml runs (gh run view <id> --log)"
  retention: "GitHub default 90 days"

discoverability_test:
  command: "git tag --merged origin/main --list vinngest-v1.1.25"
  expected_output: "vinngest-v1.1.25"
```

The probe reads the same primitive both checks read (tag reachability from `origin/main`) and prints a
literal. It needs no pipe and no network, and it assumes tags are fetched locally.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-232.** This extends the ADR; it does not reverse it. Add §7 (§Implementation Phases
step 10). No new ADR ordinal is claimed.

### C4 views

All three model files were read: `model.c4`, `views.c4` and `spec.c4`.

**One `.c4` edit, a correctness update.** ADR-232 §Verification names the `github -> soleurMarketplace`
edge as the place where the bump's controls are documented. That edge narrates the bump flow step by
step. Without the new refusal, a reader would conclude that an off-main semver-max tag gets pinned.
So the edge is incomplete rather than false, and the gap misleads. Append:

> refuses (stage `ancestry`, before crane) a semver-max tag whose commit is not an ancestor of main, and
> binds to the built commit; the build refuses an off-main HEAD (ADR-232 §7, #8747)

Keep the stage list identical to ADR-232 §6 in the same commit.

**Enumeration:**

- **Actor.** `founder` ("Founder / Operator") is modeled. There is **no** `founder -> github` tag-push
  edge. Tag pushing is part of the operator's generic repository interaction, which the model does not
  break out per git verb. This change adds no new relationship, so none is added. The absence is
  recorded here rather than implied away.
- **Systems.** `github` (Actions), GHCR and zot are modeled.
- **Containers, stores, relationships.** No new container, data store, external system or access
  relationship.
- **Counts.** No count embedded in edge prose moves.

Validate with `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`,
`apps/web-platform/test/c4-render.test.ts` and `plugins/soleur/test/c4-model-freshness.test.sh`.

### Sequencing

The decision is true the moment this merges. The target-selection follow-up is #8782.

## Guard Contract

### Guard 1: bump-script ancestry stage (`test-bump-inngest-bootstrap-pin.sh`, behavior rows)

**Property.** `bump-inngest-bootstrap-pin.sh` never pushes a branch, opens a PR or arms auto-merge for a
`TARGET` whose commit is not reachable from the `HEAD` it rewrites. It never passes the stage without a
successful ancestry test.

**Assembly.** The script's write paths (rewrite → commit → push → `gh pr create`/`merge`) and its first
network call (`crane digest`) all come after the single `TARGET` resolution. `target_on_main` sits
between that resolution and `crane`. The chokepoint is that ordering, and the target is the only input
it judges.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `target_on_main` call (guard's own dispatch) | RED: B1 (off-main semver-max) must end `result=error`, `::error::ancestry:`, zero pushes, zero `gh` calls |
| 2 | Move the call after the `crane digest` loop (REORDER) | RED: B1 asserts the crane stub log is EMPTY; after the reorder crane is called, and for an off-main tag with no image the run ends `skipped` exit 0 |
| 3 | Judge `SIGNED_TAG` instead of `TARGET` | RED: B3 (signed tag on-main, semver-max off-main) must end `result=error` at `ancestry` |
| 4 | Collapse rc handling (`if merge-base …; then ok; else refuse`) or treat rc 128 as pass | RED: B7 (unresolvable base) must end `result=error` with the "could not decide" wording, not the off-main wording |
| 5 | Resolve the bare `vinngest-${TARGET}` instead of `refs/tags/…` | RED: B8 (`refs/vinngest-vX.Y.Z` shadows the bare name) must end in refusal |
| 6 | Drop the shallow-repo refusal | RED: B9's empty-crane-log assertion (the tag is on main, so without the refusal crane is called) |
| 7 | Skip the `SIGNED_COMMIT` equality when `SIGNED_TAG == TARGET` | RED: B10 |

**Harness rows.** Must-RED on the suite: B1's fixture first asserts `git merge-base --is-ancestor` rc 1
on its own tag, so a fixture that accidentally tags `main` reds the row instead of passing it vacuously.
B2 (the squash shape) is a fixture row rather than a code mutation: content equality must not satisfy
the gate.
Must-PASS non-canonical: B4, an OLDER off-main tag below an on-main semver-max → `result=opened`; B5, a
true merge commit (not a squash) bringing the side branch into main → `result=opened`; B6, an annotated
tag on an older main commit with main advanced → `result=opened`. Every pre-existing row (all tags on
`main`) stays green unchanged.

**Anchor.** Verdicts come from git's own ancestry walk over real fixture repositories, not from a stored
value. No single diff can weaken the check and its expected answer together.

### Guard 2: publish step (inline-step harness I1–I6 + shape asserts S1–S4 + mirror-only suite)

**Property.** Every non-`mirror_only` run of `build` refuses, before `Build + verify + push`, a `HEAD`
that is not an ancestor of `refs/remotes/origin/main`, and `HEAD` is the commit the build uses.

**Assembly.** The single checkout in the `build` job (`fetch-depth: 0`), and the one inline step: its
`if:`, its position relative to `Build + verify + push` and `Mirror inngest image GHCR→zot`, and its
`run:` body. The harness executes the shipped body, sliced from the YAML. No other job builds.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Hollow the step (`run: true`) or delete it | RED: I2 (off-main must exit 1); S2 if deleted |
| 2 | Reverse the arguments (`--is-ancestor origin/main HEAD`) | RED: I4 (side commit off main's tip must exit 1) |
| 3 | Print the rc-1 `::error::` but drop `exit 1` | RED: I2/I3 assert rc 1 |
| 4 | Collapse rc 1 and 128 into one branch | RED: I6 asserts the "could not decide" wording |
| 5 | Drop the shallow refusal | RED: I5 |
| 6 | Move the step after `Build + verify + push` (REORDER) | RED: S3 line order |
| 7 | Invert or drop the `if:` | RED: mirror-only suite exact-string assert on `${{ !inputs.mirror_only }}` |
| 8 | Revert the checkout to the default depth | RED: S1 |
| 9 | Interpolate `${{ github.ref_name }}` into the body instead of the validated env | RED: S5 |
| 10 | Refuse the shallow case only when the output `== true` (fail-open on empty) | RED: I8 |
| 11 | Revert the dispatch checkout to the bare `inputs.ref` | RED: S7 |

**Harness rows.** Must-RED on the suite: rename the step. The harness slices by name, so it fails to
find a body, and S2 reds instead of the harness passing on an empty body. Must-PASS non-canonical:
extra comment lines and reordered `with:` keys in the checkout still pass.

**Anchor.** The harness executes the committed step body against real git fixtures, so a weakened body
fails its rows. Live proof is AC-P1.

## Test Scenarios

Fixture helper: add `seed_tag_at <tag> <rev> [--annotate]`. The existing `seed_tag` only makes
lightweight tags on HEAD, and these rows need annotated tags on side-branch commits. Every fixture ends
checked out on `main`, because the script runs `checkout -qB` from HEAD.

Every **refusal** row asserts the stop point, not just `result=error`:

- stderr contains `::error::ancestry:`
- the crane stub log (`MOCK_CRANE_LOG`) is empty
- the gh log is empty
- the bare origin has no `soleur/inngest-pin-*` branch

Each fixture first asserts its own precondition (for example, `git merge-base --is-ancestor` returns 1
on its tag) so that a mis-built fixture reds instead of passing vacuously.

Bump-suite behaviour rows (real git):

- **B1** The semver-max tag is annotated and sits on an unmerged side-branch commit, and a crane digest
  is seeded for it. Expected: refusal. Because the digest is seeded, deleting the check yields `opened`,
  not a quiet `skipped`.
- **B2** The same side branch is squash-merged into `main` with identical content. Expected: still
  refusal.
- **B3** `--signed-tag` is on-main while the semver-max tag is off-main. Expected: refusal, and the
  message names the semver-max tag as the offender.
- **B4** An older off-main tag sits below an on-main semver-max. Expected: `result=opened`.
- **B5** A true merge commit brings the side branch into `main`. Expected: `result=opened`.
- **B6** The tag is on an older `main` commit and main has advanced 3 commits; a lightweight-tag variant
  is included. Expected: `result=opened` for both.
- **B7** The ancestry walk cannot complete. Construction, verified at deepen:
  1. Build main `c1←c2←c3` and a side branch off `c1` carrying the tag.
  2. Delete `c2`'s loose object.
  3. Assert that `rev-parse` of the tag still succeeds, that `git cat-file -e c2` fails, and that
     `merge-base` returns 128.

  Expected: refusal with the "could not decide" wording.
- **B7a** The tag's commit object is absent, so `rev-parse …^{commit}` fails. Expected: refusal with the
  "tag not found" wording.
- **B8** `git update-ref refs/vinngest-vX.Y.Z <main-sha>` shadows the tag's bare name; a same-named
  *branch* does NOT shadow it, because git prefers the tag (measured). Expected: refusal, because only
  the explicit `refs/tags/…` resolution judges the real tag.
- **B9** A `file://` depth-1 clone with the semver-max tag on the HEAD of `main`, with `F_REPO` pointed at
  the clone. Expected: refusal (shallow). With the shallow refusal removed, `merge-base` returns 0 and
  crane is called, so the empty-crane-log assertion is what reds.

- **B10** The signed commit differs from the tag's current commit while `SIGNED_TAG == TARGET`, which is
  the re-pointed-tag race. Expected: refusal at `ancestry`.
- **B11** `--signed-commit` is missing or malformed. Expected: `result=error` at `args`.

Inline-step behaviour harness. It follows the `test-inngest-bootstrap-tag-guard.sh` precedent but
**slices** the step's `run:` body out of the YAML by step name instead of keeping a copy, so the tested
body is the shipped body. Each row runs it with `bash` inside a fixture clone that has
`refs/remotes/origin/main`:

- **I1** HEAD on main → rc 0, prints `verdict=on-main`.
- **I2** HEAD on an unmerged side commit → rc 1, `::error::` naming the commit.
- **I3** Squash-merged side commit → rc 1.
- **I4** HEAD is a side commit branched from main's tip. Expected: rc 1. This row catches the
  argument-reversal mutant (`--is-ancestor origin/main HEAD`).
- **I5** Shallow clone → rc ≠ 0 with the shallow message.
- **I6** Corrupt history (the B7 construction) → rc ≠ 0 with the "could not decide" message, not the
  off-main message.
- **I7** `HEAD_SHA` differs from the tag's commit → rc ≠ 0 with the "re-pointed" message.
- **I8** A `git` stub makes `--is-shallow-repository` print nothing. Expected: refusal (fail-closed).
- **I9** `refs/remotes/origin/main` is absent. Expected: refusal with its own message.

Shape asserts (bump suite Guard 2 section, sliced by job key and comment-stripped):

- **S1** the build checkout has `fetch-depth: 0`.
- **S2** the step is named exactly as the harness slices it, and its `run:` body is non-empty.
- **S3** the step precedes `Build + verify + push` and `Mirror inngest image GHCR→zot`.
- **S4** neither the step nor the `build` job carries `continue-on-error`.
- **S5** the step body (comment-stripped) contains no `${{`, and its `env:` binds
  `TAG: ${{ steps.tag.outputs.tag }}`.
- **S6** the step follows `Resolve image tag`, and `Record the built commit` carries no `if:`.
- **S7** on dispatch the checkout `ref:` expression contains `format('refs/tags/{0}', inputs.ref)`.
- **S8** the bump invocation passes `--signed-commit`, bound to `needs.build.outputs.commit`.

The mirror-only suite adds the exact-string `if: ${{ !inputs.mirror_only }}` assert on the step.

## Acceptance Criteria

### Pre-merge

- [ ] **AC1** `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` passes. B1–B11 (plus B7a),
      I1–I9 and S1–S8 are all present, and `MIN_ASSERTIONS` is raised by the number of assertions added.
- [ ] **AC2** `bash apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh` passes, and still
      asserts exactly the jobs `build` + `bump-cloud-init-pin`.
- [ ] **AC3** Each of these mutations was applied once locally and drove its suite RED, with the failing
      assertion for each recorded in the PR body: Guard 1 row 2 (REORDER), Guard 2 row 2 (argument
      reversal), Guard 2 row 6 (REORDER) and Guard 2 row 7 (inversion).
- [ ] **AC4** `bash .github/scripts/test/run-all.sh`,
      `bash .github/scripts/test/test-inngest-bootstrap-tag-guard.sh` and
      `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` pass. AC6 and GuardA are green,
      `cloud-init-inngest-bootstrap.test.sh` is unmodified, and `test-inngest-bootstrap-tag-guard.sh`
      differs only in its corrected header comment. *Amended at review:* `cloud-init-inngest-bootstrap.test.sh`
      gained only an AC6 DRIFT-branch diagnostic (an off-main semver-max tag prints the #8747
      recovery instead of "bump to it"); no assertion changed and its count stays 230.
- [ ] **AC5** ADR-232 carries §7, `ancestry` in §6, the rewritten Context/§2/Consequences passages, the
      amendment note and two Alternatives rows. The bump script header's stage list includes `ancestry`.
- [ ] **AC6** `inngest-server.md` §Bootstrap-image release says the tag goes on the squash-merge commit
      on `main` after merge, that a PR-branch tag is refused (with the delete command), and describes the
      carrier-changing PR flow.
- [ ] **AC7** The `model.c4` edge clause is added, and these are green: `c4-count-parity.test.sh`,
      `c4-model-freshness.test.sh`, `c4-code-syntax.test.ts` and `c4-render.test.ts`.
- [ ] **AC8** Comments are posted on #6766 (including the deadlock warning), on #4326 (with the
      dispatch-from-main shape) and on #8209 (with the environment conflict). #8780, #8781 and #8782 are
      linked from the PR body.

### Post-merge (pipeline-executed, immediately after merge)

- [ ] **AC-P1** `vinngest-v1.1.40` is cut on this PR's squash-merge commit. In its run, the inline step
      prints `verdict=on-main`, and the bump job reports `result=opened` with auto-merge armed. Auto-merge
      arms only when the run reports `mirror_status=ok`. A `degraded` mirror leaves a held PR, which
      must be verified and merged per ADR-232 §5 before AC-P2.
- [ ] **AC-P2** After that bump PR merges, main's pin is `v1.1.40`,
      `git merge-base --is-ancestor "vinngest-v1.1.40^{commit}" origin/main` exits 0, and AC6 and GuardA
      are green on main.

## Plan Review Revisions

v1 → v2 changes, applied from the eng panel (DHH, Kieran, code-simplicity) plus the CTO, spec-flow and
advisor passes:

- **DHH / simplicity, both panels on one scope, so delete over fix.** The `verify-tag-on-main` job, bind
  step, shared helper (with `--expect-commit` / `--allow-off-main`) and gate-job Slack step are replaced
  by one inline step in `build` that judges `HEAD`. That property holds by construction, not by binding.
- **Simplicity (g).** The `TARGET == pinned tag` skip is cut. It covered only the minutes between merge
  and the re-anchor, which AC-P1 now runs immediately.
- **Simplicity (i).** The AC6/GuardA hint echoes are cut. The refusal message and the runbook carry the
  remediation, and `cloud-init-inngest-bootstrap.test.sh` stays untouched.
- **Simplicity (j).** The `model.c4` clause is cut. The edge prose is not falsified, and "no C4 change"
  is backed by the enumeration plus `c4-count-parity`.
- **DHH (5).** Hand-applied mutations are limited to the REORDER, squash-shape and inversion rows (AC3).
- **DHH (1).** The plan now states that the bump gate is the fix and the publish check is
  defence-in-depth.
- **Kieran (on v1).** P1-1 found that the `TARGET == pinned tag` skip was decided from one pin site. The
  cut above dissolves it: v2 always judges `TARGET`, so a partially bumped file set cannot slip through.
  The other findings are folded in:
  - P1-2: the crane stub had no call log (`MOCK_CRANE_LOG` added).
  - P2-5: a shallow fixture needs `file://`.
  - P2-6: AC-P1 is conditional on `mirror_status=ok`.
  - P2-7: the discoverability probe prints a literal.

  P2-4 (bind vs `--expect-commit`) and P2-8 (hint git call) went with the cut mechanisms.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment:** The design is sound, with the bump gate as the real chokepoint.

Folded in:

- `mirror_only` is not refused. Refusing it would permanently strand the 16 legacy off-main versions
  from zot backfill.
- ADR-232 §7 states that the bump check's "main's script" authority holds only while the bump-job YAML
  is unmodified.
- The re-anchor touches no live host.
- #4326 is raised to the planned next PR.
- The lost pre-merge image build is recorded (#8781).

Superseded by plan review: the CTO's "skip when TARGET is already pinned" is covered instead by running
the re-anchor immediately.

Recorded as decision challenges, not folded:

- GuardA as a warning on PRs whose own diff changes a carrier.
- A no-push `docker build` on such PRs.

Spec-flow analysis (Phase 3) also ran. Folded in:

- The offending tag is named when `SIGNED_TAG != TARGET`.
- Every refusal prints the delete command.
- The #6766 deadlock warning.
- The dispatch-from-non-main-ref class, added to #8780.
- The rollback-by-re-cut runbook note.

Residuals, documented rather than fixed:

- A tag re-pointed between two on-main commits.
- A pre-ADR-232 branch can build an inert off-main image.
- A hand-authored pin PR to an off-main tag (see Sharp Edges).

No Product/UX gate applies: no file in Files to Edit is a UI surface (tier NONE).

## Dependencies & Risks

- **Operator workflow change (the largest cost).** Tagging a PR branch, which is how the last 14 of 14
  tags were cut, is now refused. Mitigations: the refusal names the exact delete and re-cut commands, the
  runbook documents the new flow, and #4326 automates it.
- **Longer red window on main after a carrier merge** (merge → manual tag → bump). `main-health-monitor`
  may file `ci/main-broken` during it. The signal is truthful; #4326 removes it.
- **An off-main tag reds AC6 repo-wide until it is deleted** (until #8782 lands). This is loud by
  design.
- **Stale-branch workflow copies.** A tag on a branch forked before this merge runs that branch's YAML,
  which has no publish check. The bump gate still refuses the pin.
- **Conflicts.** #8209 (ADR-241) and #8759 edit adjacent sections; both can only cause rebase conflicts.
- **Post-merge re-anchor.** It publishes a new digest and auto-merges a pin bump. The content is
  identical and no live host changes.

## Sharp Edges

- If the `## User-Brand Impact` section is empty, holds only placeholder text, or omits the threshold,
  the plan fails `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- The build job's checkout is a tag tree and, on the dispatch path, predates any helper. The publish
  step MUST be inline bash, never a call to `.github/scripts/…` (the #4700 exit-127 regression).
- `git merge-base --is-ancestor` returns 1 for "no". Capture it with `|| rc=$?` under `set -uo pipefail`
  (never `-e`), and never collapse 1 and 128.
- Fixture tags must be created the way the incident created them: annotated, on a side-branch commit,
  then squash-merged. A row that only ever tags `main` cannot see the defect.
- Guard 1 row 2 and Guard 2 row 2 are REORDER rows. Each must red on position (crane-stub log / line
  order), not only on the final result.
- Do not hand-edit any `cloud-init*.yml` pin in this PR. The post-merge re-anchor moves the pin through
  the bump bot, and AC6 and GuardA must stay green on this branch.
- **The natural repairs, checked (fail-closed-repair rule).** For a refused tag, the likeliest "unstick"
  moves are:
  - (a) Re-dispatch with `mirror_only`. A refused tag has no GHCR image, so the crane copy fails and
    nothing is pinned.
  - (b) Dispatch from a feature-branch workflow ref. The bump gate still refuses the pin; the build
    itself is tracked in #8780.
  - (c) Hand-author a pin PR to the off-main tag. **No gate in this plan blocks this**: AC6 is satisfied
    and GuardA is advisory. Human review is the control, and #8782 makes that PR's AC6 red. This is
    recorded as a residual, not claimed as covered.
- **Test registration.** `run-all.sh` runs `for t in "$DIR"/test-*.sh`, which feeds the required
  `guard-script-fixture-tests`. The edited bump suite is already in that glob, and
  `infra-validation.yml` path-filters on the workflow file, so the mirror-only suite runs on this PR.
- **Check 10 sandbox and git (resolved at deepen).** The `discoverability_test` runs `git` inside
  preflight's sandbox. `preflight/SKILL.md` Check 10 read-only binds
  `git rev-parse --path-format=absolute --git-common-dir` whenever it lies outside `$REPO_ROOT`, which
  is the linked-worktree case, so `git tag --merged` resolves there. `probe-verb-gate.sh` accepts the
  command (rc 0, measured).
- **The crane stub records no calls today** (`test-bump-inngest-bootstrap-pin.sh`, the `crane` heredoc
  stub). B1 and Guard 1 row 2 depend on a call log, so add `MOCK_CRANE_LOG`:
  - the stub appends `$*` to it;
  - `reset_state` creates it;
  - `run_bump` exports it.
- **Existing rows stay green.** Every pre-existing row seeds tags with `seed_tag` on `main` HEAD after
  `fixture_commit`, so each one passes the ancestry check unchanged (verified in review).
- **A shallow fixture needs `file://`.** `git clone --depth 1 <local path>` ignores the depth for a plain
  path, so B9 must clone `file://<path>`.
- **Fixture constructions that look right but test the wrong branch (verified at deepen).** Each of these
  was measured in a scratch repository:
  - A missing tagged commit fails at `rev-parse` (the "tag not found" arm, B7a), not at `merge-base`.
    To reach the rc-128 arm, delete an intermediate main commit's loose object instead (B7).
  - A same-named branch does NOT shadow a tag: git prefers the tag and warns about the ambiguity. Only
    `refs/vinngest-vX.Y.Z` shadows the bare name (B8).
  - A depth-1 clone fetches only the tags on HEAD, and a shallow repo cannot push. So B9 must put the
    semver-max tag on main's HEAD and rely on the empty-crane-log assert to catch the mutation.
- **Old main commit residual.** A tag cut on an old main commit, for example one whose code was later
  reverted, passes both checks and auto-merges if it is semver-max. Ancestry proves "was reviewed", not
  "is current". GuardA on main still reds the content drift. This is recorded in ADR-232 §7.
