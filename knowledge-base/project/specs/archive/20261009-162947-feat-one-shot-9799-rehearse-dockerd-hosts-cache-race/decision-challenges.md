# Decision challenges: feat-one-shot-9799-rehearse-dockerd-hosts-cache-race

## 2026-10-09 plan: a new offline suite where the brief said "if one exists"

Class: User-Challenge (adds scope the operator conditioned on something that is not true).

- Operator direction: "add offline test row(s) in the existing zot-image-rehearse test suite if one exists".
- Finding: no such suite exists. The only suite that opens `zot-image-rehearse.sh` is `web-ghcr-deny.test.sh`
  (its census), which is not a test of the probe.
- Plan default: create `apps/web-platform/infra/zot-image-rehearse-probe.test.sh` (5 rows, 4 mutations, behavioural,
  PATH shims) plus a source guard in the script so the one function can run offline.
- Alternative the operator may prefer: ship the fix with no new suite (CI `rehearse` legs are the verification),
  or only a static assertion in `web-ghcr-deny.test.sh` (one `docker pull` line, no `/dev/null` on it, a sleep
  before it). The plan-review simplicity seat recommended the static form; the plan keeps the behavioural suite
  because a static grep is satisfiable by a stub.
- To change: drop Phase 1, the source guard, and the suite acceptance criteria; the fix itself is unaffected.

## Resolution (work phase, 2026-10-09)

Resolved by the operator brief's own condition ("add test rows to the existing suite if one exists"): no suite
for the probe exists, so no new behavioural suite file was created. The probe is guarded inside the existing
`web-ghcr-deny.test.sh` instead (a static `probe` check plus a driven run of the extracted function, mutation
rows 28-44, floor 56). The source guard the plan proposed was not added.
