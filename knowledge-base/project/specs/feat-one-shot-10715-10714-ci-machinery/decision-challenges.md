# Decision Challenges — feat-one-shot-10715-10714-ci-machinery

Technical rulings the planning phase could not escalate to a subagent
(this harness has no Task/spawn tool). Recorded per
`technical-ruling-delegation.md`: `pending - assumed: <default>`.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| #10715 fix mechanism — grant the plan credential `API Token Permission Groups:Read` (issue option A) vs. scope the matrix step to skip data-read-only roots (issue option B) | technical | pending - assumed: option B — `.pr-plan-skip` sentinel + `plan_directories` filter in detect-changes. Option A is a production-credential mutation outside the pipeline's authorization class; B is self-serve, keeps ADR-241's least-privilege direction, and is reversible (grant + delete the sentinel restores plan coverage). |
| #10714 fix mechanism — H3 tolerates the devin-cache arm (issue option A) vs. skips when `CLAUDE_PLUGIN_ROOT` unset (issue option B) | technical | pending - assumed: option A — assert `verified=true` on the healthy-arm allowlist `{plugin-root-token, grok-env, devin-cache}`. A skip disarms real-harness contact on exactly the hosts arm 3 (#8401) was built for; tolerance keeps the tested property (`verified=true`) blocking. |
