# Decision Challenges — feat-one-shot-11720-mut-skip-remainder

Recorded from the `/soleur:go` resume of epic #10390 (2026-11-02). CTO ownership spawn: `Own the epic #10390, delegation https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901` — delegation `valid` (expiry 2026-11-20), no delegated act due.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Carrier-batch hold expressibility (#8525 + #8013 + RestartSec=300 half of #8080 + #10290) | technical | Ruled by CTO agent, 2026-11-02: record the hold ungated (Needs a person) — no Gate kind can express "next vinngest-v* bake/host-replace window"; pr-merged needs a concrete PR number, no-inflight-run has the wrong polarity, and the window is itself operator-sanctioned (each host replace needs a fresh go; host replace is on the Excluded list) |
| #8839 backstop shape — sweep cron vs deriveTodayCardState render | technical | Ruled by CTO agent, 2026-11-02: if the Sentry dead-letter evidence requires a backstop, build the sweep cron that settles stale "Working" rows server-side, not the render shape — the render shape is the only Product/UX-gated option and leaves rows unsettled for every future consumer, so the Product/UX call leaves the critical path - dissent: the render is cheaper (no new cron, no data write); the sweep wins on durable state and also settles the pre-fix historical rows |
| Delegation scope item 1 — is the manual scheduled-terraform-drift.yml dispatch still owed | technical | Ruled by CTO agent, 2026-11-02: not owed — the operator's own manual dispatch (run 40955212467, 2026-10-29, deruelle) and ~10 green Inngest cadence runs since satisfy "check the read-only orphan sweep"; no delegated act ran so no receipt is required — the delegation grants authority, it does not obligate |
| Delegation scope item 2 — is a revert PR owed | technical | Ruled by CTO agent, 2026-11-02: none — #11824 merge commit 3a88a52d3d shows all success/skipped check runs; the only non-green main run is the operator's in-flight inngest-key-rotate, the excluded #10382 rotation, not an epic-merge regression |
| op=backup dispatch (epic standing hold) | operator (production-mutating) | Operator-reserved — outside the recorded delegation scope (covers only scheduled-terraform-drift.yml dispatch + revert PRs); stands for the operator |
| DOPPLER_TOKEN_INFRA_PRIVILEGED seed (epic standing hold) | operator (production-mutating) | Operator-reserved — secret-store write on the denylist and the delegation's Excluded list; stands for the operator |
| #9943 machine-enforce liveness-heartbeat flip precondition (epic standing hold) | operator (authorization) | Operator-reserved — the issue's own words name it the owner's call on a new Better Stack read credential; stands for the operator |
| #8839 Sentry dead-letter evidence + 35d lifecycle check | operator (evidence fetch) | Stands — a Sentry evidence pull no Gate predicate can express; technical fork ruled (sweep-cron backstop shape, see above) so only the evidence path remains |

## Operator Holds (epic #10390 — verbatim CTO output for the plan record)

```text
## Operator Holds

Delegation: https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901
Envelope: knowledge-base/engineering/operations/runbooks/delegated-dispatch-10390-terraform-drift-envelope.md

- Hold: the deferred carrier batch (#8525 + #8013 + the RestartSec=300 half of #8080 + advisory #10290) waits for the next vinngest-v* bake / host-replace window
- Hold: #8839 (stuck-on-Working spawn backstop) waits for the Sentry spawn-agent dead-letter evidence and the 35-day lifecycle check
- Hold: Operator-reserved: #9943 — the owner's decision on a new Better Stack read credential in the cutover dispatch
- Hold: Operator-reserved: op=backup dispatch
- Hold: Operator-reserved: DOPPLER_TOKEN_INFRA_PRIVILEGED seed
```

Note: the `Envelope:` path names a file that does not exist (read-only CTO run). That is deliberate — the evaluator leaves every hold standing when the envelope is missing, and no delegated act is armed. Create the file only if the drift dispatch ever becomes due.
