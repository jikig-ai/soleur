# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-05-fix-concierge-idle-runaway-and-duplicate-label-plan.md
- Status: complete (with mid-pipeline amendment)

### Errors
None

### Decisions
- Bug 1 root cause: `DEFAULT_WALL_CLOCK_TRIGGER_MS = 30s` in `soleur-go-runner.ts:82` too tight for PDF Read+summarize turns. Fix raises to 90s and resets the window on every assistant block (text or tool_use). Validated against new evidence (2026-05-05): a "continue" nudge re-runs the Read tool and fails identically — deterministic, NOT racy — which is consistent with the per-turn Read latency consistently exceeding the 30s ceiling.
- Bug 2 root cause: `message-bubble.tsx:145-153` renders both `displayName` and `leader.title` side-by-side when `showFullTitle=true`. Generic substring rule `title.includes(displayName)` chosen over cc_router-specific branch (also catches latent `system` leader collision).
- Mid-pipeline amendment (post-deepen, pre-work): plan extended with two new acceptance criteria after real-user evidence — (1) follow-up Concierge bubble (`showFullTitle=false`, currently renders bare "Concierge") MUST also render "Soleur Concierge", (2) `runner_runaway` log MUST include `elapsedMs` + `lastBlockKind` + `lastBlockToolName` so future timer tightening is informed by tool-mix data.
- Tests land in `soleur-go-runner-awaiting-user.test.ts` (Bug 1) and a new `message-bubble-header.test.tsx` (Bug 2).
- Risk-acceptance: `## User-Brand Impact` threshold is `none` — no credentials/auth/data/payments touched.

### Components Invoked
- soleur:plan, soleur:deepen-plan
- Manual amendment by main agent after user surfaced new evidence (nudge fails identically; turn-2 bubble header bare "Concierge")
