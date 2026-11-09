# Decision Challenges — feat-one-shot-11544-monitor-required-wiring

The pipeline brief carries the CTO ruling for this item verbatim (2026-11-08). The `technical` row below records it;
`soleur:ship` renders this table into the PR body. Rows are ruled, none pending.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Which #11544 item is next, and how wide: monitor half only, or monitor half plus the ship Phase 7 poll? | technical | Ruled by CTO agent, 2026-11-08: the next delegable item is the #11544 monitor half only (wire `monitor-pr-checks.sh` to `ci-head-verdict.sh required` on the green-but-blocked exit). Constraints from the 2026-10-30 comment on #11544: read the `SOLEUR_CI_REQUIRED_SET` marker, never the exit code; never auto-execute `RECOVERY` lines (print only); call `required` only when the verdict is full-decided, auto-merge is armed and the PR is un-queued after about 10 minutes; wrap the call in a Bash `timeout 120` (`required` is read-only, it runs `admin-merge-ready.sh` without `--wait`). The ship Phase 7 poll and its fixture suite stay on #11544 as a follow-up; do not widen. Dissent: if the monitor half cannot be wired without the Phase 7 fixture suite, stop and report. Flip evidence: an open PR touching `monitor-pr-checks.sh` appears, or `required` turns out to need a workflow edit. Checked at plan time: no other open PR touches the monitor script, and the wiring needs no workflow edit. |
