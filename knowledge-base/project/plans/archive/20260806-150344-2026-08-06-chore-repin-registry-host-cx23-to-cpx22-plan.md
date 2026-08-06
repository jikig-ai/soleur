---
title: "chore: repin the container-registry host cx23 → cpx22 — buy stock out of the variable set on a one-way recreate"
type: chore
date: 2026-08-06
lane: cross-domain
issue: 7309
refs: [7287, 7278, 6929, 6460, 7027, 7247, 7299, 7300, 7303, 7310]
brand_survival_threshold: aggregate pattern
---

# chore: repin the container-registry host `cx23` → `cpx22`

Spec lacks a valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed); there is no
`knowledge-base/project/specs/feat-one-shot-7309-registry-repin-cpx22/spec.md`.

---

## ⚠ READ FIRST — the issue's premise is FALSE and must not be repeated

**#7309's title and body assert that `cx23` is unorderable in `hel1-dc2`, "so no recreate path
can succeed". That is measurably false as of 2026-08-06.**

Re-probed against the live Hetzner API in this planning session — `GET /v1/datacenters`,
reading `.server_types.available` (never `.supported`), **three consecutive samples, all
agreeing**:

| Datacenter | `cx23` (id 114) | `cpx22` (id 109) |
|---|---|---|
| `hel1-dc2` ← the registry runs here | **available** | available |
| `nbg1-dc3` | **available** | available |
| `fsn1-dc14` | **available** | available |

`cx23` is also in `.supported` in all three. Pricing re-read from `GET /v1/server_types` at
`hel1`: `cx23` = **EUR 5.49/mo net**, `cpx22` = **EUR 19.49/mo net**; both are x86, **2 vCPU /
4 GB**; disk 40 GB → 80 GB is the only spec difference.

**Stock returned.** Every artifact this PR writes — the plan, the variable description, the PR
body, the #7287 comment, the #7309 correction — MUST state the corrected measurement and MUST
NOT restate the "unorderable" claim.

This is not a style preference. `apps/web-platform/infra/` is inside the scan scope of
`scripts/lint-diagnosis-claims.sh` (ADR-166, widened by #7310), which is **BLOCKING** in CI at a
ratcheting baseline of **1**. Its detector fires on `echo`/`printf`/`::error::` operator-message
lines carrying a causal-claim phrase with no measurement in the block — so it mechanically
catches a falsified premise re-entering `registry-userdata-budget.sh` or
`registry-boot-guard.test.sh`, and it does **not** mechanically catch one re-entering a `.tf`
comment. The `.tf` prose is exactly where the defect ADR-166 exists to stop would land silently.
Treat the lint's baseline as the floor, not the standard.

Baseline measured this session: `lint-diagnosis-claims: OK — 1 unmeasured causal claims (baseline 1).`

---

## The rationale of record — operator-confirmed, and NOT the issue's framing

The operator was shown the 2026-08-06 measurement above and chose to repin anyway. The accepted
justification is **not** "cx23 is unorderable". It is:

> Stock volatility is an unacceptable variable on a **one-way recreate of the sole
> container-registry pull path**. `cx23` measured unorderable on 2026-08-04 and orderable on
> 2026-08-06. Today's window cannot be used, because **#7287 is independently blocked by #7278**
> (no in-place restart lever — its own body calls this a *ROLLBACK dependency*, not merely a
> prerequisite) **and #6929** (the guarded recut dispatch does not exist yet). By the time those
> clear, the window may be gone. The apply has **no capacity reservation**, and a failed revert
> needs a **second successful create**, so a stock miss mid-revert leaves a crash-looping
> registry with no forward and no back. `cpx22` removes stock as a variable permanently for
> **EUR 168/yr**.

Every artifact that records a "why" for this change carries **that** paragraph, in substance.
Do not soften it back into the issue's original framing.

---

## Enhancement Summary

**Deepened:** 2026-08-06 · **Reviewers:** kieran-rails-reviewer (correctness),
code-simplicity-reviewer (YAGNI), a scoped `opus` advisor consult (ADR-083), two research
agents, and a verify-the-negative sweep.

### Key changes made at review

1. **P0 — the `discoverability_test` command was spoofable.** It printed the whole `default = …`
   line, and Check 10 substring-matches, so `default = "cx23" # was cpx22` would have PASSED on a
   reverted default. Replaced with a comment-stripping, value-extracting form; **both arms
   measured** against a synthesized spoof. This is the same defect precedent B already fixed in
   `git-data-luks.test.sh`.
2. **Q1 (replace vs in-place) is no longer measured on this PR.** The advisor showed the
   prescribed `terraform plan` was **confounded** by the already-pending replace — it returns
   `["delete","create"]` whatever `server_type` does, so it would have manufactured a false
   "ForceNew confirmed" and written it into an ADR. Routed to #7287; a binding Q1-independence
   invariant replaced the measurement.
3. **Scope cut from 15 files to 12** and **20 ACs to 17** — three fold-ins (a `validation` block,
   a new boot-guard assertion, an ADR-143 pointer) and six narration ACs removed. Precedent A
   shipped the same operation in 7 files with none of them.
4. **`## Downtime & Cutover` added** (deepen-plan Phase 4.55 halt fired on the `server_type`
   change). It records the zero-downtime evaluation, names the blue-green blocker (the private IP
   `10.0.1.30` is baked into ~20 consumer sites), and ties it to ADR-096 clause (g) / **#6126**
   (OPEN: *"zot registry HA + read-replicas"*) rather than pretending to close it.
5. **Sweep scope widened on evidence:** the re-derivation grep is now case-**insensitive**
   (`CX23` appears in `cost-model.md` / `expenses.md` row labels), `model.c4` gained two more
   falsified `cx33 is unorderable` clauses, and a **claim inventory** (Phase 0.8 + AC21) replaced
   the unfalsifiable "five blocks someone noticed".

### New considerations discovered

- **Two of #7309's own file claims are false** and are corrected rather than inherited:
  `stock-preflight-gate.sh` contains zero `cx23`, and the workflow's hits are at 2090/2115/2124/2142
  (not 2085/2094) with the type derived at runtime.
- **`cx33` and the whole "three grandfathered hosts" claim are also falsified** (both `cx33` and
  `cx23` measured available in all three EU DCs) — corrected where this PR already edits, and
  otherwise handed to #6460. The **`cax` line genuinely remains unavailable** and must survive.
- **The repo contradicts itself** on whether `server_type` is `ForceNew` (ADR-096) or a
  reboot-forcing in-place update (`variables.tf` + the destroy-guard's `reboot_updates` counter).
  Recorded, not resolved.

### Verify-the-negative sweep — result recorded, not assumed

Six falsifiable absolute claims were probed against the repo; **all six CONFIRM, zero
contradictions.** (1) No `zot-registry.tf` address appears in the merge-path `-target=` lists —
and the lookalike `terraform_data.registry_insecure_config` is declared in `server.tf`, triggering
on `sha256(local.docker_daemon_json)`, whose only registry input is `local.registry_endpoint`
(the private IP), with no edge to `var.registry_server_type`. (2) `registry_server_type` already
has a default; no new `variable` block. (3) The `templatefile(...)` call passes **12** keys and
exactly **4** trace to `var.registry_server_type` — nothing missed. (4) `stock-preflight-gate.sh`
reads `.change.after.server_type` and hardcodes nothing. (6) No test, `.tftest.hcl`, `.jq` or CI
gate pins the default to `cx23`. (7)/(8) The store volume is not a separate C4 element, and
`zotRegistry` is already in both view include-lists, so `views.c4` needs no edit.

Claim (5) — the live `cax` / `cx33` stock readings — is correctly **NOT-APPLICABLE** to an
offline sweep and was **not guessed**. It was instead verified directly against the Hetzner API
during planning (`.server_types.available`, 3 samples) and is re-probed at Phase 0.1.

### Gates run

Phase 4.6 (user-brand) PASS · 4.7 (observability, 5 fields) PASS · 4.8 (PAT-shaped) PASS ·
4.9 (UI wireframe) **does not fire** — zero UI-surface paths in Files to Edit/Create ·
4.10 (encryption posture) PASS · **4.55 (downtime) FIRED → section added** ·
4.5 (network-outage) **does not fire** — no trigger keyword in Overview/Problem/Hypotheses, and
`hcloud_server.registry` carries no `provisioner`/`connection` block, so there is no implicit SSH
apply-time dependency. Phase 5's full agent fan-out was deliberately scoped to the four passes
above: the plan is a 12-file prose sweep, and its reviewers' dominant finding was *excess*
machinery, not insufficient review.

---

## Overview

`var.registry_server_type` defaults to `cx23`. This plan changes that default to `cpx22`,
sweeps every **claim** the change falsifies (not merely every file containing the literal
`cx23`), records the recurring expense in the same PR, refreshes the C4 model, and corrects the
tracker.

Two properties make this cheap and one makes it sharp:

- **Cheap (1):** `cpx22` is the same shape as `cx23` (2 vCPU / 4 GB, x86). The arch derivation
  and the ADR-062 memory cap are both provably unchanged — see *What does not change*.
- **Cheap (2):** the merge is **inert in production**. `zot-registry.tf` resources are
  `OPERATOR_APPLIED_EXCLUSIONS` (CTO ruling 2026-07-06,
  `.github/workflows/apply-web-platform-infra.yml` §`OPERATOR_APPLIED_EXCLUSIONS`) and are absent
  from the merge-path `-target=` allow-list, so the push-triggered apply never evaluates
  `hcloud_server.registry`. The declared type changes; the live host does not.
- **Sharp:** `hcloud_server.registry` carries **no** `lifecycle.ignore_changes = [user_data]` and
  already has a pending replace in state. `zot-registry.tf` states that a plan showing a registry
  replace is a **STOP, not a proceed**. This PR must not become the vehicle that fires that
  apply. The apply belongs to **#7287**, on its own gates.

**This PR ships a decision and a record. It does not ship an apply.**

---

## Research Reconciliation — cited claims vs. measured reality

Every row was checked in this planning session. Sources are content anchors, not line numbers.

| # | Claim, and where it is asserted | Measured reality (2026-08-06) | Plan response |
|---|---|---|---|
| R1 | "`cx23` is unorderable in `hel1-dc2`, so no recreate path can succeed" — **#7309 title + body**; `zot-registry.tf` `STOCK REALITY — live probe 2026-08-04` table | **FALSE.** `cx23` available in `hel1-dc2`, `nbg1-dc3`, `fsn1-dc14`; 3/3 samples agree | Correct the premise in every artifact; rewrite #7309's title + body (scope item 6). Never restate |
| R2 | "`cx23` (this default) and `cx33` are both orderable in **0 of 3** EU DCs, as is the entire `cax` ARM line" — `variables.tf` `STOCK REALITY (live probe 2026-07-26, #6966)` | **Mixed.** `cx23` ✓ and `cx33` (id 115) ✓ in all three DCs. **`cax11` (id 45) is still unavailable in all three.** | Correct the `cx`/`cx33` half; the **`cax` half stands** and must be preserved, not deleted with it |
| R3 | "THREE running hosts sit on types that can no longer be ordered — web-1 (`cx33`), `soleur-grok-dogfood` (`cx33`), `soleur-registry` (`cx23`)" — `variables.tf` DISASTER-RECOVERY GAP; `expenses.md` *"Not a limit but the same class of latent risk"*; `ADR-143` consequences; `model.c4` web-host node | **FALSE on all three counts.** Both `cx33` and `cx23` are orderable in all three EU DCs | Correct it where this PR already edits the file. It is a whole-fleet claim owned by **#6460**; do not expand scope into re-auditing the fleet — state the measurement and point at #6460 |
| R4 | "`tests/scripts/lib/stock-preflight-gate.sh:109` hardcodes `cx23`" — **#7309 body** | **FALSE.** `grep -c cx23 tests/scripts/lib/stock-preflight-gate.sh` = **0**. The gate is fully parameterised (`stock_preflight <type> <loc>`) and reads `.change.after.server_type` from the plan JSON | **Remove from the sweep.** No edit needed. It picks up `cpx22` with zero changes |
| R5 | "`apply-web-platform-infra.yml:2085,2094` both hardcode `cx23` in stock-probe comments" — **#7309 body** | **FALSE at those lines** (2085 is a `$GITHUB_OUTPUT` echo; 2094 is unrelated prose). Real hits are at 2090 / 2115 / 2124 / 2142, **all comments**. The probe derives the type at runtime via `read_default registry_server_type`, an awk block-range read of `variables.tf` | Sweep the two that name the registry's default as `cx23`; the two dated `#6460` examples are history — keep |
| R6 | "`server_type` is `ForceNew`" — **ADR-096** consequences vs. "a `server_type` change is a **reboot-forcing in-place update** — `reboot_updates` guard" — **`variables.tf`** web-2 block | **The repo contradicts itself.** Its own destroy-guard machinery classifies a `server_type` change as an **in-place update**: `tests/scripts/lib/web-host-birth-gate.sh` selects `.change.actions == ["update"]` AND `before.server_type != after.server_type` into `reboot_updates`, and its comment says selecting `["update"]` exactly *"never double-counts a replace (that carries a delete)"* | **Do not restate either claim as fact.** Carry it as an open question (Q1). **Not resolved here** — with the replace already pending, a single plan reading is confounded, and the answer changes nothing this PR decides. Routed to #7287, which runs a plan against this resource anyway |
| R7 | "the rendered `user_data` is over Hetzner's 32,768 B cap" — superseded framing on #7287 | **FALSE and already corrected** by #7300. Re-measured this session: `stored_bytes=9408`, `cap=32768`, `headroom=23360` | Do not restate. Cited only as the reason the budget script is a safe before/after instrument |
| R8 | "`cpx22` is 2 vCPU / 4 GB, same shape as `cx23`" — #7309 | **TRUE.** Live catalog: `cpx22` id 109, x86, 2 cores, 4 GB, 80 GB disk; `cx23` id 114, x86, 2 cores, 4 GB, 40 GB disk | Confirmed; drives *What does not change* |
| R9 | "This shifts a finance category subtotal by >10%" — dispatch instruction, conditional | **FALSE.** Registry row $5.93 → $21.05 = **+$15.12/mo** against `cost-model.md` **Subtotal Product COGS $223.39** = **+6.77 %** | `cost-model.md` gets its **row label + a forward-dated note**, not a subtotal re-derivation. State the arithmetic so the next reader can check the threshold rather than trust it |
| R10 | Precedent sizing: `31092749f` = 10 files / 995 insertions; `1c801040e` = 35 files / 2,094 insertions — #7309 | **TRUE.** `31092749f` non-planning = **7 files** (`variables.tf`, `zot-registry.tf`, ADR-143, `model.c4`, `model.likec4.json`, `expenses.md`, one learning). `1c801040e` non-planning = **31 files** (excluding `plans`/`specs`/`brainstorms` — the same definition that yields 7 for `31092749f`; excluding `learnings` too gives 27) | The registry repin sits between them. See *Sizing* |
| R11 | Precedent A dropped its `cloud-init-registry.yml` comment edit because a comment edit re-renders `user_data` on a host with no `ignore_changes` | **TRUE then; the premise has since changed.** `local.registry_rationale_strip` now strips whole-line `#` comments out of the render *before* `base64gzip` | The comment edit is very likely byte-neutral in the stored payload — **but that is a claim to MEASURE, not assume.** See AC7 |

**Premise Validation note.** Blockers cited by reference were checked with `gh issue view`:
#7287 OPEN, #7278 OPEN, #6929 OPEN, #6460 OPEN, #7309 OPEN. None is stale. #7277 and #7280 are
recorded as CLEARED on #7287's own table and were not re-litigated. #7027 already owns the
ADR-143 probe-table refresh — **do not duplicate it here**; this plan touches ADR-143 with at
most a one-line pointer.

---

## Open Questions

- **Q1 — is a `server_type` change on `hcloud_server` a replace or a reboot-forcing in-place
  update?** The repo asserts both (R6). Terraform's JSON provider schema does not expose
  `ForceNew`, so it is not answerable by reading the schema.

  **NOT RESOLVED HERE — deliberately, and the measurement is deliberately NOT prescribed.** Two
  independent reasons:

  1. **The obvious measurement is confounded and would manufacture a false certainty.**
     `hcloud_server.registry` **already has a pending replace** from the drifted `user_data`, so a
     `terraform plan` emits `["delete","create"]` for that address **regardless of what
     `server_type` does**. Whoever ran it would read "replace", promote ADR-096's `ForceNew`
     clause to fact, and write it into an artifact a future one-way recreate will cite. Only a
     *differential* between a `cx23` plan and a `cpx22` plan carries any signal, and with the
     replace already pending the two are expected to be identical — i.e. the experiment is
     predicted to return UNKNOWN before it is run.
  2. **The answer changes nothing this PR decides**, and buying it would mean handling raw prod
     R2/Hetzner credentials on a PR whose entire thesis is that it ships a decision and a record,
     not an apply.

  **Routed to #7287**, which actually runs a plan against this resource and can read the
  differential for free as a side effect of work it must do anyway.

  **Binding invariant — NO ARTIFACT IN THIS DIFF MAY ASSERT REPLACE-VS-IN-PLACE.** The ADR-096
  addendum, the `model.c4` description, the runbook and the expenses row are all written without
  reference to it, and **ADR-096's existing `server_type is ForceNew` clause is left EXACTLY as
  found** — not corrected, not softened, not annotated with a guess. The contradiction is recorded
  in the PR body as an open question (AC16). Whatever the answer turns out to be, the risk framing
  does not move: the pending `user_data` drift makes the carrying apply a replace either way.
- **Q2 — a `validation` block for `registry_server_type`? SCOPED OUT.** Its two siblings
  (`git_data_server_type`, `inngest_server_type`) have one and this variable does not — but adding
  it fixes no defect, and it forces an edit to the header comment of
  `tests/scripts/lib/stock-preflight-gate.sh`, the single file that gates **every destructive
  registry dispatch**. Editing the destructive-dispatch gate is not a free fold-in on a repin PR.
  File as `type/chore` if wanted.

---

## Research Insights

- **Arch derivation** (`zot-registry.tf`): `registry_arch = startswith(var.registry_server_type,
  "cax") ? "arm64" : "amd64"`. `startswith("cpx22","cax")` is false → **amd64**, identical to
  `cx23`. Therefore `local.zot_image` still selects `zot_image_amd64`, and `local.doppler_sha256`
  still selects the amd64 checksum.
- **Memory cap derivation** (`zot-registry.tf`): `registry_memory_cap_mb =
  data.hcloud_server_type.registry.memory * 1024 - local.registry_host_reserve_mb`, with
  `registry_host_reserve_mb = 1024`. Live catalog gives `cpx22.memory = 4` (GB) — identical to
  `cx23`. So the cap is `4 × 1024 − 1024 =` **3072m**, unchanged. Every comment in the tree
  reasoning about "a 4 GB host", "3072m", "4096m", or "7168m can never bind" therefore stays
  **true** and must NOT be swept.
- **`user_data` re-render:** the only template inputs that depend on `var.registry_server_type`
  are `zot_image`, `doppler_arch`, `doppler_sha256` (all via `registry_arch`) and
  `zot_memory_cap_mb`. All four are unchanged, so the repin **alone** does not move the render.
  Measured baseline this session: `{"raw_bytes":74682,"stripped_bytes":23958,"stored_bytes":9408,"cap":32768,"headroom":23360}`.
- **Merge behaviour:** `apps/web-platform/infra/**` is in `apply-web-platform-infra.yml`'s push
  path filter, so merging **does** fire the workflow. Its `apply` job plans against an explicit
  `-target=` allow-list containing **zero** `zot-registry.tf` addresses. Expect a green, no-op
  run with `host_creates=0`, `reboot_updates=0`, `resource_deletes=0`.
- **`stock_preflight_gate`** is sourced only from `workflow_dispatch`-scoped jobs. It never runs
  on the merge path, and it reads the type from the plan JSON — so it needs **no edit** to pick
  up `cpx22`.
- **Grep-invisible prose.** Blocks that describe this decision *without* the literal `cx23` and
  which a naive sweep will miss: `zot-registry.tf`'s
  `⚠ THIS EDIT ARMS A PENDING REPLACE, AND THE RECREATE WOULD FAIL ON STOCK IN hel1.` banner;
  its `That is an improvement only if the type is orderable.`; its
  `CONSEQUENCE: do not run an untargeted apply … "the plan shows the registry being replaced" is
  a STOP, not a proceed`; `variables.tf`'s `…stays unmeasured until a recreate on an orderable
  type.` and its `the cx33 arm of this revert path is CLOSED`; and its `the DR remediation for
  all three grandfathered hosts belongs to #6460`.
- **Learnings consulted:** `2026-07-17-hetzner-cloud-api-catalog-not-billed-and-one-marker-per-row.md`
  (the `.available` vs `.supported` trap and the one-marker-per-row ledger discipline);
  `2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md`
  (precedent A's own learning — a cloud-init comment is a live host input);
  `2026-08-04-my-guard-certified-a-string-in-a-file-not-the-render-that-boots.md` (assert the
  render, not the source string).

---

## Sizing

| | Files (non-planning) | Insertions |
|---|---:|---:|
| `31092749f` — web-2 `cx23`→`cpx22` | 7 | 995 |
| `1c801040e` — git-data `cax11`→`cpx22` | 30 | 2,094 |
| **This plan (estimate)** | **12** | **~250–400** |

Larger than A because the registry's decision prose is spread across `variables.tf`,
`zot-registry.tf`, `cloud-init-registry.yml`, two ADRs, a runbook and the recut workflow's
comments. Smaller than B because there is no arch change, no cutover, no new resource, no
`.tftest.hcl`, and no app-code surface.

---

## Files to Edit

### Tier 1 — the repin and the falsified premises (required)

1. **`apps/web-platform/infra/variables.tf`**
   - `variable "registry_server_type"` → `default = "cpx22"`.
   - Rewrite the `description` to carry the **rationale of record** above (the operator-confirmed
     paragraph), in the house style of the `git_data_server_type` description immediately above
     it — which already records this exact decision shape as **ADR-068 D-SIZE** and is the model
     to follow: it states the sizing claim *and* what enforces it, names the rejected cheaper
     option with its price delta, and names the correction path that actually carries the
     decision. Read that description before writing this one.
   - Correct the `STOCK REALITY (live probe 2026-07-26, #6966)` block to the 2026-08-06 reading.
     **Preserve the `cax`-line claim** (still true, R2). **Preserve** the `.available` vs
     `.supported` measurement-trap paragraph verbatim — it is the most valuable thing in the
     block and the repin does not touch it.
   - Retire `CONSEQUENCE: soleur-registry is GRANDFATHERED on cx23 … CANNOT BE REBUILT` and
     `This default is deliberately NOT changed here` — both are now false. Retire, do not soften.
   - Re-anchor `the cx23 recreate WAS to be that measurement — but it can no longer happen on
     cx23` — the large-store boot-scan RSS measurement is now schedulable, not foreclosed.
   - Re-anchor the revert path: `the cx33 arm of this revert path is CLOSED` is false (`cx33`
     measured available). Re-state from the 2026-08-06 probe, or drop the closure claim.
   - Correct the `DISASTER-RECOVERY GAP` "three running hosts" paragraph per R3 and point at
     #6460.
   - Re-anchor `cx23's 40 GB local disk … is irrelevant to store capacity` → `cpx22`'s 80 GB;
     the *conclusion* (irrelevant — the store is a separate 60 GB volume) is unchanged.
   - **Do NOT touch** any statement about "4 GB", "3072m", "4096m" or "7168m can never bind" —
     all still true (Research Insights).
   - Optional per Q2: add the mirroring `validation` block.

2. **`apps/web-platform/infra/zot-registry.tf`** — prose only; **no resource attribute changes**.
   - The `registry_arch` locals block: retire `as of the live probe 2026-07-26 (#6966) NEITHER has
     stock … soleur-registry is GRANDFATHERED on its cx23` and
     `Do not read this block as offering a cax11↔cx23 choice.` The `cax11` half of that sentence
     is still true for a different reason (`cax` is unavailable); say so precisely.
   - `server_type = var.registry_server_type # cax11 (arm64) / cx23 (amd64)` → name the real
     current pair.
   - The `⚠ THIS EDIT ARMS A PENDING REPLACE, AND THE RECREATE WOULD FAIL ON STOCK IN hel1.`
     banner — the second clause is now false. **Rewrite; do not delete the banner.** The pending
     replace is real and is the load-bearing hazard.
   - The `STOCK REALITY — live probe 2026-08-04` table → the 2026-08-06 reading, with the
     `.available`/`.supported` discipline preserved.
   - `#6508's plan-time guard does NOT catch it … it is AVAILABILITY that is zero` — the
     *distinction* is still worth keeping; the *instance* is not. Rewrite to keep the lesson.
   - `CONSEQUENCE: … "the plan shows the registry being replaced" is a STOP, not a proceed.` —
     **keep the STOP.** Only its stock premise dissolves; the destroy-the-sole-pull-path hazard
     (ADR-169) does not.

3. **`knowledge-base/operations/expenses.md`** — `wg-record-recurring-vendor-expense-before-ready`.
   - The `Hetzner CX23 (registry)` row. **Do not simply overwrite the amount.** The row's status
     is `active` (real, live draw) while the repin is declared-only. Record: declared type
     `cpx22`; the rate delta **EUR 5.49 → EUR 19.49/mo net = +EUR 14.00/mo (~+USD 15.12 at ~1.08
     FX), 3.55×, EUR 168/yr**; that **billing does not change until the replace applies**, with
     the trigger named (#7287's dispatch); the same `net == gross` caveat the web-2 and git-data
     rows carry (the API returns identical `net`/`gross` for this account, so the delta is
     arithmetic on those values, not a VAT-adjusted quote — verify against the first invoice);
     and the operator-confirmed rationale in one sentence. Follow the web-2 row's shape, which is
     the in-repo precedent for exactly this "repinned, not yet billing" state.
   - The `Not a limit but the same class of latent risk` paragraph — correct per R3.

### Tier 2 — architecture record (`wg-architecture-decision-is-a-plan-deliverable`)

4. **`knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`**
   - **Append an `## Addendum — 2026-08-06: registry repinned `cx23` → `cpx22` (#7309)`.** This
     is an **addendum to the governing ADR, not a new ADR** — the house pattern for exactly this
     operation (`ADR-143` §`Addendum — 2026-07-26: web-2 repinned cx23 → cpx22`; `ADR-068`
     D-SIZE). **No new ordinal is claimed, so there is no ADR-ordinal collision risk.**
   - The addendum states: the 2026-08-06 measurement (cx23 orderable — the premise is corrected,
     not repeated), the operator-confirmed stock-volatility rationale, the cost, and that arch +
     cap are unchanged.
   - Correct the blocker list that reads `blocked on #7277 (the recut gate has no valid PASS
     condition), #7278, #6929, and Hetzner cx23 stock`. **Two clauses go, not one:** the stock
     clause is false, and **#7277 is already CLOSED by PR #7290** (recorded on #7287's own table
     and in `registry-luks-recut-6929.md`). Since the sentence is being rewritten anyway, strike
     both and cite #7290 — leaving a cleared blocker standing is the same decay class.
   - **Leave ADR-096's `server_type is ForceNew` clause untouched** (Q1-independence).

5. **`knowledge-base/engineering/architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md`**
   - The consequence reading `stock_preflight_gate still applies, and cx23 was measured orderable
     in nbg1-dc3 but not in hel1-dc2 where this host runs` — present tense, now false. Correct
     it. **`stock_preflight_gate` still applying is still true** and must survive the edit.

6. **`knowledge-base/engineering/architecture/diagrams/model.c4`**
   - The registry node description (`OCI-native container registry (zot) on a dedicated Hetzner
     host (cx23, 2 vCPU / 4 GB, hel1, volume-backed) …`) → declared `cpx22`. Use the file's own
     declared-vs-live vocabulary: the code declares `cpx22`; the live host is still `cx23` until
     the replace applies. A description that claims the live host is `cpx22` on merge would be
     the same class of defect this PR is correcting.
   - The web-host node carries **three** falsified clauses, not one. All are undated and
     present-tense, so all three fail AC3:
     1. `soleur-registry (cx23) … NONE can be rebuilt on its current type` — per R3.
     2. `a path web-1 can never take: cx33 is unorderable in all 3 EU DCs` — **`cx33` (id 115)
        measured available in all three DCs** (R3). This one carries no `cx23` literal and is
        therefore invisible to the token sweep.
     3. `because cx33 is unorderable, web-2 returns as a fresh cattle **cpx22**` — same falsified
        premise; the *decision* stands (web-2 is cpx22), only its stated cause does not.

     **Do NOT touch** the `0 of 3 EU DCs` sentence later in the same description — it is
     explicitly dated to the 2026-07-26 probe and legitimately survives.
   - The C4 completeness enumeration has **already been performed at plan time** and is recorded
     under *Architecture Decision (ADR/C4) › C4 views*. Nothing structural changes; do not re-derive
     it, but do re-read that section before editing so the description edit stays consistent with it.

7. **`knowledge-base/engineering/architecture/diagrams/model.likec4.json`**
   - **Regenerated, never hand-edited:** `bash scripts/regenerate-c4-model.sh`, then `git add` it.
   - Precedent A shipped RED here and needed a follow-up commit. `plugins/soleur/test/c4-model-freshness.test.sh`
     byte-diffs the committed artifact against a fresh render.

### Tier 3 — operator surfaces

8. **`knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`**
   - The precondition `Measured 2026-08-05: cx23 orderable in nbg1-dc3 but not hel1-dc2 … a recut
     aborts at the stock gate` → the 2026-08-06 reading.
   - The blocker row naming #7309 as `the live blocker` → resolved by this PR. **Keep the
     re-probe instruction** — stock is not reserved and moves on an hours timescale.

9. **`.github/workflows/apply-web-platform-infra.yml`** — comment prose only, in the
   `registry_luks_recut` pre-rehearsal probe. **Four `cx23` hits, three dispositions:**
   - the two that name the registry's default as `(cx23)` while explaining an earlier dark-grep
     defect → **re-anchor to `cpx22`**;
   - the `#6460` example comment that is **already dated** (`…on 2026-08-05`) → **keep as-is**;
   - the second `#6460` example comment, which is **undated** (`#6460 (cx23 orderable in nbg1-dc3
     but NOT hel1-dc2, where this host runs) was invisible to it`) → **date it in place**, e.g.
     `#6460 (as measured 2026-08-05: cx23 orderable in nbg1-dc3 but not hel1-dc2)`. Leaving it
     undated makes it an undated present-tense falsified claim, which **AC3 fails on**.

   Nothing in this workflow hardcodes the type as a probe input — it derives via `read_default`
   (R5).

10. **`apps/web-platform/infra/registry-userdata-budget.sh`** — the comment
    `The amd64 branch of local.zot_image (registry_arch is amd64 for the cx23 default)`. Only the
    type name is stale; `cpx22` is also amd64, so the branch selection is unchanged. **This file
    is in the ADR-166 lint's scan scope** — the edit must not introduce an unmeasured causal
    claim on an `echo`/`printf` line.

11. **`apps/web-platform/infra/cloud-init-registry.yml`** — **two `cx23` hits, only one is an
    edit.** Change the comment
    `the host provisions on whichever of cax11 (arm64) / cx23 (amd64) has Hetzner stock`.
    **KEEP** the other one — `…silently back to the UNCAPPED-on-cx23 condition that caused
    #6288` — it is the historical note explaining what the hardcoded `7168m` literal *was*, and
    it stays true. Name it explicitly so a residual sweep does not touch it.
    **This file is ALSO in the ADR-166 lint's scan scope** (the lint walks `.yml`/`.yaml`/`.sh`
    under `apps/web-platform/infra/`, not only `.sh`) — the edit must not introduce an unmeasured
    causal claim on an operator-facing message line.
    **Sharp edge, and the reason precedent A dropped its equivalent edit:** this file is
    `templatefile()`d into `hcloud_server.registry.user_data`, which is `ForceNew` with no
    `ignore_changes`. Precedent A's premise has since changed — `local.registry_rationale_strip`
    now removes whole-line `#` comments from the render before `base64gzip`, so a comment-only
    edit *should* be byte-neutral in the stored payload. **Measure it (AC7); do not assume it.**
    If `stored_bytes` moves, drop this edit and record why.

### Tier 4 — finance

12. **`knowledge-base/finance/cost-model.md`** — the `Hetzner CX23 (zot registry, hel1)` row
    label and the dated 2026-07-16 review note that says *"the registry is cx23"*. **Do not
    re-derive the subtotals, break-even or margin figures:** the shift is +$15.12 on Product COGS
    $223.39 = **+6.77 %**, below the 10 % re-derivation threshold, and the amount does not change
    at merge because billing does not change until the replace applies. Record the arithmetic and
    the forward trigger so the next reader can check the threshold instead of trusting it.

**Twelve files. There is no Tier 5.** Three candidate fold-ins were considered and cut — a new
`registry-boot-guard.test.sh` assertion, a `validation` block (+ its forced edit to
`stock-preflight-gate.sh`), and an ADR-143 pointer. Reasons are in *Files NOT to Edit* and
*Alternatives Considered*. Precedent A shipped the same operation in 7 files with none of them.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-7309-registry-repin-cpx22/tasks.md`
- A learning file under `knowledge-base/project/learnings/` (directory + topic only; the author
  picks the date at write time). Candidate topic: *an issue's own premise can expire between
  filing and implementation — re-probe the vendor before inheriting it.*

## Files NOT to Edit — and why

Each of these contains `cx23` and is deliberately out of scope. Listing them is the record that
the sweep *considered* them, so a later reviewer does not re-open the question.

| Path | Why not |
|---|---|
| `apps/web-platform/infra/git-data-luks.test.sh` | The `"cx23:amd64"` row is an **arch-derivation fixture**. Its own comment says it "pins the DERIVATION, not today's Hetzner stock" |
| `scripts/followthroughs/zot-restart-plateau-6288.sh` | Dated historical description of #6288's slice 2 |
| `knowledge-base/engineering/operations/post-mortems/zot-registry-restart-loop-oom-postmortem.md` | A post-mortem is an immutable record of a past state |
| `knowledge-base/legal/audits/2026-07-counsel-review-6459.md` | A dated counsel audit; audit records are immutable |
| `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md` | All `cx23` hits are **web-2**, already repinned. No new sub-processor, no new region, no transfer change — same Hetzner account. Nothing to record |
| `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | Its two stale `cx23` mentions are about **web-2**'s ADR-143 D1 sizing, not the registry. Out of this issue's scope |
| `knowledge-base/project/{plans,specs,brainstorms,learnings}/**`, `**/archive/**` | Point-in-time records that must cite the state as it was — including **this plan** and its `tasks.md`, which are explicitly carved out of any residual-zero AC |
| `tests/scripts/lib/stock-preflight-gate.sh` | Contains **zero** `cx23` (R4) and is fully parameterised — it picks up `cpx22` from the plan JSON with no edit. Would only be dragged in by Q2's `validation` block, which is scoped out precisely to avoid editing the destructive-dispatch gate |
| `apps/web-platform/infra/registry-boot-guard.test.sh` (**as a new assertion**; the file's existing historical `cx23` note also stays) | A new "declared default is cpx22" assertion would pin **nothing derivational** — unlike precedent B's `A17`, which pins a derivation that CROSSES the `cax` prefix boundary. Here the derivation is provably unchanged (both types are amd64), and the literal is already asserted by AC1 *and* executed verbatim by preflight Check 10 |
| `knowledge-base/engineering/architecture/decisions/ADR-143-…md` | Its `cx23` hits are web-2 sizing plus a **dated 2026-07-26 addendum**. Nothing in ADR-143 becomes false when the registry default changes, and **#7027 owns its probe-table refresh** |
| `knowledge-base/engineering/architecture/decisions/ADR-068-…md` | D4's rejection of `cx23` for git-data and its "not candidates — all out of stock" line are git-data's decision record, dated to the 2026-07-26/27 probes |

---

## Open Code-Review Overlap

One open `code-review` issue mentions a file in this plan's edit list:

- **#7098** — *"ci: audit the 56 `run:` bodies whose `set` omits -e against GitHub's inherited
  `bash -e`, then shape the lint"* — names `.github/workflows/apply-web-platform-infra.yml`.
  **Disposition: acknowledge.** Different concern entirely (shell errexit semantics in `run:`
  bodies); this plan edits only comment prose in that file and touches no `run:` body. The
  scope-out stays open.

No open code-review issue mentions `variables.tf`, `zot-registry.tf`, `expenses.md`, `model.c4`
or `cloud-init-registry.yml`.

---

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing at merge — and that is the point worth
  stating precisely rather than waving at. `hcloud_server.registry` is an
  `OPERATOR_APPLIED_EXCLUSION` and is absent from the merge-path `-target=` allow-list, so no
  push-triggered apply can act on it. The realistic merge-time failure is *documentary*: a
  falsified premise left standing in `variables.tf` / `zot-registry.tf` / the recut runbook
  mis-steers whoever fires #7287's destructive dispatch, which is the ADR-166 failure shape that
  already cost three blocked production releases on this exact host. The user-visible artifact of
  that failure is a **dark container registry**: `app.soleur.ai` keeps serving its current image,
  but no new release — including a security fix — can be pulled or deployed, and there is no GHCR
  fallback (the read PAT is revoked and the minter is disabled per ADR-096).
- **If this leaks, the user's data is exposed via:** nothing new. This change moves no secret,
  opens no ingress, and creates no store. `hcloud_server.registry` keeps its deny-all-public
  firewall and private-net-only pull transport; the LUKS-backed store volume and the Doppler-held
  passphrase are untouched. The only new fact written to a public repo is a Hetzner **catalog
  price**, which is already public.
- **Brand-survival threshold:** `aggregate pattern`

**Why `aggregate pattern` and not `single-user incident`** — stated so the choice is auditable
rather than assumed: no individual user can be harmed by this PR merging, because the merge
cannot reach the live host. The harm mode requires a *second* actor to fire a *separate*, gated,
destructive dispatch (#7287) while reading a document this PR left wrong — i.e. it is a pattern
of decayed operator-facing record, not a per-user incident. **Named escalation:** the apply
itself *is* `single-user incident` class — it destroys the sole pull path — and it is governed by
**ADR-169** and gated behind #7278 and #6929. This plan deliberately does not carry it. If a
later revision folds the apply into this PR, the threshold must be raised and CPO sign-off added.

---

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/variables.tf` — `var.registry_server_type` default `cx23` → `cpx22`;
  optional `validation { condition = can(regex("^(cax|cpx|cx|ccx)", …)) }` per Q2, mirroring
  `git_data_server_type` and `inngest_server_type`.
- `apps/web-platform/infra/zot-registry.tf` — **comments only.** No resource attribute, local, or
  data-source change. `data "hcloud_server_type" "registry" { name = var.registry_server_type }`
  resolves `cpx22` (id 109) against the live catalog and continues to act as the plan-time
  phantom-type tripwire.
- No new provider, no new resource, no new variable, and therefore **no new `TF_VAR_*` to
  provision** — this is a default change on an existing variable, so
  `hr-tf-variable-no-operator-mint-default` is not engaged.

### Apply path

**None in this PR — and that is a deliberate, verified property, not a deferral.**

`zot-registry.tf` resources are `OPERATOR_APPLIED_EXCLUSIONS`; the merge-triggered `apply` job's
`-target=` allow-list contains zero registry addresses. The declared type changes; the live host
is untouched. Delivery of the new type to the live host is the guarded
`registry-host-replace` / `registry-luks-recut` `workflow_dispatch`, which is **#7287's** work
and is independently blocked by #7278 and #6929.

Expected blast radius of the merge: one green, no-op `apply-web-platform-infra.yml` run
(`host_creates=0`, `reboot_updates=0`, `resource_deletes=0`). Expected downtime: **zero**.

**One near-miss a reviewer will trip on, named pre-emptively:** the merge-path apply *does*
`-target` `terraform_data.registry_insecure_config`. Despite the name it is declared in
`server.tf`, **not** `zot-registry.tf`, and it triggers on `sha256(local.docker_daemon_json)`,
which does not read `var.registry_server_type`. So the merge-inertness claim survives — but the
address looks like a counterexample at a glance, and the PR body should say so before a reviewer
has to ask.

### Distinctness / drift safeguards

- `hcloud_server.registry` deliberately carries **no** `lifecycle.ignore_changes = [user_data]`,
  and already has a pending replace in state. **Any untargeted plan — the operator's full apply
  and the 12h drift detector — will show the registry being replaced. That is a STOP, not a
  proceed**, and this PR does not change that. After this PR the same untargeted plan will
  additionally show the `server_type` diff.
- `stock_preflight_gate` reads `.change.after.server_type` from the plan JSON and is sourced only
  from dispatch-scoped jobs. It picks up `cpx22` with no edit and will re-probe live availability
  at fire time. **Re-probe immediately before any firing regardless** — stock is not reserved and
  moved twice in 48 hours on this very type.
- Secret handling unchanged: no value in this diff lands in `terraform.tfstate` that was not
  already there.

### Vendor-tier reality check

Not applicable — Hetzner Cloud has no free tier gate on server types. The only gate is live
per-datacenter availability, which is what `stock_preflight_gate` asserts.

---

## Downtime & Cutover

*(deepen-plan Phase 4.55 fires: the plan changes `server_type` on an `hcloud_server`.)*

### The offline-inducing operation, named

Delivering `cpx22` to the live host is a **power-cycle of the sole container-registry pull path**
— the guarded `registry-host-replace` / `registry-luks-recut` `workflow_dispatch`. Whether
`server_type` alone would be a replace or a reboot-forcing in-place resize is **Q1 and stays
open**; the analysis below does not depend on it, because *both* take the host offline, and the
already-pending `user_data` drift makes the carrying apply a replace either way.

### This PR's downtime: ZERO — and that is verified, not assumed

`zot-registry.tf` resources are `OPERATOR_APPLIED_EXCLUSIONS` and appear **nowhere** in the
merge-path `-target=` allow-list, so the push-triggered apply never evaluates
`hcloud_server.registry`. This PR changes a **declared** type. It schedules no apply, and
therefore **accepts no downtime and requires no maintenance window**. AC18 verifies the merge run
was a no-op on the registry.

### Zero-downtime evaluation for the delivery (recorded here so #7287 inherits it, not so this PR performs it)

The gate's default is zero-downtime-first. Evaluated honestly, the zero-downtime path for **this
particular host** is not currently available, and the reason is structural rather than an
oversight:

| Path | Verdict |
|---|---|
| **Blue-green** (birth a second registry on `cpx22`, replicate the store, cut over, retire the old) | **The right shape, and blocked on a known gap.** `local.registry_private_ip = "10.0.1.30"` is baked into ~20 consumer sites — web-host `cloud-init.yml`, `docker-daemon.json.tmpl`, `server.tf`, the Cloudflare Tunnel ingress route in `tunnel.tf`, `ci-deploy.sh`, `web-zot-consumer-probe.sh`, `zot-entry-gate.sh`. A real blue-green needs either a private-IP move (itself a detach/attach on both hosts) or a coordinated repoint of every consumer. **This is not a new idea:** ADR-096 **clause (g)** already names "a second mirror" as one of its two named remedies, records that clause as still open, and notes it is owned by no issue (closest fit #6126). |
| **Rolling / drain-then-act** | **Unavailable.** The registry is a singleton with no rotation and no second replica to drain onto. |
| **Expand-contract** | **Not applicable** — no schema or data migration; the 60 GB store volume is preserved and re-attached by the dispatch's 6-target scope. |
| **`terraform state mv` / state-only re-address** | **Not applicable** — the type genuinely changes on the provider side; there is no re-address that avoids touching the host. |
| **Accept a bounded window** | What #7287 will actually do. Its runbook already mandates firing *immediately before a planned release window*, and ADR-169 governs what authorizes destroying the sole pull path at all. |

**The outage, when it happens, is UNMASKED.** ADR-096 **retracted** its "the GHCR atomic fallback
masks the brief replace outage" claim on 2026-07-30: the GHCR read PAT is revoked (401) and the
minter is disabled (403 `GHCR_MINTER_DISABLED=true`), so the fallback is a dead code path. Any
pull during the window fails outright. The store volume is preserved, so this is an **availability
cost for the duration, not data loss** — but it must not be scheduled as though it were invisible.

### Disposition

This plan **does not close the zero-downtime gap and does not pretend to**. It records the
evaluation, names ADR-096 clause (g) / #6126 as where the blue-green arm actually lives, and hands
both to **#7287**, which owns the apply and the window. Folding the apply into this PR would also
raise the brand-survival threshold from `aggregate pattern` to `single-user incident` — see
*User-Brand Impact*.

---

## Encryption Posture

```yaml
# This plan introduces NO persistent store and NO new cross-component connection — it changes one
# server-type string on an already-provisioned host. The section is REQUIRED anyway: deepen-plan
# Phase 4.10 Step 1 fires mechanically on `Files to Edit` matching `\.tf$` or
# `cloud-init.*\.ya?ml$` (both match here) with no store-semantics escape hatch, and HALTs if the
# section is absent. Clearing 4.10 is this section's whole job — preflight Check 12 does NOT read
# it (it shells out to lint-encryption-posture.py --repo-sweep against the repo ledger).
# The entries below restate the EXISTING posture unchanged, from
# scripts/encryption-posture-ledger.json, and add nothing. The `exception:` block is REQUIRED, not
# padding: Step 3 mandates it whenever `cert_verification: off`, which it is on the private-net
# registry link.
at_rest:
  - store: hcloud_volume.registry
    mechanism: luks
    evidence: apps/web-platform/infra/cloud-init-registry.yml (cryptsetup luksFormat/luksOpen registry); key random_password.registry_luks + doppler_secret.registry_luks_key (zot-registry.tf); fstab entry in the same cloud-init
    defends_against: a seized/RMA'd or snapshot-imaged Hetzner block volume — OCI blobs + cosign signatures are unreadable without the Doppler-held LUKS passphrase
    does_not_defend: a leaked credential, an app-layer read on the unlocked live registry host, or exfiltration via a compromised zot process
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no zot-host at-rest posture probe yet; tracked #6895
    unchanged_by_this_plan: true — the store volume is not touched; a server-type repin does not detach, resize or re-key it
in_transit:
  - connection: web hosts -> zot registry (10.0.1.30:5000)
    enforced_at: apps/web-platform/infra/zot-registry.tf (private-network-only; hcloud_firewall.registry denies all public ingress)
    tls: none (plain HTTP on the private network by design)
    cert_verification: off
    does_not_defend: a passive on-net attacker could read pulled image bytes; integrity (not confidentiality) comes from cosign digest-pinning
    disclosed_as: not-publicly-claimed
    unchanged_by_this_plan: true — the private IP, the firewall and the transport are untouched
exception:
  justification: private-network-only registry link; integrity comes from cosign digest-pinning, not TLS; image bytes are public OCI layers
  tracking_issue: "#6897"
  reevaluate_when: the registry is exposed beyond the private network, or TLS is added to the link
  expires_on: 2026-10-22
```

---

## Observability

```yaml
liveness_signal:
  what: Better Stack heartbeat betteruptime_heartbeat.registry_prd (zot answers on its own private IP) + betteruptime_heartbeat.registry_disk_prd (/var/lib/zot under 85% used). Absence of a ping is the alert.
  cadence: 5 min (the SOLEUR_ZOT_DISK cron in cloud-init-registry.yml); heartbeat absence window per the Better Stack monitor
  alert_target: operator email via Better Stack
  configured_in: apps/web-platform/infra/zot-registry.tf (betteruptime_heartbeat.registry_prd / registry_disk_prd, passed into user_data as liveness_heartbeat_url / disk_heartbeat_url)

error_reporting:
  destination: Better Stack Logs source 2457081 (eu-fsn-3) via the host's vector sink; release-path failures surface in Sentry project web-platform via the ci-deploy zot-mirror bridge
  fail_loud: a SOLEUR_ZOT_DISK row carrying zot_memory_capped=false or zot_oom_kills>0 or state_status=unknown; on the release path, a failing zot-mirror bridge step in Web Platform Release

failure_modes:
  - mode: the repin lands but the derived ADR-062 memory cap silently changes (a wrong cap on a 4 GB host is #6288's uncapped condition)
    detection: apps/web-platform/infra/registry-boot-guard.test.sh asserts the cap comes from the templated zot_memory_cap_mb and that no 7168m literal exists on an executable line; the host itself self-reports zot_memory_cap_mb and zot_memory_capped in every SOLEUR_ZOT_DISK row, so no gate has to assume the cap
    alert_route: CI (infra-validation) pre-merge; Better Stack Logs post-apply
  - mode: the repin silently moves the rendered user_data and re-crosses the Hetzner 32,768 B cap, making every registry provisioning event fail at the API
    detection: bash apps/web-platform/infra/registry-userdata-budget.sh --json emits stored_bytes vs cap; plugins/soleur/test/cloud-init-user-data-size.test.ts carries the registry arm in CI. Read the JSON fields, never the exit code — the script exits 0 with a SKIP line when terraform is absent
    alert_route: CI (infra-validation) pre-merge
  - mode: a falsified stock premise is left standing in an operator-facing message under apps/web-platform/infra/, mis-steering whoever fires the #7287 dispatch
    detection: scripts/lint-diagnosis-claims.sh (ADR-166), BLOCKING in CI via the scripts shard of test-all.sh, ratcheting baseline 1
    alert_route: CI, pre-merge, fail-closed
  - mode: the declared type drifts back, or the merge unexpectedly plans a change against the live registry host
    detection: the merge-triggered apply-web-platform-infra.yml run's destroy-guard counters (host_creates / reboot_updates / resource_deletes) must all read 0 for the registry; the 12h drift detector re-plans untargeted
    alert_route: GitHub Actions run annotation + the drift detector's auto-filed issue

logs:
  where: Better Stack Logs source 2457081 (eu-fsn-3), grep marker SOLEUR_ZOT_DISK — this host has NO SSH ingress at all, so this is the only off-box read of its state; GitHub Actions run logs for the CI-side gates
  retention: Better Stack plan retention for source 2457081; GitHub Actions logs 90 days

discoverability_test:
  command: awk '/^variable "registry_server_type"/,/^}/ { if (sub(/^[ \t]*default[ \t]*=[ \t]*"/, "")) print substr($0, 1, index($0, "\"") - 1) }' apps/web-platform/infra/variables.tf
  expected_output: cpx22
```

**It reads the DECLARED type on purpose — do not "improve" it into a live probe.** The merge is
inert, so the live host stays `cx23` until #7287's dispatch fires; a command asserting `cpx22`
against the live API would correctly FAIL. Every off-box read of this host's real state is also
credential-gated (`doppler` / `hcloud`), which Check 10 rejects outright. The declared default is
the fact this PR actually changes. Shape borrowed from precedent `1c801040e`, which shipped the
same idiom through Check 10.

**It emits the BARE VALUE, not the line — and that is load-bearing, not style.** Check 10 matches
`expected_output` as a **substring** of stdout. A line-printing form is therefore spoofable: a
trailing comment turns `  default = "cx23" # was cpx22` into a PASS on a `cx23` default.
**Measured, both arms:** the line-printing form emits `  default = "cx23" # was cpx22` (contains
`cpx22` → false PASS); the form above emits bare `cx23` (→ correct FAIL). This is the exact defect
precedent B already measured and fixed — see `apps/web-platform/infra/git-data-luks.test.sh`
§*"COMMENT-STRIPPED, AND THE VALUE TAKEN FROM THE ASSIGNMENT — never `$NF`"*, whose own note
records `default = "cax11" # regressed from cpx22` defeating the naive predicate. Do not
"simplify" this back to a line print.

**Verification receipt** — executed in a byte-faithful reproduction of Check 10 Step 10.5
(`env -i PATH=/usr/local/bin:/usr/bin:/bin HOME="$HOME" timeout 15s bash -c "$CMD"`): `rc=0`,
stdout `cx23` against the real `variables.tf`, and `cx23` against a synthesized spoof file
carrying the trailing `# was cpx22` comment. All three pre-execution rejects (ssh /
credentialed-CLI / shell-active-token) were run against the literal and passed — `$0` is safe
because the reject pattern is `\$\{?[A-Za-z_]` and `0` is not in that class, and the single-`if`
form avoids the `;` that a multi-statement awk program would introduce (itself an instant FAIL).

---

## Domain Review

**Domains relevant:** Engineering, Finance, Operations

### Engineering

**Status:** reviewed
**Assessment:** A declared-only infra change on a sensitive path. The two substantive engineering
questions are Q1 (replace vs. in-place update — the repo asserts both, and this plan refuses to
promote either to fact without a measurement) and the claim-vs-file sweep discipline, where the
grep-invisible prose blocks are the real risk. The arch and memory-cap invariants were verified
by evaluating the actual derivations against the live catalog rather than by assertion. The
merge-inertness property was verified against the workflow's `-target=` allow-list and its `on:`
path filter, not assumed.

### Finance

**Status:** reviewed
**Assessment:** +EUR 14.00/mo (~+USD 15.12), 3.55× on this host, EUR 168/yr. Accepted by the
operator as the price of removing stock from the variable set on a one-way recreate. The shift is
**+6.77 %** of Product COGS, below the 10 % re-derivation threshold, so `cost-model.md` keeps its
subtotals and takes a label + forward-trigger note. The expense is recorded in the **same PR**
per `wg-record-recurring-vendor-expense-before-ready`; a follow-up would be non-compliant.
Ledger accuracy note: billing does **not** move at merge, so the row must not be overwritten in a
way that overstates burn — that is the exact defect #6453 corrected on the git-data row.

### Operations

**Status:** reviewed
**Assessment:** No new vendor, no new account, no new sub-processor — same Hetzner account, same
region (`hel1`), same DPA. Therefore no `article-30-register.md` or `compliance-posture.md` entry
is required. The operator-facing surfaces that decay are the recut runbook and the recut
workflow's comments; both are in scope.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Edit` / `## Files to Create`
matched **zero** paths (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any
UI-surface term). Product domain assessed **NONE** — infrastructure/tooling change with no
user-facing surface, so no `.pen` wireframe is required.

### GDPR / Compliance Gate

**Skipped, with the reason recorded.** The canonical regulated-data regex is not matched (no
schema, migration, auth flow, API route or `.sql` file). None of the four expansion triggers
fires either: (a) no new LLM/external-API processing of operator-session data, (b) the
brand-survival threshold is `aggregate pattern`, not `single-user incident`, (c) no new
cron/workflow reads `learnings/` or `specs/`, (d) no new artifact-distribution surface.

---

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-096 with an addendum — do not create a new ADR.** ADR-096 is the governing decision
for this host; the house pattern for a forced type repin is an addendum to the governing ADR
(`ADR-143` §*Addendum — 2026-07-26: web-2 repinned `cx23` → `cpx22`*) or a named sizing decision
inside it (`ADR-068` D-SIZE). **Because no new ordinal is claimed, the `/ship` ADR-Ordinal
Collision Gate has nothing to collide with here** — the recurring renumber hazard does not apply
to this PR.

The addendum records: the corrected 2026-08-06 measurement; the operator-confirmed
stock-volatility rationale (not the issue's framing); the cost; that arch stays `amd64` and the
ADR-062 cap stays 3072m; and that ADR-096's own blocker list must drop its `cx23`-stock clause.
Also correct the present-tense stock clause in **ADR-169**.

**Q1-independence is a hard constraint on this addendum.** Every sentence above is true
regardless of whether a `server_type` change is a replace or a reboot-forcing in-place update.
**ADR-096's existing `server_type is ForceNew` clause is left EXACTLY as found** — not corrected,
not softened, not annotated with a guess. An ADR is the artifact a future one-way recreate of the
sole pull path will cite; writing a side into it on the strength of a confounded plan reading is
strictly worse than leaving a recorded contradiction. The contradiction goes in the PR body as an
open question (AC16), not into the ADR.

Status stays `accepted` on both.

### C4 views

**Container view** only. `model.c4`'s registry node description carries the host type; it changes
from `cx23` to declared `cpx22`, using the file's declared-vs-live vocabulary so the description
does not claim a live state the merge cannot produce. The web-host node's "three grandfathered
hosts" clause is corrected per R3.

**No element and no relationship is added or removed — and here is the enumeration that supports
it**, performed against all three sources (`model.c4`, `views.c4`, `spec.c4`), not a keyword grep:

- **(a) External human actors** — `founder`, `emailSender`, `betaContact`, `contributor`. The only
  actor edge touching this subsystem is `betterstack -> founder` (paging on a missed registry
  heartbeat). A host-type change adds no actor and changes no actor edge.
- **(b) External systems / vendors** — already modelled and reachable from the registry:
  `projectZot` (the public upstream zot binary source), `ghcr`, `github`, `cloudflare` (the
  tunnel), `doppler`, `betterstack`, `sentry`. **Hetzner-the-vendor is deliberately not a distinct
  element** — the fleet is modelled as the container `platform.infra.hetzner` — so changing a
  Hetzner server type introduces no new vendor element by construction.
- **(c) Containers / data stores** — `zotRegistry` (a `#selfhosted` system) and
  `platform.infra.hetzner`. The registry's 60 GB store volume is **not** a separate element (unlike
  `workspacesVolume`, `gitDataStore`, `sessionStore`); it is folded into `zotRegistry`'s
  "volume-backed" description. The repin does not detach, resize or re-key it.
- **(d) Access relationships** — the nine edges on `zotRegistry`: `tunnel -> zotRegistry`,
  `github -> tunnel`, `github -> zotRegistry` (the ADR-169 restore path), `hetzner -> zotRegistry`
  (image pull), `hetzner -> zotRegistry` (consumer serviceability probe),
  `zotRegistry -> projectZot`, `doppler -> zotRegistry`, `zotRegistry -> betterstack`,
  `github -> betterstack`. **None changes.** `server_type` is a host attribute described inside
  `zotRegistry`, not an edge.
- **Views** — `zotRegistry` already appears in the `include` lists of **both** `view context` and
  `view containers` in `views.c4`, so it renders today. **No `views.c4` edit is required**, and no
  `view … include` line references an element this change could leave undefined.

So the C4 work is a **description edit plus a regeneration**, nothing structural.

Then: `bash scripts/regenerate-c4-model.sh`, `git add` the regenerated
`model.likec4.json`, and run the C4 validation tests.

### Sequencing

None. Both the ADR addendum and the C4 edit describe a state that is true the moment this PR
merges (the *declared* type), so nothing is deferred and no `status: adopting` note is needed.

---

## Implementation Phases

### Phase 0 — Preconditions (verify; do not assume)

0.1 Re-probe Hetzner `/v1/datacenters` `.server_types.available` for `hel1-dc2`, `nbg1-dc3`,
    `fsn1-dc14` for ids 114 (`cx23`), 109 (`cpx22`), 115 (`cx33`), 45 (`cax11`). Take **3
    samples**. Record the readings verbatim into the plan/PR. **If cx23 is no longer available,
    the corrected premise in this plan is itself stale — stop and re-state, do not silently fall
    back to the issue's original wording.** *What the 3 samples do and do not buy:* they guard
    against a transient bad API read. They say **nothing** about durability — three reads seconds
    apart measure one moment, which is precisely the argument for buying `cpx22` in the first
    place. Do not report them as a stability signal.
0.2 Re-read `/v1/server_types` for `cpx22` and `cx23` at `hel1`: confirm cores, memory, disk and
    `price_monthly.net`. Confirm `memory == 4` for `cpx22` — this is what makes the 3072m cap
    claim true.
0.3 Capture the pre-change `registry-userdata-budget.sh --json` baseline
    (`stored_bytes`, `cap`, `headroom`). **Read the JSON, never `$?`.**
0.4 Capture the pre-change `bash scripts/lint-diagnosis-claims.sh` census.
0.5 Read the `git_data_server_type` description in `variables.tf` **before** writing the new
    `registry_server_type` description. It is the house style and it already records this
    decision shape.
0.6 Read the two precedents. Use `git show --stat` for both — `1c801040e` is 2,094 insertions and
    a bare `git show` is unbounded output (`hr-never-run-commands-with-unbounded-output`). Then
    read only the named hunks: each commit's `variables.tf` and `expenses.md` changes.
0.7 Re-derive the sweep file list yourself — **case-insensitively**:
    `git grep -ci cx23 -- . | grep -v '^knowledge-base/project/\(plans\|specs\|brainstorms\|learnings\)/' | grep -v archive/`.
    The `-i` is load-bearing, not hygiene: `cost-model.md` and `expenses.md` carry `CX23` in row
    **labels**, and a case-sensitive grep misses `| Hetzner CX23 (zot registry, hel1) |` — the
    exact cell *Files to Edit* item 12 tells you to change. **Do not trust this plan's list** —
    reconcile any divergence in the PR body.
0.8 **Build the CLAIM INVENTORY — this is the sweep's actual unit of work, and without it the
    sweep is unfalsifiable.** A grep can prove a *token* is gone; nothing can prove a *claim* is
    gone, so "the six grep-invisible blocks" this plan names are only the six that happened to
    be noticed. Read **whole** — not grepped — `variables.tf`, `zot-registry.tf`,
    `cloud-init-registry.yml`, the ADR-096 registry-sizing and blocker passages, ADR-169's
    consequences, `model.c4`'s registry + web-host nodes, `registry-luks-recut-6929.md`, and the
    `registry_luks_recut` block of `apply-web-platform-infra.yml`. Emit a **numbered** inventory,
    one row per claim, each marked **REWRITE / KEEP / DELETE** with a one-line reason. Phase 5
    gates on every row having a disposition **and** a matching diff hunk (AC21).
0.9 **Propagation grep — the falsified premise may live outside the edit list.** Run a repo-wide
    `git grep -nEi 'unorderable|not orderable|cannot be rebuilt|0 of 3 EU' -- . ` and
    `git grep -ni cx23 -- .` (again case-insensitive), excluding
    `knowledge-base/project/{plans,specs,brainstorms,learnings}/`
    and `**/archive/**`. Any hit outside the twelve edited files is either folded in or explicitly
    scoped out with a reason in the PR body. Silence is not a result here — record the hit list.

### Phase 1 — The repin and its rationale

1.1 `variables.tf`: `default = "cpx22"`; rewrite the description and the block comment per *Files
    to Edit* item 1.
1.2 `zot-registry.tf`: prose corrections per item 2, including the three grep-invisible blocks.
1.3 `cloud-init-registry.yml`: the comment edit, **with its gate inline** — run
    `registry-userdata-budget.sh --json` immediately before and immediately after the edit and
    compare `stored_bytes`. If it moved, revert the (still-uncommitted) hunk and record why.
    The measurement belongs **here**, not in Phase 5: deferring it means reverting a committed
    hunk two phases later.
1.4 **Run `bash scripts/lint-diagnosis-claims.sh` at the END of Phase 1, not only in Phase 5.**
    Phases 1 and 4 both rewrite operator-facing prose inside the lint's scan scope
    (`apps/web-platform/infra/`), and a rewritten message that names stock as a cause is exactly
    what ADR-166 forbids. Catching it here costs one command; catching it in Phase 5 costs a
    re-run of every downstream edit.

### Phase 2 — Cost record (same PR; `wg-record-recurring-vendor-expense-before-ready`)

2.1 `expenses.md`: the registry row (declared vs. billing) and the "three hosts" paragraph.
2.2 `cost-model.md`: row label + forward-trigger note; **no subtotal re-derivation** (state the
    +6.77 % arithmetic).

### Phase 3 — Architecture record

3.1 ADR-096 addendum + its blocker-list correction (**leaving its `ForceNew` clause untouched**).
    ADR-169's stock clause.
3.2 `model.c4` — consistent with the enumeration already recorded under *Architecture Decision
    (ADR/C4) › C4 views*.
3.3 `bash scripts/regenerate-c4-model.sh`; `git add` `model.likec4.json`.
3.4 Run the C4 validation tests.

### Phase 4 — Operator surfaces

4.1 `registry-luks-recut-6929.md` precondition + blocker row.
4.2 `apply-web-platform-infra.yml` comment prose (the two that name the default).
4.3 `registry-userdata-budget.sh` comment.

### Phase 5 — Gates

5.1 `bash apps/web-platform/infra/registry-boot-guard.test.sh` — 0 failed.
5.2 `bash apps/web-platform/infra/registry-userdata-budget.sh --json` — final reading vs. the
    Phase-0 baseline (the gating comparison already ran inline at 1.3).
5.3 `bash scripts/lint-diagnosis-claims.sh` — census ≤ the Phase-0 baseline.
5.4 **The claim-inventory disposition gate (AC21):** every numbered row from Phase 0.8 has a
    disposition AND, for every `REWRITE`/`DELETE` row, a matching hunk in `git diff`. A row with
    no hunk is an unswept claim. Plus the AC3/AC4/AC22 read-through.
5.5 The C4 freshness + render tests.
5.6 Whatever `scripts/test-all.sh` shard covers the touched files.
5.7 `/soleur:preflight` — Checks 6 and 10 both fire on `apps/[^/]+/infra/`.

### Phase 6 — Tracker (work-phase, NOT planning)

6.1 **Correct #7309's own premise** — its title and body assert something now measurably false.
    Edit the title and body to carry the 2026-08-06 measurement and the operator-confirmed
    rationale. Also correct the two false file claims (R4, R5) so the next reader does not chase
    them.
6.2 **Comment on #7287** flipping its "Hetzner stock" blocking row. It currently reads *"not
    closable by any issue"*; that becomes false when this lands. The comment must carry the
    2026-08-06 measurement, name #7309/this PR as the closer of that row, and **must not restate
    the unorderable claim**. It must also preserve what is still true: #7278 and #6929 remain
    open, and stock must still be re-probed immediately before firing because it is not reserved.
6.3 `Closes #7309` in the **PR body** (not the title).

---

## Acceptance Criteria

**17 criteria; the numbering has gaps.** AC5/6/9/11/15/17 were cut at plan review as ceremony —
each verified that a *narration* happened rather than a post-condition on file state, command
output or merged behaviour. Their substance was folded into the survivors (AC5→AC3, AC6→AC14,
AC9→AC8, AC11→the plan's own C4 enumeration, AC15→AC19, AC17→`wg-use-closes-n-in-pr-body-not-title-to`).
IDs are left un-renumbered on purpose: they are referenced from the Implementation Phases and the
Risks table, and a renumber that missed one would silently point at the wrong check.

### Pre-merge (PR)

- [ ] **AC1 — the repin.** The `discoverability_test.command` from the `## Observability` block
      (block-scoped, comment-stripped, value-extracting) prints exactly `cpx22`. Block-scoping
      alone is insufficient — a bare `grep cpx22 variables.tf` is already green via
      `git_data_server_type` / `inngest_server_type`, and a line-printing form is spoofable by a
      trailing comment. Use the command verbatim; do not paraphrase it.
- [ ] **AC2 — the corrected premise is stated, not merely the old one deleted.** The **Phase-0.1
      probe date and reading** (not a hardcoded `2026-08-06` — 0.1 mandates a fresh probe and may
      run later) appears in `variables.tf`, `zot-registry.tf`, the ADR-096 addendum and
      `registry-luks-recut-6929.md`, each naming `.server_types.available`.
- [ ] **AC3 — the falsified premise is nowhere restated, and the claim-level sweep landed.** In
      the **files this PR edits**, no surviving line asserts that **`cx23` OR `cx33`** is
      unorderable / grandfathered / cannot be rebuilt / "0 of 3 EU DCs", **except** where the
      sentence is explicitly dated to a past probe. (The `cx33` half matters: `model.c4`'s
      web-host node asserts `cx33 is unorderable in all 3 EU DCs` twice, undated, with no `cx23`
      literal anywhere near it.) **Verification method:** read each edited hunk against the six
      grep-invisible content anchors named in *Files to Edit* items 1, 2 and 6 — `⚠ THIS EDIT
      ARMS A PENDING REPLACE…`, `That is an improvement only if the type is orderable.`,
      `CONSEQUENCE: do not run an untargeted apply…`, `…until a recreate on an orderable type.`,
      `the cx33 arm of this revert path is CLOSED`, and `the DR remediation for all three
      grandfathered hosts belongs to #6460` — **not** a bare token grep, which cannot see any of
      them.
- [ ] **AC4 — the still-true claims survive.** The `cax` line is still described as unavailable
      (measured: `cax11` id 45 unavailable in all three DCs); the `.available`-vs-`.supported`
      measurement-trap paragraph is intact; the `STOP, not a proceed` warning on a registry
      replace is intact; the "4 GB / 3072m / 4096m / 7168m-can-never-bind" reasoning is untouched.
- [ ] **AC7 — the render is measured before and after, and the measurement GATES the edit.**
      `registry-userdata-budget.sh --json` is run **immediately before and immediately after** the
      `cloud-init-registry.yml` comment edit, inside Phase 1 — not deferred to Phase 5, so a
      moved `stored_bytes` reverts an uncommitted hunk rather than a committed one. Both values
      recorded. **Read the JSON fields, never `$?`** — the script exits 0 on its SKIP path.
- [ ] **AC8 — the recurring expense is recorded in the SAME PR, on both ledgers.**
      `knowledge-base/operations/expenses.md` carries the registry row with the declared `cpx22`,
      the `EUR 5.49 → EUR 19.49/mo net` delta, the `+EUR 14.00/mo` / `EUR 168/yr` / `3.55×`
      figures, the `net == gross` verify-on-invoice caveat, and an explicit statement that
      **billing does not change until the replace applies**. `cost-model.md` carries the row label
      plus the `+$15.12 / $223.39 = +6.77 %` arithmetic, with its subtotals, break-even and margin
      figures unchanged.
- [ ] **AC10 — C4 is regenerated, not hand-edited.** `git diff --name-only` includes both
      `model.c4` and `model.likec4.json`; the C4 freshness/render/syntax tests pass. (The
      completeness enumeration is already recorded in the plan under *Architecture Decision
      (ADR/C4) › C4 views* — it is a plan deliverable, not a PR-body narration.)
- [ ] **AC12 — ADR-096 addendum exists** and ADR-096's blocker list no longer names `cx23` stock;
      ADR-169's present-tense stock clause is corrected while its `stock_preflight_gate`-still-
      applies statement survives.
- [ ] **AC13 — the ADR-166 lint does not regress.** `bash scripts/lint-diagnosis-claims.sh`
      reports a census **≤** the Phase-0 baseline. Run the gate's own invocation; do not
      hand-enumerate its input set.
- [ ] **AC14 — the existing boot guard stays green, and the derived invariants are measured.**
      `bash apps/web-platform/infra/registry-boot-guard.test.sh` reports `0 failed` (its
      `--memory` cap assertion is what mechanically pins the cap half). The PR body records, from
      the **live catalog**: `cpx22` → `startswith(…,"cax") == false` → `registry_arch = amd64`
      (unchanged), and `cpx22.memory == 4` → `local.registry_memory_cap_mb = 4×1024−1024 = 3072`
      (unchanged). No new assertion is added to this suite — see *Files NOT to Edit*.
- [ ] **AC16 — Q1 is left open, and nothing in the diff resolves it by implication.** No artifact
      in the diff asserts replace-vs-in-place, and **ADR-096's existing `server_type is ForceNew`
      clause is left exactly as found**. The PR body records the contradiction and routes it to
      #7287. A PR-body sentence that picks a side fails this AC.
- [ ] **AC21 — the claim inventory is complete and dispositioned.** The PR body carries the
      numbered Phase-0.8 inventory; every row has `REWRITE`/`KEEP`/`DELETE` plus a reason; and
      every `REWRITE`/`DELETE` row maps to a hunk in `git diff`. A row with no hunk fails this AC.
      This is the only check that makes the claim-level sweep falsifiable — a token grep cannot.
- [ ] **AC22 — the STOP-on-registry-replace guard survives, asserted by content anchor.** After
      the sweep, `zot-registry.tf` still contains a warning that a plan showing the registry being
      replaced is a **STOP, not a proceed**. Assert the *phrase*, not a bare token — this block is
      the last guard on destroying the sole pull path, it is incident-class, and only its **stock
      premise** dissolved, not the hazard.
- [ ] **AC23 — propagation is bounded.** The Phase-0.9 repo-wide grep hit list is recorded in the
      PR body, and every hit outside the twelve edited files is either folded in or scoped out
      with a reason. An empty result must be shown as an empty result, not omitted.

### Post-merge (verification — automated, no operator step)

- [ ] **AC18 — the merge is inert on the live host.** The `apply-web-platform-infra.yml` run
      triggered by this merge is green with `host_creates=0`, `reboot_updates=0`,
      `resource_deletes=0`, and no `hcloud_server.registry` address in its plan. Read from the run
      via `gh run view`; no dashboard eyeballing.
- [ ] **AC19 — #7309 corrected and closed**, with its title and body no longer asserting the
      falsified premise.
- [ ] **AC20 — #7287's "Hetzner stock" row flipped** by a comment carrying the 2026-08-06
      measurement, naming this PR, preserving the still-open #7278 / #6929 blockers and the
      re-probe-before-firing instruction, and not restating the unorderable claim.

---

## Test Scenarios

- **Given** `var.registry_server_type = "cpx22"`, **when** `local.registry_arch` is evaluated,
  **then** it is `amd64` (because `startswith("cpx22","cax")` is false) and `local.zot_image`
  still resolves to the amd64 repository — verified against the live catalog, not asserted.
- **Given** `cpx22.memory == 4` from the Hetzner catalog, **when**
  `local.registry_memory_cap_mb` is evaluated, **then** it is `3072`, so every existing comment
  reasoning about a 4 GB host and a 3072m cap remains true.
- **Given** only comment lines changed in `cloud-init-registry.yml`, **when**
  `registry-userdata-budget.sh --json` is re-run, **then** `stored_bytes` is unchanged (because
  `local.registry_rationale_strip` removes whole-line comments before `base64gzip`) — and if it
  is not, the comment edit is dropped.
- **Given** the merge lands, **when** `apply-web-platform-infra.yml` fires on the
  `apps/web-platform/infra/**` path filter, **then** the plan contains no `hcloud_server.registry`
  address and all three destroy-guard counters read 0.
- **Given** a future edit reintroduces an unmeasured causal claim under
  `apps/web-platform/infra/`, **when** `scripts/lint-diagnosis-claims.sh` runs in the `scripts`
  shard, **then** the census exceeds the baseline and CI fails (blocking).
- **Given** someone reverts `default` to `cx23`, **when** preflight Check 10 executes the
  discoverability command, **then** stdout is the bare string `cx23`, `cpx22` is not a substring,
  and the check FAILs.
- **Given** a reverted default disguised as `default = "cx23" # was cpx22`, **when** the same
  command runs, **then** stdout is still bare `cx23` and the check still FAILs — the
  comment-stripping value extraction is what makes this true, and a line-printing form would
  wrongly PASS. Both arms measured.

---

## Alternatives Considered

| Option | Why not chosen |
|---|---|
| **Keep `cx23`** — it is orderable again today | This is the option the corrected measurement makes *available*, and it is exactly what the operator rejected. `cx23` measured unorderable on 2026-08-04 and orderable on 2026-08-06; the apply is one-way, has no capacity reservation, cannot fire until #7278 and #6929 clear, and a failed revert needs a **second** successful create. Betting the sole pull path on a window that moved twice in 48 hours is the risk being bought out for EUR 168/yr |
| **`cpx12`** (1 vCPU / 2 GB, ~EUR 11.49/mo) | Halves RAM. The ADR-062 cap would derive to 1024m, and the *unmeasured* large-store boot-scan RSS is the one residual risk this host actually carries. Cheaper on paper, strictly worse on the failure mode that matters |
| **`cx33`** (4 vCPU / 8 GB, ~EUR 8.49/mo — and measured available today) | Cheaper than `cpx22` and more RAM. Rejected on the same volatility ground: `cx33` is in the same `cx` family whose availability has oscillated, and re-adopting the 8 GB shape re-opens #6288's unconfirmed OOM diagnosis that #6497/#6463 deliberately reverted. Worth naming explicitly rather than leaving as an unexamined cheaper option |
| **`cpx32`** (4 vCPU / 8 GB, ~EUR 35.49/mo) | The documented revert target if the 4 GB call is ever falsified. Not the default — the live telemetry (37 MB steady, ~1 MB/GB of store) does not support paying 6.5× |
| **Wait for stock to be "reliably" back** | Unfalsifiable — there is no signal that distinguishes "back" from "back until Thursday", and the `.available` field is a point-in-time reading by construction |
| **Ship the repin together with the apply** | `zot-registry.tf` states a plan showing a registry replace is a STOP; both precedents shipped the repin as its own PR on its own plan; and the apply is independently blocked by #7278 and #6929. Folding it in would also raise the brand-survival threshold to `single-user incident` |
| **Add the `validation` block for sibling parity (Q2)** | Fixes no defect, and forces an edit to the header comment of `stock-preflight-gate.sh` — the single file gating every destructive registry dispatch. Not a free fold-in on a repin PR |
| **Add a "declared default is cpx22" assertion to `registry-boot-guard.test.sh`** | Precedent B's `A17` earns its place because `cax11→cpx22` CROSSES the `cax` prefix boundary and pins a live derivation. Here the derivation is provably unchanged, so the assertion pins nothing — and the literal is already covered by AC1 and executed verbatim by preflight Check 10 |
| **Fix the whole-fleet "unorderable types" claim everywhere** | R3 shows it is false for all three hosts, but that is a fleet audit owned by **#6460**. Correct it where this PR already edits; do not expand |

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
Only risks whose mitigation is *not* simply "an AC covers it" are listed. The AC list is the
mitigation index; repeating it here would be a second copy of it.

| Risk | Mitigation |
|---|---|
| **Q1 is "resolved" by a confounded single plan reading.** `hcloud_server.registry` already has a pending replace, so ONE plan shows `["delete","create"]` whatever `server_type` does — and that reading would then be written into an ADR a future one-way recreate will cite **Q1 is not measured on this PR at all** — the confound is exactly why. Only a *differential* between a `cx23` plan and a `cpx22` plan would carry signal, and with the replace already pending the two are predicted identical, so the experiment returns UNKNOWN before it is run. Routed to #7287, which runs a plan anyway. AC16 enforces that nothing in the diff resolves it by implication and that ADR-096's `ForceNew` clause is left untouched |
| **The claim sweep is unfalsifiable as designed** — a grep proves a token is gone, nothing proves a *claim* is gone, so the six grep-invisible blocks named here are only the six someone noticed | Phase 0.8 builds a numbered claim inventory by reading the affected files **whole**; AC21 gates on every row having a disposition AND a matching diff hunk |
| The falsified premise has already propagated to files outside the edit list (other ADRs, runbooks, workflow prose) | Phase 0.9's repo-wide grep for `unorderable` / `cannot be rebuilt` / `0 of 3 EU` / `cx23`; AC23 requires the hit list be recorded and each hit folded in or scoped out |
| The STOP-on-registry-replace guard is deleted along with the false stock premise it sits beside — removing the last guard on destroying the sole pull path | AC22 asserts the surviving phrase by content anchor, not a bare token |
| The expenses row is overwritten to `cpx22 / $21.05 / active`, overstating burn months before the apply — the exact defect #6453 corrected on the git-data row | AC8 requires the **declared-vs-billing** split, with the billing trigger named (#7287's dispatch) |
| Stock moves again between planning and merge | Phase 0.1 re-probes and instructs a STOP-and-restate rather than a silent fallback to the issue's wording |
| Scope creep into #6460 (fleet audit) or #7027 (ADR-143 probe table) | Both named as out of scope in *Files NOT to Edit* and *Alternatives* |

---

## Sharp Edges

- **Preflight Check 10 EXECUTES the `discoverability_test.command`, and this plan's is already
  verified against it.** It rejects `ssh`, the credentialed-CLI set, and every shell-active token
  (`|`, `;`, `&&`, `>`, `<`, `&`, `$VAR`, `$( )`), with a 15 s cap. **Do not "improve" the command
  by adding a pipe to `jq` or `grep` — that is an instant FAIL**, and do not repoint it at the
  live host, which stays `cx23` until the apply.
- **`hcloud_server.registry` has a pending replace and no `ignore_changes = [user_data]`.** Any
  untargeted plan shows the registry being replaced. That is a **STOP, not a proceed** — this PR
  does not change it, and nothing here authorises firing an apply.
- **Read `.server_types.available`, never `.supported`, and never the `hcloud` CLI's location
  column.** Both of the latter report the SUPPORTED set. This is the trap that produced the
  original wrong reading; it is documented at the head of
  `tests/scripts/lib/stock-preflight-gate.sh` and must survive every edit in this PR.
- **`registry-userdata-budget.sh` prints `SKIP` and exits 0 when terraform is absent.** Reading
  `$?` alone is indistinguishable from "under cap". Always read the JSON fields.
- **A bare `grep cpx22 apps/web-platform/infra/variables.tf` is vacuously green** — two sibling
  variables already default to `cpx22`. Every assertion about the registry's declared type must
  be block-scoped to `variable "registry_server_type"`.
- **Two constants in this plan are inherited, not derived here.** The `~1.08` USD/EUR FX basis
  comes from `expenses.md`'s existing Hetzner rows (same basis as the web-2, git-data and inngest
  `cpx22` rows) — mirror it, do not re-derive it, and carry the same `net == gross` caveat those
  rows carry. The **10 % category-subtotal re-derivation threshold** is a dispatch-level
  instruction for this change, **not** a repo invariant — state it once with the arithmetic
  (`+$15.12 / $223.39 = +6.77 %`) and do not cite it as though `cost-model.md` defined it.
