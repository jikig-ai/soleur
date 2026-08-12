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

### Scope caveat carried into implementation — CORRECTED AT REVIEW
An earlier draft of this section asserted flatly that closing #7474 does not resolve the
reporter's incident. That is the **H3** branch, which the plan itself rates *UNKNOWN — probably
cannot*, while **H2** (instruction/payload split) is rated *PLAUSIBLE and consistent with the
report* and says the opposite: the reporter observed `SOLEUR_ROOT_OK=1`, a gate that only exists
post-#7443, while `installed_plugins.json` held a pre-#7443 SHA — so their next run executes a
`sync.md` carrying these guards against the same stale root, the marker fires, and the incident
IS resolved.

Stated correctly: resolves the reported incident under H2, does not under H3; the plan's
evidence favours H2. Independently of which holds, the guard covers torn payloads and every
future producer, and P6 makes it mandatory for producers that do not exist yet.

Asserting the H3 conclusion as fact was the same error class UC1 refuses on
`reason=stale-install` — reasoning from the least-supported branch — pointed the other way.

The update-path pain (marketplace update != install update) shipped as docs in this PR, not as a
separate Phase 4 issue; see `decision-challenges.md` T1 for the CONCUR-gate DISSENT that changed it.

Three operator-stated decisions were changed rather than silently applied — recorded in
`decision-challenges.md`: the `reason=stale-install` token, the Phase 0 placement, and the remedy
sentence.

### Components Invoked
`soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`; agents: `repo-research-analyst`,
`learnings-researcher`, `engineering:cto` (structural + devex passes), scoped strong-model advisor
consult, `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
`architecture-strategist`, `spec-flow-analyzer`, `product:cpo`.
