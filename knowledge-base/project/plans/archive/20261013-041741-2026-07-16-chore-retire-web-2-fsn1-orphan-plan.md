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

- **A6 — PUBLIC legal docs (EMERGENT; v2 did not contemplate this).** v2 scoped PR A to
  the **internal** register + ledger. It missed that the **public** docs users read carry
  the same defect on a far more exposed surface: **40 live claims** across
  `docs/legal/{gdpr-policy,privacy-policy,data-protection-disclosure}.md`, their 3 Eleventy
  mirrors, and the DPA template pinned hosting to **Helsinki-only** and named web-2 — false
  since #6393 (2026-07-13). They also asserted a **dedicated per-workspace git-data host**
  that has **never existed** (verified live: 5 servers, no `soleur-git-data`).
  **Operator decision 2026-07-16 — state the plane at the EU level, do not re-pin to two
  DCs.** Re-pinning would be true today and false the moment PR B lands, and **PR B had no
  step to revert it** (B5 covers only the register + expenses.md) — i.e. the literal fix
  plants a defect PR B is not scoped to catch. The EU-level claim is true now, after PR B,
  and after active-active-N (#6459); the Finland pin has already broken once and #6570
  says capacity may force other DCs again. Claims that are specific **and true** keep
  their specificity (workspace data, user-serving host, per-turn telemetry → `hel1`).
  The **6 dated `Previous:` changelog entries are left verbatim** — true when written.
  PR B inherits **B5.3/B5.4** to update the one "current DCs" note per doc.
- **A7 — `terms-and-conditions.md` deliberately NOT edited.** Its claim is defensible as
  written (web-2 never served the Web Platform), and the CLO-signed
  `knowledge-base/legal/tc-version-bump-policy.md` makes **any non-cosmetic T&C edit Tier 2
  "clarifying" → BUMP REQUIRED**, forcing every user to re-accept and closing live WS
  sessions. Not worth consent fatigue for a host being deleted. `TC_VERSION` 2.4.0 and
  `TC_DOCUMENT_SHA` untouched; the file is byte-identical to main.
  *(Note: `legal-doc-shas.ts` has **no `terms-and-conditions` key** — the T&C SHA lives in
  `tc-version.ts` and is written to the WORM consent ledger.)*

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
2b. **Derivation sweep (ADR-118 — the sweep above cannot find what created the B-GATE).**
   The token grep enumerates *mentions*; `proxy-tls.tf` couples to web-2 purely by
   *derivation* (`for h in values(var.web_hosts)`) and contains **zero** `web-2` literals,
   so step 2, AC-B4 and the measurement missed it simultaneously. Capture a second hit-set:
   ```
   git grep -ln 'var\.web_hosts' apps/web-platform/infra    # 9 files, measured 2026-07-17
   ```
   Audit **every dependent** (not every mention) for ForceNew-on-membership-change *and for
   host-count assumptions*, and diff AC-B4 against this set too. The **nine**:
   `server.tf`, `network.tf`, `dns.tf`, `placement-group.tf`, `proxy-tls.tf`, `variables.tf`,
   **`web-hosts-fanout-parity.test.sh`**, **`tests/web-hosts-eu-pin.tftest.hcl`**,
   **`scripts/deploy-status-fanout-verify.sh`**.

   ⚠️ **The last three were themselves missed by the first draft of this very step** (it
   listed six from memory instead of running the command). That is the ADR-118 lesson
   recurring inside its own remediation: **run the sweep, do not recall it.** Derive this list
   fresh at B0 — if it returns more than nine, audit the extras rather than assuming noise.
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
`web2_retire_allow` with **seven** *(5 + the 2 added by ADR-118)*:

```
hcloud_server.web["web-2"]
hcloud_server_network.web["web-2"]
hcloud_volume_attachment.workspaces["web-2"]
hcloud_volume.workspaces["web-2"]        # retire DESTROYS it (inverts AC15)
hcloud_firewall_attachment.web           # the measured "1 to change" — update-only
tls_self_signed_cert.proxy_server        # ADR-118 — replace (delete+create); cert_replaced <= 1
doppler_secret.proxy_tls_cert            # ADR-118 — update-only; doppler_cert_ok, NEVER delete
```

`tls_private_key.proxy_server` is **deliberately absent** — it has no `var.web_hosts`
dependency, so it must never plan a change; if it does, that is a key rotation and
`web2_out_of_scope_changes` must halt. Assert this with a synthesized fixture, don't assume it.

Adding the two cert addresses **cannot weaken the gate**: membership is exact-equality via
`IN(.address; web2_retire_allow[])` (the filter's own header warns against substring matching
for precisely this reason), and they are exact strings in a resource-type space disjoint from
`hcloud_volume.workspaces["web-1"]`. The allow-list is a set of exact addresses, not a risk budget.
⚠️ **Name the RETIRE array, not the recreate one** — the existing `web2_allow` is the 3-address
*recreate* set above; the new predicate must read `web2_retire_allow[]`. Copy-pasting
`web2_allow[]` into B1.4 silently grades the retire plan against the recreate allow-set.

**The corresponding `-target` list gains only ONE entry (5 → 6)** — the two lists are not the
same list. `-target=doppler_secret.proxy_tls_cert` transitively pulls in
`tls_self_signed_cert.proxy_server` → `tls_private_key.proxy_server`, because `-target` is
transitive on *dependencies*. The allow-list must name everything that **appears in the plan**;
the `-target` list names only what must be **reached**.

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

### B3 — var removal + the `proxy-tls` decision (SEE §Resolved Decision / ADR-118)

1. Remove the `"web-2"` key + its rationale comment from `var.web_hosts`.
2. **`proxy-tls` — ADR-118, Option 1.** `proxy-tls.tf` must end **byte-identical to `main`**
   (a zero-line diff — the existing for-expressions already compute the right answer; if that
   file changed, the wrong option was implemented). The work lives entirely in the gate
   (B1.4/B1.4b) and the `-target` list (B6). **Do NOT hardcode/pin the SAN list** — rejected
   Option 3.
3. `terraform fmt` + `validate` clean.
4. **Fix `web-hosts-fanout-parity.test.sh` — PR B red-CIs it otherwise** (CI-registered at
   `.github/workflows/infra-validation.yml:434`; measured against a simulated B3.1, not
   predicted). Two distinct edits, both required:
   - **Three workflow literals must move in lockstep** with the roster —
     `web-platform-release.yml:563`, `apply-web-platform-infra.yml:710` and `:974` each
     hardcode `WEB_HOST_PRIVATE_IPS: "10.0.1.10,10.0.1.11"` → `"10.0.1.10"`.
   - **The test's own hardcoded 2-host floor** (`if [ "$tf_n" -lt 2 ]; then fail "… — parser
     drift"`) must drop to `-lt 1`. Correcting only the literals still leaves `3 passed, 1
     failed`, and it fails with a message blaming *parser drift* rather than the roster — fix
     the message too, or the next reader debugs the wrong thing.

   ⚠️ **Ordering trap for #6575:** apply-workflow copies #1/#2 live in the
   `warm_standby`/`web_2_recreate` jobs that **#6575 deletes after B6** — and
   `check_all_copies "$APPLY_WORKFLOW" … 2` pins `min_copies=2`, so #6575's deletion trips
   `expected >=2 copies, found 0`. #6575 must lower `min_copies` in the same PR.

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
2. Produce the saved plan locally (`-target` the **6** addresses — the 5 plus
   `doppler_secret.proxy_tls_cert` per ADR-118; the gate's `web2_retire_allow` is a
   **different list** and carries **7** — `-out=tfplan`), run
   `terraform show -json tfplan | jq -f destroy-guard-filter-web-platform.jq`, and show
   the operator the gate verdict **and** the exact apply command.
3. **Wait for explicit per-command go-ahead** (`hr-menu-option-ack-not-prod-write-auth`
   — per-command confirmation; menu acks and prior approvals do NOT extend). Then apply
   in-session. This is a confirm-then-run, **never** a checklist handed over
   (`hr-ship-message-no-operator-checklist`). *(Corrected 2026-07-17: this cited
   `hr-never-defer-operator-actions`, which does not exist in AGENTS.md and is not in
   `scripts/retired-rule-ids.txt` — a fabricated ID, structurally indistinguishable from a
   real one. Pre-existing on `main`; fixed inline rather than deferred.)*
4. Verify by self-pull (`hr-no-dashboard-eyeball-pull-data-yourself`), then
   `gh issue close 6538 6463`.

**If go-ahead does not arrive** (spec-flow P0-2 — v1 left this open-ended): the wedge
persists and every merge needs the skip token. **Time-box: 1 hour.** Past that, revert
PR B (re-add the `web_hosts` key) — state and config re-converge, window closes, retry
later. **AC-B10** covers this.

## Resolved Decision — `proxy-tls` cert rotation (was P0; **RESOLVED 2026-07-17**)

**Ruled: Option 1 — bring the cert + `doppler_secret.proxy_tls_cert` into PR B's scope
and re-mint deliberately inside the supervised operator-local apply.** Full rationale and
rejected alternatives: **[ADR-118](../../engineering/architecture/decisions/ADR-118-proxy-cert-sans-track-the-cluster-roster.md)**
(CTO ruling, deepen-plan 2026-07-17). `proxy-tls.tf` is **unchanged** — a zero-line diff;
the existing for-expressions already compute the right answer.

**The B-GATE is cleared. B0–B6 may proceed.**

`apps/web-platform/infra/proxy-tls.tf`:

```hcl
resource "tls_self_signed_cert" "proxy_server" {
  ip_addresses = [for h in values(var.web_hosts) : h.private_ip]   # RequiresReplace
  dns_names    = concat(keys(var.web_hosts), ["localhost"])        # RequiresReplace
}
resource "doppler_secret" "proxy_tls_cert" { ... }
```

Removing web-2 **replaces the cert** and rotates `PROXY_TLS_CERT` in Doppler `prd` — the
value the proxying client pins as `ca:` with `rejectUnauthorized: true`.

**It contains no `web-2` literal**, so B0's grep, AC-B4, and the measurement (outside the
2-target scope) **all miss it**. The coupling is by *derivation*, not by mention — a token
grep is structurally blind to it (see B0's added `var.web_hosts` sweep). Left un-applied it
is *latent*, surfacing on the next **full** plan: `scheduled-terraform-drift.yml` runs
`terraform plan -detailed-exitcode` with **no `-target`** → a permanent 12h drift alarm
(`cron: 0 6,18 * * *`, one issue + a "Drift still present" comment every 12h + 2 emails/day
to ops, with no allow-list to silence it). This **falsifies** v1's claim that the drift
detector is "independent confirmation".

### Two corrections to this section's own v2 text (verified 2026-07-17)

1. **Only `PROXY_TLS_CERT` rotates — NOT `PROXY_TLS_KEY`.** This section previously named
   both. `doppler_secret.proxy_tls_key` reads `tls_private_key.proxy_server.private_key_pem`,
   and that resource has **zero** dependency on `var.web_hosts`, so it is never replaced.
   Same key, new cert.
2. **The "blast radius on the live origin" that motivated the deferral does not exist.** The
   proxy path is dark behind three independent locks (`GIT_DATA_STORE_ENABLED` unset;
   `SOLEUR_HOST_ROSTER` unset → `owner-unresolved`, never `proxy`; `SOLEUR_PROXY_BIND` unset
   → no listener). Further, a mismatch is *structurally impossible*: the TLS server cert and
   the pinned client CA are the same PEM read from the same env var on the same host, so a
   stale host verifies against itself; skew needs two hosts of different vintages, which the
   destroy removes. §User-Brand Impact repeats this vacuous risk and is corrected below.

### The three options, and why Option 1 won (summary; ADR-118 is authoritative)

1. **Bring cert + the cert's Doppler secret into the retire scope.** **CHOSEN.** The cost is
   provably zero *today* (path dark, one host, cert unconsumed) and monotonically increasing
   after the 3.D cutover. `terraform-target-parity.test.ts` already carries a *tested*
   rationale that the cert *"belong[s] to the web-host cluster (SANs = web host private IPs)
   and ride[s] the same cluster apply"* — PR B's local apply **is** that cluster apply.
2. **Accept + document the drift.** Rejected — dominated: pays a permanent alarm *and* still
   ends in the same rotation, later, unbounded. Alarm fatigue on the detector guarding prod
   is itself the harm.
3. **Decouple / pin the SAN list.** Rejected despite being a *proven* no-op (measured:
   `No changes.`). It falsifies the parity test's rationale in place, and at 3.D a new host
   gets no SAN → TLS verification fails on the live path **with the drift detector blinded**
   (a static pin doesn't drift when a host is added). Trading a loud alarm for a quiet break
   is not conservative.

## User-Brand Impact

- **If this lands broken, the user experiences:** a total prod outage if the destroy
  mis-scopes onto **web-1** (the live origin — app A-record; only tunnel connector).
  web-2's own retirement is user-invisible: never served, no LB, empty volume.
  *(Corrected 2026-07-17, ADR-118: this bullet previously also claimed "a TLS handshake
  failure across the proxy path if the cert rotates under a running web-1". That risk is
  **vacuous** — the proxy path is dark behind three independent locks, and the server cert
  and pinned client CA are the same PEM from the same env var on the same host, so a stale
  host verifies against itself. Vintage skew requires two hosts; the destroy leaves one.
  The mis-scope-onto-web-1 risk is the sole survivor, and it is what the gate defends.)*
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
  - mode: "proxy-tls cert re-mint not applied (would leave a permanent 12h drift alarm)"
    detection: "in-scope per ADR-118 — the B1.4b counters cert_replaced + doppler_cert_ok, evaluated over the SAVED plan JSON at B6; scheduled-terraform-drift.yml full plan (no -target, cron 0 6,18 * * *) is the backstop that fires if the re-mint never applies"
    alert_route: "gate fails before apply; else auto-filed drift issue + 12h comment thread + 2 emails/day to ops"
logs: { where: "in-session apply output + GitHub Actions for the merge", retention: "GitHub default 90d" }
discoverability_test:
  command: "curl -sS -H \"Authorization: Bearer $HCLOUD_TOKEN\" 'https://api.hetzner.cloud/v1/servers?name=soleur-web-2' | jq '.servers | length'"
  expected_output: "0 (volumes?name=soleur-web-platform-data-web-2 → 0; total servers → 4)"
```

No `ssh` anywhere. Soak follow-through (2.9.1): n/a — verified synchronously.

## Acceptance Criteria

### PR A (pre-merge)

- **AC-A1** — Art. 30: no surviving **present-tense locative** claim placing web-2 in
  `hel1`. Anchor on the locative *construct*, not the bare token
  (`cq-assert-anchor-not-bare-token`):
  `grep -cE 'web-2[^.;]{0,25}(in|\(CX33,) \`hel1\`' article-30-register.md` == 0,
  **and** `grep -cE 'web-2[^.;]{0,45}\`fsn1\`'` == **6** (all four clauses located, plus
  the annex row and PA-8(e)). *(Count corrected at /work 2026-07-16: this AC said **4**.
  The as-written file has **6** — the annex row and PA-8(e) were added after the AC was
  drafted, so the **AC was a stale plan-prose tally and the file was right**. Re-derived
  from the as-written file with the command published above, per the plan's own
  "counts must be derived from the as-written artifact" rule. The four clauses are PA-1
  (d)/(e) and PA-2 (d)/(e).)*
  All **four** clauses (PA-1 (d)/(e), PA-2 (d)/(e)) reconciled.
  **v2 note — the first draft of this AC was itself the defect** (the exact
  false-failing absence-grep the panel warned about): `web-2.*(CX33|hel1)` matches the
  *correct* text "web-2 CX33 in `fsn1`", because CX33 is a true property of web-2, and
  the alternation also fires on the legitimate relocation history `relocated \`hel1\`→\`fsn1\``.
  The predicate above is **mutation-tested**: 0 on the corrected file, 2 on a copy with
  the locative reverted to `hel1` — so it is anchored, not vacuous.
- **AC-A2** — `compliance-posture.md` locative corrected **and** the TS-1 row still
  present: `grep -c 'cross-tenant write threat class' compliance-posture.md` >= 1.
- **AC-A3** — `expenses.md`: web-1 row reads ~9.17 / 80 GB; registry reads CX23;
  grok-dogfood row reads live/billing. web-2's three rows still present.
- **AC-A4** — `cost-model.md` Product COGS includes web-2, registry, inngest.
- **AC-A5** — `bash scripts/test-all.sh` green (the **real** runner per `package.json`;
  v1 named a nonexistent `tests/scripts/test-all.sh`).

### PR B (pre-merge)

- **AC-B1** — Both measurements re-run at B0 and recorded verbatim in the PR body.
  **Per ADR-118 there are now two distinct shapes and they must not be conflated:** the
  **push-apply-scope** measurement is **unchanged** (`0 to add, 1 to change, 1 to destroy`)
  — the cert is unreachable from that scope, since `-target` is transitive on *dependencies*,
  not *dependents*, and nothing in the push-apply list depends on the cert. The **B3
  local-apply** shape **does** change (a cert replace is `1 to add, 0 to change, 1 to
  destroy`, so the destroy count increments). **Measure both; encode neither** — a predicted
  counter here would repeat the v1 P0 miss that the 5th address already cost once.
- **AC-B2** — `web2_retire_allow` has exactly the **7** addresses *(was 5; ADR-118 adds two)*:
  the four `["web-2"]` addresses + `hcloud_firewall_attachment.web`, plus
  `tls_self_signed_cert.proxy_server` (replace: delete+create) and
  `doppler_secret.proxy_tls_cert` (update-in-place). The **`-target` list is a different
  list and gains only one entry (5 → 6)**: `-target=doppler_secret.proxy_tls_cert`, which
  transitively pulls in the cert → key. **Do NOT add `-target=doppler_secret.proxy_tls_key`**
  — the key does not rotate, and naming it invites the false belief that it does.
  Two new counters mirroring `firewall_attachment_ok`: `cert_replaced` (`<= 1`,
  delete+create only) and `doppler_cert_ok` (exactly one `update`, **never `delete`** — a
  delete strips `PROXY_TLS_CERT` from Doppler `prd`). **Deliberate omission, asserted not
  assumed:** `tls_private_key.proxy_server` is **NOT** in the allow-list — it must never plan
  a change, and if it does, that is a key rotation and `web2_out_of_scope_changes` must halt.
  (`host_creates` is not tripped: that tripwire is type-scoped to `hcloud_server`/
  `hcloud_volume`.)
- **AC-B3** — Gate tests (extending `test-destroy-guard-counter-web-platform.sh`) REJECT:
  web-1 touch; non-web-2 volume destroy; server-only partial; firewall-attachment delete;
  unparseable plan; **a `doppler_secret.proxy_tls_cert` `delete` (must be `update`-only)**;
  and **any `tls_private_key.proxy_server` change (key rotation → halt)**. And ACCEPT a
  3-of-4 retry-after-partial **and a cert-replaced-but-Doppler-update-not-yet-applied
  partial** (Terraform applies sequentially and can die between the two — the `<= 1` /
  subset-not-equality shape must hold here too). Proven by test, not inspection; fixtures
  synthesized per `cq-test-fixtures-synthesized-only`.
- **AC-B4** — Reference sweep: `git grep` over the **corrected** path set diffs clean
  against the B0-captured expected hit-set. (Not "returns only historical prose" — v1's
  AC4 had no machine-checkable verdict and returned 311 hits.)
  **Second sweep, added per ADR-118 — this is the miss that created the B-GATE:** a token
  grep enumerates *mentions* and is structurally blind to *derived* coupling, which is why
  `proxy-tls.tf` (zero `web-2` literals) evaded B0's grep, AC-B4 and the measurement all at
  once. Add `git grep -n 'var\.web_hosts' apps/web-platform/infra` and diff AC-B4 against
  **that** hit-set too, auditing every dependent — not just every mention. This is
  `hr-write-boundary-sentinel-sweep-all-write-sites` in its read-side form.
- **AC-B5** — Destroy-HALT `::error::` text names `[skip-web-platform-apply]` and warns
  that `[ack-destroy]` may be partial.
- **AC-B6** — §Resolved Decision closed (**done: ADR-118, Option 1**) and its choice
  implemented — i.e. `web2_retire_allow` at 7, the `-target` list at 6, the two new
  counters, the key-rotation-halt fixture, and B0's `var.web_hosts` derivation sweep all
  landed. `proxy-tls.tf` itself must be **byte-identical to `main`** (the ruling is a
  zero-line diff to that file — if it changed, the wrong option was implemented).
  `terraform validate` clean; `terraform fmt -check` clean.
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
- **R3 — proxy-tls cert rotation.** **Resolved 2026-07-17 — ADR-118, Option 1** (§Resolved
  Decision): re-mint inside B6's supervised local apply. Mitigated by B1.4b's `cert_replaced`
  + `doppler_cert_ok` counters over the SAVED plan. The rotation is free today (proxy path
  dark) and only `PROXY_TLS_CERT` moves — not `PROXY_TLS_KEY`.
- **R3b — a SECOND `var.web_hosts`-derived coupling: `web-hosts-fanout-parity.test.sh`.**
  Same class as R3 (derived, not literal), found by review. Removing the web-2 key **red-CIs
  it** (CI-registered at `.github/workflows/infra-validation.yml:434`) — measured, not
  predicted. Handled by B3.4; see the derivation sweep at B0 step 2b.
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
