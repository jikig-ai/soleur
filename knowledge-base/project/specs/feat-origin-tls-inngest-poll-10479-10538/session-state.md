# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-13-feat-origin-tls-cleanup-and-inngest-public-poll-plan.md
- Status: complete
- cto_spawns=2 (one pre-plan by the one-shot runner, one batched in planning)

### Errors
- decision-challenges row of class `record` rejected by the ruling gate; removed.
- ADR-321 amendment renumbered to item 13.
- Plan review and deepen scaled down (machine saturated).
- lint-encryption-posture.py is red on origin/main (rows 6 and 7 expired 2026-11-12) until PR #12733 lands.

### Decisions
- #10479: adopted rule dcb85b75 becomes strict for app.soleur.ai only; canary and strict gated rules and both variables removed; `[ack-destroy]` in the removing commit; port 80 stays.
- #10538: remedy (c) sdk_url -> https://app.soleur.ai/api/inngest; live only at the owner's inngest-host-replace.
- One Better Stack logs alert on SOLEUR_INNGEST_SERVER_PROBE registry_fns; FU-1 adds sync evidence before the replace.
- Ledger: row 7 converted to measured TLS; row 6 stays an exception (expires_on owned by PR #12733).
- Per-host pre-merge evidence: LB pool snapshot + Better Stack per-host counts + public probes.

### Components Invoked
soleur:plan, soleur:deepen-plan, learnings-researcher, repo-research-analyst, cto, architecture-strategist, code-simplicity-reviewer, cpo, framework-docs-researcher, general-purpose.

## Operator Constraints

- constraint: No Doppler writes, no apply/cutover/release dispatches, no host replace, no merge; STOP BEFORE MERGE at green CI + ready-for-review.
- constraint: Never edit or push PR #12733 or worktree chore-enqueue-evidence; build on #12733's ledger renewal, rebase cleanly whichever merges first.
- constraint: prepush-secret-scan.sh verdict=CLEAN before every push.
- ci-is-the-gate: do NOT run test-all.sh, run-registered-suites.sh or the full/affected battery locally. Single test files only.

## Work Phase
- Status: complete (all workstreams committed; origin/main with #12733 merged in, ledger row 7 conflict resolved to the conversion)
- Affected gate: `gate-or-skip.sh` reported `battery-owed: OWED` for the infra surface and started `test-all.sh --affected`; killed by PID per the operator's no-local-battery constraint. Carried by the PR's CI `infra-validation` / `deploy-script-tests` runs, which must be green before ready.
- Follow-ups: #12742 (leg-2 delivery), #12743 (port 80 / AOP), #12744 (handshake-burst alert), #12745 (lb-pool-health reader).
