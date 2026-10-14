---
date: 2026-07-16
topic: web-2 disposition — retire the fsn1 orphan, unblock active-active
issues: [6538, 6463]
related: [6393, 6453, 6457, 6459, 6460, 6497]
lane: cross-domain
brand_survival_threshold: single-user incident
status: decided
---

# Brainstorm — web-2 disposition (#6538, #6463)

## What We're Building

**Retire `soleur-web-2`.** Remove it from `var.web_hosts`, destroy the host and its
(empty) 20 GB volume via a guarded destroy path, and correct the two registers that
describe it inaccurately (Art. 30 register, expense ledger). Re-birth a second web host
in `hel1` **inside** `hcloud_placement_group.web_spread` when the active-active work
(ADR-068 §(c) chain) actually starts.

This is **not** the fix #6538 proposed. #6538 asked which of two ways to make web-2
recreatable. The measured answer is that web-2 should not exist in its current shape at
all, and cannot ever be part of the operator's stated target topology.

## Why This Approach

Every fact below was measured live (Hetzner API, Better Stack ClickHouse) or read from
code in this worktree — not inferred from the issue body.

### The issue's premise was substantially wrong

| #6538 claim | Verdict |
|---|---|
| web-2 unrebuildable (cx33 not orderable in fsn1) | **Confirmed** — cx33 orderable only in `hel1-dc2` |
| web-2 ships zero telemetry | **Confirmed** — 0 lines/24h vs web-1's 17,987 |
| web-2 is "outside the HA placement group" | **Misframed** — the group is EMPTY; web-1 is outside it too |
| fsn1 was "a stock workaround [that] became permanent" | **False** — deliberate, PR #6393 |
| "Is the volume disposable?" is the load-bearing question | **Moot** — the volume is empty; and it only force-replaces on a *location* change |

`variables.tf` records the fsn1 placement as intentional — *"web-2 sits in a DIFFERENT DC
from web-1's hel1 (DC-failure resilience)"* — and PR #6393 is titled *"relocate warm-standby
web-2 hel1→fsn1 (cross-DC HA)"*, merged 2026-07-13, **three days before #6538 was filed**.
#6538 quotes the first line of the `server.tf` comment (*"Spread across distinct physical
hosts within the EU location (HA)"*) but not the four lines below it that call the null
placement group deliberate.

### The decisive fact: web-2 can never join the target topology

`server.tf` gates placement-group membership on co-location with web-1:

```hcl
placement_group_id = each.value.location == var.web_hosts["web-1"].location ? hcloud_placement_group.web_spread.id : null
```

and then:

```hcl
lifecycle {
  ignore_changes = [user_data, ssh_keys, image, placement_group_id]
}
```

`placement_group_id` is **create-time only**. A host cannot be added to the group after
birth. Live state confirms the consequence: `soleur-web-spread` exists with `servers=[]`
— **web-1 is not in it either**, and never can be without a recreate.

Therefore any real active-active host must be **born** in `hel1` inside the group. web-2
(fsn1) must be destroyed and re-born regardless of what we do today. Paying to make the
wrong-shaped host recreatable buys nothing.

### The cost of the alternative is real

Live pricing (Hetzner API, 2026-07-16):

| type | cores | RAM | disk | €/mo | orderable in fsn1 |
|---|---|---|---|---|---|
| cx33 (current) | 4 shared | 8 GB | 80 GB | **8.49** | ❌ |
| cpx32 | 4 shared | 8 GB | 160 GB | **35.49** | ✅ |
| ccx13 | 2 dedicated | 8 GB | 80 GB | 42.99 | ✅ |

`cpx32` is the **cheapest ≥8 GB machine fsn1 will sell** — there is nothing between €8.49
and €35.49. So keeping web-2 cross-DC costs **+€27/mo (+€324/yr, +47% of all Hetzner
spend)** for a host that still cannot serve.

### Stock is the real root cause — and it is fleet-wide

`cx33` is orderable in **exactly one datacenter on Earth** (`hel1-dc2`) and was orderable
in **zero** for a window on 2026-07-15. The `stock-preflight-gate.sh` header records the
trap: *"`.supported` … is what a DC can host; `.server_types.available` is what is orderable
right now"*, and *"cx33 went from 'orderable in hel1' to orderable in ZERO datacenters
within ~3h on 2026-07-15"*.

**web-1 carries the identical fragility** — it is a cx33 in hel1, rebuildable today only
because hel1 happens to have stock. This is not a web-2 defect; it is an IaC-pinned-to-a-
dying-SKU defect. #6463's title already names the class.

### Retiring web-2 is the first step of active-active, not a detour

The operator's target is **active-active-N web behind an LB**. Its blocker chain:

- ADR-068 §(c) is a hard invariant: no LB weight to web-2 until the owner-side relay is
  active **and** the git-data store is cut over.
- `soleur-git-data` **has never existed**. `git-data.tf` pins
  `server_type = var.git_data_server_type  # cax11 = ARM64 (Ampere)`, and the **entire
  cax line is orderable in 0 of 3 EU DCs** (measured live).
- There is **no load balancer resource anywhere in the repo**.
- The account sits at **5/5 servers** (the cap #6453 was filed over).

Retiring web-2 takes the fleet to 4/5, freeing the slot git-data needs. git-data
additionally needs a type change off cax11. Both are prerequisites for active-active;
neither is optional. So "retire web-2" and "start active-active" are the same move.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Retire web-2** (remove from `var.web_hosts`; destroy host + empty volume) | Unanimous across CTO, platform-strategist, CPO, CFO. It has never served, ships nothing, holds an empty volume, and can never join `web_spread`. |
| 2 | **Reject cpx32@fsn1** | +€324/yr to buy "observability of idleness" on a host barred from serving by ADR-068 §(c), behind an unborn host. |
| 3 | **Reject cx33@hel1** | Reverts #6393's documented cross-DC decision AND re-bets on a SKU orderable in one DC today, zero DCs yesterday. Ranked last by every leader. |
| 4 | **Correct the Art. 30 register** in the same PR | Register says web-2 is *"(CX33, `hel1`)"*; live is fsn1. PR #6393 moved it without amending. §5(2) accuracy defect (CLO). Retiring makes the fix a strike-out. |
| 5 | **Reconcile `expenses.md`** in the same PR | Ledger drift found by CFO + verified live (below). |
| 6 | **Do NOT bundle the placement-group defect** | `web_spread` is empty and unreachable-by-design (`ignore_changes`) while `placement-group.tf` claims it *"guarantees the web hosts land on DIFFERENT physical servers."* Same class as the "routing lie". Own issue (CTO + CPO both said split). |
| 7 | **git-data type decision is the next brainstorm** | cax11 is unorderable EU-wide; the type choice changes ADR-068's "git/sshd are ARM-native" premise. Needs its own ADR-shaped decision, not a ride-along. |
| 8 | **#6538 is superseded by this decision; #6463 is where the call belongs** | #6463 (filed 2026-07-15, one day earlier) already framed the same dilemma and asked for the operator call. Close both against this PR. |
| 9 | Visual design | N/A — pure infra, no UI surface (Phase 3.55 trigger boundary). |

## User-Brand Impact

- **Artifact:** the web-host cluster terraform (`var.web_hosts` / `hcloud_server.web`),
  web-2's telemetry reachability, and the Art. 30 register entry describing it.
- **Vector:** believing we have failover that we demonstrably do not. ADR-068's 2026-07-03
  amendment calls a bare web-2's `200 / status:ok` **"a routing lie"**, and §1 notes a
  request round-robined to it *"hits an empty workspace — a single-user (workspace-gone)
  incident."*
- **Threshold:** `single-user incident`.

**The inversion matters.** The dark standby is not itself a user risk — it is unreachable.
The user-reaching risk is the *belief* that it is a standby. Options A and B keep that lie
alive and better-instrumented; retiring deletes it.

## Verified ledger + register drift (found during this brainstorm)

| Artifact | Claim | Live truth |
|---|---|---|
| `article-30-register.md` §(e) | web-2 = *"(CX33, `hel1`)"* | cx33 @ **fsn1** since #6393 |
| `expenses.md` | web-1 & web-2 @ `15.37`/mo each, *"160 GB SSD"* | cx33 = €8.49 (~$9.17), 80 GB |
| `expenses.md` | registry = `CX33 / 9.17` | **cx23** (~€5.49) since #6497/#6463 |
| `expenses.md` | grok-dogfood = *"approved-not-billing … Not born"* | **LIVE** — `soleur-grok-dogfood` cx33, created 2026-07-16 (verified via Hetzner API) |
| `cost-model.md` | Product COGS = web platform only | Missing web-2, registry, inngest (~$50/mo of active rows) |

Live Hetzner total ≈ **€57.79/mo** (5 servers €50.45 + volumes ~€4.84 + IPv4 ~€2.50).
Retiring web-2 → ≈ **€47.92/mo** (−€9.87). cpx32 → ≈ **€84.79/mo** (+€27.00).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Retire. cpx32 would buy "observability of idleness"; cx33@hel1 trades a
documented invariant for stock fragility. Confirmed `hcloud_server.web` is **excluded from
the push-apply `-target` allow-list**, so a `var` change cannot trigger an unguarded
resize/reboot on merge — but that also means a `server_type` change alone would be a
*resize*, which does **not** re-run cloud-init, so it would never install Vector. #6538 is
a duplicate of #6463; the placement-group defect is a separate LOW issue.

### Engineering / Infra (platform-strategist)

**Summary:** Rank C ≫ A > B. There is **no €0 middle option** for telemetry:
`ignore_changes = [user_data]` means only a recreate re-runs cloud-init, and SSH is barred
by `hr-no-ssh-fallback-in-runbooks` — so restoring telemetry *is* the recreate. Same-DC +
a real placement group is the correct active-active topology; cross-DC costs ~20–30 ms per
hop and buys nothing the placement group doesn't. The 5-server cap binds materially
(`GET /v1/limits` → 404; raise is a Console request).

### Product (CPO)

**Summary:** All three options are user-invisible today — that is the finding, not a
caveat. Fixing web-2 now moves #6459 forward by **zero**. Retire; re-create at epic start
with strictly better information about what is orderable then.

### Legal (CLO)

**Summary:** Legally **indifferent** between A/B/C — fsn1/hel1/nbg1 are all EU, so CLO T-1
residency is satisfied identically and no sub-processor or transfer surface changes.
Destroying an empty volume that never held user data carries no retention/Art. 17/DSAR
obligation. The one real deliverable: the Art. 30 register is factually wrong about web-2
(§5(2) accuracy defect) and must be corrected under **every** option.

### Finance (CFO)

**Summary:** Retire. Option A is +47% of all Hetzner spend for a capability gated behind a
host the ledger itself flags as a *"PHANTOM ROW … this host has NEVER existed"*. The
re-purchase option is free (cpx32 is orderable in fsn1 today at the same price later) and
the volume is empty, so retiring costs nothing recoverable. Ledger drift above must be
fixed regardless of option.

### Operations / Marketing / Sales / Support

**Summary:** Not relevant — no customer-facing, pipeline, or support surface. Operations
overlaps Finance via `expenses.md` (covered above).

## Capability Gaps

| Gap | Domain | Evidence |
|---|---|---|
| **No guarded destroy path for a web host.** `web-2-recreate` (replace) and `registry-region-migrate` exist; there is no `web-2-retire`. `hcloud_server.web` is excluded from push-apply, so removing it from `var.web_hosts` will **not** destroy it on merge. | Engineering | `git grep -rln "web-2-recreate\|registry-region-migrate" → .github/workflows/apply-web-platform-infra.yml`; workflow header: *"`hcloud_server.web`, `hcloud_volume.workspaces` … remain excluded — managed by initial-apply + drift detector, not per-PR"* |
| **git-data cannot be born.** `cax11` ARM is orderable in 0 of 3 EU DCs (measured live via `/v1/datacenters` + `/v1/server_types`). | Engineering | `git-data.tf:120` — `server_type = var.git_data_server_type # cax11 = ARM64 (Ampere)`; live probe: `nbg1/hel1/fsn1 cax_orderable=0` |
| **No load balancer exists.** Active-active has no ingress primitive. | Engineering | `grep -rn "cloudflare_load_balancer\|hcloud_load_balancer" --include=*.tf .` → zero hits; `server.tf`: *"(No load balancer exists yet — ADR-068 §(c)'s LB weight is future-tense …)"* |
| **Server cap has no API self-serve.** | Operations | `GET /v1/limits` → 404 (recorded in the 2026-07-15 replace-shaped-ops learning) |

## Open Questions

1. **What is the guarded destroy path for web-2?** Mirror `registry-region-migrate`'s
   plan-JSON allow-set shape (`out_of_scope==0`, no `[ack-destroy]` bypass, menu-ack
   dispatch per `hr-menu-option-ack-not-prod-write-auth`) — resolve at plan time.
2. **Does `terraform_data`/`moved`/`removed` cleanup accompany the `var.web_hosts` key
   removal?** web-1 is *"pinned 23 times across 5 files"*; verify no `web["web-2"]`
   reference strands.
3. **Should `grok-dogfood` also be reaped?** It is live but the ledger books it as
   *"not born"* and `enable_grok_dogfood` defaults to `false`. Out of scope here; feeds
   #6460 (fleet-capacity-audit).
4. **Which server type replaces cax11 for git-data?** Moving off ARM invalidates ADR-068's
   *"git/sshd are ARM-native"* rationale. Next brainstorm.

## Productize Candidate

**`fleet-sku-orderability-audit`** — a scheduled check that every `server_type` referenced
in IaC (`var.web_hosts`, `var.git_data_server_type`, registry, inngest) is *orderable* in
its pinned location, alerting on drift. Both defects in this session (web-2 cx33, git-data
cax11) are the same class: IaC pinned to a SKU the vendor stopped selling in our region,
discovered only at apply time. #6460 (fleet-capacity-audit) is the existing home — feed
this shape into it rather than opening a new issue.
