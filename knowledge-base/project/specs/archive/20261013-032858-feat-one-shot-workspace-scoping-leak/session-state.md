# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-02-fix-workspace-scoping-leak-knowledge-drift-and-feature-audit-plan.md
- Status: complete

## Work Phase — CORRECTED ROOT CAUSE (code-trace + prod probe, 2026-06-02)

The plan's Decision D2/D3 rest on a **false premise**: that the KB-drift walker scans a
per-user workspace KB at `<WORKSPACES_ROOT>/<workspace_id>/knowledge-base` and that a
scanned `workspace_id` should be threaded into the card.

**Actual producer** (`scripts/kb-drift-walker.sh:27-28`, `.github/workflows/kb-drift-walker.yml`):
the walker is a nightly GitHub Actions cron that checks out **Soleur's own dev repo** and scans
`$REPO_ROOT/knowledge-base` + `AGENTS.*.md` + learnings — ONE global company KB. There is no
per-workspace KB scan and no `workspace_id` to thread. The plan-author conflated the KB-drift
walker (CI cron on Soleur's repo) with `resolveActiveWorkspaceKbRoot` (a different subsystem:
per-user workspace KB on the app server disk).

**Read-only prod probe (project ifsccnjhymdmidffkzhl, DATABASE_URL_POOLER, SELECT-only):**
- Founder `52af49c2…` owns TWO workspaces, both named "My Workspace": `52af49c2…` (= founderId,
  **solo**, is_solo=true) and `754ee124…` (second workspace, owner via workspace_members).
  ("Soleur Workspace"/"Chatte Workspace" are the user's informal labels.)
- All **4** kb-drift draft cards are pinned to the SOLO workspace (`52af49c2…`); previews are
  "174 KB-drift findings — Broken link in knowledge-ba…" → they describe **Soleur's company
  repo docs**, confirming the global-KB scan model. Solo-pin is CORRECT.
- Founder `current_workspace_id` = solo. The cards leak onto the second workspace purely
  because the Today read (`today/route.ts:124`) filters by `user_id` only, no `workspace_id`.

### Corrected scope
- **KEEP** Phase 1 (read scoping) — the real + complete fix. `.eq("workspace_id", activeWorkspaceId)`.
- **KEEP** AC3 sibling-route audit, Phase 4 (conversations), Phase 5 (rate-limit + billing).
- **DROP** Phase 2 (walker-threading + insertDraftCard override) — false premise; write already correct.
- **DROP** Phase 3 (migration 093) — the 4 existing cards correctly belong to solo; no re-attribution.

### Errors
None blocking. Plan premise correction documented above (work-skill mandate: trace the actual
producer before coding).

### Components Invoked
- soleur:plan, soleur:deepen-plan; read-only prod probe via pg/DATABASE_URL_POOLER.
