# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-07-28-fix-fail-open-gate-preamble-actionlint-deadlock-sigpipe-assertions-plan.md`
- Status: complete
- Draft PR: #7035
- Paused at operator request after plan + deepen-plan; `/work` NOT started.

### Errors
None blocking. Five premises supplied in the invocation brief were falsified by measurement and
are recorded in the plan's `## Verified Facts` rather than silently edited:

- "nine gate call sites" → **19** (the original count counted `source` lines, not call sites)
- "D1/D2/D3 are fail-open, drive every arm RED first" → all nine gates already abort on
  missing-file and unparseable-JSON; that AC was unachievable as written
- "sentry-full-root-apply is a live fail-open" → structurally unreachable (16,892-byte producer
  vs a 65,536-byte pipe buffer; 10/10 runs returned 0). Latent shape, not a live defect.
- "ADR-149 says *five*, the header says *SEVEN* — correct them" → **already landed** (ADR-149:243
  and plan-gate-preamble.sh:13 both already record that both numbers were wrong). Verified
  independently by the parent before pausing. Residual work is the inverse correction *after*
  the retrofit lands.
- "never `grep -q` on a pipe, per AGENTS.rest.md" → **no such rule exists** (zero hits across
  AGENTS.{md,core,rest}). Verified independently by the parent. A guard for this shape does
  already ship and already runs in CI.

Two of the planning agent's own v1 claims were retracted in-plan: that extraction is "strictly
more fail-closed" (the body already starts `set -euo pipefail`), and that a file-scope
`return 1` fails open (`set -e` is armed, so it fails closed).

### Decisions
- **#7002 fixed by extraction, not splitting.** The `run:` body has zero `${{ }}` expressions and
  zero heredocs, so it moves to `scripts/cutover-inngest.sh` as one byte-exact diff — dissolving
  the risk of restructuring a cutover that was dispatched twice on 2026-07-24 and failed both times.
- **The derivation command ADR-149 publishes goes vacuous the moment this PR lands.**
  `grep -L plan_gate_assert_readable` is satisfied by the `declare -F` guard line alone, so a gate
  that sources the preamble but never calls it would pass. Every use is re-anchored on the call form.
- **Priority inverted by call-site count.** `web2-retire-gate.sh` is sourced by no workflow (blast
  radius zero, sequenced last); `stock-preflight-gate.sh` — nominally "lower-priority tier" — is
  sourced 8×, more than any Tier-1 gate.
- **~2,000 lines of scaffolding cut.** Four proposed lint scripts → one six-line CI step guarding
  the direct `rc=124` signal; a 90-arm mutation battery → ~4 arms/gate on the existing
  `mutate_layered` harness.
- **#7024 scoped to two files**, cross-linked to open issue #7005 (~800-site corpus). Recorded as a
  User-Challenge because it narrows operator-stated scope.

### Components Invoked
- `soleur:plan` → `soleur:plan-review` → `soleur:deepen-plan`
- Research: `repo-research-analyst` ×2, `learnings-researcher`
- Domain/advisory: `soleur:engineering:cto` (Phase 2.5 + devex-lensed review), scoped strong-model consult
- Plan-review panel (6): `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
  `architecture-strategist`, `spec-flow-analyzer`, `cto`
- Verification tooling: `gh`, `git`, `jq`, `python3`+PyYAML, `actionlint`, `shellcheck`,
  `scripts/lint-agents-rule-budget.py`
