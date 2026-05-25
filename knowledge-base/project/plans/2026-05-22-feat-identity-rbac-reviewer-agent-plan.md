---
title: Identity/RBAC Reviewer Agent
issue: 4233
parent_issue: 4229
spec: knowledge-base/project/specs/feat-agent-identity-rbac-reviewer-4233/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-22-agent-identity-rbac-reviewer-brainstorm.md
branch: feat-agent-identity-rbac-reviewer-4233
pr: 4288
date: 2026-05-22
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: false
requires_cto_signoff: true
requires_clo_signoff: false
requires_adr: false
cpo_signoff_note: "Brainstorm-time CPO assessment was 'sign-off not required for the agent itself; threshold flows from purpose, not surface'. Per plan skill Step 2.6 step 3 option 2 ('confirm CPO has reviewed the brainstorm'), carry-forward attestation is the load-bearing artifact. user-impact-reviewer at PR-review time is the diff-level gate."
---

# Plan: Identity/RBAC Reviewer Agent

## Summary

Create one narrow-scope review agent for multi-org / workspace boundary integrity. Wire it into `/soleur:review` dispatch on identity-touching diffs. Update plugin manifest counts via `release-docs`.

`USER_BRAND_CRITICAL=true`. False-negative review on an identity-touching PR IS the brand-survival event (cross-tenant read, write under wrong workspace_id, stale-JWT privilege, JWT claim impersonation).

## Implementation Choice (re-eval at /work Phase 0)

Brainstorm chose **Approach A: new narrow agent**. DHH-style review challenged: if security-sentinel and identity-rbac-reviewer always fire on the same identity-touching PRs, that's duplication wearing two hats — **Approach B (section append to security-sentinel)** is functionally equivalent and cheaper (1 fewer dispatch entry, 1 fewer boundary paragraph, 1 fewer README row).

`/work` Phase 0 MUST re-evaluate before authoring:

1. Check `security-sentinel.md` description-line + body word budget. If a ~30-line "Multi-org / workspace boundary" subsection fits without violating `cq-skill-description-budget-headroom` or bloating the description, **Approach B is the right call**.
2. Check `/review/SKILL.md` Conditional Agents dispatch — security-sentinel currently fires unconditionally (line 64 Change Classification Gate; on every `code` class). Adding the new checks to security-sentinel makes them fire on every code PR (broad) vs. firing identity-rbac-reviewer on identity-touching diffs only (narrow). The narrow-firing argument favors Approach A.

If Approach B wins at /work: rewrite Phases 1-3 to "append section to security-sentinel.md" instead of "create new file + dispatch entry"; ACs 1-4 collapse to one "section exists with shape" check. If Approach A wins: proceed as drafted below.

**Falsifiability criterion (apply post-merge under either approach):** after 5 identity-touching PRs post-merge, audit whether the new identity findings were a strict subset of pre-existing security-sentinel findings on the same PRs. If yes, fold back. Track via a Phase 5 follow-up issue filed at ship time.

## Research Reconciliation — Spec vs. Codebase

Three spec claims drift from codebase reality. Phase 0 corrects spec.md inline.

| Spec claim | Codebase reality (verified 2026-05-22) | Plan response |
|---|---|---|
| FR2.1: 7 tables (`conversations`, `messages`, `kb_files`, `kb_chunks`, `runtime_cost_state`, `scope_grants`, `attachments`) workspace-keyed via `is_workspace_member()` | Migration 059 covers **3 only**: `conversations`, `messages`, `scope_grants`. `kb_files`, `kb_chunks`, `runtime_cost_state`, `attachments` NOT yet workspace-keyed via this predicate; `attachments` is cascade-keyed via `is_message_owner` (migration 045) | Rewrite check as **predicate-based**: "every table containing `workspace_id` (or cascade-routed via a workspace-scoped parent) must reference `is_workspace_member()` or document the cascade." Surface the 4 deferred tables in `## Known gaps` (file deferral issues in Phase 0) |
| FR2.3: JWT `org_id` claim | Migration 060 injects `app_metadata.current_organization_id` via Custom Access Token Hook. No `org_id` claim exists | Rewrite check to `current_organization_id` |
| FR2.6: attestation writes verify "owner-or-admin" role | Migration 058 `add_workspace_member_attestation` enforces **owner only** (lines 198-207). No 'admin' role in `workspace_members.role` | Rewrite check to "owner role" |

FR2.4 (session invalidation) is forward-looking — no mechanism exists today; the agent surfaces this on every identity-touching PR until implemented (tracked via deferral issue, see Phase 0).

## Goals (carried from spec)

- G1: New agent at `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` (or new section in security-sentinel.md per /work Phase 0 re-eval) covering predicate-based Day-1 RLS + JWT checks.
- G2: `/review` dispatches on identity-touching diffs.
- G3: Plugin manifest + README counts updated via `/soleur:release-docs`.

## Non-Goals

- SSO / SAML / SCIM coverage (deferred to Enterprise tier scoping).
- BYOK key cryptographic-isolation review.
- Static analysis tooling (semgrep-sast covers this).
- New test framework or calibration fixture.

## TDD Posture

Infrastructure-only (markdown agent file + dispatch table edit + plugin metadata). Existing `plugins/soleur/test/components.test.ts` auto-discovers agents via `discoverAgents()` and validates frontmatter shape + non-empty body; no new test code needed. Verification is end-to-end: `bash scripts/test-all.sh` + `npx @11ty/eleventy`.

## Implementation Phases

### Phase 0 — Preflight + Spec Correction + Deferral Issues

1. **Approach A vs B re-eval.** Apply the decision tree from `## Implementation Choice` above; record decision in /work tasks.md.
2. **Correct spec.md** FR2.1 → predicate-based, FR2.3 → `current_organization_id`, FR2.4 → forward-looking, FR2.6 → owner-role only. Single commit: `docs(spec): reconcile FR2.{1,3,4,6} with actual migration state (#4233)`.
3. **File 5 deferral issues** for the gaps the agent will surface as `info`-severity findings on every identity-touching PR until closed:
   - "feat: workspace-keyed RLS on kb_files" (label: `deferred-scope-out`, milestone: Post-MVP)
   - "feat: workspace-keyed RLS on kb_chunks" (same)
   - "feat: workspace-keyed RLS on runtime_cost_state" (same)
   - "feat: workspace-keyed RLS on attachments — extend is_message_owner cascade or migrate to direct workspace_id" (same)
   - "feat: session invalidation on workspace_member row delete / role change" (same)

   Each issue body: "Surfaced as known gap by identity-rbac-reviewer (#4233). Re-evaluation criterion: next PR touching this surface OR Enterprise tier scoping." Link issue IDs back into the agent body's `## Known gaps` block.
4. **Verify dispatch globs** match repo state: for each glob in Phase 2 dispatch, run `git ls-files | grep -E '<glob>'` and confirm ≥1 match.

### Phase 1 — Author the agent file (Approach A path)

Author `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` modeled on `data-integrity-guardian.md` (~80 lines).

**Frontmatter description (concise, no duplicated boundary text — boundary lives in `/review/SKILL.md` §boundaries only):**

```yaml
---
name: identity-rbac-reviewer
description: "Use this agent when reviewing PRs that introduce or modify multi-org / workspace boundary surfaces (RLS predicates on workspace-scoped tables, JWT current_organization_id claim consumption, write-boundary sentinel on workspace_id-bearing tables, session invalidation on workspace_member state change, SECURITY DEFINER search_path pinning, workspace_member_attestation owner-check). See plugins/soleur/skills/review/SKILL.md §boundaries for disambiguation."
model: inherit
---
```

**Body sections:**

1. **Mission paragraph** (3-4 sentences) — orient on multi-org/workspace boundary integrity at Day-1 scope; reference live primitives (migrations 053/058/059/060/061).
2. **Day-1 Checklist (R1-R6):**
   - **R1: workspace-keyed RLS.** Every RLS policy on a table containing `workspace_id` (or cascade-routed via a workspace-scoped parent like `messages → attachments`) must reference `public.is_workspace_member(workspace_id, auth.uid())` or document the cascade in a comment.
   - **R2: write-boundary sentinel.** Every `INSERT` / `UPDATE` to a workspace-scoped table must pass through the `assertWriteScope`-class sentinel (canonical pattern; grep the codebase for the live symbol name — e.g., `assertWriteScope`, `assertWorkspaceWrite`, or the helper defined in `apps/web-platform/lib/supabase/tenant.ts`). Inline literal `workspace_id = <expr>` without the sentinel is a finding.
   - **R3: JWT claim consumption.** Routes / middleware filtering by workspace must consume `app_metadata.current_organization_id` (set by migration 060 JWT hook), not a client-supplied arg.
   - **R4: session invalidation (forward-looking).** PRs adding session-state primitives MUST either implement invalidation on `workspace_member` row delete / role change OR explicitly defer with linked issue. **Surface as `info` severity** while no mechanism exists; promote to `high` once foundations land.
   - **R5: SECURITY DEFINER `search_path` pin.** Every new SECURITY DEFINER function touching org/workspace data must include `SET search_path = public, pg_temp` (per `cq-pg-security-definer-search-path-pin-pg-temp`).
   - **R6: attestation RPC owner-check.** Attestation-writing RPCs must verify the caller has `role = 'owner'` on the target workspace at write time (canonical: `add_workspace_member_attestation` lines 198-207).
3. **Severity tagging.** R1, R2, R3, R5, R6 findings: default `critical` (load-bearing safety checks). R4 + Known-gaps findings: default `info` (nudge-pressure on deferred work; do NOT block merge).
4. **Known gaps as of 2026-05-22** — list the 5 deferral issues from Phase 0.3 with linked IDs. Note: "verify against `apps/web-platform/supabase/migrations/` for the canonical predicate list at review time" to handle future helper additions.
5. **Reporting protocol** — match `data-integrity-guardian` severity scale (Critical → High → Medium → Low → Info).

No `## Future:` placeholder section. When SSO/SAML/SCIM scoping begins, add the section then.

### Phase 2 — Wire `/review` dispatch

Edit `plugins/soleur/skills/review/SKILL.md`:

1. Add entry #18 under `#### Conditional Agents`:

   ```markdown
   **If diff touches multi-org / workspace boundary surfaces:**

   18. Task identity-rbac-reviewer(PR content) — workspace-keyed RLS predicates, JWT claim consumption, write-boundary sentinel, session invalidation, SECURITY DEFINER search_path pinning, attestation owner-check

   **When to run identity-rbac-reviewer:**

   - Diff modifies any of (path patterns):
     - `apps/web-platform/supabase/migrations/.*\.sql$`
     - `apps/web-platform/lib/supabase/tenant\.ts`
     - `apps/web-platform/server/.*workspace.*\.ts$` OR `apps/web-platform/server/conversation-writer\.ts`
     - `apps/web-platform/app/api/(workspace|conversations|kb|messages|attachments|scope-grants|account)/.*`
   - OR diff content contains any of (content patterns, anchored to avoid false positives):
     - `\bis_workspace_member\b`
     - `\bcurrent_organization_id\b`
     - `\bworkspace_members\b` (the table, not stray "workspace_member" mentions)
     - `\bset_current_organization_id\b`
     - `\badd_workspace_member_attestation\b`

   **What this agent checks:** see `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` body for the R1-R6 checklist + Known gaps.
   ```

2. Extend `#### Boundary disambiguation` (line 268) to add one paragraph:

   > Use `identity-rbac-reviewer` for multi-org/workspace boundary integrity (RLS routing through `is_workspace_member()`, JWT `current_organization_id` consumption, attestation owner-checks, SECURITY DEFINER pinning). Use `security-sentinel` for OWASP-generic auth/sessions/authorization. Both may fire on the same migration PR — each owns a distinct lens.

### Phase 3 — Release-docs

1. `bash scripts/sync-readme-counts.sh` — auto-updates count headers in both READMEs.
2. Append agent row to `plugins/soleur/README.md` agent table:
   ```
   | `identity-rbac-reviewer` | Multi-org / workspace boundary integrity (RLS, JWT claim, attestation owner-check) |
   ```
   Alphabetical position: between `data-migration-expert` and `kieran-rails-reviewer` (verify at edit time).

### Phase 4 — Verification

1. `bash scripts/test-all.sh > /tmp/test-all.log 2>&1; rc=$?; echo "EXIT=$rc"` — assert `rc=0` (per sharp edge: harness `bash -c` does not inherit pipefail; capture exit explicitly).
2. `npx @11ty/eleventy` — exits 0; `grep -c 'identity-rbac-reviewer' _site/pages/agents.html` returns ≥1.
3. Re-run code-review overlap check; expect no new overlaps.

### Phase 5 — Ship (chained from /work Phase 4 handoff)

`/soleur:work` Phase 4 → `/soleur:review` → `/soleur:compound` → `/soleur:ship`. No operator step.

File one **post-merge follow-up issue** at ship time:

- "ops: audit identity-rbac-reviewer findings after 5 identity-touching PRs (#4233 falsifiability criterion)" — label `deferred-scope-out`, milestone Post-MVP. Body cites the Implementation Choice falsifiability criterion above.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** Agent file exists at chosen path (Approach A or B) with frontmatter (name, description, model: inherit) and body containing the R1-R6 checklist, severity-tagging instructions, and `## Known gaps as of 2026-05-22` block listing the 5 deferral issue IDs.
- [ ] **AC2.** `plugins/soleur/skills/review/SKILL.md` contains a dispatch entry routing identity-touching diffs to the new check surface. AC verifier:
  ```bash
  # Each path pattern + content pattern matches ≥1 file in current repo
  for glob in 'apps/web-platform/supabase/migrations/.*\.sql$' \
              'apps/web-platform/lib/supabase/tenant\.ts' \
              'apps/web-platform/app/api/(workspace|conversations|kb|messages|attachments|scope-grants|account)/'; do
    n=$(git ls-files | grep -E "$glob" | wc -l)
    [[ $n -gt 0 ]] || { echo "FAIL: $glob"; exit 1; }
  done
  # Boundaries paragraph names the new agent
  grep -q 'identity-rbac-reviewer' plugins/soleur/skills/review/SKILL.md
  ```
- [ ] **AC3.** Spec.md FR2.1 / FR2.3 / FR2.4 / FR2.6 corrected. AC verifier:
  ```bash
  spec=knowledge-base/project/specs/feat-agent-identity-rbac-reviewer-4233/spec.md
  grep -q 'is_workspace_member' "$spec"                      # FR2.1 references predicate
  grep -q 'current_organization_id' "$spec"                  # FR2.3 canonical claim
  ! grep -qE '\borg_id\b' "$spec"                            # FR2.3 stale name gone
  grep -qE "role = 'owner'" "$spec"                          # FR2.6 owner-only
  ! grep -q 'owner-or-admin' "$spec"                         # FR2.6 stale phrasing gone
  grep -qE 'forward-looking|no current mechanism' "$spec"    # FR2.4 acknowledged
  ```
- [ ] **AC4.** 5 deferral issues filed with `deferred-scope-out` label; IDs cited in agent body's `## Known gaps` block. AC verifier:
  ```bash
  gh issue list --label deferred-scope-out --state open --search 'workspace-keyed RLS OR session invalidation' --json number --limit 10
  # ≥ 5 results; cross-check each ID appears in the agent file body
  ```
- [ ] **AC5.** `bash scripts/sync-readme-counts.sh` runs clean; new agent row appended to `plugins/soleur/README.md` table.
- [ ] **AC6.** `bash scripts/test-all.sh > /tmp/test-all.log 2>&1; rc=$?; echo "EXIT=$rc"` reports `EXIT=0`.
- [ ] **AC7.** `npx @11ty/eleventy` exits 0; `grep -c 'identity-rbac-reviewer' _site/pages/agents.html` returns ≥1.

### Post-merge (operator)

None inline. Falsifiability follow-up issue (Phase 5) tracked separately.

## Files to Create

- `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` (Approach A) OR a new `## Multi-org / workspace boundary` section in `security-sentinel.md` (Approach B; chosen at /work Phase 0)
- `knowledge-base/project/specs/feat-agent-identity-rbac-reviewer-4233/tasks.md` (auto-generated)

## Files to Edit

- `plugins/soleur/skills/review/SKILL.md` (dispatch entry + boundaries paragraph)
- `plugins/soleur/README.md` (agent table row + sync-readme-counts.sh header)
- `README.md` (sync-readme-counts.sh)
- `knowledge-base/project/specs/feat-agent-identity-rbac-reviewer-4233/spec.md` (FR2.1/2.3/2.4/2.6 corrections — Phase 0)

## Open Code-Review Overlap

- **#3750** — "review: Extract mint-app-jwt composite action" mentions `plugins/soleur/test/components.test.ts`. **Disposition: acknowledge.** Different concern (JWT-mint helper extraction); this plan does not modify components.test.ts. The two PRs cannot conflict.

No overlap on the other planned files.

## User-Brand Impact

`USER_BRAND_CRITICAL=true`. Threshold: `single-user incident`.

**If this lands broken, the user experiences:** the next identity-touching PR ships without dedicated review coverage; a cross-tenant read/write bug is more likely to escape pre-merge review.

**If this leaks, the user's data is exposed via:** four vectors:
1. Cross-tenant data read — RLS uses `auth.uid()` directly instead of `is_workspace_member()`.
2. Cross-tenant data write — write site bypasses workspace-keyed sentinel.
3. Stale session privilege — workspace_member removed but their existing JWT still passes `is_workspace_member()` until expiry. **Known gap.**
4. JWT claim impersonation — org-switch endpoint accepts client-supplied `org_id` without verifying membership.

`user-impact-reviewer` at `/review` (#15) is the load-bearing diff-level gate. This plan adds defense-in-depth lens. CPO sign-off was carried forward from brainstorm (see frontmatter `cpo_signoff_note`).

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward + plan-time self-assessment + 3-agent plan-review applied).

**Assessment:** Narrow review agent matching the existing single-concern reviewer pattern. Day-1 scope is bounded. Build cost: ~30-60 min. Research Reconciliation surfaced 3 spec drifts; corrected in Phase 0. /work Phase 0 re-evaluates Approach A vs B per DHH-style review challenge; the brainstorm chose A but the architectural seam between A and B is thin and worth re-questioning at implementation time. Falsifiability criterion (Phase 5 follow-up issue) makes the decision auditable post-merge.

### Product/UX Gate

**Tier:** none — no user-facing surface.

### Legal (CLO)

**Status:** not invoked — internal review tooling; no DSAR/PII surface.

## Risks

- **R1. Severity tagging not honored.** If `/review` synthesis ignores per-finding severity tags, R4 (session invalidation) and Known-gap findings will surface as critical on every PR and become merge-blocker noise. **Mitigation:** Phase 4 includes a smoke-test of severity propagation: file a synthetic identity-touching PR diff with one R5 violation (missing `search_path`) AND one known-gap touch (modify kb_files), run `/review` against it, confirm R5 fires `critical` and the kb_files-touch fires `info`. If `/review` collapses severity, file a follow-up to fix the synthesis path first.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty / TBD / missing threshold fails `deepen-plan` Phase 4.6. This plan: threshold + 4 named vectors. Passes.
- Predicate-based checklist (R1) is future-proof; table-list-based checklists rot the moment a sibling migration adds a workspace-keyed table the brainstorm-author didn't see.
- README agent-row insertion is alphabetical; `sync-readme-counts.sh` does NOT auto-insert table rows.

## References

- Issue: [#4233](https://github.com/jikig-ai/soleur/issues/4233) · Parent: [#4229](https://github.com/jikig-ai/soleur/issues/4229)
- Spec: `knowledge-base/project/specs/feat-agent-identity-rbac-reviewer-4233/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-agent-identity-rbac-reviewer-brainstorm.md`
- Template: `plugins/soleur/agents/engineering/review/data-integrity-guardian.md`
- Migrations: 053 (organizations + workspace_members), 058 (attestations), 059 (workspace-keyed RLS sweep), 060 (current_organization_id JWT hook), 061 (BYOK workspace_id RPCs)
- Rules: `hr-write-boundary-sentinel-sweep-all-write-sites`, `cq-pg-security-definer-search-path-pin-pg-temp`, `hr-weigh-every-decision-against-target-user-impact`, `hr-when-a-plan-specifies-relative-paths-e-g`, `wg-when-deferring-a-capability-create-a`
