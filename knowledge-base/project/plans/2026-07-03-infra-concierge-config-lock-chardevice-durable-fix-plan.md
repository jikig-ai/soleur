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
   node at a privileged layer**." When that fix lands, #5912's fallback branch becomes
   dead-code insurance rather than a load-bearing path — exactly as #5934 predicted.

## Research Reconciliation — Spec vs. Codebase

| # | Claim (issue / sibling brainstorm) | Codebase reality (verified this session) | Plan response |
|---|---|---|---|
| R1 | "Determine whether the masking is single-path or glob (`*.lock`)." | `apps/web-platform/server/agent-runner-sandbox-config.ts:213-221`: `filesystem.allowWrite = [workspacePath]`; `filesystem.denyRead = enumerateSiblingDenyPaths()` = sibling workspace dirs + `/proc` **only**. No `.lock`, no glob, no `/dev/null`/file-level mask anywhere in the repo sandbox config. | The config expresses **no `.lock` mask**. Origin (a) ruled out. The wedge is a per-path substrate artifact → **single-path**, de-risking #5912. |
| R2 | Sibling brainstorm: platform fix (3) "lives in Concierge sandbox infra (**not this repo**) … Filed as an upstream companion ask." | The sandbox filesystem substrate IS this repo's IaC: `apps/web-platform/Dockerfile`, `apps/web-platform/infra/cloud-init.yml`, `hcloud_volume.workspaces` (`placement-group.tf:29`), `git-data-bootstrap.sh` (`/mnt/git-data/repositories` bare repos, ADR-068), `apparmor-soleur-bwrap.profile`. The Concierge runs on **web-platform Hetzner hosts** whose image + volumes + bwrap policy are all repo-defined. | The durable fix is **repo-expressible IaC**, not a pure upstream ask. The plan lands an in-repo substrate remediation, not a no-op PR. |
| R3 | Sibling brainstorm Open Q1: "confirm single-path vs glob against the next fuller forensic **or by probing the sandbox mount config**." | The mount config was probed directly (R1) → answered. But the exact **substrate mechanism** (OverlayFS whiteout `rdev 0:0` vs. leftover bind vs. tmpfs device node) and **which volume/layer** holds the node are **not yet pinned** — the current sweep classifies a char device as `type=other`, discarding the decisive signal (`sweep_stale_git_locks`, `worktree-manager.sh:194-196` — no `-c` branch; `rdev` never emitted). | Phase 1 **sharpens the forensic** (`-c` detection + `rdev` major:minor) to pin the exact mechanism/layer on the next wedge **before** committing a substrate remediation to a specific layer (per Sharp Edge: "establish WHICH path executes before prescribing the fix layer"). |
| R4 | #5934: "the SDK translates denyRead into `--tmpfs` obscuring + `--ro-bind` re-binds, and file-level masking is done by bind-mounting `/dev/null`." | Confirmed via SDK types (`@anthropic-ai/claude-agent-sdk` v0.2.85: `denyRead`/`allowRead`/`allowWrite` are **path arrays**; module header `agent-runner-sandbox-config.ts:33-50` documents dir-level `denyRead → --tmpfs`, `allowRead → --ro-bind`). File-level `/dev/null` masking only fires for a **file path passed to `denyRead`** — the repo passes **only directory paths**. | Origin (b) ruled out **as the cause**: the SDK never receives `.git/config.lock` (or any `*.lock`) to mask. The `/dev/null`-bind mechanism is real but **unreachable from our config**. |

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
  **residual** artifact of the container/volume substrate at one historical path.
  Leading concrete mechanism: an **OverlayFS / Docker-overlay2 whiteout**, which the
  kernel represents as a **character device with `rdev 0:0`** — created when a prior
  process (e.g. git killed under the 2026-07-01 seccomp/`unshare` EPERM outage, or an
  image/layer that deleted the path) removed `config.lock` across an overlay boundary,
  leaving a persistent whiteout the blind in-sandbox agent cannot `rm`. Alternatives to
  discriminate in Phase 1: a leftover `--bind` of a device node, or a tmpfs device node.

**Phase 1 discriminates these with `rdev`:** `0:0` ⇒ overlay whiteout; non-zero ⇒
real/leftover device bind. The remediation LAYER (Phase 2) is chosen from that evidence.

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

- **Coordinate with PR #5932** (WIP, same file + same `sweep_stale_git_locks` function).
  This plan's Phase 1 edits are **additive** (a new `-c` branch + one extra field on the
  existing `SOLEUR_GIT_LOCK_DIAG` line). Sequencing: if #5932 merges first, rebase onto
  it; if this merges first, #5932 rebases. Do NOT duplicate #5932's `atomic_git_config`
  work here — Phase 1 only extends the **diagnostic**.
- Add an explicit char-device branch in the type-precedence ladder
  (`worktree-manager.sh` `sweep_stale_git_locks`), **before** the `-d`/`-f`/`other`
  fallthrough: `elif [[ -c "$path" ]]; then ftype=chardevice`.
- Capture and emit `rdev` on the DIAG line for the char-device case:
  `rdev=$(stat -c '%t:%T' -- "$path" 2>/dev/null)` (GNU `stat`; hex major:minor —
  `0:0` ⇒ overlay whiteout). Extend `SOLEUR_GIT_LOCK_DIAG` to
  `… type=chardevice … rdev=$rdev`.
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

- **Layer selection is decided by Phase 1's `rdev` evidence** (do not pre-commit):
  - If the node is an **overlay whiteout on the container layer** (`rdev 0:0`, path under
    the container FS): the sweep runs at **container entrypoint** (before the agent
    runtime starts) — a new idempotent step in the image/entrypoint path
    (`apps/web-platform/Dockerfile` / entrypoint), removing char-device locks under
    known bare-repo roots.
  - If the node is on a **persistent block volume** (`/workspaces` or
    `/mnt/git-data/repositories`, ADR-068): the sweep runs in the volume bootstrap
    (`git-data-bootstrap.sh` and/or a new sibling staged like
    `inngest-wiped-volume-verify.sh`), invoked from `cloud-init.yml` `runcmd` on first
    boot **and** re-run on existing hosts via the idempotent bootstrap path.
- **Sweep semantics (root, non-blind):** find `config.lock` / `config.worktree.lock`
  under bare git dirs that are **character devices** (`test -c`); `rm -f` each (root can,
  unlike the sandboxed agent); emit one structured, no-SSH-readable marker per removal
  (Sentry/Better Stack + a state file readable by the `cat-*-state.sh` pattern). Regular
  in-flight locks are **never** touched (that stays the age-guarded in-sandbox job).
- **Idempotent + safe:** no-op when no char-device lock exists; scoped strictly to the
  two config-write lock filenames on bare git dirs (never `index.lock`/`HEAD.lock`/
  per-worktree locks — same scoping rationale as `sweep_stale_git_locks:169-176`).
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

- [ ] **AC1 (origin pinned):** the plan/PR body states origin = (c) substrate, with (a)
  and (b) ruled out, each citing `agent-runner-sandbox-config.ts` line evidence.
- [ ] **AC2 (forensic char-device branch):** `sweep_stale_git_locks` in
  `worktree-manager.sh` contains an `[[ -c "$path" ]] → ftype=chardevice` branch placed
  **before** the `-d`/`-f`/`other` fallthrough; `grep -n 'ftype=chardevice'
  plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` returns ≥1.
- [ ] **AC3 (rdev emitted):** for a char-device lock the `SOLEUR_GIT_LOCK_DIAG` line
  includes a `rdev=<hex>:<hex>` field; asserted by the diag test.
- [ ] **AC4 (bit-rot fixture reaches the branch):** `worktree-manager-stale-lock-diag.test.sh`
  has a case that forces a char device at `config.lock` and asserts
  `type=chardevice` + well-formed `rdev`; the test **fails** if the `-c` branch is
  removed. Run via the repo's shell-test convention (`plugins/soleur/test/*.test.sh` —
  verify runner before prescribing; do NOT hardcode `bats`).
- [ ] **AC5 (char-device stays unremovable in-sandbox):** the sweep still emits
  `SOLEUR_GIT_LOCK_UNREMOVABLE … type=chardevice reason=non-regular-lock` and never
  auto-`rm`s on the blind surface (regression guard on `:245-246`).
- [ ] **AC6 (Phase 2 sweep is char-device-scoped + idempotent):** the privileged sweep
  script removes **only** `config.lock`/`config.worktree.lock` that are `test -c` true
  under bare git dirs, is a no-op otherwise, and has a shell test asserting: (i) removes a
  forced char-device lock, (ii) leaves a regular lock untouched, (iii) leaves
  `index.lock` untouched.
- [ ] **AC7 (fully pipeline-applied):** every infra change applies through
  cloud-init/bootstrap + `terraform apply` / the deploy pipeline; no phase applies a
  change by hand on a host.
- [ ] **AC8 (ADR shipped, not deferred):** the ADR named below exists on this branch
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

```yaml
liveness_signal:
  what: "privileged char-device lock sweep ran (per boot / bootstrap invocation)"
  cadence: "on container start and/or volume bootstrap (idempotent re-run)"
  alert_target: "Better Stack heartbeat OR deploy-state marker read via cat-*-state.sh"
  configured_in: "apps/web-platform/infra/git-lock-chardevice-sweep.sh + infra-config-apply.sh"
error_reporting:
  destination: "Sentry (feature: agent-sandbox) + host journal + no-SSH state file"
  fail_loud: "sweep failure to remove a detected char-device lock emits a loud structured marker; never silent"
failure_modes:
  - mode: "char-device config.lock persists after sweep (wrong layer / permission)"
    detection: "in-sandbox SOLEUR_GIT_LOCK_UNREMOVABLE type=chardevice rdev=<maj:min> on the agent's captured stdout (the affected blind surface's own probe)"
    alert_route: "grep-able orchestrator stdout + Sentry mirror; discriminates rdev 0:0 (whiteout) vs leftover-bind in one event"
  - mode: "sweep removes a lock it should not (regular / index.lock)"
    detection: "sweep test asserts scope; structured removal marker names the exact path+rdev removed"
    alert_route: "Sentry event review; CI test gate"
  - mode: "sweep never runs (staging/invocation drift)"
    detection: "absence of liveness marker in state file / heartbeat"
    alert_route: "Better Stack heartbeat miss"
logs:
  where: "Sentry (feature: agent-sandbox) + host journal + infra state file"
  retention: "Sentry default; state file overwritten per run"
discoverability_test:
  command: "read the sweep state marker via apps/web-platform/infra/cat-*-state.sh (or query Sentry for type=chardevice events) — no remote shell"
  expected_output: "last-run timestamp + count of char-device locks removed (0 when clean)"
```

**Affected-surface (blind sandbox) note (Phase 2.9.2):** the failing surface is the
agent bwrap sandbox — a blind surface. The load-bearing probe is the **in-sandbox**
`SOLEUR_GIT_LOCK_DIAG`/`UNREMOVABLE` line emitted FROM the sandbox on captured stdout
(not only a host-side sweep marker), and its `rdev` field **discriminates all competing
substrate hypotheses in one event** (`0:0` whiteout vs. non-zero leftover-bind vs.
mount) — satisfying the structured-fields-discriminate-all-hypotheses requirement.

### Soak follow-through enrollment
- Script: `scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh` — exit 0 when,
  for the soak window, zero `type=chardevice` UNREMOVABLE events occurred
  (Sentry-rate soak; `start=` pinned strictly after deploy, mirroring
  `reconcile-ff-only-sentry-4977.sh`).
- Tracker directive on #5934: `<!-- soleur:followthrough script=scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh earliest=<deploy+7d> secrets=SENTRY_AUTH_TOKEN -->`
  + the `follow-through` label.
- Wire any new `secrets=` into `.github/workflows/scheduled-followthrough-sweeper.yml`.

## Architecture Decision (ADR/C4)

This plan records a substrate-root-cause decision that a future engineer would be
surprised to find undocumented → an ADR is a **deliverable of this PR**, not a follow-up.

### ADR
- **Create ADR-080 — "Char-device residual at `.git/config.lock`: substrate root cause
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
- `knowledge-base/engineering/architecture/decisions/ADR-080-*.md` — the substrate
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

- **Do not pre-commit the Phase 2 remediation layer.** Choose container-entrypoint vs.
  volume-bootstrap from Phase 1's `rdev`/mount evidence — a substrate fix at the wrong
  layer is the recurring "fixed a code path the surface never executes" failure class.
- **Coordinate the `worktree-manager.sh` edit with WIP PR #5932** (same file, same
  function) — additive only; rebase whichever merges second.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This section is
  filled with a concrete artifact, vector, and `single-user incident` threshold.
- **Verify the shell-test runner before prescribing** (`plugins/soleur/test/*.test.sh`
  convention; do NOT hardcode `bats`). Force a char device via `mknod … c 1 3` only where
  permitted; gate with the suite's existing capability skip pattern.
- **GNU `stat` only** (`%t:%T` for `rdev`, `%m` for mount) — Linux containers + CI ubuntu
  + dev; mirrors the existing `stat -c%s`/`%m` usage in the same file.
