---
title: "reusable-release: a blocking zot-mirror failure sends no Slack (implicit success() on the gate)"
type: fix
date: 2026-10-09
slug: slack-on-blocked-release
branch: feat-one-shot-7256-slack-on-blocked-zot-mirror
issue: 7256
closes: 7256
lane: single-domain
---

# fix: a blocked release must also reach Slack (#7256)

## Enhancement Summary

**Deepened on:** 2026-10-09 (proportionate pass: the four-seat plan-review panel already ran; the 40-agent fan-out was deliberately not repeated for a ~250-line CI change on a contended machine)
**Gates run mechanically:** 4.6 User-Brand Impact (pass, `none` with scope-out), 4.7 Observability (five fields present, probe is `grep`, expected output is the literal `1`), 4.8 PAT-shaped variables (none), 4.9 UI wireframe (not applicable), 4.10 encryption posture (not triggered), 4.11 Guard Contract (`scripts/lint-guard-contract.py` green; assembly is derived from the parsed workflow, not listed), 4.12 Scope Check (rewritten into the compliant Ask Mapping / Provenance / Split tables).
**Citations verified live:** #7256 OPEN, #6278 CLOSED, PR 7390 OPEN draft; cited rule ids all exist in `AGENTS.md`; `Post to Slack (release BLOCKED)` is absent on `origin/main` (count 0), so the discoverability probe will read 1 only after the change; `timeout-minutes: 60` exists on the release job (the timeout scenario row is real).

### Key improvements over the first draft
1. The sibling-step decision survived four independent reviews; the success path stays untouched.
2. The test moved from awk plus a hand-rolled expression evaluator to parsed YAML with whole-value equality, a derived census and env-wiring assertions.
3. The message no longer over-claims ("nothing was published" became "the GitHub release was NOT published"), and the registry lines disappear for plugin releases.
4. The web-platform `notify-gated` Slack duplicate is named, accepted and disclosed.

### New considerations discovered
- `mint-inngest-bootstrap-tag.yml` path-triggers on `build-inngest-bootstrap-image.yml`, and `web-platform-release.yml` path-triggers on `plugins/soleur/**` minus `docs/` and `test/`: two docs edits that looked free would have fired a zot push and a web deploy.
- `.github/workflows/reusable-release.yml` matches the sensitive-path regex, so `threshold: none` needs the scope-out line (present).

## Overview

The release notification step in the shared release workflow (`Post to Slack (release)` in `.github/workflows/reusable-release.yml`) carries a plain-expression `if:`, so GitHub ANDs an implicit `success()` into it. Since the zot mirror gate became release-blocking (`degraded()` exits non-zero and the mirror step no longer carries `continue-on-error`), a mirror failure fails the job before that step is evaluated and the step is skipped. The release job's own signal on a blocked release is then the failure email (`Email notification (release FAILED)`, `if: failure()`).

**Decision (technical fork, resolved here per `hr-technical-fork-is-not-an-operator-question`):** add ONE new sibling step, `Post to Slack (release BLOCKED)`, gated `!cancelled() && failure() && <the release-in-flight predicate the success step already uses>`. The success step's `if:`, env and run block stay byte-for-byte untouched, the failure email stays untouched, and the comments that document the old behaviour are rewritten to point at the sibling.

## Research Insights

### Premise Validation (Phase 0.6) — re-derived against the working tree, 2026-10-09

| Premise | Re-derived result |
|---|---|
| #7256 is open | `gh issue view 7256`: `OPEN`, no closing PR. Holds. |
| `Post to Slack (release)` has no status function | Its `if:` is `steps.check_changed.outputs.changed == 'true' && (steps.create_release.outputs.released == 'true' \|\| steps.idempotency.outputs.draft_exists == 'true')`. Holds (implicit `success()`). |
| `cancelled()` occurs zero times in the file | `grep -c 'cancelled()' .github/workflows/reusable-release.yml` prints `0`. Holds. |
| The mirror step is blocking | `id: zot_mirror` has `if: steps.docker_build.outcome == 'success'`, no `continue-on-error`; `degraded()` writes `mirror_status=degraded` and `mirror_reason=<stage>` to `$GITHUB_OUTPUT` and then exits non-zero. Outputs are readable from a later step after the failure. Holds. |
| Step order | `zot_mirror` -> `Tear down cloudflared registry bridge` (`if: always()`) -> `Finalise release (publish draft)` -> `Email notification (release)` -> `Email notification (release FAILED)` (`if: failure()`) -> `Post to Slack (release)` -> output-carrier steps. The draft is CREATED before the mirror step and PUBLISHED by Finalise, so on a mirror block `create_release.outputs.released == 'true'` while the release is still a draft; the existing predicate is the right conjunct. Steps between Finalise and the new step are `continue-on-error`, so `failure()` there means the failure happened at or before Finalise. |
| `build-inngest-bootstrap-image.yml` fixed the same class | Its step is `if: ${{ !cancelled() && steps.zot_mirror.outputs.mirror_status == 'degraded' }}`, degrade-only with no happy-path announcement. The shape does NOT transplant: here a bare `!cancelled() &&` on the existing step would post `released!` for a still-draft release. |
| A single Slack message can carry the reason the email carries | Yes: `steps.zot_mirror.outputs.mirror_reason` and `steps.token_preflight.outputs.verdict` are step outputs, readable after a failure; the new step passes both through `env:`. |
| **"A blocked release reaches ops by email alone" (plan review F1)** | TRUE only for plugin releases and `workflow_dispatch` runs. For a web-platform PUSH release, `web-platform-release.yml` `notify-gated` already posts "Web Platform deploy GATED — prod NOT updated" to the same `SLACK_RELEASES_WEBHOOK_URL` when `skip_reason == 'release_failed'` (set at the in-run and `workflow_run` arms), with no `mirror_reason`; `release-outcome` also emails from the `workflow_run` run. **Decision: keep the new step and accept the web-platform duplicate** (disclosed in the PR body, as FR-A6 disclosed its own widening). It fires earlier (from the failing run itself, not after CI completion), carries the mirror reason `notify-gated` lacks, and is the only Slack signal for plugin and dispatch runs. Gating on `inputs.component` was rejected: it adds a conditional and would silence the dispatch path, where `notify-gated` does not fire. A lead comment above the new step names `notify-gated` so nobody "deduplicates" by deleting one. |

**ADR corpus:** ADR-096's "AMENDED 2026-07-30" bullet states the old behaviour (the Slack step "does not run at all" on a blocked release) — amended in this PR. ADR-166 binds the message: name only what the job measured (see the message contract).

### Property List and Cut List (Phase 0.6b)

1. P1 — a blocked release (job failed, release in flight) produces a Slack message in the releases channel.
2. P2 — a cancelled run produces no message from either release step.
3. P3 — a successful release still produces exactly the existing announcement, condition unchanged.
4. P4 — the failure email still fires.
5. P5 — the blocked message carries the mirror reason and token verdict the email carries, and never claims the release was published.
6. P6 — the gate is pinned by anchored syntax and proven by mutation.

| Mechanism | Property | Disposition |
|---|---|---|
| Edit the existing step to `!cancelled() && …` with a branching message | P1, P2 | CUT for a sibling: touches the hot path of every release and needs a status env to avoid a false `released!`. The sibling keeps P3 trivially. |
| A new composite for the Slack post | P1 | CUT: single consumer; the repo carves out an inline Slack step for the release channel. The boilerplate duplication is accepted (extraction is a later cleanup, not a filing here). |
| A new test file | P6 | CUT: `plugins/soleur/test/reusable-release-idempotency.test.sh` already reads both notify steps and is registered in `scripts/suite-shard-legs.tsv` and `scripts/lib/test-affected-paths.sh`. |
| Numeric anti-vacuity floor on that suite | P6 | CUT: it would enrol the suite in `scripts/guard-vacuity-floor.test.sh`'s derived population. Dispatch-vacuity is bought by an empty lookup being an explicit FAIL. |
| Python truth-table / expression evaluator; normalizer + layout self-test; order assertion; `continue-on-error` mutation row; gate-the-step-by-component | — | CUT at plan review (DHH, simplicity, Kieran agreed): whole-string `if:` equality already pins every property they check; ordering is caught by `actionlint` (`property "zot_mirror" is not defined`); the component gate is rejected above. |
| Edit the stale "Tracked separately (#7256)" comment in `build-inngest-bootstrap-image.yml` | none | CUT, hazard: `mint-inngest-bootstrap-tag.yml` `on.push.paths` lists that file, so any edit fires the auto-mint, a build and a zot push. The comment still names #7256, which this PR closes. |
| Edit the Slack carve-out sentence in `plugins/soleur/skills/ship/references/ci-workflow-authoring.md` | none | CUT, hazard: `web-platform-release.yml` fires on `plugins/soleur/**` except `docs/` and `test/`, so it would build and deploy. The sentence does not state the old behaviour. |
| Append a pointer to the FR-A6 comment above the failure email | none | CUT: the lead comment above the new step carries the email/Slack pairing; a third copy is drift surface. |

### Learnings applied

`2026-08-01-alert-step-and-its-fallback-died-together-guard-fallbacks-with-not-cancelled.md` (a compensating step inheriting `success()` cannot compensate for its subject failing); `2026-07-30-the-guard-i-wrote-for-the-failure-path-could-not-run-on-the-failure-path.md` and `cq-assert-anchor-not-bare-token` (anchor on parsed structure and unambiguous sentinels, never prose a comment or remedy sentence could satisfy); `hr-ship-message-no-operator-checklist` (one remedy sentence).

### Open Code-Review Overlap

None. Open `code-review` issues were queried for `.github/workflows/reusable-release.yml`, `reusable-release-idempotency.test.sh` and `ADR-096-migrate-container-registry`: zero matches.

### Collision note (PR 7390)

Draft PR 7390 edits the Docker build-arg secret handling in `reusable-release.yml` (the middle of the file). This plan's hunks are two comment blocks plus one new step inserted AFTER the existing `Post to Slack (release)` step and BEFORE the "CARRY THIS JOB'S OUTPUT VALUES ACROSS THE RUN BOUNDARY" comment block, i.e. the tail. No shared context lines.

## Problem Statement

On a blocked release (mirror gate failure, or any failure after the draft is created) the release job's only push signal is the failure email; the Slack releases channel is silent, except that a web-platform push release is later announced as "deploy GATED" by a different workflow. The step's own comment documents the silence as intended, which is why it reads as a decision. The brief resolves the fork: Slack should fire too, because #6278 chose Slack as the push channel for mirror problems and the blocked case is the more severe one.

Out of scope, stated so P1 is not over-claimed: a job-level timeout (`timeout-minutes`) ends the job as cancelled, so both the failure email and the new step stay silent on it; `notify-gated` covers web-platform, and a plugin-release timeout remains silent (unchanged).

## Proposed Solution

### 1. New step `Post to Slack (release BLOCKED)` (insert after the success Slack step)

```yaml
      - name: Post to Slack (release BLOCKED)
        if: >-
          !cancelled() && failure() &&
          steps.check_changed.outputs.changed == 'true' &&
          (steps.create_release.outputs.released == 'true' ||
           steps.idempotency.outputs.draft_exists == 'true')
        continue-on-error: true
        env:
          SLACK_RELEASES_WEBHOOK_URL: ${{ secrets.SLACK_RELEASES_WEBHOOK_URL }}
          TAG: ${{ steps.version.outputs.tag }}
          VERSION: ${{ steps.version.outputs.next }}
          COMPONENT_DISPLAY: ${{ inputs.component_display }}
          MIRROR_REASON: ${{ steps.zot_mirror.outputs.mirror_reason }}
          TOKEN_VERDICT: ${{ steps.token_preflight.outputs.verdict }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: |
          (empty webhook -> ::warning:: and exit 0; ::add-mask::; MESSAGE via printf; escape & < > in
           MIRROR_REASON/TOKEN_VERDICT with bash substitutions; payload via
           `jq -n --arg text "$MESSAGE" '{text: $text, unfurl_links: false}'`; the same
           `curl … || echo "000"` and 2xx/::warning:: tail as the success step.)
```

Message contract (ADR-166: state only what the job measured; one remedy sentence):

- Header: `*<COMPONENT_DISPLAY> v<VERSION> release BLOCKED — the GitHub release was NOT published*` (single-asterisk mrkdwn bold). Not "nothing was published": GHCR tags and the image are pushed before the mirror gate (the file already records `docker_pushed: true` on a blocked release).
- Line 2: `The release job failed, so <TAG> was not published (the draft is kept).`
- Registry lines ONLY when `MIRROR_REASON` or `TOKEN_VERDICT` is non-empty (a plugin release builds no image, so both are empty there and the lines would be noise): `zot mirror stage: <reason or "not reached">; registry-push token verdict: <verdict or "unmeasured">`.
- One remedy sentence: `Re-run failed jobs on this run to retry with the same version; a fresh "Run workflow" dispatch recomputes it.`
- Last line: `Run: <RUN_URL>`.
- Never contains `released!` and carries no release-notes body (no `md-to-mrkdwn` path).

Condition rationale: `!cancelled()` is the brief's no-fire-on-cancel (and removes the docs-literal ambiguity of `failure()` = "any previous step failed" on a run cancelled after an earlier failure); `failure()` keeps it off successful runs, where the success step owns the announcement; the release-in-flight predicate is copied verbatim from the success step so a failure BEFORE any draft exists stays email-only; `continue-on-error: true` mirrors the success step (cheap, and the learning's guidance).

### 2. Comment rewrites in `reusable-release.yml` (two blocks plus a lead comment)

| Block (find by anchor, never by line number) | New text must say |
|---|---|
| Success step `env:`, paragraph beginning `CORRECTED 2026-07-30: the original reason given here` — the single authoritative paragraph | This step is deliberately the PUBLISHED-release announcer and keeps its plain `if:` (implicit `success()`): on a blocked release it does not run BY DESIGN; the blocked case is announced by the failure-gated sibling `Post to Slack (release BLOCKED)` (#7256). Reading the OUTPUT stays correct (outputs are set on every path including the override; `outcome` conflates "mirror degraded" with "release blocked"). Mark `CORRECTED 2026-10-09 (#7256)`; keep the 2026-07-30 history to one clause. |
| Success step run block, comment starting `# This branch now means something NARROWER than it used to` — shrink to a pointer | One or two lines: this step does not run on a blocked release; the sibling below does; the only reachable path through this `degraded` branch is the operator override. Delete the sentence "this Slack step carries no status function — so its implicit success() means it does not run at all". |
| Lead comment above the new step (new) | Why a sibling and not an edit of the success step; why `!cancelled() && failure()`; that the failure email is the independent second channel; that web-platform push releases also get `notify-gated`'s "deploy GATED" Slack from `web-platform-release.yml` and the duplicate is deliberate (the reason is only here); #7256. |

### 3. ADR-096 amendment (one short sentence)

In ADR-096's "AMENDED 2026-07-30" bullet, after the clause "the Slack step carries an implicit `success()`, so on a blocked release it does not run at all", add: `AMENDED 2026-10-09 (#7256): a separate failure-gated step, "Post to Slack (release BLOCKED)", now announces a blocked release.` Nothing more; this is not an architectural decision.

## Files to Edit

- `.github/workflows/reusable-release.yml` — new step, the two comment rewrites, the lead comment.
- `plugins/soleur/test/reusable-release-idempotency.test.sh` — new T6b and T7b; `WF` override hook; header mention of #7256.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — the one sentence.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-7256-slack-on-blocked-zot-mirror/tasks.md` (plan artifact only).

## Files NOT to touch (each with its reason)

- `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, `server.tf`, `ci-deploy.sh`, any `deploy_pipeline_fix` trigger file — a registry replace or web-host apply would fire and reset the running 24-hour observation window on the registry host.
- `.github/workflows/build-inngest-bootstrap-image.yml` — path-triggers `mint-inngest-bootstrap-tag.yml` (build and zot push).
- Anything under `plugins/soleur/` except `test/` — `web-platform-release.yml` fires on `plugins/soleur/**` minus `docs/` and `test/` and would build and deploy. (`plugins/soleur/test/` still fires `version-bump-and-release.yml`, which cuts a plugin release through this same reusable workflow: normal for any plugin-tree change, builds no image, touches no registry, and exercises the unchanged success path.)
- No web-1/web-2/git-data host contact; no apply workflow dispatch; no new issues (net-issue-flow).

## Implementation Phases

### Phase 1 — RED: tests first (`cq-write-failing-tests-before`)

In `plugins/soleur/test/reusable-release-idempotency.test.sh` (existing style: `pass`/`fail`/`assert_eq`, `$WF`):

1. `WF="${REUSABLE_RELEASE_WF:-$REPO_ROOT/.github/workflows/reusable-release.yml}"` with a comment that it is a test-only hook so a mutation proof edits a COPY (CI never sets it; the real run must have it unset).
2. One `python3 -I` helper block (PyYAML is already imported by sibling suites such as `workflow-run-deploy-invariants.test.sh` and several `scripts/lint-workflow-*.py`) that `yaml.safe_load`s `$WF`, finds a step by EXACT `name`, and prints a field: `if` (whitespace-collapsed with `" ".join(s.split())`), `env.<KEY>`, `continue-on-error`, `run`; and prints the census (names of steps whose `json.dumps(step)` contains `secrets.SLACK_RELEASES_WEBHOOK_URL`). A missing step, an empty result or a YAML error is an explicit FAIL, never a skip. YAML comments are structurally excluded (an awk extractor would treat a `#` line inside a `>-` block wrongly, and cannot cleanly bound a step).
3. T6b assertions (whole-value `assert_eq`, not substring greps):
   - success gate == `steps.check_changed.outputs.changed == 'true' && (steps.create_release.outputs.released == 'true' || steps.idempotency.outputs.draft_exists == 'true')` (P3, byte-for-byte pin);
   - blocked gate == `"!cancelled() && failure() && "` + the success literal (one literal, derived, so the two cannot drift) (P1, P2);
   - failure-email gate == `failure()` (P4);
   - census == exactly {`Post to Slack (release)`, `Post to Slack (release BLOCKED)`}, and the blocked step's `continue-on-error` is `True`;
   - env wiring (F3 — T7b sets env directly and cannot see a mis-wired `env:` line): blocked `env.MIRROR_REASON == "${{ steps.zot_mirror.outputs.mirror_reason }}"`, `env.TOKEN_VERDICT == "${{ steps.token_preflight.outputs.verdict }}"`, `env.TAG == "${{ steps.version.outputs.tag }}"`, `env.VERSION == "${{ steps.version.outputs.next }}"`, `env.SLACK_RELEASES_WEBHOOK_URL == "${{ secrets.SLACK_RELEASES_WEBHOOK_URL }}"`.
4. T7b: take `run` from the parsed step (faithful dedent; the awk `extract_run_block` runs on into the following comment block and mis-dedents) and execute it under the existing curl stub with `bash -eo pipefail`, using UNAMBIGUOUS sentinels (`MIRROR_REASON=zz_stage_7256`, `TOKEN_VERDICT=zz_verdict_7256` — never `bridge`/`live`, which ordinary prose or the remedy sentence could contain):
   - empty webhook -> rc 0 and no curl call;
   - configured webhook -> valid JSON, `unfurl_links == false`, `.text` contains `release BLOCKED`, both sentinels, the run URL and `Re-run failed jobs`, and does NOT contain `released!`;
   - must-PASS non-canonical input (plugin case): both vars empty -> rc 0, valid JSON, `release BLOCKED` present, and NEITHER sentinel nor the `zot mirror stage` phrase present (the registry lines are suppressed);
   - only one var set -> the other renders its fallback (`unmeasured` / `not reached`), no empty backticks;
   - `&`, `<`, `>` in `MIRROR_REASON` are entity-escaped in `.text`;
   - curl stub exits non-zero -> step rc 0 (the `|| echo 000` tail copied into the new block).
5. Run the suite: the new assertions fail (step absent) — RED.

### Phase 2 — GREEN: workflow, comments, ADR

Apply Proposed Solution 1-3. Then: the new suite green with all pre-existing T1-T7 passing; `actionlint .github/workflows/reusable-release.yml` shows no finding that is new versus `origin/main`; `python3 scripts/lint-workflow-step-env-refs.py` over the workflow (it checks ALL_CAPS shell variables in `run:` bodies against `env:` — every variable the new block reads is declared in `env:` or guarded with `${X:-}`); `shellcheck` over the parsed new run block. Do NOT run the broad battery (CI owns it; the machine is contended).

### Phase 3 — Mutation proof (against a COPY via `REUSABLE_RELEASE_WF=<copy>`; the tracked file is never edited and the variable is unset for the real run)

Run each Guard 1 matrix row, expect RED, and note the outcome in one short PR-body table. A row that stays green is a test defect: fix the test.

### Phase 4 — Ship (`soleur:ship`)

PR body: `Closes #7256` on its own line; the mutation table; `Brand-survival threshold: none` with the reason below; the disclosed web-platform duplicate (`notify-gated` and `release-outcome`); a note that the PR touches `.github/workflows`, so there is no agent admin-merge path and it ships through the normal merge queue. No post-merge dispatch: a blocked release cannot be forced safely (it would exercise the registry path), so verification is the mutation-proven suite plus `actionlint`; the first real blocked release is the live observation.

## Guard Contract

### Guard 1 — release-notification gate pin (T6b / T7b)

**Property.** Every step that can post to the releases Slack channel fires on exactly the outcome it is for — the success announcer on an uncancelled successful run with a release in flight, the BLOCKED notifier on an uncancelled failed run with a release in flight — neither fires on a cancelled run, the BLOCKED message states only what the job measured, and the failure email keeps its `failure()` gate.

**Assembly.** Derived from the parsed workflow, never listed by hand: the set of steps whose structure references `secrets.SLACK_RELEASES_WEBHOOK_URL` (the census); each such step's `if:`, `continue-on-error` and `env:` wiring; the failure-email step's `if:`; and the blocked step's parsed `run:` (what it actually sends). Chokepoints: the success gate, the blocked gate, the census (so a THIRD Slack-posting step with a plain `if:` cannot appear unnoticed), the env wiring, and the run block under a curl stub.

**Mutation matrix.** Each row edits the COPY and MUST turn the named assertion RED.

| # | Edit | Caught by |
|---|---|---|
| 1 | Delete `!cancelled() &&` from the blocked `if:` | blocked gate equality |
| 2 | Delete `failure() &&` from the blocked `if:` (it would double-announce every success) | blocked gate equality |
| 3 | Delete the release-in-flight conjunct from the blocked `if:` | blocked gate equality |
| 4 | Add `!cancelled() &&` (or `failure() \|\|`) to the SUCCESS step's `if:` | success gate equality |
| 5 | Guard's own dispatch: rename the new step to `Post to Slack (release-blocked)` | explicit "step not found" FAIL, plus the census (name set differs) |
| 6 | Second member after a compliant first: add a THIRD step referencing the secret with a plain `if:` | census |
| 7 | Change the failure email's `if: failure()` to `if: success()` | failure-email equality |
| 8 | Mis-wire the blocked step's `MIRROR_REASON` to `steps.zot_mirror.outputs.mirror_status` | env wiring assertion |
| 9 | In the blocked run block, replace `release BLOCKED` with `released!` | T7b contains / not-contains |
| 10 | In the blocked run block, drop `${MIRROR_REASON}` from the message | T7b sentinel |

**Harness rows.**

| # | Edit | Expectation |
|---|---|---|
| H1 | In T6b weaken the blocked-gate expected literal (drop `failure() && `) | the suite goes RED against the correct workflow, proving the equality compares rather than rubber-stamps |
| H2 (must-PASS, non-canonical) | T7b with both vars empty (the plugin-release shape) and with only one var set — differing from the canonical fixture in a way the contract permits | suite stays GREEN; a guard that rejected every non-canonical input would pass rows 1-10 and still be wrong |

**Anchor.** The pinned literal and the guarded `if:` can be edited in one diff, so the suite proves consistency, not integrity; what sits outside the commit and must also move for a weakening to land is the required CI check on the merge-queue ref plus human review of the diff (no agent admin-merge path). That is proportionate to a notification-routing pin.

## Acceptance Criteria

- [ ] `.github/workflows/reusable-release.yml` has exactly one step named `Post to Slack (release BLOCKED)`, whose parsed `if` equals `!cancelled() && failure() && steps.check_changed.outputs.changed == 'true' && (steps.create_release.outputs.released == 'true' || steps.idempotency.outputs.draft_exists == 'true')` — asserted by T6b on the parsed YAML, not by `grep`.
- [ ] `git diff origin/main...HEAD -- .github/workflows/reusable-release.yml` shows no change to the `if:`, `env:` assignments or run-block code of `Post to Slack (release)` (comment lines only) and no change to `Email notification (release FAILED)`.
- [ ] The blocked message carries `release BLOCKED`, the reason and verdict (when set), the run URL and `Re-run failed jobs`; never `released!`; omits the registry lines when both values are empty (T7b).
- [ ] The two stale comment blocks are rewritten and the lead comment names `Post to Slack (release BLOCKED)`, `notify-gated` and #7256: `git grep -n "does not run at all" -- .github/workflows/reusable-release.yml` returns nothing.
- [ ] ADR-096's "AMENDED 2026-07-30" bullet carries the `AMENDED 2026-10-09 (#7256)` sentence.
- [ ] `bash plugins/soleur/test/reusable-release-idempotency.test.sh` exits 0 with `REUSABLE_RELEASE_WF` unset, and every pre-existing T1-T7 assertion still passes.
- [ ] Guard 1 rows 1-10 and H1 were executed against a copy and observed RED, H2 GREEN; the outcome is noted in the PR body.
- [ ] `actionlint` reports nothing new versus `origin/main`; `python3 scripts/lint-workflow-step-env-refs.py` reports nothing for the new step.
- [ ] Diff scope: `git diff --name-only origin/main...HEAD` is a subset of {the workflow, the idempotency test, the ADR-096 file, this plan, its `tasks.md`} and matches none of `cloud-init-registry`, `zot-registry.tf`, `variables.tf`, `server.tf`, `ci-deploy.sh`, `build-inngest-bootstrap-image.yml`, `ci-workflow-authoring.md`, or `plugins/soleur/` outside `test/`.
- [ ] PR body carries `Closes #7256` on its own line, the brand-survival statement, the disclosed `notify-gated`/`release-outcome` duplicate, and that it ships through the normal merge queue.

## Test Scenarios

| Job status | Release in flight | Success step | BLOCKED step | Failure email (unchanged by this PR) |
|---|---|---|---|---|
| success | yes | fires | silent | silent |
| success | no | silent | silent | silent |
| failure (mirror blocked, draft created) | yes | silent | FIRES | fires |
| failure after a self-heal draft (`draft_exists`) | yes | silent | FIRES | fires |
| failure before any draft exists | no | silent | silent | fires |
| cancelled / job timeout | any | silent | silent | not changed by this PR (`failure()` semantics) |
| success via dispatch override (`mirror_status=degraded`) | yes | fires, with the existing warning line | silent | silent |
| plugin component failure | yes | silent | FIRES, no registry lines | fires |
| web-platform push failure | yes | silent | FIRES (plus `notify-gated` later, deliberate) | fires |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The worst realistic regression is a missing or duplicated internal Slack message in the team's releases channel; no end-user surface, data or deploy path changes.
- **If this leaks, the user's data is exposed via:** no new vector. The step reads the same `SLACK_RELEASES_WEBHOOK_URL` secret as the existing step, masks it with `::add-mask::`, receives it through `env:` (never inline), and the message holds only repo-derived tokens (component, version, tag, fixed-vocabulary reason and verdict, the run URL) — no release-notes body and no untrusted text.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`: this changes which internal channel a failure notice reaches, an independent failure email carries the same signal, so a defect degrades convenience, not any user's outcome.

threshold: none, reason: the touched path is a release workflow's internal-ops notification routing; the failure email is an independent second channel, the step is `continue-on-error`, and no user data, credential handling or deploy decision changes.

## Observability

(The path matches the canonical sensitive-path regex via `release`, so the block is declared. Layer 6: workflow-run log of the calling workflow's step.)

```yaml
liveness_signal:
  what: the BLOCKED Slack step exists in the shared release workflow and fires only when a release job fails with a release in flight
  cadence: per failed release run (event-driven; silent by design on healthy runs)
  alert_target: the Slack releases channel via SLACK_RELEASES_WEBHOOK_URL, plus the existing ops email
  configured_in: .github/workflows/reusable-release.yml (step "Post to Slack (release BLOCKED)")

error_reporting:
  destination: GitHub Actions run log and step annotations (layer 6, workflow-run log)
  fail_loud: a non-2xx or transport failure prints a ::warning:: annotation; an empty webhook prints a ::warning:: and exits 0; the step is continue-on-error and the failure email is the independent second channel

failure_modes:
  - mode: Slack webhook secret unset or empty
    detection: ::warning:: "No Slack webhook URL configured" in the step log (layer 6, workflow-run log)
    alert_route: the failure email still fires, and web-platform push releases also get notify-gated's deploy-GATED Slack
  - mode: Slack returns non-2xx or the transport fails
    detection: ::warning:: "Slack notification failed (HTTP <code>)" (layer 6, workflow-run log)
    alert_route: the failure email still fires

logs:
  where: GitHub Actions run log for the release job
  retention: the repository's Actions log retention setting (GitHub default 90 days)

discoverability_test:
  command: grep -cF 'name: Post to Slack (release BLOCKED)' .github/workflows/reusable-release.yml
  expected_output: 1
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI notification-routing change in a release workflow (engineering/tooling only). Phases 2.7, 2.8, 2.10 and 2.11 do not apply (no regulated data, no new infrastructure, no architectural decision — the ADR-096 edit amends a sentence this change falsifies — and no store or network connection); no UI surface.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "make Slack fire for a blocked release too" [brief] | Proposed Solution 1; Files to Edit: reusable-release.yml | mapped |
| 2 | "without firing on a cancelled run" [brief] | `!cancelled()` in the new gate; Guard 1 rows 1-3 | mapped |
| 3 | "keep the existing success-path Slack condition byte-for-byte equivalent for non-failure runs" [brief] | success step left untouched; T6b success-gate equality | mapped |
| 4 | "keep the failure email" [brief] | failure-email step left untouched; T6b failure-email equality | mapped |
| 5 | "rewrite the step's own comment that currently documents the old behaviour" [brief] | Proposed Solution 2 (two comment blocks plus lead comment) | mapped |
| 6 | "VERIFY THE PREMISE FIRST against the current file" [brief] | Research Insights, Premise Validation table | mapped |
| 7 | "also read how build-inngest-bootstrap-image.yml fixed the same class and whether a single Slack message can carry the mirror failure reason the email already uses" [brief] | Premise Validation rows 5 and 6; message contract | mapped |
| 8 | "Add or extend a test pinning the gate ... the gate must be pinned by anchored syntax, not a bare token, and mutation-proven by deleting the new condition and confirming red" [brief] | Phase 1 (T6b/T7b on parsed YAML), Phase 3, Guard Contract | mapped |
| 9 | "edit only reusable-release.yml plus its test and any doc line that states the old behaviour" [brief] | Files to Edit (workflow, test, ADR-096 sentence); Files NOT to touch | mapped |
| 10 | "do not touch cloud-init-registry.yml, zot-registry.tf, variables.tf, server.tf, ci-deploy.sh or any deploy_pipeline_fix trigger file" [brief] | Files NOT to touch; diff-scope acceptance criterion | mapped |
| 11 | "The PR body will carry `Closes #7256` on its own line" and "ship through the normal merge queue" [brief] | Phase 4; last acceptance criterion | mapped |
| 12 | "keep your hunk narrow so the two do not collide" [brief] | Collision note (PR 7390) | mapped |
| 13 | "The brand-survival threshold is expected to be `none` ... state the reason" [brief] | User-Brand Impact | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit: `.github/workflows/reusable-release.yml` (new step, comments) | "edit only reusable-release.yml plus its test" | asked |
| Files to Edit: `plugins/soleur/test/reusable-release-idempotency.test.sh` | "Add or extend a test pinning the gate" | asked |
| Files to Edit: ADR-096 one-sentence amendment | "any doc line that states the old behaviour" | asked |
| Files to Create: `specs/.../tasks.md` | — | inferred — justification: the plan skill's own save-tasks step produces it; it is a plan artifact, not product scope |
| Sibling step `Post to Slack (release BLOCKED)` | "make Slack fire for a blocked release too" | asked |
| Release-in-flight predicate copied into the new gate | "keep the existing success-path Slack condition byte-for-byte equivalent" | asked |
| Registry-line suppression when both values are empty; entity escape of reason and verdict | — | inferred — justification: the shared workflow also serves plugin releases that build no image (CTO devex review), and `degraded()` reasons are free-form shell arguments (Kieran F7); without them the message is noise or an injection surface |
| `WF` override hook (`REUSABLE_RELEASE_WF`) | "mutation-proven by deleting the new condition and confirming red" | asked |
| Parsed-YAML helper and census assertion | "the gate must be pinned by anchored syntax, not a bare token" | asked |
| Env-wiring assertions | "the gate must be pinned by anchored syntax, not a bare token" | asked |
| T7b run-block contract | "whether a single Slack message can carry the mirror failure reason the email already uses" | asked |
| Guard Contract section | "mutation-proven by deleting the new condition and confirming red" | asked |
| Observability block | — | inferred — justification: the file path matches the canonical sensitive-path regex, so preflight Check 10 and deepen-plan 4.7 require the block |

### Split Assessment

- Subsystems touched: 3 — `.github`, `plugins/soleur`, `knowledge-base`
- Planned files: 3 edited + 1 created (plus the plan file) | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Plan Review Revisions (2026-10-09; all Mechanical, applied)

DHH, Kieran, the simplicity reviewer and the CTO devex lens reviewed this plan. Applied: awk extraction and normalizer replaced by a parsed-YAML helper (F2, DHH 5, simplicity); truth table, layout self-test, order assertion, `continue-on-error` mutation row, three of twelve mutation rows and two harness rows cut; FR-A6 comment append cut; the over-claim "nothing was published" replaced by a measured statement (F7, DHH 15, simplicity); env-wiring assertion and unambiguous sentinels added (F3); the wrong "independent catcher" corrected to `actionlint` (F4); the web-platform `notify-gated` duplicate named and accepted (F1, CTO); plugin-release noise removed by suppressing the registry lines (CTO); the timeout row added (F8); the `does not run at all` grep widened to the whole file (F10). Not applied, recorded as the one open tension: the simplicity reviewer would also cut the census; DHH and Kieran kept it as the cheap catch for a third plain-`if:` notifier, which is the actual #7256 class, so it stays.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `none` with a scope-out reason because the path is sensitive-path-matched.
- `!cancelled() && failure() &&` at the start of a `>-` folded block is valid YAML (block-scalar content is literal), and `actionlint` accepts it; the unfolded `if: !cancelled() …` is NOT (a leading `!` is a YAML tag), which is why the sibling workflow wraps its condition in `${{ }}`.
- The folded `if:` keeps newlines on more-indented continuation lines; the test helper collapses all whitespace before comparing.
- Existing T6/T7 select steps with `index()` on `- name: Post to Slack (release)`; `(release BLOCKED)` does not contain that literal, so they keep working. Do not rename the new step to `(release) …`.
- Do not "port" this fix into `build-inngest-bootstrap-image.yml` or edit its comment (mint-trigger hazard).
- `Closes #7256` goes in the PR BODY on its own line, not the title (`wg-use-closes-n-in-pr-body-not-title-to`).
