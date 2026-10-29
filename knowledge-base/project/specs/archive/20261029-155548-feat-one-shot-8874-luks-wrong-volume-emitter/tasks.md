# Tasks — feat-one-shot-8874-luks-wrong-volume-emitter

Plan: `knowledge-base/project/plans/2026-10-29-fix-inngest-luks-wrong-volume-emitter-plan.md`
Issue: #8874 (PR body carries `Ref #8874`, never `Closes` — the live change lands at the merge-triggered apply).

## Phase 1 — Predicate + guard (single commit)

- [ ] 1.1 In `apps/web-platform/infra/betterstack-logs-alerts.tf`, inside `local.inngest_luks_wrong_volume_sql`, insert `AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-server-probe'` as the first conjunct under `WHERE time BETWEEN {{start_time}} AND {{end_time}}` (before the `SOLEUR_INNGEST_SERVER_PROBE` marker line). Do not touch the marker anchor, 'host_role=dedicated ' scope, or the negated `data_mount_devid` predicate.
- [ ] 1.2 Extend the local's `LIVE-PROBED` comment block: add a dated entry naming this change and one line stating the conjunct exists because `doppler` event-log rows quote the marker verbatim (#8846) — the `{'-prefix exclusion is incidental. Leave count slots for Phase 2 to fill.
- [ ] 1.3 In `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`, add a "WHAT THIS FILE PROTECTS" header bullet: the row set is pinned to the probe's own emitter so a `doppler` row quoting the marker can never count (#8874/#8846).
- [ ] 1.4 Add a presence assertion after the marker-anchor row: extracted `LOCAL_SQL` contains the fixed string `JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'inngest-server-probe'` (`grep -cF`, same shape as the marker row).
- [ ] 1.5 Add three `mutate_red` rows on the TF copy: (a) conjunct line deleted; (b) emitter literal flipped to `'doppler'`; (c) equality rewritten as `position(JSONExtractString(raw, 'SYSLOG_IDENTIFIER'), 'inngest-server-probe') > 0`. Each must drive the inner run red.
- [ ] 1.6 Update floors: `_floor=23` → `_floor=27`; `MUT_SKIP` floor `13` → `14`; update the `23 = 13 presence + 10 mutation` comment to `27 = 14 presence + 13 mutation`.
- [ ] 1.7 Run `terraform fmt -check apps/web-platform/infra/betterstack-logs-alerts.tf` (fix layout only if it reports drift).
- [ ] 1.8 Run `bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` — expect `27 passed, 0 failed`.

## Phase 2 — Live-probe (pre-merge, required by #8874)

- [ ] 2.1 Read the live `data_mount_devid` value off the newest `host_role=dedicated` probe row (runbook `inngest-luks-cutover-6894.md` readback recipe).
- [ ] 2.2 Run control A (population): emitter + marker anchor + 'host_role=dedicated ' over hot∪archive — expect `n > 0`.
- [ ] 2.3 Run control B (emitter breakdown): marker anchor alone, `GROUP BY SYSLOG_IDENTIFIER` — enumerate which emitters carry anchored rows.
- [ ] 2.4 Run control C (quiet): full new predicate with the live alias — expect `n=0`.
- [ ] 2.5 Run control D (positive): same predicate with a wrong alias (e.g. `scsi-0HC_Volume_0`) — expect `n` equal to control A's count.
- [ ] 2.6 Fill the Phase 1.2 comment slots with the window and all four numbers.

## Phase 3 — Merge and post-apply close

- [ ] 3.1 PR body first line states: merging fires the push-triggered apply which updates the live exploration SQL. Body carries `Ref #8874`.
- [ ] 3.2 After merge, read the `apply-web-platform-infra.yml` run on the merge SHA: it must show `logtail_exploration.inngest_luks_wrong_volume` updated in place (the alert re-plans unchanged).
- [ ] 3.3 Once the apply lands both resources, `gh issue close 8874 -c "<apply run URL + live-probe numbers>"`. Do not gate on the scheduled drift plan — it is the standing backstop.
- [ ] 3.4 Optional same-day sanity: re-run control C post-apply.
