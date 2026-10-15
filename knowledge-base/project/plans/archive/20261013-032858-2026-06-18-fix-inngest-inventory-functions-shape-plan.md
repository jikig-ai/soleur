<!-- iac-routing-ack: this plan edits an EXISTING on-host script (inngest-inventory.sh)
     delivered through the ALREADY-PROVISIONED no-SSH infra-config push + webhook hook.
     It introduces NO new server, service, secret, vendor, DNS, or persistent process.
     The `systemctl`/`/v1/functions`/`curl` strings below are descriptions of an
     existing runtime surface, not new provisioning. No new Terraform is required. -->
---
title: "fix(inngest): correct op=inventory /v1/functions projection to the real host shape (captured fixture, not probed claim)"
type: fix
issue: 5517
branch: feat-one-shot-fix-5517-inngest-functions-shape
date: 2026-06-18
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(inngest): op=inventory `/v1/functions` returns a non-array (number) on host — correct the functions projection

🐛 **Bug fix.** Single on-host infra script + its unit test. No new infrastructure, no new dependency, no UI surface.

## Overview

`op=inventory` (delivered by `inngest-inventory.sh`, run on the durable-backend host
via the no-SSH `/hooks/inngest-inventory` GET hook and consumed by
`cutover-inngest.yml`) now deploys and runs end-to-end, but **correctly fails loud**:

```
FATAL /v1/functions unreachable or non-array (shape="number"); is inngest-server.service up?
```

The `#5509` fail-loud guard (`inngest-inventory.sh:111-118`) is **working as intended** —
it refuses to emit a false-clean empty `functions` baseline. The defect is upstream of
the guard: the `functions` projection at `inngest-inventory.sh:119`
(`[ .[] | (.name // .slug // .id // empty) ] | sort`) assumes `GET 127.0.0.1:8288/v1/functions`
returns a **JSON array** of function objects. The live host endpoint returns a bare JSON
**number** (`shape="number"`).

### Root cause (captured-fixture-vs-probed-assumption class)

The array assumption was **mirrored** from `inngest-wiped-volume-verify.sh:132-134`, whose
`jq 'if type=="array" then length else 0 end'` *tolerates* a non-array (treats it as `0`).
So the verify path never validated the shape and never captured the real bytes; the
inventory path inherited a sibling's assumption rather than the endpoint's real response.
This is exactly `knowledge-base/project/learnings/integration-issues/2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim.md`
and its sibling `…/2026-06-17-inngest-eventsv2-raw-payload-and-receivedat-filter.md`: a
quoted external-API shape is a **hypothesis**, not a fact. The fix is not deployable until
the REAL `/v1/functions` response is **captured and landed as a test fixture**.

### The hard constraint this plan is built around

**The real `/v1/functions` shape is currently UNKNOWN.** The host's fail-loud guard tells us
only `type=="number"` — it does NOT capture the number's *value* or confirm what the number
means (function count? a status code? something else?). Two candidate semantics:

1. **A bare function count** (e.g. `7`) — `/v1/functions` may return `{count}` flattened, or
   the endpoint path differs from what we assume. If it is a count, the inventory cannot
   recover per-function *names* from this endpoint at all.
2. **A wrapped/object shape** the guard's `type` check collapsed — *ruled out* by the captured
   evidence (`shape="number"`, not `"object"`), but re-confirm against the captured bytes.

The issue body suggests a GraphQL fallback (`/v0/gql functions` field "like enumerate does for
events"). **This is itself an unverified assumption** and must NOT be adopted on faith: the
verified schema pin (`knowledge-base/project/specs/feat-one-shot-inngest-cutover-no-ssh-5450/inngest-graphql-schema.md`)
documents ONLY `eventsV2` — it does **not** document a top-level `functions` GraphQL query field.
Adopting GraphQL requires the same live-probe + schema-pin discipline that produced the
`eventsV2` shape. See §Research Reconciliation and §Sharp Edges.

## Research Insights (deepen-plan, 2026-06-18)

Two parallel research agents (inngest-API-contract + verify-the-negative/precedent-diff) ran on
2026-06-18. Key findings that **materially change the recommended fix path**:

- **`GET /v1/functions` is NOT a registered route in inngest v1.19.4.** Source-code inspection of
  `pkg/devserver/api.go`, `pkg/api/apiv1/apiv1.go`, and `pkg/coreapi/coreapi.go` shows the `/v1`
  router registers `GET /v1/apps/{appName}/functions` — there is **no bare `/v1/functions`**. The
  observed bare-number response is almost certainly a **router 404/fallback body** (or a pre-refactor
  artifact), NOT a function payload. *Hypothesis to confirm against the Phase-0 live capture* — but it
  reframes the bug: the script is hitting a **wrong/unregistered path**, not parsing a real shape wrong.
  - Correct REST: `GET /v1/apps/{appName}/functions` → a **bare JSON array** `[{...}]` of
    `cqrs.Function` objects (direct `json.NewEncoder(w).Encode(fns)`, NOT `{data:[…]}`-wrapped). But
    this requires knowing the `appName`(s) first.
  - **GraphQL `functions` field EXISTS and is the cleanest path** (contradicts the issue's
    "likely more reliable" hedge AND my plan-v1 claim that the schema pin lacks it): `pkg/coreapi/gql.query.graphql`
    declares top-level `functions: [Function!]` at `POST /v0/gql` — a rich object array (the same
    source the devserver UI uses), no auth on loopback. This is the SAME GraphQL endpoint enumerate
    already uses for `eventsV2`, so the script already has the curl+jq+`#5503`-purity machinery.
  - **Verdict: prefer the GraphQL `functions` query** (single endpoint, no `appName` discovery needed,
    object array → names project cleanly). Phase 0 MUST still live-probe BOTH `/v0/gql { functions { ... } }`
    AND introspect the live `Function` type's fields (the v1.19.4 `Function` field set is the unknown
    to pin in the schema doc — `slug`/`name`/`triggers` are likely but unconfirmed).
- **The schema-pin doc gap is real and must be closed:** `inngest-graphql-schema.md` documents only
  `eventsV2`. Adding the `functions` query field requires the SAME live-probe + schema-pin discipline
  (`2026-06-17-inngest-eventsv2-raw-payload-and-receivedat-filter`). Pin the captured `Function` field
  set in that doc as part of this PR.
- **Phase-0 option (A) has NO precedent and risks `#5503` purity** (precedent-diff agent): neither
  `inngest-inventory.sh` nor `inngest-enumerate-reminders.sh` echoes bounded raw bytes to stderr; the
  `#5503` block at `inngest-enumerate-reminders.sh:146-158` explicitly PROHIBITS success-path stderr
  echoes (webhook `CombinedOutput()` merges streams). The existing FATAL stderr lines surface only
  derived metadata (`shape=`), never raw bytes. **Re-prefer Phase-0 option (A) only on the FATAL/exit-1
  path** (where stdout is already non-JSON and the body is not parsed as success), bounding to a short
  prefix — OR, better, capture via a **read-only GraphQL probe through an existing host hook / a one-shot
  diagnostic that runs the `/v0/gql { functions }` query and surfaces its shape on the FATAL line**. Do
  NOT add any success-path stderr echo.
- **All 6 verify-the-negative claims confirmed** (citations): projection `:119`, guard `:111-118`,
  sibling latent bug `inngest-wiped-volume-verify.sh:132-134` (bare-number → `jq … else 0` → false
  `no_functions` abort after a healthy restart — Phase 3 fold-in is justified), consumer
  `cutover-inngest.yml:239,246`, and the FATAL diagnostic captures `type` only, never the value.

**Net effect on the plan:** Phase 2's default projection switches from "correct the REST array parse"
to "**re-point to the GraphQL `functions` query** (paralleling enumerate's `eventsV2`), pin the
`Function` field set in the schema doc, project names." The REST `/v1/apps/{appName}/functions` array
path remains a documented fallback if GraphQL `functions` proves unavailable on the live host. Phase 0
remains the BLOCKING gate — confirm the live shape before committing the projection.

## Research Reconciliation — Issue Claims vs. Codebase / Schema Reality

| Claim (issue / prose) | Reality (verified this session) | Plan response |
| --- | --- | --- |
| `/v1/functions` returns a JSON array of function objects (`inngest-inventory.sh:8,16,119`) | Live host returns a bare JSON **number** (`shape="number"` in the FATAL line) | Capture the real bytes (Phase 0), then correct the projection to the captured shape (Phase 2). |
| GraphQL `/v0/gql functions` field is "likely more reliable" (issue Fix step 1) | **Confirmed by source-code research:** `pkg/coreapi/gql.query.graphql` declares top-level `functions: [Function!]` at `POST /v0/gql` (rich object array, no auth on loopback). The schema PIN doc lacks it, but the field exists. Separately, `GET /v1/functions` is NOT a registered route in v1.19.4 (correct REST is `/v1/apps/{appName}/functions`). | **GraphQL `functions` is now the PREFERRED path** (single endpoint, reuses enumerate's `eventsV2` machinery, no `appName` discovery). Still requires a Phase-0 live probe + a schema-doc pin of the v1.19.4 `Function` field set. REST `/v1/apps/{appName}/functions` array is the documented fallback. |
| The `#5509` fail-loud guard is the bug | Guard is **working as intended** (no false-clean baseline) | Keep the guard verbatim. Only the *array assumption upstream of it* changes. |
| `#5515 -replace workaround landed inngest-inventory.sh` | `#5515` is an unrelated OPEN bug (webhook FILE_MAP one-apply-late); the inventory script landed via PR `#5510` (commit `b8850c968`) | Loose prose in the issue; not load-bearing. Delivery is verified end-to-end per the issue Summary. No action. |
| `op=backup` / `op=enumerate` / `re-arm` affected | Issue states these are **live/unaffected** | Out of scope. This PR touches only the `functions` projection + its fixture/test. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. This is an operator-only
cutover-diagnostics surface (`op=inventory` before/after baseline). A wrong `functions`
projection degrades the operator's ability to *diff* the cutover, not any end-user flow. The
`#5509` guard already prevents the worst case (a silent false-clean baseline) by failing loud.

**If this leaks, the user's data is exposed via:** N/A — the inventory summary is counts +
reminder_ids only (no bodies) per the `#5503` purity invariant, which this PR preserves.

**Brand-survival threshold:** none. *Reason:* operator-only cutover-diagnostics script; no
end-user-facing surface, no regulated-data surface, no persistence. The existing fail-loud
guard bounds the worst outcome to a loud, diagnosable abort (not silent corruption).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Captured fixture lands in the diff.** A real `/v1/functions` response (the actual
  host bytes, captured per Phase 0 via the no-SSH path) is committed as a test fixture under
  `apps/web-platform/infra/` (e.g. inline in `inngest-inventory.test.sh` `make_functions` /
  a `fixtures/` file). The fixture's shape is the captured shape, NOT a hand-authored array.
  Grep gate: the test references the captured shape, and the PR body quotes the captured bytes.
- [ ] **AC2 — Projection matches the captured shape.** `inngest-inventory.sh`'s `functions`
  projection (`:119`) is corrected so that, given the captured fixture, `functions` in the
  emitted object is the correct value for the real shape:
  - if the real shape is a **count**, `functions` surfaces the count (and the header comment +
    the emitted object's contract are updated to say "count", not "array of names");
  - if the real shape is `{data:[…]}` or another wrapped array, `functions` unwraps to the
    name/slug/id list as before;
  - if GraphQL is adopted (only on Phase 0 evidence + a schema-pin), `functions` projects names
    from the pinned GraphQL field.
- [ ] **AC3 — Fail-loud guard preserved.** The `#5509` guard at `:111-118` still trips on a
  genuine fetch failure / unparseable body (Test 9 `test_functions_fetch_failure_is_loud` still
  passes), AND the guard's `type=="array"` check is replaced with the correct shape check for
  the captured shape (so the REAL response no longer trips the guard). The guard must NOT be
  loosened to silently accept *any* shape — it must accept the captured shape and reject
  fetch-failure / unexpected shapes.
- [ ] **AC4 — `#5503` combined-stream purity preserved.** Test 1 (`test_combined_is_pure_json_object`)
  still passes: success-path stdout+stderr is a single pure JSON object with the 3 keys, and
  success-path stderr is empty (summary stays journald-only).
- [ ] **AC5 — Header/contract docs corrected.** The script header (`:8`, `:16-19`) and the
  emitted-object contract comment are updated to describe the REAL `/v1/functions` shape, with a
  `# verified: 2026-06-18` annotation citing the Phase-0 capture. No stale "JSON array of
  registered functions" prose remains. Grep gate: `grep -n 'JSON array of registered functions' inngest-inventory.sh` returns 0.
- [ ] **AC6 — Test suite green.** `bash apps/web-platform/infra/inngest-inventory.test.sh` exits 0
  (all tests pass, including a NEW test that drives the corrected projection against the captured
  fixture and asserts the right `functions` value).
- [ ] **AC7 — shellcheck clean.** `shellcheck apps/web-platform/infra/inngest-inventory.sh` is clean
  (or only the pre-existing SC2016 disables remain).
- [ ] **AC8 — Workflow consumer compatibility.** If the `functions` value changes type
  (array → count number), `cutover-inngest.yml:239` (`FN=$(echo "$BODY" | jq '.functions | length')`)
  and `:246` (`{functions, …}`) are reconciled in the SAME PR so the `::notice::` and the
  before/after diff block render correctly. Grep gate: `grep -n '.functions | length' .github/workflows/cutover-inngest.yml`
  is updated if `.functions` is no longer an array.

### Post-merge (operator)

- [ ] **AC9 — Re-run `op=inventory` and confirm a clean baseline.** After merge (the script is
  delivered on the next infra-config push), trigger `op=inventory` via
  `gh workflow run cutover-inngest.yml -f op=inventory` and confirm the `::notice::inventory: functions=…`
  line reports the corrected value (no FATAL). *Automation:* `gh workflow run` + `gh run watch` —
  bake into `/work` Phase 2 verification or `/soleur:ship` post-merge (see §Sharp Edges; this is
  the SAME no-SSH path Phase 0 uses, so it is automatable, not operator-manual).

## Implementation Phases

> **Phase ordering is load-bearing.** Phase 0 (capture) MUST complete before Phase 2
> (projection), because the projection's correctness is defined by the captured bytes. Writing
> the projection before capturing the shape would re-commit the original sin (assuming a shape).

### Phase 0 — Capture the REAL `/v1/functions` shape (no-SSH; BLOCKING gate)

**This phase is the whole point.** Do not write any projection code until the real bytes are in hand.

The host is reachable ONLY via the no-SSH path (`hr-no-ssh-fallback-in-runbooks`). Two automatable
options; prefer (A):

- **(A) Workflow-mediated raw-body capture (preferred).** Add a one-shot diagnostic to the
  non-array branch of `fetch_functions` / the guard so the FATAL path *also* logs the raw body
  (bounded, e.g. first 512 bytes) to journald via `logger` — NOT to stdout (preserves `#5503`
  purity). Ship that single diagnostic commit, let it deliver, trigger `op=inventory`, then read
  the captured bytes. **Reachability:** journald is on-host; but the cutover workflow already
  surfaces the FATAL *cause line* in the `::error::` (`cutover-inngest.yml:234`) — extend the
  cause line (stderr) to carry the bounded raw shape so it reaches the workflow run-log no-SSH.
  Mind `#5503`: the bounded raw bytes go to **stderr/journald**, never the success-path stdout.
- **(B) Direct GraphQL/REST probe via an existing host hook.** If a hook can echo the raw
  `/v1/functions` body to the workflow response (read-only), use it. Confirm no body-leak concern
  (`/v1/functions` carries function metadata, not reminder payloads — low sensitivity, but keep it
  bounded).

**Capture target (per deepen-plan research — PREFER GraphQL):**
1. **GraphQL (preferred):** probe `POST 127.0.0.1:8288/v0/gql` with `query { functions { slug name triggers } }`
   (the exact `Function` field set is the unknown — start minimal, introspect). Capture the response +
   the live `Function` type fields. This is the same endpoint enumerate already uses for `eventsV2`.
2. **REST diagnostic (confirm the bug's true cause):** capture the literal bytes of
   `GET 127.0.0.1:8288/v1/functions` (the bare number — almost certainly a 404/fallback body since the
   route is unregistered) AND, if pursuing the REST fallback, `GET /v1/apps/{appName}/functions` after
   discovering the app name(s).
3. **`/health` 200** alongside, to settle H1 vs H2 (healthy server returning the number → confirms the
   wrong-path hypothesis, not a degraded read).

**Output of Phase 0:** the captured GraphQL `functions` response + `Function` field set pasted into the
PR body, landed as the AC1 fixture, pinned in `inngest-graphql-schema.md`; and a one-line determination:
"projection will re-point to GraphQL `functions` (or REST `/v1/apps/{appName}/functions` fallback)."

> Decision tree after Phase 0: (a) GraphQL `functions` returns a name-bearing object array → re-point
> the projection there (DEFAULT, paralleling `eventsV2`); (b) GraphQL unavailable but REST
> `/v1/apps/{appName}/functions` works → use it (requires `appName` discovery); (c) neither recovers
> names → `functions` becomes a count-only signal, header/contract + AC2 scoped to "count" — document
> explicitly rather than faking a names array.

### Phase 1 — RED: write the failing test against the captured fixture

Per `cq-write-failing-tests-before`. Add a test to `inngest-inventory.test.sh` that:
- builds `make_functions` from the **captured shape** (not the current `[{name,slug,triggers}]` array helper);
- asserts the corrected `functions` value in the emitted object;
- keeps Test 9 (fail-loud on genuine failure) and Test 1 (`#5503` purity) green.
The new test must FAIL against the current `:119` projection (proving it drives the fix).

### Phase 2 — GREEN: correct the projection + guard + contract

- Update the guard shape check (`:111`) from `type == "array"` to the captured-shape check.
- Update the projection (`:119`) to the captured shape.
- Update the header comment (`:8`, `:16-19`) + emitted-object contract + add `# verified: 2026-06-18`.
- If the `functions` type changed, update `cutover-inngest.yml:239,246` in the same commit (AC8).

### Phase 3 — REFACTOR + cross-check the sibling

- Consider whether `inngest-wiped-volume-verify.sh:132-134` (the source of the bad assumption)
  needs the same correction. Its `if type=="array" then length else 0 end` *tolerates* a number
  by treating it as `0` — which means its `fn_count >= 1` durability assert (`:134`) **silently
  fails** on the real (number) shape: a successful restart would report `0 functions` and abort
  the verify with `no_functions`. **This is a latent bug in the sibling, surfaced by this issue.**
  Fold the same shape-correction into `inngest-wiped-volume-verify.sh` in this PR (it shares the
  endpoint and the wrong assumption) OR file a tracking issue. Default: **fold in** — it is the
  same endpoint, same fix, and leaving it produces a false `no_functions` abort on the real shape.
  Add/extend `inngest-wiped-volume-verify.test.sh` accordingly.

## Files to Edit

- `apps/web-platform/infra/inngest-inventory.sh` — correct guard shape check (`:111`), projection
  (`:119`), header/contract comments (`:8`, `:16-19`); add Phase-0 raw-shape diagnostic to the
  FATAL/stderr path (bounded, `#5503`-safe).
- `apps/web-platform/infra/inngest-inventory.test.sh` — `make_functions` rewritten to the captured
  shape; new test driving the corrected projection; keep Tests 1 & 9 green.
- `apps/web-platform/infra/inngest-wiped-volume-verify.sh` — fold the same shape correction (`:132-134`)
  so the `fn_count >= 1` durability assert is correct on the real shape (Phase 3; fold-in default).
- `apps/web-platform/infra/inngest-wiped-volume-verify.test.sh` — cover the corrected sibling shape.
- `.github/workflows/cutover-inngest.yml` — ONLY IF the `functions` value type changes
  (`:239` `.functions | length`, `:246` diff block) — reconcile the consumer (AC8).
- `knowledge-base/project/specs/feat-one-shot-inngest-cutover-no-ssh-5450/inngest-graphql-schema.md`
  — pin the live-probed v1.19.4 GraphQL `functions: [Function!]` query field + the `Function` type's
  field set (the doc currently covers only `eventsV2`). Required if the GraphQL path is adopted.

## Files to Create

- A captured-fixture file under `apps/web-platform/infra/` IF the captured bytes are large enough
  to warrant a file over inline `make_functions` (decided at Phase 0). Otherwise none.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` checked against the files above; no open
scope-out names `inngest-inventory.sh`, `inngest-wiped-volume-verify.sh`, or `cutover-inngest.yml`.)

## Infrastructure (IaC)

Skip — no new infrastructure. This PR edits an EXISTING on-host script already delivered through the
provisioned no-SSH infra-config push + `adnanh/webhook` hook (`hooks.json.tmpl:100-101`). No new
server, service, secret, vendor, DNS record, TLS cert, firewall rule, or persistent process. No
Terraform change. (See the iac-routing-ack comment at the top of this file.)

## Observability

```yaml
liveness_signal:
  what: "op=inventory emits a `::notice::inventory: functions=N event_names=M armed_reminders=K` line on the cutover-inngest.yml run"
  cadence: "on-demand (operator triggers op=inventory before/after the cutover)"
  alert_target: "the GitHub Actions run log (no-SSH); FATAL path also reaches host journald via `logger -t inngest-inventory`"
  configured_in: ".github/workflows/cutover-inngest.yml:242 (::notice::), inngest-inventory.sh:167 (logger summary)"
error_reporting:
  destination: "FATAL cause line on stdout → webhook response body → cutover-inngest.yml `::error::` (run log); journald `logger` on host"
  fail_loud: true  # the #5509 guard exits 1 → webhook non-200 → workflow ::error::; this PR PRESERVES it
failure_modes:
  - mode: "/v1/functions returns an unexpected shape (the bug this PR fixes)"
    detection: "guard shape check (inngest-inventory.sh:111, corrected this PR) → FATAL exit 1"
    alert_route: "cutover-inngest.yml ::error:: with the bounded raw shape in the cause line (added Phase 0)"
  - mode: "/v1/functions unreachable (inngest-server.service down)"
    detection: "curl failure → __FETCH_FAILED__ sentinel → guard trips (preserved)"
    alert_route: "same ::error:: path"
logs:
  where: "host journald (`journalctl -t inngest-inventory`); GitHub Actions run log for the cause line"
  retention: "journald host-local (rotated); Actions logs per GH retention"
discoverability_test:
  command: "gh workflow run cutover-inngest.yml -f op=inventory && gh run watch"  # no-SSH; runs through the existing GitHub Actions + webhook hook path
  expected_output: "::notice::inventory: functions=<corrected value> … (no FATAL line)"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications — operator-only infrastructure/tooling change to a cutover-diagnostics
script. No Product/UX surface (no file under `components/**`, `app/**/page.tsx`, etc.), no marketing,
legal, finance, sales, ops, or support implications.

## Architecture Decision (ADR/C4)

Skip — no architectural decision. This is a shape-correction bug fix on an existing endpoint
projection within an already-decided cutover architecture (ADR-030/ADR-033 self-hosted inngest,
`#5450`). No ownership/tenancy boundary move, no new substrate, no resolver/trust-boundary change,
no reversal/extension of an existing ADR. A competent engineer reading the existing ADRs + C4 would
NOT be misled about the system after this fix. **C4 completeness check:** read
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — the inngest host
and its loopback endpoints are an internal implementation detail of the already-modeled cutover; no
new external actor, external system, container, or access relationship is introduced by correcting a
JSON-shape assumption. No `.c4` edit required.

## GDPR / Compliance

Skip — no regulated-data surface. The inventory summary is counts + reminder_ids only (no bodies,
per `#5503`); `/v1/functions` carries function metadata (names/slugs), not user data. No schema,
migration, auth flow, or API-route change. None of the (a)–(d) expansion triggers fire (no new
LLM/external-API processing of session data, threshold is `none`, no new learnings-reading cron, no
new artifact-distribution surface).

## Hypotheses

The bug-report keyword scan matches none of the network-outage trigger set as a *root-cause*
hypothesis — the FATAL is a deliberate fail-loud, not a connectivity failure. But the FATAL message
itself asks "is inngest-server.service up?", so Phase 0 must distinguish two states before correcting
the projection:

1. **H1 (most likely): `/v1/functions` genuinely returns a number on a HEALTHY server** — the
   endpoint shape differs from the mirrored assumption (the real bug). Phase 0 capture confirms by
   pairing the `/v1/functions` probe with a `/health` 200 in the same run.
2. **H2 (rule out): the number is an error/status artifact of a degraded read** — the guard already
   distinguishes a curl failure (sentinel string, non-JSON) from a parseable JSON number, so a clean
   JSON `number` on a `/health`-200 host points to H1. Phase 0 MUST capture `/health` alongside
   `/v1/functions` to settle this before writing the projection.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** (Filled above; threshold = none
  with a reason, required because the diff touches an infra path.)
- **The captured `/v1/functions` shape MUST land as a fixture in the diff — a "probed" annotation is
  not evidence** (`2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim`).
  Review must re-confirm the fixture matches the captured bytes, not trust prose.
- **GraphQL `functions` IS a real field but its v1.19.4 `Function` field set is unpinned.** Research
  confirmed `functions: [Function!]` exists at `/v0/gql`, but the schema PIN doc
  (`inngest-graphql-schema.md`) documents only `eventsV2`. Phase 0 MUST live-probe the `Function`
  fields and pin them in that doc as part of this PR (same discipline as `eventsV2`) — do NOT assume
  `slug`/`name`/`triggers` without confirming.
- **`GET /v1/functions` is an unregistered route in v1.19.4 (root cause refinement).** The correct REST
  path is `/v1/apps/{appName}/functions`. The bare number the script reads is almost certainly a
  router fallback body, not a real projection target. Phase 0 confirms; this is why GraphQL is preferred
  (no `appName` discovery needed).
- **Phase-0 raw-shape diagnostic is a NOVEL stderr pattern — confine it to the FATAL/exit-1 path.** No
  precedent exists for echoing bounded raw bytes to stderr; the `#5503` block PROHIBITS success-path
  stderr echoes. Any diagnostic MUST live on the already-non-JSON FATAL/exit-1 path (bounded prefix),
  never the success path.
- **The sibling `inngest-wiped-volume-verify.sh` has the SAME latent bug** (`type=="array" → length else 0`
  silently reports `0` on the real number shape → false `no_functions` abort after a successful
  restart). Fold the correction in (default) or file a tracking issue — do not leave the sibling
  asserting on a tolerated-zero.
- **`#5503` combined-stream purity is load-bearing.** The Phase-0 raw-shape diagnostic and any new
  echo MUST go to stderr/journald, never the success-path stdout — the webhook returns
  `cmd.CombinedOutput()` and the workflow jq-parses the body as an object. An accidental stdout echo
  breaks the parse (the exact regression that blocked the cutover before).
- **AC8 type-change reconciliation:** if `functions` changes from an array to a count number,
  `cutover-inngest.yml:239` (`.functions | length`) becomes wrong (length of a number is null) — it
  must be reconciled in the same PR or the `::notice::` silently mis-reports.
- **No-SSH host-op delivery is a multi-file lockstep**, but this PR does NOT add or rename a delivered
  script (it edits an existing one), so the FILE_MAP↔DEST_SPEC parity test does not need a count bump.
  Confirm by grepping the parity test for `inngest-inventory` (already present) — no new entry.
- **Post-merge `op=inventory` re-run is automatable** via `gh workflow run cutover-inngest.yml -f op=inventory`
  + `gh run watch` — it is NOT operator-manual. Bake AC9 into `/work` Phase 2 or `/soleur:ship`.
