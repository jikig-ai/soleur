# Decision challenges: feat-one-shot-merge-queue-aware-behind-sync

Persisted by plan-review (headless). Each is a taste or user-challenge item for `ship` to surface; none blocks the plan.

1. **User-challenge: `Ref #8683` instead of the brief's "likely `Closes` candidate".** Three reviewers (CTO, DHH, simplicity) converged on `Ref`: the change delivers option B for queue repos only, and #8683 is already the tracker for option A with a 2026-10-24 re-evaluation. Applied in the plan; if the operator wants #8683 closed, it is a one-line follow-up.
2. **User-challenge: keep the idle-grace expiry vs rely on `MAX_POLL_MIN` alone.** The simplicity reviewer called the grace the weakest mechanism (outcome (b) is not observed in 5 of 5 PRs). Kept because the brief requires "a bounded-wait/escape" and the fallback restores today's behaviour on a stalled queue.
3. **Taste: an unreadable `gh pr checks` answer counts as idle** (walks toward the sync fallback), per the brief's "fail toward current behavior". DHH preferred holding the count to avoid a spurious sync during a `gh` throttle. Kept; the expiry needs 6 consecutive non-positive reads and re-checks `--queue-state` first.
4. **Taste: policy lives in two parity-pinned fences, not in `sync-pr-behind.sh`.** CTO: a poor long-term home once a third consumer needs queue semantics. Kept for now because `--step` cannot tell a real BEHIND from a DIRTY-derived one and the fences run a frozen script snapshot; move it into the script when a third consumer appears.
