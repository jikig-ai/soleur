---
title: Unified CI Deploy Stall Hardening
status: ready-to-plan
created: 2026-05-13
related_issues: ["#3712", "#3704", "#2207"]
related_prs: ["#3706"]
related_specs: ["feat-one-shot-3704-harden-release-pipeline"]
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
---

# Spec: Unified CI Deploy Stall Hardening

## Problem Statement

Three open GH issues describe one failure mode (`ci-deploy.sh` hanging on prod):

- **#3712 (p1, follow-through):** `apply-deploy-pipeline-fix.yml` auto-apply failed for merge `dc7c8b71` (PR #3706) with `dial tcp 135.181.45.178:22: i/o timeout`. PR #3706 (the durable fix for #3704) is merged but not installed on prod. Operator must manually run `terraform apply -target=terraform_data.deploy_pipeline_fix` from an allowlisted IP.
- **#3704 (p1):** Web Platform Release stalled at 900s for v0.81.0 + v0.82.0; prod was stranded on v0.80.4. Prod has since reached v0.82.1, but the stall protection (#3706's wrapper + TERM trap) is not yet active on the server. Closes once 2 organic releases verify the protection runs.
- **#2207 (p3, deferred from PR #2187):** Proposed `systemd-run --scope --property=TimeoutSec=600` belt-and-suspenders. The #3706 deepen-pass §49-59 ("systemd-run rejection rationale") explicitly rejected `systemd-run --scope` on polkit/non-TTY grounds for `User=deploy` (the webhook user) and chose `timeout(1)` instead. `ci-deploy-wrapper.sh` IS the implementation of #2207's intent via a different primitive.

A cross-cutting infra problem also surfaced: the auto-apply path that should have run #3706 on prod failed because the GitHub Actions runner's outbound IP isn't in `var.admin_ips`. The `apply-deploy-pipeline-fix.yml` workflow ran exactly once (its inaugural invocation, the one that failed). Every future merge touching the 5 trigger files will fail identically until the auto-apply path itself is fixed — but the 2026-03-19 learning explicitly precludes allowlisting GH runner IPs (5000+ rotating ranges).

## Goals

1. Operator-manual install of #3706's already-merged fix on prod, verified via file-SHA + `systemctl is-active` (closes #3712).
2. Passive verification that #3706's protection actually catches the next stall (closes #3704 after 2 organic releases <900s with `exit_code=0 reason=ok`).
3. Comment-close #2207 citing the #3706 deepen-pass rationale.
4. Compliance learning entry at `knowledge-base/project/learnings/compliance/2026-05-13-pipeline-reliability-as-gdpr-art32-control.md` covering Art. 32(1)(d) framing + SIGKILL audit-trail caveat.
5. File a follow-up issue for the Hetzner self-hosted runner that fixes the auto-apply IP-allowlist drift durably.

## Non-Goals

- **No new code in `ci-deploy.sh`, `ci-deploy-wrapper.sh`, `server.tf`, `hooks.json.tmpl`, or any workflow YAML.** #3706 already shipped the engineering fix.
- **No `systemd-run --scope` second-layer wrapper.** Explicitly rejected by the #3706 deepen-pass; `timeout(1)` is the chosen primitive.
- **No Hetzner runner work in this PR.** Separate terraform root, separate destroy runbook, separate ADR — deferred to follow-up issue.
- **No docker-swap atomicity changes** (CLO's availability gap finding). Documented in compliance learning as known-residual; not a code change in this scope.
- **No SIGKILL state-write recovery.** Plan Sharp Edge #5 documents this as accepted status quo; workflow's `elapsed>900s` branch is the load-bearing recovery.

## Functional Requirements

**FR1.** Brainstorm document committed at `knowledge-base/project/brainstorms/2026-05-13-unified-ci-deploy-stall-hardening-brainstorm.md` capturing user-brand-impact framing, domain assessments (CTO + CPO + CLO), key decisions, and capability-gap audit.

**FR2.** Compliance learning entry committed at `knowledge-base/project/learnings/compliance/2026-05-13-pipeline-reliability-as-gdpr-art32-control.md`. Sections: (a) Art. 32(1)(d) framing — release-pipeline reliability as an organizational control when shipping rights-fulfillment code; (b) SIGKILL audit-trail caveat — `reason=running` stays stale if bash dies before trap dispatch; (c) docker-swap availability gap (CLO finding) cross-referenced from this same file.

**FR3.** All three referenced issues (#3712, #3704, #2207) receive a "Bundled scoping" comment linking this brainstorm, spec, branch (`feat-unified-ci-deploy-stall-hardening`), and PR (#3719). No new umbrella issue is created — the brainstorm + spec ARE the bundle's single source of truth.

**FR4.** Follow-up GH issue created for the Hetzner self-hosted runner work — **#3723** (p2-medium). Body references this spec, the 2026-03-19 hidden-dependency learning, and the `hr-every-new-terraform-root-must-include-an` rule.

**FR5.** No operator-facing runbook duplication. #3712's issue body already contains the canonical apply triplet and verification commands; this spec references rather than re-states them.

## Technical Requirements

**TR1.** Branch: `feat-unified-ci-deploy-stall-hardening` (already created). Draft PR: #3719 (already opened).

**TR2.** Files added by this PR (4 only):
- `knowledge-base/project/brainstorms/2026-05-13-unified-ci-deploy-stall-hardening-brainstorm.md`
- `knowledge-base/project/specs/feat-unified-ci-deploy-stall-hardening/spec.md`
- `knowledge-base/project/learnings/compliance/2026-05-13-pipeline-reliability-as-gdpr-art32-control.md`
- (Implicit: `knowledge-base/project/learnings/compliance/` directory creation if not present)

**TR3.** Files NOT modified by this PR: any `apps/web-platform/infra/*` file, any `.github/workflows/*` file, any `plugins/soleur/skills/*` file.

**TR4.** PR body uses `Closes #3712`, `Closes #2207` (the comment-close is the merged-PR-discussion closure), and `Ref #3704` (passive close awaits 2 organic releases).

**TR5.** No new tests required — no code is being changed. `bun test` and `bash apps/web-platform/infra/ci-deploy.test.sh` should still pass unchanged (already verified in #3706).

## Acceptance Criteria

- [ ] All 3 markdown files (FR1, FR2, plus this spec) exist on the feature branch and pass markdown-lint (if a lint hook is configured).
- [ ] Compliance learning's Art. 32(1)(d) framing is ≤900 words (verifiable via `wc -w`; ceiling accommodates Art. 32(1)(d) framing + SIGKILL audit caveat + docker-swap availability gap + atomicity proof + post-apply verification contract) and cites the 5 relevant prior learnings listed in brainstorm `References`.
- [ ] Each of #3712, #3704, #2207 has a "Bundled scoping" comment with the artifact links (verify via `gh issue view`).
- [ ] Follow-up issue for Hetzner runner exists and is linked from the brainstorm's Key Decisions table.
- [ ] PR #3719 body references all four (`Closes #3712`, `Closes #2207`, `Ref #3704`, `Ref #3723` for the Hetzner-runner follow-up).
- [ ] **Operator post-merge (not gating this PR):** run `terraform apply -target=terraform_data.deploy_pipeline_fix` per #3712's body, then verify file-SHA + `systemctl is-active webhook` from an allowlisted IP. After 2 organic Web Platform Release runs report `exit_code=0 reason=ok` <900s, close #3712 + #3704.

## Key Decisions (carry-forward from brainstorm)

Authoritative table lives in the brainstorm `Key Decisions` section. Spec-side index so plan-time readers don't have to re-read the brainstorm to know what's settled:

| # | Decision (one-line) | See brainstorm row |
|---|---|---|
| 1 | #3712 → operator-manual `terraform apply -target=terraform_data.deploy_pipeline_fix` (re-litigating 2026-03-19 GH-runner-IP-allowlist decision is out of scope). | brainstorm #1 |
| 2 | #3704 → passive close after 2 organic releases <900s, `exit_code=0 reason=ok`. | brainstorm #2 |
| 3 | #2207 → comment-close as superseded by `ci-deploy-wrapper.sh` `timeout(1)` primitive. | brainstorm #3 |
| 4 | Compliance learning entry (Art. 32(1)(d) framing + SIGKILL audit caveat) — this PR. | brainstorm #4 |
| 5 | Hetzner self-hosted runner deferred to **#3723** (~€4/mo; cheapest durable fix for auto-apply IP drift). | brainstorm #5 |
| 6 | No bash trap / `set -m` / docker-swap-atomicity code changes — plan Sharp Edge #5 ("SIGKILL → state-stays-running as accepted status quo") is load-bearing. | brainstorm #6 |

## Sharp Edges

1. **#2207 comment-close must cite the exact AC mapping.** The original AC list ("Stalled ci-deploy.sh invocations are SIGTERM'd at 600s", "write_state writes `reason=timeout` when SIGTERM fires", "CI polling detects timeout-reason and fails fast", "Operator runbook updated") maps to #3706's deliverables but with a 900s ceiling (not 600s) and `timeout(1)` primitive (not systemd-run). The close-comment must spell out each AC and how #3706 satisfies it, otherwise future archaeology may re-open the question.

2. **Auto-apply structural failure is silently masked by `/ship` Phase 5.5.** The Drift Gate prompts the operator at PR-merge time, so the workflow's perpetual time-out goes unnoticed in the absence of the Hetzner runner. Document this in the follow-up issue's body so the next deploy-pipeline-fix change doesn't surprise the operator.

3. **`scheduled-terraform-drift.yml` files an issue every 12h on drift but does NOT attempt apply.** Until #3712's apply runs, the drift cron will repeat-file `infra-drift`-labeled issues every 12h. Operator should run the apply within the first cron cycle to avoid issue-spam.

4. **No code change ≠ no risk.** The act of comment-closing #2207 changes nothing in main but may signal to future-readers that the systemd-run path is "considered and rejected." Anchor that signal to the plan §49-59 ("systemd-run rejection rationale") citation so it cannot be re-litigated from cold-start.

## Risks

- **Operator forgets to run the apply.** Mitigated by /ship Phase 5.5 Drift Gate + 12h `scheduled-terraform-drift.yml` cron + this PR's brainstorm being the canonical bundle reference.
- **2 organic releases don't happen within reasonable window.** Acceptable; #3704 stays open as a tracking issue until verified. The protection is already merged, just not yet installed.
- **Hetzner-runner follow-up never gets scheduled.** Auto-apply remains structurally broken; every drift-prone PR pays the manual-apply cost. Acceptable given /ship Phase 5.5 catches it pre-merge.

## Domain Review (carry-forward)

**Engineering (CTO):** Reviewed wrapper primitive choice + auto-apply allowlist options + sequencing. Recommended Hetzner self-hosted runner; bundled vs. split per follow-up issue. Reconciled initial `systemd-run --scope` recommendation against deepen-pass rejection: ship `timeout(1)`-only; document the SIGKILL gap as known-residual.

**Product (CPO):** Endorsed sequencing #3712 > #3704 > #2207. Current stale-`/health` UX acceptable at pre-beta. Revisit user-facing signal when first regulated user-facing surface ships.

**Legal (CLO):** No DB migration in `ci-deploy.sh` → no schema-vs-binary split-brain. Docker-swap window is an Art. 32 availability concern (not data exposure). DSAR SLA not breached. Filed Art. 32(1)(d) organizational-measure concern → compliance learning entry. SIGKILL audit-trail-completeness caveat included in same entry.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-13-unified-ci-deploy-stall-hardening-brainstorm.md`
- #3706 plan: `knowledge-base/project/plans/2026-05-12-fix-harden-web-platform-release-pipeline-3704-plan.md` (§49-59 "systemd-run rejection rationale"; §190 "risk table")
- #3706 spec: `knowledge-base/project/specs/feat-one-shot-3704-harden-release-pipeline/spec.md`
- Compliance learning (this PR): `knowledge-base/project/learnings/compliance/2026-05-13-pipeline-reliability-as-gdpr-art32-control.md`
