# Tasks — feat-one-shot-6588-luks-workspaces-volume

Derived from `knowledge-base/project/plans/2026-07-17-fix-6588-luks-encrypt-workspaces-volume-plan.md`.
Read the plan first — the phase ORDER is load-bearing and several tasks exist to prevent a specific
verified failure mode, not as ceremony.

**lane:** `cross-domain` — no `spec.md` exists for this branch (no brainstorm ran; entered via
one-shot), so the lane defaulted to `cross-domain` fail-closed.

> ## ⚠️ READ `## Deepen Pass Corrections` IN THE PLAN FIRST — C1-C17 are BINDING
>
> The deepen pass found **four vacuous gates**. Do not implement the pre-deepen text below where a
> correction supersedes it. The highest-severity items:
>
> - **C1 🔴** the Phase-4 verify (2.4.5) **cannot go RED** — proven empirically. Use
>   `rsync -aHAXi … --out-format='%i %n' | wc -l == 0` and mutation-test it. **Delete the `chown`
>   after the verify** (any mutation after the verify voids it). Add `git fsck --full` + a `df -i`
>   capacity preflight. Drop caches before the checksum pass.
> - **C2 🔴** `--restart unless-stopped` (`cloud-init.yml:770`) **defeats the 2.1.3 gate on reboot** —
>   use `RequiresMountsFor=/mnt/data` + `chattr +i` the root-disk mountpoint.
> - **C3 🔴** the 2.3.6 escrow proof is **vacuous** — use `luksOpen --test-passphrase` against the
>   **real** device; no throwaway volume.
> - **C14 🔴** the host-side Sentry emit **does not exist** for a standing unit; the soak probe
>   **can never go RED**; `workspaces-luks-verify.yml` is cited but never created.
> - **C11 🔴** the C4 enumeration is **wrong** — Hetzner is an internal container, the volume is
>   unmodelled, the `views.c4` edit is vacuous. Redo, don't patch.
> - **C10** task 2.1.1 **contradicts a currently-passing CI guard**
>   (`soleur-host-bootstrap-observability.test.sh:166-170`) — add it to Files to Edit and re-point it.
>
> **Sequencing changed:** PR #6568 **merged docs-only**; web-2 survives; `var.web_hosts` still has
> both. **Phase 0 / task 2.0.1 is NOT a blocker** — proceed on **web-1 only** and scope web-2 out
> (see §Sequencing correction). Never gate on PR-merge status; check `var.web_hosts` directly.
>
> **Three PRs, not two:** PR 1 legal-retraction · PR 2 infra · PR 3 legal-flip.

**PR 1 (legal, decoupled) can start immediately. PR 2 (infra) is NOT blocked** (see above).

---

## PR 1 — Legal retraction (docs-only, no infra dependency, ship this week)

### 1.1 Enumerate

- [ ] 1.1.1 Run the union-anchor grep to enumerate ALL clause sites. **Do NOT `grep LUKS`** — two of
      seven canonical body sites carry the git-data-host clause with no `LUKS` token:
      ```
      grep -rnEi "LUKS|git.data host|dedicated host for per-workspace|re-verified|TLS-encrypted|encrypted in transit with TLS" \
        docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md \
        plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md
      ```
      Expect ~20 sites (7 canonical body + 3 `Last Updated` headers, ×2 mirrors). Verified at plan
      time: canonical hits are pp `:11,:298,:488,:518` · gdpr `:13,:44,:318` · dpd `:12,:189,:276`.
- [ ] 1.1.2 Confirm the count against the plan's Premise Validation P3. If it differs, the docs moved —
      reconcile before editing.

### 1.2 Retract + qualify

- [ ] 1.2.1 Retract clause (a) *dedicated per-workspace git-data host* — per-site, per-site anchor.
- [ ] 1.2.2 Retract clause (b) *cross-host TLS in transit* — note the variant wording (`dpd:276`
      "host↔host traffic is TLS-encrypted (in transit)" vs `gdpr:44` "traffic between the hosts is
      encrypted in transit with TLS"). **A literal find/replace silently misses sites.**
- [ ] 1.2.3 Retract clause (c) *membership re-verified across hosts* — variants include "re-verified
      on proxied sessions".
- [ ] 1.2.4 Temporally qualify the LUKS clause. Mechanism per PR #4455; **author the wording fresh** —
      #4455 is a Flagsmith sub-processor disclosure and does **not** contain the quoted phrasing.
      Anchor the duty in **Art. 12(1) + Art. 5(1)(a)**, NOT Art. 13(3).
- [ ] 1.2.5 Update the 3 `Last Updated` changelog headers — they restate the retracted claims in prose.
- [ ] 1.2.6 Bump `Last Updated` in **lockstep** canonical + mirror (parity test asserts equality).
- [ ] 1.2.7 **Do not assert a new false thing.** Verify every implementation claim in the NEW prose
      against `server.tf` / `cloud-init.yml` (the #4353/#4558 drift class). Do not write "host-local
      NVMe" without checking.

### 1.3 Close the mirror hole (BLOCKS 1.2 from shipping)

- [ ] 1.3.1 Write `apps/web-platform/test/legal-mirror-clause-retraction.test.ts`. **Path matters** —
      `vitest.config.ts` collects `test/**/*.test.ts{,x}`; a co-located test never runs.
- [ ] 1.3.2 Assert, for all 3 docs in **both** canonical and mirror: each retracted clause's semantic
      anchor **absent**, qualified LUKS wording **present**. Content anchors, not bare tokens
      (`cq-assert-anchor-not-bare-token`).
- [ ] 1.3.3 **Mutation-test it:** re-inserting a retracted clause into a **mirror** must go RED.
      A gate that cannot go red is worthless.
- [ ] 1.3.4 Register in CI.
- [ ] 1.3.5 **Do NOT** attempt the 8-doc body-equivalence remediation — separate scope; the
      pre-existing benign drift must be cleaned first (`check-tc-document-sha.sh:11-19`).

### 1.4 Re-pin SHAs

- [ ] 1.4.1 `sha256sum docs/legal/privacy-policy.md` → `LEGAL_DOC_SHAS["privacy-policy"]`.
- [ ] 1.4.2 Same for `data-protection-disclosure`, `gdpr-policy`. **No regen script exists** — by hand.
- [ ] 1.4.3 Confirm `tc-document-sha-guard` CI job green.

### 1.5 Compliance records

- [ ] 1.5.1 **Verify the next free PA ordinal**: `grep "^## Processing Activity" knowledge-base/legal/article-30-register.md | tail`. PA-16 collided once before.
- [ ] 1.5.2 CREATE the Art. 30 Processing Activity for workspace git-data storage. Limb (g) states the
      **TRUE current state**: "plaintext ext4 on `hcloud_volume.workspaces`; LUKS planned, Ref #6588".
      Writing the true state IS the Art. 5(2) fix — accountability, not confession.
- [ ] 1.5.3 Amend §Cross-Cutting TOMs (`article-30-register.md:443`) with an explicit Hetzner-volume
      limb **including today's explicit negative**. Silence is what failed.
- [ ] 1.5.4 Correct `knowledge-base/legal/compliance-posture.md:78` — the Hetzner DPA row asserts the
      never-born CAX11 as covered scope (Art. 28(3)).
- [ ] 1.5.5 Add a #6588 Active Item to `compliance-posture.md`.

### 1.6 Ship PR 1

- [ ] 1.6.1 PR body carries the **Tier 1** classification.
- [ ] 1.6.2 `Ref #6588` — **NOT `Closes`**.
- [ ] 1.6.3 Close DC-1 (it closes when PR 1 merges, not when #6588 does).
- [ ] 1.6.4 CLO attestation at ship Phase 5.5 → `knowledge-base/legal/audits/`. **Auto-routed — not a
      human task.**
- [ ] 1.6.5 File the deferral issues (see plan Deferrals): Art. 25(1) reconciliation gate, ledger rate
      correction, cpx32 price contradiction, body-equivalence, backup posture, cutover phantoms,
      roadmap staleness.

---

## PR 2 — Infra (BLOCKED on PR #6568)

### 2.0 Phase 0 — gates (no code)

- [ ] 2.0.1 Confirm PR #6568 merged. Re-derive `var.web_hosts` (expect `{web-1}`). Confirm
      `hcloud_volume.workspaces["web-2"]` destroyed. **If #6568 stalls: STOP and re-price.**
- [ ] 2.0.2 **HIGHEST-VALUE CHECK IN THE PLAN.** Verify the **live** host's actual `/etc/fstab` and
      mount state (read-only, via the sanctioned CI path). The glob finding is a *code-shape* finding.
      **If web-1 rebooted since first boot and `/mnt/data` is unmounted, the data is not where this
      plan assumes and the sequencing is invalid.**
- [ ] 2.0.3 Verify `host_creates` destroy-guard scope vs `hcloud_volume` (asserted from a workflow
      comment, not measured).
- [ ] 2.0.4 Verify hcloud provider 1.63.0: volume `name` is updatable in place (not ForceNew).

### 2.1 Phase 1 — Pin the mount, fail-closed (ships alone)

- [ ] 2.1.1 Replace the `cloud-init.yml:568-569` `scsi-0HC_Volume_*` glob with an explicit volume-ID
      device path. **Remove `|| true`.**
- [ ] 2.1.2 fstab line: explicit device + `nofail` + `grep -q` idempotency guard (git-data's `:170` form).
- [ ] 2.1.3 Add the **pre-`docker run` fail-closed mount gate**: refuse container start unless
      `findmnt -no SOURCE /mnt/data` == the mapper. (D2 synthesis — `nofail` prevents a boot hang; this
      prevents silent root-disk writes.)
- [ ] 2.1.4 Deliver to the live host through the cutover channel (`ignore_changes` ⇒ merge alone is inert).
- [ ] 2.1.5 `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` (budget 21,900).

### 2.2 Phase 2 — ADR + C4 + baked LUKS + drift guard

- [ ] 2.2.1 **First task:** re-verify the next free ADR ordinal against `origin/main`, then copy
      `specs/feat-one-shot-6588-luks-workspaces-volume/adr-118-seed.md` →
      `knowledge-base/engineering/architecture/decisions/ADR-118-*.md` with `status: adopting`.
      **If renumbered, sweep the plan + this tasks.md + every AC naming the ordinal in the same edit.**
- [ ] 2.2.2 C4: correct the `/workspaces` element description; add the **Doppler → web-host boot-time
      passphrase** edge to `model.c4`; add the `include` line to `views.c4` so it renders.
- [ ] 2.2.3 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 2.2.4 `workspaces-luks.tf`: `random_password` (len 40, `special = false`) + `doppler_secret` +
      read-only `doppler_service_token` + `hcloud_volume.workspaces_luks` + attachment. Mirror
      `git-data-luks.tf`. **No `TF_VAR`, no human-minted secret.**
- [ ] 2.2.5 Add `lifecycle { prevent_destroy = true }` to the OLD volume (CPO G7).
- [ ] 2.2.6 Verify in-band Doppler config creation (`doppler_config` resource) —
      `automation-status: UNVERIFIED`. **Attempt before any handoff.**
- [ ] 2.2.7 LUKS block into `soleur-host-bootstrap.sh` (baked, ADR-080). `--key-file -` via **stdin**,
      never argv. Fail loud on empty key — never an unencrypted fallback.
- [ ] 2.2.8 Write `apps/web-platform/infra/workspaces-luks.test.sh`, modelled on `git-data-luks.test.sh`.
      **Every predicate mutation-tested.** Content anchors, not line numbers.
- [ ] 2.2.9 Mutation cases: plaintext volume → RED; passphrase as argv → RED; `isLuks` guard removed →
      RED; unencrypted fallback → RED.
- [ ] 2.2.10 Register in `.github/workflows/infra-validation.yml` (pattern `:356-385`).

### 2.3 Phase 3 — Additive volume, gates, escrow, rehearsal, bulk rsync (zero downtime)

- [ ] 2.3.1 Write `.github/workflows/workspaces-luks-cutover.yml` + the `workspaces-luks-cutover`
      dispatch job in `apply-web-platform-infra.yml` (template: `git_data_host_replace` ~`:2158`).
      Sourced structured-plan gate, **no `[ack-destroy]` bypass**. Join the
      `terraform-apply-web-platform-host` concurrency group (R2 has no state lock).
- [ ] 2.3.2 Write `apps/web-platform/infra/workspaces-cutover.sh`. Copy the **shape** of
      `git-data-cutover.sh` — **never invoke it** (it calls two units that do not exist).
- [ ] 2.3.3 Apply: create + attach `hcloud_volume.workspaces_luks`. Verify `terraform plan` shows
      **0 to destroy** and no destroy/replace of `hcloud_volume.workspaces["web-1"]`.
- [ ] 2.3.4 **L3 gate:** assert SSH reachability via Cloudflare Access; abort if absent.
- [ ] 2.3.5 **L3 gate:** `dig +short +time=5 +tries=2 app.soleur.ai` + private `10.0.1.10` answers.
- [ ] 2.3.6 **G5 escrow proof (BLOCKING):** read the passphrase back from Doppler; **prove it unlocks a
      throwaway volume**. An unproven key is not a key. Negative test: a wrong passphrase must FAIL.
- [ ] 2.3.7 `prepare_luks_target`: luksFormat the **FRESH** volume (isLuks guard safe by construction).
- [ ] 2.3.8 **G2 manifest:** enumerate every workspace; `git rev-parse` **every** ref including
      `refs/checkpoints/*`; `git status --porcelain` dirty inventory → counts + SHAs.
- [ ] 2.3.9 **G8 rollback rehearsal:** prove the plaintext volume remounts and serves.
- [ ] 2.3.10 Pass-1 bulk `rsync -aHAX` against the live tree.

### 2.4 Phase 4 — The freeze (≤20 min budget, ≤2h hard abort, sign-off gated)

- [ ] 2.4.1 Halt `webhook.service` (prevents a CI deploy restarting the container mid-rsync).
- [ ] 2.4.2 `docker stop soleur-web-platform` — the sole writer.
- [ ] 2.4.3 **G4:** assert `fuser -vm /mnt/data` / `lsof +f -- /mnt/data` **EMPTY**.
- [ ] 2.4.4 Pass-2 delta `rsync -aHAX --delete` against the quiesced tree.
- [ ] 2.4.5 **Filesystem-level verify:** `rsync -aHAX --numeric-ids --checksum --delete --dry-run SRC/ DST/`
      prints **zero transfers** + file-count + byte asserts. **NOT a `rev-list` identity** (it would pass
      while dropping working-tree data). **NOT a count-match.**
- [ ] 2.4.6 Re-assert `chown 1001:1001 /mnt/data/workspaces` (must match the Dockerfile UID).
- [ ] 2.4.7 **G3:** re-verify the G2 manifest, assert **equality**, with `refs/checkpoints/*` as its own
      named check. *(Highest-probability silent loss.)*
- [ ] 2.4.8 `repoint_luks_mount`: mapper → **`/mnt/data`** (NOT a sibling path — `cloud-init.yml:776`
      hardcodes `/mnt/data/workspaces` into the bind mount). Backup fstab, rewrite, `findmnt` assert.
- [ ] 2.4.9 `docker start`; resume `webhook.service`.
- [ ] 2.4.10 **Canary:** `blkid TYPE=crypto_LUKS` AND `findmnt -no SOURCE /mnt/data == /dev/mapper/workspaces`
      AND app-level workspace read AND `https://app.soleur.ai/api/health` == 200.
- [ ] 2.4.11 Emit freeze-start/freeze-end timestamps; assert ≤20 min.
- [ ] 2.4.12 Any failed assert ⇒ rollback to the plaintext mount.

### 2.5 Phase 5 — Soak, converge, wipe

- [ ] 2.5.1 Write `apps/web-platform/infra/luks-monitor.{sh,service,timer}` (5-min timer; mirrors
      `disk-monitor`). Emit `{device_type, mount_source, mountpoint_ok, passphrase_source, host}` to
      Sentry `op:workspaces-luks-drift` — **5 discriminating fields, one event**.
- [ ] 2.5.2 Write `scripts/followthroughs/workspaces-luks-soak-6588.sh` — exit 0 iff zero drift events
      over 7d (`start=` pinned strictly AFTER the canary timestamp) AND Better Stack `status == "up"`.
- [ ] 2.5.3 Add the `<!-- soleur:followthrough … earliest=<canary+7d> secrets=… -->` directive +
      `follow-through` label; wire secrets into `scheduled-followthrough-sweeper.yml`.
- [ ] 2.5.4 Retain the plaintext volume **attached-unmounted, `prevent_destroy`, un-wiped, 7 days**.
- [ ] 2.5.5 On soak-pass: release `prevent_destroy` → double-gated wipe (canary_ok AND confirm_wipe) →
      Hetzner API delete.
- [ ] 2.5.6 TF convergence: destroy old → `state rm` → `moved` → rename.
- [ ] 2.5.7 Flip ADR-118 `adopting` → `accepted`.
- [ ] 2.5.8 Write `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6588.md`.
      **State the one-way door explicitly** — rollback authority expires at canary-pass. **No "log in
      and check" step** (`hr-no-ssh-fallback-in-runbooks`).
- [ ] 2.5.9 Open **PR 2 (legal)**: flip the LUKS clause to present tense; amend the PA's limb (g);
      re-pin `legal-doc-shas.ts` ×3.

### 2.6 Exit gate

- [ ] 2.6.1 `bash tests/scripts/test-all.sh` — read the **`N/N suites passed`** summary, not just the
      exit code (orphan-suite class).
- [ ] 2.6.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (**not** `npm run -w`).
- [ ] 2.6.3 `terraform-target-parity.test.ts` green (`user_data` still in `ignore_changes`).
- [ ] 2.6.4 Verify all 30 ACs in the plan.
