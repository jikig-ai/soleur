# Decision challenges — feat-one-shot-7122-community-monitor-output-allowlist

## 2026-10-06 — Taste: what the closed publication schema keeps of the old digest

- **Decision (default, in the plan).** The published digest and issue are rendered from a draft whose only
  leaves are bounded integers and closed enum members. Top Contributors, Community Interactions,
  stargazer usernames, quoted excerpts, free-text Trending prose and click-through issue numbers are no
  longer published. Two integers (`externalContributors`, `externalInteractions`) keep outside activity
  visible without a name.
- **Why this is the default.** A free-text or username field is exactly the structure an injected
  instruction would use; closing the schema is what makes "model output cannot determine arbitrary
  published text" true.
- **Options.**
  - (a) Drop per-person detail, narrative and pointers; keep counts (this plan).
  - (b) Keep counts plus `topics[].refs` issue numbers so the founder can click through. Rejected by three
    reviewers (DHH, CTO, code-simplicity): the only leaf that points outside the digest (it creates
    cross-reference events on arbitrary issues) for little operator value. The CPO preferred it as an
    optional enhancement. Reversible by a schema edit.
  - (c) A private rich channel for the founder (operator-only digest). A follow-up, not part of this
    security fix. The interactive `/soleur:community digest` skill already shows full detail on demand.
- **Legal framing (CLO).** This is a product trade-off, not a legal conclusion. The PR must not claim R1,
  R2 or R4 are satisfied: future output is structurally incapable of the R1/R2/R3 content and R4's objective
  is met by a different mechanism; whether that substitutes for R1-R4 is for counsel at #7119.
- **Operator action.** None required to merge. Say so in the PR if a richer digest is wanted back.

## 2026-10-06 — Taste: the agent loses ALL file tools; the draft rides the final message

- **Decision.** The agent has no file tools (hook `no-file-tools` directive plus `--disallowedTools`:
  Read, Glob, Grep, Write, Edit, MultiEdit, Task, Agent, Skill) and no `gh` verbs; its final message is the
  draft, carried by a new `SpawnResult.finalMessage`. Rationale: with Write the agent could overwrite the
  allowlisted router script and run it with the spawn environment; with the read tools its deny-list was
  bypassable (`Grep{path:"/",glob:"proc/*/environ"}`) and `gh issue list --jq env` dumps the environment
  into its context. Cost: a strict one-line-JSON final-message contract; the prompt can no longer read the
  brand guide (it writes no prose anyway).
- **Alternative.** Keep Read/Glob/Grep behind a `read-root` allow-list directive (resolve every path-bearing
  field under the ephemeral root, deny `..`/`.git`/`.claude`, `HOME` = ephemeral root) — only if Spike S3
  finds a prompt step that genuinely needs a file read. Larger hook change; reversible later.
