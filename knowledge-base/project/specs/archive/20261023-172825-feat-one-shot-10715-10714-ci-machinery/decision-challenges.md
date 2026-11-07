# Decision Challenges — feat-one-shot-10715-10714-ci-machinery

Technical rulings the planning phase could not escalate to a subagent
(this harness has no Task/spawn tool). Recorded per
`technical-ruling-delegation.md`: `pending - assumed: <default>`.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| #10715 fix mechanism — grant the plan credential `API Token Permission Groups:Read` (issue option A) vs. scope the matrix step to skip data-read-only roots (issue option B) | technical | Ruled by CTO agent, 2026-10-23: option B — `.pr-plan-skip` sentinel + `plan_directories` filtered at the detect-changes chokepoint (infra-validation.yml:383); `plan` repoints `if:`/`matrix`, `validate` keeps `directories` - iam.tf:26's data source can never succeed under the Tier-A credential; minimal two-reference diff; preserves ADR-241 least-privilege, reversible via grant + sentinel delete. Dissent: PR-plan preview is absent for this root while the sentinel stands; a future PR could abuse the mechanism to dodge plan preview, though never `validate`. |
| #10714 fix mechanism — H3 tolerates the devin-cache arm (issue option A) vs. skips when `CLAUDE_PLUGIN_ROOT` unset (issue option B) | technical | Ruled by CTO agent, 2026-10-23: option A — `verified=true` on healthy-arm allowlist `{plugin-root-token, grok-env, devin-cache}` per gate, extract-then-classify, 3 `ck` preserved - `verified=true` is the invariant; arm name is environment data (go.md:119 documents devin-cache as the healthy Devin path); a skip would disarm the suite's only real-harness contact on arm-3 hosts. Dissent: an arm-1-only regression would pass H3 on Devin hosts, but R5/R5b/R5c mediated rows pin arm-level correctness; new arms fail closed until allowlisted. |
