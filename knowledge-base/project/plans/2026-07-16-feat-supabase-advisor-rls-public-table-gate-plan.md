# feat: nightly Supabase advisor gate — no public table without RLS (#3366)

```yaml
lane: cross-domain            # no spec.md on this branch — defaulted to cross-domain (TR2 fail-closed)
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: [3366, 6506]
branch: feat-one-shot-3366-supabase-advisor-scan
pr: 6520
budget: ~1 day
plan_version: 2   # v2 after Step 4.5 consult + architecture-strategist + spec-flow-analyzer
```

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No `spec.md` exists on this branch.

## Overview

Build the durable "no public table without RLS" detection layer that #3366 has described since
2026-05-06. The operator decided **DC-1** (recorded in decision issue **#6506**) in favour of building
it now, reversing the escalate-only default, following the CTO + CPO recommendation.

**Shipping this closes #3366 AND closes #6506.**

Nightly, for **all three** live Supabase projects, the gate asserts that no public table lacks RLS —
and **fails the run** when one does.

**Why now** (carry into the PR body):

- #3366 has been open since 2026-05-06 — **71 days** as of today (51 at decision time), among **149**
  open `deferred-scope-out` issues.
- Its re-evaluation trigger fired **three times** (2026-05-03, 2026-06-22, 2026-07-12). Each firing
  produced a comment and nothing else. *"A trigger that fires three times and changes nothing is not a
  trigger."*
- Had this gate existed it would have caught the dark-Inngest RLS gap on **2026-07-11** — a day before
  a human noticed it on 07-12.
- Without it, the detection layer for a 15th unprotected table is **time-to-human-PR — unbounded**.
- This plan **completes DC-2's accepted residual risk**. DC-2 dropped the transient hourly cron on the
  verified premise that the Inngest bootstrap image is pinned (`cloud-init-inngest.yml:337` —
  `IREF=…soleur-inngest-bootstrap:v1.1.19`, a concrete tag, not `:latest`), so goose cannot create a
  table without a reviewable in-PR pin bump. DC-2 explicitly deferred its detection duty *to this gate*.
  This is not a new capability — it is the layer DC-2 was already counting on.

> **v2 note.** v1 of this plan diagnosed a fail-open bug in the existing code and then **reproduced its
> exact shape three times in its own acceptance criteria** (an AC that passed on a broken git command,
> an AC that passed without reading a file, and an assertion resting on a source this plan itself
> documents as unreliable) — while its one load-bearing negative-control AC was **unimplementable**,
> because the code it tested lived inside a workflow `run:` block with no callable seam. All are fixed
> below; the recurring lesson is recorded in §Sharp Edges. The v1→v2 delta is itself the strongest
> argument that the DC-1 "~5 lines" estimate was not the real shape of this work (see DC-B).

## Enhancement Summary

**Deepened on:** 2026-07-16 · **Plan version:** v3 (v1 → plan-review → v2 → deepen-plan → v3)
**Agents/passes used:** Step-4.5 scoped consult (fable), architecture-strategist, spec-flow-analyzer,
repo-research; deepen-plan halts 4.6/4.7/4.8/4.9 + verify-the-negative pass.

### Key improvements

1. **The briefed blocker was false — and the real one was the opposite.** `rls_disabled_in_public` is
   **0 on all three projects**, so no baseline/allowlist machinery is needed at all. The genuine risk
   was never a false-red; it was the **fail-open** (a 401 parses to `0`) and its twin the **false-green**
   (a stale-clean advisor over a live violation).
2. **The gate's assertion was re-oriented.** The catalog is now the unconditional, coverage-bearing
   authority; the advisor is subordinate and can only ever *add* a failure. This is what makes the
   ADR-112 citation true rather than inverted.
3. **The load-bearing negative control became runnable.** v1's AC7 had no seam — the parse path lived in
   a workflow `run:` block. Extracting `scripts/supabase-advisor-scan.sh` turned the plan's central claim
   from prose into an executable test.
4. **Three "it'll be picked up automatically" assumptions were falsified** (`-target=`, Inngest
   registration, `infra-validation.yml`) — each fails silently and green. See §Deepen-Plan Findings.
5. **All 16 verification commands were executed**, not asserted. Four ACs were false-passing as written.

### New considerations discovered

- **The plan reproduced the very bug it targets, three times, in its own ACs** (a Unicode ellipsis making
  git error to stderr; a `grep -c` with no file reading stdin; an assertion resting on a source the plan
  itself documents as unreliable). Recorded in §Sharp Edges — the general lesson is that *an AC asserting
  "empty output" passes on any broken command*, so assert exit codes.
- **The "~5 lines" estimate in DC-1 does not survive contact with the code** (DC-B). The decision to
  build is unaffected — arguably better supported — but the estimate should not later be cited as
  evidence this over-built.
- **`soleur-web-platform`, not `soleur-prd`** — an identity preflight built on the assumed name would
  have failed closed on every run.

## Research Reconciliation — Spec vs. Codebase

Every row was measured live this session, not paraphrased. **Four reverse a premise the task was briefed
on.** The pattern is consistent: the durable 20% is real, but nearly every specific claim about *how* to
build it needed correction against live state.

| # | Claim (as briefed / as #3366 states) | Reality (verified 2026-07-16) | Plan response |
|---|---|---|---|
| 1 | "dev is co-tenanted and reports **~52 pre-existing violations forever** — a naive `== 0` against dev fails permanently on day one. Your plan MUST resolve this or the gate is unshippable." | **False for the decided assertion.** `rls_disabled_in_public` is **0 on all three projects** right now. Green on day one. | **Build no baseline/allowlist/asymmetry machinery at all.** The single largest simplification. |
| 2 | The "~52" figure. | **Real, but a different predicate.** It is **51**, from `apply-inngest-rls.yml:195`'s **broad catalog gate** (`relrowsecurity=false OR owner<>postgres OR anon/authenticated holds SELECT/INSERT/UPDATE/DELETE/TRUNCATE`) — counting anon/authenticated **grants**, which the app holds *by design* and RLS **policies** gate. The advisor lint counts only "public table with RLS not enabled". DC-3 conflated the two. | State the distinction in the script header. This conflation is what made #3366 look unshippable for 71 days. |
| 3 | DC-3: "prd's gate is schema-wide, whereas **dev** is co-tenanted → the dev/prd asymmetry." | **Inaccurate.** The broad gate reports **51 on web-platform prd too** — identical to dev. The real asymmetry is **web-platform-schema (51) vs inngest-schema (0)**, present in dev and prd alike. Not a co-tenancy artifact. | Correct it rather than inherit it. No dev/prd branching. |
| 4 | #3366: scan "**dev + prd**" (2 projects). | **Three projects exist.** Since 2026-07-08 `soleur-inngest-prd` is separate. Scanning only "dev + prd" as worded would **exclude the very dark-Inngest surface that motivated this decision**. | **Deliberate correction to #3366's scope: scan all three.** |
| 5 | "Marginal cost is **~5 lines** — the block already parses the lint." | **The existing block is FAIL-OPEN.** Proven live: a `401` returns a body that parses to **`0`** — indistinguishable from a clean scan. `.lints[]?`'s `?` swallows a missing key. A naive `!= 0` assertion would be **permanently green** on an expired PAT. | **The durable 20% is not 5 lines.** See DC-B. |
| 6 | Substrate: "add a nightly GitHub Actions workflow" (#3366) / my own first read of ADR-033 as endorsing GHA cron. | **Both wrong.** ADR-033's canonical shape for a credential-heavy infra cron is **Inngest schedules via `workflow_dispatch`; GHA executes**. `scheduled-terraform-drift.yml:7-12` states it verbatim. `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` **denies** any new `scheduled-*.yml` whose body declares `schedule:`/`cron:`. | Inngest dispatches; GHA file is **`workflow_dispatch:`-only** → hook allows, **no gate-override**. Corroborated independently by `cron-supabase-disk-io.ts:13-16`: *"the runtime container has the service-role key but NOT a Management API PAT."* |
| 7 | DC-3/DHH: a new workflow would be a 3rd/4th copy of the anti-exfil helpers. | **Half already solved.** `scripts/lib/strip-log-injection.sh` **exists**, sourced by 2 scripts. `scrub_pat` has **no lib** (4 inline copies). | Source the lib; **extract `scrub_pat`**. Net **zero new copies**. Do not refactor the 7 pre-existing copies. |
| 8 | The advisor lint is safe to hard-assert. | **Stale in BOTH directions.** `apply-inngest-rls.yml:8-10`: advisor lints "can be served stale right after a DDL change". Over-reports (the ≤1h `17 * * * *` self-heal window) **and** can under-report (a cached `0` over a live violation). | The **catalog** is the authoritative assertion (Phase 3). |
| 9 | "SUPABASE_ACCESS_TOKEN may need provisioning." | **Already wired** (2026-06-18); used by `apply-inngest-rls.yml:86` + `scheduled-inngest-health.yml:173`. | **No new secret. Zero operator steps.** |
| 10 | prd project is "soleur-prd". | **It is `soleur-web-platform`.** (dev=`soleur-dev`, inngest=`soleur-inngest-prd`.) | A preflight with the guessed name would **fail-closed every run**. Names pinned from live API. |
| 11 | Adding a Sentry monitor is just a `cron-monitors.tf` entry. | **`apply-sentry-infra.yml:197-260`'s `-target=` list is enumerated per-resource, not a wildcard.** A monitor without a matching `-target=` line is **declared but never applied** — liveness ships **dark**. | `apply-sentry-infra.yml` is a **load-bearing** edit. The 3 guard suites are *type*-scoped (`test-destroy-guard-sentry-scope-guard.sh:52` greps `sentry_cron_monitor\|sentry_uptime_monitor\|sentry_issue_alert`) → **verified** no edit needed. |
| 12 | DC-2 cites `cloud-init-inngest.yml:330`. | Pin is real but at **`:337`**. | Premise holds; cite `:337`. |
| 13 | *(v1's own claim)* "no C4 change" per `ADR-030…:159`. | **Wrong precedent, and v1 missed live drift.** ADR-030's reason is *"soleur-dev is not modeled"* — that covers **only dev**; `soleur-web-platform` and `soleur-inngest-prd` **are** modeled (`model.c4:164`, `:188`). And `model.c4:444` enumerates *"check-ins from **5 workflows** … **2** `workflow_dispatch`-only that Inngest DISPATCHES … Of **48 cron monitors**, **5** check in from here"* — **48 verified** by count. This plan makes it 6/3/49/6. | Right citation is **`ADR-112:141`** (*"Standard C4 does not model CI gates / security controls as elements"*). No structural edit — but a **description refresh** at `model.c4:444` is required. v1's AC13 would have **locked in a now-false model**. |

## Scope Reconciliation — #3366's "Proposed Fix" vs. the operator's DC-1 decision

| #3366 proposes | Call | Justification |
|---|---|---|
| **(a)** Nightly scan, dev + prd | **KEEP — widened to 3 refs** | The nightly cadence is what #3366 is titled after; dropping it guts the issue. Widened per Reconciliation #4. DC-2's pinned-image finding is why *nightly* (not hourly) suffices: a new table needs a reviewable PR. |
| **(b)** Baseline / snapshot diffing | **DROP** | **Nothing to diff.** All three refs are at 0. A baseline encoding "0" *is* `== 0` — the diff machinery would be a more complex spelling of the same predicate. Snapshot diffing manages a backlog you cannot fix; there is none. YAGNI. |
| **(c)** Auto-file `code-review` + `type/security` issue **per new finding** | **KEEP, scoped to two classes** | Per-finding filing is machinery for a multi-lint scan with a backlog. We assert one lint with zero backlog. But **two** classes are needed, not one — see Phase 4.1. |
| **(d)** **Non-blocking** failure | **RECONCILED — the conflict dissolves** | #3366 says *non-blocking*; DC-1 says *fail the run*. **A nightly scheduled workflow has no PR to block.** "Fail the run" turns it red and files an issue; no developer PR is blocked. We honour DC-1's hard assertion *and* #3366's non-blocking property simultaneously. |
| *(implied)* assert other lints | **DROP — `rls_disabled_in_public` only** | The others are **non-zero** — `authenticated_security_definer_function_executable`=45, `rls_enabled_no_policy`=28/14/14, `auth_leaked_password_protection`=1 — and *this* is where a real "pre-existing violations" problem lives. **`ADR-112 §Decision 1`** makes `rls-authz-fuzz` (AC8) the "AUTHORITATIVE durable class-level guard" and states its authority explicitly *"so a future PR cannot cite the cheaper static tier to weaken AC8"*. Asserting the coarser advisor lint would do exactly that. Also `rls_enabled_no_policy`=14 on inngest-prd is **the lockdown working as designed**. Reported as **non-asserting observability**. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing immediately — and that is the danger. This is a
**detective** control; its failure mode is *silent greenness*. A fail-open gate would close #3366, retire
the human vigilance currently substituting for it, and provide zero coverage — leaving the operator
strictly **worse off than today**, believing a surface is watched when it is not.

**If this leaks, the user's data is exposed via:** the gate reads only catalog metadata and lint counts —
no personal data. The vector it *guards*: a public table without RLS on `soleur-web-platform` (52 tables,
incl. auth-adjacent founder data) is readable by anyone holding the `anon` key, which ships in the client
bundle by design. The gate's own leak vector is `SUPABASE_ACCESS_TOKEN` (a cloud-admin PAT) — mitigated
by env-injection (never argv), a pinned API host (no override — an overridable host is a
PAT-exfil-via-redirect seam), `curl … 2>/dev/null`, and `sanitize()` on every echoed body.

**Brand-survival threshold:** `single-user incident` — justified on the false-confidence argument above,
not carried forward from ADR-030. `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review.

## Architecture Decision (ADR/C4)

### ADR — none new; two existing ADRs govern

- **`ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md:32` — substrate.**
  Its 2026-06-02 scope note decides this exact class: for a **credential-heavy infra cron whose
  execution must stay in an ephemeral runner**, Inngest→`workflow_dispatch` is *the correct shape*
  ("Do not mis-cite this rejection as a blanket ban on Inngest→workflow_dispatch"). **Cite by slug** —
  three files share ordinal ADR-033 and two share ADR-030, so a bare "(ADR-033)" is ambiguous.
- **`ADR-112-definer-grant-hygiene-two-tier-guard.md` — tiering + boundary.** Establishes the two-tier
  pattern: authoritative durable guard = coverage-bearing; cheap tier = "advisory fast-feedback, **NEVER**
  coverage-bearing". Phase 3 applies it **in that orientation** (catalog authoritative, advisor
  subordinate). ADR-112 also owns the definer-lint class.

> **This is conditional on Phase 3's orientation, and that is the point.** Review flagged that v1 had
> ADR-112 **inverted** — it made the advisory tier the sole detector and demoted the authoritative
> catalog to a conditional *suppressor*. Shipped that way it would have been a new architectural
> commitment contradicting `ADR-112 §Decision 2`, requiring its own ADR to record the departure. v2
> fixes the design rather than writing the fallback ADR.

### C4 views — **description refresh only, no structural change**

All three model files were **read**. Enumeration:

- **(a) External human actors:** none new.
- **(b) External systems:** the Supabase **Management API** is unmodeled (grep for `management api` /
  `api.supabase.com` across all three `.c4` returns zero) — and **stays** unmodeled: `ADR-112:141`,
  *"Standard C4 does not model CI gates / security controls as elements."* That is the on-point
  precedent for a CI security gate, decided 2026-07-11.
  > v1 cited `ADR-030…:159` instead. **Wrong precedent:** its reason is *"soleur-dev is not modeled —
  > the C4 model is strictly prod topology"*, which reaches only `soleur-dev`. Two of our three refs
  > **are** modeled (`model.c4:164`, `:188`). The conclusion survives; the citation does not.
- **(c) Containers / data stores:** `supabase`, `inngestPostgres` — read-only, metadata only.
- **(d) Relationships:** no new edge. **But `github -> sentry` (`model.c4:444`) carries a live
  enumeration this plan falsifies** — *"5 workflows … 3 GHA-`schedule:`-fired … and 2
  `workflow_dispatch`-only that Inngest DISPATCHES … Of 48 cron monitors, 5 check in from here and 43
  from webapp."* Verified: `grep -c '^resource "sentry_cron_monitor"' cron-monitors.tf` → **48**. This
  plan makes it **6 workflows / 3 Inngest-dispatched / 49 monitors / 6 from here**.

**In-scope task:** refresh the `model.c4:444` description (5→6, 2→3, 48→49, 5→6, name the new workflow).
Precedent for description-refresh-as-non-structural: ADR-030's 2026-06-29 amendment ("no C4 **structural**
change … only the element description is refreshed"). **No new element, no new relationship, no
`views.c4` change** → `c4-render.test.ts` unaffected.

> **v1 shipped the opposite of its own thesis here.** Its AC13 asserted `diagrams/` was untouched —
> which would have **affirmatively locked in a now-false model**. An AC that verifies the wrong
> invariant is exactly the failure this plan exists to prevent.

### Sequencing

None. The decision is true the moment the gate ships.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/sentry/cron-monitors.tf` — add one `sentry_cron_monitor`,
`scheduled_supabase_advisor_scan`, mirroring `scheduled_terraform_drift` (`:83-93`):
`schedule = { crontab = "37 3 * * *" }`, `checkin_margin_minutes`, `max_runtime_minutes`,
`failure_issue_threshold = 1`, `recovery_threshold = 1`, `timezone = "UTC"`.
**`name` must be written slug-shaped** (`"scheduled-supabase-advisor-scan"`) — Sentry derives the slug by
slugifying `name`, and the workflow's `monitor-slug` must equal that derived slug.
**No new provider, variable, or secret.**

### Apply path

`apply-sentry-infra.yml` auto-applies on merge; its `paths:` names `cron-monitors.tf` explicitly, so the
apply **does** fire. **Load-bearing:** add `-target=sentry_cron_monitor.scheduled_supabase_advisor_scan \`
to the enumerated list at `:197-260`. Without it the resource is declared but never applied
(Reconciliation #11). Pure create — no destroy, no `[ack-destroy]`. Expect `1 to add, 0 to change, 0 to
destroy`.

### Distinctness / drift safeguards

Three refs pinned as literals + a **project-identity preflight** per ref (assert the ref resolves to the
expected `PROJECT_NAME` before asserting anything), reused from `apply-inngest-rls.yml:131-142`, names
verified live (Reconciliation #10). This is the `hr-dev-prd-distinct-supabase-projects` guard.

### Vendor-tier reality check

`sentry_cron_monitor` is already created by this root 48× on the current tier — no free-tier gate.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor check-in "scheduled-supabase-advisor-scan" (ok|error), posted by
        ./.github/actions/sentry-heartbeat at the END of the GHA run with if: always(), and ONLY
        when github.event.inputs.source == 'inngest'
  cadence: nightly 03:37 UTC
  alert_target: Sentry issue stream (failure_issue_threshold = 1) — a MISSED check-in alerts, which is
                what covers a dead/failed Inngest dispatch
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (+ the -target= line in
                 .github/workflows/apply-sentry-infra.yml — else it never applies)

error_reporting:
  destination: (1) GHA run status -> red; (2) one of TWO deduped GitHub issues (see failure_modes);
               (3) Sentry check-in status=error; (4) the Inngest fn reports its own
               token-mint/dispatch failure via reportSilentFallback (token redacted), mirroring
               cron-terraform-drift.ts:45-46
  fail_loud: true — every non-200, every structurally-unexpected body, every parse failure, and every
             UNANTICIPATED abort is a FAILURE that files an issue, never a zero and never a silent
             red. This is the plan's central contract.

failure_modes:
  # --- class A: "public table without RLS" (type/security, priority/p1-high) ---
  - mode: violation_confirmed — a public table has no RLS (the thing the gate exists to catch)
    detection: catalog assertion rls_off != 0 (Phase 3.1, UNCONDITIONAL)
    alert_route: red run + issue "[ci/supabase-advisor] public table without RLS"
  - mode: confirm_indeterminate — advisor names a table the catalog cannot find or classify
    detection: Phase 3.3 object-scoped lookup returns no row / relrowsecurity=false
    alert_route: same as violation_confirmed (fail-closed: an unexplained disagreement is NOT benign)
  # --- class B: "scan failed" (infrastructure; NOT type/security, priority/p2-medium) ---
  - mode: advisor_unreachable — PAT expired/revoked/unauthorized (401)
    detection: HTTP status assertion == 200 (the naive parse returns 0 here = silently green)
    alert_route: red run + issue "[ci/supabase-advisor] scan failed"
  - mode: advisor_malformed — API contract drift (.lints renamed/removed)
    detection: jq -e 'has("lints") and (.lints|type=="array")'
    alert_route: red run + issue "[ci/supabase-advisor] scan failed"
  - mode: identity_mismatch — a ref resolves to the wrong project
    detection: project-identity preflight vs expected PROJECT_NAME
    alert_route: red run + issue "[ci/supabase-advisor] scan failed"
  - mode: not_scanned — a ref was skipped because an earlier ref aborted
    detection: per-ref status accumulation (Phase 2.4); rendered explicitly in the issue body
    alert_route: red run + issue "[ci/supabase-advisor] scan failed"
  - mode: unknown_error — an UNANTICIPATED abort (jq crash, mktemp failure, OOM) under set -euo pipefail
    detection: `if: failure()` UNCONDITIONALLY, with FAIL_MODE defaulted to 'unknown_error'
    alert_route: red run + issue "[ci/supabase-advisor] scan failed"
    why: the ported source gates issue-filing on `failure_mode != ''`; an abort before that output is
         written would file NOTHING. Red run, no issue, no dedupe, no auto-close. Do not port blind.
  # --- non-failing ---
  - mode: stale_advisor — advisor fires, catalog clean, every advisor-named table now RLS-on
    detection: Phase 3.3 object-scoped lookup confirms relrowsecurity=true on each named table
    alert_route: WARN in the run log; does NOT fail (the benign <=1h self-heal window)

logs:
  where: GHA run log (sanitized via strip_log_injection + scrub_pat); the issue body carries per-ref
         status (incl. not_scanned), the catalog + advisor results, and the non-asserting lint census
  retention: GitHub Actions default (90 days); the issue is durable

discoverability_test:
  command: gh run list --workflow=scheduled-supabase-advisor-scan.yml --limit 5 --json
           conclusion,createdAt,displayTitle
  expected_output: a run within the last 24h with conclusion "success"; and
                   `gh issue list --label ci/supabase-advisor --state open` returns empty when healthy
```

No SSH anywhere in the diagnostic path (`hr-no-ssh-fallback-in-runbooks`).

### Soak Follow-Through Enrollment

**Not applicable.** No AC is time-gated: the gate is green on day one (Reconciliation #1) and its
correctness is proven at merge by the AC7 harness, not by a post-deploy soak.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

0.1 Re-run the live advisor + catalog counts for all three refs; confirm still `0`. If any is non-zero,
    **stop** — that is a live security finding to remediate first, and the day-one-green premise needs
    re-deciding.
0.2 Confirm `scripts/lib/strip-log-injection.sh` exists and exposes `strip_log_injection`.
0.3 Confirm `apply-sentry-infra.yml`'s `-target=` list is still enumerated (not wildcarded).
0.4 `gh secret list | grep SUPABASE_ACCESS_TOKEN` — confirm still wired.
0.5 **Pin the advisor lint's object metadata shape** (load-bearing for Phase 3.3, which reads table
    names out of it). Dump one live lint object; confirm which field carries schema + table.
    > **No live sample of `rls_disabled_in_public` exists** — all three refs return zero of them. Sample
    > the envelope from a sibling lint that *is* non-zero (`rls_enabled_no_policy`, 28 on dev). **Do not
    > assume field names.** If the shape cannot carry reliable object identity, Phase 3.3 degrades to:
    > **any** advisor-fires + catalog-clean disagreement is a **FAIL** (`confirm_indeterminate`). Accept
    > a rare false-red over any false-green. Decide **here**, not mid-build.
0.6 **Verify the dispatch credential path BEFORE Phase 6's four-site registration.** Confirm
    `cron-terraform-drift.ts:69-70`'s `mint-installation-token` step is reachable with `actions: write`
    (GitHub **App** installation token — `hr-github-app-auth-not-pat` forbids a PAT). If absent, re-make
    the substrate decision **now**; retrofitting after registration is the rework this phase prevents.

### Phase 1 — Extract the `scrub_pat` helper (closes DHH's DC-3 point for new code)

1.1 Create `scripts/lib/scrub-supabase-pat.sh` exposing `scrub_pat()`, lifted **verbatim** from
    `apply-inngest-rls.yml:102-104` (`sed -E 's/sbp_[A-Za-z0-9]{20,}/sbp_REDACTED/g'`). Header mirrors
    `strip-log-injection.sh`.
1.2 **Do not** migrate the 4 pre-existing inline copies — separate cleanup PR. This plan's obligation is
    **not to add a copy**, which it meets.

### Phase 2 — Extract the scan to a **testable script** (the highest-leverage change in v2)

> **Why a script and not a `run:` block.** v1 put the scan inline in workflow YAML and then declared a
> negative-control AC over it. **That AC was unimplementable**: nothing can call a `run:` block with a
> fixture body, and Phase 2's pinned host (no env override) means it cannot be pointed at a stub either.
> The plan's headline mitigation was prose. A script has a **seam**; the seam is what makes the rest of
> the plan verifiable rather than asserted.

2.1 Create `scripts/supabase-advisor-scan.sh`.
    - **In (env):** `REF`, `PROJECT_NAME`, `SUPABASE_ACCESS_TOKEN`. **Out (stdout):** per-ref counts +
      census as parseable key=value. **Exit:** `0` clean / `1` fail, with `fail_mode` emitted.
    - Sources both libs: `. scripts/lib/strip-log-injection.sh`, `. scripts/lib/scrub-supabase-pat.sh`;
      `sanitize() { scrub_pat "$(strip_log_injection "$1")"; }`.
    - `API="https://api.supabase.com"` **pinned — no env override**. The test stubs **`curl` on `PATH`**,
      not the host — which dissolves the pinned-host-vs-testability tension entirely.
    - Token via env, never argv; `curl … 2>/dev/null`.
2.2 **The fail-closed contract**, in order, per ref:
    1. **Project-identity preflight** — `GET /v1/projects/{ref}`; assert HTTP 200 **and**
       `.name == $PROJECT_NAME`. Pinned: `mlwiodleouzwniehynfz`→`soleur-dev`,
       `ifsccnjhymdmidffkzhl`→`soleur-web-platform`, `pigsfuxruiopinouvjwy`→`soleur-inngest-prd`.
    2. **Transport assertion** — `-w '%{http_code}'`; **HTTP != 200 is a FAILURE**, not a zero.
    3. **Structural assertion** — `jq -e 'has("lints") and (.lints|type=="array")'`; a body without a
       `lints` array is a FAILURE, not a zero.
    4. **Only then** count, with `.lints[]` **without `?`** — the `?` is precisely what makes the
       existing block fail-open, and is unnecessary once (3) proved the array exists.
2.3 Non-asserting lint census: emit full per-lint counts (sanitized).
2.4 **Scan all three refs; accumulate per-ref status; fail once at the end.** A first-ref abort must not
    blind refs 2-3 — an identity failure on `soleur-dev` would otherwise leave **both prod refs
    unscanned** while the issue body reads like a full scan. Refs not reached are recorded
    `not_scanned` and rendered as such.

### Phase 3 — Two assertions, correctly oriented (catalog authoritative, advisor subordinate)

Staleness cuts **both ways** (`apply-inngest-rls.yml:8-10`), and the two directions need different
handling:

- **advisor fires, catalog clean** → likely the benign ≤1h self-heal window → must **not** fail.
- **advisor clean (stale), catalog dirty** → a **real violation the advisor has not caught up to** → must
  fail. *A design that consults the catalog only when the advisor fires misses this entirely* —
  re-creating the fail-open bug one tier up, via staleness instead of parsing. **This is what v1 did.**

3.1 **Catalog assertion — AUTHORITATIVE, unconditional, coverage-bearing** (ADR-112's AC8 role):
    `select count(*) as rls_off from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relkind in ('r','p') and c.relrowsecurity=false`
    (measured **0** on all three refs). **`rls_off > 0` → FAIL**, regardless of the advisor.
3.2 **Advisor — SUBORDINATE.** It may only ever **add** a failure signal; it can **never** suppress or
    weaken 3.1. This orientation is what keeps `ADR-112 §Decision 2` true.
3.3 **The only benign carve-out, and it is object-scoped — never count-vs-count.** When the advisor is
    non-zero **and** 3.1 is clean, extract the **table names from the advisor lint metadata** (shape
    pinned in 0.5) and check each directly, **without the relkind filter**:
    `select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname = $schema and c.relname = $table`
    - every named table reports `relrowsecurity = true` → **WARN** (`stale_advisor`), pass.
    - **any** named table reports `false`, **or resolves to no row** → **FAIL**
      (`confirm_indeterminate`).
    > **Why object-scoped** *(both reviewers converged here)*: 3.1's predicate hardcodes
    > `relkind in ('r','p')` and `nspname='public'`. Count-vs-count would let a genuine advisor finding
    > on an object *outside* that predicate meet a clean-looking `rls_off = 0` and be downgraded to
    > WARN-pass — **rebuilding the fail-open one tier up**, which AC7 could not catch (AC7 only
    > exercises the parse path; hence AC7b). Two numbers agreeing at `0` does not prove they measured
    > the same tables. And it resolves the plan's own tension: v1 rejected catalog-as-primary because
    > the predicate is brittle, then handed that same brittle predicate **veto power** over the advisor.
    > Object-scoping means an unexplained disagreement **fails** instead of being swallowed as lag —
    > so `stale_advisor` can no longer pass forever on a *permanent* disagreement.

**Quadrant table — the gate must be correct in all four:**

| | advisor clean | advisor fires |
|---|---|---|
| **catalog clean** | PASS | **WARN** iff every advisor-named table is now RLS-on; else **FAIL** (`confirm_indeterminate`) |
| **catalog dirty** | **FAIL** (3.1 — a stale advisor cannot hide a real violation) | **FAIL** |

### Phase 4 — Failure-issue filing (reuse the block; do NOT port its conditions blind)

4.1 **Two classes, two titles** — the plan's own rule ("per-class title separation is load-bearing")
    applied to itself. v1 had one title for four semantically different fail_modes, so an **expired PAT
    would have filed "public table without RLS" labelled `type/security` + `p1-high`** — paging the
    operator for a data-exposure incident that is a token renewal. Worse, a *real* violation would then
    only **comment** on the pre-existing token-expiry issue, and token recovery would **auto-close an
    issue whose body describes an unfixed RLS violation**.
    | Class | Title | Labels |
    |---|---|---|
    | A — violation (`violation_confirmed`, `confirm_indeterminate`) | `[ci/supabase-advisor] public table without RLS` | `ci/supabase-advisor`, `type/security`, `priority/p1-high` |
    | B — infrastructure (`advisor_unreachable`, `advisor_malformed`, `identity_mismatch`, `not_scanned`, `unknown_error`) | `[ci/supabase-advisor] scan failed` | `ci/supabase-advisor`, `priority/p2-medium` (**no** `type/security`) |
    Independent dedupe **and** independent close-search per title. Labels created idempotently
    (`gh label create … || true`). **`--milestone "Post-MVP / Later"`** — a hook rejects `gh issue create`
    without it. Env: `GH_TOKEN: ${{ github.token }}`, `GH_REPO: ${{ github.repository }}`, `RUN_URL: …`.
4.2 **The `if:` condition — do not port the source's.** `apply-inngest-rls.yml:253` reads
    `if: failure() && steps.apply.outputs.failure_mode != ''`. Under `set -euo pipefail` an
    *unanticipated* abort exits **before** `failure_mode` is written → condition false → **red run, no
    issue, no dedupe, no auto-close ever**. Only the four anticipated modes would file anything.
    Use `if: failure()` **unconditionally**, with
    `FAIL_MODE: ${{ steps.scan.outputs.failure_mode || 'unknown_error' }}`. Auto-close step:
    `if: success()`.
    > v1 omitted `if:` from Phase 4 entirely while specifying `if: always()` for the heartbeat — reading
    > as unconsidered rather than implied. A step with no condition after a failing step is **skipped**.
4.3 **Dedupe by label, not `--search`** (learning `2026-06-12-gh-search-api-empty-cross-repo-under-in-action-app-token.md`:
    `--search` can return empty under some token contexts → a duplicate issue every night). Use
    `scheduled-terraform-drift.yml:144-148`'s shape:
    `gh issue list --label ci/supabase-advisor --state open --json number,title --jq 'map(select(.title == "…")) | .[0].number // empty'`.
4.4 Body: per-ref status (incl. `not_scanned`), catalog + advisor results, the census, `RUN_URL`, and
    `fail_mode`. All sanitized.

### Phase 5 — Sentry heartbeat + IaC

5.1 Add `./.github/actions/sentry-heartbeat`, `if: always()`, `continue-on-error: true`,
    `monitor-slug: scheduled-supabase-advisor-scan`, `status: … && 'ok' || 'error'`.
    - **Invariant 1 — the check-in fires at the END of the GHA run, never from the Inngest fn at
      dispatch time.** A dispatch-time check-in marks the monitor green while covering only the first
      hop, leaving "dispatch accepted, workflow never ran" invisible — **the same fail-open shape as the
      jq `?`, relocated to the orchestration layer.**
    - **Invariant 2 — only an Inngest-sourced run may post the check-in.** The workflow is
      `workflow_dispatch`-only and we advertise `gh workflow run …` as a smoke test, so **any manual
      dispatch would otherwise post `ok` and satisfy the check-in window — forging the liveness signal
      while Inngest is dead for weeks.** The Inngest fn passes `inputs: { source: "inngest" }`; gate the
      heartbeat step on `github.event.inputs.source == 'inngest'`. Manual runs still scan and still file
      issues — they just cannot forge liveness.
5.2 Add the `sentry_cron_monitor` to `cron-monitors.tf` (`name` slug-shaped).
5.3 **Add the `-target=` line to `apply-sentry-infra.yml`** — without it 5.2 is inert.

### Phase 6 — The Inngest scheduler (the canonical substrate)

6.1 Create `apps/web-platform/server/inngest/functions/cron-supabase-advisor-scan.ts`, modelled on
    `cron-terraform-drift.ts`: `{ cron: "37 3 * * *" }`, mint a short-lived `actions: write` GitHub App
    installation token inside `step.run`, `POST …/actions/workflows/{workflow_id}/dispatches` with the
    workflow **file basename** as `{workflow_id}` and `inputs: { source: "inngest" }`. Dispatch-only —
    it holds **no** Supabase credential. Report dispatch failure via `reportSilentFallback`.
    - **03:37 is deliberate:** 20 min after the `:17` hourly self-heal, minimizing the Phase-3.3 window.
6.2 **Register at all four sites** — a miss is a silently dead cron:
    1. `apps/web-platform/app/api/inngest/route.ts` — import + `functions: [...]` entry.
    2. `apps/web-platform/server/inngest/cron-manifest.ts` — add `"cron-supabase-advisor-scan"`.
    3. `apps/web-platform/server/inngest/routine-metadata.ts` — metadata entry (domain `Engineering`,
       ownerRole `CTO`, scheduleLabel `Daily 03:37 UTC`, manualTrigger `allowed`).
    4. Parity tests (`routine-metadata-parity.test.ts`, `manual-trigger-allowlist.test.ts`,
       `list-routines.test.ts`) enforce 1-3 — run them.

### Phase 7 — Guards (because actionlint runs in ZERO workflows)

7.1 `actionlint` is **local-only** — there is **no CI gate a new workflow YAML must pass**
    (`ADR-030-inngest-as-durable-trigger-layer.md:159`; `apply-inngest-rls-dev-workflow.test.sh:8`). The
    enforceable pattern is a checked-in shape-guard `.test.sh` under `apps/*/infra/**`, **wired by an
    explicit enumerated step** (NOT auto-discovered — R14) in
    `infra-validation.yml`.
7.2 Create `apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh` asserting:
    - **the hook's own regex** — pipe a synthetic Write payload through
      `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` and assert `permissionDecision == "allow"`.
      This is stricter and more honest than re-implementing the predicate (see AC1).
    - the API host literal is `https://api.supabase.com` with no `${{ }}` interpolation;
    - all three refs + expected names present;
    - both libs sourced (no inline redefinition of `strip_log_injection`/`scrub_pat`);
    - the `sentry-heartbeat` step lives in the **GHA workflow** with `if: always()` **and** the
      `source == 'inngest'` gate; the Inngest fn contains **no** check-in call;
    - the catalog assertion is **not** nested inside an advisor-non-zero conditional;
    - `slugify(cron-monitors.tf name) == workflow monitor-slug`;
    - **`cron-monitors.tf` and `apply-sentry-infra.yml`'s `-target=` set agree** (Reconciliation #11);
    - **`model.c4:444`'s counts match `cron-monitors.tf`** — the C4 drift that v1 missed, now
      mechanically checked rather than trusted.
7.3 Create `tests/scripts/test-supabase-advisor-scan.sh` — the **AC7 harness**. Puts a stub `curl` on
    `PATH` emitting synthesized fixture bodies (`cq-test-fixtures-synthesized-only` — no live capture),
    and drives `scripts/supabase-advisor-scan.sh` through every parse case and every decision quadrant.
7.4 Locally: `actionlint .github/workflows/scheduled-supabase-advisor-scan.yml` + `shellcheck`.
    **Never pipe `actionlint` to `head`** — masks the exit code, reports a false green. Do **not** run it
    against `.github/actions/*/action.yml`.

### Phase 8 — C4 + ship

8.1 Refresh the `model.c4:444` description (5→6 workflows, 2→3 Inngest-dispatched, 48→49 monitors, 5→6
    from here; name the new workflow). **No new element or relationship.**
8.2 PR body: `Closes #3366`, `Closes #6506`. Carry the Overview's "why now" verbatim, and surface the
    decision-challenges (`specs/feat-one-shot-3366-supabase-advisor-scan/decision-challenges.md`).

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/supabase-advisor-scan.sh` | **The scan, as a callable seam.** Without this, AC7 is prose. |
| `tests/scripts/test-supabase-advisor-scan.sh` | The AC7/AC7b harness — stubs `curl` on `PATH`. |
| `.github/workflows/scheduled-supabase-advisor-scan.yml` | The executor. `workflow_dispatch:`-only; loops the script over 3 refs. |
| `apps/web-platform/server/inngest/functions/cron-supabase-advisor-scan.ts` | The scheduler (dispatch-only). |
| `scripts/lib/scrub-supabase-pat.sh` | Extracted `scrub_pat` — this PR adds **zero** new helper copies. |
| `apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh` | Shape + cross-file drift guard. |
| `apps/web-platform/test/server/inngest/cron-supabase-advisor-scan.test.ts` | Registration-shape + dispatch unit test. |

## Files to Edit

| Path | Change | Why load-bearing |
|---|---|---|
| `apps/web-platform/infra/sentry/cron-monitors.tf` | + `sentry_cron_monitor` (slug-shaped `name`) | Liveness signal. |
| `.github/workflows/apply-sentry-infra.yml` | + one `-target=` line | **Without it the monitor is never applied** (Reconciliation #11). |
| `apps/web-platform/app/api/inngest/route.ts` | + import, + `functions:` entry | Unregistered fn never fires. |
| `apps/web-platform/server/inngest/cron-manifest.ts` | + `"cron-supabase-advisor-scan"` | Registry-count + watchdog parity. |
| `apps/web-platform/server/inngest/routine-metadata.ts` | + metadata entry | `routine-metadata-parity.test.ts` fails otherwise. |
| `.github/workflows/infra-validation.yml` | + one explicit `run: bash apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh` step | **The shape guard is NOT auto-discovered** (R14) — this file hand-enumerates ~50 `.test.sh` steps with **no glob runner**. Without this line the guard never runs in CI and AC8 gates nothing. Precedent: `inngest-rls/apply-inngest-rls-dev-workflow.test.sh` is enumerated at `:502`. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | **description refresh at `:444`** (counts) | v1's AC would have locked in a false model (Reconciliation #13). |

**Not edited (deliberate):** the 4 inline `scrub_pat` + 7 `strip_log_injection` copies (separate sweep);
`apply-inngest-rls.yml` / `apply-inngest-rls-dev.yml` — the RLS remediation's diff **stays clean**, an
explicit condition of the operator's decision.

## Acceptance Criteria

### Pre-merge (PR)

Commands are repo-root-relative unless prefixed. **Every AC below was itself audited for the
proxy-vs-invariant defect this plan is about** — v1 shipped three that false-passed.

1. **AC1 — hook parity, using the hook's own regex.** v1 asserted `^\s*(schedule|cron):` (anchored) while
   the hook's scan (`new-scheduled-cron-prefer-inngest.sh:112`) is **unanchored**:
   `(^|[[:space:]]|\\n)(schedule|cron):([[:space:]]|\\n|$)` — so **AC1 could pass while the hook denies
   the Write**. Live risk: Phase 2.1's header comment documents the cadence, and a space-preceded
   `schedule:` in prose trips it (`scheduled-terraform-drift.yml` survives only because its
   `` `schedule:` `` is backtick-preceded). **Assert by executing the hook** (Phase 7.2) —
   `permissionDecision == "allow"` — not by re-implementing its predicate. Header comments must write
   schedule/cron tokens backtick-wrapped, never space-preceded-colon-suffixed.
2. **AC2** `grep -cF 'https://api.supabase.com' scripts/supabase-advisor-scan.sh` ≥ 1, **and** no `${{`
   on the host line.
3. **AC3** All three refs + expected names present **and correctly paired** — pairing is not
   grep-assertable (grep cannot see variable flow), so the AC7 harness covers it: the stub returns the
   wrong `.name` for one ref → assert `identity_mismatch`.
4. **AC4** Covered behaviorally by AC7 (v1 claimed a `has("lints")` **and** an HTTP-status grep, but only
   the first had a command — the second half was unasserted prose).
5. **AC5** `! grep -qF '.lints[]?' scripts/supabase-advisor-scan.sh`.
   > v1 was `grep -c '\.lints\[\]?'` — **no file argument**, so it read stdin, printed `0`, and **passed
   > without examining anything**. It would have passed on a file full of `.lints[]?`. Note also: `-F`
   > is deliberate — "fixing" the BRE to `grep -cE` makes `]` optional and matches the *correct*
   > `.lints[]`, a permanent false-fail.
6. **AC6** `! grep -qE '^\s*(strip_log_injection|scrub_pat)\(\)' scripts/supabase-advisor-scan.sh`
   (never redefined) **and** both `. scripts/lib/…` source lines present.
7. **AC7 — negative control, parse path. `bash tests/scripts/test-supabase-advisor-scan.sh` → exit 0.**
   Drives the real script (via the `curl` stub) with: a `401` body, an empty body, an HTML 502, a
   `.lints`-renamed body, a genuine clean body, a genuine-violation body, and a wrong-`.name` identity
   body. All but the clean body MUST fail, each with the correct `fail_mode`.
   > **This is the AC that proves the gate is not the fail-open one we started from — and in v1 it was
   > unimplementable**, because the code under test lived in a workflow `run:` block with no seam. The
   > Phase-2 script extraction exists to make this AC real.
8. **AC7b — negative control, decision quadrants.** Same harness; asserts all cells of the Phase-3 table,
   because AC7 exercises only the parse path and structurally cannot catch a fail-open in the *decision*
   logic:
   | advisor | catalog | advisor-named table | expected |
   |---|---|---|---|
   | clean | clean | — | pass |
   | clean | **dirty** | — | **FAIL** (the stale-advisor false-green v1 missed) |
   | fires | clean | `relrowsecurity = true` | **WARN + pass** |
   | fires | clean | `false` **or no row** | **FAIL** (`confirm_indeterminate`) |
   | fires | dirty | — | **FAIL** |
9. **AC9** `bash apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh` → exit 0 (covers the
   `-target=`↔`cron-monitors.tf` agreement, `slugify(name) == monitor-slug`, the heartbeat placement +
   `source == 'inngest'` gate, and the `model.c4:444` counts).
9b. **AC9b (the guard is actually wired — R14).** AC9 only proves the guard *passes*; it cannot prove CI
   *runs* it. Assert the enumeration explicitly:
   `grep -qF 'bash apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh' .github/workflows/infra-validation.yml`
   → exit 0. *Without this, the guard is a file nobody calls: green locally, gating nothing on every PR
   — the same "looks present, does nothing" shape this whole plan exists to catch. `infra-validation.yml`
   hand-enumerates ~50 `.test.sh` steps and has no glob runner.*
10. **AC10** `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` and
    `test-destroy-guard-counter-sentry.sh` still exit 0 (verified type-scoped → expected to pass
    unmodified; a failure means the allowlist analysis was wrong).
11. **AC11** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean. (**Not** `npm run -w …` —
    the repo root declares no `workspaces`.)
12. **AC12** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-supabase-advisor-scan.test.ts
    test/server/inngest/routine-metadata-parity.test.ts test/lib/inngest/manual-trigger-allowlist.test.ts
    test/server/routines/list-routines.test.ts` — all pass (the four-site registration proof).
    > The `cd` is load-bearing: `vitest` does **not** exist at the repo root, and the `test/…` paths are
    > package-relative. v1 false-failed as written — the same trap the Sharp Edges document for `tsc`.
13. **AC13 — C4 counts, not C4 silence.**
    `bash apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh` asserts `model.c4:444`'s
    workflow/monitor counts equal the live `cron-monitors.tf` count, **and**
    `git diff --numstat origin/main...HEAD -- knowledge-base/engineering/architecture/diagrams/` shows a
    change confined to `model.c4` with **no new element/relationship** (assert `git`'s exit code, not
    just empty stdout).
    > v1's AC13 was `git diff --name-only origin/main… -- …` → **empty**. Two independent bugs: (a) `…`
    > is a **Unicode ellipsis**, so git exits `fatal: bad revision` — to **stderr**, printing **nothing
    > to stdout**, so the AC *passed on a broken command*, and would have passed identically had every
    > `.c4` file been rewritten; (b) it asserted the **wrong invariant** — the model needs a
    > description refresh, so "diagrams untouched" would have locked in a false model. Use ASCII
    > `origin/main...HEAD`.
14. **AC14** `actionlint .github/workflows/scheduled-supabase-advisor-scan.yml` → **exit 0**.
    > v1 said "no new findings vs. the `origin/main` baseline" — **meaningless for a new file** (the
    > baseline has zero findings for a file that does not exist, so every finding is new). It was exit-0
    > wearing a baseline costume, and a repo-wide count comparison could mask a new finding against a
    > coincidentally-fixed old one. The baseline framing belongs to *pre-existing* files.
15. **AC15** PR body contains `Closes #3366` and `Closes #6506`.

### Post-merge (operator)

**None.** The secret is already wired, the TF auto-applies on merge, and the Inngest fn registers on the
next deploy. First dispatch is observable via `gh run list --workflow=scheduled-supabase-advisor-scan.yml`;
manual smoke is `gh workflow run scheduled-supabase-advisor-scan.yml` (which scans and files issues but
cannot forge the liveness check-in, per Phase 5.1 Invariant 2). Both agent-runnable; neither
operator-gated.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| **GH Actions `schedule:` cron** (what #3366 literally proposes) | **Rejected.** Denied by `new-scheduled-cron-prefer-inngest.sh` absent an override marker, and non-canonical per ADR-033. (`scheduled-inngest-health.yml` *is* GHA-`schedule:`-fired and *does* hold `SUPABASE_ACCESS_TOKEN` — but its override justification, "an Inngest cron cannot detect Inngest being down", does not transfer to us.) |
| **Inngest fn does the scan in-process** (no GHA) | **Rejected.** Parks a Supabase cloud-admin PAT on the long-lived app host — "actively harmful" per ADR-033's scope note. `cron-supabase-disk-io.ts:13-16` corroborates: *"the runtime container has the service-role key but NOT a Management API PAT."* |
| **Advisor as the primary assertion** (DC-1's literal mechanism; v1's design) | **Rejected — this is the plan's biggest correction.** It inverts ADR-112 (advisory tier becomes coverage-bearing) and rests the clean path on a source this plan quotes as unreliable. A stale-cached `0` is a `0` that means "I don't know," asserted as "clean" — the same shape as the 401 bug. Catalog is authoritative (3.1); advisor is subordinate (3.2) and may only *add* failures. Surfaced as **DC-A**. |
| **Catalog only; drop the advisor assertion** | **Rejected.** Our catalog predicate hardcodes `relkind in ('r','p')`; the advisor tracks *Supabase's own* lint semantics and so covers objects our predicate may miss. Keeping it subordinate-but-object-scoped (3.3) gets both properties without letting either swallow the other. |
| **Consult the catalog only when the advisor fires** (v1 Phase 3) | **Rejected.** Handles the false-red, misses the **false-green**. Both assertions now run unconditionally. |
| **Count-vs-count catalog confirm** (v1 3.1) | **Rejected.** An advisor finding outside our predicate would meet a clean `rls_off=0` and be downgraded to WARN-pass; and a *permanent* disagreement would WARN-pass forever. Now object-scoped. |
| **Baseline/snapshot diffing** (#3366 (b)) | **Rejected.** Nothing to diff — all three refs at 0. |
| **Per-finding issue filing** (#3366 (c)) | **Rejected.** One lint, zero backlog → two classes, two titles. |
| **One issue title for all fail_modes** (v1) | **Rejected.** An expired PAT would page as a data-exposure incident, and a real violation would merely comment on the token issue. |
| **Assert all advisor lints** | **Rejected.** 45 definer + 28/14/14 no-policy lints are non-zero; `ADR-112 §Decision 1` owns the definer class and forbids citing a cheaper tier to weaken AC8. |
| **Accept the ≤1h benign false-red** (skip 3.3) | **Rejected.** A nightly security gate that cries wolf gets ignored — *that is how #3366 rotted for 71 days*. |
| **Refactor all 11 inline helper copies now** | **Rejected — out of scope.** The obligation is not to *add* a copy. |

## Open Code-Review Overlap

- **#3366** — this plan's target. **Fold in** (`Closes #3366`).
- **#6506** — the operator-decision record. **Fold in** (`Closes #6506`).
- **#6488** (`chore(inngest): post-cutover drop of the 14 orphaned dark-Inngest tables … + atomic
  retirement of 0002/apply-inngest-rls-dev.yml`) — **Acknowledge.** Touches `apply-inngest-rls-dev.yml`,
  which this plan deliberately does not edit. No file overlap. Interaction worth noting: when #6488
  retires the dev workflow and drops the 14 tables, **this gate becomes the surviving detection layer**
  for `soleur-dev` — which strengthens the case for landing this first.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO-lens. The substrate decision is settled by an accepted ADR (`ADR-033…spawn:32`) plus a
live precedent (`cron-terraform-drift.ts` + `scheduled-terraform-drift.yml`), independently corroborated
by `cron-supabase-disk-io.ts:13-16` — not invented here. The material engineering risk was the fail-open
parse inherited from the corroboration block; v2 addresses it with a **testable seam** (Phase 2 script)
rather than prose, pinned by AC7/AC7b. Reuse is high: helper libs, the issue-filing block, identity
preflight, heartbeat composite, `-target=` pattern. Net new invention is small.
**Agents invoked:** Step 4.5 scoped consult (fable), architecture-strategist, spec-flow-analyzer.
**Skipped specialists:** none.

### Product/UX Gate

Not applicable — **no UI surface**. The mechanical UI-surface override does not fire: no path in Files to
Create/Edit matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Tier: **NONE**.

### GDPR / Compliance (Phase 2.7)

**Not invoked — no regulated-data surface.** The scan reads catalog *metadata* and lint counts; it never
reads rows, and none of the (a)-(d) expansion triggers fire. For the record: this gate is a **detective
control supporting Art. 32** (security of processing) — it strengthens the compliance posture rather than
creating a processing activity. No Article 30 entry needed.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The gate ships fail-open and is worse than nothing** (headline — it would close #3366 while covering nothing) | Phase 2.2's contract + **AC7's harness against a real seam**. v1's version of this row said "Proven-by-test, not by prose" while its test was unimplementable; the Phase-2 extraction is what makes the claim true. |
| Supabase **renames** the lint → advisor silently 0 | **Bounded by Phase 3.1**: the catalog assertion runs unconditionally and does not depend on lint naming. (Under v1's conditional design this was *unbounded* — the Risks table claimed otherwise, falsely.) |
| A benign ≤1h self-heal window turns the gate red and it gets ignored | Phase 3.3 object-scoped carve-out + the 03:37 schedule (20 min after the `:17` self-heal). |
| A *permanent* advisor/catalog disagreement WARN-passes forever | Object-scoped 3.3: anything but "this exact table is now RLS-on" is `confirm_indeterminate` → FAIL. |
| Sentry monitor declared but never applied → liveness dark | The `-target=` line is an explicit Files-to-Edit row + AC9's cross-file assertion. |
| Inngest fails to dispatch → scan silently never runs | Sentry **missed** check-in alerts; the check-in is end-of-run and Inngest-gated so a manual dispatch cannot forge it. Inngest liveness independently owned by `scheduled-inngest-health.yml`. |
| An unanticipated abort files no issue | `if: failure()` unconditional + `unknown_error` default (Phase 4.2). |
| A future edit adds `schedule:` back | AC1 executes the hook itself. |
| `--search` dedupe returns empty → duplicate issue nightly | Label-based dedupe (Phase 4.3). |
| PAT exfiltrated via a crafted response body | Pinned host, env-injection, `2>/dev/null`, `sanitize()` on every echo, `sbp_` redaction. |
| One flaky ref retires coverage for the other two | Phase 2.4 accumulates per-ref status; `not_scanned` is rendered explicitly. |

## Deepen-Plan Findings (round 2)

The halt gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped variable, 4.9 UI-wireframe) all
**pass**. The verify-the-negative pass re-checked every load-bearing negative claim in the plan body —
`actionlint runs in ZERO workflows` (**confirmed**: 0 workflows invoke it), `the repo root declares no
workspaces` (**confirmed**), `vitest is absent at repo root` (**confirmed**), `no new secret needed`
(**confirmed**: `SUPABASE_ACCESS_TOKEN` wired 2026-06-18), `apply-sentry-infra.yml paths: covers
cron-monitors.tf` (**confirmed**: named explicitly at `:45`). Every cited AGENTS rule ID resolves to an
**active** `[id: …]` in AGENTS.md — no fabricated or retired citations. Milestone `Post-MVP / Later`
exists. Label `ci/supabase-advisor` does **not** exist yet — already handled by Phase 4.4's idempotent
`gh label create … || true`.

**One new defect found — R14, and it is the third instance of a single recurring class.**

| # | Finding | Verified how | Applied |
|---|---|---|---|
| **R14** | **The shape guard would never have run in CI.** The plan claimed `apps/*/infra/**.test.sh` is "auto-run by `infra-validation.yml`". **False.** That workflow **hand-enumerates ~50 explicit `run: bash …test.sh` steps** and has **no `find`/glob/`for`-loop runner**. A new `.test.sh` is picked up by **nothing**. AC8 would pass locally while the guard gated nothing on every PR — the guard-that-doesn't-guard, which is this plan's own thesis applied to itself. *(The one glob-ish hook, "Run per-app `main.test.sh` (if present)" at `:212-218`, matches only a file literally named `main.test.sh` at an infra root — not a named guard in a subdirectory.)* | `grep -nE 'test\.sh' .github/workflows/infra-validation.yml` → ~50 enumerated steps; `grep -nE 'find .*test\.sh\|for .*test\.sh\|\*\.test\.sh'` → **none**. Precedent for the fix: `inngest-rls/apply-inngest-rls-dev-workflow.test.sh` is enumerated at `:502`. | `.github/workflows/infra-validation.yml` added to **Files to Edit** (one explicit `run:` step). Its `paths:` already covers `apps/*/infra/**`, so the workflow fires — only the step was missing. |

### The recurring class this plan keeps hitting

**R14 is the third time the same assumption failed in this repo.** Each was found only by looking:

1. **`-target=`** in `apply-sentry-infra.yml` — **enumerated per-resource**, not `sentry_cron_monitor.*`. Omit the line → monitor declared, never applied.
2. **Inngest cron registration** — **four explicit sites** (route.ts, cron-manifest.ts, routine-metadata.ts, parity tests), not auto-discovery. Miss one → silently dead cron.
3. **`infra-validation.yml`** — **~50 enumerated steps**, not a glob. Omit the step → guard never runs.

**The rule this yields: in this repo, "it will be picked up automatically" is false by default.** Every
registration surface is a hand-maintained list, and every one of them fails *silently and green* when you
forget it — the artifact exists, the tests pass locally, and nothing runs. Any future plan adding a
monitor, a cron, or a guard should grep for the enumeration site **before** assuming discovery. This is
the same defect shape the gate itself targets (a thing that looks present but does nothing), which is why
it is worth naming rather than just fixing.

## Sharp Edges

- **The recurring lesson of this plan, stated once:** *a gate is only as good as the seam it can be
  tested through.* v1 diagnosed a fail-open bug and then reproduced its exact shape three times in its
  own ACs — an AC that passed on a broken git command (Unicode `…`), an AC that passed without reading a
  file (no filename → stdin), and an assertion resting on a source the plan itself documented as
  unreliable — while the one AC that would have caught all three was unimplementable, because the code
  under test had **no callable seam**. Extract the logic to a script *first*; the ACs become behavioral
  instead of grep-shaped, and the greps stop being proxies.
- **The `?` in `.lints[]?` is the whole bug.** It is correct in `apply-inngest-rls.yml` (corroboration
  that must never break an apply) and fatal here (an assertion that must never pass on garbage). Same
  token, opposite correctness, depending on whether the caller *asserts*. Never copy it mechanically.
- **`grep -c` with no filename reads stdin and prints `0`** — which is exactly the "pass" value an
  absence-AC expects. Always pass an explicit file; prefer `! grep -qF <pattern> <file>`.
- **`git diff origin/main…` (Unicode ellipsis) errors to stderr and prints nothing to stdout** — so any
  AC whose pass condition is "empty output" passes on the broken command. Use ASCII `...` and assert the
  exit code.
- **An AC that asserts a file is *untouched* is only correct if the file is *supposed* to be untouched.**
  Verify the invariant, not the silence.
- **The `new-scheduled-cron-prefer-inngest` hook's regex is unanchored** — a space-preceded `schedule:`
  **inside a comment** trips it. Backtick-wrap or hyphenate schedule/cron tokens in prose. Assert by
  executing the hook, not by re-implementing its predicate.
- **`if: failure() && steps.X.outputs.failure_mode != ''` files nothing on an unanticipated abort.**
- **A `workflow_dispatch`-only workflow's Sentry check-in can be forged by any manual run** — gate it on
  a dispatch input if it is your dead-cron detector.
- **`-target=` is transitive on dependencies.** The new monitor references nothing excluded — re-verify
  with `terraform plan` showing exactly `1 to add, 0 to change, 0 to destroy`.
- **Do not pipe `actionlint` to `head`** (masks exit code → false green); do not run it against
  `.github/actions/*/action.yml` (composite schema → spurious errors). **`bash -n` cannot lint a
  workflow** (parses YAML as bash).
- **Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`**; **vitest likewise needs the
  `cd`** — neither binary exists at the repo root and `npm run -w …` aborts (`No workspaces found`).
- **GNU `tr` does not interpret `\xNN` hex escapes** — only octal. The extracted `scrub_pat` lib must not
  "modernize" the byte-set (`2026-05-11-tr-does-not-interpret-hex-escapes.md`,
  `cq-regex-unicode-separators-escape-only`).
- **`gh issue create` without `--milestone` is rejected** by a hook.
- **Adding a cron requires four registration sites**, not one. The parity tests are the enforcement.
- **Three files share ordinal ADR-033 and two share ADR-030** — cite by **slug**, or an AC-level grep for
  `ADR-033` is noisy and a bare "(ADR-033)" in a header is ambiguous.
