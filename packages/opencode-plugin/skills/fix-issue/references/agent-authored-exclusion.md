# Agent-Authored Issue Exclusion

Canonical opt-in convention for excluding agent-authored GitHub issues from
auto-fix, auto-triage, and any future issue-consuming workflow.

## Why this exists

Agent-native skills that file GitHub issues (today: `soleur:ux-audit`; future:
any scheduled monitor, security scanner, or community digest that produces
issues) create a **governance loop** when those issues are then picked up by
auto-triage (which re-classifies them) or auto-fix (which attempts to patch
them). The agent files, the agent triages, the agent prioritizes its own work —
founder judgment is bypassed.

The load-bearing mitigation is **label-based exclusion**: every agent-authored
issue carries labels that mark it as agent-authored, and every automation
workflow that consumes open issues drops anything carrying those labels before
processing.

See
[2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md](../../../../knowledge-base/project/learnings/2026-04-15-brainstorm-calibration-pattern-and-governance-loop-prevention.md)
for the original pattern and the calibration session that surfaced it.

## Label convention

Every agent-native skill that files GitHub issues MUST apply BOTH labels:

1. A **stream tag** identifying the source agent/skill — e.g. `ux-audit`,
   `seo-audit`, `community-digest`. Matches the existing `ux-audit` label.
2. An **`agent:<role>` label** identifying the authoring agent — e.g.
   `agent:ux-design-lead`, `agent:ticket-triage`. The `agent:` prefix is the
   canonical opt-in for automation exclusion.

The canonical example is `scheduled-ux-audit.yml` (label inputs around the
`gh issue create` invocation), which applies `ux-audit` + `agent:ux-design-lead`
on first-filed issues.

## Workflows that honor exclusion

The following workflows filter both label classes out of their input using the
canonical jq clause (see
[exclude-label-jq-snippet.md](./exclude-label-jq-snippet.md)):

- `.github/workflows/scheduled-bug-fixer.yml` — per-priority selection loop
- `.github/workflows/scheduled-daily-triage.yml` — triage prompt's initial
  `gh issue list`

Additionally, `scheduled-bug-fixer.yml` passes
`--exclude-label ux-audit --exclude-label 'agent:*'` to the skill invocation as
defense-in-depth. The `fix-issue` skill's `Phase 0: Parse arguments` and
`Phase 1: Read and Validate` short-circuit if the issue carries any excluded
label — this is the only guard for manual invocations and for
`workflow_dispatch` with an explicit `issue_number` input.

Any new workflow that consumes open issues for automation MUST:

1. Include the canonical jq clause verbatim (or the inline form) before any
   `sort_by` / `.[0]` / `last` reduction.
2. Pass `--exclude-label ux-audit --exclude-label 'agent:*'` when invoking
   `soleur:fix-issue` (or any other skill that operates on a single issue).

## Adding a new agent-authored stream

1. **Apply both labels at creation time.** The authoring skill must pass
   `--label <stream-tag>` AND `--label agent:<role>` to `gh issue create`.
2. **Extend the canonical clause if the stream tag is new.** Only if the new
   stream uses a tag that does NOT start with `agent:` (and is not `ux-audit`),
   add an explicit branch to the clause in `exclude-label-jq-snippet.md` AND
   mirror it into both consumer workflows. If the stream relies on the
   `agent:*` prefix, no clause edit is needed.
3. **Default milestone: `Post-MVP / Later`** unless the authoring skill has an
   explicit phase target. Agent-authored issues that arrive milestoned to the
   current phase bypass founder prioritization.
4. **Cap per-run and global output.** The authoring skill must enforce a
   per-run cap (e.g. "file at most 5 findings") and a global cap (e.g. "if >20
   open agent-authored issues exist, stop filing and notify"). Prevents an agent
   loop from flooding the tracker.
5. **Announce the new stream in the PR description.** Reviewers must verify
   both labels are applied and both consumer workflows still filter correctly.

## How to test

Three manual checks before merging any new stream:

1. **Authoring skill dry-run.** Run the authoring skill end-to-end in dry-run
   mode; confirm the issues it would file carry both the stream tag and the
   `agent:<role>` label.
2. **Daily triage `workflow_dispatch`.** Trigger `scheduled-daily-triage.yml`
   manually; confirm the new stream's issues are dropped from the
   initial `gh issue list` (they should not be re-triaged).
3. **Bug fixer `workflow_dispatch` with explicit `issue_number`.** Pass an
   agent-authored issue number as `inputs.issue_number`; confirm the
   `fix-issue` skill's Phase 1 short-circuit logs the benign exit message and
   no PR is opened. Confirms the defense-in-depth skill-level guard fires even
   when the scheduler's upstream filter is bypassed.

## `gh --jq` pitfall

`gh issue list --jq '<expr>'` accepts one jq expression STRING. It does NOT
forward jq flags (`--arg`, `--argjson`). Any parameterization MUST use
`export VAR=...; jq '... $ENV.VAR ...'` via a pipe — NOT
`gh issue list --jq ... --arg VAR ...`. The canonical clause uses only
hard-coded literals so this pitfall does not affect current workflows, but any
future per-repo configurability must route through `$ENV.*`. See
[2026-03-03-scheduled-bot-fix-workflow-patterns.md](../../../../knowledge-base/project/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md).

## Retroactive stream-tag dependency (as of 2026-04-18)

Four of five current `ux-audit` issues (#2378, #2379, #2352, #2351) lack
`agent:ux-design-lead` because they were filed by follow-up sessions, not by the
`ux-audit` skill itself. The `ux-audit` branch of the canonical jq clause is
therefore load-bearing for existing tracker state.

A well-meaning cleanup that "DRYs up" the clause by keeping only the `agent:*`
branch would silently regress. Before removing the `ux-audit` branch, apply a
one-shot retroactive label sweep to backfill `agent:ux-design-lead` on the four
issues above, then verify with
`gh issue list --label ux-audit --state all --json number,labels`.
