# Decision challenges

Headless planning subagent. No CTO spawn is available in this process. Technical rows stay placeholders until the parent context rewrites them before work.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Seal only when the caller passes --seal with a terminal status | technical | pending - assumed: phase names do not seal; terminal statuses are completed, failed, and budget-capped; started and any other token do not set sealed; a later upsert does not clear sealed, completed_at, or the terminal status |
| Goto count and gate line come from existing stores | technical | pending - assumed: goto_count counts lines containing retry-budget-ruling: verb=goto phase=; tally_show is the full stdout of pipeline-tally.sh show; no second counter |
| Schema version and where it lives | technical | pending - assumed: schema_version integer 1 in one markdown file at plugins/soleur/skills/one-shot/references/run-health-schema.md; the unit test is the consumer in this issue; do not edit the forensics analyst |
| Brand-survival threshold | technical | pending - assumed: single-user incident, and requires_cpo_signoff stays true, because one committed prompt snapshot can expose one person's data |
| Helper exit on a bad argument or a failed write | technical | pending - assumed: stay fail-open and exit 0; do not switch the helper to set -euo pipefail or exit 1 |
| Phase token charset before any write | technical | pending - assumed: refuse a token that does not match ^[A-Za-z0-9._-]+$ and exit 0 before mkdir |
| What a phase snapshot contains, and how one-shot stays under its byte ceiling | technical | pending - assumed: snapshot the step invocation, not the skill file; put the one-shot call list in the schema file; keep a short bash line in the skill; delete the two dated history sentences in the Why this gate exists paragraph so wc -c is at most 51950 |
| Who runs the helper during planning | technical | pending - assumed: the parent one-shot context emits around steps 1-2; the planning subagent does not call the helper |
