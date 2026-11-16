---
module: web-platform infra (web hosts, LB weight gate)
date: 2026-11-12
problem_type: best_practice
component: tooling
symptoms:
  - "After web host roles became keyed fields of var.web_hosts, lb-weight-gate.sh accepted the unkeyed workspaces LUKS marker for any gated key"
  - "A new key declared at lb_weight = 1 could have pooled outside the drain gate on web-2's evidence"
  - "The web-1 literal ratchet and the workflow byte gate both turned red after an origin/main merge, with no change from this branch"
root_cause: missing_validation
resolution_type: code_fix
severity: high
tags: [web-hosts, lb-weight-gate, keyed-evidence, luks-marker, ratchet, workflow-file-size, adr-327]
issue: 12008
---

# Learning: a gate generalized to N keyed hosts must refuse evidence that is not keyed to the host it gates

## Problem

PR #12613 (PR 1 of 7 for #9421) turned the web host roles into keyed fields of `var.web_hosts`. It also made
`lb-weight-gate.sh` take the gated host as an input (`SOLEUR_GATED_HOST`). The gate still read one piece of evidence
that was **not keyed**: the workspaces LUKS cutover marker (`WORKSPACES_LUKS_CUTOVER_AT`). That marker has exactly one
writer, and the writer probes web-2. Once the gate accepted any key, a new host (web-3) would have passed the LUKS
check on web-2's evidence. Review caught this as a P2; no production run was affected.

## Solution

The marker is now bound to the host it attests (commit c4c3ccbc6a):

```bash
# lb-weight-gate.sh: the marker is unkeyed, so it attests its writer's host and no other
[[ "${WORKSPACES_LUKS_MARKER_HOST-}" == "$HOST" ]] || fail "B_workspaces_luks_marker_other_host"
```

The seam names the host (`WORKSPACES_LUKS_MARKER_HOST`), throws away any value the caller passes, and is
parity-pinned to the marker's writer. The test now covers web-3 in five cases: standby, refused on web-2's marker,
authorized on a marker that attests web-3, missing from the roster, and address not allowlisted. A separate plan-time
precondition on the GA pool allows at most one host serving outside the drain gate, so a new key at weight 1 is refused
before apply.

## Key Insight

When a single-host gate becomes a gate over N keys, the inputs widen, but the evidence it reads may not. List every
piece of evidence the gate consumes (markers, env values, probe results) and ask of each one: *which host wrote
this?* If the answer is "one fixed host", the gate must check that the requested key **is** that host, and refuse
otherwise. Never let a new key inherit it. A keyed input that reads unkeyed evidence fails open for every key added
later.

A second, smaller insight: **repo-wide counts measured on a branch drift with `main`.** The web-1 literal ratchet
(`web-hosts-generic.test.sh`, `count_lit`) counts literals across the whole tree, so `main` landing new literals turns
it red with no change from the branch. The fix is to re-baseline right after each `main` merge and say in the comment
where the increase came from (b7b5be83a2: +43 IP and +5 key literals, all from main). Never commit a baseline taken
mid-merge. The same goes for `apply-web-platform-infra.yml` against the 490,000-byte gate in
`plugins/soleur/test/workflow-file-size.test.ts`. At f458eecd1f the file is 489,868 B, which is 132 B under the gate,
so any `main` growth to that file before merge turns it red again. The structural fix is tracked in #8385.

## Session Errors

1. **The no-human-steps lint fired on the plan's quoted owner asks.**
   - **Recovery:** the ask-mapping table was fenced away from the lint (5d77a1674a).
   - **Prevention:** already lint-enforced. When a plan quotes owner-facing asks, put them in the fenced form the lint
     skips from the start.
2. **The web-1 literal ratchet went red after the origin/main merge** (main added 43 IP and 5 key literals).
   - **Recovery:** re-baselined at the merge commit, with the reason in the comment (b7b5be83a2).
   - **Prevention:** re-baseline only after a completed `main` merge, never mid-merge. Ship re-runs
     `web-hosts-generic.test.sh` after each sync.
3. **`apply-web-platform-infra.yml` went over the 490,000-byte gate after the merge.**
   - **Recovery:** budget comments were trimmed (2d0a9aa6b1). Headroom is now 132 B.
   - **Prevention:** run `workflow-file-size.test.ts` after every `main` merge on a branch that edits this file.
     The structural fix (splitting the dispatch jobs) is #8385.
4. **The unkeyed workspaces LUKS marker could have authorized an ungated key** (review P2).
   - **Recovery:** the marker is bound to its host, and the plan-time precondition refuses ungated pooling
     (c4c3ccbc6a).
   - **Prevention:** when a plan generalizes a host-specific gate to keyed hosts, list each piece of evidence the gate
     reads and add one test case per piece of the shape "key B refused on key A's evidence".
5. **The coverage-notice and registry-gate-mutation suites time out locally under machine load** (load average ~44 on
   16 cores).
   - **Recovery:** both are confirmed on CI at ship, after the PR is marked ready.
   - **Prevention:** a local timeout under heavy load is not a verdict. Read the CI result for those suites before
     calling them red or green.

## Related

- `knowledge-base/project/learnings/2026-09-21-widening-who-reaches-an-evidence-check-inherits-what-the-evidence-is-keyed-on.md`.
  This is the same class. The plan skill's sharp edge ("When a plan widens WHICH items reach an existing evidence
  check…", `plugins/soleur/skills/plan/references/plan-sharp-edges.md`) already requires it. Here it was missed at
  plan time and caught at review, so no new rule was added.
- `knowledge-base/project/learnings/2026-11-10-a-failover-premise-must-be-checked-against-the-serving-topology.md`
  (same feature, brainstorm phase)
- ADR-327 (dedicated bastion; web hosts are identical cattle), ADR-326 (kernel at birth)
- Deferred P3 test hardening: #12659

## Tags

category: best-practices
module: web-platform infra
