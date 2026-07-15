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

**Shipped in-session:** G1 (reclaim `hermes-agent`) — fleet is 4/5 — and the snapshot
decision (taken, then **deleted**; the ledger discloses no rollback exists). This plan covers
the remainder: **the stock gate** (the deliverable), the hard-rule amendment **+ its required
ADR-092 ack**, the residency-validation gap, the phantom ledger rows, and an honestly-labelled
operator issue for the limit raise.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (live-probed 2026-07-15) | Plan response |
|---|---|---|
| Spec/brainstorm: "raise the cap → unblocks ADR-068 Phase 3 (git-data)" | **False.** `git_data_server_type` = `cax11` (`variables.tf:113`); the entire ARM `cax` line is orderable in **0 of 3 EU DCs**. git-data cannot be born at **any** cap. | Corrected in the brainstorm (inline note). Cap raise is justified by **probe hosts only** — not git-data (stock-blocked), and not web-3 either (see Phase 6.3: web-3 births via an operator-local full apply, outside CI, ungated). |
| Brainstorm: "reclaim only funds git-data's unborn slot" (platform-strategist) | **Dissolved.** git-data cannot claim the slot (no cax11 stock). The reclaimed slot is genuine free headroom. | No action — the reclaim already shipped and is now better-justified than when authorised. |
| Spec: "steady-state need is 6 (5 permanent incl. git-data + 1 ephemeral)" | Permanent is **4** while cax11 has no EU stock. Need is **5** (4 + 1 ephemeral); 6 if git-data ever becomes orderable. | Still ask **10** — a limit is free and the ask is one-shot. Rationale changes, number does not. |
| FR6/TR2: "stock preflight mechanics UNVERIFIED; `/v1/limits` is 404" | **Buildable.** `GET /v1/datacenters` exposes `server_types.available` (orderable now) vs `.supported` (24/DC). hel1 was 14-of-24 available; **12 three hours later**. | FR6 **ships**. TR2's drop-clause does not fire. The volatility is why the gate queries live and its tests use fixtures. |
| Draft: "`B_ALWAYS` 22757 is over the 22000 critical cap (#6461), so a new rule is unaffordable" | **False.** `lint-agents-rule-budget.py:74-75` → `WARN=20000`, `REJECT=23000`; `:69` — *"Reject raised 22000 → 23000 in #4599."* Linter **exits 0**; ~243 B headroom. The 22000 came from a **stale rubric** in `compound/SKILL.md`, not from running the script. | Byte argument **removed** from Phase 3.3 — amending still wins, on the "headroom is the wrong frame" argument alone. The stale rubric is now #6461's actual subject. |
| Draft: "`git-data-host-replace` is dead code (a scoped `-replace` needs the resource in state)" | **False.** `terraform plan -replace=<addr>` on an address **not in state** exits 0 and plans a plain **create**. `hcloud_server.git_data` is declared unconditionally → that dispatch tries to **create** git-data into a 5-cap with a type orderable in 0 EU DCs. | Wired into the gate — **5 paths, not 4**. It needs the gate most. |
| Spec AC: "`hcloud server list` returns 4" | Done 2026-07-15. | Marked `[x]`. |
| `expenses.md:14-16` / `:17-19` line refs | Still accurate — the hermes row was inserted at `:24`, after both. | No renumbering needed. |
| Snapshot retention "expiry" | Hetzner images have **no TTL field** (`PUT /v1/images/{id}` accepts only `description`/`labels`/`type`). The follow-through sweeper **cannot delete** — it only comments/closes (`sweep-followthroughs.sh:220-273`), is `--state open` (so `Closes #6453` would kill the enrollment at merge), and has no Hetzner credential by design (all 28 existing scripts are read-only probes). | **Dropped the enrollment; deleted the snapshot in-session** (operator decision). Every enforcement mechanism available was worse than the risk. |

### The finding that reshapes the plan

`GET /v1/datacenters`, 2026-07-15:

```
fsn1-dc14 orderable NOW:  ccx33 ccx43 cpx32 ccx13 cpx22 cpx52 cpx62 ccx63 ccx53 cpx12 cpx42 ccx23
hel1-dc2  orderable NOW:  ccx33 cx23 ccx43 cpx32 ccx13 cpx22 cpx52 cpx62 cx33 ccx63 ccx53 cpx12 cpx42 ccx23
```

- **`cx33` was orderable in exactly one DC globally (`hel1-dc2`).** `web-2` is `cx33 @ fsn1`
  → **`web-2-recreate` would strand the fleet today.** A verbatim #6393 repeat, in the DC
  #6393 fled *to*. Remediation filed as **#6463**.
- **`cax11` orderable in 0 of 3 EU DCs** → git-data unborn regardless of cap.

> **Re-probed ~3h later, same session: `cx33` is now orderable in ZERO datacenters** (hel1
> dropped 14 → 12 available). **web-2 is un-recreatable *everywhere*, not just fsn1**, and
> #6463's "move it to hel1" option evaporated. **This volatility is the thesis, not a
> footnote:** a type/DC pin is not a durable fix — whatever we pin to can go unorderable
> within hours. It is why (a) the gate must query **live** on every dispatch, (b) its tests
> must be **synthesized fixtures** (a live-bound suite is red by lunchtime), and (c) the
> durable fix is the *shape* — create-before-destroy (#6459) — not the pin.

**The stock preflight is therefore not speculative — it fires on live paths today.**
A cap preflight would have returned green on every one of them.

## User-Brand Impact

Carried forward verbatim from the brainstorm/spec — not re-authored.

- **If this lands broken, the user experiences:** a recreate destroys `web-2`, stock
  blocks re-placement, and apply-on-merge wedges — so if `web-1` degrades in that window
  users hit a full outage with no failover, no ability to deploy a fix, and no free slot
  to diagnose from, while the HA posture reads healthy because `web-1` is still up.
- **If this leaks, the user's data/workflow is exposed via:** ~~snapshot `408787015`~~ —
  **closed 2026-07-15.** The snapshot held an unaudited 40 GB disk of unknown provenance;
  retaining it without an expiry would have been continued processing of data we never
  inventoried (CLO). It was **deleted in-session** (operator decision) rather than enrolled
  in a follow-through, because every available enforcement mechanism was worse than the risk
  (see Phase 5). Residual exposure: **none from the snapshot**; the accepted cost is that
  hermes-agent is now unrecoverable.
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

- **External human actors:** none added or changed — operator-facing infra, no new
  correspondent, reviewer, or recipient role.
- **External systems:** none touched. **Hetzner is not modelled as an external system at
  all** — `model.c4:180` models it as `platform.infra.hetzner`, a `container "Compute"`
  (`technology "Hetzner Cloud"`) **inside** the platform boundary, carrying no `#external`
  tag (the `#external` systems are the top-level declarations at `model.c4:222-268`). There
  is no Hetzner vendor edge for a quota change to touch. *(The earlier draft claimed Hetzner
  "is already modelled as an external system" — false premise, correct conclusion; corrected
  at review.)*
- **Containers / data stores:** none added. `hermes-agent` was **never** modelled (verified:
  zero case-insensitive hits across all three `.c4` files) — that absence is #6460's subject;
  removing it changes no modelled element. `soleur-git-data` (`model.c4:210`) is
  modelled-but-unborn — **correctly so, and deliberately not corrected here**: it sits inside
  the block `model.c4:197` explicitly marks `(ADR-068, #5274 — adopting)`, alongside
  `coordinator` (`:202`), `scheduler` (`:206`, `technology "Nomad (Phase 4a)"`) and
  `sessionStore` (`:214`) — **all four unborn by design**. The model documents ADR-068's
  *target* state; singling out git-data would make the block **less** internally consistent.
  The corpus-level question is #6460's.
- **Access relationships:** none change. The gate adds a CI→Hetzner-API read, but rides a
  **pre-existing** edge — same workflow, same token, read-only. *(Note: that CI→Hetzner
  control-plane edge is itself unmodelled today — `github`'s only edges are `→ webapp`,
  `→ tunnel`, `→ sigstore`, `→ betterstack` — a pre-existing gap this plan does not create;
  belongs to #6460's model-accuracy sweep.)*

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
  cadence: >-
    on every web-2-recreate / inngest-host-replace / registry-host-replace /
    registry-region-migrate / git-data-host-replace dispatch
  alert_target: the dispatching operator (workflow run status — a fail-closed abort is red)
  configured_in: >-
    .github/workflows/apply-web-platform-infra.yml (all FIVE destroy-guard steps —
    corrected at review: this block was authored when the plan still wired three, and
    understated coverage by two paths incl. git-data-host-replace, which the plan's own
    reconciliation table argues "needs the gate most")
  note: >-
    The PASS half is a real emit, not aspirational — stock_preflight_gate echoes
    "stock-preflight PASS: N planned server create(s) orderable..." on success and a distinct
    "0 planned server creates" line on the no-op path. Added at review: without them only the
    ABORT half existed, so a gate that had rotted into a silent no-op was indistinguishable
    in the run log from a gate that ran and passed.
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
    HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain);
    export HCLOUD_TOKEN;
    read -r WEB2_TYPE WEB2_LOC < <(hcloud server describe soleur-web-2 -o format='{{.ServerType.Name}} {{.Datacenter.Location.Name}}');
    source tests/scripts/lib/stock-preflight-gate.sh;
    stock_preflight "$WEB2_TYPE" "$WEB2_LOC"; echo "exit=$?"
  expected_output: >-
    The abort names the SHORTAGE specifically:
    "stock-preflight ABORT: server_type 'cx33' is NOT orderable in 'fsn1' today" (exit=1;
    true today, #6463). exit=0 once stock returns or #6463 repins the type.
  why_the_message_and_not_the_code: >-
    Corrected at review. The old form pinned `exit=1`, which is the UNIVERSAL fail-closed
    code — stock_preflight returns 1 for empty args, an unreachable /server_types, an unknown
    type, an unreachable /datacenters, an unknown location AND a real stock miss. So `hcloud`
    missing (=> empty $() => empty args) or a failed Doppler read both produced "exit=1" and
    the test "passed" while proving nothing. Pinning the distinct message is the only form
    that distinguishes "the gate works" from "the gate is broken or absent" — the same bar
    the gate's own header sets when it insists the blip and shortage messages stay DISTINCT.
    The token read is also split off `export` (a bare `export X=$(cmd)` masks cmd's exit
    code), and the LOCATION is now derived live alongside the type: the old form hardcoded
    `fsn1` while boasting it avoided hardcoding `cx33` — but #6463's remediation is a type/DC
    change, so the location moves too.
```

No `ssh` in the discoverability test. The preflight is inspectable from any machine with
the read-only token.

### Soak Follow-Through Enrollment — N/A (no soak-gated criterion remains)

Phase 2.9.1's trigger does not fire: this plan has **no post-deploy soak / time-gated close
criterion**. The one candidate — snapshot `408787015`'s retention — was resolved by
**deleting the snapshot in-session** rather than enrolling a 30-day soak.

**Why the enrollment was the wrong tool**, in case a future plan reaches for it here:

1. **Semantics inverted.** Exit 0 = PASS = the sweeper **closes the tracker**
   (`sweep-followthroughs.sh:220-233`). The draft treated exit 0 as "the signal to delete".
   It is terminal, not a signal — on 2026-08-14 the sweeper would have posted PASS, closed
   #6453 (the only record of the pending deletion), and retained the disk forever.
2. **No actuator exists.** The sweeper's vocabulary is `comment` and `close`; permissions are
   `contents: read, issues: write`; all 28 existing scripts are read-only probes. Wiring
   `HCLOUD_TOKEN` into `secrets=` would hand a Hetzner credential to **every** follow-through
   script on every sweep, gated only by a directive parsed from an **editable issue body**.
3. **The enrollment would never have fired.** The sweeper lists `--state open`; PR #6457
   carries `Closes #6453`, so merge would have closed the tracker first.

`Closes #6453` is therefore safe — nothing depends on the issue staying open.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --json number,title,body --limit 200`
returned no issue body containing any path in `## Files to Edit`.

## Preconditions — RESOLVED at plan-review (no Phase 0; nothing left to probe)

All five original preconditions were resolved or cut by the review panel. Recorded here as
findings, not as gates:

- **Plan JSON availability — RESOLVED, PASSES.** `terraform show -json tfplan > tfplan.json`
  runs in **all five** paths (`:1193`, `:1610`, `:1772`, `:1965`, `:2167`), each immediately
  before its sourced gate (`:1197`, `:1614`, `:1776`, `:1969`, `:2171`) and before any apply.
  Fixture-proven: `tests/scripts/fixtures/tfplan-web2-recreate-scoped.json` carries
  `after.server_type="cx33"`, `after.location="fsn1"`, with `after_unknown` **null** for both
  — known at plan time for create, delete+create, and no-op alike. **Phase 2.1 is sound.**
- **`-replace` on a not-in-state address — settled, no probe needed.** The repo already
  treats `git-data-host-replace` as live: `tests/scripts/lib/git-data-host-replace-gate.sh`
  exists and is sourced at `:2168`. The plan does not get to re-adjudicate a shipped, gated,
  tested job as dead code.
- **Test discovery — RESOLVED: nothing auto-discovers `tests/scripts/`.** The `test-all.sh:218`
  glob excludes it; siblings are hand-registered at `:144-146`. See Phase 2.5 + AC16.
- **Sourced-gate precedent / follow-through semantics — cut.** "Read the file you are copying"
  is not a probe. FR1 is dropped entirely (below), so the sweeper's semantics no longer apply.

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

1.3 **Abort message.** CPO conditioned sign-off on the escape path. **Three review
    corrections are folded in — the first draft's option (1) was fabricated:**

  - **`workflow_dispatch` has NO location input** (`apply-web-platform-infra.yml:76-104` —
    inputs are `reason` + `apply_target` only). "Re-dispatch against another location" is
    not a thing an operator can do; location lives in `var.web_hosts` (`variables.tf:92`)
    and changing it is a code edit + merged PR — i.e. the same option as #6463. **Cut it.**
  - **The missing tine — the highest-leverage edit in this plan.** `warm-standby`
    (`:791-796`) is an **additive** 6-target job: it targets
    `hcloud_server_network.web["web-2"]`, `hcloud_volume.workspaces["web-2"]`, and
    `hcloud_volume_attachment.workspaces["web-2"]` — **not** `hcloud_server.web`. No
    destroy, **no stock requirement, works today**. This is how web-2's private IP was
    restored on 2026-07-13 without recreating the host (`created` unchanged). The workflow
    already says so at **`:451`** — four lines below the `:447` this plan cites for tripwire
    posture. Without this tine the gate converts a **repairable** condition into a #6463
    escalation, which is the opposite of the sign-off condition.
  - **Filter the "orderable elsewhere" list to the EU allow-set** (`["nbg1","fsn1","hel1"]`,
    the same set as Phase 4). `/v1/datacenters` returns `ash-dc1`, `hil-dc1`, `sin-dc1` — a
    naive enumeration would advise putting a prod host in **Singapore**. This couples Phase 4
    to Phase 1 deliberately.

```
::error::stock-preflight ABORT: server_type 'cx33' is NOT orderable in 'fsn1' today
(orderable in EU: <none|hel1|...>). A -replace DESTROYS before it creates — this recreate
would strand the fleet with no rollback (#6393, #6463).
  • If you only need the private NIC or the /workspaces volume re-attached, this is NOT a
    recreate — dispatch `apply_target=warm-standby` (additive, no destroy, no stock needed).
    See apply-web-platform-infra.yml:451.
  • If the host genuinely must be reborn: see #6463 (type/DC change — operator cost/HA call).
  • Stock is time-varying — re-run later.
Do NOT bypass.
```

  The **API-blip** mode is a distinct message, or operators read a blip as a real shortage:
  `::error::stock-preflight ABORT: cannot PROVE stock for '<type>' in '<loc>' (Hetzner API unreachable). An unreachable API is not evidence of availability. Re-dispatch.`

1.4 **Mockable fetch seam — REQUIRED (`cq-test-fixtures-synthesized-only`).** The gate MUST
    route every HTTP call through one indirection so the test can stub it:

```bash
HCLOUD_API="${HCLOUD_API:-https://api.hetzner.cloud/v1}"
_stock_fetch() { curl -sS -H "Authorization: Bearer ${HCLOUD_TOKEN}" "${HCLOUD_API}$1"; }
```

  The test sources the gate and redefines `_stock_fetch` to `cat` a synthesized fixture →
  all cases hermetic, offline, deterministic, no token. **This is not optional polish:**
  sibling gates declare the posture explicitly (`tests/scripts/test-git-data-host-replace-gate.sh:17-21`
  — *"Deterministic; no network. All fixtures are SYNTHESIZED"*), and a live-bound test is
  **red as of this session** — `cx33` went from "orderable in hel1" to **orderable NOWHERE**
  within ~3 hours. The plan's own Sharp Edge forbids encoding today's stock as a constant.

1.5 **Resolve the type by name, not by paging.** Use `/v1/server_types?name=<type>`
    (live-verified: `name=cx33` → 1 result; `name=bogus99` → 0). **Not** `?per_page=50`,
    which silently encodes "Hetzner has ≤50 types" and fails **closed** if a type ever lands
    on page 2 — aborting a legitimate recreate. Unknown-type detection becomes `length == 0`.

### Phase 2 — Wire the gate into **all five** destroy-shaped paths + CI discovery

2.0 **P0 — the gate cannot reach `HCLOUD_TOKEN` as the workflow stands.** Every gate call
    site's step `env:` is **`DOPPLER_TOKEN` only** (`:1168-1169`, `:1747-1748`, …), and the
    `source` + gate invocation run **outside** the `doppler run` wrapper (`:1194-1197`).
    `stock_preflight` would therefore fail-closed on **every dispatch** — a fail-closed gate
    that fails 100% of the time is an outage, not a tripwire. **This is the single most
    damaging defect the review found.** Add to each of the five steps, before the gate call
    (precedent: `cutover-inngest.yml:359`):

```bash
HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain)
export HCLOUD_TOKEN
```

2.1 Source the gate and call it from the existing destroy-guard steps. Derive
    `server_type`/`location` from the **terraform plan JSON** already produced there
    (`terraform show -json tfplan > tfplan.json` at `:1193`, `:1610`, `:1772`, `:1965`,
    `:2167`) — **not** `variables.tf`, because a `TF_VAR_*` can override a default and the
    plan is what actually applies. For `registry-region-migrate`, `after.location` is the
    **target** region for free, which independently vindicates this choice.
    **Two MUSTs from the fixture review:**
    - **Filter `select(.type == "hcloud_server")` first, and match `.address` exactly.**
      Sibling entries carry `change.after` **without** these keys —
      `hcloud_server_network.web["web-2"]` → `after` keys `["ip"]`;
      `hcloud_volume_attachment.workspaces["web-2"]` → `["volume_id"]`. A naive
      `.resource_changes[] | .change.after.server_type` yields `null` for 2-5 entries per
      path. A `tfplan-web2-recreate-substring-collision.json` fixture already guards the
      address-matching class.
    - **Filter on `.change.actions | index("create")`** — a `no-op` entry also carries
      `after.server_type`, so an unfiltered gate would preflight untouched hosts.
2.2 Tripwire framing in the step comment, matching `:447` in posture ("This is a
    TRIPWIRE, not a routine gate").
2.3 **No `[ack-destroy]` bypass** — matches `:1775`, `:1613`, `:2170`.
2.4 **Five paths, not three.** Gate call sites are `:1197` (web-2), `:1614` (inngest),
    `:1776` (registry), `:1969` (registry-region-migrate), `:2171` (git-data-host-replace)
    — those are where 2.1 edits; the `:1165`/`:1583`/… anchors cited earlier are job/comment
    headers, not the edit points. Note `registry-region-migrate` carries **no `-replace`
    flag** (`:1944-1945`) — it is a **pure create** driven by the location change. Still
    correctly gated; the plan's "`-replace`-shaped" description of it was wrong.

  > **Corrected — the "dead code" premise was FALSE.** The plan previously skipped
  > `git-data-host-replace` on the belief that a scoped `-replace` requires the resource
  > in state. Architecture review established that **`terraform plan -replace=<addr>` on
  > an address NOT in state exits 0 with no error and plans a plain CREATE.** Since
  > `hcloud_server.git_data` is declared unconditionally (`git-data.tf:118`), that
  > dispatch would attempt to **create git-data** — into a 5-server cap, with a `cax11`
  > type that is orderable in **0 EU DCs**. It is a live path that fails, not dead code.
  > It needs the gate most of all. **Re-verify this terraform behaviour at Phase 0**
  > before relying on it (the reviewer verified it; this plan's author did not).

2.5 **Register the test in CI — MANDATORY (P0.3 resolved: nothing auto-discovers it).**
    Add an explicit line to `scripts/test-all.sh` in the `tests/scripts/` block, matching
    the sibling form at `:144-146`:

```bash
run_suite "tests/scripts/stock-preflight-gate" bash tests/scripts/test-stock-preflight-gate.sh
```

    `tests/scripts/` is **not** covered by the `*.test.sh` glob at `:218`, and
    `infra-validation.yml` is the wrong home once Phase 1 relocates the gate out of
    `apps/web-platform/infra/`. **Without this line the deliverable's test never runs.**
    Place it inside the same `want_*` guard as its siblings.

### Phase 2.6 — The coverage-enumeration test (AC3's home)

**This phase exists because AC3 had none** — the plan's own anti-regression control ("what
prevents a 5th dispatch path shipping without the gate") was unassigned. Author it modelled
on `plugins/soleur/test/terraform-target-parity.test.ts`, which already parses this workflow.
Read the recreate-shaped targets from the `apply_target.options` enum (`:97-104`, 8 items)
and assert each has the gate in its job body, with an explicit `EXCLUSION_ALLOWLIST`
(shape borrowed from `terraform-target-parity.test.ts:79` — note that allowlist holds
terraform **resource names**, a different axis, so borrow the shape, not the set).

### Phase 3 — Amend the hard rule (+ its required WORM ack)

3.1 Amend `hr-prod-host-config-change-immutable-redeploy` (`AGENTS.core.md:26`) **in
    place** — same id — to name the no-rollback danger: `-replace` destroys before it
    creates, so any create-failure (DC stock, cloud-init, name collision) strands the
    fleet with no rollback; verify target-type stock in the target location first.

3.2 **P0 — the ADR-092 / AP-017 body ack. Without it the PR CANNOT MERGE.**
    `rule-body-lint` is an **always-run required check** (pinned in terraform,
    `ci.yml:170-193`): *any* edit to an `hr-*`/`wg-*` rule **body** is human-gated by a
    per-change, hash-bound WORM ack. This rule's body hash is pinned at
    `.claude/rule-body-hashes.txt:34`. **"It's a strengthening, not a weakening" does not
    exempt it** — ADR-092 Decision 2 requires the ack for all hard-rule bodies regardless
    (existing acks include ones reasoned *"clarification, not a weakening"*). After 3.1:
    1. `python3 scripts/lint-rule-bodies.py --write` → regenerate `.claude/rule-body-hashes.txt`
    2. Append the hash-bound ack to `.claude/rule-weakening-acks.txt`
    3. Verify: `git fetch --no-tags origin main && python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"`
       (the gate re-derives the hash and BLOCKS a stale/hand-edited manifest)

    > **Architectural note worth knowing:** ADR-092 makes **ADD** the ungated primitive and
    > **EDIT** the gated one. Phase 3.3's choice to amend rather than add routed this change
    > onto the WORM-acked path. That choice is still right — but on the "wrong frame"
    > argument alone, **not** on byte grounds (below).

3.3 **Do not add a new rule** — because "headroom" is the wrong frame for a danger the cap
    does not cause. **NOT because of byte budget: that argument was false.**
    `lint-agents-rule-budget.py:74-75` sets `B_ALWAYS_WARN = 20000`, `B_ALWAYS_REJECT = 23000`,
    and `:69` records *"Reject raised 22000 → 23000 in #4599."* Measured **B_ALWAYS = 22757**,
    linter **exit 0** — WARN tier, ~243 B headroom. The earlier draft asserted "already over
    the 22000 critical threshold" by copying a **stale rubric** from `compound/SKILL.md`
    instead of running the linter it describes (that staleness is now #6461). Byte-neutrality
    remains good discipline; it is not a constraint that forces a design.

### Phase 4 — Residency validation

4.1 Add `validation` blocks to `var.location` (`variables.tf:38`) and
    `var.registry_location` (`:44`), mirroring `web_hosts`' condition at `:94-96`:
    `contains(["nbg1","fsn1","hel1"], var.location)`.
4.2 Error message mirrors `:96`'s framing (GDPR residency, CLO T-1).
4.3 Verify current values pass (`hel1` both) — a tightening that fails closed on live
    config would break the next apply.

### Phase 5 — Ledger reconcile

5.1 `expenses.md:14-16` — git-data host/IPv4/LUKS volume: `active` → `approved-not-billing`
    (~$5.12/mo phantom). Add a note: the host has never existed; **cax11 is orderable in
    0 EU DCs**, so it cannot be born at any cap.
5.2 `expenses.md:17-19` — web-2 `hel1` → `fsn1` (stale since #6393). Reference #6463.

> **FR1 (snapshot retention follow-through) is DROPPED — operator decision, 2026-07-15.**
> Snapshot `408787015` was **deleted in-session** instead, and the `expenses.md` hermes row
> now discloses **no rollback exists**. Three review findings converged to kill the
> enrollment: (a) exit 0 makes the sweeper **close** the tracker with a green PASS while
> nothing deletes — the CLO control would have retired itself silently; (b) the sweeper is
> `--state open` and PR #6457 carries `Closes #6453`, so the enrollment would never have
> fired **once**; (c) giving the sweeper a write-capable Hetzner credential would hand it to
> **all 28** follow-through scripts, gated only by a directive parsed from an **editable
> issue body** — inverting the security model the convention documents. Deleting now costs
> the rollback (accepted knowingly) and buys the CLO's expiry with zero machinery.
> **Consequence: `Closes #6453` in the PR body is now safe** — no enrollment depends on the
> issue staying open.

### Phase 6 — Limit-raise tracking

6.1 File the `action-required` issue for the Console limit raise (server → 10, **and** the
    volume limit — a separate counter). **DONE at /work: #6481.** Verified operator-only by a
    fresh attempt (a plan-declared operator gate is UNVERIFIED until re-attempted — the
    Playwright-first hard gate fires even when the plan pre-declares the step):
    `playwright-attempt: navigated https://console.hetzner.cloud/ (301 → console.hetzner.com). The Heray proof-of-work interstitial at accounts.hetzner.com/_ray/pow AUTO-CLEARED and the run reached the real login form at accounts.hetzner.com/login (client-number + password fields, no active session). Gate reached: a CREDENTIAL WALL with no credential in existence — Doppler holds only HCLOUD_TOKEN across prd_terraform/prd/dev, an API token that cannot reach the limits form. GET /v1/limits → 404 while GET /v1/pricing → 200 with the same token, proving the 404 is a real absence and not an auth artifact. The account password lives only in the operator's personal password manager.`

    > **The plan's original evidence line was WRONG and is corrected above.** It asserted the
    > PoW gate *"returns HTTP 429"* and blocked the run. **Not reproducible on 2026-07-15** —
    > the PoW cleared on the first attempt and the run reached the login form. The conclusion
    > (operator-only) survives, but for a different reason: the gate is the **missing
    > credential**, not the bot check. This is exactly why the hard gate requires a fresh
    > attempt rather than honoring a plan-declared handoff: had the 429 claim been taken at
    > face value, the recorded reason would have been fiction. Note "no credential exists" is
    > not one of the enumerated human gates (CAPTCHA/OTP/TOTP/passkey/push-MFA/card/hardware)
    > — it is operator-only because storing the root infra-account password in Doppler for an
    > agent to use is a **security decision for the operator**, not a blocker to route around.

6.2 **Be honest that this rots — do NOT claim it is tracked.** The earlier draft said
    *"tracked by the `action-required` issue — not left to memory."* **That is false:**
    `action-required` has **no sweeper** (grep across `.github/workflows/`, `scripts/`,
    `.claude/hooks/` returns only unrelated hits), and the backlog proves it — 9+ open,
    oldest **2026-07-08**, including **#6406**. `GET /v1/limits` is 404, so there is **no
    API to poll** and no non-destructive probe (the only empirical test is attempting a 6th
    create). The raise is **unverifiable-by-construction**; state that plainly. The honest
    mechanism is the **consumer**: whoever next adds web-3 or a probe host discovers the cap
    at plan time. Say so, and drop the tracking claim.

6.3 The raise's rationale is **probe hosts only**. **Not git-data** (stock-blocked, not
    cap-blocked). **And not web-3 either** — `for_each = var.web_hosts` fans out four
    resources, no `apply_target` creates web-3, and the workflow documents (`:454`) that it
    needs an **operator-local full apply before the code merges, or EVERY subsequent merge
    HALTs**. That birth path runs outside CI where this gate never executes, and **AC3
    structurally cannot see it** (adding web-3 to `var.web_hosts` adds zero `apply_target`
    options). Name this; #6459 is its natural owner.

## Files to Edit

| File | Change |
|---|---|
| `tests/scripts/lib/stock-preflight-gate.sh` | **new** — sourced gate exposing `stock_preflight <type> <location>` (matches `web2-recreate-gate.sh`) |
| `tests/scripts/test-stock-preflight-gate.sh` | **new** — 6 cases, fail-closed coverage |
| `.github/workflows/apply-web-platform-infra.yml` | gate into **5** destroy-shaped steps (`:1165`, `:1583`, `:1744`, `:1877`, `:2079`) |
| `scripts/test-all.sh` | **add an explicit `run_suite` line** in the `tests/scripts/` block (match `:144-146`). **P0.3 proved nothing auto-discovers `tests/scripts/`** — the glob at `:218` excludes it. Without this the test ships dead. **NOT** `infra-validation.yml` — that serves `apps/web-platform/infra/*.test.sh`, the wrong directory after Phase 1's relocation. |
| `plugins/soleur/test/terraform-target-parity.test.ts` *(or a sibling)* | coverage-enumeration test for AC3 + `EXCLUSION_ALLOWLIST` |
| `AGENTS.core.md` | amend `hr-prod-host-config-change-immutable-redeploy` in place (≤600 B, byte-neutral) |
| `apps/web-platform/infra/variables.tf` | 2 `validation` blocks (`location`, `registry_location`) |
| `knowledge-base/operations/expenses.md` | `:14-16` status flip; `:17-19` region fix (the hermes no-rollback disclosure already landed) |
| `.claude/rule-body-hashes.txt` | regenerate via `python3 scripts/lint-rule-bodies.py --write` after the AGENTS.core.md edit |
| `.claude/rule-weakening-acks.txt` | **append** the hash-bound ack (ADR-092 / AP-017 — the `rule-body-lint` **required** check) |

## Files to Create

None beyond the three new scripts above. **No `components/**/*.tsx`, `app/**/page.tsx`,
or `app/**/layout.tsx`** — the mechanical UI escalation does not fire.

## Acceptance Criteria

**Trimmed 16 → 9 at plan-review.** Cut: **AC2/AC14/AC15** (live-stock-bound — `cx33` went
from "orderable in hel1" to **orderable nowhere** within ~3h of the probe; they are RED as
written, and their assertions belong in AC1's synthesized fixtures); **AC8** (unsatisfiable —
`/git-data/` unanchored matches the `Hetzner CX33 (registry)` row, whose Notes read *"where
the web/git-data/inngest hosts live"*, and which is correctly `active`); **AC10** (tests the
plan document's own links, not the deliverable — green before a line of code); **AC11/AC12**
(FR1 dropped); **AC4** (folded into AC3 — a hardcoded `== 23` baseline rots, and it never
bound "no bypass" to the *new* step anyway).

### Pre-merge (PR)

- [x] **AC1** `bash tests/scripts/test-stock-preflight-gate.sh` passes **all 6 cases**,
      **hermetic** — no network, no `HCLOUD_TOKEN`, all fixtures synthesized via the
      `_stock_fetch` seam (`cq-test-fixtures-synthesized-only`; sibling posture at
      `tests/scripts/test-git-data-host-replace-gate.sh:17-21`). Cases: orderable → 0;
      not-orderable → 1 **and the abort names the `warm-standby` tine + `#6463`**;
      unknown type → 1; unknown location → 1; API 500 → 1 with the **distinct**
      `cannot PROVE stock` message; non-EU DC (e.g. `sin`) **filtered out** of the
      orderable-elsewhere list.
- [x] **AC3** *(reshaped per CTO — the old `grep -c … >= 4` did NOT bind a preflight to a
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
- [x] **AC4** *(folded from old AC4 — self-maintaining, no rotting baseline)* No bypass
      introduced by this PR:
      `git diff origin/main -- .github/workflows/apply-web-platform-infra.yml | grep '^+' | grep -F 'ack-destroy' | grep -vE '^\+\s*(#|echo )' | wc -l` == **0**.

      > **Corrected at /work (2026-07-15) — the plan-quoted command was self-contradictory.**
      > The original bare-token form (`grep -c '^+.*ack-destroy'` == 0) is unsatisfiable
      > *given this plan's own Phase 2.3*, which mandates the sibling idiom "NO `[ack-destroy]`
      > bypass on this path" in each new step's abort message (matching `:1775`, `:1613`,
      > `:2170`). A bare-token grep cannot tell "introduces a bypass" from "declares there is
      > none" — it scored **10** against a diff that adds zero bypasses, all 10 being `echo`
      > prose. Anchored instead on the **syntactic construct** a real bypass requires (a
      > conditional on `$HEAD_MSG`, the file's only true bypass at `:465`), excluding comment
      > and `echo` prose. Mutation-proven at /work: injecting
      > `if [[ "$HEAD_MSG" =~ \[ack-destroy\] ]]` scores **1**; the real diff scores **0**.
      > Same class as `hr-when-a-plan-specifies-relative-paths-e-g` (plan authoritative for
      > intent, never for the literal command) and the documented
      > "grep-assertion-over-script-body false-matches its own comments" learning.
- [x] **AC5** `cd apps/web-platform/infra && terraform fmt -check && terraform validate` passes
      (both do), **and** the live values provably pass the new validations.

      > **Corrected at /work (2026-07-15) — `terraform validate` CANNOT see variable
      > validations.** Empirically established on the pinned **Terraform v1.10.5**:
      > `TF_VAR_location=us-east terraform validate` returns **"Success! The configuration is
      > valid." (rc=0)**; only `terraform plan` evaluates a `validation` block
      > (`Error: Invalid value for variable`, rc=1). So AC5's `validate` half is a real check
      > of config consistency but proves **nothing** about residency, and **T8 as written was
      > false**. Verified by the right mechanism instead, in three parts:
      > 1. **Condition logic** — a scratch root carrying the identical
      >    `contains(["nbg1","fsn1","hel1"], var.location)` block: `plan` with `us-east`
      >    **rejects** (rc=1), `plan` with the `hel1` default **passes** (rc=0).
      > 2. **Live values pass** — both defaults are `hel1` ∈ the allow-set, and **Doppler
      >    `prd_terraform` defines neither `LOCATION` nor `REGISTRY_LOCATION`** (checked
      >    against its 152 names), so `--name-transformer tf-var` injects no `TF_VAR_location`
      >    / `TF_VAR_registry_location` override. The defaults are what applies ⇒ the
      >    tightening cannot fail-closed on the live config.
      > 3. **The real gate is the merge-path plan**, which runs `terraform plan` on every
      >    merge and therefore exercises both validations for free — as the plan's own
      >    "Apply path: None required" section already says.
      >
      > A local `terraform plan` against the real root was deliberately not run: it needs the
      > R2 backend + prod creds to prove something parts 1-2 already establish offline.
- [x] **AC6** `python3 scripts/lint-agents-rule-budget.py` → **exit 0** (it already enforces
      both `B_ALWAYS_REJECT=23000` and `PER_RULE_CAP=600`; do not restate its constants).
      Rule id unchanged: `grep -c 'hr-prod-host-config-change-immutable-redeploy' AGENTS.core.md` == 1.
- [x] **AC7** *(merged with old AC8 — one invariant, one parser, anchored to the Service column)*
      `awk -F'|' '$2 ~ /git-data/ && $6 ~ /active/ {n++} END {print n+0}' knowledge-base/operations/expenses.md` → **0**
      (returns **3** today — the three real git-data rows; the registry row correctly drops out).
- [x] **AC9** *(row-count only — the region half was CUT at review as vacuous)*
      `awk -F'|' '$2 ~ /\(web-2/ {n++} END {print n+0}'` == **3** (verified: 3).

      > **The second clause was removed at review (2026-07-15) — it could not fail.** It read
      > `$2 ~ /\(web-2/ && $8 ~ /fsn1/` == 3, but **`$8` is the Notes column; this table has no
      > Region field.** All three web-2 rows contain BOTH `hel1` and `fsn1` in `$8` — because
      > Phase 5.2's own mandated correction prose says *"Region corrected hel1 → fsn1"*.
      > Proven at review by reverting the region markers back to `**hel1**`: the clause still
      > returned 3 and still passed. It asserted nothing.
      >
      > This is the *mirror image* of the defect AC9 was written to fix. The plan already knew
      > the negative `/hel1/` grep was "a landmine that Phase 5.2's own migration prose would
      > trip" — the positive `/fsn1/` grep trips on that identical prose, just silently.
      > Same class as the documented "grep assertion over a script body false-matches its own
      > comments" learning, applied to a markdown ledger.
      >
      > **No awk over this table can assert region**, so the honest options were (a) add a
      > Region column, or (b) state that region is prose-only. Taking (b): the region
      > correction is human-verifiable in the Notes and was confirmed correct at review by
      > reading the rows. **The data is right; only the guard was inert.** Recorded rather than
      > left as a green tick over a check that cannot fail.
- [x] **AC16** The gate's test actually runs in CI — not just locally:
      `grep -c 'test-stock-preflight-gate' scripts/test-all.sh` == 1. Nothing auto-discovers
      `tests/scripts/` (the `:218` glob excludes it; siblings hand-registered at `:144-146`),
      so this one line is all that stands between the deliverable and a green PR with **zero
      coverage**.
- [x] **AC17** *(the required check — distinct from AC6's byte lint)* ADR-092 / AP-017 body ack:
      `git fetch --no-tags origin main && python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` → **exit 0**, **and**
      `grep -c 'hr-prod-host-config-change-immutable-redeploy' .claude/rule-weakening-acks.txt` == 1.
      **Without this the PR cannot merge** — `rule-body-lint` is always-run and required.

### Post-merge (operator)

- [ ] **AC13** Hetzner Console → Limits → "Request change → Limit increase": **server → 10**, and raise the **volume** limit.
      **Filed as #6481** (`action-required`, Post-MVP / Later) with the full attempt evidence.
      `Automation: not feasible because no Hetzner Console credential exists in Doppler (only HCLOUD_TOKEN, an API token that cannot reach the limits form) — verified across prd_terraform/prd/dev; GET /v1/limits → 404 while GET /v1/pricing → 200 with the same token (the 404 is a real absence, not an auth artifact). See the corrected playwright-attempt line in Phase 6.1: the PoW interstitial CLEARED and the run reached the login form, so the gate is the missing credential, NOT the "429 anti-bot wall" this plan originally claimed.`

      > **Dropped the tracking claim — it contradicted this plan's own Phase 6.2.** AC13 read
      > *"Tracked by the `action-required` issue — not left to memory."* Phase 6.2 says in
      > terms that this is **false**: `action-required` has **no sweeper** (grep across
      > `.github/workflows/`, `scripts/`, `.claude/hooks/` returns only unrelated hits; 9+ open,
      > oldest 2026-07-08, incl. #6406), and with `/v1/limits` → 404 there is **no API to poll**
      > and no non-destructive probe — the only empirical test is attempting a 6th create. The
      > raise is **unverifiable by construction**. The honest mechanism is the **consumer**:
      > whoever next needs a probe host discovers the cap at plan time. #6481 says so in its
      > own body rather than posing as a tracker.

## Test Scenarios

**All gate cases are FIXTURE-driven** (via the `_stock_fetch` seam) — never live stock.
`cx33` moved from "orderable in hel1" to **orderable nowhere** within ~3h of the original
probe; a live-bound suite is red by lunchtime and violates `cq-test-fixtures-synthesized-only`.
Invocation is `source tests/scripts/lib/stock-preflight-gate.sh; stock_preflight <type> <loc>`
— **not** the standalone `stock-preflight.sh` path, which Phase 1 forbids.

| # | Scenario (synthesized fixture) | Expected |
|---|---|---|
| T1 | type present in `available` for the DC | exit 0 |
| T2 | type absent from `available`, present elsewhere in EU | exit 1; abort names the **`warm-standby` tine**, `#6463`, and the EU-filtered orderable list |
| T3 | type absent everywhere (the cax11/cx33 shape) | exit 1; abort reads `orderable in EU: <none>` |
| T4 | type orderable only in a **non-EU** DC (`sin`) | exit 1; `sin` **filtered out** of the suggestion — never advise a Singapore prod host |
| T5 | `/v1/server_types?name=…` → 0 results | exit 1 (unknown type → fail-closed) |
| T6 | unknown location | exit 1 (fail-closed) |
| T7 | fetch returns 500 | exit 1 + the **distinct** `cannot PROVE stock` message |
| T8 | ~~`terraform validate`~~ **`terraform plan`** with `location = "us-east"` | rejected (`Error: Invalid value for variable`). **Corrected at /work:** `terraform validate` returns rc=0 "Success" here — it does **not** evaluate `validation` blocks (proven on the pinned TF v1.10.5). Asserting via `validate` would have been a vacuously-green residency test. |
| T9 | `terraform plan` with live `hel1` values | passes. Live values are the `hel1` defaults — Doppler `prd_terraform` defines no `LOCATION`/`REGISTRY_LOCATION`, so no `TF_VAR_*` override exists. Exercised for free by the merge-path plan. |

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
- Stock is **time-varying on an HOURS timescale** — `cx33` went from "orderable in hel1" to
  **orderable nowhere** within ~3h of the first probe, in this same session. Never encode
  today's availability as a constant: the gate queries live every dispatch, and its **tests
  use synthesized fixtures** (`cq-test-fixtures-synthesized-only`). The first draft of this
  plan wrote this very Sharp Edge and then encoded live stock in 6 assertions — do not repeat it.
- **Run the linter; don't quote a rubric that describes it.** The first draft asserted
  `B_ALWAYS` was "over the 22000 critical threshold" by copying `compound/SKILL.md`'s rubric.
  The real linter is `WARN=20000 / REJECT=23000` (`:74-75`, raised in #4599) and **exits 0**.
  The rubric is stale (#6461). A number you typed is not a number you ran.
- **`available` ≠ `supported`.** `supported` (24/EU DC) is what a DC *can* host; `available`
  (12-14, moving) is what is *orderable now*. A gate built on `supported` passes the live
  trap. Same trap in the CLI: `hcloud server-type list -o columns=name,location` reports the
  **supported** set — it would have said `cx33 → fsn1,nbg1,hel1` while cx33 was orderable nowhere.
- **A `-replace` on an address not in state plans a plain CREATE** (exit 0, no warning). That
  is why `git-data-host-replace` is a live failing path, not dead code.
- **Not every web-2 repair is a recreate.** `hcloud_server_network.web` is a separate
  `for_each`'d resource — an *additive online attach* (`network.tf:9-13`), deliberately not an
  inline `network {}` block (which would force-replace the host). `apply_target=warm-standby`
  re-attaches the NIC + volume with **no destroy and no stock requirement** — that is how
  web-2's IP was restored on 07-13 without recreating it (`created` unchanged). Documented at
  `apply-web-platform-infra.yml:451`.
</content>
