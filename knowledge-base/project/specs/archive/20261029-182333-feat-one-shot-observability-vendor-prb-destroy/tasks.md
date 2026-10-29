---
title: Tasks — feat(observability) PR-B destroy the 43 pruned Sentry cron monitors
feature: feat-one-shot-observability-vendor-prb-destroy
plan: knowledge-base/project/plans/2026-10-29-feat-observability-vendor-prb-destroy-plan.md
status: pending
---

# Tasks

## Phase 1 — Terraform destroy

- [ ] 1.1 Delete the 43 `sentry_cron_monitor` blocks (+ leading comment stanzas) from `apps/web-platform/infra/sentry/cron-monitors.tf` — delete list = the 43 `cron_monitor_alert_unrouted` labels; NEVER the 24 kept blocks
- [ ] 1.2 Same commit: delete the 43 `cron_monitor_alert_unrouted` entries + the "PR-A unbind set" comment header in `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`; map ends with exactly `workspaces_luks_verify_web2` + `scheduled_betterstack_incident_mirror` (reasons verbatim)

## Phase 2 — Guard reconciliation (NG4: exempt, don't strip)

- [ ] 2.1 Create `apps/web-platform/test/server/inngest/pruned-monitor-slugs.ts` exporting `PRUNED_MONITOR_SLUGS` (43 kebab-case slugs + NG4/inventory rationale + re-add path)
- [ ] 2.2 `sentry-monitor-iac-parity.test.ts`: consult `PRUNED_MONITOR_SLUGS` in the code-slug→IaC and workflow-slug→IaC guards; add assertions `PRUNED ∩ declared = ∅` and `PRUNED ⊆ producers`
- [ ] 2.3 `function-registry-count.test.ts`: remove the 8 stale `NON_INNGEST_MONITORS` entries; extend guard (c) to consult `PRUNED_MONITOR_SLUGS`
- [ ] 2.4 `plugins/soleur/test/c4-count-parity.test.sh`: `derive_github_slugs` → workflow slugs ∩ declared tf `name` attrs (14) feeding C5/C6/C9; NEW raw `derive_github_emitter_slugs` feeds ONLY the `c5 -ge c1` invariant (:203-212); comment names the split; verify C1=19, C2=13, C3=6, C5=14, C6=10, C9=10
- [ ] 2.5 #10972 tracker retirement (CTO tails): delete `scripts/followthroughs/orphan-sweeps-relook-10972.{sh,test.sh}` + `run_suite` line in `scripts/test-all.sh`; regenerate `suite-shard-legs.tsv`/`suite-durations.tsv` via `regenerate-shard-manifest.py --incremental --write`; update 3 stale `#10972` comments in `scheduled-terraform-drift.yml` (~L3000/~L3281/~L3311 — destroyed-not-routed + mail-key common-mode record)

## Phase 3 — Count citations + model regen

- [ ] 3.1 `apps/web-platform/infra/sentry/README.md`: `**67 cron monitors**` → `**24 cron monitors**`; "declares **60**" → 24 + prune provenance
- [ ] 3.2 `apps/web-platform/scripts/sentry-monitors-audit.sh` Class-D comment → `24 \`resource "sentry_cron_monitor"\` blocks` (one line, T25-grepped)
- [ ] 3.3 `model.c4` edge prose (github→sentry 24/14/10 + NG4 emitter clause; webapp→sentry "the 10"), then `bash plugins/soleur/scripts/render-c4-model.sh` → `model.likec4.json`
- [ ] 3.4 (optional) `knowledge-base/operations/expenses.md` one-line "destroyed by PR-B" append

## Phase 4 — Commit convention + PR

- [ ] 4.1 `[ack-destroy]` alone on a commit-BODY line (never subject, never PR-body-only)
- [ ] 4.2 Push; read `plan_pr`: 43 DESTROYS, 0 creates, gate PASS via ack. GuardA carrier-red ("last applied commit not an ancestor of merge ref") → rebase + re-push

## Phase 5 — Post-merge verification + bookkeeping

- [ ] 5.1 Apply run lands the 43 destroys; verify live removal via `sentry-monitors-audit.sh` Class D (the #6615 survivor check)
- [ ] 5.2 `sentry-audit-gate` + `scheduled-sentry-alert-drift` green on next runs
- [ ] 5.3 Fire-test one retained heartbeat miss → BS alert → `[ci/betterstack-incident]` issue (AC7)
- [ ] 5.4 Comment #6590 (executed); close #10972 OBE post-apply (comment names the Resend-mail-key common-mode loss) + drop `follow-through` label; comment #8704 + #8595; #7577 Nano tracking + verify_by=2026-11-12 unchanged

## Acceptance Criteria

- [ ] AC1 — 24 `sentry_cron_monitor` resources remain; deleted set = the 43 inventory labels 1:1; keep-list byte-identical
- [ ] AC2 — `cron_monitor_alert_unrouted` = exactly the two keep-list entries; `monitor_ids` unchanged at 22
- [ ] AC3 — Green suite (registry/parity vitest, T25, c4-count-parity); 8 NON_INNGEST entries gone; `[ack-destroy]` on a commit-body line
- [ ] AC4 — `plan_pr` DESTROYS == 43 labels, 0 creates; post-merge apply lands them; no live-undeclared survivors
- [ ] AC5 — README/audit-comment/model.c4 counts at 24(/14/10); `model.likec4.json` regenerated
- [ ] AC6 — #6590 commented; #10972 closed; #8704 + #8595 commented
- [ ] AC7 — audit-gate + alert-drift green post-merge; retained-heartbeat fire-test → BS alert → GH issue
