# Decision challenges — feat-one-shot-8706-luks-monitor-timer-dark

Recorded headless by `soleur:plan` / `soleur:plan-review` (2026-09-27). `ship` renders these into the
PR body and files one `action-required` issue.

## UC-1 (user-challenge): close #8706 after one timer-fired night instead of three

- **Source:** plan review, `soleur:engineering:review:dhh-rails-reviewer`.
- **Stated direction (default, kept):** #8706's re-evaluation trigger closes the issue after a
  host-unit `OK:` row appears on 3 consecutive days.
- **Challenge:** a daily timer that fired once is armed; staying green afterwards is the new logs
  alert's job, so the follow-through script and its credentials baseline bump could be dropped.
- **Why the default stands:** the three-night criterion is the issue author's own closure rule, and
  the follow-through script doubles as the plan's no-SSH discoverability probe.
- **To change it:** edit #8706's re-evaluation trigger; the work phase then closes on the first
  hour-00 row and drops `scripts/followthroughs/luks-monitor-host-timer-8706.sh`.

## T-1 (taste): a separate host-only Better Stack heartbeat instead of a logs alert

- **Source:** `soleur:engineering:cto` (plan-time domain review, preferred alternative).
- **Chosen:** the ADR-218 logs absence alert (no new heartbeat object, Doppler secret, unit env var
  or `luks-monitor.sh` edit). **Trade-off accepted:** the alert also fires when Vector or the Logs
  source is down; its incident text tells the operator to check the pipeline first.
