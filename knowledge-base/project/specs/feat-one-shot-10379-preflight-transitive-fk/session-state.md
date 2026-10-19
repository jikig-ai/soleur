# Session State — one-shot #10379

- **Issue**: #10379 OPEN — `preflight-worm-cascade-contradiction.sh` scans only `confrelid=public.users`; misses table-to-table WORM FK chains (how the #10254 wedge shipped undetected).
- **Branch/worktree**: `feat-one-shot-10379-preflight-transitive-fk` @ `.worktrees/feat-one-shot-10379-preflight-transitive-fk`. Draft PR #10417.
- **Tally**: `feat-one-shot-10379-preflight-transitive-fk-1a22fe` init'd; agent_rounds gate before each spawn batch.
- **Audit comment** (issuecomment-6193176714): no live wedge today; dormant anchors = `dsar_export_audit_pii.job_id → dsar_export_jobs` (SET NULL, mig-160 carve-out is user_id-scoped only) + `action_sends.grant_id → scope_grants` (bare REFERENCES/NO ACTION). Safe-shape refs: email_triage_items/template_authorizations non-user FKs are RESTRICT.
- **Design tension for planner**: stricter gate will flag the two dormant anchors red on main → needs a reviewed allowlist/suppression mechanism OR the anchors get fixed. Deliberate option.
- **Prior arc closed**: #10254/mig162 merged (PR #10385, v3.339.6), verify 8/8 bad=0 on dev.

### Pipeline position (in-flight)
- Plan committed: `2026-10-15-fix-preflight-transitive-fk-plan.md` + tasks.md + decision-challenges.md (7 rows: 3×cto, 1×plan-analysis allowlist→matrix, 1×operator-scope CODEOWNERS, 1×plan ride-along, 1×cpo).
- IN FLIGHT: CTO consult (agent cd68a4ef) on rows 1-3 — cone-refuse severity / census scope / confdeltype='d'. CPO (6babf3ee) + user-impact (f8bb5e33) sign-offs for `single-user incident`.
- Gate structure understood: 183-line script, pg_constraint census at ~119-145 (confrelid=public.users, 'n'/'c' only), disposition loop ~160-180. Test fixture: 6 tests, MOCK_ROWS schema `severity|tbl|trg|fn|fk|action|level|timing` → new schema adds `class|...|parent` per plan.
- Tally: 1 gate pass (agent_rounds) before CTO batch.
- Next: collect 3 agents → record rulings → technical-ruling gate → Phase 0.2 baseline → implement per plan → review → ship → merge.
- Plan disposition matrix (§lines 179-200): cone-refuse+owned → ::error::; cone-write-stmt+owned → ::error::; cone-write-row → ::warning::; dormant → ::warning:: naming parent.
