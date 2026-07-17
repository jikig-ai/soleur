---
title: "fix(security): LUKS-encrypt hcloud_volume.workspaces + retract the three unachievable privacy-policy clauses"
issue: 6588
date: 2026-07-17
lane: cross-domain
type: security-remediation
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_clo_signoff: true
adr: ADR-118 (provisional — re-verify ordinal at ship)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Ack rationale: Phase 2.8 was run and `soleur:engineering:cto` ruled the architecture
  (see "Architecture Decision"); an "Infrastructure (IaC)" section is present. Every host
  command named below is a step INSIDE `workspaces-cutover.sh`, executed by a
  `workflow_dispatch` job with credentials held off-host — the sanctioned
  `git-data-cutover.yml` pattern. This plan authors ZERO commands for a human to run
  (see "Automation feasibility"). The only human act is a risk-acceptance sign-off.
-->

# 🔒 fix(security): LUKS-encrypt `hcloud_volume.workspaces` (#6588)

## Overview

User source code sits **unencrypted at rest** on `hcloud_volume.workspaces` while three
published legal documents tell data subjects it is LUKS-encrypted. Issue #6588 mandates routing
to the CTO **before any terraform**. That happened; the ruling is ADR-118 (see Architecture Decision).

**This plan differs materially from the issue's framing.** Eight of the issue's premises are
false or incomplete, and four domain leaders — CTO, CLO, COO, CPO — converged *without contact*
on the same restructuring. Two findings are not in the issue at all:

> **(1) `cx33` is `available=false` in all three EU datacentres** (hel1-dc2, fsn1-dc14, nbg1-dc3),
> live-verified 2026-07-17 and corroborated in-repo at `tests/scripts/test-stock-preflight-gate.sh:11-13`.
> A `terraform -replace` destroys before it creates. Replacing web-1 today would succeed at the
> destroy, fail the create with `resource_unavailable`, and strand the platform **unrebuildable**.
> The issue's preferred approach (blue-green) is not merely expensive — it is **impossible**, and
> the existing `stock-preflight-gate.sh` (#6453) would correctly abort it.
>
> **(2) The fix creates a terminal failure mode worse than the one it closes** (CPO F4). Today's
> worst case: *someone else* reads the user's code. Post-LUKS worst case: **the user cannot** — a
> lost passphrase makes the volume unreadable forever. Key escrow is therefore not a nicety; it is
> a precondition **manufactured by the fix itself**.

The **additive-volume** design is the only one that can execute: it attaches a volume to the
already-running web-1, so no server is created or replaced and DC stock is never consulted.

> No `spec.md` exists for this branch (entered via one-shot; no brainstorm ran) — **lane defaulted to
> `cross-domain` (TR2 fail-closed)**. Four domain leaders were consulted, which the default correctly
> anticipated.

---

## Premise Validation (Phase 0.6)

Every premise cited by reference was checked. Eight did not survive.

| # | Issue claim | Verified reality | Response |
|---|---|---|---|
| P1 | "`hcloud_volume.format` is ForceNew — a naive apply **destroys the volume**" | **Red herring.** LUKS at Hetzner is **guest-side**; `format` never changes. `git-data-luks.tf:11-14` verbatim: *"encryption-at-rest is GUEST-SIDE LUKS, NOT an hcloud_volume attribute. There is no hcloud 'encrypted' flag"* — its LUKS volume keeps `format = "ext4"`. | Reframe (→ P2) |
| P2 | *(not named)* | **The real data-loss mechanism**: `cloud-init-git-data.yml:159` `if ! cryptsetup isLuks "$DEV"; then luksFormat`. On a **populated plaintext** device `isLuks` is false ⇒ `luksFormat` ⇒ **wipes live user code**. Safe only because git-data's volume is born fresh. | Never point the guard at the live volume |
| P3 | Clause in 2 docs + 2 mirrors (4 files) | **7 canonical body sites + 3 `Last Updated` headers, ×2 mirrors = 20 sites**, across **three** docs. `gdpr-policy.md` missed entirely. Worse: `privacy-policy.md:488` + `gdpr-policy.md:318` (+ mirrors) carry the git-data-host clause with **no "LUKS" token** — invisible to the issue's own framing. | Union-anchor grep; **never** `grep LUKS` |
| P4 | "see `specs/feat-6538-web2-fsn1-orphan/decision-challenges.md` DC-1" | Exists **only on unmerged PR #6568**, not `main`. Content + 2026-07-23 trigger confirmed on the PR branch. | Sequencing dep |
| P5 | "Blue-green… aligns with the zero-downtime precedent in #5887" | **Inverts it.** #5887's norm: *"Default to the zero-downtime path… Downtime is acceptable only with explicit justification + a bounded window + operator sign-off."* Justification exists; the machinery does not (**no LB**, `server.tf:186-187`; `web["web-1"]` pinned **23× / 5 files**; **#6459 is OPEN with "ADR needed"**). | Option 1 rejected |
| P6 | `#6570 #6459 #5274 #6538` blockers | All **OPEN**. `#5887` **CLOSED**. `#6426` **MERGED**. `#6568` is an **open PR**. | Hold |
| P7 | DC-1 cites "the Art. 13(3) precedent set in PR #4455 — *'encryption at rest is being rolled out'*" | PR #4455 is MERGED but is *"feat(legal): PR-1 Flagsmith sub-processor disclosure"*. **That wording is not in it.** The *mechanism* is reusable; the citation is loose. CLO separately ruled the **Art. 13(3) anchor wrong** → **Art. 12(1) + 5(1)(a)**. | Do not propagate |
| P8 | *(implicit)* "the claim misleads users" | **There are ZERO beta users** (`roadmap.md` Current State; #1439 "recruit 10 solo founders" still **OPEN**). The volume holds the **operator's own** dogfooding workspaces. The threshold is met, but no data subject has yet been misled. | Makes retraction **free now** |

**Own-capability claims** (`hr-verify-repo-capability-claim-before-assert`): I asserted "worktrees
rehydrate from GitHub ⇒ re-clone instead of rsync" — **refuted** (R1). I asserted the cx33 finding
was novel — **it is corroborated in-repo**. I asserted `provisionWorkspace` was the "Start Fresh"
card — **CPO corrected me** (R1a).

---

## Research Reconciliation — Spec vs. Codebase

| # | Claim | Reality | Response |
|---|---|---|---|
| R1 | *(my hypothesis)* "re-clone instead of rsync" | **Refuted — the volume is SOLE-COPY.** `refs/checkpoints/<convId>` (`server/inflight-checkpoint.ts`) snapshots uncommitted agent edits; its own header notes *"Greenfield ref namespace — `git grep "refs/checkpoints"` returns 0 elsewhere."* Every push refspec is namespace-scoped (`refs/heads/*`); **no `--mirror`, no `push --all`** ⇒ checkpoints sit outside **both** `origin` **and** git-data. `session-sync.ts`: `ALLOWED_AUTOCOMMIT_PATHS = [/^knowledge-base\//]` — only KB is ever pushed. | Freeze + **filesystem-level** copy is mandatory |
| R1a | *(my claim)* "'Start Fresh' has no remote" | **Wrong label, broader exposure** (CPO, verified): the *Start Fresh card* → `startSetup(data.repoUrl, …, "start_fresh")` (`connect-repo/page.tsx:210`) **creates a real GitHub repo** — it has an origin. The remote-less `provisionWorkspace` (`git init`, no `remote add`) is the **signup/auth-callback** path (`app/(auth)/callback/route.ts:380`, `app/api/workspace/route.ts:55`). ⇒ **every signup materialises a remote-less workspace.** | Sole-copy stands; label corrected |
| R2 | ADR-068 §1 *"GitHub remains the durable rehydration source"* | **Walked back by its own §(d)** (2026-07-02): *"a fresh GitHub clone can be strictly behind the user's latest tip."* `GIT_DATA_STORE_ENABLED` is **OFF** in prod; git-data's refspec is `heads`+`tags` ⇒ checkpoints never replicate. | Cite §(d), not §1 |
| R3 | *(issue)* implies the git-data LUKS work is a reusable asset | **`git-data-cutover.sh` cannot run today.** It invokes two units — `soleur-drain.service` (:205,:218) and `soleur-web.service`; `grep -rln` finds each in **that file only**. Neither is defined anywhere. The app is a bare `docker run -d --name soleur-web-platform` (`cloud-init.yml:768-769`), not a systemd unit. | A **shape to copy**, never a script to invoke |
| R4 | *(implicit)* "a cloud-init edit delivers LUKS to the hosts" | **False.** `server.tf:254-256` `ignore_changes = [user_data, ssh_keys, image, placement_group_id]` ⇒ **no diff at all** on web-1/web-2. Only a fresh **create** consumes it. | Cutover delivers to the live host; cloud-init covers the fresh-host path |
| R5 | *(CTO F7 + CPO G6; I confirmed independently)* | **`/mnt/data` has no working reboot path today.** `cloud-init.yml:568-569`: `mount /dev/disk/by-id/scsi-0HC_Volume_* /mnt/data \|\| true` then `echo '<same glob> … ext4 defaults 0 2' >> /etc/fstab`. **fstab does not expand globs** ⇒ inert. No `nofail`, no `grep -q` guard, and `\|\| true` **swallows mount failure**. Contrast git-data's correct `:170`. Consequences: a reboot leaves the container writing workspaces to the **root disk**; a second attached volume makes the glob match **two devices**. | **Phase 1** — prerequisite, not nice-to-have |
| R6 | *(CTO F8)* "reuse `verify_set_identity`" | **Does not port.** `git-data-cutover.sh:246` verifies `git rev-list --all \| sort \| sha256sum` — sound for **bare** repos (all state = refs/objects). `/workspaces` holds **working trees**: uncommitted edits, untracked files, `refs/checkpoints/*`. A rev-list identity **passes while dropping exactly the sole-copy data in R1**. | Filesystem-level verify (Phase 4) |
| R7 | AC: "every `var.web_hosts` member" | `{web-1: hel1, web-2: fsn1}` today; **PR #6568 destroys web-2** ⇒ post-merge `{web-1}`. Encrypting a volume scheduled for destruction is waste. | Sequence after #6568 |
| R8 | *(implicit)* "add LUKS to cloud-init.yml" | **Byte-budget blocked.** `WEB_GZIP_BUDGET = 21_900` (`cloud-init-user-data-size.test.ts:79`); `server.tf:157` records *"under ~300 bytes of headroom"*, cloud-init.yml *"effectively comment-frozen"*. | **Bake** into `soleur-host-bootstrap.sh` (ADR-080) |
| R9 | *(implicit)* "add the volume to the allow-list" | `apply-web-platform-infra.yml:29-35` **OPERATOR_APPLIED_EXCLUSION** excludes `hcloud_server.web`, `hcloud_volume.workspaces`, `_attachment.workspaces`. Only `hcloud_firewall.web`/`_attachment.web` are on the merge path (`:388-389`). | Dedicated `workflow_dispatch` job |
| R10 | `/mnt/data` == workspaces | Also `/mnt/data/plugins/soleur` (`:573`, seeded `:661-666`) — **re-derivable** (`docker cp` + `.seed-complete`). | Rsync all (free); irreplaceable set = `/mnt/data/workspaces` |
| R11 | *(COO)* ledger rates | `expenses.md` encodes a stale `~0.044/GB` across **5 volume rows**; live `GET /v1/pricing` (2026-07-17) = **0.0572 EUR/GB/mo** ⇒ **~$2.33/mo understated**. | **Out of scope — P2, separate PR** |
| R12 | *(CPO)* roadmap Current State | **Stale** — says 43 open, milestone API says 58 (dated 2026-05-25). | Noted; not blocking |

---

## Hypotheses

**Gate fired** (Phase 1.4): the issue names `terraform apply` against `hcloud_server.web`, whose
definition carries 11 `provisioner "remote-exec"` blocks with `connection { type = "ssh" }`. Per
`hr-ssh-diagnosis-verify-firewall`, L3→L7 order is mandatory before any service-layer hypothesis.

**This is not an outage diagnosis — nothing is down.** The checklist applies to the plan's
*apply-time SSH dependency*: Phases 1/3/4 orchestrate over SSH from CI, so an L3 failure strands
the cutover **mid-freeze**, container stopped, site down. Each layer is a **pre-flight gate inside
the workflow**, not a diagnosis.

1. **L3 — firewall allow-list.** `[gate]` The runner's egress is not in `var.admin_ips`; it must
   reach web-1 via **Cloudflare Access SSH** (`cloudflare_zero_trust_access_application.ssh` +
   `..._service_token.ci_ssh`), as `git-data-cutover.yml` does. **Verification (Phase 3, pre-freeze):**
   assert SSH reachability; abort if absent. Artifact: probe exit code + resolved endpoint in the run
   log. *Skipped ⇒* freeze engages, delta rsync cannot connect, site down with no orchestrator.
2. **L3 — DNS / routing.** `[gate]` `app.soleur.ai` is a proxied singleton A record to
   `hcloud_server.web["web-1"]` (`dns.tf`). **Verification:** `dig +short +time=5 +tries=2
   app.soleur.ai` resolves to CF edge **and** private `10.0.1.10` answers, **before** the freeze.
   *Skipped ⇒* ADR-115's fresh-host private-NIC-down class (`2026-07-07-immutable-redeploy.md`)
   misread as a cutover fault.
3. **L7 — TLS / proxy.** `[opt-out with artifact]` No cert/SNI change in scope; the tunnel connector
   is untouched (`web_tunnel_connector = each.key == "web-1"`, unchanged). *Artifact:* the canary's
   `curl -sS -o /dev/null -w '%{http_code}' https://app.soleur.ai/api/health` → 200 post-restart,
   which exercises the full HTTPS path.
4. **L7 — application layer.** `[gate]` The freeze's straggler assert is `fuser -vm /mnt/data` /
   `lsof +f -- /mnt/data` returning **empty** — proof the service is not touching the mount.
   **Absence here is the intended signal.** *Skipped ⇒* rsync a live tree, silently lose the delta.

> **Ordering discipline honoured.** L3 gates run in Phase 3 (pre-freeze, zero downtime). Only after
> both pass does Phase 4 engage the freeze. **A cutover that cannot reach the host must fail before
> it stops the container, never after.**

---

## Architecture Decision (ADR/C4)

`wg-architecture-decision-is-a-plan-deliverable` — the ADR is **in-scope work for this plan**, not
a follow-up issue.

### ADR

**Create `ADR-118-luks-at-rest-for-the-live-workspaces-volume.md`.** Provisional ordinal (ADR-117 is
max); `/ship`'s ADR-Ordinal Collision Gate re-verifies against `origin/main`. **If renumbered, sweep
this plan + `tasks.md` + every AC naming it in the same edit**
(`2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md`).

The full CTO ruling is captured verbatim at
`knowledge-base/project/specs/feat-one-shot-6588-luks-workspaces-volume/adr-118-seed.md` (written by
this plan; Phase 2's first task copies it to the decisions directory). The seed keeps the ADR a
**deliverable in hand** rather than a deferred promise, while respecting this phase's write boundary.

**One-line decision:** *Encrypt the live `/workspaces` volume by attaching a fresh LUKS-formatted
volume additively, freezing writers by stopping the app container, two-pass rsync with
filesystem-level verification, repointing the mapper to `/mnt/data`, and retaining the plaintext
volume under `prevent_destroy` as the sole rollback backstop — never by replacing the host, which DC
stock makes impossible.*

**Rejected alternatives** (full text in the seed):

| Alternative | Verdict |
|---|---|
| **1. Blue-green host** (issue's preferred) | **Rejected — currently impossible.** cx33 `available=false` in all 3 EU DCs; `-replace` destroys first ⇒ strands the fleet **unrebuildable**. Also needs a nonexistent LB, unwinding 23 `web["web-1"]` pins, and an ADR for #6459 that was never written. Most expensive **and** least safe. Inverts #5887's own norm. |
| **2. Additive volume + freeze + rsync + repoint** | **ADOPTED.** The only design where the source is never written to and stays mountable at every instant — the only acceptable property when the data has no second copy (R1). No server create ⇒ stock gate never consulted. |
| **3. Accept + re-scope the claim** | **Rejected as primary** (encryption is affordable), **ADOPTED for the three unachievable clauses** — they can never be true, so encrypting while leaving them standing merely *relocates* the false claim. |
| **4a. In-place `cryptsetup reencrypt --encrypt --reduce-device-size`** | **Rejected** — the strongest alternative, omitted by the issue. Genuinely simpler (same volume, same TF address, no state surgery). But it **operates on the sole copy**: LUKS2's journal is crash-*resumable*, not crash-*proof*; a `resize2fs` shrink + header insert on the only extant copy turns every recoverable failure into an unrecoverable one. Adding a snapshot to make it safe pays option 2's cost while re-opening the exposure. |
| **4b. fscrypt / ext4 native / gocryptfs** | **Rejected** — metadata leakage, and the published wording says *"LUKS"*. The claim is the artifact being made true. |
| **Build `soleur-drain.service`** | **Rejected** — buys nothing. A drain sheds traffic to peers; there is no LB and no peer. For a singleton, drain ≡ stop, and **stop is strictly stronger**. Its absence is evidence the git-data script was written against a fleet shape that never existed. |
| **Pre-cutover Hetzner snapshot as backstop** | **Rejected — CTO and COO converged independently.** A retained plaintext snapshot manufactures an indefinitely-retained unencrypted copy of user source code *inside the very issue that exists to eliminate them*. Cost (EUR 0.0143/GB/mo) was never the objection. See **Cross-Domain Disagreement** for how CPO's C3 backup condition is satisfied without one. |

### C4 views

**All three model files read in full** — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — per the C4 completeness mandate. A keyword grep is **not** evidence.

Enumerated:
- **External human actors:** none added. The data subject (operator/user) is modelled; no new correspondent/reviewer/recipient.
- **External systems / vendors:** **Hetzner** (block storage) and **Doppler** (passphrase custody) — both already modelled. **No new vendor, no new sub-processor** (same account, same EU region).
- **Containers / data stores:** the `/workspaces` volume — **this is the C4 edit**: its description must state LUKS-at-rest once Phase 4 lands.
- **Access relationships:** a **new edge — Doppler → web-host boot-time passphrase**. The host's `/mnt/data` mount now **depends on Doppler reachability at boot**: a real architectural dependency, not a detail. The C4 must **not** acquire a git-data host or cross-host edge — the same phantom the legal docs assert.

**Verdict: C4 impact is real and in scope** — one element-description correction + one new
Doppler→web-host edge (+ its `views.c4` `include` so it renders). Sequenced with Phase 4. Run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` — a `view include` naming an
undefined element fails there, not at `tsc`.

### Sequencing

The decision is only *true* after Phase 4. ADR-118 is authored **now** with **`status: adopting`**,
flipped to `accepted` on soak-pass. It is **not** postponed to its own issue.

---

## User-Brand Impact

**If this lands broken, the user experiences:** their workspace is gone or truncated — uncommitted
edits, untracked files, and `refs/checkpoints/*` (the agent's in-flight work snapshotted on
disconnect) are **unrecoverable**, because `session-sync.ts` only ever pushed `knowledge-base/**`
and every signup-provisioned workspace has no remote at all. They open Soleur and their code is
missing, with nowhere to get it back from. **Or — the mode the fix itself creates (CPO F4) — the
volume is intact and encrypted, and the passphrase is gone: their code is unreadable forever.** A
botched `-replace` is worse still: **web-1 cannot be rebuilt** (cx33 stock), so the failure mode is
not "workspace gone" but "the product is gone."

**If this leaks, the user's source code is exposed via:** a Hetzner volume snapshot, a mis-scoped
detach, or physical-media recovery of `soleur-web-platform-data` — today plaintext ext4. BYOK keys
are separately AES-256-GCM encrypted; **repository contents are not.** The compounding harm is the
published contradiction: under **Art. 34(3)(a)** encryption exempts the controller from notifying
data subjects; plaintext means **no exemption**, so the Art. 33 filing would state "data was in
plaintext" while the live privacy policy states "LUKS-encrypted" — and the supervisory authority
receives both documents.

**Brand-survival threshold:** `single-user incident`

⇒ `requires_cpo_signoff: true` — **obtained, APPROVE WITH CONDITIONS** (see Domain Review).
`user-impact-reviewer` is invoked at review time per `plugins/soleur/skills/review/SKILL.md`.

> **Scope note (P8):** with **0 beta users**, today's "single user" is the operator himself. The
> threshold is met on data-criticality, not on population.

---

## Observability

```yaml
liveness_signal:
  what: "luks-monitor.sh — asserts (a) blkid TYPE=crypto_LUKS on the workspaces device, (b) findmnt -no SOURCE /mnt/data == /dev/mapper/workspaces, (c) mountpoint -q /mnt/data (root-disk fallthrough detector)"
  cadence: "every 5 min (systemd timer; mirrors disk-monitor.service/.timer, cloud-init.yml:151-185)"
  alert_target: "Sentry (host-side emit via the baked SOLEUR_SENTRY_DSN already wired at soleur-host-bootstrap.sh:44-46,263) + Better Stack heartbeat"
  configured_in: "apps/web-platform/infra/luks-monitor.{sh,service,timer}; baked per ADR-080"
error_reporting:
  destination: "Sentry — op slug `op:workspaces-luks-drift`"
  fail_loud: true   # NEVER an unencrypted fallback (NFR-026; mirrors cloud-init-git-data.yml:158)
failure_modes:
  - mode: "Volume is plaintext ext4 (LUKS never applied, or a future volume born plaintext)"
    detection: "blkid TYPE != crypto_LUKS — emitted FROM the host, in-surface"
    alert_route: "Sentry P1 + Better Stack heartbeat miss"
  - mode: "/mnt/data mounted from the raw device, bypassing the mapper (the #5274 data-stranding trap)"
    detection: "findmnt -no SOURCE /mnt/data != /dev/mapper/workspaces"
    alert_route: "Sentry P1 — the silent-plaintext-writes mode"
  - mode: "/mnt/data not mounted at all => container writes workspaces to the ROOT DISK (the live R5 bug)"
    detection: "mountpoint -q /mnt/data fails"
    alert_route: "Sentry P1 + disk-monitor's existing root-disk fill alarm as a second signal"
  - mode: "Doppler unreachable at boot => passphrase absent => mapper never opens => nofail leaves /mnt/data unmounted"
    detection: "same mountpoint probe + a distinct reason=doppler_unreachable field on the boot emit"
    alert_route: "Sentry P1 — MUST page; a silent degraded boot is the worst mode"
  - mode: "Passphrase lost/unescrowed => volume unreadable forever (CPO F4 — the mode the fix creates)"
    detection: "Phase 3 escrow proof (read back from Doppler + unlock a throwaway volume) is a BLOCKING pre-cutover gate; post-cutover, mapper-open failure at boot"
    alert_route: "Sentry P1 + cutover aborts before the freeze"
  - mode: "Cutover aborts mid-freeze (container stopped, site down)"
    detection: "Better Stack uptime monitor on app.soleur.ai (uptime-alerts.tf) + the workflow's own non-zero exit"
    alert_route: "Better Stack alert + workflow failure annotation"
logs:
  where: "journald -> Vector -> Better Stack Logs source 2457081, host_name=soleur-web-platform (#6396)"
  retention: "per existing Better Stack plan; no change"
discoverability_test:
  command: "gh workflow run workspaces-luks-verify.yml && gh run watch  # plus: curl -sS -H \"Authorization: Bearer $BS\" https://uptime.betterstack.com/api/v2/monitors/<id> | jq -r .data.attributes.status"
  expected_output: "workflow conclusion=success; monitor status == \"up\""
```

**Discriminating fields (§2.9.2 — blind-surface extension).** The volume is a surface the operator
cannot inspect without a login, so a single boolean is insufficient. Every `luks-monitor` event
carries **`{device_type, mount_source, mountpoint_ok, passphrase_source, host}`** so the competing
failure modes are discriminated **in one event** — `device_type=ext4` vs `mount_source=/dev/sdb` vs
`mountpoint_ok=false` vs `passphrase_source=absent` name different root causes that a lone
`luks_ok=false` would collapse.

> `hr-no-ssh-fallback-in-runbooks` does **not** bar an SSH-orchestrated cutover —
> `git-data-cutover.yml` (workflow_dispatch, creds off-host) is the sanctioned precedent. It bars the
> **runbook** from saying "log in and check." Hence the standing probe: the runbook's verification is
> a workflow + an API read, never a login.

### Soak Follow-Through Enrollment (§2.9.1)

Phase 5 gates on a soak before the plaintext volume is wiped and ADR-118 flips `adopting → accepted`.
That is a time-gated close criterion ⇒ enrollment is **mandatory**, not prose.

**Retention = 7 days** (CPO C7/G7 is blocking and overrides COO's 72h — see Cross-Domain Disagreement).

- **Script:** `scripts/followthroughs/workspaces-luks-soak-6588.sh` — exit 0 iff, over the full 7d
  window: zero `op:workspaces-luks-drift` Sentry events (`start=` pinned strictly **after** the
  Phase-4 canary timestamp, mirroring `reconcile-ff-only-sentry-4977.sh`) **and** the Better Stack
  monitor reports `status == "up"`.
- **Tracker directive:** `<!-- soleur:followthrough script=scripts/followthroughs/workspaces-luks-soak-6588.sh earliest=<canary+7d> secrets=SENTRY_API_TOKEN,BETTERSTACK_API_TOKEN -->` + the `follow-through` label.
- **Wiring:** add `SENTRY_API_TOKEN`, `BETTERSTACK_API_TOKEN` to `.github/workflows/scheduled-followthrough-sweeper.yml` if absent.

Enforced fail-closed by `/ship` Phase 5.5 + `ship-soak-followthrough-gate.sh`.

---

## Infrastructure (IaC)

### Terraform changes

| File | Change |
|---|---|
| `apps/web-platform/infra/workspaces-luks.tf` **(new)** | `random_password.workspaces_luks` (length 40, `special = false` — shell/stdin-safe for the `printf %s \| cryptsetup --key-file -` pipe, ~238 bits); `doppler_secret.workspaces_luks_key`; `doppler_service_token.workspaces_luks` (`access = "read"`); `hcloud_volume.workspaces_luks` + `hcloud_volume_attachment.workspaces_luks`; **`lifecycle { prevent_destroy = true }` on the OLD volume** (CPO G7). **Shape mirrors `git-data-luks.tf`.** |
| `apps/web-platform/infra/server.tf` | Phase 5 only: `moved` + name convergence after the old volume is released. |
| `apps/web-platform/infra/soleur-host-bootstrap.sh` | LUKS block (baked, ADR-080) for the **fresh-host** path + the **pre-container fail-closed mount gate** (CPO G6 synthesis). |
| `apps/web-platform/infra/cloud-init.yml` | **Phase 1**: replace the `scsi-0HC_Volume_*` glob at `:568-569` with an explicit volume-ID device + `nofail` + `grep -q` guard; **remove the `\|\| true` failure-swallow**. |

**Provider pins:** `hcloud ~> 1.49` (lock resolves `1.63.0`), `doppler`, `random` — all existing. No
new providers.

**Sensitive variables: none added.** The passphrase is **Soleur-generated** (`random_password`) per
`hr-tf-variable-no-operator-mint-default` — **no human-minted secret, no `TF_VAR_*`** — so the
merge-triggered apply cannot fail on an unprovisioned no-default var (the #5468 sequencing trap does
not apply). Delivered to the host **only** as the Doppler-injected env `WORKSPACES_LUKS_KEY`; never
argv, never baked into `user_data`.

> **Doppler config precondition.** `git-data-luks.tf` records that the Doppler provider manages
> environments-and-configs as a unit and the existing configs are not TF-managed, so `prd_git_data`
> had to pre-exist. **This plan does not inherit that manual step.** Phase 2 re-verifies whether a
> dedicated config is creatable in-band (`doppler_config` resource) —
> `automation-status: UNVERIFIED — /work MUST attempt in-band creation before any handoff`.
> An a-priori "dashboard-only" assertion is **not** acceptable evidence
> (`2026-06-17-vendor-dashboard-mint-presumed-playwright-automatable.md`).

### Apply path

**(b) cloud-init + idempotent cutover script**, delivered by a **dedicated `workflow_dispatch` job** —
*not* the merge-triggered allow-list.

- `hcloud_volume.workspaces` / `_attachment.workspaces` / `hcloud_server.web` are excluded by
  **OPERATOR_APPLIED_EXCLUSION** (`apply-web-platform-infra.yml:29-35`). **Do not add them.**
- New job `workspaces-luks-cutover` on the `git_data_host_replace` template (~`:2158`), with a sourced
  structured-plan gate and **no `[ack-destroy]` bypass**.
- The volume create/attach is a **create, not a destroy** ⇒ it does not trip the destroy-guard. But
  `host_creates` (#6416) fires on a pure `+ create` of `hcloud_server`/`hcloud_volume` on the per-PR
  path — hence the dedicated job. **Verify the counter's exact resource-type scope at /work**; if
  `hcloud_volume` is in scope, the dispatch job must be the only apply path.
- **`stock-preflight-gate.sh` does not apply** — verified: it scopes to `.server_types.available`
  (`tests/scripts/lib/stock-preflight-gate.sh:19,73`), i.e. **servers only**. No server is created, so
  it never fires. **This is precisely why the additive design is executable while every
  server-creating design is currently (and correctly) blocked.**
- **Blast radius:** Phases 1-3 = **zero downtime**. Phase 4 = **≤20 min budget** (target ~10; CPO
  authorises a ≤2h hard-abort ceiling).

### Distinctness / drift safeguards

- `lifecycle.ignore_changes = [user_data, ssh_keys, image, placement_group_id]` **stays**.
  `plugins/soleur/test/terraform-target-parity.test.ts:1188` asserts `entries` contains `user_data` as
  a non-vacuity check — **dropping it reds that test.**
- **State divergence (Phases 4→5) is real and must not be assumed away.** The live host ends on
  `soleur-web-platform-data-luks`; a from-empty apply would create `soleur-web-platform-data`.
  `hr-fresh-host-provisioning-reachable-from-terraform-apply` is satisfied in **behaviour** (both paths
  end LUKS-encrypted) but **not in state** until Phase 5 converges: release `prevent_destroy` →
  destroy old → `state rm` → `moved` → rename (hcloud volume `name` **is** updatable in place, not
  ForceNew — verify against provider 1.63.0 at /work).
- **Secrets land in `terraform.tfstate`** — the R2 backend is encrypted; `use_lockfile = false`, so the
  shared `terraform-apply-web-platform-host` concurrency group is **load-bearing**. The new job MUST
  join it.

### Vendor-tier reality check

Hetzner block storage has **no free tier and no tier gate** — pay-per-GB at **EUR 0.0572/GB/mo net**
(live-verified 2026-07-17). No `count = var.x_paid_tier ? 1 : 0` needed. **Volume creation is not
subject to the cx33 server-stock constraint**; its only capacity failure mode is
`no_space_left_in_location` (a location-scoped storage-pool error, distinct from the server-placement
`resource_unavailable` that wedged the fleet on 2026-07-13) — real but low-frequency for 20 GB in hel1.

---

## Downtime & Cutover

**Justification (required by the #5887 norm; CPO C8).** The norm says *default* to zero-downtime, not
*always*. Here zero-downtime is rejected on four grounds:

1. **Zero external users** (P8) — availability nobody consumes. The entire benefit accrues to a user
   set of size 0.
2. **Downtime buys data integrity.** A quiesce window copies a volume **at rest** — no in-flight
   session writes, no live `refs/checkpoints/` mutation mid-rsync. A zero-downtime design must copy
   live data and reconcile deltas: **strictly more ways to lose sole-copy data.**
3. **Zero-downtime is currently impossible anyway** — it needs a host create, and cx33 is unorderable
   in all 3 EU DCs.
4. **#5887's precedent was won for a reboot/wedge** (`state mv`, `ignore_changes`) — an availability
   problem with no data-integrity dimension. Different class.

**Window:** ≤20 min budget, ~10 target, **≤2h hard abort** (CPO ceiling). **Sign-off** on engaging the
freeze is the single human decision in the plan (see Automation feasibility).

**Rollback:** the retained plaintext volume, `prevent_destroy = true`, attached-unmounted for 7 days.
Inside the freeze rollback is unmount-mapper → remount-plaintext → restart (seconds, byte-identical).
**After traffic resumes, rollback is no longer lossless** — new writes land on LUKS only. **Rollback
authority expires at canary-pass: a one-way door**, stated as such in the runbook, never implied.
**Rehearsed, not documented** (CPO G8) — Phase 3 proves the old volume remounts and serves.

---

## Implementation Phases

> **Phase order is load-bearing.** R5 (pin the mount) precedes the additive volume because the device
> glob is what makes a second volume ambiguous. Escrow proof (G5) precedes the freeze because F4 is
> terminal. The ADR precedes the code because it is the contract the code implements.

### Phase 0 — BLOCKED on PR #6568 (no code)

- [ ] Confirm PR #6568 merged; re-derive `var.web_hosts` (expect `{web-1}`); confirm
      `hcloud_volume.workspaces["web-2"]` destroyed. **If #6568 stalls, STOP and re-price** — two-host
      is worse than 2× (web-2's volume would need the same cutover for a host being deleted). *(CPO C9)*
- [ ] **Highest-value check in the plan** (CTO open risk 1): verify the **live** host's actual
      `/etc/fstab` + mount state. R5 is a *code-shape* finding. **If web-1 has been rebooted since first
      boot and `/mnt/data` is unmounted, the workspace data is not where this plan assumes and the
      sequencing is invalid.** Read-only, via the sanctioned CI path.

### Phase 1 — Pin the mount, fail-closed (ships alone; independently a latent-bug fix) *(CPO C6)*

- [ ] Replace `cloud-init.yml:568-569` glob with explicit volume-ID device + `nofail` + `grep -q`
      guard (git-data's `:170` form). **Remove `|| true`.**
- [ ] **G6 synthesis** (resolves a CTO↔CPO conflict — see Cross-Domain Disagreement): keep `nofail`
      in fstab so a Doppler outage is a **degraded, pageable boot rather than a hang**, AND add a
      **fail-closed gate before `docker run`** that refuses to start the container unless
      `findmnt -no SOURCE /mnt/data` == the mapper. Boot completes and is observable; **the app never
      silently writes to the root disk.**
- [ ] Deliver to the live host through the same channel the cutover uses (`ignore_changes` ⇒ no live
      effect from the merge alone).
- [ ] Re-run `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` (budget).

### Phase 2 — ADR-118 + C4 + LUKS in the baked bootstrap + mutation-tested drift guard

- [ ] **First task:** copy `specs/…/adr-118-seed.md` → `knowledge-base/engineering/architecture/decisions/ADR-118-luks-at-rest-for-the-live-workspaces-volume.md` (`status: adopting`). Re-verify the ordinal against `origin/main`.
- [ ] C4: element-description correction + Doppler→web-host boot edge + `views.c4` include. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] LUKS block into `soleur-host-bootstrap.sh` (ADR-080). `--key-file -` via **stdin**, never argv. Fail loud on empty key.
- [ ] `workspaces-luks.tf` (mirror `git-data-luks.tf`), incl. `prevent_destroy` on the old volume.
- [ ] **`apps/web-platform/infra/workspaces-luks.test.sh`** — mutation-tested drift guard modelled on
      `git-data-luks.test.sh`. **Each predicate re-run against a deliberately broken copy MUST flip to
      failing.** Assert on **content anchors, not line numbers** (`cq-cite-content-anchor-not-line-number`).
      **The AC's "a plaintext volume must go RED" is the mutation case.** Register in
      `.github/workflows/infra-validation.yml` (pattern `:356-385`).

### Phase 3 — Additive volume + L3 gates + escrow proof + rollback rehearsal + live bulk rsync (ZERO downtime)

- [ ] New `workspaces-luks-cutover` dispatch job (template `git_data_host_replace`).
- [ ] Apply: create + attach `hcloud_volume.workspaces_luks`.
- [ ] **L3 gates (Hypotheses 1-2) — abort before any freeze if either fails.**
- [ ] **G5 escrow proof (BLOCKING, CPO C5):** read the passphrase back from Doppler and **prove it
      unlocks a throwaway volume** before any cutover step. F4 is terminal; an unproven key is not a key.
- [ ] `prepare_luks_target`: luksFormat the **FRESH** volume (`isLuks` guard safe **by construction** —
      the volume is empty). Open mapper at a staging path.
- [ ] **G2 pre-cutover manifest (CPO C4):** enumerate every workspace; `git rev-parse` **every** ref
      **including `refs/checkpoints/*`**; `git status --porcelain` dirty-file inventory → counts + SHAs.
- [ ] **G8 rollback rehearsal:** prove the plaintext volume remounts and serves **before** it is needed.
- [ ] Pass-1 bulk `rsync -aHAX` against the **live** tree. No user impact.

### Phase 4 — The freeze (≤20 min budget, ≤2h hard abort, sign-off gated)

- [ ] Cutover script halts `webhook.service` (so a CI deploy cannot restart the container mid-rsync).
- [ ] `docker stop soleur-web-platform` — the sole writer (`cloud-init.yml:776`).
- [ ] **G4: assert `fuser -vm /mnt/data` / `lsof +f -- /mnt/data` EMPTY.** Verifiable, not advisory.
- [ ] Pass-2 delta `rsync -aHAX --delete` against the quiesced tree.
- [ ] **Filesystem-level verify (R6):** `rsync -aHAX --numeric-ids --checksum --delete --dry-run SRC/ DST/`
      prints **zero transfers**, + file-count + total-byte asserts. **Not a rev-list identity. Not a
      count-match.** Re-assert `chown 1001:1001 /mnt/data/workspaces` (`:581`, must match the Dockerfile UID).
- [ ] **G3: explicit `refs/checkpoints/*` carriage assertion** — re-verify the G2 manifest and assert
      **equality**, with checkpoint refs named as their own check. *(Highest-probability silent loss.)*
- [ ] `repoint_luks_mount`: mapper → **`/mnt/data`** (the original mountpoint — `:776` hardcodes
      `/mnt/data/workspaces` into the bind mount, so the **#5274 data-stranding trap** is sharper here).
      Rewrite fstab (backup first) + `findmnt` assert.
- [ ] `docker start`; cutover script resumes `webhook.service`.
- [ ] **Canary:** `blkid TYPE=crypto_LUKS` **AND** `findmnt -no SOURCE /mnt/data == /dev/mapper/workspaces`
      **AND** an app-level workspace read **AND** `https://app.soleur.ai/api/health` == 200.
- [ ] **Any failed assert ⇒ rollback** to the plaintext mount (rehearsed in Phase 3).

### Phase 5 — 7d soak → converge → wipe → (only then) the LUKS-clause flip

- [ ] Plaintext volume stays **attached-unmounted, `prevent_destroy`, un-wiped** for **7 days** (CPO C7).
- [ ] Soak-pass ⇒ release `prevent_destroy` → double-gated wipe (canary_ok **AND** confirm_wipe) →
      Hetzner API delete.
- [ ] TF convergence: destroy old → `state rm` → `moved` → rename.
- [ ] ADR-118 `adopting` → `accepted`.
- [ ] **PR 2 (legal):** flip the LUKS clause to present tense; amend Art. 30 PA limb (g); **re-pin
      `apps/web-platform/lib/legal/legal-doc-shas.ts` ×3**.

---

## The legal track — DECOUPLED (a deviation from the issue's AC)

> **The issue's AC requires the doc correction only after live verification, and the three
> unachievable clauses corrected in the same PR. CLO and CPO both ruled against it, and the CTO's
> evidence independently supports it. Recorded as a User-Challenge — see Decision Challenges.**

**Why decouple** — three independent arguments:

1. **Legal.** No state of the world makes the three clauses true. Gating their retraction behind a
   migration keeps three falsehoods published **for a reason that does not exist**.
2. **Safety — decisive.** Gating the doc fix on the migration makes **legal-accuracy pressure the
   forcing function on a data-loss-capable cutover** over sole-copy data (R1). Decoupling removes
   schedule pressure from precisely the operation that must not be rushed. **The two goals are
   aligned, not in tension.**
3. **Product (CPO).** **The claim's audience does not exist yet** — 0 beta users (P8). Retraction is
   **free right now** and gets monotonically more expensive with every founder #1439 recruits.
   **#1439 and #6588 are on a collision course**: the first signup is the moment a victimless
   inaccuracy becomes an actual breach against a real data subject. `brand-guide.md` mandates
   *"Honest, actionable"* and **"Trust scaffolding"** against the #1 objection across 8/10 personas
   (*"What if the output is wrong?"*). For a brand whose thesis is *"give us your source code"*, an
   over-claimed encryption control is the worst credibility asset to be caught holding.

### PR 1 — docs-only, THIS WEEK, zero infra dependency *(CPO C1/C2)*

- [ ] Retract clauses (a) git-data host, (b) cross-host TLS, (c) cross-host membership re-verification
      across **all 20 sites**. **Per-site edits with per-site anchors** — the wording is **not uniform**
      (`dpd:276` *"host↔host traffic is TLS-encrypted (in transit)"* vs `gdpr:44` *"traffic between the
      hosts is encrypted in transit with TLS"*), so a literal find/replace **silently misses sites**.
- [ ] **Temporally qualify** the LUKS clause (mechanism per PR #4455; **anchor in Art. 12(1) +
      Art. 5(1)(a)**, *not* Art. 13(3) — CLO correction; and per P7, #4455's exact wording is **not** a
      template — author fresh).
- [ ] **CREATE** the missing Art. 30 Processing Activity for workspace git-data storage at its **true
      current state** ("plaintext ext4 on `hcloud_volume.workspaces`; LUKS planned, Ref #6588"). Writing
      the true state **is** the Art. 5(2) fix — accountability working, not a confession. **Verify the
      next free PA ordinal** (`grep "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail`) — PA-16 collided once before.
- [ ] Amend §Cross-Cutting TOMs (`article-30-register.md:443`) with an explicit Hetzner-volume limb —
      **including today's explicit negative. Silence is what failed.**
- [ ] Correct `knowledge-base/legal/compliance-posture.md:78` — the Hetzner DPA row asserts the
      **never-born CAX11** as covered scope (**Art. 28(3)**). Add a #6588 Active Item.
- [ ] **Mirror-hole gate (blocks PR 1).** `legal-doc-shas.ts` hashes **canonical only**;
      body-equivalence is `terms-and-conditions`-only by **explicit deferral**
      (`check-tc-document-sha.sh:11-19`); `legal-doc-consistency.test.ts` asserts heading-sequence +
      Last-Updated parity — **neither changes on a clause retraction**. ⇒ **edit canonical, forget the
      mirror, CI goes green while soleur.ai serves the false text.** Add a **targeted, mutation-tested
      content-assertion test**: for all 3 docs in **both** canonical and mirror, each retracted clause's
      anchor **absent** + qualified LUKS wording **present**; re-inserting a clause into a **mirror**
      must go **RED**. **Do NOT** attempt the full 8-doc body-equivalence remediation (separate scope;
      the pre-existing benign drift must be cleaned first).
- [ ] Re-pin `legal-doc-shas.ts` ×3 (`sha256sum docs/legal/<doc>.md` — **no regen script exists**).
- [ ] Bump `Last Updated` in **lockstep** canonical + mirror (parity test asserts equality).
- [ ] **Close DC-1** — it closes when PR 1 merges, **not** when #6588 does (CPO C2).

**CLO warning carried forward:** at PR time, verify every implementation claim in the **new** prose
against the actual terraform/cloud-init (the #4353/#4558 drift class). **The retraction must not
assert a new false thing** — replacing three falsehoods with a fourth is a live risk when prose is
written to sound reassuring. Do **not** write "host-local NVMe" without checking `server.tf`.

---

## Cross-Domain Disagreement — resolved

Two genuine conflicts surfaced between independently-spawned leaders. Both are resolved here; neither
is papered over.

### D1 — CPO C3 ("verified-restorable backup before encryption, BLOCKING") vs. CTO/COO ("no snapshot")

- **CTO:** *"Do NOT take a pre-cutover Hetzner snapshot as a backstop: a retained plaintext snapshot
  re-creates the exact Art. 32 exposure this ADR closes."*
- **COO** (independently): *"It was never the cost that made snapshotting wrong; it's that it
  manufactures an indefinitely-retained unencrypted copy of user source code inside the very issue
  that exists to eliminate them."*
- **CPO:** *"Encryption of unbacked sole-copy data is a net downgrade in user outcomes."*

**Resolution — both are right; they answer different questions.** CPO's condition is
**outcome-shaped** ("no path may make F1-F4 reachable"), not mechanism-shaped; CPO explicitly says
*"I am not prescribing the mechanism."* The **additive design already produces a two-copy state**: the
old volume retains the original while the new volume receives the copy. That IS an off-volume,
verified-restorable backup — and it is *better* than a snapshot, because it is a live, mountable
device that Phase 3 **rehearses** (G8) rather than a blob nobody has ever restored.

C3 is therefore satisfied by **G7 + G8** (retained volume under `prevent_destroy`, 7 days, rollback
rehearsed) **without** a snapshot's indefinite plaintext copy. What CPO added that the CTO's design
lacked is folded in as blocking work: **G5 escrow proof** (F4 — the terminal mode the CTO never
addressed) and **G8 rehearsal**. **Retention takes CPO's 7 days over COO's 72h** — the marginal
security cost of 4 extra days of retained plaintext is small; the data-loss protection is not, and
CPO's condition is blocking.

### D2 — CTO `nofail` ("degraded boot, not a hang") vs. CPO G6 ("a failed unlock must halt the boot")

**Resolution — synthesis, in Phase 1.** Keep **`nofail`** in fstab so a Doppler outage yields a
**degraded, pageable boot rather than a hang** (an unbootable sole host with no LB and no rebuild path
is catastrophic), AND add a **fail-closed gate before `docker run`** that refuses to start the
container unless `/mnt/data` resolves through the mapper. Boot completes and is observable; **the app
never silently writes to the root disk** — which is CPO's actual concern (F5), and is a *stronger*
guarantee than halting the boot, because it also covers the mapper-opened-but-wrong-device case.
Neither leader had this alone.

---

## Acceptance Criteria

### Pre-merge (PR 1 — legal, decoupled)

- [ ] **AC1** Union-anchor grep returns **zero** occurrences of the three retracted clauses across all 6 files:
      `grep -rcEi "git.data host|dedicated host for per-workspace|re-verified when a session|TLS-encrypted \(in transit\)|encrypted in transit with TLS" docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` → `0` for each.
      *(Scope verified at plan time: these anchors appear **only** as the claims being retracted. If /work finds a legitimate occurrence, invert to a guardrail-presence assertion per `cq-assert-anchor-not-bare-token`.)*
- [ ] **AC2** LUKS clause present and **temporally qualified** in all 6 files (anchor: the qualifier phrase, **not** "LUKS").
- [ ] **AC3** Mirror content-assertion test exists, registered in CI, **mutation-tested**: re-inserting a retracted clause into a **mirror** goes RED.
- [ ] **AC4** `tc-document-sha-guard` CI job green with 3 re-pinned SHAs.
- [ ] **AC5** `Last Updated` identical canonical↔mirror for all 3 docs (`legal-doc-consistency.test.ts` green).
- [ ] **AC6** Art. 30 register contains a new PA for workspace git-data storage whose limb (g) states the **plaintext** current state + `Ref #6588`; §Cross-Cutting TOMs carries an explicit Hetzner-volume limb.
- [ ] **AC7** `compliance-posture.md` CAX11 DPA-scope row corrected; #6588 Active Item present.
- [ ] **AC8** PR body carries the **Tier 1** classification. CLO attestation DISCHARGED at ship Phase 5.5 → `knowledge-base/legal/audits/` (**auto-routed, not a human task** — `2026-05-18-clo-attestation-auto-route-instead-of-human-task.md`).
- [ ] **AC9** DC-1 closed by PR 1's merge.
- [ ] **AC10** `Ref #6588` — **not `Closes`** (`type: security-remediation`; the fix executes post-merge, so `Closes` would auto-close before remediation runs).

### Pre-merge (PR 2 — infra)

- [ ] **AC11** `ADR-118-*.md` exists with `status: adopting`, a `## Decision`, and a `## Alternatives Considered` table naming blue-green, in-place `reencrypt`, fscrypt, option 3, `soleur-drain.service`, and the snapshot — **with the cx33-stock rationale**.
- [ ] **AC12** C4: `model.c4` carries the Doppler→web-host boot edge, `views.c4` includes it; `c4-code-syntax.test.ts` + `c4-render.test.ts` green.
- [ ] **AC13** `workspaces-luks.test.sh` registered in `infra-validation.yml` and green. **Mutation case: a `format = "ext4"`-only volume with no LUKS block goes RED.**
- [ ] **AC14** `cloud-init.yml` contains **no** `scsi-0HC_Volume_*` glob and **no `|| true`** on the mount; the fstab line carries an explicit volume ID + `nofail` + a `grep -q` guard.
      `grep -c 'scsi-0HC_Volume_\*' apps/web-platform/infra/cloud-init.yml` → `0`.
- [ ] **AC15** The pre-`docker run` fail-closed mount gate exists and is mutation-tested (mount `/mnt/data` from the raw device ⇒ container start refuses).
- [ ] **AC16** `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` green (budget 21,900).
- [ ] **AC17** `terraform-target-parity.test.ts` green (`user_data` still in `ignore_changes`).
- [ ] **AC18** `bash tests/scripts/test-all.sh` — read the **`N/N suites passed`** summary, not just the exit code (orphan-suite class, `2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md`).
- [ ] **AC19** No `TF_VAR_*` added: `git grep -c 'variable "workspaces_luks' apps/web-platform/infra/variables.tf` → `0` (passphrase is `random_password`, per `hr-tf-variable-no-operator-mint-default`).
- [ ] **AC20** `terraform plan` for the dispatch job shows **`0 to destroy`** and **no destroy/replace of `hcloud_volume.workspaces["web-1"]`** — the #5887 runbook's STOP condition. Old volume carries `prevent_destroy = true`.

### Post-merge (automated — dispatch job)

- [ ] **AC21** Cutover workflow conclusion `success`.
- [ ] **AC22 (G5, blocking pre-freeze)** Escrow proof recorded: passphrase read back from Doppler **unlocked a throwaway volume** before any cutover step.
- [ ] **AC23 (the issue's "verified live, not by inspection")** From the **host**, in-surface:
      `blkid -s TYPE -o value <dev>` == `crypto_LUKS` **AND** `findmnt -no SOURCE /mnt/data` == `/dev/mapper/workspaces` **AND** `mountpoint -q /mnt/data`. Emitted to Sentry with the 5 discriminating fields; asserted by the workflow.
- [ ] **AC24 (G2/G3)** Pre- and post-cutover ref manifests are **equal**, with `refs/checkpoints/*` asserted as its **own named check**; dirty-file inventory matches.
- [ ] **AC25 (G4)** Straggler assert recorded empty before the delta pass.
- [ ] **AC26** Filesystem verify printed **zero** transfers; file-count + byte-count match.
- [ ] **AC27** `curl -sS -o /dev/null -w '%{http_code}' https://app.soleur.ai/api/health` == `200` post-restart; Better Stack monitor `status == "up"`.
- [ ] **AC28** Downtime measured ≤ **20 min** (workflow-emitted freeze-start/freeze-end timestamps); hard abort at 2h.
- [ ] **AC29 (G8)** Rollback rehearsal recorded green in Phase 3.
- [ ] **AC30** 7d soak follow-through enrolled with the `follow-through` label + directive; on soak-pass: `prevent_destroy` released, plaintext volume deleted, TF state converged, ADR-118 → `accepted`, PR 2 (legal present-tense flip + SHA re-pin) opened.

**Automation feasibility (§2.10 gate).** Every step routes through the cutover `workflow_dispatch`
job, `gh` CLI, or an API read. **No human-run command is authored anywhere in this plan.** The one
genuinely un-automated decision is the *authorization to engage the freeze* —
`Automation: not feasible because engaging a bounded-downtime window on the sole production host is a
human risk-acceptance, not a technical step`. The Doppler-config precondition is marked
`automation-status: UNVERIFIED — /work MUST attempt in-band creation before any handoff`.

---

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| 1 | **The live `/etc/fstab` + mount state are unverified** — R5 is a code-shape finding. If web-1 rebooted since first boot, the data is not where this plan assumes. | **Phase 0 gate.** Highest-value check; invalidates sequencing if wrong. Read-only. |
| 2 | **F4 — passphrase loss makes the volume unreadable forever.** A terminal mode *created by the fix*. | **G5 escrow proof is a blocking pre-freeze gate** (AC22). Doppler custody mirrors `git-data-luks.tf`; rotation is `-replace`-explicit. |
| 3 | **Rollback expiry is a one-way door.** Lossless only inside the freeze. | Stated in the runbook (not implied). 7d retention under `prevent_destroy` + rehearsed rollback + recurring canary. **Residual risk accepted.** |
| 4 | **web-1 cannot be rebuilt** (cx33 `available=false`, all 3 EU DCs). If it dies mid-cutover, the platform is gone. | "Destroy nothing"; no server create/replace anywhere; plaintext volume retained; `stock-preflight-gate.sh` already blocks the dangerous class. |
| 5 | The cutover **edits an already-malformed fstab** on a host with no LB and no peer. | Phase 1 fixes fstab **first, standalone**. Backup before rewrite; `findmnt` assert after; `nofail` makes a bad entry a degraded boot, not a hang. |
| 6 | **Doppler unreachable at boot** ⇒ mapper never opens ⇒ `/mnt/data` unmounted. | `nofail` + a **paging** Sentry emit with `reason=doppler_unreachable` + the pre-container fail-closed gate (D2 synthesis). |
| 7 | **Retained plaintext volume is itself the exposure** for 7 days. | Accepted, time-boxed, `prevent_destroy` + double-gated wipe. The alternative (terminal data loss) is worse. **Explicitly not a snapshot** — no indefinite copy. |
| 8 | **State divergence** (Phase 4→5). If Phase 5 stalls, drift becomes permanent. | Behaviour satisfied immediately; convergence is an AC, not a follow-up. Drift guard (AC13) covers the shape. |
| 9 | **#6568 may not merge.** | Phase 0 STOP + re-price. Two-host is worse than 2×. |
| 10 | `host_creates` counter scope vs `hcloud_volume` is asserted from a workflow comment, not measured. | Verify at /work; if in scope, the dispatch job is the only apply path (already the design). |

---

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Operations (COO), Product (CPO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled **Option 2** (additive volume + freeze + rsync + repoint), single-host, sequenced
after #6568, ≤20 min. Independently found the `/mnt/data` glob (R5) and that `verify_set_identity` does
not port (R6). Rejected blue-green, in-place `reencrypt`, fscrypt, `soleur-drain.service`, and the
pre-cutover snapshot. Full ruling → `adr-118-seed.md`.

### Legal (CLO)

**Status:** reviewed
**Assessment:** **Decouple.** Corrected the site count to 7 canonical body sites (2 invisible to a
`LUKS` grep) + 3 headers, ×2 mirrors = 20. Corrected my legal anchors: **Art. 32 exposure is genuinely
weak** (Art. 32 mandates measures *appropriate to the risk*, not encryption) — the **transparency**
exposure (Art. 5(1)(a) + 12(1) + 13(1)(f)) is the strong one, and **Art. 34(3)(a)** (encryption exempts
data-subject breach notification) is the strongest limb, unnamed in the issue. Added **UCPD 2005/29
Art. 6(1)(b)** + **FTC Act §5**. Ruled **DC-1 is evidence of scienter** and that re-putting its second
ask is **mandatory** on changed facts. Found the Art. 30 register has **no PA for workspace git data at
all** and `compliance-posture.md:78` asserts the never-born CAX11. Identified the mirror hole as
blocking. **Tier 1 → CLO sign-off required.**

### Operations (COO)

**Status:** reviewed
**Assessment:** **cx33 `available=false` in all 3 EU DCs** (live 2026-07-17) — the finding that settles
the architecture. Volume cost **+$1.31/mo transient (web-1 only), $0.00 steady state** (replacement,
not addition) ⇒ **no new recurring expense line**; the ledger needs a **rate correction** (P2, separate
PR — stale `~0.044/GB` across 5 rows, ~$2.33/mo understated). **No maintenance window, no status page,
no user-comms duty** (single operator, pre-revenue). **No snapshot** — converged independently with the
CTO. No backup IaC exists fleet-wide (separate chore). Flagged that its research sub-agent read
`HCLOUD_TOKEN` from Doppler `prd_terraform` for **read-only** GETs.

### Product/UX Gate

**Tier:** none
**Decision:** n/a — no UI surface. No path in Files to Create/Files to Edit matches the UI-surface term
list or glob superset (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`); the mechanical
override does not fire. The user-facing impact is data integrity and published legal text, not an
interface.
**Agents invoked:** cpo (threshold sign-off per §2.6 — not the UX pipeline)
**Skipped specialists:** none — `ux-design-lead` is correctly **N/A** (no UI surface), not skipped.
**Pencil available:** N/A (no UI surface)

#### Findings — CPO threshold sign-off

**Verdict: APPROVE WITH CONDITIONS.** *"The encryption work is the right call and should proceed now —
at 0 users the volume is near-empty and this migration will never again be as cheap or as safe. Do it
before #1439 lands a single founder. But I do not approve the sequencing that keeps a known-false
Art. 32 claim published as the price of doing it."*

All ten conditions are folded in as plan structure, not prose:

| Condition | Where |
|---|---|
| **C1** Decouple the docs correction (standalone PR, this week) | The legal track → PR 1 |
| **C2** Time-box; DC-1 closes when PR 1 merges, not #6588 | AC9 |
| **C3** Backup before encryption (G1) | Cross-Domain Disagreement **D1** — satisfied by G7+G8, not a snapshot |
| **C4** G2/G3/G4 as named ACs with the checkpoint-ref assertion explicit | AC24, AC25; Phases 3-4 |
| **C5** G5 key escrow proven before cutover | AC22 (blocking) |
| **C6** G6 fail-loud mount + mapper-aware fstab, in this PR | Phase 1; AC14, AC15; **D2** synthesis |
| **C7** G7/G8 retained old volume (`prevent_destroy`) + rehearsed rollback | Phase 5 (7d), AC20, AC29 |
| **C8** Bounded downtime justified in `## Downtime & Cutover` | Downtime & Cutover |
| **C9** Sequence after #6538 settles | Phase 0 |
| **C10** Write the plan | this document |

Also corrected my R1a (Start Fresh vs signup path) and flagged `roadmap.md` Current State as stale
(43 vs 58 open) — noted, not blocking.

---

## GDPR / Compliance Gate (Phase 2.7)

**Invoked** — triggers (a) *(regulated-data surface: encryption of personal data at rest + three legal
documents)* and (b) *(brand-survival threshold `single-user incident`)* both fire. The CLO advisory
**is** the compliance output and supersedes a generic gate pass; its Critical findings are folded in as
AC6/AC7/AC8 and the decoupled PR 1 rather than deferred.

**Advisory only — all legal output is draft material requiring professional legal review.**

Critical items → `compliance-posture.md` Active Items + a `compliance/critical`-labelled issue:
- Art. 30 register carries **no PA** for workspace git-data storage (accountability gap, independent of
  encryption) → **AC6**.
- `compliance-posture.md:78` asserts the never-born CAX11 in the Hetzner DPA scope row (**Art. 28(3)**) → **AC7**.
- **Art. 25(1) systemic root cause:** no gate reconciles published Art. 32 claims against the Art. 30
  register — *that is why this shipped and why it survived.* → **deferred, issue filed** (Deferrals).

---

## Open Code-Review Overlap

Checked via `gh issue list --label code-review --state open --json number,title,body --limit 200` +
per-path `jq --arg` containment (two-stage, per `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`)
across `infra/server.tf`, `cloud-init.yml`, `privacy-policy.md`, `data-protection-disclosure.md`,
`legal-doc-shas.ts`, `git-data-luks`, `workspace-resolver.ts`.

- **#2197** *(refactor(billing): SubscriptionStatus type + hoist single-instance throttle doc + Sentry
  breadcrumb UUID policy)* — matched on `infra/server.tf` as an incidental substring.
  **Disposition: acknowledge.** Different concern (billing types); no overlap with any line this plan
  edits. Remains open.

No other overlap.

---

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-118-luks-at-rest-for-the-live-workspaces-volume.md`
- `apps/web-platform/infra/workspaces-luks.tf`
- `apps/web-platform/infra/workspaces-luks.test.sh` *(mutation-tested drift guard)*
- `apps/web-platform/infra/workspaces-cutover.sh`
- `apps/web-platform/infra/luks-monitor.{sh,service,timer}`
- `.github/workflows/workspaces-luks-cutover.yml`
- `scripts/followthroughs/workspaces-luks-soak-6588.sh`
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6588.md`
- `apps/web-platform/test/legal-mirror-clause-retraction.test.ts` *(mirror-hole gate)*

## Files to Edit

- `apps/web-platform/infra/cloud-init.yml` *(Phase 1 — glob → explicit volume ID + `nofail`; drop `|| true`)*
- `apps/web-platform/infra/soleur-host-bootstrap.sh` *(baked LUKS + pre-container fail-closed gate)*
- `apps/web-platform/infra/server.tf` *(Phase 5 — `moved` + name convergence)*
- `.github/workflows/apply-web-platform-infra.yml` *(new dispatch job)*
- `.github/workflows/infra-validation.yml` *(register the drift guard)*
- `.github/workflows/scheduled-followthrough-sweeper.yml` *(soak secrets)*
- `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4}`
- `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`
- `plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`
- `apps/web-platform/lib/legal/legal-doc-shas.ts`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/legal/compliance-posture.md`

**No `plugins/soleur/skills/*/SKILL.md` `description:` edit is candidate** ⇒ the skill-description
budget check (§1.8) is skipped. **No new AGENTS.md rule** ⇒ the always-loaded byte budget is untouched.

---

## Deferrals (tracking issues required)

| Item | Why deferred | Re-evaluation | Label |
|---|---|---|---|
| Expense-ledger rate correction (`~0.044` → `0.0572 EUR/GB/mo`, 5 rows, ~$2.33/mo understated; discharge the "VERIFY on invoice" flags) | Distinct concern (ledger accuracy), distinct owner (`ops-advisor`); would dilute a P1 security PR | Next invoice | `domain/engineering`, `priority/p3-low` |
| cpx32 price contradiction (`expenses.md:20` ~EUR 35/mo vs research implying a cheap cx33 analogue) | Blocks a cx33-successor decision on #6538/#6570, not this plan | Before any successor-type decision | `priority/p3-low` |
| **Art. 25(1) gate: reconcile published Art. 32 claims against the Art. 30 register** | Systemic root cause; needs its own design | After PR 1 | `type/security`, `compliance/critical` |
| Body-equivalence for the 8 non-T&C legal docs | Pre-existing benign drift must be cleaned first (`check-tc-document-sha.sh:11-19`); dragging it in risks the retraction | After PR 1 | `domain/engineering` |
| Fleet-wide backup posture (no snapshot/backup IaC exists) | Out of scope; the retained volume is this cutover's backstop | Post-GA | `domain/engineering` |
| `soleur-web.service` / `soleur-drain.service` phantoms in `git-data-cutover.sh` | Dead code for a host #6570 says can never be born | With #6570 | `deferred-scope-out` |
| `roadmap.md` Current State stale (43 vs 58 open, dated 2026-05-25) | Housekeeping | Next CPO review | `priority/p3-low` |

---

## Test Scenarios

Runner verified: `bun test` for `plugins/soleur/test/**` (`bunfig.toml` has no blocking
`pathIgnorePatterns`); `./node_modules/.bin/vitest run` for `apps/web-platform/test/**`
(`vitest.config.ts` collects `test/**/*.test.ts{,x}` — a co-located test would **not** run, hence
`apps/web-platform/test/legal-mirror-clause-retraction.test.ts`); `bash <file>.test.sh` for infra
guards. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (**not** `npm run -w` —
the root `package.json` declares no `workspaces`).

1. **Drift guard goes RED on a plaintext volume** (the AC's mutation case).
2. **Drift guard goes RED** if the passphrase appears as an argv token on any `luksFormat`/`luksOpen` line.
3. **Drift guard goes RED** if the `isLuks` idempotency guard is removed.
4. **Drift guard goes RED** if an unencrypted fallback is introduced (empty-key path must fail loud).
5. **Container-start gate goes RED** when `/mnt/data` is mounted from the raw device (D2 synthesis).
6. **Mirror gate goes RED** when a retracted clause is re-inserted into a **mirror** file only.
7. **Mirror gate goes RED** when canonical is edited but the mirror is not.
8. `cloud-init-user-data-size` stays under `WEB_GZIP_BUDGET`.
9. `terraform-target-parity` still asserts `user_data` in `ignore_changes`.
10. Cutover script **dry-run** exercises every phase with no writes.
11. Rollback path: a deliberately failed canary remounts plaintext and restarts the container.
12. Escrow proof: a wrong passphrase fails the throwaway-volume unlock (proves the check can go RED).

---

## Sharp Edges

- **Never `grep LUKS` to scope the legal edit.** Two of seven canonical body sites carry the
  git-data-host clause with no `LUKS` token (`privacy-policy.md:488`, `gdpr-policy.md:318`). Use the
  union-anchor grep. This undercount happened **three times** during planning (4 → 6 → 7).
- **Never point the `isLuks` guard at the live volume.** It is a data-destroyer on a populated plaintext
  device. It is safe **only by construction** — on a volume born empty.
- **Never `-replace` a web host while cx33 is unorderable.** Destroy-before-create + no stock = the
  platform is gone. `stock-preflight-gate.sh` enforces this; do not bypass it.
- **`git-data-cutover.sh` is not runnable code.** It invokes two systemd units that do not exist. Copy
  its *shape*; never invoke it, never cite it as a working asset.
- **`verify_set_identity` does not port.** A `rev-list` identity passes while dropping working-tree data —
  exactly the sole-copy data this migration exists to preserve.
- **The fix creates a worse failure mode than it closes.** Passphrase loss ⇒ unreadable forever. Escrow
  proof is blocking, not a nicety.
- **The mirror is never hashed.** Editing canonical and forgetting the mirror is CI-green and
  user-visible. The one thing PR 1 must not do is ship into that hole.
- **`nofail` and fail-closed are not in conflict** — put `nofail` in fstab (no boot hang) and the
  fail-closed check before `docker run` (no silent root-disk writes).
- **A plan whose `## User-Brand Impact` is empty or `TBD` fails deepen-plan Phase 4.6.** It is filled.
- **The ADR ordinal is provisional.** If renumbered, sweep this plan + `tasks.md` + every AC naming it in
  the same edit — a stale ordinal makes AC11 verify a nonexistent file.
- **`Ref #6588`, never `Closes`** — the remediation executes post-merge.

---

## Decision Challenges (ADR-084)

Persisted to `knowledge-base/project/specs/feat-one-shot-6588-luks-workspaces-volume/decision-challenges.md`;
`ship` renders these into the PR body and files them as `action-required` issues. **Headless — recorded,
not asked.**

**DC-A — User-Challenge: the plan decouples the legal retraction from the encryption work, against the
issue's stated AC.** The issue requires the three unachievable clauses be corrected *in the same PR* and
the LUKS clause changed *only after* live verification. **CLO and CPO both ruled decouple**; the CTO's
evidence independently supports it (schedule pressure on a data-loss-capable cutover over sole-copy
data). CPO adds that with **0 beta users** retraction is free now and gets monotonically more expensive
with every founder #1439 recruits. **The stated direction remains the default** — this is surfaced, not
silently applied.

**DC-B — User-Challenge: re-putting DC-1's second ask (temporal qualification), already declined
twice.** Not a relitigation: the overrule's premise was a *bounded* window, and new facts (the freeze
mechanism does not exist; cx33 is unorderable in all 3 EU DCs) establish the fix **cannot** land by
DC-1's own 2026-07-23 trigger — **the premise is already known-false as of 2026-07-17**, six days before
the trigger fires and re-ratifies by default. CLO holds that silent inheritance would launder a stale
premise, and that DC-1 — a documented, deliberated decision to keep publishing a known falsehood — is
**evidence of scienter** under Art. 5(2), making the written risk acceptance costlier than the risk it
accepts.

**DC-C — Cross-domain disagreement resolved without input (recorded for audit).** CPO's C3
("verified-restorable backup, blocking") vs CTO+COO's independent rejection of a pre-cutover snapshot.
Resolved in Cross-Domain Disagreement D1: C3 is outcome-shaped, and the additive design's retained
plaintext volume (`prevent_destroy`, 7d, rehearsed) satisfies it **better** than a snapshot. Retention
takes CPO's 7 days over COO's 72h. **If C3 is read strictly as requiring an off-volume artifact distinct
from the old volume, this resolution needs revisiting.**
