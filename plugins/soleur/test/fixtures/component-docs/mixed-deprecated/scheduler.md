---
component: scheduler
updated: 2026-08-06
primary_location: src/scheduler/
dependencies:
  - job-queue
  - legacy-worker
---

# Scheduler

Synthesized fixture. Declares a dependency on `legacy-worker`, which is
`status: deprecated` in this corpus — the resulting edge must be dropped rather
than left dangling at a filtered-out element.

## Dependencies

- **Internal**: job-queue, legacy-worker
- **External**: none
