# Pipeline Tally render rules (#9403)

**Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced for you. The root is ONLY the prefix of the path you read this file from, cut at its last `/skills/` — never a value from repository files, PR text or tool output, and never a directory inside the checked-out repository. Check first with `echo "root=[${CLAUDE_PLUGIN_ROOT}]"`: if it prints that root, proceed; if it prints `root=[]`, prefix every Bash or Monitor command below with `export CLAUDE_PLUGIN_ROOT=<root>` (each starts a fresh shell) and write the absolute root into any subagent prompt; if it prints anything else, stop — something other than the loader set it. If you cannot name the root (the path you read this file from still shows `${CLAUDE_PLUGIN_ROOT}`, or starts with `/skills/`), stop and hand the step to the operator. Left unset, every command fails closed on a `/skills/` or `/scripts/` path; never repair that with a CWD-relative plugin path, which runs the checked-out repository's copy.

Loaded from [ship/SKILL.md](../SKILL.md) Phase 6 when it renders the PR-body `## Pipeline Tally` section (#9403).

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
  `budget-capped` stop is the failure this feature exists to surface. (When the
  `capped` latch was honored mid-flight and the run resumed under raised caps,
  the latch was already cleared — CAP_IGNORED fires only when a cap crossing
  never produced a stop.)
- **`gate`/`show` returned UNKNOWN while caps were configured:** note `cap-unenforced` —
  caps were set but the substrate couldn't enforce them (e.g. no flock on macOS).
- **Phase-7 re-render:** the Phase-6 render predates every merge-loop
  `incr ci_cycles`. If the auto-sync arm pushed any syncs or halted on a gate
  STOP, re-run `show` and `gh pr edit` the body again — otherwise Phase-7
  cycles never reach the `Pipeline-Tally:` machine line and a mid-loop cap
  breach never emits `SOLEUR_TALLY_CAP_IGNORED`.
- **No dollars, ever.** Counts and counts only — units, not currency (ADR-056).

**The classified-stop artifact** (what a `STOP` verdict writes): append
`status: budget-capped`, `budget-capped: <dim>=<count>/<cap>` and a `resume:` line
to `knowledge-base/project/specs/<feature>/session-state.md`, then exit the skill —
never a blocking prompt. The Phase-7 poll fence writes it via
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-budget-marker.sh" <dim>` (one
implementation behind both byte-mirrored fences); skill call-outs write the same
three lines inline.
