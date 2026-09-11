---
date: 2026-08-06
topic: hetzner-host-class-strategy
lane: cross-domain
brand_survival_threshold: single-user incident
status: awaiting-operator-decision
related_issues: [7309, 7287, 7247, 7027, 6460]
---

# Hetzner host-class strategy — stop the recurring stock shortages

## Trigger

The operator was asked to accept **+€14.00/mo** to repin the registry host `cx23 → cpx22`
(#7309), on the premise that `cx23` is unorderable in `hel1-dc2` and therefore no registry
recreate path can succeed. The operator declined to accept and asked the prior question:

> "We are frequently facing host shortage in Hetzner, can we analyze what would be the best
> class of machine to avoid that issue and to some extent if it makes sense to migrate to a
> different cloud provider at some point?"

This document answers that. It is **read-only analysis** — no terraform was edited.

## Headline finding — #7309's premise is stale, and the registry is unblocked right now

A live probe of the Hetzner API at **2026-08-06T09:24:45Z**, read from
`/v1/datacenters` `.server_types.available` (never `.supported`, per the discipline
`zot-registry.tf` already documents):

```
cx23 (id=114)   nbg1-dc3 available=true   hel1-dc2 available=true   fsn1-dc14 available=true
```

**`cx23` is orderable in `hel1-dc2` today.** #7309's blocking claim was true on 2026-08-04 and
is false on 2026-08-06. The registry recreate paths each gate on `stock_preflight_gate` reading
the *planned* `server_type` out of `tfplan.json` — so **that gate** would pass right now, on the
existing pin, with:

- **no repin**
- **no +€14.00/mo**
- **no code change at all**

> **The stock gate passing does NOT mean the recreate is fireable.** Readiness verification
> found three further blockers that stock has nothing to do with — see § "What we should
> actually build" #1 (B1–B3). Chief among them: **#7278 is OPEN**, and #7287 states firing while
> it is open "should not be treated as acceptable even if everything else clears." **No dispatch
> was fired.** The value of today's stock reading is that it removes #7309's cost question, not
> that it authorizes a destroy.

This matters urgently because **#7247 is live and escalating**: zot has been crash-looping
since 2026-08-03 17:08 UTC and as of **2026-08-06 06:49 UTC** is now failing releases with
`500 / DIGEST_INVALID` (observed in run 31078206203, pulled from the run log). The registry is
cloud-init-only (ADR-096), so destroy-and-recreate is the *only* vehicle that can deliver a fix
to that host — and the stock window that blocks it is **open at this moment**.

> The stock window is not stable. It closed between 07-26 and 08-04 and reopened by 08-06.
> Treat this as perishable.

## The real problem is not the SKU — it is that we pin a point-in-time reading

Every recorded probe, assembled from the IaC's own comments plus today's live pull:

| Date | Source | cax line | cx line (cx23/cx33) | cpx 2-series |
|---|---|---|---|---|
| 2026-07-26 | `variables.tf:114` (#6966) | 0 of 3 EU DCs | **0 of 3 EU DCs** | available |
| 2026-07-27 | `variables.tf:174` (#6982) | 0 of 3 EU DCs | **out** | available |
| 2026-08-04 | `zot-registry.tf:438` (#7309) | — | **out in hel1**, ok in nbg1 | available |
| **2026-08-06** | **live probe (this doc)** | **0 of 3 EU DCs** | **ok in all 3 EU DCs** | available |

Three distinct behaviours, and they are not the same problem:

1. **`cax` (Ampere/ARM) is structurally unavailable** — out in 3 of 3 EU DCs at *every*
   recorded probe over 11 days. This is not a flap; treat the line as gone for planning.
2. **The `cx` line flaps.** Out on 07-26 and 07-27, partially out on 08-04, fully in on 08-06.
3. **The `cpx` 2-series has been available at 100% of recorded probes.**

Also newly visible in the live catalog: the *old* `cpx` generation (`cpx11`, `cpx21`, `cpx31`,
`cpx41`, `cpx51`) is now **out in all 3 EU DCs**, while the 2-series (`cpx12/22/32/42/52/62`)
is in. Hetzner is rotating generations, and availability tracks generation, not brand.

**The defect is architectural, not a wrong SKU choice.** A single hardcoded `server_type`
default converts a vendor inventory flap into a hard block on unrelated work — and then each
flap gets written into the repo as a durable-sounding fact, which the next issue quotes after
it has expired. That has now happened three times (#6966 web-2, #6178 inngest, #7309 registry).

## The cost framing in #7309 is also wrong — `cpx22` is the worst buy on the board

Live pricing pulled from `/v1/server_types` (EUR net/mo, hel1), same probe:

| Type | vCPU | RAM | €/mo net | hel1 stock today |
|---|---|---|---|---|
| **cx23** (registry today) | 2 | 4 G | **5.49** | available |
| cax11 | 2 | 4 G | 5.99 | **out** |
| **cx33** | **4** | **8 G** | **8.49** | available |
| **cpx22** (#7309 proposes) | 2 | 4 G | **19.49** | available |

`cpx22` costs **€11.00/mo more than `cx33` while being half the machine** (2c/4G vs 4c/8G).
If the registry must move off `cx23` at all, `cx33` dominates `cpx22` on price, cores, RAM and
today's availability simultaneously — and `cx33` is amd64 (does not start with `cax`), so
`local.registry_arch` is unchanged and `user_data` does not re-render, exactly the property
#7309 was buying with `cpx22`.

The one caveat: the ADR-062 cgroup cap is **derived** as `memory × 1024 − 1024`, so `cx33`
moves the cap 3072m → 7168m. That is re-inflating precisely what #6497/#6463 deliberately
reverted on 2026-07-16 after telemetry showed 37 MB steady usage. So `cx33` is the better
*forced* fallback, not a good *default*.

### Fleet-wide, the premium is already being paid

Live fleet (`/v1/servers`, same probe):

| Host | Type | €/mo | Note |
|---|---|---|---|
| soleur-web-platform | cx33 | 8.49 | 4c/8G |
| soleur-registry | cx23 | 5.49 | recreate blocked by #7247, not by stock |
| soleur-web-2 | cpx22 | 19.49 | repinned from cx23 **by stock**, #6966 |
| soleur-inngest | cpx22 | 19.49 | cax was EU-wide out at provision, #6178 |
| **Total** | | **52.96** | |

Two hosts sit on `cpx22` purely because of a stock flap that has since reversed. Both are
2c/4G — the *exact* shape of `cx23` at €5.49. That is a standing **≈€28.00/mo (≈€336/yr)**
premium bought during outages that are no longer in effect, and nothing re-evaluates it.

Note also that **`git-data` has never been born** — there is no such host in the live fleet —
so its `cpx22` pin (`variables.tf:176`) is a paper cost today, not a real one. It would
become real on first provision.

## Provider migration — not warranted now, but the trigger is nameable

Honest read: Hetzner's price advantage is real and large **on the `cx` line** (€5.49 for 2c/4G
is at the bottom of the EU market). It is *not* large on `cpx22` — €19.49 for 2c/4G is
roughly general-market rate for that shape.

That yields the sharpest framing available here:

> Every time a stock flap forces a `cx → cpx` repin, we pay near-market price **without**
> getting market-grade availability. The shortage is economically equivalent to a partial
> migration that we did not choose and got no reliability benefit from.

That is an argument for fixing the *pinning*, not for migrating — because on `cx` pricing
Hetzner is still decisively the cheapest, and the migration cost is measurable from our own
history: the two in-repo same-operation precedents were **10 files / 995 insertions** (#6967)
and **35 files / 2,094 insertions** (#6974) for a *single host changing type within one
provider*. A provider change is strictly larger: new terraform provider, new network model,
new volume/LUKS story, new cloud-init datasource, new DPA and EU-residency review.

**Recommended position: do not migrate now. Migrate when any of these fire —**

- `cpx`-forced hosts exceed **3** simultaneously, or the standing stock premium exceeds
  **€40/mo**, for **2 consecutive months** (i.e. the discount is structurally gone); **or**
- a stock flap blocks a **production incident fix for > 72h** (the #7247 shape — this one
  came close); **or**
- Hetzner deprecates the `cx` line EU-wide the way `cax` has effectively gone.

None of these is met today: the premium is ~€28/mo, `cpx`-forced hosts are 2, and #7247's
window is currently open.

> ⚠ Competitor price points are deliberately **not** asserted in this document. Any migration
> decision must re-pull live pricing from the candidate providers first — I did not verify
> them, and quoting remembered figures is the exact failure mode that produced #7309.

## What we should actually build

Three changes, in dependency order. Only the first is urgent.

### 1. The registry recreate is unblocked ON STOCK — but is still blocked on three other things

**Stock is no longer the binding constraint. It was never the only one.** Readiness
verification (run 2026-08-06, before any dispatch) found the recreate blocked independently of
Hetzner inventory. **No dispatch was fired.**

| # | Blocker | State | Why it binds |
|---|---|---|---|
| B1 | **#7278** — no in-place restart lever | **OPEN** | #7287 is explicit: *"there is no remedy cheaper than a full host replace. Firing while #7278 is open should not be treated as acceptable even if everything else clears."* This is a **rollback dependency**, not a prereq. |
| B2 | Five REQUIRED pre-first-fire cold-vehicle re-verifications | **never run** | The recut "shipped with **zero live executions**". The runbook declares them REQUIRED, not advisory — including the **post-destroy real restore over the CF Tunnel**, which first executes *after* the irreversible destroy. |
| B3 | One-way, **no capacity reservation** | structural | Rollback needs a *second* successful create through the same `stock_preflight_gate`. Given the `cx` line flaps (§ table above), a same-day revert may be un-orderable — "leaving a crash-looping registry with no forward and no back." |

**Vehicle correction.** `registry-host-replace` is the WRONG tool and must not be fired: in
today's state the new host's boot guard requires `/dev/mapper/registry` while the live volume
is still plaintext ext4, so cloud-init FATALs and the sole pull path is gone — #7287 says this
"darks the registry permanently." Only **`registry-luks-recut`** is valid, and it additionally
requires a pinned `expected_registry_store_volume_id` (numeric Hetzner volume id) plus the
`RECUT-REGISTRY-LUKS` typo-guard token.

**Authorization correction — this dispatch has NO reviewer gate.**
`apps/web-platform/infra/../.github/workflows/apply-web-platform-infra.yml:106-108` states
`registry-luks-recut` "has **NO `environment:`** (like all four host-replace/migrate jobs); its
authorization is the menu-ack dispatch itself (`hr-menu-option-ack-not-prod-write-auth`), and
this token only guards a mis-dispatch." So firing it **executes immediately** — it does not
queue for an environment approval. Any framing of this dispatch as "queues for operator
approval" is false, and this document previously implied that. Corrected here.

Whatever path is chosen, it must **not** be layered onto the untargeted plan:
`zot-registry.tf:426-448` records that `hcloud_server.registry` carries no
`lifecycle.ignore_changes = [user_data]` and already has a pending replace in state, and that a
registry replace appearing in an untargeted plan is "a **STOP**, not a proceed."

**The cheapest real unblock for #7247 is therefore B1 — ship #7278's in-place restart lever.**
That is ordinary code work, it is the documented rollback safety net, and on a crash-loop it
may resolve the incident without any destroy at all.

### 2. Make selection resilient instead of pinned — €0 recurring, one PR

Replace the single `server_type` default with an **ordered preference list** evaluated at
**create** time against live `.server_types.available`, plus
`lifecycle { ignore_changes = [server_type] }` so the choice does not churn after birth.

```
registry_server_type_preference = ["cx23", "cx33", "cpx22"]   # cheapest-orderable-first
```

This is the actual fix for the operator's question. It means:

- a flap never blocks a recreate again — it silently costs more for that one boot;
- we get `cx23` pricing whenever `cx23` exists, and `cpx22` availability when it does not;
- `ignore_changes` is load-bearing: without it, stock returning would propose a
  destroy-and-recreate to move *back*, which is far worse than the problem being solved.

The existing `stock_preflight_gate` should be extended to **select** from the preference list
rather than merely **assert** on one type. It already does the hard part (fail-closed
probing, shape-guarding, `.available`-not-`.supported` discipline) — today it only answers
yes/no about a type someone else picked.

### 3. Instrument stock so we stop arguing from stale snapshots — €0

There is **no scheduled stock probe** anywhere in `.github/workflows/`. Stock is probed only
reactively at dispatch. That is the root cause of the documentation defect: every issue quotes
a different point-in-time reading, writes it into a `.tf` comment as though durable, and the
next issue inherits it after expiry. #7027 already owns cleaning up two such stale readings.

A scheduled probe emitting a monitored `SOLEUR_HCLOUD_STOCK` marker to Better Stack gives a
real availability time-series — which is also the only way the migration triggers above can be
evaluated rather than argued. Per `hr-no-dashboard-eyeball-pull-data-yourself`, this belongs in
telemetry, not in a `.tf` comment.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Do not accept the +€14.00/mo repin in #7309 as specified** | Its blocking premise is false as of 2026-08-06; the recreate is unblocked on the current pin at €0 |
| D2 | If a fallback is ever forced, prefer **`cx33` (€8.49)** over `cpx22` (€19.49) | Cheaper *and* larger *and* same arch; `cpx22` is dominated on every axis |
| D3 | Do **not** standardize the fleet on one line | The data shows availability tracks *generation*, not brand; a new single pin recreates the same defect |
| D4 | Fix the **pinning**, not the SKU — ordered preference list + `ignore_changes` | Converts a hard block into a transient price change |
| D5 | **Do not migrate provider now**; adopt the named triggers | Premium is ~€28/mo against a migration cost of 10-35 files *per host, same provider* |
| D6 | Re-evaluate the standing `cpx22` pins on web-2 and inngest | Both were stock-forced during outages that have since reversed; ≈€28/mo, nothing re-checks it |
| D7 | Add a scheduled stock probe with a `SOLEUR_*` marker | Removes the stale-snapshot failure mode at its source |
| D8 | **Do not fire any registry recreate this session** | #7278 OPEN is an explicit documented veto; the five REQUIRED pre-first-fire checks have never run; the op is one-way with no capacity reservation |
| D9 | Route #7247's unblock through **#7278 (in-place restart lever)** first | It is both the cheapest fix *and* the rollback safety net the recut depends on; on a crash-loop it may resolve the incident with no destroy at all |
| D10 | `registry-host-replace` must **not** be fired in today's state | Boot guard needs `/dev/mapper/registry` against a still-plaintext ext4 volume → permanent dark registry (#7287, #6929) |

## Open Questions

1. **Is D6 in scope now or later?** Moving web-2/inngest off `cpx22` saves ≈€28/mo but each is
   a destroy-and-recreate of a live host. web-2 is an out-of-band standby (low risk); inngest
   is a singleton scheduler holding a Redis AOF volume (higher risk, and #6393/#6463 are
   precisely the stranding incidents that motivated the stock gate). Recommend: **defer to its
   own issue**, do not bundle with the registry unblock.
2. **Does the preference list need a terraform `moved`/state dance?** Adding
   `ignore_changes = [server_type]` to an existing resource is a no-op on state, but the
   create-time selection needs a data source or an external probe. Plan-time question.
3. Does #7287's blocking table need correcting regardless? Its "Hetzner stock — not closable by
   any issue" row is **false today** on the live probe.

## User-Brand Impact

- **Artifact:** the zot registry host (`hcloud_server.registry`) and the fleet's
  `server_type` pinning policy across `apps/web-platform/infra/*.tf`.
- **Vector:** a stock-blocked recreate leaves a crash-looping registry serving
  `500 / DIGEST_INVALID` on the release path — every release is blocked, and the failure is
  invisible to users only because releases are not reaching them at all. A mis-sequenced
  recreate on the untargeted plan destroys the host and fails to recreate it, stranding the
  zot store volume detached (#6393, #6463 precedent).
- **Threshold:** `single-user incident`.

## Session Errors

1. **#7309's core measurement expired before the issue was actioned.** The issue recorded a
   live probe dated 2026-08-04 as a durable blocking fact; it was false 2 days later. The
   filing was correct and careful — the defect is that the repo has no mechanism to *expire*
   a stock reading. This is what change 3 addresses.
2. **#7309 selected `cpx22` without re-checking the price board.** `cx33` is cheaper and
   larger. The likely cause is pattern-matching on the two prior precedents (#6966, #6178),
   both of which chose `cpx22` under conditions where the entire `cx` line was out — a
   condition that did not hold when #7309 was written.

3. **This session offered the operator a dispatch option described as "queues for your GitHub
   environment approval — it does not bypass the human gate." That was false.**
   `registry-luks-recut` carries **no `environment:`**, so a dispatch executes immediately; the
   workflow file says so in its own comment (`:106-108`). The operator approved on that
   framing. The error was reading the *generic* hard-rule guidance about environment reviewer
   gates as if it described *this* job, instead of checking the job header first. **Fix:** the
   readiness sequence must resolve the specific job's `environment:` before the dispatch is
   ever *described* to the operator, not merely before it is fired — the description is what
   the authorization is given against. Caught before firing; nothing was executed.

4. **#7287's own blocking table is stale in two places** (both verified this session): it calls
   PR #7300 "an open draft" — it **merged** 2026-08-06T01:16:24Z — and its "Hetzner stock" row
   says `cx23` is unorderable in `hel1-dc2`, which the live probe refutes. Same expiry defect as
   Session Error 1, one issue upstream.

## Verification notes

Every number in this document was pulled live, not quoted from issue prose:

- availability + pricing: `GET /v1/datacenters`, `/v1/server_types`, `/v1/servers`
  (Hetzner API, token from Doppler `soleur/prd_terraform`), 2026-08-06T09:24:45Z
- fleet inventory: `/v1/servers` — 4 running hosts, `git-data` absent
- gate behaviour: `tests/scripts/lib/stock-preflight-gate.sh` (`stock_preflight` returns
  rc=0/1 — asserts, never selects)
- incident state: `gh issue view 7247` — OPEN, last update 2026-08-06T07:04:53Z
- cited issues #7287, #7027, #7247, #6460 all confirmed **OPEN**; #7303 **MERGED**
