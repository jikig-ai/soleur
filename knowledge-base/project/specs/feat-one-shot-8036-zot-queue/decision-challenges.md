# Decision challenges — feat-one-shot-8036-zot-queue

These were recorded headless at plan time (plan Step 4.5 and plan-review). None was auto-applied
where it would change the operator's stated direction.

## UC-1 — Split the queue into two PRs (CTO, plan-time domain review)

- **Your stated direction:** one branch drains the whole zot queue, as four items plus a sweep,
  in one PR (#8456).
- **The challenge:** merging this one PR fires three production deliveries:
  - the `deploy_pipeline_fix` auto-apply of `ci-deploy.sh`
  - a registry **host replace**, via `registry-host-replace-dispatch.yml`
  - a Better Stack alert apply

  A revert of any one part therefore re-fires the others. Most notably, reverting `ci-deploy.sh`
  would trigger a second registry host replace.
- **Proposed split:**
  - PR-A: 1a, 1b, the ADR-087 amendment, C4, UC2, and the alert.
  - PR-B: the three `cloud-init-registry.yml` phases (#8417, #8408 b and c).
- **What was applied instead:** one PR with ordered, independently revertable commits, plus an
  alert grace (fires on ≥2 rows per 15 min), so the planned replace window cannot page.
- **If you disagree, the cost is small** at this stage. The plan's phases already split cleanly
  along that boundary.

## Taste-1 — 1b marker carries no identity field (DHH + code-simplicity)

The #8036 diagnosis asked the marker to name "the identity it carries". The plan emits only
closed-vocabulary tokens. Those are presence, creds store, helper, and readability, for each of
three config paths. The plan dropped even a `same|differs` comparison against
`GHCR_READ_USER`, for three reasons:

- it decodes a live credential in shell on the deploy path
- journald → Better Stack is unscrubbed
- neither answer changes 1a (which is correct under every hypothesis) or the 1c recommendation

If you want the comparison back, it is a single additional `case` token.

## Taste-2 — keep one new C4 edge instead of a new C4 node (DHH + code-simplicity vs the C4 completeness mandate)

The web hosts' anonymous per-deploy pull of the cosign verifier image from public ghcr.io was
unmodelled. The plan models it as a **second `hetzner -> ghcr` edge**, labelled LIVE anonymous
pull, rather than as a new external element. Reviewers preferred prose-only. The repo's C4
completeness mandate requires an unmodelled live external dependency to be modelled, and an
edge is the smallest form. The deepen review put the edge on `ghcr`, not on `sigstore`, because
the live dependency is ghcr.io's availability and its anonymous rate limit.
