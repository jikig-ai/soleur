# Decision Challenges — feat-one-shot-8400-8401-8402-plugin-root-cloud-mode

Recorded headless per `soleur:plan` Phase 4.5 / Plan Review. `soleur:ship` renders these into the
PR body and files them as `action-required`. Each is a challenge to the operator's **stated
direction**, which remains the default until the operator says otherwise.

## DC1 — Split into three PRs instead of one (source: `soleur:engineering:cto`, plan Phase 2.5)

**Operator's stated direction:** "Implement and ship #8400, #8401, #8402 as one coherent change …
Close all three with `Closes #8400`, `Closes #8401`, `Closes #8402` in the PR body."

**The challenge:** the CTO advisory recommends three separate PRs —
(A) #8400 alone, as a safety fix on an unrecoverable destructive path that needs undivided review;
(B) #8402 in two commits (guard first, then the 69-file sweep);
(C) #8401 held until ADR-179 decision 11 is amended in its own PR.
Its reasoning: 69 files of near-identical diff landing beside a destructive-path fix means the
destructive-path review drowns.

**What the plan did instead:** kept one PR, and adopted the advisory's *within-PR* commit ordering
in full — Phase 1 is its own commit, Phase 3's guard strengthening is a separate commit that
precedes its sweep, and the ADR amendment lands in the same commit as the resolver change it
authorises. That recovers most of the reviewability argument without contradicting the operator.

**What the operator is being asked:** accept the one-PR shape with staged commits, or split.
Splitting means #8401 cannot close in this pipeline, because its admissibility depends on Phase 1's
capability token shipping first.

## DC2 — Close #8401 rather than resolve it (source: same advisory)

**The challenge:** the advisory's preferred option was to close #8401 against ADR-179 decision 11
as "superseded scope", or re-scope it to readiness + cloud-detect only.

**What the plan did instead:** resolved it, by addressing the ADR's stated ground (a stale cached
`worktree-manager.sh`) with a capability feature-detect on the dispatch, and amending decision 11
explicitly. Rationale: the ADR forbids one *mechanism*, not the outcome — it says #8401 is
"explicitly gated on the script-side fix #8400", i.e. it contemplated resolution — and the defect
is real (every session-start gate is silently dead on a whole harness class). Closing it would
leave the gate dead.

**What the operator is being asked:** confirm that amending ADR-179 decision 11 in this PR is
acceptable, or direct that #8401 be closed/deferred instead.

## DC3 — "Closes #8401" no longer means what the issue asked for (source: DHH, plan review)

**Operator's stated direction:** close all three issues, with `Closes #8401` in the PR body.

**The challenge:** #8401's stated acceptance criterion is a `go-session-gates.test.sh` row asserting
`gate=session-start source=devin-cache verified=true` **reaches the stubbed manager**. DHH argued the
mechanism should instead be `SRC != devin-cache` on the dispatch — resolve from the cache arm, but
never dispatch `cleanup-merged` from it. That is ADR-179 decision 11's own confinement relocated from
the resolver (where it kills four gates) to the one `bash` call it was ever about, and it is smaller
and has no blast radius. It does **not** satisfy #8401's stated AC.

**What the plan did instead:** kept the dispatch reachable from a cache root, gated on a capability
feature-detect narrowed to that arm. #8401's AC is satisfied literally, and ADR-179's surviving
ground is closed.

**Why this is surfaced rather than decided silently:** #8401's AC rests on a premise ADR-179
falsifies — the issue assumed #8400's fix would make the dispatch safe, and the ADR records that it
does not, because the dispatched artifact is a *cached copy* the fix never reaches. So "close #8401"
and "do what #8401 asked" have come apart. Either resolution is defensible; the operator should know
which one shipped.

**What the operator is being asked:** confirm the capability-gate route (keeps the dispatch, closes
the issue as asked), or direct the smaller `SRC != devin-cache` route (drops the dispatch, and
`Closes #8401` should then become `Ref #8401` with the residual named).
