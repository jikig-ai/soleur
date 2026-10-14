# Decision Challenges — feat-one-shot-3366-supabase-advisor-scan

Source: `soleur:plan` Step 4.5 scoped consult + plan-review panel, 2026-07-16, against
`knowledge-base/project/plans/2026-07-16-feat-supabase-advisor-rls-public-table-gate-plan.md`.

Routing per ADR-084 / `decision-principles.md`: **Mechanical** findings were auto-applied to the plan.
The items below are **Taste** / **User-Challenge** — they touch the operator's stated direction (DC-1,
recorded in #6506), so they are surfaced here rather than silently applied. This session is headless, so
`ship` Phase 6 should render these into the PR body and file an `action-required` issue.

Context: DC-1's stated scope was *"assert `rls_disabled_in_public == 0` against the Supabase
`/v1/projects/{ref}/advisors/security` advisor endpoint and fail the run when a public table has no
RLS"*, at an estimated *"~5 lines in the workflow"*.

---

## DC-A — The gate asserts the **catalog** as well as the advisor
**Class:** User-Challenge · **Raised by:** plan-time adversarial review + Step 4.5 consult

**The operator's stated direction:** assert the **advisor lint** and fail on non-zero. The advisor
endpoint is named explicitly in DC-1 and in #3366's title.

**The challenge:** the advisor alone cannot carry the assertion, in **both** directions:

- **False-green (the dangerous one).** `apply-inngest-rls.yml:8-10` documents that advisor lints "can be
  served stale right after a DDL change". A stale-clean advisor over a genuinely unprotected table would
  report `0` and the gate would pass. The advisor is *definitionally* a lagging indicator; the thing we
  are gating on is a leading fact.
- **False-red.** The sibling hourly self-heal (`17 * * * *`) leaves a new Inngest table at
  `relrowsecurity=false` for ≤1h — benign (`ALTER DEFAULT PRIVILEGES` means it is born with no anon
  grant), but the lint fires. A nightly gate that cries wolf gets ignored — which is *how #3366 rotted
  for 71 days*.

**The plan's response:** assert **both**, unconditionally and independently — catalog
(`relrowsecurity=false`, authoritative, never stale) **and** advisor (Supabase's own lint semantics,
broader than our hardcoded `relkind in ('r','p')` predicate). The single benign carve-out is
**object-scoped** on the advisor-named tables, not a count comparison.

**Cost of accepting:** ~3 extra queries per night; ~10 extra lines. **Cost of declining:** the gate is
green whenever the PAT expires *or* the advisor lags — i.e. it is decorative.

**Why this is surfaced rather than applied silently:** it **adds** a signal the operator did not name.
The operator's *intent* ("fail the run when a public table has no RLS") is served strictly better; the
operator's *named mechanism* is a strict subset of what ships.

**Decision needed:** accept the advisor+catalog dual assertion, or hold the gate to the advisor alone as
literally decided?

---

## DC-B — The "~5 lines" estimate does not survive contact with the code
**Class:** User-Challenge (framing) · **Raised by:** live verification

**The operator's stated direction:** DC-1 priced the durable 20% at *"~5 lines in a workflow already
being written."* That estimate is load-bearing — it is a substantial part of why building now beat
escalating.

**The challenge:** the existing block that the 5-line estimate builds on is **fail-open**. Proven live
this session: an HTTP 401 returns a body that `jq '[.lints[]?|…]|length'` parses to **`0`** — byte-identical
to a genuinely clean scan. A literal 5-line `if [[ "$adv_n" != "0" ]]; then fail; fi` would produce a gate
that is **permanently green** on an expired or revoked PAT, while closing #3366 and retiring the human
vigilance that currently substitutes for it. That is strictly worse than no gate.

The durable 20% is really: HTTP-status assertion + structural assertion + dropping the fail-open `?` +
identity preflight + the dual assertion (DC-A) + a negative-control test proving all of it. Still
comfortably inside the ~1 day budget — but it is not 5 lines, and the plan should not pretend otherwise.

**No decision needed** — recorded so the estimate is not cited later as evidence the plan over-built.
The *decision* (build now) is unaffected and, if anything, better supported: the fail-open discovery is
itself an argument that this needed a deliberate build rather than a drive-by assertion.

---

## DC-C — No new ADR; no C4 edit
**Class:** Taste · **Raised by:** plan author, flagged for review

Two calls where the plan follows existing precedent over its own first instinct. Both are cheap to
reverse; both are recorded so the reviewer can overrule consciously rather than discover them.

- **No new ADR.** ADR-033's 2026-06-02 scope note already decides the substrate for credential-heavy
  infra crons (Inngest schedules → `workflow_dispatch`; GHA executes). ADR-112 already establishes the
  two-tier "cheap advisory pre-filter + authoritative guard" pattern this plan applies to the RLS class.
  **Risk:** if review judges advisor-detect→catalog-confirm to be a *new* architectural commitment
  rather than an application of ADR-112's, a short ADR is the remedy.
- **No C4 edit.** The enumeration found the Supabase **Management API** genuinely unmodeled across all
  three `.c4` files. My first instinct was to add a `github -> supabase` edge, reasoning that
  `github -> tunnel` and `github -> sigstore` prove the convention includes CI→external edges.
  **Verification overturned it:** `ADR-030-inngest-as-durable-trigger-layer.md:159` decided this exact
  class explicitly for a workflow calling the *same endpoint* with the *same secret* — *"no C4 change
  (soleur-dev is not modeled — the C4 model is strictly prod topology)."* The modeled CI edges are
  **release-path** edges (how prod comes to exist = topology); a nightly read-only lint poll is a
  detective control. **Risk:** if review judges that a *permanent, scheduled* CI→control-plane edge
  crosses the topology threshold in a way ADR-030's *incidental apply-time* call did not, the remedy is
  one `model.c4` line + a `views.c4` include. AC13 asserts the deliberate absence, so a future drive-by
  edit re-opens this question consciously.

---

## DC-D — #3366's own Proposed Fix is partially dropped
**Class:** Taste · **Raised by:** scope reconciliation (mandated by the task)

Recorded so closing #3366 is honest about what shipped vs. what it asked for. Full argument in the
plan's §Scope Reconciliation.

| #3366 asked for | Shipped? | One-line reason |
|---|---|---|
| Nightly scan, dev + prd | **Yes — widened to 3 refs** | Scanning only "dev + prd" as worded would exclude `soleur-inngest-prd` — the very surface that motivated the decision. |
| Baseline / snapshot diffing | **No** | All three refs are at 0. A baseline encoding "0" *is* `== 0`. |
| Per-finding `code-review` + `type/security` issue filing | **Scoped down** to one deduped issue | One lint, zero backlog → two failure modes → one issue. Mirrors `[ci/inngest-rls]`. |
| Non-blocking failure | **Reconciled, not overridden** | A nightly scheduled run has no PR to block, so DC-1's hard assertion and #3366's non-blocking property hold simultaneously. |
| (implied) assert all advisor lints | **No — `rls_disabled_in_public` only** | The other lints are non-zero (45 definer). ADR-112's `rls-authz-fuzz` AC8 owns the definer class with a strictly better mechanism and **forbids** citing a cheaper tier to weaken it. Reported as non-asserting observability. |
