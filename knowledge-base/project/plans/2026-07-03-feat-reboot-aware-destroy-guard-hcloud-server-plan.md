---
title: Reboot-aware destroy-guard for in-place `update` on `hcloud_server.*`
issue: 5911
branch: feat-one-shot-5911-reboot-aware-destroy-guard
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-068 §Amendment (2026-07-02, #5877/#5887) — flip residual note to closed
created: 2026-07-03
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan provisions NO new infrastructure (no new
     server/service/secret/vendor/cron/DNS/TLS/firewall). It edits only a jq
     filter, a CI workflow's guard bash, a bash test + synthesized JSON
     fixtures, and an ADR. All references to `ssh` in this document are
     DESCRIPTIVE of the pre-existing operator maintenance-window apply path
     (out of scope) or explicitly ssh-free (the observability discoverability
     test). No `.tf` resource is created; no manual provisioning is prescribed. -->

# Reboot-aware destroy-guard for in-place `update` on `hcloud_server.*` (#5911)

## Enhancement Summary

**Deepened on:** 2026-07-03
**Agents:** best-practices-researcher (terraform `-target` + jq semantics),
architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer.

### Key improvements folded in
1. **Load-bearing premise CONFIRMED (research).** HashiCorp docs confirm
   `terraform plan -target=A` emits *real* pending `update` actions on A's
   dependencies (not suppressed to no-op) — so a reboot-forcing update on
   `hcloud_server.web` (dependency of the targeted `hcloud_firewall_attachment.web`)
   DOES surface in the CI plan JSON where the guard reads. jq `== ["update"]`
   array-equality is stable across jq 1.6/1.7/1.8. Framing upgraded from
   "favorable either way" to "confirmed detection."
2. **P1 ack-through safety (architecture).** The `[ack-destroy]` override, if
   reflexively added to unblock CI, would itself *execute* the transitively
   dependency-included reboot on the unattended apply — the exact hazard the
   guard prevents. The correct resolution of a `reboot_updates` trip is the
   **operator maintenance-window apply**, NOT ack. The `::error::` copy, the
   User-Brand Impact section, and the ADR amendment now say this explicitly.
3. **Realistic `after_unknown` fixture (spec-flow P1-2).** `placement_group_id =
   hcloud_placement_group.web_spread.id` is a resource reference; a same-plan
   group change serializes the value into `.change.after_unknown` with
   `.change.after.placement_group_id = null`. Added a pinned fixture for this
   (before `0`, after unknown → still trips; errs safe).
4. **jq simplified (simplicity Q2/Q4).** Dropped the unreachable `location` term
   (a `location` change forces REPLACE → never matches `== ["update"]`) and
   flattened the `def` to a single `or`-select. `location`/`datacenter` are now
   documented as ForceNew-replace handled by `resource_deletes`.
5. **Type-scope breadth + singleton fixture (architecture P2-1/P2-2).** The
   `type=="hcloud_server"` select also covers `hcloud_server.git_data`
   (`git-data.tf`) — noted as deliberate defense-in-depth. Added a singleton-address
   fixture (`hcloud_server.web`, the live pre-migration shape) alongside the
   `for_each` (`["web-1"]`) shapes.

### New considerations discovered
- The allowlist of 3 named attributes is itself a second-order proxy for
  "reboot-forcing"; it silently narrows as `server.tf`'s attribute surface grows
  (new Sharp Edge + CODEOWNERS coupling recommendation).
- A `reboot_updates` trip is *persistent* until the operator applies — the same
  "pending operator-consumed change wedges the per-PR path" class as the #5887
  `moved`-block wedge (new Sharp Edge).

## Overview

The web-platform `terraform apply` destroy-guard
(`tests/scripts/lib/destroy-guard-filter-web-platform.jq`, consumed inline by
`apply-web-platform-infra.yml`) counts **`delete`** actions
(`resource_deletes`) plus nested-block **removals** across 5 Cloudflare
resource types (`nested_deletes`). It is **structurally blind to reboot-forcing
in-place `update` actions on `hcloud_server.*`**: a change to
`placement_group_id` or `server_type` powers-off / reboots the running prod
host with **0 destroys** and **0 nested-block removals**, so `destroy_count`
stays 0 and the unattended per-PR apply proceeds without an `[ack-destroy]`.

This plan adds a **third counter** — `reboot_updates` — to the same
path-specific filter, wired into the same `[ack-destroy]` gate, so a planned
reboot-forcing in-place update on `hcloud_server.*` blocks the unattended apply
unless the merge commit explicitly acknowledges it. It closes the residual that
**ADR-068 §Amendment (2026-07-02, #5877/#5887), lines 522-525** explicitly
deferred to #5911.

This is a CI/tooling change only: one `.jq` filter, one workflow bash block, one
bash test + synthesized fixtures, one ADR amendment. No app code, no DB, no UI,
no new infrastructure.

## Premise Validation

All cited references were verified against `origin/main` / live repo state at
plan time:

- **Issue #5911** — OPEN, title `arch: reboot-aware destroy-guard for in-place
  update on hcloud_server.* (P2 follow-up from #5887)`;
  `closedByPullRequestsReferences: []`. Not stale. This plan is a *build*, not a
  *fix-of-existing*.
- **ADR-068 §Amendment (2026-07-02, #5877/#5887)** — present at lines 501-525 of
  `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`.
  Lines 522-525 read: *"the destroy-guard remains blind to reboot-forcing
  in-place `update` on `hcloud_server.*` — a reboot-aware [guard] … close;
  tracked in #5911."* This plan is the sanctioned mechanism, **not** an
  ADR-rejected alternative.
- **`MOVED_OPERATOR_CONSUMED` / `terraform-target-parity.test.ts`** — present
  (#5887). Confirmed to be a **review-surfacing accounting check** (forces
  conscious classification of a new `moved` base) — it structurally cannot stop
  an author from making it pass the *wrong* way. This plan adds the **mechanical
  interlock** that accounting check does not provide.
- **Dependency-chain reachability (the load-bearing premise)** —
  `hcloud_firewall_attachment.web` (`firewall.tf:91-93`,
  `server_ids = [for h in hcloud_server.web : h.id]`) IS in the per-PR
  `-target=` allow-list (`apply-web-platform-infra.yml:351`). It depends on
  `hcloud_server.web`, so the target-scoped plan pulls `hcloud_server.web` into
  its graph — **confirmed empirically**: the captured real-baseline fixture
  (`tests/scripts/fixtures/tfplan-web-platform-real-baseline.json`) contains
  `hcloud_server.web` in `resource_changes` with `actions: ["no-op"]`,
  `server_type: "cx33"`, `placement_group_id: 0`. A future `server_type` /
  `placement_group_id` change flips that `no-op` to `["update"]` and it appears
  in `terraform show -json` where the guard reads. **The guard can see it.**

Own-capability check (`hr-verify-repo-capability-claim-before-assert`): I read
the filter, the workflow bash (lines 360-395), the counter test, the
regex-parity test, and the parity test before asserting what each does.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| Guard is "blind to reboot-forcing in-place `update`" | TRUE. `resource_deletes` = `index("delete")`; the 5 nested clauses select only Cloudflare types. `hcloud_server` `["update"]` matches none. | Add `reboot_updates` counter selecting `type=="hcloud_server"` + `actions==["update"]` + reboot-attr diff. |
| `location` change is a reboot-forcing gap | PARTLY. `location` (+ `datacenter`) forces a **full REPLACE** → `actions` includes `"delete"` → **already caught by `resource_deletes`** today. Only `placement_group_id` + `server_type` are pure `["update"]` (the true blind spot). | Reboot clause selects **only** `actions==["update"]` (never double-counts a REPLACE) and compares **only** `placement_group_id` + `server_type`. `location`/`datacenter` are NOT compared (dead code under `["update"]` — code-simplicity Q2) and are documented in the filter header + Sharp Edge as ForceNew-replace handled by `resource_deletes`. |
| "extend the web-platform destroy-guard" | The filter emits `{resource_deletes, nested_deletes}`; the workflow bash + the test `_run_gate` read exactly those two keys and sum them. | Add a THIRD key `reboot_updates`; update the workflow bash (read + regex-validate + sum + distinct `::error::`) AND the test `_run_gate` in lockstep (byte-identical mirror invariant). |
| "[ack-destroy]-style acknowledgement" | `[ack-destroy]` regex is pinned across **6 sites** by `test-destroy-guard-regex-parity.sh`. | **Reuse `[ack-destroy]`** (one ack line covers all three counters). Do NOT introduce `[ack-reboot]` (would need a 7th regex-parity site + a second gate for no benefit). |
| Guard covers the reboot risk | Nuance: the guard runs ONLY in the **unattended per-PR** `apply-web-platform-infra.yml`. The operator's **maintenance-window full apply** (where `hcloud_server` changes are intended to land per the `OPERATOR_APPLIED_EXCLUSIONS`) does NOT run this jq gate — it is human-attended (`terraform plan` shows the reboot; operator eyeballs it). | Scope the guard explicitly to the **unattended** path (the dangerous one — no human watching). State this in the plan scope + the ADR amendment so no one expects operator-path coverage. |

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) *false-negative* — a
reboot-forcing `hcloud_server` update slips through the unattended per-PR apply
and power-cycles the single operator's live production web host mid-merge
(downtime, in-flight agent sessions dropped); this is the exact hazard the guard
exists to prevent, and a broken guard = status quo (no *new* harm, but the
protection promised by the PR is absent). Or (b) *false-positive* — the guard
trips on a `no-op`/create/non-reboot update and blocks every legitimate
`apps/web-platform/infra/**` auto-apply until the trip is resolved.

**The friction's "obvious fix" is itself the hazard (architecture P1).** Once a
reboot-forcing `.tf` change merges (destined for the operator maintenance-window
apply), *every subsequent* unattended per-PR plan shows `reboot_updates ≥ 1` and
blocks — the same "pending operator-consumed change wedges the per-PR path" class
as the #5887 `moved`-block wedge. The correct resolution is the **operator
maintenance-window apply** (which clears the pending change), NOT `[ack-destroy]`
on an unrelated PR: because `hcloud_server.web` is transitively in the targeted
plan's dependency subgraph, an ack-through would let the unattended
`terraform apply tfplan` *execute the reboot* — re-introducing the exact hazard
the guard exists to prevent. The `::error::` copy (Phase 3) makes this explicit.

**If this leaks, the user's data is exposed via:** N/A — this change reads only
`terraform show -json` action metadata and resource-attribute *identifiers*
(`placement_group_id`, `server_type`); it writes no secrets and the fixtures are
synthesized (see `cq-test-fixtures-synthesized-only`). The real-baseline fixture
is already redaction-gated by the counter test's documented procedure.

**Brand-survival threshold:** `single-user incident`. The guarded event
(unattended prod reboot of the one production host) is a single-user incident,
and the guard's failure mode is precisely "green check on a broken state" — the
class the plan-skill Sharp Edges repeatedly flag as requiring
invariant-not-proxy discipline and the flow-analysis (spec-flow) +
`user-impact-reviewer` lenses. CPO sign-off is required at plan time before
`/work`; `user-impact-reviewer` runs at review time.

## Threat Model & Scope

**In scope (the unattended path):** `apply-web-platform-infra.yml`'s
target-scoped `terraform plan` → `terraform show -json` → `jq` destroy-guard.
`hcloud_server.web` reaches this plan as a dependency of the targeted
`hcloud_firewall_attachment.web`. If a merged PR changes `var.web_hosts`
(`server_type`, `location`) or the placement-group wiring such that
`hcloud_server.web["web-1"]` gets a pending in-place `update`, the guard must
block it absent `[ack-destroy]`.

**Out of scope (deliberately):**
- The operator's **maintenance-window full apply** (no `-target`, run manually /
  via the drift path) — human-attended; does not invoke this jq gate.
- **REPLACE** actions (`location` change, host recreate) — already counted by
  `resource_deletes`; the reboot clause must NOT double-count them.
- **CREATE** of `hcloud_server.web["web-2"]` (adding the 2nd host) — a legit new
  host, `actions==["create"]`, NOT a reboot; the reboot clause selects only
  `["update"]` so it is correctly ignored (invariant, not "any hcloud_server
  change").
- A *reverse-direction* `-target` scope guard for web-platform (there is a
  `test-destroy-guard-sentry-scope-guard.sh` but no web-platform equivalent).
  This plan adds a *filter* clause for a dependency-reachable type — it does NOT
  extend the `-target=` allow-list, so no scope-guard suite applies. (Verified:
  only the sentry scope guard exists.)

## Implementation Phases

Follow `cq-write-failing-tests-before` — RED fixtures + assertions before GREEN
filter/workflow edits.

### Phase 0 — Preconditions (verify, don't assume)
1. `git grep -ln 'destroy-guard\|-target=\|hcloud' tests/ scripts/ .github/` to
   confirm the artifact set to sweep (filter, counter test, regex-parity,
   parity test, workflow). Confirm **no** web-platform scope-guard suite exists.
2. Read the 3 `.c4` model files
   (`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`)
   for the C4-completeness enumeration (used by the ADR gate below).
3. Confirm `jq` array equality `.change.actions == ["update"]` selects only pure
   in-place updates on a synthesized fixture (research confirms stable across jq
   1.6/1.7/1.8; verify on the installed `jq`).
4. **Confirm the provider ForceNew map** against the pinned
   `hetznercloud/hcloud 1.63.0` (`apps/web-platform/infra/.terraform.lock.hcl`):
   `placement_group_id` + `server_type` are in-place `["update"]` (power-off
   reboot), `location` + `datacenter` are ForceNew → REPLACE. The
   best-practices-researcher could not fetch the registry schema; verify via the
   provider source (`ForceNew` flags in the `hcloud_server` schema) OR the
   `server.tf:37-39` codebase comment ("an in-place reboot, NOT a replace") — the
   latter is the operator's own confirmation for `placement_group_id`.
5. Run the Open Code-Review Overlap query (below) now that Files lists exist.

### Phase 1 — RED: fixtures + failing assertions
Create synthesized fixtures under `tests/scripts/fixtures/`. Addresses are
mixed **singleton** (`hcloud_server.web` — the live pre-migration shape today,
`placement-group.tf` `moved` not yet operator-consumed) and **for_each**
(`["web-1"]`/`["web-2"]` — post-#5877) so the RED set proves the type-scoped
select on BOTH shapes (architecture P2-2):
- `tfplan-hcloud-server-placement-group-update.json` — SINGLETON
  `hcloud_server.web`, `actions:["update"]`, `before.placement_group_id:0`,
  `after.placement_group_id:12345` (start value `0` matches the captured
  baseline). Expect `rdel=0 ndel=0 rupd=1`.
- `tfplan-hcloud-server-placement-group-after-unknown.json` — **(spec-flow P1-2,
  the realistic serialization)** `hcloud_server.web["web-1"]`, `actions:["update"]`,
  `before.placement_group_id:0`, `placement_group_id` ABSENT from `.change.after`
  and present in `.change.after_unknown` (because
  `placement_group_id = hcloud_placement_group.web_spread.id` is a resource
  reference resolved same-plan). Expect `rupd=1` — a **pinned** assertion that
  `0 != null` still trips (errs SAFE: an unknown `after` never yields a missed
  reboot).
- `tfplan-hcloud-server-type-update.json` — `hcloud_server.web["web-1"]`,
  `actions:["update"]`, `before.server_type:"cx33"` + `before.labels:{v:"1"}`,
  `after.server_type:"cx43"` + `after.labels:{v:"2"}` (multi-attr update, folds
  spec-flow P2-2 — pins that detection keys off the reboot-attr diff even when a
  non-reboot attr also changes). Expect `rupd=1`.
- `tfplan-hcloud-server-location-replace.json` — `actions:["delete","create"]`,
  `before.location:"hel1"`, `after.location:"fsn1"`. Expect `rdel=1 rupd=0`
  (REPLACE counted by `resource_deletes`, **NOT** double-counted — the
  invariant-not-proxy anchor; a live-host `location` change is a prod *destroy*,
  correctly blocked by `resource_deletes` without ack).
- `tfplan-hcloud-server-noop-attr-update.json` — `actions:["update"]` changing a
  NON-reboot attr only (e.g. `labels`), reboot attrs unchanged. Expect `rupd=0`
  (proves the clause detects the reboot-forcing **attribute diff**, not merely
  "hcloud_server has an update action" — the proxy trap).
- `tfplan-hcloud-server-create.json` — `hcloud_server.web["web-2"]`,
  `actions:["create"]`. Expect `rupd=0` (2nd-host add is not a reboot).

Add tests T13-T20 to `test-destroy-guard-counter-web-platform.sh` asserting the
above via the (extended) `_run_gate` tuple, plus an `[ack-destroy]` allow-through
test on the placement-group fixture (`rc=0`). Extend `_run_gate`'s return tuple
from `rdel:ndel:dcount:rc` → `rdel:ndel:rupd:dcount:rc` and update T1-T12
expected strings mechanically (existing fixtures have `rupd=0`, so
`"0:1:1:1"` → `"0:1:0:1:1"`, etc.). Run → RED (filter has no `reboot_updates`).

### Phase 2 — GREEN: filter clause
Extend `tests/scripts/lib/destroy-guard-filter-web-platform.jq`. Add a
`reboot_updates` key — flattened to a single `or`-select (no `def`, no `map/add`,
no `// null`) per code-simplicity review; the magnitude is discarded by the
outer `length`, so only "any reboot attr changed?" matters, and jq's
`.absent_key` already yields `null` so `0 != null` trips while `null != null` is
false:
```jq
  # 6th surface (#5911): hcloud_server.* reboot-forcing IN-PLACE update.
  # placement_group_id / server_type change → power-off reboot of the RUNNING
  # host, ZERO destroys → invisible to resource_deletes + the 5 Cloudflare
  # clauses. TYPE-scoped select (not address) INTENTIONALLY covers BOTH
  # hcloud_server.web AND hcloud_server.git_data (git-data.tf) — git_data is not
  # target-reachable today but a git_data reboot (holds the LUKS git volume) is
  # MORE disruptive, so defense-in-depth. `location`/`datacenter` force a full
  # REPLACE (actions include "delete") → already caught by resource_deletes and
  # NOT compared here (a REPLACE never matches actions==["update"], so comparing
  # them would be dead code). Selecting ONLY actions==["update"] never
  # double-counts a REPLACE, never false-fires on a CREATE (web-2 add), and never
  # false-fires on a `moved` re-address (serializes as no-op). An `after` value
  # that is UNKNOWN at plan time (placement_group_id is a resource reference →
  # serialized into change.after_unknown, change.after.<attr>=null) still trips
  # (before != null) — errs SAFE (availability friction, never a missed reboot).
  reboot_updates: (
    [ .resource_changes[]?
      | select(.type == "hcloud_server")
      | select(.change.actions == ["update"])
      | select(.change.before.placement_group_id != .change.after.placement_group_id
            or .change.before.server_type       != .change.after.server_type) ]
    | length
  )
```
Update the filter's top header comment block to document the 6th surface + the
pure-`["update"]` selection rationale + the type-scope breadth. Run counter test
→ GREEN.

### Phase 3 — GREEN: workflow bash (byte-identical mirror)
Edit `apply-web-platform-infra.yml` destroy-guard step (lines ~372-392):
- Add `reboot_updates=$(echo "$counts" | jq -r '.reboot_updates')`.
- Extend the numeric-regex parse-guard to cover `reboot_updates`.
- `destroy_count=$((resource_deletes + nested_deletes + reboot_updates))`.
- Extend the `::error::` message to name the reboot component AND steer to the
  correct resolution (architecture P1 — the override is dangerous here):
  `… (${resource_deletes} resource-level delete(s) + ${nested_deletes}
  nested-block removal(s) + ${reboot_updates} reboot-forcing in-place update(s)
  on hcloud_server.*)`. When `reboot_updates > 0`, add a second `::error::`
  line: `A reboot-forcing hcloud_server.* update is planned. Resolve via the
  operator maintenance-window apply — do NOT add [ack-destroy] to unblock this
  unattended apply: the host update is transitively in the saved plan, so
  ack-through would REBOOT prod unattended.`
- Keep the `[ack-destroy]` regex + gate unchanged (reuse). NOTE the ack STILL
  works (per the issue's "[ack-destroy]-style" requirement) — it is an emergency
  override, not the normal reboot resolution; the copy above makes that explicit.
Update the counter test's `_run_gate` to mirror this bash **exactly** (it is
documented as byte-identical to the workflow). Re-run counter test → GREEN.

### Phase 4 — ADR + C4 deliverable
- Amend ADR-068 §Amendment (2026-07-02, #5877/#5887) lines 522-525: flip the
  residual note from *"deferred … tracked in #5911"* to *"closed by PR #<n>
  (reboot-aware `reboot_updates` counter in the web-platform destroy-guard;
  covers the unattended per-PR apply path)."*
- `### C4 views`: enumerate — the actors/systems this change touches are
  Hetzner (already modeled via the host), the CI apply pipeline (internal), and
  the operator/author (already modeled). No **new** external human actor, no new
  external system/vendor, no new container/data-store, no changed
  access-relationship. Cite the three `.c4` files read in Phase 0 → conclude
  "no C4 impact" ONLY after the enumeration (per the C4 completeness mandate).

### Phase 5 — Full-suite exit gate
Run `test-destroy-guard-counter-web-platform.sh`, `test-destroy-guard-regex-parity.sh`
(unchanged — no new `[ack-destroy]` site), `terraform-target-parity.test.ts`
(unchanged — no `-target=` list edit), and the repo `test-all.sh` orphan-suite
sweep.

## Files to Edit
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq` — add
  `hcloud_reboot_forcing_diff` def + `reboot_updates` output key + header doc.
- `.github/workflows/apply-web-platform-infra.yml` — read + regex-validate + sum
  `reboot_updates`; extend `::error::` message.
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` — extend `_run_gate`
  tuple; update T1-T12 expected strings; add T13-T19 + ack test.
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`
  — flip the residual note to closed.

## Files to Create
- `tests/scripts/fixtures/tfplan-hcloud-server-placement-group-update.json` (singleton addr)
- `tests/scripts/fixtures/tfplan-hcloud-server-placement-group-after-unknown.json` (spec-flow P1-2)
- `tests/scripts/fixtures/tfplan-hcloud-server-type-update.json` (multi-attr)
- `tests/scripts/fixtures/tfplan-hcloud-server-location-replace.json`
- `tests/scripts/fixtures/tfplan-hcloud-server-noop-attr-update.json`
- `tests/scripts/fixtures/tfplan-hcloud-server-create.json`

## Acceptance Criteria

### Pre-merge (PR)
- [x] `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` exits 0 with
      all T1-T20 passing; the placement-group + server-type fixtures return
      `rupd=1` and `rc=1` without ack.
- [x] The `after-unknown` placement-group fixture returns `rupd=1` (pins that a
      resource-reference `placement_group_id` whose value is unknown at plan time
      — `after.placement_group_id` null, value in `after_unknown` — still trips;
      errs safe).
- [x] The location-REPLACE fixture returns `rdel=1 rupd=0` (no double-count) and
      the no-op-attr + create fixtures return `rupd=0` (attribute-specific,
      lifecycle-aware — the invariant, not the "any hcloud_server change" proxy).
- [x] The placement-group fixture + a `[ack-destroy]`-on-own-line message returns
      `rc=0` (ack allows the reboot through).
- [x] `jq -f tests/scripts/lib/destroy-guard-filter-web-platform.jq <
      tests/scripts/fixtures/tfplan-web-platform-real-baseline.json` returns
      `reboot_updates: 0` (T10 baseline anchor stays green — the baseline's
      `hcloud_server.web` is `no-op`).
- [x] The workflow bash `destroy_count` sum includes `reboot_updates` and its
      numeric-regex parse-guard covers the new counter (grep the step body).
- [x] `bash tests/scripts/test-destroy-guard-regex-parity.sh` exits 0 (still 6
      sites; `[ack-destroy]` reused, not a new token).
- [x] `bun test plugins/soleur/test/terraform-target-parity.test.ts` exits 0
      (unchanged — no `-target=` allow-list edit).
- [x] ADR-068 §Amendment residual note flipped to closed; `### C4 views`
      concludes no-C4-impact with the external-actor/system enumeration cited.

### Post-merge (operator)
- [x] None. This is a CI-tooling change auto-verified by the test suite; the
      `apply-web-platform-infra.yml` workflow re-fires on the filter path
      (`on.push.paths` includes the `.jq`) against `main`'s captured baseline,
      which is `reboot_updates: 0` — no reboot, no ack needed.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-068 §Amendment (2026-07-02, #5877/#5887)** in place (this is
implementing an already-recorded decision, not a new one): flip lines 522-525's
deferred-residual note to "closed by PR #<n>". The amendment text MUST state the
resolution boundary (architecture P1): a `reboot_updates` trip on the unattended
per-PR path is resolved by the **operator maintenance-window apply**, not by
`[ack-destroy]` — ack-through would execute the transitively-included reboot
unattended. No new ADR number.

### C4 views
No C4 impact — verified by reading all three
`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4` files
and enumerating: external human actors (operator/author — already modeled),
external systems/vendors (Hetzner — already modeled via the host; no new
inbound/outbound edge), containers/data-stores (none new), access-relationships
(none changed — a CI-internal guard adds no actor↔surface edge). A destroy-guard
filter clause is an internal CI check with no rendered-topology element.

### Sequencing
Single atomic PR — the filter, workflow, test, and ADR amendment ship together.

## Observability

```yaml
liveness_signal:
  what: apply-web-platform-infra.yml "Terraform plan (allow-list…)" step exit status
  cadence: on every merge touching apps/web-platform/infra/** or the filter .jq
  alert_target: GitHub Actions run status (red job = operator-visible in Actions tab + the existing apply-failure signal)
  configured_in: .github/workflows/apply-web-platform-infra.yml
error_reporting:
  destination: GitHub Actions ::error:: annotation on the workflow run (names the reboot_updates count)
  fail_loud: true  # non-zero exit halts the apply job; no silent pass
failure_modes:
  - mode: reboot-forcing hcloud_server update planned without [ack-destroy]
    detection: reboot_updates > 0 in the jq counter output
    alert_route: ::error:: annotation + job failure (apply blocked)
  - mode: jq counter emits non-numeric (filter regression)
    detection: numeric-regex parse-guard on reboot_updates
    alert_route: ::error:: "destroy-guard counter parse failed" + exit 1
logs:
  where: GitHub Actions run logs for apply-web-platform-infra.yml
  retention: GitHub default (90 days)
discoverability_test:
  command: bash tests/scripts/test-destroy-guard-counter-web-platform.sh
  expected_output: "=== N passed, 0 failed ==="
```

## Domain Review

**Domains relevant:** Engineering (infra/CI tooling).

### Engineering (infra)
**Status:** reviewed (plan author).
**Assessment:** Pure CI-guard extension over an existing infra apply pipeline.
No new provisioning (`hcloud_server.web` already exists), no new secret/vendor —
Phase 2.8 IaC-routing gate does not fire (no manual provisioning prescribed, no
new terraform root; `ssh` mentions are descriptive of the existing operator path
or explicitly ssh-free). `terraform-architect` consulted at deepen-plan for the
jq-semantics + `-target` dependency-apply behavior. GDPR gate (2.7) does not
fire — no regulated-data surface, no schema/auth/API/`.sql`, no LLM-on-session-
data; fixtures are synthesized.

### Product/UX Gate
Not relevant — no UI-surface file in Files-to-Create/Edit (only `.jq`, `.yml`,
`.sh`, `.json` fixtures, `.md`). NONE.

## Test Scenarios
See Phase 1 fixtures + T13-T19. Key negative/positive matrix: placement_group_id
update (trip), server_type update (trip), location REPLACE (counted by
resource_deletes, NOT reboot clause), no-op-attr update (pass), create (pass),
ack-through (pass), baseline no-op (pass).

## Open Code-Review Overlap
Run at Phase 0: `gh issue list --label code-review --state open --json
number,title,body --limit 200 > /tmp/rev.json`, then for each Files-to-Edit path
`jq -r --arg path "<p>" '.[]|select(.body//""|contains($path))|"#\(.number): \(.title)"' /tmp/rev.json`
over `destroy-guard-filter-web-platform.jq`,
`test-destroy-guard-counter-web-platform.sh`, `apply-web-platform-infra.yml`.
Disposition each hit fold-in / acknowledge / defer. Recorded: **None** in
plan-time file listing (re-confirm at /work Phase 0).

## Sharp Edges
- The reboot clause MUST select `actions == ["update"]` (exact equality), NOT
  `index("update")`. A REPLACE serializes as `["delete","create"]` (or
  `["create","delete"]`) — already counted by `resource_deletes`; `index("update")`
  would be false on a REPLACE anyway, but exact-`["update"]` also guarantees a
  future `["update","..."]` shape can't silently double-count with the delete
  counter. Detect the reboot-forcing **attribute diff**, not the mere presence
  of an update action (the proxy-vs-invariant trap: a `labels`-only update is
  `["update"]` but not a reboot).
- The test `_run_gate` is documented as **byte-identical** to the workflow bash.
  Editing one without the other silently diverges the gate from its test.
  Change both in the same commit; the tuple extension
  (`rdel:ndel:rupd:dcount:rc`) touches all 12 existing expected strings.
- Reuse `[ack-destroy]`; do NOT add `[ack-reboot]`. A new token would need a 7th
  entry in `test-destroy-guard-regex-parity.sh`'s `EXPECTED_SITES` and a second
  gate branch, for zero operator benefit — one ack line already means "I
  acknowledge a disruptive planned change."
- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the
  threshold fails `deepen-plan` Phase 4.6. It is filled above
  (`single-user incident`).
- Do not extend the `-target=` allow-list to add `hcloud_server.web` — that is
  the exact reboot-enabling anti-fix the #5887 parity check warns against
  (`MOVED_OPERATOR_CONSUMED`). This plan adds a *filter clause* for a
  dependency-reachable type; the allow-list is untouched.
- **The 3-attribute allowlist is itself a second-order proxy for "reboot-forcing"
  (spec-flow P1-1).** It has no mechanical coupling to `server.tf`'s actual
  attribute surface — if a future PR adds a reboot/power-cycle attribute
  (`rescue`, `iso`) to `hcloud_server.web`, or a provider upgrade flips a
  currently-ForceNew attr to in-place, the guard silently returns `rupd=0` (the
  green-on-broken class). Mitigations in this plan: (a) the filter header
  documents `rescue`/`iso` as known-uncovered (they take effect on next power
  cycle, not an immediate provider reboot today) and `location`/`datacenter` as
  ForceNew siblings caught by `resource_deletes`; (b) add a CODEOWNERS note (or a
  1-line comment on both `server.tf` and the `.jq`) that any new `hcloud_server`
  argument must be consciously classified reboot/non-reboot. Do NOT build a
  heavyweight attribute-parity test — the CODEOWNERS coupling is proportionate.
- **`[ack-destroy]` on a `reboot_updates` trip is an emergency override, not the
  normal fix (architecture P1).** Ack-through executes the transitively-included
  reboot on the unattended apply. The `::error::` copy says so; reviewers/authors
  must route a real reboot to the operator maintenance-window apply.
- **A `moved` re-address does NOT false-fire the reboot clause.** A `moved` block
  serializes as `no-op` (or the targeted plan is *rejected* pre-guard with "Moved
  resource instances excluded by targeting", per `terraform-target-parity.test.ts`),
  and `no-op != ["update"]`, so the clause skips it. The reboot guard and the
  #5887 `moved` accounting check are orthogonal.
- **The `type=="hcloud_server"` select is intentionally address-agnostic** — it
  covers `hcloud_server.web` (all `for_each` keys + the live singleton) AND
  `hcloud_server.git_data`. `git_data` is not `-target`-reachable today, but the
  breadth is deliberate defense-in-depth (a `git_data` reboot is more disruptive).

### Research Insights

**terraform `-target` dependency-emit (LOAD-BEARING, best-practices-researcher):**
HashiCorp's [Target resources tutorial](https://developer.hashicorp.com/terraform/tutorials/state/resource-targeting)
confirms `terraform plan -target=A` "extends the selection to include all other
objects that those selections depend on" and applies their *real* pending
changes (the tutorial shows dependency `random_pet` instances updated when only a
downstream object was targeted). So a pending `["update"]` on `hcloud_server.web`
(dependency of the targeted `hcloud_firewall_attachment.web`) DOES surface in the
CI `terraform show -json` — the guard is not dormant. The captured baseline
(`hcloud_server.web` present as `["no-op"]`) is the empirical confirmation.

**JSON plan shape (terraform internals/json-format):** pure in-place =
`actions:["update"]`; force-replace = `actions` containing `"delete"`
(`["delete","create"]` or `["create","delete"]`) — the docs note the ordering is
deliberately scannable for `"delete"`, which is exactly what `resource_deletes`
does. `.change.before`/`.change.after` carry `placement_group_id`, `server_type`,
`location` as top-level keys; unknown same-plan references land in
`.change.after_unknown`.

**jq array-equality:** `.change.actions == ["update"]` is order-sensitive and
stable across jq 1.6/1.7/1.8 — a safe selector for pure in-place updates.

**Provider pin:** `hetznercloud/hcloud 1.63.0` (constraint `~> 1.49`). Confirm
the ForceNew map at Phase 0 step 4.
