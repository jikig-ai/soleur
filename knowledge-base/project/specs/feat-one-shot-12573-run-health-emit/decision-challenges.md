# Decision challenges

Headless planning subagent. No CTO spawn is available in this process. Technical rows stay placeholders until the parent context rewrites them before work.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Seal only when the caller passes --seal with a terminal status | technical | Ruled by CTO agent, 2026-11-20: explicit --seal plus a terminal status only; later upserts do not clear sealed, completed_at, or the terminal status - the helper's phase-name heuristic has no dependent caller, and started does not seal. Dissent: None. |
| Goto count and gate line come from existing stores | technical | Ruled by CTO agent, 2026-11-20: count full lines `verb: goto` in the session-state file the caller passes; tally_show is the full stdout of pipeline-tally.sh show; a missing file yields goto_count 0 and exit 0; do not add a second tally file and do not edit pipeline-tally.sh - nothing emits the compact marker retry-budget-ruling: verb=goto phase=, so counting it is always zero. Dissent: a parent that later writes only the compact marker would not be counted. |
| Schema version and where it lives | technical | Ruled by CTO agent, 2026-11-20: schema_version integer 1 in plugins/soleur/skills/one-shot/references/run-health-schema.md; the unit test is the consumer; do not edit the forensics analyst - the analyst does not parse JSON. Dissent: None. |
| Brand-survival threshold | technical | Ruled by CTO agent, 2026-11-20: keep single-user incident and requires_cpo_signoff true - one committed prompt snapshot can expose one person's session text, and the gitignore does not lower that label. Dissent: None. |
| Helper exit on a bad argument or a failed write | technical | Ruled by CTO agent, 2026-11-20: stay fail-open and exit 0, logging run-health-emit: on stderr - the ledger must not stop the pipeline, and the ignore test is the secret-in-git control. Dissent: None. |
| Phase token charset before any write | technical | Ruled by CTO agent, 2026-11-20: refuse a token outside ^[A-Za-z0-9._-]+$, and also refuse `.`, `..`, and any token containing `..`, in the shell before mkdir; exit 0 and print run-health-emit: - a Python-only refusal still creates the directory, and the existing phase ids match the charset. Dissent: None. |
| What a phase snapshot contains, and how one-shot stays under its byte ceiling | technical | Ruled by CTO agent, 2026-11-20: snapshot the step invocation, not the skill file; put the call list in the schema file; keep a short bash block in the skill; delete the two dated history sentences so wc -c is at most 51950 - the file has 5 bytes of spare under the 52000 ceiling. Dissent: None. |
| Who runs the helper during planning | technical | Ruled by CTO agent, 2026-11-20: the parent one-shot context emits around steps 1-2; the planning subagent does not call the helper - the parent can snapshot the invocation it wrote, and this issue does not require the planner's private prompts. Dissent: the parent cannot see the subagent's internal tool prompts after the return. |
| Seal-only call shape | technical | Ruled by CTO agent, 2026-11-20: --seal needs --run-dir and a terminal status, does not need --phase, and does not append a phase row; --discover is its own arm ahead of the unknown-arg shift - no test requires a phase row on every seal. Dissent: None. |
| JSON replace durability | technical | Ruled by CTO agent, 2026-11-20: keep os.replace of a same-directory temp file and do not fsync - sibling writers do not fsync, and this issue does not require crash durability. Dissent: None. |
