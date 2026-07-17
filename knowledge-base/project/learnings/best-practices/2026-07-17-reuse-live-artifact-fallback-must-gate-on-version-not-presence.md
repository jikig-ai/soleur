---
title: "A 'reuse the live artifact when the fetch fails' fallback must gate on VERSION, not mere presence"
date: 2026-07-17
category: best-practices
tags: [deploy-pipeline, fallback-design, stale-bits, plan-guard-as-prose, ci-deploy, seccomp, review, test-design]
issue: 6512
pr: 6622
module: apps/web-platform/infra/ci-deploy.sh
---

## Problem

#6512 added a `local-cache` last-resort tier to `ci-deploy.sh`'s `pull_image_with_fallback`: when
BOTH registries (zot-primary, GHCR-fallback) fail to serve an image, reuse the RUNNING container's
local image instead of hard-failing `image_pull_failed`. The motivating case is the item-4 seccomp
redeploy, which by construction targets `v<running_version>` — so "reuse the running image" is
exactly right there.

The plan's guard (faithfully implemented) was: `image_kind == web` AND `TAG` is immutable semver AND
the running container's image is present locally. The plan's prose asserted this "rescues ONLY a
same-version reload … a genuine new-version deploy (never the running image ID) falls through." **But
the code never checked that TAG equals the running version.** `pull_image_with_fallback web` is the
single pull path for EVERY web deploy — including a normal new-version release. The running
container's image is ALWAYS present locally (it's what's running), so on a new-version deploy with
both registries down the tier would reuse the OLD image, and — because `ci-deploy.sh` runs no
post-deploy version assertion (health checks verify liveness, not version) — the deploy would report
the new release as `deployed` while the old version stayed live: **a silent version rollback masked
as success.**

## Root cause

"Presence of the live artifact" is not "the live artifact is the thing you were asked to deploy." A
reuse-on-fetch-failure fallback (reuse cached image / reuse last-good config / reuse the running
binary) is only safe for a SAME-VERSION reload; for a version CHANGE it serves stale bits. The plan
asserted the safety invariant in prose but encoded a weaker guard (presence) that is true in the
dangerous case too. This is the `plan-asserted-structural-guard-must-be-encoded-not-prose` class
(#4681, #5907) applied to a deploy fallback.

## Solution

Gate the reuse on the running artifact BEING the requested version, encoded as a hard invariant:

```sh
# SAME-VERSION reload ONLY: the running image must itself carry a <ref>:$TAG RepoTag (it was pulled
# under that tag at its original deploy). A new-version tag is never on the older running image →
# falls through to hard image_pull_failed. Ref-agnostic suffix match; ANY ambiguity fails SAFE.
local _rt _reload_match=0
while IFS= read -r _rt; do
  [[ "$_rt" == *":$TAG" ]] && { _reload_match=1; break; }
done < <(docker image inspect --format '{{range .RepoTags}}{{println .}}{{end}}' "$running_img_id" 2>/dev/null || true)
[[ "$_reload_match" == "1" ]] || return 1
```

Key properties: (a) ref-agnostic (matches `:vX.Y.Z` regardless of zot/ghcr prefix, so the #6512
zot-served topology still rescues); (b) fails SAFE — no RepoTag / mismatch → hard `image_pull_failed`
(which the same PR's alarm then pages), never stale bits; (c) a registry-side GC (the zot 5-`v*`
keep-set that motivated the fix) does not remove the host-LOCAL docker RepoTag, so the invariant
survives the exact prune it protects against.

## Key Insight

When you add a "the fetch failed, reuse what's already live" fallback, the safety question is never
"is something live?" (always yes) — it is "is the live thing the SAME VERSION as what was
requested?" Encode that as a hard gate that fails safe. And a system with no post-deploy version
assertion cannot lean on a downstream check to catch the mismatch — the fallback's own gate is the
only line of defense.

## Session Errors

- **#6512 was auto-closed in error** by PR #6521, whose body read "Does **not** close #6512" — GitHub's
  word-boundary close-keyword parser matched `close #6512` and closed it a second after #6521 merged.
  **Recovery:** verified the close (closedAt == #6521 mergedAt; #6521 touched one markdown file and
  disclaimed closing it), reopened with an explanation. **Prevention:** already documented in
  `2026-06-29-auto-closes-meta-content-in-commit-body-trips-github-autoclose-on-hand-rolled-merge.md`
  — write close-behavior prose without the bare `<keyword> #N` adjacency ("auto-resolves issue #N").
  Recurred here despite the learning; from a routing perspective the mitigation is to verify a
  `#N` "closed" status before routing (which `/go` did — it caught the erroneous close and reopened).
- **Latent stale-bits guard (the subject of this learning)** — the plan's presence-only guard shipped
  through 5-signal plan review + deepen; caught at post-implementation review by tracing "does
  ci-deploy assert the deployed version anywhere?" (it does not). **Prevention:** for any reuse-on-
  failure fallback, enumerate "what distinguishes a same-version reload from a new-version deploy?"
  and encode it; add a regression test for the new-version case.
- **Vacuous negative-space test (c2)** — the "non-web deploy doesn't fire the tier" case deployed a
  non-allowlisted inngest ref (`…/soleur-inngest`, not `…/soleur-inngest-bootstrap`), so the run
  exited at `image_mismatch` validation BEFORE reaching the tier — passing for the wrong reason
  (deleting the web-guard left it GREEN). **Recovery:** used the allowlisted ref + a
  `reason==image_pull_failed` positive control proving the run reached the pull. **Prevention:** every
  negative-space "guard X gates this out" test needs a positive control that the run reached the gate
  under test (the early-exit-shadowing class, here in bash).
- **Sentry alert frequency collision on rebase** — my `frequency = 25` collided with a sibling PR's
  (#6610 `workspaces_luks_drift`) that landed on main mid-session. **Recovery:** renumbered to 26/27
  during rebase conflict resolution + updated the "taken" comments. **Prevention:** the freq-dedup
  comment convention + rebase-before-ship already cover this; the collision window extends through the
  whole session, so re-check any file-appended unique-value convention after a mid-session rebase.
- **Alert script lacked idempotent label bootstrap** — `gh issue create --label ci/seccomp-unenforced`
  hard-fails on an unknown label, and the call is fail-open, so a missing label would silently drop
  the PRIMARY operator surface (the GitHub issue) to an invisible CI warning. **Recovery:** added
  `gh label create … 2>/dev/null || true` before create, matching the `scheduled-inngest-health.yml`
  precedent. **Prevention:** an issue-filing automation script must self-bootstrap its labels.
- **Slow `ci-deploy.test.sh` (~130–400s) + monitor timeouts** — environmental friction; required
  multiple background runs. One-off; no action.
