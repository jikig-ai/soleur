# Learning: A plan's re-verify/assertion must target the load-bearing invariant, not a proxy for it

## Problem

The feat-flag-org-scoping plan (#4581, brand_survival_threshold=single-user incident)
specified an FR8 "re-verify read (count==1)" to prove a flag was scoped to exactly one
org before reporting success. The plan and the existing `flip.sh` re-verify read the
**Flagsmith segment's `EQUAL orgId` conditions** — i.e. segment *membership*.

The spec-flow-analyzer review caught (P0-3) that segment membership is a **proxy**, not
the invariant. A Flagsmith feature only evaluates ON for an org if BOTH (a) the org is in
`<flag>-orgs` membership AND (b) a feature-state ON override exists on `<flag>-orgs` in
the right env(s). The historical `flip.sh --org` path never created the override
(`flip_segment_in_env` ran only in the role branch). So a `--org on` could set membership
correctly, pass a membership `count==1` check, and **report success while the flag was
still OFF** — the exact silent single-user-incident failure the feature exists to prevent.

The three other reviewers (DHH, Kieran, code-simplicity) did NOT catch this: DHH/Kieran
verify schema/contract correctness (jq types, grant model, arg shapes) and code-simplicity
verifies YAGNI — none walk the runtime evaluation semantics end-to-end. Only the
flow-analysis lens (spec-flow) traced "membership set → does the feature actually evaluate
ON?" and found the missing link.

## Solution

Rewrote FR8/Phase-4 re-verify to assert **flag evaluation**, not membership: POST a
transient Flagsmith identity carrying the `orgId` trait (per ADR-043's identity model) and
assert `<flag>` resolves `enabled=true` for the target org AND `enabled=false` for a
control org. The override-provisioning was also pulled to run *before* membership edits.

## Key Insight

When a plan proposes a verification step (re-verify read, AC assertion, post-write check)
to prove a behavioral invariant holds, confirm the check reads the **invariant itself**,
not a proxy that usually-but-not-always co-varies with it. Proxies that pass while the
invariant is false: segment membership vs flag evaluation; row `count` vs row identity;
config-secret presence vs config-secret *value*; "function exists" vs "function is
granted/reachable"; HTTP 2xx vs response *body* shape. At single-user-incident threshold
this is load-bearing — a green check on a broken state is worse than a red one. **Schema/
style/YAGNI reviewers structurally cannot catch proxy-vs-invariant gaps; the flow-analysis
lens (spec-flow-analyzer) is the one that walks "does the asserted thing actually imply the
intended outcome?"** — always include it for verification-heavy plans. Pairs with the plan
Sharp Edge on prose-contract-vs-executable-check dimension drift.

## Session Errors

1. **Plan cited `SETUP.md:64-75` as the `orgId` segment template** — it is the `role`
   template (`property=role`; `grep -n orgId SETUP.md`=0). The real orgId envelope is
   `flip.sh:328-330`. Recovery: Kieran review caught it; repointed the citation.
   Prevention: when a plan cites a file:line as a template/precedent for a specific
   property/symbol, `grep` that the named property exists at the cited location before
   writing the citation (extends the existing plan "paraphrase-without-verification" rules
   from issue-body claims to the plan author's own precedent citations).
2. **repo-research subagent false-negative** ("migration 071 / server.ts absent — 95-file
   slice") contradicted by direct read + `git ls-tree`. Recovery: trusted first-hand reads
   per the bare-repo subagent-false-negative rule (and the brainstorm learning written the
   same session). Prevention: already covered by
   `[[2026-05-29-brainstorm-read-adr-alternatives-considered-before-proposing-reversal]]`
   + `2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md`.
3. **IaC PreToolUse hook blocked the first plan Write** (`doppler secrets set` detected).
   Recovery: added `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` after genuinely
   reviewing Phase 2.8 (cli_ops is CLI-managed, not TF). Prevention: expected gate
   behavior; the ack is the sanctioned opt-out when the manual step is genuinely required.

## Tags
category: workflow-patterns
module: plan
issue: 4581
related: 2026-05-29-brainstorm-read-adr-alternatives-considered-before-proposing-reversal, 2026-05-16-prose-contract-vs-executable-check-dimension-drift
