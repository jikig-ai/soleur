---
title: "feat(infra): gated workspaces-luks-recut — make the orphaned LUKS volume a fresh target"
date: 2026-07-23
type: feat
lane: single-domain
closes: 6855
refs: [6812, 6808, 6604]
adr: ADR-119
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat(infra): gated `workspaces-luks-recut` — make the orphaned LUKS volume a genuinely FRESH target

## Overview

Build a gated, environment-reviewed `apply_target=workspaces-luks-recut` in
`.github/workflows/apply-web-platform-infra.yml` that does a scoped
`terraform -replace=hcloud_volume.workspaces_luks` (+ its attachment). It destroys the orphaned
first-cutover LUKS volume (Hetzner id `106406962`, holding the operator-accepted-discarded
2026-07-20 27-minute window) and creates a genuinely **raw** replacement carrying the **same stable
volume name** `soleur-web-platform-data-luks`. The existing cutover then resolves the new device by
name, hits its raw→`luksFormat` arm, and copies from the authoritative live plaintext `/mnt/data`.

This is the **prerequisite** the operator authorized on 2026-07-21 (#6812 comment: *"accept the
27-minute loss and re-cut; the re-cut luksFormats that device"*). It is **NOT** the re-cut itself and
**MUST NOT close #6812** — the successful cutover + verify closes that. This PR closes **#6855**.

**Why it is needed (the premise that does not hold today).** The orphaned volume `106406962` is still
the only `workspaces_luks` volume in terraform state and is already `crypto_LUKS`. Because
`workspaces-cutover.sh`'s three-arm `blkid` guard treats a `crypto_LUKS` device as an idempotent
**no-op** (`workspaces-cutover.sh:2032-2033`), a re-cut against current state re-opens the OLD header
and surfaces the stale ext4 — it never `luksFormat`s, contradicting the authorized premise. The
first-provision path `apply_target=workspaces-luks-cutover` is gate-guarded to reject a re-run (all
five resources already in state), and the cutover workflow has no fresh-target input. There is no
existing mechanism to make the volume raw again.

## Research Reconciliation — Spec vs. Codebase

| Premise (from the issue / brief) | Codebase reality (verified read-only) | Plan response |
| --- | --- | --- |
| Orphaned LUKS volume still in TF state | `hcloud_volume.workspaces_luks` id=`106406962` refreshing in drift run `29895421377` (2026-07-22 06:00 UTC); live plaintext `hcloud_volume.workspaces["web-1"]` id=`105149570` also in state | Confirmed. `-replace` targets `106406962`. |
| Cutover resolves device by **volume name** (so a same-name replace works) | `workspaces-luks-cutover.yml:426` queries `https://api.hetzner.cloud/v1/volumes?name=soleur-web-platform-data-luks` → `VID` → `/dev/disk/by-id/scsi-0HC_Volume_${VID}` → `WORKSPACES_LUKS_DEV`; script consumes it at `workspaces-cutover.sh:2019` | **Confirmed** — a new id under the same name resolves fresh. Design (a) is sound. |
| Replacement volume is born **raw** | `workspaces-luks.tf` **deliberately omits `format`** (comment: "the single most important line … is NOT here"); the discriminator `blkid TYPE == ""` → luksFormat | Confirmed. No `format` attr → raw → `luksFormat` arm. |
| Passphrase must be **reused**, not re-minted | `random_password.workspaces_luks` stays in state; `-replace` targets only the volume+attachment | Gate forbids ANY action on passphrase/secret/token (a re-mint = F4 header-loss catastrophe). |
| A scoped-`replace` apply_target pattern exists to mirror | `git_data_host_replace` / `registry_host_replace` jobs (`apply-web-platform-infra.yml`) + `git-data-host-replace-gate.sh` | Mirror job structure + destroy-guard rigor; **invert** the preserve/replace assertions (replace the volume, preserve web-1 + live volume). |
| Parity test must register the new dispatch job | `plugins/soleur/test/terraform-target-parity.test.ts:453-469` strips dispatch-only scoped jobs whose `-target`s are all `OPERATOR_APPLIED_EXCLUSIONS`; both recut targets already excluded (`:618-619`) | Add a strip clause for `workspaces_luks_recut` mirroring the git-data/registry strips. |

**Premise validation:** all six premises checked and held. No stale premises. The one that would have
broken the design (device resolved by stale id rather than name) was verified against the workflow
source and holds.

## User-Brand Impact

**If this lands broken, the user experiences:** a re-cut that silently reuses the orphaned volume's
stale 27-min-old data (serving old workspace state) OR a cutover that aborts at C1 and leaves
encryption-at-rest still off — every user's checked-out source remains plaintext at rest against
three published legal claims that it is encrypted.

**If this leaks, the user's source code is exposed via:** the mechanism itself does not add an exposure
vector, but a **defective destroy-guard** could permit a plan that touches the LIVE plaintext volume
(`105149570`) or web-1 — detaching/destroying sole-copy `/mnt/data` mid-operation strands or destroys
every user's only copy (`refs/checkpoints/*` is pushed by no refspec; signup workspaces have no remote).

**Brand-survival threshold:** single-user incident. (One user's stranded/lost workspace is
unrecoverable — sole-copy data.) `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review.

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)
1. `git show origin/main:apps/web-platform/infra/workspaces-luks.tf` — confirm the volume still has no
   `format` attr and the attachment references `hcloud_volume.workspaces_luks.id`.
2. Re-read `apply-web-platform-infra.yml` `git_data_host_replace` (`:1654`) + `workspaces_luks_cutover`
   (`:1877`) jobs and `tests/scripts/lib/workspaces-luks-cutover-gate.sh` — the exact bytes to mirror.
3. Confirm `plugins/soleur/test/terraform-target-parity.test.ts:453-469` strip pattern.

### Phase 1 — The destroy-guard gate lib (TDD: test first)
- **Create** `tests/scripts/lib/workspaces-luks-recut-gate.sh` — function `workspaces_luks_recut_gate <plan-json>`,
  mirroring `workspaces-luks-cutover-gate.sh`'s structure (jq over `terraform show -json`, exact-equality
  `IN(.address; allow[])`, parse-validate every counter, fail-loud). Semantics **inverted for a replace**:
  - `allow` = `{ hcloud_volume.workspaces_luks, hcloud_volume_attachment.workspaces_luks }` (the ONLY
    addresses permitted a positive action).
  - `named_live` = the three web-1 addresses **plus** `random_password.workspaces_luks` +
    `doppler_secret.workspaces_luks_key` (each owned by its own 0-action clause).
  - **Required ≥1:** `luks_volume_replaced` = address==`hcloud_volume.workspaces_luks` AND actions
    contains **both** `"delete"` and `"create"` (a genuine replace — a bare create or bare delete/forget
    ABORTS); `luks_attachment_created` = attachment actions contains `"create"` (re-attach the new vol).
  - **Must ==0:** `old_volume_touched` (`hcloud_volume.workspaces["web-1"]`, 4-verb positive),
    `old_attachment_touched` (`hcloud_volume_attachment.workspaces["web-1"]`), `web1_server_touched`
    (`hcloud_server.web["web-1"]`), `luks_passphrase_touched` (**4-verb create/update/delete/forget** on
    `random_password.workspaces_luks` OR `doppler_secret.workspaces_luks_key` — unlike the cutover gate,
    here even a `create` is wrong: the passphrase MUST be preserved/reused), `out_of_scope` (positive
    action on any address not in `allow` and not in `named_live` — this catches a touch on
    `doppler_service_token.workspaces_luks`, which is deliberately NOT in `named_live`).
  - `resource_deletes` = delete/forget on any address **NOT in `{volume, attachment}`** (they are
    legitimately deleted as part of the replace) — must ==0.
  - PASS iff `luks_volume_replaced>=1 && luks_attachment_created>=1 && old_volume_touched==0 &&
    old_attachment_touched==0 && web1_server_touched==0 && luks_passphrase_touched==0 &&
    resource_deletes==0 && out_of_scope==0`.
- **Create** `tests/scripts/test-workspaces-luks-recut-gate.sh` — sources the lib; synthesizes plan-JSON
  fixtures (NO real infra); asserts:
  - **GREEN:** a plan where the volume shows `["delete","create"]` and the attachment shows
    `["delete","create"]` (or `["create"]`) and nothing else touched.
  - **RED mutations (each ⇒ ABORT):** (a) volume shows only `["create"]` (not a replace) → abort;
    (b) volume shows only `["delete"]`/`["forget"]` → abort; (c) live volume `hcloud_volume.workspaces["web-1"]`
    shows any positive action → abort; (d) live attachment touched → abort; (e) `hcloud_server.web["web-1"]`
    touched → abort; (f) `random_password.workspaces_luks` shows create OR update OR delete → abort;
    (g) `doppler_secret.workspaces_luks_key` touched → abort; (h) `doppler_service_token.workspaces_luks`
    touched → abort (out_of_scope); (i) any un-enumerated address with a positive action → abort;
    (j) malformed/empty plan JSON → fail-closed (return 1).

### Phase 2 — The gated `apply_target=workspaces-luks-recut` job
- **Edit** `.github/workflows/apply-web-platform-infra.yml`:
  - Add `workspaces-luks-recut` to the `apply_target` **choice** `options:` list (`:96-108`) with a
    description matching the git-data/registry entries' style, noting it is the destructive recut.
  - Add a `confirm` input (`type: string`, `required: false`, description: "Type
    `RECUT-WORKSPACES-LUKS` to authorize the destructive volume replace (typo-guard, NOT the
    authorization)."). Other targets ignore it.
  - **New job `workspaces_luks_recut`** (`if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'workspaces-luks-recut'`), mirroring `workspaces_luks_cutover` (checkout → setup-terraform →
    Doppler → ephemeral SSH key → verify secrets → extract R2 creds → init) plus:
    - **`environment: workspaces-luks-cutover`** on the job (reuse the existing
      `github_repository_environment.workspaces_luks_cutover`, reviewers.users=[54279], already
      non-empty + provisioned). **This is the sole human authorization on the destructive replace**
      (the recut is irreversible on sole-copy data — unlike the additive first-provision, which is
      un-gated). The whole job is held in "Waiting" for @deruelle before any step runs.
    - **`concurrency: { group: web-1-swap, cancel-in-progress: false }`** (same DP-3 mutex as the
      cutover job — it mutates web-1's attached volumes).
    - **Preflight step** (before plan) validating `confirm == 'RECUT-WORKSPACES-LUKS'` (typo-guard;
      abort with `::error::` otherwise), mirroring the freeze workflow's confirm check.
    - **Plan step:** `terraform plan -out=tfplan -replace='hcloud_volume.workspaces_luks'
      -target='hcloud_volume.workspaces_luks' -target='hcloud_volume_attachment.workspaces_luks'
      -var="ssh_key_path=${CI_SSH_PUB}"` (via `doppler run … --name-transformer tf-var`), then
      `terraform show -json` → source `workspaces-luks-recut-gate.sh` → abort on gate fail, echoing the
      `will be destroyed|must be replaced|Plan:` lines (same shape as the cutover plan step).
    - **Apply step:** `terraform apply tfplan` with post-apply jq backstops from the SAVED plan
      (belt-and-suspenders to the gate): live volume/attachment + web-1 carry **0** actions; the LUKS
      volume shows a delete AND a create (replace); the attachment shows a create.
    - **Dispatch summary** step (mirror the others).
- **NO reboot, NO SSH** anywhere in the job (`hr-no-ssh-fallback-in-runbooks`). Attach/detach is a hot
  Hetzner-API operation; `/mnt/data` keeps serving from the untouched live plaintext `/dev/sdb`
  throughout — zero downtime.

### Phase 3 — Parity-test registration
- **Edit** `plugins/soleur/test/terraform-target-parity.test.ts` — add a strip clause for
  `workspaces_luks_recut` in the same block as `git_data_host_replace` / `registry_host_replace`
  (`:453-469`): a dispatch-only scoped job whose two `-target`s (`hcloud_volume.workspaces_luks`,
  `hcloud_volume_attachment.workspaces_luks`) are already `OPERATOR_APPLIED_EXCLUSIONS` (`:618-619`), so
  it must be stripped from `allTargets` exactly like its siblings. Run the suite; assert green.

### Phase 4 — ADR-119 + runbook doc updates
- **Edit** `knowledge-base/engineering/architecture/decisions/ADR-119-…md` — add an **Addendum
  (2026-07-23): the re-cut-after-orphaned-volume path (#6812/#6855)** documenting: (i) why a re-cut
  against the current state does NOT `luksFormat` (the `crypto_LUKS`→no-op arm); (ii) the
  `workspaces-luks-recut` mechanism (scoped `-replace`, environment-gated, guard-asserted); (iii) that
  it discards the operator-accepted 27-min window; (iv) that it reuses the existing passphrase (no
  re-mint). **Keep `status: adopting`** (soak/flip remain downstream, blocked on #6808).
- **Edit** `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` — add a
  **Sequence Step 0 (recover from a dead-man-orphaned volume)** BEFORE Step 1: dispatch
  `apply-web-platform-infra.yml -f apply_target=workspaces-luks-recut -f confirm=RECUT-WORKSPACES-LUKS
  -f reason='#6812 re-cut fresh target'`, approve the environment gate, then proceed to the dry-run +
  freeze. Correct the dead-man note / any "re-cut luksFormats that device" wording to state the
  already-`crypto_LUKS` caveat and point at the recut step.
- **ADR/C4:** read all three `.c4` model files
  (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) and confirm the recut
  introduces **no new** external actor, external system, container/data-store, or access relationship —
  it is a lifecycle operation on the already-modeled `/workspaces` LUKS volume, the already-modeled web-1
  host, the already-modeled operator, and the already-used Hetzner API. Cite the enumeration in the ADR
  addendum ("no C4 impact: checked actors {operator}, systems {Hetzner API}, stores {LUKS volume},
  relationships {operator→recut dispatch} — all already modeled").

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** `tests/scripts/lib/workspaces-luks-recut-gate.sh` exists; `bash tests/scripts/test-workspaces-luks-recut-gate.sh` is GREEN, covering the GREEN case + all RED mutations (a)-(j) in Phase 1.
- **AC2** The recut gate ABORTS a plan where `hcloud_volume.workspaces_luks` shows only `["create"]`
  (proves it requires a genuine replace, not a bare create) AND a plan where the live volume
  `hcloud_volume.workspaces["web-1"]` shows any positive action (proves the sole-copy backstop).
- **AC3** The recut gate ABORTS a plan where `random_password.workspaces_luks` shows a `create` (proves
  the passphrase-reuse invariant: unlike the cutover gate, create is forbidden here).
- **AC4** `apply-web-platform-infra.yml` has `workspaces-luks-recut` in the `apply_target` choice list;
  the new job declares `environment: workspaces-luks-cutover` and `concurrency: web-1-swap`; the plan
  step sources `workspaces-luks-recut-gate.sh`. (`grep`/`actionlint` on the workflow; embedded `run:`
  shell checked via `bash -c` on extracted snippets — never `bash -n` on the YAML.)
- **AC5** `gh api repos/jikig-ai/soleur/environments/workspaces-luks-cutover` returns 200 with a
  non-empty `protection_rules[].reviewers` (the reused gate is armed — DP-11 F8). *(Read-only; already
  provisioned — verifies the reuse assumption holds.)*
- **AC6** `plugins/soleur/test/terraform-target-parity.test.ts` is GREEN with the `workspaces_luks_recut`
  strip clause added (`./node_modules/.bin/vitest run` or the package's configured runner — verify via
  `package.json`/`vitest.config.ts` include globs, not a hardcoded runner).
- **AC7** ADR-119 carries the 2026-07-23 addendum and still reads `status: adopting`; the runbook has the
  recut Step 0 with the exact `gh workflow run` invocation and the corrected `luksFormat` wording.
- **AC8** `test-all.sh` (or the repo's canonical full-suite gate) is GREEN — including any orphan
  scope-guard suite that enumerates `-target` allow-lists.

### Post-merge (operator — separate, gated; NOT part of this PR)
- **AC9 (operator)** Dispatch `apply-web-platform-infra.yml -f apply_target=workspaces-luks-recut -f
  confirm=RECUT-WORKSPACES-LUKS -f reason='#6812 re-cut'`, approve the environment gate → the orphaned
  volume is replaced by a raw one. `Automation: not feasible because` the environment approval is the
  operator's sole human authorization on irreversible sole-copy-data destruction (`playwright-attempt:`
  N/A — this is a GitHub environment reviewer gate, not a vendor dashboard). **This PR does NOT dispatch it.**
- **AC10 (operator)** Then the existing runbook Sequence (dry-run → freeze → verify) runs against the
  fresh raw target, closing #6812.

## Infrastructure (IaC)

### Terraform changes
No `.tf` changes. The mechanism is a new **dispatch job + `-replace` scope** in an existing workflow
over already-declared resources (`workspaces-luks.tf`). The reused environment resource
(`github_repository_environment.workspaces_luks_cutover`) already exists. **No new `TF_VAR_*`, no new
Doppler secret, no new provider.**

### Apply path
(c) `terraform apply -replace` — scoped, guarded, environment-gated, dispatch-only. Blast radius: the
single orphaned volume `106406962` (accepted-discard) + its attachment. Downtime: **zero** (`/mnt/data`
serves from the untouched live plaintext volume throughout; attach/detach is hot).

### Distinctness / drift safeguards
`dev != prd`: N/A (prod-only infra). The destroy-guard + post-apply jq assert the live plaintext volume
(`105149570`) + web-1 carry 0 actions. No `lifecycle.ignore_changes` change. State: R2-backed encrypted
backend (unchanged). The `-target` set is exactly the two recut resources — no untargeted drift pulled in.

### Vendor-tier reality check
N/A — no new vendor resource; Hetzner volume replace is a standard API operation.

## Observability

```yaml
liveness_signal:
  what: the recut job's `terraform apply` exit + post-apply jq asserts (replace present, live vol/web-1 untouched)
  cadence: per-dispatch (operator-triggered, not scheduled)
  alert_target: GitHub Actions run conclusion + Dispatch summary step (GITHUB_STEP_SUMMARY)
  configured_in: .github/workflows/apply-web-platform-infra.yml (workspaces_luks_recut job)
error_reporting:
  destination: GitHub Actions `::error::` annotations on gate-abort + apply-fail; run conclusion=failure
  fail_loud: true (destroy-guard aborts before apply; parse-failure returns 1 fail-closed)
failure_modes:
  - mode: plan is not the exact scoped replace (drags an unexpected resource, touches live vol/web-1)
    detection: workspaces_luks_recut_gate ABORT before apply (structured plan JSON)
    alert_route: `::error::` + run failure; no apply performed
  - mode: apply fails mid-replace (old volume destroyed, new create fails — quota/API)
    detection: post-apply step non-zero; the LIVE plaintext /mnt/data is untouched (different volume) so serving is unaffected
    alert_route: `::error::` self-documenting recovery annotation ("re-dispatch to recreate the raw volume; /mnt/data unaffected") + run failure
  - mode: passphrase accidentally re-minted (F4 header-loss class)
    detection: gate `luks_passphrase_touched != 0` → ABORT (4-verb, create included)
    alert_route: `::error::` + run failure; no apply
logs:
  where: GitHub Actions run logs + GITHUB_STEP_SUMMARY; the subsequent cutover's Better Stack SOLEUR_WORKSPACES_* markers verify at-rest state post-freeze
  retention: GitHub Actions default (90d)
discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/health
  expected_output: "200" — the recut is zero-downtime; /health must stay 200 (serving is unaffected by the volume replace). The dispatch run's own conclusion + GITHUB_STEP_SUMMARY are the mechanism-level signal, visible in the Actions UI without SSH.
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-119** with the 2026-07-23 addendum (Phase 4). New decision recorded: the orphaned-volume
recut mechanism + its passphrase-reuse and environment-gate invariants. Not a new ADR (this extends
ADR-119's cutover lifecycle). `status: adopting` preserved.

### C4 views
No C4 impact — verified by reading all three `.c4` files (Phase 4): the recut adds no external actor,
external system, container/data-store, or access relationship. Enumeration cited in the ADR addendum.

### Sequencing
The ADR addendum describes the mechanism as built-and-merged; the recut *execution* is the operator's
downstream gated dispatch (AC9), and the ADR `adopting→accepted` flip stays downstream (soak, blocked
on #6808) — unchanged by this PR.

## Domain Review

**Domains relevant:** Engineering (infra).

### Engineering (CTO / infra)
**Status:** reviewed (inline single-pass; specialist spawns deferred to the review phase due to
transient background-agent instability this session — `user-impact-reviewer`, `data-integrity-guardian`,
`security-sentinel`, and `architecture-strategist` run at `/review`, which is where the
single-user-incident threshold routes them).
**Assessment:** Sound. Mirrors three shipped scoped-`replace` precedents; the one novel element (an
`environment:` gate on a scoped-replace apply_target, absent from the host-replace siblings) is
justified because this replace **destroys sole-copy data** where the host-replaces preserve their
volumes. The destroy-guard's inverted assertions (require volume-replace, forbid touching live
vol/web-1/passphrase) are the load-bearing safety surface and are TDD'd with mutation tests.

### Product/UX Gate
**Tier:** NONE — no UI surface (files are `.yml`/`.sh`/`.ts`-test/`.md`; no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`). Mechanical UI-surface override did not fire.

## Open Code-Review Overlap
None — no open `code-review`-labelled issue names the files this plan edits
(`apply-web-platform-infra.yml`, `tests/scripts/lib/workspaces-luks-recut-gate.sh`, the parity test,
ADR-119, the runbook). (Re-verify at `/work` via the `code-review` label query.)

## Risks & Sharp Edges

- **`-replace` on an address NOT in state plans a plain CREATE and exits 0** (the git-data stock-preflight
  header documents this). Here `hcloud_volume.workspaces_luks` IS in state (id `106406962`, verified in the
  drift refresh), so `-replace` produces a genuine replace. The gate's `luks_volume_replaced` clause
  (requires BOTH delete AND create) fail-closes if the volume is somehow not in state (a bare create ⇒
  abort) — so a future state-drift can't silently degrade the replace into a create.
- **A plan whose `## User-Brand Impact` section is empty/placeholder fails `deepen-plan` Phase 4.6.** It is
  filled above.
- **Environment reuse:** the recut reuses `workspaces-luks-cutover`. If that environment's reviewer set is
  ever emptied, both the freeze AND the recut auto-approve (DP-11 F8). AC5 asserts it is non-empty;
  keep it so.
- **Do NOT add a dry-run arm that skips the environment gate.** The recut is always destructive; the
  destroy-guard (post-approval, pre-apply) is the shape-safety, and the environment approval is the
  authorization. A pre-approval "plan preview" is unnecessary — the guard aborts any wrong-shape plan
  after approval, before apply.
- **This PR ships the mechanism only.** It does NOT dispatch the recut, the freeze, or the verify, and
  does NOT close #6812. Those are the operator's downstream gated steps.

## Test Scenarios
1. `bash tests/scripts/test-workspaces-luks-recut-gate.sh` — GREEN case + RED mutations (a)-(j). (No real infra; synthesized plan-JSON fixtures.)
2. `actionlint .github/workflows/apply-web-platform-infra.yml` (workflow) + `bash -c` on the recut job's extracted `run:` snippets.
3. Parity test (`vitest run plugins/soleur/test/terraform-target-parity.test.ts`).
4. `test-all.sh` full-suite gate.
