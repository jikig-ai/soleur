# Tasks: Fix Duplicate GitHub Issues

**Spec:** [spec.md](./spec.md)
**Plan:** [2026-02-06-fix-duplicate-github-issues-plan.md](../../plans/2026-02-06-fix-duplicate-github-issues-plan.md)
**Issue:** #18

## Phase 1: Issue Detection Logic

### 1.1 Add issue reference parsing
- [x] 1.1.1 Add "Check for existing issue reference" step before issue creation
- [x] 1.1.2 Add bash example: extract `#N` pattern with grep
- [x] 1.1.3 Add bash example: validate with `gh issue view --json state`

### 1.2 Add state handling
- [x] 1.2.1 Handle OPEN state: use existing issue, skip creation
- [x] 1.2.2 Handle CLOSED state: warn, create new with reference
- [x] 1.2.3 Handle NOT FOUND: warn, prompt user to confirm new issue

### 1.3 Add artifact update for existing issues
- [x] 1.3.1 Add bash example: append Artifacts section to existing issue body
- [x] 1.3.2 Include brainstorm, spec, and branch links

## Phase 2: Output Updates

### 2.1 Update output summary
- [x] 2.1.1 Change "Issue: #N (if created)" to show "using existing" vs "created"
- [x] 2.1.2 Update announcement text for existing issue case

## Phase 3: Testing

### 3.1 Manual verification
- [ ] 3.1.1 Test `/soleur:brainstorm github issue #18` - uses existing, no new issue
- [ ] 3.1.2 Test `/soleur:brainstorm add new feature` - creates new issue
- [ ] 3.1.3 Test `/soleur:brainstorm issue #99999` - warns, prompts for new
- [ ] 3.1.4 Test with closed issue reference - warns, creates new with link

## Phase 4: Finalize

### 4.1 Plugin versioning
- [x] 4.1.1 Bump version in `.claude-plugin/plugin.json` (patch)
- [x] 4.1.2 Update CHANGELOG.md
- [x] 4.1.3 Verify README.md counts
