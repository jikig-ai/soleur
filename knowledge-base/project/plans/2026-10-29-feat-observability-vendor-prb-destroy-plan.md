---
title: "feat(observability): PR-B — destroy the 43 pruned Sentry cron monitors"
date: 2026-10-29
slug: feat-observability-vendor-prb-destroy
branch: feat-one-shot-observability-vendor-prb-destroy
issue: 6590
closes: []
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
---

# feat(observability): PR-B — destroy the 43 pruned Sentry cron monitors

## Enhancement Summary

**Deepened on:** 2026-10-29
**Sections enhanced:** 6 (Proposed Solution, Files to Edit, Guard Contract,
Observability, Acceptance Criteria, Scope Check)
**Research agents used:** none — subagent context; all fan-outs executed inline
with file-level evidence (per `## Research Insights` research-mode note)

### Key Improvements

1. **Producer census resolved the emit-path question.** Measured all 43 pruned
   slugs have live producers (35 Inngest code slugs + 8 workflow `monitor-slug:`
   params). Spec NG4 rules out stripping them, so the plan carries a shared
   `PRUNED_MONITOR_SLUGS` exemption consumed by three strict guards — the only
   shape that keeps the suite green AND honest.
2. **C4 derivation fix, not just prose.** `derive_github_slugs` counts raw
   `monitor-slug:` literals; with emitters retained it would derive 22 while
   only 14 check-ins land on live monitors. The derivation moves to a
   live-backed intersection so C5/C6/C9 stay TRUE, not merely matching.
3. **`alert-reference.json` regeneration eliminated.** Verified the projection
   covers `sentry_alert` rules only and already binds the 22 kept detectors —
   removed a README-ritual step that would have been dead work.
4. **#6615 live-removal gap made a first-class AC.** Plan/apply green cannot
   prove a monitor is gone (provider-id mismatch); the audit-side Class D
   check is the verification, AC6.
5. **Stale-tracker dispositions found.** #10972 (route orphan-sweeps, due
   2026-10-27) is OBE — its followthrough probe exits 3 forever post-destroy
   until the issue is closed; #8704 loses 4 of 5 mute targets.

### New Considerations Discovered

- GuardA(i) "carrier-red" on `plan_pr` (last-applied not an ancestor of a stale
  merge ref) is expected under main's merge velocity — remediation is rebase +
  re-push, evidenced on run 40895562992 (feat-hitl-approval-queue).
- #8595 gap-1 is already fixed on main by guard (c3); this PR is its first
  live exercise (8 NON_INNGEST entries die).
- Open-PR overlap (#11289, #10905) is merge-order risk only, not scope
  duplication.

### Gate Verification (deepen-plan halt checks)

- 4.6 User-Brand: PASS (threshold `single-user incident`, all required lines)
- 4.7 Observability: PASS (5-field schema; `grep` probe, allowlisted first
  token, no `ssh `, literal `24` expected_output)
- 4.8 PAT variables: PASS (none referenced)
- 4.9 UI wireframe: N/A (no UI surface)
- 4.10 Encryption Posture: PASS (no new store/connection; stated explicitly)
- 4.11 Guard Contract: PASS (`lint-guard-contract.py` clean; 5-row mutation
  matrix + must-PASS rows + anchor)
- 4.12 Scope Check: PASS (exactly one unfenced section; 9/9 asks mapped;
  inferred items justified)
- 4.13 Task Design: N/A (no new autonomous-task surface)
- Rule IDs cited verified live in AGENTS.md; knowledge-base path citations
  all resolve.

## Overview

Complete the two-PR removal rule for the #6590 Sentry cron-monitor prune. PR-A
(#11494, merged at `dfd4fd48`) moved the 43 pruned labels from
`sentry_alert.cron_monitor_failure.monitor_ids` into
`local.cron_monitor_alert_unrouted` and regenerated `alert-reference.json`; the
monitors still exist and still bill ~$33.54/mo of PAYG seats. This PR performs
the destroy half: deletes the 43 `sentry_cron_monitor` resource blocks from
`cron-monitors.tf`, removes their 43 `cron_monitor_alert_unrouted` entries,
lands the README-listed removal edits (stale `NON_INNGEST_MONITORS` exemptions,
`[ack-destroy]` commit-body trailer, count citations in README / audit-script
comment / model.c4 + regenerated model.likec4.json), and reconciles the
monitor-parity guards to spec NG4's "emit paths unchanged" posture via an
explicit pruned-slug exemption set.

Authority set: `monitor-prune-inventory.md` (24 KEEP / 43 PRUNE with per-row
surviving-signal citations), `cron-monitor-alerts.tf:44-103` (the live unbind
list), `apps/web-platform/infra/sentry/README.md` §two-PR rule (lines 294-304).

## Problem Statement / Motivation

Until the resources are deleted, the 43 monitors keep billing (per-seat PAYG,
$0.78/mo each ≈ $33.54/mo) and the unbind is a half-finished state: every
declared monitor that is neither routed nor destroyed is the exact "spend no
apply can reclaim" class the audit's Class D exists to catch. The destroy must
go through Terraform (`hr-all-infrastructure-provisioning-servers` — no vendor
API, no dashboard) and through the merge-time apply path
(`apply-sentry-infra.yml`), whose destroy gate requires a pre-staged
`[ack-destroy]` in the merge commit body.

## Proposed Solution

One PR, four mechanical layers:

1. **Delete** the 43 `sentry_cron_monitor` blocks in `cron-monitors.tf` and the
   43 matching `cron_monitor_alert_unrouted` entries in
   `cron-monitor-alerts.tf`. Guard 1 (`sentry-cron-monitor-routing-parity.test.ts`)
   requires every declared monitor to be in `monitor_ids` XOR the unrouted map,
   and every unrouted entry to name a declared monitor — the block and its entry
   must die in the same commit.
2. **Exempt, don't strip** — spec NG4 forbids re-pointing or rewriting any emit
   path (`postSentryHeartbeat`, the `sentry-heartbeat` composite action, host
   scripts). All 43 pruned monitors still have live producers (35 Inngest
   `SENTRY_MONITOR_SLUG` consts + 8 workflow `monitor-slug:` params — measured,
   see Research Insights). Sentry drops check-ins to unknown slugs, so the
   producers become harmless void-posters by design. The strict parity guards
   (`sentry-monitor-iac-parity.test.ts` code→IaC and workflow→IaC directions,
   `function-registry-count.test.ts` guard (c)) have no exemption for this
   state, so the plan introduces a single `PRUNED_MONITOR_SLUGS` set consumed
   by the three guards, plus stale-entry assertions so the set cannot rot.
3. **Count citations** — README `**67 cron monitors**` → 24 (T25-pinned), the
   audit script's Class-D count comment → 24 (T25-pinned), model.c4 edge-prose
   counts (67 → 24; github-backed 22 → 14; webapp-backed 45 → 10), and
   `c4-count-parity.test.sh`'s `derive_github_slugs` derivation adjusted to
   intersect workflow slugs with declared monitors so the gated numbers stay
   TRUE, then regenerate `model.likec4.json` via `render-c4-model.sh`.
4. **Ack + verify** — `[ack-destroy]` alone on a commit-BODY line pre-stages
   the merge-commit ack; `plan_pr` prints the DESTROYS manifest (must be
   exactly the 43 labels, zero creates); post-merge apply destroys them and the
   Sentry audit verifies live removal (#6615's known provider-id gap means a
   plan/apply green alone does not prove a monitor is gone).

## Research Insights

**Premise Validation:** PR-A #11494 verified MERGED at `dfd4fd48f4`
(`gh pr view` + `git show`; the merge commit is in this worktree's history).
The 43 unbound labels verified live in `cron-monitor-alerts.tf:51,61-102`
(`scheduled_bot_pr_reaper` + 42 PR-A-set entries). Keep-list verified:
`scheduled_anthropic_credit_probe` sits in `monitor_ids` (line 119);
`workspaces_luks_verify_web2` + `scheduled_betterstack_incident_mirror` sit in
the unrouted map (lines 54, 58) with their own reasons. `alert-reference.json`
projects alert rules only — `cron-monitor-failure` already binds exactly the 22
kept-routed detector ids, so a monitor destroy does not change the projection
and the file needs NO regeneration in this PR (fallback if the reference gate
disagrees: the README artifact route, `sentry-alert-reference-expected-<run>`).
Cited issues verified open: #8595, #6615, #10972, #10914, #9214, #8704, #7577.
Collision precheck for #6590: no open PRs; two foreign `test-all.sh` processes
in sibling worktrees (agent-a37bb43af25149976, agent-a93446e12db271558) —
different scope, noted per protocol. Open PRs touching target files
(merge-conflict risk only): #11289 (feat-hitl-approval-queue) and #10905
(feat-git-data-erasure-ledger) touch `cron-monitor-alerts.tf`; #10905 also
touches `function-registry-count.test.ts`.

**Property List** (Phase 0.6b):
1. The 43 monitors stop billing — destroy via Terraform + merge-time apply.
2. Every guard that was green stays green and keeps teeth — exemption sets and
   derivation fixes, never guard removal or producer stripping.
3. The keep-list (`scheduled_anthropic_credit_probe`,
   `workspaces_luks_verify_web2`, `scheduled_betterstack_incident_mirror`) and
   the 21 other kept monitors are byte-identical after the diff.
4. Every count citation T25 / `c4-count-parity.test.sh` reads is true post-PR.
5. The destroy is acknowledged and verifiable end-to-end: pre-staged
   `[ack-destroy]`, DESTROYS manifest in `plan_pr`, live-removal evidence
   post-apply (the #6615 gap makes apply-green insufficient on its own).

**Cut List** (Phase 0.6b):
- Producer/emitter stripping (35 `SENTRY_MONITOR_SLUG` consts, 8 workflow
  `sentry-heartbeat` steps) — CUT by spec NG4 ("re-pointing or rewriting any
  emit path" is a non-goal); the exemption set buys the same guard-green
  property without touching emit code.
- `alert-reference.json` regeneration — CUT: the projection covers
  `sentry_alert` rules only; no alert rule changes (verified: 22 detectorIds
  already match post-PR-A state).
- Vendor-API or dashboard deletion of monitors — CUT: IaC-only per
  `hr-all-infrastructure-provisioning-servers`.
- New monitors, dashboards, or followthrough scripts — CUT: no property in the
  list needs one; the #7577 row-rate read is already tracked.

**Measured value** (Phase 0.6c): 43 seats × $0.78 = $33.54/mo realized at
destroy (inventory §"Result: 67 → 24"; expenses.md:49 cites the ~$50.94/mo
post-prune projection vs ~$84). Source: live Sentry API pass recorded in
`monitor-prune-inventory.md` (2026-10-29).

**Key file anchors (all verified on disk):**
- `apps/web-platform/infra/sentry/cron-monitors.tf` — 67
  `resource "sentry_cron_monitor"` blocks; the 43 pruned labels all present
  (e.g., `scheduled_bug_fixer` L249, `scheduled_machinery_drain` L1502,
  `scheduled_bot_pr_reaper` L1591).
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf:44-103` — the
  `cron_monitor_alert_unrouted` map; `:112-135` the 22-entry `monitor_ids`.
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` —
  `NON_INNGEST_MONITORS` L111-241 (8 entries name pruned slugs → stale under
  guard (c3) L348-352); `KNOWN_UNMONITORED_SLUGS` L87-109 (already exempts 12
  pruned code slugs); guard (c) L330-340 needs the pruned set consulted.
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` —
  "every code slug has a sentry_cron_monitor" (~L238) and "every workflow
  heartbeat slug has a cron-monitor" (~L156) have NO exemption mechanism.
- `apps/web-platform/infra/sentry/README.md` — `**67 cron monitors**` L39
  (T25-pinned), "the root declares **60**" L258, two-PR rule + PR-B removal
  list L294-304.
- `apps/web-platform/scripts/sentry-monitors-audit.sh` ~L1200-1215 — Class D
  comment cites "56 … blocks" and "67 … blocks"; T25
  (`sentry-monitors-audit.test.sh` L2048-2106) requires a
  `<n> \`resource "sentry_cron_monitor"\` blocks` line matching the tf root.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — github->sentry
  edge (~L935): "check-ins from 19 workflows … Of 67 cron monitors, 22 check in
  from here and 45 from webapp"; webapp->sentry edge (~L934): "the 45
  Inngest-substrate sentry_cron_monitors". All parity-gated by
  `plugins/soleur/test/c4-count-parity.test.sh` (C1-C6, C9 anchors L130-138).
- `plugins/soleur/test/c4-count-parity.test.sh` — `derive_github_slugs` counts
  every `monitor-slug:` literal; with emitters retained it derives 22 even
  post-destroy → must intersect with declared monitor names or C5/C6/C9 lie.
- `.github/workflows/apply-sentry-infra.yml` — `plan_pr` destroy gate
  (~L430-549): `[ack-destroy]` must reach the merge commit via squash
  COMMIT_MESSAGES (BODY line, never subject); Guard A(i) create gate (~L681,
  L942) fails closed when the PR merge ref is stale vs last-applied — the
  "carrier-red" pattern observed on run 40895562992 (feat-hitl-approval-queue):
  remediation is rebase + re-push.
- `scripts/followthroughs/orphan-sweeps-relook-10972.sh` — live-monitor probe
  for #10972; post-destroy its read returns no rows → exit 3 (cannot
  establish), so the tracker stays open until #10972 is closed by hand.

**Measured producer census (this session, derivation commands in Test
Scenarios):** all 43 pruned slugs have live producers — 35 Inngest code slugs
(`SENTRY_MONITOR_SLUG` consts under `server/inngest/functions/`) + 8 workflow
`monitor-slug:` params; the 8 workflow-produced slugs are exactly the
`NON_INNGEST_MONITORS ∩ prune` set: scheduled-actions-queue-health,
scheduled-devin-docs-drift, scheduled-domain-model-drift,
scheduled-integration-suites, scheduled-machinery-drain, scheduled-orphan-sweeps,
scheduled-prod-version-drift, scheduled-supabase-advisor-scan.

**Institutional learnings applied:** two-PR removal rule (README L294-304 —
one apply must never destroy a monitor the workflow still binds);
`sentry-cron-monitor-routing-parity` requires block+entry deletion in ONE
commit; #6074 (un-acked destroy bills forever — the ack is on the merge
commit, never the PR body alone); #8586 (the five-ledger add rule has a
removal mirror — tf, heartbeat, registry, count prose, model.c4); #6615
(terraform can report a monitor destroyed while it survives by slug — verify
live, not just plan output).

**Research-mode note:** this plan ran inside a Task subagent (one-shot
pipeline); the Phase 1/1.5/1.5b/2.5/3/4.5 agent fan-outs were executed inline
by the orchestrator with file-level evidence instead of spawned agents
(repo-research, learnings, community-discovery stack check — no
flutter/rust/etc. signatures; functional-overlap — internal IaC hygiene,
nothing to overlap; domain leaders — brainstorm carry-forward; spec-flow —
inline edge-case analysis; scoped advisor — not available, self-review at
6.5/sharp-edges instead).

## Research Reconciliation — Spec vs Codebase

| Spec/ask claim | Reality on disk | Plan response |
|---|---|---|
| "delete the 43 sentry_cron_monitor blocks … from cron-monitor-alerts.tf" (brief) | The blocks live in `cron-monitors.tf`; `cron-monitor-alerts.tf` holds only the unrouted map + alert | Delete blocks from `cron-monitors.tf`, entries from `cron-monitor-alerts.tf` |
| "NON_INNGEST_MONITORS exemption in function-registry-count.test.ts" | 8 entries go stale under (c3) — but THREE more guards also red (iac-parity code→IaC, iac-parity workflow→IaC, registry (c)) because all 43 pruned slugs still have producers | Phase 2 adds the `PRUNED_MONITOR_SLUGS` exemption the brief did not name, mandated by spec NG4 |
| "count citations in README + audit-script comment" | model.c4 edge prose is also parity-gated (C4/C5/C6/C9); `derive_github_slugs` would produce a FALSE count (22 emitter slugs vs 14 live-backed) | Phase 2.4 adjusts the derivation to live-intersection; Phase 3 updates prose |
| Keep-list "stay unrouted" | `workspaces_luks_verify_web2`, `scheduled_betterstack_incident_mirror` entries and blocks stay | Exclusion list is a hard constraint in AC1 |
| #10972 "route scheduled-orphan-sweeps (due 2026-10-27)" | Monitor is in the prune set — routing is OBE, due date passed | Close #10972 with an OBE comment; its probe exits 3 until closed |

## User-Brand Impact

- **If this lands broken, the user experiences:** a silent observability hole
  during alpha onboarding — the wrong monitor destroyed (a KEPT one) or a
  pruned monitor's cited surviving signal not actually firing — leaving a real
  production incident unpaged while a 1/10 tester is on the platform.
- **If this leaks, the user's workflow is exposed via:** nothing user-data
  bearing — the destroyed objects are vendor monitor definitions; the exposure
  is a coverage gap (missed pages), not a data leak.
- **Brand-survival threshold:** `single-user incident` (carried forward from
  the brainstorm `## User-Brand Impact` section — the wake path is
  launch-critical for the alpha cohort).
- **Threshold decision (challengeable):** kept at single-user incident because
  a botched destroy of a KEPT monitor (e.g., `scheduled_oauth_probe`,
  `workspaces_luks_verify`) removes dead-man coverage of a real user-facing
  surface, and the failure mode is silent by construction.

`requires_cpo_signoff: true` is set in frontmatter per the threshold; CPO
context is the carried-forward brainstorm assessment. The review phase invokes
`soleur:engineering:review:user-impact-reviewer` per the sign-off lifecycle.

## Implementation Phases

### Phase 1 — Terraform destroy (the two-PR rule's second half)

1.1 Delete the 43 `sentry_cron_monitor` blocks from
`apps/web-platform/infra/sentry/cron-monitors.tf`, including each block's
leading comment stanza. The authoritative delete list is the 43 entries in
`cron_monitor_alert_unrouted` (labels below in Files to Edit). NEVER touch the
24 kept blocks: the 22 in `monitor_ids` plus `workspaces_luks_verify_web2` +
`scheduled_betterstack_incident_mirror`.

1.2 In the SAME commit, delete the 43 matching `cron_monitor_alert_unrouted`
entries and the "PR-A unbind set" comment header (`cron-monitor-alerts.tf`
lines 59-60) from `cron-monitor-alerts.tf`. The map must end with exactly two
entries: `workspaces_luks_verify_web2` and `scheduled_betterstack_incident_mirror`
(keep their reason strings verbatim). Guard 1
(`sentry-cron-monitor-routing-parity.test.ts`) fails any intermediate state.

### Phase 2 — Guard reconciliation under NG4 (exempt, don't strip)

2.1 Create `apps/web-platform/test/server/inngest/pruned-monitor-slugs.ts`
exporting `PRUNED_MONITOR_SLUGS` — the 43 pruned slugs (kebab-case, matching
each block's `name` attribute), with a header comment citing #6590, the
inventory, spec NG4 (emit paths unchanged — producers keep posting and Sentry
drops unknown-slug check-ins), and the re-add path ("re-monitoring a slug =
delete its entry, re-declare the block, re-route per the two-PR rule").

2.2 `sentry-monitor-iac-parity.test.ts`: consult `PRUNED_MONITOR_SLUGS` in the
"every code slug has a sentry_cron_monitor" guard and the "every workflow
heartbeat slug has a cron-monitor" guard (a pruned slug with a live producer
is the deliberate void-post posture, not the #6374 gap). Add the stale-set
assertions from the Guard Contract below (PRUNED ∩ declared = ∅; PRUNED ⊆
producers — a typo'd or re-added slug reds instead of silently exempting).

2.3 `function-registry-count.test.ts`: remove the 8 stale
`NON_INNGEST_MONITORS` entries (scheduled-actions-queue-health,
scheduled-devin-docs-drift, scheduled-domain-model-drift,
scheduled-integration-suites, scheduled-machinery-drain,
scheduled-orphan-sweeps, scheduled-prod-version-drift,
scheduled-supabase-advisor-scan) — guard (c3) reds on them the moment the tf
blocks die; extend guard (c) to consult `PRUNED_MONITOR_SLUGS`
(`!tfMonitors.has(slug) && !KNOWN_UNMONITORED_SLUGS.has(slug) &&
!PRUNED_MONITOR_SLUGS.has(slug)`). Leave `KNOWN_UNMONITORED_SLUGS` untouched —
its 12 already-exempt pruned slugs stay valid while producers exist (guard (d)).

2.4 `plugins/soleur/test/c4-count-parity.test.sh`: change
`derive_github_slugs` to count workflow `monitor-slug:` values that also have
a declared `name = "<slug>"` in `cron-monitors.tf` (live-backed check-ins =
14 post-prune), with a comment recording the semantic shift (emitter count →
live-backed count; the emitter cohort is still pinned by
sentry-monitor-iac-parity + the PRUNED set). `derive_webapp_slugs` (C4−C5)
then yields 10 = true webapp/host-backed monitors.

### Phase 3 — Count citations + model regen

3.1 `apps/web-platform/infra/sentry/README.md`: `**67 cron monitors**` →
`**24 cron monitors**` (T25 anchor, L39); "the root declares **60** of them" →
24 with the prune provenance (L258); the routing prose at L44-48 stays true.

3.2 `apps/web-platform/scripts/sentry-monitors-audit.sh` Class-D comment
(~L1200-1215): update the verified count citations so a line reads
`24 \`resource "sentry_cron_monitor"\` blocks` (T25 greps it; keep the count
on ONE line) and the addendum's "now declares 67" history gets a dated
"…→ 24 (#6590 PR-B destroy)" tail.

3.3 `knowledge-base/engineering/architecture/diagrams/model.c4`: update the
github->sentry edge ("Of 67 cron monitors, 22 check in from here and 45 from
webapp" → "Of 24 cron monitors, 14 check in from here and 10 from webapp",
plus a clause recording that 43 emitters deliberately post to dropped slugs
post-prune — NG4) and the webapp->sentry edge ("the 45 Inngest-substrate
sentry_cron_monitors" → "the 10 …"). Then regenerate:
`bash plugins/soleur/scripts/render-c4-model.sh` →
`model.likec4.json` (byte-diff is CI-pinned by c4-model-freshness.test.sh).

3.4 (Optional, one line) `knowledge-base/operations/expenses.md` — append
"destroyed by PR-B" to the existing 2026-10-29 projection note; the
re-measure marker stays.

### Phase 4 — Commit convention + PR

4.1 Put `[ack-destroy]` alone on a commit-BODY line in the implementation
commit (never a subject — GitHub renders subjects as `* [ack-destroy]`,
breaking the apply gate's line anchor; never only the PR body). The squash
merge composes its body from COMMIT_MESSAGES, carrying the ack into the merge
commit the post-merge apply gate greps.

4.2 Push and read `plan_pr` in `apply-sentry-infra.yml`: expected = 43
DESTROYS, 0 creates, destroy-gate PASS via the pre-staged ack. If Guard A(i)
reds with "last applied commit … is not an ancestor of this PR's merge ref"
(the GuardA carrier-red pattern — observed on run 40895562992), rebase the
branch against main and re-push; it is expected under main's merge velocity,
not a defect in this diff.

### Phase 5 — Post-merge verification + bookkeeping

5.1 The merge-triggered apply run must show the 43 destroys applied. THEN
verify live removal — #6615 (a destroy can report success while the monitor
survives by slug): the next `sentry-audit-gate` run / a manual
`sentry-monitors-audit.sh` must show zero Class D live-undeclared survivors;
any survivor is reclaimed by a follow-up destroy PR naming it.

5.2 `sentry-audit-gate` (advisory) and `scheduled-sentry-alert-drift` (cron,
reads committed `alert-reference.json` — unchanged here) green on next runs.

5.3 Fire-test (AC3 continuation): force one RETAINED heartbeat miss (a
`betteruptime_heartbeat` pause or a held check-in on a kept monitor) →
Better Stack alert → `scheduled-betterstack-incident-mirror` files the
`[ci/betterstack-incident]` GitHub issue — the end-to-end wake path, unmocked.

5.4 Issue bookkeeping: comment on #6590 (PR-B executed — seat savings
realized); close #10972 as OBE (monitor destroyed by prune verdict; cover
reverts to the aggregator's notify-ops-email step its own body cites);
comment on #8704 (4 of 5 unmute targets destroyed — only
`scheduled-anthropic-credit-probe`'s unmute remains live); comment on #8595
((c3) got its first live exercise; the cadence-parity half stays open);
#7577 Nano downgrade unchanged — 24–48 h `betterstack-query.sh` row-rate read
decides; Better Stack `verify_by=2026-11-12` marker unchanged (usage/billing
APIs 404).

## Files to Edit

- `apps/web-platform/infra/sentry/cron-monitors.tf` — delete the 43
  `sentry_cron_monitor` blocks (labels: cron_action_required_sla,
  cron_github_cidr_refresh, cron_weekly_release_digest,
  scheduled_actions_queue_health, scheduled_agent_native_audit,
  scheduled_anthropic_cost_report, scheduled_architecture_diagram_sync,
  scheduled_bot_pr_reaper, scheduled_bug_fixer, scheduled_campaign_calendar,
  scheduled_cloud_task_heartbeat, scheduled_community_monitor,
  scheduled_competitive_analysis, scheduled_compound_promote,
  scheduled_content_generator, scheduled_content_publisher,
  scheduled_content_vendor_drift, scheduled_daily_triage,
  scheduled_devin_docs_drift, scheduled_domain_model_drift,
  scheduled_follow_through, scheduled_growth_audit, scheduled_growth_execution,
  scheduled_integration_suites, scheduled_legal_audit,
  scheduled_linkedin_token_check, scheduled_machinery_drain,
  scheduled_nag_4216_readiness, scheduled_orphan_sweeps,
  scheduled_plausible_goals, scheduled_prod_version_drift,
  scheduled_roadmap_review, scheduled_rule_prune, scheduled_ruleset_bypass_audit,
  scheduled_seo_aeo_audit, scheduled_skill_freshness,
  scheduled_stale_deferred_scope_outs, scheduled_strategy_review,
  scheduled_supabase_advisor_scan, scheduled_supabase_disk_io,
  scheduled_ux_audit, scheduled_weekly_analytics, scheduled_workspace_gc)
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — delete the 43
  `cron_monitor_alert_unrouted` entries + PR-A unbind comment header
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` —
  drop 8 stale `NON_INNGEST_MONITORS` entries; (c) consults
  `PRUNED_MONITOR_SLUGS`
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` —
  exempt `PRUNED_MONITOR_SLUGS` in both strict guards; add the two stale-set
  assertions
- `apps/web-platform/infra/sentry/README.md` — count citations 67/60 → 24
- `apps/web-platform/scripts/sentry-monitors-audit.sh` — Class-D count comment
  → 24
- `knowledge-base/engineering/architecture/diagrams/model.c4` — edge-prose
  counts + NG4 emitter clause
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` —
  regenerated artifact
- `plugins/soleur/test/c4-count-parity.test.sh` — `derive_github_slugs`
  live-intersection + comment
- `knowledge-base/operations/expenses.md` — OPTIONAL one-line "destroyed by
  PR-B" append

## Files to Create

- `apps/web-platform/test/server/inngest/pruned-monitor-slugs.ts` — the
  43-entry `PRUNED_MONITOR_SLUGS` set + rationale header
- `knowledge-base/project/specs/feat-one-shot-observability-vendor-prb-destroy/tasks.md`
  — pipeline task breakdown

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "PR-B destroy: delete the 43 sentry_cron_monitor blocks + matching cron_monitor_alert_unrouted entries" [brief] | Phase 1; Files-to-Edit rows 1-2 | mapped |
| 2 | "README-listed removal edits; NON_INNGEST_MONITORS exemption in function-registry-count.test.ts" [brief] | Phase 2.3 + 3.1-3.2 | mapped |
| 3 | "[ack-destroy] alone on a commit-BODY line" [brief] | Phase 4.1 | mapped |
| 4 | "count citations in README + audit-script comment; regenerate model.c4 + model.likec4.json via render-c4-model.sh if .c4 changes" [brief] | Phase 3.1-3.3 | mapped |
| 5 | "Keep: scheduled_anthropic_credit_probe … workspaces_luks_verify_web2 + scheduled_betterstack_incident_mirror (stay unrouted)" [brief] | AC1/AC2 exclusion constraints; Phase 1.1-1.2 keep-lists | mapped |
| 6 | "Verify destroys appear in apply plan output; post-merge fire-test one retained heartbeat miss → BS alert → GH issue (AC3)" [brief] | Phase 4.2, 5.1, 5.3; AC4, AC7 | mapped |
| 7 | "sentry-audit-gate + scheduled-sentry-alert-drift (cron) should be green on next runs" [brief] | Phase 5.2; AC7 | mapped |
| 8 | "Track: 24–48h betterstack-query.sh row-rate read → Nano downgrade decision (#7577); Better Stack verify_by=2026-11-12 marker" [brief] | Phase 5.4 + tracking note | mapped (existing trackers carry it — no new mechanism) |
| 9 | "Watch: apply plan for destroy may hit the same GuardA carrier-red pattern — expected" [brief] | Phase 4.2 remediation | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `pruned-monitor-slugs.ts` + guard exemptions (Phase 2) | — | inferred — justification: spec NG4 forbids emit-path rewrites while all 43 pruned slugs keep live producers; without the exemption three green guards red on the deliberate void-post posture |
| `c4-count-parity.test.sh` derivation change (Phase 2.4) | — | inferred — justification: with emitters retained, raw `monitor-slug:` counts make the parity-gated C5/C6/C9 prose FALSE; the gate exists to keep those counts true |
| Close #10972 / comment #8704, #8595 (Phase 5.4) | — | inferred — justification: the destroy makes the tracker OBE and its probe exits 3 forever until closed; the mute/scope-out issues lose their subjects — silent rot otherwise |
| Post-destroy live-removal verification (Phase 5.1) | "Verify destroys appear in apply plan output" | inferred — justification: #6615 — a green apply can leave a monitor alive by slug; the audit is the only check that sees live state |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `plugins/soleur`,
  `knowledge-base`
- Planned files: 10 edit + 2 create | Estimated changed lines: ~900-1100
  (~860 of them mechanical resource-block deletion)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — over the 800-line tunable by volume only; the
  diff is ~90% deletion of independent blocks, and splitting mid-set leaves
  dangling unrouted entries that red Guard 1. The two-PR rule already split
  this change once (PR-A unbind / PR-B destroy).

## Domain Review

**Domains relevant:** Engineering, Operations, Finance (carried forward from
the archived brainstorm's `## Domain Assessments`; Product assessed NONE).

### Engineering

**Status:** reviewed (carry-forward + inline re-assessment)
**Assessment:** Emit layer untouched per NG4 — the change is entirely IaC +
guard reconciliation + prose. The load-bearing correctness surface is the
guard semantics: the pruned set must be exempt AND non-stale-able (PRUNED ∩
declared = ∅, PRUNED ⊆ producers), or it becomes the allowlist-rot class
#8595 guards against.

### Operations

**Status:** reviewed (carry-forward)
**Assessment:** The wake path is byte-identical throughout — 24 routed/unrouted
monitors unchanged; no Responder/on-call shape change. The destroy executes on
the standard merge→apply path with the ack gate; the #6615 caveat (a green
apply can leave a live monitor) is answered by the audit-side live check.

### Finance

**Status:** reviewed (carry-forward)
**Assessment:** Realizes the recorded projection — 43 × $0.78 ≈ $33.54/mo
PAYG seats reclaimed (~$51 → ~$17.94 monitor spend). Governance is the ADR-031
amendment already landed; no new spend surface introduced.

### Product/UX Gate

**Tier:** none — no user-facing surface; Files-to-Edit/Create carry no
UI-surface path (mechanical override scan: clean).

## User-Visible / Legal note

No regulated-data surface is touched (monitor definitions are vendor ops
metadata; no schema, migration, auth flow, API route, or `.sql` file; none of
the four cross-controller triggers fire — no new processing, no
learnings-reading cron, no new distribution surface). `soleur:gdpr-gate`
skipped per Phase 2.7's skip condition; the #7529 DPA debt is unchanged.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf` — destroys 43
  `sentry_cron_monitor` resources (the only prod-mutating diff).
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — `locals` edit
  only; produces NO plan change.
- Provider: pinned `jianyuan/sentry` (existing root; no version change).
- No new secrets/`TF_VAR_*`; apply authenticates via the existing
  `SENTRY_IAC_AUTH_TOKEN` repo secret.

### Apply path

**Merging this PR alone mutates production.** `apply-sentry-infra.yml` is
push-triggered on `apps/web-platform/infra/sentry/**`; the merge commit IS the
authorization (`hr-menu-option-ack-not-prod-write-auth`) — no
`-replace`, no provisioners, no host contact. Blast radius: the 43 monitor
definitions + Sentry-side check-in acceptance for their slugs. The destroy
gate requires the pre-staged `[ack-destroy]` in the merge-commit body;
`plan_pr` on the PR prints the DESTROYS manifest for review before merge.

### Host fan-out

None — no `terraform_data` SSH provisioners are touched; Sentry resources are
vendor-API objects.

### Distinctness / drift safeguards

`scheduled-terraform-drift.yml`'s sentry leg (twice-daily full-root plan)
detects any monitor that survives or reappears unmanaged; Guard 1
(routing-parity) enforces the monitor_ids/unrouted bijection; T25 + the
c4-count-parity suite pin the prose counts; `sentry-monitors-audit.sh`
Class D is the live-side check for the #6615 survivor class.

### Vendor-tier reality check

Destroys only REDUCE PAYG seat usage; no tier-gated resource is created. The
$75 onDemandMaxSpend cap posture improves (43 seats of headroom reclaimed).

## Observability

```yaml
liveness_signal:
  what:            "the 24 RETAINED sentry_cron_monitor check-in streams + the alert routing that stays bound"
  cadence:         "per-cron (unchanged)"
  alert_target:    "sentry_alert.cron_monitor_failure → issue_owners/ActiveMembers email (unchanged)"
  configured_in:   "apps/web-platform/infra/sentry/{cron-monitors.tf,cron-monitor-alerts.tf}"
error_reporting:
  destination:     "Sentry project soleur-web-platform (unchanged) + Better Stack log alerts (unchanged)"
  fail_loud:       "a kept monitor that stops checking in pages by construction; a destroy that leaves a survivor surfaces as Class D in sentry-monitors-audit.sh and as drift in scheduled-terraform-drift.yml's sentry leg"
failure_modes:
  - mode:          "destroy plan shows creates or non-monitor deletes"
    detection:     "plan_pr prints the DESTROYS/forgets manifest + Guard A(i) create gate; required check reds the PR"
    alert_route:   "PR check failure → operator"
  - mode:          "a monitor survives the destroy by slug (#6615 provider-id mismatch)"
    detection:     "sentry-monitors-audit.sh Class D live-undeclared on the next audit/apply run"
    alert_route:   "audit report + infra-drift issue via scheduled-terraform-drift.yml"
  - mode:          "a KEPT monitor is deleted by mistake"
    detection:     "the AC1 keep-list assertion + Guard 1 routing-parity (an unrouted entry or monitor_ids ref with no block reds the suite)"
    alert_route:   "vitest gate on the PR"
  - mode:          "pruned-slug exemption rots (typo'd entry, re-added monitor)"
    detection:     "the new stale-set assertions (PRUNED ∩ declared = ∅, PRUNED ⊆ producers)"
    alert_route:   "vitest gate on the PR"
logs:
  where:           "apply-sentry-infra.yml run logs (plan + apply); Sentry audit report artifacts"
  retention:       "GitHub Actions retention (~90d)"
discoverability_test:
  command:         "grep -c '^resource \"sentry_cron_monitor\"' apps/web-platform/infra/sentry/cron-monitors.tf"
  expected_output: "24"
```

## Architecture Decision (ADR/C4)

- `### ADR` — NONE new. The architectural decision (monitor-per-cron →
  monitored-where-silence-undetectable) is already recorded: ADR-031 Amendment
  2026-10-29, landed by PR-A `dfd4fd48`. This PR executes the recorded
  decision; amending the amendment adds nothing.
- `### C4 views` — no new actor, external system, container, or access
  relationship (all three model files checked: `model.c4` edges persist with
  reduced cardinality; `views.c4`/`spec.c4` carry no monitor counts — grep
  verified). The task is edge-PROSE updates on `github -> sentry` and
  `webapp -> sentry` (cardinality + NG4 emitter clause) plus regenerating
  `model.likec4.json` — in-scope, Phase 3.3. The derived cardinalities in the
  edge prose are updated by hand per the C4-completeness rubric's
  derived-numbers carve-out, and the parity suite (C4/C5/C6/C9) pins them.
- `### Sequencing` — nothing deferred: the destroy IS this PR.

## Encryption Posture

```yaml
at_rest: []
in_transit: []
# The plan introduces no persistent store and no new cross-component
# connection. It REMOVES 43 check-in destinations (producer -> Sentry cron
# check-in API) while the POSTs themselves continue to a dropped-slug void
# (NG4): the TLS posture of the surviving check-in paths is unchanged (HTTPS
# to jikigai-eu.sentry.io with platform cert verification — no cert_verification: off
# anywhere in the emit chain). No exception block required.
```

## Guard Contract

The deliverable amends three monitor-registry guards and introduces one
exemption set — Guard Contract applies.

### Guard 1 — PRUNED_MONITOR_SLUGS exemption

**Property.** A pruned monitor's slug may keep a live producer without a
declared `sentry_cron_monitor` (the deliberate NG4 void-post posture) —
and ONLY a slug that is (a) in the pruned set, (b) still produced, and (c)
still undeclared may be exempt.

**Assembly.** The chokepoints: `PRUNED_MONITOR_SLUGS` (the single shared set,
`test/server/inngest/pruned-monitor-slugs.ts`); its three consumers
(`sentry-monitor-iac-parity.test.ts` code→IaC + workflow→IaC guards;
`function-registry-count.test.ts` guard (c)); the two producer derivations
(SLUG_RE over `server/inngest/functions/*.ts`; `monitor-slug:` over
`.github/workflows/*.yml`); and the declared-name derivation
(`name = "<slug>"` attrs in `cron-monitors.tf`).

**Mutation matrix** (must go RED):

| # | Edit | Guard arm that must red |
|---|------|-------------------------|
| 1 | Delete one pruned slug from `PRUNED_MONITOR_SLUGS` while its producer still posts | the strict producer→IaC guard (code-slug or workflow-slug arm) — the exemption is the only thing keeping that slug green |
| 2 | Add a slug to `PRUNED_MONITOR_SLUGS` that still has a declared `sentry_cron_monitor` | the `PRUNED ∩ declared = ∅` assertion (an exemption covering a LIVE monitor) |
| 3 | Add a slug to `PRUNED_MONITOR_SLUGS` naming no producer (typo / dead entry) | the `PRUNED ⊆ producers` assertion — the set cannot rot like the pre-#8595 allowlist |
| 4 | Strip a producer (delete `SENTRY_MONITOR_SLUG`/`monitor-slug:`) while its slug stays in `PRUNED_MONITOR_SLUGS` | the `PRUNED ⊆ producers` assertion — forces set cleanup when a later change DOES retire an emitter |
| 5 | Harness row: break the SLUG_RE/`monitor-slug` extractor so the producer set reads empty | the anti-vacuity floors + the `PRUNED ⊆ producers` assertion red (43 entries suddenly have no producer) |

**Must-PASS rows:** (a) a kept monitor whose slug is produced AND declared and
absent from `PRUNED_MONITOR_SLUGS` (the canonical shape — proves the guards do
not over-rely on the exemption); (b) a pruned slug produced by BOTH an Inngest
const and a workflow step (if the shape ever occurs — the set is
producer-source-agnostic by design).

**Anchor.** The set is a stored manifest reviewed in the same diff as the
deletion; integrity comes from assertion 2 (an entry cannot silently cover a
declared monitor) and assertion 3 (an entry must name a producer), not from a
count floor — a `>= N` floor would survive substitution, so no floor is
declared.

## Open Code-Review Overlap

1 open code-review issue touches the planned files:

- **#8595** (monitor registry guard gaps — NON_INNGEST_MONITORS stale entries
  + no cadence parity) touches `function-registry-count.test.ts` and
  `sentry-monitor-iac-parity.test.ts`. **Disposition: acknowledge.** Its gap 1
  (stale-entry reverse guard) is already closed on main by guard (c3), and
  this PR is its first live exercise (8 entries die); gap 2 (cadence parity
  on surviving monitors) is a separate concern this PR shrinks but does not
  close — comment at ship time per Phase 5.4.

## Test Scenarios

- `vitest run test/server/inngest/function-registry-count.test.ts
  test/server/inngest/sentry-monitor-iac-parity.test.ts
  test/server/inngest/sentry-cron-monitor-routing-parity.test.ts` — all green
  with the exemption machinery; then the mutation-matrix rows 1-4 each red
  their named arm (run row 1 as the live check: remove one PRUNED entry →
  suite names it).
- `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` — T25 green
  (README 24, script comment 24).
- `bash plugins/soleur/test/c4-count-parity.test.sh` — green at the new
  derivations (C4=24, C5=14, C6=10, C9=10; C1=19, C2=13, C3=6 unchanged);
  `vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` +
  `c4-model-freshness` byte-diff green after the render.
- Producer census (verifies this plan's premise): `grep -rhoE
  'SENTRY_MONITOR_SLUG\s*=\s*"[a-z0-9-]+"' server/inngest/functions/*.ts` ∪
  `grep -hoE 'monitor-slug:\s*"?[a-z0-9-]+' .github/workflows/*.yml` covers all
  43 pruned slugs.
- `plan_pr` manifest: `terraform show -json tfplan | jq` destroy list ==
  exactly the 43 labels; creates == 0.

## Acceptance Criteria

The PR body links `Ref #6590` (never `Closes #6590`): post-merge apply +
verification ACs remain open at merge time, and `Closes` would auto-close the
tracker before the destroy lands (ops-remediation class).

### Pre-merge (PR)

- **AC1** — Exactly 24 `sentry_cron_monitor` resources remain in
  `apps/web-platform/infra/sentry/cron-monitors.tf`; the deleted set equals
  the 43 inventory labels 1:1; `scheduled_anthropic_credit_probe`,
  `workspaces_luks_verify_web2`, `scheduled_betterstack_incident_mirror` and
  the 21 other kept blocks are byte-identical.
- **AC2** — `local.cron_monitor_alert_unrouted` contains exactly
  `workspaces_luks_verify_web2` + `scheduled_betterstack_incident_mirror`
  (reasons verbatim); `monitor_ids` unchanged at 22 entries.
- **AC3** — Green suite: vitest registry/parity guards, T25, c4-count-parity;
  8 stale `NON_INNGEST_MONITORS` entries gone; `PRUNED_MONITOR_SLUGS` carries
  the 43 slugs with the two stale-set assertions; `[ack-destroy]` alone on a
  commit-BODY line on the branch.
- **AC4** — `plan_pr` in `apply-sentry-infra.yml` prints exactly the 43
  `sentry_cron_monitor.*` DESTROYS and 0 creates, and the destroy gate passes
  on the pre-staged ack.
- **AC5** — Prose consistent: README `**24 cron monitors**`, audit comment
  `24 \`resource "sentry_cron_monitor"\` blocks`, model.c4 edges at
  24/14/10 with the NG4 emitter clause; `model.likec4.json` regenerated.

### Post-merge (apply + verification)

- **AC6** — The merge-triggered apply destroys the 43; the next audit shows no
  live-undeclared survivors (#6615 check). Bookkeeping: #6590 commented (PR-B
  executed); #10972 closed OBE; #8704 + #8595 commented.
- **AC7** — `sentry-audit-gate` and `scheduled-sentry-alert-drift` green on
  their next runs post-merge; the retained-heartbeat fire-test produces a
  Better Stack alert → `[ci/betterstack-incident]` GitHub issue.

## Sharp Edges (noted for the work phase)

- `[ack-destroy]` on a subject line silently fails the apply gate — BODY line
  only, and the squash body must come from COMMIT_MESSAGES (plan_pr verifies).
- A monitor deleted while still bound in `monitor_ids` orders destroy-before-
  update against the workflow — impossible here (PR-A unbound them) but the
  two-PR ordering is why it is safe.
- `git add` the plan + tasks atomically; never `git add` the plans directory.
- If `plan_pr`'s reference gate unexpectedly reds on `alert-reference.json`,
  regenerate via the `sentry-alert-reference-expected-<run>` artifact route —
  never hand-edit.
- The apply run stuck in `waiting` is a runner/concurrency stall, not an
  approval gate — recover by `gh run rerun` of the ack-carrying run only.
- A plan whose `## User-Brand Impact` section is empty or threshold-less fails
  deepen-plan 4.6 — filled above.

## Non-Goals

- Stripping or re-pointing any heartbeat emit path (spec NG4).
- Routing the two unrouted keep-list monitors (separate issues per their
  unrouted reasons).
- Deleting the producers' cron functions or workflows — the jobs still run;
  only their Sentry dead-man seat is reclaimed.
- `alert-reference.json` regeneration (projection unchanged — see Cut List).
- #7577 Nano downgrade execution (tracking only; decided by the row-rate read).
