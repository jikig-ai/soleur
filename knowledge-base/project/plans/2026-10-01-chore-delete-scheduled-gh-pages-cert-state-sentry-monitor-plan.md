---
title: "chore(sentry): delete the disabled scheduled-gh-pages-cert-state cron monitor (PR B of cert-state removal)"
date: 2026-10-01
slug: delete-scheduled-gh-pages-cert-state-sentry-monitor
branch: feat-one-shot-9304-delete-gh-pages-cert-state-monitor
issue: 9304
closes: 9304
type: chore
lane: cross-domain
---

# chore(sentry): delete the disabled scheduled-gh-pages-cert-state cron monitor

Spec lacks a valid `lane:` (no spec.md for this branch), so it is defaulted to `cross-domain` (TR2 fail-closed).

## Overview

PR B of the two-PR removal of the obsolete `cron-gh-pages-cert-state` routine. PR A (#9303, merge
`b2cebec0d6`) deleted the Inngest function and moved the Sentry monitor out of
`sentry_alert.cron_monitor_failure.monitor_ids` into `local.cron_monitor_alert_unrouted`. This PR deletes the
monitor itself: `sentry_cron_monitor.scheduled_gh_pages_cert_state` (slug `scheduled-gh-pages-cert-state`,
Sentry detector `1227831`), then updates every ledger that cites it. Production effect: one disabled Sentry
cron monitor destroyed by the post-merge Sentry apply, no deploy. The PR is a destroy, so a commit BODY on this
branch carries a line-anchored `[ack-destroy]`, which the operator approved in chat ("PR-B approved").

The monitor has been `enabled = false` since #7640, and ADR-194 abandoned the GitHub Pages origin certificate it
measured. Nothing checks in, and (measured below) no workflow binds it, so nothing pages on its removal.

## Research Reconciliation — Spec vs. Codebase

The brief's checklist is a subset of what the #9304 body and current `main` require. Three counts drifted since the
issue was written, because #9280 landed a 61st monitor (`scheduled_bot_pr_reaper`) after the issue was filed.

| Claim (brief / #9304 body) | Reality on `main` at `feada5c8e3` | Plan response |
|---|---|---|
| README has two `60` citations; `model.c4` becomes `59/16/43` | README cites **61** twice (lines 39, 165); the tf root declares **61** monitors (59 routed + 2 unrouted: reaper + cert-state). `model.c4` reads `Of 61 cron monitors, 16 ... 45 from webapp` | Targets are **61 -> 60** and `45 -> 44` (60 total, 16 GHA, 44 webapp). Do not apply the issue's literal `59/43`; `c4-count-parity` and T25 derive from the tf root and would red |
| "live Sentry confirms the alert binds 59 detectors" | Re-measured read-only today: workflow `cron-monitor-failure` (id 1297055) binds **59** detectorIds, `1227831` not among them; `alert-reference.json` also shows 59 and contains no `1227831`. 59 is correct because 2 of 61 monitors are unrouted, not because only cert-state is | Premise holds; recorded as the AC0 evidence. Re-run it right before pushing |
| "PR A's apply run on main is green" (issue precondition) | The push run on `b2cebec0d6` (36763579355) was **cancelled** (superseded by the next push), not green. The next two main push runs (`5cf26ec176`, `0ffabfc083`) succeeded, and the plan is FULL-ROOT (#6589), so they applied PR A's unroute. Live state (59, no `1227831`) is the proof | Precondition is satisfied by live state, not by that run. Do not wait on a run that will never go green |
| Checklist (4): fixture `tfplan-sentry-real-baseline.json` "still contains the monitor" | True (lines 234-269) but it is a point-in-time **redacted capture** used only as a "no-op plan yields 0 destroys / 0 creates" regression anchor (T4, T9 in `tests/scripts/test-destroy-guard-counter-sentry.sh`); no test couples it to the live tf root | **Leave unchanged.** Hand-editing a "real capture" breaks its provenance and buys nothing; re-capture needs Doppler + a live `terraform plan` |
| Checklist (6): regenerate `alert-reference.json` "only if the plan_pr gate requires it" | Deleting a resource that is already absent from `monitor_ids` changes no projected `detectorIds` (both sides read 59 today) | **No regeneration expected.** If the `plan_pr` gate nonetheless reds, regenerate from the `sentry-alert-reference-expected-<run>` artifact per the README recipe |
| Brief omits the count ledgers and the Art. 30 note | #9304 body requires them: README x2, `sentry-monitors-audit.sh` T25 comment, `model.c4` x2 clauses + `model.likec4.json`, `article-30-register.md` supersession note | All are in scope below (Phases 3 and 5) |
| "`[ack-destroy]` on the PR" | The gate reads **branch commit messages**, not the PR body: `sentry-squash-ack-detect.sh` emulates the squash body, and an ack as a commit *subject* is rendered `* [ack-destroy]` and does not survive | Put `[ack-destroy]` alone on its own line in a commit **body**. A PR-body-only ack does nothing |

## Research Insights

**Premise validation (Phase 0.6).** #9304 is OPEN with no closing PR; #9303 is MERGED (`b2cebec0d6`) and is an
ancestor of `HEAD`. The resource, its `cron_monitor_alert_unrouted` key and the `NON_INNGEST_MONITORS` entry all
exist on `main`. No proposed mechanism appears in the ADR corpus as a rejected alternative: ADR-031 (#8630
amendment) and the Sentry README prescribe exactly this two-PR shape. Stale-premise findings: the precondition run
was cancelled rather than green, and three counts are off by one (table above).

**Property list (Phase 0.6b).**

1. The live Sentry org no longer holds a `scheduled-gh-pages-cert-state` monitor after merge, and the terraform
   plan that deletes it shows exactly one destroy and zero adds or other changes.
2. No declared-state ledger (tf, tests, count prose, C4, register) cites the deleted monitor as live or as a
   precedent that no longer resolves.
3. The destroy is acknowledged by the one mechanism the gate reads. The ack is a blanket token (it names no
   address and no count), so it authorises whatever the full-root plan at merge time contains; the PR-time manifest
   (AC4) is the only per-resource check, and the merge-time re-check in Phase 5 keeps that manifest true.

**Cut list.** Every mechanism the ask names buys a property above or is a required ledger edit; cuts of
tempting extras:

- Re-capturing `tfplan-sentry-real-baseline.json` -> buys nothing (property 2 concerns declared state; the fixture
  is a historical capture) -> its provenance and the T4/T9 anchors already cover it.
- Regenerating `alert-reference.json` unconditionally -> no projected change -> only on a red `plan_pr` gate.
- A new test for "monitor absent" -> already covered by the `(c3)` reverse guard in `function-registry-count`
  and routing-parity Guard 1 row 11 (an unrouted entry naming no declared monitor).
- Rewriting historical prose (ADR-125, runbooks, learnings, post-mortem, `uptime-alerts.tf` comment, the
  `cron-inngest-cron-watchdog.ts` and `oneshot-4650-monitor-close.ts` comments) -> they narrate history and
  already read as past tense; none dangles on a resolvable symbol.

**Institutional learnings applied.** The squash-ack composition rule (`apply-sentry-infra.yml` destroy gate and
`scripts/sentry-squash-ack-detect.sh`); the Sentry README two-PR rule; "cite a content anchor, not a line number"
(`cq-cite-content-anchor-not-line-number`): the line numbers in this plan are orientation only, the edit sites are
named by their content.

**Per-item live infra check (`hr-bulk-delete-per-item-live-infra-role-check`).** Read-only probe, run 2026-10-01
via Doppler `prd`: detector `1227831` is `scheduled-gh-pages-cert-state`, type `monitor_check_in_failure`,
`enabled: false`, `workflowIds: []`; the org-wide workflows listing shows **no** workflow binding `1227831`. One
item, no other role.


## Open Code-Review Overlap

One open `code-review` issue touches a planned file: **#8595** (`function-registry-count.test.ts`: reverse-direction
guard for stale `NON_INNGEST_MONITORS` entries plus a cadence-parity gap). **Acknowledge.** Its first acceptance
criterion is already satisfied by the `(c3)` guard PR A added; the cadence-parity half is a separate concern. This PR
does not close it and does not touch it.

## Files to Edit

Paths are relative to the worktree root. Edit sites are named by content, not line number.

1. `apps/web-platform/infra/sentry/cron-monitors.tf`
   - Delete the `# scheduled-gh-pages-cert-state: RETIRED ...` comment block and the
     `resource "sentry_cron_monitor" "scheduled_gh_pages_cert_state"` block (contiguous, between
     `scheduled_community_monitor` and the `TR9 PR-6 (closes #4416)` comment).
   - Precedent comment 1 (inside `scheduled_follow_through`): "30-min margin per Inngest-fired precedent
     (scheduled_daily_triage above + PR-γ #4006's scheduled_gh_pages_cert_state)" -> drop the `+ PR-γ ...` clause so
     it cites `scheduled_daily_triage above` only.
   - Precedent comment 2 (above `scheduled_strategy_review`): "tighter than the GHA-era 240-min margin
     (cf. scheduled_gh_pages_cert_state) because Inngest has minimal jitter" -> delete only the `(cf. ...)`
     parenthetical. The sentence stands without it; do not invent a replacement anchor.
   - Header line "Daily/weekly monitors use 30-240 min as their observed jitter dictates.": the deleted monitor holds the
     only `checkin_margin_minutes = 240` in the file, so the upper bound becomes false. Replace `240` with the real
     maximum, derived rather than guessed:
     `awk '/checkin_margin_minutes/{print $3}' apps/web-platform/infra/sentry/cron-monitors.tf | sort -n | tail -1`.
   - After the edit, `grep -n 'gh_pages_cert_state\|gh-pages-cert-state' apps/web-platform/infra/sentry/cron-monitors.tf`
     prints nothing.
2. `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`: delete the `scheduled_gh_pages_cert_state = "disabled, ...
   (#9304)"` entry from `local.cron_monitor_alert_unrouted`; the map keeps one entry (`scheduled_bot_pr_reaper`).
3. `apps/web-platform/test/server/inngest/function-registry-count.test.ts`: delete the `// TEMPORARY (#9304): ...`
   comment and the `"scheduled-gh-pages-cert-state",` element at the end of `NON_INNGEST_MONITORS`. Leave the
   historical `70 -> 69` ledger comment in test `(a)` (the function count is unchanged by this PR).
4. `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts` (comment-only; operator checklist
   item 5): in the banner above `cfFetch`, "mirroring cf-cache-purge.ts (Bearer + AbortController) +
   cron-gh-pages-cert-state.ts." -> drop the `+ cron-gh-pages-cert-state.ts` clause and stop at `cf-cache-purge.ts`.
5. `apps/web-platform/infra/sentry/README.md`: the two `**61 cron monitors**` / `declares **61** of them` citations
   become `60` (T25 requires `**<n> cron monitors**` verbatim).
6. `apps/web-platform/scripts/sentry-monitors-audit.sh` (comment-only): in the "Addendum 2026-09-17 (extended ...)"
   comment, `61 \`resource "sentry_cron_monitor"\` blocks` -> `60 ...` (T25 greps that exact string on one line), add a
   short clause that #9304 deleted `scheduled-gh-pages-cert-state` (net 60) so the add-by-add narrative still sums,
   and "silently promoted to 61" -> 60.
7. `knowledge-base/engineering/architecture/diagrams/model.c4`: on `github -> sentry`, `Of 61 cron monitors, 16 check
   in from here and 45 from webapp` -> `Of 60 ... 44 from webapp` (gated: `c4-count-parity` rows C4 and C6); on
   `webapp -> sentry`, the ungated `45 Inngest-substrate sentry_cron_monitors` -> `44`. The ungated one has no CI
   backstop, so derive it: it equals the C6 webapp figure (monitors minus GHA check-in slugs = 60 - 16 = 44), and
   say so in the commit body.
8. `knowledge-base/engineering/architecture/diagrams/model.likec4.json`: each of the two edge `title` strings appears
   exactly once, so apply the same three substitutions (61->60, 45->44 twice) with a deterministic `sed`, then rely on
   CI `c4-model-freshness` (byte-diff against a fresh `likec4@1.50.0` render) as the check. `git diff --stat` must
   show only those two lines changed. (`scripts/regenerate-c4-model.sh` is the alternative if the CLI is available.)
9. `knowledge-base/legal/article-30-register.md`: immediately after the 2026-05-19 monitor-inventory bracket
   (`... added since: \`scheduled-follow-through\`, \`scheduled-gh-pages-cert-state\`).]**`) append a dated
   `**[2026-10-01 SUPERSESSION (#9304): ...]**` note in the register's bracket style: the monitor was retired
   (producer deleted in #9303, ADR-194) and deleted from the Sentry org; the inventory is one monitor smaller; no
   personal data, recipient or category changes. Do NOT rewrite the 2026-05-19 sentence; do not bump `last_reviewed`.
   Rationale for keeping it: the issue body lists it, and the register must not present a deleted monitor as
   current without a dated pointer.

## Files to Create

None. (`tasks.md` is produced by the plan workflow.)

## Files Deliberately NOT Edited

- `tests/scripts/fixtures/tfplan-sentry-real-baseline.json` — redacted historical capture, independent of the live
  tf root (Reconciliation row 4).
- `apps/web-platform/infra/sentry/alert-reference.json` — no projected change expected (row 5).
- `scripts/followthroughs/inngest-soak-6178.sh` (`RETIRED_IDS`) — the #6178 dedicated-host probe needs no edit
  (measured on #9304: the deleted function was an event-driven id, not one of the 52 cron ids in the population).
- ADR-194's 2026-09-30 addendum, ADR-125, the runbooks, learnings, the post-mortem and the other history comments
  (`uptime-alerts.tf`, `cron-inngest-cron-watchdog.ts`, `oneshot-4650-monitor-close.ts`,
  `cron-safe-commit-parity.test.ts`, `cron-shared.test.ts`) — they narrate the monitor as it was and none parses
  its name.

## Implementation Phases

### Phase 0 — Pre-flight (the one live gate; run right before the first commit)

1. Re-run the read-only live probe and assert `detectors == 59` and `cert_state == false`; if it reads
   `cert_state: true`, STOP, because PR A's unroute has not applied and this PR must not delete:
   `doppler run --project soleur --config prd --command 'curl -s -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/workflows/" | jq -c ".[] | select(.name==\"cron-monitor-failure\") | {detectors: (.detectorIds|length), cert_state: ((.detectorIds|index(\"1227831\"))!=null)}"'`
2. Baseline: the tf-root monitor count prints 61
   (`grep -hoE '^resource "sentry_cron_monitor" "[a-z0-9_]+"' apps/web-platform/infra/sentry/*.tf | wc -l`).

### Phase 1 — The destroy commit (files 1, 2, 3 together)

Terraform, the unrouted entry and the registry test change in ONE commit: routing-parity and `(c3)` each fail on
the `.tf` change alone, so no intermediate commit may carry a partial set. Commit message: subject
`chore(sentry): delete the retired scheduled-gh-pages-cert-state monitor`; blank line; a body line that is exactly
`[ack-destroy]` (alone on its line, never in the subject); a separate prose line recording the approval
(`operator-approved 2026-10-01 in session; scope: exactly 1 destroy, sentry_cron_monitor.scheduled_gh_pages_cert_state`);
then the attribution trailer. Before the first push, run the squash emulation on the branch messages
(`git log --reverse --format='%B%x00' origin/main..HEAD | jq -Rs 'split("\u0000") | map(select(length > 1))' | bash scripts/sentry-squash-ack-detect.sh; echo "exit=$?"`;
the script reads a JSON array of commit messages, oldest first, and exits 0 when the composed squash body carries the
line-anchored ack) so a misplaced ack costs seconds, not a CI cycle.

### Phase 2 — Count ledgers (files 5, 6, 7, 8, one commit)

Targets: 60 monitors, 16 from GitHub, 44 from webapp. `model.likec4.json` last, from the edited `model.c4`.

### Phase 3 — Comment and register hygiene (files 4, 9, one commit)

### Phase 4 — Verify and ship

The operator asked to skip the local battery and rely on CI, so local verification is only the Phase 0 probe and the
two greps in AC1. CI is the authority (Acceptance Criteria).

**PR body.** First line states the production effect: `Deletes one disabled Sentry cron monitor (scheduled-gh-pages-cert-state); no deploy.`
Then `Closes #9304`. No soak or post-deploy-verify wording, no `knowledge-base/project/plans|specs` paths (the
soak-followthrough gate reads cited plans). Attribution line per the session reminder.

**Before merging.** Re-check that nothing else landed under the Sentry tree since the PR plan ran:
`git log origin/main -- apps/web-platform/infra/sentry tests/scripts/lib/destroy-guard-filter-sentry.jq tests/scripts/lib/sentry-alert-projection.jq`
against the PR base. The ack is blanket, so a second destroy merged in between would ride under it.

**Merge path.** Prefer the normal auto-merge. This diff touches `.tf`/`.ts`/`.sh`, so the settle-then-admin-merge
classifier will print `NOT eligible` for the agent-initiated hatch; an admin merge here is permitted only under the
operator's explicit authority via that reference's operator-authorized variant, which requires `admin-merge-ready.sh`
exit 0 on the exact head SHA with every required check green (`sentry-destroy-required` included — an admin merge
bypasses it, and a missing ack would otherwise surface only as a red post-merge apply). Never pass `--body` or
`--subject` overrides to the merge: the ack survives only in the default commit-message body composition.

### Phase 5 — Post-merge (the earlier push apply was cancelled; do not assume)

1. Locate the `apply-sentry-infra.yml` push run for the merge commit. Allow 30 minutes after merge for it to start
   and finish; poll with a Monitor-style loop, do not re-trigger while it is queued.
2. If it is `cancelled` or stuck `waiting` past the bound, FIRST run the live probe below. If the monitor is already
   gone, stop (nothing to recover). If it is still present, recover ONLY with `gh run rerun` on that ack-carrying run
   (never `workflow_dispatch`, which carries no commit message and so no ack), after checking that nothing newer
   landed under the Sentry tree (`git log <merge-sha>..origin/main -- apps/web-platform/infra/sentry`); if the log is
   non-empty, stop and surface it to the operator, because a rerun re-applies the OLD sha's config under the same
   blanket ack. A later main push run is NOT an alternative: it carries no ack, so it either plans the still-pending
   destroy and fails closed, or does not run at all (the `paths:` filter).
3. Prove the end state with the read-only probe (one PASS/FAIL line): `GET .../detectors/1227831/` returns 404 AND
   workflow `cron-monitor-failure` still reports `detectors == 59` (the count also proves `SENTRY_ORG` and
   `SENTRY_API_HOST` resolve, so the 404 is not a wrong-host artifact):
   `doppler run --project soleur --config prd --command 'H="Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN"; B="https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}"; c=$(curl -s -o /dev/null -w "%{http_code}" -H "$H" "$B/detectors/1227831/"); n=$(curl -s -H "$H" "$B/workflows/" | jq "[.[]|select(.name==\"cron-monitor-failure\")|.detectorIds|length]|first"); [ "$c" = 404 ] && [ "$n" = 59 ] && echo PASS || echo "FAIL detector=$c detectors=$n"'`
4. `Closes #9304` auto-closes the issue at merge, before this proof exists (the operator mandated that form). So the
   probe is a verification of an already-closed issue: on PASS, post the one-line result on #9304; on FAIL, reopen
   it and follow step 2. The next `scheduled-terraform-drift.yml` Sentry leg is an advisory backstop only.

## Acceptance Criteria

- [ ] AC1 — `grep -rn 'scheduled_gh_pages_cert_state' apps/web-platform/infra/sentry/` and
  `grep -n 'scheduled-gh-pages-cert-state' apps/web-platform/test/server/inngest/function-registry-count.test.ts`
  print nothing; `cron_monitor_alert_unrouted` has exactly one entry (`scheduled_bot_pr_reaper`).
- [ ] AC2 — the two margin-precedent comments no longer cite the deleted resource, and the `30-240` header bound
  matches the file's real maximum margin.
- [ ] AC3 — counts read 60 / 16 / 44 everywhere they are cited (README x2, audit-script comment, `model.c4` x3,
  `model.likec4.json` x3) and the Art. 30 register carries the dated note with the 2026-05-19 sentence untouched.
- [ ] AC4 — the Terraform plan on the PR shows exactly `1 to destroy` (`sentry_cron_monitor.scheduled_gh_pages_cert_state`),
  `0 to add`, no other destroy or forget; the destroy-gate manifest lists only that address; and the ack is a
  line-anchored `[ack-destroy]` in a branch commit body (never a subject, never PR-body-only).
- [ ] AC5 — all required CI checks are green on the exact head SHA, which covers routing-parity Guard 1, `(c2)`/`(c3)`,
  T25, `c4-count-parity`, `c4-model-freshness`, `lint-legal-registers` and `sentry-destroy-required`; the
  `plan_pr` reference gate is green without a regenerated `alert-reference.json` (regenerate from its artifact only if
  it reds).
- [ ] AC6 — `cron-gh-pages-cert-reissue.ts` differs from `main` by comments only, and no tracked file outside the
  "Files Deliberately NOT Edited" history set still names the deleted monitor as live.
- [ ] AC7 — the PR body has the Phase 4 first line, `Closes #9304`, and no soak/post-deploy wording or plan/spec paths.
- [ ] AC8 — after merge, the Phase 5 probe prints `PASS` (detector 404, 59 detectors bound), and the `sentry-monitors-audit`
  Class A warning for this detector is absent from the first audit run after the apply.

## Risks and Sharp Edges

- **A subject-line ack is a silent miss.** GitHub renders a commit subject as `* [ack-destroy]` in the squash body,
  which breaks the line anchor; a wrong placement costs a CI cycle and, worse, a red post-merge apply on `main`.
  Hence the Phase 1 emulation run.
- **The ack is blanket.** It names no resource and no count; AC4's manifest and the Phase 4 "before merging" re-check
  are the only per-resource controls.
- **A stalled or cancelled apply is not a failed destroy, and a later run is not a substitute.** See Phase 5; only
  live Sentry state proves the end state.
- **Off-by-one counts.** The issue's `59/43` targets predate #9280's reaper monitor. Derive, do not copy: 60 / 16 / 44.
  The `webapp -> sentry` 44 is the only ungated count.
- **History greps match history.** Do not "clean" ADR-125, runbooks, learnings or the post-mortem.
- **No `terraform apply` locally** (`use_lockfile = false` on this root); CI applies on merge.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will
  fail `deepen-plan` Phase 4.6. This one is filled below.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The monitor is disabled and routes to nobody;
the realistic failure is a red post-merge Sentry apply on `main` (an operator/CI-facing event) that blocks later
Sentry changes until fixed.

**If this leaks, the user's data / workflow / money is exposed via:** no vector. The change removes a monitor and
edits prose and count comments; it handles no credentials or user data. The read-only probes use the existing
Doppler-held IaC token and print only ids and counts.

**Brand-survival threshold:** none

`threshold: none, reason: deletion of a disabled, unbound monitoring object whose producer is already deleted; no user data, auth or billing path is touched, and the operator explicitly approved the destroy.`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. The Art. 30 register edit is an appended,
dated inventory note; it adds no processing activity, recipient or data category, so no GDPR gate or CLO review is
required.

## Architecture Decision (ADR/C4)

No new architectural decision: this executes the two-PR removal that ADR-031 (#8630 amendment) prescribes and ADR-194
records. C4: the rubric (external actors, systems, containers, access relationships) was checked against `model.c4` —
the actors (operator, GitHub, Sentry) and the `github -> sentry` / `webapp -> sentry` edges are unchanged; only the
derived cardinalities embedded in edge prose move (61 -> 60, 45 -> 44), which Files to Edit 7-8 handle and
`plugins/soleur/test/c4-count-parity.test.sh` gates.

## Test Scenarios

No new test is authored; each guard already covers its arm. Reasoned mutation sanity: re-adding the
`NON_INNGEST_MONITORS` entry reds `(c3)`; leaving the unrouted entry reds Guard 1 row 11; dropping the ack reds
`sentry-destroy-required`; a stale count reds T25 or `c4-count-parity`.

Observability is skipped (deletes-only, no new code or infra surface); the Phase 5 probe is the post-merge
liveness evidence, run without SSH.
