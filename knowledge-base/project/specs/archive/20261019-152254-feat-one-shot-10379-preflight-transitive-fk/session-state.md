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

### Work Phase (in-flight, post-compaction resume point)
- Rulings: CTO confirmed all 3 (fail-closed cone-refuse; WORM-only census + all-tables follow-up; 'd' in write classes w/ UPDATE match). CPO APPROVE (2 blocking: rulings hold + live census cited; 3 non-blocking incl. unconditional all-tables issue). User-impact REJECT→RESOLVED via new ## User-Brand Impact section.
- DONE: test.sh rewritten (12 tests, 9-col class|tbl|trg|fn|fk|action|level|timing|parent schema) + gate rewritten (del CTE, 4 classes, DISTINCT ON dedup, silent r/a-to-roots carve, per-class copy). Fixture: 26/26 GREEN.
- TODO: (a) live dev census via extended query vs audit set; (b) file 2 dormant-anchor issues + all-tables follow-up, link in warning copy? (warning text says "file a tracking issue" generically — plan 2.2 wanted links); (c) ride-along account-delete.ts:411 RESTRICT→NO ACTION comment; (d) tenant-integration.yml ~654 comment wording; (e) CODEOWNERS pin if approved (CPO recommended yes); (f) commit+push → review panel → fix-round → ship → merge → postmerge → DONE.
- Pins: error copy "users with rows" + transitive remediation (done); action↔event match preserved (done); DISTINCT ON per-FK dedup (done); dormant warns r/a subclass emphasis (done via copy).

### Column-scoping fix (post-compaction anchor)
- Live census caught cone-write-stmt FALSE-POSITIVE on action_sends.message_id (mig-162 residue: statement trigger excludes message_id). Fixed: 'n'/'d' event match now requires `tg.tgattr = ''::int2vector OR conkey ∩ tgattr` — column-scoped UPDATE OF triggers only match when they cover the FK column.
- NEXT: re-run /tmp/extended-census.sql regenerated from the script + fixture suite; expect cone-write-row for message_id via the row guard, ZERO cone-refuse/cone-write-stmt. Then: file 3 issues (dsar job_id anchor, action_sends.grant_id anchor, all-tables cone-scan follow-up), ride-alongs (account-delete.ts:411 comment, tenant-integration.yml:654 wording), CODEOWNERS pin (CPO rec'd yes — needs operator-scope ruling, default YES per recommendation), commit+push → 3-seat review → fix-round → ship/merge → postmerge → DONE.

### Pre-review state (commit-ready)
- Gate + test GREEN (26/26), tgattr column-scoping fix verified vs dev census (0 blocking rows, 19 dormant, 4 cone-write-row residue).
- Issues filed: #10573 (dsar job_id), #10574 (action_sends.grant_id), #10575 (all-tables scan — CPO-conditional-unconditional).
- Ride-alongs done: account-delete.ts:410-414 (grant_id NO ACTION + app.worm_bypass), tenant-integration.yml:654 wording.
- CODEOWNERS pin: deferred (operator-scope row — CPO recommended; noted for PR body).
- NEXT: commit+push → 3-seat review → ADR-267 fix-round → ship (PR body w/ census output + changelog + Closes #10379, semver:patch) → ready → merge-queue → postmerge verify → DONE.

### Review fix-round landed
- 2-seat review: gate-SQL seat live-verified the query on PG17.6 (0 P1); disposition seat found fail-open `*)` arm + missing issue links.
- Fixed: `confdelsetcols` scope (PG15 subset-FK false-flag), `cns.nspname='public'` child bound (kills storage.objects + cross-schema owned_by_ref false-red), `tgenabled NOT IN ('D','R')`, stable DISTINCT-ON tie-break, fail-loud `*)` arm, issue links (#10573/10574/10575) in dormant copy, yml severity sentence, header over-inclusion note, test-3 comment.
- Live census post-fix: 0 blocking, 18 dormant, 4 cone-write-row — fixture 26/26.
- NEXT: ADR-267 fix-round seat → ship (PR body + Changelog + semver:patch + Closes #10379) → ready → merge → postmerge.
