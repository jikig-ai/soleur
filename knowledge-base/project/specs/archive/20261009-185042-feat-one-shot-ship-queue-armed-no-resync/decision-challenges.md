# Decision challenges (headless plan run, for ship to render)

1. Taste — unreadable `rules/branches/main` read while the PR is armed: fail CLOSED (exit 4, `kind=gh`), not open. Matches `queue_gate`; cost is that a customer host whose token cannot read rules gets a named stop instead of a sync. Alternative: fail open like the Phase 7 fence.
2. Taste — guard scope: standalone loop only, no override flag; `--step` and `pre-merge-rebase.sh` stay unguarded (tracked #9869). The brief anticipated an override flag only if the expiry path needs one; it does not.
3. Operator gate — `AGENTS.rules.md` `hr-pipeline-skills-never-inline-after-go-route` still says "BEHIND->resync main" with no queue exception (#9868). Not edited: hard-rule edits are an operator decision.
