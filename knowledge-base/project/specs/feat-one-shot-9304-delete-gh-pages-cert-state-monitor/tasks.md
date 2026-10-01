# Tasks: delete the scheduled-gh-pages-cert-state Sentry monitor (#9304)

Plan: knowledge-base/project/plans/2026-10-01-chore-delete-scheduled-gh-pages-cert-state-sentry-monitor-plan.md

## Phase 0 - Pre-flight
- 0.1 Run the read-only live probe: cron-monitor-failure binds 59 detectors, 1227831 not among them (STOP if bound)
- 0.2 Baseline tf-root monitor count prints 61

## Phase 1 - Destroy commit (one commit, with the ack)
- 1.1 cron-monitors.tf: delete the RETIRED comment block and sentry_cron_monitor.scheduled_gh_pages_cert_state
- 1.2 cron-monitors.tf: drop the "+ PR-gamma #4006's scheduled_gh_pages_cert_state" clause in scheduled_follow_through
- 1.3 cron-monitors.tf: drop the "(cf. scheduled_gh_pages_cert_state)" parenthetical above scheduled_strategy_review
- 1.4 cron-monitors.tf: replace the stale "30-240 min" header bound with the derived real maximum
- 1.5 cron-monitor-alerts.tf: delete the scheduled_gh_pages_cert_state entry from cron_monitor_alert_unrouted
- 1.6 function-registry-count.test.ts: delete the TEMPORARY comment and the NON_INNGEST_MONITORS entry
- 1.7 Commit body: a line that is exactly [ack-destroy] (never the subject) plus a prose approval line
- 1.8 Run scripts/sentry-squash-ack-detect.sh over the branch messages before the first push (expect exit 0)

## Phase 2 - Count ledgers (one commit; 61 -> 60, 45 -> 44, 16 unchanged)
- 2.1 README.md: two 61 citations -> 60
- 2.2 sentry-monitors-audit.sh: the Class D addendum comment 61 -> 60 plus a short #9304 clause (keep the count on one line for T25)
- 2.3 model.c4: github -> sentry "Of 60 ... 44 from webapp"; webapp -> sentry "44 Inngest-substrate"
- 2.4 model.likec4.json: same three substitutions (sed or regenerate); diff touches only the two edge titles

## Phase 3 - Comment and register hygiene (one commit)
- 3.1 cron-gh-pages-cert-reissue.ts: drop "+ cron-gh-pages-cert-state.ts" from the cfFetch banner comment (comment-only)
- 3.2 article-30-register.md: append a dated 2026-10-01 supersession note after the 2026-05-19 bracket; leave that sentence untouched

## Phase 4 - Ship
- 4.1 Open the PR: first line states the production effect, then Closes #9304; no soak/post-deploy wording, no plan/spec paths
- 4.2 CI green on the exact head SHA; plan shows 1 destroy, 0 add; no alert-reference.json regeneration unless the plan_pr gate reds
- 4.3 Before merging, re-check for newer commits under infra/sentry (the ack is blanket)
- 4.4 Merge by normal auto-merge; admin merge only under the operator's authority per settle-then-admin-merge.md; no --body/--subject overrides

## Phase 5 - Post-merge
- 5.1 Find the merge commit's apply-sentry-infra.yml run; allow 30 min
- 5.2 If cancelled/stuck: live probe first; if the monitor persists, gh run rerun that run (never workflow_dispatch), after checking nothing newer landed under infra/sentry
- 5.3 Prove end state two-sided: apply log reads `1 destroyed`, and detector 1227831 is 404 or no longer bound (the repo notes a removed monitor may be deactivated rather than deleted); compare the detector count with the pre-merge read, not a literal; post the observed state on #9304 (reopen on FAIL)
