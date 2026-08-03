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

The `hr-ssh-diagnosis-verify-firewall` network-outage checklist does **not** fire: no SSH/handshake/timeout/unreachable symptom, and no `provisioner`/`connection` block exists in either Terraform root (`rehearsal.tf:167-172` states the cloud-init-only posture explicitly).

Verdicts below are stated against the discriminator that produced them. Nothing is marked CONFIRMED on reasoning alone.

| # | Hypothesis | Verdict | Discriminator actually run |
|---|---|---|---|
| H1 | `doppler run` failed / scratch config unreachable / `GIT_DATA_LUKS_KEY` absent (the `#6982 W0` class) | **REFUTED** | The fatal row reached **Better Stack**, whose emitter block is gated on `BETTERSTACK_LOGS_TOKEN` — present only under `doppler run`. Injection demonstrably worked. Both secrets are written by the same `depends_on`-ordered terraform. |
| H2 | The LUKS device path did not resolve (attachment race / stub id) | **REFUTED** | `mount(8)` reported `ESRCH` against `/dev/mapper/git-data`; a missing mapper produces `special device … does not exist`. The mapper existed ⇒ `luksFormat`+`luksOpen` ran and succeeded. |
| H3 | `cryptsetup` absent (the `127`-swallowed-by-`if !` shape the `sshd_config` stage guards against) | **REFUTED** | Same as H2 — the mapper exists, so `cryptsetup` ran. (The latent `if ! cryptsetup …` 126/127 hole is still real; see Risks.) |
| H4 | The `-O quota,project` filesystem is unmountable *in general* | **REFUTED** | Privileged-container probe, four arms (`-O quota,project`, `-O quota`, `-O quota,project` + `-o prjquota`, plain) over a real loop device + `luksFormat`/`luksOpen`, kernel `7.0.0-28-generic`: **all four mounted, rc=0**, `dmesg` showing `Quota mode: journalled`. The defect is kernel-dependent, not filesystem-dependent. **This is why a container-based runtime guard cannot fail on the unfixed template.** |
| H5 | The `quota` superblock feature forces `ext4_enable_quotas()` at mount; the target image has no `quota_v2` to load, so `find_quota_format` returns NULL and `dquot_load_quota_sb` returns `-ESRCH` | **CONFIRMED**, modulo A1 below | (a) Errno match: `mount(2)` = `ESRCH`, `mount(8)` rc=32 — both measured on the host. (b) Ubuntu `noble` Contents index: `fs/quota/quota_v2.ko.zst` is in `linux-modules-extra-*-generic` only; `ext4.ko` has no generic row (built in) as a working control for the grep. (c) `CONFIG_QFMT_V2=m` on the generic kernel. (d) **Ubuntu 24.04 server cloud image manifest** (`ubuntu-24.04-server-cloudimg-amd64.manifest`, 664 packages): `linux-image-virtual`, `linux-modules-6.8.0-136-generic` present; **`linux-modules-extra-*` ABSENT**; no `quota` userspace package either. (e) Fleet natural experiment: `cloud-init-registry.yml:790` and `workspaces-cutover.sh:1042` `mkfs` **without** quota features on the same image and mount successfully in production; git-data is the only one that sets them and the only one that fails at mount. |
| A1 | **Assumption, not yet discharged:** Hetzner's `ubuntu-24.04` image *is* the stock Ubuntu cloud image (or at least shares its `linux-modules-extra`-absent package set) | **OPEN** | Every observable is consistent with it, and no cheap probe closes it without either SSH (forbidden, `hr-no-ssh-fallback-in-runbooks`) or a paid host (forbidden by scope). **Phase 1 therefore requires a fix that is correct whether or not A1 holds** — see the Fix-selection rule. |

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

Phase ordering here is load-bearing (`2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`): the measurement decides between fixes that differ in migration cost, so it cannot be folded into the fix commit.

**0.1 — Reproduce the ESRCH determinism question, and record the answer honestly.**
Re-run the four-arm privileged-container probe (loop file → `luksFormat` → `luksOpen` → `mkfs` arm → `mount`) already run at plan time, and record in the commit message that **all arms pass on a kernel that provides `quota_v2`**. This is the evidence that the naïve runtime guard cannot fail on the unfixed template; the regression test in Phase 2 is designed around it and must not be reverted to the naïve form later.

**0.2 — Measure the candidate fix set in the same container.** For each candidate, record `dumpe2fs -h` features and `mount` rc:

| Candidate | Question the probe answers |
|---|---|
| `mkfs.ext4 -q -O project` (no `quota`) | Does mke2fs accept `project` without `quota`? Does the resulting superblock carry `quota`? (If it does **not**, `ext4_enable_quotas()` is never reached and the mount is quota-module-independent — the strongest candidate, because it preserves the genuinely migration-forcing half.) |
| `tune2fs -O quota <dev>` on a `project`-only fs | Is the `quota` feature addable **later**, offline, without recreating the volume? This is the fact that decides whether B16's "migration-forcing" framing applies to `quota` at all, or only to `project`. |
| `mkfs.ext4 -q` (plain) | The sibling-parity baseline (`cloud-init-registry.yml:790`). |
| `mkfs.ext4 -q -O quota,project` + `mount -o noquota` | Does the `noquota` mount option escape the feature-driven enable path? **Expected NO** — `ext4_enable_quotas()` is gated on the feature bit and enables every type with a non-zero quota inode regardless of mount options. Probe it rather than assume it; a wrong answer here would change the fix. |

**0.3 — Re-verify the image fact.** Re-fetch `https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.manifest` and pin the observed `linux-*` package set + fetch date into the fix's comment block, so a future reader can tell a stale claim from a measured one. Record that `linux-modules-extra-*` is absent and that `quota_v2.ko` lives only there.

**Fix-selection rule (must be written into the plan record before Phase 1 starts):** choose the candidate that (a) produces a filesystem whose mount does **not** depend on `quota_v2`, and (b) preserves the largest amount of future capability at zero present cost, and (c) is correct **whether or not A1 holds** — i.e. does not depend on the target image's module set at all. A candidate that installs `linux-modules-extra-$(uname -r)` at boot fails (c): it adds a new network-dependent boot failure mode on a console-less host to buy a capability that is *also* unusable today (the image ships no `quota` userspace tooling either, and the template deliberately does not pass `prjquota` at mount).

### Phase 1 — Fix the template (RED first, `cq-write-failing-tests-before`)

1. Write the Phase-2 regression assertions first and watch them go **RED** against the unmodified template.
2. Apply the selected `mkfs` change in `apps/web-platform/infra/cloud-init-git-data.yml`, replacing the `#6982 W5/R31` comment block with one that states the measured mechanism (feature bit → `ext4_enable_quotas` → `find_quota_format` → `ESRCH`), the image fact with its fetch date, and what capability was preserved vs deferred.
3. **Independently of the mkfs change**, make the mount cause-carrying — it is the line that failed and the line that told us least:
   - capture the mount's own stderr to a file and pass that file to `git-data-emit` as the detail source, instead of relying on the tail of `cloud-init-output.log` (which delivered 180 bytes beginning mid-sentence inside unrelated Doppler chatter);
   - append `dmesg | tail -n 20` to that detail file on failure — `mount(8)` explicitly points at it, and the host is destroyed minutes later;
   - keep the failure **fatal**. No `|| true`, no fallback mount of the raw device (see User-Brand Impact).
4. Do **not** widen `_clean`'s `tail -c 180` in this PR unless Phase 0 shows the new detail file still truncates below usefulness; the emitter's 32 KB user_data budget and its redaction ordering are load-bearing (`hr-write-boundary-sentinel-sweep-all-write-sites`), and a byte-cap change deserves its own measured argument. If it is needed, raise the cap for the *detail file* path only and say why in the comment.

### Phase 2 — Regression test that can fail on the unfixed template

The two written-up failure classes both apply here, so the design is stated before the code:

- *A green guard that asserts nothing* (`2026-07-30-four-ways-a-green-guard-asserted-nothing-rung2-route.md`): a static grep for the new mkfs flags proves the string changed, not that the filesystem mounts.
- *A guard that cannot run on the failure path it guards* (`2026-07-30-the-guard-i-wrote-for-the-failure-path-could-not-run-on-the-failure-path.md`): **measured at plan time (H4)** — a privileged-container runtime mount test passes on the unfixed template on any kernel that has `quota_v2`, i.e. on every plausible CI runner. It cannot go red for the real reason.

**Therefore the runtime arm asserts the property that made the boot fail, not the failure itself.** Extend `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (the rung-1 Docker harness #7117 added, which already renders the real template and runs it in `ubuntu:24.04`) with:

- **R1 — feature-set allowlist (kernel-independent, fails RED on the unfixed template).** Render the real template, extract the LUKS heredoc, run its `mkfs` line against a loop-backed LUKS mapper, then read `dumpe2fs -h` and assert the resulting superblock feature set contains **no feature requiring a kernel module absent from the target image**. The denylist is a committed fixture derived from the Phase-0.3 manifest + Contents facts (today: `quota`), each entry carrying its provenance URL and fetch date. On the unfixed template `dumpe2fs` reports `quota` → RED. On the fixed template → GREEN. **This is the arm that demonstrates fail-on-unfixed**, and the demonstration is mechanical: re-run the arm against the pre-fix template bytes (`git show <base>:apps/web-platform/infra/cloud-init-git-data.yml`), assert exit non-zero, in the same test.
- **R2 — the mount actually happens.** After R1's mkfs, mount the mapper and assert `mountpoint -q` succeeds. This arm is green on both templates on a `quota_v2`-bearing runner and is *not* claimed as the regression guard — it is the sanity arm that stops R1's allowlist from being satisfied by a filesystem nobody can mount. Its limitation is written into the test body so a future reader does not over-read a green run.
- **R3 — the failure is diagnosable.** Force a mount failure deterministically (point the mount at a device carrying a deliberately corrupt superblock) and assert the emitted event's `detail` names the mount error **and** carries `dmesg` context. This arm goes RED on the unfixed template, whose detail is the 180-byte tail of an unrelated log.

Update `apps/web-platform/infra/git-data-luks.test.sh` **B16** rather than deleting it: B16 currently pins `-O quota,project` with three mutation arms and exists to stop an uninformed drop. Re-aim it at the *post-fix* invariant with mutation arms that would catch a re-introduction of `quota`, and rewrite its comment to cite this issue and the measured mechanism. Deleting it would leave the migration-forcing choice unguarded; leaving it as-is would make the fix un-landable.

Register per `apps/web-platform/infra/run-registered-suites.sh` conventions — no new orphan suite. Extend the three named suites; do not create a fourth.

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
    detection: Phase 2 arm R3 asserts the emitted detail names the mount error and carries
               dmesg context; it goes RED on the unfixed template
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
                   No ssh anywhere in this path.
```

**Affected-surface note (§2.9.2).** The git-data host is a blind execution surface by construction — deny-all firewall, no console, no log shipper, no SSH from CI. Every `detection` above is an **in-surface** probe: the event is emitted *from* the failing host, not inferred from a host-side gate. The `stage` tag is the discriminator, and Phase 1's change makes a single event carry enough to separate the competing hypotheses (which command, what errno, what the kernel said) rather than only that *something* failed — the exact gap that made #7204 cost a hand-written query to diagnose.

**Soak follow-through enrollment:** not applicable. No acceptance criterion here is time-gated; nothing closes on a post-deploy soak. The natural "did it work" signal is a rehearsal dispatch, which this plan deliberately does not perform.

---

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/cloud-init-git-data.yml` | The `mkfs.ext4` feature set in the `STAGE=luks_open` heredoc; the mount made cause-carrying (stderr file + `dmesg` tail into the emitted detail); the `#6982 W5/R31` comment replaced with the measured mechanism and the image fact + fetch date |
| `apps/web-platform/infra/git-data-luks.test.sh` | Re-aim **B16** at the post-fix invariant with mutation arms catching a re-introduction of the `quota` feature; rewrite its comment to cite #7204 |
| `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` | New arms **R1** (feature-set allowlist + explicit fail-on-pre-fix-bytes demonstration), **R2** (mount sanity, with its limitation written into the body), **R3** (the fatal names the cause) |
| `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` | Pin that `HOST_SQL` selects `detail` |
| `scripts/followthroughs/git-data-rung2-evidence-capture.sh` | Add `detail` (and `rc`) to `HOST_SQL`; correct the false Sentry-search capability claim in the header |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Correct the `gitDataStore` "deliberately UNFIRED" sentence (line ~214) |

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-158-*.md` | The birth-filesystem feature-set decision (ordinal provisional) |
| a committed fixture for R1's denylist (location to follow the harness's existing fixture convention) | The "features the target image's kernel cannot honour" list, each entry carrying its provenance URL and fetch date |

**Glob/path verification.** Every path above was confirmed present with `ls`/`git grep` at plan time except the two Files-to-Create entries. `apps/web-platform/infra/git-data-rung2-boot-evidence.env` is confirmed **absent** on `origin/main` via `git cat-file -e` — that absence is a premise of the blocker chain, not an oversight.

---

## Acceptance Criteria

### Pre-merge (PR)

1. `apps/web-platform/infra/cloud-init-git-data.yml` no longer creates a birth filesystem carrying any superblock feature on the R1 denylist. Verified by R1, not by grep alone.
2. **R1 goes RED against the pre-fix template bytes and GREEN against the post-fix ones, in the same test run** (`git show <merge-base>:apps/web-platform/infra/cloud-init-git-data.yml` as the RED fixture). This is the AC that discharges "the regression test must be able to fail on the unfixed template"; a run in which R1 is green on both is a **failing** AC, not a passing one.
3. R3 goes RED on the pre-fix template and GREEN on the post-fix one: the emitted fatal's `detail` names the failing mount command and carries `dmesg` context.
4. B16 in `git-data-luks.test.sh` holds against the post-fix template **and** each of its mutation arms goes RED, including a new arm that re-introduces the `quota` feature.
5. `HOST_SQL` in `scripts/followthroughs/git-data-rung2-evidence-capture.sh` selects `detail`; the corresponding pin in `git-data-rung2-rehearsal.test.sh` holds and its mutation arm goes RED.
6. `bash apps/web-platform/infra/run-registered-suites.sh` is green, run by its **own** invocation — not a hand-enumerated reconstruction of its input set (`2026-07-28-my-ac-verified-four-paths-while-ci-verified-five.md`). Record the suite count it reports.
7. No new orphan suite: every new arm lives in one of the three named registered suites, confirmed by `git grep -ln '<new-arm-id>' apps/web-platform/infra/ tests/`.
8. `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass after the `model.c4` edit.
9. `ADR-158` (or its collision-resolved ordinal) exists, its `## Decision` names the selected candidate, and its `## Alternatives Considered` carries the Phase-0 measurement for each of the four candidates — including the measured answer for `mount -o noquota` and for `tune2fs -O quota` as a later-addition path.
10. The PR body uses **`Ref #7204`**, not `Closes #7204` — the issue closes when a rehearsal actually passes against the corrected template, which is a separate operator dispatch. (`wg-use-closes-n-in-pr-body-not-title-to`, ops-remediation carve-out.)
11. **Merge-apply scope is unchanged.** Zero diff under `apps/web-platform/infra/*.tf` (`git diff --name-only origin/main... | grep -c '\.tf$'` returns 0) **and** zero new `TF_VAR_*` **and** the diff touches none of `web-git-data-probe.sh`, `web-git-data-probe.service`, `web-git-data-probe.timer` (`git diff --name-only origin/main... | grep -c 'web-git-data-probe'` returns 0 — the inputs to `terraform_data.git_data_probe_install`'s `triggers_replace`, whose replacement would fire an SSH provisioner during the merge apply). Note the merge **does** run `apply-web-platform-infra.yml`; this AC asserts the apply is a no-op for scope reasons, not that it does not run.
12. No `|| true`, no fallback mount, and no reduction in what is encrypted anywhere in the diff — confirmed by reading the full LUKS heredoc diff, not by grep (the User-Brand Impact hard constraint).
13. Every `knowledge-base/` path cited in this plan resolves, excluding the one path the plan explicitly documents as absent (the branch's `spec.md`, named in the frontmatter note): `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | grep -v 'specs/feat-one-shot-git-data-luks-open-fatal/spec\.md' | sort -u | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'` prints nothing. **Verified at plan time:** the only hit was that documented absence.

### Post-merge (operator)

14. **Dispatch the rung-2 rehearsal with `dry_run=false`.** *Automation: not feasible — this is a deliberate spend decision (one paid Hetzner `cpx22` per dispatch) that the plan's own scope explicitly reserves to the operator, not a technical gate. The dispatch itself is a one-line `gh workflow run`; what is operator-owned is the decision to spend, which is a judgement call, not an interpretation of technical signal.* The PR body must carry the exact command and the expected PASS/FAIL/TRANSIENT semantics.
15. On PASS, the capture writes `git-data-rung2-boot-evidence.env`. Merging that file is the second of the two intentional human gates and is deliberately not automated.
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

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **A1 is false** — Hetzner's `ubuntu-24.04` is not the stock cloud image and does carry `linux-modules-extra`. Then H5's mechanism is wrong and the real cause is unfound. | The Phase-0 fix-selection rule requires a candidate that is correct **whether or not A1 holds** — one that does not depend on the image's module set at all. If the selected fix removes the dependency rather than satisfying it, A1's truth value stops mattering for correctness (it still matters for the ADR's rationale, which states it as an assumption). |
| The fix discards project-quota capability that a multi-tenant git store will later want, and re-adding it is migration-forcing. | Phase 0.2 measures whether `project` survives without `quota`, and whether `tune2fs -O quota` is a valid later-addition path. The ADR records the answer and the price. Note the capability is *currently unusable regardless*: the image ships no `quota` userspace tooling, and the template deliberately does not pass `prjquota` at mount — so the feature bits bought nothing and cost the whole boot. |
| The regression test passes for the wrong reason on a runner whose kernel differs. | R1 is kernel-independent by construction (it reads the created superblock's feature set, not the mount's outcome). R2's kernel-dependence is stated in the test body so a green run is not over-read. |
| Re-aiming B16 is read as "weakening a guard". | B16 keeps the same number of mutation arms and gains one; the diff shows a guard re-pointed, not removed. The ADR is the record of *why*, and `rf-when-a-reviewer-or-user-says-to-keep-a` applies if a reviewer wants the old assertion retained alongside. |
| Scope creep into #7116 via the capture-script edit. | Phase 3 is bounded to two lines of SQL, one comment correction and one pin. The three-state contract, the anchor query and the poll bounds are named as out of scope. |
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
