---
issue: 4692
branch: feat-inngest-dispatch-tag-invariant
pr: 4693
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: ../../brainstorms/2026-05-31-inngest-dispatch-tag-invariant-brainstorm.md
---

# Spec: inngest-bootstrap `workflow_dispatch` tag invariant

**Issue:** #4692
**Branch:** feat-inngest-dispatch-tag-invariant
**Brainstorm:** [2026-05-31-inngest-dispatch-tag-invariant-brainstorm.md](../../brainstorms/2026-05-31-inngest-dispatch-tag-invariant-brainstorm.md)

## Problem Statement

`.github/workflows/build-inngest-bootstrap-image.yml` has two publish paths. The
`on: push: tags: ['vinngest-v*.*.*']` path mints a git tag; the `workflow_dispatch`
(free-form `inputs.tag`) path runs `docker push` with **no** tag. PR #4676's consumption-side
drift-guard (AC6 in `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, lines
169–202) trusts the semver-max `vinngest-v*` git tag as the authoritative "image published"
signal. A tagless `workflow_dispatch` publish is therefore invisible to the guard — it stays
green while prod may run a divergent bootstrap image. This fired on 2026-05-30: `v1.1.11`
published via two `workflow_dispatch` runs with no tag, forcing a retroactive tag backfill.

## Goals

- G1: Make "every published image corresponds to a `vinngest-v*` tag" a **workflow invariant**, not operator discipline.
- G2: Preserve the on-demand publish escape hatch (re-publish / CVE base-image rebuild of an already-tagged version).
- G3: Keep `permissions: contents: read` — no `contents: write` privilege bump.
- G4: Make any future divergence a **red CI run**, not a silent drift.

## Non-Goals

- NG1: Changing the AC6 consumption-side drift-guard itself (PR #4676 — it is the correct backstop).
- NG2: Changing the embedded `inngest_cli_version` / pin-bump mechanics (separate subsystem).
- NG3: Adding auto-tag-creation (rejected: requires `contents: write` tag-forging primitive).
- NG4: Dropping the `workflow_dispatch` path entirely (rejected: deletes the legitimate rebuild path).
- NG5: GHCR image-tag immutability/retention policy (out of scope).

## Functional Requirements

- FR1: `workflow_dispatch` input changes from free-form `inputs.tag` (a version string) to `inputs.ref` — the name of an **existing** `vinngest-v*` tag.
- FR2: The dispatch path checks out `inputs.ref` and derives the image tag by stripping the `vinngest-` prefix, identical to the push path's `Resolve image tag` step.
- FR3: `inputs.ref` is validated against `^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$` before any checkout/publish; a non-matching value fails the run (cannot check out an arbitrary branch/SHA).
- FR4: After `docker push`, a post-publish assertion fails the run unless `git tag --points-at HEAD` contains `vinngest-$TAG`.
- FR5: The push-tag path (`on: push: tags`) behavior is unchanged.

## Technical Requirements

- TR1: `permissions:` remains `contents: read` + `packages: write` (no elevation at workflow or job level).
- TR2: The dispatch checkout must fetch tags (`fetch-tags: true`, or `fetch-depth: 0`) so the FR4 assertion can resolve the tag locally.
- TR3: Reuse the existing workflow-injection hardening — untrusted inputs flow through env vars, never inlined into shell.
- TR4: The post-push assertion must be deterministic in CI (no dependency on a tag fetched only by the push trigger).
- TR5: Record an ADR for the publish-invariant + token-scope decision (per CTO; use `/soleur:architecture`).

## Acceptance Criteria

- AC1: A `workflow_dispatch` run with `ref=vinngest-v1.1.11` republishes `soleur-inngest-bootstrap:v1.1.11` and passes the FR4 assertion.
- AC2: A `workflow_dispatch` run with a free-form/non-tag `ref` (e.g. `main`, `v9.9.9`, a SHA) fails at FR3 validation before any publish.
- AC3: After the change, no `workflow_dispatch` run can publish an image whose version lacks a `vinngest-v*` tag.
- AC4: `cloud-init-inngest-bootstrap.test.sh` AC6 continues to pass; the guard's "latest tag == pin" invariant now cannot be blinded by the dispatch path.
- AC5: `permissions: contents: read` verified unchanged in the final workflow.

## User-Brand Impact

- **Artifact:** `soleur-inngest-bootstrap` OCI image / the cloud-init `soleur-inngest-bootstrap:<tag>` pin.
- **Vector:** tagless `workflow_dispatch` publish → AC6 stays green → prod runs a divergent bootstrap → inngest background jobs (user work) silently degrade.
- **Threshold:** `single-user incident`. This change strictly reduces the exposure (closes the tagless-publish vector without a privilege bump).
