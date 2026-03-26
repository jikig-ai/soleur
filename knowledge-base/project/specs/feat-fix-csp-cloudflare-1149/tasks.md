# Tasks: fix CSP Cloudflare challenge script blocked

## Phase 1: Documentation

- [ ] 1.1 Read `plugins/soleur/docs/_includes/base.njk` to verify current CSP meta tag location
- [ ] 1.2 Add HTML comment above CSP meta tag in `base.njk` documenting the known Cloudflare Bot Fight Mode console error and referencing #1149
- [ ] 1.3 Verify `validate-csp.sh` still passes after the comment addition (comment is not inside the meta tag, so no hash change expected)

## Phase 2: Verification

- [ ] 2.1 Run `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site` to confirm CSP validation passes (requires Eleventy build first)
- [ ] 2.2 Verify no changes to CSP directives or hashes in the meta tag

## Phase 3: Issue Closure

- [ ] 3.1 Close #1149 with a comment explaining the "accept as known limitation" decision and linking to this plan
