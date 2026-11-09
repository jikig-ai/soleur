# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-09-feat-signed-relay-hello-pre-tls-allowlist-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=1 (batched F1-F4 rulings by the planning subagent)

### Errors
None blocking. The planner grepped the sharp-edges catalogue instead of reading it whole, ran a scoped deepen pass, and used a provisional ADR-323 ordinal (ADR-322 was last on origin/main).

### Decisions
- Destroy guard: dedicated counter relay_hello_key_changes with its own non-ackable HALT (F1).
- Presence preflight: add PROXY_HELLO_HMAC_KEY to REQUIRED in verify-required-secrets.sh (F2).
- Pre-TLS allowlist via prependListener on the https server with socket.destroy(); ci-deploy.sh untouched (F3).
- Bounded reporting 5 events per 60 s per reason plus counter; replay entry expires at ts + 31 s; one shared canonical-string module (F4).
- All ten added guards get sandbox mutation rows in the commit that adds them.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto, soleur:product:cpo, plan-review panel, security-sentinel, test-design-reviewer.

## Operator Constraints

- constraint: Merge, release dispatch, apply dispatch, Doppler writes, flip.sh and cf-lb-overlay dispatch are owner gated and never run by the agent.
- constraint: Run the CI equivalent local gates including each CI flag before every push.
- constraint: Mutate every added guard on a sandbox copy in the commit that adds it, control green first.
- constraint: Review panel includes security-sentinel and test-design-reviewer at minimum.
- constraint: Stop with the PR ready and end with a Paused sentence naming the merge for the owner.
- constraint: Do not start PR B.
