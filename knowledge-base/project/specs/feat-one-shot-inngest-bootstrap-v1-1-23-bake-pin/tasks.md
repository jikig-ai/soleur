# Tasks — inngest-bootstrap v1.1.23 rebake + OCI pin bump

Plan: `knowledge-base/project/plans/2026-07-18-fix-inngest-bootstrap-v1-1-23-bake-pin-plan.md`
Lane: cross-domain · Threshold: single-user incident (requires_cpo_signoff) · Umbrella: Ref #6178

## Phase 1 — Rebake (tag push + build verification, in-session)

- [ ] 1.1 `git fetch origin`; assert `git merge-base --is-ancestor 119861998 origin/main` exits 0.
- [ ] 1.2 Create annotated tag `vinngest-v1.1.23` on `origin/main` HEAD (never the feature branch);
      `git push origin vinngest-v1.1.23`.
- [ ] 1.3 Watch `build-inngest-bootstrap-image.yml` for the tag; wait for conclusion `success`
      (`gh run watch` / `gh run view --json conclusion`).
- [ ] 1.4 Verify pullable: `docker manifest inspect ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.23`
      exits 0 (or GHCR package-versions lists `v1.1.23`). [AC1–AC3]

## Phase 2 — Pin bump (feature branch)

- [ ] 2.1 `git grep -n 'soleur-inngest-bootstrap:v1.1.22'` → confirm the 3 sites
      (cloud-init-inngest.yml, cloud-init.yml ×2). Re-verify line numbers.
- [ ] 2.2 Edit `apps/web-platform/infra/cloud-init-inngest.yml` IREF `v1.1.22 → v1.1.23`.
- [ ] 2.3 Edit `apps/web-platform/infra/cloud-init.yml` IREF + ZIREF `v1.1.22 → v1.1.23`.
- [ ] 2.4 Assert `git grep -c 'soleur-inngest-bootstrap:v1.1.22'` == 0 and `…:v1.1.23` == 3. [AC4]
- [ ] 2.5 Confirm NO edits to `ci-deploy.test.sh` or `zot-soak-6122.test.sh` (synthetic fixtures). [AC7]

## Phase 3 — Verify (CI-green)

- [ ] 3.1 `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` green (AC6 both files
      vs `LATEST_TAG=v1.1.23`; AC6b count==2/distinct==1). [AC5, AC6]
- [ ] 3.2 Run the infra `.test.sh` validation suite; confirm green. [AC7]

## Phase 4 — Ship

- [ ] 4.1 PR body: `Ref #6178` (NOT `Closes`); explain bake-gap + corrected bootstrap.sh/vector.toml
      provenance + latent-until-force-replace. [AC8]
- [ ] 4.2 Merge promptly after build-success + pullable (keeps the drift guard green for main). [AC8]

## Out of scope (do not touch)

terraform apply / inngest-host-replace / force-replace · op=arm / op=flip / cutover FSM ·
INNGEST_BASE_URL repoint · Doppler prod writes · any `.tf` edit · closing any issue.
