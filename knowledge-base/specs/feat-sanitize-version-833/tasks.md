# Tasks: sanitize version interpolation in deploy scripts

## Phase 1: Implementation

### 1.1 Add version format validation to web-platform-release.yml

- [ ] 1.1.1 Read `.github/workflows/web-platform-release.yml`
- [ ] 1.1.2 Add `[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::Invalid version format: $TAG"; exit 1; }` after line 54 (`TAG="v${{ needs.release.outputs.version }}"`)

### 1.2 Add version format validation to telegram-bridge-release.yml

- [ ] 1.2.1 Read `.github/workflows/telegram-bridge-release.yml`
- [ ] 1.2.2 Add `[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::Invalid version format: $TAG"; exit 1; }` after line 68 (`TAG="v${{ needs.release.outputs.version }}"`)

## Phase 2: Verification

### 2.1 Validate YAML syntax

- [ ] 2.1.1 Run `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/web-platform-release.yml'))"` to verify valid YAML
- [ ] 2.1.2 Run `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/telegram-bridge-release.yml'))"` to verify valid YAML

### 2.2 Verify no other unguarded version interpolations exist

- [ ] 2.2.1 Grep all workflow files for `needs.release.outputs.version` and confirm each occurrence is guarded

## Phase 3: Compound and Ship

### 3.1 Run compound

- [ ] 3.1.1 Run `skill: soleur:compound` before committing

### 3.2 Commit and push

- [ ] 3.2.1 Stage modified workflow files
- [ ] 3.2.2 Commit with message `fix(ci): validate version format before deploy commands`
- [ ] 3.2.3 Push to remote
