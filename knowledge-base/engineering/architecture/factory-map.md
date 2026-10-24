---
last_updated: 2026-10-24
last_reviewed: 2026-10-24
---

# Factory Map

One page naming Soleur's concrete filling for each agentic-factory service slot, and the
translation layer between the peer vocabulary (Task / Trigger / Run / Runner, from the
`mattpocock/skills` `software-factory` skill — MIT, vocabulary and methodology adopted, no
prose ported) and Soleur's own terms. Read this before naming a machinery concept in a plan,
spec, ADR or runbook; the glossary entries for `Run`, `Trigger`, `Runner` and `Task` point
here.

## Service slots

| Slot | Soleur filling |
|---|---|
| Ticket tracker | GitHub Issues + label routing — `drain-labeled-backlog`, `action-required`, `scheduled-<NAME>` labels, standing-delegation marker comments |
| Ticket source | Sentry monitors, `tmpfs-guard`, drift-detection and `scheduled-*` filings, follow-through sweeper trackers, operator-filed issues |
| Git host | GitHub (PRs, rulesets, merge queue, `gh` CLI + GitHub App auth — never PAT) |
| Orchestrator | GHA `schedule:`/`workflow_dispatch` workflows + Inngest (cron functions, self-armed oneshots per ADR-046, the reminder primitive's `CHECK_REGISTRY`) |
| Runner | The disposable execution surface: GHA hosted runners, Devin cloud sessions, local git worktrees, the agent bwrap sandbox |
| Observability platform | The seven enforced layers — see `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` §The seven observability layers |

## Vocabulary map

| Peer term | Soleur term | Divergence |
|---|---|---|
| Task | A defined-once, run-many-times unit: a skill (`soleur:<skill>`), a `scheduled-*.yml` workflow, or an Inngest `cron-*`/`oneshot-*` function | Soleur splits the peer's single "task" across two substrates — GHA cron for pure-GH ops, Inngest for secret/server-side work (`schedule` Step 0 routes) |
| Trigger | Cron tick, `workflow_dispatch`, label/event, upstream run, or an armed reminder check | — |
| Run | A workflow run, an Inngest execution, or an agent session — black-box trigger-to-finish; never waits on a human (`action-required` issues and the `message_user` stall-as-defer are the re-entry contract) | Soleur "session" is the preferred word for an agent-context run |
| Runner | The disposable execution surface a run lands on: GHA runner VM, Devin cloud container, worktree, bwrap sandbox | Soleur "sandbox" names the bwrap surface specifically — it is A runner, not THE runner |

## _Avoid_ guidance

- _Avoid_ "session" when you mean the black-box execution — say **Run**. A session is one
  possible runner-context, not the unit of work.
- _Avoid_ "server", "host", "box" for the execution surface — say **Runner**. Those words
  name infrastructure; the runner is the disposable surface the orchestrator allocates.
- _Avoid_ "cron job" for any scheduled unit — say **Task** and name its substrate
  (`scheduled-*.yml` vs Inngest function); `schedule` Step 0 picks the substrate, and the
  two have different secret access.

## The six task-design questions

Every NEW autonomous task answers these at design time — in the generated workflow's
`# Task design:` header (`soleur:schedule`), in the creating plan's `## Task Design`
section (plan §2.9.3 / deepen-plan §4.13), or in the design issue/arming record (Inngest
runbook): trigger, services, next, human re-entry, dedupe (beyond `concurrency: group:`),
source dedupe.

---

*Attribution: the factory-slot ontology vocabulary and the question-every-task checklist are
adapted from `mattpocock/skills` `software-factory` (MIT) — vocabulary/methodology only, no
prose ported. See `plugins/soleur/NOTICE`.*
