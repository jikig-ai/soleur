---
title: "feat: egress audit view time-window selector (24h / 7d / 30d)"
date: 2026-11-03
slug: feat-egress-audit-time-window-selector
branch: feat-one-shot-11238-egress-audit-time-window
issue: 11238
type: feat
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

## Enhancement Summary

**Deepened on:** 2026-11-03
**Sections enhanced:** Research Insights, Architecture Decision, Phase 0, Phase 1, Phase 6, Guard Contract, Domain Review
**Agents and passes used:** repo-research-analyst, learnings-researcher, spec-flow-analyzer, CPO, CLO (prepare-and-review), CTO (three rulings), ux-design-lead, gdpr-gate, plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, CTO devex lens), plus the deepen verification gates below.

### Key Improvements

1. Same-name overload replaced by a distinct function after the RLS fuzz AC7/AC8 no-overload gate was found (CTO row 5); no security-gate harness rewrite.
2. Plan-review cuts applied: identity helpers, redundant verify rows, clamp/top-N live reruns, Guard matrices trimmed to rows that test distinct properties, decision axis and source scan removed from Guard 2.
3. Staleness sweep widened: three `model.c4` places, the DSAR allowlist comment, the runbook rollback order, and the Art. 30 register and DPIA rows carried to the flag-on legal sign-off.
4. Copy honesty: the default-window view changes four strings (CLO-reviewed) and the plan now says so instead of claiming byte-identity.
5. A retirement path for the duplicated body is written into the ADR amendment so the card-count PR cannot add a third copy.

### Deepen verification log (run 2026-11-03)

- Halt gates: 4.6 User-Brand Impact present (threshold `single-user incident`); 4.7 Observability present, probe verb `grep` is allowlisted and the block is new in this change; 4.8 no PAT-shaped token (grep: none); 4.9 the plan references a committed `.pen` (`git ls-files` confirms `knowledge-base/product/design/settings/egress-audit-log.pen`); 4.10 Encryption Posture present, stated by reference to the existing `supabase.prd` ledger entry; 4.11 `python3 scripts/lint-guard-contract.py` on this plan: 1 plan, 2 guard entries, exit 0; 4.12 exactly one unfenced `## Scope Check`.
- Cited paths verified present: C4 tests (`c4-code-syntax`, `c4-render`, `c4-count-parity`), `dsar-allowlist-completeness.test.ts`, `web-egress-toggle.test.tsx`, the Sentry op-contract test, `scope-grants-page-egress-wiring.test.ts`, `migration-rpc-grants.test.ts`, `regenerate-c4-model.sh`, `run-migrations.sh`, `run-verify.sh`, ADR-112.
- Cited issues verified live: #9601 open, #11238 open, #9545 closed (the parent whose deferral this is). Ordinal: `origin/main` has no `183_*` migration (count 0) and 182 is the highest.
- Negative claims verified by grep: `EgressAuditPayload.window` is read by no runtime code (research pass); the `webapp -> supabase` edge in `model.c4` says "fixed 30-day window"; `verify/177` has twelve rows (ten function rows, two table rows); the enablement issue's number appears nowhere in the plan, tasks or decision file (grep count 0).

## Overview

Issue #11238 (epic #9601, deferred out of #9545 PR2) asks for a time-range choice on the workspace egress audit view: 24 hours, 7 days, 30 days. The view today shows a fixed 30-day window and the member read function (migration 177) has no window argument.

This plan ships the choice with the window applied **on the server**, in a new read function, and a link-chip selector on the page. The stored rollup rows are per-host sums over their own 15-minute buckets, and the read function returns one summed row per (host, decision); a client-side filter over that response cannot recover a shorter window, so it would show counts that belong to a different period than the label.

Out of this PR (CTO ruling 1): the "requests in the last 24 hours" count on the Agent web access card. It would add a windowed sum to the Scope Grants render path, where `p_limit = 0` is a deliberate O(1) probe. It ships later on the same issue (Ref only, no new issue). The card keeps calling the existing 3-argument function untouched.

Holds that bound every phase (CTO ruling 3): no feature flag or environment is created or flipped (collection stays off, the view stays dark); `docs/legal`, `plugins/soleur/docs` and the DPIA addendum are not edited; copy describes only what is measured; the 30-day retention sentences and the member-visibility sentence stay byte-identical; PR text carries only `Ref #11238` / `Ref #9601`, no closing keyword, and does not announce the feature as live or as a guarantee.

## Premise Validation

Checked 2026-11-03 before any research fan-out:

- **#11238** is open (labels `priority/p3-low`, `type/feature`, `domain/product`; milestone "Post-MVP / Later"), body matches the brief: selector on the view, plus a card count (descoped here by ruling 1). **#9601** is open.
- **Collision pre-check** (`collision-precheck.sh 11238`): one hit, PR #11990, which is this branch's own draft PR (empty body, no files). No foreign work.
- **Migration number.** Highest on `origin/main` is `182_git_data_erasure_pending` (fetched 2026-11-03), so the next ordinal is **183**. Re-verify at work time and again at ship after every sync with `origin/main`; a sibling can claim 183 mid-pipeline.
- **ADR-288 exists** (`ADR-288-aggregated-egress-audit-spool-via-vector-to-app-ingest.md`), status Adopting, already carries `Amendment 2026-10-26 (#9545 PR2)`. The new note is a second dated amendment.
- **Cited artifacts exist** on this tree: migration 177 and its `.down.sql`, `verify/177_*.sql`, `test/supabase-migrations/177-*.test.ts`, `rls-fuzz/rpc-cases.ts`, `rls-fuzz/targets.ts`, the page, view, refresh button, loader and `lib/egress-audit/summary.ts`. This is a *build on an existing view*, not a fix.
- **Mechanism vs ADR corpus.** ADR-288's amendment says "ONE `SECURITY DEFINER` function" and "Fixed 30-day window". This plan extends it (a second function sharing the contract) and records that in the new amendment; it does not re-open a rejected alternative.
- **Premise that changed during planning.** Ruling 2 asked for a same-name 4-argument overload. Evidence found while planning (the RLS fuzz coverage gates assert that no authenticated-executable definer function is overloaded) led the CTO agent to rule a distinct function name instead (decision-challenges rows 5-7). The rest of ruling 2 stands.

## Research Insights

### Property List (what the issue's mechanism must buy)

1. A member can choose 24 hours, 7 days or 30 days, and the counts and rows shown belong to the chosen period (to the precision the data allows).
2. Choosing a window never weakens who may read: membership first, token-denylist second, then argument validation.
3. The default view (no parameter) behaves exactly as today (30 days).
4. The copy never states more than is measured: counts stay minimums; the period is "about the last N" because 15-minute buckets straddling the window start are counted whole.
5. Retention and visibility statements do not change, and a shorter view window is not presented as a shorter retention.
6. The old 3-argument function keeps working for the previous app image during a deploy (migrate job runs before deploy) and for the Scope Grants card.
7. The change is reversible by a down migration that removes only what it added.

### Cut List

| Mechanism | Property | What already covers it / verdict |
|---|---|---|
| Client-side filtering of the 30-day response | 1 | Cut: cannot recover a window from per-host sums (ruling 1). |
| Same-name 4-argument overload (ruling 2 as first written) | 6 | Replaced by a distinct function name: AC7/AC8 gates reject overloads; the distinct name buys property 6 with no harness rewrite (row 5). |
| 3-argument function turned into a wrapper over the new one | 6 | Cut: 177 is immutable, the previous image calls it, and a wrapper would force the down file to restore the 177 body (row 6). |
| Echoing the chosen window key inside the payload (`'key'`) | 1 | Cut: the payload shape stays byte-identical across both functions; the page already holds the parsed window. YAGNI. |
| Probing the 30-day data to say "older activity exists" in a shorter-window empty state | 1 | Cut: a second RPC call adds latency and a failure path; the empty state links to 30 days instead. |
| Windowed 24-hour count on the card | out of scope | Deferred by ruling 1 (Ref only). |
| Persisting the chosen window per member | none asked | Cut: the URL is the state; default 30 days on every visit. |

### Institutional learnings applied

- `2026-10-26-sentry-groups-by-message-and-a-lost-grant-read-as-a-denial.md`: the 177 read path precedent. Denial messages must keep the `egress audit: ` prefix and SQLSTATE 42501 only for the in-body authz denials; plan-cache flip fixed with `plan_cache_mode = force_custom_plan` (carry into the new function); 177 was once edited in place after dev applied it, which is the failure this plan avoids by adding 183.
- `2026-09-24-editing-an-already-applied-migration-during-review-breaks-the-dev-ledger.md`: the dev-ledger guard compares byte identity, so even a comment edit to 177 fails CI. 177 stays byte-identical.
- `security-issues/2026-07-10-supabase-default-privileges-defeat-revoke-from-public.md`: REVOKE from PUBLIC does not remove the explicit anon/authenticated grants Supabase default privileges add; the new function revokes each role by name, then grants `authenticated` only.
- `2026-07-11-rls-migration-verify-savepoint-and-signature-scope.md`: verify sentinels scope to the exact signature; follow-up queries after a RAISE need a SAVEPOINT in the live suite.
- `2026-10-26-posture-sentinel-must-track-the-diff-that-changes-the-posture.md`: `run-verify.sh` runs every file in `supabase/verify/`; add `verify/183_*.sql` for the new signature (grant posture is new, so a new sentinel is required).
- `bug-fixes/2026-06-01-postgrest-rpc-named-arg-mismatch-silent-client-revert.md`: PostgREST resolves by the set of supplied argument names; a mismatch is PGRST202 that `tsc` cannot see. A loader test pins the exact four argument names.
- `2026-05-29-legal-doc-triple-lockstep-and-rpc-grants-invoker-before-definer.md` and `best-practices/2026-06-19-sql-function-body-parser-must-anchor-to-create-not-bare-function.md`: the static grants lint and any body parser must anchor on `CREATE ... FUNCTION`, not the bare function name, now that two functions share a prefix.
- `2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md`: a new function may not be callable until the schema cache reloads. `run-migrations.sh` forces a reload through the Supabase Management API after every run (best-effort when no access token is present); the direct-pg pooler path cannot deliver `NOTIFY`, so without the token the cache can lag up to the natural poll interval. The loader reports it as a paged `rpc_error` (`pg_code` PGRST202), which is the correct loud outcome; the view is dark so no member sees it.
- `2026-05-30-migration-number-collision-and-stale-plan-current-state.md` and `workflow-patterns/2026-06-30-migration-number-collision-mid-pipeline.md`: re-check the ordinal at ship after every sync.

### Repo facts (anchors, not line numbers)

- **Page:** `app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page.tsx`, `EgressAuditPage`: `searchParams: Promise<{ decision?: ... }>`, `parseDecisionFilter`, then `loadEgressAudit(supabase, user.id, filter)` and `<EgressAuditView result filter />`.
- **Loader:** `server/egress-audit-read.ts`, `loadEgressAudit`: `call(supabase, "get_egress_audit_summary", { p_workspace_id, p_limit: PAGE_LIMIT, p_decision }, ...)`; `readHint` is the separate `p_limit: 0` card probe and stays on the 177 function.
- **Types and helpers:** `lib/egress-audit/summary.ts` (`DecisionFilter`, `parseDecisionFilter`, `toRpcDecision`, `EgressAuditPayload`, `PAGE_LIMIT`, `EGRESS_AUDIT_PATH`, `RPC_DENIAL_PREFIX`, `formatAtLeast`, `formatAgo`). `EgressAuditPayload.window` is typed and structurally checked but read by no runtime code.
- **View:** `components/settings/egress-audit-view.tsx`: `hrefFor`, `Chips`, `Header`, `HostTable` (sr-only caption), `ReadyView` state ladder, `Banner` (retention and visibility sentences). Window-scoped strings that say 30 days today: header subtitle, table caption, truncation body, filter-empty line, web-off empty title.
- **Refresh button:** `egress-audit-refresh-button.tsx` calls `router.refresh()` with no arguments, so the URL (and a window parameter) is preserved with no change. The "Show all" link and `hrefFor` currently drop every other parameter and must carry the window.
- **Fuzz harness:** `test/rls-fuzz/rls-rpc.integration.test.ts` AC7/AC8 key classification on bare function name via `ATTACK_SQL` / `EXCLUDED` / `KNOWN_EXPOSURES` in `rpc-cases.ts` and assert no overloads; `CLASSIFIED_DEFINER_FN_NAMES` also feeds `test/migration-rpc-grants.test.ts` (ADR-112). `targets.ts` has a prose note for the rollup table that names migration 177.
- **Not affected:** `174_api_data_grants_snapshot.sql` covers relations only (no function rows); `178_api_data_grants_narrowing.sql` does not reference the function; `egress-audit-rpc-denial-prefix.test.ts` reads only `177_*` (extend, see Phase 1).
- **Residuals recorded by research (unverified in repo, not blocking):** the "8 s role timeout" in the 177 header is not set by any migration in the repo; the "one backward PK probe" claim depends on the planner. The new function copies both comments' substance only where it can restate them; it does not add new performance claims.

## User-Brand Impact

**If this lands broken, the user experiences:** a member opening the egress audit page sees the "Couldn't load the egress audit log" error card on every load (new function missing or not callable), or a list whose rows and counts belong to a different period than the selected chip. The view is dark (collection flag off), so no member sees either today; the cost is a wrong or failing screen the day the operator enables collection.

**If this leaks, the user's workflow metadata is exposed via:** the new `SECURITY DEFINER` read function. A definer bypasses row-level security, so a missing or reordered membership check, or a dropped `workspace_id` predicate, would let one workspace read which external hosts another workspace's agents contacted. The plan keeps authz as the first two statements, validates the window only after them, carries the tenant predicate on every read, and adds the function to the cross-tenant fuzz harness.

**Brand-survival threshold:** single-user incident

`requires_cpo_signoff: true` (carried from ADR-288's threshold). CPO plan-time review: acceptable to ship (cheap, explicitly filed, view dark), conditions adopted below. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A time-range selector on the egress audit view (24 hours, 7 days, 30 days)" [issue #11238] | Phases 1-4 (new function, loader, page, view); Files to Create/Edit | mapped |
| 2 | "a \"requests in the last 24 hours\" count on the Agent web access card" [issue #11238] | none | descoped - justification: CTO ruling 1 defers it to a later PR on the same issue because a windowed sum on the Scope Grants render path is unmeasured against a deliberate O(1) probe |
| 3 | "a window argument is an additive migration" [issue #11238] | Phase 1 (migration 183, down file, verify sentinel) | mapped |
| 4 | "SERVER-SIDE window (client-side filtering is unsound" [brief, ruling 1] | Phase 1 and Phase 3 | mapped |
| 5 | "Do NOT edit migration 177 (immutable)" [brief, ruling 2] | Phase 1 (177 untouched; parity guard reads it) | mapped |
| 6 | "validated AFTER the two authz checks with SQLSTATE 22023, no argument defaults" [brief, ruling 2] | Phase 1, Guard 1 and the 183 shape test | mapped |
| 7 | "Down file drops only the new overload" [brief, ruling 2] | Phase 1 (down file drops only the new function; "overload" became a distinct name, row 5) | mapped |
| 8 | "Extend test/supabase-migrations 177 test pattern, rls-fuzz rpc-cases.ts and targets.ts" [brief, ruling 2] | Phase 0 and Phase 5 | mapped |
| 9 | "Capture as an amendment note to ADR-288" [brief, ruling 2] | Phase 6 | mapped |
| 10 | "do not create or flip any feature flag or environment" [brief, ruling 3] | No flag file is in Files to Edit; AC9 | mapped |
| 11 | "docs/legal and plugins/soleur/docs unchanged" [brief, ruling 3] | Files to Edit excludes both; AC9 | mapped |
| 12 | "make empty-state/aria-label strings in egress-audit-view.tsx window-aware" [brief, ruling 3] | Phase 4; Guard 2 | mapped |
| 13 | "the 30-day retention lines ... and the visibility copy ... stay byte-identical" [brief, ruling 3] | Phase 4; AC6 | mapped |
| 14 | "run soleur:legal:clo as prepare-and-review on the diff's user-visible strings" [brief, ruling 4] | Phase 7 (plan-time pass done: PASS-WITH-CHANGES, changes folded in; work-time pass on the real diff) | mapped |
| 15 | "Record the four rulings above there as technical rows" [brief] | `specs/feat-one-shot-11238-egress-audit-time-window/decision-challenges.md` rows 1-4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| New migration `183_egress_audit_window_summary.sql` and `.down.sql` | "a window argument is an additive migration" | asked |
| `supabase/verify/183_egress_audit_window_summary.sql` | "Keep unchanged: authz-first ordering ... REVOKE/GRANT to authenticated only" | inferred - justification: `run-verify.sh` asserts live grant posture per signature on every deploy; the new signature has no sentinel otherwise, and the 177 sentinel pins only the 177 signature |
| `test/supabase-migrations/183-egress-audit-window-summary.test.ts` (shape + parity Guard 1) | "Extend test/supabase-migrations 177 test pattern" | asked |
| `lib/egress-audit/summary.ts`: `TimeWindow`, `parseTimeWindow`, labels | "A time-range selector on the egress audit view (24 hours, 7 days, 30 days)" | asked |
| Loader and page wiring | "SERVER-SIDE window" | asked |
| View selector chips and window-aware strings | "make empty-state/aria-label strings in egress-audit-view.tsx window-aware" | asked |
| "Show 30 days" link in the shorter-window empty state | "(buckets straddling the window start can over-count, never \"exactly\")" | inferred - justification: without it a 24h or 7d empty state is a dead end when the 30-day list has data (spec-flow gap 2); no second probe is used |
| Guard 2 render sweep over states x windows | "make empty-state/aria-label strings in egress-audit-view.tsx window-aware" | inferred - justification: the five hard-coded 30-day strings are the defect class; a sweep keeps a sixth from reappearing |
| `rpc-cases.ts` / `targets.ts` registration | "rls-fuzz rpc-cases.ts and targets.ts" | asked |
| `egress-audit-rpc-denial-prefix.test.ts` extended to 183 | "Keep unchanged: authz-first ordering" | inferred - justification: the loader tells an in-body denial from an engine grant error by message prefix; the test reads only `177_*`, so 183's messages would be unchecked |
| ADR-288 amendment | "Capture as an amendment note to ADR-288" | asked |
| `model.c4` edge text edit + regenerated `model.likec4.json` | "Capture as an amendment note to ADR-288" | inferred - justification: the `webapp -> supabase` edge says "over a fixed 30-day window"; that sentence becomes false and the C4 completeness mandate requires correcting it in the same change |
| Runbook note in `egress-audit-enable.md` | "Keep old 3-arg signature working" | inferred - justification: the runbook's paged-fault triage names only the 177 function and its lost-grant query; with a second function, on-call would check the wrong signature |

### Split Assessment

- Subsystems touched: 4 roots (`apps/web-platform`, `knowledge-base`, plus the generated C4 JSON under `knowledge-base`) - effectively 2: `apps/web-platform`, `knowledge-base`
- Planned files: 24 | Estimated changed lines: ~950 (of which ~350 are the duplicated SQL body and its tests)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The line count crosses the 800 tunable only because the SQL body is duplicated by ruling (row 6) and mirrored by tests; there is no clean seam (migration, loader, view, and gates must land together, because a view calling a function that is not yet applied faults, and the gate additions are what make the migration safe).

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-288** (`knowledge-base/engineering/architecture/decisions/ADR-288-aggregated-egress-audit-spool-via-vector-to-app-ingest.md`) with `## Amendment 2026-11-03 (#11238): the member read gains a window, in a second function`, authored via `soleur:architecture` as a task in Phase 6 (not a follow-up issue). Content, in short:

- Members read through TWO definer functions with one contract: `get_egress_audit_summary` (migration 177: fixed 30-day window; kept for the Scope Grants card hint and for the previous app image during deploy skew) and `get_egress_audit_window_summary(p_workspace_id, p_limit, p_decision, p_window)` (migration 183: `p_window` in `24h`, `7d`, `30d`, no defaults). Supersedes the amendment's "ONE `SECURITY DEFINER` function" and "Fixed 30-day window" wording.
- Same-name overload rejected (Alternatives): the RLS fuzz gates AC7/AC8 and the ADR-112 static allowlist key on bare function name and assert no overloads; a distinct name avoids rewriting a security-gate harness and any named-argument ambiguity in PostgREST.
- Window is derived after authz and validated against an allowlist with a CASE map (never cast from caller text), 22023 on anything else including NULL. Bounded above by `now()`; `last_seen` predicate unchanged; the 15-minute bucket slack remains a scan aid, so a bucket straddling the window start is counted whole (the UI says "about the last N").
- Retention is unchanged: a shorter window is a narrower read of the same stored rows; the purge still keys on `last_seen` at 30 days.
- Drift between the two bodies is capped by a text-parity guard (default suite) and a live parity check (gated suite).
- Retirement path (a decision, not a hope): the card's 24-hour count is a later PR on #11238. That PR must either move the card to the 183 function and retire the 177 function in the same change (deleting the parity guard, the 177 verify rows' successor and the loader's three-argument pin in that PR), or add a separate count-only function. It must NOT add a third copy of the body; if a third reader is ever needed, extract the shared aggregation into a non-granted `STABLE` helper first. The later PR also flips AC8's expectations and the loader test that pins the card probe's argument object. No separate issue (ruling 1); this paragraph is the record.
- The 2026-10-26 amendment gets a one-line back-pointer ("its 'ONE function' and 'Fixed 30-day window' statements are superseded in part by the 2026-11-03 amendment") so a reader of the first amendment is not misled.
- Status stays **Adopting**.

### C4 views

C4 completeness check performed by reading `model.c4`, `views.c4` and `spec.c4` for the actors and systems this feature touches (external human actor: workspace member reading the page; external system: none new; data store: Supabase Postgres, existing; access relationship: workspace member to webapp to supabase, existing, membership-gated). All are already modeled. The one change: the `webapp -> supabase` edge in `model.c4` describes the read path "over a fixed 30-day window". That sentence becomes false. Phase 6 edits three places so they stop being false: (1) the `webapp -> supabase` edge: the page calls `get_egress_audit_window_summary` and the card hint calls `get_egress_audit_summary`, "over a 24-hour, 7-day or 30-day window (default 30 days)"; (2) the `hetzner -> platform.webapp` edge, which says members read "only through the get_egress_audit_summary RPC"; (3) the comment block above it (around the "Members read the table only through" sentence). It then re-renders `model.likec4.json` with `bash scripts/regenerate-c4-model.sh`, and runs `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (no cardinality in that sentence changes; the parity test must stay green). No new element or relationship.

### Sequencing

The ADR describes the target state now. No soak gate: the status flip to `accepted` stays tied to the enablement work already recorded in the ADR, which this plan does not touch.

## Implementation Phases

Follow `cq-write-failing-tests-before`: Phase 0 lands first and is RED against the unchanged tree.

### Phase 0 - Tests first (RED)

All paths under `apps/web-platform/` (cwd-independent: `git rev-parse --show-toplevel` then this prefix).

1. `test/supabase-migrations/183-egress-audit-window-summary.test.ts` (new). Pattern: the 177 shape test. Pins (each as its own `it`, over comment-stripped SQL):
   - files exist (`183_egress_audit_window_summary.sql`, `.down.sql`, `supabase/verify/183_*.sql`);
   - exactly one `CREATE OR REPLACE FUNCTION public.get_egress_audit_window_summary(` with exactly four parameters `p_workspace_id uuid, p_limit integer, p_decision text, p_window text` and **no `DEFAULT`** anywhere in the parameter list; `SECURITY DEFINER`, `STABLE`, `SET search_path = public, pg_temp`, `SET plan_cache_mode = force_custom_plan`;
   - statement order: membership check first (same regex as 177, 42501, constant message with `RPC_DENIAL_PREFIX`), jti check second (once), then the `p_decision` check, then the `p_window` check, then the `p_limit = 0` probe; the `p_window` check raises `ERRCODE = '22023'` with a message that starts with `RPC_DENIAL_PREFIX`; `p_window` is not referenced at all before the jti statement ends;
   - the window is derived by a `CASE p_window WHEN '24h' ... WHEN '7d' ... WHEN '30d' ... END` map to a literal `interval`, with no `p_window::interval`, no `p_window ||`, no `format(`, no `EXECUTE`;
   - `v_lo` is `v_now - <mapped interval>` and every read keeps `last_seen >= v_lo` and `last_seen <= v_now` and both 15-minute bucket slack bounds;
   - tenant predicate: the number of `workspace_id = p_workspace_id` occurrences in the 183 body is asserted as an exact count equal to the number of `FROM public.workspace_egress_audit_rollup` reads (a regex that "matches somewhere" would pass with one dropped); `v_span` and `v_lo` are assigned only after the `p_decision` check; the `CASE p_window` has no `ELSE` branch (so NULL and unknown fall to the 22023 check);
   - 177-test pins that cannot be copied as is: the `p_limit integer DEFAULT 200` signature pin and `PAGE_LIMIT === default` (183 has no defaults) become `PAGE_LIMIT` equals the `COALESCE(p_limit, 200)` literal; the in-body message list is four entries in this order (membership, token, decision, window); the "`p_window` not referenced before the jti statement" scan starts after `BEGIN` because the signature itself contains `p_window`;
   - the shape test pins only what DIFFERS from 177 (signature, no defaults, the CASE map, order, window-derived `v_lo`, grants, down file). Clamp, sums, top-N, materialization and the 15-minute slack are pinned once, in Guard 1's parity against the immutable 177 body, not a second time here;
   - `REVOKE ALL ON FUNCTION public.get_egress_audit_window_summary(uuid, integer, text, text) FROM PUBLIC, anon, authenticated, service_role` then exactly one `GRANT EXECUTE ... TO authenticated`; no table grant, policy, trigger, `statement_timeout`, `source_host`;
   - returns the typed contract keys (`'window'`, `'truncated'`, `'summary'`, `'rows'`, `'overflow'`, `'last_request_at'`) and the `'window'` object has exactly `start` and `end`;
   - the down file drops exactly `public.get_egress_audit_window_summary(uuid, integer, text, text)` and nothing else, and does not mention `get_egress_audit_summary`;
   - **Guard 1 parity** (see Guard Contract): body-parity between the 177 and 183 function bodies modulo a named normalization;
   - verify sentinel rows (below).
2. `test/egress-audit-rpc-denial-prefix.test.ts` (edit): iterate `[177, 183]` files so every `42501` raised in 183 carries the prefix, and the 22023 messages in both also carry it; keep the non-vacuity floor per file.
3. `test/egress-audit-summary-helpers.test.ts` (edit): `parseTimeWindow` (undefined, empty, `bogus`, `30D`, ` 7d`, repeated `["7d","24h"]` takes the first like `parseDecisionFilter` and falls back only when the first is unknown), the `WINDOW_LABEL` table for all three, `DEFAULT_TIME_WINDOW === "30d"`, and an allowlist-drift test: the keys of the `CASE p_window` map in `183_*.sql` equal `TIME_WINDOWS` (a TypeScript/SQL drift would otherwise surface only as a runtime 22023).
4. `test/egress-audit-read-loader.test.ts` (edit): the page RPC is called as `get_egress_audit_window_summary` with exactly `{ p_workspace_id, p_limit: 200, p_decision, p_window }` for each window and each decision; the card probe (`loadEgressCardState`) still calls `get_egress_audit_summary` with exactly `{ p_workspace_id, p_limit: 0, p_decision: null }` and **no `p_window`** (this is the guard for ruling 1: the Scope Grants hot path is untouched); a PGRST202 reply is a paged `rpc_error` with `pg_code` `PGRST202` and renders `unavailable` (skew case), never falls back to the 177 function; a 22023 reply is a paged `rpc_error` (not `forbidden`); the sentry op contract test is unchanged and must stay green (no new op).
5. `test/egress-audit-page-wiring.test.ts` (edit): `?window=` parsing (valid x3, unknown, repeated, mixed case) reaches the loader as the 4th argument and the view as `timeWindow`; independent of `decision`; the `render` helper accepts both params; the existing `toEqual({ result, filter })` becomes `{ result, filter, timeWindow }`.
6. `test/egress-audit-view.test.tsx` (edit): see Phase 4; includes Guard 2 sweep.
7. `test/rls-fuzz/egress-audit-rollup.integration.test.ts` (edit, live-database suite, gated by `RLS_FUZZ_LOCAL=1`, local DSN only): new `describe` for the window function: per-window inclusion (rows seeded at 60 minutes, 3 days, 10 days, 29 days: `24h` returns the first, `7d` the first two, `30d` all four); `p_limit = 0` probe respects the window (a 3-day-old row only: `24h` gives null `last_request_at`, `7d` gives it); a bucket straddling the window start is counted whole and documented as accepted (assert the larger value); a future-dated bucket is excluded; non-member with an invalid window gets the membership 42501 (order oracle), a member gets 22023, NULL window gets 22023; jti-denied member is refused before the window check; cross-tenant: with workspace B data present, a member of A sees none of it for each window; anon and service_role fail on the engine GRANT (text differs from the in-body denial); `window.end - window.start` equals the chosen span; **live parity**: for the seeded fixture, `get_egress_audit_window_summary(ws, 200, null, '30d')` equals `get_egress_audit_summary(ws, 200, null)` as jsonb (both read `now()` of the same transaction, so `window` matches too), including a cross-tenant fixture (workspace B rows present) so the parity also covers the tenant boundary. Clamp and top-N are not re-run: parity plus the existing 177 cases cover them.
8. `test/rls-fuzz/rpc-cases.ts` (edit): add `get_egress_audit_window_summary` to `ATTACK_SQL` and keep the existing entry; see Phase 5.
9. `test/egress-audit-view.test.tsx` and the helpers test above must fail before Phase 2-4 and pass after.

### Phase 1 - Migration 183 (additive), down file, verify sentinel

Files: `supabase/migrations/183_egress_audit_window_summary.sql`, `183_egress_audit_window_summary.down.sql`, `supabase/verify/183_egress_audit_window_summary.sql`.

Re-verify the ordinal immediately before creating files: `git fetch origin main && git ls-tree --name-only origin/main apps/web-platform/supabase/migrations/ | sort | tail -3` (expect 182 as highest). Confirm the known-present `182_*` appears, so an empty result cannot read as clean.

`183_egress_audit_window_summary.sql` (header states the contract and why a second function; no argument defaults):

```sql
CREATE OR REPLACE FUNCTION public.get_egress_audit_window_summary(
  p_workspace_id uuid,
  p_limit        integer,
  p_decision     text,
  p_window       text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET plan_cache_mode = force_custom_plan
AS $$
DECLARE
  v_limit  integer;
  v_now    timestamptz := now();
  v_span   interval;
  v_lo     timestamptz;
  v_last   timestamptz;
  v_result jsonb;
BEGIN
  -- 1. membership (42501, constant message)   2. jti denylist (42501)   -- both byte-for-byte as in 177
  -- 3. p_decision (22023)   4. p_window (22023):
  v_span := CASE p_window
              WHEN '24h' THEN interval '24 hours'
              WHEN '7d'  THEN interval '7 days'
              WHEN '30d' THEN interval '30 days'
            END;
  IF v_span IS NULL THEN
    RAISE EXCEPTION 'egress audit: invalid window' USING ERRCODE = '22023';
  END IF;
  v_lo := v_now - v_span;
  -- remainder: the 177 body, unchanged (clamp, p_limit = 0 probe, w/g/s/r/o CTEs, jsonb result)
END;
$$;
```

then `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role;`, `GRANT EXECUTE ... TO authenticated;`, and a `COMMENT ON FUNCTION` that states "member-only, windowed (24h/7d/30d) summary", best-effort minimums, the straddle caveat, and the same no-function-level-timeout note. The header comment cross-references 177 for the parts that are identical and states that 177 and its function are untouched. Because `v_lo` is no longer a declaration initializer, the parity normalization (Guard 1) names exactly that difference.

`183_egress_audit_window_summary.down.sql`: `DROP FUNCTION IF EXISTS public.get_egress_audit_window_summary(uuid, integer, text, text);` only.

`verify/183_egress_audit_window_summary.sql`: the ten function rows of `verify/177` for the new signature plus a window row (`egress_window_summary_validates_window`: the live body carries the window check), eleven in all, with check names distinct from 177's (`egress_window_summary_*`) (definer, stable, search_path pinned incl. pg_temp, `plan_cache_mode=force_custom_plan`, body contains `is_jti_denied_from_jwt()`, anon / service_role / PUBLIC revoked, `authenticated` granted, grantee set is only `authenticated` plus owner). Existence of the new function is asserted with `to_regprocedure(...)` (a `::regprocedure` cast would raise instead of returning `bad = 1`). The 177 function's continued existence is already asserted by `verify/177`; the two table-level `egress_rollup_*` rows stay there too. Each row is a `pg_proc` / `has_function_privilege` predicate on the exact `regprocedure`, not just a check name (the 177 test already enforces predicate content; extend the same test pattern).

The header repeats the 177 `-- LAWFUL_BASIS: legitimate interests (Art. 6(1)(f))` line verbatim and adds that a shorter window is a narrower read of the same stored aggregates (gdpr-gate plan-time pass: one Suggestion, `GDPR-Art-6`, folded in here; no Critical or Important finding; no column, table, foreign key, vendor or retention change).

No grant to any table, no policy, no data change, no cron, no flag.

### Phase 2 - Client-safe types and helpers (`lib/egress-audit/summary.ts`)

Add, next to `DecisionFilter`: `export type TimeWindow = "24h" | "7d" | "30d"`; `TIME_WINDOWS` (ordered); `DEFAULT_TIME_WINDOW: TimeWindow = "30d"`; `parseTimeWindow(raw: string | string[] | undefined): TimeWindow` (same shape as `parseDecisionFilter`: first of an array, unknown or empty falls back to the default, never a 400); `WINDOW_LABEL` (`24 hours`, `7 days`, `30 days`) and `windowPhrase(w)` = `about the last ${label}`; the value is passed to the RPC as is (no mapping function). `EgressAuditPayload` is **not** changed (the new function returns the identical payload shape; Cut List). Name the parameter `timeWindow`, never `window` (shadows the browser global in client bundles).

### Phase 3 - Loader and page

- `server/egress-audit-read.ts`: `loadEgressAudit(supabase, userId, filter, timeWindow)` (required parameter so every caller is swept at compile time). The page call becomes `call(supabase, "get_egress_audit_window_summary", { p_workspace_id: ws, p_limit: PAGE_LIMIT, p_decision: toRpcDecision(filter), p_window: timeWindow }, PAGE_TIMEOUT_MS)`. No new op, no new message string, no fallback to the 177 function. `readHint` and `loadEgressCardState` are not touched. Update the file's header comment where it says "migration 177" for the page path.
- `page.tsx`: `searchParams: Promise<{ decision?: string | string[]; window?: string | string[] }>`; read it as `(await searchParams).window` (property access, no destructuring into a `window` binding); `const timeWindow = parseTimeWindow(...)`; pass to the loader and to `<EgressAuditView result filter timeWindow />`. Update the header comment ("the filter is the `?decision=` search param" gains the window).

### Phase 4 - View (`components/settings/egress-audit-view.tsx`)

Design source: the wireframes produced at plan time by the Product/UX Gate (see Domain Review). Behavior:

- Prop `timeWindow?: TimeWindow` on `EgressAuditView` (default `DEFAULT_TIME_WINDOW`, like the existing `now` default). The default-window view is NOT byte-identical to today in four strings, and this is a deliberate, CLO-reviewed copy change: the table caption gains "about" (`in about the last 30 days`), the filter-empty line becomes `No Blocked requests recorded in about the last 30 days.`, the web-off empty title becomes `Nothing recorded in about the last 30 days`, and the truncation body drops "30-day" (`Older entries in this window ...`). The existing assertions for those strings in `egress-audit-view.test.tsx` are updated in Phase 0.6; every OTHER existing assertion (Banner, retention, visibility, summary line, empty cards, subtitle) stays untouched and is the regression lock for the default window.
- `hrefFor(filter, timeWindow)` builds the canonical URL: `decision` omitted when `all`, `window` omitted when `30d`, order `decision` then `window`. Examples: `BASE`, `BASE?decision=blocked`, `BASE?window=7d`, `BASE?decision=blocked&window=7d`. The decision chips carry the current window; the window chips carry the current decision. The "Show all" link and the new "Show 30 days" link use the same builder (Show all drops only `decision`; Show 30 days drops only `window`).
- New `WindowChips` component: a muted visible `Time window` label plus `<nav aria-label="Time window">` of `NavLink`s (nav-pending channel, ADR-255; no bare `<a>`), `aria-current="page"` on the selected one, same visual treatment as the outcome chips, wraps on narrow widths. It renders **before** the outcome chips (same row on desktop, stacked above on mobile) and in every ready branch except `collection === false` and the unavailable branch (`collection === "unknown" || webAccess === null`), where there is no data to scope. It is not rendered for `forbidden`, `unbound`, `unavailable`.
- Window-aware strings (final copy; N = `WINDOW_LABEL`):

| Where | Copy |
|---|---|
| Header subtitle | `Sites {workspace's \| your workspace's} agents contacted in about the last N, with the outcome of each (best-effort).` |
| Table caption (sr-only) | `Hosts your workspace's agents contacted in about the last N, with outcome and a minimum request count` |
| Truncation body | `Older entries in this window are not listed, and counts are minimums.` |
| Filter-empty line | `No {Allowed\|Blocked\|Other} requests recorded in about the last N.` (CLO-required "recorded") |
| Web access off, no rows, title | `Nothing recorded in about the last N` (body unchanged) |
| Shorter-window empty (24h and 7d only; recording on, web access on, no rows) | title `No requests recorded in about the last N`; body `Nothing was recorded in this window. This list is best-effort, so this does not show that no requests were made. Requests can take some time to appear. A longer window may show more.`; actions: `Refresh` button and a `Show 30 days` link |
| 30-day empty (recording on, web access on, no rows) | unchanged: `No requests recorded yet` / `Nothing has been recorded yet. Requests can take a few minutes to appear.` |

- **Byte-identical, asserted by exact text under all three windows:** the `Banner` (`A best-effort summary, not a full record.` / `Some requests may be missing and counts are minimums. Every current member of this workspace can see this list, including activity from before they joined. No member or session is recorded. Records are deleted about 30 days after they were recorded.`), the `Web access is off. Nothing new is recorded.` / `Records are deleted about 30 days after they were recorded.` notice, the web-off empty body, the `Recording isn't on for this workspace.` card, the summary line (`at least N requests · at least M blocked`, `(all outcomes)` when filtered), the footer, the unavailable/forbidden/unbound cards. The Banner renders above every window state including the shorter-window empty state.
- A non-canonical inbound URL (`?window=30d`, `?decision=all`) renders correctly and is not redirected to the canonical form; accepted (links the page emits are canonical).
- No finer last-seen precision than today (`formatAgo` unchanged; no `<time dateTime>`; DPIA C7 and the CLO timing-linkability note).
- Header comment of the component keeps the copy rules; add one line: "window-scoped copy is derived from the selected window; the retention and visibility sentences are never windowed."
- Wording bans (assert in tests over the rendered text of every state x window): no `exactly`, `complete`, `guarantee`, `we block`, `prevent`, `protect`, `every connection`, `tamper-proof`, `sessions`.

### Phase 5 - Harness registration (gates)

- `test/rls-fuzz/rpc-cases.ts`: `ATTACK_SQL.get_egress_audit_window_summary = (c) => \`select get_egress_audit_window_summary('${c.wsA}', 200, null, '30d')\`` with a comment pointing at migration 183. The existing `get_egress_audit_summary` entry stays. `CLASSIFIED_DEFINER_FN_NAMES` picks up the new name automatically, which is what lets `test/migration-rpc-grants.test.ts` bless the new grant (run it).
- `test/rls-fuzz/targets.ts`: extend the rollup-table prose note: members read only through `get_egress_audit_summary` (mig 177) and `get_egress_audit_window_summary` (mig 183); still no member SELECT policy, still an excluded zero-policy target.
- Confirm AC8's expectations without a live database where possible: a default-suite assertion (in the 183 test) that `Object.keys(ATTACK_SQL)` contains both names and that neither name is a prefix-collision of the other in the static grants lint's extraction (anchor on `CREATE ... FUNCTION`).
- The live-DB fuzz suites cannot be validated by plain vitest; run them against the **local** database only (`RLS_FUZZ_LOCAL=1`, local DSN); never against production.

### Phase 6 - Docs: ADR amendment, C4, runbook

- ADR-288 amendment via `soleur:architecture` (content above, including the retirement path and the back-pointer added to the 2026-10-26 amendment). No edit to the Status paragraph other than leaving it Adopting.
- `knowledge-base/engineering/architecture/diagrams/model.c4`: edit the `webapp -> supabase` edge text ("... best-effort minimum counts over a fixed 30-day window" and "the Scope Grants audit page and card call the get_egress_audit_summary RPC") to the windowed wording that names both functions; name both functions in the `hetzner -> platform.webapp` edge and the comment above it. Run `bash scripts/regenerate-c4-model.sh`, commit the regenerated `model.likec4.json`, run the three C4 tests.
- `knowledge-base/engineering/operations/runbooks/egress-audit-enable.md`: in the paged-fault triage, name both functions: the page reads `get_egress_audit_window_summary`, the card reads `get_egress_audit_summary`; add the lost-grant query for the new signature; add a rollback-order line (the down migration must not run while an image that calls the new function is live: roll the app back first; a host still on the previous image keeps calling the 177 function and is safe throughout a multi-host rollout); add "every page load faults with `pg_code=PGRST202` right after a deploy: the new function is not in PostgREST's schema cache yet (migration applied but cache not reloaded); the card still works because it uses the 177 function". Do not describe the feature as live.
- `apps/web-platform/server/dsar-export-allowlist.ts`: comment only (the egress-audit entry says members read "through get_egress_audit_summary"); name both functions. `dsar-allowlist-completeness.test.ts` must stay green.
- `apps/web-platform/test/feature-map.md`: the egress audit route entry says "expects: last 30 days of agent outbound hosts"; update to name the window selector (default 30 days).
- Not touched: `docs/legal`, `plugins/soleur/docs`, the DPIA addendum, `knowledge-base/legal/article-30-register.md` (its recipients row names only the 177 function and its pre-selector window; carried to the flag-on legal sign-off with the DPIA row, decision-challenges row 8), privacy/GDPR pages, any `.github` file, any `scripts/` file, any feature-flag file.

### Phase 7 - Legal wording re-check and local validation

- Run `soleur:legal:clo` (prepare-and-review) on the **implemented** diff's user-visible strings; the plan-time pass on the drafted strings returned PASS-WITH-CHANGES and both required changes are folded into the table above. Record the work-time verdict in the PR body reminder (no sign-off claim; flag-on sign-off stays with the operator).
- Local validation, in order: `cd apps/web-platform && npx vitest run test/supabase-migrations/183-egress-audit-window-summary.test.ts test/supabase-migrations/177-egress-audit-summary-rpc.test.ts test/egress-audit-*.test.* test/migration-rpc-grants.test.ts test/sentry-egress-audit-read-alert-op-contract.test.ts test/scope-grants-page-egress-wiring.test.ts test/web-egress-toggle.test.tsx` then `npx tsc --noEmit` then the C4 tests. If a local Supabase is available, apply 183 to the LOCAL database first and then run the live suites with `RLS_FUZZ_LOCAL=1` against the local DSN (AC8's `stale` check reds if `ATTACK_SQL` names a function the local catalog does not yet have). The agent never applies migrations or runs psql against production; the release `migrate` job applies 183 on merge.

## Commit and review ordering

One PR, commits ordered so a reviewer can read the SQL first: (1) migration 183 + down + verify + 183 shape/parity test + denial-prefix test + `rpc-cases`/`targets` registration + ADR amendment (the function is unused until the app lands); (2) helpers, loader, page, view and their tests; (3) C4, runbook, DSAR comment, feature map, wireframes. The PR body includes `diff` of the 177 and 183 function bodies so the 150-line copy reads as the ~20-line window change it is.

## Files to Create

- `apps/web-platform/supabase/migrations/183_egress_audit_window_summary.sql`
- `apps/web-platform/supabase/migrations/183_egress_audit_window_summary.down.sql`
- `apps/web-platform/supabase/verify/183_egress_audit_window_summary.sql`
- `apps/web-platform/test/supabase-migrations/183-egress-audit-window-summary.test.ts`

(The wireframe frames are added to the existing `knowledge-base/product/design/settings/egress-audit-log.pen` by the Product/UX Gate at plan time; no new component file.)

## Files to Edit

- `apps/web-platform/lib/egress-audit/summary.ts`
- `apps/web-platform/server/egress-audit-read.ts`
- `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page.tsx`
- `apps/web-platform/components/settings/egress-audit-view.tsx`
- `apps/web-platform/test/egress-audit-view.test.tsx`
- `apps/web-platform/test/egress-audit-page-wiring.test.ts`
- `apps/web-platform/test/egress-audit-read-loader.test.ts`
- `apps/web-platform/test/egress-audit-summary-helpers.test.ts`
- `apps/web-platform/test/egress-audit-rpc-denial-prefix.test.ts`
- `apps/web-platform/test/rls-fuzz/rpc-cases.ts`
- `apps/web-platform/test/rls-fuzz/targets.ts`
- `apps/web-platform/test/rls-fuzz/egress-audit-rollup.integration.test.ts`
- `apps/web-platform/server/dsar-export-allowlist.ts` (comment only)
- `apps/web-platform/test/feature-map.md`
- `knowledge-base/engineering/architecture/decisions/ADR-288-aggregated-egress-audit-spool-via-vector-to-app-ingest.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)
- `knowledge-base/engineering/operations/runbooks/egress-audit-enable.md`
- `knowledge-base/product/design/settings/egress-audit-log.pen` and the exported frames under `knowledge-base/product/design/settings/screenshots/` (produced at plan time by the Product/UX Gate)

Explicitly NOT edited: migration 177 and its down file, `verify/177_*.sql`, `177-egress-audit-summary-rpc.test.ts`, `web-egress-toggle.tsx`, `scope-grants/page.tsx`, `egress-audit-refresh-button.tsx` (the refresh keeps the URL), `egress-audit-collection.ts`, any flag file, `docs/legal`, `plugins/soleur/docs`.

## Open Code-Review Overlap

None. Queried open `code-review` issues for every planned path (view, loader, summary, page, rpc-cases, targets, integration test, verify, migration 177, model.c4, ADR-288, refresh button, runbook): no matches.

## Acceptance Criteria

Pre-merge (PR):

- [ ] **AC1 Window is server-side.** `get_egress_audit_window_summary` exists with the four named parameters and no defaults; for a seeded fixture `24h` < `7d` < `30d` row sets match the inclusion table in Phase 0 item 7 (live suite) and the page makes exactly one RPC call per load with `p_window` set.
- [ ] **AC2 Authz order.** Membership first, jti second, then `p_decision`, then `p_window` (22023, message starts with `egress audit: `); NULL and unknown windows raise 22023; a non-member with an invalid window gets the membership 42501. Asserted by the 183 shape test (text) and the live suite.
- [ ] **AC3 Tenant boundary.** Every read of `workspace_egress_audit_rollup` carries `workspace_id = p_workspace_id`; the new function is classified in `ATTACK_SQL` and `migration-rpc-grants.test.ts` is green; live cross-tenant case passes for each window.
- [ ] **AC4 Grants.** REVOKE from PUBLIC, anon, authenticated, service_role; GRANT to `authenticated` only; the eleven `verify/183` rows all return `bad = 0` locally; 177 function and its `verify/177` rows unchanged and still green.
- [ ] **AC5 Parity.** Guard 1 passes: the 183 body equals the 177 body modulo the named window-derivation lines; live check: `window_summary(..., '30d')` equals `get_egress_audit_summary(...)` as jsonb on the fixture.
- [ ] **AC6 Copy.** For each of the three windows, the Banner, web-off notice body, web-off empty body, `Recording isn't on...` card and summary line match their exact current text (retention and visibility sentences byte-identical); window-scoped strings match the table in Phase 4; Guard 2 sweep finds no unlisted `30` in rendered text for `24h` and `7d`; no banned word appears in any state x window.
- [ ] **AC7 Default and URL.** No parameter, `?window=30d`, an unknown value and a repeated value all render the 30-day view; links are canonical (default omitted); decision chips keep the window, window chips keep the decision, `Show all` keeps the window, `Show 30 days` keeps the decision.
- [ ] **AC8 Ruling 1 guard.** The Scope Grants card path still calls `get_egress_audit_summary` with exactly `{ p_workspace_id, p_limit: 0, p_decision: null }`; `scope-grants/page.tsx` is not in the diff.
- [ ] **AC9 Holds.** The diff contains no feature-flag file, no flag-state change, no `docs/legal` / `plugins/soleur/docs` / DPIA / `.github` / `scripts` path, no edit to migration 177 or its down file; `git grep` of the PR diff for the enablement issue's number returns nothing; no closing keyword in any commit or PR text.
- [ ] **AC10 Down file.** `183_*.down.sql` drops only `public.get_egress_audit_window_summary(uuid, integer, text, text)`.
- [ ] **AC11 Denial prefix.** `egress-audit-rpc-denial-prefix.test.ts` covers both migrations and each has a non-vacuous floor.
- [ ] **AC12 Docs.** ADR-288 carries the 2026-11-03 amendment (status still Adopting); `model.c4` edge text and regenerated `model.likec4.json` agree; the three C4 tests are green; the runbook names both functions and the PGRST202 skew line.
- [ ] **AC13 Typecheck and suites.** `tsc --noEmit` clean; the vitest command in Phase 7 green; the Sentry alert op-contract test unchanged and green.
- [ ] **AC14 CLO.** Work-time `soleur:legal:clo` pass on the implemented strings returns PASS or PASS-WITH-CHANGES with changes applied; the PR body states legal wording sign-off at flag-on stays with the operator.
- [ ] **AC15 PR text.** Body contains `Ref #11238` and `Ref #9601` only (no closing keyword); no "live", "protects", "prevents", "blocks" or guarantee wording; it says the view is dark and collection is off.

Post-merge:

- [ ] The release workflow's `migrate` job applies 183 (normal path; nothing is run by hand). Verification is read-only: the `run-verify.sh` step of that job passes with the `verify/183` rows.

## Test Scenarios

Default suite (fast, no database): 183 shape + parity, denial-prefix, helpers, loader (argument names, card probe unchanged, skew, 22023), page wiring, view state ladder x window, grants lint with the new classification. Live-DB suite (gated, local only): window inclusion, order oracle, cross-tenant, grants, live parity, clamp/top-N reruns. No browser e2e: the page is server-rendered links; the render sweep covers the states. Test pyramid: unit-heavy by design, one gated integration layer, zero e2e.

Edge cases worth naming: `window=24h&decision=blocked` with no blocked rows but total > 0 (filter-empty line, window-aware); `24h` with no rows while `30d` has rows (shorter-window empty with `Show 30 days`); `30d` with no rows (existing empty states, no `Show 30 days` link); web access off with `7d`; truncation notice at `24h`; `?window=7d&window=24h` (first wins, as for `decision`); a bucket whose `first_seen` is before the window start but `last_seen` inside it (counted whole, accepted); Back/forward between windows (server navigation, `no-store`, no stale state).

## Domain Review

**Domains relevant:** Product, Engineering, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO agent rulings 1-4 (brief) and 5-7 (planning-time forks) recorded in `decision-challenges.md`: server-side window; additive migration 183 as a distinct-named function; duplicate body with a parity guard; loader always calls the new function with no silent fallback. Architecture-wise the change is an extension of ADR-288's read path, captured as an amendment.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Plan-time prepare-and-review on the drafted strings: PASS-WITH-CHANGES. Required changes adopted (filter-empty line says "recorded"; shorter-window empty body states the list is best-effort and does not show that no requests were made; "some time" instead of "a few minutes" there). Retention and visibility copy unchanged; a shorter window is a narrower read of the same stored rows, so the DPIA screening conclusions and the purge posture are unaffected; the server allowlist caps the window at 30 days (a longer window would be a widening trigger); no finer last-seen precision in the shorter windows. One CLO suggestion is **not** applied here because ruling 3 forbids DPIA edits in this PR: the DPIA addendum's section 12.1 "Window" row ("no time-range selector, no 24-hour count") becomes stale when this ships. It is recorded in `decision-challenges.md` row 8 for the flag-on legal sign-off, which stays with the operator.

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface override: `components/settings/egress-audit-view.tsx` is in Files to Edit)
**Decision:** reviewed
**Agents invoked:** soleur:product:spec-flow-analyzer, soleur:product:cpo, soleur:product:design:ux-design-lead
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

- **spec-flow:** gaps adopted: window-parametrize all five 30-day strings (Guard 2); window control present in every ready branch with data context; `Show all` / chips must carry the other parameter; canonical URLs (defaults omitted); shorter-window empty state must not be a dead end (link to 30 days, no second probe); retention sentence never interpolated; truncation copy window-aware; nav-pending for window links (NavLink); migration-first ordering and PGRST202 skew tagged. Gap 14 (window label in the summary line) considered and not adopted: the subtitle directly above and the selected chip already state the window, and the summary line is a CLO-reviewed string.
- **CPO (advisory):** acceptable to ship (cheap, explicitly filed, view dark); keep the card count deferred; chips preserve the other parameter; the 30-day empty state must not offer a "Show 30 days" dead end (it does not); say what an absent or invalid parameter falls back to (30 days, AC7); mark the active chip with `aria-current`; two chip rows wrap on mobile; keep the best-effort banner adjacent to the empty state.
- **ux-design-lead:** four frames added to the existing `knowledge-base/product/design/settings/egress-audit-log.pen` (non-empty, modified in this branch) and exported under `knowledge-base/product/design/settings/screenshots/`: `07-26-destination-populated-7-day-window-desktop.png`, `07-27-destination-truncated-7-day-window-desktop.png`, `07-28-destination-empty-24-hour-window-desktop.png`, `07-29-destination-24-hour-window-mobile.png`. Wireframes ready for async review (headless: no pause). Design decisions the implementer follows: a muted visible label `Time window` sits to the left of the three bordered chips (the `nav` also carries `aria-label="Time window"`), the selected chip is gold-bordered like the outcome chips, on desktop the `Time window` group and the outcome chips share one row (window group first, about 24px apart in the 760px column), and on mobile they stack with the window group above (the label sits above its chips); the outcome chips are hidden in the shorter-window empty state (as in the existing empty frames) while the window group stays; the empty-window card shows `Refresh` and a gold `Show 30 days` link side by side, the banner stays above every state.
- **Wireframe vs code copy.** The frames render the banner retention sentence as "Records are kept for about 30 days, then deleted.", which is NOT the shipped string. The wireframes are layout references only; the shipped Banner stays byte-identical to the current component text ("Records are deleted about 30 days after they were recorded."), asserted by the tests under all windows. The frames are not to be treated as copy sources, and the mismatch is not a reason to change the component. Two older frames in the same file (the filtered-empty desktop and mobile frames) still show the pre-change line "No Blocked requests in the last 30 days."; they are superseded by the table in Phase 4, and the layout reference for the new line is the populated frames.

## Observability

```yaml
liveness_signal:
  what: Existing Sentry events tagged feature:egress-audit-read with ops rpc_error, rpc_timeout, workspace_read_error (paged) - the page now reaches them through the new function; no new op, no new message string
  cadence: on every page load (event-driven; silence is the healthy state because the view is dark and collection is off)
  alert_target: the existing Sentry issue-alert rule for feature:egress-audit-read paged ops (apps/web-platform/infra/sentry/issue-alerts.tf, contract test sentry-egress-audit-read-alert-op-contract.test.ts)
  configured_in: apps/web-platform/server/egress-audit-read.ts (fault/warn emitters) and apps/web-platform/infra/sentry/issue-alerts.tf
error_reporting:
  destination: Sentry via reportSilentFallback (fault) and mirrorWarnWithDebounce (warn); low-cardinality pg_code tag
  fail_loud: yes - every RPC error renders the unavailable state and is mirrored; there is no fallback to the 177 function
failure_modes:
  - mode: new function missing or not in PostgREST's schema cache (migration not applied yet, or cache reload lagging)
    detection: rpc_error event with pg_code=PGRST202 on the page path while the card (177 function) keeps working
    alert_route: existing paged rpc_error rule (observability layer 2, the pino-to-Sentry mirror via reportSilentFallback; Sentry issue-alert egress-audit-read-failure)
  - mode: window rejected by the function (22023) - only reachable if the allowlist in TypeScript and SQL drift
    detection: rpc_error with pg_code=22023; the loader test pins the three values, the 183 test pins the CASE map
    alert_route: existing paged rpc_error rule (observability layer 2, the pino-to-Sentry mirror via reportSilentFallback; Sentry issue-alert egress-audit-read-failure)
  - mode: lost EXECUTE grant on the new function
    detection: rpc_error with pg_code=42501 and a message without the egress audit prefix (not treated as forbidden); verify/183 fails the deploy first
    alert_route: existing paged rpc_error rule (observability layer 2, the pino-to-Sentry mirror via reportSilentFallback; Sentry issue-alert egress-audit-read-failure); runbook query for the new signature
  - mode: slow or timing-out aggregate on a large workspace
    detection: rpc_timeout (8 s page bound); shorter windows read fewer rows than 30 days
    alert_route: existing paged rpc_timeout rule (observability layer 2, the pino-to-Sentry mirror via reportSilentFallback; Sentry issue-alert egress-audit-read-failure)
logs:
  where: Sentry (events above); Postgres function has no logging
  retention: Sentry project retention
discoverability_test:
  command: grep -c '"get_egress_audit_window_summary"' apps/web-platform/server/egress-audit-read.ts
  expected_output: 1
  # Holds once Phase 3 lands (0 on the pre-implementation tree). It proves the page path is wired to the new
  # function and, with the unchanged loader test, that the card path is not; the runtime signal is the Sentry
  # events named in liveness_signal.
```

## Encryption Posture

No new persistent store and no new cross-component connection: the new function reads the existing `workspace_egress_audit_rollup` table in the existing Supabase project and is reached over the existing web-platform to Supabase PostgREST connection. Both are already declared in the ledger (`scripts/encryption-posture-ledger.json`: store `supabase.prd`; connection `web-platform server -> Supabase Postgres/PostgREST`). The migration path pattern triggers this section, so the posture is stated by reference rather than re-declared:

```yaml
at_rest:
  - store: supabase.prd (existing ledger entry; the rollup table is unchanged)
    mechanism: provider-managed:supabase-postgres-aes256
    evidence: existing ledger entry for supabase.prd (Supabase security documentation, retrieved 2026-07-24); this change adds a function, not a store
    defends_against: physical-media compromise of the managed Postgres storage
    does_not_defend: a leaked service-role key, an RLS bypass, or any query through a legitimate connection; the key is provider-managed; the new definer function is itself an RLS-bypass surface and relies on its in-body membership check
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:named SOC 2 attestation formalization pending (tracked in the existing ledger entry)
in_transit:
  - connection: web-platform server -> Supabase Postgres/PostgREST (existing ledger entry)
    enforced_at: existing ledger entry (no connecting code changes in this plan)
    tls: unchanged from the existing entry
    cert_verification: unchanged from the existing entry
    does_not_defend: a compromised server process holding the caller's cookie client can call the function as that member
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 - Body parity between the 177 function and the 183 function

**Property.** The windowed function computes the same payload as the 177 function for the same window, because its body differs from the 177 body only in the lines that derive the window.

**Assembly.** The two function bodies, each extracted by anchoring on `CREATE OR REPLACE FUNCTION public.<name>(` through the matching `$$;` terminator (never by bare function name, which also matches REVOKE, GRANT and COMMENT lines); comments stripped, whitespace collapsed AND spacing around punctuation normalized (so a reflowed `(\n x` equals `(x`); the normalization is an explicit list of exact, line-level substitutions (never a dropped DECLARE block, which would stop checking `v_limit`, `v_now`, `v_last`, `v_result`): (a) the signature and parameter list, (b) the single declaration line `v_lo timestamptz := now() - interval '30 days';` in 177 versus the two lines declaring `v_span interval;` and `v_lo timestamptz;` in 183, (c) the `p_window` CASE and `22023` block (present only in 183), (d) the `v_lo := v_now - v_span;` assignment (present only in 183). Nothing else may differ. The chokepoint is the extraction function in the test; both bodies must flow through it, and the test asserts both extracted bodies are non-empty and exceed a floor of statements so a failed extraction cannot compare two empty strings.

**Mutation matrix.**

| # | Edit (MUST drive the guard RED) | Targets |
|---|---|---|
| 1 | In the 183 file, drop `AND t.last_seen <= v_now` from one read (the `w` CTE; then repeat for the probe's outer query) | a predicate dropped from the new body - a second member after a compliant first |
| 2 | In the 183 file, remove one `workspace_id = p_workspace_id` predicate (the `w` CTE, the probe's outer query, or the probe's inner subquery - the three table reads; the `g`/`s`/`r`/`o` CTEs read `w`/`g`, not the table) | tenant boundary; also red in the exact-count assertion of the shape test |
| 3 | Make the extractor return `""` for the 177 file (a fixture that renames the function) | the guard's own dispatch: must fail on the non-empty floor, never pass on two empty strings |
| 4 | Move the `p_window` CASE block (unchanged) above the jti statement | order/lifetime: a REORDER row, not a delete row; deleting the block reds any suite, while moving it reds only a suite that asserts the position (the shape test's `p_window` not referenced before the jti statement ends) |
| 5 | Harness row: replace the normalization with the identity function | the suite itself: with no normalization the legitimate window-derivation difference makes the guard fail, proving it compares (the Guard Contract requires one harness row; the others a first draft carried were cut as redundant) |
| 6 | Must-PASS non-canonical input: the 183 body with extra comments and reflowed whitespace | a differing-but-permitted input still passes (the guard is not a byte equality) |

**Anchor.** The guard compares two files that one diff could edit together. The 177 file is protected independently by the dev-ledger byte-identity check (CI), so a weakening of both in one PR is caught outside this test; the live parity check in the gated suite compares behavior, not text.

### Guard 2 - No stale 30-day window copy in the view

**Property.** Every window-scoped sentence the view renders is derived from the selected window; the only places the number 30 appears in rendered text are the allowlisted retention sentences, the `30 days` chip and the `Show 30 days` link.

**Assembly.** The rendered text (not the source) of `EgressAuditView` for the full state ladder (forbidden, unbound, unavailable, ready with rows, ready with truncation, ready filter-empty, ready web-off with rows, ready web-off empty, ready collection-off, ready collection-unknown, ready shorter-window empty, ready 30-day empty) crossed with the three windows (the decision filter is not an axis: it does not touch window-scoped copy). The chokepoint is a single test helper that renders every cell of that cross product and returns the text; the allowlist is a closed list of exact sentences. The "no stray 30" scan runs on the `24h` and `7d` cells.

**Mutation matrix.**

| # | Edit (MUST drive the guard RED) | Targets |
|---|---|---|
| 1 | Hard-code `in the last 30 days` back into the table caption | one of five known sites |
| 2 | Hard-code `30 days` in the truncation body while the other four stay windowed | a second site after a compliant first |
| 3 | Make the helper render only the `24h` window (drop `7d`) | the guard's own dispatch: a cross-product floor (3 windows x ladder size) must fail the suite |
| 4 | Interpolate the window into a retention sentence (`Records are deleted about 7 days after`) | retention drift: exact-text assertions on the Banner under all windows |
| 5 | Harness row: empty the allowlist | the suite must go RED on the legitimate retention sentences, proving the allowlist is load-bearing |
| 6 | Must-PASS non-canonical input: render with a workspace name containing the digits `30` | a permitted variation must not trip the scan (strip the workspace name before scanning) |

**Anchor.** The allowlist lives in the test; changing a retention sentence in the component without changing the test fails the exact-text assertions, and changing both is visible in one diff reviewed by the CLO pass (AC14).

## Sharp Edges

- **Never name a variable `window`** in the view, page or helpers: it shadows the browser global in client bundles and `tsc` may not flag it. Use `timeWindow`. Read the query value as `(await searchParams).window`.
- **Do not add `DEFAULT` to any parameter of the new function.** Ruling 2 forbids it, and it keeps the PostgREST resolution unambiguous even though the name is now distinct. The loader test pins the four named arguments (a mismatch is a silent PGRST202 that `tsc` cannot see).
- **Do not edit migration 177, `verify/177`, or the 177 test.** Even a comment edit fails the dev-ledger byte-identity check. The parity guard reads 177 as the oracle.
- **The 15-minute bucket slack is a scan aid, not a filter.** The `last_seen >= v_lo` predicate decides inclusion; a bucket that began before the window start but has a `last_seen` inside it is counted whole. This is why every window phrase says "about the last N" and why no string may say "exactly". The live suite documents it as accepted behavior.
- **`now()` is the transaction start.** The live parity check can compare the two functions' full jsonb including `window` because both read the same `now()` inside one rolled-back transaction; do not call `clock_timestamp()`.
- **Do not weaken the Scope Grants hot path.** `loadEgressCardState` and `readHint` must keep calling the 3-argument function with `p_limit: 0`. AC8 pins the exact argument object.
- **The enablement issue's number must not appear anywhere in the diff**, including ADR text copied from the existing amendment (do not copy its "enablement blockers" sentence; write the new amendment without that reference), the runbook edit, test comments and commit messages. Run the AC9 grep before each commit.
- **No closing keyword** (`Closes`, `Fixes`, `Resolves`) in any commit or PR text: the issue stays open for the card count.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6.** It is filled here (threshold `single-user incident`).
- **Never run migrations, `psql` or the live fuzz suites against production.** Local database only; the release `migrate` job applies 183 on merge.
- **Re-verify the migration ordinal at ship**, after every sync with `origin/main`; if 183 is taken, renumber the three SQL files, the test file name, the references in the ADR amendment and this plan's artifacts (`grep -rn '183' knowledge-base/project/{plans,specs}/feat-one-shot-11238-egress-audit-time-window/`).

## Review residuals accepted (2026-11-03, review pass on #11238)

- **Router Cache.** `next.config.ts` sets `staleTimes.dynamic: 30`, so each of the three `?window=` URLs is its own client Router Cache entry and a revisit inside 30 s can show a list up to 30 s old, including for a member removed in that interval. This is the existing ADR-067 invariant for every dynamic settings page, the view is dark, and `force-dynamic` plus `no-store` cover document navigations only. Accepted; not a new exposure class.
- **Future-dated buckets are excluded.** `last_seen <= now()` (copied from 177) drops rows whose `last_seen` is ahead of the database clock, so an ingest clock running ahead undercounts the freshest rows. This falls under the existing "counts are minimums" copy.
- **Schema-cache reload.** Migration 183 contains no `NOTIFY pgrst`; `run-migrations.sh` requests a PostgREST schema-cache reload after each run (best-effort). Until it lands, the page shows the paged `rpc_error` with `pg_code=PGRST202` and the card keeps working (runbook step 5).
- **"Blocked" is a recorded outcome, not a protection claim.** The label is the stored `denied` value renamed. Before flag-on, confirm with the operator's legal sign-off that `denied` means the proxy refused the request; this PR makes no protection claim and the plan's copy bans stay in force.
- **Not adopted.** The screen-reader summary line stays window-free: it is a CLO-reviewed string and the selected chip and subtitle name the window. A live-state parity check (a later migration redefining either function) is outside the default suite; migration immutability and the reader-set test cover the file-level cases.

> **Superseded 2026-11-03 (ship, #11238):** the comment-only edit to `apps/web-platform/server/dsar-export-allowlist.ts` listed above was dropped. Any edit to that file, a comment included, makes the legal-doc cross-document gate (`enforce`) require updates to four privacy and legal documents, and this change updates none. The file is unchanged from main; the egress-audit entry keeps its existing wording.
