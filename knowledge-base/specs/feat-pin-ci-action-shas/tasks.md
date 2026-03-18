# Tasks: fix(ci): pin action tags to SHA in build-web-platform.yml

## Phase 1: Implementation

- [ ] 1.1 Edit `.github/workflows/build-web-platform.yml` line 33: replace `actions/checkout@v4` with `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`
- [ ] 1.2 Edit `.github/workflows/build-web-platform.yml` line 36: replace `docker/login-action@v3` with `docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9 # v3.7.0`
- [ ] 1.3 Edit `.github/workflows/build-web-platform.yml` line 46: replace `docker/build-push-action@v6` with `docker/build-push-action@10e90e3645eae34f1e60eeb005ba3a3d33f178e8 # v6.19.2`
- [ ] 1.4 Edit `.github/workflows/build-web-platform.yml` line 66: replace `appleboy/ssh-action@v1` with `appleboy/ssh-action@0ff4204d59e8e51228ff73bce53f80d53301dee2 # v1.2.5`

## Phase 2: Validation

- [ ] 2.1 Verify all `uses:` lines contain 40-char hex SHAs with `# vX.Y.Z` trailing comments
- [ ] 2.2 Verify `actions/checkout` SHA matches `ci.yml` (`34e114876b0b11c390a56381ad16ebd13914f8d5`)
- [ ] 2.3 Verify no other changes to the workflow file (triggers, env, secrets, step logic unchanged)
- [ ] 2.4 Validate YAML syntax

## Phase 3: Ship

- [ ] 3.1 Run compound
- [ ] 3.2 Commit with message `fix(ci): pin action tags to SHA in build-web-platform.yml`
- [ ] 3.3 Push and create PR (closes #716, label: `semver:patch`)
