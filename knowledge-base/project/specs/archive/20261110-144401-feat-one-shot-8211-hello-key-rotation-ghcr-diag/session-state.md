# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-09-feat-relay-hello-key-rotation-ghcr-push-diagnostics-plan.md
- Status: complete
- cto_spawns=1

### Errors

None. Deepen-plan fan-out narrowed to lens-fit reviewers because the machine is saturated; deterministic gates passed.

### Decisions

- Item A (PR B / next arc step): Ruled by CTO agent, 2026-11-10. PR B was the web-2 serve flip, already run 2026-11-08. This branch is the next PR. Remaining before external users: one real proxied session showing accepted greater than 0, and the key move-out tracked in issue 12538. Issue 12167 closes at ship with evidence.
- Item B: B3, one accept-only slot PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO, never used to sign, absent by default, ships dark. Boot fingerprint line relay_hello_key_fp. ADR-323 Decision 9 amended.
- Item E (signed probe hello): deferred to issue 12539.
- Item C: diagnostics only, SOLEUR_GHCR_PUSH_FAILED marker step after a failed build-and-push, new runbook. Budget raise is operator money decision.
- Item D: dropped; PR 12489 by another session fixes the pin drift.
- D1: release build step gets DOCKER_BUILD_RECORD_UPLOAD and DOCKER_BUILD_SUMMARY set to false. Operator chose to keep it in this PR (2026-11-10) and authorized deleting the existing build-record artifacts. Token rotation is the operator's.

### Components Invoked

soleur:plan, soleur:gdpr-gate, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto, soleur:product:cpo, soleur:legal:clo, research and review agents.

## Operator Constraints

- constraint: Never git stash. No secrets on command lines, never print a secret value. Run the prepush secret scan, verdict CLEAN, before every push.
- constraint: The machine is saturated. Do NOT run test-all.sh, run-registered-suites.sh or the full or affected gate locally, CI is the gate, single test files only. Scratch and logs go under var tmp.
- constraint: STOP BEFORE MERGE. Merging production-changing work is owner-gated.
- constraint: Owner-gated, never run any Doppler write, cutover dispatches, host replace rotate create, apply dispatches, flip.sh, cf-lb-overlay dispatches, any web-platform-release dispatch or release re-run, every RF step, any billing budget change.
- constraint: Technical forks go to the CTO agent and legal ones to the CLO agent. Never ask the operator a technical question.
- ci-is-the-gate: CI is the gate, single test files only, do NOT run test-all.sh or the full or affected gate locally.
