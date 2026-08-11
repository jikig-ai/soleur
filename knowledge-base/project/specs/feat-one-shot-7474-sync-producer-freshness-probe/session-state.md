# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-11-fix-sync-producer-freshness-probe-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Draft PR: #7475

### Errors
None. All deepen-plan halt gates passed (4.6, 4.7, 4.8); 4.5, 4.55, 4.9 and 4.10 correctly skipped.

Two research-agent claims were falsified by direct measurement and corrected in the plan's
Research Reconciliation table:

1. "No existing test verifies referenced scripts exist on disk" — P2 already runs `existsSync`.
2. "No `bunfig.toml` pathIgnorePatterns relevant to sync" — `apps/web-platform/bunfig.toml` sets
   `pathIgnorePatterns = ["**"]`, so vitest is the only runner.

One unverified capability claim ("markers are parsed by an agent that files GitHub issues") was
withdrawn per `hr-verify-repo-capability-claim-before-assert` — no such consumer exists.

### Decisions
- **Per-invocation-site guards, not a Phase 0 probe loop** — makes the check enforcement rather
  than instruction-following, satisfies ADR-179 decision 5, and dissolves five reviewer findings
  including a false-marker regression on unrelated areas (`/soleur:sync conventions` invokes no
  producer at all, so a Phase 0 loop would emit a confident wrong answer on a healthy run).
- **`reason=absent-from-verified-root`, not `reason=stale-install`** — the marker states the
  observation; the stale-install hypothesis and remedy move to operator prose. Matches both
  existing `reason=` tokens in `sync.md`.
- **The Phase 0 identity-gate fence is not edited at all** — the proposed `exit 0` plus STOP-prose
  retarget were cut after three reviewers showed they would degrade both of ADR-179's stop signals
  to pre-empt a hypothetical refactor.
- **The SHA-divergence variant stays deferred to #7452, but the user pain is filed separately in
  Phase 4** — #7452 sits in Post-MVP/Later behind 1027 issues, which is indistinguishable from
  unfiled.
- **P6 parity assertion pins guarded sites *and* `affects=` values** — scoped to `sync.md`'s entry
  (unscoped it would demand `go.md`'s operands), inserted above P5 (registration-order counter),
  non-vacuous, with remedy-bearing failure strings. Both hand-ratcheted floors bump.

### Scope caveat carried into implementation
Closing #7474 does not resolve the reporter's original incident. `commands/` and `scripts/` ship in
one payload at one SHA, so a merely-old install runs its own old `sync.md`. The guard helps torn
payloads, instruction/payload splits, and every future producer. The item addressing the reporter's
actual pain (marketplace update != install update) is filed separately into Phase 4.

Three operator-stated decisions were changed rather than silently applied — recorded in
`decision-challenges.md`: the `reason=stale-install` token, the Phase 0 placement, and the remedy
sentence.

### Components Invoked
`soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`; agents: `repo-research-analyst`,
`learnings-researcher`, `engineering:cto` (structural + devex passes), scoped strong-model advisor
consult, `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
`architecture-strategist`, `spec-flow-analyzer`, `product:cpo`.
