---
title: "Clearing a masking CI wedge exposes a chain of latent defects — verify each fix by running the pipeline, file each as its own issue, and know when the wall is host-visibility"
date: 2026-07-03
category: workflow-patterns
tags: [ci, terraform, hetzner, seccomp, deploy-pipeline, latent-defects, verification, scope-discipline, auto-close, adr-068, adr-079]
issues: [5887, 5877, 5911, 5955, 5960, 5950, 5957, 5963]
---

# Learning: clearing a masking wedge unwinds a cascade of latent defects

## Problem

`/soleur:go #5887` looked like a one-line infra fix (a red `apply-web-platform-infra.yml`).
It unwound into a **4-link chain** of latent defects, each of which had **never run green**
because the one before it blocked the pipeline before that step ever executed:

1. **#5887** — the #5877 `moved`-block migration + the #5911 `reboot_updates` destroy-guard
   halted BOTH web-platform apply pipelines at the terraform-plan stage (web-1's pending
   `placement_group_id` attach forces a Hetzner power-off reboot).
2. Fixing it (**#5950**: `lifecycle { ignore_changes = [placement_group_id] }` on
   `hcloud_server.web`) let the pipelines reach terraform-apply for the first time → exposed
   **#5955** — the seccomp-reload step (#5875) sent `tag=latest` to `ci-deploy.sh`, which
   requires semver (`^v[0-9]+\.[0-9]+\.[0-9]+$`) → `reason=tag_malformed`, and the rejection
   re-stamped `.tag=latest`, a self-perpetuating loop.
3. Fixing it (**#5957**: resolve the running semver from `/health`, tighten validation) let
   the redeploy succeed (`exit_code=0`) → exposed **#5960** — the redeploy's `loaded` seccomp
   sha came back empty, failing the `loaded==committed` assert.
4. Fixed by **#5963** in a parallel session (validate swap terminal + read the loaded profile
   live). Both pipelines finally green on `b62526b80`.

## Key insights

1. **"Merged" ≠ "ever ran green."** A build step / assert that ships behind an upstream wedge
   is **unverified**, no matter how many green checkmarks its own PR had. #5875's seccomp
   assert (ADR-079) merged clean but had never executed once — the reboot wedge sat in front
   of it. When you clear a long-standing wedge, treat every downstream step as first-run code.
2. **Verify each fix by running the actual pipeline — do not trust the diff.** The read-only
   prod `terraform plan` (`31 add, 2 change` → **`31 add, 1 change, 0 destroy`**, run against
   live state via `doppler … prd_terraform` + raw `AWS_*` for the R2 backend) proved the
   zero-reboot invariant of the `ignore_changes` fix *before* merge. Post-merge, when the fix
   PR only touched files outside the workflow's `on.push.paths` filter (the workflow YAML +
   an ADR), the pipeline did **not** auto-trigger — dispatch it: `gh workflow run <wf> --ref
   main -f reason="…"` (note: this workflow *required* a `reason` input; a bare dispatch 422s).
3. **Each newly-surfaced defect is a DIFFERENT subsystem → its own issue, never folded into
   the unrelated PR.** #5955 (tag contract) and #5960 (profile-load observability) were filed
   separately with full diagnoses, not bundled into the #5950 reboot-deferral branch. Scope
   discipline keeps a possible-P1 from being buried.
4. **Know when the wall is host-visibility, and stop drilling.** #5960 required knowing the
   state of a file on the prod host (`/etc/docker/seccomp-profiles/soleur-bwrap.json`) that
   CI does not expose and this repo has no SSH runbook to reach. The right move was to file it
   with the 3 candidate root causes + the honest "prod posture is *unverified*, not
   confirmed-broken" framing — not to guess-and-drill a 4th layer blind. (The parallel session
   with host access closed it.)
5. **Route the fix DECISION, not just the diagnosis.** #5955's fix had 3 viable approaches
   with real trade-offs (resolve-from-`/health` vs. relax the semver guard vs. digest-redeploy)
   — a deploy-subsystem tag-contract call. That is an architectural fork → routed to the `cto`
   agent (per the work-skill HARD GATE), which ruled A/a1 and preserved the security guard;
   captured as an ADR-079 amendment. Implement the ruling, don't freelance the subsystem.

## The generalizable rule

When you clear a **masking** failure (a wedge, a short-circuit, a gate that aborts early),
assume it was hiding a queue of downstream defects that never executed. Budget for a *chain*,
not a *fix*: verify each link by running the real surface, file each newly-exposed defect in
its own subsystem's issue, route genuine design forks to the owner (CTO/ADR), and when a link
needs observability you don't have, add the observability (or hand off) rather than guessing.

## Session Errors

- **Auto-close-prose trap — hit TWICE (#5887, #5955).** Both issues auto-closed *prematurely*
  by GitHub's word-boundary close-keyword parser firing on prose in the squash-commit / PR
  body ("the sweeper **closes #5887**", "I'll **close #5955** after the pipeline confirms
  green"). The closures were substantively correct but fired before the verifying pipeline ran.
  **Recovery:** re-verified independently and left clarifying comments. **Prevention:** write
  close-behavior prose as **"auto-resolves issue #N"** (no bare `close/closes/fixes/resolves`
  + `#N` adjacency). **Workflow gap (the real finding):** the existing learning
  `2026-06-29-auto-closes-meta-content-in-commit-body-trips-github-autoclose-on-hand-rolled-merge.md`
  documents this AND `/ship` Phase 6 runs `auto-close-scan.sh` — but I **hand-rolled**
  `gh pr merge --squash --auto` both times, bypassing `/ship` where that scan lives. A
  hand-rolled / auto-merge path has **no** equivalent check. **Proposed enforcement:** a
  PreToolUse hook on `gh pr merge` that runs `auto-close-scan.sh` over the branch's commit
  bodies (mirroring how `pre-merge-rebase.sh` already intercepts `gh pr merge`), so the guard
  is merge-path-independent rather than `/ship`-only.
- **Worktree pruned mid-write.** Concurrent session churn reaped the `feat-multi-host-blue-green-ingress`
  worktree while I was still building it; `plan.md`/`tasks.md` survived as orphaned untracked
  files. **Recovery:** `mv` the orphan dir aside (guardrail blocks `rm -rf` on worktree paths),
  recreate the worktree, copy files back. **Prevention:** acquire the session lease
  (`session-state.sh acquire_lease`) **at worktree-create time**, not after the first edits —
  I acquired it late, leaving a window for a sibling `cleanup-merged` to reap it.
- **Combined a needed op with a blockable op in one bash call.** A `cp` backup and an
  `rm -rf <worktree>` were in the same command; the guardrail rejected the whole call
  pre-execution, so the `cp` never ran. **Prevention:** never pair a load-bearing step with a
  step that might be denied — run backups/reads as their own call first.
- **`sed` range over-deletion.** A `sed '/start/,/end/d'` whose end-pattern didn't match the
  actual line deleted from the anchor to EOF, wiping a draft. **Recovery:** restored from
  scratchpad. **Prevention:** for bounded deletions prefer an explicit Edit of the known block,
  or verify the end anchor matches (`grep -n`) before running a range `sed`.
- **`gh workflow run` missing a required input** (422) and **`gh pr view` combined `--jq`
  empty on a null field** — one-offs; pass `-f reason=…`, and split `--jq` per field when one
  may be null.

## Related

- `knowledge-base/project/plans/2026-07-03-feat-multi-host-blue-green-ingress-prereqs-plan.md` (the prereqs plan; deferred GA remainder)
- ADR-068 §Amendment (2026-07-03, #5887 blue-green ingress) + ADR-079 §Amendment (#5955 tag resolution)
- `2026-07-02-zero-downtime-first-moved-block-statemv-and-blue-green-cutover.md` (the zero-downtime framing this session applied)
- `2026-06-29-auto-closes-meta-content-in-commit-body-trips-github-autoclose-on-hand-rolled-merge.md` (the auto-close trap; this session is a recurrence + a proposed merge-path-independent guard)
