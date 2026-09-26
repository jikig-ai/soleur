---
name: cohort-status
description: "This skill should be used when the operator asks for the alpha-tester cohort status — recruitment tally, checkpoint state, quiet flags. Pull-based; no dashboard."
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# cohort-status

Prints the alpha-tester cohort table on demand — the pull-based answer to "where is the
cohort". **Operator-invoked only; never cron.** The armed `cohort-quiet` Inngest check is
the push path; this skill is for when the operator asks.

## Sources (all local + `gh`; never the hosted DB — there is no CLI auth path)

1. **Tally** — the recruitment-mix table in
   `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md`
   (columns: Tester | Company | Claude Code user? | Surface | Onboarded | Terms |
   cohort_key | nudged_at). This is the only ledger for mix/quota state.
2. **Checkpoint state** — `gh issue list --state all -L 50 --search "checkpoint: 2-week
   usage review" --json number,title,state,createdAt`. Per-tester checkpoint issues are
   titled `checkpoint: 2-week usage review — <Company> (alpha tester #N), due <date>`.
3. **Armed reminders** — derived by convention, not read from a store:
   `checkpoint-tester-N-<YYYY-MM-DD>` and `cohort-quiet-tester-N-<YYYY-MM-DD>` exist iff
   Step 6 of the runbook ran (`arm-checkpoint.sh N <issue>`). A tester row whose tally has
   no checkpoint issue means arming never happened — report `checkpoint_armed: NO`, do not
   infer dates.

## Procedure

1. Read the runbook tally table. If the file or the table is unreadable, print
   `UNREADABLE: <path>` and stop — **never** print zeros for a failed read.
2. Run the `gh issue list` query. If it fails, print `UNREADABLE: gh` and show the tally
   alone.
3. Per tester row, compute:
   - `checkpoint` — open / closed / `unfiled` (no matching issue found for #N)
   - `armed` — `yes` iff a matching checkpoint issue exists (Step 6 files it and arms in
     the same step)
   - `quiet` — only from a POSITIVE read: a tester is `quiet` iff the latest `cohort-quiet`
     comment on their tracking issue names their company domain (the check emits
     company-level identifiers — email domains, never mailboxes). Never mark quiet from
     absence — absent data is `unknown`, not `quiet`.
   - `nudged_at` — echoed verbatim from the tally row; the checkpoint interview discloses
     assisted-vs-unassisted returns.
4. **Sanitize every issue title before printing** — `tr -d '\n'` and `tr '|' '/'` (issue
   titles are editable text; a newline or pipe inside one breaks the table layout).
5. Print the table:

```
| Tester | Company | CC? | Surface | Onboarded | cohort_key | checkpoint | armed | quiet | nudged_at |
```

6. Print the mix floor: `Non-CC recorded X / floor 3; CC recorded Y / ceiling 7` — a
   tester #8 warning when the floor is unreachable.

## Hard rules

- `UNREADABLE`, never fabricated zeros — a failed read is a hole, not a count.
- Company-level identifiers only; never print tester names/emails from elsewhere.
- No automatic nudging, no posting — this skill is read-only.
