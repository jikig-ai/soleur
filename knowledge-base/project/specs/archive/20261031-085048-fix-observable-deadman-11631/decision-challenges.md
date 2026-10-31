# Decision Challenges — fix-observable-deadman-11631

Session: one-shot planning subagent (2026-10-30), issue #11631. The binding CTO ruling for the overall
design is `deadman-ruling.md` (CTO, 2026-10-30; committed beside this file as `deadman-ruling.md`, quoted in the plan). Rows below record
forks the plan met on top of it.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| What starts the hourly feeder: GitHub `schedule:` only (the ruling's literal trigger list), a `WATCHDOG_DISPATCH_TABLE` row, an Inngest dispatcher, or schedule-only with a much wider heartbeat grace | technical | Ruled by CTO agent, 2026-10-30: Option A, add a `WATCHDOG_DISPATCH_TABLE` row (`scheduled-deadman-heartbeat-feeder.yml`, slug `scheduled-deadman-heartbeat-feeder`, `intervalMinutes: 60`) citing the ADR-248 second clause (#9703); heartbeat period 3600 and grace 3600 (luks-monitor) / 7200 (cost-capture) unchanged [SUPERSEDED for luks-monitor: the later ruling in the plan-review table below raised the luks grace to 7200, page threshold 10800 s]; workflow keeps `schedule: 0 * * * *` as fallback, `workflow_dispatch`, and a concurrency group with `cancel-in-progress: false`. Why: measured 2026-10-30 with `gh run list --event schedule`, the hourly cron of two repo workflows (59 gaps each) was delivered at gaps of min 7232 s, median 15361-16727 s, p90 about 23000 s, max about 25200 s, so a schedule-only feeder cannot hold a 7200 s / 10800 s budget (it would false-page most days once armed). Option B (Inngest dispatcher) would let an Inngest outage silence the feeder (the failure ADR-248 exists to avoid); Option C (widen grace to about 8-9 h) only slows detection and ADR-248 already rejected "retune margins only". Also ruled: the Sentry monitor follows the GHA-fired convention (`checkin_margin_minutes` at most 60, unrouted under the two-PR rule). The CTO did not verify that the luks-monitor and cost-capture checks count as "a check on the substrate" for the ADR-248 clause; if review rejects the eligibility wording the row stays anyway, because the alternative is false pages. |

## Design choices made inside the binding ruling (mechanical, no ruling needed)

| Item | Class | Choice and reason |
|---|---|---|
| One script with a target argument vs two scripts | mechanical | One script `scripts/deadman-heartbeat-feeder.sh <target>`; the workflow loops over both targets in one step so one target's failure cannot skip the other. The manifest evidence shape (`bash scripts/<x>.sh`, no arguments, `evidenceShapeOk`) is satisfied by the shared pattern; per-target step presence is pinned by the new suite, not by the manifest. |
| Exit contract on "no qualifying row" | mechanical | Follows the sibling feeder: withhold = exit 3 (Sentry `error`); exit 0 means exactly `beat` or `qualifying_row_heartbeat_paused`. The heartbeat timing out is the paging surface; the Sentry `error` is the run-level signal and is unrouted. |
| `arming_pending` on the two new manifest rows | mechanical | Required: the nightly live reconcile raises `fed-but-paused` for a paused heartbeat whose feeder exists unless the row declares `arming_pending: { tracking_issue: 11631 }`; the ruling's "born paused, owner arms" is exactly that deferred-arming state. Removal is a later record PR after the owner's measured arm. |
| `luks_monitor_runbook_url` local | mechanical | Unused once the alert is gone: delete it. The runbook heading `### Host-timer liveness alert (#8706)` keeps its text so the anchor `#host-timer-liveness-alert-8706` (cited by ADRs, the post-mortem and the feeder's marker text) stays valid; its body is rewritten for the heartbeat. |
| `INTENDED_DESTROYS` census entries | mechanical | `tests/scripts/test-infra-privileged-tier-census.sh` G4c fails a deleted resource block with no `removed` block unless the address is in `INTENDED_DESTROYS` and still bare-targeted by the apply workflow (the #9062 / #8714 precedent). Add the four addresses with `#11631`; keep the four `-target=` lines. |

## Plan-review outcomes (2026-10-30, headless; DHH, Kieran, code-simplicity, plus a sharp-edges audit)

Mechanical findings were applied to the plan (cut: `stale_row` second chokepoint and the clock seam, the permanent
base-ref predicate anchor, ADR-117/ADR-119 amendments and the post-mortem pointer, the pre-written Phase 0.3
pre-filter and the duplicate selftest pin, Guard 4's third-target row; added: `function-registry-count`
`NON_INNGEST_MONITORS`, `sentry-monitors-audit` count and README, `test-affected-paths.sh` array, a home and lexing
rules for the 900 s sentinel, curl timeouts and no-retry, the empty-aggregate answer contract, the Phase 0.1 hard gate,
the retained `workspaces-luks-provision.sh` stale comment, an explicit residual-set sweep AC, content anchors in place
of line numbers, `actionlint`, the PR-body first-line statement and `Automation:` lines).

| Item | Class | Ruling |
|---|---|---|
| Replace the python SQL-subset evaluator stub with canned `{n,newest}` answers (DHH, code-simplicity) | taste | Kept the evaluator. The binding ruling's tests are fixtures at ROW level ("row 26 h old beats; 28 h old withholds ... a `soleur-web-2` row withholds; a verify-job row without `_SYSTEMD_UNIT` withholds"); with canned answers the web-2 and verify-job fixtures would be indistinguishable from the empty case. Cutting it would drop CTO-specified test scope. Trade-off recorded: about 250-400 lines and a "not ClickHouse" fidelity limit, mitigated by the Phase 0.1 live gate. Surfaced for the operator to challenge. |
| Shrink the four-guard Guard Contract and mutation volume (DHH) | taste | Kept (the plan gate requires a contract per guard, and the ruling asks for mutation cases "in the style of `luks-monitor-install.test.sh`"); Guard 4 trimmed to the cross-surface names and the cost-capture heartbeat. |
| Drop the two follow-up issues (code-simplicity) | taste | Kept, one trimmed: the deferral rule requires a tracking issue for any deferral; one issue now covers the key-continuity reuse the ruling names, the other the stale `-target`/census cleanup. |
| Raise the luks heartbeat grace from 3600 to 7200 (Kieran in plan-review; architecture-strategist in deepen) | technical | Ruled by CTO agent, 2026-10-30: raise luks grace to 7200 (page threshold 10800 s); keep cost-capture at 7200 (threshold 10800 s). Measured 79 watchdog-dispatch gaps (max 3680 s) give about 6100 s worst-case spacing only while no slot is lost; the clock closes a slot after `MAX_ATTEMPTS_PER_SLOT = 3` failed ticks, so one lost slot gives at least 7200 s and would falsely page a healthy host at the old threshold. Cost: detection moves from the window plus 1 to 2 h to the window plus 2 to 3 h, i.e. luks about 29 to 30 h and cost about 26 to 27 h after the last qualifying row (the first draft's "28-29 h" was wrong: 27 h + 2 to 3 h; corrected to match the ADR-218 amendment). Both-clocks-dark falls to the 2-7 h schedule fallback and may still page: real degradation, out of scope. Unverified against the code by the CTO. |
