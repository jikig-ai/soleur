# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-10-legal-corpus-defects-7349-plan.md`
- Status: complete (recovered mid-phase — see Errors)

### Errors
- An API stall ("Response stalled mid-stream") terminated the planning subagent ~19 min in, after
  44 tool calls / ~268k subagent tokens, with **nothing persisted to disk**. Recovered by resuming
  the subagent's live context and instructing it to write the plan file before any further fan-out.
  The underlying pipeline gap — `soleur:plan` completes its whole Phase 1 research fan-out before
  its first write — is filed as #7418.
- The first plan draft carried four false claims inherited from the #7349 issue body (PA-30
  re-home, E2 forum conflict, E5 direction, two of E8's three limbs) and two unshippable acceptance
  criteria (AC8 unsatisfiable, AC19 unreachable). All caught by CLO review and corrected; the
  reversals are recorded in the plan rather than silently absorbed.
- A PreToolUse hook blocked one edit on manual-infrastructure phrasing. Phase 2.8 genuinely does
  not apply; recorded the sanctioned `iac-routing-ack` with written justification rather than
  rephrasing to evade the check.
- `ListAgents` became unavailable mid-session after an MCP disconnect, so agent progress could not
  be polled.

### Decisions
- **Ship as one PR.** E1/E5/E8 remain cross-document even after the CLO's corrections; splitting
  would move contradictions rather than resolve them.
- **Re-characterise PA-30 in place** (not re-home to the Art. 30(2) register) and add a `P-2`
  reservation stub for the first arms-length store owner — reversing the plan's own B4 on CLO
  ruling. Re-homing would have dropped six of PA-30's limbs past a silently-passing deletion gate.
- **Carve `gdpr-policy`'s Art. 6(1) lawful-basis bullets back into scope** (CPO); defer only the
  orthogonal copy work, with the mirror-drift ratchet making progress permanent.
- **Tier 1, `TC_VERSION` 2.4.0 → 2.5.0 MINOR**; real-user blast radius measured at zero.
- **Treat gate firings as signal** — AC33 requires reading every gate script's diff to confirm
  nothing was weakened to make a check pass.
- **DPD scope-block referent hazard is in scope for this PR:** inserting a restored §2.3 item above
  the hard-wrapped block silently re-points its "The paragraph above" referent while **both**
  write-time gates stay green, because the block's own line never changes.

### Components Invoked
- `soleur:plan`, `soleur:deepen-plan` (halts 4.6/4.7/4.8 pass; 4.5/4.9/4.10 not triggered;
  2.8 reviewed and acked)
- `soleur:legal:clo` — six rulings with drafted replacement wording; merge sign-off deferred to
  diff-time
- `soleur:product:cpo` — sign-off conditional on four corrections, all folded in
- `soleur:engineering:research:learnings-researcher`
- `Explore` ×3 — write-time gate mechanics, T&C contradiction enumeration, defect verification
- `gh` CLI (premise validation, code-review overlap scan across 64 open issues), `git`, both legal
  lint gates run live against the clean tree

## Scope Verification
`git diff origin/main...HEAD --name-only` → only `knowledge-base/project/plans/` and
`knowledge-base/project/specs/`. No product-code breach of the plan-only mandate.

## Plan Shape
1,125-line plan, 41 acceptance criteria; `tasks.md` = 75 tasks across 10 phases.
E9 (AUP mirror Eleventy-template divergence) moved Phase 5 → Phase 4 as a precondition of the
Phase 6 ratchet activation.
