# Decision challenges: feat-one-shot-4671-untrusted-data-classification (#4671)

Headless plan pass (2026-10-13). Technical rulings came from the CTO agent; mechanical plan-review findings were applied to the plan. Taste rows keep the plan default and record dissent for `ship`.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| R1 Detection mechanism: heuristic scorer vs heuristic+LLM vs LLM-only | technical | Ruled by CTO agent, 2026-10-13: deterministic heuristic scorer only, fail-open, no LLM in the hot path; LLM tier deferred behind eval recall - no measured LLM numbers, 300ms-1s latency and a second injection surface |
| R2 Enforcement posture: observe / annotate / taint downgrade | technical | Ruled by CTO agent, 2026-10-13: annotate + observe in v1; taint-based downgrade follows with the #4672 slice - safe to ship unmeasured, downgrade changes canUseTool semantics |
| R3 Slice scope for this PR | technical | Ruled by CTO agent, 2026-10-13: shared module + 3 envelope migrations + WebFetch PostToolUse hook; defer cron issue bodies, plugin CLI, taint, LLM tier; PR uses Ref #4671 |
| R4 Module placement and API | technical | Ruled by CTO agent, 2026-10-13: new server/untrusted-content.ts; prompt-injection-wrap.ts untouched - different trust models |
| R5 Evidence bar before any public claim | technical | Ruled by CTO agent, 2026-10-13: >=150 synthetic fixtures, recall >=0.90, FPR <=0.05, obvious-override >=0.95 in CI vitest; claims scoped to heuristic flagging on fetched web content; prd flags default off; observe 7 days before wrap |
| R6 ADR and C4 | technical | Ruled by CTO agent, 2026-10-13: ADR required (provisionally ADR-287), C4 impact minimal |
| R7 Telemetry fields | technical | Ruled by CTO agent, 2026-10-13: one structured log per classification, breadcrumb only when flagged, Sentry event only on scorer error, never content/query/matches/addresses |
| P1 Cut the wrap flag, the updatedToolOutput rewrite and half of Phase 0 from v1 (DHH, code-simplicity, Kieran) | taste | Plan keeps wrap (CTO R2 ruled it as the second step; issue ask "downgrade it to data-only"); Phase 0 negative result deletes wrap and its flag. Dissent recorded |
| P2 Shrink corpus to ~40 fixtures, drop the frozen holdout (DHH) | taste | Plan keeps >=150 + holdout per CTO R5 threshold ruling; holdout number is the only claim number. Dissent recorded |
| P3 Defer or minimize the three envelope migrations (DHH, code-simplicity) | taste | Plan keeps them (CTO R3; removes drift; wording byte-stable) |
| P4 Drop weak reason codes encoded-blob and hidden-text-or-zero-width (DHH) | taste | Plan keeps them as low-weight signals; recall measured on the corpus decides |
| P5 Mutation matrix 11 rows is heavy (DHH, code-simplicity) | taste | Merged overlapping rows 4/5; rest kept (guard contract lint) |
| P6 Canary cohort before prd-wide wrap flip (spec-flow) | taste | Not in this PR; belongs to the wrap-enable decision tracker |
| P7 CPO sign-off (single-user-incident threshold) | operator (brand) | CPO agent verdict at plan time: approved with conditions (hold the no-claim line; file the P1 remaining-surfaces issue before merge; no prd flag flip without an operator-visible decision; ADR says annotate-not-block, partial, WebFetch-only; roadmap CP1 row text update; thresholds changeable only by a CTO ruling row) |
| P8 Any later public claim about prompt-injection protection | operator (legal-risk) | Out of this PR; routes through the CLO agent, scoped to the measured holdout numbers |
