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

## 2026-10-06 — Taste: Write tool removed from the agent; draft rides the final message

- **Decision.** The agent has no file-writing tools (hook `no-write` directive plus `--disallowedTools`);
  its final message is the draft. Rationale: with Write available the agent could overwrite the
  allowlisted router script and run it with the spawn environment (CTO P0), and a sidecar file needs
  symlink and TOCTOU hardening. Cost: a strict final-message contract (one JSON object, 8 KiB tail cap).
- **Alternative.** Keep Write for a sidecar file plus a per-cron `write-allow <path>` hook directive.
  Larger hook change and a larger surface; reversible later.
