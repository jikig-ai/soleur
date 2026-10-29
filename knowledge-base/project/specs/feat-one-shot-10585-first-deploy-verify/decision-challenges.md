# Decision Challenges — feat-one-shot-10585-first-deploy-verify

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Standing notify-only watchdog on a permanently-open tracker vs per-replace tracker vs ADR-218 paging alert | technical | pending - assumed: standing notify-only probe (exit 5/2/3/78, never 0/1) on a standing open tracker — the sweeper substrate is built for clock-bounded obligations; per-replace trackers cannot parameterize probes under `env -i`; the paging tier is already scoped to open sibling #10584 |
| Verdict source: Better Stack journald `host_name` Deploy-succeeded marker vs `/hooks/deploy-status` `peers["<ip>"].exit_code` grade | technical | pending - assumed: journald marker — the proven `web2-plugin-seed-8743.sh` template with `host_name` join and positive control; the deploy-status peers grade is documented as the fallback in the plan's alternatives table |
| Population covers `web_host_create` (births) in addition to `web_host_replace` | technical | pending - assumed: both — the issue's own framing is "the missing arm is boot→first-deploy"; the emitted-line anchor `web-host-(replace|create)` is shared, so covering births costs one alternation and closes the identical gap |
| First-deploy deadline = 2 days | technical | pending - assumed: 48h — mirrors the #8743 `earliest=merge+2d` convention; releases land far more often, and 48h is comfortably inside the ~5-day blind spot the incident measured |
| #10585 closes post-enrollment (PR body `Ref`, `gh issue close` after the tracker is filed) vs directive on #10585 itself kept open | technical | pending - assumed: dedicated standing tracker + `Ref #10585` — keeps issue lifecycle clean; a directive on #10585 would either auto-close the watchdog's home or leave the work item permanently open |
