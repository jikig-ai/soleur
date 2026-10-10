# Decision challenges: feat-one-shot-9728-ci-draft-light

## 2026-10-09 plan review (headless)

### User-Challenge 1: gate 6 passes on a substituted bound, not a measured post-policy mean

- Operator direction (default, kept): "pass only if the post-policy mean >= 2.75", measured as pre-policy and post-policy means over a 30-day census.
- Challenge (DHH, code-simplicity: collapse to PASS/FAIL on the raw mean and print the floor as information; Kieran: if the floor substitutes for the measurement, record it as a deviation, rename it a floor and compare in integers).
- Applied: the rule stays two-sided. PASS needs the raw mean AND `POLICY_FLOOR_MEAN` (pushes minus CI-failed pushes, per PR) at or above 2.75, because no post-policy population exists (the policy is enforced nowhere, see the plan's Reconciliation table) and a measured post-policy mean replaces the floor if Phase 0 finds an enforcement date with 30 days behind it. When the mean passes and the floor does not, the verdict is INDETERMINATE (hold, no `ci.yml` change), never a silent PASS. The planning pilot (8.24 mean, 7.18 floor) says PASS, so the hold branch is expected to stay unused; it is kept as the only reading of the operator's rule that does not loosen it.

### User-Challenge 2: Phase 7 reader fan-out versus a wait-step-only stage

- Operator direction (default, kept): the issue lists `monitor-pr-checks.sh`, ship Phase 6/7, `drain-prs`, `merge-pr` and `admin-merge-ready.sh --wait` as consumers that must resolve from the newest non-draft run.
- Challenge (code-simplicity): if gate 1 shows the newest row per name decides, readers already see PENDING; ship only `wait-ready-run` and patch a reader only where gate 5 shows a misread.
- Applied in part: every reader edit starts from a failing fixture row, so a reader that already behaves correctly is pinned rather than edited. Not applied in full: until the aggregator runs (up to 38 to 51 minutes after the ready event) the newest `test` row IS the draft run's red one, which gate 1 does not change.

### User-Challenge 3: the S4/S5 parking rule can deadlock under Branch C

- Operator direction (kept): S4 (#9729) and S5 (#9730) stay parked until S3 has a post-merge census or closes by gate or stop rule.
- Challenge (spec-flow): Branch C (hold, policy never enforced) neither closes S3 nor produces a census, so S4 and S5 wait forever. The plan holds them parked and states why; whether a hold should count as "closed by gate" is the operator's call.

### User-Challenge 4: gate 6 is a push count; the saving is minutes

- Operator direction (kept): pass at a post-policy mean of 2.75 pushes per draft PR.
- Challenge (spec-flow): a push-count PASS can be net-negative in minutes if the light run is expensive. The plan prints the minutes break-even as an informational line and raises a negative result to the operator before Branch B proceeds; it does not add a second verdict input on its own authority.

### Taste notes (not applied)

- DHH: widen/narrow guard matrices. Declined; the Guard Contract lint requires the shape and duplicated rows are annotated with the suite that also covers them.
- Code-simplicity: replace the `draft-light` live read with a `RUN_ATTEMPT == 1` guard (the S2 `push-dedupe` pattern). Declined: ADR-276 Decision 4 and the issue say the draft state is resolved live, because a re-run reuses the original payload and `RUN_ATTEMPT` does not say whether the PR has been readied since.
- Code-simplicity: drop the 1-day dark-merge deadline and the dark-merge option. Kept (CTO asked to bound the dark window rather than remove the option).
- Spec-flow: bot PRs opened as drafts gain a real full run on the human ready click; the plan accepts that and subtracts those runs from the net-minutes criterion. The alternative (excluding bot heads from the ready run) is an Option T-style skip and is the operator's call.
- Code-simplicity: activation gated on a `S3-CONFIRMED` marker is inferred from the S2 precedent and the CTO's advice, not stated by the operator. Kept; the alternative is "the operator's explicit go only" (which the repo's production-write rule already demands). Surface for the operator.

### Not Yet Specified candidates

None.

## Review round (2026-10-10, PR #9885): challenges applied, declined and recorded

Applied (fixes): the resolver's API-error marker is `state=error` outside the closed set (every consumer stub now prints the real shape); `verdict` and `wait-ready-run` answer n/a / ok when the repo's default-branch ci.yml has no `draft-light` job (customer repos keep today's flow); no skew allowance; stall window 120 minutes; `wait-ready-run` exits 3 with reason `api-error` when the last poll could not read; jq epochs instead of GNU `date`; triage keys the newest row on workflow and name; the webhook filter is scoped to `jikig-ai/soleur` and its whole lookup is deadline-raced; AGENTS rule `wg-after-marking-a-pr-ready-run-gh-pr-merge` now says arm after `wait-ready-run` exits 0 (ack recorded); the protocol lives once in `ship/references/ready-run-wait.md`; test harnesses tell a crash from a catch and have known positives.

Declined, with the reason (none files an issue: each is a design preference on code that is built, tested and pinned, not a defect):
- Cut the soak probe's `S3-CONFIRMED` ordering, the `bad_ready` GraphQL join and the merge_group sweep (design-simplicity). The probe is the only detective control the ADR names for a setting no code path can refuse; removing checks now would remove the evidence the exit census is judged on. The API-budget concern is real: the open-PR list is not paginated (stated in the probe header) and the sweep is bounded per run; a pre-filter on a single `statusCheckRollup` read is a follow-up if the sweeper token starves.
- Fold `awaiting-approval` into `no-run` (design-simplicity). No fork PRs exist today, but a fork run waiting for approval is the one human-only recovery in the flow, and folding it would tell a maintainer to undo and re-ready a PR that needs a click; the cost is one state in a closed set that every consumer and test already enumerates.
- Replace `ready-count` + `--before-count` with one `ready` verb (design-simplicity). The ordering hazard is real and is now pinned by the L2 row (known negatives for K-after-ready and a deleted wait); a single verb would also run `gh pr ready`, which the resolver, being read-only, deliberately never does.
- Stall only on `no-run` (design-architecture alternative to a larger N). Kept `pending-full` stalling too, at 120 minutes: a run in flight for two hours is not healthy, and the soak criterion is "zero queue stalls".
- Billed-minute baseline and one-day sample (design-performance). Recorded in the ADR as the unit and denominator of the criteria; the exit census measures against its own run set.
- Restoring the ~1.8 KB of "Why" prose trimmed from `ship/SKILL.md` to fit the byte ceiling (agent-native). The ceiling is exact (274,000 bytes) after this round; the structural fix is already taken (the protocol moved to a reference), and restoring the unrelated prose needs its own PR that extracts something else.
