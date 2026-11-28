---
title: "Server-side bot self-arm and the agent-review merge gate"
status: active
date: 2026-11-17
---

# ADR-328: Server-side bot self-arm and the agent-review merge gate

## Context

Follow-up to #12656 (PR #12706, CTO ruling R2, 2026-11-13). The review-evidence arm check (`plugins/soleur/skills/review/references/review-evidence-comment.md#arm-check`) now gates every agent arm site in the skills, but first-party bot paths self-arm server-side with no evidence check:

- `.github/scripts/bump-inngest-bootstrap-pin.sh` (`gh pr merge … --auto`)
- `.github/actions/bot-pr-with-synthetic-checks/action.yml` (`gh_app pr merge … --auto`)
- `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` (`enablePullRequestAutoMerge`)

At least six bot PRs since 2026-11-01 touched `apps/web-platform/infra/` with zero Review-Evidence comments. The arm-check site list recorded the gap; it did not close it. #12712 (delegated-envelope `gh pr merge --auto`) is explicitly out of scope here.

## Decision

1. **Repo-wide arm/merge walker with exemption ledger.** Every merge site in the repo either invokes the arm check in the same scope or carries a row in `knowledge-base/engineering/review-evidence-exemption-ledger.yml` (site, surface, reason, owner, added, ruling). A test (`plugins/soleur/test/review-evidence-arm-walker.test.sh`) enforces this on every PR.

2. **Domain-surface control.** A first-party bot PR touching a domain surface (`infra/`, `.github/workflows/`, `cloud-init*`, migrations, terraform, auth/secrets/validation code) must not self-arm: the bot refuses to call `enablePullRequestAutoMerge`/`gh pr merge --auto` and leaves the PR unarmed with a `needs-review` label so `soleur:review` picks it up. Refusal is the mechanism; routing is the workflow. This aligns with #12656 R1 (bot PR with no evidence goes to `soleur:review` first).

3. **Hook re-arm text.** `.claude/hooks/pre-merge-rebase.sh` re-arm guidance points at `review-evidence-comment.md#arm-check`, as `sync-pr-behind.sh` and `scripts/merge-queue-jump.sh` already do.

4. **Main/master carve-out** is tracked in #8791; this ADR links it and does not duplicate it. The walker must cover generated templates too, since `soleur:schedule`-generated workflows self-arm from `main`.

## Ledger governance

- Only the CTO agent may add rows, and only in a PR citing this ADR.
- Rows with `surface != none` may not use `synthetic-checks-only` or `infra-pin-bump`; they must use `routed-to-review`.
- Reason closed set: `synthetic-checks-only`, `infra-pin-bump`, `scheduled-cron`, `legacy-pre-gate` (with mandatory `sunset:` date).

## Alternatives considered

- Hard CI block on domain-surface self-arms: rejected because it stalls bot pipelines with no recovery path.
- Markdown-table ledger: rejected because the walker needs machine parsing and exact row shape.
- Deferring the ADR: rejected because the walker's reason-code set and governance need a stable citation target.

## Consequences

- Three named bot sites seed the ledger with `legacy-pre-gate` rows (with sunset dates) until they are converted to refuse-on-domain-surface.
- #12712 (delegated envelope) remains separate and follows this ADR's ledger schema as a consumer.
- Every future merge site must either run the arm check or carry a ledger row; CI enforces via the walker test.