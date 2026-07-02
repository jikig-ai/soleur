---
plan: domain-model-register-gates
issue: 5871
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-02-domain-model-register-gates-brainstorm.md
spec: knowledge-base/project/specs/feat-domain-model-register-gates/spec.md
branch: feat-domain-model-register-gates
pr: 5895
created: 2026-07-02
---

# Plan: Mechanical enforcement gates for the domain-model register (#5871)

## Overview

Make the domain-model register's maintenance contract mechanically enforced. The register
(`knowledge-base/engineering/architecture/domain-model.md`) is a **curated** subset of core
entities + ~11 business rules; #5754 shipped the deterministic analyzer
(`scripts/domain-model-drift.sh`) that drift-checks it. This plan wires the three fast-follow
gates named in the register's contract and tracked in #5871 — but the design shifted after
plan-time verification of the analyzer against live repo state (see Research Reconciliation).

**Chosen shape** (revised after plan-review — DHH + code-simplicity both cut the advisory-first
apparatus and the plan-time reminder as ceremony/theatre):
1. **Analyzer anchor fix** (enforces ADR-076 item 3): strip the `public.` default-schema
   qualifier so anchors are `<table>.<object>`, not the corrupt `public.<table>.public.<object>`.
2. **One blocking gate** at preflight (`Check 11`), keyed on **stale register citations**
   (high-signal, 0 on `main` today), diff-scoped. **Ships blocking directly** — stale=0 today means
   there is nothing to soak, so the advisory-first rollout + `REGISTER_DRIFT_BLOCKING` flag were cut;
   the residual citation-parser false-positive risk is handled by an actionable FAIL message, not a
   rollout flag.
3. **One advisory review note** — a single informational line surfacing the drift counts +
   `/soleur:sync domain-model` pointer (the undocumented-facts triage preflight does not cover).

Plan-time flagging (the third gate named in #5871) is **deliberately dropped** — no diff exists at
plan time, so it can only be an unenforced nudge (see Non-Goals NG1).

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified 2026-07-02) | Plan response |
|---|---|---|
| "Fix the `public` FP → `drift` exits 0 on clean main → gate can block on exit code" (spec FR2/TR4) | The `public` token is a **schema-qualifier mis-capture** in `name_after()` (`domain-model-lib.sh:63`) that **collapses ~50 public tables into one token**. Fixing it correctly *un-masks* dozens of genuinely-un-curated tables → `drift` **still exits 1** (undocumented-facts), because the register is a *curated subset*, not a full table catalog. | **Do NOT gate on the raw exit code / undocumented-facts count.** Gate on the **"Stale register citations (N)"** sub-count instead (N=0 today, unaffected by the schema bug). Undocumented-facts becomes advisory-only. |
| "#5882 backlog is the sequencing blocker" | #5882 is **CLOSED** (backlog drained). The blocker was the anchor bug + the wrong signal choice, not a backlog. | Backlog triage is **not** a prerequisite. Stale-only gate is clean on `main` now. |
| Guard surface glob `app/api|lib/(auth|byok|stripe|supabase)` (spec TR1) | The analyzer scans exactly: `apps/web-platform/supabase/migrations/*.sql` + the single file `apps/web-platform/server/workspace-resolver.ts` (`dm_guards_from_ts`). `app/api`/`lib/*` are not analyzer inputs. | Diff-scope trigger = migrations glob + `workspace-resolver.ts` + the register file itself. |
| "The `public` FP is cosmetic" (brainstorm) | It corrupts BOTH table and object segments (`public.X.public.X_pkey`), degrading the existing `/soleur:sync domain-model` write-row / Auto-inferred output. Violates ADR-076 item 3 (`<table>.<object>`). | Fix is a genuine correctness fix to the #5754 sync path; kept in-scope, Phase 1, severable if plan-review objects. |

## Implementation Phases

Phase order is load-bearing: the analyzer contract (Phase 1) ships before its consumers
(Phases 2–4). All phases land in one PR (#5895); ship is atomic.

### Phase 1 — Analyzer anchor fix (enforce ADR-076 item 3)
- **1.1** `scripts/lib/domain-model-lib.sh` `name_after()` bare-identifier branch (line 63): after
  extracting `tok`, `sub(/^public\./, "", tok)`. Strips the Postgres default schema only —
  `storage.objects` / `auth.users` (which the register cites *with* schema) are preserved; quoted
  policy names (line 62) are untouched. This corrects table tokens (`public.users`→`users`) and
  SECURITY-DEFINER function tokens (`public.resolve_x`→`resolve_x`, matching how the register cites
  `resolve_byok_key_owner`).
- **1.2** `scripts/domain-model-drift.test.sh`: add one additive test with a schema-qualified
  fixture (`CREATE POLICY p ON public.foo ...` + `ALTER TABLE public.foo ...`) asserting the emitted
  anchor is `... › foo.<object>` (no `public.` prefix, no double-dot), AND a `storage.objects`
  fixture asserting the `storage.` schema is preserved. Existing fixtures use bare table names, so
  no existing assertion changes.

### Phase 2 — Blocking ship gate: preflight `Check 11` (stale-citation gate)
- **2.1** `plugins/soleur/skills/preflight/SKILL.md`: add `### Check 11: Domain-Model Register Drift`
  after Check 10.
  - **Fast-path SKIP predicate** (against `"$PREFLIGHT_TMP/preflight-diff-files.txt"`, the cached
    diff SSOT from Step 0.1): SKIP unless the path-set matches
    `apps/web-platform/supabase/migrations/.*\.sql$` OR `apps/web-platform/server/workspace-resolver\.ts$`
    OR `knowledge-base/engineering/architecture/domain-model\.md$` (all three as explicit literals in
    the regex). Register-file inclusion is load-bearing: editing the register can itself introduce a
    stale citation.
  - **Fail-safe: never SKIP on an empty/missing cache (spec-flow #4).** If
    `"$PREFLIGHT_TMP/preflight-diff-files.txt"` is missing or zero-length (offline / no remote / Phase-0
    cache write failed), do NOT treat "no match → SKIP" — recompute inline
    (`git diff --name-only origin/main...HEAD`) and re-test; if that also yields nothing, **run** the
    check (fail-closed), do not SKIP. An empty path-set matching nothing would otherwise silently
    disable the gate.
  - **Runs pre-PR by design (spec-flow #2).** Unlike Check 6, Check 11's predicate reads the
    diff-set (`origin/main...HEAD`), which is PR-independent — so Check 11 RUNS against local commits
    even with no PR open. Do NOT "fix" it to SKIP-on-no-PR; that would fail it open.
  - **Run:** `bash scripts/domain-model-drift.sh drift --repo . --register knowledge-base/engineering/architecture/domain-model.md > "$PREFLIGHT_TMP/register-drift.txt"; rc=$?`.
  - **Parse the STALE sub-count** (not the exit code), **line-anchored** (Kieran MEDIUM): `stale=$(grep -oE '^## Stale register citations \([0-9]+\)' "$PREFLIGHT_TMP/register-drift.txt" | head -1 | grep -oE '[0-9]+')`. The `^` anchor is load-bearing: `emit_drift_report` prints per-fact predicate text pulled verbatim from migration SQL, so an *unanchored* grep could match a predicate line echoing the substring → a multiline capture that breaks the `[ "$stale" -gt 0 ]` numeric test. `^` + `head -1` guarantees a single number from the canonical column-0 header (`domain-model-drift.sh:175`).
  - **Verdict — ships blocking directly** (preflight vocabulary is PASS/FAIL/SKIP):
    - `rc==0` → PASS.
    - `stale>0` (parsed count) → **FAIL**. Actionable message (covers the non-technical operator +
      the documented citation-parser FP): "domain-model register has N stale citation(s): the register
      cites a file/symbol that no longer resolves. Fix: update the cited row(s), or run
      `/soleur:sync domain-model`. If a citation backticks a *filename* (e.g. `` `053_x.sql` ``), the
      parser can false-flag it — cite migrations as unbackticked prose (see
      `knowledge-base/project/learnings/best-practices/2026-07-01-domain-model-register-curation-citation-parser-and-grep-validation.md`)."
    - `rc==2` (analyzer error / unanalyzable source) → **FAIL**. Message: "register-drift check could
      not run (analyzer exit 2) — inspect `--repo`/jq/migrations dir; this is NOT a drift finding."
    - `rc==3` (secret-refuse) → **FAIL**. Message (spec-flow #7): "domain-model analyzer refused to
      emit: a secret-shaped substring was found in extracted structural text — likely a recently-changed
      migration column/value matching `sk_test`/`ghp_`/`AKIA…`/`-----BEGIN` (a benign column name can
      false-positive). Inspect the newest `apps/web-platform/supabase/migrations/*.sql`."
  - Note in the check body: the "Undocumented source facts (M)" count is **intentionally not a FAIL
    input** — for a curated register M is ~50 by-design omissions; it is surfaced only in the advisory
    review note.
  - Add the SKIP predicate row to the Fast-path SKIP overview table (line 44).
- **2.2** Ship inherits automatically: `ship/SKILL.md` Phase 5.4 already invokes preflight and halts
  on any FAIL. **No ship-skill edit.** (Confirmed: `ship/SKILL.md` Phase 5.4.)

### Phase 3 — Advisory review note (single informational line)
- **3.1** `plugins/soleur/skills/review/SKILL.md` Conditional-Agents block (after gdpr-gate, before
  the Anti-slop hook, ~line 267): add a conditional gate with the **same diff predicate** as Check 11.
  Runs `drift` and surfaces **one informational line** in the review summary reporting both counts +
  the pointer: "domain-model register: N stale citation(s), M undocumented table(s) — see
  `/soleur:sync domain-model`". Purely informational (no "must fix" / no blocking-coordination logic —
  preflight `Check 11` is the sole enforcement surface). Its non-redundant value is the
  **undocumented-facts** pointer, which the (stale-only) preflight gate never surfaces.

*(Plan-time reminder gate cut per plan-review — see Non-Goals NG1.)*

### Phase 4 — Contract prose + ADR/C4
- **4.1** `knowledge-base/engineering/architecture/domain-model.md` maintenance-contract prose: flip
  "**Fast-follow (not yet mechanically gated):** plan-time flagging, a review drift-check, and a ship
  block — tracked in #5871" → "**Wired:** the `architecture` ADR step; preflight `Check 11`
  (stale-citation ship block, diff-scoped); an advisory review note (drift counts +
  `/soleur:sync domain-model`). (Plan-time flagging intentionally not built — no diff at plan time; #5871.)"
- **4.2** Amend ADR-076 (`## Enforcement gates (2026-07-02, #5871)` section) — see Architecture
  Decision below.

## Files to Edit
- `scripts/lib/domain-model-lib.sh` (Phase 1.1 — 1-line schema strip)
- `scripts/domain-model-drift.test.sh` (Phase 1.2 — additive fixtures)
- `plugins/soleur/skills/preflight/SKILL.md` (Phase 2.1 — Check 11 + SKIP table row)
- `plugins/soleur/skills/review/SKILL.md` (Phase 3.1 — advisory review note)
- `knowledge-base/engineering/architecture/domain-model.md` (Phase 4.1 — contract prose)
- `knowledge-base/engineering/architecture/decisions/ADR-076-domain-model-drift-extraction.md` (Phase 4.2 — amendment)

*(`plugins/soleur/skills/plan/SKILL.md` removed from scope — plan-time reminder cut per plan-review.)*

## Files to Create
- None. (No new script, skill, agent, workflow, or `.pen`.)

## Acceptance Criteria

### Pre-merge (PR)
- **AC1:** `bash scripts/domain-model-drift.test.sh` passes, including a new schema-qualified fixture
  (`ON public.foo` → anchor `… › foo.<object>`, no `public.` / no double-dot) AND a `storage.objects`
  fixture asserting the `storage.` schema is **preserved**. (Absorbs the former standalone
  extract-grep check: the suite exercises both strip + preserve directions.)
- **AC2:** On this branch, `bash scripts/domain-model-drift.sh extract --repo . | jq -r '.facts[].anchor' | grep -c 'public\.'`
  returns `0`, and the `drift` report's `^## Stale register citations (N)` line reports **N=0**
  (stale-only gate is clean → this PR's own register edit does not introduce staleness).
- **AC3:** preflight `Check 11` SKIPs on a docs-only diff (synthesized path-set with no business-rule
  surface) and RUNS on a diff touching `apps/web-platform/supabase/migrations/*.sql`, the register
  file, or `workspace-resolver.ts` (verify each against a synthesized `preflight-diff-files.txt`); on
  an empty/missing cache it RUNS (does not SKIP).
- **AC4:** Check 11 keys on the **stale** count, not the raw exit code: a synthesized report with
  `Stale register citations (0)` + `Undocumented source facts (50 …)` yields **PASS** (never
  FAIL-for-undocumented); a report with `Stale register citations (1)` yields **FAIL** with the
  actionable message. Exit 2 and exit 3 each yield FAIL with their distinct messages.
- **AC5:** register maintenance-contract prose no longer says "not yet mechanically gated"; ADR-076
  carries the `## Enforcement gates (2026-07-02, #5871)` amendment.

## Domain Review

**Domains relevant:** Engineering (carry-forward from brainstorm).

### Engineering
**Status:** reviewed (brainstorm carry-forward — CTO)
**Assessment:** Build ONE diff-scoped gate at ship/preflight; reuse the drift call as an advisory
review note. Diff-scope the gate, not the analyzer. Complexity: small (wiring, not a new engine). No
capability gaps — all hook points exist. *Plan-time refinements beyond the brainstorm:* (a) gate on
the stale-citation sub-count (not raw exit / undocumented-facts), because the curated register makes
undocumented-facts a ~50-item by-design signal; (b) ship blocking directly + drop the plan-time gate
(plan-review consensus).

### Product/UX Gate
Not run — no UI surface. `## Files to Create` is empty; no `components/**`, `app/**/page.tsx`, or
`.pen` path. Mechanical UI-surface override did not fire. Tier: NONE.

**Other domains (Marketing, Operations, Sales, Finance, Support, Legal):** not relevant — internal
CI/workflow tooling with no user-facing surface, no user data path, no vendor/infra/legal dimension.

## User-Brand Impact

**If this lands broken, the user experiences:** a business-rule change (migration / RLS policy /
resolver-guard) ships with the register left silently stale, so a future engineer or auditor reading
the register trusts a wrong ownership/visibility/tenancy model.

**If this leaks, the user's data is exposed via:** an engineer acting on a stale register row makes a
wrong owner/visibility call in a later change → one user's data is disclosed or wrongly denied.

**Brand-survival threshold:** single-user incident.

*CPO sign-off:* carried from the brainstorm's always-on user-brand-critical framing (per #5175). The
threshold is precautionary (the register documents access-control-adjacent rules); the feature itself
processes **no** personal data — it reads migration DDL *structure*, never rows. `user-impact-reviewer`
runs at PR review as the load-bearing gate. *Note:* the register is best-effort structural extraction,
NOT a security audit (ADR-076 item 4); the gate enforces documentation coverage, not access-control
correctness.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-076** with a `## Enforcement gates (2026-07-02, #5871)` section recording:
- Gates key on the **stale-citation** sub-count (deterministic, high-signal), NOT the raw exit code —
  "undocumented source facts" is advisory-only because the register is a curated subset (blocking on
  it would demand documenting every table, contradicting item 5's curation-preserving intent).
- Single blocking chokepoint at preflight `Check 11` (ship inherits via its preflight Phase 5.4);
  the review note is advisory-only; plan-time flagging is not built (no diff at plan time). Diff-scoped
  at the gate (not the analyzer — no `--since` mode added, consistent with the bounded scope of item 4).
- Ships blocking directly (stale=0 on main; no advisory-first rollout apparatus).
- The `public.` schema-strip enforces item 3 (anchors are `<table>.<object>`).
New decision, not a deferred issue — the amendment ships in this PR.

### C4 views
**No C4 impact.** Checked all three model files (`model.c4` 332L, `views.c4`, `spec.c4`). Enumerated
for this feature: (a) external human actors — none (the gate acts on the internal developer/CI
workflow; no modeled actor like an end user or correspondent is introduced); (b) external systems /
vendors — none (the analyzer is a local bash script; no webhook/API/third-party store); (c) containers
/ data-stores — none (the register is a repo markdown file, a dev artifact outside the C4 runtime
boundary; no runtime container changes); (d) actor↔surface access relationships — none changed. The
feature is entirely dev/CI toolchain, which the C4 runtime model does not (and should not) contain.

## Observability
**Skip — justified.** No server/cron/Inngest/infra runtime surface. The gate is a synchronous
local preflight/review check; its `PASS`/`FAIL`/`SKIP` output is directly operator-visible in
preflight output. No Sentry/liveness/log-retention surface exists to declare (no code under
`apps/*/server`, `apps/*/infra`, or `plugins/*/scripts`; the edited `scripts/*.sh` analyzer is a
CLI invoked synchronously with its exit code as the signal).

## GDPR / Compliance
**Considered (single-user-incident threshold triggers review), nil surface.** The feature processes
**no personal data** — it reads migration DDL *structure* (table/policy/constraint names), never rows.
No new lawful basis, Art. 30 processing activity, special-category data, or data-movement surface. The
register *documents* GDPR-relevant rules (BR-BYOK-1 Art. 7, BR-DSAR-1 Art. 15/17) but the gate does not
touch those data flows. No `compliance/critical` finding.

## Open Code-Review Overlap
None (verified 2026-07-02). `gh issue list --label code-review --state open` → no open scope-out names
`domain-model-drift.sh`, `domain-model-lib.sh`, the register, ADR-076, or the preflight/review SKILL.md files.

## Non-Goals / Deferred
- **NG1 — Plan-time flagging (dropped, not deferred).** #5871 names three gates (plan-flag / review /
  ship); this plan builds two. A plan-time flag has no diff to inspect (plan runs on the feature
  *description*), so it can only be an unenforced prose nudge — both plan-review reviewers (DHH +
  code-simplicity) classified it as theatre. Dropped with rationale, not filed as a follow-up (there is
  no future trigger that makes it more enforceable). If a proactive nudge is ever wanted, it belongs in
  the brainstorm/plan authoring guidance, not as a "gate."
- **NG1b — No advisory-first rollout.** The stale-only signal is 0 on `main` today and diff-scoped, so
  `Check 11` ships **blocking directly** (no `REGISTER_DRIFT_BLOCKING` flag, no soak, no flip issue).
  The residual citation-parser false-positive risk is covered by the actionable `stale>0` FAIL message.
- **NG2 — Semantic drift on a documented entity (disclosed coverage gap).** A PR that edits an RLS
  *predicate* on an already-documented table without changing any cited filename/symbol leaves the
  register **statement** silently stale while the **citation** still resolves — the stale-citation
  gate does NOT catch this (nor does the advisory undocumented-facts signal). This is inherent to
  structural extraction (ADR-076 item 4). Disclosed, not fixed. The advisory review comment is the
  mitigation (it prompts a human to eyeball the register when a business-rule surface changes).
  Corollary (spec-flow #6): the analyzer only sees guards in `workspace-resolver.ts`
  (`dm_guards_from_ts` hardcodes it) — a business-rule guard added to any *other* server file is
  invisible to both signals. The Check 11 trigger is deliberately scoped to that one guard file (not a
  broad `server/**.ts`) so the gate never PASSes with false confidence over an un-analyzed guard.
- **NG3 — No diff-scoped drift mode in the analyzer** (no `--since`); diff-scoping stays at the gate.
- **NG4 — No hard CI job.** Enforcement lives in the ship pipeline (preflight), consistent with how
  other Soleur invariants (security headers, env isolation) gate. A GitHub Actions job would duplicate
  the preflight check.
- **NG5 — No auto-write to the curated register.** Row recording stays the human-in-loop
  `/soleur:sync domain-model` path (ADR-076 item 5).

## Risks & Mitigations
- **R1 — schema strip over-strips a legitimately `public`-named non-default-schema object.** Mitigated:
  strip is anchored `^public\.` (a *leading* default-schema qualifier), and the register cites the two
  non-default schemas it needs (`storage.`, `auth.`) which are preserved; test AC1/AC2 assert both
  directions.
- **R2 — advisory undocumented-facts list is noisy (~50 items).** Mitigated: advisory review surfaces
  a **count + pointer**, not the full list; the blocking gate ignores it entirely.
- **R3 — diff-scope trigger drifts from the analyzer's real inputs.** Mitigated: trigger derived
  directly from `dm_find_migrations_dir` + `dm_guards_from_ts` (single guard file) — TR pins them; if
  the analyzer later scans more TS, the trigger must be re-synced (noted in the Check 11 body).
- **R4 — `origin/main...HEAD` three-dot base shifts if `origin/main` advances mid-session
  (spec-flow #8).** Low-risk and inherent to preflight's diff model; the `drift` analyzer itself is
  deterministic (`LC_ALL=C` sorts, `head -1`). Disclosed; no code change. Re-running preflight after a
  rebase re-bases the diff-set, which is the desired behavior.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6.
  This plan's section is filled (threshold: single-user incident).
- The `public.` strip changes the `extract` JSON for many facts; the existing test suite is safe
  (fixtures are bare-named), but any future fixture that schema-qualifies must expect the stripped form.
- Check 11 parses the **stale** count via the line-anchored `grep -oE '^## Stale register citations \([0-9]+\)' | head -1`
  (Kieran MEDIUM) — the `^` prevents matching a verbatim-SQL predicate line that echoes the substring.
  This is an implementation-invariant signal (the header is emitted unconditionally by
  `emit_drift_report`), unlike the noisy undocumented count. Do not gate on the raw exit code.
- **Schema-fix bundling (DHH dissent, resolved).** DHH argued the 1-line `public.` strip should ship as
  its own PR (it's a #5754 analyzer fix, not a #5871 gate). Kept bundled because Phase 3's advisory
  review note reports the **undocumented-facts count**, which is garbage (`public`=1) until the strip
  lands — so the advisory surface built here depends on the fix for honest output. Shipped as the
  first, independently-committed phase; severable if a reviewer re-raises it.
