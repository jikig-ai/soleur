---
date: 2026-05-31
topic: inngest-bootstrap workflow_dispatch tag invariant
issue: 4692
branch: feat-inngest-dispatch-tag-invariant
pr: 4693
lane: cross-domain
brand_survival_threshold: single-user incident
status: decided
---

# Brainstorm: Close the `workflow_dispatch` tag blind-spot in `build-inngest-bootstrap-image.yml`

## What We're Building

A **workflow invariant** guaranteeing that every published `soleur-inngest-bootstrap`
OCI image corresponds to a `vinngest-v*` git tag — so the consumption-side drift-guard
(AC6 in `cloud-init-inngest-bootstrap.test.sh`, shipped by PR #4676 / closes #4675) can
never go blind.

Today `build-inngest-bootstrap-image.yml` has two publish paths:

- `on: push: tags: ['vinngest-v*.*.*']` — tag push builds + pushes the image.
- `workflow_dispatch` (free-form `inputs.tag`) — runs `docker push` but mints **no** git tag.

AC6 trusts the **semver-max `vinngest-v*` tag** as the authoritative "a new image was
published" signal and compares it to the cloud-init pin. A tagless `workflow_dispatch`
publish is therefore invisible to the guard — it stays green while prod may run a divergent
bootstrap. This already fired: `v1.1.11` was published via two `workflow_dispatch` runs on
main (2026-05-30, both `sha=d844b41d`) with no tag, forcing a retroactive
`vinngest-v1.1.11` annotated-tag backfill to make the guard green.

## Why This Approach (Option 3: tag-driven dispatch + post-push assertion)

The issue framed a binary: **(1) auto-tag on dispatch** (priv bump) vs **(2) drop dispatch**
(lose flexibility). The CTO surfaced a third option that dominates both, and CPO + CLO
independently leaned away from approach 1's privilege bump.

The guard's real contract is **"every published image SHA is reachable from a `vinngest-v*`
tag."** Option 3 *enforces that contract* instead of recreating it:

1. **Tag-driven dispatch.** Change `workflow_dispatch` input from free-form `inputs.tag`
   to `inputs.ref` — an *existing* `vinngest-v*` tag. Checkout that ref; derive the image
   tag by stripping the `vinngest-` prefix, identical to the push path. Dispatch can then
   only re-publish a version that **already has a tag** — it physically cannot mint a tagless
   image. The escape hatch (re-publish / CVE base-image rebuild of an existing vX.Y.Z)
   survives.
2. **Post-push assertion (belt-and-suspenders).** After `docker push`, fail the run unless
   `git tag --points-at HEAD` contains `vinngest-$TAG`. Converts operator discipline into a
   red CI run.

Both moves keep `permissions: contents: read` — no `contents: write` privilege bump.

### Why not 1 or 2

- **Approach 1 (auto-tag):** Needs `contents: write`. A workflow with push-tag perms *plus*
  a `docker build` from a `mktemp` Dockerfile is a tag-forging primitive if any step is ever
  compromised (security-sentinel flagged token scope on the parent PR). Its only safe
  idempotency story (tag-exists → skip) still silently permits a version-without-tag publish
  — a weaker invariant than Option 3, which makes the tag a *precondition*.
- **Approach 2 (drop dispatch):** Durable by construction and keeps `contents: read`, but
  deletes the legitimate on-demand rebuild path. (Recoverable via `git tag -f … && git push -f`,
  which re-fires `on: push: tags` — but that force-push dance is noisier than Option 3's
  clean ref-driven rebuild.)

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Approach | Option 3: tag-driven dispatch + post-push assertion | Dominates 1 & 2: keeps `contents: read`, keeps escape hatch, makes tag a publish precondition |
| Token scope | `permissions: contents: read` unchanged | No tag-forging primitive; strongest least-privilege/provenance posture (CLO note) |
| Dispatch input | `inputs.ref` (existing `vinngest-v*` tag), replacing free-form `inputs.tag` | Physically prevents tagless publish |
| Input validation | `^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$` | Dispatch can only check out an existing release tag, never an arbitrary branch/SHA |
| Assertion | Post-`docker push`: `git tag --points-at HEAD` must contain `vinngest-$TAG`, else fail | Belt-and-suspenders; red CI on any future divergence |
| Tag reachability | Dispatch checkout needs `fetch-tags: true` (or `fetch-depth: 0`) | So the post-push assertion can see the tag locally |
| ADR | Record publish-invariant + token-scope decision | CTO flagged this as architecture-worthy |

## Open Questions

- **Concurrency:** A dispatch on an existing tag while a push of the same tag is in flight —
  both publish the same image:tag idempotently; the assertion holds for both. No `contents`
  mutation, so no tag race (unlike approach 1). Confirm no GHCR immutable-tag rejection on
  re-push of an existing image tag (current behavior already allows it).
- **ADR scope:** One ADR for "inngest-bootstrap publish invariant via tag-driven dispatch", or
  fold into the existing #4675/#4676 drift-guard record? (Lean: new short ADR — the token-scope
  decision is the durable part.)

## User-Brand Impact

- **Artifact:** `soleur-inngest-bootstrap` OCI image / the cloud-init `soleur-inngest-bootstrap:<tag>` pin.
- **Vector:** A tagless `workflow_dispatch` publish leaves AC6 green while prod runs a divergent
  bootstrap image. Inngest runs background jobs that perform user work, so a divergent bootstrap
  can silently degrade or stall those jobs with no alert.
- **Threshold:** `single-user incident`. Option 3 strictly *reduces* this exposure — it closes
  the tagless-publish vector without the `contents: write` privilege bump that approach 1 would
  add. Plan derived from this brainstorm inherits `Brand-survival threshold: single-user incident`.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO)

### Engineering (CTO)

**Summary:** Recommends Option 3 (tag-driven dispatch + post-push assertion) over both issue
approaches — risk medium, complexity small. Keeps `contents: read` (avoids the tag-forging
primitive approach 1 creates), keeps the CVE-rebuild escape hatch, and makes the tag a
*precondition* of publish rather than a side-effect, strictly reducing the single-user-incident
exposure. Flagged the decision as ADR-worthy.

### Product (CPO)

**Summary:** No end-user product surface — pure CI/infra plumbing. On operator ergonomics, the
capability approach 2 removes is "the one causing the bug"; net operator-experience impact of
tightening the publish path is positive. Defers the final technical choice to the CTO.

### Legal (CLO)

**Summary:** No PII / user-data / third-party-processing surface; no GDPR/DPA angle. One
governance note: granting the workflow `contents: write` (approach 1) broadens token scope
(SLSA provenance / least-privilege) — if taken, scope it at the *job* level, not workflow level.
Option 3 / approach 2 keep `contents: read`, the stronger provenance posture.
