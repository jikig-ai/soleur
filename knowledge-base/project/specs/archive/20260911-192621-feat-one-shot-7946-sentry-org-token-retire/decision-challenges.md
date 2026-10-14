# Decision Challenges — feat-one-shot-7946-sentry-org-token-retire

Persisted headless per ADR-084. Each entry is a Taste or User-Challenge finding from the
2026-09-11 plan-review panel, surfaced rather than applied. `ship` Phase 6 renders these into the
PR body and files an `action-required` issue. DC-3 of the parent run (#7993) is **decided** in the
plan (`## DC-3 — Decision`) and recorded in ADR-031 and the 2026-09-09 spec's
`decision-challenges.md`; it is not re-opened here.

---

## DC-4 — Land the Rule D remediation as a separate preceding PR, not a first commit

**Class:** taste (delivery boundary; no correctness error either way).

**Raised by:** the scoped strong-model consult, DHH, code-simplicity and the CTO devex lens —
four of seven, independently.

**The proposal:** the 14-file Rule D remediation (13 followthroughs plus the boot-trail's curl) is
forced only by the baseline's `--changed` drawdown contract and maps to none of P1–P4. Pay it in
its own mechanical PR under the old credential name, so the credential PR is a pure
`s/SENTRY_AUTH_TOKEN/SENTRY_ACTIONS_RO_TOKEN/` with zero baseline deltas and the Risks row
"drawdown stalls the PR" disappears.

**What the plan does instead:** two commits in one PR — Rule D + org-slug pins + boot-trail curl
first (passes CI on its own), rename second. Per-commit review gives the readability the
proposal wants; a second PR runs the pipeline tail (review → QA → ship) twice, which is real
additional operator spend, and the brief scopes this run to one PR for the credential half.

**If the operator takes the challenge:** cut commit 1 to its own branch and PR, merge it first,
rebase this branch. Nothing else in the plan changes; AC-5's `comm` then returns 0 trivially.

---

## DC-5 — Store the token as an Actions *environment* secret rather than a repository secret

**Class:** taste (a narrower store at the same single-store cost; a scope addition, not a
correction).

**Raised by:** the scoped strong-model consult; corroborated by architecture-strategist (five
`pull_request_target` workflows can reach repository secrets).

**The proposal:** create a GitHub Actions environment bound only to the sweeper and the two
provisioning jobs and set `SENTRY_ACTIONS_RO_TOKEN` there; `pull_request_target` workflows cannot
reach it.

**Cost, corrected by the deepen pass (security-sentinel):** the two provisioning jobs
(`web_host_create`, `web_host_replace`) already declare `environment: web-platform-infra-apply`,
so for them it is `gh secret set --env web-platform-infra-apply` with zero YAML. Only the sweeper
needs a new environment (no reviewer, `deployment_branch_policy` = `main`) — one repo-settings
write plus one `environment:` key. What it buys is security-material, not cosmetic: the
repository-secret vector is a same-repo branch workflow run by a write collaborator (two on this
public repo — the `pull_request_target` workflows do not reach it), and `event:read` on this org
exposes production event context (emails, IPs, breadcrumbs).

**Why it is still not folded in:** it adds a prod write (W7) to a register that already carries
six, and diverges from the two sibling Sentry secrets (`SENTRY_IAC_AUTH_TOKEN`, the DSN triple)
that ADR-031 places at repository level; the amendment records it as the considered narrower
store with the cost above.

**If the operator takes the challenge:** add W7 (create the sweeper environment) to the register,
add `environment:` to the sweeper job, set the secret with `--env` on both environments. The
plan's ACs are unchanged except AC-7 (`gh secret list --env <name>` ×2).
