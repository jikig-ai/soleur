---
date: 2026-07-03
type: infra
title: "Stop the Concierge agent-sandbox substrate from materializing .git/config.lock as a character device (durable root-cause fix)"
closes: 5934
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-one-shot-5934-concierge-config-lock-chardevice
lineage: "companion tracker #5912; repo-side PR #5932 (WIP); instrument PR #5907 (merged); 2026-07-03 config.lock-wedge-fix brainstorm"
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# 🔧 Durable root-cause fix: stop the Concierge sandbox substrate from materializing `.git/config.lock` as a character device

## Enhancement Summary

**Deepened on:** 2026-07-03
**Agents used:** OverlayFS/whiteout kernel research (Explore), verify-the-negative sweep (general-purpose), architecture-strategist review.

### Key improvements
1. **Corrected the leading mechanism + Phase 2 layer.** Confirmed topology (`ci-deploy.sh:899`,
   `-v /mnt/data/workspaces:/workspaces`) shows bare repos on a **persistent bind-mount, not
   container overlay2** — so the node is a **real char-special inode (rdev non-zero) on the
   persistent volume**, not a container-overlay whiteout (which would be hidden/ENOENT and
   would NOT cause EEXIST). Phase 2 is scoped to `/mnt/data/workspaces`, host-side.
2. **Added `umount`-before-`rm` handling** for a bind-mounted device node (`rm -f` alone →
   `EBUSY`; silent non-remediation) — the plan's own sub-hypothesis needed it.
3. **Constrained the sweep to a quiescent window** (first-boot/entrypoint) and named the
   shared-git-data (ADR-068) concurrency hazard a periodic sweep would hit.
4. **Renumbered ADR-080 → ADR-081** (080 is taken) and made #5932-first ordering mandatory.
5. **Kernel-grounded the discriminators:** whiteout = char dev `0:0` (and hidden in merged
   view); `/dev/null` = `1:3`; `O_CREAT|O_EXCL` fails EEXIST on ANY inode type. Phase 1 now
   records `rdev` + merged-view visibility (the pair, not `rdev` alone, pins the layer).

### New considerations discovered
- **overlayfs hides merged-view whiteouts** → a *visible* char device is itself evidence
  against a plain container-overlay whiteout. This is the single most important finding.
- **"#5912 becomes dead-code insurance" is conditional** on the node being a one-time
  persistent-volume artifact; AC10's soak is its empirical test.
- **SDK-pin dependence:** installed SDK is v0.3.197 (module comment stale at v0.2.85); the
  (a)/(b) ruling is grounded in dir-only path passing (verified) + documented SDK behavior.

## Overview

The confirmed root cause of the worktree-creation wedge (companion tracker #5912) is
that `.git/config.lock` in the Concierge agent sandbox is a **non-regular file — a
character device**, write/remove-protected. Every `git config` write in
`ensure_bare_config()` then hits `EEXIST` against the pre-existing device node
(`open(O_CREAT|O_EXCL)` cannot create a regular lock over it), permanently wedging
worktree creation with no in-sandbox self-heal.

The repo-side fix (#5912 / PR #5932, WIP) makes `worktree-manager.sh` self-heal
**in-session** via a lockless `atomic_git_config` writer that never touches the masked
`config.lock`. That is the pragmatic PRIMARY fix (in-session, no host-level steps).
**This plan tracks #5934 — the DURABLE fix: stop the substrate from placing a device
node at that path in the first place** (or clear it at a privileged, non-blind layer
before the agent runs).

**The decisive planning question — WHERE does the char device originate?** The parent
handed three candidate origins: (a) an explicit `.lock`/`*.lock` mask in this repo's
sandbox config, (b) SDK-internal bubblewrap behavior driven by our config, or (c)
genuinely external Concierge mount infra. **This plan pins the origin before designing
the fix** (see `## Hypotheses`). The short answer, established by directly reading the
config: origin **(c)** — a container filesystem/mount **substrate** artifact — with (a)
and (b) affirmatively ruled out. Because the substrate defining that sandbox
(`apps/web-platform/Dockerfile`, `apps/web-platform/infra/cloud-init.yml`, the
`/workspaces` + git-data block volumes, `apparmor-soleur-bwrap.profile`) IS this repo's
IaC, the durable fix is **repo-expressible** — not a pure upstream ask.

**Re-evaluation criteria from #5934 — both answered at plan time:**

1. **Single-path or glob (`*.lock`)?** The repo sandbox config expresses **no `.lock`
   mask at all** — neither single-path nor glob (see Research Reconciliation R1). A
   character-device wedge is therefore a **per-path substrate artifact** (an OverlayFS
   whiteout is created per deleted path, not per glob), i.e. **single-path**. This
   **de-risks #5912**: its atomic temp file's `.lock` sibling
   (`config.soleur-tmp.$$.lock`) is a fresh, never-before-deleted path, so the substrate
   has no device node there. #5912's core assumption holds.
2. **Can the masking layer allow-list git's own lock acquisition / not mask `*.lock`?**
   There is nothing to allow-list — the wedge is not a deliberate mask; it is a
   **residual device node** (whiteout / leftover bind) at one specific historical path.
   The durable fix is therefore not "narrow the mask" but "**clear/prevent the residual
   node at a privileged layer**." **The "#5912 becomes dead-code insurance" claim holds
   ONLY under the assumption that the node is a one-time persistent-volume artifact**
   (created once, cleared at the next quiescent boot/entrypoint, never re-appearing
   mid-container-lifetime). This assumption is plausible — a char-device `config.lock` is
   NOT what a git-killed-mid-write leaves (that is a *regular* stale lock the in-sandbox
   age-guard already handles), so the char-device trigger is genuinely rare/substrate — but
   it is an assumption, and AC10's 7-day soak is its empirical test. If the node can appear
   mid-lifetime, entrypoint/boot granularity cannot preempt it and #5912 stays load-bearing.

## Research Reconciliation — Spec vs. Codebase

| # | Claim (issue / sibling brainstorm) | Codebase reality (verified this session) | Plan response |
|---|---|---|---|
| R1 | "Determine whether the masking is single-path or glob (`*.lock`)." | `apps/web-platform/server/agent-runner-sandbox-config.ts:213-221`: `filesystem.allowWrite = [workspacePath]`; `filesystem.denyRead = enumerateSiblingDenyPaths()` = sibling workspace dirs + `/proc` **only**. No `.lock`, no glob, no `/dev/null`/file-level mask anywhere in the repo sandbox config. | The config expresses **no `.lock` mask**. Origin (a) ruled out. The wedge is a per-path substrate artifact → **single-path**, de-risking #5912. |
| R2 | Sibling brainstorm: platform fix (3) "lives in Concierge sandbox infra (**not this repo**) … Filed as an upstream companion ask." | The sandbox filesystem substrate IS this repo's IaC: `apps/web-platform/Dockerfile`, `apps/web-platform/infra/cloud-init.yml`, `hcloud_volume.workspaces` (`placement-group.tf:29`), `git-data-bootstrap.sh` (`/mnt/git-data/repositories` bare repos, ADR-068), `apparmor-soleur-bwrap.profile`. The Concierge runs on **web-platform Hetzner hosts** whose image + volumes + bwrap policy are all repo-defined. | The durable fix is **repo-expressible IaC**, not a pure upstream ask. The plan lands an in-repo substrate remediation, not a no-op PR. |
| R3 | Sibling brainstorm Open Q1: "confirm single-path vs glob against the next fuller forensic **or by probing the sandbox mount config**." | The mount config was probed directly (R1) → answered. But the exact **substrate mechanism** (OverlayFS whiteout `rdev 0:0` vs. leftover bind vs. tmpfs device node) and **which volume/layer** holds the node are **not yet pinned** — the current sweep classifies a char device as `type=other`, discarding the decisive signal (`sweep_stale_git_locks`, `worktree-manager.sh:194-196` — no `-c` branch; `rdev` never emitted). | Phase 1 **sharpens the forensic** (`-c` detection + `rdev` major:minor) to pin the exact mechanism/layer on the next wedge **before** committing a substrate remediation to a specific layer (per Sharp Edge: "establish WHICH path executes before prescribing the fix layer"). |
| R4 | #5934: "the SDK translates denyRead into `--tmpfs` obscuring + `--ro-bind` re-binds, and file-level masking is done by bind-mounting `/dev/null`." | Confirmed via SDK types (`@anthropic-ai/claude-agent-sdk` v0.2.85: `denyRead`/`allowRead`/`allowWrite` are **path arrays**; module header `agent-runner-sandbox-config.ts:33-50` documents dir-level `denyRead → --tmpfs`, `allowRead → --ro-bind`). File-level `/dev/null` masking only fires for a **file path passed to `denyRead`** — the repo passes **only directory paths**. | Origin (b) ruled out **as the cause**: the SDK never receives `.git/config.lock` (or any `*.lock`) to mask. The `/dev/null`-bind mechanism is real but **our config never exercises it** (no file path ever enters `denyRead`). |

## Hypotheses — origin of the character device (the decisive gate)

Per the KEY PLANNING CONSTRAINT, the origin is pinned **before** designing the fix:

- **(a) Explicit repo mask of `.lock` / `*.lock`** — **RULED OUT.** The repo sandbox
  config (`agent-runner-sandbox-config.ts:172-223`) masks nothing under `.git/`; its
  only `denyRead` entries are sibling tenant workspaces + `/proc`, and its only
  `allowWrite` is the agent's own workspace. No file-level mask, no glob (R1, R4).
- **(b) SDK-internal bubblewrap behavior driven by our config** — **RULED OUT as the
  cause.** The SDK's file-level `/dev/null` mask fires only for a **file path** in
  `denyRead`; the repo passes only directory paths, so the SDK cannot emit a node at
  `.git/config.lock`. (The mechanism exists in the SDK; our config never triggers it.)
- **(c) Container filesystem / mount substrate** — **THE ORIGIN.** The device node is a
  **residual** artifact at one historical path on the **persistent host block volume**
  that holds the bare repos. Confirmed topology (`apps/web-platform/infra/ci-deploy.sh:899`):
  the Concierge container runs `-v /mnt/data/workspaces:/workspaces` — the bare repos live
  on a **bind-mounted persistent volume**, NOT the container overlay2 upper layer. The
  agent sees the residual node because the SDK/bwrap base `--ro-bind / /` faithfully
  re-exposes any pre-existing char-special inode at the bare-repo path (read-only) into the
  sandbox. **Leading concrete mechanism (revised at deepen-plan — see Research Insights):**
  a **real char-special inode (rdev NON-zero)** on `/mnt/data/workspaces` — a persistent
  node that survives container recreation and deploys, matching the "wedged forever /
  across sessions" symptom. A container-overlay-layer whiteout is **discriminated AGAINST**:
  overlay2 does not overlay the bind mount, and a merged-view whiteout renders as ENOENT
  (hidden) so git's `O_CREAT|O_EXCL` would SUCCEED — the opposite of the observed EEXIST on
  a VISIBLE node. Sub-hypotheses to separate in Phase 1: a `/dev/null`-style device bind
  (`rdev 1:3`) vs. a real `mknod` node (other non-zero rdev) vs. an anomalous visible `0:0`.

**Phase 1 discriminates these with `rdev` + merged-view visibility:** the node is already
KNOWN to be visible in the sandbox (that is the symptom), so `rdev` is the discriminator —
`1:3` ⇒ a bound `/dev/null` (needs `umount` before `rm`); other non-zero ⇒ a real device
node (`rm` clears it); a *visible* `0:0` ⇒ anomalous (a merged-view whiteout would be
hidden) and must be explained before acting. The remediation LAYER (Phase 2) is scoped to
the persistent volume `/mnt/data/workspaces` (ADR-068's `/mnt/git-data` is the not-yet-GA
multi-host future, `replicas=1` still in force — not the active wedge surface).

### Research Insights — kernel-grounded discriminators (deepen-plan)

**Revised conclusion (deepen-plan):** given the confirmed bind-mount topology
(`ci-deploy.sh:899`, bare repos on persistent `/mnt/data/workspaces`) AND the symptom of a
**visible** char device causing EEXIST, the leading mechanism is a **real char-special
inode (rdev non-zero) on the persistent volume** — a container-overlay whiteout is ruled
out (overlay2 doesn't overlay the bind mount; a merged-view whiteout is hidden/ENOENT). The
`0:0`-whiteout hypothesis survives only as an anomaly to explain, not the prior.

Authoritative grounding for the mechanism claims (fold into ADR-081):

- **Ruling-out (a)/(b) confirmed by a verify-the-negative sweep.** `agent-runner-sandbox-config.ts`
  `denyRead` = sibling dirs + `/proc`, `allowWrite = [workspacePath]` (all directory paths;
  no `.lock`/glob/`/dev/null`); no other sandbox file (`sandbox.ts`, `bash-sandbox.ts`,
  `sandbox-hook.ts`, `sandbox-startup-classifier.ts`, `plugin-mount-check.ts`) binds
  `/dev/null` or `mknod`s a node. **Caveat:** the SDK's actual bwrap-arg construction lives
  in a compiled CLI binary (not source-verifiable), and the INSTALLED SDK is **v0.3.197**
  (the module-header comment saying "v0.2.85" is stale) — so the "dir→`--tmpfs`,
  file→`/dev/null`" behavior is grounded in the module-header documentation, not re-derived
  from vendored source. The ruling-out is therefore **SDK-pin-dependent**; a future SDK bump
  could change the guarantee. This does not weaken the conclusion (the repo demonstrably
  passes only directory paths, so the file-mask path is never reached regardless), but
  ADR-081 should state the pin-dependence as a one-line caveat + a drift-guard idea.

- **Overlay whiteout = char device `rdev 0:0`.** Kernel doc (Documentation/filesystems/overlayfs.rst, "Whiteouts and opaque directories"): *"A whiteout is created as a character device with 0/0 device number or as a zero-size regular file with the xattr `trusted.overlay.whiteout`."* So `test -c` is true and GNU `stat -c '%t:%T'` returns `0:0`. (Ref: docs.kernel.org/filesystems/overlayfs.html.)
- **`/dev/null` = char device `rdev 1:3` — a clean discriminator.** A bwrap `--dev-bind /dev/null <path>` (or any `/dev/null` bind) makes the path a char device with `rdev 1:3`, NOT `0:0`. `--tmpfs` alone creates no device nodes. So the Phase-1 `rdev` field cleanly separates: **`0:0` ⇒ overlay whiteout**; **`1:3` ⇒ a bound `/dev/null`** (some mount/plumbing layer binds it — never our repo config, R1/R4); **other non-zero ⇒ a real `mknod` device**. (Ref: bwrap.1; local `stat` verification.)
- **LOAD-BEARING CAVEAT — overlayfs HIDES merged-view whiteouts.** The kernel conceals a whiteout from the merged/mounted view: through the overlay mount the path reads as **ENOENT (absent)**, and a whiteout is only visible as a char device when reading the **raw upper/`diff` dir directly**. Consequence for diagnosis: the wedge forensic reportedly **observed a visible non-regular node** (`type=other`, `stat` succeeded) AND git failed `EEXIST` — a *merged-view* container-overlay whiteout would instead present as ENOENT and git's `O_CREAT|O_EXCL` would **succeed**. So a *visible* char device at `.git/config.lock` points AWAY from a plain merged-view container-overlay whiteout and TOWARD either (i) a `/dev/null`-style bind (`rdev 1:3`) at some mount layer, (ii) a persistent-volume/raw-diff exposure where the whiteout IS visible, or (iii) a real device node. **Phase 1 must therefore record BOTH the `rdev` AND whether the node is visible in the agent's merged view** — that pair, not `rdev` alone, pins the layer. This materially tightens Phase 2 layer selection and is the single most important deepen-plan finding.
- **`O_CREAT|O_EXCL` fails `EEXIST` on ANY pre-existing inode type** (POSIX/open(2): "fail if the file exists" — not "if a regular file exists"). A leftover char-device at `.git/config.lock` therefore blocks git's lock creation before any device semantics apply — confirming the wedge mechanism. (Ref: man7.org/linux/man-pages/man2/open.2.html.)
- **Alternate whiteout form to rule out:** a zero-size **regular** file bearing the `trusted.overlay.whiteout` xattr. This presents as `type=regular` (the existing age-guarded removal path would touch it) but is semantically a whiteout — Phase 1 should additionally `getfattr -n trusted.overlay.whiteout` (or `lsattr`/`stat`) a *regular* `config.lock` before treating it as an ordinary stale lock.

## User-Brand Impact

**If this lands broken, the user experiences:** an autonomous Concierge `/soleur:go` /
`/soleur:one-shot` session that **cannot create a worktree and cannot start any work** —
the product appears silently, permanently broken for that user, with no in-session
recourse (the #5912 self-heal is the only stopgap until this durable fix removes the
node at the substrate).

**If this leaks, the user's data/workflow is exposed via:** N/A for data — this is git
plumbing on the agent's own bare repo. The workflow-availability blast radius is the
exposure: a single user hitting the wedge loses the entire session.

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true` — CPO
sign-off required at plan time before `/work` begins (carry forward the CTO/CPO framing
from the 2026-07-03 sibling brainstorm, which set `USER_BRAND_CRITICAL=true`);
`user-impact-reviewer` runs at review time.

## Implementation Phases

### Phase 1 — Sharpen the in-repo forensic to pin the substrate mechanism (ships regardless of Phase 2/3 outcome)

The current sweep loses the decisive signal: a character device falls through
`worktree-manager.sh` type-precedence to `type=other` (`:181-196`), and `rdev` is never
captured. Sharpen it so the **next** wedge — or a deliberately-forced fixture — proves
the exact mechanism.

- **#5932-FIRST ordering is MANDATORY, not optional (P1 — arch review).** PR #5932 is
  +160/−19 on `worktree-manager.sh` and +45/−10 on the diag test — the exact two files
  Phase 1 edits — and its `atomic_git_config` refactor touches the SAME
  `sweep_stale_git_locks` type-precedence ladder (`:181-196`), the SAME
  `SOLEUR_GIT_LOCK_DIAG` echo, and the SAME diag test. #5932 is the more urgent PRIMARY
  in-session fix. **Merge #5932 first, then rebase Phase 1's additive `-c`/`rdev`/visibility
  additions onto the merged sweep.** Do NOT duplicate #5932's `atomic_git_config` work.
- Add an explicit char-device branch in the type-precedence ladder
  (`worktree-manager.sh` `sweep_stale_git_locks`), **before** the `-d`/`-f`/`other`
  fallthrough: `elif [[ -c "$path" ]]; then ftype=chardevice`.
- Capture and emit `rdev` AND merged-view visibility on the DIAG line for the char-device
  case: `rdev=$(stat -c '%t:%T' -- "$path" 2>/dev/null)` (GNU `stat`; hex major:minor —
  `1:3` ⇒ bound `/dev/null`, other non-zero ⇒ real device, `0:0` ⇒ anomalous whiteout).
  Also record whether the node is a mountpoint (`stat -c%m` == its realpath) — a bind vs a
  plain inode determines whether Phase 2 needs `umount`. Extend `SOLEUR_GIT_LOCK_DIAG` to
  `… type=chardevice … rdev=$rdev mount=<none|mountpoint>`. For a REGULAR `config.lock`,
  additionally probe `getfattr -n trusted.overlay.whiteout` (the zero-size-regular-file
  whiteout form) before treating it as an ordinary stale lock.
- Keep the **existing** UNREMOVABLE behavior for `chardevice` (non-regular → flag
  unremovable, never auto-`rm` on the blind surface — `:237-247`). The DIAG `rdev` is
  the new forensic; removal stays the privileged Phase-2 job.
- **Test (RED→GREEN):** extend `plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh`
  with a fixture that forces a char device at `config.lock`
  (`mknod config.lock c 1 3` where permitted; else a skip-guard mirroring the suite's
  existing capability gate) and asserts the DIAG line reports `type=chardevice` + a
  well-formed `rdev=…`. This is the bit-rot guard the sibling brainstorm's "CI
  char-device fixture" decision already calls for — build it once here.

### Phase 2 — Durable substrate remediation: privileged, non-blind char-device lock sweep (in-repo IaC) — GATED on Phase 1 evidence

The blind in-sandbox agent cannot remove the node (no privilege, and auto-`rm -rf` on a
blind surface is out of scope). The durable fix runs the removal at a **root-privileged,
non-blind layer** the substrate is provisioned from — clearing any device-node
`config.lock` / `config.worktree.lock` under bare git dirs **before** an agent session
uses the repo. Mirror the existing opt-in volume-maintenance precedent
`apps/web-platform/infra/inngest-wiped-volume-verify.sh` (base64-staged via
`infra-config-apply.sh`, run from cloud-init/bootstrap).

- **Layer: the persistent volume `/mnt/data/workspaces` on the host (arch-review P1).**
  Confirmed topology (`ci-deploy.sh:899`): bare repos live on the host bind-mount
  `/mnt/data/workspaces`, so the durable sweep runs **host-side** at a **quiescent window**
  — the volume bootstrap / a new sibling staged like `inngest-wiped-volume-verify.sh`,
  invoked from `cloud-init.yml` `runcmd` on first boot AND re-run idempotently on existing
  hosts. (A container-entrypoint step also runs before the agent starts and is an
  acceptable secondary placement; the `Dockerfile` overlay layer is NOT the target — it
  does not overlay the bind mount.) Do NOT scope to ADR-068 `/mnt/git-data` (not-yet-GA).
- **Sweep semantics (root, non-blind), rdev-aware removal:** find `config.lock` /
  `config.worktree.lock` under bare git dirs that are **character devices** (`test -c`),
  bounded to KNOWN bare-repo roots (not an unbounded `find` across all tenant workspaces —
  arch-review P2 scaling). For each:
  - **plain char-special inode** (not a mountpoint): `rm -f` (root can, unlike the
    sandboxed agent).
  - **bind-mounted device node** (`stat -c%m` == realpath ⇒ mountpoint; e.g. a bound
    `/dev/null`, `rdev 1:3`): `unlink` returns `EBUSY` — the sweep MUST `umount` the path
    FIRST, then `rm -f`; otherwise it silently "succeeds" while the wedge persists
    (arch-review P1). Emit a distinct marker for the umount branch.
  - emit one structured, no-SSH-readable marker per removal (Sentry/Better Stack + a state
    file readable by the `cat-*-state.sh` pattern), naming the path + rdev + branch taken.
  Regular in-flight locks are **never** touched (that stays the age-guarded in-sandbox job).
- **Quiescence is the concurrency-safety mechanism (arch-review P1).** The sweep runs ONLY
  in a quiescent window (first-boot / container-entrypoint, before the agent runtime
  starts) — NOT as a periodic job against live git-data. Under a future ADR-068 shared
  git-data topology the volume is NOT quiescent (concurrent cross-host writers), so a
  periodic sweep there would race a live writer; the entrypoint/first-boot ordering closes
  the TOCTOU by construction. State this explicitly; do not add a periodic timer.
- **Idempotent + safe:** no-op when no char-device lock exists; scoped strictly to the two
  config-write lock filenames on bare git dirs (never `index.lock`/`HEAD.lock`/per-worktree
  locks — same scoping rationale as `sweep_stale_git_locks:169-176`).
- **Apply path:** cloud-init + idempotent bootstrap script (extends already-provisioned
  hosts without re-provisioning). Applied via the auto-applied `apps/web-platform/infra/`
  root (`terraform apply`) and/or the deploy pipeline — applied through the pipeline, not
  by hand on a host.

### Phase 3 — External-substrate fallback (fires ONLY if Phase 1 proves a substrate layer outside this repo's IaC)

If Phase 1's `rdev`/mount evidence proves the node lives on a substrate layer **not**
expressible in this repo's IaC (e.g. a host-runtime storage-driver default outside
`apps/web-platform/infra/`), then Phase 2's in-repo sweep cannot reach it. In that case:

- Ship Phase 1 (forensic) + the ADR (below) + the #5912 de-risking regardless — **not a
  no-op PR**.
- File a **clearly-scoped upstream/host prerequisite** issue naming the exact layer,
  the `rdev` evidence, and the required change (e.g. storage-driver/mount option), with a
  re-evaluation criterion. Route per the automation-feasibility gate: if the change is a
  host-level configuration action, mark `automation-status: UNVERIFIED — /work MUST run a
  Playwright attempt before any handoff` rather than pre-assuming it is human-only.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (origin pinned):** the plan/PR body states origin = (c) substrate, with (a)
  and (b) ruled out, each citing `agent-runner-sandbox-config.ts` line evidence.
- [x] **AC2 (forensic char-device branch):** `sweep_stale_git_locks` in
  `worktree-manager.sh` contains an `[[ -c "$path" ]] → ftype=chardevice` branch placed
  **before** the `-d`/`-f`/`other` fallthrough; `grep -n 'ftype=chardevice'
  plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` returns ≥1.
- [x] **AC3 (rdev emitted):** for a char-device lock the `SOLEUR_GIT_LOCK_DIAG` line
  includes a `rdev=<hex>:<hex>` field; asserted by the diag test.
- [x] **AC4 (bit-rot fixture reaches the branch):** `worktree-manager-stale-lock-diag.test.sh`
  has a case that forces a char device at `config.lock` and asserts
  `type=chardevice` + well-formed `rdev`; the test **fails** if the `-c` branch is
  removed. Run via the repo's shell-test convention (`plugins/soleur/test/*.test.sh` —
  verify runner before prescribing; do NOT hardcode `bats`).
- [x] **AC5 (char-device stays unremovable in-sandbox):** the sweep still emits
  `SOLEUR_GIT_LOCK_UNREMOVABLE … type=chardevice reason=non-regular-lock` and never
  auto-`rm`s on the blind surface (regression guard on `:245-246`).
- [x] **AC6 (Phase 2 sweep is char-device-scoped, rdev-aware + idempotent):** the
  privileged sweep script removes **only** `config.lock`/`config.worktree.lock` that are
  `test -c` true under KNOWN bare-repo roots, is a no-op otherwise, and has a shell test
  asserting: (i) removes a plain forced char-device lock, (ii) `umount`s-then-`rm`s a
  bind-mounted device node (mountpoint case) rather than failing `EBUSY`, (iii) leaves a
  regular lock untouched, (iv) leaves `index.lock` untouched.
- [x] **AC7 (fully pipeline-applied):** every infra change applies through
  cloud-init/bootstrap + `terraform apply` / the deploy pipeline; no phase applies a
  change by hand on a host.
- [x] **AC8 (ADR shipped, not deferred):** the ADR named below exists on this branch
  (create/amend in this PR), not a follow-up issue.

### Post-merge (pipeline — automated)

- [ ] **AC9 (substrate sweep is live):** after the infra apply, the privileged sweep's
  structured marker is readable **without SSH** (Sentry/Better Stack event OR the
  `cat-*-state.sh` state-file read) confirming the sweep ran at least once.
- [ ] **AC10 (soak — wedge non-recurrence):** for **7 days** post-deploy, zero
  `SOLEUR_GIT_LOCK_UNREMOVABLE … type=chardevice` events across Concierge sessions.
  Enrolled as a follow-through (see Observability §Soak).

## Infrastructure (IaC)

### Terraform changes
- No new Terraform **resources**; the change extends existing artifacts under the
  auto-applied `apps/web-platform/infra/` root and `apps/web-platform/Dockerfile`.
- Files (final set decided by Phase 1 layer evidence): the privileged sweep script (new,
  e.g. `apps/web-platform/infra/git-lock-chardevice-sweep.sh` mirroring
  `inngest-wiped-volume-verify.sh`), its base64 staging line in `infra-config-apply.sh`,
  and its invocation in `cloud-init.yml` `runcmd` and/or `git-data-bootstrap.sh` and/or
  the container entrypoint.
- No new `TF_VAR_*` / secrets (no vendor credential; the sweep needs only root on the
  host it already runs on).

### Apply path
(b) cloud-init + idempotent bootstrap script — the default for existing infra. The
existing web-platform release/deploy pipeline restarts the container on merge; the
volume-bootstrap path re-runs idempotently on existing hosts. Expected downtime: none
(sweep is a fast no-op when clean). Blast radius: the two config-lock filenames on bare
git dirs only.

### Distinctness / drift safeguards
Sweep is idempotent and strictly char-device-scoped; a regular in-flight lock is never
touched, so no interaction with the in-sandbox age-guarded self-heal. No
`lifecycle.ignore_changes` needed (no new TF resource). dev≠prd not applicable (host
maintenance script, not a Supabase/data surface).

### Vendor-tier reality check
N/A — no vendor resource created (Hetzner host-local maintenance only).

## Observability

**Corrected after review:** this host's `vector.toml` has **no Sentry sink** — all
telemetry ships to **Better Stack** (journald → `host_scripts_journald` → HTTP sink).
The earlier Sentry / `cat-*-state.sh` / heartbeat citations below were aspirational;
the wired layer is the Better Stack `SOLEUR_CHARDEV_SWEEP_*` markers.

```yaml
liveness_signal:
  what: "privileged char-device lock sweep ran (per deploy invocation)"
  cadence: "per deploy (ci-deploy.sh pre-canary-docker-run); event-driven, NOT a fixed heartbeat cadence"
  alert_target: "SOLEUR_CHARDEV_SWEEP_DONE marker in Better Stack (scripts/betterstack-query.sh --grep SOLEUR_CHARDEV_SWEEP_DONE)"
  configured_in: "apps/web-platform/infra/git-lock-chardevice-sweep.sh + ci-deploy.sh + vector.toml"
error_reporting:
  destination: "Better Stack (journald host_scripts_journald → HTTP sink) + host journal; host-local /var/lock state file (NOT no-SSH readable — no cat-reader wired)"
  fail_loud: "sweep failure to remove a detected char-device lock emits a loud SOLEUR_CHARDEV_SWEEP_FAILED marker → Better Stack; never silent"
failure_modes:
  - mode: "char-device config.lock detected but NOT cleared (umount/rm failed → wedge persists)"
    detection: "SOLEUR_CHARDEV_SWEEP_FAILED marker (Better Stack), carrying path + rdev + branch + reason"
    alert_route: "betterstack-query.sh --grep SOLEUR_CHARDEV_SWEEP_FAILED; this is the AC10 soak's regression signal"
  - mode: "in-sandbox wedge reaches a live session despite the sweep"
    detection: "in-sandbox SOLEUR_GIT_LOCK_UNREMOVABLE type=chardevice rdev=<maj:min> on the agent's captured stdout"
    alert_route: "grep-able orchestrator stdout ONLY — NOT yet mirrored to a queryable sink (tracked as an observability follow-up); the host FAILED marker above is the wired proxy"
  - mode: "sweep removes a lock it should not (regular / index.lock)"
    detection: "sweep test asserts -type c scope + TOCTOU re-assert; structured removal marker names the exact path+rdev removed"
    alert_route: "CI test gate (git-lock-chardevice-sweep.test.sh); Better Stack removal-marker review"
  - mode: "sweep never runs (staging/invocation drift)"
    detection: "absence of SOLEUR_CHARDEV_SWEEP_DONE marker in the deploy window (Better Stack)"
    alert_route: "the AC10 soak treats zero-DONE as TRANSIENT (inconclusive, never a false PASS)"
logs:
  where: "Better Stack (host_scripts_journald) + host journal; host-local /var/lock state file"
  retention: "Better Stack default; state file overwritten per run"
discoverability_test:
  command: "scripts/betterstack-query.sh --since 7d --grep SOLEUR_CHARDEV_SWEEP_DONE (needs BETTERSTACK_QUERY_* from Doppler prd_terraform) — no remote shell"
  expected_output: "one JSONEachRow row per sweep run (DONE marker); zero SWEEP_FAILED rows when the fix holds"
```

**Affected-surface (blind sandbox) note (Phase 2.9.2):** the failing surface is the
agent bwrap sandbox — a blind surface. The load-bearing probe is the **in-sandbox**
`SOLEUR_GIT_LOCK_DIAG`/`UNREMOVABLE` line emitted FROM the sandbox on captured stdout
(not only a host-side sweep marker), and its `rdev` field **discriminates all competing
substrate hypotheses in one event** (`0:0` whiteout vs. non-zero leftover-bind vs.
mount) — satisfying the structured-fields-discriminate-all-hypotheses requirement.

### Soak follow-through enrollment (corrected after review)
- Script: `scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh` — PASS (exit 0)
  only when, for the soak window, the sweep ran ≥1× (a `SOLEUR_CHARDEV_SWEEP_DONE`
  marker) AND zero `SOLEUR_CHARDEV_SWEEP_FAILED` markers occurred, queried via
  **Better Stack** (`scripts/betterstack-query.sh`). Fail-safe TRANSIENT (never a false
  PASS/close) on any query/auth failure OR when no DONE marker is observed yet.
  (The original Sentry-query design was vacuous — the in-sandbox UNREMOVABLE line is not
  mirrored to any queryable sink; see `## Observability`.)
- Tracker directive on #5934: `<!-- soleur:followthrough script=scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh earliest=<deploy+7d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
  + the `follow-through` label.
- `BETTERSTACK_QUERY_*` wired into `.github/workflows/scheduled-followthrough-sweeper.yml`
  (shared with #5110); until those GH secrets are provisioned the soak stays fail-safe
  TRANSIENT (#5934 stays open, never false-closes).

## Architecture Decision (ADR/C4)

This plan records a substrate-root-cause decision that a future engineer would be
surprised to find undocumented → an ADR is a **deliverable of this PR**, not a follow-up.

### ADR
- **Create ADR-081 — "Char-device residual at `.git/config.lock`: substrate root cause
  and privileged non-blind sweep remediation"** (or amend ADR-075 if the reviewer
  prefers extending the tenant-isolation record). Decision: the sandbox filesystem
  substrate can leave a character-device residual (overlay whiteout `rdev 0:0`) at a
  historical `config.lock` path; the durable remediation is a root-privileged,
  non-blind, char-device-scoped sweep at container-entrypoint / volume-bootstrap, NOT an
  in-sandbox mask change (nothing in the repo config masks `.lock`). Cross-reference
  ADR-068 (multi-host git-data), ADR-075 (tenant read isolation), and #5912/#5932 (the
  in-session self-heal companion). `## Alternatives Considered` must record: (i) in-repo
  mask allow-list — rejected, no mask exists; (ii) unconditional in-sandbox `rm -rf` —
  rejected, blind-surface + privilege; (iii) #5912 lockless writer alone — accepted as
  primary but not durable (node persists).
- Status: `adopting` until the 7-day soak (AC10) confirms non-recurrence, then `accepted`.

### C4 views
**No C4 impact.** All three model files were read
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`).
Enumerated and confirmed already-modeled / unchanged: (a) **external human actors** — the
workspace Owner (`model.c4:9`); no new correspondent/recipient. (b) **external systems** —
GitHub; no new inbound/outbound vendor. (c) **containers / data-stores** — Agent Runtime
(`claude`, `:52`), Shared git-data (`gitDataStore`, `:194-196`), Compute/`/workspaces`
cluster (`hetzner`, `:164-166`, ADR-068); this change is an **internal
filesystem-substrate maintenance step within already-modeled containers** — no new store.
(d) **access relationships** — `claude -> gitDataStore` (`:304`) unchanged; no
ownership/tenancy edge changes. A privileged host-local lock sweep adds no element,
edge, or actor, so no `.c4` edit is in scope.

## Domain Review

**Domains relevant:** Engineering (carry-forward from 2026-07-03 sibling brainstorm CTO assessment).

### Engineering
**Status:** reviewed (carry-forward)
**Assessment:** The temp-copy + atomic-rename in-session fix (#5912) is correct and is
the primary path; #5934's durable fix is the substrate-layer node removal. This plan's
CTO-relevant additions: (1) the origin is pinned to the substrate with (a)/(b) ruled out
by direct config read; (2) the remediation LAYER must be chosen from Phase 1 `rdev`
evidence, not pre-assumed (Sharp Edge: verify which path/layer executes before choosing
the fix layer); (3) the fix is repo-expressible IaC (correcting the brainstorm's
"not this repo" assumption). No Product/Legal surface — pure developer-tooling git
plumbing + host-maintenance IaC, no user-data or content surface.

### Product/UX Gate
Not relevant — no UI-surface file in `## Files to Edit` (scripts + infra + ADR only).
Mechanical UI-surface override did not fire.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` cross-checked against the planned
file set — `worktree-manager.sh`, `apps/web-platform/infra/*`, `apps/web-platform/Dockerfile`
— returned no open scope-outs touching these paths at plan time; re-run at /work Step 2.)

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — add the `-c`
  char-device branch + `rdev` field in `sweep_stale_git_locks` (coordinate with #5932).
- `plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh` — char-device fixture
  asserting `type=chardevice` + `rdev`.
- `apps/web-platform/infra/infra-config-apply.sh` — base64 staging line for the sweep
  script (mirror `INNGEST_WIPED_VOLUME_VERIFY_SH_B64`).
- `apps/web-platform/infra/cloud-init.yml` and/or `apps/web-platform/infra/git-data-bootstrap.sh`
  and/or `apps/web-platform/Dockerfile` (entrypoint) — invoke the sweep (final layer set
  by Phase 1 evidence).
- `.github/workflows/scheduled-followthrough-sweeper.yml` — wire soak secrets if new.

## Files to Create

- `apps/web-platform/infra/git-lock-chardevice-sweep.sh` — privileged, idempotent,
  char-device-scoped lock sweep (+ `.test.sh` sibling).
- `knowledge-base/engineering/architecture/decisions/ADR-081-*.md` — the substrate
  root-cause + remediation decision.
- `scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh` — soak probe.

## Alternative Approaches Considered / Non-Goals

| Approach | Verdict | Rationale |
|---|---|---|
| Allow-list git's lock acquisition in the sandbox mask | Rejected | No mask exists to narrow (R1). Not applicable. |
| Unconditional in-sandbox `rm -rf` of the char-device lock | Rejected | Blind surface + no privilege; auto-`rm -rf` on a blind surface is out of scope (worktree-manager.sh:153-154). |
| Rely on #5912 lockless writer alone | Rejected as durable fix (kept as primary in-session) | The device node persists on the substrate; #5934 is explicitly the "remove the node" tracker. |
| Vendored-SDK bwrap-arg reorder | Non-goal here | Tracked separately (ADR-075 "durable TOCTOU closer"); unrelated to the residual node. |

**Deferral tracking:** if Phase 3 fires (substrate outside this repo's IaC), file the
scoped upstream/host prerequisite issue with re-evaluation criteria and the roadmap
milestone, per the deferral-tracking gate. No other deferrals.

## Sharp Edges

- **The sweep target is the persistent volume `/mnt/data/workspaces`, not the container
  overlay.** overlay2 does not overlay the bind mount; a `Dockerfile`-layer sweep would
  never see the node. Confirm the bare-repo root path against `ci-deploy.sh:899` at /work.
- **`rm -f` alone cannot clear a bind-mounted device node** (`unlink` → `EBUSY`). If Phase
  1 `rdev`/mount evidence shows a mountpoint (e.g. bound `/dev/null` `rdev 1:3`), the sweep
  MUST `umount` before `rm`, else it "succeeds" while the wedge persists.
- **Run the sweep ONLY in a quiescent window** (first-boot / container-entrypoint) — never
  a periodic timer against live (future shared-git-data) volume, which would race a
  concurrent writer. Ordering is the TOCTOU-safety mechanism.
- **#5932 MUST merge first.** It is +160/−19 on the same `worktree-manager.sh` sweep
  function; treat Phase 1 as an additive rebase ON TOP of merged #5932, not a parallel edit.
- **ADR number: 081, not 080** — `ADR-080-runtime-plugin-deploys-via-image-rebuild.md`
  already exists. Verify the next free number at /work before creating the file.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This section is
  filled with a concrete artifact, vector, and `single-user incident` threshold.
- **Verify the shell-test runner before prescribing** (`plugins/soleur/test/*.test.sh`
  convention; do NOT hardcode `bats`). Force a char device via `mknod … c 1 3` only where
  permitted; gate with the suite's existing capability skip pattern.
- **GNU `stat` only** (`%t:%T` for `rdev`, `%m` for mount) — Linux containers + CI ubuntu
  + dev; mirrors the existing `stat -c%s`/`%m` usage in the same file.
