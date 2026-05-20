---
issue: 4159
type: docs-fix
lane: single-domain
classification: docs-only
detail_level: MINIMAL
requires_cpo_signoff: false
deepened: 2026-05-20
---

# Fix Inngest verification hostname (`web-platform.soleur.ai` → `app.soleur.ai`)

Closes #4159.

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Implementation, Acceptance Criteria, Sharp Edges (precision adds — substring-collision audit; AC4 made grep-checkable; gate confirmations).
**Research agents used:** none (inline-only — proportionate to a 4-edit, 2-file docs swap; per AGENTS.md `cm-delegate-verbose-exploration-3-file`, fan-out is not warranted).

### Key Improvements

1. **Substring-collision audit.** `grep -cF 'web-platform.soleur.ai'` returns exactly 1+3=4, matching the known sites. The standalone `web-platform` substring (without `.soleur.ai`) appears 30+ times in `apps/web-platform/infra/...` path references AND in the container/unit name `soleur-web-platform` — `replace_all=true` on the FQDN `web-platform.soleur.ai` does NOT collide with any of these (the literal `old_string` includes `.soleur.ai`). Risk R2 (scope creep) is therefore mechanically zero, not just "verified by AC4".
2. **AC4 hardened.** Replaced prose file-list with a `git diff --name-only main...HEAD | sort` expected-output block.
3. **Hard-gate confirmations** (Phase 4.6 User-Brand Impact: PASS; Phase 4.7 Observability: SKIP per pure-docs trigger; Phase 4.5 Network-Outage: FALSE-POSITIVE skip — see Gate Confirmations).

### New Considerations Discovered

- The plan body matches the Phase 4.5 SSH trigger (case-insensitive) via "no SSH required" (a parenthetical describing the runbook's verification approach, not an SSH-diagnosis hypothesis). Per the L3→L7 checklist's stated intent ("plans addressing SSH/network-connectivity symptoms"), this is a false positive — the plan is a hostname swap, not a connectivity diagnosis. Skipped with rationale rather than mechanically firing the deep-dive.
- No new learnings need to be captured. The existing learning at `knowledge-base/project/learnings/best-practices/2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces.md` already documents the class. The PR will be a self-evident application of that rule.

## Overview

The Inngest server runbook section added in PR #4148 (the `## Fresh-host provisioning (#4118)` section) cites `https://web-platform.soleur.ai/api/inngest` as the operator verification URL. That hostname does not resolve. The canonical prod hostname is `app.soleur.ai`, per `apps/web-platform/infra/variables.tf:88`:

```
default     = "app.soleur.ai"
```

The bad hostname was inherited from issue #4118's body, propagated through PR #4148's body, the runbook section, and the post-merge `gh issue close` instructions. It was caught during post-merge verification on PR #4148 — by definition AFTER the runbook had become the canonical operator reference.

Scope: rename `web-platform.soleur.ai` → `app.soleur.ai` everywhere it appears under `knowledge-base/`. Repo-wide grep (excluding `.git`, `node_modules`, `_site`, `.next`) returns exactly 4 hits in 2 files, all under `knowledge-base/`:

| File | Lines |
| --- | --- |
| `knowledge-base/engineering/ops/runbooks/inngest-server.md` | 301 |
| `knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md` | 177, 237, 379 |

No app code, IaC, workflow YAML, test fixture, or `apps/**` doc reference the wrong hostname. Cloudflare DNS, Terraform `variables.tf`, sibling runbooks (`stripe-live-activation.md`, `github-app-callback-audit.md`, `oauth-probe-failure.md`) already use the canonical `app.soleur.ai`.

## User-Brand Impact

**If this lands broken, the user experiences:** the next operator follows the runbook, runs `curl ... https://web-platform.soleur.ai/api/inngest`, gets DNS-resolution failure, and incorrectly concludes Inngest is down — masking real status during an incident.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — pure docs correction; no data movement, no auth surface, no money flow.

**Brand-survival threshold:** `none`. The runbook lives in `knowledge-base/engineering/ops/runbooks/`, an internal operator-only surface. Wrong hostname is operator-time-wasted, not user-facing. No sensitive-path regex match — no `requires_cpo_signoff` and no scope-out reason needed because no sensitive surface is touched.

## Research Reconciliation — Spec vs. Codebase

| Claim (from issue body) | Reality (grep on 2026-05-20) | Plan response |
| --- | --- | --- |
| "The actual prod hostname is `app.soleur.ai` (per `variables.tf` `app_domain` default)" | Confirmed at `apps/web-platform/infra/variables.tf:85-89` (`variable "app_domain" { default = "app.soleur.ai" }`) | Use `app.soleur.ai` as the canonical replacement. |
| "Update `knowledge-base/engineering/ops/runbooks/inngest-server.md` (the `## Fresh-host provisioning (#4118)` section) and any other reference" | Grep returns 4 hits in 2 files (1 runbook, 1 plan file under `plans/` — NOT yet under `plans/archive/`) | Fix all 4 hits in the same commit. The merged plan file is historical but not archived; future operators searching by content can still copy-paste the bad URL. Per AGENTS.md `2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces`, operator-facing surfaces include `knowledge-base/project/plans/` outside `archive/`. |
| "Verify by grepping `grep -rE 'web-platform\.soleur\.ai' knowledge-base/` — every hit needs the swap" | 4 hits, all enumerated above | Acceptance Criteria includes the grep with expected `0` lines after the fix. |

## Files to Edit

- `knowledge-base/engineering/ops/runbooks/inngest-server.md` — line 301 (verification `curl` URL in the `## Fresh-host provisioning (#4118)` section). The surrounding context (`### Verification (no SSH required)`) describes the verification step; the URL on the next line is the only token requiring change. No prose or AC re-flow needed.
- `knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md` — lines 177, 237, 379 (verification `curl` URL appears three times: once in implementation prose, once in AC-post-1 body, once in a fenced code block). Same one-token swap; no prose re-flow.

## Files to Create

None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200` matched against the two edited file paths returned zero results. (Both files were authored in PR #4148 which merged on 2026-05-20 — no time for a code-review backlog to accumulate.)

## Implementation

A single-edit pass per file. Replacement string: `web-platform.soleur.ai` → `app.soleur.ai`. Use `Edit` with `replace_all=true` on each file (safe: no other text in either file legitimately contains `web-platform.soleur.ai`).

```bash
# Verification command operator (or /work) runs after the edits:
grep -rE 'web-platform\.soleur\.ai' knowledge-base/
# Expected output: (empty) — exit code 1.

# Spot-check the canonical hostname now appears at the same sites:
grep -nE 'app\.soleur\.ai/api/inngest' \
  knowledge-base/engineering/ops/runbooks/inngest-server.md \
  knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md
# Expected output: 4 lines (1 in runbook, 3 in plan).
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** `grep -rE 'web-platform\.soleur\.ai' knowledge-base/ --exclude-dir=feat-one-shot-runbook-hostname-4159 --exclude=2026-05-20-fix-runbook-inngest-hostname-app-soleur-ai-plan.md` returns no lines (exit code 1). The exclusions cover this fix plan and `tasks.md`, both of which intentionally retain the literal bad string in prose describing the rename (meta-documentation, not operator-actionable). Verified post-edit by the implementer.
- [ ] **AC2.** `grep -cE 'app\.soleur\.ai/api/inngest' knowledge-base/engineering/ops/runbooks/inngest-server.md` returns `1`.
- [ ] **AC3.** `grep -cE 'app\.soleur\.ai/api/inngest' knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md` returns `3`.
- [ ] **AC4.** No other file is modified in this PR. `git diff --name-only main...HEAD | sort` returns EXACTLY:

  ```
  knowledge-base/engineering/ops/runbooks/inngest-server.md
  knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md
  knowledge-base/project/plans/2026-05-20-fix-runbook-inngest-hostname-app-soleur-ai-plan.md
  knowledge-base/project/specs/feat-one-shot-runbook-hostname-4159/tasks.md
  ```

  Per issue body: "One-line fix; do not require new acceptance tests."
- [ ] **AC5.** PR body uses `Closes #4159` (not `Refs`) — this is a docs change applied at merge time with no post-merge operator action, so auto-close at merge is correct.

### Post-merge (operator)

None. No deploy, no migration, no apply, no follow-up verification — the runbook becomes correct at merge time. Per AGENTS.md `hr-no-dashboard-eyeball-pull-data-yourself`: no dashboard check is needed because the artifact under verification IS the merged file content, which `git show` and `gh pr diff` already confirm at merge.

## Test Strategy

No new tests. Per issue body: "One-line fix; do not require new acceptance tests." The verification greps in AC1-AC3 are the post-conditions; running them after the edit is the test. No drift-guard test is justified — the canonical hostname is locked in `apps/web-platform/infra/variables.tf:88` and propagating it into the runbook is a one-shot doc fix, not a recurring contract.

(If this class of regression recurs — wrong hostname in operator-facing docs — a future PR could add a CI grep step against operator-facing surfaces to flag any literal hostname that disagrees with `variables.tf`'s `app_domain` default. Out of scope for this PR; tracked implicitly by the existing learning `2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces.md`.)

## Risks

- **R1 (low):** the merged plan file at `2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md` is historical record. Editing it post-merge mildly muddies the audit trail of "what the plan looked like when it merged." Mitigation: git history preserves the pre-edit content; anyone needing the original can run `git show <pre-fix-sha>:<path>`. The benefit (preventing future operator copy-paste of the bad URL) outweighs the audit-trail cost — same logic as updating any merged-and-living document.
- **R2 (none):** scope creep into adjacent files. Mitigated by AC1's exit-code-1 verification (zero remaining hits) AND AC4's file-list assertion (only the runbook + the inngest plan + this plan's scaffold).
- **R3 (none):** wrong replacement value. `app_domain = "app.soleur.ai"` at `variables.tf:85-89` is the single source of truth; 7 sibling files (sentry README, seo-rulesets.tf, 3 sibling runbooks, more) already cite `app.soleur.ai` — corroborated. No alternative candidate hostname exists.

## Domain Review

**Domains relevant:** none.

Pure docs-only correction inside an existing runbook section. No code, no schema, no UI, no IaC, no regulated-data surface, no new agent body, no SDK contract, no auth flow. Phase 2.5 domain sweep skipped per "infrastructure/tooling change with no cross-domain implications."

## Infrastructure (IaC)

Not applicable. No new resource, no provider edit, no Terraform root, no cloud-init change, no service, no secret. Per Phase 2.8: "Skip silently if the plan introduces no new infrastructure (pure code change against an already-provisioned surface)." This plan only edits markdown.

## Observability

Skip — pure-docs plan. Files-to-Edit list contains zero code-class files under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`, and introduces no new infrastructure surface (Phase 2.8 trigger set empty). Per Phase 2.9 skip rule: "Plan is pure-docs (no Files-to-Edit under code/infra paths above)."

## GDPR / Compliance Gate

Skip silently. Canonical regex (`schemas, migrations, auth flows, API routes, .sql files`) does not match — only `.md` files are touched. None of the 4 expansion triggers fire: (a) no LLM/external API processing, (b) brand-survival threshold is `none`, (c) no new cron/workflow reading from `knowledge-base/project/learnings/` or `specs/`, (d) no new artifact distribution surface.

## Sharp Edges

- The merged plan file `2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md` is touched in this PR but is **not** in `plans/archive/`. The archive sharp-edge rule (`knowledge-base/project/{plans,specs}/**` excluded from operator-surface grep sweeps applies to `archive/` subdirs specifically — the active `plans/` directory IS an operator-facing surface per `2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces.md`). Treat it as in-scope.
- Do NOT add `replace_all` semantics blindly — both edited files contain other `soleur.ai` subdomains and surrounding prose. Use `replace_all=true` on the EXACT string `web-platform.soleur.ai` only, which is uniquely the wrong hostname in both files (no false positives).

## Why one-shot, not deferred

The issue is labeled `priority/p3-low` but the cost of fix is ~2 edits and the cost of leaving it is operator-time-wasted at the next incident. One-shot is correct: a multi-phase plan would be over-engineering for a 4-line, 2-file docs swap.

## Plan-time verifications run

1. Read `apps/web-platform/infra/variables.tf:85-89` — confirmed `app_domain` default = `app.soleur.ai`.
2. `grep -rn 'web-platform\.soleur\.ai' .` (excluding `.git`/`node_modules`/`_site`/`.next`) — 4 hits, enumerated above.
3. `grep -rn 'app\.soleur\.ai' apps/web-platform/infra/ knowledge-base/engineering/ops/runbooks/` — confirmed canonical hostname appears in 6+ sibling locations.
4. `gh issue view 4159` — confirmed scope, labels, AC text.
5. `git log --oneline -10 -- knowledge-base/engineering/ops/runbooks/inngest-server.md` — confirmed PR #4148 (`f2b2f959`) introduced the wrong hostname.
6. `gh issue list --label code-review --state open` matched against edited file paths — zero overlap.

## Deepen-pass verifications run

7. `grep -cF 'web-platform.soleur.ai' <runbook> <inngest-plan>` returns `1` and `3` respectively, confirming the 4-hit total via a substring-anchored (not regex) count.
8. `grep -nF 'web-platform' <runbook> <inngest-plan>` returns 30+ matches, none of which extend to `.soleur.ai` (all are `apps/web-platform/...` paths or `soleur-web-platform` unit/container names). Confirms `replace_all=true` on the FQDN `web-platform.soleur.ai` does NOT collide.

## Gate Confirmations

- **Phase 4.5 (Network-Outage Deep-Dive):** SKIP. Trigger pattern `SSH` matches (one occurrence: "no SSH required" in Files-to-Edit prose at line 51 of this plan, describing the runbook's existing SSH-free verification approach — NOT an SSH-diagnosis hypothesis). The L3→L7 checklist's stated intent is "plans addressing SSH/network-connectivity symptoms"; this plan addresses a literal-string hostname swap with no network-failure hypothesis to diagnose. False-positive trigger; deep-dive skipped with rationale. Resource-shape trigger does NOT fire (no `terraform apply` in this PR; no `provisioner "file"` / `remote-exec` / `connection { type = "ssh" }` in the edited files — both are markdown).
- **Phase 4.6 (User-Brand Impact Halt):** PASS. Heading present at the `## User-Brand Impact` section. Body has all three required lines (lands-broken artifact, leaks-vector, threshold). Threshold = `none`. Sensitive-path regex does NOT match the diff (all edited paths are `.md` under `knowledge-base/`; no `apps/web-platform/(server|supabase|app/api|middleware.ts)`, no `apps/*/infra/`, no `.github/workflows/`, no `doppler*.{yml,yaml,sh}`). Scope-out line not required.
- **Phase 4.7 (Observability Gate):** SKIP. All Files-to-Edit paths match `^knowledge-base/` (pure-docs trigger). No `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/` paths. No `## Observability` section required.
- **GDPR / Compliance Gate (Phase 2.7):** SKIP. Canonical regex (schemas/migrations/auth/API/`.sql`) does not match; expansion triggers (a)-(d) do not fire.
- **Infrastructure-as-Code Gate (Phase 2.8):** SKIP. No new resource, no provider, no Terraform root edit, no cloud-init change. Pure docs.
