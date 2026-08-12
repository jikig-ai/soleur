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

### Decisions — CORRECTED AT REVIEW

Four of the five original bullets were written at plan time and reversed during review. They are
restated here as shipped; the plan-time wording is preserved in the plan itself.

- **Per-invocation-site guards, not a Phase 0 probe loop** — makes the check enforcement rather
  than instruction-following, and dissolves five reviewer findings including a false-marker
  regression on unrelated areas (`/soleur:sync conventions` invokes no producer at all, so a
  Phase 0 loop would emit a confident wrong answer on a healthy run).
  **Correction:** the original bullet said this *satisfies ADR-179 decision 5*. It does not.
  Decision 5's property is that the invocation line ALONE is safe, via an operand bound only by
  the gate; this guard's invocation line is byte-identical to the pre-fix line, so it is
  **co-located**, not fail-closed in isolation. Decision 5's *reasoning* is what applies (a gate
  separated from its invocation is not a gate). Binding the operand to a variable would satisfy
  the letter and drop it out of `extractOperands`, vacating P2's residency assertion — a worse
  trade, recorded in the ADR amendment rather than glossed.
- **`reason=absent-from-verified-root`, not `reason=stale-install`** — the marker states the
  observation; the stale-install hypothesis and remedy move to operator prose. Matches both
  existing `reason=` tokens in `sync.md`. (Unchanged.)
- **`sync.md`'s Phase 0 identity-gate fence is not edited** — the proposed `exit 0` plus
  STOP-prose retarget were cut after three reviewers showed they would degrade both of ADR-179's
  stop signals to pre-empt a hypothetical refactor. **Correction:** the original bullet said this
  unscoped. `go.md`'s Step 0.0 identity fence *body* WAS edited, to nest a presence check inside
  it. The claim holds for `sync.md` only.
- **The SHA-divergence mechanism stays deferred to #7452.** **Correction:** the original bullet
  said the user pain is *filed separately in Phase 4*. It is not — the CONCUR gate DISSENTed and
  it shipped as docs in this PR. See `decision-challenges.md` T1.
- **P6 pins presence-guard parity across the WHOLE command surface; P7 pins sync.md's marker
  grammar.** **Correction:** the original bullet described a single P6 scoped to `sync.md` that
  also pinned `affects=`. Review split them and widened P6 deliberately — `go.md` carried the
  same gap and is the higher-traffic file, so scoping around it was the defect, not the design.
  `affects=` is now a producer→area **Map** checked for correspondence, not a set checked for
  membership (3 producers against 3 areas made every permutation pass). Floors: `EXPECTED_CASES`
  13, `assertions` 14 — the vitest floor counts decided assertions, not blocks.

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
