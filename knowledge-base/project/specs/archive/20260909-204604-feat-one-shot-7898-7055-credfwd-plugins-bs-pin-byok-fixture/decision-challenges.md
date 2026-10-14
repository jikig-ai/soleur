# Decision Challenges — feat-one-shot-7898-7055-credfwd-plugins-bs-pin-byok-fixture

Recorded headless during `/soleur:plan`. Each entry is a point where the plan departs from the
stated direction, or where a reviewer's recommendation was surfaced rather than adopted. `/ship`
renders these into the PR body and files them as `action-required`.

## 1. User-Challenge — the prescribed #7055 fix is already on `main`

**Stated direction:** "Fix by making the fixture independent of other writers — scope the delegation
rows to a per-run unique tenant/workspace so a concurrent CI run cannot contribute to the same meter."

**Measured:** that was already true at the flaking commit `37dc09e6`. `syntheticEmail()` derives from
`randomBytes(8)`, `createSyntheticUser()` mints a fresh auth user and workspace, `grantDelegation()`
mints a fresh delegation per test, and migration 137's meter is keyed by `delegation_id`. Implementing
the prescribed fix would be a no-op presented as a fix.

**Plan's departure:** re-diagnosed from the assertion order at that commit — `allFulfilled` and
`admitted === K` both passed, so the `FOR UPDATE` lock held; only the count computed by matching one
expected error string failed. The defect is an unpartitioned outcome channel on both the client and
ledger sides. The brief's binding constraints are all still honoured: exact equality kept, no retries,
null-change control included.

**If this is wrong,** the fallback is to implement the prescribed scoping anyway and accept a no-op
diff — which would leave the required check flaky.

## 2. Premise correction — there is no Rule D highwater to drive down

**Stated direction:** "Drive the Rule D baseline AND its highwater DOWN by exactly the files remediated."

**Measured:** no `lint-shell-trace-credential-refusal*.highwater` exists. It was built and cut at
review as "strictly subsumed by the repo-wide run". The baseline file is the ratchet. Task dropped.

## 3. User-Challenge — the Better Stack opt-in seam is rejected, not built

**Stated direction:** "Fix = a `*.betterstackdata.com` allowlist plus an explicit opt-in seam for the
~12 suites that drive the script through a stub host."

**Measured:** 10 of the 12 suites never execute the real script's host check — each substitutes a
fake query binary or shadows the file. Only two touch it, and one of those already shadows `curl` as
a shell function. The seam requirement collapses to a single test arm.

**Plan's departure:** allowlist only, no seam. The one arm gets a `curl` shim (existing repo
precedent), which exercises the guard instead of declaring past it. The CTO's ruling was decisive:
the threat model is env control over `BETTERSTACK_QUERY_HOST`, so an env-declared seam is a complete
bypass available to exactly the actor the pin defends against. The brief's requirement that "a missing
declaration fails loud rather than silently re-permitting arbitrary hosts" is satisfied more strongly
with no seam at all. The rejection is recorded in ADR-214 so a future copy-paste does not reintroduce it.

## 4. Threshold raised above the stated framing

**Stated direction:** "the failure mode is one user's project key — a single-user incident".

**Measured:** only 7 of the 15 scripts are customer-facing. The other 8 read Jikigai's own
credentials — `set-role.sh` reads `SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd`, which bypasses RLS
across every customer's rows. The brief's framing understates the operator half.

**Plan's departure:** the two populations are split in `## User-Brand Impact` and the operator half's
severity is stated in prose. The frontmatter value stays `single-user incident` — not a retreat: the
gate enum is `single-user incident | aggregate pattern | none`, so `all-users incident` (which a draft
did write) is invalid as a token and would have failed preflight Check 6. The escalation the threshold
buys — CPO sign-off and `user-impact-reviewer` — is engaged either way.

## 5. CTO recommendation surfaced, not adopted — PR split

**Recommendation:** ship slices A+B in one PR and slice C separately, on the grounds that if C needs
iteration it blocks a security fix, and `Closes #7055` reads cleaner alone.

**Not adopted:** the one-shot batching of #7898 and #7055 is the operator's explicit instruction.
Mitigated by ordering slice C last in the implementation phases so it can be dropped without
unpicking A or B.

## 6. Two pre-existing findings deferred rather than absorbed

Surfaced by the CPO review, both real and both outside this PR's scope: the eight operator-only
skills ship in the customer payload and are advertised on the public docs site while being unrunnable
by customers (route to #2719), and the three `*-setup.sh` scripts write user tokens into `.env`,
which transport confinement does not address. Each is recorded as a Non-Goal with a tracking
disposition.

---

## From the six-agent plan review (2026-09-09)

The panel's **mechanical** findings were auto-applied to the plan — three of them overturned claims
the plan had made, and every one was falsified by running a command rather than by argument:

- The `readonly DOPPLER_API_PINNED` remedy does **not** clear the Rule D finding; hoisting the
  multi-line payload does, and the plan had explicitly ordered those the other way round.
- The repo-wide summary prints `len(offenders)`, not the baseline file's line count — so the
  post-drawdown A/B/C figure is 101, not 103. As written, a blocking criterion would have failed on
  a correct implementation.
- The linter emits a **conditional** xtrace arm for `provision-doppler.sh`, whose token arrives from
  `read -rs` *after* the prologue — so the plan's "use the conditional arm wherever the linter offers
  one" would have shipped a guard that is open at guard time over an operator's workplace-scoped
  Doppler token.
- The hosted-path "no-op" claim was false: `AGENT_ENV_ALLOWLIST` forwards the proxy variables and
  `HOME` into the agent subprocess by design, and the plan's grep scope could not see it.

The items below are **Taste / User-Challenge** and were surfaced rather than applied.

### 7. Cut the null-change control entirely

Two reviewers argued the control proves a primary-key equality in a SQL `WHERE` clause that the
plan's own Cut List already certified as holding, and that a *concurrent* control would add live-DB
contention to the very suite being repaired for intermittent redness.

**Not cut** — the brief mandates it and calls its design load-bearing. **But the concurrency
objection was correct and was acted on:** the control is now sequential, which removes the added
contention while proving the same property, and review surfaced a genuinely non-trivial target for it
(`record_byok_use_and_check_cap`'s founder-scoped meter *does* pool across sibling delegations, so the
isolation claim is true of one meter and false of its sibling).

### 8. Cut Phase 4 / do not close #7055 with a message improvement

DHH's sharpest point: partitioning the outcomes renames the flake rather than reducing it, so
`Closes #7055` on a `flaky`-labelled issue would be mislabelling. **Partly adopted:** Phase 4b now
serializes the tenant-integration concurrency group across refs — the leading environmental cause —
so the PR removes a cause as well as naming the failure. The plan states plainly that the partition
alone would not justify the closure. If the operator prefers, the honest alternative is to retitle
#7055 and close it only after a soak.

### 9. Cut ADR-214

Argued the confinement doctrine is already encoded executably in the linter and an ADR restating it
is a second copy that can drift. **Partly adopted:** the ADR is narrowed to the seam corollary alone
— the one decision the linter does not encode — and the four confinement flags are explicitly kept
out of the corpus.

### 10. Split A+B from C into separate PRs

Now recommended by three reviewers. DHH's form is the sharpest: the plan's own mitigation ("C can be
dropped without unpicking A or B") concedes that C is a separate PR, and bundling a p3 flaky-test fix
with a credential fix whose operator half exposes every customer's rows ships the security half at the speed of the slower one.

**Still not adopted** — the one-shot batching is the operator's explicit instruction. Mitigated by
ordering C last. This is the single most-repeated dissent in the review and the operator may want to
overrule the batching.
# Decision D1 — DECLINE wrapping `createSyntheticUser` in `withGoTrueRetry`

Raised by: `data-integrity-guardian` (MEDIUM, tagged pr-introduced)
Decided by: lead, 2026-09-09. Not routed to the operator — a technical fork is
not an operator question (`hr-technical-fork-is-not-an-operator-question`), and
not routed to the CTO because it is a mechanical/taste call, not an
architecture fork with material trade-offs.

## The finding

T10 raises this file's `auth.admin.createUser` volume, and
`apps/web-platform/test/helpers/gotrue-retry.ts` › `withGoTrueRetry` exists to
retry past GoTrue rate limits. Four sibling tenant-isolation suites use it;
this file does not.

## Why DECLINE

1. **It is not pr-introduced in kind.** Measured: `admin.createUser` occurs at
   ONE call site on `origin/main` and ONE on this branch — it lives inside the
   shared `createSyntheticUser` helper. What changed is call VOLUME, from 7 to
   9 `grantDelegation` sites (~29%). The agent's "two more un-retried calls"
   is true of invocations, not of sites, and no site in this diff is new and
   unretried. The gap is pre-existing and applies equally to all nine.

2. **AC11 forbids it, explicitly and blocking.** "The diff of that test file
   contains no occurrence of `retry`, `retries`, `attempt`." Importing
   `withGoTrueRetry` puts the token in the diff. An AC is a contract; the
   sanctioned move when one is wrong is to AMEND it in the open, not to
   satisfy a looser reading of it.

3. **AC11 is not wrong here, which is why it is not amended.** #7055's whole
   thesis is that this suite's redness is shared-database state and NOT a
   retry budget. Introducing retry machinery into the very file carrying that
   claim weakens it and hands the next reader a precedent for adding one on
   the assertion path — the failure the issue exists to prevent. The
   distinction between "setup retry" and "assertion retry" is real to me and
   invisible in a diff six months from now.

## Residual, stated rather than hidden

GoTrue rate-limit exposure on this file grows ~29% and is unmitigated. If the
suite starts failing with GoTrue 429s or the opaque "Database error deleting
user", that is the cause, and the fix is to wire `withGoTrueRetry` into
`createSyntheticUser` in a change that owns this file's whole fixture strategy
and can amend AC11 deliberately.

NOT filed as an issue: the cost-of-filing gate puts a one-line helper swap far
below the crossover, and filing it would grow the backlog for work whose
trigger has not fired. Recorded here and surfaced in the PR body instead.


---

# CTO RULING — O7 concurrency group (BINDING, implement verbatim)

Ruling: **Option C** — delete the workflow-level `concurrency:` block; put a
repo-wide mutex on the `tenant-integration` JOB only, group literal
`dev-supabase-exclusive`, `cancel-in-progress: false`. Plus Option B's
diagnostic arm in the verdict script (fails closed, explains eviction).

## Why the shipped change was wrong

The workflow has NO `paths:` filter under `on:` (by design, #5585 — the
always-run aggregator must report a required context on EVERY PR). So the
repo-wide group at WORKFLOW level enrols every PR run + every push to main,
not the ~5% touching the isolation surface. The PR's own comment claiming
"path-filtered, so the population that can queue is small" is contradicted by
the same file's header comment.

Measured: 85 first-parent merges in 14 days (~6/day, three inside one hour on
2026-09-07), plus every push to every open PR. Eviction = steady state.

Asymmetry: ref-scoped, the only evictor is a new push to the SAME PR, which
moves the head SHA — the evicted run was already superseded, harmless by
construction. Repo-wide, the evictor is on a DIFFERENT ref and the victim's
head SHA is still current -> red required check on an unrelated PR.

Mechanism confirmed: GitHub keeps at most ONE pending entry per group; a third
arrival cancels the pending one. `cancel-in-progress: false` protects only the
entry already executing.

## What C buys

- group membership: only runs with tenant=true (pushes to main + ~5% of PRs)
- required context still reported on every PR (detect-changes + aggregator stay
  OUTSIDE the group)
- merge_group emits tenant=false -> job skipped -> never joins the group
- independent win: the `Apply migrations to dev` step in the same job is itself
  unsafe run twice concurrently against one project; C fixes that on its own
  terms, which is why C beats A (plain revert)

## Rejected

- B (keep workflow-level): disqualified by the no-paths-filter measurement
- A (revert): safe, but forfeits the migration-apply correctness win; remains
  the escape hatch if C's residual proves worse
- D (pg_advisory_lock): session-scoped lock unsafe behind a TRANSACTION-mode
  pooler — the backend can be handed to another client, so the lock's session
  identity is not the run's identity. Also misses the migration-apply step.
- E (second Supabase project): rejected upstream; also trips
  wg-record-recurring-vendor-expense-before-ready for an UNCONFIRMED hypothesis

## Honestly not confirmed

Expected a merge-queue stall hazard; found the `merge_queue` ruleset rule was
added by #5780 and REVERTED 2026-06-30, so it is dormant, not live. Flagged only
because it would reappear on re-adoption — and C is immune either way.

## Residual, accepted

Three-way overlap inside one job's runtime still evicts a pending job. Verdict
stays RED (fail-closed) because detect-changes said the tree touches the
isolation surface and the suite never ran. Victim is by construction a run on
this surface, never an unrelated PR. Remedy named in the annotation: "Re-run
failed jobs".

## No ADR required

CI topology change, not a new service or data model. The `dev-supabase-exclusive`
literal would merit an ADR only if a second workflow joins it.

Full drafted YAML + shell replacements are in the agent report; implement verbatim.
