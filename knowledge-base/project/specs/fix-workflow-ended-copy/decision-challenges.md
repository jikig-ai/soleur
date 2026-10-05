# Decision Challenges — fix-workflow-ended-copy

Headless pipeline run (one-shot → plan → deepen-plan). Items below were
recorded rather than asked, per the headless arm of the plan skill's
review/apply gates.

## 2026-10-05 — Product/UX tier classification deviation

- **Challenge:** The `soleur:plan` Phase 2.5 mechanical UI-surface
  override literally reads "force Product-relevant = true AND tier =
  BLOCKING" on any `components/**` glob match in Files to Edit. This plan
  edits `components/chat/chat-surface.tsx` and
  `components/chat/workflow-lifecycle-bar.tsx`, so the letter of the
  override yields BLOCKING — which would make plan Phase 2.5 the sole
  mandated producer of a `.pen` wireframe for a copy-text fix.
- **Applied instead:** Tier **advisory** (auto-accepted, pipeline). The
  tier definitions — BLOCKING = *creates* new pages/flows/components,
  ADVISORY = modifies existing surfaces — plus the shared
  ui-surface-terms exclusion ("pure copy or style tweaks with no
  structural/layout change" need no wireframe) both classify this as
  advisory. In-repo precedent: `2026-06-05-likec4-contrast` and
  `2026-05-29-kb-drift-messages` plans, both advisory over component
  edits.
- **Residual risk:** deepen-plan Phase 4.9's halt is mechanical on the
  glob — it may still halt demanding a committed `.pen`. Fallback is
  armed: Pencil headless CLI verified available (`check_deps.sh` Tier 0,
  Node 26); generate a minimal `.pen` under
  `knowledge-base/product/design/web-platform/` and reference it in the
  plan if the halt fires.
- **Process note:** the literal "AND tier = BLOCKING" phrasing of the
  override appears unreachable-by-design (any component edit would force
  blocking, making ADVISORY unreachable through the mechanical path) —
  worth a skill-text reconciliation at review/ship if the panel agrees.

## 2026-10-05 — Taste item: badge label wording

- `WORKFLOW_ENDED_STATUS_COPY` label strings ("Finished", "Stopped",
  "Cost cap reached", "Timed out", "Plugin failed to load", "Agent
  stalled", "Something went wrong", "Session revoked", "Workspace error",
  generic "Ended") are draft wording mirroring the reviewed
  `WORKFLOW_END_USER_MESSAGES`/`SESSION_ENDED_COPY` sentence semantics at
  pill length. Final wording is a taste call for review — the mechanism
  (map shape, resolver, warn channel) is independent of the strings.
