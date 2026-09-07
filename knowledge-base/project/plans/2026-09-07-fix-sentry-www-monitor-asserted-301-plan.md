---
title: "fix: sentry_uptime_monitor.soleur_www pages on its own asserted 301 — the www redirect has no working alarm"
date: 2026-09-07
slug: fix-sentry-www-monitor-asserted-301
branch: feat-one-shot-7798-sentry-www-monitor-asserted-301
issue: 7798
closes: 7798
type: bug
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

> No `spec.md` exists for this branch, so no `lane:` could be carried forward —
> defaulted to `cross-domain` (TR2 fail-closed). The Domain Review below found
> Engineering to be the only relevant domain; the frontmatter value stays
> fail-closed regardless.

## Overview

The Sentry uptime monitor guarding `https://www.soleur.ai/` sits in a sustained
failure incident while recording exactly the response it declares as healthy. Its
Terraform config asserts `status_code_check(equals, 301)`, the live monitor
read back from the Sentry API carries that same assertion, and every check still
records `failure` at HTTP 301. The sibling ACME probe asserting `equals 404`
against a real 404 records `success`, so custom assertions are honoured in
general — the failure is specific to this monitor's shape.

The consequence is that the www→apex redirect currently has no working alarm, and
`soleur_www` is one of the monitors the ADR-194 apex-cutover CUT8 gate reads.
This plan establishes the real cause from live API evidence and restores a
working guard on the redirect-health property.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference the issue cites was checked against live state on 2026-09-07.

| Cited premise | Verification | Verdict |
|---|---|---|
| `#7798` is open and unresolved | `gh issue view 7798` → `state: OPEN`, `closedByPullRequestsReferences: []` | HOLDS |
| Declared config asserts `equals 301` | Read `apps/web-platform/infra/sentry/uptime-monitors.tf`, `soleur_www` block | HOLDS |
| Live assertion reads back `equals 301` | `GET /api/0/organizations/jikigai-eu/uptime/` → monitor id `1221117` carries `{"root":{"op":"status_code_check","value":301,"operator":{"cmp":"equals"}}}` | HOLDS — **live == declared, so there is no drift** |
| `soleur_www` uptimeStatus 2, checks fail at 301 | Same call: `uptimeStatus: 2`. Checks endpoint: 100/100 most-recent checks `failure_incident`, `httpStatusCode: 301` | HOLDS |
| ACME sibling asserts `equals 404` and succeeds | Monitor `1221116`: assertion `equals 404`, checks `success`, `assertionFailureData: null` | HOLDS |
| www genuinely 301s to apex | `curl -sSL -w '%{num_redirects} %{url_effective}'` → `1 https://soleur.ai/`; unfollowed → `HTTP/2 301`, `location: https://soleur.ai/` | HOLDS |
| "blocks the ADR-194 cutover; CUT8 can never pass" | The cutover is **already complete** — PR5 `44f93dd2b` ("retire the GitHub Pages publish leg") merged 2026-09-04, after PR4b `99eeebfef`. `cutover-verify.sh`'s CUT8 already passed via the baseline-comparison path | **STALE** — re-scoped below |
| Remediation: "dispatch apply, confirm it leaves incident state" | Live == declared, so the plan is a no-op on this attribute | **REFUTED** |
| Remediation fallback: "recreate rather than converge" | Recreation reproduces byte-identical config. Separately, the pinned provider marks only `organization`/`project` `RequiresReplace`, so `assertion_json` is an in-place update and a recreate is not even reachable by editing it | **REFUTED** |

**Re-scope.** The issue's framing ("blocks the cutover") no longer applies — the
cutover shipped and the baseline-comparison workaround held. What remains, and
is the real reason to act, is the two live harms the issue also names: the www
redirect has no working alarm, and a permanently-red monitor has been emitting a
standing incident (`WEB-PLATFORM-11`, 578 events, `firstSeen 2026-05-29T10:30:46Z`,
still unresolved) for 101 days.

### Root cause — established from vendor source, not inferred

`equals 301` on this URL is **structurally unsatisfiable**. Sentry's uptime
checker always follows 3xx redirects and evaluates the assertion against the
**final** response:

- `getsentry/uptime-checker` `src/checker/reqwest_checker.rs` builds its client
  with no `.redirect(...)` override, so it inherits `getsentry/reqwest-uptime`'s
  `Policy::default()` = `Policy::limited(10)`. There is no `CheckConfig` field
  and no API parameter to disable it.
- In the same file the assertion is evaluated as
  `compiled_assertion.eval(r.status(), r.headers(), &body_bytes, …)` where `r` is
  the response returned by `client.execute()` — i.e. the terminal response after
  the whole redirect chain has been resolved.
- Sentry's own docs state it: *"Sentry will follow redirects for URLs returning
  an HTTP status code in the 300–399 range and verify that the final destination
  URL returns a successful response. This ensures that redirects won't falsely
  create downtime issues."*
- There is **no** 2xx/3xx precondition ahead of assertions —
  `getsentry/sentry` `src/sentry/uptime/types.py` shows the 2xx rule is merely
  `DEFAULT_2XX_STATUS_ASSERTION`, substituted only when no custom assertion is
  configured. This refutes the competing "Sentry hard-fails all 3xx" hypothesis.

So the checker follows `www.soleur.ai` 301 → `soleur.ai` 200 and evaluates
`equals 301` against **200**. It has been false on every check since the
assertion landed, and always will be.

The `httpStatusCode: 301` on the check row — the datum that made this look like a
contradiction — is a per-hop artifact: `src/types/result.rs` builds one
`RequestInfo` per redirect hop, and `src/sentry/uptime/consumers/eap_converter.py`
stamps the check-level `checkStatus`/`assertionFailureData` (computed once, from
the final response) onto every hop's row. The row surfaced by the checks endpoint
carries hop 0's status code beside a verdict computed from hop 1.

This also explains the two facts that first looked like counter-evidence:

- **The ACME sibling passes.** Its URL returns 404 with no `Location`, so the
  chain terminates at hop 0 and `equals 404` sees the response it names. It is
  not evidence that assertions work on this monitor's shape — it is a case that
  never exercises redirect-following.
- **`durationMs` for `www` (median 101 ms) is *lower* than `apex` (128 ms)**,
  measured over 100 checks each, which appears to rule out a second fetch. Under
  the per-hop row model this is the same artifact as `httpStatusCode`: the row is
  hop 0's, so its duration is the www hop alone. Recorded because it was the one
  datum that pointed the other way, and it resolves rather than survives.

Residual UNVERIFIED: the per-hop-row explanation is read off vendor source, not
confirmed against a sibling `httpStatusCode: 200` row in this org (the checks
endpoint returns exactly one row per check — 100 rows over 100 five-minute
intervals — and no per-check or trace endpoint exposes the captured response;
`/organizations/<org>/trace/<id>/` returns `[]`). **The conclusion does not
depend on it**: redirect-following and final-response evaluation are established
independently, and each alone makes `equals 301` unsatisfiable.

### The property is inexpressible in Sentry Uptime

The pinned provider is `jianyuan/sentry` **0.15.7** (`versions.tf`
`required_providers`, matched by `.terraform.lock.hcl` — note the file's own
header comment narrates a historical `0.15.4` pin and is stale). Its complete
assertion catalog, verified by fetching the function docs at tag `v0.15.7`:

| Function | Sees |
|---|---|
| `op_and` / `op_or` / `op_not` | combinators |
| `op_status_code_check(operator, value)` — operators `equals`, `not_equal`, `less_than`, `greater_than`, `always`, `never` | final response status |
| `op_header_check(key_op, key_operand, value_op, value_operand)` | final response **headers** |
| `op_jsonpath(operand, operator, value)` | final response **body** |

Every op reads the terminal response. Consequences that bound the design:

- `op_header_check` on `Location` **cannot** work — the final response is the
  apex's 200, which carries no `Location`. This was the most attractive
  candidate fix and it is dead.
- `equals 200` would pass, but is satisfied equally by "www 301s to a healthy
  apex" and by "www serves its own 200" — the exact regression the monitor
  exists to catch. Vacuous for redirect-health.
- No op sees an intermediate hop, and there is no redirect-count op.

**There is therefore no way to express "www must 301 to apex" as a Sentry uptime
assertion.** The remediation is forced: the redirect-health property must move
off this substrate.

### Property List (Phase 0.6b)

- **P1 — Redirect-health has a continuous paging alarm.** If `https://www.soleur.ai/`
  stops returning 301 → `https://soleur.ai/`, a human is paged within a bounded time.
- **P2 — No standing false alarm.** The monitor stops emitting a permanently-red
  incident that trains alert-blindness.
- **P3 — The CUT8 baseline records no pre-existing failure**, so a future
  cutover-style gate can read absolute health rather than regression-vs-baseline.

Coverage of P1 already on `origin/main`, checked by reading each:

| Existing mechanism | Buys P1? |
|---|---|
| `apps/web-platform/infra/cutover-verify.sh` `check_redirect` (CUT3/CUT4) — asserts 301 + exact `Location` + absence of a GitHub/Fastly origin marker | **The assertion logic, not the alarm.** One-shot cutover script; pages nobody; runs only when invoked |
| `.github/workflows/deploy-docs.yml` "Probe www→apex 301" | No. Fires only on a docs deploy, and only to time the monitor resume |
| `apps/web-platform/infra/www-apex-canonicalizer.test.sh` | No. Config-drift guard on the declared Cloudflare Bulk Redirect at PR time; blind to runtime drift |
| `apps/web-platform/infra/uptime-alerts.tf` (Better Stack) | Not today — it carries no www monitor. **But this root can express the property, and Sentry cannot.** See below |

P1 is genuinely uncovered at runtime today.

**Correction — Better Stack is not ruled out, and this reverses the design.** The
first pass of this plan dismissed Better Stack on its header comment ("here for
VENDOR ISOLATION, not URL coverage… free tier caps the workspace at 10
monitors") and designed a bespoke scheduled probe instead. CTO review challenged
that, and the dismissal does not survive measurement:

- Only **2** `betteruptime_monitor` resources are declared ungated (`soleur_apex`,
  `app`). The one other `betteruptime_monitor` in the repo,
  `github_webhook_failures` in `alerts-github-webhook.tf`, carries
  `count = var.betterstack_paid_tier ? 1 : 0`, and that variable defaults to
  `false`. (That file's two other gated Better Stack resources are
  `betteruptime_heartbeat`, a different type — so "the others" is one monitor plus
  two heartbeats, not three monitors.) Live state, which supersedes this
  declaration count, is measured below.
- The pinned provider is `BetterStackHQ/better-uptime` **0.20.17**
  (`.terraform.lock.hcl`, `constraints = "~> 0.20"`). Its own docs at that tag
  state:
  - `follow_redirects` (Boolean) — *"Set to true for the monitor to follow
    redirects."* — i.e. **`false` is available**, which is exactly the knob Sentry
    does not have.
  - `monitor_type` accepts `expected_status_code` — *"We will check if your
    website returned one of the values in expected_status_codes."*
  - `expected_status_codes` (List of Number) — *"We will create a new incident if
    the status code returned from the server is not in the list."*
  - `confirmation_period` (Number, seconds) — *"How long should we wait after
    observing a failure before we start a new incident?"*
  - `monitor_type = "expected_status_code"` appears in-repo at
    `apps/web-platform/infra/alerts-github-webhook.tf` — **but that block is
    `count`-gated on `var.betterstack_paid_tier`, which defaults to `false`, so
    no `expected_status_code` monitor has ever actually run in this workspace.**
    (An earlier draft of this plan cited it as an established pattern; that
    overstated it. It is a syntax precedent, not a behavioural one.)

  No `ConflictsWith` is documented between `follow_redirects`, `monitor_type` and
  `expected_status_codes`.

**Live Better Stack state, measured 2026-09-07** via
`GET https://uptime.betterstack.com/api/v2/{monitors,heartbeats}` with
`BETTERSTACK_API_TOKEN` from Doppler `soleur/prd_terraform`:

| Fact | Value |
|---|---|
| Monitors live | **3** — `soleur dot ai apex`, `soleur app dashboard`, `app.soleur.ai/health` |
| Heartbeats live | **9** |
| All three monitors' `follow_redirects` | `true` |
| Any monitor with `monitor_type = expected_status_code` | **none** |

Two things follow, and both correct claims an earlier draft made:

1. **The quota arithmetic is settled empirically.** A plan-review pass raised
   that the free tier's "10 monitors" cap might be a pooled quota across monitors
   *and* heartbeats — in which case 2 + 8 declared would already be at the cap and
   this plan's addition would trip it mid-apply. The measurement refutes that:
   **3 monitors and 9 heartbeats coexist live**, so the cap is not a pooled 10.
   Read against monitors alone, the workspace is at 3 of 10 and this is the 4th.
   Phase 0 re-measures immediately before the block is written rather than
   trusting this snapshot.
2. **One live monitor is unmanaged.** `app.soleur.ai/health` (id `4226366`) has no
   `betteruptime_monitor` block anywhere in `apps/web-platform/infra/*.tf`, and its
   `pronounceable_name` equals its URL — the vendor default when none is set,
   which is what a dashboard-created monitor looks like. This is the Better Stack
   mirror of the Sentry orphan class that #4929 and #6074 were about. **Out of
   scope for this plan** — adopting or deleting it is a separate decision with its
   own blast radius — but it is recorded here and filed as a tracking issue rather
   than left as an unremarked observation.

So a single `betteruptime_monitor` with `follow_redirects = false` and
`expected_status_codes = [301]` asserts the property **directly**, at 180-second
cadence, in an already-wired Terraform root — no new workflow, no new script, no
new cron monitor, and no C4 count-parity edits. It dominates the scheduled-probe
design on every axis that matters here, and it is what this plan adopts.

The "vendor isolation, not URL coverage" principle is not being ignored — it is
being **amended**, and the amendment is recorded in ADR-204. That principle was
written while Sentry was believed able to cover the `www` host. Now that Sentry is
known to
be structurally unable to express this property, a Better Stack monitor for it is
not redundant second-vendor coverage; it is the only vendor that can express it.

`check_redirect()` in `cutover-verify.sh` remains the reference for the stricter
three-part assertion (status + exact `Location` + origin markers) that no uptime
vendor can express; the residual gap that leaves is scoped explicitly below.

### Cut List (Phase 0.6b)

| Mechanism proposed by the issue | Property claimed | Why cut |
|---|---|---|
| Dispatch `apply-sentry-infra.yml` to converge the monitor | P2 | Live assertion already equals declared assertion (measured). The plan is a no-op on this attribute; nothing converges |
| Recreate/replace the monitor in Terraform | P2 | Recreation reproduces byte-identical config against an unsatisfiable assertion. Also unreachable: only `organization`/`project` carry `RequiresReplace` in the pinned provider, so `assertion_json` edits are in-place |
| `op_header_check` on the `Location` header (candidate raised during this research, not by the issue) | P1 | Header ops read the **final** response, which is the apex 200 and carries no `Location` |

`--capture-monitor-baseline` is **not** cut: it is retained as P3, but demoted
from "the remediation" to a downstream step gated on the monitor actually going
green.

### Value-proposition measurement (Phase 0.6c)

Not applicable — the justification is correctness and observability, not a cost
or latency saving. No unquantified performance claim is load-bearing anywhere in
this plan.

### Institutional learnings that apply

- `knowledge-base/project/learnings/bug-fixes/2026-06-08-fetch-redirect-follow-makes-3xx-auth-probe-branch-dead.md`
  — **the same bug class, already documented in this repo.** An HTTP client that
  follows redirects by default consumes the 3xx and reports the final status, so
  a branch that classifies on 3xx is structurally unreachable. Predicts this
  defect exactly.
- `knowledge-base/project/learnings/2026-09-03-my-guard-blocked-the-recovery-and-missed-the-hazard.md`
  — from PR #7793, the very PR that shipped CUT8: a Sentry monitor's `.status`
  is *configuration* state and reads `active` during an outage. `cutover-verify.sh`
  consequently grades health from the **checks** collection, not `.status`. Any
  new health assertion here must read a field that can say "no".
- `knowledge-base/project/learnings/2026-08-09-the-monitor-reported-success-and-i-read-the-field-that-cannot-say-otherwise.md`
  — ask which field carries the fact and whether it can report failure.
- `knowledge-base/project/learnings/2026-05-29-verify-redirect-ownership-before-codifying-in-terraform.md`
  and `.../2026-05-29-redirect-rule-host-match-vs-canonicalizer-phase-ordering.md`
  — establish the live hop chain empirically before codifying redirect behaviour.
  Done: single hop, 301 → `https://soleur.ai/`, Cloudflare-served.
- `knowledge-base/project/learnings/2026-05-15-sentry-iac-billing-and-quirks.md`
  — the jianyuan provider is an unreliable narrator of vendor behaviour; check
  the live API rather than apply output.
- The `soleur_acme_probe` block in `uptime-monitors.tf` is the in-repo precedent
  for documenting a monitor whose assertion is semantically wrong while
  syntactically fine (it is *vacuously green* post-cutover). Its comment is the
  template for how this file records such a thing.

### Repo mechanics that constrain the implementation

- **Apply path.** `.github/workflows/apply-sentry-infra.yml` triggers on `push`
  to `main` filtered to `apps/web-platform/infra/sentry/**` and plans/applies the
  **full root** (`state UNION config`) since #6589 — the `-target=` allow-list was
  removed because it made deletion a silent no-op and orphaned live monitors
  twice (#4929, #6074). A merge is therefore the apply; no dispatch step exists
  or is needed.
- **Destroy gate.** `sentry-destroy-required` + `scripts/sentry-destroy-gate-verdict.sh`
  require a line containing exactly `[ack-destroy]`, alone on its own line, in a
  **commit body** (not a subject — GitHub prefixes squash subjects with an
  asterisk and a space,
  breaking the anchor). Per `tests/scripts/lib/destroy-guard-filter-sentry.jq`, a
  REPLACE serialises as `["delete","create"]` and trips the gate; a pure
  `["update"]` does not. **The design below is update-only and needs no ack.**
- **Create gate.** `scripts/sentry-create-gate.sh` is diff-matched: a create
  explained by a `resource` block the same PR adds passes silently.
- **Guard suites.** `apps/web-platform/scripts/sentry-monitors-audit.sh` and
  `scripts/sentry-monitor-binding-gate.sh` are scoped to `sentry_cron_monitor` /
  `sentry_alert` respectively and do not quantify over `sentry_uptime_monitor`.
- **`plugins/soleur/test/c4-count-parity.test.sh` is the orphan suite that will
  red.** It parity-gates four numeric clauses in `model.c4`'s `github -> sentry`
  edge against live derivations: C1 workflows containing `actions/sentry-heartbeat`,
  C2 those with a `schedule:` key, C3 those without, C4
  `grep -cF 'resource "sentry_cron_monitor"' cron-monitors.tf` (plus a derived
  webapp-slug count = C4 − C1). Adding one scheduled heartbeat workflow and one
  cron monitor moves C1, C2, C4 and the derived count. Its filename stem contains
  neither "sentry" nor "uptime", so a diff-scoped test run would not reach it.
- **Reusable check-in path.** `.github/actions/sentry-heartbeat` posts a single
  `ok|error` Sentry Crons heartbeat; callers pair it with
  `continue-on-error: true` so a Sentry blip never reds an otherwise-green probe.
  `scheduled-realtime-probe.yml` is the closest shape to copy.
- **Deploy-window interaction.** `deploy-docs.yml` pauses and resumes
  `soleur-ai-www` around the Pages publish because a rebuild transiently makes
  www serve its own 200 instead of the 301 (#4596, Option A). Note the dates:
  `WEB-PLATFORM-11` opened `2026-05-29T10:30:46Z` — 12:30 CEST, exactly the flap
  that comment cites — and the `equals 301` assertion landed the same day in
  `a546a7986` (#4578). The incident opened as a genuine transient and was then
  frozen open by an assertion that can never recover. The suppression machinery
  built afterwards has never been able to help.

### Related issues and PRs

`#7798` (this issue) · `#4577`/`#4578` (apex-canonical reconcile; introduced the
`equals 301` assertion) · `#4595`/`#4596` (soleur_www threshold and the
pause/resume suppression) · `#4585` (uptime monitors joined auto-apply) ·
`#4929`/`#6074` (orphaned monitors) · `#6589` (full-root apply, destroy/create
gates) · `#6636` (provider bump) · `#7209` (C4 count parity gate) · `#7640` /
ADR-194 (apex cutover) · `#7793` (PR4b, CUT8 + baseline) · `#7824` (PR5, cutover
complete).

### Conventions carried forward

- `hr-no-dashboard-eyeball-pull-data-yourself` — all live state in this plan was
  pulled via the Sentry API using `SENTRY_IAC_AUTH_TOKEN` from Doppler
  `soleur/prd_terraform`. No dashboard reading is delegated anywhere.
- `hr-all-infrastructure-provisioning-servers` — every change lands as Terraform
  under `apps/web-platform/infra/sentry/` or as a committed workflow, applied by
  merge. No dashboard or CLI mutation step.
- `hr-verify-repo-capability-claim-before-assert` — the two load-bearing
  capability claims here (the provider's `always` operator, and `op_header_check`)
  were verified by fetching the provider function docs at tag `v0.15.7`, not
  recalled.
- `hr-observability-as-plan-quality-gate` — `## Observability` below.
- `wg-use-closes-n-in-pr-body-not-title-to` — `Closes #7798` on its own body line.
- `cq-assert-anchor-not-bare-token` — verification commands below anchor on
  clause text, never a bare numeral.

### Open Code-Review Overlap

None. Every planned path was matched against the 63 open `code-review` issues
(`gh issue list --label code-review --state open --json number,title,body --limit 200`,
then `jq --arg path … | contains($path)` per path); zero issues reference any of
them.

## Research Reconciliation — Issue Claims vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "The live monitor's assertion looks correct… yet its checks still record failure" — framed as an unexplained defect | Fully explained: the checker follows the 301 and evaluates the assertion against the apex's 200. Sourced from `getsentry/uptime-checker` and Sentry's own docs | Root cause section above; the design follows from it rather than from a converge/recreate guess |
| "The discriminator ruling out 'Sentry fails all non-2xx' is the sibling ACME probe" | The discrimination is sound but the conclusion drawn from it is not. `getsentry/sentry` `types.py` shows the 2xx rule is only a *default* assertion; ACME passes because its URL does not redirect, so hop 0 is the final response | Both the discarded hypothesis and the real one are recorded, so the next reader does not re-derive them |
| "Dispatch `apply-sentry-infra.yml` and confirm the monitor leaves incident state" | Live assertion already equals declared. The plan is a no-op on this attribute; there is nothing to converge | Cut. Merge still triggers the apply — but for the *new* config this plan writes |
| "If the apply is a no-op, the divergence originated outside Terraform and the monitor needs to be recreated" | The apply *is* a no-op, but the inference does not follow — there is no divergence to recreate away. A recreate reproduces byte-identical config, and is unreachable via `assertion_json`, an in-place attribute in the pinned provider | Cut. The plan does **not** replace the resource, and therefore needs no `[ack-destroy]` |
| "`soleur_www` is one of five monitors CUT8 requires green… CUT8 can never pass… a healthy cutover would be rolled back" | The cutover is complete (PR5 `44f93dd2b`, 2026-09-04). CUT8 graded via the baseline-comparison path and held | Urgency re-scoped from "unblock the cutover" to "the redirect has no alarm, and a standing false incident has run for 101 days" |
| "Re-run `--capture-monitor-baseline`" | Correct, but only *after* the monitor can be green — capturing now would freeze the same failure | Retained as a post-merge step gated on measured green |

## User-Brand Impact

**If this lands broken, the user experiences:** `https://www.soleur.ai/` silently
stops redirecting to the canonical apex — serving duplicate content on a second
hostname, splitting search-engine signal for the marketing site, and presenting
visitors a non-canonical host — with nothing paging anyone, because the alarm
meant to catch it is the thing being repaired. The subtler failure is the one
that actually recurs here: a monitor that reports green without having measured
the property installs a false all-clear, which is worse than the honest red it
replaces. That is the exact shape of the defect this issue is about, and of the
`soleur_acme_probe` vacuity already documented one resource away.

**If this leaks, the user's data is exposed via:** no new exposure surface. The
new monitor reads a public unauthenticated URL from the vendor's own probe
network and stores a status code. No personal data, no new credential, no
response body captured.

**Brand-survival threshold:** `aggregate pattern`

Rationale: the harm is gradual SEO and canonicalization degradation across all
visitors, not a per-user data incident. No `requires_cpo_signoff`; the
`user-impact-reviewer` agent is not mandatory at review.

## Architecture Decision (ADR/C4)

Detection fires. This plan records a **permanent vendor constraint**, **moves a
monitored property between vendors**, and **amends a stated design principle**
(Better Stack's "vendor isolation, not URL coverage"). It also invalidates a
load-bearing architectural rationale in `dns.tf` — see the Camp B finding below.
A future engineer reading only the current ADRs and comments would be actively
misled about where redirect-health is enforced.

### ADR

Create **ADR-204 — "Redirect-health is inexpressible in Sentry Uptime; it moves
to Better Stack with `follow_redirects = false`"**, via `/soleur:architecture`,
as an in-scope task of this plan.

`## Decision` records: Sentry's uptime checker always follows 3xx and evaluates
assertions against the terminal response, and its entire op catalog
(`status_code_check` / `header_check` / `json_path`) reads only that terminal
response — so "must 301 to X" is permanently inexpressible there. Better Stack's
`follow_redirects = false` + `monitor_type = "expected_status_code"` can express
it. The property therefore moves vendors, the Sentry monitor is retargeted to
reachability, and Better Stack's role is **amended** from "vendor isolation only"
to "vendor isolation, plus properties Sentry structurally cannot express".

`## Alternatives Considered` records all five cut mechanisms below.

Relates to ADR-031 (Sentry-as-IaC), ADR-194 (the cutover that made www's
canonicalization Cloudflare-owned). Amends the Better Stack scoping rationale in
`uptime-alerts.tf`; supersedes no ADR.

**Ordinal is PROVISIONAL.** `ADR-204` was verified free across **all 71
`refs/remotes/origin/*` refs** on 2026-09-07 (highest claimed: ADR-203) — not just
`origin/main`. Re-derive immediately before merge and after every rebase; if it
moves, sweep the whole feature artifact set in one edit:
`grep -rn 'ADR-204' knowledge-base/project/{plans,specs}/ apps/ .github/`.

### C4 views

All three model files were **read**, not keyword-grepped:
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`.

Enumeration performed for this change:

- **External human actors** — none new. The page still reaches `founder`, now over
  the existing `betterstack -> founder` edge as well as `sentry -> founder`. Both
  edges exist and both remain accurate.
- **External systems** — none new. `betterstack` and `sentry` are both already
  modeled, both tagged `#external`, and both already included in the `context` and
  `containers` views. No `view … include` line is needed.
- **Containers / data stores touched** — none.
- **Access relationships that change** — none.

**No count-parity clause moves.** `plugins/soleur/test/c4-count-parity.test.sh`
gates seven clauses (C1–C6 on `github -> sentry`, C7 on `github -> resend`); every
one derives from heartbeat workflows, `sentry_cron_monitor` blocks, or Resend
emitters. This plan adds no workflow, no cron monitor and no emitter, so C1–C7 are
untouched. **This is a direct consequence of choosing the Better Stack design** —
the rejected scheduled-probe design would have moved C1, C2, C4, C5 and C6, and
that suite's filename stem contains neither "sentry" nor "uptime", so a
diff-scoped run would not have reached it.

One C4 **description** edit is required for correctness, though no test enforces
it: the `betterstack` element enumerates its monitors in prose ("Apex + inngest +
registry-disk heartbeats, plus … TWO new per-host web heartbeats …"). That list
becomes incomplete and must gain the www redirect monitor, along with a clause
recording that this monitor is the one Better Stack holds *because Sentry cannot
express it*.

### Sequencing

None. The decision is true the moment the monitor applies; ADR-204 is authored at
`status: accepted`, not `adopting`.

## Infrastructure (IaC)

### Terraform changes

| File | Change | Plan action |
|---|---|---|
| `apps/web-platform/infra/uptime-alerts.tf` | **new** `betteruptime_monitor.soleur_www_redirect` | create |
| `apps/web-platform/infra/sentry/uptime-monitors.tf` | `soleur_www.assertion_json` → `local.uptime_assertion_2xx` | in-place update |

Providers, both already pinned and locked, neither bumped:
`BetterStackHQ/better-uptime 0.20.17` and `jianyuan/sentry 0.15.7`.

**No new Terraform variable and no new secret.** The Better Stack root already
authenticates via its existing token; the new monitor is **ungated** (no
`count = var.betterstack_paid_tier ? 1 : 0`) and carries `policy_id` as the same
free-tier-null ternary its three siblings use, so it
alerts by email on the free tier exactly as `soleur_apex` and `app` already do.
`hr-tf-variable-no-operator-mint-default` is not engaged.

### Apply path

**(b) — merge-triggered convergence, two independent roots, no bootstrap script.**
The two roots do **not** work the same way, and an earlier draft of this plan
asserted "merge-triggered convergence" for both after verifying it for only one.

- `apps/web-platform/infra/sentry/**` is applied by `apply-sentry-infra.yml` on
  merge, **full-root** since #6589. Declaring a resource applies it.
- `apps/web-platform/infra/**` is applied by `apply-web-platform-infra.yml` on
  merge, but that root is **`-target=`-scoped against a hand-maintained
  allow-list of 258 entries**, split across two stages by credential transport.
  Its own maintenance note is explicit: *"if a future PR adds a new `.tf`
  resource at `apps/web-platform/infra/*.tf`, append a matching `-target=<addr>`
  line below."*

**Therefore `-target=betteruptime_monitor.soleur_www_redirect` MUST be appended
to that allow-list, or the monitor is declared and never applied.** It belongs in
the **bridge-less** (first) stage beside its siblings —
`-target=betteruptime_monitor.soleur_apex`, `-target=betteruptime_policy.uptime`,
`-target=betteruptime_monitor.app` — because it is not SSH-provisioned and the
second stage is for post-bridge resources only.

This is the same declared-but-never-applied class that #6589 removed from the
sentry root and that orphaned live monitors twice (#4929, #6074); the
web-platform root still carries it.

**The omission is NOT silent, and an earlier draft of this plan said it was.**
That draft read only the first coverage `describe` in
`plugins/soleur/test/terraform-target-parity.test.ts` — which is scoped to
SSH-provisioned `terraform_data` resources — and concluded no guard existed. It
does: the **Non-SSH resource coverage (#5566)** guard further down the same file
asserts every managed resource address is either `-target=`-ed or listed in
`OPERATOR_APPLIED_EXCLUSIONS`, and it runs in the `test-bun` shard feeding the
required `test` aggregator. Forgetting the line fails CI loudly. (Recording the
mistake rather than quietly fixing it: this is the truncated-read failure mode
the plan's own Sharp Edges warn about, committed inside a plan about an
unverified claim.)

**The real risk is therefore the escape hatch, not the omission.** A red #5566
guard has two ways to go green: add the address to the `-target=` list (correct),
or add it to `OPERATOR_APPLIED_EXCLUSIONS` (green CI, monitor never applied —
reproducing #5566's own defect class on the exact monitor this plan exists to
make effective). The plan therefore carries an explicit AC that the address is in
the `-target=` set **and absent from `OPERATOR_APPLIED_EXCLUSIONS`**, so the
wrong remedy cannot pass.

Plan shape is **one create (Better Stack) and one update (Sentry), zero deletes
and zero replaces**:

- The Sentry update does not trip `[ack-destroy]` —
  `tests/scripts/lib/destroy-guard-filter-sentry.jq` counts only
  `index("delete")`, and a pure `["update"]` is neither a delete nor a create.
- No Sentry create occurs, so `scripts/sentry-create-gate.sh` has nothing to
  match.

No downtime; nothing user-facing changes. Blast radius is one new vendor monitor
plus one assertion swap on a monitor that is already failing 100% of checks.

### Distinctness / drift safeguards

Sentry is a single org (`jikigai-eu`) and Better Stack a single workspace, so
there is no dev/prd pair to keep distinct here. No `lifecycle.ignore_changes` is
added or relied upon. State lives in the existing encrypted R2 backends. The new
monitor writes no secret into state — its attributes are a URL, a status-code
list, three integers and three booleans.

### Vendor-tier reality check

Better Stack's free tier caps the workspace at 10 **monitors**. **Measured live
2026-09-07: 3 monitors and 9 heartbeats.** This monitor is the 4th of 10.

The pooled-quota worry raised at plan review — that heartbeats might count
against the same 10 — is refuted by the measurement itself: 12 resources already
coexist, so the cap cannot be a pooled 10. Recording that explicitly because the
next engineer adding a monitor should inherit a measured number, not the
arithmetic-from-`.tf`-blocks that an earlier draft of this plan got wrong (it
counted 2, because it counted declarations rather than live state and missed the
unmanaged `app.soleur.ai/health`).

`check_frequency = 180` is deliberately the free-tier-allowed 3 minutes — the
file's own header records that sub-minute checks are paid — and **no
`betteruptime_policy` is attached**, which is the resource the free tier rejects
and the reason every paid-tier-only block in this root carries a `count` gate.

**Recurring cost: none.** The monitor is ungated and policy-less, so it rides the
existing free-tier email path at zero marginal spend, and no expense-ledger entry
is required. What Phase 0 records instead is the **headroom fact** (4 of 10
monitors after this PR), flagged as the trigger point for a
`var.betterstack_paid_tier` conversation if a future gap pushes the count toward
the cap. Phase 0 re-measures before the block is written so the apply cannot fail
on a cap mid-merge.

## Observability

```yaml
liveness_signal:
  what: betteruptime_monitor.soleur_www_redirect probes https://www.soleur.ai/
        and requires HTTP 301 without following the redirect. Better Stack opens
        an incident when the observed status is not 301.
  cadence: check_frequency 180s; confirmation_period 1200s before an incident opens (~20 min worst-case MTTD)
  alert_target: Better Stack email notification to the founder (the existing
                betterstack -> founder edge); policy_id null under the free tier, email route
  configured_in: apps/web-platform/infra/uptime-alerts.tf
error_reporting:
  destination: Better Stack incident (primary) and, for the reachability half,
               the Sentry uptime downtime issue on soleur_www
  fail_loud: true — an unreachable www fails BOTH vendors independently, which is
             the vendor-isolation property this root exists for. Neither can
             suppress the other.
failure_modes:
  - mode: the Cloudflare Bulk Redirect stops firing and www serves the site
          directly (HTTP 200, no redirect) — the exact failure the dns.tf Camp B
          ruling accepts as tolerable "for one monitor interval"
    detection: expected_status_codes [301] does not contain 200, with
               follow_redirects false so the 200 is actually observed rather than
               resolved away
    alert_route: Better Stack incident -> email
  - mode: www returns 302/307/308 instead of 301 (a weaker or temporary redirect
          that search engines treat differently)
    detection: expected_status_codes is the exact list [301], not a 3xx class
    alert_route: same
  - mode: www unreachable entirely (NXDOMAIN, TLS failure, 5xx, connect timeout)
    detection: TWO independent vendors — Better Stack sees a non-301, and
               sentry_uptime_monitor.soleur_www (retargeted to 2xx, 300s interval,
               downtime_threshold 3) fails at ~15 min
    alert_route: Better Stack incident + Sentry downtime issue
  - mode: the monitor itself goes vacuous — a future edit flips follow_redirects
          to true, or widens expected_status_codes to include a 2xx, restoring the
          exact defect this issue is about
    detection: www-apex-canonicalizer.test.sh asserts all three load-bearing
               values at PR time (Guard Contract below). This is the mode with
               precedent: it has now happened once on Sentry and once, in mirror
               image, on soleur_acme_probe
    alert_route: CI red at PR time
  - mode: the 301 fires but points at the wrong target, or is served by a stale
          GitHub/Fastly origin
    detection: NOT covered at runtime by any vendor — see Residual Gap below.
               Covered at PR time by www-apex-canonicalizer.test.sh (declared
               config) and at cutover time by cutover-verify.sh CUT3/CUT4
    alert_route: CI red at PR time only
logs:
  where: Better Stack incident timeline and per-check history for the monitor;
         Sentry uptime check records for soleur_www
  retention: Better Stack free-tier retention; Sentry event retention on the
             web-platform project
discoverability_test:
  command: bash apps/web-platform/infra/cutover-verify.sh --check-www-redirect
  expected_output: |
    CUT3 PASS https://www.soleur.ai/ -> https://soleur.ai/
    (exit 0)
  credentials_required: none — this mode exits before any token is read, so the
    property is verifiable against a public unauthenticated URL by anyone, from
    anywhere, with nothing. Confirming the SEPARATE question "is the vendor
    monitor configured correctly" needs BETTERSTACK_API_TOKEN and is deliberately
    not folded in here.
```

**No new script.** An earlier draft created `www-redirect-check.sh`, described in
its own Files-to-Create entry as *"a thin wrapper over the same three-part
assertion `cutover-verify.sh` `check_redirect()` already implements"* — i.e. it
announced the duplication it was committing. Both DHH and the simplicity review
called it, and they are right: a second copy of the origin-marker heuristic drifts
from the first the moment either is edited.

Instead, `cutover-verify.sh` gains a fourth mode, `--check-www-redirect`, beside
its existing `--expected-sha` / `--capture-baseline` / `--capture-monitor-baseline`.
It calls the existing `check_redirect CUT3 "https://www.$APEX/" "https://$APEX/"`
and exits — one new case arm, zero duplicated logic, and the assertion stays
single-sourced. The mode must return before the script's credentialed paths so the
`credentials_required: none` claim above holds literally.

### Operator-facing naming and the runbook

`betteruptime_monitor` exposes **no `description` or `note` field** (verified
against the pinned provider's argument list) — `pronounceable_name` is the only
operator-facing string, and it is what lands in the incident email subject. Both
existing monitors set it (`"soleur dot ai apex"`, `"soleur app dashboard"`); an
earlier draft of this plan omitted it entirely, which would have left the alert
titled by the vendor's URL default.

After this plan www is watched by two alarms meaning different things, so the
names must disambiguate in an inbox at a glance:

| Alarm | Operator-visible name | Means |
|---|---|---|
| Better Stack | `soleur dot ai www redirect 301` | www stopped 301-ing to the apex |
| Sentry | `soleur-ai-www-reachability` (renamed — see Files to Edit) | www is unreachable / 5xx |

Because the only actionable string is a name, the paging path needs a
destination: **create
`knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md`**, following
the 69-file convention in that directory (`# Runbook: …` + `**TL;DR:**`). It states
which alarm means what, the one-command reproduction
(`cutover-verify.sh --check-www-redirect`), where the redirect is declared
(`seo-bulk-redirects.tf`, `cloudflare_list.www_canonical`), and the first
diagnostic step. Every corrected comment cites it, and cites the sibling monitor by
**both** Terraform address and `pronounceable_name`, so a reader starting from
either the code or an inbox email can reach the other.

## Guard Contract

### Guard 1 — the load-bearing-attribute assertion on `soleur_www_redirect`

Added to the **existing** `apps/web-platform/infra/www-apex-canonicalizer.test.sh`
suite rather than a new file: that suite already owns "the www canonicalization is
declared correctly", and this is the same question asked of the alarm.

**Property.** The declared `betteruptime_monitor.soleur_www_redirect` block cannot
silently become vacuous or anonymous: it asserts exactly `[301]`, it does **not**
follow redirects, it is not gated off, and it carries a `pronounceable_name` that
distinguishes it from the sibling apex monitor. Each is a single-token edit away
from restoring a defect class this repo has already shipped twice.

**Assembly.** The property quantifies over the whole
`resource "betteruptime_monitor" "soleur_www_redirect"` block in
`apps/web-platform/infra/uptime-alerts.tf` — the block delimited by its `resource`
header and its closing brace, extracted as a unit before any attribute is read.
This is the chokepoint: assertions must run against that extracted block, never
against a whole-file grep, because a whole-file grep for `follow_redirects = false`
is satisfied by *any* monitor in the file — and that file already contains two
monitors legitimately setting `follow_redirects = true`. Neighbouring-block
confusion is the concrete way this guard goes vacuous.

**This reuses machinery the target suite already owns**, which is why it is an
extension rather than new infrastructure:
`apps/web-platform/infra/www-apex-canonicalizer.test.sh` already ships
`strip_comments(file)`, `hcl_block(type, name, file)` and `attr(key, blocktext)`,
and already uses exactly this block-scoped shape to assert five `cloudflare_*`
resources' attributes. Two implementation notes that are easy to get wrong:

- `hcl_block` takes a `file` argument, but every existing call site passes a
  `dns.tf` / `cf-pages.tf` / `seo-bulk-redirects.tf` path. This is the first call
  against `uptime-alerts.tf`, so Phase 1 must confirm the extractor is not
  incidentally coupled to one of those path variables.
- The suite's anti-vacuity floor is an **exact cardinality** with two
  stage-dependent arms (`EXPECTED_CASES=24` / `EXPECTED_CASES=23`), deliberately
  literal so it cannot become a tautology. **Both arms must be bumped by the
  number of cases added**, or the suite fails closed with
  `[FATAL] vacuity floor: … a case was deleted, skipped, or added without
  updating EXPECTED_CASES`. There is also a `PASS + FAIL == CASES` accounting
  check that reports outside the suite's own `fail` helper — which is what makes
  harness row H1 below actually detectable.

**Mutation matrix** — derived from the design, written before the block:

| # | Mutation | Why it must red |
|---|---|---|
| M1 | `follow_redirects = false` → `true` | Reproduces the Sentry defect exactly: the probe resolves to the apex 200 and `[301]` can never match |
| M2 | `expected_status_codes = [301]` → `[301, 200]` (or `[200]`, or a widened 3xx set) | Admits the precise state the monitor exists to catch |
| M3 | **Guard's own dispatch:** rename the resource, or delete the block entirely, so the extractor finds nothing | A guard that passes when its subject is absent is vacuous — the suite must fail on an empty extraction, not skip. This is the row that catches the class |
| M4 | **Second member after a compliant first:** leave `follow_redirects = false` correct but flip `expected_status_codes`, and vice-versa | Proves the suite checks *every* load-bearing attribute rather than stopping at the first satisfied one |
| M5 | Add `count = var.betterstack_paid_tier ? 1 : 0` to the block | The monitor would silently never be created — the resource reads correct while provisioning nothing, which no attribute-value assertion alone would catch |
| M6 | Delete `pronounceable_name`, or set it to a string that does not distinguish it from the apex monitor | The only operator-facing string on this resource. Without it the incident email is titled by the vendor's URL default, and the two www alarms become indistinguishable in an inbox — an observability defect even though the monitor still *functions* |

**Harness rows** — mutations to the SUITE, plus a non-canonical must-PASS:

| # | Row | Expected |
|---|---|---|
| H1 | Stub every new assertion body in the suite to `true` | Suite RED — the existing `PASS + FAIL == CASES` accounting check reports outside the suite's own `fail` helper, so a stubbed case produces no verdict and trips it. Verified present at `www-apex-canonicalizer.test.sh`, not assumed |
| H2 | Reformat the block: reorder attributes, change whitespace/alignment, and write `expected_status_codes = [ 301 ]` with inner spaces | Suite **PASS** — the contract is about values, not formatting. This is the must-PASS row that is not the canonical fixture, and it is what proves the guard does not simply reject everything |

### No Guard 2 — the allow-list is already guarded

An earlier draft of this plan specified a second guard asserting that every
ungated `betteruptime_*` resource appears in the apply workflow's `-target=` list.
It is **cut**: `terraform-target-parity.test.ts`'s Non-SSH resource coverage
(#5566) guard already enforces exactly that property, repo-wide, and re-writing it
here would be a narrower copy of a check that already runs — the same
mechanism-duplication this plan cut the scheduled-probe design for.

What that guard does *not* distinguish is the two ways to satisfy it, so the
residual risk moves to an acceptance criterion rather than a new guard: the
address must be in the `-target=` set and **not** in `OPERATOR_APPLIED_EXCLUSIONS`
(AC5b).

## Residual Gap (explicit, scoped, tracked)

No uptime vendor can assert the redirect's **target** — Better Stack matches the
status code only, and Sentry cannot see the hop at all. So "www 301s, but to the
wrong host" and "the 301 is served by a stale GitHub/Fastly origin" remain
**runtime-undetected**. They are covered:

- at PR time, by `www-apex-canonicalizer.test.sh` over the declared Cloudflare
  Bulk Redirect (source and target hosts, `status_code = 301`);
- at cutover time, by `cutover-verify.sh` CUT3/CUT4;
- on demand, by `cutover-verify.sh --check-www-redirect`.

Reaching that state therefore requires a change made outside Terraform. This plan
**does not** build a scheduled probe for it — that was the rejected design, and
its cost (a workflow, a script, a cron monitor, a test battery and five C4 parity
clauses) is not proportionate to a threat the declared-config gate already blocks
on the only path Terraform owns. A tracking issue is filed recording the gap and
its re-evaluation trigger (any future evidence of a Cloudflare-side change
reaching production without a Terraform apply). Per DHH's review the issue stays
two paragraphs — a sticky note, not a spec.

**Second, and worth stating rather than leaving to be rediscovered:
redirect-health is now a SINGLE-VENDOR property.** Apex reachability is watched by
Sentry *and* Better Stack, deliberately, so a Sentry outage is survivable. The www
redirect is watched only by Better Stack, because it is the only vendor that can
express it. That is a net gain — the property went from zero working alarms to one
— not a regression from two to one, and it does not undermine the second-source
design for the properties that have it. But a future engineer must not infer from
the apex pattern that a Better Stack outage leaves this property still covered. It
does not, and ADR-204 says so explicitly.

## Files to Edit

- `apps/web-platform/infra/uptime-alerts.tf` — add
  `betteruptime_monitor.soleur_www_redirect`; amend the "Why apex only (not www…)"
  header comment, which is the stated principle this plan revises, citing ADR-204.
- `apps/web-platform/infra/sentry/uptime-monitors.tf` — retarget
  `soleur_www.assertion_json` to `local.uptime_assertion_2xx`; rewrite the
  resource comment and the `WHY FOUR MONITORS` header bullet 2. Say plainly what
  the monitor now does and does not guard, in the voice the adjacent
  `soleur_acme_probe` comment already uses for exactly this situation.
- `apps/web-platform/infra/www-apex-canonicalizer.test.sh` — add the Guard 1
  assertions; correct the two comments citing
  `sentry_uptime_monitor.soleur_www (equals 301)` as the runtime guard.
- **`apps/web-platform/infra/dns.tf` — the load-bearing one.** Two sites:
  (a) "Runtime drift of the 301 is guarded by `sentry_uptime_monitor.soleur_www`";
  (b) the **"WHY www STAYS A CNAME (Camp B; CTO ruling)"** block, which accepts a
  real failure mode on the strength of this monitor — *"if the Bulk Redirect ever
  stops firing, www SERVES the site (duplicate content for one monitor interval)
  rather than returning a 522"*. That acceptance has been resting on an assertion
  that has never once evaluated true, so the accepted bound was never real. The
  Better Stack monitor at 180s + 1200s confirmation restores an interval consistent
  with what Camp B assumed; the comment must be corrected to name the monitor that
  actually provides it. **This is why the MTTD target is minutes and not hours** —
  an hourly probe would have quietly widened a documented architectural
  acceptance, which the rejected design would have done without saying so.
- `apps/web-platform/infra/fixtures/dns.tf.pr4a-baseline` — carries the same stale
  claim. Phase 0 determines whether it is asserted against literally; if it is a
  frozen point-in-time baseline it is left alone and excluded deliberately, per
  the convention that migration fixtures record the old state.
- `plugins/soleur/skills/seo-aeo/SKILL.md` — cites
  `sentry_uptime_monitor.soleur_www` as covering a canonical-host flip. Re-verify
  and repoint; the claim is about a config-drift class, so it may need only a
  pointer change rather than a rewrite.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — the `betterstack`
  element's monitor enumeration.
- **`knowledge-base/engineering/architecture/decisions/ADR-194-*.md` — an ACCEPTED
  ADR that this plan makes false in two places** and that an earlier draft missed
  entirely, because the consumer grep was run with `':!knowledge-base'` and so
  excluded the very corpus most likely to carry an architectural claim. Both
  passages assert that `sentry_uptime_monitor.soleur_www` guards redirect drift —
  one saying it "keeps working unchanged because the asserted URL does not move",
  the other that a Bulk-Redirect failure is "caught by `sentry_uptime_monitor.soleur_www`
  within one confirmation interval". Both go false the moment the assertion becomes
  2xx, by this plan's own analysis. Append an amendment note at each pointing to
  ADR-204, mirroring the `dns.tf` correction. (A third passage, about HTTP 526
  detection, stays true — a 2xx assertion still fails on 526 — and must not be
  "corrected".)
  `knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md`
  also cites the monitor, but only as historical narration of the #7798 incident
  at cutover time; it asserts no ongoing guarantee and is deliberately left alone.
- `apps/web-platform/infra/cutover-verify.sh` — the CUT8 PASS message names
  `soleur-ai-www` and `#7798` as a known pre-existing failure covered in-band by
  CUT3/CUT4. Stale once the monitor can be green.
- `apps/web-platform/infra/cutover-monitor-baseline.txt` — re-captured by script
  in Phase 5, never hand-edited.
- `.github/workflows/deploy-docs.yml` — see Phase 4.
- **`.github/workflows/apply-web-platform-infra.yml` — append
  `-target=betteruptime_monitor.soleur_www_redirect`** to the bridge-less (first)
  stage's allow-list, beside `-target=betteruptime_monitor.soleur_apex` /
  `-target=betteruptime_policy.uptime` / `-target=betteruptime_monitor.app`.
  Without this the resource is declared and never applied, and nothing reports it
  (Guard 2). This entry was missing from an earlier draft of this plan, which
  asserted full-root convergence for a root that is `-target=`-scoped.
- `apps/web-platform/infra/cutover-verify.sh` — in addition to the stale CUT8
  message, add the `--check-www-redirect` mode and its `usage()` line, and update
  the `SENTRY_MONITORS` array for the rename below.

### The Sentry monitor is renamed, not just retargeted

Retargeting `soleur_www`'s assertion while leaving it named for the property it no
longer checks would reproduce, deliberately, the exact "syntactically fine,
semantically wrong" trap this plan documents on `soleur_acme_probe` — and which
`equals 301` itself is an instance of. So the resource and its Sentry `name` are
renamed to say what they now assert:

- Terraform address: `sentry_uptime_monitor.soleur_www` → `…soleur_www_reachability`
- Sentry `name`: `"soleur-ai-www"` → `"soleur-ai-www-reachability"`

`name` is an in-place attribute in the pinned provider (only `organization` and
`project` carry `RequiresReplace`), so this is still update-only and still needs no
`[ack-destroy]`. Full consumer list, derived by
`git grep -n 'soleur-ai-www' 'sentry_uptime_monitor\.soleur_www'` rather than
recalled — every one is already in this plan's edit set, which is what makes the
rename cheap:

| Consumer | Disposition |
|---|---|
| `sentry/uptime-monitors.tf` (block + `name`) | renamed |
| `cutover-verify.sh` `SENTRY_MONITORS` array, plus its two comments | renamed |
| `cutover-monitor-baseline.txt` | re-captured in Phase 5 under the new key |
| `deploy-docs.yml` (5 references) | all inside the bracket Phase 4 removes |
| `dns.tf`, `www-apex-canonicalizer.test.sh`, `uptime-alerts.tf`, `seo-aeo/SKILL.md`, `fixtures/dns.tf.pr4a-baseline` | already being corrected for semantics; the address changes in the same edit |

Sequencing hazard, and why it fails safe: `cutover-verify.sh` resolves monitors by
name, so if the array and the `name` diverge, CUT8 reports `unknown` and
`--capture-monitor-baseline` **refuses to write** rather than recording a wrong
state. An AC asserts the array and the `name` match.

## Files to Create

- `knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md` — short
  runbook, following the directory's 69-file `# Runbook: …` + `**TL;DR:**`
  convention. States which of the two www alarms means what, the one-command
  reproduction, where the redirect is declared, and the first diagnostic step. It
  is the destination the paging path currently lacks: `betteruptime_monitor` has
  no `description` field, so without this the alert ends at a name in an inbox.
- `knowledge-base/engineering/architecture/decisions/ADR-204-*.md`.

**Deliberately not created:** `www-redirect-check.sh`. An earlier draft added it
and described it as a wrapper over logic `cutover-verify.sh` already has; it is
replaced by a `--check-www-redirect` mode on that script (see Observability).

## Implementation Phases

### Phase 0 — Falsify the vendor claim, then the rest of the preconditions

**Step 1 is the most important step in this plan, and it gates everything after
it.** The design rests on one claim taken from vendor documentation rather than
measured: that Better Stack with `follow_redirects = false` and
`expected_status_codes = [301]` evaluates the **pre-redirect** 301. If that is
wrong, the new monitor is as vacuous as the one it replaces — permanently red,
emailing on every cycle, with no escalation policy live on the free tier to
   dampen it — and the plan
would have reproduced this issue's own defect on a second vendor while also
weakening the Sentry monitor. Post-merge detection is too late for that, and it is
not something to discover from an alert.

1. **Transient falsification probe — diagnosis only, never left in place.**
   `POST https://uptime.betterstack.com/api/v2/monitors` with
   `BETTERSTACK_API_TOKEN` from Doppler `soleur/prd_terraform`, creating a probe
   against `https://www.soleur.ai/` with exactly `monitor_type
   "expected_status_code"`, `expected_status_codes [301]`, `follow_redirects
   false`, and — critically — **`confirmation_period 0`**, so a failure is visible
   immediately instead of being masked for the confirmation window. Wait one
   `check_frequency` cycle, read the monitor's status **and its check's recorded
   response status**, then `DELETE` it.

   This is a create-and-delete diagnostic against a vendor API, not provisioning:
   nothing is left behind, no Terraform state is touched, and the workspace
   returns to exactly its prior shape. It also incidentally answers whether the
   free tier accepts `monitor_type = "expected_status_code"` at all — which the
   in-repo "precedent" cannot, being `count`-gated off.

   **Fork on the result, and take it seriously rather than rationalising past it:**
   - **Confirms** (probe reports up against the live 301) → proceed to Phase 1.
     Record the measurement in the PR body; it converts the plan's one
     documentation-derived claim into an observed one *before* any code lands.
   - **Refutes** (probe fails against a genuine 301) → **halt and re-scope.** The
     Better Stack design is dead, and the correct fallback is the scheduled-probe
     design this plan cut at CTO review — restored deliberately, with its cost
     re-accepted, rather than improvised. In that branch the Sentry retarget must
     **not** ship on its own: a 2xx assertion with no redirect-health alarm
     anywhere is a false all-clear, which is worse than today's honest red.

2. Re-pull live Sentry uptime state and incident `WEB-PLATFORM-11`, so the work
   acts on current data rather than this document's snapshot.
3. Re-measure live Better Stack monitor **and** heartbeat counts (the pooled-quota
   question), and record the post-PR headroom figure the narrative will cite.
4. Re-derive the free ADR ordinal across every `origin/*` ref.
5. Determine whether `fixtures/dns.tf.pr4a-baseline` is asserted against literally
   by any suite; decide edit-vs-exclude on that evidence, not on assumption.
6. Confirm `hcl_block()` in `www-apex-canonicalizer.test.sh` extracts correctly
   from `uptime-alerts.tf` — the first call site outside the `dns.tf` /
   `cf-pages.tf` / `seo-bulk-redirects.tf` trio.
7. Run the web-platform destroy-guard and fixture-based suites **before** any
   change, recording which carry resource-count assertions that adding one ungated
   resource could move (`tests/scripts/fixtures/tfplan-web-platform-real-baseline.json`
   already contains `betteruptime_monitor` rows).

### Phase 1 — Guard first

Add the Guard 1 mutation matrix to `www-apex-canonicalizer.test.sh` **before**
writing the Terraform block. Confirm M3 reds against the absent resource, then add
the block until the suite is green. The matrix comes from the design above; do not
re-derive it from whatever the block turns out to look like.

### Phase 2 — The Better Stack monitor

Write `betteruptime_monitor.soleur_www_redirect`:

| Attribute | Value | Why |
|---|---|---|
| `url` | `https://www.soleur.ai/` | the host under guard |
| `monitor_type` | `"expected_status_code"` | `status` means 2xx-only and cannot express 301 |
| `expected_status_codes` | `[301]` | exact, not a 3xx class — a 302/307/308 is a different canonicalization contract |
| `follow_redirects` | `false` | **the single token that separates this monitor from the broken one** |
| `check_frequency` | `180` | free-tier-allowed 3 minutes, matching both siblings |
| `confirmation_period` | `1200` | see below |
| `pronounceable_name` | `"soleur dot ai www redirect 301"` | the only operator-facing string; distinguishes it from `"soleur dot ai apex"` and from Sentry's www alarm |
| `verify_ssl` | `true` | parity with `soleur_apex` |
| `email` | `true`; `call`/`sms`/`push` false | free-tier email route |
| `count` | **absent** | a `count` gate would provision nothing — see Guard 1 M5 |
| `policy_id` | `var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null` | **follow the file's convention, do not omit it.** All three sibling monitors carry this exact ternary. Under the free tier it evaluates to `null` and changes nothing; omitting the attribute instead would silently exclude this monitor from escalation on a future `betterstack_paid_tier` flip, unlike every sibling, and would need a separate edit nobody would remember to make. `betteruptime_policy.uptime` is already in the `-target=` allow-list, so this introduces no adjacency gap |

Then append the `-target=` line to `apply-web-platform-infra.yml` **in the same
commit** — the resource is inert without it.

**`confirmation_period = 1200`, not 900.** The Pages-rebuild window during which
www transiently serves its own 200 was observed at ~15 minutes, and 900 s is
exactly that — zero margin, so a rebuild that runs even slightly long (propagation
jitter, a slower purge) opens a false incident on precisely the class this setting
exists to absorb. 1200 s buys ~5 minutes of margin over the single observed
instance. The cost is symmetric and must be stated rather than buried: the same
timer bounds real-regression detection, so worst-case MTTD is ~20 minutes rather
than ~15. That is still materially tighter than the `dns.tf` Camp B ruling's
assumed "one monitor interval" bound of 15 minutes was ever *actually* delivering
— which, as this plan establishes, was zero — and an order of magnitude better
than the ~2 h of the rejected scheduled-probe design.

Comment each load-bearing attribute inline with why it is load-bearing, and cite
the runbook and ADR-204.

### Phase 3 — Retarget the Sentry monitor

Swap `soleur_www.assertion_json` to `local.uptime_assertion_2xx` and rewrite the
comments to state the narrowed scope and point at the Better Stack monitor and
ADR-204.

### Phase 4 — The deploy-docs bracket

The `Pause soleur_www uptime monitor` / `Probe www→apex 301 then resume` pair
exists solely to suppress a deploy-window false page under the **old** assertion:
during a Pages rebuild www transiently serves its own 200, which failed
`equals 301`. Under a 2xx assertion that transient 200 now *passes*, so the
suppression need is gone — and the bracket carries a live hazard its own comment
documents: a failed resume leaves the monitor disabled, and that comment states
the next `apply-sentry-infra.yml` run is **not** a guaranteed self-heal.

**The YAML does not split the way "remove two steps" implies, and the edit must
be described precisely or it will leave debris.** There are two steps, but the
second one *interleaves* the parts being kept and removed:

- `Pause soleur_www uptime monitor` (id `pause_www_monitor`) — **delete entirely.**
- `Probe www→apex 301 then resume soleur_www monitor` — **keep the step, gut its
  second half.** Retain the curl retry loop and its `::warning::` reporting;
  delete the resume `PUT`, the `MONITOR_ID: ${{ steps.pause_www_monitor.outputs.monitor_id }}`
  env line (which references the deleted step), the Sentry credential env vars it
  no longer needs, and the `if: always()` guard whose only purpose was "never
  strand the monitor paused". Rename the step to drop "then resume".

Retain the curl because it is the only per-deploy immediate confirmation that the
redirect survived *this* deploy: it makes no API mutation, so it cannot strand
anything, and without it a deploy-caused regression waits out the Better Stack
confirmation window instead of surfacing in the run that caused it.

The new monitor's own deploy-window tolerance comes from
`confirmation_period = 1200`, not from pausing — no vendor state is mutated by CI,
which is the property that removes the stranding hazard entirely.

### Phase 5 — Docs, ADR, C4, and post-merge verification

Update the comment sites, write ADR-204, edit the `betterstack` C4 description,
file the residual-gap tracking issue. Run `plugins/soleur/test/c4-count-parity.test.sh`
explicitly to confirm C1–C7 are unmoved, plus the C4 syntax/render suites and
`actionlint` on the edited workflow.

Then, after merge and the two applies, by API rather than by assumption. **Polling
runs through the `Monitor` tool with an until-loop** — never a foreground `sleep`,
never a detached background poller (`hr-monitor-not-run-in-background-for-polling`)
— so the wait is bounded and its result lands in the session rather than being
dropped when it ends:

1. Poll Sentry until `soleur-ai-www-reachability` reports `uptimeStatus 1` with
   recent checks `success`, and confirm `WEB-PLATFORM-11` has resolved.
2. Poll Better Stack until `soleur_www_redirect` has been up **continuously past
   `confirmation_period` + one `check_frequency`** and its latest check records a
   `301`. Both conditions, for the reason AC24 gives: inside the confirmation
   window a fully-failing monitor still reads `up`, so the obvious poll would
   confirm the plan's central claim during the one interval in which it cannot
   fail.
3. If either poll ends unsatisfied, execute the containment in AC25 — pause the
   new monitor, revert the Sentry retarget, file `action-required`, re-open #7798
   — rather than leaving a second permanently-red monitor mailing.
4. Only after step 1 holds, re-capture the CUT8 baseline, so it records measured
   health instead of freezing the failure it was created to work around.

## Acceptance Criteria

Every pre-merge criterion below is deterministic over this diff. Two earlier ones
were not — they asserted properties of a whole multi-hundred-resource Terraform
plan, which unrelated ambient drift in either root could flip without a line of
this diff changing (`cq-ac-must-not-depend-on-concurrent-sessions`). Both are now
scoped to the addresses this PR touches.

### Pre-merge (PR)

**The monitor and its wiring**

1. `soleur_www_reachability.assertion_json` references `local.uptime_assertion_2xx`,
   and the string `op_status_code_check("equals", 301)` no longer appears in
   `apps/web-platform/infra/sentry/uptime-monitors.tf`.
2. `betteruptime_monitor.soleur_www_redirect` carries `follow_redirects = false`,
   `expected_status_codes = [301]`, a `pronounceable_name` distinct from every
   sibling's, `policy_id` as the free-tier-null ternary its siblings use, and **no**
   `count` — all asserted from the extracted resource block, never a whole-file grep.
3. Scoped to the touched address only:
   `jq '[.resource_changes[] | select(.address=="sentry_uptime_monitor.soleur_www_reachability")]'`
   over the sentry-root plan JSON shows exactly one element whose
   `.change.actions == ["update"]`. **Not** asserted through
   `destroy-guard-filter-sentry.jq`: that filter emits only
   `{resource_deletes, resource_creates, resource_forgets, nested_deletes}` and has
   no update counter, so it cannot verify this half.
4. Through `destroy-guard-filter-sentry.jq` (which *can* verify this half):
   `resource_deletes == 0`, `resource_creates == 0`, `resource_forgets == 0`,
   `nested_deletes == 0` on the sentry root — i.e. no `[ack-destroy]` is required.
5. Scoped to the touched address only: the web-platform plan JSON shows exactly one
   element for `betteruptime_monitor.soleur_www_redirect` with
   `.change.actions == ["create"]`, and **no** `resource_changes` entry whose
   address matches a `betterstack_paid_tier`-gated resource.
5b. `-target=betteruptime_monitor.soleur_www_redirect` is present in the
   bridge-less stage of `.github/workflows/apply-web-platform-infra.yml`, **and the
   address is absent from `OPERATOR_APPLIED_EXCLUSIONS`** in
   `plugins/soleur/test/terraform-target-parity.test.ts`. Both halves are required:
   the #5566 coverage guard is satisfied by either, and only one of them applies
   the monitor.
6. `plugins/soleur/test/terraform-target-parity.test.ts` passes.

**Guards and suites**

7. `apps/web-platform/infra/www-apex-canonicalizer.test.sh` passes with **both**
   `EXPECTED_CASES` arms bumped by the number of cases added, and each of M1–M6 and
   H1, applied one at a time, drives it red; H2 passes. Recorded as an explicit
   7-red / 1-pass tally in the PR body.
8. `bash apps/web-platform/infra/cutover-verify.sh --check-www-redirect` exits 0 and
   prints its PASS line, and the mode is listed in the script's `usage()`. *(A live
   probe: it can be flipped by a genuine production outage rather than by this diff.
   It is retained deliberately as a smoke check, and the deterministic coverage of
   the same logic lives in AC7's fixtures — this AC is informative, not the gate.)*
9. `plugins/soleur/test/c4-count-parity.test.sh` passes, invoked **by name** (its
   filename stem contains neither "sentry" nor "uptime", so a diff-scoped run does
   not reach it).
10. `plugins/soleur/test/c4-from-components.test.sh` and
    `plugins/soleur/test/c4-model-freshness.test.sh` pass, and
    `npx -y likec4@1.50.0 validate .` exits 0.
11. `actionlint` is clean on the edited `deploy-docs.yml` and
    `apply-web-platform-infra.yml`; each edited `run:` snippet parses under `bash -c`.

**The rename, and the documentation that must not lie**

12. `grep -n 'pause_www_monitor\|Pause soleur_www' .github/workflows/deploy-docs.yml`
    returns nothing, and no reference to the removed step ids or their outputs — the
    `MONITOR_ID` env line and the resume-only `if:` guard included — survives in the
    retained probe step.
13. The `SENTRY_MONITORS` array entry in `cutover-verify.sh` is byte-identical to the
    `name` on the renamed Sentry resource. (If they diverge, CUT8 reports `unknown`
    and `--capture-monitor-baseline` refuses to write — it fails safe, but this AC
    catches it before that.)
14. No file outside `**/archive/**` and this plan's own artifacts still asserts that
    `sentry_uptime_monitor.soleur_www` guards the 301 — verified by grepping the
    claim's **content anchor**, not the bare monitor name, which legitimately still
    appears. Covers `dns.tf` (both sites), `www-apex-canonicalizer.test.sh` (both),
    `uptime-alerts.tf`, `seo-aeo/SKILL.md`, `cutover-verify.sh`'s CUT8 message, and
    **ADR-194**'s two now-false passages — while its 526 passage is unchanged.
15. The `fixtures/dns.tf.pr4a-baseline` disposition decided in Phase 0 is visible in
    the diff: either edited, or explicitly listed as a deliberate carve-out with its
    reason. Silence is not an acceptable outcome for it.
16. `model.c4`'s `betterstack` element description names the new monitor. *(No test
    enforces this — it is asserted here precisely because the plan flagged it as
    untestable, which is otherwise an invitation to skip it.)*
17. The runbook `www-redirect-alarm.md` exists, and every corrected comment cites
    both it and the sibling monitor by Terraform address **and** `pronounceable_name`.
18. `ADR-204-*.md` exists at `status: accepted`, records that redirect-target-health
    is now **single-vendor**, and its ordinal is re-derived free across all `origin/*`
    refs at ship time.
19. The residual-gap tracking issue and the unmanaged-`app.soleur.ai/health`-monitor
    tracking issue both exist and are linked from ADR-204 and from the
    `uptime-alerts.tf` header comment.
20. Every `knowledge-base/` path cited in this plan resolves:
    `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'`
    prints nothing. Note that this check reports the two paths this PR *creates*
    (`www-redirect-alarm.md`, `ADR-204-*.md`) as broken until they exist, so it is
    an exit-gate assertion, not a plan-time one — it must be re-run after Phase 5,
    and a residual broken path at that point is a real defect.
21. PR body carries `Closes #7798` on its own line, and records the Phase 0
    falsification-probe measurement.

### Post-merge (pipeline-executed; no delegated steps)

Polling is driven by the `Monitor` tool with an until-loop, never a foreground
`sleep` and never a detached background poller (`hr-monitor-not-run-in-background-for-polling`).

22. Both applies succeed on the merge commit, and the web-platform apply's log shows
    the new `-target=` address.
23. Sentry: `soleur-ai-www-reachability` reports `uptimeStatus 1` with recent checks
    `success`, and `WEB-PLATFORM-11` is no longer `unresolved`.
24. Better Stack: `soleur_www_redirect` reports up **sustained past
    `confirmation_period` + one `check_frequency`** (≥ 1380 s), **and** its most
    recent check records a response status of `301`. Both halves are required — with
    a 1200 s confirmation window, a monitor whose every check is failing still reads
    `up` for the first 20 minutes, so a bare "is it up within the hour?" poll would
    pass during exactly the window in which it is silently broken.
25. **Containment, if 23 or 24 fails.** Do not leave the system in the failure state:
    set `paused = true` on `soleur_www_redirect` via Terraform to stop the email
    cadence, revert the Sentry retarget so www is no better disguised than it was,
    file an `action-required` issue, and re-open #7798 (which `Closes` will have
    auto-closed at merge). The bad branch must not end with a second permanently-red
    monitor mailing indefinitely — that is this issue's own defect, reproduced.
26. `cutover-monitor-baseline.txt` re-captured **after** 23 holds, recording the
    renamed monitor as `healthy`.

## Encryption Posture

Detection fires on the `\.tf$` glob. No persistent store is introduced, so the
`at_rest` rows name the only byte-stores this change touches rather than leaving
the field empty.

```yaml
at_rest:
  - store: Terraform state for the web-platform and sentry roots (existing R2
           backends, unchanged by this plan)
    mechanism: provider-managed server-side encryption on the R2 buckets, via the
               S3-compatible backends already configured for both roots
    evidence: the backend blocks in apps/web-platform/infra/ and
              apps/web-platform/infra/sentry/; no new backend is introduced
    defends_against: at-rest disclosure of stored monitor configuration if the
                     underlying media is compromised
    does_not_defend: anyone holding the R2 credentials in Doppler prd_terraform
                     reads plaintext state; SSE is not a defence against a
                     credential compromise
    disclosed_as: no disclosure change — the attributes this plan adds to state
                  are a public URL, a status-code list, three integers and three
                  booleans. No personal data and no secret value
    live_verification: both roots already read and write this state on every
                       merge-triggered apply; no new verification is added
  - store: Better Stack per-check history for the new monitor (vendor-side)
    mechanism: vendor-managed encryption at rest, under the existing Better Stack
               sub-processor relationship already covering soleur_apex and app
    evidence: no new vendor and no new data category; the monitor stores a status
              code and a timestamp per check
    defends_against: at-rest disclosure of probe history in the vendor's estate
    does_not_defend: anyone holding the Better Stack workspace credentials reads
                     it; unchanged from the two monitors already there
    disclosed_as: covered by the existing Better Stack sub-processor disclosure;
                  no new data category is introduced
    live_verification: the existing monitors already exercise this path
in_transit:
  - connection: Better Stack probe network -> https://www.soleur.ai/
    tls: TLS 1.2+ to the Cloudflare edge
    cert_verification: on — `verify_ssl = true`, matching soleur_apex
    does_not_defend: nothing about the CONTENT of the redirect; a validly-signed
                     but wrongly-configured edge still serves a wrong Location,
                     which is precisely the Residual Gap recorded above
    disclosed_as: outbound request to a public first-party URL; no disclosure
                  change
  - connection: Terraform runner -> Better Stack API (apply-time only)
    tls: HTTPS, provider default
    cert_verification: on — provider default, not overridden
    does_not_defend: the workspace API token is a Doppler secret; a token
                     compromise permits monitor tampering, which is exactly why
                     Guard 1 asserts the declared attributes at PR time rather
                     than trusting live vendor state
    disclosed_as: unchanged — the same credential already applies the two existing
                  monitors
exception: none — no plaintext store and no disabled certificate verification is
           introduced anywhere in this change.
```

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The `follow_redirects = false` + `expected_status_codes = [301]` combination is taken from vendor documentation, not measured against production** | This is the plan's one un-measured load-bearing claim, and it is called out rather than buried. Three independent supports: the pinned tag's own docs (both arguments quoted verbatim above); `expected_status_code` is already used in-repo; and **the repo's own `app` monitor corroborates the redirect semantics** — its comment reads *"follow_redirects = true: app.soleur.ai/ 307s to /login for an unauthenticated probe, so the monitor succeeds only if the full chain / -> 307 -> /login -> 200 returns 200"*, which is only a meaningful thing to write if `follow_redirects = false` would instead have surfaced the **307** to the check. That is precisely the semantics this plan depends on, reasoned from a sibling resource in the same file. AC18 still converts the claim to a measurement post-apply, and AC19 makes failure loud rather than silent |
| **The bad outcome of that risk is epistemic, not functional** — if Better Stack turns out vacuous, we hold a green monitor that proves nothing | Worth stating plainly, because it bounds the downside: the Sentry monitor is *already* 100% failing, and a permanently-red monitor cannot signal a new failure, so retargeting it to 2xx forfeits no working detection — it strictly adds reachability coverage that does not exist today. The genuine harm in the bad branch is the false all-clear, which is why AC18 is a measurement rather than an assumption and AC19 escalates on silence |
| **The new monitor false-fires during a docs-deploy window** (www transiently serves its own 200 during a Pages rebuild, ~15 min observed) | `confirmation_period = 1200` absorbs it without pausing anything, with ~5 min margin over the single observed 15-min window (900 would have had exactly zero). The symmetric cost — the same timer bounds real-regression MTTD at ~20 min — is stated in Phase 2 rather than buried. Deliberately *not* solved by a CI pause/resume bracket — that mechanism's stranding hazard is what Phase 4 removes |
| **Retargeting `soleur_www` to 2xx weakens it silently**, and a future reader sees green and infers the redirect is healthy | The precise trap already documented one resource away on `soleur_acme_probe`. The comment must state what is no longer guarded; ADR-204 records it; and the property is not merely dropped — it moves to a named monitor |
| **The Camp B acceptance in `dns.tf` was resting on a bound that never existed** | Corrected in the same PR rather than left to a follow-up, and the correction is why the design targets minutes rather than hours |
| **Better Stack's role expands beyond "vendor isolation"** | Amended deliberately and recorded in ADR-204, not done silently. The amendment is narrow: properties Sentry structurally cannot express |
| **Free-tier monitor cap** | 2 of 10 in use; this is the 3rd. Re-asserted live in Phase 0 before the block is written |
| **`Closes #7798` auto-closes at merge, before post-merge verification** | AC19 makes the failure loud: an `action-required` issue is filed if the monitors have not gone green within an hour, rather than the closure standing on an unverified apply |
| **ADR ordinal collision** | Provisional; re-derived across all 71 origin refs at ship time, with a sweep of the full artifact set if it moves |
| **The bad branch leaves a second permanently-red monitor mailing indefinitely**, with #7798 already auto-closed at merge | The single most important mitigation in this plan: the Phase 0 falsification probe runs **before any code is written**, so the branch is taken pre-merge in the ordinary case. If it is somehow reached post-merge anyway, AC25 is an explicit containment sequence — pause the monitor, revert the retarget, file `action-required`, re-open #7798 — rather than an implicit "someone will notice" |
| **A red #5566 coverage guard is "fixed" via `OPERATOR_APPLIED_EXCLUSIONS`** instead of the `-target=` list, turning CI green while the monitor is never applied | AC5b asserts both halves. This is the specific wrong-remedy the architecture review predicted, on the exact monitor the plan exists to make effective |
| **An accepted ADR keeps asserting the old guarantee** | ADR-194's two false passages are corrected in this PR. Found only because a reviewer grepped the corpus this plan's own consumer sweep had excluded — recorded so the next sweep does not repeat the exclusion |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Dispatch the apply to converge the monitor (the issue's primary remediation) | Live config already equals declared config. Measured, not assumed |
| Recreate / `-replace` the monitor (the issue's fallback) | Reproduces byte-identical config against an unsatisfiable assertion; also unreachable, since `assertion_json` is an in-place attribute in the pinned provider |
| `op_header_check` asserting the `Location` header in Sentry | Header ops read the **terminal** response, which is the apex's 200 and carries no `Location` |
| Assert `equals 200` on www in Sentry and call it redirect-health | Passes equally when www serves its own 200 — the exact regression under guard. Vacuous |
| **A scheduled GHA probe check-ing in to a new Sentry cron monitor** (this plan's own first design) | Rejected at CTO review on minimality and MTTD. It cost a workflow, a script, a cron monitor, a test battery and five C4 parity clauses, and delivered ~2h detection — which would have quietly widened the `dns.tf` Camp B acceptance from "one monitor interval" to two hours. Better Stack delivers ~18 min in one Terraform resource |
| Delete `sentry_uptime_monitor.soleur_www` outright | Better Stack carries no www monitor today, so deleting would leave www with **zero** reachability coverage from any vendor — losing DNS/TLS/5xx detection on a distinct CNAME surface, not just the already-lost redirect-health. Also costs an `[ack-destroy]`, a `SENTRY_MONITORS` edit and a baseline edit |
| Inngest-dispatch the probe for tighter cadence (ADR-033) | GHA `schedule:` jitter is minutes; the rejected design's MTTD was dominated by its 1-hour interval, not jitter. Moot once the design is vendor-side |
| Build the runtime target/origin assertion anyway | See Residual Gap — disproportionate to a threat the declared-config gate blocks on the only path Terraform owns. Tracked, with a named re-evaluation trigger |

## Test Scenarios

**Cut, deliberately.** An earlier draft carried a T1–T12 table that restated the
Guard Contract's mutation and harness rows in a second format, which — together
with AC7's PR-body tally — stated the same battery three times. The Guard Contract
matrix (M1–M6, H1–H2) is now the single enumeration; AC7 asserts its outcome. The
only scenarios that are *not* mutations of the guard are the live and post-apply
checks, and those are ACs 8, 22, 23 and 24 rather than a parallel table.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment:** Reviewed the plan against the live infra. Four findings, all
folded in rather than deferred:

1. **The Better Stack option was dismissed too fast.** `betteruptime_monitor`
   already exposes `follow_redirects` as a live toggle and `expected_status_code`
   as a monitor type used in-repo; only 2 of 10 free-tier monitors are in use. If
   viable it dominates the scheduled-probe design on MTTD *and* complexity.
   → **Verified against the pinned provider's own docs and adopted.** The plan was
   rewritten around it; the scheduled-probe design is now a recorded rejection.
2. **A load-bearing architectural acceptance depends on the broken assertion.**
   The claim is split across two files, and an earlier draft of this finding
   attributed both halves to `dns.tf`: the *acceptance* — "www SERVES the site
   (duplicate content for one monitor interval)" rather than 522-ing — is
   `dns.tf`'s Camp B block; the *justification* for it — that `soleur_www`
   "asserts `equals 301` and pages on EITHER outcome" — lives in
   `www-apex-canonicalizer.test.sh`. Both are stale, in different files, and both
   are in Files to Edit. The bound was never real, and an hourly replacement
   would have widened it silently. → Folded in as a load-bearing edit, and it is
   why the MTTD target is minutes rather than hours.
3. **Missed consumers.** `dns.tf` (two sites), `fixtures/dns.tf.pr4a-baseline`,
   and `plugins/soleur/skills/seo-aeo/SKILL.md` all cite the monitor's old
   semantics. → All added to Files to Edit, with the fixture's disposition
   deferred to a Phase 0 measurement rather than guessed.
4. **Deleting the whole deploy-docs bracket drops a per-deploy causal signal.**
   → Phase 4 now removes only the two Sentry-mutating steps and retains a
   warning-only curl.

Also confirmed: no existing scheduled workflow was a natural home for a probe;
Inngest dispatch would not have changed the MTTD math; and an ADR is warranted,
scoped to the vendor constraint and substrate choice.

### Plan Review panel (6 agents + a scoped strong-model consult)

Eng panel (DHH, Kieran, code-simplicity) plus architecture-strategist and
spec-flow-analyzer, with `cto` on a devex lens. Named-panel relevance was computed
independently of the Domain Review verdict above: the mechanical UI-surface scan
over Files to Create/Edit matched nothing, so `cpo`/`cmo`/`ux-design-lead` did not
activate; `cto` did, on code/infra Files-to-Edit.

All findings classified **Mechanical** (technical, one right answer) and applied.
No Taste or User-Challenge finding arose — nothing argued the operator's stated
scope should change — so `decision-challenges.md` is not written.

The ones that changed the plan rather than polishing it:

| Source | Finding | Applied as |
|---|---|---|
| architecture-strategist (P0) | The web-platform root is `-target=`-scoped, not full-root; the new monitor needs an allow-list line, and the plan asserted merge-convergence for a root it had verified only for *sentry* | `apply-web-platform-infra.yml` added to Files to Edit; Apply-path section rewritten; AC5b added for the `OPERATOR_APPLIED_EXCLUSIONS` escape hatch |
| architecture-strategist (P1) | **ADR-194 — an accepted ADR — makes two now-false claims** that this plan's own reasoning invalidates. Missed because the consumer grep excluded `knowledge-base/` | ADR-194 added to Files to Edit with the exact passages and the one that must *not* be touched |
| strong-model consult (P0-equivalent) | AC18 could not falsify the plan's central claim: inside `confirmation_period` a fully-failing monitor still reads `up` | AC24 now requires sustained-up past the window **and** a 301 on the check row |
| strong-model consult | The "`expected_status_code` is already used in-repo" support is not live — that block is paid-tier-gated and has never run | Corrected in Research Insights; the Phase 0 probe now also answers whether the free tier accepts the type |
| spec-flow (P0) | The paging path ends at a name in an inbox — no runbook, and `betteruptime_monitor` has no `description` field | Runbook added to Files to Create; naming table added |
| spec-flow (P0) | No containment if the vendor claim is wrong — the plan could fail into a *worse* state than it started, indefinitely, with #7798 already auto-closed | Phase 0 falsification probe (pre-merge, gating) + AC25 containment |
| spec-flow (P1) | `confirmation_period = 900` had exactly zero margin over the observed deploy window | Raised to 1200 with the symmetric MTTD cost stated |
| spec-flow (P1) | Retargeting while keeping the name reproduces the "semantically wrong, syntactically fine" trap | Sentry monitor renamed, with the full consumer list derived by grep |
| spec-flow (P2) | Six Files-to-Edit items had no AC | ACs 14–19 |
| cto devex (P1) | `pronounceable_name` omitted — the only operator-facing string | Added to Phase 2 and as Guard 1 M6 |
| cto devex (P1) | Free-tier quota math counted declarations, not live state, and might be pooled with heartbeats | Measured live (3 monitors, 9 heartbeats); pooled-quota theory refuted; unmanaged 4th monitor discovered |
| Kieran (P1) | AC3 asserted "one update" through a filter with no update counter | Split into AC3 (jq on the address) and AC4 (the filter's actual output) |
| Kieran (P1) | AC3/AC4 asserted whole-root plan totals — ambient drift could flip them | Both scoped to the touched addresses |
| Kieran (P1) | A Domain Review quote was attributed to `dns.tf` but lives in `www-apex-canonicalizer.test.sh` | Attribution split |
| Kieran (P2) | `policy_id` omitted, breaking the file's convention and future paid-tier escalation | Follows the sibling ternary |
| DHH (P1) | `www-redirect-check.sh` announced the duplication it was committing | Cut; replaced by a `--check-www-redirect` mode on `cutover-verify.sh` |
| DHH (P0) | Guard Contract, Test Scenarios and the PR-body tally stated the same battery three times | Test Scenarios table cut; the Guard Contract matrix is the single enumeration |
| DHH / code-simplicity | A second guard duplicated the existing #5566 coverage check | Guard 2 cut, replaced by AC5b |

code-simplicity recommended **no** mechanism be cut (`YAGNI violations: none`),
finding every remaining one traceable to P1/P2/P3 or to a named hard rule — and
independently flagged the same `check_redirect()` duplication DHH did.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Create` and
`## Files to Edit` matches no UI-surface path — the change set is Terraform, a
shell check, one workflow edit, an ADR and documentation comments. No user-facing
page, component or flow is created or modified, so Product is `NONE` by both the
semantic sweep and the mechanical override.

**Brainstorm-recommended specialists:** none — this plan was entered directly from
`/soleur:one-shot` with no preceding brainstorm.

**Skipped specialists:** none.

## GDPR / Compliance Gate

Skipped, and the skip is deliberate rather than incidental. The canonical
regulated-surface regex matches nothing here: no schema, no migration, no auth
flow, no API route, no `.sql`. The four expansion triggers were each checked and
none fires — (a) no LLM or external-API processing of session-derived data; (b)
the brand-survival threshold is `aggregate pattern`, not `single-user incident`;
(c) no new cron reads `knowledge-base/project/learnings/` or `specs/`; (d) no new
artifact-distribution surface. The only data the change causes to exist is a
status code and a timestamp per check, at a sub-processor already disclosed.
