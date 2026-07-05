---
title: "feat: autonomous no-SSH web-2 host-bootstrap (terraform -replace) — bind :9000, unblock ADR-068 warm-standby"
date: 2026-07-05
type: feat
branch: feat-one-shot-web-2-recreate-bootstrap
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-068 (amend)
issues_context: [5887, 5933, 5921, 5911, 5950, 4419, 4420]
---

# feat: Autonomous no-SSH web-2 host-bootstrap (`apply_target=web-2-recreate`)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO manual-infra step. Every `systemctl`/webhook
     reference in prose is either (a) the EXISTING cloud-init root cause being diagnosed, or
     (b) an explicitly-REJECTED SSH alternative. The fix routes 100% through terraform
     `-replace` + first-boot cloud-init; see ## Infrastructure (IaC). -->

🔧 **Infra / CI workflow change — destructive prod server RECREATE, guarded.**

## Overview

The first live ADR-068 warm-standby dispatch (2026-07-05) attached web-2's private-net
interface (`10.0.1.11`) + 20 GB `/workspaces` volume cleanly, and the fail-closed verify
correctly RED'd (`reason=ok_peer_fanout_degraded`; web-2 stays drained / zero-weight / no
user impact) — but web-2's `:9000` webhook listener is **unbound**. web-2's first-boot
cloud-init aborted **before** the `enable --now webhook` step
(`apps/web-platform/infra/cloud-init.yml:439`); the webhook binds `0.0.0.0:9000`
(`webhook.service:11`), so an unbound `:9000` proves cloud-init stopped early.

**Root cause (verified, file:line).** web-2 is created by the same
`hcloud_server.web` `for_each` with byte-identical cloud-init as web-1
(`server.tf:95,114`). The baked-host-script hash-verify block
(`cloud-init.yml:353-400`, `set -e` + `exit 1` at `:391`) recomputes the combined content
hash of the image's baked `/opt/soleur/host-scripts` and aborts the **entire** runcmd when
it ≠ the Terraform-computed `host_scripts_content_hash` (`server.tf:71-73`, injected into
`user_data` at `:124`). A mismatch fires the `on_err` trap (Sentry `stage=verify`) then
`exit 1` — cloud-init never reaches the webhook enable step, so `:9000` never binds. The
most consistent trigger is the mutable `:latest` default of `var.image_name`
(`variables.tf:44-48`): a web-2 boot that pulls a `:latest` whose baked host-scripts drifted
from the applied hash aborts at `stage=verify` — the ADR-080 stale-image trap the hash-verify
was designed to surface loudly.

**The fix (only in-band, no-SSH, reachable-from-terraform-apply path).**
`hcloud_server.web` carries `lifecycle.ignore_changes = [user_data, ssh_keys, image,
placement_group_id]` (`server.tf:163-165`), so **no plain apply** can re-push cloud-init to
the existing web-2 — only instance **RECREATION** re-runs first-boot cloud-init. `-replace`
destroys+creates the server; on the CREATE leg `ignore_changes` does **not** apply, so the
fresh `user_data` (carrying a **pinned** `image_name`) boots the host. So: pin
`var.image_name` to an immutable `@sha256:` digest **whose baked host-scripts hash provably
matches** the applied `host_scripts_content_hash`, then
`terraform apply -replace='hcloud_server.web["web-2"]'`.

**Production-safe by construction.** web-2 is weight-0, empty `/workspaces`, in no serving
pool (ingress stays on web-1 throughout). The 20 GB `hcloud_volume.workspaces["web-2"]` is a
**separate** resource (`server.tf:1030`) — recreating the SERVER does not recreate the
VOLUME. Only the server + its two id-referencing dependents
(`hcloud_server_network.web["web-2"]` at `network.tf:39`, `hcloud_volume_attachment.workspaces["web-2"]`
at `server.tf:1042`) replace; they re-attach to the new server id cleanly.

This is an **operator-acknowledged, post-merge menu dispatch** (`hr-menu-option-ack-not-prod-write-auth`):
`gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='…'`.
`workflow_dispatch` resolves against the **default branch** only
(learning `2026-04-21-workflow-dispatch-requires-default-branch`), so the path cannot run
pre-merge. **NEVER run against web-1. DO NOT run any prod apply during the build.**

## Research Reconciliation — Spec vs. Codebase

| Claim (task) | Reality (verified) | Plan response |
|---|---|---|
| A NEW warm-standby dispatch job must be built | `warm_standby` job **already exists** (`apply-web-platform-infra.yml:628-1046`), attaches + fans out + verifies off-host | MIRROR its shape for the new `web_2_recreate` job; reuse its baseline/fan-out/verify steps verbatim where possible |
| Extend destroy-guard to "permit the scoped web-2 replace" | Current jq emits `{resource_deletes, nested_deletes, reboot_updates}`; a `-replace` shows `actions:["delete","create"]` → trips `resource_deletes` (`destroy-guard-filter-web-platform.jq:79`) | ADD backward-compatible keys (`web2_disallowed_deletes`, `web2_server_replaced`); the new job reads them, existing jobs unchanged |
| `hcloud_server_network.web["web-2"]` is a dependent that replaces | Confirmed — `network.tf:39-44` `for_each`, references `hcloud_server.web[each.key]`; volume attachment `server.tf:1042-1046` likewise | `-target` all 3 web-2 addresses so the replacement is ordered; assert volume itself is untouched |
| Resolve web-1's running digest from deploy-status `.image`/`.tag` | `cat-deploy-state.sh` surfaces `.tag` (validated `^v[0-9]…`); **`.image` is NOT surfaced**; the immutable digest is NOT in the payload | Read `.tag`, resolve tag→`@sha256` via GHCR (`docker buildx imagetools inspect`); add a **coherence preflight** (below) |
| Pin the digest web-1 is running (known-good) | web-1 booted on it *when its local host-scripts matched*; if `main` drifted since, that digest **re-aborts** at `stage=verify` | Coherence preflight: docker-cp the digest's `/opt/soleur/host-scripts`, recompute the boot-identical hash, assert `== terraform local.host_scripts_content_hash`; abort loud on mismatch |

## User-Brand Impact

**If this lands broken, the user experiences:** *nothing directly* — web-2 is weight-0,
drained, in no serving pool; the fail-closed off-host verify keeps a still-broken web-2 OUT
of ingress (the warm-standby fan-out RED's on `ok_peer_fanout_degraded`, exactly as it did
on 2026-07-05). The **load-bearing** risk is a **guard defect** that lets the plan touch
`hcloud_server.web["web-1"]` — the sole live origin. A web-1 delete/replace = full data-loss
outage; a web-1 in-place reboot = ~1-2 min outage for **every** user.

**If this leaks, the user's data is exposed via:** n/a — no user-data surface; this is an
infra CI workflow + terraform guard. (Sensitive values: `image_name` digest is public GHCR;
Doppler `prd_terraform` secrets flow through the existing masked pattern.)

**Brand-survival threshold:** `single-user incident` — the destroy-guard is the only
mechanical protection against a web-1 mistake on an unattended prod apply. A wrong guard is a
full-outage class defect, so the guard's precision (permit ONLY the 3 web-2 replaces; ABORT
on ANY web-1 delete/reboot/replace and ANY web-2-volume destroy) is the plan's central
correctness property.

> CPO sign-off required at plan time (`requires_cpo_signoff: true`). Headless pipeline —
> flagged here; `user-impact-reviewer` runs at review time (review/SKILL.md conditional-agent
> block) enumerating web-1-blast-radius failure modes against the diff.

## Acceptance Criteria

### Pre-merge (PR — all CI-verifiable, no prod write)

- [ ] **AC1** `apply_target` choice in `apply-web-platform-infra.yml` gains a third option
  `web-2-recreate` (alongside `manual-rerun`, `warm-standby`); the three select
  MUTUALLY-EXCLUSIVE jobs (each job's `if:` gate is disjoint). Verify:
  `grep -c 'web-2-recreate' .github/workflows/apply-web-platform-infra.yml` ≥ 3 (option +
  job `if:` + step refs).
- [ ] **AC2** New job `web_2_recreate` runs under the SAME top-level
  `concurrency: group: terraform-apply-web-platform-host` (inherited — it is a job of THIS
  workflow, NOT a second workflow). Verify no second `concurrency:` block is added.
- [ ] **AC3** The plan step uses EXACTLY:
  `-replace='hcloud_server.web["web-2"]'` + `-target='hcloud_server.web["web-2"]'` +
  `-target='hcloud_server_network.web["web-2"]'` +
  `-target='hcloud_volume_attachment.workspaces["web-2"]'` +
  `-var="image_name=<resolved @sha256 digest>"`. It does **NOT** `-target`
  `hcloud_volume.workspaces["web-2"]`.
- [ ] **AC3b (TOCTOU — CTO must-fix 1)** The tag→digest resolution runs EXACTLY ONCE; the
  result is frozen as a job-level env/output `$PINNED` and consumed byte-identically by (i) the
  coherence preflight, (ii) `-var="image_name=$PINNED"`, and (iii) any re-check. The workflow
  MUST NOT re-run `docker buildx imagetools inspect` between preflight and apply (a moved tag
  would resolve to a different digest, voiding the preflight's guarantee).
- [ ] **AC4** `destroy-guard-filter-web-platform.jq` emits new keys `web2_out_of_scope_changes`
  (POSITIVE scope: any create/update/delete whose address ∉ the exact web-2 allow-set) and
  `web2_server_replaced` (1 iff `hcloud_server.web["web-2"]` actions ⊇ {delete, create}); existing
  keys `resource_deletes`/`nested_deletes`/`reboot_updates` are byte-unchanged (backward-compat).
  Exact-equality membership (`IN(.address; web2_allow[])`), NOT `inside`/substring.
- [ ] **AC5** The `web_2_recreate` guard is an **extracted, sourced shell function** (spec-flow
  P1-1 — not inline) that ABORTS (exit 1, no `[ack-destroy]` bypass) unless
  `web2_out_of_scope_changes==0 && nested_deletes==0 && reboot_updates==0 &&
  web2_server_replaced==1`, reading the plan JSON (`terraform show -json`), never stderr.
- [ ] **AC6** `tests/scripts/test-destroy-guard-counter-web-platform.sh` calls the extracted
  gate function directly and proves (synthesized fixtures only, `cq-test-fixtures-synthesized-only`):
  (a) a scoped web-2 replace PASSES; (b) a `hcloud_server.web["web-1"]` delete/replace FAILS;
  (c) a `hcloud_volume.workspaces["web-2"]` destroy FAILS; (d) a web-2 in-place reboot FAILS
  (`reboot_updates>0`); (e) a no-op plan FAILS (`web2_server_replaced==0`); **(f) a web-1
  in-place UPDATE with a non-`placement_group_id`/`server_type` attr diff FAILS**
  (`web2_out_of_scope_changes>0` — the P0-2 hole); **(g) a substring-collision address (e.g.
  bare `hcloud_server.web`) is NOT falsely allowed**; **(h) `[ack-destroy]` in the commit does
  NOT bypass the recreate gate** (AC5 no-bypass).
- [ ] **AC7** `plugins/soleur/test/terraform-target-parity.test.ts` gains a
  `WEB2_RECREATE_TARGETS` constant = exactly the 3 web-2 addresses; asserts (i) it matches the
  workflow's `web_2_recreate` `-target` set, (ii) every base address ∈
  `OPERATOR_APPLIED_EXCLUSIONS`, (iii) `hcloud_volume.workspaces["web-2"]` is **NOT** in the
  set, (iv) the `-replace` address is the server. **CTO must-fix 2 (#1 test-integration risk):**
  there are TWO `stripJob` call sites — the coverage test AND the `MOVED_OPERATOR_CONSUMED`
  anchor test (parity ~L838/851, strips only `warm_standby` today). Adding
  `hcloud_server.web["web-2"]` to `allTargets` WITHOUT also stripping `web_2_recreate` at the
  moved-anchor site could MASK a dropped moved-base — verify BOTH sites handle the new job
  consistently. Existing `MOVED_OPERATOR_CONSUMED` / `WARM_STANDBY_TARGETS` / `reboot_updates=0`
  guards stay green.
- [ ] **AC8** Sweep ALL guard suites (learning `2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites`):
  `git grep -ln 'destroy-guard-filter-web-platform\|web2_\|WEB2_RECREATE\|-target=' tests/ scripts/ plugins/soleur/test/`
  and confirm every hit (jq, counter test, parity test, and any orphan **scope-guard** suite)
  is updated; `bash scripts/test-all.sh` reports N/N suites passed (read the summary, not just
  exit code).
- [ ] **AC9** `python3 scripts/lint-infra-no-human-steps.py knowledge-base/engineering/operations/runbooks/moved-block-wedge-cutover-5887.md`
  exits 0 with the new web-2-recreate step present (dispatch/orchestrator actor phrasing;
  `bash scripts/lint-infra-no-human-steps.test.sh` still green).
- [ ] **AC10** `apps/web-platform` typecheck + the touched test suites pass:
  `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`;
  `./node_modules/.bin/vitest run test/terraform-target-parity.test.ts`;
  `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`.
- [ ] **AC10b (spec-flow P1-4/P1-2)** The digest-resolution + coherence-preflight bash is an
  **extracted standalone script** (not inline workflow YAML) with `set -euo pipefail`; it
  format-validates `DIGEST =~ ^sha256:[0-9a-f]{64}$` and `WANT`/`GOT` `=~ ^[0-9a-f]{64}$`
  BEFORE comparing, and RED-aborts on: absent/non-JSON `.tag`, empty `imagetools inspect`
  result, `terraform console` failure, or hash mismatch. A pre-merge test drives it with a
  **mismatching-digest fixture** and asserts non-zero exit (testable without prod).
- [ ] **AC10c (spec-flow P1-3)** The `web_2_recreate` off-host verify REUSES the `warm_standby`
  poll (shared extracted step), NOT a re-derived copy; a test asserts the timeout branch
  `exit 1`s (no green-on-timeout) and the `ROSTER_COUNT==1` single-peer guard is present in the
  new job's verify.
- [ ] **AC11** ADR-068 gains a 2026-07-05 Amendment documenting the web-2-recreate bootstrap
  as the **prerequisite** to the warm-standby fan-out, and the digest-pin determinism
  decision; the `## C4 impact` enumeration is reconciled (see Architecture Decision section).

### Post-merge (operator — menu-ack dispatch, `Ref #N` not `Closes`)

- [ ] **AC12** Operator dispatches
  `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='…'`
  (menu-ack; the workflow does everything — no SSH, no local command).
  *Automation: menu-ack dispatch per `hr-menu-option-ack-not-prod-write-auth` — a destructive
  prod host recreate legitimately requires the operator's go/no-go ack; the STEP is a single
  `gh workflow run`, not a manual multi-step.*
- [ ] **AC13** The dispatch binds web-2 `:9000` (fresh cloud-init completes past the webhook
  enable step), verified OFF-HOST: web-1's `/hooks/deploy-status` `reason` flips
  `ok_peer_fanout_degraded → ok` (single-peer invariant proves web-2 accepted the fan-out).
  No SSH, no private-IP curl.
- [ ] **AC14** If the fresh boot ALSO aborts, the job surfaces the fresh-host Sentry
  `emit_fail` event (`soleur-hostscript-seed failed` stage∈{pull,extract,verify} OR
  `soleur-host-bootstrap failed` stage∈{install,hooks,assert,reload,journald}) in the job
  summary and fails RED with a pointer — a repeat failure is diagnosable off-host.
- [ ] **AC15** Post-dispatch, `hcloud_volume.workspaces["web-2"]` is confirmed 0-destroy /
  preserved (its data survives — read from terraform state / `terraform state show`).
- [ ] **AC16 (spec-flow P2-3)** The recreate is idempotent / re-dispatch-safe: a TF create-success
  followed by a cloud-init abort still lands the server (verify RED, re-dispatch re-runs boot); a
  TF-level create failure (web-2 destroyed, create failed) is documented in the runbook as
  recoverable by re-dispatch. No partial state strands web-2 permanently.

## Implementation Phases

### Phase 0 — Preconditions (verify, no writes)

1. Re-confirm `warm_standby` job shape (`apply-web-platform-infra.yml:628-1046`) — baseline
   read, fan-out, off-host verify — to mirror. Confirm `apply` job `if:` and `warm_standby`
   `if:` remain disjoint after adding the third.
2. Confirm `local.host_script_files` list (`server.tf:16-53`) is the canonical baked set and
   `host_scripts_content_hash` (`server.tf:71-73`) is the injected hash. Prefer
   `terraform console <<< 'local.host_scripts_content_hash'` for the CI-side hash (single
   source of truth — do NOT re-implement the file list in bash; avoids the lockstep-drift trap).
3. Confirm the GHCR repo `ghcr.io/jikig-ai/soleur-web-platform` is **public** (model.c4:244)
   so `docker buildx imagetools inspect <tag>` needs no auth to resolve the digest.
4. Grep for an orphan **scope-guard** suite (learning `2026-05-29`): `git grep -ln
   'scope-guard\|scope_guard' tests/ scripts/` — if one exists that fails when the workflow
   targets a type the filter doesn't cover, extend it.
5. Read all three `.c4` files (model/views/spec) for the C4-impact enumeration (below).
6. Confirm `var.image_name` (`variables.tf:44-48`) has NO validation block rejecting the
   `@sha256:` form (spec-flow P2-4) — else `-var="image_name=<@sha256 digest>"` errors at plan.
7. Confirm the GH runner is `ubuntu-24.04` (amd64) and the Hetzner host is amd64, so the
   multi-arch manifest-list digest resolves to the same platform manifest on both (spec-flow P2-5).

### Phase 1 — Destroy-guard extension (write-boundary; do FIRST, contract before consumer)

`tests/scripts/lib/destroy-guard-filter-web-platform.jq` — add, keeping existing keys
byte-identical (backward-compat for the `apply` + `warm_standby` consumers):

```jq
# --- web-2-recreate scoped guard (this PR) --------------------------------
# The EXACT allow-set: the web-2 server + its two id-referencing dependents.
# A -replace of the server shows actions ⊇ {delete,create}; its dependents
# (network attach, volume attachment) replace because they reference the new
# server id. hcloud_volume.workspaces["web-2"] is DELIBERATELY absent — any
# change to it must trip web2_out_of_scope_changes.
def web2_allow: [
  "hcloud_server.web[\"web-2\"]",
  "hcloud_server_network.web[\"web-2\"]",
  "hcloud_volume_attachment.workspaces[\"web-2\"]"
];
# POSITIVE-SCOPE guard (spec-flow P0-2): count EVERY resource_change carrying a
# create/update/delete action whose address is NOT in the allow-set. This is
# STRICTLY STRONGER than a delete-only counter: it also catches a web-1 in-place
# UPDATE that reboots via an attribute OTHER than placement_group_id/server_type
# (the reboot_updates counter is KNOWN-UNCOVERED for those; see its header), and
# any stray create. Blocks web-1 delete/replace/reboot-via-any-attr, web-2 VOLUME
# change, and anything else outside the 3 allowed replaces.
# EXACT-EQUALITY membership via IN(.address; web2_allow[]) — do NOT use
# `inside`/`contains` (array `contains` does SUBSTRING matching, a false-match
# hazard: prose-contract-vs-executable Sharp Edge). Verified on jq 1.8.1.
# NOTE: `index("delete")` semantics count Terraform "delete"; a 1.7+ ["forget"]
# state-drop is a distinct action (no destroy) — the `any(...create/update/delete)`
# form below also excludes "forget", so a forget of a non-allow resource is NOT
# counted here (no removed{} blocks exist in apps/web-platform/infra/ today; if one
# is added, extend this list — mirrors the filter header's existing forget note).
web2_out_of_scope_changes: (
  [ .resource_changes[]?
    | select(.change.actions? | any(. == "create" or . == "update" or . == "delete"))
    | select(IN(.address; web2_allow[]) | not) ] | length ),
# Prove the recreate actually happens (guard against a silent no-op plan).
web2_server_replaced: (
  [ .resource_changes[]?
    | select(.address == "hcloud_server.web[\"web-2\"]")
    | select((.change.actions? | index("delete")) and (.change.actions? | index("create"))) ]
  | length )
```

> The recreate guard asserts `web2_out_of_scope_changes==0 && nested_deletes==0 &&
> reboot_updates==0 && web2_server_replaced==1`. `web2_out_of_scope_changes` SUBSUMES a
> delete-only check and closes the web-1-in-place-update / stray-create hole (spec-flow P0-2);
> `reboot_updates==0` + `nested_deletes==0` are kept as belt-and-braces. Verified (jq 1.8.1,
> this session) the exact-equality membership flags a web-1 change and ignores a web-2-volume
> no-op. The counter test (Phase 2) is the executable arbiter.

### Phase 2 — Guard suites (parity + counter + scope-guard)

1. `tests/scripts/test-destroy-guard-counter-web-platform.sh` — add T20-T24 per AC6, each with
   a synthesized `tfplan-*.json` fixture under `tests/scripts/fixtures/`:
   - T20 web-2 replace (server+network+attachment `["delete","create"]`, volume absent) →
     `web2_disallowed_deletes=0`, `web2_server_replaced=1` → recreate-guard PASS.
   - T21 same + a `hcloud_server.web["web-1"]` `["delete","create"]` → `web2_disallowed_deletes≥1` → FAIL.
   - T22 same + `hcloud_volume.workspaces["web-2"]` `["delete","create"]` → `web2_disallowed_deletes≥1` → FAIL.
   - T23 web-2 server in-place reboot (`actions==["update"]`, placement/server_type diff) →
     `reboot_updates=1` → FAIL.
   - T24 no-op / drift-only plan → `web2_server_replaced=0` → FAIL.
2. `plugins/soleur/test/terraform-target-parity.test.ts` — add `WEB2_RECREATE_TARGETS` + the
   AC7 assertions; extend `stripJob` for the new job where the moved-block anchor needs it.

### Phase 3 — `web_2_recreate` workflow job

Add `apply_target: web-2-recreate` choice option, and the new job (mirror `warm_standby`
scaffolding: checkout, setup-terraform, doppler, ephemeral ssh key, verify secrets, extract
R2 backend creds, `terraform init`). `timeout-minutes: 30` (fresh Ubuntu boot: apt + docker +
multi-image-pull is 10+ min; + fan-out + verify poll under this ceiling). Steps:

1. **Resolve known-good digest (off-host).** Read web-1's running `.tag` from
   `/hooks/deploy-status` (HMAC + CF Access, same auth as `warm_standby` baseline
   `:807-871`). **Gate the read on web-1 `reason==ok && exit_code!=-1`** (spec-flow P2-1 — do
   not pin a transient mid-deploy tag). Validate `^v[0-9][A-Za-z0-9._-]*$`. Resolve tag →
   immutable digest ONCE and freeze `$PINNED` (AC3b, no re-resolve):
   `DIGEST=$(docker buildx imagetools inspect ghcr.io/jikig-ai/soleur-web-platform:"$TAG" --format '{{.Manifest.Digest}}')`;
   assert `DIGEST` non-empty + `=~ ^sha256:[0-9a-f]{64}$`; `PINNED="ghcr.io/jikig-ai/soleur-web-platform@$DIGEST"`.
   **Multi-arch (CTO must-fix 4, hard checkpoint):** `{{.Manifest.Digest}}` is the manifest-LIST
   digest; confirm the runner + Hetzner host are both amd64 so `docker create`/`run` resolve the
   same platform manifest (host-scripts are arch-independent text, so content coherence holds —
   assert amd64 to keep the equivalence exact).
2. **Coherence preflight (LOAD-BEARING).** Compute the applied hash:
   `WANT=$(doppler run … -- terraform console <<< 'local.host_scripts_content_hash' | tr -d '"')`.
   docker-cp the digest's baked scripts and recompute the **boot-identical** hash
   (`cloud-init.yml:390`): `docker create --name seed "$PINNED"; docker cp seed:/opt/soleur/host-scripts/. "$D/";`
   `GOT=$(cd "$D" && find . -type f -exec sha256sum {} + | awk '{print $1}' | LC_ALL=C sort | tr -d '\n' | sha256sum | awk '{print $1}')`.
   `[ "$GOT" = "$WANT" ]` — else ABORT before `-replace` (message: the pinned digest's baked
   host-scripts diverge from the applied hash → recreating would RE-ABORT at cloud-init
   `stage=verify`; the checkout has drifted from web-1's running image). This is the exact
   boot check run off-host, pre-destruction — **the durable `:latest` fix** (scope item 2).
3. **Plan (guarded).** `terraform plan -replace='hcloud_server.web["web-2"]'` + the 3 web-2
   `-target`s + `-var="image_name=$PINNED"` + `-var="ssh_key_path=$CI_SSH_PUB"` `-out=tfplan`.
   Run the extended destroy-guard (AC5, sourced function): abort unless
   `web2_out_of_scope_changes==0 && nested_deletes==0 && reboot_updates==0 && web2_server_replaced==1`.
4. **Apply (explicit ack).** `terraform apply -auto-approve tfplan`. Post-apply, assert web-2
   attachments re-landed in state and `hcloud_volume.workspaces["web-2"]` is NOT in the plan's
   destroy set (AC15) — mirror `warm_standby`'s attach-proof (`:775-805`).
5. **Wait + off-host verify.** Bounded generous poll: trigger the deploy fan-out to web-2 and
   poll `/hooks/deploy-status` until `exit_code==0 && tag==deployed_tag && reason=="ok"` (the
   single-peer invariant proves web-2 accepted → `:9000` bound). Reuse `warm_standby`'s
   baseline/fan-out/verify shape (`:807-1025`) — do NOT re-derive; extract shared steps if
   clean.
6. **Surface fresh-host Sentry on failure (AC14).** On verify timeout/RED, query Sentry for a
   recent `soleur-hostscript-seed failed` OR `soleur-host-bootstrap failed` event within the
   apply window and echo it into `$GITHUB_STEP_SUMMARY` with the `stage`/`failed_file`/`host_id`
   tags. (Deepen-plan: exact Sentry search API + auth; `host_id` is web-2's Hetzner instance-id,
   not known to the runner — match on message + recent window as the pragmatic query.)

### Phase 4 — Documentation (ADR-068 + runbook + C4)

1. **ADR-068 Amendment (2026-07-05).** web-2-recreate bootstrap is the **prerequisite** to the
   warm-standby fan-out (web-2 must bind `:9000` before the fan-out can verify `reason==ok`);
   record the digest-pin determinism decision (recreate/boot must pin an `@sha256` digest whose
   baked host-scripts hash == applied `host_scripts_content_hash`, never trust `:latest`).
2. **Runbook** `moved-block-wedge-cutover-5887.md` §Warm-standby bring-up — insert a step
   BEFORE step 5 (warm-standby): "web-2 host bootstrap (recreate)" documenting the autonomous
   dispatch. Phrase for `lint-infra-no-human-steps` (dispatch/orchestrator actor; `gh workflow
   run` is a menu dispatch, NOT an on-host infra imperative; NO "operator SSHs/runs by hand").
   Include the **coherence-abort remediation** (CTO must-fix 3): if the preflight aborts on a
   hash mismatch, redeploy web-1 to current `main` first, then re-dispatch. Include the
   **re-dispatch-is-idempotent** note (spec-flow P2-3).
3. **C4** — `hetzner`, `ghcr`, and the `hetzner -> ghcr` pull edge (`model.c4:321`) are already
   modeled; refine that edge's description to note digest-pinning on recreate. No new external
   actor/system/container.

## Infrastructure (IaC)

### Terraform changes
- **No new `.tf` resources.** The recreate operates on existing `hcloud_server.web["web-2"]` +
  its two dependents via `-replace`/`-target`. The only Terraform-adjacent change is the
  extended destroy-guard jq (a CI artifact, not `.tf`).
- **Sensitive vars:** `image_name` pinned to a **public** GHCR `@sha256` digest (not secret);
  all `TF_VAR_*` flow via the existing Doppler `prd_terraform` `--name-transformer tf-var`
  pattern; R2 backend creds via the existing bare-`AWS_*` extract step.

### Apply path
- **(c) taint + `terraform apply -replace`** — the ONLY path (`ignore_changes` blocks in-place
  cloud-init re-push). Blast radius: web-2 only (server + network attach + volume attachment
  replace). web-2 is weight-0 / drained → **zero ingress impact**. Downtime: none for users.

### Distinctness / drift safeguards
- `dev != prd`: this is a `prd_terraform`-only path (no dev web cluster).
- `lifecycle.ignore_changes = [user_data, ssh_keys, image, placement_group_id]` stays — the
  recreate relies on CREATE-leg bypass of `ignore_changes`; a plain apply still cannot push
  cloud-init.
- The `-target` set deliberately EXCLUDES `hcloud_server.web["web-1"]` (untargeted, not a
  dependency of any web-2 address) AND `hcloud_volume.workspaces["web-2"]` (data-bearing;
  0-destroy asserted by the guard + AC15).

### Vendor-tier reality check
- n/a (Hetzner/GHCR already provisioned; no new vendor tier).

## Observability

```yaml
liveness_signal:
  what: web-2 :9000 bound (webhook listener up) proven off-host via web-1 /hooks/deploy-status reason flip ok_peer_fanout_degraded to ok
  cadence: on-dispatch (bounded poll, STATUS_POLL_MAX_ATTEMPTS x interval under 30m ceiling)
  alert_target: the web_2_recreate job fails RED on verify timeout; Better Stack per-host absence detector (web-2.app.soleur.ai/health) once monitored=true (gated OFF today, monitored=false)
  configured_in: .github/workflows/apply-web-platform-infra.yml (web_2_recreate job); apps/web-platform/infra/uptime-alerts.tf (#5933 Item 1, future-on)
error_reporting:
  destination: Sentry (fresh-host emit_fail — soleur-hostscript-seed failed / soleur-host-bootstrap failed, fatal, tags stage+failed_file+host_id)
  fail_loud: true (cloud-init set -e + exit 1 aborts the whole runcmd; /run/soleur-hostscripts.ok sentinel absent then terminal block poweroffs; host stays absent to Better Stack)
failure_modes:
  - mode: fresh boot re-aborts at cloud-init stage=verify (hash mismatch)
    detection: coherence preflight catches it BEFORE -replace (off-host, no destruction); if it slips past, Sentry stage=verify + verify-step RED + job surfaces the event
    alert_route: job RED + GITHUB_STEP_SUMMARY Sentry pointer
  - mode: fresh boot aborts at install/hooks/assert (post-verify)
    detection: Sentry soleur-host-bootstrap failed stage=install|hooks|assert|reload|journald + verify never reaches reason==ok
    alert_route: job RED + summary pointer
  - mode: guard defect lets the plan touch web-1 (delete/replace/reboot-via-any-attr/stray-create)
    detection: web2_out_of_scope_changes (positive scope) + reboot_updates + nested_deletes guard aborts BEFORE apply; counter test (incl. web-1 non-placement update case) + parity test gate at CI
    alert_route: CI red (pre-merge) — never reaches prod
logs:
  where: GitHub Actions run log (web_2_recreate job); web-2 host journald (persistent, post-bootstrap) via Vector; deploy-status JSON
  retention: GH Actions default; journald bounded per journald-soleur.conf
discoverability_test:
  command: 'curl -s -H "X-Signature-256: sha256=$(printf "" | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" | sed "s/.*= //")" -H "CF-Access-Client-Id: $CF_ID" -H "CF-Access-Client-Secret: $CF_SECRET" https://deploy.soleur.ai/hooks/deploy-status | jq -r .reason'
  expected_output: "ok" (was ok_peer_fanout_degraded pre-bootstrap) — NO ssh
```

## Architecture Decision (ADR/C4)

Detected: this **amends ADR-068** (a new bootstrap prerequisite + a determinism decision on
the `:latest`→digest pin for recreate/boot). The ADR write is a deliverable of THIS plan, not
a deferred issue (`wg-architecture-decision-is-a-plan-deliverable`).

### ADR
- **Amend ADR-068** — add a 2026-07-05 Amendment: (1) web-2-recreate is the autonomous no-SSH
  prerequisite that binds web-2 `:9000` before the warm-standby fan-out can verify `reason==ok`;
  (2) recreate/boot pins an immutable `@sha256` digest whose baked host-scripts hash provably
  matches the applied `host_scripts_content_hash` (coherence preflight) — the durable fix for
  the `:latest` non-determinism / ADR-080 stale-image trap. Sequenced under the existing
  `## C4 impact` section. (ADR ordinal n/a — amendment, not a new ADR.)

### C4 views
- Enumeration checked against all three `.c4` files: (a) external actors — none new (operator
  dispatch is the existing menu-ack actor); (b) external systems — `ghcr` (GHCR) and `sigstore`
  already modeled (`model.c4:244,324`); (c) containers/stores — `hetzner` cluster already models
  the fresh-host boot pull + baked-script docker cp (`model.c4:170,321`); (d) access relationships
  — no change (web-2 joins no serving pool). **Refinement only:** amend the `hetzner -> ghcr`
  edge description (`model.c4:321`) to note the recreate/boot pins an `@sha256` digest (not
  `:latest`). Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after.
- **No new C4 element** — the enumeration above is the citation (not an unsupported "None").

### Sequencing
- The amendment describes the current (post-merge-dispatchable) state; it is authored in THIS
  PR, not postponed.

## Domain Review

**Domains relevant:** Engineering (infra/CI). No UI-surface files in Files-to-Edit → Product/UX
Gate = NONE. GDPR gate (2.7): no regulated-data surface touched → skip. IaC gate (2.8):
satisfied above (no manual SSH; autonomous dispatch). Observability gate (2.9): block present.

### Engineering (CTO)
**Status:** reviewed — **verdict: proceed to /work, do NOT reject** ("unusually rigorous plan").
CTO verified the file:line citations, the hash byte-equivalence (preflight == boot check), the
order-agnostic replace detection, the type-scoped `reboot_updates`, and the shared-R2-serializer
correctness (no lock-less second-writer hazard — a job of the same workflow inherits the group).
5 must-fixes folded: (1) freeze one `$PINNED` (TOCTOU, AC3b); (2) dual `stripJob` call sites
(AC7); (3) runbook coherence-abort remediation (Phase 4.2); (4) multi-arch digest hard checkpoint
(Phase 3.1 / Phase 0.7); (5) `["forget"]` action-semantics note (Phase 1 jq comment).

### SpecFlow (spec-flow-analyzer)
**Status:** reviewed. Caught **P0-2** (the load-bearing correctness fix): the original 4-key
guard did NOT enforce "only the 3 web-2 replaces" — a web-1 in-place update rebooting via a
non-`placement_group_id`/`server_type` attr, or any stray create, passed green. Resolved by the
POSITIVE-scope `web2_out_of_scope_changes` key (Phase 1). Also folded: P0-1 (exact-equality
membership, done), P1-1 (extract gate to sourced fn + test rc + `[ack-destroy]`-no-bypass, AC5/AC6),
P1-2 (preflight `set -euo pipefail` + format-validate, AC10b), P1-3 (reuse warm_standby verify +
timeout-`exit 1` test, AC10c), P1-4 (preflight standalone + mismatch fixture pre-merge test,
AC10b), P2-1 (gate `.tag` read on web-1 `reason==ok`, Phase 3.1), P2-3 (idempotent re-dispatch,
AC16), P2-4 (`@sha256` var-validation check, Phase 0.6), P2-5 (runner amd64, Phase 0.7).

### Product/UX Gate
**Tier:** none (no user-facing surface; infra workflow). No `.pen` required.

## Risks & Sharp Edges

- **Guard precision is the whole ballgame.** `web2_disallowed_deletes` MUST count deletes
  outside the exact 3-address allow-set — a web-1 replace serializes with `actions⊇{delete}`
  and MUST trip it; the counter test's T21 is the proof. Do NOT rely on `-target` alone to keep
  web-1 out (defense-in-depth: web-1 is untargeted AND guarded).
- **jq membership MUST be exact-equality (`index($a)`), NOT `inside`/`contains`** — array
  `contains` does SUBSTRING matching on string elements (a false-match hazard on similar
  addresses). Verified on jq 1.8.1 this session; the counter test is the executable arbiter.
  (Sharp Edge: prose-contract-vs-executable-check dimension drift.)
- **Coherence preflight is load-bearing** — pinning web-1's running digest WITHOUT the hash
  check can re-abort at `stage=verify` (the exact bug). The preflight is the off-host
  equivalent of the boot check; never skip it.
- **`terraform console` for the hash** — avoids re-implementing `local.host_script_files` in
  bash (lockstep-drift trap, `server.tf:12-14` warns the list is kept in lockstep with the
  Dockerfile COPY). Confirm `terraform console` resolves all vars under `doppler run
  --name-transformer tf-var`.
- **A plan whose `## User-Brand Impact` is empty/TBD fails deepen-plan Phase 4.6** — it is
  filled above (threshold single-user incident, CPO sign-off flagged).
- **`gh workflow run` resolves against the default branch** — the web-2-recreate path is
  post-merge only; never dispatchable pre-merge.
- **Sweep ALL guard suites** — jq + counter test + parity test + any orphan scope-guard
  (`2026-05-29`). Missing one greens a false pass under `test-all.sh` exit-code aggregation.
- **`docker buildx imagetools inspect` digest format** — multi-arch manifest-list vs
  platform digest; pin the manifest-list digest (what `docker pull` resolves on the amd64 host).
- **for_each over target-excluded map** (`2026-07-03`) — this PR adds NO new `for_each =
  var.web_hosts` resource, so the premature-provisioning trap does not apply; confirm at review.
- **Positive-scope guard subsumes delete-only (spec-flow P0-2)** — `web2_out_of_scope_changes`
  counts ANY create/update/delete outside the 3-address allow-set, closing the hole where a
  web-1 in-place update rebooting via a non-`placement_group_id`/`server_type` attr passed green
  (the `reboot_updates` counter is KNOWN-UNCOVERED for those attrs). Do NOT regress to a
  delete-only counter.
- **`["forget"]` action semantics** — a Terraform 1.7+ `removed{}` state-drop is a distinct
  action; the positive-scope `any(create/update/delete)` does not count it (no `removed{}` blocks
  in `apps/web-platform/infra/` today). Mirror the filter header's existing forget note.
- **Coherence-abort operational coupling (CTO must-fix 3)** — the preflight aborts loud whenever
  `main`'s host-scripts advanced beyond what web-1 currently runs (unrelated host-script merge
  not yet deployed to web-1). Safe (aborts before `-replace`) but confusing; the runbook step
  MUST state the remediation: **redeploy web-1 to current `main` first, then re-dispatch.**
- **AC14 Sentry surface is best-effort** — `host_id` is unknown to the runner, so the query
  matches on message + recent window; a concurrent/stale event or a failed `emit_fail` curl
  yields a misleading or empty pointer. Job RED's regardless; label the summary line
  "best-effort, may show an unrelated host / may be empty."

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Plain `terraform apply` to re-push cloud-init | **Rejected** — `ignore_changes=[user_data]` blocks it; only recreation re-runs first-boot |
| On-host webhook remediation over a manual root session | **Rejected** — violates `hr-no-ssh-fallback-in-runbooks` / `hr-all-infrastructure-provisioning-servers`; web-2 has no admin-IP path from the runner anyway |
| Pin `:latest` (trust the mutable tag) | **Rejected** — the exact non-determinism that caused the abort; scope item 2 replaces it with a coherence-checked digest |
| Blanket `[ack-destroy]` on the recreate path | **Rejected** — ack would also permit a web-1 delete; the precision guard (permit ONLY the 3 web-2 replaces) is strictly safer |
| Pin web-1's running digest without the coherence preflight | **Rejected** — re-aborts at `stage=verify` if `main` drifted since web-1's deploy; the preflight is mandatory |

## Files to Edit
- `.github/workflows/apply-web-platform-infra.yml` — `apply_target` choice + new `web_2_recreate` job.
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq` — `web2_disallowed_deletes` + `web2_server_replaced` keys.
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` — T20-T24 cases.
- `plugins/soleur/test/terraform-target-parity.test.ts` — `WEB2_RECREATE_TARGETS` + assertions.
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — Amendment + C4-impact reconcile.
- `knowledge-base/engineering/operations/runbooks/moved-block-wedge-cutover-5887.md` — web-2-recreate step.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `hetzner -> ghcr` edge description refinement.

## Files to Create
- `tests/scripts/fixtures/tfplan-web2-recreate-*.json` — synthesized destroy-guard fixtures (T20-T24).

## Open Code-Review Overlap

None checked at draft time — run `gh issue list --label code-review --state open --json number,title,body`
against the Files-to-Edit at deepen-plan/work; record dispositions.

## PR-body reminder

Use `Ref #5887` (ADR-068 GA arc context) — NOT `Closes` (the actual web-2 bootstrap is the
post-merge operator dispatch, not the merge). Split ACs Pre-merge / Post-merge (done above).
