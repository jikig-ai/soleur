---
title: "Compound Promotion Loop — audit log"
type: audit-log
issue: "#2720"
---

# Compound Promotion Loop — audit log

Append-only log of every promotion proposal opened by
`.github/workflows/scheduled-compound-promote.yml`. Each cron run that opens
one or more draft PRs appends one row per PR below the `ROWS BELOW` marker.

**Schema:**

| Date | Cluster-Hash | Target | Source count | Decision | Tier | PR |
|------|--------------|--------|--------------|----------|------|-----|

- **Date** — UTC date (YYYY-MM-DD) of the cron run that opened the proposal.
- **Cluster-Hash** — `sha256(sorted(source_learning_paths))`, re-derived by
  the workflow before PR creation (AC11) so the LLM cannot smuggle in
  arbitrary edits under a forged hash.
- **Target** — proposed edit target (`AGENTS.core.md` or a skill SKILL.md).
- **Source count** — number of source learnings in the cluster (>=5 to qualify).
- **Decision** — `pending` (initial only). Live decision is **not stored** —
  derive at read-time via `gh pr view <pr-number> --json state,merged`:
  `merged === true` → applied; `state === CLOSED && merged === false` →
  rejected. This keeps the log non-mutating (CLO non-repudiation requirement).
- **Tier** — `skill` or `agents-core`.
- **PR** — `gh pr view` URL once the workflow's PR-create step lands. The
  workflow writes the row as `(PR pending)` and a follow-up amend writes the
  URL on the same step.

Issue: #2720.

<!-- ROWS BELOW THIS LINE — append-only -->
