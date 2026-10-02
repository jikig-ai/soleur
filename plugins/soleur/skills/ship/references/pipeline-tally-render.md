# Pipeline Tally render rules (#9403)

Phase 6 reads the run's ledger before writing the PR body:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-tally.sh" show`. Render `## Pipeline Tally`
before `## Changelog` in BOTH body templates, per these rules (in order):

- **Ledger present, counts > 0:** one `tally: seats=N ci_cycles=N fix_rounds=N agent_rounds=N`
  line; a glossary line (`seats = reviewer agents spawned`); any `warned:<dim>=<at>` /
  `capped:<dim>` events from `show`'s annotation line; cap usage as `N of cap <dim>`
  fractions for each `cap_<dim>` set. Then the machine line on its own line:
  `Pipeline-Tally: seats=N; ci_cycles=N; fix_rounds=N; agent_rounds=N` — it is the
  cross-PR aggregation surface (squash merge drops commit trailers, so counts live in
  the body, never a git trailer).
- **Ledger present, all counters 0:** `tally: 0 — no counted operations`
  (instrumented-but-unused is a real state, not an absence).
- **Ledger absent / `show` prints UNKNOWN:** the literal line `SOLEUR_TALLY_ABSENT` —
  never render a zero tally for an instrumented run that never wrote.
- **Ledger carries `capped=<dim>` but the run shipped anyway:** additionally emit
  `SOLEUR_TALLY_CAP_IGNORED` on its own line — a cap crossed without producing a
  `budget-capped` stop is the failure this feature exists to surface.
- **`gate`/`show` returned UNKNOWN while caps were configured:** note `cap-unenforced` —
  caps were set but the substrate couldn't enforce them (e.g. no flock on macOS).
- **No dollars, ever.** Counts and counts only — units, not currency (ADR-056).
