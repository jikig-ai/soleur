---
module: Brainstorm
date: 2026-11-09
problem_type: workflow_issue
component: brainstorm-skill
symptoms:
  - "An issue compared whole vendor platforms against a criterion that only one component of each platform satisfies"
  - "The issue claimed a single prior evaluation existed; the decisive prior decision lived on a month-old unmerged PR branch"
  - "A fixed-width context regex returned zero hits for a string that was present, and nearly impeached a correct leader citation"
  - "The CTO agent received an assessment request phrased with the cue that selects its ruling interface"
root_cause: coupled_decisions
resolution_type: process_fix
severity: medium
synced_to: [brainstorm]
tags: [vendor-evaluation, sandbox, egress, credential-injection, prior-art, unmerged-branch, premise-validation, "#12517", "#9842"]
---

# Learning: a deciding criterion belongs to one component; find it before comparing bundles

## Problem

Issue #12517 asked whether to keep our bwrap sandbox and CONNECT gateway or move agent execution to a managed sandbox platform (Cloudflare, Vercel, Daytona, E2B). The operator added a deciding criterion: one mechanism must cover every HTTPS-credentialed tool without per-tool code.

Framed that way, the question compares bundles. Each vendor sells isolation, lifecycle, storage and credential injection as one product, so "which platform injects credentials" reads as "which platform do we move to", and a runtime migration gets chosen to obtain a feature of the network path.

## Solution

Ask which component the criterion is a property of before ranking anything. Credential injection needs TLS termination, a CA the sandbox trusts, session-to-tenant identity and policy, all on the egress hop. None of it depends on the isolation runtime. Once that was stated, every option except per-verb tools tied on the first criterion, the tiebreak fell to cost, residency and reversibility, and the decision split in two: an injector decided now on the existing hop, and a runtime decision left with the epic that already owned it (#9842).

The operator chose that split (approach A), with a capped synthetic-data trial of one managed platform as the measured contingency and written flip facts defining when the managed path takes over.

## Key Insight

A vendor bundle couples decisions that are separable in our own architecture. When an issue ranks platforms by one criterion, locate the component that criterion belongs to first. If it belongs to one hop or layer, the comparison is between implementations of that layer, and adopting a whole platform to get it is a second, separate decision that needs its own justification.

A corollary for the criterion itself: "no per-tool code" survived only until approvals attached. Gating writes at the network layer needs per-host protocol classifiers, because one POST can carry a read or a write. A criterion stated before the security constraint is applied should be re-read after it.

## Session Errors

1. **The issue's "only prior managed-runtime evaluation" premise was wrong, and a search of `main` could not show it.** The gVisor epic's spec recorded "Managed vendors: no" with reasons, but the spec and its brainstorm exist only on the branch of PR #9832, open and unmerged for a month. Recovery: the sibling-issue search surfaced the epic, and `git ls-tree -r --name-only origin/<branch>` plus `git show origin/<branch>:<path>` read the artifacts. **Prevention:** when a sibling epic or issue cites a brainstorm or spec path that does not resolve on `main`, list open PRs for it and read the artifact from the PR's branch before accepting any "no prior evaluation" framing.

2. **A fixed-width context regex reported a present string as absent.** `grep -o -iE '.{80}TLS bump.{40}'` returned nothing because the match sits fewer than 80 characters into its line. I was one step from recording a correct CLO citation as reconstructed. Recovery: a `-l` file search, then a `.{0,90}` context pattern. **Prevention:** in a verification grep, context quantifiers are always `.{0,N}`, never `.{N}`; and an empty result from a pattern with mandatory context is not evidence of absence until the bare token has been searched.

3. **An unbounded grep on a legal document dumped 46 KB.** The privacy policy has multi-kilobyte lines, so `grep -n` on it overflowed the output. Recovery: `grep -o` with bounded context and `cut -c`. **Prevention:** already covered by `hr-never-run-commands-with-unbounded-output`; files under `docs/legal/` need `-o` with bounded context because line count does not bound byte count there.

4. **The CTO assessment prompt carried the cue that selects the CTO's ruling interface.** `plugins/soleur/agents/engineering/cto.md` routes any prompt containing "Do NOT use AskUserQuestion" to its Rule interface; I added that sentence to an assessment request. The agent noticed and answered both ways. Recovery: none needed this time. **Prevention:** an orchestrator that wants an assessment from the CTO writes `Structured advisory only`, which selects the Assess interface, and leaves out the AskUserQuestion sentence (a subagent cannot ask the operator anyway).

5. **A research subagent left a 22 KB file at `/tmp/x`** after a failed `git show` redirect. Recovery: deleted. **Prevention:** one-off; research prompts that expect `git show` output should name the session scratchpad as the only place to write.

6. **A leader's issue citation did not match the issue it named.** The CLO gave #5274 as the T-1 EU-location gate; that issue's title is about workspace durability. Recovery: recorded as unverified in the brainstorm's Open Questions instead of repeated as fact. **Prevention:** covered by the existing brainstorm rule on verifying cited numbers before threading them onward.

## Related

- Brainstorm: `knowledge-base/project/brainstorms/2026-11-09-agent-runtime-sandbox-eval-brainstorm.md`
- `knowledge-base/project/learnings/2026-07-26-prior-art-sweep-by-function-and-scoped-agent-negatives.md`
- `knowledge-base/project/learnings/2026-09-04-an-agent-will-confidently-restate-the-position-your-corpus-already-corrected.md`
- ADR-311 (the credential-broker mechanism is measured before it is built)
