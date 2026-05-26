---
title: "ADR amendment required when reversing a documented decision in the same PR; destroy-guard empty-string bypass"
date: 2026-05-16
category: workflow-failures
module: ship, infra, ci
tags:
  - adr
  - workflow-gap
  - terraform
  - auto-apply
  - destroy-guard
  - bash-arithmetic
  - silent-failure
  - multi-agent-review
related:
  - knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md
  - knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md
  - knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md
issues:
  - 3895
  - 3896
  - 3903
  - 3910
---

# ADR amendment when reversing decisions, and the destroy-guard empty-string bypass

Two distinct compound-worthy patterns surfaced while pivoting PR #3903 from a verify-only follow-through workflow to an auto-apply-on-merge terraform workflow:

## Pattern 1 — ADR amendment is required when reversing a documented decision in the same PR

**Symptom.** PR #3903 was framed as "auto-apply on merge, mirroring ADR-031." The actual contract drift only surfaced when the multi-agent review's git-history-analyzer pulled up the live ADR-032 text on `main`:

> *"Apply is operator-only. The auto-apply patterns in `apply-deploy-pipeline-fix.yml` and `apply-sentry-infra.yml` … do NOT apply here because the ruleset mutation is a write-to-prod-policy event requiring single human attestation per `hr-menu-option-ack-not-prod-write-auth`."*
> — `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` lines 87-93 (added by PR #3891, merged 2026-05-16)

That text was on `main` the same day PR #3903 was authored. Shipping the workflow without touching ADR-032 would have left a `git grep` trap: any future agent reading `infra/github/` would find an ADR that says "no auto-apply" alongside a workflow that auto-applies, and treat the older ADR as authoritative.

**Why this happens.** `/ship` Phase 7 generates follow-through tickets without auditing the surrounding ADRs/plans. When a follow-up PR reverses one of those decisions, no gate prompts "amend the ADR you're reversing." The pivot felt like an honest workflow fix (eliminate the manual step); the documentation debt was invisible until review.

**How review caught it.** `git-history-analyzer` was the only one of four reviewers to surface it. The other three (security-sentinel, pattern-recognition, code-quality) approved the workflow in isolation because they read the new file but not the ADR it superseded. The defect class is **self-claimed cross-artifact contract drift** (see `2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md`): the workflow header claims "mirroring ADR-031" but the local ADR-032 actively contradicted that framing.

**Prevention.**

1. **Ship-time / plan-time gate.** Before merging a PR that touches `apply-*.yml` or any terraform root, grep `knowledge-base/engineering/architecture/decisions/ADR-*.md` for the same root path or resource type. If a hit exists and the PR doesn't modify it, surface as a workflow-gap warning. Cheapest implementation: a `git diff --name-only origin/main...HEAD` filter + an ADR grep in `/ship` Phase 5.5.
2. **Author-time discipline.** When pivoting a follow-through ticket whose body cites a specific hard-rule or ADR, treat the cited document as in-scope for the same PR. Amending an ADR is ~30 lines and is the contract source-of-truth — leaving it stale is more expensive than fixing it inline.
3. **`/soleur:work` should run a "sibling-ADR scan" at Phase 1** for any PR that touches a path covered by an existing ADR's path-globs (terraform roots, security workflows, etc.).

## Pattern 2 — Destroy-guard empty-string bypass class

**Symptom.** The `terraform plan` step in `apply-github-infra.yml` had the pattern:

```bash
set -uo pipefail            # -e dropped so we can capture rc=$? from plan
doppler run -- terraform plan -out=tfplan
rc=$?
# ... rc check ...
destroy_count=$(terraform show -json tfplan | jq '[.resource_changes[]? | ...] | length')
if [[ "$destroy_count" -gt 0 ]] && [[ "$ack_destroy" != "true" ]]; then
  # destroy guard
fi
```

With `set -e` disabled, if either `terraform show` or `jq` failed, `destroy_count` would be the empty string. `[[ "" -gt 0 ]]` in Bash evaluates to FALSE — the guard silently lets a destructive plan through.

**Root cause.** Bash's `[[ <var> -gt N ]]` does arithmetic context coercion: empty string → 0. There is no fail-on-empty mode. `set -e` would have caught the upstream pipe failure, but it was deliberately disabled to allow the `rc=$?` capture. The disablement window extended past the `rc` check by accident.

**Fix shape.**

```bash
# After the rc check, re-enable -e so subsequent failures fail-fast.
set -e
destroy_count=$(terraform show -json tfplan | jq '...')

# Belt-and-braces: validate destroy_count parsed as a number.
if [[ ! "$destroy_count" =~ ^[0-9]+$ ]]; then
  echo "::error::destroy_count parse failed (jq returned: '${destroy_count}')."
  exit 1
fi
```

The numeric regex check is the load-bearing defense — `set -e` re-enable is belt-and-braces. Both together close the failure mode regardless of which upstream step fails.

**Generalized pattern.** Any time a Bash script uses `[[ "$VAR" -gt|-lt|-eq|-ne N ]]` where `$VAR` came from a piped command:

- If `set -e` is OFF, validate `$VAR` matches `^[0-9]+$` before the arithmetic test, OR
- Re-enable `set -e` immediately after the rc-capture window closes.

`apply-sentry-infra.yml` has the same `set -uo pipefail` pattern but doesn't re-validate; it's vulnerable to the same class. Worth a follow-up audit (filed inline as a P3 in PR #3903's review notes; not load-bearing for Sentry because `sentry_cron_monitor` deletes are rarer and recoverable).

**Why this is compound-worthy.** Bash arithmetic context's empty-string-to-zero coercion is documented but not widely internalized. Multi-agent code-quality reviewer caught it in seconds; manual review would have missed it because the `set -e` deviation looked intentional (it WAS intentional, just incomplete).

## Session Errors

1. **Authored auto-apply workflow without amending the contradicting ADR-032.** — Recovery: ADR-032 amended with a "Revised 2026-05-16 (PR #3903)" section in the same commit. — **Prevention:** `/ship` Phase 5.5 should run an ADR-surface grep when the diff touches `infra/**`, `terraform_data.*` triggers, or `apply-*.yml` workflows. A detected match with no diff-side edit should surface as a workflow-gap warning. This is also the systemic fix tracked in #3910 (`/ship` Phase 7 follow-through generator gap).

2. **Destroy guard silently bypassed when `jq` returns empty.** — Recovery: re-enabled `set -e` after `rc=$?` capture + added explicit numeric regex validation on `destroy_count`. — **Prevention:** a Bash-style lint rule (`shellcheck` plugin, custom semgrep, or a new pre-merge hook) that flags `[[ "$VAR" -gt N ]]` where `$VAR` is assigned from a pipe within a `set -uo pipefail` (no `-e`) block without an explicit numeric guard. Same class affects `apply-sentry-infra.yml` and likely other terraform-apply workflows.

3. **Initial PR scaffold (verify-only workflow) was sized for the wrong problem.** PR #3903 originally scaffolded a `workflow_dispatch`-only verifier for #3896's verdict-only contract. The user surfaced that #3895's "operator runs terraform apply" classification was itself the workflow gap. — Recovery: pivoted the PR mid-flight to the auto-apply workflow. — **Prevention:** the `/soleur:go` routing + brainstorm flow should weight "is this manual-because-of-historical-classification?" before scaffolding artifacts that work around the manual step. A Soleur founder-user can't reasonably run `terraform apply` from a terminal; the founder-user-impact lens (`hr-weigh-every-decision-against-target-user-impact`) should fire on any "operator must do X manually" task.

## Cross-references

- ADR-031 (Sentry as IaC) — the precedent for "PR merge IS attestation" applied here.
- ADR-032 (revised in PR #3903) — the original "operator-only" framing now superseded for `infra/github/`.
- `apply-sentry-infra.yml` — the canonical apply-on-merge template.
- `apply-github-infra.yml` — this PR's new workflow.
- Issue #3910 — `/ship` Phase 7 follow-through generator must price auto-apply-on-merge.
- Issues #3895, #3896 — closed as superseded by #3903.
- Learning `2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md` — same defect class (cross-artifact contract drift caught by multi-agent review).
