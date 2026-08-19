# Decision Challenges — feat-one-shot-7590-sentry-rules-api-410

Findings from `plan-review` that argue the **operator's stated direction** should change.
Per ADR-084 these are never auto-applied. Recorded here for `ship` Phase 6 to render into the
PR body and file as an `action-required` issue.

Panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
architecture-strategist, spec-flow-analyzer (5 delivered; cto pending at time of writing).

---

## UC-1 — Drop the substring fallback that the task brief explicitly asked to keep

**decisionClass:** user-challenge

**The operator's stated direction.** The task brief said, verbatim: *"Keep the existing 'fall back
to substring search only if the structured pass returns zero' safety property."*

**What the reviewers found.** `code-simplicity-reviewer` recommends deleting it outright. The
measured hit rate is **0 of 55 on the old payload and 0 of 55 on the new one** — I verified both.
Under the new schema `detectors[].dataSources[].queryObj.slug` is an exact 55/55 structural match
to the live monitor set, so the fallback has nothing left to catch. Keeping it costs
`rules_serialized`, a grep, and a two-stage loop structure that AC6, Phase 5 and Guard 2 must each
preserve — and AC6 as written is unverifiable, because no fixture can distinguish "the structured
pass found it" from "the fallback found it" without emitting a structured-pass count.

**Why this is not mine to auto-apply.** It removes a safety property the operator named. The
fallback's value is precisely that it is speculative — it guards a schema change nobody has seen yet.

**Recommendation.** Keep it, but make it observable: emit the structured-pass count into the report
so AC6 becomes checkable and a fallback activation is visible rather than silent. If the operator
prefers the simplification, delete it and rely on the Class A invariant assertion instead.

---

## UC-2 — Delete orphan Class A rather than remapping it

**decisionClass:** user-challenge

**The operator's stated direction.** The brief asked to *"remap the orphan-detection jq to the
workflow/detector response schema"* and to *"say so explicitly rather than shipping detection that
silently finds nothing"* — i.e. fix the detection, not remove it.

**What the reviewers found.** `dhh-rails-reviewer` recommends deleting Class A entirely, on measured
grounds I verified:

- Class A has **never discriminated**. The only two committed reports show 8-of-8 flagged
  (2026-05-15) and a trivially-clean run over one rule (2026-05-17).
- The 8 monitors flagged in May were never remediated; the count is now 55.
- The predicate contradicts the architecture on purpose: `issue-alerts.tf`'s header states these
  rules are *"PROJECT-WIDE frequency alerts … bound to no monitor"*. Cron failures route through the
  `monitor_check_in_failure` issue, never through a rule naming a slug.
- Under the new predicate it is still 55/55, so the plan's proposed "record 55 as the baseline, a
  change is the signal" reduces to alerting on the monitor count — which Class D already watches,
  with teeth.

`architecture-strategist` adds that pinning the baseline as prose in ADR-031 is the
"prose is not an enforcement mechanism" anti-pattern, and that the report's Orphans section would
silently change meaning from 8/8 to 55/55 with no provenance in the artifact.

**Why this is not mine to auto-apply.** It removes a whole detection class from an artifact with an
Article 30 accountability role. That is a scope reduction the operator did not ask for.

**Recommendation.** Middle path, which the plan now adopts: keep Class A but replace the per-slug
list with a **count plus a machine-checked invariant** (`class_a_count == cron_detector_count`), so
ordinary monitor growth is not a signal while a real routing attachment or an extraction failure
both are. If the operator agrees with DHH, deleting it and stating why in the report is defensible
and strictly simpler.

---

## UC-3 — Split the script's gating half from its reporting half (`AUDIT_MODE=gates`)

**decisionClass:** user-challenge

**The operator's stated direction.** The brief scoped the work to `fetch_rules()`, the orphan jq,
diagnostics, brownout behaviour, tests, and a required-check recommendation. It did not ask for a
structural split, and it said explicitly: *"the four destination-controllability gates … are
unaffected. Do not regress them."*

**What the reviewers found.** `architecture-strategist` identifies the root cause behind four
separate P0s: the script conflates two responsibilities with **opposite failure postures** behind
one exit code — fail-closed destination gating (which `apply-sentry-infra.yml` runs *before*
`terraform plan`) and advisory orphan reporting. This PR changes only the reporting half, but routes
its central mechanism (`curl_retry`) through the gating half.

It also corrects a claim in my plan: I wrote that the four gates *"run before `fetch_rules()`"* and
are therefore unaffected. That is **false** — Gates 1–3 call `curl_retry` directly and Gate 4
consumes `gate1_body`, so a `curl_retry` rewrite is squarely inside their blast radius. I have
corrected the plan.

An `AUDIT_MODE=gates` parameter, with `apply-sentry-infra.yml` switched to it, would reduce this
PR's blast radius on the apply path to **zero** and dissolve the pagination deadlock, the Gate 3
retry-208 hazard, and the detectors-partial-fetch posture question in one move.

**Why this is not mine to auto-apply.** It is a structural change to a load-bearing production gate,
beyond the brief's stated scope, and it touches the workflow the operator told me not to regress.

**Recommendation.** Strongly worth doing, and the plan records it as the preferred follow-up. If the
reviewer wants it in scope, the plan's Phase list absorbs it cleanly and several ACs simplify. If
not, the plan's compensating controls (idempotency-aware retry, mandatory cursor-following on
`detectors/`, declared partial-fetch posture) must all land, because without the split they are the
only things standing between a Sentry API wobble and a blocked `terraform apply`.

---

## UC-4 — Reconsider making the gate a required check now rather than later

**decisionClass:** user-challenge

**The operator's stated direction.** The brief asked for *"a recommendation, not an automatic
change"*. The plan recommends **not** requiring it.

**What changed.** The plan's recommendation leaned on a compensating control that does not exist:
"register the orphan unit suite so its 14 tests run under `test`, which is already required." Those
14 tests **already** run under the required `test` check via the `SUITE_GLOBS` glob — verified with
`lint-orphan-test-suites.sh` (`358 covered, 0 orphaned`) and a green `14 passed, 0 failed`.

So the recommendation must be re-derived without it. The substantive arguments against requiring the
gate survive intact — it calls the live Sentry API, and its own history holds three vendor-caused
reds in three months: Gate 3 `504` (08-06), Gate 3 `208` (05-26), org-GET `500` (05-26), per the
plan's H3 row. But the plan can no longer claim it is *banking new deterministic coverage* in
exchange.

(Corrected 2026-08-19. This line read "(500, 504, timeout)" until review; the plan header and
`sentry-audit-gate.yml` carried the same wrong triple. It substitutes a transport class for the
`208`, dropping the write-probe idempotency red — the one red a retry cannot help with, which is
exactly why Decision 5 keeps writes off status retry. The triple is the argument, so it now quotes
H3 verbatim at all three sites.)

**Recommendation.** Keep "not yet", on the vendor-availability argument alone. The honest follow-up
is UC-3's split: once a hermetic gates-only mode exists, requiring *that* is the version of this
that does not hand merge control to a vendor's uptime.
