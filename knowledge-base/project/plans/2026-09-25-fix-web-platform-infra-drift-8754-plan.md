---
title: "fix(infra): clear the standing web-platform drift tail and bind the inngest firewall at server creation (#8754)"
date: 2026-09-25
slug: fix-web-platform-infra-drift-8754
branch: feat-one-shot-8754-web-platform-drift
issue: 8754
closes: ""
type: fix
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Clear the web-platform Terraform drift reported in #8754

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-25

**Sections enhanced:** Implementation Phases (3.1, 3.2, 0.4, 1B.4), Downtime & Cutover (new),
Observability, User-Brand Impact, Acceptance Criteria (AC-C2), Per-resource classification
(attributions), Research Insights.

**Agents used:**

- **Deepen pass:** security-sentinel, deployment-verification-agent,
  observability-coverage-reviewer, user-impact-reviewer, and a verify-the-negative/attribution sweep.
- **Planning, carried in:** terraform-architect, CTO (twice), CPO, spec-flow-analyzer (twice),
  advisor consult, DHH, Kieran, code-simplicity and architecture-strategist.

### Key Improvements

1. The inngest firewall is now bound through `hcloud_server.firewall_ids`, so it attaches before
   first boot. This replaces plan v2's target-plus-gate-counter design. Three reviewers converged on
   it. It removes the boot window and the partial-failure dead end.
2. A new `## Downtime & Cutover` section evaluates and rejects blue-green for the singleton
   scheduler, with a bounded window and a rollback path for 3.1.
3. The git-data G3 step now carries the runbook's one-attempt cap, its GO fields, and the Art. 12(3)
   deadline of 2026-10-24.
4. Observability now cites a layer for every failure mode, adds the stranded-scheduler mode, and
   makes the probe print the server ids.

### New Considerations Discovered

- `sendInngestWithRetry` gives up after about 1.5 s. Events sent while the inngest host is down fail
  at the caller, and that failure class is live today.
- Two attributions in the draft were wrong: the heartbeat pair came from PR #5818, and the digest
  came from PR #6839, not #6780.
- The PR plan job's `GITHUB_TOKEN` cannot read deployment policies once an `import` block exists,
  hence the `actions: read` change.

## Overview

The scheduled drift check on the `web-platform` Terraform root reports a non-empty plan
(16 to add, 3 to change, 9 to destroy, run of 2026-09-25 06:02 UTC). Measured against the live
APIs, that plan is four separate problems.

1. **A standing tail that no workflow can apply.** It has appeared in every drift report since at
   least 2026-08-06 (#7316). Two of its diffs are perpetual: every merge apply "fixes" them and the
   next refresh reverts them. They are `cloudflare_bot_management.soleur_ai` and
   `github_repository_environment_deployment_policy.web_platform_infra_apply_main`. Six more
   resources are "operator-applied exclusions" whose route, a full-root apply outside CI, no longer
   exists: the git-data heartbeat pair, the proxy-TLS quartet, the inngest config-digest pointer,
   and the orphaned `ZOT_HEARTBEAT_URL` secret.
2. **A live security gap.** The dedicated inngest host (`167310350`, born 2026-09-24 18:57 UTC)
   has **no Hetzner firewall attached**. The deny-all firewall `soleur-inngest` (id 11269127) is
   applied to nothing, and sshd answers on the public IP. The binding is
   `hcloud_firewall_attachment.inngest`, whose `server_ids` goes stale on every replace.
   `inngest-host-replace` does not target it, on the premise that "the next full/drift apply
   reconciles server_ids". No such apply exists.
3. **A pending git-data host replace.** PR #8711 changed its user_data after the 2026-09-24 09:08
   replace. The replace belongs to the #5274 git-data LUKS post-merge sequence (G2 `plan_only`,
   then G3 real replace), and each of those steps needs its own explicit go-ahead.
4. **A pending inngest host replace.** The ADR-232 pin bump to inngest-bootstrap v1.1.40 (PR #8802)
   changed its user_data. The delivery route is `inngest-host-replace` followed by
   `cutover-inngest.yml op=resume` (measured `INNGEST_CUTOVER_FLIP=done`). It overlaps the open
   inngest outage #8833/#8834.

The plan ships **two small config PRs**:

- **PR-A** binds the inngest firewall through `hcloud_server.inngest.firewall_ids`. Hetzner then
  applies the firewall at server creation, before first boot, on every birth and replace, so no
  attachment can go stale and no gate has to police one.
- **PR-B** converges the standing tail.

Classes 2 to 4 then run through the repo's existing gated dispatch routes in one fixed order. The
exit criterion is a clean follow-up drift plan. The host replaces need a per-command go-ahead, and
the plan states exactly what remains if that go-ahead is not given in-session.

## Research Reconciliation — Brief vs. Live Reality

| Brief claim | Reality (measured 2026-09-25) | Plan response |
|---|---|---|
| Plan destroys `zot_heartbeat_url_prd`, creates git-data heartbeat, `inngest_config_digest`, proxy TLS, deployment policy | True, but **none of it is new**: every one has been in every drift report since #7316 (2026-08-06). EVERY merge apply re-"creates" the deployment policy, and the next refresh drops it | Classified per resource below; config fixes, not "apply the pending merge" |
| `hcloud_firewall_attachment.inngest` still lists 165279348 | Hetzner API: server 165279348 is `not_found`. Firewall 11269127 has `applied_to=[]`, and server 167310350 has `firewalls=[]`. On 95.217.161.110, TCP 22 is **open**; 80, 443, 6379, 8288, 8289, 9000, 9090 and 3000 are filtered. The firewalled git-data host (2.29.3.249) filters 22 | Real drift with a structural cause. PR-A binds the firewall on the server resource itself; the next inngest replace creates the host with the firewall already applied |
| `cloudflare_bot_management` diff is "dashboard drift or provider default" | The zone plan is **Pro** (`legacy_id=pro`). The live API returns `sbfm_definitely_automated=allow` and `sbfm_verified_bots=allow`. Config omits both, so every merge apply's PUT omits them and the API keeps `allow`: a perpetual diff. Push applies 35976102312, 36008843465, 36037220805, 36077212409 and 36092626570 all print `cloudflare_bot_management.soleur_ai will be updated in-place` | Declare both as `"allow"`. This mirrors live state and follows the drift-detect rationale the file already gives for `fight_mode` |
| Deployment policy is an un-applied merge | The live `web-platform-infra-apply` environment has policy `main`, id **49861552**, created outside Terraform. The provider's create collides with it and records the phantom id `soleur:web-platform-infra-apply:0` (operator comment on #8590), which each refresh drops | Adopt id 49861552 by `import` into a NEW address, plus `removed{destroy=false}` for the phantom address. An import whose target address is already in state is skipped, and the phantom is back in state after every merge apply |
| Host replaces "are normally driven by a dedicated replace dispatcher" | Confirmed. git-data uses `apply_target=git-data-host-replace`, which `git-data-pin-redeploy.yml` follows automatically. Inngest uses `apply_target=inngest-host-replace` followed by `cutover-inngest.yml op=resume`. The drift check is full-root (`scheduled-terraform-drift.yml`: "The plan is full-root"), so there is **no** exclusion convention. The git-data runbook calls the pending replace "Expected drift" | Replaces stay on their owning routes, gated on per-command go-ahead |
| Both hosts boot from zot only; GHCR PAT revoked | Consistent with #8708 (merged 2026-09-24). Neither replace needs GHCR | Replaces carry no GHCR dependency; backlog items 2 and 3 are untouched |

## Per-resource classification

Commit and PR attribution comes from `git log -S` on `origin/main` (the git-history research) and from live reads.

| # | Planned action | Class | Evidence | Resolution |
|---|---|---|---|---|
| 1 | `cloudflare_bot_management.soleur_ai` ~ (`sbfm_*` allow→null) | **Real drift (config)**: a perpetual diff | Pro zone; live value `allow`; config omits both attributes, so every merge apply has re-PUT them since at least #7316 | PR-B: declare `sbfm_definitely_automated = "allow"` and `sbfm_verified_bots = "allow"` |
| 2 | `github_repository_environment_deployment_policy.web_platform_infra_apply_main` + | **Real drift (state)**: a phantom create that collides with a pre-existing live policy | Added by PR #6953 (2f46570c19, 2026-07-26). Live policy id is 49861552. Every merge apply records the phantom id `…:0` | PR-B: new address `…web_platform_infra_apply_main_adopted`, an `import` (id `soleur:web-platform-infra-apply:49861552`), and `removed{destroy=false}` for the old address |
| 3 | `doppler_secret.zot_heartbeat_url_prd` − | **Un-applied removal** (no route) | Removed in PR #6654 (14075d1b43, 2026-07-18). It was never on any `-target` list, so no apply ever destroyed it. **Zero consumers** (see the ZOT audit) | PR-B: bare `-target` on the orphaned address in the per-merge list (a destroy "because not in configuration"); the squash commit carries `[ack-destroy]` |
| 4 | `betteruptime_heartbeat.git_data_prd` + and `doppler_secret.git_data_heartbeat_url_prd` + | **Un-applied, no route**: an `OPERATOR_APPLIED_EXCLUSIONS` member whose route (a full-root apply outside CI) no longer exists | Both resources were declared by PR #5818 (e589457312, 2026-07-01); PR #6654 rewired the secret's consumer. The feeder `web-git-data-probe.sh` now dereferences the URL through a per-run `doppler run` (`web-git-data-probe.service`), and heartbeat-manifest.ts flipped the row to `kind:"timer"`. `arm-heartbeats.sh` already has `arm_one 'betteruptime_heartbeat.git_data_prd'`. #6548 and the `l3-probe-armed-6438.sh` follow-through are both waiting on it (`soleur-git-data-prd=ABSENT`) | PR-B: move both to the per-merge `-target` list. The same merge apply's arm step measures a beat, then arms the heartbeat or rolls it back to paused |
| 5 | `tls_private_key.proxy_server`, `tls_self_signed_cert.proxy_server`, `doppler_secret.proxy_tls_{key,cert}` + | **Declared ahead of rollout** (no route; the consumer shipped, the rollout config is absent) | PR #5877 (d7f1fa55ff, 2026-07-01). `SOLEUR_PROXY_BIND` and `SOLEUR_PROXY_PEER_ALLOWLIST` are absent from Doppler prd. web-2 is a weight-0 standby until the Phase-6 flip (`lb-weight-gate.sh`). Delivering the material now would make `createProxyServer` fire a `reportSilentFallback` Sentry event on every container start (`session-proxy.ts`, `createProxyServer.no-bind`) | PR-B: gate all four behind `var.host_proxy_tls_enabled` (bool, default `false`), which the multi-host flip sets |
| 6 | `doppler_secret.inngest_config_digest` + (value `""`) | **Declared ahead of need** (no promoted digest; channel not live) | PR #6839 (32431c8249, 2026-07-23; issue #6780). `INNGEST_CONFIG_DIGEST` is absent from `prd_terraform`, so the variable takes its default `""`. `betterstack-query.sh --grep SOLEUR_INFRA_PULL_APPLIED --since 48h` returns nothing, so by the runbook's own gate the channel is not live | PR-B: `count = var.inngest_config_digest != "" ? 1 : 0`; file a follow-up for the missing promotion apply route |
| 7 | `hcloud_firewall_attachment.inngest` ~ | **Real drift: a live security gap** | See Research Reconciliation row 2. The attachment's `server_ids` binds to the replaced server's id and nothing re-targets it; `inngest-host.tf` says "Do NOT add it to the replace allow-set" | PR-A: `firewall_ids = [hcloud_firewall.inngest.id]` on `hcloud_server.inngest`; `removed{destroy=false}` for the attachment. The next inngest replace creates the server with the firewall applied |
| 8 | `hcloud_server.inngest` −/+ (+ `hcloud_server_network.inngest`, `hcloud_volume_attachment.inngest_redis{,_luks}`) | **Expected via another path** | user_data changed by PR #8802 (309ff2a316, pin v1.1.39→v1.1.40, ADR-232). The last replace was run 36044687768 (2026-09-24 18:56) | `apply_target=inngest-host-replace` after PR-A merges, then `cutover-inngest.yml op=resume`. One go-ahead covers both. Coordinate with #8833 |
| 9 | `hcloud_server.git_data` −/+ (+ network, `hcloud_volume_attachment.git_data{,_luks}`) and `hcloud_firewall_attachment.git_data` ~ | **Expected via another path**. The firewall update is only the replace cascade: live firewall 11622852 is correctly applied to 167236662 | user_data changed by PR #8711 (a5b2e36b56, dm-snapshot count) after the 2026-09-24 09:08 replace. Rung-2 evidence landed in PR #8751 (`RUNG2_REPLACE_BOOT=PASS`). #8710 was fixed by PR #8755 | #5274 post-merge G2 (`plan_only=true`), then G3 (`apply_target=git-data-host-replace`); `git-data-pin-redeploy.yml` follows automatically. Per-command go-ahead |

### ZOT heartbeat secret audit (precondition for destroying #3)

- `git grep -nIi -E 'ZOT_HEARTBEAT_URL|zot_heartbeat_url'` finds 20 files on `origin/main` (23 with this plan's own artifacts), and **every hit is a
  comment, an ADR, a learning, a brainstorm or a plan**. No code, workflow, cloud-init, script or
  test dereferences the value. Within `apps/ plugins/ scripts/ tests/ .github/ infra/` the only hits
  are three `.tf` comments and one parity-test comment. No glob-style `*_HEARTBEAT_URL` consumer
  exists.
- `gh secret list` and `gh variable list` contain no `ZOT_*HEARTBEAT*`.
- A Doppler raw-value scan (`doppler secrets --json --raw`) across `soleur/{prd,prd_terraform,dev,ci}`,
  `soleur-registry/prd` and `soleur-inngest/prd` found zero `${…ZOT_HEARTBEAT…}` references, and no
  cross-config references at all.
- The value points at a Better Stack heartbeat URL. Deleting the Doppler secret does not touch any
  Better Stack object.
- The historical record agrees. ADR-117 and learning
  `2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes.md` measured "zero
  consumers", and PR #6654 deleted the block for exactly that reason.
- The work phase re-runs this audit (AC-B1), because the claim is a snapshot.

## Research Insights

**Premise Validation.** #8754 is open, labelled `priority/p1-high` and `infra-drift`, and its latest
drift comment (2026-09-25 06:02) was read in full. The cited PRs are all verified merged: #8711,
#8751, #8755 (for #8710), #8802, #8745 and #8708. Two overlapping incidents are open: #8833 and
#8834 (the dedicated inngest host is not serving; opened 2026-09-25 09:17). A `web_host_replace`
dispatch (run 36117021829) was **in progress** at 09:11 UTC on the shared
`terraform-apply-web-platform-host` group. The prior drift issue #8590 was auto-closed by
`apply-deploy-pipeline-fix.yml` ("Server state was re-aligned with HEAD") while the same tail
remained, and the next drift run opened #8754.

**Property List** (what the ask needs, independent of mechanism):

- P1 — a full-root drift plan of `apps/web-platform/infra` exits 0 (no changes).
- P2 — every live Hetzner host with a declared firewall has it applied, including from the first
  boot after any gated birth or replace.
- P3 — nothing reads `ZOT_HEARTBEAT_URL` at the moment it is deleted.
- P4 — no host replace runs outside its gated route, and both stores (git-data LUKS, inngest Redis
  AOF) survive.
- P5 — backlog items 2 (GHCR token-minter retirement) and 3 (GHCR egress removal) are not touched.

**Cut List:**

- `-target` of `hcloud_firewall_attachment.inngest` in the replace job, plus a gate counter, plus
  an `inngest-host` shape-gate recovery route (P2). This was plan v2. It was cut once the review
  panel converged on `hcloud_server.firewall_ids`. The provider applies `opts.Firewalls` inside
  ServerCreate (`terraform-provider-hcloud` v1.63.0 `internal/server/resource.go`, create path),
  and `firewall_ids` updates in place (`d.HasChange("firewall_ids")`), so the firewall is on the
  host before first boot. That closes the boot window ADR-145 records for attachments, and leaves no
  stale binding to police, no gate change and no partial-failure dead end.
- A new `apply_target` "standing-set reconcile" dispatch (P1). The per-merge allow-list already
  applies host-independent resources. Workflow byte headroom is about 1.4 kB (488,582 of
  490,000 B, `workflow-file-size.test.ts`).
- `lifecycle.ignore_changes` on the `sbfm_*` attributes (P1). Cut in favour of declaring the live
  value: SBFM is dashboard-settable on a Pro zone, and a toggle to `block` would re-block AI
  crawlers.
- A same-address `import` for the deployment policy (P1). Terraform skips an import whose address
  is already in state, and every merge apply re-records the phantom.
- Applying the proxy-TLS quartet now (P1). That would turn every web container start into a Sentry
  silent-fallback event.
- A `removed{destroy=true}` block for the ZOT secret. A bare `-target` on the orphan already plans
  the destroy (verified on 1.10.5).
- A `for_each` fallback on the import, and the ADR-118 C4 description edit (review cuts).
- A pre-merge rehearsal via `scheduled-terraform-drift.yml` from the PR branch. It is infeasible:
  that job and every apply job run under `environment: infra-privileged`, whose policy is main-only
  (`infra_privileged_main`, `branch_pattern = "main"`). The PR's own `infra-validation` plan comment
  (AC-B6) is the pre-merge shape check instead.

**Relevant files (verified on origin/main):**

- `apps/web-platform/infra/inngest-host.tf`: `resource "hcloud_server" "inngest"` (its `firewall_ids` is currently unset) and `resource "hcloud_firewall_attachment" "inngest"` with its comment
- `apps/web-platform/infra/inngest-host.test.sh`: static checks over `inngest-host.tf`, e.g. check 3 "Deny-all-public firewall (zero inbound rules)"
- `apps/web-platform/infra/bot-management.tf`, `web-host-birth-environment.tf` (ADOPTION note), `zot-registry.tf` (NOTE #6438 B3), `git-data.tf` (the heartbeat pair), `proxy-tls.tf`, `inngest-config-digest.tf`, `variables.tf`
- `apps/web-platform/server/proxy-tls.ts` and `apps/web-platform/server/session-proxy.ts` (`createProxyServer`)
- `.github/workflows/apply-web-platform-infra.yml`, three places: the `apply` job's `Terraform plan (allow-list, non-SSH resources only)`; the `inngest_host` job plan step, which carries `-target='hcloud_firewall_attachment.inngest'`; and the arm step `arm-heartbeats.sh --arm`
- `.github/workflows/infra-validation.yml`, job `plan`: an untargeted `-refresh=false` plan whose token has `contents: read` and `pull-requests: write`
- `tests/scripts/lib/inngest-host-shape-gate.sh` and `tests/scripts/test-inngest-host-shape-gate.sh`: class `firewall_touched`; red rows for the attachment's `update` and `forget`
- `tests/scripts/lib/inngest-host-replace-gate.sh`: header comment claiming the attachment "does NOT change"
- `tests/scripts/lib/registry-host-replace-gate.sh`: comment "INTENTIONAL deviation from inngest"
- `plugins/soleur/test/terraform-target-parity.test.ts`: `OPERATOR_APPLIED_EXCLUSIONS`, which includes `hcloud_firewall_attachment.inngest` and the heartbeat pair; `GIT_DATA_BIRTH_REFUSED`, which must NOT change
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES = 29`
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq`: forget/ack semantics, and a stale "no `removed` blocks" note
- `apps/web-platform/infra/arm-heartbeats.sh`: `arm_one 'betteruptime_heartbeat.git_data_prd'`
- Runbooks: `git-data-luks-cutover-5274.md` (§"Between merge and step 3"), `inngest-server.md` (inherited `done`), `inngest-config-refresh.md` (step 3), `apply-web-platform-infra-job-rationale.md` (ADR-231 rationale home, which names the old policy address) and `vector-redeliver.md` (old policy address)

**Institutional learnings applied:**

- ADR-145: `hcloud_firewall_attachment` (unlike `hcloud_server.firewall_ids`) does not attach before
  first boot. ADR-148 states that stores are preserved by OMISSION from the `-target` set. The
  replace gate's address-pinned counters (`redis_volume_destroyed`, `redis_volume_touched`,
  `luks_volume_destroyed`, `luks_volume_touched`, `luks_passphrase_in_graph`) assert that
  positively.
- `2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`: a drift tail that no path applies
  is a design gap, not noise.
- ADR-231: the apply workflow is byte-budgeted, so rationale goes to the runbook, not the YAML.
- ADR-117 / #6537: a heartbeat is armed only after a measured beat (`arm-heartbeats.sh`).
- `destroy-guard-filter-web-platform.jq`: a `removed{}` forget is excluded from `resource_deletes`
  and trips `nested_deletes` only when `before.rules` is populated.
- Plan sharp edges applied:
  - Answer "does merging this alone mutate prod?" in each PR body's first line (#8296).
  - Enumerate every workflow that can apply an edited resource (#8705). Only
    `apply-web-platform-infra.yml` fires on these paths: `apply-deploy-pipeline-fix.yml`'s `paths:`
    names no edited file.
  - A declared `credentials_required` bumps `BASELINE_DECLARED_PROBES` (#8651).
  - Prefer delete over fix when both review panels fire on one scope.

**Terraform semantics, verified by the terraform-architect pass** (Terraform 1.10.5 on scratch
configs; provider sources read at the pinned tags):

- An `import` into an address holding a stale entry is skipped and plans a create.
- Renaming to a new address, importing into it and adding `removed{destroy=false}` for the old
  address works when both addresses are targeted. The plan reads "import … forget", it applies
  cleanly, and a re-plan shows no changes. If the old address is left untargeted, the forget is not
  planned.
- A bare `-target` on an orphaned address plans its destroy "because not in configuration".
- `count` over a sensitive variable works on 1.10.5 with or without `nonsensitive()`.
- `cloudflare_bot_management` v4.52.7: `sbfm_definitely_automated` and `sbfm_verified_bots` are
  Optional and not Computed. When config equals state there is no diff and no PUT.
- No other `.tf` file interpolates the proxy-TLS resources, so there is no state migration. The
  only other references are string literals in `terraform-target-parity.test.ts` and
  `test-destroy-guard-counter-web-platform.sh`, which keep matching index-free addresses.
- The github provider import ID is `<repository>:<environment>:<policy_id>`.
- A config-driven `import` still calls the provider Read under `-refresh=false`. That matters for the
  PR plan job (1B.3).
- Hetzner `hcloud_server.firewall_ids` is Optional+Computed and not ForceNew. At create it is sent
  as `opts.Firewalls`, and on update it is applied via `d.HasChange("firewall_ids")`. This was read
  from the v1.63.0 source during this plan.

**Repo settings that shape the ship path:** `squash_merge_commit_message = COMMIT_MESSAGES` and
`squash_merge_commit_title = COMMIT_OR_PR_TITLE` (`gh api repos/jikig-ai/soleur`). The squash body is
built from the branch's commit messages. PR #8733's body had no `[ack-destroy]` line, but its merge
commit did, carried in from a branch commit.

**External docs:** Terraform import idempotence
(developer.hashicorp.com/terraform/language/import/single-resource); github provider
`repository_environment_deployment_policy.md` import format. Pins: cloudflare `4.52.7`, github
`6.12.1`, hcloud per lock, Terraform `1.10.5`.

**CLAUDE.md conventions:** `hr-all-infrastructure-provisioning-servers`,
`hr-prod-host-config-change-immutable-redeploy`, `hr-menu-option-ack-not-prod-write-auth`,
`hr-dispatch-async-must-arm-watch`, `hr-monitor-not-run-in-background-for-polling`,
`hr-no-ssh-fallback-in-runbooks`.

## Implementation Phases

**Execution order (single, fixed):** Phase 0 → PR-A (1A) merge and verify (2A) → 3.1 inngest
replace + resume → 3.2 git-data G2/G3 → PR-B (1B) merge and verify (2B) → 3.3 final drift. Each
3.x step needs its own go-ahead. If the 3.2 go-ahead is withheld, PR-B still merges after 3.1, and
the expected heartbeat absence during a later G3 is posted on #5274. If the 3.1 go-ahead is
withheld, PR-B still merges, and the withheld-path deliverables below apply.

### Phase 0 — Re-measure at work time (read-only, no prod writes)

0.1 Re-read the newest drift comment on #8754 and diff its resource list against the table above.
    Classify any unlisted address first. Re-check #8754's `state`: `apply-deploy-pipeline-fix.yml`
    can flip it, and this check repeats before 2B and 3.3.
0.2 Run `gh run list --status in_progress` and `--status queued` for `apply-web-platform-infra.yml`,
    `cutover-inngest.yml`, `deploy-inngest-image.yml` and `git-data-pin-redeploy.yml`. No merge or
    dispatch happens while any run on the three groups is queued or in progress.
0.3 Re-run the ZOT audit (AC-B1).
0.4 GET-only reads, repeated immediately before each merge and dispatch:
    - firewall 11269127 `applied_to` and the inngest server's `firewalls`;
    - a TCP connect probe of the inngest public IP on 22, 6379, 8288, 8289 and 9000 (today only 22
      is open);
    - `GIT_DATA_STORE_ENABLED` absence from prd (names only, `doppler secrets -p soleur -c prd --only-names`).
      The 3.2 "store is dark" premise depends on it, so it is re-read immediately before G3;
    - the live deployment policy id, via
      `gh api repos/jikig-ai/soleur/environments/web-platform-infra-apply/deployment-branch-policies`.
    If any data port answers publicly, stop and route to the CLO for a GDPR assessment. If the
    policy id is no longer 49861552, use the live id.

### Phase 1A — PR-A: bind the inngest firewall at server creation (no destroy, no ack)

Test-first. Write the Guard 1 rows as failing assertions in `apps/web-platform/infra/inngest-host.test.sh`
before editing `.tf`.

1A.1 In `apps/web-platform/infra/inngest-host.tf`, add `firewall_ids = [hcloud_firewall.inngest.id]`
     to `resource "hcloud_server" "inngest"`. Replace `resource "hcloud_firewall_attachment" "inngest"`
     with `removed { from = hcloud_firewall_attachment.inngest  lifecycle { destroy = false } }`.
     The forget is non-destructive: the attachment is applied to nothing today, and a destroy would
     try to detach the firewall. Rewrite the comment block to record why: the attachment went stale
     on every replace, and `firewall_ids` applies before boot.
1A.2 In `.github/workflows/apply-web-platform-infra.yml`:
     - remove `-target='hcloud_firewall_attachment.inngest'` from the `inngest_host` job, so a birth
       never plans the forget;
     - add `-target=hcloud_firewall_attachment.inngest` to the per-merge `apply` list, so PR-A's own
       merge apply plans the forget. A `removed` block is planned only when its address is targeted
       (`doppler-write-token.tf` precedent). A forget is excluded from `resource_deletes`, and the
       attachment has no `before.rules`, so no `[ack-destroy]` is needed.
     Keep the YAML byte-neutral apart from the `-target` lines; the rationale goes to
     `apply-web-platform-infra-job-rationale.md`. `inngest_host_replace` is unchanged: its
     `-replace=hcloud_server.inngest` now creates the server with the firewall, and its gate's
     allow-set does not need the attachment.
1A.3 In `plugins/soleur/test/terraform-target-parity.test.ts`, reclassify
     `hcloud_firewall_attachment.inngest` so it appears where the parity suite expects a
     `removed`-block address targeted by the per-merge job (mirror the `doppler-write-token.tf`
     entries). Leave `GIT_DATA_BIRTH_REFUSED` alone.
1A.4 **Shape gate follows the job's `-target` set.** `tests/scripts/test-inngest-host-shape-gate.sh`
     DERIVES the `inngest_host` job's `-target` set and pins it at 18 addresses. Dropping the
     attachment makes that 17. Update the fixture count, and remove `"hcloud_firewall_attachment.inngest"`
     from the gate's `allow` list and from the `firewall_touched` class in
     `tests/scripts/lib/inngest-host-shape-gate.sh`, so the class covers `hcloud_firewall.inngest`
     only. Also update its header table.
     Two red rows change: `red firewall_touched 'hcloud_firewall_attachment.inngest=["update"]'` and
     the `["forget"]` row. They now expect the out-of-allow-set reason the gate emits for an address
     outside `allow`, because any action there is still refused. Verify that token against the
     gate's `order=(…)` array; do not assume it.
     Comment-only edits go to `tests/scripts/lib/inngest-host-replace-gate.sh` (the false "does NOT
     change" premise) and `tests/scripts/lib/registry-host-replace-gate.sh` ("INTENTIONAL deviation
     from inngest").
1A.5 In `plugins/soleur/test/preflight-discoverability-test.test.ts`, change
     `BASELINE_DECLARED_PROBES` from 29 to 30, with the PLACEMENT/TRUTH/NO SUBSTITUTE comment its
     failure text asks for. This plan declares `credentials_required` and the plan file rides this
     branch.
1A.6 ADR-100 amendment (see ADR/C4).
1A.7 PR-A body, first line: "Merging this runs the per-merge apply. It forgets the unapplied
     inngest firewall attachment, and, as on every merge since August, it re-PUTs bot management
     and re-records the phantom deployment policy. It changes no host. The firewall binding takes
     effect at the next inngest birth or replace." Use `Ref #8754`, not `Closes`.

### Phase 1B — PR-B: the standing tail (from a branch cut from main after PR-A merges)

1B.1 **Bot management.** In `bot-management.tf`, add `sbfm_definitely_automated = "allow"` and
     `sbfm_verified_bots = "allow"`, with a comment in the file's existing "mirrors the current
     dashboard state so plan drift-detects a toggle" style that names the Pro plan and the
     perpetual-diff evidence.
1B.2 **Deployment policy adoption.** In `web-host-birth-environment.tf`:
     - rename the resource to `web_platform_infra_apply_main_adopted`;
     - add `import { to = github_repository_environment_deployment_policy.web_platform_infra_apply_main_adopted  id = "soleur:web-platform-infra-apply:49861552" }`;
     - add `removed { from = github_repository_environment_deployment_policy.web_platform_infra_apply_main  lifecycle { destroy = false } }`.
     In the workflow, add `-target=…_adopted` and KEEP the old `-target`. Update the prose mentions
     in `apply-web-platform-infra-job-rationale.md` and `vector-redeliver.md`. Fix the stale "no
     `removed` blocks in apps/web-platform/infra/" note in
     `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (`doppler-write-token.tf` has two).
1B.3 **PR plan job permission.** Add `actions: read` to `permissions:` of job `plan` in
     `.github/workflows/infra-validation.yml`. Under `-refresh=false` an `import` still calls the
     provider Read, and GitHub's deployment-branch-policy GET needs Actions read. The payoff is that
     the PR's own plan comment then shows the import, the forgets, the destroy and the per-merge
     creates BEFORE merge (AC-B6). Fork PRs never run this job: its `if:` requires
     `needs.check-secrets.outputs.has-doppler-token == 'true'`, and forks get no secrets. The added
     scope is read-only.
1B.4 **ZOT secret destroy.** Add `-target=doppler_secret.zot_heartbeat_url_prd` to the per-merge
     list (a bare orphan target; no `removed` block). Restore path, if ever needed: Doppler keeps
     secret version history for the `soleur/prd` config, and the value is only a Better Stack
     heartbeat URL, which can be re-read from Better Stack. Never copy the value into a file or a
     PR. Update the NOTE in `zot-registry.tf` and the
     parity-test comment that calls the exclusion obsolete.
1B.5 **Git-data heartbeat pair.** Add `-target=betteruptime_heartbeat.git_data_prd` and
     `-target=doppler_secret.git_data_heartbeat_url_prd` to the per-merge list. Remove both from
     `OPERATOR_APPLIED_EXCLUSIONS` ONLY; `GIT_DATA_BIRTH_REFUSED` stays, since the birth route still
     cannot arm them (#6537). Add a parity assertion that the `apply` job targets both and
     `git_data_host_create` still does not. Fix the stale `TODO(#5274 PR C / follow-up)` comment in
     `git-data.tf`; the probe has shipped.
1B.6 **Proxy TLS gate.**
     - In `variables.tf`, add `variable "host_proxy_tls_enabled" { type = bool, default = false }`.
       Its description names the multi-host flip (#5274 Phase 3/6), and says the four `-target`s
       must be added together (key and cert as a pair).
     - In `proxy-tls.tf`, add `count = var.host_proxy_tls_enabled ? 1 : 0` to all four resources
       and index the references (`[0]`).
     - Keep the four `OPERATOR_APPLIED_EXCLUSIONS` entries. Add a short ADR-118 amendment, because
       its "PR B must" target list names the addresses that now carry `[0]`.
1B.7 **Config-digest gate.** In `inngest-config-digest.tf`, set
     `count = var.inngest_config_digest != "" ? 1 : 0`. Update the header's apply-ordering note: the
     admission regex has already landed in `cloud-init-inngest.yml` ("INNGEST_CONFIG_DIGEST is
     admitted AHEAD of its terraform apply"). Keep the resource in `OPERATOR_APPLIED_EXCLUSIONS`.
     Correct step 3 of `inngest-config-refresh.md`, which names a per-merge reconcile that does not
     target the resource. File the follow-up issue (Deferrals).
1B.8 **Ship mechanics for the destroy.** The branch commit that adds the ZOT `-target` carries a
     standalone `[ack-destroy]` line in its message. Merge with
     `gh pr merge --squash --body-file <file>`, whose text also holds that line.
     PR-B body, first line: "Merging this mutates production. The per-merge apply creates the
     git-data heartbeat and its URL secret, deletes `ZOT_HEARTBEAT_URL` from Doppler prd, and adopts
     the live deployment policy." Use `Ref #8754`.
1B.9 **Merge window.** Merge PR-B only while no run on `terraform-apply-web-platform-host` is queued
     or in progress. A newer pending run cancels a waiting one, and a cancelled PR-B apply leaves
     every later merge apply halting on the unacknowledged destroy.

### Phase 1 suites (each PR, on its own diff)

- `bash apps/web-platform/infra/inngest-host.test.sh`
- `bash tests/scripts/test-inngest-host-shape-gate.sh`
- `bash tests/scripts/test-inngest-host-replace-gate.sh`
- `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`
- `bun test plugins/soleur/test/terraform-target-parity.test.ts plugins/soleur/test/workflow-file-size.test.ts plugins/soleur/test/preflight-discoverability-test.test.ts`
- `bash plugins/soleur/test/c4-count-parity.test.sh`
- `python3 scripts/lint-encryption-posture.py`
- `terraform fmt -check` and `terraform validate` in `apps/web-platform/infra` (init
  `-backend=false`; PR-B validates with `host_proxy_tls_enabled` at its default and at `true`)
- `wc -c .github/workflows/apply-web-platform-infra.yml` ≤ 490,000

### Phase 2 — Verify each merge apply

2.1 Confirm the squash message with `git show -s --format=%B <sha>`. For PR-B it must contain a
    line exactly `[ack-destroy]`.
2.2 Watch each push run of `apply-web-platform-infra.yml` with a Monitor until-loop. A `cancelled`
    conclusion counts as failure. If PR-B's apply was cancelled or halted on the ack, recover with a
    one-line follow-up PR. That PR must touch a watched path (a comment line in
    `tests/scripts/lib/destroy-guard-filter-web-platform.jq`), and its commit message must carry
    `[ack-destroy]`. A `manual-rerun` dispatch cannot carry the ack.
    - 2A (PR-A) expected plan: the forget of `hcloud_firewall_attachment.inngest` plus the same two
      perpetual entries every merge shows. Nothing else.
    - 2B (PR-B) expected plan: `+ betteruptime_heartbeat.git_data_prd`,
      `+ doppler_secret.git_data_heartbeat_url_prd`, an import of `…_adopted`, a forget of the old
      policy address, and `- doppler_secret.zot_heartbeat_url_prd`. There must be **no**
      `cloudflare_bot_management` entry. Any other address halts verification and is classified.
2.3 After 2B, read the arm step's verdict for `git-data-prd`. ARMED and rolled-back-to-paused both
    leave no drift. Record a rollback on #6548.
2.4 After each merge, dispatch `scheduled-terraform-drift.yml` by hand. It is a read-only plan, and
    its Inngest cron trigger shares the #8833 outage. Post the residual on #8754 and re-check the
    issue's state.

### Phase 3 — Host replaces on their owning routes (each needs its own go-ahead)

Preconditions for every step:

- PR-A is merged.
- No run is queued or in progress on `terraform-apply-web-platform-host`, `deploy-inngest-restart`
  or `git-data-state`.
- The go-ahead names the exact commands.
- A `cancelled` conclusion counts as failure.

3.1 **Inngest replace (first; it closes the security gap).** One go-ahead covers the replace AND
    the resume, and it names who will approve the `inngest-cutover` environment. Coordinate with
    #8833 first: read its latest status and the most recent `SOLEUR_INNGEST_SERVER_PROBE` and
    `SOLEUR_INNGEST_BOOT_STAGE` rows. If an incident responder already owns a restoration replace,
    hand them this route instead of dispatching.
    - Dispatch: `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason='#8754: deliver v1.1.40 + firewall at creation'`
    - Gates: `environment: infra-privileged` (main-only); the `deploy-inngest-restart` mutex plus the
      workflow group; `inngest_host_replace_gate`, unchanged; and the #7228 inherited-`done`
      preflight.
    - Data: `hcloud_volume.inngest_redis` and `hcloud_volume.inngest_redis_luks` are preserved by
      omission. The gate aborts on any action on either volume, on any LUKS passphrase in the graph,
      and on any attachment action that is not a recreate. The route hard-deletes the old server, so
      AOF writes from about the last second (one fsync interval) are at risk. That is an existing
      property of the route, and today's scheduler outage bounds new writes.
    - Resume (measured `INNGEST_CUTOVER_FLIP=done`): `gh workflow run cutover-inngest.yml -f op=resume`,
      then the `inngest-cutover` environment approval. Watch the run to `success` with a Monitor
      loop.
    - Partial failure: Hetzner applies the firewall as part of the server create. It is an
      `apply_firewall` action returned with the create, per the provider's `opts.Firewalls`; this is
      read from source and docs, not measured.
      - If that action itself fails, the server can exist unfirewalled and tainted. So after ANY
        partial failure, run the port-22 probe and the `applied_to` read before anything else, then
        re-dispatch the same replace and run `op=resume` again.
      - AC-C1's probe is the measurement of the "before first boot" claim on the real host.
    - Last-resort scheduler restore: if the dedicated host cannot be brought to serving, dispatch
      `gh workflow run cutover-inngest.yml --field op=rollback` to bring the web scheduler back. That
      is the path `inngest-server.md` names. It is a separate prod write and needs its own go-ahead.
    - Before dispatching, record the latest `SOLEUR_INNGEST_SERVER_PROBE` row and any queue or
      reminder count it carries, so that AC-C3 compares before and after on a measured value.
    - Verify with AC-C1 to AC-C3.
3.2 **Git-data (#5274 G2, then G3).** This runs before PR-B merges, so the newly armed
    `soleur-git-data-prd` heartbeat never watches a replace window.
    - G2: `gh workflow run apply-web-platform-infra.yml -f apply_target=git-data-host-replace -f plan_only=true -f reason='#5274 G2 / #8754'`.
      It must end `success`, with the apply skipped and `git_data_host_replace_gate` PASS.
    - G3: the same command without `plan_only`. Its gates are `environment: infra-privileged`, the
      `git-data-state` mutex, the rung-2 rehearsal gate (RELEASED by PR #8751), the root-key arm
      gate, the SSH authorization map and the boot-signal poll.
    - Data: `hcloud_volume.git_data`, `hcloud_volume.git_data_luks` and the LUKS passphrase are
      preserved by omission. The gate requires both attachments to be recreated and `firewall_ok`.
      The store is dark (`GIT_DATA_STORE_ENABLED` is absent from prd), so it serves no user data
      during the window.
    - Follower: `git-data-pin-redeploy.yml` forces one web release to load the rotated
      `GIT_DATA_SSH_HOST_KEY`. Watch it to `success` (`git_data_pin=present`).
    - Runbook GO criteria (`git-data-luks-cutover-5274.md`, the G1 to G4 table):
      - G3 is capped at **one attempt**. On failure, read the run first and never dispatch a second
        replace to recover.
      - The replace boot must emit `boot_complete` with `plaintext_journal=dirty plaintext_empty=yes fence_on_mapper=yes erasure_probe=yes`.
        A production `plaintext_journal=clean` is NO-GO and an incident.
      - Zero Sentry `erasure_outcome` events in the window.
      - G4, the strict `git-data-cutover.yml` dry run, reads `role=git-data-auth verdict=ok`.
      - The Art. 12(3) sweep of refused erasures (deadline **2026-10-24**) is recorded on #5914.
3.3 Dispatch `scheduled-terraform-drift.yml` and expect `No drift detected in web-platform`.
    Re-check #8754's state, comment the run URL on it, and close it.

**Timing.** Run 3.1 as soon as PR-A's apply is verified. PR-A only forgets the attachment, so the
live host keeps a public sshd until 3.1 runs. While #8833 holds the host dark, a replace costs almost
nothing.

**If the 3.1 go-ahead is not given in-session:** file a dedicated issue labelled
`priority/p1-high` and `type/security`, titled "inngest host has no Hetzner firewall attached". Link
it to #8833 and #8754. It must name the owner (the operator), a date (the next inngest replace or
2026-09-28, whichever is sooner), the exact command pair, and the measured exposure (sshd only). It must also record the one interim
option that needs no replace: a one-shot Hetzner `apply_to_resources` for firewall 11269127 against
the live server. With `firewall_ids` declared and Optional+Computed, Terraform would then plan no
change. That option needs a new gated dispatch path this plan does not build, so it is recorded
there as an operator decision and not executed here.

**If the 3.2 go-ahead is not given:** leave G2/G3 on #5274, where it already lives, and post the
expected heartbeat absence there.

In both cases #8754 stays open with a status comment that names the residual (the not-yet-run
subset of #8 and #9), its owners and the commands.

## Files to Edit

PR-A:

- `apps/web-platform/infra/inngest-host.tf`
- `apps/web-platform/infra/inngest-host.test.sh`
- `.github/workflows/apply-web-platform-infra.yml` (`inngest_host` target removed; per-merge target added)
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `plugins/soleur/test/preflight-discoverability-test.test.ts`
- `tests/scripts/lib/inngest-host-replace-gate.sh` (comment only)
- `tests/scripts/lib/registry-host-replace-gate.sh` (comment only)
- `tests/scripts/lib/inngest-host-shape-gate.sh` (allow-set and `firewall_touched` class drop the attachment)
- `tests/scripts/test-inngest-host-shape-gate.sh` (derived target count 18→17; two red rows re-pointed)
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` (amendment)

PR-B:

- `apps/web-platform/infra/bot-management.tf`
- `apps/web-platform/infra/web-host-birth-environment.tf`
- `apps/web-platform/infra/zot-registry.tf` (comment)
- `apps/web-platform/infra/git-data.tf` (comment only)
- `apps/web-platform/infra/proxy-tls.tf`
- `apps/web-platform/infra/variables.tf`
- `apps/web-platform/infra/inngest-config-digest.tf`
- `.github/workflows/apply-web-platform-infra.yml` (per-merge `-target` lines)
- `.github/workflows/infra-validation.yml` (job `plan`: `actions: read`)
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (stale comment only)
- `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md`
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
- `knowledge-base/engineering/operations/runbooks/vector-redeliver.md`
- `knowledge-base/engineering/architecture/decisions/ADR-118-proxy-cert-sans-track-the-cluster-roster.md` (amendment)

## Files to Create

- none

## Open Code-Review Overlap

None. All 81 open `code-review` issues were checked against every path above; no issue body names
any of them.

## Non-Goals

- Backlog items 2 and 3. This change does not touch `doppler_service_token.ghcr_minter`,
  `doppler_secret.ghcr_read_*`, `ghcr-minter-doppler-token.tf`, `ghcr-read-credential.tf` or
  `cron-egress-allowlist*.txt`.
- Moving git-data, the registry or web to `firewall_ids`. They re-attach in their replace plans
  today, so their boot window is a follow-up.
- Changing the drift workflow or `apply-deploy-pipeline-fix.yml`'s drift auto-close.
- Any local `terraform apply` or `plan` against prod state, SSH, host edit or dashboard edit.

## Deferrals (each gets a tracking issue in the work phase)

- **The inngest config-digest promotion has no apply route.** Re-evaluate when
  `SOLEUR_INFRA_PULL_APPLIED` first appears (the #6178 channel goes live).
- **`apply-deploy-pipeline-fix.yml` closes drift issues it did not resolve.** Gate the close on a
  clean full-root drift plan.
- **The "operator-applied exclusion" class recurs silently** (CTO devex). Candidates: turn
  `OPERATOR_APPLIED_EXCLUSIONS` into an address→route map with a parity assertion, and raise a drift
  age alarm for addresses drifting 14+ days. Re-evaluate at the next drift triage.
- **Other hosts' pre-boot firewall window.** Candidate: move git-data and registry to
  `firewall_ids`. Re-evaluate at the next replace-route change.
- **Remove the one-shot adoption scaffolding** after PR-B's apply is verified. That covers the
  `import` block, the policy `removed` block, the old policy `-target`, the attachment `-target`, and
  the `actions: read` grant on the infra-validation plan job (it is only needed while an `import`
  block exists).
- **Proxy-TLS enable step:** recorded on #5274 as a comment, not a new issue.

## Guard Contract

### Guard 1 — the inngest server is born with the deny-all firewall

**Property.** Every `hcloud_server.inngest` that Terraform creates, by birth or by replace,
carries `hcloud_firewall.inngest` in `firewall_ids`. No `hcloud_firewall_attachment` binds that
firewall anywhere in the root.

**Assembly.** The chokepoint is the one `resource "hcloud_server" "inngest"` block in
`apps/web-platform/infra/inngest-host.tf`. Both routes that create the server (the `inngest_host`
and `inngest_host_replace` jobs) create it from that block, so one static check over the block
covers every path. The second half of the property ranges over every `*.tf` file in
`apps/web-platform/infra/`. The check lives in `apps/web-platform/infra/inngest-host.test.sh`, next
to check 3 (the zero-inbound-rules assertion).

**Mutation matrix** (each edit must drive the suite RED):

| # | Mutation | Expected |
|---|---|---|
| M1 | Delete the `firewall_ids` line from the server block | RED |
| M2 | Point `firewall_ids` at another firewall (`[hcloud_firewall.registry.id]`) | RED |
| M3 | Re-add `resource "hcloud_firewall_attachment" "inngest"` in any `*.tf` of the root | RED |
| M4 | Second member: add a second firewall to the list after a compliant first (`[hcloud_firewall.inngest.id, hcloud_firewall.web.id]`) | RED (the list must be exactly the inngest firewall) |
| M5 | Own dispatch: rename the server block so the extractor finds nothing | RED ("server block not found"), never a vacuous pass |
| M6 | Add an attachment under a different name whose `firewall_id = hcloud_firewall.inngest.id` | RED (the property quantifies over every attachment binding that firewall, not one resource name) |
| M7 | Add an `apply_to` block to `resource "hcloud_firewall" "inngest"` | RED (a second binding channel for the same firewall) |

**Harness rows.** H1 is a must-PASS row that differs from the canonical form: `firewall_ids` is
written with extra whitespace and a trailing comment (`firewall_ids = [ hcloud_firewall.inngest.id ] # deny-all`),
and it must still PASS. H2 swaps in a synthetic `inngest-host.tf` fixture where the block is
compliant but split across lines. It must PASS, which proves the extractor is not keyed on one line
layout.

**Anchor.** The static check and the `.tf` land in one commit, so the check proves consistency, not
integrity. Two checks sit outside the commit. First, the live Hetzner read after 3.1: firewall
11269127 `applied_to` equals the new server id. Second, the follow-up drift plan shows no
firewall-related change.

## Observability

```yaml
liveness_signal:
  what: scheduled-terraform-drift verdict for apps/web-platform/infra (exit 0 = no drift) plus the Hetzner firewall applied_to set for soleur-inngest
  cadence: twice daily (Inngest cron-terraform-drift dispatch, 06:00 and 18:00 UTC) and on demand via workflow_dispatch; while #8833 holds the Inngest scheduler down it is dispatched by hand
  alert_target: infra-drift GitHub issue (opened/commented by the drift workflow) + ops email from notify-apply-failure on a failed or cancelled apply job
  configured_in: .github/workflows/scheduled-terraform-drift.yml; .github/workflows/apply-web-platform-infra.yml
error_reporting:
  destination: layer 6 (GitHub Actions run conclusion and ::error::/::warning:: annotations); drift issue comments; layer 3 (Vector to Better Stack) for on-host inngest lines
  fail_loud: the inngest-host.test.sh firewall_ids check fails the infra-validation job on any regression before merge
failure_modes:
  - mode: the inngest server loses its firewall binding in config
    detection: layer 6 (infra-validation run log, Guard 1 RED); layer 6 (drift plan shows a firewall_ids change)
    alert_route: failed PR check; infra-drift issue
  - mode: the deployment-policy import does not fire (phantom persists)
    detection: layer 6 (infra-validation plan job run log and its PR comment, AC-B6); layer 6 (Phase 2.2 greps the push-apply log for a create of web_platform_infra_apply_main_adopted)
    alert_route: PR review blocks merge; Phase 2.2 halts
  - mode: the PR-B apply is cancelled or halted, leaving the zot destroy unacknowledged
    detection: layer 6 (push-apply run conclusion). A run cancelled while still queued starts no job, so notify-apply-failure does not email; the Phase 2.2 Monitor watch on that exact run id is the synchronous signal
    alert_route: Monitor event in the pipeline session; later merge applies halt on destroy_count (layer 6, notify-apply-failure email)
  - mode: the git-data heartbeat is armed and red during a later G3 window
    detection: layer 6 (the arm step verdict in the PR-B apply run log); Better Stack heartbeat absence alert
    alert_route: Better Stack email (pre-announced on #5274)
  - mode: the inngest scheduler is stranded by the inherited done flag after the replace
    detection: layer 6 (the #7228 preflight ::warning:: in the replace run log); layer 3 (Vector ships the flip-guard BLOCK lines to Better Stack); scheduled-inngest-health (GitHub cron every 15 minutes, off-host)
    alert_route: the ci/inngest-dedicated-host and ci/inngest-no-live-scheduler watchdog issues (#8833/#8834 class)
logs:
  where: GitHub Actions run logs (apply-web-platform-infra, infra-validation, scheduled-terraform-drift, git-data-pin-redeploy, cutover-inngest); Better Stack Logs for SOLEUR_INNGEST_SERVER_PROBE and the flip-guard lines
  retention: GitHub Actions default 90 days; Better Stack per plan
discoverability_test:
  command: curl -sf -H "Authorization: Bearer ${HCLOUD_TOKEN}" "https://api.hetzner.cloud/v1/firewalls?name=soleur-inngest" | jq -r '"applied_to=" + (.firewalls[0].applied_to | length | tostring) + " server_ids=" + ([.firewalls[0].applied_to[].server.id | tostring] | join(","))'
  expected_output: "applied_to=1"
  credentials_required: "Hetzner API token (Doppler soleur/prd_terraform HCLOUD_TOKEN, GET only). Hetzner exposes firewall attachment state only through the authenticated API. The unauthenticated alternative, a TCP connect to the host's port 22, needs the public IP, which changes on every replace, and a bash /dev/tcp redirect that preflight Check 10 rejects as a shell-active token"
```

## Infrastructure (IaC)

### Terraform changes

All changes are in `apps/web-platform/infra/`.

- `inngest-host.tf`: add `firewall_ids` on `hcloud_server.inngest`, and a `removed{destroy=false}`
  for the attachment.
- `bot-management.tf`: two declared attributes.
- `web-host-birth-environment.tf`: rename the resource, then add `import` and
  `removed{destroy=false}`.
- `proxy-tls.tf` and `variables.tf`: add `host_proxy_tls_enabled` (default `false`) and a count
  gate.
- `inngest-config-digest.tf`: a count gate that holds until a digest is promoted.

No provider or version changes. No new sensitive variable.

### Apply path

- **(a) The per-merge `apply` job** covers the attachment forget, #1, #2, #3 and #4. All of these
  are host-independent and on the `-target` allow-list.
- **(c) The gated `-replace` dispatches** cover #8 and #9 (`inngest-host-replace`,
  `git-data-host-replace`). #8 carries the `firewall_ids` binding.
- **#5 and #6** converge by count-gating, with no apply.

Blast radius: the per-merge apply touches only Better Stack, Doppler `prd`, GitHub environment state
and the Terraform state entry of the attachment. The replaces are the only steps that touch a host,
and they inherit their routes' gates. Only `apply-web-platform-infra.yml` fires on the edited paths.

### Distinctness / drift safeguards

`[ack-destroy]` covers the one destroy (the ZOT secret). The forgets (the attachment and the phantom
policy) are excluded from `resource_deletes` and carry no `before.rules`. No `ignore_changes` is
added. Tfstate gains the heartbeat URL, a masked secret of the same class as every other heartbeat
URL already in state.

### Vendor-tier reality check

The Cloudflare zone is **Pro** (measured `plan.legacy_id=pro`), so SBFM attributes are valid inputs.
Hetzner `firewall_ids` has no tier dependency.

## Downtime & Cutover

These are the operations in this plan that can take something offline, and the zero-downtime
options each one was checked against.

| Operation | Surface affected | Zero-downtime path evaluated | Decision |
|---|---|---|---|
| PR-A and PR-B merge applies | None. They touch Better Stack, Doppler `prd`, GitHub environment state and Terraform state entries. No host is targeted. | Not needed | No downtime |
| 3.1 `inngest-host-replace` (`-/+ hcloud_server.inngest`) | The dedicated Inngest scheduler (crons, reminders) | **Blue-green was rejected.** ADR-100 makes the scheduler a singleton, so two live schedulers would double-fire every cron and reminder. That is the #7228 hazard `inngest-server-flip-guard.sh` exists to prevent. **Re-pooling the web scheduler during the window was rejected.** It is the cutover FSM's own `op=rollback` path on `cutover-inngest.yml`, which is a separately authorized prod write with flip and FLUSH semantics, not a shim for a routine replace. **A state-only re-address does not apply,** because the change IS user_data (a new bootstrap image), and user_data is the host's only delivery channel. | Residual downtime accepted, bounded, and gated (below) |
| 3.2 `git-data-host-replace` | The git-data store. It is dark: `GIT_DATA_STORE_ENABLED` is absent from prd, so no user traffic reaches it. There is also one forced web release from `git-data-pin-redeploy.yml`. | The replace window has no user-facing effect. The forced web release uses the normal release deploy path, the same as every merge. | No user-facing downtime beyond a normal release |

**3.1 downtime bound and justification.**

- **Today** the dedicated scheduler is not serving (#8833 and #8834 are open), so the replace takes
  nothing offline that is currently up. It is also the delivery route for the fixed image.
- **If #8833 is resolved before 3.1 runs**, the window is:
  - the replace job, under a 20-minute `timeout-minutes`;
  - the boot to `inngest-server` refusing on the inherited `done`;
  - `op=resume` plus the `inngest-cutover` approval.

  The target is under 30 minutes end to end. Reminders due in the window are delivered late, not
  dropped, because the AOF survives on the preserved volumes (AC-C3).
- **Per-stage verification and rollback:**
  - The replace run's gate line (`redis_volume_destroyed=0 luks_volume_destroyed=0`) is checked
    before the resume.
  - `op=resume` is watched to `success`.
  - `scheduled-inngest-health` must go green.
  - Rollback path: the replace does not touch either volume, so a failed boot is re-dispatched on the
    same route. A bad image is reverted by the next ADR-232 pin bump PR plus another replace.
- **Operator sign-off** is the 3.1 go-ahead, which names the window and the approver in advance.
  Prefer a low-traffic hour for reminders (per the health workflow's recent run history).

## Encryption Posture

This plan adds no persistent store, no cross-component connection and no new resource type, so the
`lint-encryption-posture.py` type partition does not change (the Phase 1 suites cover the run). The
two host replaces re-attach existing volumes without changing their posture:

- `hcloud_volume.git_data_luks` and `hcloud_volume.inngest_redis_luks` stay LUKS, with unchanged
  device bindings.
- The retained plaintext siblings (`hcloud_volume.git_data`, `hcloud_volume.inngest_redis`) keep
  the posture already recorded in `scripts/encryption-posture-ledger.json`.
- The proxy-TLS connection is gated off until the flip. Its `rejectUnauthorized:true` pinning in
  `apps/web-platform/server/session-proxy.ts` is untouched.

## Architecture Decision (ADR/C4)

### ADR

- **Amend ADR-100** (inngest dedicated host) in PR-A. The dated amendment records three things.
  First, the inngest firewall is bound through `hcloud_server.firewall_ids`, so it is applied at
  create, before first boot (ADR-145's recorded difference), and the attachment is forgotten.
  Second, it amends the "Apply-path constraint (recorded #6197)" bullet: the #6197 premise
  ("server_ids does not change; the next full/drift apply reconciles it") had no actor, and host
  167310350 was unfirewalled from birth. Third, the alternatives table adds two rejected options:
  (a) targeting the attachment in the replace job plus a gate counter, rejected because it still
  leaves a boot window and a partial-failure dead end; and (b) `label_selectors`, rejected because
  it would need a dedicated label on a shared label scheme.
- **Amend ADR-118** (proxy cert SANs) in PR-B. The material is instantiated only when
  `host_proxy_tls_enabled` is set at the multi-host flip. The "PR B must" target list now reads
  `…[0]`, and the key and cert are targeted together. SAN derivation is unchanged.

### C4 views

All three model files were read (`model.c4`, `views.c4`, `spec.c4`) and checked against this plan:

- **External systems:** Cloudflare, Doppler, Better Stack and GitHub are all modeled.
- **Containers:** Inngest Server, Inngest Redis, Shared git-data and Session Router are all modeled.
- **Actors, stores and relationships:** the plan adds none.

The Session Router description ("remote ⇒ proxy over one-way-TLS private net") states the design,
which does not change. Firewall bindings are below C4 granularity, so there is no C4 edit.
`plugins/soleur/test/c4-count-parity.test.sh` is run to confirm, since heartbeat and monitor
declaration counts are unchanged.

### Sequencing

ADR-100 lands in PR-A, and ADR-118 in PR-B.

## User-Brand Impact

**If this lands broken, the user experiences:**

- **Reminders and scheduled agent runs that never fire.** An inngest replace can strand the
  scheduler or lose the Redis AOF queue.
- **A late burst after the outage.** When the scheduler resumes (after `op=resume` and the
  environment approval), every reminder already persisted in the AOF whose fire time passed during
  the outage is delivered late, in Inngest's drain order.
  - The replace hard-deletes the old server, so AOF writes inside the last fsync interval (about
    1 s) can be lost. AC-C3's before/after record is how that gets measured.
  - Cron schedules are not expected to backfill missed ticks. Only already-enqueued work drains. The
    work phase confirms this against the pinned Inngest version before 3.1, because a burst of
    overdue scheduled agent runs would spend BYOK users' credits and hit their per-user concurrency
    caps.
  - The window's length depends on a human approval click, so 3.1's go-ahead names the approver in
    advance and the resume is watched to `success`.
- **Events sent while the host is unreachable fail.** `sendInngestWithRetry`
  (`apps/web-platform/server/inngest/send-with-retry.ts`) retries a transient failure twice with
  500 ms and 1 s backoff, about 1.5 s in total. That is far shorter than a replace. Its callers
  (`server/index.ts`, `server/routines/run-routine.ts`) then see the failure. Before 3.1, the work
  phase reads the post-retry branch of both callers and records the user-visible effect (an error
  shown, or a silent drop mirrored to Sentry) in the 3.1 go-ahead request. This class is already live
  today while #8833 holds the host down.
- **A brief reconnect for open chats.** `git-data-pin-redeploy.yml` forces one web release, and it
  deploys through the normal release path, the same container swap as every merge to main. 3.2 runs
  in the same low-traffic window as 3.1.
- **AI answer engines blocked from soleur.ai** if a wrong `sbfm_*` value lands.
- **A web host that cannot reach its git-data store** after the host-key rotation. The store is
  dark today, so this stays latent.

**If this leaks, the user's data is exposed via:** the inngest host's public interface.
`GIT_DATA_HEARTBEAT_URL` also joins the web container's env, because `ci-deploy.sh` downloads the
whole prd config. A leaked URL would let someone send fake beats that mask a git-data outage. That is
the same class as every heartbeat URL already in prd (`INNGEST_HEARTBEAT_URL` and the per-host
probe URLs), and it is accepted on the same basis: the URL grants no read and no write of user data. As measured
on 2026-09-25, only sshd answers there with no Hetzner firewall. Sshd is key-only
(`PasswordAuthentication no`), and Redis and the inngest ports (6379, 8288, 8289, 9000) are
filtered. The host holds the Redis AOF with queued user event payloads. This plan closes the
exposure and a regression would reopen it. If any data port ever answers publicly, the finding goes
to the CLO (Phase 0.4).

**Brand-survival threshold:** single-user incident. The Phase-3 replaces act on the only copy of
armed reminders (the inngest AOF). Stores are preserved by omission and gate-checked. CPO sign-off
was approved with conditions, all folded in: the failure modes above, the Phase 0.4 port
measurement, AC-C3, and the withheld-path P1 issue.
`soleur:engineering:review:user-impact-reviewer` runs at review.

## Risks and Sharp Edges

- **Byte budget.** There was 1,418 B of headroom before the change. The net effect is about +250 B
  (PR-A about +0, PR-B about +250). Measure after every edit.
- **Squash body.** Squash bodies are built from commit messages, so use both the commit line and
  `--body-file` (1B.8).
- **Pending-run cancellation.** The shared group keeps one pending run, so merge into a quiet group
  (1B.9) and treat `cancelled` as a failure.
- **Phantom state.** A merge apply between Phase 0 and the PR-B merge re-records the phantom. The
  `removed{}` forget handles either state.
- **Auto-close.** `apply-deploy-pipeline-fix.yml` may close #8754 early. Re-check it at 0.1, 2.4
  and 3.3, and reopen it if the residual is not clean.
- **Inherited `done`.** The inngest replace leaves `inngest-server` refusing to start until
  `op=resume` completes and the approval is clicked.
- **`firewall_ids` versus the attachment.** Declaring both on one firewall is the documented fight
  that `ignore_remote_firewall_ids` exists for. The attachment is removed in the same change
  (Guard 1 M3).
- **Empty sections.** A plan whose `## User-Brand Impact` section is empty, contains only
  placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6.

## Acceptance Criteria

### Pre-merge — PR-A

- [x] **AC-A1** `bash apps/web-platform/infra/inngest-host.test.sh` passes with the Guard 1 rows.
      Before the `.tf` edit, the canonical assertion was observed RED (today there is no
      `firewall_ids` and the attachment exists). Each of M1 to M5 was observed RED against the
      edited tree. The TDD log goes in the PR body.
- [x] **AC-A2** `bun test plugins/soleur/test/terraform-target-parity.test.ts plugins/soleur/test/workflow-file-size.test.ts plugins/soleur/test/preflight-discoverability-test.test.ts`
      and `bash tests/scripts/test-inngest-host-shape-gate.sh` pass.
- [x] **AC-A3** `terraform validate` (init `-backend=false`) passes in `apps/web-platform/infra`.
- [ ] **AC-A4** The PR's own `infra-validation` plan comment for `apps/web-platform/infra` shows
      `hcloud_server.inngest` planned with `firewall_ids` containing the inngest firewall, and
      `hcloud_firewall_attachment.inngest` as a forget.

### Pre-merge — PR-B

- [ ] **AC-B1** Re-run the ZOT audit at work time against the pre-change tree, so PR-B's own new
      `-target` line cannot match. The command
      `git grep -nI 'ZOT_HEARTBEAT_URL' origin/main -- apps plugins scripts tests .github infra` must
      return only comment lines (case-sensitive: this matches the environment variable name).
      The Doppler raw-value scan must find no reference; it covers every `prd` branch config
      (`doppler configs -p soleur` lists them), since branch configs inherit from `prd`. Record both
      results in the PR body. Deleting the Doppler copy does not revoke the Better Stack ping URL
      itself, which grants only a heartbeat ping to whichever heartbeat it names; record that
      heartbeat's name in the PR body.
- [ ] **AC-B2** `terraform fmt -check` and `terraform validate` pass with `host_proxy_tls_enabled`
      unset and with it set to `true`. `python3 scripts/lint-encryption-posture.py` exits 0.
- [ ] **AC-B3** `wc -c .github/workflows/apply-web-platform-infra.yml` ≤ 490000.
- [ ] **AC-B4** `git log --format=%B origin/main..HEAD | grep -cx '\[ack-destroy\]'` ≥ 1, and the
      merge command's `--body-file` contains a line exactly `[ack-destroy]`.
- [ ] **AC-B5** No path matching `ghcr-minter-doppler-token.tf`, `ghcr-read-credential.tf` or
      `cron-egress-allowlist*` appears in `git diff --name-only origin/main...HEAD`. This applies to
      both PRs.
- [ ] **AC-B6** The PR's own `infra-validation` plan comment, re-run on the final head immediately
      before merging (the merge apply refreshes, while this plan runs `-refresh=false`), for `apps/web-platform/infra` shows:
      `…web_platform_infra_apply_main_adopted` as an import (not a create), the old policy address
      as a forget, and `doppler_secret.zot_heartbeat_url_prd` as a destroy. It shows no action on the
      four proxy-TLS addresses or on `doppler_secret.inngest_config_digest`. This is required before
      merge.

### Post-merge — automated by the pipeline

- [ ] **AC-M1** PR-A's merge apply concludes `success`. Its plan holds the attachment forget plus
      the two standing perpetual entries, and nothing else.
- [ ] **AC-M2** PR-B's merge apply concludes `success` (not `cancelled`). Its plan lists exactly the
      2B addresses, with no `cloudflare_bot_management` change. Afterwards:
      - `ZOT_HEARTBEAT_URL` is absent from `doppler secrets -p soleur -c prd --only-names`;
      - `GIT_DATA_HEARTBEAT_URL` is present;
      - the deployment-branch-policies read still lists exactly one policy, `main`.
- [ ] **AC-M3** The drift run after each merge shows a residual that equals the not-yet-executed
      subset of {#8, #9}. It is commented on #8754.

### Post-merge — behind per-command go-ahead

- [ ] **AC-C1** After 3.1, `curl … /v1/firewalls?name=soleur-inngest` prints `applied_to=1`, and
      the id equals the new `hcloud_server.inngest` id. A TCP connect to port 22 on the new public IP
      fails.
- [ ] **AC-C2** After 3.1, `cutover-inngest.yml op=resume` concludes `success`, and
      `scheduled-inngest-health` concludes `success`. A fresh `SOLEUR_INNGEST_SERVER_PROBE` row from
      the new host (Better Stack query via `scripts/betterstack-query.sh`) shows it serving. Both
      checks stand even if the #8833/#8834 watchdog lags; those issues then close on their own
      watchdog.
- [ ] **AC-C3** Queue continuity. The replace run's gate line reads `redis_volume_destroyed=0` and
      `luks_volume_destroyed=0`. The first post-resume `SOLEUR_INNGEST_SERVER_PROBE` row shows the
      server serving from the pre-existing store (the resume completes to `done` with no
      re-FLUSHALL, per `inngest-server.md`). If an off-host queue-depth field is found before 3.1,
      record the counts before and after.
- [ ] **AC-C4** After 3.2, `git-data-pin-redeploy.yml` concludes `success`.
- [ ] **AC-C5** `scheduled-terraform-drift.yml` reports `No drift detected in web-platform`, and
      #8754 is closed with that run URL. If a go-ahead is withheld, AC-C1 to AC-C5 are replaced by
      the withheld-path deliverables in Phase 3, and #8754 stays open.

## Domain Review

**Domains relevant:** engineering, product

### Engineering

**Status:** reviewed

**Assessment:**

- **CTO (first pass):** approve with changes. The firewall fix is split into its own PR and merges
  first. 3.1 reads #8833's state, names the approver, and watches `op=resume`. Redis public
  reachability was measured closed. The heartbeat now follows G3.
- **Terraform-architect:** all seven semantic claims verified TRUE. One new risk was folded in: the
  PR plan job's token cannot read deployment policies, so 1B.3 and AC-B6 cover it.
- **Plan-review panel:** DHH, architecture-strategist and code-simplicity converged on binding the
  firewall with `firewall_ids`. This replaced plan v2's target, gate counter and recovery route, and
  it closes the boot window. Architecture-strategist also caught that `GIT_DATA_BIRTH_REFUSED` must
  not lose the heartbeat pair, and it fixed the phase order into one fixed execution order.
- **CTO devex:** the class-recurrence forcing function is deferred and recorded in
  `decision-challenges.md`.

### Product/UX Gate

**Tier:** none (no user-facing surface)

**Decision:** reviewed. The CPO signed off, as required at the single-user-incident threshold.

**Agents invoked:** soleur:product:cpo, soleur:product:spec-flow-analyzer

**Skipped specialists:** none

**Pencil available:** N/A (no UI surface)

#### Findings

- **CPO:** approved with conditions. All four are folded in.
- **Spec-flow, two passes:** the first pass found nine gaps, all resolved. The second pass found
  three new ones, also resolved:
  - the fallback that contradicted AC-B6 was removed;
  - the ack-recovery PR now names a watched path;
  - the phase order is now a single fixed order, and AC-M3 depends on that order.

## Test Scenarios

**Guard 1 (`inngest-host.test.sh`)**

| Input | Expected |
|---|---|
| Canonical `firewall_ids = [hcloud_firewall.inngest.id]` | PASS |
| Canonical form with extra whitespace and a trailing comment | PASS |
| Multi-line layout | PASS |
| Line missing | RED |
| `firewall_ids` pointing at a different firewall | RED |
| Two firewalls in the list | RED |
| A re-added attachment resource | RED |
| An attachment under another name that binds `hcloud_firewall.inngest` | RED |
| An `apply_to` block on `hcloud_firewall.inngest` | RED |
| Server block renamed | RED, and never a vacuous pass |

**Parity**

- The per-merge job targets `hcloud_firewall_attachment.inngest` (the `removed` block) and the
  heartbeat pair.
- `inngest_host` no longer targets the attachment.
- `git_data_host_create` still does not target the heartbeat pair.

**Terraform `validate`**

- Run with `host_proxy_tls_enabled=false` (the default) and with `true`.
- Run with `inngest_config_digest=""` and with a synthetic digest.
