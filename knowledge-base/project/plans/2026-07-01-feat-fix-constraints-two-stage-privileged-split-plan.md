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

## Overview

The `/soleur fix constraints` recovery dispatcher (`fix-constraints.yml`, built for #5791, held in draft PR #5804) trips **3 critical CodeQL `actions/untrusted-checkout-toctou` alerts**. It is an `issue_comment`-triggered job that holds `ANTHROPIC_API_KEY` + `contents: write`, checks out PR-head code (`gh pr checkout`), and **executes it** — `bun install --frozen-lockfile` (postinstall scripts), the api-spend script, and `apps/web-platform/scripts/constraint-gates.sh` — all from the PR head. The author-association + collaborator-permission + head==base gates bound **who** can trigger it, but CodeQL fires on the *structural* sink: a privileged trigger that holds secrets/write executes untrusted-PR-derived code. Gates don't clear it.

Operator decision (2026-06-30): **hold + redesign**, not dismiss-and-merge. The constraint-gate is still informational (not a required branch-protection check), so the founder-deadlock is latent and there is no urgency.

**The fix is architectural** — the GitHub Security Lab "preventing pwn requests" canonical pattern: split the workflow so the *write-capable* stage never co-locates with untrusted code execution.

- **Stage A — `pull_request` (untrusted, NO write token):** runs `bun install --frozen-lockfile --ignore-scripts` + the **full** `constraint-gates.sh` (not bare `depcruise` — preserves the `couldNotResolve` blind-gate self-check); only if the gate is RED **and** the agent has a key (same-repo PR), dispatches the agent to fix, **re-verifies the gate is green**, and uploads an artifact containing the **full post-image contents of the changed allowlisted files** (NOT a unified diff) + `meta.json` (pr_number, immutable head_sha, head_ref — for cross-checking only). `permissions: contents: read`. No write token. Running untrusted PR code here is the *expected, safe* thing — `pull_request` is CodeQL's designated untrusted context.
- **Stage B — `workflow_run` (privileged, HAS write token):** triggered by Stage A's completion. **Sources all routing identity from the trusted event, never the artifact** — `head_sha` from `github.event.workflow_run.head_sha`, `pr_number`/`head_ref` resolved by API from that SHA (cross-checked against `meta.json`, reject on mismatch — `workflow_run.pull_requests` is empty for fork PRs). Validates each file path against a **normalized path allowlist** (reject `.github/**`, `*.cjs`, the runner, symlinks, `..` traversal, anything outside the gate-fixable surface). Then **builds the commit via the Git Data API** — create blobs from the explicit allowlisted post-image files → tree on top of `head_sha` → commit → `soleur/fix-constraints/<pr>` ref — and opens a **follow-up PR** (`Ref #<pr>`, human merge gate). **Stage B NEVER `actions/checkout`s the untrusted tree, never `git apply`s a diff, never runs `bun install` or any PR script.** This makes the untrusted-checkout sink *structurally absent* (no checkout step to flag) and dissolves the entire diff-parser attack class (rename/symlink/traversal). The write token never touches untrusted code or an untrusted checkout → clears the structural finding by construction.

**UX change (deliberate, ADR-recorded):** the `/soleur fix constraints` *comment* trigger is **dropped**. Recovery becomes **automatic** on any PR whose gate is red and auto-fixable, delivered as a follow-up PR. This is strictly better for the #5791 founder-deadlock target (a non-technical founder's GitHub-web hotfix gets an auto-fix PR with zero ceremony) and removes the entire comment-parse + author-association + exact-match-command surface that CodeQL flagged. See Alternative Approaches for the comment-as-label hybrid that preserves on-demand invocation (deferred).

This branch is off `main`; the redesign-target files exist **only** in held PR #5804 (see Research Reconciliation). Therefore **#5814 supersedes #5804**: it lands the *redesigned* dispatcher + scaffold template + tests + ADR/C4 directly on top of main, and #5804 is **closed** (not merged) when #5814 merges.

**Deliverables:**

1. **Two repo-root workflows** replacing the single held `fix-constraints.yml`:
   - `.github/workflows/fix-constraints-stage-a.yml` — `pull_request`, read-only, agent + patch-artifact producer.
   - `.github/workflows/fix-constraints-stage-b.yml` — `workflow_run`, privileged, patch-validator + `git apply` + bot-branch follow-up PR.
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
| "Stage A — `pull_request` (no secrets)." | `pull_request` **does** carry secrets for **same-repo** PRs (the solo-founder target, head==base); it **withholds** secrets from **fork** PRs. | Same-repo PRs (the target user) get `ANTHROPIC_API_KEY` in Stage A → agent runs. Fork PRs get no key → agent step skipped → no patch → Stage B no-ops. Consistent with the held "fork PRs can't be auto-fixed" stance. |
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

- **Create `ADR-074` — "fix-constraints recovery: two-stage `pull_request`→`workflow_run` privileged split."** (ADR-074 confirmed free: `grep -rl ADR-074 knowledge-base/` → empty; highest on main is ADR-073.) **The load-bearing decision to record is the data-plane apply mechanism: Git Data API blob/tree/commit (Stage A uploads full post-image file contents) vs. checkout-of-head + `git apply` of a diff** — the Git Data API choice is what makes the untrusted-checkout sink *structurally absent* (no checkout step exists to flag) and dissolves the diff-parser attack class (rename/symlink/`..`-traversal), not merely mitigate them. Also record: the structural CodeQL sink; why `pull_request` is the safe place to run untrusted code; event-sourced routing identity (`head_sha`/`pr_number`/`head_ref` from the event, never the artifact — P0-1); the normalized path allowlist; the **baseline-suppression hazard** (P0-3: the agent can pass the gate by whitelisting a real leak into `.dependency-cruiser-known-violations.json` — Stage B must segregate baseline-mutating patches to heightened review); the dropped comment trigger; the follow-up-PR-via-GITHUB_TOKEN (no-CI-retrigger) reasoning; the capped per-tenant key bounded-exfil acceptance; and **Alternatives Considered** (single-job permission-downscope — rejected, CodeQL keys on the trigger not job perms; checkout-head + `git apply` of a diff — rejected as primary, hostile parser surface + checkout-in-privileged-`workflow_run` may trip `untrusted-checkout-high` independent of execution; egress-restricted self-hosted runner — heavier, Soleur-only, deferred; comment→label→`pull_request:[labeled]` hybrid — deferred). Author via `/soleur:architecture create 'Two-stage privileged-recovery dispatcher: data-plane apply over Git Data API'`.
- **Amend `ADR-071`** recovery paragraph: replace the held-PR wording ("dispatcher now wired via `fix-constraints.yml`, pushes to PR head, gated by author-association…") with "auto-recovery via the two-stage split (ADR-074); follow-up PR, not head-push." Keep promotion-to-required blocked on #5778 (still out of scope).

### C4 views

**Read all three model files** (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Verified current state: **modeled** — `founder` actor (model.c4:8), `anthropic` external system (model.c4:196), `constraintscaffold` component (model.c4:138-141) with edge `constraintscaffold -> webapp "Generates L1 import-boundary gate (CI)"` (model.c4:312). **NOT modeled** — the GitHub Actions CI runner, the fix-constraints recovery dispatcher + its `pull_request`/`workflow_run` trust boundary, a generic Contributor (untrusted PR author) distinct from the Owner-founder.

External-actor / external-system / access-relationship enumeration for this feature:
- **External human actor — Contributor / PR author (untrusted):** distinct from the trusted `founder`. The redesign's whole point is the untrusted-vs-privileged boundary. → **add** a `contributor` actor tagged `#external`, OR (lighter) annotate the boundary on the recovery component. Decision in /work: add a minimal `contributor` actor only if it renders meaningfully; otherwise model the trust boundary on the recovery component's description.
- **External system — Anthropic API:** already modeled (model.c4:196). Add the Stage-A edge: `fixconstraints -> anthropic "Agent fixes tripped gate (Stage A, capped key)"`.
- **Container/data-store — GitHub Actions runner + artifact store:** the artifact is the trust-boundary crossing (Stage A → Stage B). Model a `fixconstraints` component (the two-stage recovery dispatcher) with edges: Stage A reads the PR head (untrusted), Stage B writes a follow-up PR to `webapp` repo (privileged, data-only `git apply`).
- **Access-relationship change:** none on the *product* data model (this is CI harness infra). The new relationship is CI-internal (dispatcher → repo via follow-up PR).

**Task:** edit `model.c4` to add the `fixconstraints` recovery-dispatcher component + its two edges (→ anthropic, → webapp), add the `view … include` line in `views.c4` so it renders, and fix any element description the change falsifies. Then run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` (a `view include` of an undefined element fails there, not at `tsc`). A "no C4 impact" conclusion is **rejected** here — the recovery trust boundary is a genuine architectural addition the existing model omits.

### Sequencing

ADR-074 is authored now describing the target state; it ships **with** this PR (status: accepted). No soak gating (the "0 CodeQL alerts" verification is a one-time post-merge check, not a multi-day soak).

## Infrastructure (IaC)

The redesign introduces one new credential surface: a **capped, rotatable Anthropic API key with a hard spend cap**, contained in Stage A.

### Terraform changes

- **No Terraform provider exists for Anthropic API-key minting.** Anthropic offers an **Admin API** (Workspaces + API keys + workspace-scoped spend limits) — **automation feasibility UNVERIFIED at plan time.** `/work` MUST verify via the `claude-api` skill / Anthropic Admin API docs whether a workspace-scoped key + spend limit can be created programmatically (Admin API) or via Playwright against the Anthropic Console, **before** asserting operator-only (`hr-verify-repo-capability-claim-before-assert`; learning 2026-06-17-vendor-dashboard-mint-presumed-playwright-automatable).
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
  - mode: "patch fails the path allowlist (touches .github/**, *.cjs, runner, or out-of-scope)"
    detection: "Stage B validator rejects pre-apply"
    alert_route: "Stage B comments 'fix not auto-applicable (out-of-scope edit) — maintainer needed' on the original PR"
  - mode: "git apply fails (head moved / conflict)"
    detection: "git apply --check non-zero in Stage B"
    alert_route: "Stage B comments the apply failure; no push"
  - mode: "fork PR (no key in Stage A)"
    detection: "agent step skipped (no ANTHROPIC_API_KEY)"
    alert_route: "Stage A logs skip; optional 'fork PRs need a maintainer' note (non-blocking)"
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
- 0.4 **download-artifact SHA:** the repo has no `actions/download-artifact` precedent. Pin it to the v4 release SHA, **fetched at /work** via `gh api repos/actions/download-artifact/git/refs/tags/v4` — do NOT fabricate a SHA. upload-artifact is already pinned `ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2` (reuse).
- 0.5 **Anthropic capped-key automatability** (IaC section) — verify Admin API vs Playwright vs operator. Mark UNVERIFIED until a real attempt.
- 0.6 **Create the `constraint-baseline-growth` label** — `gh label list` confirms it does NOT exist; `gh label create constraint-baseline-growth --description "Auto-recovery PR grew the dependency-cruiser baseline — heightened review" --color D93F0B` (Stage B applies it; prescribed-labels Sharp Edge).

### Phase 1 — Stage A workflow (`fix-constraints-stage-a.yml`)
- `on: pull_request: types: [opened, synchronize, reopened]`, `paths:` the constrained surface (`apps/web-platform/app/**`, `components/**`, `server/**`, `apps/web-platform/.dependency-cruiser*`). Defense-in-depth: skip on `soleur/fix-constraints/*` head branches (P1 loop guard — Stage B's follow-up PR must not re-dispatch). `concurrency: group fix-constraints-a-${{ github.event.pull_request.head.sha }}, cancel-in-progress: true` (P1 key-burn dedup — one head SHA can't fan out N agent dispatches).
- `permissions: contents: read` (NO write, NO pull-requests). Top-level none; job-level explicit.
- Steps: SHA-pinned `actions/checkout` (defaults to immutable `pull_request.head.sha`); `anthropic-preflight` gate; `setup-bun` + `bun install --frozen-lockfile --ignore-scripts` (Setup-Bun toolchain lesson — the gate needs `node_modules/.bin/depcruise`; `--ignore-scripts` kills the postinstall ACE vector over fork code; CTO §6); run the **full** `constraint-gates.sh` (NOT bare `depcruise` — preserves the `couldNotResolve` blind-gate self-check) and capture rc; **if rc!=0 AND key present:** dispatch `claude-code-action` (file edits only, no commit/push — same prompt as held); re-run the **full** `constraint-gates.sh` to VERIFY (rc must be 0 AND `git diff` non-empty); `extract-api-spend.sh` → upload api-spend artifact.
- **Produce the recovery artifact as full post-image FILE CONTENTS, not a diff** (CTO P0-2): compute the changed-file set (`git diff --name-only`), assert every path is in the allowlist (else abort — don't ship an out-of-scope file), copy each changed file's *current* content into the artifact preserving its repo-relative path, and write `meta.json` (`pr_number`, `head_sha`, `head_ref`, the changed-path list, and a `touches_baseline` boolean if `.dependency-cruiser-known-violations.json` changed). Upload via `actions/upload-artifact` (name `fix-constraints-patch-<pr>`). No artifact when the gate was already green, the agent made no change, or verify is still red.
- Sanitize every PR-derived string passed to `run:` via `env:` (never inline `${{ github.event.* }}`); strip `[\x00-\x1f\x7f  ]` before any annotation (log-injection learning).

### Phase 2 — Stage B workflow (`fix-constraints-stage-b.yml`)
- `on: workflow_run: workflows: ["fix-constraints-stage-a"], types: [completed]`. Guard `if: github.event.workflow_run.conclusion == 'success'` (precedent: deploy-docs.yml:16-18,32 / post-merge-monitor.yml). Stage B's workflow file is always read from the **default branch** (the security property that makes the pattern safe).
- `permissions: contents: write, pull-requests: write`.
- Download the Stage A artifact via `actions/download-artifact` with `run-id: ${{ github.event.workflow_run.id }}` + `github-token`. If no artifact → exit 0 (no-op).
- **Routing identity from the EVENT, never the artifact (CTO P0-1/Q4):** `HEAD_SHA = github.event.workflow_run.head_sha`. Resolve `pr_number` + `head_ref` by GitHub API from `HEAD_SHA` (NOT `workflow_run.pull_requests`, which is empty for fork PRs), then **cross-check against `meta.json` and reject on any mismatch**. A fork-controlled `meta.json` must never redirect the fix at a victim PR or smuggle ref-metacharacters into the branch name. Validate `HEAD_SHA` matches `^[0-9a-f]{40}$`; `pr_number` `^[0-9]+$`.
- **Path validation (security crux):** for each artifact file path, normalize/canonicalize, reject any absolute path or `..` segment, reject symlink modes (`120000`), then **ALLOW only** `apps/web-platform/{app,components,server}/**` + `apps/web-platform/.dependency-cruiser-known-violations.json`; **REJECT** (hard-fail, comment, no write) `.github/**`, `**/*.cjs`, `apps/web-platform/scripts/constraint-gates.sh`, and anything else. Fail-closed: any unmatched path rejects the WHOLE artifact.
- **Build the commit via the Git Data API — NO checkout of the untrusted tree, NO `git apply`** (CTO P0-2): for each allowlisted file create a blob (`POST /git/blobs`), build a tree on base `HEAD_SHA` (`POST /git/trees`), create a commit (`POST /git/commits`, parent = `HEAD_SHA`), create the ref `refs/heads/soleur/fix-constraints/<pr>` (`POST /git/refs`). No `actions/checkout` of head, no `bun install`, no script execution anywhere in Stage B.
- **Baseline-suppression segregation (CTO P0-3):** if `meta.json.touches_baseline` is true, the follow-up PR MUST (a) carry a `constraint-baseline-growth` label, (b) enumerate every newly-suppressed edge (diff the baseline JSON), and (c) carry a heightened-review banner — a non-technical founder cannot tell a real fix from a real leak whitelisted into the baseline. Route to CODEOWNERS / explicit annotation. Flag to `data-integrity-guardian` at review.
- Open follow-up PR: title `fix(constraint-gates): auto-recover tripped gate for #<pr>`, body `Ref #<pr>` + the gate-fix summary + "Stage A pre-verified the gate is green." Comment on the original PR linking the follow-up PR. **Feedback-output preservation (CTO §6 P1):** dropping the comment *trigger* must NOT drop the comment *output* — one deterministic comment per terminal state (recovered→PR-opened / rejected-out-of-scope / identity-mismatch / no-fix), never silent; explicit step-output conditionals, not job-`result` trichotomy.

### Phase 3 — Scaffold template + generator + tests
- Replace the held single `fix-constraints-workflow.template` with **two** templates (`fix-constraints-stage-a.template`, `fix-constraints-stage-b.template`) using the `__TARGET_DIR__` placeholder. Update `constraint-scaffold.sh` (emit both, extend the refuse-if-exists loop, sed both) — main version currently emits 3 artifacts; the held branch added FIXWORKFLOW (lines 40,156). The redesign emits config + runner + constraint-gates.yml + **both** stage workflows.
- Redesign `emit-fix-constraints.test.sh`: assert both stage files emitted, `__TARGET_DIR__` fully substituted (no residual placeholder), refuse-if-exists (exit 66), trigger-block anchored greps (`pull_request` in A, `workflow_run` in B — anchored on syntactic constructs, not prose, per the `pull-request-target`-in-comment false-match learning), and a **forbidden-pattern** grep proving Stage B contains no `bun install` / no PR-script execution. Keep `parity.test.sh` green (templates ↔ dogfood copies in sync).

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
- `knowledge-base/engineering/architecture/diagrams/model.c4` + `views.c4` — add the recovery-dispatcher component + edges + view include.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (62 open) — no body/title match for `fix-constraints`, `constraint-scaffold`, or `constraint-gates`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `fix-constraints-stage-a.yml` triggers on `pull_request` (not `issue_comment`/`pull_request_target`), declares `permissions: contents: read` only, and contains **no** `contents: write` / `pull-requests: write` anywhere. Verify: `grep -L 'pull_request_target\|issue_comment' .github/workflows/fix-constraints-stage-a.yml` and a grep that the only `permissions:` block is `contents: read`.
- [ ] `fix-constraints-stage-b.yml` triggers on `workflow_run` (workflows: fix-constraints-stage-a, types: completed), guards `conclusion == 'success'`, and contains **no** `bun install`, no `setup-bun`, **no `actions/checkout` of the untrusted head**, no `git apply`, and no execution of any path from any tree. Verify: `grep -c 'bun install\|setup-bun\|git apply' fix-constraints-stage-b.yml` == 0 and no `actions/checkout` step references `head_sha`/PR head.
- [ ] Stage B sources `head_sha` from `github.event.workflow_run.head_sha` (NOT `meta.json`), resolves `pr_number`/`head_ref` from the event by API, and rejects on `meta.json` mismatch. Covered by a test feeding a mismatched `meta.json` and asserting rejection.
- [ ] Stage B builds the bot-branch commit via the **Git Data API** (blob→tree→commit→ref on parent `head_sha`), never a local checkout+apply.
- [ ] Stage B path validator hard-rejects any file touching `.github/**`, `**/*.cjs`, `constraint-gates.sh`, absolute/`..`-traversal paths, or symlink modes; ALLOWs only `apps/web-platform/{app,components,server}/**` + `.dependency-cruiser-known-violations.json`, fail-closed (any unmatched path rejects the whole artifact). Covered by a shell test feeding (a) out-of-scope, (b) traversal, (c) symlink, (d) in-scope inputs.
- [ ] **Baseline-suppression segregation:** when the artifact mutates `.dependency-cruiser-known-violations.json`, the follow-up PR carries the `constraint-baseline-growth` label + enumerates each newly-suppressed edge in the body. Covered by a test.
- [ ] **Feedback-output preservation:** every terminal state (recovered / rejected-out-of-scope / identity-mismatch / no-fix) posts exactly one deterministic comment on the original PR; none is silent.
- [ ] `emit-fix-constraints.test.sh` asserts both stage templates emit, `__TARGET_DIR__` fully substituted, refuse-if-exists (exit 66), and Stage B template contains no `bun install`. `parity.test.sh` green.
- [ ] `boundary.test.sh`, `generator.test.sh`, `components.test.ts`, and the C4 tests (`c4-code-syntax.test.ts`, `c4-render.test.ts`) pass.
- [ ] ADR-074 exists (status accepted) with the Alternatives table; ADR-071 recovery paragraph points at ADR-074. `model.c4` renders the recovery-dispatcher component + edges (C4 render test green).
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
**Status:** reviewed (in-pass sweep + `soleur:engineering:cto` spawned)
**Assessment:** CTO approves the direction (net security improvement over #5804) and surfaced **three P0s now folded into the plan**: (P0-1) Stage B sources `head_sha`/`pr_number`/`head_ref` from the **trusted event**, never the attacker-controlled `meta.json` (cross-check + reject on mismatch; `workflow_run.pull_requests` is empty for fork PRs); (P0-2) build the bot commit via the **Git Data API** (Stage A uploads full post-image file contents, not a diff) so the untrusted-checkout sink is *structurally absent* and the diff-parser attack class (rename/symlink/`..`) is dissolved — this is the load-bearing ADR-074 decision; (P0-3) **baseline-suppression** is a verify-passing attack (the agent can green the gate by whitelisting a real leak into `.dependency-cruiser-known-violations.json`) — Stage B segregates baseline-mutating patches to heightened review. P1 carry-overs folded: bot self-trigger loop guard, per-head-SHA dedup concurrency, feedback-output preservation, and re-running the **full** `constraint-gates.sh` (not bare `depcruise`) for the blind-gate self-check. **Routing note:** at review/deepen, `security-sentinel` MUST be tasked explicitly with the GHA-workflow-injection surface (`workflow_run` artifact trust, fork-secret exposure, CodeQL `untrusted-checkout-*` semantics) by name — `infra-security` is Cloudflare-scoped and is the wrong fit; `data-integrity-guardian` owns the baseline-suppression call. At single-user-incident threshold, deepen-plan's triad + review-time `user-impact-reviewer` + `security-sentinel` provide the deep review; the `untrusted-checkout-toctou` class is named in every security spawn prompt.

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
- **Same-repo PR, gate red, auto-fixable:** Stage A fixes + verifies green + uploads patch; Stage B validates + applies + opens follow-up PR; original PR gets the link comment.
- **Same-repo PR, gate red, NOT auto-fixable:** agent makes no/insufficient edit; gate still red → no artifact → Stage B no-op; Stage A logs give-up.
- **Fork PR:** no key in Stage A → agent skipped → no artifact → Stage B no-op.
- **Malicious artifact (file path = `.github/workflows/**`, `..` traversal, or symlink mode):** Stage B path validator rejects pre-write, comments, no commit. (Security regression test — out-of-scope / traversal / symlink inputs.)
- **Fork-controlled `meta.json` redirects at a victim PR:** Stage B resolves identity from the event + rejects on `meta.json` mismatch — never targets a PR the artifact claims. (Identity-mismatch test.)
- **Baseline-suppression:** agent whitelists a leak into the baseline JSON → Stage B labels `constraint-baseline-growth` + enumerates new edges for heightened review. (Baseline-mutation test.)
- **head moved after Stage A (TOCTOU attempt):** Stage B builds the commit on the recorded immutable `head_sha` from the event via the Git Data API — never on a surprise tree; no mutable ref is ever resolved.
- **Scaffold emit:** both stage templates emitted with substituted `__TARGET_DIR__`; refuse-if-exists on re-run.

## Alternative Approaches Considered
| Approach | Verdict |
|---|---|
| Single-job `issue_comment` with job-level `permissions: {}` on the agent job | **Rejected.** CodeQL keys on the *trigger* being privileged (issue_comment carries secrets + grants write), not job-perm downscoping. Untrusted-checkout-in-privileged-trigger stays red. |
| SHA-pin + `--ignore-scripts` + base-branch gate (targeted hardening) | **Rejected** (per issue). Closes TOCTOU + postinstall but leaves untrusted-code-with-secrets execution → CodeQL stays red. (We still adopt SHA-pin + `--ignore-scripts` as defense-in-depth.) |
| Egress-restricted self-hosted runner for Stage A | **Deferred** (Soleur-only, heavy). The capped key is the v1 containment. → tracking issue. |
| Comment→label→`pull_request:[labeled]` hybrid (preserves on-demand `/soleur fix constraints`) | **Deferred.** Preserves the #5791 comment UX with a CodeQL-clean labeling workflow (no checkout/exec), but adds a 3rd workflow. v1 ships zero-touch auto-recovery. → tracking issue. |
| Pure-Contents-API patch application (no head checkout in Stage B) | **Documented fallback** in ADR-074 if CodeQL flags Stage B's immutable-SHA checkout. More complex (parse diff → blobs/tree). |

**Deferrals → tracking issues (create with re-eval criteria + milestone from roadmap.md):** egress-restricted runner; comment→label hybrid; (if Anthropic Admin-API mint proves un-automatable) the capped-key rotation runbook.

## Risks & Mitigations
- **Baseline-suppression verify-passing attack (CTO P0-3):** the agent greens the gate by whitelisting a real client→server-secret leak into `.dependency-cruiser-known-violations.json` rather than fixing it; the non-technical founder reviewing the follow-up PR can't tell. Mitigation: Stage B labels/segregates baseline-mutating recoveries + enumerates each new suppressed edge for heightened review; `data-integrity-guardian` owns this at review.
- **CodeQL still flags Stage B even via Git Data API** (no checkout exists, but the broader `untrusted-checkout-high` query is config-dependent). Mitigation: the Git Data API design has *no checkout step to flag*; the post-merge 0-alerts AC is the proof. There is no remaining "checkout the head" path to fall back from — this IS the safe primary.
- **CodeQL `actions` scanning not enabled** (advanced setup removed in 77c2376). Mitigation: Phase 0.2 verifies/enables; else the 0-alerts AC is dashboard-verified with a note.
- **Auto-recovery noise** (agent fires on every red-gate PR). Mitigation: gate is informational + rarely trips; agent only runs when gate is red; bot-branch is excluded from re-triggering Stage A (loop guard). Trade-off noted in ADR-074.
- **Accepted residual:** `ANTHROPIC_API_KEY` runs over untrusted code in Stage A. Mitigation: capped/rotatable per-tenant key with hard spend cap bounds exfil to spend.
- **Follow-up PR created by GITHUB_TOKEN doesn't re-run CI.** Mitigation: Stage A pre-verified the gate green; the follow-up PR is a delivery vehicle, not the verification point. Documented in ADR-074.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's is filled; threshold = single-user incident.)
- **Do NOT name a `download-artifact` SHA from memory** — pin from `gh api repos/actions/download-artifact/git/refs/tags/v4` at /work. The repo has no existing precedent to copy.
- **claude-code-action `claude_args` ≠ the `claude` CLI flags** — reuse the held CI-validated string verbatim; do not re-derive flags.
- **`pull-request-target` in a workflow *comment* false-matches a forbidden-literal grep** — anchor trigger-presence greps on syntactic constructs (`^on:`-block keys), and write any explanatory prose with the hyphenated `pull-request-target` form (#5804 learning).
- **Stage B must never `actions/checkout` the untrusted head or `git apply` a diff** — both reintroduce the sink/parser surface. Build via the Git Data API (blob→tree→commit→ref). The forbidden-pattern test guards `bun install`/`setup-bun`/`git apply`/`checkout-of-head`.
- **Routing identity from the event, not the artifact:** `head_sha`/`pr_number`/`head_ref` come from `github.event.workflow_run.*` + API resolution; `meta.json` is a cross-check that must MATCH or the run rejects. A fork-controlled `meta.json` redirecting at a victim PR is the live vuln this guards.
- **Baseline-suppression is a verify-passing attack:** "gate green" is satisfiable by whitelisting a real leak into `.dependency-cruiser-known-violations.json`; segregate + heightened-review any baseline-mutating recovery (the founder reviewer can't tell fix from leak).
- **GITHUB_TOKEN-created follow-up PR triggers no CI** — by design; do not gate the follow-up PR on a CI re-run that never fires (Stage A pre-verified green).
- **Path allowlist fails closed:** any unmatched / `..`-traversal / symlink-mode path rejects the whole artifact, never partial.
