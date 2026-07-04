---
lane: cross-domain
issue: 5933
umbrella_plan: knowledge-base/project/plans/2026-07-03-feat-web2-absence-detector-image-pin-plan.md
---

# Tasks: Image signing + running-host verify (#5933 Item 4, PR 2/2)

- [x] 1. `reusable-release.yml`: `id-token: write` + pinned `sigstore/cosign-installer` + `cosign sign --yes …@${digest}`.
- [x] 2. `ci-deploy.sh`: `COSIGN_*` constants, `cosign_verify_event`, `verify_image_signature` (WARN/ENFORCE), call after app pull, thread verified digest to plugin-seed/canary/production.
- [x] 3. `ci-deploy.test.sh`: `inspect RepoDigests` + cosign-`verify` mock handlers; WARN-does-not-block (verify + inspect) + ENFORCE-blocks tests (103/103).
- [x] 4. `sigstore` system + sign/verify edges in `model.c4`/`views.c4`; `model.likec4.json` regenerated; c4 suite green (incl. freshness).
- [x] 5. ADR-082 Item 4 amendment (dual-path + rejected alternatives).
- [ ] 6. Review + ship (WARN).
- [ ] 7. Post-merge: confirm a signed release exists + WARN clean → ENFORCE fast-follow (flip `IMAGE_VERIFY_MODE` default warn→enforce).
