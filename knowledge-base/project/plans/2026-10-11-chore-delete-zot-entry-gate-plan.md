---
title: "chore(infra): delete the superseded zot-entry-gate.sh and every live reference to it (#7258 Step B)"
type: chore
date: 2026-10-11
slug: delete-zot-entry-gate
branch: feat-one-shot-7258-delete-zot-entry-gate
issue: 7258
closes: [7258]
lane: cross-domain
priority: p3-low
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore(infra): delete the superseded zot-entry-gate.sh and every live reference to it (#7258 Step B)

## Overview

Step B of #7258: a pure delete. `apps/web-platform/infra/zot-entry-gate.sh` is a pre-flip go/no-go script that nothing invokes (its own header says SUPERSEDED/UNWIRED since 2026-07-30), and its only test, `zot-entry-gate.test.sh`, proves a file that gates nothing. Step A (PR #9979, merge `10f33882ad`) replaced its one unique job (does zot serve the platform repos to the HOST's pull credential) with the web-1 consumer probe covering both `jikig-ai/soleur-web-platform` and `jikig-ai/soleur-inngest-bootstrap`; the Step B go/no-go recipe was observed green and posted on #7258 (comment 6108887287, 2026-10-11).

Scope, from the brief: delete the script and its test; drop their two registration rows; repair the dangling comment references; fix two statements that the passage of events has made false (both about Slack delivery); sweep the repo and decide every remaining hit. PR body carries `Closes #7258` and `Refs #7079` (not a close keyword, see Phase 6).

Terms used below: **Step A / Step B** = the two halves of #7258. **Registration rows** = one row per suite in `suite-shard-legs.tsv` and `suite-durations.tsv` (suite registration is filesystem presence plus those rows since ADR-252; there is no `run:` step in `infra-validation.yml` any more).

## Research Insights

### Premise Validation (Phase 0.6, re-derived on `origin/main` 67cb281e4f)

| Cited premise | Check | Result |
|---|---|---|
| #7258 open, Step B gate met | `gh issue view 7258` + comment 6108887287 | OPEN. Two distinct 30-minute buckets (11:39Z, 12:10Z), both repos code 200, zero SUPPRESS and zero HARD FAILURE rows, canary alive, heartbeat `soleur-web-zot-consumer-web-1` up. Held. |
| Nothing invokes the script | `git grep -n 'zot-entry-gate' origin/main -- . ':!knowledge-base'` | Held. Every non-self hit is a comment or a `.tsv` row; no workflow, script, Terraform or test calls it. |
| `scripts/suite-*.tsv` carry no row | `grep -n zot-entry-gate scripts/suite-*.tsv` | Held: zero hits (those are the repo-level manifests; the gate rows live in `apps/web-platform/infra/suite-*.tsv`). |
| Floors and ledgers hold no entry for the gate | grep of `scripts/guard-vacuity-floor.test.sh` (PROMOTED_FILES) and `plugins/soleur/test/fixture-relative-assert.baseline.txt` | Held: zero hits in both. No deferral-ledger or floor edit is needed, so there is nothing that can rise. |
| #7079 lists the gate as a residual item | `gh issue view 7079` | OPEN; the post-mortem table row confirms. Noted for ship; not closed here. |
| #7256 ("blocking zot-mirror failure sends no Slack") | `gh issue view 7256` | CLOSED by #9892. This is what falsifies the Slack comment in `build-inngest-bootstrap-image.yml` (Phase 4). |
| No open PR touches the gate | brief's collision probe + re-run for the five edited files | Held for the gate itself. Two open PRs touch files this PR edits: #9938 (canary DIAG) edits `apps/web-platform/infra/ci-deploy.sh` and `ci-deploy.test.sh`, and #7390 (a WIP) edits `.github/workflows/reusable-release.yml`. Neither names the gate, but #9938 is also a deploy-pipeline-fix trigger: if it merges first, rebase (the edits are in different regions of `ci-deploy.sh`, so a clean rebase is expected) and let its apply finish before this PR is queued (Phase 7). Re-check at enqueue. |
| ADR corpus | grep of `knowledge-base/engineering/architecture/decisions/` | ADR-096 line ~496 already says the gate was "superseded". No decision here contradicts the deletion; no ADR is needed (see Architecture Decision). |

### Property List (Phase 0.6b) and Cut List

Properties this change must buy:

1. No script exists that asserts a stale contract and gates nothing, and no registration row points at a file that does not exist.
2. No live file points a reader at the deleted script.
3. No live comment or doc states something false because of events since it was written (two Slack statements, plus one stale "no host-side probe" statement in the same hunk as a dangling reference).
4. Nothing that only ratchets one way (vacuity floors, the relative-assert baseline, the declared-probe count) rises.
5. The one production side effect (a `ci-deploy.sh` content change reaching the host) lands as a single, sequenced apply.

Cut list (mechanisms considered and removed before research):

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| A replacement probe for the "zot's real 403" the gate was named as the home of | 1/3 | Already bought: `web-zot-consumer-probe.sh` reads `/v2/<repo>/tags/list` with the pull credential and a 403 is an unexpected code, which emits `SUPPRESS ping` and alarms by absence. Step A added it. Nothing new is built. |
| Rewriting `ci-deploy.sh` so the 403 comment is deleted outright | 2 | Kept as a re-pointed comment instead: the paragraph exists to tell the next reader which layer sees a broken `accessControl`; deleting it loses that and re-creates the confusion. |
| Editing historical knowledge-base records (ADR-096, one post-mortem, one learning, seven plans, one spec, and the archives) | 2 | Point-in-time records; rewriting them falsifies history. Decided per hit in the census below. |
| A new test that asserts the file is absent | 1 | A deleted file needs no test; `test-infra-suite-registration.sh` already fails if a registration row names a missing file, and the Phase 7 grep census is the one-time evidence. |
| Folding `server.tf`'s stale `web-probe.tf:22` comment cite (Step A's accepted-but-unfixed note) | 3 | Out of the brief; `server.tf` is also a trigger path, so touching it widens the apply. Left for the next PR that has a reason to edit `server.tf`. |

### Applicable learnings (from the Step A and Step B-hold plans, re-read)

- Registration is filesystem presence plus the two `.tsv` rows (ADR-252); the issue body's "remove the `run: bash ...zot-entry-gate.test.sh` step" no longer exists.
- Deleting anything under `apps/web-platform/infra/` matches the push filters of `apply-web-platform-infra.yml` and `web-platform-release.yml`; a `ci-deploy.sh` edit also matches `apply-deploy-pipeline-fix.yml`.
- `ci-deploy.sh` feeds `triggers_replace`, so a version or a date in the replacement comment makes every later zot bump edit it: write the replacement text without either (the file's own comment says this at the per-registry measured-behaviour block).
- `BASELINE_DECLARED_PROBES` (58) counts PLANS that declare `credentials_required`. This plan must not declare that key, or the count becomes 59 and the baseline would have to be raised.

## Research Reconciliation: brief vs codebase

| Brief claim | Reality on `origin/main` | Plan response |
|---|---|---|
| Rows at `suite-shard-legs.tsv` ~:175 and `suite-durations.tsv` ~:172 | Exactly `:175` and `:172` today | Re-grep at work time; delete by content, not by line number. |
| Comment refs at `ci-deploy.sh` ~:1410, `build-inngest-bootstrap-image.yml` ~:817, ~:931, `reusable-release.yml` ~:1219, ~:1420 | Exactly those lines | Same: edit by anchor text. |
| "Fix two stale Slack statements ... grep each for the statement that names the gate or a Slack notification it no longer sends" | The brief does not name them. Measured candidates: (1) `build-inngest-bootstrap-image.yml:971-979` says this workflow is AHEAD of `reusable-release.yml`, that `cancelled()` occurs ZERO times there, and that a blocking mirror failure there "yields no Slack ... tracked separately (#7256)". All three are false now: `reusable-release.yml` has 3 `cancelled()` occurrences and a `Post to Slack (release BLOCKED)` step (`!cancelled() && failure()`) shipped by #9892, which closed #7256. (2) `ci-workflow-authoring.md:10` says the only Slack carve-out is the `Post to Slack (release)` step. There are now seven Slack-posting steps across four workflows. | Fix both in Phase 4 and record the choice as challengeable (the brief left the targets implicit). |
| `scripts/guard-vacuity-floor.test.sh` may conflict; `BASELINE_DECLARED_PROBES` is 58 on main | Confirmed 58 at `preflight-discoverability-test.test.ts:2909`; the gate is in neither floor list | This PR does not edit either file. A conflict can only arrive through a sibling merge; resolve per rule, never raise a floor. |
| `scripts/sync-pr-behind.sh <PR> --queue-state` | The script is `plugins/soleur/scripts/sync-pr-behind.sh`; `deploy-arm.sh` is `plugins/soleur/scripts/deploy-arm.sh` | Use the real paths. |
| One more stale statement exists beside the two (not in the brief) | `build-inngest-bootstrap-image.yml:929-931` says "There is currently no live probe of jikig-ai/soleur-inngest-bootstrap from the host side ... zot-entry-gate.sh is SUPERSEDED/UNWIRED". After Step A the web-1 probe covers that repo (web-2 still runs the single-repo probe until its next replace). The `GITHUB_STEP_SUMMARY` text four lines below says host pull is "unverified for this repo". | The ~:931 edit is forced anyway (it names the gate). Rewrite the sentence to the post-Step-A truth in the same hunk; adjust the summary echo to match (Phase 3). Marked `inferred` in the Scope Check. |

## Open Code-Review Overlap

Queried the 200 open `code-review` issues for each edited path and the gate name. Matches: `#8881` (review: test-scripts K=6 to K=7 rebalance) names `suite-shard-legs.tsv` only because that review concerns the repo-level shard manifest.

- **#8881 — Acknowledge.** Different manifest (`scripts/suite-shard-legs.tsv` territory; this PR edits `apps/web-platform/infra/suite-shard-legs.tsv` and removes one row). No rebalance is attempted. The scope-out stays open.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-visible. The deleted script runs nowhere. The worst realistic failure is a red CI check (a registration row left pointing at a deleted file, or a mangled workflow comment breaking YAML) that blocks a merge, or the post-merge deploy of the web image/`ci-deploy.sh` stalling; production keeps serving the previous image either way.
- **If this leaks, the user's data is exposed via:** no exposure vector. The diff deletes a script that read the registry pull credential (it is a consumer of `ZOT_PULL_*`, never a producer) and edits comments; it adds no code path, secret, log line or network edge.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change is a deletion plus comments with one byte-for-byte-equivalent-behaviour edit to a host script; the next tier up (`aggregate pattern`) would need a way for the deletion to degrade many users at once, and the only runtime-adjacent edit is a comment inside `ci-deploy.sh`.

`threshold: none, reason: the sensitive-path regex matches (apps/web-platform/infra/ and .github/workflows/*release*.yml) but the diff deletes an uncalled script and edits comments only; the one executable file touched, ci-deploy.sh, changes by comment lines with no change to any statement.`

## Files to Delete

- `apps/web-platform/infra/zot-entry-gate.sh`
- `apps/web-platform/infra/zot-entry-gate.test.sh`

## Files to Edit

| File | Edit |
|---|---|
| `apps/web-platform/infra/suite-shard-legs.tsv` | Delete the `zot-entry-gate.test.sh	3` row. |
| `apps/web-platform/infra/suite-durations.tsv` | Delete the `zot-entry-gate.test.sh	0	measured` row. |
| `apps/web-platform/infra/ci-deploy.sh` | Re-point the comment line that ends "`zot-entry-gate.sh` is where zot's real 403 lives." to the web-host consumer probe (no version, no date; see Learnings). Comment-only. |
| `.github/workflows/build-inngest-bootstrap-image.yml` | (a) ~:817 drop "+ zot-entry-gate.sh" from the namespace comment. (b) ~:929-931 rewrite the "no live probe ... SUPERSEDED/UNWIRED" sentence to the post-Step-A truth. (c) ~:940-943 align the `GITHUB_STEP_SUMMARY` wording ("Host-side pull ... is unverified for this repo") with it, keeping the "does not license a pin" conclusion (retention still evicts). (d) ~:971-979 replace the false parity paragraph with one that states the current fact. |
| `.github/workflows/reusable-release.yml` | ~:1219 drop "and zot-entry-gate.sh" from the namespace comment; ~:1420 drop "zot-entry-gate/" from "zot-entry-gate/soak-gate catch a missing/unsigned copy before the flip" (the pre-cutover claim is already marked superseded by the cutover to `ZOT_ACTIVE=1`; reduce it to what is still true or mark it historical). Comment-only. |
| `plugins/soleur/skills/ship/references/ci-workflow-authoring.md` | Line 10: replace "One carve-out: the release announcement posts to Slack via the inline `Post to Slack (release)` step" with the true set (below). |

### Sweep census (Phase 5 of the brief): every hit decided

`git grep -n -i 'zot-entry-gate'` outside `archive/`, after excluding the files above:

| Hit | Decision | Reason |
|---|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-096-...zot.md` (~:496) | Leave | Historical ADR; the sentence already says "superseded". |
| `knowledge-base/engineering/operations/post-mortems/2026-07-29-v0244-1-...-postmortem.md` (~:222, #7079 row) | Leave | Point-in-time record. |
| `knowledge-base/project/learnings/best-practices/2026-07-09-nonblocking-copy-then-sign-...md` | Leave | Historical learning. |
| `knowledge-base/project/plans/*.md` (7 files, 2026-07-09 through 2026-09-24) | Leave | Historical plans; one-time evidence of the decision trail. |
| `knowledge-base/project/specs/feat-one-shot-zot-mirror-fail-closed/tasks.md` | Leave | Completed spec (`[x]` rows), not live guidance. |
| `knowledge-base/project/{plans,specs}/archive/**` | Leave | Archives. |
| This feature's own plan and `specs/feat-one-shot-7258-delete-zot-entry-gate/tasks.md` | Leave | Migration records; must cite the deleted path (exclude from the zero-residual check, as for any rename sweep). |
| Non-hits that matched the looser pattern `entry gate` (ADR-276, CLA files, `ci.yml:1153`, agent-runner tests, ...) | Not this gate | Different concept; verified by reading context. |

Result: no live non-historical knowledge-base document references the gate, so the knowledge-base needs no edit. The implementer re-runs the census at work time; any NEW live hit (a sibling that merged) is decided the same way.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-7258-delete-zot-entry-gate/tasks.md` (derived task list; produced with this plan).

## Implementation Phases

### Phase 0: Preflight (read-only)

1. `git fetch origin main`; rebase (never merge) if behind. Check for conflict markers before any `git add`.
2. Re-run the census: `git grep -n 'zot-entry-gate' -- . ':!knowledge-base'` and compare with the table above; re-grep every line number.
3. Re-confirm the floors: `grep -n 'zot-entry-gate' scripts/guard-vacuity-floor.test.sh plugins/soleur/test/fixture-relative-assert.baseline.txt scripts/suite-*.tsv` returns nothing (use `/usr/bin/grep -a` if the host grep is ugrep and a must-match grep returns nothing).

### Phase 1: Delete the script, its test, and the registrations

`git rm` the two files; delete the one row from each `.tsv` by content. Do not run `regenerate-shard-manifest.py --write` (it rewrites header timestamps); hand deletion keeps the diff to two rows, and the registration test is the verifier.

### Phase 2: Dangling comment references (comment-only)

`ci-deploy.sh`, `reusable-release.yml` x2, `build-inngest-bootstrap-image.yml` ~:817. For `ci-deploy.sh`, the replacement is a single sentence naming `web-zot-consumer-probe.sh` as the layer that sees a broken `accessControl` (its `tags/list` read with the pull credential returns 403, which is an unexpected code and emits `SUPPRESS ping`). No version number, no date.

### Phase 3: Post-Step-A truth in `build-inngest-bootstrap-image.yml` ~:929-943

State what is now true: the web-1 host probe reads the repo's `tags/list` with the pull credential for `jikig-ai/soleur-inngest-bootstrap` (web-2 not until its next replace), but it does not resolve the PINNED tag's manifest and does not defend against retention eviction, so a green run here is still not evidence for an `@sha256` pin. Keep the "does not license a pin" summary conclusion; reword only the "host-side pull is unverified for this repo" clause. Before editing, `git grep` the touched summary strings in `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh`, `cutover-inngest-workflow.test.sh` and `.github/scripts/test/` so no suite pins the old text (initial grep found none).

### Phase 4: The two stale Slack statements

1. `build-inngest-bootstrap-image.yml` ~:971-979. Replace the "AHEAD of ... ZERO times ... Tracked separately (#7256)" paragraph with the current fact: `reusable-release.yml` now has a failure-gated sibling `Post to Slack (release BLOCKED)` (`!cancelled() && failure()`, #7256 closed by #9892), so a blocking mirror failure reaches Slack in both workflows; this step keeps `!cancelled() &&` for the reason stated just above it. Verify each claim with grep before writing (`grep -c 'cancelled()' .github/workflows/reusable-release.yml`, and the step name).
2. `ci-workflow-authoring.md:10`. Keep the rule (notifications via `.github/actions/notify-ops-email`, not chat webhooks; Discord for community content only). Replace the single-step carve-out with the verified set of release/mirror push signals: `Post to Slack (release)` and `Post to Slack (release BLOCKED)` in `reusable-release.yml` (#5079, #7256), `Post deploy-gated notification to Slack` in `web-platform-release.yml`, and the mirror-status, publish-refused and pin-bump-failure steps in `build-inngest-bootstrap-image.yml` plus `mint-inngest-bootstrap-tag.yml`'s auto-mint failure step (#6278, #8747). Re-derive the list with `git grep -n -E 'name: .*Slack' -- .github/workflows` at work time and write exactly what it returns. This is documentation of existing behaviour, not a new authorization.

### Phase 5: Local verification (see Acceptance Criteria for commands)

Registration and manifest tests, `shellcheck` on `ci-deploy.sh`, the workflow YAML parse, the guards named in the standing rules, then the hook tests (`.claude/hooks/*.test.sh`; run `pre-merge-rebase.test.sh` with a timeout above 120 s). The local full battery is optional: skip it when the capacity probe shows contention (CI is the merge gate).

### Phase 6: Ship

PR body: `Closes #7258` on its own line; `Refs #7079` (the post-mortem residual item list names the gate: post a one-line comment there that the gate item is resolved by this PR, but leave #7079 open for its other items); threshold `none` with the reason above; the sweep census; the two-Slack-statement choice flagged as challengeable; the apply-sequencing note. Do not push while the PR is queued (the merge queue handles BEHIND). A draft PR's draft-light `test` check reads red; ignore it and read the run created at ready.

### Phase 7: Deploy sequencing (before enqueue and after merge)

Before queueing: if #9938 (it edits `ci-deploy.sh`) merged in the meantime, wait for its `apply-deploy-pipeline-fix.yml` run to finish first; `gh run list --status in_progress` and the `Apply web-platform infra` and `Apply deploy-pipeline-fix` workflows must show nothing in flight (at plan time one `apply-web-platform-infra` run was in progress and one pending from earlier merges: re-check, wait for them), and read the `soleur:ship` "Deploy Pipeline Fix Drift Gate" (Phase 5.5), which `ci-deploy.sh` triggers. The edit is comment-only, so the gate's expectation is "re-delivery of identical behaviour".

After merge, from the merge commit: three workflows start. Expected outcomes:

- `apply-deploy-pipeline-fix.yml` (trigger file `ci-deploy.sh`): one apply, expected green (the last six runs were green). It fails closed if web-2 is down or mid-replace.
- `apply-web-platform-infra.yml` (push filter `apps/web-platform/infra/**`): expected plan has no resource change from this PR; the run is already red on main for an unrelated reason (`terraform_data.egress_gateway_web2` port-22 timeout, #10003). A red here is NOT attributable to this PR as long as the failing resource is that one.
- `web-platform-release.yml` (`apps/web-platform/**`): cuts and deploys a web image. Verify with `bash plugins/soleur/scripts/deploy-arm.sh find --wait <full 40-hex merge sha>`, then `deploy-arm.sh served <full sha>`.

## Architecture Decision (ADR/C4)

Skipped: no architectural decision is made or changed. The deletion executes the decision already recorded in the ADR-096 amendment (zot is the sole pull path; the gate is superseded). A reader of the existing ADRs and C4 would not be misled after this ships; the C4 model has no element for the script (it was never a runtime component).

## Observability

The change adds no code path. The observability that matters is that the surface which superseded the gate stays alive.

```yaml
liveness_signal:
  what: Better Stack heartbeat soleur-web-zot-consumer-web-1 (status up) plus the per-repository SOLEUR_ZOT_PROBE_VERDICT marker rows from web-1
  cadence: every 30 minutes (marker rows) and the heartbeat period
  alert_target: Better Stack incident to the ops email policy; absence-of-ping alarms
  configured_in: apps/web-platform/infra/web-probe.tf and apps/web-platform/infra/web-zot-consumer-probe.sh
error_reporting:
  destination: journald -> vector -> Better Stack Logs (SOLEUR_ZOT_PROBE_VERDICT, SUPPRESS ping, HARD FAILURE lines)
  fail_loud: an unexpected registry code suppresses the heartbeat ping so the absence alarms; no deleted-script path can fail silently because none exists
failure_modes:
  - mode: a registration row left pointing at a deleted file
    detection: .github/scripts/test/test-infra-suite-registration.sh fails in CI
    alert_route: red required check on this PR
  - mode: a comment edit breaks a workflow's YAML so no job starts
    detection: workflow parse in CI and the actionlint-class check in the local verification step
    alert_route: red required check on this PR
  - mode: the ci-deploy.sh re-delivery apply fails on a down web-2
    detection: apply-deploy-pipeline-fix.yml run conclusion
    alert_route: red run, tracked by the post-merge verification step
logs:
  where: Better Stack Logs (probe markers); GitHub Actions run logs (apply and release)
  retention: per the Better Stack plan and 90 days for Actions logs
discoverability_test:
  command: bash -c 'if git grep -q zot-entry-gate -- apps .github scripts plugins; then echo PRESENT; else echo ABSENT; fi'
  expected_output: ABSENT
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an infrastructure cleanup that deletes an uncalled script and corrects comments and one internal reference page. No user-facing surface (no UI-surface path in the Files lists), no regulated-data surface, no new vendor, store, or connection (so the GDPR, Encryption Posture and Guard Contract gates do not fire: the deliverable contains no guard; it removes a gate-shaped script that was never wired).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "pure-delete PR removing apps/web-platform/infra/zot-entry-gate.sh (the superseded zot entry gate)" [brief] | Files to Delete; Phase 1 | mapped |
| 2 | "apps/web-platform/infra/zot-entry-gate.sh and apps/web-platform/infra/zot-entry-gate.test.sh" [brief 1] | Files to Delete; Phase 1 | mapped |
| 3 | "Their rows in apps/web-platform/infra/suite-shard-legs.tsv (~:175) and apps/web-platform/infra/suite-durations.tsv (~:172). scripts/suite-*.tsv are different files; check they carry no row for the gate." [brief 2] | Files to Edit rows 1-2; Phase 0 step 3 | mapped |
| 4 | "Dangling comment refs: apps/web-platform/infra/ci-deploy.sh (~:1410), .github/workflows/build-inngest-bootstrap-image.yml (~:817, ~:931), .github/workflows/reusable-release.yml (~:1219, ~:1420)" [brief 3] | Phase 2; Phase 3 | mapped |
| 5 | "Fix two stale Slack statements in .github/workflows/build-inngest-bootstrap-image.yml and plugins/soleur/skills/ship/references/ci-workflow-authoring.md" [brief 4] | Phase 4 | mapped |
| 6 | "Sweep: git grep -n 'zot-entry-gate' across the repo excluding archive/ dirs ... Decide every hit." [brief 5] | Sweep census; Phase 0 step 2 | mapped |
| 7 | "the ci-deploy.sh edit is a deploy-pipeline-fix trigger file, so the merge fires apply-deploy-pipeline-fix.yml. Before queueing, check no other apply is in flight" [brief] | Phase 7 | mapped |
| 8 | "Rebase, never merge main into the branch (rename-guard)." [brief] | Phase 0 step 1 | mapped |
| 9 | "Deleting a suite: check scripts/guard-vacuity-floor.test.sh PROMOTED_FILES, the deferral ledger and plugins/soleur/test/fixture-relative-assert.baseline.txt for the gate's test file." [brief] | Premise Validation row 4; Phase 0 step 3; AC | mapped |
| 10 | "Before enqueue, run the .claude/hooks/*.test.sh guards; pre-merge-rebase.test.sh needs a timeout above 120 s." [brief] | Phase 5 | mapped |
| 11 | "put \"Closes #7258\" in the PR body" and "the plan should note it for the ship phase but not close it" (#7079) [brief] | Phase 6 | mapped |
| 12 | "Raise to the operator, do not file an issue: the `cron_monitor_alert_unrouted` no-expiry." [brief] | Operator note below | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Delete the script and its test | "pure-delete PR removing apps/web-platform/infra/zot-entry-gate.sh" | asked |
| Two `.tsv` row deletions | "Their rows in apps/web-platform/infra/suite-shard-legs.tsv (~:175)" | asked |
| Comment-only edits in `ci-deploy.sh`, `reusable-release.yml`, `build-inngest-bootstrap-image.yml` | "Dangling comment refs" | asked |
| Slack fix 1 (`build-inngest-bootstrap-image.yml` ~:971-979) | "Fix two stale Slack statements in .github/workflows/build-inngest-bootstrap-image.yml" | asked (target chosen by measurement; challengeable) |
| Slack fix 2 (`ci-workflow-authoring.md:10`) | "...and plugins/soleur/skills/ship/references/ci-workflow-authoring.md" | asked (target chosen by measurement; challengeable) |
| Post-Step-A rewrite of the ~:929-931 sentence and the summary echo at ~:940-943 | "(~:817, ~:931)" covers the sentence; the summary echo is not quoted | inferred — justification: leaving "no live probe of ... soleur-inngest-bootstrap" in the same hunk that stops naming the gate would keep a statement Step A made false, which is the class the brief asks to fix; the summary echo repeats the same claim four lines below and rots with it |
| Sweep census table | "Decide every hit." | asked |
| Phase 7 sequencing | "Strictly sequential infra applies" | asked |
| `Refs #7079` comment at ship | "note it for the ship phase but not close it" | asked |

### Split Assessment

- Subsystems touched: 3 roots in the code diff (`apps/web-platform`, `.github`, `plugins/soleur`); `knowledge-base` holds only this plan's artifacts
- Planned files: 9 edited or deleted, 2 plan artifacts | Estimated changed lines: about 290 (the deleted script is 118 lines and its test 125; edits are under 50 lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the brief asks for one PR; the code diff touches 3 roots; knowledge-base artifacts do not count toward the code split)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git ls-files | grep -c zot-entry-gate` returns 0 for paths outside `knowledge-base/`; the two files are deleted.
- [ ] `git grep -n 'zot-entry-gate' -- . ':!knowledge-base'` returns nothing (the zero-residual check excludes this feature's own plan and tasks, which cite the old path).
- [ ] Neither `.tsv` mentions the gate; no other row changed (`git diff --stat` on both shows one deletion each).
- [ ] `bash .github/scripts/test/test-infra-suite-registration.sh` and `bash plugins/soleur/test/regenerate-shard-manifest.test.sh` pass.
- [ ] `shellcheck apps/web-platform/infra/ci-deploy.sh` is clean; the `ci-deploy.sh` diff contains only comment lines (`git diff -U0 -- apps/web-platform/infra/ci-deploy.sh | grep -E '^[+-][^+-]' | grep -vE '^[+-]\s*#'` returns nothing).
- [ ] Both edited workflow files parse as YAML and `bash plugins/soleur/test/reusable-release-idempotency.test.sh` still passes (it keys on the `Post to Slack (release)` step name and body, which this PR does not touch).
- [ ] `grep -c 'cancelled()' .github/workflows/reusable-release.yml` is at least 1 and the `Post to Slack (release BLOCKED)` step exists, matching the sentence that replaces the false parity paragraph.
- [ ] The `ci-workflow-authoring.md` carve-out lists exactly the steps `git grep -n -E 'name: .*Slack' -- .github/workflows` returns (or a defensible subset with the rest named as covered by the same rule).
- [ ] `bash scripts/guard-vacuity-floor.test.sh`, `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` (the G1 count stays 58: this plan declares no `credentials_required`), and the fixture-relative-assert ratchet pass with NO floor or baseline edit; if a sibling's merge forces a conflict, resolve it without raising any number.
- [ ] `.claude/hooks/*.test.sh` all pass (with `pre-merge-rebase.test.sh` run under a timeout above 120 s).
- [ ] `python3 scripts/lint-guard-contract.py` is not needed (no guard); `bash plugins/soleur/test/c4-count-parity.test.sh` stays green.
- [ ] PR body: `Closes #7258`, `Refs #7079`, threshold `none` with the reason, the census, the challengeable Slack-target note, and the sequencing note.

### Post-merge (operator-free verification)

- [ ] `bash plugins/soleur/scripts/deploy-arm.sh find --wait <full 40-hex merge sha>` returns an arm, then `deploy-arm.sh served <full sha>` reports the merge served.
- [ ] Exactly one `apply-deploy-pipeline-fix.yml` run for the merge, concluding success.
- [ ] The `apply-web-platform-infra.yml` run, if red, fails only on `terraform_data.egress_gateway_web2` (#10003).
- [ ] #7258 closes via the PR body; #7079 stays open with a one-line comment that its zot-entry-gate item is resolved.
- [ ] The Step A probe is still healthy: heartbeat `soleur-web-zot-consumer-web-1` up and `SOLEUR_ZOT_PROBE_VERDICT` rows still arriving (the deletion must not have disturbed it; it shares no file with the deleted script).

## Test Scenarios

1. Deletion integrity: with both files and both rows removed, the registration test passes; restoring ONLY the `.tsv` row (a mutant) makes it fail, which is how the verifier proves it still checks row-to-file consistency.
2. Dangling-reference census: `git grep -n 'zot-entry-gate' -- . ':!knowledge-base'` is empty; re-introducing any one comment makes the census non-empty (it is the same command run twice, pre- and post-edit).
3. Comment-only claim for `ci-deploy.sh`: the diff filter in the Acceptance Criteria returns empty; a non-comment hunk would fail the criterion.
4. Floors: the count in `preflight-discoverability-test.test.ts` stays 58 and no floor in `guard-vacuity-floor.test.sh` changes; any rise is a defect in this PR.
5. Statement truth: each replaced sentence's factual claims (`cancelled()` count, the BLOCKED step name and `if:`, the Slack step list, the probe's repo list) are verified by the command named next to it in Phase 3 and Phase 4 immediately before writing.

## Risks and Sharp Edges

- A deletion under `apps/web-platform/infra/` starts `apply-web-platform-infra.yml` and `web-platform-release.yml`; the `ci-deploy.sh` comment edit additionally starts `apply-deploy-pipeline-fix.yml` and changes `host_scripts_content_hash` (a user_data input that is `ignore_changes` on the running hosts, so no replace). The cost of the `ci-deploy.sh` edit is one prod re-delivery of a behaviour-identical script. The alternative (leave a pointer to a deleted file in a comment) was rejected by the brief; this is recorded so the choice is visible.
- Do not put a version or date in the replacement `ci-deploy.sh` comment (the file's own header warns this makes every zot bump edit it).
- This plan must not declare the optional probe-credentials key in its `discoverability_test`; doing so moves `BASELINE_DECLARED_PROBES` from 58 to 59 and reddens the discoverability suite. The command above is unauthenticated and finishes well inside the 15 s cap.
- Sibling merges can create conflicts in `scripts/guard-vacuity-floor.test.sh` and `plugins/soleur/test/preflight-discoverability-test.test.ts` even though this PR does not edit them. Rebase, check for conflict markers before `git add`, never raise a count.
- grep on this host may be ugrep: use `/usr/bin/grep -a` when a must-match grep returns nothing. semgrep is broken here; shellcheck is the gate. `pgrep -f` is blocked: use `source plugins/soleur/scripts/lib/proc.sh; list_runs 'pattern'`.
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it and carries the sensitive-path scope-out line.
- Do not push while the PR is queued.

## Operator note (raise, do not file)

The standing rules ask that `cron_monitor_alert_unrouted` having no expiry be raised to the operator rather than filed as an issue. It is unrelated to this change; the final report to the operator should carry one line naming it (a locals entry in the Sentry infra root that exempts a monitor from alert routing with no expiry date).

## References

- #7258 (comments 6091351965, 6107727572, 6108887287), #7079, #7256 (closed by #9892), #10003, #9979 (Step A), draft PR #10016.
- Archived plans: `knowledge-base/project/plans/archive/20261010-020113-2026-10-10-fix-registry-template-render-fixture-hold-zot-entry-gate-delete-plan.md` (deletion checklist), `.../20261011-120807-2026-10-11-chore-zot-consumer-probe-covers-inngest-bootstrap-plan.md` (`## Step B follow-up`).
- `plugins/soleur/skills/ship/SKILL.md` "Deploy Pipeline Fix Drift Gate"; `plugins/soleur/scripts/deploy-arm.sh`; `plugins/soleur/scripts/sync-pr-behind.sh`.
