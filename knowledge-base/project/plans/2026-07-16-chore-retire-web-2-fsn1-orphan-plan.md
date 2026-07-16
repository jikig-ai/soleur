---
title: "chore: retire soleur-web-2 (fsn1 orphan)"
date: 2026-07-16
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: [6538, 6463]
related: [6393, 6453, 6457, 6459, 6460, 6570, 6571]
brainstorm: knowledge-base/project/brainstorms/2026-07-16-web2-retire-fsn1-orphan-brainstorm.md
spec: knowledge-base/project/specs/feat-6538-web2-fsn1-orphan/spec.md
branch: feat-6538-web2-fsn1-orphan
pr: 6568
---

# chore: retire soleur-web-2 (fsn1 orphan)

## Overview

Retire `soleur-web-2`: remove its `var.web_hosts` entry, destroy the host + its
empty volume through a **new, guarded `web-2-retire` dispatch**, and correct the
Art. 30 register and expense ledger that describe it inaccurately.

Decision is operator-confirmed and unanimous (CTO, platform-strategist, CPO, CFO;
CLO indifferent). **Do not re-litigate** — the spec's Non-Goals record why
`cpx32@fsn1` (+€27/mo) and `cx33@hel1` (reverts PR #6393) were rejected. The
deciding argument is topological, not cost: `placement_group_id` is create-time
only (`ignore_changes`), so a host born in fsn1 can never join `web_spread`.
web-2 must be destroyed and re-born to reach the operator's active-active target
regardless.

## Research Reconciliation — Spec vs. Codebase

The spec's TR1 named the guard shape as the load-bearing design question. Plan-time
measurement found a **second, larger** one that inverts the phase order.

| Spec/brainstorm claim | Measured reality (2026-07-16) | Plan response |
|---|---|---|
| "`hcloud_server.web` is EXCLUDED from push-apply, so removing web-2 from `var.web_hosts` will NOT destroy it on merge." | **FALSE — measured.** `terraform plan` over the exact push-apply target scope with web-2 removed returns `Plan: 0 to add, 1 to change, 1 to destroy` → `hcloud_server.web["web-2"] will be destroyed (because key ["web-2"] is not in for_each map)`. `-target` is transitive: `hcloud_firewall_attachment.web` (line 389 of the push-apply target list) has `server_ids = [for h in hcloud_server.web : h.id]`, dragging `hcloud_server.web` into the merge graph. | **Phase order inverted.** The var removal must NOT reach a live push-apply. Merge carries `[skip-web-platform-apply]`; the destroy runs via the guarded dispatch. See §Sequencing. |
| (implicit) "a destroy on merge would at least be complete" | **FALSE — measured.** Only **1** destroy: the *server*. `hcloud_volume.workspaces["web-2"]`, `hcloud_server_network.web["web-2"]`, and `hcloud_volume_attachment.workspaces["web-2"]` are NOT in the firewall attachment's dependency graph. An `[ack-destroy]` merge would strand them in state **and keep billing the volume**. | The retire dispatch `-target`s **all four** addresses explicitly; the gate asserts the destroy set equals exactly that set. |
| Baseline drift unknown | `terraform plan` on the push-apply scope, config unmodified: **"No changes. Your infrastructure matches the configuration."** | No pre-existing drift to disentangle. The 1-destroy/1-change delta is attributable solely to the var removal. |
| Volume is empty/disposable (ADR-068 §1) | Holds. Volume `soleur-web-platform-data-web-2` (id `106374503`, fsn1, 20 GB, created 2026-07-15). ADR-068 §1: worktrees host-local; GitHub is durable rehydration. ADR-068's deep-readiness amendment defines `populated` specifically to "reject a fresh/empty volume". | TR4 permits **exactly one** volume destroy, asserted by the gate. |
| Art. 30 register describes web-2 | Holds. `article-30-register.md` §(e): *"a second web host **web-2** (CX33, `hel1`)"* — live is **fsn1** since #6393. | Phase 4 strikes the clause (CLO: §5(2) accuracy defect). |
| `grok-dogfood` is not born | **FALSE — measured.** `soleur-grok-dogfood` (cx33, hel1) created 2026-07-16 and live, occupying 1 of 5 capped slots; ledger books it `approved-not-billing / "Not born"`. | **Out of scope** (NG6) — routed to #6460. Named here so the next planner does not re-discover it. |

**Measurement method** (re-runnable): the Sharp-Edges triplet — raw `AWS_*` exports
from Doppler `prd_terraform` (R2 backend), `terraform init -input=false`, then
`doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan
-lock=false -target=hcloud_firewall.web -target=hcloud_firewall_attachment.web`.
The `var.web_hosts` edit was made in the working tree, measured, and reverted
(`git status` clean).

## Sequencing (load-bearing — derived from the measurement)

There is **no ordering that avoids a wedge window**, because config (merge) and
state (dispatch) necessarily change at different moments. Both candidate orders
fail *safe* (they HALT, they do not silently destroy), so the choice is which HALT
to accept and how long to hold it open.

| Order | Window behaviour | Verdict |
|---|---|---|
| Merge var removal plainly, then dispatch | push-apply plans `1 to destroy` → destroy-guard HALTs **every subsequent merge**, not just this PR's | **Reject** — repo-wide wedge, the #6393 class |
| Merge with `[ack-destroy]`, then dispatch | Unguarded **partial** destroy (server only; volume + attachments stranded, still billing) authorized by a **commit trailer** | **Reject** — violates `hr-menu-option-ack-not-prod-write-auth` |
| Destroy first (config still declares web-2), then merge | State loses web-2, config keeps it → next push-apply plans a **CREATE** → create-HALT fires ("EVERY subsequent merge HALTs here") | **Reject** — same wedge, mirrored |
| **Merge with `[skip-web-platform-apply]`, then dispatch `web-2-retire`** | Apply skipped at merge (no halt, no partial destroy). Window opens until the dispatch completes; a concurrent merge in the window HALTs on `destroy_count=1` and is unwedged by the documented `[skip-web-platform-apply]` token. | **Chosen** |

`[skip-web-platform-apply]` is the workflow's own documented kill switch
(*"include on its own line in the merge commit message to skip auto-apply for that
merge"*), anchored to its own line by the same regex posture as `[ack-destroy]`.

**Window-minimisation:** the dispatch is a destructive prod write, so
`hr-menu-option-ack-not-prod-write-auth` requires showing the exact command and
waiting for **explicit per-command go-ahead** — it may NOT be auto-fired by `/ship`.
This is *not* a deferred operator action (`hr-never-defer-operator-actions`): the
agent runs the command in-session immediately after the go-ahead. Phase 8 is a
confirm-then-run, never a post-merge checklist handed to the operator.

**Precondition (Phase 0.3):** `workflow_dispatch` input enums are validated against
the workflow definition; a new `apply_target=web-2-retire` value must be on the
default branch before it can be dispatched (`hr-github-api-endpoints-with-enum` —
"exact format matching … handle HTTP 422"). This is *why* the enum ships in the
same PR and the dispatch fires post-merge. Verify, do not assume.

## User-Brand Impact

Carried forward verbatim from the brainstorm (plan Phase 2.6 prefers carry-forward
over re-authoring).

- **If this lands broken, the user experiences:** nothing directly — web-2 has never
  served, has no LB, and its volume is empty. The reachable failure is the
  *inverse*: an incomplete retire that strands `hcloud_volume.workspaces["web-2"]`
  or mis-scopes the destroy onto **web-1**, which IS the live origin (`dns.tf` A
  record; the only tunnel connector). A web-1 touch is a full prod outage.
- **If this leaks, the user's data is exposed via:** n/a — the volume is empty and
  never held a worktree; all candidate DCs are EU (CLO: residency neutral).
- **Brand-survival threshold:** `single-user incident` — justified by the blast
  radius of the destroy path, not by web-2's own value.

**The inversion matters.** The dark standby is not itself a user risk; the risk is
*believing* it is a standby. ADR-068's amendment calls a bare web-2's `200/status:ok`
**"a routing lie"**, and §1 notes a request round-robined to it *"hits an empty
workspace — a single-user (workspace-gone) incident."* Retiring deletes that surface.

`requires_cpo_signoff: true` — satisfied by the brainstorm's CPO assessment
(carry-forward). `user-impact-reviewer` fires at review time.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Finance (carried forward from the
brainstorm's `## Domain Assessments`; no fresh sweep — all four leaders assessed the
final scope, which has not changed).

### Engineering (CTO + platform-strategist)

**Status:** reviewed
**Assessment:** Retire; rank C ≫ A > B. Confirmed `hcloud_server.web` is outside the
push-apply allow-list *as a resource*, but see §Research Reconciliation — the
firewall attachment's transitive pull reintroduces it. No €0 middle option for
telemetry: `ignore_changes = [user_data]` means only a recreate re-runs cloud-init
and SSH is barred (`hr-no-ssh-fallback-in-runbooks`). Placement group is create-time
only → web-2 can never join → retire is forced by the target topology.

### Product (CPO)

**Status:** reviewed
**Assessment:** All three options are user-invisible today — that is the finding, not
a caveat. Fixing web-2 moves #6459 forward by zero; its blocker is `git-data`, unborn
on a type orderable in 0/3 EU DCs. Re-create at epic start with better information.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Legally indifferent between options; residency is neutral (all EU).
Destroying an empty volume that never held user data carries no retention/Art. 17/DSAR
obligation. **One mandatory deliverable regardless of option:** the Art. 30 register is
factually wrong about web-2 (§5(2) accuracy defect introduced when #6393 moved it
without amending the register).

### Finance (CFO)

**Status:** reviewed
**Assessment:** Retire. Option A is +47% of all Hetzner spend for a capability gated
behind a host the ledger itself flags as a *"PHANTOM ROW … this host has NEVER existed"*.
Ledger drift must be fixed regardless of option (Phase 5).

### Brainstorm-recommended specialists

None beyond the four leaders above. Product/UX Gate: **NONE** — the mechanical
UI-surface scan over `## Files to Edit` matches no path in
`ui-surface-terms.md` (all edits are `*.tf`, `*.yml`, `*.sh`, `knowledge-base/**`).
No `.pen` required (`wg-ui-feature-requires-pen-wireframe` not triggered).

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/variables.tf` — remove the `"web-2"` key from
  `var.web_hosts` and its now-obsolete cross-DC rationale comment.
- No new resources, providers, or variables. No new secrets. Nothing to provision.

### Apply path

**(c) scoped, guarded `workflow_dispatch`** — a new `apply_target=web-2-retire` job in
`.github/workflows/apply-web-platform-infra.yml`. Not cloud-init, not bootstrap: the
change is a *destroy*. Blast radius is confined by the gate's exact-equality allow-set
(§TR1/TR2). Expected downtime: **zero** — web-2 serves no traffic and holds no LB
weight (no LB exists).

### Distinctness / drift safeguards

- Merge carries `[skip-web-platform-apply]` so the merge-apply cannot act on the
  orphaned instance (see §Sequencing).
- Post-dispatch, config == state == cloud; the drift detector's next run is the
  independent confirmation.
- `lifecycle.ignore_changes = [user_data, ssh_keys, image, placement_group_id]` on
  `hcloud_server.web` is untouched.

### Vendor-tier reality check

N/A — a destroy consumes no quota. Retiring **frees** 1 of the 5 capped slots
(`GET /v1/limits` → 404; no API self-serve), which is the enabling step for #6570.

## Observability

```yaml
liveness_signal:
  what: "apply-web-platform-infra.yml `web-2-retire` job conclusion + the drift detector's next scheduled run (0 6,18 * * *)"
  cadence: "once (dispatch) + 12h (drift detector)"
  alert_target: "GitHub Actions run status; drift detector auto-files an issue on divergence"
  configured_in: ".github/workflows/apply-web-platform-infra.yml"
error_reporting:
  destination: "GitHub Actions job failure (::error:: annotations from the gate lib)"
  fail_loud: true
failure_modes:
  - mode: "Gate mis-scopes and the plan touches web-1"
    detection: "gate lib asserts out_of_scope==0 against an exact-equality allow-set, from the SAVED plan JSON"
    alert_route: "job fails before apply; no ::error:: suppression"
  - mode: "Destroy is partial — server dies, volume/attachments stranded and still billing"
    detection: "gate asserts the destroy set EQUALS the 4 web-2 addresses (not >=); post-apply Hetzner API probe asserts server AND volume absent"
    alert_route: "job fails; TR7 probe fails loudly"
  - mode: "Merge-apply acts on the orphaned instance before the dispatch runs"
    detection: "push-apply destroy-guard HALTs on destroy_count>0 (measured: 1)"
    alert_route: "merge-apply fails loudly; documented unwedge is [skip-web-platform-apply]"
  - mode: "Retire succeeds but state retains orphan addresses"
    detection: "post-apply `terraform state list | grep -c 'web-2'` == 0"
    alert_route: "job fails"
logs:
  where: "GitHub Actions run logs; Better Stack is NOT a route here (web-2 ships zero lines — that is the defect being retired, not a signal to preserve)"
  retention: "GitHub default (90d)"
discoverability_test:
  command: "curl -sS -H \"Authorization: Bearer $HCLOUD_TOKEN\" 'https://api.hetzner.cloud/v1/servers?name=soleur-web-2' | jq '.servers | length'"
  expected_output: "0 (and volumes?name=soleur-web-platform-data-web-2 → 0; total servers → 4)"
```

No `ssh` in any command (`hr-no-ssh-fallback-in-runbooks`). No dashboard eyeballing
(`hr-no-dashboard-eyeball-pull-data-yourself`).

**Soak follow-through (2.9.1):** not applicable — no time-gated close criterion. The
retire is verified synchronously by the Phase 8 API probe.

## Architecture Decision (ADR/C4)

Detection fires: retiring web-2 **supersedes ADR-068's warm-standby posture**, a
recorded architectural decision. Per `wg-architecture-decision-is-a-plan-deliverable`
the ADR + C4 edits are tasks of THIS plan, not a follow-up issue.

### ADR

**Amend ADR-068** (`ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`)
rather than mint a new ordinal — the decision being changed is ADR-068's own
warm-standby posture, and the §(c) LB-weight hard invariant survives intact.
Amendment records: the warm standby is retired; HA is deferred to active-active-N
(#6459) whose hosts must be **born in hel1 inside `web_spread`** (create-time-only
`placement_group_id`); git-data (#6570) is the gating blocker. Add the rejected
options (cpx32@fsn1, cx33@hel1) to `## Alternatives Considered` with the measured
cost + stock evidence.

*(If a reviewer prefers a standalone ADR, `/ship`'s ADR-Ordinal Collision Gate
re-verifies the next free ordinal against `origin/main`; any renumber must sweep
this plan + tasks.md + the ACs in the same edit.)*

### C4 views

**Enumeration performed** (all three model files read, per the C4 completeness
mandate) — `model.c4`, `views.c4`, `spec.c4`:

- **External human actors:** none added or removed. A host retirement changes no
  actor.
- **External systems / vendors:** none added or removed. Hetzner and Better Stack
  are already modeled.
- **Containers / data stores:** no element added or removed. The fleet is modeled as
  a single `hetzner = container "Compute"` element; there is **no dedicated `web2`
  element** to delete, and no `view … include` line to change.
- **Access relationships:** unchanged.
- **Falsified descriptions — 2 found, both must be corrected:**
  - `model.c4` `betterstack -> hetzner`: *"web-2 warm standby has NO standing uptime
    coverage — its dead-boot page is the #6396 Sentry terminal-stage issue-alert"* —
    falsified once web-2 does not exist.
  - `model.c4` `tunnel -> zotRegistry`: *"#6416: web-2 was not [a 10.0.1.0/24 member],
    so CI's registry bridge failed…"* — becomes a historical claim about a host that
    no longer exists; reword to past-tense/historical or drop the clause.

Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the
edit (a bad `view include` fails there, not at `tsc`).

### Sequencing

The ADR amendment is authored in this PR (status: accepted at merge — the decision is
true the moment the retire dispatch completes, which is Phase 8 of this same
lifecycle). No `adopting` state needed.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body` → searched
each planned path. **None** — no open code-review issue names
`variables.tf`, `apply-web-platform-infra.yml`, `article-30-register.md`,
`expenses.md`, or `cost-model.md`. Re-run at /work if the corpus changes.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

1. Re-run the baseline + web-2-removed measurement (§Research Reconciliation method).
   Confirm the delta is still `1 to change, 1 to destroy`. Stock and state are
   time-varying on an hours timescale; a stale measurement is not evidence.
2. `git grep -n 'web-2\|web\["web-2"\]' apps/web-platform/infra .github/workflows tests/` —
   enumerate the FULL reference set into tasks.md before editing anything. Known
   holders: `scheduled-inngest-health.yml`, `scripts/web2-recreate-preflight.sh`,
   the `web-2-recreate` dispatch + `tests/scripts/lib/web2-recreate-gate.sh` + its
   test, `cloud-init-ghcr-seed-login.test.sh`, `soleur-host-bootstrap-observability.test.sh`,
   `web-1-swap-concurrency-parity.test.sh`, `inngest.tf` (comment), `server.tf`
   (`web["web-1"]` is *"pinned 23 times across 5 files"* — verify none are web-2).
3. **Enum dispatchability:** confirm whether `gh workflow run --ref <branch> -f
   apply_target=web-2-retire` is rejected (422) because the enum is validated against
   the default branch. If it IS dispatchable from the branch, the `[skip-web-platform-apply]`
   merge token may be unnecessary — re-derive §Sequencing. Do not assume either way.
4. `git grep -ln 'terraform-target-parity\|OPERATOR_APPLIED_EXCLUSION' tests/ scripts/` —
   the `-target=` allow-list is asserted by a parity test AND possibly a scope guard
   (orphan suite). Every hit joins `## Files to Edit` (Sharp Edge: allow-list
   extensions must sweep all guard suites).

### Phase 1 — RED: gate-lib tests (`cq-write-failing-tests-before`)

Author `tests/scripts/test-web2-retire-gate.sh` against a not-yet-existing
`tests/scripts/lib/web2-retire-gate.sh`, sourcing the lib so CI and the test exercise
the **same bytes** (the `registry-region-migrate-gate.sh` precedent). Synthesized
plan-JSON fixtures only (`cq-test-fixtures-synthesized-only`), covering:

- happy path: exactly the 4 web-2 addresses, server+volume+network+attachment destroyed → PASS
- a web-1 address present in ANY action → FAIL
- a volume other than `workspaces["web-2"]` in the destroy set → FAIL
- destroy set missing the volume (partial retire — the measured `[ack-destroy]` shape) → FAIL
- a secret destroy present → FAIL
- unparseable/empty plan JSON → FAIL (fail-closed, TR3)

### Phase 2 — GREEN: gate lib + workflow job

Implement `web2-retire-gate.sh` and the `web_2_retire` job. Mirror
`registry-region-migrate`'s shape: `if: github.event_name == 'workflow_dispatch' &&
inputs.apply_target == 'web-2-retire'`; exact-equality `IN(.address; allow[])`
allow-set (never `inside`/`contains`); `out_of_scope == 0`; **no `[ack-destroy]`
bypass** — authorization is the menu-ack dispatch
(`hr-menu-option-ack-not-prod-write-auth`). Join the shared `web-1-swap` concurrency
group (this touches the fleet) and keep the workflow-level R2 serializer.

**Inverts AC15:** where `web-2-recreate` asserts the data volume is 0-destroy, this
path asserts the destroy set is **exactly** the 4 web-2 addresses — permitting the
volume destroy and *requiring* it (TR4), so the measured partial-destroy shape fails
closed. Add `web-2-retire` to the `apply_target` enum + its description string.

### Phase 3 — var removal

Remove the `"web-2"` key + its rationale comment from `var.web_hosts`. Sweep every
Phase-0.2 reference. `terraform fmt` + `terraform validate` clean.

### Phase 4 — Registers (CLO deliverable)

Strike the web-2 clause from `article-30-register.md` §(d)/§(e) and the matching rows
in `compliance-posture.md`. Cite content anchors, not line numbers
(`cq-cite-content-anchor-not-line-number`).

### Phase 5 — Ledger (CFO deliverable)

`expenses.md`: remove the three web-2 rows (`CX33 (web-2) 15.37`, `Volume (web-2,
20 GB) 0.88`, `Primary IPv4 (web-2) 0.54`); correct web-1 `15.37 → ~9.17` and its
`160 GB` spec → `80 GB`; correct registry `CX33 / 9.17 → CX23 / ~5.93`. Refresh
`cost-model.md` Product COGS (currently omits web-2/registry/inngest, ~$50/mo).
Carry the standard `VERIFY actual draw on the next Hetzner invoice` caveat.
`wg-record-recurring-vendor-expense-before-ready` — this is a **reduction**, but the
ledger must still be true before PR-ready.

### Phase 6 — ADR + C4

Per §Architecture Decision. Run the two C4 tests.

### Phase 7 — Merge (`[skip-web-platform-apply]`)

`/ship` → `/review` → merge. The squash commit message MUST carry
`[skip-web-platform-apply]` **on its own line** (the regex anchors to line
boundaries so it cannot fire from a code fence or trailer). Without it, the merge-apply
HALTs on the measured `destroy_count=1`.

### Phase 8 — Retire dispatch (per-command go-ahead; in-session)

Show the operator the exact command, wait for explicit go-ahead, then run it
(`hr-menu-option-ack-not-prod-write-auth`):

```
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=web-2-retire \
  -f reason="#6538 retire fsn1 orphan — cx33 unorderable in fsn1, zero telemetry, cannot join web_spread"
```

Then verify by self-pulling (TR7) — never ask the operator to check a dashboard:
server absent, volume absent, fleet = 4, `terraform state list | grep -c web-2` == 0.
The wedge window closes here.

### Phase 9 — Close out

`gh issue close 6538 6463` with the decision recorded. Confirm #6570/#6571/#6460
remain open and correctly scoped.

## Files to Edit

- `apps/web-platform/infra/variables.tf` — remove `"web-2"` from `var.web_hosts`
- `.github/workflows/apply-web-platform-infra.yml` — `web-2-retire` job + enum + description
- `tests/scripts/lib/web2-retire-gate.sh` *(create)*
- `tests/scripts/test-web2-retire-gate.sh` *(create)*
- `knowledge-base/legal/article-30-register.md` — strike web-2 §(d)/§(e)
- `knowledge-base/legal/compliance-posture.md` — matching rows
- `knowledge-base/operations/expenses.md` — 3 row removals + 2 corrections
- `knowledge-base/finance/cost-model.md` — Product COGS refresh
- `knowledge-base/engineering/architecture/decisions/ADR-068-*.md` — amendment
- `knowledge-base/engineering/architecture/diagrams/model.c4` — 2 falsified descriptions
- *(Phase 0.2 + 0.4 sweep output — the web-2 reference holders + `-target` guard suites)*

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `var.web_hosts` contains only `web-1`; `terraform fmt -check` + `terraform validate` clean.
- **AC2** — `bash tests/scripts/test-web2-retire-gate.sh` passes; it exercises the **same** lib CI sources. Fixtures synthesized.
- **AC3** — The gate REJECTS: a web-1 touch; a non-web-2 volume destroy; a **partial** destroy missing the volume; a secret destroy; an unparseable plan. Proven by the test, not by inspection.
- **AC4** — `git grep -n 'web\["web-2"\]\|web-2' apps/web-platform/infra .github/workflows tests/` returns only (a) the `web-2-retire` job itself and (b) historical prose. No live wiring to a nonexistent host.
- **AC5** — `article-30-register.md` and `compliance-posture.md` contain no stale web-2 claim: `grep -ci 'web-2' <both>` == 0.
- **AC6** — `expenses.md` has no web-2 rows; web-1 reads ~9.17 / 80 GB; registry reads CX23. `cost-model.md` Product COGS includes web-2's removal, registry, inngest.
- **AC7** — ADR-068 amendment present with the two rejected options in `## Alternatives Considered`, citing the measured €8.49 vs €35.49 and cx33-orderable-in-one-DC evidence.
- **AC8** — `model.c4`'s two falsified descriptions corrected; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **AC9** — Full suite green (`tests/scripts/test-all.sh` or the repo's canonical runner — read `package.json scripts.test`; do NOT assume a runner).
- **AC10** — PR body uses **`Closes #6538` / `Closes #6463`**… **see Risk R4** — if the retire dispatch is post-merge, these MUST be `Ref` and closed in Phase 9 instead (the ops-remediation Sharp Edge: `Closes` auto-closes at merge, before the remediation runs).

### Post-merge (operator go-ahead required — in-session, not a checklist)

- **AC11** — Merge commit contains `[skip-web-platform-apply]` on its own line; the merge-apply run shows the kill switch fired (no HALT, no destroy).
- **AC12** — `web-2-retire` dispatch run is green; its gate log shows `out_of_scope=0` and the destroy set == the 4 web-2 addresses.
- **AC13** — Hetzner API: `servers?name=soleur-web-2` → 0; `volumes?name=soleur-web-platform-data-web-2` → 0; total servers == 4.
- **AC14** — `terraform state list | grep -c 'web-2'` == 0 (no stranded addresses).
- **AC15** — web-1 (`soleur-web-platform`) still `running`; **no reboot, no resize** — `uptime`-equivalent via the Hetzner API `created`/status and a green `app.soleur.ai` probe. Better Stack still shows web-1 shipping.
- **AC16** — A subsequent no-op merge to `main` runs push-apply to **completion** (no HALT) — proves the wedge window is closed.

## Risks & Mitigations

- **R1 — mis-scoped destroy hits web-1 (catastrophic; web-1 is the live origin).**
  Mitigation: exact-equality allow-set from the SAVED plan JSON; `out_of_scope==0`;
  RED tests assert the web-1-touch rejection before the lib exists; no `[ack-destroy]`
  bypass; shared `web-1-swap` concurrency group.
- **R2 — wedge window between merge and dispatch.** Measured, understood, bounded.
  Fails safe (HALT, never silent destroy). Unwedge is the documented
  `[skip-web-platform-apply]`. Closed by Phase 8. Mitigation: run Phase 8 immediately
  after merge; do not leave the session between 7 and 8.
- **R3 — partial destroy strands the volume (measured as the `[ack-destroy]` shape).**
  Mitigation: TR4 requires the destroy set to EQUAL all four addresses; AC13 probes
  the volume independently of the server.
- **R4 — `Closes #N` auto-closes at merge, before the retire runs.** This is an
  ops-remediation-class plan (the fix executes post-merge). Per the Sharp Edge, use
  `Ref #6538 / Ref #6463` in the PR body and close in Phase 9 after the dispatch
  verifies. **Resolve R4 before /ship** — it contradicts AC10's first clause by
  design; pick `Ref`.
- **R5 — giving up a held `cx33@fsn1` that cannot be re-acquired** (cx33 is orderable
  only in `hel1-dc2`). Accepted: it is an option on a posture being abandoned;
  active-active provisions fresh hosts in hel1 inside `web_spread`.
- **R6 — stock/state drift between plan and work.** Mitigation: Phase 0.1 re-measures.

## Alternative Approaches Considered

| Option | Why rejected |
|---|---|
| `cpx32 @ fsn1` (+€27/mo) | Buys recreatability + telemetry for a host barred from serving by ADR-068 §(c) behind an unborn git-data. 4.2x cost, +47% of all Hetzner spend. Cannot join `web_spread` regardless. |
| `cx33 @ hel1` (€0) | Reverts PR #6393's deliberate cross-DC decision, force-replaces the volume, and re-bets on a SKU orderable in one DC today / zero yesterday. Ranked last by every leader. |
| `ccx13 @ fsn1` (€42.99) | Strictly worse: more expensive than cpx32 with half the cores. |
| Keep web-2, fix telemetry only | Impossible. `ignore_changes = [user_data]` → only a recreate installs Vector → blocked by the stock preflight. There is no €0 middle option. |

## Deferred (already filed — keep out of scope)

- **#6570** — git-data pinned to `cax11`, orderable in 0/3 EU DCs. Root blocker of
  ADR-068 §(c) → active-active. **The next brainstorm.**
- **#6571** — `web_spread` empty AND unreachable-by-design (`ignore_changes`).
- **#6460** — fleet-capacity-audit + the `grok-dogfood` ledger reconcile +
  `fleet-sku-orderability-audit`.
