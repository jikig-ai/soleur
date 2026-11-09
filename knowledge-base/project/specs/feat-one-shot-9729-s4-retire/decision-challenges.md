# Decision Challenges — feat-one-shot-9729-s4-retire

Source: `knowledge-base/project/plans/2026-11-09-ci-s4-stage-retirement-plan.md` §Decision Challenges. Rows follow the `| Item | Class | Ruling |` contract (Class: `technical`, `taste`, or `operator (<category>)`). The CTO agent could not be spawned on this harness (no subagent spawn tool), so technical rows carry `pending - assumed: <default>` per `technical-ruling-delegation.md`; ship phase renders this table into the PR body and files an `action-required` issue if any row is unresolved at ship time.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Retire-vs-schedule the S4 stage (the fork itself) | operator (irreversible authorization) | **Ruled by CTO agent + operator authorization, 2026-11-09** (issue-comment 6751457876): retire — no further evidence-tooling round funded; criterion (a) concluded at NO-GO, criterion (c) caps further rounds at UNDECIDED. BINDING; this plan executes it. |
| New oracle-list home: committed `scripts/ci-oracle-surface.txt` vs embedding the list in `ci-oracle-review.sh` | technical | pending - assumed: dedicated committed list file — base-sourced, greppable, self-membered, frees the sentinel's extractor from importlib-on-.py |
| Oracle-list membership: union(old `RATCHET_ORACLE` − retired members) + `ci-oracle-lane-legs.tsv` + the list file itself | technical | pending - assumed: that set — covers every live lane file; the legs.tsv addition closes a pre-existing gap (in `is_excluded_path` but absent from `RATCHET_ORACLE`) |
| List-resolution fallback chain during transition (base `ci-oracle-surface.txt` → base `ci-pr-affected-replay.py` legacy import → HEAD `ci-oracle-surface.txt`) | technical | pending - assumed: the chain above — mirrors the driver's existing HEAD-copy fallback for pre-PR3b bases; the only ordering that keeps this PR's own `oracle-review-required` check green while its base lacks the new file |
| Atomic diff + `gh pr merge --admin` vs two-PR sequence for the required-context removal | technical | pending - assumed: atomic + admin merge — mirrors the #12089 removal precedent exactly (the only precedent for removing required contexts whose producers die in the same diff) |
| #12155 (PR3b-lite ratchet-verdict drift gate) disposition | operator (scope) | pending - assumed: close *not planned* — it arms the verdicts of the retired ratchet; flagged for ship-phase confirmation |
| #12456 (replay collect window tip) disposition | operator (scope) | pending - assumed: close *not planned* — it patches `ci-pr-affected-replay.py`, deleted in Phase 4; flagged for ship-phase confirmation |
| #10949 disposition | operator (scope) | pending - assumed: close *not planned* — doubly dead (the probe file no longer exists AND the machinery it observed is retired); the brief asked for evaluation, this is the evaluation |
