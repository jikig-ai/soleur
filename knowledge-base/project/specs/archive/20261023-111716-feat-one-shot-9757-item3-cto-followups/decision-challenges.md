# Decision challenges (plan phase, 2026-10-22)

Headless plan run for umbrella #9757 item 3 (P3 only). No item here asks the operator to change their stated direction; the table records the technical rulings made during planning.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Stall-clock anchor for `ci-head-verdict.sh`: ready-event time T only (today), newest kept run's `created_at`, the head commit's committer date, PR `updated_at`, or the earliest check-suite `created_at` at the head sha | technical | Ruled by CTO agent, 2026-10-22: anchor (B), the earliest `created_at` among ALL check suites at the head sha, read lazily and only when the T-based test already says stalled, with `stall_from = max(T, A)` - it is the only server-assigned anchor that also covers the no-run window right after a push, it costs nothing on the common path, and the committer date (client-controlled) and PR `updated_at` (reset by any comment) were rejected |
| Behaviour when the lazy suite read fails, returns a malformed body, or returns an empty list | technical | Ruled by CTO agent, 2026-10-22: `state=error`, exit 3, never a fallback to T and never a closed-set state - an empty list right after a push would otherwise yield a spurious `stalled` that advises `gh pr ready --undo` and cancels a healthy fresh run; the next poll resolves it |
| Whether the dirty/conflicting rule, the awaiting-approval path or `wait-ready-run` change | technical | Ruled by CTO agent, 2026-10-22: no change to any of them (`awaiting-approval` never reaches the stall test; `wait-ready-run` takes T fresh by construction) |
| Order and slicing of the P4 items (one PR each, after the P3 PR merges) and P2 (needs an ADR) | operator (scope) | Already fixed by the operator brief: this run does P3 only; P4 items are listed as separate follow-up PRs and not implemented here; P2 is out of scope |
| Hybrid anchor: use the kept run's `created_at` when a run exists and read check suites only when none exists (plan-review DHH finding) | technical | Ruled by CTO agent, 2026-10-22: adopt the hybrid - the run's `created_at` is a server-assigned bound that needs no extra call and adds no failure mode on the pending-full path, so the suites read fires only for a head with no kept run |
| Keep a `head_sha == H` select in the suites jq (simplicity finding) | technical | Ruled by CTO agent, 2026-10-22: drop the select but assert head_sha equality in the shape check - the endpoint is keyed by sha, and a silent filter would turn a server fault into a healthy-looking answer |
| Operator-visible text for the persistent no-check-suites error (devex review) | technical | Ruled by CTO agent, 2026-10-22: add a stderr line naming the sha and the explicit not-judged-stalled meaning - an unexplained persistent error is the main operator cost of the anchor ruling and the consumers discard stderr on purpose, so no consumer-message change is made |
| Tracking issues for the deferred items (devex review) | technical | Ruled by CTO agent, 2026-10-22: one issue for P2 and one checklist issue for P4a-P4d - per-item issues cost more to triage than the small PRs cost to do, and the PRs stay one each |
| Where the stall rule is defined (devex review) | technical | Ruled by CTO agent, 2026-10-22: define it once in the script header and have the ADR addendum and the consumer messages point at it - one source of truth for the next edit |

Note (mechanical, no ruling needed): the ADR-276 sentence that states the stall clock ("N minutes after the ready event") is amended by a dated addendum in the same PR, because the plan extends an existing ADR (plan Phase 2.10).
