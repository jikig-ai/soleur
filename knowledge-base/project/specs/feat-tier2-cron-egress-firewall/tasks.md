---
title: "Tasks — Tier-2 Cron Egress Firewall + Restore Paused Crons"
issue: "#5046"
branch: feat-tier2-cron-egress-firewall
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-09-feat-tier2-cron-egress-firewall-plan.md
created: 2026-06-09
---

# Tasks

Derived from the finalized (post-plan-review) plan. **This branch = PR-1.** PR-2 (firewall) is a
sequenced follow-on branch — deepen-plan when reached. content-publisher→GHA is deferred (follow-up).

## Phase 1 — PR-1: Restore allowlistable crons + narrow the cron token (THIS branch)

### 1.0 Per-cron containment re-triage (evidence-first)
- [ ] 1.0.1 For each of the 11 in `TIER2_DEFERRED_CRONS` (`_cron-shared.ts:196`), read the cron's prompt and enumerate its actual bash surface (the `gh`/`git`/shell verbs it issues).
- [ ] 1.0.2 Classify each as **allowlistable** (finite verb set, model on `cron-roadmap-review`) or **needs-firewall** (broad/dynamic bash). Record the evidence per cron for the PR body (AC1).
- [ ] 1.0.3 Do NOT assume the "likely" candidates — let evidence decide; flag if `bug-fixer` (CPO #1) lands in needs-firewall.

### 1.1 Restore the allowlistable subset
- [ ] 1.1.1 Add a `CRON_BASH_ALLOWLISTS[<cron>]` entry for each allowlistable cron (`_cron-claude-eval-substrate.ts:139`), modeled on the `cron-roadmap-review` entry.
- [ ] 1.1.2 Remove each restored cron from `TIER2_DEFERRED_CRONS` (`_cron-shared.ts:196`).
- [ ] 1.1.3 Update `cron-shared.test.ts` to assert the defer-set membership + allowlist for restored crons (mirror existing tests).

### 1.2 Interim stopgap for the live 4 (decide in this PR)
- [ ] 1.2.1 Decide: dry-run `content-publisher` (`X_ALLOW_POST`/`LINKEDIN_ALLOW_POST`/`BSKY_ALLOW_POST` → false) OR accept the bounded window with PR-2 expedited. Record choice + rationale in the PR body (AC4).
- [ ] 1.2.2 If dry-run chosen: edit `cron-content-publisher.ts` flags.

### 1.3 Narrow the cron token (folded from former PR-4)
- [ ] 1.3.1 Add an additive `permissions?` option to `mintInstallationToken` (`_cron-shared.ts:119`), defaulted to `{ contents: "write", issues: "write" }` repo-scoped to soleur.
- [ ] 1.3.2 Thread the `permissions`/`repositories` POST body into `generateInstallationToken` (`github-app.ts:708-733`), additive + defaulted; do NOT touch the ~10 non-cron call sites.
- [ ] 1.3.3 Test the override: seed a bogus ambient `GH_TOKEN`, assert the subprocess sees the **minted narrowed** token (`cron-shared.test.ts`).

### 1.4 Verify + ship
- [ ] 1.4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 1.4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-shared.test.ts` green.
- [ ] 1.4.3 PR body: per-cron triage evidence (AC1), token narrowing note, interim-stopgap decision (AC4). `Closes #5046`? → NO (umbrella; use `Ref #5046`, close after PR-2).
- [ ] 1.4.4 Post-merge: validate each restored cron via `/soleur:trigger-cron <event>` — output issue appears + `runHookSelfTest` passes (AC6).

## Phase 2 — PR-2: Container egress firewall (FORWARD EPIC — separate branch, deepen-plan first)

- [ ] 2.1 deepen-plan PR-2 (firewall mechanism, exact allowlist host set incl. Inngest + Sentry-ingest, re-resolve timer, DOCKER-USER rule shape, host-egress-unaffected test).
- [ ] 2.2 New `terraform_data "cron_egress_firewall"` in `server.tf` (DOCKER-USER nftables, `{rules_hash, server_id}` trigger, SSH provisioner per `docker_seccomp_config`).
- [ ] 2.3 `cron-egress-nftables.sh` + periodic IP re-resolve timer; mirror into `cloud-init.yml`.
- [ ] 2.4 `egress_blocked` Sentry issue alert (`issue-alerts.tf`); Inngest throw on block.
- [ ] 2.5 Restore the needs-firewall crons (from 1.0) once the boundary is proven via trigger-cron.
- [ ] 2.6 Add to `apply-web-platform-infra.yml` `-target=` set; verify deny + host-egress-unaffected.

## Deferred (tracked follow-up)
- content-publisher → ephemeral GHA (Option C). Revisit only if PR-2's allowlist is insufficient for it.
