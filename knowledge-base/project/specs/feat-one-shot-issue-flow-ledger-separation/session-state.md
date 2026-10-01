# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-10-feat-issue-flow-ledger-separation-plan.md
- Status: complete
- Plan artifact: recovered (selector=branch)

Recovered from partial-artifact: the planning subagent was terminated mid-run by an
API session rate limit (HTTP 429, resets 14:30 Europe/Paris), not by a defect in the
task. The plan body was already on disk and carries `## Acceptance Criteria`, so per
one-shot's plan-artifact-recovery predicate the planning phase had finished and only
the Session Summary emission was lost. Scope verified clean: `git status --porcelain`
listed the plan file and nothing else, so the plan-only mandate held.

### Errors
- Planning subagent terminated early: rate_limit / HTTP 429, session limit.
  Not re-run — the on-disk artifact satisfies the recovery predicate.
- Step 0a Linear preflight matched `ADR-006` / `ADR-155` against the Linear-ID regex
  `[A-Z]{2,}-[0-9]+`. Both resolve to committed files under
  `knowledge-base/engineering/architecture/decisions/`, so `linear-fetch` was skipped
  on that evidence. Gate false-positive; capture at /compound, do not file.

### Decisions
- Machinery findings get a LABEL, not a separate repo and not a knowledge-base log
  (technical fork resolved per hr-technical-fork-is-not-an-operator-question).
- Lever 2 (filing-time gate) is the PRIMARY deliverable and must be blocking, not
  advisory. Operator pushback: expiry drains the stock, only the filing-time gate
  touches the rate.
- Success criterion is a fall in the FILING RATE, with expiry-driven closes excluded
  from that measurement so they cannot mask a flat or rising rate.
- The single-chokepoint claim was FALSIFIED during planning. The filing surface has
  five classes; the PreToolUse Bash hook covers class 1 only. The Inngest cron
  substrate (class 3) loads only `cron-bash-allowlist-hook.mjs`, so `guardrails.sh`
  never runs for ten scheduled agents that file discretionary findings. The assembly
  is two chokepoints; classes 2 and 5 are stated and justified as out of assembly.
- DRIFT_SUSTAINED_THRESHOLD_MIN correction ruled OUT of scope and recorded in
  Non-Goals: `resolve-target` is absent from this branch's base, so raising the
  threshold here would blind the drift alerter on main until the CI-concurrency PR
  merges.

### Components Invoked
- soleur:plan (via general-purpose planning subagent)
- soleur:deepen-plan (plan carries deepened sections: Research Insights, Guard
  Contract, Observability, Domain Review, Test Scenarios, Alternative Approaches)


## Compound Phase

- Learning: `knowledge-base/project/learnings/2026-09-10-every-escape-my-mutations-could-not-reach.md`
- Rule budget at compound: `[WARN] B_ALWAYS=45836` against the 46000 ratchet —
  164 bytes headroom, 105 rules, longest rule at the 600-byte cap. The placement
  gate therefore applied: every insight from this session is domain-scoped and
  routed to a skill, and NO rule was added to AGENTS.rules.md.
- Routed: one bullet to `plugins/soleur/skills/review/SKILL.md` — escape rows
  answer what mutation rows structurally cannot.

### Archival DEFERRED to post-merge, deliberately

`archive-kb.sh` would move both the plan and the whole spec directory. Two of
those artifacts must not move yet:

- `measurement-baseline.md` is cited BY PATH from the accepted ADR-216, and it is
  the artifact AC25/AC26 are checked against on 2026-10-08. Archiving it breaks
  an accepted ADR's citation and moves the thing the success criterion reads.
- the plan is still the reviewer's reference while the PR is open.

Recorded here rather than skipped silently, because compound's own guidance warns
that a hand-driven phase run is exactly where Step E gets dropped without a
prompt to surface it. Archive after merge, specs included.
