# Decision Challenges — feat-one-shot-7442-sync-plugin-root-anchoring

Headless run, so per `plan/SKILL.md` Step 4.5 these are persisted for `/soleur:ship` to
render into the PR body and file as an `action-required` issue.

---

## DC-1 — The `${CLAUDE_PLUGIN_ROOT:-…}` fallback convention is unsafe on the CLI

**Class:** user-challenge — it contradicts an established, ADR-cited repo convention
**Raised by:** Step 4.5 strong-model consult; independently confirmed by architecture review
**Status:** **UPHELD by direct measurement.** The plan changed; the convention did not
(yet).

### The challenge

The plan originally anchored producers as `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/…`,
following the repo's dominant convention (55 sites). The consult observed the fallback
is itself CWD-relative — *"the bug class reintroduced inside the fix."*

### What the measurement showed

| Fact | Evidence |
| --- | --- |
| `CLAUDE_PLUGIN_ROOT` is **unset** in a plain CLI session | measured directly this session |
| The repo already documented this twice | `plans/2026-07-21-fix-preflight-check-10-folded-scalar-parser-plan.md:369`; `plans/2026-07-08-fix-residual-plugin-root-migration-agent-run-skills-plan.md:186` |
| The export invariant is **Concierge/server-only** | ADR-093 §Amendment — `buildAgentEnv`, `/app`-validated |
| **Neither** fallback form reaches a marketplace install | `./plugins/soleur` → customer CWD; `$(git rev-parse --show-toplevel)/plugins/soleur` → customer repo root. A marketplace customer has the payload at neither. |

So the challenge was correct, and stronger than stated: the convention is CLI-correct
only because its CLI user has so far been the dogfooding operator standing in this
monorepo.

### Resolution in this plan

The plan no longer adopts the convention for customer-facing producers. It adds a
**blocking Phase 0** that measures whether `CLAUDE_PLUGIN_ROOT` is exported in
plugin-*command* context and binds the remedy to that outcome, with one invariant fixed
in advance: **no `:-` fallback into a customer-writable path.**

### What the operator is being asked

Two questions this PR should not decide alone:

1. **The repo-wide convention.** 93 existing sites use a `:-` fallback that cannot reach
   a marketplace install. If Phase 0 confirms the variable is unavailable in command
   context, those sites are latent instances of #7442 — a much larger remediation than
   this issue, overlapping #6222.
2. **Whether a marketplace-installed plugin can locate its own payload from a command's
   shell at all.** If not, that is a harness/packaging capability gap, and #7442 is a
   symptom rather than the defect.

**Recommendation:** land this PR on the Phase 0 outcome; open the repo-wide question
separately with the measurement attached.

---

## DC-2 — Amend ADR-093 vs mint a new ADR

**Class:** taste (architectural document boundary)
**Status:** Reversed during review — the plan now mints a new ADR.

The first draft proposed amending ADR-093 to avoid ordinal-collision churn. Review
established that `scripts/check-adr-ordinals.sh` already exists and is fail-closed
(removing the process rationale), and that ADR-093 is surface-bound to the
platform/Concierge path whose machinery has no CLI equivalent. Recorded here because it
reverses a decision the plan previously argued for, and because minting an ordinal
carries the collision risk the original choice was avoiding — the new ADR's ordinal must
be re-derived across all `origin/*` refs immediately before merge.
