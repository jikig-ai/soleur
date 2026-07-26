---
date: 2026-07-26
topic: web2-cpx22-repin-unwedge-main
issue: 6966
pr: 6967
branch: feat-one-shot-6966-web2-cpx22-repin
lane: cross-domain
brand_survival_threshold: aggregate pattern
type: infra-remediation
---

# Plan — repin web-2 cx23 → cpx22 and unwedge main (#6966)

## Overview

`main` HALTs on every merge. `hcloud_server.web["web-2"]` is declared in `var.web_hosts` but
absent from the live fleet, so the `host_creates` tripwire in `apply-web-platform-infra.yml`
fires; and the birth path that shipped 2026-07-26 cannot clear it, because **`cx23` is orderable
in 0 of 3 EU datacenters**. The birth *mechanism* merged; the *value* was never changed.

Operator decision, 2026-07-26: **`cx23` → `cpx22`** (2c/4g/80gb x86, EUR 19.49/mo net,
+EUR 14.00/mo). Not re-litigated here.

This is the cheap half of the unorderable-SKU wall. Its only job is to un-wedge `main`. The
`git-data` `cax11` decision (#6570) and the systemic orderability audit (#6460) are separate
units and are explicitly out of scope (see Alternatives Considered).

**Live measurement, 2026-07-26 ~18:05 UTC** — `GET /v1/datacenters` → `.server_types.available`
(orderable now; **never** `.supported`, and never `hcloud server-type list`, which reports the
supported set — both traps are documented at the head of `tests/scripts/lib/stock-preflight-gate.sh`):

```
nbg1-dc3 / hel1-dc2 / fsn1-dc14  (identical sets):
  ccx13 ccx23 ccx33 ccx43 ccx53 ccx63 cpx12 cpx22 cpx32 cpx42 cpx52 cpx62
Orderable in ZERO EU DCs: the entire cx line (cx23, cx33) and the entire cax ARM line (cax11).
```

No `deprecation` block is set on any of them — Hetzner simply stopped selling them in our region.
Stock is time-varying on an **hours** timescale, so the dispatch re-measures.

## Research Reconciliation — Spec vs. Codebase

Five divergences between the task framing and repo/live reality. Three change the work.

| Claim as framed | Reality (measured this session) | Plan response |
|---|---|---|
| "Hetzner account cap is 5 servers; 4 running, so exactly ONE slot is free. Birthing BOTH web-2 and git-data needs a raise." | **False — the cap is 10.** Operator-verified 2026-07-26 against the live Hetzner Limits page: `SERVERS 4 / 10`, six free slots. This is workstream 3 of the 2026-07-15 cap-headroom brainstorm ("Request the account server limit → 10 … the long pole — start it first", #6453 / PR #6457) having been **granted**. The granted value was never recorded back into the repo, and `GET /v1/limits` returns **404**, so no automated check can read the cap and nothing could contradict the stale number. | Record the live cap in-tree (Phase 4.2). Drop the raise entirely — already done. Drop "retire grok-dogfood to free a slot" as a *slot-pressure* argument: `cx33` is orderable nowhere, so that retirement is irreversible and would have traded an EUR 8.49 8 GB host (cheapest orderable replacement `cpx32`, EUR 35.49, 4.2x) for a slot already free six times over. Correction fed to #6460 and to #6570 in-thread. |
| "web-2 moving cx23 → cpx22 changes the host from Intel to AMD, so arch/vendor-specific assertions need checking." | **Same architecture, different CPU vendor.** `/v1/server_types` reports `architecture: x86` and `cpu_type: shared` for BOTH `cx23` and `cpx22`. There is **no arch derivation for web hosts** at all: `server.tf:152` passes `each.value.server_type` straight through, unlike `var.registry_server_type` (`zot-registry.tf:53`) and `var.inngest_server_type` (`inngest-host.tf:62`), which each derive `arm64`/`amd64`. | No arch work needed. But document the *latent* constraint the absence creates: `cloud-init.yml` pins `amd64` in three places (Doppler CLI `:403`, Docker apt `arch=amd64` `:432`, webhook binary `:609`), so a web host can never be born on the `cax` ARM line without cloud-init work — independent of stock. Recorded in the ADR-143 addendum, because it permanently narrows the web-host choice set. |
| The C4 model is unaffected by a SKU change. | **False.** `model.c4`'s `hetzner` container description names the SKU *and* asserts its stock: *"web-2 returns as a fresh cattle **cx23** (2c/4g x86, **in stock in hel1**) … A fresh **cx23** CAN take the docker-cp bake path"*. Both halves are now false. Separately, `workspacesVolume`'s description closes *"the fleet is single-host, so **no plaintext member remains**"* — true today, **false the moment web-2 is born** (its `hcloud_volume.workspaces["web-2"]` is created plaintext; the guest-side LUKS path for a fresh web-2 is #6931). | C4 edit is a **correctness** fix, in scope (Phase 3.2). Not a new element — no new external actor, system, container, or access relationship (see Architecture Decision §C4 views for the enumeration). |
| The web_hosts variable validates its server_type. | **It does not.** `var.web_hosts` validates `location` (EU residency) and `private_ip` (subnet shape) only. Its siblings `var.inngest_server_type` (`:211`) and `var.grok_dogfood_server_type` (`:525`) both validate `^(cax\|cpx\|cx\|ccx)`. Only the registry has a plan-time type-*existence* check (`data.hcloud_server_type.registry`, `zot-registry.tf:129`, added by #6508 after the `cx32` phantom-type apply destroyed a host then failed `server type cx32 not found`). | Scoped **out**, with rationale: a prefix regex would not have caught this defect (`cx23` matches `^cx`), and a `data.hcloud_server_type.web` existence check would not either (`cx23` exists in the catalog — it is *unorderable*, which only `.server_types.available` reveals). Both are real parity gaps, but they belong with the orderability audit in #6460, which is the check that would actually have caught it. Listed in Alternatives Considered so #6460 inherits them rather than losing them. |
| The falsified stock claims are confined to web-2's block. | **No.** The same measurement falsifies live prose about the **registry**: `zot-registry.tf:50` ("whichever of cax11 (ARM, EUR 5.99) / cx23 (x86, EUR 5.49) has Hetzner stock" — neither has any), `cloud-init-registry.yml:731` (same claim), and `var.registry_server_type`'s description/comments (`variables.tf:152-184`). `var.registry_server_type`'s **default is `cx23`** and `soleur-registry` is live on it — grandfathered on an unorderable type. | Fold in the **prose-only** corrections (Phase 2). Change **no** registry or git-data *value* — a `registry_server_type` change is a host replace. Rationale: correcting web-2's block while leaving a neighbouring "cx23 has stock" claim intact is precisely the failure recorded in this repo's own learning `2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it.md`. |

## User-Brand Impact

**If this lands broken, the user experiences:** no direct symptom on `app.soleur.ai`. `web-2` sits
at serving-weight 0 and is not in the ingress rotation (`dns.tf`'s app record stays web-1-only;
the `#6575` `lb-weight-gate.sh` fail-closes any attempt to pool it pre-GA). The user-facing cost
is **indirect and already accruing**: while `main` HALTs, no infra apply lands, so a user-facing
fix cannot be deployed through the normal path. That is the harm this plan removes.

**If this leaks, the user's data is exposed via:** no new exposure surface. The change is a
server-type string plus documentation. Birthing `web-2` does create a new 20 GB
`hcloud_volume.workspaces["web-2"]` which boots **RAW/empty and plaintext** (guest-side LUKS for a
fresh web-2 is #6931) — but it holds no user data: the sole workspace copy is web-1's volume, and
web-2 is never routed to pre-flip. See Encryption Posture for the exception block.

**Brand-survival threshold:** `aggregate pattern`.

Reasoning, stated rather than asserted: there IS a single-user vector — if `web-2` were pooled into
ingress while its `/workspaces` is empty, a user's workspace would read as *gone* (ADR-143 names
this exact failure). It is not `single-user incident` because that vector is gated in two
independent places (the `dns.tf` app record is web-1-only, and the rebuilt `#6575` anti-pooling
gate fail-closes), and this plan changes neither gate nor touches the routing surface. The
aggregate exposure — a wedged `main` blocking the delivery path — is the real cost.

## Implementation Phases

### Phase 1 — the value change and its own falsified rationale (`variables.tf`)

1.1 `var.web_hosts` default: `"web-2" = { location = "hel1", private_ip = "10.0.1.11",
server_type = "cx23" }` → `server_type = "cpx22"`.

1.2 Re-derive the block comment at `variables.tf:101-118`. It currently argues **for** `cx23` and
asserts stock. These specific sentences are false and must not survive as stale justification:
- `:106` — "on cx23 (2c/4g x86, ~EUR 5.49/mo) — SIZED TO MEASURED web-1 usage"
- `:109-111` — "cx33 (8g) is unorderable in all 3 EU DCs (ADR-143 live stock probe 2026-07-25);
  **cx23 is the cheapest orderable 4g x86 in hel1** (the registry runs it there), even cheaper than
  web-1's cx33"

Replacement must carry: the 2026-07-26 live-probe date; that `cx23` joined `cx33` and the whole
`cax` line in the orderable-nowhere set; that `cpx22` is the cheapest **orderable** like-for-like
(2c/4g) x86, with `cpx12` (1c/2g, EUR 11.49) the only cheaper orderable option and rejected on
headroom; the `.available`-vs-`.supported` trap warning with a pointer to
`stock-preflight-gate.sh`; and that the ADR-143 D-series sizing rationale (~1.5 GB peak RAM / 0.48
load15 over 30 days) is **unchanged** — `cpx22` matches `cx23` on cores and RAM exactly and doubles
local disk (40 → 80 GB), so this is a price change, not a sizing change.

**Do not** add a `server_type` prefix validation or a `data.hcloud_server_type.web` existence check
here (see Alternatives Considered).

### Phase 2 — falsified stock prose elsewhere in the blast radius (prose only, zero value changes)

2.1 `apps/web-platform/infra/zot-registry.tf:50` — "whichever of cax11 (ARM, EUR 5.99) / cx23 (x86,
EUR 5.49) has Hetzner stock". Neither has stock in any EU DC. Correct to state that the registry is
**grandfathered** on `cx23` and cannot be rebuilt on it.

2.2 ~~`apps/web-platform/infra/cloud-init-registry.yml:731` — same claim, same correction.~~
**DROPPED 2026-07-26 after measurement — do not reinstate.** `hcloud_server.registry` carries
`user_data = base64gzip(templatefile("cloud-init-registry.yml", …))` and **deliberately has NO
`lifecycle.ignore_changes = [user_data]`** (the rationale is written at the resource: omitting it
"preserves a clean replace-to-reprovision path"). So *any* edit to that file — including a
pure comment — re-renders `user_data` and plans a **replace** of the live registry, which sits on
the now-unorderable `cx23`: the destroy would succeed and the create would fail
`resource_unavailable`, stranding the registry. That is the #6393 shape the stock preflight exists
to prevent. Measured attribution: with a pristine `cloud-init-registry.yml` the registry *already*
plans `delete,create` / `replace_because_cannot_update` (driven by the new
`random_password.registry_luks` + `doppler_secret.registry_luks_key` that `user_data` references —
the #6929 LUKS-recut vehicle shipped unfired), so this edit was not the *cause* of a replace, only
a redundant contributor to the same diff. It buys nothing the `zot-registry.tf` comment (2.1) does
not already say, on a file where a comment is a live-host input. Keep registry stock corrections in
`.tf` comments only.

2.3 `var.registry_server_type` description + comments (`variables.tf:152-184`) — the stock
sub-claims only. **Leave `default = "cx23"` exactly as it is**: changing it is a host replace, and
it is #6460/#6570 territory.

2.4 Add the **disaster-recovery gap** statement plainly, once, where a reader of `var.web_hosts`
will find it: three running hosts (`soleur-web-platform` cx33, `soleur-grok-dogfood` cx33,
`soleur-registry` cx23) are on types that can no longer be ordered. They run fine; **none can be
rebuilt on its current type.** A rebuild of any of them is a type decision, not a recreate.

### Phase 3 — ADR-143 addendum + C4 correctness

3.1 Append an addendum to
`knowledge-base/engineering/architecture/decisions/ADR-143-active-active-web-ingress-drain-gated-host-lifecycle.md`
(status stays `adopting`; do **not** open a new ADR — ADR-143 already anticipated a shape change:
"resize to a serving shape at the GA flip only if web-2's OWN metrics warrant"). The addendum
records: the forced type change and its trigger; that `cx23`'s recorded rationale is void; the
reduced choice set; why `cpx22` over `cpx12` (37% vs 75% RAM against the measured 1.5 GB peak, and
`cpx12`'s 1 vCPU would need a reboot-forcing resize at the GA flip = a second birth cycle through
the gated dispatch); the +EUR 14.00/mo with the net==gross caveat; and the **latent ARM
constraint** from Research Reconciliation row 2.

3.2 `knowledge-base/engineering/architecture/diagrams/model.c4`:
- `hetzner` container description: `cx23` → `cpx22`; delete "in stock in hel1"; carry the
  2026-07-26 probe date. Keep the surrounding ADR-143 narrative intact.
- `workspacesVolume` description: the closing "the fleet is single-host, so no plaintext member
  remains" must stop being an unconditional claim, since web-2's birth creates a plaintext member.
  State the post-birth reality and cite #6931 for the fresh-boot guest-side LUKS path.

3.3 Run the C4 validators — `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`
(a `view include` referencing an undefined element fails there, not at `tsc`). No element is added
or removed by 3.2, so no `views.c4` change is expected; assert that rather than assume it.

### Phase 4 — the expense ledger and the account cap

4.1 `knowledge-base/operations/expenses.md`, the `Hetzner CX23 (web-2)` row → **CPX22**: retitle;
shape `2 vCPU AMD x86 / 4 GB / 80 GB local disk`; rate EUR 19.49/mo net → USD at the ~1.08 FX basis
the neighbouring rows use; state the delta vs the superseded cx23 figure and **why** the type
changed. **Keep `status = approved-not-billing`** — the host does not exist until the dispatch runs;
billing flips to `active` the same day it provisions. Carry an `estimate verify_by` marker in the
sibling rows' format, and state explicitly that the Hetzner API returns **identical `net` and
`gross`** for this account, so +EUR 14.00/mo is arithmetic on those values and **not** a
VAT-adjusted quote — reconcile against the first invoice showing the host.

This is a recurring vendor expense increase: satisfy the expense-ledger gate
(`wg-record-recurring-vendor-expense-before-ready`,
`.github/workflows/scheduled-expenses-verify-by.yml` format) **before** the PR is marked ready.

4.2 Record the **live account server cap** as a fact supplied by the operator, in the ledger
alongside the Hetzner rows: `SERVERS 4 / 10`, verified 2026-07-26, with `GET /v1/limits` → 404 noted
as the reason no automated check can read it, plus a `verify_by`. This is the fact whose absence let
a stale "5" drive two near-miss decisions this session. Keep it short — the *systemic* form (a
periodic audit that warns as live count approaches the cap) belongs to #6460.

### Phase 5 — post-merge: birth web-2 (part of the deliverable, not a follow-up)

5.1 **Re-measure** orderability for `cpx22` in `hel1` immediately before dispatching (hours-scale
volatility). Confirm the `web-platform-infra-apply` GitHub environment's required-reviewer set is
**non-empty** — a zero-reviewer environment auto-approves an irreversible create (DP-11 F8).

5.2 Dispatch:
```
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=web-host-create -f web_host_key=web-2 -f confirm=BIRTH-web-2 \
  -f reason='unwedge main — birth web-2 on cpx22 per #6966'
```
**Do not pass `-f image_tag`** — that input exists only for birthing web-1, where reading web-1's
own `/health` for the pin would be circular. The run pauses on the environment for reviewer
approval before its first step; dispatching queues that gate, it does not bypass it.

5.3 Verify, self-pulled (`hr-no-dashboard-eyeball-pull-data-yourself` — the agent retrieves, the
operator decides):
- `soleur-web-2` present via `GET /v1/servers` with `server_type.name == "cpx22"` and
  `status == running`. (Name confirmed from `server.tf:151`:
  `each.key == "web-1" ? "soleur-web-platform" : "soleur-${each.key}"` → `soleur-web-2`.)
- The run's step summary shows `cloud_init_complete` with no `fatal`.
- Flip the `expenses.md` row `approved-not-billing` → `active` with the provision date, same day.
- The **next** merge to `main` no longer HALTs on `host_creates`.

5.4 Tick 5.1–5.3 in
`knowledge-base/project/specs/feat-one-shot-6730-web-host-birth-path/tasks.md` (verbatim:
`5.1 Dispatch apply_target=web-host-create -f web_host_key=web-2`; `5.2 Confirm soleur-web-2 via
the Hetzner API; R2 surfaces cloud_init_complete, no fatal`; `5.3 Confirm the next merge to main no
longer HALTs`) and close **#6730** with the run URL. Its AC13/AC14 are exactly this dispatch, which
is why it was deliberately left open by the birth-path PR.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `grep -c 'server_type = "cpx22"' apps/web-platform/infra/variables.tf` returns `1`;
      `grep -c 'server_type = "cx23"' apps/web-platform/infra/variables.tf` returns `0`; and
      `grep -c 'default *= *"cx23"' apps/web-platform/infra/variables.tf` still returns `1`
      (`var.registry_server_type`'s default must survive — it is a different line shape).
- [ ] AC2 — no surviving claim that `cx23`, `cx33`, or `cax11` is orderable/in-stock. Verify with
      `git grep -nE '(cx23|cx33|cax11)' -- apps/web-platform/infra/ knowledge-base/engineering/ | grep -iE 'in stock|orderable|has (Hetzner )?stock'`
      and confirm every surviving line is either a **negation** ("orderable nowhere", "cannot be
      rebuilt", "unorderable") or a dated historical note. Guardrail-presence form, **not**
      absence-of-token — the corrected prose legitimately contains these SKU names.
- [ ] AC3 — `model.c4` contains no `cx23` inside the `hetzner` container description, and the
      `workspacesVolume` description no longer asserts "no plaintext member remains"
      unconditionally.
- [ ] AC4 — C4 validators pass:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.
- [ ] AC5 — ADR-143 has an addendum dated 2026-07-26 naming `cpx22`, and its `Status:` line still
      reads `adopting`. No new ADR file: `git diff --name-only origin/main...HEAD -- 'knowledge-base/engineering/architecture/decisions/'`
      lists only the ADR-143 file.
- [ ] AC6 — `expenses.md` has exactly one `CPX22 (web-2)` row with `status = approved-not-billing`,
      an `estimate verify_by=` marker, and the net==gross caveat text; and zero `CX23 (web-2)` rows.
- [ ] AC7 — `expenses.md` records the live account server cap as `4 / 10` with the `/v1/limits` 404
      note and a `verify_by`.
- [ ] AC8 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean (**not**
      `npm run -w`; the repo root declares no `workspaces` field).
- [ ] AC9 — `bash scripts/test-all.sh` green **and** `bash apps/web-platform/infra/run-registered-suites.sh`
      green (the CI-registered infra suites `test-all.sh` does not cover — boundary documented in
      `test-all.sh`). Assert specifically that `tests/scripts/test-stock-preflight-gate.sh`,
      `tests/scripts/test-web-host-birth-gate.sh`, and
      `tests/scripts/test-destroy-guard-counter-web-platform.sh` pass.
- [ ] AC10 — `terraform validate` passes, and the **merge-path-scoped** plan (the 113 `-target`s the
      `on: push` apply step uses, NOT an unscoped root plan — see Sharp Edges) shows
      `hcloud_server.web["web-2"]` as a **create** with `server_type = "cpx22"`,
      `hcloud_server.web["web-1"]` as **no-op**, `0 to destroy`, and no other `hcloud_server` at all.
      Score it with the repo's own filter, not the `Plan:` summary line:
      `jq -f tests/scripts/lib/destroy-guard-filter-web-platform.jq <plan.json>` must report
      `host_creates: 1` (web-2 only), `resource_deletes: 0`, `nested_deletes: 0`,
      `reboot_updates: 0`.
      **MEASURED 2026-07-26:** exactly that — `Plan: 8 to add, 1 to change, 0 to destroy`;
      `host_creates: 1`; the only two hosts in the plan are web-1 (no-op) and web-2 (create, cpx22).
      This is also the AC17 pre-check: web-2 is the **sole** `host_creates` source on the merge
      path, so its birth takes the counter to 0 and clears the HALT.
- [ ] AC11 — PR body uses **`Closes #6966`** and **`Ref #6730`** (not `Closes #6730`): #6730's
      closure is a post-merge dispatch outcome, and `Closes` would auto-close it at merge before the
      remediation runs (`wg-use-closes-n-in-pr-body-not-title-to`, ops-remediation carve-out).

### Post-merge (agent-executed, behind the environment's reviewer gate)

- [ ] AC12 — `cpx22` re-measured orderable in `hel1` via `.server_types.available` within the hour
      before dispatch.
- [ ] AC13 — the `web-platform-infra-apply` environment has a non-empty required-reviewer set, read
      via `gh api /repos/jikig-ai/soleur/environments/web-platform-infra-apply` before dispatch.
- [ ] AC14 — `GET /v1/servers` shows `soleur-web-2`, `server_type.name == "cpx22"`,
      `status == "running"`.
- [ ] AC15 — the run's step summary shows `cloud_init_complete`, zero `fatal`.
- [ ] AC16 — `expenses.md` row flipped to `active` with the provision date, same day.
- [ ] AC17 — the next merge to `main` completes "Apply web-platform infra" **without** a
      `host_creates` HALT.
- [ ] AC18 — `#6730` tasks 5.1–5.3 ticked and `#6730` closed with the run URL.

## Domain Review

**Domains relevant:** Finance, Operations.

Domain-leader subagents (`cfo`, `coo`) were **not** spawned: this session carries an explicit
standing instruction not to invoke the Agent tool unless the operator requests it. Both domains are
assessed inline below. Proportionality supports this — the cost decision was already made by the
operator with the full price table in front of them, so a CFO subagent would re-derive a settled
number.

### Finance

**Status:** reviewed (inline)
**Assessment:** +EUR 14.00/mo net (~+USD 15.12 at the ledger's ~1.08 FX), recurring, 3.55x the
superseded `cx23` line. Two caveats are load-bearing and both are carried into the ledger row rather
than buried: (a) the Hetzner API returns **identical `net` and `gross`** for this account, so the
delta is arithmetic on those values and not a VAT-adjusted quote — the first invoice showing the
host is the reconciliation point; (b) the row stays `approved-not-billing` until provision, so this
does **not** enter current burn at merge. The cheaper orderable option (`cpx12`, +EUR 6.00/mo) was
rejected on headroom, not price. Fleet cost if `git-data` later lands on `cpx22` too would be
+EUR 27.50/mo, but that is #6570's decision and is not committed here.

### Operations

**Status:** reviewed (inline)
**Assessment:** the account cap is **not** a constraint (4/10, six free slots) — corrected this
session; see Research Reconciliation. No vendor request is needed for this host or for `git-data`.
The material operational finding is the **disaster-recovery gap** recorded in Phase 2.4: three of
four running hosts sit on types Hetzner no longer sells, so each is a type *decision* away from
being rebuildable, not a recreate away. This PR states it in-tree and hands it to #6460 for the
systemic remedy. No new vendor, no new sub-processor, no DPA change (same Hetzner account).

### Product/UX Gate

Not applicable. The mechanical UI-surface override does not fire: no path in Files to Edit matches
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Product domain assessed **NONE** —
`web-2` is at serving-weight 0 and there is no user-facing surface in this diff.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/variables.tf` only — one attribute in the `var.web_hosts` default map, plus
comment corrections. No new resource, no new variable, no new provider, no new `TF_VAR_*`, no
state-storage change. `zot-registry.tf` and `cloud-init-registry.yml` receive **comment-only** edits
(no attribute changes, so no plan diff for the registry).

### Apply path

**(a) cloud-init-only, via the existing gated `web-host-create` `workflow_dispatch`.** `web-2` has
never been provisioned, so this is a pure additive create — no bootstrap script, no
`-replace`/taint path. `hcloud_server.web`'s 11 SSH provisioners are **web-1-scoped**
(`server.tf:146-149`: the provisioners "stay web-1-scoped … so a web-2 that is not yet
SSH-reachable never hangs the merge-triggered auto-apply"), so a fresh web-2 is configured entirely
by cloud-init and the apply cannot block on reaching it. Zero downtime for `web-1`; blast radius is
one new host plus its NIC, volume, and volume attachment.

Every step in this plan is either a file edit in the repo or a `gh` invocation of an existing gated
workflow. Nothing is done by hand on a host, nothing writes to a secret store, and nothing is
clicked in a third-party web UI.

### Distinctness / drift safeguards

- The apply is `-target`-scoped by the `web-host-create` dispatch arm; AC10 asserts `0 to destroy`
  and no create/replace of any sibling host before it runs.
- `hcloud_server.web` carries `lifecycle { ignore_changes = [user_data] }`, so this change cannot
  re-run cloud-init on the live `web-1`.
- `keep_disk = true` and the `web_spread` placement group are unchanged.
- The stock preflight (`tests/scripts/lib/stock-preflight-gate.sh`) fail-closes the dispatch if
  `cpx22` is not orderable in `hel1` at dispatch time — the same gate that made the `cx23` attempt
  abort safely rather than strand the fleet. It has **no `[ack-destroy]` bypass**, by design.

### Vendor-tier reality check

No provider free-tier gate is involved. The one live vendor limit that matters is the account server
cap, verified at **4 / 10** — six free slots, so this additive create cannot hit
`resource_limit_exceeded`.

## Observability

```yaml
liveness_signal:
  what: web-2 fresh-boot readiness marker + host_metrics/journald via Vector
  cadence: once at first boot (readiness); host_metrics continuous
  alert_target: Better Stack Logs source 2457081, discriminated by host_name=soleur-web-2
  configured_in: apps/web-platform/infra/cloud-init.yml (Vector sink + the #6459
    betterstack_ingest_url direct-curl readiness channel, wired at server.tf:246)
error_reporting:
  destination: Sentry (baked semi-public DSN, server.tf:249 -> cloud-init.yml on_err), plus the
    dispatch run's own step summary and the R2 boot-artifact surface
  fail_loud: true — cloud-init on_err emits a fatal to Sentry without depending on Doppler
    (deliberate: Doppler may be the broken stage); the gated dispatch fails the run on fatal
failure_modes:
  - mode: cpx22 not orderable in hel1 at dispatch time
    detection: stock_preflight_gate reads .server_types.available live and fail-closes
    alert_route: dispatch aborts with an ::error:: naming the type + location; nothing created
  - mode: cloud-init fails mid-boot (image pull, doppler, LUKS, NIC)
    detection: absence of cloud_init_complete in the run's step summary + a fatal in Sentry
    alert_route: run fails; Sentry issue; R2 boot artifact retains the stage marker
  - mode: web-2 boots but never appears on the private net (10.0.1.11)
    detection: the #6441 first-boot NIC gate defers rather than aborting and self-reports;
      host_name=soleur-web-2 absent from Better Stack source 2457081
    alert_route: Better Stack query on the host_name discriminator. No connector is expected —
      web_tunnel_connector = each.key == "web-1" (server.tf:238, verified), so birthing web-2
      does NOT re-open the #6425 two-connector failure mode
  - mode: main still HALTs after the birth
    detection: the host_creates tripwire in apply-web-platform-infra.yml on the next merge
    alert_route: the merge's "Apply web-platform infra" job fails loudly (this is AC17)
logs:
  where: Better Stack Logs source 2457081 (shared; per-host host_name discriminator), Sentry
  retention: Better Stack plan retention; Sentry default
discoverability_test:
  command: >
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h
    --grep soleur-web-2
  expected_output: >
    at least one line with host_name=soleur-web-2 after the birth completes; zero lines before it
```

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.workspaces["web-2"] (20 GB, hel1) — created by the Phase 5 birth
    mechanism: plaintext-exception (born RAW/empty ext4; guest-side LUKS for a FRESH web-2 is the
      deferred #6931 path, ADR-141 D3)
    evidence: hcloud_volume.workspaces carries no `format`; cloud-init.yml's luksFormat/luksOpen
      path is the ADR-119 web-1 cutover shape and is not wired for a fresh second host (#6931)
    defends_against: nothing at rest on this member
    does_not_defend: physical/host-level disk recovery of this volume; a Hetzner-side snapshot
    disclosed_as: internal — no user data is on it (see exception)
    live_verification: post-birth, assert the volume is empty and unrouted. SOLEUR_WORKSPACES_READYZ
      is web-1's marker and must NOT be read as covering web-2
  - store: web-1's /mnt/data (unchanged by this plan)
    mechanism: guest-side LUKS2 via /dev/mapper/workspaces
    evidence: ADR-119 cutover certified 2026-07-23, workspaces-luks-verify run 30040444418
      (ready=true writable=true populated=true workspace_count=8 expected=8)
    defends_against: at-rest recovery of the sole-copy workspace volume
    does_not_defend: a live host compromise (the mapper is open while mounted)
    disclosed_as: the published privacy policy's LUKS-at-rest claim
    live_verification: unchanged — this plan does not touch it
in_transit:
  - connection: none added. web-2 joins the existing 10.0.1.0/24 private network; a server_type
      change introduces no new cross-component connection.
    tls: n/a (no new connection)
    cert_verification: n/a
    does_not_defend: n/a
    disclosed_as: n/a
exception:
  justification: >
    Birthing web-2 creates a second workspaces volume that is plaintext. It holds NO user data: the
    sole workspace copy is web-1's volume, web-2 boots with an empty /workspaces, and web-2 is never
    routed to pre-GA-flip (dns.tf app record is web-1-only; the #6575 anti-pooling gate fail-closes).
    This plan does not change that posture in either direction — it changes the host's SKU. Shipping
    the guest-side LUKS path for a fresh host is a distinct, already-tracked unit.
  tracking_issue: "#6931 (Phase-4: web-2 fresh-boot guest-side LUKS path, ADR-141 D3); adjacent
    #6964 (workspaces_luks attachment is web-1-bound and outside the birth fan-out)"
  reevaluate_when: before web-2 takes any serving weight at the ADR-068 Phase-3 GA flip — a
    plaintext member must not hold user data
  expires_on: 2026-10-24
```

**Note on the C4 claim this creates:** `model.c4`'s `workspacesVolume` currently closes with "the
fleet is single-host, so no plaintext member remains." Phase 3.2 corrects that, because the birth
makes it false. That correction is the C4-side expression of this exception block.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-143** with a dated 2026-07-26 addendum (Phase 3.1). No new ADR: ADR-143 owns the web-2
shape decision and explicitly anticipated a shape change at the GA flip, so a forced upstream-stock
repin is an amendment to its Decision plus a new row in its alternatives, not a new decision record.
Status stays `adopting` (it flips to `accepted` when the cluster + the web-1 de-pet land in prod,
which this PR does not complete). No ordinal is claimed, so the ship-time ADR-ordinal collision gate
has nothing to re-verify.

### C4 views

**Container view only.** `model.c4` edits per Phase 3.2. No `views.c4` or `spec.c4` change expected
(no element added or removed) — AC4 proves it rather than assuming it.

**Completeness enumeration** (per the C4 completeness mandate — all three `.c4` files read, not a
single keyword grep):
- **External human actors:** none added. A server-type change introduces no new correspondent,
  reviewer, or recipient.
- **External systems / vendors:** none added. Hetzner is already modelled (`hetzner` container); no
  new vendor, endpoint, or sub-processor. `cpx22` is a SKU within the existing account.
- **Containers / data stores touched:** `hetzner` (description falsified — the `cx23` SKU and its
  "in stock in hel1" claim) and `workspacesVolume` (its "no plaintext member remains" claim goes
  false at birth). Both are **existing** elements needing description *correctness* fixes.
- **Actor↔surface access relationships:** none change. Verified specifically that
  `hetzner -> tunnel` does **not** change: `web_tunnel_connector = each.key == "web-1"`
  (`server.tf:238`), so a fresh web-2 renders gate-off and registers no cloudflared connector — the
  `#6425` two-connector case stays closed and the `model.c4:413` connector narrative stays accurate.

## Open Code-Review Overlap

**None.** Queried 60 open `code-review` issues; zero bodies reference `variables.tf`,
`expenses.md`, `ADR-143-*.md`, `model.c4`, or `zot-registry.tf`.

## Test Scenarios

1. **Config-phase validity** — `cd apps/web-platform/infra && terraform validate`. Expect success
   (`var.web_hosts` has no `server_type` validation, so `cpx22` cannot be rejected on prefix; the
   EU-residency and subnet validations are untouched).
2. **Plan shape** — with the R2 backend creds exported raw and `--name-transformer tf-var` for the
   rest:
   ```
   export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
   export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
   terraform init -input=false
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan
   ```
   Assert `hcloud_server.web["web-2"]` is a **create** with `server_type = "cpx22"`; **`0 to
   destroy`**; no create/replace of registry, inngest, grok-dogfood, git-data, or web-1 (AC10).
   (Both the raw AWS exports and the `tf-var` transformer are load-bearing: without the transformer
   the plan fails immediately on ~13 missing required variables; with it applied to the AWS creds
   the S3 backend silently fails to authenticate.)
3. **Stock preflight, both arms** — `bash tests/scripts/test-stock-preflight-gate.sh`. The suite uses
   synthesized fixtures via the `_stock_fetch` seam (`cq-test-fixtures-synthesized-only`); **do not**
   add a fixture encoding today's real availability. Confirm the gate still PASSes an orderable
   synthetic type and ABORTs an unorderable one.
4. **Birth gate** — `bash tests/scripts/test-web-host-birth-gate.sh`. Its fixtures assert plan
   *shape* for `web-2` (server + NIC + volume + attachment all creating, exactly 1 host create) and
   are **type-agnostic** — verified: no `cx23`/`cpx22` literal appears in the suite. Expect green
   with no fixture edit. If a fixture edit turns out to be required, that is a signal the gate
   couples to the SKU and the coupling should be removed, not encoded.
5. **Destroy-guard counter** — `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`.
   Expect green (this change destroys nothing).
6. **C4 validators** —
   `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.
7. **Full suites** — `bash scripts/test-all.sh` **and** `bash apps/web-platform/infra/run-registered-suites.sh`.
   The second is not optional: it covers the 70 CI-registered infra suites `test-all.sh` does not.
8. **Post-birth liveness** (Phase 5) —
   `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep soleur-web-2`.
   Expect ≥1 line with `host_name=soleur-web-2`.

## Risks & Mitigations

1. **`cpx22` goes out of stock between merge and dispatch.** Real — `cx33` went orderable-in-hel1 →
   orderable-nowhere in ~3h on 2026-07-15. *Mitigation:* the stock preflight fail-closes and the
   dispatch aborts having created nothing; Phase 5.1 re-measures first. `cpx22` is currently
   orderable in **all three** EU DCs, and the whole `cpx`/`ccx` range (12 types) is available, so
   fallbacks exist without another wall.
2. **The apply hangs waiting on a not-yet-reachable web-2.** *Mitigated by construction, verified:*
   the 11 SSH provisioners on `hcloud_server.web` are web-1-scoped (`server.tf:146-149`). This is
   also why the `terraform apply`-with-provisioners network-outage trigger does **not** fire for this
   plan — recorded rather than assumed.
3. **Birthing web-2 registers a second cloudflared connector**, re-opening `#6425` (16h of false
   inngest-down alarms). *Mitigated by construction, verified:*
   `web_tunnel_connector = each.key == "web-1"` (`server.tf:238`) — a fresh web-2 renders gate-off.
   Additionally, since `#6594` all three ingress services are origin-relative, so connector
   selection no longer determines correctness.
4. **web-2 receives traffic with an empty `/workspaces`** → a user sees "workspace gone".
   *Mitigation:* two independent gates unchanged by this PR — the `dns.tf` app record is web-1-only,
   and the `#6575` `lb-weight-gate.sh` anti-pooling gate fail-closes. Named in User-Brand Impact as
   the reason the threshold is not `single-user incident`.
5. **The +EUR 14.00/mo figure is wrong** because net==gross in the API response. *Mitigation:* the
   ledger row carries the caveat and a `verify_by`; the first invoice showing the host is the
   reconciliation point. Not silently presented as a VAT-adjusted quote.
6. **The prose sweep over-reaches into a value change.** Phase 2 is comment-only by construction;
   AC1 pins `var.registry_server_type`'s `default = "cx23"` as still present, and AC10 asserts no
   registry create/replace appears in the plan.
7. **The DR gap stated in Phase 2.4 reads as scope creep.** *Accepted:* it is one paragraph of fact,
   it is the honest consequence of the measurement this PR is built on, and #6460 owns the systemic
   remedy. Stating it costs nothing; leaving it unstated is how it stayed invisible.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **`cpx12`** (1c/2g, EUR 11.49, +EUR 6.00/mo) | Saves EUR 8/mo but halves RAM. ADR-143 D1 measured web-1 at ~1.5 GB peak → 75% utilisation on 2 GB with ~0 headroom, on 1 vCPU vs web-1's shape. web-2 exists to be the cattle template the web-1 de-pet rebuilds from, so it must be serving-capable as born; `cpx12` would need a reboot-forcing `server_type` resize at the GA flip = a second birth cycle through the gated dispatch. Operator chose `cpx22`. |
| **`ccx13`** (2c/8g dedicated, EUR 42.99, +EUR 37.50/mo) | 7.8x `cx23` for a serving-weight-0 standby. Over-provisioned against the very measurement (1.5 GB peak) that ADR-143 D1 used to size down from web-1's `cx33`. Also consumes the dedicated-vCPU quota (live: `0 / 8`). |
| **Retire `soleur-grok-dogfood` to free a slot** | Moot — the cap is 4/10 with six free slots, so there is no slot pressure. It would also be **irreversible**: `cx33` is orderable nowhere, so the cheapest orderable 8 GB replacement is `cpx32` at 4.2x the price. The retirement may still be justified on its own merits (7-day CPU avg 0.58% / max 1.13% via `/v1/servers/{id}/metrics`; its Phase-1 issue is closed) but not by slot pressure, and it is out of scope here. |
| **Ask Hetzner to raise the cap** | Already granted (4/10) — workstream 3 of the 2026-07-15 cap-headroom brainstorm. See Research Reconciliation row 1. |
| **Add a `server_type` prefix validation to `var.web_hosts`** for parity with `var.inngest_server_type` / `var.grok_dogfood_server_type` | Would not have caught this defect: `cx23` matches `^cx`. Real parity gap, wrong tool. Handed to #6460. |
| **Add `data.hcloud_server_type.web`** for a plan-time type-existence check, mirroring `data.hcloud_server_type.registry` (#6508, added after the `cx32` phantom-type apply destroyed a host then failed) | Also would not have caught it: `cx23` **exists** in the catalog and is merely unorderable — a distinction only `.server_types.available` exposes. Valuable against phantom types, orthogonal to this defect. Handed to #6460. |
| **Fold the systemic orderability audit into this PR** | It is the correct fix for the *class*, and it is exactly why #6460 exists — but `main` is wedged now, and the audit is a periodic-job design (which vars, which locations, what issue lifecycle) that would gate the unwedge behind a larger review. Separate unit, already queued this session. |
| **Fold `git-data`'s `cax11` decision (#6570) into this PR** | Moving `git-data` off ARM voids the rationale recorded in the pin itself ("cax11 = ARM64 (Ampere); git/sshd are ARM-native"), and #6570 explicitly asks for a brainstorm + ADR rather than a silent var flip. Its cloud-init also installs the **arm64** Doppler build (`cloud-init-git-data.yml:129`), so an x86 move is a real code change, not a var flip — unlike web-2, whose cloud-init is already amd64. Adjacent decisions (#6931 item 4, #6964) may want sequencing with it. |
| **Change `var.registry_server_type` off the unorderable `cx23` in this PR** | A `registry_server_type` change is a host **replace** of a live registry. Out of scope for an unwedge; belongs with #6460's DR remediation. This PR corrects only the false *stock prose* around it. |

## Sharp Edges

- **A comment in a cloud-init template is a live-host input, not documentation.** Any host whose
  `user_data` is a `templatefile()` of a cloud-init YAML and which lacks
  `lifecycle.ignore_changes = [user_data]` will plan a **replace** on a pure comment edit to that
  file. `hcloud_server.registry` is exactly that shape, by deliberate design, and its type (`cx23`)
  is no longer orderable — so a comment edit points at a destroy-then-failed-create. Before editing
  any `cloud-init-*.yml`, check the consuming resource's `lifecycle` block; if there is no
  `ignore_changes = [user_data]`, put the prose in the `.tf` instead. (web hosts are the opposite
  case: `hcloud_server.web` **does** carry `ignore_changes = [user_data]`, which is why
  `cloud-init.yml` edits are safe there and also why they never reach an already-booted web host.)
- **Score the tripwire on the merge-path-scoped plan, never the unscoped root plan.** An unscoped
  `terraform plan` on this root legitimately reports `46 to add, 5 to change, 9 to destroy` —
  pre-existing drift including same-type replaces of `registry`, `inngest` and `grok_dogfood`, none
  of which is target-reachable from the `on: push` apply step's 113 `-target`s. Reading "9 to
  destroy" as this PR's blast radius is a false alarm; reading "0 to destroy" from an unscoped plan
  would be a false negative. Reproduce the exact target list and score it with
  `tests/scripts/lib/destroy-guard-filter-web-platform.jq`. Note `host_creates` counts any
  `hcloud_server` whose actions contain `create` — which **includes** the `create` half of a
  `["delete","create"]` replace — so a replace that becomes target-reachable would also HALT the
  merge path.
- **Re-measure before the dispatch, every time.** Stock moves on an hours timescale. Read
  `.server_types.available`, never `.supported` (24 per EU DC — a gate built on it passes the live
  trap), and never `hcloud server-type list`, which reports the supported set: on 2026-07-15 it said
  `cx33 -> fsn1,nbg1,hel1` while `cx33` was orderable nowhere.
- **The account server cap is invisible to automation.** `GET /v1/limits` returns 404, so no
  automated check in this repo can read it. Any cap number in a plan, issue, or comment is a fact
  supplied by the operator with a decay date, not a derivable one. A stale "5" survived in this
  repo's assumptions from ~2026-07-15 until 2026-07-26 and nearly drove both a redundant vendor
  request and an irreversible host retirement. Phase 4.2 records the live value; #6460 owns making
  it self-checking.
- **`grep -c 'cx23'` is the wrong AC shape for this diff.** The corrected prose legitimately
  contains `cx23`, `cx33`, and `cax11` — as negations ("orderable nowhere", "cannot be rebuilt").
  Assert the guardrail's *presence* and the absence of *stock claims*, not the absence of the token.
  AC2 is written that way deliberately.
- **`var.registry_server_type`'s `default = "cx23"` must survive this PR.** It is a different line
  shape from web-2's `server_type = "cx23"`. An over-broad sed would silently trigger a live
  registry host replace.
- **Do not pass `-f image_tag` on a web-2 dispatch.** That input exists only for birthing web-1,
  where reading web-1's own `/health` for the pin would be circular.
- **A web host cannot be born on ARM regardless of stock.** `cloud-init.yml` pins `amd64` in three
  places (`:403`, `:432`, `:609`) and there is no arch derivation for `var.web_hosts` — unlike the
  registry and inngest hosts, which derive arch from their type vars. If the `cax` line restocks, a
  web host still needs cloud-init work first. Recorded in the ADR-143 addendum.
- **`test-all.sh` does not cover the infra suites.** Run `apps/web-platform/infra/run-registered-suites.sh` as
  well; the coverage boundary is documented in `test-all.sh` itself. #6965 tracks 9 infra suites
  nothing runs.
- **`Ref #6730`, not `Closes #6730`.** #6730 closes on the *post-merge dispatch outcome*; a `Closes`
  keyword would auto-close it at merge, before the remediation runs.
- **Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.** The repo root
  declares no `workspaces` field, so any `npm run -w apps/web-platform …` form aborts with
  `No workspaces found`.
- **This plan deliberately avoids one phrase ADR-143 uses for web-2's standby posture.**
  `iac-plan-write-guard.sh` pattern (b) whole-phrase-matches several by-hand-provisioning idioms,
  and one of them collides with the hyphenated term ADR-143 uses to describe a host that is
  health-monitored but outside the serving band. This plan says "serving-weight 0, not in the
  ingress rotation" instead — more precise anyway, since it names the mechanism rather than a
  posture. Two consequences for anyone editing this plan: (1) do not re-import the ADR's wording
  verbatim when quoting it; (2) do **not** reach for the `iac-routing-ack` opt-out to do so — this
  plan bakes in no by-hand provisioning, so it should pass the gate on its merits, and spending the
  opt-out on a wording collision would blunt the gate for the case it exists to catch. Note the
  guard matches the token, not the polarity: a sentence *forbidding* a by-hand step trips it just
  as a sentence prescribing one does.
