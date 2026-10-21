# Decision Challenges — feat-one-shot-10401-differential-migration-testing

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Doc home + pointer surface (plan/references + plan-issue-templates.md vs work/references + work/SKILL.md) | technical | Ruled by CTO agent, 2026-10-20: doc at `plugins/soleur/skills/plan/references/differential-migration-testing.md` with the sole pointer as one identical conditional line inside each of the three `## Test Scenarios` blocks in `plan-issue-templates.md`; no capped SKILL.md edits - the issue's named surface is plan references, the templates file is read unconditionally at plan Step 4 and satisfies the components.test.ts reachability census with zero capped bytes, and every capped SKILL.md lacks headroom (`work` 118 B already ~claimed by in-flight #10400, `plan` 34 B, `review` 0 B). |
| Slim skill vs reference doc | technical | Ruled by CTO agent, 2026-10-20: reference doc - the issue sizes "~1 new file + pointer edits", a skill adds registration + description budget for zero added property; reference is the first minimalism-ladder rung that holds. |
| Link form inside the fenced template blocks | technical | Ruled by CTO agent, 2026-10-20: `${CLAUDE_PLUGIN_ROOT}`-form markdown link - template text is copied verbatim into generated plans where a `./` relative link resolves nowhere; the root-prefixed path resolves to the user's plugin install. |
| Optional follow-up: work-surface pointer once #10400's headroom claim resolves | taste | deferred — noted in plan Non-Goals; no tracking issue filed at plan time (ship phase may file `action-required` if review re-surfaces it). |
