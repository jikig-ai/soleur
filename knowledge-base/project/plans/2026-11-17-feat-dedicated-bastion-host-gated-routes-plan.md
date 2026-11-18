---
title: "infra: web-1 retirement step 2 — dedicated bastion host with gated create/replace routes (ADR-327)"
date: 2026-11-17
slug: feat-dedicated-bastion-host-gated-routes
branch: feat-12866-bastion-host
issue: 12866
type: feat
priority: p3-low
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# infra: dedicated bastion host with gated create and replace routes

## Overview

Step 2 of the seven-step web-1 retirement sequence tracked on epic #9421. This step adds a
dedicated bastion server to the web-platform Terraform root, with its own small cloud-init, a host
key generated in Terraform, no public inbound, an egress allowlist whose every row names its
consumer, and gated create and replace routes, and it records the new recurring cost. Moving roles onto the bastion is step 3 (#12867), not
this step. The design was ruled on by the CTO on 2026-11-10 and is recorded in ADR-327.

**This plan is PR 2a of two** (CTO ruling F7, 2026-11-17). It delivers the host, its birth route, its
egress policy and its readiness signal. PR 2b delivers the replace route, the Better Stack heartbeat, and proves it
with a `plan_only` run against the real born bastion; it is filed as #12879 and must merge
before step 3. The git-data allowlist item is descoped, because git-data has no such allowlist (see
Research Reconciliation).

## Research Reconciliation — Spec vs. Codebase

| Spec claim (#12866 / plan of record) | Reality on `origin/main` | Plan response |
|---|---|---|
| "gated create and replace routes" named `bastion-host-create` / `bastion-host-replace` | Host routes are `apply_target` jobs in `apply-web-platform-infra.yml`, not workflow files | New `apply_target` value `bastion-host-create` and a `bastion_host_create` job (2a); `bastion-host-replace` in 2b |
| "the git-data SSH source allowlist entry for the bastion" | No such allowlist exists; admission is private-network membership plus per-key forced commands | Descoped (CTO F1). ADR-327 corrected and the residual named; #12880 tracks a real nftables source allowlist on git-data, to ride the next git-data replace |
| "egress only to Cloudflare, apt, Sentry, Doppler; nftables allowlist to git-data:22, each web host's :9000 and the registry" | None of those consumers runs on the bastion in step 2 | Rows only for consumers present now (CTO F2); steps 3 and 4 add rows with the consumers they move |
| "Host key generated in Terraform … survives a replace" | The one precedent (git-data) rotates its key on replace | Same `tls_private_key` + `ssh_keys` pattern, never rotated (CTO F5); the 2b replace gate refuses any action on the key |
| "bastion about EUR 4-5/month" (approved 2026-11-10) | Live catalog: cx23 EUR 5.49 + primary IPv4 EUR 0.50 = EUR 5.99/month in hel1 | Ledger records EUR 5.99; the owner's typed go on the birth names the figure (Operator Holds) |
| "Its replace route exists and is tested" | A replace gate is pinned to a live physical id; nothing exists to pin before birth | Moved to 2b, which tests it against the born host (CTO F7) |

## CTO Rulings (2026-11-17, binding)

Ruled by CTO agent, 2026-11-17, on eight forks this plan's research opened.

- **F1** Descope the git-data allowlist; correct ADR-327; name the residual (any member of the private
  network can reach git-data:22); file a tracking issue for an nftables source allowlist on git-data.
- **F2** Egress rows only for consumers on the bastion in step 2: DNS, NTP, the metadata endpoint
  (root only), the apt mirror and Sentry (the boot marker); the heartbeat endpoint moved to 2b with the
  heartbeat (F3 re-rule). The chain drops by
  default. Every accept row's comment names a unit or file present on the bastion, and a test rejects
  any uncited row and any accept-all fallback. Follow `cron-egress-nftables.sh`.
- **F3** At birth, cloud-init sends a Sentry `fresh_boot_ready` event after the apt and settle steps
  pass, and `fresh-host-boot-trail.sh` reads it with `host_name=soleur-bastion`. Generalise the
  reader's host input instead of copying the script. Add a Better Stack heartbeat the host pings itself.
  **Re-ruled by CTO agent, 2026-11-17:** the heartbeat, its timer, manifest row, allowlist entry and
  ping proof move to 2b (#12879), because `heartbeat-reprovision-parity.test.ts` requires a
  `dedicated-host-boot` heartbeat to have a replace path, which only 2b brings. Dissent recorded: 2a
  has no signal after birth.
  A skipped read (unbound token) counts as not ready on the bastion route.
- **F4** cx23 in `var.location` (hel1) behind `stock-preflight-gate.sh`; an x86 architecture
  precondition as `git-data.tf` has; private IP `10.0.1.70`. If stock fails, do not switch type:
  cpx12 (EUR 9.49) is a money decision for the owner.
- **F5** Copy git-data's `tls_private_key` + `ssh_keys` pattern; no rotation on replace; publish the
  pin to Doppler in step 3 with its first dialer; copy the metadata-endpoint drop for non-root UIDs now.
  The ADR names the residual (a leaked copy stays valid until a deliberate rotation) and the runbook
  names the rotation act.
- **F6** `bastion-host-create` birth gate: creates exactly the bastion's resources, zero updates or
  destroys elsewhere; the shared `terraform-apply-web-platform-host` concurrency group;
  `OPERATOR_APPLIED_EXCLUSIONS`; the existing `host_creates` halt; the stock gate. The 2b replace gate:
  pinned to the live physical id, delete-and-create of the server and its attachments only, and a
  create-only recovery arm only when state has no server and the live API shows no `soleur-bastion`.
- **F7** Split: 2a (this plan) and 2b (replace route). 2b must merge before step 3; #12867 is marked
  blocked by 2b. The birth dispatch is a production act and needs the owner's go.
- **F8** Follow git-data's `public_net` shape: a public IPv4 for egress only, a firewall with zero
  inbound rules.

## Research Insights

### Premise Validation (Phase 0.6, 2026-11-17)

- #12866 is open; no open PR or foreign gate process names it (`collision-precheck.sh 12866`:
  `prs=none foreign=none`). Step 1 (PR #12613) merged 2026-11-16. ADR-327, the census and the
  archived plan of record exist on `origin/main`.
- **Stale premise 1, the route shape.** There are no `*host-create*` or `*host-replace*` workflow
  files. Every host route is an `apply_target` job inside
  `.github/workflows/apply-web-platform-infra.yml` (`web_host_create`, `web_host_replace`,
  `git_data_host_create`, `git_data_host_replace`, `inngest_host_replace`, `registry_host_replace`),
  each sourcing a gate in `tests/scripts/lib/*-gate.sh`. The "bastion-host-create" and
  "bastion-host-replace" routes are therefore new `apply_target` values, not new workflow files.
- **Stale premise 2, the git-data allowlist.** git-data has no SSH source allowlist. Admission is
  private-network membership (the `git-data.tf` and `zot-registry.tf` firewall comments: traffic
  inside `hcloud_network` is open by membership) plus three git keys with forced commands
  (`git-data.tf`, the `git` user key map). `cloud-init-git-data.yml` carries no `from=`, `Match`,
  `AllowUsers` or `ListenAddress` restriction.
- **Stock.** Live read of `/v1/server_types` at 2026-11-17T16:15Z (read-only token): cx23 is
  orderable in hel1 only (fsn1 and nbg1 `available: false`), EUR 5.49/month gross; cpx12 is
  orderable in all three EU locations (EUR 9.49 hel1). `variables.tf` (the `web_hosts` type note)
  records the whole cx line unorderable on 2026-07-26 and cx23 back on 2026-08-06, so stock is a
  dated reading. `/v1/datacenters` is gone (HTTP 410); `tests/scripts/lib/stock-preflight-gate.sh`
  already reads `server_types[].locations[].available`.
- **Free private IP.** In use under `apps/web-platform/infra/`: .10 .11 .12 .20 .21 .22 .30 .31
  .40 .41 .50 (reserved, `grok_dogfood_private_ip`) .60 (`inngest-provision-rehearsal`) .77 .99.
  `10.0.1.70` is free (`git grep -hoE '10\.0\.1\.[0-9]{1,3}'`).

### Property List (Phase 0.6b)

- P1. A bastion server exists in the web-platform root, and its SSH host-key pin is known before
  it boots.
- P2. Nothing on the public internet can open a connection to it, and nothing on the private network
  can either (host-local nftables `input` chain, `policy drop`; Hetzner firewalls filter only the
  public interface).
- P3. Every egress destination it may reach is listed, and each row names the program on the
  bastion that needs it.
- P4. Its first boot runs the same bounded apt and single kernel-settle reboot as a web host
  (ADR-326).
- P5. It can be created or replaced only through a gated route that rehearses first (`plan_only`),
  and no per-merge apply can create or replace it.
- P6. A replace cannot strand the fleet without a bastion (stock checked before the destroy; a
  create-only retry is accepted).
- P7. A birth reports ready, or not ready, without anyone opening SSH.
- P8. The new recurring cost is in the expense ledger.

### Cut List (Phase 0.6b)

- Separate `bastion-host-create.yml` / `bastion-host-replace.yml` workflow files → P5 → the
  existing `apply_target` job family in `apply-web-platform-infra.yml` already carries
  confirm tokens, the environment reviewer gate and the shared `terraform-apply-web-platform-host`
  concurrency group.
- A new per-merge halt for bastion creates → P5 → `host_creates` in
  `tests/scripts/lib/destroy-guard-filter-web-platform.jq` counts every `hcloud_server` create with
  no name filter, and `terraform-target-parity.test.ts` keeps an excluded resource out of the
  per-merge `-target` list. A test row proving the counter sees a bastion create is enough.
- A new stock check → P6 → `stock-preflight-gate.sh` is sourced by every capacity-sensitive route,
  the additive `web_host_create` included.
- A new readiness reader → P7 → `scripts/fresh-host-boot-trail.sh` reads Sentry by `host_name` and
  `stage` and is shared by create and replace; it only needs the bastion to emit the marker.

### Repo anchors

- Host-key pattern to copy: `git-data.tf` (`resource "tls_private_key" "git_data_host_ssh"`,
  `output "git_data_ssh_host_key_fingerprint"`, the EXPOSURE note naming the state and `user_data`
  copies) and `cloud-init-git-data.yml` (`ssh_keys:` with `ed25519_private` / `ed25519_public`).
- Zero-inbound firewall pattern: `zot-registry.tf` and `git-data.tf` (`hcloud_firewall` with labels
  only, "ZERO inbound rules"), attachment resources beside them, private-net attach in
  `network.tf`.
- Birth route to mirror: `git_data_host_create` in `apply-web-platform-infra.yml` (boot-trail
  anchor step, partial-birth TWO EXCEPTIONS message, `plan_only` consumer). Birth gate shape:
  `tests/scripts/lib/web-host-birth-gate.sh` (exactly one create of the requested host, zero
  destroys, zero reboots, zero out-of-scope). Confirm token form: `confirm=BIRTH-<key>`.
- Per-merge `-target` allowlist and the create HALT: `apply-web-platform-infra.yml` (the
  "terraform plan would CREATE ... hcloud_server resource(s) on the per-PR apply path" error).
- Exclusion list: `plugins/soleur/test/terraform-target-parity.test.ts` `OPERATOR_APPLIED_EXCLUSIONS`
  (entries for `hcloud_server.git_data`, `hcloud_server.registry`, `hcloud_server.inngest`).
- ADR-326 steps: `cloud-init.yml` (`STAGE=apt_update`, `STAGE=apt_install`, `# ADR-326: one reboot
  onto the new kernel`, `STAGE=kernel_settle`); `kernel-currency.test.sh` hardcodes `cloud-init.yml`.
  Per-host `user_data` budget scripts: `git-data-userdata-budget.sh`, `inngest-userdata-budget.sh`,
  `registry-userdata-budget.sh`.
- Egress row format: `cron-egress-nftables.sh` (`add rule ip filter SOLEUR-EGRESS ip daddr … accept
  comment "soleur-egress: <consumer>"`); no existing test rejects an uncited row.
- Readiness reader: `scripts/fresh-host-boot-trail.sh` (Sentry events query on `host_name` and
  `stage`, terminal `fresh_boot_ready`, deadline `BOOT_TRAIL_DEADLINE_S=1200`). Emitter to imitate:
  `soleur-host-bootstrap.sh` (`STAGE=fresh_boot_ready_author`, the `@@SOLEUR_SENTRY_DSN@@` splice).
- Test registration: `apps/web-platform/infra/*.test.sh` are picked up by `git ls-files` glob in
  `run-registered-suites.sh` (basenames must be unique); `tests/scripts/test-*.sh` must be added by
  hand to `scripts/test-all.sh` (`run_suite` lines beside the web-host gate suites).
- Ratchet: `web-hosts-generic.test.sh` counts `10.0.1.10` and `"web-1"` in tracked files against
  `IP_CEIL` / `KEY_CEIL`; new bastion files must contain neither literal.
- Ledger: `knowledge-base/operations/expenses.md`, `## Recurring`, columns
  `Service | Provider | Category | Amount | Status | Renewal Date | Notes`, amounts in USD; a
  not-yet-billing host uses status `approved-not-billing`.

### Institutional learnings applied

- `bug-fixes/2026-07-13-warm-standby-cross-dc-and-replace-capacity-footgun.md` and
  `2026-07-15-replace-shaped-ops-are-net-zero-on-the-resource-they-exhaust.md`: the replace route
  checks per-location stock before the destroy, never account headroom.
- `security-issues/2026-07-23-terraform-destroy-guard-address-vs-physical-id-and-replace-recovery-arm.md`:
  the replace gate pins the live server's physical id and accepts the create-only recovery arm.
- `2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md` and
  `test-failures/2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace.md`:
  every file rendered into the bastion's `user_data` is a replace input; the plan names each carrier.
- `2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md`: the bastion gets its own
  `user_data` byte budget check.
- `2026-11-08-a-merge-that-edits-registry-cloud-init-auto-replaces-the-registry-host-and-the-plan-checked-only-the-apply-workflow.md`:
  no workflow may fire on a push that touches the bastion's files; the plan enumerates every
  `on.push.paths` match.
- `2026-11-16-web2-kernel-currency-replace-five-operational-traps.md`: replace runs share the host
  concurrency group; a cancelled dispatch can still run; the new address is read from apply output.
- `security-issues/2026-09-21-pinning-ssh-host-keys-the-guards-pinned-presence-not-the-resolved-value.md`:
  a pin test asserts the resolved value, not the presence of an option.
- `best-practices/2026-05-20-hr-fresh-host-iac.md`: the bastion's readiness comes from its own
  cloud-init on apply alone (and in 2b, its heartbeat).
- `2026-07-17-hetzner-cloud-api-catalog-not-billed-and-one-marker-per-row.md`: the ledger row is a
  catalog estimate with a `verify_by` marker.
- `workflow-patterns/2026-07-07-agent-runs-terraform-apply-never-route-to-operator.md`: the agent
  dispatches the route after the owner's typed go; no operator step is written.

### Functional overlap

No community skill or agent covers bastion lifecycle, Terraform-minted host keys, egress allowlists
or gated create routes (3 of 3 registries answered; nothing installed).

## Hypotheses

Network checklist N/A (fired on "SSH"): this is a build, nothing connects to the bastion in step 2, and
inbound is closed at both layers (P2, AC5, Guard 2 row 10). Step 3 re-runs the checklist.

## Proposed Solution

One new Terraform file defines the bastion and everything that is born with it. One new cloud-init
file configures it on first boot. One new `apply_target` job births it through an inverted gate. The
host reports ready through the existing Sentry reader, run in a new strict mode; it is observed after
birth from #12879, which adds the heartbeat.
A birth that does not reach ready is powered off by the same job, so a wrong host never sits running on
the private network while it waits for #12879.

**What the merge does to production** (corrected at review, 2026-11-18): the merge creates, replaces
and updates no Hetzner resource; the bastion exists only after the reviewer-approved
`bastion-host-create` dispatch.

1. `apply-web-platform-infra.yml` runs its per-merge targeted apply. No bastion address is in its
   `-target` list, every one is in `OPERATOR_APPLIED_EXCLUSIONS`, so the plan has zero bastion changes and
   the `host_creates` HALT cannot fire because of the bastion. It applies whatever drift is already
   pending in its list, as on every merge. The dispatch-only `bastion_host_create` job does not run.
2. `web-platform-release.yml` is not checks-only: `apps/web-platform/**` changed, so it bumps `web-v*`,
   builds and pushes a new `soleur-web-platform` image (app code unchanged) and runs the normal
   production deploy to the web hosts. User impact is that of an ordinary release.
3. `version-bump-and-release.yml` cuts a plugin release (`plugins/soleur/**` changed) and
   `deploy-docs.yml` redeploys the docs site.
4. Checks only: `infra-validation.yml`, `validate-vector-config.yml` (it also wakes on the bastion shell
   files: `bastion-egress.sh`, `bastion.test.sh`, `fresh-host-boot-trail.test.sh`,
   `soleur-host-bootstrap-observability.test.sh`), `ci.yml` and the scanners. `variables.tf` is not
   edited, so `registry-host-replace-dispatch.yml` does not wake.
5. Not a push trigger: `scheduled-terraform-drift.yml` plans the whole root every 12 h, so from merge
   until birth it reports the five bastion creates; the agent asks the owner for the birth go on merge
   day so that window stays short.

This paragraph is the first section of the PR body.

## Implementation Phases

### Phase 1 — Tests first (cq-write-failing-tests-before)

1. `tests/scripts/test-bastion-host-birth-gate.sh`: the mutation matrix of Guard 1, against
   synthesized `tfplan.json` fixtures. RED until the gate exists.
2. `apps/web-platform/infra/bastion.test.sh`: sections EGRESS (Guard 2), SETTLE (Guard 3), HOSTKEY
   (Guard 4), BUDGET (Guard 5: `wc -c` of the render against a pinned 32,768), and SHAPE (zero inbound
   firewall rules; `10.0.1.70` inside the subnet and distinct from every `var.web_hosts` default
   `private_ip` and the fixed host IPs; x86 precondition; no file name that a push-path filter of another workflow matches, and a push
   trigger with no path filter counts as matching every file unless it is in the reviewed
   non-deploying `EVERY_PUSH` set; the `10.0.1.10` / `"web-1"` literal rule is
   `web-hosts-generic.test.sh`'s, not this lint's). Renders `bastion-cloud-init.yml` through
   Terraform as `kernel-currency.test.sh` does.
3. A row in `tests/scripts/test-destroy-guard-counter-web-platform.sh`: a fixture plan creating
   `hcloud_server.bastion` yields `host_creates == 1`.
4. Reader strict mode, characterization first: a commit that pins the web callers' current output
   byte for byte, then `BOOT_TRAIL_STRICT=1` cases. Strict mode takes the host name in
   `BOOT_TRAIL_HOST_NAME` (leaving `WEB_HOST_KEY` and the web-1 → `soleur-web-platform` mapping
   untouched), requires the event's `host_name` tag to equal it (today an untagged event matches),
   refuses a missing or malformed `BOOT_TRAIL_SINCE` anchor (AP-027), treats an unbound or malformed
   token as not ready, and prints one `verdict=ready|not_ready|skipped` line. Mutation rows: an
   untagged `fresh_boot_ready`, a ready event tagged for another host, a missing anchor, an unbound
   token. Web callers never set the switch, so their output stays byte-identical.
5. `tests/scripts/test-bastion-boot-verify.sh` for the decision library (Phase 4.2).

### Phase 2 — Terraform

1. `bastion.tf`: `tls_private_key.bastion_host_ssh` (ED25519), `hcloud_server.bastion` (name
   `soleur-bastion`, `server_type = "cx23"` as a literal, because a type change is the owner's money
   decision (F4) and a variable would invite a silent `-var`; `var.location`, `ubuntu-24.04`,
   git-data's `public_net` shape but with `ipv6_enabled = false` so no IPv6 path bypasses the IPv4
   allowlist, git-data's `ssh_keys` shape, labels, an x86 `lifecycle.precondition` and a non-empty,
   well-formed `var.sentry_dsn` precondition as `inngest-host.tf` has),
   `local.bastion_private_ip = "10.0.1.70"` (as git-data owns `local.git_data_private_ip`),
   `hcloud_server_network.bastion`, `hcloud_firewall.bastion` (labels only, zero inbound rules) with a
   separate `hcloud_firewall_attachment.bastion` (git-data's form, not inline `firewall_ids`),
   and outputs for the key fingerprint and the private IP. The file carries the EXPOSURE note git-data
   has (the private half is in `tls_private_key` state; the locked hcloud provider stores `user_data` as
   a hash, and the metadata endpoint serves it to root on the host).
2. `tests/scripts/lib/bastion-resources.txt`: the one list of bastion resource addresses. The gate
   reads it as its allow-set, and `plugins/soleur/test/terraform-target-parity.test.ts` asserts the
   job's `-target` lines equal it and that every entry is in `OPERATOR_APPLIED_EXCLUSIONS` (each with
   its reason); `bastion_host_create` goes in the `stripDispatchJobs` list. One list instead of the
   three hand-synced ones git-data carries, because 2b and steps 3-4 add to it.

### Phase 3 — Cloud-init

`bastion-cloud-init.yml`, in this order:

1. A static baseline ruleset written to `/etc/soleur/bastion-nftables.conf` and installed to
   `/etc/nftables.conf` by the post-settle pass (writing the dpkg conffile before `apt-get install
   nftables` trips dpkg's conffile prompt; review, 2026-11-18). Input and output `policy drop`, loopback
   and established only; from the boot after the post-settle pass it loads before `network-pre.target`.
2. `ssh.service` and `ssh.socket` masked: nothing connects to the bastion in step 2, so sshd does not
   run at all, which also closes the public window before `hcloud_firewall_attachment.bastion` lands.
   Step 3 unmasks it with its first dialer. `ssh_keys:` still delivers the Terraform key
   (`ed25519_private`, `ed25519_public`), `ssh_deletekeys: true`, no other key type, plus the sshd
   hardening drop-in (no passwords, root by key only), so the pin is fixed from birth (F5).
3. The ADR-326 bounded apt step and the single kernel-settle reboot, inline, byte-identical to
   `cloud-init.yml` (Guard 3). apt sources over https. During this first-boot stage the egress rows are
   not yet loaded, so apt runs before the baseline is tightened to the allowlist (step 4); the
   baseline's output policy admits DNS, NTP, the metadata endpoint (root only) and https until then.
4. Egress allowlist as boot-persistent units, not a one-shot cloud-init step (the copied settle block
   deletes its semaphore so `runcmd` re-runs after the reboot, as `cloud-init.yml` does; steps 4 and 5
   run in that post-settle pass, and the policy itself reloads on every boot). A small bastion-only `bastion-egress.sh`, rendered
   with `base64encode(file())` and run by a `bastion-egress.service` plus `bastion-egress.timer`, loads
   and resolves in one `nft -f`. It takes two rules from the web `cron-egress-resolve.sh` (one atomic
   swap; a failed lookup never empties the set) but not its 1,024 lines, and it does not render the
   web script, so a web egress edit never replaces the bastion. Its allowlist (the apt mirror and Sentry
   ingest) is a list in the script, each hostname carrying
   `soleur-egress: <unit or file on the bastion>`. The tables are `inet` family, so the policy covers both address
   families. The output chain then accepts DNS, NTP, the metadata
   endpoint (root only) and the `soleur_egress_allow` set, and drops the rest. The metadata drop for
   non-root UIDs comes from `cloud-init-git-data.yml`. The script and its units are replace carriers
   (Distinctness).
5. The readiness event, first boot only (cloud-init per-instance): after the chain loads, the
   consumers prove their own paths in order (`apt-get update` through the loaded chain), then `fresh_boot_ready` (info) with `host_name=soleur-bastion`; `fresh_boot_not_ready_<reason>`
   (fatal) from the error trap otherwise. The DSN is `var.sentry_dsn` (Doppler `prd_terraform`
   `SENTRY_DSN`, as the web cloud-init's `_emit`), so a DSN rotation is a replace input. It sends the
   reader's exact `QUERY` message literals, including `cloud_init_complete`.

### Phase 4 — Birth route

1. `scripts/fresh-host-boot-trail.sh`: the strict mode of Phase 1.4.
2. `scripts/lib/bastion-boot-verify.sh`: the readiness decision (run the strict reader, ready only on
   `verdict=ready`; otherwise power the server off through the Hetzner API, print
   the recovery step and comment the run URL on #12879), in a library as `git-data-boot-signal-poll.sh`
   is, because inline copies drifted there within one PR and #12879's replace job needs the same
   decision.
3. `tests/scripts/lib/bastion-host-birth-gate.sh` (Guard 1).
4. `apply-web-platform-infra.yml`: `bastion-host-create` in the `apply_target` choices; a
   `bastion_host_create` job modelled on `git_data_host_create`: environment `web-platform-infra-apply`,
   `confirm=BIRTH-bastion`; it inherits the workflow-level `terraform-apply-web-platform-host` group
   with no job-level `concurrency` block (a job group equal to the workflow's own is cancelled). It
   copies the precedent's "Generate ephemeral SSH public key for var.ssh_key_path" step, without which
   the plan fails. In this order:
   - before any plan: the precedent's "assert SENTRY_DSN present" step and its birth-readiness
     interlock, plus the reader's Sentry token bound and well-formed (fail closed, so a skipped read can never follow a real create);
   - an explicit `-target` line per entry of `bastion-resources.txt`
     (`tls_private_key.bastion_host_ssh`, `hcloud_firewall.bastion`, `hcloud_server.bastion`,
     `hcloud_server_network.bastion`, `hcloud_firewall_attachment.bastion`; downstream attachments are not pulled in by `-target`'s upstream
     closure);
   - the birth gate on the `tfplan.json`, then the stock gate (the precedent's load-bearing order);
     the job reads the `HCLOUD_TOKEN` that `stock-preflight-coverage.test.ts` requires;
   - the run summary prints the commit SHA and the planned resource addresses; stop here when
     `plan_only` is true;
   - apply of exactly that plan; `bastion-boot-verify.sh`, run after a green OR a failed apply
     (git-data's precedent); the summary prints the key fingerprint and the private IP on success.
5. The `host_creates` HALT message (reachable only on the break-glass untargeted path, since the
   per-merge plan is targeted) gains a `hcloud_server.bastion` arm pointing at `bastion-host-create`,
   and its break-glass full-apply recipe gains "abort if the plan creates, replaces or deletes any
   bastion address, `tls_private_key.bastion_host_ssh` included" (repeated in the runbook).
6. `soleur-host-bootstrap-observability.test.sh`: `bastion_host_create` added to the AC8d job loop,
   and `bastion-cloud-init.yml` added as an emitter under the AC8 `QUERY` literal pin.
7. `scripts/test-all.sh`: `run_suite` for the gate test and the boot-verify test.

### Phase 5 — Records

1. ADR-327 amendment (see Architecture Decision).
2. C4 `model.c4` and `views.c4` (see Architecture Decision).
3. `knowledge-base/operations/expenses.md`: two `approved-not-billing` rows (cx23 bastion about USD 5.93,
   primary IPv4 about USD 0.54; the ledger's Amount column is USD, so the EUR 5.49 / EUR 0.50 figures
   and the FX go in Notes, as the web-2 IPv4 row does) with `verify_by` markers.
4. `knowledge-base/engineering/operations/runbooks/bastion-host.md`:
   - birth, and the stock-failure stop (the type question goes to the owner);
   - partial birth: which retry subsets the gate accepts (Guard 1 rows 5a-5c), and that a server which
     landed goes to #12879;
   - not-ready birth: the job has powered it off; #12879's
     replace route is the only exit in 2a;
   - late ready: the agent re-runs the reader locally, read-only, with the Sentry token from Doppler
     (no second dispatch, which the gate refuses);
   - lost state while Hetzner shows `soleur-bastion`: never re-birth; #12879's recovery arm;
   - the deliberate key-rotation act and its triggers (a suspected state or `user_data` leak, an
     operator offboarding).
5. Issues (filed at plan time): #12879 (2b, the replace route), with #12867 marked blocked by it;
   #12880 (the git-data nftables source allowlist, F1); #12882 (the ADR-326 shared-block follow-up, Guard 3).

### Phase 6 — After merge (Operator Holds)

With the owner's typed go for each command, the agent dispatches the `plan_only` rehearsal and arms a
watch on it (`hr-dispatch-async-must-arm-watch`), shows the owner the printed SHA and resource
addresses, and only on the second go dispatches the real birth. Before that dispatch the agent checks
that no bastion file changed on `main` since the rehearsal SHA (`git diff --quiet <sha> origin/main --
<bastion paths>`); if one did, it re-runs the rehearsal. The real run is watched the same way, then the
trail is read.

## Files to Create

- `apps/web-platform/infra/bastion.tf`
- `apps/web-platform/infra/bastion-cloud-init.yml`
- `apps/web-platform/infra/bastion-egress.sh`
- `tests/scripts/lib/bastion-resources.txt`
- `scripts/lib/bastion-boot-verify.sh`
- `tests/scripts/test-bastion-boot-verify.sh`
- `apps/web-platform/infra/bastion.test.sh`
- `tests/scripts/lib/bastion-host-birth-gate.sh`
- `tests/scripts/test-bastion-host-birth-gate.sh`
- `knowledge-base/engineering/operations/runbooks/bastion-host.md`

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — `apply_target` choice, the `bastion_host_create` job, the HALT arm
- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` — strict mode, plus its characterization and strict cases in the existing reader test
- `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` — AC8d job loop and the AC8 emitter pin
- `tests/scripts/test-destroy-guard-counter-web-platform.sh` — bastion create fixture row
- `plugins/soleur/test/terraform-target-parity.test.ts` — `OPERATOR_APPLIED_EXCLUSIONS`, `stripDispatchJobs`, the `bastion-resources.txt` equality check
- `plugins/soleur/test/stock-preflight-coverage.test.ts` — no edit expected; it auto-enrols the new option and must pass
- `scripts/test-all.sh` — `run_suite` for the gate and boot-verify tests
- `knowledge-base/operations/expenses.md` — two rows
- `scripts/encryption-posture-ledger.json` — a `bastion.baked_credentials_on_host` store row and the bastion's outbound connection rows (Sentry, apt), modelled on the git-data rows; `python3 scripts/lint-encryption-posture.py` must PASS
- `knowledge-base/engineering/architecture/decisions/ADR-327-dedicated-bastion-web-hosts-are-identical-cattle.md` — amendment
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `knowledge-base/engineering/architecture/diagrams/views.c4` — bastion container and edges

## Open Code-Review Overlap

2 open code-review issues touch these files:

- #7098 (`run:` bodies whose `set` omits `-e`, in `apply-web-platform-infra.yml`): **Acknowledge.** A
  different concern; the new job's `run:` bodies use `set -euo pipefail`, so this PR adds no instance.
- #7942 (mutation batteries named `*.mutation.sh` run in no gate, in `scripts/test-all.sh`):
  **Acknowledge.** This PR's gate test is a `test-*.sh` registered with `run_suite`, not a
  `*.mutation.sh`, so it adds no instance.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly in step 2, because no user path
  crosses the bastion until step 3. One path exists from birth: the bastion joins the private network,
  and any member of it can open a connection to git-data:22 (#12880). Other services trust subnet
  membership too: web-host sshd (fail2ban `ignoreip` covers 10.0.1.0/24), the registry at 10.0.1.30:5000
  and Inngest at 10.0.1.40:8288. The bastion's default-drop output chain is their shared protection: it
  has no row for any private address in step 2, and Guard 2 (`bastion-lint.py egress`, tightened at
  review) refuses any output accept row with a private-range destination or with no destination or owner
  qualifier. The risk is indirect: a bastion born wrong (an open inbound port, a
  wrong host key, egress wider than declared) becomes the management-plane jump to every user's code on
  git-data in step 3.
- **If this leaks, the user's data is exposed via:** the bastion's SSH host private key (in Terraform
  state, and in `user_data` as the metadata endpoint serves it to root on the host), which would let an attacker with a network
  position impersonate the bastion to CI and to operators from step 3 on; or a widened egress or inbound
  rule on a host that will hold the jump to git-data.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the host becomes the single path to the store holding every
  user's source code, so one mis-born bastion is a fleet-wide exposure, not an aggregate degradation.

CPO sign-off is required at plan time (`requires_cpo_signoff: true`), and
`soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

```yaml
liveness_signal:
  what: "at birth, the Sentry fresh_boot_ready event with host_name=soleur-bastion, read by the strict boot-trail reader; no signal after birth in 2a (the heartbeat arrives with #12879, CTO re-rule 2026-11-17)"
  cadence: "once per birth"
  alert_target: "a red bastion-host-create run (the agent watches it, hr-dispatch-async-must-arm-watch)"
  configured_in: "apps/web-platform/infra/bastion-cloud-init.yml (_emit), apps/web-platform/infra/scripts/fresh-host-boot-trail.sh (strict reader), scripts/lib/bastion-boot-verify.sh (decision)"
error_reporting:
  destination: "Sentry (the web-platform project the boot trail already reads), via the cloud-init error trap"
  fail_loud: "fresh_boot_not_ready_<reason> fatal; the birth job's ::error:: and exit 1 on any fatal stage, on timeout, and on a skipped read"
failure_modes:
  - mode: "Hetzner has no cx23 stock in hel1"
    detection: "stock-preflight-gate.sh refuses the plan before apply (layer 6: workflow run log ::error::)"
    alert_route: "red bastion-host-create run"
  - mode: "apt or the kernel settle fails or hangs"
    detection: "STAGE=apt_install / STAGE=kernel_settle fatal, or no fresh_boot_ready before BOOT_TRAIL_STRICT_DEADLINE_S (layer 6: workflow run log ::error:: from fresh-host-boot-trail.sh / bastion-boot-verify.sh)"
    alert_route: "red bastion-host-create run; the host is powered off"
  - mode: "egress policy blocks the readiness endpoint, or the egress load fails"
    detection: "fresh_boot_not_ready_egress_load (the trap flushes the ruleset so it reaches Sentry), else no fresh_boot_ready before the deadline (layer 6: workflow run log ::error::)"
    alert_route: "red bastion-host-create run; the host is powered off"
  - mode: "the private NIC never configures 10.0.1.70 (hot-attached NIC left unmanaged, #8539)"
    detection: "STAGE=private_ip fatal (fresh_boot_not_ready_private_ip) after the networkd fallback and a bounded wait (layer 6: workflow run log ::error::)"
    alert_route: "red bastion-host-create run; the host is powered off"
  - mode: "boot-verify cannot power a not-ready host off"
    detection: "bastion-boot-verify.sh ::error:: and poweroff_result=failed in the run summary (layer 6)"
    alert_route: "red bastion-host-create run; the agent powers it off through the Hetzner API (runbook)"
  - mode: "the bastion dies after birth, or a 15-minute egress refresh fails (accepted 2a gap)"
    detection: "none in 2a: layers 1-6 are absent on the bastion (no Vector, no heartbeat); the heartbeat, carrying egress-refresh health, is #12879"
    alert_route: "none in 2a; nothing depends on the bastion until step 3, which #12879 blocks"
  - mode: "the reader cannot authenticate to Sentry"
    detection: "the birth-readiness interlock refuses before the plan; at read time the strict reader's skip is not ready (layer 6: workflow run log ::error::)"
    alert_route: "red bastion-host-create run"
logs:
  where: "Sentry events (birth stages); journald on the host (not shipped in step 2: no Vector on the bastion)"
  retention: "Sentry project retention"
discoverability_test:
  command: "grep -cE '_emit \"soleur-cloud-init boot stage\" (fresh_boot_ready|cloud_init_complete) info' apps/web-platform/infra/bastion-cloud-init.yml"
  expected_output: "2"
```

The discoverability test is offline and sub-second: it proves both readiness emitters the strict reader
needs are in the template. The full wiring proof is `bash apps/web-platform/infra/bastion.test.sh`
(about a minute; it renders the template with terraform) in CI. The live state is read by the birth
job's boot-trail step, which needs no SSH.

## Infrastructure (IaC)

### Terraform changes

- Root: `apps/web-platform/infra/` (existing; R2 backend already present). No new root.
- New resources: `tls_private_key.bastion_host_ssh`, `hcloud_server.bastion`,
  `hcloud_server_network.bastion`, `hcloud_firewall.bastion`, `hcloud_firewall_attachment.bastion`.
  Providers already pinned in the root (`hcloud`, `tls`); no new provider.
- Variables: none added; the server type and private IP are literals in `bastion.tf`. No
  sensitive variable is added; the host key is generated, never supplied
  (hr-tf-variable-no-operator-mint-default).

### Apply path

(a) cloud-init only. The host does not exist; it is born by `bastion-host-create`, never by the
per-merge apply. Downtime and blast radius: none, because nothing depends on it in step 2.

### Host fan-out

No `terraform_data` SSH provisioner is added or changed. The bastion receives no SSH-delivered config
(ADR-327).

### Distinctness / drift safeguards

- Every new resource is in `OPERATOR_APPLIED_EXCLUSIONS` and outside the per-merge `-target` list, and
  `host_creates` halts that path on any server create.
- `user_data` on `hcloud_server.bastion` is not in `ignore_changes`: any edit to
  `bastion-cloud-init.yml`, or to a file or variable rendered into it, plans a replace. After 2b merges,
  that replace runs only through `bastion-host-replace`. The carriers are `bastion-cloud-init.yml`,
  `bastion-egress.sh` and its units, `tls_private_key.bastion_host_ssh` and `var.sentry_dsn` (Doppler `prd_terraform`
  `SENTRY_DSN`). The bastion renders no web file, so web edits never replace it, except the ADR-326
  blocks Guard 3 pins.
- State: the R2 backend holds the private key in the `tls_private_key` resource (the locked hcloud
  provider stores `user_data` as a hash), as for git-data (ADR-237 residual).

### Vendor-tier reality check

No Better Stack resource in 2a. Hetzner cx23 stock is a dated reading (hel1 only on 2026-11-17); the stock
gate re-reads it at dispatch.

## Encryption Posture

```yaml
at_rest:
  - store: "bastion.baked_credentials_on_host (scripts/encryption-posture-ledger.json, modelled on git_data.baked_credentials_on_host)"
    mechanism: plaintext-exception
    evidence: "bastion-cloud-init.yml: the host private key at /etc/ssh (0600 root), the Sentry DSN in the emitter; no volume, no LUKS; the disk holds nothing else but the OS and journald"
    defends_against: "nothing at rest; there is no user data on this disk"
    does_not_defend: "a seized or RMA'd disk yields the host private key"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable: no inbound path in step 2"
  - store: "Terraform state (R2 backend) — tls_private_key.bastion_host_ssh and hcloud_server.bastion.user_data"
    mechanism: "provider-managed:Cloudflare R2 encryption at rest (AES-256), as declared for this root's existing state"
    evidence: "the root's backend block (unchanged); git-data.tf EXPOSURE note for the same residual"
    defends_against: "a raw read of the R2 storage medium"
    does_not_defend: "anyone holding the state credential reads the private key in clear"
    disclosed_as: not-publicly-claimed
    live_verification: "available: terraform state show of the key resource from CI"
in_transit:
  - connection: "bastion -> Sentry ingest (readiness and fatal events)"
    enforced_at: "bastion-cloud-init.yml _emit (curl https, --proto =https)"
    tls: "https, TLS 1.2 minimum"
    cert_verification: on
    does_not_defend: "a compromised bastion sending false events"
    disclosed_as: not-publicly-claimed
  - connection: "bastion -> apt mirror"
    enforced_at: "bastion-cloud-init.yml apt sources (https)"
    tls: "https, TLS 1.2 minimum; package integrity by apt's signed InRelease"
    cert_verification: on
    does_not_defend: "a compromised mirror serving packages signed by a compromised archive key"
    disclosed_as: not-publicly-claimed
exception:
  justification: "the bastion root disk holds no user data; adding LUKS would need an unlock secret at boot on a host whose only secret is its own host key"
  tracking_issue: "#12867"
  reevaluate_when: "the bastion stores anything beyond the OS, its host key and journald (for example a cached credential in step 3)"
  expires_on: 2027-02-15
```

## Task Design

```yaml
tasks:
  - task: "bastion-host-create (apply_target job bastion_host_create in apply-web-platform-infra.yml)"
    trigger: "workflow_dispatch with apply_target=bastion-host-create and confirm=BIRTH-bastion, approved through the web-platform-infra-apply environment"
    services: "reads Hetzner /v1/server_types and the Sentry events API; writes Terraform state (R2), Hetzner (server, network attachment, firewall, poweroff on a not-ready birth)"
    next: "nothing; the replace route arrives in PR 2b"
    human_reentry: "plan_only=true stops after the plan and gate; the environment reviewer can refuse; a run can be cancelled before apply"
    dedupe: "the birth gate refuses any plan that does not create hcloud_server.bastion, so a second birth against a born bastion plans no create and is refused; the shared terraform-apply-web-platform-host concurrency group serialises it with every other host route"
    source_dedupe: "not a ticket source"
```

## Guard Contract

### Guard 1 — bastion birth gate

**Property.** A `bastion-host-create` apply runs only on a plan that creates the bastion server and
the members its creation entails (`hcloud_server_network.bastion`, `hcloud_firewall_attachment.bastion`),
leaves every other bastion resource created or already present (`create` or `no-op`), plans the
firewall with zero rules, and changes nothing else. This is the precedent's rule
(`git-data-host-birth-gate.sh`: require create for what the server's creation entails, require the
rest merely present), so a partial birth can be retried.

**Assembly.** `resource_changes[]` of the one `tfplan.json` the job produced, read by
`tests/scripts/lib/bastion-host-birth-gate.sh`, and the job's apply step, which must consume that same
plan file. Two chokepoints: the gate's classification of every change, and the workflow wiring between
gate and apply (a re-plan between them bypasses the gate).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | The plan also creates `hcloud_server.web["web-3"]` | RED |
| 2 | The gate is fed a plan with an empty `resource_changes` (it reports 0 checked) | RED |
| 3 | The plan creates all bastion resources, then carries a second change: an in-place update to `hcloud_firewall.web` | RED |
| 4 | The plan carries a delete of any resource | RED |
| 5 | Partial-birth retry: the key and firewall are `no-op` (they landed in a failed first run); the server and its attachments are `create` | PASS |
| 5a | The key is `update` or `delete` in an otherwise valid plan | RED (the key never rotates, F5) |
| 5b | Every bastion resource is `no-op` (already born) | RED, "already born: use #12879" |
| 5c | `hcloud_server.bastion` is delete-and-create | RED, never applied |
| 6 | The job's apply step re-runs `terraform plan` instead of applying the gated file | RED (workflow structure assertion) |
| 7 | The plan creates the server but not `hcloud_server_network.bastion` | RED |
| 8 | The job's `-target` lines differ from `bastion-resources.txt` by one entry | RED (parity assertion) |
| 9 | `hcloud_firewall.bastion` is planned with a non-empty `rule` | RED |

Lost state while Hetzner still shows `soleur-bastion` plans a fresh create that collides on the name
at apply; the runbook routes it to #12879's recovery arm, and the gate does not try to detect it.

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | The gate under test is replaced by `return 0` | suite RED |
| H2 | A plan with the bastion resources in a different order plus `no-op` and `read` actions on data sources | PASS |

**Anchor.** The allowed set lives in the gate, and one diff can widen both the set and `bastion.tf`, so
the gate proves consistency, not integrity. The outside anchor is the owner's typed go after the
`plan_only` run prints the plan's resource list in the run summary.

### Guard 2 — bastion egress rows cite a consumer

**Property.** Every accept rule in the bastion's output chain, and every hostname the resolver feeds
into its allow set, names a unit or file that exists on the bastion; the output and input chains drop
everything else.

**Assembly.** The nftables text in the rendered `user_data` of `hcloud_server.bastion` (rendered through
Terraform, not read from the source YAML, because rows can arrive through template variables): every
`add rule … accept` line, every chain `policy`, and the set of unit and file names the same render
installs.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | An accept row with no `comment` | RED |
| 2 | The nftables block is removed from the render (0 rows checked) | RED |
| 3 | A second uncited row after a cited first | RED |
| 4 | The output chain policy is `accept` | RED |
| 5 | A row cites `soleur-egress: cloudflared`, and the render installs no cloudflared unit | RED |
| 6 | An accept-all row with a valid-looking comment (`oifname "eth0" accept comment "soleur-egress: apt"`) | RED |
| 7 | The rendered ruleset has a syntax error (`nft -c -f` on the render fails) | RED |
| 8 | The refresh timer is removed from the render while hostname rows remain | RED |
| 9 | A resolver allowlist hostname has no `soleur-egress:` citation | RED |
| 10 | The `input` chain policy is `accept`, or the chain is absent | RED |
| 11 | The table family is not `inet`, or `hcloud_server.bastion` has `ipv6_enabled = true` | RED |
| 12 | The baseline `/etc/soleur/bastion-nftables.conf` is absent from the render, or `ssh.service` is not masked | RED |
| 13 | `bastion-egress.sh` empties the allow set when one lookup fails (fixture resolver) | RED |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | The lint function is replaced by `true` | suite RED |
| H2 | A cited row whose match fields appear in a different order with extra spaces | PASS |

**Anchor.** No stored value; consumer presence is checked against the same render.

### Guard 3 — ADR-326 steps match the web hosts

**Property.** The bastion's bounded apt wrapper and kernel-settle block are the same bytes as the web
hosts', and the bastion installs `linux-image-generic`.

**Assembly.** The blocks in `cloud-init.yml` and in `bastion-cloud-init.yml` anchored on the existing
`STAGE=apt_update`, `STAGE=apt_install` and `# ADR-326: one reboot` lines (no markers are added to
`cloud-init.yml`, so no web-host `user_data` byte changes), for each of the apt-update, apt-install
wrapper and kernel-settle blocks; the bastion's package list is a
per-host field checked only for `linux-image-generic`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | The apt timeout changes in the bastion file only | RED |
| 2 | The markers are missing from the bastion file (both extracts empty) | RED |
| 3 | The web block changes and the bastion block does not | RED |
| 4 | A second kernel-settle block is appended in the bastion file | RED |
| 5 | `linux-image-generic` is dropped from the bastion package list | RED |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | The comparison is replaced by `true` | suite RED |
| H2 | The two files differ only outside the markers | PASS |

**Anchor.** None stored; both sides are read from the tree. The wrapper is compared with only its
package list normalised (it shares a line with the wrapper), and the bastion's helpers (`_emit`,
`on_err`, the trap) carry the same names, rendered through `templatefile` with the same escaping. The
RED message names both actions: edit `bastion-cloud-init.yml`, then dispatch `bastion-host-replace`
(#12879).

### Guard 4 — the bastion boots with the Terraform host key

**Property.** The only SSH host key the bastion can present is `tls_private_key.bastion_host_ssh`.

**Assembly.** The `ssh_keys` mapping and `ssh_deletekeys` setting in the rendered `user_data`, compared to
the key resource's public half from the same plan.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | The render carries a different ed25519 key | RED |
| 2 | The `ssh_keys` block is absent (sshd would mint its own) | RED |
| 3 | An `rsa_private` entry is added after the compliant ed25519 entry | RED |
| 4 | `ssh_deletekeys: false` | RED |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | The comparison reads the expected key from the render itself | suite RED (the fixture key differs) |
| H2 | The same key with different YAML quoting | PASS |

**Anchor.** The expected value comes from the key resource, not from the render, so the render cannot
certify itself.

### Guard 5 — bastion user_data fits the cap

**Property.** The rendered bastion `user_data` is non-empty and at most 32,768 bytes.

**Assembly.** The BUDGET section of `bastion.test.sh`: `wc -c` over the same Terraform render the
other sections read (no separate budget script, because the render already exists there).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | The render exceeds 32,768 bytes | RED |
| 2 | The render is empty (0 bytes) | RED |
| 3 | The render is 32,769 bytes (one over) | RED |

**Harness rows:**

| # | Suite edit or input | Expected |
|---|---|---|
| H1 | The size measurement returns 0 | suite RED |
| H2 | A render 1 byte under the cap | PASS |

**Anchor.** The cap is the provider's documented 32,768 bytes, pinned in the test.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-327 (no new ADR; `soleur:architecture`). The amendment, dated 2026-11-17, records:

- the routes are `apply_target` jobs, not workflow files;
- git-data admits by private-network membership plus forced commands; the residual (any member of the
  private network reaches git-data:22) and the tracking issue for an nftables source allowlist;
- egress rows land with the consumer they serve, step by step;
- the bastion host key does not rotate on replace; the residual (a leaked copy stays valid until a
  deliberate rotation) and the runbook act that rotates it;
- Hetzner firewalls filter only the public interface; the bastion's own `input` chain drops private-network
  inbound, which git-data does not yet do (#12880);
- step 2 is two PRs, and 2b blocks step 3; until 2b merges, the Consequences' claim that the
  bastion's own replace route bounds the risk is not yet true, and a not-ready birth is powered off;
- the recurring cost is EUR 5.99/month, not EUR 4-5.

### C4 views

All three model files were read for this plan (`model.c4`, `views.c4`, `spec.c4`). Checked:

- External human actors: `founder` (the operator who gives the typed go) is already modelled. No new
  actor.
- External systems: `github` (CI births the host), `sentry` (readiness)
  are already modelled. Hetzner is modelled as the `platform.infra.hetzner` container, not a system.
- Containers: no bastion exists. Add `bastion = container "Bastion"` under `platform.infra`, with
  technology "Hetzner Cloud cx23, no public inbound" and a description naming its step-2 state (born,
  no role yet) and ADR-327.
- Relationships to add: `github -> bastion` ("born via `bastion-host-create`; replace pending
  #12879"), `bastion -> sentry` (birth readiness); `bastion -> betterstack` lands with #12879.
- Descriptions falsified: none in step 2. The `tunnel -> hetzner` edge (deploy. and ssh. to web-1's
  private IP) stays true until step 3, which edits it.
- `views.c4`: add `platform.infra.bastion` to the include list beside `platform.infra.gitDataStore`.
- Validation: `apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts`
  and `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

The amendment describes step 2 as it ships. Step 3's plan amends the C4 edges it moves.

## Domain Review

**Domains relevant:** Engineering, Operations, Product, Finance, Legal

### Engineering

**Status:** reviewed
**Assessment:** The CTO ruled on eight forks on 2026-11-17 (see CTO Rulings), on top of the binding
2026-11-10 ruling recorded in ADR-327. The design reuses the existing route family, gates, stock check
and readiness reader, and adds only what step 2 needs.

### Operations

**Status:** reviewed
**Assessment:** One new host and two ledger rows; the heartbeat lands with #12879. The runbook carries the
partial-birth decision tree and the key-rotation act. No operator step is written: the agent dispatches
after the owner's typed go.

### Finance

**Status:** reviewed
**Assessment:** The live catalog price is EUR 5.99/month (cx23 EUR 5.49 plus IPv4 EUR 0.50), above
the EUR 4-5 approved on 2026-11-10. The ledger records the real figure, and the birth go names it. A
switch to cpx12 (EUR 9.49) is not made without the owner.

### Legal

**Status:** reviewed
**Assessment:** No new vendor and no new processing of personal data. Hetzner and Sentry
are existing processors on existing DPAs, and the bastion stores no user data in step 2.

### Product (CPO sign-off)

**Status:** reviewed
**Assessment:** Signed off with conditions by the CPO agent, 2026-11-17. The User-Brand Impact framing
and both descopes hold. Conditions applied: the Overview no longer claims the git-data allowlist item;
User-Brand Impact names the private-network path to git-data:22 and the egress test that blocks it;
the runbook lists rotation triggers; #12880 re-decides at the #12867 sign-off; #12867 records the
cutover's user-facing check (git access and workspace saves keep working).

### Product/UX Gate

**Tier:** none (no UI surface; the mechanical UI-surface override did not fire on the file lists)

## Operator Holds

- Hold: Operator-authorizes: dispatch the bastion birth rehearsal after merge, `gh workflow run apply-web-platform-infra.yml -f apply_target=bastion-host-create -f confirm=BIRTH-bastion -f plan_only=true`. The environment reviewer approval on `web-platform-infra-apply` is the owner's.
- Hold: Operator-authorizes: dispatch the real bastion birth after reviewing the rehearsal's SHA and resource list, `gh workflow run apply-web-platform-infra.yml -f apply_target=bastion-host-create -f confirm=BIRTH-bastion -f plan_only=false`, quoting the rehearsal run ID. This go also accepts the EUR 5.99/month recurring cost.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add the dedicated bastion host: `hcloud_server.bastion` in the web-platform root" [issue #12866] | `bastion.tf` | mapped |
| 2 | "its cloud-init (same bounded apt and kernel-settle steps as web hosts, ADR-326)" [issue #12866] | `bastion-cloud-init.yml`, Guard 3 | mapped |
| 3 | "a Terraform-generated host key" [issue #12866] | `tls_private_key.bastion_host_ssh`, Guard 4 | mapped |
| 4 | "no public inbound" [issue #12866] | `hcloud_firewall.bastion`, `bastion.test.sh` SHAPE | mapped |
| 5 | "an egress allowlist with a cited consumer per row" [issue #12866] | nftables block, Guard 2 | mapped |
| 6 | "Add gated create and replace routes for it" [issue #12866] | create: `bastion_host_create` job, Guard 1 | mapped |
| 7 | "Its replace route exists and is tested." [issue #12866] | — | descoped — justification: CTO F7 moves it to PR 2b, because a replace gate pins a live physical id and can only be proven against the born host; 2b is filed as an issue and blocks step 3 |
| 8 | "the git-data SSH source allowlist entry for the bastion" [issue #12866] | — | descoped — justification: no such allowlist exists (git-data admits by network membership); CTO F1 corrects ADR-327 and files a tracking issue |
| 9 | "The bastion is born through its gated create route (`plan_only` first) and reports ready." [issue #12866] | Phase 6, Operator Holds, AC9 | mapped |
| 10 | "The new recurring cost (about EUR 4-5/month) is recorded in the expense ledger in the same PR." [issue #12866] | `expenses.md` rows | mapped |
| 11 | "Typed go for the bastion create, `plan_only` then real." [issue #12866] | Operator Holds | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `bastion.tf` | asks 1, 3, 4 | asked |
| `bastion-cloud-init.yml` | asks 2, 5 | asked |
| `bastion-egress.sh` | ask 5 | asked |
| `bastion-resources.txt` | — | inferred — justification: one list instead of three hand-synced ones (CTO devex review); 2b and steps 3-4 extend it |
| `bastion-boot-verify.sh` and its test | ask 9 ("reports ready") | asked |
| `bastion.test.sh` | asks 2-5 | asked |
| `bastion-host-birth-gate.sh` and its test | ask 6 | asked |
| `apply-web-platform-infra.yml` | ask 6 | asked |
| `fresh-host-boot-trail.sh` and the tests that call it | ask 9 ("reports ready") | asked |
| `test-destroy-guard-counter-web-platform.sh` row | — | inferred — justification: proves the existing per-merge halt sees a bastion create, the enforcement contract ADR-327 relies on |
| `terraform-target-parity.test.ts` | — | inferred — justification: Guard 1 of that suite reds on any managed resource missing from the target list or the exclusions |
| `scripts/test-all.sh` | — | inferred — justification: a `tests/scripts/test-*.sh` suite runs only when registered |
| `expenses.md` | ask 10 | asked |
| `encryption-posture-ledger.json` rows | — | inferred — justification: the Layer A posture lint reds on an unledgered store or connection the plan introduces (ADR-140) |
| ADR-327 amendment and C4 edits | — | inferred — justification: wg-architecture-decision-is-a-plan-deliverable; the plan corrects ADR-327's premises |
| `bastion-host.md` runbook | — | inferred — justification: CTO F5 requires the rotation act to be named; the partial-birth tree is the sibling routes' pattern |
| `betteruptime_heartbeat.bastion` and its timer | — | moved to 2b (#12879), CTO re-rule 2026-11-17 |
| Two issues (2b, git-data allowlist) | asks 7, 8 | asked |

### Split Assessment

- Subsystems touched: 6 — `apps/web-platform`, `.github`, `tests`, `plugins/soleur`, `scripts`, `knowledge-base`
- Planned files: 24 | Estimated changed lines: 1,300
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — the replace route (gate, test, job) is PR 2b, ruled by the CTO (F7). The
  remaining 2a set stays one PR: the host, its birth gate and its tests cannot be reviewed apart, and
  most of the roots are one-line registrations.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge

- [ ] AC1. `bash apps/web-platform/infra/bastion.test.sh` passes, and each Guard 2 to Guard 5 mutation row
  turns it red (run in work; results quoted in the PR body).
- [ ] AC2. `bash tests/scripts/test-bastion-host-birth-gate.sh` passes, and each Guard 1 row behaves as
  its table says; it is registered in `scripts/test-all.sh`.
- [ ] AC3. No bastion resource address appears in the per-merge `-target` list, and every bastion
  resource is in `OPERATOR_APPLIED_EXCLUSIONS` (`terraform-target-parity.test.ts` passes, a static check
  over the workflow and the `.tf` files, not a live plan that a concurrent merge could change).
- [ ] AC4. The destroy-guard counter test has a bastion fixture with `host_creates == 1`, and it passes.
- [ ] AC5. `hcloud_firewall.bastion` has zero `rule` blocks, and the bastion has a private IP of
  `10.0.1.70` that the `hcloud_server.bastion` precondition proves unique and inside the subnet.
- [ ] AC6. No new file contains `10.0.1.10` or `"web-1"`; `web-hosts-generic.test.sh` passes with its
  ceilings unchanged.
- [ ] AC7. `fresh-host-boot-trail.sh` reads by host name; the web routes' existing reader tests pass
  unchanged in result; the bastion job treats `verdict=skipped` (and anything but `verdict=ready`) as
  not ready.
- [ ] AC8a. `python3 scripts/lint-encryption-posture.py` reports PASS with the bastion's store and connection rows ledgered.
- [ ] AC8. The ADR-327 amendment, the C4 bastion container and edges, the two ledger rows and the runbook
  are in the PR; the three C4 tests pass.
### Post-merge

- [ ] AC9. After merge and the owner's go: the `plan_only` run stops after a gate PASS listing exactly the
  bastion's resources; the real run applies, the trail reads `fresh_boot_ready` for `soleur-bastion`,
  and the ledger rows flip to `active` in a follow-up commit. The PR body uses
  `Ref #12866`; #12866 closes when the birth reads ready and #12879 has merged.
- [x] AC10. #12879 (2b), #12880 (git-data allowlist) and #12882 (shared ADR-326 block) are filed, and #12867 is marked blocked by
  #12879 (done at plan time, 2026-11-17).

## Test Scenarios

- Given a plan that creates only the bastion's resources, when the birth gate reads it, then it passes
  (unit).
- Given any extra create, update or delete, when the gate reads it, then it refuses and names the
  address (unit).
- Given an empty plan, when the gate reads it, then it refuses (unit).
- Given the rendered bastion `user_data`, when the egress lint runs, then every accept row cites a unit
  present in the render and the policy is drop (unit).
- Given the two cloud-init files, when the settle parity check runs, then the marked blocks are
  identical (unit).
- Given the rendered `user_data` and the key resource, when the host-key check runs, then the only host
  key is the Terraform key (unit).
- Given the per-merge plan path, when a fixture plan creates `hcloud_server.bastion`, then
  `host_creates` is 1 and the halt fires (integration).
- Given the reader with `host_name=soleur-bastion` and no Sentry token, when the bastion route calls it,
  then the route ends not-ready (unit).
- Given the owner's go, when the agent dispatches `plan_only`, then the run summary lists the plan's
  resources and stops (live, post-merge).

## Dependencies & Risks

- **Stock.** cx23 is orderable in hel1 only (2026-11-17). If it disappears, the stock gate stops the
  birth and the type question goes to the owner (CTO F4). No silent switch.
- **Cost.** EUR 5.99/month is above the approved EUR 4-5; the go names the figure.
- **Shared reader change.** Strict mode is opt-in; the characterization commit pins the web callers'
  output byte for byte before it lands.
- **Window before 2b.** The bastion exists without a replace route until 2b merges. Safe only because
  nothing depends on it; 2b blocks step 3.
- **A not-ready birth has no route in 2a.** The first real boot of this cloud-init is the production
  birth, the birth gate allows no update or destroy, and a fix to `user_data` forces a replace. Recovery
  is #12879's replace route, whose `plan_only` proof then runs against the not-ready host; until then it
  bills about EUR 0.20/day and serves nothing. The runbook names this. Three checks lower the chance:
  `nft -c` on the rendered ruleset in CI (Guard 2 row 7), the consumers' own ordered checks through
  the loaded chain before `fresh_boot_ready`, and the reader's deadline, which turns a host that cannot send its fatal event
  into a red run.
- **Key residual.** The private key sits in state and is served to root by the metadata endpoint; a leak stays valid until a
  deliberate rotation (runbook).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- Any edit to `bastion-cloud-init.yml` after the birth plans a replace of the bastion. Read the carrier
  list in Distinctness before touching it.
- Never add a bastion resource to the per-merge `-target` list.
- An edit to the ADR-326 blocks in `cloud-init.yml` reds Guard 3 and forces a bastion replace through
  `bastion-host-replace` (#12879).
