---
title: "chore(infra): retire the superseded 8296 probe and route the probe-heartbeat Sentry monitor (Stage 3b of #9703)"
date: 2026-10-12
slug: inngest-probe-heartbeat-retire-8296-probe
branch: feat-one-shot-9703-stage-3b-retire-8296-probe
issue: 9703
type: chore
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# chore(infra): retire the superseded 8296 probe and route the probe-heartbeat Sentry monitor (Stage 3b of #9703)

## Enhancement Summary

**Deepened on:** 2026-10-12
**Method:** targeted gate passes (4.6 user-brand, 4.7 observability, 4.8 PAT, 4.10 encryption, 4.11 guard, 4.12 scope) plus repo verification greps; the fan-out agent pass was not run because the change is a mechanical retire-and-refresh whose facts are all one grep away.

### Key Improvements
1. Phase 4.7 caught that the first `discoverability_test` declared a whole suite (over Check 10's 15 s cap); replaced with a one-line file probe that prints the literal `scheduled_inngest_probe_heartbeat.id` once routing lands (it prints nothing today, which is the red state).
2. Phase 4.12 caught the Scope Check lacking Ask Mapping, Provenance and Split Assessment; rewritten with verbatim asks and justified `inferred` rows.
3. Verified `monitor_ids` sort position (`scheduled_inngest_health` < `scheduled_inngest_probe_heartbeat` < `scheduled_integration_suites`), the absence of any test pinning the ledger string or the unrouted-map size (`git grep` over `scripts/`, `plugins/soleur/test`, `apps/web-platform/test` finds only audit-test fixtures), and that `ADR-117-executable-heartbeat-arming.md` carries the 2026-10-11 amendment the plan cites.

### New Considerations Discovered
- `.github/workflows/apply-web-platform-infra.yml` triggers on `apps/web-platform/infra/**`, which also covers the `sentry/` subdirectory: the comment-only edits fire the parent push-apply, whose plan must read "No changes"; the Sentry routing edit additionally fires `apply-sentry-infra.yml`.
- `archive-kb.sh` unions branch-diff discovery even with an explicit slug, so it would archive this branch's own live plan; manual `git mv` is prescribed.
- Closing #9703 stays an operator-authorized post-merge step; no PR text may contain a closing keyword.


Draft PR: #10154. Reference form is `Ref #9703` everywhere (PR title, body, every commit). No closing keyword
may appear in any of them, and `closingIssuesReferences` is asserted to be `[]` after every body edit.

## Overview

The Better Stack heartbeat `betteruptime_heartbeat.inngest_server_probe` (id 504655) is armed and fed by
`.github/workflows/scheduled-inngest-probe-heartbeat.yml`. Stage 3a (#10134, merge `f2f5e0521b`) dropped
`arming_pending`. Until now the daily follow-through probe `scripts/followthroughs/inngest-luks-property-8296.sh`
was the only reporter of a silent probe pipeline; the heartbeat supersedes it. Stage 3b retires the probe and
everything that names it, routes the feeder's Sentry monitor so a missed or withheld run emails, refreshes the
comments the read-back made false, and archives the Stage 3a artifacts.

Parent plan: `knowledge-base/project/plans/2026-10-11-feat-inngest-probe-heartbeat-feeder-plan.md` Phase 7 (3b).
Stage 3a plan (archived by this PR): `knowledge-base/project/plans/2026-10-12-chore-inngest-probe-heartbeat-drop-arming-pending-plan.md`.

This PR does not close #9703. The close is a separate explicit `gh issue close 9703 --comment <read-back evidence>`
after merge, and only on the operator's authorization (see Post-merge).

## Premise Validation (Phase 0.6)

Checked against `origin/main` at `1ff24abfb1` plus this branch (`7ace384193`):

- #9703 is OPEN. Stage 1 and 3a are merged (3a = `f2f5e0521b`). The Stage 3b gate numbers in the brief
  (heartbeat 504655 `up`/`paused=false`; nightly reconcile run 38288047570 clean; feeder runs 38289834837,
  38291467012, 38293255806, 38294942384 all `verdict=beat http=200` over 46 minutes) were read-only verified by the caller
  at 2026-10-12T19:05Z. This plan does not re-assert them from memory: Phase 0 re-runs the gate read-only at work time.
- Every deletion site exists at the cited location (see the census below). The ADR corpus does not reject the
  mechanism: the parent plan and ADR-117's 2026-10-11 amendment prescribe the deletion order.
- Stale in the brief: the parent plan lists `uptime-alerts.tf` comment edits and `inngest-server.md` prose as 3b
  content; the brief's list does not. `uptime-alerts.tf` carries nothing false after 3a (its armed sentence was
  rewritten in 3a), so it stays untouched (Cut List). `inngest-server.md` and `model.c4` and the 8296
  script reference ARE stale and are in scope (below).
- The brief names `cron-monitors.tf:1066`; the stale unrouted claims sit at ~1076-1077 and ~1082 (the
  routing comments), so the plan cites content anchors, not line numbers.
- `scripts/suite-durations.tsv.n` and `scripts/suite-shard-legs.tsv.n` are tracked stray files (added by
  `c64bdcd292`) that also carry the 8296 row. The brief names only the two `*.tsv` files.

## Research Reconciliation: brief vs. codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "the two `*.tsv` rows" | Also one row each in two tracked `*.tsv.n` strays | Remove the row in the strays too, so the residual grep is zero (Cut List records that deleting the strays is out of scope) |
| "the 5a pointer in the 6894 runbook" | Three coupled passages: the §5a enrolment bullets at ~L242-250 ("#8285 is enrolled ... directive for the 8296 probe", "Retiring the probe ..."), the "Do not delete ... until #9703's cleanup stage" bullet at ~L348-351, and the 5a reference in the probe's ACTION text | Rewrite the first two to a dated retirement record; delete the "do not delete" bullet (its condition is met) |
| "MUST_FIND entry" | `scripts/lib/inngest-probe-row.test.sh` L148-159 plus the `pass` line at L249 prints `${#MUST_FIND[@]}` dynamically | Remove one array element; the count in the message is computed, no literal to edit |
| "edit the ledger as the plan's 3b list says" | Phase 7 names `encryption-posture-ledger.json` `live_verification` only; one occurrence (store `hcloud_volume.inngest_redis_luks`, `at_rest.live_verification`) | Single-line rewrite of that one JSON string; keep the `unavailable:` prefix |
| "refresh stale comments (betterstack-logs-alerts.tf:277, cron-monitors.tf:1066, 8296.sh:63)" | First: the passage "born paused pending its feeder ... scripts/followthroughs/inngest-luks-property-8296.sh reports the same silence" (L275-278). Second: the unrouted-until-routing claims in the `scheduled_inngest_probe_heartbeat` block. Third: the script itself (deleted). Also stale: `cron-monitor-alerts.tf` L56-61, `model.c4` L320 (+ `model.likec4.json` regenerate), `inngest-server.md` ~L1690, followthrough-convention.md L249 | In scope, see Files to Edit |

## Research Insights

Property List (Phase 0.6b):

1. P1: no repo file names or runs the retired probe, and the sweeper cannot point at a deleted script.
2. P2: a missed or withheld feeder check-in (Sentry monitor `scheduled_inngest_probe_heartbeat`) emails like its siblings.
3. P3: silence of the probe pipeline stays covered by the armed heartbeat, and no statement claims the retired probe still reports it.
4. P4: the Stage 3a artifacts are archived and nothing live points at their old paths.
5. P5: the edit set conflicts minimally with open drafts #10081 and #8626.

Cut List (Phase 0.6b), mechanisms or edits considered and cut:

- A replacement reporter for the LUKS-type claim: the retired probe never verified the cipher either (`live_verification` already reads `unavailable:`); the heartbeat covers silence, the paging alert covers wrong-volume. Nothing to rebuild.
- Editing `uptime-alerts.tf`: nothing false remains after 3a, and any edit under `apps/web-platform/infra/**` widens the push-apply review for no gain.
- Deleting the stray `.tsv.n` files (decision F1): out of scope; only the 8296 row goes. A one-line follow-up issue ("delete stray scripts/*.tsv.n files added by c64bdcd292", milestone from `knowledge-base/product/roadmap.md`) is filed in the work phase so the deferral is tracked.
- Editing the legal audit record `knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md` L234 (decision F3): attestation-class, excluded in 3a too; a historical checkbox.
- A new ADR or C4 structural change: no architectural decision changes (see Architecture).
- Running `archive-kb.sh`: its branch-diff discovery would also archive THIS branch's own plan and spec (decision F2).

Overlap with open drafts (conflict minimisation, P5):

| File | #10081 (parked draft, #9786) | #8626 (draft, #8532) | This PR |
|---|---|---|---|
| `scripts/encryption-posture-ledger.json` | hunk near L282 (rehearsal store) | hunks incl. `records` insert at ~L213 and the store's `evidence` line | ONE single-line change to `inngest_redis_luks.at_rest.live_verification` (L213); no reflow, no key reorder, no trailing-whitespace change |
| `apps/web-platform/infra/betterstack-logs-alerts.tf` | hunk near L177 | none | one comment block at ~L275-278 only |
| `knowledge-base/.../inngest-luks-cutover-6894.md` | hunks near L117 and L623 | none | passages at ~L242-250 and ~L348-351 only |
| `knowledge-base/.../inngest-server.md` | hunks near L27, L610, L1493, L3052 | none | one sentence near L1690 |
| `model.c4` / `model.likec4.json` | none | `model.c4` | one sentence in L320; `model.likec4.json` is regenerated, so a conflict there is resolved by regeneration (ADR-235 resolver) |

Whichever of the three merges later rebases onto the earlier; because each hunk here is a distinct line, no
textual conflict is expected. #10081 is parked and #8626 is a draft, so this PR will most likely merge first and the
siblings rebase over a smaller delta. Never `update-branch` a queued PR.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "delete the superseded 8296 probe: scripts/followthroughs/inngest-luks-property-8296*, its test, the run_suite line in scripts/test-all.sh, the two *.tsv rows, test-affected-kb-consumers.baseline.txt rows, the 5a pointer in the 6894 runbook, and the MUST_FIND entry" | Phase 2; Files to Delete; Files to Edit (registrations, 6894 runbook) | mapped |
| 2 | "remove the follow-through directive from #9703 (issue edit, ask before the production write if it is not a plain issue-body edit)" | Phase 1 | mapped |
| 3 | "route the Sentry monitor scheduled_inngest_probe_heartbeat (apps/web-platform/infra/sentry/)" | Phase 3 | mapped |
| 4 | "refresh stale comments at betterstack-logs-alerts.tf:277, cron-monitors.tf:1066, scripts/followthroughs/inngest-luks-property-8296.sh:63" | Phase 4 (third goes away with deletion) | mapped |
| 5 | "edit scripts/encryption-posture-ledger.json as the plan's Stage 3b list says" | Phase 5 | mapped |
| 6 | "also archive the Stage 3a plan and spec files" | Phase 6 | mapped |
| 7 | "Plan the edits to minimize conflict and note it in the plan" | Research Insights overlap table; single-line ledger edit | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 0 read-only gate re-run | "Gate verified read-only 2026-10-12T19:05Z" (parent plan Phase 7: "3b gate (mechanical, read-only; all must hold before any deletion)") | asked |
| Residual rows in the two `*.tsv.n` strays | "the two *.tsv rows" | inferred - same registration class; leaving them fails the residual-zero grep; CTO F1 |
| `model.c4` clause + `model.likec4.json` regeneration | parent plan Phase 7: "edit the prose references (... `model.c4` + regenerate ...)" | asked (via the named Phase 7 list) |
| `inngest-server.md` sentence, followthrough-convention.md example | parent plan Phase 7: "edit the prose references"; "refresh stale comments" | inferred - same stale-reference class, one sentence each; CTO F4 |
| `cron-monitor-alerts.tf` label move + `alert-reference.json` regeneration | "route the Sentry monitor scheduled_inngest_probe_heartbeat" | asked |
| Follow-up issue for the stray `.tsv.n` files | "Constraints: ... " (deferral tracking rule) | inferred - a deferral without an issue is invisible; CTO F1 |

### Split Assessment

- Subsystems touched: 4 roots - `scripts/`, `apps/web-platform/infra/` (+ `sentry/`), `knowledge-base/`, and the generated `model.likec4.json` under `knowledge-base/`; grouped by deploy surface that is 3 (scripts, infra, knowledge-base).
- Planned files: 22 | Estimated changed lines: ~250 (two deletions of ~600 lines excluded from the estimate as pure removals)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the pieces are mutually tripwired (the MUST_FIND entry reds if the script disappears alone; the totality checks red on an orphaned registration), so a split would land red.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO rulings F1-F6 recorded in `knowledge-base/project/specs/feat-one-shot-9703-stage-3b-retire-8296-probe/decision-challenges.md`. No UI surface, no schema, no regulated-data surface touched (the legal audit record is deliberately untouched). Product/UX gate does not fire (no component, page or layout path in the file lists).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; the failure shape is operational: the daily reporter of a silent Inngest probe pipeline is gone while the heartbeat that replaces it is mis-fed or paused, so a wrong-volume or dead-probe condition on the store that holds queued user jobs would go unreported.
**If this leaks, the user's data is exposed via:** no new exposure vector (deletion plus comment refresh plus an alert-routing change; no credential, URL or secret is printed, moved or added).
**Brand-survival threshold:** aggregate pattern

Mitigation is the gate: the PR is not marked ready until the Phase 0 read-only gate re-passes, and the nightly `heartbeat-live-reconcile` job (in `scheduled-terraform-drift.yml`) keeps the `fed-but-paused` net.

## Files to Delete

- `scripts/followthroughs/inngest-luks-property-8296.sh`
- `scripts/followthroughs/inngest-luks-property-8296.test.sh`

## Files to Edit

Deletion registrations:

- `scripts/test-all.sh`: the `run_suite "scripts/inngest-luks-property-8296" ...` line and the two-line `#8296 ledger-vs-device` comment above it (content anchor: the comment starts "#8296 ledger-vs-device property probe, enrolled on #8285").
- `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`: the `scripts/inngest-luks-property-8296` row each. Same row in the two tracked `*.tsv.n` strays (F1).
- `scripts/test-affected-kb-consumers.baseline.txt`: the two `scripts/inngest-luks-property-8296<TAB>...` rows.
- `scripts/lib/inngest-probe-row.test.sh`: the `"scripts/followthroughs/inngest-luks-property-8296.sh"` element of `MUST_FIND`. Header comment of that block is unchanged.

Prose and comments:

- `scripts/encryption-posture-ledger.json`: `live_verification` of store `hcloud_volume.inngest_redis_luks` only (F5).
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`: the §5a "#8285 is enrolled ... directive for the 8296 probe" and "Retiring the probe" bullets become a dated retirement record; delete the "Do not delete ... until #9703's cleanup stage" bullet.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: the sentence near "later stages (the cleanup gate and the order in which the superseded 8296 probe ... are removed) are tracked on #9703" becomes a dated record that the probe was retired.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`: the worked-example name in the NOTIFY-ONLY bullet reworded to "the retired #8296 probe" (F4).
- `apps/web-platform/infra/betterstack-logs-alerts.tf`: the comment block that says the heartbeat is "born paused pending its feeder" and that the 8296 script "reports the same silence ... in the interim" is rewritten to say the heartbeat is armed and fed by the repo-side verifier (comment-only; the push-apply plan must show "No changes").
- `apps/web-platform/infra/sentry/cron-monitors.tf`: the comment block above `scheduled_inngest_probe_heartbeat` (the "unrouted: it emails nobody until the routing stage on #9703" claim and the "Unrouted under the two-PR rule" closing line) rewritten to "routed (#9703 Stage 3b)". Comment-only.
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`: delete the `scheduled_inngest_probe_heartbeat` entry and its two-line comment from `local.cron_monitor_alert_unrouted`; add `sentry_cron_monitor.scheduled_inngest_probe_heartbeat.id` to `sentry_alert.cron_monitor_failure.monitor_ids` in sorted position (after `scheduled_inngest_health`, before `scheduled_integration_suites`: the list is sorted, and `scheduled_inngest_probe_heartbeat` sorts after `scheduled_inngest_health`).
- `apps/web-platform/infra/sentry/alert-reference.json`: regenerated from the CI artifact `sentry-alert-reference-expected-<run-id>` (`detectorIds` change), never hand-edited.
- `knowledge-base/engineering/architecture/diagrams/model.c4` L320 (the Inngest queue description): drop the clause "scripts/followthroughs/inngest-luks-property-8296.sh cross-checks the ledger claim against the device daily" and keep the heartbeat clause; then regenerate `model.likec4.json` (ADR-235 regenerable artifact; CI and the pre-merge resolver regenerate it from merged sources). Run `plugins/soleur/test/c4-count-parity.test.sh`.

## Files to Archive (manual `git mv`, F2)

- `knowledge-base/project/plans/2026-10-12-chore-inngest-probe-heartbeat-drop-arming-pending-plan.md` to `knowledge-base/project/plans/archive/<YYYYMMDD-HHMMSS>-2026-10-12-chore-inngest-probe-heartbeat-drop-arming-pending-plan.md`
- `knowledge-base/project/specs/feat-one-shot-9703-stage-3a-drop-arming-pending/` to `knowledge-base/project/specs/archive/<YYYYMMDD-HHMMSS>-feat-one-shot-9703-stage-3a-drop-arming-pending/`

One timestamp for both. The Stage 1 plan/spec and the 2026-10-07 plan stay where they are: they are archived when #9703 closes, not by this PR. After the move, `git grep` the two old paths; references from live files (other than archived content and this plan) are updated to the archive path or removed.

## Open Code-Review Overlap

None recorded as blocking; the work phase runs the two-stage `gh issue list --label code-review` / `jq --arg path` query over the files above and records the result here before the first commit. Siblings #10081 and #8626 are drafts, not code-review scope-outs; see the overlap table.

## Implementation Phases

### Phase 0: Gate re-verification (read-only, before any edit)

All must hold, or STOP and report (do not delete anything):

1. Heartbeat state `504655 up paused=false` read via the runbook's P3 read-back (`inngest-server.md` § "Arming the probe heartbeat (#9703)"); the URL attribute is never selected, no secret is printed. No SSH, no dashboard click.
2. `gh run list --workflow scheduled-inngest-probe-heartbeat.yml --limit 8 --json databaseId,conclusion,createdAt`: the last four completed runs span at least 45 minutes, each log has `verdict=beat`.
3. The newest nightly `heartbeat-live-reconcile` job (workflow `scheduled-terraform-drift.yml`) after 3a (`f2f5e0521b`) is clean.
4. `gh pr view 10154 --json isDraft,closingIssuesReferences` is draft and `[]`.

Record the run ids in the PR body. If a paused heartbeat is found, STOP: the 8296 probe is still the only reporter of silence.

### Phase 1: Directive removal from #9703 (GitHub write, ordering-critical)

Sequence: after Phases 2-6 are committed, locally verified and CI is green, and immediately BEFORE the PR is marked ready or enqueued (F6, ruled: late, not early; re-confirm the heartbeat is still beating at that moment), so the sweeper never points at a deleted script on main. It is a plain issue-body edit, done as `gh issue view 9703 --json body --jq .body` to a scratch file, remove exactly the `<!-- soleur:followthrough script=scripts/followthroughs/inngest-luks-property-8296.sh ... -->` line (and, with it, only that line), then `gh issue edit 9703 --body-file <scratch>`. Per the standing constraint, ask before this production write: it is a plain issue-body edit, but still a mutation outside the repo, so the work phase asks once with the exact before/after diff of the body. Afterward: diff the re-read body against the scratch file (only the directive line removed), assert no `follow-through` directive remains (`grep -c 'soleur:followthrough' = 0`), and keep the `follow-through` label unless the sweeper requires a directive (the label alone is inert; leave it).

If the PR is abandoned after this edit, re-adding the directive is a one-line `gh issue edit`; the gate already passed so a missing tripwire is acceptable.

### Phase 2: Delete the probe and its registrations

Delete the two scripts; remove the registrations listed under Files to Edit. After each, run the narrowest test (see Test Scenarios). Then sweep:

- `git grep -n "inngest-luks-property-8296\|luks-property-8296"` must return only: archived or point-in-time artifacts (this plan, the parent plans, learnings, the legal audit record), and nothing under `scripts/`, `.github/`, `plugins/`, `apps/`, `knowledge-base/engineering/` (except an explicit dated retirement record).
- Enumerate directory-wide consumers of `scripts/followthroughs/*.sh` for count floors or per-file registries (`git grep -n 'followthroughs/' -- scripts plugins/soleur/test .github`) and confirm none pins a count that this deletion lowers. Record the result.

### Phase 3: Route the Sentry monitor (two-PR rule, PR 2)

PR 1 landed in Stage 1 and applied (the monitor exists in Sentry state). Edit `cron-monitor-alerts.tf` as listed. `alert-reference.json` is regenerated through the PR round-trip: push, let `plan_pr` red, `gh run download <run-id> -n sentry-alert-reference-expected-<run-id>` (7-day retention), `cp` over `alert-reference.json`, commit. Without Doppler `prd_terraform` access this is the route; if access exists, the README's local `terraform plan` + `jq` recipe is equivalent. The CI artifact and the local recipe are byte-identical by design; either is acceptable. The routing change makes the monitor emit email through `sentry_alert.cron_monitor_failure` (frequency 1441 min, one email per persistent failure).

Production effect: merging runs `apply-sentry-infra.yml`, which writes the alert's monitor list in Sentry. That is the explicit scope item (3). The PR body states it in its first line (see PR hygiene).

### Phase 4: Refresh stale comments and prose

Edit the comment blocks, runbook passages and `model.c4` clause listed above. Rules:

- Each statement that the heartbeat is armed cites the arm record by name ("runbook section 'Arming the probe heartbeat (#9703)'") and is dated; the live state is read from Better Stack, not from the repo.
- The retirement record says what retired, when (2026-10-12 gate), what covers silence now (the armed heartbeat plus the nightly `fed-but-paused` reconcile), and what it does NOT cover (the LUKS-type claim, which was never verified daily either: `live_verification` stays `unavailable:`).
- Comment-only edits under `apps/web-platform/infra/**` must keep `terraform fmt -check` and `terraform validate` green; the parent-root push-apply plan must report "No changes".
- Regenerate `model.likec4.json` after the `model.c4` edit (the repo's documented render path; see ADR-235 / ADR-050) and run `c4-count-parity`. Do not hand-edit the JSON.

### Phase 5: Ledger edit (F5)

Single-line rewrite of `at_rest.live_verification` for `hcloud_volume.inngest_redis_luks`. It keeps the `unavailable:` prefix and the existing reasoning (the probe row proves WHICH device backs `/mnt/data`, not that it is `crypto_LUKS`) and replaces the sentence that names the retired script with: the 2026-10-12 retirement, that probe silence is now covered by `betteruptime_heartbeat.inngest_server_probe`, and that the paging detector remains the wrong-volume alert. Verify: `python3 -c 'import json;json.load(open("scripts/encryption-posture-ledger.json"))'`; `git diff --stat` shows exactly one changed line; `python3 scripts/lint-encryption-posture.py` (or the targeted test that wraps it) is green, including the `LIVE_VERIFICATION_RE` shape and the `live_coverage_floor` (unchanged: the value stays `unavailable:`).

### Phase 6: Archive Stage 3a artifacts

`git mv` as specified. Do NOT run `archive-kb.sh` (F2). Then assert the plan and spec dir are gone from the active locations and present under `archive/`.

### Phase 7: Verify and ship

- Targeted tests only locally, `TEST_GROUP=affected` or by name (CI is the authority for the full battery): the suites named under Test Scenarios.
- Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` on every commit; messages carry `Ref #9703`, never a closing keyword.
- PR body (edit #10154): first line answers "does merging this alone mutate production?" with "Yes: the Sentry routing apply writes `sentry_alert.cron_monitor_failure.monitor_ids` (scope item 3); the Better Stack parent-root apply is comment-only and must show No changes; no Better Stack write; the #9703 body edit was made before ready (pre-merge, GitHub only)". Then `Ref #9703`, the gate run ids, a `## Changelog` section, and the closing line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Auto-close scan over title, body and every commit message on the branch: grep for `(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+#?\d+` and the full-URL forms; any hit is rewritten. After EVERY body edit assert `gh pr view 10154 --json closingIssuesReferences --jq '.closingIssuesReferences | length'` is `0`.
- Merge queue is on: after enqueue never `update-branch`; if it conflicts, merge main locally per the repo's pre-merge procedure and push. Never touch web-1 LUKS volume 106443278, never reboot or replace a host; none of this PR's edits can.

## Acceptance Criteria

Pre-merge (PR):

- [ ] Phase 0 gate re-passed read-only, with run ids in the PR body.
- [ ] `git grep -n "inngest-luks-property-8296"` has zero hits under `scripts/`, `.github/`, `plugins/`, `apps/`, and `knowledge-base/engineering/` except an explicit dated retirement record; remaining hits are only point-in-time plans, learnings and the legal audit record.
- [ ] `scripts/followthroughs/inngest-luks-property-8296.sh` and `.test.sh` do not exist; `bash scripts/lib/inngest-probe-row.test.sh` passes with one fewer must-find reader (the message reads `found all <N-1> must-find readers`).
- [ ] The #9703 body contains no `soleur:followthrough` directive (re-read after the edit), and only that line changed.
- [ ] `sentry_cron_monitor.scheduled_inngest_probe_heartbeat.id` is in `monitor_ids` (sorted), the label is gone from `cron_monitor_alert_unrouted`, `alert-reference.json` matches the CI-expected artifact (the `plan_pr` sentry gate is green), and `sentry-monitors-audit.test.sh` is green.
- [ ] `scripts/encryption-posture-ledger.json` parses and shows a one-line diff; the encryption-posture lint is green.
- [ ] Parent-root `terraform` plan in `plan_pr` for the comment edit reports "No changes"; `terraform fmt -check` and `validate` green for both roots.
- [ ] `model.c4` clause dropped; `model.likec4.json` regenerated; `c4-count-parity` green.
- [ ] The two Stage 3a artifacts exist only under `archive/`.
- [ ] `closingIssuesReferences` is `[]`; the PR title, body and all commits use `Ref #9703` only.
- [ ] Full battery green in CI (shard totality, `suite-shard-legs`/`suite-durations` consistency, baseline, ADR-ordinals, lints).

Post-merge (operator-authorized, not part of the PR):

- [ ] Read back: the next daily follow-through sweep run logs no reference to the deleted script (no `NOT YET`/`ACTION REQUIRED` comment on #9703 after merge).
- [ ] The apply-sentry-infra run for the merge commit succeeded and the next nightly `sentry-alert-drift` is clean.
- [ ] `gh issue close 9703 --comment <read-back evidence>` only on the operator's explicit authorization (production write); archive the Stage 1 plan/spec and the 2026-10-07 plan at that time.

## Test Scenarios

Mutation row from the deletion registrations (the deliverable is a deletion, so each registration has a "stale row left behind reds X" scenario):

- `bash scripts/lib/inngest-probe-row.test.sh`: green after removing the MUST_FIND element; re-adding it with the file deleted reds it (verify once on a scratch copy, record in the PR body).
- `TEST_GROUP=affected bash scripts/test-all.sh` (or the targeted shard-totality / suite-registry tests that name `suite-shard-legs.tsv`, `suite-durations.tsv`, `test-affected-kb-consumers.baseline.txt`): a registration left for a deleted suite reds the totality check.
- `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh`: routing leaves the declared-pending count one lower.
- Sentry parity: `apps/web-platform/test/sentry-monitor-iac-parity.test.ts` (the monitor stays declared; margin unchanged).
- `bash plugins/soleur/test/c4-count-parity.test.sh` and `apps/web-platform/test/c4-render.test.ts` after the C4 clause edit.
- `python3 scripts/lint-encryption-posture.py` and its test.
- `scripts/lint-infra-no-human-steps.py` over the new plan/spec files and the runbook edits (no human-actor plus infra-imperative phrasing; this plan keeps the arming and re-pause commands in the runbook and does not restate them).

## Observability

```yaml
liveness_signal:
  what: the armed heartbeat betteruptime_heartbeat.inngest_server_probe (id 504655) fed hourly-ish by scheduled-inngest-probe-heartbeat.yml; the feeder's Sentry check-in monitor scheduled_inngest_probe_heartbeat
  cadence: feeder every 15 minutes; heartbeat period 3600 s, grace 1800 s
  alert_target: Better Stack email (the paging surface); after this PR the Sentry monitor emails via sentry_alert.cron_monitor_failure
  configured_in: apps/web-platform/infra/uptime-alerts.tf (heartbeat), apps/web-platform/infra/sentry/cron-monitor-alerts.tf (routing)
error_reporting:
  destination: Sentry issue on a missed or status=error check-in; Better Stack page on a missed beat
  fail_loud: true (a withheld verdict posts status=error; a dead trigger posts a missed check-in)
failure_modes:
  - mode: feeder dark (clock and fallback dead, workflow disabled)
    detection: Sentry missed check-in after interval 15 + margin 60 = 75 min; Better Stack heartbeat missed at 5400 s
    alert_route: Sentry email (new in this PR) and Better Stack email
  - mode: heartbeat re-paused out of band
    detection: nightly heartbeat-live-reconcile fed-but-paused class (re-armed by 3a)
    alert_route: reconcile report / issue
  - mode: probe pipeline silent on the store
    detection: feeder verdict producer_silent withholds the beat
    alert_route: heartbeat page
logs:
  where: GitHub Actions run logs (verdict= line) and Better Stack logtail rows SOLEUR_INNGEST_SERVER_PROBE
  retention: GitHub 90 days; Better Stack per team plan
discoverability_test:
  command: grep -o "sentry_cron_monitor.scheduled_inngest_probe_heartbeat.id" apps/web-platform/infra/sentry/cron-monitor-alerts.tf
  expected_output: scheduled_inngest_probe_heartbeat.id
```

The `discoverability_test` is a local, ssh-free, sub-second file probe that proves the routing half (P2) is declared; it does not claim the live heartbeat state. The live state is read by the Phase 0 gate (Better Stack read-only token inside `doppler run`, never printed) and by the nightly reconcile, which is why the gate and not this probe decides whether the deletion proceeds. The suite `scripts/lib/inngest-probe-row.test.sh` is run in Phase 7 as a test, not declared as the discoverability probe (a suite cannot finish inside preflight Check 10's 15 s cap).

## Encryption Posture

No new store and no new connection. The ledger edit rewrites one `live_verification` string and keeps it `unavailable:`; the encryption claim and `does_not_defend` text are unchanged. The `.tf` trigger matched only comment and alert-routing edits: no persistent store and no cross-component connection is introduced, so there is no at_rest or in_transit entry to declare (Phase 2.11 skip rule). The lint is nonetheless run (Phase 5).

## Architecture Decision (ADR/C4)

No architectural decision changes. The retirement was decided by ADR-117's 2026-10-11 amendment and the parent plan; this PR executes it.

- C4 views: actors, external systems and relationships checked against all three `.c4` files (`model.c4`, `views.c4`, `spec.c4`): external system Better Stack (heartbeat) and Sentry (check-in monitor) already modelled; GitHub Actions feeder already modelled; the retired probe is a repo script with no element of its own. Only the prose clause on the Inngest queue element (`model.c4` L320) names the script, so the edit is one clause plus regeneration; the derived cardinalities (monitor count, heartbeat count) do not move (routing does not add or remove a monitor), which `c4-count-parity` proves.
- ADR: none new. If the work phase finds an ADR amendment paragraph that still calls the 8296 probe live, it is edited in place with a dated status line.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/sentry/cron-monitor-alerts.tf` (`monitor_ids` list, `cron_monitor_alert_unrouted` map): resource change on `sentry_alert.cron_monitor_failure`, applied by `apply-sentry-infra.yml` on merge. `betterstack-logs-alerts.tf` and `sentry/cron-monitors.tf`: comment-only. No new variable, provider or secret.

### Apply path

(a) The existing push-apply workflows only; no replace, no host action, no bootstrap script. Expected downtime: none. Blast radius: one alert rule's monitor list in Sentry.

### Host fan-out

Not applicable: no `terraform_data` SSH provisioner is touched.

### Distinctness / drift safeguards

`alert-reference.json` is held equal to the plan projection by `scripts/sentry-alert-reference-gate.sh` in `plan_pr`; the nightly `scheduled-sentry-alert-drift` cross-checks live. The parent root's push-apply on the comment edit is expected "No changes".

### Vendor-tier reality check

Not applicable (no Better Stack resource created; no tier-gated resource).

## Risks and Sharp Edges

- Ordering: the directive must leave #9703 before the script leaves main. The plan puts the issue edit before PR-ready, after local verification. A sweeper run between the issue edit and merge finds no directive, which is intended.
- A paused heartbeat is silent in the feeder (`fresh_heartbeat_paused`, exit 0); the retired probe was the cover for a dark pipeline pre-arm only. The Phase 0 gate is the protection; do not skip it because the brief already recorded it.
- Never hand-edit `alert-reference.json` or `model.likec4.json` (generated); a hand edit passes locally and reds in CI.
- `*.tsv` / `*.tsv.n` rows are tab-separated; remove with an exact-match line filter, not an editor reflow, and keep each file's trailing newline. A stray space breaks the shard-totality parse.
- The first deleted-script grep must also cover `scripts/*.tsv.n` (the strays), or the residual-zero AC fails on files nobody opened.
- A plan or PR text containing the strings `Closes`, `Fixes` or `Resolves` followed by an issue number (including inside quoted prose) arms auto-close; this plan keeps them out and the scan re-asserts.
- A plan whose `## User-Brand Impact` is empty fails deepen-plan Phase 4.6; it is filled here.

## References

- Parent plan Phase 7: `knowledge-base/project/plans/2026-10-11-feat-inngest-probe-heartbeat-feeder-plan.md`
- Arming and read-back: `knowledge-base/engineering/operations/runbooks/inngest-server.md` § "Arming the probe heartbeat (#9703)"
- Two-PR rule: `apps/web-platform/infra/sentry/README.md` § "Adding or removing a cron monitor"
- Follow-through convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
- Decisions: `knowledge-base/project/specs/feat-one-shot-9703-stage-3b-retire-8296-probe/decision-challenges.md`
