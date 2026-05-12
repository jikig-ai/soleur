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
- **PR** — written as the literal string `(PR pending)` and never mutated
  afterwards (rows are append-only per the CLO non-repudiation requirement).
  To resolve a row to the live PR, search by Cluster-Hash:
  `gh pr list --search "self-healing/auto-<cluster-hash>" --state all --json url,state,number`
  returns the PR opened from that cluster. The Cluster-Hash column is
  load-bearing for this lookup.

Issue: #2720.

<!-- ROWS BELOW THIS LINE — append-only -->
