---
title: "chore(#7071): residual items - regenerate release notes on the orphaned-draft self-heal publish"
type: fix
date: 2026-10-12
slug: fix-release-self-heal-regenerate-draft-notes
branch: feat-one-shot-7079-release-draft-notes
issue: 7079
closes: none
ref: 7079
priority: p3
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix: regenerate release notes on the orphaned-draft self-heal publish (#7079 item 3)

PR body contract: `Ref #7079` (never `Closes` - the issue stays open until its owner closes it),
a `## Changelog` section, and the already-done / not-fixed-alone rationale below.

## Enhancement Summary

**Deepened on:** 2026-10-12
**Sections enhanced:** 4 (Research Insights, Observability, Phase 2.2 literals, Risks)
**Research agents used:** none spawned beyond the plan-phase learnings researcher, the CTO rulings and the four plan-review agents; deepen-plan ran its halt gates and live verifications inline, because every remaining claim was checkable with one command against this repo or one upstream file.

### Halt gates (all passed)

| Gate | Result |
|---|---|
| 4.6 User-Brand Impact | present; threshold `none`; sensitive-path scope-out bullet present (the file matches via the `release` token) |
| 4.7 Observability | five fields present, none placeholder; `command` starts with `grep`, has no shell-active character and no ssh; finishes in milliseconds; block is NEW so the `expected_output` literal rule binds: changed to the single token `notes_regenerated` (see below) |
| 4.8 PAT-shaped variable | no match |
| 4.9 UI wireframe | not a UI surface; skipped |
| 4.10 Encryption posture | no store, no new connection, no matching file; skipped |
| 4.11 Guard Contract | `scripts/lint-guard-contract.py` green; assembly names the single chokepoint and the three input axes, not today's members |
| 4.12 Scope Check | exactly one unfenced section; three sub-sections; no `unmapped`; no `status: BLOCKED`; Split Assessment carries `Recommendation:` |
| 4.4 / 4.55 | no SQL, no scheduled job, no downtime-class operation |

### Live verifications

- **One-call claim (the plan's one gh-wire assumption).** Fetched `https://raw.githubusercontent.com/cli/cli/trunk/pkg/cmd/release/edit/edit.go` on 2026-10-12: `getParams(opts)` builds ONE map (`params["body"] = opts.Body`, `params["draft"] = *opts.Draft`), the `--notes-file` content is read in `RunE` via `cmdutil.ReadFile` into `opts.Body`, and `editRelease(httpClient, baseRepo, release.DatabaseID, params)` is called once. `editRelease`'s own body was not in the fetched text, so "that call is one PATCH" rests on the name and on the CTO ruling; the unit rows pin the single gh INVOCATION, which is the part this repo controls. `gh release edit --help` (gh 2.102.0) lists `-F, --notes-file` and `--draft` on the one subcommand.
- **Citations.** #7079 OPEN; #7071 MERGED; #10016 MERGED (`76da243c20` is a commit and an ancestor of `origin/main`); #7258, #4902, #7256 CLOSED; #9892 MERGED; #10157 OPEN draft. Rule id `cq-write-failing-tests-before` is active in `AGENTS.md`. Every `knowledge-base/` path in this plan resolves (checked with the sharp-edge grep).
- **Exit-code claim.** The planned block was run mentally and by the correctness reviewer under `bash -e` and `bash -eo pipefail`: `grep -q` inside an `if` condition cannot trip errexit on a non-match, an empty file or a missing file.
- **Probe dry run (sharp edge: run every prescribed command).** `gh release view <tag> --json body,isDraft` returned a body for the newest tag; a draft `web-v0.340.3` was visible in `gh release list` at planning time, confirming orphan drafts do occur here. `grep -oF notes_regenerated .github/workflows/reusable-release.yml` is intentionally empty until Phase 2 lands (it names a string introduced by this PR).

### Key improvements

1. The discoverability literal changed from a multi-word phrase to the single token `notes_regenerated`, so it passes both Check 10's substring match and the deepen-plan prose-detector; the log line now reads `notes_regenerated=true`.
2. The gh single-call claim moved from "assumed" to "verified against upstream source, with the one residual caveat named".
3. All halt gates and citation checks are recorded here so the work phase does not repeat them.

### New considerations discovered

- A currently orphaned draft (`web-v0.340.3`) exists on the repo; the self-heal and this notes fix would apply to it only if a same-tag run recomputes it. This PR does not touch it and must not (no release mutation in a planning or CI-workflow PR).
- Rows b and c of T8 can only go RED through the warning literal (the old block already issues a plain `--draft=false`), which Phase 1.4 states.

## Overview

#7079 consolidates three deferred items from #7071 (zot mirror fail-closed). Only item 3 is still
open work: the orphan-draft / stale-release-notes leak in `.github/workflows/reusable-release.yml`.

The self-heal added in #4902 republishes an orphaned draft when a later run recomputes the identical
tag, but the `Finalise release (publish draft)` step runs a bare `gh release edit "$TAG"
--draft=false`, so the republished release carries the FIRST attempt's changelog. Meanwhile the
current run has already regenerated the notes file (the changelog step is gated only on
`exists == 'false'`, which is true on the draft path) and the Slack announcer reads that file - so
today the GitHub Release page and the Slack announcement of the very same release can disagree.

The fix, already ruled by the CTO (2026-10-12; do not re-litigate): in the Finalise step, when an
orphaned draft is being published, pass the regenerated notes in the SAME `gh release edit` call
that publishes it. No reaper.

### Already done on main (no work in this PR)

| #7079 item | State on `origin/main` (verified 2026-10-12) |
|---|---|
| 2. `zot-entry-gate.sh` wire-or-delete | Done. The script and its test were deleted by merged #10016 (`76da243c20`, "delete the superseded zot-entry-gate.sh (#7258 Step B)"); `ls scripts/ apps/web-platform/infra/` finds no `zot-entry-gate*`. |
| 1. Two false `/v2/` gates in `cloud-init.yml` (cited lines 527 and 733) | Gone. `git grep '/v2/' origin/main -- apps/web-platform/infra/cloud-init.yml` is empty: the GHCR boot legs were retired. |

### Not fixed alone: the one surviving same-family probe

`apps/web-platform/infra/cloud-init-registry.yml` ~line 2618 (zot readiness loop:
`curl -s -o /dev/null "http://localhost:5000/v2/"`) is the same false-gate shape. CTO ruling
2026-10-12: NOT worth fixing alone - nothing consumes the loop result, the 60s liveness heartbeat
already checks 200/401, and any `user_data` byte change forces a registry host destroy-recreate.
Fix it as a free rider if `user_data` is edited for another reason. This PR does NOT touch
`cloud-init-registry.yml`. The rationale goes in the PR body.

## Research Reconciliation - Spec vs. Codebase

| Claim (issue #7079 / brief) | Reality (verified on this branch at `origin/main` 41b8801ad8) | Plan response |
|---|---|---|
| "the override input's description already mentions it" (same-bump constraint) | False. `reusable-release.yml` `bump_type` says only "Override bump type (empty = use PR labels)"; the two dispatch inputs in `version-bump-and-release.yml` and `web-platform-release.yml` do not mention it either. | Append the one-line constraint to the reusable input description (optional item, ruled yes). The callers' choice-input descriptions are left alone (out of scope; the reusable description is what the brief names). |
| "the notes file is populated there" (changelog step gated on `exists == 'false'`) | True: changelog step `if` is `changed == 'true' && exists == 'false'`, and an orphaned draft yields `exists=false, draft_exists=true`. `echo "$CHANGELOG" > "$RELEASE_NOTES_FILE"` always writes at least a newline, and with a resolved PR the `- $PR_TITLE` fallback makes the content non-blank, so a blank file is unreachable today (plan review, 2026-10-12). The real risk is the no-PR paths: `workflow_dispatch` / the `give_up` path carry a low-information fallback (`- Manual version bump`, a bare commit subject, or an empty subject yielding a bare dash). | Gate on a resolved PR number (CTO ruling row 3, Option B) AND keep the non-blank test as one cheap defence-in-depth clause, with the invariant stated inline next to it; otherwise publish with plain `--draft=false`. |
| Brief: Finalise step ~1515-1525, self-heal comment ~1508-1514, idempotency comment ~335-342, bump_type ~30-31 | All four confirmed at those lines (Finalise `run:` is line 1524; comment block 1508-1514; idempotency comment 335-342; description line 31). | Edit in place. |
| Re-run semantics: a retry recomputes the same tag | Only for GitHub's "Re-run failed jobs" (preserves the push event, so `Find merged PR` resolves the same PR). A fresh `workflow_dispatch` short-circuits to no PR and a default `patch` bump (documented at ~1047-1055). | The notes overwrite fires only when `PR_NUMBER` is non-empty, so a dispatch republish keeps the draft's existing notes (today's behavior) instead of overwriting real notes with "Manual version bump". |

## Research Insights

**Premise Validation (Phase 0.6).** Checked #7079 (OPEN, no closing PR), item 2's script
(absent on `origin/main`, deleted by #10016), item 1's cited file (`/v2/` gates absent from
`cloud-init.yml`), the surviving probe (present at `cloud-init-registry.yml` ~2618, behavior as
described), and the four line anchors in `reusable-release.yml` (all hold). No ADR in
`knowledge-base/engineering/architecture/decisions/` governs release-note regeneration; ADR-096/166
concern the zot registry, not this step. The proposed mechanism (single `gh release edit`) is not in
any rejected-alternatives table.

**Property List (Phase 0.6b).**

1. A republished orphaned draft describes the merge that publishes it, not the first attempt's merge. (Known limit: when a LATER, different merge recomputes the same tag, the release holds both merges' code but the page describes only the latest; neither today's behavior nor this one is complete, and the CTO ruled for overwrite. Stated in the comment and the PR body.)
2. Notes replacement and publish are one atomic API call (no window with new notes on a still-draft
   release, or a published release with stale notes).
3. A blank, missing, or non-PR-derived notes file never replaces existing notes, and never fails or
   blocks the publish (publishing matters more than the notes; a hard failure would re-orphan the draft).
4. The non-self-heal path (new draft created this run, and the already-published path) is unchanged.
5. The operator can see where the "different bump orphans the prior draft" constraint lives.
6. The behavior is pinned by a test that fails when any of properties 1-4 regresses.

**Cut List.**

| Mechanism | Property it would buy | Disposition |
|---|---|---|
| A reaper for orphaned drafts | Cleanup of drafts orphaned by a different-bump retry | CUT (CTO: new scheduled object with its own failure modes for a cosmetic leak). Constraint is documented instead (property 5). |
| `gh release view --json body` probe to compare notes before overwriting | Avoid clobbering "good" notes | CUT (CTO: extra API call and failure mode); the `PR_NUMBER` gate buys the same property from data already in the job. |
| Second `gh release edit --notes-file` call before the publish call | Property 1 | CUT: not atomic (property 2). Single call instead. |
| Fixing `cloud-init-registry.yml` ~2618 | Same-family false gate | CUT (CTO ruling above). |

**Institutional learnings applied** (learnings-researcher, 2026-10-12):

- `knowledge-base/project/learnings/bug-fixes/2026-06-03-draft-release-creates-no-tag-idempotency-must-be-draft-aware.md` - origin of the self-heal; `gh release edit --draft=false` is idempotent; the idempotency suite extracts real run blocks and runs them under a `gh` stub.
- `knowledge-base/project/learnings/2026-09-28-this-repos-releases-are-immutable-and-my-stub-could-not-know.md` - releases here are immutable once published (assets 422), so notes must ride the same call that publishes; a draft is mutable, so editing notes while publishing is safe. Route stub argv by position and refuse arguments the code must not send.
- `knowledge-base/project/learnings/2026-06-09-no-test-asserts-X-must-grep-workflow-step-names-in-ci-test-sh.md` - before editing a workflow step, `git grep` the literal in `*.test.sh`; run the sibling suite explicitly.
- `knowledge-base/project/learnings/2026-03-19-github-actions-env-indirection-for-context-values.md` - pass context values through `env:`, quote in shell.
- `knowledge-base/project/learnings/2026-10-09-my-gate-pins-were-green-and-left-position-wiring-and-the-request-itself-unpinned.md` - pin wiring (env values, referenced step ids resolve) and request argv, not only `if:` text.
- `knowledge-base/project/learnings/2026-06-02-auto-merge-livelock-fast-moving-main.md` and `knowledge-base/project/learnings/workflow-issues/merge-queue-ejections-two-causes-and-fix-pr-guard-survivors-20261005.md` - batch pushes; mutate the new guard before shipping.
- Gap: no learning covers `gh release edit --notes-file --draft=false` semantics. `gh release edit --help` (gh 2.102.0, run on this branch 2026-10-12) lists `-F, --notes-file file` and `--draft`; the PATCH is one request. Precedent plan for the sibling change to this very file and suite: `knowledge-base/project/plans/archive/20261009-224857-2026-10-09-fix-slack-on-blocked-release-plan.md` (cite by archived path).

**Open code-review overlap:** see the section below (none).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (limit 200) bodies were searched for
`.github/workflows/reusable-release.yml` and `plugins/soleur/test/reusable-release-idempotency.test.sh`;
zero matches.

## User-Brand Impact

- **If this lands broken, the user experiences:** the public GitHub Release page for a component
  shows a blank or wrong changelog, or (worst case) a self-heal run fails at the Finalise step and the
  release stays an unpublished draft - the very leak being fixed. No product runtime, no customer
  data path.
- **If this leaks, the user's data is exposed via:** nothing new. The notes text is the PR's
  `## Changelog` section, which is already published on the release and sent to Slack today; no new
  secret, token scope, or egress is introduced (`GH_TOKEN` already has `contents: write` in this job).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** none, not `aggregate pattern`: the worst outcome is a
  cosmetic wrong changelog on an internal-cadence release page, fully reversible by a later
  `gh release edit --notes-file`, and the guard degrades to today's behavior rather than to a failure.

threshold: none, reason: `.github/workflows/reusable-release.yml` matches the sensitive-path regex only through the `release` filename token; the change touches no credential, token scope, deploy target or user data - it only chooses which already-public changelog text rides an existing publish call.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "regenerate the release notes on the self-heal publish of an orphaned draft" | Phase 2 step 2.2 (Finalise `run:`) | mapped |
| 2 | "add `RELEASE_NOTES_FILE: ${{ steps.tmpfiles.outputs.release_notes }}` and `DRAFT_EXISTS: ${{ steps.idempotency.outputs.draft_exists }}` to env" | Phase 2 step 2.1 | mapped |
| 3 | "When DRAFT_EXISTS=true, run `gh release edit \"$TAG\" --notes-file \"$RELEASE_NOTES_FILE\" --draft=false` in a single call (notes and publish atomic); otherwise keep the plain `--draft=false`" | Phase 2 step 2.2; AC3, AC4 | mapped |
| 4 | "Update the self-heal comment block (~1508-1514)" | Phase 2 step 2.3 | mapped |
| 5 | "if it could be empty, guard so an empty file never blanks the notes" | Phase 2 step 2.2 (blank guard, defence in depth: unreachable with a resolved PR); Research Reconciliation row 2 | mapped |
| 6 | "Idempotency step comment (~335-342): add one line saying the draft's notes are overwritten at publish from the current run's PR" | Phase 2 step 2.4 | mapped |
| 7 | "Optionally append \"(a retry with a different bump orphans the prior draft)\" to the bump_type input description" | Phase 2 step 2.5 | mapped |
| 8 | "No reaper." | Cut List row 1 | mapped |
| 9 | "Add or extend a test pinning the new behavior if the repo has a release-workflow test suite" | Phase 1 (T8 four rows, T8b wiring in `reusable-release-idempotency.test.sh`) | mapped |
| 10 | "mind the workflow byte budget gates for workflow files" | AC8 (`workflow-file-size.test.ts`; file is 122,278 bytes against the 490,000 gate) | mapped |
| 11 | "ALREADY DONE on main (state this in the plan and PR body, do no work on it)" | Overview, "Already done on main" table; AC9 | mapped |
| 12 | "do NOT touch cloud-init-registry.yml" | Overview "Not fixed alone"; AC10 | mapped |
| 13 | "Use `Ref #7079` in the PR body, not Closes, and include a ## Changelog section" | Phase 5 (PR body); AC11 | mapped |
| 14 | "re-check ratchet BASELINE_DECLARED_PROBES against origin/main before the final push (65 at last report)" | Phase 5 step 5.2; AC12 | mapped |
| 15 | "Rebase onto origin/main, never merge main; main has a merge queue, so once the PR is armed do not push syncs while it is queued" | Phase 5 step 5.3 | mapped |
| 16 | "record `Ruled by CTO agent, <date>: <decision> - <rationale>` in the branch's `decision-challenges.md`" | `specs/feat-one-shot-7079-release-draft-notes/decision-challenges.md` (4 rows written during planning) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `reusable-release.yml` Finalise env + run + comment (2.1-2.3) | asks 1-5 | asked |
| `reusable-release.yml` idempotency comment (2.4) | "Idempotency step comment (~335-342): add one line" | asked |
| `reusable-release.yml` bump_type description (2.5) | "Optionally append" | asked |
| `PR_NUMBER` env + `-n "$PR_NUMBER"` condition (2.1, 2.2) | - | ruled, not asked - CTO ruling row 3 (decision-challenges.md): without it a workflow_dispatch or `give_up` republish would overwrite a real PR-derived changelog with "- Manual version bump", a regression versus today. Cost: one env line, one condition. |
| `::warning::` + plain-publish fallback instead of failing (2.2) | - | ruled, not asked - CTO ruling row 3 (never fail the step: a hard failure would re-orphan the draft); also the observability signal for the no-PR path |
| `idempotency.test.sh` T8/T8b + `MIN_ASSERTIONS` bump (Phase 1) | "Add or extend a test pinning the new behavior" | asked; the floor bump is inferred - justification: the suite's own anti-vacuity contract says to ratchet `MIN_ASSERTIONS` in the same commit as any added assertion |
| Mutation proof against a COPY via `REUSABLE_RELEASE_WF` (Phase 3) | "Add or extend a test pinning the new behavior" | inferred - justification: the plan carries a Guard Contract (blank-notes guard); precedent in the archived #7256 plan Phase 3; run at build time, one-line result in the PR |
| decision-challenges.md rows | ask 16 | asked |

### Split Assessment

- Subsystems touched: 2 - `.github/workflows/`, `plugins/soleur/test/`
- Planned files: 2 edited (plus plan / tasks / decision-challenges artifacts) | Estimated changed lines: ~130 (workflow ~35, test ~95)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Observability

Required because `reusable-release.yml` matches the canonical sensitive-path regex (preflight Check 10 is path-gated on it). The step runs on a GitHub-hosted runner; the signals live in the Actions run, not on a host.

```yaml
liveness_signal:
  what: the Finalise step's stdout line "Published release <tag> (notes_regenerated=true, from this run's PR #<n>)" on every orphaned-draft self-heal publish, and "Published release <tag>" otherwise
  cadence: per release run (every merge to main that triggers a release lane)
  alert_target: GitHub Actions run log for the release job; a failed Finalise step pages through the existing "Post to Slack (release BLOCKED)" and "Email notification (release FAILED)" steps
  configured_in: .github/workflows/reusable-release.yml (Finalise release (publish draft) step; BLOCKED notifier gate pinned by plugins/soleur/test/reusable-release-idempotency.test.sh T6b)

error_reporting:
  destination: GitHub Actions annotations on the release run, plus the existing BLOCKED Slack notifier and failure email for a failed step
  fail_loud: gh exits non-zero -> step fails -> release stays an unpublished draft -> BLOCKED notifier fires (gate: !cancelled() && failure() && release in flight)

failure_modes:
  - mode: gh release edit fails on the combined call (API error, permission)
    detection: step exit code; failure() in the notifier gates
    alert_route: Post to Slack (release BLOCKED) and Email notification (release FAILED)
  - mode: notes file blank, missing, or no PR number resolved (workflow_dispatch or give_up path)
    detection: "::warning::Orphaned draft <tag> published with its EXISTING notes" annotation on the run
    alert_route: Actions annotation only; deliberately not paged (cosmetic, publish still succeeds)
  - mode: regression that drops --notes-file from the combined call or the DRAFT_EXISTS gate
    detection: reusable-release-idempotency.test.sh T8/T8b run in the repo test battery on every PR
    alert_route: CI failure on the PR (pre-merge)

logs:
  where: GitHub Actions run logs for the release job (workflow reusable-release.yml)
  retention: GitHub default Actions log retention for this repository

discoverability_test:
  command: grep -oF notes_regenerated .github/workflows/reusable-release.yml
  expected_output: notes_regenerated
```

Why the probe literal is one token: Check 10 substring-matches `expected_output` tokens against stdout,
and the deepen-plan 4.7 detector rejects an `expected_output` whose every token contains whitespace
(a multi-word phrase reads as prose). `notes_regenerated` is a single token the Finalise log line and
the test both carry; the command prints one line per occurrence and finishes in milliseconds, with no
shell-active characters and no ssh. It names a string that exists in THIS PR's tree after Phase 2.

## Implementation Phases

### Phase 1 - Tests first (RED) - `plugins/soleur/test/reusable-release-idempotency.test.sh`

Per `cq-write-failing-tests-before`: add T8/T8b BEFORE the workflow edit and confirm they are RED
against the unmodified workflow.

1.1 **T8 (behavioral).** Read the real `Finalise release (publish draft)` run block with the parsed
helper `wf_step_field "Finalise release (publish draft)" run` (as T7b does; it drops the trailing
comment block that `extract_run_block` would carry). Run it under the existing `gh` stub with env
`TAG`, `DRAFT_EXISTS`, `PR_NUMBER`, `RELEASE_NOTES_FILE`, `GH_TRACE`, in `bash -eo pipefail` (CI's
default for a step without `shell:` is `bash -e`; the suite's `-eo pipefail` is a stricter superset,
as in T7/T7b).

**Stub change (needed to see quoting).** The stub's `edit` branch records `edit "$*"`, which
flattens argv, so a dropped quote around a path with a space is invisible. Extend the stub to ALSO
write one argument per line to a second file (`$GH_ARGV`), leaving `$GH_TRACE` unchanged for any
existing reader. The trace line today reads `edit release edit <tag> ...` (the stub's `$*` includes
`release edit`); assert on the per-line argv file instead, by position: argv is exactly
`release edit <tag> --notes-file <path> --draft=false` (row a) or `release edit <tag> --draft=false`
(all others), and the `edit` call count (`grep -c '^edit '` on the trace) is exactly 1.

Rows. Each asserts argv AND stdout/warning in ONE comparison (a row that asserts argv alone would be
GREEN against the unmodified workflow for the negative arms, because the old block already issues a
plain `--draft=false`; those rows go RED only through the warning/log literal, which is why it is part
of the same assertion):

| # | DRAFT_EXISTS | PR_NUMBER | Notes file | Expected argv | Expected stdout |
|---|---|---|---|---|---|
| a | true | 123 | real changelog (multi-line, directory name contains a space) | one `edit`: `<tag> --notes-file <exact path> --draft=false` | contains "notes_regenerated=true"; no `::warning::` |
| b | true | (empty) | real changelog | one `edit`: `<tag> --draft=false` | `::warning::` containing "EXISTING notes" |
| c | true | 123 | each of: whitespace-only, zero bytes, missing (one parametrized loop, one assertion block) | one `edit`: `<tag> --draft=false` | `::warning::` containing "EXISTING notes"; rc 0 |
| d | false | 123 | real changelog | one `edit`: `<tag> --draft=false` | no `::warning::`, no "regenerated" (new-draft and normal path unchanged; `PR_NUMBER` cannot matter when `DRAFT_EXISTS=false`, so no separate empty-PR row) |

Row a is the positive control for every negative row: each of b, c, d differs from it in exactly one
dimension (`PR_NUMBER`, the notes file, `DRAFT_EXISTS`), so a change that rejects everything fails
row a and a change that accepts everything fails b, c or d.

1.2 **T8b (wiring, parsed workflow via the existing `wf_step_field` / `wf_ref_check` helpers - place
the section AFTER their definition in T6b, at the end of the T7b section).** Assert for the Finalise
step: each wiring literal (`DRAFT_EXISTS=${{ steps.idempotency.outputs.draft_exists }}`,
`PR_NUMBER=${{ steps.pr.outputs.number }}`, `RELEASE_NOTES_FILE=${{ steps.tmpfiles.outputs.release_notes }}`),
and the FULL `wf_ref_check` string `refs=check_changed,create_release,idempotency,pr,tmpfiles,version;unresolved=`
(matching the T6b pattern, so a drifted `refs=` set also fails). No exact-env-key-set assertion and no
`shell:` assertion (they restate the code and break on any future legitimate env addition; a dropped
env line is already caught by its wiring literal). The existing "Finalise gate == in-flight
predicate" assertion (T6b) must stay green untouched.

1.3 **Anti-vacuity.** `MIN_ASSERTIONS` is currently 77 and the suite currently passes 77/77
(measured on this branch); raise it to `77 + <number of assertions T8/T8b add>` in the same commit
(compute from a real run, do not estimate). T8 must itself assert the run block read from the
workflow is non-empty and contains `gh release edit` (own-dispatch row).

1.4 Run the suite against the UNMODIFIED workflow; T8 rows a, b, c and the T8b wiring rows must be
RED (b and c through the warning literal); row d and every pre-existing assertion GREEN.

### Phase 2 - Workflow edits - `.github/workflows/reusable-release.yml`

2.1 Finalise step `env:` gains (appended after `TAG`, same style):
`RELEASE_NOTES_FILE: ${{ steps.tmpfiles.outputs.release_notes }}`,
`DRAFT_EXISTS: ${{ steps.idempotency.outputs.draft_exists }}`,
`PR_NUMBER: ${{ steps.pr.outputs.number }}`.

2.2 Finalise `run:` becomes (shape; implementer finalises wording, keeping the two literals the tests
pin - "notes_regenerated=true" and "EXISTING notes"):

```bash
# One call: the regenerated notes and the publish are atomic. Only on the self-heal path,
# only with a real PR-derived changelog (a resolved PR number AND non-blank notes).
# Invariant this relies on: with a resolved PR the changelog step always writes a non-blank
# file (its `- $PR_TITLE` fallback); the blank test is defence in depth against that changing.
if [ "$DRAFT_EXISTS" = "true" ] && [ -n "$PR_NUMBER" ] && grep -q '[^[:space:]]' "$RELEASE_NOTES_FILE"; then
  gh release edit "$TAG" --notes-file "$RELEASE_NOTES_FILE" --draft=false
  echo "Published release $TAG (notes_regenerated=true, from this run's PR #$PR_NUMBER)"
else
  if [ "$DRAFT_EXISTS" = "true" ]; then
    echo "::warning::Orphaned draft $TAG published with its EXISTING notes: this run resolved no PR (workflow_dispatch / give_up) or produced a blank changelog."
  fi
  gh release edit "$TAG" --draft=false
  echo "Published release $TAG"
fi
```

Constraints: explicit `if`/`else` (no `cond && x || y`, shellcheck SC2015 and the repo's errexit
lint); `grep -q` reads a file inside an `if` condition, so a non-match, an empty file and a missing
file are branches, not errexit (a missing file also prints grep's own stderr line, deliberately left
visible); the blank branch never fails the step (publishing matters more than the notes - a hard
failure would re-orphan the draft). `$RELEASE_NOTES_FILE` is always double-quoted (row a's
space-containing path and the per-line argv file pin this). The two literals the tests pin
("notes_regenerated=true", "EXISTING notes") are owned by the tests: an implementer who
rewords them edits the tests and the discoverability probe in the same commit.

2.3 Update the self-heal comment block above the step (the one starting `Self-heal gate (#4902)`),
a few lines, written ONCE here: on the orphaned-draft path the step publishes AND overwrites the
draft's notes with this run's regenerated changelog in one call (atomic); it is gated on a resolved
PR and non-blank content; on the no-PR paths (workflow_dispatch, give_up) the draft's existing notes
are kept. State the known limit plainly: when a LATER, different merge recomputes the same tag the
Release page describes only that latest merge (the release contains both merges' code); do NOT claim
the Release page and the Slack announcement always agree (on the no-PR paths the Slack message still
carries the fallback text, pre-existing). Keep "we only flip draft->published here, never upload to a
published (immutable) release."

2.4 Idempotency step comment (the block starting `exists=true ONLY when the release is already PUBLISHED`): add one line pointing at the Finalise
comment - the draft's notes are overwritten at publish from the current run's PR, so a same-tag republish describes the latest merge.

2.5 `bump_type` description (the `bump_type:` input under `workflow_call`): `"Override bump type (empty = use PR labels; a retry with a
different bump orphans the prior draft)"`. Verify no test or tooling pins the old string:
`git grep -nF "Override bump type" -- . ':!knowledge-base'`.

### Phase 3 - Mutation proof (against a COPY via `REUSABLE_RELEASE_WF=<copy>`; the tracked file is never edited; the variable is unset for the real run)

Run each Guard Contract mutation on a fresh copy of the finished workflow (or, for the harness rows,
of the suite) and require the suite RED (rc != 0), and the must-PASS row GREEN. Do this while
building; the PR body carries a one-line result ("N mutations RED, 1 must-PASS GREEN"), not a table.
Restore nothing (copies are temp).

### Phase 4 - Gates (run only these; do not run the broad battery)

- `bash plugins/soleur/test/reusable-release-idempotency.test.sh` (REUSABLE_RELEASE_WF unset) green.
- `actionlint .github/workflows/reusable-release.yml` - nothing new versus `origin/main`.
- `python3 scripts/lint-workflow-step-env-refs.py` (new env refs resolve) and the errexit lint
  `scripts/lint-workflow-errexit-capture.py` over the file.
- `shellcheck` over the extracted Finalise block.
- `bun test plugins/soleur/test/workflow-file-size.test.ts` (file stays far under the 490,000-byte gate).
- `git grep -nF "Finalise release (publish draft)" -- '*.test.sh' 'plugins/**/test/**'` - any other
  suite asserting on this step is run explicitly (learning 2026-06-09).

### Phase 5 - Ship hygiene

5.1 PR body: `Ref #7079` (not `Closes`), `## Changelog` (one line: release workflow republishes an
orphaned draft with the current run's notes), the "Already done on main" table, the "Not fixed
alone" rationale, the four decision rows, the one-line mutation-proof result. Label per the repo's semver
rule for a CI-only change (ship decides).

5.2 **Standing check (AC12):** immediately before the final push, read the ratchet from the file on
`origin/main` - `git show origin/main:plugins/soleur/test/preflight-discoverability-test.test.ts |
grep -n "BASELINE_DECLARED_PROBES = "` - (65 at planning time, 2026-10-12). This plan declares no
`credentials_required`, so it owes NO bump; a sibling PR bumping it is picked up by the rebase, never
re-typed from this plan (learning `2026-10-12-egress-gateway-single-shot-tcp-probe-raced-squid-bind.md`
item 5: read the value from the file at commit time, not the plan).

5.3 **Merge-queue discipline:** rebase onto `origin/main` (never merge main); batch changes into as
few pushes as possible before arming; once the PR is armed and queued, push no sync/update-branch.

5.4 **Archive:** when archived, cite this plan by its archived path
(under `knowledge-base/project/plans/archive/`, timestamp-prefixed, ending `2026-10-12-fix-release-self-heal-regenerate-draft-notes-plan.md`)
in the PR body and any follow-up.

## Files to Edit

- `.github/workflows/reusable-release.yml` - Finalise step env/run/comment (the `Finalise release (publish draft)` step and the comment above it), the idempotency step's leading comment, the `bump_type` description (content anchors; line numbers drift).
- `plugins/soleur/test/reusable-release-idempotency.test.sh` - `gh` stub argv-per-line recording, T8 behavioral rows, T8b wiring rows, `MIN_ASSERTIONS` ratchet, header comment line.

## Files to Create

- None in product code. Planning artifacts only: this plan, `knowledge-base/project/specs/feat-one-shot-7079-release-draft-notes/tasks.md`, `.../decision-challenges.md`.

## Files NOT to Touch

- `apps/web-platform/infra/cloud-init-registry.yml` (CTO ruling: free-rider only; any `user_data` byte change forces a registry host destroy-recreate).
- `.github/workflows/zot-image-mirror.yml` (its own `gh release edit --draft=false` is a different tag / repo and unrelated).

## Guard Contract

### Guard 1 - Finalise notes-overwrite condition

**Property.** On the orphaned-draft publish, a release's notes are replaced by this run's changelog
only when that changelog is non-blank AND derived from a resolved PR, in the same `gh release edit`
call that publishes it; in every other case the publish proceeds with the notes untouched and the
step does not fail.

**Assembly.** The chokepoint is the single `Finalise release (publish draft)` run block - the only
`gh release edit ... --draft=false` in `reusable-release.yml` (census: `git grep -n "draft=false" --
.github`; the only other hit, `zot-image-mirror.yml:146`, publishes a different artifact). It is
reached from exactly two producers of "draft exists": the `create_release` step (`released == 'true'`,
where `DRAFT_EXISTS` is `false`) and the idempotency step (`draft_exists == 'true'`). Inputs the
condition quantifies over: `DRAFT_EXISTS` in {true,false}, `PR_NUMBER` in {empty, number},
notes file in {real, whitespace-only, zero-byte, missing} (the blank arms are unreachable today while the changelog step keeps its `- $PR_TITLE` fallback, so they are pinned as defence in depth). The Slack announcer reads the same file
but is not a writer and is out of the guard's assembly.

**Mutation matrix:**

| # | Mutation (applied to a COPY of the workflow via `REUSABLE_RELEASE_WF`, or to the suite) | Expected |
|---|---|---|
| 1 | Drop `--notes-file "$RELEASE_NOTES_FILE"` from the combined call (property 1) | RED (T8 row a) |
| 2 | Break atomicity: split into two calls (`--notes-file` call, then `--draft=false` call), or append a SECOND compliant-looking call after the first (e.g. a trailing `--latest`) | RED (T8 call-count assertion: `edit` trace has 2 lines) |
| 3 | Remove the `grep -q '[^[:space:]]'` blank test, or weaken it to a size test (`[ -s ... ]`, which a one-newline file passes) | RED (T8 row c, whitespace-only arm) |
| 4 | Remove the `[ -n "$PR_NUMBER" ]` test (dispatch/give_up overwrite) | RED (T8 row b) |
| 5 | Replace the `DRAFT_EXISTS = "true"` test with an always-true condition (new-draft path now passes `--notes-file`) | RED (T8 row d only; row b/c stay GREEN because the `PR_NUMBER`/blank tests still divert them) |
| 6 | Drop the `DRAFT_EXISTS` env line from the step (condition silently false in CI; unit rows stay green because they set env directly) | RED (T8b `DRAFT_EXISTS` wiring literal) |
| 7 | Unquote `$RELEASE_NOTES_FILE` in the combined call (word-splits a path containing a space) | RED (T8 row a: the per-line argv file shows a split argument) |
| 8 | Own dispatch: rename the step `Finalise release (publish draft)` so the helper reads nothing | RED (T8 asserts the run block is non-empty and contains `gh release edit`; also the pre-existing T4 / T6b step lookups) |
| 9 | Suite edit (harness row): make the `gh` stub's `edit` branch stop recording to `$GH_TRACE` / `$GH_ARGV` | RED (rows a-d see an empty trace; an empty trace must never read as "no `--notes-file` found, pass") |
| 10 | Must-PASS non-canonical (harness row): notes content with CRLF line endings, unicode and a leading blank line (the path with a space is row a's own fixture) | GREEN (still exactly one call with the exact path; the guard permits any non-blank text) |

Order/lifetime row: the property is about WHICH CALL carries the notes, not about a window, so a
reorder row would not discriminate beyond row 2; row 2 observes the call sequence in the trace
(the one place a split would show), not only the final state.

**Anchor.** The guard compares no stored hash or manifest. The one stored number is the suite's
`MIN_ASSERTIONS` floor, raised in the same commit and compared against the live assertion count at
runtime; lowering it is a visible diff to a file the reviewer is already reading, and set identity
is covered by the named rows above (a `>= N` floor alone would survive a substitution that keeps N).

## Acceptance Criteria

<!-- Headless run: no founder-stated check captured (interactive only; see plan-founder-check.md). -->

- [ ] AC1. `plugins/soleur/test/reusable-release-idempotency.test.sh` T8/T8b were observed RED against the unmodified workflow (Phase 1.4) and are GREEN after Phase 2.
- [ ] AC2. `bash plugins/soleur/test/reusable-release-idempotency.test.sh` exits 0 with `REUSABLE_RELEASE_WF` unset; the final line reads `=== Results: N/N passed, 0 failed ===` with N >= the raised `MIN_ASSERTIONS`.
- [ ] AC3. With `DRAFT_EXISTS=true`, a resolved PR and a non-blank notes file, the extracted Finalise block issues exactly one `gh release edit <tag> --notes-file <file> --draft=false` (T8 row a, argv asserted per line so quoting is pinned).
- [ ] AC4. In every other combination (DRAFT_EXISTS false; PR_NUMBER empty; notes blank / zero-byte / missing) it issues exactly one `gh release edit <tag> --draft=false` with no `--notes-file`, exits 0, and emits `::warning::` only on the DRAFT_EXISTS=true variants (T8 rows b-d).
- [ ] AC5. The Finalise step `if:` is unchanged (`GATE_INFLIGHT`, T6b "Finalise gate == in-flight predicate" still green) and its three new env lines carry the wiring literals (T8b).
- [ ] AC6. The self-heal comment block and the idempotency-step comment state the overwrite behavior; the `bump_type` description ends with "(a retry with a different bump orphans the prior draft)". `git grep -nF "orphans the prior draft" -- .github/workflows/reusable-release.yml` returns the description line.
- [ ] AC7. Phase 3 mutations 1-9 each turn the suite RED and 10 stays GREEN; the PR body carries the one-line result.
- [ ] AC8. `actionlint`, `scripts/lint-workflow-step-env-refs.py`, `scripts/lint-workflow-errexit-capture.py` and shellcheck on the extracted block report nothing new versus `origin/main`; `bun test plugins/soleur/test/workflow-file-size.test.ts` passes (`wc -c .github/workflows/reusable-release.yml` stays under 490000; it is 122,278 at planning time).
- [ ] AC9. The PR body states items 1 (the two `cloud-init.yml` gates) and 2 (`zot-entry-gate.sh`) are already resolved on main, with #10016 cited, and does no work on them.
- [ ] AC10. `git diff origin/main...HEAD --name-only` contains neither `apps/web-platform/infra/cloud-init-registry.yml` nor any other `apps/*/infra/` path; the PR body records the "not fixed alone" rationale.
- [ ] AC11. PR body has `Ref #7079` and a `## Changelog` section and does NOT contain `Closes #7079`, `Fixes #7079` or `Resolves #7079`.
- [ ] AC12. Immediately before the final push, `BASELINE_DECLARED_PROBES` was re-read from `origin/main` (65 at planning time) and this PR carries no change to `preflight-discoverability-test.test.ts`.
- [ ] AC13. The branch is rebased on `origin/main` (no merge commits from main) and no sync push occurs after the PR is queued in the merge queue.
- [ ] AC14. `decision-challenges.md` carries the four `| Item | Class | Ruling |` rows with `Ruled by CTO agent, 2026-10-12:` and the plan cites itself by archived path once archived.

## Test Scenarios

All `unit` layer (bash, `gh` stubbed; no live GitHub call, no e2e).

- Given an orphaned draft (`DRAFT_EXISTS=true`), a PR number and a populated notes file, when Finalise runs, then one `gh release edit` carries both `--notes-file` and `--draft=false`.
- Given an orphaned draft from a `workflow_dispatch` run (no PR), when Finalise runs, then the release is published with the draft's existing notes and a warning names why.
- Given an orphaned draft and a whitespace-only / zero-byte / missing notes file, when Finalise runs, then publish succeeds, notes are untouched, rc 0.
- Given a freshly created draft (`DRAFT_EXISTS=false`), when Finalise runs, then behavior is byte-identical to today (plain `--draft=false`).
- Given the workflow's Finalise step, when env wiring is parsed, then every referenced `steps.<id>` is defined and the key set is exactly the five wired keys.

Post-merge verification (not a pre-merge gate; no operator step): the next release run that
self-heals an orphaned draft logs "notes_regenerated=true" and
`gh release view <tag> --json body` shows this run's changelog (learning
`2026-09-18-the-release-run-was-green-and-production-was-still-serving-the-previous-build.md`:
verify the outcome, not the run's conclusion). Orphan drafts are rare, so this is observed
opportunistically rather than scheduled; the unit rows are the pre-merge proof.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - CI workflow / test-suite change on internal release
tooling. The engineering fork (dispatch/give_up overwrite) was ruled by the CTO agent and recorded
in `decision-challenges.md`. No UI surface, no regulated-data surface (the notes text is already
public on the release), no new infrastructure (no Terraform, no `user_data` change, no apply), no
architectural decision (ADR/C4 not applicable: one step's behavior, not a boundary), no persistent
store or new connection (encryption posture not applicable).

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails `deepen-plan` Phase 4.6; this one is filled with threshold `none` plus the scope-out bullet (the file matches the sensitive-path regex via the `release` token).
- T8 reads the block through the parsed `wf_step_field ... run` helper (not the awk `extract_run_block`), and asserts it is non-empty and contains `gh release edit`, so a renamed step or a mis-read is loud.
- CI runs a `run:` without `shell:` as `bash -e`; the suite runs it under `-eo pipefail`, a stricter superset. The blank guard uses `grep -q` against a FILE inside an `if` condition so a non-match is a branch, not an errexit.
- `PR_NUMBER` is empty not only on dispatch but also when the PR lookup `give_up`s; both mean "notes are not a real changelog", so both keep existing notes. A same-run Slack announcement still posts the fallback text there - pre-existing, unchanged.
- Do not stage `tasks.md` by directory; commit the exact plan path (skeleton-sweep hazard).
- **Claim to verify, not assume (deepen-plan):** "one `gh release edit` call is one PATCH carrying both the body and `draft:false`" is a claim about gh's implementation (`pkg/cmd/release/edit/edit.go` in cli/cli builds one params map and issues one `editRelease`). The unit rows pin that THIS step makes one gh invocation; they cannot see gh's wire behavior, because the stub records argv only. `gh release edit --help` (gh 2.102.0) confirms both flags exist on the one subcommand. Cite the source URL when deepen-plan verifies it.
- The `gh` stub replays only argv recording; real `gh release edit` also prints the release URL and exits non-zero on API failure. Row coverage of the failure arm is the existing BLOCKED-notifier suite (T6b), not T8.
- Each negative T8 row differs from positive row a in exactly one dimension (DRAFT_EXISTS, PR_NUMBER, or the notes file), so a regression that rejects everything fails row a, and a regression that accepts everything fails rows b-e (positive control on the same input, per the sharp-edge on negative-row controls).
- The suite is already registered: `scripts/test-all.sh` globs `plugins/soleur/test/*.test.sh`, and this PR adds no new file. The post-merge probe shape below was run once on 2026-10-12 against a live release (`gh release view <tag> --json body,isDraft` returns the body and draft flag).
