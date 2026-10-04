---
title: "chore: Zot / ADR-096 wrap-up - close #9391 with evidence and supersede the pre-apply docs"
type: chore
date: 2026-10-04
slug: zot-adr096-wrapup-close-9391-and-supersede-notes
branch: feat-one-shot-zot-adr096-wrapup-docs-9391
issue: 9391
closes: none
lane: cross-domain
brand_survival_threshold: none
---

# chore: Zot / ADR-096 wrap-up - close #9391 with evidence and supersede the pre-apply docs

Spec lacks valid lane: - defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-04
**Sections enhanced:** 4 (Premise Validation, Phase 1, Risks, Acceptance Criteria checks)
**Method:** halting gates 4.6-4.12 run mechanically; Quality Checks citations verified live. The 40-agent review fan-out was deliberately not run for a two-file, additions-only docs plan (disclosed in the Session Summary); the facts that could be wrong (run log lines, workflow state, alert state, ancestry, issue states) were each re-read from the live source instead.

### Key Improvements
1. SSH-bridge delivery is now backed by the run's own log line (`Apply complete! Resources: 2 added, 0 changed, 2 destroyed.`, 14:37:06Z), not only by step names; the non-SSH line (`7 added, 0 changed, 0 destroyed`, 14:35:39Z) is confirmed too.
2. Ancestry verified: `2afe2e1746` (#9451, resolver and loader edits) and `7a58d1935b` (#9448, web LUKS passphrase) are both ancestors of the apply SHA `9e6412fb3`, so the note's claims about what the run carried hold.
3. AC6 is satisfiable: the last `workspaces-luks-cutover.yml` run is 2026-09-30 (before the apply), so "no run after 2026-10-04T14:00Z" holds today.
4. Citation hygiene: #7539 and #9274 are cited as the runbook and `.tf` comments cite them, with their actual state noted, rather than as independent facts.

### Gate Results
- 4.6 User-Brand Impact: present, threshold `none`, diff has no sensitive path (knowledge-base only). Pass.
- 4.7 Observability: pure-docs diff, skipped by its own Step 1.
- 4.8 PAT-shaped variable: zero hits. Pass.
- 4.9 UI wireframe: no UI-surface file. Skipped.
- 4.10 Encryption posture: no `.tf`/migration/cloud-init in the diff and no store or connection introduced (the plaintext workspaces volume is named only as untouched). Skipped.
- 4.11 Guard contract: no guard in the deliverable. Skipped.
- 4.12 Scope check: exactly one unfenced `## Scope Check`, one `Recommendation:` line, no `status: BLOCKED`, no `unmapped` status; the two `inferred` rows carry dependency/safety justifications. Pass.
- Rule IDs cited (`hr-before-asserting-github-issue-status`, `hr-menu-option-ack-not-prod-write-auth`, `hr-never-run-commands-with-unbounded-output`) each match one `[id: ...]` in AGENTS.md.
- tasks.md: no deepen correction changes its content; no propagation needed.

## Overview

ADR-096 and ADR-190 are Accepted, both ADR-096 implementation PRs are merged and deployed, and
the production apply run 37209725107 (workflow_dispatch `manual-rerun` on main `9e6412fb3`,
success, 14:33Z to 14:37Z on 2026-10-04) delivered the web-1 half of the egress carve plus the
Better Stack alert. What is left is bookkeeping with evidence:

1. Prove the #9391 alert is live and unpaused through the same reader the drift reconciler uses,
   run the runbook's `ghcr_deny_rows` decode with the `=1` positive controls first, then close
   #9391 with an evidence comment. No code change.
2. One small docs-only PR (draft #9487) that APPENDS dated superseding notes to the two documents
   whose text describes the pre-apply state: the runbook section "Known residual: web-1 until the
   apply workflow runs" and the ADR-218 "Merge consequence" bullet. Nothing existing is rewritten.
3. Read-and-report only: #9393, #9390, #9291.
4. Explain the monitor-audit warning "2 cron detectors bound to no workflow" (report only).

Hard constraints carried into every phase: the web-1 plaintext wipe must not happen
(`workspaces-luks-cutover.yml` with `wipe_plaintext=true` is dispatch-only and is never
dispatched here); no commit body contains an `[ack-destroy]` line; no apply workflow is enabled or
dispatched by this plan (the one-time approval for run 37209725107 is spent); no `web-host-replace`.

## Premise Validation (Phase 0.6)

Checked live on 2026-10-04 (15:0xZ):

| Premise | Result |
|---|---|
| #9391, #9393, #9390, #9291, #9372 are open | Held. All five OPEN. #9391 is still open, so closing it is in scope. |
| Draft PR #9487 exists, no files yet | Held. `OPEN draft=true files=[]`; branch is 1 ahead / 0 behind `origin/main`. |
| `apply-web-platform-infra.yml` is `disabled_manually` | Held. `gh api .../actions/workflows/apply-web-platform-infra.yml` reads `disabled_manually`, `updated_at` 2026-10-04T16:37:48+02:00 (= 14:37:48Z, right after the run). `apply-deploy-pipeline-fix.yml` reads `active` (updated 09:26+02:00). |
| Run 37209725107 is a success on `9e6412fb3` | Held: `success 9e6412fb34... workflow_dispatch 14:33:54Z-14:37:14Z`. `2afe2e1746` (#9451, resolver and loader edits) is an ancestor of `9e6412fb3`, so the removal trigger's "after the resolver and loader changes" clause holds. |
| The SSH apply step ran (not a green-skip, the runbook's caveat citing #7539, whose own title is about the `[ack-destroy]` guard) | Held on step names: `CF Tunnel SSH bridge (gated)` and `Terraform apply (SSH-provisioned resources, over the bridge)` both concluded `success`, not `skipped`; non-SSH step logged `Apply complete! Resources: 7 added, 0 changed, 0 destroyed.` Phase 1 re-reads the SSH step's own "Apply complete" line before it is cited. |
| Alert exists live | Held: Better Stack API lists `soleur-ghcr-hostsfile-deny-lost-prd`, `paused=false`, `created_at` 2026-10-04T14:35:37Z (inside the run). |
| The 06:00/18:00 drift reconcile already reads it | Stale as a premise. The last two reconcile runs (06:01Z and 07:47Z, both `workflow_dispatch` by the Inngest dispatcher) predate the alert (created 14:35Z) and print `surface=logs_alert declared=9 live=10`. The first run that can see it is the 18:00Z run. See Phase 1 for how the evidence is obtained without waiting. |
| ADR corpus: is "docs-only supersede notes" an ADR-rejected mechanism? | No. ADR-218's own convention is dated `## Amendment` sections and the runbook already uses dated blockquote notes. No ADR is created or changed in substance. |

## Property List and Cut List (Phase 0.6b)

Properties the ask actually needs:

- P1. A reader can see, from #9391 itself, proof that the alert is live and unpaused and that no
  host currently reports `ghcr_blocked=0`.
- P2. A reader of the runbook or ADR-218 is not misled into thinking web-1 still lacks the carve,
  resolver, probe and alert, and the pre-apply history stays readable.
- P3. The still-true residuals stay visible: web-2 waits for the #9372 rebirth, the apply workflow
  is paused again, #9393 stays open.

Mechanisms proposed in the ask and what they buy: reading the reconciler arm (P1), the optional
decode with positive controls (P1), appended dated notes (P2, P3), `gh issue close` (P1).

Cut list: no new script, test or workflow. A "wait for the 18:00Z scheduled reconcile" gate is cut
as a blocker (the identical script is run read-only now; the 18:00Z run is cited only if it has
already happened by ship time). A code fix for the audit warning is cut (Phase 4: needs the audit
script to learn the declared-unrouted map, a cross-file change with a 2364-line test beside it, not
inline-small).

## Research Insights

- Reconciler arm: `.github/workflows/scheduled-terraform-drift.yml`, job `heartbeat-live-reconcile`
  (line 1405), step "Reconcile live heartbeats" runs
  `bun plugins/soleur/scripts/reconcile-live-heartbeats.ts` with `BETTERSTACK_API_TOKEN` taken from
  Doppler `soleur/prd_terraform` secret `BETTERSTACK_API_TOKEN_READONLY` (GET-only). The
  `logs_alert` arm prints `SOLEUR_HEARTBEAT_RECONCILE_OK surface=logs_alert declared=N live=M` and,
  per problem, `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=<n> live=logs_alert reason=logs-alert-paused|logs-alert-absent ...`.
  Healthy output has no MISMATCH row for the alert's name.
- Plan-time dry reading (same script, same token, run locally, rc=0):
  `surface=logs_alert declared=10 live=11`, no MISMATCH. The extra live alert is the old hand-made
  "Output utilization high" (paused, created 2026-05-21), not a #9391 matter; the arm only checks
  declared-vs-live in one direction. The pre-apply count was `declared=9 live=10`, so declared
  moved 9 to 10 exactly as the tenth alert predicts (ADR-218 "Count. Ten Logs alerts now apply").
- Direct API read: `soleur-ghcr-hostsfile-deny-lost-prd paused=false created=2026-10-04T14:35:37.180Z`.
- Runbook decode: `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`, section
  "Hosts-file deny lost (Better Stack alert)", function `ghcr_deny_rows` (lines 549-560) and the
  four calls (lines 561-564). Positive controls first: `=1` web and `=1` registry; an empty `=0`
  result means nothing unless the matching `=1` query returns rows for the host asked about.
  The web arm is a sample taken when `ci-deploy.sh` runs, so a web host with no deploy in the
  window legitimately has no `=1` row; that is a finding to record, never a reason to trigger a
  deploy.
- Docs targets (anchors, not line numbers): runbook heading `### Known residual: web-1 until the
  apply workflow runs` (its removal-trigger sentence reads "first green `apply-web-platform-infra.yml`
  run whose SSH apply step ran after the resolver and loader changes"); runbook heading
  `### Known residual: running web-2` (its sentence "#9393 also needs the web-1 apply to close");
  ADR-218 bullet `**Merge consequence.**` inside `## Amendment - 2026-10-04 (#9391): the tenth Logs alert`,
  which is the last section of the file.
- Tests that read the runbook: `apps/web-platform/test/infra/ghcr-blocked-alert.test.sh` (asserts
  the `#hosts-file-deny-lost-better-stack-alert` heading slug resolves and that
  `.github/workflows/infra-validation.yml` lists the runbook path once; mutation copies of the
  runbook) and `apps/web-platform/infra/cron-egress-firewall.test.sh` (every sentinel name is
  documented in the runbook). Additions-only edits outside the "Hosts-file deny lost" section keep
  both green; the PR will run `infra-validation.yml` because the runbook path is in its filter.
- Code-review overlap: `jq` over open `code-review` issue bodies for `cron-egress-blocked.md` and
  `ADR-218` returned nothing.
- Learnings applied: `hr-before-asserting-github-issue-status` (read issue state live before the
  close), `hr-menu-option-ack-not-prod-write-auth` (the spent apply approval is not reused),
  `hr-never-run-commands-with-unbounded-output` (decode piped through `head`/`wc -l`).

## Research Reconciliation - Spec vs. Codebase

| Claim in the brief | Reality | Plan response |
|---|---|---|
| "the 06:00 and 18:00 UTC runs ... look for logs-alert-absent / logs-alert-paused" | No run after the apply has happened yet (next is 18:00Z, ~3h out). Earlier runs predate the alert. The markers only print when something is wrong; the healthy signal is the `surface=logs_alert declared=10` OK line and the absence of a MISMATCH row. | Phase 1 reads the identical script live now and cites the 18:00Z run only if it exists by ship time. |
| "2 cron detectors bound to no workflow" warning | Emitted by `apps/web-platform/scripts/sentry-monitors-audit.sh` (line 1560), surfaced on `apply-sentry-infra.yml` and `sentry-audit-gate.yml` runs. | Phase 4 report. |
| ADR-218 "Merge consequence" "describes the pre-apply state" | True: "when it is disabled, no apply runs and the alert stays absent". Live: the alert exists. | Append a dated note; do not edit the bullet. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing; a wrong note would mislead the
next on-call reader of a runbook about whether web-1 has the egress carve (a stale "not delivered"
would prompt a needless production-apply approval request).

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The
notes cite a public run id, resource names and commit SHAs only; no secret, token value or host
address is written (the Doppler token is read into a shell variable and never printed or logged).

**Brand-survival threshold:** none. threshold: none, reason: the diff is two knowledge-base markdown
files with additions only, no sensitive path (schema, auth, API route, workflow) is touched.

## Architecture Decision (ADR/C4)

Skipped by the gate's own test: no architectural decision is made or changed. ADR-218 gets a dated
status note only (its existing amendment convention), not a new decision; no C4 element, actor,
system or relationship changes (docs-only; the derived-count gate `c4-count-parity` is untouched
because no `.tf`, workflow or monitor count moves).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - infrastructure bookkeeping and documentation. (Engineering
runbook and ADR text only; no legal, marketing, product, finance or support surface. Observability,
encryption-posture, guard-contract and GDPR gates do not fire: no code, infra, store, guard or
regulated-data file is in the diff.)

## Implementation Phases

### Phase 1 - Verify and close #9391 (read-only, then one `gh issue close`)

All commands start with `cd /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-zot-adr096-wrapup-docs-9391 &&`.
No secret is printed; tokens go into shell variables only.

1.1 Re-read state (guards against drift since this plan):
`gh issue view 9391 --json state,title -q .state` (must be OPEN, else skip to 1.6 with a note),
`gh api repos/jikig-ai/soleur/actions/workflows/apply-web-platform-infra.yml --jq '.state+" "+.updated_at'`,
`gh run view 37209725107 --json conclusion,headSha -q '.conclusion+" "+.headSha'`.

1.2 Confirm the SSH step really applied (so the docs note may say "delivered"):
`gh run view 37209725107 --log | grep -E "Apply complete"` expecting one line `7 added, 0 changed, 0 destroyed`
(non-SSH, 14:35:39Z) and one SSH-bridge line `Resources: 2 added, 0 changed, 2 destroyed.` (14:37:06Z; both confirmed at plan time). If the SSH line is
missing or says `0 added`, STOP: the note's delivery claim is unproven; report instead of writing
it.

1.3 Logs-alert arm reading (the reconciler's own reader, read-only token):
```bash
TOKEN=$(doppler secrets get BETTERSTACK_API_TOKEN_READONLY -p soleur -c prd_terraform --plain 2>/dev/null)
BETTERSTACK_API_TOKEN="$TOKEN" timeout 90 bun plugins/soleur/scripts/reconcile-live-heartbeats.ts 2>&1 | cut -c1-300 | head -20
```
Expected literals: `SOLEUR_HEARTBEAT_RECONCILE_OK surface=logs_alert declared=10`, and NO line containing
`logs-alert-absent` or `logs-alert-paused`. Then the direct read:
`curl -s -H "Authorization: Bearer $TOKEN" "https://telemetry.betterstack.com/api/v2/alerts?per_page=50" | jq -r '.data[]|select(.attributes.name=="soleur-ghcr-hostsfile-deny-lost-prd")|"\(.attributes.name) paused=\(.attributes.paused)"'`
expecting `paused=false`. Unset `TOKEN` afterwards. If a later scheduled `heartbeat-live-reconcile`
run (18:00Z) already exists at ship time, also cite its `surface=logs_alert declared=10` line
(`gh run list --workflow=scheduled-terraform-drift.yml --limit 3`, then `gh run view <id> --log | grep "surface=logs_alert"`).

1.4 Runbook decode with positive controls (exact function from the runbook, copied into the shell;
every call piped through `wc -l` plus `head -5` so output stays bounded):
`ghcr_deny_rows 'GHCR_DENY ghcr_blocked=1' 1`, `ghcr_deny_rows 'SOLEUR_ZOT_DISK' 1` FIRST, then
`ghcr_deny_rows 'GHCR_DENY ghcr_blocked=0' 0` and `ghcr_deny_rows 'SOLEUR_ZOT_DISK' 0`. Pass: the
registry `=1` control returns rows (about 288 a day), the web `=1` control returns at least one
row, and both `=0` queries return zero rows. If the web `=1` control is empty for web-1, record
"web arm silent: no `ci-deploy` in the window" (a documented silent state), do not deploy to
manufacture a row, and do not treat empty `=0` as proof for that host. If any `=0` row appears,
that IS the alert's signal: do NOT close, comment the rows and follow the runbook's per-host repair
table (no SSH, no apply from this plan).

1.5 Post the evidence on #9391 (one comment): run id and link, the 1.2 apply lines, the 1.3 reconcile
OK line and `paused=false` line with alert creation time, the 1.4 row counts per query (counts and
host names only, no raw log rows), and the two honest caveats (web arm is a sample taken at
`ci-deploy`; ingest-dark is covered by `[ci/zot-telemetry-silent]` for the registry arm only).

1.6 `gh issue close 9391 --comment "<one line pointing at the evidence comment>" --reason completed`.
Closing an issue is not merge authority, spend or a destructive production action, so it needs no
operator approval. Verify with `gh issue view 9391 --json state -q .state` = CLOSED
(`hr-before-asserting-github-issue-status`).

Decision on closing mechanics: the PR body uses `Ref #9391`, NOT `Closes`. The evidence comment is
the closing event and exists before the PR merges; a `Closes` keyword would re-close an issue that
is already closed and would couple the close to a docs merge. (Contrast: `Closes` is right only when
evidence cannot be had before merge, which is not the case here.)

### Phase 2 - Append the superseding notes (docs only, additions only)

Edit exactly two files. Invariant, checked in Acceptance Criteria: `git diff --numstat origin/main`
shows 0 deleted lines for both.

2.1 `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`, directly under the
heading `### Known residual: web-1 until the apply workflow runs` and above the existing
`State observation 2026-10-04T12:20Z` blockquote, insert:

> **Superseded 2026-10-04 (delivered by apply run 37209725107; the text below is the pre-apply
> record and is kept unedited).** The web-1 half of this section's removal trigger has fired.
> `apply-web-platform-infra.yml` was enabled with the operator's approval, dispatched as
> `manual-rerun` on main `9e6412fb3`
> ([run 37209725107](https://github.com/jikig-ai/soleur/actions/runs/37209725107), success), and
> set back to `disabled_manually`. The non-SSH apply added 7, changed 0 and destroyed 0 resources,
> including Better Stack alert `soleur-ghcr-hostsfile-deny-lost-prd` and its exploration (#9391)
> and the web LUKS passphrase, header bucket and Doppler secrets (#9448). The SSH-bridge apply
> re-created `terraform_data.cron_egress_firewall` and `terraform_data.luks_monitor_install` (no
> host or volume), so the carve, resolver and probe are now on web-1, and the alert reads present
> and unpaused (evidence on #9391). The plaintext workspaces volume was not touched and no wipe
> ran. Still true: the workflow is paused again (read it live with the `gh api` command in the note
> below), so the paragraphs about a merge triggering no apply and about a pending registry replace
> that nothing re-fires apply whenever it reads `disabled_manually`; web-2 is unchanged and waits
> for the #9372 rebirth (#9393 stays open, no plain `web-host-replace`). In the "Hosts-file deny
> lost" section above, the clause "until the #9275 carve is delivered, #9393" is satisfied for
> web-1 only.

2.2 Same file, section `### Known residual: running web-2`, append ONE line at the end of that
section (a new paragraph after its last sentence "The closing event is the #9372 rebirth run."):

> *Update 2026-10-04: the web-1 apply that this section's header line waits on has run (run
> 37209725107, see the superseding note under "Known residual: web-1 until the apply workflow
> runs"); only the #9372 rebirth remains for #9393.*

2.3 `knowledge-base/engineering/architecture/decisions/ADR-218-...-logtail-provider.md`, append at the
end of the file (the end of the `## Amendment - 2026-10-04 (#9391)` section, after the
`**Enforcement.**` bullet) one new bullet, leaving the `**Merge consequence.**` bullet untouched:

> - **Merge consequence, update 2026-10-04.** The enabled-versus-disabled wording above describes
>   the pre-apply state. `apply-web-platform-infra.yml` was enabled once, dispatched as
>   `manual-rerun` on main `9e6412fb3` (run 37209725107, success), and set back to
>   `disabled_manually`; that run created `soleur-ghcr-hostsfile-deny-lost-prd` and its exploration
>   (7 added, 0 changed, 0 destroyed non-SSH) together with the backlog since the previous apply.
>   The drift reconciler's `logs_alert` arm reads declared 10 against live 11 with no
>   `logs-alert-absent` or `logs-alert-paused` row (the extra live alert is the hand-made, paused
>   "Output utilization high"). While the workflow is paused again, a later merge under
>   `apps/web-platform/infra/` triggers no apply, exactly as the bullet above says.

Check that the figure "declared 10 against live 11" is re-read in Phase 1.3 on the day of writing
and that the wording matches what that run printed; if it prints other numbers, write the numbers
it printed.

2.4 Preview locally: `markdownlint`/the repo's markdown lint is run by CI; locally only
`git diff --numstat origin/main` (0 deletions) and a render check of the two blockquotes. Do not run
full test batteries. Do not bump versions.

### Phase 3 - Ship the docs PR (existing draft #9487)

3.1 Commit (message ends `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` then the
Claude-Session trailer). The commit body contains no `[ack-destroy]` line and the diff touches no
file under `.github/workflows` or `apps/web-platform/infra`, so the agent merge path stays open
(had it touched a workflow, no agent admin-merge path would exist, and this plan would stop at
ready-for-review).

3.2 Push; mark the draft ready via the normal `soleur:ship` flow. PR title:
`docs(zot): record web-1 delivery by apply run 37209725107 (supersede pre-apply notes)`.
PR body: summary of the three appended notes, the Phase 3-report findings below (so the operator
sees them), `Ref #9391`, `Ref #9393`, and ends with the Generated-with-Claude-Code line. Do NOT sync
the branch with main unless required for merge: a BEHIND sync restarts a ~35 min CI cycle; the branch
is 0 behind now.

3.3 CI is the typecheck/lint authority (local `node_modules` is stale). Expected affected jobs:
`infra-validation.yml` (runs `ghcr-blocked-alert.test.sh` and the runbook-sentinel check because the
runbook path is in its filter), markdown lint, the ADR frontmatter/ordinal guard (no new ADR, so
unaffected).

### Phase 4 - Read-and-report (no edits)

Report these in the PR body and the final summary; nothing here changes a file:

- #9393 (OPEN, p3): web-1 half delivered by run 37209725107. web-2 is a weight-0 standby that keeps
  the old allow list and resolver and has no probe until the single-use gated volume rebirth
  (#9372, ADR-263). Never a plain `web-host-replace` (ADR-263's discriminate step refuses the live
  plaintext volume; a plain replace powers the host off). The #9372 image must be built from a commit
  that already includes #9451 (it does: `2afe2e1746` is an ancestor of main). The decision to run the
  rebirth belongs to the operator; #9393 closes on that rebirth run. Re-evaluate 2026-10-17.
- #9390 (OPEN, held): add `docker.pkg.github.com` to the host hosts-file deny at six byte-identical
  sites. Trigger (all of): the pause is lifted AND a registry render change is otherwise due or a
  standalone replace is authorized AND `scripts/registry-replace-preflight.sh` reads clean. None
  holds (workflow paused again). Re-read confirms the 2026-10-03 hold comment is still current;
  nothing implemented. Re-evaluate 2026-10-17 with #9393.
- #9291 (OPEN, `decision-challenge`, p3 question): surface only. The decision shipped by default
  (per-release `GHCR_DENY` evidence, not a heartbeat); no objection comment exists. Observation to
  surface: the new alert's web arm is the same per-`ci-deploy` sample, so it inherits the staleness
  #9291 describes (documented under "What this alert is silent about"). Ask the operator to confirm or
  object; no action taken.
- Monitor-audit warning "2 cron detectors bound to no workflow": emitted by
  `apps/web-platform/scripts/sentry-monitors-audit.sh` (the `routing_warn_parts` block, "Class A"),
  surfaced as a `::warning::` on `apply-sentry-infra.yml` and `sentry-audit-gate.yml` runs (e.g. run
  37192063039: `...2 cron detector(s) bound to no workflow ...: scheduled-bot-pr-reaper
  workspaces-luks-verify-web2; 5 monitor(s) muted ...`). Cause: those two monitors are deliberately
  listed in `cron_monitor_alert_unrouted` in `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`
  under the two-PR rule (per the `.tf` comments: #9274 for the reaper, #9372 for the web-2 soak-marker monitor; #9274 is itself CLOSED, so that citation is historical), so their
  detectors have `workflowIds: []` by design. The script counts every empty-`workflowIds` detector
  without consulting that map, so the warning cannot tell a declared pending route from live drift
  and fires on every run. Not fixed: making the audit read the `.tf` map and split "declared
  pending" from "undeclared" touches the audit script plus its 2364-line test and the report text,
  more than an inline fix; filing a tracking issue is blocked by the issue-filing hook below its
  size threshold, so it is noted in the PR body only. Follow-up trigger: route the two monitors
  (the reaper after the loop is measured; the web-2 monitor after its first measured check-in).
  Also visible in the same warning, not part of this ask: 5 monitors muted in at least one
  environment (`scheduled-anthropic-credit-probe`, `scheduled-bug-fixer`, `scheduled-daily-triage`,
  `scheduled-follow-through`, `scheduled-content-generator`); a mute is a Sentry write the provider
  cannot express, so it is reported, not fixed.

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` (two additions, no deletions)
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` (one appended bullet)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-zot-adr096-wrapup-docs-9391/tasks.md` (plan artifact)

## Open Code-Review Overlap

None (checked `cron-egress-blocked.md` and `ADR-218` against open `code-review` issue bodies).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "confirm the drift reconciler's logs-alert arm reads the alert present and unpaused" | Phase 1.3 | mapped |
| 2 | "Optionally run the runbook's ghcr_deny_rows decode ... with the =1 positive controls" | Phase 1.4 | mapped |
| 3 | "Then close #9391 with that evidence" | Phase 1.5-1.6 | mapped |
| 4 | "Append a dated superseding note (APPEND-ONLY, do not rewrite history)" | Phase 2.1, 2.3 | mapped |
| 5 | "One small PR; if it touches .github/workflows there is no agent admin-merge path." | Phase 3 (no workflow touched) | mapped |
| 6 | "Read-and-report only: #9393 ..., #9390 (held; re-read issue), #9291 (surface only)." | Phase 4 | mapped |
| 7 | "Investigate the monitor-audit warning ... report cause; fix only if inline-small, else note" | Phase 4 last bullet | mapped |
| 8 | "decide in the plan" (Ref vs Closes) | Phase 1.6 decision paragraph | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1.1-1.2 re-read of issue state and the SSH-step "Apply complete" line | "Then close #9391 with that evidence" (asks 1-3) | inferred - justification: the delivery claim in the appended note must be backed by the run's own log line, otherwise the note repeats an unverified statement |
| Phase 2.2 one-line update in the web-2 section | "Append a dated superseding note" (ask 4) | inferred - justification: that section's header line says it also needs "the web-1 apply to close", which is now stale in the same way as the named section |
| Phase 1.6 `--reason completed` close | ask 3 | asked |
| All other items | asks 1-8 | asked |

### Split Assessment

- Subsystems touched: 1 - `knowledge-base/`
- Planned files: 3 (2 edited, 1 plan artifact) | Estimated changed lines: about 45 added, 0 deleted
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1. `gh issue view 9391 --json state -q .state` prints `CLOSED` and the closing comment links
  an evidence comment that quotes: the `surface=logs_alert declared=10` OK line, `paused=false` for
  `soleur-ghcr-hostsfile-deny-lost-prd`, and per-query row counts for the four `ghcr_deny_rows`
  calls with both `=1` controls listed before the `=0` queries.
- [ ] AC2. Either all `=0` queries return zero rows, or #9391 is left OPEN with the rows commented
  (a `=0` row is the alert's signal, not a docs task).
- [ ] AC3. `git diff --numstat origin/main -- knowledge-base/engineering` shows `0` in the deleted
  column for both edited files (append-only invariant), and `git diff origin/main --stat` lists no
  path under `.github/` or `apps/`.
- [ ] AC4. `grep -c "Superseded 2026-10-04" knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`
  prints `1`; `grep -c "Merge consequence, update 2026-10-04"` on the ADR-218 file prints `1`; the
  original text `**Merge consequence.** When` and `### Known residual: web-1 until the apply workflow
  runs` still match exactly once each.
- [ ] AC5. The runbook heading slug `hosts-file-deny-lost-better-stack-alert` still resolves
  (`ghcr-blocked-alert.test.sh` green in CI via `infra-validation.yml`).
- [ ] AC6. No commit body on the branch contains the literal `[ack-destroy]`
  (`git log origin/main..HEAD --format=%B | grep -c '\[ack-destroy\]'` prints `0`), and no run of
  `workspaces-luks-cutover.yml` exists after 2026-10-04T14:00Z
  (`gh run list --workflow=workspaces-luks-cutover.yml --limit 3`).
- [ ] AC7. PR body carries `Ref #9391`, not `Closes #9391`, and states the Phase 4 findings (#9393,
  #9390, #9291, audit warning cause).
- [ ] AC8. `apply-web-platform-infra.yml` still reads `disabled_manually` at ship time (this work
  must not change it): `gh api repos/jikig-ai/soleur/actions/workflows/apply-web-platform-infra.yml --jq .state`.

## Test Scenarios

Verification here is evidence-gathering, not code tests; no test files are added.

- Positive control before the signal: `ghcr_deny_rows 'SOLEUR_ZOT_DISK' 1` returns rows before
  `ghcr_deny_rows 'SOLEUR_ZOT_DISK' 0` is read as "clean".
- Negative: if the reconcile output contains `logs-alert-absent` or `logs-alert-paused`, or the
  alert is `paused=true`, Phase 1.6 does not run and the docs note's "alert reads present and
  unpaused" clause is not written.
- Append-only mutation check: after editing, `git diff origin/main` shows only `+` lines in both
  files; any `-` line fails AC3.

## Risks and Sharp Edges

- The new note quotes "declared 10 against live 11": that is a reading, not a constant. Re-read at
  write time (Phase 2.3) so the ADR does not freeze a number that drifts when the hand-made alert is
  removed.
- Do not paraphrase the run as "applied the whole plan": the apply was allow-list scoped (`-target`),
  and the SSH half only re-created two provisioner resources. The note says exactly that.
- Do not turn "set back to `disabled_manually`" into a claim of permanence: it is live, operator-owned
  state; the note tells readers to read it with `gh api`, as the existing note does.
- `gh workflow view` prints no state and `gh workflow list` drops rows; use the `gh api` command only.
- The web `=1` positive control can legitimately be empty for a host that has not deployed since the
  window; record that, never manufacture a deploy.
- A `## User-Brand Impact` section that is empty or lacks the threshold fails deepen-plan Phase 4.6;
  this one states `none` with the docs-only reason.
- Any later edit to this branch that touches `.github/workflows` removes the agent admin-merge path;
  keep the diff to the two markdown files.
- Hook constraints for follow-ups: the issue-filing hook needs measured `User-Impact:` and
  `Fix-Size: N lines / M files` and refuses <= 100 lines and <= 4 files, so small gaps are fixed
  inline or noted in the PR body, not filed.
