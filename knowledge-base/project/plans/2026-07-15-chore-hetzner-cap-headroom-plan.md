---
date: 2026-07-15
type: chore
issue: 6453
pr: 6457
branch: feat-hetzner-cap-headroom
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-15-hetzner-cap-headroom-brainstorm.md
spec: knowledge-base/project/specs/feat-hetzner-cap-headroom/spec.md
---

# chore: Hetzner cap headroom — stock preflight, rule amendment, ledger reconcile (#6453)

## Overview

#6453 asked for a **cap** preflight to protect destroy-then-create recreates. Live
probes falsified the premise: a `-replace` frees its own slot, so the cap never
engages on a recreate. The operator confirmed dropping it.

What the probes found instead is worse than the issue described, and it reshapes
this plan: **the fleet's recreate paths are blocked by DC *stock*, not by the quota,
and two of them are blocked right now.**

G1 (reclaim `hermes-agent`) already shipped in-session — fleet is 4/5. This plan
covers the remainder.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (live-probed 2026-07-15) | Plan response |
|---|---|---|
| Spec/brainstorm: "raise the cap → unblocks ADR-068 Phase 3 (git-data)" | **False.** `git_data_server_type` = `cax11` (`variables.tf:113`); the entire ARM `cax` line is orderable in **0 of 3 EU DCs**. git-data cannot be born at **any** cap. | Corrected in the brainstorm (inline note). Cap raise is justified by probe hosts + web-3 **only**. Removed git-data from the raise's rationale. |
| Brainstorm: "reclaim only funds git-data's unborn slot" (platform-strategist) | **Dissolved.** git-data cannot claim the slot (no cax11 stock). The reclaimed slot is genuine free headroom. | No action — the reclaim already shipped and is now better-justified than when authorised. |
| Spec: "steady-state need is 6 (5 permanent incl. git-data + 1 ephemeral)" | Permanent is **4** while cax11 has no EU stock. Need is **5** (4 + 1 ephemeral); 6 if git-data ever becomes orderable. | Still ask **10** — a limit is free and the ask is one-shot. Rationale changes, number does not. |
| FR6/TR2: "stock preflight mechanics UNVERIFIED; `/v1/limits` is 404" | **Buildable.** `GET /v1/datacenters` exposes `server_types.available` (orderable now) vs `.supported` (24). hel1 = 14 available of 24. | FR6 **ships**. TR2's drop-clause does not fire. |
| Spec AC: "`hcloud server list` returns 4" | Done 2026-07-15. | Marked `[x]`. |
| `expenses.md:14-16` / `:17-19` line refs | Still accurate — the hermes row was inserted at `:24`, after both. | No renumbering needed. |
| Snapshot retention "expiry" | Hetzner images have **no TTL field** (`PUT /v1/images/{id}` accepts only `description`/`labels`/`type`). | Implement as a **follow-through enrollment** (Phase 2.9.1), the repo's native soak-gated pattern — not a label-only note. |

### The finding that reshapes the plan

`GET /v1/datacenters`, 2026-07-15:

```
fsn1-dc14 orderable NOW:  ccx33 ccx43 cpx32 ccx13 cpx22 cpx52 cpx62 ccx63 ccx53 cpx12 cpx42 ccx23
hel1-dc2  orderable NOW:  ccx33 cx23 ccx43 cpx32 ccx13 cpx22 cpx52 cpx62 cx33 ccx63 ccx53 cpx12 cpx42 ccx23
```

- **`cx33` is orderable in exactly one DC globally: `hel1-dc2`.** `web-2` is `cx33 @ fsn1`
  → **`web-2-recreate` would strand the fleet today.** A verbatim #6393 repeat, in the DC
  #6393 fled *to*. Remediation filed as **#6463** (cost/HA tradeoff — operator's call).
- **`cax11` is orderable in 0 of 3 EU DCs** → git-data unborn regardless of cap.

**The stock preflight is therefore not speculative — it fires on two live paths today.**
A cap preflight would have returned green on both.

## User-Brand Impact

Carried forward verbatim from the brainstorm/spec — not re-authored.

- **If this lands broken, the user experiences:** a recreate destroys `web-2`, stock
  blocks re-placement, and apply-on-merge wedges — so if `web-1` degrades in that window
  users hit a full outage with no failover, no ability to deploy a fix, and no free slot
  to diagnose from, while the HA posture reads healthy because `web-1` is still up.
- **If this leaks, the user's data/workflow is exposed via:** snapshot `408787015` holds
  an unaudited 40 GB disk of unknown provenance; retained without expiry it is continued
  processing of data we never inventoried (CLO).
- **Brand-survival threshold:** `single-user incident`.

**Adjudicated, not speculative:** the 2026-07-13 PIR's "no user-facing impact" framing
was formally corrected on 2026-07-14 (#6400) — the same apply-wedge froze the `web-1`
prod deploy leg ~10+ hours (`2026-07-13-web-2-fsn1-warm-standby-auth-denied-postmortem.md:22-25`).

`requires_cpo_signoff: true`.

**CPO sign-off: GRANTED at plan-review (2026-07-15), conditional on the Phase 1.3 escape
path — which is implemented.** The plan originally claimed the brainstorm's sign-off
carried forward without a re-spawn; the CPO rejected that reasoning on review: *"A plan
cannot assert its own sign-off,"* and the scope had materially changed (cap preflight
dropped, stock preflight added, the git-data rationale collapsed). The fresh call is this
review, not the brainstorm. Recorded here rather than left as a self-certification.

## Domain Review

**Domains relevant:** Engineering, Legal, Product — all three carried forward from the
brainstorm's `## Domain Assessments` (CPO + CLO + CTO + platform-strategist). No fresh
assessment; scope has not materially changed since, except the stock findings above,
which **strengthen** the CTO's stock-over-cap position rather than reopening it.

### Engineering

**Status:** reviewed (carry-forward)
**Assessment:** CTO: drop the cap preflight (a `-replace` needs zero free slots); amend
the existing hard rule rather than mint a new id. platform-strategist: ship a stock
preflight in tripwire posture into the existing destroy-guard steps; fail-closed, no
`[ack-destroy]` bypass. Both positions are now corroborated by live probe.

### Legal

**Status:** reviewed (carry-forward)
**Assessment:** CLO: snapshot of unknown data is continued processing → needs a retention
expiry (FR1). The residency validation gap (`var.location` / `var.registry_location` carry
no EU-DC check) is the sharpest finding and is in scope (FR5).

### Product

**Status:** reviewed (carry-forward)
**Assessment:** CPO: p2 is mis-prioritised for the reclaim (shipped, moot) but correct for
the durable guards. Sequencing reclaim → preflight → naming → raise. Flagged that a
slot-count-only check would not catch #6393 — now proven.

### Product/UX Gate

**Tier:** none — no UI surface. `## Files to Edit` contains only `.yml`, `.tf`, `.md`,
and `.sh` paths; zero matches against `references/ui-surface-terms.md` (no page,
component, modal, banner, nav, flow, or email template). Mechanical UI-surface override
did not fire.

## Architecture Decision (ADR/C4)

**No ADR.** This plan makes no architectural decision: the reclaim was operational
cleanup, the cap raise is a vendor-limit change, and the preflight/rule-amendment
encode an existing invariant rather than changing one. The one genuine architectural
decision in this space — **blue-green via add/drain/remove** (per-host naming, IP
allocation, replacing `-replace`) — is deferred and **already filed as #6459 with an
ADR named as its deliverable**.

**No C4 impact.** Checked all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) for
this change's external actors, external systems, containers, and access relationships:

- **External human actors:** none added or changed — this is operator-facing infra with
  no new correspondent, reviewer, or recipient role.
- **External systems:** **Hetzner Cloud** is the only vendor touched, and it is already
  modelled as the hosting substrate; no new vendor edge (the limit-raise is a change to
  an existing account's quota, not a new integration).
- **Containers / data stores:** none added. `hermes-agent` was never modelled (it was
  never in IaC — that absence is the subject of #6460); removing it changes no modelled
  element. `soleur-git-data` remains modelled-but-unborn — **not corrected here**,
  because the phantom-corpus cleanup is tracked in #6460 and correcting the C4 for a
  host that may yet be born (once cax11 restocks) would be premature.
- **Access relationships:** none change — no actor↔surface access is added or widened.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/variables.tf` only — two `validation` blocks added to existing
variables (`location`, `registry_location`). **No new resources, no new providers, no new
sensitive variables, no state change.** A `validation` block is config-phase only.

### Apply path

**None required.** Variable validation runs at config-phase on every `terraform
plan`/`apply`; it does not create, modify, or destroy any resource. The next
merge-triggered apply exercises it for free. The workflow edits (FR6) are CI-only.

### Distinctness / drift safeguards

The validation is a *tightening* — it rejects a config that would previously have been
accepted. Confirm current values pass before merging (they do: `location = "hel1"`,
`registry_location = "hel1"`, both in the EU allow-set), or the next apply fails closed
on a legitimate config. **AC5 covers this.**

### Vendor-tier reality check

N/A — no new vendor resource.

## Observability

```yaml
liveness_signal:
  what: The stock preflight step's own PASS/ABORT annotation in the recreate dispatch job
  cadence: on every web-2-recreate / inngest-host-replace / registry-host-replace dispatch
  alert_target: the dispatching operator (workflow run status — a fail-closed abort is red)
  configured_in: .github/workflows/apply-web-platform-infra.yml (the three destroy-guard steps)
error_reporting:
  destination: GitHub Actions annotation (::error::) + non-zero exit
  fail_loud: true — fail-closed, no [ack-destroy] bypass (matches :1775, :1613, :2170)
failure_modes:
  - mode: target server_type not orderable in target location (the #6393 / #6463 class)
    detection: preflight asserts type ∈ datacenters[location].server_types.available
    alert_route: ::error:: + abort BEFORE the destroy; run goes red
  - mode: Hetzner API unreachable / malformed response during preflight
    detection: curl non-2xx or jq parse failure
    alert_route: fail-closed (abort). A preflight that cannot prove stock MUST NOT
      permit the destroy — an unavailable API is not evidence of availability.
  - mode: stock evaporates between preflight and apply (TOCTOU)
    detection: NOT detectable — accepted. terraform surfaces resource_unavailable and
      the fleet strands, exactly as today. The tripwire narrows the window; it does not
      close it. The non-racy fix is create-before-destroy (#6459).
logs:
  where: GitHub Actions run logs for apply-web-platform-infra.yml
  retention: GitHub default (90d)
discoverability_test:
  command: >-
    export HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain);
    bash apps/web-platform/infra/scripts/stock-preflight.sh cx33 fsn1; echo "exit=$?"
  expected_output: "exit=1 (cx33 is not orderable in fsn1 today — the #6463 trap). `... cx33 hel1` → exit=0."
```

No `ssh` in the discoverability test. The preflight is inspectable from any machine with
the read-only token.

### Soak Follow-Through Enrollment (FR1)

The snapshot-retention decision **is** a soak-gated close criterion ("no incident traced
to `hermes-agent` for N days → delete snapshot `408787015`"), so it enrolls per Phase 2.9.1:

- **Script:** `scripts/followthroughs/hermes-snapshot-retention-6453.sh` — exits 0 when the
  soak holds (snapshot older than the window AND no reopened incident), which is the signal
  to delete.
- **Directive** on #6453: `<!-- soleur:followthrough script=scripts/followthroughs/hermes-snapshot-retention-6453.sh earliest=2026-08-14 secrets=HCLOUD_TOKEN -->` + the `follow-through` label.
- **Sweeper wiring:** `HCLOUD_TOKEN` must be added to `.github/workflows/scheduled-followthrough-sweeper.yml`'s `secrets=` allow-set if not already present.

30 days is the window: long enough that a low-rate outbound producer's absence would have
surfaced, short enough to bound the retention of unaudited data (CLO).

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --json number,title,body --limit 200`
returned no issue body containing any path in `## Files to Edit`.

## Phase 0 — Preconditions (verify BEFORE coding; each can re-shape a later phase)

These are the plan's unverified load-bearing assumptions. Each is a cheap probe whose
failure changes the plan, so they run first.

- [ ] **P0.1 — plan JSON availability (gates FR6's whole wiring).** Read the destroy-guard
      steps at `apply-web-platform-infra.yml` `:1165`, `:1583`, `:1744`, `:1877`, `:2079`.
      Confirm a `terraform show -json` output is available in each, and that a `-replace`
      create carries `server_type` + `location` in `.resource_changes[].change.after`.
      **If not, re-shape Phase 2.1 before coding.**
- [ ] **P0.2 — `-replace` on a not-in-state address.** Confirm `terraform plan -replace=<addr>`
      for an address absent from state exits 0 and plans a plain **create** (architecture
      review established this; verify independently — it is the basis for treating
      `git-data-host-replace` as live rather than dead).
- [ ] **P0.3 — test discovery.** Confirm whether `scripts/test-all.sh` globs `tests/scripts/`.
      If yes, Phase 2.5's `infra-validation.yml` step is a no-op; if no, it is mandatory.
      **Do not assume — the whole deliverable's CI coverage rides on this.**
- [ ] **P0.4 — sourced-gate precedent.** Read `tests/scripts/lib/web2-recreate-gate.sh` and
      match its shape (function export, sourcing contract, exit semantics).
- [ ] **P0.5 — follow-through exit semantics.** Read `.github/workflows/scheduled-followthrough-sweeper.yml`
      + `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh` and confirm the exit-code
      convention before authoring FR1's script (the plan asserts "exit 0 = soak held = delete";
      **verify that matches the sweeper's actual interpretation**).

## Implementation Phases

Phase order is dependency-directed: the gate must exist before the workflow steps source it.

### Phase 1 — Stock preflight as a **sourced gate** (TDD)

**Shape corrected per CTO review:** the repo's established pattern for these exact steps
is a *sourced gate* exposing a function, sourced by **both** the workflow and its test so
CI runs the same bytes (precedent: `tests/scripts/lib/web2-recreate-gate.sh:1-10`). Do
**not** author a standalone `infra/scripts/stock-preflight.sh` — that invents a second
pattern and lands outside test discovery.

1.1 Write failing test `tests/scripts/test-stock-preflight-gate.sh` covering:
  - orderable type/location → exit 0 (`cx33 hel1`)
  - non-orderable type/location → exit 1 (`cx33 fsn1` — the live #6463 trap)
  - non-orderable ARM type → exit 1 (`cax11 hel1` — 0 EU DCs)
  - unknown server type → exit 1 (fail-closed)
  - unknown location → exit 1 (fail-closed)
  - API failure (mocked non-2xx) → exit 1 (fail-closed)

1.2 Implement `tests/scripts/lib/stock-preflight-gate.sh` exposing
    `stock_preflight <server_type> <location>`:
  - resolve `server_type` name → id via `GET /v1/server_types?per_page=50`
  - resolve `location` → its **single** datacenter via `GET /v1/datacenters`
  - assert the type id ∈ `datacenters[].server_types.available` (**not** `.supported`)
  - fail-closed on any resolution/API failure
  - **read-only**; needs only `HCLOUD_TOKEN`

1.3 **Abort message** (per CTO — the plan previously left this underspecified, and CPO
    conditioned sign-off on the escape path being present). On a stock miss, emit the
    orderable locations for the target type — **already in the same `/v1/datacenters`
    response, no extra call** — so the abort is a fork, not a wall:

```
::error::stock-preflight ABORT: server_type 'cx33' is NOT orderable in 'fsn1' today
(orderable: hel1). A -replace DESTROYS before it creates — this recreate would strand the
fleet with no rollback (#6393, #6463). Options: (1) re-dispatch against a location where
cx33 is orderable; (2) if this host must stay in fsn1, see #6463 (type/DC change is an
operator cost/HA decision); (3) stock is time-varying — re-run later. Do NOT bypass.
```

  The **API-blip** mode MUST be a distinct message, or operators read a blip as a real
  shortage and open a spurious #6463 dup:
  `::error::stock-preflight ABORT: cannot PROVE stock for '<type>' in '<loc>' (Hetzner API unreachable). An unreachable API is not evidence of availability. Re-dispatch.`

### Phase 2 — Wire the gate into **all five** destroy-shaped paths + CI discovery

2.1 `apply-web-platform-infra.yml` — source the gate and call it from the existing
    plan-time destroy-guard steps. Derive `server_type`/`location` from the terraform
    plan JSON already produced in those steps (do **not** re-read `variables.tf` — a
    `TF_VAR_*` can override a default; the plan is what actually applies).
    **VERIFY FIRST (Phase 0 precondition):** confirm the plan JSON is available in each
    step and that a `-replace` create carries `server_type`/`location` in
    `.resource_changes[].change.after`. If it does not, re-shape this phase before
    coding — this is FR6's load-bearing assumption and it is **not yet verified**.
2.2 Tripwire framing in the step comment, matching `:447` in posture ("This is a
    TRIPWIRE, not a routine gate").
2.3 **No `[ack-destroy]` bypass** — matches `:1775`, `:1613`, `:2170`.
2.4 **Five paths, not three.** `:1165` (web-2), `:1583` (inngest), `:1744` (registry),
    `:1877` (registry-region-migrate — destroy-then-create with a *target region*), and
    **`:2079` (git-data-host-replace)**.

  > **Corrected — the "dead code" premise was FALSE.** The plan previously skipped
  > `git-data-host-replace` on the belief that a scoped `-replace` requires the resource
  > in state. Architecture review established that **`terraform plan -replace=<addr>` on
  > an address NOT in state exits 0 with no error and plans a plain CREATE.** Since
  > `hcloud_server.git_data` is declared unconditionally (`git-data.tf:118`), that
  > dispatch would attempt to **create git-data** — into a 5-server cap, with a `cax11`
  > type that is orderable in **0 EU DCs**. It is a live path that fails, not dead code.
  > It needs the gate most of all. **Re-verify this terraform behaviour at Phase 0**
  > before relying on it (the reviewer verified it; this plan's author did not).

2.5 **Wire the test into CI — non-optional.** `scripts/test-all.sh:219` globs
    `apps/web-platform/scripts/*.test.sh` but **NOT** `infra/*.test.sh`; infra tests run
    from a **hand-maintained explicit list** in `.github/workflows/infra-validation.yml:167-200`
    (one `run:` step per file, no glob). Without this the gate's test ships dead — green
    PR, zero coverage, AC1 passing only because a human ran it locally. Add the step.
    (`tests/scripts/` discovery: confirm at Phase 0 whether `test-all.sh` already globs
    it; if so, 2.5 is satisfied by the relocation in Phase 1 and this step is a no-op —
    **verify, do not assume**.)

### Phase 3 — Amend the hard rule

3.1 Amend `hr-prod-host-config-change-immutable-redeploy` (`AGENTS.core.md:26`) **in
    place** — same id — to name the no-rollback danger: `-replace` destroys before it
    creates, so any create-failure (DC stock, cloud-init, name collision) strands the
    fleet with no rollback; verify target-type stock in the target location first.
3.2 Keep the body **≤ 600 B** (`lint-agents-rule-budget.py` rejects above).
3.3 **Measure `B_ALWAYS` before and after.** It is **22757 B** today — already over the
    22000 critical threshold (#6461). The amendment MUST be byte-neutral-or-negative;
    if it grows the body, trim redundant prose in the same rule (preserving per-issue
    mechanism labels after each `#N`). **Do not add a new rule** — a new pointer costs
    ~50-60 B of always-loaded budget that does not exist.

### Phase 4 — Residency validation

4.1 Add `validation` blocks to `var.location` (`variables.tf:38`) and
    `var.registry_location` (`:44`), mirroring `web_hosts`' condition at `:94-96`:
    `contains(["nbg1","fsn1","hel1"], var.location)`.
4.2 Error message mirrors `:96`'s framing (GDPR residency, CLO T-1).
4.3 Verify current values pass (`hel1` both) — a tightening that fails closed on live
    config would break the next apply.

### Phase 5 — Ledger reconcile + follow-through enrollment

5.1 `expenses.md:14-16` — git-data host/IPv4/LUKS volume: `active` → `approved-not-billing`
    (~$5.12/mo phantom). Add a note: the host has never existed; **cax11 is orderable in
    0 EU DCs**, so it cannot be born at any cap.
5.2 `expenses.md:17-19` — web-2 `hel1` → `fsn1` (stale since #6393). Reference #6463.
5.3 Author `scripts/followthroughs/hermes-snapshot-retention-6453.sh`; add the
    `soleur:followthrough` directive + `follow-through` label to #6453; wire `HCLOUD_TOKEN`
    into the sweeper's `secrets=` if absent.

### Phase 6 — Limit-raise tracking

6.1 Add the `action-required` label + an operator-facing issue for the Console limit raise
    (server → 10, **and** the volume limit — separate counter). It is **verified**
    operator-only:
    `playwright-attempt: not applicable — no Hetzner Console credentials exist in Doppler
    (only HCLOUD_TOKEN, an API token that cannot reach the limits form); GET /v1/limits → 404;
    Console is OAuth + MFA + probable Turnstile; no precedent for infra-provider console
    automation.`
    Per the plan skill's automation-feasibility gate, the absence of credentials — not an
    a-priori "console-gated" assertion — is the evidence.
6.2 The raise's rationale is **probe hosts + web-3 only**. Do **not** justify it by
    git-data (stock-blocked, not cap-blocked).

## Files to Edit

| File | Change |
|---|---|
| `tests/scripts/lib/stock-preflight-gate.sh` | **new** — sourced gate exposing `stock_preflight <type> <location>` (matches `web2-recreate-gate.sh`) |
| `tests/scripts/test-stock-preflight-gate.sh` | **new** — 6 cases, fail-closed coverage |
| `.github/workflows/apply-web-platform-infra.yml` | gate into **5** destroy-shaped steps (`:1165`, `:1583`, `:1744`, `:1877`, `:2079`) |
| `.github/workflows/infra-validation.yml` | **add the test step** — the list at `:167-200` is hand-maintained, not a glob. **Without this the test ships dead.** (No-op only if Phase 0 proves `test-all.sh` already discovers `tests/scripts/`.) |
| `plugins/soleur/test/terraform-target-parity.test.ts` *(or a sibling)* | coverage-enumeration test for AC3 + `EXCLUSION_ALLOWLIST` |
| `AGENTS.core.md` | amend `hr-prod-host-config-change-immutable-redeploy` in place (≤600 B, byte-neutral) |
| `apps/web-platform/infra/variables.tf` | 2 `validation` blocks (`location`, `registry_location`) |
| `knowledge-base/operations/expenses.md` | `:14-16` status flip; `:17-19` region fix |
| `scripts/followthroughs/hermes-snapshot-retention-6453.sh` | **new** — soak probe |
| `.github/workflows/scheduled-followthrough-sweeper.yml` | add `HCLOUD_TOKEN` to `secrets=` if absent |

## Files to Create

None beyond the three new scripts above. **No `components/**/*.tsx`, `app/**/page.tsx`,
or `app/**/layout.tsx`** — the mechanical UI escalation does not fire.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `bash apps/web-platform/infra/stock-preflight.test.sh` passes all 5 cases.
- [ ] **AC2** `bash apps/web-platform/infra/scripts/stock-preflight.sh cx33 fsn1; echo $?` → `1`
      (the live #6463 trap) and `... cx33 hel1` → `0`. Both with `HCLOUD_TOKEN` exported.
- [ ] **AC3** *(reshaped per CTO — the old `grep -c … >= 4` did NOT bind a preflight to a
      **path**; four calls inside one job would pass it.)* A **coverage-enumeration test**
      asserts every recreate-shaped `apply_target` option has the gate in its job body.
      Model it on `plugins/soleur/test/terraform-target-parity.test.ts`, which already
      parses **this exact workflow** to assert target coverage, and read the options from
      the `apply_target.options` enum (`apply-web-platform-infra.yml:92-104`, 8 items).
      `git-data-host-replace` is **in** the covered set (see Phase 2.4 — it is not dead
      code). Any genuinely-excluded target goes in an explicit `EXCLUSION_ALLOWLIST`
      (mirroring `terraform-target-parity.test.ts:81`) so an exclusion is **declared**,
      not silently skipped — and so a future target auto-enrolls.
      **This is what prevents a 5th dispatch path shipping without the gate.**
- [ ] **AC4** No bypass token added:
      `grep -c 'ack-destroy' .github/workflows/apply-web-platform-infra.yml` == **23**
      (the `origin/main` baseline, measured 2026-07-15). The token legitimately appears 23×
      elsewhere in the file, so an absolute `== 0` would false-fail a correct implementation.
      The invariant is *unchanged*, not *absent*.
- [ ] **AC5** `cd apps/web-platform/infra && terraform validate` passes, **and** a
      `terraform plan` with the live `hel1` values does not error on the new validations.
- [ ] **AC6** `python3 scripts/lint-agents-rule-budget.py` passes, **and** `B_ALWAYS` after
      ≤ `B_ALWAYS` before (baseline **22757 B**). Rule id unchanged:
      `grep -c 'hr-prod-host-config-change-immutable-redeploy' AGENTS.core.md` == 1 and
      `grep -c 'hr-destroy-requires-headroom' AGENTS*.md` == 0.
- [ ] **AC7** `grep -cE '^\| Hetzner (CAX11 \(git-data\)|Primary IPv4 \(git-data\)|Volume \(git-data)' knowledge-base/operations/expenses.md` == 3 **and** none of those 3 rows contains `| active |`.
- [ ] **AC8** Zero `active` rows for git-data: `awk -F'|' '/git-data/ && $6 ~ /active/' knowledge-base/operations/expenses.md | wc -l` == 0.
- [ ] **AC9** web-2 rows read fsn1:
      `awk -F'|' '/\(web-2/ && /hel1/' knowledge-base/operations/expenses.md | wc -l` == 0.
- [ ] **AC10** Every `knowledge-base/` path cited in this plan resolves:
      `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'` → empty.
- [ ] **AC11** `bash scripts/followthroughs/hermes-snapshot-retention-6453.sh; echo $?` → non-zero today (soak window has not elapsed; `earliest=2026-08-14`).
- [ ] **AC12** #6453 carries the `soleur:followthrough` directive + `follow-through` label.
- [ ] **AC14** *(CPO sign-off condition — the escape path)* The stock-miss abort names the
      **orderable locations for the target type** and points at #6463. Verify:
      `stock_preflight cx33 fsn1 2>&1 | grep -q 'orderable: hel1'` **and**
      `... | grep -q '#6463'`. The data comes from the `/v1/datacenters` response the gate
      already fetched — no extra call. **This is what makes the abort a fork instead of a
      wall**, and CPO conditioned sign-off on it.
- [ ] **AC15** The API-blip abort is a **distinct** message from the stock-miss abort
      (`grep -q 'cannot PROVE stock'`), so an operator does not read a blip as a real
      shortage and file a spurious #6463 duplicate.
- [ ] **AC16** The gate's test actually runs in CI — not just locally. Either
      `grep -q 'test-stock-preflight-gate' .github/workflows/infra-validation.yml`, **or**
      P0.3 proved `scripts/test-all.sh` discovers `tests/scripts/`. **One of the two must
      hold**; a green PR with a dead test is the failure mode this AC exists for.

### Post-merge (operator)

- [ ] **AC13** Hetzner Console → Limits → "Request change → Limit increase": **server → 10**, and raise the **volume** limit.
      `Automation: not feasible because no Hetzner Console credentials exist in Doppler (only HCLOUD_TOKEN, an API token that cannot reach the limits form); GET /v1/limits → 404 (probed); Console is OAuth + MFA + probable Turnstile; no precedent for infra-provider console automation.`
      Tracked by the `action-required` issue from Phase 6.1 — not left to memory.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | `stock-preflight.sh cx33 hel1` | exit 0 |
| T2 | `stock-preflight.sh cx33 fsn1` | exit 1 + `::error::` (live #6463 trap) |
| T3 | `stock-preflight.sh cax11 hel1` | exit 1 (ARM line, 0 EU DCs) |
| T4 | `stock-preflight.sh bogus99 hel1` | exit 1 (unknown type → fail-closed) |
| T5 | `stock-preflight.sh cx33 atlantis` | exit 1 (unknown location → fail-closed) |
| T6 | API returns 500 (mocked) | exit 1 (fail-closed — unavailable API ≠ available stock) |
| T7 | `terraform validate` with `location = "us-east"` | rejected by the new validation |
| T8 | `terraform validate` with live `hel1` values | passes |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **TOCTOU** — stock evaporates between preflight and apply | **Accepted, documented.** The window is seconds-to-minutes; #6393's shortage persisted long enough to fail 4 retries. The non-racy fix is create-before-destroy (#6459). |
| The preflight fails-closed on a transient Hetzner API blip, blocking a legitimate recreate | Intended. At `single-user incident` threshold, a blocked recreate is strictly better than a stranded fleet. Re-dispatch is cheap; a stranded fleet is a 10-hour deploy freeze (#6400). |
| Deriving type/location from `variables.tf` instead of the plan JSON | **Avoided by design** (Phase 2.1): read the plan JSON. A default in `variables.tf` can be overridden by a `TF_VAR_*`; the plan is what actually applies. |
| The rule amendment grows `B_ALWAYS` past the cap and blocks the commit | AC6 gates it. Baseline captured (22757 B). Trim within the same rule if needed. |
| Fresh boots fail silently (3 postmortems in 2 weeks) | **Out of scope and unchanged by this plan** — the preflight gates the *create's feasibility*, not the boot's success. Readiness assertions are deferred (brainstorm `## Deferred`). This plan does not birth any host. |
| Residency validation tightening breaks the next apply | AC5 verifies live values pass before merge. |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **Cap preflight** (`free_slots == 0`) — the issue's original ask | A `-replace` frees its own slot; the cap never engages on a recreate. Would fail every recreate for no reason, and returns green on #6393/#6463. Operator-confirmed drop. |
| **Create-before-destroy** | The only non-racy fix, but `create_before_destroy` exists nowhere and the singletons have hard-coded names + pinned IPs that collide first. IaC redesign → **#6459** (with an ADR). |
| **New rule `hr-destroy-requires-headroom`** | "Headroom" is the wrong frame (the cap is not what makes `-replace` dangerous), and `B_ALWAYS` is already over the critical cap (#6461). Amend the existing rule instead. |
| **Automate the Console limit-raise** | No Console credentials exist in Doppler; OAuth + MFA + Turnstile; no precedent. Verified operator-only. |
| **Change web-2's type/DC now** to make it recreatable | A real cost/HA tradeoff needing an operator decision → **#6463**. This plan ships the *detection*; #6463 owns the *remediation*. **CPO reviewed this split and endorsed it over folding in** — folding would execute a destroy-then-create of the warm standby inside the same PR that ships the gate protecting it, on a guard that has never fired in anger, alongside a Terraform tightening and a hard-rule edit. Sign-off was conditioned on the **escape path** (Phase 1.3) instead. |
| **`hcloud` CLI instead of curl+jq** | **False-green — verified.** `hcloud server-type list -o columns=name,location` reports `cx33 → fsn1,nbg1,hel1`, which is the **supported/prices** set, not the orderable one. It would PASS the live #6463 trap. `hcloud datacenter describe hel1-dc2 -o json \| jq '.server_types.available'` is correct but returns **IDs**, so the name→id resolution is still needed — no savings. `hcloud` is also not installed on the runner (zero hits in the workflow). **Keep curl+jq, and name this rejected false-green in a code comment** so a future maintainer does not "simplify" straight into #6463. |
| **Terraform `data "hcloud_datacenter"` + `precondition`** instead of a shell gate | **Catastrophically wider blast radius.** A `data` source + precondition evaluates at **plan time on every apply — including the per-merge path**. A Hetzner blip would then wedge *every* apply, not just the recreate dispatches. That is the #6285 lesson (a `data` source 403 at plan time wedges the whole root) amplified: fail-closed is correct on 4-5 dispatch paths and unacceptable on the merge path. The shell gate confines fail-closed to exactly the paths that destroy. |

## Deferred (tracked)

- **#6459** — blue-green via add/drain/remove (needs its own ADR)
- **#6460** — fleet-capacity-audit / phantom-resource detection
- **#6461** — AGENTS always-loaded payload over the 22k cap (98/198 rules unused)
- **#6463** — web-2 is un-recreatable (cx33 orderable in hel1 only)
- git-data birth — blocked by cax11 EU stock **and** the cap **and** #6416 **and** ADR-115's `luksOpen`; GA trigger #5274 is "Post-MVP / Later"

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one is carried forward
  from the brainstorm — do not re-author it.
- **`available` vs `supported`** on `/v1/datacenters` are different fields. `supported` (24 types
  in every EU DC) is what the DC *can* host; `available` (12-14) is what is *orderable now*. A
  preflight built on `supported` would pass on the #6463 trap. Use `available`.
- Each Hetzner **location** maps to exactly one **datacenter** (`fsn1 → fsn1-dc14`), so there is
  no sibling-DC fallback within a location. Resolve location → its single DC; do not assume a set.
- Stock is **time-varying**. `cx33 @ fsn1` may return. Do not encode today's availability as a
  constant — the preflight must query live, every dispatch.
</content>
