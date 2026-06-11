# Learning: premise-validation must grep the ADR corpus for the proposed *mechanism*, not just the cited issue refs

## Problem

`/soleur:go #5087` ("Model-tiered maker/checker: pin cheaper models on explorer
agents, stronger models on reviewers") routed to brainstorm → one-shot. The
issue proposed tiering agent models via **`model:` frontmatter** (haiku on
research agents, opus on reviewers). Brainstorm premise-validation verified the
mechanical facts (the field exists, set to `inherit` on all 66 agents; built-in
agent types are out of scope) and the operator confirmed both decisions via
`AskUserQuestion`.

**All of that was premised on an approach an Accepted ADR had rejected the day
before.** `ADR-053` (Accepted 2026-06-10, shipped via PR #5096) chose
**workflow call-site pins** for exactly this cost-reduction goal and listed
"Frontmatter tiering (pin research agents to `sonnet`)" as a **rejected
alternative** (context-blind, silently upgrades cheap sessions, re-fights the
2026-02-24 model-policy standardization). Issue #5087 was filed without
awareness of ADR-053; the brainstorm premise-validation grep looked for the
*cited issue numbers* (#5087, #5086 — both OPEN, no collision) but never grepped
the ADR corpus for the *proposed mechanism* ("frontmatter tiering" / "model
tiering"). The conflict surfaced only at **deepen-plan's adversarial
architecture review** — three phases and one full plan deep, after the operator
had already confirmed a now-conflicting design.

A second, subtler trap rode along: the operator's confirmed "pin reviewers to
`opus`" decision was actively *counterproductive* — a frontmatter pin is
absolute, so on a Fable 5 session (the most capable tier) it would **downgrade**
reviewers to Opus. The operator approved it without that fact because the
brainstorm hadn't surfaced ADR-053's absolute-pin semantics.

## Solution

deepen-plan's architecture-strategist caught the ADR-053 conflict and proposed
**Option C**: a narrow, additive, floor-safe `haiku` pin on the 5 research
agents only. It survives ADR-053's rejection reasons because a `haiku` *floor*
pin can never upgrade any session (neutralizing the "silent cheap-session
upgrade" objection that was written against a `sonnet` pin), uses Model
Selection Policy §1's existing override mechanism, and leaves reviewers at
`inherit` (which already yields strongest-available-per-session, avoiding the
Fable-downgrade trap). The pipeline paused, re-surfaced the conflict + the
Fable-downgrade fact to the operator, who chose Option C. Shipped as 5
frontmatter pins + a §1 policy exception registration — no ADR supersession, no
clo attestation.

## Key Insight

**A feature's proposed *mechanism* is a premise, not a given — and the
authoritative record of "we already decided against that mechanism" is the ADR
corpus, keyed by mechanism keyword, NOT by issue number.** Premise-validation
that only checks cited issue/PR state (open/closed/collision) is blind to a
decision recorded against the *approach* under a different issue. Before
accepting a feature's framing in brainstorm/plan, grep
`knowledge-base/engineering/architecture/decisions/` for the proposed
mechanism's keywords and read any hit's `## Decision` + `## Alternatives
Considered`. A mechanism named in an ADR's rejected-alternatives table is not an
unconsidered idea — it is an explicitly-rejected one, and the brainstorm's job
becomes "did the ADR leave a gap this still addresses?" (here: yes — ADR-053's
workflow pins don't reach `/plan`'s direct, unpinned `Task` research spawns), not
"design the rejected thing."

Corollary: when a feature proposes an *absolute* config value (a pinned model, a
fixed tier, a hardcoded limit), check its interaction with the *most capable*
end of the range, not just the cheap end. "Pin reviewers to opus" reads as a
safety upgrade but is a downgrade on a Fable session.

## Session Errors

1. **ADR-053 mechanism-vs-framing premise miss.** Brainstorm + `/go` +
   operator-confirmed decisions matched the alternative ADR-053 rejected one day
   prior; premise-validation greped for issue refs, not the proposed mechanism
   against the ADR corpus. **Recovery:** deepen-plan's architecture-strategist
   flagged it; surfaced to operator → Option C. **Prevention:** brainstorm
   Phase 1.0.5 and plan research/premise phase must grep
   `knowledge-base/engineering/architecture/decisions/` for the proposed
   mechanism keywords before accepting the framing (routed to both skills).
2. **Edit-before-Read.** First Edit on `repo-research-analyst.md` was rejected
   ("File has not been read yet") because the frontmatter had been inspected via
   `sed`/Bash, not the Read tool. **Recovery:** used the Read tool on all 5
   files. **Prevention:** already enforced by `hr-always-read-a-file-before-editing-it`;
   one-off — Bash inspection does not satisfy the Edit tool's read-tracking.
3. **Planning subagent worktree-path Write (forwarded).** One Write was blocked
   by the worktree-write hook (a non-worktree path was used), corrected
   immediately to the worktree path. **Recovery:** re-issued against the worktree
   path. **Prevention:** already hook-enforced; one-off.

## Tags
category: workflow-patterns
module: brainstorm, plan, one-shot
