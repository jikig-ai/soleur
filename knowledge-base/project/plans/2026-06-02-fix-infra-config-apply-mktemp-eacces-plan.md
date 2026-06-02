---
title: "fix(infra): infra-config-apply.sh mktemp EACCES — stage in deploy-writable dir, escalate the move"
type: fix
issue: 4827
branch: feat-one-shot-4827-infra-config-mktemp
lane: single-domain
brand_survival_threshold: aggregate pattern
created: 2026-06-02
refs: [4804, 4811, 4814, 4805]
---

# fix(infra): infra-config-apply.sh mktemp EACCES — webhook (deploy user) cannot write root-owned dest dirs → deploy-config push lands 0 files

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Overview, Implementation Phases, Alternatives, Risks/Precedent-Diff, Network-Outage Deep-Dive
**Research method:** repo precedent-diff (`ci-deploy.sh` inngest-bootstrap escalation), verify-the-negative pass, hard-gate verification (4.6/4.7/4.8 all pass), network-outage deep-dive (4.5 fired: SSH-provisioner apply path).

### Key Improvements

1. **Canonical precedent found and cited.** `ci-deploy.sh:683-788` is the exact pattern this fix should mirror: the deploy user extracts to a **fixed deploy-writable path** (`/tmp/inngest-extract/`, NOT mktemp), guards against symlink/owner TOCTOU, then escalates a **single fixed-command** `sudo /usr/bin/bash <fixed-path>` via a wildcard-free `Cmnd_Alias INNGEST_BOOTSTRAP`. This collapses the plan's "helper vs N-aliases" open question: the helper form is the established house pattern. The dest-allowlist-in-root-helper design is confirmed correct.
2. **sudo-rs wildcard constraint is doubly-precedented.** `ci-deploy.sh:684-686` AND `deploy-inngest-bootstrap.sudoers:5-8` both document it. The plan's rejection of Option A′ (per-file `install` with mktemp-random source) is correct — the random `$tmp` path is the wildcard sudo-rs would reject.
3. **Atomicity refinement.** The precedent stages in `/tmp` (a fixed path) and the *helper* does the privileged write. For atomic same-fs rename, the helper itself should `mktemp` in the **dest dir** (it runs as root, so EACCES does not apply to it) and `mv` — i.e., move the mktemp from the deploy-user handler INTO the root helper. This is cleaner than staging in a separate fs + cross-fs copy. See updated Phase 2.
4. **Network-Outage Deep-Dive added** (4.5 fired): the fix ships via `terraform apply` on SSH-provisioner resources; admin-IP allowlist must be verified before apply per `hr-ssh-diagnosis-verify-firewall`.

### New Considerations Discovered

- **The root helper can mktemp in the dest dir directly.** The cleanest design is NOT "deploy-user stages in writable dir → escalate move". It is "deploy-user passes the decoded payload (or a deploy-writable temp) to a root helper that does mktemp-in-dest + chmod + chown + atomic mv". The root helper has no EACCES problem in `/usr/local/bin`. This eliminates the cross-filesystem atomicity concern entirely (AC7 / Phase 0 step 1 simplifies).
- **TOCTOU guards are mandatory** per the precedent (`ci-deploy.sh:693-702`): the helper must refuse to operate on a symlinked or wrong-owner staging path, since the deploy-writable staging dir is the one attacker-influenceable surface.
- **`cat-deploy-state.sh` in-repo already emits `journald_storage`** (`:48-128`, added #4792) — confirming AC11's premise that the *host's stale* copy is what lacks the field. The fix landing the repo version self-heals `/hooks/deploy-status`.

🐛 **Bug fix** · Issue #4827 · Ref #4804, #4811 (closed by #4814), #4805

> Lane note: no `spec.md` exists for this branch → `lane:` defaulted to `single-domain` (this is a pure infra-script + sudoers + IaC-delivery change; not a multi-domain feature). Recorded here per the plan-skill lane-default contract.

## Overview

`infra-config-apply.sh` — the `/hooks/infra-config` webhook handler — lands **0 files** on every push. It runs as `User=deploy` (per `webhook.service:11`) and `mktemp`s its staging file **inside each destination directory** (`infra-config-apply.sh:96`: `mktemp "${dest_dir}/tmp.infra-config.XXXXXX"`) to enable an atomic same-filesystem `mv` (`:127`). But every destination directory is `root:root 0755` on the host filesystem, so the non-root `deploy` user gets `EACCES` on the very first `mktemp` (`/usr/local/bin/ci-deploy.sh` is the first FILE_MAP entry). `set -euo pipefail` aborts; the EXIT trap writes `reason:"unhandled", files_written:0`.

This is **not** a systemd mount-namespace restriction: `webhook.service:40` `ReadWritePaths` *includes* `/usr/local/bin` (and `/etc/systemd/system`, `/etc/webhook`, `/etc/sudoers.d`). The systemd RW grant elevates the mount namespace to read-write but does **not** override DAC ownership — a non-root UID still cannot create a file in a `root:root 0755` directory. This is the distinguishing fact from #4492 (which *was* a namespace restriction).

The fix: stage the temp file in a **deploy-writable** directory, then escalate only the final atomic move to root via an allowlisted sudoers entry — mirroring the existing `deploy-inngest-bootstrap.sudoers` precedent. The handler must keep working unchanged in `TEST_DESTDIR` sandbox mode (no sudo, no install).

### Why this is the deepest layer of the #4804 freeze

- **#4805** (merged) made the handler fail-loud + land-partial.
- **#4811 → #4814** (merged) gave the handler a *deploy path* to the running host (the SSH `terraform_data.infra_config_handler_bootstrap` bridge in `server.tf:284`), so `/hooks/infra-config-status` now returns 200.
- With both fixed, the handler now actually runs end-to-end — and fails loud here, exposing that it could **never** write to root-owned dirs as the deploy user. This issue (#4827) removes that final blocker so config pushes land.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body) | Reality (verified) | Plan response |
|---|---|---|
| `mktemp` fails inside `/usr/local/bin/` only | Verified `:96`, but FILE_MAP (`:25-34`) targets **4** root-owned dest dirs: `/usr/local/bin`, `/etc/systemd/system`, `/etc/webhook`, `/etc/sudoers.d`. The EACCES fires on the first dir but the fix must cover **all four**. | Fix is dir-agnostic: stage in ONE deploy-writable dir, escalate the move per-dest. Do NOT special-case `/usr/local/bin`. |
| Option A: `sudo /usr/bin/install -o root -g root -m <mode> <tmp> <dest>` via allowlisted sudoers | `deploy-inngest-bootstrap.sudoers:5-8` documents that **Ubuntu 24.04 sudo-rs rejects wildcards in command arguments**. A single `install <tmp> *` rule is impossible; `<tmp>`, `<mode>`, `<dest>` all vary per file. | Pin **one fixed-form** escalated mover that takes NO caller-controlled path/mode wildcards. See "Sudoers design" below — a dedicated helper script invoked via a single pinned `Cmnd_Alias` is the sudo-rs-safe shape, not 8 per-file `install` aliases. |
| #4811 is the open blocker | #4811 was **closed by #4814** (merged). #4804 (parent) is still OPEN. | Use `Ref #4804` (do NOT auto-close — #4804 is the umbrella drift issue; this PR closes #4827 only). |
| Stage in `/mnt/data` or `/var/lib/inngest` | Both are in `ReadWritePaths` (`webhook.service:40`) and deploy-writable. `/var/lock` is also RW and is already where the handler writes its state file (`:40`). | Stage in `/var/lib/infra-config-staging` (deploy-owned, created at bootstrap) OR reuse an existing deploy-writable RW path. Decide in Phase 0 by checking on-host ownership; default to a dedicated `mktemp -d`-created subdir under a confirmed-writable RW path. |

## User-Brand Impact

**If this lands broken, the user experiences:** deploy-config pushes continue to land 0 files — `ci-deploy.sh`, `cat-deploy-state.sh`, `webhook.service` stay frozen at their last SSH-provisioned state, and the recurring deploy-pipeline-fix drift (`knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`) persists. No direct end-user-facing surface; the blast radius is the operator's deploy pipeline.

**If this leaks, the user's data is exposed via:** N/A — no user data flows through this handler. The only sensitivity is the sudoers grant: an over-broad escalation rule (wildcard path, caller-controlled `install` target) would let the deploy user write arbitrary root-owned files. The fix MUST keep the escalation pinned to the fixed FILE_MAP dest set.

**Brand-survival threshold:** aggregate pattern — a single failed push is recoverable (next push self-heals once the handler is fixed); the harm is the *aggregate* drift of the deploy substrate over time. Threshold `aggregate pattern` → no per-PR CPO sign-off; section present per gate.

threshold: aggregate pattern, reason: deploy-pipeline infra only; no user-data surface; harm accrues as drift not as a single-user incident.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Handler test suite green.** `bash apps/web-platform/infra/infra-config-apply.test.sh` exits 0 (all 12 existing tests still pass; the `TEST_DESTDIR` sandbox path must be unchanged — sudo/install only fire in prod mode).
- [ ] **AC2 — New test: prod-mode escalation path.** A new test asserts that when `TEST_DESTDIR` is empty (prod mode) AND a mocked `sudo`/helper is on PATH, the handler stages in the deploy-writable dir (not the dest dir) and invokes the pinned escalation mover with the correct `(tmp, dest, mode, owner)`. The test must FAIL against the current `mktemp "${dest_dir}/..."` form (RED-first per `cq-write-failing-tests-before`).
- [ ] **AC3 — Staging dir is deploy-writable & in ReadWritePaths.** `grep` confirms the chosen staging path appears in `webhook.service:ReadWritePaths` AND in `cloud-init.yml`'s mirror (`grep -n '<staging-path>' apps/web-platform/infra/webhook.service apps/web-platform/infra/cloud-init.yml`).
- [ ] **AC4 — Sudoers rule is wildcard-free (sudo-rs safe).** The new sudoers entry contains no `*` in any `Cmnd_Alias` command spec. Verify: `! grep -E 'Cmnd_Alias.*\*' apps/web-platform/infra/deploy-inngest-bootstrap.sudoers`. The escalation helper (or pinned install commands) take fixed paths only.
- [ ] **AC5 — Sudoers mirrored across all 3 delivery surfaces.** The new sudoers content is identical in `deploy-inngest-bootstrap.sudoers` (the file the handler writes via FILE_MAP), `cloud-init.yml` (fresh-host write_files at `:54`), AND is delivered to the running host by the existing SSH handler-bootstrap bridge (`server.tf:284`). `diff` the three sudoers bodies (or assert via the existing `infra-config-handler-bootstrap.test.sh` parity check — read it first).
- [ ] **AC6 — visudo validation still gates the sudoers install.** The existing visudo arm (`infra-config-apply.sh:110-120`) is preserved; the new sudoers content passes `visudo -cf` (test via the mocked visudo + a real `visudo -cf` smoke if available).
- [ ] **AC7 — Atomicity preserved.** The escalated move is still a same-filesystem atomic rename at the destination (no `cp` across filesystems mid-write). If the staging dir is on a *different* filesystem than the dests, the helper must `install`/`mv` within the dest filesystem — document which. Test 5 (`test_atomic_write`) stays green and a new assertion confirms no partial file at dest on a simulated mid-write failure.
- [ ] **AC8 — No new operator-only step.** The fix ships entirely through `terraform apply` of the existing handler-bootstrap bridge + deploy_pipeline_fix (both already re-fire on `infra-config-apply.sh` / sudoers hash change). No SSH-by-hand, no dashboard step. (See Infrastructure (IaC) section.)
- [ ] **AC9 — Lockfile / bash syntax.** `bash -n apps/web-platform/infra/infra-config-apply.sh` and `bash -n` on any new helper script pass; `terraform validate` (or `fmt -check`) passes for `server.tf` / `cloud-init.yml` edits if touched.

### Post-merge (operator)

- [ ] **AC10 — Live push lands all files.** After `terraform apply` delivers the fixed handler + helper + sudoers to the host, a `/hooks/infra-config` push (or the dual-fire from the handler-hash trigger) yields `GET /hooks/infra-config-status` → `{"exit_code":0,"files_written":7,"files_failed":0,"files_total":7}`. **NOTE (security review on #4827):** the sudoers grant was REMOVED from the webhook FILE_MAP (8→7 files) — letting the deploy-user escalation helper write a sudoers file is an unbounded privilege escalation (a deploy user could install `NOPASSWD: ALL`; visudo validates syntax, not policy). The sudoers is now delivered root-only (the SSH `infra_config_handler_bootstrap` bridge + cloud-init), so the webhook push count is **7**, not 8. Verify via the deploy webhook status endpoint (read-only `curl`, NOT ssh) per `hr-no-dashboard-eyeball-pull-data-yourself`.
- [ ] **AC11 — Downstream self-heal.** `GET /hooks/deploy-status` reports `journald_storage.persistent == true` (the freshly-landed `cat-deploy-state.sh` now emits the field that the stale 2026-05-21 version predated).

## Implementation Phases

### Phase 0 — Preconditions (verify on-host facts before coding)

1. Confirm the chosen **staging dir** is (a) in `webhook.service:ReadWritePaths`, (b) deploy-writable by ownership on the host, (c) on the **same filesystem** as the dest dirs (so the escalated mover can do an atomic rename, not a cross-fs copy). If no single existing RW path satisfies (c) for all dests, the helper must create a per-dest staging subdir inside each dest's filesystem — but since all 4 dest dirs are under `/` (root fs) and `/var/lock`, `/var/lib/inngest` are likely also root fs, a single staging dir under `/var/lib/` is expected to work. **Verify filesystem layout via the deploy-status webhook or the handler-bootstrap SSH apply output — do NOT add an ad-hoc ssh step.**
2. Read `apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` to learn the existing sudoers/handler parity-assertion shape; the new sudoers entry must satisfy it.
3. Confirm sudo-rs wildcard constraint by reading `deploy-inngest-bootstrap.sudoers:5-8` (done — pinned, no wildcards).

### Phase 1 — RED: failing test for the escalation path (`cq-write-failing-tests-before`)

Add a test to `infra-config-apply.test.sh` (`test_prod_mode_escalated_move` or similar) that:
- Runs the handler with `TEST_DESTDIR` **unset** (prod mode) but with mocked `sudo` + escalation helper + a writable fake-root layout on PATH.
- Asserts the staging `mktemp` targets the deploy-writable staging dir, NOT `${dest_dir}`.
- Asserts the pinned escalation mover is invoked once per file with the correct fixed args.
- This test FAILS against the current `mktemp "${dest_dir}/..."` form.

> Note: the existing 12 tests all run in `TEST_DESTDIR` sandbox mode where dest dirs ARE writable. They must stay green — the fix branches on `[[ -z "$DESTDIR" ]]` (the same predicate already gating `chown` at `:124`).

### Phase 2 — GREEN: handler change

In `infra-config-apply.sh`, replace the write mechanism (`:90-127`) so that:
- **Test mode** (`DESTDIR` non-empty): unchanged — `mktemp "${dest_dir}/..."` + `chmod` + `mv -f` (dest dirs are sandbox-writable; no sudo).
- **Prod mode** (`DESTDIR` empty): `mktemp` in the deploy-writable **staging dir**; `base64 -d` into it; `chmod $mode`; then the **escalated atomic install** to `$dest` with `$owner`/`$mode` via the pinned sudoers helper. Preserve the visudo arm for sudoers files (validate the temp before escalation). Preserve per-file failure accounting + state JSON.

**Sudoers design (sudo-rs-safe, the load-bearing decision):**
Because sudo-rs forbids argument wildcards, do NOT write 8 per-file `Cmnd_Alias install ... <dest>` rules (brittle; couples sudoers to FILE_MAP). Instead ship a tiny **fixed-path helper** — e.g. `/usr/local/bin/infra-config-install` (itself root-owned, delivered by the same FILE_MAP + bootstrap path) that reads the `(tmp, dest, mode, owner)` it should apply, **validates `dest ∈ the hardcoded FILE_MAP dest allowlist`** inside the helper (so the deploy user cannot redirect the install to an arbitrary root path even though sudo runs it as root), then performs `install -o <owner-user> -g <owner-group> -m <mode> <tmp> <dest>`. The sudoers entry is a single pinned alias:
```
Cmnd_Alias INFRA_CONFIG_INSTALL = /usr/local/bin/infra-config-install
deploy ALL=(root) NOPASSWD: INFRA_CONFIG_INSTALL
```
The dest-allowlist check lives in the **helper** (running as root), not in sudoers — this is what makes a wildcard-free single alias safe.

#### Research Insights (deepen-plan)

**Canonical precedent — mirror it exactly.** `ci-deploy.sh:683-788` (the inngest-bootstrap escalation) is the house pattern for "deploy user invokes a root operation via pinned sudoers":
- **Fixed path, not random.** The precedent stages at the *fixed* `/tmp/inngest-extract/` and the sudoers alias pins that exact path (`:684-687`). Mirror: pin `/usr/local/bin/infra-config-install` (a fixed path), and have the **root helper** do the mktemp — never put a `mktemp`-random path in the sudoers command spec.
- **Cleanest atomicity shape (refinement over the issue's Option A).** Because the helper runs as **root**, it has no EACCES problem in `/usr/local/bin` or any dest dir. So the helper itself should `mktemp` in the *destination* directory, base64-decode/`chmod`/`chown` there, then `mv` (same-fs atomic). The deploy-user handler just passes `(payload-or-deploy-temp, dest, mode, owner)`. This eliminates the cross-filesystem-copy atomicity concern entirely — preferred over staging in a separate fs and moving across.
- **TOCTOU guards are mandatory** (`ci-deploy.sh:693-702`): the helper MUST refuse a symlinked staging input and refuse a staging path whose owner ≠ deploy. The deploy-writable staging surface is the one attacker-influenceable input.
- **Failure surface mirrors the precedent's `final_write_state 1 "<reason>:<stderr_tail>"`** (`:786`): add `install_failed` / `install_rejected` reasons to the per-file state JSON so `/hooks/infra-config-status` surfaces the cause without SSH.

If a reviewer prefers a simpler **N-fixed-alias** form (one `Cmnd_Alias` per dest path), that is sudo-rs-safe ONLY if the *source* path is also fixed (the helper form avoids this by keeping the random temp inside the root helper). The helper form is recommended — it matches the precedent and keeps sudoers decoupled from FILE_MAP.

> **Chicken-and-egg note for the helper:** `/usr/local/bin/infra-config-install` is itself root-owned and must reach the host. Add it to FILE_MAP **and** to the handler-bootstrap bridge / cloud-init so it is present before the handler needs it. On the FIRST apply after this lands, the helper arrives via the SSH bootstrap bridge (root over SSH can write it), exactly as `infra-config-apply.sh` itself does. The handler does not need the helper to write the helper (the first delivery is SSH-root, not webhook-deploy).

### Phase 3 — Delivery surfaces (IaC; no operator SSH)

- Add the new sudoers `Cmnd_Alias INFRA_CONFIG_INSTALL` block to: `deploy-inngest-bootstrap.sudoers`, the `cloud-init.yml` mirror (`:54-69`), and ensure the SSH handler-bootstrap bridge (`server.tf:284`) re-fires (its `triggers_replace` already hashes `infra-config-apply.sh`; adding the helper to FILE_MAP changes the handler hash → re-fires).
- Add `infra-config-install` helper to FILE_MAP in `infra-config-apply.sh`, to `cloud-init.yml` write_files, and to whichever delivery resource is canonical (mirror the existing `cat-infra-config-state.sh` delivery shape).
- Update FILE_MAP count expectations: tests asserting `files_total == 8` become `9` (the helper is a 9th managed file) — OR deliver the helper purely via bootstrap/cloud-init and keep it OUT of the webhook FILE_MAP. **Decide in Phase 2** (keeping it out of FILE_MAP avoids the count churn but means the helper is bootstrap/cloud-init-only; keeping it in FILE_MAP makes it self-healing via webhook). Recommend: keep it OUT of the webhook FILE_MAP (cloud-init + SSH-bootstrap delivery), so the `files_total` count is unchanged and the helper-can't-deliver-itself paradox is avoided.

### Phase 4 — Verify

- Run the full handler test suite + any sibling infra tests (`*.test.sh` under `apps/web-platform/infra/`).
- `bash -n` all edited scripts; `terraform fmt -check` / `validate` on TF edits.

## Alternatives Considered

| Option | Verdict | Rationale |
|---|---|---|
| **A. Stage deploy-writable + escalate move via pinned helper** (chosen) | ✅ | Lowest blast radius; wildcard-free sudoers; dest-allowlist enforced in root-run helper; matches `deploy-inngest-bootstrap.sudoers` precedent. |
| A′. Per-file `Cmnd_Alias install -m <mode> -o <owner> <tmp> <dest>` (one alias per FILE_MAP entry) | ⚠️ fallback | sudo-rs-safe **only** if every arg is fixed — but `<tmp>` is `mktemp`-random, so the alias would need a wildcard on the source path → rejected by sudo-rs. Would require a fixed staging filename per dest (loses mktemp collision-safety). Inferior to the helper. |
| **B. `chgrp deploy` + `g+w` on the 4 dest dirs** | ❌ | Broadens write surface on `/usr/local/bin`, `/etc/systemd/system`, `/etc/sudoers.d` (security-sensitive). The deploy user could then write *any* file in those dirs, not just the FILE_MAP set. Rejected in issue and here. |
| **C. Run the whole write step under `sudo`** | ❌ | Either needs a wildcard sudoers rule (sudo-rs rejects) or runs the entire handler as root (defeats `User=deploy` hardening). |

## Risks & Mitigations — Precedent-Diff (deepen-plan Phase 4.4)

**Pattern: deploy-user → root escalated write via pinned wildcard-free sudoers.** This is NOT a novel pattern — the canonical precedent is `inngest-bootstrap` in `ci-deploy.sh:683-788`. Side-by-side:

| Dimension | Precedent (`ci-deploy.sh` inngest-bootstrap) | This fix (`infra-config-install`) |
|---|---|---|
| Staging path | Fixed `/tmp/inngest-extract/` (NOT mktemp — `:684-686`) | Deploy-writable staging dir OR payload passed to root helper; root helper does the in-dest mktemp |
| sudo-rs wildcard avoidance | `Cmnd_Alias INNGEST_BOOTSTRAP = /usr/bin/bash /tmp/inngest-extract/inngest-bootstrap.sh` (fixed path, no `*`) | `Cmnd_Alias INFRA_CONFIG_INSTALL = /usr/local/bin/infra-config-install` (fixed path, no `*`) |
| Privileged action | `sudo --preserve-env=... /usr/bin/bash <fixed>` (`:775`) | `sudo /usr/local/bin/infra-config-install` (root does chmod+chown+atomic-mv) |
| TOCTOU guard | symlink-refuse (`:693-697`) + owner-mismatch-refuse (`:698-702`) | **MUST mirror** — helper refuses symlinked/wrong-owner staging input |
| Dest pinning | the bootstrap script's targets are fixed in the image | helper validates `dest ∈ hardcoded FILE_MAP allowlist` before `install` |
| Serialization | "webhook serializes deploys; concurrent collisions not possible" (`:687`) | same — webhook handler is single-threaded per push |
| Failure surface | `final_write_state 1 "inngest_bootstrap_failed:<stderr_tail>"` (`:786`) | new `install_failed`/`install_rejected` reason in state JSON |

**Mitigation deltas vs. precedent:**
- The precedent's privileged target is a *whole bootstrap script baked into an OCI image*; this fix's privileged target is a *small fixed helper in the repo*. The helper's dest-allowlist (running as root) is the security boundary — it must hardcode the same 8 FILE_MAP dest paths so a compromised deploy user cannot redirect an `install` to an arbitrary root path.
- Because the **root helper** can `mktemp` directly in the (root-owned) dest dir, the cleanest shape moves the mktemp+chmod+chown+mv ENTIRELY into the helper, and the deploy-user handler only base64-decodes the payload into a deploy-writable temp and hands `(temp, dest, mode, owner)` to the helper. This sidesteps the cross-filesystem-atomicity risk (the helper's mktemp+mv are same-fs by construction).
- **No precedent gap:** every dimension of this fix maps to an established `ci-deploy.sh` line. Reviewers should scrutinize only the helper's dest-allowlist completeness and the TOCTOU guard parity.

## Network-Outage Deep-Dive (deepen-plan Phase 4.5)

This fix ships via `terraform apply` on `terraform_data.infra_config_handler_bootstrap` (`server.tf:284`) and `terraform_data.deploy_pipeline_fix` — both carry `connection { type = "ssh" }` + `provisioner "file"`/`remote-exec`. Per `hr-ssh-diagnosis-verify-firewall`, the apply-path L3 firewall allowlist is a hard apply-time dependency even though the *fix itself* is a filesystem-permission change with no network component.

| Layer | Verification status | Note |
|---|---|---|
| **L3 firewall allow-list** | Operator/CI egress IP MUST be ∈ `var.admin_ips` (`firewall.tf`) for the SSH handshake to succeed. | `server.tf:330` documents: a `connection reset by peer` here is **admin-IP drift** (fix: `/soleur:admin-ip-refresh`, runbook `admin-ip-drift.md`), NOT an sshd/handler fault. **This resource is admin-applied** — the GitHub-hosted runner egress IP is non-static and NOT in `admin_ips`, so do NOT add it to `apply-deploy-pipeline-fix.yml`'s `-target=` set. |
| **L3 DNS/routing** | `hcloud_server.web.ipv4_address` is the direct host IP (no DNS dependency for SSH). | N/A — direct IP. |
| **L7 TLS/proxy** | The webhook push path (`/hooks/infra-config`) goes through Cloudflare Tunnel; the SSH *delivery* path does not. | Not on the fix's critical path — the fix is delivered over SSH:22, verified over HTTPS status endpoint. |
| **L7 application** | After delivery, `/hooks/infra-config-status` (HTTPS, read-only) confirms `exit_code:0`. | AC10/AC11 verification is HTTPS `curl`, no SSH — per `hr-no-ssh-fallback-in-runbooks`. |

**Gap to close before apply:** confirm the applying operator's egress IP is in `var.admin_ips` (run `/soleur:admin-ip-refresh` if a handshake reset occurs). No service-layer (sshd/fail2ban) hypothesis is warranted — firewall + egress IP first.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/server.tf` (`terraform_data.infra_config_handler_bootstrap` at `:284`): re-fires automatically because its `triggers_replace` hashes `infra-config-apply.sh` (which changes). If the `infra-config-install` helper is delivered via this bridge, add it as a `provisioner "file"` mirroring the `cat-infra-config-state.sh` block (`:362`). No new providers, no new variables, no new secrets.
- `apps/web-platform/infra/cloud-init.yml`: add the helper to write_files + the new sudoers alias to the `deploy-inngest-bootstrap` mirror (`:54`). Fresh-host parity.

### Apply path
- **(b) cloud-init + idempotent bootstrap (default for existing infra).** Existing host: the SSH handler-bootstrap bridge + deploy_pipeline_fix re-fire on `terraform apply` (admin-applied — runner egress IP is not in `admin_ips`, per `server.tf:330` caveat). Fresh host: cloud-init write_files. Expected downtime: none beyond the handler's existing 3s deferred webhook self-restart.

### Distinctness / drift safeguards
- No `dev != prd` divergence (single prod host). The sudoers + helper are root-owned; the helper's dest-allowlist is the security boundary, not the sudoers wildcard. `terraform.tfstate` gains no new secrets (the helper + sudoers are non-secret; only `hooks.json` carries `var.webhook_deploy_secret`, unchanged).

### Vendor-tier reality check
- N/A — no third-party vendor resource created.

## Observability

```yaml
liveness_signal:
  what: "/hooks/infra-config-status returns {exit_code:0, files_written==files_total}"
  cadence: "on every deploy-config push + on handler-hash-triggered re-fire"
  alert_target: "deploy-status webhook consumer / CI verify gate on the push"
  configured_in: "cat-infra-config-state.sh (status endpoint) + infra-config-apply.sh state JSON"
error_reporting:
  destination: "journald (logger -t infra-config-apply) + state JSON reason field"
  fail_loud: "exit_code:1 + per-file reason (missing_env|base64_decode|visudo_validation_failed); a NEW eacces/install_failed reason if the escalated move fails"
failure_modes:
  - mode: "escalated install fails (sudoers missing/visudo-rejected/helper absent)"
    detection: "state JSON files[].reason == install_failed; exit_code 1"
    alert_route: "/hooks/infra-config-status non-zero exit_code; CI verify gate on push"
  - mode: "staging dir not writable (ReadWritePaths drift)"
    detection: "mktemp in staging dir fails; EXIT trap writes reason:unhandled"
    alert_route: "/hooks/infra-config-status reason:unhandled"
  - mode: "helper dest-allowlist rejects a dest (FILE_MAP/helper drift)"
    detection: "helper exits non-zero; state JSON reason:install_rejected"
    alert_route: "status endpoint non-zero"
logs:
  where: "journald on host (logger tag infra-config-apply); persistent (/var/log/journal exists)"
  retention: "journald default (host-configured)"
discoverability_test:
  command: "curl -s https://<deploy-host>/hooks/infra-config-status | jq '{exit_code,files_written,files_total}'"
  expected_output: '{"exit_code":0,"files_written":8,"files_total":8}'
```

## Open Code-Review Overlap

2 open code-review issues mention `server.tf` but neither touches the mktemp/escalation surface:
- **#3216** (regex-canary-bundle PR review, resolved inline) — **Acknowledge**: unrelated to the handler write path; no overlap with the files this PR edits beyond the shared `server.tf` filename.
- **#2197** (billing SubscriptionStatus refactor) — **Acknowledge**: false-positive substring match (`server.tf` appears incidentally); zero overlap with infra.

No fold-in; both deliberately left open (different concerns).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (webhook handler + sudoers + Terraform delivery). No user-facing surface, no schema/auth/payment/legal surface.

## Files to Edit

- `apps/web-platform/infra/infra-config-apply.sh` — branch the write mechanism on `DESTDIR`; prod-mode stages in deploy-writable dir + escalated install.
- `apps/web-platform/infra/infra-config-apply.test.sh` — add RED-first prod-mode escalation test; keep all 12 existing tests green.
- `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers` — add wildcard-free `INFRA_CONFIG_INSTALL` alias.
- `apps/web-platform/infra/cloud-init.yml` — mirror the sudoers alias (`:54`) + helper write_file.
- `apps/web-platform/infra/server.tf` — (if helper delivered via bridge) add helper `provisioner "file"` mirroring `cat-infra-config-state.sh`; re-fire is automatic via handler-hash trigger.
- `apps/web-platform/infra/infra-config-handler-bootstrap.test.sh` — extend parity assertions if the helper/sudoers parity shape changes (read first).

## Files to Create

- `apps/web-platform/infra/infra-config-install.sh` (the pinned root-run escalation helper with a hardcoded dest allowlist) — **only if** the chosen design uses the helper form (recommended). Plus its own `infra-config-install.test.sh` (allowlist-rejection + install-success assertions, sandbox-mode).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- **sudo-rs wildcard rejection is the trap.** Do NOT prescribe `sudo install <tmp> <dest>` with a wildcard sudoers rule — it parses `*` as a literal and the escalation silently never matches → the install fails at runtime, not at apply. The dest-allowlist MUST live in a root-run helper, not in the sudoers command spec.
- **Test sandbox must stay sudo-free.** The 12 existing tests run in `TEST_DESTDIR` where dest dirs are writable; branching on `[[ -z "$DESTDIR" ]]` (same predicate as the existing `chown` skip at `:124`) keeps them green. A naive "always escalate" change breaks the suite.
- **Helper-delivery paradox.** If the `infra-config-install` helper is added to the webhook FILE_MAP, the handler needs the helper to install the helper — circular on a host missing it. Deliver the helper via cloud-init + the SSH bootstrap bridge (root-writable) and keep it OUT of the webhook FILE_MAP, OR accept that the first delivery is always SSH-root (the bridge), never webhook.
- **Atomicity vs. cross-filesystem staging.** `mv`/`install` is atomic only within one filesystem. If the staging dir and a dest are on different filesystems, the rename degrades to copy+unlink (non-atomic, a reader can see a partial file). Phase 0 must confirm the staging dir shares the dest filesystem, or the helper must stage per-dest-filesystem.
- **`files_total` count churn.** If the helper enters FILE_MAP, every test asserting `files_total == 8` / `files_written == 8` flips to 9. The recommended design keeps the helper out of FILE_MAP to avoid this.

## Test Scenarios

1. **Prod-mode escalation (new, RED-first):** `TEST_DESTDIR` unset, mocked `sudo`+helper → staging in deploy-writable dir, pinned escalation invoked per file with correct args. Fails against current code.
2. **Test-mode unchanged:** all 12 existing sandbox tests green (happy path, missing_env, empty_env, visudo failure, atomic write, state-file variants, logger tag, restart ordering, exit trap, partial write).
3. **Helper dest-allowlist rejection (new, if helper form):** helper invoked with a dest NOT in its hardcoded allowlist → non-zero exit; handler records `install_rejected`.
4. **Sudoers wildcard-free assertion:** `! grep -E 'Cmnd_Alias.*\*' deploy-inngest-bootstrap.sudoers`.
5. **Sudoers tri-surface parity:** `deploy-inngest-bootstrap.sudoers` ≡ `cloud-init.yml` mirror ≡ bootstrap-bridge-delivered body.
