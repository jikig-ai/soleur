# Decision Challenges — feat-one-shot-6766-6774-ci-guards-cannot-fail

Persisted at plan time (headless run — no operator-attached gate available).
`/ship` renders this into the PR body and files it as an `action-required` issue.

---

## DC-1 — The issue's prescribed ordering is inverted and would wedge the repository

**Class:** User-Challenge (ADR-084) — the operator's stated direction is the default; this
records a challenge to it, not a silent override.

**What the operator specified (#6766, "Suggested order"):**
> "Gap 2 first — it is a ruleset edit with no code risk and it stops the bleeding
> immediately. Gap 1 second, with its own tests."

i.e. add `deploy-script-tests` to the "CI Required" ruleset (id `14145388`) as an isolated,
low-risk first step.

**What research found — verified three independent ways:**

1. `.github/workflows/infra-validation.yml` `on: pull_request:` carries a `paths:` filter
   (`:11-47`). A path-filtered workflow posts **no status context at all** on a PR it does
   not match. A required context that never posts sits at *"Expected — Waiting for status"*
   permanently — every non-infra PR (docs, app code, plans) becomes unmergeable.
2. The workflow's own comment says so verbatim (`:246-263`): *"DO NOT make this a required
   context yet — it would deadlock every non-infra PR."*
3. Open issue **#6480** is entirely about this, and opens with: *"**Do not simply add the
   context to the ruleset.**"* Its body records that four independent review agents
   converged on this during #6458, correcting an earlier "one-line admin follow-up" claim.

**Why it matters:** executed as stated, this is a repo-wide delivery outage — and a
*silent* one (a pending check, not a red X). It is the highest-risk action available in
this issue, not the lowest.

**What the plan does instead:**

- **Inverts the order.** The enabling work lands first (PR A: drop the `paths:` filter,
  gate `deploy-script-tests` on a new `suite_relevant` output, route `merge_group`, add
  workflow concurrency, extract the aggregator verdict to a fail-closed script). The
  ruleset flip lands last (PR B), after an empirical check that the context actually posts.
- **Swaps the required context.** `infra-validate-required` (a cheap static-named
  `if: always()` aggregator that already exists) becomes required, with
  `deploy-script-tests`' result folded into its verdict — rather than making the 12-minute
  `deploy-script-tests` job itself a required context on every PR's critical path. This is
  the shape both existing precedents (`tenant-integration-required`,
  `sentry-destroy-required`) already use.
- **Folds in #6480**, whose scope is a superset of #6766's parts 1 and 3. Leaving it open
  after doing its work would itself be a stale-guard defect.

**The operator's direction is preserved on intent.** The requirement — *a red loopback
suite must block merge, and main must not be able to sit red invisibly* — is delivered in
full. Only the mechanism and the ordering changed.

**Operator decision requested:** confirm the two-PR split and the
`deploy-script-tests` → `infra-validate-required` context swap, or direct otherwise.

---

## DC-2 — v1 of this plan reproduced the defect class it exists to fix

**Class:** Taste / process note (no operator action required — already corrected).

Plan-review (architecture-strategist + spec-flow-analyzer) found that v1's own aggregator
would have shipped **green** on #6766's headline case. The existing
`infra-validate-required` step opens with:

```bash
if [[ "$DIRS" == "[]" ]]; then exit 0; fi
```

A PR touching only `.github/workflows/restart-inngest-server.yml` yields
`directories='[]'` with `suite_relevant='true'`; `deploy-script-tests` reds; the early
`exit 0` returns success. v1's acceptance criterion only required the string
`needs.deploy-script-tests.result` to *appear* in the step — which unreachable code after
`exit 0` satisfies.

Recorded here because it is the same failure class the two issues describe — *a check that
certifies a different property than the one it names* — occurring one level up, in the fix
itself. v2 resolves it by extracting the verdict to a unit-tested fail-closed allow-list
script (`scripts/infra-validate-gate-verdict.sh`), mirroring the existing
`scripts/tenant-integration-gate-verdict.sh` precedent, and by rewriting the AC to assert
behaviour rather than string presence.

Four further P0/P1 findings from the same review are recorded in the plan's
§Plan Review Findings table (F1–F14).
