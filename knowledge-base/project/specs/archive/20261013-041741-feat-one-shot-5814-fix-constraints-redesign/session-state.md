# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-01-feat-fix-constraints-two-stage-privileged-split-plan.md
- Status: complete

### Errors
None. (Two non-error notes: one Edit retried after a linter touched the file; the "BROKEN" KB-citation flag for `ADR-074-….md` is expected — it is a Files-to-Create deliverable, not a broken reference.)

### Decisions
- #5814 supersedes #5804 (close, not merge). Premise validation found the redesign-target `fix-constraints.yml` + template exist only in held draft PR #5804, not on main; all dependencies (anthropic-preflight, extract-api-spend.sh, constraint-gates.sh/.yml) are already on main, so #5814 stands alone on top of main and #5804 is closed on merge.
- Two-stage trigger split (`pull_request` Stage A producer / `workflow_run` Stage B consumer) is the primary architectural decision (ADR-074, new); the Git Data API data-plane (full post-image file contents → blobs/tree/commit, no checkout, no `git apply`) is the enabling mechanism that makes the CodeQL `untrusted-checkout-toctou` sink structurally absent.
- Corrected a load-bearing security error mid-deepen (security-sentinel P0): `pull_request` runs the fork's own Stage A definition, so the artifact is 100% attacker-controlled — the "fork → no key → no artifact" reasoning was wrong. Added Stage B's explicit `isCrossRepository==false` + single-matching-PR gate as the real fork defense.
- Auto-recovery is fix-only (data-integrity P0): the dependency-cruiser suppression baseline is removed from both allowlists, so the agent cannot green a tripped gate by whitelisting a real client→server-secret leak; baseline growth stays a maintainer-only local action.
- Capped per-tenant Anthropic key is `automation-status: UNVERIFIED`: the Admin API confirmed cannot create keys (Console-only) or set regular-tier spend limits, but the Console UI stays presumptively Playwright-automatable — /work must attempt before any operator handoff.

### Components Invoked
- Skills: `soleur:plan`, `soleur:deepen-plan`
- Agents (plan phase): `soleur:engineering:cto`; 2 research agents (Explore — workflow_run/held-artifact precedent; `learnings-researcher`)
- Agents (deepen phase): `security-sentinel`, `architecture-strategist`, `data-integrity-guardian`, + capability-verification Explore (Git Data API / download-artifact / CodeQL default-setup / Anthropic Admin API)
- Mandatory deepen gates run: 4.6 User-Brand Impact (pass, threshold `single-user incident`), 4.7 Observability (pass), 4.8 PAT-halt (pass), 4.9 UI-wireframe (skip — no UI surface), 4.4 precedent-diff
