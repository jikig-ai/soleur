# Soleur Plugin — Component Diagram (C4 Level 3)

Generated: 2026-03-27 · Migrated to LikeC4: 2026-06-03

Rendered interactively from the canonical LikeC4 model in this directory
(`spec.c4`, `model.c4`, `views.c4`). This is the deepest level — drilled into
from the **Soleur Plugin** box in the container view.

```likec4-view
components
```

## Notes

- Three commands (go, sync, help) are the only user-facing entry points (ADR-016)
- One-shot orchestrates the full pipeline: plan → work → review → compound → ship (ADR-015)
- Domain leaders (CTO, CMO, CPO) participate in brainstorm Phase 0.5 and plan Phase 2.5 (ADR-013)
- CTO agent detects architectural decisions and recommends `/soleur:architecture create`
- Architecture-strategist checks ADR coverage during review as advisory finding
- 8 review agents run in parallel during `/soleur:review` — only architecture-strategist shown here
