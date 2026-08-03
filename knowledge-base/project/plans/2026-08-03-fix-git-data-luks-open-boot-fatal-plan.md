---
title: "fix(infra): git-data rung-2 rehearsal dies at stage:luks_open — the birth mkfs sets an ext4 quota feature the target image's kernel cannot mount"
issue: 7204
branch: feat-one-shot-git-data-luks-open-fatal
date: 2026-08-03
type: bug
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# Fix the `stage:luks_open` boot fatal blocking the git-data rung-2 rehearsal

## Enhancement Summary

**Deepened on:** 2026-08-03
**Panels run:** plan-review (architecture-strategist, spec-flow-analyzer, scoped strong-model advisor) → 20 revisions R1–R20, all mechanical, all applied. deepen-plan (best-practices kernel research, learnings-researcher, git-history-analyzer, test-design-reviewer).
**Gates:** 4.5 network-outage **triggered and dispositioned**; 4.6 user-brand impact **pass**; 4.7 observability 5-field **pass**; 4.8 PAT-shaped **pass** (no hits); 4.9 UI wireframe **skip** (no UI surface); 4.10 encryption posture **pass**; 4.55 downtime/cutover **no trigger**.

### Key improvements from the deepen pass

1. **The root cause moved from "strongly supported" to confirmed against upstream.** Theodore Ts'o documented this exact failure mode; `ext4_enable_quotas()` is called unconditionally from `ext4_fill_super()` on the `quota` feature bit, and the missing `quota_v2` module yields `ESRCH`. Kernel-source and LKML citations are now in the plan.
2. **A load-bearing premise was refuted.** `tune2fs(8)` lists **both** `quota` and `project` as settable/clearable after filesystem creation — so the "migration-forcing, cannot fix forward" rationale behind guard B16 and the template comment is **wrong**. That false belief is *why* an unmountable feature set was pinned onto a store that did not yet exist. The fix-selection calculus changed as a result.
3. **Candidate (d) (`mount -o noquota`) was refuted before Phase 0 runs it** — the kernel *ignores* quota mount options when the feature bit is set. The probe still executes, but a pass would now be the surprising outcome.
4. **The apply-path claim in the first draft was false and is corrected.** Merging *does* fire `apply-web-platform-infra.yml` (path filter `apps/web-platform/infra/**`, not `*.tf`); safety comes from `-target` scope + `OPERATOR_APPLIED_EXCLUSIONS`, verified per-PR. A prior session made the identical mistake — there is a learning file for it.
5. **The regression-test design was rebuilt.** The original R1 was unimplementable in the named harness (it needed `--privileged` + loop devices the unprivileged harness does not have) and its RED control (`git show <merge-base>`) would have inverted the moment this PR merged. R1 is now an unprivileged superblock **fingerprint** check with an in-test mutation control; R2 is an explicit Phase-0 disposition rather than an assumed arm; R3 is re-scoped to what the container can actually observe.
6. **The diagnostic fix was corrected before it could regress four failure modes.** Seeding the detail file at *stage entry* (not at mount time) and ordering `dmesg` before the failing stderr are both load-bearing given the emitter's `tail -n 20 | tail -c 180` double-truncation.
7. **Premise validation: 20 of 20 cited claims CONFIRM** against a freshly-fetched `origin/main`, including every content anchor, every issue state, and the ADR ordinal.

### New considerations discovered

- The rung-2 FAIL artifact carries a verdict with **no cause** — `HOST_SQL` never selected `detail`. The cause of this incident was recoverable only by hand-writing a new Better Stack query.
- The capture script's header contains a **false capability claim** ("Sentry has no search capability wired in this repo"). Sentry search works today via `SENTRY_ISSUE_RO_TOKEN`, which materially changes what #7116 could do.
- The C4 model still describes the rehearsal route as "deliberately UNFIRED"; it has fired four times and consumed three paid hosts.
- Ordering-vs-co-presence is the specific defect class this plan's Phase 1.4 is exposed to, and a grep proving both lines exist cannot detect it.

---

Tracking issue: **#7204**.
Related, referenced and NOT closed: **#7025** (DO-NOT-DISPATCH banner — this fix is its precondition), **#7116** (capture mis-reports TRANSIENT for early-boot fatals), **#6588** (P1: user source code unencrypted at rest), **#7117** (the immediate predecessor whose fix exposed this one).

> **Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).** No `knowledge-base/project/specs/feat-one-shot-git-data-luks-open-fatal/spec.md` exists; this plan is the first artifact on the branch.

---

## Overview

`soleur-git-data` — the host that will store every connected user's source code — has never been born. Its birth is gated on a rung-2 boot rehearsal producing `apps/web-platform/infra/git-data-rung2-boot-evidence.env`, and that rehearsal has died three times. The most recent death (run **30649892865**, 2026-07-31T17:06:57Z) is a **genuine defect in the shared cloud-init template**, not an artifact of the rehearsal fixture: the birth `mkfs.ext4` sets an ext4 superblock feature that the target image's kernel structurally cannot honour, so the very next line — the mount of the LUKS mapper — fails with `ESRCH` on every fresh boot.

The mechanism, end to end:

1. `apps/web-platform/infra/cloud-init-git-data.yml` runs `mkfs.ext4 -q -O quota,project /dev/mapper/git-data`, setting the ext4 `quota` RO_COMPAT superblock feature.
2. On the very next mount, `ext4_fill_super` unconditionally calls `ext4_enable_quotas()` whenever `ext4_has_feature_quota(sb)` holds — the mount options are irrelevant to that branch.
3. That reaches `dquot_load_quota_sb()` → `find_quota_format(QFMT_VFS_V1)`, which returns `NULL` when no quota format is registered and `request_module()` cannot load one. `dquot_load_quota_sb` then returns **`-ESRCH`**.
4. **Measured:** the stock Ubuntu 24.04 server cloud image installs `linux-image-virtual` + `linux-modules-6.8.0-136-generic` and **does not install `linux-modules-extra-*`** — while `lib/modules/*-generic/kernel/fs/quota/quota_v2.ko.zst` ships **only** in `linux-modules-extra-*-generic`. The generic kernel config carries `CONFIG_QFMT_V2=m`. So there is no `quota_v2` on disk to load.
5. `mount(2)` therefore returns `ESRCH`; `mount(8)` prints `mount(2) system call failed: No such process` and exits **32**; the heredoc's `set -euo pipefail` trips the `luks_err` EXIT trap, which emits `stage:luks_open level:fatal rc:32`.

That is exactly the observed event. **`cryptsetup luksFormat`, `luksOpen` and `mkfs.ext4` all succeeded** — the mapper existed, or `mount` would have reported a missing special device rather than `ESRCH`. The boot died one line from the end of the stage.

The fix is small; the discipline around it is not. Three things make this plan longer than the diff:

- The fix touches a **migration-forcing** choice on a store that has not yet been created, pinned by an existing mutation-armed guard (`git-data-luks.test.sh` B16) that exists specifically to stop someone doing what this plan proposes. That guard is not wrong — it must be *re-aimed*, and the decision recorded in an ADR.
- The regression test must be able to **fail on the unfixed template**, and the obvious runtime test cannot: a Docker container shares the host kernel, so on any runner whose kernel provides `quota_v2` the unfixed template mounts fine. This plan measured that directly (see Hypotheses H4) and designs around it.
- The rehearsal reported a **verdict with no cause**. The cause was recoverable only by writing a new Better Stack query by hand. That is a defect in the diagnostic route itself and is in scope, bounded.

**Do NOT dispatch** the rehearsal (`dry_run=false` spends a paid host) or the birth (environment-gated on a human reviewer). Land the fix only.

---

## Premise Validation

Every claim this plan carries by reference was probed against a freshly-fetched `origin/main` during deepen-plan (attribution, not merely state — a cited PR can be genuinely merged while the claim about what it did is false). **20 of 20 claims CONFIRM; zero contradictions; zero unverifiable.**

- **PR #7117** merged 2026-07-31T17:05:52Z as `2cd251885`; `git merge-base --is-ancestor` confirms it is an ancestor of `origin/main`. Run **30649892865**'s `headSha` **is** that commit. The rehearsal workflow shows exactly **4** dispatches (1 success 2026-07-30T15:49, 3 failures). `git log origin/main --since=2026-07-31 -- apps/web-platform/infra/cloud-init-git-data.yml` shows that commit as the **only** change — so the fatal is live on today's `main`.
- **`git-data-rung2-boot-evidence.env` is absent** on `origin/main` (`git cat-file -e` fails) — the blocker chain's premise holds.
- **#7025, #7116, #6588 are all OPEN**; #7204 (this plan's tracking issue) exists and is open. None is closed-by-a-merged-PR, so the plan is not built on a stale premise.
- **Every content anchor resolves**, cited by content rather than line number alone (`cq-cite-content-anchor-not-line-number`): the three `mkfs.ext4` invocations, the three assertion floors (101 / 19 / 65), the `OPERATOR_APPLIED_EXCLUSIONS` comment, the rehearsal workflow's evidence-merge command block, AP-018 in `principles-register.md`, the `"deliberately UNFIRED"` sentence in `model.c4`, and ADR-147 / ADR-152.
- **ADR ordinal**: highest on `origin/main` is **ADR-157**, so **ADR-158** is the next free ordinal — derived from a fresh `git fetch origin main`, not the branch base. It remains provisional; `/ship`'s collision gate re-verifies at merge.
- **All AGENTS.md rule IDs cited in this plan are active** (checked against `[id: …]` in `AGENTS.md`; none retired, none fabricated). **All three GitHub labels** applied to #7204 exist.

## Research Reconciliation — Spec vs. Codebase

| Claim carried into this plan | Reality, verified | Plan response |
|---|---|---|
| "All four assertion booleans are empty ⇒ the host died AT LUKS open — before mount, before repo root, before hooks path, before provision." | **Partly false as inference.** `HOST_SQL` in `git-data-rung2-evidence-capture.sh:184-197` extracts `luks_mounted/repo_root/hooks_path/provision` from the row's JSON. `git-data-bootstrap.sh` emits those four only on `boot_complete`; the `luks_err` trap passes only `rc=`. They are **structurally empty on every non-`boot_complete` row**. The stage tag alone carries the "died at luks_open" fact. | Do not treat the four empties as independent evidence anywhere in this plan or the issue. Fold the `detail` column into `HOST_SQL` (Phase 3) so the artifact's most prominent columns are the informative ones. |
| "Everything before `doppler run` reaches SENTRY ONLY." | **True, and load-bearing in the opposite direction from how it was framed.** The fatal row *did* reach Better Stack, which (emitter, `cloud-init-git-data.yml` Better Stack block gated on `BETTERSTACK_LOGS_TOKEN`) is only possible from inside the `doppler run` child. That proves `doppler run` succeeded, the scratch config resolved, and the secrets were injected. | Used as a positive discriminator: it eliminates the entire Doppler-scope hypothesis family (`#6982 W0` class) without a further probe. |
| "Is this a rehearsal artifact of stub volume ids / scratch Doppler config?" | **No.** `rehearsal.tf:9-14` states and implements that the volumes are real Hetzner volumes and the passphrase a real `random_password` in a real scratch config, with `depends_on` ordering the secret before the host. A stub-id draft was explicitly rejected. | Answered decisively in §Template-vs-Rehearsal below. |
| "The rehearsal diverges on 8 vars, so divergence could explain it." | Only `git_data_luks_volume_id` of the 8 reaches the LUKS block, and it demonstrably resolved. `git_data_server_type` (`cpx22`), `location` (`hel1`), `git_data_volume_size` (10), `git_data_luks_volume_size` (10) and `image` (`ubuntu-24.04`) are byte-identical between `rung2-rehearsal/variables.tf` and `apps/web-platform/infra/variables.tf`. | Divergence eliminated as a cause with named evidence, not by assertion. |
| Capture script header: *"Sentry has no search capability wired in this repo … the `event:read` scope lives in a token this route does not carry."* | **False today.** `SENTRY_ISSUE_RO_TOKEN` (Doppler `soleur/prd`) returns HTTP 200 on `/api/0/organizations/jikigai-eu/issues/?query=…`, `/issues/<id>/events/?full=true` and `/tags/<key>/values/`. The full 5-event stage timeline for the failing host was pulled that way. | Correct the comment (Phase 3). Do **not** fix #7116 here, but record the capability so #7116 is planned against reality (`hr-verify-repo-capability-claim-before-assert`). |
| C4 `model.c4:214` `gitDataStore`: "#7025 shipped the gated rehearsal ROUTE that produces it … deliberately **UNFIRED**." | **Falsified.** The route has been dispatched four times (one dry-run success, three real-host failures) and has consumed three paid hosts. | In-scope C4 correction (Phase 5). |

---

## Hypotheses

The `hr-ssh-diagnosis-verify-firewall` checklist does **not** fire on the *prose* trigger: no SSH/handshake/timeout/unreachable symptom, and neither Terraform root carries a `provisioner`/`connection` block (`rehearsal.tf:167-172` states the cloud-init-only posture explicitly). It **does** fire on the resource-shape trigger via the merge-time apply — dispositioned in the deep-dive below.

Verdicts below are stated against the discriminator that produced them. Nothing is marked CONFIRMED on reasoning alone.

| # | Hypothesis | Verdict | Discriminator actually run |
|---|---|---|---|
| H1 | `doppler run` failed / scratch config unreachable / `GIT_DATA_LUKS_KEY` absent (the `#6982 W0` class) | **REFUTED** | The fatal row reached **Better Stack**, whose emitter block is gated on `BETTERSTACK_LOGS_TOKEN` — present only under `doppler run`. Injection demonstrably worked. Both secrets are written by the same `depends_on`-ordered terraform. |
| H2 | The LUKS device path did not resolve (attachment race / stub id) | **REFUTED** | `mount(8)` reported `ESRCH` against `/dev/mapper/git-data`; a missing mapper produces `special device … does not exist`. The mapper existed ⇒ `luksFormat`+`luksOpen` ran and succeeded. |
| H3 | `cryptsetup` absent (the `127`-swallowed-by-`if !` shape the `sshd_config` stage guards against) | **REFUTED** | Same as H2 — the mapper exists, so `cryptsetup` ran. (The latent `if ! cryptsetup …` 126/127 hole is still real; see Risks.) |
| H4 | The `-O quota,project` filesystem is unmountable *in general* | **REFUTED** | Privileged-container probe, four arms (`-O quota,project`, `-O quota`, `-O quota,project` + `-o prjquota`, plain) over a real loop device + `luksFormat`/`luksOpen`, kernel `7.0.0-28-generic`: **all four mounted, rc=0**, `dmesg` showing `Quota mode: journalled`. The defect is kernel-dependent, not filesystem-dependent. **This is why a container-based runtime guard cannot fail on the unfixed template.** |
| H5 | The `quota` superblock feature forces `ext4_enable_quotas()` at mount; the target image has no `quota_v2` to load, so `find_quota_format` returns NULL and `dquot_load_quota_sb` returns `-ESRCH` | **CONFIRMED**, modulo A1 below | (a) Errno match: `mount(2)` = `ESRCH`, `mount(8)` rc=32 — both measured on the host. (b) Ubuntu `noble` Contents index: `fs/quota/quota_v2.ko.zst` is in `linux-modules-extra-*-generic` only; `ext4.ko` has no generic row (built in) as a working control for the grep. (c) `CONFIG_QFMT_V2=m` on the generic kernel. (d) **Ubuntu 24.04 server cloud image manifest** (`ubuntu-24.04-server-cloudimg-amd64.manifest`, 664 packages): `linux-image-virtual`, `linux-modules-6.8.0-136-generic` present; **`linux-modules-extra-*` ABSENT**; no `quota` userspace package either. (e) Fleet natural experiment: `cloud-init-registry.yml:790` and `workspaces-cutover.sh:1042` `mkfs` **without** quota features on the same image and mount successfully in production; git-data is the only one that sets them and the only one that fails at mount. |
| A1 | **Assumption, not yet discharged:** Hetzner's `ubuntu-24.04` image *is* the stock Ubuntu cloud image (or at least shares its `linux-modules-extra`-absent package set) | **OPEN** | Every observable is consistent with it, and no cheap probe closes it without either SSH (forbidden, `hr-no-ssh-fallback-in-runbooks`) or a paid host (forbidden by scope). **Phase 1 therefore requires a fix that is correct whether or not A1 holds** — see the Fix-selection rule. |

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

The gate fires on the **resource-shape trigger**, not the prose trigger: merging this PR runs `apply-web-platform-infra.yml`, whose push-time `-target` set includes `terraform_data.git_data_probe_install` — a resource carrying `connection { type = "ssh" }` plus `provisioner "file"`/`remote-exec` against live `web-1` (`server.tf:733-765`). Per `hr-ssh-diagnosis-verify-firewall` the L3→L7 order is mandatory, so each layer is dispositioned rather than skipped. Telemetry emitted.

| Layer | Status for this change | Verification artifact |
|---|---|---|
| **L3 — firewall allow-list / egress IP** | **Not reached.** The provisioner only runs if the resource replaces, and its `triggers_replace` hashes exactly `web-git-data-probe.{sh,service,timer}` + the probe service token (`server.tf:737-743`). None is in Files to Edit. | Read of `triggers_replace` inputs vs. this plan's Files-to-Edit list — a set intersection, verified empty. |
| **L3 — DNS / routing** | **Not reached**, same reason. | As above. |
| **L7 — TLS / proxy** | **Not applicable.** No HTTPS surface changes; the git-data host's own egress (Sentry, Better Stack, Doppler CDN, GitHub) is unchanged by this plan. | The emitter's `curl` invocations are untouched (Phase 1 edits the LUKS heredoc and the detail file, not the emitter's transport). |
| **L7 — application** | **This is where the defect lives**, and it is not a network fault at all: `mount(2)` returned `ESRCH` from the ext4/quota subsystem on a host with working egress (it had already downloaded the Doppler CLI over the network and shipped two events off-box). | The fatal reached **both** Sentry and Better Stack from the failing host, which is itself proof that L3/L4/L7 egress was healthy at the moment of failure. |

**Conclusion: no network hypothesis is live, and the discharge is by scope rather than by assumption.** If a future revision adds any of `web-git-data-probe.{sh,service,timer}` to Files to Edit, this discharge is void and the full L3→L7 checklist applies before any sshd/fail2ban-shaped hypothesis may be entertained.

**What remains genuinely unknown**, stated so a later reader does not over-read this table: the untruncated `/var/log/cloud-init-output.log` (host destroyed by the workflow's `if: always()` teardown; the emitter ships only the last 180 bytes), the `dmesg` output the mount error points at, and any Better Stack rows for the 2026-07-30 run (aged out of a ~72 h retention floor — **unverifiable, not silent**).

---

## Template defect, not a rehearsal artifact — the load-bearing answer

**Verdict: genuine template defect. The real birth would die identically.**

Evidence, each item independently checkable:

1. **The failing lines are template lines rendered from the shared module.** `mkfs.ext4 -q -O quota,project /dev/mapper/git-data` and `mountpoint -q /mnt/git-data-luks || mount /dev/mapper/git-data /mnt/git-data-luks` live in `apps/web-platform/infra/cloud-init-git-data.yml`, rendered through `modules/git-data-userdata` by **both** roots (`git-data.tf:295-301` and `rung2-rehearsal/rehearsal.tf:143-165`).
2. **No divergence variable reaches them.** The declared set is identity-only: `host_name, git_data_volume_id, git_data_luks_volume_id, doppler_token, doppler_config_name, git_transport_pubkey, git_provision_pubkey, git_remove_pubkey`. Only `git_data_luks_volume_id` appears in the LUKS block (as `$DEV`), and H2 shows it resolved.
3. **Every non-divergent axis that could plausibly matter is byte-identical to prod**: `git_data_server_type = cpx22`, `location = hel1`, `git_data_volume_size = 10`, `git_data_luks_volume_size = 10`, `image = ubuntu-24.04`.
4. **The cause is image-level, and the image is the same one.** H5's mechanism depends on the kernel's module set, which is a property of `ubuntu-24.04` — a MUST-MATCH axis, not a divergence axis.

**Therefore the "if it is a rehearsal artifact, say how the rehearsal can still produce valid evidence" branch does not apply.** The gate is not unsatisfiable by construction: fix the template, and the same rehearsal route produces evidence hash-bound to the corrected template. Recorded here explicitly so the branch is visibly closed rather than silently skipped.

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing new *today* — `soleur-git-data` is unborn, so no user data is on it. The harm is the status quo persisting: every connected user's source code stays on the plaintext `hcloud_volume.workspaces` path while the privacy policy claims LUKS encryption-at-rest (#6588). A *wrong* fix is worse than none: any change that makes the mount succeed by weakening the store — a fallback to an unencrypted device, a `|| true` on the mount, a mount of the raw volume instead of the mapper — would let the birth proceed and put a real user's source code on plaintext disk while every artifact attests encryption.

**If this leaks, the user's source code is exposed via:** an at-rest read of the Hetzner block volume (snapshot, decommissioned disk, provider-side access) for any repository written to a store whose LUKS mapper was not actually the mounted device. The `[ -n "$GIT_DATA_LUKS_KEY" ] || … refusing unencrypted mount` guard and the mapper-path mount are the only two things standing between "encrypted at rest" and "not"; this plan touches the lines immediately adjacent to both.

**Brand-survival threshold:** `single-user incident`.

Consequences, per the sign-off lifecycle: `requires_cpo_signoff: true` in frontmatter (CPO sign-off at plan time — carried by the Phase 2.5 domain sweep below, which spawned CPO); `user-impact-reviewer` is invoked at review time by `review/SKILL.md`'s conditional-agent block; `deepen-plan` Phase 4.6 and preflight Check 6 gate on this section's presence.

**Hard constraint carried into every phase:** no fix may make the mount succeed by reducing what is encrypted. If the corrected template cannot mount the mapper, it must **fail loud with the cause named** — never fall through.

---

## Encryption Posture

Detection fires: `## Files to Edit` includes `cloud-init-git-data.yml` (matches `cloud-init.*\.ya?ml$`) and the change alters how the persistent store's filesystem is created.

```yaml
at_rest:
  - store: hcloud_volume.git_data_luks (the FRESH cutover target, /mnt/git-data-luks)
    mechanism: guest-side LUKS2 (cryptsetup luksFormat --type luks2), passphrase delivered
               ONLY as the Doppler-injected env GIT_DATA_LUKS_KEY, never in user_data and
               never an argv positional
    evidence: apps/web-platform/infra/cloud-init-git-data.yml STAGE=luks_open heredoc;
              measured 2026-07-31 on rehearsal host -30649892865, where luksFormat and
              luksOpen SUCCEEDED (the mapper existed) — this plan does not change that
    defends_against: at-rest read of the detached/decommissioned/snapshotted Hetzner block
                     device by anyone without GIT_DATA_LUKS_KEY
    does_not_defend: a live host (the mapper is open and the filesystem mounted while the
                     host runs); anyone who can read the Doppler prd_git_data config; an
                     in-guest root compromise; Hetzner-side memory access
    disclosed_as: privacy policy "encryption at rest"; #6588 is the open P1 asserting the
                  claim currently outruns the implementation
    live_verification: NOT YET POSSIBLE — the host does not exist. The rung-2 rehearsal is
                       the only route that measures it, and it is the thing this plan
                       unblocks. Post-fix verification is the rehearsal's own PASS row,
                       not an operator dashboard.
  - store: hcloud_volume.git_data (the PLAINTEXT Phase-2 store, /mnt/git-data)
    mechanism: plaintext-exception
    evidence: git-data.tf hcloud_volume.git_data, format = "ext4", no LUKS apparatus;
              already recorded in encryption-posture-ledger.json
    defends_against: nothing at rest
    does_not_defend: any at-rest read of the device
    disclosed_as: ledgered exception, tracking #6897
    live_verification: n/a (unprovisioned)
in_transit:
  - connection: git-data host → Sentry (boot-stage fatals, baked DSN)
    tls: yes (https, curl -sf)
    cert_verification: on (curl default; no -k anywhere in the emitter)
    does_not_defend: Sentry-side retention/access; the event body is sanitised by the
                     emitter's _clean/_devalue redactor, not encrypted end-to-end
    disclosed_as: sub-processor disclosure (Sentry)
  - connection: git-data host → Better Stack Logs ingest (post-Doppler stages only)
    tls: yes (https)
    cert_verification: on
    does_not_defend: same as above; the ingest token is write-only against shared source
                     2457081, so a host compromise yields no readback
    disclosed_as: sub-processor disclosure (Better Stack)
exception:
  - store: hcloud_volume.git_data (plaintext)
    justification: pre-existing Phase-2 store; the LUKS volume is its cutover TARGET and
                   the cutover is gated on GIT_DATA_STORE_ENABLED. Out of scope here.
    tracking_issue: 6897
    reevaluate_when: the git-data birth completes and git-data-cutover.sh runs
    expires_on: 2026-12-31
```

**No new store and no new connection is introduced by this change.** The posture above is the existing one, restated because the change edits the filesystem-creation line of an encrypted store.

---

## Implementation Phases

### Phase 0 — Probe-first. Ships alone, before any fix line is written.

Phase ordering here is load-bearing (`knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`): the measurement decides between fixes that differ in migration cost, so it cannot be folded into the fix commit.

**0.1 — Reproduce the ESRCH determinism question, and record the answer honestly.**
Re-run the four-arm privileged-container probe (loop file → `luksFormat` → `luksOpen` → `mkfs` arm → `mount`) already run at plan time, and record in the commit message that **all arms pass on a kernel that provides `quota_v2`**. This is the evidence that the naïve runtime guard cannot fail on the unfixed template; the regression test in Phase 2 is designed around it and must not be reverted to the naïve form later.

**0.2 — Measure the candidate fix set in the same container.** For each candidate, record `dumpe2fs -h` features and `mount` rc:

#### Research Insights — the mechanism is now confirmed upstream, and one premise is refuted

Deepen-plan research against kernel.org, LKML and the e2fsprogs man pages. **These findings change the fix calculus and must be read before Phase 0.2 runs.**

**1. The ESRCH chain is confirmed, and this is a known, documented failure mode.** Theodore Ts'o documented exactly this: an ext4 filesystem carrying the `quota` RO_COMPAT feature fails to mount with `ESRCH` ("No such process") when the quota code is built as a module and `quota_v2` is not available. `ext4_enable_quotas()` is called **unconditionally** from `ext4_fill_super()` when the feature bit is set. A later kernel patch (`9db176bceb5c`, *"ext4: fix mount failure with quota configured as module"*) added `IS_ENABLED()`-based autoloading — which cannot help here, because on this image the module **is not on disk at all**, so `request_module` has nothing to find. H5 moves from *strongly supported* to **confirmed against upstream**; only A1 (Hetzner image == stock Ubuntu cloud image) remains, and Hetzner's own changelog documents `ubuntu-24.04` (image ids 161547269 / 161547270) as the stock Canonical cloud image, which narrows A1 substantially.
   - Refs: <https://docs.kernel.org/admin-guide/ext4.html>, <https://lkml.iu.edu/hypermail/linux/kernel/2002.3/05061.html>

**2. Candidate (d) is REFUTED by upstream before Phase 0 runs it — but run it anyway.** The kernel **ignores** quota mount options entirely when the feature bit is set: the patch *"ext4: ignore quota mount options if the quota feature is enabled"* (merged 3.19/4.4/4.5) changed the behaviour from *failing* the mount to *silently ignoring* the options, matching XFS. Kernel docs state the quota mount options "are ignored by the filesystem … used only by quota tools". So `-o noquota` **cannot** rescue a `quota`-featured filesystem. Phase 0.2.4 still executes it — a two-minute local confirmation of a documented negative is cheap, and this plan does not mark things confirmed on reading alone (`knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`) — but it is now expected to fail, and a *surprising pass* would be the finding.
   - Ref: <https://lkml.iu.edu/hypermail/linux/kernel/1604.2/00669.html>

**3. ⚠️ The "migration-forcing" premise behind B16 is REFUTED.** `tune2fs(8)` lists **both** `quota` and `project` among the features that can be set and cleared **after** filesystem creation on an unmounted filesystem. The template comment (`#6982 W5/R31`) and B16's rationale both assert the opposite — that these ship at birth or need "a replace PLUS an rsync of every user's objects". That is the belief that pinned an unmountable feature set onto a store that had not yet been created, and it is wrong.
   - **What is genuinely not free later:** `tune2fs -O quota` sets the superblock flag; it does not populate a quota database, so enabling enforcement later additionally needs the `quota` userspace package (absent from the image) and a `quotacheck` pass. That is an *operational* step on an unmounted volume — not a volume replace, and not a data migration.
   - **Consequence for the fix:** candidate **(c) plain `mkfs.ext4`** — sibling parity with the two working production LUKS stores — is now a *low-future-cost* option rather than a capability write-off, and candidate **(a) `-O project` alone** is viable because `ext4_enable_quotas()` is gated on `RO_COMPAT_QUOTA`, not on `project`. Phase 0.2 still measures both; what changed is that criterion (b) no longer strongly favours keeping the flags.
   - Refs: <https://manpages.debian.org/unstable/e2fsprogs/tune2fs.8.en.html>, <https://manpages.debian.org/unstable/e2fsprogs/mke2fs.8.en.html>

**4. `-O project` without `quota` is accepted but only half a capability.** mke2fs sets the project-ID inode field, but creates no quota inodes, so project-quota *enforcement* does not work; `-E quotatype=prjquota` "has effect only if the quota feature is set". Phase 0.2.1 must therefore report not just "does it mkfs and mount" but "what does it actually buy" — otherwise the ADR records a preserved capability that is inert, which is precisely the error the current template made.

| Candidate | Question the probe answers |
|---|---|
| `mkfs.ext4 -q -O project` (no `quota`) | Does mke2fs accept `project` without `quota`? Does the resulting superblock carry `quota`? (If it does **not**, `ext4_enable_quotas()` is never reached and the mount is quota-module-independent — the strongest candidate, because it preserves the genuinely migration-forcing half.) |
| `tune2fs -O quota <dev>` on a `project`-only fs | Is the `quota` feature addable **later**, offline, without recreating the volume? This is the fact that decides whether B16's "migration-forcing" framing applies to `quota` at all, or only to `project`. |
| `mkfs.ext4 -q` (plain) | The sibling-parity baseline (`cloud-init-registry.yml:790`). |
| `mkfs.ext4 -q -O quota,project` + `mount -o noquota` | Does the `noquota` mount option escape the feature-driven enable path? **Expected NO** — `ext4_enable_quotas()` is gated on the feature bit and enables every type with a non-zero quota inode regardless of mount options. Probe it rather than assume it; a wrong answer here would change the fix. |

**0.3 — Re-verify the image fact.** Re-fetch `https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.manifest` and pin the observed `linux-*` package set + fetch date into the fix's comment block, so a future reader can tell a stale claim from a measured one. Record that `linux-modules-extra-*` is absent and that `quota_v2.ko` lives only there.

**0.2b — probe `project`'s offline-addability too, not only `quota`'s. [advisor]** If **both** are addable later via `tune2fs`, then criterion (b) below stops distinguishing `-O project` from plain `mkfs.ext4`, and sibling parity (candidate c) becomes the simpler correct answer. Without this probe the fix may be chosen on an unverified asymmetry.

**0.6 — measure the emitter's detail budget before Phase 1 needs the answer. [R3-rev]** Write a representative detail file by hand (20 `dmesg` lines followed by a realistic multi-line `mount` stderr, and the reverse ordering), run each through the **shipped** `_clean`, and report which bytes survive `tail -n 20 | … | tail -c 180`. This is the measurement Phase 1.4 gates on, and it is fully available before Phase 1 exists.

**0.7 — decide R2's disposition explicitly** (drop / promote rung 1 to privileged / push to rung 2), per Phase 2. If "promote", the taxonomy change goes in the Phase 4 ADR.

**Fix-selection rule (must be written into the plan record before Phase 1 starts):** choose the candidate that (a) produces a filesystem whose mount does **not** depend on `quota_v2`, and (b) preserves the largest amount of future capability at zero present cost, and (c) is correct **whether or not A1 holds** — i.e. does not depend on the target image's module set at all. A candidate that installs `linux-modules-extra-$(uname -r)` at boot fails (c): it adds a new network-dependent boot failure mode on a console-less host to buy a capability that is *also* unusable today (the image ships no `quota` userspace tooling either, and the template deliberately does not pass `prjquota` at mount).

> **Criterion (c) is NOT dischargeable by a mount rc, and the plan must not pretend otherwise. [R4-rev]** Phase 0.2 measures `mount` in a container whose kernel — by H4's own finding — *has* `quota_v2`. A green mount there cannot distinguish "needs no module" from "the module happened to be present": criterion (c) is exactly what that probe is blind to. Two escapes were considered:
> - *Simulate the target's module set in the container* (`modprobe -r quota_v2` plus an `install quota_v2 /bin/false` in `/etc/modprobe.d/`). **Rejected — it does not work.** `find_quota_format` reaches the module loader via `request_module()` → `call_usermodehelper`, which runs in the **init namespace**, so a container's `/etc/modprobe.d` is never consulted and the host's `quota_v2` loads anyway. Unloading it host-side has the same problem in reverse: `request_module` simply reloads it. Simulating this condition needs a VM, not a container.
> - **Adopted:** discharge (c) as a **feature-bit argument, not a mount observation** — assert which superblock bits `ext4_fill_super` gates a module load on, and treat `mount` rc as a sanity signal only. This is the same reasoning that makes R1 (not R2) the guard, applied one level up. The ADR must record (c) as discharged *by construction*, never as "measured", or it will record "measured" for a property nobody measured.

**Candidate table — one enumerated set, referenced by both Phase 0 and the Phase 4 ADR. [R6]** The first draft listed four candidates in Phase 0 and a *different* four in the ADR's Alternatives, making AC9 unsatisfiable against either. The canonical set is: **(a)** `-O project` without `quota`; **(b)** `tune2fs -O quota`/`-O project` as a later-addition path; **(c)** plain `mkfs.ext4` (sibling parity); **(d)** keep `quota,project` + `mount -o noquota`; **(e)** keep `quota,project` + install `linux-modules-extra` at boot. Every candidate needs a disposition in the ADR; **"rejected a priori by rule (c)"** is a valid disposition and is (e)'s.

### Phase 1 — Fix the template (RED first, `cq-write-failing-tests-before`)

1. Write the Phase-2 regression assertions first and watch them go **RED** against the unmodified template.
2. Apply the selected `mkfs` change in `apps/web-platform/infra/cloud-init-git-data.yml`, replacing the `#6982 W5/R31` comment block with one that states the measured mechanism (feature bit → `ext4_enable_quotas` → `find_quota_format` → `ESRCH`), the image fact with its fetch date, and what capability was preserved vs deferred.
3. **Independently of the mkfs change**, make the stage cause-carrying — it is the line that failed and the line that told us least. **[R8, R3-rev]** The design below is corrected from the first draft, which both reviewers showed would have *regressed* diagnosability on four of the stage's five failure modes:
   - **Seed a stage detail file at stage ENTRY, not at mount time.** `luks_err` is the trap for the *whole* `STAGE=luks_open` — the `GIT_DATA_LUKS_KEY` guard, `cryptsetup isLuks`, `luksFormat`, `luksOpen`, `mkfs.ext4` and `mount`. The first draft swapped the trap's detail source to a mount-specific stderr file; on any non-mount failure that file would not exist, and the emitter's `[ -r "$DETAIL_SRC" ]` branch (`cloud-init-git-data.yml:154-158`) would fall through to `_san "$DETAIL_SRC"` — shipping **the literal path string** as the diagnostic. A `luksFormat` failure would emit a filename. Seeding the file unconditionally at stage entry makes the trap's source always readable, and every command in the stage appends to it (`2>>`).
   - **Ordering is load-bearing because the emitter double-tails.** `DETAIL=$(tail -n 20 "$DETAIL_SRC" | _devalue | _clean)` and `_clean` ends in `tail -c 180` — so the emitter keeps the **last 20 lines, then the last 180 bytes**. Appending `dmesg` *after* the mount stderr would push the mount error out of the window entirely. Write **dmesg first, the failing command's stderr last**, so the bytes that survive are the ones that name the failure.
   - A `|| true` on the **`dmesg` capture itself** is required and is explicitly carved out of the hard constraint: `luks_err` runs with `set -euo pipefail` still armed, so a failing or SIGPIPE'd `dmesg` would abort the handler *before* `git-data-emit` — killing the diagnostic this step exists to add. The hard constraint is about the **mount**, never about the diagnostic. Note also that `luks_err`'s existing `… "rc=$rc" || true` (`:479`) is load-bearing for the same reason and must stay.
   - Use a plain `2>>file` redirect, **not** `exec 2> >(tee …)`. The heredoc carries a rejected-design comment at exactly this spot (`:482-485`) explaining that a process substitution under `set -euo pipefail` can leave the script waiting on `tee` at exit — a boot that hangs instead of one that reports. Say so in the new comment so a reviewer does not stall there.
   - Keep the failure **fatal**. No `|| true` on the mount, no fallback mount of the raw device (see User-Brand Impact).
4. **[R3-rev]** The detail-budget question is a **Phase 0.6** measurement, not a Phase 1 judgement call — the first draft gated it on "Phase 0 shows the new detail file still truncates", which was unassignable because Phase 0 runs before Phase 1 creates the file. Phase 0.6 instead writes a *representative* detail file by hand (20 dmesg lines + a realistic mount stderr), runs it through the shipped `_clean`, and reports what survives. If the answer is "not the mount error", Phase 1 either reorders further or raises the cap **for the detail-file path only**, with the reason in the comment. The emitter's redaction ordering is load-bearing (`hr-write-boundary-sentinel-sweep-all-write-sites`) and must not be disturbed.
5. **[R9]** Respect the hard `user_data` budget. Measured at plan time: `git-data-userdata-budget.sh --json` → `{"raw":51755,"stored":22772,"cap":32768,"headroom":9996}`. Comments are stripped at render (ADR-152), so Phase 1.3's expanded comment block is free; the new capture code is not. Re-run the budget script after the edit and record the headroom — exceeding 32768 stored bytes is a ForceNew gate, not a warning.

### Phase 2 — Regression test that can fail on the unfixed template

The two written-up failure classes both apply here, so the design is stated before the code:

- *A green guard that asserts nothing* (`knowledge-base/project/learnings/2026-07-30-four-ways-a-green-guard-asserted-nothing-rung2-route.md`): a static grep for the new mkfs flags proves the string changed, not that the filesystem mounts.
- *A guard that cannot run on the failure path it guards* (`knowledge-base/project/learnings/2026-07-30-the-guard-i-wrote-for-the-failure-path-could-not-run-on-the-failure-path.md`): **measured at plan time (H4)** — a privileged-container runtime mount test passes on the unfixed template on any kernel that has `quota_v2`, i.e. on every plausible CI runner. It cannot go red for the real reason.

**Therefore the runtime arm asserts the property that made the boot fail, not the failure itself.** Extend `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (the rung-1 Docker harness #7117 added, which already renders the real template and runs it in `ubuntu:24.04`) with:

- **R1 — feature-set FINGERPRINT, asserted as equality against a measured-good baseline (kernel-independent; the arm that carries the guarantee).** Render the real template, extract the LUKS heredoc, run its `mkfs` line against a loop-backed LUKS mapper, then read `dumpe2fs -h` and assert the resulting superblock feature set **equals** a committed fingerprint fixture.

  **Equality, not absence-of-a-known-bad.** A denylist containing `quota` guards against *this* incident, not the class: the next flag that reintroduces a mount-time kernel-module dependence sails through it. The invariant worth pinning is "the birth filesystem's mount depends on no kernel module absent from the target image", and there is already a **measured** witness of that invariant in production — the feature set of the two sibling LUKS stores (`cloud-init-registry.yml:790`, `workspaces-cutover.sh:1042`) that mount successfully on the same image. Pin equality with that baseline, carrying the same provenance-URL + fetch-date discipline. Any divergence — in either direction — is then a deliberate decision that must update the fixture and say why, which is exactly the review conversation this defect needed and did not get.

  **The fail-on-unfixed demonstration is an in-test mutation, NOT `git show <merge-base>:…`.** The merge-base is a moving target: the run that merges this fix is the *last* run in which merge-base carries the unfixed template. Afterwards a merge-base-based negative control either fails forever (blocking CI) or gets deleted — and R1 silently loses the property this whole phase exists to establish. Instead, inject `-O quota` into the *rendered* template in-test and assert R1 rejects it, matching the harness's existing `assert_mutation` idiom. Evergreen, no dependence on git history, same guarantee.
  **R1 runs UNPRIVILEGED and needs neither a loop device nor LUKS. [R2-rev, R13]** Both reviewers caught that the first draft's "loop-backed LUKS mapper" bought the harness's most fragile capability for nothing: R1's assertion is `dumpe2fs -h` on a *created superblock*, and `mkfs.ext4` accepts a **regular file**. The existing harness runs plain `docker run --rm` with bind mounts only (`git-data-runcmd-rehearsal.test.sh:430, 497, 533, 594`) — no `--privileged`, no `--cap-add`, no `--device` — and its header declares that boundary architecturally (`:12-16`: rung 1 "does not exercise … `luksOpen` against a real volume"). Coupling the plan's headline kernel-independent arm to `losetup` + dm-crypt + `CAP_SYS_ADMIN` would have made it the least portable arm in the suite. `mkfs.ext4` on a file + `dumpe2fs -h` on that file needs none of it. Add `e2fsprogs` to the container step (absent from base `ubuntu:24.04`).

  **Extraction, not re-rendering. [R2-rev(P0-2), R3-rev]** R1 must *not* re-render the template through `git-data-userdata-budget.sh`: that script hardcodes `templatefile("${DIR}/cloud-init-git-data.yml", …)` with no template-path parameter (`:82`, `DIR` at `:29`), is itself a registered CI step (`infra-validation.yml:1098`), and is held byte-equal to `modules/git-data-userdata/main.tf` by `git-data-render-strip-parity.test.sh` — a producer with three consumers, unplanned. The `mkfs` line carries **no `${}` interpolation**, so R1 extracts it from the template bytes directly and executes it. The mutation control mutates that extracted line.

- **R2 — the mount actually happens. [R2-rev(P0)]** *Status: decide in Phase 0, do not assume.* The first draft claimed this arm is "green on both templates"; in the harness's actual unprivileged container `mount(2)` fails **EPERM on both**, so as written it is green on neither. Three dispositions, and Phase 0.7 picks one **explicitly** — "extend the existing harness" is not a decision here:
  1. **Drop R2.** Defensible: it was never the guard, and R1 + the fingerprint baseline already carry the guarantee.
  2. **Promote rung 1 to privileged.** This is an *architectural* change to the rung-1/rung-2 taxonomy, against a boundary the harness's own header declares — so it belongs in the Phase 4 ADR, not in a test commit.
  3. **Push R2 to rung 2**, where a real host mounts a real mapper — which is exactly what the rehearsal already does, making R2 redundant there.
  Whichever is chosen, write the reasoning into the test body so a future reader does not restore a mount test believing it covers something.
- **R3 — the failure is diagnosable. Re-scoped. [R4-rev]** The first draft asserted the emitted `detail` "names the mount error and carries `dmesg` context", and would have passed for the wrong reason on both templates: the shipped trap's detail source is `/var/log/cloud-init-output.log`, which **does not exist in the container** (the harness says so at `:328-330`), so pre-fix detail is empty by *container artifact* rather than by truncation — and `dmesg` in an unprivileged container fails EPERM or is blocked by `kernel.dmesg_restrict`. That is precisely the cited "guard that cannot run on the failure path it guards". Re-scope R3 to what the container **can** assert: that the stage detail file is written unconditionally at stage entry and is passed as the emitter's 4th argument (a path that is readable, not a literal), plus a dash-level assertion that the emitter takes its `[ -r … ]` file branch rather than the `_san` fallback. Move the "carries dmesg" claim to a stated limitation in the test body, mirroring R2's treatment.

Update `apps/web-platform/infra/git-data-luks.test.sh` **B16** rather than deleting it: B16 currently pins `-O quota,project` with three mutation arms — its first arm is literally `s/-O quota,project/-O project/`, i.e. the proposed fix encoded as the drift to catch — so inversion is unavoidable and deletion would leave the invariant unguarded. Re-aim it at the post-fix invariant, and **[R7]**:
1. **Raise the suite's minimum-assertion floor** with the arms that make it necessary. `git-data-luks.test.sh:1039` gates on `total -lt 101` and its own comment sets the doctrine: *"RAISED 95 → 101 WITH THE ARMS THAT MADE IT NECESSARY … The floor must move with the suite or it only ever guards the work that predates it."* Same for `git-data-runcmd-rehearsal.test.sh:675` (`-lt 19`) and `git-data-rung2-rehearsal.test.sh:1345` (`-lt 65`).
2. **Record the premise correction in the ADR, not just the decision change.** B16's comment asserts the choice is migration-forcing; Phase 0.2 measures whether that is even true for `quota`. If `tune2fs -O quota` works offline, B16's stated rationale was factually wrong — and that wrong premise is *why* the unmountable flags were pinned in the first place. The ADR's `## Decision` must say so.
3. **Name the authority between the two guards.** B16 (static, on the template) and R1 (runtime, on the created superblock) now cover one invariant at two layers. Mirror the canonical framing at `knowledge-base/engineering/architecture/principles-register.md:28` (AP-018): an authoritative runtime gate plus a subordinate static pre-filter that is explicitly **never coverage-bearing**. Without that, the next author deletes one believing the other covers it.

**No new suite is created**, so no `infra-validation.yml` registration is needed — `run-registered-suites.sh:139` auto-discovers `apps/web-platform/infra/**/*.test.sh` and checks each is referenced by the workflow. **[R11-rev]** That also means the "no orphan suite" AC is trivially satisfied and must not be counted as coverage.

### Phase 3 — Make the rehearsal report a cause, not just a verdict (bounded)

In `scripts/followthroughs/git-data-rung2-evidence-capture.sh`:

1. Add `JSONExtractString(raw,'detail') AS detail` (and `rc`) to `HOST_SQL`. The FAIL arm already prints matching rows; with `detail` selected, the artifact carries the cause. This is the single change that would have made #7204 self-diagnosing.
2. Correct the header's Sentry-capability claim to what is measured today (search **is** available via `SENTRY_ISSUE_RO_TOKEN`), citing `hr-verify-repo-capability-claim-before-assert`. Do **not** implement the Sentry read path — that is #7116's job; this only stops #7116 being planned against a false constraint.
3. Extend the mutation-armed assertions in `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` to pin that `HOST_SQL` selects `detail` (a FAIL artifact without a cause is the defect being fixed).

Explicitly **out of scope**: changing the three-state verdict contract, the anchor query, the poll bounds, or anything else #7116 owns.

### Phase 4 — ADR (provisional **ADR-158**)

The birth filesystem's feature set is a migration-forcing decision on the store that will hold every user's source code, and no ADR records it today — it lives in a code comment (`#6982 W5/R31`) pinned by a test. Per `wg-architecture-decision-is-a-plan-deliverable` this ADR is a deliverable of *this* plan, not a follow-up.

- **Decision:** the git-data birth filesystem is created with only features the target image's kernel can honour; project-quota enforcement is deferred to an explicit, separately-evidenced change that also provisions the kernel module and userspace tooling.
- **Alternatives Considered** must include, with the Phase-0 measurements: installing `linux-modules-extra` at boot; `mount -o noquota`; keeping `-O quota,project` and accepting a dark boot; `tune2fs -O quota` as the later-addition path (with the measured answer to whether it works).
- **Status:** `accepted` if Phase 0 confirms the selected candidate; `adopting` if any measurement is ambiguous.
- The ordinal is **provisional**: `/ship`'s ADR-Ordinal Collision Gate re-verifies the next free ordinal against `origin/main`. On renumber, sweep `grep -rn 'ADR-158' knowledge-base/project/{plans,specs}/feat-one-shot-git-data-luks-open-fatal/` in the same edit, including any AC that names the ordinal.

### Phase 5 — C4 correction

`model.c4:214` `gitDataStore` describes the rung-2 route as "deliberately **UNFIRED**". It has been fired four times and consumed three paid hosts. Correct that sentence and add the birth-blocking fact (the rehearsal's current failure class), keeping the rest of the description intact. Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the edit — a `view include` referencing an undefined element fails there, not at `tsc`.

**C4 completeness — enumeration checked (per the Phase 2.10 mandate), all three model files read:**
- *External human actors:* none new. The operator (`founder`) already has edges to `betterstack`; end users reach `gitDataStore` only via `claude`, already modelled (`model.c4:566`).
- *External systems / vendors:* Hetzner, Doppler, Sentry, Better Stack, GitHub — all present, all already edged to `gitDataStore` or its host (`model.c4:467, 539, 542`).
- *Containers / data stores touched:* `platform.infra.gitDataStore` only. Already declared and already in the `views.c4:35` include list.
- *Access relationships changed:* none. The change alters how the store's filesystem is created, not who reaches it.
- *Descriptions falsified by this change:* one — the "UNFIRED" sentence above. Corrected, not skipped.

### Phase 6 — Verification and hand-off

Run the full registered infra suite (`run-registered-suites.sh`) plus the three named suites individually. Then **stop**. Record in the PR body that the rehearsal has *not* been re-dispatched and that doing so is a separate operator decision costing a paid host, with the exact dispatch command for whoever makes it.

---

## Infrastructure (IaC)

### Terraform changes
None. No new resource, variable, provider or secret. The change is confined to `apps/web-platform/infra/cloud-init-git-data.yml` (a `templatefile` payload rendered by `modules/git-data-userdata`) and to test/script files. No `TF_VAR_*` is added, so `hr-tf-variable-no-operator-mint-default` does not engage.

### Apply path
**(a) cloud-init-only**, and this is the correct choice rather than a shortcut: the resource has not been provisioned. `hcloud_server.git_data` does not exist, so there is no running host to patch and no bootstrap script to write. The template change takes effect on the next fresh boot — which is exactly the rehearsal, and then the birth. Blast radius: **zero live hosts**. Expected downtime: none.

**Merging this PR DOES fire `apply-web-platform-infra.yml`.** An earlier draft of this plan asserted the opposite ("a `*.tf`-free change does not trigger the path-filtered auto-apply"); that was **wrong** and is recorded here rather than quietly corrected. The filter is `apps/web-platform/infra/**` — not `infra/*.tf` — with a single negation for `rung2-rehearsal/**` (`apply-web-platform-infra.yml:66-89`). Four of the six edited paths sit under that glob, so the workflow runs on merge. What makes that safe is the **apply's scope, not its trigger**:

- The per-PR apply is `-target`-scoped, and **`git-data.tf` + `git-data-luks.tf` + `network.tf` resources are `OPERATOR_APPLIED_EXCLUSIONS` (ADR-068)** — stated at `apply-web-platform-infra.yml:2335`, deliberately outside the per-PR set. Every `-target='hcloud_server.git_data'` / `hcloud_volume*.git_data*` occurrence in that file lives inside the `git-data-host-replace` (:2449-2453) or `git_data_host_create` (:4134-4136) **dispatch** jobs, never the merge job. So no git-data resource can be created by this merge — the transitive-`-target` hazard does not fire.
- The one git-data-named `-target` that *is* in the merge job is `terraform_data.git_data_probe_install` (:933), which is a **web-host** resource (`server.tf:733`) carrying `connection { type = "ssh" }` plus `provisioner "file"`/`remote-exec`. Its `triggers_replace` hashes exactly `web-git-data-probe.{sh,service,timer}` and the probe service token (`server.tf:737-743`). **None of those is in this plan's Files to Edit**, so it does not replace and its SSH provisioners do not fire.

**Network-outage gate (`hr-ssh-diagnosis-verify-firewall`, plan-skill §1.4): triggered and discharged.** The gate fires on a `terraform apply` reaching a resource with a `provisioner`/`connection` block, which the bullet above is. It is discharged by *scope*, not by hope: the resource's replace-trigger inputs are disjoint from this diff, verified by reading `triggers_replace` rather than inferring from the resource name. Should a future revision of this plan add any of those three files, this discharge is void and the L3→L7 checklist (firewall allow-list and egress IP **before** any sshd/fail2ban hypothesis) applies in full.

The birth job is `workflow_dispatch` + environment-gated regardless. **Net: nothing about this merge provisions, replaces, or SSHes into anything.**

### Distinctness / drift safeguards
The template's hash is bound into rung-2 evidence by `git_data_rung2_user_data_sha256`, so **editing the template invalidates any existing evidence file by construction** — which is the intended behaviour and the reason no stale-evidence carve-out is needed. There is no evidence file on `main` to invalidate. No `lifecycle.ignore_changes` is added or relied on. No secret value enters `terraform.tfstate` as a result of this change.

### Vendor-tier reality check
Not applicable — no vendor resource is created. The one cost consideration is that each `dry_run=false` rehearsal dispatch spends a real Hetzner host (`cpx22`, hourly-billed, destroyed by the workflow's `if: always()` teardown); this plan dispatches none.

---

## GDPR / Compliance Gate

The canonical `hr-gdpr-gate-on-regulated-data-surfaces` regex does not match (no schema, migration, auth flow, API route or `.sql` file). Trigger **(b)** does fire — the plan declares brand-survival threshold `single-user incident` — so `/soleur:gdpr-gate` is invoked against this plan document during `/work` Phase 0, advisory-only.

Framing for that invocation: the change does not alter what personal data is processed, stored, or transferred. It alters the technical measure (Art. 32) protecting a store that will hold user source code. The relevant compliance question is narrow and already tracked: the privacy policy's encryption-at-rest claim currently outruns the implementation (#6588), and this plan is a step on the path that closes that gap — not a new processing activity. No Article 30 entry is created or modified.

---

## Observability

```yaml
liveness_signal:
  what: stage:boot_complete from the git-data host, with the four bootstrap assertion tags
  cadence: once per boot (this is cattle-at-birth, not a recurring beat)
  alert_target: none new — the git_data_prd Better Stack heartbeat remains deliberately
                unarmed (#6548 owns that decision; #6982 D-HB examined and declined)
  configured_in: apps/web-platform/infra/cloud-init-git-data.yml (git-data-emit) and
                 scripts/followthroughs/git-data-rung2-evidence-capture.sh (the consumer)
error_reporting:
  destination: Sentry (unconditional, baked DSN — org jikigai-eu, project web-platform)
               plus Better Stack Logs source 2457081 for post-`doppler run` stages only
  fail_loud: yes — the LUKS heredoc keeps `set -euo pipefail` and its EXIT trap; this plan
             adds no `|| true` to the mount and removes none of the existing fatals
failure_modes:
  - mode: the birth filesystem cannot be mounted (the defect being fixed)
    detection: stage:luks_open level:fatal, emitted FROM INSIDE the doppler-run child on the
               affected host, now carrying the mount's own stderr AND `dmesg | tail -n 20`
    alert_route: rung-2 capture FAIL arm (exit 1) with the cause printed in the artifact
                 (Phase 3 adds `detail` to HOST_SQL); Sentry issue on the same event
  - mode: the mount succeeds but against the wrong device (encryption silently absent)
    detection: git-data-bootstrap.sh's LUKS re-assert + the boot_complete luks_mounted tag
    alert_route: rung-2 capture's `"…":"no"` FAIL arm; note in the test body that those
                 booleans are hardcoded literals today, so this arm is latent
  - mode: the emitted detail is truncated past usefulness (the near-miss on #7204)
    detection: Phase 2 arm R4 drives the EXTRACTED emitter with a synthetic detail file
               (dmesg-shaped lines then the real mount error) and asserts the captured
               detail still contains "No such process" after tail -n 20 | tail -c 180;
               its mutation arm reverses the ordering and asserts RED. R3 separately
               asserts the detail SOURCE is a readable file rather than a literal path.
    alert_route: CI (infra-validation.yml), pre-merge
  - mode: a future edit makes the mount non-fatal (fall-through to an unencrypted device)
    detection: Phase 2 arm B17 (p_mount_no_fallthrough) — a STANDING static guard with
               three mutation arms, not a one-shot diff grep
    alert_route: CI (infra-validation.yml), pre-merge
logs:
  where: Sentry events (tags stage/host_name/detail/rc) and Better Stack Logs source
         2457081, queryable by ClickHouse SQL via scripts/betterstack-query.sh
  retention: Better Stack ~72 h measured on 2026-08-03 (floor 2026-07-31 09:46:21 UTC);
             Sentry retains longer — the 2026-07-30 events are still queryable. Any
             post-fix rehearsal must be captured within the Better Stack window or read
             from Sentry.
discoverability_test:
  command: |
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "
      SELECT dt, raw FROM (SELECT dt, raw FROM remote(\$BS_TABLE)
        UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
      WHERE dt > now() - INTERVAL 30 DAY
        AND JSONExtractString(raw,'host_name') LIKE 'soleur-git-data%'
      ORDER BY dt DESC LIMIT 50 FORMAT JSONEachRow"
  expected_output: for a healthy boot, one stage:boot_complete row for the host; for a
                   failed boot, a level:fatal row whose `detail` names the failing command.
                   This path never shells out over SSH.
```

**Affected-surface note (§2.9.2).** The git-data host is a blind execution surface by construction — deny-all firewall, no console, no log shipper, no SSH from CI. Every `detection` above is an **in-surface** probe: the event is emitted *from* the failing host, not inferred from a host-side gate. The `stage` tag is the discriminator, and Phase 1's change makes a single event carry enough to separate the competing hypotheses (which command, what errno, what the kernel said) rather than only that *something* failed — the exact gap that made #7204 cost a hand-written query to diagnose.

**Soak follow-through enrollment:** not applicable. No acceptance criterion here is time-gated; nothing closes on a post-deploy soak. The natural "did it work" signal is a rehearsal dispatch, which this plan deliberately does not perform.

---

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/cloud-init-git-data.yml` | The `mkfs.ext4` feature set in the `STAGE=luks_open` heredoc; the mount made cause-carrying (stderr file + `dmesg` tail into the emitted detail); the `#6982 W5/R31` comment replaced with the measured mechanism and the image fact + fetch date |
| `apps/web-platform/infra/git-data-luks.test.sh` | Re-aim **B16** at the post-fix invariant with mutation arms catching a re-introduction of the `quota` feature; rewrite its comment to cite #7204 |
| `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` | New arms **R1** (classified feature allowlist, extracted from the render, two negative controls), **R3** (the detail source is a readable file, not a literal path), **R4** (the mount error survives the emitter's double-truncation, + ordering-reversal mutation). **R2 only if Phase 0.7 selects it** — see D2. |
| `apps/web-platform/infra/git-data-luks.test.sh` (second entry) | New **B17** `p_mount_no_fallthrough` + three mutation arms — the standing guard for this plan's top invariant (D3) |
| `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` | Pin that `HOST_SQL` selects `detail` |
| `scripts/followthroughs/git-data-rung2-evidence-capture.sh` | Add `detail` (and `rc`) to `HOST_SQL`; correct the false Sentry-search capability claim in the header |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Correct the `gitDataStore` "deliberately UNFIRED" sentence (line ~214) |

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-158-*.md` | The birth-filesystem feature-set decision (ordinal provisional) |
| `apps/web-platform/infra/git-data-birth-fs-fingerprint.txt` | R1's expected superblock feature fingerprint, plus `source:`, `fetched:` and `expires_on:` provenance lines. **[R17]** The path is decided here, not deferred: `git-data-runcmd-rehearsal.test.sh` has **no** fixture files — every fixture is an inline heredoc (`:311-320, :337-368, :567-590`) — so there is no "existing fixture convention" to follow, and leaving it TBD would give AC7's `git grep` nothing to anchor on. A static synthesized text file is permitted under `cq-test-fixtures-synthesized-only` (no secrets, no captured production data). |

**Explicitly NOT edited, and why it matters:** `apps/web-platform/infra/git-data-userdata-budget.sh` is *not* in Files to Edit and must stay that way. R1 extracts the `mkfs` line from the template bytes rather than re-rendering, precisely so this producer — a registered CI step held byte-equal to `modules/git-data-userdata/main.tf` by `git-data-render-strip-parity.test.sh` — stays untouched. If a later revision needs a `--template <path>` parameter, that script **and** `git-data-render-strip-parity.test.sh` both join Files to Edit.

**Phase-order note. [R18]** The numbering reads 0→1→2 but the executable order is **Phase 0 → Phase 2's assertions (RED) → Phase 1's fix (GREEN) → Phase 2's remainder**. Phase 1's own first step says so, but a reader following the numbering writes the fix before the failing test, violating `cq-write-failing-tests-before`. `tasks.md` sequences the real order.

**Glob/path verification.** Every path above was confirmed present with `ls`/`git grep` at plan time except the two Files-to-Create entries. `apps/web-platform/infra/git-data-rung2-boot-evidence.env` is confirmed **absent** on `origin/main` via `git cat-file -e` — that absence is a premise of the blocker chain, not an oversight.

---

## Acceptance Criteria

### Pre-merge (PR)

1. **[R8-rev]** The superblock created by the post-fix template **equals** the fingerprint fixture, and the fixture's own provenance is asserted fresh: it carries a source URL, a fetch date and an `expires_on`, and R1 fails if `expires_on` has passed. (The first draft asserted only "no feature on the denylist", which is green whenever a hand-curated one-entry fixture says so — fail-open against any *future* module-dependent feature, and silently ageing while A1 stays open.)
2. **R1 goes RED on a mutated-in-test rendering and GREEN on the shipped one, in the same run.** The RED control is produced by injecting `-O quota` into the extracted `mkfs` line in-test (the harness's existing `assert_mutation` idiom) — **not** by `git show <merge-base>:…`. **[advisor, R3-rev, R2-rev]** A merge-base control is pre-fix only while this branch is open: once merged, every later branch's merge-base carries the *fixed* template and the arm either goes permanently red or gets deleted, taking the plan's headline guarantee with it. It is also unrunnable in a shallow clone. A run in which R1 is green on both the shipped and mutated forms is a **failing** AC, not a passing one.
3. **[R4-rev]** R3 goes RED on the pre-fix template and GREEN on the post-fix one, asserting **what the container can actually observe**: the stage detail file is written unconditionally at stage entry, is passed as the emitter's 4th argument, is readable (so the emitter takes its `[ -r … ]` branch and not the `_san "$DETAIL_SRC"` literal-string fallback). The "carries `dmesg`" property is a documented limitation in the test body, not an assertion — `dmesg` is EPERM-blocked in the harness's unprivileged container.
3b. **[R8-rev]** No non-mount failure in `STAGE=luks_open` emits a detail consisting of a bare path string. Asserted by driving the emitter with an absent `DETAIL_SRC` and confirming the post-fix stage cannot produce that state.
4. B16 in `git-data-luks.test.sh` holds against the post-fix template **and** each of its mutation arms goes RED, including a new arm that re-introduces the `quota` feature. Its rewritten comment names R1 as the authoritative gate and itself as a non-coverage-bearing static pre-filter (AP-018 framing).
4b. **[R7, R11]** All three suite minimum-assertion floors are raised with the arms that made them necessary: `git-data-luks.test.sh:1039` (`-lt 101`), `git-data-runcmd-rehearsal.test.sh:675` (`-lt 19`), `git-data-rung2-rehearsal.test.sh:1345` (`-lt 65`).
5. `HOST_SQL` in `scripts/followthroughs/git-data-rung2-evidence-capture.sh` selects `detail`; the corresponding pin in `git-data-rung2-rehearsal.test.sh` holds and its mutation arm goes RED. **[R16]** If `rc` is also selected, it is pinned by the same arm — a column with no consumer is dropped rather than added.
5b. **[R9]** `bash apps/web-platform/infra/git-data-userdata-budget.sh --json` reports `stored` ≤ 32768 with the headroom recorded in the PR body (plan-time baseline: `stored=22772`, `headroom=9996`).
6. `bash apps/web-platform/infra/run-registered-suites.sh` is green, run by its **own** invocation — not a hand-enumerated reconstruction of its input set (`knowledge-base/project/learnings/2026-07-28-my-ac-verified-four-paths-while-ci-verified-five.md`). Record the suite count it reports. **This AC is not sufficient on its own and must not be reported as if it were:** the runner executes each suite as `bash "{}" >/dev/null 2>&1` and prints `PASS`, so on a machine without a reachable docker daemon `git-data-runcmd-rehearsal.test.sh` self-skips with exit 0 and reports **PASS while asserting nothing** — which is precisely the suite carrying R1/R2/R3. The runner's own header documents this. Therefore AC6 must be satisfied **either** in CI (where `CI=true` converts the skip into a failure) **or** on a machine with a reachable docker daemon, and the run record must state which.
7. No new orphan suite: every new arm lives in one of the three named registered suites, confirmed by `git grep -ln '<new-arm-id>' apps/web-platform/infra/ tests/`. Note the suite list is **derived from `.github/workflows/infra-validation.yml`**, not globbed off the directory — extending an already-registered suite needs no workflow edit, but any new suite file would (and this plan creates none).
7b. `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` is run **directly** (not through the parallel runner) on a docker-bearing machine, and its output shows R1/R2/R3 actually executing — not skipping. Paste the arm-by-arm result lines into the PR body.
8. `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass after the `model.c4` edit.
9. `ADR-158` (or its collision-resolved ordinal) exists, its `## Decision` names the selected candidate, and its `## Alternatives Considered` carries the Phase-0 measurement for each of the four candidates — including the measured answer for `mount -o noquota` and for `tune2fs -O quota` as a later-addition path.
10. The PR body uses **`Ref #7204`**, not `Closes #7204` — the issue closes when a rehearsal actually passes against the corrected template, which is a separate operator dispatch. (`wg-use-closes-n-in-pr-body-not-title-to`, ops-remediation carve-out.)
11. **Merge-apply scope is unchanged.** Zero diff under `apps/web-platform/infra/*.tf` (`git diff --name-only origin/main... | grep -c '\.tf$'` returns 0) **and** zero new `TF_VAR_*` **and** the diff touches none of `web-git-data-probe.sh`, `web-git-data-probe.service`, `web-git-data-probe.timer` (`git diff --name-only origin/main... | grep -c 'web-git-data-probe'` returns 0 — the inputs to `terraform_data.git_data_probe_install`'s `triggers_replace`, whose replacement would fire an SSH provisioner during the merge apply). Note the merge **does** run `apply-web-platform-infra.yml`; this AC asserts the apply is a no-op for scope reasons, not that it does not run.
12. **[R9-rev]** No construct anywhere in the diff permits the boot to proceed with an unencrypted or wrong device mounted. Mechanically: `mount /dev/mapper/git-data` is not followed by `|| true`, `|| mount`, `|| :` or any `if`-guard that continues on failure, and no `mount` of a `/dev/disk/by-id/…` path is added inside the LUKS heredoc. The first draft's blanket "no `|| true` anywhere" was **unfalsifiable and self-contradictory**: `luks_err` already ends in `… "rc=$rc" || true` (`:479`, load-bearing — an emitter that aborts loses its event), and Phase 1.3's `dmesg` capture *requires* one under the armed `set -euo pipefail`. Both are explicitly carved out; the mount is not.
13. Every `knowledge-base/` path cited in this plan resolves, excluding the one path the plan explicitly documents as absent (the branch's `spec.md`, named in the frontmatter note): `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | grep -v 'specs/feat-one-shot-git-data-luks-open-fatal/spec\.md' | sort -u | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'` prints nothing. **Verified at plan time:** the only hit was that documented absence.

### Post-merge (operator)

13b. **[R15]** AC11's greps are written so that a zero count does not itself fail under `set -e`: `grep -c` exits **1** when the count is 0, i.e. the command proving the AC fails exactly when the AC holds. Use `! git diff --name-only origin/main... | grep -qE '\.tf$'` (and the same shape for `web-git-data-probe`).
13c. **[R1-blocker]** The PR body states plainly that **merging this PR runs `apply-web-platform-infra.yml`** (path filter `apps/web-platform/infra/**`), names why the apply is a no-op for scope reasons, and records whether the documented `[skip-web-platform-apply]` kill switch (workflow header `:51`) was used in the merge commit and why.

14. **Dispatch the rung-2 rehearsal with `dry_run=false`.** *Automation: not feasible — this is a deliberate spend decision (one paid Hetzner `cpx22` per dispatch) that the plan's own scope explicitly reserves to the operator, not a technical gate. The dispatch itself is a one-line `gh workflow run`; what is operator-owned is the decision to spend, which is a judgement call, not an interpretation of technical signal.* The PR body must carry the exact command and the expected PASS/FAIL/TRANSIENT semantics.
14b. **[R7-specflow] The FAIL and TRANSIENT branches must be written out, with a spend cap.** The first draft covered only PASS, handing the operator an unbounded, unpriced retry loop. Required in the PR body:
   - **PASS** → AC15.
   - **FAIL** (exit 1) → **stop.** Read the `detail` column (now selected, per Phase 3) for the cause and open a new issue. Do **not** re-dispatch on a FAIL; a second paid host cannot tell you more than the first.
   - **TRANSIENT** (exit 2, six distinct exits in the capture script: `:139, :143, :206, :225, :235, :287`) → **do not simply retry.** Per **#7116, which this plan lists as OPEN, the capture mis-reports TRANSIENT for exactly the early-boot fatals it could read from Sentry directly** — attempt 1 of run 30649892865 was that mis-report, one attempt before the real FAIL. A TRANSIENT verdict on a post-fix rehearsal must therefore be **confirmed against Sentry** (`host_name:soleur-git-data-rehearsal-<run-id>`, org `jikigai-eu`, project `web-platform`) before any re-dispatch. If Sentry shows a `level:fatal` row, treat the verdict as FAIL.
   - **Hard cap: at most two `dry_run=false` dispatches per fix attempt** (one initial, one only if Sentry independently confirms a genuine transient). Three have already been spent on failures.
15. On PASS, the capture writes `git-data-rung2-boot-evidence.env`. Merging that file is the second of the two intentional human gates. **[R14]** The *gate is the human review, not the typing*: `.github/workflows/git-data-rung2-rehearsal.yml:370-374` already prints the exact four-command merge sequence, so the operator is not being asked to compose anything. Automating the **commit** is deliberately declined because a route that writes its own gate-releasing evidence is self-approving (the capture script's own header states this); that is the justification `hr-never-label-any-step-as-manual-without` requires, and it is a judgement gate rather than an un-automatable one.
16. Only then does `git_data_host_create` become dispatchable. Out of scope here.

---

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200`, then `jq --arg path … contains($path)` per file in Files to Edit (two-stage form — `gh --jq` does not forward `--arg`).

- **#7098** — *ci: audit the 56 `run:` bodies whose `set` omits -e against GitHub's inherited `bash -e`, then shape the lint* — matches `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`. **Disposition: acknowledge.** Different concern (a repo-wide CI `set -e` audit and its lint shape); folding it in would expand this PR from a boot-fatal fix into a 56-site workflow audit, and the two changes touch different regions of the file. #7098 stays open and is not re-filed by this PR's review.
- All other Files-to-Edit paths: no matches.

---

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — mandated by the `single-user incident` threshold), Operations (COO — paid-host spend on the rehearsal route).

### Engineering (CTO)
**Status:** reviewed
**Assessment:** The diagnosis is closed to the level a plan can close it: the failing command, its errno, and a packaging fact that explains the errno, plus a fleet natural experiment where the two sibling LUKS mounts differ from this one on exactly the suspect axis and succeed. The residual risk is not the diagnosis but the **fix-shape**: the naive fix (drop the flags) discards a migration-forcing capability, and the naive test (mount it in a container) cannot fail on the unfixed template. Both are addressed structurally rather than by care — Phase 0 measures before Phase 1 chooses, and AC2 makes "R1 is green on both templates" a *failing* condition. Flagged for the reviewer: the `if ! cryptsetup isLuks "$DEV"` construct still swallows 126/127 exactly as the `sshd_config` stage's own comment warns against; it is **not** this defect (H3 refuted) and is deliberately left alone to keep the diff honest, but it is a real latent hole and belongs in a scope-out.

### Product (CPO)
**Status:** reviewed
**Assessment:** The user-visible stake is #6588 — the privacy policy claims encryption at rest for source code that is not yet encrypted at rest. This plan does not close that gap; it removes the one mechanical blocker on the route that can. The product risk to guard is the temptation to make the boot green: any fix that mounts something other than the LUKS mapper converts an *unstarted* promise into a *broken* one, which is materially worse. The plan's hard constraint (fail loud, never fall through) is the right shape and is encoded as AC12 rather than left as prose.

### Operations (COO)
**Status:** reviewed
**Assessment:** Each `dry_run=false` rehearsal spends a real `cpx22`. Three have been spent on failures already. The plan spends none, which is correct: dispatching before the fix lands would spend a fourth to learn nothing new. AC14 keeps the spend decision with the operator and gives them the command rather than a checklist. No recurring vendor expense is created (`wg-record-recurring-vendor-expense-before-ready` does not engage — the rehearsal host is hourly and self-destroying).

### Product/UX Gate
**Not applicable.** The mechanical UI-surface scan over `## Files to Create` and `## Files to Edit` finds no path matching the UI-surface term list or glob superset — the diff is a cloud-init template, four shell test suites, one shell script, one `.c4` model file and one ADR. Product is relevant to this plan (above) without the plan having a UI surface, so the gate resolves to **NONE** by the mechanical rule, not by subjective judgement.

---

## Research Insights — institutional learnings that bind this plan

Swept from `knowledge-base/project/learnings/` during deepen-plan. Listed only where they change a phase; the four learnings already cited in the body are not repeated.

**1. An existence assertion placed before the thing exists bricks every boot — and a co-presence grep cannot see it.**
`knowledge-base/project/learnings/2026-07-26-an-existence-assertion-that-ran-before-the-file-existed-bricked-every-boot.md` — a PR fixing boot diagnostics nearly shipped `test -x` assertions ~120 lines *above* the heredocs that create the files they assert on. *"Co-presence is not ordering."* The self-authored mutation battery could not catch it because the suite `awk`-extracts heredoc **bodies** and runs those in isolation, making "created too late" structurally invisible.
→ **Binds Phase 1.4 directly.** Seeding the detail file at stage entry is exactly this shape: a resource whose *position* relative to its consumers is load-bearing, in a file whose test harness extracts fragments rather than executing the stage in order. **Required:** the new comment must state the ordering as load-bearing, and the R3 arm must assert the seed **precedes** the first append — not merely that both lines exist. A grep proving both are present is the failure mode this learning names.

**2. A mutation battery measures the axes it varies, not the rows it contains.**
`knowledge-base/project/learnings/2026-07-30-a-known-gap-of-seven-was-a-predicate-and-my-battery-mutated-one-axis.md` — *"N mutations of one axis is one mutation."* Also the canonical source of the assertion-floor doctrine this plan already invokes.
→ **Binds Phase 2.** B16's three existing arms all mutate the **same axis** (the mkfs flag string). Before declaring Phase 2 done, enumerate the axes the combined battery varies and record them in the test body: (a) mkfs flag set, (b) resulting superblock features, (c) detail-file presence/ordering, (d) `HOST_SQL` column set. An axis with zero arms is the gap; a fourth arm on axis (a) is not coverage.

**3. The infra path-glob fires the apply — independently confirmed.**
`knowledge-base/project/learnings/best-practices/2026-07-11-cron-egress-sentinel-needs-runbook-row-and-infra-glob-fires-apply.md` — *"The delivery premise 'merging does not fire the apply because it is not a `.tf` file' is **false**."* Same trigger (`apps/web-platform/infra/**` at `:69-70`), same wrong premise, already written up.
→ **Confirms the R1 correction** in `## Infrastructure (IaC)`. This plan reached the finding independently by reading `on.push.paths`; that a prior session made the identical mistake is the argument for the Sharp Edge being stated rather than assumed. **Cite this learning in the IaC section at implementation time.**

**4. Renumber MINE, never main's — and key the sweep on the issue number.**
`knowledge-base/project/learnings/workflow-patterns/2026-07-05-adr-ordinal-collision-on-rebase-renumber-mine-not-mains.md` and `knowledge-base/project/learnings/2026-07-05-ghcr-installation-token-minter-dependency-gate-and-adr-ordinal-drift.md` — in shared files (`model.c4`, `principles-register.md`) main's ADR and yours coexist, so a blanket `s/ADR-158/ADR-159/g` corrupts main's references. The discriminator is the **issue number**.
→ **Binds Phase 4.4.** Replace the blanket sweep with the line-scoped form: `sed -i '/#7204/ s/ADR-158/ADR-<new>/g'` on shared files, plus the unscoped rename only within this feature's own artifacts (`plans/`, `specs/feat-one-shot-git-data-luks-open-fatal/`, the ADR body).

**5. `set -euo pipefail` upgrade pitfalls.**
`knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` — under `-u`, a bare `$2`/`$3` when unset aborts immediately; under `pipefail`, a `grep` with no match inside a command substitution propagates rc=1 and aborts the caller.
→ **Binds Phase 1.4.** Audit the new trap code for both: no bare positionals in `luks_err`, and no `$( … | grep … )` in the capture path that could abort the handler before `git-data-emit` runs. The `|| true` on `dmesg` is necessary but not sufficient.

**6. A `moved` block on an operator-excluded resource red-lines targeted CI applies.**
`knowledge-base/project/learnings/2026-07-02-moved-block-on-operator-excluded-resource-wedges-targeted-ci-apply.md` — the fix is the cutover **with** the migration, never an allow-list edit.
→ **Validates the current Apply-path analysis** (this plan adds no `moved` block and no `.tf` diff). Recorded as a forward constraint: if a future revision migrates git-data resources, the `moved` block ships with the operator cutover apply, not in a per-PR apply.

**7. C4 impact requires reading all three model files and enumerating external actors.**
`knowledge-base/project/learnings/2026-06-18-c4-impact-requires-reading-all-diagrams-and-enumerating-external-actors.md`.
→ **Already satisfied** — the Phase 5 enumeration covers actors, external systems, containers and access relationships, and reaches a *correction* rather than a "no impact" conclusion. No change needed; recorded so a reviewer can see the gate ran.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **A1 is false** — Hetzner's `ubuntu-24.04` is not the stock cloud image and does carry `linux-modules-extra`. Then H5's mechanism is wrong and the real cause is unfound. | The Phase-0 fix-selection rule requires a candidate that is correct **whether or not A1 holds** — one that does not depend on the image's module set at all. If the selected fix removes the dependency rather than satisfying it, A1's truth value stops mattering for correctness (it still matters for the ADR's rationale, which states it as an assumption). |
| The fix discards project-quota capability that a multi-tenant git store will later want, and re-adding it is migration-forcing. | Phase 0.2 measures whether `project` survives without `quota`, and whether `tune2fs -O quota` is a valid later-addition path. The ADR records the answer and the price. Note the capability is *currently unusable regardless*: the image ships no `quota` userspace tooling, and the template deliberately does not pass `prjquota` at mount — so the feature bits bought nothing and cost the whole boot. |
| The regression test passes for the wrong reason on a runner whose kernel differs. | R1 is kernel-independent by construction (it reads the created superblock's feature set, not the mount's outcome). R2's kernel-dependence is stated in the test body so a green run is not over-read. |
| Re-aiming B16 is read as "weakening a guard". | B16 keeps the same number of mutation arms and gains one; the diff shows a guard re-pointed, not removed. The ADR is the record of *why*, and `rf-when-a-reviewer-or-user-says-to-keep-a` applies if a reviewer wants the old assertion retained alongside. |
| Scope creep into #7116 via the capture-script edit. | Phase 3 is bounded to two lines of SQL, one comment correction and one pin. The three-state contract, the anchor query and the poll bounds are named as out of scope. |
| **The new arms need `--privileged` + loop devices, which the existing harness may not use.** `git-data-runcmd-rehearsal.test.sh` today runs three plain `docker run --rm` invocations; R1/R2/R3 need `losetup` and `cryptsetup`, i.e. `--privileged` (verified working at plan time on this machine, but not yet verified on the CI runner). | Phase 0.1's probe run is also the feasibility check: run it under the same shape the test will use. If `--privileged`/`losetup` is unavailable on the GitHub-hosted runner, R1 must fall back to a form that needs no loop device — `mkfs.ext4` on a plain **file** and `dumpe2fs` on that file both work unprivileged, and R1's assertion is about the created superblock, not about a block device. Note this fallback loses R2 (mount) entirely, which is acceptable precisely because R2 was never the guard. Decide this in Phase 0, not at implementation time. |
| **A green `run-registered-suites.sh` can be a false green for exactly these arms.** Docker-less machines self-skip with exit 0 and the parallel runner prints PASS. | AC6 is explicitly qualified and AC7b requires a direct, arm-by-arm run on a docker-bearing machine. |
| The emitter's 180-byte detail cap still swallows the cause after Phase 1. | Phase 1.3 routes the mount's own stderr into a dedicated detail file rather than relying on the shared log tail, so the 180 bytes are spent on the relevant text. Phase 1.4 makes a cap change conditional on measurement rather than assumed. |

---

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| `apt-get install -y linux-modules-extra-$(uname -r)` in `runcmd` to supply `quota_v2` | Adds a network-dependent, version-pinned boot failure mode on a console-less host to buy a capability that is unusable today anyway (no `quota` userspace tooling, no `prjquota` mount option). Violates the Phase-0 fix-selection rule (c). |
| `mount -o noquota` while keeping the feature bits | `ext4_enable_quotas()` is gated on the **feature bit**, not the mount options, and enables every type with a non-zero quota inode. Expected not to work — but Phase 0.2 probes it rather than asserting it, because a wrong answer here would change the fix. |
| Re-dispatch the rehearsal to gather more evidence before fixing | Spends a paid host to re-learn what two channels already agree on, and the scope explicitly forbids it. The cause was recoverable for free from retained telemetry. |
| Fix #7116's Sentry read path here so the capture reports the cause directly | Right idea, wrong PR. #7116 owns it, and this plan's Phase 3 removes the false capability claim that would otherwise make #7116 be planned against a constraint that does not exist. |
| Widen `_clean`'s `tail -c 180` globally | Touches the redaction/truncation ordering that `hr-write-boundary-sentinel-sweep-all-write-sites` and the emitter's measured 32 KB user_data budget both bear on. Deferred unless Phase 0 shows the targeted detail file still truncates. |

**Deferrals requiring tracking issues** (file during `/work`, per `wg-when-deferring-a-capability-create-a`):
1. The `if ! cryptsetup isLuks "$DEV"` 126/127-swallowing hole (the same class the `sshd_config` stage explicitly guards against, unfixed one stage later).
2. Project-quota enforcement for the git-data store, if Phase 0 shows the selected fix defers it — with the re-evaluation trigger and the measured price of re-adding it.
3. The emitter's 180-byte detail cap, if Phase 1.4 concludes it still bites.

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Fill it before requesting deepen-plan or `/work`.
- **The four assertion booleans in a rung-2 FAIL row are structurally empty and carry no information.** They are populated only on `boot_complete`. Reading them as "the host died before mount/repo-root/hooks/provision" is an over-read that this plan's own source brief made; the `stage` tag is the only positional fact in that row.
- **A privileged-container mount test cannot reproduce this class of defect.** Containers share the host kernel, so any kernel-module-dependent boot failure is invisible to them. Measured, four arms, at plan time (H4). Any future reviewer who proposes "just mount it in the test and see" should be shown that measurement.
- **`apply-web-platform-infra.yml` is path-filtered on `apps/web-platform/infra/**`, NOT on `*.tf`.** A `.tf`-free change to anything under that directory — a cloud-init template, a `.test.sh`, a systemd unit — still fires the production apply. This plan's first draft asserted the opposite and was wrong; the check that corrected it was reading `on.push.paths` (`:66-89`), not reasoning about file extensions. What makes such a merge safe is the `-target` scope plus the `OPERATOR_APPLIED_EXCLUSIONS` contract (`:2335`), which must be re-verified per PR — never inherited from a previous PR's conclusion.
- **A `-target` naming `git_data` is not necessarily a git-data resource.** `terraform_data.git_data_probe_install` is in the *merge* apply's target set and lives in `server.tf` on the **web** host, carrying SSH provisioners. Read the resource, not the name: the question that matters is what its `triggers_replace` hashes.
- **Editing the cloud-init template invalidates any rung-2 evidence file by construction** (the hash-of-hashes binds the template plus every `file()`-bound payload). That is intended. Do not attempt to preserve evidence across a template edit.

---

## Plan Review Revisions

Panel: `architecture-strategist`, `spec-flow-analyzer`, and a scoped strong-model advisor consult (ADR-083), escalated per the `single-user incident` threshold. All findings below are **mechanical/correctness** and were auto-applied; none were taste calls, and none reversed operator-stated direction (no User-Challenge to surface).

| # | Finding | Applied as |
|---|---|---|
| R1 | **The apply-path claim was false.** `apply-web-platform-infra.yml` filters on `apps/web-platform/infra/**`, not `*.tf` — merging this PR **does** fire a production apply. Caught by reading `on.push.paths:66-89` (self-caught during plan authoring, independently confirmed by architecture review). | `## Infrastructure (IaC) › Apply path` rewritten with the real filter and the real reason the apply is a no-op (`-target` scope + `OPERATOR_APPLIED_EXCLUSIONS`, `:2335`); AC11 re-scoped; AC13c added; two Sharp Edges added. |
| R2 | **R1/R2 were not implementable in the named harness.** It runs unprivileged `docker run --rm` with bind mounts only; R1's loop+LUKS apparatus needs `CAP_SYS_ADMIN`, and R2's `mount` fails EPERM on *both* templates. H4's laptop probe does not transfer to it. | R1 stripped to `mkfs.ext4` on a regular file + `dumpe2fs -h` (unprivileged); R2 demoted to an explicit Phase 0.7 disposition (drop / promote rung 1 / push to rung 2), with the taxonomy change routed to the ADR if "promote". |
| R3 | **AC2's `git show <merge-base>` control is non-durable and unimplementable** — it inverts the moment the PR merges, is vacuous in a shallow clone, and would require editing the byte-parity-guarded renderer. | Replaced with an in-test mutation of the extracted `mkfs` line, matching the harness's `assert_mutation` idiom. |
| R4 | **R3 could not run on the path it guards** — `/var/log/cloud-init-output.log` does not exist in the container (harness `:328-330`) and `dmesg` is EPERM-blocked, so pre-fix "empty detail" was a container artifact, not truncation. Same class as the learning the plan cites. | R3 re-scoped to what the container can observe (detail file written at stage entry, passed as arg 4, readable, emitter takes its file branch); the dmesg claim demoted to a documented limitation. |
| R5 | **Fix-selection criterion (c) was not dischargeable by the probe.** The container's kernel *has* `quota_v2`, so a green mount cannot distinguish "needs no module" from "module happened to be present". | Criterion (c) restated as a feature-bit argument discharged **by construction**, with mount rc demoted to sanity. The suggested container-side `modprobe.d` blacklist was **rejected on inspection**: `request_module` → `call_usermodehelper` runs in the init namespace, so a container's `modprobe.d` is never consulted — simulating this needs a VM. |
| R6 | **R1 was headed "allowlist" and bodied as a one-entry denylist** — fail-open against any future module-dependent feature, and its fixture had a fetch date but no expiry. | Converted to an equality fingerprint against the measured-good sibling baseline, with `expires_on` asserted by the arm itself (AC1). |
| R7 | **Two disjoint "four candidates" lists** made AC9 unsatisfiable against either. | One canonical five-candidate table in Phase 0, referenced by the ADR; "rejected a priori by rule (c)" is a valid disposition. |
| R8 | **The detail-source swap would have regressed four of five failure modes**: on a non-mount failure the emitter's `[ -r … ]` branch falls through to `_san "$DETAIL_SRC"` and ships the literal path string. And appending `dmesg` *after* the mount stderr pushes the mount error out of the emitter's `tail -n 20 | tail -c 180` window. | Detail file seeded at stage **entry**; ordering fixed (dmesg first, failing stderr last); AC3b added. |
| R9 | **AC12 was unfalsifiable and self-contradictory** — `luks_err` already ends in `|| true` (load-bearing), and the `dmesg` capture requires one under the armed `set -euo pipefail`. Also, the `user_data` 32 KB ForceNew cap appeared in no AC. | AC12 re-scoped to the property it means, with both carve-outs named; AC5b adds the budget gate (baseline `stored=22772`, `headroom=9996`). |
| R10 | **AC13 was simultaneously vacuous and guaranteed-red** — its regex matched only the one path the plan declares absent, while the four learnings the design rests on were cited bare and never checked. | All four learning citations given their `knowledge-base/project/learnings/` prefix (verified to resolve); AC13 excludes the documented absence. |
| R11 | **Three suite assertion-count floors** (`101`, `19`, `65`) would have gone stale, defeating the anti-vacuity guard for exactly the new arms. | AC4b added; the floors are named with their line anchors. |
| R12 | **AC6 was satisfiable with zero new arms executed** — the parallel runner prints PASS for a docker-skipping suite. | AC6 qualified (must be `CI=true` or a docker-bearing machine, and say which); AC7b requires a direct arm-by-arm run. |
| R13 | **The post-merge hand-off had no FAIL and no TRANSIENT branch**, and routed the operator straight into #7116's known TRANSIENT mis-report with no retry or spend cap. | AC14b written out: FAIL → stop; TRANSIENT → confirm against Sentry before re-dispatch; hard cap of two paid dispatches per fix attempt. |
| R14 | **AC15's "deliberately not automated" was thinner than `hr-never-label-any-step-as-manual-without` requires**, and ignored that the workflow already prints the merge commands (`:370-374`). | Restated: the gate is the human *review*, not the typing; the self-approval argument is the justification. |
| R15 | `grep -c` exits 1 on a zero count, so AC11's proof command fails precisely when the AC holds. | Rewritten as `! … | grep -qE …` (AC13b). |
| R16 | Phase 3 added an `rc` column with no consumer. | AC5 now requires it pinned or dropped. |
| R17 | The R1 fixture path was deferred to a "harness fixture convention" that does not exist (every fixture there is an inline heredoc). | Path decided: `apps/web-platform/infra/git-data-birth-fs-fingerprint.txt`. |
| R18 | Phase numbering inverts its own dependency (Phase 1 step 1 consumes Phase 2). | Phase-order note added; `tasks.md` sequences the executable order. |
| R19 | **B16 and R1 now cover one invariant at two layers with no stated authority** — the next author deletes one believing the other covers it. Also, the ADR should record the *premise correction* (was "migration-forcing" ever true for `quota`?), not only the decision. | Both folded into Phase 2's B16 block, mirroring AP-018 (`principles-register.md:28`): authoritative runtime gate + explicitly non-coverage-bearing static pre-filter. |
| R20 | **ADR-147 tension unaddressed** — it freezes diagnostic-capture logic in baked host-scripts, and Phase 1.3 adds capture logic to `user_data`. ADR-152 records why baking does not transfer to git-data. | The Phase 4 ADR must state the relationship (extends ADR-152's carve-out) rather than leaving a reader to reconcile them. Advisory from the same finding: consider an `advisory`-tier AP row for "a boot-time filesystem/feature choice must be honourable by the target image's kernel" — the class generalises beyond git-data. |

**Findings deliberately NOT applied:** none. Two were *corrected* rather than adopted verbatim — R5's container-blacklist mechanism (refuted on inspection, see above) and R3's committed-pre-fix-fixture form (the in-test mutation is equivalent and matches the harness idiom).

---

## Deepen-Plan Revisions (D1–D11)

From `test-design-reviewer` (Dave Farley 8-property evaluation; **Test Quality Score 7.25/10, grade C** — reasoning graded B/A, *specification* is what lands it at C). The reviewer ran its own measurements; two are load-bearing and reproduced here. All revisions below are mechanical and supersede the Phase 2 / Acceptance Criteria text above where they conflict.

**Measurement 1 — the equality fingerprint is measurably brittle.** Same `mkfs.ext4 -O project` on a 10G file:
- host, e2fsprogs **1.47.2** → `… metadata_csum_seed … orphan_file … project`
- `ubuntu:24.04`, e2fsprogs **1.47.0** → same set **minus** `orphan_file` and `metadata_csum_seed`

Two features differ across **one e2fsprogs patch version**, and `ubuntu:24.04` is a moving tag. Neither differing feature can trigger a `request_module`.

**Measurement 2 — `-O` accumulates** (`-O project -O quota` yields both), and a backing file under 3 MB falls into mke2fs's `floppy` bucket and silently drops `has_journal`. 100M/600M/10G are identical.

| # | Revision | Rationale |
|---|---|---|
| **D1** | **R1 asserts a CLASSIFIED ALLOWLIST, not set equality.** The fixture becomes one row per feature with a mount-time class (`in-tree` / `module-dep`), each `module-dep` row carrying its mechanism. R1 makes three assertions with three distinct messages: (a) every observed feature appears in the table — fail-closed against any *future* flag, which is what equality was bought for; (b) no observed feature is classified `module-dep` — the invariant, stated directly; (c) the observed set contains `has_journal` — a non-vacuity probe that also catches an accidentally-tiny backing file. | Equality reds on a benign e2fsprogs bump (Measurement 1), and the remedy an author reaches for is "refresh the fixture" — training exactly the rubber-stamping the plan says it wants to prevent. The allowlist reds with *"new feature `orphan_file` is unclassified — classify it before shipping"*, whose remedy is a one-line classification with a rationale. Still fail-closed. |
| **D2** | **`## Files to Edit` no longer mandates R2.** It is listed conditionally, resolved by Phase 0.7. | The table contradicted Phase 0.7's "decide, do not assume" — a reviewer would have read R2 as a required deliverable. |
| **D3** | **Add B17 `p_mount_no_fallthrough` to `git-data-luks.test.sh`**, with three mutation arms (one per fall-through shape). Predicate anchors on what follows the **mount** command — the shipped line is `mountpoint -q … || mount …`, so a naive "no `||` near mount" test is wrong in both directions. | This plan's highest-stakes invariant ("a *wrong* fix is worse than none") was enforced only by **AC12, a hand-run grep over one PR diff**. That protects this PR and nothing after it. The next author is the threat. |
| **D4** | **Promote Phase 0.6 from a measurement to arm R4**, with an ordering-reversal mutation: write a synthetic detail file (20 dmesg-shaped lines, then the real `No such process` mount error), drive the **extracted** emitter (`$TMP/git-data-emit`, already extracted at `:59-60`), assert the captured detail still contains `No such process`; reverse the ordering and assert RED. | R8 identified the `tail -n 20 \| tail -c 180` double-truncation hazard, the plan fixes it in prose, and **nothing pins it**. A one-character regression in the exact code path whose absence cost #7204 a hand-written query. Unprivileged, deterministic, no dmesg, no mount. The reviewer calls this the single most valuable available assertion. |
| **D5** | **R1 extracts from `$TMP/rendered.yml`, not raw template bytes**, with `assert len(...) == 1` in the same python block (matching `:67`, `:71`, `:80`). | Phase 1.3 mandates a new comment block that will contain the literal `mkfs.ext4 -q -O quota,project` — so a raw-bytes grep matches **two** lines and `head -1` may execute a comment. `cq-assert-anchor-not-bare-token` firing on the plan's own new comment. The harness already renders (`:52`) and already extracts stage blocks by `STAGE=` marker (`:79-81`); ADR-152 strips whole-line comments at render, so the collision disappears for free. R3's earlier "do not re-render" reasoning was about re-rendering a *mutated* template, which this does not require. |
| **D6** | **AC3b is rewritten.** Drive the extracted emitter with `$4=/nonexistent/xyzzy` and assert the captured detail does not contain `xyzzy`. | As worded ("absent `DETAIL_SRC`") it tests the wrong branch and **passes vacuously**: the emitter guards `[ -n "$DETAIL_SRC" ] && [ -r "$DETAIL_SRC" ]`, so an *empty* `$4` falls to `_san ""` (empty detail). The literal-path leak needs **non-empty but unreadable**. Bonus: the corrected form reds on the shipped code today (`luks_err` passes `/var/log/cloud-init-output.log`, unreadable in-container) and greens post-fix — a real RED/GREEN control replacing an argument-by-construction. |
| **D7** | **Add a second negative control**: a committed pre-fix literal `MKFS_PREFIX='mkfs.ext4 -q -O quota,project /dev/mapper/git-data'  # what shipped before #7204`, executed directly, alongside the in-test mutation. Plus a **mutation-landed** assertion before the mkfs runs. | The mutation is candidate-dependent: if Phase 0 picks candidate (c) plain `mkfs.ext4 -q`, there is no `-O` to inject and the sed silently changes meaning. AC2 still catches a no-op sed, but *misattributes* it ("fingerprint held on the mutant" instead of "the mutation did not land") — the exact misattribution class this suite's own S1 (`:638-645`) and T5 (`:492-494`) arms exist to prevent. |
| **D8** | **`expires_on` leaves R1's assertion path** into its own labelled arm with a named remediation tied to the birth, not an arbitrary +6 months. `mke2fs -V` is recorded in the fixture as **failure-message context**, not as an assertion. | A CI failure triggered by a wall-clock date is unrepeatable and its message says nothing about the filesystem; worse, a stale date can mask or merge with real feature drift. Supersedes AC1's `expires_on` clause. |
| **D9** | **R1's extraction-failure and fixture-missing paths emit identical cardinality**, mirroring S1's seven `fail`s at `:660-667`. | Otherwise a drifted extraction emits 1 assertion instead of 5, the *floor* reports "ran only N" and the real cause ("the mkfs line moved") is buried. Also: `mkfs.ext4` → `mke2fs -t ext4` would red B16 while R1 silently fails to extract. |
| **D10** | **Restate the AP-018 split with the docker-less caveat, and re-scope B16 to guard R1's *preconditions* rather than duplicate its semantics.** B16 owns: the `mkfs` invocation appears exactly once, is not on a comment line, and lies inside the `STAGE=luks_open` heredoc. R1 owns the feature semantics. Caveat to state: *R1 is authoritative **when it runs**; CI is the only environment where both run; B16 is the unconditional tripwire.* | AP-018 presumes the runtime gate always runs — here the suite `exit 0`s at `:41-44` without docker, so on a docker-less laptop **B16 is the only coverage that exists**. An author who reads "B16 is never coverage-bearing" and deletes it leaves local runs with zero coverage. Non-overlapping arms also remove the drift hazard. |
| **D11** | **Add a `HOST_SQL`-keys ⊆ emitter-payload-keys subset arm**, with a rename mutation. Also resolves AC5's open `rc` question: **keep it** — verified from the emitter's `--data-raw`, `rc` rides in `$TAGS` which is concatenated at top level, so `JSONExtractString(raw,'rc')` works. | A static grep for `detail` proves the column is *selected*, not that it is ever *populated*: rename the emitter's field and the SQL keeps selecting an always-empty column with the test still green. The subset arm also mechanically surfaces Research Reconciliation row #1 (`luks_mounted`/`repo_root`/`hooks_path`/`provision` are selected but emitted only on `boot_complete`), converting a Sharp Edge into an enumerated exception in the test body instead of folklore. |

**Also corrected:** AC3's name ("the failure is diagnosable") over-claimed what the arm asserts — rename to *"the detail source is a readable file, not a literal"* so a green run is not over-read. The `## Observability` block's `failure_modes` entry has been updated to describe R4 + R3 as revised, and now carries the B17 failure mode.

**Not applied:** nothing. Three reviewer suggestions were folded rather than adopted verbatim — the backing-file size (10G sparse, matching `git_data_luks_volume_size`) is folded into D1(c)'s non-vacuity probe; the "fold R1 into an existing container invocation" performance note is folded into D5 (extraction from the existing render makes it free); and the fixture-provenance loophole ("nothing forbids generating the fixture by running the post-fix template") is folded into D1 as an explicit requirement that the fixture derive from the **sibling baseline**, not from the post-fix output — otherwise R1 degrades from an invariant to a change-detector and the TDD claim becomes ceremonial.

---

## Phase 0 Measurement Record — executed 2026-08-03, before any fix line was written

Task 0.4 requires the fix-selection decision to be written here **before** Phase 1 starts. This
section is that record. Every number below was produced by a command run in this session; nothing
is carried over from plan-time prose.

### 0.1 — Four-arm LUKS probe (privileged `ubuntu:24.04`, host kernel `7.0.0-28-generic`)

Loop-backed file → `luksFormat --type luks2` → `luksOpen` → mkfs arm → `mount`.

| Arm | mkfs | Resulting features (tail) | `mount` rc |
|---|---|---|---|
| A | `-O quota,project` | `… extra_isize quota metadata_csum project` | **0** |
| B | `-O quota` | `… extra_isize quota metadata_csum` | **0** |
| C | `-O quota,project` + `mount -o prjquota` | `… quota metadata_csum project` | **0** |
| D | plain | `… extra_isize metadata_csum` | **0** |

**All four mounted.** H4 reproduced: on any kernel providing `quota_v2` the *unfixed* template
mounts fine, so a container mount test cannot go RED for the real reason. This is the measurement
that justifies R1 being a superblock assertion rather than a mount assertion, and it must not be
"simplified" back into a mount test later.

Incidental but load-bearing: inside the container `find /lib/modules/$(uname -r) -name 'quota_v2*'`
returned **NONE**, yet the arms still mounted — because `request_module()` →
`call_usermodehelper` runs in the **init namespace** and loaded the *host's* module. That is
direct evidence for R5's rejection of the `modprobe.d`-blacklist simulation: simulating this
condition needs a VM, not a container.

### 0.2 — Candidate measurement (10G sparse regular file)

| Candidate | Command | Features produced | Carries `quota`? |
|---|---|---|---|
| (a) | `mkfs.ext4 -q -O project` | `… extra_isize metadata_csum project` | **NO** |
| (c) | `mkfs.ext4 -q` | `… extra_isize metadata_csum` | NO |
| pre-fix | `mkfs.ext4 -q -O quota,project` | `… extra_isize quota metadata_csum project` | YES |

**mke2fs does NOT imply `quota` from `project`.** Candidate (a) yields the project-ID inode field
with no `quota` RO_COMPAT bit.

### 0.2.2 / 0.2.5 — `tune2fs` offline-addability: BOTH probe results were surprising, and both change the calculus

| Start state | Command | End state | Note |
|---|---|---|---|
| `-O project` fs | `tune2fs -O quota` | `… quota metadata_csum` — **`project` CLEARED** | rc=0 |
| plain fs | `tune2fs -O project` | `… quota metadata_csum project` — **`quota` ADDED** | rc=0 |
| plain fs | `tune2fs -O quota,project` | `… quota metadata_csum project` | rc=0 |

Re-measured in a second isolated probe with explicit before/after capture; both reproduced.

**Consequence, and it is the decisive one.** `tune2fs -O project` **implicitly sets `quota`**
(project quota depends on the quota feature). So "ship plain now, add `project` later via
`tune2fs`" is **not a safe path on this image** — it would set the exact RO_COMPAT bit that makes
the volume unmountable, converting a working store into a dark boot. The deepen-plan finding that
`tune2fs` makes these features "addable later" is true *mechanically* and misleading *operationally*:
`quota` is addable, `project` is not addable **without also adding `quota`**.

This inverts the (a)-vs-(c) comparison the plan left open. `project` must be set **at birth by
`mkfs`** (which does not pull in `quota`) or it cannot be had at all on this image.

### 0.2.4 — `mount -o noquota` (candidate (d))

`mount -o noquota` on a `-O quota,project` mapper returned **rc=0**, feature bit still present.

**This probe is NOT evidence that (d) works.** It ran on a kernel that *has* `quota_v2`, so it
cannot discriminate "the option escaped the enable path" from "the enable path ran and succeeded" —
the same blindness criterion (c) names. (d) is rejected on the feature-bit argument below, and this
rc=0 is recorded as **non-discriminating**, not as a pass.

### 0.2b — backing-file size (D-Measurement 2 reproduced)

`1M` → **no `has_journal`** (mke2fs `floppy` bucket); `100M` and `10G` → identical, `has_journal`
present. R1 uses a **10G sparse** file and asserts `has_journal` as its non-vacuity probe.

### 0.3 — Image fact, re-fetched 2026-08-03T10:39:33Z

`https://cloud-images.ubuntu.com/releases/24.04/release/…` **302-redirects** to `…/releases/noble/release/…`;
the first fetch without `-L` returned a 372-byte HTML redirect stub whose greps reported
`linux-modules-extra: 0`. **That zero was an artifact, not absence.** Re-fetched with `-L`:

- `HTTP=200`, 21233 bytes, **664 packages** (matches the plan-time count).
- Positive control: 13 `linux-*` rows present, incl. `linux-image-virtual`,
  `linux-image-6.8.0-136-generic`, `linux-modules-6.8.0-136-generic`.
- `linux-modules-extra` → **count=0** (now genuine absence — the positive control proves the grep works).
- `quota` userspace package → **count=0**.
- `e2fsprogs 1.47.0-2.4~exp1ubuntu4.1` — **exactly the version measured in `ubuntu:24.04`**, and
  one patch level below this host's 1.47.2, reproducing D-Measurement 1's feature-set delta.

### H5 / criterion (c) — discharged against kernel source, not against a mount rc

Read from `torvalds/linux` at tag **v6.8** (`fs/ext4/super.c`, fetched via the GitHub contents API):

- **`super.c:5567`** — `if (ext4_has_feature_quota(sb) && !sb_rdonly(sb)) err = ext4_enable_quotas(sb);`
  The call is gated on the **`quota`** feature bit **only**. `project` does not reach it.
- **`super.c:3645-3652`** — the only project-related mount refusal is wrapped in
  `#if !IS_ENABLED(CONFIG_QUOTA) || !IS_ENABLED(CONFIG_QFMT_V2)`.

From Ubuntu's own noble kernel-config annotations (fetched this session):
`CONFIG_QFMT_V2 policy<{'amd64': 'm', …}>`, `CONFIG_QUOTA policy<{'amd64': 'y', …}>`
(control row `CONFIG_EXT4_FS … 'y'` proves the grep resolves).

`IS_ENABLED()` is true for `=m`, so that refusal block is **compiled out** on the target kernel —
`project`-without-`quota` mounts. And because `CONFIG_QFMT_V2=m`, `quota_v2` must exist **on disk**,
which is precisely what `linux-modules-extra`'s absence denies. The chain
`quota` bit → `ext4_enable_quotas()` → `find_quota_format(QFMT_VFS_V1)` → NULL → `-ESRCH` → `mount(8)` rc=32
is now confirmed at every link. **A1 no longer gates correctness of the selected fix** (see below).

### 0.4 — FIX SELECTION: candidate (a), `mkfs.ext4 -q -O project`

| Criterion | Candidate (a) verdict |
|---|---|
| (a) mount does not depend on `quota_v2` | **MET** — measured: no `quota` bit; and `super.c:5567` gates the module load on that bit alone |
| (b) most future capability at zero present cost | **MET, and uniquely so** — `project` is obtainable ONLY at birth, because `tune2fs -O project` would implicitly add `quota` (0.2.5) |
| (c) correct whether or not A1 holds | **MET** — the fix removes the module dependency rather than satisfying it, so the image's module set is irrelevant to correctness |

**Full candidate disposition** (the canonical five-set; every candidate gets one):

- **(a) `-O project`, no `quota` — SELECTED.**
- **(b) `tune2fs` as a later-addition path — REJECTED as a fix, and recorded as an operational hazard.** Measured to mutate the feature set in both directions unsafely (0.2.2/0.2.5).
- **(c) plain `mkfs.ext4` (sibling parity) — REJECTED in favour of (a).** Safe and mountable, but given (b) it discards `project` *permanently*, not merely "for now". (a) is safe on the same axis at identical present cost.
- **(d) keep `quota,project` + `mount -o noquota` — REJECTED** on the feature-bit argument (`ext4_enable_quotas` is gated on the bit, not the options). The probe's rc=0 is non-discriminating and is not counted as evidence either way.
- **(e) keep `quota,project` + install `linux-modules-extra` at boot — REJECTED a priori by rule (c).**

**Capability actually preserved vs deferred, stated honestly:** (a) preserves the project-ID inode
field. It does **not** deliver project-quota *enforcement* — that additionally needs the `quota`
feature, the `quota` userspace package (absent from the image) and a `quotacheck` pass. Enforcement
is therefore **deferred**, and re-adding it is a genuine future cost, not a free `tune2fs`. Tracked
per Phase 6.5(b).

### 0.6 — Emitter detail budget, measured against the SHIPPED `_clean`

Extracted the emitter body from the template, de-escaped `$${`→`${`, sourced its real `_clean`/`_devalue`
(guards assert both `_clean()` and `tail -c 180` were extracted, else the measurement voids), and ran
`tail -n 20 <file> | _devalue | _clean`:

| Ordering | 180-byte survivor ends with | Mount error survives? |
|---|---|---|
| **dmesg first, mount stderr last** | `… mount(2) system call failed: No such process.` | **YES** |
| reversed (dmesg last) | `… no quota format module line 20` | **NO** |
| 5-line dmesg, stderr last | `… No such process.` | YES |

**Answer to Phase 1.5: reorder only — do NOT raise the cap.** The prescribed ordering already fits
the mount error inside 180 bytes, so the redaction/truncation ordering is left untouched.

Also measured: `_san('/var/log/cloud-init-output.log')` → `/var/log/cloud-init-output.log`. That is
the literal path string, and it is exactly what the shipped `luks_err` emits as its "detail" whenever
that file is unreadable. Confirms R8/D6 and gives R3/AC3b a real pre-fix RED.

### 0.7 — R2 disposition: **DROP**

Measured: `git-data-runcmd-rehearsal.test.sh` runs **four** plain `docker run --rm` invocations and
contains **zero** occurrences of `--privileged`/`--cap-add`/`--device`. A `mount(2)` arm fails EPERM
on *both* templates there, so it would be green on neither. Promoting rung 1 to privileged is an
architectural change against the boundary the harness header itself declares, and rung 2 already
mounts a real mapper on a real host. R1 plus the classified allowlist carries the guarantee. The
reasoning is written into the test body so a later reader does not restore a mount arm believing it
covers something.

### 0.8 — R1 feasibility confirmed unprivileged

`docker run --rm ubuntu:24.04` (no privilege flags): `truncate -s 10G` → `mkfs.ext4 -q -F -O project`
→ rc=0 → `dumpe2fs -h` reads the feature set. `e2fsprogs` must be apt-installed in the container step
(absent from base `ubuntu:24.04`).

### Sibling baseline for the R1 fixture (provenance)

Plain `mkfs.ext4 -q` under e2fsprogs 1.47.0 — the measured-good witness the two working production
LUKS stores create:

```
has_journal ext_attr resize_inode dir_index filetype extent 64bit flex_bg sparse_super large_file huge_file dir_nlink extra_isize metadata_csum
```

The fixture is derived from **this** baseline plus `project` classified explicitly — never from the
post-fix template's own output, which would make R1 a change-detector instead of an invariant.
