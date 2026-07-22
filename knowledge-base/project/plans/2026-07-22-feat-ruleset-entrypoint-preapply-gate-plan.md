---
title: "Pre-apply entrypoint-enumeration gate for whole-list Terraform resources + retrospective drift audit"
issue: 6767
branch: feat-one-shot-6767-ruleset-entrypoint-preapply-gate
date: 2026-07-22
type: feature
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
plan_review: 6-agent panel applied (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cto) — 2026-07-22
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan provisions NO new infrastructure. It adds a CI
     gate + a read-only audit around the EXISTING apps/web-platform/infra/ terraform
     apply path. Mentions of dashboard/manual action describe the failure mode being
     ELIMINATED (routing through CI automation), never a prescribed manual step. No
     server, secret, DNS record, vendor account, or cron is created. See the
     ## Infrastructure (IaC) section below. -->

# 🛡️ Pre-apply entrypoint-enumeration gate + retrospective drift audit (#6767)

## Overview

A `kind = "zone"` Cloudflare ruleset **owns its phase entrypoint as a whole-list
replacement**. `terraform plan` reports `1 to add, 0 to destroy` for such a
resource when it is absent from *state* — and that line is *correct* — but `plan`
never calls the Cloudflare API, so it cannot see that the live entrypoint is
already populated with dashboard-created rules. A clean plan is therefore fully
compatible with a **destructive first apply**: the create replaces the live rule
list with the config's, silently deleting rules a human made in the CF dashboard.
This is the outage-class gap #6746 hit on `app.soleur.ai` (the "Flexible SSL for
web platform" rule).

The **destroy-guard cannot be this gate.** `tests/scripts/lib/destroy-guard-filter-web-platform.jq`
computes `cf_ruleset_rules_count(.change.before) - cf_ruleset_rules_count(.change.after)`;
on a *create*, `change.before` is `null` → `0 − 2 = −2` → filtered out by
`select(. > 0)`, and `resource_deletes` is `0` too, so no `[ack-destroy]` fires
(confirmed by three reviewers against the live filter). **A plan-derived guard
inherits `plan`'s blind spot.** The gate must assert on plan *shape* (a whole-list
resource planned as a pure `create` from absent state) and then **query the live
Cloudflare API** to decide.

This plan delivers the two pieces the issue's own corrective comment scoped it
to (the third — ADOPTION — is already shipped; see Research Reconciliation):

1. **PRE-APPLY GATE (prospective, the real fix).** A fail-closed, API-querying
   gate wired as a **separate step** into `apply-web-platform-infra.yml` after
   the "Terraform plan" step and before the main "Terraform apply" step. For a
   resource planned as a pure `create` from absent state (`actions == ["create"]
   && before == null && importing == null`) whose type is a **natural-key
   server-side singleton** (Inclusion Principle below — today exactly
   `cloudflare_ruleset`), it enumerates that phase's live entrypoint via the
   Cloudflare API and **fails the apply** if the entrypoint is non-empty. It is
   **default-deny**: it PASSES only on a proven-empty entrypoint and fail-closes
   on every ambiguity.

2. **RETROSPECTIVE DRIFT AUDIT (read-only).** An `--audit` mode of the same
   script that enumerates every declared ruleset's live entrypoint and diffs it
   against `terraform show -json` of current state, surfacing anything
   live-but-absent (historical loss or current drift). Run read-only in CI via a
   dedicated guarded dispatch; findings posted once to #6767 as the
   system-of-record (no dashboard eyeball — `hr-no-dashboard-eyeball-pull-data-yourself`).

Same shape as `2026-07-20-a-plan-can-prescribe-a-resource-its-credential-cannot-create.md`
and `2026-07-20-terraform-plan-cannot-see-what-a-whole-list-resource-destroys.md`,
generalised from a per-plan `/work`-time probe into a standing CI gate.

### Inclusion Principle (what the gate guards — architecture-strategist Finding B)

The #6746 hazard is **narrower** than "whole-list-owning". It is precisely:

> *a `create` silently **adopts** and **whole-replaces** a server-side singleton
> addressed by a **natural / composite key** that can pre-exist outside Terraform
> (e.g. created directly in the CF dashboard).*

Adjudicating every whole-list-shaped Cloudflare class in this root against that
principle (recorded in ADR-133 + the gate script header, cross-referenced to the
destroy-guard class table `destroy-guard-filter-web-platform.jq:5-16` so the two
cannot drift):

| Class | Key | Silent-adopt on create? | Verdict |
|---|---|---|---|
| `cloudflare_ruleset` zone/account phase entrypoint | `(zone\|account, phase)` — natural | **Yes** — whole-list PUT over a pre-existing entrypoint | **IN** (the one true member) |
| `cloudflare_zero_trust_tunnel_cloudflared_config` | `tunnel_id` (TF-created same apply) | No — attaches to a *fresh* tunnel | OUT (caveat: IN the day a tunnel is imported/adopted) |
| `cloudflare_zone_settings_override` / `_notification_policy` / `_zero_trust_access_policy` / `cloudflare_list` | TF-generated ID | No — a same-named dashboard object is a *different* object | OUT (recorded so "extensible" is not mistaken for coverage — spec-flow B3) |
| DNS record sets | name+type | No — errors/duplicates, never silent whole-replace | OUT |

The gate therefore covers exactly `cloudflare_ruleset` (zone + account phase
entrypoints). A parity test (Phase 4) makes this a *tested* coupling, not
prose someone must remember to update for a new class (CTO F1) — the exact
failure this issue exists to kill, one level up.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body / ARGUMENTS) | Reality (verified on this branch) | Plan response |
|---|---|---|
| (1) ADOPTION "both halves required" — add the Flexible SSL rule + `import` so state matches live | **Already shipped and merged via #6746** (`e567792fa`). `seo-config-rules.tf` carries the `import` block + the adopted rule verbatim (`ssl = "flexible"`, `ref = "dcb85b…"`). `test/seo-config-rules.test.ts` pins exactly-two-rules + the adopted rule's expression/param/ref + the singular `zone/` import ID. Plan verified `1 to import, 0 to add, 1 to change, 0 to destroy`. | **Do NOT re-implement.** Adoption is complete. This plan keeps the two-rule pin intact; it touches `seo-config-rules.tf` only for a one-line comment update. |
| "Every other `kind = "zone"` ruleset has the same exposure and was never enumerated" | **Overstated (corrected by issue author).** `terraform state list` shows all siblings already in state. In-state resources refresh their entrypoint on every `plan`, so a dashboard-added rule shows as ordinary drift. Exposure is **retrospective**, not prospective. | Scope split: **gate = prospective** (future whole-list resources), **audit = retrospective** (confirm nothing already lost + no current drift). |
| "`bulk_redirects` … same zone exposure" | `bulk_redirects` is `kind = "root"` with `account_id` (seo-bulk-redirects.tf) — **account-level**. Entrypoint endpoint is `accounts/$ACCT/rulesets/phases/<phase>/entrypoint`. | Gate handles both `zone_id` and `account_id` (branch on kind). |
| ADR-130 defines the entrypoint probe as a manual `/work` step; "Making it a gate is open in #6767" (ADR-130:156) | Confirmed. Prose, not enforced. | ADR-133 (new) makes it a standing automated gate; ADR-130 gets a "see ADR-133" cross-note. |
| Predecessor is #6746 | `git log` confirms sole commit `e567792fa (#6746)`, MERGED, does not close #6767 (still OPEN). | Premise holds; genuine follow-up. |

**Premise Validation note:** Checked #6746 (MERGED, does not close #6767), #6767
(OPEN), ADR-130 (defines the probe set; explicitly defers the gate to #6767),
`seo-config-rules.tf` + `test/seo-config-rules.test.ts` (adoption + two-rule pin
already shipped). The one stale premise — "re-implement adoption" — is corrected:
adoption is done; this plan builds only the gate + audit + ADR/C4. No proposed
mechanism sits in an ADR's rejected-alternatives table.

## Problem Statement

`apply-web-platform-infra.yml` runs `terraform plan -out=tfplan` (a ~70-address
`-target=` list including all zone/account rulesets) → `terraform show -json
tfplan | jq -f destroy-guard-filter-web-platform.jq` → numeric validation →
`host_creates` tripwire → `destroy_count` + `[ack-destroy]` → `terraform apply
tfplan`. Nothing enumerates a live entrypoint. The next **new** whole-list
resource's first apply will clobber whatever the dashboard put there —
invisibly to `plan`, invisibly to the destroy-guard, and in a way
`seo-config-rules.tf`'s "ROLL FORWARD, NEVER REVERT" note shows the
`[ack-destroy]` prompt makes look survivable.

## User-Brand Impact

- **If this lands broken (fail-OPEN gate), the user experiences:** a future
  TLS/config outage on `app.soleur.ai` (the main product web host) when the next
  unguarded whole-list `create` silently deletes a live dashboard-created rule —
  the #6746 failure recurring *through* the control built to stop it. A
  fail-CLOSED false positive instead blocks a legitimate infra apply (dev
  friction, no user harm) — the safe direction this design biases toward.
- **If this leaks, the user's data is exposed via:** N/A — the gate processes no
  personal data. It issues read-only `GET`s to the Cloudflare rulesets API using
  the existing `CF_API_TOKEN_RULESETS`; it adds no new secret, no persisted
  state, no user-data surface. The threat guarded is **availability**, not
  exposure.
- **Brand-survival threshold:** `single-user incident`

Artifact/vector pair for `user-impact-reviewer`: *(artifact)* a fail-open gate →
`app.soleur.ai` serving TLS errors after a whole-list clobber; *(vector)* the
gate exiting 0 on a create-shaped whole-list resource whose live entrypoint is
non-empty — via any of the fail-open seams the panel surfaced (malformed plan
JSON read as "no matches"; a 404 from a mis-constructed URL read as "empty"; an
unenumerated HTTP code falling through to PASS; an empty token; an early
loop-exit masking a later clobber). CPO sign-off required at plan time;
`user-impact-reviewer` runs at review time against the gate's control flow.

## Implementation Phases

### Phase 0 — Preconditions (`/work`, verify before writing)

- **P0.1** Against a real `terraform show -json` capture (TF 1.10.5, cloudflare
  provider 4.52.7), confirm the three discriminated shapes — do NOT assume:
  - pure **create from absent state**: `change.actions == ["create"]` (EXACT —
    NOT `index("create")`, which also matches `-replace` `["delete","create"]`
    and CBD `["create","delete"]`; the house idiom in this workflow uses
    `index("create")` and is **wrong here** — spec-flow D1 / Kieran M1),
    `change.before == null`, `change.importing == null`.
  - confirm a first create of a resource with `lifecycle { create_before_destroy
    = true }` still renders `["create"]` (CBD only reorders on *replace*), so the
    exact-match filter has no false negative.
  - the **import/adopt** shape (shipped `seo_config_settings`): confirm the
    import signal is `change.importing` (NOT `action_reason`), and that once
    in state it plans as `["no-op"]`/`["update"]` — exempt in **both** phases.
- **P0.2** Confirm the live-entrypoint contract for **both** the zone
  (`zones/$ZONE/…`) AND account (`accounts/$ACCT/…`) paths (ADR-130's probe set
  is zone-only — spec-flow #12): 200 = populated, **404 = empty phase (PASS)**,
  403 = permission failure. Confirm `CF_API_TOKEN_RULESETS` can read
  account-scoped rulesets (it carries `Account Rulesets:Edit` per ADR-130/#5092).
  Confirm the CI read path: the apply job runs under `doppler run -p soleur -c
  prd_terraform`; the gate step sets `env: DOPPLER_TOKEN` and reads the raw token
  via `doppler secrets get CF_API_TOKEN_RULESETS … --plain`.
- **P0.3** Re-read the destroy-guard header's cap-coupling convention (dedicated
  filter + dedicated `test-*` + CODEOWNERS + parity test) and follow it.

### Phase 1 — Gate script (`tests/scripts/lib/preapply-entrypoint-gate.sh`)

Single script, two modes, `set -euo pipefail` throughout. **Default-deny**: the
spec enumerates the only two PASS branches and routes *everything else* to one
fail-closed sink (spec-flow A1 / Kieran L2).

**`--gate <plan.json>` mode** (runs in the apply job):

1. **Token guard.** Read the token from ONE pinned env var (`PREAPPLY_CF_TOKEN`).
   `[[ -n "$PREAPPLY_CF_TOKEN" ]]` else **fail-closed** with a DISTINCT message
   ("gate environment: CF token empty/unreadable from Doppler" — NOT a target
   finding). (spec-flow A2 / Kieran H1)
2. **Input validation.** `jq -e '.resource_changes | type == "array"'` on
   `plan.json`; a parse error / non-array / empty file → **fail-closed** ("plan
   JSON unparseable — refusing to read as 'no matches'"). An empty/truncated
   plan must NEVER read as "zero matched rows → PASS" (spec-flow B1/A3).
3. **Plan-shape pre-filter (iterate ALL matches, aggregate a `fail` sentinel —
   spec-flow B4).** Select `resource_changes[]` where `.type == "cloudflare_ruleset"`
   AND `.change.actions == ["create"]` (exact) AND `.change.before == null` AND
   `.change.importing == null`. **Iterate the full `resource_changes[]` array,
   never the `-target` list** (architecture Finding C — a transitively pulled-in
   create must still be caught). Emit a `::notice::` with the matched-row count +
   probe count (makes "zero API calls on a normal merge" observable — spec-flow
   L1 / CTO F3). Zero matches → `::notice::` + exit 0 (fast, no API calls).
4. **Control probe (once, only if ≥1 matched row).** GET a KNOWN-populated phase
   on the zone (`http_request_dynamic_redirect` — the `seo_page_redirects`
   entrypoint) with `curl --max-time <N>`. Expect HTTP **200**. Not 200 →
   **fail-closed** ("gate environment invalid — token scope / URL scheme /
   network; NOT a target finding"). This single control probe (ADR-130's
   control-probe pattern applied to the gate itself) makes a subsequent target
   **404 provably mean "empty phase"**, not "mis-constructed URL / bad token" —
   closing the fail-open 404 seam (code-simplicity CRITICAL) and disambiguating
   the byte-identical-403 problem (Kieran H1).
5. For each matched row: read `.change.after.kind` / `.phase` / `.zone_id` /
   `.account_id`.
   - **kind allowlist:** `zone` → `zones/$ZONE/rulesets/phases/$PHASE/entrypoint`;
     `root` → `accounts/$ACCT/rulesets/phases/$PHASE/entrypoint`; **any other
     kind → fail-closed** ("unclassified ruleset kind '$k' — enumerate by hand")
     (spec-flow #5).
   - if the URL-building field (`zone_id`/`account_id`/`phase`) is
     null/empty/unknown-after-apply → **fail-closed** (spec-flow B2).
   - `curl --max-time <N> -sS -w '%{http_code}'` (bounded so a Cloudflare hang
     converts to fail-closed rather than holding the SOLE apply concurrency
     serializer for the whole job budget — CTO F4).
   - **Default-deny HTTP handling:**
     - exactly `200` → parse `.result.rules` (jq parse failure → fail-closed); if
       `length > 0` → set `fail`, emit `::error::` with a **copy-pasteable
       remedy** (the singular v4 `zone/<zone_id>/<ruleset_id>` import block filled
       from `.result.id`, plus the live rules to reproduce verbatim incl. `ref`
       — the data is already in hand; do NOT merely point at ADR-130 — CTO F3) ;
       if `length == 0` → pass this row.
     - exactly `404` → pass this row.
     - **everything else** (000/400/401/403/429/5xx, non-numeric, curl non-zero)
       → **fail-closed** via the single catch-all default.
6. After the loop: `fail` set → exit non-zero; else exit 0.
7. **Testability seam:** the HTTP fetch is injected via one indirection
   (`PREAPPLY_ENTRYPOINT_FETCH="${PREAPPLY_ENTRYPOINT_FETCH:-_default_curl}"`) so
   the test stubs it and asserts control flow with **no live API in the assertion
   path**.

**`--audit` mode** — Phase 3.

### Phase 2 — Wire the gate into the apply workflow

Kieran H3: the destroy-guard is NOT a splice-able step — `terraform show -json |
jq`, numeric validation, the `host_creates` HALT, and the `destroy_count` gate
all live inside the **single** "Terraform plan" run block. So:

- Inside the existing "Terraform plan" step, add `terraform show -json tfplan >
  tfplan.json` **once** and have the destroy-guard `jq` read that file (not a
  second `terraform show` — Kieran L4 / code-simplicity).
- Add a **new separate step** "Pre-apply entrypoint gate" AFTER the "Terraform
  plan" step and BEFORE the **main** "Terraform apply" step (there are two apply
  steps — main ~L542 and the SSH-provisioned one ~L700; anchor before the main
  one — Kieran H2). The step:
  - `working-directory: ${{ env.INFRA_DIR }}` (the plan step writes `tfplan.json`
    into `apps/web-platform/infra/`; the script gets a bare relative path — Kieran H3);
  - sets `env: DOPPLER_TOKEN: ${{ secrets.… }}` (every Doppler-reading step in
    this workflow does — Kieran H1) and `set -euo pipefail`;
  - reads `CF_API_TOKEN_RULESETS` → exports it as `PREAPPLY_CF_TOKEN` → runs
    `bash "$GITHUB_WORKSPACE/tests/scripts/lib/preapply-entrypoint-gate.sh"
    --gate tfplan.json`.
  - Positioned OUTSIDE any `[ack-destroy]` bypass (mirrors the `host_creates`
    tripwire — architecture confirmed this is structurally correct; a whole-list
    clobber is never something to type past).
- **Sibling-workflow / dispatch-job boundary (architecture Finding A, CTO F6):**
  the 6 `workflow_dispatch` jobs and the sibling `apply-deploy-pipeline-fix.yml`
  target only `hcloud_*`/`doppler_*`/`random_*` resources and — because `-target`
  transitivity flows toward *dependencies*, not dependents — cannot pull in a
  ruleset create. Record this as the exemption rationale AND back it with the
  parity test in Phase 4 (so the job-vs-workflow boundary is a *tested*
  invariant, not prose).

### Phase 3 — Retrospective drift audit (`--audit` + guarded read-only dispatch)

- **`--audit` mode:**
  - **Static (deterministic, runnable at `/work`):** enumerate every
    `cloudflare_ruleset` in `apps/web-platform/infra/*.tf`, classify zone vs
    account, note `-target=` coverage + in-state/import status. Committable now.
  - **Live (CI, read-only):** control-probe first; then for each ruleset GET its
    entrypoint and diff live rules against **`terraform show -json` of current
    state** (structured — NOT a fragile HCL grep — spec-flow C3). Report
    live-but-absent-in-state (drift / historical loss) and state-but-absent-live.
- **Recording (single system-of-record — code-simplicity, spec-flow C1/C2):**
  add a dedicated `entrypoint-audit` value to the `apply_target` dispatch `choice`
  enum with a mutually-exclusive `if:` guard (so the apply job's `push ||
  manual-rerun` guard excludes it — CTO F5 / Kieran L3 / spec-flow C4), its OWN
  `concurrency:` group (not `terraform-apply-web-platform-host`, so an audit
  never serializes behind / delays a real apply — Kieran L3), `permissions:
  contents: read, issues: write` with **GitHub App token** auth
  (`hr-github-app-auth-not-pat` — the default job perms are `contents: read`
  only, so `gh issue comment` silently fails without this — spec-flow C1), and
  **no `terraform apply`** in its body (asserted by a test — CTO F5). It writes
  the findings once to **#6767 as the system-of-record comment**; the committed
  runbook `## Results` section **links to that comment** rather than duplicating
  it (spec-flow C2).
- **Ship runs it in-session, blocks PR-ready (CTO F2 / `wg-block-pr-ready-on-undeferred-operator-steps`
  / never-defer-operator-actions):** ship executes `gh workflow run
  apply-web-platform-infra.yml -f apply_target=entrypoint-audit`, waits for the
  run, and confirms findings posted to #6767 **before** marking the PR ready. It
  is NOT a post-merge checkbox a human owns.
- The runbook `knowledge-base/engineering/operations/runbooks/cloudflare-whole-list-entrypoint-audit.md`
  ships with METHOD + the static parity table + the correction-comment context
  (siblings in-state; exposure retrospective); `## Results` links to the CI-run
  comment.

### Phase 4 — Tests + parity + CODEOWNERS (cap-coupling convention)

- **`tests/scripts/test-preapply-entrypoint-gate.sh`** — control flow vs
  synthesized fixtures (stubbed fetch, no live API):
  - create-shape (zone) + control-probe 200 + target 200/2-rules → **exit ≠ 0**,
    `::error::` carries the singular-form import block + live rules.
  - create-shape + target 404 (empty phase) → **exit 0**.
  - create-shape + control-probe non-200 → **exit ≠ 0** (gate-environment-invalid).
  - create-shape + target 403 / 000 / 429 / 5xx / non-numeric → **exit ≠ 0**
    (default-deny fail-closed, one case per code family).
  - empty token → **exit ≠ 0** before any curl.
  - malformed / empty `tfplan.json` → **exit ≠ 0** (never "no matches → PASS").
  - account-level (`kind=root`, `account_id`) create-shape + non-empty → **exit ≠ 0**
    via the account endpoint.
  - unclassified `kind` on a create → **exit ≠ 0**.
  - **replace** (`["delete","create"]`, `before != null`) → **exit 0, does NOT
    fire** (locks spec-flow D1 against regression).
  - **import** (first-apply, `importing` present) AND **steady-state**
    (`["no-op"]`/`["update"]`) → **exit 0, zero API calls** (adopted resource
    exempt in both phases — Kieran M2).
  - **untargeted create** (a whole-list create present in the plan but on no
    `-target` line) → **exit ≠ 0** (architecture Finding C invariant).
  - multi-row: one PASS + one FAIL row → **exit ≠ 0** (loop aggregation — spec-flow B4).
  - `--audit` static mode → parity table emitted (control-flow pinned so an
    audit-side edit can't regress `--gate` — CTO F7).
  - **wiring assertions:** grep the invocation tokens **independently /
    whitespace-normalized** (the call spans a backslash continuation — a
    single-line `grep -F` fails — Kieran H2); assert the gate step sits before
    the **main** apply step (pinned by name) and carries no `[ack-destroy]` gate.
- **Parity test** (`tests/scripts/test-preapply-entrypoint-gate-parity.sh` or a
  section of the above) — the forcing function that stops the class-registry
  going stale (CTO F1/F6, architecture A/B):
  - FAIL if any dispatch job's `-target` set in `apply-web-platform-infra.yml`
    (or any other `apply-*.yml` root) gains a `cloudflare_ruleset` address while
    that job has no gate step.
  - FAIL if a `cloudflare_*` resource *type* appears in `apps/web-platform/infra/*.tf`
    that is neither in the gate's covered set NOR in the ADR-133 adjudicated-OUT
    list (forces conscious classification of any new whole-list-shaped class,
    cross-referenced to the destroy-guard class table).
- **Fixtures** (`tests/scripts/fixtures/`, synthesized —
  `cq-test-fixtures-synthesized-only`): `tfplan-ruleset-create.json` (zone +
  account rows, `["create"]`, `before==null`), `tfplan-ruleset-create-untargeted.json`,
  `tfplan-ruleset-import.json`, `tfplan-ruleset-steady-state.json`,
  `tfplan-ruleset-replace.json`.
- **CODEOWNERS** rows for the new gate script + tests (mirror the destroy-guard rows).
- Wire the test into the harness that runs the other `tests/scripts/test-*.sh`
  (confirm: `scripts/test-all.sh` — per the CTO's grounding — and/or
  infra-validation.yml) so it is not an orphan suite.

### Phase 5 — ADR-133 + ADR-130 cross-note + C4 + docs

- **ADR-133** (provisional; re-verify next-free ordinal at ship — highest live is
  ADR-132). Keep it **thin** (DHH): state the Decision (standing fail-closed
  gate), the **Inclusion Principle** + the class adjudication table above, the
  `["create"] && before==null && importing==null` discriminator, the
  control-probe + the 404 residual-seam it closes, the iterate-all-`resource_changes`
  invariant, and the sibling/dispatch-job boundary. **Reference this plan's
  Alternative Approaches table rather than re-typing it.** Cross-note ADR-130's
  entrypoint Consequence with "see ADR-133".
- **C4 (completeness mandate — read all three `.c4`, do not grep the feature
  noun):** external human actor — none new; external system — Cloudflare rulesets
  API, already modeled as `cloudflare` (model.c4:234); container/store — none
  new; access relationship — the apply CI workflow now issues read-only `GET`s to
  the Cloudflare rulesets API. Confirm whether a CI→cloudflare (read) edge is
  modeled; if absent add the edge + `view include` line and run
  `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`. Cite the
  enumeration; an unsupported "no C4 impact" is a reject condition.
- **Docs:** update the entrypoint-enumeration Sharp Edge in
  `plugins/soleur/skills/plan/SKILL.md` (prose → standing gate; the manual
  ADR-130 probe remains the `/work`-time pre-*write* check); update
  `seo-config-rules.tf`'s "#6767 is a drift-audit, not a pre-apply gate" comment
  to point at the shipped gate.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Extend `destroy-guard-filter-web-platform.jq` with a create-clobber counter | On a create, `change.before` is null → the rule-count delta is negative → filtered; `resource_deletes` is 0. A plan-derived guard cannot see what a create destroys. The gate MUST query the live API. |
| Plan-shape assertion only | False-positives on a genuinely new empty phase. The API enumeration distinguishes "create into empty" (safe) from "create over live rules" (clobber). Plan-shape is only the cheap pre-filter. |
| `index("create")` filter (the house idiom) | Matches `-replace` `["delete","create"]` and CBD — false-positive blocking a legitimate replace of an in-state ruleset. The hazard is create-from-**absent-state** only → `== ["create"] && before == null`. |
| Enumerate the fail HTTP codes (403, curl-fail, …) | Leaves 5xx/429/401/400 unspecified → an implementer's missing `else` becomes a fail-open hole. Inverted to **default-deny**: PASS only on proven-empty; everything else fail-closed. |
| "Extensible whole-list class registry" (speculative) | Exactly one class exists (`cloudflare_ruleset`). A registry for a set of size 1 is speculative generality. Replaced with a **stated inclusion principle + a parity test** (a forcing function), which is stronger than both a speculative registry and a bare hardcode. |
| Recurring cron drift-audit | The in-state siblings' drift already shows via `plan` + the infra-drift detector. The retrospective audit is a one-shot confirmation via guarded dispatch, not a new cron. (DHH + code-simplicity argued the whole audit is redundant — recorded as a User-Challenge in `decision-challenges.md`; kept because it is an explicit #6767 deliverable.) |
| Keep it as prose in plan/SKILL.md + ADR-130 | A probe someone must remember to write is precisely what failed. |

## Observability

```yaml
liveness_signal:
  what:            "GitHub Actions job status of apply-web-platform-infra.yml (the gate is a step within the apply job); a red run == the gate blocked an apply"
  cadence:         "per-apply (every merge touching apps/web-platform/infra/**); the audit is on-demand guarded workflow_dispatch"
  alert_target:    "GitHub Actions run status + the apply-run failure surface (already operator-visible)"
  configured_in:   ".github/workflows/apply-web-platform-infra.yml + tests/scripts/lib/preapply-entrypoint-gate.sh"

error_reporting:
  destination:     "GitHub Actions ::error:: / ::notice:: annotations on the apply run (no Sentry DSN in this CI step); the failed run is the fail-loud surface"
  fail_loud:       "::error:: naming resource address, phase, zone/account, live rule count, and a copy-pasteable singular-form import remedy; distinct ::error:: strings for gate-environment-invalid (control probe), empty-token, unparseable-plan-JSON, unclassified-kind, and the default-deny catch-all"

failure_modes:
  - mode:          "whole-list resource planned as create-from-absent while its live entrypoint is non-empty (the clobber this prevents)"
    detection:     "control probe 200 + target GET 200 with .result.rules length > 0 -> non-zero exit -> apply job fails"
    alert_route:   "operator sees the red apply run + the ::error:: adoption remedy"
  - mode:          "gate environment invalid (token unreadable/unscoped, wrong URL scheme, network)"
    detection:     "control probe against a known-populated phase returns non-200 -> fail-closed, distinct message"
    alert_route:   "red apply run"
  - mode:          "CF API hang (slow/unresponsive)"
    detection:     "curl --max-time bound converts a hang to fail-closed in seconds -- protects the sole apply concurrency serializer"
    alert_route:   "red apply run"
  - mode:          "empty/unreadable CF token from Doppler"
    detection:     "[[ -n TOK ]] guard before any curl -> fail-closed distinct message"
    alert_route:   "red apply run"
  - mode:          "empty/malformed tfplan.json"
    detection:     "jq -e '.resource_changes | type == array' -> fail-closed (never 'no matches -> PASS')"
    alert_route:   "red apply run"
  - mode:          "unhandled HTTP code (000/401/429/5xx/non-numeric)"
    detection:     "default-deny catch-all -> fail-closed"
    alert_route:   "red apply run"

logs:
  where:           "GitHub Actions run logs + GITHUB_STEP_SUMMARY (audit table); audit findings system-of-record = #6767 comment"
  retention:       "GitHub Actions default (90 days); the #6767 comment is durable"

discoverability_test:
  command:         "bash tests/scripts/test-preapply-entrypoint-gate.sh"
  expected_output: "all assertions pass (gate blocks create-over-nonempty + every fail-closed fixture; exits 0 with zero API calls on import/steady-state/normal-merge) -- synthesized fixtures + stubbed fetch, no ssh, no live API"
```

## Infrastructure (IaC)

Adds a CI **gate around** the existing `apps/web-platform/infra/` apply path;
provisions **no new infrastructure**. (`<!-- iac-routing-ack -->` at the top: Phase
2.8 reviewed — no server/secret/DNS/vendor/cron created.)

### Terraform changes
None (a one-line comment update in `seo-config-rules.tf` only).

### Apply path
Unchanged apply mechanism. A fail-closed pre-apply step is inserted after the
"Terraform plan" step and before the main "Terraform apply" step. A false
positive fails the apply job before `apply` runs — zero prod mutation. A CF-API
hang is bounded by `curl --max-time` so the sole apply concurrency serializer is
not held.

### Distinctness / drift safeguards
Read-only `GET` using the existing `CF_API_TOKEN_RULESETS` (Doppler
`prd_terraform`); no new `TF_VAR_*` no-default root variable; no state write. The
audit job uses a separate concurrency group + `issues: write` GitHub App token.

### Vendor-tier reality check
Cloudflare rulesets `GET` endpoints carry no paid-tier gate; a 404 on an
entrypoint is a PASS (phase exists, no ruleset) — validated by the control probe.

## Architecture Decision (ADR/C4)

### ADR
Create **ADR-133** (provisional; re-verify next-free at ship — highest live is
ADR-132), thin, per Phase 5. Extends ADR-130's manual probe into a standing
fail-closed control; adds the Inclusion Principle + class adjudication + the
discriminator + control-probe + iterate-all invariant; references this plan's
Alternatives table. Cross-note ADR-130. Sweep this plan + tasks.md if the ordinal
is renumbered.

### C4 views
Read all three `.c4` files; apply the Phase 5 completeness enumeration
(`cloudflare` already modeled; confirm/add the CI-apply → Cloudflare read edge);
run the c4 tests after any edit.

### Sequencing
The ADR ships with the gate in this PR — not deferred.

## Acceptance Criteria

### Pre-merge (PR)

#### Functional Requirements
- [ ] Gate exits non-zero for a `cloudflare_ruleset` planned as `== ["create"]`
  with `before == null` whose (stubbed) live entrypoint returns 200 with ≥1 rule;
  exits 0 for 404 (empty) and for the import + steady-state shapes.
- [ ] Gate is **default-deny**: control-probe non-200, empty token, malformed
  plan JSON, unclassified `kind`, and every non-200/404 HTTP code (000/401/403/429/5xx/
  non-numeric) each yield a non-zero exit with a distinct message (one fixture per branch).
- [ ] Gate does NOT fire on a `-replace` (`["delete","create"]`, `before != null`)
  (fixture `tfplan-ruleset-replace.json`).
- [ ] Gate iterates the full `resource_changes[]` array (untargeted-create
  fixture fires) and aggregates across multiple matched rows (PASS+FAIL → non-zero).
- [ ] Gate makes **zero** live API calls when no create-from-absent whole-list
  resource is present (assert stub call-count 0 on import/steady-state/normal fixtures).
- [ ] Gate handles both `zone_id` and `account_id` rulesets; the `::error::` on a
  clobber carries a copy-pasteable **singular** `zone/<zone>/<ruleset_id>` import
  block + the live rules to reproduce.
- [ ] `apply-web-platform-infra.yml` invokes the gate as a separate step AFTER
  the "Terraform plan" step and BEFORE the **main** "Terraform apply" step, with
  `working-directory: INFRA_DIR`, `env: DOPPLER_TOKEN`, and NO `[ack-destroy]`
  bypass (wiring pinned by whitespace-normalized / independent-token greps).
- [ ] Parity test FAILs if any dispatch `-target` set gains a `cloudflare_ruleset`
  without a gate, or if a new `cloudflare_*` type appears un-adjudicated.
- [ ] `--audit` static mode emits the parity table; the audit job runs read-only
  (no `terraform apply` — asserted), on its own concurrency group + dispatch
  value, with `issues: write` GitHub App auth.
- [ ] `test/seo-config-rules.test.ts` two-rule + adopted-rule pin still passes
  (adoption NOT modified).

#### Quality
- [ ] New script + tests follow cap-coupling (dedicated files + CODEOWNERS +
  parity test) and are wired into the `tests/scripts/test-*.sh` harness.
- [ ] `bash tests/scripts/test-preapply-entrypoint-gate.sh` passes locally.
- [ ] ADR-133 created (thin, references plan Alternatives); ADR-130 cross-note
  added; C4 enumeration cited across all three `.c4` files; c4 tests pass.
- [ ] plan/SKILL.md Sharp Edge + `seo-config-rules.tf` comment updated.
- [ ] Fixtures synthesized (no live prod plan pasted).

### Post-merge (CI — automated, NOT dashboard eyeball)
- [ ] First merge exercises the gate on the apply run (expected no-op: no
  create-from-absent whole-list resource → zero API calls). *Automation:* apply
  run status in Actions.
- [ ] Ship dispatches `-f apply_target=entrypoint-audit` in-session, waits, and
  confirms the audit findings posted to #6767 before PR-ready. *Automation:* `gh
  workflow run` + `gh run watch` + read the #6767 comment (CTO F2 — not a deferred
  checkbox). Runbook `## Results` links to that comment.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — `terraform show -json tfplan
  > tfplan.json` capture (reused by destroy-guard); new gate step (post-plan,
  pre-main-apply, `working-directory` + `DOPPLER_TOKEN`); new guarded read-only
  `entrypoint-audit` dispatch value + job (own concurrency group + `issues:
  write` App auth, no `terraform apply`).
- `CODEOWNERS` — rows for the new gate script + tests.
- `plugins/soleur/skills/plan/SKILL.md` — entrypoint-enumeration Sharp Edge (prose → gate).
- `apps/web-platform/infra/seo-config-rules.tf` — one-line comment update.
- `knowledge-base/engineering/architecture/decisions/ADR-130-cloudflare-token-widen-vs-narrow-alias.md`
  — "see ADR-133" cross-note.
- `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4` — read
  all three; add the CI→cloudflare read edge only if the enumeration finds it absent.
- `scripts/test-all.sh` (and/or `.github/workflows/infra-validation.yml`) — wire
  the new test into the harness.
- This plan file — kept in sync if the ADR ordinal is renumbered.

## Files to Create

- `tests/scripts/lib/preapply-entrypoint-gate.sh` — `--gate` + `--audit`.
- `tests/scripts/test-preapply-entrypoint-gate.sh` — control-flow + wiring tests.
- `tests/scripts/test-preapply-entrypoint-gate-parity.sh` — dispatch-coverage +
  class-adjudication parity (may be folded into the test above).
- `tests/scripts/fixtures/tfplan-ruleset-create.json`
- `tests/scripts/fixtures/tfplan-ruleset-create-untargeted.json`
- `tests/scripts/fixtures/tfplan-ruleset-import.json`
- `tests/scripts/fixtures/tfplan-ruleset-steady-state.json`
- `tests/scripts/fixtures/tfplan-ruleset-replace.json`
- `knowledge-base/engineering/architecture/decisions/ADR-133-preapply-entrypoint-enumeration-gate.md`
- `knowledge-base/engineering/operations/runbooks/cloudflare-whole-list-entrypoint-audit.md`

## Open Code-Review Overlap

None. Queried open `code-review` issues (50, `--json number,title`); none name
`apply-web-platform-infra.yml`, `destroy-guard-filter-web-platform.jq`, the CF
ruleset `.tf` files, or `tests/scripts/`. The check ran.

## Domain Review

**Domains relevant:** none

No cross-domain (business) implications — internal infrastructure/CI tooling.
Product/UX Gate: NONE (Files are `.sh`, `.yml`, `.tf` comment, `.md`, `.c4` — no
UI-surface path matches the mechanical override). The engineering/CTO + blast-radius
+ flow lenses were covered by the mandatory 6-agent plan-review panel (DHH,
Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cto),
escalated per the `single-user incident` threshold; findings folded in above.

## Risks & Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty/`TBD`/omits the threshold
  fails `deepen-plan` Phase 4.6.** Filled (threshold `single-user incident`,
  `requires_cpo_signoff: true`).
- **Fail-open is the cardinal risk.** Every ambiguous outcome exits non-zero.
  Default-deny (PASS only on proven-empty), the control probe, the `[[ -n "$TOK" ]]`
  and `.resource_changes|type==array` guards, `curl --max-time`, loop
  aggregation, and the exact-match `["create"]` discriminator all exist to close
  a specific fail-open seam the panel surfaced.
- **The gate must not become a plan-derived guard.** Its only plan input is
  shape; the decision comes from the live API. Do not "optimise" it into a jq
  count or scope it to the `-target` list (architecture Finding C).
- **`terraform show -json` field shapes are a P0 verification** (create vs
  import vs replace vs CBD) against TF 1.10.5 / provider 4.52.7.
- **Import ID / provider-version trap** (v4 singular `zone/`; plural `zones/`
  fails as `Authentication error (10000)`). The gate only reads (no import), but
  the `::error::` remedy + ADR must print the singular form.
- **Orphan test suite.** Wire the test + parity test into `scripts/test-all.sh`
  or it silently rots.
- **ADR ordinal collision.** ADR-133 provisional; re-verify next-free at ship;
  sweep this plan + tasks.md if renumbered.
- **The audit's `## Results` cannot be pre-filled at `/work`** (no live creds);
  ship dispatches the audit job in-session and blocks PR-ready on the #6767
  comment — never eyeballed, never a post-merge checkbox.
- **Audit recording depends on `issues: write` + GitHub App auth** — the default
  job perms (`contents: read`) make `gh issue comment` fail silently.

## Test Scenarios

See the fixture-by-fixture list in Phase 4. Every branch of the gate's decision
table (control probe, kind allowlist, HTTP default-deny, loop aggregation,
input/token guards, replace/import/steady-state exemptions, untargeted-create
invariant) has a dedicated fixture + assertion with a stubbed fetch and no live
API in the assertion path.
