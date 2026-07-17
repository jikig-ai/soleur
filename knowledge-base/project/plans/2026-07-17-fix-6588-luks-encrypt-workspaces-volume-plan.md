---
title: "fix(security): LUKS-encrypt hcloud_volume.workspaces + retract the three unachievable privacy-policy clauses"
issue: 6588
date: 2026-07-17
lane: cross-domain
type: security-remediation
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_clo_signoff: true
adr: ADR-119 (provisional — re-verify ordinal at ship)
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

> ## ⚠️ Enhancement Summary — Deepen Pass (2026-07-17)
>
> **Eight lenses ran. The plan does NOT survive them intact. `/work` MUST apply §Deepen Pass
> Corrections before implementing — several ACs as originally written are FALSE-GREEN GENERATORS.**
>
> **Sections enhanced:** Premise Validation (P4/P4a), Research Reconciliation (R7), Sequencing,
> Observability, + the new §Deepen Pass Corrections which SUPERSEDES parts of Phases 1-5 and the ACs.
>
> **Agents:** verify-the-negative · data-integrity-guardian · security-sentinel ·
> architecture-strategist · code-simplicity-reviewer · terraform-architect · spec-flow-analyzer ·
> observability-coverage-reviewer.
>
> ### The four findings that matter
>
> 1. **AC26 — the verify could not go RED. Empirically proven.** The prescribed
>    `rsync -aHAX --numeric-ids --checksum --delete --dry-run SRC/ DST/` "prints zero transfers" was
>    run against a DST with corrupted content + wrong perms + an orphan file: **it printed nothing and
>    exited 0.** rsync's default verbosity is 0. **The single check standing between the user and
>    permanent loss of their source code was a false-green generator** — and the plan mutation-tested
>    the drift guard and the mirror gate but never this. *(→ C1)*
> 2. **The `#6568` premise was false, and it moved mid-session.** PR #6568 **merged docs-only** at
>    10:17:46Z (zero `.tf`); web-2 survives; `var.web_hosts` still has both. Phase 0 blocked on a
>    condition that had already resolved differently. *(→ fixed inline: P4/P4a, R7, §Sequencing correction)*
> 3. **`--restart unless-stopped` defeats the D2 fail-closed gate on the exact path it exists for.**
>    On reboot `dockerd` resurrects the container — `docker run` never executes, the gate never runs,
>    and Docker silently creates the bind-mount dir on the **root disk**. My D2 synthesis was
>    **circular**: I chose `nofail` *because* the gate would catch it. It does not. *(→ C2)*
> 4. **The escrow proof was vacuous.** Formatting a throwaway with the same string just read from
>    Doppler and re-opening it passes for **any** string — it cannot fail. *(→ C3)*
>
> **Verdict: the design (additive volume, freeze, filesystem-level verify, retain plaintext) survives
> — the ADR's core ruling is unchanged. The instrumentation around it did not.**

## Overview

User source code sits **unencrypted at rest** on `hcloud_volume.workspaces` while three
published legal documents tell data subjects it is LUKS-encrypted. Issue #6588 mandates routing
to the CTO **before any terraform**. That happened; the ruling is ADR-119 (see Architecture Decision).

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
| P4 | "see `specs/feat-6538-web2-fsn1-orphan/decision-challenges.md` DC-1" | **Moved mid-session.** At plan-open it existed only on the unmerged PR #6568. **PR #6568 MERGED at 2026-07-17T10:17:46Z** — DC-1 is now **on `main`** and directly closable. Content + the 2026-07-23 trigger confirmed. | PR 1 closes DC-1 on main |
| P4a | *(the issue + my own Phase 0)* "PR B (#6538) is concurrently destroying web-2 … sequence after #6568" | **FALSE — caught by the deepen verify-the-negative pass.** PR #6568 merged as **`docs(legal,finance): state the hosting locative at EU level; re-derive the cost model`** — **docs-only, ZERO `.tf` files** (`gh pr view 6568 --json files`). `git show origin/main:apps/web-platform/infra/variables.tf` still defines **both** `web-1` (hel1) and `web-2` (fsn1). **web-2 was never destroyed, and no teardown PR exists** — #6538 is an open *issue* with no PR. | **Phase 0 UNBLOCKED — see §Sequencing correction** |
| P5 | "Blue-green… aligns with the zero-downtime precedent in #5887" | **Inverts it.** #5887's norm: *"Default to the zero-downtime path… Downtime is acceptable only with explicit justification + a bounded window + operator sign-off."* Justification exists; the machinery does not (**no LB**, `server.tf:186-187`; `web["web-1"]` pinned **23× / 5 files**; **#6459 is OPEN with "ADR needed"**). | Option 1 rejected |
| P6 | `#6570 #6459 #5274 #6538` blockers | All **OPEN**. `#5887` **CLOSED**. `#6426` **MERGED**. `#6568` is an **open PR**. | Hold |
| P7 | DC-1 cites "the Art. 13(3) precedent set in PR #4455 — *'encryption at rest is being rolled out'*" | PR #4455 is MERGED but is *"feat(legal): PR-1 Flagsmith sub-processor disclosure"*. **That wording is not in it.** The *mechanism* is reusable; the citation is loose. CLO separately ruled the **Art. 13(3) anchor wrong** → **Art. 12(1) + 5(1)(a)**. | Do not propagate |
| P8 | *(implicit)* "the claim misleads users" | **There are ZERO beta users** (`roadmap.md` Current State; #1439 "recruit 10 solo founders" still **OPEN**). The volume holds the **operator's own** dogfooding workspaces. The threshold is met, but no data subject has yet been misled. | Makes retraction **free now** |

**P3 drift — re-derive the site count at the legal PR, do NOT inherit the 20.** Re-verified at /work
(2026-07-17, after rebasing onto `origin/main` @ `105799dbd`): **#6568 merged between plan-time and
/work-time and PROLIFERATED the false claim** — it added fresh `**Last Updated:**` changelog headers to
all three canonical docs, each of which **restates the LUKS clause verbatim** (`privacy-policy.md:11`,
`gdpr-policy.md:13`, `data-protection-disclosure.md:12`). Current canonical LUKS-token sites:
pp `:11,:298,:518` · gdpr `:13,:44` · dpd `:12,:189,:276` = **8**, plus the 2 no-LUKS-token
git-data-host sites, ×2 mirrors. **The plan's "20 sites" is stale and the number will keep moving with
every legal PR that lands.** The legal PR must re-run the union-anchor grep and derive the count from
the command's output at ITS work-time — never quote this plan's figure
(`cq-cite-content-anchor-not-line-number`; the count is a claim, not a fact). The *conclusion* is
unchanged and strengthened: the claim is live, published, and now more widely restated than when the
issue was filed.

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
| R7 | AC: "every `var.web_hosts` member" | **Corrected at deepen.** `var.web_hosts` = `{web-1: hel1, web-2: fsn1}` on **fresh `origin/main`** and **stays that way** — PR #6568 merged docs-only (P4a). So the AC literally means **both hosts today**. But web-2 is slated for teardown (#6538, open, no PR), so encrypting its volume is waste. | **Scope out web-2 explicitly; do NOT block on a PR that does not exist** — §Sequencing correction |
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

**Create `ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`.** Provisional ordinal (ADR-117 is
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

The decision is only *true* after Phase 4. ADR-119 is authored **now** with **`status: adopting`**,
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

> **Rewritten at deepen (simplicity review).** The original design polled `blkid`/`findmnt`/`mountpoint`
> every 5 minutes from a new `luks-monitor.{sh,service,timer}`. That was **cargo-culted from git-data —
> a design for a second host nobody could see.** web-1 *is* the host that serves the site. Two facts kill
> the probe: (1) **the state it polls is boot-immutable** — nothing but the cutover script remounts
> `/mnt/data`, so a 5-min timer on a boot-time constant is a heartbeat pretending to be a probe; and
> (2) **every one of its five failure modes is already caught, and caught louder, by the pre-`docker run`
> fail-closed gate** — no mapper ⇒ no container ⇒ HTTP down ⇒ the existing Better Stack `app.soleur.ai`
> monitor pages. The one thing the probe added was *discrimination* (`reason=doppler_unreachable` vs
> `reason=plaintext_device`). **That belongs inside the gate**, at the one point where the state actually
> transitions — five lines in a gate Phase 1 already builds, not a systemd unit + timer + baked script.
> The plan's own sentence applies: *"for a singleton, drain ≡ stop, and stop is strictly stronger."*
> **Cut: 3 files.** Phase 0 must assert the boot-immutability premise, not assume it.

```yaml
liveness_signal:
  what: "The pre-`docker run` fail-closed mapper gate (soleur-host-bootstrap.sh). Refuses to start the app container unless findmnt -no SOURCE /mnt/data == /dev/mapper/workspaces AND blkid TYPE=crypto_LUKS AND mountpoint -q /mnt/data. On refusal it emits the discriminating reason and exits non-zero — the container never starts, so the failure is an HTTP outage, not a silent plaintext write."
  cadence: "every boot + every container start (the only moments the asserted state can change)"
  alert_target: "Sentry (host-side emit via the baked SOLEUR_SENTRY_DSN already wired at soleur-host-bootstrap.sh:44-46,263) + the EXISTING Better Stack app.soleur.ai uptime monitor (uptime-alerts.tf:79) — a refused container is a hard down"
  configured_in: "apps/web-platform/infra/soleur-host-bootstrap.sh (the gate); .github/workflows/workspaces-luks-verify.yml (on-demand read-only re-assert)"
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

Phase 5 gates on a soak before the plaintext volume is wiped and ADR-119 flips `adopting → accepted`.
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

### Sequencing correction (deepen pass — supersedes the CTO's sub-ruling (d))

The CTO ruled *"wait for #6568; once web-2 leaves `var.web_hosts` the AC means web-1 only."* **That
premise is dead.** #6568 merged docs-only and web-2 survives (P4a). The teardown is #6538 — an **open
issue with no PR**. Blocking on it would be blocking on a PR that does not exist: a dead end, not a gate.

**Corrected:** the plan is **NOT blocked**. Proceed on **web-1 only**, and scope web-2 out explicitly:

- `hcloud_volume.workspaces_luks` is a **singleton for web-1**, not `for_each = var.web_hosts` — which
  also sidesteps the `for_each`-over-a-`-target`-excluded-map hazard
  (`2026-07-03-for-each-over-target-excluded-map-forces-premature-provisioning.md`).
- **web-2's volume is deliberately left plaintext**, tracked by #6538. Rationale: it is slated for
  destruction, holds no live user data (`app.soleur.ai` is a hard-pinned singleton to web-1 and web-2
  has never served), and encrypting a volume scheduled for deletion is waste. **This is a knowing,
  recorded deviation from the issue's "every `var.web_hosts` member" AC** — see AC1a.
- The CTO's *other* reason to wait — avoiding a `server.tf`/`variables.tf` collision with PR B — is
  moot: no such PR is in flight.

### Phase 0 — Read-only preconditions (no code, NOT blocked)

- [ ] **Highest-value check in the plan** (CTO open risk 1): verify the **live** host's actual
      `/etc/fstab` + mount state. R5 is a *code-shape* finding. **If web-1 has been rebooted since first
      boot and `/mnt/data` is unmounted, the workspace data is not where this plan assumes and the
      sequencing is invalid.** Read-only, via the sanctioned CI path.
- [ ] **Measure the actual data size**: `du -sh /mnt/data/workspaces` (free — same read-only probe).
      Every cutover estimate is priced against 20 GB of *capacity*; CPO reports the volume is near-empty
      at 0 users. **If it is small, the single-pass rsync below is confirmed and no staging pass is
      needed.**
- [ ] Confirm `var.web_hosts` still `{web-1, web-2}` and that no web-2 teardown PR has landed; if one
      has, re-read R7 (the scope-out's rationale changes but not its conclusion).

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

### Phase 2 — ADR-119 + C4 + LUKS in the baked bootstrap + mutation-tested drift guard

- [ ] **First task:** copy `specs/…/adr-118-seed.md` → `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` (`status: adopting`). Re-verify the ordinal against `origin/main`.
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
- [ ] ADR-119 `adopting` → `accepted`.
- [ ] **The legal PR (single, coupled — operator decision):** now that the volume is live-verified
      LUKS, land **all four** doc corrections together: retract the three permanently-false clauses
      (git-data host / cross-host TLS / cross-host membership re-verification) across **all 20 sites**
      with **per-site anchors**, assert the LUKS clause **present-tense true**, create the Art. 30 PA
      + Cross-Cutting TOM limb, correct `compliance-posture.md:78`, ship the mutation-tested
      mirror-hole gate, **re-pin `legal-doc-shas.ts` ×3**, and **close DC-1**. This is AC1–AC10,
      re-targeted here. Honours the AC's "Only THEN" for the whole clause set.

---

## The legal track — COUPLED (the issue's AC governs; operator decision 2026-07-17)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

> ## ⚖️ OPERATOR DECISION — SUPERSEDES THIS SECTION'S ORIGINAL DIRECTION
>
> The decouple proposed below was **put to the operator and DECLINED** (DC-A, DC-B — both now RESOLVED).
> **#6588's AC governs as written.** Binding on `/work`:
>
> 1. **This run's infra PR carries ZERO doc changes.** No retraction, no temporal qualification, no
>    `legal-doc-shas.ts` re-pin, no Art. 30 PA. Do not touch `docs/legal/**`,
>    `knowledge-base/legal/**`, or the Eleventy mirrors in the infra PR.
> 2. **"PR 1 — docs-only, THIS WEEK" is CANCELLED.** Everything specified under it is **re-targeted**
>    to the single post-cutover legal PR, which also flips the LUKS clause to present tense.
> 3. **That PR is gated on the `workspaces-luks-cutover` job's canary passing** (AC "Only THEN"), and
>    is a follow-up to this run, not part of it.
> 4. **DC-1 closes when that post-cutover PR merges.**
> 5. The three permanently-false clauses **stay published** meanwhile — the controller's risk
>    acceptance, taken a third time on current facts.
>
> **Read the checklist below as the post-cutover PR's specification**, merged with Phase 5's LUKS flip
> into one PR. The corrections of *fact* in it (Art. 12(1) anchor not Art. 13(3); #4455 is not a
> wording template; per-site anchors because the wording is not uniform; the mirror-hole gate) remain
> **fully binding** on that PR.

**The arguments that were made and declined** — retained for audit, because a risk acceptance is only
meaningful if the case against it stays legible:

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

### ~~PR 1 — docs-only, THIS WEEK~~ → **CANCELLED. Re-targeted to the post-cutover legal PR.**

> **NOT this run.** Operator declined the decouple (DC-A). Every item below is gated on the
> `workspaces-luks-cutover` canary and ships in ONE PR together with Phase 5's LUKS present-tense flip.
> `/work` must implement **none** of it in the infra PR. The items remain binding **on that PR**.

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

### The legal PR — **NOT this run.** Gated on the cutover canary (operator decision: coupling kept)

> **AC1–AC10 are OUT OF SCOPE for the infra PR this run produces.** They ship in the single
> post-cutover legal PR, together with Phase 5's LUKS present-tense flip. `/work` must satisfy **none**
> of them now, and must **not** treat them as unmet gates on the infra PR.
>
> Two consequences of the coupling, folded in: **AC2's** clause is asserted **present-tense true**, not
> temporally qualified (DC-B declined). **AC6's** limb (g) states the **then-encrypted** state, not the
> plaintext one — that PR lands after the volume is verified LUKS.

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
- [ ] **AC9** DC-1 closed by the **post-cutover legal PR's** merge (not by the infra PR, and not by #6588 closing).
- [ ] **AC10** `Ref #6588` — **not `Closes`** (`type: security-remediation`; the fix executes post-merge, so `Closes` would auto-close before remediation runs).

### Pre-merge (the infra PR) — ⬅ **THIS RUN's deliverable. AC11–AC20 are the gates `/work` must meet.**

- [ ] **AC11** `ADR-119-*.md` exists with `status: adopting`, a `## Decision`, and a `## Alternatives Considered` table naming blue-green, in-place `reencrypt`, fscrypt, option 3, `soleur-drain.service`, and the snapshot — **with the cx33-stock rationale**.
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
- [ ] **AC30** 7d soak follow-through enrolled with the `follow-through` label + directive; on soak-pass: `prevent_destroy` released, plaintext volume deleted, TF state converged, ADR-119 → `accepted`, and the **coupled legal PR (AC1–AC10 + present-tense LUKS flip + SHA re-pin)** opened.

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

- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`
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

## Deepen Pass Corrections — BINDING on `/work`

These supersede the sections they name. Each is evidence-backed; none is taste.

### C1 — AC26's verify is a false-green generator (data-integrity, **empirically proven**) 🔴

The prescribed command prints **nothing** and exits 0 against a corrupt DST. Verified locally
(rsync 3.4.1) against a DST with same-size content corruption + a perms divergence + an orphan:
plan's exact command → **empty output, exit 0**. Even `-v` under-reports (it lists transfers and
deletions but **not attribute-only** updates — exactly what `-aHAX` exists to preserve).

**Replace AC26's command with the itemized form, and mutation-test it:**
```
rsync -aHAXi --numeric-ids --checksum --delete --dry-run --out-format='%i %n' SRC/ DST/ \
  | tee /dev/stderr | wc -l    # MUST be 0
```
**Mutation cases (blocking — if any does not flip RED, the cutover does not proceed):**
`touch DST/x` · `chmod` a file · `truncate -s-1` a file · `chown` a file.

Also from the same review:
- **`-a` does NOT include `-S` (sparse).** The "total-byte assert" must be `du --apparent-size -sb`,
  **never** `du -sb`/`df` — LUKS steals a header and a fresh `mkfs` has different geometry, so a
  `df`-based assert can *never* match and will be loosened into meaninglessness.
- **Drop the caches before the checksum pass** (`sync && echo 3 > /proc/sys/vm/drop_caches`) — else
  you verify rsync's page cache, not that the bytes round-tripped through **dm-crypt**, which is the
  brand-new code path.
- **DELETE the `chown 1001:1001` re-assert.** It sits *after* the verify — **any mutation after the
  verify voids the verify** — and is redundant: `rsync -a` with a trailing-slash source preserves
  uid/gid exactly. Keep `--numeric-ids` (UID 1001 has no host `/etc/passwd` entry).
- **Pass 2 has no `--checksum`** ⇒ the verify is its *only* backstop. Give pass 2 `--checksum` or
  state the dependency explicitly.
- **Hardcode `--dry-run`** — one typo from `rsync --delete SRC/ DST/`; transposed operands wipe live data.
- **Add `git fsck --full` per DST workspace** — the highest-value missing check; no rsync verify can
  tell you a copied `.git` is internally consistent.
- **Add a capacity preflight** — `df` AND `df -i`. Millions of loose objects ⇒ **inode exhaustion with
  free bytes** is the realistic ENOSPC, and it is site-down if it fires inside the freeze.

### C2 — `--restart unless-stopped` defeats the D2 gate on reboot (security) 🔴

`cloud-init.yml:770` — **verified.** On reboot `dockerd` resurrects `soleur-web-platform` from stored
config; `docker run` never executes; the pre-`docker run` gate never runs; `-v /mnt/data/workspaces`
bind-mounts a **root-disk dir Docker silently creates**. Result: container healthy, `/api/health`
200 (**AC27 passes**), **user source code written in plaintext to the root disk**. My D2 synthesis
was circular. This also **defeats the simplicity review's case for cutting the probe** ("the gate
catches all five modes") — on the reboot path it catches none.

**Fix (take both):** (a) make the mount a real dependency — a systemd unit with
`RequiresMountsFor=/mnt/data`, ordered after the mapper-open (or `/etc/crypttab` + `systemd.mount`),
so *container running ⇒ mount correct* holds **by construction**; (b) `chattr +i` the root-disk
`/mnt/data` inode so Docker's implicit `mkdir` returns `EPERM` and the container refuses to start.

### C3 — the escrow proof was vacuous (security) 🔴

Formatting a throwaway with the same string read from Doppler and opening it **passes for any
string**. It cannot fail. It also misses the mode that actually kills you: a `-replace` of
`random_password` re-mints Doppler **but does not re-key the LUKS header** (`git-data-luks.tf:26-30`
documents exactly this) ⇒ escrow divergence, throwaway test green forever, real volume unopenable.

**Fix — one command, no volume, no leak surface:**
```
printf '%s' "$WORKSPACES_LUKS_KEY" | cryptsetup luksOpen --test-passphrase --key-file - "$REAL_DEV"
```
against the **real** device, key read in a process distinct from the one that ran `luksFormat`. This
deletes the throwaway's CI-transit/orphan/cost surface and makes Test Scenario 12 a genuine RED.
**Then make it continuous** — a **daily** `--test-passphrase` probe with `reason=escrow_divergence`.
*The plan invented a terminal failure mode and then declined to monitor it.*

### C4 — HIGH: the LUKS **header** is unescrowed (security) — an independent terminal limb

A corrupted/overwritten LUKS2 header is unrecoverable **even with a perfect passphrase** (keyslots
live in the header; no derivation path exists). Absent from Risks, failure_modes, and the ACs.
**Fix:** `cryptsetup luksHeaderBackup` after `prepare_luks_target`, stored off-host in a bucket
**distinct from the tfstate bucket** — else both halves are colocated and the "different provider,
different blast radius" property evaporates. Add an AC asserting the backup's `luksDump` UUID matches.

### C5 — HIGH: the "wipe" is not a wipe (security)

- A **Hetzner API delete is not a crypto-erase** and carries no attestation — asserting a wipe you
  cannot evidence is the same failure class as the three clauses PR 1 retracts.
- **`luksFormat` as a wipe is worst-of-all** — it overwrites ~16 MB of header/keyslots; **every byte
  of source code past that offset survives**. It is a crypto-erase only for already-encrypted data.
- **`blkdiscard` can silently no-op** if the virtio device doesn't advertise discard — gate on
  `lsblk -D` showing non-zero.
- **Sequence:** assert discard capability → `blkdiscard -z` (or `dd`) → **verified read-back at
  random offsets + offset 0** → delete. In-repo precedent: `inngest-wiped-volume-verify.sh`.
- **DETACH the retained volume, don't leave it attached-unmounted.** Unmounted is hygiene, not a
  control: `dd if=/dev/sdb | strings` still recovers everything. Detached collapses the
  root-compromise read path *and* makes the R5 glob class structurally unable to remount it.
  Re-attach for rollback is one API call. **Detached-retained strictly dominates at zero cost.**

### C6 — HIGH: the dedicated Doppler config is right; my rationale was cargo-cult (security)

I inherited git-data's blast-radius argument. **It does not port** — web-1 already carries full-prd
`DOPPLER_TOKEN`, so there is no host blast radius to buy. **The real reason is decisive and I never
stated it.** Verified at `cloud-init.yml:755` + `:773`:
`doppler secrets download --config prd > "$TMPENV"` → `docker run --env-file "$TMPENV"` ⇒ **every prd
secret is injected into the agent container's env.** A `WORKSPACES_LUKS_KEY` in `prd` would be
readable via `/proc/self/environ` **by the very agent code whose data it encrypts** (CWE-522),
reducing the at-rest guarantee to zero against in-container compromise or prompt-injection exfil.
**Keep the config; rewrite the rationale; assert it** — `workspaces-luks.test.sh` mutation case
(`config == "prd"` ⇒ RED) + a runtime assert (`docker exec … env` contains no `WORKSPACES_LUKS_KEY`).

### C7 — MEDIUM: drop `format` — it is what *prevents* a sound guard (security)

"Safe by construction" is asserted, not engineered. The natural guard — *format only a device with no
filesystem signature* — is **impossible today** because `format = "ext4"` makes the fresh volume
`TYPE=ext4`, **byte-indistinguishable from the live plaintext volume**. `git-data-luks.tf:74-77` even
admits the format is pointless. **Drop `format` on `hcloud_volume.workspaces_luks`** ⇒ raw device ⇒
the discriminator exists:
```
sig=$(blkid -o value -s TYPE "$DEV" 2>/dev/null || true)
case "$sig" in
  "")          luksFormat ;;                # raw — the ONLY formattable state
  crypto_LUKS) : ;;                         # idempotent no-op
  *) echo "FATAL: $DEV carries TYPE=$sig — refusing to format a populated device"; exit 1 ;;
esac
```
Plus a terraform-interpolated **not-the-old-volume** deny, and select the device **by volume ID from
the terraform output — never by glob scan** (the precedent scans for the device that *is* LUKS; the
inverse predicate matches the **live plaintext volume**). Mutation-test: point it at the live device ⇒ abort.
*This refines P1: `format` never needs to change on the live volume — but it must be **dropped** on the new one.*

### C8 — the freeze: "stop is strictly stronger than drain" is FALSE for write-atomicity (data-integrity)

True for availability quiescence; **false for integrity**. Drain lets in-flight work *finish*; stop
*interrupts* it. `git-data-cutover.sh:191-195` says so — *"stop new turns; let in-flight finish"* —
**I inverted the precedent's rationale while claiming to copy its shape.** `docker stop` defaults to a
**10s** grace then SIGKILL; an agent mid-`write()` leaves a **truncated file** that is then faithfully
rsynced and certified correct. `fuser` can't see a dead writer; the verify can't see a quiesce failure.
**Fix:** `docker stop -t 120`; add post-stop interrupted-write asserts (no `.git/index.lock`, no
`objects/pack/tmp_pack_*`, no `gc.pid`) ⇒ abort rather than copy wreckage. Use `lsof +D /mnt/data`
(`lsof +f -- /mnt/data` is malformed). *(`git gc --auto` is a verified non-risk: it dies with the PID
namespace, and `refs/checkpoints/*` are gc roots.)*

### C9 — G2/G3 compare the wrong pair (data-integrity)

G2 is taken in **Phase 3 against the live tree**; G3 "re-verifies equality" in Phase 4. The operator
dogfoods between them, so refs legitimately move ⇒ **false-RED mid-freeze** ⇒ under a 20-min clock the
predictable fix is to re-take the manifest and compare it to itself — **vacuous**. **Take the manifest
after the freeze on SRC and compare against DST** — same instant, opposite volumes.

### C10 — Phase 1 contradicts a **currently-passing** CI guard (data-integrity)

`soleur-host-bootstrap-observability.test.sh:166-170` **requires the exact string AC14 removes**:
`grep -qE 'mount /dev/disk/by-id/scsi-0HC_Volume_\* /mnt/data \|\| true'` → *"do not invert
survivable→fatal"*. Direct contradiction; the file is **absent from Files to Edit**. AC18 catches it
at /work, where the path of least resistance is to delete the assertion — **silently reversing a
deliberate prior decision.** **Add the file, argue the reversal, and re-point the guard at the new
invariant.** Also: **AC14's "no `|| true`" is cargo-cult** — runcmd runs as one `/bin/sh` with `set +e`
active, so removal achieves nothing; the real fix is the `grep -q` guard + a boot emit on mount
failure. And **widen the AC14 grep** — `git grep 'scsi-0HC_Volume_\*'` also hits
`git-data-bootstrap.sh:46,71` (`hr-write-boundary-sentinel-sweep-all-write-sites`).
*R5 may be **understated**: a `defaults`/`pass=2` entry naming a nonexistent device fails
`local-fs.target` → emergency mode → a headless host cx33 cannot rebuild.*

### C11 — the C4 enumeration is WRONG on two of three limbs (architecture) 🔴

My §C4 claimed "Hetzner and Doppler both already modelled". **Verified false:**
- **Hetzner is NOT external** — `model.c4:180` is `hetzner = container "Compute"` **inside**
  `platform.infra`, no `#external` tag. There is no block-storage vendor element at all.
- **The `/workspaces` volume is not modelled at any level** — so "correct its description" targets
  **an element that does not exist**.
- **The `views.c4` edit is vacuous** — `views.c4:32` already includes `platform.infra.hetzner` and
  `:36` already includes `doppler`; LikeC4 renders relationships between included elements
  automatically. **Drop it from Files to Edit and from AC12.**
- **The Doppler→host boot edge is genuinely new** (only `doppler -> engine|claude|inngest|zotRegistry`
  exist) and follows the established host-boot-credential pattern. That limb holds.
- **The miss that stings:** `model.c4:182` and `:212` both say **"per-user worktrees on host-local
  NVMe"** — a reader who takes that literally concludes there is no attached volume to encrypt. My own
  plan warns the CLO *"Do not write 'host-local NVMe' without checking `server.tf`"* — **while the C4
  says it twice and my enumeration never noticed.** **Redo the C4 section; do not patch it.**

### C12 — delete the rename; the divergence is self-inflicted (architecture)

`name` **is** updatable in place (confirmed against the `1.63.0` binary: `resourceVolumeUpdate` →
`VolumeUpdateOpts`) — but **the rename should not happen at all.** The volume name is cosmetic: the
mount pins by **volume-ID**, so nothing reads it. **Keep `hcloud_volume.workspaces_luks` as the
permanent address** and retire the old block ⇒ no `state rm`, no `moved`, no rename, **no divergence
window**. Kills the Phase 5 `server.tf` edit, Risk 8, and seed open-risk 5. *(Constraint: while web-2
lives, `hcloud_volume.workspaces` retains a web-2 instance — an argument for sequencing after the
**real** teardown, not for the rename.)* **Also incoherent as written:** Phase 5 says
"destroy old → `state rm` → `moved` → rename" *and* "Hetzner API delete" — **three disposal paths for
one volume.** If Terraform destroys it there is no state entry to `state rm`. Pick one.

### C13 — rollback closes ~30s earlier than stated (data-integrity)

Phase 4 order is `docker start` → canary → *"any failed assert ⇒ rollback"*. **The door closes at
`docker start`** — the app writes on boot. So the rollback promised on canary-failure is *already*
lossy when invoked. **Fix:** run the host-level canary (`blkid`/`findmnt`/`mountpoint` — no container
needed) **before** `docker start`; resume `webhook.service` only after canary-pass.
**And the lossless/lossy dichotomy is false** — the LUKS volume physically retains every post-cutover
write, so post-canary rollback is *reconcilable*, not impossible. Saying "one-way door" will make an
operator refuse a rollback they should take. Remount the retained volume **read-only at a distinct
path**: a byte-exact T0 that turns the door into "restore T0 + replay from LUKS".

### C14 — Observability: the emit path does not exist (observability) 🔴

- **P0-1:** the cited host-side Sentry emit is **bootstrap-process-only**. `soleur-host-bootstrap.sh:44`
  `DSN="${SOLEUR_SENTRY_DSN:-}"` is a shell function local to that process; the DSN arrives only as a
  process env var from `cloud-init.yml:561` and is **never persisted** —
  `/etc/default/webhook-deploy` (`:409`) carries no `SOLEUR_SENTRY_DSN`. **A new systemd unit sourcing
  it gets nothing.** Cite `cron-egress-enforce-probe.sh:46-64` instead.
- **P0-2 (circular):** the only DSN path open to a standing unit is `doppler secrets get` — so the
  **"Doppler unreachable ⇒ MUST page"** mode has its DSN resolve fail **by the same cause**, and every
  emitter wraps the POST in `if [ -n "$DSN" ] … || true` ⇒ **silently dropped**. The one mode called
  "the worst" is the one guaranteed to go dark. **Fix:** persist the DSN (extend `cloud-init.yml:409`)
  or read the baked literal from `/usr/local/bin/soleur-boot-emit`.
- **P0-3:** `discoverability_test` invokes `workspaces-luks-verify.yml`, **not in Files to Create**
  (I caught this independently). **Add it** — a read-only `workflow_dispatch` re-assert is also the
  right no-SSH artifact for the runbook. Replace the `<id>` placeholder with a real monitor ID.
- **P1-1:** the 5 fields **do not discriminate** — FM3/FM4/FM5 collapse to an identical tuple
  (`mount_source` is empty for all three; `passphrase_source` is read at probe time, not boot).
  **An operator seeing it must SSH — the precise outcome §2.9.2 exists to prevent.** Add
  `mapper_present`, `luks_open_result`, `header_uuid_match`, `cryptsetup_unit_result`,
  `doppler_reachable`.
- **P1-2:** `soleur-boot-emit`'s body is **hardcoded** to 3 tags — it **cannot carry `reason=`**.
- **P1-3:** `logs.where` is **false** — Vector drops every `luks-monitor` line
  (`vector.toml:141-143` is an exact-match `SYSLOG_IDENTIFIER` allowlist of 14 tags; `luks-monitor`
  is absent; the file's own comment warns "a tag typo silently matches nothing").
- **P1-4:** **no `betteruptime_heartbeat` resource exists or is planned** — `zot-registry.tf:336-339`
  records this exact failure: *"until it shipped, that monitor had ZERO consumers and stayed paused."*
- **P1-5:** the emit sets **neither `feature:` nor `op:`** — every existing Sentry rule filters on
  `feature:`. Events land in the stream; **nothing pages**. `issue-alerts.tf` is not in Files to Edit.
- **⇒ the 7d soak probe CAN NEVER GO RED** (both legs missing): the query matches zero events
  unconditionally, and there is no positive control. **It exits 0 for 7 days regardless of the volume's
  actual state — and then authorizes wiping the plaintext rollback volume.** That is the dangerous part.
  Gate the soak on `heartbeat status == "up"` **AND** zero drift events, so a dead probe **fails**.
- *Correct as written:* the `hr-no-ssh-fallback-in-runbooks` reading (the rule bars **human-run** steps
  and the runbook's debug path, not workflow-orchestrated SSH) and `betteruptime_monitor.app`.
- *P2:* `disk-monitor` is **not** a Sentry precedent — it alerts via **Resend email**. Mirror
  `cron-egress-enforce-probe.sh` for the emit, `disk-monitor.{service,timer}` for cadence only.

### C15 — simplicity cuts (accepted, as amended by C2/C14)

- **Cut `luks-monitor` at 5-min cadence** — the state it polls is **boot-immutable**; a timer on a
  boot-time constant is a heartbeat pretending to be a probe. **BUT C2 shows the gate does not cover
  the reboot path and C3 needs a daily escrow probe** ⇒ keep a **daily** unit (escrow divergence +
  header UUID), not a 5-min one, and only once C14's emit path is real.
- **Cut pass-1 rsync** — the freeze is free at 0 users, and a single rsync into an **empty** volume
  needs **no `--delete`** at all, removing `--delete` from the critical path over sole-copy data.
  *(Phase 0's `du -sh` confirms.)*
- **Cut the 7d soak → replace with `reboot once + re-canary` in Phase 4.** The realistic failure is the
  **boot path**; 7 days of an uptime host tests it **zero times**. A deliberate reboot tests it in 90s,
  inside the window, with the plaintext volume still attached. *(Retention length is then decoupled from
  the clause flip; COO's 72h is the better-argued number — CPO's 7d won on authority, not argument.)*
- **Cut G8 rehearsal** — it rehearses the state that is **running right now**, and "and serves" implies
  a container restart, contradicting Phase 3's own ZERO-downtime header.
- **Cut the runbook** → fold the one-way-door decision into ADR Consequences. *(Architecture dissents:
  keep it, per the ADR-068 + runbook precedent, and move the **mechanics** there. Resolve at /work —
  either way the ADR stays at decision altitude.)*
- **Cut ~10 ACs** that are phase-output audits: AC8, AC9, AC10, AC11 (reduce to "ADR exists,
  `status: adopting`"), AC16/AC17 (collapse into "CI green"), AC21 (vacuous container), AC25, AC28
  (a metric with no consumer — keep the 2h abort in the script), AC29, AC30 (five actions in one box).
- **Naming bug:** AC11-AC20 are headed "PR 2 — infra" while AC30 says "PR 2 (legal)". **There are three
  PRs and two are called PR 2.** Rename: **PR 1 legal-retraction · PR 2 infra · PR 3 legal-flip.**
- **The two-PR split STANDS on simplicity merits alone** — fusing them would give a three-line clause
  retraction a merge gate on **Hetzner's inventory**. Dependency removal, not bureaucracy.
- **Turn P8 on the plan's own budget:** zero users is a reason to do this **simply and now**, not to
  run a 5-phase program.

### C16 — line-citation corrections (verify-the-negative)

All 17 load-bearing claims **confirmed**. Convert these to content anchors (`cq-cite-content-anchor-not-line-number`):
`stock-preflight-gate.sh` `.server_types.available` is at **`:73`/`:144`, not `:19`** · `disk-monitor`
block is **`:151-177`, not `:151-185`** · `docker run` is **`:768`**. Exact and correct as cited:
`server.tf:254-256` · `terraform-target-parity.test.ts:1188` · `session-sync.ts:33` ·
`cloud-init.yml:776`/`:581`/`:561` · `compliance-posture.md:78` · `git-data-luks.tf:83`.

### C18 — Terraform: Phase 5's convergence is NOT executable, and its likeliest variant deletes the data (terraform-architect, **measured against 1.63.0**) 🔴

- **🔴 `moved` into a still-occupied address does NOT error — it degrades to a *Warning* and plans a
  `delete` of the SOURCE.** Measured: `hcloud_volume.workspaces["web-1"] → no-op` while
  **`hcloud_volume.workspaces_luks → delete`** — i.e. *the old plaintext volume survives and the volume
  holding every migrated workspace is planned for deletion*, behind a **Warning**. The repo filter reports
  `resource_deletes: 1`, so the per-PR guard halts — with *"Add `[ack-destroy]` to acknowledge"*, **the
  exact prompt an author types past.** ⇒ the gate MUST carry named `old_volume_touched == 0` +
  `luks_volume_destroyed == 0` backstops and **no `[ack-destroy]` bypass**. *(The safe failure looks
  wrong: leaving the block declared gives a clean hard error. **`terraform validate` passes on the
  dangerous config — only `plan` catches it.** validate is not evidence for anything in Phase 5.)*
- **🔴 "destroy old" is impossible.** `hcloud_volume.workspaces` is `for_each = var.web_hosts`; the only
  way TF destroys `["web-1"]` is removing web-1 from the map — which **also destroys
  `hcloud_server.web["web-1"]`, the sole prod host, on a cx33 unorderable in all 3 EU DCs.** That is the
  fleet-wedging footgun, not a convergence step. And "destroy → `state rm`" is redundant.
  **Only coherent sequence:** API-detach → API-**delete** → `state rm` (volume **and** attachment) →
  PR removing the `workspaces_luks` blocks + adding **both** `moved`s → plan (expect rename-in-place
  only) → apply. **Order matters:** API-delete *before* `state rm`, else a failed delete leaves an
  invisible orphan billed at ~EUR 1.14/mo with nothing in state or config to surface it.
- **HIGH — the attachment `moved` is missing.** Volume-only `moved` ⇒
  `hcloud_volume_attachment.workspaces["web-1"].volume_id` (**ForceNew**) changes ⇒ **detach/attach churn
  on the live, mounted, in-use volume.** Add the paired `moved` + `state rm` (precedent: `placement-group.tf:28-36`).
- **HIGH — the job is undispatchable:** `workspaces-luks-cutover` must be added to the `apply_target`
  **`type: choice` options** (`apply-web-platform-infra.yml:96-105`) + the description at `:91`.
  `choice` rejects any value not in `options`.
- **HIGH — missing `concurrency: group: web-1-swap`.** The workflow-level group is inherited, but
  `warm_standby` (`:697`) and `web_2_recreate` (`:934`) each declare a **second job-level** `web-1-swap`
  group. A cutover that stops the container and rewrites web-1's fstab **must** serialize against those.
- **MED — `prevent_destroy` measured:** it applies to **every `for_each` instance** and fails the **whole
  plan** (`Error: Instance cannot be destroyed … hcloud_volume.workspaces["web-2"]`). It **rejects
  expressions** ⇒ Phase 5's "release" is a **PR+merge+apply**, not a dispatch input. **It also hard-blocks
  any future web-2 volume destroy if it lands first** — add to Phase 0. It is a **deviation, not a
  mirror** (`git-data-luks.tf` has no `lifecycle` block).
- **MED — DROP the dedicated Doppler config** (contradicts C6 — resolve at /work). git-data's rationale is
  *entirely* about a property web-1 lacks: web-1 **is** the host that legitimately holds
  `SUPABASE_SERVICE_ROLE`, and already carries full-prd. An attacker on web-1 reads the full-prd token and
  gets the key anyway ⇒ **zero blast-radius reduction**, at the cost of a config + token + delivery path +
  the **UNVERIFIED** precondition. **⚠️ C6 counters with a reason this review did not consider — the
  `--config prd` → `TMPENV` → `--env-file` injection into the *agent container*. That is a real,
  different boundary (host-vs-container, not host-vs-host). C6's argument survives; C18's does not
  defeat it. Keep the config, on C6's rationale.**
- **MED — use a SINGLETON, not `for_each`** (matches `git-data-luks.tf:79`, and `moved` wants a singleton
  source). A `for_each`'d attachment would land outside `web2_allow`
  (`destroy-guard-filter-web-platform.jq:96-100`) and **permanently brick the `web-2-recreate` path**.
  *Also: the plan **mis-cites** the `for_each` learning — `-target` pulls **dependencies, never
  dependents**, and nothing in the 92-address allow-list depends on the new volume, so it never appears on
  the per-PR path. Safe, but by a different mechanism than claimed.*
- **MED — gate test missing:** `tests/scripts/test-workspaces-luks-cutover-gate.sh` sourcing the same lib
  (CAP-COUPLING convention, jq `:48-52`). `workspaces-luks.test.sh` is a *different* artifact (`.tf` drift).
- **LOW — AC19's grep collides** with a legitimate `variable "workspaces_luks_volume_size"`. Scope it to the
  passphrase, or assert "no new `sensitive = true` variable".
- **LOW — missing:** the ephemeral SSH keygen step (`:2202-2209` — HCL evaluates `file()` at plan time
  **regardless of `-target`**); `labels = { app = "soleur-web-platform" }`; a size input (reuse `var.volume_size`).
- **LOW — `host_creates` reasoning inverted** (conclusion right, mechanism wrong): it fires on a pure
  `+ create` of `hcloud_volume` (**verified — Risk 10 discharged**), but the per-PR plan is `-target`-scoped
  and never reaches the new volume, so it would be **0** there. **The dedicated job is required because no
  other apply path exists**, not because a guard blocks one.

**Discharged — drop these /work TODOs:** `hcloud_volume.name` **is** update-in-place in 1.63.0 (measured:
`~ name … Plan: 0 to add, 1 to change, 0 to destroy`) · `host_creates` fires on a pure volume create
(Risk 10) · `random_password(40, special=false)` + **no** `ignore_changes` matches both precedents
(`live-verify.tf:30-31`: *"rotation is operator-explicit via -replace"*). Carry `visibility = "masked"`.

**Required gate counters:** `out_of_scope == 0` (exact `IN(.address; allow[])`, never `contains`) ·
`old_volume_touched == 0` (**AC20's STOP**) · `web1_server_touched == 0` (**highest-value line — a
destroyed web-1 is unrecoverable**) · `luks_volume_created >= 1` (anti-no-op) ·
`luks_attachment_created >= 1` · `resource_deletes == 0`.

### C19 — Flow: the plan is a decision record, not a state machine (spec-flow) 🔴

**The deepest finding — two of my OWN findings compose and I never noticed:**

- **🔴 The baked LUKS block AND the D2 fail-closed gate are DEAD CODE.** The bake (ADR-080) is consumed
  **only on a fresh create**; R4 says `ignore_changes` makes it inert on web-1; and **cx33 is unorderable
  ⇒ web-1 cannot be created.** So **the fresh-host path has no consumer** — and with it goes the very
  mechanism CPO's C6/G6 requires *"in this PR"* to stop silent root-disk writes **on the only host that
  exists**. AC15's mutation test would pass against a gate that never runs in prod. *(Compounds C2: the
  gate is bypassed on reboot AND never deployed.)* **Resolve before /work: the gate must reach web-1 via
  the cutover channel, not the bake.**
- **🔴 The escrow proof is tautological BY ORDER** — Phase 3 runs G5 **before** `prepare_luks_target`, so
  it *cannot* test the real volume. And it proves the **CI read path**, not the **host's service-token**
  path — the one that runs at boot, i.e. the exact F4 mode. **Re-order: `prepare_luks_target` → G5 against
  the real volume via the host's token path.** *(Compounds C3.)*
- **🔴 Rotation is named as F4's mitigation; the precedent gates against it as the catastrophe.**
  §Risks #2 offers *"rotation is `-replace`-explicit"* as the F4 mitigation — but `-replace` regenerates
  the passphrase and updates Doppler while **the volume header is untouched** ⇒ **that IS F4**, permanently,
  after the plaintext backstop is wiped. `git-data-host-replace-gate.sh` asserts **`luks_passphrase_touched == 0`**
  on exactly these grounds. **Add that predicate; strike the mitigation claim; spec `luksChangeKey` if
  rotation must be supported.**
- **🔴 The soak has ≥3 independent false-green paths** *(beyond C14's)*: the monitor is authored in Phase 5
  **after** the soak window opens, is **never activated** (no unit-enable task; cf. `cloud-init.yml:616`),
  and is **never delivered**; an auth failure returns zero events ⇒ **PASS** (no TRANSIENT case — the
  convention doc mandates one); and **`earliest=<canary+7d>` is a literal placeholder** — `iso_to_epoch`
  returns 0 on unparseable input ⇒ **gate opens ⇒ the soak runs on day 0**, finds zero events, PASSes, and
  **closes its own tracker**. Also: the declared secret names are **both wrong** (`SENTRY_AUTH_TOKEN`,
  `BETTERSTACK_QUERY_*`). ⇒ **the soak can go green on day 0 with the monitor never deployed and the volume
  plaintext, then authorize wiping the rollback volume.**
- **🔴 AC30's five post-conditions have NO ACTOR.** `sweep-followthroughs.sh` only `gh issue comment` +
  `gh issue close`. Nothing releases `prevent_destroy`, deletes the volume, converges state, flips the ADR,
  or opens PR 3. **Worse: the green soak closes the tracker — deleting the only reminder the work was owed.**
  This is the exact rot the sweeper exists to prevent (#5675/#5689). **Fix:** fold the work into the script
  before `exit 0` (precedent `web2-tunnel-depool-6425.sh`) **or** invert the criterion to *"the wipe already
  happened"* (precedent `inngest-rls-drop-6488.sh`).
- **🔴 No EXIT trap.** The precedent auto-rolls-back on any non-zero exit (`trap cleanup EXIT` +
  `FREEZE_HELD`/`FLIP_DONE`/`CANARY_OK` + a `ROLLBACK=1` mode). Task 2.4.12 lists rollback as a *terminal
  step*, not a trap. **Without a trap the ≤2h abort IS the stranded state, not the escape from it.**
- **🔴 The SSH gate is a probe, not a lease.** Reachability at gate-time ≠ at freeze-time, and the human
  sign-off makes Δ unbounded. If Access drops mid-freeze: container stopped, site down, **and rollback
  needs the SSH that just died.** No exit.
- **🔴 Five states have no exit:** G8-red *(and G8 can't execute in a ZERO-downtime phase — the container
  holds the bind mount, so the unmount is refused; G8-green is D1's load-bearing premise ⇒ a red G8
  retroactively invalidates the CPO sign-off)*; frozen-and-unreachable; soak-red *(rollback authority has
  already expired)*; Phase 0's *"re-price"* **(no procedure, no owner, no criteria)**; Phase 0's
  *"sequencing is invalid"* **(the highest-value check has no response to the only outcome that makes it
  high-value)**.
- **🔴 The single human sign-off has NO MECHANISM.** `git-data-cutover.yml` has **no `environment:`**; its
  only gate is a `confirm:` string it self-describes as a **typo-guard** that its own header expects a *bot*
  to type. And #4220 **deliberately removed** the `environment:` reviewer gate (13h waits) — but a
  `workflow_dispatch` cutover **has no merge**, so the doctrine's control (CODEOWNERS at merge) doesn't
  exist on this path. **Either reintroduce `environment:` on this one job with an explicit #4220
  counter-argument, or withdraw the §2.10 `Automation: not feasible` claim as false.**
- **P1 — the canary chain has a missing link:** `blkid(X)=LUKS ∧ findmnt(/mnt/data)=mapper` does **not**
  entail *"/mnt/data is served from encrypted X"*. **Add `cryptsetup status workspaces`** (mapper→device).
  AC23's `<dev>` is an unresolved placeholder — that's where the gap hides. And the canary is structurally
  **blind to partial data loss** (all four asserts pass while workspaces are missing) — relabel it; **G3 is
  the data gate**, not the canary.
- **P1 — no `count > 0` floor anywhere.** `rsync --dry-run` zero-transfers between two **empty** trees is
  zero transfers. If SRC is wrong-pathed, `DST == SRC == ∅` **passes**. Derive an absolute floor from G2.
- **P1 — the infra PR CANNOT MERGE:** the new LUKS resources must be added to `OPERATOR_APPLIED_EXCLUSIONS`
  (`terraform-target-parity.test.ts:534-548` — the canonical machine-readable list; the workflow's `:29-35`
  prose is only a comment). `host_creates` is **type-scoped** ⇒ `hcloud_volume.workspaces_luks` **is** in
  scope, evaluated **before** `destroy_count` ⇒ **`[ack-destroy]` cannot reach it.**
- **P1 — `canary_ok` has no source at wipe time** (precedent works because the wipe is the *same process*;
  here it is 7 days and a separate dispatch later). **The first gate of the double-gate has no source.**
- **P1 — PR ordering is never asserted.** If the infra PR merges before PR 1, the LUKS clause becomes true
  and PR 1's "temporally qualify" edit **understates a live control** ⇒ AC2 is wrong on arrival.
  *(AC9 is fine — P4 resolves it: DC-1 **is now on main**.)*
- **P1 — the runbook postdates the risk it mitigates** (authored Phase 5; the one-way door closes in Phase 4).
- **P1 — Phase 1's identity is self-contradictory:** headed *"ships alone"*, filed in tasks.md under
  *"PR 2 — Infra (BLOCKED)"*. It fixes a **live** latent bug (a reboot today writes workspaces to the root
  disk) — blocking it is a real ongoing cost. *(§Sequencing correction unblocks it.)*
- **P1 — no `DRY_RUN` task** despite Test Scenario 10 testing it.
- **P2 — mirroring propagates a latent precedent bug:** `cloud-init-git-data.yml:155` runs
  `doppler run --config prd` while its token is scoped `prd_git_data`; a service token is config-scoped ⇒
  the `--config` literal is stale. **Verify before copying.**

### C17 — ADR seed corrections (architecture)

- **Strengthen 4a's rejection into a dominance proof:** *any safe `reencrypt` is option 2 with extra
  steps* (to make it safe you must first create a second volume and rsync onto it — that **is** option 2,
  plus a shrink and a second rsync). Also: **4a does not save the freeze** (ext4 shrink needs the fs
  unmounted + fsck'd). Drop the probabilistic framing — it invites the rebuttal.
- **Delete 4b's wording argument** — "the published wording says LUKS" cannot be a fixed constraint
  when **PR 1 edits that wording**. The metadata-leak reason is sound and sufficient.
- **Name AP-002** (no SSH state mutation) explicitly as a recorded deviation discharged by the
  `git-data-cutover.yml` precedent, and **AP-009** (never delete user data) showing Phase 5's alignment.
- `status: adopting` is **correct** — verified against 4 in-repo ADRs incl. ADR-068's identical shape.

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
