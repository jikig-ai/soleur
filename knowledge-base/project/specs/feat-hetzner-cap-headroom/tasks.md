---
feature: hetzner-cap-headroom
issue: 6453
pr: 6457
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-15-chore-hetzner-cap-headroom-plan.md
---

# Tasks — feat-hetzner-cap-headroom (#6453)

**Already shipped in-session — do NOT redo:** `hermes-agent` destroyed (fleet 4/5); snapshot
`408787015` taken **and deleted** (operator decision — no rollback exists, disclosed in
`expenses.md`); the hermes retirement row added to the ledger.

**No Phase 0.** All five original preconditions were resolved or cut at plan-review — see the
plan's "Preconditions — RESOLVED" section. Nothing left to probe.

## Phase 1 — The stock gate (TDD)

- [ ] **1.1** Write the failing test `tests/scripts/test-stock-preflight-gate.sh`.
      **Hermetic** — no network, no `HCLOUD_TOKEN`; stub `_stock_fetch` to `cat` synthesized
      fixtures (`cq-test-fixtures-synthesized-only`; sibling posture at
      `tests/scripts/test-git-data-host-replace-gate.sh:17-21`). Six cases = T1-T7 in the plan.
      **Never bind a case to live stock** — `cx33` went orderable→nowhere in ~3h.
- [ ] **1.2** Implement `tests/scripts/lib/stock-preflight-gate.sh` exposing
      `stock_preflight <server_type> <location>`. Match `tests/scripts/lib/web2-recreate-gate.sh`
      (function export, sourcing contract, exit semantics).
  - [ ] **1.2.1** Route every HTTP call through the seam:
        `HCLOUD_API="${HCLOUD_API:-https://api.hetzner.cloud/v1}"` +
        `_stock_fetch() { curl -sS -H "Authorization: Bearer ${HCLOUD_TOKEN}" "${HCLOUD_API}$1"; }`
  - [ ] **1.2.2** Resolve the type via `/v1/server_types?name=<type>` — **not** `?per_page=50`
        (which encodes "≤50 types" and fails **closed** if one lands on page 2). Unknown type =
        `length == 0`.
  - [ ] **1.2.3** Resolve `location` → its **single** datacenter (`fsn1 → fsn1-dc14`; one DC per
        location, no sibling fallback).
  - [ ] **1.2.4** Assert type id ∈ `datacenters[].server_types.available` — **`available`, never
        `.supported`** (`supported` is 24/DC and would pass the live trap).
  - [ ] **1.2.5** Fail-closed on every resolution/API failure.
- [ ] **1.3** Abort messages. Stock-miss MUST name: the **EU-filtered** orderable list (filter
      to `["nbg1","fsn1","hel1"]` — `/v1/datacenters` returns `ash`/`hil`/`sin`, and advising a
      Singapore prod host is a residency break), the **`warm-standby` tine**, and **#6463**.
      **Do NOT offer "re-dispatch against another location"** — `workflow_dispatch` has no
      location input (`apply-web-platform-infra.yml:76-104`). API-blip is a **distinct**
      message (`cannot PROVE stock`).

## Phase 2 — Wire into all five destroy-shaped paths

- [ ] **2.0** **P0 — token reachability.** Each gate call site's step `env:` is `DOPPLER_TOKEN`
      only, and the gate runs **outside** `doppler run`. Without this the gate fail-closes on
      **every** dispatch = an outage. Add before each gate call (precedent `cutover-inngest.yml:359`):
      `HCLOUD_TOKEN=$(doppler secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain); export HCLOUD_TOKEN`
- [ ] **2.1** Source the gate + call it at the five sites: `:1197` (web-2), `:1614` (inngest),
      `:1776` (registry), `:1969` (registry-region-migrate), `:2171` (git-data-host-replace).
      Derive type/location from `tfplan.json` (produced at `:1193`/`:1610`/`:1772`/`:1965`/`:2167`).
  - [ ] **2.1.1** `select(.type == "hcloud_server")` **first**, match `.address` **exactly**
        (siblings carry `after` without these keys: `hcloud_server_network` → `["ip"]`,
        `hcloud_volume_attachment` → `["volume_id"]`; a collision fixture already exists).
  - [ ] **2.1.2** Filter `.change.actions | index("create")` — a `no-op` also carries
        `after.server_type`.
- [ ] **2.2** Tripwire posture in the step comment (match `:447`).
- [ ] **2.3** **No `[ack-destroy]` bypass** (match `:1775`, `:1613`, `:2170`).
- [ ] **2.5** **Register the test in CI — MANDATORY.** Add to `scripts/test-all.sh`'s
      `tests/scripts/` block (match `:144-146`):
      `run_suite "tests/scripts/stock-preflight-gate" bash tests/scripts/test-stock-preflight-gate.sh`
      Nothing auto-discovers `tests/scripts/` (the `:218` glob excludes it). **Without this the
      deliverable's test never runs.**
- [ ] **2.6** Author the coverage-enumeration test (AC3's home — it previously had no phase).
      Model on `plugins/soleur/test/terraform-target-parity.test.ts`; read
      `apply_target.options` (`:97-104`, 8 items); explicit `EXCLUSION_ALLOWLIST`.

## Phase 3 — Hard rule + its required ack

- [ ] **3.1** Amend `hr-prod-host-config-change-immutable-redeploy` (`AGENTS.core.md:26`)
      **in place, same id** — name the no-rollback danger.
- [ ] **3.2** **P0 — ADR-092/AP-017 ack. Without it the PR CANNOT MERGE** (`rule-body-lint` is
      always-run + required, `ci.yml:170-193`). "Strengthening, not weakening" does **not** exempt.
  - [ ] **3.2.1** `python3 scripts/lint-rule-bodies.py --write`
  - [ ] **3.2.2** Append the hash-bound ack to `.claude/rule-weakening-acks.txt`
  - [ ] **3.2.3** `git fetch --no-tags origin main && python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"`
- [ ] **3.3** Do **not** add a new rule — on the "headroom is the wrong frame" argument.
      **Not on byte grounds** (that premise was false: linter is 20000/23000 and exits 0).

## Phase 4 — Residency validation

- [ ] **4.1** Add `validation` blocks to `var.location` (`variables.tf:38`) and
      `var.registry_location` (`:44`), mirroring `web_hosts` at `:94-96`.
- [ ] **4.2** Error message mirrors `:96` (GDPR residency, CLO T-1).
- [ ] **4.3** Verify live values (`hel1` both) pass — a tightening that fails closed on live
      config breaks the next apply.

## Phase 5 — Ledger reconcile

- [ ] **5.1** `expenses.md:14-16` git-data rows → `approved-not-billing`; note cax11 is
      orderable in 0 EU DCs, so it cannot be born at any cap.
- [ ] **5.2** `expenses.md:17-19` web-2 `hel1` → `fsn1`; reference #6463.
      *(FR1/follow-through: dropped — snapshot already deleted.)*

## Phase 6 — Limit-raise issue

- [ ] **6.1** File the `action-required` issue with the **playwright-attempt evidence line**
      (301→console.hetzner.com; `accounts.hetzner.com/login` → `/_ray/pow` **429** PoW gate;
      `/v1/limits` **404**; no Console creds in Doppler; profile has 65 domains, **zero** Hetzner).
- [ ] **6.2** State plainly that it is **unverifiable-by-construction** and **NOT** tracked —
      `action-required` has no sweeper (9+ open, oldest 2026-07-08, incl. #6406). Do not claim
      otherwise. The honest mechanism is the consumer discovering the cap at plan time.
- [ ] **6.3** Rationale = **probe hosts only**. Not git-data, not web-3.

## Phase 7 — Verify + ship

- [ ] **7.1** Run the ACs (10 — see plan). AC17 (`lint-rule-bodies --check`) is the **required**
      check; AC16 proves the test actually runs; AC6 is linter-exit-0 only.
- [ ] **7.2** `bash scripts/test-all.sh`
- [ ] **7.3** `/soleur:review` → `/soleur:compound` → `/soleur:ship`. PR body uses
      `Closes #6453` (safe — no enrollment depends on the issue staying open).
</content>
