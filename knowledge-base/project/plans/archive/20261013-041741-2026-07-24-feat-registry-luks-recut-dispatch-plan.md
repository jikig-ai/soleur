---
title: "feat: guarded registry-luks-recut workflow_dispatch (three-way -replace)"
issue: 6929
type: enhancement
date: 2026-07-24
branch: feat-one-shot-6929-registry-luks-recut-dispatch
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: "yes-with-conditions (C1-C5, all applied — see §Domain Review)"
plan_review: "v2 — 7-agent panel applied (dhh, kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cpo, cto). Taste/User-Challenge items in specs/<branch>/decision-challenges.md"
---

# feat: guarded `registry-luks-recut` `workflow_dispatch` (three-way `-replace`)

`Closes #6929`

## Enhancement Summary

**Deepened on:** 2026-07-24
**Panel:** 7 review agents (dhh, kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cpo, cto-devex) + a learnings pass + a verify-the-negative citation sweep.

### Key improvements over v1

1. **The operator's entry point was a dead end.** v1 told the operator to read the volume id from the drift run's terraform refresh line. `scheduled-terraform-drift.yml:99` captures that output into a command substitution — it never reaches the step log. The id now comes from a bounded, one-command **Hetzner API** lookup, which also makes the id-pin a genuine cross-check rather than an echo of the state file it guards.
2. **The documented recovery was unreachable for two of three mid-apply failure windows.** v1's gate had only *replace* and *bare-create* arms, so a failure after the volume was recreated planned the volume as `no-op` and ABORTed the very re-dispatch the plan prescribed. Replaced with a **resume arm admitted by a live Hetzner existence probe** — evidence, not an operator checkbox — which also closes the partial-state-loss hole that all three of v1's brakes were silent on.
3. **The id-pin was vacuous in the arm that needed it most.** Arm selection moved from a per-invocation shell argument to a **per-change** predicate, and the lib now fail-closes on its own argument rather than inheriting the sibling's skip-on-empty idiom.
4. **The liveness gate could have gone green over a dark registry** by reading the dead host's residual `up` (period 60 + grace 30, and a heartbeat exposes no `last_ping_at`). Rebuilt as a tested `scripts/registry-heartbeat-poll.sh` that requires a **transition**, handles `paused`, and resolves the heartbeat id from tfstate rather than a name filter.
5. **One conditional gate shape became one unconditional shape.** v1 would have shipped one of two different gates depending on a live prod state read — unreviewable against the plan. Both new operator booleans were deleted along with it.
6. **A counter that could never fail was removed.** `resource_deletes` uniquely rejected nothing; neutralising it would have turned no test red, silently degrading the non-vacuity acceptance criterion from evidence to decoration.
7. **Mechanical enforcement replaced prose.** A cross-gate divergence test (the two registry gates must *disagree* on the same fixture), allow-set⇄`-target` parity across all three registry jobs, job⇄gate-lib pairing, and step-order assertions — plus per-case counter assertions in stdout, so non-vacuity re-runs in CI instead of resting on a hand-run matrix.
8. **`timeout-minutes: 30`** on a job that holds the fleet-wide apply mutex with `cancel-in-progress: false` — without it, a hung poll blocks every merge-apply for six hours.

### New considerations discovered

- The empty-store window after a recut is a **paging** window (`zot_mirror_fallback_rate`), not a quiet one, and nothing the operator controls bounds it — so the runbook now carries a one-command force.
- `hcloud_volume.workspaces` — the sole copy of `/mnt/data` — has **no** declarative destroy protection anywhere in the root. Adding `prevent_destroy` was surfaced as **DC-2**, not assumed, and the operator **cut it from this PR** on 2026-07-25: it is now tracked standalone in **#6943**. This plan's Terraform changes are **None**.
- `registry_region_migrate` already accepts the same bare creates with no confirm token, no id-pin and no opt-in, so this gate's strictness is locally sound but globally partial (**DC-3**).
- The `host_creates` HALT message is **already false** today; it is corrected rather than extended.
- Two ordering windows (firewall-naked on boot; NIC-guard reboot during `luksFormat`) are now recorded as accepted in the ADR rather than left implicit.

### Gates

Phase 4.6 (user-brand) PASS · 4.7 (observability) PASS · 4.8 (PAT-shaped) PASS, no matches · 4.9 (UI wireframe) N/A, no UI surface · 4.10 (encryption posture) PASS · **4.55 (downtime & cutover) fired and is now satisfied** — see §Downtime & Cutover. 4.5 (network-outage) did not fire: the trigger keywords appear only outside Overview/Problem/Hypotheses, and no resource this plan's terraform touches carries a `provisioner`/`connection` block (ADR-115 makes cloud-init-only a load-bearing condition of the exclusion contract). 4.4 (precedent-diff) satisfied inline — the gate lib's mandated header carries an explicit delta against `registry_region_migrate_gate.sh`, the id-pin idiom is diffed against `workspaces-luks-recut-gate.sh:145-149`, and the heartbeat-gating precedent is cited as `arm_one`. All cited AGENTS rule IDs verified active; all 12 cited issue/PR numbers verified live for both state and semantic role. A verify-the-negative sweep re-checked every negative/absolute claim and every `file:line` anchor against the tree: two citation-drift errors were found and corrected (`test-all.sh` `:386`→`:391`; `ci-deploy.sh` `:650`→`:657`), and every other claim resolved exactly as written.

**On line-number citations** (`cq-cite-content-anchor-not-line-number`): the `file:line` references in this plan body are *point-in-time review evidence*, each paired with the quoted content it proves, and they expire with the PR. Every citation that ships into a **durable** artifact — the gate-lib headers, the corrected posture-audit row, the ADR amendment — uses a content anchor, and AC16 enforces that for the audit row specifically.

> Spec lacks valid `lane:` (no `spec.md` on this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

PR #6926 (commit `d1ac91890`, 2026-07-24) shipped guest-side LUKS for the registry (zot) store volume: `hcloud_volume.registry` lost its `format = "ext4"` argument (it is now a raw device), `random_password.registry_luks` + `doppler_secret.registry_luks_key` were added, and `cloud-init-registry.yml` gained a `blkid`-TYPE discriminator that `luksFormat`s an **empty** device, no-ops on `crypto_LUKS`, and **FATALs on anything else**. That PR deliberately excluded the guarded recut dispatch (ADR-096 amendment → "deferred to a follow-up (#6929)"). This plan adds it.

One new `apply_target=registry-luks-recut` dispatch job performs the sanctioned recut as **one atomic apply**:

```
terraform plan -out=tfplan \
  -replace='hcloud_volume.registry' \
  -replace='hcloud_volume_attachment.registry' \
  -replace='hcloud_server.registry' \
  -target=<the 6 registry addresses>
```

A fresh **raw** volume ⇒ cloud-init's `blkid` **empty** arm ⇒ `luksFormat` ⇒ the store re-mirrors from GHCR on the next CI dual-push (**not** an automatic pull-through — see §Research Reconciliation). The apply is fenced by, in order: a pre-destroy **pull-path health** check, the sourced **destroy-guard**, a **live Hetzner existence probe** that admits the resume arm, `stock_preflight_gate`, a **pre-apply** web-1/workspaces zero-touch assert, and a post-apply **liveness poll**.

**Adding the job is CODE-ONLY, with no exceptions.** Every `zot-registry.tf` resource is an `OPERATOR_APPLIED_EXCLUSION`, so merging applies nothing there, and this PR carries **no** `.tf` edit at all (the one candidate, D13, was cut to #6943 — see DC-2). Merging this PR mutates no live infrastructure; firing the dispatch is the gated operator step.

### Why it matters — the footgun this removes

The operator must **NOT** use `registry-host-replace` for the recut. That dispatch **preserves** the volume (`store_destroyed == 0`, `volume_bad_update == 0`), so the replaced host boots cloud-init against the still-**plaintext ext4** volume, lands in the `blkid` `*)` arm — `refusing-non-luks-device … exit 1` — and **darks the registry**. Forgetting the `-replace` on the volume does the same.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified 2026-07-24) | Plan response |
|---|---|---|
| "Register any new guard test in `infra-validation.yml`." | **False.** That workflow runs named steps over `apps/web-platform/infra/*.test.sh` only; it registers **zero** `tests/scripts/test-*-gate.sh` suites. All six siblings register in `scripts/test-all.sh:335`-area, inside `want_scripts` (`:165`). | Register in **`scripts/test-all.sh`**. AC12. |
| Operator reads the volume id from the drift run's `hcloud_volume.registry: Refreshing state... [id=…]` line. | **False, and it is the operator's first step.** `scheduled-terraform-drift.yml:99` captures the plan into `PLAN_OUTPUT=$(… 2>&1)` — **nothing reaches the step log**; `:107` writes it to a temp file surfaced *only* into a GitHub **issue** on drift. `gh run view` shows only `No drift detected` / `::warning::Drift detected`. The same false instruction already propagated into `workspaces-luks-cutover-6604.md:42`. | **Source the id from the Hetzner API** (D9). One bounded command, and independent of the state file it guards. AC19. |
| "zot re-fills from GHCR" implies pull-through. | The zot config declares `storage` + `retention` only — **no `sync`/`onDemand` extension**. But `registry-region-migrate-gate.sh:15-16` *already* states the mechanism correctly ("re-fills from GHCR **on the next CI dual-push**"), so my v1 reconciliation mischaracterized the sibling. The empty-store window is the **already-shipped, precedented** posture. | No in-job backfill (D12). But the window is a **paging** window — `registry_pull_event ghcr-fallback` is `level: "warning"` (`apps/web-platform/infra/ci-deploy.sh:657`) wired to `zot_mirror_fallback_rate`, "the only no-SSH page gating the IRREVERSIBLE ADR-096 5.5 PAT" (`apps/web-platform/infra/sentry/issue-alerts.tf:1470`). Stated in the plan; the runbook gives the one-command force. |
| Parity suite runs under `bash scripts/test-all.sh scripts`. | **False.** `plugins/soleur/package.json` and `plugins/soleur/bunfig.toml` **do not exist**. The suite runs via `run_suite "plugins/soleur" bun test plugins/soleur/` at `scripts/test-all.sh:391`, inside **`want_bun`** (`:390`). Root `bunfig.toml:18` sets `pathIgnorePatterns = [".worktrees/**", "apps/web-platform/**"]` — and this branch **is** a worktree. | AC13 uses `bun test plugins/soleur/test/terraform-target-parity.test.ts`; Phase 0.5 verifies it is not silently skipped from a worktree path. |
| `-target` set is the 3 `-replace` addresses. | `-replace` does not scope; `-target` does. The 6-address set is byte-identical to `registry_region_migrate`'s (`apply-web-platform-infra.yml:1578-1583`). `doppler_secret.registry_luks_key` enters the closure **only** via `hcloud_server.registry`'s `depends_on` (`zot-registry.tf:433-438`); `random_password.registry_luks` rides in via the secret's `value` (`:240`). | 6 `-target`s; both LUKS-key addresses are **named-live**, not allow-set (D6). |
| "mirror `workspaces-luks-recut`" (which has `environment:`). | It is the **only** job here with one, because it touches sole-copy `/mnt/data`. All four host-replace/migrate jobs have none. An `environment:` naming an **unprovisioned** GitHub environment silently **auto-approves**. | Mirror typed-confirm + id-pin + sourced-gate; **no** `environment:` (D5). |
| Encryption posture prose is current. | `encryption-posture-ledger.json` was updated by #6926 and correctly says `live_verification: unavailable`. Two prose copies were **not**: the audit row (still `**plaintext ext4**`, `` `format = "ext4"` `` — a fragment #6926 **deleted**, `zot-registry.tf:449-460`, and a bare `:407` line-number citation) and `model.c4:268`. ADR-096's `lint-infra-ignore` comment body (`:493-497`) also still says "the deferred guarded dispatch #6929". | Sweep all three, phrased **code-declared / live-pending** (no live over-claim). AC15/AC16. |
| `hcloud_server.registry` "NO dispatch creates it". | **Already false.** `registry_region_migrate_gate` requires `server_created >= 1` via `index("create")` and its header states both are pure creates. | Correct the HALT claim, do not extend it (D14, AC14). |
| #6929 OPEN, #6895 its parent. | Verified: #6929 OPEN; #6895 CLOSED by PR #6926. | Proceed. |

**Premise Validation.** Every path, symbol and content anchor cited in this plan was verified against the tree by the review panel (see §Domain Review for the audit table). Two premises were falsified (the drift-log id source; the parity-suite runner) and one mischaracterized (the sibling's GHCR prose); all three are reconciled above.

## User-Brand Impact

**If this lands broken, the user experiences** one of two directions:

- *Guard too loose* — a mis-scoped destroy-guard PASSes a plan it should ABORT. The blast radius is not the registry (a disposable GHCR mirror with an atomic fallback) but what an un-caught `out_of_scope` could reach through the shared, **lock-less** (`use_lockfile = false`) `terraform-apply-web-platform-host` state: `hcloud_server.web["web-1"]` (unrebuildable `cx33`, no automated birth path — #6730) or `hcloud_volume.workspaces` (sole-copy `/mnt/data`). **Tail severity is `aggregate pattern`-shaped** — destroying that volume takes every workspace on the host, not one — while the declared threshold covers the expected case. The declarative brake this direction has never had (`prevent_destroy`, D13) is **not** in this PR: it was cut to **#6943** (DC-2), so this PR's protection for that address remains the jq `out_of_scope` invariant, exactly as for the five existing gates. Landing #6943 is what closes this direction structurally.
- *Guard too strict / vehicle never fireable* — the recut cannot run, `hcloud_volume.registry` stays physically plaintext indefinitely, and the ledger + corrected prose describe an encryption posture the live device does not have. This is why every ABORT path in §Operator flow has a named exit, and why AC19 enumerates transitions rather than topics.

**If this leaks:** no new secret material and no new data surface. The recut *reduces* exposure. `REGISTRY_LUKS_KEY` is read at boot from the isolated `soleur-registry/prd` Doppler config; never in `user_data`, never an argv positional; this plan adds no read site. Separately and deliberately: this repo is **public**, so the PR publishes the destroy recipe — resource addresses, the confirm literal, the dispatch line. That is acceptable because authorization is GitHub Actions write access plus a `CODEOWNERS`-gated workflow file, not obscurity; stating it beats asserting "no new data surface".

**Brand-survival threshold:** `single-user incident` (tail is aggregate-shaped, see above)

## Design decisions

<!-- lint-infra-ignore start -->
<!-- Sanctioned deferred-orchestrator prose: the block below DESCRIBES the operator-fired
     registry-luks-recut `workflow_dispatch` (the gated vehicle this plan ships), it does not
     prescribe a human-run terraform/SSH step. The linter matches on an actor token plus an
     imperative co-occurring, which this prose trips while naming the automated path. Same
     sanctioned wrapper already used for ADR-096's contract prose. See
     hr-no-ssh-fallback-in-runbooks. -->
| # | Decision | Rationale |
|---|---|---|
| D1 | `-target` set = the **6** `registry_region_migrate` addresses. | `-replace` does not scope. The logs-token secret must ride the same dispatch (4-secret boot guard). |
| D2 | `-replace` all three: volume, attachment, server, one saved plan. | Issue + ADR-096 contract. The NIC replaces transitively (`server_id` ForceNew); `nic_created` covers it. |
| D3 | **Two arms, selected by the plan's own delete-set — not by an operator checkbox.** *Recut arm*: the plan contains a `delete`/`forget` on `hcloud_volume.registry` ⇒ full-recut shape + strict id-pin. *Resume arm*: the plan contains **zero** deletes/forgets anywhere ⇒ admitted only on live evidence (D4). | A zero-delete plan cannot destroy anything, so the arm is non-destructive **by construction**. Replaces v1's `recovery_bare_create` boolean, which three reviewers called an unevidenced checkbox held by the same person at the same moment as the decision to recut. |
| D4 | **Live Hetzner existence probe admits the resume arm.** `GET /v1/volumes/<expected_id>` → **200 ⇒ ABORT** (the pinned volume still exists; the remedy is `terraform import`, never `create`). `GET /v1/servers?name=soleur-registry` → non-empty **and** the server is a planned create ⇒ ABORT. 404/empty ⇒ genuine loss, proceed. | The only proposed check whose evidence is **independent of the terraform state**. Replaces all three of v1's brakes: an unevidenced checkbox, a `luks_key_touched` clause that is silent for a state-loss confined to the recut's own resources, and a Hetzner-name-uniqueness "brake" that is really a post-authorization provider error. `HCLOUD_TOKEN` is already read and masked in the same step for `stock_preflight_gate`. |
| D5 | **No `environment:`**, **no** job-level `concurrency:` — inherit `terraform-apply-web-platform-host`. | Verified complete serializer: `apply-deploy-pipeline-fix.yml:144` shares the literal; `scheduled-terraform-drift.yml` is plan-only; `workspaces-luks-cutover.yml` runs no terraform. `cancel-in-progress: false` prevents a cancel mid-destroy. `web-1-swap` deliberately unused. |
| D6 | **`doppler_secret.registry_luks_key` + `random_password.registry_luks` are named-live, full 4-verb `luks_key_touched == 0`, unconditional.** The ABORT text names the remedy: *"the isolated Doppler config lacks the key — run the operator's untargeted apply first, then re-dispatch."* | v1's conditional D7 arm made a **code artifact's shape a function of a point-in-time state read**, contradicting its own rationale. Failure directions are asymmetric: strict-when-absent is a loud, recoverable ABORT; permissive-when-present leaves a permanently unnecessary exemption on the discriminator. Also: a first-apply exemption had to cover **both** addresses (`zot-registry.tf:168`, `:240`), which v1's wording did not. |
| D7 | *(retired — folded into D6.)* | |
| D8 | `stock_preflight_gate` after the destroy-guard, before apply. | All four siblings do. Destroy-before-create + no stock ⇒ the registry is destroyed and never lands (#6393/#6400/#6463). |
| D9 | **Id-pin is per-*change*, not per-invocation, and is sourced from Hetzner.** In the recut arm `before.id` must be **present** and `(before.id \| tostring) == $expected`; an absent id is a FAIL. The lib **fail-closes on its own argument** (`$expected` not `^[0-9]+$` ⇒ `return 1`), independent of the workflow check. Provenance: `GET /v1/volumes?name=soleur-registry-store`. | v1 selected the arm by a shell arg, so passing the recovery flag on a genuine replace of the **wrong** volume yielded `volume_id_mismatch = 0` — reintroducing one layer up the exact hole D9 exists to close. The sibling never has it (`workspaces-luks-recut-gate.sh:145-149` branches per change) — but that sibling's idiom is *skip-on-empty*, which this gate must not inherit. |
| D10 | **Pre-destroy pull-path health gate, zero-tolerance threshold**: `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep ghcr-fallback --grep local-cache --limit 20`; **≥1 row ⇒ ABORT**. Fail-closed if the query cannot run. **Phase 0.2 positive control**: prove the query returns rows on a known-degraded historical window; if it cannot be shown to ever go red, the step ships as a `::warning::`, not a gate, and that is recorded. | A healthy fleet emits **only** `registry=zot` (`apps/web-platform/infra/ci-deploy.sh:642-643`), so zero-tolerance has no false-abort surface and is a real number rather than v1's undefined "sustained hits". The precedent (`scheduled-zot-restart-loop.yml:229`) is a human-read issue body, so this is the first automated use — hence the positive control. Named remedy: the degradation must clear before re-firing; if the degradation *is* the reason to recut, that is an incident path, not a recut. |
| D11 | **Post-apply liveness assert, built as a tested script.** `scripts/registry-heartbeat-poll.sh`: resolve the heartbeat id from **tfstate** (`betteruptime_heartbeat.registry_prd`), never a name filter; read `BETTERSTACK_API_TOKEN` (a *different* secret from `betterstack-query.sh`'s `BETTERSTACK_QUERY_*`) and mask it; wait out `period + grace` = **90 s** or observe a non-`up` sample **before** the `up` window opens; then poll ≤ 8 min for `up`; treat `paused` as a **distinct** failure; fail-closed on an unreadable token. | The store is destroyed at apply-return, so there is no rollback target. But v1's naive poll could read the **dead host's residual `up`** (period 60 + grace 30) and go green over a registry that never came up — and a heartbeat exposes **no `last_ping_at`** (`apply-web-platform-infra.yml:801-804`), so `up` alone is never evidence of a *new* beat. `arm_one` (defined `:852`, called `:893-895`) in this same workflow is the precedent that heartbeat gating is legitimate *when it requires a transition* — which also answers the recorded "non-gating" note on the best-effort status step. |
| D12 | **No in-job backfill.** State the empty-store window, its **paging** consequence, and give the operator the one-command force (`gh workflow run web-platform-release.yml -f bump_type=patch`) plus "fire the recut immediately before a planned release". | The sibling's gate header already documents the mechanism correctly, so this is the shipped, precedented posture — not an open question. Phase 0.3 still verifies the *disposability premise itself* (CPO C3). |
| D13 | *(cut from this PR — deferred to **#6943**.)* `lifecycle { prevent_destroy = true }` on `hcloud_volume.workspaces` (`server.tf`) remains the right brake, and the analysis behind it stands: the sole copy of `/mnt/data` has **no** declarative protection, the only barrier is a hand-maintained jq invariant now in its sixth copy, and it is provider-enforced at **plan** time so it defends against all six gates and every future one. But it is a scope addition beyond #6929 that would flip §Infrastructure from "Terraform changes: None" to a real `.tf` edit. Surfaced as **DC-2**; operator cut it on 2026-07-25 so a prod-safety change to sole-copy `/mnt/data` is reviewed on its own merits rather than as a rider on a workflow PR. | |
| D14 | **Correct the `host_creates` HALT claim; do not extend it.** True invariant: *no dispatch creates the registry host from an empty **root**; two dispatches (region-migrate, luks-recut resume arm) re-create a host absent from state, gated by `out_of_scope` on the from-empty closure.* | The current message (`:504`) is already false — `registry_region_migrate` permits a pure create. |
| D15 | `timeout-minutes: 30` on the job. | It holds the **fleet-wide** apply mutex with `cancel-in-progress: false`. No declaration ⇒ GitHub's 360-minute default ⇒ a hung poll blocks every merge-apply for six hours. The D11 bound must be strictly less so its diagnostic wins over an opaque cancellation. |
<!-- lint-infra-ignore end -->

## Files to Edit

- **`.github/workflows/apply-web-platform-infra.yml`**
  - Inputs: add **`expected_registry_store_volume_id`** (string; the name avoids collision with `expected_luks_volume_id`, which is the *workspaces* volume and would otherwise read as the one to fill in). Prefix both id-pin descriptions and `confirm`'s with `[registry-luks-recut]` / `[workspaces-luks-recut]` tags. **No new boolean inputs** (D3/D4 removed both). Add a comment above `inputs:`: *`workflow_dispatch` caps at 10 inputs; 5 used. The next per-target input pair should split its target into a dedicated workflow (precedent: `workspaces-luks-cutover.yml`; the concurrency group is a shared literal and survives the split).*
  - Fix the `confirm` input's **comment block** (`:84-86`), which asserts the `environment:` reviewer gate is "the sole human authorization" — false for the registry target once `confirm` serves both.
  - `apply_target`: add `registry-luks-recut` to `options:`. Convert `description:` to a **block scalar** (`>-`) and shorten it to a pointer at the runbooks — it is already **1574 chars on one physical line**, is rendered as the field label above the dropdown a non-technical operator reads before firing a destructive apply, and every edit produces an unreviewable whole-line diff. (Its existing `registry-region-migrate` clause carries the "re-fills from GHCR" wording this PR is correcting elsewhere — evidence that nothing in that blob gets read.)
  - New job `registry_luks_recut` after `registry_region_migrate`.
  - Correct the `host_creates` HALT `hcloud_server.registry` line per D14. Anchor: `::error::  • hcloud_server.registry → NO dispatch creates it`.
- **`scripts/test-all.sh`** — one `run_suite "tests/scripts/registry-luks-recut-gate" …` line beside the `workspaces-luks-recut-gate` entry.
- **`plugins/soleur/test/terraform-target-parity.test.ts`** — five additions:
  1. `"registry_luks_recut"` in `stripDispatchJobs()` (`:449`) **and** its pin (`:424`). Not cosmetic: without it the new `-target`s fold into the per-PR coverage anchor.
  2. New `describe("registry-luks-recut dispatch -target/-replace set …")`: the 6 `-target`s, the 3 **sorted** `-replace` addresses, every base address an `OPERATOR_APPLIED_EXCLUSION`, and `expect(jobBlock).not.toContain("resource_changes")` (no re-derived inline jq copy).
  3. **Allow-set ⇄ `-target` parity across all three registry jobs** — regex the `def allow: [...]` array out of each gate lib and assert set-equality with its job's `-target` set. The identical 6-address set now lives in **six** places with nothing asserting agreement; a seventh registry resource would have to move in lockstep, and missing one surfaces as a mysterious `out_of_scope > 0`.
  4. **Job ⇄ gate-lib pairing**: each dispatch job sources **exactly one** `tests/scripts/lib/*-gate.sh` and it is the matching one. Two inverse, near-identically-named gates now exist; a copy-pasted `source` line silently inverts a destroy authorization.
  5. **Step-order assertion** (replaces AC9's eyeball): index ordering of markers inside the extracted job block — `betterstack-query` < `registry_luks_recut_gate` < `stock_preflight_gate` < web-1 zero-touch < `terraform apply` < `registry-heartbeat-poll`.
- **`knowledge-base/engineering/architecture/decisions/ADR-096-…zot.md`** — amend the 2026-07-24 amendment (`:478`): shipped vehicle, confirm token, id-pin + its Hetzner provenance; **and** record (a) the accepted empty-store/paging window, (b) the corrected `host_creates` invariant, (c) the accepted firewall-naked and NIC-guard-reboot ordering windows, (d) the `registry_region_migrate` residual (DC-3). Also sweep the `lint-infra-ignore` comment body (`:493-497`), which still calls #6929 deferred and which AC15's prose grep would miss. FOOTGUN paragraph byte-unchanged.
- **`knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md`** — the `hcloud_volume.registry` row: `**plaintext ext4**` → code-declared LUKS2 / live-pending; drop the `` `format = "ext4"` `` fragment (#6926 deleted the argument); replace the `zot-registry.tf:407` line-number citation with a content anchor.
- **`knowledge-base/engineering/architecture/diagrams/model.c4`** — same phrasing on the registry element's `AT REST: PLAINTEXT ext4 … Ledgered exception` sentence.
- **`knowledge-base/engineering/architecture/diagrams/model.likec4.json`** — regenerated only, via `bash scripts/regenerate-c4-model.sh`.

## Files to Create

- **`tests/scripts/lib/registry-luks-recut-gate.sh`** — `registry_luks_recut_gate <plan-json> <expected_volume_id> [probe_result]`. Header must carry: the permitted shapes; per-counter rationale; an explicit **delta-vs-`registry_region_migrate_gate.sh`** paragraph stating that gate's PASS predicate **would PASS the canonical recut plan** (a replace's actions include `"create"`), so this is that gate *plus* strictness clauses — not a different gate; the #6497 do-not-widen-the-allow-set rule; the firewall-attachment update-in-place note; and a countable debt marker:

  ```
  # SOLEUR-DEBT: 6th near-identical sourced destroy-guard (allow-set + positive-action filter +
  # counter parse-loop + verdict scaffold are byte-shared with registry-region-migrate-gate.sh and
  # registry-host-replace-gate.sh); extract a shared allow-set + counter-scaffold helper when a
  # 7th gate lib lands OR when any registry address must change in >1 gate in the same PR.
  ```

  (v1's marker named `/soleur:harvest-debt` as its own trigger — circular, and it would parse, so the rot-detector would report clean forever.)
- **`tests/scripts/test-registry-luks-recut-gate.sh`** — see §Test suite.
- **`scripts/registry-heartbeat-poll.sh`** — the D11 contract, with its own suite. Built in **Phase 1** alongside the gate lib so Phase 2 consumes a defined, tested contract (v1 had Phase 2 consuming a capability no phase defined).
- **`knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`** — see §Operator flow for the required contents.

## Gate design — `registry_luks_recut_gate`

Idiom from `registry-region-migrate-gate.sh`: allow-set + `IN(.address; allow[])`; positive-action filter `create|update|delete|forget` (excludes `no-op` and `read`, so a `data.*` read cannot false-abort); per-counter numeric parse-validation failing loud; every counter echoed before the verdict; fail-closed on a missing/unparseable plan JSON **and on its own arguments** (D9).

**Allow-set (6)** = the `-target` set: `hcloud_server.registry`, `hcloud_server_network.registry`, `hcloud_volume_attachment.registry`, `hcloud_firewall_attachment.registry`, `hcloud_volume.registry`, `doppler_secret.registry_betterstack_logs_token`.

**Named-live (excluded from `out_of_scope` so their own clause is the sole, legible catcher):** `doppler_secret.registry_luks_key`, `random_password.registry_luks`.

**Arm selection** is derived from the plan, not from an argument: `has_destroy` = any `delete`/`forget` on `hcloud_volume.registry`.

**Counters (9).** `resource_deletes` is **deleted** — five reviewers independently found it subsumed (a delete on the firewall attachment fails `firewall_ok`; on the logs secret, `logs_secret_destroyed`; on either named-live address, `luks_key_touched`; anything else, `out_of_scope`). It uniquely rejects nothing, so neutralising it would turn **no** test red and would have silently degraded AC4 from evidence to decoration.

| Counter | Definition |
|---|---|
| `server_provisioned` | recut arm: `delete` AND `create` on `hcloud_server.registry`. resume arm: `create` **or** `no-op`. |
| `volume_provisioned` | recut arm: `delete` AND `create`. resume arm: `create` **or** `no-op`. |
| `completion_progress` | resume arm only: ≥1 `create` across {volume, server, NIC, attachment}. A resume plan that creates nothing is not a recovery. |
| `volume_id_mismatch` | **Per change, never per invocation.** Recut arm: `before.id` absent OR `(before.id \| tostring) != $expected` ⇒ mismatch. Resume arm: the *probe* is the evidence (D4), so this counter is 0 and the gate refuses to run at all unless `probe_result == "absent"`. |
| `attachment_created` | recut arm: a `create`. resume arm: `create` or `no-op`. |
| `nic_created` | recut arm: a `create`. resume arm: `create` or `no-op`. |
| `firewall_ok` | actions exactly `["create"]` or `["update"]`. |
| `logs_secret_destroyed` | `delete`/`forget` on the logs-token secret (allow-set member — `out_of_scope` cannot see it). |
| `luks_key_touched` | full 4-verb on either named-live address (D6). |
| `out_of_scope` | any positive action on an address neither allow-set nor named-live. Sole rejecter of a from-empty birth. |

**PASS (rc = 0) iff** `out_of_scope == 0 && logs_secret_destroyed == 0 && luks_key_touched == 0 && volume_id_mismatch == 0 && server_provisioned >= 1 && volume_provisioned >= 1 && attachment_created >= 1 && nic_created >= 1 && firewall_ok >= 1`, plus `completion_progress >= 1` in the resume arm.

**From-empty birth is rejected by `out_of_scope`** — verified: the from-empty closure of the 6 targets also creates `hcloud_ssh_key.default`, `doppler_project.registry`, `doppler_environment.registry_prd`, `doppler_service_token.registry`, `betteruptime_heartbeat.registry_prd` + `registry_disk_prd`, `doppler_secret.zot_pull_token_registry` + `zot_push_token_registry`, `random_password.zot_pull` + `zot_push`, `hcloud_firewall.registry`, `hcloud_network.private`, `hcloud_network_subnet.private` — 13-14 out-of-scope creates. `data.hcloud_server_type.registry` is correctly excluded by the `read` filter. `hcloud_ssh_key.default` carries `ignore_changes = [public_key]` (`server.tf:106-108`), so the ephemeral CI key cannot false-abort.

**NO `[ack-destroy]` bypass** — the menu-ack dispatch is the authorization.

## Test suite — `tests/scripts/test-registry-luks-recut-gate.sh`

Mechanics mirror `test-workspaces-luks-recut-gate.sh`: `set -uo pipefail`; `source "${DIR}/lib/registry-luks-recut-gate.sh"` (the same bytes the workflow sources); `mktemp -d` + `trap`; `printf`-based builders, no heredocs; synthesized fixtures only (`cq-test-fixtures-synthesized-only`); `passes`/`fails` tally; `[[ "$fails" -eq 0 ]]` as the exit expression.

**Every case asserts the named counter in stdout, not just `rc`** — the gate's counter line is the contract (§Observability designates it the machine-readable ABORT reason), so this makes each case self-proving **durably, in CI**, instead of resting on a hand-run matrix that runs once and never re-runs:

```
out="$(registry_luks_recut_gate "$TMP/plan.json" "$ID" 2>&1)"; rc=$?
[[ $rc -eq 1 && "$out" == *"volume_id_mismatch=1"* ]]
```

Cases (≈22): canonical recut PASS · **volume `["no-op"]` ⇒ ABORT** (the exact `registry-host-replace` footgun — this is the case that proves the issue's purpose) · server `["no-op"]` in the recut arm ⇒ ABORT · attachment/NIC missing their create ⇒ ABORT ×2 · firewall `["create"]` ⇒ PASS · firewall `["delete"]` ⇒ ABORT · id mismatch ⇒ ABORT · **`before.id` absent in the recut arm ⇒ ABORT** · `before.id` as a JSON string vs numeric input ⇒ PASS (`tostring` normalization) · **empty/non-numeric `$expected` ⇒ ABORT** (the lib fail-closes on its own arg; the sibling's skip-on-empty idiom must not be inherited) · logs secret `["delete"]` ⇒ ABORT · `registry_luks_key` `["create"]` ⇒ ABORT · `registry_luks_key` `["update"]` ⇒ ABORT · `random_password.registry_luks` `["forget"]` ⇒ ABORT · out-of-scope on `hcloud_server.web["web-1"]` ⇒ ABORT · out-of-scope on `hcloud_volume.workspaces["web-1"]` ⇒ ABORT · from-empty birth shape ⇒ ABORT · plan JSON missing ⇒ ABORT · malformed JSON / unparseable counter ⇒ ABORT (fail-loud, never silently 0) · `data.*` read + unrelated no-ops ⇒ PASS.

**Resume-arm cases — one per mid-apply failure window** (v1 had only the both-bare-create shape, so two of three windows were untested *and* unreachable): (a) both volume+server bare create · (b) **volume `no-op` + server create** · (c) **volume + server `no-op`, attachment create** · (d) resume shape with `probe_result != "absent"` ⇒ ABORT · (e) resume shape with zero creates ⇒ ABORT (`completion_progress`).

**Cross-gate divergence block** (the mechanical enforcement of the preserve-vs-replace distinction, using fixtures the suite already builds): source `registry-host-replace-gate.sh` alongside, then assert the canonical recut fixture ⇒ recut gate PASS **and** host-replace gate ABORT, and the volume-`no-op` fixture ⇒ recut gate ABORT **and** host-replace gate PASS. The failure mode this catches is not "someone writes a wrong new gate" but "someone **harmonises** the two", which silently re-arms the footgun #6929 exists to remove — and no other case in the suite would go red for it.

## Operator flow — every abort has a named exit

The runbook must document each transition below; AC19 enumerates **transitions**, not topics.

| Step / abort | Exit |
|---|---|
| Obtain the volume id | One bounded command against Hetzner (**not** `gh run view --log`, which is unbounded and, per §Research Reconciliation, does not contain the id): `curl -s -H "Authorization: Bearer $HCLOUD_TOKEN" 'https://api.hetzner.cloud/v1/volumes?name=soleur-registry-store' \| jq -r '.volumes[0].id'` |
| confirm token / id regex ABORT | Re-fire with the corrected value. |
| D10 pull-path degraded | The degradation must clear first (check the `zot_mirror_fallback_rate` alert state); re-fire after. If the degradation *is* why you want to recut, that is an incident path, not a recut. |
| `luks_key_touched` ABORT | Run the operator's untargeted apply (the `OPERATOR_APPLIED_EXCLUSIONS` contract) so the Doppler key lands, then re-dispatch. The `::error::` states this verbatim (D6). |
| Other gate counters | Reconcile terraform state; `volume_id_mismatch` specifically means the address resolves to a different physical volume — STOP. |
| `stock_preflight_gate` ABORT | Nothing was destroyed. Wait for stock and re-fire, or — if the type is unavailable in this region generally — use `registry-region-migrate`. |
| Apply fails mid-recut | Re-dispatch with the **same** confirm + **same** id. The resume arm covers all three windows (D3/D4); the probe supplies the evidence, so no flag is needed. |
| D11 liveness never `up` | **Decision rule:** the volume is now `crypto_LUKS`, so `registry-host-replace` **is** the correct tool for a boot flake — the blanket do-not-use warning applies only to a *plaintext* volume. If the cause is `reason=device-absent` (the attachment lands after the server, and cloud-init's 60 s device wait logs `refusing to luksFormat/mount a missing device` and continues, consuming the per-instance `runcmd` — the reopen unit then refuses to format a raw device and the zot mount-gate FATALs forever), the host will **never** self-heal and a **full recut** is required. Discriminate with `scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK`. |
| Success | The store is empty. It re-fills on the next CI dual-push — **and until then `ghcr-fallback` pages** via `zot_mirror_fallback_rate`. Force it now with `gh workflow run web-platform-release.yml -f bump_type=patch`, or schedule the recut immediately before a planned release. |
| Any follow-up recut | The dispatch summary emits the **new** volume id (D11 area) — without it the next recut is blocked until the next 12 h drift run. |

## Implementation Phases

Contract before consumer; test before lib.

### Phase 0 — Preconditions (only premise-falsifying reads)

<!-- lint-infra-ignore start -->
<!-- Sanctioned deferred-orchestrator prose: the block below DESCRIBES the operator-fired
     registry-luks-recut `workflow_dispatch` (the gated vehicle this plan ships), it does not
     prescribe a human-run terraform/SSH step. The linter matches on an actor token plus an
     imperative co-occurring, which this prose trips while naming the automated path. Same
     sanctioned wrapper already used for ADR-096's contract prose. See
     hr-no-ssh-fallback-in-runbooks. -->
0.1. `zot-registry.tf`: no `prevent_destroy`, no `create_before_destroy`, fixed name literals (`soleur-registry` `:325`, `soleur-registry-store` `:450`); `hcloud_server.registry`'s `depends_on` includes `doppler_secret.registry_luks_key` (`:433-438`). Re-verify the from-empty closure enumerated in §Gate design against `zot-registry.tf` + `network.tf`; if any member is inside the allow-set or named-live set, add an explicit `birth_shape` counter.
0.2. **D10 positive control** — prove `betterstack-query.sh --grep ghcr-fallback --grep local-cache` returns rows on a known-degraded historical window (i.e. that web-host syslog actually reaches the queried table). If it cannot be shown to go red, the step ships as a `::warning::` and that is recorded in the PR body. A health gate that can only ever be green is worse than none.
0.3. **Disposability premise** — is every tag currently in the live zot store guaranteed present in GHCR? A locally-built image, a GHCR-retention-pruned tag, or a manually deleted package version makes the recut **data loss** and invalidates both D12's accepted-risk record and the §User-Brand Impact framing.
0.4. Re-read the `blkid` discriminator (`cloud-init-registry.yml`, anchor `#6895: guest-side LUKS-at-rest mount + resize of the zot store volume`): three arms `""` → `luksFormat`, `crypto_LUKS` → no-op, `*)` → `exit 1`, plus the empty-key guard and the 60 s device wait. The plan's whole justification rests on the empty arm firing for a fresh Hetzner volume.
0.5. **Runner reality** — confirm `bun test plugins/soleur/test/terraform-target-parity.test.ts` actually collects from **this worktree** given root `bunfig.toml:18` `pathIgnorePatterns = [".worktrees/**", …]`. If it does not, AC13 must run from the main checkout and that is recorded.
0.6. Verify the Hetzner name-uniqueness premise from the vendor's documented `uniqueness_error` behaviour (D3's `create_before_destroy`-is-impossible claim rests on it) — `hr-verify-repo-capability-claim-before-assert`.
0.7. `bash scripts/regenerate-c4-model.sh` on the **unmodified** tree → no-op diff, so the committed `model.likec4.json` diff is attributable to the `model.c4` edit alone.
<!-- lint-infra-ignore end -->

### Phase 1 — RED then GREEN (gate lib + heartbeat poller)

1.1. Write `tests/scripts/test-registry-luks-recut-gate.sh` (all cases incl. the resume-arm windows and the cross-gate divergence block). Run — MUST fail. Record RED.
1.2. Write `tests/scripts/lib/registry-luks-recut-gate.sh` per §Gate design, with the full header block.
1.3. Write `scripts/registry-heartbeat-poll.sh` + its suite per D11.
1.4. All green. `shellcheck` clean on all three new shell files.
1.5. One-time mutation spot-check (belt-and-braces only — the per-case counter assertions are now the durable evidence): neutralise `volume_provisioned`, `volume_id_mismatch`, `luks_key_touched`, `out_of_scope` and confirm each turns ≥1 case red, asserting the `return 1` halt. Revert each.

### Phase 2 — Workflow job

<!-- lint-infra-ignore start -->
<!-- Sanctioned deferred-orchestrator prose: the block below DESCRIBES the operator-fired
     registry-luks-recut `workflow_dispatch` (the gated vehicle this plan ships), it does not
     prescribe a human-run terraform/SSH step. The linter matches on an actor token plus an
     imperative co-occurring, which this prose trips while naming the automated path. Same
     sanctioned wrapper already used for ADR-096's contract prose. See
     hr-no-ssh-fallback-in-runbooks. -->
2.1. Inputs + `confirm` comment/description fixes + `apply_target` block scalar + the input-budget comment.
2.2. Add `registry_luks_recut` after `registry_region_migrate`, `timeout-minutes: 30` (D15), no `environment:`, no job-level `concurrency:`. Steps in this order:
  1. checkout / setup-terraform / Doppler CLI — SHA-pinned, byte-identical to siblings.
  2. Validate `confirm == "RECUT-REGISTRY-LUKS"` and `expected_registry_store_volume_id =~ ^[0-9]+$`. Inputs via `env:`, never inline `${{ }}` in `run:`.
  3. **D10** pull-path health gate.
  4. Ephemeral SSH keygen for `var.ssh_key_path`.
  5. `DOPPLER_TOKEN` present; extract + mask R2 creds.
  6. `terraform init -input=false -lockfile=readonly`.
  7. **Plan + destroy-guard.** `set +e`/`rc=$?`/re-enable idiom; 3 `-replace` + 6 `-target` + `-var="ssh_key_path=${CI_SSH_PUB}"`; `terraform show` to `tfplan.txt`/`tfplan.json`. Read + mask `HCLOUD_TOKEN`; run the **D4 probe** and pass its verdict to the gate. Source the lib, call `registry_luks_recut_gate`. On ABORT: `::error::` naming each counter in operator language plus its exit from §Operator flow, then `grep -E 'will be destroyed|must be replaced|will be created|Plan:' tfplan.txt | head -40 >&2`. "NO `[ack-destroy]` bypass on this path."
  8. `stock_preflight_gate tfplan.json` (`HCLOUD_TOKEN` already exported).
  9. **Pre-apply zero-touch assert** — `hcloud_server.web["web-1"]`, `hcloud_volume.workspaces["web-1"]`, `hcloud_volume_attachment.workspaces["web-1"]` each show **0** positive actions. Its own step, **before** apply: in v1 these ran *after* the mutation from the same `tfplan.json` the gate already read, so they added no information and could prevent nothing.
  10. `terraform apply tfplan` + post-apply **completeness** backstops (the replace-or-resume shapes) — these correctly stay post-apply.
  11. **D11** `scripts/registry-heartbeat-poll.sh`. Failure `::error::` names both the `blkid`-arm FATAL **and** `reason=device-absent`, with the `SOLEUR_ZOT_DISK` discriminator query and the §Operator flow decision rule.
  12. Best-effort `soleur-registry-disk-prd` status — informational, swallows every error.
  13. **Dispatch summary** (`if: always()`) — reason, status, run URL, the **new `hcloud_volume.registry` id** (read from `terraform state show -json`; a known-after-apply create has no `after.id` in `tfplan.json`), and the empty-store + paging sentence with the force command.
2.3. Correct the `host_creates` HALT per D14.
2.4. `actionlint`; `bash -c` the extracted `run:` snippets (never `bash -n` on the `.yml`).
<!-- lint-infra-ignore end -->

### Phase 3 — Registration + parity

3.1. `scripts/test-all.sh` entry. 3.2. The five `terraform-target-parity.test.ts` additions. 3.3. Sweep for any other artifact enumerating dispatch jobs or target sets: `git grep -ln "registry_region_migrate\|workspaces_luks_recut" -- tests/ scripts/ plugins/ .github/`.

### Phase 4 — Terraform + docs

4.1. *(cut — D13 `prevent_destroy` deferred to #6943 per DC-2. No `.tf` edit in this PR; no `terraform validate` step needed.)*
4.2. ADR-096 amendment incl. all four records (D12/D14/ordering windows/DC-3 residual) + the `lint-infra-ignore` comment sweep. File the DC-3 tracking issue. **Also record the DC-5 cold-vehicle disposition** (see §Cold-vehicle re-verification trigger): the dispatch ships unfired, and the ADR names the mandatory pre-first-fire re-verification.
4.3. The runbook, covering every row of §Operator flow. No SSH.
4.4. Audit-row + `model.c4` corrections + `regenerate-c4-model.sh`.

### Phase 5 — Verification

`bash tests/scripts/test-registry-luks-recut-gate.sh` · the heartbeat-poller suite · `bash scripts/test-all.sh scripts` (suite name must appear in the **output**) · `bun test plugins/soleur/test/terraform-target-parity.test.ts` · `c4-code-syntax` + `c4-render` · `python3 scripts/lint-encryption-posture.py --repo-sweep` · `actionlint` + `shellcheck` · `terraform validate` · full `bash scripts/test-all.sh`.

## Architecture Decision (ADR/C4)

**ADR:** amend ADR-096 (heading `### Guest-side LUKS at-rest for the store volume (amendment 2026-07-24, #6895)`). No new ADR — the decision is already recorded there; what changes is that the vehicle ships, plus the four newly-explicit records in Files to Edit. Required by `wg-architecture-decision-is-a-plan-deliverable`.

**C4:** read all three of `{model.c4,views.c4,spec.c4}` (a keyword grep is not sufficient evidence). Enumeration: **external human actors** — none added (the operator is already modelled); **external systems/vendors** — none added (Hetzner, Doppler, Better Stack, GHCR, GitHub Actions all modelled); **containers/data stores** — none added (`hcloud_volume.registry` is already an attribute of the registry element); **actor↔surface access relationships** — none changed (a new *path* along an existing operator→Actions→Hetzner relationship). ⇒ **no new elements, tags, relationships or `view … include` lines.** One existing description is falsified (by #6926, not by this change) and is corrected as **code-declared / live-pending** — asserting live encryption before the dispatch fires would be a live over-claim (#6897 precedent).

**Sequencing:** none. The decision is true at merge. No soak ⇒ no follow-through enrollment.

## Infrastructure (IaC)

### Terraform changes

**None.** No `.tf` file is edited by this PR — no new resource, provider, variable or lifecycle block. The one candidate (D13, `prevent_destroy` on `hcloud_volume.workspaces`) was surfaced as **DC-2** and **cut by the operator on 2026-07-25**; it is tracked standalone in **#6943**.

The registry resources remain `OPERATOR_APPLIED_EXCLUSION`s, so the new dispatch job applies nothing on merge. Merging this PR therefore mutates no live infrastructure whatsoever.

### Apply path

<!-- lint-infra-ignore start -->
<!-- Sanctioned deferred-orchestrator prose: the block below DESCRIBES the operator-fired
     registry-luks-recut `workflow_dispatch` (the gated vehicle this plan ships), it does not
     prescribe a human-run terraform/SSH step. The linter matches on an actor token plus an
     imperative co-occurring, which this prose trips while naming the automated path. Same
     sanctioned wrapper already used for ADR-096's contract prose. See
     hr-no-ssh-fallback-in-runbooks. -->
(c) `-replace`, only when an operator fires the dispatch. No `provisioner`/`remote-exec`/`connection` block exists on the registry resources (a load-bearing condition of the exclusion contract per ADR-115), so the network-outage checklist does not fire.
<!-- lint-infra-ignore end -->

**Blast radius when fired:** destroy attachment → destroy NIC + server → destroy volume → create volume → create server → create NIC + attachment (forced: `user_data` interpolates `hcloud_volume.registry.id` at `zot-registry.tf:349`). Registry down for the apply plus first boot (single-digit minutes); store empty afterwards until the next CI dual-push, which is a **paging** window. No web/user-facing downtime. Two ordering windows are **accepted and recorded in the ADR** rather than left implicit: the firewall attachment is update-in-place on `server_ids`, so the host boots with a public IP and no firewall for seconds; and the NIC guard holds reboot authority, so a guard reboot can land mid-`luksFormat`.

### Distinctness / drift safeguards

`out_of_scope == 0` bounds the dispatch. The provider-enforced brake that would sit underneath it (D13) is **not** in this PR — cut to #6943 per DC-2 — so `out_of_scope` is the sole barrier here, as it already is for the five existing gates. The workflow-level concurrency group is the sole serializer for the lock-less R2 backend (verified complete — D5) and is inherited unchanged. No new secret value enters state beyond what the 2026-07-24 guest-side-LUKS PR already put there.

### Vendor-tier reality check

N/A — no new vendor resource. Hetzner **stock** (not quota) is the constraint, covered by `stock_preflight_gate`; `-replace` is net-zero on caps.

## Cold-vehicle re-verification trigger (DC-5)

**Operator answer, 2026-07-25: no registry LUKS recut is currently scheduled. This ships cold — deliberately, with the risk recorded rather than left silent.**

#6929's own re-evaluation criteria said "add it when the first live recut is scheduled." Neither that trigger nor the second-region trigger is asserted, so this PR builds the vehicle before the trip has a date. The consequence is real and must not be soft-pedalled: **the dispatch merges with zero live executions**, and every gate in it — the D10 pull-path check, the destroy-guard, the D4 Hetzner existence probe, `stock_preflight_gate`, the D11 heartbeat transition poll — will first meet production at the single highest-stakes moment, an irreversible destroy of the store volume.

What makes shipping cold defensible rather than reckless is that the *guard logic* is not cold: the gate lib is exercised by ~22 synthesized fixtures in `tests/scripts/test-registry-luks-recut-gate.sh` (including the exact `registry-host-replace` footgun case), the heartbeat poller is a tested script rather than an inline poll, and the cross-gate divergence + allow-set⇄`-target` parity tests fail loudly if the two inverse registry gates are ever harmonised. What is genuinely untested is the *live-API* surface — the two Hetzner probes and the Better Stack query — none of which can be exercised without either firing the dispatch or reaching prod.

**Mandatory pre-first-fire re-verification.** This is a gate on the first live fire, not a suggestion, and it belongs in the runbook (Phase 4.3) and the ADR amendment (Phase 4.2). Before the first-ever `-f apply_target=registry-luks-recut`:

1. **Re-run the D10 positive control.** Confirm `betterstack-query.sh --since 24h --grep ghcr-fallback --grep local-cache` still returns rows on a known-degraded historical window. A silently-renamed marker or a rotated `BETTERSTACK_QUERY_*` credential turns a zero-tolerance gate into a gate that can never go red — indistinguishable from a healthy fleet at the moment it matters.
2. **Dry-run the two Hetzner probes by hand** (`GET /v1/volumes?name=soleur-registry-store`, `GET /v1/servers?name=soleur-registry`) and confirm both return the shape D4/D9 parse. An API version bump or a resource rename makes the id-pin's provenance step fail *after* the operator has already typed the confirm token.
3. **Confirm the heartbeat id still resolves from tfstate** (`betteruptime_heartbeat.registry_prd`) and that `period + grace` is still 90 s — D11's transition window is derived from those numbers, and a Better Stack config change silently shortens or lengthens the window it waits out.
4. **Re-read the ADR-096 amendment's ordering-window records.** They were accepted against the infra as of 2026-07-24; if `zot-registry.tf` or `cloud-init-registry.yml` changed since, the accepted windows may no longer be the actual ones.
5. **Fire immediately before a planned release** (D12/DC-6), so the empty-store paging window is bounded by a dual-push the operator controls rather than by whenever CI next happens to run.

If step 1 or 2 fails, the correct move is to fix the probe and re-verify — **not** to proceed with a degraded gate. A gate that cannot fail is worse than no gate, because it is read as evidence.

## Downtime & Cutover

*(deepen-plan Phase 4.55 — fires because the plan `-replace`s an `hcloud_server`, which the provider applies by destroying and recreating the host.)*

**The offline-inducing operation.** `terraform apply` destroys `hcloud_server.registry` before creating it (forced: `hcloud_volume.registry` is also replaced and `user_data` interpolates its id, and both resources carry fixed name literals that Hetzner enforces as unique, so `create_before_destroy` cannot be used). **Affected surface: the zot registry at `10.0.1.30:5000`** — offline for the apply plus first boot, single-digit minutes, then serving an **empty** store until the next CI dual-push.

**Zero-downtime evaluation — the *serving* surface already has it, by design.**

The surface users depend on is not zot; it is the **host image-pull path**. ADR-096 ships an **atomic GHCR fallback** on that path: `ci-deploy.sh` tries `registry=zot` and falls through to `registry=ghcr-fallback` (and, since #6512, to `local-cache`) without failing the deploy. So for the duration of the recut *and* the subsequent empty-store window, deploys continue — degraded and paging, never broken. **This plan defaults to that path** and hardens it rather than routing around it:

<!-- lint-infra-ignore start -->
<!-- Sanctioned deferred-orchestrator prose: the block below DESCRIBES the operator-fired
     registry-luks-recut `workflow_dispatch` (the gated vehicle this plan ships), it does not
     prescribe a human-run terraform/SSH step. The linter matches on an actor token plus an
     imperative co-occurring, which this prose trips while naming the automated path. Same
     sanctioned wrapper already used for ADR-096's contract prose. See
     hr-no-ssh-fallback-in-runbooks. -->
- **D10** refuses to start when the fallback is *already* degraded — i.e. it refuses to create the one situation in which this operation would become a real outage (the #6400 shape).
- **D11** proves the new host actually came back, so the offline window is bounded by evidence rather than by assumption.
- The **empty-store window** is bounded by the operator: fire the recut immediately before a planned release, or force the re-mirror with `gh workflow run web-platform-release.yml -f bump_type=patch`.
<!-- lint-infra-ignore end -->

**Blue-green for the registry itself — evaluated, rejected.** Standing up a second registry host and cutting the pull path over would remove even the minutes-long zot outage. It is rejected because the pull endpoint is a **single-sourced pinned constant**: `local.registry_private_ip` (`10.0.1.30`) is interpolated into `user_data`, into `ci-deploy.sh`'s registry address, and into the first-boot NIC guard — which holds **reboot authority** on a mismatch. A second host therefore means a second private IP plus a coordinated re-point of every consumer, and the NIC guard would have to be taught that two addresses are legitimate. That is a strictly larger and riskier change than the fallback it would replace, for a surface whose outage the fallback already covers. Revisit only if the registry ever becomes a hard dependency (i.e. if the GHCR fallback is retired at ADR-096 Phase 5.5) — at which point blue-green stops being optional.

**Residual downtime accepted:** zot offline for the apply + first boot, then an empty store until the next dual-push.
**Justification:** non-user-facing; covered by a designed, tested fallback; the alternative costs more risk than it removes.
**Bounded window:** `timeout-minutes: 30` caps the job; D11 caps the boot wait at ~8 min and fails loud rather than hanging; the operator chooses the wall-clock window (AC23) and can collapse the empty-store tail to one command.
**Per-stage verification / rollback:** D10 (pre-destroy, nothing mutated on abort) → destroy-guard + D4 probe (pre-destroy) → `stock_preflight_gate` (pre-destroy — the check that the create is *feasible* before the destroy runs) → pre-apply zero-touch assert → apply → D11 liveness. Rollback after the destroy is not available by construction (the store is gone); the substitute is the resume arm, which makes a plain re-dispatch complete any partially-applied recut, plus the `registry-host-replace`-vs-full-recut decision rule in §Operator flow.
**Operator sign-off:** AC23 — firing the dispatch *is* the sign-off, and it is deliberately not performed by this PR.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.registry (zot OCI store, /var/lib/zot)
    mechanism: guest-side LUKS2 (cryptsetup luksFormat --type luks2, mapper "registry")
    evidence: cloud-init-registry.yml anchor "#6895: guest-side LUKS-at-rest mount + resize of
      the zot store volume"; key from random_password.registry_luks ->
      doppler_secret.registry_luks_key (REGISTRY_LUKS_KEY, isolated soleur-registry/prd);
      scripts/encryption-posture-ledger.json row kind "guest-luks-volume"
    defends_against: offline read of the detached/decommissioned Hetzner block device;
      hypervisor-side volume snapshot exfiltration
    does_not_defend: live compromise of the registry host (mapper open while running); the
      Doppler config holding REGISTRY_LUKS_KEY; anything an authenticated zot pull can read
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable: code-declared only until this dispatch first fires; the
      LIVE volume remains plaintext ext4 until then (no live over-claim — #6897). No zot-host
      at-rest posture probe yet; tracked #6895."
in_transit:
  - connection: hosts -> zot (10.0.1.30:5000, Hetzner private network)
    tls: off (plain HTTP on the private net)
    cert_verification: n/a
    does_not_defend: an attacker inside the private network can read pull traffic; integrity
      comes from cosign digest-pinning, not confidentiality
    disclosed_as: not-publicly-claimed
exception:
  status: code-closed, live-pending
  justification: the live flip is a destructive recut requiring an operator-chosen window
  tracking_issue: 6895 (closed by PR #6926); vehicle #6929 (this PR)
  reevaluate_when: the operator fires apply_target=registry-luks-recut
  expires_on: n/a (no time-boxed exception; the vehicle ships here)
```

## Observability

```yaml
liveness_signal:
  what: Better Stack heartbeat "soleur-registry-prd" (betteruptime_heartbeat.registry_prd,
    zot-registry.tf:526-529) — period 60s, grace 30s. scripts/registry-heartbeat-poll.sh polls
    it as a GATING post-apply assert, requiring a TRANSITION (a heartbeat exposes no
    last_ping_at, so a terminal "up" can be the dead host's residual state for period+grace).
    "soleur-registry-disk-prd" (period 900s) stays best-effort/informational.
  cadence: 60s host ping; the poller waits >=90s then polls <=8 min
  alert_target: Better Stack on-call policy for the registry host
  configured_in: apps/web-platform/infra/zot-registry.tf + uptime-alerts.tf
error_reporting:
  destination: GitHub Actions run log + job summary (::error::). The gate echoes EVERY counter
    by name before its verdict, so the ABORT reason is machine-readable from the log — and the
    test suite asserts on that same line, making it a contract rather than a detail. Host boot
    events reach Better Stack Logs via the isolated BETTERSTACK_LOGS_TOKEN (#6244).
  fail_loud: true — the gate fail-closes on a missing plan JSON, a jq failure, a non-numeric
    expected id, and any counter not matching ^[0-9]+$. D10 fail-closes when its query cannot
    run; the poller fail-closes on an unreadable BETTERSTACK_API_TOKEN.
failure_modes:
  - mode: pull-path already degraded — destroying the store would remove the last source
      (#6400/#6512; a host on registry=local-cache reads clean on a ghcr-fallback-only check)
    detection: D10 pre-destroy gate, BEFORE any terraform step, zero-tolerance threshold
    alert_route: job fails with the named remedy; no prod mutation occurred
  - mode: gate ABORT (not the scoped recut; wrong physical volume; passphrase create/rotate;
      resume arm without live evidence)
    detection: the counter line + the named ::error:: clause
    alert_route: operator sees the failed run; no prod mutation occurred
  - mode: stock preflight ABORT
    detection: stock_preflight_gate ::error::, BEFORE apply
    alert_route: nothing stranded (#6393/#6463 averted); exit is wait-or-region-migrate
  - mode: apply fails mid-recut (any of three windows)
    detection: apply-step ::error::; both registry heartbeats go missing; CI pulls fall through
      to GHCR (non-blocking)
    alert_route: heartbeat-missing alert + the failed run; remedy is a plain re-dispatch, which
      the resume arm admits on live Hetzner evidence
  - mode: recut succeeds but the volume did not come up LUKS (blkid-arm regression, empty
      REGISTRY_LUKS_KEY, or reason=device-absent — which is terminal and never self-heals)
    detection: the D11 poller never observes the up TRANSITION (the zot launch mount-gate
      refuses to start unless /var/lib/zot is /dev/mapper/registry); code-side gate is
      apps/web-platform/infra/registry-luks.test.sh (#6895)
    alert_route: the job FAILS (not a silent green) + heartbeat-missing alert; the ::error::
      carries the registry-host-replace-vs-full-recut decision rule
logs:
  where: Actions run logs + step summary; host events in Better Stack Logs (SOLEUR_ZOT_DISK,
    SOLEUR_PRIVATE_NIC), queryable off-box via scripts/betterstack-query.sh
  retention: Actions default; Better Stack per plan retention
discoverability_test:
  command: >-
    gh run list --workflow=apply-web-platform-infra.yml --limit 20
    --json databaseId,displayTitle,conclusion,event,createdAt
    | jq -r '.[] | select(.event=="workflow_dispatch") | "\(.createdAt) \(.conclusion) \(.displayTitle)"'
  expected_output: one row per dispatch with its conclusion; `gh run view <id> --log` then shows
    the gate's counter line (out_of_scope=… volume_provisioned=… volume_id_mismatch=…
    luks_key_touched=… …) and, on ABORT, the named clause + its exit. Host-side follow-up is
    `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep
    SOLEUR_ZOT_DISK`. No host shell access anywhere in this path.
```

No soak-gated close criterion ⇒ §2.9.1 does not fire. No blind execution surface ⇒ §2.9.2 does not fire.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — the gate lib defines exactly one function: `grep -c '^registry_luks_recut_gate()' … → 1` **and** `grep -cE '^[a-z_]+\(\) \{' … → 1` (the second is what actually asserts "exactly one" — the first only proves *this* function is defined once).
- **AC2** — `def allow:` is exactly the 6 D1 addresses; named-live is exactly the 2 LUKS-key addresses; `resource_deletes` does **not** appear.
- **AC3** — `bash tests/scripts/test-registry-luks-recut-gate.sh` exits 0, ≥22 passed / 0 failed, including all five resume-arm cases and the cross-gate divergence block.
- **AC4** — **every** ABORT case asserts its named counter in the gate's stdout (not `rc` alone). Grep-checkable: no test case matches `rc -eq 1` without an accompanying `"$out" == *"<counter>="*` assertion.
- **AC5** — the volume-`["no-op"]` case ABORTs (the `registry-host-replace` footgun) and the absent-`before.id` case ABORTs (the vacuous-pin hole).
- **AC6** — the job `-replace`s exactly, sorted, `['hcloud_server.registry','hcloud_volume.registry','hcloud_volume_attachment.registry']`.
- **AC7** — `grep -c 'registry_luks_recut_gate' <workflow> → 3` (sibling parity: header comment + step comment + call — all three siblings measure 3; v1's `→ 1` would have forced stripping explanatory comments from a prod-destroy job) **and** `grep -c 'source .*registry-luks-recut-gate\.sh' <workflow> → 1`. No-inline-copy is asserted mechanically by the parity suite's `not.toContain("resource_changes")`.
- **AC8** — `confirm` and the id are validated before any terraform step; every dispatch input reaches `run:` via `env:`.
- **AC9** — step order asserted **mechanically** by the parity suite (marker index ordering), not by reading.
- **AC10** — no `environment:`, no job-level `concurrency:`, and `timeout-minutes: 30` present.
- **AC11** — `registry-luks-recut` in `options:`; `description:` is a block scalar and does not claim automatic pull-through.
- **AC12** — exactly one `run_suite "tests/scripts/registry-luks-recut-gate"` in `scripts/test-all.sh`, and the suite name appears in the **output** of `bash scripts/test-all.sh scripts`.
- **AC13** — `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes with all five additions (strip-list + pin; the new describe block; allow-set⇄`-target` parity across the three registry jobs; job⇄gate-lib pairing; step order).
- **AC14** — the `host_creates` HALT states the **corrected** invariant (no dispatch creates the host from an empty *root*; two re-create a host absent from state, gated by `out_of_scope`).
- **AC15** — ADR-096's amendment contains `apply_target=registry-luks-recut` and records the empty-store/paging window, the corrected HALT invariant, the two ordering windows, and the `registry_region_migrate` residual; **and** neither the prose paragraph nor the `lint-infra-ignore` comment body still calls #6929 deferred. FOOTGUN paragraph byte-unchanged.
- **AC16** — neither the posture audit nor `model.c4` describes the volume as plaintext, **and** neither asserts the LIVE volume is encrypted; the audit row no longer contains `format = "ext4"` and cites a content anchor, not `:407`. `model.likec4.json` regenerated by script; `c4-code-syntax` + `c4-render` pass.
- **AC17** — `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0.
- **AC18** — `actionlint` clean; `shellcheck` clean on all three new shell files; `terraform validate` passes with D13.
- **AC19** — the runbook exists and documents **every row of §Operator flow** (each abort's exit, the D11 decision rule, the empty-store force command, the new-id emission), gives the bounded one-command Hetzner id lookup, and carries the do-not-use-`registry-host-replace` warning **scoped to the plaintext case**. SSH assertion is anchored, not a bare token: `grep -nEi '(^|[^a-z])(ssh|scp|rsync)[[:space:]:]'` returns only lines that are explicit no-SSH statements.
- **AC20** — the dispatch summary emits the post-apply `hcloud_volume.registry` id.
- **AC21** — `bash scripts/test-all.sh` (full) exits 0.
- **AC22** — the PR body carries `Closes #6929` and records the Phase 0 determinations: the from-empty closure re-verification, the **D10 positive-control result** (gate or warning), the **disposability answer** (0.3), the worktree runner answer (0.5), and the name-uniqueness citation (0.6). It also records the two operator dispositions of 2026-07-25: **DC-2 cut to #6943** (so Terraform changes are None) and **DC-5 ships cold**.
- **AC24** — the **cold-vehicle re-verification trigger** (§Cold-vehicle re-verification trigger, DC-5) appears in **both** durable artifacts, not just this plan: the operator runbook (Phase 4.3) and the ADR-096 amendment (Phase 4.2), each carrying all five numbered pre-first-fire checks. A grep for the runbook's heading must resolve; a plan-only record does not satisfy this criterion, because the plan is not what the operator reads before firing.

### Post-merge (operator)

- **AC23** — *(gated operator step — deliberately NOT performed by this PR.)* Firing the recut, **preceded by the five-step cold-vehicle re-verification** (AC24) since this vehicle ships unfired. **Automation status: automated** — pre-flight, guard, live probe, stock check, apply and post-apply verification are all this dispatch; the id is one bounded command. What remains operator-owned is the *decision to fire* and the choice of window, which is scheduling judgement. No credential mint, no dashboard click, no SSH.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The resume arm is a birth path. | Rejected by `out_of_scope` on the ~13-member from-empty closure (verified), and admitted only on a live Hetzner 404 (D4) — evidence, not a checkbox. |
| Partial state loss (`state rm` of just server+volume, or an R2 rollback) looks exactly like a legitimate resume. | The D4 probe is the discriminator: if the pinned volume still exists in Hetzner, the plan is not recovery and the remedy is `terraform import`, not `create`. This is the case where all three of v1's brakes were silent. |
| The id-pin's provenance is the artifact it guards. | Sourced from the Hetzner API, not a terraform refresh line (D9) — and the drift line does not exist anyway. |
| Mid-apply failure strands the operator. | Three windows, all covered by the resume arm and all fixture-tested. |
| Firing while GHCR fallback is also degraded (#6400/#6512). | D10, zero-tolerance, both signals, fail-closed — with a Phase 0 positive control so it is not a gate that can only be green. |
| Green job over a dark registry. | D11 requires an `up` **transition** after the residual window, handles `paused`, and its `::error::` carries the recovery decision rule. |
| `device-absent` leaves a permanently non-LUKS host. | Named explicitly in the D11 diagnostic with its discriminator query; the exit is a full recut, which the emitted new id (AC20) makes possible immediately rather than after 12 h. |
| Someone harmonises the two inverse registry gates. | The cross-gate divergence block fails the build; the parity suite pins job⇄lib pairing. |
| The 6-copy registry allow-set drifts. | Parity assertion across all three registry jobs. |
| `registry_region_migrate` accepts the same creates unguarded. | Recorded as an accepted residual in the ADR + a tracking issue (**DC-3**). |
| A hung poll blocks every merge-apply for 6 h. | `timeout-minutes: 30`, with the poller bound strictly less. |
| The store is not actually disposable. | Phase 0.3 verifies it before ship; a negative answer invalidates D12 and the User-Brand framing and must re-derive both. |
| The C4/audit correction over-claims live encryption. | AC16 requires code-declared / live-pending in both, mirroring the ledger. |

## Alternative Approaches Considered

| Alternative | Verdict |
|---|---|
| Reuse `registry-region-migrate`. | **Rejected** — no `-replace` flag (it relies on a location change), no id-pin, location-agnostic by design. But note it *would* PASS the canonical recut plan, which is why the new gate's header must say it is that gate plus strictness clauses, not a different gate. |
| A `mode` flag on `registry-host-replace-gate.sh`. | **Rejected** — its load-bearing asserts are the exact inverse. A boolean would put "preserve" and "destroy" behind one flag in the artifact that authorizes prod destroys. |
| `recovery_bare_create` / `first_luks_key_create` operator booleans (v1). | **Rejected on review** — an unevidenced checkbox held at the same moment as the decision to recut, and (for the latter) asking a non-technical operator to assert a fact about terraform state internals. Replaced by the D4 live probe and D6's unconditional strictness. |
| Ship one of two gate shapes chosen from a live state read (v1's D7). | **Rejected** — makes a code artifact's shape a function of a point-in-time read, and the PR becomes unreviewable against the plan. |
| An `environment:` reviewer gate. | **Rejected** — parity with all four siblings; an unprovisioned environment silently auto-approves. |
| Refactor the six gate libs onto a shared jq builder. | **Rejected** — risk ≫ benefit on a prod-destroy path. The duplication that actually costs is the 6-copy allow-set, answered by a 30-line parity assertion instead. |
| Automate a `crane copy` backfill into the job. | **Rejected** — the sibling ships this window as its accepted posture and documents the mechanism correctly; the operator gets the one-command force instead. |
| Split the gate lib and the workflow job across two PRs. | **Rejected** — a gate with no consumer is inert, and `Closes #6929` requires the vehicle. |
| Defer the C4/audit corrections. | **Rejected** (CPO called it the only defensible defer, with a tracking issue — see **DC-4**). |

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` matched zero open scope-outs against every planned path.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering — plan-review panel (7 agents)

**Status:** reviewed. `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `cto` (devex lens). Escalated to 5 eng agents by the `single-user incident` threshold; `cpo` + `cto` activated by the independent relevance read.

**Verified against the tree** (all confirmed): `scripts/test-all.sh:335` inside `want_scripts:165`; parity-suite helpers at `:449`/`:1134`/`:524`/`:1166`; the HALT line at `:504`; ADR-096's heading + `lint-infra-ignore` wrapper at `:478`; `betterstack-query.sh`'s repeatable `--grep`; the 6-address `-target` set byte-identical to `:1578-1583`; the `depends_on` edge at `zot-registry.tf:433-438`; no `prevent_destroy`/`create_before_destroy` + fixed name literals at `:325`/`:450`; `stock_preflight_gate` usage at `:1610-1628`; the D4 from-empty closure (13-14 out-of-scope creates); `hcloud_ssh_key.default`'s `ignore_changes`; D5's concurrency completeness; the forced destroy/create ordering.

**Falsified, and fixed above:** the drift-log id source (P0, spec-flow — the operator's entry point was a dead end, and the same false instruction had already propagated into a shipped runbook); the recovery arm's reachability (P0, spec-flow + architecture — two of three mid-apply windows ABORTed the documented remedy); the id-pin's per-invocation arm selection (P0, kieran) and its vacuity in the resume arm (P0, architecture); D11's residual-`up` false green (P0, kieran) and its missing implementation surface (P1, kieran); `resource_deletes`'s non-existent unique coverage (P0, dhh + cto + kieran + simplicity + architecture); AC7's `→ 1` (P1, kieran); the parity-suite runner and `plugins/soleur/package.json` (P1, kieran); the already-false HALT invariant (P1, architecture); the missing `timeout-minutes` (P1, architecture); post-apply placement of the pre-apply-shaped backstops (P1, architecture); D10's undefined threshold and misquoted precedent (P0/P1, dhh + kieran); D7's live-state-dependent artifact shape (P2, architecture) and its one-address exemption bug (P1, kieran); the circular `SOLEUR-DEBT` trigger (P1, cto); the 6-copy allow-set with nothing asserting agreement (P1, cto); the prose-only preserve/replace distinction (P0, cto); the hand-run mutation matrix as sole evidence (P1, cto); the 1574-char single-line `description:` (P1, cto); the `expected_luks_volume_id` naming collision (P2, cto); the stale `format = "ext4"` fragment, the `confirm` comment block, and the ADR `lint-infra-ignore` body (P2, kieran).

**Simplification cuts applied:** `resource_deletes`; both new boolean inputs; D7 entirely; Phase 0 from ten sub-steps to seven premise-falsifying reads; the redundant best-effort/gating heartbeat duplication.

**Splits recorded, not silently resolved:** DC-1 (D10/D11 keep-vs-cut — simplification panel vs product/structure panel) and DC-4 (the doc-debt fold-in) in `decision-challenges.md`.

### Product (CPO)

**Status:** reviewed — **SIGN-OFF: yes-with-conditions.** All five conditions applied: **C1** ship one gate shape, and if a first-create arm were needed the *job* must determine it, never an operator boolean → D6/D7. **C2** bounded, one-command, independently-sourced volume id → D9 + §Operator flow. **C3** verify the disposability premise → Phase 0.3 + AC22. **C4** bound the empty-store window and name who controls the clock → D12 + the force command. **C5** four `## User-Brand Impact` amendments (the gate-too-strict direction; the aggregate-shaped tail; the public-repo acknowledgment; the recut-scheduling question) → applied, with the scheduling question raised as **DC-5**. CPO's R2 (ledger `at_rest.mechanism` vs. downstream renderers such as `/soleur:code-to-prd`) is out of scope here and pre-exists this PR, but this plan extends its window — recorded for a separate tracking issue.

### Product/UX Gate

**Tier: NONE.** The mechanical UI-surface scan over Files to Edit/Create matches no UI path.

### GDPR / Compliance

Skipped — no regulated-data surface; the store holds OCI blobs and cosign signatures. None of the four expansion triggers fire. The `single-user incident` threshold is declared for **destroy blast radius**, not personal-data exposure.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6.
- **Do not "simplify" this gate toward `registry-host-replace-gate.sh`.** That one requires the volume **preserved**; this one requires it **replaced**. They read almost identically and mean opposite things. The cross-gate divergence test is what fails the build if someone harmonises them — keep it.
- **`registry_region_migrate_gate` would PASS the canonical recut plan** (a replace's actions include `"create"`). This gate is that gate *plus* strictness clauses. Do not route a recut through the weaker one.
- **`-replace` does not scope a plan.** Dropping a `-target` widens it to the whole root; the gate ABORTs, but the failure reads as a mysterious `out_of_scope` rather than the real mistake.
- **The resume arm's admission is the live Hetzner probe, not the plan's shape.** If a future edit lets plan shape alone admit it, a partial-state-loss plan becomes indistinguishable from a recovery.
- **`before.id` is a JSON string** — compare via `tostring`, never a bare numeric `==`. And the lib must fail closed on an empty `$expected`: the sibling's idiom is *skip-on-empty*, which inverts the pin.
- **A heartbeat exposes no `last_ping_at`**, so a terminal `up` is never evidence of a new beat. Any future edit to the poller must preserve the transition requirement and the `paused` arm.
- **`registry-host-replace` remains correct** for a boot flake on an already-`crypto_LUKS` volume. The do-not-use warning is scoped to the *plaintext* case; a blanket warning removes the one live remedy for a D11 failure.
- **After a recut the store is EMPTY and `ghcr-fallback` pages.** Any doc that says "re-fills from GHCR" without naming the next-CI-dual-push mechanism, the paging consequence, and the force command is restating the defect this plan corrected.
- **`.claude/hooks/iac-plan-write-guard.sh` has a latent SIGPIPE defect** (found while writing this plan): `set -o pipefail` + `echo "$content" | grep -q …` returns 141 when `grep` exits early, so on a large plan both its detection patterns **and** its own `iac-routing-ack` escape hatch mis-fire depending on where the match sits. Reproduced deterministically. Fix is `grep -q … <<<"$content"`. Out of scope here; worth its own issue.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
