# Decision Challenges — feat-one-shot-10045-kdeny-least-priv

Headless pipeline run (one-shot → plan). No TTY; per plan/SKILL.md classifier routing,
Taste-class findings persist here for `soleur:ship` Phase 6 to render.

## 2026-10-11 — plan-review (sequential-fallback, self-applied panel rubric)

### Taste — `src=` vocabulary unchanged on the privileged path

- **Decision:** after the grant lands, `src=journal` names the *stream*, not the privilege path
  that read it; no new `src=`/`j=` enum value marks "read via sudo grant".
- **Context:** a reviewer lens could argue `j=ok` via the root grant vs. via a hypothetical
  unprivileged path are different facts worth separating in the row.
- **Why kept:** vocabulary stability (runbook + Better Stack queries + tests all key on
  `journal|dmesg|none`); provenance is recoverable out-of-band (the provisioner execute probe
  proves the grant; sudo's own journal `COMMAND=` record audits each read). A new enum value would
  widen the row schema for a distinction the diagnostic never acts on.
- **Disputed if:** a future incident needs to know *which* channel read the stream from the row
  alone — revisit then.
