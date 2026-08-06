# Session State

## Plan Phase

- Plan file: `knowledge-base/project/plans/2026-08-04-feat-registry-zot-restart-lever-plan.md`
- Status: **recovered from on-disk artifact** — a prior one-shot run (2026-08-04) completed
  plan + deepen-plan for #7278. Steps 1–2 were NOT re-run; re-planning would have discarded
  the prior run's decisions and burned a full cycle.

### Recovery evidence (Step 0a.5 collision probe, 2026-08-06)

The body-text probe surfaced merged PR #7280 whose diff includes:

- `knowledge-base/project/plans/2026-08-04-feat-registry-zot-restart-lever-plan.md`
- `knowledge-base/project/specs/feat-one-shot-7278-registry-restart-lever/tasks.md`

Scope discriminator (non-empty intersection against the issue's named paths) → **collision
confirmed as PLAN-ONLY**, not a completed implementation:

- `git ls-tree -r main` shows **no** `restart-registry` workflow — only the
  `restart-inngest-server.yml` precedent this plan mirrors.
- `tasks.md` on main carries an explicit banner: *"Only Phase 0 and Phase 0.5 landed, in
  PR #7280 … #7278 remains OPEN; every unchecked box below is still outstanding."*
- Task tally on main: **7 checked / 62 unchecked**.
- No live worktree or branch for 7278 existed before this run.

`linked:issue` hits #7283 and #7300 were discriminated as **citations, not collisions** —
`closingIssuesReferences` resolves them to #7282 and #7299 respectively, not #7278.

All refs passed the collision gate as OPEN: #7278, #7322, #7247, #7287, #6929.

### Errors

None. Plan recovered intact (frontmatter `issue: 7278`, `branch:` matches this worktree,
Overview + Acceptance Criteria both present, deepen-plan enhancement section present).

### Decisions

- Reuse the 2026-08-04 plan rather than re-planning — it is complete, deepened, and its
  Phase 0.5 prerequisite already shipped.
- Branch named `feat-one-shot-7278-registry-restart-lever` to match the existing spec
  directory on main, so tasks.md and session-state.md co-locate rather than forking a
  sibling spec dir.
- **Phase 0 preconditions must be re-verified, not assumed.** Task 0.5 carries an explicit
  re-scope trigger: *"If the store has filled and the registry is hard down, STOP and
  re-scope — the activation story changes materially."* That condition now appears to hold
  (#7247: zot failing releases with 500 / DIGEST_INVALID as of 2026-08-06 06:49 UTC),
  whereas the plan was authored 2026-08-04. Unchecked Phase 0 boxes (0.2, 0.4, 0.6) plus a
  fresh 0.5 re-pull gate the rest of the work.
- ADR ordinal 169 is marked PROVISIONAL in the plan frontmatter and must be re-derived
  against freshly-fetched `origin/main` at ship (task 0.1 was checked on 08-04 and has since
  had two days of merges — treat it as stale).

### Components Invoked

- `soleur:go` → `soleur:brainstorm` (Hetzner host-class strategy) → `soleur:one-shot`
- Step 0a.5 collision probes: `gh issue view`, `gh pr list --search linked:issue`,
  `gh pr list --search "#N in:body" --state merged`, `gh pr diff --name-only`,
  `git log origin/main --grep`
- Plan/deepen: **recovered from disk**, not re-invoked.

## Phase 0 — task 0.5 RE-SCOPE TRIGGER: **FIRED** (2026-08-06)

Task 0.5 reads: *"Re-pull `SOLEUR_ZOT_DISK`. Record `pcent` and `zot_restarts`. **If the store
has filled and the registry is hard down, STOP and re-scope** — the activation story changes
materially."*

Pulled myself via `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh
--since 6h --grep SOLEUR_ZOT_DISK`. **72 samples, 6-hour window (04:30 → 10:25 UTC):**

| Field | Value | Reading |
|---|---|---|
| `pcent` | **100** on **72 / 72** samples | store volume is **completely full**, continuously |
| `zot_restarts` | 13954 → 15354 | **1,400 restarts in 6 h** (~3.9/min — matches #7247) |
| `oom_killed` | `false` × 72 | **not** an OOM |
| `zot_oom_kills` / `oom_kills_5m` | `0` × 72 | **not** an OOM |
| `zot_anon_mb` | 36 (cap 3072) | memory at **~1.2 %** of cap — memory is not the constraint |
| `fs_size_gb` / `block_size_gb` | 59 / 60, `resize_ok=true` | already grown to fill the device; **no slack to reclaim by resizing** |

### What this falsifies

The plan's implicit activation story was that an operator-reachable **restart** recovers a
crash-looping zot. **It does not recover this one.** Restarting zot into a 100 %-full volume
restarts it into the same wall — which is precisely why `--restart unless-stopped` has already
burned **15,354** restarts without recovering. The lever as planned would be *reachable* and
still *ineffective* on the live incident.

Note this also refutes the OOM framing carried by
`knowledge-base/engineering/operations/post-mortems/zot-registry-restart-loop-oom-postmortem.md`
for the CURRENT episode: zero OOM kills across the whole window, 36 MB anon against a 3072 MB
cap. The memory cap is working; the disk is the binding constraint.

### Disk diagnosis (operator-directed, 2026-08-06)

**Correction — my first hypothesis below was wrong.** I proposed orphaned `blobs/uploads/`
accumulating past zot's GC. `cloud-init-registry.yml:47` and the `#6247` precedent refute it:
*"gc alone only reclaims DANGLING blobs"* and *"**gc cannot reclaim a blob the policy says to
KEEP**"*. The live logs agree — GC runs hourly and reports `gc successfully completed … no
digests left, finished`, i.e. it is working and has nothing to collect. Retained for the record;
the paragraph below it is superseded.

**The precedent is exact.** `variables.tf:249` records that this identical failure occurred at
30 GB on 2026-07-09 (#6247): `resize_ok=true` + `pcent=100` on a fully-grown fs — *"a genuine
capacity limit, NOT a resize regression"*. It was fixed by growing 30→60 GB **and** tightening
the keep-set. It has now recurred at 60 GB.

**Current keep-set** (`cloud-init-registry.yml:100-113`), per repo, ×2 repos:
`latest` + `v.*`×5 + `[0-9a-f]{7,64}`×5 + `sha256-.*`×50 (sig referrers, small).

> **Honest gap: I cannot confirm the 59 GB is all policy-KEPT blobs.** Rough arithmetic from
> the recorded ~1.5–2 GB/image puts the keep-set nearer ~25 GB than 59 GB. Something may be
> consuming space beyond it. `SOLEUR_ZOT_DISK` reports `pcent` but **no per-path breakdown**,
> so the telemetry cannot answer it — and I will not guess at a number I have not measured.

### The actual root blocker — every remediation needs host execution, and none exists

| Remediation | Blocked by |
|---|---|
| Tighten the keep-set | lives in `/etc/zot/config.json`, written by cloud-init → needs a host write + zot restart |
| Grow the volume again | `hcloud` resize is online, but `resize2fs` runs only in `runcmd`, which `cloud-init-registry.yml:671` states is **PER-INSTANCE and does NOT re-run on reboot** → needs a rebuild |
| Force a GC pass | **no endpoint exists** — measured 2026-08-05: `/v2/_zot/gc`, `/v2/_catalog/gc`, `/_zot/gc`, `/v2/_zot/ext/gc` all 404, and the pinned build's `BinaryType` excludes mgmt/scrub/search |
| Add per-path disk telemetry to diagnose further | the monitor script is itself written by cloud-init → same blocker |
| Restart zot | the 5-min cron self-heal restarts only on a *mount* failure, not on a full disk |

**Everything converges on one missing capability: there is no way to execute anything on this
host.** That is exactly #7278. So the lever is the right work — but a **restart-only** lever
resolves none of the rows above. To be the fix it must be able to deliver a **config change**
and/or a **reclaim/resize** action, which is what the plan's own "must CHANGE something"
constraint was reaching for.

### Superseded hypothesis (kept for the record)

#7247 reports the release path failing at `PATCH .../blobs/uploads/<uuid>` → **500**, then
`PUT` → `DIGEST_INVALID`. On a full volume a blob upload cannot be written, so it fails
mid-flight and leaves an orphaned `blobs/uploads/` entry. zot's GC collects **manifests and
digests** — the logs repeatedly show `gc successfully completed … no digests left, finished`,
i.e. GC is running and finding nothing to reclaim — but in-progress/abandoned **uploads** are
a different reclamation path. That gives a self-sustaining loop: full disk → failed upload →
orphan → fuller disk.

If that holds, the reclaim target is the upload scratch area, not the manifest GC.

### Consequence for scope

The restart lever is still worth building — it remains the documented **rollback safety net**
and the open blocker that **vetoes the recut** (#7287). But it is **not** the #7247 fix, and
shipping it as though it were would close an incident that is still burning. The plan's own
constraint already points at the correction: the lever must be able to **CHANGE something**,
not merely re-run the same failing start. On this evidence the action set needs a
**disk-reclaim** action, not just `restart`.

**No implementation was written. Halted at Phase 0 per the plan's instruction.**

## Upstream context

This work was selected by the operator during the Hetzner host-class brainstorm
(worktree `feat-hetzner-host-class-strategy`, PR #7322) over firing a registry recreate.
The recreate path is vetoed while #7278 is open, so this lever is simultaneously the
cheapest fix for the #7247 crash-loop and the rollback safety net the recut depends on.
