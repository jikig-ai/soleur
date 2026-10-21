# Decision Challenges — feat-one-shot-10390-cosign-zot-stage

Recorded during `soleur:plan` on 2026-10-21 (headless pipeline; no Task/Agent
tool in this harness, so technical forks are recorded `pending - assumed:` per
the technical-ruling-delegation rule — a CTO spawn should confirm before or at
`soleur:work`).

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Host-side fix mechanism — brief option A (provision pull + `docker tag` to gcr ref) vs option B (`REFRESH_COSIGN_IMAGE` env override) vs repoint default + explicit tick pull | technical | Ruled by CTO agent, 2026-10-21: repoint `COSIGN_IMAGE` default to `${ZOT_EP}/jikig-ai/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870` + explicit `docker pull "$COSIGN_IMAGE"` in the tick (`verify_fail pull "" "member=cosign-image"`) - option A unimplementable (`docker tag` rejects digest refs; a `name@sha256:D` run-ref resolves only via pull-derived RepoDigests, never a `gcr.io/…` one); option B inert in prod (seam gate unsets `REFRESH_*` absent `--fixture-seams`, cloud-init-inngest.yml:1821-1838); (c) fits `ZOT_EP`/`BREF`/bounded-pull/`verify_fail` structure at :2003-2070 and repairs the `reason=signature` misattribution. Dissent: diverges inngest host's verifier ref from web hosts' gcr ref (ADR-096) — parity pin moves to the shared digest; spends ~2 of ~680 B user_data headroom. |
| Mirror dst form — `…/jikig-ai/cosign@sha256:57c0e93a…` (digest ref, brief literal) vs `…/jikig-ai/cosign:v3.1.1` (tag) | technical | Ruled by CTO agent, 2026-10-21: tag dst `127.0.0.1:5000/jikig-ai/cosign:v3.1.1` + `crane digest` equality check vs the pinned gcr digest - matches the step's push-to-tag/pull-by-digest split (`ZOT_DST` at build-inngest-config-bundle.yml:157; host pulls `@sha256` at cloud-init-inngest.yml:2009); `crane digest` on a tag dst returns the *stored* digest (verified, not asserted) while a digest-form dst degenerates the check to identity; matches `:v${VERSION}` convention. Dissent: tag adds one mutable zot object — bounded (host pulls digest only); convention dependency that nothing consumes `jikig-ai/cosign:v*` tag-form, worth a comment line. |
| Post-merge pointer — keep v2 vs promote v3 | operator (production-mutating) | ACTION: approve/promote a bundle digest after merge. Recommended keep-v2 (fewer prod writes; pointer already promoted; host applies v2 once the verifier resolves). Either reaches APPLIED. Operator decides at the dispatch window. |
| Brand-survival threshold — none vs single-user incident | taste | single-user incident — the surface is the sole scheduler's provenance channel; a boot-bricking cloud-init defect darkens the automation backbone for the only user. `requires_cpo_signoff: true` set in the plan frontmatter. |
| Provision-time pre-pull (stage at boot vs first tick) | technical | Ruled by CTO agent, 2026-10-21: cut — the tick's explicit pull stages at first use - a second pull site duplicates the bounded-retry machinery (cloud-init-inngest.yml:1315-1356) against ~680 B user_data headroom for ≤60 s earlier signal, and cannot even fire in the replace-before-mirror ordering (mirror leg only runs inside a bundle dispatch, build-inngest-config-bundle.yml:147-149); tick failure emits distinguishable `verify_fail pull member=cosign-image` and self-heals next ~5-min tick on the fail-closed channel. Dissent: first verify lands one pull later; failure is visible in the tick stream, not boot phone-home — runbook should name it. |

## Not Yet Specified candidates

None.
