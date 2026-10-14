# Counsel-Review CLO-Attestation Gate

Moved verbatim out of `ship/SKILL.md` Phase 5.5 to stay under the SKILL.md body ceiling (ADR-229); SKILL.md keeps the trigger and a load directive.

**The reviewing authority for legal-doc attestation is the `soleur:legal:clo` agent, NOT the human operator.** The Soleur user is a non-lawyer founder; deferring legal sign-off to them bottlenecks indefinitely and mis-allocates expertise (the `soleur:legal:clo` agent orchestrates `soleur:legal:legal-compliance-auditor` + `soleur:legal:legal-document-generator` and can cross-check prose against statute and against the implementing migration in one cycle). This is symmetric to how `soleur:plan` routes CPO sign-off to the CPO agent. See `knowledge-base/project/learnings/workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md` (the operator has corrected human-routed legal sign-off ≥3×).

**Trigger:** the PR diff touches a legal-doc directory AND the change is legal-attestation-bearing:

```bash
legal_touch=$(git diff main...HEAD --name-only \
  | grep -E '^(docs/legal/|plugins/soleur/docs/pages/legal/|knowledge-base/legal/)' | head -n 1)
# Scope the marker grep to legal-doc dirs ONLY — otherwise it self-fires on
# this gate's own prose in ship/SKILL.md or on spec/tasks.md that quotes the
# literal descriptively (false positive).
draft_marker=$(git diff main...HEAD -- docs/legal/ plugins/soleur/docs/pages/legal/ knowledge-base/legal/ \
  | grep -E '^\+.*\[DRAFT — pending CLO/counsel review' | head -n 1 || true)
sui_plan=$(gh pr view --json body --jq .body \
  | grep -oE 'knowledge-base/project/(plans|specs)/[^[:space:])]+' | head -n 1 || true)
sui_threshold=""
if [[ -n "$sui_plan" && -f "$sui_plan" ]]; then
  sui_threshold=$(grep -E '^brand_survival_threshold:\s*single-user incident' "$sui_plan" || true)
fi
# Gate fires when legal docs changed AND (single-user-incident OR a DRAFT marker is present)
```

**If triggered (`legal_touch` non-empty AND (`sui_threshold` OR `draft_marker` non-empty)):**

1. **Invoke the `soleur:legal:clo` agent via Task** with: the diff, every changed legal artifact, and the implementing files it must cross-check against (migrations, RPC bodies, the consuming TS). Instruct it to produce/attest the counsel-review audit at `knowledge-base/legal/audits/<YYYY-MM>-counsel-review-<issue>.md` (house style: `2026-05-counsel-review-4353.md`), resolving lawful-basis, consent, retention, and Art. 6(1)(f) LIA questions, and to return a per-artifact verdict + an overall disposition (DISCHARGED or BLOCKED).
2. **On DISCHARGED** — the CLO agent is the authority, so proceed without a human sign-off:
   - Apply any in-PR conditions the CLO agent names (prose corrections, LIA-test updates).
   - Remove the `[DRAFT — pending CLO/counsel review per #<issue>]` markers across `docs/legal/ plugins/soleur/docs/pages/legal/ knowledge-base/legal/` (derive the file list via `grep -rl`; do NOT strip the literal from spec/`tasks.md` descriptive references). Keep each canonical doc and its Eleventy mirror in lockstep, then regenerate `apps/web-platform/lib/legal/legal-doc-shas.ts` for each changed canonical doc. Non-T&C edits → no `TC_VERSION` bump. **Re-run `legal-doc-shas-guard.test.ts` + `legal-doc-consistency.test.ts` AFTER this marker-clearing mutation and confirm green** — Phase 4 ran the suite BEFORE this gate, so these post-mutation edits are otherwise unverified within the pipeline (a stale SHA or broken mirror lockstep would slip to CI otherwise).
   - Set the audit frontmatter `status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)`.
   - **Optional human veto (not a block).** Emit exactly one line: `COUNSEL-REVIEW: soleur:legal:clo agent DISCHARGED #<issue> (audit: <path>). Reply "veto" to hold for external counsel; otherwise ship proceeds.` Then continue the pipeline. Do NOT wait for an ack — the veto is an interrupt the operator may raise, not a gate that blocks on their input (matches the operator's chosen v1 model). If the operator vetoes, halt and route the named concern back to the `soleur:legal:clo` agent. (Headless mode: there is no veto channel — emit the line and proceed.)
3. **On BLOCKED** — the CLO agent found prose that misstates the implementation, a weak/absent lawful basis, or a missing disclosure. Halt the ship pipeline and surface the agent's named blocker + recommended fix. This is the ONLY block path, and it is an agent verdict — never "waiting on the human to do legal review."

**If not triggered:** Skip silently.

**Why:** PR #4559 (#4558, ADR-044) shipped legal amendments under a `single-user incident` threshold with `[DRAFT — pending CLO/counsel review]` markers and an issue (#4564) framed as "a genuine human CLO/CPO sign-off." That framing is the recurring bug the 2026-05-18 learning already named — legal review is a CLO-agent function. This gate closes it at ship time: the `soleur:legal:clo` agent attests and the DRAFT markers clear automatically, with the operator retaining an optional veto rather than being the bottleneck. External counsel re-review is reserved for the audit's frontmatter re-evaluation triggers (first arms-length user, EEA-out, regulated industry), not routine review.
