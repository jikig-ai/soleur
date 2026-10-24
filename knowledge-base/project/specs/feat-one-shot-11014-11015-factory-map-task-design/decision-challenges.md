# Decision Challenges — feat-one-shot-11014-11015-factory-map-task-design

Headless one-shot planning run for issues #11014 + #11015. This harness has no
Agent/Task tool, so `soleur:engineering:cto` rulings, domain leaders, the
`soleur:plan-review` panel and the scoped advisor consult could not be spawned.
Technical rows carry `pending - assumed: <default>` per the
technical-ruling-delegation contract; the parent pipeline's batched CTO consult
replaces them.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| #11015 landing option: `schedule` create flow (a) vs plan `## Observability` extension (b) — issue says "pick at plan time" | technical | pending - assumed: **both** — the two options guard disjoint creation paths (skill-generated GHA workflows vs plan-authored autonomous tasks), and implementing only one leaves the other path ungated; the issue's AC ("a written answer to all six questions" on task creation) only holds universally if both fire. A third surface (the Inngest runbook) covers the substrate schedule Step 0 routes server-side work to. |
| `## Observability` 6th field vs new conditional `## Task Design` section | technical | pending - assumed: **new conditional section** following the `## Encryption Posture` precedent (plan §2.11 / deepen-plan §4.10). A 6th Observability field ripples into all parity-pinned surfaces (plan §2.9, templates ×3, deepen-plan §4.7, deepen-plan.workflow.js ×2, AGENTS.rules.md `(5 fields)` count, `observability-schema-parity.test.ts`) and would force every infra-touching plan to answer six questions it doesn't need; a conditional section fires only when a new autonomous-task file is created. |
| New AGENTS.rules.md rule for the task-design gate | technical | pending - assumed: **no** — `cq-agents-md-tier-gate` precedent (a domain-scoped gate that can only be violated in one phase lives in the enforcing skill, cf. `wg-architecture-decision-is-a-plan-deliverable` migration to plan §2.10). The gate lives in plan §2.9.3 / deepen-plan §4.13 / schedule SKILL.md. |
| ADR for the task-design contract / factory vocabulary | technical | pending - assumed: **no ADR** — factory-map.md documents existing architecture (decides nothing new); the gate is a process contract in the same class as the observability/encryption plan gates, which are skill-enforced without dedicated ADRs. |
| CI/lefthook lint enforcing the `# Task design:` header on new `scheduled-*.yml` | technical | pending - assumed: **cut** — the generator embeds the block (create path can't emit without it) and the plan gate covers plan-authored files; a hand-authored file outside any plan is the same trust surface every skill-level rule already relies on. Revisit if a bypass is observed. |
| `--once` mode: derived answers vs new mandatory flags | technical | pending - assumed: **derived** — all six answers are mechanically fixed by the D1–D5 machinery (trigger = one-time cron + D3; re-entry = pinned issue-comment thread; dedupe = D3+D4+concurrency group; source-dedupe = not-a-source default). Zero new operator burden; recurring mode is where free answers are collected. |
| `plan-review` reviewer panel not spawned (no Agent tool in this harness) | technical | pending - assumed: **no panel re-run required before `soleur:work`** (precedent: feat-one-shot-9963 ruling). Self-review applied; `soleur:plan-review` may still run at the review stage. |
| Brand-survival threshold `none` | taste | assumed: none — docs + prompt-skill text + a test suite; no user-facing artifact, no data path, no credential surface. |
| Scoped advisor consult (plan §4.5) not spawned | technical | pending - assumed: skip — no Task tool in this harness; the plan's riskiest phase (Phase 3 gate text) is a documented conditional-section precedent copy, low rework risk. |
