# Decision challenges (plan phase, headless)

Persisted by the plan skill for `ship` Phase 6 to render. Each entry is a reviewer or advisor suggestion that would change the operator's stated direction; the operator's direction is the default and the plan keeps it.

## 2026-10-11 — split the lint-harness refactor into a preparatory PR

- Operator direction: "ONE slice, ONE PR".
- Challenge (advisor consult): land the census-ceiling harness refactor (synthesized baseline/ceiling pair, S5 Guard 1 decoupled from the first real baseline row) as its own PR first, so the fix PR only deletes rows and rewords headers.
- Plan disposition: kept as one PR. The baseline rows, the conversion and the suite rewrites are one coupling (removing rows without converting, or converting without removing, is a red tree); the plan's Split Assessment records this.
- Decision needed from the operator only if they want the split.

## 2026-10-11 — cut the new bootstrap harness suite (`bootstrap-r2-probe.test.sh`) and the mktemp change

- Operator direction: "Owning suites must assert the key id/secret pair is absent from every recorded argv".
- Challenge (DHH and code-simplicity reviewers): bootstrap.sh is a one-shot script with no suite; replace the harness with one static row (no curl `--user`, reaches the helper) and drop the mktemp/trap change.
- Plan disposition: the ask is kept. The harness shrinks to two rows (probe argv clean and stdin carries the `user =` line; a malformed pair makes zero probe calls). A static grep proves the builder, not the wire.
