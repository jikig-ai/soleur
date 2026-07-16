---
title: "chore: retire soleur-web-2 (fsn1 orphan)"
date: 2026-07-16
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
refs: [6538, 6463]
related: [6393, 6453, 6457, 6459, 6460, 6570, 6571, 6574, 6575]
brainstorm: knowledge-base/project/brainstorms/2026-07-16-web2-retire-fsn1-orphan-brainstorm.md
spec: knowledge-base/project/specs/feat-6538-web2-fsn1-orphan/spec.md
revision: v2 (post 6-agent plan-review)
---

# chore: retire soleur-web-2 (fsn1 orphan)

> **`refs:` not `closes:` — deliberate.** The remediation runs POST-merge (a guarded
> local apply). `Closes #N` would auto-close at merge, before the host is destroyed,
> producing a false-resolved state. #6538/#6463 are closed by hand in Phase B6 after
> the API probe verifies. This applies to the frontmatter, the PR body, and the ACs —
> all three writers must say `Ref`.

## Overview

Retire `soleur-web-2`. Operator-confirmed, unanimous across CTO / platform-strategist /
CPO / CFO; CLO indifferent. **Do not re-litigate** — the spec's Non-Goals record why
`cpx32@fsn1` (+€27/mo) and `cx33@hel1` (reverts #6393) were rejected. The deciding
argument is topological: `placement_group_id` is create-time only (`ignore_changes`),
so a host born in fsn1 can never join `web_spread`; web-2 must be destroyed and re-born
to reach the active-active target regardless.

**v2 supersedes v1** after a 6-agent review (DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow, CTO-devex). v1's defects are recorded in
§v1 Defects rather than silently dropped — three were mine, and one would have wedged
the gate permanently.

## Shape (operator decisions, 2026-07-16)

| Decision | Choice | Consequence |
|---|---|---|
| Delivery mechanism | **Operator-local guarded apply** — extend the EXISTING `destroy-guard-filter-web-platform.jq`, run it against a locally-produced saved plan JSON, apply on per-command go-ahead | No new CI job, no 9th enum value, no new gate lib, no dispatchability precondition, nothing to delete afterwards. Sanctioned by the workflow's own `OPERATOR_APPLIED_EXCLUSIONS` contract (ADR-096). |
| PR shape | **Split** — PR A (docs, this branch) then PR B (destroy, new branch) | The Art. 30 §5(2) defect is live TODAY and ships in minutes without inheriting a destroy's ceremony. |
| Dead dispatch surface | **Immediate follow-up (#6575)** | `warm-standby` + `web-2-recreate` go *broken*, not merely dead. Enum drops 9→6. Landing it inside a prod-destroy PR inverts the risk budget. |

## PR A — register + ledger accuracy (this branch, PR #6568, docs-only)

Everything here is **true today**, independent of the retire. No gates, no sequencing.
Merges immediately.

- **A1** — `article-30-register.md`: web-2's locative is wrong (`(CX33, hel1)`; live is
  **fsn1** since #6393 — a §5(2) accuracy defect CLO says must be corrected under every
  option). Correct `hel1 → fsn1` **and** `CX33` spec. Note: the register has **two**
  records (PA-1 and PA-2), each with its own (d) and (e) — **four clauses**, not two
  (v1 undercounted).
- **A2** — `compliance-posture.md`: same locative correction. **Do NOT delete the TS-1
  row** (*"a second web host (web-2) writing per-workspace git data raised a
  cross-tenant write threat class"*, #5274, status OPEN, soak-gated) — it is a live
  compliance record, not a stale claim.
- **A3** — `expenses.md`: web-1 `15.37 → ~9.17` and `160 GB → 80 GB` (cx33 is €8.49 /
  80 GB — the ledger prices the same SKU two ways); registry `CX33 / 9.17 → CX23 / ~5.93`
  (#6497/#6463); **`grok-dogfood` booked `approved-not-billing` / "Not born" but is LIVE**
  (verified via Hetzner API: cx33, hel1, created 2026-07-16, occupying 1 of 5 capped
  slots) — fix the row inline; do not route a known-false row to #6460.
  **web-2's own three rows stay** — the host still exists until PR B.
- **A4** — `cost-model.md`: Product COGS omits web-2, registry, inngest (~$50/mo).
- **A5** — planning artifacts already committed (brainstorm, spec, this plan, the
  session learning, the `brainstorm/SKILL.md` route).

**Not in PR A:** the ADR-068 amendment and the `model.c4` description fixes. Both
describe the warm-standby posture, which is **true until the destroy lands** — amending
them pre-destroy would make them lie in the other direction.

## PR B — the destroy (new branch)

### B-Sequencing (measured; unchanged by the mechanism choice)

`terraform plan` over the **exact push-apply target scope** with `"web-2"` removed from
`var.web_hosts`:

```
Plan: 0 to add, 1 to change, 1 to destroy.
  # hcloud_firewall_attachment.web will be updated in-place
  # hcloud_server.web["web-2"] will be destroyed
  # (because key ["web-2"] is not in for_each map)
```

Baseline, config unmodified: `No changes. Your infrastructure matches the configuration.`

Cause: `-target` is transitive, and `hcloud_firewall_attachment.web` — which **is** in
the push-apply target list — declares `server_ids = [for h in hcloud_server.web : h.id]`.
(The generalised hazard is now #6574; not fixed here.)

| Order | Behaviour | Verdict |
|---|---|---|
| Merge var removal plainly | destroy-guard HALTs **every subsequent merge** | Reject — #6393-class wedge |
| Merge with `[ack-destroy]` | Unguarded **partial** destroy (server only; volume strands, still billing) via a commit trailer | Reject — `hr-menu-option-ack-not-prod-write-auth` |
| Destroy first (config still declares web-2) | Next push-apply plans a CREATE → the `host_creates` tripwire HALTs (verified: evaluated *before and outside* the `destroy_count` sum, so `[ack-destroy]` cannot bypass it) | Reject — mirrored wedge |
| **Merge with `[skip-web-platform-apply]`, then guarded local apply** | Apply skipped at merge. Window until the apply completes. | **Chosen** |

**No ordering closes the window** (config changes at merge, state at apply). All fail
*safe* (HALT, never silent destroy). `[skip-web-platform-apply]` is the workflow's own
documented kill switch and its deliberate use is in-contract; it suppresses **all**
guards for that squash, so the squash must stay single-purpose.

**Phase 0.3 is settled by policy, not experiment** (v1 wrongly deferred it): the sibling
plan `2026-07-05-feat-web-2-recreate-bootstrap-plan.md` states flatly that
`workflow_dispatch` resolves against the default branch only. Moot regardless — the
chosen mechanism has no dispatch. **v1's "the skip token may be unnecessary — re-derive
§Sequencing" clause is deleted**: never let `/work` re-derive the most load-bearing
section mid-implementation.

### B0 — Preconditions

1. Re-run both measurements (baseline + web-2-removed) — stock and state are
   time-varying; a stale measurement is not evidence. **AC-B1** records the result.
2. Reference sweep — **paths corrected** (v1 greped two tokens that appear **zero**
   times and missed the directory where the guards live):
   ```
   git grep -n 'web-2\|web_2\|web\["web-2"\]' \
     apps/web-platform/infra .github/workflows tests/ scripts/ plugins/soleur/test/
   ```
   Capture the hit-set to a file at B0 — **AC-B4 diffs against it** rather than grading
   prose. (Measured today: **311 hits / 45 files** — v1's AC4 was unsatisfiable.)
3. **Do NOT** join the `web-1-swap` concurrency group (v1 would have red-CI'd:
   `web-1-swap-concurrency-parity.test.sh` asserts a named member allow-list **and**
   exactly 4 `group: web-1-swap` occurrences). Moot under the local-apply mechanism —
   no job exists. The workflow-level R2 serializer is the one that matters, and the R2
   backend has **no state lock** (`use_lockfile = false`), so the local apply must not
   race a CI apply: confirm no `apply-web-platform-infra` run is in flight first.

### B1 — Extend the existing gate (no new lib)

`tests/scripts/lib/destroy-guard-filter-web-platform.jq` already implements
exact-equality via `IN(.address; web2_allow[])`. Its `web2_allow` is a **recreate**
set — 3 addresses, deliberately excluding the volume (that is AC15). Add a sibling
`web2_retire_allow` with **five**:

```
hcloud_server.web["web-2"]
hcloud_server_network.web["web-2"]
hcloud_volume_attachment.workspaces["web-2"]
hcloud_volume.workspaces["web-2"]        # retire DESTROYS it (inverts AC15)
hcloud_firewall_attachment.web           # the measured "1 to change" — update-only
```

**The 5th address is a v1 P0 miss.** The precedent targets its firewall attachment
deliberately (`registry_region_migrate` comments *"the registry server + its 3
id-referencing dependents"*, with a `firewall_ok` counter accepting `update`/`create`).
Omitting it wedges the gate permanently: the attachment is out-of-scope → abort → and
web-2 is already removed from config.

Asserts:
- `out_of_scope == 0` — **necessary but NOT sufficient**: it *passes* the measured
  1-destroy partial shape (the server destroy IS in the allow-set). The positive
  per-address counters are the load-bearing half.
- **Four named per-address destroy counters** (`server_destroyed`, `nic_destroyed`,
  `attachment_destroyed`, `volume_destroyed`) — not a bare `length == 4`, which four
  *wrong* addresses could satisfy if `out_of_scope` ever has a hole. The volume counter
  is pinned to the exact address (a bare `hcloud_volume.*` count would let **web-1's**
  volume satisfy it).
- `firewall_attachment_ok`: exactly one `update`, **never `delete`** (a delete strips
  web-1's firewall).
- **Idempotent-retry shape:** assert each counter is `<= 1` and the destroy set is a
  **subset** of the allow-set with `>= 1` member — NOT strict equality. Terraform
  applies sequentially and can die after 1 of 4; strict equality would fail-closed on
  re-run, leaving a half-retired state (server gone, volume billing) unrecoverable by
  the gate itself. **v1 P0, caught by spec-flow.**
- Fail-closed on unparseable/empty plan JSON.

Tests extend `tests/scripts/test-destroy-guard-counter-web-platform.sh` — the **real**
exerciser. There is no `test-web2-recreate-gate.sh`; v1 invented a file the precedent
it cited does not have. Fixtures synthesized (`cq-test-fixtures-synthesized-only`):
web-1 touch → FAIL; non-web-2 volume destroy → FAIL; partial (server-only) → FAIL;
firewall attachment **delete** → FAIL; retry-after-partial (3 of 4 remaining) → PASS;
unparseable → FAIL.

### B2 — Fix the destroy-HALT error text (safety prerequisite)

The `destroy_count` HALT currently ends: *"Add a line containing exactly
'[ack-destroy]' to the merge commit message to acknowledge, or revert the trigger
commit."* A concurrent merge during **our** window hits exactly this text, and following
it authorizes the partial destroy this plan exists to prevent. (v1's R2 cited the
`host_creates` HALT's `[skip-web-platform-apply]` unwedge line — **the wrong HALT**.)

Make the destroy-HALT name `[skip-web-platform-apply]` and warn that `[ack-destroy]`
here may be a *partial* destroy. **In PR B, not #6575** — we create this hazard, so we
carry its mitigation; and it is a one-string safety fix, not machinery deletion.

### B3 — var removal + `proxy-tls` decision (SEE §Open Decision)

Remove the `"web-2"` key + its rationale comment. `terraform fmt` + `validate` clean.

### B4 — ADR-068 amendment + C4

Amend ADR-068 (do not mint a new ordinal — the decision being changed is its own
warm-standby posture; §(c) survives). Record: standby retired; HA deferred to
active-active-N (#6459) whose hosts must be **born in hel1 inside `web_spread`**;
git-data (#6570) is the gating blocker. Add the rejected options to
`## Alternatives Considered` with the measured cost/stock evidence.

**C4 enumeration** (all three `.c4` files read): no external actor, external system,
container, data store, or access relationship changes — the fleet is one
`hetzner = container "Compute"` element; there is no `web2` element and no
`view … include` to touch. **Two descriptions are falsified and must be corrected:**
`betterstack -> hetzner` (*"web-2 warm standby has NO standing uptime coverage…"*) and
`tunnel -> zotRegistry` (the *"#6416: web-2 was not [a subnet member]…"* clause → past
tense). Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### B5 — Register + ledger strikes

Now that web-2 is going: **record the retirement, do not silently strike** (good Art. 30
practice, and the token must survive for the audit trail). Add an amendment note dated
2026-07-16 referencing #6538. Remove web-2's three `expenses.md` rows.

### B6 — Merge, apply, verify, close

1. Merge PR B with `[skip-web-platform-apply]` **on its own line** of the squash commit.
2. Produce the saved plan locally (`-target` the 5 addresses, `-out=tfplan`), run
   `terraform show -json tfplan | jq -f destroy-guard-filter-web-platform.jq`, and show
   the operator the gate verdict **and** the exact apply command.
3. **Wait for explicit per-command go-ahead** (`hr-menu-option-ack-not-prod-write-auth`
   — per-command confirmation; menu acks and prior approvals do NOT extend). Then apply
   in-session. This is a confirm-then-run, **never** a checklist handed over
   (`hr-never-defer-operator-actions`).
4. Verify by self-pull (`hr-no-dashboard-eyeball-pull-data-yourself`), then
   `gh issue close 6538 6463`.

**If go-ahead does not arrive** (spec-flow P0-2 — v1 left this open-ended): the wedge
persists and every merge needs the skip token. **Time-box: 1 hour.** Past that, revert
PR B (re-add the `web_hosts` key) — state and config re-converge, window closes, retry
later. **AC-B10** covers this.

## Open Decision — `proxy-tls` cert rotation (P0, unresolved)

`apps/web-platform/infra/proxy-tls.tf`:

```hcl
resource "tls_self_signed_cert" "proxy_server" {
  ip_addresses = [for h in values(var.web_hosts) : h.private_ip]
  dns_names    = concat(keys(var.web_hosts), ["localhost"])
}
resource "doppler_secret" "proxy_tls_cert" { ... }
```

Both inputs are **ForceNew**. Removing web-2 **replaces the cert** and rotates
`PROXY_TLS_CERT` / `PROXY_TLS_KEY` in Doppler `prd` — the runtime value the proxying
client pins as `ca:` with `rejectUnauthorized: true`.

**It contains no `web-2` literal**, so B0's grep, AC-B4, and the measurement (outside the
2-target scope) **all miss it**. It fires at neither merge nor the 5-target apply — it is
*latent*, surfacing on the next **full** plan: `scheduled-terraform-drift.yml` runs
`terraform plan -detailed-exitcode` with **no `-target`** → a permanent 12h drift alarm
auto-filing issues. This **falsifies** v1's claim that the drift detector is
"independent confirmation".

Three options, none free — **route to `/soleur:deepen-plan`** (the plan skill mandates it
at `single-user incident`, and its data-integrity + security triad is the right lens):

1. **Bring cert + both Doppler secrets into the retire scope.** Correct end-state, but
   rotates the pinned CA under a **running web-1** that baked the old cert at container
   start → mismatch until web-1's next restart. Blast radius on the live origin.
2. **Accept + document the drift.** Permanent 12h alarm until someone runs the
   operator-local full apply — which then rotates the cert anyway, unsupervised.
3. **Decouple the cert from `var.web_hosts`** (pin the SAN list, or fan `for_each`) so
   removing a host is not ForceNew. Cleanest; adjacent to #6574.

**Do not start B3 until this is decided.**

## User-Brand Impact

- **If this lands broken, the user experiences:** a total prod outage if the destroy
  mis-scopes onto **web-1** (the live origin — app A-record; only tunnel connector), or
  a TLS handshake failure across the proxy path if the cert rotates under a running
  web-1 (§Open Decision). web-2's own retirement is user-invisible: never served, no LB,
  empty volume.
- **If this leaks, the user's data is exposed via:** n/a — volume empty, never held a
  worktree; all DCs EU (CLO: residency neutral).
- **Brand-survival threshold:** `single-user incident` — from the destroy path's blast
  radius, not web-2's value. `requires_cpo_signoff: true`, satisfied by brainstorm
  carry-forward; `user-impact-reviewer` fires at review.

**The inversion:** the dark standby is not the risk; *believing* it is a standby is.
ADR-068 calls a bare web-2's `200/status:ok` **"a routing lie"**.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Finance — all four assessed the final
scope at brainstorm; carried forward verbatim rather than restated here (v1 spent 40
lines re-litigating a decision it declared out of scope). See the brainstorm's
`## Domain Assessments`. Product/UX Gate: **NONE** — the mechanical UI-surface scan over
Files-to-Edit matches no path in `ui-surface-terms.md`; no `.pen` required.

## Observability

```yaml
liveness_signal:
  what: "the guarded local apply's gate verdict + the drift detector's next full plan (0 6,18 * * *)"
  cadence: "once (apply) + 12h (drift)"
  alert_target: "in-session gate output; drift detector auto-files an issue"
  configured_in: "tests/scripts/lib/destroy-guard-filter-web-platform.jq; .github/workflows/scheduled-terraform-drift.yml"
error_reporting: { destination: "in-session gate verdict + terraform exit code", fail_loud: true }
failure_modes:
  - mode: "destroy mis-scopes onto web-1"
    detection: "out_of_scope==0 + four named per-address counters over the SAVED plan JSON"
    alert_route: "gate fails before apply"
  - mode: "partial destroy — server dies, volume strands and keeps billing"
    detection: "per-address volume_destroyed counter pinned to hcloud_volume.workspaces[\"web-2\"]; post-apply API probe asserts volume absent independently of the server"
    alert_route: "gate fails; probe fails"
  - mode: "apply dies mid-sequence; retry blocked by a strict-equality gate"
    detection: "subset + <=1 counters (NOT strict equality) so a 3-of-4 retry passes"
    alert_route: "retry proceeds; no unrecoverable half-state"
  - mode: "concurrent merge during the window"
    detection: "push-apply destroy-guard HALTs on destroy_count>0 (measured: 1)"
    alert_route: "merge fails loudly; B2 makes its error text name the CORRECT recovery"
  - mode: "proxy-tls cert drift (latent — see Open Decision)"
    detection: "scheduled-terraform-drift.yml full plan (no -target)"
    alert_route: "auto-filed drift issue"
logs: { where: "in-session apply output + GitHub Actions for the merge", retention: "GitHub default 90d" }
discoverability_test:
  command: "curl -sS -H \"Authorization: Bearer $HCLOUD_TOKEN\" 'https://api.hetzner.cloud/v1/servers?name=soleur-web-2' | jq '.servers | length'"
  expected_output: "0 (volumes?name=soleur-web-platform-data-web-2 → 0; total servers → 4)"
```

No `ssh` anywhere. Soak follow-through (2.9.1): n/a — verified synchronously.

## Acceptance Criteria

### PR A (pre-merge)

- **AC-A1** — Art. 30: no surviving **present-tense locative** claim placing web-2 in
  `hel1`. Assert the anchor, not the bare token (`cq-assert-anchor-not-bare-token`):
  `grep -cE 'web-2.*(CX33|hel1)' article-30-register.md` == 0. All **four** clauses
  (PA-1 (d)/(e), PA-2 (d)/(e)) reconciled.
- **AC-A2** — `compliance-posture.md` locative corrected **and** the TS-1 row still
  present: `grep -c 'cross-tenant write threat class' compliance-posture.md` >= 1.
- **AC-A3** — `expenses.md`: web-1 row reads ~9.17 / 80 GB; registry reads CX23;
  grok-dogfood row reads live/billing. web-2's three rows still present.
- **AC-A4** — `cost-model.md` Product COGS includes web-2, registry, inngest.
- **AC-A5** — `bash scripts/test-all.sh` green (the **real** runner per `package.json`;
  v1 named a nonexistent `tests/scripts/test-all.sh`).

### PR B (pre-merge)

- **AC-B1** — Both measurements re-run at B0 and recorded verbatim in the PR body.
- **AC-B2** — `web2_retire_allow` has exactly the **5** addresses incl.
  `hcloud_firewall_attachment.web`.
- **AC-B3** — Gate tests (extending `test-destroy-guard-counter-web-platform.sh`) REJECT:
  web-1 touch; non-web-2 volume destroy; server-only partial; firewall-attachment delete;
  unparseable plan. And ACCEPT a 3-of-4 retry-after-partial. Proven by test, not inspection.
- **AC-B4** — Reference sweep: `git grep` over the **corrected** path set diffs clean
  against the B0-captured expected hit-set. (Not "returns only historical prose" — v1's
  AC4 had no machine-checkable verdict and returned 311 hits.)
- **AC-B5** — Destroy-HALT `::error::` text names `[skip-web-platform-apply]` and warns
  that `[ack-destroy]` may be partial.
- **AC-B6** — §Open Decision resolved and its choice implemented; `terraform validate`
  clean; `terraform fmt -check` clean.
- **AC-B7** — ADR-068 amended with both rejected options; `model.c4`'s two falsified
  descriptions corrected; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **AC-B8** — `bash scripts/test-all.sh` green. If a new suite file is added, it is
  **registered in `scripts/test-all.sh`** (it registers suites explicitly — otherwise
  the gate never runs in CI and AC-B3 passes standalone while AC-B8 greens vacuously).
- **AC-B9** — PR body uses **`Ref #6538` / `Ref #6463`** (never `Closes`); frontmatter
  says `refs:`.

### PR B (post-merge — in-session, per-command go-ahead)

- **AC-B10** — Merge commit carries `[skip-web-platform-apply]` on its own line; the
  merge-apply run shows the kill switch fired. If go-ahead has not arrived within **1
  hour**, PR B is reverted and the window closed.
- **AC-B11** — Gate verdict shown to the operator BEFORE apply; `out_of_scope=0`; four
  per-address destroy counters == 1; firewall attachment update-only.
- **AC-B12** — Hetzner API: `servers?name=soleur-web-2` → 0; `volumes?name=soleur-web-platform-data-web-2`
  → 0; total servers == 4.
- **AC-B13** — `terraform state list | grep -c 'web-2'` == 0.
- **AC-B14** — web-1 still serving: `app.soleur.ai` probe 200 **and** Better Stack still
  shows `host=soleur-web-platform` shipping. (v1's "no reboot via the `created` field"
  was a **broken proxy** — Hetzner `created` never changes on reboot.)
- **AC-B15** — A subsequent no-op merge runs push-apply to completion (no HALT) — proves
  the window is closed.
- **AC-B16** — #6538 + #6463 closed by hand after AC-B12 verifies. #6575 filed and
  unblocked.

## v1 Defects (recorded, not dropped)

Four were mine and would have shipped:

1. **Missing 5th `-target`** (`hcloud_firewall_attachment.web`) — my own measurement
   printed it as "1 to change" and I did not carry it into the allow-set. Would have
   wedged the gate permanently. *(architecture-strategist P0)*
2. **`proxy-tls.tf` unseen** — a `var.web_hosts` consumer with no `web-2` literal,
   invisible to my grep, my AC, and my measurement. *(architecture-strategist P0)*
3. **Strict-equality gate is not idempotent** — a mid-apply failure would be
   unrecoverable by the gate itself. *(spec-flow P0)*
4. **R2 cited the wrong HALT's recovery text** — the destroy-HALT actually prescribes
   `[ack-destroy]`, i.e. the partial destroy this plan exists to prevent. *(CTO P0)*
5. AC4 unsatisfiable (311 hits); AC5 an absence-grep that would delete a live compliance
   record; AC9 a nonexistent runner; Phase 0.4 greped two tokens with zero hits; Phase 2
   would have red-CI'd the concurrency parity test; AC15 a broken reboot proxy; R4/AC10/
   frontmatter a three-way `Closes`-vs-`Ref` contradiction.

## Risks

- **R1 — mis-scoped destroy hits web-1.** Exact-equality allow-set from the SAVED plan;
  four per-address counters; RED tests first; operator sees the verdict before apply.
- **R2 — wedge window.** Fails safe (HALT). B2 fixes the recovery text. Time-boxed to 1h
  with a revert path (AC-B10).
- **R3 — proxy-tls cert rotation.** Unresolved — §Open Decision, routed to deepen-plan.
- **R4 — R2 backend has no state lock.** Confirm no CI apply in flight before the local
  apply (B0.3).
- **R5 — giving up a held `cx33@fsn1`** (orderable only in `hel1-dc2`). Accepted: an
  option on a posture being abandoned.

## Deferred (filed)

- **#6570** — git-data pinned to `cax11`, orderable 0/3 EU DCs. Root blocker of
  active-active. **Next brainstorm.**
- **#6571** — `web_spread` empty AND unreachable-by-design.
- **#6574** — the push-apply `-target` allow-list is a fiction (firewall attachment
  drags the fleet into every merge's graph). Standing hazard.
- **#6575** — dead web-2 dispatch sweep (`warm-standby` + `web-2-recreate` + scripts +
  parity blocks + inngest-health prose + ADR-082 + the #6396 Sentry alert +
  `lb-weight-gate.sh`). Enum 9→6. Lands immediately after B6 verifies.
- **#6460** — fleet-capacity-audit + `fleet-sku-orderability-audit`.
