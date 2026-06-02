<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "fix(infra): give infra-config-apply.sh a deploy path independent of the on-host handler"
date: 2026-06-02
type: fix
issue: 4811
ref_issues: [4804]
lane: cross-domain
brand_survival_threshold: aggregate pattern
status: planned
---

# fix(infra): deploy-pipeline-fix handler has no deploy path to a running host

🐛 Closes the architectural chicken-and-egg that makes an `infra-config-apply.sh`
(webhook handler) edit a no-op on a running host, and gives the handler +
host-side `hooks.json` a deploy path that does not route *through* the handler
it is trying to replace.

> Lane note: branch has no `spec.md`; `lane:` defaulted to `cross-domain` (TR2 fail-closed).

> IaC-routing note: the entire change IS a Terraform `terraform_data` resource
> (Phase 2.8 reviewed). The apply is `terraform apply -target=...` and the host
> writes happen inside the resource's own `remote-exec` block — there is NO
> manual SSH provisioning step outside Terraform. The `## Infrastructure (IaC)`
> section below is the routing artifact; ack comment at top of file.

## Overview

`terraform_data.deploy_pipeline_fix` pushes 8 files to prod via the
`/hooks/infra-config` webhook (`push-infra-config.sh` → `infra-config-apply.sh`).
The handler `infra-config-apply.sh` is **not one of those 8 files** — it is not
in `push-infra-config.sh`'s payload nor in the handler's own `FILE_MAP`. The
handler reaches the host only via:

1. `cloud-init.yml` write_files (`server.tf:40`) — but `hcloud_server.web` has
   `lifecycle.ignore_changes = [user_data]` (`server.tf:57`), so cloud-init never
   re-applies to the running host; and
2. the `triggers_replace` hash (`server.tf:318`) — editing the handler bumps the
   hash and re-runs `push-infra-config.sh`, which pushes the **other** files,
   leaving the handler change dead on the host.

Net: a handler/`hooks.json` drift on the host is **unrecoverable through the
webhook path**, because the recovery itself flows through the (stale) handler.
PR #4805 made the handler fail loud + land partial files (the false-success is
gone), but a fix can only take effect on a host that *receives the new handler* —
and there is no path that delivers it.

The fix adds a **dedicated SSH `terraform_data` bootstrap resource** that writes
`infra-config-apply.sh`, `hooks.json`, and `cat-infra-config-state.sh` directly
to the running host and restarts the webhook listener — exactly mirroring the
**7 existing SSH-provisioner siblings** already in `server.tf`. This path does
not depend on the on-host handler, so it simultaneously:

- **Work item A** — one-time recovers the frozen prod host (`135.181.45.178`),
  unblocking #4804; and
- **Work item B** — closes the architectural gap permanently: any future handler
  or host-side `hooks.json` edit reaches the running host on the next apply.

### Why SSH (and why this is not a #3756 regression)

`#3756` replaced **only** `deploy_pipeline_fix`'s SSH provisioner with the
webhook, to keep the *routine* deploy-config push HTTPS-only. SSH was never
removed from the stack: **7 sibling `terraform_data` resources** in the same
`server.tf` still use `connection { type = "ssh" }` + `provisioner "file"` +
`remote-exec` against `hcloud_server.web.ipv4_address` today
(`disk_monitor_install`, `resource_monitor_install`, `fail2ban_tuning`,
`journald_persistent`, `docker_seccomp_config`, `apparmor_bwrap_profile`,
`orphan_reaper_install`). SSH:22 is allowlisted to `var.admin_ips`
(`firewall.tf:6-10`). The webhook path cannot bootstrap its own handler by
construction (it routes through the handler); SSH is the only path that can
deliver the handler *to* a host where the handler is broken. This resource is
the **handler-bootstrap bridge**, the SSH analogue of the existing
`journald_persistent` resource — not a reversal of #3756's routine-push decision.

## Premise Validation

Checked every referenced artifact against `origin/main` at plan time:

- **#4811** (this issue): OPEN. Not yet resolved by any merged PR. Premise holds.
- **#4804** (the freeze this unblocks): OPEN. The `Ref #4804` post-merge close
  path in `apply-deploy-pipeline-fix.yml:313-400` is gated on `#4804` still
  OPEN — still live.
- **#4805** (handler-logic + CI-gate fix): MERGED (`77f0f5ff`). The handler now
  fails loud + lands partial; this plan delivers the handler, it does not re-fix
  its logic.
- **#3756** (webhook-replaces-SSH for `deploy_pipeline_fix`): CLOSED/merged
  (`fc8b8179` via #4492). Scope was `deploy_pipeline_fix` only; 7 sibling SSH
  provisioners survive in `server.tf`.
- **Cited file/symbol paths** all confirmed present on the worktree:
  `push-infra-config.sh` (8-file payload, no `infra_config_apply_sh_b64`),
  `infra-config-apply.sh` `FILE_MAP` (8 entries, no self-write),
  `server.tf` `terraform_data.deploy_pipeline_fix` (`triggers_replace` over 10
  inputs incl. the handler), `hooks.json.tmpl` (already registers
  `infra-config-status` + maps `cat_infra_config_state_sh_b64` — the *repo* is
  correct; only the *on-host* copy is stale), `cloud-init.yml:206` (handler
  write_files), `firewall.tf:6-10` (SSH:22 → `admin_ips`).

No stale premise. The "fix the bug in X" framing is correct (X exists; it has no
deploy path), not a "X was never built" build plan.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "hooks.json `infra-config` hook does not map `cat_infra_config_state_sh_b64`" | TRUE **on the host**; the *repo* `hooks.json.tmpl:46` already maps it and `:77-94` registers `infra-config-status`. The drift is host-only. | The bootstrap resource pushes the repo's correct `hooks.json` (via `local.hooks_json`) to the host, re-aligning host to repo. No `hooks.json.tmpl` edit needed. |
| "`infra-config-apply.sh` does not write itself (not in FILE_MAP)" | TRUE (`FILE_MAP` has 8 entries; the handler is not one). | By design, the handler can't self-deliver; the bootstrap resource is SSH-direct, not handler-routed. |
| "Reconsider the no-SSH constraint (#3756)" | #3756 removed SSH only from `deploy_pipeline_fix`; 7 SSH siblings remain. | No constraint to "reconsider" — SSH is already the live mechanism for 7 host-side installs. New resource adopts the same pattern verbatim. |
| "live: /hooks/infra-config-status → 404, /hooks/deploy-status → journald_storage: null (2026-06-02)" | Live prod assertion in the issue body; not re-verified at plan time (read-only webhook GET needs prod secrets — done in the apply, not the plan). | The post-apply verify steps assert `infra-config-status` returns 200 AND `journald_storage.persistent == true`, closing #4804. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing *directly* — this is an
internal deploy-pipeline reliability surface, not a runtime user path. Indirect:
a future handler edit silently fails to reach prod (the exact #4804 class), so a
deploy-config fix believed shipped is dead on the host, and the next genuine
deploy-pipeline change (e.g., a `ci-deploy.sh` security fix) cannot land —
degrading the ability to ship fixes to *all* users.

**If this leaks, the user's data/workflow/money is exposed via:** no new data
surface. The bootstrap writes the same files the webhook already writes; the
SSH connection reuses `var.admin_ips` + agent auth identical to the 7 siblings.
No new secret, no new credential, no new inbound port.

**Brand-survival threshold:** aggregate pattern. A single botched apply is
recoverable (re-run, or apply again as today); the brand risk is the *recurring*
"deploy-config edits silently don't ship" pattern (7 remediation cycles already
documented in
`knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`),
which this plan terminates. No per-PR CPO sign-off required at `aggregate
pattern`; section present per gate.

## Hypotheses

This plan introduces an SSH `provisioner` (`connection { type = "ssh" }` +
`remote-exec`), which makes SSH reachability a hard apply-time dependency. Per
the Network-Outage checklist (`hr-ssh-diagnosis-verify-firewall`), the L3→L7
layers are addressed *before* any service-layer assumption. The
`hr-ssh-diagnosis-verify-firewall applied` incident was emitted at plan time.

1. **L3 — firewall allow-list (apply-time SSH dependency).** The new resource's
   `terraform apply` SSHes from the applying machine's egress IP to
   `hcloud_server.web.ipv4_address:22`, which is allowlisted to `var.admin_ips`
   only (`firewall.tf:6-10`). A `connection reset by peer` / `handshake failed`
   here is **admin-IP drift**, NOT an sshd/handler fault. Verification (at apply,
   not plan): `hcloud firewall describe` (or the Hetzner console) diffed against
   the applying egress `curl -s https://ifconfig.me/ip`; remediation
   `/soleur:admin-ip-refresh`, runbook
   `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`. **Identical to the
   apply-path firewall note already documented on `journald_persistent`
   (`server.tf:217-221`)** — the new resource inherits the same precondition
   because it uses the same connection block.
   - **Runner-egress caveat (load-bearing):** the 7 existing SSH siblings are
     applied from an admin machine (admin IP ∈ `admin_ips`), NOT from CI — only
     `deploy_pipeline_fix` runs in `apply-deploy-pipeline-fix.yml`, and it uses the
     *webhook* (CF Tunnel), which needs no SSH allowlist entry. A GitHub-hosted
     runner's egress IP is **not** in `admin_ips` and is not static. Therefore the
     new SSH resource MUST NOT be auto-applied from CI against `admin_ips` as-is.
     See Infrastructure → Apply path for the resolution.
2. **L3 — DNS / routing.** SSH targets `hcloud_server.web.ipv4_address` (a
   Terraform attribute, not DNS) — no resolver dependency for the SSH hop. The
   *verify* step's HTTPS GET targets `deploy.${APP_DOMAIN_BASE}` through the CF
   Tunnel (same hostname the existing verify steps already use successfully);
   DNS for it is verified-stable by the fact the same endpoint serves
   `/hooks/deploy-status` today. [opt-out: same host+path reachable in every
   prior apply; artifact = existing green `Verify webhook is alive` step]
3. **L7 — TLS / proxy (verify step only).** The post-apply verification curls
   `https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config-status` and
   `/hooks/deploy-status` through the CF Tunnel + CF Access service token (same
   headers as `apply-deploy-pipeline-fix.yml:189-194`). A non-200 with a CF error
   body = edge/Access misconfig, not handler fault.
4. **L7 — application (handler) layer.** Only *after* L3 is verified: if
   `/hooks/infra-config-status` still 404s post-apply, the host's `hooks.json`
   did not re-register the status hook → the bootstrap `hooks.json` write or the
   webhook restart failed. Inspect via the apply's `remote-exec` stdout (printed
   to the apply log) and the handler's own `logger -t infra-config-apply` lines.

## Implementation Phases

### Phase 0 — Preconditions (verify before any edit)

0.1 Confirm the 7 SSH siblings' connection-block shape is current (the pattern
the new resource copies verbatim):
`grep -n 'connection {' apps/web-platform/infra/server.tf` → expect 7 hits, each
`type="ssh"` / `host=hcloud_server.web.ipv4_address` / `user="root"` /
`agent=true`. The new resource uses the identical block.

0.2 Confirm the handler is NOT in the webhook payload (the gap this closes):
`grep -c infra_config_apply apps/web-platform/infra/push-infra-config.sh` → 0;
and `infra-config-apply.sh` `FILE_MAP` has no self-entry.

0.3 Confirm `local.hooks_json` is the single rendered source already shared by
cloud-init + `deploy_pipeline_fix` (`server.tf:1-8`, `:39`, `:341`) — the new
resource pushes the SAME rendered content, so host `hooks.json` re-aligns to repo.

### Phase 1 — Add `terraform_data.infra_config_handler_bootstrap` (server.tf)

Add a new resource **mirroring `journald_persistent`** (the closest sibling: a
single-purpose SSH install with positive post-write assertions and a webhook
restart). Precedent-diff is required at deepen-plan Phase 4.4 — cite
`server.tf:222-282` (`journald_persistent`) as the pattern source.

- `triggers_replace = sha256(join(",", [ file("infra-config-apply.sh"),
  file("cat-infra-config-state.sh"), local.hooks_json ]))` — re-fires the
  bootstrap whenever the handler, the status script, OR the rendered hooks.json
  changes. (Note: these three are ALSO in `deploy_pipeline_fix`'s
  `triggers_replace`; that is intentional — both resources re-fire on a handler
  edit, but only THIS one actually delivers the handler.)
- `connection { type = "ssh"; host = hcloud_server.web.ipv4_address;
  user = "root"; agent = true }` — copied verbatim from the 7 siblings.
- `provisioner "file"` × 2: push `infra-config-apply.sh` →
  `/usr/local/bin/infra-config-apply.sh`, `cat-infra-config-state.sh` →
  `/usr/local/bin/cat-infra-config-state.sh`. For `hooks.json`, the rendered
  content lives in `local.hooks_json` (secrets interpolated at plan time), NOT
  on disk — so it cannot be a `provisioner "file"` source. Write it via
  `remote-exec` heredoc from a base64-encoded local value, mirroring how
  `push-infra-config.sh` passes `HOOKS_JSON_B64`:
  `printf '%s' '${base64encode(local.hooks_json)}' | base64 -d > /etc/webhook/hooks.json`
  (sensitive value; Terraform permits interpolation inside `remote-exec inline`
  strings the same way the existing `fail2ban`/`disk-monitor` resources
  interpolate `var.resend_api_key`).
- `provisioner "remote-exec"` (post-write): `chmod 0755` the two scripts;
  `chown root:root` scripts, `chown root:deploy` + `chmod 0640`
  `/etc/webhook/hooks.json` (match `cloud-init.yml:231-232` ownership); a webhook
  listener restart; then **positive assertions** (fail2ban/journald pattern —
  prove it took, don't observe it):
  - `test -x /usr/local/bin/infra-config-apply.sh`
  - `grep -q infra-config-status /etc/webhook/hooks.json` (hook re-registered)
  - `grep -q cat_infra_config_state_sh_b64 /etc/webhook/hooks.json` (key mapped)
  - assert the webhook unit reports `active` (the `is-active` check the
    `journald_persistent` resource uses for `systemd-journald`).
- Header comment block: explain this is the **handler-bootstrap bridge** (SSH,
  not webhook) and WHY (the webhook path routes through the handler it would
  replace → cannot self-deliver). Cite #4811, #4804, and the apply-path firewall
  note (copy the `journald_persistent:217-221` admin-IP framing verbatim).
- `depends_on`: none required beyond implicit `hcloud_server.web` (the webhook
  binary + `/etc/webhook` dir are provisioned by cloud-init on fresh hosts; on
  the existing host they already exist).

**Sibling-sync note in the comment:** unlike `deploy_pipeline_fix` (which has a
cloud-init mirror for fresh hosts), this resource is a *running-host-only* bridge;
fresh hosts get the handler from cloud-init write_files (`cloud-init.yml:206`)
directly. State that explicitly so a future reader does not add a redundant
cloud-init block.

### Phase 2 — Drift-guard test (infra-config-handler-bootstrap.test.sh)

Add `apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` — a static
drift-guard (no SSH, no root; the convention every sibling `.test.sh` follows,
e.g. `journald-config.test.sh`). Assertions:

- `server.tf` contains `resource "terraform_data" "infra_config_handler_bootstrap"`.
- Its `triggers_replace` references `infra-config-apply.sh` AND
  `cat-infra-config-state.sh` AND `local.hooks_json`.
- The resource's `remote-exec` block contains the three positive assertions
  (`infra-config-status`, `cat_infra_config_state_sh_b64`, and the webhook
  `is-active` check) — so a future edit that drops an assertion fails the guard.
- **Anti-regression for the gap:** assert the resource writes
  `/usr/local/bin/infra-config-apply.sh` (the file `deploy_pipeline_fix` cannot
  deliver) — the load-bearing invariant proving the handler now HAS a deploy path.

Wire it into `infra-validation.yml` as a new step (mirror the existing
`Run infra-config-apply.sh tests` step at `:142-143`):
`- name: Run infra-config-handler-bootstrap drift-guard` →
`run: bash apps/web-platform/infra/infra-config-handler-bootstrap.test.sh`.

### Phase 3 — Apply path (work item A: one-time recovery + work item B: standing)

See `## Infrastructure (IaC)` below for the full apply-path contract. Summary:
the resource is applied via the canonical `prd_terraform` triplet
`terraform apply -target=terraform_data.infra_config_handler_bootstrap` from an
egress IP ∈ `admin_ips` (the same admin-applied path the 7 SSH siblings already
use). Work item A is the first such apply; work item B is the standing behavior
(drift cron surfaces a replacement plan on each handler/hooks.json/status-script
edit). The routine webhook push (`deploy_pipeline_fix` via CI) continues for the
other 8 files unchanged.

### Phase 4 — Documentation + learning

- Update `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`
  with a closing note: the handler itself now has an SSH bootstrap path, so a
  handler edit is no longer a silent no-op on the host.
- The `server.tf` header comment on the new resource is the primary documentation
  (matches the in-file-comment convention of the 7 siblings).

## Files to Edit

- `apps/web-platform/infra/server.tf` — add
  `resource "terraform_data" "infra_config_handler_bootstrap"` (Phase 1).
- `.github/workflows/infra-validation.yml` — add the drift-guard test step
  (Phase 2), mirroring `:142-143`.
- `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`
  — closing note (Phase 4).

## Files to Create

- `apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` — static
  drift-guard (Phase 2).

(No new `.tf` root, no new variable, no new secret, no new SKILL.md, no new
agent — so the `hr-every-new-terraform-root` README gate, the
`tf-variable-no-operator-mint` gate, and the skill/agent budget gates do not
fire.)

## Open Code-Review Overlap

Two open `code-review` issues mention infra files (`#3216`
fix-dpf-regex-canary-bundle, `#2197` billing SubscriptionStatus) but neither
touches `infra-config-apply.sh`, `push-infra-config.sh`, the handler-bootstrap
resource, or the host-side `hooks.json` delivery path. **Disposition:
Acknowledge** — different concerns (canary-bundle regex; billing types); they
remain open and out of scope.

## Acceptance Criteria

### Pre-merge (PR / CI)

- [ ] `server.tf` defines `terraform_data.infra_config_handler_bootstrap` with an
  SSH `connection` block matching the 7 sibling shape (`type="ssh"`,
  `host=hcloud_server.web.ipv4_address`, `user="root"`, `agent=true`).
  Verify: `grep -A6 'infra_config_handler_bootstrap' apps/web-platform/infra/server.tf | grep -c 'type  = "ssh"'` ≥ 1.
- [ ] `triggers_replace` of the new resource references all three of
  `infra-config-apply.sh`, `cat-infra-config-state.sh`, `local.hooks_json`.
  Verify via the new test's `triggers_replace` assertion.
- [ ] The new resource writes `/usr/local/bin/infra-config-apply.sh` — the file
  `deploy_pipeline_fix` cannot deliver. Verify:
  `grep -q '/usr/local/bin/infra-config-apply.sh'` within the resource body (the
  test's anti-regression assertion).
- [ ] `infra-config-handler-bootstrap.test.sh` exists, is wired into
  `infra-validation.yml`, and passes:
  `bash apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` exits 0.
- [ ] `terraform validate` passes in `apps/web-platform/infra` (the new resource +
  heredoc interpolation parse). Verify:
  `terraform init -backend=false && terraform validate`.
- [ ] PR body uses `Ref #4811` and `Ref #4804` (NOT `Closes` — the host recovery
  + #4804 close happen post-merge in the admin apply, per
  `wg-use-closes-n-in-pr-body-not-title-to` ops-remediation guidance).

### Post-merge (admin apply)

- [ ] Run `terraform apply -target=terraform_data.infra_config_handler_bootstrap`
  via the canonical `prd_terraform` triplet (see Infrastructure → Apply path) from
  an egress IP ∈ `admin_ips`. **Automation: not feasible from CI** because the
  GitHub-hosted runner egress IP is not in `admin_ips` and is non-static (the 7
  existing SSH siblings are admin-applied for the same reason); the routine CI
  apply path stays scoped to `-target=terraform_data.deploy_pipeline_fix` (webhook,
  no SSH allowlist needed).
- [ ] Verify (automatable, no SSH): `GET /hooks/infra-config-status` → HTTP 200,
  and `GET /hooks/deploy-status` → `.journald_storage.persistent == true`. Same
  curl+HMAC+CF-Access shape as `apply-deploy-pipeline-fix.yml:329-384`.
- [ ] `gh issue close 4804 --reason completed` after the two verify curls pass
  (or let the existing `apply-deploy-pipeline-fix.yml` `#4804`-gated close step
  run on the next routine apply — both close-paths converge).

## Domain Review

**Domains relevant:** Engineering (infrastructure).

### Engineering

**Status:** reviewed
**Assessment:** Pure IaC reliability change. Adds one SSH `terraform_data`
resource that copies the established 7-sibling pattern (closest precedent:
`journald_persistent`). No new dependency, secret, port, or vendor. The only
sharp edge is the runner-egress-vs-`admin_ips` constraint (resolved by keeping
the new resource admin-applied and CI scoped to the webhook target), addressed in
Hypotheses L3 and the Infrastructure apply-path section. No Product, Legal,
Finance, Sales, Marketing, Ops-vendor, or Support implications.

### Product/UX Gate

Not applicable — Product domain not relevant. No new user-facing page, flow,
component, or copy. Mechanical escalation scan: no new file under
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Tier: NONE.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/server.tf` — adds
  `terraform_data.infra_config_handler_bootstrap` to the **existing** root (no new
  root → `hr-every-new-terraform-root` README gate does not fire).
- Providers: none new. Uses the existing `hcloud` provider attribute
  (`hcloud_server.web.ipv4_address`) and built-in `terraform_data` +
  `remote-exec`/`file` provisioners — same as the 7 siblings.
- Sensitive variables: none new. `local.hooks_json` (already rendered from
  `var.webhook_deploy_secret` at `server.tf:5-7`) is the only sensitive value
  touched; it is interpolated into a `remote-exec` heredoc the same way
  `var.resend_api_key` is interpolated in `disk_monitor_install` /
  `fail2ban_tuning` today. No `TF_VAR_*` addition.

### Apply path

**Chosen path: (b) idempotent SSH bootstrap on existing infra** — the resource is
SSH-direct (not cloud-init-only), so it applies to the already-running host.

Canonical `prd_terraform` invocation triplet (per
`knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`):

```bash
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
terraform init -input=false
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply -target=terraform_data.infra_config_handler_bootstrap -auto-approve -input=false
```

- **One-time (work item A):** the above, run from an egress IP ∈ `admin_ips`
  (same admin-applied path the 7 SSH siblings already use; the PR merge is the
  human authorization, the apply re-aligns the frozen host). Expected impact:
  sub-second webhook listener restart (RestartSec=5 covers the gap); blast-radius
  = webhook binary only (no container/app/Vector restart).
- **Standing (work item B):** `scheduled-terraform-drift.yml` surfaces a
  replacement plan on the next 12h tick whenever the handler/`hooks.json`/
  status-script changes; the same triplet re-delivers. The routine webhook push
  (`deploy_pipeline_fix`) continues for the other 8 files unchanged.
- **Pre-apply firewall check (mandatory, L3 per Hypotheses):** confirm the egress
  IP ∈ `admin_ips` (`curl -s https://ifconfig.me/ip`); a `connection
  reset`/`handshake failed` is admin-IP drift → `/soleur:admin-ip-refresh`.
- **Why not auto-apply from CI:** the GitHub-hosted runner egress IP is not in
  `admin_ips` and is non-static, so an SSH connection from CI would fail the
  handshake. This is exactly why the 7 existing SSH siblings are NOT in
  `apply-deploy-pipeline-fix.yml`'s `-target=` set (which only applies the webhook
  resource). Do NOT add this resource to that CI workflow.

### Distinctness / drift safeguards

- `dev != prd`: this stack is prod-only (`prd_terraform` Doppler config); there is
  no dev Hetzner host. N/A beyond the explicit `-c prd_terraform`.
- `lifecycle.ignore_changes`: NOT used on the new resource — it is a
  `triggers_replace`-driven replace-on-change resource (like all 7 siblings), so
  drift detection is the intended behavior, not noise. (Contrast: the
  `ignore_changes=[user_data]` on `hcloud_server.web` is the ROOT CAUSE this plan
  works around, not something to add here.)
- State storage: `local.hooks_json` (containing `var.webhook_deploy_secret`) lands
  in `terraform.tfstate` already (it does today via `deploy_pipeline_fix`'s
  `HOOKS_JSON_B64` env + cloud-init `hooks_json_b64`); the R2 backend is encrypted.
  No NEW secret enters state.

### Vendor-tier reality check

No vendor free-tier limit applies — Hetzner SSH + an existing webhook binary; no
new provider resource is created (the host already exists; this resource only
provisions files onto it). N/A.

## Research Insights (deepen-plan, 2026-06-02)

### Precedent-Diff Gate (Phase 4.4) — `journald_persistent` is the canonical form

The new resource is **not novel**; it copies the established SSH-provisioner shape.
`sed -n '222,282p' apps/web-platform/infra/server.tf` (`journald_persistent`)
confirms the pattern the plan adopts verbatim:

| Element | `journald_persistent` (precedent) | new `infra_config_handler_bootstrap` |
|---|---|---|
| `connection` block | `type="ssh"` / `host=hcloud_server.web.ipv4_address` / `user="root"` / `agent=true` (`:225-230`) | identical (copy verbatim) |
| sensitive-value delivery | `file` provisioner for the conf; SSH for the dir pre-create | `file` provisioner for the 2 scripts; `remote-exec` heredoc for `local.hooks_json` (secret-bearing, not on disk) |
| post-write restart | journald daemon restart via systemd (`:268`) | webhook listener restart via systemd |
| positive assertions | `test -d /var/log/journal`; header grep for `/var/log/journal`; an `is-active`==`active` check on the journald unit (`:275-279`) | `test -x .../infra-config-apply.sh`; `grep -q infra-config-status hooks.json`; `grep -q cat_infra_config_state_sh_b64 hooks.json`; an `is-active`==`active` check on the webhook unit |
| apply-path firewall note | admin-IP drift framing at `:217-221` | copy verbatim into the new resource's header |

**Sensitive interpolation precedent confirmed:** `disk_monitor_install` /
`resource_monitor_install` already interpolate `${var.resend_api_key}` into
`remote-exec inline` strings (`server.tf:90`, `:128`). Interpolating
`${base64encode(local.hooks_json)}` into a `remote-exec` heredoc is the same
established mechanism — Terraform permits sensitive interpolation in `remote-exec`
inline (it only refuses it in `local-exec`'s `command`). No novel pattern.

**Provider version check:** `hetznercloud/hcloud` is pinned `1.63.0`
(`.terraform.lock.hcl`); `hcloud_server.web.ipv4_address` is a long-stable
attribute — no version-pinned attribute drift. `terraform_data` +
`remote-exec`/`file` are Terraform core, version-independent.

### Network-Outage Deep-Dive (Phase 4.5) — L3→L7 verification status

Triggered by the `connection { type = "ssh" }` block (resource-shape trigger) and
the `handshake`/`connection reset` keywords in the Hypotheses section. Telemetry
`hr-ssh-diagnosis-verify-firewall applied` emitted at deepen time. Layer status:

- **L3 — firewall allow-list:** ADDRESSED at plan-design time, VERIFIED-AT-APPLY.
  SSH:22 → `var.admin_ips` confirmed at `firewall.tf:6-10`. The plan correctly
  routes a `connection reset`/`handshake failed` to admin-IP drift (NOT
  sshd/handler), with the `hcloud firewall describe` + `ifconfig.me/ip` diff and
  `/soleur:admin-ip-refresh` remediation. The egress-IP diff is the one artifact
  that can only be captured at apply time (it depends on the applying machine);
  the plan names the exact command, satisfying the checklist's "verified / not
  verified with a specific command" requirement. **This is the load-bearing
  apply-time precondition** — same as every one of the 7 SSH siblings.
- **L3 — DNS / routing:** N/A for the SSH hop (targets a Terraform IP attribute,
  not DNS). The verify-step HTTPS GET targets `deploy.${APP_DOMAIN_BASE}` — opt-out
  justified: the same endpoint serves `/hooks/deploy-status` in every prior apply.
- **L7 — TLS / proxy:** the verify curls go through the CF Tunnel + CF Access
  service token (same headers as `apply-deploy-pipeline-fix.yml:189-194`).
  Verified-stable by reuse of the working endpoint.
- **L7 — application (handler):** post-apply 404 on `/hooks/infra-config-status`
  ⇒ hooks.json not re-registered ⇒ bootstrap write or webhook restart failed;
  inspect via apply `remote-exec` stdout + handler `logger` lines.

**No gap to close before implementation** — the only unverifiable-at-plan-time
layer (L3 egress-IP diff) is correctly deferred to apply with a named command, per
the checklist's opt-out discipline.

### Verify-the-Negative Pass (Phase 4.45)

Every load-bearing negative claim probed against the codebase:

- "the handler is NOT in `push-infra-config.sh`'s payload" → CONFIRMED:
  `grep -c infra_config_apply apps/web-platform/infra/push-infra-config.sh` = 0.
  This is the gap; the new resource closes it.
- "no new data surface / no new secret enters state" → CONFIRMED: the resource
  writes the same files the webhook already writes; `local.hooks_json` already
  lands in `terraform.tfstate` today. The 5 `NEXT_PUBLIC_*` references under
  `infra/` are pre-existing cloud-init container env, untouched by this change.
- "webhook binary + `/etc/webhook` already exist on the running host (so no extra
  `depends_on`)" → CONFIRMED: cloud-init installs `/usr/local/bin/webhook`
  (`cloud-init.yml:431`), runs it against `/etc/webhook/hooks.json` (`:245`), and
  writes that dir (`:228`). On the existing host these are present; the bootstrap
  only overwrites the handler + hooks.json + status script.

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Research Insights (Precedent-Diff, Network-Outage
Deep-Dive, Verify-the-Negative) added; mandatory gates 4.6/4.7/4.8 passed.

### Gate results
- **4.4 Precedent-Diff:** PASS — `journald_persistent` is the canonical precedent;
  side-by-side diff added. Pattern is NOT novel.
- **4.5 Network-Outage Deep-Dive:** L3→L7 verified; only the apply-time egress-IP
  diff is deferred (with a named command), no pre-implementation gap.
- **4.6 User-Brand Impact:** PASS — section present, threshold `aggregate pattern`.
- **4.7 Observability:** PASS — all 5 fields present, non-placeholder, no SSH in
  `discoverability_test.command`.
- **4.8 PAT-shaped variable:** PASS — no PAT-shaped TF var / token; no GitHub
  infra-write auth introduced.

### Key findings carried into the plan
1. The fix is a verbatim copy of the 7-sibling SSH-provisioner pattern (lowest
   novelty); `journald_persistent` is the line-cited template.
2. The runner-egress-≠-`admin_ips` constraint is the single sharp edge; the plan
   keeps the resource admin-applied and CI scoped to the webhook target.
3. All three load-bearing negative claims confirmed against code.

## Observability

```yaml
liveness_signal:
  what: "/hooks/infra-config-status returns 200 with exit_code==0; /hooks/deploy-status returns journald_storage.persistent==true"
  cadence: "on every apply of the bootstrap resource (post-write verify), and continuously available as a no-SSH GET endpoint"
  alert_target: "apply-deploy-pipeline-fix.yml verify steps (:214-311 landed-files gate; :329-384 #4804 journald gate) fail-loud exit 1"
  configured_in: ".github/workflows/apply-deploy-pipeline-fix.yml + new resource's remote-exec positive assertions in server.tf"
error_reporting:
  destination: "terraform apply stdout (CI/admin log) via remote-exec positive assertions; on-host handler emits logger -t infra-config-apply to journald (Vector to Better Stack)"
  fail_loud: true
failure_modes:
  - mode: "SSH handshake fails (admin-IP drift)"
    detection: "terraform apply errors at connection with 'connection reset'/'handshake failed'"
    alert_route: "apply log non-zero exit; runbook admin-ip-drift.md; /soleur:admin-ip-refresh"
  - mode: "bootstrap writes files but webhook restart fails / hooks.json not re-registered"
    detection: "remote-exec positive assertion (webhook is-active) OR 'grep -q infra-config-status hooks.json' fails, apply exits non-zero"
    alert_route: "apply log non-zero exit"
  - mode: "handler delivered but still 404 on status endpoint post-apply"
    detection: "GET /hooks/infra-config-status != 200 in the no-SSH verify curl"
    alert_route: "apply-deploy-pipeline-fix.yml Verify-infra-config step exit 1 (false-success gate, #4804)"
logs:
  where: "host journald (logger -t infra-config-apply, visible via Vector journald source to Better Stack); terraform apply log in GitHub Actions / admin terminal"
  retention: "journald persistent (Storage=persistent, SystemMaxUse-bounded per journald-soleur.conf); GitHub Actions log 90d"
discoverability_test:
  command: "curl -s -H \"X-Signature-256: sha256=$(printf '' | openssl dgst -sha256 -hmac \"$WEBHOOK_SECRET\" | sed 's/.*= //')\" -H \"CF-Access-Client-Id: $CF_ACCESS_ID\" -H \"CF-Access-Client-Secret: $CF_ACCESS_SECRET\" https://deploy.${APP_DOMAIN_BASE}/hooks/infra-config-status"
  expected_output: "HTTP 200 with JSON {exit_code:0, files_written==files_total, files_failed:0}"
```

## Test Scenarios

Static drift-guard only (no live SSH in CI). `infra-config-handler-bootstrap.test.sh`:

1. **Resource present:** `server.tf` declares
   `terraform_data.infra_config_handler_bootstrap`. (RED first: assertion fails
   before Phase 1 lands.)
2. **Triggers complete:** `triggers_replace` references all three trigger inputs.
3. **Handler delivered (anti-regression):** resource body writes
   `/usr/local/bin/infra-config-apply.sh` — the load-bearing invariant.
4. **Positive assertions present:** remote-exec contains `infra-config-status`,
   `cat_infra_config_state_sh_b64`, and the webhook `is-active` check.
5. **Wired into CI:** `infra-validation.yml` has a step invoking this test.

Runner: plain `bash <file>.test.sh` (matches every sibling `.test.sh`; verified
against `infra-validation.yml:142-152`). No new test framework
(`command -v bats` not required; convention is `.test.sh`).

## Sharp Edges

- `local.hooks_json` is NOT a file on disk — it is a `templatefile()` render with
  `var.webhook_deploy_secret` interpolated. The new resource CANNOT use
  `provisioner "file" { source = ".../hooks.json" }` for it (the on-disk file is
  the `.tmpl`, not the rendered output — same trap documented in
  `push-infra-config.sh:12-15`). Push it via `remote-exec` base64 heredoc from
  `base64encode(local.hooks_json)`, exactly as `push-infra-config.sh` passes
  `HOOKS_JSON_B64`.
- **Runner egress ≠ `admin_ips`.** Do NOT add this SSH resource to
  `apply-deploy-pipeline-fix.yml`'s `-target=` set — the CI runner's egress IP is
  not allowlisted and is non-static. CI applies only the webhook target; this
  resource is admin-applied (like the 7 existing SSH siblings). Wiring it into CI
  would fail every run with a handshake error misdiagnosed as sshd drift.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This section is filled; threshold = `aggregate pattern`.)
- The new resource and `deploy_pipeline_fix` BOTH list the handler in
  `triggers_replace`, so a handler edit re-fires both. That is correct, not
  redundant: `deploy_pipeline_fix` re-pushes the other 8 files (its hash bump is
  what re-fires it), while THIS resource is the only one that actually delivers
  the handler. Document the dual-fire in both header comments so a future reader
  does not "dedupe" them.
- The webhook restart in this resource's `remote-exec` is SYNCHRONOUS (no
  `systemd-run --on-active=3s` defer needed). The handler's own self-restart must
  defer because the handler IS exec'd by the webhook binary (killing it kills the
  response). This SSH path is independent of the webhook process (SSH = root over
  :22; webhook = deploy user on 127.0.0.1:9000), so it can restart + assert
  active immediately. Note this in the header comment so a future reader does not
  copy the handler's deferred-restart dance unnecessarily.
