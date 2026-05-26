---
title: Tasks — Identity/RBAC Reviewer Agent
issue: 4233
spec: knowledge-base/project/specs/feat-agent-identity-rbac-reviewer-4233/spec.md
plan: knowledge-base/project/plans/2026-05-22-feat-identity-rbac-reviewer-agent-plan.md
branch: feat-agent-identity-rbac-reviewer-4233
pr: 4288
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks: Identity/RBAC Reviewer Agent

Derived from `knowledge-base/project/plans/2026-05-22-feat-identity-rbac-reviewer-agent-plan.md`. Execution is sequential per phase; tasks within a phase may be parallelized where independent.

## Phase 0 — Preflight + Spec Correction + Deferral Issues

- [ ] **0.1 Re-evaluate Approach A vs B.** Read `plugins/soleur/agents/engineering/review/security-sentinel.md` (currently 98 lines). Measure: would a ~30-line "Multi-org / workspace boundary" subsection violate `cq-skill-description-budget-headroom` (description-line budget) OR meaningfully bloat the body? Read `plugins/soleur/skills/review/SKILL.md` Change Classification Gate (line 64) — confirm security-sentinel fires on every `code`-class PR (broad) vs identity-rbac-reviewer firing only on identity-touching diffs (narrow). Record the chosen approach + rationale in this tasks.md as a one-line comment under task 1.1.
- [ ] **0.2 Correct spec.md.** Edit `knowledge-base/project/specs/feat-agent-identity-rbac-reviewer-4233/spec.md`:
  - FR2.1: replace 7-table list with "every table containing `workspace_id` (or cascade-routed via a workspace-scoped parent) must reference `public.is_workspace_member()` or document the cascade"
  - FR2.3: replace `org_id` with `current_organization_id`
  - FR2.4: append "(forward-looking — no current mechanism; agent surfaces as `info` finding until implemented)"
  - FR2.6: replace "owner-or-admin role" with "owner role"
  - Single commit: `docs(spec): reconcile FR2.{1,3,4,6} with actual migration state (#4233)`
  - **Verify:** run AC3's grep block (see plan) and confirm all 6 assertions pass.
- [ ] **0.3 File 5 deferral issues.** For each, body cites #4233 and `wg-when-deferring-a-capability-create-a`:
  - [ ] 0.3.1 `gh issue create --title "feat: workspace-keyed RLS on kb_files" --label deferred-scope-out --milestone "Post-MVP / Later" --body "Surfaced as known gap by identity-rbac-reviewer (#4233). Re-evaluation: next PR touching kb_files OR Enterprise tier scoping."`
  - [ ] 0.3.2 Same for `kb_chunks`.
  - [ ] 0.3.3 Same for `runtime_cost_state`.
  - [ ] 0.3.4 Same for `attachments — extend is_message_owner cascade or migrate to direct workspace_id`.
  - [ ] 0.3.5 `gh issue create --title "feat: session invalidation on workspace_member row delete / role change" --label deferred-scope-out --milestone "Post-MVP / Later" --body "Surfaced as known gap (R4) by identity-rbac-reviewer (#4233). Currently JWTs remain valid until expiry; removed members retain access during the window. Re-evaluation: when Enterprise tier scoping begins OR multi-org incident."`
  - Record the 5 issue numbers in this tasks.md inline for AC4 cross-check.
- [ ] **0.4 Verify dispatch globs.** For each glob in Phase 2 dispatch, run `git ls-files | grep -E '<glob>' | wc -l` and confirm ≥1 match. If a glob returns 0, refine (e.g., camelCase vs kebab-case filename drift).
- [ ] **0.5 Commit phase 0** (spec correction is its own commit per 0.2; the deferral issues are external GH state, not local).

## Phase 1 — Author the agent file

(If Approach B chosen at 0.1: skip this phase; instead append a `## Multi-org / workspace boundary` section to `plugins/soleur/agents/engineering/review/security-sentinel.md` with the same R1-R6 checklist + severity tagging + Known-gaps block. Adapt subsequent phases.)

- [ ] **1.1 Author `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md`** modeled on `data-integrity-guardian.md` (~80 lines). Required structure per plan §Phase 1:
  - Frontmatter: `name: identity-rbac-reviewer`, `description: "..."` (concise — no boundary text duplication; refer to `/review/SKILL.md` §boundaries), `model: inherit`.
  - Mission paragraph (3-4 sentences) citing migrations 053/058/059/060/061.
  - Day-1 Checklist R1-R6 per plan §Phase 1 (predicate-based R1; named symbol-class for R2 — verify the actual symbol name in `apps/web-platform/lib/supabase/tenant.ts` at write time).
  - Severity tagging block: R1/R2/R3/R5/R6 → `critical`; R4 + Known-gaps → `info`.
  - `## Known gaps as of 2026-05-22` with the 5 deferral issue IDs from 0.3.
  - Reporting protocol matching `data-integrity-guardian` (Critical → High → Medium → Low → Info).
  - **No `## Future:` placeholder section** (add when SSO scoping begins).
- [ ] **1.2 Verify frontmatter.** Run `bun test plugins/soleur/test/components.test.ts 2>&1 | grep -E "(identity-rbac|FAIL)"`. The new file is auto-discovered and must pass `has frontmatter`, `has name field`, `has description field`, `has valid model field`, `description does not contain <example> block`, `has non-empty body`.
- [ ] **1.3 Verify R2 sentinel symbol.** `grep -nE 'assertWriteScope|assertWorkspaceWrite' apps/web-platform/lib/supabase/tenant.ts apps/web-platform/server/ | head` — confirm the canonical sentinel name and update the agent's R2 text to reference it literally.
- [ ] **1.4 Commit:** `feat(plugin): add identity-rbac-reviewer agent for multi-org/workspace boundary integrity (#4233)`

## Phase 2 — Wire `/review` dispatch

- [ ] **2.1 Add dispatch entry #18** to `plugins/soleur/skills/review/SKILL.md` per plan §Phase 2 step 1. Place after #17 (anti-slop scanner) and before §`### 2. Rate Limit Fallback`. Use the verbatim shape from the plan (path patterns + content patterns + What-this-agent-checks pointer).
- [ ] **2.2 Extend boundaries paragraph** at `{#boundaries}` (line 268) per plan §Phase 2 step 2. One additional paragraph naming identity-rbac-reviewer's distinct lens against security-sentinel.
- [ ] **2.3 Confirm dispatch globs match repo (re-verify from 0.4 in case of intervening edits):**
  ```bash
  for glob in 'apps/web-platform/supabase/migrations/.*\.sql$' \
              'apps/web-platform/lib/supabase/tenant\.ts' \
              'apps/web-platform/app/api/(workspace|conversations|kb|messages|attachments|scope-grants|account)/'; do
    n=$(git ls-files | grep -E "$glob" | wc -l)
    echo "$glob: $n"
    [[ $n -gt 0 ]] || { echo "FAIL"; exit 1; }
  done
  ```
- [ ] **2.4 Run tests** — `bash scripts/test-all.sh > /tmp/test-all.log 2>&1; rc=$?; echo "EXIT=$rc"`. Assert `rc=0`.
- [ ] **2.5 Commit:** `feat(plugin): wire identity-rbac-reviewer into /review dispatch (#4233)`

## Phase 3 — Release-docs

- [ ] **3.1** `bash scripts/sync-readme-counts.sh` (no `--check`; this is the apply path).
- [ ] **3.2** Append agent row to `plugins/soleur/README.md` agent table:
  ```
  | `identity-rbac-reviewer` | Multi-org / workspace boundary integrity (RLS, JWT claim, attestation owner-check) |
  ```
  Alphabetical position: between `data-migration-expert` and `kieran-rails-reviewer`. Verify the surrounding rows at edit time.
- [ ] **3.3 Re-run `bash scripts/sync-readme-counts.sh --check`** to confirm counts agree across both READMEs after the manual row append.
- [ ] **3.4 Commit:** `docs(plugin): release-docs updates for identity-rbac-reviewer (#4233)`

## Phase 4 — Verification

- [ ] **4.1** `bash scripts/test-all.sh > /tmp/test-all.log 2>&1; rc=$?; echo "EXIT=$rc"` — assert `EXIT=0` and capture the summary line in the PR body.
- [ ] **4.2** `npx @11ty/eleventy` — exit 0; then `grep -c 'identity-rbac-reviewer' _site/pages/agents.html` returns ≥1.
- [ ] **4.3 Severity propagation smoke-test (R1 mitigation).** Construct an in-memory synthetic diff (do NOT commit) with one R5 violation (missing `SET search_path` on a SECURITY DEFINER function) AND one Known-gap touch (modify `kb_files` table). Spawn `identity-rbac-reviewer` agent against the diff and inspect output: R5 should be tagged `critical`; kb_files touch should be tagged `info`. If `/review` synthesis collapses severities, file a follow-up to fix the synthesis path before claiming the agent is production-ready.
- [ ] **4.4 Re-run code-review overlap check:** `gh issue list --label code-review --state open --json number,title,body --limit 200` and grep for the plan's edited files. No new overlaps expected beyond #3750 (already acknowledged).
- [ ] **4.5 Cross-check AC verification block** from plan §Acceptance Criteria runs clean. Capture command output in the PR body for AC traceability.

## Phase 5 — Ship + Follow-up issue

- [ ] **5.1 File falsifiability follow-up issue:**
  ```bash
  gh issue create --title "ops: audit identity-rbac-reviewer findings after 5 identity-touching PRs (#4233 falsifiability criterion)" \
    --label deferred-scope-out --milestone "Post-MVP / Later" \
    --body "Per plan §Implementation Choice falsifiability criterion: after 5 identity-touching PRs post-merge, audit whether identity-rbac-reviewer's findings were a strict subset of pre-existing security-sentinel findings on the same PRs. If yes, fold the R1-R6 checklist back into security-sentinel and remove the standalone agent. Tracks #4233."
  ```
- [ ] **5.2 Chain `/soleur:ship`** — handles `/review` → `/compound` → `gh pr ready` → auto-merge. No operator step.

## Done-criteria checklist

All Pre-merge ACs from the plan satisfied (AC1-AC7); `/soleur:ship` exits clean; PR #4288 merged; 6 GitHub issues filed (5 deferral + 1 falsifiability follow-up); #4233 auto-closed by merge via `Closes #4233` in PR body.
