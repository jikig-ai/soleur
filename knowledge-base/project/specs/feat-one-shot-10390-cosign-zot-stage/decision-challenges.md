# Decision Challenges — feat-one-shot-10390-cosign-zot-stage

Recorded during `soleur:plan` on 2026-10-21 (headless pipeline; no Task/Agent
tool in this harness, so technical forks are recorded `pending - assumed:` per
the technical-ruling-delegation rule — a CTO spawn should confirm before or at
`soleur:work`).

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Host-side fix mechanism — brief option A (provision pull + `docker tag` to gcr ref) vs option B (`REFRESH_COSIGN_IMAGE` env override) vs repoint default + explicit tick pull | technical | pending - assumed: repoint `COSIGN_IMAGE` default to `${ZOT_EP}/jikig-ai/cosign@sha256:57c0e93a…` (resolved after `ZOT_EP`) + explicit `docker pull "$COSIGN_IMAGE"` before `docker run` (`verify_fail pull "" "member=cosign-image"`). Option A is unimplementable (`docker tag` rejects digest refs; RepoDigests only arise from pulls through that ref — a tag can never satisfy `docker run gcr.io/…@sha256:D`); option B is inert in prod (the #7761 seam gate unsets `REFRESH_*` absent `--fixture-seams`). The assumed shape is the only mechanism that satisfies the intent. |
| Mirror dst form — `…/jikig-ai/cosign@sha256:57c0e93a…` (digest ref, brief literal) vs `…/jikig-ai/cosign:v3.1.1` (tag) | technical | pending - assumed: `:v3.1.1` tag dst + `crane digest` equality check against the pinned gcr digest. The host pulls by digest regardless (zot serves any stored manifest by digest); the tag form matches the step's own `:v${VERSION}` convention and enables a run-time digest-preservation check the digest form cannot express. |
| Post-merge pointer — keep v2 vs promote v3 | operator (production-mutating authorization) | Recommended keep-v2 (fewer prod writes; pointer already promoted; host applies v2 once the verifier resolves). Either reaches APPLIED. Operator decides at the dispatch window. |
| Brand-survival threshold — none vs single-user incident | taste | single-user incident — the surface is the sole scheduler's provenance channel; a boot-bricking cloud-init defect darkens the automation backbone for the only user. `requires_cpo_signoff: true` set in the plan frontmatter. |
| Provision-time pre-pull (stage at boot vs first tick) | technical | pending - assumed: cut — the tick's explicit pull stages at first use with correct reason granularity; a second pull site doubles the pinned surface for ≤60 s earlier signal. Reversible follow-up. |

## Not Yet Specified candidates

None.
