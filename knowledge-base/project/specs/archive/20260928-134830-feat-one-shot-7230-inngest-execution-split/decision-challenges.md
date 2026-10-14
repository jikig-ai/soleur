# Decision challenges: #7230 Inngest execution placement

These are taste decisions from plan review (`soleur:plan-review`, 2026-09-28) that were **not**
auto-applied. The plan keeps the CTO ruling in each case. They are recorded here for `ship` to
render.

## T1: Three placement classes vs two (Taste)

- **Challenge:** DHH and code-simplicity propose collapsing `host-affine` and `volume-bound` into a
  single `pinned` class with the detail kept in `reason`. Today only the `portable` boundary is
  enforced.
- **Kept:** three classes. The CTO ruling (Q2) says they have different future hosts: any single
  app host versus the `/mnt/data` holder. The #9137 Phase-3 consumer needs the distinction.
- **Cost of the alternative:** a lossy class that #9137 would have to re-split.

## T2: Manifest key is the function id vs the route.ts identifier (Taste)

- **Challenge:** code-simplicity. Keying by the route.ts identifier drops the AST id extraction.
- **Kept:** the function id, per the CTO ruling (Q3). It is the identity that survives a move,
  and it matches `EXPECTED_CRON_FUNCTIONS`.

## T3: Full mutation matrices vs one RED plus one PASS per guard (Taste)

- **Challenge:** DHH calls the matrices "a test suite for the test suite".
- **Kept:** the matrices, as required by the plan Phase 2.12 Guard Contract gate and by
  `scripts/lint-guard-contract.py`. The low-value self-config harness rows were cut (R8).

## T4: ADR-030 pointer, C4 edge edit and registry-test comment (Taste)

- **Challenge:** code-simplicity says none maps to a stated property.
- **Kept:** all three. Each is a one-line discoverability aid. The C4 edit makes the single
  step-executing host visible in the model.

## T5: Split `_cron-shared.ts` into pinned and generic modules (Taste, deferred)

- **Challenge:** DHH says that with the split, plain reachability works and the allowlist and
  `stopAt` go away.
- **Deferred:** the split changes runtime imports in about 50 files, which is outside this PR's
  no-runtime-change scope. Noted for #9137.
