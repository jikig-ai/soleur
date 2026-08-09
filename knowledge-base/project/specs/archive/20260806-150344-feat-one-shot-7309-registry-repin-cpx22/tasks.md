# Tasks — repin the container-registry host `cx23` → `cpx22` (#7309)

Plan: [`knowledge-base/project/plans/2026-08-06-chore-repin-registry-host-cx23-to-cpx22-plan.md`](../../plans/2026-08-06-chore-repin-registry-host-cx23-to-cpx22-plan.md)

Branch: `feat-one-shot-7309-registry-repin-cpx22` · PR #7325 (draft) · Closes #7309

> **Premise note — read before touching anything.** #7309 asserts `cx23` is unorderable in
> `hel1-dc2`. A live probe on **2026-08-06** (`.server_types.available`, 3 samples) found `cx23`
> **available in all three EU DCs**. The rationale of record is **stock volatility on a one-way
> recreate of the sole pull path**, not unorderability. Do not restate the falsified claim in any
> file, commit message, PR body or issue comment. This file deliberately retains `cx23` — it is a
> point-in-time migration record and is carved out of every residual-zero check.

---

## Phase 0 — Preconditions (measure; assume nothing)

- [ ] 0.1 Re-probe Hetzner `/v1/datacenters` `.server_types.available` for `hel1-dc2`,
      `nbg1-dc3`, `fsn1-dc14` × ids 114 (`cx23`), 109 (`cpx22`), 115 (`cx33`), 45 (`cax11`).
      **3 samples.** Record verbatim. If `cx23` is no longer available, **STOP and re-state** —
      do not silently fall back to the issue's original wording.
- [ ] 0.2 Re-read `/v1/server_types` at `hel1` for `cpx22` and `cx23`: cores, memory, disk,
      `price_monthly.net`. Confirm `cpx22.memory == 4` (this is what makes the 3072m cap claim
      true).
- [ ] 0.3 **Q1 is NOT measured here.** With a replace already pending on `hcloud_server.registry`,
      a single `terraform plan` returns `["delete","create"]` whatever `server_type` does — the
      reading is confounded, and the answer changes nothing this PR decides. Routed to #7287. Do
      not handle prod R2/Hetzner credentials on this PR.
- [ ] 0.4 Capture the pre-change `bash apps/web-platform/infra/registry-userdata-budget.sh --json`
      baseline (`stored_bytes`, `cap`, `headroom`). **Read the JSON, never `$?`.**
- [ ] 0.5 Capture the pre-change `bash scripts/lint-diagnosis-claims.sh` census.
- [ ] 0.6 Read the `git_data_server_type` description in `apps/web-platform/infra/variables.tf`
      **before** writing the new `registry_server_type` description — it is the house style.
- [ ] 0.7 Read the two precedents with `git show --stat` (a bare `git show 1c801040e` is 2,094
      insertions — unbounded output), then only the `variables.tf` and `expenses.md` hunks.
- [ ] 0.8 Re-derive the sweep file list independently — **`git grep -ci cx23`, case-insensitive**
      (`CX23` appears in `cost-model.md` / `expenses.md` row labels) minus
      `project/{plans,specs,brainstorms,learnings}` and `archive/`). Reconcile divergence from the
      plan's list in the PR body.
- [ ] 0.9 **Build the numbered CLAIM INVENTORY** by reading the affected files **whole**, not
      grepped. One row per claim, each `REWRITE` / `KEEP` / `DELETE` + reason. This is the unit
      the sweep is graded on (AC21).
- [ ] 0.10 Run the **propagation grep** (`unorderable|not orderable|cannot be rebuilt|0 of 3 EU`
      and `cx23`, both case-insensitive, repo-wide, minus the carve-outs). Record the hit list;
      fold in or scope out each hit outside the twelve edited files (AC23).

## Phase 1 — The repin and its rationale

- [ ] 1.1 `apps/web-platform/infra/variables.tf`: `default = "cpx22"`.
- [ ] 1.2 Rewrite the `registry_server_type` **description** to carry the operator-confirmed
      stock-volatility rationale, in the `git_data_server_type` house style.
- [ ] 1.3 Rewrite the block comment: the `STOCK REALITY` table → 2026-08-06; retire
      `GRANDFATHERED on cx23` / `CANNOT BE REBUILT` / `deliberately NOT changed here`; re-anchor
      the boot-scan-RSS sentence and the `cx33 arm … is CLOSED` revert path; correct the
      `DISASTER-RECOVERY GAP` three-hosts paragraph; re-anchor `cx23's 40 GB local disk` → 80 GB.
- [ ] 1.4 **PRESERVE** (do not sweep): the `cax`-line unavailability claim (still true), the
      `.available` vs `.supported` measurement-trap paragraph, and every "4 GB / 3072m / 4096m /
      7168m-can-never-bind" statement (unchanged — both types are 4 GB).
- [ ] 1.5 `apps/web-platform/infra/zot-registry.tf` — **prose only, no attribute changes**: the
      `cax11↔cx23 choice` block; the `server_type = …` inline comment; the
      `⚠ THIS EDIT ARMS A PENDING REPLACE…` banner (rewrite, do not delete); the
      `STOCK REALITY — live probe 2026-08-04` table; the `#6508's guard does NOT catch it` lesson
      (keep the distinction, drop the instance); and the `STOP, not a proceed` block — **keep the
      STOP**, only its stock premise dissolves.
- [ ] 1.6 `apps/web-platform/infra/cloud-init-registry.yml`: change the `cax11 / cx23 has Hetzner
      stock` comment. **KEEP** its other `cx23` hit (the historical `UNCAPPED-on-cx23` #6288 note).
      This file is **also** in the ADR-166 lint scope (`.yml` under `apps/web-platform/infra/`).
      **Gated on 1.7.**
- [ ] 1.7 Re-run the budget script **inline, before committing 1.6**; compare `stored_bytes`
      against 0.4. If it moved, revert the still-uncommitted hunk and record why (AC7).
- [ ] 1.8 Run `bash scripts/lint-diagnosis-claims.sh` **now**, not only in Phase 5 — census must
      not exceed the 0.5 baseline.

## Phase 2 — Cost record (same PR — `wg-record-recurring-vendor-expense-before-ready`)

- [ ] 2.1 `knowledge-base/operations/expenses.md`: the registry row — declared `cpx22`;
      `EUR 5.49 → EUR 19.49/mo net`; `+EUR 14.00/mo` / `EUR 168/yr` / `3.55×` /
      `~+USD 15.12 @ ~1.08 FX`; the `net == gross` verify-on-invoice caveat; and an explicit
      statement that **billing does not change until the replace applies** (trigger: #7287).
      Follow the web-2 row's declared-vs-billing shape. Do **not** overwrite to `active @ 21.05`.
- [ ] 2.2 `knowledge-base/operations/expenses.md`: the `Not a limit but the same class of latent
      risk` paragraph — all three named hosts measured orderable 2026-08-06; correct and point at
      #6460.
- [ ] 2.3 `knowledge-base/finance/cost-model.md`: the `Hetzner CX23 (zot registry, hel1)` row
      label + a forward-trigger note. **No subtotal re-derivation** — record the
      `+$15.12 / $223.39 = +6.77 %` arithmetic and that it is below the 10 % threshold.

## Phase 3 — Architecture record (`wg-architecture-decision-is-a-plan-deliverable`)

- [ ] 3.1 Append `## Addendum — 2026-08-06: registry repinned cx23 → cpx22 (#7309)` to
      **ADR-096**. Addendum, **not a new ADR** (house pattern: ADR-143 addendum, ADR-068 D-SIZE)
      — so no ordinal is claimed and the ship-time collision gate has nothing to collide with.
- [ ] 3.2 ADR-096: drop `cx23` stock from its blocker list. **Leave its `server_type is ForceNew`
      clause EXACTLY as found** — Q1-independence is binding.
- [ ] 3.3 **ADR-169**: correct the present-tense `cx23 … not in hel1-dc2` consequence; keep the
      `stock_preflight_gate still applies` statement.
- [ ] 3.4 The **C4 completeness enumeration is already done at plan time** — see the plan's
      *Architecture Decision (ADR/C4) › C4 views*. Re-read it; do not re-derive it.
- [ ] 3.5 `model.c4`: the registry node description → declared `cpx22`, using the file's
      declared-vs-live vocabulary (the live host is still `cx23` until the apply). Correct **all
      three** falsified clauses on the web-host node: the `soleur-registry (cx23) … NONE can be
      rebuilt` one, **and the two undated `cx33 is unorderable in all 3 EU DCs` clauses** (cx33
      measured available — and they carry no `cx23` literal, so a token sweep misses them). **Do
      NOT** touch that node's `0 of 3 EU DCs` sentence — it is explicitly dated to 2026-07-26.
- [ ] 3.6 `bash scripts/regenerate-c4-model.sh` → `git add`
      `knowledge-base/engineering/architecture/diagrams/model.likec4.json`. **Never hand-edit** —
      precedent A shipped RED here.
- [ ] 3.7 Run the C4 validation tests (`c4-code-syntax`, `c4-render`, and the freshness suite).

## Phase 4 — Operator surfaces

- [ ] 4.1 `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`: the
      2026-08-05 stock precondition → 2026-08-06; the #7309 "live blocker" row → resolved.
      **Keep the re-probe-before-firing instruction** — stock is not reserved.
- [ ] 4.2 `.github/workflows/apply-web-platform-infra.yml` — four `cx23` hits, three dispositions:
      re-anchor the **two** naming the registry default as `(cx23)`; **keep** the `#6460` comment
      that is already dated `on 2026-08-05`; and **date in place** the second `#6460` comment,
      which is undated and therefore fails AC3. Nothing here hardcodes the type as a probe input
      — it derives via `read_default`.
- [ ] 4.3 `apps/web-platform/infra/registry-userdata-budget.sh`: the
      `registry_arch is amd64 for the cx23 default` comment. This file is in the ADR-166 lint's
      scope — no unmeasured causal claim on an `echo`/`printf` line.
- [ ] 4.4 `apps/web-platform/infra/registry-boot-guard.test.sh` — **NOT edited.** A new
      declared-type assertion was cut at plan review: unlike precedent B's `A17` it would pin
      nothing derivational (the arch derivation is unchanged), and AC1 + preflight Check 10
      already assert the literal. The file's historical `cx23` note stays.

## Phase 5 — Gates

- [ ] 5.1 `bash apps/web-platform/infra/registry-boot-guard.test.sh` → `0 failed`.
- [ ] 5.2 `bash apps/web-platform/infra/registry-userdata-budget.sh --json` vs the 0.4 baseline.
- [ ] 5.3 `bash scripts/lint-diagnosis-claims.sh` — census ≤ the 0.5 baseline (BLOCKING in CI).
- [ ] 5.4 **Claim-inventory disposition gate (AC21):** every 0.9 row has a disposition, and every
      `REWRITE`/`DELETE` row has a matching hunk in `git diff`.
- [ ] 5.5 **AC22:** `zot-registry.tf` still carries the `STOP, not a proceed` warning — assert by
      content anchor, not a bare token.
- [ ] 5.6 AC3/AC4 read-through: no surviving **undated** assertion that `cx23` **or `cx33`** is
      unorderable; the still-true claims (cax line, `.available`/`.supported` trap, 4 GB/3072m
      reasoning) intact.
- [ ] 5.7 The `scripts/test-all.sh` shard(s) covering the touched files.
- [ ] 5.8 Run `/soleur:preflight` — Checks 6 and 10 both fire on `apps/[^/]+/infra/`.

- [ ] 5.9 **Q1 stays open:** confirm nothing in the diff asserts replace-vs-in-place, and that
      ADR-096's `server_type is ForceNew` clause is byte-identical to `origin/main` (AC16).

## Phase 6 — Tracker (work phase — **not** planning)

- [ ] 6.1 **Correct #7309's title and body.** They assert something measurably false. Replace with
      the 2026-08-06 measurement and the operator-confirmed rationale. Also correct its two false
      file claims: `tests/scripts/lib/stock-preflight-gate.sh` contains **zero** `cx23`, and the
      workflow's hits are at 2090/2115/2124/2142, not 2085/2094.
- [ ] 6.2 **Comment on #7287** flipping its `Hetzner stock` blocking row (currently *"not closable
      by any issue"*). Carry the 2026-08-06 measurement; name #7309/this PR as the closer of that
      row; **do not restate the unorderable claim**; and preserve what is still true — #7278 and
      #6929 remain open, and stock must still be re-probed immediately before firing.
- [ ] 6.3 `Closes #7309` in the PR **body**, not the title.

## Phase 7 — Ship

- [ ] 7.1 Capture a learning under `knowledge-base/project/learnings/` (directory + topic only;
      pick the date at write time). Topic: an issue's own premise can expire between filing and
      implementation — re-probe the vendor before inheriting it.
- [ ] 7.2 `/soleur:ship`.
- [ ] 7.3 **Post-merge (automated):** confirm the merge-triggered
      `apply-web-platform-infra.yml` run is green with `host_creates=0`, `reboot_updates=0`,
      `resource_deletes=0` and no `hcloud_server.registry` address in its plan (`gh run view`).
- [ ] 7.4 Confirm #7309 closed with its premise corrected, and #7287's stock row flipped.

---

## Out of scope — do not expand into these

- **The apply itself.** Delivering `cpx22` to the live host is #7287's guarded dispatch, blocked
  by #7278 and #6929. `zot-registry.tf` says a plan showing a registry replace is a **STOP**.
  This PR schedules no apply, so it **accepts no downtime and needs no maintenance window** — see
  the plan's `## Downtime & Cutover`, which also records the zero-downtime (blue-green)
  evaluation and hands it to #7287 / ADR-096 clause (g) / #6126 rather than closing it here.
- **#6460** — the fleet-capacity audit (all three "grandfathered" hosts measured orderable).
- **#7027** — the ADR-143 probe-table refresh.
- Files whose `cx23` references are historical records or derivation fixtures: `git-data-luks.test.sh`,
  `scripts/followthroughs/zot-restart-plateau-6288.sh`, the OOM post-mortem, the counsel audit,
  `article-30-register.md` / `compliance-posture.md` (web-2 only), `betterstack-log-query.md`.
