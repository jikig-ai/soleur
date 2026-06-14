---
plan: knowledge-base/project/plans/2026-06-14-fix-cron-egress-firewall-remote-exec-apply-plan.md
issue: 5279
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — fix(infra): cron_egress_firewall remote-exec apply

Derived from `2026-06-14-fix-cron-egress-firewall-remote-exec-apply-plan.md`. Phase 0 is a BLOCKING diagnosis gate — Phase 1 cannot begin until the exact failing command is captured.

## Phase 0 — Make the failing command visible (BLOCKING)

- [ ] 0.1 Reproduce with output un-suppressed and capture the exact failing assertion + its stderr.
  - [ ] 0.1.1 Confirm the resource is `tainted` (so the next apply replaces it).
  - [ ] 0.1.2 Preferred: read-only on-host trace over the operator admin-IP path — run server.tf:810-842 assertions verbatim under `bash -x`; record the first non-zero command.
  - [ ] 0.1.3 Record the failing command + stderr into spec session-state and the plan's Research Reconciliation; name the sub-hypothesis (4a-4e).
- [ ] 0.2 Confirm `ci_ssh` token freshness (read-only Doppler `prd_terraform`); check CF Access service-token expiry via Cloudflare MCP. File a SEPARATE issue if expired.
- [ ] 0.3 Confirm the 6 SSH-provisioned siblings pass in the same run (scope boundary; do not touch them).
- [ ] **Phase 0 exit gate:** exact failing command named with stderr before Phase 1.

## Phase 1 — Fix the identified failing assertion (branch on Phase 0)

- [ ] 1.1 Write the RED regression test in `apps/web-platform/infra/cron-egress-firewall.test.sh` reproducing the Phase 0 condition (must FAIL pre-fix).
- [ ] 1.2 Apply the minimal fix per the matched sub-hypothesis (4a nft format-agnostic / 4b EnableIPv6 gate / 4c loader die / 4d container probe / 4e host egress) — fix the firewall/format, NEVER weaken a load-bearing containment invariant.
- [ ] 1.3 Confirm the test now PASSES (GREEN) and the non-vacuous negative still fails (AC3).
- [ ] 1.4 `bash -n` + `shellcheck` clean on any edited `.sh`.

## Phase 2 — Harden observability (always)

- [ ] 2.1 Wrap every `grep -q`/check-active/`inspect` assertion in server.tf:810-842 with a unique `ASSERT-FAILED: <name>` sentinel before `exit 1`.
- [ ] 2.2 Confirm/add an apply-time failure mirror to the operator's no-SSH observability plane (Sentry/Slack).
- [ ] 2.3 Document the un-suppression technique in `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`.

## Pre-merge gates

- [ ] AC1-AC7 satisfied (Phase 0 captured, regression test, non-vacuous fix, sentinels, sibling boundary, CPO sign-off, `Ref #5279` not `Closes`).
- [ ] Multi-agent review (`user-impact-reviewer` invoked — single-user-incident threshold).

## Post-merge gates

- [ ] AC8 apply green at `terraform_data.cron_egress_firewall` (`gh run list ... --jq '.[0].conclusion'` → success).
- [ ] AC9 firewall verified live (DOCKER-USER jump + service active, read-only).
- [ ] AC10 `gh issue close 5279`.
